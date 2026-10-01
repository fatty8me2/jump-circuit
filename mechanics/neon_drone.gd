class_name NeonDrone
extends Node3D
## Neon City searchlight drone: a police-style quadcopter hovering over a rooftop and sweeping
## a hard white-amber searchlight back and forth between two floor points on the course clock
## (eased, with a hover pause at each end). Get caught in the bright pool on the floor and you are
## zapped back to the checkpoint. Always readable: the pool and its light cone are lit the whole
## time, the drone chirps and its strobes flare as it sets off on every sweep, and the rain glitters
## in the beam. Pure function of Game.course_time, identical for every racer.
## Build: set `a` / `b` (floor points, world, same height), then add the node anywhere (it places
## itself).

@export var a: Vector3 = Vector3.ZERO
@export var b: Vector3 = Vector3(8, 0, 0)
## Height of the drone above the floor.
@export var hover: float = 7.5
## Radius of the deadly pool of light on the floor.
@export var radius: float = 1.7
## Seconds for a full there-and-back.
@export var period: float = 8.0
@export var phase: float = 0.0
## Fraction of each leg spent hovering at its end.
@export var dwell: float = 0.22

var _drone: Node3D
var _cone: MeshInstance3D
var _pool: MeshInstance3D
var _rotors: Array[Node3D] = []
var _strobes: Array[MeshInstance3D] = []
var _spot: SpotLight3D
var _motes: GPUParticles3D
var _flash_mat: StandardMaterial3D
var _red_mat: StandardMaterial3D
var _blue_mat: StandardMaterial3D
var _dim_mat: StandardMaterial3D
var _leg: int = -999
var _hit_tick: int = -100
var _hum: AudioStreamPlayer3D


func _ready() -> void:
	top_level = true
	global_position = Vector3.ZERO
	_build()
	_apply(Game.course_time)
	add_to_group("course_clock")
	# SOUND: neon_drone_hum - the rotors' whine (loop)
	_hum = WorldAudio.loop("neon_drone_hum", _drone, -6.0, 30.0, 5.0)


## 0..1 position between a and b at time t (ping-pong with a hover pause at each end).
func u_at(t: float) -> float:
	var u: float = fposmod(t / maxf(period, 0.01) + phase, 1.0)
	var tri: float = 1.0 - absf(u * 2.0 - 1.0)
	var k: float = clampf((tri - dwell) / maxf(1.0 - 2.0 * dwell, 0.01), 0.0, 1.0)
	return k * k * (3.0 - 2.0 * k)


## Centre of the pool of light on the floor at time t.
func spot_at(t: float) -> Vector3:
	return a.lerp(b, u_at(t))


## True when the pool stays at least `margin` m clear of every point in `pts` (flat distance)
## for the whole of [now + t0, now + t1]. For the bot.
func clear_of(pts: Array, margin: float, t0: float, t1: float) -> bool:
	var s: float = t0
	while s <= t1:
		var c: Vector3 = spot_at(Game.course_time + s)
		for p: Vector3 in pts:
			if Vector2(c.x - p.x, c.z - p.z).length() < radius + margin:
				return false
		s += 0.04
	return true


func snap_to_clock() -> void:
	_apply(Game.course_time)


func _physics_process(_dt: float) -> void:
	_apply(Game.course_time)
	var pl: Node3D = WorldAudio.local_player(self)
	if pl == null:
		return
	var c: Vector3 = spot_at(Game.course_time)
	var p: Vector3 = pl.global_position
	if Vector2(p.x - c.x, p.z - c.z).length() < radius * 0.92 and p.y > c.y - 0.6 and p.y < c.y + hover - 1.5:
		var tick: int = Engine.get_physics_frames()
		if tick - _hit_tick > 30:
			_hit_tick = tick
			# SOUND: neon_drone_zap - caught in the searchlight
			WorldAudio.at(self, "neon_drone_zap", p, 1.0, 40.0)
			var n: Node = self
			while n != null and not n.has_method("fail"):
				n = n.get_parent()
			if n != null:
				n.call_deferred("fail", "hazard")


func _apply(t: float) -> void:
	var c: Vector3 = spot_at(t)
	# lean into the direction of travel
	var ahead: Vector3 = spot_at(t + 0.15) - c
	_drone.position = c + Vector3(0, hover, 0)
	_drone.rotation = Vector3(ahead.z * 0.9, 0, -ahead.x * 0.9).limit_length(0.35)
	_pool.position = c + Vector3(0, 0.04, 0)
	_cone.position = c + Vector3(0, hover * 0.5, 0)


func _process(dt: float) -> void:
	var t: float = Game.course_time
	for r: Node3D in _rotors:
		r.rotation.y += dt * 40.0
	# a new sweep: chirp and flare the strobes as it sets off
	var u: float = fposmod(t / maxf(period, 0.01) + phase, 1.0)
	var leg: int = int(floor(t / maxf(period, 0.01) + phase) * 2.0) + (1 if u >= 0.5 else 0)
	var into_leg: float = fposmod(u, 0.5) * 2.0
	if leg != _leg and into_leg >= dwell * 0.5:
		if _leg != -999:
			# SOUND: neon_drone_chirp - the drone sets off on a sweep
			WorldAudio.at(self, "neon_drone_chirp", _drone.global_position, 0.8, 45.0)
		_leg = leg
	var flare: bool = into_leg > dwell * 0.5 - 0.06 and into_leg < dwell * 0.5 + 0.2
	var blink: bool = fmod(t, 0.5) < 0.12
	for i: int in _strobes.size():
		var on: bool = flare or (blink if i % 2 == 0 else not blink and fmod(t, 0.5) < 0.24)
		_strobes[i].material_override = (_red_mat if i % 2 == 0 else _blue_mat) if on else _dim_mat


