class_name DinoHerd
extends Node3D
## A herd of DinoCreatures walking (or soaring) round in a big circle, for scenery: bronto herds
## plodding along a riverbank far below, raptor packs sprinting across a meadow, pterosaur flocks
## wheeling over the valley. Purely visual, a function of time only; creatures are built with the cheap
## `lod` 1 silhouette. Each keeps its own radius jitter and phase so a herd looks like a herd.

var kind: String = "bronto"
var count: int = 4
var radius: float = 40.0
## Ground speed (m/s) of the circling.
var speed: float = 3.0
var creature_scale: float = 1.0
var flying: bool = false
## Height of the flight above `position` (flying) or bob amplitude (walking, ignored).
var altitude: float = 0.0

var _creatures: Array[DinoCreature] = []
var _angle0: Array[float] = []
var _rad: Array[float] = []
var _alt: Array[float] = []
var _t: float = 0.0


static func make(parent: Node3D, center: Vector3, kind_id: String, n: int, orbit: float, scale: float, v: float, fly: bool = false, alt: float = 0.0) -> DinoHerd:
	var h := DinoHerd.new()
	h.kind = kind_id
	h.count = n
	h.radius = orbit
	h.creature_scale = scale
	h.speed = v
	h.flying = fly
	h.altitude = alt
	h.position = center
	parent.add_child(h)
	h._build()
	return h


func _build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([kind, count, int(radius), int(position.x), int(position.z)])
	for i: int in count:
		var d: DinoCreature = DinoCreature.make(kind, creature_scale * rng.randf_range(0.85, 1.15), Color(0, 0, 0, 0), 1)
		if flying:
			d.auto_flap = rng.randf_range(4.5, 7.0)
		else:
			d.amount = 0.7
			d.heavy = 0.5
		add_child(d)
		_creatures.append(d)
		_angle0.append(TAU * float(i) / float(count) + rng.randf_range(-0.25, 0.25))
		_rad.append(radius * rng.randf_range(0.82, 1.18))
		_alt.append(rng.randf_range(-0.1, 0.1) * altitude)
	_place()


func _place() -> void:
	for i: int in _creatures.size():
		var a: float = _angle0[i] + _t * speed / maxf(_rad[i], 1.0)
		var d: DinoCreature = _creatures[i]
		d.position = Vector3(cos(a) * _rad[i], altitude + _alt[i] + (sin(_t * 0.7 + float(i)) * 1.5 if flying else 0.0), sin(a) * _rad[i])
		var v: Vector3 = Vector3(-sin(a), 0.0, cos(a))
		d.rotation.y = atan2(-v.x, -v.z)
		if flying:
			d.rotation.z = -0.25
		else:
			d.gait = a * _rad[i] / 2.4 * (1.0 + 0.3 * float(i % 3))
			if kind == "bronto":
				d.pose()


func _process(dt: float) -> void:
	_t += dt
	_place()
