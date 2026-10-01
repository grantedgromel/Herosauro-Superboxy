# Code map (generated for the storybook adaptation)

Read-only survey of the project as of b03fef2, written so level and UI agents do not each re-derive it. Line numbers drift; treat them as pointers.

All paths are relative to `/home/user/Herosauro-Superboxy/herosauro-superboxy/` unless noted. Key absolute paths: `/home/user/Herosauro-Superboxy/ARCHITECTURE.md`, `.../herosauro-superboxy/scripts/main.gd`, `.../autoloads/game_manager.gd`, `.../autoloads/input_manager.gd`, `.../project.godot`. No files were edited and Godot was not run.

## 1. Boot and flow

**`scenes/main.tscn`** is a bare `Node3D` with `scripts/main.gd` attached. `project.godot` sets `run/main_scene` to it and has three autoloads: GameManager, AudioManager, InputManager.

**`main.gd` `_ready()` (39–56), in order:**
1. Sets `PROCESS_MODE_ALWAYS`.
2. Creates a `CanvasLayer` called "UI" and instances `scenes/ui/hud.tscn`, `game_over.tscn` and `main_menu.tscn` into it, in that order (preloads at 28–30).
3. Connects `state_changed`, `game_started` and `game_over`.
4. Calls `GameManager.change_state(MENU)`.

No 3D world exists while the menu is up.

**Menu to run:**
- START → `main_menu.gd:_on_activated` (246–249) → `_leave()` runs a 0.28 s curtain fade, then calls `GameManager.start_game()`.
- `start_game` (game_manager.gd:111) resets everything, calls `change_state(PLAYING)`, then emits `game_started`.
- `main._on_state_changed(PLAYING)` (145) runs `_build_world()`.
- `main._on_game_started` (156–171) runs `_build_world()` again (idempotent), calls `reset_state()` on every node in "players" and `reset_boss()` on "boss", and frees the children of the spawn root.

**`_build_world()` (68–107):** if a world exists and `_roster_matches()` (174) is true, it returns early. Otherwise it tears down and builds:
- `World` (Node3D)
- the bridge, from `WorldScene = preload("res://scenes/world/bridge_arena.tscn")` (25)
- `Spawned` (Node3D, joins group `spawn_root`)
- the heroes, via `_spawn_player(id)` (122–130) for each `GameManager.active_player_ids()`. Scenes come from `HeroScenes {1: herosauro.tscn, 2: superboxy.tscn}` (12–15). Each gets `player_id` and `spawn_position` set before `add_child`.
- the props, from `PropSpawnerScene` (`scenes/props/prop_spawner.tscn`, 27)
- the boss, from `AdamastorScene` (`scenes/boss/adamastor.tscn`, 26), placed at `BOSS_SPAWN`
- `CameraRig.new()`, added last, with `target = first hero`

Teardown (110–119) calls `remove_child` then `queue_free`.

**Inside the bridge scene:** `bridge_arena.tscn` holds the deck collider (100×2×14 box, top at y=2), the river (900×900 plane at y=-15, z=-140), the `SunLight`, and an instance of `sky_background.tscn` (WorldEnvironment with `porto_daylight.tres` plus `LightingRig`). `sky_background.gd:_ready` (159–178) adds CityBackdrop, `TerrainBuilder.build()`, the Ribeira city, landmarks, rabelos, `RiverLife` and clouds. `bridge_arena.gd:_ready` (257–268) builds the roadway, tramway, footways, parapets, ends, arch, ironwork, lamps and dressing.

**Level-agnostic pieces:**
- A `LevelConfig` or level switch is **absent**. `docs/IMPLEMENTATION_PLAN.md:129` proposed one; it was never built.
- Already generic:
  - `PlayerBase` fall detection: a raycast for "no WORLD below", no deck height.
  - `Hitbox` / `Hurtbox`, `ImpactFX`, `BossTelegraph`, `MeshBaker`, `SceneryKit`, `ToonFactory`, `UIStyle`, `AudioManager`.
  - `CameraRig` group framing (aims at "boss" if one exists, otherwise holds yaw).
  - `PropSpawner` placement exports.

**What must change to load a different arena:**
- **main.gd:** replace the constants `WorldScene`, `AdamastorScene`, `P1_SPAWN`, `P2_SPAWN`, `BOSS_SPAWN` and the PropSpawner config with per-level data, using `load()` rather than `preload` so the web build doesn't load every level at boot. `_build_world`'s early return must also compare the level id; today PLAY AGAIN (VICTORY→PLAYING, which skips MENU) reuses whatever world exists if the roster matches.
- **game_manager.gd:**
  - Add a current-level field and setter.
  - Add a public win/objective mutator. `_end_game` (289) is private, and victory exists only inside `damage_boss` (257–258).
  - Make `MAX_BOSS_HEALTH` and the phase ratio per-level, or optional.
  - Add any new signals, plus matching rows in ARCHITECTURE.md's signal table.

**Every hard-coded bridge or Adamastor assumption:**

