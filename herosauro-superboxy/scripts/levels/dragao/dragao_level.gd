extends LevelBase
## Chapter 2, "O Tesouro do Dragão": the Estádio do Dragão at night under a full
## moon. The goblins have roped the stadium's blue dragon to the centre circle
## and run off with the club's cups.
##
##   Stage 1 "Liberta o dragão!" (4): bonk the four glowing stakes (three hits
##   each) while six goblins dance round him; every stake snaps its rope, the
##   last one frees him and he stands up and ROARS. The goblins panic.
##   Stage 2 "Recupera as taças!" (6): six goblins pour out of their van, each
##   holding a cup over its head, and run about the pitch. Bowl one over (a jab,
##   Dino Energy, Boxy's dash, or a football kicked into it: PUMBA!) and it drops
##   its cup; touch the cup and it arcs home into the trophy cabinet, which
##   lights up shelf by shelf. The dragon follows the heroes and roars at
##   carriers near him so they drop their cups (a helping paw).
##   Finale: the goblins sprint for the van, the dragon puffs one big cartoon
##   fire cloud at it, it goes sooty, they sit down dazed; three seconds later
##   GameManager.complete_chapter().
##
## A goblin bowled over twice is dizzy, then one of Herosauro's green energy
## pterodactyls swoops down and carries it away (the outro pages fly them to
## the river). Nothing is ever lost: there are no timers and no fail state.
##
## Progress goes ONLY through GameManager (set_objective, advance_objective,
## request_story_beat, complete_chapter). Everything is built once in _ready and
## reused: begin() (every run, PLAY AGAIN included) only resets state.

const L := preload("res://scripts/levels/dragao/dragao_layout.gd")
const M := preload("res://scripts/levels/dragao/dragao_mats.gd")
const StadiumBuilder := preload("res://scripts/levels/dragao/stadium_builder.gd")
const FX := preload("res://scripts/levels/dragao/dragao_fx.gd")
const Goblin := preload("res://scripts/levels/dragao/goblin.gd")
const Dragon := preload("res://scripts/levels/dragao/dragon.gd")
const Stake := preload("res://scripts/levels/dragao/stake.gd")
const Football := preload("res://scripts/levels/dragao/football.gd")
const Cup := preload("res://scripts/levels/dragao/cup.gd")
const Cabinet := preload("res://scripts/levels/dragao/cabinet.gd")
const Van := preload("res://scripts/levels/dragao/van.gd")
const Ptero := preload("res://scripts/levels/dragao/ptero.gd")
const SkyShader := preload("res://scripts/levels/dragao/night_sky.gdshader")

const STAGE1 := {"pt": "Liberta o dragão!", "en": "Free the dragon!"}
const STAGE2 := {"pt": "Recupera as taças!", "en": "Win back the cups!"}
enum Stage { ROPES, CUPS, FINALE }

const DANCERS := 6
const CARRIERS := 6
const GOBLIN_POOL := 12
const PTERO_POOL := 4
const POKE_TOKENS := 2
const PICKUP_RADIUS := 1.7
const STAGE2_DELAY := 2.6
const FINALE_HOLD := 3.0
const GIGGLE_GAP := 1.3

var fx: FX
var dragon: Dragon
var van: Van
var cabinet: Cabinet
var goblins: Array[Goblin] = []
var stakes: Array[Stake] = []
var balls: Array[Football] = []
var cups: Array[Cup] = []
var pteros: Array[Ptero] = []
var stage: int = Stage.ROPES
## Read by the probe: goblins a football has bowled over, and goblins the
## pterodactyls have carried off, this run.
var ball_knockdowns: int = 0
var goblins_carried: int = 0

var _heroes: Array[Node3D] = []
var _tokens: int = POKE_TOKENS
var _giggle_cd: float = 0.0
var _stage2_in: float = -1.0
var _victory_in: float = -1.0
var _finale_started: bool = false
var _scorched: bool = false
var _blockers: Array = []
var _pumba: Label3D
var _pumba_t: float = -1.0


