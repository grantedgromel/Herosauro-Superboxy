extends Node3D
## BridgeArena: the playable Dom Luís I bridge over the Douro.
##
## The .tscn holds only the deck mass and its one big collider, the sun, the
## river and the sky. Everything else the hero can stand on, walk into or fall
## off is assembled here from the cross-section constants below, so the whole
## road section is one place to read and one place to edit.
##
## The deck used to be a single 100x2x12 box. Under the old fixed camera that was
## enough; at third-person eye level it read as a featureless plane. It is now a
## real bridge section: a dark granite carriageway either side of a sunken tram
## bed with two flush rails, pale kerbs on the arena edge line, raised flagstone
## walkways, and an iron parapet of balusters standing on a granite plinth. Under
## the deck hangs the iconic single steel arch, its X-braced lattice truss and a
## second chord — pure decoration, as before.
##
## COLLISION CONTRACT — layer 1 (world), which the camera's SpringArm also sweeps:
##
##   Solid, one simple primitive each: the deck slab (in the .tscn), the
##   kerb/walkway step, the parapets, the end abutments, the arch's springing
##   piers, the lampposts.
##
##   Deliberately NOT solid: the arch ribs, the lattice, the second chord, the
##   individual balusters, the fascia girders, the tram rails and everything
##   flush with the deck. The parapet's single box stands in for its ~320
##   balusters on purpose — a swept sphere catching on each bar in turn is
##   exactly what makes a third-person camera chatter, and a railing the player
##   cannot walk through the gaps of is what a railing is anyway.

# --- Deck cross-section ------------------------------------------------------
# Every Z is a half-width from the bridge centreline, every Y is absolute.
# DECK_TOP must stay at 2.0: main.gd drops the hero above it and prop_spawner.gd
# settles the barrels onto it.

const DECK_LENGTH := 100.0        # x in [-50, 50]
const DECK_HALF_WIDTH := 7.0      # z in [-7, 7]
const DECK_TOP := 2.0
const DECK_BOTTOM := 0.0
## Top of the structural mass in the .tscn. The 4 cm between it and DECK_TOP is
## the depth every paving seam reveals, so the deck reads as laid courses rather
## than as one poured plane.
const STRUCTURE_TOP := 1.96

## The kerb line is deliberately adamastor.gd's ARENA_Z. Every raised surface on
## the bridge is therefore outside the fighting corridor, and the corridor itself
## is one dead-flat plane from kerb to kerb.
const ROADWAY_HALF := 5.0
const KERB_WIDTH := 0.30
## 13 cm. Against the hero's 0.45 m capsule the kerb corner presents a ~43 deg
## contact normal, inside PlayerBase.FLOOR_MAX_ANGLE_DEG (50), so it is a step
## you walk up rather than a wall you stick to. Raising it past ~0.17 flips that.
const KERB_RISE := 0.13
const WALKWAY_TOP := DECK_TOP + KERB_RISE
## Where the pavement stops and the parapet stands.
const WALKWAY_OUTER := 6.55
const PARAPET_THICKNESS := DECK_HALF_WIDTH - WALKWAY_OUTER
const PARAPET_MID := (WALKWAY_OUTER + DECK_HALF_WIDTH) * 0.5
const PLINTH_TOP := 2.55          # granite base course under the ironwork
const HANDRAIL_TOP := 3.50        # ~1.37 m over the pavement: chest height, see-over
const MIDRAIL_Y := 2.98

## Metro tramway down the middle. The rail heads sit exactly at DECK_TOP so there
## is nothing to catch on, and the bed is sunk 2 cm so the rails read as rails.
const TRAM_HALF := 1.75
const TRAM_TOP := DECK_TOP - 0.02
const RAIL_GAUGE_HALF := 0.72     # 1.44 m gauge
const RAIL_HEAD := 0.08
const SLEEPER_PITCH := 1.0

# --- Course pitches ----------------------------------------------------------
const BAY_PITCH := 2.5            # deck plates along the carriageway
const BAY_SEAM := 0.06
const FLAG_PITCH := 1.25          # kerbstones and pavement flags
const FLAG_SEAM := 0.05
const KERB_JOINT := 0.03
const BALUSTER_PITCH := 0.62
const POST_PITCH := 5.0           # heavy parapet posts; lamp stations stand on these

