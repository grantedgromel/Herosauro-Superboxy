extends CharacterBody3D
## Adamastor: the rocky stone-giant boss of the Dom Luís Bridge.
##
## Visual is a Meshy-generated, RIGGED + ANIMATED glTF giant (assets/models),
## towering ~5x over the human kids. Owns an AdamastorStateMachine "brain"; the
## FSM drives patrol + attacks, and we map FSM state -> a skeletal animation clip
## (walk / run / stomp / kick). Damage is routed through GameManager: this node
## REACTS to boss_damaged (flinch + white flash) and boss_phase_changed (red).

const GRAVITY := 30.0
const CONTACT_DAMAGE := 5
const CONTACT_RANGE := 5.0
const CONTACT_COOLDOWN := 1.0
const NUDGE_DECAY := 22.0

# Compact arena (single source of truth — main.gd's BOSS_SPAWN matches SPAWN).
const SPAWN := Vector3(16.0, 2.0, 0.0)
const ARENA_X_MIN := -14.0   # reaches past the player spawn zone (-12/-8) so chase can close
const ARENA_X_MAX := 24.0
const ARENA_Z := 5.0

const AdamastorModel: PackedScene = preload("res://assets/models/adamastor.glb")
const MODEL_YAW := -PI / 2.0   # face -X, toward the approaching heroes
const MODEL_SCALE := 4.8       # rigged model is ~1.9u -> ~9u giant

var _fsm: AdamastorStateMachine
var _model: Node3D
var _anim: AnimationPlayer
var _clip_walk := ""
var _clip_run := ""
var _clip_stomp := ""
var _clip_kick := ""
var _cur_clip := ""

# Material handling for hit-flash / phase-2 recolour.
var _mesh_mats: Array[StandardMaterial3D] = []
var _mat_orig: Array[Color] = []
var _mat_cur: Array[Color] = []
var _phase2: bool = false
var _flashing: bool = false

# FSM still calls these arm hooks; the skeletal anim handles motion now, so they
# are safe no-ops (no separate arm nodes on the rigged mesh).
var _head: Node3D = null
var _left_arm: Node3D = null
var _right_arm: Node3D = null
var _arm_base_y: float = 0.0

var _dead: bool = false
var _death_tween: Tween = null
var _contact_cd: float = 0.0
var _nudge: Vector3 = Vector3.ZERO


func _ready() -> void:
	add_to_group("boss")
	collision_layer = 1 << 2
	collision_mask = 1 << 0
	_build_model()
	_fsm = AdamastorStateMachine.new(self)
	GameManager.boss_damaged.connect(_on_boss_damaged)
	GameManager.boss_phase_changed.connect(_on_phase_changed)
	GameManager.game_started.connect(reset_boss)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = -1.0

	velocity.x = 0.0
	velocity.z = 0.0

	if not _dead and GameManager.state == GameManager.State.PLAYING:
		_fsm.update(delta)

	velocity.x += _nudge.x
	velocity.z += _nudge.z
	_nudge = _nudge.move_toward(Vector3.ZERO, NUDGE_DECAY * delta)

	move_and_slide()
	_clamp_to_arena()
	_update_animation()

	if _contact_cd > 0.0:
		_contact_cd -= delta
	if not _dead and GameManager.state == GameManager.State.PLAYING:
		_check_contact()


# --- Animation -------------------------------------------------------------

func _update_animation() -> void:
	if _dead or _anim == null:
		return
	var want := _clip_run if _phase2 else _clip_walk
	if _fsm:
		if _fsm.state == AdamastorStateMachine.SLAM:
			want = _clip_stomp
		elif _fsm.state == AdamastorStateMachine.ROCK_THROW:
			want = _clip_kick
	if want != "" and want != _cur_clip:
		_cur_clip = want
		_anim.play(want)


# --- Public API (used by the state machine / Super Boxy) -------------------

## True while the giant is committed to a slam or rock-throw wind-up (lets the
## camera ease out to reveal the telegraph / AoE).
func is_attacking() -> bool:
	return _fsm != null and (_fsm.state == AdamastorStateMachine.SLAM or _fsm.state == AdamastorStateMachine.ROCK_THROW)


