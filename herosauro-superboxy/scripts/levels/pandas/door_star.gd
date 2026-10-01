extends Node3D
## The glowing magic star at a house's door: the thing the heroes hit to repair
## it. A "thing heroes can hit" (docs/story/ADAPTATION.md): the root joins group
## "targets" and implements take_hit(); a Hurtbox on TARGETS forwards to it.
##
## It starts DARK (not in "targets", Hurtbox off the layer) while the house's
## rubbish pile is in the way, and lights up when the pile is cleared, so the
## kids learn "clear, then fix". Three hits repair the house; Dino Energy counts
## as two. Three little orbs circle it and light up one per hit, so progress is
## visible on the star itself as well as on the house.
##
## The root sits on the ground in front of the door (auto-aim, the dash and the
## companion measure flat distance to it); the star floats above it.

signal struck(steps: int)

const Kit := preload("res://scripts/levels/pandas/pandas_kit.gd")
const MagicFX := preload("res://scripts/levels/pandas/magic_fx.gd")

const HITS_TO_REPAIR := 3
## Above Super Boxy's dash (25) and below Dino Energy (50): the orb counts twice.
const BIG_HIT := 40.0
const FLOAT_Y := 1.75
const HURT_RADIUS := 1.25
const ORB_RADIUS := 0.62
## A jab and a dash can land in the same physics tick; count them once.
const REHIT_GAP := 0.12

var fx_surface: int = ToonFactory.Surface.FLAT

var _lit: bool = false
var _hits: int = 0
var _t: float = 0.0
var _since_hit: float = 10.0
var _pop: float = 0.0          # squash spring
var _pop_v: float = 0.0
var _spin_boost: float = 0.0
var _float: Node3D
var _star: MeshInstance3D
var _orbs: MultiMeshInstance3D
var _hurtbox: Hurtbox
var _mat_lit: StandardMaterial3D
var _mat_dark: StandardMaterial3D


func _ready() -> void:
	_build()
	reset()


func reset() -> void:
	_lit = false
	_hits = 0
	_pop = 0.0
	_pop_v = 0.0
	_spin_boost = 0.0
	visible = true
	if is_in_group("targets"):
		remove_from_group("targets")
	_hurtbox.collision_layer = 0
	_star.material_override = _mat_dark
	_refresh_orbs()


func is_lit() -> bool:
	return _lit


func hits() -> int:
	return _hits


func light_up() -> void:
	if _lit:
		return
	_lit = true
	add_to_group("targets")
	_hurtbox.collision_layer = PhysicsLayers.TARGETS
	_star.material_override = _mat_lit
	_kick(0.45)
	_spin_boost = 9.0
	MagicFX.burst(self, global_position + Vector3.UP * FLOAT_Y, Color(1.0, 0.9, 0.35), 16, 3.5,
		int(absf(global_position.x) * 100.0) + 11)
	_refresh_orbs()


## Done: leave "targets" so auto-aim and the companion stop fussing over it.
func finish() -> void:
	if is_in_group("targets"):
		remove_from_group("targets")
	_hurtbox.collision_layer = 0
	visible = false


func take_hit(amount: float, knockback: Vector3) -> Variant:
	if not _lit or _hits >= HITS_TO_REPAIR:
		return false
	if _since_hit < REHIT_GAP:
		return true
	_since_hit = 0.0
	var steps := 2 if amount >= BIG_HIT else 1
	steps = mini(steps, HITS_TO_REPAIR - _hits)
	_hits += steps
	var flat := Vector3(knockback.x, 0.0, knockback.z)
	_kick(-0.5)
	_spin_boost = 14.0
	var at := global_position + Vector3.UP * FLOAT_Y
	ImpactFX.spark(self, at, flat.normalized() if flat.length() > 0.01 else Vector3.UP,
		ToonFactory.Surface.FLAT, 1.2)
	MagicFX.burst(self, at, Color(0.5, 1.0, 0.45), 14 + 8 * steps, 4.0 + float(steps),
		int(absf(global_position.x) * 100.0) + _hits * 7)
	AudioManager.play_sfx(&"star", at)
	_refresh_orbs()
	struck.emit(steps)
	return true


func _physics_process(delta: float) -> void:
	_t += delta
	_since_hit += delta
	# Spring: squash on a hit, stretch on lighting up, settle in a wobble.
	_pop_v += (-220.0 * _pop - 14.0 * _pop_v) * delta
	_pop += _pop_v * delta
	_spin_boost = maxf(0.0, _spin_boost - _spin_boost * 3.0 * delta)
	var s := clampf(_pop, -0.5, 0.5)
	if _lit:
		var pulse := 1.0 + 0.06 * sin(_t * 5.0)
		_float.position.y = FLOAT_Y + 0.12 * sin(_t * 2.4)
		_float.rotation.y += (1.4 + _spin_boost) * delta
		_float.scale = Vector3(pulse * (1.0 - s * 0.5), pulse * (1.0 + s), pulse * (1.0 - s * 0.5))
	else:
		_float.position.y = FLOAT_Y - 0.15
		_float.rotation.y = 0.35 * sin(_t * 0.7)
		_float.scale = Vector3(0.85, 0.85, 0.85)
	# Orbs circle the star; each lights up as a hit lands.
	var mm := _orbs.multimesh
	for i in HITS_TO_REPAIR:
		var a := _t * 1.6 + TAU * float(i) / float(HITS_TO_REPAIR)
		var p := Vector3(cos(a) * ORB_RADIUS, FLOAT_Y + 0.12 * sin(_t * 2.4) + 0.1 * sin(a * 2.0),
			sin(a) * ORB_RADIUS)
		var size := 0.0001
		if _lit:
			size = 0.13 if i >= _hits else 0.19 + 0.03 * sin(_t * 9.0 + float(i))
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * size), p))


func _kick(amount: float) -> void:
	_pop_v += amount * 14.0


func _refresh_orbs() -> void:
	var mm := _orbs.multimesh
	for i in HITS_TO_REPAIR:
		mm.set_instance_color(i, Color(0.45, 1.0, 0.4) if i < _hits else Color(1.0, 0.95, 0.75))


func _build() -> void:
	_float = Node3D.new()
	_float.name = "Float"
	_float.position.y = FLOAT_Y
	add_child(_float)
	var b := Kit.VBaker.new()
	b.star(0.62, 0.27, 0.2, Transform3D.IDENTITY, Color(1.0, 0.82, 0.25))
	_star = MeshInstance3D.new()
	_star.name = "Star"
	_star.mesh = b.bake_mesh()
	_star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_float.add_child(_star)
	_mat_lit = ToonFactory.glow(Color(1.0, 0.8, 0.25), 1.6)
	_mat_dark = ToonFactory.build(Color(0.5, 0.47, 0.4), ToonFactory.Surface.FLAT, 0.6)

	_orbs = Kit.multimesh(Kit.sparkle_mesh(), HITS_TO_REPAIR, Kit.unshaded(),
		AABB(Vector3(-1.5, 0.0, -1.5), Vector3(3.0, 3.5, 3.0)), "Orbs")
	add_child(_orbs)

	_hurtbox = Hurtbox.new()
	_hurtbox.name = "Hurtbox"
	_hurtbox.collision_layer = 0
	_hurtbox.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = HURT_RADIUS
	cs.shape = sphere
	cs.position = Vector3(0.0, 1.45, 0.0)
	_hurtbox.add_child(cs)
	add_child(_hurtbox)

