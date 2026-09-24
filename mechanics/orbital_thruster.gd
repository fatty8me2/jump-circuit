class_name OrbitalThruster
extends Node3D
## ORBITAL DRIFT - RCS THRUSTER. A station attitude jet that fires on a fixed
## rhythm (Game.course_time). Its plume (a box along the nozzle's local +Y) pushes
## a player inside it along the thrust while it burns: pointed up under a grate it
## is a timed lift that hurls you to the next deck; pointed sideways across a gap
## it is a blast that shoves a jumper off line. It coughs and sputters for `warn`
## seconds before every burn, so the rhythm is readable. No kill, only push.

@export var length: float = 8.0
@export var width: float = 2.4
## Acceleration along the thrust while burning (m/s^2; gravity is 30 up / 42 down).
@export var push: float = 80.0
## Speed along the thrust the plume will not push past.
@export var max_along: float = 16.0
@export var period: float = 3.0
## Fraction of the cycle it burns (burn starts at u = 0).
@export var on_fraction: float = 0.35
@export var phase: float = 0.0
@export var warn: float = 0.5
@export var nozzle_radius: float = 0.8

var _area: Area3D
var _plume: GPUParticles3D
var _core: GPUParticles3D
var _cough: GPUParticles3D
var _throat_mat: StandardMaterial3D
var _light: OmniLight3D
var _firing: bool = false


func _ready() -> void:
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 2
	_area.monitorable = false
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, length, width)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	_area.add_child(cs)
	_area.position = Vector3(0, length * 0.5, 0)
	add_child(_area)
	_build_visual()
	_apply(Game.course_time)


func is_firing_at(time: float) -> bool:
	return fposmod(time / period + phase, 1.0) < on_fraction


## Seconds until the next burn starts (0 while burning).
func time_until_fire(time: float) -> float:
	var u: float = fposmod(time / period + phase, 1.0)
	return 0.0 if u < on_fraction else (1.0 - u) * period


## Seconds until the current burn ends (0 while idle).
func time_until_stop(time: float) -> float:
	var u: float = fposmod(time / period + phase, 1.0)
	return (on_fraction - u) * period if u < on_fraction else 0.0


func _physics_process(dt: float) -> void:
	var t: float = Game.course_time
	_apply(t)
	if not _firing:
		return
	var dir: Vector3 = global_basis.y.normalized()
	for body: Node3D in _area.get_overlapping_bodies():
		if body is Player:
			var p := body as Player
			if p.velocity.dot(dir) < max_along:
				p.add_impulse(dir * push * dt)


func _apply(t: float) -> void:
	var on: bool = is_firing_at(t)
	var until: float = time_until_fire(t)
	var coughing: bool = not on and until < warn
	if on != _firing:
		_firing = on
		_plume.emitting = on
		_core.emitting = on
	if _cough.emitting != coughing:
		_cough.emitting = coughing
	var glow: float = 5.0 if on else (2.0 if coughing and fmod(until, 0.12) > 0.06 else 0.5)
	if not is_equal_approx(_throat_mat.emission_energy_multiplier, glow):
		_throat_mat.emission_energy_multiplier = glow
	_light.light_energy = (2.2 + sin(t * 53.0) * 0.4) if on else 0.0


# ---- look -------------------------------------------------------------------------------------

func _build_visual() -> void:
	var metal: StandardMaterial3D = Look.flat(Color(0.30, 0.31, 0.35), 0.35, 0.85)
	var dark: StandardMaterial3D = Look.flat(Color(0.12, 0.12, 0.14), 0.5, 0.6)
	# bell: narrow throat at the base, flaring toward the thrust
	add_child(Look.cylinder(nozzle_radius * 0.45, nozzle_radius * 1.3, metal, Vector3(0, -nozzle_radius * 0.65, 0), nozzle_radius, 20))
	add_child(Look.cylinder(nozzle_radius * 0.55, nozzle_radius * 0.5, dark, Vector3(0, -nozzle_radius * 1.5, 0), nozzle_radius * 0.5, 16))
	_throat_mat = StandardMaterial3D.new()
	_throat_mat.albedo_color = Color(1.0, 0.55, 0.2)
	_throat_mat.emission_enabled = true
	_throat_mat.emission = Color(1.0, 0.5, 0.15)
	_throat_mat.emission_energy_multiplier = 0.5
	add_child(Look.cylinder(nozzle_radius * 0.85, 0.06, _throat_mat, Vector3(0, -0.05, 0), -1.0, 20))
	# hazard ring round the lip
	var lip := TorusMesh.new()
	lip.inner_radius = nozzle_radius * 0.95
	lip.outer_radius = nozzle_radius * 1.1
	lip.rings = 24
	lip.ring_segments = 6
	add_child(Look.mesh_node(lip, Look.flat(Color(1.0, 0.72, 0.1), 0.5, 0.1, 0.8), Vector3(0, 0.02, 0)))
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.7, 0.45)
	_light.omni_range = maxf(length * 0.8, 6.0)
	_light.light_energy = 0.0
	_light.position = Vector3(0, 1.2, 0)
	add_child(_light)
	var speed: float = length / 0.55
	_plume = _jet(90, 0.55, speed * 0.85, speed, 14.0, Vector2(0.7, 0.7), 1.0, 3.2,
			[Color(1.0, 1.0, 1.0, 0.0), Color(0.75, 0.9, 1.0, 0.9), Color(1.0, 0.62, 0.28, 0.55), Color(0.5, 0.3, 0.3, 0.0)])
	_core = _jet(40, 0.3, speed * 0.9, speed * 1.1, 4.0, Vector2(0.45, 0.45), 1.0, 1.6,
			[Color(1, 1, 1, 0.0), Color(0.85, 0.95, 1.0, 1.0), Color(0.6, 0.8, 1.0, 0.6), Color(0.4, 0.6, 1.0, 0.0)])
	_cough = _jet(10, 0.35, 2.0, 4.0, 30.0, Vector2(0.5, 0.5), 0.8, 2.4,
			[Color(1, 1, 1, 0.0), Color(0.85, 0.85, 0.9, 0.5), Color(0.6, 0.6, 0.65, 0.25), Color(0.5, 0.5, 0.55, 0.0)])


func _jet(amount: int, lifetime: float, v_min: float, v_max: float, spread: float, quad: Vector2, s0: float, s1: float, ramp: Array) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = Fx.count(amount)
	p.lifetime = lifetime
	p.emitting = false
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-length, -2.0, -length), Vector3(length * 2.0, length * 1.6 + 4.0, length * 2.0))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = nozzle_radius * 0.45
	pm.direction = Vector3(0, 1, 0)
	pm.spread = spread
	pm.initial_velocity_min = v_min
	pm.initial_velocity_max = v_max
	pm.gravity = Vector3.ZERO
	pm.damping_min = 1.0
	pm.damping_max = 3.0
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, s0 / s1))
	sc.add_point(Vector2(1.0, 1.0))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	pm.scale_min = s1 * 0.8
	pm.scale_max = s1
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.1, 0.55, 1.0])
	g.colors = PackedColorArray(ramp)
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = quad
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_texture = OrbitalGravityBay._dot()
	q.material = m
	p.draw_pass_1 = q
	add_child(p)
	return p
