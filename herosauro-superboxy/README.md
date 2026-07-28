# Herosauro & Super Boxy: Legends of Porto

A third-person action game built in **Godot 4.7**, set on the **Ponte de Dom Luís I**
over the Douro in Porto. You play **Herosauro**, defending the bridge from
**Adamastor**, the giant of Portuguese myth, while the sun sets over the Ribeira.

![engine](https://img.shields.io/badge/engine-Godot%204.7.1-blue) ![renderer](https://img.shields.io/badge/desktop-Forward%2B%20(PBR%2C%20GI%2C%20SSR)-green) ![web](https://img.shields.io/badge/web-GL%20Compatibility-orange)

## Running it

### Desktop — the quality build

Forward+ gives the full lighting stack: HDR framebuffer, PBR materials, HDRI-style
sky with image-based lighting, real-time GI (SDFGI), SSAO/SSIL/SSR, volumetric fog,
soft shadows and AgX tone mapping.

1. Install **Godot 4.7.1** (standard build) — https://godotengine.org/download
2. Open `project.godot` in the editor and press **F5**.

Headless, from a terminal:

```bash
godot --path . --rendering-driver vulkan
```

To export a standalone binary you need the matching export templates
(*Editor → Manage Export Templates → Download*), then:

```bash
godot --headless --export-release "Linux"   build/linux/herosauro.x86_64
godot --headless --export-release "Windows" build/windows/herosauro.exe
```

### Web — reduced-fidelity preview

The browser build runs on **GL Compatibility** (WebGL 2). Godot cannot export
Forward+ to the web — WebGPU is not implemented — and Compatibility renders 3D into
an **LDR** framebuffer, so the web build has **no** SSR, GI, volumetric fog, TAA or
depth of field. It keeps PBR materials, the HDRI sky, real shadows, SSAO, glow and
tone mapping. The photogrammetry backdrop is skipped there for download size.

The live build is published by CI to the `gh-pages` branch on every push to `main`
or `claude/**`. It is **not** committed to the source tree — a 16 MB `index.pck`
regenerated on two branches is an unmergeable binary conflict on every pull
request. To play it locally, build it yourself:

```bash
godot --headless --import .                              # once, to build the import cache
godot --headless --export-release "Web" web/index.html
python3 -m http.server --directory web 8000              # open http://localhost:8000
```

A plain `file://` open will not work — wasm needs to be served over HTTP.

## Controls

| Input | Action |
|---|---|
| `WASD` | Move (camera-relative) |
| Mouse / right stick | Look |
| `Space` | Jump |
| `Shift` | Sprint |
| `LMB` / `Q` | Attack |
| `RMB` / `E` | Dino Energy special |
| `Esc` | Pause / release mouse |

## Architecture

Code-driven composition keeps scenes small; `main.gd` assembles world, camera, hero,
props and boss at runtime, and everything cross-cutting flows through the
`GameManager` autoload's signals.

```
autoloads/
  game_manager.gd     # state machine, score, combo, health, hit-stop, shake requests
  input_manager.gd    # input abstraction
  audio_manager.gd    # procedural SFX synthesised at startup (no audio files)
scripts/
  toon_factory.gd     # PBR StandardMaterial3D factory, cached and shared
  camera_rig.gd       # third-person SpringArm orbit camera with collision
  players/            # CharacterBody3D hero, camera-relative movement, AnimationTree
  boss/               # Adamastor + FSM, real hitboxes, physics corpse topple
  props/              # Hitbox/Hurtbox components, rigid-body and breakable props
  world/              # bridge geometry, Porto skyline, city backdrop, lighting rig
  fx/ · abilities/ · ui/
assets/
  environments/  porto_golden_hour.tres     # Environment + sky
  textures/      procedural detail normal / roughness+AO maps (NoiseTexture2D)
  shaders/       water_wave.gdshader
  models/backdrop/   photogrammetry city scan (see ATTRIBUTION.md)
tools/
  shotrunner.{gd,tscn}   # headless screenshot harness, fixed vantage points
  playtest.{gd,tscn}     # headless scripted playthrough
```

### Notable systems

- **Materials:** one cached factory builds every procedural material, so dozens of
  Ribeira facades in seven palette colours collapse onto seven materials. Detail
  normal/roughness maps are generated as `NoiseTexture2D` — no binary texture assets.
- **Water:** the Douro's normals are derived analytically from the summed sine
  derivatives, with a Fresnel depth blend, whitecaps and a sun-glint lobe.
- **Renderer-aware lighting:** one Environment authors both tiers; a runtime rig
  strips the Forward+-only effects when running on Compatibility.
- **Procedural audio:** every sound is synthesised from sine/noise envelopes at
  startup — no audio assets ship.

## Third-party assets

The city backdrop is **CC BY 4.0** by **Eduardo Soethe**
([Sketchfab](https://sketchfab.com/3d-models/ponte-de-d-luis-portoportugal-2551868c712942729abe8e5bd6cc318c)).
Full attribution and the list of modifications: `assets/models/backdrop/ATTRIBUTION.md`.

Character and boss models were generated with Meshy.

## Tuning

Most gameplay values are `@export`ed (movement, camera distances and sensitivity,
ability damage/cooldowns, boss timings) or are named constants at the top of each
script.
