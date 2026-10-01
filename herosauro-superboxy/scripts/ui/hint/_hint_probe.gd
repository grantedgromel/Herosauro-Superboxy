extends Node
## Probe for the start-of-level controls card and the idle hint ladder.
## Not shipped.
##
## A live HUD on a fixed 1280x720 stage, a camera, a fake boss and a fake level
## whose hint_target() the probe moves around. The card is driven with
## InputManager virtual input (the same route the touch overlay and the AI
## use); the ladder is walked with IdleHint.step() so no check waits 8 s.
##
## Run:
##   godot --headless --path . scripts/ui/hint/_hint_probe.tscn

const HUDScene: PackedScene = preload("res://scenes/ui/hud.tscn")
const VIEW := Vector2(1280, 720)
const LEVEL_SRC := "extends Node3D\nvar target := Vector3.INF\nfunc hint_target() -> Vector3:\n\treturn target\n"

var _fails := 0
var _stage: SubViewport
var _cam: Camera3D
var _level: Node3D
var _boss: Node3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_stage = SubViewport.new()
	_stage.size = Vector2i(VIEW)
	_stage.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_stage)
	UIProgress.use_memory_only()
	GameManager.language = "pt"
	GameManager.narration = true
	GameManager.reduce_motion = false
	GameManager.player_count = 1
	GameManager.human_hero = 1
	GameManager.companion = true
	GameManager.chapter_id = "dragao"

	_cam = Camera3D.new()
	_stage.add_child(_cam)
	_cam.global_position = Vector3(0.0, 4.0, 12.0)
	_cam.look_at(Vector3(0.0, 1.0, 0.0))
	_cam.current = true
	var gs := GDScript.new()
	gs.source_code = LEVEL_SRC
	gs.reload()
	_level = Node3D.new()
	_level.set_script(gs)
	_level.add_to_group("level")
	_stage.add_child(_level)

	var hud: Control = HUDScene.instantiate()
	_stage.add_child(hud)
	await get_tree().process_frame

	print("=== controls card ===")
	await _check_card(hud)
	print("=== idle hint ladder ===")
	await _check_hint(hud)

	InputManager.clear_virtual()
	print("")
	if _fails == 0:
		print("HINT PROBE: PASS")
	else:
		print("HINT PROBE: %d FAILURE(S)" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)


func _ok(cond: bool, what: String) -> void:
	if cond:
		print("  ok   %s" % what)
	else:
		_fails += 1
		print("  FAIL %s" % what)


func _wait_ms(ms: int) -> void:
	var until := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


func _wait_until(cond: Callable, timeout_ms: int) -> void:
	var until := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < until:
		if cond.call():
			return
		await get_tree().process_frame


func _check_card(hud: Control) -> void:
	var card: ControlsCard = hud.get("_coach")
	_ok(card != null, "the HUD builds a controls card")
	if card == null:
		return
	card.force_device = ControlsCard.Device.KEYS
	GameManager.start_game()
	await get_tree().process_frame
	_ok(card.is_open() and card.visible, "the card is up when the level starts")

	var r := card.card_rect()
	_ok(r.size.x <= VIEW.x * ControlsCard.MAX_SHARE + 0.5,
		"no wider than 35%% of the screen (%.0f px)" % r.size.x)
	_ok(absf(r.get_center().x - VIEW.x * 0.5) < 1.0 and r.end.y <= VIEW.y - UIStyle.SCREEN_MARGIN + 0.5,
		"bottom-centre, inside the gutter %s" % r)
	var clear := true
	for panel: Control in (hud.get("_heroes") as Dictionary).values():
		if panel.visible and Rect2(panel.global_position, panel.size * panel.scale).intersects(r):
			clear = false
	_ok(clear, "the card never covers a hero panel")

	await _wait_until(func() -> bool: return card.spoken_line != "", 2000)
	_ok(card.spoken_line == "Anda com as setas, salta com o espaço e ataca com o J!",
		"says the keyboard line in Portuguese ('%s')" % card.spoken_line)
	_ok(ControlsCard.line_for(ControlsCard.Device.PAD).contains("A")
		and ControlsCard.line_for(ControlsCard.Device.TOUCH) != card.spoken_line,
		"the pad and touch lines are their own")

	InputManager.set_virtual_move(1, Vector2(0.0, 1.0))
	await _wait_ms(120)
	InputManager.set_virtual_move(1, Vector2.ZERO)
	_ok(card.done[ControlsCard.Act.MOVE], "moving ticks MOVE off")
	_ok(card.is_open(), "moving alone does not dismiss the card")
	InputManager.press_virtual(1, &"attack")
	await _wait_ms(120)
	_ok(card.done[ControlsCard.Act.HIT], "hitting ticks HIT off")
	await _wait_until(func() -> bool: return not card.is_open(), 3000)
	_ok(not card.is_open(), "moved + hit: the card leaves by itself")
	await _wait_until(func() -> bool: return not card.visible, 2000)
	_ok(not card.visible, "and fades all the way out")

	GameManager.start_game()
	await get_tree().process_frame
	_ok(not card.is_open(), "a replay of the same chapter never shows it again")
	GameManager.chapter_id = "pandas"
	GameManager.start_game()
	await get_tree().process_frame
	_ok(card.is_open(), "the next chapter's first run shows it again")
	card._clock = ControlsCard.LIFETIME - 0.01
	await _wait_ms(80)
	_ok(not card.is_open(), "an untouched card leaves after %.0f s" % ControlsCard.LIFETIME)
	await _wait_until(func() -> bool: return not card.visible, 2000)


