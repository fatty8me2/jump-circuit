class_name AuroraDecor
extends RefCounted
## Aurora Run's set dressing: the mountain itself (a heightfield with a valley floor under the course, steep
## snowy walls, far peaks and a frozen tarn), pines in MultiMesh chunks, boulders, cairns, lantern posts and
## ice crystals. Everything is visual only (no collision) and built from a handful of shared meshes and
## materials. The course tells it where its lowest surface is (note()) so the terrain always sits below it.

const SNOW_SHADER: Shader = preload("res://visual/aurora_snow.gdshader")

const SNOW := Color(0.82, 0.90, 1.0)
const ROCK := Color(0.11, 0.14, 0.22)
const PINE := Color(0.05, 0.16, 0.17)
const PINE_TIP := Color(0.55, 0.74, 0.86)
const GREEN := Color(0.18, 1.0, 0.55)
const TEAL := Color(0.12, 0.85, 0.95)
const VIOLET := Color(0.70, 0.32, 1.0)
const LAMP := Color(0.62, 1.0, 0.92)

## How far under the lowest course surface the valley floor lies.
const FLOOR_DROP: float = 8.0
## Half-width of the flat valley floor under the course, and the course's x range it must clear.
const FLOOR_HALF: float = 30.0

var root: Node3D
var rng: RandomNumberGenerator
var _noise: FastNoiseLite
var _ridge: FastNoiseLite
## Lowest course surface by z, built by note(): z sorted descending after finish().
var _pz: PackedFloat32Array = PackedFloat32Array()
var _py: PackedFloat32Array = PackedFloat32Array()
var _end_z: float = -1100.0
var _end_y: float = -130.0
var _peaks: Array[Vector4] = []
var _basin: Vector4 = Vector4(0, 0, 0, 0)  # centre z, half length, half width, level
var _snow_mat: ShaderMaterial
var _pine_mesh: ArrayMesh
var _rock_mesh: Mesh
var _pine_mat: StandardMaterial3D


func _init(parent: Node3D, shared_rng: RandomNumberGenerator) -> void:
	root = parent
	rng = shared_rng
	_noise = FastNoiseLite.new()
	_noise.seed = 4711
	_noise.frequency = 0.012
	_noise.fractal_octaves = 3
	_ridge = FastNoiseLite.new()
	_ridge.seed = 99
	_ridge.frequency = 0.0045
	_ridge.fractal_octaves = 4


# ---- the course's profile -------------------------------------------------------------------------

## Records that the course has a walkable surface at (z, y); the terrain stays FLOOR_DROP under the lowest.
func note(z: float, y: float) -> void:
	_pz.append(z)
	_py.append(y)


## Sorts the profile and bins it to a smooth lower envelope (call once the course is built).
func finish(end_z: float, end_y: float) -> void:
	_end_z = end_z
	_end_y = end_y
	var n: int = _pz.size()
	var order: Array[int] = []
	for i: int in n:
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return _pz[a] > _pz[b])
	var step: float = 6.0
	var z0: float = 40.0
	var bins: int = int((z0 - end_z) / step) + 2
	var env := PackedFloat32Array()
	env.resize(bins)
	env.fill(INF)
	for i: int in n:
		var b: int = clampi(int((z0 - _pz[i]) / step), 0, bins - 1)
		env[b] = minf(env[b], _py[i])
	# fill gaps and take a running minimum over +-2 bins, then smooth
	var prev: float = 0.0
	for b: int in bins:
		if is_inf(env[b]):
			env[b] = prev
		prev = env[b]
	var low := PackedFloat32Array()
	low.resize(bins)
	for b: int in bins:
		var m: float = env[b]
		for k: int in range(-2, 3):
			m = minf(m, env[clampi(b + k, 0, bins - 1)])
		low[b] = m
	var smooth := PackedFloat32Array()
	smooth.resize(bins)
	for b: int in bins:
		var s: float = 0.0
		var w: float = 0.0
		for k: int in range(-3, 4):
			s += low[clampi(b + k, 0, bins - 1)]
			w += 1.0
		smooth[b] = minf(s / w, low[b] + 1.5)
	_pz = PackedFloat32Array()
	_py = smooth
	for b: int in bins:
		_pz.append(z0 - float(b) * step)
	# far peaks all round the valley
	var peak_rng := RandomNumberGenerator.new()
	peak_rng.seed = 2024
	for i: int in 34:
		var side: float = -1.0 if i % 2 == 0 else 1.0
		var z: float = lerpf(120.0, end_z - 700.0, float(i) / 33.0) + peak_rng.randf_range(-40.0, 40.0)
		var x: float = side * peak_rng.randf_range(260.0, 560.0)
		var h: float = peak_rng.randf_range(110.0, 270.0)
		var r: float = peak_rng.randf_range(150.0, 280.0)
		_peaks.append(Vector4(x, z, h, r))
	# a great peak far ahead, the aurora rising behind it
	_peaks.append(Vector4(-60.0, end_z - 640.0, 320.0, 330.0))
	_peaks.append(Vector4(240.0, end_z - 560.0, 250.0, 260.0))


