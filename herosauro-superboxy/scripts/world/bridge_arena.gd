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
const DeckKit := preload("res://scripts/world/bridge/deck_kit.gd")
const WireSwayScript := preload("res://scripts/world/bridge/wire_sway.gd")

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
const RAIL_GAUGE_HALF := 0.72     # 1.44 m gauge, taken to the gauge faces
const SLEEPER_PITCH := 1.0
## The rail CROWN, 4 mm proud of the carriageway. Real grooved rail stands a few
## millimetres out of the paving it is bedded in; the deck collider is the flat
## box in the .tscn, so nothing here is a step anything can trip on.
const RAIL_CROWN_Y := DECK_TOP + 0.004

# --- Catenary ----------------------------------------------------------------
## Gantry stations. Interleaved with LAMP_XS (-30/-10/10/30) on purpose: masts and
## lamp posts at the same X would stack two verticals in one place and leave 20 m
## of nothing between them, which is the opposite of the rhythm this is for.
##
## NOTHING AT x = 0, and that is the whole reason this ladder is offset by 12
## rather than centred. Shot 07_ribeira looks straight down the deck's centreline
## at the arch, which round 1 named as the identity anchor that must not be
## occluded; a mast on the centreline projects to the exact middle of that frame
## and stands up through the arch's span. At +-12 and +-36 the four masts land at
## screen x = 34, 323, 957 and 1246 against an arch spanning 420 to 880, so all
## four are clear of it and the crown is untouched. Move these and re-check that.
const CATENARY_XS := [-36.0, -12.0, 12.0, 36.0]
## Masts stand on the footway, hard against the parapet, so a mast never lands in
## the fighting corridor and never fouls the kerb the hero steps up.
const MAST_Z := WALKWAY_OUTER - 0.30
const MAST_BASE_Y := WALKWAY_TOP

# --- The wrecked span --------------------------------------------------------
## THE CATENARY OVER THE FIGHTING SPAN IS BUILT ALREADY DOWN, and that is a fix,
## not a flourish. Adamastor's model stands 8.6 m out of a deck at 2.0, so the top
## of him is at 10.6; the contact wire hangs at 7.0, its messenger at 7.72 and the
## gantry cross-spans at 7.84. All three pass straight through his chest and neck
## for the whole fight.
##
## The two obvious fixes are both wrong. Lowering an overhead line to clear a
## nine-metre giant puts it at head height on a tram deck and looks wrong from
## every angle; deleting the catenary costs the corridor the converging verticals
## that are the one thing round 1's critics said it lacked. The third option costs
## nothing and pays: he has been rampaging on this bridge — that is the premise of
## the game — so over the span he fights in, the line is already torn out. A
## snapped wire has no span left for him to walk through, the run keeps its true
## height everywhere it is actually visible, and the eye reads the intact run
## first, then the break, and knows what happened here without a word of dialogue.
##
## MIRRORED, NOT IMPORTED. Reaching into another stream's script is banned
## (ARCHITECTURE.md rule 2), so these repeat adamastor.gd the way ROADWAY_HALF
## above already repeats its ARENA_Z. If the giant's arena moves, move these.
const BOSS_ARENA_X := Vector2(-14.0, 24.0)     # adamastor.gd ARENA_X_MIN / ARENA_X_MAX
## adamastor.gd's CORPSE_SIZE, which that file's own header calls "closer to what
## the model actually occupies" than the generous 5 x 9 x 4 gameplay box: 2.8 m
## across and 8.6 m tall. Half of 2.8 either side of the position clamp is how far
## the giant's shoulders really reach along the deck.
const GIANT_HALF_WIDTH := 1.4
const GIANT_TOP := DECK_TOP + 8.6
## What has to be clear of overhead line. A stomp or a kick throws an arm well
## past the torso, so the giant's own footprint is not enough on its own; 3 m of
## slack at each end covers the animation overhang. Comes out at -18.4 .. 28.4.
const WRECK_REACH := Vector2(
		BOSS_ARENA_X.x - GIANT_HALF_WIDTH - 3.0,
		BOSS_ARENA_X.y + GIANT_HALF_WIDTH + 3.0)
