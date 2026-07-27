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

const IronworkScript := preload("res://scripts/world/bridge_ironwork.gd")

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
## Sits on BridgeIronwork.RAIL_TOP, not HANDRAIL_TOP. The ironwork's parapet
## tops out at 3.33 — its plinth is deliberately lower than the 2.55 used here so
## a 1.20 m railing has room for a readable lattice band — so keying the lamps to
## 3.50 would leave all eight floating 17 cm above their posts.
const LAMP_BASE_Y := 3.33
const LAMP_GLOBE_Y := LAMP_BASE_Y + 3.0

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
	_build_arch_foundations()
	IronworkScript.attach(self)
	_build_lamps()


# --- Roadway -----------------------------------------------------------------

## Deck plates: four columns of granite bays, two per carriageway, running from
## the tram bed out to the kerb. The 6 cm-wide seams between them drop 4 cm to
## STRUCTURE_TOP, so at the sun's 11.5 degrees every course throws a hand's width
## of shadow across the next — which is the whole difference between a road and a
## grey rectangle, and it costs one draw call for all 160 slabs.
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

	# Collision is the pavement slab plus a short ramp buried inside the
	# kerbstones. The step has to be climbable by two very different bodies: the
	# hero's capsule rolls up a 13 cm edge at ~43 degrees and is fine, but
	# CharacterBody3D has no step offset and Adamastor's collider is a BOX, for
	# which any vertical face is a wall. Left as a plain step the kerb fenced the
	# giant two metres short of the parapet, which handed the player a safe ledge
	# running the length of the bridge. The ramp lies entirely inside the
	# kerbstone's own footprint, so the worst the mismatch costs is the hero's
	# feet sinking a few centimetres into a stone he is in the act of stepping on.
	var ramp_angle := atan(KERB_RISE / KERB_WIDTH)
	var ramp_size := Vector3(DECK_LENGTH, 0.5,
			sqrt(KERB_WIDTH * KERB_WIDTH + KERB_RISE * KERB_RISE))
	# Slide the box back along its own tilted up axis, so its TOP face is the ramp
	# and runs from the roadway at DECK_TOP up to the pavement at WALKWAY_TOP.
	var ramp_up := Vector3(0.0, cos(ramp_angle), -sin(ramp_angle))
	var ramp_pos := Vector3(0.0, DECK_TOP + KERB_RISE * 0.5, kerb_mid) - ramp_up * ramp_size.y * 0.5
	var flat_inner := ROADWAY_HALF + KERB_WIDTH
	var flat_width := WALKWAY_OUTER - flat_inner

	for side in [-1.0, 1.0]:
		# Bedding course under the lot, so a joint reads as a 5 cm groove instead
		# of a slot dropping 17 cm into the dark of the deck mass.
		SceneryKit.box(walk, "FootwayBed", Vector3(DECK_LENGTH, 0.14, step_width),
				Vector3(0.0, bed_top - 0.07, side * step_mid), bed_mat)
		for x in xs:
			kerbs.append(Vector3(x, WALKWAY_TOP - kerb_size.y * 0.5, side * kerb_mid))
			flags.append(Vector3(x, WALKWAY_TOP - flag_size.y * 0.5, side * flag_mid))

		var body := SceneryKit.solid(walk, "FootwayBody",
				Vector3(DECK_LENGTH, KERB_RISE, flat_width),
				Vector3(0.0, DECK_TOP + KERB_RISE * 0.5, side * (flat_inner + flat_width * 0.5)))
		SceneryKit.solid_shape(body, ramp_size,
				Vector3(ramp_pos.x, ramp_pos.y, ramp_pos.z * side),
				Vector3(-ramp_angle * side, 0.0, 0.0))

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

	# The parapet's MESH — plinth, rails, balusters, posts, edge girder — is built
	# by BridgeIronwork now, as one riveted lattice run rather than a handrail on
	# sticks. What stays here is the collider, because that is this file's job.
	#
	# One box per side from pavement to handrail, standing in for ~320 balusters.
	# See the collision contract at the top of the file: a swept camera sphere
	# catching on each bar in turn is exactly what makes a third-person camera
	# chatter, and a railing you cannot squeeze between the bars of is what a
	# railing is anyway.
	for side in [-1.0, 1.0]:
		SceneryKit.solid(rails, "ParapetBody", Vector3(DECK_LENGTH, HANDRAIL_TOP - DECK_TOP, PARAPET_THICKNESS),
				Vector3(0.0, (HANDRAIL_TOP + DECK_TOP) * 0.5, side * PARAPET_MID))


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


