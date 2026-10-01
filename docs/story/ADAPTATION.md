# The storybook adaptation: design and contracts

**Read this, `ARCHITECTURE.md` and `docs/story/CODEMAP.md` before writing code.**
This file is the coordination mechanism for the storybook build, the same way
ARCHITECTURE.md is for the engine. Where the two disagree, this file wins for
the new work and ARCHITECTURE.md wins for everything else. Function signatures
below are contracts: implement them exactly, call them exactly.

## What we are making

*As Aventuras de Herosauro & Super Boxy*, a storybook action game for children
aged 4 to 8, playable in a web browser, alone (with the other brother as an AI
companion) or co-op on one machine. The owner's picture book is the spine: each
chapter is a book story, told in page-turn scenes with narration, with a short
playable level in the middle.

| # | chapter id | story | level | play |
|---|---|---|---|---|
| 1 | `adamastor` | the giant breaks the Douro bridges | the existing Ponte D. Luís fight | boss fight, kid-tuned |
| 2 | `dragao` | goblins steal the cups from the Estádio do Dragão | a floodlit football stadium at night | free the dragon, bowl goblins over with footballs, win back the cups |
| 3 | `pandas` | panda tourists have nowhere to stay | a run-down Porto street | magically repair houses, find the pandas' suitcases, no enemies |

Text, page ids and objectives live in `scripts/story/story_data.gd`
(`StoryData`). The canon it comes from is `docs/story/SOURCE.md`.

## Kid rules (non-negotiable, from `KIDS_DESIGN_RESEARCH.md`)

1. **Never fail.** With Ajudas on (the default) there is no DEFEAT state, no
   lives, no timers. A hero at 0 health floats in a bubble for 2 s and pops
   back at full health next to the partner. Falling off: same bubble, no penalty.
2. **Voice first, icon first.** Every page and every objective is spoken
   (text-to-speech, or a recorded file when one exists). Text is support, in
   PT-PT by default with a live English toggle.
3. **Few buttons.** Move, jump, attack, power. No holds, no mashing, no combos
   required. Attacks auto-aim at the nearest target in front.
4. **The camera drives itself.** Manual camera is optional, never needed.
5. **Positive feedback only.** No buzzers, no "you lose". A miss is a soft
   sound. Progress only ever goes up.
6. **Mischievous, never scary.** Goblins giggle and tumble; nothing bleeds,
   dies or cries. Defeated goblins get dizzy and are carried off.
7. **Motion safety.** "Menos movimento" turns screen shake down to 20% and
   removes white flashes. No full-screen flash ever exceeds 3 per second.
8. **Short chapters.** 5 to 8 minutes of play, skippable pages, autosave.
9. **Nothing leaves the device.** No accounts, no analytics, no external links,
   no ads.
10. **Targets are big.** Every on-screen button is at least 76 px tall at 720p.

## Flow

```
Toca para começar ─► Estante (3 book covers) ─► who's playing? (1 or 2)
   ─► intro pages ─► level (HUD: objective + story beats) ─► VICTORY
   ─► outro pages ─► sticker on the cover ─► Estante (next chapter highlighted)
```

The reader and bookshelf run while GameManager is in `MENU` (and the outro in
`VICTORY`); no new GameManager state is added.

## Ownership for this build

The table in ARCHITECTURE.md still holds. New rows:

