extends CharacterBody3D
## Adamastor: the rocky stone-giant boss of the Dom Luís Bridge.
##
## Visual is a Meshy-generated, RIGGED + ANIMATED glTF giant (assets/models),
## towering ~5x over the human kids. Owns an AdamastorStateMachine "brain"; the
## FSM drives patrol + attacks, and we map FSM state -> a skeletal animation clip
## (walk / run / stomp / kick). Damage is routed through GameManager: this node
## REACTS to boss_damaged (flinch + white flash) and boss_phase_changed (red).
##
## This node owns the giant's BODY: his volumes, his push-out, who he is angry
## at and the ground marks his attacks draw. The FSM owns the TIMING.

## Fired the moment a ground mark is planted, carrying the mark's promise: the
## attack lands `lead` seconds from now. Node-local, like Hitbox.landed — the
## GameManager vocabulary is for cross-stream traffic, and both ends of this are
## the boss stream (the FSM emits it, `_boss_probe` measures against it).
signal attack_telegraphed(kind: StringName, lead: float)
## Fired on the frame an attack's damage actually resolves. The gap between this
## and the matching attack_telegraphed IS the honesty of the tell, and the probe
## fails the build when it drifts.
signal attack_impact(kind: StringName)
## Fired once, on the frame the beaten giant hits the Douro, with the point on
## the water where he went in. Node-local like the two above: the boss probe and
## the splash shot are the only listeners.
signal splashed(at: Vector3)

const GRAVITY := 30.0

## Per-attack damage does NOT scale with the roster, deliberately. How hard one
## blow lands is a property of the blow; how OFTEN blows come and how many heroes
## each one threatens is what a second hero changes, and that is derived in
## AdamastorStateMachine.reset(). A slam that hurt less because your partner was
## alive would make the pair weaker together than apart, which is the opposite of
## what a co-op game is for. The hero's 1.5 s of i-frames already gates the rate;
## these are the size of each bite.
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

# --- The slam's heavy volume ------------------------------------------------
## Radius and local offset of the slam's direct hit. Named constants rather than
## literals at the call site because the AOE telegraph is drawn FROM them: the
## mark and the hitbox are the same circle by construction, so they cannot drift
## apart the way a hand-copied radius would.
const SLAM_RADIUS := 5.2
const SLAM_OFFSET := Vector3(-4.2, 1.2, 0.0)
## Hit-stop when the slam catches a hero. The shorter freeze for the slam merely
## landing on granite is AdamastorStateMachine.SLAM_GROUND_STOP, next to the beat
## that requests it — both are impacts, only one of them is a hit.
const SLAM_HIT_STOP := 0.09
## The killing blow. A boss death is the biggest impact in the run and it gets
## the biggest freeze; the splash brings the second transient when he lands.
const DEATH_HIT_STOP := 0.16

# --- Push-out ---------------------------------------------------------------
## The giant's shove volume is his collider plus this much on X and Z.
const SHOVE_PAD := Vector3(1.4, 0.0, 1.4)
## How fast his body shunts a hero out of the space it is trying to occupy, in
## m/s. Comfortably above his own 9.6 m/s ceiling (AdamastorStateMachine.
## SPEED_CAP), so he can close on a hero and carry them along in front of him but
## can never pass through one.
const SHOVE_RATE := 14.0

# --- Aggro ------------------------------------------------------------------
## How far out of his way the giant will walk for the hero hurting him most, in
## metres of apparent distance. Under the 7 m melee range on purpose: enough that
## out-damaging your partner pulls the giant off them across the deck, never
## enough that he ignores the hero standing on his foot.
const THREAT_REACH := 5.0
## Combo length that counts as "all of the pressure". Six connected hits is a
## little over two seconds of an unbroken chain at the heroes' 0.45 s attack
## cooldown, so the chain term reads as "who is hitting me RIGHT NOW" while the
## score term reads as "who has hurt me most this fight".
const THREAT_COMBO_FULL := 6.0

