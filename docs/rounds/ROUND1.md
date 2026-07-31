# Round 1 — the daylight conversion, scored

First frames put in front of adversarial critics after golden hour was removed.
Shots captured at review tier (1280x720, Forward+ under lavapipe) from
`tools/shots.json`; scored against `tools/critic/RUBRIC.md`.

## Scores

| shot | verdict | overall |
|---|---|---|
| `02_deck_eye` | AMATEUR | 2.0 / 10 |
| `01_deck_mid` | AMATEUR | 2.3 / 10 |
| `07_ribeira` | AMATEUR | 2.8 / 10 |
| `03_rail_macro` | AMATEUR | 3.0 / 10 |

Mean **2.5 / 10** across two independent critics who did not see each other's
reviews and who agreed on every systemic finding.

Every critic in every round so far picks the real Crash Bandicoot N. Sane
Trilogy frame in the blind test. That is the honest position and it is where a
round-1 score should be.

## The critic's measurements, independently verified

The focal-hierarchy claim was re-measured by the lead from the same PNGs before
any work was briefed on it. It reproduces:

| region | critic | lead | |
|---|---|---|---|
| `02_deck_eye` deck (playable) | L=86 sat=0.158 | **L=81.3 sat=0.138** | |
| `02_deck_eye` facades (background) | L=161 sat=0.326 | **L=161.2 sat=0.354** | |
| `07_ribeira` deck (playable) | L=73 sat=0.148 | **L=73.5 sat=0.159** | |
| `07_ribeira` facades (deep background) | L=151 sat=0.351 | **L=145.8 sat=0.274** | |

**The focal hierarchy is inverted, and it is the most damaging finding in the
round.** The playable corridor is roughly half the luminance and 40% of the
saturation of the furthest thing in shot. The rubric requires the opposite: the
bridge deck is where the fight happens and it must be the brightest,
highest-contrast region in frame, with background Porto sitting back behind
aerial perspective. Right now the disposable background is winning outright.

## One critic diagnosis was wrong, and acting on it would have wasted the round

The critic's number-one systemic finding was *"not one cast shadow exists in
either frame — every object floats on ambient"*, and it recommended that as the
root cause to fix first.

The observation is right. The diagnosis is not, and the difference is a whole
round of work:

- `SunLight.shadow_enabled = true` in `bridge_arena.tscn`.
- Shadows demonstrably render: the black under-deck mass filling the lower third
  of `01_deck_mid` is the deck soffit shadowing itself.
- The sun sits at **51 degrees elevation**. A 1.2 m parapet at 51 degrees casts
  roughly 1 m of shadow, straight down at its own feet, where it is invisible
  from a deck-level camera.

So the frames are not missing shadows. They are missing *readable* shadows,
because the key light is too high and too close to the fill in strength. "Turn
shadows on" would have changed nothing and the next round would have reported
the same defect again — which is exactly the failure mode the rubric warns
about, and the reason it asks critics to flag when a defect survives repeated
fixing.

Worth recording that the correction ran in the same direction as the original
brief's mistake: the brief said "high, bright sun, Porto on a clear day", the
agent delivered exactly that, and *technically correct midday light is the
flattest light there is*. N. Sane's levels are keyed lower and rake across the
geometry precisely because shape comes from shadow. The fix is lighting design,
not a toggle.

The critic also spotted this pattern itself, from the other end, and its warning
is correct: depth in `07_ribeira` is carried almost entirely by **blur** while
value and saturation are untouched, so the hero object is softened while the
disposable background shouts. Reaching for more distance blur is the backwards
move; depth belongs in value compression and desaturation toward sky colour.

### And the lead's own first read was wrong, corrected by measurement

The lead looked at the deck bands in `02_deck_eye` at magnification and called
them cobble material rather than shadows. The second critic measured them and
they are shadows — the giveaway is that the cobble's normal-map relief is
present outside the band and *gone* inside it, which no material change would
do. Pixel measurement beat eyeballing, which is the entire argument for having
the harness.

That correction turns a vague complaint into a precise, actionable one, below.

## Confirmed defects, in priority order

Verified against the frames, several by direct pixel measurement.

