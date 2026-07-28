extends Control
## The title screen.
##
## Not a flat gradient with a button on it any more: the real Douro gorge is
## rendered live behind it by a scripted cinematic camera, the three character
## sheets are staged as foreground art over the top, and the UI is a graded
## column down the left margin.
##
## LAYER ORDER, back to front. Only the first of these is 3D, and it renders
## under every CanvasItem in the tree by definition, so nothing here has to fight
## for draw order:
##
##   MenuWorld    bridge_arena.tscn plus a camera on a 74-second loop
##   Atmosphere   scrims, horizon glare, vignette, drifting motes
##   HeroStage    Adamastor, Super Boxy, Herosauro, parallaxed against the camera
##   TitleLogo    the display lockup
##   MenuList     START / DIFFICULTY / CONTROLS / CREDITS / QUIT
##   Hints        the key legend
##   Modal        CONTROLS and CREDITS panels
##   Curtain      the fade this screen enters and leaves through
##
## COMPOSITION. Everything readable hangs off the left margin and everything
## drawn owns the right. That is not a style choice so much as a consequence of
## the art: Adamastor has to be cropped by the frame to read as a giant, the
## heroes have to stand in front of him, and the camera's best shot of Porto is
## down the gorge into the sun — all of which wants the right two thirds. A
## centred logo and a centred button stack would have sat straight on top of it.
##
## LIFETIME. The 3D backdrop only exists while this screen is the one on show.
## `_wake()` builds it a frame after the state settles (main.gd tears the
## gameplay world down with `queue_free()`, which does not flush until the end of
## its frame, and two live WorldEnvironments in one viewport is one too many);
## `_sleep()` and `_leave()` detach it synchronously. See menu_world.gd.

const MenuWorldScript := preload("res://scripts/ui/menu/menu_world.gd")
const AtmosphereScript := preload("res://scripts/ui/menu/menu_atmosphere.gd")
const HeroStageScript := preload("res://scripts/ui/menu/hero_stage.gd")
const TitleLogoScript := preload("res://scripts/ui/menu/title_logo.gd")
const MenuListScript := preload("res://scripts/ui/menu/menu_list.gd")
const MenuModalScript := preload("res://scripts/ui/menu/menu_modal.gd")

# --- Layout ------------------------------------------------------------------
#
# The project stretches `canvas_items` with `expand`, so the logical viewport is
# never smaller than 1280x720 in either axis — one axis is exactly the base size
# and the other grows. `_ui_scale()` is therefore 1.0 in practice; it is computed
# anyway so that changing the stretch settings degrades instead of breaking.

const DESIGN := Vector2(1280.0, 720.0)
const MARGIN_FRACTION := 0.06
const MARGIN_MIN := 60.0
const MARGIN_MAX := 168.0
const LOGO_TOP := 0.065          # fraction of the frame height
const LOGO_WIDTH_MAX := 620.0
const LOGO_WIDTH_FRACTION := 0.46
const COLUMN_WIDTH_MAX := 430.0
const COLUMN_WIDTH_FRACTION := 0.34
const LOGO_TO_LIST := 44.0
const HINTS_BASELINE := 58.0     # up from the bottom edge
const LIST_BOTTOM_CLEAR := 92.0

# --- Timing ------------------------------------------------------------------

const CURTAIN_IN := 0.95         # fade up from black once the world is standing
const CURTAIN_OUT := 0.28        # fade to black on START / QUIT
const LOGO_DELAY := 0.06
const STAGE_DELAY := 0.14
const STAGE_STAGGER := 0.13
const LIST_DELAY := 0.44
const LIST_STAGGER := 0.07

var _world: MenuWorldScript
var _atmosphere: AtmosphereScript
var _stage: HeroStageScript
var _logo: TitleLogoScript
var _list: MenuListScript
var _modal: MenuModalScript
var _hints: Control
var _curtain: ColorRect

var _awake: bool = false
var _leaving: bool = false
var _return_focus: StringName = &"start"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(false)
	_build()

	GameManager.state_changed.connect(_on_state_changed)
	visibility_changed.connect(_on_visibility_changed)
	resized.connect(_relayout)

	_relayout()
	if visible and GameManager.state == GameManager.State.MENU:
		_wake()


# --- Construction ------------------------------------------------------------

func _build() -> void:
	_atmosphere = AtmosphereScript.new()
	_atmosphere.name = "Atmosphere"
	add_child(_atmosphere)

	_stage = HeroStageScript.new()
	_stage.name = "HeroStage"
	add_child(_stage)

	_logo = TitleLogoScript.new()
	_logo.name = "TitleLogo"
	add_child(_logo)

	_list = MenuListScript.new()
	_list.name = "MenuList"
	_list.activated.connect(_on_activated)
	_list.difficulty_changed.connect(_on_difficulty_changed)
	add_child(_list)

	_hints = UIStyle.hint_row([
		["W", "Up"], ["S", "Down"], ["Enter", "Select"], ["Esc", "Back"],
	], UIStyle.SPACE_LG)
	_hints.name = "Hints"
	(_hints as HBoxContainer).alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(_hints)

	_modal = MenuModalScript.new()
	_modal.name = "Modal"
	_modal.closed.connect(_on_modal_closed)
	add_child(_modal)

	# Opaque from frame one. It hides the boot hitch while bridge_arena builds
	# its terrain, facades and landmarks, and it is what START fades out through.
	_curtain = ColorRect.new()
	_curtain.name = "Curtain"
	_curtain.color = UIStyle.BASE
	_curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_curtain)


