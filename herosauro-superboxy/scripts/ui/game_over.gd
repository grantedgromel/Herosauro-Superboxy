extends Control
## Victory / Defeat card.
##
## Two-column: the character who decided the fight on the left (the heroes on a
## win, the giant on a loss) and the verdict, the run's numbers and the two
## things you can do next on the right. Using the concept art here is the whole
## point — a results screen with a face on it is authored, one with a font on it
## is a debug print.
##
## IN CO-OP BOTH HEROES TAKE THE WIN. The partner is staged behind and to the
## side of the lead figure rather than being left out, because a two-player run
## that ends on a portrait of player one is the same slight the old single-hero
## HUD was making, moved to the last screen of the game.
##
## It does not appear, it ARRIVES: the scrim fades, the card drops in past its
## resting size and springs back, then the verdict punches. Roughly half a
## second, and it turns "the game stopped" into "the game is telling you
## something".

const CARD_W := 780.0
## Declared height. The PanelContainer grows past this if its content demands it,
## so the reveal takes its pivot from the measured size, not from this constant.
const CARD_H := 462.0
const ART_H := 310.0
const REVEAL := 0.46

var _dim: ColorRect
## Full-rect wrapper the card is centred inside. The rise animation moves THIS,
## because `position` on an anchor-centred control is measured from the parent's
## top-left, not from the anchor — tweening the card itself would fling it to the
## top of the screen.
var _stage: Control
var _card: PanelContainer
var _glow: TextureRect
var _art: TextureRect
## The co-op partner, staged behind and outboard of the lead figure. Hidden in a
## solo run and on a defeat, where the giant stands alone.
var _art2: TextureRect
var _title: Label
var _subtitle: Label
var _rows: VBoxContainer
var _badge: PanelContainer
var _again_btn: Button
var _menu_btn: Button
## Input is ignored until the reveal finishes, so a mashed attack button on the
## killing blow cannot skip straight past the results.
var _interactive: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP

	_dim = ColorRect.new()
	_dim.color = UIStyle.OVERLAY
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)

	_stage = Control.new()
	_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)

	_card = UIStyle.card(UIStyle.Elev.MODAL, UIStyle.RADIUS_LG, UIStyle.SPACE_XL)
	_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_card.offset_left = -CARD_W * 0.5
	_card.offset_right = CARD_W * 0.5
	_card.offset_top = -CARD_H * 0.5
	_card.offset_bottom = CARD_H * 0.5
	_stage.add_child(_card)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", UIStyle.SPACE_XL)
	_card.add_child(columns)

	columns.add_child(_build_art_column())
	columns.add_child(_build_body_column())

	GameManager.game_over.connect(_on_game_over)
	GameManager.game_started.connect(_hide_now)


func _build_art_column() -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(252, ART_H)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	# Soft coloured bloom behind the figures so the line art lifts off the panel.
	_glow = TextureRect.new()
	_glow.stretch_mode = TextureRect.STRETCH_SCALE
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_glow)
	_glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glow.offset_left = -40.0
	_glow.offset_right = 40.0
	_glow.offset_top = -20.0
	_glow.offset_bottom = 20.0

	# Partner first, so the lead figure draws over it. Smaller, pushed left and
	# down, and knocked back a touch — a staged group shot, not two cut-outs.
	_art2 = _figure(holder)
	_art2.offset_left = -58.0
	_art2.offset_right = -58.0
	_art2.offset_top = 34.0
	_art2.modulate = Color(0.86, 0.88, 0.92, 1.0)
	_art2.visible = false

	_art = _figure(holder)
	return holder


func _figure(holder: Control) -> TextureRect:
	var tr := TextureRect.new()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(tr)
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return tr


func _build_body_column() -> Control:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", UIStyle.SPACE_SM)

	_title = UIStyle.title("", UIStyle.Scale.TITLE, UIStyle.VICTORY)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(_title)

	_subtitle = UIStyle.text("", UIStyle.Scale.BODY, UIStyle.TEXT_SECONDARY, HORIZONTAL_ALIGNMENT_LEFT)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.custom_minimum_size = Vector2(0, 42)
	col.add_child(_subtitle)

	col.add_child(UIStyle.divider(2, 0.12))

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", UIStyle.SPACE_XS)
	col.add_child(_rows)

	# A solid gold chip, not a gold sentence. A personal best is the one piece of
	# good news on this card and it should look like a sticker stuck to it.
	_badge = UIStyle.pill("NEW PERSONAL BEST", UIStyle.GOLD, UIStyle.BASE, UIStyle.Scale.LABEL)
	_badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_badge.visible = false
	col.add_child(_badge)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, UIStyle.SPACE_MD)
	col.add_child(gap)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", UIStyle.SPACE_MD)
	col.add_child(actions)

	_again_btn = UIStyle.button("PLAY AGAIN", true, Vector2(230, 56))
	_again_btn.pressed.connect(_on_play_again)
	actions.add_child(_again_btn)

	_menu_btn = UIStyle.button("MAIN MENU", false, Vector2(190, 56))
	_menu_btn.pressed.connect(_on_main_menu)
	actions.add_child(_menu_btn)
	return col


