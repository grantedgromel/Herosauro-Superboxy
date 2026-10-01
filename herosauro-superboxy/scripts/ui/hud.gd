extends Control
## In-game HUD, for two heroes, kid-first.
##
##   +------------------------------------------------------------------+
##   | (II)       +-- ADAMASTOR ------------+        +- * the goal -----+|
##   |            |# [===== boss bar =====] |        |  * * o o    2/4  ||
##   |            +-------------------------+        +------------------+|
##   |            +- (face) a line from the book... -+                   |
##   |            +----------------------------------+                   |
##   |                     x5                        x3                  |
##   |  +-------------------+                    +-------------------+   |
##   |  |# HEROSAURO    (o) |                    | (o)  SUPER BOXY R#|   |
##   |  |  [==== 84/100 ===]|                    |[=== 100/100 ====] |   |
##   |  +-------------------+                    +-------------------+   |
##   +------------------------------------------------------------------+
##
## Boss top-centre, and only while a "boss" node exists: the stadium and the
## street have no giant. The chapter's goal top-right (ObjectiveWidget, fed by
## objective_changed / objective_progress), story beats as toasts under the
## banner (StoryToast), a big pause button top-left. No score and no clock:
## for four-year-olds those are noise, and the goal's stars are the number.
##
## THE HEROES ARE MIRROR IMAGES IN THE TWO BOTTOM CORNERS: same size, same
## content, same weight. In solo with the companion on, both panels still show
## and the AI brother's carries a robot-and-heart badge (HeroPanel).
##
## CROSS-STREAM INTERFACE. Everything visible here comes from GameManager's
## signals, from `active_player_ids()` / `is_ai()` for the roster, from
## StoryData for beat text, and from the `players` / `boss` groups for the
## things that are positions and fractions rather than events.
##
## THE ROSTER IS NOT A RANGE. `active_player_ids()` is the single authority;
## the panels are built on `game_started`, not in `_ready`, because the roster
## is chosen in the menu after this scene already exists.

const BOSS_ACTOR := UIStyle.Actor.ADAMASTOR

# --- Grid ---------------------------------------------------------------------
const M := UIStyle.SCREEN_MARGIN          # screen gutter
## Lean on purpose: the banner is the one HUD piece that stays up for a whole
## fight, over the top of the play view, so it carries a face, a name and a
## bar and nothing a 4-year-old cannot read (no epithet, no "PHASE 1").
const BOSS_PLATE := Vector2(540.0, 84.0)
const BOSS_BAR_H := 24.0
const BOSS_AVATAR := 58.0
## Vertical gap between stacked top-row widgets (banner -> toast).
const STACK_GAP := 10.0
const PAUSE_BUTTON := 88.0
## Hero panel scale in the touch layout, where they stack top-left under the
## pause button and leave both bottom corners to the thumbs.
const COMPACT := 0.72
const COMPACT_GAP := 8.0
## Seconds into a run before the chapter's "start" story beat shows.
const START_BEAT_DELAY := 5.0
## Boss health fraction under which the "low" beat shows.
const LOW_BEAT_RATIO := 0.20

## Fraction of hero health below which the screen edge starts glowing. Read from
## the WORST-off living hero, not from player one: in co-op the danger signal
## belongs to whoever is about to go down.
const DANGER_RATIO := 0.30

## Fixed seed for the damage-number scatter. Explicit because the capture gate
## compares frames pixel for pixel and `randf_range()` would put every floating
## number somewhere new on every run — see ARCHITECTURE.md, "Why the determinism
## rules exist".
const POP_SEED := 0x51500FE1

## Hero panels, keyed by player_id. Rebuilt from `active_player_ids()` whenever
## the roster changes; see `_sync_roster()`.
var _heroes: Dictionary = {}
## Fixed slot in the child list the panels are (re)built into, so a rebuild
## cannot land them on top of the pause sheet. Panels added after `_ready()`
## would otherwise be appended last, i.e. above every overlay.
var _hero_layer: Control

# Boss banner, all under one layer so it can disappear when there is no boss.
var _boss_layer: Control
var _boss_plate: AtlasPlate
var _boss_face: PortraitFrame
var _boss_name: InkText
var _boss_epithet: InkText
var _boss_bar: StatBar
var _boss_hp: InkText
var _phase_label: InkText
var _phase_pips: Array[IconAtlas.Tile] = []

