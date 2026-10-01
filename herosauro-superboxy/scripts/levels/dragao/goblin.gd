extends Node3D
## A duende: a 1.1 m green goblin from the south with a big head, long pointy
## ears, huge eyes and a cheeky grin, in a red shirt or a green-and-white hooped
## one, shorts and curly pointy shoes. Mischievous, never scary.
##
## Built from a handful of vertex-coloured parts (vc_baker.gd) so it can move:
## body, head, two ears, two arms, two legs (eight draw calls; the dizzy stars
## and the raspberry tongue only while they show). Every motion is procedural
## and accumulated from delta: waddle, ear wiggle, giggle hops, a tumble that
## bounces, squash and stretch on every landing.
##
## It is a "thing heroes can hit" (docs/story/ADAPTATION.md): the root joins
## group "targets", a Hurtbox on TARGETS forwards to take_hit(). The first hit
## tumbles it and leaves it dizzy for DIZZY_TIME; the second leaves it dizzy and
## then one of Herosauro's energy pterodactyls swoops down and carries it off
## (the level supplies the pterodactyl). A carrier drops its cup on the first.
##
## The level (`level`) is its only window on the world: heroes, the dragon,
## the poke tokens, the effects. Deterministic: one seeded RNG per goblin.

signal knocked(goblin: Node3D, first: bool)
signal gone(goblin: Node3D)

const VC := preload("res://scripts/levels/dragao/vc_baker.gd")
const M := preload("res://scripts/levels/dragao/dragao_mats.gd")
const L := preload("res://scripts/levels/dragao/dragao_layout.gd")

enum S { OFF, DANCE, WANDER, FLEE, REST, SNEAK, POKE, TAUNT, TUMBLE, DIZZY, LIFTED, ENTER, LEAVE, TO_VAN, COWER, SIT }

const SCALE := 0.92
const GRAVITY := 24.0
const WALK_SPEED := 2.4
const FLEE_SPEED := 4.7
const CARRY_FLEE_SPEED := 4.2
const SNEAK_SPEED := 2.3
const SPRINT_SPEED := 6.0
const FLEE_RADIUS := 4.2
const FLEE_CALM := 7.0
## Kids must be able to catch them: a goblin that has run this long stops to
## pant for REST_TIME, which is the moment a six-year-old gets there.
const FLEE_TIRE := 2.6
const REST_TIME := 1.3
const DIZZY_TIME := 2.5
const DIZZY_LIFT_TIME := 1.1
const POKE_REACH := 1.05
const POKE_DAMAGE := 5
const HURT_RADIUS := 0.62
const BODY_RADIUS := 0.4

## Palette: three goblin greens, the two shirts, and the friendly extras.
const SKINS := [Color(0.42, 0.78, 0.25), Color(0.33, 0.7, 0.3), Color(0.5, 0.8, 0.2)]
const RED := Color(0.88, 0.13, 0.14)
const HOOP_GREEN := Color(0.06, 0.56, 0.26)
const WHITE := Color(0.96, 0.96, 0.95)
const SHOE := Color(0.5, 0.2, 0.12)
const PINK := Color(1.0, 0.55, 0.62)

static var _meshes: Dictionary = {}

var level = null  # the dragao level (untyped: no cyclic preload)
var shirt: int = 0
var skin: int = 0
var carrying: Node3D = null
var hits: int = 0
var state: int = S.OFF

var _rng := RandomNumberGenerator.new()
var _seed: int = 1
var _t: float = 0.0          # time in state
var _clock: float = 0.0      # accumulated, drives cycles
var _phase: float = 0.0      # walk cycle
var _vel := Vector3.ZERO     # ground velocity
var _air := Vector3.ZERO     # tumble velocity
var _yaw: float = 0.0
var _goal := Vector3.ZERO
var _home: int = S.WANDER    # the calm state to return to
var _flee_for: float = 0.0
var _taunt_in: float = 4.0
var _sneak_in: float = 10.0
var _has_token: bool = false
var _poked: bool = false
var _bounces: int = 0
var _spin_axis := Vector3.RIGHT
var _spin: float = 0.0
var _squash: float = 0.0
var _squash_v: float = 0.0
var _taunt_kind: int = 0
var _ptero: Node3D = null
var _blob: int = -1
var _dance_angle: float = 0.0
var _dance_r: float = 6.5
var _dance_dir: float = 1.0
var _van_spot := Vector3.ZERO
var _invuln: float = 0.0

