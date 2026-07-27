class_name SceneryKit
extends RefCounted
## Primitive builders shared by the two procedural world scripts.
##
## bridge_arena.gd and sky_background.gd between them lay down a few thousand
## boxes. Both had grown their own `make a box / make a static body` helpers;
## these are the one copy, in the same static-factory shape as ToonFactory next
## door, so the batching and collision-layer decisions are made once.
##
## The important one is repeat(). Godot does not batch MeshInstance3Ds, so a
## hundred metres of kerbstone is a hundred draw calls; as a MultiMesh it is one.
## The bridge deck and the Ribeira window fittings both live entirely inside
## MultiMeshes for that reason, and it is what pays for the detail pass on a
## GL Compatibility web build.

static var _world_mats: Dictionary = {}


# --- Meshes ------------------------------------------------------------------

static func box(parent: Node3D, node_name: String, size: Vector3, pos: Vector3,
		mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


static func cylinder(parent: Node3D, node_name: String, top_r: float, bottom_r: float,
		height: float, pos: Vector3, mat: Material, segments: int = 8) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_r
	mesh.bottom_radius = bottom_r
	mesh.height = height
	mesh.radial_segments = segments
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


## One draw call for any number of identical, axis-aligned boxes: paving bays,
## balusters, window surrounds. Returns null for an empty list so a caller can
## hand over whatever it collected without checking first.
static func repeat(parent: Node3D, node_name: String, size: Vector3,
		positions: Array[Vector3], mat: Material) -> MultiMeshInstance3D:
	if positions.is_empty():
		return null

	var mesh := BoxMesh.new()
	mesh.size = size
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = positions.size()

	var half := size * 0.5
	var bounds := AABB(positions[0] - half, size)
	for i in positions.size():
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, positions[i]))
		bounds = bounds.merge(AABB(positions[i] - half, size))
	# Stated rather than left to be derived. A MultiMesh whose bounds go stale is
	# culled whole — a hundred metres of deck disappearing in one go — and that is
	# not the kind of failure anything short of a live render would catch.
	mm.custom_aabb = bounds

	var node := MultiMeshInstance3D.new()
	node.name = node_name
	node.multimesh = mm
	node.material_override = mat
	parent.add_child(node)
	return node


# --- Collision ---------------------------------------------------------------

## A StaticBody3D on the world layer carrying one box. mask 0 on purpose: a
## static body never queries anything, and a non-zero mask only buys broadphase
## pairs. Layer 1 is also what CameraRig's SpringArm sweeps, so anything built
## with this will push the camera as well as the player — which is the point for
## a parapet and a mistake for a handrail.
static func solid(parent: Node3D, node_name: String, size: Vector3,
		pos: Vector3, rot: Vector3 = Vector3.ZERO) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	parent.add_child(body)
	solid_shape(body, size, pos, rot)
	return body


## `rot` is Euler radians on the shape, for the occasional wedge — a collision
## ramp under a visual step, say. Keep it to shallow tilts: a steeply rotated box
## is exactly the shape a swept-sphere camera probe resolves badly against.
static func solid_shape(body: StaticBody3D, size: Vector3, pos: Vector3,
		rot: Vector3 = Vector3.ZERO) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = pos
	cs.rotation = rot
	body.add_child(cs)


# --- Materials ---------------------------------------------------------------

## ToonFactory maps its triplanar textures in OBJECT space, which stamps the
## identical patch of noise onto every instance that shares a mesh. That is right
## for scattered props and wrong for a hundred metres of coplanar paving, where
## the repeat is the first thing the eye finds. This returns a world-mapped copy,
## so the grain runs continuously across the whole surface instead.
##
## Only ever for geometry that does not move — a world-mapped prop swims through
## its own texture. The duplicate is mandatory (factory materials are shared and
## cached) and memoised here, so one call site per surface does not quietly
## become one material per call.
static func world_mapped(mat: StandardMaterial3D) -> StandardMaterial3D:
	var cached: StandardMaterial3D = _world_mats.get(mat)
	if cached != null:
		return cached
	var world: StandardMaterial3D = mat.duplicate()
	world.uv1_world_triplanar = true
	_world_mats[mat] = world
	return world
