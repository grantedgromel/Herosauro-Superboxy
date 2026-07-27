extends Node3D
## SkyBackground: the warm Porto golden-hour backdrop.
##
## The WorldEnvironment + sunset Sky live in the .tscn; this script procedurally
## builds a recognizably-Porto skyline: hillside banks dropping to a granite
## waterline quay, tight terraces of narrow, colourful Ribeira houses with pitched
## terracotta roofs stacked down both slopes, Gaia's port-wine lodges with their
## rooftop lettering, rabelo boats bobbing on the Douro, an azulejo-fronted chapel,
## and the two landmarks — the round Serra do Pilar dome and the slim Clérigos
## tower — plus drifting toon clouds and circling gulls. Decorative, no collision.
##
## The facades used to be flat coloured boxes with a glowing rectangle stuck on
## the front, which under a raking 11.5-degree sun read as painted card. They now
## carry the things that actually catch that light: a granite ground course, a
## projecting eaves band, proud window surrounds over recessed panes, sills,
## doors, the odd balcony, and chimneys breaking the roofline. All of it is
## affordable because every repeated fitting goes into one MultiMesh per terrace
## (see SceneryKit.repeat) — a row of thirteen houses costs four draw calls per
## house plus eight for the whole row, however many windows it ends up with.

const CLOUD_SPEED := 1.4          # world units / second of drift along +X
const CLOUD_WRAP_MIN := -120.0    # x where a cloud re-appears after wrapping
const CLOUD_WRAP_MAX := 120.0     # x past which a cloud wraps back

# --- Far-city extents --------------------------------------------------------
#
# RECONCILIATION CONTRACT. A photogrammetry scan of the real district is going in
# behind this procedural skyline. Everything about where the skyline stands is in
# the five constants below and nowhere else — the hillside masses under the
# houses, the Gaia lodges and the Clérigos tower all derive their X from
# CITY_BANK_X, and each terrace row carries its own hill in the same table. So
# making room for the scan is: pull CITY_BANK_X in, move a row's `z`, or set
# CITY_CULL_Z to the scan's front edge. Not surgery.
#
# Where the two overlap, the procedural city is the one that should give way: it
# exists to fill the gap between the bridge ends and the horizon, and the scan is
# the real thing.

## Distance from the bridge centreline out to each bank's line of house fronts.
const CITY_BANK_X := 60.0

## Terrace rows, front to back.
##   z / dx     where the row stands (dx pushes it further out from CITY_BANK_X)
##   count      houses in the row
##   lift       the hillside tier it stands on
##   low / high facade height range
##   detail     2 = close enough to read as buildings (full trim, doors,
##              balconies); 1 = silhouette and windows only
##   hill*      the bank mass under the row, so pulling the row in drags the
##              hillside with it. hill_dz is measured back from the row.
const CITY_TERRACES := [
	{
		"z": -21.0, "dx": 0.0, "count": 13, "lift": 0.0,
		"low": 8.0, "high": 19.0, "detail": 2,
		"hill": Vector3(60.0, 10.0, 26.0), "hill_dx": 6.0, "hill_dz": -5.0,
	},
	{
		"z": -31.0, "dx": 6.0, "count": 10, "lift": 7.0,
		"low": 7.0, "high": 16.0, "detail": 1,
		"hill": Vector3(50.0, 8.0, 22.0), "hill_dx": 12.0, "hill_dz": -7.0,
	},
]

## The Porto-side waterline row: low houses standing right on the cais, so the
## Ribeira cascade runs all the way down to the river. Porto bank only — Gaia's
## waterline is the lodges.
const CITY_QUAY_ROW := {
	"z": -10.0, "dx": 4.0, "count": 8, "lift": -10.1,
	"low": 5.0, "high": 8.0, "detail": 2,
}

## Terrace rows further back than this are skipped, hillside and all. Set it to
## the front edge of the photogrammetry backdrop and the procedural city stops
## exactly where the real scan takes over.
const CITY_CULL_Z := -1000.0

## Waterline shelf / cais / quay wall, and the lodges standing on the Gaia one.
const BANK_SHELF_DX := 18.0

# --- Ribeira palette ---------------------------------------------------------
# Pitched a good 10-15% darker than a photograph of these houses would suggest.
# The key light is 2.4 energy of Color(1, 0.78, 0.54) and AgX has a 12.0 white
# point: at the old values the ochres, creams and roses all converged on the same
# hot cream and the terrace lost its stripe. Chroma went up as the values came
# down, so the hue survives the exposure instead of being bleached out of it.

