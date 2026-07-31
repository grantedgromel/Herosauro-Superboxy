class_name PropMeshKit
extends RefCounted
## Every mesh the interactive props and their shards are made of.
##
## Two jobs, and they are the same job: a crate has to read as a crate at 5 m,
## and the planks it bursts into have to read as pieces OF THAT CRATE. Building
## both from one kit is the only way that stays true when someone retunes a
## barrel's radius — the staves come off the same number.
##
## --- Why this is assembled from engine primitives, not from a SurfaceTool ----
##
## Round 2 spent a whole round on two mirror-image winding bugs in MeshBaker, and
## settled the engine convention four ways: Godot's front face is the one whose
## right-hand normal points INTO the solid, so an outward shading normal is -RH.
## Every hand-wound emitter in this project has been wrong about that at least
## once. Nothing here winds a triangle. `SurfaceTool.append_from()` copies the
## vertices AND the stored normals out of Godot's own BoxMesh / CylinderMesh /
## TorusMesh and transforms them, so the primitives that Round 2 verified as
## correct are the only source of geometry in this file. _props_probe.gd measures
## the stored normals on the committed meshes anyway, because "it must be right
## by construction" is what the last two rounds each believed.
##
## --- Why one mesh per prop, not one node per part ---------------------------
##
## ARCHITECTURE.md rule 6: draw calls are the number that kills the frame. A
## crate built as a core box plus twelve edge battens is thirteen MeshInstance3Ds
## and thirteen draw calls; committed through one SurfaceTool it is one. Fourteen
## props on the deck therefore cost 14 body draws plus 10 trim draws (barrels and
## crates carry an iron trim surface, rubble does not) rather than ~180.
##
## --- Caching ----------------------------------------------------------------
##
## Shards are spawned in bursts of up to a dozen at the exact moment the frame is
## already busy, so nothing here may build geometry at shatter time. Every
## builder is keyed and cached process-wide; the cache is small and bounded
## because every caller quantises its arguments (see PropBody.variant_index).

## Built meshes, keyed on the builder name plus its rounded arguments.
static var _cache: Dictionary = {}

## Radial resolution of anything round. 12 is the barrel's own segment count and
## it is chosen for silhouette, not for smoothness: a Crash barrel is faceted.
const RADIAL_SEGMENTS := 12

## How far a barrel's waist bulges past its ends, as a fraction of the radius.
## Real rabelo casks bulge about 8%; exaggerated to 14% because the RUBRIC asks
## for cartoon proportions and a straight cylinder reads as a bin.
const BARREL_BULGE := 0.14
## Stave courses up the barrel wall. Five gives four visible steps in the
## silhouette, which at this size is what sells "assembled from staves".
const BARREL_COURSES := 5


# --- Prop bodies ------------------------------------------------------------

## A slatted crate: a core box inside a frame of twelve edge battens.
##
## The battens are what make it a crate rather than a cube. They stand 3 cm
## proud, so at any grazing angle the silhouette breaks up and the frame catches
## a different amount of key light than the panels do — which is the cheapest
## honest answer to the RUBRIC's "any flat-coloured polygon fails the shot".
static func crate_body(size: Vector3) -> ArrayMesh:
	var key := "crate_body|%.3f|%.3f|%.3f" % [size.x, size.y, size.z]
	if _cache.has(key):
		return _cache[key]

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Panels sit inboard of the frame so the battens read as applied timber.
	var batten := minf(size.x, minf(size.y, size.z)) * 0.11
	_box(st, size - Vector3.ONE * batten * 1.2, Transform3D.IDENTITY)

	# Twelve edges of a box: four along each axis, at the four (+-,+-) corners of
	# the other two.
	var h := size * 0.5
	for sa: float in [-1.0, 1.0]:
		for sb: float in [-1.0, 1.0]:
			var off := (h - Vector3.ONE * batten * 0.5)
			_box(st, Vector3(size.x, batten, batten),
				Transform3D(Basis.IDENTITY, Vector3(0.0, sa * off.y, sb * off.z)))
			_box(st, Vector3(batten, size.y, batten),
				Transform3D(Basis.IDENTITY, Vector3(sa * off.x, 0.0, sb * off.z)))
			_box(st, Vector3(batten, batten, size.z),
				Transform3D(Basis.IDENTITY, Vector3(sa * off.x, sb * off.y, 0.0)))

	return _commit(key, st)


## The eight iron corner brackets. A separate surface because it wears the iron
## material — see PropBody._apply_materials and the "prop_trim" group.
static func crate_brackets(size: Vector3) -> ArrayMesh:
	var key := "crate_brackets|%.3f|%.3f|%.3f" % [size.x, size.y, size.z]
	if _cache.has(key):
		return _cache[key]

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var batten := minf(size.x, minf(size.y, size.z)) * 0.11
	var leg := minf(size.x, minf(size.y, size.z)) * 0.30
	var h := size * 0.5 - Vector3.ONE * batten * 0.5
	# Slightly fatter than the batten it wraps, so the strap is visible against
	# the timber instead of being coplanar z-fighting.
	var t := batten * 1.25
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				var c := Vector3(sx * h.x, sy * h.y, sz * h.z)
				_box(st, Vector3(leg, t, t),
					Transform3D(Basis.IDENTITY, c - Vector3(sx * leg * 0.5, 0.0, 0.0)))
				_box(st, Vector3(t, leg, t),
					Transform3D(Basis.IDENTITY, c - Vector3(0.0, sy * leg * 0.5, 0.0)))
				_box(st, Vector3(t, t, leg),
					Transform3D(Basis.IDENTITY, c - Vector3(0.0, 0.0, sz * leg * 0.5)))
	return _commit(key, st)


