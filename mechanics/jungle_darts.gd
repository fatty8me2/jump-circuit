class_name JungleDarts
extends Node3D
## Jungle Temple: a dart trap. A carved stone face set in a wall fires volleys of poison darts
## straight across a lane on the course clock. Each cycle: quiet, then the TELL (`warn` seconds:
## the face's jade eyes and the holes in its mouth glow brighter and brighter, grit puffs from the
## holes and the mechanism clicks faster), then the VOLLEY (`fire_time` seconds: darts streak
## across the lane - touch the lane and you are out), then quiet again. Pure function of
## Game.course_time, like the laser gates.
## Positioned at the foot of the face: local +X runs across the lane to the far wall (`span` m),
## the lane is `depth` m deep along local Z and the darts fly between 0.25 m and `height` m up.

@export var span: float = 3.4
@export var depth: float = 1.2
@export var height: float = 2.2
@export var period: float = 4.8
@export var fire_time: float = 1.0
@export var warn: float = 1.0
@export var phase: float = 0.0
## Build the carved face (false when the level dresses the wall itself).
@export var show_face: bool = true

const STONE := Color(0.46, 0.47, 0.38)
const JADE := Color(0.25, 0.95, 0.65)
const DART := Color(0.86, 0.22, 0.14)

var _area: Area3D
var _darts: Array[MeshInstance3D] = []
var _dart_lane: Array[Vector2] = []    # (y, z) of each dart's hole
var _eyes: Array[MeshInstance3D] = []
var _eye_mat: StandardMaterial3D
var _hole_mat: StandardMaterial3D
var _grit: GPUParticles3D
var _hits: GPUParticles3D
var _lamp: OmniLight3D
var _click_k: int = -1
var _fired_k: int = -1


func _ready() -> void:
	add_to_group("course_clock")
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 2
	_area.monitorable = false
	var shape := BoxShape3D.new()
	shape.size = Vector3(span, height - 0.2, depth * 0.9)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	_area.add_child(cs)
	_area.position = Vector3(span * 0.5, 0.2 + (height - 0.2) * 0.5, 0)
	add_child(_area)
	_build()
	_area.body_entered.connect(_on_body)
	snap_to_clock()


func _build() -> void:
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.albedo_color = JADE
	_eye_mat.emission_enabled = true
	_eye_mat.emission = JADE
	_eye_mat.emission_energy_multiplier = 0.4
	_hole_mat = StandardMaterial3D.new()
	_hole_mat.albedo_color = Color(0.08, 0.1, 0.06)
	_hole_mat.emission_enabled = true
	_hole_mat.emission = Color(1.0, 0.35, 0.15)
	_hole_mat.emission_energy_multiplier = 0.0
	var stone: StandardMaterial3D = Look.flat(STONE, 0.9)
	var dark: StandardMaterial3D = Look.flat(STONE.darkened(0.35), 0.95)
	if show_face:
		# the face: a slab with a brow, two jade eyes, a nose ridge and a gaping mouth full of holes
		var w: float = depth + 1.0
		var h: float = height + 1.6
		add_child(Look.box(Vector3(0.7, h, w), stone, Vector3(-0.35, h * 0.5, 0)))
		add_child(Look.box(Vector3(0.9, 0.35, w + 0.2), dark, Vector3(-0.3, h - 0.25, 0)))
		add_child(Look.box(Vector3(0.5, 0.3, w * 0.9), dark, Vector3(-0.05, height + 0.7, 0)))
		for s: float in [-1.0, 1.0]:
			var e := Look.box(Vector3(0.12, 0.22, 0.34), _eye_mat, Vector3(0.02, height + 0.35, s * w * 0.24))
			add_child(e)
			_eyes.append(e)
		add_child(Look.box(Vector3(0.3, 0.6, 0.22), dark, Vector3(0.1, height - 0.15, 0)))
		add_child(Look.box(Vector3(0.1, height - 0.1, depth + 0.1), Look.flat(Color(0.12, 0.12, 0.1), 0.95), Vector3(0.01, (height + 0.15) * 0.5, 0)))
		# fangs top and bottom of the mouth
		for i: int in 4:
			var z: float = (float(i) - 1.5) / 1.5 * depth * 0.45
			var f := Look.cylinder(0.08, 0.3, Look.flat(Color(0.86, 0.82, 0.7), 0.8), Vector3(0.08, height + 0.02, z), 0.0, 5)
			f.rotation.z = PI
			add_child(f)
	# the holes and their darts: a grid across the mouth
	var rows: int = maxi(2, int(height / 0.55))
	var cols: int = maxi(2, int(depth / 0.45))
	var dart_mat: StandardMaterial3D = Look.flat(DART, 0.5, 0.0, 0.6)
	for r: int in rows:
		for c: int in cols:
			var y: float = 0.35 + (height - 0.5) * float(r) / float(rows - 1)
			var z: float = (float(c) / float(maxi(cols - 1, 1)) - 0.5) * depth * 0.7
			var hole := Look.cylinder(0.06, 0.04, _hole_mat, Vector3(0.07, y, z), -1.0, 8)
			hole.rotation.z = PI * 0.5
			add_child(hole)
			var d := Look.cylinder(0.025, 0.42, dart_mat, Vector3(0.2, y, z), 0.005, 5)
			d.rotation.z = -PI * 0.5
			# a fletching tuft at the back
			d.add_child(Look.box(Vector3(0.1, 0.06, 0.1), Look.flat(Color(0.95, 0.85, 0.3), 0.8), Vector3(0, -0.2, 0)))
			d.visible = false
			add_child(d)
			_darts.append(d)
			_dart_lane.append(Vector2(y, z))
	var big := AABB(Vector3(-2, -1, -depth - 2), Vector3(span + 4, height + 4, depth * 2 + 4))
	_grit = Fx.emitter({"amount": 18, "lifetime": 0.6, "emitting": false, "shape": "box",
		"extents": Vector3(0.05, height * 0.4, depth * 0.35), "dir": Vector3(1, -0.2, 0), "spread": 25.0,
		"speed": Vector2(0.6, 1.6), "gravity": Vector3(0, -6, 0), "additive": false, "size": 0.07,
		"color": Color(0.6, 0.58, 0.46, 0.9), "fade": PackedFloat32Array([1.0, 1.0, 0.0]), "aabb": big})
	_grit.position = Vector3(0.1, height * 0.5 + 0.1, 0)
	add_child(_grit)
	_hits = Fx.emitter({"amount": 26, "lifetime": 0.5, "shape": "box",
		"extents": Vector3(0.05, height * 0.4, depth * 0.35), "dir": Vector3(-1, 0.3, 0), "spread": 50.0,
		"speed": Vector2(1.0, 3.0), "gravity": Vector3(0, -8, 0), "additive": false, "size": 0.06,
		"color": Color(0.7, 0.62, 0.45, 0.9), "fade": PackedFloat32Array([1.0, 1.0, 0.0]), "emitting": false, "aabb": big})
	_hits.position = Vector3(span - 0.05, height * 0.5 + 0.1, 0)
	add_child(_hits)
	_lamp = OmniLight3D.new()
	_lamp.light_color = Color(1.0, 0.5, 0.25)
	_lamp.light_energy = 0.0
	_lamp.omni_range = 4.0
	_lamp.position = Vector3(0.6, height * 0.5, 0)
	add_child(_lamp)


