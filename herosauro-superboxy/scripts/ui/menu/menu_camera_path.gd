extends RefCounted
## The title screen's camera move, as pure maths.
##
## Split out from menu_world.gd on purpose: a camera path that must never clip
## geometry and never show the edge of the world is a claim you can only make if
## you can actually measure it, and you cannot measure a path that only exists
## inside a _process() call. `sample()` is a total function of one number, so
## `_menu_probe.gd` can walk the whole loop headlessly and prove the clearances.
##
## SHAPE OF THE MOVE. The camera orbits a pivot out in the Douro, downstream of
## the bridge, on the Gaia side of the channel. Azimuth, radius, height, look
## target and focal length are each the sum of a first and a second harmonic of
## the loop, which buys three things at once:
##
##   * it loops with no seam at all. Every term is periodic in `u`, so position,
##     velocity and acceleration all match across u = 1 -> 0. There is no keyframe
##     to ease into and no cut to hide.
##   * the return leg is not the outbound leg run backwards. A single sine is a
##     pendulum and reads as one; adding a second harmonic at an unrelated phase
##     turns the ground track into a slow figure-of-eight, so the shot keeps
##     finding new angles for the whole 74 seconds.
##   * it cannot drift. Nothing here integrates, so no accumulated error can walk
##     the camera into the parapet after twenty minutes on the menu.
##
## WHERE THE SHOT IS AIMED. The world runs the gorge along Z and crosses it with
## the bridge along X; the sun sits low over the -x/-z quadrant, behind the
## Ribeira. So the whole path stays downstream (z well past the deck's +7.5 face)
## and looks back up the channel into the sun: the bridge crosses the frame, the
## arch and its lattice hang under it, the terraced Ribeira and the Clerigos
## tower are on the left in silhouette, Serra do Pilar is on the right, and the
## photogrammetry city closes the far end.
##
## u = 0 is deliberately the low, close, arch-heavy end of the loop — the camera
## skimming the water under the truss — and the first ~20 seconds are the rise
## and pull-back that opens the city out behind it.

# --- Loop --------------------------------------------------------------------

## Seconds for one lap. Long enough that nobody sitting on the menu sees it
## repeat, short enough that the reveal happens while they read the title.
const PERIOD := 74.0

## Orbit centre, in the channel downstream of the bridge centre. Y is unused —
## the shot's vertical aim comes from PITCH_* below, not from this point, so the
## horizon line stays where it was composed instead of sliding with the camera.
const PIVOT := Vector3(-4.0, 0.0, -10.0)

# --- Harmonics ---------------------------------------------------------------
# Each triple is (mean, first-harmonic amplitude, second-harmonic amplitude) and
# each pair of phases is (first, second), in radians. The phases are chosen so
# that u = 0 lands on the opening frame described above.

## Azimuth off +Z, positive towards Gaia (+x). Capped at ~0.53 rad of swing for a
## reason: yaw plus half the horizontal field of view has to stay under 90
## degrees off -Z or the frame starts to include the open water downstream, which
## is the one direction this world does not model. At 21:9 — the widest the
## project's `expand` stretch can produce — this tops out near 81 degrees.
const AZIMUTH := Vector3(0.10, 0.44, 0.09)
const AZIMUTH_PHASE := Vector2(0.75, -0.30)

## Distance from the pivot. Bottoms out around 31 units, which keeps ~13 units
## between the camera and the bridge's own bounding box at the closest approach.
const RADIUS := Vector3(40.0, 7.0, 2.5)
const RADIUS_PHASE := Vector2(-1.20, 0.30)

## Height above the deck datum. The floor (~ -5.5) is still 9 units clear of the
## water shader's highest crest at -14.65, so the near plane can never dip under
## the river; the ceiling (~ +11) looks down over the parapet without ever
## putting the deck's far edge against bare sky.
const HEIGHT := Vector3(3.5, 7.5, 2.0)
const HEIGHT_PHASE := Vector2(-1.5708, -0.60)

## Where the pan is aimed, as a wander around PIVOT in XZ. Small: this exists so
## the pan is not rigidly locked to one point for 74 seconds, not to reframe.
const TARGET_DRIFT := Vector2(5.0, 4.0)
const TARGET_PHASE := Vector2(2.10, 0.20)

## Vertical aim, in degrees, negative looking down. Mostly a linear function of
## height — rise and you tilt down, which is what a crane move does — plus a
## small independent wobble so the tilt is not a slave to the boom.
const PITCH_BIAS := -1.0
const PITCH_PER_HEIGHT := -0.60
const PITCH_WOBBLE := 1.6
const PITCH_WOBBLE_PHASE := 2.2

## Vertical field of view. Breathing it against the radius gives the move a hint
## of dolly-zoom without ever being obvious about it.
const FOV := Vector2(38.0, 5.0)
const FOV_PHASE := 0.50

## Where the depth-of-field plane sits, as a multiple of the distance to the
## subject. Just past 1 so the bridge stays crisp and the city behind it goes
## soft, which is what lets a gold logo sit over a bright sky and still read.
const FOCUS_SCALE := 1.22


## One frame of the move. `u` is the loop phase in [0, 1); values outside are
## wrapped, so callers can hand over raw elapsed time / PERIOD.
##
## Returns a dictionary rather than four out-parameters because it is sampled
## once per frame and read by two very different callers (the live camera and
## the probe), and naming the fields is worth more here than the allocation.
static func sample(u: float) -> Dictionary:
	var a := TAU * fposmod(u, 1.0)
	var azimuth := AZIMUTH.x + AZIMUTH.y * sin(a + AZIMUTH_PHASE.x) \
			+ AZIMUTH.z * sin(2.0 * a + AZIMUTH_PHASE.y)
	var radius := RADIUS.x + RADIUS.y * sin(a + RADIUS_PHASE.x) \
			+ RADIUS.z * sin(2.0 * a + RADIUS_PHASE.y)
	var height := HEIGHT.x + HEIGHT.y * sin(a + HEIGHT_PHASE.x) \
			+ HEIGHT.z * sin(2.0 * a + HEIGHT_PHASE.y)

	var position := Vector3(
		PIVOT.x + sin(azimuth) * radius,
		height,
		PIVOT.z + cos(azimuth) * radius)

	var aim_x := PIVOT.x + TARGET_DRIFT.x * sin(a + TARGET_PHASE.x)
	var aim_z := PIVOT.z + TARGET_DRIFT.y * sin(2.0 * a + TARGET_PHASE.y)
	var reach := Vector2(aim_x - position.x, aim_z - position.z).length()

	# The target's height is derived from the pitch we want rather than authored,
	# which is the whole trick that keeps the horizon nailed to the same third of
	# the frame however high the boom goes.
	var pitch := PITCH_BIAS + PITCH_PER_HEIGHT * height \
			+ PITCH_WOBBLE * sin(2.0 * a + PITCH_WOBBLE_PHASE)
	var target := Vector3(aim_x, position.y + tan(deg_to_rad(pitch)) * reach, aim_z)

	return {
		"position": position,
		"target": target,
		"fov": FOV.x + FOV.y * sin(a + FOV_PHASE),
		"focus": position.distance_to(target) * FOCUS_SCALE,
	}
