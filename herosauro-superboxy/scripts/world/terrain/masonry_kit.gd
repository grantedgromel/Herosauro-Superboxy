extends RefCounted
## Granite construction: coursed walls, copings, buttresses, stairs, bollards.
##
## Porto's riverfront is one material used six ways. The quay walls, the
## retaining walls holding each terrace up, the cheeks of every escadaria, the
## kerbs, the bollards and the steps into the water are all the same grey
## granite, laid in courses, and what distinguishes them is joint size, block
## size and how much the face leans back. So they are all here, built out of two
## primitives — a course of blocks and a dressed stone — rather than modelled
## separately.
##
## Three things the callers depend on:
##
##   * WALLS ARE BATTERED. A real retaining wall leans back roughly 1:12; a
##     vertical one reads as a set flat. Every wall function takes the face
##     position at its TOP and thickens downwards, so a caller can line copings
##     and platform edges up on one number and let the toe fall where it may.
##
##   * BLOCKS ARE NOT A GRID. Course heights vary, block lengths vary, every
##     block is a centimetre or two proud or shy of its neighbours, and
##     alternate courses are offset so no vertical joint runs more than two
##     courses. That last one is doing most of the work: a wall with aligned
##     joints reads as tiling, not as masonry.
##
##   * `outward` IS THE FACE NORMAL'S SIGN IN X. The gorge runs along Z, so every
##     wall on the bank faces the river along +-X. On the Porto bank (negative x)
##     that is +1; on Gaia it is -1. It is always `-side`.
##
## Determinism is by hash, not by a sequential RNG. Two call sites that ask for
## the same run of wall must get the same wall — the height query in
## terrain_builder.gd has to agree with the geometry without rebuilding it — and
## a shared RandomNumberGenerator makes that depend on call order.

const TerrainBatch := preload("res://scripts/world/terrain/terrain_batch.gd")

## Mortar joint. Blocks are shrunk by this so the gap between them is a real
## shadow line rather than a coincident face pair that z-fights.
const JOINT := 0.035


# --- Deterministic noise ------------------------------------------------------

## A stable [0,1) from two integers. Cheap integer hash, masked positive at each
## step because GDScript's `>>` is an arithmetic shift and a sign bit would make
## the mixing lopsided.
static func hash01(a: int, b: int) -> float:
	var h: int = (a * 73856093) ^ (b * 19349663)
	h = h & 0x7FFFFFFF
	h = (h ^ (h >> 13)) * 1274126177
	h = h & 0x7FFFFFFF
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65536.0


## The same, signed into [-1, 1).
static func hash_sym(a: int, b: int) -> float:
	return hash01(a, b) * 2.0 - 1.0


# --- Ground surfaces ----------------------------------------------------------

## Height of a paved platform at (x, z), given its river-side and back edges.
##
## Public and pure because two things need to agree on it: the geometry, and
## terrain_builder's ground_height() query, which placement code uses to sit
## buildings on the ground. Both edges return their nominal height exactly — the
## camber and the sag are faded out at t=0 and t=1 — so a wall built to `y_front`
## meets the paving with no lip.
static func surface_y(x_front: float, x_back: float, y_front: float, y_back: float,
		crown: float, wobble: float, seed: int, x: float, z: float) -> float:
	var span := x_back - x_front
	var t := 0.0 if absf(span) < 1e-4 else clampf((x - x_front) / span, 0.0, 1.0)
	var arch := sin(t * PI)
	# Two incommensurable wavelengths: enough to keep a 190 m quay from reading as
	# a ruler, not enough for anyone to find the period.
	var sag := sin(z * 0.077 + float(seed) * 0.31) * 0.62 + sin(z * 0.213 - float(seed)) * 0.38
	return lerpf(y_front, y_back, t) + crown * arch + wobble * sag * arch


# --- Walls --------------------------------------------------------------------

