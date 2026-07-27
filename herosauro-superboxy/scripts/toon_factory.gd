class_name ToonFactory
extends RefCounted
## Central factory for every material the procedurally-built world uses.
##
## The name is a fossil: this used to hand out flat cel-shaded ShaderMaterials
## with an inverted-hull outline. It now hands out stylised-realistic PBR
## StandardMaterial3Ds instead — but ~40 call sites across the world, sky and fx
## scripts spell it `ToonFactory`, so the class name and the solid()/glow()
## signatures stayed put rather than churn every one of them.
##
## Two things callers must know:
##
## 1. Materials are CACHED AND SHARED by parameter set. Two hundred Ribeira
##    facades in seven palette colours collapse onto seven materials, which is
##    what lets the renderer batch them instead of issuing a draw call each.
##    Anything that mutates a material per instance (hit flash, fade-out tween)
##    MUST call .duplicate() on the result first.
##
## 2. The scenery is raw BoxMesh / PrismMesh / SphereMesh. Their 0..1 UVs would
##    smear one texture tile across a 100 m bridge deck, so every textured helper
##    maps triplanar in *object* space at a real-world tile size. Object space,
##    not world space, so a moving prop (a lobbed rock, a bobbing rabelo) doesn't
##    swim through its own texture.
##
## Detail maps live in res://assets/textures/ as NoiseTexture2D descriptors —
## no bitmaps in the repo. See generate_detail_maps.gd there for the recipes.

# --- Surfaces ---------------------------------------------------------------

## Which detail map set a material wears. FLAT means "no textures at all", which
## is right for clouds, gull wings and anything read at a distance where a
## detail normal is just shimmer.
enum Surface { FLAT, GRANITE, IRON, COBBLE, PLASTER, TERRACOTTA, WOOD }

const _NORMAL_MAPS := {
	Surface.GRANITE: preload("res://assets/textures/detail_granite_normal.tres"),
	Surface.IRON: preload("res://assets/textures/detail_iron_normal.tres"),
	Surface.COBBLE: preload("res://assets/textures/detail_cobble_normal.tres"),
	Surface.PLASTER: preload("res://assets/textures/detail_plaster_normal.tres"),
	Surface.TERRACOTTA: preload("res://assets/textures/detail_terracotta_normal.tres"),
	Surface.WOOD: preload("res://assets/textures/detail_wood_normal.tres"),
}

## R = roughness multiplier, G = ambient occlusion. One texture, two channels,
## because triplanar costs three taps per map and we sample it twice either way.
const _MASK_MAPS := {
	Surface.GRANITE: preload("res://assets/textures/detail_granite_mask.tres"),
	Surface.IRON: preload("res://assets/textures/detail_iron_mask.tres"),
	Surface.COBBLE: preload("res://assets/textures/detail_cobble_mask.tres"),
	Surface.PLASTER: preload("res://assets/textures/detail_plaster_mask.tres"),
	Surface.TERRACOTTA: preload("res://assets/textures/detail_terracotta_mask.tres"),
	Surface.WOOD: preload("res://assets/textures/detail_wood_mask.tres"),
}

# --- Palette ----------------------------------------------------------------
# Defaults so a caller that just wants "some granite" can write ToonFactory.stone().

const STONE_GREY := Color(0.56, 0.54, 0.50)
const IRON_GREY := Color(0.36, 0.38, 0.42)
const COBBLE_GREY := Color(0.62, 0.60, 0.56)
const PLASTER_CREAM := Color(0.88, 0.85, 0.78)
const TERRACOTTA_RED := Color(0.62, 0.29, 0.21)
const WOOD_BROWN := Color(0.36, 0.24, 0.14)
const CLOTH_LINEN := Color(0.93, 0.89, 0.79)
const AZULEJO_BLUE := Color(0.18, 0.38, 0.66)
const GLASS_TINT := Color(0.72, 0.82, 0.86)

# --- Shared look ------------------------------------------------------------

## A little Fresnel rim on everything. It is the one deliberate survivor of the
## toon pass: it keeps silhouettes reading against the hazy golden-hour sky now
## that the hard black outline is gone, without costing a second draw call.
const RIM_AMOUNT := 0.22
const RIM_TINT := 0.45
const DEFAULT_ROUGHNESS := 0.80

