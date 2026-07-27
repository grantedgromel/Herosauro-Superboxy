class_name TerrainBuilder
extends RefCounted
## The Douro gorge: quay walls, the Cais da Ribeira, the terraced hillside above
## it, the escadarias that stitch the terraces together, and the Serra do Pilar
## bluff on the Gaia side.
##
## What it replaces was six flat grey boxes. That is not a hillside, it is a
## stack of slabs, and buildings placed on it float on nothing. The point of this
## file is that the ground under Porto is *architecture* — the city sits on a
## staircase of granite retaining walls, and every one of those walls is a real
## surface with a coping, a batter, buttresses, weeds in the joints and ivy
## hanging off it. Model that and the buildings have somewhere to stand.
##
## HOW THE WORLD IS ORIENTED. The gorge runs along Z; the bridge crosses it along
## X. Water is a plane at y = -15 and everything at |x| < 52 is river. The Ribeira
## bank is at NEGATIVE x and the Gaia bank at positive x, which is where
## sky_background already puts the Serra do Pilar dome and the quay-row houses.
##
## The sun sits low over -x/-z, so the two banks are lit completely differently
## and are therefore built differently on purpose:
##
##   PORTO (-x), BACKLIT. Six terraces climbing 23 m from the water in uneven
##   steps, each on its own retaining wall, cut through by four escadarias.
##   SILHOUETTE does the work here — the stepped skyline, the cypresses, the
##   sawtooth of every stair cheek against the sky.
##
##   GAIA (+x), SUNLIT. A broad flat cais for the port lodges, one low terrace,
##   then the bluff: a banded rock scarp climbing 14.5 m in one go to the
##   monastery plateau. SURFACE does the work here — coursed masonry and rock
##   strata raked by a low sun.
##
## Mirroring the two would waste that, and the old code's own comment says so.
##
## ONE SOURCE OF TRUTH FOR HEIGHT. Every ground surface in this file — promenade,
## terrace platform, open hillside, headland — is a quad grid whose corners come
## from ground_height(). Nothing has its own idea of where the ground is, which
## is why placement code can trust the query: a building sat on ground_height()
## is sat on the mesh, not near it. The height functions take no seed for the
## same reason; build()'s seed only reaches jitter that does not move the ground.
##
## NOTHING HERE COLLIDES. The player never leaves the deck and the camera's
## spring arm never reaches |x| = 52, so a StaticBody per terrace would buy
## broadphase pairs and nothing else. It is all baked mesh.
##
## Usage:
##     add_child(TerrainBuilder.build())
##     TerrainBuilder.ground_height(x, z)                   # y of the ground
##     TerrainBuilder.building_plots(TerrainBuilder.PORTO)   # where houses go

const MK := preload("res://scripts/world/terrain/masonry_kit.gd")
const RK := preload("res://scripts/world/terrain/rock_kit.gd")
const FK := preload("res://scripts/world/terrain/flora_kit.gd")
const TerrainBatch := preload("res://scripts/world/terrain/terrain_batch.gd")

# --- The gorge ---------------------------------------------------------------

## Ribeira. Negative x, backlit, terraced.
const PORTO := -1.0
## Vila Nova de Gaia. Positive x, sunlit, cliff.
const GAIA := 1.0

## Matches the river plane in bridge_arena.tscn. Everything keys off it.
const WATER_Y := -15.0
## Where the quay wall foots: below the water and below anything ever seen.
const WALL_FOOT_Y := -16.2

## Modelled reach of the bank, upstream (far) to downstream (near). The far end
## stops 3 units short of the photogrammetry scan at z = -131, so the procedural
## bank runs into the real one rather than ending in mid-air.
const BANK_Z_FAR := -128.0
const BANK_Z_NEAR := 30.0
## Past BANK_Z_NEAR the bank sinks into the water as a rock headland — the river
## mouth opening out. Nothing is modelled downstream of this.
const HEADLAND_Z := 46.0

## Inside this the bake casts shadows and the masonry is laid block by block;
## outside it, neither. Set to the directional light's shadow range, so geometry
## that could never appear in a cascade does not pay for one.
const NEAR_Z_FAR := -78.0

## No plots and no stairs within this of the bridge centreline. The abutments
## occupy x in [49.5, 58.5], z in [-7.5, 7.5], and a rooftop in the player's
## sightline along the deck is worse than a gap in the terrace.
const BRIDGE_CLEAR_Z := 12.0

# --- Terrace layout ----------------------------------------------------------
#
# One row per level, river-side outwards. `front` is the |x| of that level's own
# retaining wall, which is also the front edge of its platform; `top` is the
# platform surface. A platform runs from its own `front` to the NEXT level's
# `front`, so treads are implied and the table cannot describe an impossible
# bank. `street` is how much of the tread is public cobbles in front of the
# buildings; `jog` is how far the wall wanders in and out along the river.
#
# Risers are deliberately uneven — 4.75, 4.50, 4.85, 3.55, 4.95 on Porto. A slope
# is cut into wherever the rock allowed, not divided into equal parts, and equal
# steps are exactly what makes a terraced hillside read as a wedding cake.

