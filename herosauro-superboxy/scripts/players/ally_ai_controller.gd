class_name AllyController
extends RefCounted
## A lightweight "brain" that drives a hero as a CPU ally in 1-player mode.
##
## Mirrors the boss-FSM idiom: it is ticked once per physics frame via update(delta)
## and exposes the same intent surface PlayerBase reads for a human
## (get_move_vector / wants_jump / is_jump_held / wants_ability / wants_attack).
## PlayerBase's own cooldown gates mean the controller can hold intents true every
## frame; the hero only acts when the matching ability/attack is actually ready.
##
## Behaviour: close to a hero-specific standoff distance from the boss, always face
## it, fire the special when ready and in range, and throw basic attacks in melee.
## Herosauro hangs back and lobs Dino Energy; Super Boxy presses in to punch/dash.

var player: Node          # the PlayerBase this controller drives

var _move: Vector2 = Vector2.ZERO
var _ability: bool = false
var _attack: bool = false

# Hero-specific spacing / engagement ranges (set from player_id in _init).
var _standoff: float = 4.0
var _ability_range: float = 12.0
var _ability_min: float = 0.0
var _attack_reach: float = 3.0


func _init(p: Node) -> void:
	player = p
	if p.player_id == 1:
		# Herosauro: ranged. Hang back and fire the Dino Energy projectile.
		_standoff = 9.0
		_ability_range = 17.0
		_ability_min = 4.0
		_attack_reach = 3.0
	else:
		# Super Boxy: melee. Get in close to punch and dash.
		_standoff = 2.6
		_ability_range = 10.0
		_ability_min = 0.0
		_attack_reach = 2.8


func update(_delta: float) -> void:
	_move = Vector2.ZERO
	_ability = false
	_attack = false

	if player == null or not is_instance_valid(player):
		return
	var boss := player.get_tree().get_first_node_in_group("boss")
	if boss == null or not is_instance_valid(boss):
		return

	var to: Vector3 = (boss as Node3D).global_position - player.global_position
	to.y = 0.0
	var dist := to.length()
	var dir := to.normalized() if dist > 0.01 else Vector3.ZERO

	# Always face the boss so swings and the projectile aim true even when still.
	player.face_toward((boss as Node3D).global_position)

	# Close to standoff, then keep gentle forward pressure (stays facing the boss).
	if dist > _standoff:
		_move = Vector2(dir.x, dir.z)
	else:
		_move = Vector2(dir.x, dir.z) * 0.12

	# Special when off cooldown and within its useful band.
	if player.is_ability_ready() and dist <= _ability_range and dist >= _ability_min:
		_ability = true

	# Basic attack when in melee reach.
	if dist <= _attack_reach:
		_attack = true


# --- Intent surface (read by PlayerBase) -----------------------------------

func get_move_vector() -> Vector2:
	return _move

func wants_jump() -> bool:
	return false

func is_jump_held() -> bool:
	return false

func wants_ability() -> bool:
	return _ability

func wants_attack() -> bool:
	return _attack
