extends Node
## Touch probe: the on-screen controls and every screen, driven by emulated
## touches through the real input pipeline (Input.parse_input_event, so the
## engine's touch-to-mouse emulation runs exactly as on a tablet).
##
##   godot --headless --path . scripts/ui/touch/_touch_probe.tscn
##
## What it pins down:
##   * the overlay never shows without touch, nor in a headless run on AUTO;
##     the first touch shows it (when AUTO may run), a key hides it again;
##   * the stick moves the RIGHT hero (human_hero in solo, hero 1 in co-op),
##     with a dead zone, and lets go cleanly;
##   * Attack / Power / Jump give one just-press each for that hero, Jump is
##     held while the finger is down, and a stick finger plus a button finger
##     work at the same time;
##   * a touch in play is not also an emulated left click (= "attack");
##   * the pause button works by touch, and the pause sheet by tap;
##   * the touch layout keeps the HUD out of the thumbs' way at 16:9 and 4:3;
##   * the title, shelf, who's playing, reader, settings and sticker screens all
##     work by tapping;
##   * the gameplay HUD stays inside its draw-call budget (structural proxy:
##     no polygon-drawn KidIcons or four-pass Labels, and a capped number of
##     visible canvas items).
## Exit code 0 = pass.

const HUDScene := preload("res://scenes/ui/hud.tscn")
const MenuScene := preload("res://scenes/ui/main_menu.tscn")
const GameOverScene := preload("res://scenes/ui/game_over.tscn")

var _fails := 0
var _watch: _Watcher


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	UIProgress.use_memory_only()
	GameManager.language = "pt"
	GameManager.assists = true
	GameManager.companion = true
	GameManager.narration = false
	_watch = _Watcher.new()
	add_child(_watch)
	await get_tree().process_frame
	print("view: %s" % str(get_viewport().get_visible_rect().size))

	print("=== overlay visibility ===")
	await _check_visibility()
	print("=== stick and buttons ===")
	await _check_controls()
	print("=== pause by touch ===")
	await _check_pause()
	print("=== touch layout ===")
	await _check_layout(Vector2i(1280, 720))
	await _check_layout(Vector2i(1280, 960))
	print("=== HUD draw-call budget (structural) ===")
	await _check_budget()
	print("=== every screen by tapping ===")
	await _check_menus()

	TouchControls.force = TouchControls.Force.AUTO
	TouchControls.headless_auto = false
	print("")
	if _fails == 0:
		print("TOUCH PROBE: PASS")
	else:
		print("TOUCH PROBE: %d FAILURE(S)" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)


# --- Overlay visibility ------------------------------------------------------------

func _check_visibility() -> void:
	TouchControls.force = TouchControls.Force.AUTO
	TouchControls.headless_auto = false
	var hud := await _hud(1, 1)
	var touch: TouchControls = hud._touch
	_ok(touch != null, "the HUD adds the touch overlay")
	_ok(not touch.is_active() and not touch.is_shown(),
		"no touchscreen, no touch: the overlay is hidden in play")
	_ok(not hud._compact, "and the HUD keeps its normal corners")
	_touch(0, Vector2(300, 500), true)
	_touch(0, Vector2(300, 500), false)
	await _frames(2)
	_ok(not touch.is_shown(), "a headless run on AUTO never shows it, even after a touch")

	# Let AUTO run here, as it does on a device.
	TouchControls.headless_auto = true
	_touch(0, Vector2(300, 500), true)
	_touch(0, Vector2(300, 500), false)
	await _frames(2)
	_ok(touch.is_active() and touch.is_shown(), "the first touch shows the overlay")
	_ok(hud._compact, "and the HUD moves its panels out of the thumbs' way")
	_ok(not Input.emulate_mouse_from_touch, "touch-to-mouse emulation is off while it plays")
	_key(KEY_W)
	await _frames(2)
	_ok(not touch.is_active() and not touch.is_shown(), "a key press hides it again")
	_ok(not hud._compact, "and the HUD goes back to its corners")
	_ok(Input.emulate_mouse_from_touch, "and the emulation is back on")
	# Two players: player two's keys belong to the other hero, not the overlay.
	_free(hud)
	hud = await _hud(2, 1)
	touch = hud._touch
	_touch(0, Vector2(300, 500), true)
	_touch(0, Vector2(300, 500), false)
	await _frames(2)
	_ok(touch.is_shown(), "co-op: touch shows the overlay for player one")
	_key(KEY_I)
	await _frames(2)
	_ok(touch.is_shown(), "player two's keys leave it up")
	_key(KEY_W)
	await _frames(2)
	_ok(not touch.is_shown(), "player one's keys hide it")
	TouchControls.headless_auto = false
	GameManager.change_state(GameManager.State.MENU)
	await _frames(1)
	_free(hud)


