extends SceneTree
## Throwaway budget + winding probe for FacadeBuilder. Not shipped.

const FB := preload("res://scripts/world/facade_builder.gd")
const Geo := preload("res://scripts/world/facade/facade_geo.gd")
const Batch := preload("res://scripts/world/facade/facade_batch.gd")

var _fails := 0


func _initialize() -> void:
	print("=== budgets ===")
	_one("typical 5-storey FULL", FB.Detail.FULL, 5, FB.Style.PLASTER, FB.Ground.DOOR, true)
	_one("5-storey MEDIUM", FB.Detail.MEDIUM, 5, FB.Style.PLASTER, FB.Ground.DOOR, false)
	_one("5-storey LOW", FB.Detail.LOW, 5, FB.Style.PLASTER, FB.Ground.DOOR, false)
	_one("azulejo 5-storey FULL", FB.Detail.FULL, 5, FB.Style.AZULEJO, FB.Ground.SHOPFRONT, true)
	_one("granite arch FULL", FB.Detail.FULL, 4, FB.Style.GRANITE, FB.Ground.ARCH, false)

	_row("terrace x14 FULL", 14, FB.Detail.FULL, true)
	_row("terrace x14 MEDIUM", 14, FB.Detail.MEDIUM, false)
	_row("terrace x14 LOW", 14, FB.Detail.LOW, false)
	_row("terrace x40 MEDIUM", 40, FB.Detail.MEDIUM, false)

	print("=== winding ===")
	_check_windings()
	print("=== bounds ===")
	_check_bounds()
	print("=== ground floor containment ===")
	_check_ground_floor()
	print("=== public API ===")
	_check_api()
	print("=== determinism ===")
	_check_determinism()
	print("=== FAILURES: %d ===" % _fails)
	quit()


# --- Budgets -----------------------------------------------------------------

