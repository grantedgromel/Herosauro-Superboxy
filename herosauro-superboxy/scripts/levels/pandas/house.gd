extends Node3D
## A narrow Porto townhouse with two looks, both baked once at load:
##
##   BROKEN   grey cracked plaster, boarded windows, a shutter hanging off one
##            hinge, planks nailed across the door, missing roof tiles, rusty
##            railings, and a rubbish heap in front;
##   REPAIRED bright paint, blue-and-white azulejos, open shutters, flower boxes,
##            warm lit windows, a lantern by the door.
##
## The heap (rubbish_pile.gd) lights the door star (door_star.gd) when cleared.
## Three hits on the star repair the house (Dino Energy counts as two), and each
## hit fixes a little part first: hit one straightens the hanging shutter, hit
## two knocks the door planks off, hit three is the transformation: a ring of
## green sparkles sweeps up the facade, the house pops (squash and stretch),
## the looks swap, petals fly and the magic_repair sound plays.
##
## Local frame: the facade is the z = 0 plane facing +Z, x across, ground y = 0.
## The level owns the tall collider behind the facade (off the camera's layer).

signal repaired(house: Node3D)
signal step_fixed(house: Node3D, hits: int)

const Kit := preload("res://scripts/levels/pandas/pandas_kit.gd")
const MagicFX := preload("res://scripts/levels/pandas/magic_fx.gd")
const DoorStar := preload("res://scripts/levels/pandas/door_star.gd")
const RubbishPile := preload("res://scripts/levels/pandas/rubbish_pile.gd")

const GF := 3.6          # ground floor height
const FH := 3.0          # upper floor height
const PIL := 0.42        # granite corner pilasters
const DOOR_W := 1.3
const DOOR_H := 2.5
const WIN_W := 1.05
const WIN_H := 1.95
const STAR_Z := 0.95
const PILE_Z := 2.7
const SWAP_AT := 0.5     # seconds into the transformation the looks swap
const BALCONY_TOP := 1.8

# --- Config, set by the level before add_child ----------------------------------
var index: int = 0
var width: float = 6.4
var floors: int = 3
var paint := Color(0.95, 0.66, 0.6)
var shutter_paint := Color(0.2, 0.55, 0.45)
var door_paint := Color(0.2, 0.45, 0.8)
var tile_style: int = 0
var tile_layout: int = 0       # 0 upper facade, 1 ground floor + frieze, 2 everything
var pile_size: int = 1
var door_side: float = -1.0
var low_balcony: bool = false
var has_door_leaf: bool = false
var rng_seed: int = 1

var star: Node3D
var pile: Node3D

var _visual: Node3D
var _broken: Node3D
var _fixed: Node3D
var _hanging: MeshInstance3D
var _hanging_rest := Vector3(0.18, 0.0, -0.75)
var _planks: MeshInstance3D
var _planks_rest := Transform3D.IDENTITY
var _door_leaf: Node3D
var _repaired: bool = false
var _anim_t: float = -1.0
var _swapped: bool = false
var _shutter_t: float = -1.0
var _plank_t: float = -1.0
var _plank_v := Vector3.ZERO
var _pending_planks: float = -1.0
var _pop: float = 0.0
var _pop_v: float = 0.0
var _door_open: float = 0.0
var _door_open_target: float = 0.0
var _h: float = 9.6
var _inner: float = 5.5
var _door_x: float = 0.0
var _shop_x: float = 0.0
var _twinkle_local: Array[Vector3] = []
var build_tris: int = 0


func _ready() -> void:
	_h = GF + FH * float(floors - 1)
	_inner = width - 2.0 * PIL
	_door_x = _inner * 0.25 * door_side
	_shop_x = -_door_x
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	_broken = _build_look(true)
	_broken.name = "Broken"
	_visual.add_child(_broken)
	_fixed = _build_look(false)
	_fixed.name = "Repaired"
	_visual.add_child(_fixed)
	if low_balcony:
		var slab := Vector3(2.3, 0.24, 1.25)
		SceneryKit.solid(self, "BalconyCollider", slab,
			Vector3(_shop_x, BALCONY_TOP - slab.y * 0.5, slab.z * 0.5))

	star = DoorStar.new()
	star.name = "DoorStar"
	star.position = Vector3(_door_x, 0.0, STAR_Z)
	add_child(star)
	star.struck.connect(_on_star_struck)
	pile = RubbishPile.new()
	pile.name = "Rubbish"
	pile.size = pile_size
	pile.rng_seed = rng_seed * 7 + 3
	pile.position = Vector3(_door_x + 0.2 * door_side, 0.0, PILE_Z)
	add_child(pile)
	pile.cleared.connect(_on_pile_cleared)
	reset()


func reset() -> void:
	_repaired = false
	_anim_t = -1.0
	_swapped = false
	_shutter_t = -1.0
	_plank_t = -1.0
	_pending_planks = -1.0
	_pop = 0.0
	_pop_v = 0.0
	_door_open = 0.0
	_door_open_target = 0.0
	_visual.scale = Vector3.ONE
	_broken.visible = true
	_fixed.visible = false
	_hanging.visible = true
	_hanging.rotation = _hanging_rest
	_planks.visible = true
	_planks.transform = _planks_rest
	_planks.scale = Vector3.ONE
	if _door_leaf:
		_door_leaf.rotation.y = 0.0
	star.reset()
	pile.reset()


