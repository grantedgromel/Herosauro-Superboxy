extends Control
## In-game HUD — health (P1 left, P2 right, boss centre), ability cooldowns,
## score, fight timer, combo, i-frame indicators and pause overlay. Restyled
## with the shared UIStyle for a clean, professional look.

const OptionsMenuScene: GDScript = preload("res://scripts/ui/options_menu.gd")

var _p1_bar: ProgressBar
var _p2_bar: ProgressBar
var _boss_bar: ProgressBar
var _dino_bar: ProgressBar
var _dash_bar: ProgressBar
var _score: Label
var _timer: Label
var _combo: Label
var _dino_lbl: Label
var _dash_lbl: Label
var _p1_shield: Label
var _p2_shield: Label
var _pause: Control
var _pulse: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# --- Player health ---
	_place(UIStyle.label("HEROSAURO", 17, UIStyle.P1.lightened(0.25), true, HORIZONTAL_ALIGNMENT_LEFT),
		Control.PRESET_TOP_LEFT, Vector2(26, 14), Vector2(300, 22))
	_p1_bar = _place(UIStyle.bar(UIStyle.P1), Control.PRESET_TOP_LEFT, Vector2(26, 40), Vector2(300, 20))
	_p1_shield = _place(UIStyle.label("◆ INVINCIBLE", 13, UIStyle.GOLD, true, HORIZONTAL_ALIGNMENT_LEFT),
		Control.PRESET_TOP_LEFT, Vector2(28, 62), Vector2(200, 16))
	_p1_shield.visible = false

	_place(UIStyle.label("SUPER BOXY", 17, UIStyle.P2.lightened(0.2), true, HORIZONTAL_ALIGNMENT_RIGHT),
		Control.PRESET_TOP_RIGHT, Vector2(-326, 14), Vector2(300, 22))
	_p2_bar = _place(UIStyle.bar(UIStyle.P2), Control.PRESET_TOP_RIGHT, Vector2(-326, 40), Vector2(300, 20))
	_p2_shield = _place(UIStyle.label("INVINCIBLE ◆", 13, UIStyle.GOLD, true, HORIZONTAL_ALIGNMENT_RIGHT),
		Control.PRESET_TOP_RIGHT, Vector2(-226, 62), Vector2(200, 16))
	_p2_shield.visible = false

	# --- Boss health ---
	_place(UIStyle.label("ADAMASTOR — THE GIANT OF THE DOURO", 18, UIStyle.CREAM, true),
		Control.PRESET_CENTER_TOP, Vector2(-280, 14), Vector2(560, 24))
	_boss_bar = _place(UIStyle.bar(UIStyle.BOSS, GameManager.MAX_BOSS_HEALTH),
		Control.PRESET_CENTER_TOP, Vector2(-262, 42), Vector2(524, 22))

	# --- Score / timer / combo ---
	_score = _place(UIStyle.label("SCORE  0", 22, UIStyle.GOLD, true, HORIZONTAL_ALIGNMENT_LEFT),
		Control.PRESET_CENTER_TOP, Vector2(-262, 74), Vector2(260, 28))
	_timer = _place(UIStyle.label("0:00", 22, UIStyle.CREAM, true, HORIZONTAL_ALIGNMENT_RIGHT),
		Control.PRESET_CENTER_TOP, Vector2(2, 74), Vector2(260, 28))
	_combo = _place(UIStyle.label("", 32, UIStyle.GOLD, true), Control.PRESET_CENTER_TOP, Vector2(-262, 108), Vector2(524, 40))

	# --- Ability cooldowns ---
	_dino_lbl = _place(UIStyle.label("DINO ENERGY", 16, UIStyle.CREAM, true, HORIZONTAL_ALIGNMENT_LEFT),
		Control.PRESET_BOTTOM_LEFT, Vector2(26, -64), Vector2(240, 20))
	_dino_bar = _place(UIStyle.bar(UIStyle.P1.lightened(0.1)), Control.PRESET_BOTTOM_LEFT, Vector2(26, -42), Vector2(230, 16))
	_dash_lbl = _place(UIStyle.label("BOXY DASH", 16, UIStyle.CREAM, true, HORIZONTAL_ALIGNMENT_RIGHT),
		Control.PRESET_BOTTOM_RIGHT, Vector2(-256, -64), Vector2(240, 20))
	_dash_bar = _place(UIStyle.bar(UIStyle.GOLD), Control.PRESET_BOTTOM_RIGHT, Vector2(-256, -42), Vector2(230, 16))

	_build_pause()

	GameManager.player_damaged.connect(_on_player_damaged)
	GameManager.boss_damaged.connect(_on_boss_damaged)
	GameManager.score_changed.connect(_on_score_changed)
	GameManager.combo_changed.connect(_on_combo_changed)
	GameManager.timer_updated.connect(_on_timer_updated)
	GameManager.boss_phase_changed.connect(_on_phase_changed)
	GameManager.state_changed.connect(_on_state_changed)


