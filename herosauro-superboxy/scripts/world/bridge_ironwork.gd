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
## and delete the iron half of bridge_arena.gd's _build_parapets() / _build_arch()
## / _build_lattice(). Every part is behind its own flag if some of it must stay.
##
## SCALE HONESTY. The scene is compressed ~3.5x vertically (17 m of deck-to-water
## against the real 60 m), so the arch cannot have its true 0.26 rise/span without
## the springings ending up 11 m under the river. They are dropped to -17.6 —
## just under the opaque water, where the granite towers hide them — which buys
## rise/span ~0.16. The crescent, the lattice, the splay and the deck relationship
## are all true; the arc is flatter than Porto's. See BridgeArchCurve.

const Curve := preload("res://scripts/world/bridge/arch_curve.gd")
const Kit := preload("res://scripts/world/bridge/iron_kit.gd")

# --- Mirrored from bridge_arena.gd -------------------------------------------
# That script has no class_name, so these cannot be imported. They are the deck
# cross-section this ironwork hangs off; if bridge_arena.gd moves one, move it
# here too or the parapet floats and the fascia girders bite into the slab.

const DECK_LENGTH := 100.0
const DECK_HALF_WIDTH := 7.0
const DECK_TOP := 2.0
const DECK_BOTTOM := 0.0
const WALKWAY_TOP := 2.13          # DECK_TOP + KERB_RISE
const PARAPET_MID := 6.775
const PLINTH_TOP := 2.55           # top of the granite base course the railing stands on

# --- Deck framing ------------------------------------------------------------
# The slab in the .tscn stops dead at y = 0 and hangs there. Real deck spans have
# their main girders BELOW the roadway, and hanging them there does three things
# at once: the deck gains 1.85 m of visible depth from the river, the arch gets
# something structural to bear against at the crown, and the spandrel columns get
# somewhere to land that is not the underside of a granite box.

const FRAME_BOTTOM := -1.85
const FASCIA_Z := 6.85             # main girder centreline, 15 cm inboard of the fascia
const FASCIA_PITCH := 2.50         # panel length of the deck girder lattice
const CROSS_PITCH := 5.0           # transverse floor beams
const CROSS_TOP := -1.10
const CROSS_BOTTOM := -1.80
const FRAME_END_X := 49.8          # stops just short of the abutment faces

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
# Kick rail, lattice frieze, mid rail, handrail — the same criss-cross as the
# arch, at 1/40 the size. Everything tops out at 3.33: exactly 1.20 m over the
# footway, which is the ceiling before a third-person camera starts fighting it.

