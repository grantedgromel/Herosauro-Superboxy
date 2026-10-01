extends RefCounted
## The static set of chapter "pandas", built once and baked: the cobbled square,
## the dry fountain, benches, lamp posts, the azulejo chapel closing the west
## end, the miradouro terrace on the east with its balustrade, and the view over
## the Douro to the Dom Luís I arch and the Serra do Pilar on the far bank.
##
## Collision follows the camera rule: everything a hero bumps into that is LOW
## (ground, kerbs, fountain rim, benches, balustrade, planters) is on WORLD; the
## tall things (facade rows, chapel, lamp posts, the fountain's column, the
## invisible fences above the low walls) are on BLOCKERS, which heroes collide with
## and the camera's spring arm does not.
##
## Layout (metres, the level root at the origin, +X toward the river):
##   house rows: facades at z = -13.5 (facing +Z) and z = +13.5 (facing -Z),
##               x from -18 to about 7.5;
##   chapel:     the west end, facade at x = -18 facing +X;
##   terrace:    x 7.5 .. 20, balustrade at x = 20, the drop to the river beyond;
##   fountain:   (-5, 0, 0).

const Kit := preload("res://scripts/levels/pandas/pandas_kit.gd")

const FOUNTAIN := Vector3(-5.0, 0.0, 0.0)
const FOUNTAIN_R := 3.0
const ROW_Z := 13.5
const ROW_X0 := -18.0
const ROW_X1 := 7.5
const RAIL_X := 20.0
const RIVER_Y := -14.0

const BENCHES: Array[Vector3] = [
	Vector3(17.4, 0.0, 5.2),     # terrace, facing the view (a suitcase spot)
	Vector3(17.4, 0.0, -3.2),
	Vector3(-14.6, 0.0, 6.2),    # by the chapel
]
const BENCH_YAWS: Array[float] = [PI * 0.5, PI * 0.5, PI * 0.5]
const LAMPS: Array[Vector3] = [
	Vector3(-11.6, 0.0, -11.3), Vector3(1.2, 0.0, -11.3),
	Vector3(-8.0, 0.0, 11.3), Vector3(4.6, 0.0, 11.3),
	Vector3(19.2, 0.0, -8.6), Vector3(19.2, 0.0, 9.6),
	Vector3(-17.0, 0.0, -4.6), Vector3(-17.0, 0.0, 4.6),
]
const LAMP_GLOBE_Y := 3.55
const PLANTERS: Array[Vector3] = [
	Vector3(10.5, 0.0, -12.4), Vector3(14.0, 0.0, -12.4),
	Vector3(10.5, 0.0, 12.4), Vector3(14.0, 0.0, 12.4), Vector3(18.6, 0.0, 12.4),
]


static func build(level: Node3D) -> Dictionary:
	var out := {}
	var stone := Kit.VBaker.new()
	var wood := Kit.VBaker.new()
	var iron := Kit.VBaker.new()
	var soft := Kit.VBaker.new()
	var tiles := Kit.VBaker.new()
	var glow := Kit.VBaker.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5A0A

	# --- Ground: one cobble sheet, granite paving laid over it. ---
	var ground := MeshBaker.new()
	ground.add_box(Vector3(48.0, 1.0, 36.0), Transform3D(Basis(), Vector3(0.0, -0.5, 0.0)))
	var gmi := ground.commit(SceneryKit.world_mapped(ToonFactory.cobblestone(Color(0.56, 0.52, 0.47), 1.2)), "Cobbles", false)
	level.add_child(gmi)
	_paving(stone, rng)
	_fountain(stone, soft, rng)
	for i in BENCHES.size():
		_bench(wood, iron, BENCHES[i], BENCH_YAWS[i])
	for p in LAMPS:
		_lamp(iron, p)
	_terrace(stone, soft, rng)
	_chapel(stone, wood, tiles, glow, soft, rng)
	_details(iron, soft, wood, rng)

	level.add_child(stone.bake(Kit.vc("stone"), "Granite"))
	level.add_child(wood.bake(Kit.vc("wood"), "Wood"))
	level.add_child(iron.bake(Kit.vc("iron"), "Iron"))
	level.add_child(soft.bake(Kit.vc("soft"), "Greenery"))
	level.add_child(tiles.bake(Kit.azulejo(0), "ChapelTiles", false))
	level.add_child(glow.bake(Kit.window_glow(), "ChapelWindows", false))
	_backdrop(level, rng)
	_colliders(level)
	out["lamps"] = LAMPS
	return out


# --- Square ----------------------------------------------------------------------

