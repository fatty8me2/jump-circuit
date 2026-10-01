class_name FrontierScroll
extends Node3D
## Wild West Heist's moving world. The train never moves: every car is plain static ground, so the
## run along it is as solid as any other level. Instead the world slides past it. A FrontierScroll
## holds a field of scenery that repeats every `period` metres along Z (sleepers, trestle bents,
## telegraph poles, hoodoos...) and shifts it back along +Z at the train's speed, wrapping by exactly
## one repeat, so the field never jumps. Driven by Game.course_time, so it stops with the clock
## (pause, results) and is identical for every racer. Visual only.

## The train's speed through the canyon (m/s): everything trackside moves back along +Z this fast.
const SPEED: float = 10.0

## Metres after which the field repeats itself.
var period: float = 10.0
## Speed multiplier (1 = scenery at the trackside; distant layers can use less for parallax).
var rate: float = 1.0
var _base: Vector3 = Vector3.ZERO


static func make(period_m: float, rate_mult: float = 1.0) -> FrontierScroll:
	var s := FrontierScroll.new()
	s.period = period_m
	s.rate = rate_mult
	return s


## How far (0..period) a field repeating every `period_m` has slid at `time`.
static func shift(time: float, period_m: float, rate_mult: float = 1.0) -> float:
	return fposmod(time * SPEED * rate_mult, period_m)


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_base = position
	_process(0.0)


func _process(_dt: float) -> void:
	position = _base + Vector3(0, 0, shift(Game.course_time, period, rate))