func _check_hint(hud: Control) -> void:
	var hint: IdleHint = hud.get("_hint")
	_ok(hint != null, "the HUD builds an idle hint")
	if hint == null:
		return
	GameManager.set_objective({"pt": "Encontra as malas!", "en": "Find the suitcases!"}, 4)
	_level.set("target", Vector3(40.0, 0.0, 0.0))   # well off the right edge
	hint.reset()
	hint.step(IdleHint.SHOW_AT - 0.5)
	_ok(not hint.is_showing(), "no arrow before %.0f s idle" % IdleHint.SHOW_AT)
	hint.step(0.7)
	_ok(hint.is_showing(), "an arrow after %.0f s idle" % IdleHint.SHOW_AT)

	var centre := VIEW * 0.5
	var goal := Vector3(40.0, 0.0, 0.0) + IdleHint.LEVEL_LIFT
	var want := (_cam.unproject_position(goal) - centre).normalized()
	var err := rad_to_deg(absf(hint.arrow_direction().angle_to(want)))
	_ok(not hint.pointing_on_screen() and err <= 25.0,
		"off-screen goal: an edge arrow points at it (%.1f deg off)" % err)
	var tip := hint.arrow_tip()
	_ok(Rect2(Vector2.ZERO, VIEW).has_point(tip) and tip.x > centre.x,
		"the edge arrow sits on screen, on the goal's side %s" % tip)

	_level.set("target", Vector3(-1.5, 0.0, 0.0))   # in view
	hint.step(0.016)
	var spot := _cam.unproject_position(Vector3(-1.5, 0.0, 0.0) + IdleHint.LEVEL_LIFT)
	_ok(hint.pointing_on_screen() and hint.arrow_tip().distance_to(spot) <= 40.0
		and hint.arrow_direction().dot(Vector2.DOWN) > 0.95,
		"on-screen goal: the arrow hovers over it, pointing down")

	_ok(hint.spoken_count == 0, "nothing is said before %.0f s" % IdleHint.SPEAK_AT)
	hint.step(IdleHint.SPEAK_AT - hint.idle_time() + 0.1)
	_ok(hint.spoken_count == 1 and hint.spoken_text == "Encontra as malas!",
		"at %.0f s the objective is spoken ('%s')" % [IdleHint.SPEAK_AT, hint.spoken_text])
	hint.step(3.0)
	hint.step(3.0)
	_ok(hint.spoken_count == 1, "and only once")

	InputManager.set_virtual_move(1, Vector2(1.0, 0.0))
	await _wait_ms(60)
	InputManager.set_virtual_move(1, Vector2.ZERO)
	hint.step(0.016)
	_ok(not hint.is_showing() and hint.idle_time() < 0.1, "a move hides it and resets the ladder")

	hint.step(IdleHint.SHOW_AT + 0.2)
	_ok(hint.is_showing(), "idle again: the arrow comes back")
	GameManager.advance_objective(1)
	_ok(not hint.is_showing() and hint.idle_time() < 0.1, "progress hides it and resets the ladder")

	GameManager.change_state(GameManager.State.PAUSED)
	hint.step(IdleHint.SHOW_AT + 1.0)
	_ok(not hint.is_showing(), "never while paused")
	GameManager.change_state(GameManager.State.PLAYING)

	var toast: StoryToast = hud.get("_toast")
	toast.show_beat(StoryData.chapter("pandas")["beats"][0])
	hint.reset()
	hint.step(IdleHint.SHOW_AT + 1.0)
	_ok(not hint.is_showing(), "never while a story toast is speaking")
	toast.clear()

	_level.set("target", Vector3.INF)
	hint.reset()
	hint.step(IdleHint.SHOW_AT + 0.2)
	_ok(not hint.is_showing(), "no goal, no boss: no arrow")
	_boss = Node3D.new()
	_boss.add_to_group("boss")
	_stage.add_child(_boss)
	_boss.global_position = Vector3(0.0, 0.0, -6.0)
	hint.step(0.016)
	_ok(hint.is_showing(), "an infinite hint_target falls back to the boss")

	GameManager.reduce_motion = true
	hint.reset()
	hint.step(IdleHint.SHOW_AT + 0.2)
	var a := hint.arrow_tip()
	hint.step(0.3)
	var b := hint.arrow_tip()
	_ok(a.distance_to(b) < 0.01, "Menos movimento: a steady arrow, no hop")
	GameManager.reduce_motion = false
	GameManager.change_state(GameManager.State.MENU)
	hint.step(IdleHint.SHOW_AT + 1.0)
	_ok(not hint.is_showing(), "never in the menus")