var _visual: Node3D
var _body: MeshInstance3D
var _head: Node3D
var _head_mi: MeshInstance3D
var _ear_l: MeshInstance3D
var _ear_r: MeshInstance3D
var _tongue: MeshInstance3D
var _arm_l: MeshInstance3D
var _arm_r: MeshInstance3D
var _leg_l: MeshInstance3D
var _leg_r: MeshInstance3D
var _stars: MeshInstance3D
var _socket: Node3D
var _hurtbox: Hurtbox
var _hurt_shape: CollisionShape3D
var _poke: Hitbox


func setup(p_level: Node3D, p_shirt: int, p_seed: int) -> void:
	level = p_level
	shirt = p_shirt
	_seed = p_seed
	skin = p_seed % SKINS.size()


func _ready() -> void:
	_build()
	_blob = level.fx.blob_alloc() if level != null else -1
	deactivate()


# --- Public API (the level) ---------------------------------------------------------

## Bring the goblin on in `mode` at `at`. Resets everything about it.
func activate(at: Vector3, mode: int, p_hits: int = 0) -> void:
	_rng.seed = _seed
	hits = p_hits
	carrying = null
	_ptero = null
	position = Vector3(at.x, 0.0, at.z)
	_vel = Vector3.ZERO
	_air = Vector3.ZERO
	_squash = 0.0
	_squash_v = 0.0
	_invuln = 0.0
	_flee_for = 0.0
	_taunt_in = _rng.randf_range(2.0, 6.0)
	_sneak_in = _rng.randf_range(6.0, 14.0)
	_dance_angle = atan2(at.z, at.x)
	_dance_r = _rng.randf_range(6.3, 7.8)
	_dance_dir = 1.0 if _rng.randf() < 0.5 else -1.0
	visible = true
	_visual.transform = Transform3D(Basis().scaled(Vector3.ONE * SCALE), Vector3.ZERO)
	_tongue.visible = false
	_stars.visible = false
	_set_hittable(true)
	_home = S.DANCE if mode == S.DANCE else S.WANDER
	_enter(mode)


func deactivate() -> void:
	_release_token()
	state = S.OFF
	visible = false
	carrying = null
	_set_hittable(false)
	if level != null:
		level.fx.blob_hide(_blob)
	set_physics_process(false)


func is_active() -> bool:
	return state != S.OFF


## Hittable right now (and so in group "targets").
func is_hittable() -> bool:
	return is_in_group("targets")


## Carry `cup` over the head (stage 2).
func give_cup(cup: Node3D) -> void:
	carrying = cup
	cup.call("attach_to", _socket)


## The dragon's roar: a carrier squeals and lets go of its cup.
func scare_drop() -> void:
	if carrying == null or state in [S.TUMBLE, S.DIZZY, S.LIFTED, S.OFF]:
		return
	_drop_cup(Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized() * 2.0)
	level.giggle(global_position)
	_squash_kick(0.35)
	_flee_for = 0.0
	_enter(S.FLEE)


## Stage 1 is over: run back to the van and hop in.
func panic_leave() -> void:
	if state in [S.TUMBLE, S.DIZZY, S.LIFTED, S.OFF]:
		return
	_enter(S.LEAVE)


## The finale: sprint for the van and wait by it.
func run_to_van(spot: Vector3) -> void:
	if state in [S.LIFTED, S.OFF]:
		return
	_van_spot = spot
	if state in [S.TUMBLE, S.DIZZY]:
		return   # it goes once it has its feet back (see _recover)
	_enter(S.TO_VAN)


## The van went up in a sooty puff: sit down, dazed.
func sit_dazed() -> void:
	if state in [S.LIFTED, S.OFF]:
		return
	_enter(S.SIT)


## A pterodactyl has it: follow the talons until carry_done().
## The level has sent a pterodactyl for it (so it is not summoned twice).
func claim_ptero(ptero: Node3D) -> void:
	_ptero = ptero


func lift_by(ptero: Node3D) -> void:
	_ptero = ptero
	_set_hittable(false)
	_enter(S.LIFTED)


func carry_done() -> void:
	gone.emit(self)
	deactivate()


func is_waiting_for_ptero() -> bool:
	return state == S.DIZZY and hits >= 2 and _ptero == null and _t >= DIZZY_LIFT_TIME


## The contract: a hero's jab, Dino Energy or dash, or a fast football.
func take_hit(_amount: float, knockback: Vector3) -> void:
	if not is_hittable() or _invuln > 0.0:
		return
	hits += 1
	var flat := Vector3(knockback.x, 0.0, knockback.z)
	if flat.length() < 0.1:
		flat = -global_transform.basis.z
		flat.y = 0.0
	flat = flat.normalized()
	AudioManager.play_sfx(&"goblin_hit", global_position)
	level.fx.sparkle(global_position + Vector3.UP * 1.0, Color(1.0, 0.95, 0.6), 1.0)
	if carrying != null:
		_drop_cup(flat * 2.5)
	_release_token()
	_air = flat * 5.2 + Vector3.UP * 6.0
	_spin_axis = Vector3.UP.cross(flat).normalized()
	_bounces = 0
	_invuln = 0.35
	_enter(S.TUMBLE)
	knocked.emit(self, hits == 1)


