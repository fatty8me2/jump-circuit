class_name ReefJelly
extends AnimatableBody3D
## Coral Depths: a jellyfish that is a bounce pad. Its bell is a vertical pad (sets your
## vertical speed to `strength`, KEEPS your horizontal momentum - sprint onto it), and it can
## drift along `points` (offsets, eased ping-pong like MovingPlatform) and bob up and down,
## all a pure function of Game.course_time. The glowing ring on the bell is in the pad
## strength colour, so it reads like every other pad in the game.
## Positioned by the centre of the TOP of its bell.

@export var strength: float = 17.0
@export var radius: float = 1.2
## Drift path (offsets from the start position). Fewer than two = no drift.
@export var points: Array[Vector3] = []
@export var period: float = 5.0
@export var phase: float = 0.0
## Vertical bob (m) and its period (s).
@export var bob: float = 0.0
@export var bob_period: float = 3.0
@export var tint: Color = Color(1.0, 0.45, 0.8)

const DWELL: float = 0.1

var _origin: Vector3
var _bell: Node3D
var _t: float = 0.0
var _squash: float = 0.0
var _burst: GPUParticles3D
var _bell_mat: StandardMaterial3D


func _ready() -> void:
	sync_to_physics = false
	collision_layer = 1
	collision_mask = 0
	_origin = position
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = 0.5
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, -0.25, 0)
	add_child(cs)
	_build_visual()
	position = _origin + offset_at(Game.course_time)
	reset_physics_interpolation()
	add_to_group("course_clock")


func snap_to_clock() -> void:
	position = _origin + offset_at(Game.course_time)
	reset_physics_interpolation()


func offset_at(time: float) -> Vector3:
	var off := Vector3.ZERO
	if points.size() >= 2:
		var u: float = fposmod(time / maxf(period, 0.01) + phase, 1.0)
		var legs: int = points.size() - 1
		var tri: float = 1.0 - absf(u * 2.0 - 1.0)
		var f: float = tri * float(legs)
		var leg: int = mini(int(f), legs - 1)
		var k: float = clampf((f - float(leg) - DWELL) / (1.0 - 2.0 * DWELL), 0.0, 1.0)
		k = k * k * (3.0 - 2.0 * k)
		off = points[leg].lerp(points[leg + 1], k)
	if bob > 0.0:
		off.y += bob * sin(TAU * (time / bob_period + phase))
	return off


func _physics_process(_dt: float) -> void:
	position = _origin + offset_at(Game.course_time)


# ---- pad contract (duck-typed by Player._scan_collisions) -----------------------------

func get_surface_up() -> Vector3:
	return Vector3.UP


func get_launch() -> Dictionary:
	return {"velocity": Vector3(0, strength, 0), "keep_horizontal": true}


func launch_origin() -> Vector3:
	return global_position + Vector3(0, 0.05, 0)


func on_bounced(_player: Node) -> void:
	_squash = 1.0
	if _burst != null:
		_burst.restart()
		_burst.emitting = true


# ---- visuals ------------------------------------------------------------------------------

func _process(dt: float) -> void:
	_t += dt
	_squash = maxf(_squash - dt * 3.2, 0.0)
	var pulse: float = sin(_t * 2.6 + phase * 10.0)
	var sq: float = _squash * _squash
	_bell.scale = Vector3(1.0 + 0.05 * pulse + 0.22 * sq, 1.0 - 0.08 * pulse - 0.45 * sq, 1.0 + 0.05 * pulse + 0.22 * sq)
	_bell_mat.emission_energy_multiplier = 1.1 + 0.5 * maxf(pulse, 0.0) + 3.0 * sq


