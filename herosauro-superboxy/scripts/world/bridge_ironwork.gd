class_name BridgeIronwork
extends Node3D
## The Dom Luís I as wrought iron: the crescent lattice arch, the spandrel
## columns, the deck framing, the lattice parapets, the granite abutment towers
## and the suspended road deck below.
##
## WHAT THIS REPLACES. The arch used to be a chain of smooth boxes on a parabola
## that SAGGED — crown at the bottom, ends up at deck level — so it read as a
## hanging cable, and everything on it was a solid beam. Nothing about that is the
## Dom Luís I. Seyrig's 1886 arch is a two-hinged CRESCENT: two chords pinned
## together at each springing, opening to their greatest separation at the crown,
## with the space between them filled by a dense riveted zig-zag. It bows UP and
## the deck rides ON it. That is rebuilt here from BridgeArchCurve's parametrics
## with BridgeIronKit's riveted members, baked by MeshBaker into a handful of
## draw calls.
##
## WHICH DECK THE PLAYER IS ON. The real bridge is double-deck, "one on top of the
## arch and the other suspended below it". The playable deck carries a metro
## tramway and two pedestrian footways, so it is the UPPER deck — which is why the
## arch belongs entirely below it, crown kissing the deck framing at mid-span and
## falling away toward the banks with latticed spandrel columns of increasing
## height standing between. The road deck the bridge also carries is built too,
## 14 m down: it hangs off the arch's lower chord through the middle, threads
## BETWEEN the splayed ribs at the quarter points, and is propped up off the upper
## chord near the ends, exactly as the real one crosses its own arch.
##
## OWNERSHIP AND INTEGRATION. This node builds meshes only — not one collider.
## bridge_arena.gd keeps the whole collision contract, and the boxes it already
## has (deck slab, parapet body, footway step, abutment body) still stand in for
## everything here. Drop it in with:
##
##     const IronworkScript = preload("res://scripts/world/bridge_ironwork.gd")
##     IronworkScript.attach(self)
##
## then delete, from bridge_arena.gd: _build_arch() and _build_lattice() entirely
## except the two pier StaticBody3Ds; and, inside _build_parapets(), the Plinth,
## MidRail, HandRail, EdgeGirder, GirderFlange, Balusters and ParapetPosts — that
## is, everything but the ParapetBody collider. Leaving any of them builds a
## second railing 17 cm above this one. Every part here is behind its own @export
## flag if some of it has to stay for a while.
##
## SCALE HONESTY. The scene is compressed ~3.5x vertically (17 m of deck-to-water
## against the real 60 m), so the arch cannot have its true 0.26 rise/span without
## the springings ending up 11 m under the river. They are dropped to -17.6 —
## just under the opaque water, where the granite towers hide them — which buys
## rise/span ~0.16. The crescent, the lattice, the splay and the deck relationship
## are all true; the arc is flatter than Porto's. See BridgeArchCurve.

const ArchCurve := preload("res://scripts/world/bridge/arch_curve.gd")
const IronKit := preload("res://scripts/world/bridge/iron_kit.gd")

# --- Mirrored from bridge_arena.gd -------------------------------------------
# That script has no class_name, so these cannot be imported. They are the deck
# cross-section this ironwork hangs off; if bridge_arena.gd moves one, move it
# here too or the parapet floats and the fascia girders bite into the slab.

const DECK_LENGTH := 100.0
const DECK_HALF_WIDTH := 7.0
const DECK_TOP := 2.0
const DECK_BOTTOM := 0.0
const WALKWAY_TOP := DECK_TOP + 0.13   # + bridge_arena.gd's KERB_RISE
const PARAPET_MID := 6.775
const STRUCTURE_TOP := 1.96        # top of the deck mesh; the parapet plinth roots in it

# --- Deck framing ------------------------------------------------------------
# The slab in the .tscn stops dead at y = 0 and hangs there. Real deck spans have
# their main girders BELOW the roadway, and hanging them there does three things
# at once: the deck gains 1.85 m of visible depth from the river, the arch gets
# something structural to bear against at the crown, and the spandrel columns get
# somewhere to land that is not the underside of a granite box.

const FRAME_BOTTOM := -1.85
const FASCIA_Z := DECK_HALF_WIDTH - 0.15   # main girder centreline, inboard of the fascia
const FASCIA_PITCH := 2.50         # panel length of the deck girder lattice
const CROSS_PITCH := 5.0           # transverse floor beams
const CROSS_TOP := -1.10
const CROSS_BOTTOM := -1.80
const FRAME_END_X := DECK_LENGTH * 0.5 - 0.2   # stops just short of the abutment faces

# --- Spandrel columns --------------------------------------------------------
# Stations bunch toward the springings, as the real ones do: the arch drops away
# from the deck fastest there, so the columns get taller and are spaced closer.
# The inner three are so short they fall through to cast pedestals, which is also
# what the real bridge does over the crown.

## Stops at 40: past that the arch has already run into the granite (its inner
## face is at |x| = 43.3) and a column there would be buried, paying 500
## triangles to be invisible.
const SPANDREL_XS := [0.0, 5.0, 10.0, 15.0, 22.0, 29.0, 35.0, 40.0]
const SPANDREL_TOP_Y := -1.80
const SPANDREL_PANEL := 3.0        # lattice panel height
const SPANDREL_ATTACH_Z := Vector2(4.8, 6.2)   # clamp for where a column head can land

