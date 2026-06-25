extends RigidBody3D
## Dino Energy: Herosauro's signature projectile.
##
## A bright green energy orb that flies forward, damages the boss on contact and
## bursts on any impact. Spawned by Herosauro into the "spawn_root".

@export var speed: float = 20.0
@export var lifetime: float = 2.0
@export var damage: int = 50

const TRexModel: PackedScene = preload("res://assets/models/trex.glb")
const TREX_SCALE := 1.3
const TREX_YAW_OFFSET := 0.0   # model faces +Z; tweak if it flies tail-first

var direction: Vector3 = Vector3.RIGHT
var source_player: int = 1


func _ready() -> void:
	add_to_group("projectiles")
	gravity_scale = 0.0
	contact_monitor = true
	max_contacts_reported = 8
	lock_rotation = true
	collision_layer = 8          # player_projectiles
	collision_mask = 5           # world (1) + boss (4)

	_apply_visuals()

	linear_velocity = direction.normalized() * speed
	body_entered.connect(_on_body_entered)

	var timer := get_tree().create_timer(lifetime)
	timer.timeout.connect(_on_lifetime_timeout)


func _apply_visuals() -> void:
	# Hide the placeholder orb; the summoned green T-Rex spectrum is the visual.
	var orb := get_node_or_null("Mesh") as MeshInstance3D
	if orb:
		orb.visible = false

	var trex := TRexModel.instantiate()
	trex.scale = Vector3.ONE * TREX_SCALE
	# Aim the dino head-first along its flight direction (model faces +Z).
	trex.rotation.y = atan2(direction.x, direction.z) + TREX_YAW_OFFSET
	add_child(trex)

	var trail := get_node_or_null("Trail") as CPUParticles3D
	if trail:
		trail.emitting = true


func _on_lifetime_timeout() -> void:
	if is_instance_valid(self):
		_burst()
		queue_free()


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("boss"):
		GameManager.damage_boss(damage, source_player)
		AudioManager.play_dino_hit()
		GameManager.hit_stop(0.07)
		_burst()
		queue_free()
	elif not body.is_in_group("players"):
		_burst()
		queue_free()


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
		return
	root.add_child(burst)
	burst.global_position = pos

	# Free the burst node once its particles have finished.
	var t := burst.get_tree().create_timer(burst.lifetime + 0.2)
	t.timeout.connect(burst.queue_free)
