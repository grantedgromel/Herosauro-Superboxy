extends Area3D
## Shockwave: the expanding ground wave from Adamastor's slam and his phase-two
## roar.
##
## Spawned at the giant's feet into the "spawn_root". Its sphere collider grows
## outward; any hero or prop it sweeps over is knocked away once, and the visual
## rides the same radius, so what you see is exactly what is about to hit you.
##
## This is the WIDE, weaker half of the slam. The heavy close hit is the boss's
## own slam hitbox; the hero's i-frames mean only one of the two ever lands.
##
## --- WHAT THIS DRAWS AND WHY -------------------------------------------------
##
## It used to be a translucent brown `TorusMesh` scaled up by a tween: one flat
## unshaded colour, no dust, no interaction with the deck, and nothing at the
## point of contact. Against the RUBRIC that is a decal being resized. A nine
## metre giant putting his fists through granite has to move the deck, and three
## things now say so:
##
##   * THE FRONT. `ImpactFX.ring_mesh()` — the same baked annulus every impact
##     in the game uses, wound to the MeshBaker contract, with a raised inner lip
##     so the key light catches the leading face and not the trailing one. It is
##     a wave with a lit side, not a ring of colour.
##   * THE DUST WALL. A MultiMesh of chunky lit puffs riding the rim, lagging it
##     by a per-puff fraction so the wall boils rather than sliding out rigidly,
##     rising and fading as the wave spends itself. One draw call for the lot.
##   * THE CRATER. One `ImpactFX.ground()` burst at the centre on the frame the
##     wave is born, so the giant's fists throw chips and a dust cloud out of the
##     surface he actually hit.
##
## The hero's end of a hit is NOT drawn here. `PlayerBase.take_hit()` owns it —
## five damage sources converge there and none of them can forget — so this only
## has to deliver the damage and let that fire.
##
## --- SURFACE -----------------------------------------------------------------
##
## `fx_surface` is the deck the wave is rolling across, and everything it draws
## resolves through `ImpactFX.impact_row()`: the ring's colour and the dust's
## colour, volume and settle time all come out of the table, so a wave over the
## calçada does not look like a wave over granite. `ImpactFX.surface_of()` reads
## the same property off any node, which is how the rest of the world opts in.
##
## Determinism: the rim's angular scatter runs off a seeded RNG derived from the
## blast position, and everything animates off accumulated `delta`. No tween and
## no clock — ARCHITECTURE.md rules 4 and 5.

@export var damage: int = 14
@export var max_radius: float = 15.0
@export var grow_time: float = 0.5
@export var knockback: float = 14.0
## Impulse handed to props the wave passes over, at the blast's centre. Falls off
## with distance so barrels at the rim tip rather than fly.
@export var prop_impulse: float = 38.0
## What the wave is rolling over. The deck between the tram rails is calçada, so
## that is the default; the boss can override it if he ever slams somewhere else.
@export var fx_surface: int = ToonFactory.Surface.COBBLE

## How long the wave hangs around after it has reached full radius, letting the
## dust wall settle instead of being cut off at its brightest. The collider stops
## mattering the instant the wave is at `max_radius` — everything it can catch,
## it has caught — so this is purely the visual tail.
const TAIL := 0.45
## Puffs in the dust wall. One draw call whatever the number; 18 is where the
## wall stops reading as separate balls at the fifteen-metre rim and is still
## legible at the roar's eleven.
const RIM_PUFFS := 18
## Height of the wall as a fraction of the wave's radius. A 15 m blast throws a
## wall about 2.4 m high, which is a little over a hero's head — enough to read
## as a wall from a deck-level camera, not enough to hide the giant behind it.
const RIM_RISE := 0.16
## How far behind the rim the slowest puff trails, as a fraction of the radius.
## Without this the wall is a rigid hoop sliding outward; with it the front
## boils, because each puff is on its own clock.
const RIM_LAG := 0.26
## Vertical squash on the ring as it opens. The wave lies down as it spends
## itself, which is what stops a fifteen-metre ring reading as a wall of light.
const RING_FLATTEN := 0.55

var _shape: SphereShape3D
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _wall: MultiMeshInstance3D
## Per-puff angle, radial lag, rise rate and size, packed once at birth.
var _puff_ang: PackedFloat32Array = PackedFloat32Array()
var _puff_lag: PackedFloat32Array = PackedFloat32Array()
var _puff_rise: PackedFloat32Array = PackedFloat32Array()
var _puff_size: PackedFloat32Array = PackedFloat32Array()
## Per-puff tint, held here rather than read back off the MultiMesh: the instance
## buffer lives in the RenderingServer and reading it every frame to change one
## channel is a round trip we already have the answer to.
var _puff_tint: PackedColorArray = PackedColorArray()
var _ring_alpha: float = 0.42
var _dust_tint: Color = Color(0.72, 0.71, 0.68)

