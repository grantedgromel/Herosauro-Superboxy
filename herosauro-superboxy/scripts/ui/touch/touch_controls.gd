class_name TouchControls
extends CanvasLayer
## On-screen controls for tablets and phones: a floating stick under the left
## thumb and three big round buttons under the right one.
##
##   +------------------------------------------------------------------+
##   | (II) [hero panels, compact]                          [goal]      |
##   |                                                                  |
##   |      left half: the stick appears                    ( * )       |
##   |      where the thumb lands                    ( ^ )  ( ! )       |
##   +------------------------------------------------------------------+
##                                                 jump  attack  power
##
## Kid rule 3 (few buttons): Move, Jump, Attack, Power and nothing else. No
## text: every button is a KidIcon pictogram (BURST = hit, BOLT = power,
## JUMP = jump). Every target is at least 100 px (kid rule 10 asks for 76).
##
## WHO IT DRIVES. `InputManager.solo_slot()`: the hero the child picked in
## solo (GameManager.human_hero), hero 1 in two-player. Everything goes through
## the public virtual channel (set_virtual_move / press_virtual /
## set_virtual_held), the same one the companion AI uses for the other brother.
##
## WHEN IT SHOWS. Only while a level is PLAYING, and only on a touch device:
## when DisplayServer reports a touchscreen at boot, or from the first
## InputEventScreenTouch. Keyboard or pad input from the same player hides it
## again (a parent picking up a pad). Headless runs (every probe) never
## auto-show it; a probe sets `force`.
##
## MOUSE EMULATION. The project emulates a mouse from touch, which is what makes
## every menu button tappable. In play that emulated left click is ALSO the
## "attack" binding, so every touch on the stick would swing a fist. While the
## overlay is live and the level is PLAYING it therefore turns
## Input.emulate_mouse_from_touch off, and puts it back for the pause sheet, the
## menus and the end card. The HUD's pause button is then pressed from here
## (`pause_target`), since no emulated click will reach it.
##
## COST. Every picture is an IconAtlas stamp, so the whole overlay is a handful
## of textured rects on one texture plus the cooldown arc: about three draw
## calls on GL Compatibility, against a ~540 whole-frame web budget.

signal active_changed(on: bool)

enum Force { AUTO, ON, OFF }
enum Role { NONE, STICK, ATTACK, ABILITY, JUMP, PAUSE }

## Probes and shots pin the overlay on or off; AUTO is the shipping behaviour.
static var force: int = Force.AUTO
## Lets AUTO detection run in a headless process. Only the touch probe sets it.
static var headless_auto: bool = false
## The project's emulate-mouse-from-touch setting, captured once per process so
## two overlays (a probe builds several HUDs) never capture each other's "off".
static var _emulation_default: int = -1

# --- Layout (canvas pixels, 1280x720 design space) -----------------------------
const BUTTON := 100.0
const BUTTON_GAP := 20.0
const EDGE := 24.0
## How far past its rim a press still counts. Half the gap, so two buttons'
## catch areas meet but never overlap.
const SLOP := 10.0
const STICK_BASE := 150.0
const STICK_KNOB := 72.0
## Knob travel from the base centre, in pixels, at full deflection.
const STICK_REACH := 60.0
## Fraction of STICK_REACH that reads as "not moving". Generous on purpose:
## small hands rest heavily and wobble.
const DEAD_ZONE := 0.25
## Past the dead zone the hero starts at this speed rather than at zero, so a
## small push is a walk the child can see, not a creep that looks broken.
const MIN_SPEED := 0.35
## Drag further than this (x reach) and the base follows the thumb.
const FOLLOW := 1.5
## Idle alpha of the resting stick hint; the live stick is fully opaque.
const IDLE_ALPHA := 0.38

const ATTACK_TINT := Color("ff6a2c")
const POWER_TINT := Color("ffc12b")
const JUMP_TINT := Color("3fa9f5")

## The HUD's pause button. A tap inside it presses it.
var pause_target: Control
## Top of the region the stick may appear in (the HUD sets it below its
## compact hero panels, so a thumb never lands on them).
var stick_top: float = 260.0