# --- Stick and buttons ---------------------------------------------------------------

func _check_controls() -> void:
	TouchControls.force = TouchControls.Force.ON
	for setup: Array in [[1, 2], [2, 2], [1, 1]]:
		var players: int = setup[0]
		var human: int = setup[1]
		var want := human if players <= 1 else 1
		var other := 3 - want
		var hud := await _hud(players, human)
		var touch: TouchControls = hud._touch
		var tag := "%dP human=%d" % [players, human]
		_ok(touch.is_shown(), "%s: forced on, the overlay shows in play" % tag)
		_ok(touch.hero() == want, "%s: it drives hero %d (%d)" % [tag, want, touch.hero()])

		var zone := touch.stick_zone()
		var at := zone.position + Vector2(zone.size.x * 0.4, zone.size.y * 0.5)
		_touch(0, at, true)
		await _phys(2)
		_ok(InputManager.get_move_vector(want) == Vector2.ZERO, "%s: a thumb landing is not a move" % tag)
		_watch.clear()
		_drag(0, at + Vector2(6, -6))
		await _phys(2)
		_ok(InputManager.get_move_vector(want) == Vector2.ZERO, "%s: a wobble inside the dead zone is not a move" % tag)
		_drag(0, at + Vector2(0, -50))
		await _phys(2)
		var v := InputManager.get_move_vector(want)
		_ok(v.y > 0.5 and absf(v.x) < 0.1, "%s: pushing up walks hero %d forward %s" % [tag, want, str(v)])
		_ok(InputManager.get_move_vector(other) == Vector2.ZERO, "%s: hero %d does not move" % [tag, other])
		_drag(0, at + Vector2(80, 0))
		await _phys(2)
		v = InputManager.get_move_vector(want)
		_ok(v.x > 0.9, "%s: pushing right strafes right at full speed %s" % [tag, str(v)])
		_ok(_watch.count(want, &"attack") == 0 and not Input.is_action_pressed(&"attack"),
			"%s: the stick finger is not also a left click (= attack)" % tag)

		# Multi-touch: a second finger on Attack while the stick is held.
		_watch.clear()
		_tap_button(touch, TouchControls.Role.ATTACK, 1)
		await _phys(3)
		_ok(_watch.count(want, &"attack") == 1, "%s: Attack, stick still held: one attack (%d)"
			% [tag, _watch.count(want, &"attack")])
		_ok(InputManager.get_move_vector(want).x > 0.9, "%s: and the stick kept steering" % tag)
		_ok(_watch.count(other, &"attack") == 0, "%s: hero %d did not attack" % [tag, other])
		_touch(0, at + Vector2(80, 0), false)
		await _phys(2)
		_ok(InputManager.get_move_vector(want) == Vector2.ZERO, "%s: lifting the thumb stops the hero" % tag)

		_watch.clear()
		_tap_button(touch, TouchControls.Role.ABILITY, 2)
		await _phys(3)
		_ok(_watch.count(want, &"ability") == 1, "%s: Power gives one ability press (%d)"
			% [tag, _watch.count(want, &"ability")])
		_ok(_watch.count(want, &"attack") == 0, "%s: and no attack" % tag)

		_watch.clear()
		var jc := touch.button_rect(TouchControls.Role.JUMP).get_center()
		_touch(3, jc, true)
		await _phys(3)
		_ok(_watch.count(want, &"jump") == 1, "%s: Jump gives one jump press (%d)" % [tag, _watch.count(want, &"jump")])
		_ok(InputManager.is_jump_held(want), "%s: and holds jump while the finger is down" % tag)
		_touch(3, jc, false)
		await _phys(2)
		_ok(not InputManager.is_jump_held(want), "%s: and lets go with it" % tag)

		# Cooldown dial on the Power button, fed by the HUD.
		touch.set_ability(0.25)
		_ok(touch._ring.fraction < 0.3 and touch._buttons[TouchControls.Role.ABILITY].modulate.r < 0.9,
			"%s: Power shows its cooldown" % tag)
		touch.set_ability(1.0)
		_ok(touch._buttons[TouchControls.Role.ABILITY].modulate == Color.WHITE, "%s: and lights up when ready" % tag)

		# Leaving play drops every finger.
		_touch(4, at, true)
		_drag(4, at + Vector2(0, -60))
		await _phys(2)
		GameManager.change_state(GameManager.State.MENU)
		await _phys(2)
		_ok(not touch.is_shown() and InputManager.get_move_vector(want) == Vector2.ZERO,
			"%s: leaving play hides it and lets go of the stick" % tag)
		_touch(4, at, false)
		await _frames(1)
		_free(hud)