## Flush expansion-joint plates: over both piers, over the arch crown, and at the
## quarter points. Purely visual — the deck collider runs straight through them.
const JOINT_XS := [-47.0, -24.0, 0.0, 24.0, 47.0]

# --- Bridge ends -------------------------------------------------------------
# The deck stops dead at x = +-50 and the banks are 30 m further out, so without
# something here the player walks off into a void or into an invisible wall.
# Instead the deck runs into a granite abutment block that rises just clear of
# the parapet: a real thing to collide with, at both ends, cheap and honest.

const ABUTMENT_INNER := 49.5      # overlaps the deck by half a metre, no seam
const ABUTMENT_LENGTH := 9.0
const ABUTMENT_DEPTH := 15.0
const ABUTMENT_TOP := HANDRAIL_TOP + 0.10
const ABUTMENT_BOTTOM := -16.4    # buried well under the river plane at y = -15

# --- The arch ----------------------------------------------------------------

const ARCH_SPAN := 92.0           # horizontal reach of the arch (x in [-46, 46])
const ARCH_RISE := 18.0           # how far the arch drops below the deck
const ARCH_SEGMENTS := 24         # straight beam segments approximating the curve
## The ribs run under the kerb line, which is where a deck's main girders belong:
## they carry the parapet and pavement loads straight down into the arch.
const RIB_HALF := 5.0
const PIER_X := ARCH_SPAN * 0.5 + 1.0

# --- Lampposts ---------------------------------------------------------------

## Four stations, a lamp on each parapet at every one: eight globes, which is
## exactly LightingRig.LAMP_BUDGET. A ninth would be built and then silently get
## no OmniLight3D, so this list must not grow past four. The stations land on
## POST_PITCH multiples so every lamp stands on a heavy parapet post.
const LAMP_XS := [-30.0, -10.0, 10.0, 30.0]
const LAMP_BASE_Y := HANDRAIL_TOP
const LAMP_GLOBE_Y := HANDRAIL_TOP + 3.0

# --- Palette -----------------------------------------------------------------
# The deck's whole job at eye level is a light/dark read: near-black roadway,
# pale kerb and flags, near-black ironwork. Values run low on purpose — the key
# is 2.4 energy of warm sun and, on an up-facing plane, anything much over 0.6
# albedo clips to cream through AgX before any of this detail can show.

const ROADWAY_COLOR := Color(0.325, 0.315, 0.300)
const TRAMBED_COLOR := Color(0.235, 0.225, 0.215)
const MORTAR_COLOR := Color(0.300, 0.290, 0.275)
const KERB_COLOR := Color(0.580, 0.560, 0.510)
const FLAG_COLOR := Color(0.545, 0.525, 0.485)
const PLINTH_COLOR := Color(0.500, 0.480, 0.440)
const ABUTMENT_COLOR := Color(0.470, 0.450, 0.410)
const IRONWORK_COLOR := Color(0.210, 0.230, 0.260)
const RAILHEAD_COLOR := Color(0.520, 0.500, 0.460)
const SLEEPER_COLOR := Color(0.190, 0.160, 0.130)
const JOINT_COLOR := Color(0.340, 0.330, 0.310)
const STEEL_COLOR := Color(0.400, 0.430, 0.470)
const DARK_STEEL_COLOR := Color(0.280, 0.300, 0.340)
const LAMP_IRON_COLOR := Color(0.200, 0.220, 0.260)


func _ready() -> void:
	_build_roadway()
	_build_tramway()
	_build_footways()
	_build_parapets()
	_build_ends()
	_build_arch()
	_build_lattice()
	_build_lamps()


# --- Roadway -----------------------------------------------------------------

