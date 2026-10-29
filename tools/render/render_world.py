#!/usr/bin/env python3
"""Offline renderer for ECHOWAKE.

This is *not* a Roblox viewport capture. It is a small z-buffer rasteriser that
consumes `tools/render/world.json`, the exact geometry the game's World/Builder
turns into parts. That means the composition, silhouettes, palette, fog and
light placement you see here are the ones the game ships - only the shading
model is approximate (flat-shaded, simplified point lights, filmic post pass).

Usage: python3 tools/render/render_world.py [--fast]
"""
from __future__ import annotations

import json
import math
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
SHOTS = ROOT / "screenshots"

FOV_DEG = 62.0


# ----------------------------------------------------------------------------
# math helpers
# ----------------------------------------------------------------------------

def hex_to_rgb(value: str) -> np.ndarray:
    v = value.lstrip("#")
    return np.array([int(v[i : i + 2], 16) / 255.0 for i in (0, 2, 4)], dtype=np.float32)


def rot_x(deg: float) -> np.ndarray:
    r = math.radians(deg)
    c, s = math.cos(r), math.sin(r)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]], dtype=np.float32)


def rot_y(deg: float) -> np.ndarray:
    r = math.radians(deg)
    c, s = math.cos(r), math.sin(r)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]], dtype=np.float32)


def rot_z(deg: float) -> np.ndarray:
    r = math.radians(deg)
    c, s = math.cos(r), math.sin(r)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]], dtype=np.float32)


# ----------------------------------------------------------------------------
# primitives -> triangles (local space, then transformed)
# ----------------------------------------------------------------------------

BOX_FACES = (
    (0, 1, 2), (0, 2, 3),      # -Z
    (4, 6, 5), (4, 7, 6),      # +Z
    (0, 4, 5), (0, 5, 1),      # -Y
    (3, 2, 6), (3, 6, 7),      # +Y
    (0, 3, 7), (0, 7, 4),      # -X
    (1, 5, 6), (1, 6, 2),      # +X
)


