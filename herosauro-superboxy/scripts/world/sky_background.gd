extends Node3D
## SkyBackground: the warm Porto golden-hour backdrop.
##
## The WorldEnvironment + sunset Sky live in the .tscn; this script procedurally
## builds a recognizably-Porto skyline: tight terraces of narrow, colourful
## Ribeira houses with pitched terracotta roofs stacked up both banks, anchored by
## two landmarks — the round Serra do Pilar dome and the slim Clérigos tower — plus
## a few drifting toon clouds. Everything here is decorative, no collision.

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

var _clouds: Array[Node3D] = []


func _ready() -> void:
	_build_city()
	_build_landmarks()
	_build_clouds()


func _process(delta: float) -> void:
	# Drift the clouds and wrap them around so the sky never empties out.
	for cloud in _clouds:
		cloud.position.x += CLOUD_SPEED * delta
		if cloud.position.x > CLOUD_WRAP_MAX:
			cloud.position.x = CLOUD_WRAP_MIN


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


## A row of narrow houses packed shoulder-to-shoulder along X, centred on center_x
## and receding at base_z, raised by `lift` (for a hillside tier).
func _build_terrace(parent: Node3D, center_x: float, base_z: float, count: int, lift: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absf(center_x) * 31.0 + absf(base_z) * 7.0 + lift * 13.0)

	var pitch := 3.4   # spacing between adjacent facades (width + a sliver of gap)
	var start_x := center_x - float(count - 1) * pitch * 0.5

	for i in count:
		var building := Node3D.new()
		parent.add_child(building)

		var w := rng.randf_range(2.6, 3.4)
		var d := rng.randf_range(3.0, 4.5)
		var h := rng.randf_range(8.0, 20.0)

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
		wall.material_override = ToonFactory.solid(RIBEIRA_WALLS[rng.randi() % RIBEIRA_WALLS.size()], 0.05)
		building.add_child(wall)

		# Pitched terracotta roof: a triangular prism whose gable faces the camera.
		var roof := MeshInstance3D.new()
		roof.name = "Roof"
		var roof_mesh := PrismMesh.new()
		roof_mesh.size = Vector3(w * 1.05, rng.randf_range(1.6, 2.6), d * 1.05)
		roof.mesh = roof_mesh
		roof.position = Vector3(0.0, h + roof_mesh.size.y * 0.5, 0.0)
		roof.material_override = ToonFactory.solid(ROOF_COLOR, 0.05)
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


# --- Landmarks -------------------------------------------------------------

func _build_landmarks() -> void:
	var marks := Node3D.new()
	marks.name = "Landmarks"
	add_child(marks)

	# Serra do Pilar — the circular monastery dome on the Gaia (boss) side hill.
	_build_dome(marks, Vector3(50.0, 9.0, -30.0))
	# Clérigos Tower — the slim granite bell tower on the Porto side.
	_build_tower(marks, Vector3(-54.0, 0.0, -30.0))


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
	drum.material_override = ToonFactory.solid(Color(0.78, 0.74, 0.68), 0.05)
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
	dome.material_override = ToonFactory.solid(Color(0.55, 0.57, 0.60), 0.05)
	grp.add_child(dome)


func _build_tower(parent: Node3D, pos: Vector3) -> void:
	var grp := Node3D.new()
	grp.position = pos
	parent.add_child(grp)

	var granite := Color(0.60, 0.58, 0.54)

	var shaft := MeshInstance3D.new()
	var shaft_mesh := BoxMesh.new()
	shaft_mesh.size = Vector3(4.0, 30.0, 4.0)
	shaft.mesh = shaft_mesh
	shaft.position = Vector3(0.0, 15.0, 0.0)
	shaft.material_override = ToonFactory.solid(granite, 0.05)
	grp.add_child(shaft)

	# Tapered belfry cap.
	var cap := MeshInstance3D.new()
	var cap_mesh := CylinderMesh.new()
	cap_mesh.top_radius = 0.3
	cap_mesh.bottom_radius = 2.6
	cap_mesh.height = 6.0
	cap_mesh.radial_segments = 8
	cap.mesh = cap_mesh
	cap.position = Vector3(0.0, 33.0, 0.0)
	cap.material_override = ToonFactory.solid(Color(0.50, 0.48, 0.45), 0.05)
	grp.add_child(cap)


# --- Clouds ----------------------------------------------------------------

func _build_clouds() -> void:
	var cloud_mat := ToonFactory.solid(Color(0.99, 0.93, 0.86), 0.0)
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