# --- Death: over the parapet and into the Douro ------------------------------
## The book ends the fight "o Adamastor perdeu o equilíbrio e caiu de volta no rio
## Douro com um 'SPLASH' monumental!", so that is what the killing blow does: he
## staggers back, dizzy (never hurt), teeters on the rail, goes over it in a
## cartoon arc and vanishes into the river under a column of white water. There
## is no body: a felled giant lying on the deck reads, to a four-year-old, as a
## body lying there. Scripted rather than simulated, so the beat lands on time
## (the outro waits game_over.gd's POSE_WAIT, 2 s, then turns the page).
##
## The River plane in bridge_arena.tscn (river_life.gd WATER_Y).
const WATER_Y := -15.0
## Which parapet. Both overlook open water here: the boss arena (x -14..24) sits
## well inside the channel between the quay walls (river_life.gd CHANNEL_HALF,
## |x| < 44) and the River plane runs hundreds of metres past either rail. +Z is
## bridge_arena.gd's WRECK_HANG_SIDE, the side the signature deck view puts on
## the right of frame and the one with nothing modelled behind it, so it is the
## default; he goes over the -Z rail only when the blow clearly came from the +Z
## side, so he always falls AWAY from the punch.
const RIVER_SIDE := 1.0
## Where his shins catch the iron parapet: just inboard of bridge_arena.gd's
## WALKWAY_OUTER (6.55), a hair above its HANDRAIL_TOP (3.50) once he stands on
## the footway (WALKWAY_TOP 2.13). He pivots over the rail on that point.
const RAIL_Z := 6.4
const WALKWAY_Y := 2.13
const SHIN_HEIGHT := 1.5
## The beats, in seconds of game time after the killing blow (the 0.16 s
## hit-stop comes on top). Splash at 1.28 s, so its column is up before the
## outro turns the page.
const STAGGER_TIME := 0.36
const TEETER_TIME := 0.20
const TIP_TIME := 0.18
const FLIGHT_TIME := 0.54
const SINK_TIME := 0.50
## Over the rail he is lying back at this angle; he lands a little past flat, a
## back-flop, which is the biggest splash there is.
const TIP_ANGLE := deg_to_rad(95.0)
const LAND_ANGLE := deg_to_rad(112.0)
## The cartoon arc: how far out past the rail he travels and how high he pops
## before the drop. 5 m of pop carries his feet ~2 m over the handrail.
const FALL_OUT := 7.0
const FALL_HOP := 5.0
## How much deeper his centre goes after the splash before he is gone.
const SINK_DEPTH := 10.0
const SPLASH_SHAKE := 0.8
const SPLASH_SHAKE_TIME := 0.7
## "a beat later": the chapter's done-chime after the water.
const CHIME_BEAT := 0.35
## Kept for the wreck geometry sized against it (bridge_arena.gd GIANT_HALF_WIDTH,
## _wreck_probe.gd): what the model actually occupies, standing.
const CORPSE_SIZE := Vector3(2.8, 8.6, 2.4)
## Dizzy stars over his head while he staggers.
const STAR_COUNT := 5
const STAR_RING := 1.7
const STAR_HEIGHT := 9.4

enum Fall { NONE, STAGGER, TEETER, TIP, FLIGHT, SINK, GONE }

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
# The fall into the river (see the Death constants).
var _fall: Fall = Fall.NONE
var _fall_t: float = 0.0
var _fall_side: float = RIVER_SIDE
var _fall_from := Vector3.ZERO
var _fall_rail := Vector3.ZERO
var _fall_yaw0: float = 0.0
var _fall_yaw1: float = 0.0
var _fall_centre := Vector3.ZERO
var _fall_since_splash: float = -1.0
var _chimed: bool = false
var _stars: MultiMeshInstance3D = null
var _star_t: float = 0.0
var _nudge: Vector3 = Vector3.ZERO
## Whole-body squash and stretch, used by the phase-two roar. Held separately
## from the attack tween so killing one never leaves the giant the wrong shape.
var _pose_tween: Tween = null

# Hitboxes replacing the old distance checks. See _build_hitboxes().
var _prop_box: Hitbox = null
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
	# _shove_players() pushes out anyone who ends up inside anyway (knocked in,
	# spawned in, or squeezed against a rail). Props are handled the same way — a
	# 45 kg barrel is hurled aside, never an obstacle.
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
	if _fall != Fall.NONE:
		_tick_fall(delta)
		return

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
	# After his own move, so the shunt is solved against where he actually ended
	# up this frame rather than where he intended to be.
	if active:
		_shove_players(delta)
	_update_animation()