## Deck plates: four columns of granite bays, two per carriageway, running from
## the tram bed out to the kerb. The 6 cm seams drop to STRUCTURE_TOP, so at the
## sun's 11.5 degrees each course throws a hand's width of shadow onto the next —
## which is the whole difference between a road and a grey rectangle.
func _build_roadway() -> void:
	var deck := Node3D.new()
	deck.name = "Roadway"
	add_child(deck)

	var paving := SceneryKit.world_mapped(ToonFactory.stone(ROADWAY_COLOR, 2.6))
	var lane := (ROADWAY_HALF - TRAM_HALF) * 0.5
	var bay := Vector3(BAY_PITCH - BAY_SEAM, DECK_TOP - STRUCTURE_TOP + 0.06, lane - BAY_SEAM)
	var bays: Array[Vector3] = []
	for side in [-1.0, 1.0]:
		for slot in [0.5, 1.5]:
			var z: float = side * (TRAM_HALF + slot * lane)
			for x in _course_line(BAY_PITCH):
				bays.append(Vector3(x, DECK_TOP - bay.y * 0.5, z))
	SceneryKit.repeat(deck, "Paving", bay, bays, paving)

	# Expansion joints. 5 mm proud so they sit on top of the bays rather than
	# disappearing into a seam; nobody trips on 5 mm and the collider is flat.
	var joint := ToonFactory.iron(JOINT_COLOR, 0.8, 0.6, 0.55)
	for jx in JOINT_XS:
		SceneryKit.box(deck, "ExpansionJoint", Vector3(0.40, 0.14, ROADWAY_HALF * 2.0),
				Vector3(jx, DECK_TOP + 0.005 - 0.07, 0.0), joint)


# --- Tramway -----------------------------------------------------------------

## The metro track the real upper deck carries: a sunken sett bed, sleepers just
## breaking its surface, and two rails whose heads are exactly flush with the
## paving. Two bright parallel lines down a hundred metres of dark granite are
## the strongest perspective cue on the whole bridge.
func _build_tramway() -> void:
	var tram := Node3D.new()
	tram.name = "Tramway"
	add_child(tram)

	SceneryKit.box(tram, "TrackBed", Vector3(DECK_LENGTH, 0.12, TRAM_HALF * 2.0),
			Vector3(0.0, TRAM_TOP - 0.06, 0.0),
			SceneryKit.world_mapped(ToonFactory.cobblestone(TRAMBED_COLOR, 1.0)))

	var sleeper := Vector3(0.24, 0.06, TRAM_HALF * 1.3)
	var sleepers: Array[Vector3] = []
	for x in _course_line(SLEEPER_PITCH):
		sleepers.append(Vector3(x, TRAM_TOP + 0.005 - sleeper.y * 0.5, 0.0))
	var ties := SceneryKit.repeat(tram, "Sleepers", sleeper, sleepers,
			ToonFactory.wood(SLEEPER_COLOR, 0.5))
	if ties != null:
		# A hundred creosoted timbers sunk 1.5 cm into their own bed cannot cast a
		# shadow anyone will see, and they are too thin to help SDFGI.
		ties.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ties.gi_mode = GeometryInstance3D.GI_MODE_DISABLED

	# Polished heads: low roughness, high metallic, so the low sun runs a hot
	# specular line down each rail instead of leaving them flat grey.
	var steel := ToonFactory.iron(RAILHEAD_COLOR, 1.0, 0.85, 0.26)
	for side in [-1.0, 1.0]:
		SceneryKit.box(tram, "Rail", Vector3(DECK_LENGTH, 0.10, RAIL_HEAD),
				Vector3(0.0, DECK_TOP - 0.05, side * RAIL_GAUGE_HALF), steel)


# --- Kerbs and walkways ------------------------------------------------------