static func _paving(stone: Kit.VBaker, rng: RandomNumberGenerator) -> void:
	# Granite pavements along both rows, with a kerb line.
	for sz: float in [-1.0, 1.0]:
		var z: float = sz * (ROW_Z - 0.7)
		stone.box(Vector3(ROW_X1 - ROW_X0, 0.04, 1.4), Vector3((ROW_X0 + ROW_X1) * 0.5, 0.02, z),
			Color(0.66, 0.63, 0.59))
		stone.box(Vector3(ROW_X1 - ROW_X0, 0.06, 0.22), Vector3((ROW_X0 + ROW_X1) * 0.5, 0.03, sz * (ROW_Z - 1.5)),
			Color(0.66, 0.64, 0.6))
		var x := ROW_X0
		while x < ROW_X1 - 0.5:
			var w := rng.randf_range(0.9, 1.5)
			stone.box(Vector3(0.03, 0.045, 1.4), Vector3(x, 0.022, z), Color(0.6, 0.58, 0.55))
			x += w
	# A ring of granite round the fountain.
	for i in 24:
		var a := TAU * float(i) / 24.0
		var r := FOUNTAIN_R + 1.0
		var p := FOUNTAIN + Vector3(cos(a) * r, 0.02, sin(a) * r)
		var tone := Color(0.7, 0.67, 0.62) if i % 2 == 0 else Color(0.6, 0.57, 0.53)
		stone.box(Vector3(1.0, 0.04, 1.75), p, tone, Vector3(0.0, -a, 0.0))
	# Terrace slabs in two tones.
	for ix in 6:
		for iz in 13:
			var p := Vector3(ROW_X1 + 0.3 + 2.0 * float(ix) + 1.0, 0.015, -13.0 + 2.0 * float(iz) + 1.0)
			if p.x > RAIL_X - 0.2:
				continue
			var tone := Color(0.66, 0.62, 0.57) if (ix + iz) % 2 == 0 else Color(0.55, 0.52, 0.49)
			stone.box(Vector3(1.96, 0.03, 1.96), p, tone.darkened(rng.randf_range(0.0, 0.05)))


static func _fountain(stone: Kit.VBaker, soft: Kit.VBaker, rng: RandomNumberGenerator) -> void:
	var c := FOUNTAIN
	var granite := Color(0.7, 0.67, 0.62)
	# Octagonal basin wall and rim.
	for i in 8:
		var a := TAU * float(i) / 8.0
		var r := FOUNTAIN_R - 0.2
		var side := 2.0 * FOUNTAIN_R * tan(PI / 8.0)
		var p := c + Vector3(cos(a) * r, 0.36, sin(a) * r)
		stone.box(Vector3(0.42, 0.72, side + 0.1), p, granite.darkened(0.06), Vector3(0.0, -a, 0.0))
		stone.box(Vector3(0.62, 0.14, side + 0.32), c + Vector3(cos(a) * r, 0.79, sin(a) * r), granite.lightened(0.06),
			Vector3(0.0, -a, 0.0))
	# Dry basin floor with a few dead leaves.
	stone.cyl(FOUNTAIN_R - 0.3, 0.2, Transform3D(Basis(), c + Vector3(0.0, 0.1, 0.0)), Color(0.52, 0.5, 0.47), 16)
	for k in 9:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.8, 2.3)
		soft.box(Vector3(0.16, 0.02, 0.1), c + Vector3(cos(a) * r, 0.21, sin(a) * r),
			Color(0.7, 0.5, 0.25).darkened(rng.randf() * 0.2), Vector3(0.0, rng.randf() * TAU, 0.0))
	# Column, bowl, upper column and a pine-cone finial.
	stone.cyl(0.55, 1.3, Transform3D(Basis(), c + Vector3(0.0, 0.85, 0.0)), granite, 12)
	stone.cyl(0.75, 0.2, Transform3D(Basis(), c + Vector3(0.0, 0.3, 0.0)), granite.darkened(0.08), 12)
	stone.cyl(1.25, 0.28, Transform3D(Basis(), c + Vector3(0.0, 1.62, 0.0)), granite.lightened(0.04), 16)
	stone.cyl(0.9, 0.18, Transform3D(Basis(), c + Vector3(0.0, 1.42, 0.0)), granite.darkened(0.05), 16)
	stone.cyl(0.24, 0.8, Transform3D(Basis(), c + Vector3(0.0, 2.15, 0.0)), granite, 10)
	stone.blob(Vector3(0.3, 0.42, 0.3), Transform3D(Basis(), c + Vector3(0.0, 2.8, 0.0)), granite.lightened(0.05), 10, 6)
	for i in 4:
		var a := TAU * float(i) / 4.0 + PI * 0.25
		stone.blob(Vector3(0.14, 0.12, 0.14), Transform3D(Basis(), c + Vector3(cos(a) * 0.62, 1.05, sin(a) * 0.62)),
			granite.darkened(0.1), 8, 5)


