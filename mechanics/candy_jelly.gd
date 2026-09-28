class_name CandyJelly
extends StaticBody3D
## Sugar Rush: a jelly trampoline. A wobbling dome of fruit jelly that bounces you like a vertical
## bounce pad (your run is kept), except that it gives back what you bring: the launch is
## `base + gain * (the speed you fell onto it at)`, capped at `cap`. Step on and it only hops you;
## jump on and it throws you high; fall onto it from a height (or bounce on it again and again)
## and it throws you higher still. Standing on it you simply keep bouncing, building up to the cap
## in two or three bounces. Readable: the jelly squashes and wobbles on every landing, splashes a
## ring of droplets, and a column of sugar lights over it shows how high the LAST bounce threw you.
## The rule is deterministic (it only reads the player's fall speed on landing).
## Positioned by the centre of its TOP surface.

@export var radius: float = 1.6
@export var base: float = 11.0
@export var gain: float = 0.6
@export var cap: float = 23.0
@export var tint: Color = Color(1.0, 0.25, 0.45)
## Decorative base under the dome (a cake plinth), metres.
@export var plinth: float = 0.9

const LIGHTS: int = 10

var _dome: Node3D
var _dome_mat: StandardMaterial3D
var _lights: Array[MeshInstance3D] = []
var _wobble: float = 0.0
var _wobble_v: float = 0.0
var _fall_speed: float = 0.0
var _last_apex: float = 0.0
var _player: Node3D
var _splash: GPUParticles3D
var _ring: GPUParticles3D


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = 0.6
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, -0.3, 0)
	add_child(cs)
	_build_visual()
	var n: Node = get_parent()
	while n != null and not n.has_method("fail"):
		n = n.get_parent()
	if n != null:
		_player = n.get("player") as Node3D


## Launch speed for a landing at fall speed `fall` (m/s, positive down).
func strength_for(fall: float) -> float:
	return clampf(base + gain * maxf(fall, 0.0), base, cap)


## Apex (m above the jelly) of a bounce taken at fall speed `fall`.
func apex_for(fall: float) -> float:
	var s: float = strength_for(fall)
	return s * s / 60.0


func _physics_process(_dt: float) -> void:
	# the fall speed the player brings: read every tick while they are in the air (this node is
	# built before the player, so it runs first each tick and holds the previous tick's speed)
	if _player == null:
		var n: Node = get_parent()
		while n != null and not n.has_method("fail"):
			n = n.get_parent()
		if n != null:
			_player = n.get("player") as Node3D
		return
	var p := _player as CharacterBody3D
	if p != null and not bool(p.get("grounded")):
		_fall_speed = maxf(-p.velocity.y, 0.0)
	elif p != null:
		_fall_speed = 0.0


# ---- pad contract (duck-typed by Player._scan_collisions) -----------------------------

func get_surface_up() -> Vector3:
	return Vector3.UP


func get_launch() -> Dictionary:
	return {"velocity": Vector3(0, strength_for(_fall_speed), 0), "keep_horizontal": true}


func launch_origin() -> Vector3:
	return global_position + Vector3(0, 0.05, 0)


func bounce_clip() -> String:
	return "candy_jelly_boing" if Sfx.has_clip("candy_jelly_boing") else "bounce"


func on_bounced(_p: Node) -> void:
	var s: float = strength_for(_fall_speed)
	_last_apex = s * s / 60.0
	_wobble_v -= 2.0 + 0.12 * s
	if _splash != null:
		_splash.restart()
		_splash.emitting = true
	if _ring != null:
		_ring.restart()
		_ring.emitting = true
	set_process(true)


# ---- visuals ------------------------------------------------------------------------------

func _process(dt: float) -> void:
	# a springy wobble: squash on landing, overshoot, settle
	var acc: float = -_wobble * 160.0 - _wobble_v * 7.0
	_wobble_v += acc * dt
	_wobble += _wobble_v * dt
	var t: float = Game.course_time
	var idle: float = 0.03 * sin(t * 3.1 + position.x)
	var w: float = clampf(_wobble, -0.45, 0.45)
	_dome.scale = Vector3(1.0 - w * 0.5 + idle, 1.0 + w + idle * 0.5, 1.0 - w * 0.5 - idle)
	_dome_mat.emission_energy_multiplier = 0.5 + absf(w) * 3.0
	for i: int in _lights.size():
		_lights[i].visible = 0.9 + float(i) * 0.9 < _last_apex - 0.2


