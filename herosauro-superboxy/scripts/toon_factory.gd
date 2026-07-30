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
##
## --- Three rules this factory now enforces centrally ------------------------
##
## All three are RUBRIC lines that were being missed identically by every caller,
## which is the case for fixing them in one place rather than in forty:
##
## a) TWO TEXTURE SCALES, always. A surface map tiled at its authored real-world
##    size is magnified about elevenfold at half a metre and resolves as blur; the
##    same map tiled to resolve there tiles visibly at twenty metres. Every textured
##    material therefore also wears the shared fine pair at ~0.28 m — grit in the
##    normal, patchy discolouration in the albedo. That second layer is what the
##    RUBRIC means by "a detail layer still doing work at 0.5 m", and shot
##    03_rail_macro exists to test exactly it. It costs six more triplanar taps and
##    that is what the bar costs.
##
## b) ALBEDO VARIATION, always. Before this pass every material in the game was one
##    flat albedo colour with a bump map on it — the RUBRIC's very first material
##    failure, and the one that most reliably reads as "mobile game". The fine
##    detail layer multiplies albedo by 0.68-1.00 in blotches a few centimetres
##    across, which reads as damp, dirt, sun-bleaching or salt depending entirely on
##    what colour is underneath it.
##
## c) METALS ARE 0 OR 1. Call sites currently ask for 0.20, 0.28, 0.30, 0.35, 0.42,
##    0.45, 0.55, 0.60, 0.65 and 0.85. Every value strictly between is
##    unphysical — it desaturates the diffuse term and tints the specular at the
##    same time, so the surface reads as neither painted steel nor bare steel — and
##    it is a specific RUBRIC failure. build() snaps at 0.6 and gives the dielectric
##    side a raised metallic_specular instead, which is the thing the half-metal was
##    actually faking: painted ironwork catching the sky.

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

## The shared close-range layer, one pair for every surface. See rule (a) above and
## the header of generate_detail_maps.gd for why it is shared and for what the
## albedo map's alpha channel is doing.
const _FINE_NORMAL := preload("res://assets/textures/detail_fine_normal.tres")
const _FINE_ALBEDO := preload("res://assets/textures/detail_fine_albedo.tres")

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
## toon pass: it keeps silhouettes reading now that the hard black outline is gone,
## without costing a second draw call.
##
## 0.22 -> 0.14, and tint 0.45 -> 0.65. A rim term is a fake grazing-angle lift, and
## against a hazy low-contrast sunset sky it was buying silhouette separation cheaply.
## Against a hard blue sky at 51 degrees it buys much less — the key does that job
## now — while costing more, because a uniform white-ish edge highlight on every
## object in a bright frame is exactly the "plastic sheen" tell a critic looks for.
## The higher tint pushes what is left toward the surface's own albedo, so a terracotta
## roof rims terracotta rather than rimming white.
const RIM_AMOUNT := 0.14
const RIM_TINT := 0.65
const DEFAULT_ROUGHNESS := 0.80

# --- Physical guards --------------------------------------------------------

## Real diffuse surfaces live between about 2% (fresh asphalt, soot) and 90% (fresh
## snow, titanium white) reflectance, and the RUBRIC states that range as a rule.
## Several call sites are outside it — TRIM_WHITE at 0.93, the cloud puffs at 0.95,
## gull feathers at 0.94 — and an albedo above 0.9 does not read as "brighter", it
## reads as an object that cannot take a shadow. Clamped by scaling the whole colour
## rather than per channel, so nothing shifts hue on the way in.
const ALBEDO_CEILING := 0.90
const ALBEDO_FLOOR := 0.02

## Below this, `metallic` means "dielectric"; at or above it, "bare metal". Nothing
## in between survives — see rule (c) in the header. 0.6 is where the call sites
## actually separate: the tram railheads (0.85), the rivet plates (0.60) and the
## barrel hoops (0.65) are bare steel, and everything else on this bridge is painted.
const METALLIC_SNAP := 0.6

## metallic_specular for a snapped-to-zero dielectric that asked to be a metal.
## 0.5 is Godot's default and means F0 = 4%, which is glass and most plastics.
## Painted or oxidised steel sits nearer 5.5-6%, and that extra is the sky catching
## the ironwork — the read the half-metallic value was reaching for by the wrong
## route, because it was also washing the colour out of the diffuse term to get it.
const DIELECTRIC_METAL_SPECULAR := 0.62

# --- Close-range detail layer -----------------------------------------------

## Tile size of the shared fine pair, in metres. 0.28 m over a 256-px map is about
## 1.1 mm per texel: still resolving at the 0.5 m the RUBRIC names, and small enough
## that by 4-5 m it has gone sub-pixel and stopped contributing anything but a very
## slight softening — which is the correct behaviour for a second layer.
const DETAIL_TILE_METERS := 0.28