const PORTO_LEVELS := [
	{"front": 52.0, "top": -9.60, "street": 7.5, "jog": 0.55},
	{"front": 68.0, "top": -4.85, "street": 4.4, "jog": 1.50},
	{"front": 82.0, "top": -0.35, "street": 4.2, "jog": 1.85},
	{"front": 95.0, "top": 4.50, "street": 4.6, "jog": 1.60},
	{"front": 108.0, "top": 8.05, "street": 4.2, "jog": 2.10},
	{"front": 121.0, "top": 13.00, "street": 4.4, "jog": 1.70},
]
## Back of the top terrace, then open hillside up to the skyline crest.
const PORTO_BACK_X := 136.0
const PORTO_CREST_X := 180.0
const PORTO_CREST_Y := 21.0

const GAIA_LEVELS := [
	{"front": 52.0, "top": -9.60, "street": 8.0, "jog": 0.50},
	{"front": 74.0, "top": -5.20, "street": 4.6, "jog": 1.40},
	{"front": 88.0, "top": -0.90, "street": 4.2, "jog": 1.60},
]
const GAIA_BACK_X := 100.0
const GAIA_CREST_X := 158.0
const GAIA_CREST_Y := 14.0

## Serra do Pilar. Inside this Z window the bluff rises out of Gaia's first
## terrace and takes over from the second, climbing 14.5 m in 15 m of plan.
const BLUFF_Z0 := -66.0
const BLUFF_Z1 := -4.0
const BLUFF_TOE_X := 85.0
const BLUFF_PLATEAU_Y := 9.30
const BLUFF_SHOULDER := 0.24

## The river narrows going upstream. Four and a half metres over the whole reach:
## not enough to notice, enough to stop the two banks reading as rails.
const BANK_TAPER := 0.028

# --- Escadarias --------------------------------------------------------------
# `from`/`to` are level indices; a station builds one flight per level it climbs
# through, doglegged in Z at every landing so the route bends the way a real one
# does, and each flight cuts its own slot through the wall it passes.

const STAIR_HALF := 2.55
const STAIR_WIDTH := 3.1

const PORTO_STAIRS := [
	{"z": 16.0, "from": 0, "to": 2},
	{"z": -24.0, "from": 0, "to": 3},
	{"z": -52.0, "from": 1, "to": 4},
	{"z": -84.0, "from": 2, "to": 5},
]
const GAIA_STAIRS := [
	{"z": 18.0, "from": 0, "to": 1},
	{"z": -74.0, "from": 0, "to": 2},
]

# --- Plot rhythm -------------------------------------------------------------

const PLOT_MIN := 3.2      # narrow Ribeira frontage
const PLOT_MAX := 5.4
const ALLEY_MIN := 1.9     # becos: shoulder-width slots between the blocks
const ALLEY_MAX := 3.2
const BLOCK_MIN := 4       # plots between one alley and the next
const BLOCK_MAX := 7

const DEFAULT_SEED := 20250727

## Filled by build(). The probe reads it; it is also handy at a breakpoint.
static var last_stats: Dictionary = {}

static var _plot_cache: Dictionary = {}


# --- Public queries ----------------------------------------------------------

## Levels on one bank. Level 0 is always the waterfront cais.
static func level_count(side: float) -> int:
	return _levels(side).size()


## Signed world x of a level's retaining wall — which is also the front edge of
## its platform — at `z`. Includes the gorge's upstream taper and the wall's own
## wander, so it is the real face position and not the table value.
##
## `level == level_count()` returns the back of the top terrace, which is what
## lets the platform loops terminate without a special case.
static func front_x(side: float, level: int, z: float) -> float:
	var levels := _levels(side)
	if level >= levels.size():
		return side * ((PORTO_BACK_X if side < 0.0 else GAIA_BACK_X) + _taper(z))
	var row: Dictionary = levels[level]
	return side * (float(row["front"]) + _taper(z) + _jog(side, level, z, float(row["jog"])))


## A level's platform height at `z`, at its front edge and before camber.
static func terrace_top(side: float, level: int, z: float) -> float:
	var levels := _levels(side)
	var row: Dictionary = levels[clampi(level, 0, levels.size() - 1)]
	return lerpf(WATER_Y, float(row["top"]) + _drift(side, level, z), _end_fade(z))


## Height of the ground at (x, z) — the query placement code should use, and the
## one every ground surface in this file is built from.
##
## Water outside the banks and downstream of the headland. On a platform it is
## the paved surface including camber and cross-fall, so a building sat on it is
## sat on it. Behind the top terrace it is the eroded hillside, and on the Gaia
## bluff the scarp profile — approximate there to a couple of decimetres, since
## the strata are jittered per block and nothing stands on them.
static func ground_height(x: float, z: float) -> float:
	if z > HEADLAND_Z or z < BANK_Z_FAR:
		return WATER_Y
	var side := PORTO if x < 0.0 else GAIA
	var ax := absf(x)
	var levels := _levels(side)

	if ax < absf(front_x(side, 0, z)):
		return WATER_Y
	if side > 0.0 and ax >= BLUFF_TOE_X and _bluff_window(z) > 0.02:
		return _bluff_y(ax, z)
	if ax >= absf(front_x(side, levels.size(), z)):
		return _upland_y(side, ax, z)

	for l in range(levels.size() - 1, -1, -1):
		var f := absf(front_x(side, l, z))
		if ax >= f:
			var top := terrace_top(side, l, z)
			return MK.surface_y(f, absf(front_x(side, l + 1, z)), top, top + _back_fall(l),
					_crown(l), 0.16, _land_key(side) + l, ax, z)
	return WATER_Y


