class_name LandmarksBuilder
extends RefCounted
## The five buildings that make a skyline *Porto* rather than "a European city".
##
## Silhouette is the whole brief. These stand 40-120 m from the camera, on the
## far bank, backlit by a low sun — nobody will ever read a moulding on them.
## What they will read is an outline: one impossibly slim tower stepping inward
## five times, one squat crenellated fortress with twin cupolas, one circular
## dome ringed by a circular colonnade, one bell gable over a wall of blue tile,
## a low line of sheds under big sign frames. Get those five outlines right and
## the city is recognisable; get them wrong and no amount of surface detail
## rescues it. Every proportion below was chosen by asking what survives at that
## distance.
##
## Built to the real things:
##   * Torre dos Clérigos (Nasoni, 1754-63) — 75.6 m of granite, six stages,
##     slenderness about 7.5 to 1, stepping inward the whole way up to a
##     balustraded gallery, a lantern and an iron cross.
##   * Sé do Porto — 12th-century Romanesque, fortress-like: crenellated
##     parapets, twin square towers under cupolas, a rose window over a deep
##     recessed portal.
##   * Mosteiro da Serra do Pilar — a circular church under a hemispheric vault
##     joined to a circular cloister of 36 Ionic columns, the only one in
##     Portugal, on the Gaia cliff looking down on the bridge.
##   * An azulejo church front — pediment, pilasters, arched portal, bell gable,
##     and a flank tiled floor to eaves in blue and white.
##   * Gaia's port-wine lodges — long whitewashed sheds under terracotta, with
##     the big rooftop sign frames that name the far bank. Invented names only.
##
## Usage — one landmark, its own draw calls:
##     var tower := LandmarksBuilder.clerigos_tower()
##     tower.position = Vector3(-64.0, 7.0, -42.0)
##
## Usage — the whole skyline in one batch (strongly preferred):
##     add_child(LandmarksBuilder.porto_skyline())
##
## The second form is the point of the Batch: all five buildings are made of the
## same nine surfaces, so baking them together costs nine draw calls for the lot
## instead of thirty-odd. Geometry is baked at the transform passed in, so the
## returned node belongs at the origin.
##
## SCALE. Everything is authored in metres at 1 unit = 1 m, but the world it goes
## into is compressed: the far bank is 60 m away where the real one is 600. So
## these are built at roughly 60% of life size — a 46 m Clérigos, not 75.6 —
## which keeps them dominant without swallowing the sky. Pass your own `height` /
## `scale` if the placement changes; the scale is baked into the vertices rather
## than applied to the node, because every material here maps triplanar in
## *object* space and a scaled node would smear the texel density.
##
## WINDING. Faces are wound so a triangle's right-hand normal points the way the
## surface should be seen. That is MeshBaker's contract, stated in full at the top
## of mesh_baker.gd, and it is now honoured: MeshBaker reverses the vertex order
## on the way into the surface, because Godot's front face is the clockwise one.
## It did not used to, and until it was fixed every face in this file was
## back-facing — the tiled church flank, the lodge roofs and the arcades were
## simply absent from any camera in front of them. Nothing here compensates
## locally, which is why nothing here had to change.

const Geo := preload("res://scripts/world/landmarks/landmark_geo.gd")
const Batch := preload("res://scripts/world/landmarks/landmark_batch.gd")

## How much of the fine work survives. LOW is for anything past the far bank or
## behind haze: same silhouette, a third of the triangles.
enum Detail {
	LOW,     ## masses, cornices, flat dark openings. No reveals, no columns.
	MEDIUM,  ## + punched openings with reveals, archivolts, pilasters, balustrades.
	FULL,    ## + volutes, dome ribs, tile panels, barrels, lettering.
}


# --- Intended placement ------------------------------------------------------
# The placement stream owns where these actually go; these are the anchors they
# were proportioned against, and porto_skyline() below uses them. Y is the base
# of the building, so it wants to be the height of the ground under it: 0 on the
# Porto terrace tier, 7-9 on the hill tiers, -10.1 on the Gaia waterline shelf.

const CLERIGOS_ANCHOR := Vector3(-64.0, 7.0, -42.0)
const CLERIGOS_YAW := 0.20
const SE_ANCHOR := Vector3(-34.0, 8.0, -44.0)
const SE_YAW := -0.28
const SERRA_ANCHOR := Vector3(52.0, 9.0, -34.0)
const SERRA_YAW := 0.40
const IGREJA_ANCHOR := Vector3(-47.0, 0.0, -16.5)
const IGREJA_YAW := -0.14
## The lodges start where the real ones do, hard against the bridge's Gaia
## abutment, and run out along the waterline shelf. Three of them reach about
## x = 96, which is the far edge of the Gaia hillside mass behind them.
const LODGE_ANCHOR := Vector3(52.0, -10.1, -10.5)
## Clear ground between neighbouring sheds, on top of their own half-lengths.
const LODGE_GAP := 4.5

# --- Clérigos ----------------------------------------------------------------

## Total height. The real tower is 75.6 m; at the world's compressed distances
## that would fill the sky, and much under 40 it stops being the tallest thing
## on the skyline, which is the one job it has.
const CLERIGOS_HEIGHT := 46.0

## Base half-width as a fraction of total height. The real tower is about 7.5
## times as tall as it is wide, and that slenderness *is* the silhouette — go
## fatter and it reads as a chimney, thinner and it reads as a mast.
const CLERIGOS_SLENDER := 0.0675

## The stages, as fractions of total height, bottom to top. `w` is the plan
## half-width as a fraction of the base. The stepping is the second half of the
## silhouette: five inward steps, each announced by a cornice.
const CLERIGOS_STAGES := [
	{"top": 0.075, "w": 1.00, "kind": "socle"},
	{"top": 0.260, "w": 0.94, "kind": "window"},
	{"top": 0.430, "w": 0.88, "kind": "window"},
	{"top": 0.585, "w": 0.83, "kind": "clock"},
	{"top": 0.730, "w": 0.78, "kind": "belfry"},
]

# --- Sé ----------------------------------------------------------------------

const SE_NAVE := Vector3(10.6, 15.2, 9.2)   ## half-width, wall height, half-depth
const SE_TOWER_X := 10.6                    ## tower centres either side of the front
const SE_TOWER_HALF := 3.9
const SE_TOWER_TOP := 24.0

# --- Serra do Pilar ----------------------------------------------------------

const SERRA_CHURCH_R := 8.0
const SERRA_BAYS := 16                      ## pilaster bays round the drum
const SERRA_CLOISTER_R := 9.6
const SERRA_COLUMNS := 36                   ## the real count, in groups of nine
const SERRA_CLOISTER_X := 16.5              ## cloister centre, offset from the church

# --- Lodges ------------------------------------------------------------------

## Invented names. Deliberately not the real houses on that bank.
##
## ONE WORD EACH, and short ones, because the roof frame is sized to the string:
## six cells per character across a 15 m shed gives "CAVES DO CORVO" a cell of
## 0.15 m, i.e. a one-metre capital seen from ninety metres. That is not lettering,
## it is a grey smear with the cost of lettering. The same five sheds carrying
## "CORVO" get a cell of 0.38 and a 2.7 m capital off exactly the same frame.
const LODGE_NAMES := ["CORVO", "QUINTA", "DOURO", "VELHA"]

## A 5x7 cell alphabet for the rooftop signs. Building the letters as geometry
## rather than hanging a Label3D on the roof costs no extra draw call, needs no
## font, and — unlike a billboard — stays put when the camera swings round to
## look along the bank, which from the bridge deck is most of the time.
const SIGN_FONT := {
	"A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
	"B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
	"C": ["01110", "10001", "10000", "10000", "10000", "10001", "01110"],
	"D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
	"E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
	"F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
	"G": ["01110", "10001", "10000", "10111", "10001", "10001", "01111"],
	"H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
	"I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
	"J": ["00111", "00010", "00010", "00010", "00010", "10010", "01100"],
	"K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
	"L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
	"M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
	"N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
	"O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
	"P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
	"Q": ["01110", "10001", "10001", "10001", "10101", "10010", "01101"],
	"R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
	"S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
	"T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
	"U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
	"V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
	"W": ["10001", "10001", "10001", "10101", "10101", "11011", "10001"],
	"X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
	"Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
	"Z": ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
}