const RIBEIRA_WALLS := [
	Color(0.80, 0.60, 0.22),  # ochre yellow
	Color(0.70, 0.30, 0.24),  # terracotta red
	Color(0.80, 0.74, 0.60),  # cream
	Color(0.42, 0.58, 0.74),  # azulejo blue — the cool anchor the row needs
	Color(0.70, 0.47, 0.20),  # mustard
	Color(0.56, 0.64, 0.50),  # faded green
	Color(0.76, 0.66, 0.58),  # rose-beige
	Color(0.55, 0.25, 0.21),  # red oxide
]
## Two tile ages rather than one, so a whole hillside of roofs is not one colour.
const ROOF_COLORS := [Color(0.56, 0.28, 0.22), Color(0.48, 0.26, 0.21)]
const TRIM_STONE := Color(0.66, 0.63, 0.57)     # granite surrounds, sills, eaves
const PANE_DARK := Color(0.085, 0.095, 0.115)   # unlit glass reflecting the sky
const PANE_LIT := Color(1.00, 0.80, 0.44)
const DOOR_WOOD := Color(0.24, 0.16, 0.11)
const BALCONY_IRON := Color(0.15, 0.16, 0.18)
const CHIMNEY_BRICK := Color(0.52, 0.40, 0.33)

# --- Facade fittings ---------------------------------------------------------
# One size each, deliberately: identical fittings are what lets a whole terrace
# collapse into a handful of MultiMeshes, and real Portuguese sash windows do
# come in standard sizes.

const GROUND_FLOOR := 2.4       # height of the shop/entrance storey
const FLOOR_HEIGHT := 3.2
const MAX_FLOORS := 5
const WINDOW_SIZE := Vector3(0.86, 1.34, 0.12)   # proud stone surround
const PANE_SIZE := Vector3(0.62, 1.06, 0.06)     # set back inside it, so the
                                                 # surround's lip shades the glass
const SILL_SIZE := Vector3(1.10, 0.10, 0.26)
const DOOR_SIZE := Vector3(0.95, 2.10, 0.16)
const BALCONY_SLAB := Vector3(1.55, 0.10, 0.60)
const BALCONY_RAIL := Vector3(1.55, 0.55, 0.06)
const CHIMNEY_SIZE := Vector3(0.46, 1.90, 0.46)
const LIT_WINDOW_CHANCE := 0.22  # golden hour, not night: most glass is still dark
const BALCONY_CHANCE := 0.35

# Moored rabelo positions on the river (y is driven by the wave bob) and yaws.
const RABELO_SPOTS := [Vector3(-28.0, 0.0, -16.0), Vector3(8.0, 0.0, -24.0), Vector3(34.0, 0.0, -13.0)]
const RABELO_YAWS := [-0.35, 0.25, 0.6]

const GULL_COUNT := 5

var _clouds: Array[Node3D] = []
var _rabelos: Array[Node3D] = []
var _gulls: Array[Node3D] = []
var _gull_data: Array[Dictionary] = []


func _ready() -> void:
	_build_banks()
	_build_city()
	_build_gaia_lodges()
	_build_rabelos()
	_build_landmarks()
	_build_azulejo_chapel()
	_build_clouds()
	_build_gulls()


func _process(delta: float) -> void:
	# Drift the clouds and wrap them around so the sky never empties out.
	for cloud in _clouds:
		cloud.position.x += CLOUD_SPEED * delta
		if cloud.position.x > CLOUD_WRAP_MAX:
			cloud.position.x = CLOUD_WRAP_MIN

	# Ticks approximate the water shader's TIME, so hulls ride the same waves
	# the river surface is showing.
	var t := float(Time.get_ticks_msec()) / 1000.0
	for i in _rabelos.size():
		var boat := _rabelos[i]
		var wave := sin((boat.position.x + t * 0.5) * 0.18) + cos((boat.position.z + t * 0.4) * 0.234)
		boat.position.y = -14.75 + wave * 0.35
		boat.rotation.z = sin(t * 0.6 + float(i) * 2.1) * 0.04

	# Gulls circle their roosts, banking around the loop, wings beating.
	for i in _gulls.size():
		var gull := _gulls[i]
		var d := _gull_data[i]
		var ang: float = t * d.speed + d.phase
		var c: Vector3 = d.center
		gull.position = Vector3(
			c.x + cos(ang) * d.radius,
			c.y + sin(t * 1.7 + d.phase) * 0.8,
			c.z + sin(ang) * d.radius * 0.55
		)
		var vx: float = -sin(ang) * d.radius * d.speed
		var vz: float = cos(ang) * d.radius * 0.55 * d.speed
		gull.rotation.y = atan2(-vx, -vz)
		var flap: float = 0.35 + 0.45 * sin(t * 7.0 + d.phase * 3.0)
		(gull.get_child(0) as Node3D).rotation.z = -flap
		(gull.get_child(1) as Node3D).rotation.z = flap


