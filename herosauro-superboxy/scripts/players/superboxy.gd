extends PlayerBase
## Super Boxy (Player 2): the nimble brawler in a green hoodie, denim overalls,
## red mask, cape and boxing gloves. His signature move is the Boxy Dash — a
## short, fast, gravity-defying lunge that bonks the boss for big combo damage,
## throwing a punch as he connects.
##
## Visual is a Meshy-generated, RIGGED + ANIMATED glTF (walk / run / punch),
## driven by PlayerBase's animation driver.

const DASH_SPEED_MULT := 4.0
const DASH_DURATION := 0.25
const DASH_DAMAGE := 25
const DASH_HIT_RANGE := 5.0
const GHOST_INTERVAL := 0.06

const DashTrailScene: PackedScene = preload("res://scenes/fx/dash_trail.tscn")
const SuperBoxyModel: PackedScene = preload("res://assets/models/superboxy.glb")

const MODEL_YAW := PI / 2.0     # model faces +Z; player faces +X
const MODEL_SCALE := 0.85       # rigged model ~2u -> ~1.7u
const MODEL_Y := -0.85          # drop feet to the bottom of the 1.7u collision box

var _dash_time: float = 0.0
var _dash_dir: Vector3 = Vector3.ZERO
var _hit_boss: bool = false
var _ghost_accum: float = 0.0


func _ready() -> void:
	super._ready()
	move_speed = 8.0
	jump_velocity = 13.0
	ability_cooldown = 1.5
	# Basic attack: a fast, light standing jab (shares the punch clip with the dash).
	attack_cooldown = 0.38
	attack_damage = 7
	attack_range = 2.8
	attack_hold = 0.28


func _build_visuals() -> void:
	var model := SuperBoxyModel.instantiate()
	model.name = "SuperBoxyMesh"
	model.rotation.y = MODEL_YAW
	model.scale = Vector3.ONE * MODEL_SCALE
	model.position.y = MODEL_Y
	_model_root.add_child(model)
	# "punch" substring-matches the model's punch clip — baked as "punch1" (the
	# "Punch Combo 1" animation). Both the basic attack and the dash play it.
	bind_animations(model, {"walk": "walk", "run": "run", "idle": "walk", "ability": "punch", "attack": "punch"})


func _perform_ability() -> void:
	_dash_time = DASH_DURATION
	_dash_dir = facing_dir.normalized()
	_hit_boss = false
	_ghost_accum = 0.0
	AudioManager.play_dash()
	play_action_anim("ability", 0.5)   # throw a punch as he dashes in


func _custom_locomotion(delta: float) -> bool:
	if _dash_time > 0.0:
		_dash_time -= delta
		velocity = _dash_dir * move_speed * DASH_SPEED_MULT
		velocity.y = 0.0

		_ghost_accum += delta
		if _ghost_accum >= GHOST_INTERVAL:
			_ghost_accum -= GHOST_INTERVAL
			_spawn_ghost()

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
					Burst.hit(self, global_position + _dash_dir + Vector3(0.0, 1.4, 0.0), Color(1.0, 0.55, 0.32))
					_hit_boss = true
		return true
	return false


func _spawn_ghost() -> void:
	var ghost := DashTrailScene.instantiate()
	var root := get_tree().get_first_node_in_group("spawn_root")
	if root == null:
		root = get_tree().current_scene
	root.add_child(ghost)
	ghost.global_transform = global_transform