def box_tris(size: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    hx, hy, hz = size / 2
    verts = np.array(
        [
            [-hx, -hy, -hz], [hx, -hy, -hz], [hx, hy, -hz], [-hx, hy, -hz],
            [-hx, -hy, hz], [hx, -hy, hz], [hx, hy, hz], [-hx, hy, hz],
        ],
        dtype=np.float32,
    )
    return verts, np.array(BOX_FACES, dtype=np.int32)


def prism_tris(size: np.ndarray, sides: int, axis: str = "x") -> tuple[np.ndarray, np.ndarray]:
    """Roblox Part Cylinder has its axis on local X."""
    half_len = size[0] / 2
    radius_y = size[1] / 2
    radius_z = size[2] / 2
    verts = []
    for ring in (-half_len, half_len):
        for i in range(sides):
            a = 2 * math.pi * i / sides
            verts.append([ring, math.cos(a) * radius_y, math.sin(a) * radius_z])
    verts = np.array(verts, dtype=np.float32)
    faces = []
    for i in range(sides):
        j = (i + 1) % sides
        faces.append((i, j, sides + j))
        faces.append((i, sides + j, sides + i))
    for i in range(1, sides - 1):
        faces.append((0, i, i + 1))
        faces.append((sides, sides + i + 1, sides + i))
    return verts, np.array(faces, dtype=np.int32)


def sphere_tris(size: np.ndarray, segments: int, rings: int) -> tuple[np.ndarray, np.ndarray]:
    rx, ry, rz = size / 2
    verts = [[0.0, -ry, 0.0]]
    for r in range(1, rings):
        phi = math.pi * r / rings
        for s in range(segments):
            theta = 2 * math.pi * s / segments
            verts.append(
                [
                    rx * math.sin(phi) * math.cos(theta),
                    -ry * math.cos(phi),
                    rz * math.sin(phi) * math.sin(theta),
                ]
            )
    verts.append([0.0, ry, 0.0])
    verts = np.array(verts, dtype=np.float32)
    top = len(verts) - 1
    faces = []
    for s in range(segments):
        faces.append((0, 1 + (s + 1) % segments, 1 + s))
    for r in range(rings - 2):
        base = 1 + r * segments
        nxt = base + segments
        for s in range(segments):
            s2 = (s + 1) % segments
            faces.append((base + s, base + s2, nxt + s2))
            faces.append((base + s, nxt + s2, nxt + s))
    last = 1 + (rings - 2) * segments
    for s in range(segments):
        faces.append((top, last + s, last + (s + 1) % segments))
    return verts, np.array(faces, dtype=np.int32)


@dataclass
class Tri:
    v: np.ndarray      # (3,3) world-space vertices
    color: np.ndarray  # (3,) linear-ish rgb
    emissive: float
    alpha: float


def ring_specs(centre, radius, segments, color, thickness=0.6, height=2.4, alpha=0.25, emissive=1.0):
    """A ring of small emissive boxes: the same shape Lantern.pulseWave builds in game."""
    out = []
    for i in range(segments):
        a = 2 * math.pi * i / segments
        out.append(
            {
                "shape": "Block",
                "pos": {"x": centre[0] + math.cos(a) * radius, "y": centre[1], "z": centre[2] + math.sin(a) * radius},
                "size": {"x": thickness * 2.2, "y": height, "z": thickness * 2.2},
                "rot": {"x": 0, "y": math.degrees(-a), "z": 0},
                "color": color,
                "mat": "Neon",
                "alpha": alpha,
                "emissive": emissive,
                "tag": "vfx",
            }
        )
    return out


def cone_specs(origin, direction, length, spread_deg, color, count=18):
    """A spray of glowing motes approximating Lantern.flareFlash's cone."""
    out = []
    d = np.array(direction, dtype=np.float32)
    d /= np.linalg.norm(d)
    up = np.array([0, 1, 0], dtype=np.float32)
    right = np.cross(d, up)
    if np.linalg.norm(right) < 1e-4:
        right = np.array([1, 0, 0], dtype=np.float32)
    right /= np.linalg.norm(right)
    up2 = np.cross(right, d)
    rng = np.random.default_rng(11)
    for i in range(count):
        t = (i + 1) / count
        spread = math.tan(math.radians(spread_deg)) * length * t
        offset = (right * rng.uniform(-1, 1) + up2 * rng.uniform(-1, 1)) * spread * 0.55
        p = np.array(origin, dtype=np.float32) + d * length * t + offset
        size = 1.7 * (1 - 0.6 * t)
        out.append(
            {
                "shape": "Ball",
                "pos": {"x": float(p[0]), "y": float(p[1]), "z": float(p[2])},
                "size": {"x": size, "y": size, "z": size},
                "rot": {"x": 0, "y": 0, "z": 0},
                "color": color,
                "mat": "Neon",
                "alpha": 0.35 + 0.45 * t,
                "emissive": 1.0,
                "tag": "vfx",
            }
        )
    return out


class Scene:
    def __init__(self, data: dict):
        self.data = data
        self.tris: list[Tri] = []

    def add_area(self, area: dict):
        for part in area["parts"]:
            self.add_part(part)

    def add_part(self, part: dict):
        size = np.array([part["size"]["x"], part["size"]["y"], part["size"]["z"]], dtype=np.float32)
        pos = np.array([part["pos"]["x"], part["pos"]["y"], part["pos"]["z"]], dtype=np.float32)
        rot = part.get("rot") or {"x": 0, "y": 0, "z": 0}
        shape = part["shape"]
        alpha = part.get("alpha") or 0.0
        transparency_alpha = 1.0 - alpha

        if shape == "Cylinder":
            # Builder: Size = (height, diamX, diamZ), CFrame = Ry(y) * Rz(90)
            local_size = np.array([size[1], size[0], size[2]], dtype=np.float32)
            sides = 10 if max(size[0], size[1]) > 10 else 8
            verts, faces = prism_tris(local_size, sides)
            matrix = rot_y(rot.get("y", 0.0)) @ rot_z(90.0)
        elif shape == "Ball":
            d = max(size)
            seg, ring = (14, 10) if d > 6 else (9, 6)
            verts, faces = sphere_tris(size, seg, ring)
            matrix = np.eye(3, dtype=np.float32)
        else:
            verts, faces = box_tris(size)
            matrix = (
                rot_y(rot.get("y", 0.0))
                @ rot_x(rot.get("x", 0.0))
                @ rot_z(rot.get("z", 0.0))
            )

        world = (verts @ matrix.T) + pos
        color = hex_to_rgb(part["color"])
        material = part.get("mat", "Slate")
        emissive = float(part.get("emissive") or 0.0)
        if material == "Neon":
            emissive = max(emissive, 1.0)
        elif material == "ForceField":
            emissive = max(emissive, 0.55)
        alpha_out = transparency_alpha
        if part.get("tag") in ("water", "mote") and alpha_out > 0.9:
            alpha_out = min(alpha_out, 0.88)

        for face in faces:
            self.tris.append(
                Tri(
                    v=world[face],
                    color=color,
                    emissive=emissive,
                    alpha=alpha_out,
                )
            )


# ----------------------------------------------------------------------------
# camera + raster
# ----------------------------------------------------------------------------

class Camera:
    def __init__(self, eye, target, width, height, fov=FOV_DEG):
        self.eye = np.array(eye, dtype=np.float32)
        forward = np.array(target, dtype=np.float32) - self.eye
        forward /= np.linalg.norm(forward)
        up = np.array([0.0, 1.0, 0.0], dtype=np.float32)
        if abs(forward @ up) > 0.98:
            up = np.array([0.0, 0.0, 1.0], dtype=np.float32)
        right = np.cross(forward, up)
        right /= np.linalg.norm(right)
        true_up = np.cross(right, forward)
        self.basis = np.stack([right, true_up, forward])
        self.w = width
        self.h = height
        self.focal = (height / 2) / math.tan(math.radians(fov) / 2)


def render(scene: Scene, cam: Camera, lights, fog_rgb, fog_scale, ambient, out_path: Path):
    w, h = cam.w, cam.h
    color = np.zeros((h, w, 3), dtype=np.float32)
    color[:] = fog_rgb * 0.35
    depth = np.full((h, w), np.inf, dtype=np.float32)

    def vec(entry):
        return [entry["pos"]["x"], entry["pos"]["y"], entry["pos"]["z"]]

    light_pos = np.array([vec(l) for l in lights], dtype=np.float32) if lights else np.zeros((0, 3), np.float32)
    light_col = np.array([hex_to_rgb(l["color"]) for l in lights], dtype=np.float32) if lights else np.zeros((0, 3), np.float32)
    light_pow = np.array([l["brightness"] * 0.55 for l in lights], dtype=np.float32) if lights else np.zeros(0, np.float32)
    light_rng = np.array([l["range"] for l in lights], dtype=np.float32) if lights else np.zeros(0, np.float32)

    moon_dir = np.array([0.25, 1.0, 0.15], dtype=np.float32)
    moon_dir /= np.linalg.norm(moon_dir)

    opaque = [t for t in scene.tris if t.alpha > 0.9]
    translucent = [t for t in scene.tris if t.alpha <= 0.9]

    def draw(batch, write_depth: bool):
        for tri in batch:
            rel = tri.v - cam.eye
            view = rel @ cam.basis.T          # x right, y up, z forward
            if np.all(view[:, 2] <= 0.35):
                continue
            view = np.clip(view, None, None)
            view[:, 2] = np.maximum(view[:, 2], 0.35)

            sx = w / 2 + view[:, 0] * cam.focal / view[:, 2]
            sy = h / 2 - view[:, 1] * cam.focal / view[:, 2]
            z = view[:, 2]

            area = (sx[1] - sx[0]) * (sy[2] - sy[0]) - (sx[2] - sx[0]) * (sy[1] - sy[0])
            if area <= 0:      # back-face cull (counter-clockwise winding is outside)
                continue

            x0 = max(int(np.floor(sx.min())), 0)
            x1 = min(int(np.ceil(sx.max())) + 1, w)
            y0 = max(int(np.floor(sy.min())), 0)
            y1 = min(int(np.ceil(sy.max())) + 1, h)
            if x0 >= x1 or y0 >= y1:
                continue

            px = np.arange(x0, x1) + 0.5
            py = np.arange(y0, y1) + 0.5
            gx, gy = np.meshgrid(px, py)

            inv = 1.0 / area
            w0 = ((sx[1] - gx) * (sy[2] - gy) - (sx[2] - gx) * (sy[1] - gy)) * inv
            w1 = ((sx[2] - gx) * (sy[0] - gy) - (sx[0] - gx) * (sy[2] - gy)) * inv
            w2 = 1.0 - w0 - w1
            mask = (w0 >= -1e-6) & (w1 >= -1e-6) & (w2 >= -1e-6)
            if not mask.any():
                continue

            zz = w0 * z[0] + w1 * z[1] + w2 * z[2]
            region = depth[y0:y1, x0:x1]
            if write_depth:
                hit = mask & (zz < region)
                if not hit.any():
                    continue
                region[hit] = zz[hit]
            else:
                hit = mask & (zz <= region + 1.5)
                if not hit.any():
                    continue

            # --- flat shading -------------------------------------------------
            n = np.cross(tri.v[1] - tri.v[0], tri.v[2] - tri.v[0])
            norm = np.linalg.norm(n)
            if norm < 1e-9:
                continue
            n /= norm
            centre = tri.v.mean(axis=0)

            light_acc = np.array([ambient, ambient * 1.05, ambient * 1.2], dtype=np.float32)
            light_acc += tri.color * max(0.0, float(n @ moon_dir)) * 0.20
            if len(light_pos):
                d = np.linalg.norm(light_pos - centre, axis=1)
                atten = np.clip(1.0 - d / np.maximum(light_rng, 1.0), 0.0, 1.0) ** 2
                dirs = (light_pos - centre) / np.maximum(d, 1e-4)[:, None]
                lambert = np.clip(dirs @ n, 0.0, 1.0)
                contribution = (light_col * (light_pow * atten * lambert)[:, None]).sum(axis=0)
                light_acc += contribution

            base = tri.color * light_acc
            shade = base + tri.color * tri.emissive * 1.25 + np.array([0.012, 0.018, 0.024])
            shade = np.clip(shade / (1.0 + shade * 0.55), 0.0, 4.0)   # soft roll-off

            # --- fog ----------------------------------------------------------
            fog_amount = 1.0 - math.exp(-float(zz.mean()) / fog_scale)
            shade = shade * (1 - fog_amount) + fog_rgb * fog_amount

            dst = color[y0:y1, x0:x1]
            if write_depth:
                dst[hit] = shade
            else:
                local_alpha = tri.alpha
                dst[hit] = dst[hit] * (1 - local_alpha) + shade * local_alpha

    draw(opaque, True)
    translucent.sort(key=lambda t: float(np.mean((t.v - cam.eye) @ cam.basis[2])))
    draw(translucent, False)
    return post(color, out_path)


def post(color: np.ndarray, out_path: Path) -> Path:
    img = np.clip(color * 1.22, 0, 1) ** (1 / 1.02)   # exposure + gamma lift

    bright = np.clip(img - 0.52, 0, None)
    bloom = Image.fromarray((np.clip(bright * 255, 0, 255)).astype(np.uint8))
    bloom = bloom.filter(ImageFilter.GaussianBlur(14))
    bloom_arr = np.asarray(bloom, dtype=np.float32) / 255.0
    img = np.clip(img + bloom_arr * 0.55, 0, 1)

    h, w, _ = img.shape
    yy, xx = np.mgrid[0:h, 0:w]
    nx = (xx - w / 2) / (w / 2)
    ny = (yy - h / 2) / (h / 2)
    radius = np.sqrt(nx ** 2 + ny ** 2) / math.sqrt(2)
    vignette = np.clip(1.0 - 0.55 * radius ** 2.1, 0.35, 1.0)[..., None]
    img *= vignette

    # subtle cyan/amber split tone keeps the identity readable
    img[..., 2] *= 1.03
    img[..., 0] *= 1.01

    rng = np.random.default_rng(7)
    grain = (rng.random((h, w, 1), dtype=np.float32) - 0.5) * 0.016
    img = np.clip(img + grain, 0, 1)

    out = Image.fromarray((img * 255).astype(np.uint8))
    out.save(out_path, quality=92)
    return out_path


# ----------------------------------------------------------------------------
# shots
# ----------------------------------------------------------------------------

SHOT_LIST = [
    # name, camera eye, look-at, size, fog scale, description
    ("01_reef_nave", (3, 21, 139), (0, 26, -70), (1280, 720), 260,
     "South gate looking north down the nave: rib arches, drowned bells, ember braziers."),
    ("02_reef_chancel", (8, 9, -88), (0, 16, -132), (1280, 720), 180,
     "The Chancel dais and its beacon, seen from the nave floor."),
    ("03_reef_west_aisle", (-58, 13, 86), (-63, 9, 22), (1280, 720), 190,
     "West aisle: seated warden statue, colonnade and the west beacon."),
    ("04_reef_vault", (0, 96, 186), (0, 26, -30), (1280, 720), 300,
     "Wide vault shot showing the collapsed roof slabs and light shafts."),
    ("05_hub_island", (58, 638, 74), (0, 630, -6), (1280, 720), 340,
     "The Lantern hub island above the tide, with the tower and dive gate."),
    ("06_reef_east_gallery", (44, 11, 132), (66, 10, 88), (1280, 720), 190,
     "East gallery approach to the third beacon."),
    ("07_pulse_and_flare", (6, 14, 34), (0, 18, -60), (1280, 720), 240,
     "The pulse sounding (expanding ring) with a flare cone cutting the dark ahead."),
    ("08_beacon_relit", (5, 14, -94), (0, 15, -132), (1280, 720), 170,
     "A beacon mid-relight: the objective the whole loop is built around."),
]


def clearance(scene: Scene, eye, radius=4.5) -> tuple[float, int]:
    """Nearest triangle distance around the camera, so we never shoot from inside a wall."""
    eye = np.array(eye, dtype=np.float32)
    near = float("inf")
    hits = 0
    for tri in scene.tris:
        if tri.alpha < 0.5 or tri.emissive <= 0.0:
            continue
        d = np.linalg.norm(tri.v - eye, axis=1)
        if d.min() < near:
            near = float(d.min())
        if d.min() < radius:
            hits += 1
    return near, hits


def main():
    data = json.loads((HERE / "world.json").read_text())
    reef = Scene({"reef": data["reef"]})
    reef.add_area(data["reef"])
    hub = Scene({"hub": data["hub"]})
    hub.add_area(data["hub"])

    # Extra geometry for the two "in-play" shots, mirroring the client VFX budget.
    vfx = Scene({})
    vfx.tris = list(reef.tris)
    for spec in ring_specs((6, 1.2, 34), 34, 46, "#4BE3D2", thickness=0.55, height=2.2, alpha=0.2):
        vfx.add_part(spec)
    for spec in ring_specs((6, 1.6, 34), 17, 40, "#9BF6D8", thickness=0.35, height=1.4, alpha=0.35):
        vfx.add_part(spec)
    for spec in cone_specs((20, 9, 8), (-0.35, -0.05, -1), 34, 26, "#FFB25E"):
        vfx.add_part(spec)

    lit = Scene({})
    lit.tris = [t for t in reef.tris]
    for spec in ring_specs((0, 13, -132), 12, 30, "#4BE3D2", thickness=0.5, height=3.0, alpha=0.25):
        lit.add_part(spec)

    SHOTS.mkdir(exist_ok=True)
    for name, eye, target, size, fog_scale, _desc in SHOT_LIST:
        scene = hub if name.startswith("05") else (vfx if name.startswith("07") else (lit if name.startswith("08") else reef))
        lights = data["hub"]["lights"] if name.startswith("05") else data["reef"]["lights"]
        cam = Camera(eye, target, size[0], size[1])
        fog = hex_to_rgb("#0C1A24") if name.startswith("05") else hex_to_rgb("#071019")
        ambient = 0.34 if name.startswith("05") else 0.30
        near, close = clearance(scene, eye)
        flag = "  <-- CAMERA INSIDE GEOMETRY" if near < 2.0 or close > 3 else ""
        out = SHOTS / f"{name}.png"
        render(scene, cam, lights, fog, fog_scale, ambient, out)
        print(f"rendered {out.relative_to(ROOT)}  (nearest surface {near:.1f} studs){flag}")


if __name__ == "__main__":
    main()
