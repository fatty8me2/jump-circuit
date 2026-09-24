class_name FinishGate
extends Area3D
## The visible destination: a tall glowing arch. Entering it completes the level.

signal reached

@export var width: float = 5.0
@export var gate_height: float = 5.5

var _t: float = 0.0
var _ring: MeshInstance3D
var _done: bool = false
# crossing celebration: lamp / veil / glow flare and a confetti shower (built up front,
# so the moment of finishing never pays for creating a particle system)
var _lamp: OmniLight3D
var _veil_mat: StandardMaterial3D
var _glow: StandardMaterial3D
var _confetti: GPUParticles3D
# fireworks: rockets (world-space trails on moving emitters) that burst into spheres of
# sparks and glitter over the arch, one after another (visual only, all built up front)
var _rockets: Array[GPUParticles3D] = []
var _shells: Array[GPUParticles3D] = []
var _crackles: Array[GPUParticles3D] = []
var _shell_at: Array[Vector3] = []
var _shell_col: Array[Color] = []


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitorable = false
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, gate_height, 2.0)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, gate_height * 0.5, 0)
	add_child(cs)
	body_entered.connect(func(body: Node3D) -> void:
		if body is Player and not _done:
			_done = true
			reached.emit()
			_celebrate())
	# (Look.flat materials are shared: the gate flares its own copy)
	var glow: StandardMaterial3D = Look.flat(Look.c("accent"), 0.3, 0.0, 3.0).duplicate() as StandardMaterial3D
	_glow = glow
	var stone: StandardMaterial3D = Look.flat(Look.c("trim").lerp(Color.WHITE, 0.2), 0.6)
	for sx: int in [-1, 1]:
		add_child(Look.box(Vector3(0.7, gate_height, 0.9), stone, Vector3(sx * (width * 0.5 + 0.35), gate_height * 0.5, 0)))
		add_child(Look.box(Vector3(0.16, gate_height * 0.85, 0.95), glow, Vector3(sx * (width * 0.5 + 0.02), gate_height * 0.47, 0)))
	add_child(Look.box(Vector3(width + 2.2, 0.8, 1.1), stone, Vector3(0, gate_height + 0.4, 0)))
	add_child(Look.box(Vector3(width + 0.1, 0.14, 1.15), glow, Vector3(0, gate_height + 0.02, 0)))
	var tm := TorusMesh.new()
	tm.inner_radius = 0.9
	tm.outer_radius = 1.08
	tm.rings = 40
	tm.ring_segments = 8
	_ring = Look.mesh_node(tm, glow, Vector3(0, gate_height + 2.2, 0))
	_ring.rotation.x = PI / 2.0
	add_child(_ring)
	# sheer light curtain
	var veil_mat := StandardMaterial3D.new()
	veil_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	veil_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	veil_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var ac: Color = Look.c("accent")
	veil_mat.albedo_color = Color(ac.r, ac.g, ac.b, 0.16)
	var qm := QuadMesh.new()
	qm.size = Vector2(width, gate_height)
	var veil := Look.mesh_node(qm, veil_mat, Vector3(0, gate_height * 0.5, 0))
	veil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(veil)
	_veil_mat = veil_mat
	var lamp := OmniLight3D.new()
	lamp.light_color = ac
	lamp.light_energy = 2.5
	lamp.omni_range = 12.0
	lamp.position = Vector3(0, gate_height * 0.6, 0)
	add_child(lamp)
	_lamp = lamp
	_confetti = _make_confetti()
	add_child(_confetti)
	_build_fireworks()
	_build_idle_fx(ac)


## Idle: a slow updraft of glints through the curtain and sparks sifting off the lintel,
## so the goal reads as alive from far away (two small local emitters, visual only).
func _build_idle_fx(ac: Color) -> void:
	var vis := AABB(Vector3(-width, -1.0, -3.0), Vector3(width * 2.0, gate_height + 6.0, 6.0))
	var rise: GPUParticles3D = Fx.embers({"amount": 22, "lifetime": 2.6, "local": true,
		"extents": Vector3(width * 0.45, 0.05, 0.15), "speed": Vector2(1.2, 2.2), "tex": Fx.Tex.STAR,
		"size": 0.26, "curve": "pop", "color": Fx.hot(ac.lerp(Color.WHITE, 0.3), 2.0), "turbulence": 0.4,
		"preprocess": 2.6, "aabb": vis})
	rise.position = Vector3(0, 0.1, 0)
	add_child(rise)
	var sift: GPUParticles3D = Fx.emitter({"amount": 14, "lifetime": 1.6, "local": true, "shape": "box",
		"extents": Vector3(width * 0.5, 0.02, 0.4), "dir": Vector3.DOWN, "spread": 12.0,
		"speed": Vector2(0.4, 1.0), "gravity": Vector3(0, -1.2, 0), "size": 0.12,
		"fade": PackedFloat32Array([0.0, 1.0, 0.0]), "color": Fx.hot(ac, 2.4), "preprocess": 1.6, "aabb": vis})
	sift.position = Vector3(0, gate_height - 0.05, 0)
	add_child(sift)


