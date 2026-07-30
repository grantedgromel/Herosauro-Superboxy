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
## riding the same wave field the water shader draws, and drifting clouds. All
## decorative, none of it collides.
##
## It used to own five gulls as well — two 1.1 m boxes each, hinged at a point, pure
## white, no body — and Round 1 measured them as "untextured flat quads, bent
## rectangles hinged at a point, no wing shape, no body, no shading". They are gone
## rather than improved, because RiverLife already flies proper ones: a body, a head,
## a tail, a grey mantle, near-black primaries and a vertex-shader wingbeat, in a
## MultiMesh, with a flight envelope the probe checks against every landmark. Two
## flocks of birds in one sky where one of them is worse is a defect, not density.
##
## The city used to be rows of coloured boxes laid along X at a fixed z. That was
## wrong twice over: the boxes read as painted card under a raking sun, and the
## rows ran across the open river channel, because the Douro runs along Z here
## and the bridge crosses it along X. Both are fixed — the terrain surveys the
## plots, and the facades are real punched geometry.

const RiverLifeScript := preload("res://scripts/world/river_life.gd")
const CloudShader: Shader = preload("res://assets/shaders/soft_cloud.gdshader")

const CLOUD_SPEED := 1.4          # world units / second of drift along +X
const CLOUD_WRAP_MIN := -190.0    # x where a cloud re-appears after wrapping
const CLOUD_WRAP_MAX := 190.0     # x past which a cloud wraps back

# --- Ribeira palette ---------------------------------------------------------
# Pitched a good 10-15% darker than a photograph of these houses would suggest, with
# the chroma raised to match. That was originally a defence against a warm key and a
# high AgX white point bleaching every hue toward the same hot cream, and it still
# holds under the daylight rig for a different and better reason.
#
# The arithmetic, re-derived against the values porto_daylight.tres ACTUALLY carries
# (tonemap_exposure 0.72, tonemap_agx_white 4.0) and the re-keyed sun (energy 2.8 at
# 34 degrees elevation, 66 degrees east of +x):
#
#   These facades stand at -x facing +x, so their normal is +x and the key's incidence
#   on them is the sun vector's own x component, 0.337. plaster() takes the authored
#   ochre Color(0.80, 0.60, 0.22) to an effective mean albedo of the same 0.80 in red
#   (x1.13 for the fine layer's mean, then clamped at ALBEDO_CEILING, then multiplied
#   back down by the layer itself). So red arrives at 0.80 x 0.337 x 2.8 = 0.755
#   scene-referred, plus about 0.10 of ambient and quay bounce, and x0.72 of exposure
#   puts it at 0.60 going into AgX — high on the curve, short of the shoulder, a bright
#   wall that has kept its hue.
#
#   That is DOWN from 0.72 before the re-key, and the drop is deliberate. Round 1
#   measured the background out-shouting the playable deck by 2x in luminance and
#   2.5x in saturation; swinging the sun round toward +z cuts these facades' incidence
#   from 0.545 to 0.337 while the deck's is held flat by the energy change. Nobody's
#   paint was desaturated to get it — the Ribeira chord is the right chord for Porto
#   and the critics were explicit that it is not what is wrong.
#
#   Photo values here would still land past the white point and the terrace would go
#   back to being one cream stripe, which is the failure this palette was authored
#   against and the reason it is not simply brightened now that there is headroom.
#
# The saturation these carry also has to survive adjustment_saturation 1.12 on top of
# a per-channel LUT whose slope through the band they occupy (input 0.45-0.62) is now
# 0.95 rather than 1.3 — the grade compresses the background band on purpose this
# round. The reds are the closest to the edge; a render was checked at 1.20 and they
# went neon, which is why the environment's saturation is 1.12.

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

## Cloud field. Nine identically-scaled clusters at identical tilt read as two
## copy-pasted objects, which is what Round 1 saw; twelve over a much wider band, each
## with its own yaw, its own three-axis stretch and its own puff count, do not.
const CLOUD_COUNT := 12
## Height band and depth band the field occupies. Both pushed a long way out from the
## 34-58 / -70..-30 they used to sit in: at that range a 4 m puff scaled 2.2 subtends
## as much of shot 07 as a building does, which is why the old ones read as objects
## hanging over the river rather than as weather.
const CLOUD_Y := Vector2(58.0, 104.0)
const CLOUD_Z := Vector2(-210.0, -70.0)

