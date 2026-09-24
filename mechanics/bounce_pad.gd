class_name BouncePad
extends StaticBody3D
## Launch surface with fixed, readable rules:
##  * pitch 0  -> vertical pad: sets vertical speed to `strength`, horizontal momentum is kept.
##  * pitch >0 -> angled pad: replaces velocity with `strength` along the arrow (local -Z tilted up).
## The same pad always produces the same arc. A dotted preview shows that arc,
## chevrons show direction, colour shows strength.

@export var strength: float = 18.0
@export_range(0.0, 75.0) var pitch_deg: float = 0.0
@export var radius: float = 1.1
@export var show_arc: bool = true

const LIP: float = 0.1

var _top: Node3D
var _press: float = 0.0
var _press_vel: float = 0.0
var _surface_tilt: float = 0.0
var _shock: MeshInstance3D
var _shock_mat: StandardMaterial3D
var _shock_tw: Tween
# effects (visual only): a few motes shimmering up off the cushion, a sparkle column
# (along the launch heading on angled pads) on every launch
var _launch_fx: GPUParticles3D


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	# The pad itself stays flat and flush so it can be run onto from any side;
	# direction is communicated by chevrons, the arc dots and a launch hoop.
	_surface_tilt = 0.0
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = 0.4
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.rotation.x = -_surface_tilt
	cs.position = _tilt_basis() * Vector3(0, LIP - 0.2, 0) + Vector3(0, radius * sin(_surface_tilt), 0)
	add_child(cs)
	_build_visual()
	set_process(false)


func _tilt_basis() -> Basis:
	return Basis(Vector3.RIGHT, -_surface_tilt)


static func strength_color(s: float) -> Color:
	var k: float = clampf((s - 12.0) / 22.0, 0.0, 1.0)
	var low := Color(0.0, 0.72, 0.62)
	var mid := Color(1.0, 0.62, 0.05)
	var high := Color(0.95, 0.12, 0.45)
	return low.lerp(mid, k * 2.0) if k < 0.5 else mid.lerp(high, (k - 0.5) * 2.0)


func _build_visual() -> void:
	var col: Color = strength_color(strength)
	var lift := Vector3(0, radius * sin(_surface_tilt), 0)
	# base collar
	add_child(Look.cylinder(radius * 1.08, 0.12, Look.flat(Color(0.16, 0.17, 0.22), 0.5, 0.5), Vector3(0, -0.04, 0)))
	_top = Node3D.new()
	_top.basis = _tilt_basis()
	_top.position = lift
	add_child(_top)
	# spring coils
	for i: int in 2:
		var tm := TorusMesh.new()
		tm.inner_radius = radius * 0.55
		tm.outer_radius = radius * 0.68
		tm.rings = 24
		tm.ring_segments = 8
		var coil := Look.mesh_node(tm, Look.flat(Color(0.7, 0.72, 0.78), 0.3, 0.8), Vector3(0, -0.05 - 0.1 * i, 0))
		coil.scale = Vector3(1, 0.6, 1)
		_top.add_child(coil)
	# cushion
	_top.add_child(Look.cylinder(radius, 0.14, Look.flat(col.darkened(0.35), 0.5), Vector3(0, LIP - 0.07, 0), radius * 0.96, 36))
	_top.add_child(Look.cylinder(radius * 0.84, 0.03, Look.flat(col, 0.4, 0.0, 0.7), Vector3(0, LIP + 0.005, 0), -1.0, 36))
	# chevrons: more chevrons = stronger; they point along the launch heading
	var chevrons: int = 1 + int(clampf((strength - 12.0) / 7.0, 0.0, 2.0))
	var dark := Look.flat(Color(0.1, 0.1, 0.14), 0.6)
	if pitch_deg < 1.0:
		_top.add_child(Look.cylinder(radius * 0.3, 0.035, dark, Vector3(0, LIP + 0.012, 0), -1.0, 24))
		_top.add_child(Look.cylinder(radius * 0.18, 0.04, Look.flat(col, 0.4, 0.0, 2.0), Vector3(0, LIP + 0.016, 0), -1.0, 24))
	else:
		for i: int in chevrons:
			var z: float = (float(i) - float(chevrons - 1) * 0.5) * radius * 0.42
			for side: int in [-1, 1]:
				var bar := Look.box(Vector3(radius * 0.5, 0.035, radius * 0.13), dark, Vector3(side * radius * 0.17, LIP + 0.015, z))
				bar.rotation.y = -side * 0.7
				_top.add_child(bar)
	if pitch_deg >= 1.0:
		_build_hoop(col)
	if show_arc:
		_build_arc(col)
	_build_fx(col)


