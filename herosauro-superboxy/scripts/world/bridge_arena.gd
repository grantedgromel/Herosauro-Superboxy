extends Node3D
## BridgeArena: the playable Dom Luis I bridge over the Douro.
##
## The static collidable parts (deck, railings, river, light, sky) live in the
## .tscn. This script adds the purely-decorative, NON-COLLIDING ironwork that
## gives the bridge its iconic Dom Luís I silhouette: the single great steel arch
## slung beneath the deck, X-braced lattice tying its ribs into a deep iron truss,
## a sparse parapet, and dusk lampposts along the rail tops. Grey, toon-shaded.

const ARCH_SPAN := 92.0      # horizontal reach of the arch (x in [-46, 46])
const ARCH_RISE := 18.0      # how far the arch drops below the deck
const ARCH_SEGMENTS := 24    # straight beam segments approximating the curve
const DECK_BOTTOM := 0.0     # underside of the deck box (deck centred at y=1)
const POST_COUNT := 7        # sparse railing posts per side (scale cue, not a ladder)
const RAIL_TOP := 4.0        # height of the top guard rail

# Lamppost positions: the camera lives on the +z side, so the far rail carries
# the full row while the near rail gets just two at the ends, outside the boss
# arena, where the poles can't cross the action sight line.
const LAMP_XS_FAR := [-40.0, -20.0, 0.0, 20.0, 40.0]
const LAMP_XS_NEAR := [-44.0, 44.0]


func _ready() -> void:
	var steel := ToonFactory.solid(Color(0.40, 0.43, 0.47), 0.05)   # weathered iron grey
	var dark_steel := ToonFactory.solid(Color(0.28, 0.30, 0.34), 0.05)

	_build_arch(steel, dark_steel)
	_build_lattice(steel)
	_build_posts(steel)
	_build_lamps()


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


# --- Lattice bracing --------------------------------------------------------

## X-cross-braces between the two ribs plus a raised second chord riding each
## rib, so the arch reads as the Dom Luís I deep lattice truss instead of two
## lone parabolas.
func _build_lattice(steel: ShaderMaterial) -> void:
	var lattice := Node3D.new()
	lattice.name = "Lattice"
	add_child(lattice)

	# Braces sit in the deck's shadow where outlines smear to mush, so no outline.
	var brace := ToonFactory.solid(Color(0.28, 0.30, 0.34), 0.0)

	# X-braces between the ribs, every third segment.
	for i in range(3, ARCH_SEGMENTS - 2, 3):
		var t0 := -1.0 + 2.0 * float(i) / float(ARCH_SEGMENTS)
		var t1 := -1.0 + 2.0 * float(i + 2) / float(ARCH_SEGMENTS)
		_beam_between(lattice, _arch_point(t0, -5.0), _arch_point(t1, 5.0), 0.22, brace)
		_beam_between(lattice, _arch_point(t0, 5.0), _arch_point(t1, -5.0), 0.22, brace)

	# The second chord rides 2 units above the main rib across the middle span,
	# thickening the arch into the truss band you see from the river.
	for z_side in [-5.0, 5.0]:
		var prev := _arch_point(-0.8, z_side) + Vector3(0.0, 2.0, 0.0)
		for i in range(1, 13):
			var t := lerpf(-0.8, 0.8, float(i) / 12.0)
			var p := _arch_point(t, z_side) + Vector3(0.0, 2.0, 0.0)
			_beam_between(lattice, prev, p, 0.5, steel)
			prev = p


# --- Lampposts ---------------------------------------------------------------

func _build_lamps() -> void:
	var lamps := Node3D.new()
	lamps.name = "Lamps"
	add_child(lamps)

	var iron := ToonFactory.solid(Color(0.20, 0.22, 0.26), 0.03)
	for x in LAMP_XS_FAR:
		_lamp(lamps, x, -6.0, iron)
	for x in LAMP_XS_NEAR:
		_lamp(lamps, x, 6.0, iron)


## One dusk lamppost planted on the rail top: slim iron pole, warm glowing globe.
func _lamp(parent: Node3D, x: float, z: float, iron: ShaderMaterial) -> void:
	var pole := MeshInstance3D.new()
	pole.name = "LampPole"
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.07
	pole_mesh.bottom_radius = 0.07
	pole_mesh.height = 2.4
	pole_mesh.radial_segments = 8
	pole.mesh = pole_mesh
	pole.position = Vector3(x, RAIL_TOP + 1.2, z)
	pole.material_override = iron
	parent.add_child(pole)

	var globe := MeshInstance3D.new()
	globe.name = "LampGlobe"
	var globe_mesh := SphereMesh.new()
	globe_mesh.radius = 0.17
	globe_mesh.height = 0.34
	globe_mesh.radial_segments = 8
	globe_mesh.rings = 4
	globe.mesh = globe_mesh
	globe.position = Vector3(x, RAIL_TOP + 2.55, z)
	globe.material_override = ToonFactory.glow(Color(1.0, 0.85, 0.55), 2.2)
	parent.add_child(globe)


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
