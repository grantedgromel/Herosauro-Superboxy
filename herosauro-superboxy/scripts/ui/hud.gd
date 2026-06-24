extends Control
## In-game HUD: health bars (P1 left, P2 right, boss centre), ability cooldown
## bars, score, fight timer, P2 combo counter, i-frame indicators and the pause
## overlay. Health/score/combo/timer are pushed via GameManager signals; the
## ability fills and i-frame pulses are polled from the player nodes each frame.

const SHADOW := Color(0.0, 0.0, 0.0, 0.85)
const P1_FILL := Color(0.36, 0.82, 0.26)
const P2_FILL := Color(0.9, 0.27, 0.27)
const BOSS_FILL := Color(0.55, 0.33, 0.16)
const DINO_FILL := Color(0.3, 0.9, 0.4)
const DASH_FILL := Color(0.95, 0.8, 0.25)

var _p1_bar: ProgressBar
var _p2_bar: ProgressBar
var _boss_bar: ProgressBar
var _dino_bar: ProgressBar
var _dash_bar: ProgressBar
var _score_label: Label
var _timer_label: Label
var _combo_label: Label
var _dino_label: Label
var _dash_label: Label
var _p1_shield: Label
var _p2_shield: Label
var _pause_overlay: Control

var _pulse: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# --- Health bars ---
	_add_label("🦖 HEROSAURO (Rui)", 18, Control.PRESET_TOP_LEFT, Vector2(24, 16), Vector2(320, 24))
	_p1_bar = _add_bar(P1_FILL, 100, Control.PRESET_TOP_LEFT, Vector2(24, 42), Vector2(300, 24))
	_p1_shield = _add_label("🛡", 22, Control.PRESET_TOP_LEFT, Vector2(330, 40), Vector2(40, 30))
	_p1_shield.visible = false

	_add_label("🥊 SUPER BOXY (Kiko)", 18, Control.PRESET_TOP_RIGHT, Vector2(-344, 16), Vector2(320, 24), HORIZONTAL_ALIGNMENT_RIGHT)
	_p2_bar = _add_bar(P2_FILL, 100, Control.PRESET_TOP_RIGHT, Vector2(-324, 42), Vector2(300, 24))
	_p2_shield = _add_label("🛡", 22, Control.PRESET_TOP_RIGHT, Vector2(-370, 40), Vector2(40, 30))
	_p2_shield.visible = false

	_add_label("👹 ADAMASTOR — The Giant of the Douro", 20, Control.PRESET_CENTER_TOP, Vector2(-240, 14), Vector2(480, 26))
	_boss_bar = _add_bar(BOSS_FILL, GameManager.MAX_BOSS_HEALTH, Control.PRESET_CENTER_TOP, Vector2(-240, 42), Vector2(480, 28))

	# --- Score / timer / combo ---
	_score_label = _add_label("Score: 0", 24, Control.PRESET_CENTER_TOP, Vector2(-240, 78), Vector2(230, 30), HORIZONTAL_ALIGNMENT_LEFT)
	_timer_label = _add_label("0:00", 24, Control.PRESET_CENTER_TOP, Vector2(10, 78), Vector2(230, 30), HORIZONTAL_ALIGNMENT_RIGHT)
	_combo_label = _add_label("", 30, Control.PRESET_CENTER_TOP, Vector2(-240, 112), Vector2(480, 36))
	_combo_label.add_theme_color_override("font_color", DASH_FILL)

	# --- Ability cooldown bars ---
	_dino_label = _add_label("DINO ENERGY", 16, Control.PRESET_BOTTOM_LEFT, Vector2(24, -66), Vector2(220, 22))
	_dino_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_dino_bar = _add_bar(DINO_FILL, 100, Control.PRESET_BOTTOM_LEFT, Vector2(24, -44), Vector2(220, 20))

	_dash_label = _add_label("BOXY DASH", 16, Control.PRESET_BOTTOM_RIGHT, Vector2(-244, -66), Vector2(220, 22))
	_dash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_dash_bar = _add_bar(DASH_FILL, 100, Control.PRESET_BOTTOM_RIGHT, Vector2(-244, -44), Vector2(220, 20))

	_build_pause_overlay()

	# --- Wire up GameManager events ---
	GameManager.player_damaged.connect(_on_player_damaged)
	GameManager.boss_damaged.connect(_on_boss_damaged)
	GameManager.score_changed.connect(_on_score_changed)
	GameManager.combo_changed.connect(_on_combo_changed)
	GameManager.timer_updated.connect(_on_timer_updated)
	GameManager.boss_phase_changed.connect(_on_phase_changed)
	GameManager.state_changed.connect(_on_state_changed)