# --- Hitboxes ---------------------------------------------------------------

## Two shape-cast volumes plus a hand-rolled push-out replace the giant's old
## `distance_to() < 5.0` test and the state machine's ad-hoc checks.
##
## Local -X is the giant's forward: face_toward() solves yaw so that the body's
## -X axis points at the target (see the note on that function), so the slam
## volume sits at negative X.
func _build_hitboxes() -> void:
	# Prop sweep. Slightly proud of the CharacterBody3D box so a barrel pressed
	# against the giant registers as inside it. damage 0 means "shove, don't
	# hurt", and props caught under the giant's feet are hurled away hard enough
	# to shatter.
	#
	# PLAYERS is deliberately NOT in this mask any more. It used to be, and the
	# Hitbox's fire-and-forget impulse was the wrong tool for a persistent
	# contact: see _shove_players() for the measurement and the fix.
	_prop_box = Hitbox.box(self, BODY_SIZE + SHOVE_PAD,
		Vector3(0.0, BODY_CENTRE_Y, 0.0), PhysicsLayers.PROPS, "PropSweepVolume")
	_prop_box.damage = 0
	# knockback/lift only pick the DIRECTION here — the prop branch normalises and
	# scales by prop_impulse — so lift 0 keeps barrels skidding rather than popping.
	_prop_box.knockback = 9.0
	_prop_box.lift = 0.0
	_prop_box.prop_impulse = 26.0
	_prop_box.rehit_delay = 0.22

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
	_slam_box = Hitbox.sphere(self, SLAM_RADIUS, SLAM_OFFSET,
		PhysicsLayers.PLAYERS | PhysicsLayers.PROPS, "SlamVolume")
	_slam_box.damage = SLAM_DAMAGE
	_slam_box.knockback = 16.0
	_slam_box.lift = 7.0
	_slam_box.prop_impulse = 45.0
	_slam_box.landed.connect(_on_slam_landed)


func _sync_hitboxes(active: bool) -> void:
	if _prop_box == null:
		return
	if active == _prop_box.is_armed():
		return
	if active:
		_prop_box.arm()
		_contact_box.arm()
	else:
		_prop_box.disarm()
		_contact_box.disarm()
		_slam_box.disarm()
		# A mark that outlives the attack it was promising is worse than no mark,
		# so the run ending (or the giant dying) takes them off the deck.
		if _fsm:
			_fsm.cancel_telegraphs()


## Open the slam's active-frames window. Driven by the FSM at the impact beat
## rather than by a timer, so the window is exactly the animation's.
func arm_slam(duration: float = 0.16) -> void:
	if _slam_box == null:
		return
	_slam_box.damage = int(round(SLAM_DAMAGE * (PHASE2_DAMAGE_MULT if _phase2 else 1.0)))
	_slam_box.arm(duration)


## The heavy half of the slam's impact contract. Hitbox only emits `landed` once
## the hit was actually DELIVERED — a swing swallowed by a hero's i-frames never
## reaches here — so the frame never freezes for a hit that did not happen.
func _on_slam_landed(target: Node3D) -> void:
	if target == null or not target.is_in_group("players"):
		return
	# No hit_stop here any more, and it is worth saying why rather than leaving a
	# reader to wonder where the slam's freeze went. Hitbox._deliver() calls the
	# hero's take_hit() BEFORE it emits `landed`, take_hit now freezes in
	# proportion to damage, and GameManager.hit_stop refuses to nest — so by the
	# time this runs the frame is already stopped and this call returned
	# immediately. The freeze still happens; it is just owned by the hero, which
	# is the only place that knows how hard the hit actually landed.
	# PlayerBase.HURT_STOP_PER_DAMAGE x SLAM_DAMAGE reproduces SLAM_HIT_STOP
	# exactly, and _coop_probe asserts that equality so the two cannot drift.
	GameManager.request_shake(0.85, 0.35)


# --- Push-out ---------------------------------------------------------------

