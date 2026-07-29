extends Control
## The main menu's action column: START, DIFFICULTY, CONTROLS, CREDITS, QUIT.
##
## Laid out by hand rather than in a VBoxContainer. The entry animation slides
## every row in from the left, and a Container owns its children's positions —
## fighting one over a tween is how you get a menu that jitters on the first
## frame after a resize.
##
## Navigation is wired three ways on purpose, because a title screen is the one
## screen a player might reach with any input device already in their hand:
##   * arrow keys and D-pad / left stick, through the engine's own ui_* actions
##     and explicit wrapping focus neighbours;
##   * W and S, because a player who has just been told the game is WASD will
##     try WASD (keyboard events only — the stick already arrives as ui_up/down,
##     and accepting both would step two rows at a time);
##   * the mouse, where hovering a row TAKES focus rather than lighting a second
##     highlight next to the keyboard's one.

## Typed through the preload rather than a `class_name`: the menu's parts are
## private to this screen and there is no reason for them to appear in every
## other script's global namespace.
const MenuRow := preload("res://scripts/ui/menu/menu_row.gd")

signal activated(id: StringName)
signal difficulty_changed(index: int)

const ROW_HEIGHT := 52.0
## Was 6. A five-item column at 58 px pitch reads as a dense list of settings;
## the same five at 72 read as the five things this screen is for. The whole
## column still clears the hint row at 720p, which is what caps it here.
const ROW_GAP := 20.0
## Floor for the negotiated gap. Below this the column stops reading as a spaced
## list and starts reading as a table, which is the look this pass is undoing.
const MIN_ROW_GAP := 8.0
const ENTRY_SLIDE := 38.0
const ENTRY_TIME := 0.42

var _rows: Array[MenuRow] = []
var _difficulty_row: MenuRow
var _locked: bool = false
var _ui_scale: float = 1.0
var _gap: float = ROW_GAP
## The vertical budget the screen last gave us, remembered rather than passed
## through every time. `resized` is wired straight to relayout(), so setting the
## column's size from the screen re-enters with the default arguments — and an
## unremembered budget meant that re-entry reset the gap to its full value and
## overflowed the column back over the key legend, immediately after the screen
## had just sized it to fit. -1.0 means "never been told", i.e. unbounded.
var _available: float = -1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tiers: Array[Color] = [UIStyle.SUCCESS, UIStyle.GOLD, UIStyle.DANGER]
	_add_row(&"start", "START")
	_difficulty_row = _add_row(&"difficulty", "DIFFICULTY", MenuRow.Kind.OPTION,
			PackedStringArray(["EASY", "NORMAL", "HARD"]), tiers, GameManager.difficulty)
	_add_row(&"controls", "CONTROLS")
	_add_row(&"credits", "CREDITS")
	# The web export has nowhere to quit to, and a dead menu entry is worse than
	# a missing one.
	if not OS.has_feature("web"):
		_add_row(&"quit", "QUIT")

	_wire_focus()
	resized.connect(relayout)
	relayout()


func _add_row(id: StringName, caption: String, kind: int = MenuRow.Kind.ACTION,
		options: PackedStringArray = PackedStringArray(),
		colors: Array[Color] = [], start: int = 0) -> MenuRow:
	var row := MenuRow.new()
	add_child(row)
	row.setup(id, caption, kind, options, colors, start)
	row.pressed.connect(_on_pressed.bind(row))
	if kind == MenuRow.Kind.OPTION:
		row.value_changed.connect(func(i: int) -> void: difficulty_changed.emit(i))
	_rows.append(row)
	return row


## Explicit, wrapping neighbours. The engine's geometric fallback would work for
## a straight column, but it stops dead at the ends; wrapping is what makes a
## five-item menu feel like a dial rather than a list.
func _wire_focus() -> void:
	var n := _rows.size()
	for i in n:
		var up := _rows[(i - 1 + n) % n].get_path()
		var down := _rows[(i + 1) % n].get_path()
		_rows[i].focus_neighbor_top = up
		_rows[i].focus_neighbor_bottom = down
		_rows[i].focus_previous = up
		_rows[i].focus_next = down
		# Left and right belong to the difficulty row, never to navigation.
		_rows[i].focus_neighbor_left = _rows[i].get_path()
		_rows[i].focus_neighbor_right = _rows[i].get_path()


