class_name MatchConfig
extends RefCounted
## Who is in this match, as data.
##
## main.gd used to hold one hardcoded spawn call. The number of heroes is now a
## list length, so solo, co-op and solo-plus-ally differ by which factory is
## called and by nothing else. Everything downstream of the spawn already keys
## off player_id — GameManager's health dict, its signals, Hitbox.source_player,
## the HUD's per-hero rows — so the list is genuinely the only thing that has to
## change to add a second hero.
##
## What it does NOT do is make two-hero PRESENTATION work. The camera frames one
## subject and the HUD draws one hero's bars; both need real design work for two,
## and both are additive — nothing about leaving them solo makes them harder
## later. See local_co_op() for the full list of prerequisites.

const HerosauroScene: PackedScene = preload("res://scenes/players/herosauro.tscn")
const SuperBoxyScene: PackedScene = preload("res://scenes/players/superboxy.tscn")

## Player ids are the keys GameManager already uses. Keep them 1-based and
## contiguous: its health dict is seeded {1, 2}.
const P1 := 1
const P2 := 2

## Far enough apart that two heroes do not spawn inside each other's capsules,
## and both still well clear of the boss at +16.
const P1_SPAWN := Vector3(-12.0, 4.0, 0.0)
const P2_SPAWN := Vector3(-12.0, 4.0, 3.0)


## One hero in the match.
class Slot:
	var scene: PackedScene
	var player_id: int
	var spawn: Vector3
	var input: InputSource

	func _init(p_scene: PackedScene, p_id: int, p_spawn: Vector3,
			p_input: InputSource) -> void:
		scene = p_scene
		player_id = p_id
		spawn = p_spawn
		input = p_input


## What ships. One hero, reading the unprefixed action set — which is exactly
## what the InputManager autoload read before heroes carried their own input,
## so a solo game behaves identically to before this seam existed.
static func solo() -> Array[Slot]:
	return [Slot.new(HerosauroScene, P1, P1_SPAWN, DeviceInput.new())]


## Two humans, one keyboard-and-pad each.
##
## NOT WIRED UP, and honest about why. The code path works — this returns two
## slots and main.gd spawns whatever it is given — but three things are missing
## before it is playable, none of them in this file:
##
##   1. project.godot needs a p2_ action set (p2_move_left ... p2_ability).
##      Without it DeviceInput("p2_") warns at construction and reports neutral,
##      so Super Boxy spawns and stands there.
##   2. CameraRig frames get_first_node_in_group("players"). Two heroes need a
##      framing rule — midpoint with a distance clamp, or split screen.
##   3. HUD draws one hero's health and ability dial. It already has the
##      SHOW_SECOND_HERO switch and UIStyle already carries Super Boxy's colour,
##      portrait and epithet, but the second row does not exist yet.
static func local_co_op() -> Array[Slot]:
	return [
		Slot.new(HerosauroScene, P1, P1_SPAWN, DeviceInput.new()),
		Slot.new(SuperBoxyScene, P2, P2_SPAWN, DeviceInput.new("p2_")),
	]


## One human, one hero driven by whatever writes into the returned AgentInput.
##
## NOT WIRED UP: nothing writes to that AgentInput yet, so Super Boxy would
## spawn and stand still. The behaviour that drives him is the actual work; the
## seam it plugs into is this. Items 2 and 3 from local_co_op() apply here too.
##
## The caller keeps the AgentInput and pokes it each frame:
##
##     var roster := MatchConfig.solo_with_ally()
##     var brain := roster[1].input as AgentInput
##     # ... each frame: brain.move = ...; brain.press_attack()
static func solo_with_ally() -> Array[Slot]:
	return [
		Slot.new(HerosauroScene, P1, P1_SPAWN, DeviceInput.new()),
		Slot.new(SuperBoxyScene, P2, P2_SPAWN, AgentInput.new()),
	]
