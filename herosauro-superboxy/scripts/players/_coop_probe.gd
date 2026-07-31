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
	await _check_impact_contract()
	await _check_squash_reads()
	await _check_secondary_motion()
	await _check_downed_knockback()
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


# --- The five-part impact contract ------------------------------------------
#
# ARCHITECTURE.md, "Weight — every action": every hit, land, smash and spin needs
# a visual FX at the point of contact, a camera response, an audio transient, a
# hit-stop, and a UI acknowledgement. "A hit with three of the five feels broken
# and the critic will say so."
#
# Every leg below is measured through the mechanism that actually drives it, not
# by checking that a line of code exists:
#
#   1. visual   a NEW `ImpactFX` node appearing under the spawn root, and its
#               distance to where the contact actually was. A burst is not leg
#               one if it is drawn somewhere the blow did not land, so the
#               assertion is on the MISS, not on the count.
#   2. camera   `GameManager.camera_shake_requested`, counted and peaked.
#   3. audio    AudioManager's round-robin pool cursor. There is no "what did you
#               just play" API, and the cursor advancing is the only observable
#               "a sample was dispatched" the project offers. Same reading
#               `_props_probe` takes.
#   4. hit-stop the lowest `Engine.time_scale` seen across the window.
#               `GameManager.hit_stop` sets it synchronously and then awaits a
#               timer that ignores time scale, so a poll on the idle frame — which
#               keeps running at time_scale 0 — catches every freeze that lasts a
#               frame.
#   5. UI       the `player_damaged` / `boss_damaged` / `player_respawned`
#               signals the HUD is built on.
#
# The window is opened with `_open()`, which snapshots every burst already alive
# so another system's FX cannot be mistaken for ours, and takes a Callable that
# returns where the contact is EXPECTED to be — re-evaluated on every poll, so a
# moving attacker still gets a tight measurement.

## How far a burst may sit from the contact point and still count as being AT it.
## 1.5 m is a hero's own width; anything further out is drawn beside the impact
## rather than on it, which is the failure this is here to catch.
const FX_TOLERANCE := 1.5

var _watching: bool = false
var _shakes: int = 0
var _shake_peak: float = 0.0
var _freeze_low: float = 1.0
var _boss_hits: int = 0
var _hero_hits: int = 0
var _respawn_calls: int = 0
var _sfx_open: int = 0
var _seen_bursts: Dictionary = {}
var _new_bursts: int = 0
var _best_miss: float = INF
## Where every burst raised inside the window appeared. A single "closest to the
## anchor" number cannot describe an impact drawn in two places, which is exactly
## what going over the side is.
var _new_at: PackedVector3Array = PackedVector3Array()
var _anchor: Callable = Callable()
## Last live position of a hero's projectile, so a burst raised where an orb
## stopped can be attributed to the orb rather than to whatever else is on fire.
var _orb_seen: Vector3 = Vector3.ZERO
var _orb_live: bool = false


## Polled on the IDLE frame, not the physics frame: `Engine.time_scale = 0` stops
## the physics accumulator but the main loop keeps turning, so this is the only
## place a freeze can be observed from the outside without racing it.
func _process(_delta: float) -> void:
	if not _watching:
		return
	_freeze_low = minf(_freeze_low, Engine.time_scale)
	for p in get_tree().get_nodes_in_group("projectiles"):
		var n := p as Node3D
		if n != null:
			_orb_seen = n.global_position
			_orb_live = true
	for b in _live_bursts():
		var id: int = b.get_instance_id()
		if _seen_bursts.has(id):
			continue
		_seen_bursts[id] = true
		_new_bursts += 1
		_new_at.append(b.global_position)
		if _anchor.is_valid():
			_best_miss = minf(_best_miss, b.global_position.distance_to(_anchor.call() as Vector3))


func _live_bursts() -> Array[ImpactFX]:
	var out: Array[ImpactFX] = []
	var root := get_tree().get_first_node_in_group("spawn_root")
	if root == null:
		return out
	for c in root.get_children():
		if c is ImpactFX:
			out.append(c as ImpactFX)
	return out


