extends Node3D
## RiverLife: the Douro doing something.
##
## The bridge, the terraces and the sky are all set. What is missing from a
## golden-hour Porto frame is that the river below is *working* — gulls wheeling
## over the gorge, a barge dropping downstream, a launch crossing under the arch,
## the water breaking round the piers, and the low mist that all of it moves
## through. Every one of those is cheap; together they are most of the difference
## between a diorama and a place.
##
## Drop it anywhere in the world:
##
##     const RiverLifeScript := preload("res://scripts/world/river_life.gd")
##     add_child(RiverLifeScript.new())
##
## It builds against world coordinates, so it does not care where it is parented
## as long as that parent is not itself transformed. Nothing here collides, casts
## a shadow, or enters the playable corridor; everything is seeded, so the river
## is the same river every run.
##
## Complements rather than duplicates sky_background.gd, which owns the moored
## rabelos, the drifting clouds and five individually-flapping gulls. What is here
## is the stuff that reads at distance and in numbers: three FLOCKS on three
## different path shapes, at three heights, batched into one MultiMesh each with
## the wingbeat done in the vertex stage — 24 birds for 3 draw calls, against the
## 10 that sky_background's 5 cost. If the two together read as too busy, the
## thing to cut is _build_gulls() there, not here.
##
## Budget (measured by _atmosphere_probe.gd): 13 draw calls, ~2.0k triangles.
##
## Two shaders are compiled from source strings in this file rather than shipped
## as .gdshader assets. That is deliberate: both are a dozen lines, both exist
## only to serve geometry built here, and keeping them inline means this node is
## one file with no companion resources to lose.

# --- Where the river is ------------------------------------------------------

## bridge_arena.tscn puts the River plane here.
const WATER_Y := -15.0
## The swell runs at wave_height 0.35 over unit-amplitude trains, so crests reach
## WATER_Y + 0.35. Foam ribbons are flat quads, so they sit just clear of the
## highest crest and accept floating ~0.75 m over the deepest trough — soft alpha
## with no silhouette, all of it 40 m+ away, and the alternative is tessellating
## every ribbon below the 35 m swell wavelength to make it ride properly.
const FOAM_Y := WATER_Y + 0.40
## bridge_arena.gd's PIER_X. The arch springs off piers standing in the water here.
const PIER_X := 47.0
## Half-width of open water between the quay walls; vessels stay inside it.
const CHANNEL_HALF := 44.0
## Vessels are hidden past this |z|, which is where they wrap. At 130 m the depth
## fog is running ~45% and a 7 m launch is a couple of pixels, so the pop is not
## a pop. It also keeps them off the photogrammetry backdrop, whose leading edge
## is at z = -131.
const VESSEL_HORIZON := 130.0

# --- Gull flocks -------------------------------------------------------------

## Path shapes. The point of having three is that a sky full of identical circles
## reads as a screensaver; a wheel, a crossing figure-eight and one long slow
## ellipse read as different birds doing different things.
enum FlockPath {
	WHEEL,          ## a circle whose radius breathes — birds working one spot
	FIGURE_EIGHT,   ## a Gerono lemniscate: hard bank through the crossing, coast at the ends
	RING,           ## a plain ellipse; stretched flat it reads as a transit
}

## center   world centre of the path
## size     (x radius, vertical bob amplitude, z radius)
## period   seconds for one circuit
## count    birds
## spread   +- seconds of lag between birds, i.e. how strung out the skein is
## drift    +- metres of lateral / vertical scatter about the leader's line
##
## Every envelope is checked clear of the geometry it flies past, by
## _atmosphere_probe.gd, which sweeps a full circuit against the landmarks:
##   flock 0 wheels over the Ribeira, x in [-45.8, -6.2] and y >= 26.8. The near
##     terrace tops out at 21.6 (a 19 m facade plus a 2.6 m roof) and the upper
##     row at 25.6, and that row starts at x = -48.7 — so the flock clears the
##     first by height and the second by plan, with about 3 m in hand either way;
##   flock 1 crosses the gorge lower, at y ~19, but never past x = 34.9, and the
##     Serra do Pilar cliff mass starts at x = 42;
##   flock 2 is the long slow transit, out at z = -78 in the empty water between
##     the last terrace row (z = -39) and the photogrammetry backdrop (z = -131).
## None of the three ever enters z > -18, so nothing can clip the bridge or the
## boss whatever the camera does.
##
## The three sit at three heights — 19, 27 and 33 — which is composition, not
## caution: birds at one altitude read as a decal on the sky. sky_background.gd's
## clouds occupy y 28 and up over the same reach, so flocks 0 and 2 do cross them.
## That is fine and even correct (the clouds are opaque, so a gull passes behind
## one and comes out), but if a render ever catches a bird half inside a puff, the
## fix is to drop these centre heights rather than to move the clouds.
const GULL_FLOCKS := [
	{
		"path": FlockPath.WHEEL, "count": 8,
		"center": Vector3(-26.0, 33.0, -34.0), "size": Vector3(16.0, 2.4, 12.0),
		"period": 34.0, "spread": 3.0, "drift": Vector2(3.0, 2.4),
	},
	{
		"path": FlockPath.FIGURE_EIGHT, "count": 7,
		"center": Vector3(10.0, 19.0, -48.0), "size": Vector3(22.0, 2.0, 11.0),
		"period": 36.0, "spread": 2.4, "drift": Vector2(3.4, 2.0),
	},
	{
		"path": FlockPath.RING, "count": 9,
		"center": Vector3(0.0, 27.0, -78.0), "size": Vector3(78.0, 1.6, 26.0),
		"period": 90.0, "spread": 4.5, "drift": Vector2(6.0, 3.0),
	},
]

