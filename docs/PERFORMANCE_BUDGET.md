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

**Per-frame counters at that same camera**, which is what `tools/profile.gd`'s
BUDGET gate is written against:

| | Forward+ | GL Compatibility |
|---|---|---|
| objects in frame | not measurable here — see below | 245 |
| draw calls in frame | " | 245 |
| primitives in frame | " | 524,577 |

Two things to know about those rows.

`tools/budget.gd` prints all three as **0**, always, and has since it was written:
`tools/budget.tscn` contains no `Camera3D`, so nothing renders 3D and the counters
are honestly zero. Standing a camera at a shot vantage is the whole fix and it is
proposed to the lead.

And the Forward+ column is blank because it could not be obtained. Twelve frames
of the full Forward+ pipeline on this container's software rasteriser — SDFGI
cascade bake, SSR, SSIL, volumetric fog — did not complete inside fifty minutes.
`tools/profile.tscn` is in the same position: 70 frames of a live fight timed out
at forty minutes on Forward+ and 180 frames timed out on Compatibility. Both are
usable on real hardware and neither is usable here, which is worth knowing before
anyone waits on one.

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

52.3 MiB on the web tier for the world is a non-issue. **The UI art is not**, and
it is the largest single VRAM item in the build:

| file | size | in VRAM |
|---|---|---|
| `assets/ui/key_art.png` | 1672×941 | 7.98 MiB |
| `assets/ui/art/banner_adamastor.png` | 1672×941 | 7.98 MiB |
| `assets/ui/art/banner_superboxy.png` | 1672×941 | 7.98 MiB |
| `assets/ui/art/figure_adamastor.png` | 1024×1536 | 7.98 MiB |
| `assets/ui/art/figure_superboxy.png` | 1024×1536 | 7.98 MiB |
| three portraits | | 5.12 MiB |

All eight import at `compress/mode=0` (Lossless), so they arrive in VRAM as
uncompressed RGBA8 with mipmaps: **~45 MiB, against 52 MiB for the entire
world**, plus ~13.5 MiB of PNG in the pck. That is the `ui` stream's to decide,
and the decision is a real one — VRAM Compressed would quarter it and would show
banding on flat gradient art.

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

`tools/profile.gd`'s `BUDGET` dictionary is stale in one entry and cannot be right
in that entry for both tiers at once:

```
"primitives_p99": 1_600_000
```

The desktop world alone submits ~1.1M in the opaque pass, ~1.1M again in the
Forward+ depth prepass and 2,196,722 to the shadow cascades — roughly 4.4M before
a hero, a giant or a particle is drawn. The gate has been passing only because
nobody has run it since the density work landed.

One number cannot serve both tiers: the same scene measures 524,577 primitives on
the web tier. The gate wants to be keyed on
`RenderingServer.get_current_rendering_method()`, with the web ceiling being the
one that matters, since the web tier is the one with no headroom.

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