1. **Inverted focal hierarchy** (measured above). Systemic, all four frames.
2. **Shadow chroma is backwards, and the shadow term kills normal response.**
   Measured on the deck cobble: normalised lit = (1.00, 0.877, 0.949),
   normalised shadow = (1.00, 0.818, 0.892). Under a sky measuring (66, 151,
   211) the shadow must go *cooler*; it goes redder. Inside the band the cobble
   relief disappears entirely and the band edge is a 1 px step with no penumbra,
   so it reads as a decal quad rather than as cast light.

   The cause is almost certainly the fill rig, not a shadow setting.
   `lighting_rig.gd` adds a cool sky fill and a **warm river bounce**
   (`BOUNCE_COLOR = (1.0, 0.72, 0.46)`). Where the key is occluded, shadow
   chroma is decided entirely by the ratio of those two, and the warm bounce is
   currently winning — which is exactly inverted for daylight, where an open
   sky is the dominant fill on any surface the sun misses.
3. **A full-width polygon receives no light at all.** `01_deck_mid`,
   y≈478–605, spanning all 1280 px: constant RGB (0, 1, 2) with standard
   deviation **0.0**, confirmed to survive a 3.2-gamma lift unchanged. Not a
   dark surface — a surface with no material that not even ambient reaches,
   occupying ~14% of the frame directly beneath the playable corridor.
4. **The sun is too high to produce shape.** 51 degrees, so a 1.2 m parapet
   casts about 1 m of shadow straight down at its own feet, invisible from a
   deck-level camera.
3. **The tram rails are flat cobalt-blue painted stripes with no geometry** —
   no rail head, no web, no groove, no fixings, and blue is not a value steel
   takes in daylight. They occupy the largest, nearest region of the playable
   corridor. Confirmed at magnification.
4. **The clouds are placeholder ellipsoid meshes** — hard opaque silhouettes,
   visible mesh-intersection seams, khaki-brown undersides (midday cloud
   undersides are cool blue-grey, lit by sky), and two copy-pasted clusters at
   identical size and tilt. They occupy the top quarter of every wide shot.
5. **Every facade is a flat-coloured polygon.** Windows painted on as dark
   rectangles with no reveal or sill, roofs as flat slabs with no tile, walls
   with no plaster grain, damp or grime, and no azulejo anywhere — the defining
   Porto facade material is absent.
6. **The playable corridor is completely propless.** Not one crate, bollard,
   bench, sign, catenary pole or person across two wide establishing shots.
7. **The Dom Luís ironwork has no material** — reduced to a flat black fence
   with no rivets, gussets, rust or specular return. The single asset that makes
   this Porto rather than a generic river town is the least resolved thing in
   frame.
8. **Water reflects nothing.** A large iron arch stands over calm water and
   returns nothing; no shoreline interaction, no wet line, no foam at the quays.
9. **Copy-pasted chimneys**, ~40 per frame at identical orientation and scale.
10. **The ironwork is a black cutout, not a material.** Measured mean RGB
    (11, 16, 27), standard deviation 3, maximum (22, 28, 41). No rivets, no
    paint, no rust, and no specular return anywhere along the top rail against
    a 210-blue sky. In a game about a wrought-iron bridge this is the hero
    material of the location, and it is the highest-leverage single fix
    available because it is the same asset in every shot.
11. **The deck cobble is a normal-map-only material.** Contrast-stretched,
    every sett is the identical pinkish-mauve: no stone-to-stone albedo
    variation, no mortar colour in the joints, no dirt in the low points, no
    polished crown on the traffic line. Relief alone is doing all the work.
12. **An orphaned asset floats in clear sky in both wide shots** — a grey-green
    blob at x≈1155–1200, y≈190–215 in `03_rail_macro` and x≈1035–1075,
    y≈140–160 in `01_deck_mid`, detached from the Gaia hillside it belongs to.
    A bug, not an art note.
13. **The gulls are untextured flat quads** — bent rectangles hinged at a point,
    no wing shape, no body, no shading, at ~25 px on screen.
14. **No anti-aliasing on the parapet diagonals.** Pixel scan across a member
    goes 16 → 134 in a single pixel. Black lattice against bright sky at one
    sample will crawl badly in motion.

## What is working and must not be broken

- The sky's base gradient — a clean, correctly saturated daylight blue. The
  clouds in it are the problem, not the gradient.
- The depth staging in `07_ribeira`: five genuine, correctly scaled planes. They
  are empty, but the composition is right. Fill them; do not restage them.
- The arch silhouette and its centre-frame placement — the identity anchor.
- The corridor composition in `02_deck_eye`: lane widths, camera height and
  convergence all read correctly as playable space.
- The calçada sett band, the one surface in either frame with a working normal
  map and varying roughness. The pattern is wrong (river-pebble noise rather
  than square-cut Portuguese sett) but the material response is real.
