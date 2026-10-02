class_name IdleHint
extends Control
## The idle hint ladder (kid rule: positive feedback plus a hint at ~4 s and
## ~8 s). When the human hero has neither moved nor made progress for a while,
## a big, bouncy, cheerful arrow points at the next goal; a little later the
## goal is said out loud, once. Any move or any progress hides it and starts
## the ladder again.
##
##   rung 1 (SHOW_AT): the arrow. Over the goal when it is on screen, pointing
##                     down at it; on the screen edge, pointing towards it,
##                     when it is not.
##   rung 2 (SPEAK_AT): the objective is spoken (narration on only), once.
##
## The goal is `LevelBase.hint_target()` from the "level" group when finite,
## otherwise the "boss" node (the bridge). Projected with
## Camera3D.unproject_position into this canvas, which shares the viewport's
## 2D space.
##
## Never while paused, in a bubble, while a story toast is speaking, while the
## controls card is still up, or in menus. "Menos movimento": no hop, no pop,
## a steady arrow.
##
## Cheap: the arrow is one child drawn once; showing it only moves, turns and
## scales that child. Hidden, the whole thing is a few comparisons a frame.

const SHOW_AT := 4.0
const SPEAK_AT := 8.0
## Lift above a level's target (a stake, a house, a suitcase) and the giant.
const LEVEL_LIFT := Vector3(0.0, 1.9, 0.0)
const BOSS_LIFT := Vector3(0.0, 5.5, 0.0)
## The edge arrows keep clear of the HUD chrome: the goal and banner on top,
## the hero panels underneath.
const INSET := Vector2(96.0, 176.0)
const TOUCH_BOTTOM := 290.0
const HOP := 16.0
## The arrow's resting size: big enough to read from the sofa.
const SIZE := 1.2
const HOP_HZ := 1.6

## Wired by the HUD.
var card: ControlsCard
var toast: StoryToast

## Probe readouts.
var spoken_count := 0
var spoken_text := ""

var _idle := 0.0
var _spoke := false
var _showing := false
var _on_screen := false
var _t := 0.0
var _moved := false
## The ground spot under an on-screen level goal, for the pulsing ring there.
var _ground := Vector2.ZERO
var _ring := false
var _lift := Vector3.ZERO
var _humans := PackedInt32Array()
var _arrow: HintArrow
var _pop: Tween
var _voice: Narrator


func _ready() -> void:
	name = "IdleHint"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_arrow = HintArrow.new()
	add_child(_arrow)
	_arrow.visible = false
	_voice = Narrator.new()
	add_child(_voice)
	GameManager.objective_progress.connect(_on_progress)
	GameManager.objective_changed.connect(_on_objective)
	GameManager.boss_damaged.connect(_on_progress)
	GameManager.state_changed.connect(_on_state)


func _on_progress(_a: int, _b: int) -> void:
	reset()


func _on_objective(_label: Dictionary, _a: int, _b: int) -> void:
	reset()


func _on_state(_s: int) -> void:
	_hide()


## Back to the bottom of the ladder.
func reset() -> void:
	_cache_humans()
	_idle = 0.0
	_spoke = false
	_hide()


func is_showing() -> bool:
	return _showing


func idle_time() -> float:
	return _idle


## The arrow's screen-space direction (unit), and where its tip is.
func arrow_direction() -> Vector2:
	return Vector2.RIGHT.rotated(_arrow.rotation)


func arrow_tip() -> Vector2:
	return _arrow.position


func pointing_on_screen() -> bool:
	return _on_screen


func _hide() -> void:
	if not _showing:
		return
	_showing = false
	_ring = false
	queue_redraw()
	_arrow.visible = false
	if _pop != null:
		_pop.kill()
	_voice.stop()


func _physics_process(_delta: float) -> void:
	# Read here, not in _process: a virtual press is a one-physics-frame event.
	# The human roster is cached (reset() runs on every game_started), so this
	# allocates nothing per frame.
	for pid in _humans:
		if InputManager.get_move_vector(pid) != Vector2.ZERO:
			_moved = true


func _cache_humans() -> void:
	_humans.clear()
	for pid in GameManager.active_player_ids():
		if not GameManager.is_ai(pid):
			_humans.append(pid)


func _process(delta: float) -> void:
	step(delta)


## One frame of the ladder. Public so a probe can walk it without waiting.
func step(delta: float) -> void:
	var moved := _moved
	_moved = false
	if moved:
		reset()
		return
	if not _eligible():
		_hide()
		return
	_idle += delta
	if _idle < SHOW_AT:
		return
	if _bubbled():
		_hide()
		return
	var goal := _goal()
	if not goal.is_finite():
		_hide()
		return
	if not _showing:
		_show()
	_t += delta
	_place(goal)
	if _idle >= SPEAK_AT and not _spoke:
		_spoke = true
		_speak()


## Paused, bubbled, mid-story, mid-card or in a menu: hold the ladder still.
func _eligible() -> bool:
	if GameManager.state != GameManager.State.PLAYING or not is_visible_in_tree():
		return false
	if card != null and card.is_open():
		return false
	if toast != null and toast.is_speaking():
		return false
	return true


## A human hero floating in a bubble cannot go anywhere: no arrow. Asked only
## once the arrow is due, so the idle frames never walk the players group.
func _bubbled() -> bool:
	for p in get_tree().get_nodes_in_group("players"):
		var pid := int(p.get("player_id")) if "player_id" in p else 1
		if GameManager.is_ai(pid):
			continue
		if p.has_method("is_bubbled") and bool(p.is_bubbled()):
			return true
	return false


