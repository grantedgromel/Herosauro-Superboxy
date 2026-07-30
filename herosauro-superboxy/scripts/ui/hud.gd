extends Control
## In-game HUD, for two heroes.
##
## Layout is a deliberate grid rather than a scatter of anchored labels:
##
##   ┌──────────────────────────────────────────────────────────────────┐
##   │            ┌── ADAMASTOR ──────────────┐         ┌──────────────┐│
##   │            │▣ [====== boss bar ======] │         │ SCORE  1,240 ││
##   │            │  THE GIANT…    PHASE 1 ◆◇ │         │ TIME    2:31 ││
##   │            └───────────────────────────┘         └──────────────┘│
##   │                                                                  │
##   │                                                        ×5        │
##   │                                                     HIT COMBO    │
##   │  ┌───────────────────┐                    ┌───────────────────┐  │
##   │  │▣ P1 HEROSAURO  (◔)│                    │(◔)  SUPER BOXY P2▣│  │
##   │  │  [==== 84/100 ===]│                    │[=== 100/100 ====] │  │
##   │  └───────────────────┘                    └───────────────────┘  │
##   └──────────────────────────────────────────────────────────────────┘
##
## Four clusters, four jobs. Boss top-centre because it is the thing you are
## fighting and your eyes are already there. THE TWO HEROES ARE MIRROR IMAGES IN
## THE TWO BOTTOM CORNERS — same size, same content, same weight — because this
## is co-op and a HUD that stacks a big player one over a small player two tells
## the second player whose game they are in. Score and timer top-right, small,
## because they are a post-match concern.
##
## Nothing here dims the world. Every cluster is an opaque keylined plate, which
## is what makes the chrome readable over a bright, saturated, high-contrast
## daylight Porto without throwing away the thing that makes it worth looking at.
## The old full-width top and bottom scrims are gone with the golden hour that
## motivated them.
##
## CROSS-STREAM INTERFACE. Everything visible here comes from GameManager's
## signals — `player_damaged(player_id, …)`, `player_respawned`, `boss_damaged`,
## `score_changed`, `combo_changed`, `timer_updated`, `boss_phase_changed` — plus
## two group lookups (`players`, `boss`) for the things that are positions and
## fractions rather than events. No player or boss script is touched.

const BOSS_ACTOR := UIStyle.Actor.ADAMASTOR

# --- Grid ---------------------------------------------------------------------
const M := UIStyle.SCREEN_MARGIN          # screen gutter
const BOSS_PLATE := Vector2(640.0, 108.0)
const BOSS_BAR_H := 30.0
const BOSS_AVATAR := 68.0
const READOUT_PLATE := Vector2(226.0, 108.0)

## Fraction of hero health below which the screen edge starts glowing. Read from
## the WORST-off living hero, not from player one: in co-op the danger signal
## belongs to whoever is about to go down.
const DANGER_RATIO := 0.30
## Score rolls up to its new value instead of snapping; this is the rate.
const SCORE_LAMBDA := 9.0
## Seconds the score readout stays lit gold after it moves.
const SCORE_GLOW := 0.45
## How hard the combo splash shakes, in pixels, at the moment a hit lands.
const COMBO_SHAKE := 7.0
## Combo shake decay per second, and its ringing frequency in rad/s. Fast and
## high — a combo counter should feel struck, not wobbled.
const COMBO_SHAKE_LAMBDA := 7.0
const COMBO_SHAKE_HZ := 41.0

## Fixed seed for the damage-number scatter. Explicit because the capture gate
## compares frames pixel for pixel and `randf_range()` would put every floating
## number somewhere new on every run — see ARCHITECTURE.md, "Why the determinism
## rules exist".
const POP_SEED := 0x51500FE1

# Hero clusters, keyed by player_id.
var _heroes: Dictionary = {}

# Boss banner
var _boss_plate: Panel
var _boss_face: PortraitFrame
var _boss_name: Label
var _boss_epithet: Label
var _boss_bar: StatBar
var _boss_hp: Label
var _phase_label: Label
var _phase_pips: Array[Panel] = []