# --- Arch foundations --------------------------------------------------------

## The arch, its lattice web, the spandrel columns and the parapet ironwork are
## all built by BridgeIronwork now — a real riveted crescent truss instead of
## smooth box beams following a parabola. It emits meshes only, so the collision
## contract at the top of this file is unaffected and lives entirely here.
##
## What remains is the one thing the ironwork cannot add: something solid at the
## springings. A hero knocked over the parapet near either end lands on the
## abutment tower's top stage, and a tower you fall straight through is exactly
## the clipping this pass exists to kill.
func _build_arch_foundations() -> void:
	var arch := Node3D.new()
	arch.name = "ArchFoundations"
	add_child(arch)

	var body := StaticBody3D.new()
	body.name = "PierBodies"
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	arch.add_child(body)

	# Matches BridgeIronwork's tower top stage rather than the old 4 x 24 x 14
	# pier, which stood proud of the towers and caught the player on nothing.
	var tower_top := Vector3(8.4, 4.2, 16.6)
	for sx in [-1.0, 1.0]:
		SceneryKit.solid_shape(body, tower_top, Vector3(sx * 48.5, -1.9, 0.0))



# --- Lampposts ---------------------------------------------------------------

func _build_lamps() -> void:
	var lamps := Node3D.new()
	lamps.name = "Lamps"        # LightingRig.LAMP_GROUP_NAME — do not rename alone
	add_child(lamps)

	# All the cast iron on all eight posts bakes into one mesh; only the eight
	# glowing globes stay separate, because they are separate materials and
	# because lighting_rig.gd has to be able to find them (see _lamp below).
	var castings := MeshBaker.new()
	for x in LAMP_XS:
		for side in [-1.0, 1.0]:
			_lamp(lamps, castings, x, side * PARAPET_MID)
	# LODs off for the same reason as the arch: eight disjoint 13 cm poles are
	# exactly what mesh decimation deletes first.
	lamps.add_child(castings.commit(
			ToonFactory.iron(LAMP_IRON_COLOR, 0.8, 0.2, 0.45), "LampCastings", false))

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


## One dusk lamppost standing on the parapet: cast-iron base, slim pole, collar,
## warm globe, spiked cap. The ironwork goes into the shared bake; the globe is
## added to the tree directly.
##
## The globe being a SphereMesh added FLAT under `parent` is load-bearing:
## lighting_rig.gd finds the practicals by scanning the Lamps node's DIRECT
## children for a SphereMesh, so nesting the parts would leave the bridge unlit —
## and any second sphere here (a finial, a lantern shell) would burn one of the
## eight OmniLight3D slots on itself.
func _lamp(parent: Node3D, castings: MeshBaker, x: float, z: float) -> void:
	castings.add_box(Vector3(0.34, 0.22, 0.34),
			Transform3D(Basis.IDENTITY, Vector3(x, LAMP_BASE_Y + 0.11, z)))
	castings.add_cylinder(0.065, 2.60,
			Transform3D(Basis.IDENTITY, Vector3(x, LAMP_BASE_Y + 1.52, z)))
	castings.add_cylinder(0.11, 0.10,
			Transform3D(Basis.IDENTITY, Vector3(x, LAMP_GLOBE_Y - 0.23, z)))
	castings.add_cylinder(0.10, 0.22,
			Transform3D(Basis.IDENTITY, Vector3(x, LAMP_GLOBE_Y + 0.21, z)))

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
