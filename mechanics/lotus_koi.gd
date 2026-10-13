class_name LotusKoi
extends Node3D
## Lotus Drift: a shoal of KOI in the pond. Three to six fat fish in red, white, gold and black
## drift in slow loops under the surface (a rounded-square path round `center`), tails sweeping,
## now and then one leaps out of the water in a bright arc and splashes back. Purely scenery - a
## living pond to look at while the course runs past. `extent` is the half-size of the loop on X and
## Z; Node origin = the water surface at the loop's centre.

@export var count: int = 4
@export var extent: Vector2 = Vector2(8.0, 5.0)
@export var depth: float = 0.5
@export var speed: float = 1.1
@export var leap_every: float = 9.0

class Fish:
	var node: Node3D
	var tail: Node3D
	var phase: float
	var rate: float
	var lane: float
	var leap_t: float = -1.0
	var next_leap: float


var _fish: Array[Fish] = []
var _t: float = 0.0
var _rng := RandomNumberGenerator.new()
var _splash: GPUParticles3D


func _ready() -> void:
	_rng.seed = int(position.x * 7.0) * 31 + int(position.z * 13.0) + 5
	var cols: Array[Color] = [Color(0.95, 0.32, 0.12), Color(0.96, 0.94, 0.9), Color(1.0, 0.7, 0.2), Color(0.18, 0.16, 0.2), Color(0.95, 0.5, 0.35), Color(0.98, 0.9, 0.8)]
	for i: int in count:
		var f := Fish.new()
		f.phase = _rng.randf() * TAU
		f.rate = speed * _rng.randf_range(0.8, 1.15) / maxf((extent.x + extent.y) * 0.5, 1.0)
		f.lane = _rng.randf_range(0.65, 1.0)
		f.next_leap = _rng.randf_range(2.0, leap_every)
		var n := Node3D.new()
		var col: Color = cols[i % cols.size()]
		var body := Look.sphere(0.5, Look.flat(col, 0.5, 0.0, 0.12))
		body.scale = Vector3(0.38, 0.28, 1.0)
		n.add_child(body)
		var patch := Look.sphere(0.5, Look.flat(cols[(i + 3) % cols.size()], 0.5, 0.0, 0.1), Vector3(0, 0.1, -0.1))
		patch.scale = Vector3(0.3, 0.18, 0.42)
		n.add_child(patch)
		var tail := Node3D.new()
		tail.position = Vector3(0, 0, 0.45)
		var fin := Look.box(Vector3(0.02, 0.28, 0.4), Look.flat(col.lightened(0.15), 0.6, 0.0, 0.1), Vector3(0, 0, 0.18))
		fin.rotation.x = 0.0
		tail.add_child(fin)
		n.add_child(tail)
		for sx: float in [-1.0, 1.0]:
			var pf := Look.box(Vector3(0.18, 0.015, 0.14), Look.flat(col.lightened(0.2), 0.6), Vector3(sx * 0.2, -0.04, -0.12))
			pf.rotation.y = sx * 0.5
			n.add_child(pf)
		n.scale = Vector3.ONE * _rng.randf_range(0.8, 1.3)
		add_child(n)
		f.node = n
		f.tail = tail
		_fish.append(f)
	_splash = Fx.burst({"amount": 22, "lifetime": 0.9, "shape": "sphere", "radius": 0.15, "tex": Fx.Tex.DOT, "size": 0.12,
		"dir": Vector3.UP, "spread": 55.0, "speed": Vector2(1.5, 3.8), "gravity": Vector3(0, -9.0, 0),
		"color": Color(0.9, 1.0, 1.0, 0.85), "curve": "shrink", "aabb": AABB(Vector3(-extent.x - 3, -2, -extent.y - 3), Vector3(extent.x * 2 + 6, 6, extent.y * 2 + 6))})
	add_child(_splash)


## The loop: a superellipse round the centre (rounded square), parameter a in radians.
func _loop_pos(a: float, lane: float) -> Vector3:
	var c: float = cos(a)
	var s: float = sin(a)
	return Vector3(signf(c) * pow(absf(c), 0.8) * extent.x * lane, 0.0, signf(s) * pow(absf(s), 0.8) * extent.y * lane)


func _process(dt: float) -> void:
	_t += dt
	for f: Fish in _fish:
		var a: float = f.phase + _t * f.rate * TAU * 0.5
		var p: Vector3 = _loop_pos(a, f.lane)
		var q: Vector3 = _loop_pos(a + 0.05, f.lane)
		var dir: Vector3 = q - p
		var y: float = -depth - 0.2 * sin(_t * 0.7 + f.phase)
		var tilt: float = 0.0
		if f.leap_t >= 0.0:
			f.leap_t += dt
			var u: float = f.leap_t / 1.1
			if u >= 1.0:
				f.leap_t = -1.0
				f.next_leap = _t + _rng.randf_range(leap_every * 0.6, leap_every * 1.4)
				_splash.global_position = f.node.global_position
				_splash.restart()
				_splash.emitting = true
				# SOUND: lotus_koi_splash - a koi falling back into the pond
				WorldAudio.at(self, "lotus_koi_splash", f.node.global_position, 0.7, 28.0)
			else:
				y = -depth + 1.5 * 4.0 * u * (1.0 - u) * 1.1 + depth * 0.0
				tilt = (0.5 - u) * 1.8
		elif _t >= f.next_leap:
			f.leap_t = 0.0
			_splash.global_position = f.node.global_position
			_splash.restart()
			_splash.emitting = true
			WorldAudio.at(self, "lotus_koi_splash", f.node.global_position, 0.6, 28.0)
		f.node.position = Vector3(p.x, y, p.z)
		if dir.length() > 0.0001:
			f.node.rotation = Vector3(tilt, atan2(-dir.x, -dir.z), 0.0)
		f.tail.rotation.y = 0.55 * sin(_t * 5.0 + f.phase * 3.0)
