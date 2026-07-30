extends Node
## Correctness probe for the UI stream. Not shipped.
##
## The plain headless boot only reaches the MENU state, so it exercises none of
## the paths that actually matter: damage, the chip bar, phase two, combos, the
## results card. This drives GameManager through a whole fight against a live
## HUD + GameOver and asserts the widgets ended up where the design says they
## should, then checks the type scale, the contrast budget and the portrait
## pipeline directly.
##
## Three groups of assertion are load-bearing and are the reason this file
## exists at all, because none of them can be caught by reading the code:
##
##   THE CO-OP CONTRACT (_check_two_player). Two panels, identical size, mirror
##   gutters, mirrored internals, driven independently by player_id. This is the
##   assertion that stops the HUD regressing to "player one plus a footnote".
##
##   THE DAYLIGHT BUDGET (_check_surfaces). Opacity floors, keyline weights and
##   contrast ratios, because the world behind this UI is bright and saturated
##   and every one of those numbers is what keeps text on top of it readable.
##
##   THE SPRING (_check_stat_bar). That the health bar OVERSHOOTS rather than
##   easing. A lerp and a spring look identical in a static screenshot and in a
##   diff; the only thing that can tell them apart is sampling the value over
##   the settle, which is what this does.
##
## It runs as a SCENE, not with --script: autoload singletons are only
## instantiated on the normal startup path, and every UI file talks to
## GameManager.
##
## Nothing here can judge how it LOOKS — only that every path runs, the numbers
## are the numbers the comments claim, and nothing overlaps or leaves the frame.
##
## Run:
##   godot --headless --path . scripts/ui/_ui_probe.tscn

const HUDScene: PackedScene = preload("res://scenes/ui/hud.tscn")
const GameOverScene: PackedScene = preload("res://scenes/ui/game_over.tscn")

const VIEW := Vector2(1280, 720)

var _fails := 0
var _cam: Camera3D
var _fake_boss: Node3D
## Fixed 1280x720 stage. The headless window is not the project's viewport size,
## so anchoring against the real root would measure the layout at the wrong
## aspect and every gutter assertion below would be meaningless.
var _stage: SubViewport


func _ready() -> void:
	# Survive the pause-overlay check, which pauses the whole tree.
	process_mode = Node.PROCESS_MODE_ALWAYS

	_stage = SubViewport.new()
	_stage.size = Vector2i(VIEW)
	_stage.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_stage)

	print("=== type scale ===")
	_check_type_scale()
	print("=== palette + elevation ===")
	_check_surfaces()
	print("=== portrait pipeline ===")
	_check_portraits()
	print("=== stat bar behaviour ===")
	await _check_stat_bar()
	print("=== ability dial ===")
	await _check_dial()
	print("=== live HUD fight ===")
	await _check_hud()
	print("=== results card ===")
	await _check_game_over()

	print("")
	if _fails == 0:
		print("UI PROBE: PASS")
	else:
		print("UI PROBE: %d FAILURE(S)" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)


# --- Assertions ---------------------------------------------------------------

func _ok(cond: bool, what: String) -> void:
	if cond:
		print("  ok   %s" % what)
	else:
		_fails += 1
		print("  FAIL %s" % what)


func _near(a: float, b: float, tol: float, what: String) -> void:
	_ok(absf(a - b) <= tol, "%s (%.3f vs %.3f +-%.3f)" % [what, a, b, tol])


# --- Type + colour ------------------------------------------------------------