## Depression holding the frozen tarn: centre z, half length, half width, ice level.
func set_basin(cz: float, half_len: float, half_wid: float, level: float) -> void:
	_basin = Vector4(cz, half_len, half_wid, level)


func course_y(z: float) -> float:
	if _pz.is_empty():
		return 0.0
	if z >= _pz[0]:
		# behind the start the mountain climbs away
		return _py[0] + (z - _pz[0]) * 0.22
	if z <= _pz[_pz.size() - 1]:
		return _py[_py.size() - 1]
	var step: float = _pz[0] - _pz[1]
	var f: float = (_pz[0] - z) / step
	var i: int = clampi(int(f), 0, _py.size() - 2)
	return lerpf(_py[i], _py[i + 1], f - float(i))


# ---- terrain ----------------------------------------------------------------------------------------

## Terrain height at (x, z).
func height(x: float, z: float) -> float:
	var d: float = absf(x)
	var base: float = course_y(z) - FLOOR_DROP
	var floor_bump: float = _noise.get_noise_2d(x * 1.3, z * 1.3) * 1.6
	var out_d: float = maxf(d - FLOOR_HALF, 0.0)
	var wall: float = pow(out_d, 1.18) * 0.34
	var rid: float = 0.65 + 0.7 * (0.5 + 0.5 * _ridge.get_noise_2d(x * 0.7, z * 0.7))
	var h: float = base + floor_bump * (1.0 - clampf(out_d / 20.0, 0.0, 1.0)) + wall * rid + _noise.get_noise_2d(x + 300.0, z) * minf(out_d * 0.12, 10.0)
	for p: Vector4 in _peaks:
		var dd: float = Vector2(x - p.x, z - p.y).length()
		if dd < p.w:
			var k: float = 1.0 - dd / p.w
			h += p.z * pow(k, 1.35) * (0.8 + 0.4 * _noise.get_noise_2d(x * 0.9, z * 0.9))
	# the frozen tarn
	if _basin.y > 0.0:
		var e: float = Vector2((z - _basin.x) / _basin.y, x / _basin.z).length()
		if e < 1.35:
			var s: float = 1.0 - smoothstep(0.85, 1.35, e)
			h = lerpf(h, minf(h, _basin.w - 2.2), s)
	return h


func _col_spacing(d: float) -> float:
	if d < 56.0:
		return 4.0
	if d < 240.0:
		return 14.0
	return 60.0


## The heightfield mesh from z_hi (behind the start) to z_lo (beyond the finish), as one mesh instance.
func build_terrain(z_hi: float, z_lo: float) -> MeshInstance3D:
	var xs: Array[float] = []
	var x: float = -900.0
	while x <= 900.0:
		xs.append(x)
		x += _col_spacing(absf(x))
	var zs: Array[float] = []
	var z: float = z_hi
	while z >= z_lo:
		zs.append(z)
		z -= 5.0 if z > _end_z - 60.0 else 20.0
	var cols: int = xs.size()
	var rows: int = zs.size()
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var colors := PackedColorArray()
	verts.resize(cols * rows)
	norms.resize(cols * rows)
	colors.resize(cols * rows)
	for r: int in rows:
		for c: int in cols:
			var px: float = xs[c]
			var pz: float = zs[r]
			var h: float = height(px, pz)
			var e: float = 2.5
			var nx: float = height(px - e, pz) - height(px + e, pz)
			var nz: float = height(px, pz - e) - height(px, pz + e)
			var n := Vector3(nx, 2.0 * e, nz).normalized()
			var i: int = r * cols + c
			verts[i] = Vector3(px, h, pz)
			norms[i] = n
			colors[i] = Color(smoothstep(0.58, 0.82, 1.0 - n.y), 0, 0, 1)
	var idx := PackedInt32Array()
	idx.resize((cols - 1) * (rows - 1) * 6)
	var k: int = 0
	for r: int in rows - 1:
		for c: int in cols - 1:
			var a: int = r * cols + c
			var b: int = a + 1
			var cc: int = a + cols
			var dd: int = cc + 1
			# winding so the top faces up (z decreases with the row index)
			idx[k] = a
			idx[k + 1] = cc
			idx[k + 2] = b
			idx[k + 3] = b
			idx[k + 4] = cc
			idx[k + 5] = dd
			k += 6
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = snow_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = "Terrain"
	root.add_child(mi)
	return mi


