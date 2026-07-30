extends Node
## Headless regression probe for Adamastor.
##
## Every check in here MEASURES something and prints the number it got. That is
## deliberate: the three defects this pass fixed were all handed over as
## measurements ("the shove flings a hero 6.5 m", "the giant attacks a body that
## refuses damage"), and a probe that only asserts a boolean cannot tell the next
## person whether a change made a number better or merely kept it legal.
##
## What it measures:
##
##   * the tuning ladder — that difficulty and roster both still move the giant's
##     cadence in the right direction, and that the two gaps belonging to the
##     PLAYER (the wind-up and the retreat) do not move at all
##   * telegraph honesty — the gap between a mark promising an impact and the
##     impact actually resolving, per attack kind. This is the one that catches
##     the fx stream retuning the rock arc under us.
##   * the push-out — how much of a sustained melee exchange a hero spends unable
##     to reach the giant, over three consecutive windows so a push that
##     ACCUMULATES shows up as a trend, plus how far inside him a hero ever gets
##   * time to recover — how long a shoved hero needs to get back in swing range
##   * aggro — that a downed hero is never targeted, and that the giant turns on
##     whoever is hurting him most
##   * volley coverage and per-hero damage share across a simulated fight
##
## Headless-safe: nothing here reads the framebuffer.
##
##   godot --headless --path . scripts/boss/_boss_probe.tscn

const MainScene: PackedScene = preload("res://scenes/main.tscn")

## Physics ticks per second, used to turn seconds into settle() frames.
const TICK := 90.0
## The giant's collider is 5 x 9 x 4, so his surface stands 2.5 m (front) or
## 2.0 m (side) out from his origin. A hero whose swing volume reaches
## attack_range from their own centre can therefore connect from this far out.
const FRONT_HALF := 2.5
const SIDE_HALF := 2.0

## Tolerances. The slam is a pure timer, so it is held to a couple of frames; the
## rock has a flight time the boss can only MIRROR from the fx stream's solve, so
## it is held to a beat instead. See AdamastorStateMachine.ROCK_ARC_TIME.
const SLAM_TOLERANCE := 0.05
const ROCK_TOLERANCE := 0.15
const ROAR_TOLERANCE := 0.06

var _pass: int = 0
var _fail: int = 0
var _main: Node = null
var _clock: float = 0.0

## kind -> Array[float] of clock times.
var _promised: Dictionary = {}
var _landed: Dictionary = {}
var _damage_by_hero: Dictionary = {}


