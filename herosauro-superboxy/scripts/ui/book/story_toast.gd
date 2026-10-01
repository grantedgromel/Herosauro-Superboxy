class_name StoryToast
extends Control
## A story beat during play: a hero's face, a line from the book and its voice,
## sliding in at the top of the screen. It never blocks play (it ignores the
## mouse and takes no input) and leaves on its own once the narration ends, or
## after ~6 s when Narração is off. Beats that arrive while one is showing
## wait their turn.

## Kept small: it sits over the top of the play view while the narrator
## reads it, and the face plus three short lines is all it needs.
const W := 640.0
const H := 112.0
const FACE := 84.0
const HOLD_SILENT := 6.0
const HOLD_AFTER_VOICE := 1.2
const HOLD_MAX := 14.0

var beat_id: String = ""
var queue: Array[Dictionary] = []

var _plate: Panel
var _face: PortraitFrame
var _text: Label
var _voice: Narrator
var _clock := 0.0
var _showing := false
var _voice_done := false
var _done_at := 0.0
var _narrated := false
var _tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(W, H)
	_plate = Panel.new()
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.add_theme_stylebox_override("panel", BookKit.paper_box(30, 0))
	_plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_plate)
	# Live, not an atlas stamp: the speaker changes from beat to beat, the toast
	# is up for a few seconds at a time, and three 112 px portraits would take a
	# seventh of the atlas for two draw calls saved while one shows.
	_face = PortraitFrame.new()
	_face.custom_minimum_size = Vector2(FACE, FACE)
	_face.size = Vector2(FACE, FACE)
	_face.position = Vector2(14, (H - FACE) * 0.5)
	add_child(_face)
	_text = BookKit.print_label("", 24, true, BookKit.PRINT, HORIZONTAL_ALIGNMENT_LEFT)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	BookKit.place(_text, Vector2(FACE + 30, 8), Vector2(W - FACE - 46, H - 16))
	add_child(_text)
	_voice = Narrator.new()
	add_child(_voice)
	_voice.finished.connect(func() -> void:
		_voice_done = true
		_done_at = _clock)
	visible = false
	GameManager.settings_changed.connect(_refresh_text)


## Show a StoryData beat ({id, pt, en}). Queued behind one already showing.
func show_beat(beat: Dictionary) -> void:
	if beat.is_empty():
		return
	if _showing:
		queue.append(beat)
		return
	_begin(beat)


## True while the toast's line is being read aloud: the idle hint holds still.
func is_speaking() -> bool:
	return _showing and _narrated and not _voice_done


func is_showing() -> bool:
	return _showing


func clear() -> void:
	queue.clear()
	_voice.stop()
	_showing = false
	beat_id = ""
	visible = false


func text() -> String:
	return _text.text


func _begin(beat: Dictionary) -> void:
	beat_id = str(beat.get("id", ""))
	set_meta("beat", beat)
	var who := BookKit.cast_in(Loc.pick(beat, "pt") + " " + Loc.pick(beat, "en"))
	who.erase("adamastor")
	_face.set_actor(BookKit.actor_of(who[0]) if not who.is_empty() else UIStyle.Actor.HEROSAURO)
	_refresh_text()
	_showing = true
	_voice_done = false
	_clock = 0.0
	visible = true
	_narrated = GameManager.narration
	if _narrated:
		_voice.speak(Loc.pick(beat), Loc.lang(), beat_id)
	BookKit.sfx(&"page_turn")
	_slide(true)


func _refresh_text() -> void:
	if has_meta("beat"):
		_text.text = Loc.pick(get_meta("beat"))
		var long := _text.text.length() > 120
		# Never under 20 px at 720p (the kids' floor is 28 px at 1080p).
		_text.add_theme_font_size_override("font_size", 20 if long else 24)


func _slide(entering: bool) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if BookKit.reduce_motion():
		modulate.a = 1.0 if entering else 0.0
		if not entering:
			visible = false
		return
	_tween = create_tween().set_parallel(true)
	if entering:
		modulate.a = 0.0
		_plate.position.y = -40.0
		_tween.tween_property(self, "modulate:a", 1.0, 0.25)
		_tween.tween_property(_plate, "position:y", 0.0, 0.35).set_trans(Tween.TRANS_BACK) \
			.set_ease(Tween.EASE_OUT)
	else:
		_tween.tween_property(self, "modulate:a", 0.0, 0.3)
		_tween.chain().tween_callback(func() -> void: visible = _showing)


func _process(delta: float) -> void:
	if not _showing:
		return
	_clock += delta
	var spoken := _voice_done and _clock >= _done_at + HOLD_AFTER_VOICE
	if not _narrated:
		spoken = _clock >= HOLD_SILENT
	if spoken or _clock >= HOLD_MAX:
		_end()


func _end() -> void:
	_showing = false
	_voice.stop()
	_slide(false)
	if not queue.is_empty():
		var nxt: Dictionary = queue.pop_front()
		_begin(nxt)
