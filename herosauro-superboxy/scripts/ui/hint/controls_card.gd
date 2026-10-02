class_name ControlsCard
extends Control
## The start-of-level "how to play" card. A child who has never played lands
## in a level with no idea what to press; this shows the four actions as big
## pictures for the device in their hands, says one short line, ticks each
## action off as they try it, and goes away by itself.
##
##   +-----------------------------------+
##   |   [^]        [____]   [J]   [K]   |    keyboard: real key caps
##   | [<][v][>]                          |    pad: stick + A / X / Y in colour
##   |  ANDAR      SALTAR   SOCO  PODER   |    touch: no card, pulsing rings
##   +-----------------------------------+           round the real buttons
##
## Bottom-centre, in the gap between the two hero panels, so it never covers the
## heroes or the goal. It leaves once the child has moved AND hit something, or
## after 12 s, and only on a chapter's first run (UIProgress remembers it per
## chapter): a replay never sees it again.
##
## Cheap by construction: the card is drawn once (a handful of style boxes and
## strings, cached by the canvas) and fades by modulate. Only the touch rings
## redraw per frame, and only while they show.

enum Device { KEYS, PAD, TOUCH }

## The design size; scaled down to fit the gap between the hero panels.
## The same height as the hero panels either side, so the bottom row reads as
## one band; exactly the gap between them at 1280 wide.
const BASE := Vector2(340.0, 122.0)
## Cell widths: Move holds a four-cap cluster, Jump a wide space bar.
const CELLS := [98.0, 88.0, 72.0, 72.0]
const PAD_X := 5.0
## Never wider than this share of the screen.
const MAX_SHARE := 0.35
const LIFETIME := 12.0
## How long the ticks stay up once moved + hit, before the fade.
const LINGER := 0.9
const FADE := 0.45
const SPEAK_AT := 0.5
const PREF := "coach_seen:%s"

const CAP_FACE := Color("fff3df")
const CAP_SIDE := Color("b8a98f")
const INK := Color("0a1626")
const PAD_A := Color("5cb83c")
const PAD_X_TINT := Color("2f7de1")
const PAD_Y := Color("f2bf1d")

enum Act { MOVE, JUMP, HIT, POWER }

## The HUD's touch overlay: in touch mode the rings point at its buttons.
var touch: TouchControls
## Which device the pictures show. Follows the last input event.
var device: int = Device.KEYS
## Probes and shots pin the device; -1 follows input.
var force_device: int = -1

var done: Array[bool] = [false, false, false, false]
var spoken_line: String = ""

var _open := false
## The humans at the machine, cached on begin() so the per-frame input read
## allocates nothing.
var _humans := PackedInt32Array()
var _clock := 0.0
var _dismiss_at := -1.0
var _spoke := false
var _fade: Tween
var _voice: Narrator
var _panel_box: StyleBox
var _cap_box: StyleBoxFlat
var _cap_tints: Dictionary = {}
var _font_cap: Font
var _font_word: Font
var _arrow_tri := PackedVector2Array([Vector2(0, -6), Vector2(6, 4), Vector2(-6, 4)])
var _tick_pts := PackedVector2Array([Vector2(-6, 0), Vector2(-2, 5), Vector2(7, -5)])


func _ready() -> void:
	name = "ControlsCard"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	_voice = Narrator.new()
	add_child(_voice)
	_panel_box = UIStyle.surface(UIStyle.Elev.HIGH, UIStyle.RADIUS_MD, 0)
	_cap_box = _make_cap(CAP_SIDE)
	for t: Color in [TouchControls.JUMP_TINT, TouchControls.ATTACK_TINT, TouchControls.POWER_TINT]:
		_cap_tints[t] = _make_cap(t.darkened(0.15))
	_font_cap = UIStyle.font_of(UIStyle.Scale.HEADING)
	_font_word = UIStyle.font_of(UIStyle.Scale.LABEL)
	device = Device.PAD if not Input.get_connected_joypads().is_empty() else Device.KEYS
	GameManager.settings_changed.connect(queue_redraw)
	resized.connect(queue_redraw)


static func _make_cap(side: Color) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = CAP_FACE
	b.set_corner_radius_all(9)
	b.corner_detail = 6
	b.border_color = side
	b.set_border_width_all(2)
	b.border_width_bottom = 6
	b.shadow_color = Color(0, 0, 0, 0.35)
	b.shadow_size = 2
	b.shadow_offset = Vector2(0, 2)
	return b


