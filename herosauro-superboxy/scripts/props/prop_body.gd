class_name PropBody
extends RigidBody3D
## Base for the arena's interactive props: port-wine barrels, crates, loose
## masonry. Real Jolt rigid bodies the heroes and the giant can knock around.
##
## Six things it takes care of that a bare RigidBody3D does not:
##
##  * Layering. Props sit on their own layer and mask WORLD | PROPS | PLAYERS.
##    They deliberately do NOT mask BOSS: a 45 kg barrel must never body-block a
##    nine-metre giant. The boss shoves and shatters them from its own hitbox.
##  * Sleeping. can_sleep plus a little damping so a settled prop leaves the
##    solver entirely and an untouched arena costs nothing.
##  * A kicker volume. CharacterBody3D.move_and_slide() does not push rigid
##    bodies — the engine only depenetrates them, which reads as a barrel
##    quivering rather than rolling. The kicker converts the toucher's approach
##    speed into a real force, so props respond without the player controller
##    (owned by another stream) needing to know props exist. It self-disables
##    the moment nothing is touching.
##  * Its own LOOK. Geometry comes from PropMeshKit at the collision shape's own
##    dimensions, and every instance gets a seeded size and tint variant. The
##    RUBRIC asks for "per-instance rotation and scale variation on everything
##    placed more than twice", and fourteen identical primitives in three
##    colours is the visible repetition it fails a frame for.
##  * The impact contract for a prop that does NOT break: FX at the contact
##    point, a camera response, an audio transient. See _impact_response().
##    BreakableProp adds hit-stop and the UI acknowledgement on the frame it
##    bursts, because those two mean "something important happened" and a
##    glancing shove is not that.
##  * ARRIVAL. A prop that lands hard kicks dust off the deck and thumps, which
##    is leg one and leg three of the same contract applied to gravity rather
##    than to a hero. See _on_deck_impact().
##
## --- What a prop knows about the giant --------------------------------------
##
## Nothing directly, and that is deliberate — the boss masks WORLD only, so props
## are shoved by his explicit hitboxes and never by his collider. What a prop
## DOES get is the deck ringing under a heavy impact: see _on_world_shake(). It
## rides `camera_shake_requested`, the project's existing "something heavy just
## happened" vocabulary, so it needs no new signal and no reach into another
## stream's script.

## Which ToonFactory surface the prop wears. Meshes in the "prop_trim" group get
## `trim_color` iron instead, which is how a barrel gets its hoops.
## ImpactFX.surface_of() reads this property by name, so the strings here are
## shared vocabulary and not free to rename.
@export_enum("wood", "stone", "iron", "cobble") var surface: String = "wood"
## Which PropMeshKit body this prop is built from. "plain" leaves whatever
## MeshInstance3D the scene authored alone.
@export_enum("crate", "barrel", "rubble", "plain") var body_kind: String = "plain"
@export var tint: Color = Color(0.36, 0.24, 0.14)
@export var trim_color: Color = Color(0.26, 0.27, 0.30)

@export_group("Physics")
@export var prop_mass: float = 40.0
@export var prop_friction: float = 0.85
@export var prop_bounce: float = 0.05
## Scales how hard a walking character shoves this prop. 0 disables the kicker.
@export var kick_strength: float = 1.0

@export_group("Variation")
## Non-zero pins this instance's size, tint and mesh variant.
##
## Must be set BEFORE the prop enters the tree — _ready() reads it to decide what
## to build. The spawner does. Left at 0 it derives one from the prop's resting
## position, which is right for a hand-placed prop in a .tscn and wrong for one
## positioned after add_child(); either way it is never left to chance, per
## ARCHITECTURE.md rule 4.
@export var variant_seed: int = 0
## Half-width of the per-instance size jitter. 0.11 reads as "these were made by
## hand" at 5 m without any prop looking like a different object.
@export var size_variation: float = 0.11

## Anything that falls off the bridge is gone; the Douro surface is at y = -15
## and has no collider, so without this they fall forever.
const CULL_Y := -6.0
## Extra reach on the kicker volume, roughly a hero's capsule radius.
const KICK_MARGIN := 0.45
## Acceleration (m/s^2) applied per m/s of approach speed. Self-limiting: once
## the prop matches the pusher, approach hits zero and the force stops.
const KICK_GAIN := 4.5
const KICK_MAX_APPROACH := 9.0

