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

const CLOUD_SPEED := 1.4          # world units / second of drift along +X
const CLOUD_WRAP_MIN := -120.0    # x where a cloud re-appears after wrapping
const CLOUD_WRAP_MAX := 120.0     # x past which a cloud wraps back

# Ribeira facade palette — ochre, terracotta, cream, azulejo blue, mustard, rose.
const RIBEIRA_WALLS := [
	Color(0.91, 0.72, 0.30),  # ochre yellow
	Color(0.78, 0.36, 0.29),  # terracotta red
	Color(0.90, 0.82, 0.64),  # cream
	Color(0.50, 0.66, 0.79),  # azulejo blue
	Color(0.79, 0.54, 0.23),  # mustard
	Color(0.71, 0.78, 0.64),  # faded green
	Color(0.88, 0.78, 0.69),  # rose-beige
]
const ROOF_COLOR := Color(0.62, 0.29, 0.21)   # terracotta tile

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

	# Big tiles on the hillside masses: these boxes are 50-60 m across and a
	# tight tile would alias into shimmer at this distance.
	var plaster := ToonFactory.plaster(Color(0.60, 0.56, 0.50), 4.0)
	var granite := ToonFactory.stone(Color(0.55, 0.52, 0.48), 3.5)
	var cobble := ToonFactory.cobblestone(Color(0.66, 0.63, 0.58), 1.8)

	for sx in [-1.0, 1.0]:
		# Waterline shelf the quay row and lodges sit on (top y = -10).
		_bank_box(banks, Vector3(56.0, 5.0, 44.0), Vector3(sx * 78.0, -12.5, -14.0), plaster)
		# Cais promenade running from the house fronts to the water's edge,
		# finished with the granite quay wall dropping to the river.
		_bank_box(banks, Vector3(56.0, 0.6, 16.0), Vector3(sx * 78.0, -9.9, 0.0), cobble)
		_bank_box(banks, Vector3(56.0, 2.2, 1.0), Vector3(sx * 78.0, -11.0, 8.4), granite)
		# Hillside tiers directly under the two existing terrace rows.
		_bank_box(banks, Vector3(60.0, 10.0, 26.0), Vector3(sx * 66.0, -4.9, -26.0), plaster)
		_bank_box(banks, Vector3(50.0, 8.0, 22.0), Vector3(sx * 72.0, 3.1, -40.0), plaster)

	# Serra do Pilar's cliff: one stout rock mass whose top (y = 9) meets the dome.
	_bank_box(banks, Vector3(18.0, 24.0, 18.0), Vector3(51.0, -3.0, -30.0),
			ToonFactory.stone(Color(0.48, 0.42, 0.36), 4.5))


func _bank_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var box := MeshInstance3D.new()
	box.name = "Bank"
	var mesh := BoxMesh.new()
	mesh.size = size
	box.mesh = mesh
	box.position = pos
	box.material_override = mat
	parent.add_child(box)


# --- Ribeira terraces ------------------------------------------------------

func _build_city() -> void:
	var city := Node3D.new()
	city.name = "City"
	add_child(city)

	# Two banks beyond the bridge ends, each a tight lower terrace plus an upper
	# tier raised + set back, so the houses read as climbing the Douro hillside.
	_build_terrace(city, -60.0, -22.0, 14, 0.0)
	_build_terrace(city, -66.0, -34.0, 11, 7.0)
	_build_terrace(city, 60.0, -22.0, 14, 0.0)
	_build_terrace(city, 66.0, -34.0, 11, 7.0)

	# Porto-side waterline row: low houses right on the quay, so the Ribeira
	# cascade runs all the way down to the river.
	_build_terrace(city, -64.0, -10.0, 8, -10.1, 5.0, 8.0)


