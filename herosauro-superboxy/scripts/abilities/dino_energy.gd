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
		# damage_boss makes Adamastor play its own hit reaction, and the shipped
		# dino_hit / boss_hit samples are the same file - playing both stacked two
		# identical buffers in one frame.
		GameManager.damage_boss(damage, source_player)
		GameManager.hit_stop(0.07)
	elif body is PropBody:
		(body as PropBody).apply_hit_impulse(direction * 34.0 + Vector3.UP * 6.0, global_position)
	# Leg two, on the HIT. Herosauro._perform_ability already punches the camera on
	# the CAST, which is right for the summon but is not this event - the orb
	# bursting on the giant fifteen metres away had no camera response at all, so a
	# 50-damage special landed with less weight in the frame than an 8-damage jab.
	# Fired for every impact, not just the boss: the orb bursting on a crate or on
	# the ironwork is still fifty points of energy stopping dead.
	GameManager.request_shake(0.22, 0.16)
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


## Leg one of the impact contract for the orb: the burst where it stops.
##
## This function DREW NOTHING from the day it was written until this pass. It
## built a `CPUParticles3D`, set eleven emission parameters and a bright green
## emissive `material_override` — and never set `mesh`. `CPUParticles3D` has no
## default particle mesh, so it dutifully simulated eighteen invisible particles
## and freed itself. The material_override is exactly what made it look
## implemented for this long: every line here read like a working effect.
##
## It is now the shared burst every impact in the game draws. `ImpactFX` is one
## MultiMesh draw call rather than a per-instance particle system, it is seeded
## off the impact position so two runs of the same fight agree (ARCHITECTURE.md
## rule 4), and it parents itself into the spawn root the same way this did.
##
## FLAT rather than the struck surface: the orb is a summoned spectrum coming
## apart, not the giant's granite chipping. The giant's own material shows up in
## the jab's burst, which uses `surface_of`. 1.6 because this is a 50-damage
## special — well above a jab's 1.0, below Boxy's dash at 2.0.
##
## Also covers the orb timing out in mid-air, which is the right read: the
## spectrum dissipating should be visible, and it was not.
func _burst() -> void:
	ImpactFX.spark(self, global_position, direction, ToonFactory.Surface.FLAT, 1.6)