## How many distinct tint/mesh variants exist per prop type. ToonFactory caches
## materials by parameter set, so this is literally the number of extra cached
## materials the variation costs: four, not fourteen.
const VARIANTS := 4

# --- Arrival -----------------------------------------------------------------

## What the bridge deck is made of, for the dust a landing prop kicks up. The
## roadway between the kerbs is calçada; bridge_arena.gd owns the actual surface
## and this is the props stream's copy of that one fact.
const DECK_SURFACE := ToonFactory.Surface.COBBLE
## Speed (m/s) that must vanish in one physics frame to count as a hard landing.
## prop_spawner.gd's SETTLE_DROP puts the arrival speed of every prop in the
## arena at 2.7-4.0 m/s, so 5.0 means the arena settling at the start of a fight
## never spends a single one of ImpactFX's ten burst slots.
const LAND_MIN_DELTA_V := 5.0
## Seconds of being awake before the arrival and delta-v triggers are live at
## all — see _armed. Belt as well as braces against a prop detonating on the
## first frame of the fight.
const ARM_DELAY := 1.0

# --- Deck ring ---------------------------------------------------------------
# `camera_shake_requested` carries a strength but no epicentre, so this cannot be
# and does not pretend to be a positional shockwave — the boss's slam already has
# one of those (fx/shockwave.gd) and it hands props a real directional impulse.
# What this models is the OTHER half: a hundred metres of granite and wrought
# iron ringing, and everything loose on it hopping. That is a global event, which
# is exactly what a strength-only signal describes.

## Shake strength below which nothing hops. The ladder in the project today is
## hero jab 0.16, hero landing 0.10-0.35, rock impact 0.30, giant's slam
## 0.50-0.85, corpse landing 0.70, roar 0.95. 0.45 puts the cut cleanly between
## "a hero did something" and "nine metres of stone hit the deck".
const JOLT_MIN_SHAKE := 0.45
## Vertical speed (m/s) a prop standing right next to the giant picks up from a
## strength-1.0 event. A hop, not a launch: 1.2 m/s against gravity 30 is a 2.4 cm
## bounce, which is visible and cannot move a prop anywhere.
const JOLT_SPEED := 1.2
## Distance over which the ring falls off, and how much of it survives at the far
## end. It never reaches zero: the deck is one connected structure.
const JOLT_RANGE := 22.0
const JOLT_FAR_FRACTION := 0.35
## Minimum gap between hops. Without it a roar plus its own shockwave in the same
## frame pumps energy into every prop on the deck twice.
const JOLT_COOLDOWN := 0.18

## Seconds between a prop's own impact sounds. The giant's prop sweep re-hits
## every 0.22 s for as long as a barrel is under his feet, and one thud per
## re-hit is a machine gun.
const IMPACT_SOUND_COOLDOWN := 0.28

# --- Settling ----------------------------------------------------------------
# Measured, not assumed: dropped onto the deck and left completely alone, the
# fourteen props were still awake after six seconds at 0.10 m/s and 0.26 rad/s.
# That is a solver island per prop for the whole fight, and on screen it is a
# barrel very slightly vibrating on flat granite — the RUBRIC's "a still frame is
# a dead frame" does not mean this.
#
# Jolt's own sleep thresholds are tuned for a general-purpose scene and these
# props are heavy, high-friction and resting on a dead-flat plane, so rather than
# retune a global that every other body in the game shares, a prop decides for
# itself when it has arrived. Same pattern DebrisPiece uses, one size up.

## Speed and spin under which a prop is considered to have arrived.
const SETTLE_SPEED := 0.12
const SETTLE_SPIN := 0.40
## How long it has to be that quiet for. One frame of slowness is the apex of a
## bounce, not a rest; half a second is not.
const SETTLE_TIME := 0.5

var _kicker: Area3D = null
var _touching: Array[Node3D] = []
var _variant: int = 0
var _size_scale: float = 1.0
var _rng := RandomNumberGenerator.new()
var _jolt_cooldown: float = 0.0
var _sound_cooldown: float = 0.0
var _prev_vel: Vector3 = Vector3.ZERO
var _awake_for: float = 0.0
var _armed: bool = false
var _slow_for: float = 0.0