# Readouts
var _readout_plate: Panel
var _score_value: Label
var _timer_value: Label
var _combo_slot: Control
var _combo_count: Label
var _combo_word: Label
var _combo_track: Panel
var _combo_fill: Panel

# Effects + overlays
var _fx: HitVignette
var _pops: DamageNumbers
var _pause: Control

var _score_shown: float = 0.0
var _score_target: float = 0.0
var _score_glow: float = 0.0
var _combo_left: float = 0.0
var _combo_value: int = 0
var _combo_shake: float = 0.0
var _combo_shake_phase: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.seed = POP_SEED

	# Child order is draw order: effects behind, numbers over the world but under
	# the chrome, chrome under the pause sheet.
	_build_effects()
	_build_boss_banner()
	_build_hero_panels()
	_build_readouts()
	_build_combo()
	_build_pause()

	GameManager.player_damaged.connect(_on_player_damaged)
	GameManager.player_respawned.connect(_on_player_respawned)
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

	_pops = DamageNumbers.new()
	add_child(_pops)


func _build_boss_banner() -> void:
	var half := BOSS_PLATE.x * 0.5

	# Only a whisper of amber in the fill. The giant's colour is carried by his
	# portrait rim, his health fill and his phase pips; pushing it into the plate
	# as well only neutralises the blue ink and leaves a grey slab.
	_boss_plate = UIStyle.plate(UIStyle.BOSS_AMBER, 0.06, UIStyle.RADIUS_LG, UIStyle.Elev.HIGH)
	_place(_boss_plate, Control.PRESET_CENTER_TOP, Vector2(-half, 14.0), BOSS_PLATE)

	_boss_face = PortraitFrame.new()
	_boss_face.actor = BOSS_ACTOR
	_place(_boss_face, Control.PRESET_CENTER_TOP, Vector2(-half + 16.0, 34.0),
		Vector2(BOSS_AVATAR, BOSS_AVATAR))

	var text_x := -half + 16.0 + BOSS_AVATAR + 16.0
	var text_w := BOSS_PLATE.x - 32.0 - BOSS_AVATAR - 16.0

	_boss_name = UIStyle.text(UIStyle.actor_name(BOSS_ACTOR), UIStyle.Scale.HEADING,
		UIStyle.TEXT_PRIMARY, HORIZONTAL_ALIGNMENT_LEFT)
	_place(_boss_name, Control.PRESET_CENTER_TOP, Vector2(text_x, 22.0), Vector2(text_w * 0.6, 34))

	_boss_hp = UIStyle.text("", UIStyle.Scale.LABEL, UIStyle.TEXT_SECONDARY,
		HORIZONTAL_ALIGNMENT_RIGHT)
	_place(_boss_hp, Control.PRESET_CENTER_TOP, Vector2(text_x + text_w * 0.6, 26.0),
		Vector2(text_w * 0.4, 26))

	_boss_bar = StatBar.new()
	_boss_bar.setup(StatBar.Variant.BOSS, float(GameManager.MAX_BOSS_HEALTH), UIStyle.BOSS_AMBER, 10)
	_boss_bar.phase_marker = GameManager.BOSS_PHASE2_RATIO
	_place(_boss_bar, Control.PRESET_CENTER_TOP, Vector2(text_x, 58.0), Vector2(text_w, BOSS_BAR_H))

	# Epithet and phase share the line under the bar. Their boxes are sized to
	# butt up against each other without overlapping, so a long name can never
	# draw over the phase readout.
	_boss_epithet = UIStyle.text(UIStyle.actor_epithet(BOSS_ACTOR), UIStyle.Scale.MICRO,
		UIStyle.TEXT_SECONDARY, HORIZONTAL_ALIGNMENT_LEFT)
	_place(_boss_epithet, Control.PRESET_CENTER_TOP, Vector2(text_x, 92.0),
		Vector2(text_w - 138.0, 16))

	_phase_label = UIStyle.text("PHASE 1", UIStyle.Scale.MICRO, UIStyle.GOLD,
		HORIZONTAL_ALIGNMENT_RIGHT)
	_place(_phase_label, Control.PRESET_CENTER_TOP, Vector2(text_x + text_w - 106.0, 92.0),
		Vector2(72, 16))
	for i in 2:
		var pip := UIStyle.chip(UIStyle.GOLD if i == 0 else UIStyle.HAIRLINE_STRONG, 11.0)
		_place(pip, Control.PRESET_CENTER_TOP,
			Vector2(text_x + text_w - 28.0 + i * 15.0, 95.0), Vector2(11, 11))
		_phase_pips.append(pip)


