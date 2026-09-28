class_name CarrierElevator
extends MovingPlatform
## Super Carrier: a DECK-EDGE AIRCRAFT ELEVATOR - a huge steel platform that climbs the outside of
## the hull between the hangar deck and the flight deck (a MovingPlatform on the course clock with
## long rests at each end). It dresses itself: non-skid deck with a tie-down grid, yellow-and-black
## edge bands, safety stanchions that rise along its open edges while it moves, amber warning
## beacons that spin while it travels, and a hydraulic hum. `open_side` is the local direction of
## its outboard (sea) edge.

@export var open_side: Vector3 = Vector3(1, 0, 0)

const YELLOW := Color(1.0, 0.8, 0.12)

var _posts: Array[Node3D] = []
var _beacons: Array[Node3D] = []
var _beacon_mat: StandardMaterial3D
var _hum: AudioStreamPlayer3D
var _was_moving: bool = false
var _spray: GPUParticles3D


func _init() -> void:
	style = "alt"
	dwell = 0.3


func _ready() -> void:
	super._ready()
	_dress()
	_hum = WorldAudio.loop("carrier_elevator_hum", self, -10.0, 30.0, 6.0, false)
	set_process(true)


func _hums() -> bool:
	return false


func is_moving_at(time: float) -> bool:
	return offset_at(time + 0.05).distance_to(offset_at(time)) > 0.002


func _process(dt: float) -> void:
	var moving: bool = is_moving_at(Game.course_time)
	# stanchions rise out of the deck edge while it travels, fold away at the stops
	for p: Node3D in _posts:
		p.position.y = move_toward(p.position.y, 0.55 if moving else -0.5, dt * 2.5)
	for b: Node3D in _beacons:
		b.rotation.y += dt * (9.0 if moving else 0.0)
	_beacon_mat.emission_energy_multiplier = 2.6 if moving else 0.3
	if moving != _was_moving:
		WorldAudio.at(self, "carrier_elevator_start" if moving else "carrier_elevator_stop", global_position, 0.9, 45.0)
	WorldAudio.set_active(_hum, moving)
	if _spray != null and _spray.emitting != moving:
		_spray.emitting = moving
	_was_moving = moving


func _dress() -> void:
	var half := size * 0.5
	var top: float = half.y
	var out: Vector3 = open_side.normalized()
	var across := Vector3(-out.z, 0, out.x)
	var along_len: float = absf(size.dot(across.abs()))
	var out_len: float = absf(size.dot(out.abs()))
	# tie-down grid: rows of little recessed cups over the deck
	var cup: StandardMaterial3D = Look.flat(Color(0.14, 0.15, 0.16), 0.8)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var cm := CylinderMesh.new()
	cm.top_radius = 0.09
	cm.bottom_radius = 0.09
	cm.height = 0.02
	cm.radial_segments = 8
	cm.rings = 1
	mm.mesh = cm
	var nx: int = int(size.x / 1.4)
	var nz: int = int(size.z / 1.4)
	mm.instance_count = nx * nz
	var k: int = 0
	for ix: int in nx:
		for iz: int in nz:
			var p := Vector3(-half.x + 0.7 + float(ix) * 1.4, top + 0.005, -half.z + 0.7 + float(iz) * 1.4)
			mm.set_instance_transform(k, Transform3D(Basis.IDENTITY, p))
			k += 1
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = cup
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	# yellow-and-black bands along the open edge
	var ya: StandardMaterial3D = Look.flat(YELLOW, 0.6, 0.0, 0.2)
	var yb: StandardMaterial3D = Look.flat(Color(0.08, 0.08, 0.08), 0.7)
	var n: int = int(along_len / 1.0)
	for i: int in n:
		var f: float = (float(i) + 0.5) / float(n) - 0.5
		var c: Vector3 = out * (out_len * 0.5 - 0.3) + across * f * along_len + Vector3(0, top + 0.01, 0)
		var sz: Vector3 = (across.abs() * (along_len / float(n))) + out.abs() * 0.5 + Vector3(0, 0.03, 0)
		var b := Look.box(sz, ya if i % 2 == 0 else yb, c)
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(b)
	# safety stanchions along the open edge (they rise while it moves)
	var post: StandardMaterial3D = Look.flat(YELLOW, 0.5, 0.2)
	var np: int = maxi(int(along_len / 3.0), 2)
	for i: int in np:
		var f: float = float(i) / float(np - 1) - 0.5
		var holder := Node3D.new()
		holder.position = Vector3(0, -0.5, 0)
		add_child(holder)
		holder.add_child(Look.cylinder(0.05, 1.1, post, out * (out_len * 0.5 - 0.15) + across * f * (along_len - 0.6) + Vector3(0, top, 0)))
		_posts.append(holder)
	# amber beacons at the inboard corners
	_beacon_mat = Look.flat(Color(1.0, 0.55, 0.1), 0.3, 0.0, 0.3).duplicate() as StandardMaterial3D
	for sx: float in [-1.0, 1.0]:
		var base: Vector3 = -out * (out_len * 0.5 - 0.4) + across * sx * (along_len * 0.5 - 0.4) + Vector3(0, top, 0)
		add_child(Look.cylinder(0.14, 0.3, Look.flat(Color(0.2, 0.2, 0.2), 0.5, 0.6), base + Vector3(0, 0.15, 0)))
		var b := Node3D.new()
		b.position = base + Vector3(0, 0.42, 0)
		add_child(b)
		b.add_child(Look.cylinder(0.13, 0.22, _beacon_mat, Vector3.ZERO))
		b.add_child(Look.box(Vector3(0.05, 0.16, 0.3), Look.flat(Color(0.15, 0.15, 0.15), 0.6), Vector3(0, 0, 0.0)))
		_beacons.append(b)
	# sea spray whipped up off the open edge while it travels
	var vis := AABB(-size - Vector3(4, 8, 4), size * 2.0 + Vector3(8, 16, 8))
	_spray = Fx.emitter({"amount": 30, "lifetime": 1.4, "emitting": false, "shape": "box",
		"extents": across.abs() * along_len * 0.45 + Vector3(0, 0.1, 0) + out.abs() * 0.1,
		"offset": out * out_len * 0.5 + Vector3(0, -half.y, 0), "dir": out + Vector3(0, -0.3, 0), "spread": 25.0,
		"speed": Vector2(1.0, 3.0), "gravity": Vector3(0, -6.0, 0), "tex": Fx.Tex.DOT, "size": 0.12, "additive": false,
		"color": Color(0.95, 0.98, 1.0, 0.8), "fade": PackedFloat32Array([0.0, 1.0, 0.0]), "aabb": vis})
	add_child(_spray)