func _ready() -> void:
	add_to_group("props")
	collision_layer = PhysicsLayers.PROPS
	collision_mask = PhysicsLayers.WORLD | PhysicsLayers.PROPS | PhysicsLayers.PLAYERS

	_seed_variant()
	# Geometry FIRST, at the shape's authored size, and only then the collider is
	# resized. PropMeshKit caches on its arguments, so building at each prop's own
	# jittered size would mint one unique ArrayMesh per prop and give the renderer
	# nothing to share; built at the nominal size there are three body meshes and
	# two trim meshes in the whole arena, and the instance's size lives on the
	# MeshInstance3D's transform where it is free.
	_build_body()
	_apply_size_variation()
	_apply_visual_scale(_size_scale)

	mass = prop_mass * _size_scale * _size_scale * _size_scale
	var pm := PhysicsMaterial.new()
	pm.friction = prop_friction
	pm.bounce = prop_bounce
	physics_material_override = pm

	can_sleep = true
	# Props are slow and chunky; CCD is for the projectiles, not for these.
	continuous_cd = false
	# Enough damping that a shoved crate actually settles and sleeps instead of
	# creeping across the deck forever.
	linear_damp = 0.08
	angular_damp = 0.55

	_apply_materials()
	if kick_strength > 0.0:
		_build_kicker()

	GameManager.camera_shake_requested.connect(_on_world_shake)
	sleeping_state_changed.connect(_on_sleep_changed)
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if global_position.y < CULL_Y:
		queue_free()
		return
	_jolt_cooldown = maxf(0.0, _jolt_cooldown - delta)
	_sound_cooldown = maxf(0.0, _sound_cooldown - delta)

	if sleeping:
		# Whatever it was doing, it has arrived. Nothing to compare against next
		# time it wakes, and a settled prop is by definition armed.
		_prev_vel = Vector3.ZERO
		_slow_for = 0.0
		_armed = true
	else:
		_awake_for += delta
		if _awake_for >= ARM_DELAY:
			_armed = true
		_check_settled(delta)
		var vel := linear_velocity
		# _physics_process runs before the step is integrated, so linear_velocity
		# is the result of the PREVIOUS step: the frame after hitting something,
		# the whole impact shows up here as one big drop.
		var incoming := _prev_vel
		var dv := incoming.length() - vel.length()
		_prev_vel = vel
		if dv > 0.5:
			# `incoming` is the velocity it ARRIVED with, which is the direction a
			# shatter should throw the pieces — not the post-impact remnant.
			_on_deck_impact(dv, global_position, incoming)

	_apply_kicks()
	# Stay awake while a cooldown is still running down, or a prop that slept
	# immediately after a hit would keep a stale cooldown forever.
	if sleeping and _touching.is_empty() and _jolt_cooldown <= 0.0 and _sound_cooldown <= 0.0:
		set_physics_process(false)


# --- Shared vocabulary -------------------------------------------------------

## The prop's surface in the project's shared `ToonFactory.Surface` vocabulary.
## This is the key the fx stream's impact table and the audio stream's material
## tables are both looked up on — the string export above is an authoring
## convenience, not the contract.
func surface_kind() -> ToonFactory.Surface:
	return ImpactFX.surface_named(surface, ToonFactory.Surface.WOOD) as ToonFactory.Surface


## The prop's furniture, if it has any: the barrel's hoops, the crate's corner
## straps. `ImpactFX.TRIM_NONE` when the whole prop is one material.
func trim_kind() -> int:
	return ToonFactory.Surface.IRON if _has_trim() else ImpactFX.TRIM_NONE


## Which of the VARIANTS shapes/tints this instance drew. Public so the probe can
## check the spread rather than trusting that a seed was used.
func variant_index() -> int:
	return _variant


func size_scale() -> float:
	return _size_scale


## True once the prop has settled (or been awake for ARM_DELAY). Impact triggers
## that depend on a sudden loss of speed are inhibited until then, because being
## dropped onto the deck to settle IS a sudden loss of speed.
func is_armed() -> bool:
	return _armed


# --- Damage / impulse entry point -------------------------------------------

## The one way anything external moves a prop. `at_global` is where the blow
## landed, so an off-centre hit spins the prop.
func apply_hit_impulse(impulse: Vector3, at_global: Vector3 = Vector3.INF) -> void:
	sleeping = false
	set_physics_process(true)
	var offset := Vector3.ZERO
	var contact := global_position
	if at_global != Vector3.INF:
		# Clamp the lever arm: a contact reported a body-length away turns a
		# shove into a helicopter.
		offset = (at_global - global_position).limit_length(0.5)
		contact = global_position + offset
	apply_impulse(impulse, offset)
	_on_impact(impulse.length(), contact, impulse)


