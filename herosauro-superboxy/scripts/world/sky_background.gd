extends Node3D
## SkyBackground: everything around the bridge.
##
## The WorldEnvironment and sky live in the .tscn. This script assembles the
## world the bridge stands in, and it is mostly a placement script now — the
## heavy lifting belongs to four builders:
##
##   TerrainBuilder    the granite quay, the terraced hillside and its stairs
##   FacadeBuilder     one Ribeira house per surveyed plot
##   LandmarksBuilder  Clerigos, the Se, Serra do Pilar, the tiled church, lodges
##   RiverLife         gulls, small craft, wakes and surface mist
##
## What it still owns directly is the cheap animated dressing: moored rabelos
## riding the same wave field the water shader draws, drifting clouds, and a few
## circling gulls. All decorative, none of it collides.
##
## The city used to be rows of coloured boxes laid along X at a fixed z. That was
## wrong twice over: the boxes read as painted card under a raking sun, and the
## rows ran across the open river channel, because the Douro runs along Z here
## and the bridge crosses it along X. Both are fixed — the terrain surveys the
## plots, and the facades are real punched geometry.

const RiverLifeScript := preload("res://scripts/world/river_life.gd")

const CLOUD_SPEED := 1.4          # world units / second of drift along +X
const CLOUD_WRAP_MIN := -120.0    # x where a cloud re-appears after wrapping
const CLOUD_WRAP_MAX := 120.0     # x past which a cloud wraps back

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
## Gaia's lodges are limewashed, not painted: the far bank must read as a
## different city from the Ribeira terraces facing it.
const LODGE_WHITEWASH := [
	Color(0.82, 0.79, 0.72),
	Color(0.78, 0.75, 0.69),
	Color(0.85, 0.82, 0.75),
	Color(0.74, 0.72, 0.67),
]
const ROOF_COLORS := [Color(0.56, 0.28, 0.22), Color(0.48, 0.26, 0.21)]

# Moored rabelo positions on the river (y is driven by the wave bob) and yaws.
const RABELO_SPOTS := [Vector3(-28.0, 0.0, -16.0), Vector3(8.0, 0.0, -24.0), Vector3(34.0, 0.0, -13.0)]
const RABELO_YAWS := [-0.35, 0.25, 0.6]

const GULL_COUNT := 5

var _clouds: Array[Node3D] = []
var _rabelos: Array[Node3D] = []
var _gulls: Array[Node3D] = []
var _gull_data: Array[Dictionary] = []


const CityBackdropScene: PackedScene = preload("res://scenes/world/city_backdrop.tscn")


func _ready() -> void:
	# The photogrammetry scan of the real district, closing the far end of the
	# gorge. Without it both banks stop dead in mid-air and the view opens onto
	# empty ocean — and terrain_builder's BANK_Z_FAR, the 900x900 river plane and
	# the lighting rig are all written assuming it is there.
	#
	# It self-gates: skipped on the Compatibility web tier, and guarded by
	# ResourceLoader.exists() so a web export that strips the 38 MB asset still
	# loads this scene.
	add_child(CityBackdropScene.instantiate())
	add_child(TerrainBuilder.build())
	_build_city()
	_build_landmarks()
	_build_rabelos()
	add_child(RiverLifeScript.new())
	_build_clouds()
	_build_gulls()


# --- Ribeira city ------------------------------------------------------------

## Fill the terraced hillside with Ribeira houses.
##
## The rows used to run along X at fixed z, which was simply wrong for this
## world: the Douro runs along Z and the bridge crosses it along X, so a row laid
## along X marched off its own bank and across the open channel. The terrain now
## owns the plan — `TerrainBuilder.building_plots()` returns a surveyed plot per
## house on every terrace level, already sitting on real ground and already
## facing the water — and each plot becomes a `FacadeBuilder.Spec`.
##
## Everything goes through one batch, so the whole city costs a couple of dozen
## draw calls (bounded by the number of distinct materials, not by the number of
## houses) rather than one per fitting.
func _build_city() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8_1881          # the year they started building the bridge

	var batch := FacadeBuilder.Batch.new()
	var built := 0
	for side in [TerrainBuilder.PORTO, TerrainBuilder.GAIA]:
		for plot in TerrainBuilder.building_plots(side):
			var spec := _spec_from_plot(plot, rng)
			if spec == null:
				continue
			FacadeBuilder.add_to_batch(batch, spec, rng)
			built += 1
	var city := batch.commit("Ribeira")
	city.name = "Ribeira"
	add_child(city)