# --- Pause ------------------------------------------------------------------------------

func _check_pause() -> void:
	TouchControls.force = TouchControls.Force.ON
	var hud := await _hud(1, 1)
	var btn: Control = hud._pause_btn
	_tap(btn.get_global_rect().get_center())
	await _frames(2)
	_ok(GameManager.state == GameManager.State.PAUSED, "tapping the pause button pauses")
	_ok(not hud._touch.is_shown(), "the overlay steps aside for the pause sheet")
	_ok(Input.emulate_mouse_from_touch, "and the sheet is tappable (emulation back on)")
	_check_pause_hints(hud, true, "touch")
	await _frames(2)
	_tap(hud._resume_btn.get_global_rect().get_center())
	await _frames(2)
	_ok(GameManager.state == GameManager.State.PLAYING, "tapping Resume resumes")
	_ok(hud._touch.is_shown(), "and the controls come back")
	GameManager.change_state(GameManager.State.MENU)
	await _frames(1)
	_free(hud)
	# Without the overlay the pause button is a plain button, tapped through
	# the emulated mouse.
	TouchControls.force = TouchControls.Force.OFF
	hud = await _hud(1, 1)
	_tap(hud._pause_btn.get_global_rect().get_center())
	await _frames(2)
	_ok(GameManager.state == GameManager.State.PAUSED, "no overlay: the pause button still taps")
	_check_pause_hints(hud, false, "keyboard")
	GameManager.change_state(GameManager.State.MENU)
	await _frames(1)
	_free(hud)
	TouchControls.force = TouchControls.Force.AUTO


## The pause sheet's control reminder. By touch it is the overlay's own
## pictures (stick, jump, hit, power) and not a single key cap: a child on a
## tablet has no WASD and no Esc. On keys it is the key caps, as before.
func _check_pause_hints(hud: Control, touch_on: bool, tag: String) -> void:
	var hints: Control = hud._pause_hints
	var caps := _count_caps(hints)
	var legend := hints.find_child("TouchLegend", true, false) as Control
	if touch_on:
		_ok(caps == 0, "%s pause sheet shows no key caps (%d)" % [tag, caps])
		_ok(legend != null and legend.is_visible_in_tree(),
			"%s pause sheet shows the touch pictograms instead" % tag)
		if legend != null:
			var pics := 0
			for cell in legend.get_children():
				if cell.get_child_count() > 0 and cell.get_child(0) is TextureRect:
					pics += 1
			_ok(pics == 4, "%s legend has stick, jump, hit and power (%d)" % [tag, pics])
	else:
		_ok(caps > 0, "%s pause sheet shows the key caps (%d)" % [tag, caps])
		_ok(legend == null, "%s pause sheet has no touch legend" % tag)


func _count_caps(n: Node) -> int:
	var k := 1 if n is PanelContainer else 0
	for c in n.get_children():
		k += _count_caps(c)
	return k


# --- Layout ------------------------------------------------------------------------------

