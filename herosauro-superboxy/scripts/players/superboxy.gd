extends PlayerBase
## Super Boxy (Player 2): the nimble brawler in a green hoodie, denim overalls,
## red mask, cape and boxing gloves. His signature move is the Boxy Dash - a
## short, fast, gravity-defying lunge that bonks the boss for big combo damage.
##
## The visual is a Meshy-generated, web-optimized glTF model (assets/models),
## replacing the original code-built primitive toon.

const DASH_SPEED_MULT := 4.0
const DASH_DURATION := 0.25
const DASH_DAMAGE := 25
const DASH_HIT_RANGE := 5.0
const GHOST_INTERVAL := 0.06

const DashTrailScene: PackedScene = preload("res://scenes/fx/dash_trail.tscn")
const SuperBoxyModel: PackedScene = preload("res://assets/models/superboxy.glb")

const GLOVE_COLOR := Color(0.86, 0.12, 0.12)      # red

# Model orientation/scale to fit the CharacterBody3D (see _build_visuals).
const MODEL_YAW := PI / 2.0
const MODEL_SCALE := 0.89

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
	var model := SuperBoxyModel.instantiate()
	model.name = "SuperBoxyMesh"
	# The glTF model faces +Z; the player faces +X, so yaw it a quarter turn.
	model.rotation.y = MODEL_YAW
	# Meshy model is ~1.9 units tall; scale so the feet rest on the deck.
	model.scale = Vector3.ONE * MODEL_SCALE
	_model_root.add_child(model)


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


## Kept for the dash glove-flash. The Meshy model is a single textured mesh, so
## there are no separate glove materials to recolor yet; this is a safe no-op
## until per-region materials (or a rigged model) are added.
func _set_glove_albedo(color: Color) -> void:
	for mat in _glove_mats:
		mat.set_shader_parameter("albedo_color", color)
