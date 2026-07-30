extends Node
## Headless regression probe for two-player local co-op.
##
## Boots the real main scene and drives the parts of co-op that are easy to break
## from another stream and impossible to see in a screenshot: the roster, the two
## input sets landing on the right hero, the leash, the knockdown/revive loop and
## the solo fallback.
##
## Deliberately headless-safe — nothing here reads the framebuffer, so it runs in
## seconds on a machine with no GPU:
##
##   godot --headless --path . scripts/players/_coop_probe.tscn

const MainScene: PackedScene = preload("res://scenes/main.tscn")

var _pass: int = 0
var _fail: int = 0
var _main: Node = null


func _ready() -> void:
	await get_tree().process_frame
	await _run()
	print("\ncoop probe: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _run() -> void:
	await _check_input_map()
	await _check_coop_roster()
	await _check_input_routing()
	await _check_leash()
	await _check_framing()
	await _check_combat()
	await _check_knockdown_and_revive()
	await _check_solo_roster()


# --- Input map -------------------------------------------------------------

func _check_input_map() -> void:
	var actions := ["move_left", "move_right", "move_up", "move_down",
		"look_left", "look_right", "look_up", "look_down",
		"jump", "sprint", "attack", "ability"]
	var missing: Array[String] = []
	for a in actions:
		for slot in [1, 2]:
			var full := String(InputManager.action_name(slot, StringName(a)))
			if not InputMap.has_action(full):
				missing.append(full)
	_ok(missing.is_empty(), "both action sets exist (missing: %s)" % str(missing))

	# The whole point of the split: no pad event may sit on slot 1, or one stick
	# would drive both heroes.
	var pad_on_p1: Array[String] = []
	for a in actions:
		for ev in InputMap.action_get_events(StringName(a)):
			if ev is InputEventJoypadMotion or ev is InputEventJoypadButton:
				pad_on_p1.append(a)
	_ok(pad_on_p1.is_empty(), "no joypad binding on slot 1 (found: %s)" % str(pad_on_p1))

	# ...and slot 2 must be reachable from a pad AND from the keyboard, or a
	# pad-less couch cannot play co-op at all.
	var p2_pad := false
	var p2_key := false
	for ev in InputMap.action_get_events(&"p2_move_up"):
		p2_pad = p2_pad or ev is InputEventJoypadMotion
		p2_key = p2_key or ev is InputEventKey
	_ok(p2_pad and p2_key, "slot 2 reachable from a pad and from the keyboard")


# --- Roster ----------------------------------------------------------------

func _check_coop_roster() -> void:
	await _start(2, 1)
	var ids := _hero_ids()
	_ok(ids == [1, 2], "co-op spawns both heroes, got %s" % str(ids))
	_ok(_hero(1).get_class() == "CharacterBody3D" and _hero(2) != null,
		"both heroes are live bodies")
	var roster: Array[int] = GameManager.active_player_ids()
	_ok(roster == ([1, 2] as Array[int]), "active_player_ids() reports the co-op roster")


func _check_solo_roster() -> void:
	# Solo as hero 2 is the awkward case: the roster, the initial HUD sync and the
	# defeat test all used to assume hero 1 was the one that existed.
	await _to_menu()
	await _start(1, 2)
	var ids := _hero_ids()
	_ok(ids == [2], "solo as hero 2 spawns only Super Boxy, got %s" % str(ids))

	GameManager.damage_player(2, GameManager.MAX_PLAYER_HEALTH)
	await get_tree().physics_frame
	_ok(GameManager.state == GameManager.State.DEFEAT,
		"a lone hero at zero ends the run (state %d)" % GameManager.state)


# --- Input routing ---------------------------------------------------------

func _check_input_routing() -> void:
	await _to_menu()
	await _start(2, 1)
	# Long enough for both heroes to finish falling the 2 m from their spawn to
	# the deck, or the drop would be mistaken for movement.
	await _settle(60)

	var a: PlayerBase = _hero(1)
	var b: PlayerBase = _hero(2)
	var a0: Vector3 = a.global_position
	var b0: Vector3 = b.global_position

	Input.action_press(&"p2_move_up")
	await _settle(30)
	Input.action_release(&"p2_move_up")
	var a_moved := a0.distance_to(a.global_position)
	var b_moved := b0.distance_to(b.global_position)
	_ok(b_moved > 0.5, "p2_move_up moves hero 2 (%.2f m)" % b_moved)
	_ok(a_moved < 0.5, "p2_move_up leaves hero 1 alone (%.2f m)" % a_moved)

	a0 = a.global_position
	b0 = b.global_position
	Input.action_press(&"move_up")
	await _settle(30)
	Input.action_release(&"move_up")
	a_moved = a0.distance_to(a.global_position)
	b_moved = b0.distance_to(b.global_position)
	_ok(a_moved > 0.5, "move_up moves hero 1 (%.2f m)" % a_moved)
	_ok(b_moved < 0.5, "move_up leaves hero 2 alone (%.2f m)" % b_moved)


# --- Leash -----------------------------------------------------------------

func _check_leash() -> void:
	await _to_menu()
	await _start(2, 1)
	await _settle(60)

	var a: PlayerBase = _hero(1)
	var b: PlayerBase = _hero(2)
	# Shove them to opposite ends of the deck and let the clamp do its work.
	a.global_position = Vector3(-34.0, 3.0, 0.0)
	b.global_position = Vector3(30.0, 3.0, 0.0)
	# 64 m of gap reeled in at LEASH_REEL_SPEED from both ends takes ~1.2 s.
	await _settle(200)

	var gap: float = a.global_position.distance_to(b.global_position)
	var limit: float = PlayerBase.LEASH_RADIUS + PlayerBase.LEASH_SLACK
	_ok(gap <= limit + 0.5, "leash clamps separation to %.1f m, got %.1f" % [limit, gap])

	# ...and the camera can actually hold that much ground.
	var rig := get_tree().get_first_node_in_group("camera_rig")
	_ok(rig != null, "camera rig is in its group")
	if rig:
		_ok(float(rig.group_max_distance) > 0.0
			and limit < float(rig.group_max_distance) * 2.0,
			"leash limit (%.1f) sits inside what group_max_distance (%.1f) frames"
				% [limit, float(rig.group_max_distance)])


# --- Framing ---------------------------------------------------------------

## The claim the whole co-op camera rests on: neither hero can be pushed off
## screen. Measured by projecting each hero's head and feet through the live
## camera, not by eye, and checked both at spawn and stretched to the leash limit.
const SAFE_INSET := 0.04   ## fraction of the frame either edge that still counts as "off"


func _check_framing() -> void:
	await _to_menu()
	await _start(2, 1)
	await _settle(90)

	var rig := get_tree().get_first_node_in_group("camera_rig")
	_ok(rig != null and bool(rig.is_group_framing()),
		"two heroes put the rig into group framing")

	var m := _framing_margin(rig)
	_ok(m >= SAFE_INSET, "both heroes framed at spawn, worst margin %.3f of the frame" % m)
	_ok(_boss_head_framed(rig), "the giant's head is framed at spawn")

	# Now stretch them to the leash limit along the deck and across it, which is
	# the widest the frame can ever be asked to hold.
	var a: PlayerBase = _hero(1)
	var b: PlayerBase = _hero(2)
	var half: float = (PlayerBase.LEASH_RADIUS + PlayerBase.LEASH_SLACK) * 0.5
	a.global_position = Vector3(-half, 3.0, -4.0)
	b.global_position = Vector3(half, 3.0, 4.0)
	await _settle(120)
	m = _framing_margin(rig)
	_ok(m >= SAFE_INSET, "both heroes framed at full leash stretch, worst margin %.3f" % m)


## Smallest distance from any hero's head or feet to a frame edge, as a fraction
## of the frame. 0 means touching an edge, 0.5 would be dead centre. Negative
## means off screen. Measured through the live camera rather than by eye.
func _framing_margin(rig: Node) -> float:
	var cam: Camera3D = rig.camera
	var rect := cam.get_viewport().get_visible_rect().size
	var worst := 1.0
	for p in get_tree().get_nodes_in_group("players"):
		var body := p as Node3D
		for probe in [Vector3(0.0, 1.0, 0.0), Vector3(0.0, -1.0, 0.0)]:
			var world: Vector3 = body.global_position + probe
			if cam.is_position_behind(world):
				return -1.0
			var s := cam.unproject_position(world)
			worst = minf(worst, minf(s.x, rect.x - s.x) / rect.x)
			worst = minf(worst, minf(s.y, rect.y - s.y) / rect.y)
	return worst


## The giant is the third subject the shared frame has to hold. His origin is at
## his feet and he is nine metres tall, so it is the HEAD that decides the pitch.
func _boss_head_framed(rig: Node) -> bool:
	var boss := get_tree().get_first_node_in_group("boss") as Node3D
	if boss == null:
		return true
	var cam: Camera3D = rig.camera
	var rect := cam.get_viewport().get_visible_rect().size
	var head: Vector3 = boss.global_position + Vector3(0.0, 9.0, 0.0)
	if cam.is_position_behind(head):
		return false
	var s := cam.unproject_position(head)
	return s.y > 0.0 and s.y < rect.y and s.x > 0.0 and s.x < rect.x


# --- Combat ----------------------------------------------------------------

## BOTH heroes have to be able to hurt the giant off their own action set. The
## basic swing and the special go through different code paths (a Hitbox volume
## vs. a projectile / a dash proximity test) and both carry a source_player that
## used to be a hard-coded literal, so each of the four combinations is checked.
func _check_combat() -> void:
	await _to_menu()
	await _start(2, 1)
	await _settle(60)

	var boss := get_tree().get_first_node_in_group("boss") as Node3D
	_ok(boss != null, "the giant is in the arena")
	if boss == null:
		return

	# The camera is what tells a hero which way "forward" is, so in co-op that has
	# to resolve to "toward the giant" — otherwise pressing forward walks a player
	# away from the fight. Measured from the pair's MIDPOINT, which is what the rig
	# actually aims from, and at fighting distance rather than point-blank: with a
	# hero standing between the giant's feet the line to his origin is meaningless.
	var rig := get_tree().get_first_node_in_group("camera_rig")
	var cam: Camera3D = rig.camera
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	var mid: Vector3 = (_hero(1).global_position + _hero(2).global_position) * 0.5
	var to_boss: Vector3 = boss.global_position - mid
	to_boss.y = 0.0
	var dot := fwd.normalized().dot(to_boss.normalized())
	_ok(dot > 0.9, "camera forward points at the giant (dot %.2f)" % dot)

	for probe in [[1, &"attack", "hero 1's jab"], [2, &"p2_attack", "hero 2's jab"],
			[1, &"ability", "hero 1's Dino Energy"], [2, &"p2_ability", "hero 2's Boxy Dash"]]:
		var r: Dictionary = await _lands(int(probe[0]), probe[1])
		_ok(bool(r["hit"]), "%s damages the giant (%s)" % [probe[2], r["info"]])


## Put both heroes in front of the giant, then play the way a player does: hold
## forward and mash the action for two seconds. Reports whether the giant lost
## health, and the closest the attacker actually got.
##
## Holding forward is not padding. The giant's push-out volume is his body box
## plus 1.4 m and it shoves at 9 m/s, so a hero standing next to him is repeatedly
## launched to about 6.5 m from his origin — past both heroes' reach. Real melee
## against him is therefore a loop of "get shoved, walk back in, swing", and a
## probe that parks a hero and swings once is measuring the apex of the shove
## rather than the weapon.
func _lands(player: int, action: StringName) -> Dictionary:
	var boss := get_tree().get_first_node_in_group("boss") as Node3D
	var a: PlayerBase = _hero(1)
	var b: PlayerBase = _hero(2)
	a.global_position = boss.global_position + Vector3(-7.0, 1.0, -1.2)
	b.global_position = boss.global_position + Vector3(-7.0, 1.0, 1.2)
	await _settle(45)          # land, settle, and let the camera aim at the giant

	var who: PlayerBase = _hero(player)
	var forward: StringName = InputManager.action_name(player, &"move_up")
	var before: int = GameManager.boss_health
	var closest := 1e9

	Input.action_press(forward)
	for i in 24:
		Input.action_press(action)
		await _settle(4)
		Input.action_release(action)
		await _settle(4)
		var to_boss: Vector3 = boss.global_position - who.global_position
		to_boss.y = 0.0
		closest = minf(closest, to_boss.length())
	Input.action_release(forward)
	await _settle(60)          # the projectile still needs its flight time

	return {
		"hit": GameManager.boss_health < before,
		"info": "closed to %.1f m" % closest,
	}


# --- Knockdown / revive ----------------------------------------------------

func _check_knockdown_and_revive() -> void:
	await _to_menu()
	await _start(2, 1)
	await _settle(60)

	GameManager.damage_player(1, GameManager.MAX_PLAYER_HEALTH)
	await get_tree().physics_frame
	_ok(GameManager.state == GameManager.State.PLAYING,
		"one hero down does NOT end a co-op run (state %d)" % GameManager.state)
	_ok(_hero(1).is_downed(), "the hero at zero health is downed")
	_ok(not _hero(2).is_downed(), "the partner is still standing")

	# Ride out the revive timer. 90 Hz ticks, so this is DOWN_TIME plus slack.
	await _settle(int(PlayerBase.DOWN_TIME * 90.0) + 30)
	_ok(not _hero(1).is_downed(), "the downed hero is helped back up")
	_ok(int(GameManager.player_health[1]) > 0,
		"they come back with health (%d)" % int(GameManager.player_health[1]))
	var gap: float = _hero(1).global_position.distance_to(_hero(2).global_position)
	_ok(gap < PlayerBase.LEASH_RADIUS,
		"they come back next to their partner (%.1f m)" % gap)

	# Both down is defeat, and it has to be GameManager's own test that says so —
	# main.gd no longer carries a bridge for this.
	GameManager.damage_player(1, GameManager.MAX_PLAYER_HEALTH)
	GameManager.damage_player(2, GameManager.MAX_PLAYER_HEALTH)
	await get_tree().physics_frame
	_ok(GameManager.state == GameManager.State.DEFEAT,
		"both heroes down ends the run (state %d)" % GameManager.state)


# --- Harness ---------------------------------------------------------------

func _start(count: int, hero: int) -> void:
	if _main == null:
		_main = MainScene.instantiate()
		add_child(_main)
		await _settle(4)
	GameManager.set_player_count(count)
	GameManager.set_human_hero(hero)
	GameManager.start_game()
	await _settle(6)


func _to_menu() -> void:
	GameManager.go_to_menu()
	await _settle(4)


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


func _hero_ids() -> Array[int]:
	var out: Array[int] = []
	for p in get_tree().get_nodes_in_group("players"):
		out.append(int(p.player_id))
	out.sort()
	return out


func _hero(id: int) -> PlayerBase:
	for p in get_tree().get_nodes_in_group("players"):
		if p is PlayerBase and int(p.player_id) == id:
			return p as PlayerBase
	return null


func _ok(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("  ok   ", label)
	else:
		_fail += 1
		printerr("  FAIL ", label)
