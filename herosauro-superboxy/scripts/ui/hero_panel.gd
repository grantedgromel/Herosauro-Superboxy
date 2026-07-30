class_name HeroPanel
extends Control
## One hero's whole status, as a single moulded object.
##
## The game is two-player co-op, so the HUD carries two of these — one in each
## bottom corner, mirror images of each other. That symmetry is the design:
##
##     ┌───────────────────────────┐      ┌───────────────────────────┐
##     │ ▣  P1 HEROSAURO       ( ◔)│      │(◔ )       SUPER BOXY P2  ▣│
##     │    ▐███████ 84/100▌ SPECIAL│     │SPECIAL ▐100/100 ███████▌  │
##     │    ▪ INVINCIBLE           │      │           INVINCIBLE ▪    │
##     └───────────────────────────┘      └───────────────────────────┘
##
## Player one on the left, player two on the right, identical in size, identical
## in content, each with its portrait on the OUTSIDE edge so both heroes face in
## toward the fight. A stacked "P1 big / P2 small" arrangement is the usual
## shortcut and it tells player two they are a guest in player one's game.
##
## The panel is opaque. It is a plate with a keyline, a bevel and a drop shadow,
## and nothing behind it is dimmed to make it readable — over bright saturated
## daylight, a solid object is legible where a translucent one is a window onto
## whatever is currently blowing out behind the hero.
##
## It knows nothing about players. Everything visible here is driven by the HUD
## from `GameManager.player_damaged` / `player_respawned`, plus an ability
## fraction the HUD reads off the `players` group. That is the whole interface.

## Design size. Both panels are exactly this, at both ends of the screen.
const PANEL := Vector2(430.0, 122.0)
const AVATAR := 84.0
const BAR_H := 28.0
const DIAL := 62.0
const PAD := 14.0
## Gutter between the portrait and the text column, and between the text column
## and the dial. Wider than SPACE_MD because the portrait has its own rim.
const GUTTER := 16.0

## Health fraction under which the name and the readout go warning-coloured.
const LOW_RATIO := 0.28
## Rate the panel's own accent glow decays after a hit, per second.
const HIT_LAMBDA := 4.5

var player_id: int = 1
var actor: int = UIStyle.Actor.HEROSAURO
var accent: Color = UIStyle.HERO_GREEN
## True for player two: the whole layout is mirrored about the panel's centre.
var mirrored: bool = false

var _plate: Panel
var _face: PortraitFrame
var _name: Label
var _tag: PanelContainer
var _hp: Label
var _bar: StatBar
var _dial: AbilityDial
var _dial_cap: Label
var _status: PanelContainer
var _status_label: Label
var _down_veil: ColorRect

## Decaying 0..1 used for the hit rim glow. Integrated from delta, never read off
## the wall clock, so a capture at a fixed frame rate is reproducible.
var _hit: float = 0.0
var _pulse: float = 0.0
var _status_kind: int = 0        # 0 none, 1 invincible, 2 down
## Resting x, captured the first time the panel recoils. Two hits inside one
## recoil would otherwise let the second tween record the shoved position as
## home and walk the panel off its gutter, one hit at a time.
var _rest_x: float = INF
var _recoil: Tween


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = PANEL