static func _bench(wood: Kit.VBaker, iron: Kit.VBaker, at: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	var w := Color(0.62, 0.38, 0.22)
	for k in 3:
		wood.box_xf(Vector3(2.0, 0.06, 0.14), Transform3D(b, at + b * Vector3(0.0, 0.46, -0.16 + 0.17 * float(k))),
			w.lightened(0.04 * float(k)))
	for k in 2:
		wood.box_xf(Vector3(2.0, 0.13, 0.05), Transform3D(b.rotated(b.x, -0.2), at + b * Vector3(0.0, 0.66 + 0.17 * float(k), -0.3)), w)
	for sx: float in [-0.85, 0.85]:
		iron.box_xf(Vector3(0.07, 0.46, 0.5), Transform3D(b, at + b * Vector3(sx, 0.23, 0.0)), Color(0.16, 0.24, 0.2))
		iron.box_xf(Vector3(0.06, 0.55, 0.06), Transform3D(b, at + b * Vector3(sx, 0.72, -0.31)), Color(0.16, 0.24, 0.2))


static func _lamp(iron: Kit.VBaker, at: Vector3) -> void:
	var green := Color(0.14, 0.24, 0.2)
	iron.cyl(0.24, 0.35, Transform3D(Basis(), at + Vector3(0.0, 0.17, 0.0)), green, 10)
	iron.cyl(0.08, 3.0, Transform3D(Basis(), at + Vector3(0.0, 1.8, 0.0)), green, 8)
	iron.cyl(0.14, 0.25, Transform3D(Basis(), at + Vector3(0.0, 0.5, 0.0)), green, 10)
	iron.cyl(0.22, 0.08, Transform3D(Basis(), at + Vector3(0.0, LAMP_GLOBE_Y - 0.36, 0.0)), green, 10)
	iron.cyl(0.26, 0.1, Transform3D(Basis(), at + Vector3(0.0, LAMP_GLOBE_Y + 0.38, 0.0)), green, 10)
	iron.blob(Vector3(0.1, 0.12, 0.1), Transform3D(Basis(), at + Vector3(0.0, LAMP_GLOBE_Y + 0.52, 0.0)), green, 8, 5)
	for i in 4:
		var a := TAU * float(i) / 4.0
		iron.box(Vector3(0.03, 0.72, 0.03), at + Vector3(cos(a) * 0.21, LAMP_GLOBE_Y, sin(a) * 0.21), green)


static func _terrace(stone: Kit.VBaker, soft: Kit.VBaker, rng: RandomNumberGenerator) -> void:
	var granite := Color(0.72, 0.69, 0.64)
	# Balustrade along x = RAIL_X.
	stone.box(Vector3(0.5, 0.18, 27.4), Vector3(RAIL_X + 0.25, 0.09, 0.0), granite.darkened(0.08))
	stone.box(Vector3(0.62, 0.16, 27.6), Vector3(RAIL_X + 0.25, 1.02, 0.0), granite.lightened(0.05))
	var z := -13.4
	while z < 13.4:
		stone.blob(Vector3(0.12, 0.38, 0.12), Transform3D(Basis(), Vector3(RAIL_X + 0.25, 0.56, z)), granite, 8, 5)
		z += 0.42
	for k in 7:
		var pz := -13.5 + 4.5 * float(k)
		stone.box(Vector3(0.6, 1.2, 0.6), Vector3(RAIL_X + 0.25, 0.6, pz), granite.darkened(0.04))
		stone.blob(Vector3(0.24, 0.24, 0.24), Transform3D(Basis(), Vector3(RAIL_X + 0.25, 1.4, pz)), granite.lightened(0.04), 8, 5)
	# The drop: a granite retaining wall down to the quay.
	stone.box(Vector3(1.6, 14.2, 34.0), Vector3(RAIL_X + 1.3, RIVER_Y * 0.5 - 0.1, 0.0), Color(0.6, 0.57, 0.53))
	stone.box(Vector3(6.0, 0.8, 220.0), Vector3(RAIL_X + 5.0, RIVER_Y + 0.4, 0.0), Color(0.66, 0.63, 0.58))
	# Low side walls of the terrace, with planters of oleander and geraniums.
	for sz: float in [-1.0, 1.0]:
		stone.box(Vector3(RAIL_X - ROW_X1, 0.9, 0.7), Vector3((ROW_X1 + RAIL_X) * 0.5, 0.45, sz * (ROW_Z - 0.1)), granite)
		stone.box(Vector3(RAIL_X - ROW_X1 + 0.1, 0.12, 0.86), Vector3((ROW_X1 + RAIL_X) * 0.5, 0.96, sz * (ROW_Z - 0.1)),
			granite.lightened(0.06))
	for p in PLANTERS:
		stone.box(Vector3(1.6, 0.7, 0.9), p + Vector3(0.0, 0.35, 0.0), Color(0.75, 0.42, 0.28))
		for k in 4:
			var o := Vector3(rng.randf_range(-0.55, 0.55), 0.85 + rng.randf_range(0.0, 0.3), rng.randf_range(-0.25, 0.25))
			soft.blob(Vector3(0.38, 0.32, 0.34), Transform3D(Basis(), p + o), Color(0.24, 0.52, 0.26).lerp(Color(0.36, 0.62, 0.3), rng.randf()), 8, 5)
		for k in 9:
			var o := Vector3(rng.randf_range(-0.7, 0.7), 1.05 + rng.randf_range(0.0, 0.4), rng.randf_range(-0.38, 0.38))
			var col := [Color(1.0, 0.45, 0.65), Color(0.95, 0.25, 0.3), Color(1.0, 1.0, 0.95)][k % 3] as Color
			soft.blob(Vector3(0.09, 0.08, 0.09), Transform3D(Basis(), p + o), col, 6, 4)


## The chapel closing the west end: Porto's tiled churches (Capela das Almas),
## granite frame, blue-and-white azulejos, a bell gable. Always lovely: it shows
## the kids what the street will become.
static func _chapel(stone: Kit.VBaker, wood: Kit.VBaker, tiles: Kit.VBaker, glow: Kit.VBaker,
		soft: Kit.VBaker, rng: RandomNumberGenerator) -> void:
	var x := ROW_X0
	var granite := Color(0.86, 0.84, 0.8)
	var hw := 5.5
	var h := 12.0
	# Wall body behind the facade.
	stone.box(Vector3(8.0, h, hw * 2.0), Vector3(x - 4.0, h * 0.5, 0.0), granite.darkened(0.12))
	# Pilasters, plinth, cornice.
	for sz: float in [-1.0, 1.0]:
		stone.box(Vector3(0.3, h, 0.8), Vector3(x + 0.15, h * 0.5, sz * (hw - 0.4)), granite)
	stone.box(Vector3(0.3, 0.7, hw * 2.0), Vector3(x + 0.15, 0.35, 0.0), granite.darkened(0.06))
	stone.box(Vector3(0.5, 0.5, hw * 2.0 + 0.4), Vector3(x + 0.25, h + 0.25, 0.0), granite.lightened(0.04))
	# Curved gable stepping up to a bell arch and a cross.
	for k in 5:
		var w := hw * 2.0 * (1.0 - 0.18 * float(k))
		stone.box(Vector3(0.4, 0.62, w), Vector3(x + 0.05, h + 0.8 + 0.6 * float(k), 0.0), granite)
	stone.box(Vector3(0.6, 2.2, 0.3), Vector3(x + 0.1, h + 4.5, -0.9), granite)
	stone.box(Vector3(0.6, 2.2, 0.3), Vector3(x + 0.1, h + 4.5, 0.9), granite)
	stone.box(Vector3(0.6, 0.35, 2.1), Vector3(x + 0.1, h + 5.7, 0.0), granite)
	stone.box(Vector3(0.2, 1.1, 0.16), Vector3(x + 0.1, h + 6.4, 0.0), granite.lightened(0.05))
	stone.box(Vector3(0.2, 0.16, 0.6), Vector3(x + 0.1, h + 6.6, 0.0), granite.lightened(0.05))
	wood.blob(Vector3(0.36, 0.42, 0.36), Transform3D(Basis(), Vector3(x + 0.1, h + 4.55, 0.0)), Color(0.85, 0.65, 0.25), 10, 6)
	# Door with a granite surround.
	stone.box(Vector3(0.36, 4.4, 0.4), Vector3(x + 0.18, 2.2, -1.3), granite)
	stone.box(Vector3(0.36, 4.4, 0.4), Vector3(x + 0.18, 2.2, 1.3), granite)
	stone.box(Vector3(0.44, 0.5, 3.2), Vector3(x + 0.22, 4.55, 0.0), granite.lightened(0.05))
	wood.box(Vector3(0.1, 4.0, 2.2), Vector3(x + 0.05, 2.0, 0.0), Color(0.45, 0.26, 0.16))
	for sz: float in [-0.55, 0.55]:
		for k in 3:
			wood.box(Vector3(0.05, 1.0, 0.85), Vector3(x + 0.12, 0.8 + 1.2 * float(k), sz), Color(0.52, 0.31, 0.19))
	stone.box(Vector3(0.9, 0.06, 3.6), Vector3(x + 0.45, 0.03, 0.0), granite.darkened(0.08))
	# Windows: two tall ones and a round one over the door.
	var holes: Array[Rect2] = [Rect2(-1.55, 0.0, 3.1, 4.85)]
	for sz: float in [-3.0, 3.0]:
		stone.box(Vector3(0.3, 3.0, 1.6), Vector3(x + 0.12, 7.2, sz), granite)
		glow.box(Vector3(0.1, 2.6, 1.15), Vector3(x + 0.22, 7.2, sz), Color.WHITE)
		holes.append(Rect2(sz - 0.85, 5.6, 1.7, 3.2))
	for i in 12:
		var a := TAU * float(i) / 12.0
		stone.box(Vector3(0.3, 0.42, 0.3), Vector3(x + 0.14, 7.4 + cos(a) * 0.9, sin(a) * 0.9), granite, Vector3(-a, 0.0, 0.0))
	glow.cyl(0.78, 0.1, Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(x + 0.2, 7.4, 0.0)), Color.WHITE, 14)
	holes.append(Rect2(-1.2, 6.2, 2.4, 2.4))
	# Azulejo panels over the whole wall, cut around the openings.
	_tile_wall(tiles, x + 0.012, -hw + 0.8, hw - 0.8, 0.7, h, holes)
	# Side walls between the chapel and the house rows, with bougainvillea spilling over.
	for sz: float in [-1.0, 1.0]:
		var zc: float = sz * (hw + (ROW_Z - hw) * 0.5)
		var zw := ROW_Z - hw
		stone.box(Vector3(1.2, 6.0, zw), Vector3(x - 0.6, 3.0, zc), Color(0.74, 0.7, 0.64))
		stone.box(Vector3(1.4, 0.3, zw + 0.2), Vector3(x - 0.5, 6.1, zc), granite)
		# A dark archway suggesting the street goes on.
		stone.box(Vector3(0.1, 3.2, 2.0), Vector3(x + 0.02, 1.6, zc), Color(0.18, 0.17, 0.2))
		stone.box(Vector3(0.3, 0.4, 2.6), Vector3(x + 0.1, 3.4, zc), granite)
		# Leaves along the wall top, blossom spilling down the face.
		var zz := zc - zw * 0.45
		while zz < zc + zw * 0.45:
			soft.blob(Vector3(0.45, 0.32, 0.5), Transform3D(Basis(), Vector3(x - 0.3, 6.35, zz)),
				Color(0.26, 0.5, 0.26).lerp(Color(0.34, 0.58, 0.3), rng.randf()), 7, 5)
			var drop := rng.randf_range(0.4, 2.2)
			var yy := 6.2
			while yy > 6.2 - drop:
				soft.blob(Vector3(0.16, 0.22, 0.26), Transform3D(Basis(), Vector3(x + 0.06, yy, zz + rng.randf_range(-0.2, 0.2))),
					Color(0.92, 0.3, 0.62).darkened(rng.randf() * 0.18), 6, 4)
				yy -= 0.3
			zz += rng.randf_range(0.5, 0.8)


