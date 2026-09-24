class_name Checkpoint
extends Area3D
## Touch to bank progress. Respawns face `-Z` of this node (rotate the node to aim
## the player at the next challenge).

signal reached(cp: Checkpoint)

@export var index: int = 0
@export var radius: float = 2.2

var active: bool = false
var _ring_mat: StandardMaterial3D
var _orb: MeshInstance3D
var _orb_mat: StandardMaterial3D
var _t: float = 0.0
## Ring flare after a celebrated activation (killed by any later set_active).
var _flare_tw: Tween
## One-shot spark ring rising off the floor ring; built with the checkpoint (inside the level
## load, not as a hitch on the first touch) and restarted on every celebration.
var _burst: GPUParticles3D
# effects (visual only): a fountain of sparks and glitter off the orb on activation,
# and a gentle column of motes inside the ring while it is the live checkpoint
var _fountain: GPUParticles3D
var _glitter: GPUParticles3D
var _motes: GPUParticles3D
var _wave: GPUParticles3D
var _halo: MeshInstance3D          # soft glow around the orb: a faint beacon, bright once live
var _halo_mat: StandardMaterial3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitorable = false
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = 3.0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, 1.5, 0)
	add_child(cs)
	body_entered.connect(func(body: Node3D) -> void:
		if body is Player:
			reached.emit(self))
	# visuals: floor ring + two slim pylons with a floating orb between them
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.albedo_color = Color(0.2, 0.22, 0.28)
	_ring_mat.emission_enabled = true
	_ring_mat.emission = Look.c("accent")
	_ring_mat.emission_energy_multiplier = 0.15
	var tm := TorusMesh.new()
	tm.inner_radius = radius * 0.78
	tm.outer_radius = radius * 0.86
	tm.rings = 48
	tm.ring_segments = 6
	var ring := Look.mesh_node(tm, _ring_mat, Vector3(0, 0.03, 0))
	ring.scale = Vector3(1, 0.25, 1)
	add_child(ring)
	var pole_mat: StandardMaterial3D = Look.flat(Look.c("metal"), 0.4, 0.6)
	for sx: int in [-1, 1]:
		add_child(Look.cylinder(0.09, 2.6, pole_mat, Vector3(sx * radius * 0.82, 1.3, 0), 0.05, 10))
		add_child(Look.sphere(0.13, pole_mat, Vector3(sx * radius * 0.82, 2.65, 0)))
	_orb_mat = StandardMaterial3D.new()
	_orb_mat.albedo_color = Color(0.35, 0.38, 0.45)
	_orb_mat.emission_enabled = true
	_orb_mat.emission = Look.c("accent")
	_orb_mat.emission_energy_multiplier = 0.1
	_orb = Look.mesh_node(_octa(), _orb_mat, Vector3(0, 2.75, 0))
	add_child(_orb)
	_burst = _make_burst()
	add_child(_burst)
	_build_fx()


func _build_fx() -> void:
	var hot: Color = Fx.hot(Look.c("accent").lerp(Color.WHITE, 0.25), 2.4)
	var vis := AABB(Vector3(-radius - 4.0, -1.0, -radius - 4.0), Vector3(radius * 2.0 + 8.0, 12.0, radius * 2.0 + 8.0))
	_fountain = Fx.sparks({"amount": 90, "lifetime": 1.3, "explosiveness": 0.6, "dir": Vector3.UP,
		"spread": 28.0, "speed": Vector2(6.0, 11.0), "gravity": Vector3(0, -14, 0), "damping": Vector2(0.5, 1.0),
		"color": hot, "size": Vector2(0.07, 0.5), "curve": "flat",
		"fade": PackedFloat32Array([1.0, 1.0, 0.0]), "aabb": vis})
	_fountain.position = Vector3(0, 2.75, 0)
	add_child(_fountain)
	_glitter = Fx.burst({"amount": 50, "lifetime": 1.0, "shape": "sphere", "radius": 0.4, "tex": Fx.Tex.STAR,
		"size": 0.35, "speed": Vector2(1.5, 4.0), "damping": Vector2(2.0, 3.0), "gravity": Vector3(0, -2, 0),
		"curve": "pop", "color": hot, "aabb": vis})
	_glitter.position = Vector3(0, 2.75, 0)
	add_child(_glitter)
	_motes = Fx.embers({"amount": 18, "lifetime": 2.2, "shape": "ring", "ring_radius": radius * 0.75,
		"ring_inner": radius * 0.2, "speed": Vector2(0.4, 1.0), "tex": Fx.Tex.STAR, "size": 0.18,
		"curve": "pop", "color": hot, "turbulence": 0.3, "emitting": false, "aabb": vis})
	_motes.position = Vector3(0, 0.1, 0)
	add_child(_motes)
	_wave = Fx.shockwave(radius * 3.2, {"lifetime": 0.6, "color": hot, "aabb": vis})
	_wave.position = Vector3(0, 0.08, 0)
	add_child(_wave)
	_halo = Fx.sprite(Look.c("accent").lerp(Color.WHITE, 0.3), 1.6, Fx.Tex.DOT, true)
	_halo_mat = _halo.material_override as StandardMaterial3D
	_halo.position = Vector3(0, 2.75, 0)
	add_child(_halo)