## Probe and hint helper: where the goblin's body is.
func centre() -> Vector3:
	return global_position + Vector3.UP * 0.55


# --- Brain ------------------------------------------------------------------------

func _enter(s: int) -> void:
	if state == S.SNEAK and s != S.POKE:
		_release_token()
	if state == S.POKE:
		_release_token()
	state = s
	_t = 0.0
	match s:
		S.WANDER, S.ENTER:
			_pick_wander_goal()
		S.TAUNT:
			_taunt_kind = _rng.randi() % 3
			level.giggle(global_position)
		S.POKE:
			_poked = false
		S.TUMBLE:
			_stars.visible = false
			_tongue.visible = false
		S.DIZZY:
			_stars.visible = true
		S.SIT:
			_stars.visible = true
			_set_hittable(false)
		S.LEAVE, S.TO_VAN:
			_set_hittable(s == S.TO_VAN)
	if s != S.DIZZY and s != S.SIT:
		_stars.visible = false
	set_physics_process(s != S.OFF)


func _physics_process(delta: float) -> void:
	if level == null:
		return
	_t += delta
	_clock += delta
	_invuln = maxf(0.0, _invuln - delta)
	var want := Vector3.ZERO      # desired ground velocity
	var hero: Node3D = level.nearest_hero(global_position)
	var to_hero := Vector3.ZERO
	var hero_d := INF
	if hero != null:
		to_hero = hero.global_position - global_position
		to_hero.y = 0.0
		hero_d = to_hero.length()

	match state:
		S.DANCE:
			want = _dance(delta)
			if hero_d < FLEE_RADIUS * 0.85:
				_flee_for = 0.0
				_enter(S.FLEE)
			else:
				_maybe_taunt_or_sneak(delta, hero, hero_d)
		S.WANDER:
			want = _toward(_goal, WALK_SPEED * (0.85 if carrying else 1.0))
			if _flat_dist(_goal) < 0.8 or _t > 7.0:
				_pick_wander_goal()
			if hero_d < FLEE_RADIUS * (1.1 if carrying else 1.0):
				_flee_for = 0.0
				_enter(S.FLEE)
			elif carrying == null:
				_maybe_taunt_or_sneak(delta, hero, hero_d)
		S.ENTER:
			want = _toward(_goal, SPRINT_SPEED * 0.8)
			if _flat_dist(_goal) < 1.0 or _t > 6.0:
				_enter(S.WANDER)
		S.FLEE:
			_flee_for += delta
			var away := -to_hero.normalized() if hero_d < INF else Vector3.FORWARD
			var side := Vector3(-away.z, 0.0, away.x)
			var zig := sin(_clock * 5.5 + float(_seed)) * 0.85
			want = (away + side * zig).normalized() * (CARRY_FLEE_SPEED if carrying else FLEE_SPEED)
			want = _steer_off_walls(want)
			if _flee_for > FLEE_TIRE:
				_enter(S.REST)
			elif hero_d > FLEE_CALM and _t > 0.8:
				_enter(_home)
		S.REST:
			if _t > REST_TIME:
				if hero_d < FLEE_RADIUS:
					_flee_for = FLEE_TIRE * 0.45
					_enter(S.FLEE)
				else:
					_enter(_home)
		S.SNEAK:
			if hero == null or hero_d > 12.0 or _t > 6.0:
				_enter(_home)
			else:
				var behind := hero.global_position - _hero_facing(hero) * 0.8
				want = _toward(behind, SNEAK_SPEED)
				var facing_me := _hero_facing(hero).dot(-to_hero.normalized()) > 0.55
				if facing_me and hero_d < 3.0 and _t > 0.6:
					level.giggle(global_position)
					_flee_for = 0.0
					_enter(S.FLEE)
				elif hero_d < POKE_REACH + 0.3:
					_face(to_hero)
					_enter(S.POKE)
		S.POKE:
			if hero != null:
				_face(to_hero)
			if not _poked and _t > 0.16:
				_poked = true
				_poke.position = Vector3(sin(_yaw) * 0.6, 0.6, cos(_yaw) * 0.6)
				_poke.arm(0.12)
			if _t > 0.55:
				level.giggle(global_position)
				_release_token()
				_flee_for = 0.0
				_enter(S.FLEE)
		S.TAUNT:
			if hero != null:
				_face(to_hero if _taunt_kind != 1 else -to_hero)
			if hero_d < FLEE_RADIUS * 0.8:
				_flee_for = 0.0
				_enter(S.FLEE)
			elif _t > 1.4:
				_enter(_home)
		S.TUMBLE:
			_tumble(delta)
		S.DIZZY:
			if hits < 2 and _t > DIZZY_TIME:
				_recover()
		S.LIFTED:
			if _ptero != null and is_instance_valid(_ptero):
				global_position = _ptero.call("talon_global")
		S.LEAVE:
			var door: Vector3 = level.van_door()
			want = _toward(door, SPRINT_SPEED)
			if _flat_dist(door) < 1.2:
				level.fx.sparkle(global_position + Vector3.UP * 0.6, Color(1, 1, 1), 0.6)
				deactivate()
				return
		S.TO_VAN:
			want = _toward(_van_spot, SPRINT_SPEED)
			if _flat_dist(_van_spot) < 0.5:
				_enter(S.COWER)
		S.COWER:
			_face(level.dragon_position() - global_position)
		S.SIT:
			pass

	_move(want, delta)
	_animate(delta, want)
	level.fx.blob_set(_blob, global_position, 0.42, 1.0)


