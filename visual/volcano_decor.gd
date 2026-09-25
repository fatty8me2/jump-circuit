class_name VolcanoDecor
extends RefCounted
## Cinder Peak set dressing: columnar basalt organs, obsidian blades, charred snags, sulphur
## vents, lava falls pouring off cliffs into glowing pools, pumice boulders, and the sister
## volcano smoking on the horizon. Decoration only (no collision); the level places it round
## (never on) the route. Meshes and materials are shared through Look's caches.

const FLOW_SHADER: Shader = preload("res://visual/volcano_flow.gdshader")
const LAVA_SHADER: Shader = preload("res://visual/volcano_lava.gdshader")

var root: Node3D
var rng: RandomNumberGenerator


func _init(level_root: Node3D, random: RandomNumberGenerator) -> void:
	root = level_root
	rng = random


func _put(n: Node3D, pos: Vector3) -> Node3D:
	n.position = pos
	root.add_child(n)
	return n


static func basalt_mat(shade: float = 0.0) -> StandardMaterial3D:
	return Look.flat(Color(0.14, 0.12, 0.12).darkened(shade), 0.9)


## A cluster of hexagonal basalt columns (a "basalt organ") whose tallest top is at `top_y`,
## rooted `depth` below it. Tops of a few columns glow along their cooling cracks.
func organ(base: Vector3, top_y: float, radius: float, count: int = 7, depth: float = 60.0) -> void:
	var n := Node3D.new()
	var seam: StandardMaterial3D = Look.flat(Color(1.0, 0.35, 0.07), 0.4, 0.0, 2.4)
	var cap: StandardMaterial3D = Look.flat(Color(0.26, 0.22, 0.21), 0.8)
	for i: int in count:
		var a: float = rng.randf() * TAU
		var d: float = sqrt(rng.randf()) * radius
		var r: float = snappedf(rng.randf_range(0.7, 1.3), 0.1)
		var h: float = snappedf(depth - rng.randf_range(0.0, radius * 1.6), 1.0)
		var p := Vector3(cos(a) * d, top_y - (depth - h) - base.y, sin(a) * d)
		var col := Look.cylinder(r, h, basalt_mat(rng.randf() * 0.3), p - Vector3(0, h * 0.5, 0), r * 1.04, 6)
		col.rotation.y = rng.randf() * TAU
		n.add_child(col)
		var top := Look.cylinder(r * 0.98, 0.12, cap, p + Vector3(0, 0.02, 0), -1.0, 6)
		top.rotation.y = col.rotation.y
		n.add_child(top)
		if rng.randf() < 0.3:
			var s := Look.cylinder(r * 1.02, 0.08, seam, p - Vector3(0, rng.randf_range(0.8, 3.0), 0), -1.0, 6)
			s.rotation.y = col.rotation.y
			s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			n.add_child(s)
	_put(n, base)


## A spray of glassy black obsidian blades.
func obsidian(pos: Vector3, scale: float = 1.0) -> void:
	var n := Node3D.new()
	var glass: StandardMaterial3D = Look.flat(Color(0.04, 0.03, 0.05), 0.08, 0.35)
	for i: int in rng.randi_range(3, 6):
		var h: float = rng.randf_range(2.0, 5.5) * scale
		var b := Look.cylinder(rng.randf_range(0.35, 0.7) * scale, h, glass, Vector3(0, h * 0.4, 0), 0.0, 5)
		b.rotation = Vector3(rng.randf_range(-0.45, 0.45), rng.randf() * TAU, rng.randf_range(-0.45, 0.45))
		b.position = Vector3(rng.randf_range(-1.0, 1.0), 0, rng.randf_range(-1.0, 1.0)) * scale
		n.add_child(b)
	_put(n, pos)


## A dead, charred tree with a few embers still glowing on its broken branches.
func snag(pos: Vector3, scale: float = 1.0) -> void:
	var n := Node3D.new()
	var wood: StandardMaterial3D = Look.flat(Color(0.06, 0.05, 0.05), 0.95)
	var ember: StandardMaterial3D = Look.flat(Color(1.0, 0.4, 0.1), 0.4, 0.0, 3.0)
	var h: float = rng.randf_range(4.0, 7.0) * scale
	n.add_child(Look.cylinder(0.26 * scale, h, wood, Vector3(0, h * 0.5, 0), 0.08 * scale, 7))
	for i: int in 3:
		var bh: float = h * rng.randf_range(0.45, 0.85)
		var bl: float = rng.randf_range(1.2, 2.4) * scale
		var br := Look.cylinder(0.1 * scale, bl, wood, Vector3.ZERO, 0.03 * scale, 5)
		var a: float = rng.randf() * TAU
		var tilt: float = rng.randf_range(0.6, 1.1)
		br.rotation = Vector3(0, a, tilt)
		br.position = Vector3(0, bh, 0) + Basis(Vector3.UP, a) * Vector3(-sin(tilt), cos(tilt), 0) * bl * 0.5
		n.add_child(br)
		n.add_child(Look.sphere(0.07 * scale, ember, br.position + Basis(Vector3.UP, a) * Vector3(-sin(tilt), cos(tilt), 0) * bl * 0.5))
	n.rotation.y = rng.randf() * TAU
	_put(n, pos)