var _seen_touch := false
var _shown := false
var _pad: Control
var _stick_base: TextureRect
var _stick_knob: TextureRect
var _buttons: Dictionary = {}     # Role -> TextureRect
var _ring: _CooldownRing
## index -> Role, one entry per finger currently down.
var _fingers: Dictionary = {}
var _stick_finger := -1
var _stick_origin := Vector2.ZERO
var _stick_vec := Vector2.ZERO
var _ability := 1.0
var _hero := 1
## Every finger on the glass right now, whether or not it is ours: the
## emulation switch waits for an empty screen (see _sync_emulation).
var _down: Dictionary = {}
## True while THIS overlay has the emulation switched off.
var _holds_emulation := false


func _init() -> void:
	layer = 5
	name = "TouchControls"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _emulation_default < 0:
		_emulation_default = 1 if Input.emulate_mouse_from_touch else 0
	_pad = Control.new()
	_pad.name = "Pad"
	_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_pad)

	_stick_base = IconAtlas.sprite(_stamp_stick_base(), Vector2(STICK_BASE, STICK_BASE))
	_stick_base.name = "StickBase"
	_pad.add_child(_stick_base)
	_hero = InputManager.solo_slot()
	_stick_knob = IconAtlas.sprite(_stamp_knob(_hero_tint()), Vector2(STICK_KNOB, STICK_KNOB))
	_stick_knob.name = "StickKnob"
	_pad.add_child(_stick_knob)

	for role: int in [Role.JUMP, Role.ATTACK, Role.ABILITY]:
		var b := IconAtlas.sprite(_stamp_button(role), Vector2(BUTTON, BUTTON))
		b.name = ["", "", "Attack", "Power", "Jump"][role]
		b.pivot_offset = Vector2(BUTTON, BUTTON) * 0.5
		_pad.add_child(b)
		_buttons[role] = b
	# Last, so it draws over the button stamps and the stamps stay one batch.
	_ring = _CooldownRing.new()
	_ring.name = "CooldownRing"
	_pad.add_child(_ring)

	if force == Force.AUTO and _can_auto() and DisplayServer.is_touchscreen_available():
		_seen_touch = true
	get_viewport().size_changed.connect(_layout)
	GameManager.state_changed.connect(func(_s: int) -> void: _refresh())
	GameManager.game_started.connect(_refresh)
	_layout()
	_refresh()


func _exit_tree() -> void:
	_release_all()
	if _holds_emulation:
		Input.emulate_mouse_from_touch = true
		_holds_emulation = false


# --- Public ---------------------------------------------------------------------

## True when the controls belong on screen at all (a touch device), whether or
## not a level is running right now.
func is_active() -> bool:
	match force:
		Force.ON:
			return true
		Force.OFF:
			return false
	return _seen_touch


## True while the overlay is drawn and taking touches.
func is_shown() -> bool:
	return _shown


## Ability readiness 0..1 for the touch hero, fed by the HUD every frame from
## the same `get_ability_fraction()` its panel dial reads.
func set_ability(fraction: float) -> void:
	var f := clampf(fraction, 0.0, 1.0)
	if absf(f - _ability) < 0.004:
		return
	_ability = f
	_ring.fraction = f
	_ring.queue_redraw()
	var b: TextureRect = _buttons[Role.ABILITY]
	b.modulate = Color.WHITE if f >= 0.999 else Color(0.62, 0.62, 0.66, 1.0)


## Which hero the overlay drives right now.
func hero() -> int:
	return _hero


## Centre and radius of a button, for the layout check and the probe.
func button_rect(role: int) -> Rect2:
	var b: TextureRect = _buttons.get(role)
	return Rect2(b.position, b.size) if b != null else Rect2()


## Where the stick may appear: the left half, under `stick_top`.
func stick_zone() -> Rect2:
	var v := _view()
	return Rect2(Vector2(0.0, stick_top), Vector2(v.x * 0.5, v.y - stick_top))


## Current stick output in pad space (x right, y forward), after the dead zone.
func stick_vector() -> Vector2:
	return _stick_vec


# --- Visibility -------------------------------------------------------------------

func _can_auto() -> bool:
	return headless_auto or DisplayServer.get_name() != "headless"