## Seconds either side of `now` used to finite-difference the flight path into a
## heading and a turn rate. Short enough to track the figure-eight's crossing,
## long enough not to be noise.
const LOOK_AHEAD := 0.12
## Radians of roll per radian/LOOK_AHEAD of turn. A bird banks INTO its turn, so
## the sign is negative: a positive turn is toward the bird's own +X (its right),
## and a positive rotation about the basis Z axis — which points backwards — lifts
## +X. Flip this one sign if the flocks ever bank outward through the corners.
const BANK_GAIN := -6.0
const BANK_LIMIT := 0.85

# --- Vessels -----------------------------------------------------------------

## x        lane down the channel
## speed    m/s; positive runs downstream (-Z). The Douro at Porto is a tidal
##          pool between two banks, so all of it is slow.
## phase    seconds already elapsed into the run at t = 0. Set so the river is not
##          empty on the first frame: the three arrive under the bridge at about
##          13, 29 and 41 seconds, staggered rather than in convoy.
## run      metres per circuit, starting at +run/2, which puts both wrap ends past
##          VESSEL_HORIZON where the vessel is already hidden.
## kind     "launch" or "barge"
##
## x lanes are chosen against sky_background.gd's moored rabelos, at x = -28, 8
## and 34, and against the arch: the parabola drops ARCH_RISE = 18 below the deck
## over a half-span of 46, so at |x| = 22 the ironwork is at y = -2.1 and at
## |x| = 6 it is at y = -0.3 — 13 to 15 m of air over a launch whose masthead is
## 2.6 m above the waterline.
const VESSELS := [
	{"kind": "launch", "x": -22.0, "speed": 3.1, "phase": 35.0, "run": 300.0, "yaw": 0.0},
	{"kind": "launch", "x": 16.0, "speed": -2.4, "phase": 33.0, "run": 300.0, "yaw": PI},
	{"kind": "barge", "x": -6.0, "speed": 1.35, "phase": 70.0, "run": 300.0, "yaw": 0.0},
]

# --- Palette -----------------------------------------------------------------

const HULL_DARK := Color(0.17, 0.22, 0.24)      # tarred/painted working timber
const HULL_TRIM := Color(0.55, 0.20, 0.16)      # the red boot-top every Douro boat has
const UPPERWORKS := Color(0.80, 0.78, 0.72)     # weathered cream wheelhouse
const BARGE_HULL := Color(0.22, 0.26, 0.22)
const BARGE_UPPER := Color(0.72, 0.68, 0.60)

# --- Exports -----------------------------------------------------------------

@export var gull_flocks: bool = true
@export var vessels: bool = true
## Rabelos tied up along both quays. Static, unlike `vessels`.
@export var moored_fleet: bool = true
@export var surface_foam: bool = true
## Forward+ only — GL Compatibility has no volumetric fog for a FogVolume to
## write into, so it is skipped rather than left to warn.
@export var river_mist: bool = true
## Extinction per metre ADDED to the environment's global 0.0016 inside the mist
## box. Along a 60 m sightline down the gorge that is 1 - exp(-0.0076 * 60) = 37%,
## which dissolves the far river while leaving the city above it clear — the mist
## box tops out at y = -8.9, twenty-three metres under the ridge line. It is also
## the medium the arch's god rays actually rake through, which is why it is worth
## having at all. Exposed because it is the number most likely to want a nudge
## once someone has looked at a frame.
@export_range(0.0, 0.05, 0.0005) var mist_density: float = 0.006
@export var rng_seed: int = 0x0D0175   # "DOURO"

var _flocks: Array[Dictionary] = []
var _vessels: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
## Seconds of simulated time since this node entered the tree. The animation
## clock for every gull and vessel — see the note in _process().
var _decor_time: float = 0.0


func _ready() -> void:
	_rng.seed = rng_seed
	if gull_flocks:
		_build_gulls()
	if vessels:
		_build_vessels()
	if moored_fleet:
		_build_moored_fleet()
	if surface_foam:
		_build_surface_foam()
	if river_mist and RenderingServer.get_current_rendering_method() == "forward_plus":
		_build_mist()


func _process(delta: float) -> void:
	# Accumulated delta, NOT Time.get_ticks_msec(). This used to read the wall
	# clock "so the two sets of decor never drift apart", and accumulating does
	# that strictly better: sky_background.gd integrates the same delta from the
	# same first frame, so the two stay locked without either of them depending
	# on how long the engine happened to spend booting.
	#
	# The wall clock also made every screenshot a different screenshot. Two runs
	# reach this line milliseconds apart, so every gull and every rabelo sat
	# somewhere new in every capture, and the per-pixel regression gate in
	# tools/harness.py could never report anything but failure. See ARCHITECTURE.md,
	# "Why the determinism rules exist".
	_decor_time += delta
	_animate_gulls(_decor_time)
	_animate_vessels(_decor_time)


# --- Gulls -------------------------------------------------------------------