## Open a measurement window. `anchor` returns where the contact is expected;
## pass an invalid Callable to count bursts without placing them.
func _open(anchor: Callable = Callable()) -> void:
	_seen_bursts.clear()
	for b in _live_bursts():
		_seen_bursts[b.get_instance_id()] = true
	_new_bursts = 0
	_best_miss = INF
	_new_at.clear()
	_anchor = anchor
	_shakes = 0
	_shake_peak = 0.0
	_freeze_low = 1.0
	_boss_hits = 0
	_hero_hits = 0
	_respawn_calls = 0
	_orb_live = false
	_sfx_open = _sfx_cursor()
	if not GameManager.camera_shake_requested.is_connected(_on_shake):
		GameManager.camera_shake_requested.connect(_on_shake)
		GameManager.boss_damaged.connect(_on_boss_damaged)
		GameManager.player_damaged.connect(_on_player_damaged)
		GameManager.player_respawned.connect(_on_player_respawned)
	_watching = true
	# One poll before anything is driven, so a burst raised on the very first
	# frame of the window is still measured against a fresh anchor.
	_process(0.0)


func _close() -> void:
	_watching = false
	_anchor = Callable()
	if GameManager.camera_shake_requested.is_connected(_on_shake):
		GameManager.camera_shake_requested.disconnect(_on_shake)
		GameManager.boss_damaged.disconnect(_on_boss_damaged)
		GameManager.player_damaged.disconnect(_on_player_damaged)
		GameManager.player_respawned.disconnect(_on_player_respawned)


func _on_shake(strength: float, _duration: float) -> void:
	_shakes += 1
	_shake_peak = maxf(_shake_peak, strength)


func _on_boss_damaged(amount: int, _health: int) -> void:
	if amount > 0:
		_boss_hits += 1


func _on_player_damaged(_id: int, amount: int, _health: int) -> void:
	if amount > 0:
		_hero_hits += 1


func _on_player_respawned(_id: int) -> void:
	_respawn_calls += 1


## AudioManager's round-robin cursor. See the block comment above for why this is
## the observable rather than a signal.
func _sfx_cursor() -> int:
	var am := get_node_or_null("/root/AudioManager")
	return int(am.get("_next_player")) if am != null else 0


func _sfx_since(before: int) -> int:
	var am := get_node_or_null("/root/AudioManager")
	if am == null:
		return 0
	var size: int = (am.get("_players") as Array).size()
	if size <= 0:
		return 0
	return (_sfx_cursor() - before + size) % size


## Let a hit-stop run out. Engine.time_scale is global, and a probe that measured
## through a freeze would measure the freeze.
func _thaw() -> void:
	for i in 900:
		await get_tree().physics_frame
		if Engine.time_scale >= 1.0:
			return
	Engine.time_scale = 1.0


## Bursts alive right now within `radius` of `at`. Used for the second beat of a
## fall, which is drawn after the body has already been moved.
func _bursts_near(at: Vector3, radius: float) -> int:
	var n := 0
	for b in _live_bursts():
		if b.global_position.distance_to(at) <= radius:
			n += 1
	return n


## Of the bursts raised inside the window, how far the closest one is from `at`.
## INF when the window raised none.
func _closest_new_to(at: Vector3) -> float:
	var best := INF
	for p in _new_at:
		best = minf(best, p.distance_to(at))
	return best


func _check_impact_contract() -> void:
	await _to_menu()
	await _start(2, 1)
	await _settle(60)
	await _jab_legs(1, &"attack", "Herosauro's jab")
	await _jab_legs(2, &"p2_attack", "Super Boxy's jab")
	await _dash_legs()
	await _orb_legs()
	await _landing_legs()
	await _take_hit_legs()
	await _fall_legs()


## Both heroes' basic swing. The most-repeated impact in the game, and the one
## that drew nothing at the point of contact.
func _jab_legs(id: int, action: StringName, label: String) -> void:
	var boss := get_tree().get_first_node_in_group("boss") as Node3D
	var who: PlayerBase = _hero(id)
	if boss == null or who == null:
		_ok(false, "%s: the arena has a giant and a hero" % label)
		return
	await _park_for_melee(boss)

	# The contact point `_on_swing_landed` draws at, re-evaluated every poll so a
	# hero being shoved around by the giant's push-out is still measured tightly.
	var anchor := func() -> Vector3:
		return who.global_position + who.facing_dir * who.attack_range * 0.55 + Vector3.UP

	var forward: StringName = InputManager.action_name(id, &"move_up")
	_open(anchor)
	Input.action_press(forward)
	var landed := false
	for i in 24:
		var before: int = GameManager.boss_health
		Input.action_press(action)
		await _settle(4)
		Input.action_release(action)
		await _settle(4)
		if GameManager.boss_health < before:
			landed = true
			break
	Input.action_release(forward)
	var sounds := _sfx_since(_sfx_open)
	var froze := _freeze_low
	_close()
	await _thaw()

	print("\n  -- %s connecting: %d new burst(s), closest %.2f m from the contact, "
		% [label, _new_bursts, _best_miss]
		+ "shake x%d peak %.2f, %d sample(s), time_scale low %.2f, %d boss damage event(s)"
			% [_shakes, _shake_peak, sounds, froze, _boss_hits])
	_ok(landed and _boss_hits > 0, "%s: leg 5/5 UI — boss_damaged fired" % label)
	_ok(_new_bursts > 0 and _best_miss <= FX_TOLERANCE,
		"%s: leg 1/5 visual — a burst at the contact (%.2f m off, tolerance %.1f)"
			% [label, _best_miss, FX_TOLERANCE])
	_ok(_shakes > 0 and _shake_peak > 0.0,
		"%s: leg 2/5 camera — %d request(s), peak %.2f" % [label, _shakes, _shake_peak])
	_ok(sounds > 0, "%s: leg 3/5 audio — %d sample(s) dispatched" % [label, sounds])
	_ok(froze < 1.0, "%s: leg 4/5 hit-stop — time_scale dipped to %.2f" % [label, froze])