## A run of coursed masonry facing +-X, laid block by block.
##
## `face_x0`/`face_x1` are the face position at the TOP of the wall at z0 and z1,
## and `y_top0`/`y_top1` its coping line there. Both are interpolated PER BLOCK,
## which is what lets a wall follow a terrace that drifts up and down along the
## river without the coping parting company with the paving behind it. The face
## steps out as it descends by `batter` per metre of height.
##
## This is the expensive one — 12 triangles per block, and a 6 m wall over a 100 m
## reach is some 400 blocks. It is worth it on the near reach and nowhere else;
## use banded_wall() past the point where individual stones stop resolving.
static func coursed_wall(b: MeshBaker, z0: float, z1: float, face_x0: float, face_x1: float,
		outward: float, y_bottom: float, y_top0: float, y_top1: float,
		thickness: float = 1.2, course_h: float = 0.72,
		block_min: float = 1.1, block_max: float = 2.4,
		batter: float = 0.05, seed: int = 0) -> void:
	var mean_h := (y_top0 + y_top1) * 0.5 - y_bottom
	if mean_h <= 0.01 or absf(z1 - z0) < 0.05:
		return
	# One course count for the whole run, so the beds line up across it; the
	# courses themselves fan slightly where the top drifts, which is exactly what
	# a mason does when he trims the top course to a falling line.
	var courses := maxi(1, int(round(mean_h / course_h)))
	var run := z1 - z0
	for c in courses:
		var z := z0
		var k := 0
		while absf(z - z0) < absf(run) - 0.02:
			var length := lerpf(block_min, block_max, hash01(seed + c * 7717, k))
			# Break the vertical joint line: alternate courses start on a part
			# block, so no two courses can share a run of joints.
			if k == 0 and c % 2 == 1:
				length *= 0.45
			length = minf(length, absf(z1 - z))
			if length < 0.3:
				break
			var zc := z + signf(run) * length * 0.5
			var t := (zc - z0) / run
			var y_top := lerpf(y_top0, y_top1, t)
			var ch := (y_top - y_bottom) / float(courses)
			var y_mid := y_bottom + ch * (float(c) + 0.5)
			var proud := (hash01(seed + c * 313, k + 91) - 0.45) * 0.055
			var fx := lerpf(face_x0, face_x1, t) + outward * (batter * (y_top - y_mid) + proud)
			b.add_box(
				Vector3(thickness, ch - JOINT, length - JOINT),
				Transform3D(Basis.IDENTITY, Vector3(fx - outward * thickness * 0.5, y_mid, zc))
			)
			z += signf(run) * length
			k += 1


## The same wall, one box per course instead of one per block.
##
## Individual stones stop resolving somewhere past 60 m; the horizontal course
## shadow is what survives, and this keeps that for 1/40th of the triangles. One
## box cannot follow a drifting top, so callers should keep far-reach runs short
## enough that the mean is close enough.
static func banded_wall(b: MeshBaker, z0: float, z1: float, face_x0: float, face_x1: float,
		outward: float, y_bottom: float, y_top0: float, y_top1: float,
		thickness: float = 1.2, course_h: float = 0.9, batter: float = 0.05,
		seed: int = 0) -> void:
	var y_top := (y_top0 + y_top1) * 0.5
	var height := y_top - y_bottom
	if height <= 0.01 or absf(z1 - z0) < 0.05:
		return
	var courses := maxi(1, int(round(height / course_h)))
	var ch := height / float(courses)
	var zc := (z0 + z1) * 0.5
	var length := absf(z1 - z0)
	for c in courses:
		var y_mid := y_bottom + ch * (float(c) + 0.5)
		var out := batter * (y_top - y_mid)
		var proud := (hash01(seed, c) - 0.5) * 0.06
		var fx := (face_x0 + face_x1) * 0.5 + outward * (out + proud)
		b.add_box(
			Vector3(thickness, ch - JOINT, length),
			Transform3D(Basis.IDENTITY, Vector3(fx - outward * thickness * 0.5, y_mid, zc))
		)