func _octa() -> Mesh:
	var s := SphereMesh.new()
	s.radius = 0.3
	s.height = 0.75
	s.radial_segments = 4
	s.rings = 1
	return s


func set_active(on: bool, celebrate: bool = true) -> void:
	if active == on:
		return
	active = on
	# a flare still running must never drive a switched-off ring back up
	if _flare_tw != null and _flare_tw.is_valid():
		_flare_tw.kill()
	_ring_mat.emission_energy_multiplier = 2.4 if on else 0.15
	_orb_mat.emission_energy_multiplier = 3.5 if on else 0.1
	_orb_mat.albedo_color = Look.c("accent") if on else Color(0.35, 0.38, 0.45)
	if _motes != null:
		_motes.emitting = on
	if on and celebrate:
		var tw: Tween = create_tween()
		_orb.scale = Vector3.ONE * 2.2
		tw.tween_property(_orb, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		# the floor ring flashes bright and settles, and sparks rise off it
		_ring_mat.emission_energy_multiplier = 7.0
		_flare_tw = create_tween()
		_flare_tw.tween_property(_ring_mat, "emission_energy_multiplier", 2.4, 0.6).set_ease(Tween.EASE_OUT)
		_burst.restart()
		_fountain.restart()
		_glitter.restart()
		Fx.flash(self, global_position + Vector3(0, 2.2, 0), Look.c("accent"), 6.0, 11.0, 0.7)
		_wave.restart()


func _make_burst() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = Fx.count(40)
	p.lifetime = 0.9
	p.explosiveness = 0.9
	p.layers = 2               # (keeps the player's blob-shadow decal off the sparks)
	p.position = Vector3(0, 0.1, 0)
	p.visibility_aabb = AABB(Vector3(-radius - 2.0, -1.0, -radius - 2.0), Vector3(radius * 2.0 + 4.0, 7.0, radius * 2.0 + 4.0))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = radius * 0.84
	pm.emission_ring_inner_radius = radius * 0.76
	pm.emission_ring_height = 0.05
	pm.direction = Vector3.UP
	pm.spread = 12.0
	pm.initial_velocity_min = 4.0
	pm.initial_velocity_max = 7.0
	pm.gravity = Vector3(0, -6.0, 0)
	pm.damping_min = 1.0
	pm.damping_max = 2.0
	pm.scale_min = 0.6
	pm.scale_max = 1.0
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	p.process_material = pm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = Look.c("accent")
	var dot := Gradient.new()
	dot.set_color(0, Color(1, 1, 1, 1))
	dot.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = dot
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 32
	tex.height = 32
	m.albedo_texture = tex
	var q := QuadMesh.new()
	q.size = Vector2(0.2, 0.2)
	q.material = m
	p.draw_pass_1 = q
	return p


func respawn_transform() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, global_rotation.y), global_position + Vector3(0, 0.15, 0))


func _process(dt: float) -> void:
	_t += dt
	_orb.rotation.y = _t * (2.2 if active else 0.5)
	_orb.position.y = 2.75 + sin(_t * 2.0) * 0.08
	if _halo != null:
		_halo.position.y = _orb.position.y
		var beat: float = 0.5 + 0.5 * sin(_t * (4.0 if active else 1.6))
		_halo_mat.albedo_color.a = (0.55 + 0.3 * beat) if active else (0.14 + 0.12 * beat)
		_halo.scale = Vector3.ONE * ((1.3 + 0.25 * beat) if active else (0.9 + 0.15 * beat))