# --- Riverbanks & quays ------------------------------------------------------

## Solid hillside masses under both skylines, so the terraces climb real slopes
## down to a cobbled promenade and a granite quay wall at the waterline, plus the
## rocky spur that carries Serra do Pilar above the Gaia bridge end. Pure
## background boxes — nothing enters the play volume.
func _build_banks() -> void:
	var banks := Node3D.new()
	banks.name = "Banks"
	add_child(banks)

	# Very big tiles: these boxes are 50-60 m across, and a tight tile on one is
	# high-frequency noise at 80 m, which aliases into shimmer and nothing else.
	# Earth and rock, not render — the hillside is not a plastered wall.
	var hillside := ToonFactory.stone(Color(0.44, 0.39, 0.33), 7.0)
	var granite := ToonFactory.stone(Color(0.55, 0.52, 0.48), 3.5)
	var cobble := ToonFactory.cobblestone(Color(0.62, 0.59, 0.54), 1.8)

	var shelf_x := CITY_BANK_X + BANK_SHELF_DX
	for sx in [-1.0, 1.0]:
		# Waterline shelf the quay row and lodges sit on (top y = -10).
		_bank_box(banks, Vector3(56.0, 5.0, 44.0), Vector3(sx * shelf_x, -12.5, -14.0), hillside)
		# Cais promenade running from the house fronts to the water's edge,
		# finished with the granite quay wall dropping to the river.
		_bank_box(banks, Vector3(56.0, 0.6, 16.0), Vector3(sx * shelf_x, -9.9, 0.0), cobble)
		_bank_box(banks, Vector3(56.0, 2.2, 1.0), Vector3(sx * shelf_x, -11.0, 8.4), granite)

		# Hillside tier per terrace row, positioned off that row's own entry, so a
		# row pulled in for the backdrop takes its slope with it.
		for entry in CITY_TERRACES:
			var row: Dictionary = entry
			if float(row["z"]) < CITY_CULL_Z:
				continue
			var hill: Vector3 = row["hill"]
			var lift := float(row["lift"])
			_bank_box(banks, hill, Vector3(
					sx * (CITY_BANK_X + float(row["hill_dx"])),
					lift + 0.1 - hill.y * 0.5,          # top just under the house floors
					float(row["z"]) + float(row["hill_dz"])), hillside)

	# Serra do Pilar's cliff: one stout rock mass whose top (y = 9) meets the dome.
	_bank_box(banks, Vector3(18.0, 24.0, 18.0), Vector3(51.0, -3.0, -30.0),
			ToonFactory.stone(Color(0.44, 0.38, 0.32), 5.0))


func _bank_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	SceneryKit.box(parent, "Bank", size, pos, mat)


# --- Ribeira terraces --------------------------------------------------------

func _build_city() -> void:
	var city := Node3D.new()
	city.name = "City"
	add_child(city)

	for entry in CITY_TERRACES:
		var row: Dictionary = entry
		if float(row["z"]) < CITY_CULL_Z:
			continue
		for bank in [-1.0, 1.0]:
			_build_terrace(city, bank * (CITY_BANK_X + float(row["dx"])), row)

	if float(CITY_QUAY_ROW["z"]) >= CITY_CULL_Z:
		_build_terrace(city, -(CITY_BANK_X + float(CITY_QUAY_ROW["dx"])), CITY_QUAY_ROW)


