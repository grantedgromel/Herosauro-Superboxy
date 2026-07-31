# Round 2 — four root causes, none of them the reported symptom

Round 1 scored AMATEUR, mean 2.5/10. This is what fixing it actually turned up.

The pattern is the point: **in all four cases the defect the critics described was
real and the cause they proposed was wrong.** Acting on any of the proposed causes
would have burned a round and produced another identical review.

## 1. MeshBaker: two mirror-image winding bugs

Reported as *"surfaces float on ambient"*, *"the ironwork is a black cutout"*,
*"every facade is a flat-coloured polygon with windows painted on as dark
rectangles, no reveal, no sill"*. Three rounds of briefs would have asked for
more material work.

The engine convention was settled empirically, four ways, before anything was
changed: Godot's own `BoxMesh` / `SphereMesh` / `CylinderMesh` stored normals,
`SurfaceTool.generate_normals()`, and a direct render — in an isolated project
*and* through the real `MeshBaker.commit()` path — of a quad whose right-hand
normal faces the camera. **Godot's front face is the one whose RH points into
the solid; outward normal is −RH.**

Against that, `mesh_baker.gd` had two bugs pointing opposite ways:

| primitive | winding | consequence |
|---|---|---|
| `add_box`, `add_beam`, `add_cylinder` | RH inward | rendered, but stored an inward shading normal, so `N·L < 0` for every light outside it — no diffuse, no specular, ambient only |
| `add_roof_prism` | RH outward | normal correct but **back-facing** — landmark roofs existed only when seen from below |
| `_tri_uv` | emitted in caller order | **every caller that obeyed the project's own stated contract was culled** |

The second one is the larger. The contract written in `facade_geo.gd`,
`landmarks_builder.gd`, `terrain_builder.gd` and `deck_kit.gd` — *wind so RH
points the way the surface faces* — was honoured by the callers and then thrown
away by the emitter. Casualties: **the entire terrain ground sheet** (rendered
in isolation, the terraces were hollow — retaining walls standing over a void),
the punched facade skins, the round-2 grooved tram rail, landmark roofs, the
azulejo flank, the lodge sign faces.

Fix: `_tri_uv` keeps `+RH` as the shading normal and emits `a, c, b` with each
UV following its own vertex — one place reconciles contract and engine.
`add_box` and `add_cylinder` are re-wound to obey the contract themselves. Box,
cylinder and beam emit the same vertex order as before (two reversals cancel) so
nothing moved on screen, but their normals flip outward; everything else keeps
its normal and starts rendering at all.

### Measured, on the region Round 1 called out

`03_rail_macro`, top rail against sky, x 0–380, y 332–344:

| | mean RGB | sd |
|---|---|---|
| Round 1 baseline (critics measured 11,16,27 sd 3) | (9.8, 14.6, 25.4) | 3.13 |
| pre-fix, this tree | (28.7, 37.2, 56.4) | 6.89 |
| **post-fix** | **(37.6, 44.1, 56.4)** | **16.35** |

The standard deviation is the number that matters. **3 is a cutout; 16 is a
member with a lit face and a shadow face.** Whole-lattice luminance went
26.6 → 55.4 and its R/B ratio 0.55 → 0.69 — from cool sky ambient only, to a
warm key actually returning. Top-rail peak reached (145, 123, 83), a warm
R > G > B highlight where Round 1 found "no specular return anywhere".

`01_deck_mid`: girder truss luminance 37.9 → 73.6, sd 15.8 → 44.3. And the
focal hierarchy moved for free — **deck paving 86.7 → 96.0 while the far-bank
facades went 135.4 → 136.0**, so the playable corridor gained 11% and the
background half a percent.

### One caller was compensating

All 52 `add_quad` sites across 10 files were audited by *building the geometry
and measuring stored normals*, not by reading. Only `terrain/flora_kit.gd`
walked its rings the other way — which is precisely why it was the one family
that rendered before the fix, and it rendered inside out. Caller and emitter
flips cancel for visibility and compound for shading, so correcting it moved
nothing and lit the planting.

`_terrain_probe.gd`'s ground-sheet check was **silently vacuous**: it selected
paving by comparing `albedo_color` against the raw `COBBLE` constant, but
`ToonFactory` remaps colour through `_physical_albedo`, so it matched zero
surfaces and passed on an empty set. It also asserted the emitted RH points
*up* — i.e. that the paving is invisible from above. It now matches by material
identity, fails when it finds nothing, and validates 2,700 triangles.

