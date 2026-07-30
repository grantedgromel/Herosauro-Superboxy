# RIBEIRA — engine contract

**Every agent must read this before writing code. It is the only coordination
mechanism.**

Target: a third-person co-op action game whose *visual and tactile quality*
stands next to **Crash Bandicoot N. Sane Trilogy**. Godot 4.7.1, Forward+ on
desktop, GL Compatibility on the web. The world is **Porto** — the Ponte de Dom
Luís I over the Douro — and it must stay recognisably Porto at every step.

Two heroes, **Herosauro** and **Super Boxy**, fight **Adamastor**, the giant of
Portuguese myth, on the bridge deck. That is the game. It does not become a
platformer, a battle royale or an elimination party game.

## Hard rules

1. **You own your directory. Never edit files outside it.** Another agent owns
   every other directory and your edit will be clobbered or will break them.
   The ownership map is below and it is exhaustive.
2. **Never reach into another subsystem's script.** Cross-subsystem
   communication goes through `GameManager`'s signals or through group lookups
   (`get_tree().get_nodes_in_group("players")`). Do not `preload()` another
   stream's script to call its methods.
3. **No new addons, no GDExtension, no external asset downloads.** The project
   must build from a clean checkout with nothing but Godot 4.7.1 and the
   export templates. Everything in `assets/` is either already committed or is
   generated procedurally at load time.
4. **No unseeded randomness anywhere that reaches the screen.** Every
   `RandomNumberGenerator` gets an explicit `.seed`, and the global `randf()` /
   `randi()` family is banned in builders. Capture reproducibility depends on
   it, and the capture gate is what lets six agents work at once.
5. **Never animate off the wall clock.** `Time.get_ticks_msec()` and
   `Time.get_ticks_usec()` are forbidden in `_process` / `_physics_process`.
   Accumulate `delta` into a member instead. A subsystem that reads the wall
   clock makes every screenshot a different screenshot, which silently destroys
   the regression gate for everyone — see "Why this rule exists" below.
6. **Build geometry once, then bake.** `MeshBaker` welds a builder's output into
   a single surface. A builder that leaves several hundred `MeshInstance3D`
   nodes in the tree is a bug even if it looks correct — draw calls are the
   number that kills the frame, not triangles.
7. **Materials are cached and shared by parameter set** (`ToonFactory`).
   Anything that mutates a material per instance — hit flash, dissolve, fade —
   must `.duplicate()` first, or it recolours every object in the scene.
8. `tools/harness.py check` must pass after your change. If you break the boot
   or the import, nobody else can work.

## Ownership map

| stream | owns | may not touch |
|---|---|---|
| `world` | `scripts/world/` (except the three atmosphere files), `scenes/world/bridge_arena.tscn` | anything else |
| `atmosphere` | `assets/environments/`, `assets/shaders/`, `scripts/world/lighting_rig.gd`, `scripts/world/sky_background.gd`, `scenes/world/sky_background.tscn` | anything else |
| `materials` | `scripts/toon_factory.gd`, `assets/textures/`, `assets/materials/` | anything else |
| `players` | `scripts/players/`, `scripts/abilities/`, `scenes/players/` | anything else |
| `boss` | `scripts/boss/`, `scenes/boss/` | anything else |
| `props` | `scripts/props/`, `scenes/props/` | anything else |
| `fx` | `scripts/fx/`, `scenes/fx/` | anything else |
| `ui` | `scripts/ui/`, `scenes/ui/`, `assets/fonts/`, `assets/ui/` | anything else |
| `audio` | `autoloads/audio_manager.gd`, `assets/audio/`, `default_bus_layout.tres` | anything else |
| `camera` | `scripts/camera_rig.gd` | anything else |

Shared, owned by the lead — **do not edit**: `autoloads/game_manager.gd`,
`autoloads/input_manager.gd`, `scripts/main.gd`, `scripts/props/physics_layers.gd`,
`tools/`, `project.godot`, `export_presets.cfg`, this file.

