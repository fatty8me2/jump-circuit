class_name ReefVent
extends Node3D
## Coral Depths: a hydrothermal vent that ERUPTS on a fixed rhythm (Game.course_time).
## While erupting, its bubble column is a strong updraft (like WindZone) that carries you
## up past the ledges around it; while quiet it is just a warm glowing crater you can
## stand next to. For `warn` seconds before an eruption the crater rumbles: its glow
## flares and a skirt of sand and small bubbles puffs out - step in then.
## Positioned at the floor point at the base (centre) of the column.

@export var size: Vector3 = Vector3(2.4, 9.0, 2.4)
## Upward acceleration while erupting (gravity is 30 rising / 42 falling).
@export var push: float = 80.0
## Vertical speed the column will not push past.
@export var max_rise: float = 12.0
@export var period: float = 4.0
@export var on_fraction: float = 0.5
@export var phase: float = 0.0
@export var warn: float = 0.7

var _area: Area3D
var _plume: GPUParticles3D
var _rumble: GPUParticles3D
var _core: GPUParticles3D
var _glow_mat: StandardMaterial3D
var _light: OmniLight3D


func _ready() -> void:
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 2
	_area.monitorable = false
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	_area.add_child(cs)
	_area.position = Vector3(0, size.y * 0.5, 0)
	add_child(_area)
	_build_visual()
	_apply(Game.course_time)


func is_erupting_at(time: float) -> bool:
	return fposmod(time / period + phase, 1.0) < on_fraction


## Seconds until the next eruption starts (0 while erupting).
func time_until_eruption(time: float) -> float:
	var u: float = fposmod(time / period + phase, 1.0)
	return 0.0 if u < on_fraction else (1.0 - u) * period


## Seconds of eruption left (0 while quiet).
func eruption_left(time: float) -> float:
	var u: float = fposmod(time / period + phase, 1.0)
	return (on_fraction - u) * period if u < on_fraction else 0.0


func _physics_process(dt: float) -> void:
	var t: float = Game.course_time
	_apply(t)
	if not is_erupting_at(t):
		return
	for body: Node3D in _area.get_overlapping_bodies():
		if body is Player:
			var p := body as Player
			var dv := Vector3(0, push * dt, 0)
			if p.velocity.y > max_rise:
				dv.y = 0.0
			p.add_impulse(dv)


func _apply(t: float) -> void:
	var on: bool = is_erupting_at(t)
	var until: float = time_until_eruption(t)
	var warning: bool = not on and until < warn
	if _plume.emitting != on:
		_plume.emitting = on
	if _rumble.emitting != warning:
		_rumble.emitting = warning
	var glow: float = 0.8
	if on:
		glow = 3.5
	elif warning:
		glow = 1.2 + 2.0 * (1.0 - until / warn) * (0.75 + 0.25 * sin(t * 40.0))
	if not is_equal_approx(_glow_mat.emission_energy_multiplier, glow):
		_glow_mat.emission_energy_multiplier = glow
		_light.light_energy = glow * 0.7


func _build_visual() -> void:
	var r: float = minf(size.x, size.z) * 0.5
	var rock: StandardMaterial3D = Look.flat(Color(0.16, 0.14, 0.16), 0.9)
	# rocky chimney collar (decor, no collision - the floor around it is the level's)
	add_child(Look.cylinder(r * 1.05, 0.7, rock, Vector3(0, 0.12, 0), r * 0.8, 16))
	for i: int in 7:
		var a: float = TAU * float(i) / 7.0
		var lump := Look.sphere(0.35 + 0.1 * float(i % 3), rock, Vector3(cos(a) * r * 1.0, 0.2, sin(a) * r * 1.0))
		lump.scale = Vector3(1.0, 0.7, 1.0)
		add_child(lump)
	_glow_mat = Look.flat(Color(1.0, 0.62, 0.25), 0.4, 0.0, 0.8).duplicate() as StandardMaterial3D
	add_child(Look.cylinder(r * 0.62, 0.08, _glow_mat, Vector3(0, 0.48, 0), -1.0, 16))
	# grate bars so the mouth reads as "stand here"
	var bar: StandardMaterial3D = Look.flat(Color(0.1, 0.1, 0.12), 0.5, 0.6)
	for k: int in 3:
		add_child(Look.box(Vector3(r * 1.3, 0.06, 0.1), bar, Vector3(0, 0.53, (float(k) - 1.0) * r * 0.35)))
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.7, 0.4)
	_light.omni_range = 7.0
	_light.light_energy = 0.6
	_light.position = Vector3(0, 1.0, 0)
	add_child(_light)
	# eruption: a dense column of bubbles racing up through the updraft
	_plume = GPUParticles3D.new()
	_plume.amount = Fx.count(90)
	_plume.lifetime = size.y / 11.0 + 0.6
	_plume.local_coords = false
	_plume.visibility_aabb = AABB(Vector3(-4, -1, -4), Vector3(8, size.y + 6, 8))
	_plume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = r * 0.55
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 6.0
	pm.initial_velocity_min = 9.0
	pm.initial_velocity_max = 13.0
	pm.gravity = Vector3(0, 1.0, 0)
	pm.damping_min = 0.5
	pm.damping_max = 1.2
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.2
	pm.turbulence_noise_scale = 2.5
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.12
	pm.scale_min = 0.5
	pm.scale_max = 1.6
	pm.color_ramp = ReefFx.fade_ramp(Color(0.9, 1.0, 1.0), 0.95)
	_plume.process_material = pm
	_plume.draw_pass_1 = ReefFx.bubble_quad(0.34)
	_plume.position = Vector3(0, 0.5, 0)
	add_child(_plume)
	# warning rumble: sand skirt + small bubbles spilling out of the crater
	_rumble = GPUParticles3D.new()
	_rumble.amount = Fx.count(26)
	_rumble.lifetime = 0.8
	_rumble.local_coords = false
	_rumble.visibility_aabb = AABB(Vector3(-4, -1, -4), Vector3(8, 5, 8))
	var rm := ParticleProcessMaterial.new()
	rm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	rm.emission_ring_axis = Vector3.UP
	rm.emission_ring_radius = r * 0.7
	rm.emission_ring_inner_radius = r * 0.3
	rm.emission_ring_height = 0.1
	rm.direction = Vector3(0, 1, 0)
	rm.spread = 50.0
	rm.initial_velocity_min = 1.5
	rm.initial_velocity_max = 3.0
	rm.gravity = Vector3(0, -2.0, 0)
	rm.scale_min = 0.8
	rm.scale_max = 1.6
	rm.color_ramp = ReefFx.fade_ramp(Color(0.95, 0.85, 0.65), 0.7)
	_rumble.process_material = rm
	_rumble.draw_pass_1 = ReefFx.dot_quad(0.4, false)
	_rumble.position = Vector3(0, 0.5, 0)
	add_child(_rumble)
	# always: a lazy trickle and warm shimmer
	var trickle: GPUParticles3D = ReefFx.bubble_stream(size.y * 0.8, 8, r * 0.4, 0.2)
	trickle.position = Vector3(0, 0.5, 0)
	add_child(trickle)
	var shimmer: GPUParticles3D = ReefFx.vent_glow(Color(1.0, 0.65, 0.3), 10)
	shimmer.position = Vector3(0, 0.6, 0)
	add_child(shimmer)
