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
##   │                     ×5                        ×3                 │
##   │              HIT COMBO ▬▬▬▬              ▬▬▬▬ HIT COMBO          │
##   │  ┌───────────────────┐                    ┌───────────────────┐  │
##   │  │▣ P1 HEROSAURO  (◔)│                    │(◔)  SUPER BOXY P2▣│  │
##   │  │  [==== 84/100 ===]│                    │[=== 100/100 ====] │  │
##   │  └───────────────────┘                    └───────────────────┘  │
##   └──────────────────────────────────────────────────────────────────┘
##
## Three clusters, three jobs. Boss top-centre because it is the thing you are
## fighting and your eyes are already there. THE HEROES ARE MIRROR IMAGES IN THE
## TWO BOTTOM CORNERS — same size, same content, same weight — because this is
## co-op and a HUD that stacks a big player one over a small player two tells the
## second player whose game they are in. Each hero's combo hangs off the inboard
## edge of their own plate; see hero_panel.gd for why it is not one shared splash
## in the middle. Score and timer top-right, small, because they are a post-match
## concern.
##
## Nothing here dims the world. Every cluster is an opaque keylined plate, which
## is what makes the chrome readable over a bright, saturated, high-contrast
## daylight Porto without throwing away the thing that makes it worth looking at.
## The old full-width top and bottom scrims are gone with the golden hour that
## motivated them.
##
## CROSS-STREAM INTERFACE. Everything visible here comes from GameManager's
## signals — `player_damaged(player_id, …)`, `player_respawned`, `boss_damaged`,
## `score_changed`, `combo_changed(player_id, …)`, `timer_updated`,
## `boss_phase_changed` — from `active_player_ids()` for the roster, and from
## `InputManager.action_name()` for the control hints. Plus two group lookups
## (`players`, `boss`) for the things that are positions and fractions rather
## than events. No player or boss script is touched.
##
## THE ROSTER IS NOT A RANGE. `active_player_ids()` is the single authority, and
## a solo run driven as hero 2 returns `[2]` — iterating `range(1, count + 1)`
## builds a panel for a hero who will never spawn and leaves the real one
## unlabelled. The panels are therefore built on `game_started`, not in `_ready`,
## because the roster is chosen in the menu after this scene already exists.

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

# Effects + overlays
var _fx: HitVignette
var _pops: DamageNumbers
var _pause: Control
## Container for the pause overlay's control reference. Rebuilt with the roster,
## because the two heroes are driven by two different sets of hardware.
var _pause_hints: VBoxContainer

var _score_shown: float = 0.0
var _score_target: float = 0.0
var _score_glow: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.seed = POP_SEED

	# Child order is draw order: effects behind, numbers over the world but under
	# the chrome, chrome under the pause sheet. The hero layer is claimed here
	# and filled in later, so a mid-session roster change cannot reorder the HUD.
	_build_effects()
	_build_boss_banner()
	_hero_layer = Control.new()
	_hero_layer.name = "HeroLayer"
	_hero_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_hero_layer)
	_build_readouts()
	_build_pause()
	_sync_roster()

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
func _sync_roster() -> void:
	var roster := GameManager.active_player_ids()
	if _heroes.size() == roster.size():
		var same := true
		for pid in roster:
			if not _heroes.has(pid):
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
	for i in roster.size():
		var pid: int = roster[i]
		var right := i == 1
		var panel := HeroPanel.new()
		panel.setup(pid, right)
		var x := -(M + HeroPanel.PANEL.x) if right else float(M)
		panel.set_anchors_preset(
			Control.PRESET_BOTTOM_RIGHT if right else Control.PRESET_BOTTOM_LEFT)
		var y := -(M + HeroPanel.PANEL.y)
		panel.offset_left = x
		panel.offset_top = y
		panel.offset_right = x + HeroPanel.PANEL.x
		panel.offset_bottom = y + HeroPanel.PANEL.y
		_hero_layer.add_child(panel)
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
	card.offset_left = -400.0
	card.offset_right = 400.0
	card.offset_top = -170.0
	card.offset_bottom = 170.0
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
	# so this is where the reference lives rather than the menu footer. Filled in
	# by _rebuild_pause_hints(), because the bindings depend on the roster.
	_pause_hints = VBoxContainer.new()
	_pause_hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_hints.add_theme_constant_override("separation", UIStyle.SPACE_SM)
	col.add_child(_pause_hints)
	_rebuild_pause_hints()


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
		if roster.size() > 1:
			var actor := UIStyle.actor_for_player(pid)
			row.add_child(UIStyle.pill("P%d" % pid, UIStyle.actor_color(actor), UIStyle.BASE))
		# One cap per direction for Move, one apiece for the rest: a pause overlay
		# is a reminder, not the full controls table, and slot two's pad bindings
		# would otherwise run the row off the card.
		row.add_child(UIStyle.binding_pair("MOVE",
			UIStyle.binding_caps(pid, ["move_up", "move_left", "move_down", "move_right"], 1)))
		row.add_child(UIStyle.binding_pair("JUMP", UIStyle.binding_caps(pid, ["jump"], 1)))
		row.add_child(UIStyle.binding_pair("HIT", UIStyle.binding_caps(pid, ["attack"], 1)))
		row.add_child(UIStyle.binding_pair("SPECIAL", UIStyle.binding_caps(pid, ["ability"], 1)))
		_pause_hints.add_child(row)

	# Pause is not a per-slot action — either player's Esc resumes — so it sits on
	# its own line rather than being repeated in both rows.
	var resume := HBoxContainer.new()
	resume.alignment = BoxContainer.ALIGNMENT_CENTER
	resume.mouse_filter = Control.MOUSE_FILTER_IGNORE
	resume.add_theme_constant_override("separation", UIStyle.SPACE_MD)
	resume.add_child(UIStyle.binding_pair("RESUME", UIStyle.binding_caps(1, ["ui_pause"], 2)))
	_pause_hints.add_child(resume)


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
	_score_shown = 0.0
	_score_target = 0.0
	_score_glow = 0.0
	_score_value.text = "0"
	_score_value.add_theme_color_override("font_color", UIStyle.GOLD)
	_timer_value.text = "0:00"
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
