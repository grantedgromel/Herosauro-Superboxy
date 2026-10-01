extends Node3D
## One of the club's six cups: two big silver cups with large handle "ears" and
## four smaller gold trophies. No crest, no engraving: shape and shine only.
##
## Its life: CARRIED over a goblin's head -> knocked LOOSE (it pops up, bounces
## twice with a twinkle) -> WAITING on the grass with a glowing beacon ring ->
## a hero touches it -> FLYING in an arc back to its shelf in the trophy cabinet
## -> SHELVED. The level owns the rules; this owns the motion and the look.

signal shelved(cup: Node3D)

const VC := preload("res://scripts/levels/dragao/vc_baker.gd")
const M := preload("res://scripts/levels/dragao/dragao_mats.gd")
const L := preload("res://scripts/levels/dragao/dragao_layout.gd")

enum S { HIDDEN, CARRIED, LOOSE, WAITING, FLYING, SHELVED }

const GRAVITY := 20.0
const FLIGHT_TIME := 1.35
const PICKUP_DELAY := 0.35
const SILVER := Color(0.86, 0.89, 0.94)
const GOLD := Color(1.0, 0.76, 0.22)
const PLINTH := Color(0.12, 0.13, 0.2)

static var _meshes: Dictionary = {}

var level = null  # the dragao level (untyped: no cyclic preload)
var big: bool = false
var slot: int = 0
var state: int = S.HIDDEN
var _holder: Node3D = null
var _vel := Vector3.ZERO
var _t: float = 0.0
var _clock: float = 0.0
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _bounces: int = 0
var _spin: float = 0.0
var _mesh: MeshInstance3D
var _beacon: MeshInstance3D
var _blob: int = -1


func setup(p_level: Node3D, p_big: bool, p_slot: int) -> void:
	level = p_level
	big = p_big
	slot = p_slot


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.name = "Cup"
	_mesh.mesh = _cup_mesh(big)
	_mesh.material_override = M.trophy()
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	_beacon = MeshInstance3D.new()
	_beacon.name = "Beacon"
	var tm := TorusMesh.new()
	tm.inner_radius = 0.62
	tm.outer_radius = 0.8
	tm.rings = 24
	tm.ring_segments = 4
	_beacon.mesh = tm
	_beacon.material_override = M.flat_lit(Color(1.0, 0.85, 0.3))
	_beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beacon.top_level = true
	add_child(_beacon)
	if level != null:
		_blob = level.fx.blob_alloc()
	hide_cup()


func hide_cup() -> void:
	state = S.HIDDEN
	_holder = null
	visible = false
	_beacon.visible = false
	if level != null:
		level.fx.blob_hide(_blob)
	set_physics_process(false)


func attach_to(holder: Node3D) -> void:
	_holder = holder
	state = S.CARRIED
	visible = true
	_beacon.visible = false
	set_physics_process(true)


## Knocked out of a goblin's hands at `from`, pushed by `push`.
func drop(from: Vector3, push: Vector3) -> void:
	_holder = null
	state = S.LOOSE
	global_position = from
	global_rotation = Vector3.ZERO
	_vel = Vector3(push.x, 6.5, push.z)
	_bounces = 0
	_t = 0.0
	visible = true
	set_physics_process(true)
	if level != null:
		level.fx.sparkle(from, Color(1.0, 0.9, 0.5), 1.0)


func is_collectable() -> bool:
	return state == S.WAITING and _t >= PICKUP_DELAY


func is_loose() -> bool:
	return state == S.LOOSE or state == S.WAITING


func is_shelved() -> bool:
	return state == S.SHELVED


## A hero touched it: fly home to `to` (the cabinet slot, global).
func collect(to: Vector3) -> void:
	state = S.FLYING
	_from = global_position
	_to = to
	_t = 0.0
	_beacon.visible = false
	AudioManager.play_sfx(&"cup_collect", global_position)
	if level != null:
		level.fx.sparkle(global_position + Vector3.UP * 0.6, Color(1.0, 0.95, 0.55), 1.4)
		level.fx.blob_hide(_blob)


## Straight onto its shelf (PLAY AGAIN after a win, probes).
func place_shelved(at: Vector3) -> void:
	state = S.SHELVED
	visible = true
	global_position = at
	global_rotation = Vector3.ZERO
	_beacon.visible = false
	set_physics_process(false)