func _process(delta: float) -> void:
	_pulse += delta
	# Poll the players for ability cooldown fills and i-frame state.
	for p in get_tree().get_nodes_in_group("players"):
		if not p.has_method("get_ability_fraction"):
			continue
		var frac: float = p.get_ability_fraction() * 100.0
		var inv: bool = p.has_method("is_invulnerable") and p.is_invulnerable()
		if p.player_id == 1:
			_dino_bar.value = frac
			_dino_label.text = "DINO ENERGY  ✔" if frac >= 100.0 else "DINO ENERGY"
			_set_shield(_p1_shield, inv)
		else:
			_dash_bar.value = frac
			_dash_label.text = "BOXY DASH  ✔" if frac >= 100.0 else "BOXY DASH"
			_set_shield(_p2_shield, inv)


func _set_shield(shield: Label, on: bool) -> void:
	shield.visible = on
	if on:
		shield.modulate.a = 0.4 + 0.6 * absf(sin(_pulse * 8.0))


# --- Signal handlers -------------------------------------------------------

func _on_player_damaged(player_id: int, _amount: int, new_health: int) -> void:
	if player_id == 1:
		_p1_bar.value = new_health
	else:
		_p2_bar.value = new_health


func _on_boss_damaged(_amount: int, new_health: int) -> void:
	_boss_bar.value = new_health


func _on_score_changed(new_score: int) -> void:
	_score_label.text = "Score: %d" % new_score


func _on_combo_changed(player_id: int, combo: int) -> void:
	if player_id == 2 and combo >= 2:
		_combo_label.text = "x%d COMBO!" % combo
		_combo_label.scale = Vector2(1.3, 1.3)
		_combo_label.pivot_offset = _combo_label.size * 0.5
		var t := create_tween()
		t.tween_property(_combo_label, "scale", Vector2.ONE, 0.2)
	elif combo < 2:
		_combo_label.text = ""


func _on_timer_updated(seconds: float) -> void:
	var m := int(seconds) / 60
	var s := int(seconds) % 60
	_timer_label.text = "%d:%02d" % [m, s]


func _on_phase_changed(_phase: int) -> void:
	var t := create_tween()
	t.tween_property(_boss_bar, "modulate", Color(1.5, 0.6, 0.6), 0.12)
	t.tween_property(_boss_bar, "modulate", Color.WHITE, 0.4)


func _on_state_changed(new_state: int) -> void:
	_pause_overlay.visible = (new_state == GameManager.State.PAUSED)


# --- Builders --------------------------------------------------------------

func _add_label(text: String, size: int, preset: int, pos: Vector2, dims: Vector2,
		align: int = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", SHADOW)
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	l.set_anchors_preset(preset)
	l.offset_left = pos.x
	l.offset_top = pos.y
	l.offset_right = pos.x + dims.x
	l.offset_bottom = pos.y + dims.y
	return l


func _add_bar(fill: Color, max_val: int, preset: int, pos: Vector2, dims: Vector2) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.show_percentage = false
	pb.min_value = 0.0
	pb.max_value = max_val
	pb.value = max_val
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sb_bg := StyleBoxFlat.new()
	sb_bg.bg_color = Color(0.08, 0.08, 0.12, 0.85)
	sb_bg.set_corner_radius_all(6)
	sb_bg.set_border_width_all(2)
	sb_bg.border_color = Color(0, 0, 0, 0.7)
	var sb_fill := StyleBoxFlat.new()
	sb_fill.bg_color = fill
	sb_fill.set_corner_radius_all(6)
	pb.add_theme_stylebox_override("background", sb_bg)
	pb.add_theme_stylebox_override("fill", sb_fill)

	add_child(pb)
	pb.set_anchors_preset(preset)
	pb.offset_left = pos.x
	pb.offset_top = pos.y
	pb.offset_right = pos.x + dims.x
	pb.offset_bottom = pos.y + dims.y
	return pb


func _build_pause_overlay() -> void:
	_pause_overlay = Control.new()
	_pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_overlay.visible = false
	add_child(_pause_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.05, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_overlay.add_child(dim)

	var label := Label.new()
	label.text = "⏸  PAUSED\n\nPress ESC to resume"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 44)
	label.add_theme_color_override("font_outline_color", SHADOW)
	label.add_theme_constant_override("outline_size", 8)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_overlay.add_child(label)
