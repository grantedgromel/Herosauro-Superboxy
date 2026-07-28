extends Node
## Correctness probe for the UI stream. Not shipped.
##
## The plain headless boot only reaches the MENU state, so it exercises none of
## the paths that actually matter: damage, the lag bar, phase two, combos, the
## results card. This drives GameManager through a whole fight against a live
## HUD + GameOver and asserts the widgets ended up where the design says they
## should, then checks the type scale, the contrast budget and the portrait
## pipeline directly.
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


func _check_surfaces() -> void:
	var flat := UIStyle.surface(UIStyle.Elev.FLAT)
	var modal := UIStyle.surface(UIStyle.Elev.MODAL)
	_ok(modal.shadow_size > flat.shadow_size, "elevation increases shadow")
	_ok(modal.bg_color.v >= flat.bg_color.v, "elevation does not darken the fill")
	_ok(flat.bg_color.a > 0.0, "surfaces are opaque enough to carry text")
	# Warm identity: a neutral grey hairline is the fastest way to make a warm
	# scene look like a generic dark UI kit.
	_ok(UIStyle.HAIRLINE.r > UIStyle.HAIRLINE.b, "hairline is warm, not neutral")
	_ok(UIStyle.TEXT_PRIMARY.r > UIStyle.TEXT_PRIMARY.b, "primary text is warm cream")

	var ratio := _contrast(UIStyle.TEXT_PRIMARY, UIStyle.SURFACE)
	_ok(ratio >= 7.0, "text/surface contrast %.1f:1 (AAA)" % ratio)
	var sec := _contrast(UIStyle.TEXT_SECONDARY, UIStyle.SURFACE)
	_ok(sec >= 4.5, "secondary/surface contrast %.1f:1 (AA)" % sec)
	var gold := _contrast(UIStyle.BASE, UIStyle.GOLD)
	_ok(gold >= 4.5, "ink-on-gold button contrast %.1f:1 (AA)" % gold)


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
	# The lag bar has to stay ABOVE the real fill through the hold window; that
	# separation is the entire point of it.
	await _wait_ms(90)
	_ok(bar._ghost > bar._shown + 0.05,
		"lag bar trails the fill after a hit (%.2f > %.2f)" % [bar._ghost, bar._shown])

	# ...and it must eventually catch up rather than hanging forever.
	await _wait_until(func() -> bool: return not bar.is_processing(), 6000)
	_near(bar._ghost, bar._shown, 0.02, "lag bar converges")
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

	_check_bounds(hud)

	# A real exchange of blows.
	GameManager.damage_boss(8, 1)
	GameManager.damage_boss(8, 1)
	GameManager.damage_boss(18, 1)
	await get_tree().process_frame
	_ok(GameManager.p2_combo == 3, "combo counted three chained hits")
	_ok(hud._combo_count.visible and hud._combo_count.text == "3", "combo readout shows 3")
	_ok(hud._combo_count.text.is_valid_int(), "combo text is digits only (Bangers-safe)")
	_ok(hud._pops.get_child_count() >= 1,
		"damage numbers spawned (%d)" % hud._pops.get_child_count())

	GameManager.damage_player(1, 22)
	await get_tree().process_frame
	_ok(hud._hero_hp.text == "78 / 100", "hero readout tracks health, got '%s'" % hud._hero_hp.text)
	_near(hud._hero_bar.value, 78.0, 0.01, "hero bar took the hit")
	_ok(hud._fx._sustain_level == 0.0, "no danger glow while comfortably alive")

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

	# Combo window expires on its own.
	await _wait_until(func() -> bool: return not hud._combo_count.visible,
		int(GameManager.COMBO_TIMEOUT * 1000.0) + 3000)
	_ok(not hud._combo_count.visible, "combo readout clears when the window lapses")

	# Low health drives the sustained edge glow, and only then.
	GameManager.damage_player(1, 60)
	await get_tree().process_frame
	_ok(hud._fx._sustain_level > 0.0, "danger vignette engages below the threshold")

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
	_near(hud._hero_bar.value, 100.0, 0.01, "restart resets hero bar")
	_near(hud._boss_bar.value, float(GameManager.MAX_BOSS_HEALTH), 0.01, "restart resets boss bar")
	_ok(hud._phase_label.text == "PHASE 1", "restart resets the phase label")
	_ok(hud._fx._sustain_level == 0.0, "restart clears the danger vignette")
	_ok(hud._pops.get_child_count() == 0, "restart clears floating numbers")

	hud.queue_free()
	await get_tree().process_frame


## Everything visible must be inside the frame, and the three clusters must not
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

	var hero: Rect2 = Rect2(hud._hero_face.position, hud._hero_face.size) \
		.merge(Rect2(hud._hero_bar.position, hud._hero_bar.size)) \
		.merge(Rect2(hud._dial.position, hud._dial.size)) \
		.merge(Rect2(hud._dial_caption.position, hud._dial_caption.size))
	var boss: Rect2 = Rect2(hud._boss_bar.position, hud._boss_bar.size) \
		.merge(Rect2(hud._boss_name.position, hud._boss_name.size)) \
		.merge(Rect2(hud._boss_face.position, hud._boss_face.size))
	var read: Rect2 = Rect2(hud._score_value.position, hud._score_value.size) \
		.merge(Rect2(hud._timer_value.position, hud._timer_value.size))
	_ok(not hero.intersects(boss), "hero cluster clears the boss banner")
	_ok(not read.intersects(boss), "score readout clears the boss banner %s / %s" % [read, boss])
	_ok(not read.intersects(hero), "score readout clears the hero cluster")
	_ok(hero.position.x >= UIStyle.SCREEN_MARGIN - 1.0, "hero cluster respects the left gutter")
	_ok(hero.end.y <= VIEW.y - UIStyle.SCREEN_MARGIN + 1.0,
		"hero cluster respects the bottom gutter (%.0f)" % hero.end.y)
	_ok(read.end.x <= VIEW.x - UIStyle.SCREEN_MARGIN + 1.0, "readouts respect the right gutter")
	# The epithet and the boss HP readout share a line; their boxes must not run
	# into each other or one will draw over the other on a long name.
	var ep := Rect2(hud._boss_epithet.position, hud._boss_epithet.size)
	var hp := Rect2(hud._boss_hp.position, hud._boss_hp.size)
	var ph := Rect2(hud._phase_label.position, hud._phase_label.size)
	_ok(not ep.intersects(hp), "boss epithet clears the boss HP readout")
	_ok(not hp.intersects(ph), "boss HP readout clears the phase label")


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
