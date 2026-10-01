extends Node3D
## A practice target: the smallest complete "thing heroes can hit"
## (docs/story/ADAPTATION.md). Copy this shape for goblins, cages, anything.
##
##   * the ROOT joins group "targets" (auto-aim and the companion AI look there)
##     and implements take_hit(amount: float, knockback: Vector3) -> void;
##   * a Hurtbox child on PhysicsLayers.TARGETS, a little LARGER than the solid
##     collider, so the jab, Dino Energy and Boxy Dash all reach it;
##   * a StaticBody3D on WORLD so heroes bump into it instead of walking through.
##
## The first hit tips it over, turns it gold and reports progress through
## `struck`; later hits only wobble it. Leaving group "targets" on that first hit
## is what stops auto-aim and the companion from fussing over a done target.

signal struck(dummy: Node3D)

const POST_HEIGHT := 1.5
const POST_RADIUS := 0.32
const HEAD_RADIUS := 0.42
const HURT_RADIUS := 0.8
const WOBBLE_DECAY := 5.0
const WOBBLE_FREQ := 9.0

var _done: bool = false
var _wobble: float = 0.0      # radians of lean, decays to zero
var _wobble_t: float = 0.0
var _lean_axis := Vector3.FORWARD
var _visual: Node3D
var _head: MeshInstance3D
var _post: MeshInstance3D


func _ready() -> void:
	_build()
	reset()


## Back to standing and hittable. The level calls this from begin(), so PLAY
## AGAIN gets fresh targets.
func reset() -> void:
	_done = false
	_wobble = 0.0
	_wobble_t = 0.0
	if not is_in_group("targets"):
		add_to_group("targets")
	_apply_look()


func is_done() -> bool:
	return _done


## The contract. A level's targets take float damage and return nothing.
func take_hit(_amount: float, knockback: Vector3) -> void:
	var flat := Vector3(knockback.x, 0.0, knockback.z)
	_lean_axis = Vector3.UP.cross(flat.normalized()) if flat.length() > 0.01 else Vector3.FORWARD
	_wobble = 0.45 if not _done else 0.25
	_wobble_t = 0.0
	AudioManager.play_prop_hit(ToonFactory.Surface.WOOD, global_position)
	if _done:
		return
	_done = true
	remove_from_group("targets")
	_apply_look()
	ImpactFX.spark(self, global_position + Vector3.UP * (POST_HEIGHT + 0.4), Vector3.UP,
		ToonFactory.Surface.FLAT, 1.4)
	AudioManager.play_sfx(&"star", global_position)
	struck.emit(self)


func _physics_process(delta: float) -> void:
	if _wobble <= 0.001:
		if _visual.basis != Basis.IDENTITY:
			_visual.basis = Basis.IDENTITY
		return
	_wobble_t += delta
	_wobble = maxf(0.0, _wobble - _wobble * WOBBLE_DECAY * delta)
	var lean := _wobble * cos(_wobble_t * WOBBLE_FREQ)
	_visual.basis = Basis(_lean_axis, lean)


func _build() -> void:
	# Visuals hang off one pivot at the base so the wobble rocks the whole post.
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	_post = SceneryKit.cylinder(_visual, "Post", POST_RADIUS, POST_RADIUS * 1.2, POST_HEIGHT,
		Vector3(0.0, POST_HEIGHT * 0.5, 0.0), null, 12)
	_head = MeshInstance3D.new()
	_head.name = "Head"
	var sphere := SphereMesh.new()
	sphere.radius = HEAD_RADIUS
	sphere.height = HEAD_RADIUS * 2.0
	_head.mesh = sphere
	_head.position = Vector3(0.0, POST_HEIGHT + HEAD_RADIUS * 0.8, 0.0)
	_visual.add_child(_head)

	# Solid: heroes bump into it. On WORLD like any other piece of scenery.
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = POST_RADIUS * 1.2
	cyl.height = POST_HEIGHT + HEAD_RADIUS * 2.0
	cs.shape = cyl
	cs.position = Vector3(0.0, cyl.height * 0.5, 0.0)
	body.add_child(cs)
	add_child(body)

	# Hittable: a Hurtbox on TARGETS, bigger than the body. Its target is its
	# parent (this node), which is where take_hit lives.
	var hb := Hurtbox.new()
	hb.name = "Hurtbox"
	hb.collision_layer = PhysicsLayers.TARGETS
	hb.collision_mask = 0
	var hcs := CollisionShape3D.new()
	var hcyl := CylinderShape3D.new()
	hcyl.radius = HURT_RADIUS
	hcyl.height = POST_HEIGHT + HEAD_RADIUS * 2.0 + 0.4
	hcs.shape = hcyl
	hcs.position = Vector3(0.0, hcyl.height * 0.5, 0.0)
	hb.add_child(hcs)
	add_child(hb)


## Red-and-cream before, gold after. Materials come from ToonFactory's shared
## cache by parameter set and are never mutated, so nothing is duplicated.
func _apply_look() -> void:
	if _post == null:
		return
	_post.material_override = ToonFactory.wood(Color(0.62, 0.42, 0.26))
	if _done:
		_head.material_override = ToonFactory.glow(Color(1.0, 0.8, 0.25), 1.2)
	else:
		_head.material_override = ToonFactory.solid(Color(0.86, 0.2, 0.18), 0.0, 0.55)
