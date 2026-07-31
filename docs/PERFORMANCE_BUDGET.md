# Render budget — measured

Two tiers, two budgets. Desktop runs Forward+ and is the quality target; the web
build runs GL Compatibility and is now a **genuinely reduced build**, not the same
scene with the post-processing switched off.

Everything below is produced by `tools/budget.tscn` against
`scenes/world/bridge_arena.tscn`, plus a cascade probe described under
"Triangles submitted to shadow". Run it per tier:

```bash
# desktop
godot --path . tools/budget.tscn --rendering-driver vulkan
# what the browser actually builds
godot --path . tools/budget.tscn --rendering-method gl_compatibility
```

The second command is the important one and it did not exist before. `--headless`
always reports `forward_plus`, so every probe and every capture in `tools/` takes
the desktop path; asking for the renderer explicitly is the only way to measure
the tier the owner is complaining about.

## The two tiers

| Metric | Forward+ (desktop) | GL Compatibility (web) |
|---|---|---|
| MeshInstance3D | 178 | 209 |
| Surfaces (≈ draw calls, geometry) | 178 | 209 |
| …of which cast shadows | 130 | 100 |
| MultiMeshInstance3D | 7 (604 instances) | 7 (604 instances) |
| Lights | 4 (1 directional + 3 fills) | 4 |
| Collision bodies | 11 | 11 |
| **Triangles in the scene** | **1,095,335** | **406,179** |
| **Triangles that cast** | **551,316** | **104,891** |
| **Triangles submitted to shadow, per frame** | **2,196,722** | **199,795** |
| Texture memory | 48.0 MiB | 15.1 MiB |
| Buffer memory | 76.9 MiB | 37.3 MiB |
| Video memory | 141.9 MiB | 52.3 MiB |

Shadow submission is measured at the `01_deck_mid` camera; the other vantages are
within 1%.

## Per-frame counters, every vantage, both tiers

This is what `tools/profile.gd`'s budget gate is written against, and until
`4b20430` none of it existed: `tools/budget.gd` printed objects, draw calls and
primitives as **0** on every run it had ever done, because `budget.tscn`
contained no `Camera3D` and nothing rendered 3D. It now stands a camera at every
`world` vantage in `tools/shots.json` — the same manifest the review gate
renders — and sweeps them.

Static arena, no heroes, no giant, no FX. 1280×720, llvmpipe.

| shot | Forward+ objects | Forward+ prims | Compat objects | Compat prims |
|---|---|---|---|---|
| `01_deck_mid` | 575 | 3,261,457 | 245 | 524,577 |
| `02_deck_eye` | 447 | 3,251,645 | 226 | **574,730** |
| `03_rail_macro` | 393 | 3,200,929 | 176 | 555,740 |
| `04_cobble_macro` | 500 | 3,253,111 | 242 | 568,102 |
| `05_arch_under` | 570 | 3,215,849 | 267 | 538,669 |
| `06_river_wide` | 482 | 3,160,731 | 266 | 523,811 |
| `07_ribeira` | 477 | 3,223,291 | 206 | 524,549 |
| `08_gaia_end` | 380 | 3,232,715 | 182 | 570,988 |
| `09_water_close` | 527 | 3,194,551 | 220 | 491,409 |
| `10_skyline_high` | 508 | 3,131,571 | 297 | 522,678 |
| **worst** | 575 | **3,261,457** | 297 | **574,730** |

Draw calls equal objects in every row on both tiers.

**The web tier costs 17.6% of the desktop tier's worst-case primitives and 39%
of its draw calls.** That is the geometry tier, measured end to end rather than
inferred from the levers.

### The finding: primitives barely respond to the camera

On Forward+, objects range 380–575 across the ten vantages — a 51% spread — and
primitives range 3,131,571–3,261,457, a spread of **4.1%**. `03_rail_macro` is a
camera half a metre from a railing at 45° FOV and it still submits 3.2M
primitives, **2.9× the world's entire triangle count**.

The cascades are anchored to the camera's frustum slices, not to what the camera
is looking at, and the bridge is inside all four of them from every vantage in
the arena. Four cascades plus the colour pass is five potential submissions per
caster, and `directional_shadow_blend_splits = true` adds a sixth for anything
near a split boundary.

This is the same root cause as the web-tier finding below — bakes whose AABBs
are too large to cull — on the tier that fix did not touch. On Compatibility the
spread is 17%, four times better, which is the chunking letting culling bite.

**Not acted on.** Every lever (fewer cascades, `blend_splits` off, `cast_shadow`
off on far bakes, visibility ranges) trades a measurable win for a visual cost
that has to be scored, not assumed, and three rounds of lighting work sit on the
desktop image. It is recorded so the next round starts from a number.

## How the web tier got there