## Super Boxy's dash connect: the pair's biggest single hit.
func _dash_legs() -> void:
	var boss := get_tree().get_first_node_in_group("boss") as Node3D
	var boxy: PlayerBase = _hero(2)
	if boss == null or boxy == null:
		_ok(false, "Boxy Dash: the arena has a giant and Super Boxy")
		return
	await _park_for_melee(boss)
	# _land_dash draws at DASH_FX_REACH along the dash, and the dash direction is
	# the facing at the moment the ability fired — which _aim_at_camera has pinned
	# for the whole lunge.
	var anchor := func() -> Vector3:
		return boxy.global_position + boxy.facing_dir * 1.6 + Vector3.UP

	var forward: StringName = InputManager.action_name(2, &"move_up")
	_open(anchor)
	Input.action_press(forward)
	var landed := false
	for i in 14:
		var before: int = GameManager.boss_health
		Input.action_press(&"p2_ability")
		await _settle(4)
		Input.action_release(&"p2_ability")
		await _settle(26)
		if GameManager.boss_health < before:
			landed = true
			break
	Input.action_release(forward)
	var sounds := _sfx_since(_sfx_open)
	var froze := _freeze_low
	_close()
	await _thaw()

	print("\n  -- Boxy Dash connecting: %d new burst(s), closest %.2f m, shake x%d peak %.2f, "
		% [_new_bursts, _best_miss, _shakes, _shake_peak]
		+ "%d sample(s), time_scale low %.2f" % [sounds, froze])
	_ok(landed and _boss_hits > 0, "Boxy Dash: leg 5/5 UI — boss_damaged fired")
	_ok(_new_bursts > 0 and _best_miss <= FX_TOLERANCE + 0.5,
		"Boxy Dash: leg 1/5 visual — a burst at the connect (%.2f m off)" % _best_miss)
	# The dash is the biggest thing either hero does, so its punch has to be the
	# biggest a hero asks for: well above the jab's 0.16.
	_ok(_shakes > 0 and _shake_peak >= 0.4,
		"Boxy Dash: leg 2/5 camera — peak %.2f over %d request(s), above a jab's 0.16"
			% [_shake_peak, _shakes])
	_ok(sounds > 0, "Boxy Dash: leg 3/5 audio — %d sample(s)" % sounds)
	_ok(froze < 1.0, "Boxy Dash: leg 4/5 hit-stop — time_scale dipped to %.2f" % froze)