## Pale granite kerbstones on the arena edge line, then a raised flagstone
## pavement out to the parapet. Both are laid as discrete stones with real
## joints; the whole step is one collider box per side, so the player walks up a
## clean 13 cm edge and never feels the joints at all.
func _build_footways() -> void:
	var walk := Node3D.new()
	walk.name = "Footways"
	add_child(walk)

	var kerb_mat := SceneryKit.world_mapped(ToonFactory.stone(KERB_COLOR, 1.5))
	var flag_mat := SceneryKit.world_mapped(ToonFactory.cobblestone(FLAG_COLOR, 0.85))
	var bed_mat := SceneryKit.world_mapped(ToonFactory.stone(MORTAR_COLOR, 1.2))

	var step_width := WALKWAY_OUTER - ROADWAY_HALF
	var step_mid := (ROADWAY_HALF + WALKWAY_OUTER) * 0.5
	var flag_width := step_width - KERB_WIDTH
	var flag_mid := ROADWAY_HALF + KERB_WIDTH + flag_width * 0.5
	var kerb_mid := ROADWAY_HALF + KERB_WIDTH * 0.5
	var bed_top := WALKWAY_TOP - 0.05

	var kerb_size := Vector3(FLAG_PITCH - KERB_JOINT, 0.34, KERB_WIDTH)
	var flag_size := Vector3(FLAG_PITCH - FLAG_SEAM, 0.10, flag_width - FLAG_SEAM)
	var kerbs: Array[Vector3] = []
	var flags: Array[Vector3] = []
	var xs := _course_line(FLAG_PITCH)

	for side in [-1.0, 1.0]:
		# Bedding course under the lot, so a joint reads as a 5 cm groove instead
		# of a slot dropping 17 cm into the dark of the deck mass.
		SceneryKit.box(walk, "FootwayBed", Vector3(DECK_LENGTH, 0.14, step_width),
				Vector3(0.0, bed_top - 0.07, side * step_mid), bed_mat)
		for x in xs:
			kerbs.append(Vector3(x, WALKWAY_TOP - kerb_size.y * 0.5, side * kerb_mid))
			flags.append(Vector3(x, WALKWAY_TOP - flag_size.y * 0.5, side * flag_mid))
		# One box for the kerb face and the pavement behind it.
		SceneryKit.solid(walk, "FootwayBody", Vector3(DECK_LENGTH, KERB_RISE, step_width),
				Vector3(0.0, DECK_TOP + KERB_RISE * 0.5, side * step_mid))

	SceneryKit.repeat(walk, "Kerbstones", kerb_size, kerbs, kerb_mat)
	SceneryKit.repeat(walk, "Flagstones", flag_size, flags, flag_mat)


# --- Parapets ----------------------------------------------------------------

## Granite plinth, wrought-iron balusters between a mid and a top rail, heavy
## posts every POST_PITCH. Replaces the two solid 2 m walls the deck used to be
## fenced with: at eye level a blank wall hid the river, and the baluster gaps
## are what let the golden hour through onto the pavement.
func _build_parapets() -> void:
	var rails := Node3D.new()
	rails.name = "Parapets"
	add_child(rails)

	var plinth_mat := SceneryKit.world_mapped(ToonFactory.stone(PLINTH_COLOR, 2.0))
	# Painted cast iron: barely metallic, satin, near-black. Raw steel here reads
	# as chrome the moment the sun catches a hundred metres of handrail.
	var iron := ToonFactory.iron(IRONWORK_COLOR, 1.0, 0.30, 0.48)
	var girder := ToonFactory.iron(STEEL_COLOR, 1.6)

	var bars: Array[Vector3] = []
	var posts: Array[Vector3] = []
	var bar_size := Vector3(0.06, 3.38 - PLINTH_TOP, 0.06)
	var post_size := Vector3(0.17, HANDRAIL_TOP + 0.05 - (PLINTH_TOP - 0.05), 0.17)

	for side in [-1.0, 1.0]:
		var z: float = side * PARAPET_MID
		# Rooted in the deck mass rather than perched on the pavement, so no gap
		# opens under it where the flagstones stop.
		SceneryKit.box(rails, "Plinth", Vector3(DECK_LENGTH, PLINTH_TOP - STRUCTURE_TOP, PARAPET_THICKNESS),
				Vector3(0.0, (PLINTH_TOP + STRUCTURE_TOP) * 0.5, z), plinth_mat)
		SceneryKit.box(rails, "MidRail", Vector3(DECK_LENGTH, 0.07, PARAPET_THICKNESS * 0.5),
				Vector3(0.0, MIDRAIL_Y, z), iron)
		SceneryKit.box(rails, "HandRail", Vector3(DECK_LENGTH, 0.12, PARAPET_THICKNESS * 0.78),
				Vector3(0.0, HANDRAIL_TOP - 0.06, z), iron)

		# The deck's edge girder and its bottom flange, riding just proud of the
		# fascia. Below the pavement and outside every reachable surface, so no
		# collider: the camera would only ever scrape along them.
		SceneryKit.box(rails, "EdgeGirder", Vector3(DECK_LENGTH, 0.62, 0.30),
				Vector3(0.0, DECK_BOTTOM + 0.31, side * (DECK_HALF_WIDTH - 0.10)), girder)
		SceneryKit.box(rails, "GirderFlange", Vector3(DECK_LENGTH, 0.14, 0.52),
				Vector3(0.0, DECK_BOTTOM + 0.07, side * (DECK_HALF_WIDTH - 0.16)), girder)

		for x in _centred_line(BALUSTER_PITCH):
			bars.append(Vector3(x, PLINTH_TOP + bar_size.y * 0.5, z))
		for x in _centred_line(POST_PITCH):
			posts.append(Vector3(x, PLINTH_TOP - 0.05 + post_size.y * 0.5, z))

		# The whole parapet as one box, from the pavement to the handrail. See the
		# collision contract at the top of the file for why it is not per-baluster.
		SceneryKit.solid(rails, "ParapetBody", Vector3(DECK_LENGTH, HANDRAIL_TOP - DECK_TOP, PARAPET_THICKNESS),
				Vector3(0.0, (HANDRAIL_TOP + DECK_TOP) * 0.5, z))

	var baluster_batch := SceneryKit.repeat(rails, "Balusters", bar_size, bars, iron)
	if baluster_batch != null:
		# Shadows stay on — 300 bars striping the pavement at 11.5 degrees is the
		# single best thing the parapet does. GI comes off: 6 cm rods are far under
		# an SDFGI cascade-0 cell and only ever add leak noise.
		baluster_batch.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	SceneryKit.repeat(rails, "ParapetPosts", post_size, posts, iron)