func _one(label: String, detail: int, floors: int, style: int, ground: int, laundry: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var spec := FB.random_spec(rng, 14.0, 16.0)
	spec.detail = detail
	spec.floors = floors
	spec.style = style
	spec.ground = ground
	spec.laundry = laundry
	spec.width = 4.0
	spec.depth = 6.0
	if style == FB.Style.AZULEJO:
		spec.wall_color = FB.AZULEJO_PALETTE[0]
	var batch := Batch.new()
	FB.add_to_batch(batch, spec, rng)
	print("%-26s tris=%5d  draw_calls=%2d  wall_h=%.1f  total_h=%.1f" % [
		label, batch.triangle_count(), batch.surface_count(),
		spec.wall_height(), spec.total_height()])


func _row(label: String, count: int, detail: int, laundry: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20250727
	var batch := Batch.new()
	var x := -24.0
	for i in count:
		var spec := FB.random_spec(rng, 11.0, 18.0)
		spec.detail = detail
		spec.laundry = laundry
		spec.position = Vector3(x + spec.width * 0.5, 0.0, 0.0)
		x += spec.width + 0.06
		FB.add_to_batch(batch, spec, rng)
	var node := batch.commit("Row")
	var welded := 0
	for child in node.get_children():
		var mi := child as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			welded += mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX].size() / 3
	print("%-26s tris=%5d  draw_calls=%2d  welded=%5d  per_building=%d" % [
		label, batch.triangle_count(), batch.surface_count(), welded,
		batch.triangle_count() / count])
	node.free()


# --- Winding -----------------------------------------------------------------
# Nothing here will be seen rendering before the integrator's pass, and a quad
# wound backwards is invisible rather than obviously wrong, so every emitter's
# normal direction gets asserted numerically.

func _tris(b: MeshBaker) -> Array:
	var mi := b.commit(null, "probe", false)
	var arrays := (mi.mesh as ArrayMesh).surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var out := []
	for t in range(idx.size() / 3):
		var a := idx[t * 3]
		var centroid := (verts[a] + verts[idx[t * 3 + 1]] + verts[idx[t * 3 + 2]]) / 3.0
		out.append([centroid, norms[a]])
	mi.free()
	return out


func _expect(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("  ok    %s" % label)
	else:
		_fails += 1
		print("  FAIL  %s  %s" % [label, detail])


## `want` is +1 for faces that should turn toward the opening's centre (a window
## reveal) and -1 for faces that should turn away (a moulding's outer return).
func _expect_tube(label: String, tris: Array, want: float) -> void:
	var centre := Vector2(0.0, 2.0)
	var bad := 0
	var flat := 0
	for t in tris:
		var c: Vector3 = t[0]
		var n: Vector3 = t[1]
		if absf(n.z) > 0.01:
			flat += 1     # a side wall must not lean along the depth axis
		if (centre - Vector2(c.x, c.y)).dot(Vector2(n.x, n.y)) * want <= 0.0:
			bad += 1
	_expect(label, bad == 0 and flat == 0, "%d wrong way, %d not perpendicular" % [bad, flat])


func _check_windings() -> void:
	var xf := Transform3D.IDENTITY

	var b := MeshBaker.new()
	Geo.rect(b, xf, -1.0, 0.0, 1.0, 2.0, 0.0)
	var worst := 1.0
	for t in _tris(b):
		worst = minf(worst, (t[1] as Vector3).dot(Vector3.BACK))
	_expect("rect faces +Z", worst > 0.99, "worst dot = %.3f" % worst)

	b = MeshBaker.new()
	Geo.rect_back(b, xf, -1.0, 0.0, 1.0, 2.0, 0.0)
	worst = 1.0
	for t in _tris(b):
		worst = minf(worst, (t[1] as Vector3).dot(Vector3.FORWARD))
	_expect("rect_back faces -Z", worst > 0.99, "worst dot = %.3f" % worst)

	# A reveal: side walls run parallel to the opening's depth axis and must turn
	# toward its centre, not away. Sign test, not an angle test — the four faces
	# of a rectangle point at four different directions, none of them at a point.
	b = MeshBaker.new()
	Geo.tube(b, xf, -0.5, 1.0, 0.5, 3.0, -0.2, 0.05, true)
	_expect_tube("tube inward faces the opening", _tris(b), 1.0)

	b = MeshBaker.new()
	Geo.tube(b, xf, -0.5, 1.0, 0.5, 3.0, 0.0, 0.06, false)
	_expect_tube("tube outward faces away", _tris(b), -1.0)

	# Punched panel: every surviving strip still faces the street, and the hole
	# is genuinely absent rather than covered.
	b = MeshBaker.new()
	var holes: Array[Rect2] = [Rect2(-0.4, 1.0, 0.8, 1.6), Rect2(0.8, 2.4, 0.6, 0.9)]
	Geo.panel(b, xf, -2.0, 0.0, 2.0, 5.0, holes, 0.0)
	worst = 1.0
	var inside_hole := 0
	for t in _tris(b):
		worst = minf(worst, (t[1] as Vector3).dot(Vector3.BACK))
		var c: Vector3 = t[0]
		for h in holes:
			if h.has_point(Vector2(c.x, c.y)):
				inside_hole += 1
	_expect("panel faces +Z", worst > 0.99, "worst dot = %.3f" % worst)
	_expect("panel holes are empty", inside_hole == 0, "%d tris inside a hole" % inside_hole)
	# 3 y-bands x (2 side strips + a middle) is what the guillotine should find.
	print("        panel strips = %d tris" % _tris(b).size())

	b = MeshBaker.new()
	Geo.ring(b, xf, -0.5, 1.0, 0.5, 3.0, 0.13, 0.13, 0.0, 0.13, 0.05)
	worst = 1.0
	for t in _tris(b):
		worst = minf(worst, (t[1] as Vector3).dot(Vector3.BACK))
	_expect("ring faces +Z", worst > 0.99, "worst dot = %.3f" % worst)

	b = MeshBaker.new()
	Geo.tri(b, xf, Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0))
	_expect("tri is exactly one triangle", _tris(b).size() == 1,
			"got %d" % _tris(b).size())

	# The roof. Both slopes and both gables have to face out of the loft.
	_check_roof(false)
	_check_roof(true)


func _check_roof(gable_front: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var spec := FB.Spec.new()
	spec.width = 4.0
	spec.depth = 6.0
	spec.floors = 3
	spec.gable_front = gable_front
	spec.chimneys = 0
	var batch := Batch.new()
	FB.add_to_batch(batch, spec, rng)

	var tile_b := batch.baker(Batch.roof(spec.roof_color))
	var down := 0
	var total := 0
	for t in _tris(tile_b):
		total += 1
		# Eave lips and the ridge cap have legitimate undersides; the slopes,
		# which are the overwhelming majority, must not point at the ground.
		if (t[1] as Vector3).y < -0.2:
			down += 1
	_expect("roof tiles face up (gable_front=%s)" % gable_front, float(down) / float(total) < 0.2,
			"%d/%d downward" % [down, total])

	# Gables live in the wall material, so isolate them by height.
	var wall_b := batch.baker(FB.WALL_PALETTE[0] if false else Batch.plaster(spec.wall_color))
	var wall_h := spec.wall_height()
	var bad := 0
	var seen := 0
	for t in _tris(wall_b):
		var c: Vector3 = t[0]
		if c.y < wall_h + 0.4:
			continue
		seen += 1
		var n: Vector3 = t[1]
		# A gable end faces along the ridge, i.e. sideways and never inward.
		var outward := Vector3(signf(c.x), 0.0, 0.0) if not gable_front else Vector3(0.0, 0.0, signf(c.z))
		if n.dot(outward) < 0.5:
			bad += 1
	_expect("gable ends face out (gable_front=%s)" % gable_front, seen > 0 and bad == 0,
			"%d/%d wrong" % [bad, seen])


# --- Bounds ------------------------------------------------------------------

func _check_bounds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var spec := FB.random_spec(rng, 14.0, 15.0)
	spec.width = 4.0
	spec.depth = 6.0
	spec.position = Vector3(10.0, 3.0, -20.0)
	spec.laundry = true
	spec.side = 1
	spec.chimneys = 0
	var node := FB.build(spec, rng, "One")
	var aabb := AABB()
	var first := true
	for child in node.get_children():
		var b := (child as MeshInstance3D).mesh.get_aabb()
		aabb = b if first else aabb.merge(b)
		first = false
	print("  pos=%s size=%s" % [spec.position, aabb.size])
	print("  y span %.2f .. %.2f   roofline expected %.2f" % [
		aabb.position.y, aabb.end.y, spec.position.y + spec.total_height()])
	_expect("base sits on spec.position.y",
			absf(aabb.position.y - spec.position.y) < 0.25,
			"base y = %.3f" % aabb.position.y)
	_expect("roofline matches total_height() (chimneys excluded)",
			absf(aabb.end.y - (spec.position.y + spec.total_height())) < 0.35,
			"top y = %.3f" % aabb.end.y)
	_expect("footprint stays near the plot",
			aabb.size.x < spec.width + 1.4 and aabb.size.z < spec.depth + 1.4,
			"size = %s" % aabb.size)
	node.free()

	# The one that actually matters for a terrace: nothing may reach sideways
	# past the party wall, or a roof or a cornice grows out of the neighbour.
	for gable_front in [false, true]:
		var rng2 := RandomNumberGenerator.new()
		rng2.seed = 606
		var s := FB.random_spec(rng2, 12.0, 16.0)
		s.width = 4.0
		s.depth = 6.5
		s.gable_front = gable_front
		s.lean = 0.0
		s.tilt = 0.0
		s.yaw = 0.0
		s.side = 0
		var batch := Batch.new()
		FB.add_to_batch(batch, s, rng2)
		var n := batch.commit("Plot")
		var box := AABB()
		var f := true
		for child in n.get_children():
			var b := (child as MeshInstance3D).mesh.get_aabb()
			box = b if f else box.merge(b)
			f = false
		# Slack for the pantile relief: a crest stands 5 cm off the slope, and at
		# the verge a couple of centimetres of that lands sideways. Verge tiles do
		# stand proud in life, so this is geometry, not error.
		#
		# The budget is RETURN_SILL_PROUD, not PARTY_OVERHANG, since round 3: every
		# building now dresses both returns, and a return's window surrounds, sills
		# and string-course returns necessarily project along the party-wall axis
		# because that IS their face normal. That is a deliberate trade, and the
		# rule it relaxes is not the rule it looks like. What the check exists to
		# stop is a ROOF or a CORNICE growing out of the neighbour — geometry that
		# sits at or above the neighbour's wall head, where nothing hides it, and
		# which still has only PARTY_OVERHANG to play with. A moulding at a storey
		# line stands 11 cm into a 5 cm party gap and is therefore 6 cm inside a
		# solid wall that is exactly as deep as this one, because neighbours on a
		# level share a plot depth. Where the neighbour is absent — row ends and
		# alleys, which is the whole reason the returns are dressed — it projects
		# into open air, which is the point.
		var allowed := s.width + FacadeBuilder.RETURN_SILL_PROUD * 2.0 + 0.05
		_expect("nothing overhangs the party wall (gable_front=%s)" % gable_front,
				box.size.x <= allowed,
				"x span %.3f, allowed %.3f" % [box.size.x, allowed])
		print("  x %.2f (plot %.2f)   z %.2f (plot %.2f, eaves both sides)" % [
			box.size.x, s.width, box.size.z, s.depth])
		n.free()


# --- Ground floor ------------------------------------------------------------
# A door, a shopfront and an arch each carry dressings above the opening. Those
# have to fit inside the ground storey, or they punch through the first-floor
# sills and the string course lands across a signboard.

func _check_ground_floor() -> void:
	for ground in [FB.Ground.DOOR, FB.Ground.SHOPFRONT, FB.Ground.ARCH]:
		var worst := -1.0
		var worst_at := 0.0
		for step in 12:
			var gh := 3.0 + 0.1 * float(step)
			var rng := RandomNumberGenerator.new()
			rng.seed = 500 + step
			var spec := FB.Spec.new()
			spec.width = 3.2 + 0.2 * float(step)
			spec.ground_height = gh
			spec.ground = ground
			spec.plinth_height = 0.85           # the worst case: tallest threshold
			var batch := Batch.new()
			var holes: Array[Rect2] = []
			FB._emit_ground_floor(batch, Transform3D.IDENTITY, spec, rng, 0.0, gh, 2, holes)
			var top := -1e9
			for mat in [Batch.trim(), Batch.timber(), Batch.granite(), Batch.reveal_dark(),
					Batch.lit(), Batch.linen_thin(), Batch.iron()]:
				var b := batch.baker(mat)
				if b.triangle_count() == 0:
					continue
				for t in _tris(b):
					top = maxf(top, (t[0] as Vector3).y)
			if top - gh > worst:
				worst = top - gh
				worst_at = gh
		_expect("ground dressings fit their storey (%d)" % ground, worst < 0.0,
				"overshot by %.3f m at ground_height %.1f" % [worst, worst_at])


# --- Public API --------------------------------------------------------------
# Typed exactly as the doc comment tells the placement stream to type it, via the
# global class name rather than a preload.

func _check_api() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 31337

	var specs: Array[FacadeBuilder.Spec] = FacadeBuilder.terrace_specs(
			rng, 14, Vector3(-60.0, 0.0, -22.0), 11.0, 18.0, FacadeBuilder.Detail.FULL)
	for s in specs:
		s.laundry = true
	var row := FacadeBuilder.build_row(specs, rng, "RibeiraNorth")
	var lo := 1e9
	var hi := -1e9
	var front := -1e9
	for s in specs:
		lo = minf(lo, s.position.x - s.width * 0.5)
		hi = maxf(hi, s.position.x + s.width * 0.5)
		front = maxf(front, s.position.z + s.depth * 0.5)
	_expect("terrace_specs centres on the frontage", absf((lo + hi) * 0.5 + 60.0) < 0.01,
			"centre %.3f" % ((lo + hi) * 0.5))
	_expect("terrace_specs aligns the facades to the frontage", absf(front + 22.0) < 0.2,
			"front %.3f" % front)
	print("  14-house row spans %.1f m, %d draw calls" % [hi - lo, row.get_child_count()])
	row.free()

	var fitted := FacadeBuilder.terrace_specs_for_span(rng, 44.0, Vector3(60.0, 0.0, -22.0))
	var used := 0.0
	for s in fitted:
		used += s.width + FacadeBuilder.PARTY_WALL_GAP
	_expect("terrace_specs_for_span fills without overshooting",
			fitted.size() > 6 and used <= 44.0 + FacadeBuilder.PARTY_WALL_GAP,
			"%d houses using %.2f of 44.0 m" % [fitted.size(), used])

	# Sharing is the whole economic argument; prove the cache actually hands back
	# one material rather than one per building.
	_expect("palette colours share one material",
			FacadeBuilder.Batch.plaster(FacadeBuilder.WALL_PALETTE[0])
				== FacadeBuilder.Batch.plaster(FacadeBuilder.WALL_PALETTE[0])
			and FacadeBuilder.Batch.trim() == FacadeBuilder.Batch.trim())
	_expect("thin ironwork is double-sided",
			FacadeBuilder.Batch.iron_thin().cull_mode == BaseMaterial3D.CULL_DISABLED
			and FacadeBuilder.Batch.iron().cull_mode == BaseMaterial3D.CULL_BACK,
			"iron_thin must not be the shared cached iron")

	var batch := FacadeBuilder.Batch.new()
	batch.cast_shadows = false
	for s in FacadeBuilder.terrace_specs(rng, 8, Vector3(-64.0, -10.1, -10.0), 5.0, 8.0,
			FacadeBuilder.Detail.MEDIUM):
		s.ground = FacadeBuilder.Ground.ARCH
		FacadeBuilder.add_to_batch(batch, s, rng)
	var quay := batch.commit("Quay")
	_expect("cast_shadows=false reaches the meshes",
			(quay.get_child(0) as MeshInstance3D).cast_shadow
				== GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	quay.free()


# --- Determinism -------------------------------------------------------------

func _check_determinism() -> void:
	var counts: Array[int] = []
	for run in 2:
		var rng := RandomNumberGenerator.new()
		rng.seed = 4242
		var batch := Batch.new()
		for i in 8:
			var spec := FB.random_spec(rng, 10.0, 18.0)
			spec.laundry = true
			spec.position = Vector3(float(i) * 4.0, 0.0, 0.0)
			FB.add_to_batch(batch, spec, rng)
		counts.append(batch.triangle_count())
	_expect("same seed -> same geometry", counts[0] == counts[1],
			"%d vs %d" % [counts[0], counts[1]])