func _physics_process(delta: float) -> void:
	_t += delta
	_clock += delta
	match state:
		S.CARRIED:
			if _holder != null and is_instance_valid(_holder):
				var xf := _holder.global_transform
				global_transform = Transform3D(xf.basis.orthonormalized(), xf.origin)
		S.LOOSE:
			_vel.y -= GRAVITY * delta
			var p := global_position + _vel * delta
			_spin += delta * 8.0
			var c := L.clamp_to_pitch(p, 0.8)
			if c.x != p.x:
				_vel.x = -_vel.x * 0.5
			if c.z != p.z:
				_vel.z = -_vel.z * 0.5
			p = Vector3(c.x, p.y, c.z)
			if level != null:
				p = level.push_out_of_blockers(p, 0.6)
			if p.y <= 0.0 and _vel.y < 0.0:
				p.y = 0.0
				_bounces += 1
				_vel = Vector3(_vel.x * 0.5, -_vel.y * 0.45, _vel.z * 0.5)
				if level != null:
					level.fx.sparkle(p + Vector3.UP * 0.3, Color(1.0, 0.92, 0.5), 0.5)
				if _bounces >= 2:
					state = S.WAITING
					_t = 0.0
					_beacon.visible = true
			global_position = p
			rotation = Vector3(sin(_spin) * 0.4, _spin, 0.0)
		S.WAITING:
			# Bob and turn so it twinkles; the beacon ring pulses on the grass.
			var bob := 0.12 + 0.1 * sin(_clock * 3.0)
			global_position.y = bob
			rotation = Vector3(0.0, _clock * 1.6, 0.0)
			_beacon.global_position = Vector3(global_position.x, 0.04, global_position.z)
			var pulse := 1.0 + 0.15 * sin(_clock * 5.0)
			_beacon.scale = Vector3(pulse, 1.0, pulse)
		S.FLYING:
			var k := clampf(_t / FLIGHT_TIME, 0.0, 1.0)
			var e := k * k * (3.0 - 2.0 * k)
			var p2 := _from.lerp(_to, e)
			p2.y += sin(k * PI) * (6.0 + _from.distance_to(_to) * 0.18)
			global_position = p2
			rotation = Vector3(0.0, k * TAU * 2.0, sin(k * PI) * 0.3)
			if k >= 1.0:
				place_shelved(_to)
				shelved.emit(self)
	if level != null and (state == S.LOOSE or state == S.WAITING):
		level.fx.blob_set(_blob, global_position, 0.45 if big else 0.32, 0.9)


static func _cup_mesh(p_big: bool) -> Mesh:
	var key := "big" if p_big else "small"
	if _meshes.has(key):
		return _meshes[key]
	var b := VC.new()
	if p_big:
		# The big silver cup: a dark plinth, a slim stem, a deep bowl, and two
		# great looping handles standing out like ears.
		b.cylinder(0.2, 0.24, 0.16, Transform3D(Basis(), Vector3(0, 0.08, 0)), PLINTH, 14)
		var prof := PackedVector2Array([
			Vector2(0.17, 0.16), Vector2(0.12, 0.2), Vector2(0.05, 0.26), Vector2(0.045, 0.42),
			Vector2(0.09, 0.48), Vector2(0.2, 0.56), Vector2(0.27, 0.68), Vector2(0.3, 0.82),
			Vector2(0.31, 0.92), Vector2(0.29, 0.93)])
		b.lathe(prof, Transform3D.IDENTITY, SILVER, 18)
		b.cylinder(0.285, 0.285, 0.02, Transform3D(Basis(), Vector3(0, 0.9, 0)), SILVER.darkened(0.25), 18)
		for sx in [-1.0, 1.0]:
			var pts := PackedVector3Array()
			for k in 11:
				var a := -PI * 0.5 + PI * float(k) / 10.0
				pts.append(Vector3(sx * (0.28 + cos(a) * 0.2), 0.7 + sin(a) * 0.22, 0.0))
			b.tube(pts, 0.035, SILVER, SILVER.darkened(0.08), 6)
	else:
		# A gold trophy: plinth, stem, cup with small handles, a star on top.
		b.box(Vector3(0.3, 0.12, 0.3), Transform3D(Basis(), Vector3(0, 0.06, 0)), PLINTH)
		var prof2 := PackedVector2Array([
			Vector2(0.1, 0.12), Vector2(0.04, 0.16), Vector2(0.035, 0.27), Vector2(0.08, 0.3),
			Vector2(0.15, 0.36), Vector2(0.18, 0.46), Vector2(0.18, 0.5), Vector2(0.16, 0.5)])
		b.lathe(prof2, Transform3D.IDENTITY, GOLD, 16)
		b.cylinder(0.165, 0.165, 0.02, Transform3D(Basis(), Vector3(0, 0.48, 0)), GOLD.darkened(0.3), 16)
		for sx in [-1.0, 1.0]:
			var pts2 := PackedVector3Array()
			for k in 9:
				var a2 := -PI * 0.5 + PI * float(k) / 8.0
				pts2.append(Vector3(sx * (0.17 + cos(a2) * 0.08), 0.42 + sin(a2) * 0.07, 0.0))
			b.tube(pts2, 0.022, GOLD, GOLD.darkened(0.08), 5)
		b.star(0.09, 0.03, Transform3D(Basis(), Vector3(0, 0.6, 0)), GOLD)
	var m := b.mesh()
	_meshes[key] = m
	return m