# --- Layout ------------------------------------------------------------------

func _ui_scale() -> float:
	return clampf(minf(size.x / DESIGN.x, size.y / DESIGN.y), 0.78, 1.5)


func _relayout() -> void:
	if size.x <= 1.0 or size.y <= 1.0:
		return
	var ui := _ui_scale()
	var margin := clampf(size.x * MARGIN_FRACTION, MARGIN_MIN * ui, MARGIN_MAX * ui)

	var logo_w := minf(size.x * LOGO_WIDTH_FRACTION, LOGO_WIDTH_MAX * ui)
	_logo.position = Vector2(margin, size.y * LOGO_TOP)
	var logo_h := _logo.relayout(logo_w, ui)

	var column_w := minf(size.x * COLUMN_WIDTH_FRACTION, COLUMN_WIDTH_MAX * ui)
	_list.size = Vector2(column_w, 10.0)
	_list.relayout(ui)
	var column_h := _list.column_height()
	# Sits under the lockup, but never so far down that it crowds the hint row.
	var list_y := minf(_logo.position.y + logo_h + LOGO_TO_LIST * ui,
			size.y - LIST_BOTTOM_CLEAR * ui - column_h)
	_list.position = Vector2(margin, maxf(list_y, _logo.position.y + logo_h + 8.0 * ui))
	_list.size = Vector2(column_w, column_h)

	_hints.position = Vector2(margin, size.y - HINTS_BASELINE * ui)
	_hints.size = Vector2(maxf(size.x - margin * 2.0, 100.0), 30.0 * ui)


# --- Waking and sleeping -----------------------------------------------------

func _on_state_changed(new_state: int) -> void:
	if new_state == GameManager.State.MENU:
		_wake()
	else:
		_sleep()


func _on_visibility_changed() -> void:
	if visible and GameManager.state == GameManager.State.MENU:
		_wake()
	elif not visible:
		_sleep()


func _wake() -> void:
	if _awake:
		return
	_awake = true
	_leaving = false
	_curtain.color = Color(UIStyle.BASE.r, UIStyle.BASE.g, UIStyle.BASE.b, 1.0)
	_list.set_locked(false)
	_list.sync_difficulty(GameManager.difficulty)
	set_process(true)
	_spawn_world()


func _sleep() -> void:
	if not _awake:
		return
	_awake = false
	set_process(false)
	if _modal.is_open():
		_modal.close()
	_list.set_locked(true)
	_release_world()


## Deferred by two frames on purpose — see the lifetime note at the top of the
## file and in menu_world.gd. Re-checked after the wait because the player can
## be out of the menu again by then (PLAY AGAIN goes VICTORY -> PLAYING without
## ever passing through here, but a fast Esc-and-start can).
func _spawn_world() -> void:
	if _world != null and is_instance_valid(_world):
		return
	await get_tree().process_frame
	await get_tree().process_frame
	if not _awake or GameManager.state != GameManager.State.MENU:
		return
	_world = MenuWorldScript.new()
	_world.name = "MenuWorld"
	add_child(_world)
	_play_entry()


func _release_world() -> void:
	if _world != null and is_instance_valid(_world):
		_world.dismiss()
	_world = null


func _process(_delta: float) -> void:
	if _world != null and is_instance_valid(_world):
		_stage.camera_sway = _world.sway()


# --- Entry -------------------------------------------------------------------

func _play_entry() -> void:
	_relayout()
	_logo.play_entry(LOGO_DELAY)
	_stage.play_entry(STAGE_DELAY, STAGE_STAGGER)
	_list.play_entry(LIST_DELAY, LIST_STAGGER)
	_list.focus_row(_return_focus)
	var tw := create_tween()
	tw.tween_property(_curtain, "color:a", 0.0, CURTAIN_IN).set_trans(Tween.TRANS_SINE)


# --- Actions -----------------------------------------------------------------

func _on_activated(id: StringName) -> void:
	match id:
		&"start":
			_leave(func() -> void: GameManager.start_game())
		&"controls":
			_show_modal("CONTROLS", MenuModalScript.build_controls())
		&"credits":
			_show_modal("CREDITS", MenuModalScript.build_credits())
		&"quit":
			_leave(func() -> void: get_tree().quit())


func _on_difficulty_changed(index: int) -> void:
	GameManager.set_difficulty(index)


func _show_modal(heading: String, body: Control) -> void:
	_return_focus = _list.focused_id()
	if _return_focus == &"":
		_return_focus = &"start"
	_list.set_locked(true)
	_modal.open(heading, body)


func _on_modal_closed() -> void:
	if not _awake:
		return
	_list.set_locked(false)
	_list.focus_row(_return_focus)


## Fade to black, drop the backdrop, then do the thing. The world is released
## only once the screen is fully covered, so the hand-off to main.gd's own world
## (or to the desktop, on QUIT) never shows a bare clear colour.
func _leave(action: Callable) -> void:
	if _leaving:
		return
	_leaving = true
	_list.set_locked(true)
	_return_focus = &"start"
	var tw := create_tween()
	tw.tween_property(_curtain, "color:a", 1.0, CURTAIN_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void:
		_release_world()
		_leaving = false
		action.call())