## The dressed capping course along the top of a wall, laid as separate stones.
##
## Every quay wall in Porto is finished with one: a heavier, paler, smoother
## stone projecting a hand's breadth proud of the face. It is the line that reads
## from across the river, and without it a wall just stops.
static func coping(b: MeshBaker, z0: float, z1: float, face_x0: float, face_x1: float,
		outward: float, y_top0: float, y_top1: float, width: float = 0.9,
		height: float = 0.34, overhang: float = 0.13, stone_len: float = 2.2,
		seed: int = 0) -> void:
	var run := z1 - z0
	if absf(run) < 0.05:
		return
	var n := maxi(1, int(round(absf(run) / stone_len)))
	var step := run / float(n)
	for i in n:
		var zc := z0 + step * (float(i) + 0.5)
		var t := (zc - z0) / run
		var fx := lerpf(face_x0, face_x1, t) + outward * overhang
		var y_top := lerpf(y_top0, y_top1, t)
		# A hair of settlement per stone, so the top line is not a laser.
		var dy := hash_sym(seed + 55, i) * 0.022
		b.add_box(
			Vector3(width, height, absf(step) - JOINT),
			Transform3D(Basis.IDENTITY,
				Vector3(fx - outward * width * 0.5, y_top - height * 0.5 + dy, zc))
		)


## A battered pier standing proud of a wall face, thickening as it descends.
##
## Buttresses are the single cheapest thing that turns a long wall into
## architecture: they break the run into bays, and at a raking sun each one
## throws a hard vertical shadow the length of the wall.
static func buttress(b: MeshBaker, z_center: float, face_x: float, outward: float,
		y_bottom: float, y_top: float, width: float = 1.5, project: float = 0.75,
		steps: int = 4) -> void:
	var height := y_top - y_bottom
	if height <= 0.05:
		return
	var sh := height / float(steps)
	for i in steps:
		# Widest at the toe, tapering to nothing at the top — a real buttress
		# carries thrust down and out, and the stepped profile is how it is built.
		var f := 1.0 - float(i) / float(steps)
		var proj := project * f
		if proj < 0.04:
			continue
		var y_mid := y_bottom + sh * (float(i) + 0.5)
		b.add_box(
			Vector3(proj, sh, width * (0.85 + 0.15 * f)),
			Transform3D(Basis.IDENTITY,
				Vector3(face_x + outward * proj * 0.5, y_mid, z_center))
		)
	# Weathered cap so rain runs off the top of the pier instead of standing.
	b.add_box(
		Vector3(project * 0.35, 0.18, width * 0.9),
		Transform3D(Basis.IDENTITY, Vector3(face_x + outward * project * 0.17, y_top - 0.09, z_center))
	)


## Drainage openings, suggested rather than modelled.
##
## A real weep hole is a 10 cm pipe through a metre of masonry: unmodellable at
## this scale and invisible if it were. What reads is the dark rectangle and the
## stain under it, so that is what this is — a void-dark box set a few
## centimetres back inside the face, which the surrounding stone frames into a
## hole. Wants the batch's dark baker, not the granite one.
static func weep_holes(b: MeshBaker, z0: float, z1: float, face_x0: float, face_x1: float,
		outward: float, y: float, pitch: float = 4.5, seed: int = 0) -> void:
	var run := z1 - z0
	var n := int(absf(run) / pitch)
	for i in n:
		if hash01(seed + 7, i) < 0.35:
			continue    # not every bay drains
		var t := (float(i) + 0.5) / float(maxi(n, 1))
		var zc := lerpf(z0, z1, t)
		var fx := lerpf(face_x0, face_x1, t)
		var dy := hash_sym(seed + 13, i) * 0.35
		b.add_box(
			Vector3(0.16, 0.20, 0.30),
			Transform3D(Basis.IDENTITY, Vector3(fx - outward * 0.10, y + dy, zc))
		)


# --- Steps --------------------------------------------------------------------