# --- Bridge ends -------------------------------------------------------------

## A granite abutment at each end, rising just past the handrail so the deck
## visibly terminates in masonry the player can walk into. The sides stay open:
## going over the parapet is a deliberate fall, which PlayerBase already handles.
func _build_ends() -> void:
	var ends := Node3D.new()
	ends.name = "Abutments"
	add_child(ends)

	var granite := SceneryKit.world_mapped(ToonFactory.stone(ABUTMENT_COLOR, 3.2))
	var coping := SceneryKit.world_mapped(ToonFactory.stone(KERB_COLOR, 1.6))
	var height := ABUTMENT_TOP - ABUTMENT_BOTTOM
	var mid_y := (ABUTMENT_TOP + ABUTMENT_BOTTOM) * 0.5
	var mid_x := ABUTMENT_INNER + ABUTMENT_LENGTH * 0.5
	var mass := Vector3(ABUTMENT_LENGTH, height, ABUTMENT_DEPTH)

	for sx in [-1.0, 1.0]:
		var x: float = sx * mid_x
		SceneryKit.box(ends, "Abutment", mass, Vector3(x, mid_y, 0.0), granite)
		# Two projecting bands — a coping at the top and a cornice on the deck
		# line. They only overhang in Z, where they are seen from; overhanging in
		# X would put stone in front of the collider face the player stops at.
		SceneryKit.box(ends, "AbutmentCoping", Vector3(ABUTMENT_LENGTH, 0.40, ABUTMENT_DEPTH + 0.5),
				Vector3(x, ABUTMENT_TOP - 0.20, 0.0), coping)
		SceneryKit.box(ends, "AbutmentCornice", Vector3(ABUTMENT_LENGTH, 0.45, ABUTMENT_DEPTH + 0.8),
				Vector3(x, DECK_TOP - 0.30, 0.0), coping)
		SceneryKit.solid(ends, "AbutmentBody", mass, Vector3(x, mid_y, 0.0))


# --- The iconic arch ---------------------------------------------------------