# --- Lifecycle -------------------------------------------------------------------

## Called by the HUD on game_started. Shows only on the chapter's first run.
func begin() -> void:
	_reset()
	var key := PREF % GameManager.chapter_id
	if bool(UIProgress.get_pref(key, false)):
		return
	UIProgress.set_pref(key, true)
	_humans.clear()
	for pid in GameManager.active_player_ids():
		if not GameManager.is_ai(pid):
			_humans.append(pid)
	_open = true
	visible = true
	modulate.a = 0.0
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", 1.0, 0.35)
	queue_redraw()


## Probes: show it regardless of what UIProgress remembers.
func force_open() -> void:
	UIProgress.set_pref(PREF % GameManager.chapter_id, false)
	begin()


func is_open() -> bool:
	return _open


func is_speaking() -> bool:
	return _voice != null and _voice.is_audible()


func _reset() -> void:
	if _fade != null:
		_fade.kill()
	_voice.stop()
	_open = false
	visible = false
	_clock = 0.0
	_dismiss_at = -1.0
	_spoke = false
	spoken_line = ""
	for i in done.size():
		done[i] = false


func dismiss() -> void:
	if not _open:
		return
	_open = false
	if _fade != null:
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", 0.0, FADE)
	_fade.tween_callback(func() -> void: visible = false)


func _current_device() -> int:
	if force_device >= 0:
		return force_device
	if touch != null and touch.is_shown():
		return Device.TOUCH
	return device


func _input(event: InputEvent) -> void:
	var was := device
	if event is InputEventKey and event.is_pressed():
		device = Device.KEYS
	elif event is InputEventJoypadButton and event.is_pressed():
		device = Device.PAD
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5:
		device = Device.PAD
	if device != was and visible:
		queue_redraw()


func _physics_process(_delta: float) -> void:
	if not _open or GameManager.state != GameManager.State.PLAYING:
		return
	var changed := false
	for pid in _humans:
		changed = _mark(Act.MOVE, InputManager.get_move_vector(pid) != Vector2.ZERO) or changed
		changed = _mark(Act.JUMP, InputManager.is_jump_just_pressed(pid)) or changed
		changed = _mark(Act.HIT, InputManager.is_attack_just_pressed(pid)) or changed
		changed = _mark(Act.POWER, InputManager.is_ability_just_pressed(pid)) or changed
	if changed:
		queue_redraw()
		if done[Act.MOVE] and done[Act.HIT] and _dismiss_at < 0.0:
			_dismiss_at = _clock + LINGER


func _mark(act: int, now: bool) -> bool:
	if not now or done[act]:
		return false
	done[act] = true
	BookKit.sfx(&"star")
	return true


func _process(delta: float) -> void:
	if not visible:
		return
	# Over the pause sheet in draw order, so it steps aside while not playing.
	self_modulate.a = 1.0 if GameManager.state == GameManager.State.PLAYING else 0.0
	if _current_device() == Device.TOUCH:
		queue_redraw()   # the rings pulse
	if not _open or GameManager.state != GameManager.State.PLAYING:
		return
	_clock += delta
	if not _spoke and _clock >= SPEAK_AT:
		_spoke = true
		spoken_line = line_for(_current_device())
		if GameManager.narration:
			_voice.speak(spoken_line, Loc.lang())
	if _clock >= LIFETIME or (_dismiss_at >= 0.0 and _clock >= _dismiss_at):
		dismiss()


static func line_for(dev: int) -> String:
	match dev:
		Device.PAD:
			return Loc.t("coach_pad")
		Device.TOUCH:
			return Loc.t("coach_touch")
	return Loc.t("coach_keys")


# --- Layout ----------------------------------------------------------------------

## The card's rect in this control's space: bottom-centre, in the gap between
## the two hero panels, never wider than MAX_SHARE of the screen.
func card_rect() -> Rect2:
	var gap := size.x - 2.0 * (UIStyle.SCREEN_MARGIN + HeroPanel.PANEL.x) - 24.0
	var w := minf(BASE.x, minf(gap, size.x * MAX_SHARE))
	var k := clampf(w / BASE.x, 0.55, 1.0)
	var dims := BASE * k
	var pos := Vector2((size.x - dims.x) * 0.5, size.y - UIStyle.SCREEN_MARGIN - dims.y)
	return Rect2(pos, dims)


