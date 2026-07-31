class_name BreakableProp
extends PropBody
## A prop that comes apart when it has taken enough punishment.
##
## --- Three triggers, because there are three ways a prop dies ---------------
##
##  1. Accumulated damage. A blow of at least `break_impulse` costs the prop one
##     of its `toughness` points; the one that empties it bursts the prop. This
##     is the Crash interaction, and it is the reason the numbers moved this
##     pass: a hero's swing carries 9.0 N*s and the crate's threshold was 12.0,
##     so **no hero in this game could break a single prop.** Only the giant
##     could. Smashing a crate is the most recognisable interaction in the genre
##     and it was reachable by exactly nobody.
##  2. An overwhelming single blow — `shatter_impulse` — which skips the
##     accumulator entirely. That is what makes granite feel like granite: three
##     hero swings, or one slam.
##  3. Being hurled into something, measured as a sudden loss of speed across one
##     physics frame (PropBody tracks it) rather than through contact monitoring:
##     it needs no contact_monitor budget and behaves identically on Jolt and
##     Godot Physics.
##
## --- The five-part impact contract ------------------------------------------
##
## ARCHITECTURE.md, "Weight — every action": a visual FX, a camera response, an
## audio transient, a hit-stop and a UI acknowledgement, or it is not finished.
## Before this pass a shattering prop had one and a half of the five — grey
## debris cubes, and the BOSS's hit sample played on a barrel. `shatter()` now
## fires all five and `_take_damage()` fires the three a non-fatal blow is
## entitled to. See the report's table.
##
## --- What a smashed prop pays -----------------------------------------------
##
## Score, and only score. See PAYOUT below for the argument and for why it must
## never touch the combo chain.
##
## Piece count is a request, not a promise: DebrisPiece owns a process-wide
## budget and hands back fewer shards when the arena is already full of them.
## The shard recipe is ORDERED so the pieces that carry the read — planks,
## staves, chunks — are spawned first and the garnish is what the budget drops.

@export_group("Breaking")
## Impulse magnitude (N*s) a blow must carry to damage this at all. Below it the
## prop is only shoved. The ladder it has to sit under: hero swing 9.0, giant's
## prop sweep 26.0, rock 30.0, dino orb 34.5, shockwave 38.0, slam 45.0.
@export var break_impulse: float = 6.0
## How many qualifying blows it takes. 1 = the Crash crate.
@export var toughness: int = 1
## A single blow this hard destroys it outright whatever its remaining toughness.
@export var shatter_impulse: float = 24.0
## Speed (m/s) that has to vanish in a single physics frame — i.e. how hard it
## must slam into something — to shatter on impact. Must stay clear of the speed
## a prop reaches falling from its spawn height; prop_spawner.gd drops them from
## SETTLE_DROP and _props_probe.gd asserts the margin per prop.
@export var break_delta_v: float = 7.0
@export var piece_count: int = 11
@export var piece_lifetime: float = 4.0
## Non-zero pins the debris scatter so a replay looks identical. The spawner
## sets it; leave 0 to derive one from the prop's resting position.
@export var rng_seed: int = 0

@export_group("Payout")
## Score for a blow the prop survived. Small: it is the UI half of "that
## connected", not a reward.
@export var chip_score: int = 5
## Score for destroying it.
@export var break_score: int = 15

