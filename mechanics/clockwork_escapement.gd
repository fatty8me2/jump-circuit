class_name ClockworkPallet
extends MovingPlatform
## Clockwork Heights: one pallet of an escapement. It does not glide like a ferry -
## it TICKS: it sits still for a beat, then snaps `rise` metres up (or down) in `snap`
## seconds, the way an escapement lets the train advance one tooth at a time.
## Neighbouring pallets tick in opposite parity, so a run of them works like a
## bucket brigade: on every beat one pallet arrives at the height the next one just
## dropped to. Pure function of Game.course_time (identical for every racer), and the
## RouteBot reads it through MovingPlatform.offset_at like any other mover.

## Seconds per tick.
@export var beat: float = 1.4
## Seconds the snap between low and high takes.
@export var snap: float = 0.34
## Height between the low and the high rest.
@export var rise: float = 2.2
## 0: high during even beats, 1: high during odd beats.
@export var parity: int = 0
## Shifts the whole rhythm, in beats.
@export var beat_offset: float = 0.0


func _ready() -> void:
	period = beat * 2.0
	super()


func beat_pos(time: float) -> float:
	return time / beat + beat_offset


## 1 while resting high, 0 while resting low (smooth through the snap).
func level_at(time: float) -> float:
	var b: float = beat_pos(time)
	var n: int = floori(b)
	var into: float = (b - float(n)) * beat
	var cur: float = 1.0 if posmod(n + parity, 2) == 0 else 0.0
	var k: float = clampf(into / snap, 0.0, 1.0)
	k = k * k * (3.0 - 2.0 * k)
	return lerpf(1.0 - cur, cur, k)


func is_high_at(time: float) -> bool:
	return posmod(floori(beat_pos(time)) + parity, 2) == 0


## Seconds since the current beat began.
func into_beat(time: float) -> float:
	var b: float = beat_pos(time)
	return (b - floorf(b)) * beat


func offset_at(time: float) -> Vector3:
	return Vector3(0, rise * level_at(time), 0)