## A row of narrow houses packed shoulder-to-shoulder along X, centred on center_x
## and receding at base_z, raised by `lift` (for a hillside tier). Height range is
## overridable so quay-level rows can stay low.
func _build_terrace(parent: Node3D, center_x: float, base_z: float, count: int, lift: float,
		h_min: float = 8.0, h_max: float = 20.0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absf(center_x) * 31.0 + absf(base_z) * 7.0 + lift * 13.0)

	var pitch := 3.4   # spacing between adjacent facades (width + a sliver of gap)
	var start_x := center_x - float(count - 1) * pitch * 0.5

	for i in count:
		var building := Node3D.new()
		parent.add_child(building)

		var w := rng.randf_range(2.6, 3.4)
		var d := rng.randf_range(3.0, 4.5)
		var h := rng.randf_range(h_min, h_max)

		var px := start_x + float(i) * pitch + rng.randf_range(-0.3, 0.3)
		var pz := base_z + rng.randf_range(-1.5, 1.5)
		building.position = Vector3(px, lift, pz)

		# Wall: a tall narrow terraced facade.
		var wall := MeshInstance3D.new()
		wall.name = "Wall"
		var wall_mesh := BoxMesh.new()
		wall_mesh.size = Vector3(w, h, d)
		wall.mesh = wall_mesh
		wall.position = Vector3(0.0, h * 0.5, 0.0)
		# Seven palette colours across dozens of facades, and the factory caches by
		# colour, so the whole terrace batches onto seven materials.
		wall.material_override = ToonFactory.plaster(RIBEIRA_WALLS[rng.randi() % RIBEIRA_WALLS.size()], 1.6)
		building.add_child(wall)

		# Pitched terracotta roof: a triangular prism whose gable faces the camera.
		var roof := MeshInstance3D.new()
		roof.name = "Roof"
		var roof_mesh := PrismMesh.new()
		roof_mesh.size = Vector3(w * 1.05, rng.randf_range(1.6, 2.6), d * 1.05)
		roof.mesh = roof_mesh
		roof.position = Vector3(0.0, h + roof_mesh.size.y * 0.5, 0.0)
		roof.material_override = ToonFactory.terracotta(ROOF_COLOR)
		building.add_child(roof)

		_add_windows(building, w, h, d, rng)


func _add_windows(building: Node3D, w: float, h: float, d: float, rng: RandomNumberGenerator) -> void:
	var window_glow := Color(1.0, 0.83, 0.46)
	var rows := int(clamp(h / 6.0, 1.0, 3.0))
	for r in rows:
		var win := MeshInstance3D.new()
		win.name = "Window"
		var win_mesh := BoxMesh.new()
		win_mesh.size = Vector3(w * 0.5, 1.2, 0.2)
		win.mesh = win_mesh
		win.material_override = ToonFactory.glow(window_glow, 1.4, 0.0)
		win.position = Vector3(0.0, 3.0 + float(r) * 5.0, d * 0.5 + 0.05)
		building.add_child(win)


# --- Gaia port-wine lodges ---------------------------------------------------

