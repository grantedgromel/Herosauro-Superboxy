class_name DebrisPiece
extends RigidBody3D
## One shard thrown off by a shattered prop.
##
## Budgeted and self-cleaning: shattering is the one place in this game where an
## unbounded number of rigid bodies could appear (a boss slam can catch five
## barrels at once), so the count is capped process-wide by MAX_LIVE and every
## piece frees itself after `lifetime`. A caller that cannot reserve a slot
## simply gets fewer pieces rather than a frame spike.
##
## Pieces do not mask PLAYERS. Shards that trip the hero mid-fight are a bug
## report, not a feature.

## Ceiling across the whole process. ~5 props' worth of shards live at once,
## which at 8 collision pairs each is still trivial for Jolt.
const MAX_LIVE := 40
const SHRINK_TIME := 0.45
const CULL_Y := -6.0

static var _live: int = 0

var lifetime: float = 4.0

var _life: float = 0.0
var _counted: bool = false
var _dying: bool = false


## How many more pieces may be spawned right now.
static func budget_left() -> int:
	return maxi(0, MAX_LIVE - _live)


## Build one shard and hand it to `parent`. Returns null when the budget is
## spent, which callers must treat as "spawn fewer", not as an error.
static func spawn(parent: Node3D, at: Vector3, impulse: Vector3, size: Vector3,
		material: Material, piece_lifetime: float, spin: Vector3) -> DebrisPiece:
	if parent == null or budget_left() <= 0:
		return null

	var piece := DebrisPiece.new()
	piece.name = "Debris"
	piece.lifetime = piece_lifetime

	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = material
	piece.add_child(mesh)

	var col := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	col.shape = bs
	piece.add_child(col)

	parent.add_child(piece)
	piece.global_position = at
	piece.linear_velocity = impulse
	piece.angular_velocity = spin
	return piece


func _ready() -> void:
	add_to_group("debris")
	_live += 1
	_counted = true

	collision_layer = PhysicsLayers.PROPS
	collision_mask = PhysicsLayers.WORLD | PhysicsLayers.PROPS

	mass = 3.0
	can_sleep = true
	continuous_cd = false
	linear_damp = 0.1
	angular_damp = 0.5
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	pm.bounce = 0.12
	physics_material_override = pm

	_life = lifetime


func _physics_process(delta: float) -> void:
	if _dying:
		return
	if global_position.y < CULL_Y:
		queue_free()
		return
	_life -= delta
	if _life <= 0.0:
		_shrink_away()


## Scale the MESH out rather than fading the material: ToonFactory hands out
## shared cached materials, so a fade would need a per-piece duplicate and an
## alpha-pass draw for something on screen for 0.45 s.
func _shrink_away() -> void:
	_dying = true
	var mesh := get_node_or_null("Mesh") as MeshInstance3D
	if mesh == null:
		queue_free()
		return
	var tween := create_tween()
	tween.tween_property(mesh, "scale", Vector3.ZERO, SHRINK_TIME)
	tween.tween_callback(queue_free)


func _notification(what: int) -> void:
	# PREDELETE rather than _exit_tree: the counter must not drop on a reparent,
	# only when the piece is actually gone.
	if what == NOTIFICATION_PREDELETE and _counted:
		_counted = false
		_live = maxi(0, _live - 1)