# --- PAYOUT: the design call -------------------------------------------------
#
# In Crash a crate always pays out, and a prop that gives a hero nothing for the
# two seconds spent on it is scenery rather than interaction. But this is a co-op
# boss fight, so the payout has three constraints a platformer's does not:
#
#   * It must not be a resource the heroes are ever correct to farm. Score is the
#     right currency precisely because it is a TEAM number with no mechanical
#     effect — nobody wins the fight faster by smashing barrels, and the results
#     screen is the only place it is ever cashed.
#   * It must not touch the combo chain. `combo` only moves through
#     `damage_boss()`, and the multiplier it earns is what makes a sustained
#     assault on the giant worth more than the same number of scattered hits.
#     Letting props feed it would make scenery the cheapest way to build a
#     multiplier, which is exactly the "props fight the fight" failure the brief
#     forbids — in a stronger form, because it would be mathematically correct.
#   * It must LOSE, per second, to hitting the giant. A boss hit is
#     SCORE_PER_HIT (10) times the hero's live combo, so a hero three hits into a
#     chain already earns 30 a swing and rising. The whole deck — six barrels,
#     four crates, four blocks — pays 355 for 26 swings. _props_probe.gd measures
#     that ratio against a short chained assault, so the claim stays true if
#     anyone retunes either side.
#
# No collectible spawns, no pickup, no new signal, no new economy: `add_score()`
# already exists and `score_changed` already drives a HUD readout that rolls up
# and lights gold, which is a real leg-5 acknowledgement for free.

## Colour of forty litres of Ruby port leaving a cask at speed. ImpactFX owns the
## splash itself; this is the tint on the physical droplets a CRACKED — not yet
## burst — cask leaves on the deck, and it is deliberately the same RGB as
## `ImpactFX.PORT_WINE` so the spill and the mist are one liquid.
const PORT_RED := Color(0.30, 0.045, 0.09)

## Damage-state cues.
const SQUASH_RETURN := 0.16
## How much a masonry block loses off its own dimensions per chunk knocked out.
const CRUMBLE_STEP := 0.93
## Physical port droplets live briefly — they are a spill, not wreckage.
const DROPLET_LIFETIME := 1.4

var _shattered: bool = false
var _shard_rng := RandomNumberGenerator.new()
var _damage: int = 0
var _visual_scale: float = 1.0
var _squash: Tween = null


func _ready() -> void:
	super._ready()
	# The drawn parts already carry this instance's size variation, so every later
	# cue (squash, crumble) has to work relative to it rather than to 1.0 — or the
	# first hit would snap a small crate back to full size.
	_visual_scale = size_scale()
	# Seeded here rather than at shatter time, so the SAME generator drives the
	# chips knocked off along the way and the final burst. A prop's whole life is
	# one deterministic stream. ARCHITECTURE.md rule 4.
	if rng_seed != 0:
		_shard_rng.seed = rng_seed
	else:
		var p := global_position
		_shard_rng.seed = hash("brk|%.2f|%.2f|%.2f" % [p.x, p.y, p.z])


func _on_impact(strength: float, at: Vector3, impulse: Vector3) -> void:
	if _shattered:
		return
	if strength >= shatter_impulse:
		# Overwhelming. Carry the blow's direction into the debris.
		shatter(impulse.normalized() * 3.5)
		return
	if strength < break_impulse:
		# Not a damaging blow — a shove. Still owes the three legs a shove earns.
		_impact_response(strength, at, impulse)
		return
	_take_damage(strength, at, impulse)


## Hurled into something. Hard enough and it bursts whatever its toughness — a
## cask that hits a rail wall at 8 m/s does not care that it had a hit left.
func _on_deck_impact(dv: float, at: Vector3, incoming: Vector3) -> void:
	if _shattered:
		return
	if is_armed() and dv >= break_delta_v:
		# Shatter along the direction it was travelling: the pieces carry on
		# through, which is what sells the impact.
		shatter(incoming.normalized() * 3.0)
		return
	_land_response(dv, at)


## Rack up one point of damage and either burst or show the wear.
func _take_damage(strength: float, at: Vector3, impulse: Vector3) -> void:
	_damage += 1
	if _damage >= toughness:
		shatter(impulse.normalized() * 2.5)
		return

	# Survived it. Legs 1-3 from PropBody, plus the two cues that make a
	# multi-hit prop legible: it visibly loses material, and it visibly deforms.
	_impact_response(strength, at, impulse)
	_award(chip_score)
	_spawn_chips(at, impulse)
	if surface_kind() == ToonFactory.Surface.GRANITE:
		# Masonry does not dent, it loses corners. Shrink with each chunk taken
		# out, so three blows read as a block being worn away. Before the squash,
		# because the squash returns to whatever _visual_scale is by then.
		_crumble(CRUMBLE_STEP)
	_squash_pulse()
	if body_kind == "barrel":
		# A cracked cask starts losing what is in it, which is both the material
		# tell and the single most Porto thing on the deck.
		_bleed(at)