func _build_gulls() -> void:
	var holder := Node3D.new()
	holder.name = "GullFlocks"
	add_child(holder)

	var mesh := _gull_mesh()
	var mat := _gull_material()

	for entry in GULL_FLOCKS:
		var flock: Dictionary = entry
		var count := int(flock["count"])
		var mm := MultiMesh.new()
		# Format flags must be set before instance_count, or the buffer is
		# allocated for the wrong stride and every custom-data write is dropped.
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = count

		var lags := PackedFloat32Array()
		var sides := PackedFloat32Array()
		var rises := PackedFloat32Array()
		var spread := float(flock["spread"])
		var drift: Vector2 = flock["drift"]
		var c: Vector3 = flock["center"]
		var s: Vector3 = flock["size"]
		for i in count:
			lags.append(_rng.randf_range(-spread, spread))
			sides.append(_rng.randf_range(-drift.x, drift.x))
			rises.append(_rng.randf_range(-drift.y, drift.y))
			# x = wingbeat phase, y = per-bird rate variation. Without these the
			# whole flock beats in lockstep, which is the one thing birds never do.
			mm.set_instance_custom_data(i, Color(_rng.randf(), _rng.randf(), 0.0, 0.0))
			# Park them somewhere sane until the first _process; an unset
			# MultiMesh transform is identity, i.e. a pile of gulls at the origin.
			mm.set_instance_transform(i, Transform3D(Basis(), c))

		# Stated, not derived. A MultiMesh whose bounds go stale is culled whole,
		# and these are recomputed from instance transforms every frame otherwise.
		# The margin covers the per-bird scatter, the wing span and the flap.
		var pad := Vector3(drift.x, drift.y, drift.x) + Vector3(1.2, 1.2, 1.2)
		var half := Vector3(s.x, s.y, s.z) + pad
		mm.custom_aabb = AABB(c - half, half * 2.0)

		var node := MultiMeshInstance3D.new()
		node.name = "Flock%d" % _flocks.size()
		node.multimesh = mm
		node.material_override = mat
		# A gull's shadow lands on water (which does not receive one) or on the
		# far bank at 80 m. Not worth a shadow-map draw per flock.
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Same reason lighting_rig.gd excludes sky_background's movers: geometry
		# that moves every frame gets voxelised into the SDFGI cascades as a
		# drifting occluder and smears light across the arena.
		node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		holder.add_child(node)

		_flocks.append({
			"mm": mm, "path": int(flock["path"]), "center": c, "size": s,
			"period": float(flock["period"]),
			"lags": lags, "sides": sides, "rises": rises,
		})


## One gull, facing -Z (Godot forward) so Basis.looking_at drives it directly.
##
## ~130 triangles. What that buys over the 60 it replaces is a WING PLANFORM.
## Round 1's finding — "bent rectangles hinged at a point, no wing shape, no body,
## no tail, they read as blowing litter" — was aimed at the five hand-animated
## birds sky_background.gd builds, which really are two slabs each, but the flock
## mesh here had the same defect in a milder form: one constant-chord rectangle
## per wing, which in silhouette is a plank.
##
## A gull's wing is long, narrow and swept: broad at the shoulder, half that at
## the wrist, and a pointed hand raked back behind the shoulder line. Three
## boxes per side get all three of those, and the silhouette is the only thing
## anyone reads at sixty metres. The shader is untouched — it rotates anything
## past `body_half` about the shoulder and fades the primaries in by span, so a
## tapered wing drives the existing tip colouring correctly and for free.
func _gull_mesh() -> ArrayMesh:
	var b := MeshBaker.new()
	# Body, in three tapering blocks: a gull is deepest at the breast and runs
	# out to nothing at the tail, and one box is a brick.
	b.add_box(Vector3(0.145, 0.135, 0.28), Transform3D(Basis(), Vector3(0.0, 0.0, -0.10)))
	b.add_box(Vector3(0.115, 0.105, 0.22), Transform3D(Basis(), Vector3(0.0, -0.005, 0.13)))
	b.add_box(Vector3(0.075, 0.065, 0.14), Transform3D(Basis(), Vector3(0.0, -0.012, 0.29)))
	# Head on a short neck, and a beak: two boxes that turn a torpedo into a bird.
	b.add_box(Vector3(0.095, 0.095, 0.13), Transform3D(Basis(), Vector3(0.0, 0.035, -0.30)))
	b.add_box(Vector3(0.035, 0.035, 0.10), Transform3D(Basis(), Vector3(0.0, 0.025, -0.40)))
	# Tail, fanned: wider than the body and tapering to the trailing edge.
	b.add_box(Vector3(0.20, 0.022, 0.16), Transform3D(Basis(), Vector3(0.0, -0.012, 0.40)))
	b.add_box(Vector3(0.115, 0.020, 0.10), Transform3D(Basis(), Vector3(0.0, -0.012, 0.52)))

	# Wings. The dihedral is not baked in — the vertex shader's flap_bias holds
	# them in a shallow V and the beat swings about that, so a baked one would
	# fight it. Inner edge at x = 0.07 = body_half, which is the hinge.
	#
	# Each entry is (half-span centre, span, chord, thickness, sweep back in Z),
	# arm then wrist then hand. Sweep is what makes the outline a gull's rather
	# than an aeroplane's.
	var panels := [
		Vector4(0.185, 0.23, 0.235, 0.030),
		Vector4(0.415, 0.23, 0.170, 0.024),
		Vector4(0.640, 0.22, 0.095, 0.018),
	]
	var sweeps := [0.010, 0.055, 0.125]
	for sx: float in [-1.0, 1.0]:
		for i in panels.size():
			var p: Vector4 = panels[i]
			b.add_box(Vector3(p.y, p.w, p.z), Transform3D(Basis(),
					Vector3(sx * p.x, 0.006, 0.01 + sweeps[i])))
	var proto := b.commit(null, "GullProto", false)
	var mesh: ArrayMesh = proto.mesh
	proto.free()
	return mesh


func _animate_gulls(t: float) -> void:
	for flock in _flocks:
		var mm: MultiMesh = flock["mm"]
		for i in mm.instance_count:
			mm.set_instance_transform(i, gull_transform(flock, i, t))