## An escadaria: a flight of granite steps climbing in X, with stepped cheek
## walls and an iron handrail.
##
## Porto's staircases are steep — 30 to 35 degrees, ~17 cm rise on a ~30 cm
## tread — and they always have a landing partway, because they are long. Both
## are here: `x_bottom`/`x_top` are signed world coordinates, so the flight
## climbs whichever way the caller points it.
##
## Returns the number of steps, so a caller can budget.
static func stair_flight(batch: TerrainBatch, z_center: float, width: float,
		x_bottom: float, y_bottom: float, x_top: float, y_top: float,
		seed: int = 0, rail: bool = true) -> int:
	var rise_total := y_top - y_bottom
	var run_total := x_top - x_bottom
	if rise_total <= 0.05 or absf(run_total) < 0.5:
		return 0

	var dir := signf(run_total)
	var steps := maxi(2, int(round(rise_total / 0.175)))
	var landing := 1.7 if steps > 11 else 0.0
	var rise := rise_total / float(steps)
	var tread := (absf(run_total) - landing) / float(steps)
	var half := steps / 2

	var g := batch.dressed()
	var x := x_bottom
	var y := y_bottom
	var tops: Array[Vector3] = []     # nose centres, for the handrail
	for i in steps:
		if i == half and landing > 0.0:
			g.add_box(
				Vector3(landing, 0.30, width),
				Transform3D(Basis.IDENTITY, Vector3(x + dir * landing * 0.5, y - 0.15, z_center))
			)
			x += dir * landing
			tops.append(Vector3(x, y, z_center))
		# Each step overlaps the one below by a few centimetres in both axes, so
		# a flight is watertight without needing exact arithmetic.
		g.add_box(
			Vector3(tread + 0.05, rise + 0.16, width),
			Transform3D(Basis.IDENTITY,
				Vector3(x + dir * (tread * 0.5), y + rise * 0.5 - 0.08, z_center))
		)
		x += dir * tread
		y += rise
		# A rail station every fifth step. The run between landings is straight, so
		# more than this is triangles spent on a line that was already straight.
		if i % 5 == 0:
			tops.append(Vector3(x, y, z_center))
	tops.append(Vector3(x, y, z_center))

	# Stepped cheek walls. They step every third tread, which is how a mason
	# builds them and why an escadaria has that sawtooth edge against the sky.
	for side_i in 2:
		var s := -1.0 if side_i == 0 else 1.0
		var cz := z_center + s * (width * 0.5 + 0.24)
		var cx := x_bottom
		var cy := y_bottom
		var chunk := 3
		var i := 0
		while i < steps:
			var n := mini(chunk, steps - i)
			var seg := tread * float(n)
			if i >= half and landing > 0.0 and i - chunk < half:
				seg += landing
			var top := cy + rise * float(n) + 0.55
			var bottom := cy - 1.1
			g.add_box(
				Vector3(seg + 0.06, top - bottom, 0.42),
				Transform3D(Basis.IDENTITY,
					Vector3(cx + dir * seg * 0.5, (top + bottom) * 0.5, cz))
			)
			cx += dir * seg
			cy += rise * float(n)
			i += n

	if rail:
		for side_i in 2:
			var s := -1.0 if side_i == 0 else 1.0
			handrail(batch.iron(), tops, s * (width * 0.5 + 0.02), 0.98, seed + side_i)
	return steps


