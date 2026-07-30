extends MeshInstance3D
## A parted wire end swinging on its own hang point.
##
## The mesh is built hanging from the local origin (BridgeDeckKit.torn_tail), so
## rotating this node IS the pendulum — no skinning, no bone, no per-vertex work.
## One of these is one draw call, which is the entire reason there are two of them
## and not twenty.
##
## OFF ACCUMULATED DELTA, NEVER THE WALL CLOCK. `Time.get_ticks_msec()` is banned
## in _process by ARCHITECTURE.md rule 5, enforced by a CI grep and by the
## per-pixel capture gate, and it has been regressed once already. The gate runs a
## fresh process per shot and pumps a fixed number of frames under --fixed-fps; a
## node that integrates delta is therefore at an identical phase in every capture
## on every machine, and a node that reads the clock is at a different one every
## single time.

## Radians of swing. A dead cable in still air barely moves: on a 2.9 m tail this
## is about 28 cm of travel at the tip, which reads as alive from the deck and
## does not read as being blown around.
@export var amplitude: float = 0.095
## Two periods, deliberately not a small-integer ratio, so the swing traces a slow
## open figure instead of a flat arc and never repeats inside a shot.
@export var period_x: float = 4.3
@export var period_z: float = 6.1
## Set per instance so the bridge's two tails are never caught at the same angle.
@export var phase: float = 0.0

var _elapsed: float = 0.0


func _process(delta: float) -> void:
	_elapsed += delta
	rotation = Vector3(
		amplitude * sin(TAU * _elapsed / period_x + phase),
		0.0,
		# Across the deck the cable is stiffer — it is hanging against the parapet
		# on that side — so the second axis swings shorter than the first.
		amplitude * 0.7 * sin(TAU * _elapsed / period_z + phase * 1.7))