func _check_type_scale() -> void:
	# Every step must be strictly smaller than the one above it, or it is not a
	# scale, it is a list of numbers.
	var order := [UIStyle.Scale.DISPLAY, UIStyle.Scale.TITLE, UIStyle.Scale.HEADING,
		UIStyle.Scale.SUBHEAD, UIStyle.Scale.BODY, UIStyle.Scale.LABEL,
		UIStyle.Scale.CAPTION, UIStyle.Scale.MICRO]
	var descending := true
	for i in range(1, order.size()):
		if UIStyle.size_of(order[i]) >= UIStyle.size_of(order[i - 1]):
			descending = false
	_ok(descending, "display -> micro is monotonically descending")
	_ok(UIStyle.size_of(UIStyle.Scale.MICRO) >= 11, "micro stays legible (>= 11 px)")

	# Bangers must never be handed body copy or numerals.
	for s in [UIStyle.Scale.BODY, UIStyle.Scale.LABEL, UIStyle.Scale.CAPTION,
			UIStyle.Scale.MICRO, UIStyle.Scale.READOUT]:
		var l := UIStyle.text("123", s)
		var f: Font = l.get_theme_font("font")
		var base: Font = (f as FontVariation).base_font if f is FontVariation else f
		_ok(base != UIStyle.TITLE_FONT, "scale %d uses the UI face, not Bangers" % s)
		l.free()

	# Scale entries and raw pixel sizes must both survive the same entry point,
	# because the menu still calls it the old way.
	var by_scale := UIStyle.title("X", UIStyle.Scale.TITLE)
	var by_px := UIStyle.title("X", 68)
	_ok(by_scale.get_theme_font_size("font_size") == UIStyle.size_of(UIStyle.Scale.TITLE),
		"title(Scale.TITLE) resolves through the scale")
	_ok(by_px.get_theme_font_size("font_size") == 68, "title(68) still means 68 px")
	for l2 in [by_scale, by_px]:
		_ok(l2.get_theme_constant("outline_size") >= 2,
			"outline present at %d px" % l2.get_theme_font_size("font_size"))
		l2.free()

	# Tracking has to survive as a real FontVariation, not be silently dropped.
	var tracked := UIStyle.text("AV", UIStyle.Scale.LABEL)
	_ok(tracked.get_theme_font("font") is FontVariation, "tracked scales get a FontVariation")
	tracked.free()

	# Bangers is a decorative Latin set. Anything it is handed that it does not
	# cover falls back to the engine default mid-word, which looks like a bug —
	# so every string the display face actually renders is checked here.
	var display_strings := ["VICTORY!", "DEFEAT", "PAUSED", "0123456789"]
	for s2 in display_strings:
		var missing := ""
		for i in s2.length():
			if not UIStyle.TITLE_FONT.has_char(s2.unicode_at(i)):
				missing += s2[i]
		_ok(missing.is_empty(), "display face covers \"%s\" %s" % [s2, missing])
	# The UI face carries the glyphs the readouts are built from.
	for s3 in ["0123456789", "/", "-", ",", ":", "."]:
		var gone := ""
		for i in s3.length():
			if not UIStyle.UI_BOLD.has_char(s3.unicode_at(i)):
				gone += s3[i]
		_ok(gone.is_empty(), "UI face covers \"%s\" %s" % [s3, gone])


func _check_surfaces() -> void:
	var flat := UIStyle.surface(UIStyle.Elev.FLAT)
	var modal := UIStyle.surface(UIStyle.Elev.MODAL)
	_ok(modal.shadow_size > flat.shadow_size, "elevation increases shadow")
	_ok(modal.bg_color.v >= flat.bg_color.v, "elevation does not darken the fill")

	# THE DAYLIGHT RULE. The world behind this UI is bright, saturated and moving,
	# and the fix for that is a solid object, not a scrim over the game. A panel
	# that lets 10% of a blown-out river through has already lost the text on it,
	# so the floor here is deliberately high.
	_ok(flat.bg_color.a >= 0.95, "panels are near-opaque (%.2f) for a bright backdrop"
		% flat.bg_color.a)
	# Chunky, not hairline: every physical object in the kit is drawn with a
	# visible ink keyline, and 3 px is the floor at which a stroke still reads as
	# drawn rather than as an anti-aliasing artefact.
	_ok(flat.border_width_top >= 3, "panel keyline is %d px, not a hairline"
		% flat.border_width_top)
	_ok(UIStyle.KEYLINE.a > 0.85 and _lum(UIStyle.KEYLINE) < 0.02,
		"keyline is a near-opaque ink, not a tint")
	_ok(UIStyle.RADIUS_LG >= 24, "large radius (%d) reads as moulded" % UIStyle.RADIUS_LG)

	# Warm identity: the bevel highlight is the warm KEY light landing on the top
	# of a plate. A neutral or cold top rim lights the UI from the sky instead of
	# from the sun, which is what makes a kit look bought rather than authored.
	_ok(UIStyle.HAIRLINE.r > UIStyle.HAIRLINE.b, "bevel highlight is warm, not neutral")
	_ok(UIStyle.TEXT_PRIMARY.r > UIStyle.TEXT_PRIMARY.b, "primary text is warm cream")
	# The ink is the Douro in shade, not a neutral grey — a saturated dark reads
	# as moulded plastic, a desaturated one reads as a web dashboard.
	_ok(UIStyle.SURFACE.b > UIStyle.SURFACE.r + 0.05, "the ink is a saturated blue, not grey")

	var ratio := _contrast(UIStyle.TEXT_PRIMARY, UIStyle.SURFACE)
	_ok(ratio >= 7.0, "text/surface contrast %.1f:1 (AAA)" % ratio)
	var sec := _contrast(UIStyle.TEXT_SECONDARY, UIStyle.SURFACE)
	_ok(sec >= 4.5, "secondary/surface contrast %.1f:1 (AA)" % sec)
	var gold := _contrast(UIStyle.BASE, UIStyle.GOLD)
	_ok(gold >= 4.5, "ink-on-gold button contrast %.1f:1 (AA)" % gold)

	# Each character colour is used two ways, and they have two different budgets.
	# As a GRAPHIC — the portrait rim, the spine bar, the health fill — it sits on
	# a plate tinted toward itself and only has to stay separated from it (3:1,
	# the large-object threshold). As a FILL UNDER TEXT — the P1/P2 badge, the
	# primary button — the ink on top of it is real text and owes the full 4.5:1.
	for actor in [UIStyle.Actor.HEROSAURO, UIStyle.Actor.SUPERBOXY, UIStyle.Actor.ADAMASTOR]:
		var tint := UIStyle.actor_color(actor)
		var who := UIStyle.actor_name(actor)
		var on_plate := _contrast(tint, UIStyle.SURFACE.lerp(tint, 0.18))
		_ok(on_plate >= 3.0, "%s reads against its own plate %.1f:1" % [who, on_plate])
		var badge := _contrast(UIStyle.BASE, tint)
		_ok(badge >= 4.5, "ink on the %s badge %.1f:1 (AA)" % [who, badge])
	# The two heroes must be told apart at a glance, from the corner of the eye,
	# by colour alone — that is the whole basis of the mirrored co-op HUD.
	var p1 := UIStyle.actor_color(UIStyle.Actor.HEROSAURO)
	var p2 := UIStyle.actor_color(UIStyle.Actor.SUPERBOXY)
	var apart := absf(p1.h - p2.h)
	_ok(minf(apart, 1.0 - apart) > 0.15,
		"hero colours are %.0f degrees apart on the wheel" % (minf(apart, 1.0 - apart) * 360.0))