## Where bird `i` of `flock` is, and how far over it is banked, at time `t`.
##
## Pure, and public, for one reason: MultiMesh instance transforms round-trip
## through the RenderingServer, and the headless dummy backend hands identity
## straight back, so anything written into the MultiMesh cannot be read out again
## and checked. _atmosphere_probe.gd sweeps this instead.
func gull_transform(flock: Dictionary, i: int, t: float) -> Transform3D:
	var lags: PackedFloat32Array = flock["lags"]
	var sides: PackedFloat32Array = flock["sides"]
	var rises: PackedFloat32Array = flock["rises"]

	var bt := t + lags[i]
	var here := _flock_point(flock, bt)
	var ahead := _flock_point(flock, bt + LOOK_AHEAD)
	var behind := _flock_point(flock, bt - LOOK_AHEAD)

	var fwd := ahead - behind
	if fwd.length_squared() < 1e-8:
		fwd = Vector3.FORWARD   # a stalled path is not a bird; just point it somewhere
	fwd = fwd.normalized()

	# Signed turn over the sample window, in the horizontal plane. Vector2 packs
	# (x, z), so a positive result is a turn toward the bird's own right — see
	# BANK_GAIN for why that becomes a negative roll.
	var v0 := Vector2(here.x - behind.x, here.z - behind.z)
	var v1 := Vector2(ahead.x - here.x, ahead.z - here.z)
	var roll := 0.0
	if v0.length_squared() > 1e-8 and v1.length_squared() > 1e-8:
		roll = clampf(v0.angle_to(v1) * BANK_GAIN, -BANK_LIMIT, BANK_LIMIT)

	var basis := Basis.looking_at(fwd, Vector3.UP)
	var pos := here + basis.x * sides[i] + Vector3.UP * rises[i]
	return Transform3D(basis.rotated(basis.z, roll), pos)


func _flock_point(flock: Dictionary, t: float) -> Vector3:
	var c: Vector3 = flock["center"]
	var s: Vector3 = flock["size"]
	var w := TAU / float(flock["period"])
	var a := t * w
	match int(flock["path"]):
		FlockPath.FIGURE_EIGHT:
			# Gerono: x traces a full sine while z traces sin*cos, so the path
			# crosses itself once a circuit and the birds bank hardest there.
			return c + Vector3(sin(a) * s.x, sin(a * 3.0) * s.y, sin(a) * cos(a) * s.z * 2.0)
		FlockPath.WHEEL:
			# A circle whose radius breathes by +-28%, three times a circuit.
			var r := 0.72 + 0.28 * sin(a * 3.0)
			return c + Vector3(cos(a) * s.x * r, sin(a * 2.0) * s.y, sin(a) * s.z * r)
		_:
			return c + Vector3(cos(a) * s.x, sin(a * 2.0) * s.y, sin(a) * s.z)


# --- Vessels -----------------------------------------------------------------

func _build_vessels() -> void:
	var holder := Node3D.new()
	holder.name = "Vessels"
	add_child(holder)

	var wake_mat := _foam_material(0.50, Vector2(-0.26, 0.0), 11.0)

	for entry in VESSELS:
		var spec: Dictionary = entry
		var node := Node3D.new()
		node.name = "Vessel%d" % _vessels.size()
		holder.add_child(node)

		if String(spec["kind"]) == "barge":
			_build_barge(node)
			_attach_wake(node, wake_mat, 5.0, 13.0, 70.0)
		else:
			_build_launch(node)
			_attach_wake(node, wake_mat, 2.1, 4.0, 34.0)

		node.rotation.y = float(spec["yaw"])
		_vessels.append({
			"node": node, "x": float(spec["x"]), "speed": float(spec["speed"]),
			"phase": float(spec["phase"]), "run": float(spec["run"]),
			"bob_phase": _rng.randf_range(0.0, TAU),
		})


## A working launch: about 7 m, dark painted hull, cream wheelhouse. Two bakes
## rather than one so the hull and the upperworks are different colours — at
## 60-120 m the two-tone is most of what makes it read as a boat and not a crate.
func _build_launch(parent: Node3D) -> void:
	var hull := MeshBaker.new()
	hull.add_box(Vector3(2.00, 0.90, 6.60), Transform3D(Basis(), Vector3(0.0, 0.05, 0.0)))
	# Stem: a narrower block tilted up, so the bow has a rake instead of a wall.
	hull.add_box(Vector3(1.30, 0.85, 1.70),
			Transform3D(Basis(Vector3.RIGHT, -0.30), Vector3(0.0, 0.18, -3.60)))
	# Boot-top / rubbing strake down each side, and a transom.
	for sx in [-1.0, 1.0]:
		hull.add_box(Vector3(0.12, 0.16, 6.40), Transform3D(Basis(), Vector3(sx * 1.00, 0.42, 0.0)))
	hull.add_box(Vector3(1.90, 0.55, 0.16), Transform3D(Basis(), Vector3(0.0, 0.32, 3.30)))
	var hull_mi := hull.commit(ToonFactory.wood(HULL_DARK, 1.4), "Hull", false)
	_decor(parent, hull_mi)

	var top := MeshBaker.new()
	top.add_box(Vector3(1.40, 1.05, 1.90), Transform3D(Basis(), Vector3(0.0, 1.02, 0.55)))
	top.add_box(Vector3(1.62, 0.10, 2.10), Transform3D(Basis(), Vector3(0.0, 1.60, 0.55)))
	top.add_cylinder(0.045, 2.00, Transform3D(Basis(), Vector3(0.0, 2.10, -0.70)), 6)
	# Coachroof over the fore cabin, and a stubby mast light gantry.
	top.add_box(Vector3(1.10, 0.22, 1.60), Transform3D(Basis(), Vector3(0.0, 0.62, -1.60)))
	top.add_beam(Vector3(-0.55, 1.72, 0.55), Vector3(0.55, 1.72, 0.55), 0.05)
	var top_mi := top.commit(ToonFactory.plaster(UPPERWORKS, 0.9), "Upperworks", false)
	_decor(parent, top_mi)


