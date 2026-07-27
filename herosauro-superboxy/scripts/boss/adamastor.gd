extends CharacterBody3D
## Adamastor: the rocky stone-giant boss of the Dom Luís Bridge.
##
## Visual is a Meshy-generated, RIGGED + ANIMATED glTF giant (assets/models),
## towering ~5x over the human kids. Owns an AdamastorStateMachine "brain"; the
## FSM drives patrol + attacks, and we map FSM state -> a skeletal animation clip
## (walk / run / stomp / kick). Damage is routed through GameManager: this node
## REACTS to boss_damaged (flinch + white flash) and boss_phase_changed (red).

const GRAVITY := 30.0
## Solo tuning: one hero eats every attack that used to be split between two, so
## the giant hits less often and slightly softer than it did in co-op. i-frames
## (1.5 s on the hero) already gate the rate; this is the size of each bite.
const CONTACT_DAMAGE := 6
const CONTACT_COOLDOWN := 1.2
const SLAM_DAMAGE := 18
const PHASE2_DAMAGE_MULT := 1.15
const NUDGE_DECAY := 22.0

## Collision volume, mirroring the BoxShape3D in adamastor.tscn (5 x 9 x 4 with
## its centre 4.5 above the feet). Deliberately generous: it is a gameplay
## volume, sized so the hitboxes below read fairly, not an anatomical one.
const BODY_SIZE := Vector3(5.0, 9.0, 4.0)
const BODY_CENTRE_Y := 4.5

# --- Death ------------------------------------------------------------------
const CORPSE_MASS := 900.0
## The corpse is NARROWER than the gameplay volume, and it has to be. Toppling a
## box means pivoting on its bottom edge, which costs m*g*dh where dh is how far
## the centre of mass has to climb to get over that edge. At the full 5 m width
## that is 0.65 m — about 17.5 kJ — and measured headless, a body spun at
## 4 rad/s reaches 11 degrees, rocks, and stands back up. Narrowing to 2.8 m
## (which is closer to what the model actually occupies anyway) drops the barrier
## to ~6 kJ and the same spin clears it three times over.
const CORPSE_SIZE := Vector3(2.8, 8.6, 2.4)
const CORPSE_CENTRE_Y := 4.3
const TOPPLE_SPIN := 5.0

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
var _corpse: AdamastorCorpse = null
var _nudge: Vector3 = Vector3.ZERO

# Hitboxes replacing the old distance checks. See _build_hitboxes().
var _body_box: Hitbox = null
var _contact_box: Hitbox = null
var _slam_box: Hitbox = null


func _ready() -> void:
	add_to_group("boss")
	collision_layer = PhysicsLayers.BOSS
	# WORLD only, deliberately. Adding PLAYERS here would let a 1.7 m kid
	# body-block a nine-metre giant, because two CharacterBody3Ds are both
	# infinitely massive to each other and move_and_slide() would simply stop
	# the boss dead against the hero. The collision is asymmetric instead: the
	# giant's LAYER is in the hero's mask, so the hero cannot walk into it, and
	# _body_box shoves out anyone who ends up inside anyway (knocked in, spawned
	# in, or squeezed against a rail). Props are handled the same way — a 45 kg
	# barrel is hurled aside, never an obstacle.
	collision_mask = PhysicsLayers.WORLD
	_build_model()
	_build_hitboxes()
	_fsm = AdamastorStateMachine.new(self)
	GameManager.boss_damaged.connect(_on_boss_damaged)
	GameManager.boss_phase_changed.connect(_on_phase_changed)
	GameManager.game_started.connect(reset_boss)


func _physics_process(delta: float) -> void:
	var active := not _dead and GameManager.state == GameManager.State.PLAYING
	_sync_hitboxes(active)

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = -1.0

	velocity.x = 0.0
	velocity.z = 0.0

	if active:
		_fsm.update(delta)

	velocity.x += _nudge.x
	velocity.z += _nudge.z
	_nudge = _nudge.move_toward(Vector3.ZERO, NUDGE_DECAY * delta)

	move_and_slide()
	_clamp_to_arena()
	_update_animation()


# --- Hitboxes ---------------------------------------------------------------

