extends RefCounted
## What stands ON the quays, as opposed to what holds them up.
##
## MasonryKit builds the walls, copings, steps and bollards; this builds the
## things people put on top of them. Round 1's finding on the Ribeira was that it
## is "the most densely used public space in Porto — wall to wall with cafes,
## umbrellas, tables and crowds — and it is currently an empty grey apron", and
## the same shot showed the Gaia cais as a bare shelf in front of the port lodges.
## Both are true, and both are the RUBRIC's "empty flat ground anywhere the camera
## can see is a defect" at forty metres rather than at four.
##
## Everything here is emitted into TerrainBatch's existing bakers plus one new
## canvas pair, so a hundred parasols and three hundred crates cost a handful of
## draw calls between them. Nothing collides: the player never leaves the deck.
##
## SCALE DISCIPLINE. These are read at 40-110 m from the bridge. A chair back is
## four centimetres of screen at that range, so a chair is one box and a table is
## two; what has to be right is the SPACING and the COLOUR — a rhythm of bright
## canopies with dark gaps between them is what the eye reads as a terrace of
## cafes, and it survives any distance the camera can reach.

const MK := preload("res://scripts/world/terrain/masonry_kit.gd")


## A cafe parasol: mast, a shallow square canopy and its valance.
##
## Square rather than round, which is what the Ribeira actually puts out, and
## which costs four triangles for the canopy against a cone's sixteen. The tilt is
## per-instance — a terrace of perfectly level parasols is a car park.
static func parasol(canvas: MeshBaker, timber: MeshBaker, at: Vector3, radius: float,
		height: float, seed: int) -> void:
	var yaw := MK.hash_sym(seed, 1) * PI
	var tilt := MK.hash_sym(seed + 7, 2) * 0.07
	var xf := Transform3D(Basis(Vector3.UP, yaw), at).rotated_local(Vector3.BACK, tilt)
	timber.add_cylinder(0.045, height, xf * Transform3D(Basis(),
			Vector3(0.0, height * 0.5, 0.0)), 6)
	# Canopy: four panels falling from a peak to the four corners, so it has a
	# ridge and a shadow under it rather than being a flat card.
	var peak := Vector3(0.0, height + 0.16, 0.0)
	var lip := height - 0.10
	var corner: Array[Vector3] = [
		Vector3(-radius, lip, -radius), Vector3(radius, lip, -radius),
		Vector3(radius, lip, radius), Vector3(-radius, lip, radius),
	]
	for i in 4:
		var a: Vector3 = corner[i]
		var b: Vector3 = corner[(i + 1) % 4]
		# b before a: the corners run anticlockwise seen from above, so walking
		# them forward into the peak gives a right-hand normal pointing DOWN, and
		# a canopy shaded from underneath is a black square in a sunlit terrace.
		# The material is culling-disabled, so nothing about this shows in a
		# silhouette — only in the shading, which is exactly the failure mode that
		# is easy to ship.
		canvas.add_quad(xf * b, xf * a, xf * peak, xf * peak, Vector2(radius * 2.0, radius))
		# Valance: the short skirt hanging off each edge, and the reason a canopy
		# reads as cloth and not as a plate.
		canvas.add_quad(xf * a, xf * b, xf * (b - Vector3(0.0, 0.17, 0.0)),
				xf * (a - Vector3(0.0, 0.17, 0.0)), Vector2(radius * 2.0, 0.17))


## A cafe table with two or three chairs round it. Four boxes and a cylinder.
static func cafe_set(timber: MeshBaker, iron: MeshBaker, at: Vector3, seed: int) -> void:
	var yaw := MK.hash_sym(seed, 3) * PI
	var xf := Transform3D(Basis(Vector3.UP, yaw), at)
	iron.add_cylinder(0.035, 0.70, xf * Transform3D(Basis(), Vector3(0.0, 0.35, 0.0)), 5)
	timber.add_box(Vector3(0.62, 0.05, 0.62), xf * Transform3D(Basis(),
			Vector3(0.0, 0.72, 0.0)))
	var chairs := 2 + int(MK.hash01(seed + 11, 1) * 2.0)
	for i in chairs:
		# Pushed out to their own angles and distances, because nobody ever leaves
		# chairs evenly spaced round a table.
		var a := TAU * (float(i) + MK.hash01(seed + 3, i) * 0.7) / float(chairs)
		var r := 0.62 + MK.hash01(seed + 5, i) * 0.18
		var seat := xf * Transform3D(Basis(Vector3.UP, -a),
				Vector3(cos(a) * r, 0.0, sin(a) * r))
		iron.add_box(Vector3(0.34, 0.04, 0.34), seat * Transform3D(Basis(),
				Vector3(0.0, 0.44, 0.0)))
		iron.add_box(Vector3(0.34, 0.42, 0.04), seat * Transform3D(Basis(),
				Vector3(0.0, 0.65, -0.16)))


