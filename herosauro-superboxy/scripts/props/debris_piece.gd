class_name DebrisPiece
extends RigidBody3D
## One shard thrown off by a damaged or shattered prop.
##
## Budgeted and self-cleaning: shattering is the one place in this game where an
## unbounded number of rigid bodies could appear (a boss slam can catch five
## barrels at once), so the count is capped process-wide by MAX_LIVE and every
## piece frees itself after `lifetime`. A caller that cannot reserve a slot
## simply gets fewer pieces rather than a frame spike.
##
## Pieces do not mask PLAYERS. Shards that trip the hero mid-fight are a bug
## report, not a feature.
##
## A piece carries its own MESH, handed in by the caller. It used to build a
## BoxMesh from the requested size, which meant a crate, a cask and a granite
## block all burst into the same grey dice in three different colours — the whole
## of "material-appropriate destruction" was a tint. PropMeshKit owns the shapes;
## this owns the lifetime, the budget and the physics.

## Ceiling across the whole process. ~5 props' worth of shards live at once,
## which at 8 collision pairs each is still trivial for Jolt.
const MAX_LIVE := 40
const SHRINK_TIME := 0.45
const CULL_Y := -6.0

## Below this speed a shard has arrived, and is put to sleep rather than being
## left for the solver to converge on. Jolt's own sleep threshold is generous
## enough that a dozen shards can spend a second nudging each other on a flat
## deck, which reads as vibration, not as settling.
const SETTLE_SPEED := 0.35
const SETTLE_SPIN := 0.9
## How long it has to be that slow for. One physics frame of slowness is the top
## of a bounce, not a rest.
const SETTLE_TIME := 0.30

static var _live: int = 0

var lifetime: float = 4.0

var _life: float = 0.0
var _counted: bool = false
var _dying: bool = false
var _slow_for: float = 0.0


## How many more pieces may be spawned right now.
static func budget_left() -> int:
	return maxi(0, MAX_LIVE - _live)


## Live count as the budget believes it. Compare against the "debris" group to
## catch a leak — that is exactly what _props_probe.gd does.
static func live_count() -> int:
	return _live


## Recount from the tree. The counter is a process-wide static and the world root
## is rebuilt between runs, so a single missed PREDELETE would permanently eat
## part of the budget for the rest of the session — every later fight would get
## fewer shards for no visible reason. Called on game_started; cheap, and it turns
## a silent leak into a self-healing one.
static func resync_budget(tree: SceneTree) -> int:
	var n := 0
	for d in tree.get_nodes_in_group("debris"):
		if is_instance_valid(d) and not (d as Node).is_queued_for_deletion():
			n += 1
	_live = n
	return n


## Build one shard and hand it to `parent`. Returns null when the budget is
## spent, which callers must treat as "spawn fewer", not as an error.
##
## `mesh` is the shard's look and `collider` its physics box — they are separate
## because a bowed stave's mesh is not a box and approximating it with one is
## both correct and cheaper than a convex hull nobody will look at.
static func spawn(parent: Node3D, at: Vector3, impulse: Vector3, mesh: Mesh,
		collider: Vector3, material: Material, piece_lifetime: float, spin: Vector3,
		orientation: Basis = Basis.IDENTITY, piece_mass: float = 3.0) -> DebrisPiece:
	if parent == null or mesh == null or budget_left() <= 0:
		return null

	var piece := DebrisPiece.new()
	piece.name = "Debris"
	piece.lifetime = piece_lifetime
	piece.mass = maxf(0.2, piece_mass)

	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	mi.material_override = material
	piece.add_child(mi)

	var col := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = collider
	col.shape = bs
	piece.add_child(col)

	parent.add_child(piece)
	piece.global_transform = Transform3D(orientation, at)
	piece.linear_velocity = impulse
	piece.angular_velocity = spin
	return piece


func _ready() -> void:
	add_to_group("debris")
	_live += 1
	_counted = true

	collision_layer = PhysicsLayers.PROPS
	collision_mask = PhysicsLayers.WORLD | PhysicsLayers.PROPS

	can_sleep = true
	continuous_cd = false
	linear_damp = 0.1
	# 0.5 -> 1.1. A shard leaves the burst at up to 8 rad/s and at 0.5 it was
	# still visibly spinning when it froze at sleep, which reads as the animation
	# being cut rather than as the piece coming to rest.
	angular_damp = 1.1
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	pm.bounce = 0.12
	physics_material_override = pm

	_life = lifetime


func _physics_process(delta: float) -> void:
	# The cull runs even while dying: a piece whose shrink started in mid-air over
	# the river would otherwise keep falling for SHRINK_TIME with its collider
	# live, and the whole point of the cull is that nothing below the deck is ever
	# anyone's problem.
	if global_position.y < CULL_Y:
		queue_free()
		return
	if _dying:
		return

	_life -= delta
	if _life <= 0.0:
		_shrink_away()
		return

	if sleeping:
		return
	if linear_velocity.length() < SETTLE_SPEED and angular_velocity.length() < SETTLE_SPIN:
		_slow_for += delta
		if _slow_for >= SETTLE_TIME:
			sleeping = true
	else:
		_slow_for = 0.0


## Scale the MESH out rather than fading the material: ToonFactory hands out
## shared cached materials, so a fade would need a per-piece duplicate and an
## alpha-pass draw for something on screen for 0.45 s.
func _shrink_away() -> void:
	_dying = true
	# Stop being a physics object the instant it stops being a real object.
	# A shrinking shard that still shoves its neighbours around makes a settled
	# pile visibly rearrange itself as it disappears.
	freeze = true
	collision_layer = 0
	collision_mask = 0

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
