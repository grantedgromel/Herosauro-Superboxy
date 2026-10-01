extends Node
## Keyboard walk through the shelf and "Quem vai jogar", with real key events
## through the input pipeline (Input.parse_input_event), the way a child on a
## laptop drives it:
##
##   * Left from "1 jogador" (and from the first hero card) stays put: it must
##     not slide onto the Back button, which sits up-left of the first card and
##     is what the engine's geometric focus search used to pick. Enter after
##     that stray Left dumped the child back on the shelf.
##   * Back is still reachable on purpose: Up from the cards, and Esc.
##   * Going back to the shelf focuses the book that was opened, not the
##     "next unfinished" one UIProgress suggests.
##
## The bug it was written for: shelf -> focus pandas -> Enter -> Left -> Enter
## landed on the shelf focused on book 1.
##
##   godot --headless --path . scripts/ui/book/_nav_probe.tscn
## Exit code 0 = pass.

const MenuScene := preload("res://scenes/ui/main_menu.tscn")

var _fails := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	UIProgress.use_memory_only()
	GameManager.narration = false
	await get_tree().process_frame
	var menu: Control = MenuScene.instantiate()
	add_child(menu)
	await _frames(2)
	menu.debug_show("shelf")
	await _frames(3)

	var shelf: Bookshelf = menu.shelf
	var who: WhoPlays = menu.who
	var last := shelf.covers[shelf.covers.size() - 1]
	print("=== shelf -> %s -> who's playing ===" % last.chapter_id)
	_ok(last.chapter_id == "pandas", "the last book is pandas (%s)" % last.chapter_id)
	last.grab_focus()
	await _frames(1)
	_key(KEY_ENTER)
	await _frames(3)
	_ok(menu.screen == "who" and who.step == 0, "Enter on the book opens who's playing (%s)" % menu.screen)
	_ok(_focused() == who._cards[0] or _focused() == who._cards[1], "a players card has focus (%s)" % _name(_focused()))
	who._cards[0].grab_focus()
	await _frames(1)

	_key(KEY_LEFT)
	await _frames(2)
	_ok(_focused() == who._cards[0], "Left from 1 jogador stays on it, not Back (%s)" % _name(_focused()))
	_key(KEY_RIGHT)
	await _frames(2)
	_ok(_focused() == who._cards[1], "Right goes to 2 jogadores (%s)" % _name(_focused()))
	_key(KEY_RIGHT)
	await _frames(2)
	_ok(_focused() == who._cards[1], "Right from 2 jogadores stays (%s)" % _name(_focused()))
	_key(KEY_DOWN)
	await _frames(2)
	_ok(_focused() == who._cards[1], "Down from a card stays (%s)" % _name(_focused()))
	_key(KEY_UP)
	await _frames(2)
	_ok(_focused() == who._back, "Up from the cards reaches Back on purpose (%s)" % _name(_focused()))
	_key(KEY_DOWN)
	await _frames(2)
	_ok(_focused() == who._cards[0], "Down from Back returns to the first card (%s)" % _name(_focused()))

	# The reported sequence: Left, then Enter, must pick one player.
	_key(KEY_LEFT)
	await _frames(1)
	_key(KEY_ENTER)
	await _frames(3)
	_ok(menu.screen == "who" and who.step == 1, "Left then Enter picks 1 jogador (screen %s step %d)"
		% [menu.screen, who.step])
	_key(KEY_LEFT)
	await _frames(2)
	_ok(_focused() == who._cards[0], "Left from the first hero stays on it (%s)" % _name(_focused()))
	_key(KEY_ESCAPE)
	await _frames(3)
	_ok(who.step == 0 and _focused() == who._cards[0],
		"Esc from the heroes goes back to 1 jogador (step %d, %s)" % [who.step, _name(_focused())])
	_key(KEY_ESCAPE)
	await _frames(3)
	_ok(menu.screen == "shelf", "Esc on who's playing returns to the shelf (%s)" % menu.screen)
	_ok(_focused() == last, "the shelf focuses the book that was opened, %s (%s)"
		% [last.chapter_id, _name(_focused())])

	# The Back button by mouse/touch still goes back, and still to that book.
	shelf.covers[1].pressed.emit()
	await _frames(3)
	who._back.pressed.emit()
	await _frames(3)
	_ok(menu.screen == "shelf" and _focused() == shelf.covers[1],
		"Back from %s refocuses %s (%s)" % [shelf.covers[1].chapter_id, shelf.covers[1].chapter_id,
		_name(_focused())])

	print("")
	if _fails == 0:
		print("NAV PROBE: PASS")
	else:
		print("NAV PROBE: %d FAILURE(S)" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)


func _focused() -> Control:
	return get_viewport().gui_get_focus_owner()


func _name(c: Control) -> String:
	return "nothing" if c == null else str(c.name)


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


func _ok(cond: bool, what: String) -> void:
	if cond:
		print("  ok   %s" % what)
	else:
		_fails += 1
		print("  FAIL %s" % what)