# Storybook
var _objective: ObjectiveWidget
var _toast: StoryToast
var _pause_btn: Button
var _settings: SettingsPanel
var _resume_btn: Button
var _settings_btn: Button
var _book_btn: Button
var _pause_title: Label
var _run_clock := 0.0
var _beats_shown: Dictionary = {}
var _objective_seen := false

# Effects + overlays
var _fx: HitVignette
var _pops: DamageNumbers
var _pause: Control
## Container for the pause overlay's control reference. Rebuilt with the roster,
## because the two heroes are driven by two different sets of hardware.
var _pause_hints: VBoxContainer

var _rng := RandomNumberGenerator.new()
var _building_boss := false

# Touch: the on-screen stick and buttons, and whether the HUD is laid out
# around them (see _apply_layout).
var _touch: TouchControls
var _compact := false
var _roster_order: Array[int] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.seed = POP_SEED

	# Child order is draw order: effects behind, numbers over the world but under
	# the chrome, chrome under the pause sheet. The hero layer is claimed here
	# and filled in later, so a mid-session roster change cannot reorder the HUD.
	_build_effects()
	_boss_layer = Control.new()
	_boss_layer.name = "BossLayer"
	_boss_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_boss_layer)
	_build_boss_banner()
	_hero_layer = Control.new()
	_hero_layer.name = "HeroLayer"
	_hero_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_hero_layer)
	_build_storybook()
	_build_pause()
	_touch = TouchControls.new()
	_touch.pause_target = _pause_btn
	add_child(_touch)
	_touch.active_changed.connect(func(_on: bool) -> void: _apply_layout())
	_compact = _touch.is_active()
	_sync_roster()

	GameManager.player_damaged.connect(_on_player_damaged)
	GameManager.player_respawned.connect(_on_player_respawned)
	GameManager.boss_damaged.connect(_on_boss_damaged)
	GameManager.combo_changed.connect(_on_combo_changed)
	GameManager.boss_phase_changed.connect(_on_phase_changed)
	GameManager.state_changed.connect(_on_state_changed)
	GameManager.game_started.connect(_on_game_started)
	GameManager.objective_changed.connect(_on_objective_changed)
	GameManager.objective_progress.connect(_on_objective_progress)
	GameManager.story_beat.connect(_on_story_beat)
	GameManager.settings_changed.connect(_refresh_text)


# --- Build --------------------------------------------------------------------

func _build_effects() -> void:
	_fx = HitVignette.new()
	add_child(_fx)

	_pops = DamageNumbers.new()
	add_child(_pops)