## Replace this prop with its shards. `push` is added to every shard's launch
## velocity so a directional blow throws the debris the right way.
func shatter(push: Vector3 = Vector3.ZERO) -> void:
	if _shattered:
		return
	_shattered = true

	var root := _spawn_root()
	var recipe := _shard_recipe()
	var wanted: int = mini(mini(piece_count, recipe.size()), DebrisPiece.budget_left())
	var here := global_position
	for i in wanted:
		_launch(root, recipe[i], here, push, 1.0)

	# --- The five legs, in order ---------------------------------------------
	# `energy` is the prop's mass against the heaviest thing on the deck, so a
	# granite block is a bigger event than a crate on every one of them.
	var energy := clampf(mass / 90.0, 0.35, 1.0)

	# 1. Visual FX at the point of contact. The shards above are the physical
	#    half; ImpactFX.smash is the burst — a fan of surface-correct chips, dust
	#    scaled to the material, a ground ring, the iron of the trim as its own
	#    second material, and the port for a cask.
	ImpactFX.smash(self, here, int(surface_kind()), extent(), push, _fx_seed(),
		trim_kind(), _liquid())
	# 2. Camera response.
	GameManager.request_shake(0.13 + 0.17 * energy, 0.16 + 0.06 * energy)
	# 3. Audio transient.
	play_surface_break()
	# 4. Hit-stop, proportional to the mass that just stopped existing. A crate is
	#    three frames at 90 Hz, a granite block five. GameManager.hit_stop
	#    self-guards against re-entry, so five barrels caught by one slam freeze
	#    once between them rather than five times.
	#
	#    Gated on PLAYING for the same reason the score is: props are also
	#    destroyed by the world being torn down and by falling off the bridge
	#    after the fight, and a results screen that stutters is a bug report.
	if GameManager.state == GameManager.State.PLAYING:
		GameManager.hit_stop(0.022 + 0.035 * energy)
	# 5. UI acknowledgement.
	_award(break_score)

	queue_free()


func has_shattered() -> bool:
	return _shattered


## Damage taken so far, for the probe.
func damage_taken() -> int:
	return _damage


# --- Shard recipes ----------------------------------------------------------

