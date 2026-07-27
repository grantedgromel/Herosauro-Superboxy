extends RefCounted
## Landform that is not built: bedrock scarps, scree, boulders, earth slopes.
##
## The Gaia bank is not a terrace, it is a cliff — Serra do Pilar stands on a
## bluff of banded schist that drops most of the way to the water in one go, and
## the monastery is up there because nothing else could be. A box painted grey
## does not read as that. What reads is STRATA: a stack of near-horizontal bands
## of slightly different thickness, each stepped back a little from the one
## below, broken by vertical fractures, with the debris of the ones that have
## already fallen piled at the toe.
##
## So a bluff here is a grid: bands up, segments along the river, each cell one
## box with its own setback and its own dip. That grid is also why it can afford
## to be irregular — every cell is independently jittered from a position hash,
## which is what makes a cliff look eroded rather than extruded.
##
## The same machinery does the gentler work: `slope()` is the earth behind the
## top terrace, and `scree()` and `boulder()` dress every toe on both banks.

const MK := preload("res://scripts/world/terrain/masonry_kit.gd")


# --- Bluffs -------------------------------------------------------------------

## A banded rock scarp running along Z, rising from a toe to a crest.
##
## `outward` is the sign in X of the face's normal, as everywhere else on the
## bank. The crest is tapered away at both ends of the run by a raised-cosine
## window, so the bluff reads as a headland with shoulders instead of a wall with
## two square ends — `shoulder` is the fraction of the run each taper eats.
##
## Returns the number of bands, for budgeting.
static func strata_bluff(batch, z0: float, z1: float, toe_x: float, toe_y: float,
		crest_x: float, crest_y: float, outward: float, seed: int = 0,
		z_step: float = 4.2, band_h: float = 1.15, shoulder: float = 0.22) -> int:
	var run := z1 - z0
	if absf(run) < 1.0 or crest_y <= toe_y:
		return 0
	var segs := maxi(2, int(absf(run) / z_step))
	var bands := maxi(2, int((crest_y - toe_y) / band_h))
	var rb := batch.rock()

	for j in segs:
		var t0 := float(j) / float(segs)
		var t1 := float(j + 1) / float(segs)
		var za := z0 + run * t0
		var zb := z0 + run * t1
		var tc := (t0 + t1) * 0.5
		var win := _shoulder(tc, shoulder)
		var top_y := lerpf(toe_y + 1.0, crest_y, win)
		var n := maxi(1, int((top_y - toe_y) / band_h))
		for k in n:
			var f0 := float(k) / float(bands)
			# Setback is not linear: a scarp is near-vertical low down where the
			# river has undercut it, and lays back near the crest where weather
			# has got at it. pow() on the fraction is the whole profile.
			var back := pow(f0, 1.55)
			var fx := lerpf(toe_x, crest_x, back) + outward * MK.hash_sym(seed + k * 97, j) * 0.85
			var y0 := toe_y + band_h * float(k)
			var h := band_h * (0.72 + MK.hash01(seed + k, j + 7) * 0.62)
			# Beds dip a couple of degrees; a perfectly level stratum is a shelf.
			var dip := MK.hash_sym(seed + 31, k) * 0.045
			var depth := 3.4 + MK.hash01(seed + 51, k * 11 + j) * 2.2
			rb.add_box(
				Vector3(depth, h, absf(zb - za) + 0.5),
				Transform3D(Basis(Vector3.FORWARD, dip),
					Vector3(fx - outward * depth * 0.5, y0 + h * 0.5, (za + zb) * 0.5))
			)
		# Vertical fracture: one dark slot every few segments, which is what turns
		# a stack of bands back into a cliff rather than a bookshelf.
		if MK.hash01(seed + 5, j) < 0.34:
			var fy := lerpf(toe_y, top_y, 0.15)
			var fh := (top_y - toe_y) * (0.35 + MK.hash01(seed + 6, j) * 0.5)
			var fxx := lerpf(toe_x, crest_x, pow((fy - toe_y) / maxf(crest_y - toe_y, 1.0), 1.55))
			batch.dark().add_box(
				Vector3(0.5, fh, 0.36 + MK.hash01(seed + 8, j) * 0.4),
				Transform3D(Basis.IDENTITY,
					Vector3(fxx - outward * 0.30, fy + fh * 0.5, (za + zb) * 0.5))
			)
	return bands