func _build_boss_banner() -> void:
	_building_boss = true
	var half := BOSS_PLATE.x * 0.5

	# Only a whisper of amber in the fill. The giant's colour is carried by his
	# portrait rim, his health fill and his phase pips; pushing it into the plate
	# as well only neutralises the blue ink and leaves a grey slab.
	# Atlas first (plate, portrait, bar, pips: one batch), then the text.
	_boss_plate = AtlasPlate.make(UIStyle.BOSS_AMBER, 0.06, UIStyle.RADIUS_LG, UIStyle.Elev.HIGH)
	_place(_boss_plate, Control.PRESET_CENTER_TOP, Vector2(-half, 14.0), BOSS_PLATE)

	_boss_face = PortraitFrame.new()
	_boss_face.actor = BOSS_ACTOR
	_boss_face.stamped = true
	_place(_boss_face, Control.PRESET_CENTER_TOP,
		Vector2(-half + 14.0, 14.0 + (BOSS_PLATE.y - BOSS_AVATAR) * 0.5),
		Vector2(BOSS_AVATAR, BOSS_AVATAR))

	var text_x := -half + 14.0 + BOSS_AVATAR + 14.0
	var text_w := BOSS_PLATE.x - 28.0 - BOSS_AVATAR - 18.0

	_boss_bar = StatBar.new()
	_boss_bar.setup(StatBar.Variant.BOSS, float(GameManager.MAX_BOSS_HEALTH), UIStyle.BOSS_AMBER, 10)
	_boss_bar.phase_marker = GameManager.BOSS_PHASE2_RATIO
	_place(_boss_bar, Control.PRESET_CENTER_TOP, Vector2(text_x, 14.0 + BOSS_PLATE.y - 14.0 - BOSS_BAR_H),
		Vector2(text_w, BOSS_BAR_H))

	# The chip's keyline and white face, tinted per pip: ink times gold is
	# still ink, so one stamp serves every state.
	var chip := UIStyle.chip(Color.WHITE, 11.0)
	var chip_box := IconAtlas.box("chip:11", [chip.get_theme_stylebox("panel")])
	chip.free()
	for i in 2:
		var pip := IconAtlas.tile(chip_box, UIStyle.GOLD if i == 0 else UIStyle.HAIRLINE_STRONG)
		_place(pip, Control.PRESET_CENTER_TOP,
			Vector2(text_x + text_w - 34.0 + i * 18.0, 30.0), Vector2(14, 14))
		_phase_pips.append(pip)

	_boss_name = UIStyle.ink(UIStyle.actor_name(BOSS_ACTOR), UIStyle.Scale.HEADING,
		UIStyle.TEXT_PRIMARY, HORIZONTAL_ALIGNMENT_LEFT)
	_place(_boss_name, Control.PRESET_CENTER_TOP, Vector2(text_x, 18.0), Vector2(text_w * 0.6, 32))

	_boss_hp = UIStyle.ink("", UIStyle.Scale.LABEL, UIStyle.TEXT_SECONDARY,
		HORIZONTAL_ALIGNMENT_RIGHT)
	_place(_boss_hp, Control.PRESET_CENTER_TOP, Vector2(text_x + text_w * 0.6, 20.0),
		Vector2(text_w * 0.4 - 40.0, 26))

	# Epithet and phase are kept (live, translated, for anything that reads
	# them) but not drawn: 12 px caps saying "THE GIANT OF THE DOURO" and
	# "PHASE 1" are noise to a pre-reader, and the two pips carry the phase.
	# Their boxes still butt up against each other on the plate.
	_boss_epithet = UIStyle.ink(Loc.t("boss_epithet"), UIStyle.Scale.MICRO,
		UIStyle.TEXT_SECONDARY, HORIZONTAL_ALIGNMENT_LEFT)
	_place(_boss_epithet, Control.PRESET_CENTER_TOP, Vector2(text_x, 30.0),
		Vector2(text_w - 138.0, 16))

	_phase_label = UIStyle.ink(Loc.f("phase", [1]), UIStyle.Scale.MICRO, UIStyle.GOLD,
		HORIZONTAL_ALIGNMENT_RIGHT)
	_place(_phase_label, Control.PRESET_CENTER_TOP, Vector2(text_x + text_w - 106.0, 30.0),
		Vector2(72, 16))
	_building_boss = false
	# Kids do not read "250 / 500"; the bar is the number.
	_boss_hp.visible = false
	_boss_epithet.visible = false
	_phase_label.visible = false


## Bring the hero panels in line with the session's actual roster.
##
## Driven by `GameManager.active_player_ids()`, which is the single roster
## authority — NOT by `player_count`, and never by a range over it. A solo run
## driven as hero 2 has a roster of `[2]`; a range would build player one's panel
## for a hero who is never spawned, and leave the hero who IS in the world with
## no readout at all.
##
## Not driven by the `players` group either: the group is empty while the HUD is
## constructed (main.gd builds the world after the UI layer), so a panel that
## waited for a spawn would pop in a frame late every single run.
##
## Called from `_ready()` for the boot case and again from `game_started`, which
## is the only hook that fires after the menu has chosen a roster. A run whose
## roster is unchanged keeps its panels rather than discarding them, so a restart
## does not throw away live tweens for nothing.
func _sync_roster(rebuild: bool = false) -> void:
	var roster := GameManager.active_player_ids()
	if _heroes.size() == roster.size() and not rebuild:
		var same := true
		for pid in roster:
			# Same ids but a different driver (co-op <-> solo with the AI
			# brother) is a different roster: his panel wears the robot badge.
			if not _heroes.has(pid) or (_heroes[pid] as HeroPanel).is_ai != GameManager.is_ai(pid) \
					or (_heroes[pid] as HeroPanel).compact != _compact:
				same = false
		if same:
			return

	for panel: HeroPanel in _heroes.values():
		_hero_layer.remove_child(panel)
		panel.queue_free()
	_heroes.clear()

	# The SECOND hero on the roster takes the mirrored right-hand slot, whoever
	# that is. Mirroring is a position in a pair, not a property of a player id:
	# a lone hero 2 belongs in the same bottom-left slot a lone hero 1 would take,
	# because there is nothing on the other side of the screen to mirror against.
	_roster_order.clear()
	for i in roster.size():
		var pid: int = roster[i]
		# Compact panels stack in one column, so none of them is mirrored.
		var right := i == 1 and not _compact
		var panel := HeroPanel.new()
		panel.compact = _compact
		panel.setup(pid, right)
		_hero_layer.add_child(panel)
		_heroes[pid] = panel
		_roster_order.append(pid)
		# A rebuild mid-run (the touch layout switching) keeps the live health.
		if GameManager.player_health.has(pid):
			panel.set_health(int(GameManager.player_health[pid]), false)
	_place_panels()


