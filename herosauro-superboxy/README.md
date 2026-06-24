# Herosauro & Super Boxy: Legends of Porto

A 3D local co-op action game built in **Godot 4.3** (GDScript), rebuilt from the
original single-file Three.js / Cannon.js prototype into a clean, modular, polished
indie-style project.

Two pint-sized superheroes defend the **Dom Luís Bridge** over the Douro in Porto
from **Adamastor**, a giant rocky stone golem, while the sun sets over the city.

![toon style](https://img.shields.io/badge/style-toon%20cel--shaded-orange) ![engine](https://img.shields.io/badge/engine-Godot%204.3-blue) ![renderer](https://img.shields.io/badge/renderer-GL%20Compatibility%20(Web)-green)

## Characters

| | Hero | Player | Ability | Controls |
|---|------|--------|---------|----------|
| 🦖 | **Herosauro** (Rui) | P1 | **Dino Energy** — green energy projectile (50 dmg) | `WASD` move · `Shift` jump · `E` ability |
| 🥊 | **Super Boxy** (Kiko) | P2 | **Boxy Dash** — gravity-defying lunge (25 dmg, combos) | `Arrows` move · `/` jump · `Space` ability |

Gamepads are also mapped (P1 = device 0, P2 = device 1; left stick to move, South/West
face buttons for jump/ability).

**Boss — Adamastor:** patrols the bridge, periodically **slams** the ground (expanding
shockwave) and **hurls rocks** at the nearest hero. At 50% health he enters **Phase 2**,
turning red and attacking faster with double rock throws. Defeat him to win; if both
heroes fall, Porto is lost.

## Running the project

1. Open Godot 4.3 (stable) and import this folder (`project.godot`).
2. Press **F5** (or the Play button). The main scene is `scenes/main.tscn`.
3. On the title screen, press **ENTER** to start. `ESC` pauses.

## Exporting for Web (HTML5) — the primary target

The project renders with the **GL Compatibility** backend so it runs in browsers via
WebGL 2. A `Web` export preset is included (`export_presets.cfg`), and a **prebuilt,
ready-to-host HTML5 build is committed under [`web/`](web/)** (no-threads variant, so it
needs no special COOP/COEP headers and works on any static host, e.g. GitHub Pages).

```bash
# Play the prebuilt version locally:
python3 -m http.server --directory web 8000   # then open http://localhost:8000
```

To rebuild it yourself:

```bash
# One-time: install the matching export templates via the Godot editor
#   Editor → Manage Export Templates → Download (4.3.stable)
# Then export headlessly:
mkdir -p build/web
godot --headless --export-release "Web" build/web/index.html
# Serve it (a plain file:// won't work for wasm):
python3 -m http.server --directory build/web 8000
# open http://localhost:8000
```

## Architecture

Code-driven composition keeps every scene small and self-contained; `main.gd`
assembles the world, camera, players, boss and UI at runtime. All cross-cutting
events flow through the `GameManager` autoload's signals.

```
autoloads/
  game_manager.gd     # state machine (MENU→PLAYING→PAUSED→VICTORY/DEFEAT), score,
                      # combo, health, signals, hit-stop, screen-shake requests
  input_manager.gd    # per-player Input Map abstraction
  audio_manager.gd    # procedural SFX synthesised into AudioStreamWAV (no audio files)
scripts/
  toon_factory.gd     # builds consistent toon + outline ShaderMaterials
  camera_rig.gd       # co-op follow camera, screen shake, victory zoom-out
  main.gd             # root composition + UI state wiring + pause input
  players/player_base.gd   # movement: coyote time, jump buffer, variable jump,
                           # facing, i-frames, knockback, fall respawn, cooldowns
  players/herosauro.gd · superboxy.gd
  abilities/dino_energy.gd · boxy_dash.gd
  boss/adamastor.gd · adamastor_state_machine.gd   # explicit IDLE/SLAM/ROCK/PHASE_TWO FSM
  fx/shockwave.gd · rock_projectile.gd
  world/bridge_arena.gd · sky_background.gd
  ui/main_menu.gd · hud.gd · game_over.gd
assets/
  shaders/   toon.gdshader · toon_outline.gdshader · water_wave.gdshader
  materials/ toon_player1/2 · toon_boss · toon_bridge (.tres)
```

### Notable systems
- **Toon look:** a cel-banded lighting shader plus an inverted-hull outline pass,
  composed at runtime by `ToonFactory` so every procedurally-built mesh matches.
- **Game feel:** hit-stop on boss hits, screen shake on slams, white hit-flash,
  1.5 s invulnerability with mesh flicker, knockback impulses.
- **Procedural audio:** every sound effect (jumps, hits, slams, fanfares) is
  synthesised from sine/noise envelopes at startup — no audio assets shipped.
- **Procedural world:** the bridge arch, railings, Porto skyline and drifting clouds
  are generated in code; the Douro ripples via a vertex + UV-scroll water shader.

## Tuning

Most gameplay values are `@export`ed (player speeds/jump, ability damage/cooldowns,
boss attack timings) or are named constants near the top of each script, so they are
easy to tweak in the Inspector or in code.