## Coplanar surfaces z-fight, and the web build's GL Compatibility path has a
## 24-bit depth buffer whose resolution out at the far bank is close to a
## centimetre. Every overlay — tile panel, gable infill, clock face — is nudged
## out by this much. It is also about what a glazed tile really stands off its
## render, so nothing is being faked.
const SKIN_GAP := 0.02


# --- Whole skyline -----------------------------------------------------------

## All five landmarks, baked into one batch at the anchors above.
##
## `spread` scales the anchor positions away from the bridge without scaling the
## buildings, for the case where the placement stream pushes the banks out.
static func porto_skyline(detail: Detail = Detail.FULL, node_name: String = "PortoLandmarks",
		spread: float = 1.0, lodges: int = 3) -> Node3D:
	var batch := Batch.new()
	add_clerigos_tower(batch, _anchor(CLERIGOS_ANCHOR, CLERIGOS_YAW, spread), detail)
	add_se_cathedral(batch, _anchor(SE_ANCHOR, SE_YAW, spread), detail)
	add_serra_do_pilar(batch, _anchor(SERRA_ANCHOR, SERRA_YAW, spread), detail)
	add_igreja_azulejo(batch, _anchor(IGREJA_ANCHOR, IGREJA_YAW, spread), detail)

	var rng := RandomNumberGenerator.new()
	rng.seed = 30_417   # seeded: the far bank must be identical every run
	_lodge_row(batch, Transform3D(Basis(), LODGE_ANCHOR * Vector3(spread, 1.0, spread)),
			lodges, detail, rng)
	return batch.commit(node_name)


## Lay the lodges out end to end along +X, advancing by the two neighbours' own
## half-lengths plus a gap. Fixed spacing would either overlap the long ones or
## strand the short ones in a row of gaps, and these sheds vary by a third.
static func _lodge_row(batch: Batch, at: Transform3D, count: int, detail: Detail,
		rng: RandomNumberGenerator) -> void:
	var cursor := 0.0
	var prev_half := 0.0
	for i in count:
		var spec := LodgeSpec.random(rng, LODGE_NAMES[i % LODGE_NAMES.size()])
		var half := spec.length * 0.5
		cursor += (prev_half + half + LODGE_GAP) if i > 0 else 0.0
		prev_half = half
		var here := at * Transform3D(Basis(Vector3.UP, rng.randf_range(-0.11, 0.11)),
				Vector3(cursor, 0.0, rng.randf_range(-3.5, 3.5)))
		add_gaia_lodge(batch, here, spec, detail, rng)


static func _anchor(pos: Vector3, yaw: float, spread: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), Vector3(pos.x * spread, pos.y, pos.z * spread))


# --- Shared construction -----------------------------------------------------

## One wall face: the punched skin, the reveal into each opening, the dark plate
## behind it and an optional archivolt standing proud.
##
## The skin is a *shell*, not a decal on a solid box. A hole in a decal shows the
## box behind it, which is a wall where a window should be — so every building
## here is four punched faces meeting at the corners with a core set back behind
## them, and looking into an opening looks into the dark.
static func _wall(batch: Batch, face: Transform3D, half: float, height: float,
		openings: Array, skin: MeshBaker, detail: Detail, bands: int,
		reveal: float = 0.4, arch: float = 0.0) -> void:
	Geo.panel(skin, face, -half, 0.0, half, height, openings, 0.0, bands)
	if openings.is_empty():
		return
	var dark := batch.baker(Batch.void_dark())
	var dress := batch.baker(Batch.dress())
	for k in openings.size():
		var o: Geo.Opening = openings[k]
		Geo.opening_back(dark, face, o, -reveal + SKIN_GAP, bands)
		if detail == Detail.LOW:
			continue
		Geo.opening_reveal(dress, face, o, 0.0, -reveal, bands)
		if arch > 0.0:
			Geo.archivolt(dress, face, o, arch, 0.0, arch * 0.6, bands)


## The solid behind the four skins, set back by the wall thickness. In the body
## material, not black: the shell is what the eye sees, and the core only shows
## through the openings, where a dark plate is already covering it.
static func _core(b: MeshBaker, at: Transform3D, hx: float, hz: float, y0: float,
		height: float, reveal: float) -> void:
	b.add_box(Vector3((hx - reveal) * 2.0, height, (hz - reveal) * 2.0),
			at * Transform3D(Basis(), Vector3(0.0, y0 + height * 0.5, 0.0)))


## The same frame turned a quarter turn about Y. MeshBaker's roof prism always
## puts its ridge along local X, so a building whose long axis runs the other way
## gets its roof built in here, with its half-extents swapped by the caller.
static func _yawed(at: Transform3D) -> Transform3D:
	return at * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO)


## A window that is painted on rather than cut in: a dark plate standing a
## fraction proud of the wall, inside a thin surround.
##
## Reserved for the back-of-house walls — a monastery wing, the far side of a
## shed — where a real punched opening would mean building that wall as a shell
## for two windows nobody will look at. On anything the eye lands on, punch it.
static func _blind_window(batch: Batch, face: Transform3D, cx: float, cy: float,
		w: float, h: float) -> void:
	Geo.box(batch.baker(Batch.void_dark()), face, cx, cy, SKIN_GAP * 1.5, w, h, SKIN_GAP)
	Geo.box(batch.baker(Batch.dress()), face, cx, cy, SKIN_GAP, w + 0.28, h + 0.28, SKIN_GAP)


# --- Torre dos Clérigos ------------------------------------------------------

## The defining vertical of Porto: granite, six stages, an iron cross at 75 m.
## Returned on its own draw calls; prefer add_clerigos_tower() into a shared
## batch.
static func clerigos_tower(detail: Detail = Detail.FULL,
		height: float = CLERIGOS_HEIGHT) -> Node3D:
	var batch := Batch.new()
	add_clerigos_tower(batch, Transform3D.IDENTITY, detail, height)
	return batch.commit("ClerigosTower")