func _build_fx(col: Color) -> void:
	var hot: Color = Fx.hot(col.lerp(Color.WHITE, 0.3), 2.2)
	var vis := AABB(Vector3(-4, -1, -4), Vector3(8, 10, 8))
	var shimmer: GPUParticles3D = Fx.emitter({"amount": 8, "lifetime": 1.3, "local": true, "shape": "ring",
		"ring_radius": radius * 0.8, "ring_inner": radius * 0.2, "dir": Vector3.UP, "spread": 8.0,
		"speed": Vector2(0.5, 1.2), "tex": Fx.Tex.STAR, "size": 0.32, "curve": "pop", "color": hot,
		"aabb": vis, "preprocess": 1.3})
	shimmer.position = Vector3(0, LIP + 0.05, 0)
	add_child(shimmer)
	# idle: soft rings breathing out of the cushion, "this throws you"
	var ripple: GPUParticles3D = Fx.emitter({"amount": 2, "exact_amount": true, "lifetime": 1.5, "local": true,
		"facing": "flat", "tex": Fx.Tex.RING, "size": 1.0, "speed": Vector2(0.25, 0.25), "dir": Vector3.UP,
		"spread": 0.0, "scale": Vector2(radius * 1.5, radius * 1.5), "curve": "grow",
		"fade": PackedFloat32Array([0.0, 0.55, 0.0]), "color": Fx.hot(col.lerp(Color.WHITE, 0.2), 1.4),
		"aabb": vis, "preprocess": 1.5})
	ripple.position = Vector3(0, LIP + 0.04, 0)
	add_child(ripple)
	var up: Vector3 = _local_launch().normalized() if pitch_deg >= 1.0 else Vector3.UP
	_launch_fx = Fx.sparks({"amount": 26, "lifetime": 0.55, "shape": "ring", "ring_radius": radius * 0.7,
		"ring_inner": radius * 0.3, "dir": Vector3.UP, "spread": 10.0, "speed": Vector2(6.0, 14.0),
		"gravity": Vector3(0, -10, 0), "damping": Vector2(3.0, 6.0), "color": hot,
		"size": Vector2(0.07, 0.6), "aabb": vis})
	_launch_fx.transform = Transform3D(Fx.basis_up(up), Vector3(0, LIP + 0.05, 0))
	add_child(_launch_fx)