## The touch layout in a stage of the given canvas size (1280x720 is 16:9; a
## 4:3 tablet under canvas_items + expand is 1280x960).
func _check_layout(view: Vector2i) -> void:
	TouchControls.force = TouchControls.Force.ON
	var stage := SubViewport.new()
	stage.size = view
	stage.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(stage)
	var fake_boss := Node3D.new()
	fake_boss.add_to_group("boss")
	add_child(fake_boss)
	var hud: Control = HUDScene.instantiate()
	stage.add_child(hud)
	GameManager.player_count = 1
	GameManager.human_hero = 1
	GameManager.chapter_id = "adamastor"
	GameManager.start_game()
	GameManager.set_objective({"pt": "Derrota o Adamastor e salva a ponte!", "en": "Beat him!"}, 4)
	GameManager.combo_changed.emit(1, 6)
	GameManager.combo_changed.emit(2, 3)
	GameManager.request_story_beat("a09")
	# A hit recoils the panel about its centre; the scaled-down compact panel
	# must still land where the layout put it.
	GameManager.damage_player(1, 20)
	await _seconds(0.6)
	var tag := "%dx%d" % [view.x, view.y]
	var touch: TouchControls = hud._touch
	_ok(hud._compact and touch.is_shown(), "%s: touch layout is on" % tag)
	var frame := Rect2(Vector2.ZERO, Vector2(view))
	var buttons: Array[Rect2] = []
	for role in [TouchControls.Role.ATTACK, TouchControls.Role.ABILITY, TouchControls.Role.JUMP]:
		var r := touch.button_rect(role)
		buttons.append(r)
		_ok(frame.encloses(r) and r.size.x >= 76.0, "%s: button %d is on screen and big %s" % [tag, role, r])
		_ok(r.position.x + r.size.x <= view.x - 24.0 + 0.5 and r.end.y <= view.y - 24.0 + 0.5,
			"%s: button %d keeps 24 px from the edges" % [tag, role])
	for i in buttons.size():
		for j in range(i + 1, buttons.size()):
			var gap := buttons[i].get_center().distance_to(buttons[j].get_center()) - buttons[i].size.x
			_ok(gap >= 18.0, "%s: buttons %d/%d are %.0f px apart" % [tag, i, j, gap])
	var zone := touch.stick_zone()
	var widgets := {}
	for pid: int in hud._heroes:
		var p: HeroPanel = hud._heroes[pid]
		# Where it is DRAWN: scale applies about the pivot.
		var pr := Rect2(p.position + p.pivot_offset * (Vector2.ONE - p.scale), p.size * p.scale)
		widgets["hero %d" % pid] = pr
		# Compact panels carry their combo on the plate (no overhang).
		var cr := p.combo_rect()
		var combo := Rect2(pr.position + (cr.position - p.position) * p.scale, cr.size * p.scale)
		_ok(p._combo_count.visible and pr.grow(0.5).encloses(combo),
			"%s: hero %d's combo sits on its compact plate %s" % [tag, pid, combo])
		_ok(not p._dial.visible, "%s: hero %d's dial gives way to the Power button" % [tag, pid])
	widgets["goal"] = Rect2(hud._objective.position, hud._objective.size)
	widgets["toast"] = Rect2(hud._toast.position, hud._toast.size * hud._toast.scale)
	widgets["boss"] = Rect2(hud._boss_plate.position, hud._boss_plate.size)
	widgets["pause"] = Rect2(hud._pause_btn.position, hud._pause_btn.size)
	for k: String in widgets:
		var r: Rect2 = widgets[k]
		_ok(frame.encloses(r.grow(-0.5)), "%s: %s is on screen %s" % [tag, k, r])
		_ok(not r.intersects(zone), "%s: %s clears the stick zone %s / %s" % [tag, k, r, zone])
		for b in buttons:
			_ok(not r.intersects(b.grow(SLOP)), "%s: %s clears the action buttons" % [tag, k])
	var keys := widgets.keys()
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			var a: Rect2 = widgets[keys[i]]
			var b: Rect2 = widgets[keys[j]]
			if a.size == Vector2.ZERO or b.size == Vector2.ZERO:
				continue
			_ok(not a.intersects(b), "%s: %s and %s do not overlap" % [tag, keys[i], keys[j]])
	_ok(zone.size.y >= 300.0, "%s: the stick has room (%.0f px tall)" % [tag, zone.size.y])
	GameManager.change_state(GameManager.State.MENU)
	await _frames(1)
	stage.queue_free()
	fake_boss.queue_free()
	await _frames(1)
	TouchControls.force = TouchControls.Force.AUTO


const SLOP := 6.0


# --- Draw-call budget ------------------------------------------------------------------

