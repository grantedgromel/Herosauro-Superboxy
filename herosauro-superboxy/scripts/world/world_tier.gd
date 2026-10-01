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
## 96 -> 60, together with the single map below. 96 was chosen when the cost model
## was vertices. On a software rasteriser, switching the sun's shadows off saved
## ~420 ms of a ~1,850 ms frame (`_bridge_perf.tscn -- --experiments`), part of it
## the caster pass, which is paid once per cascade because every ring-0 chunk's
## AABB reaches into every cascade. After this change shadows-off still saves
## ~250-440 ms, so most of what is left is the per-pixel PCF on the RECEIVING side,
## which is the project's soft_shadow_filter_quality and not this file's. 60 m still
## covers the deck ahead of the chase camera, which looks down it from ~10 m behind
## the hero; what falls out is the far abutment's contact shadow.
const SHADOW_DISTANCE := 60.0
## ONE map on the reduced tier, not two. PARALLEL_2_SPLITS with split_1 = 0.06 spent
## a whole geometry pass on a 5.8 m cascade around the camera, and every caster in
## ring 0 is submitted to both. Measured together with SHADOW_DISTANCE above and the
## arch leaving the pass (bridge_ironwork.gd WEB_SHADOWLESS): shadow-pass primitives
## 204k -> 92k from the gameplay camera. The hero's and the giant's shadows on the
## deck were checked by eye in the web-tier gameplay frame and still read as
## contact shadows; the sharpness lost was not measured as a number.
const SHADOW_SPLITS := DirectionalLight3D.SHADOW_ORTHOGONAL

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


# --- Reduced-tier materials ---------------------------------------------------
##
## --- THE MEASUREMENT THAT MOVED THE COST OFF GEOMETRY ------------------------
##
## Everything above this line is about vertices, and on a real GPU that was right.
## The browser this game is first offered in is often not a real GPU: headless
## Chromium and plenty of school laptops rasterise WebGL on the CPU (SwiftShader),
## and so does llvmpipe, which is how scripts/world/_perf/_bridge_perf.tscn measures
## it here. On a CPU rasteriser the bill is per FRAGMENT, paid in texture taps.
##
## Every ToonFactory surface material is triplanar (three taps per map) with an
## albedo, a normal and a roughness/AO mask on uv1, plus the close-range detail
## layer on its own triplanar uv2 (six more), all sampled ANISOTROPICALLY. A
## software rasteriser implements anisotropy as many trilinear taps along the
## footprint, so one deck fragment cost on the order of a hundred texel fetches.
## Measured from the gameplay camera, GL Compatibility, 960x540, one llvmpipe
## thread, tree paused (`_bridge_perf.tscn -- --experiments`), per frame:
##
##   baseline                                         5,070 ms
##   every arena material: detail off, aniso off      2,346
##   ... and no normal/roughness/AO maps              1,977
##   ... and per-vertex shading                       1,609
##
## against 400 ms for the whole Dragao stadium on the same machine. No subtree of
## the scene, hidden outright, was worth half of that first line. (Single samples
## of 4 frames; repeat runs of the same configuration agree to about +-150 ms.)
##
## So the reduced tier gets two derived copies of each material, cached by source
## material so the whole city still shares one of each:
##
##   lean_material  what the deck and everything near it is drawn with: the same
##                  maps and the same look, minus the detail layer (a 0.28 m tile
##                  whose job is a 1:1 close-up the chase camera never takes) and
##                  minus anisotropy (trilinear instead).
##   far_material   for chunks outside SHADOW_RADIUS, i.e. backdrop at 66 m and
##                  beyond: lean, plus no normal/roughness/metal/AO maps and
##                  per-vertex lighting. The bakes are flat-shaded (MeshBaker writes
##                  one normal per triangle), so per-vertex diffuse is the same
##                  number per face that per-pixel was; what goes is normal-mapped
##                  grain and a specular lobe on walls 70-300 m away. The albedo map
##                  STAYS, because ToonFactory pitches albedo_color against that
##                  map's mean, and dropping it would shift every wall's colour.
##
## Desktop never asks for either: every caller is behind is_reduced() or
## split_bakes(), and on Forward+ both are false.

static var _lean: Dictionary = {}
static var _far: Dictionary = {}


## The reduced-tier copy of `mat` with the two software-rasteriser killers removed.
## Anything that is not a BaseMaterial3D (the river, the clouds, the sky) comes back
## untouched; those are shaders with their own budget.
static func lean_material(mat: Material) -> Material:
	var base := mat as BaseMaterial3D
	if base == null:
		return mat
	var cached: Material = _lean.get(base)
	if cached != null:
		return cached
	var m: BaseMaterial3D = base.duplicate()
	m.detail_enabled = false
	m.texture_filter = _no_aniso(m.texture_filter)
	_lean[base] = m
	_lean[m] = m      # a lean copy is already lean; never duplicate it again
	return m


## The reduced-tier copy of `mat` for backdrop chunks. See the header above.
static func far_material(mat: Material) -> Material:
	var base := mat as BaseMaterial3D
	if base == null:
		return mat
	var cached: Material = _far.get(base)
	if cached != null:
		return cached
	var m: BaseMaterial3D = base.duplicate()
	m.detail_enabled = false
	m.texture_filter = _no_aniso(m.texture_filter)
	m.normal_enabled = false
	m.normal_texture = null
	m.roughness_texture = null
	m.metallic_texture = null
	m.ao_enabled = false
	m.ao_texture = null
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	_far[base] = m
	_lean[m] = m      # the arena-wide lean pass must leave it alone
	return m


## The material a batch chunk in `cell` commits with. On the desktop path the
## bakes are not split, every cell is Vector2i.ZERO, and this returns `mat` itself,
## the identical object, so nothing downstream can tell it was asked.
static func chunk_material(mat: Material, cell: Vector2i) -> Material:
	if split_bakes() and not cell_casts_shadow(cell):
		return far_material(mat)
	return mat


## Should geometry at `pos` be built in its coarse, far-reach form? Only ever on
## the reduced tier, and only outside SHADOW_RADIUS, which is exactly where
## chunk_material() hands out far_material: per-vertex, no normal map, so the
## detail a coarse form drops is detail that tier no longer draws anyway.
static func coarse_at(pos: Vector3) -> bool:
	return is_reduced() and plan_distance(pos) > SHADOW_RADIUS


## Swap every BaseMaterial3D under `root` for its lean copy and return how many
## slots changed. Called once, on the reduced tier only, after the arena is built.
static func lean_tree(root: Node) -> int:
	var swapped := 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		var gi := n as GeometryInstance3D
		if gi == null:
			continue
		if gi.material_override != null:
			var lean := lean_material(gi.material_override)
			if lean != gi.material_override:
				gi.material_override = lean
				swapped += 1
			continue
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var src := mi.get_surface_override_material(i)
			if src == null:
				src = mi.mesh.surface_get_material(i)
			if src == null:
				continue
			var lean_s := lean_material(src)
			if lean_s != src:
				mi.set_surface_override_material(i, lean_s)
				swapped += 1
	return swapped


static func _no_aniso(f: BaseMaterial3D.TextureFilter) -> BaseMaterial3D.TextureFilter:
	if f == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC:
		return BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if f == BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC:
		return BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	return f
