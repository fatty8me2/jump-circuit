class_name XenoDriftWell
extends Area3D
## Xeno Wilds: a drift well - a black crystal monolith humming in the middle of a chasm, wrapped in
## a sphere of its own weak gravity. While you are airborne inside the sphere, `lift` m/s^2 of the
## moon's gravity is cancelled (30/42 -> ~14/26), so jumps hang and float; standing, running and
## jumping off the ground work as normal. Drift stones (kit.orbiter platforms dressed as rock)
## circle the monolith inside the field, and motes spiral in toward it so the sphere reads.
## Always on (unlike Orbital Drift's pulsing bay). Positioned at the centre of the sphere; the
## monolith stands on the sphere's axis from `base_y` (local) up.

@export var radius: float = 14.0
@export var lift: float = 16.0
@export var base_y: float = -30.0
@export var monolith_top: float = 3.0
@export var tint: Color = Color(0.7, 0.45, 1.0)

var _hum: AudioStreamPlayer3D
var _glyph_mat: StandardMaterial3D
var _t: float = 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitorable = false
	var shape := SphereShape3D.new()
	shape.radius = radius
	var cs := CollisionShape3D.new()
	cs.shape = shape
	add_child(cs)
	_build_visual()
	_hum = WorldAudio.loop("drift_hum", self, -6.0, radius + 14.0, 6.0)


func _physics_process(dt: float) -> void:
	for body: Node3D in get_overlapping_bodies():
		if body is Player:
			var p := body as Player
			if p.grounded or p.is_wall_running() or p.is_mantling():
				continue
			if p.global_position.distance_to(global_position) > radius:
				continue
			p.velocity.y += lift * dt


func _process(dt: float) -> void:
	_t += dt
	_glyph_mat.emission_energy_multiplier = 1.8 + 1.2 * sin(_t * 1.7)


func _build_visual() -> void:
	# the monolith: a tall hexagonal shard of black glass with bands of pulsing glyphs
	var h: float = monolith_top - base_y
	var obsidian: StandardMaterial3D = Look.flat(Color(0.06, 0.05, 0.1), 0.15, 0.6)
	var shard := Look.cylinder(1.3, h, obsidian, Vector3(0, base_y + h * 0.5, 0), 0.9, 6)
	add_child(shard)
	var tip := Look.cylinder(0.9, 3.0, obsidian, Vector3(0, monolith_top + 1.5, 0), 0.0, 6)
	add_child(tip)
	_glyph_mat = Look.flat(tint, 0.3, 0.0, 2.0).duplicate() as StandardMaterial3D
	for i: int in 7:
		var y: float = monolith_top - 1.2 - float(i) * 3.1
		var band := Look.cylinder(lerpf(1.3, 0.9, (y - base_y) / h) + 0.07, 0.18, _glyph_mat, Vector3(0, y, 0), -1.0, 6)
		band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(band)
	add_child(Look.sphere(0.5, _glyph_mat, Vector3(0, monolith_top + 3.6, 0)))
	var l := OmniLight3D.new()
	l.light_color = tint
	l.light_energy = 2.2
	l.omni_range = radius + 4.0
	l.shadow_enabled = false
	l.position = Vector3(0, monolith_top, 0)
	add_child(l)
	# rings of the field: three thin halos tilted round the monolith, turning slowly
	for i: int in 3:
		var tm := TorusMesh.new()
		tm.inner_radius = radius * (0.55 + 0.15 * float(i))
		tm.outer_radius = tm.inner_radius + 0.12
		tm.rings = 64
		tm.ring_segments = 4
		var holder := Node3D.new()
		holder.set_script(preload("res://visual/spin.gd"))
		holder.set("period", 18.0 + 7.0 * float(i))
		holder.set("axis", Vector3(0.2 * float(i), 1.0, -0.15).normalized())
		holder.rotation = Vector3(0.25 - 0.2 * float(i), 0.7 * float(i), 0.15 * float(i))
		var ring := Look.mesh_node(tm, Look.flat(tint.lightened(0.2), 0.3, 0.0, 1.6))
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(ring)
		add_child(holder)
	# a faint fresnel shell marking the edge of the field
	var shell_mat := ShaderMaterial.new()
	shell_mat.shader = preload("res://visual/xeno_shell.gdshader")
	shell_mat.set_shader_parameter("tint", Color(tint.r, tint.g, tint.b))
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 48
	sm.rings = 24
	var shell := Look.mesh_node(sm, shell_mat)
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shell)
	var vis := AABB(Vector3(-radius - 2.0, -radius - 2.0, -radius - 2.0), Vector3(radius * 2.0 + 4.0, radius * 2.0 + 4.0, radius * 2.0 + 4.0))
	# motes drifting slowly UP through the field (the tell of low gravity) ...
	var up: GPUParticles3D = Fx.emitter({"amount": 70, "lifetime": 5.0, "local": true, "shape": "sphere", "radius": radius * 0.9,
		"dir": Vector3.UP, "spread": 20.0, "speed": Vector2(0.3, 0.9), "gravity": Vector3(0, 0.1, 0),
		"tex": Fx.Tex.DOT, "size": 0.16, "curve": "pop", "color": Fx.hot(tint.lightened(0.3), 1.8), "aabb": vis, "preprocess": 5.0})
	add_child(up)
	# ... and a slow spiral of glints wheeling round the monolith
	var swirl: GPUParticles3D = Fx.emitter({"amount": 50, "lifetime": 6.0, "local": true, "shape": "ring", "ring_radius": radius * 0.8,
		"ring_inner": radius * 0.3, "ring_height": 8.0, "dir": Vector3.UP, "spread": 5.0, "speed": Vector2(0.1, 0.3),
		"radial": Vector2(-0.4, -0.2), "tex": Fx.Tex.STAR, "size": 0.3, "curve": "pop",
		"color": Fx.hot(Color(0.6, 1.0, 0.95), 1.6), "aabb": vis, "preprocess": 6.0})
	swirl.position = Vector3(0, -2.0, 0)
	add_child(swirl)