## Bottom corners, mirrored (the default), or stacked top-left under the pause
## button at COMPACT scale while the touch controls own the bottom corners.
func _place_panels() -> void:
	for i in _roster_order.size():
		var panel: HeroPanel = _heroes.get(_roster_order[i])
		if panel == null:
			continue
		if _compact:
			panel.base_scale = COMPACT
			panel.scale = Vector2.ONE * COMPACT
			panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
			# Laid out by where it is DRAWN: the panel scales about its centre
			# pivot, so its box sits PANEL * 0.5 * (1 - COMPACT) inside its rect.
			var top := _compact_top() + i * (HeroPanel.PANEL.y * COMPACT + COMPACT_GAP)
			var inset := HeroPanel.PANEL * 0.5 * (1.0 - COMPACT)
			panel.offset_left = M - inset.x
			panel.offset_top = top - inset.y
			panel.offset_right = panel.offset_left + HeroPanel.PANEL.x
			panel.offset_bottom = panel.offset_top + HeroPanel.PANEL.y
			continue
		var right := i == 1
		panel.base_scale = 1.0
		panel.scale = Vector2.ONE
		var x := -(M + HeroPanel.PANEL.x) if right else float(M)
		panel.set_anchors_preset(
			Control.PRESET_BOTTOM_RIGHT if right else Control.PRESET_BOTTOM_LEFT)
		var y := -(M + HeroPanel.PANEL.y)
		panel.offset_left = x
		panel.offset_top = y
		panel.offset_right = x + HeroPanel.PANEL.x
		panel.offset_bottom = y + HeroPanel.PANEL.y
	if _touch != null:
		_touch.set_stick_top(_compact_bottom() + 24.0)


func _compact_top() -> float:
	return 14.0 + PAUSE_BUTTON + 10.0


## Bottom edge of the compact column (the stick may appear below it).
func _compact_bottom() -> float:
	var n := maxi(1, _roster_order.size())
	return _compact_top() + n * HeroPanel.PANEL.y * COMPACT + (n - 1) * COMPACT_GAP


## The touch controls appeared or went away: lay the HUD out around them.
func _apply_layout() -> void:
	var want := _touch != null and _touch.is_active()
	if want == _compact:
		return
	_compact = want
	_sync_roster(true)


func _build_storybook() -> void:
	_objective = ObjectiveWidget.new()
	_objective.name = "Objective"
	add_child(_objective)
	_objective.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_objective.offset_left = -(M + ObjectiveWidget.W)
	_objective.offset_top = 14.0
	_objective.offset_right = -M
	_objective.offset_bottom = 14.0 + 120.0

	_toast = StoryToast.new()
	_toast.name = "StoryToast"
	add_child(_toast)
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_left = -StoryToast.W * 0.5
	_toast.offset_right = StoryToast.W * 0.5
	_toast.offset_top = 14.0
	_toast.offset_bottom = 14.0 + StoryToast.H

	_pause_btn = BookKit.round_button(KidIcon.Kind.PAUSE, BookKit.SKY, PAUSE_BUTTON)
	_pause_btn.name = "PauseButton"
	_pause_btn.focus_mode = Control.FOCUS_NONE
	_stamp_icon(_pause_btn, KidIcon.Kind.PAUSE, UIStyle.TEXT_PRIMARY)
	_pause_btn.pressed.connect(func() -> void:
		if GameManager.state == GameManager.State.PLAYING:
			GameManager.toggle_pause())
	add_child(_pause_btn)
	_pause_btn.position = Vector2(M, 14.0)