## A bulged cask: BARREL_COURSES stacked cylinder courses whose radius follows a
## parabola, so the waist is fattest and the ends draw in.
##
## Stacked courses rather than one tapered cylinder on purpose. The steps between
## them are ~1 cm and they are exactly the horizontal banding a coopered barrel
## has; a smooth lofted surface would be more "correct" and would read as plastic.
static func barrel_body(radius: float, height: float) -> ArrayMesh:
	var key := "barrel_body|%.3f|%.3f" % [radius, height]
	if _cache.has(key):
		return _cache[key]

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var course := height / float(BARREL_COURSES)
	for i in BARREL_COURSES:
		# t in [-1, 1] across the barrel's length; radius peaks at t = 0.
		var t0 := (float(i) / float(BARREL_COURSES)) * 2.0 - 1.0
		var t1 := (float(i + 1) / float(BARREL_COURSES)) * 2.0 - 1.0
		var tm := (t0 + t1) * 0.5
		var r := radius * (1.0 - BARREL_BULGE * tm * tm) / (1.0 - BARREL_BULGE * 0.0)
		var cyl := CylinderMesh.new()
		cyl.top_radius = r
		cyl.bottom_radius = r
		cyl.height = course * 1.02   # 2% overlap so no seam gaps at the joints
		cyl.radial_segments = RADIAL_SEGMENTS
		cyl.rings = 1
		# Only the end courses need caps; the middle ones are hidden.
		cyl.cap_top = i == BARREL_COURSES - 1
		cyl.cap_bottom = i == 0
		st.append_from(cyl, 0, Transform3D(Basis.IDENTITY,
			Vector3(0.0, (float(i) + 0.5) * course - height * 0.5, 0.0)))
	return _commit(key, st)


## The two iron hoops, as one surface.
static func barrel_hoops(radius: float, height: float) -> ArrayMesh:
	var key := "barrel_hoops|%.3f|%.3f" % [radius, height]
	if _cache.has(key):
		return _cache[key]

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for sy: float in [-1.0, 1.0]:
		var y := sy * height * 0.31
		# Sit each hoop proud of the wall it grips at that height.
		var t := y / (height * 0.5)
		var wall := radius * (1.0 - BARREL_BULGE * t * t)
		var torus := TorusMesh.new()
		torus.inner_radius = wall * 0.99
		torus.outer_radius = wall * 1.06
		torus.rings = RADIAL_SEGMENTS
		torus.ring_segments = 6
		st.append_from(torus, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, y, 0.0)))
	return _commit(key, st)


## A knocked-about masonry block: one core box with `variant`-dependent corner
## chips knocked out of its silhouette by overlapping smaller boxes.
##
## The chips are ADDITIVE, not boolean subtraction — Godot has no CSG at bake
## time here and a boolean would cost more than the block is worth. Adding
## angled slabs at the corners breaks the straight edge just as effectively,
## which is the RUBRIC line ("nothing perfectly straight, clean or repeated").
static func rubble_body(size: Vector3, variant: int) -> ArrayMesh:
	var key := "rubble_body|%.3f|%.3f|%.3f|%d" % [size.x, size.y, size.z, variant]
	if _cache.has(key):
		return _cache[key]

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(st, size * 0.94, Transform3D.IDENTITY)

	# Seeded, per ARCHITECTURE.md rule 4. The variant index is the seed, so the
	# same variant is byte-identical in every run and in every process.
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x51ABB1E + variant
	var chips := 4
	for i in chips:
		var s := Vector3(
			size.x * rng.randf_range(0.28, 0.46),
			size.y * rng.randf_range(0.26, 0.44),
			size.z * rng.randf_range(0.28, 0.46))
		var at := Vector3(
			size.x * 0.5 * rng.randf_range(-0.85, 0.85),
			size.y * 0.5 * rng.randf_range(-0.7, 0.7),
			size.z * 0.5 * rng.randf_range(-0.85, 0.85))
		var b := Basis.from_euler(Vector3(
			rng.randf_range(-0.5, 0.5), rng.randf_range(-PI, PI), rng.randf_range(-0.5, 0.5)))
		_box(st, s, Transform3D(b, at))
	return _commit(key, st)


# --- Shards -----------------------------------------------------------------

## A sawn plank: long, wide, thin. The crate's panels come apart into these.
static func plank(length: float, width: float, thickness: float) -> ArrayMesh:
	return _slab("plank", Vector3(length, thickness, width))


