extends PlayerBase
## Herosauro (Player 1): the green dino-suit hero. Taller, older brother to
## Super Boxy. His signature move is the Dino Energy projectile.
##
## The visual is a Meshy-generated, web-optimized glTF model (assets/models),
## replacing the original code-built primitive toon. Movement / jumping / combat
## all come from PlayerBase.

const DinoEnergyScene: PackedScene = preload("res://scenes/fx/dino_energy.tscn")
const HerosauroModel: PackedScene = preload("res://assets/models/herosauro.glb")

# Model orientation/scale to fit the CharacterBody3D (2.0u-tall collision box).
const MODEL_YAW := PI / 2.0
const MODEL_SCALE := 1.05


func _ready() -> void:
	super._ready()
	move_speed = 8.0
	jump_velocity = 13.0
	ability_cooldown = 2.0


func _build_visuals() -> void:
	var model := HerosauroModel.instantiate()
	model.name = "HerosauroMesh"
	# The glTF model faces +Z; the player faces +X, so yaw it a quarter turn.
	model.rotation.y = MODEL_YAW
	# Meshy model is ~1.9 units tall; scale so the feet rest on the deck.
	model.scale = Vector3.ONE * MODEL_SCALE
	_model_root.add_child(model)


func _perform_ability() -> void:
	var energy := DinoEnergyScene.instantiate()
	energy.direction = facing_dir
	energy.source_player = 1

	var root := get_tree().get_first_node_in_group("spawn_root")
	if root == null:
		root = get_tree().current_scene
	root.add_child(energy)
	energy.global_position = global_position + facing_dir * 1.6 + Vector3(0.0, 0.3, 0.0)

	AudioManager.play_dino_fire()
