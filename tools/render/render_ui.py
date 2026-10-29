#!/usr/bin/env python3
"""UI design mockups for ECHOWAKE.

Draws the HUD and panels using the same palette, type scale and spacing the Luau
UI kit uses (src/client/UI/Theme.luau, Hud.luau, Panels.luau). These are design
specifications, not captured screenshots: they exist so layout, hierarchy and
contrast can be reviewed and iterated without Roblox Studio.
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
SHOTS = ROOT / "screenshots"

FONT_DIRS = [
    "/usr/share/fonts/truetype/dejavu",
    "/usr/share/fonts/truetype/liberation",
    "/usr/share/fonts/truetype/noto",
]


def pick_font(bold: bool, mono: bool = False) -> str | None:
    names = []
    if mono:
        names = ["DejaVuSansMono-Bold.ttf" if bold else "DejaVuSansMono.ttf"]
    else:
        names = ["DejaVuSans-Bold.ttf"] if bold else ["DejaVuSans.ttf"]
    for directory in FONT_DIRS:
        for name in names:
            candidate = Path(directory) / name
            if candidate.exists():
                return str(candidate)
    for directory in FONT_DIRS:
        for candidate in sorted(Path(directory).glob("*.ttf")):
            return str(candidate)
    return None


def font(size: int, bold: bool = False, mono: bool = False) -> ImageFont.FreeTypeFont:
    path = pick_font(bold, mono)
    if path:
        return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def hexc(value: str, alpha: int = 255) -> tuple[int, int, int, int]:
    v = value.lstrip("#")
    return (int(v[0:2], 16), int(v[2:4], 16), int(v[4:6], 16), alpha)


C = {
    "ink": hexc("#04101A"),
    "inkSoft": hexc("#081A26"),
    "panel": hexc("#06111A"),
    "stroke": hexc("#2FD8C8"),
    "strokeDim": hexc("#166060"),
    "text": hexc("#DCEEF5"),
    "textDim": hexc("#7E96A6"),
    "amber": hexc("#FFB25E"),
    "amberDeep": hexc("#8A4A17"),
    "ember": hexc("#FFD37A"),
    "cyan": hexc("#4BE3D2"),
    "mint": hexc("#9BF6D8"),
    "bad": hexc("#FF6B7F"),
    "good": hexc("#6EF0A0"),
    "gold": hexc("#FFD37A"),
    "teal": hexc("#1FB6C4"),
}


def rounded(draw, box, radius, fill=None, outline=None, width=1):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def label(draw, xy, text, f, fill, anchor="la"):
    draw.text(xy, text, font=f, fill=fill, anchor=anchor)


def backdrop(w: int, h: int, reef_like: bool = True) -> Image.Image:
    """A dark, foggy, vaguely architectural backdrop so UI contrast is judged fairly."""
    img = Image.new("RGB", (w, h), (6, 14, 22))
    d = ImageDraw.Draw(img, "RGBA")
    # fake depth bands
    for i in range(14):
        y = int(h * (0.30 + i * 0.05))
        shade = 8 + i * 2
        d.rectangle([0, y, w, y + h], fill=(shade, shade + 8, shade + 14, 255))
    if reef_like:
        # colonnade silhouettes
        for i in range(9):
            x = int(w * (0.04 + i * 0.115))
            top = int(h * (0.16 + (i % 3) * 0.05))
            d.rectangle([x, top, x + int(w * 0.028), h], fill=(16, 26, 36, 255))
            d.rectangle([x + 3, top + 40, x + 8, h - 60], fill=(31, 182, 166, 120))
        # fog glow
        glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        gd = ImageDraw.Draw(glow)
        gd.ellipse([w * 0.34, h * 0.24, w * 0.66, h * 0.7], fill=(40, 150, 150, 70))
        glow = glow.filter(ImageFilter.GaussianBlur(90))
        img = Image.alpha_composite(img.convert("RGBA"), glow).convert("RGB")
    return img


def lantern_orb(img: Image.Image, x: int, y: int, color=C["amber"]):
    glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([x - 70, y - 70, x + 70, y + 70], fill=(color[0], color[1], color[2], 60))
    glow = glow.filter(ImageFilter.GaussianBlur(38))
    img.alpha_composite(glow)
    d = ImageDraw.Draw(img, "RGBA")
    d.ellipse([x - 16, y - 16, x + 16, y + 16], fill=(color[0], color[1], color[2], 235))
    d.ellipse([x - 34, y - 34, x + 34, y + 34], outline=(color[0], color[1], color[2], 90), width=2)


def hud(w=1440, h=810) -> Image.Image:
    img = backdrop(w, h).convert("RGBA")
    lantern_orb(img, int(w * 0.36), int(h * 0.62))
    d = ImageDraw.Draw(img, "RGBA")

    # vignette
    vig = Image.new("L", (w, h), 0)
    vd = ImageDraw.Draw(vig)
    vd.ellipse([-w * 0.25, -h * 0.3, w * 1.25, h * 1.3], fill=190)
    vig = vig.filter(ImageFilter.GaussianBlur(140))
    dark = Image.new("RGBA", (w, h), (0, 0, 0, 255))
    dark.putalpha(Image.eval(vig, lambda v: int(255 - v * 0.85)))
    img = Image.alpha_composite(img, dark)
    d = ImageDraw.Draw(img, "RGBA")

    # --- run bar (top centre) ---
    bw, bh = 430, 64
    bx = (w - bw) // 2
    rounded(d, [bx, 16, bx + bw, 16 + bh], 16, fill=(6, 17, 26, 215), outline=(22, 96, 96, 160), width=1)
    label(d, (bx + 14, 22), "TIDE", font(11, True), C["textDim"])
    label(d, (bx + 14, 34), "3:42", font(30, False, True), C["text"])
    for i, (name, progress, lit) in enumerate(
        [("C", 1.0, True), ("W", 0.55, False), ("E", 0.0, False)]
    ):
        px = bx + 120 + i * 64
        fill_col = (C["mint"][0], C["mint"][1], C["mint"][2], 210) if lit else (C["cyan"][0], C["cyan"][1], C["cyan"][2], 120)
        rounded(d, [px, 26, px + 56, 70], 8, fill=(4, 16, 26, 200), outline=(25, 100, 100, 150), width=1)
        ph = int(44 * progress)
        if progress > 0:
            rounded(d, [px, 70 - ph, px + 56, 70], 8, fill=fill_col)
        label(d, (px + 28, 48), name, font(19, True), C["ink"] if lit else C["textDim"], anchor="mm")
    label(d, (bx + bw - 16, 48), "\u25c6 86", font(17, True), C["ember"], anchor="rm")

    # --- profile card (top right) ---
    pw = 196
    px = w - pw - 22
    rounded(d, [px, 16, px + pw, 78], 14, fill=(6, 17, 26, 205), outline=(22, 96, 96, 160), width=1)
    label(d, (px + 12, 22), "LAMPLIGHTER", font(15, True), C["text"])
    label(d, (px + 12, 43), "\u25c6 1,240 embers", font(13), C["ember"])
    label(d, (px + 12, 60), "E \u00b7 The Ledger", font(11), C["textDim"])

    # --- lantern panel (bottom left) ---
    lw, lh = 300, 118
    lx, ly = 22, h - lh - 22
    rounded(d, [lx, ly, lx + lw, ly + lh], 16, fill=(6, 17, 26, 210), outline=(22, 96, 96, 165), width=1)
    label(d, (lx + 16, ly + 12), "LANTERN", font(11, True), C["textDim"])
    label(d, (lx + lw - 16, ly + 10), "68%", font(14, False, True), C["amber"], anchor="ra")
    rounded(d, [lx + 16, ly + 32, lx + lw - 16, ly + 44], 6, fill=(4, 16, 26, 220))
    bar = Image.new("RGBA", (lw - 32, 12), (0, 0, 0, 0))
    bd = ImageDraw.Draw(bar)
    for i in range(lw - 32):
        t = i / (lw - 32)
        col = tuple(int(C["amber"][k] * (1 - t) + C["mint"][k] * t) for k in range(3))
        bd.line([(i, 0), (i, 12)], fill=col + (255,))
    mask = Image.new("L", (lw - 32, 12), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, int((lw - 32) * 0.68), 12], 6, fill=255)
    img.paste(bar, (lx + 16, ly + 32), mask)
    d = ImageDraw.Draw(img, "RGBA")
    label(d, (lx + 16, ly + 50), "light is life \u00b7 light is sight", font(11), C["textDim"])

    for i, (name, key, cost, accent, cd) in enumerate(
        [("PULSE", "Q", "-18%", C["cyan"], 0.0), ("FLARE", "F", "-22%", C["amber"], 0.45)]
    ):
        cx = lx + 16 + i * 138
        cy = ly + 70
        rounded(d, [cx, cy, cx + 130, cy + 44], 10, fill=(4, 16, 26, 215), outline=(accent[0], accent[1], accent[2], 150), width=1)
        if cd > 0:
            rounded(d, [cx, cy, cx + int(130 * cd), cy + 44], 10, fill=(0, 0, 0, 120))
        rounded(d, [cx + 9, cy + 12, cx + 29, cy + 32], 5, fill=(accent[0], accent[1], accent[2], 90))
        label(d, (cx + 19, cy + 22), key, font(12, True), C["text"], anchor="mm")
        label(d, (cx + 34, cy + 13), name, font(12, True), C["text"])
        label(d, (cx + 34, cy + 28), cost, font(10), C["textDim"])

    # --- crosshair ---
    cxp, cyp = w // 2, h // 2
    d.ellipse([cxp - 9, cyp - 9, cxp + 9, cyp + 9], outline=(75, 227, 210, 140), width=2)
    d.ellipse([cxp - 2, cyp - 2, cxp + 2, cyp + 2], fill=C["mint"])

    # --- toast ---
    tw = 300
    tx = (w - tw) // 2
    rounded(d, [tx, 96, tx + tw, 130], 17, fill=(4, 16, 26, 230), outline=(110, 240, 160, 170), width=1)
    label(d, (tx + tw // 2, 113), "The Chancel relit. (2/3)", font(14), C["good"], anchor="mm")

    # --- footer hint ---
    label(d, (w // 2, h - 30), "Relight the three beacons  \u00b7  [Q] pulse  \u00b7  [F] flare", font(14), C["textDim"], anchor="mm")

    # --- touch controls (mobile layout overlay, shown dimmed for spec) ---
    for name, x, y, r, accent in [
        ("PULSE", w - 108, h - 148, 43, C["cyan"]),
        ("FLARE", w - 196, h - 210, 35, C["amber"]),
        ("RUN", w - 96, h - 96, 28, C["mint"]),
    ]:
        d.ellipse([x - r, y - r, x + r, y + r], fill=(4, 16, 26, 190), outline=(accent[0], accent[1], accent[2], 150), width=2)
        label(d, (x, y), name, font(11, True), accent, anchor="mm")
    label(d, (w - 22, h - 22), "touch layout shown at right", font(10), C["textDim"], anchor="rb")

    return img.convert("RGB")


def panel_ledger(w=1000, h=810) -> Image.Image:
    img = backdrop(w, h).convert("RGBA")
    d = ImageDraw.Draw(img, "RGBA")
    d.rectangle([0, 0, w, h], fill=(0, 0, 0, 90))

    cw, ch = 648, 486
    cx, cy = (w - cw) // 2, (h - ch) // 2
    rounded(d, [cx, cy, cx + cw, cy + ch], 20, fill=(6, 17, 26, 248), outline=(47, 216, 200, 115), width=2)

    label(d, (cx + 24, cy + 20), "THE LEDGER", font(25, True), C["text"])
    label(d, (cx + 24, cy + 56), "\u25c6 1,240 embers \u00b7 rank Lamplighter", font(13), C["textDim"])
    rounded(d, [cx + cw - 102, cy + 22, cx + cw - 24, cy + 52], 10, fill=(8, 26, 38, 230), outline=(22, 96, 96, 140), width=1)
    label(d, (cx + cw - 63, cy + 37), "CLOSE", font(12, True), C["text"], anchor="mm")

    tabs = [("UPGRADES", True), ("CODEX", False), ("LEDGER BOARD", False)]
    for i, (name, active) in enumerate(tabs):
        tx = cx + 24 + i * 158
        rounded(d, [tx, cy + 78, tx + 150, cy + 112], 10,
                fill=(4, 16, 26, 250) if active else (8, 26, 38, 200),
                outline=C["stroke"] if active else (22, 96, 96, 120), width=1)
        label(d, (tx + 75, cy + 95), name, font(12, True), C["stroke"] if active else C["textDim"], anchor="mm")

    rows = [
        ("LANTERN CAPACITY", "+48 max light", "MASTERED", C["amber"], 8, 8),
        ("STEADY WICK", "+2.24 light/sec", "\u25c6 700", C["mint"], 4, 8),
        ("RESONANCE", "+54 studs pulse range", "\u25c6 1,100", C["cyan"], 2, 8),
        ("LONG ECHO", "+1.4s echo memory", "\u25c6 1,700", C["textDim"], 0, 8),
    ]
    for i, (title, effect, price, accent, level, maxlvl) in enumerate(rows):
        ry = cy + 124 + i * 78
        rounded(d, [cx + 24, ry, cx + cw - 24, ry + 70], 12, fill=(8, 26, 38, 220))
        label(d, (cx + 38, ry + 10), title, font(15, True), accent)
        label(d, (cx + 38, ry + 30), "Wider reservoir of light before you gutter out.", font(12), C["textDim"])
        label(d, (cx + 38, ry + 50), effect, font(12, False, True), accent)
        for p in range(maxlvl):
            dotx = cx + cw - 138 + p * 12
            filled = p < level
            d.ellipse([dotx, ry + 10, dotx + 7, ry + 17],
                      fill=(accent[0], accent[1], accent[2], 255) if filled else (22, 96, 96, 140))
        affordable = price.startswith("\u25c6 7") or price.startswith("\u25c6 1,1")
        rounded(d, [cx + cw - 128, ry + 18, cx + cw - 38, ry + 52], 10,
                fill=(4, 16, 26, 240),
                outline=(C["ember"] if affordable else C["strokeDim"]), width=1)
        label(d, (cx + cw - 83, ry + 35), price, font(13, True),
              C["ember"] if affordable else C["textDim"], anchor="mm")

    return img.convert("RGB")


def main():
    SHOTS.mkdir(exist_ok=True)
    hud(1440, 810).save(SHOTS / "09_ui_hud_desktop.png")
    hud(820, 420).resize((1280, 656)).save(SHOTS / "10_ui_hud_mobile.png")
    panel_ledger().save(SHOTS / "11_ui_ledger_panel.png")
    print("rendered UI mockups")


if __name__ == "__main__":
    main()
