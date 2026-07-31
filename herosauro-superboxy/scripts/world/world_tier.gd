class_name WorldTier
extends RefCounted
## Which geometry tier this process is building, and every number that differs
## between them. The single place the web build's reduced world is defined.
##
## WHY THIS EXISTS. `lighting_rig.gd` already tiers the *shading*: on GL
## Compatibility it strips SDFGI, SSR, SSIL and volumetric fog and pays back what
## was lost. That is well done and it is not enough, because the cost of this
## scene is not per-pixel, it is geometry. Measured on the assembled arena:
##
##   Forward+          1,095,335 triangles   178 surfaces   141.9 MiB
##   GL Compatibility    669,977 triangles   177 surfaces    73.0 MiB
##
## The 425k difference is the photogrammetry backdrop, which already self-gates
## off (`city_backdrop.gd::_should_build`). Everything else — 670k triangles, of
## which 551k cast shadows — the web build submits in full, exactly as the desktop
## build does. Stripping post-processing from a scene whose cost is vertices does
## not help much, so this file is the geometry half of the same idea.
##
## --- THE MEASUREMENT THAT DECIDED THE DESIGN ---------------------------------
##
## The batchers weld a whole district into ONE surface per material. `Ribeira_1`
## is 169,936 triangles in one MeshInstance3D whose world AABB spans
## (-136, -9, -126) .. (100, 31, 32) — both banks, every terrace level, the entire
## city. Godot culls and shadow-maps an instance as a unit against that AABB, so a
## surface that large is in **every** frustum and **every** shadow cascade, always.
##
## Probed against the shot cameras, 98.6% of all shadow-casting geometry landed in
## cascade 0 — the 26 m box around the player. Four cascades therefore cost
## 4 x 551k = 2.19M triangles re-rendered per frame, and the number barely moved
## when directional_shadow_max_distance was swept from 80 m to 260 m, because
## nothing could ever be culled out of any cascade in the first place.
##
## So the two levers here are, in that order:
##
##   1. `CHUNK_RINGS` — cut each material's bake on distance from the arena, so a
##      surface belongs to a known band instead of to the whole world. This is
##      the enabling change: every other lever is a distance test, and a distance
##      test cannot be applied to an instance that is everywhere at once.
##   2. `SHADOW_RADIUS` — with the bakes cut, dropping the background out of the
##      shadow pass is a per-chunk decision instead of an all-or-nothing one.
##      Measured: 2,188,828 triangles submitted to the cascades, down to 199,795.
##
## --- WHY IT IS TIERED RATHER THAN GLOBAL -------------------------------------
##
## Three rounds of material and lighting work sit on top of the desktop image and
## the review loop scores it pixel for pixel (`docs/REVIEW_LOOP.md`). Everything
## below is therefore gated on the renderer: on Forward+ every constant collapses
## to "off", so the desktop scene is built by byte-identical code paths and the
## capture gate can prove it. The reduced tier is verified separately by running
## the same measurement scene under `--rendering-method gl_compatibility`, which
## reports the web build's real numbers on this machine.

## Renderer names, as `RenderingServer.get_current_rendering_method()` spells them.
const COMPATIBILITY := "gl_compatibility"
const MOBILE := "mobile"

# --- Reduced-tier geometry ---------------------------------------------------

## Chunks whose nearest point is further than this from the arena centre do not
## cast shadows on the reduced tier.
##
## 66 m is measured off the arena, not chosen: the deck runs to |x| = 50, the
## abutments to 59 and the arch springings to 55, so 66 keeps every part of the
## bridge and its own masonry casting while dropping the Ribeira terraces
## (frontage 52-122 m), the Gaia bank, the landmarks and the far terrain.
##
## What this gives up is the inter-building shading on the hillside that the
## desktop tier bought with directional_shadow_max_distance = 260. That is the
## right thing to give up here and `docs/REVIEW_LOOP.md` says why: the player
## spends the whole game looking at a nine-metre giant from about ten metres, and
## the far banks are backdrop nobody studies. On desktop it stays.
const SHADOW_RADIUS := 66.0