func _build_pause() -> void:
	_pause = Control.new()
	_pause.name = "Pause"
	_pause.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause.visible = false
	add_child(_pause)

	var dim := ColorRect.new()
	dim.color = UIStyle.OVERLAY
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause.add_child(dim)

	var card := PanelContainer.new()
	card.name = "PauseCard"
	card.add_theme_stylebox_override("panel", BookKit.paper_box(36, 30))
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	_pause.add_child(card)

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", UIStyle.SPACE_MD + 4)
	card.add_child(col)

	_pause_title = BookKit.loud_label(Loc.t("paused"), 64, BookKit.SUN)
	col.add_child(_pause_title)
	_resume_btn = BookKit.button(Loc.t("resume"), KidIcon.Kind.PLAY, BookKit.LEAF, Vector2(440, 84))
	_resume_btn.name = "Resume"
	_resume_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_resume_btn.pressed.connect(func() -> void:
		if GameManager.state == GameManager.State.PAUSED:
			GameManager.toggle_pause())
	col.add_child(_resume_btn)
	_settings_btn = BookKit.button(Loc.t("settings"), KidIcon.Kind.GEAR, BookKit.SKY, Vector2(440, 84))
	_settings_btn.name = "SettingsButton"
	_settings_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_settings_btn.pressed.connect(func() -> void: _settings.open())
	col.add_child(_settings_btn)
	_book_btn = BookKit.button(Loc.t("back_to_book"), KidIcon.Kind.BOOK, BookKit.PLUM, Vector2(440, 84))
	_book_btn.name = "BackToBook"
	_book_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_book_btn.pressed.connect(func() -> void: GameManager.go_to_menu())
	col.add_child(_book_btn)
	col.add_child(UIStyle.divider(3, 0.20))

	# The control reference, for the grown-up reading over the child's
	# shoulder. Filled in by _rebuild_pause_hints(): the bindings depend on the
	# roster.
	var strip := PanelContainer.new()
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_theme_stylebox_override("panel", UIStyle.surface(UIStyle.Elev.LOW, UIStyle.RADIUS_MD,
		UIStyle.SPACE_MD))
	col.add_child(strip)
	_pause_hints = VBoxContainer.new()
	_pause_hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_hints.add_theme_constant_override("separation", UIStyle.SPACE_SM)
	strip.add_child(_pause_hints)
	_rebuild_pause_hints()

	_settings = SettingsPanel.new()
	_settings.name = "Settings"
	add_child(_settings)
	_settings.closed.connect(func() -> void:
		if _pause.visible:
			_resume_btn.grab_focus())


## One hint row per hero on the roster, read live out of the Input Map.
##
## CO-OP HAS TWO BINDING SETS AND THEY SHARE NOTHING. Slot one is WASD and the
## mouse; slot two is a pad, or the IJKL cluster on a pad-less couch. A pause
## screen that shows WASD to both players is telling player two something that is
## simply false, and a hard-coded list is a lie the moment anyone rebinds
## anything — so every glyph here comes from
## `InputManager.action_name(player, action)` through the live InputMap.
func _rebuild_pause_hints() -> void:
	if _pause_hints == null:
		return
	for c in _pause_hints.get_children():
		_pause_hints.remove_child(c)
		c.queue_free()

	var roster := GameManager.active_player_ids()
	for pid in roster:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", UIStyle.SPACE_MD)
		# Only label the rows when there is more than one; a solo player does not
		# need to be told which of the one players they are.
		if GameManager.is_ai(pid):
			row.free()
			continue
		if GameManager.player_count > 1:
			var actor := UIStyle.actor_for_player(pid)
			row.add_child(UIStyle.pill("P%d" % pid, UIStyle.actor_color(actor), UIStyle.BASE))
		# One cap per direction for Move, one apiece for the rest: a pause overlay
		# is a reminder, not the full controls table, and slot two's pad bindings
		# would otherwise run the row off the card.
		row.add_child(UIStyle.binding_pair(Loc.t("move"),
			UIStyle.binding_caps(pid, ["move_up", "move_left", "move_down", "move_right"], 1)))
		row.add_child(UIStyle.binding_pair(Loc.t("jump"), UIStyle.binding_caps(pid, ["jump"], 1)))
		row.add_child(UIStyle.binding_pair(Loc.t("hit"), UIStyle.binding_caps(pid, ["attack"], 1)))
		row.add_child(UIStyle.binding_pair(Loc.t("special"), UIStyle.binding_caps(pid, ["ability"], 1)))
		_pause_hints.add_child(row)

	# Pause is not a per-slot action — either player's Esc resumes — so it sits on
	# its own line rather than being repeated in both rows.
	var resume := HBoxContainer.new()
	resume.alignment = BoxContainer.ALIGNMENT_CENTER
	resume.mouse_filter = Control.MOUSE_FILTER_IGNORE
	resume.add_theme_constant_override("separation", UIStyle.SPACE_MD)
	resume.add_child(UIStyle.binding_pair(Loc.t("resume").to_upper(), UIStyle.binding_caps(1, ["ui_pause"], 2)))
	_pause_hints.add_child(resume)
	# The kit's hint rows are MICRO (12 px): fine on a console results card,
	# too small for the grown-up reading this over a child's shoulder.
	_grow_text(_pause_hints, PAUSE_HINT_PX)