static func _tile_wall(tiles: Kit.VBaker, x: float, z0: float, z1: float, y0: float, y1: float,
		holes: Array[Rect2]) -> void:
	# Holes are Rect2(z, y, dz, dy). Same grid cut as the houses.
	var zs: Array[float] = [z0, z1]
	var ys: Array[float] = [y0, y1]
	for r in holes:
		for v: float in [r.position.x, r.position.x + r.size.x]:
			if v > z0 and v < z1:
				zs.append(v)
		for v: float in [r.position.y, r.position.y + r.size.y]:
			if v > y0 and v < y1:
				ys.append(v)
	zs.sort()
	ys.sort()
	for i in zs.size() - 1:
		for j in ys.size() - 1:
			var c := Vector2((zs[i] + zs[i + 1]) * 0.5, (ys[j] + ys[j + 1]) * 0.5)
			var inside := false
			for r in holes:
				if r.has_point(c):
					inside = true
					break
			if inside or zs[i + 1] - zs[i] < 0.02 or ys[j + 1] - ys[j] < 0.02:
				continue
			# Facing +X: wind so the right-hand normal points +X.
			tiles.quad(Vector3(x, ys[j], zs[i + 1]), Vector3(x, ys[j], zs[i]), Vector3(x, ys[j + 1], zs[i]),
				Vector3(x, ys[j + 1], zs[i + 1]), Color.WHITE)