## A splinter: long, thin both ways. Half a dozen of these are what stop a burst
## reading as a handful of identical cubes.
static func splinter(length: float, thickness: float) -> ArrayMesh:
	return _slab("splinter", Vector3(length, thickness, thickness * 1.4))


## One barrel stave, bowed. Three short slabs hinged across the bow, so the piece
## keeps the barrel's curvature as it tumbles — a straight plank off a round
## barrel is the tell that the debris was generic.
static func stave(length: float, width: float, thickness: float) -> ArrayMesh:
	var key := "stave|%.3f|%.3f|%.3f" % [length, width, thickness]
	if _cache.has(key):
		return _cache[key]

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := length / 3.0
	var bow := 0.16   # radians per joint; three segments span ~18 degrees of arc
	for i in 3:
		var k := float(i) - 1.0
		var b := Basis.from_euler(Vector3(0.0, 0.0, k * bow))
		# Offset each segment along the chord so the joints meet.
		var at := Vector3(k * seg * cos(bow * 0.5), absf(k) * seg * bow * 0.5, 0.0)
		st.append_from(_unit_box(Vector3(seg * 1.04, thickness, width)), 0,
			Transform3D(b, at))
	return _commit(key, st)


## A sheared length of hoop iron, as an arc of `segments` short bars.
static func hoop_arc(radius: float, band: float, segments: int, sweep: float) -> ArrayMesh:
	var key := "hoop_arc|%.3f|%.3f|%d|%.3f" % [radius, band, segments, sweep]
	if _cache.has(key):
		return _cache[key]

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := sweep / float(segments)
	# Chord length of one step, plus a hair so the bars overlap at the joints.
	var chord := 2.0 * radius * sin(step * 0.5) * 1.08
	for i in segments:
		var a := (float(i) + 0.5) * step - sweep * 0.5
		var at := Vector3(cos(a) * radius, sin(a) * radius, 0.0)
		# Tangent-aligned: the bar's long axis runs around the arc.
		var b := Basis.from_euler(Vector3(0.0, 0.0, a + PI * 0.5))
		st.append_from(_unit_box(Vector3(chord, band * 0.45, band)), 0, Transform3D(b, at))
	return _commit(key, st)


## An irregular masonry chunk. `variant` picks one of a handful of shapes so a
## crumbled block does not produce four identical dice.
static func chunk(scale_m: float, variant: int) -> ArrayMesh:
	var key := "chunk|%.3f|%d" % [scale_m, variant]
	if _cache.has(key):
		return _cache[key]

	var rng := RandomNumberGenerator.new()
	rng.seed = 0xC0FFEE + variant
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# A core plus two facets knocked off at angles: a conchoidal granite break,
	# not a cube.
	_box(st, Vector3(scale_m * rng.randf_range(0.8, 1.15),
		scale_m * rng.randf_range(0.6, 1.0),
		scale_m * rng.randf_range(0.75, 1.1)), Transform3D.IDENTITY)
	for i in 2:
		var s := Vector3.ONE * scale_m * rng.randf_range(0.42, 0.72)
		var b := Basis.from_euler(Vector3(
			rng.randf_range(-0.8, 0.8), rng.randf_range(-PI, PI), rng.randf_range(-0.8, 0.8)))
		var at := Vector3(
			scale_m * rng.randf_range(-0.45, 0.45),
			scale_m * rng.randf_range(-0.35, 0.35),
			scale_m * rng.randf_range(-0.45, 0.45))
		_box(st, s, Transform3D(b, at))
	return _commit(key, st)


## A flat wedge, for the splash of port a broken cask throws out. Flattened
## rather than spherical because it is going to be moving fast and short-lived,
## and a flat quad-ish shard catches the key light like a sheet of liquid does.
static func droplet(scale_m: float) -> ArrayMesh:
	return _slab("droplet", Vector3(scale_m, scale_m * 0.28, scale_m * 0.7))


# --- Internals --------------------------------------------------------------

static func _slab(kind: String, size: Vector3) -> ArrayMesh:
	var key := "%s|%.4f|%.4f|%.4f" % [kind, size.x, size.y, size.z]
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(st, size, Transform3D.IDENTITY)
	return _commit(key, st)


static func _box(st: SurfaceTool, size: Vector3, xform: Transform3D) -> void:
	st.append_from(_unit_box(size), 0, xform)


## BoxMesh instances are themselves cached: a crate frame appends thirteen of
## them and four of those are the same size.
static func _unit_box(size: Vector3) -> BoxMesh:
	var key := "box|%.4f|%.4f|%.4f" % [size.x, size.y, size.z]
	var cached: BoxMesh = _cache.get(key)
	if cached != null:
		return cached
	var bm := BoxMesh.new()
	bm.size = size
	_cache[key] = bm
	return bm


static func _commit(key: String, st: SurfaceTool) -> ArrayMesh:
	# index() welds the duplicate corners the appended boxes share, which is worth
	# doing once at build time and never again.
	st.index()
	var mesh := st.commit()
	_cache[key] = mesh
	return mesh
