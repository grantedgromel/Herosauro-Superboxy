extends Control
## The title screen.
##
## Not a flat gradient with a button on it any more: the real Douro gorge is
## rendered live behind it by a scripted cinematic camera, the three character
## sheets are staged as foreground art over the top, and the UI is a graded
## column down the left margin.
##
## LAYER ORDER, back to front. Every layer is a CanvasItem — there is no 3D on
## this screen any more:
##
##   Backdrop     a flat graded field
##   HeroStage    Adamastor, Super Boxy, Herosauro, on a slow drift
##   TitleLogo    the display lockup
##   MenuList     START / DIFFICULTY / CONTROLS / CREDITS / QUIT
##   Hints        the key legend, bottom left
##   Build        the version string, bottom left under the hints
##   Modal        CONTROLS and CREDITS panels
##   Curtain      the fade to black on START and QUIT
##
## THE BACKDROP IS FLAT ON PURPOSE. It used to be bridge_arena.tscn rendered
## live, with a cinematic camera on a 74-second loop — the real gorge, at golden
## hour, behind the menu. It looked good in isolation and cost more than it
## returned:
##
##   * The menu column sat on the brightest region of the frame. Sunlit water is
##     the highest-luminance thing in that scene and START/CONTROLS/CREDITS
##     landed straight on it, surviving on outline alone.
##   * Building the arena blocked the main thread for a second and a half, so the
##     screen needed a held title card, a veil, and a two-frame-deferred spawn to
##     hide the stall. That machinery existed only to cover a cost this screen
##     did not need to pay.
##   * It welded the menu's look to the game's time of day. Re-theming the title
##     screen meant re-lighting the fight.
##
## A flat field fixes all three at once and hands the screen to the art, which is
## the point: the cast is the game's identity and it now has the contrast to read
## as such. Gameplay keeps golden hour; the two are no longer coupled.
##
## COMPOSITION. Everything readable hangs off the left margin and everything
## drawn owns the right. Adamastor is cropped by the frame because a giant that
## fits on screen is not a giant, and the heroes stand in front of him. A centred
## logo and a centred button stack would have sat straight on top of that.

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
## Down from 620 / 0.46. At 720p the old lockup took 269 px of height, which left
## the five-row column 268 px to fit 260 px of rows into — so the gap collapsed
## to its floor and QUIT still landed under the key legend. A smaller mark also
## matches the reference: Absolum's logo is about a third of the frame, not half.
const LOGO_WIDTH_MAX := 520.0
const LOGO_WIDTH_FRACTION := 0.36
const COLUMN_WIDTH_MAX := 430.0
const COLUMN_WIDTH_FRACTION := 0.34
const LOGO_TO_LIST := 44.0
const HINTS_BASELINE := 58.0     # up from the bottom edge
const BUILD_BASELINE := 26.0     # the version stamp, below the hints
const LIST_BOTTOM_CLEAR := 92.0

# --- Backdrop ----------------------------------------------------------------
#
# Two stops, corner to corner. A single flat colour across 1280x720 reads as an
# empty buffer rather than as a designed field, and the diagonal puts the lighter
# end behind the cast on the right where it separates them from the ground.
#
# Both stops are UIStyle.BASE — the palette's darkest ink, and the one colour in
# it that was never tied to the sunset. When the new theme lands these are the
# two values to change and nothing else on this screen needs to move.

const BACKDROP_NEAR := Color("14101f")   # behind the menu column, left
const BACKDROP_FAR := Color("241a30")    # behind the cast, right

# --- Timing ------------------------------------------------------------------

const CURTAIN_OUT := 0.28        # fade to black on START / QUIT
const LOGO_DELAY := 0.0
const STAGE_DELAY := 0.10
const STAGE_STAGGER := 0.13
const LIST_DELAY := 0.34
const LIST_STAGGER := 0.07
## Radians per second of the autonomous drift that replaced the live camera's
## azimuth. Slow enough to be felt rather than watched — a static cast reads as a
## screenshot, and this is the cheapest thing that stops it.
const DRIFT_RATE := 0.11
const DRIFT_AMPLITUDE := 0.55

var _backdrop: TextureRect
var _stage: HeroStageScript
var _logo: TitleLogoScript
var _list: MenuListScript
var _modal: MenuModalScript
var _hints: Control
var _build_label: Label
var _curtain: ColorRect

var _awake: bool = false
var _leaving: bool = false
var _drift: float = 0.0
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
	_backdrop = _make_backdrop()
	add_child(_backdrop)

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
	_hints.modulate.a = 0.0
	add_child(_hints)

	# Bottom-left build stamp. Small, dim, and deliberately not centred on
	# anything: it is for bug reports, not for the player.
	_build_label = UIStyle.text(_build_stamp(), UIStyle.Scale.MICRO,
			Color(UIStyle.TEXT_DISABLED, 0.55), HORIZONTAL_ALIGNMENT_LEFT)
	_build_label.name = "Build"
	_build_label.modulate.a = 0.0
	add_child(_build_label)

	_modal = MenuModalScript.new()
	_modal.name = "Modal"
	_modal.closed.connect(_on_modal_closed)
	add_child(_modal)

	_curtain = _sheet("Curtain", 0.0)
	add_child(_curtain)


