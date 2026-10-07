class_name FungalCap
extends StaticBody3D
## Mushroom Hollow: a BOUNCY CAP, a big springy toadstool top painted like a target. It is a vertical
## bounce pad (it sets your vertical speed and keeps your run, like every vertical pad) whose spring
## depends on WHERE you land: dead centre (the gold heart) gives the full `high` launch, and it eases
## down to a `low` hop at the very rim. Land in the middle and it throws you far; clip the edge and it
## only hops you. The rings painted on the cap are the rule, so it is readable at a glance, and a
## column of little spore lights above it shows how high the LAST bounce threw you.
## The rule is a pure function of where you stand on it (no clock, nothing to wait for).
## Positioned by the centre of the TOP of the cap.

@export var radius: float = 1.6
@export var low: float = 13.0
@export var high: float = 21.0
@export var tint: Color = Color(0.9, 0.22, 0.2)
## Decorative stalk under the cap (0 = none: the cap grows out of whatever is below).
@export var stalk: float = 5.0
## Fraction of the radius (from the middle) that still gives the full launch.
@export var heart: float = 0.3

const LIGHTS: int = 9

var _cap: Node3D
var _cap_mat: StandardMaterial3D
var _lights: Array[MeshInstance3D] = []
var _squash: float = 0.0
var _last_apex: float = 0.0
var _burst: GPUParticles3D
var _ring: GPUParticles3D
var _player: Node3D


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = 0.5
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, -0.25, 0)
	add_child(cs)
	_build_visual()
	var n: Node = get_parent()
	while n != null and not n.has_method("fail"):
		n = n.get_parent()
	if n != null:
		_player = n.get("player") as Node3D
	set_process(false)


## Launch speed for a landing `d` metres (flat) from the middle of the cap.
func strength_at(d: float) -> float:
	var k: float = clampf((d / radius - heart) / maxf(1.0 - heart, 0.01), 0.0, 1.0)
	k = k * k * (3.0 - 2.0 * k)
	return lerpf(high, low, k)


## Apex (m above the cap) of a bounce of strength `s`.
static func apex_for(s: float) -> float:
	return s * s / 60.0


func _flat_offset() -> float:
	if _player == null:
		return 0.0
	var d: Vector3 = _player.global_position - global_position
	return Vector2(d.x, d.z).length()


# ---- pad contract (duck-typed by Player._scan_collisions) -----------------------------

func get_surface_up() -> Vector3:
	return Vector3.UP


func get_launch() -> Dictionary:
	return {"velocity": Vector3(0, strength_at(_flat_offset()), 0), "keep_horizontal": true}


func launch_origin() -> Vector3:
	return global_position + Vector3(0, 0.05, 0)


## Its own voice (a rubbery boing) once the lead's clip exists; the plain pad bounce until then.
func bounce_clip() -> String:
	return "fungal_cap_boing" if Sfx.has_clip("fungal_cap_boing") else "bounce"


func on_bounced(_p: Node) -> void:
	var s: float = strength_at(_flat_offset())
	_last_apex = apex_for(s)
	_squash = 0.35 + 0.65 * clampf((s - low) / maxf(high - low, 0.1), 0.0, 1.0)
	set_process(true)
	if _burst != null:
		_burst.restart()
		_burst.emitting = true
	if _ring != null:
		_ring.restart()
		_ring.emitting = true


# ---- visuals ------------------------------------------------------------------------------

var _wob: float = 0.0
var _wob_v: float = 0.0


func _process(dt: float) -> void:
	# a springy wobble: squash on landing, overshoot, settle
	if _squash > 0.0:
		_wob_v -= _squash * 14.0
		_squash = 0.0
	var acc: float = -_wob * 150.0 - _wob_v * 6.5
	_wob_v += acc * dt
	_wob += _wob_v * dt
	var w: float = clampf(_wob, -0.4, 0.4)
	_cap.scale = Vector3(1.0 - w * 0.45, 1.0 + w, 1.0 - w * 0.45)
	_cap_mat.emission_energy_multiplier = 0.25 + absf(w) * 2.5
	for i: int in _lights.size():
		_lights[i].visible = 0.9 + float(i) * 0.9 < _last_apex - 0.2
	if absf(_wob) < 0.003 and absf(_wob_v) < 0.05:
		_wob = 0.0
		_wob_v = 0.0
		set_process(false)