func nearest_player() -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for p in get_tree().get_nodes_in_group("players"):
		var d := global_position.distance_to((p as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = p
	return best


func bob_arms(_amount: float) -> void:
	pass


func raise_arms(_up: bool) -> void:
	pass


func slam_arms_down() -> void:
	pass


func nudge(world_dir: Vector3, amount: float) -> void:
	var d := world_dir
	d.y = 0.0
	if d.length() < 0.01:
		return
	_nudge += d.normalized() * amount * 6.0


func reset_boss() -> void:
	_dead = false
	# Kill any in-flight death fall so it can't keep tipping the model after a Play Again.
	if _death_tween and _death_tween.is_valid():
		_death_tween.kill()
	_death_tween = null
	collision_layer = 1 << 2   # restore "boss" layer (a previous _die() zeroed it)
	global_position = SPAWN
	rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	_nudge = Vector3.ZERO
	if _model:
		_model.position = Vector3.ZERO
		_model.rotation = Vector3.ZERO
	_phase2 = false
	for i in _mesh_mats.size():
		_mat_cur[i] = _mat_orig[i]
		_mesh_mats[i].albedo_color = _mat_orig[i]
	if _anim and _clip_walk != "":
		_cur_clip = _clip_walk
		_anim.play(_clip_walk)
	if _fsm:
		_fsm.reset()


# --- Damage reactions ------------------------------------------------------

func _on_boss_damaged(_amount: int, new_health: int) -> void:
	if _dead:
		return
	# start_game() emits a zero-damage boss_damaged purely to sync the HUD bar;
	# don't play a hit reaction (sound / flinch / flash) for it.
	if _amount <= 0:
		return
	AudioManager.play_boss_hit()
	_flinch()
	_flash()
	if new_health <= 0:
		_die()


func _flinch() -> void:
	if not _model:
		return
	var tween := create_tween()
	tween.tween_property(_model, "position:x", 0.6, 0.05)
	tween.tween_property(_model, "position:x", 0.0, 0.12)


func _flash() -> void:
	if _flashing or _mesh_mats.is_empty():
		return
	_flashing = true
	for m in _mesh_mats:
		m.albedo_color = Color(2.2, 2.2, 2.2)
	await get_tree().create_timer(0.05).timeout
	for i in _mesh_mats.size():
		_mesh_mats[i].albedo_color = _mat_cur[i]
	_flashing = false


func _on_phase_changed(phase: int) -> void:
	if phase < 2:
		return
	_phase2 = true
	for i in _mesh_mats.size():
		var red: Color = _mat_orig[i] * Color(1.5, 0.55, 0.45)
		_mat_cur[i] = red
		if not _flashing:
			_mesh_mats[i].albedo_color = red
	if _fsm:
		_fsm.enter_phase_two()


func _die() -> void:
	_dead = true
	if _fsm:
		_fsm.stop()
	if _anim:
		_anim.pause()
	GameManager.request_shake(0.4, 0.4)
	collision_layer = 0
	if _model:
		_death_tween = create_tween().set_parallel(true)
		_death_tween.tween_property(_model, "rotation:z", deg_to_rad(82.0), 1.5)
		_death_tween.tween_property(_model, "position", Vector3(-3.0, -1.5, 0.0), 1.5)


# --- Contact / clamp -------------------------------------------------------

func _check_contact() -> void:
	if _contact_cd > 0.0:
		return
	for p in get_tree().get_nodes_in_group("players"):
		var pl := p as Node3D
		if global_position.distance_to(pl.global_position) < CONTACT_RANGE:
			if pl.has_method("take_hit"):
				var dir := pl.global_position - global_position
				dir.y = 0.0
				if dir.length() < 0.01:
					dir = Vector3.LEFT
				dir = dir.normalized()
				if pl.take_hit(CONTACT_DAMAGE, dir * 8.0 + Vector3.UP * 4.0):
					_contact_cd = CONTACT_COOLDOWN


func _clamp_to_arena() -> void:
	global_position.z = clampf(global_position.z, -ARENA_Z, ARENA_Z)
	global_position.x = clampf(global_position.x, ARENA_X_MIN, ARENA_X_MAX)


## Rotate the giant (body + its child model) to face a world point, smoothly.
## The model carries a fixed MODEL_YAW offset and faces -X at body-rotation 0,
## so body yaw = atan2(dir.z, -dir.x) aims that baked facing along `dir`.
func face_toward(world_pos: Vector3, weight: float = 0.18) -> void:
	var to := world_pos - global_position
	to.y = 0.0
	if to.length() < 0.5:
		return
	var dir := to.normalized()
	var target := atan2(dir.z, -dir.x)
	rotation.y = lerp_angle(rotation.y, target, weight)


# --- Model -----------------------------------------------------------------

func _build_model() -> void:
	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)
	var inst := AdamastorModel.instantiate()
	inst.rotation.y = MODEL_YAW
	inst.scale = Vector3.ONE * MODEL_SCALE
	_model.add_child(inst)
	_anim = _find_anim_player(inst)
	_setup_clips()
	_collect_materials(inst)


func _setup_clips() -> void:
	if _anim == null:
		return
	_clip_walk = _resolve("walk")
	_clip_run = _resolve("run")
	_clip_stomp = _resolve("stomp")
	_clip_kick = _resolve("kick")
	for c in [_clip_walk, _clip_run]:
		if c != "":
			var a := _anim.get_animation(c)
			if a:
				a.loop_mode = Animation.LOOP_LINEAR
	if _clip_walk != "":
		_cur_clip = _clip_walk
		_anim.play(_clip_walk)


func _resolve(want: String) -> String:
	if _anim == null:
		return ""
	for a in _anim.get_animation_list():
		if want in String(a).to_lower():
			return a
	return ""


func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var r := _find_anim_player(c)
		if r:
			return r
	return null


## Give each surface a unique override material we can recolour for the
## hit-flash / phase-2 tint without touching the shared imported asset.
func _collect_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			for s in mi.mesh.get_surface_count():
				var base := mi.mesh.surface_get_material(s)
				if base is StandardMaterial3D:
					var dup: StandardMaterial3D = (base as StandardMaterial3D).duplicate()
					mi.set_surface_override_material(s, dup)
					_mesh_mats.append(dup)
					_mat_orig.append(dup.albedo_color)
					_mat_cur.append(dup.albedo_color)
	for child in node.get_children():
		_collect_materials(child)