## WHERE THE LINE PARTS, AND WHY IT IS A GANTRY RATHER THAN MID-SPAN. Everything
## a hero can stand on tops out at |z| = 6.55, and a hero jumping off the raised
## footway reaches 6.95 with the crown of his capsule — five centimetres under the
## contact wire. So over this deck there is no room beneath an overhead line to
## hang anything at all: the only place a loose end can droop is outboard of the
## parapet, and the only place the run gets out there on its own is a mast
## bracket. CATENARY_XS[0] and [3] are the first brackets outside WRECK_REACH, so
## the line is made off there and everything between them has come down.
## _line_is_up() and _gantry_is_wrecked() are the two tests that follow from it.
##
## 20 cm outboard of the deck's own face, which clears the parapet (7.0) and the
## fascia girder behind it (6.85 centreline). Nothing on this bridge reaches it.
const WRECK_HANG_Z := DECK_HALF_WIDTH + 0.20
## Which parapet it went over. ONE side, not both: a cable dragged sideways ends
## up on one side of what dragged it, and a matched pair either side would read as
## decoration rather than as damage. +Z is the side shot 07_ribeira looks at.
const WRECK_HANG_SIDE := 1.0
## Where a torn gantry's hanging span-wire catches the dead run as it passes.
const WRECK_CATCH_Y := 4.90

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
## Bare rolled steel, wheel-burnished. Metallic 1 and near-mirror: the crown is
## the only true bare-metal surface anywhere in the playable corridor.
const RAILHEAD_COLOR := Color(0.560, 0.545, 0.520)
## The flangeway, the check rail and the clips — everything a wheel never touches
## and rust therefore owns.
const RAIL_RUST_COLOR := Color(0.235, 0.150, 0.105)
const SLEEPER_COLOR := Color(0.190, 0.160, 0.130)
const LITTER_COLOR := Color(0.640, 0.575, 0.440)
const GULL_COLOR := Color(0.930, 0.925, 0.900)
const GULL_MARK_COLOR := Color(0.150, 0.155, 0.170)
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
	_build_deck_dressing()


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
## breaking its surface, and two lengths of real GROOVED rail whose crowns sit
## level with the paving. Two bright parallel lines down a hundred metres of dark
## granite are the strongest perspective cue on the whole bridge — but only if
## they are rails.
##
## What was here was a 100 x 0.10 x 0.08 box per side: a painted stripe, measuring
## a flat navy (21, 32, 56) with a maximum of 102, and named independently by both
## round-1 critics as the single detail that gave the frame away against N. Sane
## Trilogy. BridgeDeckKit builds the section instead — running head, gauge face,
## flangeway, check rail and clips, in two materials. See its header for why the
## crown is ground to a far tighter radius than a real one.
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

	# Two bakes, two draw calls — exactly what the pair of boxes cost before.
	var steel := MeshBaker.new()
	var rust := MeshBaker.new()
	var half := DECK_LENGTH * 0.5
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		DeckKit.grooved_rail(steel, rust, -half, half, side * RAIL_GAUGE_HALF,
				RAIL_CROWN_Y, TRAM_TOP, 4801 + i * 137)
	# metallic 1.0, not the 0.85 that was here. ToonFactory snaps at 0.6 so both
	# land on bare metal either way, and stating it stops the next reader assuming
	# there is a half-painted rail somewhere in the cache. Everything a wheel never
	# touches is dielectric rust at 0.88 in the second bake.
	#
	# Roughness 0.30, not the 0.15 a mirror-polished crown would take. Measured, on
	# a render: at 0.15 the head comes back near-black. A metal has no diffuse term
	# at all, so every photon it returns is a reflection, and at a grazing view down
	# the deck the only thing in the reflection is either the sun's own lobe — which
	# a horizontal surface under a 51-degree key cannot see — or the environment.
	# Widening the lobe is the one lever this file has over that. It is also honest:
	# a rail head is ground and then wheel-burnished, which is satin, not chrome.
	#
	# It is a partial fix and the rest is not geometry. See the report: metals in
	# this scene are returning almost nothing at grazing angles, which points at the
	# environment's screen-space reflections marching along the deck and finding the
	# deck. A ReflectionProbe over the corridor would settle it.
	#
	# LODs off, as on the arch and the lampposts: a 56 mm rail head is exactly the
	# kind of thin disjoint ribbon mesh decimation deletes first, and the crown
	# facets are the whole point of it.
	tram.add_child(steel.commit(ToonFactory.iron(RAILHEAD_COLOR, 0.6, 1.0, 0.30),
			"RailHeads", false))
	tram.add_child(rust.commit(ToonFactory.iron(RAIL_RUST_COLOR, 0.34, 0.0, 0.88),
			"RailFurniture", false))


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