func _build_arch() -> void:
	var arch := Node3D.new()
	arch.name = "Arch"
	add_child(arch)

	var steel := ToonFactory.iron(STEEL_COLOR)             # weathered iron grey
	var dark_steel := ToonFactory.iron(DARK_STEEL_COLOR)

	# Two parallel arch ribs, one under each kerb line, built from short straight
	# beam segments following a parabola that dips below the deck.
	for z_side in [-RIB_HALF, RIB_HALF]:
		var prev := _arch_point(-1.0, z_side)
		for i in range(ARCH_SEGMENTS + 1):
			var t := -1.0 + 2.0 * float(i) / float(ARCH_SEGMENTS)
			var p := _arch_point(t, z_side)
			if i > 0:
				_beam_between(arch, prev, p, 1.0, steel)   # thicker, bolder single arch
			prev = p

	# A few clean spandrel posts tying the arch up to the deck (sparse, not a thicket).
	for z_side in [-RIB_HALF, RIB_HALF]:
		for i in [4, 8, 12, 16, 20]:
			var t := -1.0 + 2.0 * float(i) / float(ARCH_SEGMENTS)
			var bottom := _arch_point(t, z_side)
			var top := Vector3(bottom.x, DECK_BOTTOM, z_side)
			if top.y - bottom.y > 0.8:
				_beam_between(arch, bottom, top, 0.3, dark_steel)

	# Two stout stone-grey piers where the arch springs off the bank. Solid: a
	# hero knocked over the parapet near the ends can land on one, and a mesh he
	# falls straight through is exactly the clipping this pass is meant to kill.
	var pier_mass := Vector3(4.0, ARCH_RISE + 6.0, DECK_HALF_WIDTH * 2.0)
	var pier_y := DECK_BOTTOM - pier_mass.y * 0.5
	var pier_body := StaticBody3D.new()
	pier_body.name = "PierBodies"
	pier_body.collision_layer = PhysicsLayers.WORLD
	pier_body.collision_mask = 0
	arch.add_child(pier_body)
	for sx in [-1.0, 1.0]:
		var pos := Vector3(sx * PIER_X, pier_y, 0.0)
		SceneryKit.box(arch, "Pier", pier_mass, pos, ToonFactory.stone(Color(0.52, 0.50, 0.47), 3.0))
		SceneryKit.solid_shape(pier_body, pier_mass, pos)


## A point on the arch rib for parameter t in [-1, 1] at a given z.
func _arch_point(t: float, z: float) -> Vector3:
	var x := t * ARCH_SPAN * 0.5
	# Parabola: 0 at the ends, -ARCH_RISE at the centre, all below the deck.
	var y := DECK_BOTTOM - ARCH_RISE * (1.0 - t * t)
	return Vector3(x, y, z)


## Spawn a thin box "beam" spanning from a to b with the given thickness.
func _beam_between(parent: Node3D, a: Vector3, b: Vector3, thickness: float, mat: Material) -> void:
	var beam := MeshInstance3D.new()
	beam.name = "Beam"
	var length := a.distance_to(b)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(length, thickness, thickness)
	beam.mesh = mesh
	beam.material_override = mat
	beam.position = (a + b) * 0.5

	# Orient the beam's local +X (its long axis) along (b - a).
	var dir := (b - a).normalized()
	if dir.length() > 0.001:
		var yaw := atan2(-dir.z, Vector2(dir.x, dir.z).length())
		var pitch := atan2(dir.y, Vector2(dir.x, dir.z).length())
		beam.rotation = Vector3(0.0, yaw, pitch)
	parent.add_child(beam)


# --- Lattice bracing ---------------------------------------------------------

## X-cross-braces between the two ribs plus a raised second chord riding each
## rib, so the arch reads as the Dom Luís I deep lattice truss instead of two
## lone parabolas. Non-colliding by contract: the camera swings through here.
func _build_lattice() -> void:
	var lattice := Node3D.new()
	lattice.name = "Lattice"
	add_child(lattice)

	var steel := ToonFactory.iron(STEEL_COLOR)
	# Braces live in the deck's shadow, lit almost entirely by bounce off the
	# river, so they get a duller, less metallic iron than the sunlit ribs.
	var brace := ToonFactory.iron(DARK_STEEL_COLOR, 1.6, 0.35, 0.72)

	# X-braces between the ribs, every third segment.
	for i in range(3, ARCH_SEGMENTS - 2, 3):
		var t0 := -1.0 + 2.0 * float(i) / float(ARCH_SEGMENTS)
		var t1 := -1.0 + 2.0 * float(i + 2) / float(ARCH_SEGMENTS)
		_beam_between(lattice, _arch_point(t0, -RIB_HALF), _arch_point(t1, RIB_HALF), 0.22, brace)
		_beam_between(lattice, _arch_point(t0, RIB_HALF), _arch_point(t1, -RIB_HALF), 0.22, brace)

	# The second chord rides 2 units above the main rib across the middle span,
	# thickening the arch into the truss band you see from the river.
	for z_side in [-RIB_HALF, RIB_HALF]:
		var prev := _arch_point(-0.8, z_side) + Vector3(0.0, 2.0, 0.0)
		for i in range(1, 13):
			var t := lerpf(-0.8, 0.8, float(i) / 12.0)
			var p := _arch_point(t, z_side) + Vector3(0.0, 2.0, 0.0)
			_beam_between(lattice, prev, p, 0.5, steel)
			prev = p