## Dino Energy. `_burst()` built a CPUParticles3D with no `mesh` and therefore
## drew NOTHING from the day it was written; this is the assertion that says so
## if it ever regresses. Anchored on the orb's own last live position rather than
## on the giant, so the burst has to be where the orb stopped.
func _orb_legs() -> void:
	var boss := get_tree().get_first_node_in_group("boss") as Node3D
	var hero: PlayerBase = _hero(1)
	if boss == null or hero == null:
		_ok(false, "Dino Energy: the arena has a giant and Herosauro")
		return
	await _park_for_melee(boss)
	var anchor := func() -> Vector3: return _orb_seen

	var forward: StringName = InputManager.action_name(1, &"move_up")
	_open(anchor)
	Input.action_press(forward)
	var landed := false
	for i in 12:
		var before: int = GameManager.boss_health
		Input.action_press(&"ability")
		await _settle(4)
		Input.action_release(&"ability")
		await _settle(40)      # flight time, then the burst
		if GameManager.boss_health < before:
			landed = true
			break
	Input.action_release(forward)
	var sounds := _sfx_since(_sfx_open)
	var froze := _freeze_low
	var saw_orb := _orb_live
	_close()
	await _thaw()

	print("\n  -- Dino Energy bursting: %d new burst(s), closest %.2f m from where the orb "
		% [_new_bursts, _best_miss]
		+ "was last seen, shake x%d peak %.2f, %d sample(s), time_scale low %.2f"
			% [_shakes, _shake_peak, sounds, froze])
	_ok(saw_orb, "Dino Energy: the orb existed")
	_ok(landed and _boss_hits > 0, "Dino Energy: leg 5/5 UI — boss_damaged fired")
	_ok(_new_bursts > 0 and _best_miss <= 2.5,
		"Dino Energy: leg 1/5 visual — a burst where the orb stopped (%.2f m off)" % _best_miss)
	_ok(_shakes > 0, "Dino Energy: leg 2/5 camera — %d request(s) incl. one on the HIT"
		% _shakes)
	_ok(sounds > 0, "Dino Energy: leg 3/5 audio — %d sample(s)" % sounds)
	_ok(froze < 1.0, "Dino Energy: leg 4/5 hit-stop — time_scale dipped to %.2f" % froze)


## A hero arriving on the deck from a real drop.
##
## Three legs, not five, and that is the design rather than a gap: nothing is
## damaged by a landing, so there is no UI acknowledgement to make and no reason
## to stop the game. The freeze is asserted to STAY at 1.0 for exactly that
## reason — a landing that hit-stops would make walking off a kerb feel like a
## hit, which is the opposite failure.
func _landing_legs() -> void:
	var hero: PlayerBase = _hero(1)
	var mate: PlayerBase = _hero(2)
	if hero == null:
		_ok(false, "landing: Herosauro is in the arena")
		return
	# Both heroes together and well clear of the giant, so the leash cannot drag
	# the faller sideways and the boss cannot be the thing raising the burst.
	await _send_boss_away()
	hero.global_position = Vector3(-26.0, 3.0, 0.0)
	if mate:
		mate.global_position = Vector3(-24.0, 3.0, 0.0)
	await _settle(50)
	var deck := hero.global_position

	var anchor := func() -> Vector3: return hero.foot_position()
	await _thaw()          # start from a clean clock, or the first read is stale
	_open(anchor)
	hero.global_position = deck + Vector3.UP * 14.0
	hero.velocity = Vector3.ZERO
	# The clock is read at the TOUCHDOWN FRAME rather than as a low-water mark over
	# the whole drop. `Engine.time_scale` is global: over 1.4 s of arena a prop
	# somewhere else can shatter and freeze the game, and that freeze is not this
	# landing's. Breaking on the frame `is_on_floor()` first comes back true reads
	# the clock while `_handle_landing`'s own effects are the newest thing that
	# happened.
	var froze := 1.0
	var touched := false
	for i in 220:
		await get_tree().physics_frame
		if hero.is_on_floor() and hero.global_position.y < deck.y + 1.0:
			froze = Engine.time_scale
			touched = true
			break
	await _settle(20)      # let the burst reach an idle frame to be counted on
	var sounds := _sfx_since(_sfx_open)
	_close()

	print("\n  -- a 14 m drop onto the deck: %d new burst(s), closest %.2f m from the soles, "
		% [_new_bursts, _best_miss]
		+ "shake x%d peak %.2f, %d sample(s), time_scale at touchdown %.2f"
			% [_shakes, _shake_peak, sounds, froze])
	_ok(touched, "landing: the hero came down")
	_ok(_new_bursts > 0 and _best_miss <= FX_TOLERANCE,
		"landing: leg 1/5 visual — a ground burst under the soles (%.2f m off)" % _best_miss)
	_ok(_shakes > 0 and _shake_peak > 0.0,
		"landing: leg 2/5 camera — %d request(s), peak %.2f" % [_shakes, _shake_peak])
	_ok(sounds > 0, "landing: leg 3/5 audio — %d sample(s)" % sounds)
	_ok(is_equal_approx(froze, 1.0),
		"landing: does NOT hit-stop the game (time_scale at touchdown %.2f)" % froze)