func _build_arc(col: Color) -> void:
	var tuning := load("res://resources/default_tuning.tres") as MovementTuning
	var v: Vector3 = _local_launch()
	if pitch_deg < 1.0:
		v = Vector3(0, strength, 0)
	var rise_time: float = v.y / tuning.gravity_rise
	var pts: PackedVector3Array = Ballistics.arc(tuning, Vector3(0, LIP, 0), v, rise_time * (1.0 if pitch_deg < 1.0 else 1.45), 0.07)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var sm := SphereMesh.new()
	sm.radius = 0.14
	sm.height = 0.28
	sm.radial_segments = 8
	sm.rings = 4
	mm.mesh = sm
	var count: int = maxi(pts.size() - 3, 0)
	mm.instance_count = count
	for i: int in count:
		var s: float = 1.0 - 0.6 * float(i) / float(maxi(count, 1))
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * s), pts[i + 3]))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var bright: Color = col.lerp(Color.WHITE, 0.25)
	mat.albedo_color = Color(bright.r, bright.g, bright.b, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.position = Vector3(0, radius * sin(_surface_tilt), 0)
	add_child(mmi)


func _build_hoop(col: Color) -> void:
	var tuning := load("res://resources/default_tuning.tres") as MovementTuning
	var pts: PackedVector3Array = Ballistics.arc(tuning, Vector3(0, LIP, 0), _local_launch(), 0.3, 0.05)
	var at: Vector3 = pts[pts.size() - 2]
	var dir: Vector3 = (pts[pts.size() - 1] - pts[pts.size() - 3]).normalized()
	var tm := TorusMesh.new()
	tm.inner_radius = radius * 1.25
	tm.outer_radius = radius * 1.25 + 0.12
	tm.rings = 40
	tm.ring_segments = 8
	var hoop := Look.mesh_node(tm, Look.flat(col, 0.35, 0.2, 2.2), at)
	var side: Vector3 = dir.cross(Vector3.RIGHT).normalized()
	hoop.basis = Basis(Vector3.RIGHT, dir, -side).orthonormalized()
	hoop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(hoop)
	# slim struts holding the hoop so it reads as part of the pad
	for sx: int in [-1, 1]:
		var foot := Vector3(sx * radius * 1.05, 0.0, 0.0)
		var top: Vector3 = at + Vector3(sx * radius * 1.3, 0, 0)
		var strut := Look.cylinder(0.05, foot.distance_to(top), Look.flat(Color(0.16, 0.17, 0.22), 0.5, 0.5), (foot + top) * 0.5, -1.0, 8)
		var up: Vector3 = (top - foot).normalized()
		var sd: Vector3 = up.cross(Vector3.RIGHT).normalized()
		strut.basis = Basis(sd.cross(up), up, sd).orthonormalized()
		add_child(strut)


func _local_launch() -> Vector3:
	var p: float = deg_to_rad(pitch_deg)
	return Vector3(0, cos(p), -sin(p)) * strength


# ---- contract used by Player -------------------------------------------------

func get_surface_up() -> Vector3:
	return (global_basis * _tilt_basis()).y.normalized()


func get_launch() -> Dictionary:
	return {
		"velocity": global_basis.orthonormalized() * _local_launch(),
		"keep_horizontal": pitch_deg < 1.0,
	}


func launch_origin() -> Vector3:
	return global_position + Vector3(0, LIP + radius * sin(_surface_tilt), 0)


func on_bounced(_player: Node) -> void:
	_press = -0.06
	_press_vel = 3.2
	set_process(true)
	# shockwave ring in the strength colour: keeps the launch point readable
	var ring: MeshInstance3D = _shock_ring()
	if _shock_tw != null:
		_shock_tw.kill()
	ring.visible = true
	ring.scale = Vector3(1.0, 0.3, 1.0)
	_shock_mat.albedo_color.a = 0.9
	_shock_tw = create_tween().set_parallel(true)
	_shock_tw.tween_property(ring, "scale", Vector3(2.4, 0.3, 2.4), 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_shock_tw.tween_property(_shock_mat, "albedo_color:a", 0.0, 0.3)
	_shock_tw.chain().tween_callback(ring.hide)
	if _launch_fx != null:
		_launch_fx.restart()


## Built on first use. Own material (Look.flat is shared per colour, and the
## fade animates alpha); parented to the pad so it doesn't bob with the cushion.
func _shock_ring() -> MeshInstance3D:
	if _shock == null:
		var tm := TorusMesh.new()
		tm.inner_radius = radius * 0.8
		tm.outer_radius = radius * 0.95
		tm.rings = 36
		tm.ring_segments = 6
		_shock_mat = StandardMaterial3D.new()
		_shock_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_shock_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_shock_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_shock_mat.albedo_color = strength_color(strength).lerp(Color.WHITE, 0.25)
		_shock = Look.mesh_node(tm, _shock_mat, Vector3(0, LIP + 0.03 + radius * sin(_surface_tilt), 0))
		_shock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_shock.layers = 2      # keeps the blob shadow decal (cull_mask 1) off it
		add_child(_shock)
	return _shock


func _process(dt: float) -> void:
	# spring-back of the cushion
	var acc: float = -_press * 420.0 - _press_vel * 16.0
	_press_vel += acc * dt
	_press += _press_vel * dt
	_top.position = Vector3(0, radius * sin(_surface_tilt), 0) + _tilt_basis().y * _press
	if absf(_press) < 0.002 and absf(_press_vel) < 0.02:
		_press = 0.0
		_top.position = Vector3(0, radius * sin(_surface_tilt), 0)
		set_process(false)
