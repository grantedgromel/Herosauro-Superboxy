class_name BridgeArchCurve
extends RefCounted
## The parametric skeleton of the Dom Luís I crescent arch. Pure maths, no meshes.
##
## Seyrig's 1886 arch is a TWO-HINGED CRESCENT: two chords that meet at a pin at
## each springing and open out to their greatest separation at the crown. That
## lens taper is the bridge's signature and the single thing a plain parabolic
## beam cannot fake, so it is expressed here once and every builder — chords, web,
## spandrel columns, lower-deck hangers, hinge shoes — samples the same functions.
## Nothing may hard-code an arch coordinate anywhere else.
##
## Both chords are parabolas through the same springing points with different
## rises, which gives depth(t) = (RISE_UPPER - RISE_LOWER) * (1 - t^2): maximal at
## the crown, exactly zero at the pins. That is the crescent, in one line.
##
## The ribs also SPLAY: the pair sits RIB_Z apart at the crown and opens to
## RIB_Z + RIB_SPLAY at the springings, as the real arch does for lateral
## stability. In elevation it is invisible; from the deck looking down, and from
## the Gaia bank, it is what stops the arch reading as two flat cut-outs.
##
## Vertical scale note. The scene is compressed ~3.5x vertically against the real
## river (17 m of deck-to-water here against 60 m there), so a truthful 0.26
## rise/span was not available: the crown is pinned under the deck framing and the
## river surface is at y = -15. The springings are therefore dropped to -17.6,
## a couple of metres under the (opaque) water, which buys back rise/span ~ 0.16
## and hides the pins in the river exactly where a granite tower would anyway.

# --- Span ---------------------------------------------------------------------

## x in [-47, 47]. The deck runs to +-50, so the arch reaches almost bank to bank,
## which is how the real single 172 m span reads: one leap, no river piers.
const HALF_SPAN := 47.0

## Springing pins. Below the river plane (y = -15) on purpose — see the header.
const SPRING_Y := -17.6

## Upper-chord centreline at the crown. The deck framing bottoms out at -1.85, so
## the chord's top face lands ~0.2 m under it and a bearing saddle closes the gap:
## the deck sits ON the arch, which is what "upper deck" means here.
const CROWN_Y := -2.45

## Chord separation at the crown, tapering to 0 at the pins. 6.6 m on a 94 m span
## is depth/span = 1/14, in the band Seyrig and Eiffel actually built to.
const CROWN_DEPTH := 6.60

# --- Rib plan -----------------------------------------------------------------

## Half-spacing of the two ribs at the crown. Matches the kerb line the deck's
## main girders sit over, so load runs straight down.
const RIB_Z := 5.0
## Extra half-spacing at the springings. Quadratic in t, so the ribs stay parallel
## through the middle third and open out only where the thrust needs the base.
const RIB_SPLAY := 2.60
## Width of each rib as a box girder: two chord planes this far apart in Z.
const RIB_WIDTH := 1.50

# --- Chord ids ----------------------------------------------------------------

const UPPER := 0
const LOWER := 1

## Derived rises, so the two chords can never drift apart in an edit.
const RISE_UPPER := CROWN_Y - SPRING_Y                  # 15.15
const RISE_LOWER := CROWN_Y - CROWN_DEPTH - SPRING_Y    # 8.55


# --- Sampling -----------------------------------------------------------------

## Height of a chord at parameter t in [-1, 1]. t = 0 is the crown.
static func chord_y(t: float, chord: int) -> float:
	var rise := RISE_LOWER if chord == LOWER else RISE_UPPER
	return SPRING_Y + rise * (1.0 - t * t)


## Vertical separation of the chords at t. Zero at the pins by construction.
static func depth(t: float) -> float:
	return (RISE_UPPER - RISE_LOWER) * (1.0 - t * t)


## Half-spacing of the rib centrelines at t.
static func rib_z(t: float) -> float:
	return RIB_Z + RIB_SPLAY * t * t


## A point on one chord of one rib.
##   side  -1 / +1, which rib
##   plane -1 = inboard chord plane, +1 = outboard, 0 = rib centreline
static func point(t: float, chord: int, side: float, plane: float = 0.0) -> Vector3:
	return Vector3(
		t * HALF_SPAN,
		chord_y(t, chord),
		side * (rib_z(t) + plane * RIB_WIDTH * 0.5))


## A chord sampled into a polyline of `bays` segments over t in [t0, t1].
##
## Sampled in t rather than in x deliberately: the parabola's curvature is
## constant in t, so equal steps give equal-looking bays right out to the pins,
## where an x-uniform sampling would visibly straighten.
static func polyline(chord: int, side: float, plane: float, bays: int,
		t0: float = -1.0, t1: float = 1.0) -> PackedVector3Array:
	var out := PackedVector3Array()
	var steps := maxi(bays, 1)
	out.resize(steps + 1)
	for i in steps + 1:
		var t := lerpf(t0, t1, float(i) / float(steps))
		out[i] = point(t, chord, side, plane)
	return out


## t of a given x. The inverse is trivial but spelling it out keeps call sites
## from sprinkling `/ HALF_SPAN` around.
static func t_at_x(x: float) -> float:
	return clampf(x / HALF_SPAN, -1.0, 1.0)


## The t at which a chord crosses a given height, on the +t half of the arch.
## Returns 1.0 when the chord never gets that low. Used to work out where the
## suspended road deck passes between the ribs instead of over or under them.
static func t_at_height(y: float, chord: int) -> float:
	var rise := RISE_LOWER if chord == LOWER else RISE_UPPER
	if rise <= 0.0:
		return 1.0
	var s := (y - SPRING_Y) / rise      # = 1 - t^2
	if s >= 1.0:
		return 0.0                       # above the crown: crossed everywhere
	if s <= 0.0:
		return 1.0                       # below the pins: never crossed
	return sqrt(1.0 - s)