## Small things that make a street lived in: drain grates, a manhole cover, a
## sleeping cat on the chapel bench, pigeons by the fountain.
static func _details(iron: Kit.VBaker, soft: Kit.VBaker, wood: Kit.VBaker, rng: RandomNumberGenerator) -> void:
	iron.cyl(0.45, 0.03, Transform3D(Basis(), Vector3(4.5, 0.015, 3.5)), Color(0.24, 0.24, 0.26), 14)
	for p: Vector3 in [Vector3(-10.0, 0.0, -12.2), Vector3(2.0, 0.0, 12.2), Vector3(-15.0, 0.0, 12.2)]:
		iron.box(Vector3(0.6, 0.03, 0.35), p + Vector3(0.0, 0.015, 0.0), Color(0.2, 0.2, 0.22))
	# The cat: ginger, curled up, asleep.
	var cat := BENCHES[2] + Vector3(0.0, 0.52, 0.55)
	soft.blob(Vector3(0.28, 0.16, 0.2), Transform3D(Basis(), cat + Vector3(0.0, 0.12, 0.0)), Color(0.95, 0.6, 0.3), 10, 6)
	soft.blob(Vector3(0.14, 0.12, 0.13), Transform3D(Basis(), cat + Vector3(0.22, 0.16, 0.06)), Color(0.95, 0.62, 0.32), 8, 5)
	for sz: float in [-1.0, 1.0]:
		soft.blob(Vector3(0.04, 0.06, 0.03), Transform3D(Basis(), cat + Vector3(0.27, 0.27, 0.06 + sz * 0.07)), Color(0.9, 0.55, 0.28), 6, 4)
	soft.blob(Vector3(0.2, 0.05, 0.05), Transform3D(Basis(Vector3.UP, 0.6), cat + Vector3(-0.12, 0.06, 0.18)), Color(0.85, 0.5, 0.25), 6, 4)
	# Pigeons pecking near the fountain.
	for k in 4:
		var a := 0.6 + float(k) * 0.5
		var p := FOUNTAIN + Vector3(cos(a) * 4.6, 0.0, sin(a) * 4.6)
		var b := Basis(Vector3.UP, rng.randf() * TAU)
		soft.blob(Vector3(0.12, 0.1, 0.16), Transform3D(b, p + Vector3(0.0, 0.14, 0.0)), Color(0.62, 0.64, 0.7), 8, 5)
		soft.blob(Vector3(0.06, 0.06, 0.06), Transform3D(b, p + b * Vector3(0.0, 0.25, 0.12)), Color(0.5, 0.52, 0.6), 6, 4)
		wood.box_xf(Vector3(0.03, 0.02, 0.05), Transform3D(b, p + b * Vector3(0.0, 0.24, 0.19)), Color(0.95, 0.65, 0.3))