## Raised-cosine window: 1.0 across the middle, easing to 0 within `edge` of
## either end. Used to shoulder a bluff or a hill mass down into its neighbours.
static func _shoulder(t: float, edge: float) -> float:
	if edge <= 0.001:
		return 1.0
	var f := 1.0
	if t < edge:
		f = t / edge
	elif t > 1.0 - edge:
		f = (1.0 - t) / edge
	return 0.5 - 0.5 * cos(clampf(f, 0.0, 1.0) * PI)


## Fallen rock heaped against a toe. Boxes, not blobs: broken schist is angular,
## and a rounded pile reads as gravel.
static func scree(batch, z0: float, z1: float, face_x: float, outward: float,
		y: float, spread: float = 4.0, seed: int = 0, density: float = 0.7) -> void:
	var rb := batch.rock()
	var run := z1 - z0
	var n := maxi(3, int(absf(run) / 2.6))
	for i in n:
		if MK.hash01(seed, i) > density:
			continue
		var t := (float(i) + 0.5) / float(n)
		var z := lerpf(z0, z1, t) + MK.hash_sym(seed + 2, i) * 1.4
		# Bigger blocks lie further out; fines bank up against the face.
		var d := MK.hash01(seed + 4, i)
		var s := 0.5 + d * 1.7
		var x := face_x + outward * (0.4 + d * spread)
		rb.add_box(
			Vector3(s * 1.4, s * 0.7, s * 1.2),
			Transform3D(
				Basis.from_euler(Vector3(MK.hash_sym(seed + 7, i) * 0.5,
					MK.hash01(seed + 9, i) * TAU, MK.hash_sym(seed + 11, i) * 0.4)),
				Vector3(x, y + s * 0.25, z))
		)


## One conspicuous block: a boulder in the shallows, a glacial erratic left on a
## terrace, the lump the bridge abutment was founded on.
static func boulder(b: MeshBaker, pos: Vector3, size: float, seed: int = 0) -> void:
	# Three interpenetrating slabs at different angles. Cheaper than any rounded
	# form and reads as a fractured block, which is what schist actually does.
	for i in 3:
		var s := size * (0.6 + MK.hash01(seed, i) * 0.55)
		b.add_box(
			Vector3(s * 1.3, s * 0.8, s * 1.1),
			Transform3D(
				Basis.from_euler(Vector3(MK.hash_sym(seed + 1, i) * 0.6,
					MK.hash01(seed + 2, i) * TAU, MK.hash_sym(seed + 3, i) * 0.6)),
				pos + Vector3(MK.hash_sym(seed + 4, i) * size * 0.3,
					MK.hash01(seed + 5, i) * size * 0.25,
					MK.hash_sym(seed + 6, i) * size * 0.3))
		)


# --- Open ground --------------------------------------------------------------

## Height of that slope at (x, z). Eased along X so it leaves the terrace behind
## it tangentially instead of at a crease, with two out-of-phase ridges across it
## because a hillside that is smooth in Z reads as an extrusion.
static func slope_y(x_front: float, x_back: float, y_front: float, y_back: float,
		relief: float, seed: int, x: float, z: float) -> float:
	var span := x_back - x_front
	var t := 0.0 if absf(span) < 1e-4 else clampf((x - x_front) / span, 0.0, 1.0)
	var ease := t * t * (3.0 - 2.0 * t)
	var ridges := sin(z * 0.041 + float(seed) * 0.7) * 0.6 + sin(z * 0.113 + float(seed) * 2.1) * 0.4
	return lerpf(y_front, y_back, ease) + relief * ridges * sin(t * PI)