func _ready() -> void:
	await get_tree().process_frame
	await _run()
	print("\nboss probe: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _process(delta: float) -> void:
	# Telegraphs and attack tweens are both idle-driven, so the clock they are
	# measured against has to be too. Accumulated delta, never a wall clock —
	# ARCHITECTURE.md rule 5, and the reason the capture gate works at all.
	_clock += delta


func _run() -> void:
	await _check_tuning_ladder()
	await _check_downed_is_never_targeted()
	await _check_threat_focus()
	await _check_push_out()
	await _check_slam_telegraph()
	await _check_rock_telegraph_and_volley()
	await _check_roar()
	await _check_damage_share()


# --- Tuning ladder ----------------------------------------------------------

## Difficulty and roster are two independent knobs on the same numbers, and it is
## easy to add one and silently break the other. This reads what the FSM actually
## derived rather than re-deriving it here, so it fails when the tuning changes
## shape and not when a constant is retuned on purpose.
func _check_tuning_ladder() -> void:
	var solo := {}
	var duo := {}
	for d in [GameManager.Difficulty.EASY, GameManager.Difficulty.NORMAL,
			GameManager.Difficulty.HARD]:
		solo[d] = await _tuning_for(1, d)
		duo[d] = await _tuning_for(2, d)

	print("  -- decide interval (s): solo %.2f/%.2f/%.2f  co-op %.2f/%.2f/%.2f  (easy/normal/hard)"
		% [solo[0]["decide_interval"], solo[1]["decide_interval"], solo[2]["decide_interval"],
			duo[0]["decide_interval"], duo[1]["decide_interval"], duo[2]["decide_interval"]])
	print("  -- slam gap (s):        solo %.2f  co-op %.2f    retreat (fixed): %.2f    speed: solo %.2f  co-op %.2f"
		% [solo[1]["slam_gap"], duo[1]["slam_gap"], solo[1]["retreat_time"],
			solo[1]["move_speed"], duo[1]["move_speed"]])

	_ok(solo[0]["decide_interval"] > solo[1]["decide_interval"]
		and solo[1]["decide_interval"] > solo[2]["decide_interval"],
		"difficulty still shortens the solo decision interval")
	_ok(duo[0]["decide_interval"] > duo[1]["decide_interval"]
		and duo[1]["decide_interval"] > duo[2]["decide_interval"],
		"difficulty still shortens the co-op decision interval")
	for d in [0, 1, 2]:
		_ok(duo[d]["decide_interval"] < solo[d]["decide_interval"],
			"a second hero raises the cadence at difficulty %d (%.2f < %.2f)"
				% [d, duo[d]["decide_interval"], solo[d]["decide_interval"]])
	_ok(duo[1]["slam_gap"] < solo[1]["slam_gap"],
		"a second hero shortens the giant's own hesitation between slams")

	# The two gaps the roster must NOT shrink, because they belong to the player:
	# the wind-up is the tell and the retreat is the punish window. Dividing the
	# retreat by the roster cost the heroes enough ground that the co-op stream's
	# melee assertions failed three runs in five — this is the regression test for
	# that, and it is why the retreat is measured here at all.
	_ok(is_equal_approx(duo[1]["slam_windup"], solo[1]["slam_windup"]),
		"the slam wind-up is roster-independent (%.3f s either way)" % solo[1]["slam_windup"])
	_ok(is_equal_approx(duo[1]["retreat_time"], solo[1]["retreat_time"]),
		"the retreat window is roster-independent (%.3f s either way)" % solo[1]["retreat_time"])

	# ...and he must never match a hero's sprint, even at his angriest, or running
	# away stops being an answer to anything. HARD co-op phase two is the corner
	# that blows through it: 5.8 * 1.4 * 1.1 * 1.2 = 10.7 m/s uncapped. Escalated
	# for real rather than by re-deriving the formula here, so a change to the
	# escalation is caught instead of being copied.
	await _to_menu()
	GameManager.set_difficulty(GameManager.Difficulty.HARD)
	await _start(2, 1)
	await _settle(4)
	GameManager.damage_boss(int(GameManager.MAX_BOSS_HEALTH * 0.55), 1)
	await _settle(4)
	var hot: Dictionary = _boss().tuning()
	var sprint := 8.0 * 1.3
	print("  -- HARD co-op phase two: %.2f m/s vs a hero's %.2f m/s sprint, decide %.2f s, slam gap %.2f s"
		% [hot["move_speed"], sprint, hot["decide_interval"], hot["slam_gap"]])
	_ok(bool(hot["escalated"]), "crossing half health escalates the tuning")
	_ok(float(hot["move_speed"]) < sprint,
		"his top speed %.2f m/s stays under a hero's sprint" % hot["move_speed"])
	_ok(float(hot["decide_interval"]) < float(duo[2]["decide_interval"]),
		"phase two tightens the cadence further (%.2f < %.2f)"
			% [hot["decide_interval"], duo[2]["decide_interval"]])


func _tuning_for(count: int, difficulty: int) -> Dictionary:
	await _to_menu()
	GameManager.set_difficulty(difficulty)
	await _start(count, 1)
	await _settle(4)
	return (_boss().tuning() as Dictionary).duplicate()


# --- Aggro ------------------------------------------------------------------

## A hero at zero health stays in the `players` group on purpose (GameManager's
## defeat test asks the scene, not a table), so the giant used to spend the whole
## ~4 s knockdown hitting a body that refuses damage while the partner hit him
## for free. Measured with the downed hero placed CLOSER, which is the case
## distance-only targeting gets wrong.
func _check_downed_is_never_targeted() -> void:
	await _to_menu()
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)
	await _start(2, 1)
	await _settle(60)

	var boss := _boss()
	var a := _hero(1)
	var b := _hero(2)
	GameManager.damage_player(1, GameManager.MAX_PLAYER_HEALTH)
	await get_tree().physics_frame
	_ok(a.is_downed(), "hero 1 is down")

	var picked_downed := 0
	var picked_nearest_downed := 0
	for i in 150:
		a.global_position = boss.global_position + Vector3(-4.0, 1.0, 0.0)
		b.global_position = boss.global_position + Vector3(-11.0, 1.0, 0.0)
		await get_tree().physics_frame
		if boss.target_player() == a:
			picked_downed += 1
		if boss.nearest_player() == a:
			picked_nearest_downed += 1
	_ok(picked_downed == 0,
		"target_player() never picks the downed hero even at 4 m vs 11 m (%d/150 frames)"
			% picked_downed)
	_ok(picked_nearest_downed == 0,
		"nearest_player() skips the downed hero (%d/150 frames)" % picked_nearest_downed)
	_ok(boss.target_player() == b, "he goes for the hero who can still fight back")


