extends CharacterBody3D
## Adamastor: the rocky stone-giant boss of the Dom Luís Bridge.
##
## Visual is a Meshy-generated, web-optimized glTF giant (assets/models),
## replacing the original code-built primitive. It towers ~5x over the human
## kids. Owns an AdamastorStateMachine "brain"; the FSM drives patrol + attacks.
## Damage is routed through GameManager: this node REACTS to boss_damaged
## (flinch + white flash) and boss_phase_changed (tint the whole giant red).
##
## NOTE: the model is a single static mesh, so the arm-animation hooks
## (bob/raise/slam) are currently safe no-ops; a rigged version is the next
## upgrade. The slam/rock attacks themselves still fire from the FSM.

const GRAVITY := 30.0
const CONTACT_DAMAGE := 5
const CONTACT_RANGE := 5.0
const CONTACT_COOLDOWN := 1.0
const NUDGE_DECAY := 22.0

const AdamastorModel: PackedScene = preload("res://assets/models/adamastor.glb")
const MODEL_YAW := -PI / 2.0   # face -X, toward the approaching heroes
const MODEL_SCALE := 4.7       # ~1.9u model -> ~9u giant (collision-box height)

var _fsm: AdamastorStateMachine
var _model: Node3D
var _head: Node3D = null         # no separate head node on the Meshy mesh
var _left_arm: Node3D = null
var _right_arm: Node3D = null
var _arm_base_y: float = 0.0

# Material handling for hit-flash / phase-2 recolour (Meshy StandardMaterial3D).
var _mesh_mats: Array[StandardMaterial3D] = []
var _mat_orig: Array[Color] = []
var _mat_cur: Array[Color] = []
var _phase2: bool = false
var _flashing: bool = false

var _dead: bool = false
var _contact_cd: float = 0.0
var _nudge: Vector3 = Vector3.ZERO
var _menu_anim: float = 0.0


func _ready() -> void:
	add_to_group("boss")
	collision_layer = 1 << 2     # "boss"
	collision_mask = 1 << 0      # collide with "world"
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

	if not _dead:
		match GameManager.state:
			GameManager.State.PLAYING:
				_fsm.update(delta)
			GameManager.State.MENU:
				_menu_idle(delta)

	velocity.x += _nudge.x
	velocity.z += _nudge.z
	_nudge = _nudge.move_toward(Vector3.ZERO, NUDGE_DECAY * delta)

	move_and_slide()
	_clamp_to_arena()

	if _contact_cd > 0.0:
		_contact_cd -= delta
	if not _dead and GameManager.state == GameManager.State.PLAYING:
		_check_contact()


# --- Public API (used by the state machine / Super Boxy) -------------------

func nearest_player() -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for p in get_tree().get_nodes_in_group("players"):
		var d := global_position.distance_to((p as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = p
	return best


func bob_arms(amount: float) -> void:
	if _left_arm:
		_left_arm.position.y = _arm_base_y + amount
	if _right_arm:
		_right_arm.position.y = _arm_base_y - amount


func raise_arms(up: bool) -> void:
	var target := _arm_base_y + (3.0 if up else 0.0)
	for arm in [_left_arm, _right_arm]:
		if arm:
			arm.position.y = target


func slam_arms_down() -> void:
	for arm in [_left_arm, _right_arm]:
		if arm:
			arm.position.y = _arm_base_y - 1.6


func nudge(world_dir: Vector3, amount: float) -> void:
	var d := world_dir
	d.y = 0.0
	if d.length() < 0.01:
		return
	_nudge += d.normalized() * amount * 6.0


func reset_boss() -> void:
	_dead = false
	global_position = Vector3(35.0, 2.0, 0.0)
	velocity = Vector3.ZERO
	_nudge = Vector3.ZERO
	if _model:
		_model.position = Vector3.ZERO
		_model.rotation = Vector3.ZERO
	# Restore the original look (clears any phase-2 red tint / flash).
	_phase2 = false
	for i in _mesh_mats.size():
		_mat_cur[i] = _mat_orig[i]
		_mesh_mats[i].albedo_color = _mat_orig[i]
	if _fsm:
		_fsm.reset()


# --- Damage reactions ------------------------------------------------------

func _on_boss_damaged(_amount: int, new_health: int) -> void:
	if _dead:
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
	GameManager.request_shake(0.4, 0.4)
	collision_layer = 0
	if _model:
		var tween := create_tween().set_parallel(true)
		tween.tween_property(_model, "rotation:z", deg_to_rad(82.0), 1.5)
		tween.tween_property(_model, "position", Vector3(-3.0, -1.5, 0.0), 1.5)


# --- Idle / tracking / contact ---------------------------------------------

func _menu_idle(delta: float) -> void:
	_menu_anim += delta
	bob_arms(sin(_menu_anim * 1.5) * 0.18)
	if _model:
		_model.position.y = sin(_menu_anim * 1.1) * 0.12


func _track_head(_delta: float) -> void:
	# No separate head node on the Meshy mesh; the whole giant faces the heroes.
	return


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
	global_position.z = clampf(global_position.z, -5.0, 5.0)
	global_position.x = clampf(global_position.x, 8.0, 46.0)


# --- Model -----------------------------------------------------------------

func _build_model() -> void:
	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)
	var mesh := AdamastorModel.instantiate()
	mesh.rotation.y = MODEL_YAW
	mesh.scale = Vector3.ONE * MODEL_SCALE
	_model.add_child(mesh)
	_collect_materials(mesh)


## Walk the imported scene, give each surface a unique override material we can
## recolour for the hit-flash / phase-2 tint without touching the shared asset.
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