## --- WHERE THE BAKES ARE CUT -------------------------------------------------
##
## Rings of plan distance from the arena centre, not a square grid, and the
## boundaries are the other constants in this file rather than round numbers.
##
## A uniform grid was tried first and measured worse on both axes at once. At a
## 32 m cell the web build came out at 671 draw calls, and coarsening it to 80 m
## only reached 448 — because the count is driven by (materials x cells) and a
## terrace uses twenty-five materials, so most cells held a few hundred triangles
## and cost a full draw call for them. Meanwhile the same coarsening broke the
## shadow test: an 80 m cell reaching from x = -45 to x = -120 has its NEAREST
## point 45 m out, so it passed the radius check and pushed all 9,392 of its
## triangles through the cascades on account of its near edge.
##
## Rings fix both, because they are the shape the test is actually asking about.
## The one decision a chunk has to carry is "does this cast", and that is a
## distance question, so cutting on distance makes it exact at its own boundary
## instead of approximate at a grid line.
##
## ONE BOUNDARY, and it is SHADOW_RADIUS, because that is the only thing the cell
## is consulted for — the detail and return ranges below are per-building tests
## made against a Spec's own position and need no cell at all. Four rings were
## measured against two and submitted exactly the same 199,795 triangles to the
## cascades for 315 draw calls against 209, so the extra bands bought nothing.
##
## What is given up is locality along the river: a ring wraps both banks, so a
## camera looking at Porto cannot frustum-cull Gaia. That is worth very little
## here — every vantage in tools/shots.json and the game's own chase camera see
## both banks at once — and the near/far split TerrainBatch already makes at
## NEAR_Z_FAR covers the one case where it would have paid.
const CHUNK_RINGS: Array[float] = [SHADOW_RADIUS]

## Beyond this, a Ribeira house is built at MEDIUM detail on the reduced tier:
## punched openings with real reveals, surrounds, sills and a barrel roof, but no
## shutters, balconies, string courses, quoins, tilework or washing.
const FACADE_MEDIUM_RANGE := 78.0
## Beyond this it is built at LOW: silhouette, plinth, cornice, flat dark
## openings, plain roof. At 110 m a 22 cm window reveal is a third of a pixel.
const FACADE_LOW_RANGE := 110.0
## Beyond this a building's flank and rear elevations are not built at all on the
## reduced tier. A return elevation is only ever seen from an oblique angle, and
## past ninety metres in a terrace it is seen by nothing: the neighbour is 5 cm
## away. Held short of FACADE_LOW_RANGE on purpose, because LOW does not emit
## returns anyway and this has to bite while there is still something to cut.
const FACADE_RETURN_RANGE := 90.0

## Directional shadow reach on the reduced tier, metres. Desktop keeps the 260 in
## bridge_arena.tscn, which reaches the Ribeira stack.
##
## With the chunking above in place this is a real lever again, and 96 is where it
## stops paying: it covers the whole deck, both abutments and the near quay, which
## with SHADOW_RADIUS is everything still casting.
const SHADOW_DISTANCE := 96.0
## Cascades on the reduced tier. Four splits over 96 m is four full geometry
## passes to resolve a range the first two already cover; PARALLEL_2_SPLITS halves
## the shadow pass outright.
const SHADOW_SPLITS := DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS

## River plane subdivisions on the reduced tier, against the .tscn's 178.
##
## 64,082 triangles of water running a six-trig vertex shader, over a third of the
## frame, is the second largest single mesh in the build after the city. 88 keeps
## 10.2-unit quads against the desktop 5.0 — the swell is a 0.35 m amplitude at an
## 0.18 wave scale, so it is still sampled well above Nyquist — and costs 15,842
## triangles instead.
const RIVER_SUBDIVISIONS := 88

static var _method: String = ""


## Cached because the builders ask per building and the answer cannot change
## inside a process.
static func rendering_method() -> String:
	if _method == "":
		_method = RenderingServer.get_current_rendering_method()
	return _method


