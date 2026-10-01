extends Node3D
## A heap of rubbish in front of a house: boxes, a crate, bin bags, tins. A
## "thing heroes can hit" (root in group "targets", Hurtbox on TARGETS), so the
## jab, Super Boxy's dash and Dino Energy all clear it. Each hit knocks a layer
## off with a burst; the last hit clears the heap with a sparkle. Then it leaves
## "targets", drops its collider and emits `cleared`, which lights the house's
## door star. Nothing scary: bright boxes and a banana skin, no smell lines.
##
## size 0 = tiny (one hit; the first house's, so the lesson is learnt at once),
## 1 = normal (two layers), 2 = the big heap on the terrace (three layers).

signal cleared(pile: Node3D)

const Kit := preload("res://scripts/levels/pandas/pandas_kit.gd")
const MagicFX := preload("res://scripts/levels/pandas/magic_fx.gd")

## The dash (25) knocks two layers off, the orb (50) the whole heap.
const DASH_HIT := 20.0
const ORB_HIT := 40.0
const FLY_TIME := 0.5

var size: int = 1
var rng_seed: int = 1
var fx_surface: int = ToonFactory.Surface.WOOD

var _chunks: Array[MeshInstance3D] = []
var _rest: Array[Transform3D] = []
var _left: int = 0
var _fly_t := PackedFloat32Array()
var _fly_v := PackedVector3Array()
var _body: StaticBody3D
var _shape: CollisionShape3D
var _hurtbox: Hurtbox
var _extent := Vector3(1.7, 1.0, 1.4)


func _ready() -> void:
	_build()
	reset()


func reset() -> void:
	_left = _chunks.size()
	for i in _chunks.size():
		_chunks[i].visible = true
		_chunks[i].transform = _rest[i]
		_fly_t[i] = -1.0
	_shape.disabled = false
	_hurtbox.collision_layer = PhysicsLayers.TARGETS
	if not is_in_group("targets"):
		add_to_group("targets")


func is_cleared() -> bool:
	return _left <= 0


func layers_left() -> int:
	return _left


func take_hit(amount: float, knockback: Vector3) -> Variant:
	if _left <= 0:
		return false
	var n := 1
	if amount >= ORB_HIT:
		n = _left
	elif amount >= DASH_HIT:
		n = 2
	n = mini(n, _left)
	var push := Vector3(knockback.x, 0.0, knockback.z)
	push = push.normalized() if push.length() > 0.01 else Vector3.BACK
	for k in n:
		_left -= 1
		var i := _left   # top layer first: chunks are stored bottom-up
		_fly_t[i] = 0.0
		_fly_v[i] = push * (3.5 + 1.2 * float(k)) + Vector3.UP * (5.5 + float(k))
		var c := global_position + _rest[i].origin + Vector3.UP * 0.3
		ImpactFX.smash(self, c, ToonFactory.Surface.WOOD, 0.45, push, rng_seed * 31 + i)
	AudioManager.play_prop_break(ToonFactory.Surface.WOOD, global_position)
	GameManager.request_shake(0.12, 0.12)
	if _left <= 0:
		_clear()
	return true


func _clear() -> void:
	remove_from_group("targets")
	_hurtbox.collision_layer = 0
	_shape.set_deferred("disabled", true)
	MagicFX.burst(self, global_position + Vector3.UP * 0.8, Color(1.0, 0.9, 0.4), 22, 5.0,
		rng_seed * 13 + 5)
	AudioManager.play_sfx(&"star", global_position)
	cleared.emit(self)


func _physics_process(delta: float) -> void:
	for i in _chunks.size():
		var t := _fly_t[i]
		if t < 0.0:
			continue
		t += delta
		_fly_t[i] = t
		var mi := _chunks[i]
		if t >= FLY_TIME:
			mi.visible = false
			_fly_t[i] = -1.0
			continue
		var v := _fly_v[i]
		v.y -= 22.0 * delta
		_fly_v[i] = v
		mi.position += v * delta
		mi.rotate_object_local(Vector3(1.0, 0.0, 0.4).normalized(), 9.0 * delta)
		var s := maxf(0.001, 1.0 - t / FLY_TIME)
		mi.scale = Vector3.ONE * s