## Keep heroes out of the space the giant's body occupies.
##
## This replaces a Hitbox that handed every overlapping hero a 9 m/s IMPULSE
## every 0.22 s. PlayerBase.apply_knockback accumulates into a reservoir that
## decays at 14 m/s^2, so 9 m/s arriving five times a second gave back only
## 3.1 m/s to decay in between: the shove ratcheted. The co-op stream measured a
## chased hero leaving the giant at about 6.5 m, past the 3.7 / 4.0 m reach of
## both heroes' melee, which made being chased unrecoverable rather than merely
## dangerous.
##
## The root cause is that a persistent contact was being expressed as repeated
## impulses, so the fix is to stop expressing it that way. This is a POSITIONAL
## shunt: a hero whose centre is inside the volume is moved out along its
## shortest exit, by at most SHOVE_RATE * delta a frame. Three consequences, and
## they are the whole argument for doing it this way:
##
##   * It cannot accumulate. There is no momentum to accumulate INTO — the hero
##     is displaced, not launched — so however long you stand under him the state
##     is the same, and the frame you step clear the push is simply gone.
##   * It costs no reach. The furthest the shunt can ever leave a hero is the
##     volume's own half-extent (3.2 m front, 2.7 m side); with the hero's
##     capsule that is 3.65 m from his origin, and both heroes' swing volumes
##     reach his collider face from 5.7 m (Super Boxy) and 6.0 m (Herosauro).
##     Being stood on is now a position you can hit back from.
##   * The giant still cannot walk THROUGH a hero, because SHOVE_RATE is well
##     over his own top speed. Standing in his path costs you ground for as long
##     as you stay there, which is the bulldozed read the old shove was for.
##
## Two things were tried before this and are recorded so they are not tried
## again. A per-frame VELOCITY governor (top the hero's outward speed up to a
## target) ratchets, because apply_knockback lands in a reservoir that does not
## fold into `velocity` for about 0.11 s — the governor cannot see its own last
## frame and injects again, measured at 28 m/s. Modelling that reservoir in a
## ledger of our own does not fix it either: PlayerBase decays the reservoir as
## one vector, so our share of it shrinks by less than our ledger's when anything
## else has contributed, and the error compounds — measured at 22 m/s and still
## climbing.
##
## What a hero feels as a HIT still comes from _contact_box, which is
## deliberately tighter: real damage, real knockback, i-frames and the whole
## impact contract. This only decides where bodies can be.
func _shove_players(delta: float) -> void:
	var half := (BODY_SIZE + SHOVE_PAD) * 0.5
	var inv := global_transform.affine_inverse()
	var step := SHOVE_RATE * delta
	for p in get_tree().get_nodes_in_group("players"):
		var hero := p as Node3D
		if hero == null:
			continue

		var local := inv * hero.global_position
		# Vertical gate. The hero's origin sits at their feet, so this asks "on
		# the same deck as him", not "inside a 9 m box" — a hero on top of the
		# giant's head is not being stood on.
		if local.y < -1.0 or local.y > BODY_SIZE.y:
			continue
		var dx := half.x - absf(local.x)
		var dz := half.z - absf(local.z)
		if dx <= 0.0 or dz <= 0.0:
			continue

		# Shortest way out, solved in the giant's own frame so the push follows
		# his facing through a turn.
		var out_local := Vector3.ZERO
		var depth := 0.0
		if dx < dz:
			out_local.x = 1.0 if local.x >= 0.0 else -1.0
			depth = dx
		else:
			out_local.z = 1.0 if local.z >= 0.0 else -1.0
			depth = dz

		var dir := global_transform.basis * out_local
		dir.y = 0.0
		if dir.length() < 0.01:
			continue
		# Rate-limited rather than snapped to the surface: at 90 Hz this is 16 cm
		# a frame, which reads as being shouldered aside instead of teleporting.
		# Downed heroes included — a body in his path gets shunted too, and being
		# positional this is the one push that works on one (PlayerBase drives a
		# downed hero's velocity to zero every frame, so an impulse would be
		# dropped on the floor).
		hero.global_position += dir.normalized() * minf(depth, step)


# --- Animation -------------------------------------------------------------