const RAIL_TOP := 3.33
const RAIL_KICK_Y := 2.68
const RAIL_MID_Y := 3.145
const RAIL_HAND_Y := 3.26
const LATTICE_LOW := 2.75
const LATTICE_HIGH := 3.10
const POST_PITCH := 2.5
const HEAVY_POST_PITCH := 10.0
const PARAPET_END_X := 49.6

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
## The coping course over bridge_arena.gd's granite plinth. Off if that plinth
## ever grows its own cap.
@export var build_plinth_cap: bool = true
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
		_build_parapets(rail, trim)
	if build_towers:
		_build_towers(stone, trim, web)
	if build_road_deck:
		_build_road_deck(web, iron)

	# Thin ironwork is far under an SDFGI cascade-0 cell, so voxelising it only
	# ever adds leak noise; the granite masses are big enough to be worth bouncing.
	_commit(iron, ToonFactory.iron(IRON_MAIN, 1.4, 0.42, 0.58), "Ironwork", false)
	_commit(web, ToonFactory.iron(IRON_WEB, 1.0, 0.30, 0.70), "IronLattice", false)
	_commit(rail, ToonFactory.iron(IRON_RAIL, 0.9, 0.28, 0.50), "ParapetIron", false)
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
			var upper := Curve.polyline(Curve.UPPER, side, plane, ARCH_BAYS)
			var lower := Curve.polyline(Curve.LOWER, side, plane, ARCH_BAYS)
			Kit.sweep(iron, upper, CHORD_W, CHORD_H)
			Kit.sweep(iron, lower, CHORD_W, CHORD_H * 0.92)
			# Gussets only on the outboard plane: on the inboard one they are
			# behind 1.5 m of lattice and nobody will ever resolve them.
			var gusset_target: MeshBaker = iron if plane > 0.0 else null
			Kit.lattice_web(web, upper, lower, WEB_W, WEB_T, Vector3.BACK,
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
		Kit.splice(b, chord[i], tangent, CHORD_W + 0.14, CHORD_H + 0.12, 0.46)


## Diagonal lacing across the 1.5 m width of one rib, top and bottom. Without it
## the two chord planes are two unrelated flat trusses, and the rib reads as a
## cut-out the moment the camera looks down at it from the deck.
func _rib_lacing(b: MeshBaker, side: float) -> void:
	for ci in 2:
		var chord := Curve.UPPER if ci == 0 else Curve.LOWER
		for i in range(0, ARCH_BAYS - 1, 2):
			var t0 := -1.0 + 2.0 * float(i) / float(ARCH_BAYS)
			var t1 := -1.0 + 2.0 * float(i + 2) / float(ARCH_BAYS)
			var a := Curve.point(t0, chord, side, -1.0)
			var bb := Curve.point(t1, chord, side, 1.0)
			var c := Curve.point(t0, chord, side, 1.0)
			var d := Curve.point(t1, chord, side, -1.0)
			Kit.bar(b, a, bb, WEB_W * 0.8, WEB_T, Vector3.UP)
			Kit.bar(b, c, d, WEB_W * 0.8, WEB_T, Vector3.UP)


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
	var t_inner := Curve.t_at_height(ROAD_Y - 0.9, Curve.LOWER)
	var t_outer := Curve.t_at_height(ROAD_Y - 1.4, Curve.UPPER)
	for i in range(0, ARCH_BAYS - 1, 2):
		var t0 := -1.0 + 2.0 * float(i) / float(ARCH_BAYS)
		var t1 := -1.0 + 2.0 * float(i + 2) / float(ARCH_BAYS)
		var mid := absf((t0 + t1) * 0.5)
		var chord := -1
		if mid < t_inner:
			chord = Curve.LOWER
		elif mid > t_outer:
			chord = Curve.UPPER
		if chord < 0:
			continue
		var a0 := Curve.point(t0, chord, -1.0, -1.0)
		var a1 := Curve.point(t0, chord, 1.0, -1.0)
		var b0 := Curve.point(t1, chord, -1.0, -1.0)
		var b1 := Curve.point(t1, chord, 1.0, -1.0)
		Kit.bar(b, a0, a1, WEB_W, WEB_T, Vector3.UP)
		Kit.bar(b, a0, b1, WEB_W * 0.8, WEB_T, Vector3.UP)
		Kit.bar(b, a1, b0, WEB_W * 0.8, WEB_T, Vector3.UP)
		Kit.gusset(plates, a0, GUSSET_SIZE * 0.9, WEB_T * 2.4, Vector3.UP, Vector3.BACK)
		Kit.gusset(plates, a1, GUSSET_SIZE * 0.9, WEB_T * 2.4, Vector3.UP, Vector3.BACK)


## The two-hinged arch's defining detail: a pin, not a fixing. Both chords have
## converged to nothing here, so the shoe is a slab of plate either side of a
## transverse pin, bedded into the granite. It is 2 m under the waterline and
## half inside the tower — but the last 5 m of chord taper INTO something, which
## is the whole point of a crescent, and a chord that just stopped in mid-air
## would undo the shape.
func _hinge_shoes(b: MeshBaker, side: float) -> void:
	for si in 2:
		var t := -1.0 if si == 0 else 1.0
		var at := Curve.point(t, Curve.UPPER, side, 0.0)
		var axis := Basis(Vector3.RIGHT, PI * 0.5)   # cylinder's local +Y onto world Z
		b.add_cylinder(0.46, Curve.RIB_WIDTH + 0.9, Transform3D(axis, at), 10)
		for pi in 2:
			var plane := -1.0 if pi == 0 else 1.0
			var cheek := at + Vector3(0.0, 0.0, side * plane * (Curve.RIB_WIDTH * 0.5 + 0.16))
			Kit.plate(b, cheek, 2.6, 1.7, 0.22, Vector3.BACK, Vector3.RIGHT)
		# Bedstone plate spreading the thrust into the masonry.
		b.add_box(Vector3(3.6, 0.34, Curve.RIB_WIDTH + 2.0),
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
			var t := Curve.t_at_x(x)
			for zi in 2:
				var side := -1.0 if zi == 0 else 1.0
				var base_y := Curve.chord_y(t, Curve.UPPER) + CHORD_H * 0.5
				var height := SPANDREL_TOP_Y - base_y
				if height <= 0.02:
					continue
				var base := Vector3(x, base_y, side * Curve.rib_z(t))
				var head_z := clampf(Curve.rib_z(t), SPANDREL_ATTACH_Z.x, SPANDREL_ATTACH_Z.y)
				var top := Vector3(x, SPANDREL_TOP_Y, side * head_z)
				# Taller columns are wider — a 14 m post at the width of a 2 m one
				# looks like it would buckle, and the eye knows it.
				var wx := clampf(1.15 + height * 0.062, 1.15, 2.10)
				var wz := clampf(0.85 + height * 0.036, 0.85, 1.35)
				Kit.lattice_tower(b, base, top, wx, wz, 0.20, SPANDREL_PANEL,
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
		Kit.lattice_girder(iron, -FRAME_END_X, FRAME_END_X, -0.02, FRAME_BOTTOM, z,
				FASCIA_PITCH, Vector2(0.62, 0.20), WEB_W * 0.55, WEB_T, 0.24)
		# Cover plates over the girder's own splices, every four panels.
		var covers := int(FRAME_END_X * 2.0 / (FASCIA_PITCH * 4.0))
		for i in covers + 1:
			var x := lerpf(-FRAME_END_X, FRAME_END_X, float(i) / float(maxi(covers, 1)))
			Kit.plate(iron, Vector3(x, (FRAME_BOTTOM - 0.02) * 0.5, z),
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
			Kit.bar(web, Vector3(x, CROSS_BOTTOM, z),
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
func _build_parapets(b: MeshBaker, trim: MeshBaker) -> void:
	var span := PARAPET_END_X * 2.0
	var posts := int(span / POST_PITCH)
	var heavies := int(span / HEAVY_POST_PITCH)

	for si in 2:
		var side := -1.0 if si == 0 else 1.0
		var z: float = side * PARAPET_MID

		if build_plinth_cap:
			# Coping over bridge_arena.gd's granite plinth: a 6 cm shadow line
			# under the ironwork, so the iron sits on stone instead of growing out
			# of it.
			trim.add_box(Vector3(span + 0.6, 0.12, 0.58),
					Transform3D(Basis(), Vector3(0.0, PLINTH_TOP - 0.06, z)))

		b.add_box(Vector3(span, 0.14, 0.34), Transform3D(Basis(), Vector3(0.0, RAIL_KICK_Y, z)))
		b.add_box(Vector3(span, 0.09, 0.26), Transform3D(Basis(), Vector3(0.0, RAIL_MID_Y, z)))
		b.add_box(Vector3(span, 0.14, 0.40), Transform3D(Basis(), Vector3(0.0, RAIL_HAND_Y, z)))

		for i in posts:
			var x0 := lerpf(-PARAPET_END_X, PARAPET_END_X, float(i) / float(posts))
			var x1 := lerpf(-PARAPET_END_X, PARAPET_END_X, float(i + 1) / float(posts))
			# One X per panel, alternating which diagonal is in front, so the run
			# reads as woven rather than as a row of identical crosses.
			var lift := 0.02 if i % 2 == 0 else -0.02
			Kit.bar(b, Vector3(x0, LATTICE_LOW, z + lift), Vector3(x1, LATTICE_HIGH, z + lift),
					0.09, 0.045, Vector3.BACK)
			Kit.bar(b, Vector3(x0, LATTICE_HIGH, z - lift), Vector3(x1, LATTICE_LOW, z - lift),
					0.09, 0.045, Vector3.BACK)
		for i in posts + 1:
			var x := lerpf(-PARAPET_END_X, PARAPET_END_X, float(i) / float(posts))
			b.add_box(Vector3(0.12, RAIL_TOP - PLINTH_TOP, 0.20),
					Transform3D(Basis(), Vector3(x, (RAIL_TOP + PLINTH_TOP) * 0.5, z)))
		for i in heavies + 1:
			var x := lerpf(-PARAPET_END_X, PARAPET_END_X, float(i) / float(heavies))
			b.add_box(Vector3(0.24, RAIL_TOP - PLINTH_TOP + 0.10, 0.32),
					Transform3D(Basis(), Vector3(x, (RAIL_TOP + PLINTH_TOP) * 0.5 - 0.05, z)))
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

		# Corbel course carrying the deck's last few metres onto the tower.
		trim.add_box(Vector3(8.8, 0.5, 17.4), Transform3D(Basis(), Vector3(cx, -0.15, 0.0)))

		if build_road_deck:
			_road_portal(trim, dark, cx - sx * (stages[1].x * 0.5), sx)


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
	# The opening itself: an unlit panel set back inside the jambs.
	dark.add_box(Vector3(0.4, head_y - ROAD_Y + 0.4, 10.2),
			Transform3D(Basis(), Vector3(face_x - sx * 0.5,
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
		var t := Curve.t_at_x(x)
		var lower_y := Curve.chord_y(t, Curve.LOWER)
		var upper_y := Curve.chord_y(t, Curve.UPPER)
		for zi in 2:
			var side := -1.0 if zi == 0 else 1.0
			var edge := Vector3(x, ROAD_Y + 0.10, side * ROAD_HALF_WIDTH)
			var rib := side * Curve.rib_z(t)
			if lower_y > ROAD_Y + 1.6:
				# Arch overhead: a hanger up to the lower chord.
				Kit.bar(b, edge, Vector3(x, lower_y, rib), 0.22, 0.11, Vector3.RIGHT)
			elif upper_y < ROAD_Y - 1.2:
				# Arch already below: a prop down onto the upper chord.
				Kit.bar(b, Vector3(x, ROAD_Y - 0.30, side * ROAD_HALF_WIDTH),
						Vector3(x, upper_y, rib), 0.26, 0.13, Vector3.RIGHT)
			elif i % 2 == 0:
				# Threading between the ribs: braced sideways into the rib instead.
				Kit.bar(b, edge, Vector3(x, ROAD_Y + 0.10, rib - side * Curve.RIB_WIDTH * 0.5),
						0.20, 0.10, Vector3.UP)
				Kit.gusset(plates, edge, 0.5, 0.10, Vector3.UP, Vector3.BACK)