## Threat, not just distance. The number that matters is that a hero can PULL the
## giant off their partner by out-damaging them, because that is the only thing
## that stops one hero tanking while the other farms from behind.
func _check_threat_focus() -> void:
	await _to_menu()
	await _start(2, 1)
	await _settle(60)

	var boss := _boss()
	var a := _hero(1)
	var b := _hero(2)
	boss.global_position = Vector3(0.0, 2.0, 0.0)
	a.global_position = Vector3(-6.0, 2.0, 0.0)
	b.global_position = Vector3(-9.0, 2.0, 0.0)
	_ok(boss.target_player() == a,
		"with nobody hurting him he takes the nearer hero (6 m vs 9 m)")

	# Six connected hits from the far hero: a full chain and the whole of the
	# fight's damage. That is a threat of 1.0, worth THREAT_REACH metres.
	for i in 6:
		GameManager.damage_boss(12, 2)
	_ok(boss.target_player() == b,
		"three metres further away but doing all the damage, hero 2 pulls him")
	print("  -- threat pull: hero 2 at 9 m outbids hero 1 at 6 m after 6 chained hits")


# --- Push-out ---------------------------------------------------------------

## The defect: `_body_box.knockback = 9.0` with `rehit_delay = 0.22` handed a hero
## standing under the giant a fresh 9 m/s impulse five times a second, and
## PlayerBase.apply_knockback ACCUMULATES into a reservoir that only gives back
## 3.1 m/s to decay in that time. The co-op stream measured a chased hero flung
## about 6.5 m, past the 3.7 / 4.0 m reach of both heroes' melee.
##
## Three separate claims are measured here, because the fix has to satisfy all
## three and it is easy to buy one with another:
##
##   1. being stood on costs no reach — the hero never ends up further out than
##      they can swing back from, and it does not creep over a long exposure;
##   2. it does not accumulate — the peak speed a hero reaches in the second half
##      of a long contact is no worse than in the first;
##   3. the giant still cannot walk THROUGH a hero, which is the failure mode a
##      weaker shove would trade for the other two.
func _check_push_out() -> void:
	await _to_menu()
	await _start(2, 1)
	await _settle(60)

	var boss := _boss()
	var a := _hero(1)
	var b := _hero(2)
	# Park the partner behind so the giant's attention (and the leash) leave the
	# measurement alone.
	b.global_position = boss.global_position + Vector3(-9.0, 1.0, 0.0)
	a.global_position = boss.global_position + Vector3(-5.0, 1.0, 0.0)
	await _settle(20)

	# Hold forward into him for six seconds, which in co-op framing means "walk at
	# the giant" (the co-op probe measures that camera forward points at him with
	# dot 1.00). Driving it through the input rather than by teleporting is the
	# whole point: it is the situation the defect was reported from, and a probe
	# that shoves the hero around itself measures the probe.
	var forward := InputManager.action_name(1, &"move_up")
	Input.action_press(forward)
	var outs: Array[float] = []
	var speeds: Array[float] = []
	var gaps: Array[float] = []
	var through := -99.0
	for w in 3:
		var win := await _shove_window(a, boss, int(2.0 * TICK))
		outs.append(float(win["out"]))
		speeds.append(float(win["speed"]))
		gaps.append(float(win["gap"]))
		through = maxf(through, float(win["inside"]))
		print("  -- 2 s pressed into him, window %d: %.0f%% of frames out of swing range, peak %.2f m/s, furthest %.2f m, %.2f m past his face"
			% [w + 1, 100.0 * win["out"], win["speed"], win["gap"], win["inside"]])
	Input.action_release(forward)

	# (1) Reach. Raw distance is the wrong metric here and it is worth saying why:
	# the giant RETREATS under his own power for 0.55 s of every cycle, so a peak
	# distance measures him as much as it measures the push. What the defect was
	# actually about is time spent unable to swing back, so that is what is
	# asserted — the hero holds forward the whole six seconds, and the number is
	# the fraction of frames his collider is out of their reach. The retreat alone
	# accounts for about a quarter of a cycle, and the hero out-walks it at 8 m/s
	# against his 5.1, so a third is generous and a shove that flung them to 6.5 m
	# would blow straight through it.
	var worst_out: float = outs.max()
	print("  -- worst window: %.0f%% of frames out of reach, furthest %.2f m (the old shove parked a hero at ~6.5 m)"
		% [100.0 * worst_out, gaps.max()])
	_ok(worst_out <= 0.34,
		"six seconds pressed into him leaves a hero able to swing back (%.0f%% of frames out of reach)"
			% (100.0 * worst_out))

	# (2) Accumulation. The shunt injects no velocity at all, so there is nothing
	# for it to accumulate INTO and the guarantee is structural; three windows are
	# here to catch it quietly going back to impulses.
	_ok(outs.max() - outs.min() <= 0.34,
		"...and shows no trend over three windows (%.0f%% / %.0f%% / %.0f%%)"
			% [100.0 * outs[0], 100.0 * outs[1], 100.0 * outs[2]])
	_ok(speeds.max() - speeds.min() <= 2.5,
		"nor does the speed a hero reaches (%.2f / %.2f / %.2f m/s)"
			% [speeds[0], speeds[1], speeds[2]])

	# (3) ...but he is still solid. A hero's capsule is 0.45 m, so pressed flat
	# against him their centre sits 0.45 m OUTSIDE his face and this reads
	# negative. Anything positive means the giant has begun to occupy the same
	# space as a hero, which is the failure a weaker shove would have bought the
	# other two with.
	_ok(through < 0.2,
		"the giant never walks through a hero (deepest %.2f m past his face)" % through)

	# Finally the number a player actually feels: getting back in is a beat.
	Input.action_press(forward)
	var frames := 0
	var back := false
	while frames < int(3.0 * TICK):
		await get_tree().physics_frame
		frames += 1
		if _gap(a, boss) <= float(a.attack_range) + SIDE_HALF:
			back = true
			break
	Input.action_release(forward)
	# Under the fix this is usually one frame, because the hero never actually
	# left swing range — which is the whole point, and is why the number is
	# printed rather than only asserted.
	print("  -- time to walk back into swing range: %.2f s" % (float(frames) / TICK))
	_ok(back and frames < int(1.5 * TICK),
		"a shoved hero is back in range in %.2f s" % (float(frames) / TICK))