func is_repaired() -> bool:
	return _repaired


func height() -> float:
	return _h


## Where the hero should stand to work on this house, and what to look at.
func work_point() -> Vector3:
	if not pile.is_cleared():
		return pile.global_position
	return star.global_position


## The top of the low balcony (a suitcase spot), in global space.
func balcony_spot() -> Vector3:
	return to_global(Vector3(_shop_x, BALCONY_TOP, 0.55))


func door_point() -> Vector3:
	return to_global(Vector3(_door_x, 0.0, 0.0))


## Facade points for the level's twinkles once repaired.
func twinkle_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for p in _twinkle_local:
		out.append(to_global(p))
	return out


func open_door(on: bool) -> void:
	_door_open_target = 1.0 if on else 0.0


# --- Progress --------------------------------------------------------------------

func _on_pile_cleared(_p: Node3D) -> void:
	star.light_up()


func _on_star_struck(steps: int) -> void:
	var hits: int = star.hits()
	if hits >= 1 and _shutter_t < 0.0 and _hanging.rotation != Vector3.ZERO:
		_shutter_t = 0.0
		MagicFX.burst(self, _hanging.global_position, Color(0.5, 1.0, 0.45), 12, 3.0, rng_seed + 41)
	if hits >= 2 and _plank_t < 0.0 and _pending_planks < 0.0:
		_pending_planks = 0.0 if steps == 1 else 0.25
	if hits >= 3 and not _repaired:
		_begin_transformation()
	step_fixed.emit(self, hits)


func _begin_transformation() -> void:
	_repaired = true
	_anim_t = 0.0
	_swapped = false
	star.finish()
	var foot := to_global(Vector3(0.0, 0.0, 0.7))
	MagicFX.ring(self, foot, global_rotation.y, width * 0.5 + 0.7, 1.1, _h + 2.4, 1.0, rng_seed + 5)
	MagicFX.burst(self, star.global_position + Vector3.UP * 1.7, Color(1.0, 0.9, 0.35), 30, 6.0,
		rng_seed + 9, 0.2)
	AudioManager.play_sfx(&"magic_repair", foot)
	GameManager.request_shake(0.22, 0.25)
	repaired.emit(self)


func _physics_process(delta: float) -> void:
	if _shutter_t >= 0.0:
		_shutter_t += delta
		var k := clampf(_shutter_t / 0.55, 0.0, 1.0)
		_hanging.rotation = _hanging_rest * _elastic_out(k)
		if k >= 1.0:
			_hanging.rotation = Vector3.ZERO
			_shutter_t = -1.0
	if _pending_planks >= 0.0:
		_pending_planks -= delta
		if _pending_planks < 0.0:
			_pending_planks = -1.0
			_plank_t = 0.0
			_plank_v = Vector3(0.6 * door_side, 2.5, 3.2)
			ImpactFX.spark(self, _planks.global_position, Vector3.BACK, ToonFactory.Surface.WOOD, 1.0)
			AudioManager.play_prop_hit(ToonFactory.Surface.WOOD, _planks.global_position)
	if _plank_t >= 0.0:
		_plank_t += delta
		_plank_v.y -= 18.0 * delta
		var p := _planks.position + _plank_v * delta
		if p.y < 0.2:
			p.y = 0.2
			_plank_v = Vector3(_plank_v.x * 0.5, absf(_plank_v.y) * 0.3, _plank_v.z * 0.5)
		_planks.position = p
		_planks.rotate_object_local(Vector3.RIGHT, 2.5 * delta)
		if _plank_t > 0.9:
			_planks.scale = Vector3.ONE * maxf(0.001, 1.0 - (_plank_t - 0.9) / 0.3)
		if _plank_t > 1.2:
			_planks.visible = false
			_plank_t = -1.0
	if _anim_t >= 0.0:
		_anim_t += delta
		if not _swapped and _anim_t >= SWAP_AT:
			_swap_to_repaired()
		if _anim_t > 3.0:
			_anim_t = -1.0
	# The pop: a spring, kicked when the looks swap.
	if absf(_pop) > 0.0005 or absf(_pop_v) > 0.0005:
		_pop_v += (-160.0 * _pop - 9.0 * _pop_v) * delta
		_pop += _pop_v * delta
		var s := clampf(_pop, -0.35, 0.35)
		_visual.scale = Vector3(1.0 - s * 0.45, 1.0 + s, 1.0 - s * 0.45)
	elif _visual.scale != Vector3.ONE:
		_visual.scale = Vector3.ONE
	if _door_leaf and absf(_door_open - _door_open_target) > 0.001:
		_door_open = move_toward(_door_open, _door_open_target, delta * 1.5)
		_door_leaf.rotation.y = -1.6 * door_side * _door_open * (2.0 - _door_open) * 0.9