func _build_fireworks() -> void:
	var cols: Array[Color] = [Look.c("accent"), Look.c("accent2"), Color(1.0, 0.45, 0.65), Color(0.55, 0.9, 1.0)]
	var vis := AABB(Vector3(-width * 2.0 - 8.0, -2.0, -10.0), Vector3(width * 4.0 + 16.0, gate_height + 20.0, 20.0))
	for i: int in 4:
		var sx: float = -1.0 if i % 2 == 0 else 1.0
		_shell_at.append(Vector3(sx * (width * 0.35 + float(i) * 0.9), gate_height + 4.5 + float(i % 3) * 1.4, -1.5 + float(i) * 0.9))
		var hot: Color = Fx.hot(cols[i], 1.7)
		_shell_col.append(cols[i])
		var rocket: GPUParticles3D = Fx.trail({"amount": 30, "lifetime": 0.45, "size": 0.22, "color": hot,
			"speed": Vector2(0.2, 0.8), "dir": Vector3.DOWN, "spread": 20.0, "aabb": vis})
		rocket.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(rocket)
		_rockets.append(rocket)
		var shell: GPUParticles3D = Fx.sparks({"amount": 90, "lifetime": 1.5, "explosiveness": 1.0,
			"spread": 180.0, "speed": Vector2(6.5, 9.5), "damping": Vector2(2.5, 3.0), "gravity": Vector3(0, -3.5, 0),
			"color": hot, "size": Vector2(0.08, 0.5), "curve": "flat",
			"fade": PackedFloat32Array([1.0, 1.0, 0.0]), "aabb": vis})
		shell.position = _shell_at[i]
		add_child(shell)
		_shells.append(shell)
		var crackle: GPUParticles3D = Fx.burst({"amount": 40, "lifetime": 1.2, "explosiveness": 0.5,
			"shape": "sphere", "radius": 3.2, "speed": Vector2(0.0, 0.5), "gravity": Vector3(0, -1.5, 0),
			"tex": Fx.Tex.STAR, "size": 0.34, "curve": "pop", "color": Fx.hot(cols[i].lerp(Color.WHITE, 0.35), 1.8),
			"aabb": vis})
		crackle.position = _shell_at[i]
		add_child(crackle)
		_crackles.append(crackle)


## Four rockets from the pillar tops, launched one after another.
func _fireworks() -> void:
	for i: int in _rockets.size():
		var sx: float = -1.0 if i % 2 == 0 else 1.0
		var r: GPUParticles3D = _rockets[i]
		var from := Vector3(sx * (width * 0.5 + 0.35), gate_height + 0.9, 0.0)
		var tw: Tween = create_tween()
		tw.tween_interval(0.12 + float(i) * 0.32)
		tw.tween_callback(func() -> void:
			r.position = from
			r.emitting = true)
		tw.tween_property(r, "position", _shell_at[i], 0.55).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.tween_callback(func() -> void:
			r.emitting = false
			_shells[i].restart()
			_crackles[i].restart()
			Fx.flash(self, global_transform * _shell_at[i], _shell_col[i], 3.0, 12.0, 0.5))


## Confetti popped under the lintel: the chase camera's frame ends about at the lintel,
## so a low start and a small upward kick keep it in view as it rains through the arch.
func _make_confetti() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 90
	p.lifetime = 2.6
	p.explosiveness = 0.85
	p.position = Vector3(0, gate_height - 0.7, 0)
	p.visibility_aabb = AABB(Vector3(-width, -gate_height - 1.0, -4.0), Vector3(width * 2.0, gate_height + 6.0, 8.0))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(width * 0.5, 0.1, 0.5)
	pm.direction = Vector3.UP
	pm.spread = 80.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 3.5
	pm.gravity = Vector3(0, -5.0, 0)
	pm.damping_min = 1.0
	pm.damping_max = 2.0
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	pm.angular_velocity_min = -360.0
	pm.angular_velocity_max = 360.0
	pm.scale_min = 0.7
	pm.scale_max = 1.2
	# each piece picks one colour from the theme's accents plus pink and white
	var pick := Gradient.new()
	pick.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	pick.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75])
	pick.colors = PackedColorArray([Look.c("accent"), Look.c("accent2"), Color(1.0, 0.45, 0.65), Color.WHITE])
	var pick_tex := GradientTexture1D.new()
	pick_tex.gradient = pick
	pm.color_initial_ramp = pick_tex
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.75, 1.0])
	fade.colors = PackedColorArray([Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
	var fade_tex := GradientTexture1D.new()
	fade_tex.gradient = fade
	pm.color_ramp = fade_tex
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.2, 0.12)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	q.material = m
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## The gate answers the crossing: confetti, and the lamp, veil and glow strips flare
## briefly (the veil stays sheer enough to keep Volt visible through it).
func _celebrate() -> void:
	_confetti.restart()
	_fireworks()
	var tw: Tween = create_tween().set_parallel(true)
	tw.tween_property(_lamp, "light_energy", 7.0, 0.1)    # (brighter blows Volt out to a white blob)
	tw.tween_property(_lamp, "light_energy", 2.5, 0.9).set_delay(0.1).set_ease(Tween.EASE_OUT)
	tw.tween_property(_veil_mat, "albedo_color:a", 0.45, 0.08)
	tw.tween_property(_veil_mat, "albedo_color:a", 0.16, 0.6).set_delay(0.08).set_ease(Tween.EASE_OUT)
	tw.tween_property(_glow, "emission_energy_multiplier", 7.0, 0.1)
	tw.tween_property(_glow, "emission_energy_multiplier", 3.0, 0.9).set_delay(0.1).set_ease(Tween.EASE_OUT)


func _process(dt: float) -> void:
	_t += dt
	_ring.rotation.y = _t * 1.2
	_ring.position.y = gate_height + 2.2 + sin(_t * 1.7) * 0.15