## A row of narrow houses packed shoulder-to-shoulder along X, laid out from one
## CITY_TERRACES entry. Every house gets its own wall, ground course, eaves and
## roof; every repeated fitting — window surround, pane, sill, door, balcony,
## chimney — is collected and emitted as one MultiMesh for the whole row.
func _build_terrace(parent: Node3D, center_x: float, row: Dictionary) -> void:
	var count := int(row["count"])
	var lift := float(row["lift"])
	var base_z := float(row["z"])
	var rich := int(row["detail"]) >= 2
	var h_min := float(row["low"])
	var h_max := float(row["high"])

	var terrace := Node3D.new()
	terrace.name = "Terrace"
	parent.add_child(terrace)

	var rng := RandomNumberGenerator.new()
	# Signed center_x, unlike the old abs(): with the magnitude alone the Porto
	# and Gaia banks drew the identical terrace and the river read as a mirror.
	rng.seed = int(center_x * 31.0 + base_z * 7.0 + lift * 13.0)

	var trim := ToonFactory.stone(TRIM_STONE, 0.9)
	var pitch := 3.4   # spacing between adjacent facades (width + a sliver of gap)
	var start_x := center_x - float(count - 1) * pitch * 0.5

	var frames: Array[Vector3] = []
	var panes: Array[Vector3] = []
	var lit_panes: Array[Vector3] = []
	var sills: Array[Vector3] = []
	var doors: Array[Vector3] = []
	var balconies: Array[Vector3] = []
	var balcony_rails: Array[Vector3] = []
	var chimneys: Array[Vector3] = []

	for i in count:
		var w := rng.randf_range(2.6, 3.4)
		var d := rng.randf_range(3.0, 4.5)
		var h := rng.randf_range(h_min, h_max)
		var px := start_x + float(i) * pitch + rng.randf_range(-0.3, 0.3)
		var pz := base_z + rng.randf_range(-1.5, 1.5)
		var face := pz + d * 0.5          # the +z facade, the one the bridge sees

		# Wall: a tall narrow terraced facade. Eight palette colours across fifty
		# facades, and the factory caches by colour, so the whole city batches onto
		# eight materials.
		SceneryKit.box(terrace, "Wall", Vector3(w, h, d), Vector3(px, lift + h * 0.5, pz),
				ToonFactory.plaster(RIBEIRA_WALLS[rng.randi() % RIBEIRA_WALLS.size()], 1.6))

		# Projecting eaves band. Cheapest strong feature on the whole facade: at
		# the sun's 11.5 degrees a 15 cm overhang throws a hard horizontal shadow
		# most of the way down the wall, which is exactly what a flat box lacks.
		SceneryKit.box(terrace, "Eaves", Vector3(w + 0.30, 0.18, d + 0.30),
				Vector3(px, lift + h - 0.09, pz), trim)

		var roof_h := rng.randf_range(1.6, 2.6)
		var roof := MeshInstance3D.new()
		roof.name = "Roof"
		var roof_mesh := PrismMesh.new()
		# PrismMesh extrudes its triangle along Z, so the gable faces the bridge
		# and the slopes fall away in +-X. Chimneys are offset in X for that reason.
		roof_mesh.size = Vector3(w * 1.06, roof_h, d * 1.06)
		roof.mesh = roof_mesh
		roof.position = Vector3(px, lift + h + roof_h * 0.5, pz)
		roof.material_override = ToonFactory.terracotta(
				ROOF_COLORS[rng.randi() % ROOF_COLORS.size()], 0.8)
		terrace.add_child(roof)

		chimneys.append(Vector3(px + w * (0.28 if i % 2 == 0 else -0.28),
				lift + h + CHIMNEY_SIZE.y * 0.5, pz + d * 0.15))

		if rich:
			# Granite ground course. Grounds the house and gives the pavement line
			# somewhere to end; without it the render floats.
			SceneryKit.box(terrace, "GroundCourse", Vector3(w + 0.10, 0.70, d + 0.10),
					Vector3(px, lift + 0.35, pz), trim)
			doors.append(Vector3(px, lift + DOOR_SIZE.y * 0.5, face + 0.02))

		var floors := clampi(int((h - GROUND_FLOOR) / FLOOR_HEIGHT), 1, MAX_FLOORS)
		var cols := 2 if w > 3.0 else 1
		for f in floors:
			var sill_y := lift + GROUND_FLOOR + float(f) * FLOOR_HEIGHT
			var win_y := sill_y + SILL_SIZE.y + WINDOW_SIZE.y * 0.5
			for c in cols:
				var cx := px + (float(c) - float(cols - 1) * 0.5) * (w * 0.44)
				frames.append(Vector3(cx, win_y, face + 0.01))
				var pane := Vector3(cx, win_y, face)
				if rng.randf() < LIT_WINDOW_CHANCE:
					lit_panes.append(pane)
				else:
					panes.append(pane)
				if rich:
					sills.append(Vector3(cx, sill_y + SILL_SIZE.y * 0.5, face + 0.07))
			if rich and f == 1 and rng.randf() < BALCONY_CHANCE:
				balconies.append(Vector3(px, sill_y - BALCONY_SLAB.y * 0.5, face + 0.30))
				balcony_rails.append(Vector3(px, sill_y + BALCONY_RAIL.y * 0.5, face + 0.57))

	SceneryKit.repeat(terrace, "WindowSurrounds", WINDOW_SIZE, frames, trim)
	SceneryKit.repeat(terrace, "Panes", PANE_SIZE, panes,
			ToonFactory.solid(PANE_DARK, 0.0, 0.16))
	SceneryKit.repeat(terrace, "LitPanes", PANE_SIZE, lit_panes,
			ToonFactory.glow(PANE_LIT, 2.2))
	SceneryKit.repeat(terrace, "Sills", SILL_SIZE, sills, trim)
	SceneryKit.repeat(terrace, "Doors", DOOR_SIZE, doors, ToonFactory.wood(DOOR_WOOD, 0.35))
	SceneryKit.repeat(terrace, "Balconies", BALCONY_SLAB, balconies, trim)
	SceneryKit.repeat(terrace, "BalconyRails", BALCONY_RAIL, balcony_rails,
			ToonFactory.iron(BALCONY_IRON, 0.35, 0.25, 0.50))
	SceneryKit.repeat(terrace, "Chimneys", CHIMNEY_SIZE, chimneys,
			ToonFactory.terracotta(CHIMNEY_BRICK, 0.4))