## Long low warehouse lodges on the Gaia waterline shelf, wearing the big rooftop
## lettering the real bank is famous for (generic names only — no brands).
func _build_gaia_lodges() -> void:
	var lodges := Node3D.new()
	lodges.name = "GaiaLodges"
	add_child(lodges)

	var rng := RandomNumberGenerator.new()
	rng.seed = 4711

	var wall_mat := ToonFactory.plaster(Color(0.93, 0.90, 0.82), 2.4)
	var roof_mat := ToonFactory.terracotta(ROOF_COLOR)
	var signs := ["PORTO", "VINHO DO PORTO", "CAVES DO DOURO"]
	var sign_sizes := [200, 120, 120]

	var xs := [58.0, 71.0, 84.0, 96.0]
	for i in xs.size():
		var x: float = xs[i]
		var length := rng.randf_range(12.0, 14.0)
		var height := rng.randf_range(4.0, 5.0)
		var depth := rng.randf_range(7.0, 8.0)
		var z := rng.randf_range(-14.0, -6.0)
		var base_y := -10.1

		var body := MeshInstance3D.new()
		body.name = "Lodge"
		var body_mesh := BoxMesh.new()
		body_mesh.size = Vector3(length, height, depth)
		body.mesh = body_mesh
		body.position = Vector3(x, base_y + height * 0.5, z)
		body.material_override = wall_mat
		lodges.add_child(body)

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
		var post := MeshInstance3D.new()
		post.name = "SignPost"
		var post_mesh := BoxMesh.new()
		post_mesh.size = Vector3(0.15, 1.6, 0.15)
		post.mesh = post_mesh
		post.position = Vector3(px, roof_y + 0.8, z)
		post.material_override = post_mat
		parent.add_child(post)

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

	var wood := ToonFactory.wood(Color(0.36, 0.24, 0.14), 0.9)
	var sail_mat := ToonFactory.cloth(Color(0.93, 0.89, 0.79))
	var barrel_mat := ToonFactory.wood(Color(0.55, 0.36, 0.18), 0.35)

	var hull := MeshInstance3D.new()
	hull.name = "Hull"
	var hull_mesh := BoxMesh.new()
	hull_mesh.size = Vector3(5.5, 0.7, 1.6)
	hull.mesh = hull_mesh
	hull.material_override = wood
	boat.add_child(hull)

	# The upswept bow and stern are the rabelo silhouette's give-away.
	for sx in [-1.0, 1.0]:
		var tip := MeshInstance3D.new()
		tip.name = "Tip"
		var tip_mesh := BoxMesh.new()
		tip_mesh.size = Vector3(1.6, 0.5, 1.3)
		tip.mesh = tip_mesh
		tip.position = Vector3(sx * 3.0, 0.55, 0.0)
		tip.rotation.z = sx * 0.45
		tip.material_override = wood
		boat.add_child(tip)

	var mast := MeshInstance3D.new()
	mast.name = "Mast"
	var mast_mesh := CylinderMesh.new()
	mast_mesh.top_radius = 0.07
	mast_mesh.bottom_radius = 0.09
	mast_mesh.height = 4.5
	mast_mesh.radial_segments = 8
	mast.mesh = mast_mesh
	mast.position = Vector3(-0.5, 2.5, 0.0)
	mast.material_override = wood
	boat.add_child(mast)

	var yard := MeshInstance3D.new()
	yard.name = "Yard"
	var yard_mesh := BoxMesh.new()
	yard_mesh.size = Vector3(2.6, 0.12, 0.12)
	yard.mesh = yard_mesh
	yard.position = Vector3(-0.5, 4.35, 0.0)
	yard.material_override = wood
	boat.add_child(yard)

	# Sail faces the camera; artistic licence over rigging accuracy.
	var sail := MeshInstance3D.new()
	sail.name = "Sail"
	var sail_mesh := BoxMesh.new()
	sail_mesh.size = Vector3(2.4, 2.0, 0.06)
	sail.mesh = sail_mesh
	sail.position = Vector3(-0.5, 3.2, 0.0)
	sail.material_override = sail_mat
	boat.add_child(sail)

	# The espadela: the long steering oar trailing up off the stern.
	var oar := MeshInstance3D.new()
	oar.name = "Espadela"
	var oar_mesh := BoxMesh.new()
	oar_mesh.size = Vector3(3.5, 0.1, 0.15)
	oar.mesh = oar_mesh
	oar.position = Vector3(4.2, 1.0, 0.3)
	oar.rotation.z = 0.35
	oar.material_override = wood
	boat.add_child(oar)

	for bx in [-0.2, 0.7]:
		var barrel := MeshInstance3D.new()
		barrel.name = "Barrel"
		var barrel_mesh := CylinderMesh.new()
		barrel_mesh.top_radius = 0.32
		barrel_mesh.bottom_radius = 0.32
		barrel_mesh.height = 0.65
		barrel_mesh.radial_segments = 10
		barrel.mesh = barrel_mesh
		barrel.position = Vector3(bx, 0.55, 0.0)
		barrel.rotation.x = PI * 0.5
		barrel.material_override = barrel_mat
		boat.add_child(barrel)

	return boat


# --- Landmarks -------------------------------------------------------------