const PAUSE_HINT_PX := 17


static func _grow_text(n: Node, px: int) -> void:
	for c in n.get_children():
		if c is Label:
			(c as Label).add_theme_font_size_override("font_size", px)
		_grow_text(c, px)


## Swap a BookKit button's live KidIcon for the same picture from the
## IconAtlas: one textured rect instead of a dozen polygons, every frame.
func _stamp_icon(b: Button, kind: int, tint: Color) -> void:
	var live := b.get_meta("icon", null) as Control
	if live == null:
		return
	var sprite := IconAtlas.sprite(IconAtlas.icon(kind, live.size.x, tint), live.size)
	sprite.set_anchors_preset(Control.PRESET_CENTER)
	sprite.offset_left = live.offset_left
	sprite.offset_top = live.offset_top
	sprite.offset_right = live.offset_right
	sprite.offset_bottom = live.offset_bottom
	b.remove_child(live)
	live.queue_free()
	b.add_child(sprite)
	b.set_meta("icon", sprite)


func _place(ctrl: Control, preset: int, pos: Vector2, dims: Vector2) -> Control:
	(_boss_layer if _boss_layer != null and _building_boss else self).add_child(ctrl)
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
	_tick_heroes()
	_tick_story(delta)


## Story beats on a clock and the boss banner's presence. The banner shows
## only while a "boss" node exists (a lookup a frame is cheap next to a stale
## giant's face over the football stadium).
func _tick_story(delta: float) -> void:
	_boss_layer.visible = get_tree().get_first_node_in_group("boss") != null
	# Under the giant's banner when there is one; otherwise in the top row,
	# centred in the gap between the pause button and the goal.
	var shift := 0.0
	var k := 1.0
	if _boss_layer.visible:
		_toast.offset_top = 14.0 + BOSS_PLATE.y + STACK_GAP
	else:
		_toast.offset_top = 14.0
	# Always centred in the gap between the left column (the pause button, plus
	# the compact hero panels in the touch layout) and the goal, and scaled
	# down if the gap is narrower than the toast: under the banner it sits
	# higher than the goal's bottom edge, so it must clear the goal sideways.
	var gap_l := M + (HeroPanel.PANEL.x * COMPACT if _compact else PAUSE_BUTTON) + 12.0
	var gap_r := size.x - M - ObjectiveWidget.W - 12.0
	k = clampf((gap_r - gap_l) / StoryToast.W, 0.6, 1.0)
	shift = (gap_l + gap_r) * 0.5 - size.x * 0.5
	_toast.scale = Vector2(k, k)
	_toast.offset_bottom = _toast.offset_top + StoryToast.H
	_toast.offset_left = -StoryToast.W * 0.5 * k + shift
	_toast.offset_right = _toast.offset_left + StoryToast.W
	if GameManager.state != GameManager.State.PLAYING:
		return
	var was := _run_clock
	_run_clock += delta
	if was < START_BEAT_DELAY and _run_clock >= START_BEAT_DELAY:
		_beat_when("start")
	# A level that never sets a goal (the bridge) still shows the chapter's.
	if was < 0.6 and _run_clock >= 0.6 and not _objective_seen:
		var ch := StoryData.chapter(GameManager.chapter_id)
		var goal: Dictionary = ch.get("objective", {})
		if not goal.is_empty():
			_objective.set_objective(goal, 0, 0)


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
		var frac := float(p.get_ability_fraction())
		panel.set_ability(frac)
		panel.set_invulnerable(p.has_method("is_invulnerable") and bool(p.is_invulnerable()))
		if _touch.is_shown() and pid == _touch.hero():
			_touch.set_ability(frac)


