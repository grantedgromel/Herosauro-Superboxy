extends Node
## Does the hero cast a shadow, or is his shadow simply landing on the near-black
## tramway strip where nothing could read it?
##
## Captured frames show him with no shadow at all. But the sun sits at 11.5
## degrees and runs almost along the bridge's own axis, so his shadow is a long,
## foreshortened streak on whatever is directly beside him — which is the
## darkest material on the deck. Staring at the frame cannot separate "casts
## nothing" from "casts onto black".
##
## So: render the same fixed frame twice from one process, once with the hero
## visible and once with him hidden, and subtract. Everything that differs is
## him: his body, and his shadow if he has one. If the difference is his
## silhouette and nothing else, he is not casting.
##
##   godot --path . tools/shadowshot.tscn --rendering-driver vulkan -- --out=/abs/dir

const ArenaScene: PackedScene = preload("res://scenes/world/bridge_arena.tscn")
const HeroScene: PackedScene = preload("res://scenes/players/herosauro.tscn")

## Where to look for the deck from. PlayerBase._physics_process returns early
## unless GameManager is PLAYING, so a dropped hero does not fall — the second
## attempt left him hovering at y = 6, where his shadow lands about 25 m away
## and very possibly off frame. So the deck is found by raycast and he is placed
## standing on it, which is also the situation the captured frames show.
const PROBE_FROM := Vector3(0.0, 20.0, 0.0)
const PROBE_TO := Vector3(0.0, -10.0, 0.0)
const HERO_HALF_HEIGHT := 1.0   ## origin is the capsule centre; feet are this far below

## The sun's horizontal travel, from SunLight's basis in bridge_arena.tscn:
## light direction (0.860, -0.200, 0.470), normalised in XZ. A shadow runs from
## the caster's feet along this, for height / tan(11.5 deg) = height * 4.91.
const SUN_XZ := Vector2(0.878, 0.479)

## High enough, and offset back along -sun, that the hero AND the whole length
## of the shadow he should be throwing are both in frame. Looking down the sun's
## own axis — which is roughly what the gameplay camera does — foreshortens that
## shadow to nothing, and that is the ambiguity this probe exists to remove.
const CAM_OFFSET := Vector3(-4.0, 14.0, 9.0)
const AIM_ALONG_SUN := 5.0      ## look this far down the expected shadow

const SETTLE := 26   ## frames for the arena build + the renderer's temporal passes
const GAP := 8       ## frames between the two exposures

var _out: String = "/tmp/shadowshot"
var _hero: Node3D
var _cam: Camera3D
var _frame: int = 0
var _stage: int = 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)

	add_child(ArenaScene.instantiate())

	_hero = HeroScene.instantiate()
	add_child(_hero)
	_hero.global_position = PROBE_FROM   # real height set in _aim, once the deck exists

	# Our own camera, marked current after the arena's so it wins. Aimed in
	# _aim(), once the hero has actually landed.
	_cam = Camera3D.new()
	_cam.name = "ProbeCamera"
	add_child(_cam)
	_cam.fov = 50.0
	_cam.current = true

	print("shadowshot: adapter=", RenderingServer.get_video_adapter_name())


## Stand the hero on the deck, then frame him together with the ground his
## shadow has to fall on.
func _aim() -> void:
	var space := get_viewport().world_3d.direct_space_state
	var query := PhysicsRayQueryParameters3D.create(PROBE_FROM, PROBE_TO)
	query.exclude = [_hero.get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return   # arena still building; try again next frame

	var deck: Vector3 = hit["position"]
	_hero.global_position = deck + Vector3(0.0, HERO_HALF_HEIGHT, 0.0)

	# The hero is placed here rather than simulated — PlayerBase._physics_process
	# returns early outside State.PLAYING — so anything it would normally drive
	# per frame has to be driven by hand. Without this the contact-shadow decal
	# keeps the position it was given in _ready(), 20 m up with no ground under
	# it, and the probe reports "no contact shadow" whatever the code does.
	if _hero.has_method("_update_contact_shadow"):
		_hero.call("_update_contact_shadow")

	var aim := deck + Vector3(SUN_XZ.x, 0.0, SUN_XZ.y) * AIM_ALONG_SUN
	_cam.global_position = deck + CAM_OFFSET
	_cam.look_at(aim, Vector3.UP)
	_cam.current = true
	if _frame % 10 == 1:
		print("shadowshot: deck at ", deck, "  hero ", _hero.global_position,
				"  camera ", _cam.global_position)


func _process(_d: float) -> void:
	_frame += 1
	# Re-aim every frame until the exposure: the hero is still falling, and the
	# arena's own camera may become current partway through its build.
	if _stage == 0:
		_aim()
	match _stage:
		0:
			if _frame >= SETTLE:
				_save("a_hero_visible")
				_hero.visible = false
				_frame = 0
				_stage = 1
		1:
			if _frame >= GAP:
				_save("b_hero_hidden")
				print("shadowshot: DONE")
				get_tree().quit()


func _save(label: String) -> void:
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, label])
	print("shot: ", label)