## A plain iron handrail following a polyline of step noses.
##
## Two bars and a post every couple of metres. Round posts, flat top rail: it is
## the same vocabulary as the bridge parapet, which matters — the ironwork on the
## bank should look like it came from the same foundry as the ironwork on the
## bridge, because in Porto it did.
static func handrail(b: MeshBaker, path: Array[Vector3], z_offset: float,
		height: float = 0.98, seed: int = 0) -> void:
	if path.size() < 2:
		return
	var top: Array[Vector3] = []
	for p in path:
		top.append(Vector3(p.x, p.y + height, p.z + z_offset))
	for i in range(top.size() - 1):
		b.add_beam(top[i], top[i + 1], 0.055)
		# Mid rail at 55% of the drop — the proportion every municipal railing in
		# the city uses, and it is what stops the run reading as a single wire.
		b.add_beam(top[i] - Vector3(0, height * 0.45, 0), top[i + 1] - Vector3(0, height * 0.45, 0), 0.038)
	for i in top.size():
		if i % 2 != 0 and i != top.size() - 1:
			continue
		var p := top[i]
		# Uncapped: the ends are inside the rail and inside the step, and the two
		# caps are a third of the post's triangles.
		b.add_cylinder(0.042, height,
				Transform3D(Basis.IDENTITY, p - Vector3(0, height * 0.5, 0)), 6, false)
	# One newel finial per run, at the head, where a hand actually lands.
	b.add_box(Vector3(0.13, 0.13, 0.13),
			Transform3D(Basis.IDENTITY, top[top.size() - 1] + Vector3(0, 0.04, 0)))


## The flight of steps down into the river.
##
## Ribeira's are projecting stone jetties flanked by two cheek piers, running out
## from the quay and down past the waterline; boats come alongside them. Steep by
## modern standards — a 30 cm rise is normal — because they were built for
## stepping into a rabelo, not for strolling.
static func water_steps(batch: TerrainBatch, z_center: float, face_x: float, outward: float,
		y_top: float, y_bottom: float, width: float = 3.4, project: float = 5.6,
		seed: int = 0) -> void:
	var drop := y_top - y_bottom
	if drop <= 0.2:
		return
	var steps := maxi(3, int(round(drop / 0.31)))
	var rise := drop / float(steps)
	var tread := project / float(steps)
	var g := batch.dressed()
	for i in steps:
		var x := face_x + outward * tread * (float(i) + 0.5)
		var y := y_top - rise * (float(i) + 0.5)
		g.add_box(
			Vector3(tread + 0.04, rise + 0.20, width),
			Transform3D(Basis.IDENTITY, Vector3(x, y, z_center))
		)
	# Flanking piers, sloping with the flight, tied back into the wall.
	var m := batch.granite()
	for side_i in 2:
		var s := -1.0 if side_i == 0 else 1.0
		var cz := z_center + s * (width * 0.5 + 0.36)
		for i in range(0, steps, 2):
			var x := face_x + outward * tread * (float(i) + 1.0)
			var top := y_top - rise * float(i) + 0.22
			var bottom := y_bottom - 1.2
			m.add_box(
				Vector3(tread * 2.0, top - bottom, 0.66),
				Transform3D(Basis.IDENTITY, Vector3(x, (top + bottom) * 0.5, cz))
			)
		# One mooring ring on each pier head, where a boat would actually tie up.
		mooring_ring(batch.iron(), Vector3(face_x + outward * (project * 0.35),
				y_top - drop * 0.30, cz + s * 0.30), 0.20, seed + side_i)


# --- Waterfront furniture -----------------------------------------------------

## A granite mooring bollard with an iron ring through it. Ribeira has a line of
## these along the coping and they are the detail that says "working quay".
static func bollard(batch: TerrainBatch, pos: Vector3, outward: float, seed: int = 0) -> void:
	var g := batch.dressed()
	var h := 0.72 + hash01(seed, 3) * 0.10
	g.add_cylinder(0.24, h, Transform3D(Basis.IDENTITY, pos + Vector3(0, h * 0.5, 0)), 8)
	# Mushroom head — the shape is what stops a hawser riding off the top.
	g.add_cylinder(0.31, 0.16, Transform3D(Basis.IDENTITY, pos + Vector3(0, h + 0.05, 0)), 8)
	mooring_ring(batch.iron(), pos + Vector3(outward * 0.24, h * 0.55, 0.0), 0.17, seed)
	# The grime ring at the foot. Bollards on a working quay are never clean where
	# they meet the setts, and it is the contact darkening the renderer is not
	# supplying — see the note on BridgeDeckKit.contact_patch() for why this is
	# geometry in this pass and not an environment setting.
	batch.dark().add_box(Vector3(0.62, 0.014, 0.62),
			Transform3D(Basis.IDENTITY, pos + Vector3(0.0, 0.014, 0.0)))


