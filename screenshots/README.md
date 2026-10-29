# Screenshots and renders

## What these are

These are **renders, not Roblox engine captures.** No Roblox runtime is available in the
environment this project was built in, so instead of pretending otherwise:

- `01`–`08` are produced by `tools/render/render_world.py`, a small z-buffer rasteriser
  that consumes `tools/render/world.json` — which is exported directly from
  `Layout.build()`, the same function `World/Builder` uses to create the live parts.
  **Geometry, positions, colours, emissive materials and light placement are the
  shipping values.** Shading, bloom and depth-of-field are approximations of the
  engine's `Future` lighting.
- `09`–`11` are **UI specifications** drawn with the same palette, type scale, spacing
  and layout numbers as `src/client/UI/Theme.luau` / `Hud.luau` / `Panels.luau`.

They are honest design-review artefacts: good enough to judge composition, readability,
hierarchy and palette, and explicitly not proof that the game runs in-engine. Runtime
verification status is in [`../docs/TESTING.md`](../docs/TESTING.md).

Regenerate everything: `./tools/render/build.sh`

## Index

| File | Shows | Design intent |
| --- | --- | --- |
| `01_reef_nave.png` | The nave from the return gate | Establishes the guiding inlay line, rib-arch rhythm, sconce lighting and the pull toward the chancel |
| `02_reef_chancel.png` | The Chancel dais and beacon | Objective readability: light pillar, coral depth, warm/cool split |
| `03_reef_west_aisle.png` | West aisle and beacon | Sector colour identity (mint), colonnade silhouette, ambient glow |
| `04_reef_vault.png` | Wide vault view | Scale, collapsed roof slabs, light shafts, overall arena composition |
| `05_hub_island.png` | The Lantern hub | First impression: tower, causeway, standing stones, dive gate, tide shelf |
| `06_reef_east_gallery.png` | East gallery | Teal sector, drowned bells, uneven floor rubble |
| `07_pulse_and_flare.png` | Pulse ring + flare cone | The core verb: information for light |
| `08_beacon_relit.png` | Beacon mid-relight | The reward moment the loop is built around |
| `09_ui_hud_desktop.png` | Full HUD, 1440×810 | Corner-anchored layout, light bar, cooldown chips, run pips, toasts |
| `10_ui_hud_mobile.png` | HUD at phone aspect | Touch buttons, compact lantern panel |
| `11_ui_ledger_panel.png` | The Ledger modal | Upgrade hierarchy, affordability states, level pips, tab structure |
