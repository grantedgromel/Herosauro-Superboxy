extends Node
## Headless screenshot harness — the backbone of the visual review loop.
##
## Loads the world, parks a free camera at a fixed set of vantage points, and
## writes a PNG per shot. Vantage points are deliberately stable between runs so
## successive review passes are directly comparable.
##
## Usage:
##   godot --path . tools/shotrunner.tscn -- --out=/abs/dir [--only=deck_mid,...]
##
## Runs under Xvfb + lavapipe (software Vulkan) since this container has no GPU:
##   VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json \
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . tools/shotrunner.tscn \
##     --rendering-driver vulkan -- --out=/tmp/shots

const WorldScene: PackedScene = preload("res://scenes/world/bridge_arena.tscn")

## Each shot: name, camera position, look-at target, fov.
## Chosen to cover playable surfaces, the backdrop, and known defect hotspots.
const SHOTS: Array[Dictionary] = [
	{"name": "01_deck_mid", "pos": Vector3(0, 5, 16), "look": Vector3(0, 2.5, 0), "fov": 55.0},
	{"name": "02_deck_eye", "pos": Vector3(-6, 3.6, 4), "look": Vector3(30, 2.5, -1), "fov": 65.0},
	{"name": "03_porto_end", "pos": Vector3(-38, 6, 14), "look": Vector3(-60, 4, -18), "fov": 60.0},
	{"name": "04_gaia_end", "pos": Vector3(38, 6, 14), "look": Vector3(62, 4, -18), "fov": 60.0},
	{"name": "05_under_arch", "pos": Vector3(0, -8, 22), "look": Vector3(0, -2, -4), "fov": 60.0},
	{"name": "06_wide_river", "pos": Vector3(-70, 18, 70), "look": Vector3(10, -2, -20), "fov": 50.0},
	{"name": "07_backdrop", "pos": Vector3(0, 12, 20), "look": Vector3(0, 10, -60), "fov": 55.0},
	{"name": "08_rail_close", "pos": Vector3(-2, 3.2, 3.2), "look": Vector3(-2, 3.0, -6), "fov": 45.0},
	{"name": "09_water_close", "pos": Vector3(0, -10, 18), "look": Vector3(0, -14, -6), "fov": 55.0},
	{"name": "10_skyline_high", "pos": Vector3(-20, 30, 55), "look": Vector3(0, 8, -30), "fov": 55.0},
]

var _out_dir: String = "/tmp/shots"
var _only: PackedStringArray = []
var _cam: Camera3D
var _queue: Array[Dictionary] = []
var _settle: int = 0
var _current: Dictionary = {}

## Frames to wait after moving the camera. TAA/SDFGI/SSAO and the sky radiance
## map all need several frames to converge, otherwise shots come out noisy.
const SETTLE_FRAMES: int = 24


func _ready() -> void:
	_parse_args()
	DirAccess.make_dir_recursive_absolute(_out_dir)

	add_child(WorldScene.instantiate())

	_cam = Camera3D.new()
	_cam.current = true
	add_child(_cam)

	for shot in SHOTS:
		if _only.is_empty() or _only.has(shot["name"]):
			_queue.append(shot)

	if _queue.is_empty():
		push_error("shotrunner: no shots matched --only filter")
		get_tree().quit(1)
		return

	print("shotrunner: renderer=", RenderingServer.get_video_adapter_name())
	print("shotrunner: ", _queue.size(), " shots -> ", _out_dir)
	_advance()


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.substr(6)
		elif arg.begins_with("--only="):
			_only = arg.substr(7).split(",", false)


func _advance() -> void:
	if _queue.is_empty():
		print("shotrunner: DONE")
		get_tree().quit()
		return
	_current = _queue.pop_front()
	_cam.global_position = _current["pos"]
	_cam.look_at(_current["look"], Vector3.UP)
	_cam.fov = _current["fov"]
	_settle = SETTLE_FRAMES


func _process(_delta: float) -> void:
	if _current.is_empty():
		return
	if _settle > 0:
		_settle -= 1
		return
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_out_dir, _current["name"]]
	var err := img.save_png(path)
	if err != OK:
		push_error("shotrunner: failed to write %s (err %d)" % [path, err])
	else:
		print("shot: ", _current["name"])
	_current = {}
	_advance()