## What this prop comes apart into, most important piece first.
##
## Ordered, because DebrisPiece's budget truncates the list: when the arena is
## already full of debris a barrel should still throw staves and merely lose its
## offcuts, rather than throwing a random subset of everything.
##
## Every entry is {mesh, collider, material, mass, speed}. `speed` scales the
## launch: splinters leave fast and light, a stave leaves heavy and slow, and an
## iron hoop leaves slowest of all. That spread is most of what makes a burst
## read as one object coming apart rather than as a uniform puff.
func _shard_recipe() -> Array[Dictionary]:
	var e := extent()
	var body_mat := _surface_material()
	var trim_mat := trim_material()
	var out: Array[Dictionary] = []

	match body_kind:
		"barrel":
			# Staves first: they are the barrel. Six of them at the cask's own
			# length, bowed to its own curvature.
			var stave_len := e * 1.55
			var stave_w := e * 0.34
			var stave_t := e * 0.11
			for i in 6:
				out.append({
					"mesh": PropMeshKit.stave(stave_len, stave_w, stave_t),
					"collider": Vector3(stave_len * 0.9, stave_t, stave_w),
					"material": body_mat, "mass": 2.4, "speed": 0.85,
				})
			# Then the two iron hoops, sheared open. Heavier and slower — a hoop
			# lands and rings rather than flying.
			for i in 2:
				out.append({
					"mesh": PropMeshKit.hoop_arc(e * 0.75, e * 0.14, 4, PI * 0.9),
					"collider": Vector3(e * 1.1, e * 1.1, e * 0.16),
					"material": trim_mat, "mass": 4.0, "speed": 0.6,
				})
			# Then short offcuts. Last, so it is what the budget drops.
			for i in 3:
				out.append({
					"mesh": PropMeshKit.splinter(e * 0.7, e * 0.11),
					"collider": Vector3.ONE * e * 0.22,
					"material": body_mat, "mass": 0.8, "speed": 1.45,
				})
		"crate":
			var plank_len := e * 1.5
			var plank_w := e * 0.7
			var plank_t := e * 0.14
			for i in 5:
				out.append({
					"mesh": PropMeshKit.plank(plank_len, plank_w, plank_t),
					"collider": Vector3(plank_len, plank_t, plank_w),
					"material": body_mat, "mass": 1.8, "speed": 1.0,
				})
			# Two iron corner straps.
			for i in 2:
				out.append({
					"mesh": PropMeshKit.plank(e * 0.7, e * 0.22, e * 0.07),
					"collider": Vector3(e * 0.7, e * 0.07, e * 0.22),
					"material": trim_mat, "mass": 2.2, "speed": 0.8,
				})
			for i in 4:
				out.append({
					"mesh": PropMeshKit.splinter(e * 0.85, e * 0.10),
					"collider": Vector3.ONE * e * 0.24,
					"material": body_mat, "mass": 0.7, "speed": 1.5,
				})
		_:
			# Masonry: a few real chunks, then grit.
			for i in 4:
				out.append({
					"mesh": PropMeshKit.chunk(e * 0.72, i),
					"collider": Vector3.ONE * e * 0.62,
					"material": body_mat, "mass": 4.5, "speed": 0.7,
				})
			for i in 5:
				out.append({
					"mesh": PropMeshKit.chunk(e * 0.30, i + 4),
					"collider": Vector3.ONE * e * 0.26,
					"material": body_mat, "mass": 1.0, "speed": 1.25,
				})
	return out


## The small pieces a blow the prop SURVIVED knocks loose. Taken from the TAIL of
## the recipe (offcuts, splinters, grit) so they are visibly the small stuff, and
## capped at three: chips off a three-hit block must not eat the budget the burst
## is going to need.
func _spawn_chips(at: Vector3, impulse: Vector3) -> void:
	var recipe := _shard_recipe()
	if recipe.is_empty():
		return
	var root := _spawn_root()
	var n: int = mini(3, DebrisPiece.budget_left())
	var dir := impulse.normalized()
	var tail: int = mini(4, recipe.size())
	for i in n:
		var r: Dictionary = recipe[recipe.size() - 1 - (i % tail)]
		_launch(root, r, at, dir * 2.0, 0.55)


## Port leaving a cracked cask. Physical droplets rather than an FX burst,
## because the point is that the deck under a damaged barrel gets wet and stays
## wet for a beat — the burst's own splash is ImpactFX's job and arrives later.
func _bleed(at: Vector3) -> void:
	var root := _spawn_root()
	var n: int = mini(2, DebrisPiece.budget_left())
	var e := extent()
	for i in n:
		_launch(root, {
			"mesh": PropMeshKit.droplet(e * 0.34),
			"collider": Vector3.ONE * e * 0.24,
			"material": _port_material(), "mass": 0.5, "speed": 1.3,
			"lifetime": DROPLET_LIFETIME,
		}, at, Vector3.ZERO, 0.7)


## What the prop was full of, for ImpactFX.smash's liquid channel.
func _liquid() -> Color:
	return ImpactFX.PORT_WINE if body_kind == "barrel" else ImpactFX.NO_LIQUID


# --- Damage cues ------------------------------------------------------------