## Peak horizontal speed, peak distance from the giant, and the deepest the hero
## ever got past his collider face, over `frames` of the hero holding forward
## into him. Contact has to be SUSTAINED for the defect to appear at all — the
## original was reported from a chase, not from one touch.
func _shove_window(hero: Node3D, boss: Node3D, frames: int) -> Dictionary:
	var speed := 0.0
	var gap := 0.0
	var inside := 0.0
	var out_of_reach := 0
	var reach: float = float((hero as PlayerBase).attack_range) + SIDE_HALF
	for i in frames:
		await get_tree().physics_frame
		var v: Vector3 = (hero as CharacterBody3D).velocity
		speed = maxf(speed, Vector2(v.x, v.z).length())
		var d := _gap(hero, boss)
		gap = maxf(gap, d)
		if d > reach:
			out_of_reach += 1
		var local: Vector3 = boss.global_transform.affine_inverse() * hero.global_position
		# His collider is 5 x 9 x 4, so its faces are 2.5 and 2.0 out. Anything
		# less than that on BOTH axes at once means the hero is inside him.
		inside = maxf(inside, minf(FRONT_HALF - absf(local.x), SIDE_HALF - absf(local.z)))
	return {
		"speed": speed,
		"gap": gap,
		"inside": inside,
		"out": float(out_of_reach) / float(maxi(1, frames)),
	}