# --- Parapet -----------------------------------------------------------------
# Plinth, coping, kick rail, lattice frieze, mid rail, handrail. Everything tops
# out at 3.33 — exactly 1.20 m over the footway, the ceiling before a
# third-person camera starts fighting the railing instead of seeing over it.
#
# The plinth is built HERE, and lower than bridge_arena.gd's 2.55, for one
# reason: a 1.20 m parapet standing on a 0.42 m plinth leaves 0.78 m of iron, and
# a lattice X across a 2.5 m panel in a 0.35 m band lies at 8 degrees, which reads
# as a painted zigzag stripe. Dropping the stone to 2.30 buys a 0.56 m band, and
# a W-lattice pitched at a quarter of the post bay then sits at 41 degrees — a
# real truss angle. The stone lost is worth the ironwork gained.

const PLINTH_TOP := 2.30
const PARAPET_THICK := 0.45        # bridge_arena.gd's PARAPET_THICKNESS
const COPING_TOP := 2.42
## Derived, not chosen: the third-person camera has to see over this, and 1.20 m
## above the surface the player is standing on is where that stops being true.
const RAIL_TOP := WALKWAY_TOP + 1.20
const RAIL_KICK_Y := 2.49
const RAIL_MID_Y := 3.165
const RAIL_HAND_Y := 3.26        # 0.14 deep, so its top is exactly RAIL_TOP
const LATTICE_LOW := 2.56
const LATTICE_HIGH := 3.12
const POST_PITCH := 2.5
## Lattice nodes per post bay. Four gives a W whose ends land on the posts, so
## the frieze is tied into the frame rather than floating between it.
const LATTICE_PER_BAY := 4
const HEAVY_POST_PITCH := 10.0
## Posts sit on a SYMMETRIC LADDER through x = 0, not on a course offset half a
## bay, so the heavy posts land on round metres. That is load-bearing:
## bridge_arena.gd stands its lampposts at LAMP_XS = +-10, +-30, and a ladder is
## what puts a heavy post under each of them instead of a gap.
const POST_LADDER_X := 47.5
const HEAVY_LADDER_X := 40.0
## The rails run past the last post to meet the abutment.
const PARAPET_END_X := DECK_LENGTH * 0.5 - 0.4

# --- Abutment towers ---------------------------------------------------------
# Big battered granite, stepped in three times, with cutwaters on the river faces.
# They stop 0.2 m over the deck underside: bridge_arena.gd's _build_ends() owns
# everything above the deck, and this is the river pier it stands on.

const TOWER_X := 48.5
const TOWER_TOP := 0.20
const TOWER_BASE_Y := -19.6

# --- Suspended road deck -----------------------------------------------------
# 3 m over the water, which is where 11 m over the Douro lands once the scene's
# vertical compression is applied. Narrow enough (8.4 m) to thread between the
# ribs where the arch crosses its level.

const ROAD_Y := -12.0
const ROAD_HALF_WIDTH := 4.2
const ROAD_END_X := 52.0           # buried in the bank shelf, which starts at |x| = 50
const ROAD_HANGER_PITCH := 4.0

# --- Member sizing -----------------------------------------------------------
# The whole believability of a lattice is in the ratio between chord and web. A
# chord is a deep box girder; a web bar is a thin flat. Bring them within 2x of
# each other and it stops reading as a truss and starts reading as a fence.

const CHORD_W := 0.55              # across the rib
const CHORD_H := 0.82              # in the plane of the arch
const WEB_W := 0.30                # lattice flat: wide in plane...
const WEB_T := 0.10                # ...thin across it
const GUSSET_SIZE := 0.72
const ARCH_BAYS := 26
const SPLICE_EVERY := 4            # chord splice covers, in bays

# --- Palette -----------------------------------------------------------------
# Two irons, not one. The chords and plates catch the low sun; the web sits in
# their shadow and behind them, and giving it its own darker, rougher, less
# metallic material is what makes the lattice read as depth rather than as a
# flat pattern painted on the arch.

const IRON_MAIN := Color(0.315, 0.335, 0.365)
const IRON_WEB := Color(0.208, 0.226, 0.252)
const IRON_RAIL := Color(0.200, 0.220, 0.250)     # bridge_arena.gd's IRONWORK_COLOR
const GRANITE := Color(0.470, 0.450, 0.412)       # bridge_arena.gd's ABUTMENT_COLOR
const GRANITE_TRIM := Color(0.575, 0.555, 0.505)

# --- Part switches -----------------------------------------------------------
# One per thing bridge_arena.gd might still be building itself, so integration is
# a flag rather than a merge.

@export var build_arch: bool = true
@export var build_spandrels: bool = true
@export var build_deck_frame: bool = true
@export var build_parapets: bool = true
@export var build_towers: bool = true
@export var build_road_deck: bool = true
## The parapet's own granite plinth and coping. Leave ON and delete the Plinth
## line from bridge_arena.gd's _build_parapets(); turning it OFF instead leaves
## the ironwork standing 12 cm inside a plinth 25 cm too tall for it.
@export var build_plinth: bool = true
## Prints the measured triangle and draw-call totals at build time.
@export var report_budget: bool = false

var _built := false
var _tri_total := 0
var _draw_calls := 0


func _ready() -> void:
	rebuild()


## Make the node, apply overrides, park it under `parent`. Overrides are applied
## before the node enters the tree, so they take effect on the first build.
static func attach(parent: Node3D, overrides: Dictionary = {}) -> BridgeIronwork:
	var node := BridgeIronwork.new()
	node.name = "Ironwork"
	for key in overrides:
		node.set(key, overrides[key])
	parent.add_child(node)
	return node


## Total triangles this node put in the scene. Measured, not estimated.
func triangle_count() -> int:
	return _tri_total


## MeshInstance3Ds committed — one draw call each, since every bake is a single
## surface with a single material_override.
func draw_call_count() -> int:
	return _draw_calls


# --- Build -------------------------------------------------------------------