# --- Deck dressing -----------------------------------------------------------

## Everything the corridor was missing. Round 1's finding was blunt and correct:
## across four wide shots there was not one crate, bollard, bench, sign, drain,
## catenary pole, landed gull or piece of litter on this deck, and the RUBRIC
## counts empty flat ground anywhere the camera can see as a defect.
##
## WHERE IT ALL GOES. props/prop_spawner.gd documents its own lane — barrels hug
## the rails at |z| ~ 4.2 and keep the middle six metres clear — so nothing static
## here occupies |z| in [3.4, 4.9] unless it is flush with the paving. Everything
## with height stands on the footway or against the parapet, outside ARENA_Z.
##
## FIVE MATERIALS, FIVE DRAW CALLS, one bake each. Every piece below is a handful
## of boxes and would have been a MeshInstance3D apiece under the old scheme; at
## roughly a hundred pieces that is a hundred draw calls, which is the whole
## reason MeshBaker exists. The only exceptions are the two parted wire ends,
## which move and therefore cannot be welded into a static surface — see
## _build_fallen_line. Two draw calls, and they are the whole cost of the wreck.
func _build_deck_dressing() -> void:
	var dressing := Node3D.new()
	dressing.name = "DeckDressing"
	add_child(dressing)

	var iron := MeshBaker.new()      # catenary, gratings, bollards
	var stone := MeshBaker.new()     # benches
	var dark := MeshBaker.new()      # grating voids, gull markings
	var feather := MeshBaker.new()   # gull bodies
	var scrap := MeshBaker.new()     # litter

	var rng := RandomNumberGenerator.new()
	rng.seed = 18_86    # the year the bridge opened; seeded, see ARCHITECTURE.md

	_build_catenary(iron)
	_build_fallen_line(iron, dressing)
	_build_furniture(iron, stone, rng)
	_build_gratings(iron, dark)
	_build_perched_gulls(feather, dark, rng)
	_build_litter(scrap, rng)

	# Same cast iron as the lampposts, so the two share a cached material even
	# though they are separate bakes.
	dressing.add_child(iron.commit(ToonFactory.iron(LAMP_IRON_COLOR, 0.8, 0.0, 0.5),
			"DeckIron", false))
	dressing.add_child(stone.commit(SceneryKit.world_mapped(
			ToonFactory.stone(KERB_COLOR, 1.5)), "DeckStone"))
	dressing.add_child(dark.commit(ToonFactory.solid(Color(0.055, 0.05, 0.055), 0.0, 1.0),
			"DeckVoids", false))
	dressing.add_child(feather.commit(ToonFactory.solid(GULL_COLOR, 0.0, 0.82),
			"PerchedGulls", false))
	# Paper, leaves and torn ticket stock. Cloth at a tight tile is the closest
	# thing in the factory to a scrap of something on stone.
	dressing.add_child(scrap.commit(ToonFactory.cloth(LITTER_COLOR, 0.22), "DeckLitter", false))