## Instance ids, not references: the wave outlives a prop it shatters.
var _hit: Array[int] = []
var _t: float = 0.0
var _begun: bool = false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = PhysicsLayers.PLAYERS | PhysicsLayers.PROPS

	var col := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col and col.shape is SphereShape3D:
		_shape = col.shape as SphereShape3D
	else:
		_shape = SphereShape3D.new()
		if col == null:
			col = CollisionShape3D.new()
			col.name = "CollisionShape3D"
			add_child(col)
		col.shape = _shape
	# The shape resource is shared by every instance of the packed scene, so give
	# this wave its own before we start animating the radius — otherwise two waves
	# in the air at once fight over one number.
	_shape = _shape.duplicate()
	col.shape = _shape
	_shape.radius = 0.5

	# An Area3D's overlap list starts empty, so anything already standing on the
	# boss's feet arrives through body_entered on the first physics frame — no
	# separate initial sweep needed (the one that used to be here queried the list
	# before it was populated and always came back empty).
	body_entered.connect(_on_body_entered)


## Everything that depends on WHERE the blast is.
##
## The spawner does `add_child(wave)` and only then sets `global_position`, so
## `_ready()` runs at the spawn root's origin rather than at the giant's feet.
## That is not cosmetic: the previous code cached `_origin = global_position` in
## `_ready()`, so every knockback direction and every distance falloff in the
## game was measured from world (0, 0, 0) instead of from the blast. A hero
## standing between the origin and the giant was thrown TOWARD him. The blast
## centre is now read live from `global_position` (this node never moves), and
## anything that has to be built at the right place is built here, on the first
## idle frame, by which time the spawner has finished.
func _begin() -> void:
	_begun = true
	var row := ImpactFX.impact_row(fx_surface)
	_ring_alpha = float(row["ring_alpha"])
	_dust_tint = row["dust_tint"]
	# Seeded off the blast position, so the same slam in two runs of the same
	# fight throws the same wall. ARCHITECTURE.md rule 4.
	var here := global_position
	_rng.seed = hash("wave|%.2f|%.2f|%.2f|%.2f" % [here.x, here.y, here.z, max_radius])

	_build_ring(row)
	_build_wall()

	# The crater: chips and a dust cloud out of the surface the giant actually
	# hit, at the point of contact. Half the blast radius, because the dust the
	# fists throw is a local thing — the wave carries the rest of it outward.
	ImpactFX.ground(self, here, fx_surface, max_radius * 0.28, 1.6)


func _process(delta: float) -> void:
	if not _begun:
		_begin()
	_t += delta
	var span: float = maxf(0.05, grow_time)
	# Ease-out: the wave leaves fast and decelerates into its full radius, which is
	# how a pressure front behaves and what makes it read as released rather than
	# as drawn. The collider follows the SAME curve as the visual — a tell that
	# lies about where the edge is would be worse than no tell at all.
	var k: float = clampf(_t / span, 0.0, 1.0)
	var grown: float = 1.0 - pow(1.0 - k, 2.4)
	var radius: float = lerpf(0.5, max_radius, grown)
	if _shape:
		_shape.radius = radius
	_draw(radius, k, _t)
	if _t >= span + TAIL:
		queue_free()


# --- Visual -------------------------------------------------------------------

func _build_ring(row: Dictionary) -> void:
	# Any Ring node left in the packed scene is replaced: the baked annulus is the
	# shared one every impact in the game uses, and two ring geometries is exactly
	# how a slam and a rock landing would stop agreeing about what a wave is.
	var old := get_node_or_null("Ring")
	if old:
		remove_child(old)
		old.queue_free()

	var tint: Color = row["ring_tint"]
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Double-sided: the co-op camera sits low and the wave passes under it, so the
	# inside of the ring is on screen as often as the outside.
	_ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ring_mat.albedo_color = Color(tint.r, tint.g, tint.b, _ring_alpha)
	_ring_mat.emission_enabled = true
	_ring_mat.emission = tint
	_ring_mat.emission_energy_multiplier = 2.2
	_ring_mat.disable_receive_shadows = true

	_ring = MeshInstance3D.new()
	_ring.name = "Ring"
	_ring.mesh = ImpactFX.ring_mesh()
	_ring.material_override = _ring_mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.position.y = ImpactFX.RING_LIFT
	add_child(_ring)


func _build_wall() -> void:
	_puff_ang.resize(RIM_PUFFS)
	_puff_lag.resize(RIM_PUFFS)
	_puff_rise.resize(RIM_PUFFS)
	_puff_size.resize(RIM_PUFFS)
	_puff_tint.resize(RIM_PUFFS)
	for i in RIM_PUFFS:
		# Evenly spaced, then jittered by up to half a slot. Even spacing alone
		# reads as a cog; pure scatter leaves gaps you can see the deck through.
		var slot: float = TAU * float(i) / float(RIM_PUFFS)
		_puff_ang[i] = slot + _rng.randf_range(-0.5, 0.5) * TAU / float(RIM_PUFFS)
		_puff_lag[i] = _rng.randf_range(1.0 - RIM_LAG, 1.0)
		_puff_rise[i] = _rng.randf_range(0.45, 1.0)
		_puff_size[i] = _rng.randf_range(0.7, 1.35)
		var g: float = _rng.randf_range(0.84, 1.16)
		_puff_tint[i] = Color(_dust_tint.r * g, _dust_tint.g * g, _dust_tint.b * g, 1.0)

	var mm := MultiMesh.new()
	# mesh, format, use_colors, THEN count — setting use_colors afterwards
	# reallocates the buffer and discards everything already written.
	mm.mesh = ImpactFX.dust_mesh()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = RIM_PUFFS
	# Explicit bounds around the fully grown wave, in this node's local space.
	# Godot derives a MultiMesh's AABB from its instance buffer and ours moves
	# every frame; a stale bound is a dust wall that vanishes when the camera
	# turns, which is a bug that only shows up in a capture.
	var reach: float = max_radius * 1.3
	mm.custom_aabb = AABB(Vector3.ONE * -reach, Vector3.ONE * reach * 2.0)

	_wall = MultiMeshInstance3D.new()
	_wall.name = "DustWall"
	_wall.multimesh = mm
	_wall.material_override = ImpactFX.dust_material()
	_wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_wall)