## Five bakers, five draw calls. Grouping is by MATERIAL and nothing else: a
## member goes into the baker whose colour it wants, wherever it is on the bridge,
## because a sixth MeshInstance3D costs more than a thousand extra triangles do.
func rebuild() -> void:
	if _built:
		return
	_built = true

	var iron := MeshBaker.new()      # chords, flanges, plates, floor beams
	var web := MeshBaker.new()       # lattice bars, spandrel columns, road deck
	var rail := MeshBaker.new()      # parapet ironwork
	var stone := MeshBaker.new()     # abutment towers
	var trim := MeshBaker.new()      # copings and string courses

	if build_arch:
		_build_arch(iron, web)
	if build_spandrels:
		_build_spandrels(web, iron)
	if build_deck_frame:
		_build_deck_frame(iron, web)
	if build_parapets:
		_build_parapets(rail, trim, stone)
	if build_towers:
		_build_towers(stone, trim, web)
	if build_road_deck:
		_build_road_deck(web, iron)

	# Thin ironwork is far under an SDFGI cascade-0 cell, so voxelising it only
	# ever adds leak noise; the granite masses are big enough to be worth bouncing.
	_commit(iron, ToonFactory.iron(IRON_MAIN, 1.0, 0.42, 0.58), "Ironwork", false)
	_commit(web, ToonFactory.iron(IRON_WEB, 0.8, 0.30, 0.70), "IronLattice", false)
	_commit(rail, ToonFactory.iron(IRON_RAIL, 0.7, 0.28, 0.50), "ParapetIron", false)
	_commit(stone, ToonFactory.stone(GRANITE, 3.4), "AbutmentTowers", true)
	_commit(trim, ToonFactory.stone(GRANITE_TRIM, 1.7), "MasonryTrim", true)

	if report_budget:
		print("BridgeIronwork: %d triangles, %d draw calls" % [_tri_total, _draw_calls])


## LOD generation is deliberately OFF for every bake.
##
## meshoptimizer simplifies by collapsing edges, and a lattice is thousands of
## disjoint 12-triangle boxes with no shared edges at all: there is nothing to
## collapse except whole members, so the first LOD does not simplify the arch, it
## deletes parts of it. The player never sees this structure from further than
## ~60 m anyway, and 23k triangles is not what costs anything here.
func _commit(baker: MeshBaker, mat: Material, mesh_name: String, gi: bool) -> void:
	if baker.triangle_count() == 0:
		return
	var mi := baker.commit(mat, mesh_name, false)
	if not gi:
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mi)
	_tri_total += baker.triangle_count()
	_draw_calls += 1


# --- The crescent arch -------------------------------------------------------

## Two ribs, each a box girder of two chord planes; in every plane an upper and a
## lower chord converging to the springing pin, and between them a full X-lattice.
## Then the things that make it one structure rather than four flat trusses:
## lacing across each rib's own width, cross-frames between the ribs, splice
## covers down the chords, gussets at every web joint, and a hinge shoe where the
## whole thrust lands on the granite.
func _build_arch(iron: MeshBaker, web: MeshBaker) -> void:
	for si in 2:
		var side := -1.0 if si == 0 else 1.0
		for pi in 2:
			var plane := -1.0 if pi == 0 else 1.0
			var upper := ArchCurve.polyline(ArchCurve.UPPER, side, plane, ARCH_BAYS)
			var lower := ArchCurve.polyline(ArchCurve.LOWER, side, plane, ARCH_BAYS)
			IronKit.sweep(iron, upper, CHORD_W, CHORD_H)
			IronKit.sweep(iron, lower, CHORD_W, CHORD_H * 0.92)
			# Gussets only on the outboard plane: on the inboard one they are
			# behind 1.5 m of lattice and nobody will ever resolve them.
			var gusset_target: MeshBaker = iron if plane > 0.0 else null
			IronKit.lattice_web(web, upper, lower, WEB_W, WEB_T, Vector3.BACK,
					2, 0.70, gusset_target, GUSSET_SIZE)
			_chord_splices(iron, upper)
			_chord_splices(iron, lower)

		_rib_lacing(web, side)
		_hinge_shoes(iron, side)

	_cross_frames(web, iron)


## Splice covers: the plated butt joints between rolled lengths. One oversized
## collar every few bays, which from the deck is a shadow line marching down the
## chord — the cheapest and most legible rivet cue there is.
func _chord_splices(b: MeshBaker, chord: PackedVector3Array) -> void:
	for i in range(SPLICE_EVERY, chord.size() - 1, SPLICE_EVERY):
		var tangent := (chord[i + 1] - chord[i - 1]).normalized()
		IronKit.splice(b, chord[i], tangent, CHORD_W + 0.14, CHORD_H + 0.12, 0.46)


## Diagonal lacing across the 1.5 m width of one rib, top and bottom. Without it
## the two chord planes are two unrelated flat trusses, and the rib reads as a
## cut-out the moment the camera looks down at it from the deck.
func _rib_lacing(b: MeshBaker, side: float) -> void:
	for ci in 2:
		var chord := ArchCurve.UPPER if ci == 0 else ArchCurve.LOWER
		for i in range(0, ARCH_BAYS - 1, 2):
			var t0 := -1.0 + 2.0 * float(i) / float(ARCH_BAYS)
			var t1 := -1.0 + 2.0 * float(i + 2) / float(ARCH_BAYS)
			var a := ArchCurve.point(t0, chord, side, -1.0)
			var bb := ArchCurve.point(t1, chord, side, 1.0)
			var c := ArchCurve.point(t0, chord, side, 1.0)
			var d := ArchCurve.point(t1, chord, side, -1.0)
			IronKit.bar(b, a, bb, WEB_W * 0.8, WEB_T, Vector3.UP)
			IronKit.bar(b, c, d, WEB_W * 0.8, WEB_T, Vector3.UP)