func _ready() -> void:
	_build_environment()
	StadiumBuilder.build(self)
	fx = FX.new()
	fx.name = "FX"
	add_child(fx)

	cabinet = Cabinet.new()
	cabinet.name = "TrophyCabinet"
	cabinet.level = self
	cabinet.position = L.CABINET_POS
	add_child(cabinet)

	van = Van.new()
	van.name = "Van"
	van.level = self
	van.position = L.VAN_POS
	van.rotation.y = L.VAN_YAW
	add_child(van)

	dragon = Dragon.new()
	dragon.name = "Dragon"
	dragon.level = self
	add_child(dragon)
	dragon.roared.connect(_on_dragon_roared)
	dragon.fired.connect(_on_dragon_fired)

	for i in L.STAKES.size():
		var s: Stake = Stake.new()
		s.name = "Stake%d" % i
		var p: Vector3 = L.STAKES[i]
		s.position = p
		s.setup(self, Vector3(signf(p.x) * 0.55, 1.62, clampf(p.z * 0.4, -1.1, 1.1)))
		add_child(s)
		s.snapped.connect(_on_stake_snapped)
		stakes.append(s)

	for i in L.BALLS.size():
		var b: Football = Football.new()
		b.name = "Football%d" % i
		b.level = self
		b.home = L.BALLS[i]
		b.position = L.BALLS[i]
		add_child(b)
		balls.append(b)

	for i in CARRIERS:
		var c: Cup = Cup.new()
		c.name = "Cup%d" % i
		c.setup(self, i < 2, i)
		add_child(c)
		c.shelved.connect(_on_cup_shelved)
		cups.append(c)

	for i in GOBLIN_POOL:
		var g: Goblin = Goblin.new()
		g.name = "Goblin%d" % i
		g.setup(self, i % 2, 1000 + i * 7919)
		add_child(g)
		g.gone.connect(func(_g: Node3D) -> void: goblins_carried += 1)
		goblins.append(g)

	for i in PTERO_POOL:
		var pt: Ptero = Ptero.new()
		pt.name = "Pterodactyl%d" % i
		pt.level = self
		add_child(pt)
		pteros.append(pt)

	_build_pumba()
	# The dragon's soft circles (shared, updated in place) plus the van's.
	var d: Array = dragon.blockers()
	_blockers = [d[0], d[1], d[2]]
	var vf := Vector3(sin(L.VAN_YAW), 0, cos(L.VAN_YAW))
	for k in 3:
		_blockers.append([L.VAN_POS + vf * (float(k) - 1.0) * 1.7, 1.35])


# --- LevelBase -------------------------------------------------------------------

func spawn_point(player_id: int) -> Vector3:
	return to_global(L.SPAWN_1 if player_id != 2 else L.SPAWN_2)


## Stage 1 the co-op camera orbits the dragon in the centre circle (the pitch
## centre): he is solid, so nobody walks through the focus, and the stakes round
## him stay in shot. Stage 2 it looks steadily across the pitch toward the main
## stand, where the trophy cabinet lights up; the finale looks at the van.
func camera_focus() -> Vector3:
	match stage:
		Stage.CUPS:
			return to_global(Vector3(L.CABINET_POS.x * 0.5, 0.0, -75.0))
		Stage.FINALE:
			return to_global(L.VAN_POS)
	return to_global(dragon.position if dragon != null else L.DRAGON_POS)


func kill_y() -> float:
	return global_position.y - 10.0


func ground_surface() -> int:
	return ToonFactory.Surface.FLAT


func music_track() -> String:
	return "battle_phase1"


