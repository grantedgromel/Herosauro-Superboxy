extends Node3D
## CityBackdrop: the photogrammetry Porto that closes the far end of the gorge.
##
## `assets/models/backdrop/porto_backdrop.glb` is a 426,571-triangle aerial scan of
## the real district around the Ponte de Dom Luís I — Eduardo Soethe, CC BY 4.0.
## See `assets/models/backdrop/ATTRIBUTION.md`: the credit is a licence condition,
## not a courtesy, and it has to reach the game's credits screen.
##
## It is one draw call over one 1024x1024 baked-albedo atlas, and it only works at
## distance. At eye level it is melted wax; at two hundred metres the arch and the
## Ribeira hillside are unmistakable. Everything below is in service of keeping it
## at that distance, off the player, and out of the lighting.
##
## The scan is loaded by path at runtime rather than referenced as an ext_resource
## in the .tscn. That is deliberate: the Web export preset already carries
## `exclude_filter="assets/models/backdrop/*"`, and a scene holding a hard
## dependency on a stripped file errors on load. By string it simply is not there,
## and `_should_build()` says so before anything asks for it.

# --- Where the scan goes, and why -------------------------------------------
#
# Every figure below was measured off the mesh (area-weighted triangle sampling),
# not eyeballed. The imported node-space AABB is
#   position (-27.541, -10.889, -72.935)  size (91.185, 29.927, 71.936)
# and inside it:
#
#   upper deck slab   y = +10.45, a 2.20-wide ribbon whose principal axis in XZ is
#                     (0.9729, -0.2315) -> the bridge runs 13.382 deg off world +X.
#   river surface     y = -2.13 (p99.9 = -1.49). Dead flat and untextured, which is
#                     why it has to end up underneath ours.
#   river channel     x in [-1, +39] once the deck is rotated onto +X: 40 units
#                     wide, running along Z for the model's whole 90-unit depth.
#   capture skirt     the curtain of stretched triangles hanging off every capture
#                     boundary, down to y = -10.889. Pure garbage; must be drowned.
#
# Two independent checks put one scan unit at 5.0 real metres: the arch spans 33.7
# units against the real 172 m, and deck-to-water is 12.6 units against the real
# ~63 m. So the atlas carries 6.5 texels per scan unit — measured directly as
# sqrt(uv_area * 1024^2 / surface_area), and unusually tight: p05 3.3, p95 6.8.
#
# YAW -6.382 deg = -13.382 (alignment) + 7.000 (deliberate).
#   -13.382 puts the scan's deck on world +X, which necessarily also puts its river
#   on world Z. That is our axis too: our banks are the masses at |x| >= 50 and our
#   channel runs along Z, so the scan continues our reach of the Douro rather than
#   sitting behind it as an unrelated ridge. The +7 then does three jobs at once —
#   it makes the far bridge cross the gorge obliquely instead of parading as a twin
#   of the one the player is standing on (Maria Pia and Infante are not parallel to
#   Luís I either), it bends the reach the way the Douro actually bends below Porto,
#   and it swings the scan's Porto bank out to x = -110 so it covers the end of the
#   procedural bank at x = -106 instead of leaving a wedge of sky in the joint.
#
# SCALE 3.2. The scan's 40-unit channel becomes 128 against our 100 (quay to quay,
#   x = +-50). Overshooting is correct, not sloppy: the scan starts 80 units further
#   down the river, so perspective already pulls its banks inside our quay lines on
#   screen — its leading edge sits at x = +-63.5, z = -132, which projects to 63/132
#   against the near quay's 50/51. Matched 1:1 in plan, the gorge would read as
#   *narrowing* rather than opening out. 3.2 also keeps
#   the atlas honest: 1.8 screen pixels per texel at 1080p (p90 2.2, p99 2.5), i.e.
#   barely magnified, and minified outright at 720p.
#
# HEIGHT pinned so scan y = -1.0 lands on our river surface at y = -15. That drowns
#   the scan's own river plane to y = -18.6, comfortably clear of our wave troughs at
#   -15.35, and drowns the skirt to -46.6. 28.7% of the scan's surface area ends up
#   below our waterline and is never drawn against anything but water — which is also
#   why the River plane below had to grow to cover the scan's whole footprint. What is
#   left standing is a 3.2-unit quay, against our own promenade at y = -9.9.
#
# RESULT world AABB (-131.8, -46.6, -389.9) .. (153.9, 49.0, -130.8). Nearest
#   surface 168 units from the deck centre, farthest 407. All of it past
#   fog_depth_begin (45) and most past fog_depth_end (280), so the environment
#   blends it 35-50% into the sky. That blend is not decoration — see below, it is
#   where the contrast reduction the baked-in sunlight needs actually comes from.

const SCAN_PATH := "res://assets/models/backdrop/porto_backdrop.glb"