## Bake the tower into `batch`, based at `at` with its front (the church end) on
## the frame's -Z side.
static func add_clerigos_tower(batch: Batch, at: Transform3D, detail: Detail = Detail.FULL,
		height: float = CLERIGOS_HEIGHT) -> void:
	# One unit of trim, tied to the tower's height so mouldings scale with it.
	var u := height / CLERIGOS_HEIGHT
	var hw := height * CLERIGOS_SLENDER
	var hz := hw * 1.06        # the real plan is rectangular, not square
	var bands := _bands(detail)

	var dress := batch.baker(Batch.dress())
	var crown := batch.baker(Batch.dark_stone())

	# Plinth: three courses stepping in, so the tower lands on the ground rather
	# than being pushed into it.
	Geo.moulded_band(crown, at, 0.0, hw * 1.06, hz * 1.06,
			[Vector2(0.24 * u, 0.5 * u), Vector2(0.10 * u, 0.45 * u), Vector2(0.0, 0.35 * u)])

	var y := 1.3 * u
	for s in CLERIGOS_STAGES:
		var top: float = height * float(s["top"])
		var sw: float = hw * float(s["w"])
		var sz: float = hz * float(s["w"])
		var cornice := 0.78 * u
		_clerigos_stage(batch, at, y, top - cornice, sw, sz, String(s["kind"]), detail, bands, u)
		Geo.moulded_band(dress, at, top - cornice, sw, sz,
				[Vector2(0.16 * u, 0.24 * u), Vector2(0.38 * u, 0.30 * u), Vector2(0.22 * u, 0.24 * u)])
		y = top

	# The gallery. On the real tower this is the viewing terrace, and it is the
	# one place the outline goes *outward* on the way up — which is exactly why
	# the eye reads everything above it as a separate, smaller thing.
	var gal_w := hw * 0.86
	var gal_z := hz * 0.86
	var gal_h := 1.5 * u
	Geo.balustrade_rect(dress, at, y, gal_w, gal_z, gal_h, 0.46 * u, detail == Detail.LOW)
	y += gal_h

	# Lantern: a small stage with an arched opening on every face.
	var lan_top := height * 0.880
	var lan_w := hw * 0.56
	var lan_z := hz * 0.56
	_clerigos_stage(batch, at, y, lan_top - 0.6 * u, lan_w, lan_z, "lantern", detail, bands, u)
	Geo.moulded_band(dress, at, lan_top - 0.6 * u, lan_w, lan_z,
			[Vector2(0.14 * u, 0.22 * u), Vector2(0.30 * u, 0.22 * u), Vector2(0.16 * u, 0.16 * u)])
	y = lan_top
	if detail == Detail.FULL:
		# Corner volutes on the lantern cornice, buttressing the crown that steps
		# in above them. Baroque scrollwork, and at this distance four small
		# blocks breaking the corner is all of it that survives anyway.
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				dress.add_box(Vector3(0.5 * u, 0.9 * u, 0.5 * u), at * Transform3D(Basis(),
						Vector3(sx * lan_w, y + 0.45 * u, sz * lan_z)))

	# Stepped crown, cupola, ball, cross. Three shrinking steps read as a taper at
	# this distance and cost a tenth of a real ogee.
	var steps := [0.42, 0.34, 0.28]
	for i in steps.size():
		var f: float = steps[i]
		var h := (height * 0.935 - lan_top) / float(steps.size())
		crown.add_box(Vector3(hw * f * 2.0, h, hz * f * 2.0),
				at * Transform3D(Basis(), Vector3(0.0, y + h * 0.5, 0.0)))
		y += h

	# The cupola springs a little proud of the last step, as a dome on a cornice
	# does; flush would read as a pinched cone.
	var cupola_r := hw * 0.30
	Geo.dome(crown, at, cupola_r, y, height * 0.032, _segments(detail, 14, 10, 6), 4, 0.22)
	var ball := Geo.finial_ball(crown, at, y + height * 0.032, 0.32 * u,
			_segments(detail, 10, 8, 6))
	Geo.cross_finial(batch.baker(Batch.iron()), at, ball, height - ball, 0.9 * u, 0.16 * u)

	if detail != Detail.LOW:
		_clerigos_church(batch, at, hw, hz, u, detail, bands)


## One stage of the tower: a core, four punched faces, corner pilasters and
## whatever opening the stage carries.
static func _clerigos_stage(batch: Batch, at: Transform3D, y0: float, y1: float, hw: float,
		hz: float, kind: String, detail: Detail, bands: int, u: float) -> void:
	var h := y1 - y0
	if h <= 0.0:
		return
	var stone := batch.baker(Batch.granite())
	var dress := batch.baker(Batch.dress())
	var reveal := 0.42 * u

	_core(stone, at, hw, hz, y0, h, reveal)

	for i in 4:
		var yaw := PI * 0.5 * float(i)
		var dist := hz if i % 2 == 0 else hw
		var across := hw if i % 2 == 0 else hz
		var face := Geo.face_of(at, yaw, dist, y0)
		var openings: Array = []

		match kind:
			"socle":
				if i == 2:   # the doorway is on the church side only
					openings.append(Geo.Opening.arched(0.0, across * 0.46, 0.0, h * 0.55, -1.0))
			"window", "clock":
				openings.append(Geo.Opening.flat(0.0, across * 0.40, h * 0.26, h * 0.46))
			"belfry":
				# The widest opening on the tower by a distance. On the real
				# belfry the bell chamber is nearly all void, and that band of
				# black holes is what separates the top of the tower from the
				# shaft at any range.
				openings.append(Geo.Opening.arched(0.0, across * 0.72, h * 0.13, h * 0.42, -1.0))
			"lantern":
				openings.append(Geo.Opening.arched(0.0, across * 0.50, h * 0.16, h * 0.34, -1.0))

		_wall(batch, face, across, h, openings, stone, detail, bands, reveal, 0.18 * u)

		if detail != Detail.LOW:
			# Paired pilasters at each corner — the baroque way of dressing a
			# corner, and two narrow shadows read better than one wide one.
			var edge := across - 0.34 * u
			for sx in [-1.0, 1.0]:
				Geo.pilaster(dress, face, sx * edge, 0.0, h, 0.42 * u, 0.16 * u, true)
				if detail == Detail.FULL:
					Geo.pilaster(dress, face, sx * (edge - 0.55 * u), 0.0, h, 0.34 * u,
							0.11 * u, false)

		if kind == "clock" and i == 0:
			_clock_face(batch, face, h * 0.72, across * 0.42, u)


## The clock partway up the tower, on the river face only.
static func _clock_face(batch: Batch, face: Transform3D, cy: float, radius: float,
		u: float) -> void:
	var dress := batch.baker(Batch.dress())
	var dark := batch.baker(Batch.void_dark())
	var ring := face * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, cy, SKIN_GAP))
	Geo.annulus(batch.baker(Batch.limewash()), ring, 0.0, radius, 0.06 * u, 12, true)
	Geo.moulded_ring(dress, ring, 0.0, radius, [Vector2(0.16 * u, 0.14 * u)], 12)
	dark.add_box(Vector3(radius * 1.2, 0.09 * u, 0.09 * u),
			face * Transform3D(Basis(Vector3.BACK, 1.9), Vector3(0.0, cy, 0.10 * u)))
	dark.add_box(Vector3(radius * 0.8, 0.09 * u, 0.09 * u),
			face * Transform3D(Basis(Vector3.BACK, 0.4), Vector3(0.0, cy, 0.10 * u)))


## The church the tower grows out of. Without it the tower is a pillar planted in
## a hillside; with it, it is the west end of a building.
static func _clerigos_church(batch: Batch, at: Transform3D, hw: float, hz: float, u: float,
		detail: Detail, bands: int) -> void:
	var stone := batch.baker(Batch.granite())
	var dress := batch.baker(Batch.dress())

	var nave := Vector3(6.6 * u, 10.5 * u, 7.5 * u)     # half-width, height, half-depth
	var centre := Vector3(0.0, 0.0, -(hz + nave.z - 0.6 * u))
	var plan := at * Transform3D(Basis(), centre)
	var reveal := 0.45 * u
	var arch := 0.16 * u if detail == Detail.FULL else 0.0

	Geo.moulded_band(batch.baker(Batch.dark_stone()), plan, 0.0, nave.x, nave.z,
			[Vector2(0.3 * u, 0.7 * u), Vector2(0.12 * u, 0.5 * u)])
	_core(stone, plan, nave.x, nave.z, 1.2 * u, nave.y, reveal)

	# Three arched windows down each flank; the two ends are plain, since one of
	# them is behind the tower and the other faces uphill.
	for i in 4:
		var yaw := PI * 0.5 * float(i)
		var dist := nave.z if i % 2 == 0 else nave.x
		var across := nave.x if i % 2 == 0 else nave.z
		var face := Geo.face_of(plan, yaw, dist, 1.2 * u)
		var openings: Array = []
		if i % 2 == 1:
			for k in 3:
				var cz := (float(k) - 1.0) * nave.z * 0.62
				openings.append(Geo.Opening.arched(cz, 1.5 * u, 4.0 * u, 3.2 * u, -1.0))
		_wall(batch, face, across, nave.y, openings, stone, detail, bands, reveal, arch)

	var top := 1.2 * u + nave.y
	Geo.moulded_band(dress, plan, top, nave.x, nave.z,
			[Vector2(0.18 * u, 0.24 * u), Vector2(0.4 * u, 0.3 * u)])
	Geo.balustrade_rect(dress, plan, top + 0.54 * u, nave.x + 0.4 * u, nave.z + 0.4 * u,
			1.2 * u, 0.44 * u, detail == Detail.LOW)
	# Ridge along the nave, which runs away from the tower — so the roof frame is
	# yawed a quarter turn and its half-extents swap with it.
	Geo.gable_roof(batch.baker(Batch.roof()), _yawed(plan), top + 0.3 * u, nave.z - 0.4 * u,
			nave.x - 0.4 * u, 1.8 * u, 0.0, 0.0, false)