# --- Layout ------------------------------------------------------------------

## `available` is the vertical room the screen actually has for the column, in
## pixels. Pass -1.0 for "as much as it wants".
##
## The gap is negotiated rather than fixed. ROW_GAP is what the design asks for;
## if the logo and the hint row do not leave that much, it compresses toward
## MIN_ROW_GAP instead of overflowing. Before this, widening the gap silently
## pushed QUIT underneath the key legend at 720p — the column had no idea what
## was above or below it.
func relayout(ui_scale: float = -1.0, available: float = -1.0) -> void:
	if ui_scale > 0.0:
		_ui_scale = ui_scale
	if available > 0.0:
		_available = available
	_gap = _fit_gap(_available)
	var h := ROW_HEIGHT * _ui_scale
	var y := 0.0
	for row in _rows:
		row.rescale(_ui_scale)
		row.position = Vector2(0.0, y)
		row.size = Vector2(size.x, h)
		y += h + _gap


func _fit_gap(available: float) -> float:
	var want := ROW_GAP * _ui_scale
	if available <= 0.0 or _rows.size() < 2:
		return want
	var rows_h := _rows.size() * ROW_HEIGHT * _ui_scale
	var spare := (available - rows_h) / float(_rows.size() - 1)
	return clampf(spare, MIN_ROW_GAP * _ui_scale, want)


## Total height the column needs, so the screen can stack things under it.
## Reads the negotiated gap, so it agrees with what relayout actually laid out.
func column_height() -> float:
	return _rows.size() * ROW_HEIGHT * _ui_scale + (_rows.size() - 1) * _gap


# --- Interaction -------------------------------------------------------------

func _on_pressed(row: MenuRow) -> void:
	if _locked:
		return
	if row.kind == MenuRow.Kind.OPTION:
		row.step(1)
		return
	activated.emit(row.id)


## Swallows input and drops focus while a modal is up or the screen is leaving.
## Focus mode is cleared as well as the flag, otherwise Tab still walks into a
## column the player cannot see.
func set_locked(locked: bool) -> void:
	_locked = locked
	set_process_unhandled_input(not locked)
	for row in _rows:
		row.focus_mode = Control.FOCUS_NONE if locked else Control.FOCUS_ALL


func focus_row(id: StringName) -> void:
	for row in _rows:
		if row.id == id:
			row.grab_focus()
			return
	focus_first()


func focus_first() -> void:
	if not _rows.is_empty():
		_rows[0].grab_focus()


func focused_id() -> StringName:
	for row in _rows:
		if row.has_focus():
			return row.id
	return &""


## Keeps the difficulty pills honest if anything else changes GameManager.
func sync_difficulty(index: int) -> void:
	if _difficulty_row != null:
		_difficulty_row.set_index(index, false)


func _unhandled_input(event: InputEvent) -> void:
	if _locked or not is_visible_in_tree() or not (event is InputEventKey):
		return
	if event.is_action_pressed("move_up", true):
		_step_focus(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_down", true):
		_step_focus(1)
		get_viewport().set_input_as_handled()


func _step_focus(delta: int) -> void:
	if _rows.is_empty():
		return
	var at := 0
	for i in _rows.size():
		if _rows[i].has_focus():
			at = i
			break
	_rows[wrapi(at + delta, 0, _rows.size())].grab_focus()


# --- Entry -------------------------------------------------------------------

func play_entry(delay: float, stagger: float) -> void:
	for i in _rows.size():
		var row := _rows[i]
		row.modulate.a = 0.0
		var tw := row.create_tween().set_parallel(true)
		var wait := delay + stagger * float(i)
		tw.tween_property(row, "modulate:a", 1.0, ENTRY_TIME).set_delay(wait)
		tw.tween_property(row, "position:x", 0.0, ENTRY_TIME).from(-ENTRY_SLIDE) \
				.set_delay(wait).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
