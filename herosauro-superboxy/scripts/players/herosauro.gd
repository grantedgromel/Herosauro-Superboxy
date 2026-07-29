extends PlayerBase
## Herosauro: the green dino-suit hero and the one hero you play. His signature
## move is the Dino Energy projectile — he summons a green T-Rex spectrum to
## charge Adamastor, hadouken-style, down whatever line the camera is aiming.
##
## Visual is a Meshy-generated, RIGGED + ANIMATED glTF (walk / run / cast / jab),
## driven by PlayerBase's AnimationTree.

const DinoEnergyScene: PackedScene = preload("res://scenes/fx/dino_energy.tscn")
const HerosauroModel: PackedScene = preload("res://assets/models/herosauro.glb")

const MODEL_YAW := PI / 2.0     # model faces +Z; body yaw 0 faces +X (PlayerBase._face_movement)
const MODEL_SCALE := 1.0        # rigged model ~2u tall
const MODEL_Y := -1.0           # drop feet to the bottom of the 2.0u collision capsule


func _ready() -> void:
	super._ready()
	move_speed = 8.0
	jump_velocity = 13.0
	ability_cooldown = 2.0
	# Basic attack: a slower, heavier jab (his "cast" stays the big special).
	attack_cooldown = 0.55
	attack_damage = 10
	# Reach is now hero-centre to the far face of the swing volume, and has to
	# clear the giant's ~3.65 m push-out. Herosauro is the longer-reach hero.
	attack_range = 4.0
	attack_hold = 0.34


func _build_visuals() -> void:
	var model := HerosauroModel.instantiate()
	model.name = "HerosauroMesh"
	model.rotation.y = MODEL_YAW
	model.scale = Vector3.ONE * MODEL_SCALE
	model.position.y = MODEL_Y
	_model_root.add_child(model)
	# The GLB ships albedo only — no normal/roughness/metallic. Give it sane PBR
	# response and a normal map derived from the albedo so it isn't a flat decal
	# under Forward+ lighting.
	ToonFactory.upgrade_glb_materials(model)
	# "jab" matches the model's jab clip (the "Right Jab From Guard" animation);
	# "cast" is the Dino Energy summon. Substring match, so full names also resolve.
	# No "idle" key: the art has none, so PlayerBase synthesizes one from "walk".
	bind_animations(model, {"walk": "walk", "run": "run", "ability": "cast", "attack": "jab"})


func _perform_ability() -> void:
	play_action_anim("ability", 0.7)   # the T-Rex summon gesture

	var energy := DinoEnergyScene.instantiate()
	energy.direction = facing_dir
	energy.source_player = player_id
	var root := get_tree().get_first_node_in_group("spawn_root")
	if root == null:
		root = get_tree().current_scene
	root.add_child(energy)
	energy.global_position = global_position + facing_dir * 1.6 + Vector3(0.0, 0.3, 0.0)

	AudioManager.play_dino_fire()