If you need a change in a lead-owned file, say so in your report. Do not make it.

## Signal vocabulary

`GameManager` is the hub. Gameplay nodes **call the mutators**; UI, FX, audio and
camera **react to the signals**. Nothing else is a legitimate cross-stream path.

| signal | payload | emitted when |
|---|---|---|
| `state_changed` | `(new_state: int)` | MENU / PLAYING / PAUSED / VICTORY / DEFEAT transition |
| `game_started` | — | a run begins; reset yourself here |
| `game_over` | `(victory: bool)` | run ends |
| `player_damaged` | `(player_id, amount, new_health)` | a hero takes damage, and once at `start_game` as a sync |
| `player_respawned` | `(player_id)` | a hero returns after going over the side |
| `boss_damaged` | `(amount, new_health)` | Adamastor takes damage, and once at `start_game` |
| `boss_phase_changed` | `(phase: int)` | boss crosses 50% health |
| `score_changed` | `(new_score: int)` | score moves |
| `combo_changed` | `(player_id, combo: int)` | combo counter moves or times out |
| `timer_updated` | `(seconds: float)` | every frame while PLAYING |
| `camera_shake_requested` | `(strength: float, duration: float)` | any system wants a shake |

Mutators: `start_game()`, `change_state()`, `go_to_menu()`, `toggle_pause()`,
`damage_player()`, `damage_boss()`, `add_score()`, `hit_stop()`, `request_shake()`,
`notify_player_respawned()`, `difficulty_scalar()`.

If you need a signal that is not listed, add a row here in the same commit and
say so in your report — the lead adds it to `game_manager.gd`.

## Physics layers

`PhysicsLayers` is the single source of truth. Never write a raw bitmask.

`WORLD` `PLAYERS` `BOSS` `PLAYER_PROJECTILES` `HAZARDS` `PROPS`

Two rules that are easy to get wrong: Godot collides when **either** side's mask
names the other's layer, and **the boss deliberately masks `WORLD` only** — a
nine-metre giant that a barrel can body-block reads as broken. Adamastor blocks
other things by being in *their* masks, and shoves them with explicit hitboxes.

## Surface vocabulary

Shared between `materials`, `fx` and `audio` so an impact picks the right spark
and the right sound. `ToonFactory.Surface`:

`FLAT` `GRANITE` `IRON` `COBBLE` `PLASTER` `TERRACOTTA` `WOOD`

Adding a surface means adding its detail normal + mask pair in
`assets/textures/generate_detail_maps.gd` and a case in the `fx` impact table
and the `audio` footstep table, in the same commit.

## Groups

Runtime lookup contract. Adding a node to a group is a public API.

| group | who joins | who reads |
|---|---|---|
| `players` | every `PlayerBase` | boss, camera, ui, props, main |
| `boss` | Adamastor | players, camera, ui, main |
| `camera_rig` | the active `CameraRig` | players (for camera-relative movement) |
| `spawn_root` | the node transient spawns are parented to | fx, boss, props |

---

# The quality bar

Every visual change is reviewed by an adversarial critic against **Crash
Bandicoot N. Sane Trilogy**. The critic's job is to find the frame *amateur*,
and it is told to compare against the real thing. These are the non-negotiables
it scores against.

N. Sane Trilogy is not "a cartoon look". It is **cartoon proportions rendered
with completely uncompromised material and lighting work** — the geometry is
exaggerated and readable, and then every surface on it behaves like real
photographed matter. Both halves are required. Stylised geometry with cheap
materials reads as a mobile game; realistic materials on realistic proportions
reads as a different game entirely.

## Materials

- **No flat surfaces.** Every material needs albedo variation, a normal map,
  roughness variation and a detail layer that is still doing work at 0.5 m.
  A single flat-coloured polygon anywhere in frame fails the shot.