# --- Gaia port-wine lodges ---------------------------------------------------

## Long low warehouse lodges on the Gaia waterline shelf, wearing the big rooftop
## lettering the real bank is famous for (generic names only — no brands).
func _build_gaia_lodges() -> void:
	var lodges := Node3D.new()
	lodges.name = "GaiaLodges"
	add_child(lodges)

	var rng := RandomNumberGenerator.new()
	rng.seed = 4711

	# Limewash, but well down from the old 0.93: a big low-pitched roof plus a
	# near-white wall is two thousand square metres of clipped highlight.
	var wall_mat := ToonFactory.plaster(Color(0.84, 0.81, 0.74), 2.4)
	var roof_mat := ToonFactory.terracotta(ROOF_COLORS[0], 0.8)
	var signs := ["PORTO", "VINHO DO PORTO", "CAVES DO DOURO"]
	var sign_sizes := [200, 120, 120]

	# Strung out along the Gaia shelf, so they follow if CITY_BANK_X moves.
	var offsets := [-2.0, 11.0, 24.0, 36.0]
	for i in offsets.size():
		var x: float = CITY_BANK_X + float(offsets[i])
		var length := rng.randf_range(12.0, 14.0)
		var height := rng.randf_range(4.0, 5.0)
		var depth := rng.randf_range(7.0, 8.0)
		var z := rng.randf_range(-14.0, -6.0)
		var base_y := -10.1

		SceneryKit.box(lodges, "Lodge", Vector3(length, height, depth),
				Vector3(x, base_y + height * 0.5, z), wall_mat)

		# Ridge must run along X on these long sheds: PrismMesh extrudes its
		# triangle along Z, so swap the footprint axes and yaw the prism 90°.
		var roof := MeshInstance3D.new()
		roof.name = "LodgeRoof"
		var roof_mesh := PrismMesh.new()
		roof_mesh.size = Vector3(depth * 1.08, 1.8, length * 1.05)
		roof.mesh = roof_mesh
		roof.rotation.y = PI * 0.5
		roof.position = Vector3(x, base_y + height + 0.9, z)
		roof.material_override = roof_mat
		lodges.add_child(roof)

		if i < signs.size():
			_lodge_sign(lodges, signs[i], sign_sizes[i], x, z, base_y + height + 1.8)


## Rooftop skeleton sign: two thin posts on the ridge holding up big lettering.
func _lodge_sign(parent: Node3D, text: String, size_px: int, x: float, z: float, roof_y: float) -> void:
	var post_mat := ToonFactory.iron(Color(0.30, 0.28, 0.26), 0.6, 0.3, 0.55)
	for px in [x - 3.0, x + 3.0]:
		SceneryKit.box(parent, "SignPost", Vector3(0.15, 1.6, 0.15),
				Vector3(px, roof_y + 0.8, z), post_mat)

	var label := Label3D.new()
	label.name = "SignText"
	label.text = text
	label.font = load("res://assets/fonts/Fredoka-Bold.woff2")
	label.font_size = size_px
	label.pixel_size = 0.012
	label.modulate = Color(1.0, 0.95, 0.85)
	label.outline_size = int(size_px * 0.18)
	label.outline_modulate = Color(0.15, 0.12, 0.10)
	label.position = Vector3(x, roof_y + 1.9, z)
	parent.add_child(label)


# --- Rabelo boats ------------------------------------------------------------

## A few moored rabelos — flat dark hulls, upswept bow and stern, one square
## cream sail, port barrels on deck — bobbed on the river waves in _process.
func _build_rabelos() -> void:
	var fleet := Node3D.new()
	fleet.name = "Rabelos"
	add_child(fleet)

	for i in RABELO_SPOTS.size():
		var spot: Vector3 = RABELO_SPOTS[i]
		var boat := _build_rabelo(fleet)
		boat.position = Vector3(spot.x, -14.75, spot.z)
		boat.rotation.y = RABELO_YAWS[i]
		_rabelos.append(boat)


