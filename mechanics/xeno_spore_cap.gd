class_name XenoSporeCap
extends StaticBody3D
## Xeno Wilds: a giant mushroom cap that BREATHES. It is a vertical bounce pad (sets your
## vertical speed to its strength and keeps your run, like every vertical pad), but the strength
## swells and ebbs on the course clock between `low` and `high`: land on it at the top of a breath
## for the big launch, in the trough for a hop - or bounce in place until it swells. Readable at a
## glance: the cap swells, brightens and exhales a puff of spores at the top of each breath, its
## rim ring takes the pad strength colour of the moment, and a column of spore lights over it
## shows how high it would throw you right now. A pure function of Game.course_time.
## Positioned by the centre of the TOP of the cap.

@export var low: float = 12.0
@export var high: float = 20.0
@export var period: float = 3.0
@export var phase: float = 0.0
@export var radius: float = 1.4
@export var tint: Color = Color(1.0, 0.42, 0.85)
## Decorative stalk under the cap (0 = none: the cap grows out of whatever is below).
@export var stalk: float = 5.0

const LIGHTS: int = 9

var _cap: Node3D
var _cap_mat: StandardMaterial3D
var _ring_mat: StandardMaterial3D
var _lights: Array[MeshInstance3D] = []
var _squash: float = 0.0
var _burst: GPUParticles3D
var _puff: GPUParticles3D
var _was_peak: bool = false


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
	_apply(Game.course_time)


## 0 at the bottom of a breath, 1 at its top.
func breath_at(time: float) -> float:
	return 0.5 - 0.5 * cos(TAU * (time / period + phase))


func strength_at(time: float) -> float:
	return lerpf(low, high, breath_at(time))


## Apex of a bounce taken at `time` (m above the cap).
func apex_at(time: float) -> float:
	var s: float = strength_at(time)
	return s * s / 60.0


# ---- pad contract (duck-typed by Player._scan_collisions) -----------------------------

func get_surface_up() -> Vector3:
	return Vector3.UP


func get_launch() -> Dictionary:
	return {"velocity": Vector3(0, strength_at(Game.course_time), 0), "keep_horizontal": true}


func launch_origin() -> Vector3:
	return global_position + Vector3(0, 0.05, 0)


## Its own voice (the spongy boing) once the lead's clip exists; the plain pad bounce until then.
func bounce_clip() -> String:
	return "spore_boing" if Sfx.has_clip("spore_boing") else "bounce"


func on_bounced(_player: Node) -> void:
	_squash = 1.0
	if _burst != null:
		_burst.restart()
		_burst.emitting = true


# ---- visuals ------------------------------------------------------------------------------

func _process(dt: float) -> void:
	_squash = maxf(_squash - dt * 3.0, 0.0)
	_apply(Game.course_time)


func _apply(t: float) -> void:
	var b: float = breath_at(t)
	var sq: float = _squash * _squash
	_cap.scale = Vector3(1.0 + 0.1 * b + 0.18 * sq, 0.8 + 0.4 * b - 0.4 * sq, 1.0 + 0.1 * b + 0.18 * sq)
	_cap_mat.emission_energy_multiplier = 0.5 + 1.6 * b + 2.5 * sq
	var s: float = strength_at(t)
	var col: Color = BouncePad.strength_color(s)
	_ring_mat.albedo_color = col
	_ring_mat.emission = col
	var apex: float = s * s / 60.0
	for i: int in _lights.size():
		var h: float = 0.9 + float(i) * 0.85
		_lights[i].visible = h < apex - 0.2
	var peak: bool = b > 0.96
	if peak and not _was_peak and _puff != null:
		_puff.restart()
		_puff.emitting = true
	_was_peak = peak


