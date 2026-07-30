class_name BossTelegraph
extends Node3D
## The ground read for one of Adamastor's attacks.
##
## N. Sane's bosses announce every heavy move with a pose, a colour, a sound and
## a beat of anticipation. The giant's pose and colour live on the giant himself
## (`Adamastor.set_lean` / `set_charge`) and the sound is AudioManager's; this is
## the fourth leg — a mark on the deck that says WHERE the attack lands and, by
## filling or closing, exactly WHEN.
##
## Two shapes, deliberately not interchangeable, so a player who is watching
## their partner rather than the giant can still name the attack from the deck
## alone:
##
##   AOE    a hot ring at the blast radius with a disc that fills outward from
##          the centre. The fill reaching the ring IS the impact. Slam, and the
##          phase-two roar.
##   MARKER a cool crosshair that CLOSES inward onto one point. One per rock in a
##          volley, planted the instant the throw is committed, so stepping off
##          the mark beats it.
##
## The colour carries the same information a second time: the slam's orange means
## "get out of the circle", the rock's cyan means "get off the cross". A colour-
## blind player still has two different shapes and two different animations.
##
## Everything here animates off accumulated `delta`, never a clock, and there is
## no randomness in it at all — the capture gate compares frames pixel for pixel.
## See ARCHITECTURE.md, "Why the determinism rules exist".

enum Kind {
	AOE,      ## fills outward to `radius`; the fill arriving is the hit
	MARKER,   ## closes inward onto the origin; the ring arriving is the hit
}

## Palette. Exposed as constants so the state machine names a colour rather than
## repeating a literal, and so slam / rock / roar can never drift into each other.
const SLAM_TINT := Color(1.00, 0.34, 0.10)
const ROCK_TINT := Color(0.38, 0.80, 1.00)
const ROAR_TINT := Color(1.00, 0.76, 0.22)

## Seconds the mark stays on the deck after its beat lands, flashing out. Short:
## it is punctuation on the impact, not a second telegraph.
const FLASH := 0.16
## How far above the deck the decal sits. Enough to clear z-fighting against the
## granite at a grazing camera angle without reading as a card floating over it.
const LIFT := 0.09
## Ring wall thickness as a fraction of the radius, floored so an eight-metre
## slam ring and a one-metre rock mark are both still legible.
const RING_FRACTION := 0.05
const RING_MIN := 0.16
## Where the closing MARKER ring starts, as a multiple of its final radius. Big
## enough that the collapse is unmistakable from across the deck.
const MARKER_OPEN := 2.8
## Insistence beat, in Hz. Roughly a heartbeat at rest and it is the same rate on
## every attack, so the pulse reads as "incoming" rather than as attack identity.
const PULSE_HZ := 4.0

var kind: int = Kind.AOE
var radius: float = 6.0
## Seconds from now until the attack lands. The animation is normalised to it, so
## the mark is a clock, not a decoration.
var lead: float = 0.8
var tint: Color = SLAM_TINT

var _t: float = 0.0
var _ring: MeshInstance3D = null
var _fill: MeshInstance3D = null
var _cross: Node3D = null
var _ring_mat: StandardMaterial3D = null
var _fill_mat: StandardMaterial3D = null


# --- Construction -----------------------------------------------------------

## An area-of-effect ring that fills outward. `parent` is usually the giant
## himself, so the mark tracks his feet through the lunge — it has to show where
## the blast WILL be, not where he was when he started winding up.
static func aoe(parent: Node3D, p_radius: float, p_lead: float,
		p_tint: Color = SLAM_TINT) -> BossTelegraph:
	return _make(parent, Kind.AOE, p_radius, p_lead, p_tint)


## A crosshair that closes onto a point. Parented into the spawn root and pinned
## to a world position by the caller, because a rock's landing spot is committed
## at wind-up time and must not follow anything afterwards.
static func marker(parent: Node3D, p_radius: float, p_lead: float,
		p_tint: Color = ROCK_TINT) -> BossTelegraph:
	return _make(parent, Kind.MARKER, p_radius, p_lead, p_tint)


static func _make(parent: Node3D, p_kind: int, p_radius: float, p_lead: float,
		p_tint: Color) -> BossTelegraph:
	if parent == null or not is_instance_valid(parent):
		return null
	var tg := BossTelegraph.new()
	tg.name = "Telegraph"
	tg.kind = p_kind
	tg.radius = maxf(0.5, p_radius)
	tg.lead = maxf(0.05, p_lead)
	tg.tint = p_tint
	parent.add_child(tg)
	return tg


## Take the mark off the deck now. Used when the fight ends or resets mid
## wind-up, so a telegraph can never outlive the attack it was promising.
func cancel() -> void:
	queue_free()


