extends RefCounted
## Builds the Estádio do Dragão ONCE, at night: the striped pitch, the LED
## boards, four blue stands with a roof ring, floodlight towers, goals with
## nets, corner flags, dugouts and the players' tunnel, plus the colliders.
##
## Everything static is welded by vc_baker.gd into one surface per material, so
## the whole stadium is about ten draw calls. Only the low, near things (boards,
## goals, flags, dugouts) cast shadows: the stands and roof stand outside the
## play area and a roof shadow across the pitch would darken exactly what the
## children must see.
##
## Colliders follow the camera rule: WORLD only for low things (the ground, a
## 1 m ball wall along the boards, the goal frames), because the camera's
## spring arm sweeps WORLD. The tall wall that stops a hero jumping out over the
## boards is on BOSS, which heroes collide with and the spring arm ignores. No
## club crest, sponsor or lettering anywhere: colours only.

const VC := preload("res://scripts/levels/dragao/vc_baker.gd")
const M := preload("res://scripts/levels/dragao/dragao_mats.gd")
const L := preload("res://scripts/levels/dragao/dragao_layout.gd")

const BLUE := Color(0.06, 0.29, 0.84)
const BLUE_DEEP := Color(0.04, 0.16, 0.5)
const SKY_BLUE := Color(0.32, 0.6, 1.0)
const WHITE := Color(0.84, 0.87, 0.92)
const CONCRETE := Color(0.6, 0.63, 0.7)
const STEEL := Color(0.3, 0.33, 0.4)
const LAMP := Color(1.0, 0.97, 0.88)
const WARM := Color(1.0, 0.82, 0.5)

const SEAT_PITCH := 0.9
const AISLE_EVERY := 10.0
const FENCE_H := 7.0
const BALL_WALL_H := 1.0


