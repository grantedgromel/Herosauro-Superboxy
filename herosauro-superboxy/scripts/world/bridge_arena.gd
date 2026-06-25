extends Node3D
## BridgeArena: the playable Dom Luis I bridge over the Douro.
##
## The static collidable parts (deck, railings, river, light, sky) live in the
## .tscn. This script adds the purely-decorative, NON-COLLIDING ironwork that
## gives the bridge its iconic Dom Luís I silhouette: the single great steel arch
## slung beneath the deck, a few clean spandrels tying it up, and a sparse parapet.
## Deliberately simple — no overhead cross-ties or lattice thicket. Grey, toon-shaded.

const ARCH_SPAN := 92.0      # horizontal reach of the arch (x in [-46, 46])
const ARCH_RISE := 18.0      # how far the arch drops below the deck
const ARCH_SEGMENTS := 24    # straight beam segments approximating the curve
const DECK_BOTTOM := 0.0     # underside of the deck box (deck centred at y=1)
const POST_COUNT := 7        # sparse railing posts per side (scale cue, not a ladder)
const RAIL_TOP := 4.0        # height of the top guard rail


func _ready() -> void:
	var steel := ToonFactory.solid(Color(0.40, 0.43, 0.47), 0.05)   # weathered iron grey
	var dark_steel := ToonFactory.solid(Color(0.28, 0.30, 0.34), 0.05)

	_build_arch(steel, dark_steel)
	_build_posts(steel)


# --- The iconic arch -------------------------------------------------------

func _build_arch(steel: ShaderMaterial, dark_steel: ShaderMaterial) -> void:
	var arch := Node3D.new()
	arch.name = "Arch"
	add_child(arch)

	# Two parallel arch ribs, one near each railing edge (z = +-5), built from
	# short straight beam segments following a parabola that dips below the deck.
	for z_side in [-5.0, 5.0]:
		var prev := _arch_point(-1.0, z_side)
		for i in range(ARCH_SEGMENTS + 1):
			var t := -1.0 + 2.0 * float(i) / float(ARCH_SEGMENTS)
			var p := _arch_point(t, z_side)
			if i > 0:
				_beam_between(arch, prev, p, 1.0, steel)   # thicker, bolder single arch
			prev = p

	# A few clean spandrel posts tying the arch up to the deck (sparse, not a thicket).
	for z_side in [-5.0, 5.0]:
		for i in [4, 8, 12, 16, 20]:
			var t := -1.0 + 2.0 * float(i) / float(ARCH_SEGMENTS)
			var bottom := _arch_point(t, z_side)
			var top := Vector3(bottom.x, DECK_BOTTOM, z_side)
			if top.y - bottom.y > 0.8:
				_beam_between(arch, bottom, top, 0.3, dark_steel)

	# Two stout stone-grey piers where the arch meets the bank.
	for sx in [-1.0, 1.0]:
		var pier := MeshInstance3D.new()
		pier.name = "Pier"
		var pier_mesh := BoxMesh.new()
		pier_mesh.size = Vector3(4.0, ARCH_RISE + 6.0, 13.0)
		pier.mesh = pier_mesh
		pier.position = Vector3(sx * (ARCH_SPAN * 0.5 + 1.0), -(ARCH_RISE + 6.0) * 0.5 + DECK_BOTTOM, 0.0)
		pier.material_override = ToonFactory.solid(Color(0.52, 0.50, 0.47), 0.06)
		arch.add_child(pier)


## A point on the arch rib for parameter t in [-1, 1] at a given z.
func _arch_point(t: float, z: float) -> Vector3:
	var x := t * ARCH_SPAN * 0.5
	# Parabola: 0 at the ends, -ARCH_RISE at the centre, all below the deck.
	var y := DECK_BOTTOM - ARCH_RISE * (1.0 - t * t)
	return Vector3(x, y, z)


## Spawn a thin box "beam" spanning from a to b with the given thickness.
func _beam_between(parent: Node3D, a: Vector3, b: Vector3, thickness: float, mat: ShaderMaterial) -> void:
	var beam := MeshInstance3D.new()
	beam.name = "Beam"
	var length := a.distance_to(b)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(length, thickness, thickness)
	beam.mesh = mesh
	beam.material_override = mat
	beam.position = (a + b) * 0.5

	# Orient the beam's local +X (its long axis) along (b - a).
	var dir := (b - a).normalized()
	if dir.length() > 0.001:
		var yaw := atan2(-dir.z, Vector2(dir.x, dir.z).length())
		var pitch := atan2(dir.y, Vector2(dir.x, dir.z).length())
		beam.rotation = Vector3(0.0, yaw, pitch)
	parent.add_child(beam)


# --- Railing posts ---------------------------------------------------------

func _build_posts(steel: ShaderMaterial) -> void:
	var posts := Node3D.new()
	posts.name = "RailPosts"
	add_child(posts)

	# Posts run the length of the bridge on both edges, just inside the walls.
	for z_side in [-5.7, 5.7]:
		for i in range(POST_COUNT):
			var x := lerpf(-48.0, 48.0, float(i) / float(POST_COUNT - 1))
			var post := MeshInstance3D.new()
			post.name = "Post"
			var mesh := BoxMesh.new()
			mesh.size = Vector3(0.22, RAIL_TOP - 2.0, 0.22)
			post.mesh = mesh
			# Deck top is y=2; posts rise from there to the top rail.
			post.position = Vector3(x, 2.0 + (RAIL_TOP - 2.0) * 0.5, z_side)
			post.material_override = steel
			posts.add_child(post)

		# A continuous top guard rail capping the posts.
		var rail := MeshInstance3D.new()
		rail.name = "TopRail"
		var rail_mesh := BoxMesh.new()
		rail_mesh.size = Vector3(98.0, 0.18, 0.3)
		rail.mesh = rail_mesh
		rail.position = Vector3(0.0, 2.0 + (RAIL_TOP - 2.0), z_side)
		rail.material_override = steel
		posts.add_child(rail)