func _build_visual() -> void:
	var ring_col: Color = BouncePad.strength_color(strength)
	_bell = Node3D.new()
	add_child(_bell)
	# translucent glowing bell: a flattened dome whose crown is flush with the collision top
	_bell_mat = StandardMaterial3D.new()
	_bell_mat.albedo_color = Color(tint.r, tint.g, tint.b, 0.55)
	_bell_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_bell_mat.emission_enabled = true
	_bell_mat.emission = tint
	_bell_mat.emission_energy_multiplier = 1.2
	_bell_mat.roughness = 0.2
	_bell_mat.rim_enabled = true
	_bell_mat.rim = 0.8
	_bell_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var dome := SphereMesh.new()
	dome.radius = radius * 1.05
	dome.height = radius * 2.1
	dome.radial_segments = 28
	dome.rings = 10
	var bell := Look.mesh_node(dome, _bell_mat, Vector3(0, -0.4, 0))
	bell.scale = Vector3(1, 0.44 / (radius * 1.05), 1)
	bell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bell.add_child(bell)
	# frilled skirt under the bell
	var skirt := Look.cylinder(radius * 1.05, 0.5, _bell_mat, Vector3(0, -0.6, 0), radius * 0.8, 28)
	skirt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bell.add_child(skirt)
	# strength ring (the pad colour) and a bright crown dot
	var tm := TorusMesh.new()
	tm.inner_radius = radius * 0.62
	tm.outer_radius = radius * 0.74
	tm.rings = 32
	tm.ring_segments = 6
	var ring := Look.mesh_node(tm, Look.flat(ring_col, 0.3, 0.0, 2.6), Vector3(0, -0.02, 0))
	ring.scale = Vector3(1, 0.3, 1)
	_bell.add_child(ring)
	_bell.add_child(Look.cylinder(radius * 0.22, 0.04, Look.flat(ring_col.lightened(0.3), 0.3, 0.0, 3.0), Vector3(0, 0.0, 0), -1.0, 16))
	# oral arms + trailing tentacles (swaying ribbons)
	var arm_mat: StandardMaterial3D = Look.flat(Color(tint.r, tint.g, tint.b, 0.6), 0.3, 0.0, 1.6)
	for i: int in 4:
		var a: float = TAU * float(i) / 4.0 + 0.4
		var arm := Look.cylinder(0.09, 2.2, arm_mat, Vector3(cos(a) * radius * 0.25, -1.8, sin(a) * radius * 0.25), 0.03, 6)
		arm.rotation = Vector3(sin(a) * 0.12, 0, cos(a) * 0.12)
		arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(arm)
	var ten_mat: StandardMaterial3D = Look.flat(tint.lightened(0.35), 0.3, 0.0, 2.2)
	for i: int in 10:
		var a2: float = TAU * float(i) / 10.0
		var tl: float = 2.4 + 1.4 * fposmod(float(i) * 0.618, 1.0)
		var holder := Node3D.new()
		holder.position = Vector3(cos(a2) * radius * 0.9, -0.8, sin(a2) * radius * 0.9)
		holder.set_script(preload("res://visual/reef_sway.gd"))
		holder.set("amount", 0.14)
		holder.set("speed", 1.3 + 0.2 * float(i % 3))
		holder.set("offset", float(i))
		var ten := Look.cylinder(0.025, tl, ten_mat, Vector3(0, -tl * 0.5, 0), 0.012, 4)
		ten.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(ten)
		add_child(holder)
	# glowing plankton dots marking the bounce column (like a pad's arc preview)
	var h: float = strength * strength / 60.0
	var dot_mat: StandardMaterial3D = Look.flat(Color(ring_col.r, ring_col.g, ring_col.b, 0.8), 0.3, 0.0, 2.0)
	var n: int = int(h / 1.1)
	for i: int in n:
		var d := Look.sphere(0.09 - 0.05 * float(i) / float(maxi(n, 1)), dot_mat, Vector3(0, 1.0 + float(i) * 1.1, 0))
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_bell.add_child(d)
	# shed motes: glowing specks drifting off the tentacles (world space so they trail a drifting jelly)
	var motes := GPUParticles3D.new()
	motes.amount = Fx.count(10)
	motes.lifetime = 2.8
	motes.preprocess = 2.8
	motes.local_coords = false
	motes.visibility_aabb = AABB(Vector3(-6, -8, -6), Vector3(12, 12, 12))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = radius * 0.9
	pm.emission_ring_inner_radius = radius * 0.3
	pm.emission_ring_height = 2.5
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 30.0
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.4
	pm.gravity = Vector3(0, -0.1, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	pm.color_ramp = ReefFx.fade_ramp(tint.lightened(0.4))
	motes.process_material = pm
	motes.draw_pass_1 = ReefFx.dot_quad(0.12, true)
	motes.position = Vector3(0, -1.6, 0)
	add_child(motes)
	# bounce burst: a ring of bubbles and sparks thrown off the bell
	_burst = GPUParticles3D.new()
	_burst.emitting = false
	_burst.one_shot = true
	_burst.amount = Fx.count(28)
	_burst.lifetime = 0.9
	_burst.explosiveness = 0.95
	_burst.local_coords = false
	_burst.visibility_aabb = AABB(Vector3(-6, -3, -6), Vector3(12, 10, 12))
	var bm := ParticleProcessMaterial.new()
	bm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	bm.emission_ring_axis = Vector3.UP
	bm.emission_ring_radius = radius
	bm.emission_ring_inner_radius = radius * 0.7
	bm.emission_ring_height = 0.1
	bm.direction = Vector3(0, 1, 0)
	bm.spread = 70.0
	bm.initial_velocity_min = 2.0
	bm.initial_velocity_max = 4.5
	bm.gravity = Vector3(0, 1.5, 0)
	bm.damping_min = 2.5
	bm.damping_max = 4.0
	bm.scale_min = 0.5
	bm.scale_max = 1.3
	bm.color_ramp = ReefFx.fade_ramp(ring_col.lerp(Color.WHITE, 0.4))
	_burst.process_material = bm
	_burst.draw_pass_1 = ReefFx.bubble_quad(0.28)
	add_child(_burst)