## Transverse cross-frames tying the two ribs together — struts across plus
## diagonals in plan.
##
## They are placed on whichever chord is CLEAR of the suspended road deck at that
## station: on the lower chord through the middle where the arch is above the
## road, on the upper chord near the ends where it has dropped below it, and
## nowhere at all in the band where the road threads between the ribs. Bracing a
## real arch straight through its own carriageway is the one thing Seyrig could
## not have done either.
func _cross_frames(b: MeshBaker, plates: MeshBaker) -> void:
	# Clearances, not guesses: a cross-frame spans the FULL width between the ribs,
	# so it must miss the road deck's whole envelope — parapet rail at ROAD_Y+1.05
	# above, edge girder at ROAD_Y-1.11 below — not just its slab. 1.7 / 1.8 leave
	# ~0.65 m either way. Shrink these and the struts saw through the girders.
	var t_inner := ArchCurve.t_at_height(ROAD_Y + 1.7, ArchCurve.LOWER)
	var t_outer := ArchCurve.t_at_height(ROAD_Y - 1.8, ArchCurve.UPPER)
	for i in range(0, ARCH_BAYS - 1, 2):
		var t0 := -1.0 + 2.0 * float(i) / float(ARCH_BAYS)
		var t1 := -1.0 + 2.0 * float(i + 2) / float(ARCH_BAYS)
		var mid := absf((t0 + t1) * 0.5)
		var chord := -1
		if mid < t_inner:
			chord = ArchCurve.LOWER
		elif mid > t_outer:
			chord = ArchCurve.UPPER
		if chord < 0:
			continue
		var a0 := ArchCurve.point(t0, chord, -1.0, -1.0)
		var a1 := ArchCurve.point(t0, chord, 1.0, -1.0)
		var b0 := ArchCurve.point(t1, chord, -1.0, -1.0)
		var b1 := ArchCurve.point(t1, chord, 1.0, -1.0)
		IronKit.bar(b, a0, a1, WEB_W, WEB_T, Vector3.UP)
		IronKit.bar(b, a0, b1, WEB_W * 0.8, WEB_T, Vector3.UP)
		IronKit.bar(b, a1, b0, WEB_W * 0.8, WEB_T, Vector3.UP)
		IronKit.gusset(plates, a0, GUSSET_SIZE * 0.9, WEB_T * 2.4, Vector3.UP, Vector3.BACK)
		IronKit.gusset(plates, a1, GUSSET_SIZE * 0.9, WEB_T * 2.4, Vector3.UP, Vector3.BACK)


## The two-hinged arch's defining detail: a pin, not a fixing. Both chords have
## converged to nothing here, so the shoe is a slab of plate either side of a
## transverse pin, bedded into the granite. It is 2 m under the waterline and
## half inside the tower — but the last 5 m of chord taper INTO something, which
## is the whole point of a crescent, and a chord that just stopped in mid-air
## would undo the shape.
func _hinge_shoes(b: MeshBaker, side: float) -> void:
	for si in 2:
		var t := -1.0 if si == 0 else 1.0
		var at := ArchCurve.point(t, ArchCurve.UPPER, side, 0.0)
		var axis := Basis(Vector3.RIGHT, PI * 0.5)   # cylinder's local +Y onto world Z
		b.add_cylinder(0.46, ArchCurve.RIB_WIDTH + 0.9, Transform3D(axis, at), 10)
		for pi in 2:
			var plane := -1.0 if pi == 0 else 1.0
			var cheek := at + Vector3(0.0, 0.0, side * plane * (ArchCurve.RIB_WIDTH * 0.5 + 0.16))
			IronKit.plate(b, cheek, 2.6, 1.7, 0.22, Vector3.BACK, Vector3.RIGHT)
		# Bedstone plate spreading the thrust into the masonry.
		b.add_box(Vector3(3.6, 0.34, ArchCurve.RIB_WIDTH + 2.0),
				Transform3D(Basis(), at + Vector3(t * 0.6, -1.05, 0.0)))


# --- Spandrel columns --------------------------------------------------------

## The latticed columns carrying the deck down onto the arch's extrados. Short
## cast pedestals over the crown, 14 m four-post lattice towers near the
## springings, and every one of them raked: the ribs splay outward toward the
## banks and the deck does not, so the outer columns lean inward to meet it.
func _build_spandrels(b: MeshBaker, plates: MeshBaker) -> void:
	for x_abs in SPANDREL_XS:
		for si in 2:
			var sx := -1.0 if si == 0 else 1.0
			if x_abs == 0.0 and sx < 0.0:
				continue     # the centreline station exists once
			var x: float = sx * float(x_abs)
			var t := ArchCurve.t_at_x(x)
			for zi in 2:
				var side := -1.0 if zi == 0 else 1.0
				var base_y := ArchCurve.chord_y(t, ArchCurve.UPPER) + CHORD_H * 0.5
				var height := SPANDREL_TOP_Y - base_y
				if height <= 0.02:
					continue
				var base := Vector3(x, base_y, side * ArchCurve.rib_z(t))
				var head_z := clampf(ArchCurve.rib_z(t), SPANDREL_ATTACH_Z.x, SPANDREL_ATTACH_Z.y)
				var top := Vector3(x, SPANDREL_TOP_Y, side * head_z)
				# Taller columns are wider — a 14 m post at the width of a 2 m one
				# looks like it would buckle, and the eye knows it.
				var wx := clampf(1.15 + height * 0.062, 1.15, 2.10)
				var wz := clampf(0.85 + height * 0.036, 0.85, 1.35)
				IronKit.lattice_tower(b, base, top, wx, wz, 0.20, SPANDREL_PANEL,
						WEB_W * 0.78, WEB_T)
				# Base shoe and capital: the plated joints top and bottom, where a
				# real column meets the arch chord and the floor beam.
				plates.add_box(Vector3(wx + 0.5, 0.20, wz + 0.5),
						Transform3D(Basis(), base + Vector3(0.0, 0.08, 0.0)))
				plates.add_box(Vector3(wx + 0.6, 0.22, wz + 0.6),
						Transform3D(Basis(), top - Vector3(0.0, 0.10, 0.0)))


