# ECHOWAKE — design document

*A lantern is a small, fragile thing to bring into a cathedral.*

---

## 1. Concept

The reef is a drowned cathedral. The tide took it centuries ago and something else
moved in: the **Gloam**, photosensitive tissue that hunts the only thing a Lamplighter
cannot hide — light.

You do not carry a gun. You carry a **lantern**, and the lantern is the whole game.

**One-sentence pitch:** *Descend into a lightless reef cathedral with three dead
beacons, use sound to find what is hunting you, and get out with more than you came
with.*

### Unique selling point

Most Roblox PvE loops separate *resource* from *threat*. ECHOWAKE fuses them:

| Resource | Also is |
| --- | --- |
| Light (health bar) | your ammunition, your visibility, your sprint fuel |
| The pulse (information) | **bait** — it reveals enemies *by making them come to you* |
| The beacons (objective) | your only light regeneration and your only safe payout |
| The exit gate (safety) | opt-in, not automatic — you choose when to stop |

The result is a game about **when to be loud**, which is a decision no other Roblox
dive game asks you to make.

## 2. Player fantasy and tone

You are the last Lamplighter: under-equipped, deliberate, and outnumbered.
The tone is a slow, gorgeous dread — deep teal water, amber lantern, magenta things in
the fog. Nothing is gory; the horror is the fog line and the sound design.

## 3. The loops

### Primary loop (5–30 s)
Move through dark → decide to spend light on a pulse → get a 2–3 second snapshot of
the reef and everything in it → everything now knows where you are → flare the closest
thing (costs light) or sprint away (costs light) → regain light by standing still or
standing in a lit beacon.

Every action has a light price and a positional consequence. The loop is fully
satisfying with zero progression: pulse, panic, flare, laugh.

### Session loop (5 minutes)
One tide = 300 s (+20 s per extra diver). Three beacons to relight, ~42 ember motes to
collect, one gate home. Beacons pay out whether or not you escape; carried embers are
halved if you are doused. Tension rises as *the tide clock* and *your light* run down
in parallel.

### Meta loop (days)
Five upgrades with material stat effects, a lantern hue cosmetic that other players can
see, a Gloam codex that fills as you encounter archetypes, ranks that show investment,
and a lifetime-ember leaderboard. Full mastery is ~30–60 dives (asserted in
`tests/specs/BalanceSpec.luau`).

## 4. The three Gloam

Designed as *questions*, not just health bars.

| | Behaviour | The question it asks |
| --- | --- | --- |
| **Drifter** | Slow, relentless, homes on any burning lantern | "Can you afford to keep burning?" |
| **Lunger** | Coils, then dashes when you are close and lit | "Do you flare, or do you move first?" |
| **Siphon** | Ignores you; drains beacon progress | "Do you defend the objective or yourself?" |

One Siphon slows a beacon; two can deny it. That is deliberate: co-op is the answer,
and the game says so mechanically instead of in a tutorial.

## 5. Objectives & map flow

```
                    ┌────────── THE CHANCEL (beacon 1) ──────────┐
                    │            apse dais, north                │
   WEST AISLE ──────┤                                            ├────── EAST AISLE
   (beacon 2)       │            NAVE: rib arches,              │       (beacon 3)
   colonnade,       │            inlaid guide line,             │       drowned bells,
   warden statue    │            braziers, light shafts         │       collapsed vault
                    └──────────── RETURN GATE (south) ───────────┘
```

Readability rules that came directly out of the render review:

1. **One guiding line.** A broken cyan inlay runs the length of the nave. In fog, that
   line is the map.
2. **Colour-coded sectors.** Nave = cyan, west = mint, east = teal. You can navigate by
   hue alone when you cannot see geometry.
3. **Vertical beacons.** Each unlit beacon throws a translucent light pillar so the
   objective is visible from the gate — the "pull" that makes a dark level fair.
4. **Warm/cool split.** Cyan architecture, amber gameplay furniture (braziers, sconces,
   lanterns). Amber means *you can interact with this*.
5. **Silhouette variety.** Columns, rib arches, hanging bells, statues and coral have
   deliberately different outlines so the fog never becomes a grey wall.

## 6. Art direction

- **Palette:** deep teal/steel for architecture, cyan bioluminescence for the reef,
  amber for player-owned light, magenta for threat, mint for success. Every one of those
  is a single source of truth in `src/shared/Palette.luau`.
- **Lighting:** `Future` technology, low ambient with heavy fog (`FogEnd` 420), an
  `Atmosphere` with strong haze, bloom for emissives, a subtle colour-correction grade.
  The fog is the level design: it hides geometry so the reef feels endless.
- **Materials:** slate for stone, neon for anything alive, metal for ironwork, glass/
  forcefield for water and gates, fabric for the drowned banners.
- **Scale:** 40-stud nave, 62-stud arches, 8-stud player. The building is deliberately
  three times human scale; the player should feel like a visitor.

## 7. UX and onboarding

The game teaches in three beats, each under ten seconds:

1. **Spawn in the hub.** One lit causeway, one visible gate, one toast:
   *"Walk to the Dive Gate and hold E to descend."*
2. **First descent.** Full-light spawn, a toast naming the pulse key, and a footer hint
   that repeats the current objective.
3. **First death or first escape.** The payout card explains the economy in plain
   language: carried × N, beacons × N, multiplier.

HUD rules: everything lives in a corner, scales with viewport height, and never covers
the crosshair. Amber = your light, magenta = damage, mint = success, cyan = world.
Mobile gets circular thumb buttons in the lower-right and a compact lantern panel.

## 8. Retention and social

- **Reasons to return tomorrow:** leaderboard rank, codex completion, next upgrade tier,
  and the deeper "one more dive" pull of a near-miss payout.
- **Social surface:** a light pillar from another player's beacon is visible across the
  map — you can literally watch a teammate succeed. Beacon progress is shared; dive time
  scales with party size; light regen multiplies while any beacon burns.
- **Fair monetisation:** none implemented. No Robux, no passes, no paid assets. If
  monetisation were added, the honest levers are cosmetic lantern effects and extra
  codex slots — never light capacity, which would break the core tension.

## 9. Scope discipline (what was cut, and why)

| Cut | Reason |
| --- | --- |
| Procedural *rooms* | A hand-tuned single arena reads better and is testable; the layout is still seeded and validated. |
| Player weapons | Any weapon dilutes "the lantern is the game". |
| Backpack/inventory | Five fixed upgrades cover the same progression with a fraction of the UI surface. |
| Boss encounter | The tide clock is already the pressure; a boss would fight it for attention. |
| Third-party audio | No verified, properly licensed sound was integrated; see `ASSETS.md`. |

## 10. Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| Too dark on cheap screens | Dozens of authored light sources, emissive inlays, and a floor guide line; ambient is deliberately not zero. |
| Pulse feels mandatory → spam | Pulse costs 18% of base-light, more than one cooldown of regen restores (asserted in tests). |
| Siphons make beacons impossible | One Siphon can only slow; two make it a genuine co-op problem. |
| Data loss / duplication | Sanitised payloads, write lease, read-only mode when a load fails. |
| Mobile performance | ~1,780 parts total, no per-frame server work beyond a 12 Hz AI tick, no textures or meshes, LOD-ready folder split. |