| stream | owns |
|---|---|
| `spine` (lead's delegate) | every lead-owned file, `scripts/story/`, `scripts/levels/level_base.gd`, `tools/`, probes that must change because of the contracts below; for this build also `scripts/players/`, `scripts/abilities/`, `scripts/props/hitbox.gd`, `scripts/props/hurtbox.gd`, `scripts/camera_rig.gd`, `scripts/boss/` (kid tuning only) |
| `ui` | `scripts/ui/`, `scenes/ui/`, `assets/ui/`, `assets/fonts/`, `assets/story/` |
| `level_dragao` | `scripts/levels/dragao/`, `scenes/levels/dragao/` |
| `level_pandas` | `scripts/levels/pandas/`, `scenes/levels/pandas/` |
| `audio` | as before, plus the SFX ids below |
| `touch` | `scripts/ui/touch/`, `scenes/ui/touch/` (carved out of `ui` for wave 3) |

## Contracts

### GameManager (implemented by `spine`)

```gdscript
signal chapter_changed(chapter_id: String)
signal objective_changed(label: Dictionary, done: int, total: int)  # label = {"pt": ..., "en": ...}
signal objective_progress(done: int, total: int)
signal story_beat(beat_id: String)       # HUD shows StoryData beat with that id
signal settings_changed()

var chapter_id: String = "adamastor"     # default stays the bridge; probes depend on it
var language: String = "pt"              # "pt" | "en"
var assists: bool = true                 # "Ajudas"
var reduce_motion: bool = false
var narration: bool = true
var companion: bool = true               # solo play spawns the other brother as AI

func set_chapter(id: String) -> void
func set_language(lang: String) -> void
func set_assists(on: bool) -> void
func set_reduce_motion(on: bool) -> void
func set_narration(on: bool) -> void
func set_companion(on: bool) -> void
func is_ai(player_id: int) -> bool       # true for the AI-driven brother in solo
func set_objective(label: Dictionary, total: int) -> void
func advance_objective(amount: int = 1) -> void   # clamps; emits objective_progress
func objective_done() -> int
func objective_total() -> int
func complete_chapter() -> void          # public victory: VICTORY + game_over(true)
func request_story_beat(beat_id: String) -> void
func hero_damage_scale() -> float        # 0.5 with assists, 1.0 without
```

Settings (language, assists, reduce_motion, narration, companion, music and
SFX volume) persist to `user://settings.cfg`, loaded in `_ready`.
`request_shake` scales strength by 0.2 when `reduce_motion` is on.
`active_player_ids()` returns `[1, 2]` whenever the companion is on, so every
existing roster consumer keeps working; `is_ai()` says which one is the robot.

### Levels

`main.gd` keeps the bridge path exactly as it is for `adamastor`. Any other
chapter loads `res://scenes/levels/<id>/<id>_level.tscn` with `load()` (never
`preload`), instances it under `World`, and spawns heroes and the CameraRig
as today. It does not spawn Adamastor or the bridge PropSpawner for them.
`_build_world`'s early return must also compare the chapter id.

A level root extends `LevelBase` (`scripts/levels/level_base.gd`, owned by
`spine`), joins group `level`, and overrides what it needs:

```gdscript
class_name LevelBase extends Node3D
func spawn_point(player_id: int) -> Vector3          # required
func camera_focus() -> Vector3                       # where the co-op camera looks when there is no boss
func kill_y() -> float                               # below this a hero bubbles back; default -20
func ground_surface() -> int                         # ToonFactory.Surface for landing FX; default COBBLE
func music_track() -> String                         # AudioManager track id; default "battle_phase1"
func begin() -> void                                 # called on game_started after heroes exist; set the objective here
func hint_target() -> Vector3                        # where the idle hint arrow points; INF = none
```

A level owns its WorldEnvironment, lights, geometry, colliders, enemies,
NPCs and objective logic, and reports progress only through the GameManager
mutators above. Everything it spawns at runtime goes under `spawn_root`.

### Things heroes can hit (implemented by `spine`)

`PhysicsLayers.TARGETS = 64`. Anything hittable that is not the boss and not a
`PropBody` is a `Hurtbox` (Area3D) on layer `TARGETS` whose target implements

```gdscript
func take_hit(amount: float, knockback: Vector3) -> void
```

and whose root joins group `targets` (for auto-aim and the companion AI). The
hero jab, Dino Energy and Boxy Dash all reach `TARGETS`. Footballs, crates and
anything else physical stay `PropBody`, which heroes already knock around.

Enemies that touch heroes use the existing `Hitbox` "players" route.

### Input (implemented by `spine`)

- P1 moves with WASD **or the arrow keys**; jump Space; attack J or Q or left
  click; power K or E or right click. P2 keeps its own keys.
- Gamepad device 0 drives P1, device 1 drives P2; in solo any pad drives P1.
- Virtual input, for the companion AI and the touch overlay:

```gdscript
func set_virtual_move(player_id: int, v: Vector2) -> void   # pad space, like get_move_vector
func press_virtual(player_id: int, action: StringName) -> void   # &"jump" | &"attack" | &"ability"; reads as just_pressed once
func set_virtual_held(player_id: int, action: StringName, held: bool) -> void
```

### Audio (generic id API by `spine`, sounds by `audio`)

```gdscript
AudioManager.play_sfx(id: StringName, at: Vector3 = Vector3.INF) -> void   # unknown id = silent
```

Reserved ids: `ui_tap page_turn star objective_done bubble_pop cup_collect
goblin_hit goblin_giggle ball_kick rope_snap dragon_roar dragon_fire
magic_repair panda_cheer suitcase`. A stream may call any of them before the
sound exists.

### Story art

`StoryData` page `art` paths point under `res://assets/story/`. The images are
not committed yet; the reader composes a page from committed art when one is
missing and must never error on it. When the owner adds the book pages,
`tools/import_story_art.py` (owned by `ui`) converts a folder of the Drive PNGs
into 1600 px WebP at those paths.

## Definition of done for any stream

- `godot --headless --path . tools/parsecheck.tscn` passes.
- Every existing probe still passes, or was changed on purpose with the reason
  written in the commit.
- `godot --headless --path . tools/playtest.tscn --fixed-fps 60 -- --out=/tmp/pt` passes.
- The determinism, baking, material and layer rules of ARCHITECTURE.md hold.
- New behaviour has a probe that was watched failing first (ARCHITECTURE rule 9).
- Work is committed on the branch you were given, with a message that says
  what changed and why.