## A crust of sulphur crystals round a vent that hisses pale steam.
func sulphur_vent(pos: Vector3) -> void:
	var n := Node3D.new()
	var y: StandardMaterial3D = Look.flat(Color(0.95, 0.85, 0.22), 0.6, 0.0, 0.4)
	var pale: StandardMaterial3D = Look.flat(Color(0.8, 0.76, 0.5), 0.8)
	n.add_child(Look.cylinder(1.2, 0.3, pale, Vector3(0, 0.1, 0), 0.8, 10))
	for i: int in 8:
		var a: float = TAU * float(i) / 8.0 + rng.randf() * 0.4
		var c := Look.box(Vector3(0.18, rng.randf_range(0.3, 0.6), 0.18), y, Vector3(cos(a), 0.25, sin(a)) * rng.randf_range(0.6, 1.1))
		c.rotation = Vector3(rng.randf_range(-0.5, 0.5), a, rng.randf_range(-0.5, 0.5))
		n.add_child(c)
	_put(n, pos)
	VolcanoFx.steam(root, pos + Vector3(0, 0.3, 0), 0.5, 7.0, 12)


## A cliff of dark rock with lava pouring off its lip into a glowing pool at its foot.
## `face` is the horizontal direction the fall pours toward.
func lava_cliff(foot: Vector3, height: float, width: float, face: Vector3) -> void:
	var yaw: float = atan2(face.x, face.z)
	var basis := Basis(Vector3.UP, yaw)
	var rock: StandardMaterial3D = basalt_mat(0.1)
	var cliff := Look.box(Vector3(width + 8.0, height, 7.0), rock)
	cliff.position = foot + basis * Vector3(0, height * 0.5, -4.2)
	cliff.rotation.y = yaw
	root.add_child(cliff)
	# the fall: a ribbon of flowing lava down the face
	var m := ShaderMaterial.new()
	m.shader = FLOW_SHADER
	m.set_shader_parameter("size", Vector2(width, height))
	m.set_shader_parameter("speed", 7.0)
	var q := QuadMesh.new()
	q.size = Vector2(width, height)
	var fall := Look.mesh_node(q, m)
	fall.position = foot + basis * Vector3(0, height * 0.5, -0.6)
	fall.rotation.y = yaw
	fall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(fall)
	# the pool it fills
	var lm := ShaderMaterial.new()
	lm.shader = LAVA_SHADER
	lm.set_shader_parameter("crust", 0.25)
	lm.set_shader_parameter("flow", Vector2(face.x, face.z) * 0.8)
	var pm := PlaneMesh.new()
	pm.size = Vector2(width + 6.0, 12.0)
	var pool := Look.mesh_node(pm, lm, foot + basis * Vector3(0, 0.1, 5.0))
	pool.rotation.y = yaw
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(pool)
	var spl: GPUParticles3D = VolcanoFx.splash(root, foot + basis * Vector3(0, 0.4, 0.4), width * 0.4, 30, 5.0)
	spl.one_shot = false
	spl.explosiveness = 0.2
	spl.emitting = true
	VolcanoFx.smoke(root, foot + basis * Vector3(0, 1.0, 1.5), width * 0.4, 20.0, 8, Color(0.3, 0.2, 0.18, 0.45), 4.0)
	VolcanoFx.glow_light(root, foot + basis * Vector3(0, height * 0.35, 3.0), 3.0, height * 0.9 + 6.0)


## A few pumice and scoria boulders.
func boulders(pos: Vector3, scale: float = 1.0) -> void:
	var n := Node3D.new()
	for i: int in rng.randi_range(2, 4):
		var r: float = rng.randf_range(0.5, 1.2) * scale
		var b := Look.sphere(r, Look.flat(Color(0.2, 0.15, 0.14).lightened(rng.randf() * 0.15), 0.95),
			Vector3(rng.randf_range(-1.2, 1.2), r * 0.5, rng.randf_range(-1.2, 1.2)) * Vector3(scale, 1.0, scale))
		b.scale = Vector3(1.0, rng.randf_range(0.6, 0.9), rng.randf_range(0.8, 1.2))
		n.add_child(b)
	_put(n, pos)


## The sister volcano on the horizon: a dark cone with a dull crater glow and a leaning plume.
func sister(center: Vector3, height: float, base_r: float) -> void:
	var n := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.03, 0.03)
	mat.roughness = 1.0
	mat.disable_fog = true
	var cone := CylinderMesh.new()
	cone.bottom_radius = base_r
	cone.top_radius = base_r * 0.07
	cone.height = height
	cone.radial_segments = 48
	cone.rings = 1
	n.add_child(Look.mesh_node(cone, mat, Vector3(0, height * 0.5, 0)))
	var glow := VolcanoPeak._glow_mat(Color(1.0, 0.35, 0.08), 3.0)
	n.add_child(Look.cylinder(base_r * 0.06, 2.0, glow, Vector3(0, height + 0.5, 0), -1.0, 24))
	var halo := Fx.sprite(Color(1.0, 0.35, 0.1, 0.45), base_r * 0.45, Fx.Tex.DOT, true)
	(halo.material_override as StandardMaterial3D).disable_fog = true
	halo.position = Vector3(0, height + base_r * 0.05, 0)
	n.add_child(halo)
	_put(n, center)
	var plume: GPUParticles3D = VolcanoFx.smoke(root, center + Vector3(0, height, 0), base_r * 0.06, height * 0.9, 14, Color(0.12, 0.07, 0.07, 0.6), base_r * 0.1)
	var pm := plume.process_material as ParticleProcessMaterial
	pm.gravity = VolcanoPeak.WIND * 6.0 + Vector3(0, 1.0, 0)
	plume.visibility_aabb = AABB(Vector3(-2000, -200, -2000), Vector3(4000, 2400, 4000))
	VolcanoPeak.unfog(plume)