## A stack of port pipes on the Gaia cais: two or three courses of barrels lying
## on their sides, chocked, the way a lodge yard actually stores them.
static func barrel_stack(timber: MeshBaker, iron: MeshBaker, at: Vector3, along: Vector3,
		courses: int, per_course: int, seed: int) -> void:
	var across := along.cross(Vector3.UP).normalized()
	const R := 0.42
	for c in courses:
		var n := per_course - c
		if n <= 0:
			break
		for i in n:
			var offset := across * ((float(i) - float(n - 1) * 0.5) * R * 2.05)
			var pos := at + offset + Vector3.UP * (R + float(c) * R * 1.78)
			# Lying down, axis along `along`.
			var basis := Basis()
			basis.y = along
			basis.x = across
			basis.z = across.cross(along).normalized()
			var xf := Transform3D(basis, pos)
			timber.add_cylinder(R, 1.05, xf, 8)
			# Two hoops. On a 40 m read they are the only thing separating a
			# barrel from a log.
			for sh: float in [-0.3, 0.3]:
				iron.add_cylinder(R * 1.04, 0.07,
						xf * Transform3D(Basis(), Vector3(0.0, sh, 0.0)), 8)


## A stack of crates, each with its own yaw and a shallow lean, because a stack
## somebody made by hand is never square.
static func crate_stack(timber: MeshBaker, at: Vector3, size: float, count: int,
		seed: int) -> void:
	var y := 0.0
	for i in count:
		var s := size * (0.82 + MK.hash01(seed, i) * 0.36)
		var h := s * (0.62 + MK.hash01(seed + 2, i) * 0.3)
		var xf := Transform3D(Basis(Vector3.UP, MK.hash_sym(seed + 4, i) * 0.5),
				at + Vector3(MK.hash_sym(seed + 6, i) * s * 0.18, y + h * 0.5,
					MK.hash_sym(seed + 8, i) * s * 0.18))
		timber.add_box(Vector3(s, h, s * 0.86), xf)
		y += h


## A fixed awning over a shopfront: a sloping sheet on two struts, running along
## the building line.
static func awning(canvas: MeshBaker, iron: MeshBaker, at: Vector3, along: Vector3,
		width: float, reach: float, outward: Vector3) -> void:
	var half := along * width * 0.5
	var lip := outward * reach - Vector3.UP * 0.42
	# Which way round the four corners go depends on the sign of `along` against
	# `outward`, and the caller sets both — so it is decided here from the normal
	# that comes out rather than assumed, and the sheet faces up on either bank.
	var a := at - half
	var b := at + half
	if (b - a).cross(b + lip - a).y >= 0.0:
		canvas.add_quad(a, b, b + lip, a + lip, Vector2(width, reach))
	else:
		canvas.add_quad(b, a, a + lip, b + lip, Vector2(width, reach))
	for s: float in [-1.0, 1.0]:
		iron.add_beam(at + half * s, at + half * s + lip, 0.03)


## The big iron sign frames that name the Gaia bank.
##
## Standing lattice frames carrying block letters, which is what the port houses
## put on their roofs and hillside and what makes that bank instantly Porto from
## anywhere on the river. Letters come from LandmarksBuilder's 5x7 alphabet, so
## there is one font in the project and it is geometry rather than a Label3D that
## would turn to face the camera.
static func hillside_sign(board: MeshBaker, iron: MeshBaker, face: MeshBaker, at: Vector3,
		yaw: float, text: String, cell: float) -> void:
	var xf := Transform3D(Basis(Vector3.UP, yaw), at)
	var chars := maxi(1, text.length())
	var text_w := float(chars) * cell * 6.0
	var hw := text_w * 0.5 + cell * 1.6
	var sill := cell * 1.0
	var top := sill + cell * 9.0
	var legs := maxi(2, int(hw * 2.0 / 4.5))

	for i in range(legs + 1):
		var px := lerpf(-hw, hw, float(i) / float(legs))
		iron.add_beam(xf * Vector3(px, 0.0, 0.0), xf * Vector3(px, top, 0.0), 0.14)
		# Raking back-stay, so the frame stands up rather than being pasted on.
		iron.add_beam(xf * Vector3(px, top * 0.72, 0.0),
				xf * Vector3(px, 0.0, -top * 0.5), 0.09)
	for ty: float in [sill, top]:
		iron.add_beam(xf * Vector3(-hw, ty, 0.0), xf * Vector3(hw, ty, 0.0), 0.12)

	# A solid ground behind the letters, not an open frame.
	#
	# The real hoardings are open steelwork with the sky through them, and the
	# first version of this was too — which at ninety metres, seen against a
	# terrace of white sheds, resolved to a small dark smudge with no letters in
	# it at all. Light lettering needs something dark immediately behind it or the
	# glyphs have nothing to be light AGAINST, and a board is what a painted sign
	# is anyway once it has been repainted a few times.
	board.add_box(Vector3(hw * 2.0, top - sill, 0.10),
			xf * Transform3D(Basis(), Vector3(0.0, (sill + top) * 0.5, -0.05)))

	LandmarksBuilder.sign_text(face, xf, text, -text_w * 0.5 + cell * 0.5,
			sill + cell * 1.0, cell)
