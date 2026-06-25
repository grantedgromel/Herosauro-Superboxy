extends Node3D
## CameraRig: a dynamic "action zoom" camera (à la Smash Bros / Streets of Rage 4).
##
## It frames the two heroes close and large by default, then smoothly folds the
## boss into the shot as the giant engages or telegraphs an attack — punching in
## tight during melee and easing out when players spread or a big move winds up,
## so nobody ever leaves the frame. Also handles screen shake and the victory
## pull-out. Distance is derived from how spread-out the framed subjects are, then
## clamped, so characters stay readable at both extremes.

@export var follow_speed: float = 4.0
@export var fov: float = 50.0             # slightly telephoto -> flat "fighting game" perspective
@export var height: float = 5.0           # low, near-side-on (kept above the y4 near rail so it never occludes)
@export var look_offset_x: float = -2.0
@export var look_height: float = 2.2      # eyeline target above the focus (chest height)

@export var min_distance: float = 7.0     # melee punch-in: heroes fill the frame
@export var max_distance: float = 20.0    # spread / boss-windup ceiling: keep everyone on screen
@export var close_pad: float = 1.5        # breathing room added to the fitted distance
@export var player_pad: float = 2.5       # keep heroes off the very edge
@export var boss_pad: float = 4.0         # the giant's body extent
@export var boss_attack_pad: float = 6.0  # extra reveal while the boss winds up an attack
@export var boss_near: float = 9.0        # boss fully framed when within this of a hero
@export var boss_far: float = 26.0        # boss ignored beyond this (heroes stay tight)
@export var boss_focus_bias: float = 0.4  # how far the focus shifts toward an engaged boss

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
	camera.fov = fov
	camera.current = true
	GameManager.camera_shake_requested.connect(_on_shake_requested)
	GameManager.game_over.connect(_on_game_over)
	GameManager.game_started.connect(func() -> void: _extra_zoom = 0.0)


func _process(delta: float) -> void:
	var players := get_tree().get_nodes_in_group("players")
	var focus := _focus_point(players)

	# How much the boss is part of the shot right now: 0 when far/idle (frame just
	# the heroes, tight), ramping to 1 as it closes in, and forced to 1 while it
	# winds up an attack (so the telegraph / AoE is on screen).
	var boss := get_tree().get_first_node_in_group("boss")
	var boss_pos := focus
	var bw := 0.0
	var boss_attacking := false
	if boss and is_instance_valid(boss):
		boss_pos = (boss as Node3D).global_position
		bw = clampf(inverse_lerp(boss_far, boss_near, _nearest_player_dist(players, boss_pos)), 0.0, 1.0)
		boss_attacking = boss.has_method("is_attacking") and boss.is_attacking()
		if boss_attacking:
			bw = 1.0
		focus = focus.lerp(boss_pos, boss_focus_bias * bw)

	# Distance needed to fit the framed subjects horizontally, with padding.
	var tan_h: float = maxf(0.001, tan(deg_to_rad(fov * 0.5)) * _aspect())
	var radius := 0.0
	for p in players:
		radius = maxf(radius, _h_dist(focus, (p as Node3D).global_position) + player_pad)
	if boss and is_instance_valid(boss):
		var bpad := boss_pad + (boss_attack_pad if boss_attacking else 0.0)
		# Scaled by bw so the boss only stretches the frame as it becomes relevant.
		radius = maxf(radius, (_h_dist(focus, boss_pos) + bpad) * bw)

	var dist := clampf(radius / tan_h + close_pad, min_distance, max_distance) + _extra_zoom

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


func _nearest_player_dist(players: Array, pos: Vector3) -> float:
	var best := INF
	for p in players:
		best = minf(best, _h_dist(pos, (p as Node3D).global_position))
	return best if best != INF else 0.0


func _h_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _aspect() -> float:
	var vp := get_viewport()
	if vp:
		var s := vp.get_visible_rect().size
		if s.y > 0.0:
			return s.x / s.y
	return 16.0 / 9.0


func _on_shake_requested(strength: float, duration: float) -> void:
	_shake_strength = max(_shake_strength, strength)
	_shake_time = duration
	_shake_total = duration


func _on_game_over(victory: bool) -> void:
	if victory:
		_extra_zoom = 14.0
