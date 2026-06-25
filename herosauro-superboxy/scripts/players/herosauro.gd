extends PlayerBase
## Herosauro (Player 1): the green dino-suit hero. Taller, older brother to
## Super Boxy. His signature move is the Dino Energy projectile — he summons a
## green T-Rex spectrum to charge Adamastor, hadouken-style.
##
## Visual is a Meshy-generated, RIGGED + ANIMATED glTF (walk / run / cast),
## driven by PlayerBase's animation driver.

const DinoEnergyScene: PackedScene = preload("res://scenes/fx/dino_energy.tscn")
const HerosauroModel: PackedScene = preload("res://assets/models/herosauro.glb")

const MODEL_YAW := PI / 2.0     # model faces +Z; player faces +X
const MODEL_SCALE := 1.0        # rigged model ~2u tall
const MODEL_Y := -1.0           # drop feet to the bottom of the 2.0u collision box


func _ready() -> void:
	super._ready()
	move_speed = 8.0
	jump_velocity = 13.0
	ability_cooldown = 2.0


func _build_visuals() -> void:
	var model := HerosauroModel.instantiate()
	model.name = "HerosauroMesh"
	model.rotation.y = MODEL_YAW
	model.scale = Vector3.ONE * MODEL_SCALE
	model.position.y = MODEL_Y
	_model_root.add_child(model)
	bind_animations(model, {"walk": "walk", "run": "run", "idle": "walk", "ability": "cast"})


func _perform_ability() -> void:
	play_action_anim("ability", 0.7)   # the T-Rex summon gesture

	var energy := DinoEnergyScene.instantiate()
	energy.direction = facing_dir
	energy.source_player = 1
	var root := get_tree().get_first_node_in_group("spawn_root")
	if root == null:
		root = get_tree().current_scene
	root.add_child(energy)
	energy.global_position = global_position + facing_dir * 1.6 + Vector3(0.0, 0.3, 0.0)

	AudioManager.play_dino_fire()