func _maybe_taunt_or_sneak(delta: float, hero: Node3D, hero_d: float) -> void:
	_taunt_in -= delta
	_sneak_in -= delta
	if hero == null:
		return
	if _sneak_in <= 0.0:
		_sneak_in = _rng.randf_range(8.0, 15.0)
		if hero_d < 11.0 and level.take_poke_token():
			_has_token = true
			_enter(S.SNEAK)
			return
	if _taunt_in <= 0.0:
		_taunt_in = _rng.randf_range(4.0, 8.0)
		if hero_d < 10.0:
			_enter(S.TAUNT)


func _dance(delta: float) -> Vector3:
	_dance_angle += _dance_dir * 0.32 * delta
	var c: Vector3 = level.dragon_position()
	var spot := c + Vector3(cos(_dance_angle), 0.0, sin(_dance_angle)) * _dance_r
	return _toward(spot, 2.2)


func _recover() -> void:
	_squash_kick(0.4)
	if _van_spot != Vector3.ZERO:
		_enter(S.TO_VAN)
		return
	_flee_for = 0.0
	_enter(S.FLEE)


func _tumble(delta: float) -> void:
	_air.y -= GRAVITY * delta
	position += _air * delta
	_spin += delta * 13.0
	var clamped := L.clamp_to_pitch(position, 0.2)
	if clamped.x != position.x:
		_air.x = -_air.x * 0.5
	if clamped.z != position.z:
		_air.z = -_air.z * 0.5
	position.x = clamped.x
	position.z = clamped.z
	if position.y <= 0.0 and _air.y < 0.0:
		position.y = 0.0
		_bounces += 1
		_squash_kick(-0.5 + 0.15 * float(_bounces))
		if _bounces >= 2 or absf(_air.y) < 2.0:
			_air = Vector3.ZERO
			_spin = 0.0
			_enter(S.DIZZY)
			return
		_air.y = -_air.y * 0.42
		_air.x *= 0.6
		_air.z *= 0.6


func _move(want: Vector3, delta: float) -> void:
	if state == S.TUMBLE or state == S.LIFTED:
		return
	var accel := 14.0 if state != S.FLEE else 20.0
	_vel = _vel.move_toward(want, accel * delta)
	var next := position + _vel * delta
	next = _avoid(next)
	next = L.clamp_to_pitch(next, 0.0)
	position = Vector3(next.x, 0.0, next.z)
	if _vel.length() > 0.3 and state not in [S.POKE, S.TAUNT, S.COWER]:
		_face(_vel)


## Out of the dragon, the van and the other goblins (soft circles).
func _avoid(p: Vector3) -> Vector3:
	var out := p
	var circles: Array = level.blockers()
	for c in circles:
		var centre: Vector3 = c[0]
		var r: float = c[1] + BODY_RADIUS
		var d := Vector3(out.x - centre.x, 0.0, out.z - centre.z)
		var len := d.length()
		if len < r and len > 0.001:
			out += d / len * (r - len)
	for g in level.goblins:
		if g == self or not g.visible or g.state in [S.OFF, S.LIFTED, S.TUMBLE]:
			continue
		var d2 := Vector3(out.x - g.position.x, 0.0, out.z - g.position.z)
		var l2 := d2.length()
		if l2 < 0.8 and l2 > 0.001:
			out += d2 / l2 * (0.8 - l2) * 0.5
	return out