# --- Deck framing ------------------------------------------------------------

## What the deck stands on, seen from the river: a lattice girder down each edge
## and a floor beam across every 5 m, hung under the slab so the deck has 1.85 m
## of real depth instead of being a slab floating on nothing.
func _build_deck_frame(iron: MeshBaker, web: MeshBaker) -> void:
	for si in 2:
		var side := -1.0 if si == 0 else 1.0
		var z: float = side * FASCIA_Z
		# All of it in the chord colour: this girder is the one piece of ironwork
		# in full sun all day, and darkening its diagonals to match the arch web
		# would read as dirt rather than as depth.
		IronKit.lattice_girder(iron, -FRAME_END_X, FRAME_END_X, DECK_BOTTOM - 0.02, FRAME_BOTTOM, z,
				FASCIA_PITCH, Vector2(0.62, 0.20), WEB_W * 0.55, WEB_T, 0.24)
		# Cover plates over the girder's own splices, every four panels.
		var covers := int(FRAME_END_X * 2.0 / (FASCIA_PITCH * 4.0))
		for i in covers + 1:
			var x := lerpf(-FRAME_END_X, FRAME_END_X, float(i) / float(maxi(covers, 1)))
			IronKit.plate(iron, Vector3(x, (FRAME_BOTTOM + DECK_BOTTOM) * 0.5, z),
					0.44, 1.55, 0.10, Vector3.BACK, Vector3.RIGHT)

	var beam_count := int(FRAME_END_X * 2.0 / CROSS_PITCH)
	var beam_y := (CROSS_TOP + CROSS_BOTTOM) * 0.5
	var beam_h := CROSS_TOP - CROSS_BOTTOM
	for i in beam_count + 1:
		var x := lerpf(-FRAME_END_X, FRAME_END_X, float(i) / float(beam_count))
		iron.add_box(Vector3(0.34, beam_h, FASCIA_Z * 2.0 + 0.4),
				Transform3D(Basis(), Vector3(x, beam_y, 0.0)))
		# Knee brackets into the main girders: the triangles under a floor beam's
		# ends that stop the deck edge reading as a butt joint.
		for si in 2:
			var side := -1.0 if si == 0 else 1.0
			var z: float = side * (FASCIA_Z - 0.28)
			IronKit.bar(web, Vector3(x, CROSS_BOTTOM, z),
					Vector3(x, CROSS_TOP + 0.55, side * (FASCIA_Z - 1.5)),
					0.26, WEB_T, Vector3.RIGHT)


# --- Parapets ----------------------------------------------------------------

## Kick rail, lattice frieze, mid rail, handrail, a post every 2.5 m and a heavy
## one every 10. The frieze is the arch's own X-lattice at 1/40 scale, which is
## what ties the thing the player's hand is on to the thing under their feet.
##
## No collider: bridge_arena.gd's single ParapetBody box already stands in for the
## lot, and it is right that it does — a swept-sphere camera catching on 320
## individual bars is exactly what makes a third-person camera chatter.
func _build_parapets(b: MeshBaker, trim: MeshBaker, stone: MeshBaker) -> void:
	var span := PARAPET_END_X * 2.0
	var posts := _ladder(POST_LADDER_X, POST_PITCH)
	var heavies := _ladder(HEAVY_LADDER_X, HEAVY_POST_PITCH)
	heavies.append(-POST_LADDER_X)
	heavies.append(POST_LADDER_X)
	var node_pitch := POST_PITCH / float(LATTICE_PER_BAY)
	var nodes := _ladder(POST_LADDER_X, node_pitch)

	for si in 2:
		var side := -1.0 if si == 0 else 1.0
		var z: float = side * PARAPET_MID

		if build_plinth:
			# Rooted in the deck mass, not perched on the flagstones, so no gap
			# opens under it where the pavement stops.
			stone.add_box(Vector3(span, PLINTH_TOP - STRUCTURE_TOP, PARAPET_THICK),
					Transform3D(Basis(), Vector3(0.0, (PLINTH_TOP + STRUCTURE_TOP) * 0.5, z)))
			# Coping: overhangs the plinth both sides, so the ironwork stands on a
			# shadow line instead of growing straight out of the stone.
			trim.add_box(Vector3(span + 0.4, COPING_TOP - PLINTH_TOP, PARAPET_THICK + 0.11),
					Transform3D(Basis(), Vector3(0.0, (COPING_TOP + PLINTH_TOP) * 0.5, z)))

		b.add_box(Vector3(span, 0.14, 0.34), Transform3D(Basis(), Vector3(0.0, RAIL_KICK_Y, z)))
		b.add_box(Vector3(span, 0.09, 0.26), Transform3D(Basis(), Vector3(0.0, RAIL_MID_Y, z)))
		b.add_box(Vector3(span, 0.14, 0.40), Transform3D(Basis(), Vector3(0.0, RAIL_HAND_Y, z)))

		# W-lattice: one continuous zig-zag between the kick and mid rails, its
		# nodes landing on every post. Crossing X diagonals would double the
		# member count for the same 0.56 m of band, and a hundred metres of
		# railing is the geometry closest to the camera on the entire bridge.
		for i in nodes.size() - 1:
			var y0 := LATTICE_LOW if i % 2 == 0 else LATTICE_HIGH
			var y1 := LATTICE_HIGH if i % 2 == 0 else LATTICE_LOW
			IronKit.bar(b, Vector3(nodes[i], y0, z), Vector3(nodes[i + 1], y1, z),
					0.085, 0.05, Vector3.BACK)
		for x in posts:
			if _near_any(heavies, x):
				continue     # a heavy post already stands here
			b.add_box(Vector3(0.12, RAIL_TOP - COPING_TOP, 0.20),
					Transform3D(Basis(), Vector3(x, (RAIL_TOP + COPING_TOP) * 0.5, z)))
		for x in heavies:
			# Heavy posts start below the coping, so they read as standing on the
			# plinth with the light ones hung off the rails between them.
			b.add_box(Vector3(0.24, RAIL_TOP - PLINTH_TOP, 0.32),
					Transform3D(Basis(), Vector3(x, (RAIL_TOP + PLINTH_TOP) * 0.5, z)))
			b.add_box(Vector3(0.34, 0.08, 0.42),
					Transform3D(Basis(), Vector3(x, RAIL_TOP - 0.04, z)))