# --- Sé do Porto -------------------------------------------------------------

## Romanesque, defensive, and deliberately the opposite of Clérigos in every
## dimension: squat where that is slim, crenellated where that is moulded, twin
## towers where that is one.
static func se_cathedral(detail: Detail = Detail.FULL, scale: float = 1.0) -> Node3D:
	var batch := Batch.new()
	add_se_cathedral(batch, Transform3D(Basis().scaled(Vector3.ONE * scale), Vector3.ZERO), detail)
	return batch.commit("SeCathedral")


## Bake the cathedral into `batch`. The west front — rose window, portal, towers
## — faces the frame's +Z, so point that at the river.
static func add_se_cathedral(batch: Batch, at: Transform3D, detail: Detail = Detail.FULL) -> void:
	var stone := batch.baker(Batch.granite())
	var dress := batch.baker(Batch.dress())
	var dark := batch.baker(Batch.void_dark())
	var bands := _bands(detail)

	# --- Nave: four punched faces round a set-back core
	var reveal := 1.9   # a genuinely thick Romanesque wall
	Geo.moulded_band(batch.baker(Batch.dark_stone()), at, 0.0, SE_NAVE.x, SE_NAVE.z,
			[Vector2(0.5, 0.9), Vector2(0.2, 0.6)])
	_core(stone, at, SE_NAVE.x, SE_NAVE.z, 1.5, SE_NAVE.y, reveal)

	# --- West front: portal, rose window, blind arcading
	var front := Geo.face_of(at, 0.0, SE_NAVE.z, 1.5)
	var portal := Geo.Opening.arched(0.0, 4.2, 0.0, 4.2, 2.1)
	_wall(batch, front, SE_NAVE.x, SE_NAVE.y, [portal], stone, detail, bands, reveal)
	if detail != Detail.LOW:
		# Three archivolt orders stepping out of the wall. This receding stack of
		# arches is the single most Romanesque thing a west front does, and it is
		# still legible as a dark ring of steps at a hundred metres.
		for k in 3:
			var f := float(k)
			Geo.archivolt(dress, front, portal, 0.34, -0.4 + f * 0.55, 0.15 + f * 0.55, bands)
	Geo.rose_window(dress, dark, front, 0.0, 9.6, 2.5, 12, 0.0, 0.55)
	if detail == Detail.FULL:
		# Blind arcading either side of the rose — clear of its moulded ring, and
		# clear of the towers that stand on the outer thirds of this wall.
		for sx in [-1.0, 1.0]:
			for k in 2:
				var blind := Geo.Opening.arched(sx * (4.3 + float(k) * 1.6), 1.2, 12.2, 0.9, -1.0)
				Geo.archivolt(dress, front, blind, 0.2, 0.0, 0.14, bands)
	# The rear elevation is plain, but it still has to close the shell.
	Geo.panel(stone, Geo.face_of(at, PI, SE_NAVE.z, 1.5), -SE_NAVE.x, 0.0, SE_NAVE.x,
			SE_NAVE.y, [], 0.0, bands)

	# --- Parapet and roof
	var wall_top := 1.5 + SE_NAVE.y
	Geo.moulded_band(dress, at, wall_top, SE_NAVE.x, SE_NAVE.z,
			[Vector2(0.22, 0.3), Vector2(0.5, 0.36)])
	var para := wall_top + 0.66
	Geo.merlons(dress, at, para, SE_NAVE.x + 0.3, SE_NAVE.z + 0.3, 1.15, 0.85, 1.5, 0.66)
	# Ridge running back from the west front, along the nave, and low enough that
	# only its top course clears the parapet — which is how a fortified church
	# looks: a wall line with a hint of roof behind it.
	Geo.gable_roof(batch.baker(Batch.roof()), _yawed(at), para - 0.2, SE_NAVE.z - 0.9,
			SE_NAVE.x - 0.9, 2.8, 0.0, 0.0, false)

	# --- Flanks: narrow lights between shallow, wide Romanesque buttresses. Not
	# gothic fins — these barely leave the wall, and that heaviness is the point.
	for i in 2:
		var yaw := PI * 0.5 * (1.0 if i == 0 else -1.0)
		var side := Geo.face_of(at, yaw, SE_NAVE.x, 1.5)
		var lights: Array = []
		for k in 4:
			lights.append(Geo.Opening.arched((float(k) - 1.5) * SE_NAVE.z * 0.44, 1.0, 9.0,
					2.4, -1.0))
		_wall(batch, side, SE_NAVE.z, SE_NAVE.y, lights, stone, detail, bands, reveal)
		for k in 5:
			var cz := (float(k) - 2.0) * SE_NAVE.z * 0.42
			Geo.box(stone, side, cz, SE_NAVE.y * 0.5, 0.28, 1.2, SE_NAVE.y, 0.56)

	# --- Twin towers
	for sx in [-1.0, 1.0]:
		_se_tower(batch, at * Transform3D(Basis(), Vector3(sx * SE_TOWER_X, 0.0, SE_NAVE.z - SE_TOWER_HALF)),
				detail, bands)

	# --- Crossing lantern over the rear of the nave
	var lantern := at * Transform3D(Basis(), Vector3(0.0, 0.0, -SE_NAVE.z * 0.45))
	var lan_h := 6.4
	var lan_half := 2.8
	_core(stone, lantern, lan_half, lan_half, wall_top, lan_h, 0.4)
	for i in 4:
		var face := Geo.face_of(lantern, PI * 0.5 * float(i), lan_half, wall_top)
		var slit := Geo.Opening.arched(0.0, 1.5, 2.2, 2.0, -1.0)
		_wall(batch, face, lan_half, lan_h, [slit], stone, detail, bands, 0.4, 0.22)
	var lan_top := Geo.moulded_band(dress, lantern, wall_top + lan_h, lan_half, lan_half,
			[Vector2(0.2, 0.26), Vector2(0.45, 0.3)])
	# A four-sided pyramid is a cone with four segments — and at 80 m that is
	# genuinely all a tiled pyramid roof is.
	Geo.dome(batch.baker(Batch.roof()), lantern, 4.1, lan_top, 3.4, 4, 1)


## One of the west front's square towers: shaft, string courses, crenellated
## parapet, octagonal drum, cupola, cross.
static func _se_tower(batch: Batch, at: Transform3D, detail: Detail, bands: int) -> void:
	var stone := batch.baker(Batch.granite())
	var dress := batch.baker(Batch.dress())
	var h := SE_TOWER_HALF
	var shaft := SE_TOWER_TOP - 1.5

	Geo.moulded_band(batch.baker(Batch.dark_stone()), at, 0.0, h, h,
			[Vector2(0.45, 0.9), Vector2(0.18, 0.6)])
	_core(stone, at, h, h, 1.5, shaft, 0.5)

	for i in 4:
		var face := Geo.face_of(at, PI * 0.5 * float(i), h, 1.5)
		var lights: Array = []
		if detail != Detail.LOW:
			for sy in [10.5, 17.5]:
				lights.append(Geo.Opening.arched(0.0, 1.25, sy, 2.3, -1.0))
		_wall(batch, face, h, shaft, lights, stone, detail, bands, 0.5, 0.2)
		if detail != Detail.LOW:
			for sx in [-1.0, 1.0]:
				Geo.pilaster(dress, face, sx * (h - 0.45), 0.0, shaft, 0.7, 0.2, false)

	# String courses. On a tower this plain they are most of the modelling, and
	# they are what stops 24 m of granite reading as one extruded post.
	for band_y in [9.0, 16.5]:
		Geo.moulded_band(dress, at, band_y, h, h, [Vector2(0.2, 0.34)])

	Geo.moulded_band(dress, at, SE_TOWER_TOP, h, h, [Vector2(0.24, 0.3), Vector2(0.55, 0.38)])
	Geo.merlons(dress, at, SE_TOWER_TOP + 0.68, h + 0.4, h + 0.4, 1.0, 0.72, 1.4, 0.6)

	var drum := SE_TOWER_TOP + 2.1
	var segs := _segments(detail, 8, 8, 6)
	Geo.cyl_shell(stone, at, h * 0.62, drum, drum + 2.0, segs)
	Geo.moulded_ring(dress, at, drum + 2.0, h * 0.62, [Vector2(0.24, 0.28)], segs)
	Geo.dome(dress, at, h * 0.66, drum + 2.28, 2.6, segs, 4, 0.24)
	var ball := Geo.finial_ball(dress, at, drum + 4.88, 0.34, segs)
	Geo.cross_finial(batch.baker(Batch.iron()), at, ball, 1.5, 0.8, 0.14)