## Masts, span wires, messenger and contact wire, station by station — and, over
## the fighting span, the same assembly built already torn out. See WRECK_REACH.
##
## The contact wire staggers either side of the centreline between stations, which
## is both what a real one does — so a pantograph carbon wears evenly instead of
## grooving in one place — and what stops a 100 m wire being a dead straight line
## down the middle of the frame.
func _build_catenary(iron: MeshBaker) -> void:
	var span_y := MAST_BASE_Y + DeckKit.MAST_HEIGHT - DeckKit.SPAN_DROP
	for x: float in CATENARY_XS:
		# Every mast, its cap and its bracket lug stand on all four stations, torn
		# gantry or not. They are the converging verticals the corridor is for, and
		# at |z| = 6.25 against a giant who reaches 5.75 they are already clear.
		for side in [-1.0, 1.0]:
			DeckKit.catenary_mast(iron, x, side * MAST_Z, MAST_BASE_Y)
		if _gantry_is_wrecked(x, span_y):
			DeckKit.torn_cross_span(iron, x, MAST_Z, span_y, WRECK_HANG_Z,
					WRECK_CATCH_Y - 0.35)
		else:
			DeckKit.cross_span(iron, x, MAST_Z, span_y, 0.34,
					DECK_TOP + DeckKit.WIRE_HEIGHT + DeckKit.MESSENGER_RISE)

	# The through-line, support to support. The ladder carries the two abutment
	# anchors as well as the four masts, because a wire that stops dead over the
	# last mast is the sort of thing that survives three review rounds because
	# nobody looks up. Only the bays outside WRECK_REACH are still strung.
	var ladder: Array[float] = [-ABUTMENT_INNER]
	ladder.append_array(CATENARY_XS)
	ladder.append(ABUTMENT_INNER)
	for i in range(1, ladder.size()):
		var x0: float = ladder[i - 1]
		var x1: float = ladder[i]
		if not _line_is_up(x0, x1):
			continue
		# The end bays are anchored, not registered, so they carry less sag than a
		# mast-to-mast span. Same two numbers this had before the break existed.
		var sag := 0.05 if (i == 1 or i == ladder.size() - 1) else 0.09
		DeckKit.catenary_run(iron, x0, x1, DECK_TOP,
				_wire_stagger(i - 1, ladder.size()), _wire_stagger(i, ladder.size()), sag)


## Is the through-line still up over this bay? Only the two end bays are: the run
## is made off at the outer gantries and everything between them has come down.
func _line_is_up(x0: float, x1: float) -> bool:
	return maxf(x0, x1) <= CATENARY_XS[0] \
			or minf(x0, x1) >= CATENARY_XS[CATENARY_XS.size() - 1]


## Has this gantry lost its span wire? Only the ones the giant can reach, and only
## while their cross-span hangs below the top of him — raise the masts past 10.6
## and this correctly stops claiming damage that no longer needs doing.
func _gantry_is_wrecked(x: float, span_y: float) -> bool:
	return x > WRECK_REACH.x and x < WRECK_REACH.y and span_y - 0.34 < GIANT_TOP


## Contact-wire stagger at support `i` of the ladder: it zig-zags mast to mast and
## comes back to the centreline where it is anchored at the abutments.
func _wire_stagger(i: int, count: int) -> float:
	if i == 0 or i == count - 1:
		return 0.0
	return DeckKit.WIRE_STAGGER * (1.0 if i % 2 == 1 else -1.0)