## A river barge: 24 m, low in the water, wheelhouse right aft. Slow enough that
## it crosses the frame over a whole fight rather than a whole shot, which is what
## makes it read as weight rather than traffic.
func _build_barge(parent: Node3D) -> void:
	var hull := MeshBaker.new()
	hull.add_box(Vector3(5.00, 2.10, 22.00), Transform3D(Basis(), Vector3(0.0, 0.10, 0.0)))
	hull.add_box(Vector3(3.60, 1.90, 2.60),
			Transform3D(Basis(Vector3.RIGHT, -0.34), Vector3(0.0, 0.30, -11.60)))
	for sx in [-1.0, 1.0]:
		hull.add_box(Vector3(0.22, 0.34, 21.60), Transform3D(Basis(), Vector3(sx * 2.45, 1.14, 0.0)))
	hull.add_box(Vector3(4.80, 0.90, 0.26), Transform3D(Basis(), Vector3(0.0, 0.72, 10.95)))
	var hull_mi := hull.commit(ToonFactory.iron(BARGE_HULL, 2.2, 0.35, 0.68), "BargeHull", false)
	_decor(parent, hull_mi)

	var top := MeshBaker.new()
	# Three hatch covers over the hold — the cargo silhouette.
	for i in 3:
		top.add_box(Vector3(3.80, 0.55, 4.40),
				Transform3D(Basis(), Vector3(0.0, 1.30, -6.20 + float(i) * 4.90)))
	# Wheelhouse aft, its roof, and a short funnel beside it.
	top.add_box(Vector3(3.00, 2.30, 3.00), Transform3D(Basis(), Vector3(0.0, 2.20, 8.60)))
	top.add_box(Vector3(3.40, 0.14, 3.40), Transform3D(Basis(), Vector3(0.0, 3.42, 8.60)))
	top.add_cylinder(0.34, 1.90, Transform3D(Basis(), Vector3(0.95, 4.20, 8.60)), 8)
	top.add_cylinder(0.05, 2.40, Transform3D(Basis(), Vector3(0.0, 4.70, 8.60)), 6)
	var top_mi := top.commit(ToonFactory.plaster(BARGE_UPPER, 1.6), "BargeUpperworks", false)
	_decor(parent, top_mi)


## The Kelvin pattern: two arms diverging from the bow, plus the churned centre
## trail off the stern. Baked flat at the waterline in the vessel's own space, so
## it turns with the boat.
##
## It also travels with the boat, which a real wake does not — the foam should be
## left behind in world space. At 1.4 to 3.1 m/s, 60 m out, through 30% haze, that
## is not a read anyone gets, and the alternative is a per-vessel ribbon buffer
## rebuilt every frame.
##
## The divergence is 10 degrees, not the physical Kelvin 19.5. The real half-angle
## is measured to the outer limit of the interference pattern, most of which is
## ripple; the FOAM line — which is all that is drawn here — is a good deal
## tighter, and 19.5 degrees over a 34 m ribbon puts a 2 m launch inside a 24 m
## wide V, which reads as a boat wearing a bow tie.
func _attach_wake(parent: Node3D, mat: Material, beam: float, bow_z: float, length: float) -> void:
	var b := MeshBaker.new()
	var y := FOAM_Y - WATER_Y - 0.10   # local: the vessel node rides just over the water
	var spread := 0.18

	for sx: float in [-1.0, 1.0]:
		var x0 := sx * beam * 0.30
		var x1 := sx * (beam * 0.30 + length * spread)
		var w_head := beam * 0.30
		var w_tail := beam * 1.60
		_ribbon(b,
			Vector3(x0 - w_head * 0.5, y, -bow_z), Vector3(x0 + w_head * 0.5, y, -bow_z),
			Vector3(x1 - w_tail * 0.5, y, -bow_z + length),
			Vector3(x1 + w_tail * 0.5, y, -bow_z + length))

	# Centre trail from the transom: the propeller wash, widening then dissolving.
	# 0.82 of the bow offset lands on the transom for both hulls (3.3 and 10.7),
	# so the wash starts where the water is actually being pushed.
	var stern := bow_z * 0.82
	var tail_z := stern + length * 0.62
	_ribbon(b,
		Vector3(-beam * 0.55, y, stern), Vector3(beam * 0.55, y, stern),
		Vector3(-beam * 1.15, y, tail_z), Vector3(beam * 1.15, y, tail_z))

	var mi := b.commit(mat, "Wake", false)
	_decor(parent, mi)


## A foam ribbon from a head edge (ha, hb) to a tail edge (ta, tb), wound so the
## face looks up whichever order the caller listed the edges in, and so UV.x always
## runs head (0) to tail (1) — which is what the foam shader's fades key off.
##
## The winding matters less than it looks, since the foam material is unshaded and
## cull_disabled, but a mesh whose normals point into the riverbed is a trap for
## anyone who later wants these lit.
func _ribbon(b: MeshBaker, ha: Vector3, hb: Vector3, ta: Vector3, tb: Vector3) -> void:
	if (ta - ha).cross(tb - ha).y >= 0.0:
		b.add_quad(ha, ta, tb, hb, Vector2.ONE)
	else:
		b.add_quad(hb, tb, ta, ha, Vector2.ONE)


func _animate_vessels(t: float) -> void:
	for v in _vessels:
		var node: Node3D = v["node"]
		var run: float = v["run"]
		var speed: float = v["speed"]
		# Start half a run upstream of the origin so both wrap ends sit past
		# VESSEL_HORIZON, where the vessel is already hidden.
		var z := run * 0.5 - fposmod((t + float(v["phase"])) * absf(speed), run)
		if speed < 0.0:
			z = -z
		var visible_now := absf(z) < VESSEL_HORIZON
		node.visible = visible_now
		if not visible_now:
			continue
		var phase: float = v["bob_phase"]
		node.position = Vector3(float(v["x"]), WATER_Y + 0.10 + sin(t * 0.62 + phase) * 0.16, z)
		# Pitch and roll off the same clock, a quarter-period apart, so the hull
		# corkscrews gently instead of see-sawing on one axis.
		node.rotation.x = sin(t * 0.55 + phase) * 0.018
		node.rotation.z = sin(t * 0.41 + phase * 1.7) * 0.026