func _build_rabelo(parent: Node3D) -> Node3D:
	var boat := Node3D.new()
	boat.name = "Rabelo"
	parent.add_child(boat)

	# Object-space triplanar throughout, never SceneryKit.world_mapped: these hulls
	# bob every frame and a world-mapped one swims through its own grain.
	var wood := ToonFactory.wood(Color(0.32, 0.21, 0.12), 0.9)
	var sail_mat := ToonFactory.cloth(Color(0.88, 0.83, 0.72))
	var barrel_mat := ToonFactory.wood(Color(0.50, 0.33, 0.16), 0.35)

	SceneryKit.box(boat, "Hull", Vector3(5.5, 0.7, 1.6), Vector3.ZERO, wood)

	# The upswept bow and stern are the rabelo silhouette's give-away.
	for sx in [-1.0, 1.0]:
		var tip := SceneryKit.box(boat, "Tip", Vector3(1.6, 0.5, 1.3),
				Vector3(sx * 3.0, 0.55, 0.0), wood)
		tip.rotation.z = sx * 0.45

	SceneryKit.cylinder(boat, "Mast", 0.07, 0.09, 4.5, Vector3(-0.5, 2.5, 0.0), wood)
	SceneryKit.box(boat, "Yard", Vector3(2.6, 0.12, 0.12), Vector3(-0.5, 4.35, 0.0), wood)
	# Sail faces the camera; artistic licence over rigging accuracy.
	SceneryKit.box(boat, "Sail", Vector3(2.4, 2.0, 0.06), Vector3(-0.5, 3.2, 0.0), sail_mat)

	# The espadela: the long steering oar trailing up off the stern.
	var oar := SceneryKit.box(boat, "Espadela", Vector3(3.5, 0.1, 0.15),
			Vector3(4.2, 1.0, 0.3), wood)
	oar.rotation.z = 0.35

	for bx in [-0.2, 0.7]:
		var barrel := SceneryKit.cylinder(boat, "Barrel", 0.32, 0.32, 0.65,
				Vector3(bx, 0.55, 0.0), barrel_mat, 10)
		barrel.rotation.x = PI * 0.5

	return boat


# --- Landmarks ---------------------------------------------------------------

func _build_landmarks() -> void:
	var marks := Node3D.new()
	marks.name = "Landmarks"
	add_child(marks)

	# Serra do Pilar — the circular monastery dome on the Gaia (boss) side cliff.
	_build_dome(marks, Vector3(50.0, 9.0, -30.0))
	# Clérigos Tower — the slim granite bell tower, set back uphill on the Porto
	# side so it clears the rooflines the way the real one does.
	_build_tower(marks, Vector3(-(CITY_BANK_X + 2.0), 7.0, -38.0))


func _build_dome(parent: Node3D, pos: Vector3) -> void:
	var grp := Node3D.new()
	grp.position = pos
	parent.add_child(grp)

	SceneryKit.cylinder(grp, "Drum", 5.0, 5.6, 8.0, Vector3(0.0, 4.0, 0.0),
			ToonFactory.plaster(Color(0.72, 0.68, 0.62), 2.2), 16)

	var dome := MeshInstance3D.new()
	dome.name = "Dome"
	var dome_mesh := SphereMesh.new()
	dome_mesh.radius = 5.0
	dome_mesh.height = 5.0
	dome_mesh.is_hemisphere = true
	dome_mesh.radial_segments = 16
	dome_mesh.rings = 8
	dome.mesh = dome_mesh
	dome.position = Vector3(0.0, 8.0, 0.0)
	dome.material_override = ToonFactory.stone(Color(0.50, 0.52, 0.55), 2.0)
	grp.add_child(dome)

	# The monastery's circular cloister colonnade ringing the drum. Tile pulled to
	# 0.55: a 1.2 m tile on a 0.56 m column showed less than half a period of the
	# granite grain, which reads as a smooth plastic post.
	var col_mat := ToonFactory.stone(Color(0.78, 0.75, 0.69), 0.55)
	for i in 8:
		var ang := TAU * float(i) / 8.0
		SceneryKit.cylinder(grp, "Column", 0.28, 0.28, 3.0,
				Vector3(cos(ang) * 6.3, 1.5, sin(ang) * 6.3), col_mat)

	SceneryKit.cylinder(grp, "CloisterRing", 6.4, 6.4, 0.5, Vector3(0.0, 3.4, 0.0), col_mat, 16)

	# A low monastery wing trailing along the clifftop.
	SceneryKit.box(grp, "Wing", Vector3(8.0, 3.5, 6.0), Vector3(5.5, 1.75, -4.0),
			ToonFactory.plaster(Color(0.74, 0.70, 0.64), 2.2))