func begin() -> void:
	_heroes.clear()
	for h in get_tree().get_nodes_in_group("players"):
		_heroes.append(h as Node3D)
	stage = Stage.ROPES
	ball_knockdowns = 0
	goblins_carried = 0
	_tokens = POKE_TOKENS
	_giggle_cd = 0.0
	_stage2_in = -1.0
	_victory_in = -1.0
	_finale_started = false
	_scorched = false
	_pumba.visible = false
	_pumba_t = -1.0
	dragon.reset()
	van.reset()
	cabinet.reset()
	for s in stakes:
		s.reset()
	for b in balls:
		b.reset_ball()
	for c in cups:
		c.hide_cup()
	for g in goblins:
		g.deactivate()
	for p in pteros:
		p.cancel()
	for i in DANCERS:
		var a := TAU * float(i) / float(DANCERS) + 0.3
		goblins[i].activate(Vector3(cos(a) * 7.0, 0, sin(a) * 7.0), Goblin.S.DANCE)
	GameManager.set_objective(STAGE1, stakes.size())
	for h in _heroes:
		if h.has_method("face_toward"):
			h.face_toward(global_position)


func hint_target() -> Vector3:
	var from := _heroes[0].global_position if not _heroes.is_empty() and is_instance_valid(_heroes[0]) else global_position
	var best := Vector3.INF
	var best_d := INF
	match stage:
		Stage.ROPES:
			for s in stakes:
				if s.is_done():
					continue
				var d := from.distance_to(s.global_position)
				if d < best_d:
					best_d = d
					best = s.global_position + Vector3.UP * 2.2
		Stage.CUPS:
			for c in cups:
				if c.is_loose():
					var d2 := from.distance_to(c.global_position)
					if d2 < best_d:
						best_d = d2
						best = c.global_position + Vector3.UP * 1.6
			if best == Vector3.INF:
				var g := nearest_carrier(from)
				if g != null:
					best = g.global_position + Vector3.UP * 2.6
	return best


# --- Services for the cast (goblins, dragon, cups, pterodactyls) ---------------------