# --- Signals ------------------------------------------------------------------

func _on_game_started() -> void:
	# The roster is chosen in the menu, long after this scene was built, so this
	# is the only hook that can see it. Panels first: the health and combo sync
	# GameManager pushes immediately after `game_started` has to land on the
	# panels this run actually fields.
	_sync_roster()
	_rebuild_pause_hints()
	for panel: HeroPanel in _heroes.values():
		panel.reset()
	_boss_bar.reset_to(float(GameManager.MAX_BOSS_HEALTH))
	_boss_bar.set_fill_color(UIStyle.BOSS_AMBER)
	_run_clock = 0.0
	_beats_shown.clear()
	_objective_seen = false
	_objective.reset()
	_toast.clear()
	_fx.set_danger(0.0)
	_pops.clear_all()
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
	if new_health > 0 and float(new_health) < float(GameManager.MAX_BOSS_HEALTH) * LOW_BEAT_RATIO:
		_beat_when("low")
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
	if not is_inside_tree():
		return
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


## Route a chain to the hero who owns it.
##
## `combo_changed`'s player_id is meaningful now — each hero keeps an independent
## chain with its own timeout — so this is a lookup, not a display. A single
## widget fed by both heroes would flicker between two unrelated counts, which is
## why the counter lives in the panel; see hero_panel.gd.
##
## An id with no panel (a hero not on this session's roster) is dropped rather
## than coerced onto player one's readout.
func _on_combo_changed(player_id: int, combo: int) -> void:
	var panel: HeroPanel = _heroes.get(player_id)
	if panel != null:
		panel.set_combo(combo)


func _on_phase_changed(phase: int) -> void:
	_set_phase(phase)
	if phase >= 2:
		_beat_when("phase2")
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
	_phase_label.text = Loc.f("phase", [phase])
	_phase_label.set_meta("phase", phase)
	var hot := UIStyle.BOSS_RAGE if phase >= 2 else UIStyle.GOLD
	_phase_label.add_theme_color_override("font_color", hot)
	for i in _phase_pips.size():
		var lit := i < phase
		_phase_pips[i].color = hot if lit else UIStyle.HAIRLINE_STRONG
	if phase < 2:
		_boss_name.add_theme_color_override("font_color", UIStyle.TEXT_PRIMARY)
		_boss_bar.enrage(false)
		_boss_plate.modulate = Color.WHITE


func _on_state_changed(new_state: int) -> void:
	var paused := new_state == GameManager.State.PAUSED
	_pause.visible = paused
	if paused:
		_resume_btn.call_deferred("grab_focus")
	elif _settings.is_open():
		_settings.close()


# --- Storybook ---------------------------------------------------------------------

func _on_objective_changed(label: Dictionary, done: int, total: int) -> void:
	_objective_seen = true
	_objective.set_objective(label, done, total)


func _on_objective_progress(done: int, total: int) -> void:
	_objective.set_progress(done, total)


## GameManager.story_beat(id): a level asks for a StoryData beat by id. The
## `when` tokens are accepted too, so a level can say "stage2" or "half".
func _on_story_beat(beat_id: String) -> void:
	for b: Dictionary in StoryData.chapter(GameManager.chapter_id).get("beats", []):
		if str(b.get("id", "")) == beat_id or str(b.get("when", "")) == beat_id:
			_show_beat(b)
			return


func _beat_when(trigger: String) -> void:
	for b: Dictionary in StoryData.chapter(GameManager.chapter_id).get("beats", []):
		if str(b.get("when", "")) == trigger:
			_show_beat(b)


## Each beat shows once per run.
func _show_beat(b: Dictionary) -> void:
	var id := str(b.get("id", ""))
	if _beats_shown.has(id):
		return
	_beats_shown[id] = true
	_toast.show_beat(b)


func _refresh_text() -> void:
	_boss_epithet.text = Loc.t("boss_epithet")
	_set_phase(int(_phase_label.get_meta("phase", 1)))
	_pause_title.text = Loc.t("paused")
	BookKit.set_caption(_resume_btn, Loc.t("resume"))
	BookKit.set_caption(_settings_btn, Loc.t("settings"))
	BookKit.set_caption(_book_btn, Loc.t("back_to_book"))
	_rebuild_pause_hints()
	for panel: HeroPanel in _heroes.values():
		panel.refresh_text()
