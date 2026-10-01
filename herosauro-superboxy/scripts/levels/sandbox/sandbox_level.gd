extends LevelBase
## Sandbox: the reference level. A lit yard, a low wall around it and three
## practice dummies; hit each one once and the chapter is won.
##
## It exists to be copied. Everything a storybook level needs is here and
## nothing else is:
##
##   1. the LevelBase overrides (spawn_point, camera_focus, kill_y,
##      ground_surface, begin, hint_target);
##   2. its own WorldEnvironment and sun (a level owns its lighting);
##   3. geometry built ONCE and baked into one mesh (ARCHITECTURE rule 6), with
##      a handful of simple box colliders on WORLD, kept LOW so the camera's
##      spring arm is not slammed in by a tall wall;
##   4. targets that follow the "things heroes can hit" contract
##      (target_dummy.gd);
##   5. progress reported ONLY through GameManager: set_objective in begin(),
##      advance_objective per target, complete_chapter at the end.
##
## Load it with GameManager.set_chapter("sandbox"); main.gd finds it at
## res://scenes/levels/sandbox/sandbox_level.tscn by naming convention.

const TargetDummy := preload("res://scripts/levels/sandbox/target_dummy.gd")

const OBJECTIVE := {"pt": "Acerta nos 3 alvos!", "en": "Hit the 3 targets!"}
const HALF := 16.0           # the yard is 32 x 32 m, centred on the origin
const WALL_HEIGHT := 1.2     # low: tall WORLD geometry pulls the camera in
const WALL_THICK := 0.6
## Heroes start at -X facing +X, like on the bridge; the dummies wait ahead.
const SPAWNS := {1: Vector3(-9.0, 1.2, -1.5), 2: Vector3(-9.0, 1.2, 1.5)}
const DUMMY_SPOTS: Array[Vector3] = [
	Vector3(-1.0, 0.0, -4.0),
	Vector3(3.0, 0.0, 3.5),
	Vector3(8.0, 0.0, -1.0),
]

var _dummies: Array[Node3D] = []


func _ready() -> void:
	_build_environment()
	_build_yard()
	for i in DUMMY_SPOTS.size():
		var d: Node3D = TargetDummy.new()
		d.name = "Dummy%d" % (i + 1)
		add_child(d)
		d.position = DUMMY_SPOTS[i]
		d.struck.connect(_on_dummy_struck)
		_dummies.append(d)


# --- LevelBase ---------------------------------------------------------------

func spawn_point(player_id: int) -> Vector3:
	return to_global(SPAWNS.get(player_id, SPAWNS[1]))


## Beyond the far wall, so the co-op camera always looks down +X across the
## yard and never swings round as the heroes walk about.
func camera_focus() -> Vector3:
	return to_global(Vector3(40.0, 0.0, 0.0))


func kill_y() -> float:
	return global_position.y - 10.0


func ground_surface() -> int:
	return ToonFactory.Surface.GRANITE


## Every run, including PLAY AGAIN (which reuses this node): fresh dummies, a
## fresh objective.
func begin() -> void:
	for d in _dummies:
		d.reset()
	GameManager.set_objective(OBJECTIVE, _dummies.size())


func hint_target() -> Vector3:
	var best := Vector3.INF
	var best_d := INF
	var heroes := get_tree().get_nodes_in_group("players")
	var from: Vector3 = heroes[0].global_position if not heroes.is_empty() else global_position
	for d in _dummies:
		if d.is_done():
			continue
		var dist := from.distance_to(d.global_position)
		if dist < best_d:
			best_d = dist
			best = d.global_position + Vector3.UP * 2.4
	return best


# --- Objective ---------------------------------------------------------------

func _on_dummy_struck(_dummy: Node3D) -> void:
	GameManager.advance_objective(1)
	if GameManager.objective_done() >= GameManager.objective_total():
		GameManager.complete_chapter()


# --- Build (once) --------------------------------------------------------------

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.75, 0.95)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.7, 0.85)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.name = "Environment"
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	add_child(sun)


func _build_yard() -> void:
	# One baker per material, one commit each: the ground and the walls are two
	# draw calls however many boxes they are made of.
	var ground := MeshBaker.new()
	ground.add_box(Vector3(HALF * 2.0, 1.0, HALF * 2.0), Transform3D(Basis(), Vector3(0.0, -0.5, 0.0)))
	add_child(ground.commit(ToonFactory.cobblestone(), "Ground"))

	var walls := MeshBaker.new()
	var wall_boxes := _wall_boxes()
	for b in wall_boxes:
		walls.add_box(b[0], Transform3D(Basis(), b[1]))
	add_child(walls.commit(ToonFactory.stone(), "Walls"))

	# Colliders: plain boxes on WORLD.
	SceneryKit.solid(self, "GroundCollider", Vector3(HALF * 2.0, 1.0, HALF * 2.0),
		Vector3(0.0, -0.5, 0.0))
	for i in wall_boxes.size():
		SceneryKit.solid(self, "WallCollider%d" % i, wall_boxes[i][0], wall_boxes[i][1])


## [size, centre] for the four perimeter walls.
func _wall_boxes() -> Array:
	var y := WALL_HEIGHT * 0.5
	var long := HALF * 2.0 + WALL_THICK * 2.0
	return [
		[Vector3(long, WALL_HEIGHT, WALL_THICK), Vector3(0.0, y, -HALF - WALL_THICK * 0.5)],
		[Vector3(long, WALL_HEIGHT, WALL_THICK), Vector3(0.0, y, HALF + WALL_THICK * 0.5)],
		[Vector3(WALL_THICK, WALL_HEIGHT, HALF * 2.0), Vector3(-HALF - WALL_THICK * 0.5, y, 0.0)],
		[Vector3(WALL_THICK, WALL_HEIGHT, HALF * 2.0), Vector3(HALF + WALL_THICK * 0.5, y, 0.0)],
	]