func _build_tower(parent: Node3D, pos: Vector3) -> void:
	var grp := Node3D.new()
	grp.position = pos
	parent.add_child(grp)

	var granite_mat := ToonFactory.stone(Color(0.56, 0.54, 0.50), 2.0)
	# Openings read as holes, so: no detail map, fully rough, no spec to catch.
	var dark_inset := ToonFactory.solid(Color(0.12, 0.11, 0.10), 0.0, 1.0)

	SceneryKit.box(grp, "Shaft", Vector3(4.0, 34.0, 4.0), Vector3(0.0, 17.0, 0.0), granite_mat)

	# Baroque cornice bands breaking up the shaft.
	for cy in [12.0, 22.0]:
		SceneryKit.box(grp, "Cornice", Vector3(4.8, 0.6, 4.8), Vector3(0.0, cy, 0.0), granite_mat)

	# The clock face partway up the +z (camera) side.
	SceneryKit.box(grp, "Clock", Vector3(1.3, 1.3, 0.2), Vector3(0.0, 23.5, 2.05),
			ToonFactory.plaster(Color(0.86, 0.82, 0.72), 0.6))

	# Belfry stage with dark arched openings on the three visible faces.
	SceneryKit.box(grp, "Belfry", Vector3(3.7, 6.0, 3.7), Vector3(0.0, 29.0, 0.0), granite_mat)

	for opening in [Vector3(0.0, 29.0, 1.95), Vector3(1.95, 29.0, 0.0), Vector3(-1.95, 29.0, 0.0)]:
		var size := Vector3(1.6, 2.8, 0.2) if absf(opening.z) > 0.0 else Vector3(0.2, 2.8, 1.6)
		SceneryKit.box(grp, "BelfryOpening", size, opening, dark_inset)

	SceneryKit.box(grp, "Balustrade", Vector3(4.6, 0.5, 4.6), Vector3(0.0, 32.3, 0.0), granite_mat)

	# Tapered crown, small dome and finial spike.
	var crown_mat := ToonFactory.stone(Color(0.48, 0.46, 0.43), 1.4)
	SceneryKit.cylinder(grp, "Cap", 1.2, 2.4, 4.0, Vector3(0.0, 34.5, 0.0), crown_mat)

	var crown := MeshInstance3D.new()
	crown.name = "Crown"
	var crown_mesh := SphereMesh.new()
	crown_mesh.radius = 1.2
	crown_mesh.height = 1.2
	crown_mesh.is_hemisphere = true
	crown_mesh.radial_segments = 8
	crown_mesh.rings = 4
	crown.mesh = crown_mesh
	crown.position = Vector3(0.0, 36.5, 0.0)
	crown.material_override = crown_mat
	grp.add_child(crown)

	SceneryKit.cylinder(grp, "Finial", 0.03, 0.08, 1.4, Vector3(0.0, 38.2, 0.0),
			ToonFactory.iron(Color(0.35, 0.33, 0.30), 0.4, 0.6, 0.4), 6)


# --- Azulejo chapel ----------------------------------------------------------

## One chapel standing proud of the near terrace row, its facade carrying the
## blue-and-white azulejo tile panel that screams Porto. Sits a step in front of
## the houses (z -18) so the tile front never hides behind a taller neighbour.
func _build_azulejo_chapel() -> void:
	var chapel := Node3D.new()
	chapel.name = "AzulejoChapel"
	chapel.position = Vector3(-44.0, 0.0, -18.0)
	add_child(chapel)

	var dark := ToonFactory.solid(Color(0.15, 0.13, 0.12), 0.0, 1.0)
	var trim := ToonFactory.stone(TRIM_STONE, 0.9)

	SceneryKit.box(chapel, "Body", Vector3(7.0, 15.0, 3.0), Vector3(0.0, 7.5, 0.0),
			ToonFactory.plaster(Color(0.86, 0.87, 0.84), 2.0))

	var gable := MeshInstance3D.new()
	gable.name = "Gable"
	var gable_mesh := PrismMesh.new()
	gable_mesh.size = Vector3(7.4, 2.2, 3.2)
	gable.mesh = gable_mesh
	gable.position = Vector3(0.0, 16.1, 0.0)
	gable.material_override = trim
	chapel.add_child(gable)

	# Pilasters and a cornice: the chapel is the one facade the eye lands on, and
	# four projecting edges are what stop it reading as a painted flat.
	for sx in [-1.0, 1.0]:
		SceneryKit.box(chapel, "Pilaster", Vector3(0.55, 15.0, 0.35),
				Vector3(sx * 3.1, 7.5, 1.62), trim)
	SceneryKit.box(chapel, "Cornice", Vector3(7.6, 0.35, 3.6), Vector3(0.0, 14.8, 0.0), trim)

	SceneryKit.box(chapel, "Portal", Vector3(2.0, 3.5, 0.3), Vector3(0.0, 1.75, 1.55), dark)
	SceneryKit.box(chapel, "PortalSurround", Vector3(2.5, 4.0, 0.18), Vector3(0.0, 2.0, 1.5), trim)
	SceneryKit.box(chapel, "BellOpening", Vector3(1.2, 1.8, 0.2), Vector3(0.0, 13.5, 1.55), dark)

	# The azulejo band: offset tiles read as a blue-and-white checker from afar.
	# Deeper than the facade-palette blue — the warm sun washes lighter blues
	# out to near-white at this distance.
	var tiles: Array[Vector3] = []
	for col in 4:
		var tx := -1.5 + float(col)
		var ty := 6.0 if col % 2 == 0 else 7.0
		for r in 2:
			tiles.append(Vector3(tx, ty + float(r) * 2.0, 1.55))
	SceneryKit.repeat(chapel, "Azulejos", Vector3(1.0, 1.0, 0.15), tiles,
			ToonFactory.ceramic(Color(0.16, 0.34, 0.62), 0.5))