func _sheet(sheet_name: String, alpha: float) -> ColorRect:
	var r := ColorRect.new()
	r.name = sheet_name
	r.color = Color(UIStyle.BASE.r, UIStyle.BASE.g, UIStyle.BASE.b, alpha)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return r


## The flat field. A GradientTexture2D rather than two stacked ColorRects so the
## ramp is resampled by the GPU at whatever size the window is, with no banding
## at 8 bits and nothing to re-lay-out on resize.
func _make_backdrop() -> TextureRect:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	grad.colors = PackedColorArray([BACKDROP_NEAR, BACKDROP_FAR])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 256
	gt.height = 256
	gt.fill_from = Vector2(0.12, 0.0)
	gt.fill_to = Vector2(1.0, 1.0)
	var tr := TextureRect.new()
	tr.name = "Backdrop"
	tr.texture = gt
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return tr


## `v02 / r34450`-style stamp. Reads the project version so it cannot drift from
## what actually shipped.
func _build_stamp() -> String:
	var v := String(ProjectSettings.get_setting("application/config/version", ""))
	return v if v != "" else "dev build"


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
	# The column starts under the lockup and has to finish above the hint row, so
	# that span — not the column's own preference — is what it gets to spend. It
	# compresses its gap to fit rather than overflowing into the legend.
	var list_top := _logo.position.y + logo_h + LOGO_TO_LIST * ui
	var floor_y := size.y - LIST_BOTTOM_CLEAR * ui
	# Last-resort guard. The column compresses its own gap to fit `available`, but
	# it cannot compress below MIN_ROW_GAP, so a tall enough lockup could still
	# push it past the legend. If that happens, the column wins and slides up
	# under the logo: overlapping the art is survivable, overlapping the key
	# legend is not. Sizing the logo so this never fires is the real fix — it just
	# must not be the only thing standing between us and a broken screen.
	var available := floor_y - list_top
	_list.relayout(ui, available)
	var column_h := _list.column_height()
	_list.position = Vector2(margin, minf(list_top, floor_y - column_h))
	_list.size = Vector2(column_w, column_h)

	# Sized to its own content, not to the remaining width: a hint row stretched
	# across the frame is an invisible box lying over the character art, and the
	# first thing that goes wrong with one of those is hit-testing.
	var hint_w := maxf(_hints.get_combined_minimum_size().x, 120.0)
	_hints.position = Vector2(margin, size.y - HINTS_BASELINE * ui)
	_hints.size = Vector2(hint_w, 30.0 * ui)

	var stamp := _build_label.get_combined_minimum_size()
	_build_label.position = Vector2(margin, size.y - BUILD_BASELINE * ui)
	_build_label.size = Vector2(maxf(stamp.x, 80.0), stamp.y)


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


## Nothing blocks any more, so this is the whole entry: everything is already
## built, the layout is already valid, and the screen can simply play in. The
## deferred spawn, the held title card and the veil all existed to cover the
## arena build and went with it.
func _wake() -> void:
	if _awake:
		return
	_awake = true
	_leaving = false
	_curtain.color.a = 0.0
	_hints.modulate.a = 0.0
	_build_label.modulate.a = 0.0
	_stage.modulate.a = 1.0
	_list.modulate.a = 1.0
	_list.sync_difficulty(GameManager.difficulty)
	set_process(true)
	_relayout()
	_logo.play_entry(LOGO_DELAY)
	_reveal()


func _sleep() -> void:
	if not _awake:
		return
	_awake = false
	set_process(false)
	if _modal.is_open():
		_modal.close()
	_list.set_locked(true)


## The parallax shear used to be driven by the live camera's azimuth. With no
## camera, it is driven by a slow sine instead — same input range, same code path
## downstream in hero_stage.gd, and the cast keeps drifting against itself.
func _process(delta: float) -> void:
	_drift += delta * DRIFT_RATE
	_stage.camera_sway = sin(_drift) * DRIFT_AMPLITUDE


# --- Reveal ------------------------------------------------------------------

func _reveal() -> void:
	_stage.play_entry(STAGE_DELAY, STAGE_STAGGER)
	_list.play_entry(LIST_DELAY, LIST_STAGGER)
	_list.set_locked(false)
	_list.focus_row(_return_focus)

	var tw := create_tween().set_parallel(true)
	tw.tween_property(_hints, "modulate:a", 1.0, 0.5).set_delay(LIST_DELAY + 0.25)
	tw.tween_property(_build_label, "modulate:a", 1.0, 0.5).set_delay(LIST_DELAY + 0.35)


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


## Fade to black, then do the thing. The action fires only once the screen is
## fully covered, so the hand-off to main.gd's world (or to the desktop, on QUIT)
## never shows a bare clear colour.
func _leave(action: Callable) -> void:
	if _leaving:
		return
	_leaving = true
	_list.set_locked(true)
	_return_focus = &"start"
	var tw := create_tween()
	tw.tween_property(_curtain, "color:a", 1.0, CURTAIN_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void:
		_leaving = false
		action.call())