## A hero taking a hit. Driven through `take_hit` itself, because that is what
## every damage source in the game calls — the slam hitbox, the giant's body
## contact, the shockwave and a thrown rock all arrive here.
func _take_hit_legs() -> void:
	var hero: PlayerBase = _hero(1)
	if hero == null:
		_ok(false, "take_hit: Herosauro is in the arena")
		return
	await _send_boss_away()
	hero.global_position = Vector3(-26.0, 3.0, 0.0)
	await _settle(50)
	# Clear the i-frames the previous section may have left on him.
	for i in 200:
		if not hero.is_invulnerable():
			break
		await get_tree().physics_frame

	var blow := Vector3(1.0, 0.0, 0.0)
	var anchor := func() -> Vector3:
		return hero.global_position - blow * 0.45 + Vector3.UP * 0.35
	_open(anchor)
	var accepted: bool = hero.take_hit(14, blow * 8.0 + Vector3.UP * 6.0)
	# Read synchronously, the way _props_probe does: hit_stop sets the clock and
	# only then awaits its own timer, and ImpactFX.spark adds its node in the same
	# call, so everything is already observable here.
	_process(0.0)
	var froze := _freeze_low
	var sounds := _sfx_since(_sfx_open)
	var hits := _hero_hits
	_close()
	await _thaw()

	print("\n  -- a 14-damage hit on a hero: %d new burst(s), closest %.2f m, shake x%d "
		% [_new_bursts, _best_miss, _shakes]
		+ "peak %.2f, %d sample(s), time_scale %.2f, %d player_damaged event(s)"
			% [_shake_peak, sounds, froze, hits])
	_ok(accepted, "take_hit: the blow was accepted")
	_ok(_new_bursts > 0 and _best_miss <= FX_TOLERANCE,
		"take_hit: leg 1/5 visual — a burst on the struck side (%.2f m off)" % _best_miss)
	_ok(_shakes > 0 and _shake_peak > 0.0,
		"take_hit: leg 2/5 camera — peak %.2f" % _shake_peak)
	_ok(sounds > 0, "take_hit: leg 3/5 audio — %d sample(s)" % sounds)
	_ok(froze < 1.0, "take_hit: leg 4/5 hit-stop — time_scale dropped to %.2f" % froze)
	_ok(hits > 0, "take_hit: leg 5/5 UI — player_damaged fired")
	# The anchor of the whole freeze scale: the heaviest blow in the fight must
	# still get the freeze the boss stream tuned for it.
	var slam: float = float(PlayerBase.HURT_STOP_PER_DAMAGE) * 18.0
	_ok(is_equal_approx(snappedf(slam, 0.001), 0.09),
		"take_hit: 18 damage (a slam) still freezes for %.3f s" % slam)


## Going over the side of the Dom Luís — the worst-rated impact in the game
## before this pass, at one leg out of five.
##
## Driven the real way: put the hero out past the deck with nothing under them
## and let `_handle_fall` find it.
func _fall_legs() -> void:
	var hero: PlayerBase = _hero(1)
	var mate: PlayerBase = _hero(2)
	if hero == null or mate == null:
		_ok(false, "the fall: both heroes are in the arena")
		return
	await _send_boss_away()
	mate.global_position = Vector3(-20.0, 3.0, 0.0)
	hero.global_position = Vector3(-20.0, 3.0, 2.0)
	await _settle(60)
	for i in 200:
		if not hero.is_invulnerable():
			break
		await get_tree().physics_frame
	var health_before: int = int(GameManager.player_health[1])

	# Off the side and below the kill depth, with nothing under them. z is far
	# outside BridgeArena.ROADWAY_HALF and the Douro has no collider. Held as a
	# constant because it is what the LOSS beat has to be drawn at, and the hero is
	# already back on the deck by the time anything can be read off them.
	var over_the_side := Vector3(-20.0, -6.0, 46.0)
	# No tracking anchor here: the two beats are drawn 50 m apart inside one call,
	# and a single "closest to the hero" number would silently report the return
	# burst as if it were the loss. Both are measured against their own place.
	_open()
	hero.global_position = over_the_side
	hero.velocity = Vector3(0.0, -4.0, 0.0)
	await _settle(6)
	var loss_bursts := _new_bursts
	var loss_miss := _closest_new_to(over_the_side)
	var froze := _freeze_low
	var sounds := _sfx_since(_sfx_open)
	var respawned := _respawn_calls
	var hits := _hero_hits
	var shakes := _shakes
	var peak := _shake_peak
	# The return beat is drawn after the body has already been moved, so it is
	# measured where the hero ended up.
	var return_miss := _closest_new_to(hero.foot_position() - Vector3.UP * 1.0)
	var returned := _bursts_near(hero.foot_position(), 2.5)
	_close()
	await _thaw()

	print("\n  -- going over the side: %d new burst(s) (%.2f m from where they went over, "
		% [loss_bursts, loss_miss]
		+ "%.2f m from where they came back, %d alive on the deck), shake x%d peak %.2f, "
			% [return_miss, returned, shakes, peak]
		+ "%d sample(s), time_scale %.2f, %d damage event(s), %d respawn signal(s)"
			% [sounds, froze, hits, respawned])
	_ok(respawned > 0, "the fall: the hero actually went over (player_respawned fired)")
	_ok(loss_bursts >= 2,
		"the fall: leg 1/5 visual — %d bursts, one for the loss and one for the return"
			% loss_bursts)
	_ok(loss_miss <= 3.0,
		"the fall: leg 1/5 visual — the loss is drawn out over the river where they went "
			+ "over (%.2f m off)" % loss_miss)
	_ok(return_miss <= 2.0,
		"the fall: leg 1/5 visual — the return is drawn under their soles (%.2f m off)"
			% return_miss)
	_ok(returned > 0,
		"the fall: leg 1/5 visual — the return is drawn on the deck they land on")
	_ok(shakes >= 2 and peak >= PlayerBase.RECOVER_SHAKE,
		"the fall: leg 2/5 camera — %d request(s), peak %.2f (the loss punches harder "
			% [shakes, peak] + "than the recovery)")
	_ok(sounds >= 2, "the fall: leg 3/5 audio — %d sample(s), the fall and the landing"
		% sounds)
	_ok(froze < 1.0, "the fall: leg 4/5 hit-stop — time_scale dropped to %.2f" % froze)
	_ok(hits > 0 and int(GameManager.player_health[1]) < health_before,
		"the fall: leg 5/5 UI — player_damaged fired, %d -> %d health"
			% [health_before, int(GameManager.player_health[1])])