## What came down. The messenger is still made off at both outer brackets, so the
## dead run hangs in swags along the OUTSIDE of the parapet, caught over the two
## torn gantries on its way; the contact wire it used to carry has parted near
## each end, and those two free tails are the only moving thing on this deck.
##
## Nothing here is inboard of WRECK_HANG_Z except the two short jogs from the
## brackets, which are still 7.9 m up where they cross the footway edge. The
## clearance argument is in the WRECK_REACH block and it is checked for real by
## scripts/world/bridge/_wreck_probe.gd.
func _build_fallen_line(iron: MeshBaker, dressing: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2_002    # the year the Metro reached the upper deck; seeded, see ARCHITECTURE.md
	var span_y := MAST_BASE_Y + DeckKit.MAST_HEIGHT - DeckKit.SPAN_DROP
	var sz := WRECK_HANG_SIDE
	var outer := CATENARY_XS[CATENARY_XS.size() - 1] as float
	var catch_z := sz * WRECK_HANG_Z

	# Bracket, a jog out over the rail, the two torn gantries, jog, bracket.
	var path: Array[Vector3] = [
		Vector3(-outer, span_y, sz * (MAST_Z - 0.10)),
		Vector3(-outer + 1.2, span_y - 0.73, catch_z),
		Vector3(CATENARY_XS[1], WRECK_CATCH_Y, catch_z),
		Vector3(CATENARY_XS[2], WRECK_CATCH_Y, catch_z),
		Vector3(outer - 1.2, span_y - 0.73, catch_z),
		Vector3(outer, span_y, sz * (MAST_Z - 0.10)),
	]
	# Sag per swag. It deepens toward the middle because that is where the slack
	# of seventy metres of cable ends up, and because the centre swag dropping
	# below the handrail line is what makes the run read as fallen rather than
	# as a second, lower catenary someone strung on purpose.
	var sags: Array[float] = [0.0, 1.55, 2.55, 1.55, 0.0]
	for i in range(1, path.size()):
		DeckKit.fallen_line(iron, path[i - 1], path[i], sags[i - 1], rng)

	# The two parted ends of the contact wire, hung off the outer swags where the
	# messenger still holds them. Separate nodes because they move: one draw call
	# each, and the only two in this whole rebuild.
	for i in 2:
		var from: Vector3 = path[1] if i == 0 else path[3]
		var to: Vector3 = path[2] if i == 0 else path[4]
		var at := DeckKit.swag_point(from, to, sags[1 if i == 0 else 3],
				0.21 if i == 0 else 0.79)
		var tail := WireSwayScript.new() as MeshInstance3D
		tail.name = "TornContactWire%d" % (i + 1)
		tail.mesh = DeckKit.torn_tail(2.9 - float(i) * 0.5, 0.32, 7 + i * 5)
		tail.position = at
		# The cached DeckIron material, so a parted end is visibly the same cable
		# as the run it fell off.
		tail.material_override = ToonFactory.iron(LAMP_IRON_COLOR, 0.8, 0.0, 0.5)
		# A 30 mm cable hanging over the river casts onto water fifteen metres
		# below and onto nothing else, and a moving shadow caster is the one kind
		# the shadow atlas cannot cache.
		tail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tail.set("phase", 0.9 + float(i) * 2.4)
		dressing.add_child(tail)


## Bollards guarding the footway ends, and a granite bench under every other
## catenary station. The bench is the only piece of dressing tall enough to stand
## in the player's way, so it is the only one with a collider.
func _build_furniture(iron: MeshBaker, stone: MeshBaker, rng: RandomNumberGenerator) -> void:
	var bodies := StaticBody3D.new()
	bodies.name = "DeckFurnitureBodies"
	bodies.collision_layer = PhysicsLayers.WORLD
	bodies.collision_mask = 0
	add_child(bodies)

	var bench_z := WALKWAY_OUTER - 0.32
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			for k in 2:
				# Two bollards per corner, each with its own lean: a matched pair
				# of perfectly plumb posts is the repetition the RUBRIC bans.
				var x := sx * (ABUTMENT_INNER - 0.9 - float(k) * 1.35)
				DeckKit.bollard(iron, Vector3(x, WALKWAY_TOP, sz * (WALKWAY_OUTER - 0.42)),
						0.78 + rng.randf_range(-0.05, 0.05), rng.randi())
		for bx: float in [-30.0, 10.0]:
			var z := sx * bench_z
			DeckKit.bench(stone, Vector3(bx, WALKWAY_TOP, z), 1.9, rng.randf_range(-0.03, 0.03))
			# The box reaches back into the parapet body, so there is no
			# hero-width slot between a bench and the railing behind it.
			SceneryKit.solid_shape(bodies, Vector3(2.0, 0.55, 0.86),
					Vector3(bx, WALKWAY_TOP + 0.275, sx * (WALKWAY_OUTER - 0.05)))


## Gully gratings in the kerb line, where the carriageway drains. Flush with the
## paving — 8 mm of bar over a recessed frame — so they are a pattern in the deck
## and never something to trip on.
func _build_gratings(iron: MeshBaker, dark: MeshBaker) -> void:
	var z := ROADWAY_HALF - 0.24
	var x := -DECK_LENGTH * 0.5 + 6.0
	while x < DECK_LENGTH * 0.5 - 5.0:
		for sz in [-1.0, 1.0]:
			DeckKit.drain(iron, dark, Vector3(x, DECK_TOP, sz * z), 0.52, 0.30)
		x += 12.5


## Gulls standing on the handrail. Five, on both parapets, never at a matching X
## and never at a repeated yaw — the frame should not show two birds in the same
## pose at the same station.
func _build_perched_gulls(feather: MeshBaker, dark: MeshBaker,
		rng: RandomNumberGenerator) -> void:
	# BridgeIronwork.RAIL_TOP. Mirrored rather than imported: that script has no
	# class_name either, and it already mirrors this file's cross-section back.
	const HANDRAIL_Y := 3.33
	for spot: Vector3 in [
		Vector3(-17.5, 1.0, 0.0), Vector3(6.0, 1.0, 0.0), Vector3(27.0, -1.0, 0.0),
		Vector3(-34.0, -1.0, 0.0), Vector3(15.5, -1.0, 0.0),
	]:
		DeckKit.perched_gull(feather, dark,
				Vector3(spot.x, HANDRAIL_Y, spot.y * PARAPET_MID),
				rng.randf_range(-PI, PI))


## Scraps blown into the angles the wind cannot reach: the kerb line, the back of
## the footway and the outer edge of the tram bed. Two triangles each, and they
## are what stops a hundred metres of swept granite reading as swept granite.
func _build_litter(scrap: MeshBaker, rng: RandomNumberGenerator) -> void:
	# Lanes, as (z, how far the scatter spreads either side). Nothing lands inside
	# prop_spawner.gd's barrel lane at |z| ~ 4.2 with any height, but these are
	# 2 mm quads and a barrel settling on one is not a collision anyone can see.
	var lanes: Array[Vector2] = [
		Vector2(ROADWAY_HALF - 0.15, 0.13),        # against the kerb face
		Vector2(WALKWAY_OUTER - 0.16, 0.12),       # against the parapet plinth
		Vector2(TRAM_HALF - 0.18, 0.14),           # the tram bed's outer gutter
	]
	for lane in lanes:
		var count := int(DECK_LENGTH / 5.5)
		for i in count:
			if rng.randf() < 0.35:
				continue
			for sz: float in [-1.0, 1.0]:
				var x := lerpf(-DECK_LENGTH * 0.5 + 2.0, DECK_LENGTH * 0.5 - 2.0,
						(float(i) + rng.randf()) / float(count))
				var z := sz * (lane.x + rng.randf_range(-lane.y, lane.y))
				var y := TRAM_TOP if absf(z) < TRAM_HALF else DECK_TOP
				if absf(z) > ROADWAY_HALF:
					y = WALKWAY_TOP
				DeckKit.litter(scrap, Vector3(x, y, z),
						Vector2(rng.randf_range(0.07, 0.19), rng.randf_range(0.05, 0.15)),
						rng.randf_range(-PI, PI))


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