| where | what |
|---|---|
| main.gd:21–23 | `P1_SPAWN (-12,4,0)`, `P2_SPAWN (-8,4,2)`, `BOSS_SPAWN (16,2,0)` |
| main.gd:25–27 | bridge, Adamastor and prop-spawner scene preloads |
| adamastor.gd:94–97 | `SPAWN (16,2,0)`, `ARENA_X_MIN -14`, `ARENA_X_MAX 24`, `ARENA_Z 5`; `_clamp_to_arena` (670); `reset_boss` sets `global_position = SPAWN` (550) |
| bridge_arena.gd:39–115 | `DECK_TOP 2.0` ("must stay at 2.0", 35–37), `ROADWAY_HALF 5`, `WALKWAY_OUTER 6.55`, `BOSS_ARENA_X` |
| prop_spawner.gd:42–60 | `x_min/x_max ±32`, `edge_z 4.2`, `deck_top_y 2.0` (exports); `KEEP_OUT` is a **const** that mirrors main.gd's spawns |
| prop_body.gd:75, debris_piece.gd:24 | `CULL_Y -6` |
| prop_body.gd:93 | `DECK_SURFACE COBBLE` |
| player_base.gd:65, 68 | `ABSOLUTE_KILL_Y -60`; `RECOVERY_HALF_WIDTH 5.0` (= ROADWAY_HALF), used to clamp the recovery position's z (718) |
| player_base.gd:548, 671, 1154, 1175 | landing, recovery, knockdown and revive FX use `Surface.COBBLE` |
| player_base.gd:715 | default recovery direction is -X ("back down the bridge") |
| player_base.gd:229 | fall SFX is the "Douro" splash |
| camera_rig.gd:316 | `SAFE_HALF_WIDTH 6.55` (= WALKWAY_OUTER), used for the shoulder fade in world Z |
| camera_rig.gd:400 | default aim is +X ("giant waits at +X") |
| camera_rig.gd:231 | co-op yaw aims at the "boss" group |
| game_manager.gd:37–39, 253–258 | `MAX_BOSS_HEALTH 500`, `BOSS_PHASE2_RATIO`; win = boss_health ≤ 0 |
| hud.gd:49, 176 | `BOSS_ACTOR = ADAMASTOR`; boss bar sized from `MAX_BOSS_HEALTH` |
| game_over.gd:181–189 | Adamastor art on defeat; "Porto stands…" / "Adamastor still holds the bridge…" |
| audio_manager.gd:733–752 | `battle_phase1` on game_started, `battle_phase2` on boss_phase_changed |
| ui_progress.gd | best score, time and wins are global, not per level |
| tools | playtest asserts boss damage > 0 and hero min y ≥ -4 (playtest.gd:241, 259); shots.json, baseline.gd, budget.gd (preloads bridge_arena) and profile.gd's ROUTE are all bridge vantages |
| probes | `_props_probe` asserts KEEP_OUT, the deck and barrel axis; `_boss_probe` and `_coop_probe` boot main.tscn and expect Adamastor |

## 2. GameManager (`autoloads/game_manager.gd`)

**States (33):** `MENU, PLAYING, PAUSED, VICTORY, DEFEAT`. `change_state` (134) sets `get_tree().paused = (state == PAUSED)`.

**Difficulty (34):** `EASY, NORMAL, HARD`. `difficulty_scalar()` (160) returns 0.75 / 1.0 / 1.4. `set_difficulty` (146) clamps.

**Signals (17–31):**
- `state_changed(new_state:int)`
- `game_started`
- `game_over(victory:bool)`
- `player_damaged(player_id, amount, new_health)`
- `player_respawned(player_id)`
- `boss_damaged(amount, new_health)`
- `boss_phase_changed(phase)`
- `score_changed(new_score)`
- `combo_changed(player_id, combo)`
- `timer_updated(seconds)`
- `camera_shake_requested(strength, duration)`

**Constants (36–45):** `MAX_PLAYER_HEALTH 100`, `MAX_BOSS_HEALTH 500`, `FALL_PENALTY 20`, `BOSS_PHASE2_RATIO 0.5`, `COMBO_TIMEOUT 2.5`, `SCORE_PER_HIT 10`, `REVIVE_HEALTH 50`.

**Mutators:**
- `start_game()` (111): resets score, `fight_time`, health {1:100, 2:100}, `player_score`, boss health, phase and combos. Then PLAYING, then `game_started`, then sync emits: `boss_damaged(0, hp)`, plus `player_damaged(pid, 0, hp)` and `combo_changed(pid, 0)` per roster id, `score_changed`, `timer_updated(0)`.
- `go_to_menu()` (140); `toggle_pause()` (170), PLAYING↔PAUSED only.
- `set_player_count(n)` (150), clamped 1–2; `set_human_hero(h)` (154), clamped 1–2.
- `damage_player(id, amount)` (179): no-op unless PLAYING and the id is in the table; emits `player_damaged`; if `_all_heroes_down()` (211, which asks the "players" group) it calls `_end_game(false)`.
- `revive_player(id, health = 50)` (195): emits `player_damaged(id, 0, hp)` and `player_respawned`.
- `notify_player_respawned(id)` (230).
- `damage_boss(amount, source_player)` (234):
  - lowers health and emits `boss_damaged`
  - increments that player's combo, resets its window to 2.5 s, and emits `combo_changed`
  - awards `points = 10 × combo` to both `player_score[pid]` and `add_score`
  - at ≤50% health: `boss_phase = 2` and emits `boss_phase_changed(2)`
  - at ≤0: `_end_game(true)`
- `add_score(points)` (265); `combo_for(id)` (261).
- `hit_stop(duration = 0.1)` (273): sets `Engine.time_scale = 0`, waits on a timer that ignores time scale, restores 1. It refuses to nest.
- `request_shake(strength, duration = 0.3)` (283).
- `p2_combo` (78) is a deprecated getter.

**Victory and defeat:**
- Victory happens only when boss health reaches 0.
- Defeat happens only when every hero in the "players" group is at 0 health. If no hero nodes exist, it falls back to the roster.
- `_end_game` resets time scale, changes to VICTORY or DEFEAT, and emits `game_over`.
- There is no time limit or other objective.

**Roster:**
- `player_count` defaults to **2**, and the menu never changes it. `set_player_count` is called only by probes, so the shipped UI always starts co-op.
- `active_player_ids()` (104) returns `[human_hero]` in solo, otherwise `[1, 2]`.
- AI ally is **absent** (stated at 54 and in main.gd:10). The docstring at 158 mentions "ally AI", but none exists.

**Revive and respawn:**
- In co-op, 0 health means DOWN for `PlayerBase.DOWN_TIME` = 4.0 s, then `revive_player` brings the hero back at 50 health. Solo 0 health ends the run immediately.
- Going over the side costs 20 health and returns the hero next to the partner (or to their own spawn).

**Timer:** `fight_time += delta` and `timer_updated` is emitted every frame while PLAYING (87–98). Each player's combo window decays independently there too.