The web build used to be the desktop scene minus the post effects: 669,977
triangles (the photogrammetry backdrop already excludes itself) with the same 130
casters and the same four cascades, i.e. **2.19 million triangles re-rendered per
frame for shadows alone**. Four levers, in the order they pay:

| lever | triangles | shadow submission |
|---|---|---|
| starting point (web, before) | 669,977 | 2,196,722 |
| + bake split and ring shadow gate | 669,977 | **407,685** |
| + cascades 4 → 2, reach 260 m → 96 m | 669,977 | **199,795** |
| + facade detail and returns by distance | **454,419** | 199,795 |
| + river retessellation | **406,179** | 199,795 |

The first two do not remove a single triangle from the scene and are worth more
than the two that do. That is the whole finding of this pass and it is worth
stating plainly:

> **The bakes were too big to cull.** `MeshBaker` welds a whole district into one
> surface per material, which is what makes the detail affordable in draw calls —
> and `Ribeira_1` came out as 169,936 triangles in a single instance whose world
> AABB spans (-136, -9, -126) .. (100, 31, 32). Godot culls and shadow-maps an
> instance against its AABB **as a unit**, so a surface that size is inside every
> frustum and every shadow cascade for as long as any part of the city is on
> screen. Probed against the shot cameras, **98.6% of all shadow-casting geometry
> landed in cascade 0** — the 26 m box around the player.

Until that is fixed, no distance lever does anything, which is why the shadow
distance sweep below reads as flat as it does.

`WorldTier` (`scripts/world/world_tier.gd`) is where every reduced-tier number
lives. On Forward+ each one collapses to "off", so the desktop scene is built by
byte-identical code paths — proven below.

## Triangles submitted to shadow

The number `budget.tscn` cannot report and the one that decides this frame. Each
directional cascade is a **full geometry re-render** of everything that casts into
it, so the cost is (casters in cascade) × (cascade count), not (casters).

Measured by walking the scene, bounding each cascade's frustum slice with the
sphere Godot uses, and testing every caster's AABB against that sphere projected
along the light — i.e. a disc in light space, unbounded along the light axis,
which is exactly the set Godot submits.

**Desktop, sweeping `directional_shadow_max_distance` on the current scene:**

| max_distance | 01_deck_mid | 07_ribeira | 06_river_wide |
|---|---|---|---|
| 80 m | 2,184,498 | 2,184,618 | 2,072,156 |
| 100 m (Godot default) | 2,188,828 | 2,188,972 | 2,078,390 |
| 160 m | 2,190,946 | 2,190,900 | 2,084,770 |
| **260 m (current)** | **2,196,722** | **2,196,746** | **2,138,040** |

**100 m → 260 m costs 0.36% on both review shots and 2.9% on the widest one.**
It is not the regression it looked like, and it should stay: it is what gives the
Ribeira terraces inter-building shading, and the reason it is nearly free is the
uncullable-bake problem above — the cascades were already carrying the entire
city at 100 m.

Two consequences worth keeping:

- If the bake split is ever brought to the desktop tier, **re-measure this**. The
  sweep is flat because nothing can be culled; make culling work and this becomes
  a real lever again.
- The lever that actually moved the web tier was not distance, it was *which
  surfaces cast at all*. See `WorldTier.SHADOW_RADIUS`.

## What the web tier skips that desktop keeps

| | desktop | web |
|---|---|---|
| Photogrammetry backdrop (425,358 tris) | yes | no — self-gates, and the export strips the asset |
| SDFGI / SSR / SSIL / volumetric fog | yes | no — `lighting_rig.gd`, unchanged by this pass |
| Background shadow casters past 66 m | yes | no |
| Shadow cascades | 4, to 260 m | 2, to 96 m |
| Ribeira detail past 78 m | FULL | MEDIUM |
| Ribeira detail past 110 m | FULL/MEDIUM | LOW |
| Flank and rear elevations past 90 m | yes | no |
| Washing past 90 m | yes | no |
| River tessellation | 178 × 178 (64,082 tris) | 88 × 88 (15,842 tris) |

Nothing in that list changes massing, roofline, colour, silhouette or placement.
What goes is sub-pixel: shutter leaves, balcony balusters, string courses, window
reveals, tile panels, and elevations that face a party wall five centimetres away.

**One honest consequence.** The facade emitters draw from a shared
`RandomNumberGenerator` as they build, and the LOW and MEDIUM paths consume fewer
draws than FULL. So the web tier's Porto is not the desktop city with detail
removed — it is a *different draw from the same seed*, still deterministic, still
the same palette, plot plan and skyline, but house-for-house the colours and
window counts differ. Fixing that means giving every building its own seeded RNG,
which would change the desktop city and cost a full re-review. Not worth it.

## Memory