## Walk the giant to the far end of the deck.
##
## Not cosmetic. Three of the measurements below are about what a HERO does on
## their own, and a nine-metre giant standing next to them poisons all of them:
## his slam fires `SLAM_GROUND_STOP` whether or not it catches anybody, so a
## landing that must be shown NOT to freeze the game would flake; his shockwave
## raises its own `ImpactFX` at his feet, which is a burst the FX attribution
## would have to tell apart from the hero's; and his positional push-out moves a
## downed body, which is exactly the thing `_check_downed_knockback` is measuring
## the absence of. Eighty metres is further than he can close inside any window
## here.
func _send_boss_away() -> void:
	var boss := get_tree().get_first_node_in_group("boss") as Node3D
	if boss == null:
		return
	boss.global_position = Vector3(60.0, boss.global_position.y, 0.0)
	await _settle(4)


## Put both heroes in front of the giant and let them settle. Same staging
## `_lands()` uses, and for the same reason: the giant's push-out launches a hero
## to about 6.5 m, so melee against him is a loop of get shoved, walk in, swing.
func _park_for_melee(boss: Node3D) -> void:
	var a: PlayerBase = _hero(1)
	var b: PlayerBase = _hero(2)
	if a:
		a.global_position = boss.global_position + Vector3(-7.0, 1.0, -1.2)
	if b:
		b.global_position = boss.global_position + Vector3(-7.0, 1.0, 1.2)
	await _settle(45)


# --- Squash and stretch ------------------------------------------------------

## The rubric scores a character that translates without deforming as a prop
## being slid around, so it is not enough for the squash to exist — it has to
## reach the mesh at an amplitude the eye reads from the co-op camera.
##
## Measured off `PlayerBase.stretch()`, which is exactly what is written into the
## model's scale, sampled every physics frame across a real jump, a real landing
## and a real swing. The thresholds are the point of the test: they are set just
## under the design amplitude of each beat, so a constant being quietly halved
## fails here instead of shipping.
const READS_JUMP := 0.20
const READS_LAND := 0.24
const READS_ATTACK := 0.17


