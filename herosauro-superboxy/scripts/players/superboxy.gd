extends PlayerBase
## Super Boxy: the nimble brawler in a green hoodie, denim overalls, red mask,
## cape and boxing gloves — PLAYER TWO. His signature move is the Boxy Dash: a
## short, fast, gravity-defying lunge that bonks the boss for big combo damage,
## throwing a punch as he connects.
##
## The close-range, fast half of the pair against Herosauro's reach: a quicker,
## lighter jab, a shorter cooldown on the special, and a special that has to be
## in the giant's face to do anything — which is what makes the two heroes want
## to stand in different places.
##
## Visual is a Meshy-generated, RIGGED + ANIMATED glTF (walk / run / punch),
## driven by PlayerBase's AnimationTree.

const DASH_SPEED_MULT := 4.0
const DASH_DURATION := 0.25
const DASH_DAMAGE := 25
const DASH_HIT_RANGE := 5.0
const GHOST_INTERVAL := 0.06
## How hard the frame kicks when the dash connects. Well above the basic jab's
## 0.16 — this is the biggest single thing either hero does to the giant, and the
## impact contract says every hit gets a camera response in proportion.
const DASH_SHAKE := 0.55
const DASH_SHAKE_TIME := 0.26

const DashTrailScene: PackedScene = preload("res://scenes/fx/dash_trail.tscn")
const SuperBoxyModel: PackedScene = preload("res://assets/models/superboxy.glb")

const MODEL_YAW := PI / 2.0     # model faces +Z; body yaw 0 faces +X (PlayerBase._face_movement)
const MODEL_SCALE := 0.85       # rigged model ~2u -> ~1.7u
const MODEL_Y := -0.85          # drop feet to the bottom of the 1.7u collision capsule

var _dash_time: float = 0.0
var _dash_dir: Vector3 = Vector3.ZERO
var _hit_boss: bool = false
var _ghost_accum: float = 0.0


func _ready() -> void:
	super._ready()
	move_speed = 8.0
	jump_velocity = 13.0
	ability_cooldown = 1.5
	# Basic attack: a fast, light standing jab (shares the punch clip with the dash).
	attack_cooldown = 0.38
	attack_damage = 7
	# Shorter than Herosauro's by design, but still past the giant's push-out.
	attack_range = 3.7
	attack_hold = 0.28


func _build_visuals() -> void:
	var model := SuperBoxyModel.instantiate()
	model.name = "SuperBoxyMesh"
	model.rotation.y = MODEL_YAW
	model.scale = Vector3.ONE * MODEL_SCALE
	model.position.y = MODEL_Y
	_model_root.add_child(model)
	# The GLB ships albedo only — no normal/roughness/metallic. Same treatment
	# Herosauro gets, or Boxy reads as a flat decal next to a hero who does not.
	ToonFactory.upgrade_glb_materials(model)
	# "punch" substring-matches the model's punch clip — baked as "punch1" (the
	# "Punch Combo 1" animation). Both the basic attack and the dash play it.
	# No "idle" key: the art has none, so PlayerBase synthesizes one from "walk".
	bind_animations(model, {"walk": "walk", "run": "run", "ability": "punch", "attack": "punch"})


func _perform_ability() -> void:
	_dash_time = DASH_DURATION
	_dash_dir = facing_dir.normalized()
	_hit_boss = false
	_ghost_accum = 0.0
	AudioManager.play_dash()
	play_action_anim("ability", 0.5)   # throw a punch as he dashes in
	# The lunge itself: a hard horizontal squash, so the body flattens into the
	# direction of travel before the ghosts start. PlayerBase has already applied
	# the generic anticipation; this is the extra Boxy gets for launching himself.
	_kick_squash(-0.14)
	GameManager.request_shake(0.10, 0.14)


func _custom_locomotion(delta: float) -> bool:
	if _dash_time > 0.0:
		_dash_time -= delta
		velocity = _dash_dir * move_speed * DASH_SPEED_MULT
		velocity.y = 0.0

		_ghost_accum += delta
		if _ghost_accum >= GHOST_INTERVAL:
			_ghost_accum -= GHOST_INTERVAL
			_spawn_ghost()

		if not _hit_boss:
			var boss := get_tree().get_first_node_in_group("boss")
			if boss:
				var here := global_position
				var there: Vector3 = boss.global_position
				var dx := here.x - there.x
				var dz := here.z - there.z
				if sqrt(dx * dx + dz * dz) < DASH_HIT_RANGE:
					_land_dash(boss)

		if _dash_time <= 0.0:
			# Follow-through on the way out of the lunge: the body springs back
			# past neutral rather than simply stopping being squashed.
			_kick_squash(0.16)
		return true
	return false


## Where the dash connects, measured from Boxy's centre.
##
## `DASH_HIT_RANGE` is 5.0 and is a proximity test to the giant's ORIGIN, which
## is at his feet — it fires while Boxy is still well outside the giant's surface,
## so a burst at the full 5 m would hang in the air short of him and a burst at
## Boxy's own position would sit behind his gloves. 1.6 m puts it out in front of
## the fists at about the depth his own swing volume reaches, and +UP lifts it off
## the deck to where the two bodies actually meet.
const DASH_FX_REACH := 1.6
## Above the jab's 1.0 and above Herosauro's orb at 1.6: this is the biggest
## single thing either hero does to Adamastor and the burst has to say so.
const DASH_FX_POWER := 2.0

## The dash connecting is the pair's biggest single hit, so it carries all five
## parts of the impact contract: this is the FX at the point of contact, the
## audio, the hit-stop and the camera, and the UI picks it up from
## GameManager.boss_damaged. (The ghost trail is the LUNGE, not the connect — it
## is drawn every 0.06 s along the whole dash whether or not anything is hit, so
## before this pass the one frame that mattered drew nothing that the frame
## before it had not already drawn.)
func _land_dash(boss: Node) -> void:
	GameManager.damage_boss(DASH_DAMAGE, player_id)
	if boss.has_method("nudge"):
		boss.nudge(_dash_dir, 1.2)
	# `surface_of` resolves granite off the giant — he is in the "boss" group and
	# he is literally a stone giant — so the gloves throw stone chips.
	ImpactFX.spark(self, global_position + _dash_dir * DASH_FX_REACH + Vector3.UP,
		_dash_dir, ImpactFX.surface_of(boss), DASH_FX_POWER)
	AudioManager.play_super_boxy_hit()
	GameManager.hit_stop(0.06)
	GameManager.request_shake(DASH_SHAKE, DASH_SHAKE_TIME)
	_hit_boss = true


func _cancel_actions() -> void:
	_dash_time = 0.0
	_hit_boss = false
	_ghost_accum = 0.0


func _spawn_ghost() -> void:
	var ghost := DashTrailScene.instantiate()
	var root := get_tree().get_first_node_in_group("spawn_root")
	if root == null:
		root = get_tree().current_scene
	root.add_child(ghost)
	ghost.global_transform = global_transform