52.3 MiB on the web tier for the world is a non-issue. The UI art was a real
one, and the first pass over it got the size wrong twice over. Measured from
each file's IHDR, with `mipmaps/generate` checked rather than assumed:

| file | size | RGBA8 | loaded by |
|---|---|---|---|
| `assets/ui/key_art.png` | 1672×941 | 6.00 MiB | `menu_backdrop.gd` |
| `assets/ui/portraits/adamastor.png` | 631×900 | 2.17 MiB | `ui_style.gd` |
| `assets/ui/portraits/herosauro.png` | 282×900 | 0.97 MiB | `ui_style.gd` |
| `assets/ui/portraits/superboxy.png` | 209×900 | 0.72 MiB | `ui_style.gd` |
| `assets/ui/art/banner_adamastor.png` | 1672×941 | 6.00 MiB | **nothing** |
| `assets/ui/art/banner_superboxy.png` | 1672×941 | 6.00 MiB | **nothing** |
| `assets/ui/art/figure_adamastor.png` | 1024×1536 | 6.00 MiB | **nothing** |
| `assets/ui/art/figure_superboxy.png` | 1024×1536 | 6.00 MiB | **nothing** |

The earlier figure of "~45 MiB, against 52 MiB for the entire world" was wrong
in two independent ways, and both inflated it:

* **Mipmaps were assumed, not checked.** All eight import with
  `mipmaps/generate=false`, which is Godot's default for 2D textures. The base
  level is the whole cost, so a 1672×941 plate is 6.00 MiB and not 7.98.
* **Four of the eight are referenced by nothing** — no `.gd`, no `.tscn`, no
  `.tres`. They never load, so they were never in VRAM. They were pck weight,
  which is a different problem needing a different fix.

The honest totals: **33.9 MiB** if everything were resident, **9.9 MiB**
actually resident. Both are worth fixing and both now are. All eight moved to
`compress/mode=2` in `19b521d` (these are painterly plates viewed at or near
native size — the block artifacts have nothing crisp to chew on), and the four
unreferenced ones are excluded from the web pck in `4b20430`.

Nothing about the conclusion changes; the size of it does. Quoting a number
four times too big to justify a change that was right anyway is how a rubric
ends up being optimised instead of a game.

## Texture compression and the export preset

One texture in the whole project is VRAM-compressed (`compress/mode=2`):
`assets/models/backdrop/porto_backdrop_0.webp`. Everything else is Lossless, and
the detail maps are `NoiseTexture2D` generated at load. So:

- The Web preset's `vram_texture_compression/for_mobile=false` **costs nothing
  today**, because the only VRAM-compressed texture in the project is inside
  `exclude_filter="assets/models/backdrop/*"` and never ships to web.
- It is still wrong, and latently expensive. `project.godot` already sets
  `textures/vram_compression/import_etc2_astc=true`, so the ETC2/ASTC variants
  are being *built* at import and then thrown away at export. A mobile browser
  exposes `WEBGL_compressed_texture_etc`/`astc`, never S3TC, so the first texture
  anyone switches to VRAM Compressed will decompress to RGBA8 on every phone.
  Setting `vram_texture_compression/for_mobile=true` on the Web preset costs pck
  size only when there is something to compress, which is currently nothing.
- `texture_format/etc2_astc=false` and `s3tc_bptc=true` are on the **Linux and
  Windows** presets, not the Web one, and there they are correct.

## What is NOT measured, and why

**Framerate.** This is a container with **no GPU** — rendering runs on Mesa's
lavapipe, so a frame time here says nothing about a real card and nothing at all
about a browser. Every number above is deliberately hardware-independent: counts
and bytes, not milliseconds. The 60 fps target is pursued through budgets and
confirmed by one run on real hardware, not asserted here.

**Load time**, which on the web tier is probably the worse problem. The world is
built in GDScript at runtime and the Web preset sets
`variant/thread_support=false`, so the whole build blocks the browser's main
thread on a single-threaded WASM interpreter. That is a separate pass and it wants
its own measurement.

## Where the remaining web cost is

Geometry is no longer the top of this list. In order:

1. **Fill rate.** 1280×720 at `msaa_3d=2` (which is 4×) is 3.7M samples a frame
   on a WebGL2 context. `anti_aliasing/quality/msaa_3d.web=0` is the single
   biggest remaining win and costs desktop nothing.
2. **The shadow atlas.** `lights_and_shadows/directional_shadow/size=4096` is a
   64 MiB depth texture, allocated whatever the tier. With 2 cascades over 96 m,
   `directional_shadow/size.web=2048` is more texels than the web tier can
   resolve and saves 48 MiB.
3. **Transparent overdraw.** 24 cloud clusters, 37,632 triangles, alpha-blended
   over most of the sky, plus the Douro's per-pixel fresnel and foam over roughly
   a third of the frame. Both are `atmosphere`-owned.