static var _cache: Dictionary = {}
static var _derived_normals: Dictionary = {}


# --- Legacy API -------------------------------------------------------------

## A plain untextured PBR surface — the general-purpose fallback.
##
## `_legacy_outline_width` is the dead cel-shader's outline thickness. It is
## ignored and only survives so the pre-PBR call sites keep compiling; new code
## should skip past it and set `roughness` / `metallic`, or reach for one of the
## named material helpers below, which come with detail maps.
static func solid(color: Color, _legacy_outline_width: float = 0.0,
		roughness: float = DEFAULT_ROUGHNESS, metallic: float = 0.0) -> StandardMaterial3D:
	return build(color, Surface.FLAT, roughness, metallic)


## An emissive surface — the Dino Energy orb, lamp globes, lit windows.
##
## `energy` now drives emission_energy_multiplier; under Forward+'s HDR buffer
## values above ~1.5 actually bloom instead of just clipping to white.
## `_legacy_outline_width` is ignored, as in solid().
static func glow(color: Color, energy: float = 3.0, _legacy_outline_width: float = 0.0,
		roughness: float = 0.42) -> StandardMaterial3D:
	return build(color, Surface.FLAT, roughness, 0.0, 1.0, 1.0, 0.0, color, energy)


# --- Material helpers -------------------------------------------------------

## Granite: piers, quay walls, the Clérigos shaft, thrown masonry.
static func stone(color: Color = STONE_GREY, tile_meters: float = 2.4) -> StandardMaterial3D:
	return build(color, Surface.GRANITE, 0.92, 0.0, tile_meters, 1.0, 0.35)


## Cobbled setts: the Ribeira cais, any paved promenade.
static func cobblestone(color: Color = COBBLE_GREY, tile_meters: float = 1.4) -> StandardMaterial3D:
	return build(color, Surface.COBBLE, 0.88, 0.0, tile_meters, 1.2, 0.45)


## Painted / weathered structural steel: the arch, lattice, rails, lampposts.
## Semi-metallic so it picks up the sunset sky instead of reading as grey card.
static func iron(color: Color = IRON_GREY, tile_meters: float = 1.6,
		metallic: float = 0.55, roughness: float = 0.62) -> StandardMaterial3D:
	return build(color, Surface.IRON, roughness, metallic, tile_meters, 0.9, 0.25)


## Limewashed render — Ribeira facades, lodge walls, chapel body.
static func plaster(color: Color = PLASTER_CREAM, tile_meters: float = 2.0) -> StandardMaterial3D:
	return build(color, Surface.PLASTER, 0.94, 0.0, tile_meters, 0.7, 0.20)


## Clay barrel roof tiles.
static func terracotta(color: Color = TERRACOTTA_RED, tile_meters: float = 0.85) -> StandardMaterial3D:
	return build(color, Surface.TERRACOTTA, 0.86, 0.0, tile_meters, 1.0, 0.35)


## Timber: rabelo hulls, masts, barrels, decking.
static func wood(color: Color = WOOD_BROWN, tile_meters: float = 1.1) -> StandardMaterial3D:
	return build(color, Surface.WOOD, 0.80, 0.0, tile_meters, 0.8, 0.25)


## Woven cloth: sails, awnings, banners. Fully rough, no spec highlight to speak
## of — the plaster map at a tight tile stands in for the weave.
static func cloth(color: Color = CLOTH_LINEN, tile_meters: float = 0.45) -> StandardMaterial3D:
	return build(color, Surface.PLASTER, 0.98, 0.0, tile_meters, 0.5, 0.15)


## Glazed ceramic — the azulejo panels. Wet-looking: that hard specular kick off
## a tile front is the whole reason azulejos read as Porto and not as blue paint.
static func ceramic(color: Color = AZULEJO_BLUE, tile_meters: float = 0.5) -> StandardMaterial3D:
	return build(color, Surface.TERRACOTTA, 0.14, 0.0, tile_meters, 0.25, 0.10)