func _process(delta: float) -> void:
	_pulse += delta
	for p in get_tree().get_nodes_in_group("players"):
		if not p.has_method("get_ability_fraction"):
			continue
		var frac: float = p.get_ability_fraction() * 100.0
		var inv: bool = p.has_method("is_invulnerable") and p.is_invulnerable()
		if p.player_id == 1:
			_dino_bar.value = frac
			_dino_lbl.modulate = Color.WHITE if frac >= 100.0 else Color(1, 1, 1, 0.6)
			_set_shield(_p1_shield, inv)
		else:
			_dash_bar.value = frac
			_dash_lbl.modulate = Color.WHITE if frac >= 100.0 else Color(1, 1, 1, 0.6)
			_set_shield(_p2_shield, inv)


func _set_shield(shield: Label, on: bool) -> void:
	shield.visible = on
	if on:
		shield.modulate.a = 0.45 + 0.55 * absf(sin(_pulse * 7.0))


# --- Signals ---------------------------------------------------------------

func _on_player_damaged(player_id: int, _amount: int, new_health: int) -> void:
	(_p1_bar if player_id == 1 else _p2_bar).value = new_health


func _on_boss_damaged(_amount: int, new_health: int) -> void:
	_boss_bar.value = new_health


func _on_score_changed(new_score: int) -> void:
	_score.text = "SCORE  %d" % new_score


func _on_combo_changed(player_id: int, combo: int) -> void:
	if player_id == 2 and combo >= 2:
		_combo.text = "%d×  COMBO!" % combo
		_combo.pivot_offset = _combo.size * 0.5
		_combo.scale = Vector2(1.35, 1.35)
		create_tween().tween_property(_combo, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	elif combo < 2:
		_combo.text = ""


func _on_timer_updated(seconds: float) -> void:
	_timer.text = "%d:%02d" % [int(seconds) / 60, int(seconds) % 60]


func _on_phase_changed(_phase: int) -> void:
	var fl := (_boss_bar.get_theme_stylebox("fill") as StyleBoxFlat)
	if fl:
		fl.bg_color = UIStyle.BOSS_RED
	var t := create_tween()
	t.tween_property(_boss_bar, "modulate", Color(1.6, 0.7, 0.7), 0.12)
	t.tween_property(_boss_bar, "modulate", Color.WHITE, 0.45)


func _on_state_changed(new_state: int) -> void:
	_pause.visible = (new_state == GameManager.State.PAUSED)


# --- Builders --------------------------------------------------------------

func _place(ctrl: Control, preset: int, pos: Vector2, dims: Vector2) -> Control:
	add_child(ctrl)
	ctrl.set_anchors_preset(preset)
	ctrl.offset_left = pos.x
	ctrl.offset_top = pos.y
	ctrl.offset_right = pos.x + dims.x
	ctrl.offset_bottom = pos.y + dims.y
	return ctrl


func _build_pause() -> void:
	_pause = Control.new()
	_pause.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Interactive overlay that must work while the tree is paused.
	_pause.process_mode = Node.PROCESS_MODE_ALWAYS
	_pause.visible = false
	add_child(_pause)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.66)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause.add_child(dim)

	var label := UIStyle.title("PAUSED", 70)
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	label.offset_top = -150.0
	label.offset_bottom = -70.0
	_pause.add_child(label)

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 14)
	col.set_anchors_preset(Control.PRESET_CENTER)
	col.offset_left = -160.0
	col.offset_right = 160.0
	col.offset_top = -40.0
	col.offset_bottom = 160.0
	_pause.add_child(col)

	var resume := UIStyle.button("▶  RESUME", true)
	resume.pressed.connect(func() -> void: GameManager.toggle_pause())
	col.add_child(resume)

	var opts := UIStyle.button("OPTIONS")
	opts.pressed.connect(_on_pause_options)
	col.add_child(opts)

	var quit := UIStyle.button("QUIT TO MENU")
	quit.pressed.connect(func() -> void: GameManager.go_to_menu())
	col.add_child(quit)

	var hint := UIStyle.label("ESC to resume", 18, UIStyle.MUTED)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -48.0
	hint.offset_bottom = -22.0
	_pause.add_child(hint)


func _on_pause_options() -> void:
	var o: Control = OptionsMenuScene.new()
	o.process_mode = Node.PROCESS_MODE_ALWAYS
	_pause.add_child(o)