## 2. The black band: a subtraction labelled a multiply

Reported as *"a full-width polygon that receives no light"* — constant
RGB (0, 1, 2), standard deviation exactly 0.0, unmoved by a 3.2-gamma lift.

`toon_bridge.tres` carried `detail_blend_mode = 2` above a comment asserting
that 2 was MUL. Godot's `BlendMode` is MIX 0, ADD 1, **SUB 2**, MUL 3. It was
computing `ALBEDO − detail`; the fine map runs 0.68–1.00 against the material's
0.32, so every channel went negative and clamped.

And the `(0,1,2)` was never the surface — it is the grade LUT's own stop at
input zero, which is exactly why the deviation was 0.0 and why a gamma lift did
nothing. That band now measures L=91.9, sd=9.4. The probe asserts the mode
against `BLEND_MODE_MUL` **by name** rather than by number.

> Note: the winding pass separately reports this same band as culled geometry.
> Both defects were real and stacked — the blend mode was fixed first and moved
> the band to L=91.9, so that is the one that was operative at measurement time.
> Worth re-measuring once, rather than assuming either account is complete.

## 3. Shadow chroma: the wrong fill was blamed

Reported as *"shadow is warmer than the lit surface under a blue sky"*, with the
warm river bounce named as the cause. Measuring the rig showed both directional
fills were **already blue** on an up-facing surface.

The warmth came from the directionless terms — ambient plus SSIL at radius 4.0,
which on flat paving gathers four metres of *the same sunlit warm paving*, a
view factor no real plane has. Re-balanced as a ratio of directional to
directionless light: the shadow term went from warmer than the key to B/R 1.608
against the key's 0.855, and shadow fill is now 74% directional against 56%.

The visually important number is the second one: **cobble standard deviation
inside a shadow band went 10.8 → 18.0**, so relief survives in shadow instead of
the band reading as an opaque sticker.

## 4. The floating blob: photogrammetry, not a prop

Reported as an orphaned grey-green asset hovering in clear sky in two shots. A
vertex-level projection probe put it at world (148, 42, −245) — 250 m out, 41 m
up. Not a tree or a rock: **1,213 triangles (0.28%) of the photogrammetry scan**,
capture-boundary islands sitting above the scan's real skyline of y=38.0, with
two metres of clear air beneath. Identical garbage to the skirt hanging off the
*bottom* of the capture volume, which the placement code already deliberately
drowns under the river. Nothing drowned the ones in the air. Fixed with a
documented ceiling clip at load.

## Findings withdrawn

- **Serra do Pilar is a smeared mass** — misattributed. The mass in that frame
  is the photogrammetry scan plus far Gaia terrain; our procedural Serra do
  Pilar projects clean off the right edge and was never in the shot reviewed.
- **No anti-aliasing on the parapet diagonals** — `project.godot` already runs
  MSAA 4x with FXAA and edges ramp over about two pixels. The crawl is contrast,
  black against 210-blue, not sampling.
- **The port-lodge signs are illegible** — the glyphs were always fine. A 4.3 m
  cap at 90 m subtends ~28 px. The boards were *occluded*: sills under a metre
  off the terrace behind lodges with 6–9 m ridges, so the roofline ate the
  bottom two-thirds of every letter. Raising cap height — the obvious fix —
  would have produced large unreadable letters.

## Briefs that were wrong, corrected by the agent that received them

Worth recording, because a wrong finding propagates through a faithfully-relayed
brief:

- "The masts and cross-spans are clear of the giant in Z." True of the masts
  (6.25 vs 5.75), false of the cross-spans, which run the full deck width at
  7.84–8.18 where a 10.6 m giant walks through them.
- "Hang the broken wire toward the deck." No room: hero capsule 2.0 m plus
  2.82 m of jump off a 2.13 m footway puts a jumping hero's crown at 6.95,
  five centimetres under the wire being replaced.
- "Fix the missing anti-aliasing." Already on; see above.

## Harness defect found this round

`harness.py` gated capture success on the engine's exit code. Godot writes the
PNG and then spends **four minutes** tearing down a 900k-triangle scene on this
hardware, so captures that had completely succeeded were reported as TIMEOUT —
and it hit the wide establishing shots hardest, which are the ones critics
score. Success is now "a decodable PNG exists": `png.read()` inflates the IDAT
and unfilters every scanline, so a file truncated by a killed process raises
rather than passing. Verified against a deliberately truncated frame.