func _build_visual() -> void:
	var r: float = radius * 1.12
	# the cap: a domed, spotted top whose pivot sits on the top surface
	_cap = Node3D.new()
	add_child(_cap)
	_cap_mat = StandardMaterial3D.new()
	_cap_mat.albedo_color = tint
	_cap_mat.roughness = 0.5
	_cap_mat.emission_enabled = true
	_cap_mat.emission = tint
	_cap_mat.emission_energy_multiplier = 0.25
	_cap_mat.rim_enabled = true
	_cap_mat.rim = 0.35
	var dome := Look.sphere(r, _cap_mat, Vector3(0, -0.5 * r * 0.5, 0))
	dome.scale = Vector3(1.0, 0.5, 1.0)
	_cap.add_child(dome)
	# the bullseye: cream rings painted flat on the top, a gold heart (the full-launch zone)
	var cream: StandardMaterial3D = Look.flat(Color(1.0, 0.95, 0.8), 0.6)
	for ring_r: float in [radius * 0.62, radius * 0.9]:
		var tm := TorusMesh.new()
		tm.inner_radius = ring_r - 0.05
		tm.outer_radius = ring_r + 0.05
		tm.rings = 40
		tm.ring_segments = 5
		var rn := Look.mesh_node(tm, cream, Vector3(0, 0.0, 0))
		rn.scale = Vector3(1, 0.25, 1)
		rn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_cap.add_child(rn)
	var heart_disc := Look.cylinder(radius * heart + 0.08, 0.04, Look.flat(Color(1.0, 0.8, 0.25), 0.4, 0.0, 0.9), Vector3(0, 0.0, 0), -1.0, 24)
	heart_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cap.add_child(heart_disc)
	# a few cream spots on the dome's shoulder
	for i: int in 7:
		var a: float = TAU * float(i) / 7.0 + 0.4
		var sp := Look.sphere(0.12 + 0.06 * float(i % 2), cream, Vector3(cos(a) * r * 0.9, -0.14, sin(a) * r * 0.9))
		sp.scale = Vector3(1.0, 0.5, 1.0)
		_cap.add_child(sp)
	# gills under the rim
	var gill := Look.cylinder(r * 0.96, 0.1, Look.flat(Color(0.95, 0.86, 0.66), 0.8), Vector3(0, -0.5 * r * 0.5 - 0.04, 0), r * 0.3, 24)
	_cap.add_child(gill)
	if stalk > 0.0:
		var stem_mat: StandardMaterial3D = Look.flat(Color(0.97, 0.92, 0.8), 0.8)
		add_child(Look.cylinder(radius * 0.34, stalk, stem_mat, Vector3(0, -0.55 - stalk * 0.5, 0), radius * 0.26, 14))
		var skirt := Look.cylinder(radius * 0.5, 0.2, Look.flat(Color(0.99, 0.95, 0.85), 0.7), Vector3(0, -1.0, 0), radius * 0.32, 16)
		add_child(skirt)
	# the spore-light column: how high the last bounce threw you
	var dot: StandardMaterial3D = Look.flat(Color(1.0, 0.9, 0.5), 0.3, 0.0, 2.0)
	for i: int in LIGHTS:
		var d := Look.sphere(0.1 - 0.05 * float(i) / float(LIGHTS), dot, Vector3(0, 0.9 + float(i) * 0.9, 0))
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		d.visible = false
		add_child(d)
		_lights.append(d)
	var vis := AABB(Vector3(-5, -2, -5), Vector3(10, 14, 10))
	# idle: pollen drifting up off the cap
	var idle: GPUParticles3D = Fx.emitter({"amount": 8, "lifetime": 2.8, "shape": "ring", "ring_radius": radius * 0.9,
		"ring_inner": radius * 0.2, "dir": Vector3.UP, "spread": 25.0, "speed": Vector2(0.25, 0.7),
		"gravity": Vector3(0, 0.1, 0), "tex": Fx.Tex.DOT, "size": 0.13, "curve": "pop", "turbulence": 0.7,
		"color": Fx.hot(Color(1.0, 0.9, 0.55), 1.6), "aabb": vis, "preprocess": 2.8, "local": true})
	idle.position = Vector3(0, 0.1, 0)
	add_child(idle)
	# the bounce: a burst of spores and a flat ring of dust
	_burst = Fx.burst({"amount": 28, "lifetime": 0.9, "shape": "ring", "ring_radius": radius * 0.9, "ring_inner": radius * 0.4,
		"dir": Vector3.UP, "spread": 55.0, "speed": Vector2(2.5, 5.5), "gravity": Vector3(0, -2.0, 0),
		"size": 0.2, "color": Fx.hot(Color(1.0, 0.92, 0.6), 2.0), "aabb": vis})
	_burst.position = Vector3(0, 0.1, 0)
	add_child(_burst)
	_ring = Fx.shockwave(radius * 1.5, {"lifetime": 0.45, "color": Fx.hot(Color(1.0, 0.95, 0.75), 1.3), "aabb": vis})
	_ring.position = Vector3(0, 0.08, 0)
	add_child(_ring)