func _gap(hero: Node3D, boss: Node3D) -> float:
	var d := hero.global_position - boss.global_position
	d.y = 0.0
	return d.length()


# --- Telegraph honesty ------------------------------------------------------

## The slam's mark is a pure timer — its disc reaches the ring exactly when the
## hitbox opens — so it is held to a couple of frames.
func _check_slam_telegraph() -> void:
	await _to_menu()
	await _start(2, 1)
	await _settle(60)
	_watch_boss()

	var boss := _boss()
	var a := _hero(1)
	var b := _hero(2)
	# Stand in his face and stay there so he slams rather than throws.
	for i in int(12.0 * TICK):
		a.global_position = boss.global_position + Vector3(-5.0, 1.0, -1.0)
		b.global_position = boss.global_position + Vector3(-5.0, 1.0, 1.0)
		_keep_alive()
		await get_tree().physics_frame

	var err := _telegraph_error(&"slam")
	print("  -- slam: %d marks, %d impacts, mean error %.3f s, worst %.3f s"
		% [_promised.get(&"slam", []).size(), _landed.get(&"slam", []).size(),
			err["mean"], err["worst"]])
	_ok(int(err["pairs"]) >= 3, "the giant slammed at least three times (%d)" % int(err["pairs"]))
	_ok(float(err["worst"]) <= SLAM_TOLERANCE,
		"the slam's disc lands on the impact frame (worst %.3f s, tolerance %.3f)"
			% [err["worst"], SLAM_TOLERANCE])


## The rock's mark has to predict a BALLISTIC arc the boss can only mirror from
## rock_projectile.gd, so this is the check that catches the fx stream retuning
## it. It also counts the volley, because one rock per standing hero is what
## makes flanking cost something.
func _check_rock_telegraph_and_volley() -> void:
	await _to_menu()
	await _start(2, 1)
	await _settle(60)
	_watch_boss()

	var boss := _boss()
	var a := _hero(1)
	var b := _hero(2)
	# Pinned beyond his 16 m rock range, so every decision is a throw.
	for i in int(16.0 * TICK):
		boss.global_position = Vector3(22.0, boss.global_position.y, 0.0)
		a.global_position = Vector3(-10.0, 2.2, -2.0)
		b.global_position = Vector3(-10.0, 2.2, 2.0)
		_keep_alive()
		await get_tree().physics_frame

	var volleys := _burst_sizes(&"rock")
	print("  -- rock volleys: %s (co-op, phase one)" % str(volleys))
	_ok(volleys.size() >= 2, "he threw at least two volleys (%d)" % volleys.size())
	var covered := true
	for n in volleys:
		if int(n) < 2:
			covered = false
	_ok(covered, "every co-op volley carries a rock per standing hero")

	var err := _telegraph_error(&"rock")
	print("  -- rock: %d marks, %d impacts, mean error %.3f s, worst %.3f s"
		% [_promised.get(&"rock", []).size(), _landed.get(&"rock", []).size(),
			err["mean"], err["worst"]])
	_ok(int(err["pairs"]) >= 2, "rocks actually landed (%d matched)" % int(err["pairs"]))
	_ok(float(err["mean"]) <= ROCK_TOLERANCE,
		"the crosshair closes on the rock landing (mean %.3f s, tolerance %.3f)"
			% [err["mean"], ROCK_TOLERANCE])