## Overridden by BreakableProp. `strength` is the impulse magnitude in N*s.
func _on_impact(strength: float, at: Vector3, impulse: Vector3) -> void:
	_impact_response(strength, at, impulse)


## Overridden by BreakableProp, which shatters above its own threshold.
## `dv` is the speed lost in one physics frame — how hard it hit something.
func _on_deck_impact(dv: float, at: Vector3, _incoming: Vector3) -> void:
	_land_response(dv, at)


## Legs 1-3 of the impact contract for a blow that does NOT destroy the prop:
## an FX at the contact point, a camera response, an audio transient. Hit-stop
## and the UI acknowledgement are deliberately not here — a barrel taking a
## glancing shove must not freeze the game or move the score, or the two legs
## that mean "something important happened" stop meaning anything.
func _impact_response(strength: float, at: Vector3, impulse: Vector3) -> void:
	if strength < 1.0:
		return
	# 30 N*s is the rock's impulse and about the middle of the ladder, so a hero's
	# 9 lands at 0.3 and the giant's slam saturates.
	var power := clampf(strength / 30.0, 0.12, 1.4)
	var into := impulse.normalized()
	if into.length() < 0.5:
		into = Vector3.DOWN
	# The spark is ungated: it is the point-of-contact FX and suppressing it is
	# what makes a hit feel dead. It costs nothing when there is nothing to spend,
	# because ImpactFX hands back null past its own budget.
	ImpactFX.spark(self, at, into, int(surface_kind()), power, _fx_seed())
	# The shake and the sound ARE gated, on the same cooldown and for the same
	# reason: the giant's prop sweep re-hits every 0.22 s for as long as a barrel
	# is under his feet, and five barrels under him is twenty-three shake requests
	# a second. That is not weight, it is a rumble with no edges on it.
	if _sound_cooldown > 0.0:
		return
	_sound_cooldown = IMPACT_SOUND_COOLDOWN
	# Small and proportional. A hero's own swing already asks for 0.16, so a prop
	# adding much on top of it would double-count the same blow.
	GameManager.request_shake(0.05 + 0.06 * power, 0.10)
	play_surface_hit()


## Legs 1-3 for a prop ARRIVING: dust off the deck, a thump, a whisper of shake.
## This is what stops a barrel punted across the bridge landing in silence, and
## it is deliberately gated hard so the fourteen props settling at the start of a
## fight never touch ImpactFX's ten-burst budget.
func _land_response(dv: float, at: Vector3) -> void:
	if not _armed or dv < LAND_MIN_DELTA_V or _sound_cooldown > 0.0:
		return
	_sound_cooldown = IMPACT_SOUND_COOLDOWN
	var power := clampf(dv / 9.0, 0.35, 1.3)
	# The burst belongs on the deck under the prop, not at its centre of mass.
	var ground := at - Vector3(0.0, extent() * 0.85, 0.0)
	ImpactFX.ground(self, ground, int(DECK_SURFACE), extent() * 2.4, power, _fx_seed())
	AudioManager.play_land()
	GameManager.request_shake(0.04 + 0.05 * power, 0.10)


## Put the prop to sleep once it has genuinely stopped. See the SETTLE_ block
## above for the measurement that made this necessary.
##
## Never while something is standing against it: the kicker holds a reference to
## whoever is touching, and apply_force() on a sleeping body does nothing at all,
## so a prop that slept under a hero's shoulder could never be pushed again.
func _check_settled(delta: float) -> void:
	if not _touching.is_empty():
		_slow_for = 0.0
		return
	if linear_velocity.length() < SETTLE_SPEED and angular_velocity.length() < SETTLE_SPIN:
		_slow_for += delta
		if _slow_for >= SETTLE_TIME:
			_slow_for = 0.0
			linear_velocity = Vector3.ZERO
			angular_velocity = Vector3.ZERO
			sleeping = true
	else:
		_slow_for = 0.0


## A deterministic, non-zero seed for one FX burst. Drawn from this prop's own
## generator, so a replay produces the same chips in the same places; ImpactFX
## treats 0 as "derive one from the position" and that is a worse guarantee.
func _fx_seed() -> int:
	return int(_rng.randi()) | 1