# --- Build -------------------------------------------------------------------------

func _build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var layers := 1 if size == 0 else (2 if size == 1 else 3)
	var w := 1.2 if size == 0 else (1.9 if size == 1 else 2.6)
	_extent = Vector3(w, 0.6 + 0.4 * float(layers), w * 0.75)
	var mat := Kit.vc("plaster")
	for layer in layers:
		var b := Kit.VBaker.new()
		var y0 := 0.42 * float(layer)
		var spread := w * (1.0 - 0.22 * float(layer))
		var count := 3 if size == 0 else 4 - layer
		for k in count:
			var x := rng.randf_range(-spread * 0.4, spread * 0.4)
			var z := rng.randf_range(-spread * 0.28, spread * 0.28)
			var what := (k + layer + rng.randi_range(0, 3)) % 5
			_item(b, rng, what, Vector3(x, y0, z))
		# One cheerful oddity per layer: a banana skin, a tin, a newspaper.
		_oddity(b, rng, Vector3(rng.randf_range(-spread * 0.5, spread * 0.5), y0,
			rng.randf_range(-spread * 0.3, spread * 0.3)), layer)
		var mi := b.bake(mat, "Layer%d" % layer)
		add_child(mi)
		_chunks.append(mi)
		_rest.append(mi.transform)
	_fly_t.resize(_chunks.size())
	_fly_v.resize(_chunks.size())

	_body = StaticBody3D.new()
	_body.name = "Body"
	_body.collision_layer = PhysicsLayers.WORLD
	_body.collision_mask = 0
	_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(_extent.x * 0.85, _extent.y, _extent.z * 0.85)
	_shape.shape = box
	_shape.position = Vector3(0.0, _extent.y * 0.5, 0.0)
	_body.add_child(_shape)
	add_child(_body)

	_hurtbox = Hurtbox.new()
	_hurtbox.name = "Hurtbox"
	_hurtbox.collision_mask = 0
	var hcs := CollisionShape3D.new()
	var hbox := BoxShape3D.new()
	hbox.size = Vector3(_extent.x + 0.7, _extent.y + 0.9, _extent.z + 0.7)
	hcs.shape = hbox
	hcs.position = Vector3(0.0, hbox.size.y * 0.5, 0.0)
	_hurtbox.add_child(hcs)
	add_child(_hurtbox)


