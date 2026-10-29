# Security model

Threat model: a modified client can send any remote payload at any frequency. All of it
is treated as hostile input.

## 1. Trust boundaries

| Boundary | Direction | Handling |
| --- | --- | --- |
| `Remotes/Intent` (RemoteEvent) | client → server | allow-list by action name, exact payload shape, per-action token bucket, liveness check, `pcall`-isolated handler |
| `Remotes/Query` (RemoteFunction) | client → server | allow-list by name, its own token bucket, returns data only (never accepts state) |
| `Remotes/Signal` (RemoteEvent) | server → client | the only channel the client listens on; unknown events are ignored |
| DataStore payloads | disk → server | `SaveSchema.sanitize` on read: clamp, type-check, drop unknown keys, migrate old shapes |
| Studio/third-party assets | import → game | review checklist in `ASSETS.md`; no scripts are ever imported |

## 2. What the client can and cannot do

The client **can** ask to: dive, leave, pulse, flare (with an aim vector), sprint, buy an
upgrade by id, change lantern hue, open a panel.

The client **cannot**:
- set its own light, embers, upgrade levels, or run timer (all server-owned; the HUD
  reads server signals);
- damage a specific Gloam or choose flare targets (server runs the cone test with its
  own agent positions);
- buy at its own price (`Progression.purchase` prices on the server and re-clamps level);
- grant itself codex entries for unknown ids (`Codex.get` must resolve);
- exceed per-action rate limits or act without a live humanoid.

Aim vectors are the only free-form data accepted, and they are range-checked
(`Validate.isDirectionTriple` for shape, magnitude 0.1–2 on the server) before use.

## 3. Economic integrity

- **Light** is a server-side `DiverState` field. Pulse/flare/damage mutate it after
  cooldown checks on the server (`os.clock()` there, not the client's).
- **Embers** are only paid in `DiveService.settle`, from server-tracked `carried` values
  collected by server proximity checks.
- **Payouts** are computed by the pure `LightMath.payout`, which clamps beacons to the
  beacon count and floors negative carried values — asserted in `LightMathSpec`.
- **Upgrades** are purchased through `Progression.purchase`, which returns a *new* save
  and cannot mutate the caller's table.

## 4. Persistence integrity

- `sanitize` on every read: embers ≤ 1e9, levels ≤ 99, counters clamped, NaN rejected,
  unknown keys dropped, hue validated against an allow-list.
- **Write lease:** each server writes `_lease = { server, at }` via `UpdateAsync`. If
  another server holds an unexpired lease, this server refuses to write and marks the
  player read-only — the standard defence against two servers duplicating a save.
- **Read-only on failed load:** if `GetAsync` fails after retries, the session is marked
  read-only rather than writing a default save over live data (which would silently wipe
  a player's progress).
- Retries with linear backoff; `BindToClose` flushes; autosave every 90 s.

## 5. Availability and abuse resistance

| Abuse | Defence |
| --- | --- |
| Remote flooding | token bucket per player per action (`Net.INTENT_SHAPES` / `Net.IntentBudget`), plus a shared wrapper for queries |
| Payload smuggling (extra fields, nested junk) | `Validate.shape` rejects any field outside the allow-list |
| Action spam that would be "legal" | in-code cooldowns (pulse 5.5 s, flare 3.4 s) enforced on the server |
| Beacon progress from a distance | server proximity check against `Config.Dive.BeaconRadius` on the server's own positions |
| Decompression/NaN exploits | `Validate.isNumber` rejects NaN/±inf, `isFiniteInRange` bounds magnitude |

## 6. Secrets

No credentials, tokens or API keys exist in this repository. No `HttpService` calls. The
game never asks the player for anything but input.

## 7. Known gaps

- Rate limits are in-memory per server; a distributed attacker across many servers is
  limited only by `os.clock()` buckets on each.
- No anti-teleport/anti-speed detection: a client that walks through walls can reach a
  beacon faster. This is low-severity for a cooperative PvE game (it steals no currency,
  but it can earn beacons) and would be the next hardening step: server-side movement
  distance validation per `Heartbeat`.
- No profanity/text filtering surface exists because the game has no free text.