## Crossing 50% used to be a stat change. It is now an attack, so it has to be
## telegraphed like one — and it has to actually fire.
func _check_roar() -> void:
	await _to_menu()
	await _start(2, 1)
	await _settle(60)
	_watch_boss()

	var boss := _boss()
	var a := _hero(1)
	var b := _hero(2)
	a.global_position = boss.global_position + Vector3(-8.0, 1.0, -2.0)
	b.global_position = boss.global_position + Vector3(-8.0, 1.0, 2.0)
	await _settle(30)

	var before := int(GameManager.player_health[1])
	GameManager.damage_boss(int(GameManager.MAX_BOSS_HEALTH * 0.55), 1)
	_ok(GameManager.boss_phase == 2, "crossing half health flips the phase")

	for i in int(3.0 * TICK):
		_keep_alive()
		await get_tree().physics_frame

	var marks: Array = _promised.get(&"roar", [])
	var hits: Array = _landed.get(&"roar", [])
	_ok(marks.size() >= 1 and hits.size() >= 1,
		"the phase flip plays a telegraphed roar (%d marks, %d blasts)"
			% [marks.size(), hits.size()])
	var err := _telegraph_error(&"roar")
	print("  -- roar: promised lead %.2f s, error %.3f s"
		% [AdamastorStateMachine.ROAR_WINDUP, err["worst"]])
	_ok(float(err["worst"]) <= ROAR_TOLERANCE,
		"the roar's ring lands on its blast (%.3f s)" % err["worst"])
	_ok(int(GameManager.player_health[1]) < before or int(GameManager.player_health[2]) < 100,
		"the roar actually hits somebody standing in it")


# --- Damage share -----------------------------------------------------------

## Who the giant actually hurt over a simulated fight. Reported rather than
## asserted tightly: the split is an emergent property of threat targeting and
## the volley, and pinning it to a number would make every future tuning change
## look like a regression. The claim under test is only that neither hero is
## ignored — which is exactly what the roster-blind volley used to get wrong.
func _check_damage_share() -> void:
	await _to_menu()
	await _start(2, 1)
	await _settle(60)
	_damage_by_hero = {1: 0, 2: 0}
	GameManager.player_damaged.connect(_on_player_damaged)

	var boss := _boss()
	var a := _hero(1)
	var b := _hero(2)
	for i in int(25.0 * TICK):
		# Both flanking at the same distance, so nothing but the giant's own
		# choices decides the split.
		if i % 3 == 0:
			a.global_position = boss.global_position + Vector3(-6.0, 1.0, -3.0)
			b.global_position = boss.global_position + Vector3(-6.0, 1.0, 3.0)
		_keep_alive()
		await get_tree().physics_frame
	GameManager.player_damaged.disconnect(_on_player_damaged)

	var d1 := int(_damage_by_hero[1])
	var d2 := int(_damage_by_hero[2])
	var total := d1 + d2
	print("  -- 25 s flanking him: hero 1 took %d, hero 2 took %d (%.0f%% / %.0f%%), %.1f dps team"
		% [d1, d2, 100.0 * float(d1) / float(maxi(1, total)),
			100.0 * float(d2) / float(maxi(1, total)), float(total) / 25.0])
	_ok(total > 0, "he lands damage on a flanking pair at all (%d)" % total)
	_ok(d1 > 0 and d2 > 0, "neither flank is ignored (%d / %d)" % [d1, d2])