## Squash and stretch on a prop that took a hit and held. ARCHITECTURE.md asks
## for it on "everything that moves"; a crate that absorbs a swing without
## deforming reads as a static collider being nudged.
func _squash_pulse() -> void:
	var parts := _meshes(self)
	if parts.is_empty():
		return
	if _squash != null and _squash.is_valid():
		_squash.kill()
	# Flattened along the body's own Y. 1.14^2 * 0.82 = 1.07, i.e. a touch of
	# gain rather than exact volume preservation — at this duration the eye reads
	# gain as impact and loss as deflation.
	var flat := Vector3(1.14, 0.82, 1.14) * _visual_scale
	_squash = create_tween()
	_squash.set_parallel(true)
	for mi in parts:
		mi.scale = flat
		_squash.tween_property(mi, "scale", Vector3.ONE * _visual_scale, SQUASH_RETURN) \
			.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## Take a bite out of the block: shrink both the drawn mesh AND the collider, so
## a worn-down block is genuinely smaller rather than merely looking it.
func _crumble(factor: float) -> void:
	_visual_scale *= factor
	_apply_visual_scale(_visual_scale)
	var node := _own_collision_node()
	if node == null or node.shape == null:
		return
	# Duplicate before resizing: sub-resources are shared between instances of a
	# PackedScene, so resizing in place would shrink every block in the arena.
	var s := node.shape.duplicate() as Shape3D
	if s is BoxShape3D:
		(s as BoxShape3D).size *= factor
	elif s is CylinderShape3D:
		var cyl := s as CylinderShape3D
		cyl.radius *= factor
		cyl.height *= factor
	elif s is SphereShape3D:
		(s as SphereShape3D).radius *= factor
	node.shape = s


# --- Internals --------------------------------------------------------------

## Throw one shard. `scale_speed` lets a chip leave at a fraction of a full
## burst's energy without a second copy of the launch maths.
func _launch(root: Node3D, r: Dictionary, from: Vector3, push: Vector3,
		scale_speed: float) -> void:
	if root == null:
		return
	var dir := Vector3(
		_shard_rng.randf_range(-1.0, 1.0),
		_shard_rng.randf_range(0.25, 1.0),
		_shard_rng.randf_range(-1.0, 1.0)).normalized()
	var speed: float = float(r.get("speed", 1.0)) * scale_speed
	var vel := push * scale_speed + dir * _shard_rng.randf_range(2.5, 6.5) * speed \
		+ linear_velocity * 0.4
	var spin := Vector3(
		_shard_rng.randf_range(-8.0, 8.0),
		_shard_rng.randf_range(-8.0, 8.0),
		_shard_rng.randf_range(-8.0, 8.0))
	# Random start orientation. Without it every plank leaves the burst lying the
	# same way up and the debris reads as a fan rather than as wreckage.
	var orient := Basis.from_euler(Vector3(
		_shard_rng.randf_range(-PI, PI),
		_shard_rng.randf_range(-PI, PI),
		_shard_rng.randf_range(-PI, PI)))
	DebrisPiece.spawn(root, from + dir * extent() * 0.6, vel,
		r["mesh"] as Mesh, r["collider"] as Vector3, r["material"] as Material,
		float(r.get("lifetime", piece_lifetime)), spin, orient, float(r.get("mass", 3.0)))


## Score only counts during a live fight. Props are also destroyed by the world
## being torn down and by falling off the bridge between runs, and a score that
## moves on the results screen is a bug report.
func _award(points: int) -> void:
	if points <= 0 or GameManager.state != GameManager.State.PLAYING:
		return
	GameManager.add_score(points)


func _port_material() -> StandardMaterial3D:
	# Roughness 0.18: liquid is the one thing on this deck with a real specular
	# kick, and the RUBRIC's "wetness" line is most of what makes it read.
	return ToonFactory.solid(PORT_RED, 0.0, 0.18, 0.0)


## Debris goes into the spawn root so main.gd's between-runs sweep collects it.
func _spawn_root() -> Node3D:
	var root := get_tree().get_first_node_in_group("spawn_root") as Node3D
	if root == null:
		root = get_parent() as Node3D
	return root