# --- Backdrop: the Douro, the Dom Luís I arch, the far bank -------------------------

static func _backdrop(level: Node3D, rng: RandomNumberGenerator) -> void:
	var walls := Kit.VBaker.new()
	var roofs := Kit.VBaker.new()
	var bridge := Kit.VBaker.new()
	# The river: wide, below the terrace, running north-south across the view.
	var river := MeshInstance3D.new()
	river.name = "Douro"
	var plane := PlaneMesh.new()
	plane.size = Vector2(260.0, 900.0)
	river.mesh = plane
	river.position = Vector3(RAIL_X + 130.0, RIVER_Y, 0.0)
	river.material_override = ToonFactory.water(Color(0.16, 0.38, 0.46), 1.0)
	river.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	level.add_child(river)

	# The far bank (Gaia): a green hill rising from a quay, with the port lodges'
	# long roofs along the water and houses climbing behind.
	var bank_x := RAIL_X + 120.0
	# Quay wall, then one long green slope with the town climbing it.
	walls.box(Vector3(10.0, 3.0, 700.0), Vector3(bank_x + 2.0, RIVER_Y + 1.5, 0.0), Color(0.62, 0.6, 0.56))
	var slope := 0.42
	var run := 150.0
	var tilt := atan(slope)
	var mid := Vector3(bank_x + 6.0 + run * 0.5, RIVER_Y + 3.0 + run * 0.5 * slope - 0.6, 0.0)
	walls.box(Vector3(run / cos(tilt), 1.2, 700.0), mid, Color(0.44, 0.56, 0.32), Vector3(0.0, 0.0, tilt))
	var palette := [Color(0.97, 0.9, 0.78), Color(0.96, 0.74, 0.58), Color(0.86, 0.84, 0.78), Color(0.99, 0.86, 0.55),
		Color(0.8, 0.86, 0.94), Color(0.95, 0.62, 0.55)]
	for row in 7:
		var x := bank_x + 9.0 + 15.0 * float(row)
		var z := -180.0 + rng.randf_range(0.0, 8.0)
		while z < 180.0:
			var s := Vector3(rng.randf_range(6.0, 8.0), rng.randf_range(5.0, 10.0), rng.randf_range(6.0, 11.0))
			if row == 0:
				s = Vector3(11.0, 6.0, rng.randf_range(22.0, 36.0))
			var gy := RIVER_Y + 3.0 + (x - bank_x - 6.0) * slope
			var col: Color = palette[rng.randi_range(0, palette.size() - 1)]
			if row == 0:
				col = Color(0.93, 0.9, 0.84)
			walls.box(s, Vector3(x, gy + s.y * 0.5 - 1.0, z), col)
			walls.box(Vector3(0.2, 1.1, s.z * 0.7), Vector3(x - s.x * 0.5 - 0.05, gy + s.y * 0.62 - 1.0, z), Color(0.25, 0.25, 0.3))
			roofs.prism(s.z + 0.6, 2.4, s.x + 0.8, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(x, gy + s.y - 1.0, z)),
				Color(0.82, 0.4, 0.27).darkened(rng.randf() * 0.18))
			if rng.randf() < 0.35:
				walls.blob(Vector3(4.0, 3.5, 4.0), Transform3D(Basis(), Vector3(x + 7.0, gy + 3.0, z + s.z * 0.5 + 2.5)),
					Color(0.24, 0.44, 0.24), 8, 5)
			z += s.z + rng.randf_range(1.0, 6.0)
	# Serra do Pilar: the round monastery church on the hill by the bridge.
	var sp := Vector3(bank_x + 40.0, RIVER_Y + 3.0 + 34.0 * slope + 1.0, -62.0)
	walls.cyl(9.0, 12.0, Transform3D(Basis(), sp + Vector3(0.0, 6.0, 0.0)), Color(0.92, 0.9, 0.84), 18)
	walls.blob(Vector3(7.5, 6.0, 7.5), Transform3D(Basis(), sp + Vector3(0.0, 12.5, 0.0)), Color(0.82, 0.8, 0.75), 16, 8)
	walls.box(Vector3(26.0, 8.0, 14.0), sp + Vector3(16.0, 4.0, 10.0), Color(0.9, 0.87, 0.8))
	roofs.prism(26.0, 3.0, 14.6, Transform3D(Basis(), sp + Vector3(16.0, 8.0, 10.0)), Color(0.76, 0.42, 0.3))
	# The near bank north of the square, glimpsed past the terrace.
	for k in 18:
		var z := -40.0 - rng.randf_range(0.0, 140.0)
		var x := RAIL_X + rng.randf_range(-6.0, 14.0)
		var s := Vector3(rng.randf_range(5.0, 8.0), rng.randf_range(10.0, 18.0), rng.randf_range(5.0, 8.0))
		var col := [Color(0.95, 0.72, 0.5), Color(0.98, 0.88, 0.6), Color(0.72, 0.82, 0.92), Color(0.95, 0.6, 0.55)][k % 4] as Color
		walls.box(s, Vector3(x, RIVER_Y + s.y * 0.5, z), col)
		roofs.prism(s.x + 0.4, 2.0, s.z + 0.4, Transform3D(Basis(), Vector3(x, RIVER_Y + s.y, z)), Color(0.78, 0.4, 0.28))
	_bridge(bridge)
	_rabelos(walls, roofs)

	level.add_child(walls.bake(Kit.vc("plaster"), "FarBank", false))
	level.add_child(roofs.bake(Kit.vc("roof"), "FarRoofs", false))
	level.add_child(bridge.bake(Kit.vc("iron"), "DomLuisBridge", false))