func _swap_to_repaired() -> void:
	_swapped = true
	_broken.visible = false
	_fixed.visible = true
	_hanging.visible = false
	_planks.visible = false
	_plank_t = -1.0
	_pop = -0.22
	_pop_v = 3.2
	MagicFX.petals(self, to_global(Vector3(0.0, 0.0, 0.4)), global_rotation.y, width, _h, rng_seed + 17)
	AudioManager.play_land()


static func _elastic_out(k: float) -> float:
	# 1 -> 0 with one small overshoot: the shutter swings past straight and settles.
	if k >= 1.0:
		return 0.0
	return (1.0 - k) * cos(k * PI * 2.5) * (1.0 - k * 0.3)


# --- Build -----------------------------------------------------------------------

func _build_look(broken: bool) -> Node3D:
	var root := Node3D.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed * 1009 + (1 if broken else 2)
	var body := Kit.VBaker.new()
	var trim := Kit.VBaker.new()
	var roof := Kit.VBaker.new()
	var tiles := Kit.VBaker.new()
	var glow := Kit.VBaker.new()

	var wall := paint
	var granite := Color(0.84, 0.82, 0.77)
	var shutter := shutter_paint
	var door := door_paint
	var roof_c := Color(0.86, 0.4, 0.26)
	var iron := Color(0.14, 0.16, 0.2)
	var glass := Color(0.12, 0.13, 0.17)
	if broken:
		# Grey, cracked, with a faded ghost of the colour it will be.
		var g := rng.randf_range(-0.03, 0.03)
		wall = Color(0.56 + g, 0.54 + g, 0.51 + g).lerp(paint, 0.2)
		granite = Color(0.56, 0.55, 0.53)
		shutter = Color(0.46, 0.5, 0.46)
		door = Color(0.4, 0.32, 0.26)
		roof_c = Color(0.6, 0.42, 0.35)
		iron = Color(0.45, 0.3, 0.22)

	var w := width
	var h := _h
	var inner := _inner
	# Body block (the facade face is its +Z side) and a chimney.
	body.box(Vector3(w, h, 8.0), Vector3(0.0, h * 0.5, -4.0), wall)
	body.box(Vector3(0.62, 1.7, 0.62), Vector3(w * 0.27 * -door_side, h + 2.0, -2.6), wall.lightened(0.1))
	roof.box(Vector3(0.78, 0.16, 0.78), Vector3(w * 0.27 * -door_side, h + 2.9, -2.6), roof_c.darkened(0.1))
	# Granite: pilasters, plinth, floor bands, cornice.
	for sx: float in [-1.0, 1.0]:
		trim.box(Vector3(PIL, h, 0.18), Vector3(sx * (w * 0.5 - PIL * 0.5), h * 0.5, 0.09), granite)
	trim.box(Vector3(w, 0.5, 0.14), Vector3(0.0, 0.25, 0.07), granite.darkened(0.08))
	for f in floors - 1:
		trim.box(Vector3(w, 0.2, 0.16), Vector3(0.0, GF + FH * float(f), 0.08), granite)
	trim.box(Vector3(w + 0.08, 0.32, 0.42), Vector3(0.0, h + 0.1, 0.13), granite)
	trim.box(Vector3(w + 0.18, 0.14, 0.52), Vector3(0.0, h + 0.33, 0.18), granite.lightened(0.05))
	if broken:
		# Chipped cornice: a missing block.
		body.box(Vector3(0.7, 0.3, 0.1), Vector3(w * 0.18 * door_side, h + 0.12, 0.32), Color(0.4, 0.37, 0.35))

	# Roof, with tile courses; broken ones have holes and a slipped tile.
	var slope := atan2(2.3, 3.7)
	roof.prism(w + 0.3, 2.3, 7.4, Transform3D(Basis(), Vector3(0.0, h + 0.4, -3.3)), roof_c)
	for k in 7:
		var t := (float(k) + 0.6) / 7.0
		var c := Vector3(0.0, h + 0.4 + t * 2.3 + 0.03, 0.4 - t * 3.7)
		roof.box(Vector3(w + 0.3, 0.07, 0.16), c, roof_c.darkened(0.12 if k % 2 == 0 else 0.04),
			Vector3(slope, 0.0, 0.0))
	if broken:
		for k in 4:
			var t := rng.randf_range(0.15, 0.8)
			var c := Vector3(rng.randf_range(-w * 0.35, w * 0.35), h + 0.4 + t * 2.3 + 0.06, 0.4 - t * 3.7)
			roof.box(Vector3(rng.randf_range(0.6, 1.1), 0.05, 0.6), c, Color(0.16, 0.12, 0.11), Vector3(slope, 0.0, 0.0))
		roof.box(Vector3(0.42, 0.05, 0.3), Vector3(-w * 0.2, h + 0.45, 0.42), roof_c.darkened(0.2),
			Vector3(slope, 0.4, 0.5))

	# --- Ground floor: door and shop window (or the low balcony). ---
	var holes: Array[Rect2] = []
	_door(body, trim, glow, broken, door, granite, glass, holes)
	if low_balcony:
		_low_balcony(body, trim, glow, tiles, broken, granite, iron, glass, wall, holes, rng)
	else:
		_window(body, trim, glow, broken, Vector2(_shop_x, 0.7), Vector2(1.55, 2.05), granite, glass,
			shutter, false, holes, rng)

	# --- Upper floors. ---
	var cols := [-inner * 0.25, inner * 0.25]
	var hanging_done := false
	for f in range(1, floors):
		var fy := GF + FH * float(f - 1)
		if f == 1:
			_balcony(body, trim, broken, fy, inner, granite, iron, rng)
		for ci in 2:
			var x: float = cols[ci]
			var wy := fy + 0.6
			_window(body, trim, glow, broken, Vector2(x, wy), Vector2(WIN_W, WIN_H), granite, glass,
				shutter, true, holes, rng)
			if f > 1:
				_juliet(body, trim, broken, Vector2(x, wy), granite, iron, rng)
			if broken and not hanging_done and f == 1 and ci == (0 if door_side > 0 else 1):
				hanging_done = true
				_make_hanging(Vector2(x, wy), shutter)

	if broken:
		_dilapidate(body, rng, holes)
	else:
		_azulejos(tiles, holes)
		_twinkle_local = [Vector3(-w * 0.35, h + 0.5, 0.45), Vector3(w * 0.3, GF + 1.2, 0.85),
			Vector3(_door_x, DOOR_H + 0.6, 0.4)]

	build_tris += body.triangle_count() + trim.triangle_count() + roof.triangle_count() \
		+ tiles.triangle_count() + glow.triangle_count()
	var mi: MeshInstance3D = body.bake(Kit.vc("plaster"), "Body")
	root.add_child(mi)
	root.add_child(trim.bake(Kit.vc("stone"), "Granite"))
	# The body block already throws the row's shadow; the roof's adds nothing
	# the street can see, so it is spared the shadow pass.
	root.add_child(roof.bake(Kit.vc("roof"), "Roof", false))
	if not tiles.is_empty():
		root.add_child(tiles.bake(Kit.azulejo(tile_style), "Azulejos", false))
	if not glow.is_empty():
		root.add_child(glow.bake(Kit.window_glow(), "Windows", false))
	if broken:
		_make_planks(root)
	elif has_door_leaf:
		_make_door_leaf(root)
	return root


