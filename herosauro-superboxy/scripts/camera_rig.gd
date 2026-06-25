extends Node3D
## CameraRig: a Node3D that owns a single Camera3D child and frames both heroes
## at an arcade-fighter scale — a close, low, near-side-on shot (à la Street
## Fighter / Tekken) so the characters read large. Widens a little as players
## separate, handles screen shake, and pulls out for the victory pose.

@export var follow_speed: float = 4.0
@export var base_distance: float = 9.5    # close in, so the heroes fill the frame
@export var height: float = 5.0           # low, near-side-on — kept above the y4 near rail so it never occludes
@export var separation_factor: float = 0.28
@export var look_offset_x: float = -2.0
@export var look_height: float = 2.2      # eyeline target above the focus (chest height)
@export var min_distance: float = 8.0     # hard floor: heroes never shrink below this
@export var max_distance: float = 15.0    # hard ceiling: separation can't dolly out forever
@export var boss_focus_weight: float = 0.15  # keep the heroes dominant; the giant just looms in

var camera: Camera3D
var _last_focus: Vector3 = Vector3(0.0, 2.0, 0.0)
var _shake_strength: float = 0.0
var _shake_time: float = 0.0
var _shake_total: float = 0.0
var _extra_zoom: float = 0.0


func _ready() -> void:
	add_to_group("camera_rig")
	camera = get_node_or_null("Camera3D")
	if camera == null:
		camera = Camera3D.new()
		camera.name = "Camera3D"
		add_child(camera)
	camera.fov = 50.0   # slightly telephoto -> flatter, more "fighting game" perspective
	camera.current = true
	GameManager.camera_shake_requested.connect(_on_shake_requested)
	GameManager.game_over.connect(_on_game_over)
	GameManager.game_started.connect(func() -> void: _extra_zoom = 0.0)


func _process(delta: float) -> void:
	var players := get_tree().get_nodes_in_group("players")
	var focus := _focus_point(players)
	# Pull the frame toward the boss so the giant and the heroes share one tight shot,
	# rather than centring on empty deck while the boss sits off-screen.
	var boss := get_tree().get_first_node_in_group("boss")
	if boss and is_instance_valid(boss):
		focus = focus.lerp((boss as Node3D).global_position, boss_focus_weight)

	var sep := _separation(players)
	# Deadzone (sep-6): normal co-op spread doesn't dolly at all; the clamp caps the worst case.
	# Victory _extra_zoom rides on top so the celebratory pull-out still reads.
	var dist := clampf(base_distance + maxf(sep - 6.0, 0.0) * separation_factor, min_distance, max_distance) + _extra_zoom

	var target := focus + Vector3(look_offset_x, height + _extra_zoom * 0.4, dist)
	global_position = global_position.lerp(target, clamp(follow_speed * delta, 0.0, 1.0))

	var shake_off := Vector3.ZERO
	if _shake_time > 0.0:
		_shake_time -= delta
		var k: float = _shake_strength * (_shake_time / max(0.0001, _shake_total))
		shake_off = Vector3(randf_range(-k, k), randf_range(-k, k), 0.0)
	camera.position = shake_off
	camera.look_at(focus + Vector3(0.0, look_height, 0.0), Vector3.UP)


func _focus_point(players: Array) -> Vector3:
	if players.is_empty():
		return _last_focus
	var sum := Vector3.ZERO
	for p in players:
		sum += (p as Node3D).global_position
	_last_focus = sum / float(players.size())
	return _last_focus


func _separation(players: Array) -> float:
	if players.size() < 2:
		return 0.0
	var a := (players[0] as Node3D).global_position
	var b := (players[1] as Node3D).global_position
	return Vector2(a.x - b.x, a.z - b.z).length()


func _on_shake_requested(strength: float, duration: float) -> void:
	_shake_strength = max(_shake_strength, strength)
	_shake_time = duration
	_shake_total = duration


func _on_game_over(victory: bool) -> void:
	if victory:
		_extra_zoom = 14.0