func _update_animation() -> void:
	if _dead or _anim == null:
		return
	var want := _clip_run if _phase2 else _clip_walk
	if _fsm:
		if _fsm.state == AdamastorStateMachine.SLAM or _fsm.state == AdamastorStateMachine.ROAR:
			want = _clip_stomp
		elif _fsm.state == AdamastorStateMachine.ROCK_THROW:
			want = _clip_kick
	if want != "" and want != _cur_clip:
		_cur_clip = want
		_anim.play(want)


# --- Public API (used by the state machine / Super Boxy) -------------------

## True while the giant is committed to a heavy move (lets the camera ease out to
## reveal the telegraph / AoE).
func is_attacking() -> bool:
	if _fsm == null:
		return false
	return _fsm.state == AdamastorStateMachine.SLAM \
		or _fsm.state == AdamastorStateMachine.ROCK_THROW \
		or _fsm.state == AdamastorStateMachine.ROAR


## Closest hero who can still be fought. A hero at zero health is in a ~4 s
## knockdown but STAYS in the `players` group deliberately, because
## GameManager._all_heroes_down() works off the scene; without this test the
## giant spent the whole knockdown attacking a body that refuses damage while the
## partner hit him for free. `include_downed` exists for the one caller that
## wants a body rather than an opponent — the death topple, which only needs a
## direction to fall in.
func nearest_player(include_downed: bool = false) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for p in get_tree().get_nodes_in_group("players"):
		var body := p as Node3D
		if body == null:
			continue
		if not include_downed and body.has_method("is_downed") and body.is_downed():
			continue
		var d := global_position.distance_to(body.global_position)
		if d < best_d:
			best_d = d
			best = body
	return best


## Who the giant attacks. Distance still decides most of it, pulled by up to
## THREAT_REACH metres toward whoever is hurting him most.
##
## Against one hero this is exactly nearest_player(): the pull is a constant
## added to every candidate's score, so with a single candidate it cannot change
## the answer. Against two it is the whole co-op fight — the giant turning on the
## hero who out-damages their partner is what stops one of them farming him from
## behind while the other tanks, and it makes threat something the pair trade
## deliberately rather than a coin flip on who stood closer.
func target_player() -> Node3D:
	var best: Node3D = null
	var best_score := INF
	for p in get_tree().get_nodes_in_group("players"):
		var body := p as Node3D
		if body == null:
			continue
		if body.has_method("is_downed") and body.is_downed():
			continue
		var pid := 1
		if "player_id" in body:
			pid = int(body.player_id)
		var score := global_position.distance_to(body.global_position) \
			- THREAT_REACH * _threat_of(pid)
		if score < best_score:
			best_score = score
			best = body
	return best


## 0 = has not touched him, 1 = doing all of the damage on an unbroken chain.
## Half the weight on the fight-long split (GameManager.player_score) and half on
## the live chain (combo_for), so he remembers who has hurt him AND notices who
## is hurting him this second.
func _threat_of(pid: int) -> float:
	var roster: Array[int] = GameManager.active_player_ids()
	var total := 0.0
	for id in roster:
		total += float(GameManager.player_score.get(id, 0))
	var share := 1.0 / float(maxi(1, roster.size()))
	if total > 0.0:
		share = float(GameManager.player_score.get(pid, 0)) / total
	var chain: float = clampf(float(GameManager.combo_for(pid)) / THREAT_COMBO_FULL, 0.0, 1.0)
	return 0.5 * share + 0.5 * chain


## The slam's heavy volume, so the FSM can draw its ground mark on exactly the
## circle the hitbox will use instead of on a copy of the number.
func slam_radius() -> float:
	return SLAM_RADIUS


func slam_offset() -> Vector3:
	return SLAM_OFFSET


## Re-emitted by the FSM. Kept as methods rather than the FSM touching the
## signals directly so the boss node stays the only thing that speaks for itself.
func report_telegraph(kind: StringName, lead: float) -> void:
	attack_telegraphed.emit(kind, lead)


func report_impact(kind: StringName) -> void:
	attack_impact.emit(kind)


## What the FSM actually derived this run, for `_boss_probe`. Tuning that cannot
## be read cannot be regression-tested, and every number in here is a function of
## the difficulty and the roster.
func tuning() -> Dictionary:
	if _fsm == null:
		return {}
	return _fsm.tuning()


