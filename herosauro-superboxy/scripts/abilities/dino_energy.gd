extends ShapeCast3D
## Dino Energy: Herosauro's signature projectile — a summoned green T-Rex
## spectrum that charges Adamastor and bursts on any impact.
##
## Honestly kinematic. It used to be a RigidBody3D wearing gravity_scale = 0 and
## lock_rotation = true, which is a costume: it flew dead straight at a fixed
## speed, ignored gravity, and never responded to an impulse in its life, while
## still paying for a solver island every frame. It now integrates its own
## position and sweeps its shape across the frame's displacement instead.
##
## The sweep is not just tidiness. At 20 m/s and 90 Hz the orb moves 0.22 m a
## frame — fine today, but the moment anyone raises `speed` or drops the tick
## rate an overlap test starts missing the giant. A swept cast cannot tunnel at
## any speed, and it costs one shape query per frame instead of a rigid body.

@export var speed: float = 20.0
@export var lifetime: float = 2.0
@export var damage: int = 50

const TRexModel: PackedScene = preload("res://assets/models/trex.glb")
const TREX_SCALE := 1.3
const TREX_YAW_OFFSET := 0.0   # model faces +Z; tweak if it flies tail-first

var direction: Vector3 = Vector3.RIGHT
var source_player: int = 1

var _life: float = 0.0
var _spent: bool = false


func _ready() -> void:
	add_to_group("projectiles")
	collision_mask = PhysicsLayers.WORLD | PhysicsLayers.BOSS | PhysicsLayers.PROPS
	collide_with_bodies = true
	collide_with_areas = false
	enabled = true
	target_position = Vector3.ZERO
	_life = lifetime
	direction = direction.normalized()
	if direction.length() < 0.5:
		direction = Vector3.RIGHT
	_apply_visuals()


func _physics_process(delta: float) -> void:
	if _spent:
		return
	_life -= delta
	if _life <= 0.0:
		_finish()
		return

	# Sweep this frame's displacement, then commit to it only if nothing is in
	# the way. target_position is in local space and this node is never rotated,
	# so the step vector goes in as-is.
	var step := direction * speed * delta
	target_position = step
	force_shapecast_update()
	if is_colliding():
		_impact(get_collider(0) as Node3D)
		return
	global_position += step


func _impact(body: Node3D) -> void:
	if body == null:
		_finish()
		return
	if body.is_in_group("boss"):
		GameManager.damage_boss(damage, source_player)
		AudioManager.play_dino_hit()
		GameManager.hit_stop(0.07)
	elif body is PropBody:
		(body as PropBody).apply_hit_impulse(direction * 34.0 + Vector3.UP * 6.0, global_position)
	_finish()


func _finish() -> void:
	if _spent:
		return
	_spent = true
	_burst()
	queue_free()


func _apply_visuals() -> void:
	var trex := TRexModel.instantiate()
	trex.scale = Vector3.ONE * TREX_SCALE
	# Aim the dino head-first along its flight direction (model faces +Z).
	trex.rotation.y = atan2(direction.x, direction.z) + TREX_YAW_OFFSET
	add_child(trex)

	var trail := get_node_or_null("Trail") as CPUParticles3D
	if trail:
		trail.emitting = true


## Brief green particle pop, parented to the spawn root so it survives queue_free.
func _burst() -> void:
	var burst := CPUParticles3D.new()
	burst.emitting = true
	burst.one_shot = true
	burst.amount = 18
	burst.lifetime = 0.35
	burst.explosiveness = 1.0
	burst.spread = 180.0
	burst.initial_velocity_min = 4.0
	burst.initial_velocity_max = 8.0
	burst.scale_amount_min = 0.3
	burst.scale_amount_max = 0.6
	burst.direction = Vector3.UP
	burst.gravity = Vector3.ZERO

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.2, 1.0, 0.3, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 1.0, 0.3)
	mat.emission_energy_multiplier = 3.0
	burst.material_override = mat

	var pos := global_position
	var root := get_tree().get_first_node_in_group("spawn_root")
	if root == null:
		root = get_tree().current_scene
	if root == null:
		burst.queue_free()
		return
	root.add_child(burst)
	burst.global_position = pos

	# Free the burst node once its particles have finished.
	var t := burst.get_tree().create_timer(burst.lifetime + 0.2)
	t.timeout.connect(burst.queue_free)