## Window / lantern glazing. Transparent, so it lands in the alpha pass — keep
## the panes small and few.
static func glass(color: Color = GLASS_TINT, alpha: float = 0.28) -> StandardMaterial3D:
	return build(color, Surface.FLAT, 0.04, 0.0, 1.0, 1.0, 0.0, Color.BLACK, 0.0, alpha)


## Still water — puddles, troughs, the harbour inside a lock gate. The moving
## Douro surface is res://assets/shaders/water_wave.gdshader, not this.
static func water(color: Color = Color(0.16, 0.34, 0.42), alpha: float = 0.78) -> StandardMaterial3D:
	return build(color, Surface.PLASTER, 0.06, 0.0, 6.0, 0.35, 0.0, Color.BLACK, 0.0, alpha)


# --- Builder ----------------------------------------------------------------

## The one place a StandardMaterial3D is actually constructed. Public so a
## geometry stream can dial in something the named helpers don't cover, but
## prefer the helpers: fewer distinct parameter sets means fewer materials means
## fewer draw calls.
static func build(color: Color, surface: Surface = Surface.FLAT,
		roughness: float = DEFAULT_ROUGHNESS, metallic: float = 0.0,
		tile_meters: float = 2.0, normal_scale: float = 1.0, ao_strength: float = 0.0,
		emission: Color = Color.BLACK, emission_energy: float = 0.0,
		alpha: float = 1.0) -> StandardMaterial3D:
	var key := "%s|%d|%.3f|%.3f|%.3f|%.3f|%.3f|%s|%.3f|%.3f" % [
		color.to_html(false), surface, roughness, metallic, tile_meters,
		normal_scale, ao_strength, emission.to_html(false), emission_energy, alpha,
	]
	var cached: StandardMaterial3D = _cache.get(key)
	if cached != null:
		return cached

	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	m.roughness = roughness
	m.metallic = metallic
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.rim_enabled = true
	m.rim = RIM_AMOUNT
	m.rim_tint = RIM_TINT

	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED

	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = emission_energy

	if surface != Surface.FLAT:
		# Triplanar in object space: consistent texel density on a 100 m deck and
		# on a 0.2 m railing post, with no UVs authored on either.
		m.uv1_triplanar = true
		m.uv1_scale = Vector3.ONE / maxf(tile_meters, 0.01)
		m.normal_enabled = true
		m.normal_scale = normal_scale
		m.normal_texture = _NORMAL_MAPS[surface]

		var mask: Texture2D = _MASK_MAPS[surface]
		m.roughness_texture = mask
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		if ao_strength > 0.0:
			m.ao_enabled = true
			m.ao_texture = mask
			m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
			m.ao_light_affect = ao_strength

	_cache[key] = m
	return m


# --- Imported model upgrade -------------------------------------------------

## Retro-fit PBR onto an instantiated .glb.
##
## The four character models ship one baked-albedo texture each and nothing
## else — no normal, roughness, metallic or AO — so under Forward+ they render
## as flat plastic. This walks the instance and gives every StandardMaterial3D
## surface a sane dielectric response plus, optionally, a normal map derived
## from the albedo's luminance. That derived map is a cheat: it bumps whatever
## the texture *painted*, not real geometry, so keep `normal_scale` low.
##
## Composes with per-instance material tricks in either order. If a surface
## already has an override (e.g. Adamastor's hit-flash duplicates) it is
## upgraded in place; otherwise the mesh material is duplicated into a fresh
## override so the shared imported resource is never touched.
##
## Returns the number of surfaces upgraded.
static func upgrade_glb_materials(root: Node, roughness: float = 0.68,
		metallic: float = 0.0, normal_scale: float = 0.45,
		derive_normals: bool = true) -> int:
	if root == null:
		return 0
	var count := 0
	for mi in _mesh_instances(root):
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var mat := _instance_material(mi, s)
			if mat == null:
				continue
			mat.roughness = roughness
			mat.metallic = metallic
			mat.rim_enabled = true
			mat.rim = RIM_AMOUNT
			mat.rim_tint = RIM_TINT
			# Baked-in shading is already in the albedo; a second AO pass would
			# just crush it, so only the normal is synthesised.
			if derive_normals and mat.albedo_texture != null and not mat.normal_enabled:
				var nrm := _normal_from_albedo(mat.albedo_texture)
				if nrm != null:
					mat.normal_enabled = true
					mat.normal_texture = nrm
					mat.normal_scale = normal_scale
			count += 1
	return count