func _build_visual() -> void:
	var r: float = radius * 1.04
	_dome = Node3D.new()
	add_child(_dome)
	_dome_mat = StandardMaterial3D.new()
	_dome_mat.albedo_color = Color(tint.r, tint.g, tint.b, 0.72)
	_dome_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_dome_mat.roughness = 0.08
	_dome_mat.metallic_specular = 0.9
	_dome_mat.rim_enabled = true
	_dome_mat.rim = 0.7
	_dome_mat.rim_tint = 0.2
	_dome_mat.emission_enabled = true
	_dome_mat.emission = tint.lightened(0.15)
	_dome_mat.emission_energy_multiplier = 0.5
	# the jelly: a squat translucent dome that swells up from its base (pivot at the base)
	var dome := Look.sphere(r, _dome_mat)
	dome.scale = Vector3(1.0, 0.6 / r * 1.02, 1.0)
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_dome.position = Vector3(0, -0.62, 0)
	_dome.add_child(dome)
	# a fruit set inside the jelly, and a sugared rim at its foot
	var fruit: StandardMaterial3D = Look.flat(tint.lerp(Color(1.0, 0.9, 0.3), 0.55), 0.3, 0.0, 0.8)
	var f := Look.sphere(radius * 0.25, fruit, Vector3(0, 0.27, 0))
	f.scale = Vector3(1.0, 0.6, 1.0)
	_dome.add_child(f)
	var tm := TorusMesh.new()
	tm.inner_radius = radius * 0.96
	tm.outer_radius = radius * 1.16
	tm.rings = 36
	tm.ring_segments = 8
	var rim := Look.mesh_node(tm, Look.flat(Color(1.0, 0.97, 0.94), 0.9), Vector3(0, -0.62, 0))
	rim.scale = Vector3(1, 0.6, 1)
	add_child(rim)
	if plinth > 0.0:
		add_child(Look.cylinder(radius * 1.1, plinth, Look.flat(Color(1.0, 0.93, 0.86), 0.8), Vector3(0, -0.62 - plinth * 0.5, 0), radius * 1.15, 28))
		add_child(Look.cylinder(radius * 1.16, 0.12, Look.flat(tint.lightened(0.3), 0.5, 0.0, 0.6), Vector3(0, -0.62 - plinth * 0.5, 0), -1.0, 28))
	# how high the last bounce threw you: a column of sugar lights
	var dot: StandardMaterial3D = Look.flat(tint.lightened(0.45), 0.3, 0.0, 2.4)
	for i: int in LIGHTS:
		var d := Look.sphere(0.09 - 0.04 * float(i) / float(LIGHTS), dot, Vector3(0, 0.9 + float(i) * 0.9, 0))
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		d.visible = false
		add_child(d)
		_lights.append(d)
	var vis := AABB(Vector3(-6, -2, -6), Vector3(12, 14, 12))
	# idle: a few glossy bubbles rising inside and sugar glints on top
	var idle: GPUParticles3D = Fx.emitter({"amount": 8, "lifetime": 1.8, "local": true, "shape": "ring",
		"ring_radius": radius * 0.8, "ring_inner": radius * 0.1, "dir": Vector3.UP, "spread": 10.0,
		"speed": Vector2(0.2, 0.5), "tex": Fx.Tex.STAR, "size": 0.2, "curve": "pop",
		"color": Fx.hot(tint.lightened(0.5), 1.6), "aabb": vis, "preprocess": 1.8})
	idle.position = Vector3(0, 0.05, 0)
	add_child(idle)
	# the bounce: a splash of jelly droplets and a flat ripple ring
	_splash = Fx.burst({"amount": 28, "lifetime": 0.7, "shape": "ring", "ring_radius": radius * 0.8,
		"ring_inner": radius * 0.4, "dir": Vector3.UP, "spread": 55.0, "speed": Vector2(3.0, 6.5),
		"gravity": Vector3(0, -16, 0), "size": 0.22, "additive": false, "tex": Fx.Tex.BUBBLE,
		"color": Color(tint.r, tint.g, tint.b, 0.9).lightened(0.2), "aabb": vis})
	_splash.position = Vector3(0, 0.05, 0)
	add_child(_splash)
	_ring = Fx.shockwave(radius * 1.8, {"lifetime": 0.45, "color": Fx.hot(tint.lightened(0.4), 1.4)})
	_ring.position = Vector3(0, 0.04, 0)
	add_child(_ring)
	set_process(true)