# --- Audio -------------------------------------------------------------------
# AudioManager has no material-keyed prop entry points yet, so these pick the
# closest transient in the shipped library and are the one place that has to
# change when it does. See the report: `play_prop_hit(surface)` /
# `play_prop_break(surface)` are what this actually wants, keyed on the same
# ToonFactory.Surface the fx impact table is keyed on.

## A blow that the prop survived.
func play_surface_hit() -> void:
	match surface_kind():
		ToonFactory.Surface.GRANITE, ToonFactory.Surface.COBBLE:
			# 60 Hz rumble with noise in it — the closest thing to stone on stone.
			AudioManager.play_rock_impact()
		ToonFactory.Surface.IRON:
			AudioManager.play_boss_hit()
		_:
			# 90 Hz thud: a dull knock, which is what a full cask sounds like.
			AudioManager.play_land()


## The prop coming apart. Two layers, because one transient is a hit and a hit is
## not a destruction: the material's own crack, plus a broadband scatter tail.
func play_surface_break() -> void:
	match surface_kind():
		ToonFactory.Surface.GRANITE, ToonFactory.Surface.COBBLE:
			AudioManager.play_rock_impact()
		ToonFactory.Surface.IRON:
			AudioManager.play_boss_hit()
		_:
			AudioManager.play_super_boxy_hit()
	AudioManager.play_rock_throw()


# --- Deck ring ---------------------------------------------------------------

## Something heavy hit the deck. Everything loose on it hops.
##
## The lateral component is biased OUTBOARD, away from the centreline, and that
## is a gameplay constraint rather than a physical claim: prop_spawner.gd keeps
## the middle six metres clear because a barrel parked in the fight lane reads as
## an obstacle course, and a rattle that could random-walk props inboard would
## undo that over a three-minute fight. Outboard-only, it can only ever tidy.
func _on_world_shake(strength: float, _duration: float) -> void:
	if strength < JOLT_MIN_SHAKE or _jolt_cooldown > 0.0 or not is_inside_tree():
		return
	if freeze or is_queued_for_deletion():
		return
	_jolt_cooldown = JOLT_COOLDOWN

	var over := (strength - JOLT_MIN_SHAKE) / maxf(0.01, 1.0 - JOLT_MIN_SHAKE)
	var speed := JOLT_SPEED * clampf(over, 0.0, 1.4) * _nearness_to_giant()
	if speed < 0.05:
		return

	sleeping = false
	set_physics_process(true)
	var outboard := signf(global_position.z)
	if outboard == 0.0:
		outboard = 1.0
	var dir := Vector3(
		_rng.randf_range(-0.35, 0.35),
		1.0,
		outboard * _rng.randf_range(0.05, 0.4)).normalized()
	apply_impulse(dir * speed * mass)
	# A touch of spin, so a hopping crate rocks instead of levitating.
	apply_torque_impulse(Vector3(
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-0.4, 0.4),
		_rng.randf_range(-1.0, 1.0)) * speed * mass * 0.08)


## 1.0 next to the giant, JOLT_FAR_FRACTION at JOLT_RANGE and beyond. Group
## lookup, per the Groups contract — no reference to the boss's script.
func _nearness_to_giant() -> float:
	var boss := get_tree().get_first_node_in_group("boss") as Node3D
	if boss == null:
		return JOLT_FAR_FRACTION
	var d := global_position - boss.global_position
	d.y = 0.0
	return lerpf(1.0, JOLT_FAR_FRACTION, clampf(d.length() / JOLT_RANGE, 0.0, 1.0))


# --- Kicker -----------------------------------------------------------------

func _build_kicker() -> void:
	_kicker = Area3D.new()
	_kicker.name = "Kicker"
	_kicker.collision_layer = 0
	_kicker.collision_mask = PhysicsLayers.PLAYERS
	_kicker.monitorable = false
	var col := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = _kick_radius()
	col.shape = s
	_kicker.add_child(col)
	add_child(_kicker)
	_kicker.body_entered.connect(_on_kicker_entered)
	_kicker.body_exited.connect(_on_kicker_exited)


func _on_kicker_entered(body: Node3D) -> void:
	if body in _touching:
		return
	_touching.append(body)
	sleeping = false
	set_physics_process(true)