## u in 0..1 within the cycle: [0, 1 - (warn + fire)/period) quiet, then the tell, then the volley.
func _u(t: float) -> float:
	return fposmod(t / maxf(period, 0.01) + phase, 1.0)


func is_firing_at(t: float) -> bool:
	return _u(t) >= 1.0 - fire_time / period


func is_warning_at(t: float) -> bool:
	var u: float = _u(t)
	return u >= 1.0 - (fire_time + warn) / period and u < 1.0 - fire_time / period


## The lane stays quiet over [t + a, t + b].
func is_safe_for(t: float, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if is_firing_at(t + s):
			return false
		s += 0.04
	return is_firing_at(t + b) == false


## Seconds until the next volley starts (0 while firing).
func time_until_fire(t: float) -> float:
	if is_firing_at(t):
		return 0.0
	return (1.0 - fire_time / period - _u(t)) * period


func snap_to_clock() -> void:
	_pose(Game.course_time)


func _physics_process(_dt: float) -> void:
	if is_firing_at(Game.course_time):
		for body: Node3D in _area.get_overlapping_bodies():
			if body is Player:
				_kill()
				return


func _on_body(body: Node3D) -> void:
	if body is Player and is_firing_at(Game.course_time):
		_kill()


func _kill() -> void:
	var n: Node = self
	while n != null and not n.has_method("fail"):
		n = n.get_parent()
	if n != null:
		n.call_deferred("fail", "hazard")


func _process(_dt: float) -> void:
	_pose(Game.course_time)


func _pose(t: float) -> void:
	var u: float = _u(t)
	var fire_u: float = 1.0 - fire_time / period
	var warn_u: float = 1.0 - (fire_time + warn) / period
	var k: int = int(floor(t / period + phase))
	if u >= fire_u:
		# the volley: each dart streaks across, staggered, again and again through the window
		var e: float = (u - fire_u) * period
		for i: int in _darts.size():
			var d: MeshInstance3D = _darts[i]
			var stagger: float = fposmod(float(i) * 0.137, 0.3)
			var f: float = fposmod((e + stagger) / 0.3, 1.0)
			d.visible = e > stagger * 0.5
			var ln: Vector2 = _dart_lane[i]
			d.position = Vector3(0.2 + f * (span - 0.3), ln.x, ln.y)
		_eye_mat.emission_energy_multiplier = 3.0
		_hole_mat.emission_energy_multiplier = 1.4
		_lamp.light_energy = 1.2
		_grit.emitting = false
		_hits.emitting = true
		if _fired_k != k:
			_fired_k = k
			WorldAudio.at(self, "jungle_dart_volley", global_position + global_basis.x * span * 0.5, 0.9, 30.0)
	else:
		for d: MeshInstance3D in _darts:
			d.visible = false
		_hits.emitting = false
		if u >= warn_u:
			var w: float = (u - warn_u) / maxf(fire_u - warn_u, 0.001)
			# eyes and holes brighten through the tell and flicker faster as it builds
			var flick: float = 0.65 + 0.35 * sin(t * (14.0 + 30.0 * w))
			_eye_mat.emission_energy_multiplier = 0.4 + 3.2 * w * flick
			_hole_mat.emission_energy_multiplier = 1.2 * w * flick
			_lamp.light_energy = 0.9 * w
			_grit.emitting = true
			# the mechanism clicks: slow, then faster
			var tick: int = int(floor(w * w * 6.0 + w * 4.0))
			if tick != _click_k:
				_click_k = tick
				WorldAudio.at(self, "jungle_dart_click", global_position, 0.6, 24.0)
		else:
			_eye_mat.emission_energy_multiplier = 0.4
			_hole_mat.emission_energy_multiplier = 0.0
			_lamp.light_energy = 0.0
			_grit.emitting = false
			_click_k = -1
