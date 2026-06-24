extends PlayerBase
## Super Boxy (Player 2): the nimble brawler. A smaller lime-green boxer with
## red boxing gloves, mask and cape. His signature move is the Boxy Dash - a
## short, fast, gravity-defying lunge that bonks the boss for big combo damage.

const DASH_SPEED_MULT := 4.0
const DASH_DURATION := 0.25
const DASH_DAMAGE := 25
const DASH_HIT_RANGE := 5.0
const GHOST_INTERVAL := 0.06

const DashTrailScene: PackedScene = preload("res://scenes/fx/dash_trail.tscn")

const BODY_COLOR := Color(0.196, 0.804, 0.196)   # lime green
const SKIN_COLOR := Color(0.98, 0.80, 0.62)
const MASK_COLOR := Color(0.86, 0.12, 0.12)       # red
const GLOVE_COLOR := Color(0.86, 0.12, 0.12)      # red

var _dash_time: float = 0.0
var _dash_dir: Vector3 = Vector3.ZERO
var _hit_boss: bool = false
var _ghost_accum: float = 0.0

var _glove_mats: Array[ShaderMaterial] = []


func _ready() -> void:
	super._ready()
	move_speed = 8.0
	jump_velocity = 13.0
	ability_cooldown = 1.5


# --- Visuals ---------------------------------------------------------------

func _build_visuals() -> void:
	var body_mat := ToonFactory.solid(BODY_COLOR)
	var skin_mat := ToonFactory.solid(SKIN_COLOR)
	var mask_mat := ToonFactory.solid(MASK_COLOR)
	var cape_mat := ToonFactory.solid(Color(0.78, 0.10, 0.10))
	var white_mat := ToonFactory.solid(Color(0.95, 0.95, 0.95))

	# Body: a smaller, boxy torso centred on the origin.
	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(0.9, 1.1, 0.7)
	body.mesh = body_mesh
	body.material_override = body_mat
	body.position = Vector3(0.0, 0.0, 0.0)
	_model_root.add_child(body)

	# Head (skin).
	var head := MeshInstance3D.new()
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.55, 0.55, 0.55)
	head.mesh = head_mesh
	head.material_override = skin_mat
	head.position = Vector3(0.0, 0.85, 0.0)
	_model_root.add_child(head)

	# Red mask across the front of the head (+X face).
	var mask := MeshInstance3D.new()
	var mask_mesh := BoxMesh.new()
	mask_mesh.size = Vector3(0.12, 0.25, 0.58)
	mask.mesh = mask_mesh
	mask.material_override = mask_mat
	mask.position = Vector3(0.30, 0.92, 0.0)
	_model_root.add_child(mask)

	# Two red boxing-glove spheres on the sides (along Z). Keep refs for flash.
	var glove_l := MeshInstance3D.new()
	var glove_l_mesh := SphereMesh.new()
	glove_l_mesh.radius = 0.26
	glove_l_mesh.height = 0.52
	glove_l.mesh = glove_l_mesh
	var glove_l_mat := ToonFactory.solid(GLOVE_COLOR)
	glove_l.material_override = glove_l_mat
	glove_l.position = Vector3(0.15, -0.05, 0.55)
	_model_root.add_child(glove_l)
	_glove_mats.append(glove_l_mat)

	var glove_r := MeshInstance3D.new()
	var glove_r_mesh := SphereMesh.new()
	glove_r_mesh.radius = 0.26
	glove_r_mesh.height = 0.52
	glove_r.mesh = glove_r_mesh
	var glove_r_mat := ToonFactory.solid(GLOVE_COLOR)
	glove_r.material_override = glove_r_mat
	glove_r.position = Vector3(0.15, -0.05, -0.55)
	_model_root.add_child(glove_r)
	_glove_mats.append(glove_r_mat)

	# Red cape trailing behind (-X).
	var cape := MeshInstance3D.new()
	var cape_mesh := BoxMesh.new()
	cape_mesh.size = Vector3(0.08, 1.0, 0.65)
	cape.mesh = cape_mesh
	cape.material_override = cape_mat
	cape.position = Vector3(-0.45, 0.05, 0.0)
	_model_root.add_child(cape)

	# White chest label on the front (+X).
	var label := MeshInstance3D.new()
	var label_mesh := BoxMesh.new()
	label_mesh.size = Vector3(0.06, 0.4, 0.4)
	label.mesh = label_mesh
	label.material_override = white_mat
	label.position = Vector3(0.46, 0.05, 0.0)
	_model_root.add_child(label)

	# Small red circle on the chest label.
	var emblem := MeshInstance3D.new()
	var emblem_mesh := SphereMesh.new()
	emblem_mesh.radius = 0.11
	emblem_mesh.height = 0.22
	emblem.mesh = emblem_mesh
	emblem.material_override = ToonFactory.solid(MASK_COLOR)
	emblem.position = Vector3(0.50, 0.05, 0.0)
	emblem.scale = Vector3(0.4, 1.0, 1.0)
	_model_root.add_child(emblem)


# --- Ability: Boxy Dash ----------------------------------------------------

func _perform_ability() -> void:
	_dash_time = DASH_DURATION
	_dash_dir = facing_dir.normalized()
	_hit_boss = false
	_ghost_accum = 0.0
	AudioManager.play_dash()
	_set_glove_albedo(Color.YELLOW)


func _custom_locomotion(delta: float) -> bool:
	if _dash_time > 0.0:
		_dash_time -= delta
		velocity = _dash_dir * move_speed * DASH_SPEED_MULT
		velocity.y = 0.0

		# Spawn ghost trail every ~0.06s (about 4 over the dash).
		_ghost_accum += delta
		if _ghost_accum >= GHOST_INTERVAL:
			_ghost_accum -= GHOST_INTERVAL
			_spawn_ghost()

		# Bonk the boss once per dash if we pass close enough.
		if not _hit_boss:
			var boss := get_tree().get_first_node_in_group("boss")
			if boss:
				var here := global_position
				var there: Vector3 = boss.global_position
				var dx := here.x - there.x
				var dz := here.z - there.z
				if sqrt(dx * dx + dz * dz) < DASH_HIT_RANGE:
					GameManager.damage_boss(DASH_DAMAGE, 2)
					if boss.has_method("nudge"):
						boss.nudge(_dash_dir, 1.2)
					GameManager.hit_stop(0.06)
					_hit_boss = true

		if _dash_time <= 0.0:
			_set_glove_albedo(GLOVE_COLOR)
		return true
	return false


func _spawn_ghost() -> void:
	var ghost := DashTrailScene.instantiate()
	var root := get_tree().get_first_node_in_group("spawn_root")
	if root == null:
		root = get_tree().current_scene
	root.add_child(ghost)
	ghost.global_transform = global_transform


func _set_glove_albedo(color: Color) -> void:
	for mat in _glove_mats:
		mat.set_shader_parameter("albedo_color", color)