func _on_kicker_exited(body: Node3D) -> void:
	_touching.erase(body)


func _apply_kicks() -> void:
	if _touching.is_empty():
		return
	for i in range(_touching.size() - 1, -1, -1):
		var body := _touching[i]
		if not is_instance_valid(body):
			_touching.remove_at(i)
			continue
		var v := Vector3.ZERO
		if body is CharacterBody3D:
			v = (body as CharacterBody3D).velocity
		v.y = 0.0
		var away := global_position - body.global_position
		away.y = 0.0
		if away.length() < 0.01:
			continue
		var n := away.normalized()
		var approach := clampf(v.dot(n), 0.0, KICK_MAX_APPROACH)
		if approach < 0.6:
			continue
		# Push slightly above the centre of mass so a crate tips as it slides.
		apply_force(n * mass * approach * KICK_GAIN * kick_strength, Vector3(0.0, 0.15, 0.0))


func _on_sleep_changed() -> void:
	if not sleeping:
		set_physics_process(true)
	else:
		_armed = true


func _kick_radius() -> float:
	var s := _own_shape()
	if s is SphereShape3D:
		return (s as SphereShape3D).radius + KICK_MARGIN
	if s is BoxShape3D:
		return ((s as BoxShape3D).size * 0.5).length() + KICK_MARGIN
	if s is CylinderShape3D:
		var cyl := s as CylinderShape3D
		return maxf(cyl.radius, cyl.height * 0.5) + KICK_MARGIN
	if s is CapsuleShape3D:
		return (s as CapsuleShape3D).height * 0.5 + KICK_MARGIN
	return 0.9


func _own_shape() -> Shape3D:
	for c in get_children():
		if c is CollisionShape3D:
			return (c as CollisionShape3D).shape
	return null


func _own_collision_node() -> CollisionShape3D:
	for c in get_children():
		if c is CollisionShape3D:
			return c as CollisionShape3D
	return null


## Half the prop's largest dimension. Used for the shard size, the scatter radius
## and ImpactFX.smash's `extent`, so it is shared with BreakableProp rather than
## duplicated there. Public because ImpactFX takes it as an argument and
## prop_spawner.gd needs it to decide how far above the deck to drop the prop.
func extent() -> float:
	var s := _own_shape()
	if s is SphereShape3D:
		return (s as SphereShape3D).radius
	if s is BoxShape3D:
		var b := (s as BoxShape3D).size
		return maxf(b.x, maxf(b.y, b.z)) * 0.5
	if s is CylinderShape3D:
		var cyl := s as CylinderShape3D
		return maxf(cyl.radius, cyl.height * 0.5)
	if s is CapsuleShape3D:
		return (s as CapsuleShape3D).height * 0.5
	return 0.5


# --- Variation ---------------------------------------------------------------

func _seed_variant() -> void:
	if variant_seed != 0:
		_rng.seed = variant_seed
	else:
		# A hand-placed prop still has to be deterministic, and its authored
		# position is the only thing about it that is. Quantised to a centimetre
		# so a solver hair's-breadth difference cannot flip the variant.
		var p := global_position
		_rng.seed = hash("%.2f|%.2f|%.2f" % [p.x, p.y, p.z])
	_variant = _rng.randi() % VARIANTS
	_size_scale = 1.0 + _rng.randf_range(-size_variation, size_variation)


## Scale the COLLISION SHAPE, never the node.
##
## Setting `scale` on a RigidBody3D is a documented Godot footgun — the physics
## server takes the shape, not the node transform, so a scaled body has a
## collider that no longer matches what is drawn. Duplicating and resizing the
## shape is the supported way, and the duplicate is mandatory for a second
## reason: sub-resources in a PackedScene are SHARED between instances, so
## resizing the authored shape in place would resize every crate in the arena by
## every crate's variation in turn. Same failure mode ARCHITECTURE.md rule 7
## calls out for materials, one layer down.
func _apply_size_variation() -> void:
	if is_equal_approx(_size_scale, 1.0):
		return
	var node := _own_collision_node()
	if node == null or node.shape == null:
		return
	var s := node.shape.duplicate() as Shape3D
	if s is BoxShape3D:
		(s as BoxShape3D).size *= _size_scale
	elif s is SphereShape3D:
		(s as SphereShape3D).radius *= _size_scale
	elif s is CylinderShape3D:
		var cyl := s as CylinderShape3D
		cyl.radius *= _size_scale
		cyl.height *= _size_scale
	elif s is CapsuleShape3D:
		var cap := s as CapsuleShape3D
		cap.radius *= _size_scale
		cap.height *= _size_scale
	node.shape = s