## Never run straight into the boards: slide along them, away from corners.
func _steer_off_walls(v: Vector3) -> Vector3:
	var p := position + v * 0.6
	var out := v
	if absf(p.x) > L.ROAM_X - 1.5:
		out.x = -signf(position.x) * absf(out.x) * 0.3
		out.z += signf(out.z if absf(out.z) > 0.1 else -position.z) * 2.0
	if absf(p.z) > L.ROAM_Z - 1.5:
		out.z = -signf(position.z) * absf(out.z) * 0.3
		out.x += signf(out.x if absf(out.x) > 0.1 else -position.x) * 2.0
	return out.normalized() * v.length()


func _pick_wander_goal() -> void:
	for attempt in 6:
		var g := Vector3(_rng.randf_range(-L.PITCH_HALF.x + 2.0, L.PITCH_HALF.x - 2.0), 0.0,
			_rng.randf_range(-L.PITCH_HALF.y + 2.0, L.PITCH_HALF.y - 2.0))
		var hero: Node3D = level.nearest_hero(g)
		if hero == null or _flat(hero.global_position - g).length() > 7.0:
			_goal = g
			return
	_goal = Vector3(_rng.randf_range(-20, 20), 0, _rng.randf_range(-12, 12))


func _drop_cup(push: Vector3) -> void:
	var cup := carrying
	carrying = null
	if cup != null:
		level.cup_dropped(cup, _socket.global_position, push)


func _release_token() -> void:
	if _has_token and level != null:
		level.give_poke_token()
	_has_token = false


func _set_hittable(on: bool) -> void:
	if on and not is_in_group("targets"):
		add_to_group("targets")
	elif not on and is_in_group("targets"):
		remove_from_group("targets")
	if _hurtbox != null:
		_hurtbox.collision_layer = PhysicsLayers.TARGETS if on else 0


# --- Animation ------------------------------------------------------------------------