# --- Moored fleet -------------------------------------------------------------

## Rabelos tied up along both quay walls.
##
## Round 1: "The Douro carries one 6 px white speck and no rabelo boats." Both
## halves of that are worth fixing and the second one is the Porto cue — the
## barcos rabelos moored bow-on to the Ribeira and Gaia quays are on every
## postcard of this exact view, and the river between two dressed banks was the
## last large empty surface in the frame.
##
## Static, and deliberately so. sky_background.gd owns three rabelos that ride the
## wave field out in the channel; these are tied to a wall, and a moored boat
## bobbing on a swell twenty metres from a quay that is not moving reads as a bug.
## One bake for the hulls and one for the canvas, whatever the fleet size.
const MOORING_Y := WATER_Y + 0.45
## Clear water between a hull's centreline and the wall it is tied to: half a
## 2.6 m beam plus a fender's worth.
const MOORING_STANDOFF := 1.55

## (z along the river, side: -1 Porto / +1 Gaia). Kept off |z| < 12, which is
## where the bridge abutments come up through the quay.
##
## The line runs a long way upstream on purpose. From the deck the near quays are
## behind our own parapet — in 07_ribeira the nearest visible water is at about
## z = -66, because everything closer is cut off by the railing at the bottom of
## the frame — so a fleet moored only alongside the near reach is a fleet nobody
## ever sees from the bridge. The near ones still earn their place in the water
## shots, which look along the river rather than across it.
const MOORINGS := [
	Vector2(-104.0, -1.0), Vector2(-92.0, -1.0), Vector2(-81.0, -1.0),
	Vector2(-70.0, -1.0), Vector2(-58.0, -1.0), Vector2(-47.0, -1.0),
	Vector2(-36.0, -1.0), Vector2(-24.0, -1.0), Vector2(-15.5, -1.0),
	Vector2(16.0, -1.0), Vector2(25.0, -1.0),
	Vector2(-98.0, 1.0), Vector2(-86.0, 1.0), Vector2(-74.0, 1.0),
	Vector2(-42.0, 1.0), Vector2(-19.0, 1.0), Vector2(20.0, 1.0),
]


func _build_moored_fleet() -> void:
	var hull_b := MeshBaker.new()
	var canvas_b := MeshBaker.new()
	for spot: Vector2 in MOORINGS:
		var z := spot.x
		var side := spot.y
		# Asked, never assumed. The gorge narrows 0.028 per metre going upstream
		# and each quay wall wanders another metre either way, so at z = -92 the
		# Ribeira face stands at |x| = 49.2 rather than the nominal 52 — and a
		# fleet laid out against 52 is a fleet buried inside the masonry. front_x()
		# is the same query the wall itself was built from, and TerrainBuilder is
		# this stream's own file rather than another subsystem's.
		var face: float = TerrainBuilder.front_x(side, 0, z)
		var x := face - side * (MOORING_STANDOFF + _rng.randf_range(0.0, 0.5))
		var yaw := _rng.randf_range(-0.06, 0.06)
		_build_rabelo(hull_b, canvas_b,
				Transform3D(Basis(Vector3.UP, yaw), Vector3(x, MOORING_Y, z)),
				_rng.randf_range(0.88, 1.12))
	_decor(self, hull_b.commit(ToonFactory.wood(HULL_DARK, 1.4), "MooredHulls", false))
	_decor(self, canvas_b.commit(ToonFactory.cloth(UPPERWORKS, 0.4), "MooredCanvas", false))


## One rabelo: a long shallow hull, the upswept bow and the high stern platform
## the espadela is worked from, a stubby mast, and port pipes on deck.
##
## The upswept ends and the stern platform ARE the silhouette — a rabelo read
## from a bridge is a dark banana with a stack of barrels in it — so those get the
## geometry and the rest is two boxes.
func _build_rabelo(hull: MeshBaker, canvas: MeshBaker, at: Transform3D, scale: float) -> void:
	# 14 m and 3.4 of beam, not the 9 x 2.6 this started at. Two reasons, and the
	# first is that 9 m was simply wrong — a rabelo is a 15-20 m cargo boat, not a
	# skiff. The second is legibility: the nearest moored boat 07_ribeira can see
	# past its own parapet is 90 m out, where a 4.6 m mast is 26 px tall and 0.9 px
	# wide, which is not a boat, it is a scratch on the water.
	var l := 14.0 * scale
	var beam := 3.4 * scale
	hull.add_box(Vector3(beam, 0.78, l * 0.72),
			at * Transform3D(Basis(), Vector3(0.0, -0.10, 0.0)))
	# Bow and stern, raked up out of the water at opposite angles.
	for sz: float in [-1.0, 1.0]:
		hull.add_box(Vector3(beam * 0.74, 0.62, l * 0.30),
				at * Transform3D(Basis(Vector3.RIGHT, sz * 0.30),
					Vector3(0.0, 0.20 * scale, sz * l * 0.45)))
	# Rubbing strake down each side — the line that separates hull from water.
	for sx: float in [-1.0, 1.0]:
		hull.add_box(Vector3(0.14, 0.20, l * 0.74),
				at * Transform3D(Basis(), Vector3(sx * beam * 0.5, 0.24, 0.0)))
	# The stern platform, its trestle, and the steering oar trailing off it.
	hull.add_box(Vector3(beam * 0.62, 0.14, 1.5 * scale),
			at * Transform3D(Basis(), Vector3(0.0, 1.30 * scale, l * 0.36)))
	for sx: float in [-1.0, 1.0]:
		hull.add_beam(at * Vector3(sx * beam * 0.26, 0.28, l * 0.30),
				at * Vector3(sx * beam * 0.26, 1.28 * scale, l * 0.36), 0.10)
	hull.add_beam(at * Vector3(0.0, 1.44 * scale, l * 0.40),
			at * Vector3(0.35, 0.55 * scale, l * 0.66), 0.09)
	# Mast and yard. Sails are furled in port, so the canvas is a bundle on the
	# yard rather than a set square sail — which is also what stops ten moored
	# boats reading as a regatta.
	hull.add_cylinder(0.13 * scale, 7.0 * scale,
			at * Transform3D(Basis(), Vector3(0.0, 3.5 * scale, -l * 0.10)), 6)
	hull.add_box(Vector3(0.16, 0.16, 3.4 * scale),
			at * Transform3D(Basis(), Vector3(0.0, 5.9 * scale, -l * 0.10)))
	canvas.add_box(Vector3(0.52, 0.46, 3.0 * scale),
			at * Transform3D(Basis(), Vector3(0.0, 5.62 * scale, -l * 0.10)))
	# Two rows of pipes on deck. The cargo IS the boat's reason to exist and the
	# reason the hull sits as low as it does.
	for i in 3:
		for sx: float in [-1.0, 1.0]:
			hull.add_cylinder(0.36 * scale, 0.95 * scale,
					at * Transform3D(Basis(Vector3.RIGHT, PI * 0.5),
						Vector3(sx * 0.55 * scale, 0.62 * scale,
							(float(i) - 1.0) * 1.05 * scale)), 7)


