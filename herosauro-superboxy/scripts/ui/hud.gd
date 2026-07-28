extends Control
## In-game HUD.
##
## Layout is a deliberate grid rather than a scatter of anchored labels:
##
##   ┌──────────────────────────────────────────────────────────────┐
##   │                    ADAMASTOR                          SCORE  │
##   │        [=========== boss banner ===========]           1,240 │
##   │        THE GIANT OF THE DOURO       PHASE 1 ◆◇         02:31 │
##   │                                                              │
##   │                                                       ×5     │
##   │                                                      COMBO   │
##   │  ┌────┐ HEROSAURO             84 / 100                       │
##   │  │face│ [==================]              ( ◔ )              │
##   │  └────┘ INVINCIBLE                     DINO ENERGY           │
##   └──────────────────────────────────────────────────────────────┘
##
## Three clusters, three jobs. Boss top-centre because it is the thing you are
## fighting and your eyes are already there. Hero bottom-left, grouped with his
## portrait and his ability, because it is *your* status and it belongs with you.
## Score and timer top-right, small, because they are a post-match concern.
## Everything sits over a bright golden-hour sky, so every element carries its
## own scrim, shadow or outline rather than relying on the backdrop being dark.

const SHOW_SECOND_HERO := false

const HERO_ACTOR := UIStyle.Actor.HEROSAURO
const BOSS_ACTOR := UIStyle.Actor.ADAMASTOR

# --- Grid ---------------------------------------------------------------------
const M := UIStyle.SCREEN_MARGIN          # screen gutter
const BOSS_BANNER_W := 660.0
const BOSS_BAR_H := 26.0
const HERO_AVATAR := 92.0
const HERO_BAR_W := 320.0
const HERO_BAR_H := 22.0
const DIAL_SIZE := 68.0

## Fraction of hero health below which the screen edge starts glowing.
const DANGER_RATIO := 0.30
## Score rolls up to its new value instead of snapping; this is the rate.
const SCORE_LAMBDA := 9.0

# Hero cluster
var _hero_face: PortraitFrame
var _hero_name: Label
var _hero_hp: Label
var _hero_bar: StatBar
var _hero_status: Label
var _dial: AbilityDial
var _dial_caption: Label

# Boss banner
var _boss_face: PortraitFrame
var _boss_name: Label
var _boss_epithet: Label
var _boss_bar: StatBar
var _boss_hp: Label
var _phase_label: Label
var _phase_pips: Array[Panel] = []

# Readouts
var _score_value: Label
var _timer_value: Label
var _combo_count: Label
var _combo_word: Label
var _combo_track: Panel
var _combo_fill: Panel

# Effects + overlays
var _fx: HitVignette
var _pops: DamageNumbers
var _pause: Control

var _pulse: float = 0.0
var _score_shown: float = 0.0
var _score_target: float = 0.0
var _combo_left: float = 0.0
var _combo_value: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Child order is draw order: effects behind, numbers over the world but under
	# the chrome, chrome under the pause sheet.
	_build_effects()
	_build_boss_banner()
	_build_hero_cluster()
	_build_readouts()
	_build_combo()
	_build_pause()

	GameManager.player_damaged.connect(_on_player_damaged)
	GameManager.boss_damaged.connect(_on_boss_damaged)
	GameManager.score_changed.connect(_on_score_changed)
	GameManager.combo_changed.connect(_on_combo_changed)
	GameManager.timer_updated.connect(_on_timer_updated)
	GameManager.boss_phase_changed.connect(_on_phase_changed)
	GameManager.state_changed.connect(_on_state_changed)
	GameManager.game_started.connect(_on_game_started)


# --- Build --------------------------------------------------------------------

func _build_effects() -> void:
	_fx = HitVignette.new()
	add_child(_fx)

	# A short scrim under the top strip. The banner and the score readout both
	# live up there and the sky behind them is the brightest thing on screen.
	var top := UIStyle.scrim(true, 170.0, 0.42)
	add_child(top)
	var bottom := UIStyle.scrim(false, 190.0, 0.44)
	add_child(bottom)

	_pops = DamageNumbers.new()
	add_child(_pops)