func _contrast(a: Color, b: Color) -> float:
	var la := _lum(a)
	var lb := _lum(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func _lum(c: Color) -> float:
	var ch := [c.r, c.g, c.b]
	var out := [0.0, 0.0, 0.0]
	for i in 3:
		var v: float = ch[i]
		out[i] = v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * out[0] + 0.7152 * out[1] + 0.0722 * out[2]


func _check_portraits() -> void:
	for actor in [UIStyle.Actor.HEROSAURO, UIStyle.Actor.SUPERBOXY, UIStyle.Actor.ADAMASTOR]:
		var who := UIStyle.actor_name(actor)
		var head := UIStyle.portrait_head(actor, 256)
		_ok(head != null and head.get_width() == 256 and head.get_height() == 256,
			"%s head crop is 256x256" % who)
		# The crop has to contain a face, not empty canvas.
		var img := head.get_image()
		var covered := 0
		for y in range(0, 256, 8):
			for x in range(0, 256, 8):
				if img.get_pixel(x, y).a > 0.35:
					covered += 1
		var frac := float(covered) / float(32 * 32)
		_ok(frac > 0.20, "%s head crop is %.0f%% opaque (a face, not canvas)" % [who, frac * 100.0])
		_ok(img.has_mipmaps(), "%s head crop carries mipmaps" % who)
		# Cached, so rebuilding the HUD does not re-run Lanczos on a 900 px sheet.
		_ok(UIStyle.portrait_head(actor, 256) == head, "%s head crop is cached" % who)

		var tall := UIStyle.portrait_scaled(actor, 480)
		_ok(tall != null and tall.get_height() == 480, "%s figure scales to 480 px tall" % who)
		# The Super Boxy sheet carries a front pose AND a back pose stacked on it,
		# so a full-figure crop that took the whole sheet came back roughly twice
		# as tall as it was wide and drew two characters. Aspect is the cheap test
		# for that: every one of these figures is a standing person or giant, and
		# none of them is narrower than 1:4.
		var aspect := float(tall.get_width()) / float(tall.get_height())
		_ok(aspect > 0.25, "%s figure is one pose, not a stacked sheet (aspect %.2f)"
			% [who, aspect])


# --- Widgets ------------------------------------------------------------------

func _check_stat_bar() -> void:
	var bar := StatBar.new()
	bar.setup(StatBar.Variant.HERO, 100.0, UIStyle.HERO_GREEN, 4)
	bar.size = Vector2(320, 22)
	_stage.add_child(bar)
	await get_tree().process_frame

	bar.set_value(40.0)
	# Checked before any frame elapses: FLASH_TIME is 0.18 s and the headless
	# loop's first delta after add_child is not small enough to rely on.
	_ok(bar._flash > 0.0, "hit registers a flash")
	_ok(bar._punch > 0.0, "hit registers a squash punch")
	# THE OVERSHOOT. The fill is a damped spring, not a lerp, so it must go PAST
	# the new value on the way down and come back. Sampled every frame across the
	# settle, because the undershoot lasts a tenth of a second and a single
	# reading after the fact would always miss it.
	# A Dictionary, not two floats: GDScript lambdas capture locals BY VALUE, so
	# a plain `lowest = minf(...)` inside the closure would update a copy and this
	# whole assertion would silently measure nothing. Dictionaries are reference
	# types, so mutating one is visible out here.
	var trace := {"low": 1.0, "gap": 0.0}
	await _wait_until(func() -> bool:
		trace["low"] = minf(trace["low"], bar._shown)
		trace["gap"] = maxf(trace["gap"], bar._ghost - bar._shown)
		return not bar.is_processing(), 6000)
	var lowest: float = trace["low"]
	_ok(lowest < 0.40 - 0.01,
		"fill overshoots past the new value (dipped to %.3f, target 0.400)" % lowest)
	# The chip bar has to stay ABOVE the real fill through the hold window; that
	# separation is the entire point of it.
	_ok(float(trace["gap"]) > 0.30,
		"chip bar trails the fill after a hit (peak gap %.2f)" % trace["gap"])
	_near(bar._ghost, bar._shown, 0.02, "chip bar converges")
	_near(bar._shown, 0.40, 0.02, "fill settles on the new value")
	# Idle bars must stop redrawing, or a static HUD costs a redraw every frame.
	_ok(not bar.is_processing(), "bar sleeps once nothing is animating")

	bar.set_value(90.0, false)
	await _wait_until(func() -> bool: return not bar.is_processing(), 6000)
	_ok(bar._ghost <= bar._shown + 0.02, "healing does not leave a ghost behind")

	bar.reset_to(100.0)
	_near(bar.fraction(), 1.0, 0.001, "reset_to snaps with no animation")

	# Boss variant: heavier, and it recolours on phase change.
	var boss := StatBar.new()
	boss.setup(StatBar.Variant.BOSS, 500.0, UIStyle.BOSS_AMBER, 10)
	boss.phase_marker = 0.5
	_stage.add_child(boss)
	await get_tree().process_frame
	boss.enrage(true)
	await _wait_ms(700)
	_ok(boss._rage > 0.9, "boss bar completes the rage cross-fade (%.2f)" % boss._rage)

	bar.queue_free()
	boss.queue_free()


func _check_dial() -> void:
	var dial := AbilityDial.new()
	dial.size = Vector2(68, 68)
	_stage.add_child(dial)
	await get_tree().process_frame
	dial.setup("E", UIStyle.GOLD)

	dial.set_fraction(0.0)
	_ok(not dial.is_ready(), "dial reads spent at 0.0")
	dial.set_fraction(0.5)
	_ok(not dial.is_ready(), "dial still spent mid-cooldown")
	dial.set_fraction(1.0)
	_ok(dial.is_ready(), "dial reads ready at 1.0")
	_ok(dial._ready_flash > 0.0, "ready transition fires the flash ring")
	dial.queue_free()


# --- Live HUD -----------------------------------------------------------------

func _check_hud() -> void:
	# Damage numbers project through the active 3D camera onto the giant's head,
	# so the probe needs both to exist.
	_cam = Camera3D.new()
	_stage.add_child(_cam)
	_cam.global_position = Vector3(0.0, 8.0, 26.0)
	_cam.look_at(Vector3(0.0, 8.0, 0.0))
	_cam.current = true
	_fake_boss = Node3D.new()
	_fake_boss.add_to_group("boss")
	_stage.add_child(_fake_boss)

	var hud: Control = HUDScene.instantiate()
	_stage.add_child(hud)
	await get_tree().process_frame

	GameManager.start_game()
	await get_tree().process_frame
	await get_tree().process_frame

	_check_two_player(hud)
	_check_bounds(hud)

	var p1: HeroPanel = hud._heroes[1]
	var p2: HeroPanel = hud._heroes[2]

	# A real exchange of blows, all of them player one's.
	GameManager.damage_boss(8, 1)
	GameManager.damage_boss(8, 1)
	GameManager.damage_boss(18, 1)
	await get_tree().process_frame
	_ok(GameManager.combo_for(1) == 3, "combo counted three chained hits")
	_ok(p1._combo_count.visible and p1._combo_count.text == "3", "P1's combo readout shows 3")
	_ok(p1._combo_count.text.is_valid_int(), "combo text is digits only (Bangers-safe)")
	_ok(hud._pops.get_child_count() >= 1,
		"damage numbers spawned (%d)" % hud._pops.get_child_count())

	# THE CHAINS ARE INDEPENDENT. Player one landing three hits must not put a
	# number over player two's head — that is the whole reason the counter moved
	# into the panels instead of staying one shared splash.
	_ok(not p2._combo_count.visible, "P2's combo readout stays clear of P1's chain")
	GameManager.damage_boss(7, 2)
	GameManager.damage_boss(7, 2)
	await get_tree().process_frame
	_ok(GameManager.combo_for(2) == 2, "P2 keeps a chain of their own")
	_ok(p2._combo_count.visible and p2._combo_count.text == "2", "P2's readout shows their own 2")
	_ok(p1._combo_count.text == "3", "P1's readout is untouched by P2's chain")
	# ...and the two are visibly distinguishable, because a chain starting in its
	# owner's colour is the second cue that says whose it is.
	_ok(p1._combo_count.get_theme_color("font_color")
		!= p2._combo_count.get_theme_color("font_color"),
		"the two chains start in different colours")
	# Each counter hangs off its own panel's INBOARD edge, pointing into the
	# fight — so P1's is to the right of P1's plate and P2's to the left of P2's,
	# and they never trade places or collide.
	var c1 := p1.combo_rect()
	var c2 := p2.combo_rect()
	_ok(c1.get_center().x > Rect2(p1.position, p1.size).get_center().x,
		"P1's combo hangs off the inboard (right) edge")
	_ok(c2.get_center().x < Rect2(p2.position, p2.size).get_center().x,
		"P2's combo hangs off the inboard (left) edge")
	_ok(not c1.intersects(c2), "the two combo counters do not collide")
	_ok(Rect2(Vector2.ZERO, VIEW).encloses(c1.merge(c2)),
		"both combo counters stay in frame %s / %s" % [c1, c2])

	GameManager.damage_player(1, 22)
	await get_tree().process_frame
	_ok(p1._hp.text == "78/100", "P1 readout tracks health, got '%s'" % p1._hp.text)
	_near(p1._bar.value, 78.0, 0.01, "P1 bar took the hit")
	# The two panels are independent. A hit on one hero must not move the other.
	_ok(p2._hp.text == "100/100", "P2 readout is untouched, got '%s'" % p2._hp.text)
	_near(p2._bar.value, 100.0, 0.01, "P2 bar is untouched")
	_ok(hud._fx._sustain_level == 0.0, "no danger glow while comfortably alive")

	# ...and player two is a first-class citizen: the same signal drives it.
	GameManager.damage_player(2, 30)
	await get_tree().process_frame
	_ok(p2._hp.text == "70/100", "P2 readout tracks health, got '%s'" % p2._hp.text)
	_near(p2._bar.value, 70.0, 0.01, "P2 bar took the hit")
	_ok(p2._bar._ghost > p2._bar._shown, "P2 bar left a chip trail behind the hit")

	# Drive the boss under half to trip phase two.
	while GameManager.boss_health > int(GameManager.MAX_BOSS_HEALTH * 0.45):
		GameManager.damage_boss(25, 1)
	await get_tree().process_frame
	_ok(GameManager.boss_phase == 2, "boss reached phase two")
	_ok(hud._phase_label.text == "PHASE 2", "phase label updated")
	_ok(hud._boss_bar._rage_target > 0.5, "boss bar is cross-fading to rage")
	_ok(hud._boss_hp.text == "%d / %d" % [GameManager.boss_health, GameManager.MAX_BOSS_HEALTH],
		"boss readout tracks health")

	# Score rolls up rather than snapping, and lands exactly.
	var target := float(GameManager.score)
	_ok(hud._score_shown < target, "score is still rolling up")
	# Wait for the exact landing, not for "close enough" — the roll is asymptotic
	# and the final snap is the part that used to be missing.
	await _wait_until(func() -> bool: return hud._score_shown == target, 6000)
	_near(hud._score_shown, target, 0.001, "score lands exactly on its target")
	_ok(hud._score_value.text == UIProgress.format_score(GameManager.score),
		"score renders grouped: '%s'" % hud._score_value.text)

	# Each hero's combo window expires on its own — GameManager runs one timer per
	# chain, and both counters have to clear off the back of their own.
	await _wait_until(func() -> bool:
		return not p1._combo_count.visible and not p2._combo_count.visible,
		int(GameManager.COMBO_TIMEOUT * 1000.0) + 3000)
	_ok(not p1._combo_count.visible, "P1's combo clears when its window lapses")
	_ok(not p2._combo_count.visible, "P2's combo clears when its window lapses")

	# Low health drives the sustained edge glow, and only then. It reads the
	# WORST-off living hero, so in co-op it is still telling you something the
	# moment either player is in trouble.
	GameManager.damage_player(1, 60)
	await get_tree().process_frame
	_ok(hud._fx._sustain_level > 0.0, "danger vignette engages below the threshold")

	# Going over the side and coming back: the panel pops rather than silently
	# reappearing, and it re-reads the authoritative health table on the way in.
	GameManager.notify_player_respawned(1)
	await get_tree().process_frame
	_ok(p1._hit > 0.0, "player_respawned plays a revive pop on the right panel")
	_ok(not p1._down_veil.visible, "a hero who respawned with health left is not shown as down")

	# A hero at zero is out of the fight and stops driving the glow, or the screen
	# would sit at full red for the whole of the survivor's comeback.
	GameManager.damage_player(1, 999)
	await get_tree().process_frame
	_ok(p1._down_veil.visible, "a downed hero's panel says so")
	_ok(hud._fx._sustain_level == 0.0,
		"a downed hero stops driving the glow (%.2f)" % hud._fx._sustain_level)

	# Pause overlay follows state.
	GameManager.change_state(GameManager.State.PAUSED)
	await get_tree().process_frame
	_ok(hud._pause.visible, "pause overlay shows on PAUSED")
	GameManager.change_state(GameManager.State.PLAYING)
	await get_tree().process_frame
	_ok(not hud._pause.visible, "pause overlay hides on resume")

	# A fresh run must wipe every trace of the last one.
	GameManager.start_game()
	await get_tree().process_frame
	_near(p1._bar.value, 100.0, 0.01, "restart resets P1's bar")
	_near(p2._bar.value, 100.0, 0.01, "restart resets P2's bar")
	_ok(not p1._down_veil.visible, "restart clears the downed state")
	_near(hud._boss_bar.value, float(GameManager.MAX_BOSS_HEALTH), 0.01, "restart resets boss bar")
	_ok(hud._phase_label.text == "PHASE 1", "restart resets the phase label")
	_ok(hud._fx._sustain_level == 0.0, "restart clears the danger vignette")
	_ok(hud._pops.get_child_count() == 0, "restart clears floating numbers")

	hud.queue_free()
	await get_tree().process_frame
	await _check_solo()


## THE ROSTER IS NOT A RANGE.
##
## `active_player_ids()` is the single authority, and the case that breaks a
## `range(1, player_count + 1)` is a solo run driven as HERO 2: the roster is
## `[2]`, the range builds player one's panel for a hero who never spawns, and
## the hero who is actually in the world gets no readout at all. Both solo
## rosters are checked here for exactly that reason.
##
## Also checks the rebuild hook. The roster is chosen in the menu, long after the
## HUD scene was built, so panels created in `_ready()` would be frozen at
## whatever the roster happened to be at boot — this drives a live HUD from one
## roster to the other and back.
func _check_solo() -> void:
	var was_count := GameManager.player_count
	var was_hero := GameManager.human_hero

	var solo: Control = HUDScene.instantiate()
	_stage.add_child(solo)
	await get_tree().process_frame
	_ok(solo._heroes.size() == 2, "the HUD boots on the default co-op roster")

	for hero in [1, 2]:
		GameManager.player_count = 1
		GameManager.human_hero = hero
		# The roster changes in the menu; `game_started` is what tells the HUD.
		GameManager.start_game()
		await get_tree().process_frame

		_ok(solo._heroes.size() == 1,
			"a solo run as hero %d builds one panel (%d)" % [hero, solo._heroes.size()])
		_ok(solo._heroes.has(hero),
			"the panel built is hero %d's, not a range's first entry %s"
			% [hero, str(solo._heroes.keys())])
		if solo._heroes.has(hero):
			var only: HeroPanel = solo._heroes[hero]
			_ok(only.actor == UIStyle.actor_for_player(hero),
				"the solo panel wears hero %d's face" % hero)
			# Mirroring is a position in a pair, not a property of a player id: a
			# lone hero 2 belongs in the same corner a lone hero 1 would take.
			_ok(not only.mirrored, "the solo panel is the unmirrored left-hand one")
			_near(only.position.x, UIStyle.SCREEN_MARGIN, 0.5,
				"the solo panel keeps the left gutter")
		# Signals aimed at the hero who is not in the world must be dropped, not
		# coerced onto the one who is.
		var absent := 2 if hero == 1 else 1
		GameManager.damage_player(absent, 25)
		GameManager.combo_changed.emit(absent, 5)
		await get_tree().process_frame
		_ok(solo._heroes.size() == 1, "signals for an absent hero are ignored cleanly")

	# ...and back to co-op, which must restore both panels rather than leaving the
	# solo one in place.
	GameManager.player_count = was_count
	GameManager.human_hero = was_hero
	GameManager.start_game()
	await get_tree().process_frame
	_ok(solo._heroes.size() == 2, "returning to co-op rebuilds both panels")

	solo.queue_free()
	await get_tree().process_frame


## The co-op contract, measured. Two panels, same size, mirror positions, and
## neither of them dominant. This is the assertion that stops the HUD quietly
## regressing to "player one plus a footnote".
func _check_two_player(hud: Control) -> void:
	_ok(hud._heroes.size() == 2, "two hero panels exist (%d)" % hud._heroes.size())
	if hud._heroes.size() < 2:
		return
	var p1: HeroPanel = hud._heroes[1]
	var p2: HeroPanel = hud._heroes[2]

	_ok(p1.size == p2.size, "both panels are exactly the same size %s / %s"
		% [str(p1.size), str(p2.size)])
	_ok(p1.actor == UIStyle.Actor.HEROSAURO and p2.actor == UIStyle.Actor.SUPERBOXY,
		"P1 is Herosauro and P2 is Super Boxy")
	_ok(p1.accent != p2.accent, "the two panels carry different accent colours")
	_ok(not p1.mirrored and p2.mirrored, "P2's layout is mirrored, P1's is not")
	_ok(p2._bar.mirrored and not p1._bar.mirrored,
		"P2's health drains outward, away from the fight")

	# Mirror symmetry about the screen's vertical centre line, to the pixel.
	var left_gutter := p1.position.x
	var right_gutter := VIEW.x - (p2.position.x + p2.size.x)
	_near(left_gutter, right_gutter, 0.5,
		"the two panels sit on symmetric gutters")
	_near(p1.position.y, p2.position.y, 0.5, "the two panels share a baseline")
	_ok(not Rect2(p1.position, p1.size).intersects(Rect2(p2.position, p2.size)),
		"the two panels do not touch each other")

	# Every element inside a panel must stay inside it, or a mirrored offset has
	# been mis-computed and something is hanging off the plate. The combo cluster
	# is the one deliberate exception — it overhangs the top edge on purpose —
	# and it is identified by sitting at negative y rather than by name, so a
	# control that drifts off any other edge is still caught.
	for panel: HeroPanel in [p1, p2]:
		var box := Rect2(Vector2.ZERO, panel.size).grow(1.0)
		var loose: Array[String] = []
		for c in panel.get_children():
			var ctrl := c as Control
			if ctrl == null or not ctrl.visible:
				continue
			var r := Rect2(ctrl.position, ctrl.size)
			if r.position.y < 0.0:
				continue   # the combo overhang
			if not box.encloses(r):
				loose.append(ctrl.get_class())
		_ok(loose.is_empty(), "P%d's contents stay on its plate %s"
			% [panel.player_id, str(loose)])


## Everything visible must be inside the frame, and the four clusters must not
## collide with each other.
func _check_bounds(hud: Control) -> void:
	var frame := Rect2(Vector2.ZERO, VIEW)
	var offenders: Array[String] = []
	for c in hud.get_children():
		if not (c is Control) or not (c as Control).visible:
			continue
		var ctrl := c as Control
		if ctrl is HitVignette or ctrl is DamageNumbers or ctrl is TextureRect:
			continue   # deliberately full-bleed
		var r := Rect2(ctrl.position, ctrl.size)
		if r.size.x <= 0.0 or r.size.y <= 0.0:
			continue
		if not frame.encloses(r):
			offenders.append("%s%s" % [ctrl.get_class(), r])
	_ok(offenders.is_empty(), "all HUD widgets sit inside 1280x720 %s" % str(offenders))

	var boss := Rect2(hud._boss_plate.position, hud._boss_plate.size)
	var read := Rect2(hud._readout_plate.position, hud._readout_plate.size)
	_ok(not read.intersects(boss), "score plate clears the boss banner %s / %s" % [read, boss])
	_ok(read.end.x <= VIEW.x - UIStyle.SCREEN_MARGIN + 1.0, "readouts respect the right gutter")

	for pid: int in hud._heroes:
		var panel: HeroPanel = hud._heroes[pid]
		var hero := Rect2(panel.position, panel.size)
		# The panel AND its combo overhang, since the overhang is what reaches up
		# toward the boss banner.
		var reach := hero.merge(panel.combo_rect())
		_ok(not reach.intersects(boss), "P%d's cluster clears the boss banner" % pid)
		_ok(not reach.intersects(read), "P%d's cluster clears the score plate" % pid)
		_ok(hero.position.x >= UIStyle.SCREEN_MARGIN - 1.0,
			"P%d respects the left gutter" % pid)
		_ok(hero.end.x <= VIEW.x - UIStyle.SCREEN_MARGIN + 1.0,
			"P%d respects the right gutter" % pid)
		_ok(hero.end.y <= VIEW.y - UIStyle.SCREEN_MARGIN + 1.0,
			"P%d respects the bottom gutter (%.0f)" % [pid, hero.end.y])
		_ok(Rect2(Vector2.ZERO, VIEW).encloses(reach),
			"P%d's cluster stays in frame %s" % [pid, reach])

	# The epithet and the phase readout share a line under the boss bar; their
	# boxes must not run into each other or one will draw over the other.
	var ep := Rect2(hud._boss_epithet.position, hud._boss_epithet.size)
	var hp := Rect2(hud._boss_hp.position, hud._boss_hp.size)
	var ph := Rect2(hud._phase_label.position, hud._phase_label.size)
	var nm := Rect2(hud._boss_name.position, hud._boss_name.size)
	_ok(not ep.intersects(ph), "boss epithet clears the phase label")
	_ok(not nm.intersects(hp), "boss name clears the boss HP readout")
	_ok(boss.grow(1.0).encloses(ep.merge(ph).merge(nm).merge(hp)),
		"the boss banner's contents stay on its plate")


func _check_game_over() -> void:
	var over: Control = GameOverScene.instantiate()
	_stage.add_child(over)
	await get_tree().process_frame

	GameManager.start_game()
	GameManager.score = 1234
	GameManager.fight_time = 92.0
	GameManager._end_game(true)
	# The card deliberately waits out the death pose before it appears.
	await _wait_until(func() -> bool: return over.visible and over._interactive, 12000)

	_ok(over.visible, "results card appeared")
	_ok(over._title.text == "VICTORY!", "victory verdict")
	_ok(over._art.texture != null, "victory shows the hero portrait")
	_ok(over._rows.get_child_count() >= 3, "stat rows present (%d)" % over._rows.get_child_count())
	_ok(over._interactive, "card becomes interactive after the reveal")
	_near(over._card.scale.x, 1.0, 0.02, "card settles at 1:1")
	_near(over._stage.position.y, 0.0, 0.5, "card settles on its baseline")
	_near(over._stage.modulate.a, 1.0, 0.02, "card finishes fading in")

	var card := Rect2(over._card.position, over._card.size)
	_ok(Rect2(Vector2.ZERO, VIEW).encloses(card), "card fits the frame %s" % str(card))
	# The card must not outgrow its own panel, or the buttons fall off the bottom.
	var content := over._card.get_child(0) as Control
	_ok(content.size.y <= over._card.size.y - 2.0 * UIStyle.SPACE_XL + 1.0,
		"card content fits its padding (%.0f in %.0f)" % [content.size.y, over._card.size.y])

	_ok(UIProgress.best_score() >= 1234, "best score persisted")
	_ok(UIProgress.format_score(1234567) == "1,234,567", "score grouping")
	_ok(UIProgress.format_time(92.0) == "1:32", "time formatting")

	# Second run, this time a loss. Same card, different character — and the stat
	# rows must be rebuilt, not appended to.
	var victory_rows: int = over._rows.get_child_count()
	var hero_art: Texture2D = over._art.texture
	over._hide_now()
	GameManager.start_game()
	GameManager.score = 40
	GameManager.fight_time = 31.0
	GameManager._end_game(false)
	await _wait_until(func() -> bool: return over.visible and over._interactive, 12000)
	_ok(over._title.text == "DEFEAT", "defeat verdict")
	_ok(over._art.texture != hero_art, "defeat swaps in the Adamastor portrait")
	_ok(over._rows.get_child_count() <= victory_rows,
		"stat rows rebuilt, not appended (%d)" % over._rows.get_child_count())
	_ok(not over._badge.visible, "no personal-best badge on a worse run")
	var lose_card := Rect2(over._card.position, over._card.size)
	_ok(Rect2(Vector2.ZERO, VIEW).encloses(lose_card), "defeat card fits the frame %s" % str(lose_card))

	over.queue_free()
	await get_tree().process_frame


# --- Helpers ------------------------------------------------------------------

## Headless runs uncapped, so frame counts are meaningless as a clock. Everything
## that waits on an eased animation waits on wall time or a predicate instead.
func _wait_ms(ms: int) -> void:
	var until := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


func _wait_until(cond: Callable, timeout_ms: int) -> void:
	var until := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < until:
		if cond.call():
			return
		await get_tree().process_frame