func nearest_hero(p: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for h in _heroes:
		if not is_instance_valid(h):
			continue
		var dx := h.global_position.x - p.x
		var dz := h.global_position.z - p.z
		var d := dx * dx + dz * dz
		if d < best_d:
			best_d = d
			best = h
	return best


func nearest_carrier(p: Vector3) -> Goblin:
	var best: Goblin = null
	var best_d := INF
	for g in goblins:
		if g.carrying == null or not g.is_hittable():
			continue
		var d := p.distance_squared_to(g.global_position)
		if d < best_d:
			best_d = d
			best = g
	return best


## Flat forward of whatever camera is drawing (the co-op rig in play).
func view_forward() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector3.FORWARD
	var f := -cam.global_basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 0.01 else Vector3.FORWARD


func dragon_position() -> Vector3:
	return dragon.position


func van_door() -> Vector3:
	return van.door_point()


func blockers() -> Array:
	return _blockers


func push_out_of_blockers(p: Vector3, r: float) -> Vector3:
	var out := p
	for c in _blockers:
		var centre: Vector3 = c[0]
		var rr: float = c[1] + r
		var d := Vector3(out.x - centre.x, 0, out.z - centre.z)
		var len := d.length()
		if len < rr and len > 0.001:
			out += d / len * (rr - len)
	return out


func take_poke_token() -> bool:
	if _tokens <= 0:
		return false
	_tokens -= 1
	return true


func give_poke_token() -> void:
	_tokens = mini(_tokens + 1, POKE_TOKENS)


func giggle(at: Vector3) -> void:
	if _giggle_cd > 0.0:
		return
	_giggle_cd = GIGGLE_GAP
	AudioManager.play_sfx(&"goblin_giggle", at)


func cup_dropped(cup: Cup, from: Vector3, push: Vector3) -> void:
	cup.drop(from, push)


## The dragon's helping roar: carriers within `radius` drop their cups.
func dragon_helped(at: Vector3, radius: float) -> void:
	for g in goblins:
		if g.carrying != null and Vector3(g.global_position.x - at.x, 0, g.global_position.z - at.z).length() < radius:
			g.scare_drop()


# --- Rules ------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_giggle_cd = maxf(0.0, _giggle_cd - delta)
	dragon.blockers()
	_bowl_with_balls()
	_summon_pteros()
	if stage == Stage.CUPS:
		_pick_up_cups()
	if _stage2_in > 0.0:
		_stage2_in -= delta
		if _stage2_in <= 0.0:
			_start_cups()
	if _victory_in > 0.0:
		_victory_in -= delta
		if _victory_in <= 0.0:
			GameManager.complete_chapter()
	_animate_pumba(delta)


func _on_stake_snapped(_stake: Node3D) -> void:
	GameManager.advance_objective(1)
	dragon.cheer()
	var left := 0
	for s in stakes:
		if not s.is_done():
			left += 1
	if left == 0:
		dragon.free_dragon()


func _on_dragon_roared() -> void:
	for g in goblins:
		if g.is_active():
			g.panic_leave()
	_stage2_in = STAGE2_DELAY


func _start_cups() -> void:
	stage = Stage.CUPS
	GameManager.set_objective(STAGE2, CARRIERS)
	GameManager.request_story_beat("d10")
	var door: Vector3 = van.door_point()
	var n := 0
	for g in goblins:
		if n >= CARRIERS:
			break
		if g.is_active():
			continue
		var off := Vector3(float(n % 3) - 1.0, 0, float(n / 3)) * 0.9
		g.activate(door + off, Goblin.S.ENTER)
		g.give_cup(cups[n])
		n += 1
	fx.sparkle(door + Vector3.UP * 1.2, Color(1.0, 0.9, 0.5), 1.4)


func _pick_up_cups() -> void:
	for c in cups:
		if not c.is_collectable():
			continue
		for h in _heroes:
			if not is_instance_valid(h):
				continue
			var d := Vector3(h.global_position.x - c.global_position.x, 0, h.global_position.z - c.global_position.z)
			if d.length() < PICKUP_RADIUS:
				c.collect(cabinet.slot_global(c.slot))
				GameManager.advance_objective(1)
				GameManager.request_shake(0.12, 0.12)
				break


func _on_cup_shelved(cup: Cup) -> void:
	cabinet.cup_arrived(cup.slot)
	var home := 0
	for c in cups:
		if c.is_shelved():
			home += 1
	if home >= cups.size() and not _finale_started:
		_start_finale()


func _start_finale() -> void:
	_finale_started = true
	stage = Stage.FINALE
	var i := 0
	for g in goblins:
		if g.is_active():
			g.run_to_van(van.huddle_point(i))
			i += 1
	dragon.breathe_fire_at(van.global_position)


func _on_dragon_fired() -> void:
	if _scorched:
		return
	_scorched = true
	van.scorch()
	for g in goblins:
		if g.is_active():
			g.sit_dazed()
	fx.sparkle(van.global_position + Vector3.UP * 2.5, Color(1.0, 0.7, 0.3), 1.8)
	_victory_in = FINALE_HOLD


## A football moving faster than BOWL_SPEED that touches a goblin knocks it
## over: the book's "PUMBA!".
func _bowl_with_balls() -> void:
	for b in balls:
		if not is_instance_valid(b) or b.sleeping:
			continue
		var v := b.linear_velocity
		if v.length() < Football.BOWL_SPEED:
			continue
		for g in goblins:
			if not g.is_hittable():
				continue
			var d: Vector3 = b.global_position - g.centre()
			if d.length() < Football.RADIUS + 0.6:
				Hurtbox.strike(g, 10, Vector3(v.x, 0, v.z).normalized() * 6.0 + Vector3.UP * 3.0, 1)
				b.rebound(d)
				ball_knockdowns += 1
				_show_pumba(g.global_position + Vector3.UP * 1.8)
				GameManager.hit_stop(0.04)
				GameManager.request_shake(0.2, 0.16)
				break


func _summon_pteros() -> void:
	for g in goblins:
		if not g.is_waiting_for_ptero():
			continue
		for p in pteros:
			if not p.busy:
				p.swoop(g)
				g.claim_ptero(p)
				break


# --- PUMBA! ------------------------------------------------------------------------

func _build_pumba() -> void:
	_pumba = Label3D.new()
	_pumba.name = "Pumba"
	_pumba.text = "PUMBA!"
	_pumba.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_pumba.no_depth_test = true
	_pumba.fixed_size = false
	_pumba.pixel_size = 0.01
	_pumba.font_size = 96
	_pumba.outline_size = 28
	_pumba.modulate = Color(1.0, 0.86, 0.15)
	_pumba.outline_modulate = Color(0.85, 0.12, 0.1)
	if ResourceLoader.exists("res://assets/fonts/Bangers.woff2"):
		_pumba.font = load("res://assets/fonts/Bangers.woff2") as Font
	_pumba.visible = false
	add_child(_pumba)


func _show_pumba(at: Vector3) -> void:
	_pumba.global_position = at
	_pumba.visible = true
	_pumba_t = 0.0


func _animate_pumba(delta: float) -> void:
	if _pumba_t < 0.0:
		return
	_pumba_t += delta
	var k := _pumba_t / 0.9
	var pop := 1.35 - 0.35 * clampf(_pumba_t / 0.15, 0.0, 1.0) if _pumba_t > 0.15 else _pumba_t / 0.15 * 1.35
	_pumba.scale = Vector3.ONE * maxf(0.05, pop)
	_pumba.position.y += delta * 0.8
	_pumba.modulate.a = 1.0 - smoothstep(0.6, 1.0, k)
	_pumba.outline_modulate.a = _pumba.modulate.a
	if k >= 1.0:
		_pumba.visible = false
		_pumba_t = -1.0


# --- Night and floodlights ----------------------------------------------------------

func _build_environment() -> void:
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = SkyShader
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.58, 0.82)
	env.ambient_light_energy = 0.8
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 0.95
	env.fog_enabled = true
	env.fog_light_color = Color(0.1, 0.15, 0.32)
	env.fog_density = 0.0035
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	var we := WorldEnvironment.new()
	we.name = "Environment"
	we.environment = env
	add_child(we)

	# The floodlights, as one strong warm-white key: the only shadow caster.
	var key := DirectionalLight3D.new()
	key.name = "Floodlights"
	key.light_color = Color(1.0, 0.97, 0.9)
	key.light_energy = 1.35
	key.shadow_enabled = true
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	key.directional_shadow_max_distance = 55.0
	key.rotation_degrees = Vector3(-60.0, 155.0, 0.0)
	add_child(key)

	# Moonlight fill from the other side, blue, no shadows.
	var moon := DirectionalLight3D.new()
	moon.name = "Moonlight"
	moon.light_color = Color(0.55, 0.66, 1.0)
	moon.light_energy = 0.45
	moon.shadow_enabled = false
	moon.rotation_degrees = Vector3(-38.0, -25.0, 0.0)
	add_child(moon)


# --- Probe helpers -------------------------------------------------------------------

## Put `hero` on the grass `dist` metres from `target` (level space), on the
## side away from the dragon unless `from_dir` says otherwise, facing it. For
## _dragao_probe and the shot tool, to skip the walking: every objective step
## is still won by a real hit or a real pickup.
func place_hero_near(hero: Node3D, target: Vector3, dist: float, from_dir: Vector3 = Vector3.ZERO) -> void:
	var away := Vector3(from_dir.x, 0, from_dir.z)
	if away.length() < 0.1:
		away = Vector3(target.x - dragon.position.x, 0, target.z - dragon.position.z)
	if away.length() < 0.1:
		away = Vector3.BACK
	var p := L.clamp_to_pitch(target + away.normalized() * dist, 0.6)
	p.y = 1.0
	hero.global_position = to_global(p)
	if hero is CharacterBody3D:
		(hero as CharacterBody3D).velocity = Vector3.ZERO
	if hero.has_method("face_toward"):
		hero.face_toward(to_global(target))


## The goblin currently holding `cup`, or null.
func carrier_of(cup: Cup) -> Goblin:
	for g in goblins:
		if g.carrying == cup:
			return g
	return null