func _build_landmarks() -> void:
	var marks := Node3D.new()
	marks.name = "Landmarks"
	add_child(marks)

	# Serra do Pilar — the circular monastery dome on the Gaia (boss) side cliff.
	_build_dome(marks, Vector3(50.0, 9.0, -30.0))
	# Clérigos Tower — the slim granite bell tower, set back uphill on the Porto
	# side so it clears the rooflines the way the real one does.
	_build_tower(marks, Vector3(-62.0, 7.0, -38.0))


func _build_dome(parent: Node3D, pos: Vector3) -> void:
	var grp := Node3D.new()
	grp.position = pos
	parent.add_child(grp)

	var drum := MeshInstance3D.new()
	var drum_mesh := CylinderMesh.new()
	drum_mesh.top_radius = 5.0
	drum_mesh.bottom_radius = 5.6
	drum_mesh.height = 8.0
	drum_mesh.radial_segments = 16
	drum.mesh = drum_mesh
	drum.position = Vector3(0.0, 4.0, 0.0)
	drum.material_override = ToonFactory.plaster(Color(0.78, 0.74, 0.68), 2.2)
	grp.add_child(drum)

	var dome := MeshInstance3D.new()
	var dome_mesh := SphereMesh.new()
	dome_mesh.radius = 5.0
	dome_mesh.height = 5.0
	dome_mesh.is_hemisphere = true
	dome_mesh.radial_segments = 16
	dome_mesh.rings = 8
	dome.mesh = dome_mesh
	dome.position = Vector3(0.0, 8.0, 0.0)
	dome.material_override = ToonFactory.stone(Color(0.55, 0.57, 0.60), 2.0)
	grp.add_child(dome)

	# The monastery's circular cloister colonnade ringing the drum.
	var col_mat := ToonFactory.stone(Color(0.85, 0.82, 0.76), 1.2)
	for i in 8:
		var ang := TAU * float(i) / 8.0
		var col := MeshInstance3D.new()
		col.name = "Column"
		var col_mesh := CylinderMesh.new()
		col_mesh.top_radius = 0.28
		col_mesh.bottom_radius = 0.28
		col_mesh.height = 3.0
		col_mesh.radial_segments = 8
		col.mesh = col_mesh
		col.position = Vector3(cos(ang) * 6.3, 1.5, sin(ang) * 6.3)
		col.material_override = col_mat
		grp.add_child(col)

	var ring := MeshInstance3D.new()
	ring.name = "CloisterRing"
	var ring_mesh := CylinderMesh.new()
	ring_mesh.top_radius = 6.4
	ring_mesh.bottom_radius = 6.4
	ring_mesh.height = 0.5
	ring_mesh.radial_segments = 16
	ring.mesh = ring_mesh
	ring.position = Vector3(0.0, 3.4, 0.0)
	ring.material_override = col_mat
	grp.add_child(ring)

	# A low monastery wing trailing along the clifftop.
	var wing := MeshInstance3D.new()
	wing.name = "Wing"
	var wing_mesh := BoxMesh.new()
	wing_mesh.size = Vector3(8.0, 3.5, 6.0)
	wing.mesh = wing_mesh
	wing.position = Vector3(5.5, 1.75, -4.0)
	wing.material_override = ToonFactory.plaster(Color(0.80, 0.76, 0.70), 2.2)
	grp.add_child(wing)