## A ring approximated by a closed loop of beams, standing in the YZ plane so it
## faces out across the water. Six segments: enough to read as round at the
## distance anything this small is ever seen from.
static func mooring_ring(b: MeshBaker, center: Vector3, radius: float, seed: int = 0,
		segments: int = 5) -> void:
	var tilt := hash_sym(seed, 21) * 0.35     # rings hang, they do not sit square
	var prev := Vector3.ZERO
	for i in range(segments + 1):
		var a := TAU * float(i) / float(segments) - PI * 0.5
		var p := center + Vector3(0.0, cos(a) * radius, sin(a) * radius).rotated(Vector3.FORWARD, tilt)
		if i > 0:
			b.add_beam(prev, p, 0.048)
		prev = p


## A kerbstone run: the raised granite edge between paving and a drop, laid as
## individual stones with the odd one settled out of line.
static func kerb(b: MeshBaker, z0: float, z1: float, face_x0: float, face_x1: float,
		outward: float, y_top: float, width: float = 0.34, height: float = 0.16,
		stone_len: float = 1.6, seed: int = 0) -> void:
	var run := z1 - z0
	if absf(run) < 0.05:
		return
	var n := maxi(1, int(round(absf(run) / stone_len)))
	var step := run / float(n)
	for i in n:
		var zc := z0 + step * (float(i) + 0.5)
		var t := (zc - z0) / run
		var fx := lerpf(face_x0, face_x1, t)
		var dy := hash_sym(seed + 91, i) * 0.018
		var dx := hash_sym(seed + 17, i) * 0.03
		b.add_box(
			Vector3(width, height, absf(step) - 0.03),
			Transform3D(Basis.IDENTITY,
				Vector3(fx - outward * (width * 0.5 - dx), y_top - height * 0.5 + dy, zc))
		)


## A low parapet along the front edge of a terrace, so the drop reads as a drop.
## Alternates solid granite stretches with iron railing, which is what happens on
## a real hillside street as walls get replaced piecemeal.
static func edge_parapet(batch: TerrainBatch, z0: float, z1: float, face_x0: float, face_x1: float,
		outward: float, y_top0: float, y_top1: float, seed: int = 0) -> void:
	var run := z1 - z0
	var bays := maxi(1, int(absf(run) / 7.0))
	var step := run / float(bays)
	for i in bays:
		var za := z0 + step * float(i)
		var zb := za + step
		var t := ((za + zb) * 0.5 - z0) / run
		var fx := lerpf(face_x0, face_x1, t)
		var y_top := lerpf(y_top0, y_top1, t)
		if hash01(seed + 41, i) < 0.55:
			batch.dressed().add_box(
				Vector3(0.36, 0.85, absf(step) - 0.08),
				Transform3D(Basis.IDENTITY,
					Vector3(fx - outward * 0.18, y_top + 0.42, (za + zb) * 0.5))
			)
		else:
			var b := batch.iron()
			var rx := fx - outward * 0.16
			var posts := maxi(2, int(absf(step) / 2.2))
			for p in range(posts + 1):
				var z := lerpf(za, zb, float(p) / float(posts))
				b.add_cylinder(0.035, 0.95,
					Transform3D(Basis.IDENTITY, Vector3(rx, y_top + 0.475, z)), 6, false)
			b.add_beam(Vector3(rx, y_top + 0.95, za), Vector3(rx, y_top + 0.95, zb), 0.055)
			b.add_beam(Vector3(rx, y_top + 0.42, za), Vector3(rx, y_top + 0.42, zb), 0.035)