## Three shape-cast volumes replace the giant's old `distance_to() < 5.0` test
## and the state machine's ad-hoc checks.
##
## Local -X is the giant's forward: face_toward() solves yaw so that the body's
## -X axis points at the target (see the note on that function), so the slam
## volume sits at negative X.
func _build_hitboxes() -> void:
	# Body volume. Slightly proud of the CharacterBody3D box so a hero pressed
	# against the giant registers as inside it. damage 0 means "shove, don't
	# hurt" — no i-frames burned, no hurt sound, no HUD flinch — and props
	# caught under the giant's feet are hurled away hard enough to shatter.
	_body_box = Hitbox.box(self, BODY_SIZE + Vector3(1.4, 0.0, 1.4),
		Vector3(0.0, BODY_CENTRE_Y, 0.0),
		PhysicsLayers.PLAYERS | PhysicsLayers.PROPS, "BodyVolume")
	_body_box.damage = 0
	_body_box.knockback = 9.0
	# No lift: apply_knockback only touches velocity.y when the impulse has a
	# vertical component, and a hero bunny-hopping every 0.22 s while pressed
	# against the giant's shin reads as a bug, not as a shove.
	_body_box.lift = 0.0
	_body_box.prop_impulse = 26.0
	_body_box.rehit_delay = 0.22

	# Damage volume, a touch tighter than the shove volume so you always get
	# pushed out before you start taking chip damage.
	_contact_box = Hitbox.box(self, BODY_SIZE + Vector3(0.8, 0.0, 0.8),
		Vector3(0.0, BODY_CENTRE_Y, 0.0), PhysicsLayers.PLAYERS, "ContactVolume")
	_contact_box.damage = CONTACT_DAMAGE
	_contact_box.knockback = 8.0
	_contact_box.lift = 4.0
	_contact_box.rehit_delay = CONTACT_COOLDOWN

	# The slam's direct hit, in front of and just above the feet. Opened for the
	# animation's active frames only; the Shockwave area is the separate, wider,
	# weaker ring that catches anyone who ran but not far enough.
	_slam_box = Hitbox.sphere(self, 5.2, Vector3(-4.2, 1.2, 0.0),
		PhysicsLayers.PLAYERS | PhysicsLayers.PROPS, "SlamVolume")
	_slam_box.damage = SLAM_DAMAGE
	_slam_box.knockback = 16.0
	_slam_box.lift = 7.0
	_slam_box.prop_impulse = 45.0


func _sync_hitboxes(active: bool) -> void:
	if _body_box == null:
		return
	if active == _body_box.is_armed():
		return
	if active:
		_body_box.arm()
		_contact_box.arm()
	else:
		_body_box.disarm()
		_contact_box.disarm()
		_slam_box.disarm()


## Open the slam's active-frames window. Driven by the FSM at the impact beat
## rather than by a timer, so the window is exactly the animation's.
func arm_slam(duration: float = 0.16) -> void:
	if _slam_box == null:
		return
	_slam_box.damage = int(round(SLAM_DAMAGE * (PHASE2_DAMAGE_MULT if _phase2 else 1.0)))
	_slam_box.arm(duration)


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
	# Hand the model back before anything else touches it: after a death it is
	# parented to the corpse, not to us.
	if _corpse and is_instance_valid(_corpse):
		_corpse.dismiss()
	_corpse = null
	collision_layer = PhysicsLayers.BOSS   # a previous _die() zeroed it
	global_position = SPAWN
	rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	_nudge = Vector3.ZERO
	if _model:
		_model.position = Vector3.ZERO
		_model.rotation = Vector3.ZERO
	if _anim:
		_anim.active = true
	if _contact_box:
		# Difficulty rides the giant's damage as well as its speed, so EASY is
		# genuinely gentler on a solo run rather than merely slower.
		_contact_box.damage = maxi(1, int(round(CONTACT_DAMAGE * GameManager.difficulty_scalar())))
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


## Hand the body to physics and let it fall. See adamastor_corpse.gd for why
## this is a whole-body topple and not a skeletal ragdoll.
func _die() -> void:
	_dead = true
	if _fsm:
		_fsm.stop()
	if _anim:
		# active = false, not pause(): the mixer must stop writing bone poses
		# entirely, or it keeps re-posing the mesh inside the falling corpse.
		_anim.active = false
	GameManager.request_shake(0.5, 0.5)
	collision_layer = 0
	_sync_hitboxes(false)
	if _model == null:
		return

	# Fall away from whoever landed the killing blow, carrying whatever
	# horizontal momentum it already had.
	var away := Vector3.LEFT
	var killer := nearest_player()
	if killer:
		var to := global_position - killer.global_position
		to.y = 0.0
		if to.length() > 0.01:
			away = to.normalized()

	# Angular velocity w satisfying w x UP = away, so the giant's head goes over
	# in the direction it is falling instead of spinning on the spot.
	var spin := Vector3.UP.cross(away) * TOPPLE_SPIN
	_corpse = AdamastorCorpse.topple(self, _model, CORPSE_SIZE, CORPSE_CENTRE_Y,
		Vector3(velocity.x, 0.0, velocity.z), away * 1.8 + Vector3.UP * 1.5,
		spin, CORPSE_MASS)


# --- Clamp -----------------------------------------------------------------

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
	# Upgrade to PBR *before* _collect_materials, so the cached overrides the hit
	# flash and phase-2 tint mutate are the upgraded ones. The giant reads as
	# rough stone rather than a flat albedo decal.
	ToonFactory.upgrade_glb_materials(inst, 0.88, 0.0, 1.4)
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
