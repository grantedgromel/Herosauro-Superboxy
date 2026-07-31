extends SceneTree
## Headless clearance check for the wrecked catenary.
##
##     godot --headless --path . -s res://scripts/world/bridge/_wreck_probe.gd
##
## Two questions, both of which used to be answered wrong and neither of which a
## screenshot can answer at all, because the offending geometry is a 30 mm wire
## behind a nine-metre giant.
##
## 1. THE GIANT. Adamastor's model is 2.8 x 8.6 x 2.4 (adamastor.gd CORPSE_SIZE)
##    on a body clamped to x in [-14, 24], |z| <= 5, and the parapet stops that
##    body's 5 x 9 x 4 collider at |z| = 4.55 — so the visible giant sweeps
##    |z| <= 5.75 and rises to 10.6. Nothing at all may be inside that box above
##    ankle height. Before this pass the contact wire (7.0), its messenger (7.72)
##    and two gantry cross-spans (7.84) all ran straight through it.
##
## 2. THE HEROES. Everything the wreck adds has to stay outboard of the walkable
##    envelope (|z| <= 6.55) or above the contact wire it replaces (y = 7.0),
##    because a hero jumping off the raised footway already reaches 6.95 and there
##    is therefore no gap underneath an overhead line on this deck to hang
##    anything in. Measured on the wreck alone, including the two swinging ends at
##    the extremes of their swing.

const DeckKit := preload("res://scripts/world/bridge/deck_kit.gd")
const ArenaScript := preload("res://scripts/world/bridge_arena.gd")

## adamastor.gd's clamp widened by half of CORPSE_SIZE.x, and the visible half
## depth the parapet lets that body's collider push to.
const GIANT_X := Vector2(-15.4, 25.4)
const GIANT_Z := 5.75
const GIANT_TOP := 10.6
## Above the drains and the litter, which are flush with the paving and which the
## giant walks over rather than into.
const GIANT_FLOOR := 2.5

## Outer edge of anything a hero can stand on: the parapet's inner face.
const WALKABLE_Z := 6.55
## The contact wire this replaces.
const CLEAR_Y := 7.0


func _initialize() -> void:
	var arena: Node3D = ArenaScript.new()
	root.add_child(arena)

	var fails := 0
	fails += _giant_sweep(arena)
	fails += _wreck_clearance(arena)
	arena.queue_free()
	quit(1 if fails > 0 else 0)


## Walk every vertex of the assembled bridge and report anything standing inside
## the giant's swept volume.
func _giant_sweep(arena: Node3D) -> int:
	var worst := 1e9
	var hits := 0
	var where := ""
	for mi in _meshes(arena):
		var xf: Transform3D = mi.global_transform
		for v in _verts(mi):
			var p: Vector3 = xf * v
			if p.x < GIANT_X.x or p.x > GIANT_X.y:
				continue
			if absf(p.z) > GIANT_Z or p.y < GIANT_FLOOR or p.y > GIANT_TOP:
				continue
			hits += 1
			if p.y < worst:
				worst = p.y
				where = "%s at %v" % [mi.name, p]
	print("giant sweep  x %.1f..%.1f  |z| <= %.2f  y %.1f..%.1f" % [
			GIANT_X.x, GIANT_X.y, GIANT_Z, GIANT_FLOOR, GIANT_TOP])
	if hits == 0:
		print("  clear: 0 vertices")
		return 0
	print("  !! %d vertices inside the giant, lowest %s" % [hits, where])
	return 1


## Rebuild the wreck on its own and measure it against the hero envelope. Built
## from the arena's own constants rather than repeated numbers, so this cannot
## drift away from what the scene actually contains.
func _wreck_clearance(arena: Node3D) -> int:
	var k: Dictionary = (arena.get_script() as Script).get_script_constant_map()
	var span_y: float = k["MAST_BASE_Y"] + DeckKit.MAST_HEIGHT - DeckKit.SPAN_DROP

	var wreck := MeshBaker.new()
	for x: float in k["CATENARY_XS"]:
		if arena.call("_gantry_is_wrecked", x, span_y):
			DeckKit.torn_cross_span(wreck, x, k["MAST_Z"], span_y,
					k["WRECK_HANG_Z"], k["WRECK_CATCH_Y"] - 0.35)
	var loose := Node3D.new()
	arena.call("_build_fallen_line", wreck, loose)

	# Static wreck first, then the two swinging ends at all four extremes of their
	# swing — a pendulum is only clear if it is clear at the ends of its arc.
	var points: Array[Vector3] = []
	var holder := wreck.commit(null, "Wreck", false)
	for v in _verts(holder):
		points.append(v)
	holder.free()
	for child in loose.get_children():
		var mi := child as MeshInstance3D
		if mi == null:
			continue
		var amp: float = mi.get("amplitude")
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				var basis := Basis.from_euler(Vector3(sx * amp, 0.0, sz * amp * 0.7))
				var xf := Transform3D(basis, mi.position)
				for v in _verts(mi):
					points.append(xf * v)
	loose.queue_free()

	var worst_y := 1e9
	var worst_at := Vector3.ZERO
	var lowest := 1e9
	for p in points:
		lowest = minf(lowest, p.y)
		if absf(p.z) <= WALKABLE_Z and p.y < worst_y:
			worst_y = p.y
			worst_at = p
	print("wreck: %d vertices, lowest point y = %.2f" % [points.size(), lowest])
	if worst_y > 1e8:
		print("  clear: nothing inboard of |z| = %.2f at all" % WALKABLE_Z)
		return 0
	print("  inboard of |z| = %.2f the lowest is y = %.2f at %v (needs >= %.2f)" % [
			WALKABLE_Z, worst_y, worst_at, CLEAR_Y])
	if worst_y >= CLEAR_Y:
		print("  clear by %.2f m" % (worst_y - CLEAR_Y))
		return 0
	print("  !! the wreck reaches into the hero envelope")
	return 1


func _meshes(from: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var stack: Array[Node] = [from]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var mi := n as MeshInstance3D
		if mi != null and mi.mesh != null:
			out.append(mi)
		stack.append_array(n.get_children())
	return out


func _verts(mi: MeshInstance3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	if mi.mesh == null:
		return out
	for s in mi.mesh.get_surface_count():
		var arrays: Array = mi.mesh.surface_get_arrays(s)
		if arrays.is_empty():
			continue
		out.append_array(arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array)
	return out
