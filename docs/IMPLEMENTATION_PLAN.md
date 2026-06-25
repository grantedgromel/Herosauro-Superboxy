# Implementation Plan — Refining Level 1 to a High-Quality Indie Standard

_Project: **Herosauro & Super Boxy: Legends of Porto** (Godot 4.3, GDScript)_
_Scope of this plan: take the **existing first level** (the Dom Luís Bridge fight vs. Adamastor)
from a working MVP to a level that reads as a polished indie game. Additional levels are
explicitly **out of scope for now** — but where a decision affects future levels, it is noted._

---

## 0. How this plan was sourced

The two requested sources — the Godot Asset Library (`godotengine.org/asset-library`) and the
Reddit thread `r/godot/.../11xurxx` — are **blocked by this session's network egress policy**
(both return HTTP 403; the proxy README instructs reporting rather than routing around it). The
Asset Library page is additionally a client-side app that renders no content to a plain fetch.

Equivalent, policy-allowed indexes of the **same** content were used instead:
- [`godotengine/awesome-godot`](https://github.com/godotengine/awesome-godot) — the official curated
  index of Asset-Library plugins/templates.
- A "most-popular Godot 4 addons by GitHub stars" survey and targeted web searches that surfaced the
  specific Asset-Library entries and the template recommendations that thread is known for.

If the literal Reddit comment list is needed, paste its text and it will be folded in; the shortlist
below already covers what that thread surfaces (Maaack templates, GodotSteam, Takin, the official
demo projects, genre starter templates).

---

## 1. Current state (grounded in the code)

**Architecture is healthy.** Code-driven composition; three autoloads (`GameManager`, `AudioManager`,
`InputManager`); a clean signal bus (`GameManager` is the authoritative hub — entities call mutators,
UI/FX react to signals). Real game-feel primitives already exist: hit-stop (`Engine.time_scale`),
screen-shake requests, i-frames, a combo system, and a difficulty scalar. Boss runs an explicit FSM
(`adamastor_state_machine.gd`); there is an AI-ally controller and an action-zoom follow camera.

**Gaps that matter for "high-quality, single-level" polish:**

| # | Gap | Where |
|---|-----|-------|
| A | Boss fight is functional but not yet *memorable* — one hand-rolled FSM, limited telegraphing/variety. | `scripts/boss/adamastor_state_machine.gd` (291 lines) |
| B | Camera framing is hand-tuned and fragile to extend. | `scripts/camera_rig.gd` |
| C | Game-feel is primitive-level (shake/hit-stop exist) but no damage numbers, hit sparks, dissolve, status flashes. | `game_manager.gd`, `scripts/fx/*` |
| D | Audio is **procedural SFX only** — no music, no mix buses. | `autoloads/audio_manager.gd` |
| E | No options menu, no input remapping, no settings persistence. | inputs baked in `project.godot`; no `user://` writes |
| F | No automated tests / scene validation / CI quality gate. | no test dir; PRs are review-validated |
| G | UI strings hardcoded; no localization (notable for a Porto-set game). | `scripts/ui/*` |
| H | Renderer ceiling: GL Compatibility (needed for the web build) caps lighting/post. | `project.godot` `rendering_method="gl_compatibility"` |

---

## 2. Platform & testing decision

**Decision: web-first for iteration; optional desktop (Forward+) build for fidelity checks. Not desktop-only.**

Rationale — this environment is headless with no Godot editor to "Play" in, so the **only friction-free
playtest channel is the web build**, which CI already exports headlessly (Godot 4.3) and publishes to
GitHub Pages on every push to `main` and `claude/**` (`.github/workflows/web-export.yml` +
`deploy-pages.yml`). Open a URL, play. Desktop-only would force download-a-binary-per-OS testing
(plus macOS Gatekeeper/signing) and the agent still couldn't run it for you.

- **Keep** GL Compatibility as the iteration/preview renderer.
- **Optionally add** a parallel Forward+ desktop export to CI that publishes a downloadable Release
  artifact, *only* when you want to evaluate premium lighting/post. Most Level-1 polish (encounter
  design, juice, audio, UI) lands fine in Compatibility; the renderer is not on the critical path.

---

## 3. Asset & infrastructure shortlist (mapped to gaps; framework-adopting posture)

Verdict: **Adopt** = wire in · **Reference** = copy the pattern, no dependency · **Optional/Later**.
Every adopted dependency must be **verified to export to Web** before it lands (the iteration build
depends on it).

### Boss/AI & camera — the heart of a one-level action game
| Asset | Gap | Verdict | Note |
|---|---|---|---|
| [**LimboAI**](https://github.com/limbonaut/limboai) — behavior trees + HSM, visual editor & debugger | A | **Adopt** | Rebuild Adamastor as an authored, debuggable tree with richer phases/telegraphs. Confirm web-export build. |
| [**Beehave**](https://github.com/bitbrain/beehave) — GDScript behavior trees | A | Fallback | Pure-GDScript alternative if LimboAI's GDExtension complicates the web export. |
| [**Phantom Camera**](https://github.com/ramokz/phantom-camera) — declarative Camera3D targets/framing | B | **Adopt** | Replaces/augments `camera_rig.gd`; cinematic boss framing, phase-2 reveal. |

### Game feel / VFX — the "premium" reads
| Asset | Gap | Verdict | Note |
|---|---|---|---|
| [**Juicee**](https://github.com/Kelpekk/Juicee) / [**Shaker**](https://github.com/Eneskp3441/Shaker) — shake/hit-stop/property shakes | C | **Reference** | You have primitives; cherry-pick the graph-driven effects. |
| [**GODOT-VFX-LIBRARY**](https://github.com/haowg/GODOT-VFX-LIBRARY) — combat/status/post shaders | C | **Reference** | Hit-flash, freeze, burn, dissolve, combo rings, impact sparks (2D-built; reuse shaders/concepts in 3D). |
| [**Godot-Trail-System**](https://github.com/OBKF/Godot-Trail-System) | C | Optional | Upgrade `dash_trail.tscn`. |
| [godotshaders.com](https://godotshaders.com/) | C,H | **Reference** | Post, dissolve, water; mind Compatibility limits. |

### The "frame of a real game" — menus, options, persistence
| Asset | Gap | Verdict | Note |
|---|---|---|---|
| [**Maaack's Game Template**](https://github.com/Maaack/Godot-Game-Template) — menus/options/pause/credits/settings | E | **Reference** | Graft its options + settings-persistence flow onto the existing menu. |
| [**Input Helper**](https://github.com/nathanhoad/godot_input_helper) — device detection + remapping | E | **Adopt** | Required for a real controls screen + robust couch co-op. |
| [**Takin Godot Template**](https://github.com/TinyTakinTeller/TakinGodotTemplate) — save + localization reference | E,G | **Reference** | Pattern source for a small `user://` settings/best-time save. |

### Audio, localization, tooling
| Asset | Gap | Verdict | Note |
|---|---|---|---|
| [**Event Audio**](https://github.com/bbbscarter/event-audio-godot) | D | **Reference** | Cleaner than the round-robin pool; add Master/Music/SFX buses. |
| Godot **built-in CSV/PO localization** (+ [PowerKey](https://github.com/phosxd/PowerKey) for dynamic vars) | G | **Adopt** | EN baseline, PT-PT second — cheap and on-theme. |
| [**GUT**](https://github.com/bitwes/Gut) or [**GdUnit4**](https://github.com/MikeSchulze/gdUnit4) | F | **Adopt** | Headless regression net in existing CI. |
| [**Godot Doctor**](https://github.com/codevogel/godot_doctor) — scene/resource validation | F | **Adopt** | Cheap pre-runtime error catch in CI. |
| [**Signal Lens**](https://github.com/yannlemos/signal-lens) — signal-connection debugger | dev | Optional | Useful for this signal-heavy design. |
| [**GodotSteam**](https://github.com/GodotSteam/GodotSteam) | dist | Optional/Later | Only if Steam ships; out of single-level scope. |

### Content sourcing (you already use Meshy)
Quaternius / Kenney / Poly Haven for props, materials, audio; CC-licensed music for the combat track.
Terrain3D is **not** needed for a bridge-arena level.

---

## 4. The plan — phases (single-level focus)

Each phase is independently shippable so the live web preview never regresses. Every adopted addon is
web-export-verified before merge.

### Phase 0 — Quality gate & guardrails (foundation)
- Add **GUT/GdUnit4** + **Godot Doctor** to the existing GitHub Actions workflow; headless smoke test
  (boot → spawn → boss to phase-2 → death → victory) gates every later change.
- Move the handful of UI strings behind Godot's **built-in localization** (EN now, PT-PT stub).
- _Outcome:_ changes are regression-guarded; localization is free from here on.

### Phase 1 — Make the boss fight *great* (the core of a one-level game)
- Rebuild Adamastor's brain on **LimboAI** (fallback **Beehave**): clearer attack telegraphs, more
  attack variety, readable phase-1 → phase-2 escalation, recovery windows that reward aggression.
- Tune the encounter loop: pacing, punish/reward windows, fairness of slam/rock tells, difficulty
  curve across Easy/Normal/Hard (the `difficulty_scalar` already exists).
- Optional light touch: extract the level's spawn/boss/music into a small `LevelConfig` resource so
  Level 1 isn't hardcoded forever (keeps the door open for future levels at near-zero cost).
- _Outcome:_ a fight worth replaying — the single most important lever for a one-level game.

### Phase 2 — Juice & audiovisual high-grade
- Adopt **Phantom Camera** for cinematic framing (tight duo framing, boss-engage reveal, phase-2 push).
- Formalize hit-stop/shake (Juicee/Shaker patterns); add **damage numbers**, **hit sparks**,
  **hit-flash / freeze / phase-2** status shaders, and a **dissolve** on boss death (VFX-library refs).
- Add **real combat music** with explore → fight → phase-2 → victory transitions, **mix buses**, and a
  richer SFX set; keep procedural audio as fallback.
- _Outcome:_ the level *feels* premium on every hit.

### Phase 3 — The "real game" frame around the level
- **Options menu**: Master/Music/SFX volume, fullscreen/resolution, **control remapping** (Input
  Helper), accessibility toggles (screen-shake intensity, hit-stop off).
- **Settings + best-time persistence** to `user://` (small save, Takin pattern); polished pause and
  win/lose flow.
- _Outcome:_ the level is wrapped in the menus/options players expect from a shipped indie.

### Phase 4 — Ship-readiness for the slice
- Controller-first UX pass, accessibility pass, performance budget on the web build.
- _Optional:_ add the **Forward+ desktop CI artifact** so you can judge the premium-lighting tier
  natively; if Steam later, layer **GodotSteam**.
- _Outcome:_ a polished, demoable vertical slice.

**Sequencing rationale:** Phase 0 makes the rest safe; Phase 1 (the boss fight) is where a single-level
game lives or dies, so it precedes cosmetic juice; Phases 2–3 are the polish and the frame; Phase 4 is
readiness. Multi-level work, if ever pursued, starts from the optional `LevelConfig` seed in Phase 1.

---

## 5. Risks & checks
- **Web-export compatibility of GDExtension addons** (LimboAI especially) — verify the addon ships web
  templates before adopting; Beehave (pure GDScript) is the fallback.
- **GL Compatibility visual ceiling** — no SDFGI/volumetrics/advanced glow; lean on emissive + custom
  shaders for "glow," or gate the premium look behind the optional Forward+ desktop build.
- **Dependency creep** — each addon must earn its place against a clear gap above and pass the headless
  smoke test in CI.

---

## 6. Sources
- [godotengine/awesome-godot](https://github.com/godotengine/awesome-godot) (curated Asset-Library index)
- [Most-popular Godot 4 addons by stars](https://garciamarquez.dev/posts/godot-popular-assets/)
- [Best Godot Plugins 2025 — GodotAwesome](https://godotawesome.com/best-godot-plugins-2025/)
- [GODOT-VFX-LIBRARY](https://github.com/haowg/GODOT-VFX-LIBRARY)
- Requested but **blocked by egress policy (HTTP 403):** `godotengine.org/asset-library/asset`,
  `reddit.com/r/godot/comments/11xurxx/...`
