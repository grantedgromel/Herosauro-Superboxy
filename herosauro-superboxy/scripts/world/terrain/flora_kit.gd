extends RefCounted
## Cheap baked vegetation: cypresses, plane-tree canopies, ivy, scrub, planters.
##
## Deliberately NOT alpha-tested cards. Cut-out foliage needs good textures to
## look like anything, costs a full alpha-scissor pass on every leaf, and turns
## into visible cardboard the moment the camera moves — which on a third-person
## rig it constantly does. Solid low-poly volumes have the opposite failure mode:
## they are never *detailed*, but they are never wrong either, and at the fifty
## to two hundred metres this planting is seen from, a mass with the right
## silhouette and the right value beats a detailed tree every time.
##
## So everything here is built from one primitive — a jittered ring — swept into
## three forms:
##
##   * a TAPER (two rings) for trunks and the tiers of a cypress,
##   * a BLOB (two rings, two apexes, 4 x sides triangles) for a clump of leaves,
##   * a CURTAIN of squashed blobs for ivy on a wall.
##
## The rule that makes it read: never one blob, always three to five overlapping
## at different sizes and offsets. A single blob is a ball. Five is a tree.
##
## Vertex jitter is hashed from position, not drawn from a sequence, so a tree
## looks the same every run and moving one does not reshuffle the rest.

const MK := preload("res://scripts/world/terrain/masonry_kit.gd")
const TerrainBatch := preload("res://scripts/world/terrain/terrain_batch.gd")

## Deep, desaturated, slightly blue-shifted greens are the point. The Porto bank
## is backlit at 11.5 degrees, so its planting is very nearly silhouette; the
## Gaia bank catches the sun and can take the warmer tone. Both come from the
## batch, which owns the two materials.


# --- Primitives ---------------------------------------------------------------

## A jittered horizontal ring of `sides` points around `center`.
static func _ring(center: Vector3, radius: Vector3, sides: int, seed: int, ragged: float) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	for i in sides:
		var a := TAU * float(i) / float(sides)
		var r := 1.0 + MK.hash_sym(seed, i) * ragged
		pts.append(center + Vector3(cos(a) * radius.x * r, 0.0, sin(a) * radius.z * r))
	return pts


## An open tapered drum between two rings — trunks, cypress tiers, hedge bodies.
##
## `_ring` runs anticlockwise seen from +Y, so a face walked bottom-then-round
## has a right-hand normal pointing at the axis. Every quad here therefore starts
## on the TOP ring and walks down, which is what MeshBaker's contract wants: the
## right-hand normal of the vertex order is the direction the surface faces.
##
## This whole file used to walk the other way — the only family in `scripts/world/`
## that did, which is why it happened to render while everything wound to the
## contract was being culled. It rendered inside out: every canopy, every trunk
## and every cypress was shaded as though the sun were inside it, which is most
## of why the planting read as flat dark blobs rather than as masses with a lit
## side. Reversing it here and reversing the emitter in MeshBaker cancel for
## visibility and compound for shading, so nothing moved and everything lit.
static func taper(b: MeshBaker, base: Vector3, top: Vector3, r_base: float, r_top: float,
		sides: int = 5, seed: int = 0, ragged: float = 0.16) -> void:
	var lo := _ring(base, Vector3(r_base, 0, r_base), sides, seed, ragged)
	var hi := _ring(top, Vector3(r_top, 0, r_top), sides, seed + 1, ragged)
	for i in sides:
		var j := (i + 1) % sides
		b.add_quad(hi[i], hi[j], lo[j], lo[i], Vector2(r_base, top.y - base.y))


## A closed low-poly clump: two rings capped with an apex at each end.
## 4 x `sides` triangles — twenty at the default, which is the whole budget for
## one puff of a canopy.
static func blob(b: MeshBaker, center: Vector3, radius: Vector3, sides: int = 5,
		seed: int = 0, ragged: float = 0.22) -> void:
	var lo := _ring(center + Vector3(0, -radius.y * 0.35, 0), radius * 0.74, sides, seed, ragged)
	var hi := _ring(center + Vector3(0, radius.y * 0.22, 0), radius, sides, seed + 3, ragged)
	var bottom := center + Vector3(MK.hash_sym(seed, 7) * radius.x * 0.2, -radius.y, 0)
	var top := center + Vector3(MK.hash_sym(seed, 9) * radius.x * 0.3, radius.y,
			MK.hash_sym(seed, 11) * radius.z * 0.3)
	for i in sides:
		var j := (i + 1) % sides
		# Same rule as `taper`: walk each face so its right-hand normal leaves the
		# clump, which for the ring means top-to-bottom, and for the two apex fans
		# means backwards around the ring.
		b.add_quad(hi[i], hi[j], lo[j], lo[i], Vector2(radius.x, radius.y))
		# Degenerate fourth corner: MeshBaker skips the zero-area triangle, so
		# this is a fan tri at the cost of writing one.
		b.add_quad(hi[j], hi[i], top, top, Vector2(radius.x, radius.y))
		b.add_quad(lo[i], lo[j], bottom, bottom, Vector2(radius.x, radius.y))