# --- Drawing ---------------------------------------------------------------------

func _draw() -> void:
	if _current_device() == Device.TOUCH:
		_draw_rings()
		return
	var r := card_rect()
	var k := r.size.x / BASE.x
	draw_set_transform(r.position, 0.0, Vector2(k, k))
	draw_style_box(_panel_box, Rect2(Vector2.ZERO, BASE))
	var pad := _current_device() == Device.PAD
	var words := ["move", "jump", "hit", "special"]
	var x := PAD_X
	for i in 4:
		var cw: float = CELLS[i]
		var c := Vector2(x + cw * 0.5, 50.0)
		x += cw
		if pad:
			_draw_pad(i, c)
		else:
			_draw_keys(i, c)
		var col := UIStyle.SUCCESS if done[i] else UIStyle.TEXT_SECONDARY
		draw_string(_font_word, Vector2(c.x - cw * 0.5, 108.0), Loc.t(words[i]),
			HORIZONTAL_ALIGNMENT_CENTER, cw, UIStyle.size_of(UIStyle.Scale.LABEL), col)
		if done[i]:
			_draw_tick(c + Vector2(cw * 0.5 - 12.0, -32.0))
	draw_set_transform(Vector2.ZERO)


func _draw_keys(i: int, c: Vector2) -> void:
	match i:
		Act.MOVE:
			var s := 29.0
			var g := 2.0
			for at: Vector2 in [Vector2(0, -1), Vector2(-1, 0), Vector2(0, 0), Vector2(1, 0)]:
				var o := c + Vector2(at.x * (s + g), at.y * (s + g) + 15.0)
				draw_style_box(_cap_box, Rect2(o - Vector2(s, s) * 0.5, Vector2(s, s)))
				var rot := 0.0
				if at == Vector2(-1, 0):
					rot = -PI * 0.5
				elif at == Vector2(1, 0):
					rot = PI * 0.5
				elif at == Vector2(0, 0):
					rot = PI
				_draw_tri(o + Vector2(0, -1.5), rot, 1.15, INK)
		Act.JUMP:
			var rr := Rect2(c + Vector2(-38, -14), Vector2(76, 38))
			draw_style_box(_cap_tints[TouchControls.JUMP_TINT], rr)
			# The space bar's own glyph: an open bracket.
			var y := rr.position.y + 22.0
			draw_polyline(PackedVector2Array([Vector2(c.x - 16, y - 7), Vector2(c.x - 16, y),
				Vector2(c.x + 16, y), Vector2(c.x + 16, y - 7)]), INK, 3.0, true)
		Act.HIT:
			_letter_cap(c, "J", TouchControls.ATTACK_TINT)
		Act.POWER:
			_letter_cap(c, "K", TouchControls.POWER_TINT)


func _letter_cap(c: Vector2, letter: String, tint: Color) -> void:
	var rr := Rect2(c + Vector2(-25, -22), Vector2(50, 52))
	draw_style_box(_cap_tints[tint], rr)
	var px := 30
	var asc := _font_cap.get_ascent(px)
	draw_string(_font_cap, Vector2(rr.position.x, rr.position.y + 4.0 + (40.0 + asc * 0.72) * 0.5),
		letter, HORIZONTAL_ALIGNMENT_CENTER, rr.size.x, px, INK)


func _draw_pad(i: int, c: Vector2) -> void:
	match i:
		Act.MOVE:
			var o := c + Vector2(0, 4)
			draw_circle(o + Vector2(0, 3), 29.0, UIStyle.SHADOW)
			draw_circle(o, 29.0, Color("3a4a5e"))
			draw_arc(o, 28.0, 0.0, TAU, 40, Color("6f8399"), 2.5, true)
			for a in 4:
				var dir := Vector2.UP.rotated(a * PI * 0.5)
				_draw_tri(o + dir * 21.0, a * PI * 0.5, 0.8, Color("c9d6e4"))
			draw_circle(o + Vector2(0, 2), 14.0, Color("101a26"))
			draw_circle(o, 13.0, Color("8ea2b8"))
			draw_circle(o + Vector2(-3, -4), 5.0, Color(1, 1, 1, 0.35))
		Act.JUMP:
			_face_button(c, "A", PAD_A)
		Act.HIT:
			_face_button(c, "X", PAD_X_TINT)
		Act.POWER:
			_face_button(c, "Y", PAD_Y)