# --- Presentation -------------------------------------------------------------

func _on_game_over(victory: bool) -> void:
	# Let the death animation land before the UI takes the screen.
	await get_tree().create_timer(2.0 if victory else 1.0).timeout
	if GameManager.state != GameManager.State.VICTORY and GameManager.state != GameManager.State.DEFEAT:
		return

	var accent := UIStyle.VICTORY if victory else UIStyle.DEFEAT
	var actor: int = UIStyle.Actor.HEROSAURO if victory else UIStyle.Actor.ADAMASTOR
	var co_op := GameManager.player_count >= 2

	_title.text = "VICTORY!" if victory else "DEFEAT"
	_title.add_theme_color_override("font_color", accent)
	if victory:
		_subtitle.text = "Porto stands. The giant of the Douro is stone again."
	else:
		_subtitle.text = "Adamastor still holds the bridge. The city waits."

	_art.texture = UIStyle.portrait_scaled(actor, int(ART_H * 1.6))
	# Both heroes take a co-op win. A defeat is the giant's moment and he takes
	# the frame alone — putting the losers next to him would undercut it.
	_art2.visible = victory and co_op
	if _art2.visible:
		_art2.texture = UIStyle.portrait_scaled(UIStyle.Actor.SUPERBOXY, int(ART_H * 1.34))
	_glow.texture = _bloom(accent)

	var beat := UIProgress.submit(GameManager.score, GameManager.fight_time, victory)
	_fill_rows(victory, accent, beat)
	_badge.visible = beat

	# The win/lose music is started by AudioManager off GameManager.game_over.
	# The old synth fanfare played on top of that real track, so it is gone.

	_reveal()


func _fill_rows(victory: bool, accent: Color, beat: bool) -> void:
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	_rows.add_child(UIStyle.stat_row("Score", UIProgress.format_score(GameManager.score),
		accent if beat else UIStyle.GOLD))
	_rows.add_child(UIStyle.stat_row("Time", UIProgress.format_time(GameManager.fight_time),
		UIStyle.TEXT_PRIMARY))
	var best := UIProgress.best_score()
	_rows.add_child(UIStyle.stat_row("Best score", UIProgress.format_score(best),
		UIStyle.TEXT_SECONDARY))
	if victory:
		var bt := UIProgress.best_time()
		if bt >= 0.0:
			_rows.add_child(UIStyle.stat_row("Fastest win", UIProgress.format_time(bt),
				UIStyle.TEXT_SECONDARY))


## Radial bloom, opaque-ish in the middle and gone at the edges — the inverse of
## the screen vignette, used as a backlight for the character art.
func _bloom(tint: Color) -> GradientTexture2D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	grad.colors = PackedColorArray([
		Color(tint.r, tint.g, tint.b, 0.30),
		Color(tint.r, tint.g, tint.b, 0.11),
		Color(tint.r, tint.g, tint.b, 0.0),
	])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 192
	gt.height = 192
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.52)
	gt.fill_to = Vector2(1.0, 0.52)
	return gt


## The card SLAMS in. It starts oversized and above its resting place and drops
## onto it with a back overshoot, which is a different move from the old gentle
## rise: a verdict that eases in politely reads as a dialog box, and this one is
## supposed to read as the game landing a full stop.
func _reveal() -> void:
	visible = true
	_interactive = false
	_dim.modulate.a = 0.0
	_stage.modulate.a = 0.0
	_stage.position.y = -46.0
	_card.pivot_offset = _card.size * 0.5
	_card.scale = Vector2(1.10, 1.10)
	_title.scale = Vector2(0.55, 0.55)
	_title.pivot_offset = Vector2(0.0, _title.size.y * 0.5)

	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(_dim, "modulate:a", 1.0, REVEAL * 0.55)
	t.tween_property(_stage, "modulate:a", 1.0, REVEAL * 0.5)
	t.tween_property(_stage, "position:y", 0.0, REVEAL) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_card, "scale", Vector2.ONE, REVEAL) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# The verdict lands a beat AFTER the card, so the two reads are sequential
	# rather than fighting each other for the same quarter second.
	t.chain().tween_property(_title, "scale", Vector2(1.08, 1.08), 0.16) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.chain().tween_property(_title, "scale", Vector2.ONE, 0.26) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.chain().tween_callback(func() -> void:
		_interactive = true
		_again_btn.grab_focus())


func _hide_now() -> void:
	visible = false
	_interactive = false


# --- Input --------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not visible or not _interactive:
		return
	if event.is_action_pressed("ui_confirm"):
		_on_play_again()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		_on_main_menu()
		get_viewport().set_input_as_handled()


func _on_play_again() -> void:
	_hide_now()
	GameManager.start_game()


func _on_main_menu() -> void:
	_hide_now()
	GameManager.go_to_menu()