func _refresh() -> void:
	var want := is_active() and GameManager.state == GameManager.State.PLAYING
	var hero_now := InputManager.solo_slot()
	if hero_now != _hero:
		_release_all()
		_hero = hero_now
		_stick_knob.texture = _stamp_knob(_hero_tint())
	if want != _shown:
		_shown = want
		if not want:
			_release_all()
		_reset_stick_hint()
		_sync_emulation()
	visible = _shown
	_pad.visible = _shown


## Touch-to-mouse emulation goes off only while a level is live under the
## overlay: the menus, the pause sheet and the end card are tapped through the
## emulated mouse. Written on transitions only, so an idle second overlay (a
## probe builds several HUDs) never undoes the live one.
##
## Switching it OFF waits until no finger is down. The engine pairs an emulated
## press with the release of the same touch; turn emulation off in between and
## that release is never translated, the left button stays down for good, and
## every later tap on a menu is swallowed. (The very first touch on AUTO is the
## case: it is pressed with emulation on, and it is what shows the overlay.)
func _sync_emulation() -> void:
	var want_off := _shown and _emulation_default != 0
	if want_off and not _holds_emulation and _down.is_empty():
		Input.emulate_mouse_from_touch = false
		_holds_emulation = true
	elif not want_off and _holds_emulation:
		Input.emulate_mouse_from_touch = true
		_holds_emulation = false


func _set_seen(on: bool) -> void:
	if _seen_touch == on:
		return
	var before := is_active()
	_seen_touch = on
	_refresh()
	if is_active() != before:
		active_changed.emit(is_active())