func snow_material() -> ShaderMaterial:
	if _snow_mat == null:
		_snow_mat = ShaderMaterial.new()
		_snow_mat.shader = SNOW_SHADER
		_snow_mat.set_shader_parameter("snow_a", Color(0.50, 0.62, 0.80))
		_snow_mat.set_shader_parameter("snow_b", Color(0.20, 0.30, 0.50))
		_snow_mat.set_shader_parameter("rock_color", Color(0.06, 0.08, 0.14))
		_snow_mat.set_shader_parameter("glow_a", GREEN)
		_snow_mat.set_shader_parameter("glow_b", VIOLET)
		_snow_mat.set_shader_parameter("glow_amount", 0.9)
	return _snow_mat


## A glossy dark sheet of ice (the tarn, the lake beyond the finish).
func ice_sheet(center: Vector3, size: Vector2) -> MeshInstance3D:
	var pm := PlaneMesh.new()
	pm.size = size
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.05, 0.12, 0.20)
	m.metallic = 0.85
	m.roughness = 0.12
	m.emission_enabled = true
	m.emission = TEAL.darkened(0.55)
	m.emission_energy_multiplier = 0.22
	var mi := Look.mesh_node(pm, m, center)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return mi


# ---- pines and boulders -------------------------------------------------------------------------------

func _cone_tier(st: SurfaceTool, y0: float, y1: float, r: float, segs: int, base_col: Color, tip_col: Color) -> void:
	for s: int in segs:
		var a0: float = TAU * float(s) / float(segs)
		var a1: float = TAU * float(s + 1) / float(segs)
		var p0 := Vector3(cos(a0) * r, y0, sin(a0) * r)
		var p1 := Vector3(cos(a1) * r, y0, sin(a1) * r)
		var tip := Vector3(0, y1, 0)
		var n: Vector3 = (tip - p0).cross(p1 - p0).normalized()
		for pt: Array in [[p0, base_col], [p1, base_col], [tip, tip_col]]:
			st.set_normal(n)
			st.set_color(pt[1] as Color)
			st.add_vertex(pt[0] as Vector3)


func pine_mesh() -> ArrayMesh:
	if _pine_mesh != null:
		return _pine_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# a stack of four snow-dusted tiers, the dark green showing under a pale tip
	var tiers: Array[Vector3] = [Vector3(1.6, 4.0, 2.4), Vector3(3.2, 6.2, 2.0), Vector3(5.0, 8.2, 1.6), Vector3(6.6, 10.0, 1.1)]
	for t: Vector3 in tiers:
		_cone_tier(st, t.x, t.y, t.z, 7, PINE, PINE.lerp(PINE_TIP, 0.82))
	# trunk (a thin box via a short cone with a flat top)
	_cone_tier(st, 0.0, 2.0, 0.28, 5, Color(0.12, 0.09, 0.08), Color(0.12, 0.09, 0.08))
	_pine_mesh = st.commit()
	_pine_mat = StandardMaterial3D.new()
	_pine_mat.vertex_color_use_as_albedo = true
	_pine_mat.roughness = 0.95
	_pine_mat.cull_mode = BaseMaterial3D.CULL_BACK
	_pine_mesh.surface_set_material(0, _pine_mat)
	return _pine_mesh


## Scatters pines on both valley walls along z in [z_hi, z_lo], in chunks that cull independently.
func pines(z_hi: float, z_lo: float, per_chunk: int = 150, chunk_len: float = 150.0) -> int:
	var mesh: ArrayMesh = pine_mesh()
	var placed: int = 0
	var z: float = z_hi
	while z > z_lo:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		var xf: Array[Transform3D] = []
		var tries: int = 0
		while xf.size() < per_chunk and tries < per_chunk * 4:
			tries += 1
			var px: float = rng.randf_range(FLOOR_HALF + 4.0, 150.0) * (-1.0 if rng.randf() < 0.5 else 1.0)
			var pz: float = z - rng.randf() * chunk_len
			var clump: float = _noise.get_noise_2d(px * 2.0, pz * 2.0)
			if clump < -0.12:
				continue
			var py: float = height(px, pz)
			var s: float = rng.randf_range(0.8, 1.7) * (1.0 + clampf((absf(px) - 40.0) * 0.004, 0.0, 0.6))
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.25), s))
			xf.append(Transform3D(basis, Vector3(px, py - 0.4, pz)))
		mm.instance_count = xf.size()
		for i: int in xf.size():
			mm.set_instance_transform(i, xf[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.name = "Pines"
		root.add_child(mmi)
		placed += xf.size()
		z -= chunk_len
	return placed


func rock_mesh() -> Mesh:
	if _rock_mesh == null:
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 1.5
		sm.radial_segments = 7
		sm.rings = 4
		_rock_mesh = sm
	return _rock_mesh


## Boulders (half-buried, dusted with snow on top) in chunks along the course walls.
func boulders(z_hi: float, z_lo: float, per_chunk: int = 26, chunk_len: float = 150.0) -> void:
	var rock: StandardMaterial3D = Look.flat(ROCK.lightened(0.05), 0.95)
	var z: float = z_hi
	while z > z_lo:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = rock_mesh()
		mm.instance_count = per_chunk
		for i: int in per_chunk:
			var px: float = rng.randf_range(FLOOR_HALF + 1.0, 110.0) * (-1.0 if rng.randf() < 0.5 else 1.0)
			var pz: float = z - rng.randf() * chunk_len
			var s: float = rng.randf_range(1.0, 4.5)
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s * rng.randf_range(0.9, 1.4), s * 0.8, s))
			mm.set_instance_transform(i, Transform3D(basis, Vector3(px, height(px, pz) + s * 0.1, pz)))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = rock
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)
		z -= chunk_len