## The door, its granite surround and fanlight. Broken: dull wood (the planks are
## a separate mesh so they can fall off). Repaired: bright paint, panels, a brass
## knob, a lantern beside it.
func _door(body: Kit.VBaker, trim: Kit.VBaker, glow: Kit.VBaker, broken: bool, door: Color,
		granite: Color, glass: Color, holes: Array[Rect2]) -> void:
	var x := _door_x
	var top := DOOR_H + 0.27
	for sx: float in [-1.0, 1.0]:
		trim.box(Vector3(0.24, top + 0.05, 0.2), Vector3(x + sx * (DOOR_W * 0.5 + 0.12), (top + 0.05) * 0.5, 0.1), granite)
	trim.box(Vector3(DOOR_W + 0.74, 0.32, 0.24), Vector3(x, top + 0.16, 0.12), granite)
	trim.box(Vector3(DOOR_W + 0.3, 0.06, 0.5), Vector3(x, 0.03, 0.25), granite.darkened(0.1))
	holes.append(Rect2(x - DOOR_W * 0.5 - 0.26, 0.0, DOOR_W + 0.52, top + 0.34))
	if not (has_door_leaf and not broken):
		body.box(Vector3(DOOR_W, DOOR_H, 0.08), Vector3(x, DOOR_H * 0.5, 0.03), door)
		for py: float in [0.75, 1.75]:
			for px: float in [-0.3, 0.3]:
				body.box(Vector3(DOOR_W * 0.34, 0.75, 0.04), Vector3(x + px, py, 0.08),
					door.lightened(0.12) if not broken else door.darkened(0.08))
	if broken:
		body.box(Vector3(DOOR_W, 0.25, 0.05), Vector3(x, DOOR_H + 0.13, 0.03), glass)
	else:
		glow.box(Vector3(DOOR_W, 0.25, 0.05), Vector3(x, DOOR_H + 0.13, 0.03), Color.WHITE)
		if not has_door_leaf:
			body.box(Vector3(0.09, 0.09, 0.06), Vector3(x + 0.4 * -door_side, 1.15, 0.12), Color(0.95, 0.75, 0.25))
		# Lantern beside the door.
		var lx := x + door_side * (DOOR_W * 0.5 + 0.55)
		body.box(Vector3(0.06, 0.06, 0.34), Vector3(lx, 2.75, 0.17), Color(0.12, 0.13, 0.15))
		body.box(Vector3(0.3, 0.08, 0.3), Vector3(lx, 2.92, 0.36), Color(0.12, 0.13, 0.15))
		body.box(Vector3(0.24, 0.06, 0.24), Vector3(lx, 2.5, 0.36), Color(0.12, 0.13, 0.15))
		glow.box(Vector3(0.2, 0.36, 0.2), Vector3(lx, 2.71, 0.36), Color.WHITE)
		# A house-number tile.
		body.box(Vector3(0.3, 0.22, 0.03), Vector3(x - door_side * (DOOR_W * 0.5 + 0.5), 2.2, 0.02),
			Color(0.95, 0.95, 0.98))
		body.box(Vector3(0.1, 0.14, 0.02), Vector3(x - door_side * (DOOR_W * 0.5 + 0.5), 2.2, 0.04),
			Color(0.15, 0.3, 0.7))