func _build_visual() -> void:
	var r: float = radius * 1.12
	# the cap: a domed, spotted bell that swells from its top (the pivot sits on the top)
	_cap = Node3D.new()
	add_child(_cap)
	_cap_mat = StandardMaterial3D.new()
	_cap_mat.albedo_color = tint.darkened(0.25)
	_cap_mat.emission_enabled = true
	_cap_mat.emission = tint
	_cap_mat.emission_energy_multiplier = 1.0
	_cap_mat.roughness = 0.45
	_cap_mat.rim_enabled = true
	_cap_mat.rim = 0.6
	var dome := Look.sphere(r, _cap_mat, Vector3(0, -0.5 * r * 0.55, 0))
	dome.scale = Vector3(1.0, 0.55, 1.0)
	_cap.add_child(dome)
	# pale glowing spots on the dome
	var spot: StandardMaterial3D = Look.flat(Color(1.0, 0.95, 0.85), 0.3, 0.0, 2.4)
	for i: int in 9:
		var a: float = TAU * float(i) / 9.0 + 0.3 * float(i % 2)
		var e: float = 0.35 + 0.35 * float(i % 3) / 2.0
		var p := Vector3(cos(e) * cos(a) * r * 0.97, sin(e) * r * 0.55 * 0.97 - 0.5 * r * 0.55, cos(e) * sin(a) * r * 0.97)
		var sp := Look.sphere(0.09 + 0.05 * float(i % 2), spot, p)
		sp.scale = Vector3(1.0, 0.45, 1.0)
		_cap.add_child(sp)
	# the gills: a glowing frilled underside
	var gill := Look.cylinder(r * 0.95, 0.12, Look.flat(tint.lightened(0.3), 0.4, 0.0, 2.6), Vector3(0, -0.5 * r * 0.55 - 0.02, 0), r * 0.35, 24)
	gill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cap.add_child(gill)
	# strength ring round the top, in the pad colour of the moment
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.emission_enabled = true
	_ring_mat.emission_energy_multiplier = 2.4
	_ring_mat.roughness = 0.3
	var tm := TorusMesh.new()
	tm.inner_radius = radius * 0.55
	tm.outer_radius = radius * 0.66
	tm.rings = 32
	tm.ring_segments = 6
	var ring := Look.mesh_node(tm, _ring_mat, Vector3(0, 0.02, 0))
	ring.scale = Vector3(1, 0.3, 1)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	# stalk + skirt
	if stalk > 0.0:
		var stem_mat: StandardMaterial3D = Look.flat(Color(0.82, 0.76, 0.92), 0.8)
		add_child(Look.cylinder(radius * 0.32, stalk, stem_mat, Vector3(0, -0.6 - stalk * 0.5, 0), radius * 0.22, 12))
		var skirt := Look.cylinder(radius * 0.5, 0.25, Look.flat(tint.lightened(0.45), 0.5, 0.0, 1.2), Vector3(0, -1.3, 0), radius * 0.3, 16)
		skirt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(skirt)
	# the spore-light column: how high it throws you right now
	var dot: StandardMaterial3D = Look.flat(Color(tint.r, tint.g, tint.b, 0.85).lightened(0.3), 0.3, 0.0, 2.2)
	for i: int in LIGHTS:
		var d := Look.sphere(0.1 - 0.05 * float(i) / float(LIGHTS), dot, Vector3(0, 0.9 + float(i) * 0.85, 0))
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(d)
		_lights.append(d)
	# idle: spores drifting up off the cap
	var vis := AABB(Vector3(-5, -2, -5), Vector3(10, 12, 10))
	var idle: GPUParticles3D = Fx.emitter({"amount": 10, "lifetime": 2.6, "shape": "ring", "ring_radius": radius * 0.9,
		"ring_inner": radius * 0.2, "dir": Vector3.UP, "spread": 25.0, "speed": Vector2(0.3, 0.8),
		"gravity": Vector3(0, 0.15, 0), "tex": Fx.Tex.DOT, "size": 0.14, "curve": "pop", "turbulence": 0.8,
		"color": Fx.hot(tint.lightened(0.35), 1.8), "aabb": vis, "preprocess": 2.6, "local": true})
	idle.position = Vector3(0, 0.1, 0)
	add_child(idle)
	# the exhale at the top of each breath: a soft ring of spores rolling off the rim
	_puff = Fx.smoke({"amount": 18, "lifetime": 1.3, "shape": "ring", "ring_radius": radius, "ring_inner": radius * 0.7,
		"dir": Vector3(0, 0.6, 0), "spread": 70.0, "radial_vel": Vector2(1.0, 2.2), "speed": Vector2(0.3, 1.0),
		"damping": Vector2(1.0, 2.0), "size": 0.9, "color": Color(tint.r, tint.g, tint.b, 0.35).lightened(0.4), "aabb": vis})
	_puff.position = Vector3(0, 0.05, 0)
	add_child(_puff)
	# bounce: a burst of glowing spores thrown off the cap
	_burst = Fx.burst({"amount": 30, "lifetime": 0.9, "shape": "ring", "ring_radius": radius * 0.9, "ring_inner": radius * 0.5,
		"dir": Vector3.UP, "spread": 60.0, "speed": Vector2(2.5, 5.5), "gravity": Vector3(0, -2.0, 0),
		"size": 0.2, "color": Fx.hot(tint.lightened(0.3), 2.2), "aabb": vis})
	_burst.position = Vector3(0, 0.1, 0)
	add_child(_burst)