# --- Abutment towers ---------------------------------------------------------

## Where 94 m of iron lands. Battered granite in three stages with a string course
## at every step-in, rusticated quoins on the corners, and a cutwater on each
## river face. Deliberately the only thing here that is not iron and not thin:
## the arch has to be seen to be held by something, and the contrast in both mass
## and material is what sells the load.
func _build_towers(b: MeshBaker, trim: MeshBaker, dark: MeshBaker) -> void:
	# Footprint (x size, z size) per stage, bottom first; LEVELS are the y each
	# stage runs between, so a stage's height is never restated.
	var stages := [
		Vector2(12.0, 22.0), Vector2(10.4, 20.0), Vector2(9.2, 18.2), Vector2(8.4, 16.6),
	]
	var levels := [TOWER_BASE_Y, -16.0, -10.0, -4.0, TOWER_TOP]

	for si in 2:
		var sx := -1.0 if si == 0 else 1.0
		var cx: float = sx * TOWER_X
		for i in stages.size():
			var s: Vector2 = stages[i]
			var y0: float = levels[i]
			var y1: float = levels[i + 1]
			b.add_box(Vector3(s.x, y1 - y0, s.y),
					Transform3D(Basis(), Vector3(cx, (y0 + y1) * 0.5, 0.0)))
			# String course on the step-in above each stage but the last.
			if i < stages.size() - 1:
				trim.add_box(Vector3(s.x + 0.4, 0.45, s.y + 0.4),
						Transform3D(Basis(), Vector3(cx, y1 - 0.05, 0.0)))
			# Quoins: shallow pilasters up the four vertical corners, which is what
			# stops a 20 m granite box from reading as a 20 m granite box.
			for qi in 4:
				var qx: float = cx + (-1.0 if qi < 2 else 1.0) * (s.x * 0.5 - 0.35)
				var qz: float = (-1.0 if qi % 2 == 0 else 1.0) * (s.y * 0.5 + 0.10)
				trim.add_box(Vector3(1.5, y1 - y0 - 0.5, 0.55),
						Transform3D(Basis(), Vector3(qx, (y0 + y1) * 0.5, qz)))

		# Cutwaters: rounded noses on the upstream and downstream faces, run from
		# the footing up to the top of the second stage.
		for zi in 2:
			var sz := -1.0 if zi == 0 else 1.0
			var nose_y := (TOWER_BASE_Y + -10.0) * 0.5
			b.add_cylinder(1.85, -10.0 - TOWER_BASE_Y,
					Transform3D(Basis(), Vector3(cx, nose_y, sz * 10.0)), 12)
			trim.add_cylinder(2.05, 0.5,
					Transform3D(Basis(), Vector3(cx, -10.15, sz * 10.0)), 12)
			# Pilasters up the long faces. A 20 m granite slab with nothing on it
			# reads as its bounding box no matter how good the material is; two
			# shallow ribs per face give the low sun something to break over.
			for pi in 2:
				var px: float = cx + (-1.0 if pi == 0 else 1.0) * 2.7
				trim.add_box(Vector3(1.9, TOWER_TOP - TOWER_BASE_Y - 1.6, 0.5),
						Transform3D(Basis(), Vector3(px,
								(TOWER_BASE_Y + TOWER_TOP) * 0.5 - 0.4, sz * 9.4)))

		_tower_coursing(b, cx, stages, levels)

		# Springing corbels: the projecting brackets the arch chords visibly run
		# into, so 94 m of iron is seen to be caught by stone rather than to end.
		for zi in 2:
			var sz := -1.0 if zi == 0 else 1.0
			var t: float = ArchCurve.t_at_x(cx - sx * 5.2)
			trim.add_box(Vector3(1.6, 1.5, ArchCurve.RIB_WIDTH + 2.2),
					Transform3D(Basis(), Vector3(cx - sx * 5.4,
							ArchCurve.chord_y(t, ArchCurve.UPPER) - 1.3,
							sz * ArchCurve.rib_z(t))))

		# Corbel course carrying the deck's last few metres onto the tower.
		trim.add_box(Vector3(8.8, 0.5, 17.4), Transform3D(Basis(), Vector3(cx, -0.15, 0.0)))

		_end_pylons(b, trim, cx)

		if build_road_deck:
			_road_portal(trim, dark, cx - sx * (stages[1].x * 0.5), sx)


