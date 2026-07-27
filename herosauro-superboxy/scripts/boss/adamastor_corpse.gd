class_name AdamastorCorpse
extends RigidBody3D
## The giant's body after the killing blow: a real dynamic rigid body that
## topples, hits the deck, slides and settles. It replaces a tween that faked a
## fall by rotating the model 82 degrees and sliding it sideways.
##
## Not a skeletal ragdoll, and the reason is recorded here so nobody has to
## rediscover it. The .glb does carry a usable 24-joint humanoid rig, and a
## PhysicalBone3D skeleton CAN be synthesised from its rest pose at runtime.
## Two things stopped it, both confirmed headless on 4.7.1:
##
##   1. A PhysicalBone3D only binds to a PhysicalBoneSimulator3D that is its
##      DIRECT parent. Nesting bones the way the editor's "Create Physical
##      Skeleton" does leaves every bone below the root with bone_id -1,
##      silently kinematic. Flattening them fixes the binding.
##   2. Even with all fourteen bodies bound, simulating and visibly moving, the
##      simulator never wrote its result back into the Skeleton3D — bone poses
##      stayed frozen at the rest pose for the whole run. A ragdoll whose mesh
##      does not follow it is worse than no ragdoll.
##
## So the giant dies as a felled statue: the model is handed to this body, which
## inherits the boss's momentum plus the direction of the killing blow and a
## topple spin, then falls under the same gravity as everything else. For a
## nine-metre STONE giant that arguably reads better than a floppy rag — and if
## it goes over near the parapet it really does roll off into the Douro.

## Camera shake is worth one big hit on landing, not one per contact.
const LAND_SHAKE := 0.7
const LAND_SHAKE_TIME := 0.6
## Once it has been still this long, freeze it out of the solver for good.
const SETTLE_TIME := 1.5
const CULL_Y := -20.0

var _model: Node3D = null
var _home: Node = null
var _home_transform: Transform3D = Transform3D.IDENTITY
var _landed: bool = false
var _still: float = 0.0


## Take `model` off `boss`, drop it into a fresh corpse at the boss's transform
## and shove it over. `body_size` / `body_centre_y` describe the collision box in
## the boss's own local space (its origin is at its feet).
static func topple(boss: Node3D, model: Node3D, body_size: Vector3, body_centre_y: float,
		inherited: Vector3, push: Vector3, spin: Vector3, corpse_mass: float) -> AdamastorCorpse:
	if boss == null or model == null:
		return null

	var corpse := AdamastorCorpse.new()
	corpse.name = "AdamastorCorpse"
	corpse.mass = corpse_mass
	corpse._model = model
	corpse._home = model.get_parent()
	corpse._home_transform = model.transform

	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = body_size
	col.shape = box
	col.position = Vector3(0.0, body_centre_y, 0.0)
	corpse.add_child(col)

	# Into the spawn root, not under the boss: the corpse has to outlive the
	# boss's own transform and keep falling wherever physics takes it.
	var root: Node = boss.get_tree().get_first_node_in_group("spawn_root")
	if root == null:
		root = boss.get_parent()
	if root == null:
		corpse.queue_free()
		return null
	root.add_child(corpse)
	corpse.global_transform = boss.global_transform

	if corpse._home != null:
		corpse._home.remove_child(model)
	corpse.add_child(model)
	model.transform = Transform3D.IDENTITY

	corpse.linear_velocity = inherited + push
	corpse.angular_velocity = spin
	return corpse


func _ready() -> void:
	collision_layer = PhysicsLayers.BOSS
	# World and props only. The fight is over; shoving the hero around with a
	# tumbling corpse is noise, but flattening the barrels on the way down is
	# exactly the punctuation the kill wants.
	collision_mask = PhysicsLayers.WORLD | PhysicsLayers.PROPS

	var pm := PhysicsMaterial.new()
	pm.friction = 0.95
	pm.bounce = 0.03
	physics_material_override = pm

	can_sleep = true
	continuous_cd = false
	# Heavy damping on purpose. Nine hundred kilos of granite should thud down
	# and stop; without it the box tumbles end over end and travels twenty
	# metres down the deck, because rolling never gets to spend the momentum on
	# friction the way sliding does.
	linear_damp = 0.5
	angular_damp = 0.4
	contact_monitor = true
	max_contacts_reported = 2
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	if global_position.y < CULL_Y:
		queue_free()
		return
	# Freeze rather than just letting it sleep: a nine-metre box resting on the
	# deck through the whole victory screen is a solver island we can hand back.
	if linear_velocity.length() < 0.4 and angular_velocity.length() < 0.4:
		_still += delta
		if _still > SETTLE_TIME:
			freeze = true
			set_physics_process(false)
	else:
		_still = 0.0


## Give the model back to the boss and remove the corpse. Called on Play Again.
func dismiss() -> void:
	if _model != null and is_instance_valid(_model) and _home != null and is_instance_valid(_home):
		remove_child(_model)
		_home.add_child(_model)
		_model.transform = _home_transform
	_model = null
	queue_free()


func _on_body_entered(_body: Node) -> void:
	if _landed:
		return
	_landed = true
	GameManager.request_shake(LAND_SHAKE, LAND_SHAKE_TIME)
	AudioManager.play_boss_slam()