## Node-space AABB size of the mesh as imported. Checked at runtime: if the .glb is
## ever re-exported or `nodes/root_scale` moves off 1.0, every number above silently
## becomes wrong, and a warning is far better than a backdrop quietly in the wrong
## place.
const SCAN_NATIVE_SIZE := Vector3(91.185, 29.927, 71.936)
const SCAN_SIZE_TOLERANCE := 0.02

@export var scan_yaw_degrees: float = -6.382
@export var scan_scale: float = 3.2
## World-space. The scan is placed with `global_transform`, so this node may sit
## anywhere in the tree, but the numbers only mean anything against the arena's
## origin — a parent that translates the whole arena would need these moved with it.
@export var scan_origin: Vector3 = Vector3(-63.467, -11.8, -150.0)

# --- Light reconciliation ----------------------------------------------------
#
# The atlas is aerial photography. The sunlight is already in it, complete with the
# capture's own midday shadows painted onto every north face. Lighting it again
# under our 5.5-degree golden-hour key would double every one of them, and doing it
# through photogrammetry normals — which are noisy at the scale of a single roof
# tile — would turn a hard low sun into speckle.
#
# So: unshaded. Standard practice for a matte-painting backdrop, and it buys two
# more things here. Emission and specular vanish, so the scan cannot catch a rim it
# has no business catching; and back faces shade identically to front faces, which
# matters because photogrammetry shells have inconsistent winding and the source
# glTF asked for doubleSided.
#
# Fog still applies to unshaded materials (that is exactly why `disable_fog` exists
# as a separate flag), and fog is doing the real grading work: at 35-50% blend
# toward the horizon sky the photo's contrast is roughly halved and its blacks are
# lifted into warm haze. `albedo_tint` only handles what fog cannot — a modest trim
# and a warm bias to drag the capture's noon white balance toward the hour we are
# actually in. Note that a multiply cannot desaturate; the atlas's terracotta stays
# as saturated as it was shot, and fog is the only thing pulling it back.
@export var unshaded: bool = true
## Multiplied over the atlas. Authored in sRGB — Godot converts it to linear on the
## way to the shader, so the effective linear multiplier is ~(0.89, 0.83, 0.73).
@export var albedo_tint: Color = Color(0.95, 0.92, 0.87)

## Godot's coarse LODs come from meshoptimizer's sloppy simplifier, which is exactly
## the wrong tool for a welded patchwork of 239 photogrammetry chunks carrying one
## thin iron arch. Biasing hard toward the finer levels keeps the silhouette the
## whole asset exists for. It is still one draw call, and it is desktop-only.
@export var lod_bias: float = 3.0

## 0 disables distance culling, which is the right default: the camera is bolted to
## a 100-unit deck and the scan never leaves the 168-407 unit band, so a range would
## either never fire or never stop firing. Left exposed because a pull-back camera
## would change that — and if it is ever switched on it fades rather than pops.
@export var visibility_end: float = 0.0
@export var visibility_fade_length: float = 60.0

var _scan: Node3D


func _ready() -> void:
	if not _should_build():
		return
	var packed := load(SCAN_PATH) as PackedScene
	if packed == null:
		push_warning("CityBackdrop: %s exists but did not load as a PackedScene." % SCAN_PATH)
		return

	_scan = packed.instantiate() as Node3D
	if _scan == null:
		push_warning("CityBackdrop: %s did not instantiate as a Node3D." % SCAN_PATH)
		return
	_scan.name = "PortoScan"
	add_child(_scan)
	# Set globally, not locally: every constant above is a world coordinate derived
	# against the arena origin, so this stays correct wherever the node is parented.
	_scan.global_transform = Transform3D(
		Basis.from_euler(Vector3(0.0, deg_to_rad(scan_yaw_degrees), 0.0)).scaled(Vector3.ONE * scan_scale),
		scan_origin
	)

	_strip_collision(_scan)
	var mat := _build_backdrop_material()
	var native := AABB()
	var seen := false
	for entry in _geometry(_scan, Transform3D.IDENTITY):
		var geo: GeometryInstance3D = entry[0]
		_configure(geo, mat)
		var mesh_instance := geo as MeshInstance3D
		if mesh_instance != null and mesh_instance.mesh != null:
			var local: AABB = (entry[1] as Transform3D) * mesh_instance.mesh.get_aabb()
			native = local if not seen else native.merge(local)
			seen = true
	if seen:
		_check_native_size(native.size)


# --- Gating ------------------------------------------------------------------