# --- Trees --------------------------------------------------------------------

## A cypress: the vertical exclamation mark on every Portuguese hillside, and the
## single most useful plant here — a stack of terraces is all horizontals, and
## three cypresses break that better than thirty of anything else.
##
## Built as tiers rather than one cone so the silhouette has notches in it. About
## 50 triangles.
static func cypress(b: MeshBaker, base: Vector3, height: float, seed: int = 0) -> void:
	var tiers := 4
	var r0 := height * 0.105
	var prev := base + Vector3(0, height * 0.04, 0)
	for i in tiers:
		var f0 := float(i) / float(tiers)
		var f1 := float(i + 1) / float(tiers)
		var next := base + Vector3(MK.hash_sym(seed, i) * height * 0.03,
				height * (0.04 + 0.96 * f1), MK.hash_sym(seed, i + 40) * height * 0.03)
		# Bulges at the third tier, like a real one that has been let go.
		var swell := 1.0 + 0.18 * sin(f0 * PI)
		taper(b, prev, next, r0 * (1.0 - f0 * 0.72) * swell, r0 * (1.0 - f1 * 0.72),
				5, seed + i * 13, 0.20)
		prev = next
	# Tip.
	var tip := prev + Vector3(0, height * 0.10, 0)
	var ring := _ring(prev, Vector3(r0 * 0.28, 0, r0 * 0.28), 5, seed + 71, 0.2)
	for i in 5:
		# Backwards around the ring, so the cone's normals point out and up.
		b.add_quad(ring[(i + 1) % 5], ring[i], tip, tip, Vector2(r0, height * 0.1))


## A broadleaf — plane, jacaranda, the big shade trees on the cais. Trunk in the
## timber baker, canopy in a leaf baker, so the two get their own material.
## About 100 triangles.
static func broadleaf(canopy: MeshBaker, trunk: MeshBaker, base: Vector3, height: float,
		seed: int = 0) -> void:
	var trunk_h := height * 0.42
	var r := height * 0.045
	taper(trunk, base, base + Vector3(0, trunk_h, 0), r * 1.5, r * 0.8, 5, seed, 0.10)
	# Two limbs leaving the trunk. Nothing reads as a tree faster than a fork.
	for k in 2:
		var a := MK.hash01(seed, k + 5) * TAU
		var tipv := base + Vector3(cos(a) * height * 0.16, trunk_h + height * 0.16,
				sin(a) * height * 0.16)
		taper(trunk, base + Vector3(0, trunk_h * 0.85, 0), tipv, r * 0.7, r * 0.35, 4, seed + k * 9, 0.12)

	var spread := height * 0.30
	var puffs := 4
	for i in puffs:
		var a := TAU * float(i) / float(puffs) + MK.hash01(seed, i) * 1.2
		var d := spread * (0.35 + MK.hash01(seed, i + 21) * 0.6)
		var rr := spread * (0.55 + MK.hash01(seed, i + 33) * 0.4)
		blob(canopy, base + Vector3(cos(a) * d, trunk_h + height * (0.22 + MK.hash01(seed, i + 47) * 0.28),
				sin(a) * d), Vector3(rr, rr * 0.78, rr), 5, seed + i * 17)


## A dense low mass: overgrown shrubs, brambles at a wall toe, an untended garden
## on a terrace. Two or three blobs, no trunk.
static func scrub(b: MeshBaker, pos: Vector3, radius: float, seed: int = 0) -> void:
	var n := 2 + int(MK.hash01(seed, 1) * 2.0)
	for i in n:
		var a := TAU * float(i) / float(n) + MK.hash01(seed, i) * 1.5
		var d := radius * 0.45 * MK.hash01(seed, i + 3)
		var rr := radius * (0.55 + MK.hash01(seed, i + 6) * 0.45)
		blob(b, pos + Vector3(cos(a) * d, rr * 0.55, sin(a) * d),
				Vector3(rr, rr * 0.6, rr), 5, seed + i * 23, 0.3)


# --- Wall planting ------------------------------------------------------------

