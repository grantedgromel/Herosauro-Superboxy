extends Node3D
## One of the four glowing stakes the goblins drove into the pitch to rope the
## dragon down. A "thing heroes can hit": root in group "targets", a Hurtbox on
## TARGETS, a slim solid on BOSS (heroes bump it, the camera arm does not).
##
## Three glowing rings are its hit counter, so a child can SEE how many more
## bonks it needs: each hit puts one out with a wobble and a chip of wood; the
## third pops the stake out of the ground, the rope whips back to the dragon and
## `snapped` fires (the level cheers, sparkles and advances the objective).

signal snapped(stake: Node3D)

const VC := preload("res://scripts/levels/dragao/vc_baker.gd")
const M := preload("res://scripts/levels/dragao/dragao_mats.gd")

const HITS := 3
const POST_H := 1.4
const RING_Y := [0.5, 0.82, 1.14]
const RING_ON := Color(1.0, 0.72, 0.18)
const ROPE := Color(0.86, 0.7, 0.45)
const ROPE_ALT := Color(0.7, 0.53, 0.32)

static var _post_mesh: Mesh
## _ring_meshes[n] is the stake's glowing rings with n of them still lit: one
## draw call however many are left.
static var _ring_meshes: Array[Mesh] = []

var level = null  # the dragao level (untyped: no cyclic preload)
var hits: int = 0
var _done: bool = false
var _anchor := Vector3.ZERO     # rope end on the dragon, level space
var _visual: Node3D
var _rings: MeshInstance3D
var _halo: MeshInstance3D
var _rope: MeshInstance3D
var _hurtbox: Hurtbox
var _body: StaticBody3D
var _wobble: float = 0.0
var _wobble_t: float = 0.0
var _lean_axis := Vector3.RIGHT
var _pop_t: float = -1.0
var _rope_t: float = -1.0
var _clock: float = 0.0


func setup(p_level: Node3D, anchor: Vector3) -> void:
	level = p_level
	_anchor = anchor


func _ready() -> void:
	_build()
	reset()


func reset() -> void:
	hits = 0
	_done = false
	_wobble = 0.0
	_pop_t = -1.0
	_rope_t = -1.0
	visible = true
	_visual.transform = Transform3D.IDENTITY
	_visual.visible = true
	_rings.mesh = _ring_meshes[HITS]
	_rings.visible = true
	_halo.visible = true
	_rope.visible = true
	_rope.scale = Vector3.ONE
	_body.collision_layer = PhysicsLayers.BOSS
	_hurtbox.collision_layer = PhysicsLayers.TARGETS
	if not is_in_group("targets"):
		add_to_group("targets")
	set_physics_process(true)


func is_done() -> bool:
	return _done


func top() -> Vector3:
	return global_position + Vector3.UP * POST_H


## The contract. Every connect counts one, whatever hit it.
func take_hit(_amount: float, knockback: Vector3) -> void:
	if _done:
		return
	hits += 1
	var flat := Vector3(knockback.x, 0.0, knockback.z)
	_lean_axis = Vector3.UP.cross(flat.normalized()) if flat.length() > 0.01 else Vector3.RIGHT
	_wobble = 0.32
	_wobble_t = 0.0
	AudioManager.play_prop_hit(ToonFactory.Surface.WOOD, global_position)
	ImpactFX.spark(self, global_position + Vector3.UP * 0.9, flat.normalized() if flat.length() > 0.01 else Vector3.UP,
		ToonFactory.Surface.WOOD, 1.0)
	var lit := HITS - hits
	_rings.mesh = _ring_meshes[maxi(lit, 0)]
	_rings.visible = lit > 0
	if level != null:
		level.fx.sparkle(global_position + Vector3.UP * RING_Y[mini(lit, 2)], RING_ON, 0.6)
	if hits >= HITS:
		_snap()


func _snap() -> void:
	_done = true
	remove_from_group("targets")
	_hurtbox.collision_layer = 0
	_body.collision_layer = 0
	_halo.visible = false
	_pop_t = 0.0
	_rope_t = 0.0
	AudioManager.play_sfx(&"rope_snap", global_position)
	GameManager.request_shake(0.25, 0.2)
	if level != null:
		level.fx.sparkle(global_position + Vector3.UP * 1.2, Color(1.0, 0.9, 0.5), 1.6)
		level.fx.sparkle(_anchor + Vector3.UP * 0.4, Color(0.7, 0.9, 1.0), 1.1)
	snapped.emit(self)