## Build the panel for a hero. Call once, before or after entering the tree.
func setup(id: int, right_hand: bool) -> void:
	player_id = id
	mirrored = right_hand
	actor = UIStyle.actor_for_player(id)
	accent = UIStyle.actor_color(actor)
	size = PANEL

	_plate = UIStyle.plate(accent, 0.13, UIStyle.RADIUS_LG, UIStyle.Elev.HIGH)
	_plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_plate)

	# A solid bar of the hero's colour down the outside edge. It is the fastest
	# possible answer to "which of these two is me" — readable from the corner of
	# the eye, at any distance, with no text involved.
	var spine := Panel.new()
	spine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var spine_box := StyleBoxFlat.new()
	spine_box.bg_color = accent
	spine_box.set_corner_radius_all(3)
	spine.add_theme_stylebox_override("panel", spine_box)
	_place(spine, Vector2(4.0, 14.0), Vector2(6.0, PANEL.y - 28.0))

	_face = PortraitFrame.new()
	_face.actor = actor
	_place(_face, Vector2(PAD + 6.0, (PANEL.y - AVATAR) * 0.5), Vector2(AVATAR, AVATAR))

	var text_x := PAD + 6.0 + AVATAR + GUTTER
	var dial_x := PANEL.x - PAD - DIAL
	var text_w := dial_x - GUTTER - text_x

	_tag = UIStyle.pill("P%d" % player_id, accent, UIStyle.BASE, UIStyle.Scale.MICRO)
	_place(_tag, Vector2(text_x, 12.0), Vector2(34.0, 22.0))

	_name = UIStyle.text(UIStyle.actor_name(actor), UIStyle.Scale.SUBHEAD,
		UIStyle.TEXT_PRIMARY, _lead_align())
	_place(_name, Vector2(text_x + 42.0, 9.0), Vector2(text_w - 42.0, 28.0))

	_bar = StatBar.new()
	_bar.mirrored = mirrored
	_bar.setup(StatBar.Variant.HERO, float(GameManager.MAX_PLAYER_HEALTH), accent, 4)
	_place(_bar, Vector2(text_x, 44.0), Vector2(text_w, BAR_H))

	# The numbers ride INSIDE the bar rather than beside it. There is not room for
	# both a readable name and a readable readout on one line at this width, and
	# putting the count on the thing it counts is what a console HUD does anyway —
	# it survives because every glyph carries the kit's ink keyline.
	_hp = UIStyle.text("100/100", UIStyle.Scale.LABEL, UIStyle.TEXT_PRIMARY, _trail_align())
	_place(_hp, Vector2(text_x + 8.0, 44.0), Vector2(text_w - 16.0, BAR_H))

	_status = UIStyle.pill("INVINCIBLE", UIStyle.GOLD, UIStyle.BASE, UIStyle.Scale.MICRO)
	_status_label = _status.get_child(0) as Label
	_place(_status, Vector2(text_x, 80.0), Vector2(124.0, 22.0))
	_status.visible = false

	_dial = AbilityDial.new()
	_place(_dial, Vector2(dial_x, 10.0), Vector2(DIAL, DIAL))
	_dial.setup("E", accent)

	_dial_cap = UIStyle.text("SPECIAL", UIStyle.Scale.MICRO, UIStyle.TEXT_SECONDARY,
		HORIZONTAL_ALIGNMENT_CENTER)
	_place(_dial_cap, Vector2(dial_x - 14.0, 76.0), Vector2(DIAL + 28.0, 16.0))

	# Drawn over everything and normally invisible: a hero at zero health is out
	# of the fight and the panel has to say so louder than a dimmed portrait can.
	_down_veil = ColorRect.new()
	_down_veil.color = Color(UIStyle.BASE.r, UIStyle.BASE.g, UIStyle.BASE.b, 0.55)
	_down_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_down_veil.visible = false
	_place(_down_veil, Vector2(3.0, 3.0), Vector2(PANEL.x - 6.0, PANEL.y - 6.0))

	set_process(false)


## Mirrors a child's placement for player two. Children are positioned in
## left-handed coordinates and reflected here, so there is exactly one layout in
## the file and no chance of the two panels drifting apart.
func _place(ctrl: Control, pos: Vector2, dims: Vector2) -> void:
	add_child(ctrl)
	ctrl.set_anchors_preset(Control.PRESET_TOP_LEFT)
	var x := PANEL.x - pos.x - dims.x if mirrored else pos.x
	ctrl.position = Vector2(x, pos.y)
	ctrl.size = dims


func _lead_align() -> int:
	return HORIZONTAL_ALIGNMENT_RIGHT if mirrored else HORIZONTAL_ALIGNMENT_LEFT


func _trail_align() -> int:
	return HORIZONTAL_ALIGNMENT_LEFT if mirrored else HORIZONTAL_ALIGNMENT_RIGHT


# --- State --------------------------------------------------------------------

## New health. `hit` is false for the sync push at the start of a run and for
## heals, so the bar does not fake damage the player did not take.
func set_health(new_health: int, hit: bool) -> void:
	_bar.set_value(float(new_health), hit)
	_hp.text = "%d/%d" % [new_health, GameManager.MAX_PLAYER_HEALTH]

	var ratio := float(new_health) / float(GameManager.MAX_PLAYER_HEALTH)
	# The readout goes warning-coloured at the same threshold the bar starts to
	# throb, so the danger state is stated twice — once in a form you read and
	# once in a form you catch out of the corner of your eye.
	_hp.add_theme_color_override("font_color",
		UIStyle.WARNING if ratio <= LOW_RATIO else UIStyle.TEXT_PRIMARY)

	var down := new_health <= 0
	_down_veil.visible = down
	_face.set_dimmed(down)
	if down:
		_set_status(2, "DOWN", UIStyle.DANGER)
	elif _status_kind == 2:
		_set_status(0, "", UIStyle.GOLD)


