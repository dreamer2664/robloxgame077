# Asset ledger and third-party policy

## Current state: no third-party assets

ECHOWAKE ships **only** content authored in this repository plus engine-provided
`rbxasset://` particles. There are no imported models, meshes, textures, decals,
animations, sounds or fonts from the Roblox Creator Store or anywhere else.

That is a deliberate decision for this build:

- **Verified provenance.** Nothing in the repo needs a licence audit, and nothing can
  hide a backdoor inside a model hierarchy.
- **Cohesion.** The reef's identity is a tight palette of five hues. Most free
  cathedral/coral kits are stylistically unrelated to each other, and a mismatched set
  reads as "asset flip" instantly.
- **Scope.** Everything the game needs (architecture, coral, lighting furniture, VFX,
  UI) turned out to be expressible as primitives, so importing was not the shortest
  path to quality.

### Engine-provided content actually referenced

| Asset | Where | Source | Notes |
| --- | --- | --- | --- |
| `rbxasset://textures/particles/sparkles_main.dds` | reef dust, beacon motes, ember motes, Gloam wisp | Roblox built-in content, resolved by the engine | No upload, no licence question, cannot be tampered with |
| Built-in fonts (`Gotham`, `Code`) | all UI | Roblox engine fonts | No asset ids |
| Built-in materials (`Slate`, `Neon`, `Metal`, `Glass`, `ForceField`, `Fabric`) | world + VFX | Roblox engine | — |

No `rbxassetid://` references exist anywhere in `src/`. Verify at any time:

```bash
grep -rn "rbxassetid" src/ || echo "no uploaded asset references"
```

## Sound: slots ready, ids intentionally empty

`src/client/Controllers/SoundKit.luau` defines the full cue list (`pulse`, `flare`,
`beaconLit`, `shard`, `hit`, `diveStart`, `bank`, `uiClick`). `SoundKit.play` is a no-op
when an id is empty, so the game is fully playable and never stalls on a missing asset.
To add audio, follow the review checklist below and paste ids into `SoundKit.IDS`.

## Checklist before adding any Creator Store / third-party asset

1. **Provenance.** Record the asset id, the store page URL, the creator, and the date
   in the table below. If any of that is unknown, do not use it.
2. **Licence.** Confirm the asset is free to use in an experience (Creator Store terms).
   Anything that requires payment, a group join, or an off-platform download is out.
3. **Inspect before importing into the place.** Prefer downloading the `.rbxm`/`.rbxmx`
   and reading it as text (or importing into a *throwaway* place first):
   - `grep -i "require"` — a decorative model should never require anything.
   - Look for `Script`/`LocalScript`/`ModuleScript` instances at all.
   - Search for `HttpService`, `InsertService`, `DataStore`, `MarketplaceService`,
     `:FireServer`, `loadstring`, `getfenv`, `setfenv`, long base64 literals, or
     anything writing to `game.ServerScriptService`.
   - Check `ParticleEmitter`/`Sound` texture ids resolve to the stated creator.
4. **Strip.** Delete every script, `RemoteEvent`, `Tool`, `HopperBin` and any
   `Humanoid`/`Animator` you did not ask for. Keep geometry + materials only.
5. **Re-parent, don't trust paths.** Move the geometry under
   `Workspace/EchowakeWorld/...` and attach behaviour from our own code, keyed by
   attribute — never let an imported script drive gameplay.
6. **Budget.** Count parts before/after. The whole world is ~1,780 parts; a single
   decorative import should not add hundreds.
7. **Profile in Studio** (F9 → Performance) before and after, on a mobile preset.
8. **Attribute it** in the table below and in `README.md` Credits.

## Ledger

| Asset id | Name | Creator | Store URL | Used for | Reviewed (date) | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| _none_ | | | | | | |

## Attribution text

If assets are added later, add the creator and store page here; Roblox does not require
in-experience attribution for Creator Store assets, but crediting creators is the right
thing to do and protects the project if an asset is later delisted.