## 3. Input

**InputManager (`autoloads/input_manager.gd`):**
- Slot prefix `{1: "", 2: "p2_"}` (46).
- Public API:
  - `action_name(player, action)` (54)
  - `solo_slot()` (76)
  - `get_move_vector(p)` (87): pad space, x = strafe, y = forward, deadzone 0.18, length capped at 1
  - `get_look_vector(p)` (100)
  - `is_jump_just_pressed` / `is_jump_held` / `is_ability_just_pressed` / `is_attack_just_pressed` / `is_sprinting` (113–131)
- `_slots_for(p)` (67): in solo, **both** sets drive the lone hero; in co-op each hero reads only its own slot.

**Input map (`project.godot [input]`):**

| action | P1 (bare name) | P2 (`p2_` prefix) |
|---|---|---|
| move left/right/up/down | A / D / W / S | J / L / I / K, left stick axes 0/1 |
| look left/right/up/down | arrow keys | right stick axes 2/3 (no keys) |
| jump | Space | M, joypad button 0 (A) |
| sprint | Left Shift | Right Shift, button 7 (L3) |
| attack | LMB, Q | U, button 2 (X) |
| ability | RMB, E | O, button 3 (Y) |

UI actions: `ui_confirm` = Enter, KP Enter, button 0; `ui_cancel` = Esc, button 1 (B); `ui_pause` = Esc, button 6 (Start). The engine's default `ui_up/down/accept` are also used by the menu.

**Gamepad:** supported on **slot 2 only**. Every joypad event uses `device -1`, so every connected pad drives P2, and P1 cannot use a pad in co-op. Solo merges both sets, so a pad works there.

**Touch:** **absent**. `export_presets.cfg` has `experimental_virtual_keyboard=false` and mobile texture formats off, with the reason given as "no touch input scheme".

## 4. Players

**Hierarchy:**
- `PlayerBase` (`class_name`, extends `CharacterBody3D`, `scripts/players/player_base.gd`).
- Subclasses: `herosauro.gd` and `superboxy.gd`.
- Virtual hooks (1470–1486): `_build_visuals`, `_perform_ability`, `_custom_locomotion(delta) -> bool`, `_cancel_actions`.
- Scenes `scenes/players/herosauro.tscn` (capsule r 0.45, h 2.0) and `superboxy.tscn` (r 0.4, h 1.7) are just a CharacterBody3D, the script and a CollisionShape3D.

**Shared values:**
- Exports (22–49): `move_speed 8`, `sprint ×1.3`, `jump_velocity 13`, `gravity 30`, `coyote 0.12`, `jump_buffer 0.10`, `low_jump_gravity ×2.2`, `invuln_time 1.5`, `knockback_decay 14`, plus acceleration ramps.
- Leash (92–100): soft pull from 12 m, hard clamp at 16 m.
- Basic attack (`_handle_attack`, 827):
  - snaps facing to the camera line
  - plays the "attack" clip
  - arms a `Hitbox.box` swing volume (`_build_swing_box`, 853) for 0.14 s
  - the volume masks **BOSS | PROPS** with knockback 4 and prop impulse 9
  - `_on_swing_landed` (881) adds a spark, `hit_stop(0.03)` and shake 0.16 on the boss, or shake 0.07 on props
- Ability (`_handle_ability`, 810): gated by `ability_cooldown`, then calls `_perform_ability()`.

**Herosauro (P1, `herosauro.gd`):**
- Jab: 10 damage, cooldown 0.55, range 4.0, hold 0.34 (20–31).
- **Dino Energy** (51–69): spawns `scenes/fx/dino_energy.tscn` into `spawn_root` at facing×1.6, plays `play_dino_fire`, shake 0.14, ability cooldown 2.0.
- The projectile script is `scripts/abilities/dino_energy.gd`, a ShapeCast3D:
  - `speed 20`, `lifetime 2`, `damage 50` (16–18)
  - mask WORLD | BOSS | PROPS with `collide_with_areas = false` (33–35)
  - `_impact` calls `damage_boss` + `hit_stop(0.07)` only for "boss" group bodies; PropBody gets an impulse; shake 0.22 on every impact

**Super Boxy (P2, `superboxy.gd`):**
- Jab: 7 damage, cooldown 0.38, range 3.7, hold 0.28.
- **Boxy Dash** (ability cooldown 1.5):
  - `DASH_DURATION 0.25` at 4× move speed (32 m/s), `velocity.y = 0`
  - leaves a ghost every 0.06 s (`scenes/fx/dash_trail.tscn` with `abilities/boxy_dash.gd`, 0.3 s red fade)
  - `_custom_locomotion` checks the 2D distance to `get_first_node_in_group("boss")` and connects under `DASH_HIT_RANGE 5.0`
  - on connect, `_land_dash` deals `damage_boss(25)`, nudges the boss by 1.2, sparks at power 2.0, then `hit_stop(0.06)` and shake 0.55

**Health:** stored in `GameManager.player_health`.
- `take_hit(amount, knockback)` (743) refuses while downed, invulnerable or not PLAYING. Otherwise it applies knockback, starts i-frames, plays the hurt sound, sparks, squashes, shakes by `0.12 + 0.01×damage`, hit-stops by `clamp(damage × 0.005, 0.025, 0.11)`, then calls `damage_player`.
- `_on_health_changed` (1124) triggers `_go_down` / `_get_up`.
- Falling (`_handle_fall`, 600) respawns when the hero is 6 m below the last ground with nothing on WORLD within 80 m below, or below y = -60.

**How heroes hit things:**
- `scripts/props/hitbox.gd` (ShapeCast3D, `landed(target)` signal, `arm(duration)`, `disarm()`, static `box()` / `sphere()`).
- `_deliver` (114) routes in this order:
  1. a Hurtbox → `receive()`
  2. "players" → `take_hit`, or `apply_knockback` when damage = 0
  3. "boss" → `GameManager.damage_boss` + `nudge`
  4. PropBody → `apply_hit_impulse`