## Upper bound on visible canvas items in the busiest gameplay HUD (boss
## banner, both panels with combos, goal, toast, touch overlay). Measured with
## scripts/ui/_shots/hud_cost.tscn under GL Compatibility, the HUD costs
## about one draw call per visible item or less once the expensive kinds below
## are gone, so this cap is the budget in a form a headless run can measure.
const BUDGET_ITEMS := 85


## The headless renderer counts nothing, so the budget is checked by structure:
## the two things that made the old HUD cost 210-300 draw calls are banned from
## the live gameplay HUD (KidIcons, which are 8-45 polygons each, and Labels
## drawn in four passes), and the number of visible items is capped.
func _check_budget() -> void:
	for touch_on in [false, true]:
		TouchControls.force = TouchControls.Force.ON if touch_on else TouchControls.Force.OFF
		var fake_boss := Node3D.new()
		fake_boss.add_to_group("boss")
		add_child(fake_boss)
		var hud := await _hud(1, 1)
		GameManager.chapter_id = "adamastor"
		GameManager.set_objective({"pt": "Derrota o Adamastor!", "en": "Beat him!"}, 4)
		GameManager.advance_objective(1)
		GameManager.combo_changed.emit(1, 6)
		GameManager.combo_changed.emit(2, 4)
		GameManager.damage_player(1, 20)
		GameManager.request_story_beat("a09")
		await _frames(4)
		var tag := "touch" if touch_on else "keyboard"
		var census := {"items": 0, "kid_icons": [], "four_pass": []}
		_census(hud, census)   # the touch overlay is the HUD's child: counted too
		print("  %s HUD: %d visible canvas items" % [tag, census["items"]])
		_ok((census["kid_icons"] as Array).is_empty(),
			"%s: no live KidIcon is drawn in play (atlas stamps instead) %s" % [tag, str(census["kid_icons"])])
		_ok((census["four_pass"] as Array).is_empty(),
			"%s: no four-pass Label is drawn in play (InkText instead) %s" % [tag, str(census["four_pass"])])
		_ok(int(census["items"]) <= BUDGET_ITEMS, "%s: %d visible canvas items, budget %d"
			% [tag, census["items"], BUDGET_ITEMS])
		GameManager.change_state(GameManager.State.MENU)
		await _frames(1)
		_free(hud)
		fake_boss.queue_free()
	TouchControls.force = TouchControls.Force.AUTO


func _census(n: Node, out: Dictionary) -> void:
	if n is CanvasItem:
		if not (n as CanvasItem).visible:
			return
		if (n as CanvasItem).modulate.a <= 0.001 or (n as CanvasItem).self_modulate.a <= 0.001:
			return   # culled by the renderer
		out["items"] = int(out["items"]) + 1
		if n is KidIcon:
			(out["kid_icons"] as Array).append(str(n.get_path()).get_file())
		elif n is Label:
			var l := n as Label
			if l.get_theme_constant("outline_size") > 0 and l.get_theme_color("font_shadow_color").a > 0.0 \
					and not l.text.is_empty():
				(out["four_pass"] as Array).append(l.text)
	elif n is CanvasLayer and not (n as CanvasLayer).visible:
		return
	for c in n.get_children():
		_census(c, out)


# --- Every screen, by tapping --------------------------------------------------------