func _face_button(c: Vector2, letter: String, tint: Color) -> void:
	var o := c + Vector2(0, 4)
	draw_circle(o + Vector2(0, 3), 26.0, UIStyle.SHADOW)
	draw_circle(o, 26.0, tint.darkened(0.25))
	draw_circle(o + Vector2(0, -1.5), 23.5, tint)
	draw_circle(o + Vector2(-7, -9), 7.0, Color(1, 1, 1, 0.28))
	var px := 30
	var asc := _font_cap.get_ascent(px)
	draw_string_outline(_font_cap, Vector2(o.x - 26.0, o.y + asc * 0.36), letter,
		HORIZONTAL_ALIGNMENT_CENTER, 52.0, px, 5, Color(0, 0, 0, 0.35))
	draw_string(_font_cap, Vector2(o.x - 26.0, o.y + asc * 0.36), letter,
		HORIZONTAL_ALIGNMENT_CENTER, 52.0, px, Color.WHITE)


func _draw_tri(at: Vector2, rot: float, k: float, col: Color) -> void:
	# draw_set_transform is absolute, not nested: compose with the card's own.
	draw_set_transform_matrix(_base_xf() * Transform2D(rot, Vector2(k, k), 0.0, at))
	draw_colored_polygon(_arrow_tri, col)
	draw_set_transform_matrix(_base_xf())


func _draw_tick(at: Vector2) -> void:
	draw_circle(at + Vector2(0, 2), 13.0, UIStyle.SHADOW)
	draw_circle(at, 13.0, UIStyle.SUCCESS)
	draw_set_transform_matrix(_base_xf() * Transform2D(0.0, at))
	draw_polyline(_tick_pts, Color.WHITE, 3.5, true)
	draw_set_transform_matrix(_base_xf())


func _base_xf() -> Transform2D:
	var r := card_rect()
	var k := r.size.x / BASE.x
	return Transform2D(0.0, Vector2(k, k), 0.0, r.position)


## Touch: no card. The real buttons get a ring each until tried, spotlit one
## at a time in the order the line says them (move, jump, hit, power), so
## neighbouring rings never pile up into a muddle.
const SPOT_BEAT := 1.3


func _spot_rect(act: int) -> Rect2:
	match act:
		Act.MOVE:
			return touch.stick_hint_rect()
		Act.JUMP:
			return touch.button_global_rect(TouchControls.Role.JUMP)
		Act.HIT:
			return touch.button_global_rect(TouchControls.Role.ATTACK)
	return touch.button_global_rect(TouchControls.Role.ABILITY)


static func _spot_tint(act: int) -> Color:
	match act:
		Act.MOVE:
			return UIStyle.TEXT_PRIMARY
		Act.JUMP:
			return TouchControls.JUMP_TINT
		Act.HIT:
			return TouchControls.ATTACK_TINT
	return TouchControls.POWER_TINT


func _draw_rings() -> void:
	if touch == null:
		return
	var pending := 0
	for act in 4:
		if not done[act]:
			pending += 1
	if pending == 0:
		return
	var inv := get_global_transform().affine_inverse()
	var calm := GameManager.reduce_motion
	var t := _clock if _open else 0.0
	var lit := int(t / SPOT_BEAT) % pending
	var n := 0
	for act in 4:
		if done[act]:
			continue
		var here := n == lit
		n += 1
		var rr := _spot_rect(act)
		if rr.size.x <= 0.0:
			continue
		var centre := inv * rr.get_center()
		var base_r := rr.size.x * 0.5 + 4.0
		var col := _spot_tint(act)
		if calm:
			# Menos movimento: every pending button gets a steady ring.
			draw_arc(centre, base_r, 0.0, TAU, 48, col, 5.0, true)
			continue
		if not here:
			continue
		# Two rings walking outwards, half a beat apart: reads as "here!".
		draw_arc(centre, base_r, 0.0, TAU, 48, col, 5.0, true)
		for h in 2:
			var ph := fmod(t / SPOT_BEAT * 2.0 + h * 0.5, 1.0)
			var c2 := col
			c2.a = (1.0 - ph) * 0.95
			draw_arc(centre, base_r + ph * 22.0, 0.0, TAU, 48, c2, 6.0 - ph * 3.0, true)
