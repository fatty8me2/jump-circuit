class_name OrbitalGravityBay
extends Area3D
## ORBITAL DRIFT - LOW-G BAY. A box where the station's gravity plating is turned
## down: while you are airborne inside it, `lift` m/s^2 of gravity is cancelled
## (30/42 -> ~16/28), so jumps float high and long (a full jump flies ~12 m).
## Standing, running and jumping off the floor work exactly as normal - only the
## flight changes - so a bay never traps you the way an updraft would.
## With `period` > 0 the field PULSES on the course clock: violet and humming
## while on, its frame flickers for `warn` s before it cuts out (and a jump that
## needed it drops like a stone). Deterministic, identical for every racer.

const FIELD_COLOR: Color = Color(0.72, 0.45, 1.0)

@export var size: Vector3 = Vector3(10, 8, 20)
## Gravity cancelled while airborne inside (m/s^2).
@export var lift: float = 14.0
## 0 = always on; otherwise the on/off cycle length (s).
@export var period: float = 0.0
@export var on_fraction: float = 0.6
@export var phase: float = 0.0
@export var warn: float = 0.6

var _frame_mat: StandardMaterial3D
var _mote_mat: StandardMaterial3D
var _sheet_mat: StandardMaterial3D
var _was_on: bool = true


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitorable = false
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	add_child(cs)
	_build_visual()
	_apply_visual(Game.course_time)


func is_on_at(time: float) -> bool:
	return period <= 0.0 or fposmod(time / period + phase, 1.0) < on_fraction


## Seconds the field stays on from `time` (INF for an always-on bay, 0 while off).
func time_until_off(time: float) -> float:
	if period <= 0.0:
		return INF
	var u: float = fposmod(time / period + phase, 1.0)
	return (on_fraction - u) * period if u < on_fraction else 0.0


func time_until_on(time: float) -> float:
	if period <= 0.0:
		return 0.0
	var u: float = fposmod(time / period + phase, 1.0)
	return 0.0 if u < on_fraction else (1.0 - u) * period


func _physics_process(dt: float) -> void:
	var t: float = Game.course_time
	_apply_visual(t)
	if not is_on_at(t):
		return
	for body: Node3D in get_overlapping_bodies():
		if body is Player:
			var p := body as Player
			if p.grounded or p.is_wall_running() or p.is_mantling():
				continue
			p.velocity.y += lift * dt


# ---- look -------------------------------------------------------------------------------------

func _build_visual() -> void:
	var h: Vector3 = size * 0.5
	_frame_mat = StandardMaterial3D.new()
	_frame_mat.albedo_color = FIELD_COLOR
	_frame_mat.emission_enabled = true
	_frame_mat.emission = FIELD_COLOR
	_frame_mat.emission_energy_multiplier = 2.6
	# the 4 vertical edges and the top rectangle: the bay's outline
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_bar(Vector3(0.09, size.y, 0.09), Vector3(sx * h.x, 0, sz * h.z))
			# emitter pod at each floor corner
			var pod := Look.sphere(0.22, _frame_mat, Vector3(sx * h.x, -h.y + 0.25, sz * h.z))
			pod.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(pod)
	for sx: float in [-1.0, 1.0]:
		_bar(Vector3(0.07, 0.07, size.z), Vector3(sx * h.x, h.y, 0))
	for sz: float in [-1.0, 1.0]:
		_bar(Vector3(size.x, 0.07, 0.07), Vector3(0, h.y, sz * h.z))
	# faint side sheets so the volume reads from inside and out
	_sheet_mat = StandardMaterial3D.new()
	_sheet_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_sheet_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_sheet_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_sheet_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_sheet_mat.albedo_color = Color(FIELD_COLOR.r, FIELD_COLOR.g, FIELD_COLOR.b, 0.05)
	_sheet_mat.albedo_texture = _sheet_texture()
	for sx: float in [-1.0, 1.0]:
		var q := QuadMesh.new()
		q.size = Vector2(size.z, size.y)
		var mi := Look.mesh_node(q, _sheet_mat, Vector3(sx * h.x, 0, 0))
		mi.rotation.y = PI * 0.5
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	# motes drifting slowly UP through the bay: the tell of low gravity
	var p := GPUParticles3D.new()
	p.amount = int(clampf(size.x * size.z * 0.12, 24, 110))
	p.lifetime = 5.0
	p.preprocess = 5.0
	p.local_coords = true
	p.visibility_aabb = AABB(-h - Vector3.ONE, size + Vector3.ONE * 2.0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(h.x * 0.95, h.y * 0.9, h.z * 0.95)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 0.9
	pm.gravity = Vector3(0, 0.12, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.25, 0.75, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.16, 0.16)
	_mote_mat = StandardMaterial3D.new()
	_mote_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mote_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mote_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mote_mat.vertex_color_use_as_albedo = true
	_mote_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_mote_mat.albedo_color = FIELD_COLOR.lightened(0.3)
	_mote_mat.albedo_texture = _dot()
	quad.material = _mote_mat
	p.draw_pass_1 = quad
	add_child(p)


func _bar(sz: Vector3, pos: Vector3) -> void:
	var b := Look.box(sz, _frame_mat, pos)
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(b)


func _apply_visual(t: float) -> void:
	var on: bool = is_on_at(t)
	var k: float = 1.0
	if not on:
		k = 0.12
	else:
		var left: float = time_until_off(t)
		if left < warn:
			k = 1.0 if fmod(left, 0.14) > 0.07 else 0.25
	if on != _was_on or period > 0.0:
		_was_on = on
		_frame_mat.emission_energy_multiplier = 0.15 + 2.45 * k
		_mote_mat.albedo_color = Color(0.9, 0.75, 1.0, k)
		_sheet_mat.albedo_color = Color(FIELD_COLOR.r, FIELD_COLOR.g, FIELD_COLOR.b, 0.05 * k)


static var _dot_tex: GradientTexture2D
static var _sheet_tex: GradientTexture2D


static func _dot() -> GradientTexture2D:
	if _dot_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		_dot_tex = GradientTexture2D.new()
		_dot_tex.gradient = g
		_dot_tex.fill = GradientTexture2D.FILL_RADIAL
		_dot_tex.fill_from = Vector2(0.5, 0.5)
		_dot_tex.fill_to = Vector2(0.5, 0.0)
	return _dot_tex


## Vertical fade: bright at the floor, gone at the top (a field rising off the plating).
static func _sheet_texture() -> GradientTexture2D:
	if _sheet_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 0))
		g.set_color(1, Color(1, 1, 1, 1))
		_sheet_tex = GradientTexture2D.new()
		_sheet_tex.gradient = g
		_sheet_tex.fill_from = Vector2(0.5, 0.0)
		_sheet_tex.fill_to = Vector2(0.5, 1.0)
	return _sheet_tex
