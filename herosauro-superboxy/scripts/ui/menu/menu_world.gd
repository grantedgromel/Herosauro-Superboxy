extends Node3D
## MenuWorld — the real Douro gorge, live behind the title screen.
##
## WHY IT IS BUILT HERE AND NOT BY main.gd. The brief offered two routes: have
## main.gd build the gameplay world at MENU as well as PLAYING, or give the menu
## its own copy. This is the second, because it needs no change in a file this
## stream does not own, and because the two worlds want different things anyway —
## the menu wants a scripted camera and no hero, no giant, no props, no physics
## stepping a boss FSM behind a screen nobody is playing.
##
## What it instances is `bridge_arena.tscn` and nothing else: the bridge, the
## terrain, the Ribeira facades, the landmarks, the photogrammetry backdrop, the
## sky and the whole lighting rig, all of which that scene assembles itself. No
## characters, no prop spawner, no CameraRig.
##
## LIFETIME, which is the part that actually matters. Two copies of this world in
## one viewport means two WorldEnvironments and two current Camera3Ds fighting
## over the same frame, so the contract is strict:
##
##   * `dismiss()` detaches synchronously — `remove_child()` before `queue_free()`
##     — so the environment and the camera are gone the instant the caller says
##     so, not at the end of the frame. main_menu.gd calls it before it calls
##     GameManager.start_game(), so main.gd's own `_build_world()` never overlaps
##     with this one.
##   * coming back from a match, main_menu.gd waits a frame before building again,
##     because main.gd's teardown is a `queue_free()` and that does not flush
##     until the end of the frame it was requested in.
##
## The one cost this design accepts is that the arena is built twice per session
## — once for the menu, once for the match. See integration notes: main.gd can
## take this instance over instead, but nothing here depends on it doing so.
##
## The camera path itself lives in menu_camera_path.gd so it can be measured.

const CameraPath := preload("res://scripts/ui/menu/menu_camera_path.gd")
const WorldScene: PackedScene = preload("res://scenes/world/bridge_arena.tscn")

## Depth of field is a Forward+ / Mobile pass; GL Compatibility, which is what
## the web export runs, has none at all. Guarded rather than conditional-compiled
## so the same build behaves correctly whichever renderer it starts under.
const USE_DEPTH_OF_FIELD := true
const DOF_TRANSITION := 55.0      # how gradually the far blur ramps in, in units
const DOF_AMOUNT := 0.055         # a suggestion of softness, not a portrait lens

## Nothing on the path comes within 13 units of the bridge, so a near plane well
## out from the default buys depth precision on the 400-unit-distant city scan
## for free.
const NEAR_PLANE := 0.5

signal first_frame_ready

var camera: Camera3D

var _arena: Node3D
var _dof: CameraAttributesPractical
var _clock: float = 0.0
var _running: bool = false


func _ready() -> void:
	# The camera goes in before the arena so that the arena's own _ready cascade —
	# which is where the terrain, facades and landmarks are actually generated —
	# happens with a valid current camera already framing the shot. Otherwise the
	# first frame is rendered from the origin.
	camera = Camera3D.new()
	camera.name = "MenuCamera"
	camera.near = NEAR_PLANE
	add_child(camera)
	_apply_depth_of_field()
	_place(0.0)
	camera.current = true

	_arena = WorldScene.instantiate()
	_arena.name = "Arena"
	add_child(_arena)

	_running = true
	_announce_ready.call_deferred()


func _announce_ready() -> void:
	first_frame_ready.emit()


# --- Lifetime ----------------------------------------------------------------

## Detach now, free later. See the note at the top: the synchronous detach is the
## whole point, because `queue_free()` alone would leave this world's
## WorldEnvironment and camera live for the rest of the frame in which the match
## starts building its own.
func dismiss() -> void:
	_running = false
	set_process(false)
	if camera != null and is_instance_valid(camera):
		camera.current = false
	var parent := get_parent()
	if parent != null:
		parent.remove_child(self)
	queue_free()


## Freeze the move without tearing anything down — used when the menu is hidden
## but still alive.
func set_running(on: bool) -> void:
	_running = on
	set_process(on)


# --- The move ----------------------------------------------------------------

func _process(delta: float) -> void:
	if not _running:
		return
	_clock = fposmod(_clock + delta, CameraPath.PERIOD)
	_place(_clock / CameraPath.PERIOD)


func _place(u: float) -> void:
	var shot := CameraPath.sample(u)
	var pos: Vector3 = shot["position"]
	var target: Vector3 = shot["target"]
	camera.fov = shot["fov"]
	# Safe against the degenerate look_at: the path's pitch never approaches
	# vertical and the target is always tens of units away.
	camera.look_at_from_position(pos, target, Vector3.UP)
	if _dof != null:
		_dof.dof_blur_far_distance = shot["focus"]


## Where the camera is in its swing, as -1 (Ribeira side) to +1 (Gaia side).
## hero_stage.gd shears the foreground cut-outs against this so they parallax
## with the world instead of floating over it.
func sway() -> float:
	var shot := CameraPath.sample(_clock / CameraPath.PERIOD)
	var pos: Vector3 = shot["position"]
	var azimuth := atan2(pos.x - CameraPath.PIVOT.x, pos.z - CameraPath.PIVOT.z)
	var span := CameraPath.AZIMUTH.y + CameraPath.AZIMUTH.z
	return clampf((azimuth - CameraPath.AZIMUTH.x) / maxf(span, 0.001), -1.0, 1.0)


# --- Depth of field ----------------------------------------------------------

## A shallow far blur so the photogrammetry city goes soft and the logo has
## something quiet to sit on. Skipped entirely off Forward+: Compatibility has no
## DOF pass, and attaching CameraAttributes it cannot use is noise.
func _apply_depth_of_field() -> void:
	if not USE_DEPTH_OF_FIELD:
		return
	if RenderingServer.get_current_rendering_method() != "forward_plus":
		return
	var attrs := CameraAttributesPractical.new()
	# Left at the neutral defaults on purpose: this resource exists to carry DOF,
	# and an exposure multiplier or an auto-exposure curve here would silently
	# re-grade a scene whose look is authored in porto_golden_hour.tres.
	attrs.exposure_multiplier = 1.0
	attrs.auto_exposure_enabled = false
	attrs.dof_blur_far_enabled = true
	attrs.dof_blur_far_transition = DOF_TRANSITION
	attrs.dof_blur_amount = DOF_AMOUNT
	camera.attributes = attrs
	_dof = attrs