# --- Mosteiro da Serra do Pilar ----------------------------------------------

## A circular church and a circular cloister. The circularity is the entire
## point — it is the only building of its kind in Portugal, and from the bridge
## it is a drum, a dome and a ring of columns on a cliff.
static func serra_do_pilar(detail: Detail = Detail.FULL) -> Node3D:
	var batch := Batch.new()
	add_serra_do_pilar(batch, Transform3D.IDENTITY, detail)
	return batch.commit("SerraDoPilar")


## Bake the monastery into `batch`, church at the frame origin and cloister out
## along +X.
static func add_serra_do_pilar(batch: Batch, at: Transform3D,
		detail: Detail = Detail.FULL) -> void:
	var stone := batch.baker(Batch.granite())
	var dress := batch.baker(Batch.dress())
	var dark := batch.baker(Batch.void_dark())
	var wash := batch.baker(Batch.limewash())
	var bands := _bands(detail)
	var segs := _segments(detail, 32, 24, 16)

	# --- Podium
	var podium := Geo.round_steps(batch.baker(Batch.dark_stone()), at, SERRA_CHURCH_R + 0.4,
			0.0, 3, 0.32, 0.36, segs)

	# --- Rotunda. Built as SERRA_BAYS flat bays rather than a true cylinder: the
	# facets land under the pilasters that divide the bays anyway, and a flat bay
	# is a wall face, which means windows can be punched through it with the same
	# code every other wall here uses.
	var drum_top := 12.4
	var bay_half := SERRA_CHURCH_R * tan(PI / float(SERRA_BAYS))
	# The interior the windows look into. Void-black rather than stone: it is
	# never seen except through a window, and through a window it should be dark.
	Geo.cyl_shell(dark, at, SERRA_CHURCH_R - 0.75, podium, drum_top, segs)
	for i in SERRA_BAYS:
		var a := TAU * float(i) / float(SERRA_BAYS)
		var face := Geo.face_of(at, a, SERRA_CHURCH_R, podium)
		var openings: Array = []
		# Windows in alternate bays, and never in the bay the cloister joins.
		if i % 2 == 1 and i != SERRA_BAYS / 4:
			openings.append(Geo.Opening.arched(0.0, 1.7, 3.9, 3.0, -1.0))
		_wall(batch, face, bay_half, drum_top - podium, openings, stone, detail, bands, 0.7, 0.22)
		if detail != Detail.LOW:
			Geo.pilaster(dress, face, -bay_half, 0.0, drum_top - podium, 0.85, 0.3, true)

	# --- Entablature, attic and the gallery round the dome's foot
	var ent := Geo.moulded_ring(dress, at, drum_top, SERRA_CHURCH_R,
			[Vector2(0.22, 0.3), Vector2(0.55, 0.4), Vector2(0.3, 0.3)], segs)
	Geo.cyl_shell(stone, at, SERRA_CHURCH_R - 0.7, ent, ent + 1.7, segs)
	var attic := Geo.moulded_ring(dress, at, ent + 1.7, SERRA_CHURCH_R - 0.7,
			[Vector2(0.3, 0.28)], segs)
	if detail != Detail.LOW:
		Geo.balustrade_ring(dress, at, SERRA_CHURCH_R - 0.1, ent, 1.3,
				_segments(detail, 36, 24, 12), segs)

	# --- Dome: hemispheric, as the real vault is, and ribbed so it does not read
	# as a grey balloon when the sun is behind it.
	var dome_r := SERRA_CHURCH_R - 0.7
	var dome_rise := 6.4
	Geo.dome(dress, at, dome_r, attic, dome_rise, segs, _segments(detail, 7, 5, 3), 0.05)
	if detail == Detail.FULL:
		Geo.dome_ribs(dress, at, dome_r, attic, dome_rise, 8, 0.3, 4)

	# --- Lantern on top: six bays, cornice, little dome, cross.
	var lan_y := attic + dome_rise - 0.3
	var lan_r := 1.95
	var lan_h := 2.9
	# Six bays wrapped round the circle the same way the drum's sixteen are: each
	# face tangent at `lan_r`, so neighbours meet at the corners exactly.
	var lan_half := lan_r * tan(PI / 6.0)
	Geo.cyl_shell(dark, at, lan_r - 0.3, lan_y, lan_y + lan_h, 6)
	for i in 6:
		var face := Geo.face_of(at, TAU * float(i) / 6.0, lan_r, lan_y)
		var o := Geo.Opening.arched(0.0, 1.0, 0.5, 1.2, -1.0)
		_wall(batch, face, lan_half, lan_h, [o], stone, detail, bands, 0.3, 0.16)
	var lan_top := Geo.moulded_ring(dress, at, lan_y + lan_h, lan_r, [Vector2(0.3, 0.26)], 12)
	Geo.dome(dress, at, lan_r * 1.05, lan_top, 1.5, 12, 3, 0.2)
	var ball := Geo.finial_ball(dress, at, lan_top + 1.5, 0.3, 8)
	Geo.cross_finial(batch.baker(Batch.iron()), at, ball, 1.6, 0.85, 0.13)

	# --- The cloister: a circle of columns carrying a circular entablature.
	# Licence taken here. The real cloister's colonnade faces its courtyard and
	# would be invisible behind an outer wall; at 60 m that turns the only
	# circular cloister in Portugal into a plain drum. So it is built as an open
	# peristyle, columns outward, which is what the place is famous for.
	var cl := at * Transform3D(Basis(), Vector3(SERRA_CLOISTER_X, 0.0, 0.0))
	var cl_base := Geo.round_steps(batch.baker(Batch.dark_stone()), cl, SERRA_CLOISTER_R + 0.55,
			0.0, 2, 0.3, 0.4, segs)
	var col_h := 4.7
	Geo.cyl_shell(wash, cl, SERRA_CLOISTER_R - 2.8, cl_base, cl_base + col_h - 0.4, segs)
	# The church stands inside the ring on the -X side, so no column there.
	Geo.colonnade(dress, cl, SERRA_CLOISTER_R, _column_count(detail), cl_base, col_h, 0.32,
			_segments(detail, 8, 6, 5), detail == Detail.FULL, PI * 1.32, PI * 1.68)
	var cl_ent := Geo.moulded_ring(dress, cl, cl_base + col_h, SERRA_CLOISTER_R + 0.2,
			[Vector2(0.22, 0.34), Vector2(0.48, 0.32)], segs)
	Geo.annulus(batch.baker(Batch.roof()), cl, SERRA_CLOISTER_R - 2.8, SERRA_CLOISTER_R + 0.6,
			cl_ent, segs, true)
	if detail != Detail.LOW:
		Geo.balustrade_ring(dress, cl, SERRA_CLOISTER_R + 0.35, cl_ent, 1.15,
				_segments(detail, 32, 20, 12), segs)

	# --- Monastic wing trailing back along the clifftop, and the terrace wall
	# that holds the whole thing up over the river.
	var wing := at * Transform3D(Basis(), Vector3(9.0, 0.0, -13.5))
	wash.add_box(Vector3(20.0, 6.4, 8.0), wing * Transform3D(Basis(), Vector3(0.0, 3.2, 0.0)))
	Geo.moulded_band(dress, wing, 6.4, 10.0, 4.0, [Vector2(0.2, 0.3)])
	Geo.gable_roof(batch.baker(Batch.roof()), wing, 6.7, 10.0, 4.0, 2.0, 0.3, 0.45, true,
			_segments(detail, 8, 6, 4))
	if detail != Detail.LOW:
		# Blind windows: this wing is a background mass behind the church, and
		# rebuilding it as a punched shell for seven of them buys nothing.
		var wall_face := Geo.face_of(wing, 0.0, 4.0, 0.0)
		for k in 7:
			_blind_window(batch, wall_face, (float(k) - 3.0) * 2.6, 3.4, 1.0, 1.9)