# --- Static water surface ----------------------------------------------------

## Everything the water does that is not a boat: the eddy lines breaking off the
## two arch piers, and long slow streaks down the channel that give the reach a
## direction. One bake, one draw call, no animation beyond the shader's own drift.
func _build_surface_foam() -> void:
	var b := MeshBaker.new()

	for sx: float in [-1.0, 1.0]:
		var px := sx * PIER_X
		# The pier stands 14 m along Z in the current. An eddy line peels off each
		# downstream (-Z) corner, a broader patch of disturbed water sits right
		# behind it, and a short standing wave marks the upstream face. The Douro
		# here is a tidal pool, not a race, so all of it is set low in alpha —
		# these are ripple lines, not whitewater.
		for cs in [-1.0, 1.0]:
			_ribbon(b,
				Vector3(px + cs * 1.6, FOAM_Y, -7.0), Vector3(px + cs * 2.4, FOAM_Y, -7.2),
				Vector3(px + cs * 5.4, FOAM_Y, -19.0), Vector3(px + cs * 6.6, FOAM_Y, -19.4))
		_ribbon(b,
			Vector3(px - 2.0, FOAM_Y, -7.2), Vector3(px + 2.0, FOAM_Y, -7.2),
			Vector3(px - 3.2, FOAM_Y, -15.5), Vector3(px + 3.2, FOAM_Y, -15.5))
		_ribbon(b,
			Vector3(px - 2.6, FOAM_Y, 7.6), Vector3(px + 2.6, FOAM_Y, 7.6),
			Vector3(px - 1.8, FOAM_Y, 9.8), Vector3(px + 1.8, FOAM_Y, 9.8))

	# Current streaks: long, thin, near-transparent, all pointing downstream with
	# a few degrees of scatter. Individually invisible; together they are what
	# stops a 900 m plane reading as a sheet of glass.
	for i in 11:
		var cx := _rng.randf_range(-CHANNEL_HALF + 6.0, CHANNEL_HALF - 6.0)
		var cz := _rng.randf_range(-118.0, -22.0)
		var length := _rng.randf_range(26.0, 52.0)
		var width := _rng.randf_range(1.6, 3.4)
		var dx := sin(_rng.randf_range(-0.16, 0.16)) * length
		_ribbon(b,
			Vector3(cx - width * 0.5, FOAM_Y, cz),
			Vector3(cx + width * 0.5, FOAM_Y, cz),
			Vector3(cx + dx - width * 0.35, FOAM_Y, cz - length),
			Vector3(cx + dx + width * 0.35, FOAM_Y, cz - length))

	var mi := b.commit(_foam_material(0.34, Vector2(-0.16, 0.0), 7.0), "SurfaceFoam", false)
	_decor(self, mi)


# --- River mist --------------------------------------------------------------

## A shallow bank of mist lying on the water. Two jobs: it dissolves the far reach
## of the river (a height-limited haze, so the city above it stays crisp — that is
## depth layering rather than a uniform veil), and it is the medium the sun's
## shafts through the arch lattice actually become visible in. The environment's
## global volumetric density is deliberately too low to show shafts on its own.
##
## The box top is at y = -8.9, nine metres under the deck's underside, so it can
## never fog anything the player stands on. height_falloff is left at 0: the
## built-in FogMaterial shader's falloff is measured against the volume's own
## frame in a way this pass cannot verify without a render, and a 7 m box already
## puts the mist where mist goes. edge_fade softens all six faces.
func _build_mist() -> void:
	var mist := FogVolume.new()
	mist.name = "RiverMist"
	mist.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	mist.size = Vector3(300.0, 7.0, 260.0)
	mist.position = Vector3(0.0, WATER_Y + 2.6, -70.0)

	var fog := FogMaterial.new()
	fog.density = mist_density
	fog.albedo = Color(1.0, 0.94, 0.88)
	fog.height_falloff = 0.0
	fog.edge_fade = 0.4
	mist.material = fog
	add_child(mist)


# --- Shared setup ------------------------------------------------------------

## Everything this node builds is decoration: no shadow (nothing below the water
## receives one, and the vessels are past the 100 m directional shadow range
## anyway) and no GI (it all moves, and moving occluders smear the SDFGI cascades).
func _decor(parent: Node3D, mi: MeshInstance3D) -> void:
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	parent.add_child(mi)