var _clouds: Array[Node3D] = []
var _rabelos: Array[Node3D] = []
var _cloud_material: ShaderMaterial
## Seconds of simulated time since this node entered the tree — the animation
## clock for the rabelos. See the note in _process().
var _decor_time: float = 0.0


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
	# The cloud shader needs the direction the key actually points, and SunLight is a
	# sibling of the arena root that has not been resolved yet during this _ready().
	# Deferring is the same thing LightingRig does one node over and for the same
	# reason. Reading it rather than authoring a copy is the whole point: a
	# hand-copied sun vector is how Mat_river's is still two rounds stale.
	_aim_clouds_at_sun.call_deferred()


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
	spec.chimneys = 1 + (1 if rng.randf() < 0.35 else 0)
	spec.lit_fraction = rng.randf_range(0.10, 0.28)
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

	# Accumulated delta, NOT Time.get_ticks_msec(). It still approximates the
	# water shader's TIME closely enough that hulls ride the waves the river
	# surface is showing, and unlike the wall clock it is identical on every run
	# — which is what lets tools/harness.py gate captures per pixel. river_life.gd
	# integrates the same delta, so the two decor sets stay locked to each other.
	_decor_time += delta
	var t := _decor_time
	for i in _rabelos.size():
		var boat := _rabelos[i]
		var wave := sin((boat.position.x + t * 0.5) * 0.18) + cos((boat.position.z + t * 0.4) * 0.234)
		boat.position.y = -14.75 + wave * 0.35
		boat.rotation.z = sin(t * 0.6 + float(i) * 2.1) * 0.04


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

## Fair-weather cumulus over the gorge.
##
## Round 1's finding, in full: "placeholder ellipsoid meshes — hard opaque
## silhouettes, visible mesh-intersection seams, khaki-brown undersides, hard-edged
## white caps, and two copy-pasted clusters at identical size and tilt. They occupy
## the top quarter of every wide shot." Five defects, and they split into two causes.
##
## Four of the five were the MATERIAL, and specifically the fact that it was an opaque
## StandardMaterial3D at all. Everything that pass tried — retinting cream to white,
## adding a plaster normal, taking it back off again, dropping the tile to 5.5 m — was
## a search inside a category that could not contain the answer, because an opaque
## Lambert solid necessarily has a one-pixel silhouette, necessarily shows its own
## interior where two spheres cross, and necessarily takes its underside from whatever
## ambient is around, which was warm enough to land in khaki. That is now
## assets/shaders/soft_cloud.gdshader: transparent, no depth write, alpha falling to
## zero at the limb, and an underside explicitly lit by the sky rather than by the
## arena. The seams and the hard edges cannot come back, because there is no depth
## buffer entry to cut with and no coverage at the limb to step from.
##
## The fifth was the GEOMETRY, and this function owns it. Nine clusters, all built
## from the same 4-6 puffs at the same 1.0 x 0.6 x 1.0 flattening with no rotation
## anywhere, read as one object stamped twice — which is exactly what the critics
## reported seeing. What varies now: cluster count, per-cluster yaw, per-cluster
## three-axis stretch, per-puff yaw and roll, per-puff three-axis stretch, and the
## number of puffs. Nothing in the field is a copy of anything else in it.
##
## The whole field also moved: from y 34-58 / z -70..-30 out to y 58-104 /
## z -210..-70. At the old range a 4 m puff scaled 2.2 subtended as much of shot 07 as
## a Ribeira house did, which is why they read as objects hovering over the river
## rather than as weather. Out there they are also behind 25-45% of aerial
## perspective, which is what puts them in the same atmosphere as everything else.
##
## Every number comes off one seeded RNG in a fixed order, so the field is identical
## on every run — the capture gate depends on it.
func _build_clouds() -> void:
	_cloud_material = ShaderMaterial.new()
	_cloud_material.shader = CloudShader

	var rng := RandomNumberGenerator.new()
	rng.seed = 90210

	var holder := Node3D.new()
	holder.name = "Clouds"
	add_child(holder)

	for i in CLOUD_COUNT:
		var cloud := Node3D.new()
		cloud.name = "Cloud%d" % i
		cloud.position = Vector3(
			rng.randf_range(CLOUD_WRAP_MIN, CLOUD_WRAP_MAX),
			rng.randf_range(CLOUD_Y.x, CLOUD_Y.y),
			rng.randf_range(CLOUD_Z.x, CLOUD_Z.y)
		)
		cloud.rotation.y = rng.randf_range(0.0, TAU)
		# Non-uniform, so no two clusters share a proportion. Cumulus are wider than
		# they are deep and much wider than they are tall.
		cloud.scale = Vector3(
			rng.randf_range(1.4, 3.1),
			rng.randf_range(0.9, 1.6),
			rng.randf_range(1.1, 2.4)
		)
		holder.add_child(cloud)
		_build_cloud_puffs(cloud, rng)
		_clouds.append(cloud)