# --- Input --------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_down[st.index] = true
		else:
			_down.erase(st.index)
		if force == Force.AUTO and _can_auto() and not _seen_touch and st.pressed:
			_set_seen(true)
		if _down.is_empty():
			_sync_emulation()
		if not _shown:
			return
		if st.pressed:
			_press(st.index, st.position)
		else:
			_release(st.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if not _shown:
			return
		var sd := event as InputEventScreenDrag
		if _fingers.get(sd.index, Role.NONE) == Role.STICK:
			_drag(sd.position)
		get_viewport().set_input_as_handled()
	elif force == Force.AUTO and _seen_touch and _is_players_own(event):
		_set_seen(false)


## A key or pad press that belongs to the hero the overlay drives. In solo any
## key or pad does (they all drive the one hero); in two-player only player
## one's bindings do, so player two's pad does not switch the overlay off.
func _is_players_own(event: InputEvent) -> bool:
	var press := false
	if event is InputEventKey:
		press = (event as InputEventKey).pressed and not event.is_echo()
	elif event is InputEventJoypadButton:
		press = (event as InputEventJoypadButton).pressed
	elif event is InputEventJoypadMotion:
		press = absf((event as InputEventJoypadMotion).axis_value) > 0.6
	if not press:
		return false
	if GameManager.player_count <= 1:
		return true
	for a in [&"move_left", &"move_right", &"move_up", &"move_down", &"jump", &"attack",
			&"ability", &"sprint"]:
		var act := InputManager.action_name(1, a)
		if InputMap.has_action(act) and event.is_action(act):
			return true
	return false


func _press(index: int, at: Vector2) -> void:
	if _fingers.has(index):
		_release(index)
	var role := _role_at(at)
	_fingers[index] = role
	match role:
		Role.ATTACK:
			InputManager.press_virtual(_hero, &"attack")
		Role.ABILITY:
			InputManager.press_virtual(_hero, &"ability")
		Role.JUMP:
			InputManager.press_virtual(_hero, &"jump")
			InputManager.set_virtual_held(_hero, &"jump", true)
		Role.PAUSE:
			if pause_target is BaseButton:
				(pause_target as BaseButton).pressed.emit()
		Role.STICK:
			_stick_finger = index
			_stick_origin = _clamp_origin(at)
			_stick_base.modulate.a = 1.0
			_stick_knob.modulate.a = 1.0
			_drag(at)
	if _buttons.has(role):
		var b: TextureRect = _buttons[role]
		b.scale = Vector2(0.9, 0.9)
		b.self_modulate = Color(1.25, 1.25, 1.25, 1.0)


func _release(index: int) -> void:
	var role: int = _fingers.get(index, Role.NONE)
	_fingers.erase(index)
	match role:
		Role.JUMP:
			InputManager.set_virtual_held(_hero, &"jump", false)
		Role.STICK:
			_stick_finger = -1
			_stick_vec = Vector2.ZERO
			InputManager.set_virtual_move(_hero, Vector2.ZERO)
			_reset_stick_hint()
	if _buttons.has(role) and not _fingers.values().has(role):
		var b: TextureRect = _buttons[role]
		b.scale = Vector2.ONE
		b.self_modulate = Color.WHITE


func _release_all() -> void:
	for index in _fingers.keys():
		_release(index)
	_fingers.clear()
	_stick_finger = -1
	_stick_vec = Vector2.ZERO
	if _hero > 0:
		InputManager.set_virtual_move(_hero, Vector2.ZERO)
		InputManager.set_virtual_held(_hero, &"jump", false)


func _role_at(at: Vector2) -> int:
	for role: int in _buttons:
		var b: TextureRect = _buttons[role]
		var c := b.position + b.size * 0.5
		if at.distance_to(c) <= BUTTON * 0.5 + SLOP:
			return role
	if pause_target != null and pause_target.is_visible_in_tree() \
			and pause_target.get_global_rect().grow(8.0).has_point(at):
		return Role.PAUSE
	if _stick_finger < 0 and stick_zone().has_point(at):
		return Role.STICK
	return Role.NONE


func _drag(at: Vector2) -> void:
	var d := at - _stick_origin
	if d.length() > STICK_REACH * FOLLOW:
		# The thumb wandered: bring the base along rather than pinning the knob
		# at the rim while the hand drifts off across the glass.
		_stick_origin = _clamp_origin(at - d.normalized() * STICK_REACH * FOLLOW)
		d = at - _stick_origin
	var k := d / STICK_REACH
	var mag := k.length()
	var out := Vector2.ZERO
	if mag > DEAD_ZONE:
		var speed := lerpf(MIN_SPEED, 1.0, clampf((mag - DEAD_ZONE) / (1.0 - DEAD_ZONE), 0.0, 1.0))
		# Screen y grows downward; pad space's y is "forward".
		out = Vector2(k.x, -k.y).normalized() * speed
	_stick_vec = out
	InputManager.set_virtual_move(_hero, out)
	_place_stick(_stick_origin, d.limit_length(STICK_REACH))


func _clamp_origin(at: Vector2) -> Vector2:
	var v := _view()
	var r := STICK_BASE * 0.5
	return Vector2(
		clampf(at.x, EDGE + r, maxf(EDGE + r, v.x * 0.5)),
		clampf(at.y, stick_top + r, maxf(stick_top + r, v.y - EDGE - r)))


# --- Layout ---------------------------------------------------------------------------

func _view() -> Vector2:
	return _pad.get_viewport_rect().size if _pad != null and _pad.is_inside_tree() \
		else Vector2(1280, 720)


func _layout() -> void:
	var v := _view()
	var step := BUTTON + BUTTON_GAP
	# Attack in the corner (the most used), Jump to its left, Power above it.
	var attack := Vector2(v.x - EDGE - BUTTON, v.y - EDGE - BUTTON)
	_buttons[Role.ATTACK].position = attack
	_buttons[Role.JUMP].position = attack - Vector2(step, 0.0)
	_buttons[Role.ABILITY].position = attack - Vector2(0.0, step)
	_ring.position = _buttons[Role.ABILITY].position - Vector2(10, 10)
	_ring.size = Vector2(BUTTON + 20, BUTTON + 20)
	if _stick_finger < 0:
		_reset_stick_hint()


func set_stick_top(y: float) -> void:
	stick_top = y
	if _stick_finger < 0:
		_reset_stick_hint()


## The resting hint: where a thumb naturally lands, faint, so the child knows
## the left side is for walking before they have touched it.
func _reset_stick_hint() -> void:
	var v := _view()
	var r := STICK_BASE * 0.5
	var at := _clamp_origin(Vector2(EDGE + r + 56.0, v.y - EDGE - r - 40.0))
	_place_stick(at, Vector2.ZERO)
	_stick_base.modulate.a = IDLE_ALPHA
	_stick_knob.modulate.a = IDLE_ALPHA


func _place_stick(origin: Vector2, knob: Vector2) -> void:
	_stick_base.position = origin - _stick_base.size * 0.5
	_stick_knob.position = origin + knob - _stick_knob.size * 0.5


func _hero_tint() -> Color:
	return UIStyle.actor_color(UIStyle.actor_for_player(_hero))


# --- Stamps (drawn once into the IconAtlas) ------------------------------------------

static func _stamp_button(role: int) -> AtlasTexture:
	var tint: Color = {Role.ATTACK: ATTACK_TINT, Role.ABILITY: POWER_TINT, Role.JUMP: JUMP_TINT}[role]
	var kind: int = {Role.ATTACK: KidIcon.Kind.BURST, Role.ABILITY: KidIcon.Kind.BOLT,
		Role.JUMP: KidIcon.Kind.JUMP}[role]
	var icon_fill := Color("fff3df")
	var icon_accent: Color = tint
	return IconAtlas.shared().stamp("touch:button:%d" % role, Vector2(BUTTON, BUTTON),
		func(root: Control) -> void:
			var disc := _Disc.new()
			disc.tint = tint
			disc.size = Vector2(BUTTON, BUTTON)
			root.add_child(disc)
			var px := BUTTON * 0.56
			var ic := KidIcon.make(kind, px, icon_fill, icon_accent)
			ic.position = (Vector2(BUTTON, BUTTON) - Vector2(px, px)) * 0.5 + Vector2(0, -2)
			root.add_child(ic))


static func _stamp_knob(tint: Color) -> AtlasTexture:
	return IconAtlas.shared().stamp("touch:knob:%s" % tint.to_html(), Vector2(STICK_KNOB, STICK_KNOB),
		func(root: Control) -> void:
			var disc := _Disc.new()
			disc.tint = tint
			disc.size = Vector2(STICK_KNOB, STICK_KNOB)
			root.add_child(disc))


static func _stamp_stick_base() -> AtlasTexture:
	return IconAtlas.shared().stamp("touch:base", Vector2(STICK_BASE, STICK_BASE),
		func(root: Control) -> void:
			var ring := _Ring.new()
			ring.size = Vector2(STICK_BASE, STICK_BASE)
			root.add_child(ring))


## A chunky round button face: drop shadow, ink keyline, a darker lip under a
## lighter face, and a gloss. Opaque inside the keyline (IconAtlas alpha rule).
class _Disc extends Control:
	var tint := Color.WHITE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 4.0
		draw_circle(c + Vector2(0, 3.5), r, Color(0.012, 0.031, 0.055, 0.6))
		draw_circle(c, r, KidIcon.INK)
		draw_circle(c, r - 4.0, tint.darkened(0.22))
		draw_circle(c + Vector2(0, -2.5), r - 6.5, tint)
		draw_circle(c + Vector2(-r * 0.22, -r * 0.34), r * 0.34, tint.lightened(0.28))


## The stick's base: an ink ring around a cream dish with four little arrows.
## Drawn opaque; the overlay fades it with modulate.
class _Ring extends Control:
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 3.0
		draw_circle(c, r, KidIcon.INK)
		draw_circle(c, r - 5.0, Color("fff3df"))
		draw_circle(c, r - 14.0, Color("e9dcc4"))
		for i in 4:
			var a := i * PI * 0.5
			var dir := Vector2(cos(a), sin(a))
			var side := Vector2(-dir.y, dir.x)
			var tip := c + dir * (r - 10.0)
			var pts := PackedVector2Array([tip, tip - dir * 14.0 + side * 11.0,
				tip - dir * 14.0 - side * 11.0])
			draw_colored_polygon(pts, KidIcon.INK)


## The Power button's cooldown: a sweep that fills clockwise from twelve
## o'clock while the power recharges, gone when it is ready. Redrawn only when
## the fraction moves.
class _CooldownRing extends Control:
	var fraction := 1.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if fraction >= 0.999:
			return
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 6.0
		draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU, 48, Color(0.016, 0.043, 0.078, 0.7), 9.0, true)
		draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * fraction, 48, POWER_TINT, 6.0, true)
