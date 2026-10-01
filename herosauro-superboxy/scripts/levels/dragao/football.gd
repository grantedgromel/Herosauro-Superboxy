extends PropBody
## A classic black-and-white football. A real PropBody, so the heroes' jab
## already sends it flying (Hitbox -> apply_hit_impulse) and walking into it
## dribbles it (PropBody's kicker); this subclass only gives it a ball's
## shape, weight, bounce and sound, a lofted kick, and a speed cap so Dino
## Energy cannot fire it through the boards.
##
## Bowling goblins over is the level's job (dragao_level.gd checks fast balls
## against goblins each frame): a ball moving faster than BOWL_SPEED that
## touches a goblin knocks it down, "PUMBA!".

const M := preload("res://scripts/levels/dragao/dragao_mats.gd")

const RADIUS := 0.26
const MAX_SPEED := 22.0
const KICK_LIFT := 2.4
const BOWL_SPEED := 6.0

## ImpactFX reads this before `surface`: a kicked ball throws a clean burst,
## not wood chips.
var fx_surface: int = ToonFactory.Surface.FLAT
var level = null  # the dragao level (untyped: no cyclic preload)
var home := Vector3.ZERO
var _blob: int = -1


func _init() -> void:
	body_kind = "plain"
	prop_mass = 0.6
	prop_friction = 0.7
	prop_bounce = 0.62
	kick_strength = 0.85
	size_variation = 0.0
	variant_seed = 0xBA11
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var sp := SphereShape3D.new()
	sp.radius = RADIUS
	cs.shape = sp
	add_child(cs)
	var mi := MeshInstance3D.new()
	mi.name = "Ball"
	var sm := SphereMesh.new()
	sm.radius = RADIUS
	sm.height = RADIUS * 2.0
	sm.radial_segments = 24
	sm.rings = 12
	mi.mesh = sm
	add_child(mi)


func _ready() -> void:
	super._ready()
	# PropBody dresses every mesh in its surface material; a ball wears its own.
	for c in get_children():
		if c is MeshInstance3D:
			(c as MeshInstance3D).material_override = M.football()
			(c as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	linear_damp = 0.35
	angular_damp = 0.25
	continuous_cd = true
	if level != null:
		_blob = level.fx.blob_alloc()


func surface_kind() -> ToonFactory.Surface:
	return ToonFactory.Surface.FLAT


## The jab arrives flat; a football wants a little loft, and a ceiling.
func apply_hit_impulse(impulse: Vector3, at_global: Vector3 = Vector3.INF) -> void:
	var imp := impulse
	imp.y = maxf(imp.y, 0.0) + KICK_LIFT
	var after := linear_velocity + imp / mass
	if after.length() > MAX_SPEED:
		imp = (after.limit_length(MAX_SPEED) - linear_velocity) * mass
	super.apply_hit_impulse(imp, at_global)


## PropBody's hit transient: a football's is a kick.
func play_surface_hit() -> void:
	AudioManager.play_sfx(&"ball_kick", global_position)


func speed() -> float:
	return linear_velocity.length()


## Back to its kick-off spot (begin(), PLAY AGAIN).
func reset_ball() -> void:
	freeze = true
	global_position = home
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze = false
	sleeping = false
	set_physics_process(true)


## Bounce back off a goblin it just bowled over.
func rebound(off: Vector3) -> void:
	var v := linear_velocity
	var n := Vector3(off.x, 0.0, off.z).normalized()
	if n.length() < 0.5:
		n = -v.normalized()
	var flat := Vector3(v.x, 0.0, v.z)
	var reflected := flat - 2.0 * flat.dot(n) * n
	linear_velocity = reflected * 0.45 + Vector3.UP * 3.0


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if level != null and is_inside_tree():
		level.fx.blob_set(_blob, global_position, RADIUS * 1.1, 0.9)