## True on the tiers that render the web build and the mobile fallback.
##
## Headless always reports forward_plus, so every probe and every capture run in
## `tools/` takes the desktop path. Measuring the reduced tier means asking for it
## explicitly:
##
##     godot --path . tools/budget.tscn --rendering-method gl_compatibility
static func is_reduced() -> bool:
	var method := rendering_method()
	return method == COMPATIBILITY or method == MOBILE


## Does a world material get ToonFactory's close-range detail layer?
##
## OFF on the reduced tier, and this is the most expensive single thing a world
## material does. A textured surface turns on BOTH `uv1_triplanar` and
## `uv2_triplanar`; triplanar samples every map three times, once per axis, and
## blends. The full set is albedo, normal, mask (read three ways) on uv1 and
## detail albedo + detail normal on uv2 — roughly TWENTY-ONE texture fetches per
## fragment, over the deck, the quays, every facade and every railing, which on
## the web tier is most of the frame. Dropping the uv2 layer removes six of them
## and a whole set of interpolated triplanar coordinates with it.
##
## What it gives up is the 0.28 m grain. That is the same trade FACADE_LOW_RANGE
## and FACADE_RETURN_RANGE already make and it is the easier one: at browser
## resolution, with the camera ten metres from a nine-metre giant, a 0.28 m tile
## is a couple of pixels across.
##
## THERE IS A SECOND REASON, and it is unconfirmed, so it is written as a
## suspicion rather than a finding. The owner reports every textured world
## surface rendering WHITE in the browser while the heroes and Adamastor — which
## take `Surface.FLAT`, and so skip this whole path — render correctly. A
## StandardMaterial3D on the dual-triplanar path needs world position, normal,
## tangent, binormal, two UV sets, two triplanar position sets, two triplanar
## blend-weight sets and shadow coordinates, and WebGL2 only GUARANTEES fifteen
## varying vectors. A driver at that minimum fails to link the program, and
## Godot substitutes its default white material — which is exactly the split
## reported. It does not reproduce on this container's SwiftShader or ANGLE/GL
## backends, so it stays a suspicion. The change stands on the fetch count
## alone; if it also fixes the white-out, that confirms the varying overflow.
static func fine_detail() -> bool:
	return not is_reduced()


## Do the batchers cut their bakes on this tier? False is the desktop path, and it
## is byte-identical to the code before chunking existed — one surface per
## material, exactly as before.
static func split_bakes() -> bool:
	return is_reduced()


## The chunk `pos` belongs in. See CHUNK_RINGS. The second component is reserved:
## it stays 0 so a future split along the river (per bank, say) can be added
## without touching a single call site.
static func cell_for(pos: Vector3) -> Vector2i:
	var d := plan_distance(pos)
	for i in CHUNK_RINGS.size():
		if d <= CHUNK_RINGS[i]:
			return Vector2i(i, 0)
	return Vector2i(CHUNK_RINGS.size(), 0)


## Does a chunk in this cell cast shadows?
##
## Asked of the CELL rather than of the committed mesh's AABB, and that is not a
## shortcut — an AABB test cannot answer it. A ring is an annulus, and the box
## around an annulus contains the origin, so every ring chunk's AABB reaches the
## bridge and a nearest-point test calls all of them near. Measured: with the AABB
## test the reduced tier submitted 611,418 triangles to the cascades; with this
## one, 121,548. The cell is the honest answer because the ring boundary IS
## SHADOW_RADIUS — ring 0 is, by construction, exactly the geometry inside it.
##
## Vector2i.ZERO is the un-split cell, which is the desktop path, and it casts.
static func cell_casts_shadow(cell: Vector2i) -> bool:
	return cell.x == 0


## How far this position is from the arena centre, measured in the plane. Y is
## dropped on purpose: the whole world is a river valley and a terrace forty
## metres up is not forty metres further away.
static func plan_distance(pos: Vector3) -> float:
	return Vector2(pos.x, pos.z).length()
