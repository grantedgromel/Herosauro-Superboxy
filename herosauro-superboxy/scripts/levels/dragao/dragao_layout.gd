extends RefCounted
## Where everything in the Estádio do Dragão chapter stands. Level-local space:
## the origin is the centre spot, +Y up, the pitch's long axis is X (goals at
## +-X), the main stand with the players' tunnel and the trophy cabinet is on
## the -Z side. Shared by the builder, the level and the characters so a number
## lives in one place.

## Playable pitch, white lines to white lines (56 x 36 m).
const PITCH_HALF := Vector2(28.0, 18.0)
## Inner face of the advertising boards: the edge of the world for everyone.
const BOARD_X := 31.0
const BOARD_Z := 21.0
const BOARD_H := 0.95
const BOARD_T := 0.28
## How far inside the boards a goblin's centre may go.
const ROAM_X := 30.1
const ROAM_Z := 20.1

## Stands: a walkway behind the boards, a front wall, then the tiers.
const STAND_GAP := 2.0
const FRONT_WALL_H := 1.3
const TIERS := 15
const TIER_D := 0.85
const TIER_H := 0.42
const ROOF_Y := 13.0

## The players' tunnel, centre of the main (-Z) stand.
const TUNNEL_X := 0.0
const TUNNEL_HALF_W := 1.8
## The heroes start in front of the tunnel, looking at the dragon.
const SPAWN_1 := Vector3(-1.8, 1.2, -13.0)
const SPAWN_2 := Vector3(1.8, 1.2, -13.0)

## Trophy cabinet: in the main stand's front, beside the tunnel, behind a gap
## in the boards so the whole pitch can see it light up.
const CABINET_POS := Vector3(-7.5, 0.0, -22.75)
const CABINET_W := 4.8
const CABINET_H := 3.3
const CABINET_D := 1.0

## The goblins' van, parked across the (+X, -Z) corner by the corner gate,
## nose pointing out of the gate.
const VAN_POS := Vector3(27.6, 0.0, -17.6)
const VAN_YAW := 2.356
const VAN_LEN := 5.2
const VAN_WID := 2.3
const VAN_HGT := 2.7

## The tied dragon lies in the centre circle; the stakes ring him.
const DRAGON_POS := Vector3(0.0, 0.0, 0.0)
const STAKES: Array[Vector3] = [
	Vector3(-4.6, 0.0, -3.2),
	Vector3(4.6, 0.0, -3.2),
	Vector3(4.6, 0.0, 3.4),
	Vector3(-4.6, 0.0, 3.4),
]
## Footballs start in a loose ring round the centre circle.
const BALLS: Array[Vector3] = [
	Vector3(-9.5, 0.4, -6.5),
	Vector3(9.0, 0.4, -7.5),
	Vector3(12.5, 0.4, 3.0),
	Vector3(-12.0, 0.4, 4.5),
	Vector3(-3.0, 0.4, 10.5),
	Vector3(4.5, 0.4, -11.5),
]

## Floodlight towers stand outside the corners.
const TOWERS: Array[Vector3] = [
	Vector3(-47.0, 0.0, -35.0),
	Vector3(47.0, 0.0, -35.0),
	Vector3(47.0, 0.0, 35.0),
	Vector3(-47.0, 0.0, 35.0),
]
const TOWER_H := 32.0


static func stand_front_z() -> float:
	return BOARD_Z + BOARD_T + STAND_GAP


static func stand_front_x() -> float:
	return BOARD_X + BOARD_T + STAND_GAP


## Keep a point inside the boards (flat).
static func clamp_to_pitch(p: Vector3, margin: float = 0.0) -> Vector3:
	return Vector3(clampf(p.x, -ROAM_X + margin, ROAM_X - margin), p.y,
		clampf(p.z, -ROAM_Z + margin, ROAM_Z - margin))