## A window: granite frame, sill and cap, glass (lit when repaired), mullions,
## shutters (open and painted when repaired; closed, missing or boarded when broken).
func _window(body: Kit.VBaker, trim: Kit.VBaker, glow: Kit.VBaker, broken: bool, at: Vector2,
		size: Vector2, granite: Color, glass: Color, shutter: Color, shutters: bool,
		holes: Array[Rect2], rng: RandomNumberGenerator) -> void:
	var x := at.x
	var y0 := at.y
	var ww := size.x
	var wh := size.y
	var fr := 0.14
	trim.box(Vector3(ww + fr * 2.0, fr, 0.17), Vector3(x, y0 + wh + fr * 0.5, 0.085), granite)
	trim.box(Vector3(fr, wh, 0.17), Vector3(x - ww * 0.5 - fr * 0.5, y0 + wh * 0.5, 0.085), granite)
	trim.box(Vector3(fr, wh, 0.17), Vector3(x + ww * 0.5 + fr * 0.5, y0 + wh * 0.5, 0.085), granite)
	trim.box(Vector3(ww + 0.36, 0.1, 0.28), Vector3(x, y0 - 0.05, 0.14), granite)
	trim.box(Vector3(ww + 0.34, 0.12, 0.22), Vector3(x, y0 + wh + fr + 0.06, 0.11), granite.lightened(0.04))
	holes.append(Rect2(x - ww * 0.5 - fr - 0.04, y0 - 0.12, ww + fr * 2.0 + 0.08, wh + fr + 0.32))
	var frame_c := Color(0.96, 0.95, 0.9) if not broken else Color(0.5, 0.46, 0.42)
	if broken:
		body.box(Vector3(ww, wh, 0.04), Vector3(x, y0 + wh * 0.5, 0.03), glass)
	else:
		glow.box(Vector3(ww, wh, 0.04), Vector3(x, y0 + wh * 0.5, 0.03), Color.WHITE)
	body.box(Vector3(0.05, wh, 0.05), Vector3(x, y0 + wh * 0.5, 0.06), frame_c)
	body.box(Vector3(ww, 0.05, 0.05), Vector3(x, y0 + wh * 0.62, 0.06), frame_c)
	if not shutters:
		if broken:
			_boards(body, Vector2(x, y0 + wh * 0.5), Vector2(ww, wh), rng)
		return
	var leaf := Vector2(ww * 0.5, wh)
	if broken:
		var state := rng.randi_range(0, 3)
		if state == 0:
			_boards(body, Vector2(x, y0 + wh * 0.5), Vector2(ww, wh), rng)
		elif state == 1:
			# Closed and faded, one slat broken.
			for sx: float in [-1.0, 1.0]:
				body.box(Vector3(leaf.x - 0.02, leaf.y, 0.05), Vector3(x + sx * leaf.x * 0.5, y0 + wh * 0.5, 0.09), shutter)
			body.box(Vector3(leaf.x * 0.8, 0.12, 0.03), Vector3(x + leaf.x * 0.5, y0 + wh * 0.3, 0.12), Color(0.1, 0.1, 0.12))
		elif state == 2:
			# One leaf left, crooked.
			body.box(Vector3(leaf.x, leaf.y, 0.05), Vector3(x - ww * 0.5 - 0.16 - leaf.x * 0.5, y0 + wh * 0.5, 0.05),
				shutter, Vector3(0.0, 0.0, 0.08))
		return
	for sx: float in [-1.0, 1.0]:
		var cx := x + sx * (ww * 0.5 + 0.17 + leaf.x * 0.5)
		body.box(Vector3(leaf.x, leaf.y, 0.05), Vector3(cx, y0 + wh * 0.5, 0.03), shutter)
		for k in 4:
			body.box(Vector3(leaf.x - 0.1, 0.04, 0.03), Vector3(cx, y0 + wh * (0.18 + 0.21 * float(k)), 0.065),
				shutter.darkened(0.18))


func _boards(body: Kit.VBaker, c: Vector2, size: Vector2, rng: RandomNumberGenerator) -> void:
	var wood := Color(0.62, 0.52, 0.4)
	for k in 3:
		var y := c.y + (float(k) - 1.0) * size.y * 0.3
		body.box(Vector3(size.x + 0.3, 0.16, 0.04), Vector3(c.x, y, 0.13), wood.darkened(0.06 * float(k)),
			Vector3(0.0, 0.0, rng.randf_range(-0.25, 0.25)))


