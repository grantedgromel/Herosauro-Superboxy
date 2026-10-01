class_name ObjectiveWidget
extends Control
## What the chapter asks, in the corner of the HUD: a sentence in the current
## language ("Recupera as taças!") and one big pip per step, filled as the
## level reports progress through GameManager.objective_progress. Each step
## pops and plays the star sound; the last one plays objective_done. The goal
## is read aloud once when it first appears (if Narração is on).
##
## A level with no counted goal (the bridge fight) still gets the sentence:
## with total 0 there are no pips and the boss bar is the progress.

const W := 300.0
const PIP := 32.0
const MAX_PIPS := 6

var label_entry: Dictionary = {}
var done: int = 0
var total: int = 0

var _plate: Panel
var _icon: KidIcon
var _text: Label
var _pips: HBoxContainer
var _count: Label
var _voice: Narrator
var _spoken := false
var _pop := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate = UIStyle.plate(UIStyle.GOLD, 0.06, UIStyle.RADIUS_LG, UIStyle.Elev.HIGH)
	_plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_plate)
	_icon = KidIcon.make(KidIcon.Kind.STAR, 54, BookKit.SUN)
	_icon.position = Vector2(14, 14)
	add_child(_icon)
	_text = UIStyle.text("", UIStyle.Scale.SUBHEAD, UIStyle.TEXT_PRIMARY, HORIZONTAL_ALIGNMENT_LEFT)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.add_theme_font_size_override("font_size", 22)
	BookKit.place(_text, Vector2(76, 10), Vector2(W - 90, 60))
	add_child(_text)
	_pips = HBoxContainer.new()
	_pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pips.add_theme_constant_override("separation", 4)
	_pips.position = Vector2(16, 74)
	add_child(_pips)
	_count = UIStyle.text("", UIStyle.Scale.READOUT, UIStyle.GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	_count.position = Vector2(W - 70, 74)
	_count.size = Vector2(58, 34)
	add_child(_count)
	_voice = Narrator.new()
	add_child(_voice)
	size = Vector2(W, 82)
	custom_minimum_size = size
	visible = false
	GameManager.settings_changed.connect(_refresh_text)


## A new goal (objective_changed). Shown, and spoken once.
func set_objective(label: Dictionary, d: int, t: int) -> void:
	label_entry = label
	total = maxi(0, t)
	done = clampi(d, 0, total) if total > 0 else 0
	_rebuild_pips()
	_refresh_text()
	visible = not label.is_empty()
	if visible and not _spoken and GameManager.narration:
		_spoken = true
		_voice.speak(Loc.pick(label_entry), Loc.lang())


func set_progress(d: int, t: int) -> void:
	var before := done
	if t != total:
		total = maxi(0, t)
		_rebuild_pips()
	done = clampi(d, 0, total)
	_paint()
	if done > before:
		_pop = 1.0
		pivot_offset = size * 0.5
		BookKit.sfx(&"objective_done" if done >= total and total > 0 else &"star")
		if _pips.get_child_count() > 0 and not BookKit.reduce_motion():
			var last := _pips.get_child(clampi(lit_count(), 1, _pips.get_child_count()) - 1) as Control
			last.pivot_offset = last.size * 0.5
			last.scale = Vector2(1.8, 1.8)
			create_tween().tween_property(last, "scale", Vector2.ONE, 0.35) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func reset() -> void:
	label_entry = {}
	done = 0
	total = 0
	_spoken = false
	_voice.stop()
	visible = false
	_rebuild_pips()


func filled_pips() -> int:
	var n := 0
	for c in _pips.get_children():
		if c.get_meta("lit", false):
			n += 1
	return n


func pip_count() -> int:
	return _pips.get_child_count()


## Pips lit for the current progress. More steps than pips (a long goal):
## each pip stands for a share of them.
func lit_count() -> int:
	var shown := _pips.get_child_count()
	if total <= MAX_PIPS:
		return mini(done, shown)
	return int(floor(float(done) * shown / maxf(1.0, total)))


func label_text() -> String:
	return _text.text


func _refresh_text() -> void:
	_text.text = Loc.pick(label_entry)
	_paint()


func _rebuild_pips() -> void:
	for c in _pips.get_children():
		_pips.remove_child(c)
		c.queue_free()
	var shown := mini(total, MAX_PIPS)
	for i in shown:
		var ic := KidIcon.make(KidIcon.Kind.STAR_EMPTY, PIP)
		_pips.add_child(ic)
	var h := 82.0 if total <= 0 else 120.0
	size = Vector2(W, h)
	custom_minimum_size = size
	_paint()


func _paint() -> void:
	var shown := _pips.get_child_count()
	var lit := lit_count()
	for i in shown:
		var ic := _pips.get_child(i) as KidIcon
		var on := i < lit
		ic.set_meta("lit", on)
		ic.set_kind(KidIcon.Kind.STAR if on else KidIcon.Kind.STAR_EMPTY)
		ic.set_fill(BookKit.SUN)
	_count.visible = total > 0
	_count.text = "%d/%d" % [done, total]


func _process(delta: float) -> void:
	if _pop <= 0.0:
		return
	_pop = maxf(0.0, _pop - delta * 3.0)
	var k := 1.0 + 0.08 * sin(_pop * PI)
	scale = Vector2(k, k) if not BookKit.reduce_motion() else Vector2.ONE