# ---- props ----------------------------------------------------------------------------------------------

## A lantern post: a slim pole and a glowing paper lantern. Emissive only (no light node).
func lantern(pos: Vector3, tint: Color = LAMP, h: float = 2.4) -> void:
	var n := Node3D.new()
	n.position = pos
	root.add_child(n)
	n.add_child(Look.cylinder(0.07, h, Look.flat(Color(0.18, 0.2, 0.28), 0.5, 0.6), Vector3(0, h * 0.5, 0), 0.05, 6))
	n.add_child(Look.box(Vector3(0.5, 0.06, 0.5), Look.flat(Color(0.2, 0.22, 0.3), 0.5, 0.6), Vector3(0, h, 0)))
	n.add_child(Look.sphere(0.2, Look.flat(tint, 0.3, 0.0, 2.8), Vector3(0, h + 0.22, 0)))
	n.add_child(Look.cylinder(0.2, 0.2, Look.flat(Color(0.2, 0.22, 0.3), 0.5, 0.6), Vector3(0, h + 0.52, 0), 0.01, 6))


## A cairn of stacked stones with a snow cap.
func cairn(pos: Vector3, s: float = 1.0) -> void:
	var rock: StandardMaterial3D = Look.flat(ROCK.lightened(0.12), 0.95)
	var snow: StandardMaterial3D = Look.flat(SNOW, 0.9)
	var n := Node3D.new()
	n.position = pos
	root.add_child(n)
	var y: float = 0.0
	for i: int in 4:
		var r: float = (0.62 - 0.11 * float(i)) * s
		var b := Look.sphere(r, rock, Vector3(rng.randf_range(-0.05, 0.05) * s, y + r * 0.45, rng.randf_range(-0.05, 0.05) * s))
		b.scale = Vector3(1.0, 0.62, 1.0)
		n.add_child(b)
		y += r * 0.9
	var cap := Look.sphere(0.2 * s, snow, Vector3(0, y + 0.02, 0))
	cap.scale = Vector3(1.0, 0.5, 1.0)
	n.add_child(cap)


## A cluster of glowing ice crystals (hexagonal spikes).
func crystals(pos: Vector3, tint: Color, s: float = 1.0) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(tint.r, tint.g, tint.b, 0.72)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.1
	m.metallic = 0.2
	m.emission_enabled = true
	m.emission = tint
	m.emission_energy_multiplier = 1.4
	var n := Node3D.new()
	n.position = pos
	root.add_child(n)
	for i: int in 6:
		var a: float = TAU * float(i) / 6.0 + rng.randf() * 0.5
		var h: float = rng.randf_range(0.9, 2.4) * s
		var spike := Look.cylinder(0.16 * s, h, m, Vector3(cos(a) * 0.45 * s, h * 0.5, sin(a) * 0.45 * s), 0.0, 6)
		spike.rotation = Vector3(sin(a) * 0.3, 0, -cos(a) * 0.3)
		n.add_child(spike)
	var core := Look.cylinder(0.22 * s, 2.8 * s, m, Vector3(0, 1.4 * s, 0), 0.0, 6)
	n.add_child(core)


## A slim glowing marker post that lines the fast route.
func marker(pos: Vector3, tint: Color = TEAL, h: float = 2.6) -> void:
	var n := Node3D.new()
	n.position = pos
	root.add_child(n)
	n.add_child(Look.cylinder(0.06, h, Look.flat(Color(0.25, 0.3, 0.4), 0.5, 0.5), Vector3(0, h * 0.5, 0), 0.06, 5))
	n.add_child(Look.cylinder(0.14, 0.5, Look.flat(tint, 0.3, 0.0, 3.0), Vector3(0, h + 0.2, 0), 0.0, 5))


## A snow bank: a squashed white dome.
func bank(pos: Vector3, size: Vector3) -> void:
	var b := Look.sphere(1.0, Look.flat(SNOW.darkened(0.15), 0.92), pos)
	b.scale = size
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(b)