## The long iron balcony across the first floor.
func _balcony(body: Kit.VBaker, trim: Kit.VBaker, broken: bool, fy: float, inner: float,
		granite: Color, iron: Color, rng: RandomNumberGenerator) -> void:
	var bw := inner + 0.1
	var d := 0.8
	trim.box(Vector3(bw, 0.14, d), Vector3(0.0, fy + 0.07, d * 0.5), granite)
	for k in 3:
		var x := (float(k) - 1.0) * bw * 0.4
		trim.box(Vector3(0.2, 0.32, 0.5), Vector3(x, fy - 0.16, 0.26), granite.darkened(0.06))
	var top := fy + 1.02
	var sag := 0.12 if broken else 0.0
	body.box(Vector3(bw, 0.06, 0.07), Vector3(0.0, top - sag * 0.5, d - 0.04), iron, Vector3(0.0, 0.0, 0.03 if broken else 0.0))
	body.box(Vector3(bw, 0.05, 0.05), Vector3(0.0, fy + 0.22, d - 0.04), iron)
	for sx: float in [-1.0, 1.0]:
		body.box(Vector3(0.05, 0.05, d), Vector3(sx * (bw * 0.5 - 0.03), top, d * 0.5), iron)
		body.box(Vector3(0.05, 0.85, 0.05), Vector3(sx * (bw * 0.5 - 0.03), fy + 0.6, d - 0.04), iron)
	var bars := int(bw / 0.17)
	for k in bars:
		if broken and rng.randf() < 0.3:
			continue
		var x := -bw * 0.5 + (float(k) + 0.5) * bw / float(bars)
		var lean := rng.randf_range(-0.15, 0.15) if broken else 0.0
		body.box(Vector3(0.03, 0.78, 0.03), Vector3(x, fy + 0.6, d - 0.04), iron, Vector3(0.0, 0.0, lean))
		if not broken and k % 3 == 1:
			# Little curls on every third bar.
			body.box(Vector3(0.14, 0.03, 0.03), Vector3(x, fy + 0.85, d - 0.04), iron, Vector3(0.0, 0.0, 0.6))
	if not broken:
		var n := 3 + int(bw > 5.0)
		for k in n:
			var x := -bw * 0.5 + (float(k) + 0.5) * bw / float(n)
			_pot(body, Vector3(x, fy + 0.14, 0.3), rng)


## A small balcony under an upper window, with a flower box when repaired.
func _juliet(body: Kit.VBaker, trim: Kit.VBaker, broken: bool, at: Vector2, granite: Color,
		iron: Color, rng: RandomNumberGenerator) -> void:
	var bw := WIN_W + 0.5
	trim.box(Vector3(bw, 0.1, 0.44), Vector3(at.x, at.y - 0.1, 0.22), granite)
	body.box(Vector3(bw, 0.05, 0.05), Vector3(at.x, at.y + 0.75, 0.42), iron,
		Vector3(0.0, 0.0, rng.randf_range(-0.12, 0.12) if broken else 0.0))
	for k in 6:
		if broken and k == 2:
			continue
		var x := at.x - bw * 0.5 + (float(k) + 0.5) * bw / 6.0
		body.box(Vector3(0.03, 0.8, 0.03), Vector3(x, at.y + 0.35, 0.42), iron)
	if not broken:
		body.box(Vector3(WIN_W + 0.2, 0.26, 0.26), Vector3(at.x, at.y + 0.08, 0.24), Color(0.62, 0.36, 0.22))
		_flowers(body, Vector3(at.x, at.y + 0.22, 0.24), WIN_W + 0.1, rng)


## The low balcony a hero can jump onto (a suitcase spot), in place of the shop
## window. Granite slab on corbels, railing at the sides, a balcony door above.
func _low_balcony(body: Kit.VBaker, trim: Kit.VBaker, glow: Kit.VBaker, tiles: Kit.VBaker,
		broken: bool, granite: Color, iron: Color, glass: Color, wall: Color,
		holes: Array[Rect2], rng: RandomNumberGenerator) -> void:
	var x := _shop_x
	var top := BALCONY_TOP
	trim.box(Vector3(2.3, 0.24, 1.25), Vector3(x, top - 0.12, 0.625), granite)
	for sx: float in [-0.8, 0.0, 0.8]:
		trim.box(Vector3(0.24, 0.6, 0.9), Vector3(x + sx, top - 0.54, 0.45), granite.darkened(0.08))
	for sx: float in [-1.0, 1.0]:
		body.box(Vector3(0.05, 0.05, 1.2), Vector3(x + sx * 1.12, top + 0.85, 0.62), iron)
		for k in 4:
			body.box(Vector3(0.03, 0.85, 0.03), Vector3(x + sx * 1.12, top + 0.42, 0.1 + float(k) * 0.33), iron)
	# Balcony door above the slab.
	_window(body, trim, glow, broken, Vector2(x, top + 0.05), Vector2(1.0, 1.45), granite, glass,
		shutter_paint if not broken else Color(0.46, 0.5, 0.46), false, holes, rng)
	# A small cellar window below.
	trim.box(Vector3(0.9, 0.62, 0.12), Vector3(x, 0.75, 0.06), granite)
	body.box(Vector3(0.7, 0.44, 0.05), Vector3(x, 0.75, 0.1), Color(0.1, 0.1, 0.12))
	holes.append(Rect2(x - 1.2, 0.0, 2.4, top + 0.15))
	if not broken:
		_pot(body, Vector3(x - 0.85, top, 1.0), rng)
		_pot(body, Vector3(x + 0.85, top, 1.0), rng)