static func _mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		found.append(node as MeshInstance3D)
	for child in node.get_children():
		found.append_array(_mesh_instances(child))
	return found


## The material to edit for one surface: an existing instance override if there
## is one, otherwise a fresh duplicate installed as the override.
static func _instance_material(mi: MeshInstance3D, surface_idx: int) -> StandardMaterial3D:
	var existing := mi.get_surface_override_material(surface_idx)
	if existing is StandardMaterial3D:
		return existing as StandardMaterial3D
	var base := mi.get_active_material(surface_idx)
	if not (base is StandardMaterial3D):
		return null   # a ShaderMaterial here is deliberate; leave it alone
	var dup: StandardMaterial3D = (base as StandardMaterial3D).duplicate()
	mi.set_surface_override_material(surface_idx, dup)
	return dup


## Central-difference the albedo's luminance into a tangent-space normal map.
##
## Downsampled hard on purpose: the albedo's fine detail is painted brush noise,
## and lifting it into geometry at full resolution reads as sandpaper. What we
## want is only the big strokes — seams, straps, the line between scale plates.
## Results are cached per source texture, since all four models share the pattern
## of one atlas per character.
static func _normal_from_albedo(src: Texture2D, size: int = 128,
		relief: float = 0.025) -> ImageTexture:
	var cache_key := src.get_instance_id()
	if _derived_normals.has(cache_key):
		return _derived_normals[cache_key]

	var img: Image = src.get_image()
	if img == null:
		return null
	img = img.duplicate()
	if img.is_compressed() and img.decompress() != OK:
		return null
	# Trilinear, not Lanczos: these atlases are 1024², and Lanczos spends 30 ms on
	# an 8x downscale to land within 1% of what the mip chain gives in half a ms.
	img.resize(size, size, Image.INTERPOLATE_TRILINEAR)
	img.convert(Image.FORMAT_RGBA8)

	# Flatten to a luminance height field up front. Going through the raw byte
	# buffer instead of get_pixel()/set_pixel() takes this from ~35 ms to a few:
	# it runs once per character at load, but four of those is a visible hitch.
	var src_bytes := img.get_data()
	var count := size * size
	var height := PackedFloat32Array()
	height.resize(count)
	for i in count:
		var o := i * 4
		height[i] = (0.2126 * float(src_bytes[o])
			+ 0.7152 * float(src_bytes[o + 1])
			+ 0.0722 * float(src_bytes[o + 2])) / 255.0

	# Tuned so a typical luminance step tilts the normal ~10 degrees. Higher and
	# every painted shadow turns into a ridge.
	var strength := float(size) * relief
	var out_bytes := PackedByteArray()
	out_bytes.resize(count * 4)
	var last := size - 1
	for y in size:
		var row := y * size
		# Clamp, don't wrap: these are UV atlases, not tiling textures, so the
		# opposite edge is unrelated art.
		var row_up := maxi(y - 1, 0) * size
		var row_dn := mini(y + 1, last) * size
		for x in size:
			var dx := height[row + mini(x + 1, last)] - height[row + maxi(x - 1, 0)]
			var dy := height[row_dn + x] - height[row_up + x]
			var n := Vector3(-dx * strength, -dy * strength, 1.0).normalized()
			var o := (row + x) * 4
			out_bytes[o] = int(clampf(n.x * 0.5 + 0.5, 0.0, 1.0) * 255.0)
			out_bytes[o + 1] = int(clampf(n.y * 0.5 + 0.5, 0.0, 1.0) * 255.0)
			out_bytes[o + 2] = int(clampf(n.z * 0.5 + 0.5, 0.0, 1.0) * 255.0)
			out_bytes[o + 3] = 255

	var out := Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, out_bytes)
	out.generate_mipmaps()
	var tex := ImageTexture.create_from_image(out)
	_derived_normals[cache_key] = tex
	return tex