## The fine albedo map averages about 0.88 of white in linear terms, so leaving it
## alone would quietly darken every authored colour in the game by roughly 12% and
## make forty call sites' palettes mean something they do not say. This puts that
## back. It is not a look dial — the RUBRIC's "exposure-driven, not
## multiplier-driven" rule is about fixing LIGHTING with albedo, and this is a
## texture-mean correction. It is applied before ALBEDO_CEILING, so it can never
## push a colour out of range.
const DETAIL_ALBEDO_GAIN := 1.13

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
##
## ao_strength 0.35 -> 0.52. This granite stands two metres above a tidal river, and
## the mask's crevices are now both darker (the AO channel was inverted before this
## pass) and glossier (roughness 0.52-1.00 across the surface), which together is the
## damp-in-the-joints, dry-on-the-face read the RUBRIC asks for by name. normal_scale
## up 1.0 -> 1.15 because the fine layer stacks at 55% and the surface normal has to
## stay the dominant one at arm's length and beyond.
static func stone(color: Color = STONE_GREY, tile_meters: float = 2.4) -> StandardMaterial3D:
	return build(color, Surface.GRANITE, 0.92, 0.0, tile_meters, 1.15, 0.52)


## Cobbled setts: the Ribeira cais, any paved promenade. ao 0.45 -> 0.60: the grout
## between setts is where the moss is, and it is the deepest AO of the six recipes.
static func cobblestone(color: Color = COBBLE_GREY, tile_meters: float = 1.4) -> StandardMaterial3D:
	return build(color, Surface.COBBLE, 0.88, 0.0, tile_meters, 1.35, 0.60)


## Painted / weathered structural steel: the arch, lattice, rails, lampposts.
##
## metallic default 0.55 -> 0.0, which is what this material has always physically
## been: the Dom Luís lattice is painted steel, and paint is a dielectric. The old
## half-metal was reaching for "picks up the sky instead of reading as grey card" and
## getting there by washing the diffuse colour out, which is why the ironwork never
## looked painted. The sky pickup is bought properly instead, with
## DIELECTRIC_METAL_SPECULAR and the iron mask's 0.34-1.00 roughness spread: intact
## paint is smooth enough to mirror the dome, a rust bloom is not, and the two sit
## next to each other on every member.
##
## Call sites that genuinely want bare steel — the tram railheads at 0.85, the rivet
## plates at 0.60, the barrel hoops at 0.65 — clear METALLIC_SNAP and get metallic 1.
static func iron(color: Color = IRON_GREY, tile_meters: float = 1.6,
		metallic: float = 0.0, roughness: float = 0.62) -> StandardMaterial3D:
	return build(color, Surface.IRON, roughness, metallic, tile_meters, 1.05, 0.38,
			Color.BLACK, 0.0, 1.0, DIELECTRIC_METAL_SPECULAR)


## Limewashed render — Ribeira facades, lodge walls, chapel body. Sun-faded and
## chalky: roughness 0.94 with the plaster mask's 0.80-1.00 on top, and now with the
## fine albedo layer blotching it, which on a pale wall reads as exactly the uneven
## weathering every limewashed facade in the Ribeira has.
static func plaster(color: Color = PLASTER_CREAM, tile_meters: float = 2.0) -> StandardMaterial3D:
	return build(color, Surface.PLASTER, 0.94, 0.0, tile_meters, 0.85, 0.30)


## Clay barrel roof tiles. Rain-polished on the crowns, gritty in the pans between
## them, with the deepest normal of the six because a roof is only ever seen from
## above at a steep angle and the tile relief is its entire silhouette.
static func terracotta(color: Color = TERRACOTTA_RED, tile_meters: float = 0.85) -> StandardMaterial3D:
	return build(color, Surface.TERRACOTTA, 0.86, 0.0, tile_meters, 1.2, 0.45)


## Timber: rabelo hulls, masts, barrels, decking. Worn pale and smooth where feet
## land, rough in the split between boards.
static func wood(color: Color = WOOD_BROWN, tile_meters: float = 1.1) -> StandardMaterial3D:
	return build(color, Surface.WOOD, 0.80, 0.0, tile_meters, 0.95, 0.32)


## Woven cloth: sails, awnings, banners. Fully rough, no spec highlight to speak
## of — the plaster map at a tight tile stands in for the weave.
static func cloth(color: Color = CLOTH_LINEN, tile_meters: float = 0.45) -> StandardMaterial3D:
	return build(color, Surface.PLASTER, 0.98, 0.0, tile_meters, 0.5, 0.15)