func _pot(body: Kit.VBaker, at: Vector3, rng: RandomNumberGenerator) -> void:
	body.cyl(0.17, 0.3, Transform3D(Basis(), at + Vector3(0.0, 0.15, 0.0)), Color(0.78, 0.4, 0.24), 8)
	_flowers(body, at + Vector3(0.0, 0.32, 0.0), 0.36, rng)


## A tuft of leaves with bright blossoms on top.
func _flowers(body: Kit.VBaker, at: Vector3, span: float, rng: RandomNumberGenerator) -> void:
	var palette := [Color(0.95, 0.25, 0.35), Color(1.0, 0.55, 0.75), Color(1.0, 0.85, 0.25),
		Color(0.98, 0.98, 0.95), Color(0.7, 0.45, 0.95), Color(1.0, 0.5, 0.2)]
	var leaves := maxi(2, int(span / 0.28))
	for k in leaves:
		var x := -span * 0.5 + (float(k) + 0.5) * span / float(leaves)
		body.blob(Vector3(0.16, 0.12, 0.13), Transform3D(Basis(), at + Vector3(x, 0.05, rng.randf_range(-0.04, 0.04))),
			Color(0.28, 0.6, 0.28).lerp(Color(0.4, 0.7, 0.3), rng.randf()), 6, 4)
	var blooms := leaves + 2
	var tone: Color = palette[rng.randi_range(0, palette.size() - 1)]
	for k in blooms:
		var x := rng.randf_range(-span * 0.5, span * 0.5)
		var c := tone if rng.randf() < 0.65 else (palette[rng.randi_range(0, palette.size() - 1)] as Color)
		body.blob(Vector3(0.075, 0.06, 0.075), Transform3D(Basis(), at + Vector3(x, rng.randf_range(0.12, 0.2),
			rng.randf_range(-0.05, 0.08))), c, 6, 4)


## Broken look: stains, cracks and a patch of bare brick, kept cartoon-tidy.
func _dilapidate(body: Kit.VBaker, rng: RandomNumberGenerator, holes: Array[Rect2]) -> void:
	var w := width
	var h := _h
	for k in 5:
		var s := Vector2(rng.randf_range(0.8, 1.9), rng.randf_range(0.6, 1.6))
		var c := Vector2(rng.randf_range(-w * 0.35, w * 0.35), rng.randf_range(0.8, h - 1.0))
		var tone := Color(0.5, 0.48, 0.45) if k % 2 == 0 else Color(0.68, 0.66, 0.62)
		body.box(Vector3(s.x, s.y, 0.01), Vector3(c.x, c.y, 0.006 + 0.001 * float(k)), tone)
	# Bare brick where the plaster fell off.
	var bc := Vector2(rng.randf_range(-w * 0.25, w * 0.25), rng.randf_range(GF + 0.8, h - 1.5))
	for row in 3:
		for col in 3:
			var off := 0.14 if row % 2 == 1 else 0.0
			body.box(Vector3(0.26, 0.1, 0.03), Vector3(bc.x + (float(col) - 1.0) * 0.29 + off, bc.y + float(row) * 0.13, 0.02),
				Color(0.68, 0.36, 0.26).darkened(rng.randf_range(0.0, 0.15)))
	# Zig-zag cracks running from window corners.
	var crack := Color(0.3, 0.28, 0.27)
	for k in 4:
		var r: Rect2 = holes[rng.randi_range(0, holes.size() - 1)]
		var p := Vector3(r.position.x + (r.size.x if k % 2 == 0 else 0.0), r.position.y + r.size.y, 0.015)
		for seg in 4:
			var q := p + Vector3(rng.randf_range(-0.35, 0.35), rng.randf_range(0.25, 0.5), 0.0)
			q.x = clampf(q.x, -w * 0.5 + PIL, w * 0.5 - PIL)
			body.beam(p, q, 0.04, crack)
			p = q
	# An old torn poster beside the door.
	body.box(Vector3(0.5, 0.7, 0.02), Vector3(_door_x - door_side * 1.25, 1.6, 0.02), Color(0.86, 0.82, 0.68),
		Vector3(0.0, 0.0, 0.06))


## Repaired look: the azulejo panels, cut around every opening.
func _azulejos(tiles: Kit.VBaker, holes: Array[Rect2]) -> void:
	var x0 := -_inner * 0.5
	var x1 := _inner * 0.5
	match tile_layout:
		0:
			_tile_rect(tiles, x0, x1, GF + 0.12, _h - 0.08, holes)
		1:
			_tile_rect(tiles, x0, x1, 0.52, GF - 0.12, holes)
			_tile_rect(tiles, x0, x1, _h - 0.9, _h - 0.08, holes)
		_:
			_tile_rect(tiles, x0, x1, 0.52, GF - 0.12, holes)
			_tile_rect(tiles, x0, x1, GF + 0.12, _h - 0.08, holes)