func _build_tower(parent: Node3D, pos: Vector3) -> void:
	var grp := Node3D.new()
	grp.position = pos
	parent.add_child(grp)

	var granite_mat := ToonFactory.stone(Color(0.60, 0.58, 0.54), 2.0)
	# Openings read as holes, so: no detail map, fully rough, no spec to catch.
	var dark_inset := ToonFactory.solid(Color(0.12, 0.11, 0.10), 0.0, 1.0)

	var shaft := MeshInstance3D.new()
	var shaft_mesh := BoxMesh.new()
	shaft_mesh.size = Vector3(4.0, 34.0, 4.0)
	shaft.mesh = shaft_mesh
	shaft.position = Vector3(0.0, 17.0, 0.0)
	shaft.material_override = granite_mat
	grp.add_child(shaft)

	# Baroque cornice bands breaking up the shaft.
	for cy in [12.0, 22.0]:
		var cornice := MeshInstance3D.new()
		cornice.name = "Cornice"
		var cornice_mesh := BoxMesh.new()
		cornice_mesh.size = Vector3(4.8, 0.6, 4.8)
		cornice.mesh = cornice_mesh
		cornice.position = Vector3(0.0, cy, 0.0)
		cornice.material_override = granite_mat
		grp.add_child(cornice)

	# The clock face partway up the +z (camera) side.
	var clock := MeshInstance3D.new()
	clock.name = "Clock"
	var clock_mesh := BoxMesh.new()
	clock_mesh.size = Vector3(1.3, 1.3, 0.2)
	clock.mesh = clock_mesh
	clock.position = Vector3(0.0, 23.5, 2.05)
	clock.material_override = ToonFactory.plaster(Color(0.92, 0.88, 0.78), 0.6)
	grp.add_child(clock)

	# Belfry stage with dark arched openings on the three visible faces.
	var belfry := MeshInstance3D.new()
	belfry.name = "Belfry"
	var belfry_mesh := BoxMesh.new()
	belfry_mesh.size = Vector3(3.7, 6.0, 3.7)
	belfry.mesh = belfry_mesh
	belfry.position = Vector3(0.0, 29.0, 0.0)
	belfry.material_override = granite_mat
	grp.add_child(belfry)

	for opening in [Vector3(0.0, 29.0, 1.95), Vector3(1.95, 29.0, 0.0), Vector3(-1.95, 29.0, 0.0)]:
		var slot := MeshInstance3D.new()
		slot.name = "BelfryOpening"
		var slot_mesh := BoxMesh.new()
		slot_mesh.size = Vector3(1.6, 2.8, 0.2) if absf(opening.z) > 0.0 else Vector3(0.2, 2.8, 1.6)
		slot.mesh = slot_mesh
		slot.position = opening
		slot.material_override = dark_inset
		grp.add_child(slot)

	var balustrade := MeshInstance3D.new()
	balustrade.name = "Balustrade"
	var bal_mesh := BoxMesh.new()
	bal_mesh.size = Vector3(4.6, 0.5, 4.6)
	balustrade.mesh = bal_mesh
	balustrade.position = Vector3(0.0, 32.3, 0.0)
	balustrade.material_override = granite_mat
	grp.add_child(balustrade)

	# Tapered crown, small dome and finial spike.
	var cap := MeshInstance3D.new()
	var cap_mesh := CylinderMesh.new()
	cap_mesh.top_radius = 1.2
	cap_mesh.bottom_radius = 2.4
	cap_mesh.height = 4.0
	cap_mesh.radial_segments = 8
	cap.mesh = cap_mesh
	cap.position = Vector3(0.0, 34.5, 0.0)
	cap.material_override = ToonFactory.stone(Color(0.50, 0.48, 0.45), 1.4)
	grp.add_child(cap)

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
	crown.material_override = ToonFactory.stone(Color(0.50, 0.48, 0.45), 1.4)
	grp.add_child(crown)

	var finial := MeshInstance3D.new()
	finial.name = "Finial"
	var finial_mesh := CylinderMesh.new()
	finial_mesh.top_radius = 0.03
	finial_mesh.bottom_radius = 0.08
	finial_mesh.height = 1.4
	finial_mesh.radial_segments = 6
	finial.mesh = finial_mesh
	finial.position = Vector3(0.0, 38.2, 0.0)
	finial.material_override = ToonFactory.iron(Color(0.35, 0.33, 0.30), 0.4, 0.6, 0.4)
	grp.add_child(finial)


# --- Azulejo chapel ----------------------------------------------------------