func bob_arms(_amount: float) -> void:
	pass


func raise_arms(_up: bool) -> void:
	pass


func slam_arms_down() -> void:
	pass


## Anticipation for the phase-two roar: the giant coils down over the whole
## wind-up. Volume is roughly conserved (the horizontals take half the vertical
## change, the other way), which is what makes it read as a body compressing
## rather than as a mesh being scaled — the same rule PlayerBase uses.
func roar_coil(duration: float) -> void:
	if _model == null:
		return
	_kill_pose_tween()
	_pose_tween = create_tween()
	_pose_tween.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_pose_tween.tween_property(_model, "scale", Vector3(1.11, 0.82, 1.11), duration)


## ...and the release: he snaps taller than he started, then settles.
func roar_release() -> void:
	if _model == null:
		return
	_kill_pose_tween()
	_pose_tween = create_tween()
	_pose_tween.tween_property(_model, "scale", Vector3(0.88, 1.22, 0.88), 0.06)
	_pose_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
	_pose_tween.tween_property(_model, "scale", Vector3.ONE, 0.55)


func _kill_pose_tween() -> void:
	if _pose_tween and _pose_tween.is_valid():
		_pose_tween.kill()
	_pose_tween = null


func nudge(world_dir: Vector3, amount: float) -> void:
	var d := world_dir
	d.y = 0.0
	if d.length() < 0.01:
		return
	_nudge += d.normalized() * amount * 6.0


func reset_boss() -> void:
	_dead = false
	_fall = Fall.NONE
	_fall_since_splash = -1.0
	visible = true
	if _stars:
		_stars.visible = false
	collision_layer = PhysicsLayers.BOSS   # a previous _die() zeroed both
	collision_mask = PhysicsLayers.WORLD
	global_position = SPAWN
	rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	_nudge = Vector3.ZERO
	_kill_pose_tween()
	if _model:
		_model.position = Vector3.ZERO
		_model.rotation = Vector3.ZERO
		_model.scale = Vector3.ONE     # a roar, or a dizzy wobble, left him squashed
		_model.visible = true
	if _anim:
		_anim.active = true
	if _contact_box:
		# Difficulty rides the giant's damage as well as his speed, so EASY is
		# genuinely gentler rather than merely slower.
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


## Beaten: stagger back, lose his balance over the rail, fall into the Douro.
## See the Death constants for the beats and for why there is no corpse.
func _die() -> void:
	_dead = true
	if _fsm:
		_fsm.stop()
	# The camera and the freeze for the last hit of the fight; the splash brings
	# the second punctuation and GameManager.game_over drives the UI.
	GameManager.request_shake(0.5, 0.5)
	GameManager.hit_stop(DEATH_HIT_STOP)
	# Nothing on him can touch a hero from here on: no layer (heroes stop
	# colliding with him), no mask (he moves by script, not by the solver), every
	# hitbox disarmed, and _physics_process never reaches _shove_players again.
	collision_layer = 0
	collision_mask = 0
	_sync_hitboxes(false)
	_kill_pose_tween()
	velocity = Vector3.ZERO
	_nudge = Vector3.ZERO

	# Backwards is away from whoever landed the killing blow. A downed hero
	# cannot have thrown it, so a standing hero is preferred.
	var away := Vector3.RIGHT
	var killer := nearest_player()
	if killer == null:
		killer = nearest_player(true)
	if killer:
		var to := global_position - killer.global_position
		to.y = 0.0
		if to.length() > 0.01:
			away = to.normalized()
	_fall_side = RIVER_SIDE
	if absf(away.z) > 0.35:
		_fall_side = signf(away.z)

	_fall_from = global_position
	_fall_rail = Vector3(
		clampf(global_position.x + away.x * 2.5, ARENA_X_MIN, ARENA_X_MAX),
		WALKWAY_Y + SHIN_HEIGHT, _fall_side * RAIL_Z)
	# Back to the river, face to the heroes: the model faces -X at yaw 0 and
	# face_toward()'s atan2(dir.z, -dir.x) aims it along dir = (0, 0, -side).
	_fall_yaw0 = rotation.y
	_fall_yaw1 = atan2(-_fall_side, 0.0)
	_fall = Fall.STAGGER
	_fall_t = 0.0
	_fall_since_splash = -1.0
	_chimed = false
	if _anim and _clip_walk != "":
		# His own walk, run backwards and quick: the stumbling steps of a dizzy
		# giant backing into the rail.
		_anim.active = true
		_anim.play(_clip_walk, 0.15, -1.35)
	_show_stars()