func _animate(delta: float, want: Vector3) -> void:
	var speed := _flat(_vel).length()
	_phase += delta * (2.0 + speed * 2.6)
	# Squash spring.
	_squash_v += (-190.0 * _squash - 14.0 * _squash_v) * delta
	_squash += _squash_v * delta
	var sq := clampf(_squash, -0.45, 0.45)

	var lift := 0.0
	var roll := 0.0
	var pitch := 0.0
	var arm_l := 0.0
	var arm_r := 0.0
	var arm_side := 0.18
	var leg_l := 0.0
	var leg_r := 0.0
	var head_yaw := 0.0
	var head_pitch := 0.0
	var head_roll := 0.0
	var ear := sin(_clock * 8.0 + float(_seed)) * 0.12
	var ear_back := 0.0
	var walk := sin(_phase * 2.0)
	var breath := 1.0
	_tongue.visible = false

	match state:
		S.DANCE:
			var hop := absf(sin(_clock * 6.5))
			lift = hop * 0.2
			if hop < 0.12 and _squash > -0.05:
				_squash_kick(-0.2)
			roll = sin(_clock * 3.25) * 0.18
			arm_l = -2.6 + sin(_clock * 6.5) * 0.5
			arm_r = -2.6 - sin(_clock * 6.5) * 0.5
			head_roll = sin(_clock * 3.25) * 0.2
			leg_l = sin(_clock * 6.5) * 0.4
			leg_r = -leg_l
		S.FLEE, S.LEAVE, S.TO_VAN, S.ENTER:
			lift = absf(walk) * 0.09
			roll = walk * 0.14
			pitch = 0.22
			if carrying:
				arm_l = -2.9
				arm_r = -2.9
			else:
				arm_l = -2.4 + walk * 0.7
				arm_r = -2.4 - walk * 0.7
			leg_l = walk * 0.85
			leg_r = -walk * 0.85
			ear_back = 0.5
			head_pitch = -0.15
		S.WANDER, S.SNEAK:
			var k := clampf(speed / WALK_SPEED, 0.0, 1.0)
			lift = absf(walk) * 0.06 * k
			roll = walk * 0.16 * k
			if carrying:
				arm_l = -2.9
				arm_r = -2.9
			elif state == S.SNEAK:
				# Tiptoe, hands up rubbing together: up to mischief.
				arm_l = -1.3 + sin(_clock * 14.0) * 0.15
				arm_r = -1.3 - sin(_clock * 14.0) * 0.15
				arm_side = -0.25
				pitch = 0.2
				lift = 0.05 + absf(walk) * 0.04
			else:
				arm_l = walk * 0.6 * k
				arm_r = -walk * 0.6 * k
			leg_l = walk * 0.6 * k
			leg_r = -walk * 0.6 * k
		S.REST:
			# Panting: hands on knees, big breaths.
			pitch = 0.45
			arm_l = -0.5
			arm_r = -0.5
			arm_side = -0.1
			lift = 0.0
			head_pitch = -0.3 + sin(_clock * 9.0) * 0.08
			breath = 1.0 + sin(_clock * 9.0) * 0.035
		S.POKE:
			var k2 := clampf(_t / 0.18, 0.0, 1.0)
			arm_r = lerpf(-0.3, -1.65, k2)
			arm_l = 0.3
			pitch = -0.1 + 0.3 * k2
			lift = 0.05
		S.TAUNT:
			match _taunt_kind:
				0:   # raspberry: tongue out, head waggle
					_tongue.visible = true
					head_yaw = sin(_clock * 26.0) * 0.28
					arm_l = -1.2
					arm_r = -1.2
					arm_side = 0.7
				1:   # bottom wiggle (turned away)
					roll = sin(_clock * 18.0) * 0.25
					pitch = 0.35
					head_yaw = 2.2
					arm_l = -0.6
					arm_r = -0.6
				_:   # giggle hops
					var hop2 := absf(sin(_clock * 10.0))
					lift = hop2 * 0.25
					arm_l = -2.8
					arm_r = -2.8
					head_roll = sin(_clock * 10.0) * 0.25
		S.DIZZY, S.SIT:
			# Sat down on the grass, wobbling, stars round the head.
			lift = -0.16
			pitch = -0.32
			leg_l = -1.35
			leg_r = -1.25
			arm_l = -0.25
			arm_r = -0.25
			arm_side = 0.55
			head_roll = sin(_clock * 4.0) * 0.3
			head_pitch = cos(_clock * 4.0) * 0.2
			roll = sin(_clock * 4.0) * 0.08
			ear = sin(_clock * 4.0) * 0.4
		S.COWER:
			lift = absf(sin(_clock * 18.0)) * 0.03
			arm_l = -2.2
			arm_r = -2.2
			arm_side = -0.2
			pitch = 0.2
			head_pitch = 0.2
		S.LIFTED:
			leg_l = sin(_clock * 16.0) * 0.6
			leg_r = -leg_l
			arm_l = -2.8 + sin(_clock * 16.0) * 0.3
			arm_r = -2.8 - sin(_clock * 16.0) * 0.3
			ear_back = 0.6

	var tumble_basis := Basis()
	if state == S.TUMBLE:
		tumble_basis = Basis(_spin_axis, _spin)
		arm_l = -2.5
		arm_r = -2.0
		leg_l = 0.8
		leg_r = -0.5
	var s := Vector3(1.0 - sq * 0.5, 1.0 + sq, 1.0 - sq * 0.5) * SCALE * breath
	var vb := tumble_basis * Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.BACK, roll)
	var origin := Vector3.UP * lift
	if state == S.TUMBLE:
		# Spin about the belly, not the feet.
		origin = Vector3.UP * 0.5 * SCALE - vb * Vector3(0.0, 0.5 * SCALE, 0.0)
	_visual.transform = Transform3D(vb * Basis.from_scale(s), origin)

	_arm_l.rotation = Vector3(arm_l, 0.0, -arm_side)
	_arm_r.rotation = Vector3(arm_r, 0.0, arm_side)
	_leg_l.rotation = Vector3(leg_l, 0.0, 0.0)
	_leg_r.rotation = Vector3(leg_r, 0.0, 0.0)
	_head.rotation = Vector3(head_pitch, head_yaw, head_roll)
	_ear_l.rotation = Vector3(ear_back, 0.0, ear)
	_ear_r.rotation = Vector3(ear_back, 0.0, -ear)
	if _stars.visible:
		_stars.rotation.y = _clock * 4.5
		_stars.position = Vector3(0.0, 1.3 * SCALE + lift * 0.5, 0.0)


func _squash_kick(amount: float) -> void:
	_squash_v += amount * 9.0


func _face(dir: Vector3) -> void:
	var d := _flat(dir)
	if d.length() < 0.01:
		return
	var want := atan2(d.x, d.z)
	_yaw = lerp_angle(_yaw, want, 0.25)


func _toward(p: Vector3, speed: float) -> Vector3:
	var d := _flat(p - position)
	if d.length() < 0.2:
		return Vector3.ZERO
	return d.normalized() * minf(speed, d.length() * 3.0)


func _flat_dist(p: Vector3) -> float:
	return _flat(p - position).length()


func _hero_facing(hero: Node3D) -> Vector3:
	var f: Variant = hero.get("facing_dir")
	if f is Vector3:
		return _flat(f as Vector3).normalized()
	return Vector3.FORWARD


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


# --- Build (meshes cached per variant) --------------------------------------------------