## The only masonry that rises ABOVE the walking surface, and the reason it exists
## is that until now nothing did.
##
## TOWER_TOP is 0.20, i.e. the towers stop 1.80 m BELOW DECK_TOP = 2.0. Everything
## the player could see above the deck was a 1.33 m parapet, eight lamp globes,
## four tram catenary masts and a stopped tram — a generic 19th-century European
## tram street, which is exactly what it read as. The arch is underneath and (see
## ArchCurve.RIB_Z) was invisible from every gameplay pose; the towers, which are
## the most Dom Luís-shaped objects in the build, never reached the deck.
##
## SO THE PYLONS FLANK THE DECK RATHER THAN BLOCKING IT. The tower's top stage is
## 8.4 x 16.6, wider than the 14 m deck, so carrying that mass straight up would
## wall the corridor off — and it would do it invisibly, because bridge_arena.gd
## owns the entire collision contract and this file commits no collision at all
## (see _commit). A player would have walked through granite. Instead these sit
## OUTBOARD at |z| = 8.15, clear of DECK_HALF_WIDTH = 7.0, so they need no
## collision, take no walkable surface, and cannot be reached: the boss is clamped
## to ARENA_X_MAX = 24.0, which is 24.5 m short of TOWER_X.
##
## No lintel over the roadway. A portal beam was the obvious next move and it is
## the one part of this that was argued down: it is the member that would have had
## to clear a nine-metre giant, and it buys framing this already gets from a pair.
## Two verticals at the vanishing point of every fight frame is the composition;
## the crossbeam was the risk.
const PYLON_TOP := 14.0
const PYLON_Z := 8.15
const PYLON_X_SIZE := 5.2
const PYLON_Z_SIZE := 3.4


func _end_pylons(b: MeshBaker, trim: MeshBaker, cx: float) -> void:
	# Two stages so it batters like the tower below it rather than reading as an
	# extruded rectangle: the shaft steps in once, at the height the deck passes.
	var waist := DECK_TOP + 4.6
	var shafts := [
		[TOWER_TOP, waist, PYLON_X_SIZE, PYLON_Z_SIZE],
		[waist, PYLON_TOP, PYLON_X_SIZE - 0.7, PYLON_Z_SIZE - 0.45],
	]
	for zi in 2:
		var sz := -1.0 if zi == 0 else 1.0
		var pz: float = sz * PYLON_Z
		for s in shafts:
			var y0: float = s[0]
			var y1: float = s[1]
			var xs: float = s[2]
			var zs: float = s[3]
			b.add_box(Vector3(xs, y1 - y0, zs),
					Transform3D(Basis(), Vector3(cx, (y0 + y1) * 0.5, pz)))
			# String course on the step-in, matching the towers' own language.
			trim.add_box(Vector3(xs + 0.35, 0.40, zs + 0.35),
					Transform3D(Basis(), Vector3(cx, y1 - 0.05, pz)))
			# Quoins up the corners, same reason as the tower: a plain granite
			# box reads as its bounding box however good the material is.
			for qi in 4:
				var qx: float = cx + (-1.0 if qi < 2 else 1.0) * (xs * 0.5 - 0.28)
				var qz: float = pz + (-1.0 if qi % 2 == 0 else 1.0) * (zs * 0.5 + 0.08)
				trim.add_box(Vector3(1.15, y1 - y0 - 0.6, 0.5),
						Transform3D(Basis(), Vector3(qx, (y0 + y1) * 0.5, qz)))
		# Cap: a shallow cornice and a plinth, so the shaft terminates instead of
		# stopping. At 66 m this is most of what says "masonry" rather than "post".
		trim.add_box(Vector3(PYLON_X_SIZE + 0.5, 0.55, PYLON_Z_SIZE + 0.5),
				Transform3D(Basis(), Vector3(cx, PYLON_TOP + 0.28, pz)))
		trim.add_box(Vector3(PYLON_X_SIZE - 1.5, 0.7, PYLON_Z_SIZE - 1.2),
				Transform3D(Basis(), Vector3(cx, PYLON_TOP + 0.9, pz)))


## Coursing: a proud band every 1.7 m all the way up. One box each, and it is the
## single cheapest thing on the whole bridge — it converts four granite boxes into
## laid masonry, because at the sun's 11.5 degrees every band throws a line.
func _tower_coursing(b: MeshBaker, cx: float, stages: Array, levels: Array) -> void:
	var course := 1.7
	for s in stages.size():
		var foot: Vector2 = stages[s]
		var y0: float = levels[s]
		var y1: float = levels[s + 1]
		var bands := int((y1 - y0) / course)
		# Bands take their own stage's footprint plus 20 cm, so one never floats
		# clear of the stone it belongs to where the tower steps in.
		for i in range(1, bands + 1):
			var y := y0 + float(i) * course
			if y > y1 - 0.5:
				break
			b.add_box(Vector3(foot.x + 0.2, 0.22, foot.y + 0.2),
					Transform3D(Basis(), Vector3(cx, y, 0.0)))


## The mouth the road deck runs into. Without it the lower deck simply intersects
## a granite box; with four stones and a shadow it becomes an abutment portal,
## which is what the road actually goes through on the real bridge.
func _road_portal(trim: MeshBaker, dark: MeshBaker, face_x: float, sx: float) -> void:
	var head_y := ROAD_Y + 3.5
	for zi in 2:
		var sz := -1.0 if zi == 0 else 1.0
		trim.add_box(Vector3(1.4, head_y - ROAD_Y + 1.2, 1.1),
				Transform3D(Basis(), Vector3(face_x + sx * 0.2,
						(head_y + ROAD_Y - 1.2) * 0.5, sz * 5.6)))
	trim.add_box(Vector3(1.4, 1.0, 12.3),
			Transform3D(Basis(), Vector3(face_x + sx * 0.2, head_y + 0.5, 0.0)))
	# The opening itself. There is no hole to cut in a baked mesh, so the mouth is
	# a dark panel sitting flush in the tower face, 0.4 m behind jambs that project
	# 0.5: it is the SHADOW GAP between the two that reads as a way in, not the
	# panel, which is why the jamb projection and this offset must stay paired.
	dark.add_box(Vector3(0.30, head_y - ROAD_Y + 0.4, 10.2),
			Transform3D(Basis(), Vector3(face_x - sx * 0.14,
					(head_y + ROAD_Y - 0.4) * 0.5, 0.0)))