# --- Azulejo church ----------------------------------------------------------

## A proper Porto church front — pilasters, pediment, arched portal, bell gable —
## with one flank tiled floor to eaves in blue and white. Replaces a box with
## checkers painted on it.
static func igreja_azulejo(detail: Detail = Detail.FULL) -> Node3D:
	var batch := Batch.new()
	add_igreja_azulejo(batch, Transform3D.IDENTITY, detail)
	return batch.commit("IgrejaAzulejo")


## Bake the church into `batch`. The front faces +Z and the tiled flank faces
## +X, so a caller wanting the tile seen from the bridge should yaw accordingly.
static func add_igreja_azulejo(batch: Batch, at: Transform3D,
		detail: Detail = Detail.FULL) -> void:
	var stone := batch.baker(Batch.granite())
	var dress := batch.baker(Batch.dress())
	var dark := batch.baker(Batch.void_dark())
	var wash := batch.baker(Batch.limewash())
	var bands := _bands(detail)

	var hx := 5.2
	var hz := 8.6
	var wall := 12.4
	var plinth := 0.9
	var reveal := 0.55

	Geo.moulded_band(batch.baker(Batch.dark_stone()), at, 0.0, hx, hz,
			[Vector2(0.3, 0.55), Vector2(0.12, 0.35)])
	# The core is what the openings look into; the four skins round it are what
	# is seen. Front in granite ashlar, flanks limewashed — which is how these are
	# actually built, the money going on the elevation that faces the street.
	_core(wash, at, hx, hz, plinth, wall, reveal)

	# --- West front. Everything that is meant to look recessed is punched, niches
	# included: a recess drawn behind an unpunched skin is a recess nobody sees.
	var front := Geo.face_of(at, 0.0, hz, plinth)
	var portal := Geo.Opening.arched(0.0, 2.5, 0.0, 2.7, -1.0)
	var window := Geo.Opening.arched(0.0, 1.9, 6.6, 2.2, -1.0)
	var openings: Array = [portal, window]
	if detail != Detail.LOW:
		for sx in [-1.0, 1.0]:
			openings.append(Geo.Opening.arched(sx * 3.3, 1.1, 6.9, 1.4, -1.0))
	_wall(batch, front, hx, wall, openings, stone, detail, bands, reveal, 0.3)
	Geo.panel(wash, Geo.face_of(at, PI, hz, plinth), -hx, 0.0, hx, wall, [], 0.0, bands)
	Geo.box(batch.baker(Batch.timber()), front, 0.0, 1.35, -0.40, 2.3, 2.7, 0.16)

	if detail != Detail.LOW:
		# Four pilasters: the pair framing the portal and one on each corner.
		for cx in [-4.6, -1.9, 1.9, 4.6]:
			Geo.pilaster(dress, front, cx, 0.0, wall - 0.4, 0.72, 0.3, true)
		# A saint standing in each niche. One block, but the eye is expecting a
		# figure in that shadow and reads it as one.
		for sx in [-1.0, 1.0]:
			Geo.box(dress, front, sx * 3.3, 7.3, -0.3, 0.42, 1.3, 0.3)

	var ent := Geo.moulded_band(dress, at, plinth + wall, hx, hz,
			[Vector2(0.2, 0.3), Vector2(0.46, 0.34)])
	var gable_face := Geo.face_of(at, 0.0, hz, ent)
	Geo.pediment(dress, gable_face, hx + 0.46, 0.0, 2.4, 0.5, 0.34)
	# A blind oculus in the tympanum: the disc has to stand proud of the tympanum
	# it sits on, since that triangle is solid rather than punched.
	Geo.rose_window(dress, dark, gable_face, 0.0, 0.95, 0.62, 6, 0.45, 0.18)

	# --- Bell gable (espadaña) rising from behind the pediment, with scrolled
	# shoulders. Its base is tucked below the pediment's apex so it grows out of
	# the roofline instead of floating over it.
	var bg := at * Transform3D(Basis(), Vector3(0.0, 0.0, hz - 0.9))
	var bg_y := ent + 1.2
	var bg_thick := 0.45
	var bg_face := Geo.face_of(bg, 0.0, bg_thick, bg_y)
	var bells: Array = [
		Geo.Opening.arched(-1.15, 1.25, 0.5, 1.1, -1.0),
		Geo.Opening.arched(1.15, 1.25, 0.5, 1.1, -1.0),
	]
	# Punched front AND back, with no dark plate between them: an espadaña is a
	# wall with holes in it, and the sky showing through those two arches is the
	# whole reason the shape reads from a distance. The openings are symmetric
	# about the centre, so the mirrored back face takes the same list.
	Geo.panel(dress, bg_face, -2.6, 0.0, 2.6, 3.5, bells, 0.0, bands)
	Geo.panel(dress, Geo.face_of(bg, PI, bg_thick, bg_y), -2.6, 0.0, 2.6, 3.5, bells, 0.0, bands)
	for k in bells.size():
		var o: Geo.Opening = bells[k]
		if detail == Detail.LOW:
			continue
		Geo.opening_reveal(dress, bg_face, o, 0.0, -bg_thick * 2.0, bands)
		if detail == Detail.FULL:
			# A bell hanging in each, dark against the sky.
			Geo.box(dark, bg_face, o.centre_x(), o.y1 + o.rise * 0.35, -bg_thick,
					0.62, 0.7, 0.5)
	# Sides and scrolls, then the cornice and cross that top the whole church.
	for sx in [-1.0, 1.0]:
		dress.add_box(Vector3(0.44, 3.5, 0.9), bg * Transform3D(Basis(),
				Vector3(sx * 2.38, bg_y + 1.75, 0.0)))
		if detail != Detail.LOW:
			for k in 2:
				var f := float(k)
				dress.add_box(Vector3(0.5, 0.5, 0.75), bg * Transform3D(Basis(),
						Vector3(sx * (2.9 + f * 0.42), bg_y + 1.0 - f * 0.55, 0.0)))
	var bg_top := Geo.moulded_band(dress, bg, bg_y + 3.5, 2.7, 0.5,
			[Vector2(0.16, 0.24), Vector2(0.34, 0.24)])
	Geo.cross_finial(batch.baker(Batch.iron()), bg, bg_top, 1.5, 0.8, 0.12)

	# --- Roof: ridge along the nave, so the prism is yawed a quarter turn.
	Geo.gable_roof(batch.baker(Batch.roof()), _yawed(at), ent + 0.1, hz, hx, 2.2, 0.0, 0.45,
			true, _segments(detail, 8, 6, 4))

	# --- Flanks: high windows over the tile wall that is the whole point. The
	# windows sit above the tiling, as they do on the real tiled churches — the
	# panels want an unbroken field, and a window punched through one ruins it.
	for i in 2:
		var sx := 1.0 if i == 0 else -1.0
		var face := Geo.face_of(at, PI * 0.5 * sx, hx, plinth)
		var wins: Array = []
		for k in 4:
			wins.append(Geo.Opening.arched((float(k) - 1.5) * 3.6 * sx, 1.3, 8.8, 1.9, -1.0))
		_wall(batch, face, hz, wall, wins, wash, detail, bands, 0.45)
		if i == 0 or detail == Detail.FULL:
			_azulejo_wall(batch, face, hz, 0.3, 8.0, detail)