## The Dom Luís I: one great iron arch springing from granite pylons, the upper
## deck resting on its crown, the lower deck hung beneath. Seen across the
## water at an angle, so it reads as the arch.
static func _bridge(b: Kit.VBaker) -> void:
	var z := -78.0
	var x0 := RAIL_X + 22.0
	var x1 := RAIL_X + 120.0
	var span := x1 - x0
	var base := RIVER_Y + 1.0
	var crown := RIVER_Y + 44.0
	var deck := crown + 1.2
	var iron := Color(0.22, 0.21, 0.24)
	var granite := Color(0.66, 0.62, 0.57)
	var n := 22
	for side: float in [-2.6, 2.6]:
		var prev_top := Vector3.ZERO
		var prev_bot := Vector3.ZERO
		for i in n + 1:
			var t := float(i) / float(n)
			var x := x0 + span * t
			var u := 2.0 * t - 1.0
			var top_y := base + (crown - base) * (1.0 - u * u)
			var depth := lerpf(2.2, 6.5, u * u)
			var top := Vector3(x, top_y, z + side)
			var bot := Vector3(x, top_y - depth, z + side)
			if i > 0:
				b.beam(prev_top, top, 1.0, iron)
				b.beam(prev_bot, bot, 1.0, iron)
				b.beam(prev_top, bot, 0.45, iron)
			b.beam(top, bot, 0.5, iron)
			prev_top = top
			prev_bot = bot
	# Cross bracing between the two arch planes at a few panels.
	for i in range(2, n - 1, 4):
		var t := float(i) / float(n)
		var u := 2.0 * t - 1.0
		var y := base + (crown - base) * (1.0 - u * u)
		b.beam(Vector3(x0 + span * t, y, z - 2.6), Vector3(x0 + span * t, y, z + 2.6), 0.5, iron)
	# Upper deck, on the crown and on iron piers out to each bank.
	b.box(Vector3(span + 70.0, 1.6, 8.0), Vector3((x0 + x1) * 0.5, deck + 0.8, z), iron.darkened(0.1))
	b.box(Vector3(span + 70.0, 0.9, 8.4), Vector3((x0 + x1) * 0.5, deck + 2.0, z), iron.lightened(0.1))
	for x: float in [x0 - 30.0, x0 - 15.0, x0 + 10.0, x0 + 22.0, x1 - 22.0, x1 - 10.0, x1 + 15.0, x1 + 30.0]:
		var u := (float(x) - (x0 + x1) * 0.5) / (span * 0.5)
		var arch_y := base + (crown - base) * (1.0 - u * u) if absf(u) <= 1.0 else base
		var foot := arch_y if absf(u) <= 1.0 else RIVER_Y
		var h := deck - foot
		if h > 1.0:
			for sz: float in [-2.6, 2.6]:
				b.box(Vector3(0.8, h, 0.8), Vector3(x, foot + h * 0.5, z + sz), iron)
	# Granite pylons at the springings.
	for x: float in [x0, x1]:
		b.box(Vector3(7.0, deck - RIVER_Y + 3.0, 10.0), Vector3(x, (deck + RIVER_Y + 3.0) * 0.5, z), granite)
		b.box(Vector3(7.6, 1.2, 10.6), Vector3(x, deck + 2.2, z), granite.lightened(0.05))
	# The lower deck, hung from the arch.
	var low := RIVER_Y + 10.0
	b.box(Vector3(span, 1.2, 8.0), Vector3((x0 + x1) * 0.5, low, z), iron.darkened(0.1))
	for i in range(1, n):
		var t := float(i) / float(n)
		var u := 2.0 * t - 1.0
		var y := base + (crown - base) * (1.0 - u * u) - lerpf(2.2, 6.5, u * u)
		if y > low + 0.6:
			for sz: float in [-2.6, 2.6]:
				b.beam(Vector3(x0 + span * t, low, z + sz), Vector3(x0 + span * t, y, z + sz), 0.25, iron)