# --- The suspended road deck -------------------------------------------------

## The other half of "double deck". 14 m below the player and unreachable, so it
## can never be mistaken for somewhere to walk, but it is what makes the arch make
## sense: through the middle it HANGS from the lower chord, at the quarter points
## it threads between the splayed ribs, and near the banks the arch has dropped
## below it and it is PROPPED UP off the upper chord instead. The crossover is
## computed from the curve, so it stays right if the arch is ever retuned.
func _build_road_deck(b: MeshBaker, plates: MeshBaker) -> void:
	var span := ROAD_END_X * 2.0
	b.add_box(Vector3(span, 0.34, ROAD_HALF_WIDTH * 2.0),
			Transform3D(Basis(), Vector3(0.0, ROAD_Y - 0.17, 0.0)))

	for si in 2:
		var side := -1.0 if si == 0 else 1.0
		var z: float = side * (ROAD_HALF_WIDTH + 0.16)
		# Edge girder and a two-rail parapet — enough to read as a road at 14 m.
		b.add_box(Vector3(span, 0.78, 0.30), Transform3D(Basis(), Vector3(0.0, ROAD_Y - 0.72, z)))
		b.add_box(Vector3(span, 0.10, 0.18), Transform3D(Basis(), Vector3(0.0, ROAD_Y + 1.00, z)))
		b.add_box(Vector3(span, 0.08, 0.14), Transform3D(Basis(), Vector3(0.0, ROAD_Y + 0.60, z)))

	var stations := int(span / ROAD_HANGER_PITCH)
	for i in stations + 1:
		var x := lerpf(-ROAD_END_X, ROAD_END_X, float(i) / float(stations))
		# Past the tower's inner face the road is inside granite; anything here
		# would be paid for and never seen.
		if absf(x) > TOWER_X - 6.0:
			continue
		var t := ArchCurve.t_at_x(x)
		var lower_y := ArchCurve.chord_y(t, ArchCurve.LOWER)
		var upper_y := ArchCurve.chord_y(t, ArchCurve.UPPER)
		# How far the road sits under the lower chord / over the upper one. Both
		# go negative in the band where the road is threading BETWEEN the chords,
		# and that is the case the lateral brace exists for. Choosing on these
		# rather than on hard x thresholds is what keeps the three support modes
		# meeting real steel if the arch is ever retuned.
		var under_lower := lower_y - ROAD_Y
		var over_upper := ROAD_Y - upper_y
		if i % 2 == 1:
			# Cross beam under the slab at every other station, tying the two edge
			# girders together — the road wants transverse rhythm as much as the
			# deck above it does.
			b.add_box(Vector3(0.26, 0.40, ROAD_HALF_WIDTH * 2.0 + 0.5),
					Transform3D(Basis(), Vector3(x, ROAD_Y - 0.54, 0.0)))
		for zi in 2:
			var side := -1.0 if zi == 0 else 1.0
			# Every support meets the road in the plane of its edge girder, and a
			# hanger therefore rises PAST the two parapet rails on its way to the
			# arch — which is what holds them up. Move this inboard and the rails
			# are two lines floating 14 m over the river with nothing under them.
			var girder_z: float = side * (ROAD_HALF_WIDTH + 0.16)
			var edge := Vector3(x, ROAD_Y - 0.10, girder_z)
			var rib := side * ArchCurve.rib_z(t)
			if under_lower >= 0.8:
				# Arch overhead: a hanger up to the lower chord.
				IronKit.bar(b, edge, Vector3(x, lower_y, rib), 0.22, 0.11, Vector3.RIGHT)
			elif over_upper >= 0.8:
				# Arch already below: a prop down onto the upper chord.
				IronKit.bar(b, Vector3(x, ROAD_Y - 0.30, girder_z),
						Vector3(x, upper_y, rib), 0.26, 0.13, Vector3.RIGHT)
			elif i % 2 == 0:
				# Threading between the ribs: braced sideways into the rib. The
				# height is clamped between the chords so the brace always lands on
				# web or on a chord, never in the gap under the arch.
				var brace_y := clampf(ROAD_Y + 0.10, minf(lower_y, upper_y),
						maxf(lower_y, upper_y))
				var start := Vector3(x, brace_y, girder_z)
				IronKit.bar(b, start,
						Vector3(x, brace_y, rib - side * ArchCurve.RIB_WIDTH * 0.5),
						0.20, 0.10, Vector3.UP)
				IronKit.bar(b, edge, start, 0.18, 0.10, Vector3.RIGHT)
				IronKit.gusset(plates, start, 0.5, 0.10, Vector3.UP, Vector3.BACK)


# --- Layout helpers ----------------------------------------------------------

## Centres on a symmetric ladder through x = 0. Structure — posts, brackets —
## wants a member ON the centreline and one at each end; a course offset half a
## bay is for paving.
func _ladder(half_extent: float, pitch: float) -> Array[float]:
	var out: Array[float] = []
	var count := int(half_extent / pitch)
	for i in range(-count, count + 1):
		out.append(float(i) * pitch)
	return out


func _near_any(values: Array[float], x: float) -> bool:
	for v in values:
		if absf(v - x) < 0.01:
			return true
	return false