func _build() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	_body = _part(_visual, "Body", _mesh_body(shirt), Vector3.ZERO)
	_head = Node3D.new()
	_head.name = "Head"
	_head.position = Vector3(0.0, 0.78, 0.0)
	_visual.add_child(_head)
	_head_mi = _part(_head, "HeadMesh", _mesh_head(skin), Vector3.ZERO)
	_ear_l = _part(_head, "EarL", _mesh_ear(skin, -1.0), Vector3(-0.24, 0.24, -0.02))
	_ear_r = _part(_head, "EarR", _mesh_ear(skin, 1.0), Vector3(0.24, 0.24, -0.02))
	_tongue = _part(_head, "Tongue", _mesh_tongue(), Vector3.ZERO)
	_arm_l = _part(_visual, "ArmL", _mesh_arm(skin), Vector3(-0.22, 0.7, 0.0))
	_arm_r = _part(_visual, "ArmR", _mesh_arm(skin), Vector3(0.22, 0.7, 0.0))
	_leg_l = _part(_visual, "LegL", _mesh_leg(skin), Vector3(-0.1, 0.34, 0.0))
	_leg_r = _part(_visual, "LegR", _mesh_leg(skin), Vector3(0.1, 0.34, 0.0))
	_socket = Node3D.new()
	_socket.name = "CupSocket"
	_socket.position = Vector3(0.0, 1.3, 0.05)
	_visual.add_child(_socket)
	_stars = MeshInstance3D.new()
	_stars.name = "DizzyStars"
	_stars.mesh = _mesh_stars()
	_stars.material_override = M.lit(1.0)
	_stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_stars)

	_hurtbox = Hurtbox.new()
	_hurtbox.name = "Hurtbox"
	_hurtbox.collision_layer = PhysicsLayers.TARGETS
	_hurtbox.collision_mask = 0
	_hurt_shape = CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = HURT_RADIUS
	cyl.height = 1.5
	_hurt_shape.shape = cyl
	_hurt_shape.position = Vector3(0.0, 0.7, 0.0)
	_hurtbox.add_child(_hurt_shape)
	add_child(_hurtbox)

	_poke = Hitbox.sphere(self, 0.55, Vector3(0.0, 0.6, 0.6), PhysicsLayers.PLAYERS, "Poke")
	_poke.damage = POKE_DAMAGE
	_poke.knockback = 3.5
	_poke.lift = 2.0
	_poke.prop_impulse = 0.0