func _check_menus() -> void:
	TouchControls.force = TouchControls.Force.AUTO
	GameManager.change_state(GameManager.State.MENU)
	var menu: Control = MenuScene.instantiate()
	add_child(menu)
	await _frames(2)
	_ok(menu.screen == "title", "the menu opens on the title")
	await _seconds(0.6)
	_tap(get_viewport().get_visible_rect().size * 0.5)
	await _seconds(0.3)
	_ok(menu.screen == "shelf", "tap: title -> shelf (%s)" % menu.screen)

	var shelf: Bookshelf = menu.shelf
	_tap(shelf._gear.get_global_rect().get_center())
	await _seconds(0.3)
	_ok(menu.settings.is_open(), "tap the gear: settings open")
	_tap(menu.settings._close.get_global_rect().get_center())
	await _seconds(0.4)
	_ok(not menu.settings.is_open(), "tap close: settings close")

	_tap(shelf.covers[0].get_global_rect().get_center())
	await _seconds(0.4)
	_ok(menu.screen == "who", "tap a book: shelf -> who's playing (%s)" % menu.screen)
	var who: WhoPlays = menu.who
	_tap(who._cards[0].get_global_rect().get_center())
	await _seconds(0.4)
	_ok(who.step == 1, "tap one player: on to which hero (step %d)" % who.step)
	_tap(who._cards[0].get_global_rect().get_center())
	await _seconds(0.5)
	_ok(menu.screen == "reader" and menu.reader.is_open(), "tap a hero: the story opens (%s)" % menu.screen)

	var reader: PageReader = menu.reader
	await _seconds(0.6)
	var before := reader.index
	_tap(reader.get_global_rect().get_center() + Vector2(0, -120))
	await _seconds(0.6)
	_ok(reader.index == before + 1, "tap the page: next page (%d -> %d)" % [before, reader.index])
	_tap(reader._next.get_global_rect().get_center())
	await _seconds(0.6)
	_ok(reader.index == before + 2, "tap the arrow: next page (%d)" % reader.index)
	_tap(reader._back.get_global_rect().get_center())
	await _seconds(0.6)
	_ok(reader.index == before + 1, "tap back: previous page (%d)" % reader.index)
	_tap(reader._skip.get_global_rect().get_center())
	await _seconds(0.8)
	_ok(GameManager.state == GameManager.State.PLAYING, "tap skip: the chapter starts")
	menu.queue_free()
	await _frames(1)

	# The end card.
	var over: Control = GameOverScene.instantiate()
	add_child(over)
	await _frames(1)
	over.chapter_id = "adamastor"
	over.call("_show_sticker")
	await _seconds(0.6)
	_tap(over._continue.get_global_rect().get_center())
	await _seconds(0.3)
	_ok(GameManager.state == GameManager.State.MENU, "tap Continue on the sticker card: back to the book")
	over.queue_free()
	await _frames(1)


# --- Helpers ---------------------------------------------------------------------------

func _hud(players: int, human: int) -> Control:
	GameManager.player_count = players
	GameManager.human_hero = human
	GameManager.chapter_id = "dragao"
	var hud: Control = HUDScene.instantiate()
	add_child(hud)
	await _frames(1)
	GameManager.start_game()
	await _frames(2)
	return hud


func _free(n: Node) -> void:
	if n != null and is_instance_valid(n):
		n.get_parent().remove_child(n)
		n.queue_free()


## Events enter as WINDOW pixels, the way a device reports them, and the
## engine's stretch transform maps them into the 1280-wide canvas; every point
## in this probe is a canvas point, so it goes out through the inverse. (The
## headless window is tiny, so the factor is large: a probe that forgot this
## would tap far off screen.)
func _win(at: Vector2) -> Vector2:
	return get_tree().root.get_final_transform() * at


func _touch(index: int, at: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = _win(at)
	e.pressed = pressed
	Input.parse_input_event(e)


func _drag(index: int, at: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = _win(at)
	Input.parse_input_event(e)


func _tap(at: Vector2, index: int = 0) -> void:
	_touch(index, at, true)
	_touch(index, at, false)


func _tap_button(touch: TouchControls, role: int, index: int) -> void:
	_tap(touch.button_rect(role).get_center(), index)


func _key(code: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := ev.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _phys(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
	await get_tree().process_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _ok(cond: bool, what: String) -> void:
	if cond:
		print("  ok: " + what)
	else:
		_fails += 1
		print("  FAIL: " + what)


## Reads the hero-facing input API on the physics tick, AFTER InputManager has
## promoted the virtual presses (it runs at priority -1000), exactly the way
## PlayerBase reads it.
class _Watcher extends Node:
	var _counts := {}

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		process_physics_priority = 100

	func clear() -> void:
		_counts.clear()

	func count(pid: int, action: StringName) -> int:
		return int(_counts.get("%d:%s" % [pid, action], 0))

	func _physics_process(_delta: float) -> void:
		for pid in [1, 2]:
			if InputManager.is_attack_just_pressed(pid):
				_bump(pid, &"attack")
			if InputManager.is_ability_just_pressed(pid):
				_bump(pid, &"ability")
			if InputManager.is_jump_just_pressed(pid):
				_bump(pid, &"jump")

	func _bump(pid: int, action: StringName) -> void:
		var k := "%d:%s" % [pid, action]
		_counts[k] = int(_counts.get(k, 0)) + 1