static func build(root: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xD7A6A0
	var far := VC.new()      # stands, roof, towers: no shadows
	var near := VC.new()     # boards, goals, flags, dugouts: cast shadows
	var seats := VC.new()
	var lights := VC.new()
	var leds := VC.new()
	var nets := VC.new()
	var glass := VC.new()

	_pitch(root)
	_boards(near, leds)
	_stands(far, seats, lights, rng)
	_corners(far, lights)
	_roof(far, lights)
	_towers(far, lights, root)
	_goals(near, nets)
	_flags(near)
	_dugouts(near, seats, glass)
	_tunnel(near, lights)

	root.add_child(far.commit(M.structure_far(), "Stands"))
	root.add_child(seats.commit(M.gloss(), "Seats"))
	root.add_child(near.commit(M.structure(), "PitchSide", true))
	root.add_child(lights.commit(M.lit(1.0), "Lamps"))
	root.add_child(leds.commit(M.led(), "LedBoards"))
	root.add_child(nets.commit(M.net(), "Nets"))
	root.add_child(glass.commit(M.glass(), "Glass"))
	_colliders(root)


# --- Pitch ---------------------------------------------------------------------

static func _pitch(root: Node3D) -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(L.stand_front_x() * 2.0 + 1.0, L.stand_front_z() * 2.0 + 1.0)
	var mi := MeshInstance3D.new()
	mi.name = "Pitch"
	mi.mesh = pm
	mi.material_override = M.pitch()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


# --- Boards ----------------------------------------------------------------------

## [from, to, inward normal] for every straight run of board; the -Z side has
## gaps at the trophy cabinet and the tunnel.
static func _board_runs() -> Array:
	var x := L.BOARD_X
	var z := L.BOARD_Z
	var cab_lo := L.CABINET_POS.x - L.CABINET_W * 0.5 - 0.3
	var cab_hi := L.CABINET_POS.x + L.CABINET_W * 0.5 + 0.3
	var tun := L.TUNNEL_HALF_W + 0.4
	return [
		[Vector3(-x, 0, -z), Vector3(cab_lo, 0, -z), Vector3.BACK],
		[Vector3(cab_hi, 0, -z), Vector3(-tun, 0, -z), Vector3.BACK],
		[Vector3(tun, 0, -z), Vector3(x, 0, -z), Vector3.BACK],
		[Vector3(x, 0, -z), Vector3(x, 0, z), Vector3.LEFT],
		[Vector3(x, 0, z), Vector3(-x, 0, z), Vector3.FORWARD],
		[Vector3(-x, 0, z), Vector3(-x, 0, -z), Vector3.RIGHT],
	]


static func _boards(near: VC, leds: VC) -> void:
	var s := 0.0
	for run in _board_runs():
		var a: Vector3 = run[0]
		var b: Vector3 = run[1]
		var n: Vector3 = run[2]
		var len := a.distance_to(b)
		var along := (b - a) / len
		var mid := (a + b) * 0.5 - n * L.BOARD_T * 0.5
		var basis := Basis(along, Vector3.UP, along.cross(Vector3.UP))
		near.box(Vector3(len, L.BOARD_H, L.BOARD_T), Transform3D(basis, mid + Vector3.UP * L.BOARD_H * 0.5), BLUE_DEEP)
		# A white cap rail, so the boards read as a clean line from far away.
		near.box(Vector3(len, 0.06, L.BOARD_T + 0.04), Transform3D(basis, mid + Vector3.UP * (L.BOARD_H + 0.03)), WHITE)
		var f := n * 0.012
		var y0 := Vector3.UP * 0.1
		var y1 := Vector3.UP * (L.BOARD_H - 0.06)
		leds.quad(a + f + y0, b + f + y0, b + f + y1, a + f + y1, n, Color.WHITE,
			Vector2(s, 0.0), Vector2(s + len, 1.0))
		s += len
	# A dark concrete walkway between the boards and the stands.
	var fz := L.stand_front_z()
	var fx := L.stand_front_x()
	var walk := Color(0.24, 0.27, 0.32)
	near.block(Vector3(-fx, -0.05, -fz), Vector3(fx, 0.015, -L.BOARD_Z - L.BOARD_T), walk)
	near.block(Vector3(-fx, -0.05, L.BOARD_Z + L.BOARD_T), Vector3(fx, 0.015, fz), walk)
	near.block(Vector3(-fx, -0.05, -L.BOARD_Z), Vector3(-L.BOARD_X - L.BOARD_T, 0.015, L.BOARD_Z), walk)
	near.block(Vector3(L.BOARD_X + L.BOARD_T, -0.05, -L.BOARD_Z), Vector3(fx, 0.015, L.BOARD_Z), walk)


# --- Stands ----------------------------------------------------------------------

## [origin at the stand's front-centre, along, out (away from the pitch), length]
static func _stand_frames() -> Array:
	var fz := L.stand_front_z()
	var fx := L.stand_front_x()
	return [
		[Vector3(0, 0, -fz), Vector3.RIGHT, Vector3.FORWARD, fx * 2.0, true],
		[Vector3(0, 0, fz), Vector3.LEFT, Vector3.BACK, fx * 2.0, false],
		[Vector3(fx, 0, 0), Vector3.BACK, Vector3.RIGHT, fz * 2.0, false],
		[Vector3(-fx, 0, 0), Vector3.FORWARD, Vector3.LEFT, fz * 2.0, false],
	]


static func _stands(far: VC, seats: VC, lights: VC, rng: RandomNumberGenerator) -> void:
	for fr in _stand_frames():
		var o: Vector3 = fr[0]
		var al: Vector3 = fr[1]
		var out: Vector3 = fr[2]
		var length: float = fr[3]
		var main: bool = fr[4]
		var basis := Basis(al, Vector3.UP, al.cross(Vector3.UP))
		var half := length * 0.5
		# Front wall: white with a blue coping.
		far.box(Vector3(length, L.FRONT_WALL_H, 0.3),
			Transform3D(basis, o + out * 0.15 + Vector3.UP * L.FRONT_WALL_H * 0.5), WHITE)
		far.box(Vector3(length, 0.12, 0.36),
			Transform3D(basis, o + out * 0.15 + Vector3.UP * (L.FRONT_WALL_H + 0.06)), BLUE)
		for i in L.TIERS:
			var d0 := 0.3 + float(i) * L.TIER_D
			var top := L.FRONT_WALL_H + float(i) * L.TIER_H
			var tone := CONCRETE * (0.94 if i % 2 == 0 else 1.0)
			tone.a = 1.0
			far.box(Vector3(length, L.TIER_H + 0.5, L.TIER_D),
				Transform3D(basis, o + out * (d0 + L.TIER_D * 0.5) + Vector3.UP * (top - (L.TIER_H + 0.5) * 0.5)), tone)
			# Seat row with aisles of steps every AISLE_EVERY metres.
			var x := -half + 0.6
			while x < half - 0.6:
				var to_aisle := fposmod(x + half, AISLE_EVERY)
				var p := o + al * x + out * (d0 + L.TIER_D * 0.62) + Vector3.UP * (top + 0.2)
				if to_aisle < 1.1:
					far.box(Vector3(1.0, 0.2, L.TIER_D * 0.5),
						Transform3D(basis, o + al * (x + 0.5) + out * (d0 + L.TIER_D * 0.25) + Vector3.UP * (top + 0.1)),
						CONCRETE * 1.08)
					x += 1.1
					continue
				seats.box(Vector3(SEAT_PITCH - 0.14, 0.4, 0.4), Transform3D(basis, p),
					_seat_colour(i, x, main, rng))
				x += SEAT_PITCH
		# Back wall up to the roof, deep blue.
		var depth := 0.3 + float(L.TIERS) * L.TIER_D
		var wall_h := L.ROOF_Y
		far.box(Vector3(length, wall_h, 0.5),
			Transform3D(basis, o + out * (depth + 0.25) + Vector3.UP * wall_h * 0.5), Color(0.13, 0.2, 0.42))
		var top_y := L.FRONT_WALL_H + float(L.TIERS - 1) * L.TIER_H
		# White structural ribs up the back wall, every few metres.
		var n_rib := int(length / 5.5)
		for k in n_rib + 1:
			var rx := -half + length * float(k) / float(n_rib)
			far.box(Vector3(0.35, wall_h - top_y, 0.12),
				Transform3D(basis, o + al * rx + out * (depth - 0.03) + Vector3.UP * (top_y + (wall_h - top_y) * 0.5)),
				Color(0.75, 0.78, 0.85))
		if main:
			# The executive boxes along the back of the main stand: a glass band
			# with warm lit panes (in one of them the president watched the
			# goblins, page d06), framed in white.
			var band_y := top_y + 2.2
			far.box(Vector3(length - 6.0, 1.7, 0.1), Transform3D(basis, o + out * (depth - 0.05) + Vector3.UP * band_y),
				Color(0.85, 0.88, 0.95))
			var n_win := 40
			var pane := (length - 6.4) / float(n_win)
			for k in n_win:
				var wx := -half + 3.2 + pane * (float(k) + 0.5)
				var lit := (k % 5 != 2 and k % 7 != 4) or k == n_win / 2
				var c := Color(0.85, 0.7, 0.42) if lit else Color(0.12, 0.17, 0.32)
				if k == n_win / 2:
					c = Color(1.0, 0.9, 0.62)
				var into: VC = lights if lit else far
				into.box(Vector3(pane - 0.12, 1.35, 0.05),
					Transform3D(basis, o + al * wx + out * (depth - 0.12) + Vector3.UP * band_y), c)


## Mostly club blue, a white ring two rows high round the whole bowl, lighter
## blue at the top, and a few seeded off-shade seats so no row is one flat run.
static func _seat_colour(row: int, x: float, main: bool, rng: RandomNumberGenerator) -> Color:
	var j := rng.randf_range(-0.06, 0.06)
	if row == 5 or row == 6:
		return Color(0.92 + j * 0.5, 0.94 + j * 0.5, 0.98)
	if row >= L.TIERS - 3:
		return Color(0.18 + j, 0.45 + j, 0.95)
	# The main stand gets a white "wave" across its middle rows.
	if main and row > 7 and absf(sin(x * 0.12) * 3.0 + 10.0 - float(row)) < 0.6:
		return Color(0.92, 0.94, 0.98)
	return Color(BLUE.r + j * 0.6, BLUE.g + j, BLUE.b + j * 0.5)


## Low concrete closing walls across the four corners, the (+X,-Z) one with the
## dark mouth of the gate the goblins' van came through.
static func _corners(far: VC, lights: VC) -> void:
	var fx := L.stand_front_x()
	var fz := L.stand_front_z()
	var depth := 0.3 + float(L.TIERS) * L.TIER_D
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var a := Vector3(sx * fx, 0, sz * (fz + depth))
			var b := Vector3(sx * (fx + depth), 0, sz * fz)
			var mid := (a + b) * 0.5
			var al := (b - a).normalized()
			var basis := Basis(al, Vector3.UP, al.cross(Vector3.UP))
			var len := a.distance_to(b)
			far.box(Vector3(len, 6.0, 0.6), Transform3D(basis, mid + Vector3.UP * 3.0), Color(0.5, 0.54, 0.62))
			far.box(Vector3(len, 0.3, 0.7), Transform3D(basis, mid + Vector3.UP * 6.1), BLUE)
			if sx > 0.0 and sz < 0.0:
				# The open gate: a dark tunnel mouth with a warm lamp over it.
				var inward := -basis.z if basis.z.dot(-mid) < 0.0 else basis.z
				far.box(Vector3(4.2, 3.4, 0.2), Transform3D(basis, mid + inward * 0.32 + Vector3.UP * 1.7),
					Color(0.04, 0.05, 0.08))
				lights.box(Vector3(1.2, 0.25, 0.2), Transform3D(basis, mid + inward * 0.4 + Vector3.UP * 3.75), WARM)


# --- Roof ring ---------------------------------------------------------------------

static func _roof(far: VC, lights: VC) -> void:
	var depth := 0.3 + float(L.TIERS) * L.TIER_D
	for fr in _stand_frames():
		var o: Vector3 = fr[0]
		var al: Vector3 = fr[1]
		var out: Vector3 = fr[2]
		var length: float = fr[3]
		var basis := Basis(al, Vector3.UP, al.cross(Vector3.UP))
		var inner := 1.2
		var span := depth + 0.8 + inner
		var c := o + out * (depth + 0.8 - span * 0.5) + Vector3.UP * (L.ROOF_Y + 0.25)
		far.box(Vector3(length + 4.0, 0.5, span), Transform3D(basis, c), Color(0.86, 0.89, 0.94))
		# Blue fascia and the floodlight strip under the roof's inner edge.
		var edge := o - out * inner + Vector3.UP * (L.ROOF_Y + 0.1)
		far.box(Vector3(length + 4.0, 0.9, 0.18), Transform3D(basis, edge), BLUE)
		lights.box(Vector3(length + 2.0, 0.14, 0.4), Transform3D(basis, edge + out * 0.35 + Vector3.DOWN * 0.48), LAMP)
		# Roof trusses: posts on the back wall and a raking top chord.
		var n_truss := int(length / 11.0)
		for k in n_truss + 1:
			var tx := -length * 0.5 + length * float(k) / float(n_truss)
			var back := o + al * tx + out * (depth + 0.9)
			_beam(far, back + Vector3.UP * L.ROOF_Y, back + Vector3.UP * (L.ROOF_Y + 3.2), 0.35, STEEL)
			_beam(far, back + Vector3.UP * (L.ROOF_Y + 3.2), o + al * tx - out * inner + Vector3.UP * (L.ROOF_Y + 0.5), 0.28, STEEL)


# --- Floodlight towers ---------------------------------------------------------------

static func _towers(far: VC, lights: VC, root: Node3D) -> void:
	var halo := M.halo(Color(1.0, 0.94, 0.78, 0.5))
	var quad := QuadMesh.new()
	quad.size = Vector2(15.0, 15.0)
	var i := 0
	for base in L.TOWERS:
		var top := base + Vector3.UP * L.TOWER_H
		var spread := [Vector3(-1.3, 0, -1.3), Vector3(1.3, 0, -1.3), Vector3(1.3, 0, 1.3), Vector3(-1.3, 0, 1.3)]
		for k in 4:
			var b0: Vector3 = base + spread[k]
			var t0: Vector3 = top + spread[k] * 0.4
			_beam(far, b0, t0, 0.28, STEEL)
			var b1: Vector3 = base + spread[(k + 1) % 4]
			var t1: Vector3 = top + spread[(k + 1) % 4] * 0.4
			# Zig-zag bracing up each face.
			for s in 6:
				var f0 := float(s) / 6.0
				var f1 := float(s + 1) / 6.0
				_beam(far, b0.lerp(t0, f0), b1.lerp(t1, f1), 0.12, STEEL)
		# The head: a lamp bank facing the centre spot, tilted down.
		var to_centre := (-base).normalized()
		to_centre.y = 0.0
		var yaw := atan2(to_centre.x, to_centre.z)
		var head_basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, deg_to_rad(28.0))
		var head_pos := top + Vector3.UP * 2.2
		far.box(Vector3(7.6, 4.2, 0.5), Transform3D(head_basis, head_pos), Color(0.22, 0.24, 0.3))
		for r in 3:
			for cidx in 6:
				var lp := Vector3(-3.0 + 1.2 * float(cidx), -1.3 + 1.3 * float(r), 0.3)
				lights.box(Vector3(1.0, 1.05, 0.12), Transform3D(head_basis, head_pos + head_basis * lp), LAMP)
		var h := MeshInstance3D.new()
		h.name = "Glare%d" % i
		h.mesh = quad
		h.material_override = halo
		h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		h.position = head_pos + head_basis * Vector3(0, 0, 1.2)
		root.add_child(h)
		i += 1