## One chapel standing proud of the near terrace row, its facade carrying the
## blue-and-white azulejo tile panel that screams Porto. Sits a step in front of
## the houses (z -18) so the tile front never hides behind a taller neighbour.
func _build_azulejo_chapel() -> void:
	var chapel := Node3D.new()
	chapel.name = "AzulejoChapel"
	chapel.position = Vector3(-44.0, 0.0, -18.0)
	add_child(chapel)

	var body := MeshInstance3D.new()
	body.name = "Body"
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(7.0, 15.0, 3.0)
	body.mesh = body_mesh
	body.position = Vector3(0.0, 7.5, 0.0)
	body.material_override = ToonFactory.plaster(Color(0.93, 0.94, 0.91), 2.0)
	chapel.add_child(body)

	var gable := MeshInstance3D.new()
	gable.name = "Gable"
	var gable_mesh := PrismMesh.new()
	gable_mesh.size = Vector3(7.4, 2.2, 3.2)
	gable.mesh = gable_mesh
	gable.position = Vector3(0.0, 16.1, 0.0)
	gable.material_override = ToonFactory.stone(Color(0.60, 0.58, 0.54), 2.0)
	chapel.add_child(gable)

	var portal := MeshInstance3D.new()
	portal.name = "Portal"
	var portal_mesh := BoxMesh.new()
	portal_mesh.size = Vector3(2.0, 3.5, 0.3)
	portal.mesh = portal_mesh
	portal.position = Vector3(0.0, 1.75, 1.55)
	portal.material_override = ToonFactory.solid(Color(0.15, 0.13, 0.12), 0.0, 1.0)
	chapel.add_child(portal)

	var bell := MeshInstance3D.new()
	bell.name = "BellOpening"
	var bell_mesh := BoxMesh.new()
	bell_mesh.size = Vector3(1.2, 1.8, 0.2)
	bell.mesh = bell_mesh
	bell.position = Vector3(0.0, 13.5, 1.55)
	bell.material_override = ToonFactory.solid(Color(0.15, 0.13, 0.12), 0.0, 1.0)
	chapel.add_child(bell)

	# The azulejo band: offset tiles read as a blue-and-white checker from afar.
	# Deeper than the facade-palette blue — the warm sun washes lighter blues
	# out to near-white at this distance.
	var tile_mat := ToonFactory.ceramic(Color(0.18, 0.38, 0.66), 0.5)
	for col in 4:
		var tx := -1.5 + float(col)
		var ty := 6.0 if col % 2 == 0 else 7.0
		for row in 2:
			var tile := MeshInstance3D.new()
			tile.name = "Tile"
			var tile_mesh := BoxMesh.new()
			tile_mesh.size = Vector3(1.0, 1.0, 0.15)
			tile.mesh = tile_mesh
			tile.position = Vector3(tx, ty + float(row) * 2.0, 1.55)
			tile.material_override = tile_mat
			chapel.add_child(tile)


# --- Clouds ----------------------------------------------------------------

func _build_clouds() -> void:
	# Fully rough and untextured: a detail normal on a 4 m puff at 50 m just
	# shimmers, and the rim term already gives the golden-hour edge glow.
	var cloud_mat := ToonFactory.solid(Color(0.99, 0.93, 0.86), 0.0, 1.0)
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

	var feather := ToonFactory.solid(Color(0.97, 0.97, 0.95), 0.0, 0.90)

	for i in GULL_COUNT:
		var gull := Node3D.new()
		gull.name = "Gull%d" % i
		holder.add_child(gull)

		for sx in [-1.0, 1.0]:
			var wing := MeshInstance3D.new()
			wing.name = "Wing"
			var wing_mesh := BoxMesh.new()
			wing_mesh.size = Vector3(1.1, 0.06, 0.35)
			wing.mesh = wing_mesh
			wing.position = Vector3(sx * 0.5, 0.0, 0.0)
			wing.material_override = feather
			gull.add_child(wing)

		_gulls.append(gull)
		# Flight envelope hugs the open air over the river: behind the far rail
		# (z <= ~-7), short of the house fronts (z >= ~-21) and clear of the
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