## Rabelo boats moored on the river, barrels on deck.
static func _rabelos(walls: Kit.VBaker, roofs: Kit.VBaker) -> void:
	var spots := [Vector3(RAIL_X + 16.0, RIVER_Y, -18.0), Vector3(RAIL_X + 15.0, RIVER_Y, 6.0),
		Vector3(RAIL_X + 17.0, RIVER_Y, 26.0)]
	for p: Vector3 in spots:
		walls.box(Vector3(3.0, 1.0, 12.0), p + Vector3(0.0, 0.3, 0.0), Color(0.36, 0.24, 0.16))
		walls.box(Vector3(2.4, 0.4, 2.0), p + Vector3(0.0, 1.0, 5.6), Color(0.4, 0.27, 0.18), Vector3(0.4, 0.0, 0.0))
		walls.box(Vector3(0.18, 6.5, 0.18), p + Vector3(0.0, 4.0, -1.0), Color(0.36, 0.24, 0.16))
		walls.box(Vector3(0.1, 4.0, 3.4), p + Vector3(0.0, 4.6, -1.0), Color(0.96, 0.94, 0.88))
		for k in 4:
			roofs.cyl(0.45, 0.9, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), p + Vector3(-0.6 + 0.4 * float(k % 2) * 3.0, 1.25, -3.2 + 1.2 * float(k))),
				Color(0.55, 0.3, 0.2), 8)


# --- Colliders ----------------------------------------------------------------------

static func _colliders(level: Node3D) -> void:
	# Ground.
	SceneryKit.solid(level, "GroundCollider", Vector3(48.0, 1.0, 36.0), Vector3(0.0, -0.5, 0.0))
	# Facade rows, the chapel end and the fences above the low terrace walls are
	# tall, so they live on BLOCKERS: heroes collide with them, the camera does not.
	var row_len := ROW_X1 - ROW_X0 + 1.0
	barrier(level, "NorthRow", Vector3(row_len, 9.0, 2.5), Vector3((ROW_X0 + ROW_X1) * 0.5, 4.5, -ROW_Z - 1.25))
	barrier(level, "SouthRow", Vector3(row_len, 9.0, 2.5), Vector3((ROW_X0 + ROW_X1) * 0.5, 4.5, ROW_Z + 1.25))
	barrier(level, "ChapelEnd", Vector3(2.5, 9.0, ROW_Z * 2.0 + 2.0), Vector3(ROW_X0 - 1.25, 4.5, 0.0))
	var tw := RAIL_X - ROW_X1 + 1.0
	for sz: float in [-1.0, 1.0]:
		SceneryKit.solid(level, "TerraceWall", Vector3(tw, 1.0, 0.8), Vector3((ROW_X1 + RAIL_X) * 0.5, 0.5, sz * (ROW_Z - 0.1)))
		barrier(level, "TerraceFence", Vector3(tw, 7.0, 0.6), Vector3((ROW_X1 + RAIL_X) * 0.5, 3.5, sz * (ROW_Z + 0.2)))
	SceneryKit.solid(level, "Balustrade", Vector3(0.7, 1.1, ROW_Z * 2.0), Vector3(RAIL_X + 0.25, 0.55, 0.0))
	barrier(level, "RiverFence", Vector3(0.6, 7.0, ROW_Z * 2.0), Vector3(RAIL_X + 0.6, 3.5, 0.0))
	# Fountain: the rim is low (WORLD, you can hop up on it); the column is tall.
	var fb := StaticBody3D.new()
	fb.name = "FountainRim"
	fb.collision_layer = PhysicsLayers.WORLD
	fb.collision_mask = 0
	_cyl_shape(fb, FOUNTAIN_R + 0.15, 0.86, FOUNTAIN + Vector3(0.0, 0.43, 0.0))
	level.add_child(fb)
	var col := StaticBody3D.new()
	col.name = "FountainColumn"
	col.collision_layer = PhysicsLayers.BLOCKERS
	col.collision_mask = 0
	_cyl_shape(col, 0.75, 3.2, FOUNTAIN + Vector3(0.0, 1.6, 0.0))
	level.add_child(col)
	for i in BENCHES.size():
		var bb := StaticBody3D.new()
		bb.name = "Bench%d" % i
		bb.collision_layer = PhysicsLayers.WORLD
		bb.collision_mask = 0
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(2.1, 0.52, 0.7)
		cs.shape = box
		cs.position = BENCHES[i] + Vector3(0.0, 0.26, 0.0)
		cs.rotation.y = BENCH_YAWS[i]
		bb.add_child(cs)
		level.add_child(bb)
	for i in LAMPS.size():
		var lb := StaticBody3D.new()
		lb.name = "Lamp%d" % i
		lb.collision_layer = PhysicsLayers.BLOCKERS
		lb.collision_mask = 0
		_cyl_shape(lb, 0.26, 4.0, LAMPS[i] + Vector3(0.0, 2.0, 0.0))
		level.add_child(lb)
	for p in PLANTERS:
		SceneryKit.solid(level, "Planter", Vector3(1.6, 0.9, 0.9), p + Vector3(0.0, 0.45, 0.0))


## A tall static box on BLOCKERS: heroes (whose mask includes BLOCKERS) bump into it; the
## camera's spring arm (mask WORLD) passes through it.
static func barrier(parent: Node3D, n: String, size: Vector3, pos: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = n
	body.collision_layer = PhysicsLayers.BLOCKERS
	body.collision_mask = 0
	parent.add_child(body)
	SceneryKit.solid_shape(body, size, pos)
	return body


static func _cyl_shape(body: StaticBody3D, r: float, h: float, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = r
	cyl.height = h
	cs.shape = cyl
	cs.position = pos
	body.add_child(cs)