# --- Lampposts ---------------------------------------------------------------

func _build_lamps() -> void:
	var lamps := Node3D.new()
	lamps.name = "Lamps"        # LightingRig.LAMP_GROUP_NAME — do not rename alone
	add_child(lamps)

	var iron := ToonFactory.iron(LAMP_IRON_COLOR, 0.8, 0.2, 0.45)
	for x in LAMP_XS:
		for side in [-1.0, 1.0]:
			_lamp(lamps, x, side * PARAPET_MID, iron)

	# Capsules, and all eight on one body: a swept-sphere SpringArm glides around
	# a capsule where it snags on the corners of a box, and one body means one
	# broadphase pair instead of eight.
	var poles := StaticBody3D.new()
	poles.name = "LampBodies"
	poles.collision_layer = PhysicsLayers.WORLD
	poles.collision_mask = 0
	lamps.add_child(poles)
	var span := LAMP_GLOBE_Y + 0.1 - LAMP_BASE_Y
	for x in LAMP_XS:
		for side in [-1.0, 1.0]:
			var capsule := CapsuleShape3D.new()
			capsule.radius = 0.13
			capsule.height = span
			var cs := CollisionShape3D.new()
			cs.shape = capsule
			cs.position = Vector3(x, LAMP_BASE_Y + span * 0.5, side * PARAPET_MID)
			poles.add_child(cs)


## One dusk lamppost standing on the parapet: cast-iron base, slim pole, warm
## globe, spiked cap.
##
## Every part is added FLAT under `parent`, and the globe is the only SphereMesh.
## Both are load-bearing: lighting_rig.gd finds the practicals by scanning this
## node's direct children for a SphereMesh, so nesting the parts would leave the
## bridge unlit, and a second sphere anywhere here (a finial, a lantern shell)
## would burn one of the eight OmniLight3D slots on it.
func _lamp(parent: Node3D, x: float, z: float, iron: Material) -> void:
	SceneryKit.box(parent, "LampBase", Vector3(0.34, 0.22, 0.34), Vector3(x, LAMP_BASE_Y + 0.11, z), iron)
	SceneryKit.cylinder(parent, "LampPole", 0.055, 0.075, 2.60, Vector3(x, LAMP_BASE_Y + 1.52, z), iron)
	SceneryKit.cylinder(parent, "LampCollar", 0.11, 0.11, 0.10, Vector3(x, LAMP_GLOBE_Y - 0.23, z), iron)

	var globe := MeshInstance3D.new()
	globe.name = "LampGlobe"
	var globe_mesh := SphereMesh.new()
	globe_mesh.radius = 0.19
	globe_mesh.height = 0.38
	globe_mesh.radial_segments = 10
	globe_mesh.rings = 5
	globe.mesh = globe_mesh
	globe.position = Vector3(x, LAMP_GLOBE_Y, z)
	# Emission energy carries into the HDR buffer under Forward+, so the globe
	# blooms rather than clipping to a flat white blob.
	globe.material_override = ToonFactory.glow(Color(1.0, 0.85, 0.55), 2.2)
	parent.add_child(globe)

	SceneryKit.cylinder(parent, "LampCap", 0.03, 0.16, 0.22, Vector3(x, LAMP_GLOBE_Y + 0.21, z), iron)


# --- Layout helpers ----------------------------------------------------------

## Course centres along the deck, first and last half a pitch in from the ends so
## no paving stone hangs over the abutment face. For laid courses.
func _course_line(pitch: float) -> Array[float]:
	var out: Array[float] = []
	var count := int(DECK_LENGTH / pitch)
	var start := -DECK_LENGTH * 0.5 + pitch * 0.5
	for i in count:
		out.append(start + float(i) * pitch)
	return out


## Centres on a symmetric ladder through x = 0. For structure — parapet posts,
## and the lamp stations that stand on them — which wants a member on the
## centreline and one at each end, not a course offset half a bay.
func _centred_line(pitch: float) -> Array[float]:
	var out: Array[float] = []
	var count := int(DECK_LENGTH * 0.5 / pitch)
	for i in range(-count, count + 1):
		out.append(float(i) * pitch)
	return out