func _physics_process(delta: float) -> void:
	_clock += delta
	if not _done:
		var pulse := 1.0 + 0.12 * sin(_clock * 4.0)
		_halo.scale = Vector3.ONE * pulse
	if _wobble > 0.001 and _pop_t < 0.0:
		_wobble_t += delta
		_wobble = maxf(0.0, _wobble - _wobble * 6.0 * delta)
		_visual.basis = Basis(_lean_axis, _wobble * cos(_wobble_t * 16.0))
	if _pop_t >= 0.0:
		# Out of the ground with a spin, then shrink away in a twinkle.
		_pop_t += delta
		var k := _pop_t / 0.75
		var y := 3.2 * _pop_t - 4.0 * _pop_t * _pop_t
		_visual.transform = Transform3D(Basis(Vector3(1, 0, 0.4).normalized(), _pop_t * 9.0)
			.scaled(Vector3.ONE * maxf(0.01, 1.0 - k * k)), Vector3(0, maxf(y, 0.0) * 1.6 + _pop_t * 0.6, 0))
		if k >= 1.0:
			_visual.visible = false
			_pop_t = -1.0
	if _rope_t >= 0.0:
		_rope_t += delta
		var r := clampf(_rope_t / 0.28, 0.0, 1.0)
		_rope.scale = Vector3.ONE * maxf(0.02, 1.0 - r)
		if r >= 1.0:
			_rope.visible = false
			_rope_t = -1.0
	if _done and _pop_t < 0.0 and _rope_t < 0.0:
		set_physics_process(false)


func _build() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	if _post_mesh == null:
		var b := VC.new()
		var wood := Color(0.55, 0.36, 0.2)
		b.cylinder(0.15, 0.17, POST_H - 0.2, Transform3D(Basis(), Vector3(0, (POST_H - 0.2) * 0.5, 0)), wood, 10)
		b.cylinder(0.02, 0.15, 0.22, Transform3D(Basis(), Vector3(0, POST_H - 0.09, 0)), wood.lightened(0.15), 10)
		b.cylinder(0.185, 0.185, 0.07, Transform3D(Basis(), Vector3(0, 0.25, 0)), Color(0.35, 0.36, 0.42), 10)
		b.sphere(Vector3(0, 0.02, 0), Vector3(0.45, 0.12, 0.45), Color(0.42, 0.3, 0.18), Basis(), 12, 6)
		# The goblins' knot: a fat coil of rope round the top.
		b.torus(0.19, 0.05, Transform3D(Basis(), Vector3(0, POST_H - 0.32, 0)), ROPE, 14, 6)
		_post_mesh = b.mesh()
		for n in HITS + 1:
			var rb := VC.new()
			for i in n:
				rb.torus(0.2, 0.045, Transform3D(Basis(), Vector3(0, RING_Y[i], 0)), RING_ON, 16, 6)
			_ring_meshes.append(rb.mesh())
	var post := MeshInstance3D.new()
	post.name = "Post"
	post.mesh = _post_mesh
	post.material_override = M.skin()
	_visual.add_child(post)
	_rings = MeshInstance3D.new()
	_rings.name = "Rings"
	_rings.mesh = _ring_meshes[HITS]
	_rings.material_override = M.lit(1.0)
	_rings.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(_rings)
	_halo = MeshInstance3D.new()
	_halo.name = "Glow"
	var q := QuadMesh.new()
	q.size = Vector2(2.2, 2.2)
	_halo.mesh = q
	_halo.material_override = M.halo(Color(1.0, 0.7, 0.25, 0.4))
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_halo.position = Vector3(0, 0.9, 0)
	_visual.add_child(_halo)

	# The rope: from this stake's knot, sagging, up and over the dragon's back.
	var top_local := Vector3(0, POST_H - 0.32, 0)
	var anchor_local := _anchor - position
	var mid := (top_local + anchor_local) * 0.5 + Vector3.DOWN * 0.25
	var over := anchor_local + Vector3.UP * 0.35
	var pts := PackedVector3Array()
	for k in 13:
		var t := float(k) / 12.0
		var a := top_local.lerp(mid, t)
		var c := mid.lerp(over, t)
		pts.append(a.lerp(c, t) - anchor_local)
	var rb2 := VC.new()
	rb2.tube(pts, 0.055, ROPE, ROPE_ALT, 6)
	_rope = rb2.commit(M.skin(), "Rope")
	_rope.position = anchor_local
	add_child(_rope)

	_body = StaticBody3D.new()
	_body.name = "Body"
	_body.collision_layer = PhysicsLayers.BOSS
	_body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.25
	cyl.height = POST_H
	cs.shape = cyl
	cs.position = Vector3(0, POST_H * 0.5, 0)
	_body.add_child(cs)
	add_child(_body)

	_hurtbox = Hurtbox.new()
	_hurtbox.name = "Hurtbox"
	_hurtbox.collision_layer = PhysicsLayers.TARGETS
	_hurtbox.collision_mask = 0
	var hcs := CollisionShape3D.new()
	var hcyl := CylinderShape3D.new()
	hcyl.radius = 0.8
	hcyl.height = 2.0
	hcs.shape = hcyl
	hcs.position = Vector3(0, 1.0, 0)
	_hurtbox.add_child(hcs)
	add_child(_hurtbox)