- **Wetness, wear and growth.** N. Sane's stone is damp in the crevices and dry
  on the exposed faces; its wood is worn pale where feet land. Porto gives this
  for free — river-damp granite, salt-bleached ironwork, moss in the joints of
  the deck, sun-faded plaster. Use it.
- **Physically plausible values.** Albedo 0.02–0.9, metals are 0 or 1 with no
  in-between, roughness varies across a surface and never sits at a constant.
- **Nothing perfectly straight, clean or repeated.** Edge wear on every corner
  the eye reaches, grime where two planes meet, per-instance rotation and scale
  variation on everything placed more than twice.

## Lighting

- **Bright, saturated, high-key daylight.** The golden-hour treatment is gone.
  Porto in clear midday sun: a strong warm key, a genuinely blue sky fill, and
  bounce that carries the colour of what it bounced off — green off the river
  banks, terracotta off the roofs, granite grey off the deck.
- **Contact is mandatory.** Every object that touches the ground needs a
  contact shadow tight enough to plant it. Objects floating on their own
  ambient are the single fastest way to read as amateur.
- **Readability first.** The playable corridor of the bridge deck is the
  brightest, highest-contrast thing in frame. Background Porto is beautiful but
  it must sit back — aerial perspective, lower contrast, cooler.
- **Exposure-driven, not multiplier-driven.** Fix the look with the sun's
  energy and the tonemap, never by multiplying an albedo.

## Silhouette and proportion

- **Chunky, exaggerated, readable at 5 m and at 50 m.** Heroes read as their
  silhouette alone. Adamastor reads as a mass, not a detailed model.
- **Squash and stretch on everything that moves.** Jump anticipation, landing
  compression, attack follow-through. A character that translates without
  deforming reads as a prop being slid around.
- **Secondary motion.** Nothing on a character is perfectly rigid — tails, ears,
  gloves, cloth all lag and settle.

## Weight — every action

Every hit, land, smash and spin needs **all five**, or it is not finished:

1. a visual FX at the point of contact,
2. a camera response (shake, punch or push),
3. an audio transient,
4. a hit-stop or a slow frame proportional to the impact,
5. a UI acknowledgement (damage number, combo tick, health move).

A hit with three of the five feels broken and the critic will say so.

## Set dressing

- **Density.** N. Sane fills every corner. Empty flat ground anywhere the camera
  can see is a defect. Crates, barrels, rope, lamps, tram rails, gulls, laundry,
  moss, puddles, papers, dropped fruit.
- **Depth in three layers.** Foreground detail the camera passes, the playable
  mid-ground, and a background Porto with real parallax.
- **Motion in the frame at all times.** Gulls, water, cloth, cloud shadow,
  drifting dust in the light shafts. A still frame is a dead frame.

---

# Why the determinism rules exist

The capture gate (`tools/harness.py`) screenshots the game from fixed vantage
points and compares to a stored baseline **pixel for pixel**. That gate is what
makes it safe for several agents to work at once: it catches the change you did
not intend to make, in a subsystem you do not own, in seconds.

It only works if two runs of the same code produce the same image. Three things
break that, and all three are banned above:

- **Wall-clock animation.** `sky_background.gd` and `river_life.gd` both drove
  their gulls and boats off `Time.get_ticks_msec()`. Two runs are milliseconds
  apart at boot, so every gull was in a different place in every capture, and
  every shot containing sky differed on every run. That is not a small
  diff — it makes the gate report failure constantly until it is ignored, and
  an ignored gate is no gate.
- **Unseeded RNG**, for the same reason at build time rather than frame time.
- **Variable frame delta.** Captures run under `--fixed-fps`, so simulation
  advances by an exact amount per frame and temporal effects converge from the
  same phase every time. Anything that integrates real time defeats this.

The capture harness pumps a **fixed number of frames** in a **fresh process per
shot**. Isolation matters as much as the frame count: sharing one process across
shots leaks exposure adaptation, particle age and animation phase forward, so
shot 7 depends on shot 6 and the set stops being reproducible.
