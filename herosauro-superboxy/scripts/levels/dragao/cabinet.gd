extends Node3D
## The club's glass trophy cabinet, set into the main stand beside the tunnel
## and facing the pitch. Empty when the chapter starts (the goblins took every
## cup); each cup a hero wins back arcs in here, and its shelf lights up.
## Faces +Z; the level places it at Layout.CABINET_POS.

const VC := preload("res://scripts/levels/dragao/vc_baker.gd")
const M := preload("res://scripts/levels/dragao/dragao_mats.gd")
const L := preload("res://scripts/levels/dragao/dragao_layout.gd")

const SHELF_Y := [0.36, 1.46, 2.42]
const SLOT_X := 0.95
const DIM := Color(0.22, 0.2, 0.3)
const LIT := Color(1.0, 0.9, 0.62)

var level = null  # the dragao level (untyped: no cyclic preload)
var _strips: Array[MeshInstance3D] = []
var _glows: Array[MeshInstance3D] = []
var _light: OmniLight3D
var _count: Array[int] = [0, 0, 0]


func _ready() -> void:
	_build()
	reset()


func reset() -> void:
	_count = [0, 0, 0]
	for i in 3:
		_strips[i].material_override = M.flat_lit(DIM)
		_glows[i].visible = false
	_light.light_energy = 0.35


## Slot `i` (0, 1 big cups on the bottom shelf; 2..5 the gold trophies above).
func slot_global(i: int) -> Vector3:
	var shelf := shelf_of(i)
	var x := -SLOT_X if i % 2 == 0 else SLOT_X
	return to_global(Vector3(x, SHELF_Y[shelf] + 0.04, 0.0))


func shelf_of(i: int) -> int:
	return clampi(i / 2, 0, 2)


func filled() -> int:
	return _count[0] + _count[1] + _count[2]


## A cup has landed on slot `i`: light its shelf.
func cup_arrived(i: int) -> void:
	var shelf := shelf_of(i)
	_count[shelf] += 1
	_strips[shelf].material_override = M.flat_lit(LIT)
	_glows[shelf].visible = true
	_light.light_energy = 0.35 + 0.3 * float(filled())
	if level != null:
		level.fx.sparkle(slot_global(i) + Vector3.UP * 0.5, Color(1.0, 0.95, 0.6), 1.2)
	AudioManager.play_sfx(&"star", global_position)


func _build() -> void:
	var w := L.CABINET_W
	var h := L.CABINET_H
	var d := L.CABINET_D
	var b := VC.new()
	var white := Color(0.94, 0.95, 0.98)
	var blue := Color(0.07, 0.3, 0.85)
	b.box(Vector3(w + 0.3, 0.3, d + 0.2), Transform3D(Basis(), Vector3(0, 0.15, 0)), white)
	b.box(Vector3(w + 0.36, 0.3, d + 0.24), Transform3D(Basis(), Vector3(0, h + 0.15, 0)), blue)
	b.box(Vector3(w + 0.4, 0.08, d + 0.28), Transform3D(Basis(), Vector3(0, h + 0.34, 0)), white)
	for sx in [-1.0, 1.0]:
		b.box(Vector3(0.16, h, d), Transform3D(Basis(), Vector3(sx * (w * 0.5 + 0.02), h * 0.5, 0)), white)
	b.box(Vector3(w, h, 0.08), Transform3D(Basis(), Vector3(0, h * 0.5, -d * 0.5 + 0.04)), Color(0.07, 0.11, 0.34))
	for y in SHELF_Y:
		b.box(Vector3(w - 0.05, 0.07, d - 0.12), Transform3D(Basis(), Vector3(0, y - 0.035, -0.02)), white)
	var frame := b.commit(M.skin(), "Frame", true)
	add_child(frame)

	var q := QuadMesh.new()
	q.size = Vector2(w, h - 0.3)
	var glass := MeshInstance3D.new()
	glass.name = "Glass"
	glass.mesh = q
	glass.material_override = M.glass()
	glass.position = Vector3(0, 0.3 + (h - 0.3) * 0.5, d * 0.5)
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glass)

	var strip_mesh := BoxMesh.new()
	strip_mesh.size = Vector3(w - 0.3, 0.05, 0.08)
	var glow_mesh := QuadMesh.new()
	glow_mesh.size = Vector2(w - 0.4, 0.9)
	var tops := [SHELF_Y[1] - 0.1, SHELF_Y[2] - 0.1, h - 0.1]
	for i in 3:
		var s := MeshInstance3D.new()
		s.name = "ShelfLight%d" % i
		s.mesh = strip_mesh
		s.position = Vector3(0, tops[i], d * 0.5 - 0.12)
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(s)
		_strips.append(s)
		var g := MeshInstance3D.new()
		g.name = "ShelfGlow%d" % i
		g.mesh = glow_mesh
		g.material_override = M.halo(Color(1.0, 0.85, 0.55, 0.55))
		g.position = Vector3(0, SHELF_Y[i] + 0.48, -d * 0.5 + 0.1)
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(g)
		_glows.append(g)
	_light = OmniLight3D.new()
	_light.name = "CabinetLight"
	_light.light_color = Color(1.0, 0.88, 0.65)
	_light.omni_range = 7.0
	_light.shadow_enabled = false
	_light.position = Vector3(0, 1.9, d * 0.5 + 0.9)
	add_child(_light)