# --- Goals, flags, dugouts, tunnel ------------------------------------------------------

static func _goals(near: VC, nets: VC) -> void:
	var gw := 3.6
	var gh := 2.4
	var depth := 1.9
	var r := 0.075
	for sx in [-1.0, 1.0]:
		var gx: float = sx * L.PITCH_HALF.x
		for sz in [-1.0, 1.0]:
			near.cylinder(r, r, gh, Transform3D(Basis(), Vector3(gx, gh * 0.5, sz * gw)), WHITE, 10)
			# Back stanchions.
			_beam(near, Vector3(gx, gh, sz * gw), Vector3(gx + sx * 1.2, gh - 0.1, sz * gw), 0.05, WHITE)
			_beam(near, Vector3(gx + sx * 1.2, gh - 0.1, sz * gw), Vector3(gx + sx * depth, 0.02, sz * gw), 0.05, WHITE)
			_beam(near, Vector3(gx, 0.03, sz * gw), Vector3(gx + sx * depth, 0.03, sz * gw), 0.05, WHITE)
		near.cylinder(r, r, gw * 2.0 + r * 2.0, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(gx, gh, 0)), WHITE, 10)
		_beam(near, Vector3(gx + sx * 1.2, gh - 0.1, -gw), Vector3(gx + sx * 1.2, gh - 0.1, gw), 0.05, WHITE)
		_beam(near, Vector3(gx + sx * depth, 0.03, -gw), Vector3(gx + sx * depth, 0.03, gw), 0.05, WHITE)
		# Nets: roof, back and both sides.
		var cell := 0.16
		var a := Vector3(gx, gh, -gw)
		var b := Vector3(gx, gh, gw)
		var c := Vector3(gx + sx * 1.2, gh - 0.1, gw)
		var d := Vector3(gx + sx * 1.2, gh - 0.1, -gw)
		nets.quad(a, b, c, d, Vector3.UP, Color.WHITE, Vector2.ZERO, Vector2(gw * 2.0 / cell, 1.2 / cell))
		var e := Vector3(gx + sx * depth, 0.0, gw)
		var f := Vector3(gx + sx * depth, 0.0, -gw)
		nets.quad(d, c, e, f, Vector3(sx, 0.4, 0).normalized(), Color.WHITE, Vector2.ZERO, Vector2(gw * 2.0 / cell, 2.6 / cell))
		for sz in [-1.0, 1.0]:
			nets.quad(Vector3(gx, 0, sz * gw), Vector3(gx + sx * depth, 0, sz * gw),
				Vector3(gx + sx * 1.2, gh - 0.1, sz * gw), Vector3(gx, gh, sz * gw),
				Vector3(0, 0, sz), Color.WHITE, Vector2.ZERO, Vector2(depth / cell, gh / cell))