## One hit landed on this hero. Flashes the portrait, glows the rim and gives the
## whole panel a short recoil — the UI half of the impact contract.
func take_hit(amount: int) -> void:
	_face.hit_flash()
	_hit = clampf(0.5 + float(amount) / 26.0, 0.5, 1.0)
	set_process(true)

	if _recoil != null and _recoil.is_valid():
		_recoil.kill()
	if is_inf(_rest_x):
		_rest_x = position.x
	position.x = _rest_x

	# Recoil away from the centre of the screen: the panel is being shoved by the
	# blow, and it squashes on the way. Pivot is the panel's own centre so the
	# squash never drags a corner across the screen gutter.
	pivot_offset = size * 0.5
	var shove := 10.0 * (1.0 if mirrored else -1.0)
	_recoil = create_tween()
	_recoil.tween_property(self, "scale", Vector2(1.05, 0.94), 0.06) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_recoil.parallel().tween_property(self, "position:x", _rest_x + shove, 0.06)
	_recoil.tween_property(self, "scale", Vector2.ONE, 0.34) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_recoil.parallel().tween_property(self, "position:x", _rest_x, 0.34) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Back on their feet after going over the side.
##
## Re-reads the authoritative health table rather than assuming full health: a
## respawn in this game costs a fall penalty and does NOT heal, so a panel that
## reset itself here would lie about the state of the run.
func revive() -> void:
	set_health(int(GameManager.player_health.get(player_id, GameManager.MAX_PLAYER_HEALTH)), false)
	_hit = 1.0
	set_process(true)
	pivot_offset = size * 0.5
	var t := create_tween()
	t.tween_property(self, "scale", Vector2(1.07, 1.07), 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "scale", Vector2.ONE, 0.30) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Wipe every trace of the last run.
func reset() -> void:
	_bar.reset_to(float(GameManager.MAX_PLAYER_HEALTH))
	_hp.text = "%d/%d" % [GameManager.MAX_PLAYER_HEALTH, GameManager.MAX_PLAYER_HEALTH]
	_hp.add_theme_color_override("font_color", UIStyle.TEXT_PRIMARY)
	_face.set_dimmed(false)
	_down_veil.visible = false
	_set_status(0, "", UIStyle.GOLD)
	_hit = 0.0
	if _recoil != null and _recoil.is_valid():
		_recoil.kill()
	if not is_inf(_rest_x):
		position.x = _rest_x
	scale = Vector2.ONE
	modulate = Color.WHITE
	_plate.modulate = Color.WHITE


## Ability cooldown, 0..1, fed straight from the hero's own readout.
func set_ability(fraction: float) -> void:
	_dial.set_fraction(fraction)
	_dial_cap.modulate.a = 1.0 if _dial.is_ready() else 0.55


## Invulnerability frames. Ignored while the hero is down — DOWN is the louder
## message and two pills fighting for the same slot reads as a bug.
func set_invulnerable(on: bool) -> void:
	if _status_kind == 2:
		return
	if on and _status_kind != 1:
		_set_status(1, "INVINCIBLE", UIStyle.GOLD)
	elif not on and _status_kind == 1:
		_set_status(0, "", UIStyle.GOLD)


func _set_status(kind: int, body: String, tint: Color) -> void:
	_status_kind = kind
	_status.visible = kind != 0
	if kind == 0:
		return
	_status_label.text = body
	var sb := _status.get_theme_stylebox("panel") as StyleBoxFlat
	if sb:
		sb.bg_color = tint
	set_process(true)


func _process(delta: float) -> void:
	_pulse += delta
	if _hit > 0.0:
		_hit = maxf(0.0, _hit - _hit * HIT_LAMBDA * delta - delta * 0.25)
		# The whole plate warms toward the hero's colour and cools back. Cheaper
		# and more legible than a border animation, and it reads at the size the
		# panel actually is on screen.
		var glow := 1.0 + 0.55 * _hit
		_plate.modulate = Color(glow, glow, glow, 1.0)
	elif _plate.modulate != Color.WHITE:
		_plate.modulate = Color.WHITE

	if _status_kind == 1:
		# Only the invincibility pill blinks. DOWN is a steady state and a
		# flashing "DOWN" would read as a warning that something is broken.
		_status.modulate.a = 0.55 + 0.45 * absf(sin(_pulse * 7.0))
	elif _status.visible:
		_status.modulate.a = 1.0

	if _hit <= 0.0 and _status_kind != 1:
		set_process(false)