# --- Look -------------------------------------------------------------------

## Build the visual from the collision shape's own dimensions, so the two can
## never drift apart and so a shard's size derives from the same number the
## physics uses. "plain" leaves an authored MeshInstance3D untouched.
func _build_body() -> void:
	if body_kind == "plain":
		return
	var s := _own_shape()
	if s == null:
		return

	var body := MeshInstance3D.new()
	body.name = "Body"
	var trim: MeshInstance3D = null

	match body_kind:
		"crate":
			var size: Vector3 = (s as BoxShape3D).size if s is BoxShape3D \
				else Vector3.ONE * extent() * 2.0
			body.mesh = PropMeshKit.crate_body(size)
			trim = MeshInstance3D.new()
			trim.name = "Trim"
			trim.mesh = PropMeshKit.crate_brackets(size)
		"barrel":
			var r: float = (s as CylinderShape3D).radius if s is CylinderShape3D else extent()
			var h: float = (s as CylinderShape3D).height if s is CylinderShape3D \
				else extent() * 2.0
			# The collider is the barrel's widest circle; the staves sit just
			# inside it so a rolling cask never floats a millimetre off the deck.
			body.mesh = PropMeshKit.barrel_body(r * 0.95, h)
			trim = MeshInstance3D.new()
			trim.name = "Trim"
			trim.mesh = PropMeshKit.barrel_hoops(r * 0.95, h)
		"rubble":
			var size: Vector3 = (s as BoxShape3D).size if s is BoxShape3D \
				else Vector3.ONE * extent() * 2.0
			body.mesh = PropMeshKit.rubble_body(size, _variant)

	add_child(body)
	if trim != null:
		trim.add_to_group("prop_trim")
		add_child(trim)


func _has_trim() -> bool:
	for mi in _meshes(self):
		if mi.is_in_group("prop_trim"):
			return true
	return false


## Uniform scale on every drawn part. Used for the per-instance size variation
## and, in BreakableProp, for the squash pulse and the crumble.
func _apply_visual_scale(s: float) -> void:
	for mi in _meshes(self):
		mi.scale = Vector3.ONE * s


func _apply_materials() -> void:
	var body_mat := _surface_material()
	# Built lazily: a masonry block has no trim, and minting its iron material
	# anyway would put four unused entries in ToonFactory's cache for nothing.
	var trim_mat: StandardMaterial3D = null
	for mi in _meshes(self):
		if mi.is_in_group("prop_trim"):
			if trim_mat == null:
				trim_mat = trim_material()
			mi.material_override = trim_mat
		else:
			mi.material_override = body_mat


func _surface_material() -> StandardMaterial3D:
	var c := _vary(tint, 1.0)
	match surface:
		"stone":
			return ToonFactory.stone(c, 1.2)
		"iron":
			return ToonFactory.iron(c, 0.9)
		"cobble":
			return ToonFactory.cobblestone(c, 0.8)
		_:
			return ToonFactory.wood(c, 0.55)


func trim_material() -> StandardMaterial3D:
	return ToonFactory.iron(_vary(trim_color, 0.5), 0.6, 0.65, 0.5)


## Nudge a colour by this instance's variant. QUANTISED to VARIANTS steps, not
## continuous: ToonFactory caches materials by parameter set, so a continuous
## jitter would mint one material — and therefore one more batch break — per
## prop, which is the opposite of what the cache is for.
func _vary(c: Color, amount: float) -> Color:
	if amount <= 0.0 or VARIANTS <= 1:
		return c
	# -1, -1/3, +1/3, +1 for VARIANTS == 4.
	var k := (float(_variant) / float(VARIANTS - 1)) * 2.0 - 1.0
	var out := Color(c)
	out.v = clampf(out.v * (1.0 + 0.085 * k * amount), 0.0, 1.0)
	out.s = clampf(out.s * (1.0 - 0.10 * k * amount), 0.0, 1.0)
	out.h = fposmod(out.h + 0.014 * k * amount, 1.0)
	return out


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for c in node.get_children():
		out.append_array(_meshes(c))
	return out
