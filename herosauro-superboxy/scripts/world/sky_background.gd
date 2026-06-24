extends Node3D
## SkyBackground: the warm Porto golden-hour backdrop.
##
## The WorldEnvironment + sunset Sky live in the .tscn; this script procedurally
## scatters the low-poly Porto city silhouette across both banks (terracotta and
## sand box buildings with little cone roofs, beyond the bridge ends) and a few
## drifting toon cloud clusters that slowly slide across the sky and wrap around.
## Everything here is purely decorative - no collision.

const CLOUD_SPEED := 1.4          # world units / second of drift along +X
const CLOUD_WRAP_MIN := -120.0    # x where a cloud re-appears after wrapping
const CLOUD_WRAP_MAX := 120.0     # x past which a cloud wraps back

var _clouds: Array[Node3D] = []


func _ready() -> void:
	_build_city()
	_build_clouds()


func _process(delta: float) -> void:
	# Drift the clouds and wrap them around so the sky never empties out.
	for cloud in _clouds:
		cloud.position.x += CLOUD_SPEED * delta
		if cloud.position.x > CLOUD_WRAP_MAX:
			cloud.position.x = CLOUD_WRAP_MIN


# --- City silhouette -------------------------------------------------------

func _build_city() -> void:
	# Warm Porto palette: terracotta, sand, ochre, faded rose, roof-tile red.
	var wall_colors := [
		Color(0.86, 0.55, 0.36),  # terracotta
		Color(0.91, 0.74, 0.50),  # sand
		Color(0.80, 0.46, 0.34),  # clay
		Color(0.93, 0.82, 0.62),  # pale ochre
		Color(0.78, 0.60, 0.52),  # faded rose
	]
	var roof_color := Color(0.66, 0.24, 0.18)  # tile red

	var city := Node3D.new()
	city.name = "City"
	add_child(city)

	# Both banks sit just beyond the bridge ends (x = +-50) and recede backward
	# (toward -Z, away from the +Z camera) so they read as a distant skyline.
	_build_bank(city, -64.0, wall_colors, roof_color, 11)   # near (boss-side mirror)
	_build_bank(city, 64.0, wall_colors, roof_color, 11)    # far end of the bridge

	# A second, deeper row on each side for a layered skyline.
	_build_bank(city, -82.0, wall_colors, roof_color, 8)
	_build_bank(city, 82.0, wall_colors, roof_color, 8)


## Build one cluster of buildings centred on bank_x, scattered across Z behind
## the arena. count buildings of varied height, each topped with a cone roof.
func _build_bank(parent: Node3D, bank_x: float, wall_colors: Array, roof_color: Color, count: int) -> void:
	var rng := RandomNumberGenerator.new()
	# Deterministic per-bank seed so the skyline is stable across runs.
	rng.seed = int(abs(bank_x) * 17.0) + (1 if bank_x > 0.0 else 0)

	for i in count:
		var building := Node3D.new()
		parent.add_child(building)

		var w := rng.randf_range(4.0, 8.5)
		var d := rng.randf_range(4.0, 8.5)
		var h := rng.randf_range(8.0, 26.0)

		# Spread along X around the bank line and recede along -Z behind the deck.
		var px := bank_x + rng.randf_range(-12.0, 12.0)
		var pz := rng.randf_range(-14.0, -52.0)
		building.position = Vector3(px, 0.0, pz)
		building.rotation.y = rng.randf_range(-0.3, 0.3)

		# Wall box: base sits on the (implied) far waterline, grows upward.
		var wall := MeshInstance3D.new()
		wall.name = "Wall"
		var wall_mesh := BoxMesh.new()
		wall_mesh.size = Vector3(w, h, d)
		wall.mesh = wall_mesh
		wall.position = Vector3(0.0, h * 0.5, 0.0)
		wall.material_override = ToonFactory.solid(wall_colors[rng.randi() % wall_colors.size()], 0.06)
		building.add_child(wall)

		# Cone roof: a short, wide cylinder tapering to a point.
		var roof := MeshInstance3D.new()
		roof.name = "Roof"
		var roof_mesh := CylinderMesh.new()
		roof_mesh.top_radius = 0.0
		roof_mesh.bottom_radius = max(w, d) * 0.62
		roof_mesh.height = rng.randf_range(2.5, 4.5)
		roof_mesh.radial_segments = 6
		roof.mesh = roof_mesh
		roof.position = Vector3(0.0, h + roof_mesh.height * 0.5, 0.0)
		roof.material_override = ToonFactory.solid(roof_color, 0.06)
		building.add_child(roof)

		# A couple of glowing windows catching the golden light, on the +Z face.
		_add_windows(building, w, h, d, rng)


func _add_windows(building: Node3D, w: float, h: float, d: float, rng: RandomNumberGenerator) -> void:
	var window_glow := Color(1.0, 0.83, 0.46)
	var rows := int(clamp(h / 6.0, 1.0, 4.0))
	for r in rows:
		var win := MeshInstance3D.new()
		win.name = "Window"
		var win_mesh := BoxMesh.new()
		win_mesh.size = Vector3(w * 0.5, 1.4, 0.2)
		win.mesh = win_mesh
		win.material_override = ToonFactory.glow(window_glow, 1.4, 0.0)
		win.position = Vector3(0.0, 3.0 + float(r) * 5.0, d * 0.5 + 0.05)
		building.add_child(win)


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