func _draw(radius: float, k: float, t: float) -> void:
	if _ring and is_instance_valid(_ring):
		_ring.scale = Vector3(radius, 1.0 - RING_FLATTEN * k, radius)
		# Bright and hard at the front, gone by the time the wave stops. Squared,
		# so it holds its brightness through the fast part of the sweep and then
		# drops away rather than dimming linearly from the first frame.
		_ring_mat.albedo_color.a = _ring_alpha * (1.0 - k * k)
		_ring_mat.emission_energy_multiplier = lerpf(3.2, 0.0, k)

	if _wall == null or not is_instance_valid(_wall):
		return
	var mm := _wall.multimesh
	var span: float = maxf(0.05, grow_time)
	for i in RIM_PUFFS:
		# Each puff sits at its own fraction of the rim, so the wall has depth
		# instead of being a hoop.
		var r: float = radius * _puff_lag[i]
		var ang: float = _puff_ang[i]
		# The wall climbs on a square root: fast off the deck, then hanging. Dust
		# thrown up by a passing front does not keep accelerating.
		var rise: float = RIM_RISE * max_radius * _puff_rise[i] * sqrt(clampf(t / span, 0.0, 1.0))
		var pos := Vector3(cos(ang) * r, rise * 0.5, sin(ang) * r)
		# Puffs grow with the wave: a fifteen-metre front needs bigger clumps than
		# an eleven-metre one or the wall reads as gravel.
		var size: float = _puff_size[i] * max_radius * 0.055 * (0.35 + 0.65 * k)
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * size), pos))
		# Fade in over the first fifth of the sweep, then out over the whole tail.
		var a: float = clampf(k / 0.18, 0.0, 1.0) * pow(1.0 - k, 1.3)
		var tint: Color = _puff_tint[i]
		mm.set_instance_color(i, Color(tint.r, tint.g, tint.b, a))


# --- Probe surface ------------------------------------------------------------

## The radius that can HIT you. Read by `_fx_probe`.
func wave_radius() -> float:
	return _shape.radius if _shape else 0.0


## The radius you can SEE. The two must agree to within a hair at every instant:
## a wave whose ring is ahead of its collider teaches the player to dodge too
## late, and one whose ring is behind it teaches them to dodge something that
## already hit them. `_fx_probe` measures the gap every frame of a full sweep.
func ring_radius() -> float:
	if _ring == null or not is_instance_valid(_ring):
		return 0.0
	return _ring.scale.x


## Puffs in the dust wall, for the budget assertions.
func wall_instances() -> int:
	if _wall == null or not is_instance_valid(_wall):
		return 0
	return _wall.multimesh.instance_count


# --- Damage -------------------------------------------------------------------

func _on_body_entered(body: Node) -> void:
	if body == null:
		return
	var id := body.get_instance_id()
	if _hit.has(id):
		return

	# The blast centre, read live. See `_begin()` for why this is not cached in
	# `_ready()` — the node is positioned after it enters the tree, and caching it
	# there measured every falloff and every knockback from world (0, 0, 0).
	var origin := global_position
	var here: Vector3 = (body as Node3D).global_position
	var flat := here - origin
	flat.y = 0.0
	var dist := flat.length()
	var dir := flat.normalized() if dist > 0.01 else Vector3.RIGHT

	if body.is_in_group("players"):
		_hit.append(id)
		# The wave delivers the damage and nothing else. The hero's end of the
		# blow — the burst at the point of contact — is drawn by
		# PlayerBase.take_hit(), which is where all five damage sources converge
		# and therefore the one place that cannot forget. A spark here as well
		# would double the burst on exactly the hits that already hurt most.
		body.take_hit(damage, dir * knockback + Vector3.UP * 6.0)
	elif body is PropBody:
		_hit.append(id)
		# Falls off toward the rim: barrels at the giant's feet are launched,
		# barrels at fifteen metres just topple.
		var falloff: float = clampf(1.0 - dist / max_radius, 0.15, 1.0)
		(body as PropBody).apply_hit_impulse(
			(dir + Vector3.UP * 0.7).normalized() * prop_impulse * falloff, here)