- `hurtbox.gd` (Area3D, `took_hit` signal, `damage_scale`, `absorbs`) forwards to its target: players → `take_hit`, boss → `damage_boss`, otherwise any node with a `take_hit` method.
- Hero layers (309–317): layer PLAYERS, mask WORLD | BOSS. Heroes pass through each other.

**AI ally controller:** absent.

**Camera lookup:** heroes use `get_viewport().get_camera_3d()` in `_camera_forward` (431), falling back to `Vector3.FORWARD`. Nothing reads the `camera_rig` group, even though ARCHITECTURE.md says players do.

**Animation:**
- The .glb models are **skinned and animated** (one skin, 24-bone humanoid each). Clips, read from the GLB JSON:
  - herosauro: `cast, jab, run, walk`
  - superboxy: `punch1, run, walk`
  - adamastor: `kick, run, stomp, walk`
  - trex.glb: no skin, no clips
- `bind_animations(root, {key: substring})` (1244) builds an AnimationTree (1333): a BlendSpace1D over idle/walk/run plus a OneShot action layer through a TimeScale. Idle is synthesized from the walk cycle (1414) because none of the art has one.
- Procedural layers on top:
  - squash and stretch spring (`_drive_squash`, 1211)
  - `body_lag.gd` (`BodyLag` SkeletonModifier3D on the Spine / Spine01 / Spine02 / neck / Head / forearm / hand bones), driven by acceleration and yaw rate
- GLB materials are upgraded through `ToonFactory.upgrade_glb_materials`.

## 5. Boss