# --- Clouds ------------------------------------------------------------------

func _build_clouds() -> void:
	# Fully rough and untextured: a detail normal on a 4 m puff at 50 m just
	# shimmers, and the rim term already gives the golden-hour edge glow.
	var cloud_mat := ToonFactory.solid(Color(0.95, 0.90, 0.84), 0.0, 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210

	var holder := Node3D.new()
	holder.name = "Clouds"
	add_child(holder)

	for i in 9:
		var cloud := Node3D.new()
		cloud.name = "Cloud%d" % i
		cloud.position = Vector3(
			rng.randf_range(CLOUD_WRAP_MIN, CLOUD_WRAP_MAX),
			rng.randf_range(34.0, 58.0),
			rng.randf_range(-70.0, -30.0)
		)
		var cloud_scale := rng.randf_range(1.0, 2.2)
		cloud.scale = Vector3.ONE * cloud_scale
		holder.add_child(cloud)

		# A cluster of overlapping flattened spheres makes a puffy toon cloud.
		var puffs := rng.randi_range(4, 6)
		for p in puffs:
			var puff := MeshInstance3D.new()
			var puff_mesh := SphereMesh.new()
			var radius := rng.randf_range(2.0, 4.0)
			puff_mesh.radius = radius
			puff_mesh.height = radius * 2.0
			puff_mesh.radial_segments = 12
			puff_mesh.rings = 6
			puff.mesh = puff_mesh
			puff.material_override = cloud_mat
			puff.position = Vector3(
				rng.randf_range(-5.0, 5.0),
				rng.randf_range(-1.0, 1.0),
				rng.randf_range(-1.5, 1.5)
			)
			puff.scale = Vector3(1.0, 0.6, 1.0)
			cloud.add_child(puff)

		_clouds.append(cloud)


# --- Gulls -------------------------------------------------------------------

## A handful of gulls circling over the river gap — two flapping wing slabs each,
## driven from _process. They live between the rail line and the skyline, so
## they're always somewhere in frame.
func _build_gulls() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 777

	var holder := Node3D.new()
	holder.name = "Gulls"
	add_child(holder)

	var feather := ToonFactory.solid(Color(0.94, 0.94, 0.92), 0.0, 0.90)

	for i in GULL_COUNT:
		var gull := Node3D.new()
		gull.name = "Gull%d" % i
		holder.add_child(gull)

		for sx in [-1.0, 1.0]:
			SceneryKit.box(gull, "Wing", Vector3(1.1, 0.06, 0.35),
					Vector3(sx * 0.5, 0.0, 0.0), feather)

		_gulls.append(gull)
		# Flight envelope hugs the open air over the river: behind the far parapet
		# (z <= ~-8), short of the house fronts (z >= ~-19) and clear of the
		# terrace x-slots, so a loop never clips a roof or the boss.
		_gull_data.append({
			"center": Vector3(
				rng.randf_range(-25.0, 25.0),
				rng.randf_range(10.0, 16.0),
				rng.randf_range(-16.0, -12.0)
			),
			"radius": rng.randf_range(6.0, 9.0),
			"speed": rng.randf_range(0.3, 0.6) * (1.0 if i % 2 == 0 else -1.0),
			"phase": rng.randf_range(0.0, TAU),
		})