## One panel per hero, mirrored into the two bottom corners.
##
## Built off `GameManager.player_count` rather than off what happens to be in the
## `players` group right now: the group is empty while the HUD is constructed
## (main.gd builds the world after the UI layer), and a panel that only appears
## once a hero has spawned would pop in a frame late every single run.
func _build_hero_panels() -> void:
	var count := clampi(GameManager.player_count, 1, 2)
	for pid in range(1, count + 1):
		var right := pid == 2
		var panel := HeroPanel.new()
		panel.setup(pid, right)
		var x := -(M + HeroPanel.PANEL.x) if right else float(M)
		_place(panel, Control.PRESET_BOTTOM_RIGHT if right else Control.PRESET_BOTTOM_LEFT,
			Vector2(x, -(M + HeroPanel.PANEL.y)), HeroPanel.PANEL)
		_heroes[pid] = panel


func _build_readouts() -> void:
	var right := -(M + READOUT_PLATE.x)

	_readout_plate = UIStyle.plate(UIStyle.GOLD, 0.05, UIStyle.RADIUS_LG, UIStyle.Elev.HIGH)
	_place(_readout_plate, Control.PRESET_TOP_RIGHT, Vector2(right, 14.0), READOUT_PLATE)

	var pad := 18.0
	var inner_w := READOUT_PLATE.x - pad * 2.0

	var score_tag := UIStyle.text("SCORE", UIStyle.Scale.MICRO, UIStyle.TEXT_SECONDARY,
		HORIZONTAL_ALIGNMENT_LEFT)
	_place(score_tag, Control.PRESET_TOP_RIGHT, Vector2(right + pad, 26.0), Vector2(80, 16))

	_score_value = UIStyle.text("0", UIStyle.Scale.HEADING, UIStyle.GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	_place(_score_value, Control.PRESET_TOP_RIGHT, Vector2(right + pad, 22.0),
		Vector2(inner_w, 34))

	var rule := UIStyle.divider(2, 0.20)
	_place(rule, Control.PRESET_TOP_RIGHT, Vector2(right + pad, 64.0), Vector2(inner_w, 2))

	var time_tag := UIStyle.text("TIME", UIStyle.Scale.MICRO, UIStyle.TEXT_SECONDARY,
		HORIZONTAL_ALIGNMENT_LEFT)
	_place(time_tag, Control.PRESET_TOP_RIGHT, Vector2(right + pad, 78.0), Vector2(80, 16))

	_timer_value = UIStyle.text("0:00", UIStyle.Scale.SUBHEAD, UIStyle.TEXT_PRIMARY,
		HORIZONTAL_ALIGNMENT_RIGHT)
	_place(_timer_value, Control.PRESET_TOP_RIGHT, Vector2(right + pad, 74.0), Vector2(inner_w, 26))


func _build_combo() -> void:
	# Right edge, vertically centred: clear of the boss banner above it, clear of
	# player two's panel below it, and out of the middle where the fight happens.
	# The splash carries no plate on purpose — it is a transient shout, and a
	# panel that appeared and vanished five times a fight would read as a bug.
	var w := 240.0
	var right := -(M + w)

	# The count lives inside a slot rather than being anchored itself. The shake
	# writes to `position`, and writing position on an anchor-placed control
	# destroys the anchor relationship the layout depends on — so the slot owns
	# the anchors and the label only ever moves relative to (0, 0) inside it.
	_combo_slot = Control.new()
	_combo_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(_combo_slot, Control.PRESET_CENTER_RIGHT, Vector2(right, -60.0), Vector2(w, 84))

	_combo_count = UIStyle.title("", UIStyle.Scale.TITLE, UIStyle.GOLD)
	_combo_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_combo_count.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_combo_slot.add_child(_combo_count)

	_combo_word = UIStyle.text("", UIStyle.Scale.LABEL, UIStyle.GOLD_DEEP, HORIZONTAL_ALIGNMENT_RIGHT)
	_place(_combo_word, Control.PRESET_CENTER_RIGHT, Vector2(right, 10.0), Vector2(w, 20))

	# Depletion rail: the combo window running out, drawn as a shrinking bar so
	# the player can see how long they have to land the next hit.
	_combo_track = Panel.new()
	_combo_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tb := StyleBoxFlat.new()
	tb.bg_color = UIStyle.BASE
	tb.set_corner_radius_all(4)
	tb.set_border_width_all(2)
	tb.border_color = UIStyle.KEYLINE
	_combo_track.add_theme_stylebox_override("panel", tb)
	_place(_combo_track, Control.PRESET_CENTER_RIGHT, Vector2(right + w - 150.0, 36.0),
		Vector2(150, 8))

	_combo_fill = Panel.new()
	_combo_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fb := StyleBoxFlat.new()
	fb.bg_color = UIStyle.GOLD
	fb.set_corner_radius_all(4)
	_combo_fill.add_theme_stylebox_override("panel", fb)
	# Pinned to the track's top-left with all four anchors at 0, so resizing the
	# fill each frame only moves its own offsets. A stretched preset here would
	# have the layout fight the width we set and log an override warning.
	_combo_fill.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_combo_fill.size = Vector2(150, 8)
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
	card.offset_left = -320.0
	card.offset_right = 320.0
	card.offset_top = -160.0
	card.offset_bottom = 160.0
	_pause.add_child(card)

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", UIStyle.SPACE_MD)
	card.add_child(col)

	col.add_child(UIStyle.title("PAUSED", UIStyle.Scale.TITLE, UIStyle.GOLD))
	col.add_child(UIStyle.text("The giant is waiting.", UIStyle.Scale.BODY,
		UIStyle.TEXT_SECONDARY, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(UIStyle.divider(3, 0.20))

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
	_tick_score(delta)
	_tick_combo(delta)
	_tick_heroes()


## Roll the score up instead of snapping, and keep it lit while it moves. A
## number that counts feels earned; a number that jumps is just a variable being
## printed, and one that counts without changing colour is easy to miss entirely.
func _tick_score(delta: float) -> void:
	if _score_glow > 0.0:
		_score_glow = maxf(0.0, _score_glow - delta / SCORE_GLOW)
		_score_value.add_theme_color_override("font_color",
			UIStyle.GOLD.lerp(Color.WHITE, 0.55 * _score_glow))

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
	if _combo_shake > 0.0:
		_combo_shake_phase += delta
		_combo_shake = maxf(0.0, _combo_shake - _combo_shake * COMBO_SHAKE_LAMBDA * delta
			- delta * 0.5)
		# Two out-of-phase sinusoids rather than random offsets: it reads as a
		# struck object ringing down, and it is identical on every run, which
		# `randf()` here would not be.
		var swing := _combo_shake * COMBO_SHAKE
		_combo_count.position = Vector2(
			sin(_combo_shake_phase * COMBO_SHAKE_HZ) * swing,
			sin(_combo_shake_phase * COMBO_SHAKE_HZ * 0.73) * swing * 0.6)
	elif _combo_count.position != Vector2.ZERO:
		_combo_count.position = Vector2.ZERO

	if _combo_value < 2:
		return
	_combo_left = maxf(0.0, _combo_left - delta)
	var frac := _combo_left / GameManager.COMBO_TIMEOUT
	_combo_fill.size.x = _combo_track.size.x * frac
	if _combo_left <= 0.0:
		_end_combo()


## Ability cooldowns and i-frames are STATE, not events — there is no signal for
## them — so they are read once a frame off the `players` group, which is the
## documented runtime-lookup contract. Only `player_id` and the two public
## readout methods are touched; no player script is reached into.
func _tick_heroes() -> void:
	for p in get_tree().get_nodes_in_group("players"):
		if not p.has_method("get_ability_fraction"):
			continue
		var pid := int(p.player_id) if "player_id" in p else 1
		var panel: HeroPanel = _heroes.get(pid)
		if panel == null:
			continue
		panel.set_ability(float(p.get_ability_fraction()))
		panel.set_invulnerable(p.has_method("is_invulnerable") and bool(p.is_invulnerable()))


# --- Signals ------------------------------------------------------------------

func _on_game_started() -> void:
	for panel: HeroPanel in _heroes.values():
		panel.reset()
	_boss_bar.reset_to(float(GameManager.MAX_BOSS_HEALTH))
	_boss_bar.set_fill_color(UIStyle.BOSS_AMBER)
	_score_shown = 0.0
	_score_target = 0.0
	_score_glow = 0.0
	_score_value.text = "0"
	_score_value.add_theme_color_override("font_color", UIStyle.GOLD)
	_timer_value.text = "0:00"
	_fx.set_danger(0.0)
	_pops.clear_all()
	_end_combo()
	_set_phase(1)


func _on_player_damaged(player_id: int, amount: int, new_health: int) -> void:
	var panel: HeroPanel = _heroes.get(player_id)
	if panel == null:
		return
	panel.set_health(new_health, amount > 0)

	# The edge glow belongs to the party, not to player one: it tracks whichever
	# hero is closest to going down, so in co-op it is still telling you
	# something the moment either of you is in trouble.
	_fx.set_danger(_party_danger())

	if amount > 0:
		panel.take_hit(amount)
		# Bigger hits bloom harder. A 6 dmg graze and an 18 dmg slam should not
		# look the same.
		_fx.flash(clampf(0.35 + float(amount) / 28.0, 0.35, 1.0))
		_spawn_player_damage_number(player_id, amount)


func _on_player_respawned(player_id: int) -> void:
	var panel: HeroPanel = _heroes.get(player_id)
	if panel != null:
		panel.revive()


## Worst living hero, as a 0..1 danger level. A hero already at zero is out of
## the fight and stops driving the glow — otherwise the screen would sit at full
## red for the whole of the survivor's comeback.
func _party_danger() -> float:
	var worst := 0.0
	for pid: int in _heroes:
		var hp := float(GameManager.player_health.get(pid, GameManager.MAX_PLAYER_HEALTH))
		if hp <= 0.0:
			continue
		var ratio := hp / float(GameManager.MAX_PLAYER_HEALTH)
		if ratio <= DANGER_RATIO:
			worst = maxf(worst, 1.0 - ratio / DANGER_RATIO)
	return worst


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
		_rng.randf_range(-1.4, 1.4), 8.6 + _rng.randf_range(-0.4, 0.4),
		_rng.randf_range(-1.0, 1.0))
	var tint := UIStyle.GOLD if crit else UIStyle.TEXT_PRIMARY
	_pops.pop_at_world(str(amount), head, tint, crit)


## Damage TAKEN also gets a number, in the hero's danger colour and prefixed so it
## can never be mistaken for damage dealt. The impact contract asks for a UI
## acknowledgement on every hit, and until now a hit on a hero produced only a
## bar move in the corner of the screen — which is precisely the feedback the
## contract says is not enough on its own.
func _spawn_player_damage_number(player_id: int, amount: int) -> void:
	for p in get_tree().get_nodes_in_group("players"):
		if not (p is Node3D):
			continue
		var pid := int(p.player_id) if "player_id" in p else 1
		if pid != player_id:
			continue
		var at: Vector3 = (p as Node3D).global_position + Vector3(
			_rng.randf_range(-0.5, 0.5), 2.4, _rng.randf_range(-0.4, 0.4))
		_pops.pop_at_world("-%d" % amount, at, UIStyle.DANGER, false)
		return


func _on_score_changed(new_score: int) -> void:
	_score_target = float(new_score)
	_score_glow = 1.0


func _on_combo_changed(player_id: int, combo: int) -> void:
	if combo < 2:
		_end_combo()
		return
	_combo_value = combo
	_combo_left = GameManager.COMBO_TIMEOUT
	# Digits only in the display face — Bangers is a decorative Latin set and a
	# missing glyph there falls back to the engine default, which looks broken.
	_combo_count.text = str(combo)
	# In co-op the chain is shared, so the splash names whose blow extended it.
	# Without that, two players both see the same "7" and neither knows who
	# earned it. Plain ASCII: a middot or an en dash is a tofu box on the web
	# export, where there is no system font to fall back to.
	_combo_word.text = ("P%d HIT COMBO" % player_id) if _heroes.size() > 1 else "HIT COMBO"
	_set_combo_visible(true)

	# Higher combos run hotter: the chain starts in the hero's own colour and
	# climbs through gold to ember, so a long chain is visibly a different thing
	# from a two-hit one.
	var heat := clampf((combo - 2) / 8.0, 0.0, 1.0)
	var start := UIStyle.actor_color(UIStyle.actor_for_player(player_id)).lerp(UIStyle.GOLD, 0.72)
	var tint := start.lerp(UIStyle.EMBER, heat)
	_combo_count.add_theme_color_override("font_color", tint)
	_combo_word.add_theme_color_override("font_color", tint.darkened(0.15))
	(_combo_fill.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = tint

	# Pop AND shake. The pop says "this went up"; the shake says "you hit
	# something". A counter that only scales reads as a UI transition.
	_combo_count.pivot_offset = Vector2(_combo_count.size.x, _combo_count.size.y * 0.5)
	var pop := 1.34 - 0.12 * heat
	_combo_count.scale = Vector2(pop, pop)
	_combo_shake = 1.0
	_combo_shake_phase = 0.0
	var t := create_tween()
	t.tween_property(_combo_count, "scale", Vector2.ONE, 0.26) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _end_combo() -> void:
	_combo_value = 0
	_combo_left = 0.0
	_combo_shake = 0.0
	_combo_count.position = Vector2.ZERO
	_set_combo_visible(false)


func _set_combo_visible(on: bool) -> void:
	for n in [_combo_slot, _combo_word, _combo_track]:
		if n:
			(n as CanvasItem).visible = on


func _on_timer_updated(seconds: float) -> void:
	_timer_value.text = UIProgress.format_time(seconds)


func _on_phase_changed(phase: int) -> void:
	_set_phase(phase)
	if phase >= 2:
		_boss_bar.enrage(true)
		_boss_name.add_theme_color_override("font_color", UIStyle.BOSS_RAGE.lightened(0.45))
		# One hard punch on the whole banner so the phase flip is an event, not a
		# colour that quietly changed while you were looking elsewhere.
		var t := create_tween()
		t.tween_property(_boss_bar, "modulate", Color(2.2, 1.2, 1.1), 0.10)
		t.tween_property(_boss_bar, "modulate", Color.WHITE, 0.5)
		var p := create_tween()
		p.tween_property(_boss_plate, "modulate", Color(1.7, 1.15, 1.05), 0.08)
		p.tween_property(_boss_plate, "modulate", Color.WHITE, 0.55)


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
		_boss_plate.modulate = Color.WHITE


func _on_state_changed(new_state: int) -> void:
	_pause.visible = (new_state == GameManager.State.PAUSED)