static func _flags(near: VC) -> void:
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var p := Vector3(sx * L.PITCH_HALF.x, 0, sz * L.PITCH_HALF.y)
			near.cylinder(0.03, 0.035, 1.6, Transform3D(Basis(), p + Vector3.UP * 0.8), WHITE, 6)
			var t := p + Vector3.UP * 1.58
			var fl := t + Vector3(-sx * 0.55, -0.2, 0.0)
			near.tri2(t, t + Vector3.DOWN * 0.42, fl, BLUE if sz < 0.0 else WHITE)
			near.sphere(t + Vector3.UP * 0.04, Vector3.ONE * 0.05, BLUE, Basis(), 6, 4)


static func _dugouts(near: VC, seats: VC, glass: VC) -> void:
	for sx in [-1.0, 1.0]:
		var cx: float = sx * 13.5
		var z0 := -L.BOARD_Z - L.BOARD_T - 0.25
		var z1 := -L.stand_front_z() + 0.05
		near.block(Vector3(cx - 3.2, 0.0, z1), Vector3(cx + 3.2, 1.9, z1 + 0.15), WHITE)
		for k in 7:
			seats.box(Vector3(0.7, 0.75, 0.55), Transform3D(Basis(), Vector3(cx - 2.7 + 0.9 * float(k), 0.38, z1 + 0.45)),
				BLUE if k % 3 != 1 else SKY_BLUE)
		for side in [-1.0, 1.0]:
			near.block(Vector3(cx + side * 3.2 - 0.06, 0.0, z0), Vector3(cx + side * 3.2 + 0.06, 1.9, z1), WHITE)
		var a := Vector3(cx - 3.2, 1.9, z1)
		var b := Vector3(cx + 3.2, 1.9, z1)
		var c := Vector3(cx + 3.2, 1.35, z0)
		var d := Vector3(cx - 3.2, 1.35, z0)
		glass.quad(a, b, c, d, Vector3(0, 0.8, 0.6).normalized(), Color.WHITE)
		glass.quad(d, c, Vector3(cx + 3.2, 0.3, z0), Vector3(cx - 3.2, 0.3, z0), Vector3.BACK, Color.WHITE)


