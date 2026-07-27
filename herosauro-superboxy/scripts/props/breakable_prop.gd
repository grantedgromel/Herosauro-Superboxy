class_name BreakableProp
extends PropBody
## A prop that shatters into smaller rigid bodies when hit hard enough.
##
## Two triggers, because the two ways a prop gets destroyed are physically
## different: a swing or a rock hands it an explicit impulse through
## apply_hit_impulse(), while being hurled into a rail wall shows up as a sudden
## loss of speed. The second is measured as delta-v across one physics frame
## rather than through contact monitoring — it needs no contact_monitor budget
## and behaves identically on Jolt and Godot Physics.
##
## Piece count is a request, not a promise: DebrisPiece owns a process-wide
## budget and hands back fewer shards when the arena is already full of them.

@export_group("Breaking")
## Impulse magnitude (N*s) an explicit hit must carry to shatter this.
@export var break_impulse: float = 18.0
## Speed (m/s) that has to vanish in a single physics frame — i.e. how hard it
## must slam into something — to shatter on impact.
@export var break_delta_v: float = 7.0
@export var piece_count: int = 5
@export var piece_lifetime: float = 4.0
## Shard edge length as a fraction of the prop's own extent.
@export var piece_scale: float = 0.34
## Non-zero pins the debris scatter so a replay looks identical. The spawner
## sets it; leave 0 to derive one from the prop's resting position.
@export var rng_seed: int = 0

var _shattered: bool = false
var _prev_vel: Vector3 = Vector3.ZERO
var _rng := RandomNumberGenerator.new()


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _shattered or is_queued_for_deletion():
		return
	# _physics_process runs before the step is integrated, so linear_velocity is
	# the result of the PREVIOUS step: the frame after a wall hit, the whole
	# impact shows up here as one big drop.
	var vel := linear_velocity
	if not sleeping and _prev_vel.length() - vel.length() >= break_delta_v:
		# Shatter along the direction it was travelling — the pieces carry on
		# through, which is what sells the impact.
		shatter(_prev_vel.normalized() * 3.0)
		return
	_prev_vel = vel


func _on_impact(strength: float) -> void:
	if strength >= break_impulse:
		shatter(Vector3.ZERO)


## Replace this prop with `piece_count` shards. `push` is added to every shard's
## launch velocity so a directional blow throws the debris the right way.
func shatter(push: Vector3 = Vector3.ZERO) -> void:
	if _shattered:
		return
	_shattered = true

	if rng_seed != 0:
		_rng.seed = rng_seed
	else:
		var p := global_position
		_rng.seed = hash("%.2f|%.2f|%.2f" % [p.x, p.y, p.z])

	var root := _spawn_root()
	var wanted: int = mini(piece_count, DebrisPiece.budget_left())
	if root != null and wanted > 0:
		var mat := _surface_material()
		var extent := _extent()
		var size := Vector3.ONE * maxf(0.12, extent * piece_scale)
		for i in wanted:
			var dir := Vector3(
				_rng.randf_range(-1.0, 1.0),
				_rng.randf_range(0.25, 1.0),
				_rng.randf_range(-1.0, 1.0)).normalized()
			var vel := push + dir * _rng.randf_range(2.5, 6.5) + linear_velocity * 0.4
			var spin := Vector3(
				_rng.randf_range(-8.0, 8.0),
				_rng.randf_range(-8.0, 8.0),
				_rng.randf_range(-8.0, 8.0))
			DebrisPiece.spawn(root, global_position + dir * extent * 0.6, vel, size,
				mat, piece_lifetime, spin)

	AudioManager.play_boss_hit()
	queue_free()


func has_shattered() -> bool:
	return _shattered


# --- Internals --------------------------------------------------------------

## Half the prop's largest dimension, used for shard size and scatter radius.
func _extent() -> float:
	var s := _own_shape()
	if s is SphereShape3D:
		return (s as SphereShape3D).radius
	if s is BoxShape3D:
		var b := (s as BoxShape3D).size
		return maxf(b.x, maxf(b.y, b.z)) * 0.5
	if s is CylinderShape3D:
		var cyl := s as CylinderShape3D
		return maxf(cyl.radius, cyl.height * 0.5)
	if s is CapsuleShape3D:
		return (s as CapsuleShape3D).height * 0.5
	return 0.5


## Debris goes into the spawn root so main.gd's between-runs sweep collects it.
func _spawn_root() -> Node3D:
	var root := get_tree().get_first_node_in_group("spawn_root") as Node3D
	if root == null:
		root = get_parent() as Node3D
	return root