## Which parapet the beaten giant goes over: +1 (+Z) or -1 (-Z).
func fall_side() -> float:
	return _fall_side


func is_falling() -> bool:
	return _fall != Fall.NONE and _fall != Fall.GONE


func _tick_fall(delta: float) -> void:
	_fall_t += delta
	var side := _fall_side
	var yaw := _fall_yaw1
	match _fall:
		Fall.STAGGER:
			var u := clampf(_fall_t / STAGGER_TIME, 0.0, 1.0)
			var e := u * u * (3.0 - 2.0 * u)
			var origin := _fall_from.lerp(_fall_rail - Vector3(0.0, SHIN_HEIGHT, 0.0), e)
			# Three stumbling steps.
			origin.y += 0.35 * absf(sin(3.0 * PI * u))
			yaw = lerp_angle(_fall_yaw0, _fall_yaw1, minf(1.0, u * 1.6))
			var sway := 0.20 * sin(TAU * 2.4 * _fall_t) * (0.4 + 0.6 * u)
			_wobble(_fall_t, 1.0)
			_set_pose(origin, yaw, 0.0, sway)
			if u >= 1.0:
				_next_beat(Fall.TEETER)
		Fall.TEETER:
			# Rocking on the rail: back, forward, further back...
			var u := clampf(_fall_t / TEETER_TIME, 0.0, 1.0)
			var tilt := 0.42 * u + 0.18 * sin(TAU * u)
			var sway := 0.20 * sin(TAU * 2.4 * (_fall_t + STAGGER_TIME))
			_wobble(_fall_t + STAGGER_TIME, 1.4)
			_set_pose(_over_rail(tilt, side, yaw, sway), yaw, side * tilt, sway)
			if u >= 1.0:
				_next_beat(Fall.TIP)
		Fall.TIP:
			# ...and over: accelerating, pivoting on his shins at the handrail.
			var u := clampf(_fall_t / TIP_TIME, 0.0, 1.0)
			var tilt := lerpf(0.42, TIP_ANGLE, u * u)
			var sway := 0.20 * sin(TAU * 2.4 * (_fall_t + STAGGER_TIME + TEETER_TIME)) * (1.0 - u)
			_wobble(_fall_t + STAGGER_TIME + TEETER_TIME, 1.8)
			_set_pose(_over_rail(tilt, side, yaw, sway), yaw, side * tilt, sway)
			if u >= 1.0:
				_fall_centre = global_transform * Vector3(0.0, BODY_CENTRE_Y, 0.0)
				if _anim:
					_anim.pause()
				if _stars:
					_stars.visible = false
				_next_beat(Fall.FLIGHT)
		Fall.FLIGHT:
			# Out and up off the rail, then down into the Douro: fast out, a
			# little cartoon pop, and the plunge, inside the time the beat has.
			var u := clampf(_fall_t / FLIGHT_TIME, 0.0, 1.0)
			var tilt := lerpf(TIP_ANGLE, LAND_ANGLE, u)
			var drop := _fall_centre.y - (WATER_Y + 0.5)
			var c := _fall_centre
			c.z += side * FALL_OUT * (1.0 - (1.0 - u) * (1.0 - u))
			c.y += FALL_HOP * sin(PI * u) - drop * u * u
			_wobble(_fall_t, 2.2)
			_set_pose(_centred_at(c, yaw, side * tilt), yaw, side * tilt, 0.0)
			if u >= 1.0:
				_fall_centre = c
				_splash(c)
				_next_beat(Fall.SINK)
		Fall.SINK:
			var u := clampf(_fall_t / SINK_TIME, 0.0, 1.0)
			var tilt := lerpf(LAND_ANGLE, LAND_ANGLE + 0.35, u)
			var c := _fall_centre + Vector3.DOWN * SINK_DEPTH * u * u
			_set_pose(_centred_at(c, yaw, side * tilt), yaw, side * tilt, 0.0)
			if u >= 1.0:
				# Under the water and gone: no body anywhere.
				visible = false
				_next_beat(Fall.GONE)
		Fall.GONE:
			pass
	_spin_stars(delta)
	if _fall_since_splash >= 0.0:
		_fall_since_splash += delta
		if not _chimed and _fall_since_splash >= CHIME_BEAT:
			_chimed = true
			AudioManager.play_sfx(&"objective_done")