**Files:** `scripts/boss/adamastor.gd` (body), `adamastor_state_machine.gd` (a `RefCounted` FSM ticked from the boss's `_physics_process`), `boss_telegraph.gd`, `adamastor_corpse.gd`. The scene is a CharacterBody3D with a 5×9×4 box.

**Layers:** layer BOSS, mask WORLD only (141–150).

**Hitboxes (`_build_hitboxes`, 195):**
- prop sweep: damage 0, prop impulse 26, rehit 0.22
- contact: 6 damage × difficulty, knockback 8, lift 4, rehit 1.2 s
- slam: sphere r 5.2 at (-4.2, 1.2, 0), 18 damage (×1.15 in phase 2 ≈ 21), knockback 16, lift 7

**Push-out:** `_shove_players` (323) moves overlapping heroes positionally at up to 14 m/s.

**FSM states (67):** `IDLE, CHASE, SLAM, ROCK_THROW, RETREAT, PHASE_TWO, ROAR`.
- CHASE (374) walks toward `target_player()` with a sine weave.
  - It slams when within `MELEE_RANGE 7` and the slam cooldown has expired.
  - Every decide interval it throws rocks if the target is at least `ROCK_RANGE 16` away, or on a roll of `aggression × (0.5 + spread_bias)`.
- Each attack is a tween chain that ends in RETREAT (0.55 s, ×0.76 in phase 2).

**Attack timings and damage:**

| attack | telegraph | damage | details |
|---|---|---|---|
| SLAM (457) | ground ring = wind-up 0.55 s (0.418 in P2) | slam volume 18 / ~21 | slam window 0.16 s; recover 0.45, settle 0.25; plus a shockwave (`scenes/fx/shockwave.tscn`, max radius 15, grow 0.5 s) at 14 / 20 in P2; shake 0.5; ground hit-stop 0.04 |
| ROCK_THROW (573) | crosshair markers, lead = wind-up 0.5 + flight time (0.35 + 0.03/m, clamped 0.5–1.8) | 15 / 18 in P2 | one rock per standing hero, plus a lead rock in P2; recover 0.35, settle 0.2; `rock_projectile.gd` is a RigidBody on HAZARDS, hits via body_entered → `take_hit` |
| ROAR (523) | wind-up 0.85, ring radius 11 | 16 | knockback 18, recover 0.5; the phase-2 entrance only |

**Tuning (`reset`, 231):**
- `n` = roster size, `ds` = `difficulty_scalar()`.
- pressure = `1 + 0.45(n-1)`
- speed = `min(9.6, 5.8 × ds × (1 + 0.1(n-1)))`
- aggression = `clamp(0.5 × ds × (1 + 0.2(n-1)), 0.3, 0.95)`
- decide interval = `clamp(3.4 / (ds × pressure), 1.6, 4.4)`
- slam gap = `1.3 / pressure`
- RNG seed `0x4144414D` (192), re-seeded on every reset.

**Targeting:** `target_player()` (427) scores each standing hero as distance − 5 m × threat. Threat (451) is `0.5 × share of player_score + 0.5 × combo/6`. Downed heroes are skipped.

**Taking damage:**
- Only through `GameManager.damage_boss`, from the Hitbox "boss" route, Dino Energy or the dash.
- `_on_boss_damaged` (578) plays `play_boss_hit`, flinches, flashes white for 0.05 s, and calls `_die` at 0.
- `_die` (627) stops the FSM, shakes 0.5, hit-stops 0.16, and topples an `AdamastorCorpse` (mass 900).
- Hit flash and recolour use duplicated per-surface materials (745).

**Phase 2:** `boss_phase_changed(2)` → `_on_phase_changed` (612) tints the materials red (×(1.5, 0.55, 0.45)) and calls `fsm.enter_phase_two()` (279). That applies the escalation (cadence ×0.65, wind-ups ×0.76, speed ×1.2, aggression +0.2) and goes to PHASE_TWO, which leads into ROAR.

**Other API:**
- signals `attack_telegraphed(kind, lead)` and `attack_impact(kind)`
- `is_attacking()`, `nearest_player()`, `nudge()`, `reset_boss()`, `tuning()`
- `BossTelegraph.aoe(parent, radius, lead, tint)` and `.marker(...)` (78, 86); tints SLAM / ROCK / ROAR at 37–39

## 6. Reusable building blocks

**ToonFactory (`scripts/toon_factory.gd`):**
- `enum Surface { FLAT, GRANITE, IRON, COBBLE, PLASTER, TERRACOTTA, WOOD }` (98).
- Static, cached `StandardMaterial3D` builders:
  - `solid(color, _, roughness, metallic)` (365)
  - `glow(color, energy)` (375)
  - `stone(color, tile)` (399), `cobblestone` (424), `iron(color, tile, metallic, roughness)` (459)
  - `plaster` (485), `terracotta` (492), `wood` (498), `cloth` (504), `ceramic` (515)
  - `glass(color, alpha)` (522), `water` (528)
  - the general `build(color, surface, roughness, metallic, tile_meters, normal_scale, ao, emission, emission_energy, alpha, specular, fine_detail)` (545)
- Also `upgrade_glb_materials(root, roughness = 0.68, metallic, normal_scale = 0.45, derive_normals)` (832) and `sample_noise` (802).
- Results are cached and shared, so `.duplicate()` before mutating one.

**MeshBaker (`scripts/world/mesh_baker.gd`, RefCounted):**
- `add_box(size, xform, uv_scale)` (77), `add_quad(a, b, c, d, uv_extent)` (119), `add_roof_prism` (130), `add_cylinder(r, h, xform, segments = 8, capped)` (162), `add_beam(from, to, thickness)` (181).
- `triangle_count()` (66).
- `commit(material, name, generate_lods = true) -> MeshInstance3D` (238) indexes, generates tangents and LODs.
- Winding contract: the right-hand normal must point the way the face faces. Get it wrong and the face is silently culled or lit inside out.

**SceneryKit (`scripts/world/scenery_kit.gd`):**
- `box` (21), `cylinder` (34)
- `repeat(parent, name, size, positions, mat)` (53): a MultiMesh, one draw call
- `solid(...)` (90): a StaticBody3D on WORLD with mask 0
- `solid_shape` (104)
- `world_mapped(mat)` (127)

**WorldTier (`scripts/world/world_tier.gd`):** `is_reduced()` (160) is true on GL Compatibility. Constants: `SHADOW_DISTANCE 96`, `SHADOW_SPLITS` 2, `RIVER_SUBDIVISIONS 88`, `SHADOW_RADIUS 66`.

**Build pattern:** the builders build into MeshBakers per material and commit once. Repeated identical boxes use `SceneryKit.repeat`. Collision uses a few simple `solid` boxes. Web cuts go behind `WorldTier.is_reduced()`, as `bridge_arena.gd:_apply_web_tier` (296) does. Kits live in `world/bridge/`, `terrain/` (`*_kit.gd`), `facade/` and `landmarks/` (`*_batch.gd` / `*_geo.gd`). RNGs are seeded explicitly (for example `rng.seed = 81881` in sky_background).

**Props:**
- `PropBody` (RigidBody3D, `prop_body.gd`):
  - exports: `surface` ("wood"/"stone"/"iron"/"cobble"), `body_kind`, `tint`, `trim_color`, `prop_mass`, `kick_strength`, `variant_seed`, `size_variation`
  - methods: `apply_hit_impulse(impulse, at)` (279), `extent()`, `surface_kind()`
  - shakes when near the giant (`_nearness_to_giant`, 446)
- `BreakableProp extends PropBody`: `toughness`, `break_impulse`, `shatter_impulse`, `piece_count`, `rng_seed`, `chip_score 5`, `break_score`; `shatter(push)` (184); `_award` → `add_score` (438).
- Scenes:
  - `crate.tscn`: wood, toughness 1, 15 points
  - `wine_barrel.tscn`: toughness 2, 25 points, port-wine liquid
  - `rubble_block.tscn`: stone, toughness 3, 35 points
- `PropSpawner` (`prop_spawner.gd`):
  - exports: `barrel_count 6`, `crate_count 4`, `rubble_count 4`, `rng_seed`, `x_min`, `x_max`, `edge_z`, `deck_top_y`, `spawn_clearance`, `refill_each_run`, `auto_populate`
  - methods: `populate()` (109), `live_props()`, `lane_bounds()`
  - `KEEP_OUT` is a const (60)
- Also `DebrisPiece.spawn(...)` (MAX_LIVE 40) and `PropMeshKit` static meshes (`crate_body`, `barrel_body`, `rubble_body`, `plank`, `chunk`, …).

**FX:**
- `ImpactFX` (static):
  - `spark(from, at, into, surface, power = 1, seed = 0)` (449)
  - `ground(from, at, surface, radius = 2, power = 1, seed)` (472)
  - `smash(from, at, surface, extent, push, seed, trim, liquid)` (506)
  - `surface_of(node)` (380) reads `fx_surface`, then `surface`, then returns GRANITE for "boss"
  - `impact_row(surface)` (246)
  - `MAX_LIVE 10`
  - seeds derive from position; parents itself to `spawn_root`, else `current_scene` (602)
- `shockwave.gd` (Area3D): exports `damage 14`, `max_radius 15`, `grow_time 0.5`, `knockback 14`, `prop_impulse 38`, `fx_surface`; mask PLAYERS | PROPS.
- `rock_projectile.gd` (RigidBody3D on HAZARDS, mask WORLD | PLAYERS | PROPS): `damage`, `lifetime 5`, `arc_time`, `fx_surface`, `launch(target)` (140).
- `dino_energy` and `dash_trail` are covered in §4.
- Everything spawned at runtime goes under `get_first_node_in_group("spawn_root")`, which main.gd clears on `game_started`.

**PhysicsLayers (`scripts/props/physics_layers.gd`):** `WORLD 1`, `PLAYERS 2`, `BOSS 4`, `PLAYER_PROJECTILES 8`, `HAZARDS 16`, `PROPS 32`.

**CameraRig (`scripts/camera_rig.gd`, created with `CameraRig.new()`):**
- Joins group `camera_rig`. Node chain: Yaw → Pitch → SpringArm3D (sphere r 0.3, mask WORLD) → Camera3D (fov 62).
- Solo: mouse and right-stick orbit, distance 5.6, shoulder offset 0.7.
- Co-op (more than one hero in "players"): follows the centroid, yaw aims at "boss", `_fit_distance` (261) is clamped 8.5–16, pitch -18° to -25°.
- Shake comes only from `GameManager.camera_shake_requested` (`_on_shake_requested`, 456): the max strength wins, seeded RNG `0x5CA1E`, plus roll.
- Victory pulls the arm out by 9.
- Arena bounds or clamps: **absent**. Only the spring-arm collision and the solo shoulder fade (`SAFE_HALF_WIDTH 6.55`) exist.
- Public: `target`, `camera`, `is_group_framing()`.

## 7. UI

**Main menu (`scripts/ui/main_menu.gd`):** everything is built in code. Layers, back to front: `menu_backdrop.gd`, `hero_stage.gd`, `title_logo.gd`, `menu_list.gd`, `menu_modal.gd`, then the curtain.
- `menu_backdrop.gd` uses key art from `res://assets/ui/key_art.png` (`load()`ed at runtime) or a graded ground.
- `hero_stage.gd` (the cut-outs) is skipped when the key art is present.
- `menu_list.gd` (41–52):
  - rows START, DIFFICULTY (an OPTION row with EASY/NORMAL/HARD pills, emits `difficulty_changed`), CONTROLS, CREDITS, and QUIT (not on web)
  - signals `activated(id)` and `difficulty_changed(i)`
  - `_add_row(id, caption, kind, options, colors, start)`
- `menu_row.gd`: a Button with `enum Kind { ACTION, OPTION }`, `setup(...)`, `value_changed`, `set_index`, `step`.
- `menu_modal.gd`: `open(heading, body: Control)`, `close()`, `closed` signal, `build_controls()` (reads the live InputMap per player), `build_credits()` (includes the CC BY attribution).
- No player-count, hero or level select, and no options or volume screen.

**UIStyle (`scripts/ui/ui_style.gd`, static design system):**
- Scales: `enum Scale { DISPLAY…MICRO }`. Elevation: `enum Elev`. Palette consts (`HERO_GREEN`, `BOXY_RED`, `BOSS_AMBER`, `GOLD`, …).
- Factories: `text()`, `title()`, `label()`, `card()`, `surface()`, `plate()`, `button()`, `pill()`, `key_cap()`, `binding_caps(player, actions)`, `event_caption()`, `hint_row()`, `stat_row()`, `scrim()`, `bar()`.
- Actors: `enum Actor { HEROSAURO, SUPERBOXY, ADAMASTOR }` (186), with preloaded portraits (188–190), `actor_name()`, `actor_epithet()`, `portrait_head()`, `portrait_scaled()`.

**HUD (`scripts/ui/hud.gd`):**
- Boss banner: a `PortraitFrame`, `StatBar` (boss variant), name, epithet, phase pips; Adamastor-only.
- `HeroPanel` per roster id (with `AbilityDial` and combo), built on `game_started`.
- Score and time readouts.
- `HitVignette`, `DamageNumbers` (seeded RNG).
- A pause overlay with binding hints.
- Reads only GameManager signals plus the "players" and "boss" groups. `_tick_heroes` (413) polls `get_ability_fraction` and `is_invulnerable`.

**Game over (`game_over.gd`):**
- Waits 2 s (victory) or 1 s (defeat), then shows the art (both heroes on a co-op win, Adamastor on defeat), title, subtitle and stats, and calls `UIProgress.submit`.
- `ui_confirm` → `start_game()`; `ui_cancel` → `go_to_menu()`.

**UIProgress (`ui_progress.gd`):** writes `user://progress.cfg`, section `records`: `best_score`, `best_time`, `wins`. Helpers: `submit(score, seconds, victory) -> bool`, `format_time`, `format_score`.

**Fonts (`assets/fonts`):** `Bangers.woff2` (display only), `Fredoka.woff2`, `Fredoka-Bold.woff2`.

**Localization:** **absent**. No `tr()`, no translation files, and every string is a hard-coded English literal.

**Art (`assets/ui`):**
- `key_art.png` (1672×941)
- `portraits/{herosauro, superboxy, adamastor}.png`
- `art/{banner, figure}_{adamastor, superboxy}.png`: referenced by nothing and excluded from the web export
- There is no Herosauro banner or figure (ROUND4.md "Still missing").

## 8. Audio (`autoloads/audio_manager.gd`)

**Public API:**
- `play_jump`, `play_dino_fire`, `play_dino_hit`, `play_dash`, `play_boss_slam`, `play_boss_hit`, `play_victory`, `play_defeat`, `play_hurt`, `play_land`, `play_rock_throw`, `play_rock_impact`, `play_super_boxy_hit` (323–335)
- `play_boss_roar()` (355)
- `play_prop_hit(surface:int, at = INF)` (368), `play_prop_break(surface, at)` (376)
- `play_fall()` (390), `play_splash(at)` (396)
- `stop_all_sfx()` (511)
- `play_music(track, loop = true, fade = 1.6)` (537), `stop_music(fade)` (599)
- `set_music_volume_db` (614), `set_sfx_volume_db` (619)
- `duck_music(bool)` (636), `duck_music_event(depth, attack, hold, release)` (649)

**SFX ids:** logical string keys (`"jump"`, `"boss_slam"`, …; surface sounds are `"prop_hit_wood"` and similar, built by `_surface_key`). The file table `SFX_FILES` (73) maps ten keys to `assets/audio/sfx/*.wav`. Each loads over a synthesized fallback, and the roar, fall, splash, prop sounds and `dino_fire` are synth-only.
- An unknown key is safe internally: `_play` (421) returns silently when `_streams` lacks it.
- There is no public generic `play(id)`. Calling a missing `play_*` method is a runtime error, which is why `player_base.gd:688` guards with `has_method`.
- 16 pooled voices; the same sound stacks at most 3 times within 45 ms; positional attenuation is relative to the active camera.

**Music:**
- `MUSIC_TRACKS` (204): `title.mp3`, `battle_phase1.ogg`, `battle_phase2.ogg`, `victory.ogg`, `defeat.ogg`.
- An unknown track gives `push_warning` and returns null (668).
- 3-player crossfade. Switching is signal-driven (`_connect_game_signals`, 702):
  - MENU → `title`
  - PAUSED → duck
  - `game_started` → `battle_phase1`
  - `boss_phase_changed` → duck plus `battle_phase2` (2.2 s fade)
  - `game_over` → `victory` (one-shot) or `defeat` (looping)

**Buses:** Master, Music (-4 dB), SFX. Two seeded RNGs.

## 9. Tools and CI

Run all of these from `herosauro-superboxy/`.

**`python3 tools/harness.py check [--timeout 900]`** (322):
1. `godot --headless --import`; fails on any "ERROR" or "SCRIPT ERROR" line (1200 s limit).
2. Renders shot `01_deck_mid` at the fast tier (640×360) under xvfb + lavapipe through `tools/baseline.tscn`.
3. Passes if a decodable PNG exists.

It takes minutes; the review tier is about 3 min per shot. It does **not** run parsecheck or the probes.

**Other harness commands:**
- `capture --out D [--tier review|fast] [--shots a,b] [--kinds world,game,menu] [--renderer forward_plus|gl_compatibility|mobile]`: one process per shot, under `--fixed-fps 60`
- `diff A B [--heatmaps] [--json]`: per-pixel comparison
- `sheet D`
- `verify`: captures twice and diffs
- The shot set is `tools/shots.json`: 10 world shots, 4 game shots (scripted inputs), 1 menu shot.

**`godot --headless --path . tools/parsecheck.tscn`:** loads and `reload()`s every .gd (except the live autoloads), exits 1 if any fail to compile. About 3 s for 94 scripts.

**`godot --headless --path . tools/playtest.tscn --fixed-fps 60 -- --out=/tmp/playtest [--shots]`:**
- Boots main.tscn, calls `start_game`, and drives a ROUTE on both slots (forward, pulsed attacks, special, jump, back off).
- Fails if the boss took no damage, a hero travelled less than 5 m, a hero's y fell below -4, or no heroes appeared.
- Takes seconds headless.

**`godot --path . tools/budget.tscn --rendering-driver vulkan`** (or `--rendering-method gl_compatibility`): preloads bridge_arena only. Prints a census (draw calls, primitives, memory, shadow casters) and a per-vantage sweep over the world shots. Report only; it quits 2 if it has no camera.

**`godot --path . tools/profile.tscn --rendering-driver vulkan --fixed-fps 60 -- --frames=600 --out=/abs/report.json`:**
- Plays a live fight from main.tscn and reports the p50/p95/p99/max distribution.
- Exits 1 if any ceiling is exceeded (`BUDGETS`, 62):

| tier | draw calls p99 | primitives p99 | nodes max | static memory |
|---|---|---|---|---|
| forward_plus | 820 | 3.7M | 900 | 175 MiB |
| gl_compatibility | 540 | 700k | 900 | 140 MiB |

- Hours under software Vulkan, so CI never runs it.

**`.github/workflows/quality.yml`** (runs on push to main and `claude/**`, PRs, manual dispatch):
- **static:**
  - error if a non-comment `Time\.get_ticks_` appears in `scripts/` or `autoloads/` (probes excluded)
  - error on `randomize()`
  - raw `collision_(layer|mask) = [1-9(]` without `PhysicsLayers` only produces a *warning*
  - nothing greps for global `randf`/`randi`, even though ARCHITECTURE.md bans them
- **probes:**
  - import, failing on "SCRIPT ERROR", "Parse Error" or "ERROR: Failed"
  - parsecheck
  - every `scripts/**/_*probe.gd`, run as its .tscn if one exists, otherwise via `--script` (no autoloads); 300 s each
  - probes: audio, boss, fx, coop, props, ui, flow, menu, atmosphere, budget, wreck, facade, landmark, winding, terrain
- **render:** `harness.py check --timeout 900`, playtest (600 s, exit code), `_coop_probe.tscn` (600 s), then uploads the PNGs.

**`.github/workflows/web-export.yml`** (push to main or `claude/**`):
1. Installs Godot 4.7.1 and the export templates.
2. Imports (failures ignored).
3. `godot --headless --export-release "Web" web/index.html`; fails if `index.pck` or `index.wasm` is missing.
4. Renames the payload to `index.<sha12>.*` and rewrites index.html; fails if the grep checks miss.
5. Deploys to gh-pages (force orphan).

## 10. Web build

- **Renderer:** `rendering_method.web = gl_compatibility`. No SSR, SDFGI, SSIL, volumetric fog or TAA; LDR. MSAA and screen-space AA are both 0 on web, so the web build has no anti-aliasing. Shadow atlas is 2048. `WorldTier` gives 2 cascades over 96 m and reduced geometry.
- **Export:** `thread_support = false`, because GitHub Pages cannot send the COOP/COEP headers threads need. Extensions off, S3TC only (no ETC2/ASTC), PWA off. Excludes `assets/models/backdrop/*` (38 MB scan) and `assets/ui/art/*`. The pck is roughly 16–18 MB.
- **Measured cost (PERFORMANCE_BUDGET.md, ROUND4.md):** web is about 479 draw calls, 621k primitives, 768 nodes, 114.7 MiB static at p99, against ceilings of 540 / 700k / 900 / 140. This is roughly 18% of desktop's primitives and 66% of its draw calls.
- **Open problems:**
  1. Load time: the world is built in GDScript on the single WASM main thread, so the build is the load screen.
  2. First-use shader-compile hitches on Compatibility.
  3. Transparent overdraw from 24 cloud clusters and the river shader.
- Frame rate in a real browser has never been measured, and the profiler is not in CI.

## 11. Contract rules for a new subsystem (ARCHITECTURE.md)

- Own one directory. The ownership map is exhaustive, so new directories need a map row. Lead-owned files are `game_manager.gd`, `input_manager.gd`, `main.gd`, `physics_layers.gd`, `tools/`, `project.godot`, `export_presets.cfg` and ARCHITECTURE.md.
- Talk to other subsystems only through GameManager signals and mutators, or group lookups (`players`, `boss`, `camera_rig`, `spawn_root`). Never preload another stream's script to call it.
- A new signal needs a row in the ARCHITECTURE table; the lead adds it to GameManager. Joining a group is a public API.
- No addons, no GDExtension, no downloads. All assets are committed or generated procedurally.
- Every RNG has an explicit `.seed`; no global `randf`/`randi`/`randomize`.
- No `Time.get_ticks_*` in `_process` or `_physics_process`; accumulate `delta`.
- Build geometry once and bake (MeshBaker or MultiMesh). Hundreds of MeshInstance3Ds is a bug.
- Materials are shared: `.duplicate()` before any per-instance change.
- Use `PhysicsLayers` constants, never raw bitmasks. The boss masks WORLD only.
- Roster comes from `active_player_ids()`, never `range(1, n+1)`.
- A new `ToonFactory.Surface` value needs a detail map pair, an fx `impact_row` case and an audio `surface_voice` case in the same commit (probes enforce this).
- Every impact needs all five legs: FX, camera, audio, hit-stop, UI.
- `tools/harness.py check` must pass. A new gate must be shown failing before it is trusted. Any change to what's on screen needs `harness.py diff` numbers recorded in the round doc.

## 12. Biggest risks for the stadium, the city square and a page-reader

1. **"boss" is a single-entity concept.**
   - The Hitbox and Hurtbox "boss" routes feed one global health pool (500) whose zero is victory.
   - The jab volume masks only BOSS | PROPS. Dino Energy has `collide_with_areas = false` and only damages "boss" bodies. Boxy Dash only measures distance to the first "boss" node and calls `damage_boss`.
   - So goblins need a new layer (e.g. ENEMIES) and/or Hurtboxes with a `take_hit`, plus player-stream edits so both specials can hit enemies. Without that, the specials do nothing to goblins.
   - The camera's co-op yaw and the hero recovery direction also key on "boss".

2. **The dragon ally must not join "players".** That group feeds camera framing, `_partner()` and the leash, `_all_heroes_down` (which treats a node without `player_id` as id 1), boss targeting, the rock volley, the HUD and the playtest. It needs its own group, and there is no ally AI to reuse.

3. **Win condition and HUD are boss-shaped.** "Repair N buildings" or "defeat every goblin" needs a new public GameManager mutator and signal (e.g. `objective_progress`), because `_end_game` is private. The HUD boss banner, the game-over copy, the music hooks and UIProgress records all assume Adamastor.

4. **World reuse on PLAY AGAIN.** `_build_world`'s roster-only early return will keep the old arena after a level switch. It must also key on the level id.

5. **Menu flow.**
   - There is no level, player-count or hero select; START always means co-op with two heroes.
   - A lone child gets an idle hero 2 that the leash keeps dragging.
   - Every pad drives P2 and P1 has no pad in co-op, so two kids with two pads won't work.

6. **Constants tuned for the bridge.** Spawns, `KEEP_OUT`, `CULL_Y -6`, `RECOVERY_HALF_WIDTH 5`, `SAFE_HALF_WIDTH 6.55`, the COBBLE landing FX, the boss arena clamp and the playtest's y ≥ -4 check all need parameterizing (full list in §1).
   - The SpringArm collides with WORLD, so tall stadium stands or square facades on WORLD will slam the camera in. Keep tall geometry off WORLD.
   - Both new arenas need perimeter colliders. The fall logic only triggers when there's no floor below.

7. **The night stadium conflicts with the written contract and the lighting stack.**
   - ARCHITECTURE.md mandates "bright high-key daylight" and "recognisably Porto at every step".
   - `LightingRig` is derived from the daylight sun and `porto_daylight.tres` (COMPAT_* constants, sun-relative fills, "Lamps" node, `LAMP_BUDGET 8`). Many floodlights are costly on the Compatibility web tier.
   - The new levels need their own environment, a rig variant, and new capture shots and baselines.

8. **Assets.**
   - No goblin, dragon or panda models exist, and rule 3 forbids downloading at build time.
   - Any new rigged GLB must expose walk/run/attack clips for `bind_animations`' substring matching.
   - The book illustrations (5–10 MB PNGs) live only in Drive. `docs/story/SOURCE.md` is untracked, and the `docs/story/ADAPTATION.md` it references is absent.

9. **Storybook reader.**
   - No `tr()` or localization at all, and Portuguese text needs accented glyphs; Bangers/Fredoka coverage is unverified. menu_row.gd already notes missing glyphs show as tofu on web.
   - `UIStyle.Actor` covers only three actors.
   - Show it inside MENU state, or add a state via the lead.
   - `ui_cancel` and `ui_pause` are both Esc; joypad A is both `ui_confirm` and `p2_jump`.
   - No touch input.
   - Each 1672×941 page is about 6 MiB of RGBA8 in VRAM. Use `load()` rather than `preload` and watch the pck size and the memory ceilings.

10. **Performance and load.**
    - Preloading three arenas in main.gd would build or load all of them at boot on single-threaded WASM.
    - Each level's runtime GDScript build blocks the main thread.
    - The ceilings are a ratchet (web draw-call headroom is about 11%), and the profiler isn't in CI, so regressions won't fail the build.

11. **Determinism.** Goblin waves, AI decisions and repair animations must use seeded RNGs and `delta` accumulation. `hit_stop` sets `Engine.time_scale = 0` globally, which freezes timers and tweens.

12. **Probes.** `_props_probe`, `_boss_probe`, `_coop_probe`, `_flow_probe`, playtest and baseline all boot main.tscn and expect the bridge and Adamastor. The default level must stay the bridge, or these break CI.