func _ready() -> void:
	# The LIFT lives on the child meshes, not on this node: `marker()` callers set
	# global_position after add_child, and that would throw away an offset stored
	# on the node itself.
	var wall: float = maxf(RING_MIN, radius * RING_FRACTION)
	_ring_mat = _decal_material(tint, 0.55)
	_fill_mat = _decal_material(tint, 0.18)

	_ring = MeshInstance3D.new()
	_ring.name = "Ring"
	var torus := TorusMesh.new()
	torus.inner_radius = maxf(0.05, radius - wall)
	torus.outer_radius = radius
	torus.rings = 6
	torus.ring_segments = 48
	_ring.mesh = torus
	_ring.material_override = _ring_mat
	_ring.position.y = LIFT
	add_child(_ring)

	if kind == Kind.AOE:
		# Unit disc, scaled on X/Z by the fill radius each frame.
		_fill = MeshInstance3D.new()
		_fill.name = "Fill"
		var disc := CylinderMesh.new()
		disc.top_radius = 1.0
		disc.bottom_radius = 1.0
		disc.height = 0.03
		disc.radial_segments = 48
		disc.rings = 0
		_fill.mesh = disc
		_fill.material_override = _fill_mat
		_fill.position.y = LIFT * 0.6
		_fill.scale = Vector3(0.001, 1.0, 0.001)
		add_child(_fill)
	else:
		# A fixed cross under the closing ring, so the exact impact point is
		# readable even at the moment the ring is still wide open.
		_cross = Node3D.new()
		_cross.name = "Cross"
		add_child(_cross)
		for axis in [Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0, 1.0)]:
			var bar := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(
				radius * 1.8 if axis.x > 0.0 else wall,
				0.03,
				wall if axis.x > 0.0 else radius * 1.8)
			bar.mesh = box
			bar.material_override = _ring_mat
			bar.position.y = LIFT
			_cross.add_child(bar)
		_ring.scale = Vector3(MARKER_OPEN, 1.0, MARKER_OPEN)

	set_process(true)
	_advance(0.0)


func _decal_material(colour: Color, alpha: float) -> StandardMaterial3D:
	# Deliberately NOT ToonFactory's cached materials: these are mutated per
	# instance every frame (alpha and emission energy), and a shared cached
	# material would recolour every other decal in the scene. See ARCHITECTURE.md
	# rule 7.
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(colour.r, colour.g, colour.b, alpha)
	mat.emission_enabled = true
	mat.emission = colour
	mat.emission_energy_multiplier = 1.2
	mat.disable_receive_shadows = true
	mat.shadow_casting_setting = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mat


# --- Animation --------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	_advance(_t)


func _advance(t: float) -> void:
	if _ring_mat == null:
		return
	if t < lead:
		_charge(clampf(t / lead, 0.0, 1.0), t)
		return
	var f := clampf((t - lead) / FLASH, 0.0, 1.0)
	_blow_out(f)
	if f >= 1.0:
		queue_free()


## The wind-up. `k` runs 0 -> 1 over `lead`, so k IS how much of the anticipation
## has been spent and the player can read the remaining time off the shape.
func _charge(k: float, t: float) -> void:
	# The pulse deepens as the beat approaches instead of running flat: an alarm
	# that never changes stops being an alarm.
	var beat := 0.5 + 0.5 * sin(t * TAU * PULSE_HZ)
	var insistence: float = lerpf(0.25, 0.9, k)
	var alpha: float = lerpf(0.30, 0.85, k) * lerpf(1.0 - insistence * 0.5, 1.0, beat)

	_ring_mat.albedo_color.a = alpha
	_ring_mat.emission_energy_multiplier = lerpf(1.0, 4.2, k)

	if kind == Kind.AOE:
		# Ease-in: the fill creeps, then rushes the last third. The rush is the
		# "here it comes" beat, and it is what stops players leaving at the last
		# possible instant every time.
		var grown: float = radius * (k * k * (3.0 - 2.0 * k))
		_fill.scale = Vector3(maxf(0.001, grown), 1.0, maxf(0.001, grown))
		_fill_mat.albedo_color.a = lerpf(0.10, 0.42, k)
		_fill_mat.emission_energy_multiplier = lerpf(0.6, 2.6, k)
	else:
		# Ease-out on the collapse: it slams shut early and then hovers, so the
		# reticle is at its most readable while there is still time to move.
		var e := 1.0 - pow(1.0 - k, 3.0)
		var s: float = lerpf(MARKER_OPEN, 1.0, e)
		_ring.scale = Vector3(s, 1.0, s)


## The punctuation: a bright over-scaled flare that fades out over FLASH.
func _blow_out(f: float) -> void:
	var fade := 1.0 - f
	_ring_mat.albedo_color.a = 0.95 * fade
	_ring_mat.emission_energy_multiplier = lerpf(6.0, 0.0, f)
	var s: float = 1.0 + 0.35 * f
	if kind == Kind.AOE:
		_ring.scale = Vector3(s, 1.0, s)
		_fill.scale = Vector3(radius, 1.0, radius)
		_fill_mat.albedo_color.a = 0.5 * fade
		_fill_mat.emission_energy_multiplier = lerpf(3.5, 0.0, f)
	else:
		_ring.scale = Vector3(s, 1.0, s)