func _part(parent: Node3D, n: String, mesh: Mesh, at: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = mesh
	mi.material_override = M.skin()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = at
	parent.add_child(mi)
	return mi


static func _cached(key: String, build: Callable) -> Mesh:
	if not _meshes.has(key):
		_meshes[key] = build.call()
	return _meshes[key]


static func _mesh_body(p_shirt: int) -> Mesh:
	return _cached("body%d" % p_shirt, func() -> Mesh:
		var b := VC.new()
		var shirt_fn := func(lp: Vector3) -> Color:
			if lp.y > 0.82:
				return WHITE   # collar
			if p_shirt == 0:
				return RED
			return HOOP_GREEN if int(floor((lp.y + 1.0) * 3.2)) % 2 == 0 else WHITE
		b.sphere_fn(Vector3(0, 0.56, 0), Vector3(0.23, 0.23, 0.2), Basis(), shirt_fn, 16, 14)
		var shorts := WHITE if p_shirt == 0 else Color(0.1, 0.1, 0.14)
		b.sphere(Vector3(0, 0.38, 0), Vector3(0.2, 0.12, 0.17), shorts)
		var sleeve := RED if p_shirt == 0 else HOOP_GREEN
		b.sphere(Vector3(-0.22, 0.69, 0), Vector3(0.085, 0.08, 0.085), sleeve, Basis(), 10, 6)
		b.sphere(Vector3(0.22, 0.69, 0), Vector3(0.085, 0.08, 0.085), sleeve, Basis(), 10, 6)
		return b.mesh())


static func _mesh_head(p_skin: int) -> Mesh:
	return _cached("head%d" % p_skin, func() -> Mesh:
		var sk: Color = SKINS[p_skin]
		var b := VC.new()
		b.sphere(Vector3(0, 0.2, 0), Vector3(0.28, 0.25, 0.25), sk, Basis(), 20, 14)
		b.sphere(Vector3(0, 0.06, 0.08), Vector3(0.2, 0.12, 0.17), sk, Basis(), 14, 8)   # jowl / chin
		for sx in [-1.0, 1.0]:
			b.sphere(Vector3(sx * 0.105, 0.24, 0.2), Vector3(0.1, 0.105, 0.085), WHITE, Basis(), 14, 10)
			b.sphere(Vector3(sx * 0.1, 0.23, 0.275), Vector3(0.056, 0.064, 0.03), Color(0.1, 0.07, 0.14), Basis(), 12, 8)
			b.sphere(Vector3(sx * 0.082, 0.26, 0.3), Vector3.ONE * 0.019, WHITE, Basis(), 6, 4)
			b.sphere(Vector3(sx * 0.17, 0.1, 0.19), Vector3(0.06, 0.04, 0.03), PINK, Basis(), 10, 6)
			b.box(Vector3(0.12, 0.028, 0.03), Transform3D(Basis(Vector3.BACK, sx * 0.38), Vector3(sx * 0.115, 0.36, 0.235)),
				sk.darkened(0.45))
		b.sphere(Vector3(0, 0.15, 0.27), Vector3(0.05, 0.048, 0.1), sk.darkened(0.1),
			Basis(Vector3.RIGHT, 0.35), 12, 8)
		# The cheeky grin: a dark smile curving up at the ends, no teeth.
		for k in 7:
			var t := -1.0 + 2.0 * float(k) / 6.0
			var gx := t * 0.11
			var gy := 0.035 + 0.04 * t * t
			var gz := 0.235 - 0.04 * t * t
			b.sphere(Vector3(gx, gy, gz), Vector3(0.026, 0.017, 0.016), Color(0.35, 0.06, 0.1), Basis(), 6, 4)
		# A tuft of hair.
		for k in 3:
			var a := -0.35 + 0.35 * float(k)
			b.cylinder(0.0, 0.045, 0.16, Transform3D(Basis(Vector3.BACK, a), Vector3(-a * 0.15, 0.48, -0.02)),
				sk.darkened(0.35), 6)
		return b.mesh())


static func _mesh_ear(p_skin: int, side: float) -> Mesh:
	return _cached("ear%d%d" % [p_skin, int(side)], func() -> Mesh:
		var sk: Color = SKINS[p_skin]
		var b := VC.new()
		# A long flat cone pointing out and a little up and back.
		var dir := Vector3(side * cos(0.32), sin(0.32), -0.15).normalized()
		var up := dir
		var fwd := Vector3.BACK
		var right := up.cross(fwd).normalized()
		fwd = right.cross(up).normalized()
		var basis := Basis(right, up, fwd)
		b.cylinder(0.0, 0.085, 0.46, Transform3D(basis * Basis.from_scale(Vector3(1, 1, 0.42)), dir * 0.21), sk, 10)
		b.cylinder(0.0, 0.05, 0.32, Transform3D(basis * Basis.from_scale(Vector3(1, 1, 0.3)), dir * 0.17 + Vector3(0, 0, 0.02)),
			PINK, 8)
		return b.mesh())


static func _mesh_arm(p_skin: int) -> Mesh:
	return _cached("arm%d" % p_skin, func() -> Mesh:
		var sk: Color = SKINS[p_skin]
		var b := VC.new()
		b.cylinder(0.04, 0.045, 0.28, Transform3D(Basis(), Vector3(0, -0.15, 0)), sk, 8)
		b.sphere(Vector3(0, -0.33, 0.01), Vector3(0.07, 0.065, 0.07), sk, Basis(), 10, 6)
		return b.mesh())


static func _mesh_leg(p_skin: int) -> Mesh:
	return _cached("leg%d" % p_skin, func() -> Mesh:
		var sk: Color = SKINS[p_skin]
		var b := VC.new()
		b.cylinder(0.05, 0.055, 0.24, Transform3D(Basis(), Vector3(0, -0.12, 0)), sk, 8)
		# Pointy shoe with a curled tip and a little bobble.
		b.sphere(Vector3(0, -0.28, 0.05), Vector3(0.085, 0.07, 0.15), SHOE, Basis(), 12, 8)
		b.cylinder(0.0, 0.06, 0.16, Transform3D(Basis(Vector3.RIGHT, 1.1), Vector3(0, -0.26, 0.2)), SHOE, 8)
		b.sphere(Vector3(0, -0.2, 0.26), Vector3.ONE * 0.035, Color(1.0, 0.85, 0.2), Basis(), 6, 4)
		return b.mesh())


static func _mesh_tongue() -> Mesh:
	return _cached("tongue", func() -> Mesh:
		var b := VC.new()
		b.sphere(Vector3(0, 0.03, 0.27), Vector3(0.06, 0.025, 0.08), Color(1.0, 0.4, 0.5), Basis(Vector3.RIGHT, 0.3), 10, 6)
		return b.mesh())


static func _mesh_stars() -> Mesh:
	return _cached("stars", func() -> Mesh:
		var b := VC.new()
		for k in 3:
			var a := TAU * float(k) / 3.0
			var p := Vector3(cos(a) * 0.34, 0.04 * float(k % 2), sin(a) * 0.34)
			b.star(0.085, 0.03, Transform3D(Basis(Vector3.UP, -a), p), Color(1.0, 0.88, 0.2))
		return b.mesh())
