# Testing and verification report

Everything below was actually executed in this workspace. Anything not run is listed
under **Not verified** at the bottom — no result in this document is inferred.

## Toolchain (obtained at verification time, not vendored)

| Tool | Version | Purpose |
| --- | --- | --- |
| `luau` / `luau-analyze` | latest luau-lang CLI release | real Luau interpreter for the test suite |
| `luau-lsp` | 1.70.1 | `--!strict` typecheck against the official Roblox API dump |
| Roblox API definitions | `globalTypes.None.d.luau`, fetched from luau-lsp `main` | actual engine API surface (1,647 classes/services) |
| `selene` | 0.32.0 + generated Roblox std | lint |
| `stylua` | 2.6.0 | formatting |
| `rojo` | 7.7.1 | sourcemap for accurate `require` resolution; place build |
| Python | 3.13 + numpy + Pillow | offline renderer |

Robin notes: the repo does not commit these binaries; `tools/check.sh` and
`tools/run_tests.sh` read `TOOLS_DIR`.

## What runs

```bash
./tools/check.sh        # typecheck -> lint -> format gate
./tools/run_tests.sh    # builds a plain-Luau mirror of src/shared and runs the specs
./tools/render/build.sh # regenerates screenshots/ from the shipped layout
```

### `tools/check.sh`

1. `rojo sourcemap` → resolves `require(script.Parent.X)` so the analyzer knows the
   real module graph (string requires are otherwise "unsupported path").
2. `luau-lsp analyze --definitions <roblox dump> src`
3. `selene src tests`
4. `stylua --check src tests`

Last run: **typecheck 0 errors** · **selene 0 errors, 7 style warnings** (all
`roblox_manual_fromscale_or_fromoffset` suggestions, intentionally left because the
explicit form is clearer in the layout code) · **stylua clean**.

### `tools/run_tests.sh`

`tools/test_build.py` copies `src/shared/*.luau` into `tests/.build/`, rewrites
`require(script.Parent.X)` into relative string requires (and injects stub
`Vector3`/`Color3` where a module uses them), then the real Luau interpreter runs the
spec files. **The files under test are byte-identical copies of what ships** — there is
no forked implementation.

Last run: **PASS — 1264 assertions across 9 suites.**

| Suite | What it actually proves |
| --- | --- |
| `Validate` | NaN/inf/absurd-magnitude rejection, integer and range guards, payload shape rejection (extra fields, missing fields, numeric keys, non-table) |
| `RateLimiter` | burst-then-deny, refill over time, burst ceiling, backwards-clock safety, fixed-window reset |
| `SaveSchema` | garbage → valid default; impossible values clamped (embers ≤ 1e9, levels ≤ 99, NaN counters); unknown keys dropped; v1→v3 migration (gold→embers, flat level→upgrades, stats blob split); timestamp ordering; non-boolean flags ignored |
| `Progression` | monotonic rounded cost curve, purchase spends exactly once and never mutates the input, refusal paths (broke / unknown / mastered), stat clamping at the hard cap, hue validation, rank thresholds |
| `LightMath` | falloff bounds/monotonicity, cone inclusion for ahead/behind/outside, flare hit selection and distance scaling, spend floor, regen clamp, payout maths (escape ×1.25, death ×0.5, negative carried floors at 0), clock formatting |
| `GloamBrain` | homes toward lit players, ignores unlit, Lunger dash range gating, stagger interrupt + recovery, single death, Siphon prioritises beacons, pulse attraction, separation steering, hover height |
| `Layout` | determinism per seed, part budget (<2,200 reef / <2,600 total), no NaN or non-positive sizes, three unique in-bounds beacons, every ember mote and the spawn/exit sit over actual floor, both areas built and lit, hub clear of the reef, sector metadata covers every beacon |
| `Random` | seed reproducibility, divergence, range/int bounds (500 draws each), ±1 sign, zero-seed remap |
| `Balance` | pulse spam is unsustainable (cost > one cooldown of regen), full recovery from 20% < 90 s, one Siphon slows but cannot deny a beacon while two can, a clean run fits inside half the tide, a perfect dive pays several tier-1 upgrades, a failed dive still pays but less than one tier-1 upgrade, full mastery is 20–400 dives, 6-player population stays under the live cap |

Three real defects were found by these suites during development and fixed:
1. `Random.new` returned a value without its own methods (crashed the world builder).
2. Six-player Gloam population (30) exceeded `MaxAlive` (26) — tuning reduced from 3 to
   2 per extra player.
3. `PopulationPerBeaconLit` in Config was dead (the service hardcoded the number).

## Visual inspection performed

`tools/render/render_world.py` is a z-buffer rasteriser that consumes
`tools/render/world.json`, exported **from the same `Layout.build()` the game uses**, so
the geometry in every render is the shipping geometry. Review cycle actually followed:

| Round | Finding | Fix |
| --- | --- | --- |
| 1 | Reef nave unreadable: everything one hue, fog swallowing the arches | Raised stone palette values, added cyan/amber sconce network, ember braziers, light shafts |
| 2 | Hub read as a flat grey slab floating in blackness | Added causeway with lantern posts, standing-stone ring, chart monument, obelisk/arch for the two shops, tide shelf, distant spires |
| 3 | Camera shot 03 was inside a column; glow pools and coral tips read as translucent blobs | Added an automated camera-clearance check to the renderer (reports "nearest surface" per shot); glow pools flattened and desaturated; coral tips made opaque; coral given side branches and colour variety |
| 4 | Beacon objective not visible from the gate | Added translucent beacon light pillars (lightning-rod composition) |
| 5 | Flare VFX blobs occluded the shot | Reduced flare mote size/count and moved the cone off-axis |

Screenshots are labelled as renderer output, not engine captures, in
`screenshots/README.md`. UI mockups (`09`–`11`) are drawn from the same palette, type
scale and spacing values as `src/client/UI/Theme.luau`.

## Not verified (needs Roblox Studio / a real device)

- **No Studio viewport screenshot and no in-engine playtest.** No Roblox engine exists
  in this environment.
- Runtime behaviour that only the engine can confirm: `PointLight` shadow cost with ~36
  lights, `Future`-lighting look, particle appearance, `Humanoid.CameraOffset` shake,
  `ProximityPrompt` feel, tween smoothness, HUD on a 320 px-wide viewport.
- DataStore round-trip, write-lease conflict handling and `BindToClose` under a real
  server shutdown.
- Genuine 2–6 player networking (message volume, divergence, phase races).
- `rojo build` output was not opened in Studio; only the sourcemap was generated.

## Suggested Studio test pass (to close the gap)

1. `rojo build default.project.json -o Echowake.rbxlx`, open in Studio, Play.
2. Console: expect `[ECHOWAKE] world built in …ms` then `server ready`. No errors.
3. Hub: verify spawn, Ledger/Codex prompts, dive gate prompt.
4. Dive: pulse (Q), flare (F), sprint (Shift), relight one beacon, watch light regen
   multiply, get doused, confirm payout card and hub return.
5. Two-player local test (Studio → Test → 2 Players): shared beacon progress, per-player
   light, toast visibility.
6. F9 Performance on a mobile preset: part count, light count, script activity at idle.
7. Re-enable API access and confirm `EchowakeSave_v1` keys appear after a dive.