func _build() -> void:
	var hull: StandardMaterial3D = Look.flat(Color(0.08, 0.08, 0.1), 0.3, 0.7)
	var trim: StandardMaterial3D = Look.flat(Color(0.85, 0.85, 0.9), 0.3, 0.6)
	_red_mat = Look.flat(Color(1.0, 0.1, 0.15), 0.3, 0.0, 6.0)
	_blue_mat = Look.flat(Color(0.2, 0.5, 1.0), 0.3, 0.0, 6.0)
	_dim_mat = Look.flat(Color(0.15, 0.1, 0.12), 0.5)
	_drone = Node3D.new()
	add_child(_drone)
	var body := Look.sphere(0.55, hull)
	body.scale = Vector3(1.3, 0.55, 1.6)
	_drone.add_child(body)
	_drone.add_child(Look.box(Vector3(1.4, 0.08, 0.3), trim, Vector3(0, 0.22, 0)))
	for i: int in 4:
		var ang: float = PI * 0.25 + PI * 0.5 * float(i)
		var dir := Vector3(cos(ang), 0, sin(ang))
		var arm := Look.box(Vector3(0.12, 0.08, 1.2), hull, dir * 0.75)
		arm.rotation.y = -ang + PI * 0.5
		_drone.add_child(arm)
		var pod := Look.cylinder(0.12, 0.22, hull, dir * 1.3 + Vector3(0, 0.1, 0), -1.0, 10)
		_drone.add_child(pod)
		var rotor := Node3D.new()
		rotor.position = dir * 1.3 + Vector3(0, 0.24, 0)
		rotor.add_child(Look.box(Vector3(1.0, 0.02, 0.12), trim))
		rotor.add_child(Look.cylinder(0.5, 0.01, Look.flat(Color(0.7, 0.7, 0.75, 0.25), 0.4), Vector3.ZERO, -1.0, 20))
		rotor.rotation.y = float(i)
		_drone.add_child(rotor)
		_rotors.append(rotor)
		var strobe := Look.sphere(0.08, _dim_mat, dir * 1.3 + Vector3(0, -0.06, 0))
		_drone.add_child(strobe)
		_strobes.append(strobe)
	# the searchlight head under the belly
	var head := Look.cylinder(0.26, 0.3, trim, Vector3(0, -0.4, 0), 0.18, 14)
	_drone.add_child(head)
	_drone.add_child(Look.cylinder(0.2, 0.04, Look.flat(Color(1.0, 0.95, 0.8), 0.2, 0.0, 8.0), Vector3(0, -0.56, 0), -1.0, 14))
	_spot = SpotLight3D.new()
	_spot.light_color = Color(1.0, 0.9, 0.72)
	_spot.light_energy = 9.0
	_spot.spot_range = hover + 3.0
	_spot.spot_angle = rad_to_deg(atan((radius + 0.6) / maxf(hover, 0.5)))
	_spot.spot_attenuation = 0.5
	_spot.shadow_enabled = false
	_spot.rotation.x = -PI * 0.5
	_spot.position = Vector3(0, -0.6, 0)
	_drone.add_child(_spot)
	# the beam: a soft additive cone from the lamp down to the floor
	var cm := CylinderMesh.new()
	cm.top_radius = 0.2
	cm.bottom_radius = radius
	cm.height = hover - 0.6
	cm.radial_segments = 24
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	var bm := ShaderMaterial.new()
	bm.shader = preload("res://visual/neon_beam.gdshader")
	bm.set_shader_parameter("tint", Color(1.0, 0.86, 0.62))
	bm.set_shader_parameter("strength", 0.55)
	_cone = Look.mesh_node(cm, bm)
	_cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cone.position.y = -0.3
	add_child(_cone)
	# the pool of light on the floor: hot centre, a red danger rim
	var pq := QuadMesh.new()
	pq.size = Vector2(radius * 2.3, radius * 2.3)
	pq.orientation = PlaneMesh.FACE_Y
	var pm := ShaderMaterial.new()
	pm.shader = preload("res://visual/neon_pool.gdshader")
	pm.set_shader_parameter("tint", Color(1.0, 0.9, 0.7))
	pm.set_shader_parameter("rim", Color(1.0, 0.15, 0.2))
	_pool = Look.mesh_node(pq, pm)
	_pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_pool)
	# rain glittering in the beam
	_motes = Fx.emitter({"amount": 40, "lifetime": 0.7, "local": true, "shape": "box",
		"extents": Vector3(radius * 0.5, 0.2, radius * 0.5), "dir": Vector3(0.1, -1, 0), "spread": 4.0,
		"speed": Vector2(9.0, 12.0), "facing": "velocity", "tex": Fx.Tex.SPARK, "size": Vector2(0.02, 0.5),
		"color": Color(2.2, 2.0, 1.6, 0.8), "fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]),
		"aabb": AABB(Vector3(-radius - 2, -hover - 2, -radius - 2), Vector3(radius * 2 + 4, hover + 4, radius * 2 + 4))})
	_motes.position = Vector3(0, -0.9, 0)
	_drone.add_child(_motes)
