class_name HyperloopTrain
extends Node3D
## Hyperloop: a distant mag-lev TRAIN streaking through a glass transit tube - pure scenery that sells the
## scale of the megastructure. A string of white capsule cars with a glowing cyan window band runs from
## `a` to `b` on a loop (a pure function of the course clock, so a restart or a respawn never desyncs it,
## and there is nothing for the player to wait for). It plays a rushing pass-by whoosh when it goes by
## close to the listener. No collision.

const WHITE := Color(0.95, 0.97, 1.0)
const CYAN := Color(0.25, 0.9, 1.0)

var a: Vector3 = Vector3.ZERO
var b: Vector3 = Vector3(0, 0, -200)
var speed: float = 90.0
var cars: int = 5
var car_len: float = 9.0
var radius: float = 1.6
var phase: float = 0.0
var _car_nodes: Array[Node3D] = []
var _whoosh_t: float = -100.0


static func make(parent: Node3D, from: Vector3, to: Vector3, car_count: int = 5, spd: float = 90.0, ph: float = 0.0) -> HyperloopTrain:
	var t := HyperloopTrain.new()
	t.a = from
	t.b = to
	t.cars = car_count
	t.speed = spd
	t.phase = ph
	parent.add_child(t)
	return t


func _ready() -> void:
	var white: StandardMaterial3D = Look.flat(WHITE, 0.3, 0.2)
	var glow: StandardMaterial3D = Look.flat(CYAN, 0.3, 0.0, 2.2)
	for i: int in cars:
		var car := Node3D.new()
		# a capsule body lying along the direction of travel
		var body := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = radius
		cm.height = car_len
		cm.radial_segments = 16
		cm.rings = 4
		body.mesh = cm
		body.material_override = white
		body.rotation.x = PI * 0.5
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		car.add_child(body)
		# the window band
		var band := Look.box(Vector3(radius * 2.05, 0.35, car_len * 0.7), glow)
		band.position = Vector3(0, radius * 0.22, 0)
		band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		car.add_child(band)
		add_child(car)
		_car_nodes.append(car)
	_place(Game.course_time)
	set_process(true)


func _span() -> float:
	return a.distance_to(b) + float(cars) * (car_len + 1.0) + 40.0


func _place(time: float) -> void:
	var dir: Vector3 = b - a
	var len_ab: float = dir.length()
	if len_ab < 0.01:
		return
	dir /= len_ab
	var total: float = _span()
	var head: float = fposmod(time * speed + phase * total, total) - 20.0
	var yaw: float = atan2(-dir.x, -dir.z)
	var pitch: float = asin(clampf(dir.y, -1.0, 1.0))
	for i: int in _car_nodes.size():
		var s: float = head - float(i) * (car_len + 1.0)
		var car: Node3D = _car_nodes[i]
		car.visible = s >= -car_len and s <= len_ab + car_len
		car.global_position = a + dir * s
		car.global_basis = Basis.from_euler(Vector3(pitch, yaw, 0.0), EULER_ORDER_YXZ)


func _process(_dt: float) -> void:
	_place(Game.course_time)
	var t: float = Game.course_time
	if t - _whoosh_t > 6.0 and not _car_nodes.is_empty():
		var lead: Node3D = _car_nodes[0]
		if lead.visible:
			var lis: Vector3 = WorldAudio.listener(self)
			if lead.global_position.distance_to(lis) < 60.0:
				_whoosh_t = t
				# SOUND: hyperloop_train_pass - a pressure-wave whoosh as a train streaks through a nearby tube
				WorldAudio.at(self, "hyperloop_train_pass", lead.global_position, 0.8, 70.0)