func _goal() -> Vector3:
	var lv := get_tree().get_first_node_in_group("level")
	if lv != null and lv.has_method("hint_target"):
		var t: Vector3 = lv.hint_target()
		if t.is_finite():
			_lift = LEVEL_LIFT
			return t + LEVEL_LIFT
	var boss := get_tree().get_first_node_in_group("boss") as Node3D
	if boss != null and boss.is_inside_tree():
		_lift = Vector3.ZERO   # the giant is the ring; no ground spot
		return boss.global_position + BOSS_LIFT
	return Vector3.INF


func _show() -> void:
	_showing = true
	_t = 0.0
	_arrow.visible = true
	if _pop != null:
		_pop.kill()
	if GameManager.reduce_motion:
		_arrow.scale = Vector2(SIZE, SIZE)
		_arrow.modulate.a = 0.0
		_pop = create_tween()
		_pop.tween_property(_arrow, "modulate:a", 1.0, 0.25)
	else:
		_arrow.modulate.a = 1.0
		_arrow.scale = Vector2(0.2, 0.2)
		_pop = create_tween()
		_pop.tween_property(_arrow, "scale", Vector2(SIZE, SIZE), 0.45) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Over the goal when it is on screen; on the edge, towards it, when not.
func _place(goal: Vector3) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		_arrow.visible = false
		return
	_arrow.visible = true
	var view := size
	var centre := view * 0.5
	var p := cam.unproject_position(goal)
	var behind := cam.is_position_behind(goal)
	if behind:
		p = centre - (p - centre)
	# With the touch overlay up, the bottom band belongs to the thumbs.
	var bottom := INSET.y
	if card != null and card.touch != null and card.touch.is_shown():
		bottom = TOUCH_BOTTOM
	var box := Rect2(INSET, view - Vector2(INSET.x * 2.0, INSET.y + bottom))
	var hop := 0.0 if GameManager.reduce_motion else absf(sin(_t * PI * HOP_HZ)) * HOP
	_on_screen = not behind and box.grow(40.0).has_point(p)
	var ring := _on_screen and _lift != Vector3.ZERO
	if ring:
		_ground = cam.unproject_position(goal - _lift)
	if ring or _ring:
		queue_redraw()
	_ring = ring
	if _on_screen:
		_arrow.rotation = PI * 0.5
		_arrow.position = p - Vector2(0.0, 8.0 + hop)
		return
	var d := p - centre
	if d.length_squared() < 1.0:
		d = Vector2.DOWN
	d = d.normalized()
	# Where the ray from the screen centre leaves the box (the box need not be
	# centred on it once the touch band is reserved).
	var tx := ((box.end.x if d.x > 0.0 else box.position.x) - centre.x) / d.x if absf(d.x) > 0.0001 else INF
	var ty := ((box.end.y if d.y > 0.0 else box.position.y) - centre.y) / d.y if absf(d.y) > 0.0001 else INF
	var t := maxf(minf(tx, ty), 0.0)
	_arrow.rotation = d.angle()
	_arrow.position = centre + d * (t - hop)


func _speak() -> void:
	var label := GameManager.objective_label()
	if label.is_empty():
		label = StoryData.chapter(GameManager.chapter_id).get("objective", {})
	var line := Loc.pick(label)
	if line.is_empty():
		return
	spoken_count += 1
	spoken_text = line
	if GameManager.narration:
		_voice.speak(line, Loc.lang())


## A flat gold ring on the ground under an on-screen goal: the arrow says
## "this one", the ring says "here". One arc, squashed into perspective.
func _draw() -> void:
	if not _ring:
		return
	var calm := GameManager.reduce_motion
	var k := 1.0 if calm else 1.0 + 0.12 * sin(_t * TAU * 0.8)
	draw_set_transform(_ground, 0.0, Vector2(1.0, 0.38))
	draw_arc(Vector2.ZERO, 46.0 * k, 0.0, TAU, 40, Color(0.012, 0.031, 0.055, 0.35), 12.0, true)
	draw_arc(Vector2.ZERO, 46.0 * k, 0.0, TAU, 40, UIStyle.GOLD, 7.0, true)
	draw_set_transform(Vector2.ZERO)


## A fat, friendly arrow with its tip at the origin, pointing +x. Drawn once.
class HintArrow extends Control:
	const SHAPE := [Vector2(0, 0), Vector2(-50, -44), Vector2(-50, -19), Vector2(-104, -19),
		Vector2(-104, 19), Vector2(-50, 19), Vector2(-50, 44)]
	var _pts := PackedVector2Array()
	var _shadow := PackedVector2Array()
	var _cols := PackedColorArray()
	var _closed := PackedVector2Array()

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		for v: Vector2 in SHAPE:
			_pts.append(v)
			_shadow.append(v + Vector2(-3, 6))
			# Lit from above: warm cream on the top edge, deep gold underneath.
			_cols.append(Color("ffe892") if v.y < -1.0 else (Color("ffc12b") if v.y < 1.0 else Color("f39a1c")))
		_closed = _pts.duplicate()
		_closed.append(_pts[0])

	func _draw() -> void:
		draw_colored_polygon(_shadow, Color(0.012, 0.031, 0.055, 0.45))
		draw_polygon(_pts, _cols)
		draw_polyline(_closed, UIStyle.KEYLINE, 6.0, true)
		for v in _pts:
			draw_circle(v, 3.0, UIStyle.KEYLINE)
		draw_line(Vector2(-96, -10), Vector2(-56, -10), Color(1, 1, 1, 0.55), 4.0, true)
