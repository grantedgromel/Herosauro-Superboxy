extends SceneTree
## TEMPORARY per-emitter caller audit. Delete after the winding fix lands.

const Flora := preload("res://scripts/world/terrain/flora_kit.gd")
const Quay := preload("res://scripts/world/terrain/quay_kit.gd")
const Rock := preload("res://scripts/world/terrain/rock_kit.gd")
const LGeo := preload("res://scripts/world/landmarks/landmark_geo.gd")
const IronKit := preload("res://scripts/world/bridge/iron_kit.gd")
const DeckKit := preload("res://scripts/world/bridge/deck_kit.gd")


func _initialize() -> void:
	var b := MeshBaker.new()
	Flora.taper(b, Vector3(0, 0, 0), Vector3(0, 2, 0), 1.0, 0.8, 8, 0, 0.0)
	_radial("flora_kit.taper", b, Vector3(0, 1, 0))

	b = MeshBaker.new()
	Flora.blob(b, Vector3(0, 0, 0), Vector3(1, 1, 1), 8, 0, 0.0)
	_radial("flora_kit.blob", b, Vector3.ZERO)

	b = MeshBaker.new()
	Flora.cypress(b, Vector3(0, 0, 0), 4.0, 0.7, 0)
	_radial("flora_kit.cypress", b, Vector3(0, 2, 0))

	b = MeshBaker.new()
	LGeo.revolve(b, Transform3D.IDENTITY,
			PackedVector2Array([Vector2(1.0, 0.0), Vector2(1.0, 2.0)]), 8, true)
	_radial("landmark_geo.revolve(outward)", b, Vector3(0, 1, 0))

	b = MeshBaker.new()
	LGeo.rect(b, Transform3D.IDENTITY, -1.0, 0.0, 1.0, 2.0, 0.0)
	_direction("landmark_geo.rect", b, Vector3(0, 0, 1))

	b = MeshBaker.new()
	LGeo.rect_back(b, Transform3D.IDENTITY, -1.0, 0.0, 1.0, 2.0, 0.0)
	_direction("landmark_geo.rect_back", b, Vector3(0, 0, -1))

	b = MeshBaker.new()
	LGeo.disc(b, Transform3D.IDENTITY, 0.0, 1.0, 0.0, 1.0, 12, true)
	_direction("landmark_geo.disc(face_out)", b, Vector3(0, 0, 1))

	var steel := MeshBaker.new()
	var rust := MeshBaker.new()
	DeckKit.grooved_rail(steel, rust, 0.0, 4.0, 0.72, 0.0, -0.02, 7)
	_up_share("deck_kit.grooved_rail steel", steel)
	_up_share("deck_kit.grooved_rail rust", rust)

	var steel2 := MeshBaker.new()
	var rust2 := MeshBaker.new()
	DeckKit.grooved_rail(steel2, rust2, 0.0, 4.0, -0.72, 0.0, -0.02, 7)
	_up_share("deck_kit.grooved_rail steel (-z)", steel2)

	b = MeshBaker.new()
	IronKit.member(b, PackedVector3Array([Vector3(0, 0, 0), Vector3(4, 0, 0), Vector3(8, 1, 0)]),
			0.3, 0.4, Vector3.UP, true)
	_radial("iron_kit.member", b, Vector3(4, 0.2, 0))

	b = MeshBaker.new()
	Rock.boulder(b, Vector3.ZERO, Vector3(2, 2, 2), 7)
	_radial("rock_kit.boulder", b, Vector3.ZERO)

	quit()


func _tris(b: MeshBaker) -> Array:
	var mi := b.commit(null, "p", false)
	var arrays: Array = (mi.mesh as ArrayMesh).surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var out := []
	for i in range(0, idx.size(), 3):
		var a := verts[idx[i]]
		var c2 := verts[idx[i + 1]]
		var c3 := verts[idx[i + 2]]
		out.append([(a + c2 + c3) / 3.0, norms[idx[i]]])
	mi.free()
	return out


func _radial(label: String, b: MeshBaker, centre: Vector3) -> void:
	var away := 0
	var toward := 0
	for t in _tris(b):
		var d: Vector3 = (t[0] as Vector3) - centre
		d.y = 0.0
		if d.length() < 1e-4:
			continue
		if (t[1] as Vector3).dot(d.normalized()) > 0.0:
			away += 1
		else:
			toward += 1
	print("%-38s outward=%5d INWARD=%5d %s" % [label, away, toward,
			"" if toward == 0 else "  <-- WRONG"])


func _direction(label: String, b: MeshBaker, want: Vector3) -> void:
	var good := 0
	var bad := 0
	for t in _tris(b):
		if (t[1] as Vector3).dot(want) > 0.0:
			good += 1
		else:
			bad += 1
	print("%-38s facing=%5d WRONG=%5d %s" % [label, good, bad, "" if bad == 0 else "  <-- WRONG"])


## Fraction of near-horizontal triangles whose stored normal points up. A deck,
## a rail crown and a groove floor are all up-facing; nothing in a rail profile
## should be a downward-facing horizontal surface except the joint plate.
func _up_share(label: String, b: MeshBaker) -> void:
	var up := 0
	var down := 0
	for t in _tris(b):
		var n: Vector3 = t[1]
		if absf(n.y) > 0.8:
			if n.y > 0.0:
				up += 1
			else:
				down += 1
	print("%-38s flat-up=%5d flat-down=%5d" % [label, up, down])
