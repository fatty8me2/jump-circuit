class_name DinoVolcano
extends Node3D
## The smoking volcano far off on Dino Valley's horizon (visual only). A big noisy cone (a generated
## mesh with gullies and a crater) in visual/dino_volcano.gdshader, a lake of lava in the crater, and a
## colossal plume of ash and smoke that pours out of it, rises, leans with the wind and spreads into an
## anvil of cloud, glowing orange underneath at the crater and dusty grey above. Occasional bursts throw a
## fountain of sparks. The plume is world-space particles the size of hills, so from the course it
## reads as a slow, huge cloud. Placed with `make`.

const HAZE := Color(0.78, 0.82, 0.72)

var radius: float = 260.0
var height: float = 190.0
var _burst: GPUParticles3D
var _next_burst: float = 4.0
var _glow_mat: StandardMaterial3D


static func make(parent: Node3D, at: Vector3, base_radius: float, peak: float) -> DinoVolcano:
	var v := DinoVolcano.new()
	v.radius = base_radius
	v.height = peak
	v.position = at
	parent.add_child(v)
	v._build()
	return v


func _cone() -> ArrayMesh:
	var rings: int = 26
	var segs: int = 56
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grid: Array[Array] = []
	# profile rings from the foot up to the lip, then in and down into the crater
	var prof: Array[Vector2] = []
	for i: int in rings + 1:
		var t: float = float(i) / float(rings)
		prof.append(Vector2(radius * pow(1.0 - t, 1.45) + radius * 0.13 * t, height * (1.0 - pow(1.0 - t, 1.9))))
	prof.append(Vector2(radius * 0.11, height * 0.975))
	prof.append(Vector2(radius * 0.06, height * 0.93))
	prof.append(Vector2(0.01, height * 0.92))
	for ring: int in prof.size():
		var row: Array = []
		for k: int in segs + 1:
			var a: float = TAU * float(k % segs) / float(segs)
			var t2: float = float(mini(ring, rings)) / float(rings)
			var wob: float = 1.0 + 0.07 * sin(a * 3.0 + 1.0) + 0.05 * sin(a * 7.0 + t2 * 5.0) + 0.045 * sin(a * 13.0 - t2 * 3.0)
			var gully: float = 1.0 - 0.035 * (0.5 + 0.5 * sin(a * 17.0 + t2 * 2.0)) * t2
			var r: float = prof[ring].x * wob * gully
			row.append(Vector3(cos(a) * r, prof[ring].y, sin(a) * r))
		grid.append(row)
	for ring2: int in prof.size() - 1:
		for k2: int in segs:
			var a0: Vector3 = grid[ring2][k2]
			var a1: Vector3 = grid[ring2][k2 + 1]
			var b0: Vector3 = grid[ring2 + 1][k2]
			var b1: Vector3 = grid[ring2 + 1][k2 + 1]
			st.add_vertex(a0)
			st.add_vertex(a1)
			st.add_vertex(b0)
			st.add_vertex(a1)
			st.add_vertex(b1)
			st.add_vertex(b0)
	st.generate_normals()
	return st.commit()


func _build() -> void:
	var cone := MeshInstance3D.new()
	cone.mesh = _cone()
	var m := ShaderMaterial.new()
	m.shader = preload("res://visual/dino_volcano.gdshader")
	m.set_shader_parameter("height", height)
	cone.material_override = m
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cone)
	# the lava lake in the crater
	_glow_mat = Look.flat(Color(1.0, 0.4, 0.08), 0.3, 0.0, 3.0).duplicate() as StandardMaterial3D
	var lake: MeshInstance3D = Look.cylinder(radius * 0.075, 1.5, _glow_mat, Vector3(0, height * 0.94, 0), -1.0, 16)
	lake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lake)
	var big := AABB(Vector3(-1500, -200, -1500), Vector3(3000, 1600, 3000))
	var top := Vector3(0, height * 0.97, 0)
	# the plume: huge soft puffs rising from the crater, leaning with the wind, darkening as they climb
	var plume: GPUParticles3D = Fx.emitter({"amount": 80, "lifetime": 26.0, "preprocess": 26.0, "shape": "sphere",
		"radius": radius * 0.07, "dir": Vector3.UP, "spread": 8.0, "speed": Vector2(10.0, 15.0),
		"gravity": Vector3(4.0, 0.6, 1.5), "damping": Vector2(0.15, 0.3), "tex": Fx.Tex.SMOKE, "additive": false,
		"size": radius * 0.5, "scale": Vector2(0.7, 1.2), "curve": "puff", "angle": Vector2(0, 360), "spin": Vector2(-4, 4),
		"turbulence": 2.0, "turbulence_scale": 0.6,
		"colors": PackedColorArray([Color(1.0, 0.5, 0.22, 0.0), Color(0.7, 0.48, 0.38, 0.55), Color(0.46, 0.42, 0.42, 0.62),
			Color(0.62, 0.6, 0.6, 0.38), Color(0.78, 0.76, 0.74, 0.0)]), "aabb": big, "fixed_fps": 12})
	plume.position = top
	add_child(plume)
	# a thinner, darker ash column hugging the vent and the glow under it
	var column: GPUParticles3D = Fx.emitter({"amount": 40, "lifetime": 12.0, "preprocess": 12.0, "shape": "sphere",
		"radius": radius * 0.04, "dir": Vector3.UP, "spread": 5.0, "speed": Vector2(16.0, 22.0), "gravity": Vector3(2.0, 0.0, 0.8),
		"tex": Fx.Tex.SMOKE, "additive": false, "size": radius * 0.22, "curve": "puff", "angle": Vector2(0, 360),
		"colors": PackedColorArray([Color(1.0, 0.45, 0.15, 0.7), Color(0.3, 0.26, 0.26, 0.7), Color(0.4, 0.38, 0.38, 0.0)]),
		"aabb": big, "fixed_fps": 12})
	column.position = top
	add_child(column)
	var glow: GPUParticles3D = Fx.emitter({"amount": 18, "lifetime": 6.0, "preprocess": 6.0, "shape": "sphere", "radius": radius * 0.05,
		"dir": Vector3.UP, "spread": 20.0, "speed": Vector2(6.0, 14.0), "tex": Fx.Tex.DOT, "size": 9.0,
		"color": Color(2.6, 1.0, 0.3, 0.6), "fade": PackedFloat32Array([0.0, 1.0, 0.4, 0.0]), "aabb": big, "fixed_fps": 12})
	glow.position = top
	add_child(glow)
	_burst = Fx.sparks({"amount": 120, "lifetime": 3.2, "one_shot": true, "emitting": false, "explosiveness": 0.95,
		"shape": "sphere", "radius": radius * 0.04, "dir": Vector3.UP, "spread": 28.0, "speed": Vector2(40.0, 80.0),
		"gravity": Vector3(2.0, -22.0, 0.0), "color": Color(3.0, 1.2, 0.35), "size": Vector2(0.9, 5.0), "aabb": big})
	_burst.position = top
	add_child(_burst)
	var rumble: AudioStreamPlayer3D = WorldAudio.loop("dino_volcano_rumble", self, -8.0, 1400.0, 300.0)
	if rumble != null:
		rumble.position = top


func _process(dt: float) -> void:
	_next_burst -= dt
	if _next_burst <= 0.0:
		_next_burst = randf_range(7.0, 13.0)
		_burst.restart()
		_burst.emitting = true
		_glow_mat.emission_energy_multiplier = 5.5
		var tw: Tween = create_tween()
		tw.tween_property(_glow_mat, "emission_energy_multiplier", 3.0, 2.5)