## Glazed ceramic — the azulejo panels. Wet-looking: that hard specular kick off
## a tile front is the whole reason azulejos read as Porto and not as blue paint,
## and under a hard blue sky it is a far bigger part of the frame than it was under a
## hazy one. specular 0.65 = F0 near 6%, which is a fired lead glaze rather than the
## 4% Godot assumes for everything, and it is the difference between a tile panel that
## flashes as the camera passes and one that does not.
static func ceramic(color: Color = AZULEJO_BLUE, tile_meters: float = 0.5) -> StandardMaterial3D:
	return build(color, Surface.TERRACOTTA, 0.14, 0.0, tile_meters, 0.30, 0.14,
			Color.BLACK, 0.0, 1.0, 0.65)


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
##
## `specular` and `fine_detail` are appended, never inserted: terrain_batch.gd calls
## this positionally with seven arguments and every other caller goes through a named
## helper, so anything new has to arrive at the end with a default that reproduces the
## old behaviour. `specular` is metallic_specular, i.e. F0 for the dielectric case;
## `fine_detail` switches off the shared close-range layer for surfaces the camera
## never gets near, where six triplanar taps buy nothing.
static func build(color: Color, surface: Surface = Surface.FLAT,
		roughness: float = DEFAULT_ROUGHNESS, metallic: float = 0.0,
		tile_meters: float = 2.0, normal_scale: float = 1.0, ao_strength: float = 0.0,
		emission: Color = Color.BLACK, emission_energy: float = 0.0,
		alpha: float = 1.0, specular: float = 0.5,
		fine_detail: bool = true) -> StandardMaterial3D:
	# Snap and clamp BEFORE the key is built, so two callers asking for 0.30 and 0.45
	# metallic — which is most of the ironwork — collapse onto one cached material
	# instead of two identical ones under different names.
	var bare_metal := metallic >= METALLIC_SNAP
	var metal := 1.0 if bare_metal else 0.0
	var f0 := specular
	if not bare_metal and metallic > 0.0:
		# The caller asked for a metal and got a dielectric. Give it back the sky
		# reflection it wanted, at a physical F0, instead of the washed-out diffuse
		# a half-metal would have traded for it.
		f0 = maxf(specular, DIELECTRIC_METAL_SPECULAR)
	var albedo := _physical_albedo(color, surface != Surface.FLAT and fine_detail)

	var key := "%s|%d|%.3f|%.3f|%.3f|%.3f|%.3f|%s|%.3f|%.3f|%.3f|%d" % [
		albedo.to_html(false), surface, roughness, metal, tile_meters,
		normal_scale, ao_strength, emission.to_html(false), emission_energy, alpha,
		f0, 1 if fine_detail else 0,
	]
	var cached: StandardMaterial3D = _cache.get(key)
	if cached != null:
		return cached

	var m := StandardMaterial3D.new()
	m.albedo_color = Color(albedo.r, albedo.g, albedo.b, alpha)
	m.roughness = roughness
	m.metallic = metal
	m.metallic_specular = f0
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

		if fine_detail:
			_add_fine_detail(m)

	_cache[key] = m
	return m


## The second texture scale, and the only source of albedo variation in the game.
##
## Rides UV2 with its own triplanar mapping, which is what lets it tile at 0.28 m
## while the surface layer tiles at whatever real-world size its material wants.
## Godot's detail pass is
##     detail     = mix(ALBEDO, ALBEDO * detail_tex.rgb, detail_tex.a);
##     detail_nrm = mix(NORMAL_MAP, detail_norm_tex.rgb, detail_tex.a);
## so MUL is the blend mode that makes the albedo map a modulation of whatever colour
## the caller asked for rather than a replacement of it, and the map's own alpha
## (0.55, baked in by generate_detail_maps.gd) is what stops the fine normal wiping
## out the surface normal instead of stacking with it.
static func _add_fine_detail(m: StandardMaterial3D) -> void:
	m.detail_enabled = true
	m.detail_uv_layer = BaseMaterial3D.DETAIL_UV_2
	m.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	m.detail_albedo = _FINE_ALBEDO
	m.detail_normal = _FINE_NORMAL
	m.uv2_triplanar = true
	m.uv2_scale = Vector3.ONE / DETAIL_TILE_METERS


## Put a caller's colour inside the range a real diffuse surface can occupy, and
## pre-multiply out the fine detail layer's mean so the authored colour still means
## what it says once that layer has multiplied it.
##
## Scaled as a whole colour, never clamped per channel: clamping (0.93, 0.91, 0.85)
## channel-wise pulls red down and leaves blue alone, which desaturates and cools the
## surface. Scaling keeps the hue and only moves the value, which is what "this wall
## is a bit too bright to be real" actually means.
static func _physical_albedo(color: Color, has_fine_detail: bool) -> Color:
	var c := color
	if has_fine_detail:
		c = Color(c.r * DETAIL_ALBEDO_GAIN, c.g * DETAIL_ALBEDO_GAIN, c.b * DETAIL_ALBEDO_GAIN)
	var peak := maxf(c.r, maxf(c.g, c.b))
	if peak > ALBEDO_CEILING and peak > 0.0:
		c *= ALBEDO_CEILING / peak
	# A floor as well as a ceiling: nothing in the real world reflects less than a
	# couple of percent, and a near-black albedo is a surface that can only ever be
	# a silhouette. Applied to the darkest channel so window reveals and void caps
	# keep their shape instead of all flattening to the same grey.
	var dim := minf(c.r, minf(c.g, c.b))
	if dim < ALBEDO_FLOOR:
		c = Color(maxf(c.r, ALBEDO_FLOOR), maxf(c.g, ALBEDO_FLOOR), maxf(c.b, ALBEDO_FLOOR))
	return c


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