func _item(b: Kit.VBaker, rng: RandomNumberGenerator, what: int, at: Vector3) -> void:
	var yaw := rng.randf_range(-0.6, 0.6)
	match what:
		0, 3:
			# Cardboard box, taped, slightly squashed.
			var s := Vector3(rng.randf_range(0.5, 0.75), rng.randf_range(0.38, 0.52), rng.randf_range(0.45, 0.65))
			var tone: Color = [Color(0.82, 0.62, 0.38), Color(0.88, 0.7, 0.45), Color(0.74, 0.55, 0.34)][rng.randi_range(0, 2)]
			var c := at + Vector3(0.0, s.y * 0.5, 0.0)
			var tilt := Vector3(rng.randf_range(-0.12, 0.12), yaw, rng.randf_range(-0.12, 0.12))
			b.box(s, c, tone, tilt)
			b.box(Vector3(s.x + 0.01, 0.02, 0.12), c + Basis.from_euler(tilt) * Vector3(0.0, s.y * 0.5, 0.0),
				Color(0.95, 0.88, 0.62), tilt)
			# Open flaps.
			b.box(Vector3(s.x * 0.95, 0.02, s.z * 0.4), c + Basis.from_euler(tilt) * Vector3(0.0, s.y * 0.5 + 0.08, s.z * 0.55),
				tone.darkened(0.1), tilt + Vector3(0.7, 0.0, 0.0))
		1:
			# Wooden crate with plank faces.
			var e := rng.randf_range(0.55, 0.7)
			var c := at + Vector3(0.0, e * 0.5, 0.0)
			var rot := Vector3(0.0, yaw, 0.0)
			var basis := Basis.from_euler(rot)
			b.box(Vector3(e, e, e), c, Color(0.62, 0.42, 0.24), rot)
			for k in 3:
				var off := (float(k) - 1.0) * e * 0.33
				b.box(Vector3(e + 0.03, e * 0.26, e + 0.03), c + basis * Vector3(0.0, off, 0.0),
					Color(0.72, 0.5, 0.3) if k % 2 == 0 else Color(0.66, 0.45, 0.27), rot)
			b.box(Vector3(e + 0.05, 0.08, 0.08), c + basis * Vector3(0.0, 0.0, e * 0.5), Color(0.5, 0.33, 0.18),
				rot + Vector3(0.0, 0.0, 0.78))
		2:
			# A bin bag, tied at the top: bright green, round, friendly.
			var r := rng.randf_range(0.3, 0.38)
			var green: Color = [Color(0.25, 0.55, 0.32), Color(0.2, 0.45, 0.6), Color(0.3, 0.3, 0.36)][rng.randi_range(0, 2)]
			b.blob(Vector3(r, r * 0.85, r), Transform3D(Basis(), at + Vector3(0.0, r * 0.8, 0.0)), green, 10, 6)
			b.blob(Vector3(0.09, 0.12, 0.09), Transform3D(Basis(), at + Vector3(0.0, r * 1.62, 0.0)), green.lightened(0.15), 6, 4)
		4:
			# Broken chair: a seat and some legs at odd angles.
			var c := at + Vector3(0.0, 0.32, 0.0)
			var rot := Vector3(0.25, yaw, 0.4)
			var basis := Basis.from_euler(rot)
			var wood := Color(0.55, 0.32, 0.2)
			b.box(Vector3(0.5, 0.06, 0.5), c, wood, rot)
			for lx: float in [-0.2, 0.2]:
				for lz: float in [-0.2, 0.2]:
					b.box(Vector3(0.05, 0.42, 0.05), c + basis * Vector3(lx, -0.2, lz), wood.darkened(0.15), rot)
			b.box(Vector3(0.5, 0.45, 0.05), c + basis * Vector3(0.0, 0.25, -0.22), wood, rot)


func _oddity(b: Kit.VBaker, rng: RandomNumberGenerator, at: Vector3, layer: int) -> void:
	match (layer + rng.randi_range(0, 2)) % 3:
		0:
			# Banana skin.
			var y := Color(1.0, 0.85, 0.2)
			for k in 3:
				var a := TAU * float(k) / 3.0 + rng.randf()
				var xf := Transform3D(Basis.from_euler(Vector3(0.0, a, 1.2)), at + Vector3(cos(a) * 0.1, 0.06, sin(a) * 0.1))
				b.blob(Vector3(0.05, 0.16, 0.035), xf, y, 6, 4)
		1:
			# Two tins.
			for k in 2:
				var xf := Transform3D(Basis.from_euler(Vector3(PI * 0.5 * float(k), rng.randf(), 0.0)),
					at + Vector3(0.18 * float(k), 0.09, 0.0))
				b.cyl(0.08, 0.2, xf, Color(0.78, 0.8, 0.84) if k == 0 else Color(0.9, 0.3, 0.25), 8)
		_:
			# A newspaper.
			b.box(Vector3(0.42, 0.03, 0.3), at + Vector3(0.0, 0.03, 0.0), Color(0.93, 0.92, 0.86),
				Vector3(0.05, rng.randf(), 0.0))