func _check_squash_reads() -> void:
	await _to_menu()
	await _start(2, 1)
	await _settle(60)
	await _send_boss_away()
	var hero: PlayerBase = _hero(1)
	var mate: PlayerBase = _hero(2)
	hero.global_position = Vector3(-26.0, 3.0, 0.0)
	if mate:
		mate.global_position = Vector3(-24.0, 3.0, 0.0)
	await _settle(50)

	# A jump: the body elongates as it leaves the deck.
	Input.action_press(&"jump")
	var up := await _peak_stretch(hero, 10, true)
	Input.action_release(&"jump")
	await _settle(90)
	_ok(up >= READS_JUMP,
		"jump anticipation reads: peak stretch %.3f (>= %.2f)" % [up, READS_JUMP])

	# A landing off a real drop.
	var deck := hero.global_position
	hero.global_position = deck + Vector3.UP * 14.0
	hero.velocity = Vector3.ZERO
	var down := await _peak_stretch(hero, 140, false)
	_ok(down >= READS_LAND,
		"landing compression reads: peak squash %.3f (>= %.2f)" % [down, READS_LAND])

	# A swing, with nothing to hit: this is the anticipation and the
	# follow-through on their own, which is the pair the rubric names.
	await _settle(40)
	Input.action_press(&"attack")
	var swing := await _peak_stretch(hero, 6, false)
	Input.action_release(&"attack")
	var follow := await _peak_stretch(hero, 40, true)
	await _settle(40)
	print("\n  -- squash amplitudes reaching the mesh: jump +%.3f, land -%.3f, "
		% [up, down] + "swing coil -%.3f, follow-through +%.3f" % [swing, follow])
	_ok(swing >= READS_ATTACK,
		"attack anticipation reads: peak coil %.3f (>= %.2f)" % [swing, READS_ATTACK])
	_ok(follow > 0.0, "attack follow-through reads: peak extension %.3f" % follow)


## Sample `stretch()` every physics frame for `frames` and report the largest
## excursion in the requested direction, unsigned.
func _peak_stretch(hero: PlayerBase, frames: int, want_up: bool) -> float:
	var peak := 0.0
	for i in frames:
		await get_tree().physics_frame
		var s: float = hero.stretch()
		peak = maxf(peak, s if want_up else -s)
	return peak


# --- Secondary motion --------------------------------------------------------

## The rubric's "nothing on a character is perfectly rigid" line, asserted.
##
## `BodyLag` is a `SkeletonModifier3D`, so what it writes is overwritten by the
## AnimationMixer on the next frame and cannot be differenced from outside the
## skeleton. The spring it writes FROM can be, and that is the thing with the
## interesting properties: it has to find its bones on the shipped rig, it has to
## respond to a hero launching, it has to stay inside its bound however violently
## it is driven, and — the one that protects every capture in the project — it
## has to return to EXACTLY zero when the hero stops, so an idle frame is
## bit-for-bit what it was before the modifier existed.
func _check_secondary_motion() -> void:
	await _to_menu()
	await _start(2, 1)
	await _settle(60)
	await _send_boss_away()
	var hero: PlayerBase = _hero(1)
	var boxy: PlayerBase = _hero(2)
	hero.global_position = Vector3(-26.0, 3.0, 0.0)
	boxy.global_position = Vector3(-24.0, 3.0, 0.0)
	await _settle(60)

	var lag: BodyLag = hero.body_lag()
	var boxy_lag: BodyLag = boxy.body_lag()
	_ok(lag != null and boxy_lag != null, "both heroes carry a BodyLag modifier")
	if lag == null or boxy_lag == null:
		return
	_ok(lag.bound_bone_count() == BodyLag.CHAIN.size()
			and boxy_lag.bound_bone_count() == BodyLag.CHAIN.size(),
		"the modifier found its whole chain on the shipped rig (%d / %d bones)"
			% [lag.bound_bone_count(), BodyLag.CHAIN.size()])

	# At rest it must be exactly neutral, not merely small.
	_ok(is_zero_approx(lag.lean_angle()) and is_zero_approx(lag.twist_angle()),
		"a standing hero's chain is at exactly neutral (lean %.5f, twist %.5f)"
			% [lag.lean_angle(), lag.twist_angle()])

	# Drive it the way the game does: run, which is `ground_accel` = 55 m/s^2.
	var peak_lean := 0.0
	Input.action_press(&"move_up")
	for i in 40:
		await get_tree().physics_frame
		peak_lean = maxf(peak_lean, lag.lean_angle())
	Input.action_release(&"move_up")
	_ok(peak_lean > 0.01,
		"launching into a run swings the chain (peak lean %.3f rad)" % peak_lean)
	_ok(peak_lean <= BodyLag.MAX_LEAN + 0.001,
		"...and never past its bound (%.3f <= %.2f rad)" % [peak_lean, BodyLag.MAX_LEAN])

	# Boxy's dash is the most violent input in the game: it sets velocity to
	# 32 m/s in one tick, and `_aim_at_camera` snaps the yaw on the same frame.
	var peak_dash := 0.0
	var peak_twist := 0.0
	var peak_written := 0.0
	Input.action_press(&"p2_ability")
	await get_tree().physics_frame
	Input.action_release(&"p2_ability")
	for i in 60:
		await get_tree().physics_frame
		peak_dash = maxf(peak_dash, boxy_lag.lean_angle())
		peak_twist = maxf(peak_twist, boxy_lag.twist_angle())
		peak_written = maxf(peak_written, boxy_lag.written_angle())
	print("\n  -- secondary motion: a run peaks the chain at %.3f rad, "
		% peak_lean
		+ "the Boxy Dash at %.3f rad with %.3f rad of twist (caps %.2f / %.2f); "
			% [peak_dash, peak_twist, BodyLag.MAX_LEAN, BodyLag.MAX_TWIST]
		+ "the largest rotation that reached a bone was %.4f rad" % peak_written)
	# The one that says the modifier is not writing into thin air: measured by
	# reading the pose back off the skeleton, inside the modifier, after the write.
	_ok(peak_written > 0.0,
		"the lag actually reaches the skeleton (largest bone move %.4f rad)" % peak_written)
	_ok(peak_dash <= BodyLag.MAX_LEAN + 0.001 and peak_twist <= BodyLag.MAX_TWIST + 0.001,
		"the dash cannot drive the chain past its bound (%.3f / %.3f rad)"
			% [peak_dash, peak_twist])
	_ok(peak_dash > peak_lean,
		"...and the dash swings it harder than a run does (%.3f > %.3f)"
			% [peak_dash, peak_lean])

	# And back to exactly zero. Not "small" — zero, or every idle frame in every
	# capture in the project moves the first time a hero has ever run.
	await _settle(120)
	_ok(is_zero_approx(lag.lean_angle()) and is_zero_approx(lag.twist_angle())
			and is_zero_approx(boxy_lag.lean_angle())
			and is_zero_approx(boxy_lag.twist_angle()),
		"a hero who stops settles back to EXACTLY neutral (%.5f / %.5f rad)"
			% [lag.lean_angle(), boxy_lag.lean_angle()])
	_ok(is_zero_approx(lag.written_angle()) and is_zero_approx(boxy_lag.written_angle()),
		"...and writes nothing at all into the pose while neutral, so an idle "
			+ "frame is what it was before the modifier existed")


