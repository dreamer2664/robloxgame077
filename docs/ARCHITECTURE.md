# Architecture

## Shape

```
              ┌──────────────── ReplicatedStorage/Shared ────────────────┐
              │ Config  Palette  Layout  GloamBrain  LightMath           │
              │ Progression  SaveSchema  Validate  RateLimiter  Net      │
              └───────┬─────────────────────────────────────┬───────────┘
                      │ (pure: no Instances, unit tested)   │
      ┌───────────────▼──────────────┐        ┌─────────────▼──────────────┐
      │ ServerScriptService/Server   │        │ StarterPlayerScripts/Client│
      │  init.server.luau (bootstrap)│        │  init.client.luau (loop)   │
      │  App.luau (service context)  │        │  Controllers/  UI/         │
      │  World/Builder.luau          │        │                            │
      │  Services/Net, PlayerData,   │        │                            │
      │           Dive, Gloam, Board │        │                            │
      └───────────────┬──────────────┘        └─────────────┬──────────────┘
                      └─────── two RemoteEvents + RF ────────┘
```

The rule that keeps this simple: **`src/shared` is pure.** No module in it touches an
Instance at load time, so the entire rules layer runs in a plain Luau interpreter and is
unit tested. Only `Builder` (server) and the UI/VFX controllers (client) know about
Roblox objects.

## Why no framework

Knit/Flamework would add dependency weight for a game with five services. Instead:
`App.luau` is a typed context object populated in `init.server.luau`, services receive
it and cross-reference through it. Construction order is explicit and readable in one
file, which matters more here than an injector.

## Server services

| Service | Owns | Notes |
| --- | --- | --- |
| `NetService` | remotes, intent gateway | the single ingress point; validation + rate limiting happen before any handler |
| `PlayerDataService` | DataStore, leases, autosave | degrades to in-memory when DataStore is unavailable |
| `DiveService` | run state machine, lantern economy, beacons, motes, payouts | ~12 Hz fixed step, independent of frame rate |
| `GloamService` | enemy parts, swarm population, contact damage, flare resolution | hands steering to the shared brain |
| `LeaderboardService` | OrderedDataStore, cached board | refreshes on a 60 s loop; never blocks a request |

### The dive tick

`RunService.Heartbeat` → `step(dt)` accumulates into a **fixed 0.1 s step** (max 3 per
frame), so AI, regen and beacon progress behave identically at 20 fps and 240 fps. Run
state is broadcast 4×/s, not per frame.

## Client

- `ClientNet` — typed wrapper over the remotes, `pcall`-isolated handlers.
- `Store` — the only client-side state, written **only** from server signals.
- `Controls` — keyboard/mouse, gamepad and touch all funnel into three verbs; local
  cooldowns gate the UI, the server re-checks everything.
- `Lantern` — orb, light, pulse shockwave, flare flash, echo reveal, pickup sparks,
  camera shake (via `Humanoid.CameraOffset` so it layers over the default camera).
- `UI/Theme` + `UI/Kit` + `Hud` + `Panels` — every colour, corner radius, motion curve
  and type size comes from `Theme`, so restyling is one file.

## Data flow for one pulse

```
key Q ─► Controls.pulse() ─► ClientNet.fire("pulse")
                                   │
        NetService: action allow-listed? payload shape ok? live humanoid? token?
                                   │ yes
        DiveService: cooldown ok? LightMath.spend(light, 18, floor=5)?
                                   │ yes
        ├─ FireAllClients("pulse", {x,y,z,radius})      → every client draws a ring
        ├─ GloamService.revealInRadius() (server truth)
        ├─ GloamService.attract()  (sound is bait)
        └─ FireClient("reveal", {ids, duration})        → only the caster sees outlines
```

## Persistence schema (v3)

```lua
{
  version = 3,
  embers = 0, lifetimeEmbers = 0,
  beaconsLit = 0, dives = 0, divesCompleted = 0, bestDiveSeconds = 0,
  upgrades = { lantern = 0, wick = 0, resonance = 0, echo = 0, flare = 0 },
  lanternHue = "amber",
  codex = { Drifter = true, ... },
  lastSeenAt = 0, firstSeenAt = 0,
}
```

Migrations from v1 (`gold`, flat `lanternLevel`) and v2 (`stats` blob) are implemented
and tested; the sanitiser runs after migration so a failed migration can never produce
an invalid save.

## Performance notes

- One `Layout.build()` pass → ~1,780 parts, split into `Structure` / `Decor` folders so
  distance-based fading can be added without touching gameplay code.
- Gloam are simple anchored balls moved by setting `CFrame` at 12 Hz, not physics
  assemblies; no `Humanoid`, no pathfinding (the arena is open, steering is enough).
- Client HUD refreshes at 20 Hz with a cheap diff; the lantern rig runs in
  `RenderStepped` but only moves two parts and expires a small reveal table.
- No per-frame allocations of note; no `while true do wait()` polling outside the two
  deliberate loops (autosave, leaderboard).