# --- Inline shaders ----------------------------------------------------------

## Wingbeat in the vertex stage, so a whole flock is one draw call and the CPU
## only ever writes one transform per bird. Anything with |x| past the body's half
## width is a wing and rotates about the shoulder; the normal is carried through
## the same rotation, without which the wings light as though still flat and the
## beat reads as a shape change rather than a movement.
##
## INSTANCE_CUSTOM.x is the bird's phase and .y its rate variation, both written
## once at build time. If MultiMesh custom data ever fails to reach the shader the
## failure is benign: the flock beats in unison.
const GULL_SHADER := """
shader_type spatial;
render_mode specular_disabled;

uniform vec4 feather_color : source_color = vec4(0.94, 0.94, 0.92, 1.0);
uniform vec4 mantle_color : source_color = vec4(0.62, 0.66, 0.70, 1.0);
uniform vec4 tip_color : source_color = vec4(0.20, 0.21, 0.24, 1.0);
uniform float body_half = 0.07;
uniform float flap_rate = 4.4;
uniform float flap_amount = 0.62;
uniform float flap_bias = 0.10;
uniform float tip_start = 0.42;
uniform float tip_blend = 0.13;

varying float v_span;

void vertex() {
	float s = sign(VERTEX.x);
	float span = abs(VERTEX.x) - body_half;
	v_span = max(span, 0.0);
	if (span > 0.0) {
		float phase = INSTANCE_CUSTOM.x * 6.2831853
				+ TIME * flap_rate * (0.82 + 0.36 * INSTANCE_CUSTOM.y);
		float ang = flap_bias + sin(phase) * flap_amount;
		float ca = cos(ang);
		float sa = sin(ang);
		float u = span;
		float v = VERTEX.y;
		VERTEX.x = s * (body_half + u * ca - v * sa);
		VERTEX.y = u * sa + v * ca;
		float nu = s * NORMAL.x;
		float nv = NORMAL.y;
		NORMAL = vec3(s * (nu * ca - nv * sa), nu * sa + nv * ca, NORMAL.z);
	}
}

void fragment() {
	// Grey mantle over the inner wing, near-black primaries at the tips. Those
	// two marks are what make a white blob read as a gull at a hundred metres.
	float tip = smoothstep(tip_start, tip_start + tip_blend, v_span);
	float mantle = smoothstep(0.02, 0.16, v_span) * (1.0 - tip);
	ALBEDO = mix(mix(feather_color.rgb, mantle_color.rgb, mantle * 0.7), tip_color.rgb, tip);
	ROUGHNESS = 0.85;
	SPECULAR = 0.15;
}
"""

## Foam ribbons: wakes, pier eddies, current streaks. Unshaded because foam is a
## dense scatterer that stays bright even out of the sun, and because it saves
## every one of these ribbons a lighting pass. depth_draw_never keeps them out of
## the depth buffer, so a wake crossing a wake blends instead of z-fighting.
##
## UV.x runs 0 at the head to 1 at the tail and UV.y across, whatever the quad's
## real size — MeshBaker is handed a (1, 1) extent for exactly that reason — so one
## material drives ribbons from 2 m to 90 m long.
const FOAM_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform vec4 foam_color : source_color = vec4(0.92, 0.85, 0.76, 1.0);
uniform float foam_alpha : hint_range(0.0, 1.0) = 0.45;
uniform vec2 drift = vec2(-0.22, 0.0);
uniform float streak_freq = 9.0;
uniform float head_fade : hint_range(0.005, 1.0) = 0.09;
uniform float tail_fade : hint_range(0.0, 1.0) = 0.62;
uniform float edge_soft : hint_range(0.0, 1.0) = 0.30;

void fragment() {
	float along = clamp(UV.x, 0.0, 1.0);
	float across = abs(UV.y * 2.0 - 1.0);
	// Feather all four edges to nothing, so the quad itself is never a shape.
	float edge = 1.0 - smoothstep(edge_soft, 1.0, across);
	float head = smoothstep(0.0, head_fade, along);
	float tail = 1.0 - smoothstep(1.0 - tail_fade, 1.0, along);
	// Two beat frequencies, one warped by the other, so the foam churns rather
	// than scrolling as a barcode. Negative drift.x sends it aft.
	vec2 p = UV + drift * TIME;
	float streak = 0.55 + 0.45 * sin(p.x * streak_freq + sin(p.y * 5.3) * 1.7);
	streak *= 0.62 + 0.38 * sin(p.x * streak_freq * 2.3 - p.y * 3.1 + 1.9);
	ALBEDO = foam_color.rgb;
	ALPHA = clamp(edge * head * tail * streak * foam_alpha, 0.0, 1.0);
}
"""

static var _gull_shader: Shader
static var _foam_shader: Shader
static var _gull_mat: ShaderMaterial


func _gull_material() -> ShaderMaterial:
	if _gull_mat == null:
		if _gull_shader == null:
			_gull_shader = Shader.new()
			_gull_shader.code = GULL_SHADER
		_gull_mat = ShaderMaterial.new()
		_gull_mat.shader = _gull_shader
	return _gull_mat


## Foam materials differ only in three uniforms, but a ShaderMaterial is per
## parameter set, so wakes and static ripples are two of them. Both share the one
## compiled Shader, which is what the driver actually cares about.
func _foam_material(alpha: float, drift: Vector2, freq: float) -> ShaderMaterial:
	if _foam_shader == null:
		_foam_shader = Shader.new()
		_foam_shader.code = FOAM_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = _foam_shader
	mat.set_shader_parameter("foam_alpha", alpha)
	mat.set_shader_parameter("drift", drift)
	mat.set_shader_parameter("streak_freq", freq)
	return mat