4. **Shader compilation**, which on GL Compatibility happens on first use and on
   the web shows as hitching through the first fight.

## The budget gate

`tools/profile.gd`'s `BUDGET` was a single `primitives_p99: 1_600_000` serving
both tiers, which cannot be right for either: the static desktop arena measures
3,261,457 primitives at its worst vantage before a hero, a giant or a particle
is drawn, and the same scene measures 574,730 on the web tier. A ceiling loose
enough for desktop is six times the web tier's entire frame.

It is now `BUDGETS`, keyed on `RenderingServer.get_current_rendering_method()`,
with an unknown renderer falling back to the *strict* tier — a gate that does
not recognise where it is running should not be the loose one.

### It had never run

The stale ceiling was not why the gate kept passing. **The gate had never
executed.** `tools/profile.gd` did not parse:

```gdscript
var p50 := proc["p50"]      # Parse Error: cannot infer the type of "p50"
```

`:=` off a Dictionary subscript is a hard parse error in GDScript — the value is
a Variant with no set type — and the line had been there since the file was
written. So the profiler that owns the frame-cost distribution, the hitch
attribution and the budget enforcement was dead code, and its silence was
indistinguishable from a clean run.

Two things nothing caught, both now closed:

* **`--import` cannot see it.** Godot compiles the scripts reachable from the
  resources it imports; a script referenced only by a `.tscn` that no import
  step loads is never compiled, so CI's "Import must be error-free" was grepping
  a log that could not contain the error. `tools/parsecheck.tscn` now loads and
  `reload()`s every `.gd` in the project in one process — three seconds for 94
  scripts — and CI runs it before the probes.
* **The gate could not fail.** `_report()` printed `BUDGET EXCEEDED` and then
  `_process` called `get_tree().quit(0)` unconditionally. Whatever launched it
  saw success. It now exits 1.

The parse check needed the same treatment applied to itself. Its first version
tested `ResourceLoader.load(...) == null`, and with the real bug reintroduced on
purpose it reported PASS — Godot hands back a `Script` object for a file that
did not compile. `reload()` returns `43` (`ERR_PARSE_ERROR`) and is the check
that discriminates. **A gate has to be shown failing on the fault it was written
for**, or it is decoration; this one was run in all three states (clean → PASS,
bug → FAIL exit 1, restored → PASS).

That is now four instances of the same failure shape in this project: the
`_menu_probe` that measured a scene it had failed to add to the tree,
`tools/budget.gd`'s zeros, the profiler that never parsed, and the parse check
that passed its own motivating bug. **A tool that does not run looks exactly
like a tool that runs and finds nothing wrong.**

### What a live fight actually costs

The first run the profiler has ever completed. 600 frames of the scripted route
in `scenes/main.tscn` — closing on the giant, swinging, the ability, taking the
slam — Forward+, 640×360, llvmpipe:

| | p50 | p95 | p99 | max |
|---|---|---|---|---|
| draw calls | 693 | 721 | 726 | 730 |
| primitives | 3,305,102 | 3,311,709 | 3,312,473 | 3,342,749 |
| nodes | 667 | 727 | 735 | 739 |

Peak static memory 146.6 MiB. Counts are resolution-independent, so 640×360 was
chosen purely to make 600 frames finish on a software rasteriser.

**Two heroes, a nine-metre giant and every combat effect add 51,016 primitives
to a 3,261,457-primitive static world — 1.5%.** Draw calls tell the same story
from the other side: 575 static to 726 live, so the actors cost 151 draw calls
and essentially no geometry. Everything else in the frame is the world being
resubmitted to the shadow cascades.

That is the number that should have driven the last four rounds. Whatever is
making a frame expensive, it is not the fight.

### The ceilings are a ratchet

They are set just above what the build measures today, so a regression trips
them. They are not a statement that this is what a frame should cost — the
desktop tier submits 2.9× the world's whole triangle count every frame and that
is an open problem, recorded above. Loosening one to make a run pass turns the
ratchet into a rubber stamp; a change that needs more headroom needs a
measurement and a line in the round doc saying what it bought.

## Rules this budget is kept under

- **Cut on the tier, never globally.** `docs/REVIEW_LOOP.md` scores desktop
  frames pixel for pixel and three rounds of material and lighting work sit on
  top of this scene. Every reduction above is behind `WorldTier.is_reduced()`,
  and the proof is a capture diff of the desktop shots that comes back
  IDENTICAL — see the report for this pass.
- **Draw calls are the ceiling, triangles are the budget.** ARCHITECTURE.md rule
  6 still holds: the bake discipline is what bought the detail. The split above
  costs the web tier 32 extra draw calls and buys back 91% of the shadow pass.
  Splitting finer was measured and is not worth it — a 32 m grid reached 671
  draw calls for the same shadow result.