## Two independent reasons to skip, and the scene has to survive both.
##
## The renderer test is the web budget: 38 MB of source against a 7 MB pck, on the
## tier that was explicitly signed up for reduced fidelity. The procedural city in
## sky_background.gd carries the skyline there on its own.
##
## The existence test is the export filter. `exclude_filter` strips the whole
## backdrop directory from the Web preset, so on web the file is genuinely gone —
## and it may be stripped from other presets later. `ResourceLoader.exists()` is
## the only honest way to ask.
func _should_build() -> bool:
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		print_verbose("CityBackdrop: gl_compatibility renderer, procedural city only.")
		return false
	if not ResourceLoader.exists(SCAN_PATH):
		push_warning("CityBackdrop: %s is not in this build; procedural city only." % SCAN_PATH)
		return false
	return true


# --- Instance setup ----------------------------------------------------------

## Depth-first walk returning [GeometryInstance3D, transform relative to the scan
## root]. The current .glb imports as exactly one MeshInstance3D under one Node3D,
## but the transform has to accumulate anyway or the AABB check below would only be
## right by accident.
func _geometry(node: Node, accumulated: Transform3D) -> Array:
	var found: Array = []
	var here := accumulated
	var spatial := node as Node3D
	if spatial != null and spatial != _scan:
		here = accumulated * spatial.transform
	if node is GeometryInstance3D:
		found.append([node, here])
	for child in node.get_children():
		found.append_array(_geometry(child, here))
	return found


func _configure(geo: GeometryInstance3D, mat: StandardMaterial3D) -> void:
	# The albedo already contains the capture's own sun and shadows. A second,
	# real shadow on top darkens every surface twice.
	geo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 426k triangles of hollow shell across a 285x96x288 volume is the worst thing
	# SDFGI could be handed: it would eat most of the cascade budget to voxelise
	# geometry that is unlit and, being 168+ units out, bounces nothing onto the
	# deck. The importer already writes gi_mode = DISABLED; this is the guarantee.
	geo.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	geo.lod_bias = lod_bias
	geo.material_override = mat
	if visibility_end > 0.0:
		geo.visibility_range_end = visibility_end
		geo.visibility_range_end_margin = visibility_fade_length
		geo.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


## Fresh material, never a ToonFactory one: those are cached and shared project-wide
## and this needs settings nothing else wants. The atlas is borrowed off whatever
## the importer built rather than preloaded by path, so this file keeps its promise
## of holding no hard reference into the backdrop directory.
func _build_backdrop_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.resource_name = "PortoBackdropOverride"
	mat.albedo_color = albedo_tint
	mat.albedo_texture = _find_albedo()
	mat.shading_mode = (
		BaseMaterial3D.SHADING_MODE_UNSHADED if unshaded
		else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	)
	# Photogrammetry shells have inconsistent winding and the source glTF asked for
	# doubleSided. Culling would punch holes; not culling costs overdraw on an object
	# that occupies a sliver of the screen behind a depth prepass.
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Hillsides seen almost edge-on are the whole silhouette. Without anisotropy the
	# atlas smears to its coarsest mip exactly where the read matters most.
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	# Only consulted on the lit fallback path, but wrong values there would be a
	# nasty surprise: flat, matte, and never catching a highlight.
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.disable_ambient_light = false
	# The one thing that must stay off: fog is doing the contrast reduction.
	mat.disable_fog = false
	return mat


func _find_albedo() -> Texture2D:
	for entry in _geometry(_scan, Transform3D.IDENTITY):
		var mesh_instance := entry[0] as MeshInstance3D
		if mesh_instance == null:
			continue
		var source := mesh_instance.get_active_material(0) as BaseMaterial3D
		if source != null and source.albedo_texture != null:
			return source.albedo_texture
	push_warning("CityBackdrop: no albedo texture on the scan; it will render flat.")
	return null


# --- Guarantees --------------------------------------------------------------

## The import is authored with `generate/physics = false` and name-suffix parsing
## switched off, so nothing should ever appear here. It stays because the player
## must never be able to touch the backdrop, and a silent regression in an .import
## file is exactly the kind of thing that ships.
func _strip_collision(node: Node) -> void:
	for child in node.get_children():
		_strip_collision(child)
	if node is CollisionObject3D or node is CollisionShape3D or node is CollisionPolygon3D:
		push_warning("CityBackdrop: scan imported collision (%s); removing it." % node.name)
		node.get_parent().remove_child(node)
		node.queue_free()


func _check_native_size(measured: Vector3) -> void:
	var expected := SCAN_NATIVE_SIZE
	var drift := maxf(
		maxf(absf(measured.x / expected.x - 1.0), absf(measured.y / expected.y - 1.0)),
		absf(measured.z / expected.z - 1.0)
	)
	if drift > SCAN_SIZE_TOLERANCE:
		push_warning(
			"CityBackdrop: scan measures %s but the placement was derived against %s (%.1f%% off). "
			% [measured, expected, drift * 100.0]
			+ "Re-derive scan_scale/scan_origin before trusting the alignment."
		)