func _on_player_damaged(pid: int, amount: int, _health: int) -> void:
	if amount <= 0:
		return
	_damage_by_hero[pid] = int(_damage_by_hero.get(pid, 0)) + amount


# --- Telegraph bookkeeping --------------------------------------------------

func _watch_boss() -> void:
	_promised.clear()
	_landed.clear()
	var boss := _boss()
	boss.attack_telegraphed.connect(_on_telegraphed)
	boss.attack_impact.connect(_on_impact)


func _on_telegraphed(kind: StringName, lead: float) -> void:
	if not _promised.has(kind):
		_promised[kind] = []
	# Stored as the moment the mark PROMISES, so the comparison downstream is one
	# subtraction and cannot get the sign wrong.
	(_promised[kind] as Array).append(_clock + lead)


func _on_impact(kind: StringName) -> void:
	if not _landed.has(kind):
		_landed[kind] = []
	(_landed[kind] as Array).append(_clock)


## Pair promises to impacts in time order and report the error. Sorted index
## pairing rather than nearest-match: nearest-match flatters itself by silently
## re-using whichever promise happens to be closest.
func _telegraph_error(kind: StringName) -> Dictionary:
	var want: Array = (_promised.get(kind, []) as Array).duplicate()
	var got: Array = (_landed.get(kind, []) as Array).duplicate()
	want.sort()
	got.sort()
	var n: int = mini(want.size(), got.size())
	if n == 0:
		return {"pairs": 0, "mean": 0.0, "worst": 0.0}
	var sum := 0.0
	var worst := 0.0
	for i in n:
		var e: float = absf(float(got[i]) - float(want[i]))
		sum += e
		worst = maxf(worst, e)
	return {"pairs": n, "mean": sum / float(n), "worst": worst}


## Marks planted in the same frame are one volley.
func _burst_sizes(kind: StringName) -> Array[int]:
	var want: Array = (_promised.get(kind, []) as Array).duplicate()
	var out: Array[int] = []
	if want.is_empty():
		return out
	# Promised times differ by the flight time, so group on the ORDER they were
	# recorded instead: a volley is a run of marks logged before the clock moves.
	# _on_telegraphed appends in call order, so a burst is contiguous.
	var runs: Array[int] = []
	var count := 1
	for i in range(1, want.size()):
		# Within a volley the promised times sit inside one throw's flight spread;
		# between volleys they are at least a wind-up apart.
		if absf(float(want[i]) - float(want[i - 1])) < AdamastorStateMachine.ROCK_FLIGHT_MAX:
			count += 1
		else:
			runs.append(count)
			count = 1
	runs.append(count)
	out.assign(runs)
	return out


# --- Harness ---------------------------------------------------------------

## Keep both heroes on their feet. The measurements above run for tens of
## seconds under a giant who is genuinely trying to kill them, and a knockdown
## halfway through would change the roster the thing being measured depends on.
func _keep_alive() -> void:
	for pid in [1, 2]:
		if int(GameManager.player_health.get(pid, 0)) < 45:
			GameManager.player_health[pid] = GameManager.MAX_PLAYER_HEALTH


func _start(count: int, hero: int) -> void:
	if _main == null:
		_main = MainScene.instantiate()
		add_child(_main)
		await _settle(4)
	GameManager.set_player_count(count)
	GameManager.set_human_hero(hero)
	GameManager.start_game()
	await _settle(6)


func _to_menu() -> void:
	GameManager.go_to_menu()
	await _settle(4)


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


func _boss() -> Node3D:
	return get_tree().get_first_node_in_group("boss") as Node3D


func _hero(id: int) -> PlayerBase:
	for p in get_tree().get_nodes_in_group("players"):
		if p is PlayerBase and int(p.player_id) == id:
			return p as PlayerBase
	return null


func _ok(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("  ok   ", label)
	else:
		_fail += 1
		printerr("  FAIL ", label)
