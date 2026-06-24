extends CharacterBody3D
## Adamastor: the rocky stone-giant boss of the Dom Luis Bridge.
##
## Owns its visual model (assembled in code under a "Model" node) and an
## AdamastorStateMachine "brain". The FSM drives patrol + attacks via the public
## animation hooks below (bob_arms / raise_arms / slam_arms_down) and throw_rock
## helpers. Damage is routed through GameManager: this node only REACTS to
## boss_damaged (flinch + white flash + death) and boss_phase_changed (go red).

const GRAVITY := 30.0
const CONTACT_DAMAGE := 5
const CONTACT_RANGE := 5.0
const CONTACT_COOLDOWN := 1.0
const NUDGE_DECAY := 22.0

const BODY_GREY := Color(0.41, 0.41, 0.42)
const DARK_GREY := Color(0.28, 0.29, 0.32)
const EYE_COLOR := Color(1.0, 0.45, 0.1)
const PHASE2_TINT := Color(0.72, 0.16, 0.12)

var _fsm: AdamastorStateMachine
var _model: Node3D
var _head: Node3D
var _left_arm: Node3D
var _right_arm: Node3D
var _arm_base_y: float = 0.0

var _materials: Array[ShaderMaterial] = []
var _orig_colors: Array[Color] = []
var _base_colors: Array[Color] = []
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
	# Gravity keeps the giant planted on the deck.
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

	# Apply + decay any knockback nudge from Boxy's dash.
	velocity.x += _nudge.x
	velocity.z += _nudge.z
	_nudge = _nudge.move_toward(Vector3.ZERO, NUDGE_DECAY * delta)

	move_and_slide()
	_clamp_to_arena()
	_track_head(delta)

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
	raise_arms(false)
	# Restore the original grey look (clears any phase-2 red tint).
	for i in _materials.size():
		_base_colors[i] = _orig_colors[i]
		_materials[i].set_shader_parameter("albedo_color", _orig_colors[i])
		_materials[i].set_shader_parameter("emission_color", Color(0, 0, 0, 1))
		_materials[i].set_shader_parameter("emission_energy", 0.0)
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
	if _flashing:
		return
	_flashing = true
	for m in _materials:
		m.set_shader_parameter("albedo_color", Color.WHITE)
	await get_tree().create_timer(0.05).timeout
	for i in _materials.size():
		_materials[i].set_shader_parameter("albedo_color", _base_colors[i])
	_flashing = false


func _on_phase_changed(phase: int) -> void:
	if phase < 2:
		return
	for i in _materials.size():
		var tinted: Color = _orig_colors[i].lerp(PHASE2_TINT, 0.75)
		_base_colors[i] = tinted
		_materials[i].set_shader_parameter("albedo_color", tinted)
		_materials[i].set_shader_parameter("emission_color", PHASE2_TINT)
		_materials[i].set_shader_parameter("emission_energy", 0.5)
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
		_model.position.y = sin(_menu_anim * 1.1) * 0.18


func _track_head(delta: float) -> void:
	if _dead or _head == null:
		return
	var target := nearest_player()
	if target == null:
		return
	var to := target.global_position - global_position
	# The giant's face is on the -X side; yaw the head toward the hero.
	var desired: float = atan2(to.z, -to.x)
	desired = clampf(desired, -0.7, 0.7)
	_head.rotation.y = lerp_angle(_head.rotation.y, desired, clampf(5.0 * delta, 0.0, 1.0))


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
	# Keep the giant on the bridge so knockbacks can't shove it into the river.
	global_position.z = clampf(global_position.z, -5.0, 5.0)
	global_position.x = clampf(global_position.x, 8.0, 46.0)


# --- Model assembly --------------------------------------------------------

func _build_model() -> void:
	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)

	var body_mat := _register(BODY_GREY)
	var dark_mat := _register(DARK_GREY)

	# Legs (origin is at the feet, y = 0).
	for sz in [-1.3, 1.3]:
		var leg := _box(Vector3(1.6, 3.2, 1.8), Vector3(0.0, 1.6, sz), dark_mat)
		_model.add_child(leg)

	# Torso.
	var torso := _box(Vector3(5.0, 5.2, 4.2), Vector3(0.0, 5.6, 0.0), body_mat)
	_model.add_child(torso)

	# Scattered rocky chunks on the torso for a craggy silhouette.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 9:
		var s := rng.randf_range(0.7, 1.5)
		var chunk := _box(Vector3(s, s, s),
			Vector3(rng.randf_range(-2.0, 2.0), rng.randf_range(4.0, 8.0), -2.1 - rng.randf_range(0.0, 0.4)),
			dark_mat if i % 2 == 0 else body_mat)
		chunk.rotation = Vector3(rng.randf_range(0.0, 1.0), rng.randf_range(0.0, 1.0), rng.randf_range(0.0, 1.0))
		_model.add_child(chunk)

	# Head pivot (for tracking) + head block.
	_head = Node3D.new()
	_head.name = "HeadPivot"
	_head.position = Vector3(0.0, 9.2, 0.0)
	_model.add_child(_head)
	var head := _box(Vector3(3.4, 2.8, 3.0), Vector3.ZERO, body_mat)
	_head.add_child(head)

	# Angry orange eyes + dark brows on the -X (front) face.
	var eye_mat := ToonFactory.glow(EYE_COLOR, 2.5)
	for sz in [-0.8, 0.8]:
		var eye := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 0.35
		em.height = 0.7
		eye.mesh = em
		eye.material_override = eye_mat
		eye.position = Vector3(-1.55, 0.25, sz)
		_head.add_child(eye)

		var brow := _box(Vector3(0.25, 0.3, 1.0), Vector3(-1.5, 0.85, sz), dark_mat)
		brow.rotation.x = (0.35 if sz < 0.0 else -0.35)
		_head.add_child(brow)

	# Arms (pivot groups so they raise/slam as a unit). Built on the +/-Z sides.
	_arm_base_y = 0.0
	_left_arm = _build_arm(Vector3(0.0, 7.4, -2.9), body_mat, dark_mat)
	_right_arm = _build_arm(Vector3(0.0, 7.4, 2.9), body_mat, dark_mat)
	_model.add_child(_left_arm)
	_model.add_child(_right_arm)


func _build_arm(shoulder: Vector3, arm_mat: ShaderMaterial, fist_mat: ShaderMaterial) -> Node3D:
	var grp := Node3D.new()
	grp.position = shoulder
	# Upper arm hangs below the shoulder.
	var upper := _box(Vector3(1.6, 4.0, 1.6), Vector3(0.0, -2.0, 0.0), arm_mat)
	grp.add_child(upper)
	# Fist at the bottom.
	var fist := _box(Vector3(2.2, 2.0, 2.2), Vector3(0.0, -4.4, 0.0), fist_mat)
	grp.add_child(fist)
	return grp


func _box(size: Vector3, pos: Vector3, mat: ShaderMaterial) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	return mi


## Make a body material and remember it for flashing / phase-2 recolour.
func _register(color: Color) -> ShaderMaterial:
	var mat := ToonFactory.solid(color, 0.06)
	_materials.append(mat)
	_orig_colors.append(color)
	_base_colors.append(color)
	return mat