# --- Downed heroes do not slide ---------------------------------------------

## `_process_downed` drives velocity.x/z to zero every frame, so `apply_knockback`
## on a downed hero is a no-op. That is INTENDED — a downed hero who slides reads
## as a dropped ragdoll, and one blown off the deck by a wave they cannot dodge
## turns a knockdown into a second death sentence — and it is documented at the
## drop in `_process_downed` and on `apply_knockback` itself.
##
## It is asserted here because it is invisible from the calling side: a system
## that shoves a hero and finds nothing happened has no way to tell whether it is
## looking at a design decision or at a bug, and the boss stream already spent a
## pass working around it.
func _check_downed_knockback() -> void:
	await _to_menu()
	await _start(2, 1)
	await _settle(60)
	await _send_boss_away()
	var hero: PlayerBase = _hero(1)
	var mate: PlayerBase = _hero(2)
	hero.global_position = Vector3(-26.0, 3.0, 0.0)
	mate.global_position = Vector3(-24.0, 3.0, 0.0)
	await _settle(50)

	# Standing: the same impulse must MOVE them, or this proves nothing.
	var from := hero.global_position
	hero.apply_knockback(Vector3(18.0, 0.0, 0.0))
	await _settle(20)
	var standing_slide: float = Vector2(hero.global_position.x - from.x,
		hero.global_position.z - from.z).length()

	# Downed: the same impulse must not.
	GameManager.damage_player(1, GameManager.MAX_PLAYER_HEALTH)
	await _settle(20)
	from = hero.global_position
	hero.apply_knockback(Vector3(18.0, 0.0, 0.0))
	await _settle(20)
	var downed_slide: float = Vector2(hero.global_position.x - from.x,
		hero.global_position.z - from.z).length()

	print("\n  -- an 18 m/s shove: a standing hero slides %.2f m, a downed one %.2f m"
		% [standing_slide, downed_slide])
	_ok(hero.is_downed(), "the hero is down for the measurement")
	_ok(standing_slide > 0.5,
		"a standing hero is moved by apply_knockback (%.2f m)" % standing_slide)
	_ok(downed_slide < 0.25,
		"a DOWNED hero is not — the impulse is dropped on purpose (%.2f m). "
			% downed_slide + "Move a downed body positionally; see _process_downed.")

	# Leave them upright for whatever runs next.
	GameManager.revive_player(1)
	await _settle(20)


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
