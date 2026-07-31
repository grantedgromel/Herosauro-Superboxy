extends Control
## The title screen. A poster: it is built in milliseconds and then it holds
## still.
##
## IT USED TO BE A LIVE 3D SHOT, AND THAT WAS THE PROBLEM. The screen instanced a
## second complete copy of `bridge_arena.tscn` — terrain, Ribeira facades,
## landmarks, ironwork, sky, lighting rig — purely as a backdrop, and flew a
## scripted camera around it on a seventy-four second loop. The probe puts that
## build at several seconds of blocking main-thread work and a few hundred nodes,
## paid before the player can read the game's name, and the whole load-hold
## sequence that used to live in this file existed only to hide it. The web build
## paid it worst. A title screen has no business being the most expensive screen
## in the game.
##
## So the backdrop is a static composed image now (see menu_backdrop.gd, which is
## also where the cinematic key art drops in when it lands), and everything that
## existed to serve a moving world went with it: the second WorldEnvironment, the
## camera path, the parallax feed into the cast, the horizon glare, the drifting
## motes, the deferred build, the veil and the held title card.
##
## LAYER ORDER, back to front. Every one of these is a CanvasItem — there is no
## 3D in this scene at all any more:
##
##   Backdrop     the key art, or a graded ground, plus scrims and vignette
##   HeroStage    Adamastor, Super Boxy, Herosauro as cut-outs. Hidden when the
##                key art is in, because the key art already has the cast in it
##   TitleLogo    the display lockup
##   MenuList     START / DIFFICULTY / CONTROLS / CREDITS / QUIT
##   Modal        CONTROLS and CREDITS panels
##   Curtain      the fade to black on START and QUIT
##
## COMPOSITION. Everything readable hangs off the left margin and everything
## drawn owns the right. That is not a style choice so much as a consequence of
## the art: Adamastor has to be cropped by the frame to read as a giant, the
## heroes have to stand in front of him, and the key art is composed down the
## gorge — all of which wants the right two thirds. A centred logo and a centred
## button stack would have sat straight on top of it.
##
## THE CURTAIN IS STILL LOAD COVER, JUST NOT FOR THIS SCREEN. Pressing START
## still hands off to main.gd, which builds the real arena and blocks while it
## does. The fade to black is what covers that; it is the one piece of the old
## sequencing worth keeping, and it now covers a build this screen does not pay
## for twice.

const BackdropScript := preload("res://scripts/ui/menu/menu_backdrop.gd")
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
const LOGO_TO_LIST := 40.0
## Air kept under the menu column. Trimmed once when the rows became plates: the
## column got taller and the clamp below was pushing it up into the strapline to
## keep this gap, which is the wrong thing to protect.
##
## This used to be measured against a W/S/Enter/Esc hint row pinned to the bottom
## left. That row went when the menu gained a dedicated CONTROLS screen — the same
## information, stated permanently, in the corner of the game's first impression.
## The air is worth more than the repetition.
const LIST_BOTTOM_CLEAR := 74.0

# --- Timing ------------------------------------------------------------------
#
# The entry is a settle, not a load screen. There is nothing to wait for any
# more, so the column is live from the first frame and the stagger below is only
# there so the poster assembles itself rather than snapping into place. Anyone
# who hits Enter before it finishes gets START, which is the correct answer.

const CURTAIN_OUT := 0.28        # fade to black on START / QUIT
const STAGE_DELAY := 0.06
const STAGE_STAGGER := 0.10
const LIST_DELAY := 0.16
const LIST_STAGGER := 0.06

var _backdrop: BackdropScript
var _stage: HeroStageScript
var _logo: TitleLogoScript
var _list: MenuListScript
var _modal: MenuModalScript
var _curtain: ColorRect

var _awake: bool = false
var _leaving: bool = false
var _return_focus: StringName = &"start"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Nothing on this screen runs per frame. The entry is a tween and the rest is
	# a still image, so the menu costs no `_process` at all while it is up.
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
	_backdrop = BackdropScript.new()
	_backdrop.name = "Backdrop"
	add_child(_backdrop)

	# The key art is a full cast shot. Staging the cut-outs over it would put a
	# second Adamastor next to the painted one, so the stage stands down entirely
	# and lets the art carry the right of the frame.
	#
	# Not built rather than built-and-hidden: three figures means three Lanczos
	# resamples of a 900 px character sheet, which is most of what this screen
	# costs to stand up. Paying it for something nobody sees is the kind of thing
	# that turns a fast screen slow again one small decision at a time.
	if not _backdrop.has_key_art():
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

	_modal = MenuModalScript.new()
	_modal.name = "Modal"
	_modal.closed.connect(_on_modal_closed)
	add_child(_modal)

	_curtain = ColorRect.new()
	_curtain.name = "Curtain"
	_curtain.color = Color(UIStyle.BASE.r, UIStyle.BASE.g, UIStyle.BASE.b, 0.0)
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
	# Sits under the lockup, but never so far down that it runs off the frame.
	var list_y := minf(_logo.position.y + logo_h + LOGO_TO_LIST * ui,
			size.y - LIST_BOTTOM_CLEAR * ui - column_h)
	_list.position = Vector2(margin, maxf(list_y, _logo.position.y + logo_h + 8.0 * ui))
	_list.size = Vector2(column_w, column_h)


# --- Waking and sleeping -----------------------------------------------------
#
# All that is left of the old lifetime dance. It used to defer the 3D build by
# two frames and then a further hold, because main.gd tears the gameplay world
# down with `queue_free()` — which does not flush until the end of its frame —
# and two live WorldEnvironments in one viewport is one too many. This screen
# owns no WorldEnvironment and no Camera3D now, so there is nothing to sequence
# against: waking is replaying the entry, sleeping is putting the modal away.

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
	_curtain.color.a = 0.0
	_list.set_locked(false)
	_list.sync_difficulty(GameManager.difficulty)
	# Re-run before the entry rather than after: coming back from a match the
	# window may have been resized while this screen was hidden, and `resized`
	# does not fire on a Control that was not laid out at the time.
	_relayout()
	_logo.play_entry(0.0)
	# Null whenever the key art is in — see `_build()`. Guarded rather than
	# replaced with a hidden stub so the "no cast to stage" case stays visible in
	# the code instead of hiding behind a node that does nothing.
	if _stage != null:
		_stage.play_entry(STAGE_DELAY, STAGE_STAGGER)
	_list.play_entry(LIST_DELAY, LIST_STAGGER)
	_list.focus_row(_return_focus)


func _sleep() -> void:
	if not _awake:
		return
	_awake = false
	if _modal.is_open():
		_modal.close()
	_list.set_locked(true)


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


## Fade to black, then do the thing. START hands off to main.gd, whose own arena
## build blocks for seconds; the curtain is what stands in front of that stall,
## and it is the reason the hand-off never shows a bare clear colour.
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