## Ivy on a wall face: a curtain of blobs squashed flat against the stone.
##
## `from_top` hangs it over the coping and lets it fall; otherwise it climbs from
## the toe. Both happen on the same wall in Porto and doing only one reads as a
## texture rather than as a plant.
##
## The squash is in X only, so the mass hugs the wall to within 30 cm — an ivy
## that stands a metre proud looks like moss on a rock.
static func ivy_curtain(b: MeshBaker, z0: float, z1: float, face_x: float, outward: float,
		y_anchor: float, reach: float, seed: int = 0, from_top: bool = true) -> void:
	var run := absf(z1 - z0)
	var n := maxi(3, int(run / 1.15))
	for i in n:
		var t := (float(i) + 0.5) / float(n)
		var z := lerpf(z0, z1, t)
		# Thinner at the leading edge, so the mass has a ragged front instead of
		# ending on a line.
		var falloff := sin(t * PI)
		var drop := reach * (0.30 + 0.70 * falloff) * (0.6 + MK.hash01(seed, i) * 0.8)
		var r := 0.55 + MK.hash01(seed, i + 17) * 0.55
		var steps := maxi(1, int(drop / 0.95))
		for s in steps:
			var f := (float(s) + 0.5) / float(steps)
			var y := (y_anchor - drop * f) if from_top else (y_anchor + drop * f)
			var rr := r * (1.0 - f * 0.35)
			blob(b, Vector3(face_x + outward * 0.16, y, z + MK.hash_sym(seed, i * 7 + s) * 0.35),
					Vector3(0.30, rr * 0.72, rr), 5, seed + i * 31 + s * 5, 0.34)


## A run of scrub along the toe of a wall — the weeds and buddleia that colonise
## every joint of every retaining wall in the city.
static func wall_toe(b: MeshBaker, z0: float, z1: float, face_x: float, outward: float,
		y: float, seed: int = 0, density: float = 0.55) -> void:
	var run := absf(z1 - z0)
	var n := maxi(2, int(run / 3.2))
	for i in n:
		if MK.hash01(seed + 3, i) > density:
			continue
		var t := (float(i) + 0.5) / float(n)
		var z := lerpf(z0, z1, t) + MK.hash_sym(seed, i) * 1.1
		var r := 0.55 + MK.hash01(seed, i + 11) * 0.75
		scrub(b, Vector3(face_x + outward * (r * 0.35), y, z), r, seed + i * 19)


# --- Furniture ----------------------------------------------------------------

## A granite trough planter with something growing out of it. Wants the batch:
## stone, soil and leaf are three materials.
static func planter(batch: TerrainBatch, pos: Vector3, size: Vector3, seed: int = 0) -> void:
	var g := batch.dressed()
	var wall := 0.13
	# Four sides rather than a box with a lid, so the trough reads as hollow.
	g.add_box(Vector3(size.x, size.y, wall),
			Transform3D(Basis.IDENTITY, pos + Vector3(0, size.y * 0.5, (size.z - wall) * 0.5)))
	g.add_box(Vector3(size.x, size.y, wall),
			Transform3D(Basis.IDENTITY, pos + Vector3(0, size.y * 0.5, -(size.z - wall) * 0.5)))
	g.add_box(Vector3(wall, size.y, size.z - wall * 2.0),
			Transform3D(Basis.IDENTITY, pos + Vector3((size.x - wall) * 0.5, size.y * 0.5, 0)))
	g.add_box(Vector3(wall, size.y, size.z - wall * 2.0),
			Transform3D(Basis.IDENTITY, pos + Vector3(-(size.x - wall) * 0.5, size.y * 0.5, 0)))
	batch.earth().add_box(Vector3(size.x - wall * 2.0, 0.12, size.z - wall * 2.0),
			Transform3D(Basis.IDENTITY, pos + Vector3(0, size.y - 0.16, 0)))
	var leaf: MeshBaker = batch.leaf_lit() if MK.hash01(seed, 2) > 0.4 else batch.leaf_dark()
	scrub(leaf, pos + Vector3(0, size.y - 0.05, 0), minf(size.x, size.z) * 0.85, seed + 61)


## A line of trees along a promenade or a terrace street, thinned out by hash so
## the spacing is not a metronome and the odd gap reads as one that died.
static func tree_row(batch: TerrainBatch, x: float, z0: float, z1: float, pitch: float,
		height_min: float, height_max: float, y: float, seed: int = 0,
		gap_chance: float = 0.22) -> void:
	var run := z1 - z0
	var n := maxi(1, int(absf(run) / pitch))
	for i in n:
		if MK.hash01(seed, i) < gap_chance:
			continue
		var z := z0 + run * ((float(i) + 0.5) / float(n)) + MK.hash_sym(seed + 5, i) * pitch * 0.22
		var h := lerpf(height_min, height_max, MK.hash01(seed + 9, i))
		var dx := MK.hash_sym(seed + 13, i) * 0.7
		broadleaf(batch.leaf_lit(), batch.timber(), Vector3(x + dx, y, z), h, seed + i * 37)