## The players' tunnel: a blue-and-white telescopic canopy out of a dark
## doorway, warm light at the far end.
static func _tunnel(near: VC, lights: VC) -> void:
	var z_wall := -L.stand_front_z()
	var z_mouth := -L.BOARD_Z - L.BOARD_T - 0.05
	var len := z_mouth - z_wall
	var r := L.TUNNEL_HALF_W
	near.block(Vector3(-r - 0.2, 0.0, z_wall - 0.05), Vector3(r + 0.2, 2.9, z_wall + 0.02), Color(0.03, 0.04, 0.07))
	lights.box(Vector3(r * 1.2, 0.5, 0.05), Transform3D(Basis(), Vector3(0, 2.2, z_wall + 0.04)), WARM)
	var segs := 9
	for k in segs:
		var a0 := PI * float(k) / float(segs)
		var a1 := PI * float(k + 1) / float(segs)
		var am := (a0 + a1) * 0.5
		var p := Vector3(cos(am) * r, 0.9 + sin(am) * r, (z_wall + z_mouth) * 0.5)
		var basis := Basis(Vector3.BACK, am)
		var seg_w := 2.0 * r * sin((a1 - a0) * 0.5) + 0.04
		near.box(Vector3(0.12, seg_w, len), Transform3D(basis, p), BLUE if k % 2 == 0 else WHITE)
	for sx in [-1.0, 1.0]:
		near.block(Vector3(sx * r - 0.06, 0.0, z_wall), Vector3(sx * r + 0.06, 0.95, z_mouth), WHITE)