func _tile_rect(tiles: Kit.VBaker, x0: float, x1: float, y0: float, y1: float, holes: Array[Rect2]) -> void:
	var xs: Array[float] = [x0, x1]
	var ys: Array[float] = [y0, y1]
	for r in holes:
		for v: float in [r.position.x, r.position.x + r.size.x]:
			if v > x0 and v < x1:
				xs.append(v)
		for v: float in [r.position.y, r.position.y + r.size.y]:
			if v > y0 and v < y1:
				ys.append(v)
	xs.sort()
	ys.sort()
	for i in xs.size() - 1:
		for j in ys.size() - 1:
			var ax := xs[i]
			var bx := xs[i + 1]
			var ay := ys[j]
			var by := ys[j + 1]
			if bx - ax < 0.02 or by - ay < 0.02:
				continue
			var centre := Vector2((ax + bx) * 0.5, (ay + by) * 0.5)
			var inside := false
			for r in holes:
				if r.has_point(centre):
					inside = true
					break
			if inside:
				continue
			tiles.quad(Vector3(ax, ay, 0.012), Vector3(bx, ay, 0.012), Vector3(bx, by, 0.012),
				Vector3(ax, by, 0.012), Color.WHITE)


## The shutter hanging off one hinge (hit one swings it straight).
func _make_hanging(at: Vector2, shutter: Color) -> void:
	var b := Kit.VBaker.new()
	var leaf := Vector2(WIN_W * 0.5, WIN_H)
	# Hinge at the window's top outer corner; the leaf hangs down beside it.
	b.box(Vector3(leaf.x, leaf.y, 0.05), Vector3(-leaf.x * 0.5, -leaf.y * 0.5, 0.0), shutter)
	for k in 4:
		b.box(Vector3(leaf.x - 0.1, 0.04, 0.03), Vector3(-leaf.x * 0.5, -leaf.y * (0.18 + 0.21 * float(k)), 0.035),
			shutter.darkened(0.15))
	_hanging = b.bake(Kit.vc("plaster"), "HangingShutter", false)
	_hanging.position = Vector3(at.x - WIN_W * 0.5 - 0.17, at.y + WIN_H, 0.05)
	_hanging_rest = Vector3(0.2, 0.0, -0.8)
	_hanging.rotation = _hanging_rest
	add_child_deferred_visual(_hanging)


## Planks nailed across the door (hit two knocks them off).
func _make_planks(_root: Node3D) -> void:
	var b := Kit.VBaker.new()
	var wood := Color(0.66, 0.5, 0.34)
	b.box(Vector3(DOOR_W + 0.5, 0.2, 0.06), Vector3(0.0, 0.5, 0.0), wood, Vector3(0.0, 0.0, 0.62))
	b.box(Vector3(DOOR_W + 0.5, 0.2, 0.06), Vector3(0.0, 0.5, 0.03), wood.darkened(0.1), Vector3(0.0, 0.0, -0.62))
	b.box(Vector3(DOOR_W + 0.4, 0.2, 0.06), Vector3(0.0, -0.45, 0.05), wood.lightened(0.05), Vector3(0.0, 0.0, 0.1))
	for p: Vector3 in [Vector3(-0.55, 0.5, 0.07), Vector3(0.55, 0.5, 0.07), Vector3(0.0, 0.5, 0.09)]:
		b.box(Vector3(0.05, 0.05, 0.02), p, Color(0.3, 0.3, 0.32))
	_planks = b.bake(Kit.vc("wood"), "DoorPlanks", false)
	_planks.position = Vector3(_door_x, DOOR_H * 0.5, 0.12)
	_planks_rest = _planks.transform
	add_child_deferred_visual(_planks)


## The prettiest house's door swings open for the pandas; behind it, warm light.
func _make_door_leaf(root: Node3D) -> void:
	var hinge := Node3D.new()
	hinge.name = "DoorHinge"
	hinge.position = Vector3(_door_x + door_side * DOOR_W * 0.5, 0.0, 0.03)
	var b := Kit.VBaker.new()
	var cx := -door_side * DOOR_W * 0.5
	b.box(Vector3(DOOR_W, DOOR_H, 0.08), Vector3(cx, DOOR_H * 0.5, 0.0), door_paint)
	for py: float in [0.75, 1.75]:
		for px: float in [-0.3, 0.3]:
			b.box(Vector3(DOOR_W * 0.34, 0.75, 0.04), Vector3(cx + px, py, 0.05), door_paint.lightened(0.12))
	b.box(Vector3(0.09, 0.09, 0.06), Vector3(cx - door_side * 0.4, 1.15, 0.08), Color(0.95, 0.75, 0.25))
	hinge.add_child(b.bake(Kit.vc("plaster"), "DoorLeaf"))
	root.add_child(hinge)
	_door_leaf = hinge
	var warm := Kit.VBaker.new()
	warm.box(Vector3(DOOR_W, DOOR_H, 0.02), Vector3(_door_x, DOOR_H * 0.5, -0.06), Color.WHITE)
	root.add_child(warm.bake(Kit.window_glow(), "Doorway", false))


func add_child_deferred_visual(n: Node3D) -> void:
	# The hanging shutter and the planks belong to the broken state but animate
	# on their own, so they hang off the scaled visual rather than a look.
	_visual.add_child(n)