## Turn one surveyed plot into a house. The terrain decides where and how big;
## this decides what kind of house stands there.
func _spec_from_plot(plot: Dictionary, rng: RandomNumberGenerator) -> FacadeBuilder.Spec:
	var centre: Vector3 = plot["center"]
	var level := int(plot["level"])
	var side: float = plot["side"]

	var spec := FacadeBuilder.Spec.new()
	spec.width = float(plot["width"]) - 0.12   # a hair of daylight between party walls
	spec.depth = minf(float(plot["depth"]), 9.0)
	spec.position = centre
	# `facing` points at the river, and a facade's front is its +Z.
	spec.yaw = atan2(plot["facing"].x, plot["facing"].z)
	# Two centuries of settlement: nothing on this hill is plumb.
	spec.lean = rng.randf_range(-0.022, 0.022)
	spec.tilt = rng.randf_range(-0.012, 0.012)

	# Gaia is not a second Ribeira, and building it as one was the single most
	# wrong thing about the far bank — it is the one the player stares at for the
	# whole fight. Its waterfront is port-wine lodges: long, low, whitewashed
	# sheds with shallow terracotta roofs, not tall painted terraces. Only its
	# upper levels are ordinary housing.
	var gaia_waterfront := side == TerrainBuilder.GAIA and level <= 1

	if gaia_waterfront:
		spec.floors = 1 + (1 if rng.randf() < 0.35 else 0)
		spec.floor_height = rng.randf_range(3.4, 4.2)
		spec.ground_height = rng.randf_range(3.8, 4.6)
		spec.attic = false
		spec.roof_pitch = rng.randf_range(0.20, 0.30)   # shallow shed pitch
		spec.gable_front = false
		spec.style = FacadeBuilder.Style.PLASTER
		spec.wall_color = LODGE_WHITEWASH[rng.randi() % LODGE_WHITEWASH.size()]
		spec.chimneys = 0
		spec.string_courses = false
		spec.lit_fraction = 0.04
	else:
		# The hill thins and drops a storey or two as it climbs, which is what
		# gives the Ribeira bank its taper.
		var floors := 5 - int(level / 2) + (1 if rng.randf() < 0.30 else 0)
		spec.floors = clampi(floors, 2, 6)
		spec.floor_height = rng.randf_range(2.75, 3.15)
		spec.ground_height = rng.randf_range(3.2, 3.9)
		spec.attic = rng.randf() < 0.35
		spec.roof_pitch = rng.randf_range(0.38, 0.50)
		spec.gable_front = rng.randf() < 0.28
		spec.chimneys = 1 + (1 if rng.randf() < 0.35 else 0)
		spec.lit_fraction = rng.randf_range(0.10, 0.28)

		# Style FIRST, then a colour from that style's own palette. Picking the
		# colour first meant every azulejo house came out ochre or terracotta —
		# 50 of 59 tiled facades, and not one of them blue.
		spec.style = FacadeBuilder.Style.AZULEJO if rng.randf() < 0.24 else FacadeBuilder.Style.PLASTER
		if level >= 4 and rng.randf() < 0.30:
			spec.style = FacadeBuilder.Style.GRANITE
		match spec.style:
			FacadeBuilder.Style.AZULEJO:
				spec.wall_color = FacadeBuilder.AZULEJO_PALETTE[rng.randi() % FacadeBuilder.AZULEJO_PALETTE.size()]
			FacadeBuilder.Style.GRANITE:
				spec.wall_color = FacadeBuilder.GRANITE_PALETTE[rng.randi() % FacadeBuilder.GRANITE_PALETTE.size()]
			_:
				spec.wall_color = RIBEIRA_WALLS[rng.randi() % RIBEIRA_WALLS.size()]

	spec.roof_color = ROOF_COLORS[rng.randi() % ROOF_COLORS.size()]

	# The waterfront level is the one the player can actually see into: give it
	# shopfronts, arcades and washing. Higher up it is all silhouette.
	if level == 0:
		if gaia_waterfront:
			spec.ground = FacadeBuilder.Ground.SHOPFRONT   # lodge loading doors
			spec.laundry = false
		else:
			spec.ground = FacadeBuilder.Ground.ARCH if rng.randf() < 0.45 else FacadeBuilder.Ground.SHOPFRONT
			spec.laundry = rng.randf() < 0.45
	else:
		spec.ground = FacadeBuilder.Ground.DOOR
		spec.laundry = false

	spec.detail = FacadeBuilder.Detail.FULL if int(plot["detail"]) >= 2 else FacadeBuilder.Detail.MEDIUM
	# NB: chimneys and lit_fraction are set per branch above and must NOT be
	# reassigned here. They were, and it silently undid the lodge branch: every
	# whitewashed shed on the Gaia waterfront came out with one or two housing
	# chimneys and a quarter of its windows lit, which is exactly the "second
	# Ribeira" read the branch exists to prevent.
	return spec


# --- Landmarks ---------------------------------------------------------------

## The skyline anchors, re-surveyed onto the rebuilt hillside.
##
## The landmark builder's own anchors were authored against the old flat-slab
## banks, where the house fronts stood at |x| = 60. The terrain now puts Porto's
## terrace fronts at |x| = 52 / 68 / 82 / 95 / 110 / 122 with the platform tops
## climbing -9.7 -> +12.9, and Gaia's bluff plateau at y = 9.30. Left alone,
## Serra do Pilar would have floated over open water two metres outside the quay.
## Each landmark is therefore pinned to the level it belongs on: Clérigos high
## and inland where it towers over everything, the Sé lower and near the bridge
## (which is where the real one sits, above the Porto abutment), the tiled church
## down on the waterfront where its azulejo flank faces the deck.
func _build_landmarks() -> void:
	var batch := LandmarksBuilder.Batch.new()
	LandmarksBuilder.add_clerigos_tower(batch, _anchor(Vector3(-114.0, 8.30, -46.0), 0.20))
	LandmarksBuilder.add_se_cathedral(batch, _anchor(Vector3(-88.0, 0.03, -30.0), -0.28))
	LandmarksBuilder.add_serra_do_pilar(batch, _anchor(Vector3(108.0, 9.30, -34.0), 0.40))
	LandmarksBuilder.add_igreja_azulejo(batch, _anchor(Vector3(-70.0, -5.11, -14.0), -0.14))

	var rng := RandomNumberGenerator.new()
	rng.seed = 30_417
	LandmarksBuilder._lodge_row(batch, _anchor(Vector3(53.0, -9.67, -12.0), 0.0), 3,
			LandmarksBuilder.Detail.FULL, rng)

	var marks := batch.commit("PortoLandmarks")
	add_child(marks)


func _anchor(pos: Vector3, yaw: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), pos)


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