func _build_boss_banner() -> void:
	var half := BOSS_BANNER_W * 0.5

	_boss_face = PortraitFrame.new()
	_boss_face.actor = BOSS_ACTOR
	_place(_boss_face, Control.PRESET_CENTER_TOP, Vector2(-half - 62.0, 20.0), Vector2(56, 56))

	_boss_name = UIStyle.text(UIStyle.actor_name(BOSS_ACTOR), UIStyle.Scale.HEADING,
		UIStyle.TEXT_PRIMARY, HORIZONTAL_ALIGNMENT_CENTER)
	_place(_boss_name, Control.PRESET_CENTER_TOP, Vector2(-half, 14.0), Vector2(BOSS_BANNER_W, 34))

	_boss_bar = StatBar.new()
	_boss_bar.setup(StatBar.Variant.BOSS, float(GameManager.MAX_BOSS_HEALTH), UIStyle.BOSS_AMBER, 10)
	_boss_bar.phase_marker = GameManager.BOSS_PHASE2_RATIO
	_place(_boss_bar, Control.PRESET_CENTER_TOP, Vector2(-half, 50.0), Vector2(BOSS_BANNER_W, BOSS_BAR_H))

	# Epithet, HP and phase share one line under the bar. Their boxes are sized to
	# butt up against each other without overlapping, so a long name can never
	# draw over the numbers.
	_boss_epithet = UIStyle.text(UIStyle.actor_epithet(BOSS_ACTOR), UIStyle.Scale.MICRO,
		UIStyle.TEXT_SECONDARY, HORIZONTAL_ALIGNMENT_LEFT)
	_place(_boss_epithet, Control.PRESET_CENTER_TOP, Vector2(-half + 2.0, 80.0), Vector2(236, 16))

	_boss_hp = UIStyle.text("", UIStyle.Scale.MICRO, UIStyle.TEXT_SECONDARY, HORIZONTAL_ALIGNMENT_CENTER)
	_place(_boss_hp, Control.PRESET_CENTER_TOP, Vector2(-90.0, 80.0), Vector2(180, 16))

	# Phase read-out: two pips plus a word, right-aligned under the bar.
	_phase_label = UIStyle.text("PHASE 1", UIStyle.Scale.MICRO, UIStyle.GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	_place(_phase_label, Control.PRESET_CENTER_TOP, Vector2(half - 128.0, 80.0), Vector2(90, 16))
	for i in 2:
		var pip := UIStyle.chip(UIStyle.GOLD if i == 0 else UIStyle.HAIRLINE_STRONG, 9.0)
		_place(pip, Control.PRESET_CENTER_TOP, Vector2(half - 30.0 + i * 14.0, 84.0), Vector2(9, 9))
		_phase_pips.append(pip)


func _build_hero_cluster() -> void:
	var text_x := M + HERO_AVATAR + UIStyle.SPACE_MD
	var accent := UIStyle.actor_color(HERO_ACTOR)

	_hero_face = PortraitFrame.new()
	_hero_face.actor = HERO_ACTOR
	_place(_hero_face, Control.PRESET_BOTTOM_LEFT, Vector2(M, -(M + HERO_AVATAR)),
		Vector2(HERO_AVATAR, HERO_AVATAR))

	_hero_name = UIStyle.text(UIStyle.actor_name(HERO_ACTOR), UIStyle.Scale.SUBHEAD,
		accent.lightened(0.25), HORIZONTAL_ALIGNMENT_LEFT)
	_place(_hero_name, Control.PRESET_BOTTOM_LEFT, Vector2(text_x, -118.0), Vector2(220, 24))

	_hero_hp = UIStyle.text("100 / 100", UIStyle.Scale.MICRO, UIStyle.TEXT_SECONDARY,
		HORIZONTAL_ALIGNMENT_RIGHT)
	_place(_hero_hp, Control.PRESET_BOTTOM_LEFT, Vector2(text_x, -116.0), Vector2(HERO_BAR_W, 20))

	_hero_bar = StatBar.new()
	_hero_bar.setup(StatBar.Variant.HERO, float(GameManager.MAX_PLAYER_HEALTH), accent, 4)
	_place(_hero_bar, Control.PRESET_BOTTOM_LEFT, Vector2(text_x, -92.0), Vector2(HERO_BAR_W, HERO_BAR_H))

	_hero_status = UIStyle.text("INVINCIBLE", UIStyle.Scale.LABEL, UIStyle.GOLD,
		HORIZONTAL_ALIGNMENT_LEFT)
	_place(_hero_status, Control.PRESET_BOTTOM_LEFT, Vector2(text_x + 2.0, -64.0), Vector2(220, 18))
	_hero_status.visible = false

	# Dial and caption bottom out on the same gutter line as the portrait, so the
	# whole cluster sits on one baseline instead of three.
	var dial_x := text_x + HERO_BAR_W + UIStyle.SPACE_LG
	_dial = AbilityDial.new()
	_place(_dial, Control.PRESET_BOTTOM_LEFT, Vector2(dial_x, -116.0), Vector2(DIAL_SIZE, DIAL_SIZE))
	_dial.setup("E", UIStyle.GOLD)

	_dial_caption = UIStyle.text("DINO ENERGY", UIStyle.Scale.MICRO, UIStyle.TEXT_SECONDARY,
		HORIZONTAL_ALIGNMENT_CENTER)
	_place(_dial_caption, Control.PRESET_BOTTOM_LEFT, Vector2(dial_x - 36.0, -44.0),
		Vector2(DIAL_SIZE + 72.0, 16))


func _build_readouts() -> void:
	var w := 210.0
	var right := -(M + w)

	var score_tag := UIStyle.text("SCORE", UIStyle.Scale.MICRO, UIStyle.TEXT_SECONDARY,
		HORIZONTAL_ALIGNMENT_RIGHT)
	_place(score_tag, Control.PRESET_TOP_RIGHT, Vector2(right, 22.0), Vector2(w, 14))

	_score_value = UIStyle.text("0", UIStyle.Scale.HEADING, UIStyle.GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	_place(_score_value, Control.PRESET_TOP_RIGHT, Vector2(right, 36.0), Vector2(w, 34))

	var rule := UIStyle.divider(1, 0.14)
	_place(rule, Control.PRESET_TOP_RIGHT, Vector2(right + w - 96.0, 76.0), Vector2(96, 1))

	var time_tag := UIStyle.text("TIME", UIStyle.Scale.MICRO, UIStyle.TEXT_SECONDARY,
		HORIZONTAL_ALIGNMENT_RIGHT)
	_place(time_tag, Control.PRESET_TOP_RIGHT, Vector2(right, 84.0), Vector2(w, 14))

	_timer_value = UIStyle.text("0:00", UIStyle.Scale.SUBHEAD, UIStyle.TEXT_PRIMARY,
		HORIZONTAL_ALIGNMENT_RIGHT)
	_place(_timer_value, Control.PRESET_TOP_RIGHT, Vector2(right, 98.0), Vector2(w, 24))


func _build_combo() -> void:
	# Right edge, vertically centred: clear of the boss banner, clear of the hero
	# cluster, and out of the middle where the fight actually happens.
	var w := 200.0
	var right := -(M + w)

	_combo_count = UIStyle.title("", UIStyle.Scale.TITLE, UIStyle.GOLD)
	_combo_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_place(_combo_count, Control.PRESET_CENTER_RIGHT, Vector2(right, -46.0), Vector2(w, 60))

	_combo_word = UIStyle.text("", UIStyle.Scale.LABEL, UIStyle.GOLD_DEEP, HORIZONTAL_ALIGNMENT_RIGHT)
	_place(_combo_word, Control.PRESET_CENTER_RIGHT, Vector2(right, 12.0), Vector2(w, 18))

	# Depletion rail: the combo window running out, drawn as a shrinking bar so
	# the player can see how long they have to land the next hit.
	_combo_track = Panel.new()
	_combo_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tb := StyleBoxFlat.new()
	tb.bg_color = Color(0, 0, 0, 0.45)
	tb.set_corner_radius_all(2)
	_combo_track.add_theme_stylebox_override("panel", tb)
	_place(_combo_track, Control.PRESET_CENTER_RIGHT, Vector2(right + w - 120.0, 34.0), Vector2(120, 4))

	_combo_fill = Panel.new()
	_combo_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fb := StyleBoxFlat.new()
	fb.bg_color = UIStyle.GOLD
	fb.set_corner_radius_all(2)
	_combo_fill.add_theme_stylebox_override("panel", fb)
	# Pinned to the track's top-left with all four anchors at 0, so resizing the
	# fill each frame only moves its own offsets. A stretched preset here would
	# have the layout fight the width we set and log an override warning.
	_combo_fill.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_combo_fill.size = Vector2(120, 4)
	_combo_track.add_child(_combo_fill)

	_set_combo_visible(false)


func _build_pause() -> void:
	_pause = Control.new()
	_pause.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause.visible = false
	add_child(_pause)

	var dim := ColorRect.new()
	dim.color = UIStyle.OVERLAY
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause.add_child(dim)

	var card := UIStyle.card(UIStyle.Elev.MODAL, UIStyle.RADIUS_LG, UIStyle.SPACE_XL)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.offset_left = -300.0
	card.offset_right = 300.0
	card.offset_top = -150.0
	card.offset_bottom = 150.0
	_pause.add_child(card)

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", UIStyle.SPACE_MD)
	card.add_child(col)

	col.add_child(UIStyle.title("PAUSED", UIStyle.Scale.TITLE, UIStyle.GOLD))
	col.add_child(UIStyle.text("The giant is waiting.", UIStyle.Scale.BODY,
		UIStyle.TEXT_SECONDARY, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(UIStyle.divider(2, 0.10))

	# A pause screen is the one moment the player has time to read the controls,
	# so this is where the full reference lives rather than the menu footer.
	var grid := UIStyle.hint_row([["WASD", "Move"], ["SPACE", "Jump"], ["SHIFT", "Sprint"]], UIStyle.SPACE_LG)
	col.add_child(grid)
	var grid2 := UIStyle.hint_row([["LMB", "Attack"], ["RMB", "Special"], ["ESC", "Resume"]], UIStyle.SPACE_LG)
	col.add_child(grid2)


func _place(ctrl: Control, preset: int, pos: Vector2, dims: Vector2) -> Control:
	add_child(ctrl)
	ctrl.set_anchors_preset(preset)
	ctrl.offset_left = pos.x
	ctrl.offset_top = pos.y
	ctrl.offset_right = pos.x + dims.x
	ctrl.offset_bottom = pos.y + dims.y
	return ctrl


# --- Frame --------------------------------------------------------------------

func _process(delta: float) -> void:
	if not visible:
		return
	_pulse += delta
	_tick_score(delta)
	_tick_combo(delta)
	_tick_hero(delta)


## Roll the score up instead of snapping. A number that counts feels earned; a
## number that jumps is just a variable being printed.
func _tick_score(delta: float) -> void:
	if absf(_score_shown - _score_target) < 0.5:
		# The roll converges asymptotically, so the last fraction of a point never
		# arrives on its own. Snap AND repaint here, or the readout settles one
		# short of the real score and stays there.
		if _score_shown != _score_target:
			_score_shown = _score_target
			_score_value.text = UIProgress.format_score(int(round(_score_target)))
		return
	_score_shown = lerpf(_score_shown, _score_target, clampf(1.0 - exp(-SCORE_LAMBDA * delta), 0.0, 1.0))
	_score_value.text = UIProgress.format_score(int(round(_score_shown)))


func _tick_combo(delta: float) -> void:
	if _combo_value < 2:
		return
	_combo_left = maxf(0.0, _combo_left - delta)
	var frac := _combo_left / GameManager.COMBO_TIMEOUT
	_combo_fill.size.x = _combo_track.size.x * frac
	if _combo_left <= 0.0:
		_end_combo()


func _tick_hero(_delta: float) -> void:
	for p in get_tree().get_nodes_in_group("players"):
		if not p.has_method("get_ability_fraction"):
			continue
		if int(p.player_id) != 1 and not SHOW_SECOND_HERO:
			continue
		_dial.set_fraction(p.get_ability_fraction())
		_dial_caption.modulate.a = 1.0 if _dial.is_ready() else 0.6
		var inv: bool = p.has_method("is_invulnerable") and p.is_invulnerable()
		_hero_status.visible = inv
		if inv:
			_hero_status.modulate.a = 0.45 + 0.55 * absf(sin(_pulse * 7.0))
		break


# --- Signals ------------------------------------------------------------------

func _on_game_started() -> void:
	_hero_bar.reset_to(float(GameManager.MAX_PLAYER_HEALTH))
	_boss_bar.reset_to(float(GameManager.MAX_BOSS_HEALTH))
	_boss_bar.set_fill_color(UIStyle.BOSS_AMBER)
	_score_shown = 0.0
	_score_target = 0.0
	_score_value.text = "0"
	_timer_value.text = "0:00"
	_hero_face.set_dimmed(false)
	_fx.set_danger(0.0)
	_pops.clear_all()
	_end_combo()
	_set_phase(1)


func _on_player_damaged(player_id: int, amount: int, new_health: int) -> void:
	if player_id != 1:
		return
	_hero_bar.set_value(float(new_health), amount > 0)
	_hero_hp.text = "%d / %d" % [new_health, GameManager.MAX_PLAYER_HEALTH]

	var ratio := float(new_health) / float(GameManager.MAX_PLAYER_HEALTH)
	# Below the danger line the edge glow ramps in; scale it so the last sliver
	# of health is unmistakable and 30% is only a hint.
	_fx.set_danger(0.0 if ratio > DANGER_RATIO else 1.0 - ratio / DANGER_RATIO)

	if amount > 0:
		_hero_face.hit_flash()
		# Bigger hits bloom harder. A 6 dmg graze and an 18 dmg slam should not
		# look the same.
		_fx.flash(clampf(0.35 + float(amount) / 28.0, 0.35, 1.0))
	if new_health <= 0:
		_hero_face.set_dimmed(true)


func _on_boss_damaged(amount: int, new_health: int) -> void:
	_boss_bar.set_value(float(new_health), amount > 0)
	_boss_hp.text = "%d / %d" % [new_health, GameManager.MAX_BOSS_HEALTH]
	if amount <= 0:
		return
	_boss_face.hit_flash()
	_spawn_damage_number(amount)


## Numbers pop at the giant's head. He is nine metres tall, so his origin is at
## his feet and putting the number there would bury it in the deck.
func _spawn_damage_number(amount: int) -> void:
	var boss: Node = get_tree().get_first_node_in_group("boss")
	if boss == null or not (boss is Node3D):
		return
	var crit := amount >= 15
	var head: Vector3 = (boss as Node3D).global_position + Vector3(
		randf_range(-1.4, 1.4), 8.6 + randf_range(-0.4, 0.4), randf_range(-1.0, 1.0))
	var tint := UIStyle.GOLD if crit else UIStyle.TEXT_PRIMARY
	_pops.pop_at_world(str(amount), head, tint, crit)


func _on_score_changed(new_score: int) -> void:
	_score_target = float(new_score)


func _on_combo_changed(_player_id: int, combo: int) -> void:
	if combo < 2:
		_end_combo()
		return
	_combo_value = combo
	_combo_left = GameManager.COMBO_TIMEOUT
	# Digits only in the display face — Bangers is a decorative Latin set and a
	# missing glyph there falls back to the engine default, which looks broken.
	_combo_count.text = str(combo)
	_combo_word.text = "HIT COMBO"
	_set_combo_visible(true)

	# Higher combos run hotter: gold to ember as the chain grows.
	var heat := clampf((combo - 2) / 8.0, 0.0, 1.0)
	var tint := UIStyle.GOLD.lerp(UIStyle.EMBER, heat)
	_combo_count.add_theme_color_override("font_color", tint)
	(_combo_fill.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = tint

	_combo_count.pivot_offset = Vector2(_combo_count.size.x, _combo_count.size.y * 0.5)
	_combo_count.scale = Vector2(1.0 + 0.28 * (1.0 - heat * 0.4), 1.0 + 0.28 * (1.0 - heat * 0.4))
	var t := create_tween()
	t.tween_property(_combo_count, "scale", Vector2.ONE, 0.24) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _end_combo() -> void:
	_combo_value = 0
	_combo_left = 0.0
	_set_combo_visible(false)


func _set_combo_visible(on: bool) -> void:
	for n in [_combo_count, _combo_word, _combo_track]:
		if n:
			(n as CanvasItem).visible = on


func _on_timer_updated(seconds: float) -> void:
	_timer_value.text = UIProgress.format_time(seconds)


func _on_phase_changed(phase: int) -> void:
	_set_phase(phase)
	if phase >= 2:
		_boss_bar.enrage(true)
		_boss_name.add_theme_color_override("font_color", UIStyle.BOSS_RAGE.lightened(0.35))
		# One hard punch on the banner so the phase flip is an event, not a
		# colour that quietly changed while you were looking elsewhere.
		var t := create_tween()
		t.tween_property(_boss_bar, "modulate", Color(2.0, 1.2, 1.1), 0.10)
		t.tween_property(_boss_bar, "modulate", Color.WHITE, 0.5)


func _set_phase(phase: int) -> void:
	_phase_label.text = "PHASE %d" % phase
	var hot := UIStyle.BOSS_RAGE if phase >= 2 else UIStyle.GOLD
	_phase_label.add_theme_color_override("font_color", hot)
	for i in _phase_pips.size():
		var lit := i < phase
		var sb := _phase_pips[i].get_theme_stylebox("panel") as StyleBoxFlat
		if sb:
			sb.bg_color = hot if lit else UIStyle.HAIRLINE_STRONG
	if phase < 2:
		_boss_name.add_theme_color_override("font_color", UIStyle.TEXT_PRIMARY)
		_boss_bar.enrage(false)


func _on_state_changed(new_state: int) -> void:
	_pause.visible = (new_state == GameManager.State.PAUSED)
