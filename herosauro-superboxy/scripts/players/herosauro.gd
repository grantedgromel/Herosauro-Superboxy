extends PlayerBase
## Herosauro (Player 1): the green dino-suit hero.
##
## A colourful low-poly toon model assembled in code and the Dino Energy
## projectile ability. Movement / jumping / combat all come from PlayerBase.

const DinoEnergyScene: PackedScene = preload("res://scenes/fx/dino_energy.tscn")


func _ready() -> void:
	super._ready()
	move_speed = 8.0
	jump_velocity = 13.0
	ability_cooldown = 2.0


func _build_visuals() -> void:
	# Colours.
	var green := Color(0.133, 0.545, 0.133)
	var skin := Color(0.96, 0.80, 0.62)
	var red := Color(0.85, 0.12, 0.12)
	var gold := Color(1.0, 0.84, 0.0)

	# Body: forest-green torso box, centred on origin.
	var body := MeshInstance3D.new()
	body.name = "Body"
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(1.0, 1.2, 0.8)
	body.mesh = body_mesh
	body.material_override = ToonFactory.solid(green)
	body.position = Vector3(0.0, 0.1, 0.0)
	_model_root.add_child(body)

	# Head: skin-tone box above the body.
	var head := MeshInstance3D.new()
	head.name = "Head"
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.7, 0.7, 0.7)
	head.mesh = head_mesh
	head.material_override = ToonFactory.solid(skin)
	head.position = Vector3(0.0, 1.05, 0.0)
	_model_root.add_child(head)

	# Red mask strip across the eyes, on the +X (forward) face of the head.
	var mask := MeshInstance3D.new()
	mask.name = "Mask"
	var mask_mesh := BoxMesh.new()
	mask_mesh.size = Vector3(0.12, 0.2, 0.74)
	mask.mesh = mask_mesh
	mask.material_override = ToonFactory.solid(red)
	mask.position = Vector3(0.30, 1.12, 0.0)
	_model_root.add_child(mask)

	# Red cape hanging behind the hero (-X) and trailing down.
	var cape := MeshInstance3D.new()
	cape.name = "Cape"
	var cape_mesh := BoxMesh.new()
	cape_mesh.size = Vector3(0.1, 1.3, 0.9)
	cape.mesh = cape_mesh
	cape.material_override = ToonFactory.solid(red)
	cape.position = Vector3(-0.55, 0.2, 0.0)
	cape.rotation = Vector3(0.0, 0.0, deg_to_rad(12.0))
	_model_root.add_child(cape)

	# Gold dino emblem disc on the chest (+X side).
	var emblem := MeshInstance3D.new()
	emblem.name = "Emblem"
	var emblem_mesh := SphereMesh.new()
	emblem_mesh.radius = 0.18
	emblem_mesh.height = 0.18
	emblem.mesh = emblem_mesh
	emblem.material_override = ToonFactory.glow(gold, 1.5)
	emblem.scale = Vector3(0.4, 1.0, 1.0)
	emblem.position = Vector3(0.42, 0.25, 0.0)
	_model_root.add_child(emblem)

	# Two skin-tone arms at the sides.
	for side in [-1.0, 1.0]:
		var arm := MeshInstance3D.new()
		arm.name = "Arm" + ("L" if side < 0.0 else "R")
		var arm_mesh := BoxMesh.new()
		arm_mesh.size = Vector3(0.3, 0.9, 0.3)
		arm.mesh = arm_mesh
		arm.material_override = ToonFactory.solid(green)
		arm.position = Vector3(0.0, 0.05, side * 0.65)
		_model_root.add_child(arm)


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