## Where buildings go on one bank: one plot per house, alleys already subtracted,
## ordered by level then by z. Cached, so callers may ask repeatedly.
##
## Each entry:
##   center   Vector3 at the middle of the footprint, y = ground there
##   width    frontage along Z
##   depth    along X
##   facing   unit vector the front of the building looks along (toward the river)
##   level    terrace index, 0 = standing on the cais
##   side     PORTO / GAIA
##   detail   2 = near enough to read as a building, 1 = silhouette only
static func building_plots(side: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var cached: Array = _plot_cache.get(side, [])
	if not cached.is_empty():
		out.assign(cached)
		return out

	var levels := _levels(side)
	for l in levels.size():
		var row: Dictionary = levels[l]
		var street := float(row["street"])
		var slots := _stair_slots(side, l + 1)     # the wall BEHIND this platform
		var z := BANK_Z_FAR + 2.0
		var in_block := 0
		var block_len := BLOCK_MIN + int(MK.hash01(int(side) * 31 + l, 0) * float(BLOCK_MAX - BLOCK_MIN))
		var i := 0
		while z < BANK_Z_NEAR - 2.0:
			var w := lerpf(PLOT_MIN, PLOT_MAX, MK.hash01(int(side) * 71 + l * 13, i))
			var zc := z + w * 0.5
			var blocked := _blocked(zc, w, slots) or (l <= 1 and absf(zc) < BRIDGE_CLEAR_Z)
			if not blocked:
				var f := absf(front_x(side, l, zc))
				var b := absf(front_x(side, l + 1, zc))
				var depth := maxf(4.6, b - f - street - 0.7)
				var cx := f + street + depth * 0.5
				out.append({
					"center": Vector3(side * cx, ground_height(side * cx, zc), zc),
					"width": w,
					"depth": depth,
					"facing": Vector3(-side, 0.0, 0.0),
					"level": l,
					"side": side,
					"detail": 2 if (zc > NEAR_Z_FAR and l <= 3) else 1,
				})
			z += w
			i += 1
			in_block += 1
			if in_block >= block_len:
				z += lerpf(ALLEY_MIN, ALLEY_MAX, MK.hash01(int(side) * 97 + l, i))
				in_block = 0
				block_len = BLOCK_MIN + int(MK.hash01(int(side) * 31 + l, i) * float(BLOCK_MAX - BLOCK_MIN))
	_plot_cache[side] = out.duplicate()
	return out


# --- Build -------------------------------------------------------------------

## Everything. The returned node belongs at the origin — all geometry is baked in
## world coordinates, so moving it moves the riverbank off the river.
static func build(seed: int = DEFAULT_SEED) -> Node3D:
	var root := Node3D.new()
	root.name = "Terrain"

	var near := TerrainBatch.new()
	var far := TerrainBatch.new()
	far.cast_shadows = false

	for side_i in 2:
		var side := PORTO if side_i == 0 else GAIA
		var bank_seed := seed + side_i * 4093
		for l in _levels(side).size():
			_build_level(near, far, side, l, bank_seed)
		_build_stairs(near, side, bank_seed)
		_build_upland(near, far, side)
		_build_waterfront(near, side, bank_seed)
		_build_planting(near, far, side, bank_seed)

	_build_bluff(near, far, seed)
	_build_headlands(near, seed)

	root.add_child(near.commit("TerrainNear"))
	root.add_child(far.commit("TerrainFar"))
	last_stats = {
		"triangles": near.triangle_count() + far.triangle_count(),
		"surfaces": near.surface_count() + far.surface_count(),
		"near_triangles": near.triangle_count(),
		"far_triangles": far.triangle_count(),
		"near_surfaces": near.surface_count(),
		"far_surfaces": far.surface_count(),
	}
	return root


# --- Ground sheets -----------------------------------------------------------

## A quad grid over an X span, sampling ground_height() at every corner.
##
## Every ground surface goes through here. Corners are shared exactly between
## neighbouring cells because the height is a pure function of position, so the
## sheet cannot crack; and because it is the SAME function placement code asks,
## nothing that stands on it can float.
static func _ground_grid(b: MeshBaker, side: float, x0: float, x1: float,
		z0: float, z1: float, x_div: int, z_step: float) -> void:
	var z_div := maxi(1, int(ceil(absf(z1 - z0) / z_step)))
	var dx := (x1 - x0) / float(x_div)
	var dz := (z1 - z0) / float(z_div)
	for i in x_div:
		var xa := side * (x0 + dx * float(i))
		var xb := side * (x0 + dx * float(i + 1))
		for j in z_div:
			var za := z0 + dz * float(j)
			var zb := za + dz
			var p00 := Vector3(xa, ground_height(xa, za), za)
			var p10 := Vector3(xb, ground_height(xb, za), za)
			var p11 := Vector3(xb, ground_height(xb, zb), zb)
			var p01 := Vector3(xa, ground_height(xa, zb), zb)
			# Wound so the normal comes out +Y whichever way the span runs.
			if (side * dx * dz) > 0.0:
				b.add_quad(p00, p01, p11, p10, Vector2(absf(dz), absf(dx)))
			else:
				b.add_quad(p00, p10, p11, p01, Vector2(absf(dx), absf(dz)))


# --- One terrace level -------------------------------------------------------

## Wall, coping, buttresses, weep holes and platform for one level.
##
## The wall belongs to the level it holds up and its toe is the platform below,
## which is why level 0's wall is the quay wall and needs no special case beyond
## footing under the water.
static func _build_level(near, far, side: float, level: int, seed: int) -> void:
	var lseed := seed + level * 617
	var outward := -side
	var toe := WALL_FOOT_Y if level == 0 else _wall_toe_y(side, level)
	var coping_h := 0.34 if level == 0 else 0.26
	var slots := _stair_slots(side, level)

	for span in _spans(BANK_Z_FAR, BANK_Z_NEAR, slots):
		_wall_run(near, far, side, level, span.x, span.y, toe, coping_h, lseed)

	# Buttresses on the deep walls only; a 4 m garden wall does not need them.
	if float((_levels(side)[level] as Dictionary)["top"]) - toe > 4.0:
		var pitch := 9.5 + float(level) * 1.4
		var n := int((BANK_Z_NEAR - BANK_Z_FAR) / pitch)
		for i in n:
			var z := BANK_Z_FAR + pitch * (float(i) + 0.5)
			if _blocked(z, 2.4, slots):
				continue
			var batch = near if z > NEAR_Z_FAR else far
			MK.buttress(batch.granite(), z, front_x(side, level, z), outward,
					toe - 0.4, terrace_top(side, level, z) - coping_h - 0.15,
					1.4 + MK.hash01(lseed, i) * 0.6, 0.55 + MK.hash01(lseed + 3, i) * 0.35)

	# Platform, in two reaches so each lands in the right bake.
	var back := level + 1
	for reach in 2:
		var z0 := NEAR_Z_FAR if reach == 0 else BANK_Z_FAR
		var z1 := BANK_Z_NEAR if reach == 0 else NEAR_Z_FAR
		var batch = near if reach == 0 else far
		var zm := (z0 + z1) * 0.5
		_ground_grid(batch.cobble(), side,
				absf(front_x(side, level, zm)), absf(front_x(side, back, zm)),
				z0, z1, 6 if reach == 0 else 3, 5.0 if reach == 0 else 9.0)


## Toe of a retaining wall: the platform below it, dropped clear of that
## platform's own drift so the wall is buried into it rather than hovering over
## the low points of it.
static func _wall_toe_y(side: float, level: int) -> float:
	return float((_levels(side)[level - 1] as Dictionary)["top"]) - 1.4


## One run of retaining wall between two stair slots, with its coping, weep
## holes and — on the near reach — individual blocks and a street parapet.
static func _wall_run(near, far, side: float, level: int, z0: float, z1: float,
		toe: float, coping_h: float, seed: int) -> void:
	var outward := -side
	# Chop at the near/far boundary, and again into short pieces so a far-reach
	# band (which cannot follow a drifting top) never has far to follow.
	var cuts: Array[float] = []
	var z := z0
	while z < z1 - 0.4:
		var limit := NEAR_Z_FAR if z < NEAR_Z_FAR else z1
		var piece := 14.0 if z < NEAR_Z_FAR else (z1 - z)
		cuts.append(z)
		z = minf(z + piece, minf(limit, z1))
	cuts.append(z1)

	for i in range(cuts.size() - 1):
		var a := cuts[i]
		var b := cuts[i + 1]
		if b - a < 0.4:
			continue
		var is_near := (a + b) * 0.5 > NEAR_Z_FAR
		var batch = near if is_near else far
		var fa := front_x(side, level, a)
		var fb := front_x(side, level, b)
		var ya := terrace_top(side, level, a)
		var yb := terrace_top(side, level, b)
		if is_near:
			# Heavier courses and bigger stones on the quay wall than on a garden
			# retaining wall, which is how they are actually built: the river face
			# takes the tide and the boats.
			MK.coursed_wall(batch.granite(), a, b, fa, fb, outward, toe,
					ya - coping_h, yb - coping_h,
					1.3 if level == 0 else 0.9, 0.78 if level == 0 else 0.60,
					1.2 if level == 0 else 0.85, 2.6 if level == 0 else 1.8,
					0.055, seed + int(a))
		else:
			MK.banded_wall(batch.granite(), a, b, fa, fb, outward, toe,
					ya - coping_h, yb - coping_h,
					1.3 if level == 0 else 0.9, 1.05, 0.055, seed + int(a))
		var proud := 0.20 if level == 0 else 0.16
		MK.coping(batch.dressed(), a, b, fa, fb, outward, ya + proud, yb + proud,
				0.95 if level == 0 else 0.62, coping_h, 0.14, 2.3, seed + 11)
		if is_near:
			MK.weep_holes(batch.dark(), a, b, fa, fb, outward,
					toe + (ya - coping_h - toe) * 0.33, 4.5, seed + level * 5)
			# A parapet only where there is a street behind the drop. The quay's
			# own edge is left open, which is what makes it a quay.
			if level >= 1:
				MK.edge_parapet(batch, a, b, fa, fb, outward, ya + 0.16, yb + 0.16,
						seed + level * 29)


# --- Escadarias --------------------------------------------------------------

static func _build_stairs(near, side: float, seed: int) -> void:
	var stations := PORTO_STAIRS if side < 0.0 else GAIA_STAIRS
	for si in stations.size():
		var st: Dictionary = stations[si]
		for level in range(int(st["from"]) + 1, int(st["to"]) + 1):
			var z := _stair_z(side, si, level)
			var f := absf(front_x(side, level, z))
			# Foot stands on the platform below, clear of the wall; head lands on
			# the street of the platform above.
			MK.stair_flight(near, z, STAIR_WIDTH,
					side * (f - 5.4), terrace_top(side, level - 1, z),
					side * (f + 2.6), terrace_top(side, level, z),
					seed + si * 37 + level, true)


## Dogleg: each landing shifts the route a couple of metres along the river.
static func _stair_z(side: float, station: int, level: int) -> float:
	var stations := PORTO_STAIRS if side < 0.0 else GAIA_STAIRS
	var st: Dictionary = stations[station]
	return float(st["z"]) + MK.hash_sym(int(side) * 53 + station * 19, level) * 3.4


## Z spans a level's wall must skip, one per flight climbing through it.
static func _stair_slots(side: float, level: int) -> Array[Vector2]:
	var slots: Array[Vector2] = []
	var stations := PORTO_STAIRS if side < 0.0 else GAIA_STAIRS
	for si in stations.size():
		var st: Dictionary = stations[si]
		if level <= int(st["from"]) or level > int(st["to"]):
			continue
		var z := _stair_z(side, si, level)
		slots.append(Vector2(z - STAIR_HALF, z + STAIR_HALF))
	slots.sort_custom(func(p: Vector2, q: Vector2) -> bool: return p.x < q.x)
	return slots


# --- Waterfront --------------------------------------------------------------

## What makes a cais a cais: bollards along the coping, mooring rings on the wall
## face, and flights of steps running down into the river.
static func _build_waterfront(near, side: float, seed: int) -> void:
	var outward := -side
	var pitch := 7.4
	var n := int((BANK_Z_NEAR - NEAR_Z_FAR) / pitch)
	for i in n:
		var z := NEAR_Z_FAR + pitch * (float(i) + 0.5)
		if absf(z) < BRIDGE_CLEAR_Z * 0.8:
			continue
		var fx := front_x(side, 0, z)
		MK.bollard(near, Vector3(fx - outward * 0.95, terrace_top(side, 0, z) + 0.02, z),
				outward, seed + i * 7)
		if i % 2 == 0:
			MK.mooring_ring(near.iron(),
					Vector3(fx + outward * 0.10, terrace_top(side, 0, z) - 1.9, z), 0.22,
					seed + i)

	for k in 2:
		var z := -20.0 - float(k) * 36.0 + MK.hash_sym(seed, k) * 4.0
		MK.water_steps(near, z, front_x(side, 0, z), outward,
				terrace_top(side, 0, z) - 0.10, WATER_Y - 0.6, 3.4, 5.4, seed + k * 13)

	# The quay face is permanently damp; ivy and weed take it wherever a boat is
	# not tied up.
	for spot in [Vector2(-40.0, -29.0), Vector2(2.0, 14.0)]:
		var zm := (spot.x + spot.y) * 0.5
		FK.ivy_curtain(near.leaf_dark(), spot.x, spot.y, front_x(side, 0, zm), outward,
				terrace_top(side, 0, zm) - 0.55, 2.8, seed + int(zm), true)


# --- Hillside behind the top terrace -----------------------------------------

static func _build_upland(near, far, side: float) -> void:
	var back := PORTO_BACK_X if side < 0.0 else GAIA_BACK_X
	var crest := PORTO_CREST_X if side < 0.0 else GAIA_CREST_X
	for reach in 2:
		var z0 := NEAR_Z_FAR if reach == 0 else BANK_Z_FAR
		var z1 := BANK_Z_NEAR if reach == 0 else NEAR_Z_FAR
		var batch = near if reach == 0 else far
		_ground_grid(batch.earth(), side, back, crest, z0, z1,
				6 if reach == 0 else 4, 8.0 if reach == 0 else 14.0)


# --- Serra do Pilar ----------------------------------------------------------

## The bluff, and the scree and scrub that make its toe look eroded rather than
## sawn. Only part of its run is inside shadow range, so it splits near/far like
## everything else.
static func _build_bluff(near, far, seed: int) -> void:
	var toe_y := float((GAIA_LEVELS[1] as Dictionary)["top"])
	var splits := [BLUFF_Z0, maxf(BLUFF_Z0, NEAR_Z_FAR), BLUFF_Z1]
	for i in range(splits.size() - 1):
		var a: float = splits[i]
		var b: float = splits[i + 1]
		if b - a < 1.0:
			continue
		var batch = near if (a + b) * 0.5 > NEAR_Z_FAR else far
		RK.strata_bluff(batch, a, b, BLUFF_TOE_X, toe_y, GAIA_BACK_X, BLUFF_PLATEAU_Y,
				-1.0, seed + 71, 4.2, 1.15, BLUFF_SHOULDER)
		RK.scree(batch, a, b, BLUFF_TOE_X, -1.0, toe_y, 4.5, seed + 73, 0.62)

	# Scrub caught on two bands of setbacks. It is what stops a scarp reading as
	# masonry, and it costs 60 triangles a clump.
	for i in 7:
		var t := (float(i) + 0.5) / 7.0
		var z := lerpf(BLUFF_Z0, BLUFF_Z1, t)
		var w := RK._shoulder(t, BLUFF_SHOULDER)
		if w < 0.25:
			continue
		var batch = near if z > NEAR_Z_FAR else far
		for k in 2:
			var f := 0.35 + float(k) * 0.34
			var y := lerpf(toe_y, lerpf(toe_y, BLUFF_PLATEAU_Y, w), f)
			var x := lerpf(BLUFF_TOE_X, GAIA_BACK_X, pow(f, 1.55)) - 1.0
			FK.scrub(batch.leaf_dark(),
					Vector3(x, y, z + MK.hash_sym(seed, i * 3 + k) * 2.0),
					0.9 + MK.hash01(seed + 2, i + k) * 0.7, seed + i * 29 + k)

	# Cypresses along the plateau lip: the monastery's own skyline.
	for i in 9:
		if MK.hash01(seed + 17, i) < 0.22:
			continue
		var z := lerpf(BLUFF_Z0 + 6.0, BLUFF_Z1 - 6.0, (float(i) + 0.5) / 9.0)
		var x := GAIA_BACK_X + 1.6 + MK.hash01(seed + 19, i) * 3.0
		var batch = near if z > NEAR_Z_FAR else far
		FK.cypress(batch.leaf_dark(), Vector3(x, ground_height(x, z) - 0.2, z),
				5.5 + MK.hash01(seed + 23, i) * 3.5, seed + i * 41)


# --- Headland ----------------------------------------------------------------

## Downstream of BANK_Z_NEAR the terraces sink into the water. Bare rock with a
## rubble toe: this is the last thing before open river, and a manicured quay
## ending in mid-air is worse than a natural one.
static func _build_headlands(near, seed: int) -> void:
	for side_i in 2:
		var side := PORTO if side_i == 0 else GAIA
		var front := absf(front_x(side, 0, BANK_Z_NEAR))
		var back := absf(front_x(side, _levels(side).size(), BANK_Z_NEAR))
		var b := near.rock()
		_ground_grid(b, side, front, back, BANK_Z_NEAR, HEADLAND_Z, 6, 3.5)

		# Close the river-facing edge, or the sheet is a flap seen edge-on from
		# anywhere downstream.
		var steps := 5
		for j in steps:
			var za := lerpf(BANK_Z_NEAR, HEADLAND_Z, float(j) / float(steps))
			var zb := lerpf(BANK_Z_NEAR, HEADLAND_Z, float(j + 1) / float(steps))
			var xa := side * front
			var top_a := Vector3(xa, ground_height(xa, za), za)
			var top_b := Vector3(xa, ground_height(xa, zb), zb)
			var foot_a := Vector3(xa, WALL_FOOT_Y, za)
			var foot_b := Vector3(xa, WALL_FOOT_Y, zb)
			# Porto's river face looks +X, Gaia's looks -X.
			if side < 0.0:
				b.add_quad(foot_b, foot_a, top_a, top_b, Vector2(zb - za, 6.0))
			else:
				b.add_quad(foot_a, foot_b, top_b, top_a, Vector2(zb - za, 6.0))

		RK.scree(near, BANK_Z_NEAR + 1.0, HEADLAND_Z - 2.0, side * (front + 1.0),
				-side, WATER_Y + 0.4, 5.0, seed + side_i * 91, 0.75)
		for k in 3:
			RK.boulder(b, Vector3(side * (front + 2.0 + float(k) * 3.4),
					WATER_Y + 0.5, BANK_Z_NEAR + 5.0 + float(k) * 9.0),
					1.6 + MK.hash01(seed, k) * 1.4, seed + k * 5)


# --- Planting ----------------------------------------------------------------

## Trees, ivy and planters, placed where planting does the most work: on the
## terrace edges where it breaks the horizontal, on the wall faces where it
## breaks the masonry, and along the promenade where it gives the eye something
## at human scale next to a 23 m hillside.
static func _build_planting(near, far, side: float, seed: int) -> void:
	var levels := _levels(side)
	var outward := -side

	# Plane trees down the middle of the cais, in two runs so the bridge landing
	# stays open.
	var row_x := side * (absf(front_x(side, 0, 0.0)) + 4.2)
	FK.tree_row(near, row_x, -70.0, -BRIDGE_CLEAR_Z - 2.0, 9.5, 6.5, 9.5,
			terrace_top(side, 0, -40.0) + 0.1, seed + 101, 0.24)
	FK.tree_row(near, row_x, BRIDGE_CLEAR_Z + 2.0, BANK_Z_NEAR - 4.0, 9.5, 6.0, 9.0,
			terrace_top(side, 0, 20.0) + 0.1, seed + 103, 0.24)

	# Planters flanking the bridge landing. Kept off z in [-7.5, 7.5], which is
	# where the abutment block comes up through the quay.
	for i in 4:
		var z: float = [-11.5, -9.0, 9.0, 11.5][i]
		FK.planter(near, Vector3(side * (absf(front_x(side, 0, z)) + 3.2),
				terrace_top(side, 0, z), z), Vector3(1.5, 0.75, 1.5), seed + i * 9)

	for l in range(1, levels.size()):
		var wseed := seed + l * 211
		var top := float((levels[l] as Dictionary)["top"])
		var toe := float((levels[l - 1] as Dictionary)["top"])
		# Weeds along every wall toe, thinning out upstream where nobody looks.
		for reach in 2:
			var z0 := NEAR_Z_FAR if reach == 0 else BANK_Z_FAR
			var z1 := BANK_Z_NEAR if reach == 0 else NEAR_Z_FAR
			var batch = near if reach == 0 else far
			FK.wall_toe(batch.leaf_dark(), z0, z1, front_x(side, l, (z0 + z1) * 0.5),
					outward, toe + 0.15, wseed, 0.6 if reach == 0 else 0.28)
		# Ivy hanging off two or three bays of each coping.
		for k in 3:
			if MK.hash01(wseed + 1, k) < 0.3:
				continue
			var z := lerpf(BANK_Z_FAR + 15.0, BANK_Z_NEAR - 15.0,
					(float(k) + 0.5 + MK.hash_sym(wseed, k) * 0.3) / 3.0)
			var batch2 = near if z > NEAR_Z_FAR else far
			FK.ivy_curtain(batch2.leaf_dark(), z - 5.0, z + 5.0, front_x(side, l, z),
					outward, top - 0.45, minf(top - toe - 0.8, 4.2), wseed + k * 7, true)
		# Cypresses on the terrace edge — the vertical accent against the steps.
		for k in 6:
			if MK.hash01(wseed + 5, k) < 0.42:
				continue
			var z := lerpf(BANK_Z_FAR + 8.0, BANK_Z_NEAR - 8.0, (float(k) + 0.5) / 6.0)
			var x := side * (absf(front_x(side, l, z)) + 1.4 + MK.hash01(wseed, k) * 1.6)
			var batch3 = near if z > NEAR_Z_FAR else far
			FK.cypress(batch3.leaf_dark(), Vector3(x, ground_height(x, z) - 0.2, z),
					6.0 + MK.hash01(wseed + 9, k) * 4.0, wseed + k * 31)

	_build_alley_shadows(near, far, side)


## A void-dark slot at the back of every gap between blocks of plots.
##
## A city reads as a city because of the negative space between its buildings,
## and on a hillside that space is a shaded slot with a wall at the end of it.
## Standing the shadow up here means the alleys read as depth even before the
## placement stream has put a single building on either side of them.
static func _build_alley_shadows(near, far, side: float) -> void:
	var outward := -side
	var plots := building_plots(side)
	var prev_end := 0.0
	var prev_level := -1
	for p in plots:
		var level := int(p["level"])
		var zc: float = (p["center"] as Vector3).z
		var w: float = p["width"]
		if level == prev_level and zc - w * 0.5 - prev_end > ALLEY_MIN * 0.8:
			var z0 := prev_end
			var z1 := zc - w * 0.5
			var zm := (z0 + z1) * 0.5
			var batch = near if zm > NEAR_Z_FAR else far
			batch.dark().add_box(
				Vector3(0.5, 2.6, z1 - z0),
				Transform3D(Basis.IDENTITY,
					Vector3(front_x(side, level + 1, zm) - outward * 0.35,
						ground_height(front_x(side, level + 1, zm), zm) + 1.3, zm))
			)
		prev_end = zc + w * 0.5
		prev_level = level


# --- Layout maths ------------------------------------------------------------
#
# Everything below is a pure function of the tables above and takes no seed:
# ground_height() must give the same answer to the geometry and to the placement
# stream, and threading build()'s seed through here would break that the moment
# somebody called build() with a different one.

static func _levels(side: float) -> Array:
	return PORTO_LEVELS if side < 0.0 else GAIA_LEVELS


## Fixed per-bank key for the landform noise. Not build()'s seed; see above.
static func _land_key(side: float) -> int:
	return int(side) * 4093 + 3


## Upstream narrowing of the gorge.
static func _taper(z: float) -> float:
	return BANK_TAPER * clampf(z, BANK_Z_FAR, HEADLAND_Z)


## How far a wall wanders in and out along the river.
##
## Piecewise-constant with a short blend, NOT a sine: a retaining wall is built
## in straight runs with a return where the ground changes, so the front line
## should hold a bearing and then step. A smooth wobble reads as a snake.
static func _jog(side: float, level: int, z: float, amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var seg := 12.0 + float(level) * 2.3
	var key := int(side) * 977 + level * 131
	var i := int(floor(z / seg))
	var f := z / seg - float(i)
	return lerpf(MK.hash_sym(key, i), MK.hash_sym(key, i + 1), smoothstep(0.80, 1.0, f)) * amount


## Slow variation in a platform's height along the river, so a terrace is a
## contour rather than a datum. Smooth, unlike the wall's jog, and out of phase
## with it — the wall follows this, so a step here would step the coping too.
static func _drift(side: float, level: int, z: float) -> float:
	var seg := 30.0 + float(level) * 3.1
	var key := int(side) * 613 + level * 89
	var i := int(floor(z / seg))
	var f := z / seg - float(i)
	return lerpf(MK.hash_sym(key, i), MK.hash_sym(key, i + 1), smoothstep(0.0, 1.0, f)) * 0.45


## Terraces fall away from the river slightly, so rain runs to the street.
static func _back_fall(level: int) -> float:
	return 0.10 if level == 0 else 0.22


## Camber. Only the public cobbles are crowned; a building platform is not.
static func _crown(level: int) -> float:
	return 0.14 if level == 0 else 0.07


## 1 inside the modelled reach, easing to 0 across the headland.
static func _end_fade(z: float) -> float:
	if z <= BANK_Z_NEAR:
		return 1.0
	return 1.0 - smoothstep(BANK_Z_NEAR, HEADLAND_Z, z)


## Open hillside above the top terrace, both banks.
static func _upland_y(side: float, ax: float, z: float) -> float:
	var levels := _levels(side)
	var back := PORTO_BACK_X if side < 0.0 else GAIA_BACK_X
	var crest_x := PORTO_CREST_X if side < 0.0 else GAIA_CREST_X
	var crest_y := PORTO_CREST_Y if side < 0.0 else GAIA_CREST_Y
	var top := float((levels[levels.size() - 1] as Dictionary)["top"]) + _back_fall(levels.size() - 1)
	var y := RK.slope_y(back, crest_x, top, crest_y, 2.4, _land_key(side), ax, z)
	if side > 0.0:
		# The monastery plateau rides on top of the general hillside inside the
		# bluff's window and merges back into it at the shoulders.
		var w := _bluff_window(z)
		if w > 0.0:
			var t := clampf((ax - back) / maxf(crest_x - back, 1.0), 0.0, 1.0)
			var plateau := lerpf(BLUFF_PLATEAU_Y, crest_y, smoothstep(0.30, 1.0, t))
			y = lerpf(y, maxf(plateau, y), w)
	return lerpf(WATER_Y, y, _end_fade(z))


## How much of the Serra do Pilar bluff is present at `z` — 1 across the middle
## of its run, 0 outside it.
static func _bluff_window(z: float) -> float:
	if z < BLUFF_Z0 or z > BLUFF_Z1:
		return 0.0
	return RK._shoulder((z - BLUFF_Z0) / (BLUFF_Z1 - BLUFF_Z0), BLUFF_SHOULDER)


## Approximate height on the bluff face. Inverts RockKit's pow(f, 1.55) setback,
## which is what makes the scarp near-vertical at the toe and lay back at the
## crest.
static func _bluff_y(ax: float, z: float) -> float:
	var w := _bluff_window(z)
	var toe_y := float((GAIA_LEVELS[1] as Dictionary)["top"])
	var crest := lerpf(toe_y + 1.0, BLUFF_PLATEAU_Y, w)
	if ax >= GAIA_BACK_X:
		return maxf(crest, _upland_y(GAIA, ax, z))
	var t := clampf((ax - BLUFF_TOE_X) / maxf(GAIA_BACK_X - BLUFF_TOE_X, 1.0), 0.0, 1.0)
	return lerpf(toe_y, crest, pow(t, 1.0 / 1.55))


# --- Span maths --------------------------------------------------------------

## Does [center - w/2, center + w/2] touch any slot?
static func _blocked(center: float, w: float, slots: Array[Vector2]) -> bool:
	for s in slots:
		if center + w * 0.5 > s.x and center - w * 0.5 < s.y:
			return true
	return false


## [z0, z1] with every slot subtracted, as a list of (start, end) pairs.
static func _spans(z0: float, z1: float, slots: Array[Vector2]) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var cursor := z0
	for s in slots:
		if s.y <= cursor or s.x >= z1:
			continue
		if s.x > cursor:
			out.append(Vector2(cursor, minf(s.x, z1)))
		cursor = maxf(cursor, s.y)
	if cursor < z1:
		out.append(Vector2(cursor, z1))
	return out
