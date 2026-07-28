extends SceneTree
## Is the hero's contact-shadow decal actually configured while the fight is
## running?
##
## Two A/B renders of the same gameplay frame — one with the decal placed wrong,
## one with it placed right — came back pixel-identical around his feet, so
## either the node is not being driven or the renderer is not drawing it. Those
## want different fixes, and a screenshot cannot tell them apart.
##
## So boot main.tscn for real, start the fight, let him stand on the deck, and
## read the decal back. If visible/size/position are right here, the code side
## is done and anything still missing from the frame is the renderer.
##
## Run:
##   godot --headless --script res://scripts/players/_decal_probe.gd --path .

## Frames to wait after the hero appears, so gravity has put him on the deck and
## _physics_process has run the contact shadow at least once.
const SETTLE_STEPS := 30
## Give up rather than spin forever if he never spawns.
const MAX_STEPS := 600

var _steps: int = 0
var _found_at: int = -1
var _started: bool = false


func _initialize() -> void:
	process_frame.connect(_tick)


func _tick() -> void:
	_steps += 1
	# --script does not boot the project's main scene; load it here, exactly as
	# _flow_probe.gd does. Without this the probe waits forever for a MainMenu
	# that was never going to exist.
	if _steps == 2:
		change_scene_to_file("res://scenes/main.tscn")
		return
	if _steps < 3:
		return
	# Start the fight the way _flow_probe.gd does — through the menu's own
	# handler. Calling GameManager.start_game() directly sets the state but
	# leaves the menu owning the viewport, and the hero is never spawned: this
	# probe sat through 600 frames looking for a node that was never coming.
	if not _started:
		var menu := root.find_child("MainMenu", true, false)
		if menu == null or not menu.has_method("_on_activated"):
			if _steps > MAX_STEPS:
				print("[decal] MainMenu never appeared")
				quit()
			return   # the menu builds its own copy of the arena; wait for it
		menu.call("_on_activated", &"start")
		_started = true
		print("[decal] fight started via the menu at frame %d" % _steps)
		return
	if not _started:
		return

	# The hero is spawned by the arena's own build, which takes a while — poll
	# for him rather than assuming a fixed frame, then give physics time to put
	# him down before reading anything back.
	var hero := _find_player(root)
	if hero == null:
		if _steps > MAX_STEPS:
			print("[decal] no node in group 'players' after %d frames" % _steps)
			quit()
		return
	if _found_at < 0:
		_found_at = _steps
		print("[decal] hero appeared at frame %d" % _steps)
		return
	if _steps - _found_at < SETTLE_STEPS:
		return

	print("[decal] hero=%s pos=%s on_floor=%s" % [
			hero.name, hero.global_position, hero.is_on_floor()])
	var d := hero.get_node_or_null("ContactShadow") as VisualInstance3D
	if d == null:
		print("[decal] ContactShadow NOT CREATED")
		quit()
		return

	print("[decal] node=%s visible=%s top_level=%s" % [d.get_class(), d.visible,
			(d as Node3D).top_level])
	var aabb := d.get_aabb()
	print("[decal] world pos=%s  aabb size=%s" % [d.global_position, aabb.size])
	var mi := d as MeshInstance3D
	if mi != null and mi.mesh != null:
		var mat := mi.mesh.surface_get_material(0) as StandardMaterial3D
		if mat != null:
			print("[decal] albedo=%s transparency=%d blend=%d unshaded=%s" % [
					mat.albedo_color, mat.transparency, mat.blend_mode,
					mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED])

	var space := root.world_3d.direct_space_state
	var from: Vector3 = hero.global_position + Vector3(0.0, -0.95, 0.0)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0.0, -4.0, 0.0),
			PhysicsLayers.WORLD)
	q.exclude = [hero.get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		print("[decal] ray from %s found NO ground on layer WORLD" % from)
	else:
		print("[decal] ground at y=%.3f  collider=%s" % [
				(hit["position"] as Vector3).y, hit["collider"]])
	quit()


func _find_player(node: Node) -> CharacterBody3D:
	if node.is_in_group("players"):
		return node as CharacterBody3D
	for c in node.get_children():
		var found := _find_player(c)
		if found != null:
			return found
	return null