# --- Collision ------------------------------------------------------------------------

static func _colliders(root: Node3D) -> void:
	SceneryKit.solid(root, "GroundCollider", Vector3(100.0, 1.0, 80.0), Vector3(0.0, -0.5, 0.0))
	var x := L.BOARD_X + 0.3
	var z := L.BOARD_Z + 0.3
	var t := 0.6
	var walls := [
		[Vector3(x * 2.0 + t * 2.0, 1.0, t), Vector3(0, 0, -z)],
		[Vector3(x * 2.0 + t * 2.0, 1.0, t), Vector3(0, 0, z)],
		[Vector3(t, 1.0, z * 2.0), Vector3(-x, 0, 0)],
		[Vector3(t, 1.0, z * 2.0), Vector3(x, 0, 0)],
	]
	# Low on WORLD: balls bounce off it and the camera arm sails over it.
	for i in walls.size():
		var s: Vector3 = walls[i][0]
		var c: Vector3 = walls[i][1]
		SceneryKit.solid(root, "BallWall%d" % i, Vector3(s.x, BALL_WALL_H, s.z), c + Vector3.UP * BALL_WALL_H * 0.5)
	# Tall on BOSS: heroes collide with BOSS, the spring arm does not.
	var fence := StaticBody3D.new()
	fence.name = "HeroFence"
	fence.collision_layer = PhysicsLayers.BOSS
	fence.collision_mask = 0
	root.add_child(fence)
	for w in walls:
		var s2: Vector3 = w[0]
		SceneryKit.solid_shape(fence, Vector3(s2.x, FENCE_H, s2.z), (w[1] as Vector3) + Vector3.UP * FENCE_H * 0.5)
	# Goal frames: posts, bar and the net box, so a ball hits the net and stops.
	for sx in [-1.0, 1.0]:
		var gx: float = sx * L.PITCH_HALF.x
		for sz in [-1.0, 1.0]:
			SceneryKit.solid(root, "Post", Vector3(0.16, 2.4, 0.16), Vector3(gx, 1.2, sz * 3.6))
			SceneryKit.solid(root, "NetSide", Vector3(1.9, 2.3, 0.1), Vector3(gx + sx * 0.95, 1.15, sz * 3.65))
		SceneryKit.solid(root, "Bar", Vector3(0.16, 0.16, 7.4), Vector3(gx, 2.4, 0))
		SceneryKit.solid(root, "NetBack", Vector3(0.1, 2.2, 7.3), Vector3(gx + sx * 1.85, 1.1, 0))


static func _beam(vc: VC, a: Vector3, b: Vector3, t: float, color: Color) -> void:
	var d := b - a
	var len := d.length()
	if len < 1e-4:
		return
	var dir := d / len
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var bx := dir
	var bz := dir.cross(up).normalized()
	var by := bz.cross(dir).normalized()
	vc.box(Vector3(len, t, t), Transform3D(Basis(bx, by, bz), (a + b) * 0.5), color)
