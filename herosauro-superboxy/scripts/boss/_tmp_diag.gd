extends Node
const MainScene: PackedScene = preload("res://scenes/main.tscn")
var _main: Node = null
var _seen := {}

func _ready() -> void:
	await get_tree().process_frame
	await _start(2, 1)
	await _settle(60)
	var boss := get_tree().get_first_node_in_group("boss") as Node3D
	for round in 4:
		_seen.clear()
		var a := _hero(1); var b := _hero(2)
		a.global_position = boss.global_position + Vector3(-7.0, 1.0, -1.2)
		b.global_position = boss.global_position + Vector3(-7.0, 1.0, 1.2)
		await _settle(45)
		var before: int = GameManager.boss_health
		var spawns := 0
		var who: int = [1, 2, 1, 2][round]
		var act: StringName = [&"attack", &"p2_attack", &"ability", &"p2_ability"][round]
		var fwd: StringName = InputManager.action_name(who, &"move_up")
		Input.action_press(fwd)
		for i in 24:
			Input.action_press(act)
			await _watch(4)
			Input.action_release(act)
			await _watch(4)
		Input.action_release(fwd)
		await _watch(60)
		for k in _seen: spawns += 1
		print("round %d (%s): orbs=%d dmg=%d deaths=%s hp=%d/%d down=%s/%s abil1=%.2f" % [
			round, act, spawns, before - GameManager.boss_health, str(_seen.values()),
			GameManager.player_health[1], GameManager.player_health[2],
			_hero(1).is_downed(), _hero(2).is_downed(), _hero(1).get_ability_fraction()])
	get_tree().quit(0)

func _watch(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame
		var boss := get_tree().get_first_node_in_group("boss") as Node3D
		for p in get_tree().get_nodes_in_group("projectiles"):
			var n := p as Node3D
			if n == null or not is_instance_valid(n): continue
			var d: float = n.global_position.distance_to(boss.global_position)
			_seen[n.get_instance_id()] = "%.1f" % d

func _start(count: int, hero: int) -> void:
	if _main == null:
		_main = MainScene.instantiate(); add_child(_main); await _settle(4)
	GameManager.set_player_count(count); GameManager.set_human_hero(hero)
	GameManager.start_game(); await _settle(6)

func _settle(frames: int) -> void:
	for i in frames: await get_tree().physics_frame

func _hero(id: int) -> PlayerBase:
	for p in get_tree().get_nodes_in_group("players"):
		if p is PlayerBase and int(p.player_id) == id: return p
	return null