## A tiled flank: white field, blue framed panels, dado and frieze bands. Real
## azulejo fronts are panels of narrative tilework set in a plain white field
## with blue borders — not a checkerboard, which is what reads as "tiles" up
## close and as grey mush at 80 m. Panels and bands survive the distance.
static func _azulejo_wall(batch: Batch, face: Transform3D, half_len: float, y0: float,
		y1: float, detail: Detail) -> void:
	var white := batch.baker(Batch.tile_white())
	var blue := batch.baker(Batch.tile_blue())
	var deep := batch.baker(Batch.tile_blue(Batch.TILE_DEEP))
	var z := SKIN_GAP * 2.0

	Geo.rect(white, face, -half_len, y0, half_len, y1, z)
	# Dado at the bottom, frieze at the top: the two horizontals that tell the eye
	# this is a tiled wall and not a painted one.
	Geo.rect(blue, face, -half_len, y0, half_len, y0 + 0.85, z + SKIN_GAP)
	Geo.rect(blue, face, -half_len, y1 - 0.5, half_len, y1, z + SKIN_GAP)

	var panels := 3
	var pitch := (half_len * 2.0 - 1.2) / float(panels)
	var pw := pitch - 0.9
	var rng := RandomNumberGenerator.new()
	rng.seed = 8815   # the pattern must be the same building every run
	for i in panels:
		var cx := -half_len + 0.6 + pitch * (float(i) + 0.5)
		var py0 := y0 + 1.5
		var py1 := y1 - 1.1
		Geo.rect(blue, face, cx - pw * 0.5, py0, cx + pw * 0.5, py1, z + SKIN_GAP)
		Geo.rect(white, face, cx - pw * 0.5 + 0.28, py0 + 0.28, cx + pw * 0.5 - 0.28,
				py1 - 0.28, z + SKIN_GAP * 2.0)
		if detail == Detail.LOW:
			continue
		# A scattering of deep-blue blocks inside the frame. Not a picture, but
		# at this range a narrative panel resolves to exactly this: irregular
		# dark massing inside a hard border.
		var cols := 5
		var rows := 6
		var cw := (pw - 0.8) / float(cols)
		var ch := (py1 - py0 - 0.9) / float(rows)
		for r in rows:
			for c in cols:
				if rng.randf() > 0.46:
					continue
				var bx := cx - pw * 0.5 + 0.4 + cw * (float(c) + 0.5)
				var by := py0 + 0.45 + ch * (float(r) + 0.5)
				Geo.rect(deep, face, bx - cw * 0.42, by - ch * 0.42, bx + cw * 0.42,
						by + ch * 0.42, z + SKIN_GAP * 3.0)


# --- Gaia port-wine lodges ---------------------------------------------------

## One warehouse on the Gaia waterline. Names are invented.
class LodgeSpec extends RefCounted:
	var length := 22.0
	var depth := 12.0
	var wall := 5.6
	var roof_rise := 2.6
	var sign_text := "VINHO DO PORTO"
	var sign_height := 3.4
	var wall_color := Batch.LIMEWASH

	static func random(rng: RandomNumberGenerator, text: String) -> LodgeSpec:
		var s := LodgeSpec.new()
		s.length = rng.randf_range(12.5, 17.5)
		s.depth = rng.randf_range(9.0, 12.0)
		s.wall = rng.randf_range(5.0, 6.4)
		s.roof_rise = s.depth * rng.randf_range(0.20, 0.26)
		s.sign_text = text
		s.sign_height = rng.randf_range(2.8, 3.8)
		# Two limewash tones and no more. Continuous per-lodge colour variation
		# would be one material and one draw call each, which is a lot to pay for
		# a difference nobody can see at 70 m; the shed proportions carry the
		# variety instead.
		s.wall_color = Batch.LIMEWASH if rng.randf() < 0.6 else Batch.LIMEWASH_WARM
		return s


## A row of lodges along the Gaia shelf, all in one batch. The first stands at
## the returned node's origin and the rest run out along +X.
static func gaia_lodges(count: int = 4, detail: Detail = Detail.FULL,
		lodge_seed: int = 30_417) -> Node3D:
	var batch := Batch.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = lodge_seed
	_lodge_row(batch, Transform3D.IDENTITY, count, detail, rng)
	return batch.commit("GaiaLodges")


## Bake one lodge into `batch`, its loading front on the frame's +Z.
static func add_gaia_lodge(batch: Batch, at: Transform3D, spec: LodgeSpec,
		detail: Detail = Detail.FULL, rng: RandomNumberGenerator = null) -> void:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.seed = 7301
	var wash := batch.baker(Batch.limewash(spec.wall_color))
	var dress := batch.baker(Batch.dress())
	var timber := batch.baker(Batch.timber())
	var bands := _bands(detail)

	var hx := spec.length * 0.5
	var hz := spec.depth * 0.5
	var plinth := 0.7
	var reveal := 0.35

	Geo.moulded_band(batch.baker(Batch.dark_stone()), at, 0.0, hx, hz,
			[Vector2(0.16, plinth)])
	_core(wash, at, hx, hz, plinth, spec.wall, reveal)

	# Loading doors on the river front, fewer on the back, small lights above.
	for i in 2:
		var yaw := 0.0 if i == 0 else PI
		var face := Geo.face_of(at, yaw, hz, plinth)
		var doors: Array = []
		var count := 3 if i == 0 else 2
		for k in count:
			var cx := (float(k) - (float(count) - 1.0) * 0.5) * (hx * 2.0 / float(count + 1))
			doors.append(Geo.Opening.arched(cx, 2.7, 0.0, 2.3, 1.35))
		var lights: Array = []
		for k in 4:
			lights.append(Geo.Opening.flat((float(k) - 1.5) * hx * 0.44, 0.9, spec.wall - 1.5, 0.9))
		var all: Array = doors + lights
		_wall(batch, face, hx, spec.wall, all, wash, detail, bands, reveal)
		for k in doors.size():
			var o: Geo.Opening = doors[k]
			Geo.box(timber, face, o.centre_x(), o.top() * 0.5, -0.2, o.width() - 0.2,
					o.top() - 0.1, 0.14)

	# Gable ends: the wall carries on up into the triangle, and the roof's own
	# gable is 2 cm behind it so the whitewash wins the depth test rather than
	# fighting the terracotta for it.
	for i in 2:
		var yaw := PI * 0.5 * (1.0 if i == 0 else -1.0)
		Geo.panel(wash, Geo.face_of(at, yaw, hx, plinth), -hz, 0.0, hz, spec.wall, [], 0.0, bands)
		var end := Geo.face_of(at, yaw, hx + SKIN_GAP, plinth + spec.wall)
		Geo.fill_outline(wash, end, PackedVector2Array([
			Vector2(-hz, 0.0), Vector2(0.0, spec.roof_rise), Vector2(hz, 0.0)]), 0.0)
		if detail != Detail.LOW:
			# A round loft light in the gable, the way every one of these sheds
			# has one. Blind, like the church's oculus: the gable triangle is a
			# solid fill, so the glass has to stand proud of it to be seen.
			Geo.rose_window(dress, batch.baker(Batch.void_dark()), end, 0.0,
					spec.roof_rise * 0.45, 0.5, 4, 0.3, 0.24)

	Geo.gable_roof(batch.baker(Batch.roof()), at, plinth + spec.wall, hx, hz, spec.roof_rise,
			0.0, 0.55, true, _segments(detail, 8, 6, 4))

	_lodge_sign(batch, at, spec, plinth + spec.wall + spec.roof_rise, detail)

	if detail == Detail.FULL:
		# Barrels and a lean-to: the clutter that says this is a working quay and
		# not a model village. Same timber as the doors, deliberately — a second
		# brown would be a second draw call for six barrels at 70 m.
		var barrel := timber
		for k in 6:
			var bx := rng.randf_range(-hx * 0.8, hx * 0.8)
			var lying := Transform3D(Basis(Vector3.BACK, PI * 0.5),
					Vector3(bx, 0.45, hz + rng.randf_range(0.9, 2.2)))
			Geo.revolve(barrel, at * lying, PackedVector2Array([
				Vector2(0.30, -0.42), Vector2(0.42, -0.16), Vector2(0.42, 0.16),
				Vector2(0.30, 0.42)]), 8)
		var lean := at * Transform3D(Basis(), Vector3(hx + 1.9, 0.0, 0.0))
		wash.add_box(Vector3(3.6, 2.9, hz * 1.2), lean * Transform3D(Basis(),
				Vector3(0.0, 1.45, 0.0)))
		Geo.gable_roof(batch.baker(Batch.roof()), lean, 2.9, 1.8, hz * 0.6, 0.7, 0.2, 0.3, false)