## One cluster. Puffs are laid along a shallow arc with a FLAT BASE — every puff's
## centre is lifted by enough of its own radius that none of them hangs below the
## cluster's base plane. That flat base is the single most recognisable thing about
## fair-weather cumulus and the old spherical blobs had none of it.
func _build_cloud_puffs(cloud: Node3D, rng: RandomNumberGenerator) -> void:
	var count := rng.randi_range(5, 9)
	var span := rng.randf_range(5.0, 9.0)
	for p in count:
		# Position along the cluster, -1 to +1, with the tallest puffs near the middle
		# so the silhouette rises to a crown instead of being a level sausage.
		var u := (float(p) + rng.randf_range(0.15, 0.85)) / float(count) * 2.0 - 1.0
		var crown := 1.0 - u * u
		var radius := rng.randf_range(2.2, 3.4) * (0.62 + 0.55 * crown)

		var puff := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = radius
		mesh.height = radius * 2.0
		# 16 x 8 rather than 12 x 6: the alpha falls off as |dot(normal, view)|, so a
		# coarse sphere shows its facets in the fade rather than only in the shading.
		mesh.radial_segments = 16
		mesh.rings = 8
		puff.mesh = mesh
		puff.material_override = _cloud_material
		# Transparent, unshaded, and 100 m up. It has no business in a shadow map or
		# in the SDFGI voxelisation; LightingRig excludes the group from GI as well.
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		puff.gi_mode = GeometryInstance3D.GI_MODE_DISABLED

		var squash := rng.randf_range(0.48, 0.68)
		puff.position = Vector3(
			u * span,
			radius * squash * rng.randf_range(0.55, 0.95),
			rng.randf_range(-2.2, 2.2)
		)
		puff.scale = Vector3(rng.randf_range(0.9, 1.25), squash, rng.randf_range(0.85, 1.15))
		puff.rotation = Vector3(
			rng.randf_range(-0.12, 0.12),
			rng.randf_range(0.0, TAU),
			rng.randf_range(-0.18, 0.18)
		)
		cloud.add_child(puff)


## Point the cloud shader at the scene's real key light.
##
## Deferred out of _ready() because SunLight is a sibling of the arena root and is not
## resolvable while this subtree is still being built. Searched by "brightest
## shadow-casting DirectionalLight3D" for the same reason LightingRig searches that
## way one node over: matching on the node name would also match the three fills it
## spawns, and matching on get_tree().current_scene breaks for anything that loads the
## arena on its own, which the capture harness does.
##
## If it finds nothing the shader keeps its authored default, which is the correct
## vector at the time of writing — so a missing sun degrades to a stale sun rather
## than to a black sky, and the probe is what catches the staleness.
func _aim_clouds_at_sun() -> void:
	if _cloud_material == null:
		return
	var sun := _find_sun()
	if sun == null:
		push_warning("SkyBackground: no shadow-casting DirectionalLight3D; clouds keep the shader default.")
		return
	_cloud_material.set_shader_parameter("sun_direction", sun.global_transform.basis.z.normalized())
	# The cap takes the key's own colour, so a re-keyed sun drags the clouds with it
	# instead of leaving them lit by a sun that is no longer there. Held at 0.97 of
	# full: nothing diffuse reflects 100%, and a cap at 1.0 clips through the grade
	# before the sun disk does.
	var c := sun.light_color
	_cloud_material.set_shader_parameter("sun_color", Color(c.r * 0.97, c.g * 0.97, c.b * 0.97))


func _find_sun() -> DirectionalLight3D:
	var root: Node = self
	while root.get_parent() != null:
		root = root.get_parent()
	return _brightest_shadow_caster(root, null)


func _brightest_shadow_caster(node: Node, best: DirectionalLight3D) -> DirectionalLight3D:
	var light := node as DirectionalLight3D
	if light != null and light.shadow_enabled:
		if best == null or light.light_energy > best.light_energy:
			best = light
	for child in node.get_children():
		best = _brightest_shadow_caster(child, best)
	return best