func _next_beat(beat: Fall) -> void:
	_fall = beat
	_fall_t = 0.0


## Feet such that his shin sits on the rail point while he leans `tilt` back.
func _over_rail(tilt: float, side: float, yaw: float, sway: float) -> Vector3:
	return _fall_rail - _fall_basis(yaw, side * tilt, sway) * Vector3(0.0, SHIN_HEIGHT, 0.0)


## Feet such that his body centre is at `centre`.
func _centred_at(centre: Vector3, yaw: float, lean: float) -> Vector3:
	return centre - _fall_basis(yaw, lean, 0.0) * Vector3(0.0, BODY_CENTRE_Y, 0.0)


## Lean is about world X (positive tips the head toward +Z, out over the +Z
## rail), sway about world Z (a dizzy side-to-side roll), both on top of yaw.
static func _fall_basis(yaw: float, lean: float, sway: float) -> Basis:
	return Basis(Vector3.RIGHT, lean) * Basis(Vector3.BACK, sway) * Basis(Vector3.UP, yaw)


func _set_pose(origin: Vector3, yaw: float, lean: float, sway: float) -> void:
	global_transform = Transform3D(_fall_basis(yaw, lean, sway), origin)


## Squash and stretch: a dazed, rubbery wobble, nothing that looks like pain.
func _wobble(t: float, rate: float) -> void:
	if _model == null:
		return
	var w := sin(TAU * 1.8 * rate * t)
	_model.scale = Vector3(1.0 + 0.06 * w, 1.0 - 0.06 * w, 1.0 + 0.06 * w)


func _splash(centre: Vector3) -> void:
	var at := Vector3(centre.x, WATER_Y, centre.z)
	WaterSplash.spawn(self, at, 1.0)
	AudioManager.play_splash(at)
	GameManager.request_shake(SPLASH_SHAKE, SPLASH_SHAKE_TIME)
	_fall_since_splash = 0.0
	splashed.emit(at)


# --- Dizzy stars ----------------------------------------------------------------

## A ring of little gold stars over his head while he staggers: the cartoon sign
## for "dizzy". One MultiMesh draw call, built on the first death and reused.
func _show_stars() -> void:
	if _stars == null:
		var mesh := SphereMesh.new()
		mesh.radius = 0.32
		mesh.height = 0.64
		mesh.radial_segments = 8
		mesh.rings = 4
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = STAR_COUNT
		_stars = MultiMeshInstance3D.new()
		_stars.name = "DizzyStars"
		_stars.multimesh = mm
		# Cached and shared; never mutated here.
		_stars.material_override = ToonFactory.glow(Color(1.0, 0.85, 0.25), 1.6)
		_stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_stars.custom_aabb = AABB(Vector3(-3.0, -1.0, -3.0), Vector3(6.0, 2.0, 6.0))
		_stars.position = Vector3(0.0, STAR_HEIGHT, 0.0)
		add_child(_stars)
	_star_t = 0.0
	_stars.visible = true
	_spin_stars(0.0)


func _spin_stars(delta: float) -> void:
	if _stars == null or not _stars.visible:
		return
	_star_t += delta
	var mm := _stars.multimesh
	for i in STAR_COUNT:
		var a := TAU * float(i) / float(STAR_COUNT) + _star_t * 5.0
		var p := Vector3(cos(a) * STAR_RING, 0.25 * sin(a * 2.0 + _star_t * 3.0), sin(a) * STAR_RING)
		var k := 0.8 + 0.25 * sin(_star_t * 9.0 + float(i))
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * k), p))


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