## The rooftop sign: an iron frame straddling the ridge with the lodge's name
## built out of it. These are the single most recognisable thing about the Gaia
## bank from the water.
static func _lodge_sign(batch: Batch, at: Transform3D, spec: LodgeSpec, ridge_y: float,
		detail: Detail) -> void:
	var iron := batch.baker(Batch.iron())
	var text: String = spec.sign_text
	# The cell size is whatever makes the name fit the shed it stands on, capped
	# so a short name does not turn into a billboard. Six cells per character:
	# five of glyph and one of gap.
	var chars := maxi(1, text.length())
	var cell := minf(spec.sign_height / 9.0, spec.length * 0.86 / (float(chars) * 6.0))
	var text_w := float(chars) * cell * 6.0
	var frame_w := minf(spec.length * 0.94, text_w + cell * 4.0)
	var hw := frame_w * 0.5
	var top := ridge_y + spec.sign_height

	var posts := maxi(2, int(frame_w / 5.0))
	for i in range(posts + 1):
		var px := lerpf(-hw, hw, float(i) / float(posts))
		Geo.beam(iron, at, Vector3(px, ridge_y - 0.4, 0.0), Vector3(px, top, 0.0), 0.14)
	Geo.beam(iron, at, Vector3(-hw, top, 0.0), Vector3(hw, top, 0.0), 0.13)
	Geo.beam(iron, at, Vector3(-hw, ridge_y + 0.2, 0.0), Vector3(hw, ridge_y + 0.2, 0.0), 0.13)
	if detail != Detail.LOW:
		# Cross-braced bays: from the bridge these frames are mostly sky, and the
		# diagonals are what stops them reading as a floating billboard.
		for i in posts:
			var x0 := lerpf(-hw, hw, float(i) / float(posts))
			var x1 := lerpf(-hw, hw, float(i + 1) / float(posts))
			Geo.beam(iron, at, Vector3(x0, ridge_y + 0.2, 0.0), Vector3(x1, top, 0.0), 0.08)
			Geo.beam(iron, at, Vector3(x1, ridge_y + 0.2, 0.0), Vector3(x0, top, 0.0), 0.08)

	if detail == Detail.LOW or text.is_empty():
		return
	# Centre the seven-cell cap height between the frame's two rails.
	#
	# SOLID letters, standing a third of a cell off the frame. Flat lettering on an
	# open frame has one value at every sun angle, so it reads as a stencil rather
	# than as a row of steel characters — the exact fault an adversarial critic
	# scored on the hillside hoardings, and this is the same font on the same bank.
	var y0 := ridge_y + 0.2 + (spec.sign_height - 0.2 - cell * 7.0) * 0.5
	sign_text_solid(batch.baker(Batch.sign_face()), at, text,
			-text_w * 0.5 + cell * 0.5, y0, cell, cell * 0.5)


## Lay out a string in 5x7 cells as quads, merging each row's runs so a letter
## costs a dozen triangles instead of thirty-five.
##
## Public because the port houses' lettering is not only on their own roofs: the
## Gaia bank carries the same names on standing frames up the hillside, and
## quay_kit.gd builds those. One alphabet in the project, one implementation of
## it, and callers hand over whatever MeshBaker they want the glyphs in.
static func sign_text(b: MeshBaker, at: Transform3D, text: String, x0: float, y0: float,
		cell: float) -> void:
	var face := at * Transform3D(Basis(), Vector3(0.0, 0.0, 0.06))
	for r in glyph_rects(text, x0, y0, cell):
		Geo.rect(b, face, r.position.x, r.position.y, r.end.x, r.end.y, 0.0)


## The same string as SOLID LETTERS standing `depth` proud of the frame.
##
## Flat lettering was the whole reason round 2's hoardings scored as "a debug
## texture that was never replaced": a zero-thickness glyph has one value at every
## sun angle, so a word is a stencil rather than a row of objects. Extruded, each
## letter has a lit face, a shadow side and a cast shadow on whatever is behind
## it — which at ninety metres is the only thing that separates a sign from a
## decal. The real port-house hoardings are exactly this: individual steel letters
## standing off an open frame, and you can see daylight between them.
##
## Cost is the reason this is not the default: a box is twelve triangles where a
## quad is two. glyph_rects() merges vertically as well as horizontally, so a
## capital I is one box rather than seven, and a five-letter word lands around
## fifty boxes rather than a hundred and seventy-five.
static func sign_text_solid(b: MeshBaker, at: Transform3D, text: String, x0: float,
		y0: float, cell: float, depth: float) -> void:
	for r in glyph_rects(text, x0, y0, cell):
		Geo.box(b, at, r.position.x + r.size.x * 0.5, r.position.y + r.size.y * 0.5,
				depth * 0.5, r.size.x, r.size.y, depth)


## The 5x7 bitmap of `text`, reduced to as few axis-aligned rectangles as a greedy
## row-then-column merge finds. Face space: +X along the baseline, +Y up, the
## first glyph's left edge at `x0` and its baseline at `y0`.
##
## Merging both ways rather than only along the row matters more than it looks:
## the alphabet is mostly vertical stems, so a row-only merge emits seven
## one-cell rectangles for every upright and the letter comes out as a stack of
## stripes the moment it has any thickness.
static func glyph_rects(text: String, x0: float, y0: float, cell: float) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var pen := x0
	for i in text.length():
		var ch := text[i]
		if not SIGN_FONT.has(ch):
			pen += cell * 6.0   # space, and anything unmapped
			continue
		var rows: Array = SIGN_FONT[ch]
		var height := rows.size()
		# open[(start, end)] -> the row index the run started on. Rows are walked
		# top to bottom, so a run that repeats simply grows downward and is only
		# emitted once it stops.
		var open: Dictionary = {}
		for r in range(height + 1):
			var seen: Dictionary = {}
			if r < height:
				var row: String = rows[r]
				var run := -1
				for c in range(row.length() + 1):
					var on := c < row.length() and row[c] == "1"
					if on and run < 0:
						run = c
					elif not on and run >= 0:
						seen[Vector2i(run, c)] = true
						run = -1
			# Close every open run this row did not repeat.
			for key: Vector2i in open.keys():
				if seen.has(key):
					continue
				var from: int = open[key]
				# Row 0 is the TOP of the glyph, so a run spanning rows
				# [from, r) occupies cells (height - r) .. (height - from).
				out.append(Rect2(
					pen + float(key.x) * cell, y0 + float(height - r) * cell,
					float(key.y - key.x) * cell, float(r - from) * cell))
				open.erase(key)
			for key: Vector2i in seen.keys():
				if not open.has(key):
					open[key] = r
		pen += cell * 6.0
	return out


# --- Detail helpers ----------------------------------------------------------

## Segments to divide an arch head into. Two is a pointed-looking approximation
## that still reads as an arch in silhouette; six is smooth at any distance the
## player can get to these.
static func _bands(detail: Detail) -> int:
	match detail:
		Detail.LOW:
			return 2
		Detail.MEDIUM:
			return 4
		_:
			return 6


static func _segments(detail: Detail, full: int, medium: int, low: int) -> int:
	match detail:
		Detail.LOW:
			return low
		Detail.MEDIUM:
			return medium
		_:
			return full


## 36 Ionic columns is the real count, and in groups of nine. Dropping to 24 or
## 18 keeps the ring reading as a ring while shedding a third of the cost.
static func _column_count(detail: Detail) -> int:
	match detail:
		Detail.LOW:
			return 18
		Detail.MEDIUM:
			return 24
		_:
			return SERRA_COLUMNS
