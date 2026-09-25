class_name VolcanoPeak
extends Node3D
## Cinder Peak's volcano, mid-eruption - the headline image of the level. Built once by the
## level at the crater centre (local XZ = offset from the crater, local Y = world height):
##  * the flank: one big radial mesh (the terrain shader draws the lava rivers racing down it),
##    carved into a gorge under the course so the climb always has air beneath it;
##  * the crater and its lava lake, glowing from within;
##  * the lava fountain (a dense core, wider spatter, a surge burst) and rim smoke;
##  * the ash column (a billowing tapered trunk plus rising puffs) spreading into an anvil
##    cloud lit red from below;
##  * volcanic lightning: jagged bolt meshes flickering inside the cloud with a flash;
##  * lava bombs lobbed out of the crater on smoky arcs;
##  * eruption surges on the course clock: the fountain bursts, the lake and rivers flare,
##    lightning storms, and the level answers with a sky flash and a rain of embers.
## All far pieces ignore the course fog (they fog themselves), so the summit reads from the
## bottom of the climb. Visual only: nothing here collides or times gameplay.

signal lightning(pos: Vector3, strength: float)
signal surged(strength: float)

const TERRAIN_SHADER: Shader = preload("res://visual/volcano_terrain.gdshader")
const PLUME_SHADER: Shader = preload("res://visual/volcano_plume.gdshader")
const LAVA_SHADER: Shader = preload("res://visual/volcano_lava.gdshader")
const SURGE_PERIOD: float = 24.0
const SURGE_OFFSET: float = 9.0
const WIND := Vector3(0.82, 0.0, 0.57)

var crater_r: float = 70.0
var rim_y: float = 80.0
var lake_y: float = 52.0
var column_h: float = 820.0
## Bearing (radians, atan2(z, x) in local XZ) of the breach the course climbs through: the rim is
## lowest there and rises to `back_wall` m higher on the far side, a horseshoe open to the climb.
var breach: float = PI * 0.5
var back_wall: float = 170.0

var _terrain_mat: ShaderMaterial
var _lake_mat: ShaderMaterial
var _column_mat: ShaderMaterial
var _anvil_mat: ShaderMaterial
var _plume_mats: Array[ShaderMaterial] = []
var _surge_burst: GPUParticles3D
var _surge_spatter: GPUParticles3D
var _lake_light: OmniLight3D
var _flash_light: OmniLight3D
var _bolts: Array[MeshInstance3D] = []
var _billows: Array[MeshInstance3D] = []
var _billow_base: Array[Vector3] = []
var _bombs: Array[Dictionary] = []
var _last_surge: int = -999
var _last_slot: int = -1
var _bolt_on: int = -1
var _bolt_until: float = 0.0
var _rng := RandomNumberGenerator.new()
static var _nofog_shaders: Dictionary = {}


## Builds the volcano at world crater centre `c` (its Y ignored) with the rim at `rim`.
## `route` is every point the course passes (the flank is carved to stay well below them).
static func make(parent: Node3D, c: Vector3, rim: float, radius: float, route: Array[Vector3], toward: Vector3 = Vector3.BACK) -> VolcanoPeak:
	var v := VolcanoPeak.new()
	v.breach = atan2(toward.z, toward.x)
	v.name = "VolcanoPeak"
	v.crater_r = radius
	v.rim_y = rim
	v.lake_y = rim - radius * 0.4
	v.position = Vector3(c.x, 0.0, c.z)
	v._rng.seed = 8128
	parent.add_child(v)
	var local: Array[Vector3] = []
	var last := Vector3(INF, 0, INF)
	for p: Vector3 in route:
		var q := Vector3(p.x - c.x, p.y, p.z - c.z)
		if Vector2(q.x - last.x, q.z - last.z).length() > 5.0:
			local.append(q)
			last = q
	v._build_flank(local)
	v._build_crater()
	v._build_fountain()
	v._build_column()
	v._build_lightning()
	v._build_bombs()
	return v


## A copy of `shader` whose render mode also ignores the fog (for the far-away pieces).
static func nofog(shader: Shader) -> Shader:
	if _nofog_shaders.has(shader):
		return _nofog_shaders[shader]
	var s := Shader.new()
	var code: String = shader.code
	var i: int = code.find("render_mode ")
	if i >= 0:
		code = code.insert(code.find(";", i), ", fog_disabled")
	else:
		code = code.replace("shader_type spatial;", "shader_type spatial;\nrender_mode fog_disabled;")
	s.code = code
	_nofog_shaders[shader] = s
	return s


## Re-draws a particle system with a private material that ignores the fog.
static func unfog(p: GPUParticles3D) -> GPUParticles3D:
	if p.draw_pass_1 is QuadMesh:
		var q := (p.draw_pass_1 as QuadMesh).duplicate() as QuadMesh
		var m := (q.material as StandardMaterial3D).duplicate() as StandardMaterial3D
		m.disable_fog = true
		q.material = m
		p.draw_pass_1 = q
	return p


static func _glow_mat(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color.darkened(0.6)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.disable_fog = true
	return m


# ---- the flank ----------------------------------------------------------------------------------

## Height of the crater rim at bearing `a`: low at the breach, a towering wall behind.
func rim_at(a: float) -> float:
	var k: float = 0.5 - 0.5 * cos(a - breach)
	return rim_y + back_wall * pow(k, 1.3) + sin(a * 11.0) * 4.0 * k


## Height of the untouched mountain at radius `r` (from the crater centre) and bearing `a`.
func _cone(r: float, a: float) -> float:
	var R: float = crater_r
	var top: float = rim_at(a)
	if r < R * 0.62:
		return lake_y - 4.0
	if r < R:
		var k: float = (r - R * 0.62) / (R * 0.38)
		return lerpf(lake_y - 4.0, top, pow(k * k * (3.0 - 2.0 * k), 0.7)) + sin(a * 17.0) * 1.5 * k
	var rr: float = r - R
	# the high back wall sheds its height steeply before joining the long flank
	var extra: float = top - rim_y
	var h: float = rim_y + extra * exp(-rr / 160.0) - (30.0 * (1.0 - exp(-rr / 40.0)) + 0.105 * rr)
	if rr > 700.0:
		h -= (rr - 700.0) * 0.14
	# gullies and ridges running down the flank, bigger the further down
	h += sin(a * 23.0 + rr * 0.01) * minf(rr * 0.02, 5.0) + sin(a * 7.0 + 1.3) * minf(rr * 0.03, 10.0)
	h += sin(a * 3.0 - 0.7) * minf(rr * 0.02, 14.0)
	return h


func _build_flank(route: Array[Vector3]) -> void:
	var R: float = crater_r
	var radii: Array[float] = [0.0, R * 0.3, R * 0.55, R * 0.62, R * 0.7, R * 0.8, R * 0.88, R * 0.94, R * 0.98, R]
	var rr: float = 4.0
	while rr < 2700.0:
		radii.append(R + rr)
		rr = rr * 1.13 if rr > 30.0 else rr + 6.0
	var seg: int = 192
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p: Vector3 in route:
		lo = lo.min(Vector2(p.x, p.z))
		hi = hi.max(Vector2(p.x, p.z))
	lo -= Vector2(220, 220)
	hi += Vector2(220, 220)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in radii.size():
		var r: float = radii[i]
		for j: int in seg + 1:
			var a: float = TAU * float(j % seg) / float(seg)
			var x: float = cos(a) * r
			var z: float = sin(a) * r
			var h: float = _cone(r, a)
			if r > R and x > lo.x and x < hi.x and z > lo.y and z < hi.y:
				for p: Vector3 in route:
					var d: float = Vector2(x - p.x, z - p.z).length()
					if d < 200.0:
						h = minf(h, p.y - 18.0 + 0.32 * maxf(d - 9.0, 0.0))
			st.add_vertex(Vector3(x, h, z))
	var w: int = seg + 1
	for i: int in radii.size() - 1:
		for j: int in seg:
			var a0: int = i * w + j
			var b0: int = (i + 1) * w + j
			st.add_index(a0)
			st.add_index(a0 + 1)
			st.add_index(b0)
			st.add_index(a0 + 1)
			st.add_index(b0 + 1)
			st.add_index(b0)
	st.generate_normals()
	var mesh: ArrayMesh = st.commit()
	_terrain_mat = ShaderMaterial.new()
	_terrain_mat.shader = TERRAIN_SHADER
	_terrain_mat.set_shader_parameter("crater_r", R)
	_terrain_mat.set_shader_parameter("rim_y", rim_y)
	var mi := Look.mesh_node(mesh, _terrain_mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 400.0
	add_child(mi)


# ---- the crater and the lake ------------------------------------------------------------------------

func _build_crater() -> void:
	var R: float = crater_r
	_lake_mat = ShaderMaterial.new()
	_lake_mat.shader = nofog(LAVA_SHADER)
	_lake_mat.set_shader_parameter("scale", 0.05)
	_lake_mat.set_shader_parameter("crust", 0.3)
	_lake_mat.set_shader_parameter("heat", 1.6)
	_lake_mat.set_shader_parameter("flow", Vector2(0.0, 0.0))
	var disc := CylinderMesh.new()
	disc.top_radius = R * 0.66
	disc.bottom_radius = R * 0.66
	disc.height = 0.5
	disc.radial_segments = 48
	disc.rings = 1
	var lake := Look.mesh_node(disc, _lake_mat, Vector3(0, lake_y, 0))
	lake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lake)
	_lake_light = OmniLight3D.new()
	_lake_light.light_color = Color(1.0, 0.45, 0.12)
	_lake_light.light_energy = 6.0
	_lake_light.omni_range = R * 4.0
	_lake_light.omni_attenuation = 0.8
	_lake_light.position = Vector3(0, rim_y + 25.0, 0)
	add_child(_lake_light)
	# a glow halo hanging over the crater (reads from far below the rim)
	var halo := Fx.sprite(Color(1.0, 0.42, 0.12, 0.55), R * 4.5, Fx.Tex.DOT, true)
	(halo.material_override as StandardMaterial3D).disable_fog = true
	halo.position = Vector3(0, rim_y + R * 0.4, 0)
	add_child(halo)
	# rim smoke rolling up round the crater
	for i: int in 6:
		var a: float = TAU * float(i) / 6.0 + 0.4
		var sm: GPUParticles3D = VolcanoFx.smoke(self, Vector3(cos(a) * R * 0.85, rim_y - 4.0, sin(a) * R * 0.85), 10.0, 90.0, 10, Color(0.16, 0.1, 0.09, 0.5), 22.0)
		unfog(sm)


# ---- the fountain -----------------------------------------------------------------------------------

func _lava_colors() -> PackedColorArray:
	return PackedColorArray([Color(4.0, 3.2, 1.6, 1.0), Color(3.6, 1.6, 0.35, 1.0), Color(2.2, 0.5, 0.1, 0.8), Color(0.6, 0.1, 0.05, 0.0)])


func _build_fountain() -> void:
	var base := Vector3(0, lake_y + 1.0, 0)
	var aabb := AABB(Vector3(-500, -200, -500), Vector3(1000, 600, 1000))
	# the core jet: dense, fast, white-hot, arcing back into the crater
	var core: GPUParticles3D = Fx.emitter({"amount": 260, "lifetime": 5.5, "preprocess": 5.5, "shape": "sphere", "radius": 6.0,
		"dir": Vector3.UP, "spread": 9.0, "speed": Vector2(60.0, 104.0), "gravity": Vector3(0, -30.0, 0),
		"tex": Fx.Tex.DOT, "size": 7.0, "scale": Vector2(0.5, 1.3), "colors": _lava_colors(), "aabb": aabb})
	core.position = base
	add_child(unfog(core))
	# spatter: heavier clots thrown wider, raining onto the upper flanks
	var spatter: GPUParticles3D = Fx.emitter({"amount": 150, "lifetime": 6.0, "preprocess": 6.0, "shape": "sphere", "radius": 10.0,
		"dir": Vector3.UP, "spread": 32.0, "speed": Vector2(30.0, 60.0), "gravity": Vector3(0, -30.0, 0),
		"tex": Fx.Tex.DOT, "size": 4.5, "scale": Vector2(0.6, 1.4), "colors": _lava_colors(), "aabb": aabb})
	spatter.position = base
	add_child(unfog(spatter))
	# glowing gas boiling off the lake at the fountain's foot
	var boil: GPUParticles3D = Fx.emitter({"amount": 40, "lifetime": 3.0, "preprocess": 3.0, "shape": "sphere", "radius": crater_r * 0.35,
		"dir": Vector3.UP, "spread": 20.0, "speed": Vector2(6.0, 14.0), "tex": Fx.Tex.SMOKE, "additive": true, "size": 26.0,
		"curve": "puff", "angle": Vector2(0, 360), "color": Color(1.4, 0.45, 0.12, 0.35), "fade": PackedFloat32Array([0.0, 1.0, 0.0]), "aabb": aabb})
	boil.position = base
	add_child(unfog(boil))
	# the surge: a one-shot burst far above the usual fountain, and a ring of spatter
	_surge_burst = Fx.emitter({"amount": 320, "lifetime": 6.5, "one_shot": true, "explosiveness": 0.7, "shape": "sphere", "radius": 8.0,
		"dir": Vector3.UP, "spread": 14.0, "speed": Vector2(80.0, 135.0), "gravity": Vector3(0, -30.0, 0),
		"tex": Fx.Tex.DOT, "size": 8.0, "scale": Vector2(0.5, 1.4), "colors": _lava_colors(),
		"aabb": AABB(Vector3(-600, -200, -600), Vector3(1200, 900, 1200))})
	_surge_burst.position = base
	add_child(unfog(_surge_burst))
	_surge_spatter = Fx.emitter({"amount": 180, "lifetime": 6.0, "one_shot": true, "explosiveness": 0.8, "shape": "sphere", "radius": 12.0,
		"dir": Vector3.UP, "spread": 50.0, "speed": Vector2(45.0, 85.0), "gravity": Vector3(0, -30.0, 0),
		"tex": Fx.Tex.DOT, "size": 5.5, "scale": Vector2(0.6, 1.3), "colors": _lava_colors(),
		"aabb": AABB(Vector3(-600, -200, -600), Vector3(1200, 900, 1200))})
	_surge_spatter.position = base
	add_child(unfog(_surge_spatter))


# ---- the ash column and the anvil -------------------------------------------------------------------

func _plume_material(glow_base: float, glow_top: float, disp: float, scale: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = PLUME_SHADER
	m.set_shader_parameter("glow_base", glow_base)
	m.set_shader_parameter("glow_top", glow_top)
	m.set_shader_parameter("disp", disp)
	m.set_shader_parameter("noise_scale", scale)
	_plume_mats.append(m)
	return m


func _build_column() -> void:
	var R: float = crater_r
	var foot: float = rim_y + 10.0
	# the trunk: a tapered, billowing cylinder leaning a little downwind
	_column_mat = _plume_material(rim_y - 20.0, rim_y + 380.0, 34.0, 0.007)
	var cm := CylinderMesh.new()
	cm.bottom_radius = R * 0.5
	cm.top_radius = 210.0
	cm.height = column_h
	cm.radial_segments = 40
	cm.rings = 28
	cm.cap_top = false
	cm.cap_bottom = false
	var trunk := Look.mesh_node(cm, _column_mat, Vector3(0, foot + column_h * 0.5, 0) + WIND * 60.0)
	trunk.rotation = Vector3(WIND.z * 0.12, 0, -WIND.x * 0.12)
	trunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	trunk.extra_cull_margin = 200.0
	add_child(trunk)
	# rising puffs: they swell as they climb, drift downwind, fade out into the anvil
	var bm := SphereMesh.new()
	bm.radius = 1.0
	bm.height = 2.0
	bm.radial_segments = 24
	bm.rings = 12
	var puff_mat: ShaderMaterial = _plume_material(rim_y - 20.0, rim_y + 380.0, 0.22, 0.012)
	for i: int in 14:
		var b := Look.mesh_node(bm, puff_mat)
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		b.extra_cull_margin = 200.0
		add_child(b)
		_billows.append(b)
		var a: float = _rng.randf() * TAU
		_billow_base.append(Vector3(cos(a), _rng.randf(), sin(a)))
	# the anvil: flattened layers spreading downwind, underlit red, with sagging lumps beneath
	var top: float = foot + column_h
	_anvil_mat = _plume_material(top - 160.0, top + 140.0, 30.0, 0.004)
	_anvil_mat.set_shader_parameter("glow", 0.5)
	_anvil_mat.set_shader_parameter("glow_reach", 260.0)
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 40
	sm.rings = 20
	var layers: Array[Array] = [
		[Vector3(0, 0, 0), Vector3(760, 120, 560)],
		[WIND * 420.0 + Vector3(0, 30, 0), Vector3(700, 100, 520)],
		[WIND * 820.0 + Vector3(0, 60, 0), Vector3(620, 80, 460)],
		[WIND * 200.0 + Vector3(-WIND.z, 0, WIND.x) * 280.0 + Vector3(0, -20, 0), Vector3(420, 90, 380)],
		[WIND * 260.0 - Vector3(-WIND.z, 0, WIND.x) * 300.0 + Vector3(0, -10, 0), Vector3(440, 90, 360)],
	]
	for l: Array in layers:
		var n := Look.mesh_node(sm, _anvil_mat, Vector3(0, top, 0) + WIND * 120.0 + (l[0] as Vector3))
		n.scale = l[1]
		n.rotation.y = atan2(WIND.x, WIND.z)
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.extra_cull_margin = 400.0
		add_child(n)
	# mammatus: lumpy pouches hanging under the anvil, glowing from the fire below
	var lump_mat: ShaderMaterial = _plume_material(top - 260.0, top - 40.0, 12.0, 0.01)
	lump_mat.set_shader_parameter("glow", 0.6)
	lump_mat.set_shader_parameter("glow_reach", 320.0)
	for i: int in 9:
		var off: Vector3 = WIND * _rng.randf_range(0.0, 700.0) + Vector3(-WIND.z, 0, WIND.x) * _rng.randf_range(-320.0, 320.0)
		var n2 := Look.mesh_node(sm, lump_mat, Vector3(0, top - 90.0 - _rng.randf_range(0.0, 40.0), 0) + WIND * 120.0 + off)
		var s: float = _rng.randf_range(90.0, 150.0)
		n2.scale = Vector3(s, s * 0.55, s)
		n2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n2.extra_cull_margin = 200.0
		add_child(n2)
	# embers and ash sucked up the column
	var up: GPUParticles3D = Fx.emitter({"amount": 120, "lifetime": 9.0, "preprocess": 9.0, "shape": "sphere", "radius": R * 0.5,
		"dir": Vector3.UP, "spread": 12.0, "speed": Vector2(25.0, 45.0), "gravity": WIND * 3.0, "turbulence": 2.0,
		"turbulence_scale": 40.0, "tex": Fx.Tex.DOT, "size": 3.0, "scale": Vector2(0.4, 1.2), "color": Color(3.0, 1.1, 0.3),
		"fade": PackedFloat32Array([0.0, 1.0, 0.6, 0.0]), "aabb": AABB(Vector3(-600, -50, -600), Vector3(1200, 700, 1200))})
	up.position = Vector3(0, foot, 0)
	add_child(unfog(up))


# ---- lightning ----------------------------------------------------------------------------------------

func _build_lightning() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(2.2, 2.2, 3.6, 1.0)
	mat.disable_fog = true
	mat.disable_receive_shadows = true
	for i: int in 8:
		var mi := MeshInstance3D.new()
		mi.mesh = _bolt_mesh(_rng.randf_range(160.0, 320.0), _rng.randi_range(9, 14))
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		mi.extra_cull_margin = 300.0
		add_child(mi)
		_bolts.append(mi)
	_flash_light = OmniLight3D.new()
	_flash_light.light_color = Color(0.7, 0.72, 1.0)
	_flash_light.omni_range = 700.0
	_flash_light.omni_attenuation = 0.6
	_flash_light.light_energy = 0.0
	_flash_light.visible = false
	add_child(_flash_light)


## A jagged forked bolt (two crossed ribbons so it reads from any side), `length` long, falling along -Y.
func _bolt_mesh(length: float, steps: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array[Vector3] = [Vector3.ZERO]
	var p := Vector3.ZERO
	for i: int in steps:
		p += Vector3(_rng.randf_range(-1.0, 1.0) * length * 0.09, -length / float(steps), _rng.randf_range(-1.0, 1.0) * length * 0.09)
		pts.append(p)
	_ribbon(st, pts, 2.6)
	# a fork off the middle
	var f: Vector3 = pts[steps >> 1]
	var fork: Array[Vector3] = [f]
	for i: int in steps >> 1:
		f += Vector3(_rng.randf_range(-0.2, 1.0) * length * 0.1, -length / float(steps) * 0.8, _rng.randf_range(-1.0, 0.2) * length * 0.1)
		fork.append(f)
	_ribbon(st, fork, 1.5)
	return st.commit()


func _ribbon(st: SurfaceTool, pts: Array[Vector3], w: float) -> void:
	for side: Vector3 in [Vector3(w, 0, 0), Vector3(0, 0, w)]:
		for i: int in pts.size() - 1:
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[i + 1]
			st.add_vertex(a - side)
			st.add_vertex(a + side)
			st.add_vertex(b + side)
			st.add_vertex(a - side)
			st.add_vertex(b + side)
			st.add_vertex(b - side)


# ---- lava bombs lobbed out of the crater (visual) ---------------------------------------------------

func _build_bombs() -> void:
	var core: StandardMaterial3D = _glow_mat(Color(1.0, 0.5, 0.12), 5.0)
	for i: int in 10:
		var n := Node3D.new()
		n.add_child(Look.sphere(3.0, core))
		var trail: GPUParticles3D = Fx.emitter({"amount": 40, "lifetime": 2.2, "fixed_fps": 0, "tex": Fx.Tex.SMOKE, "additive": false,
			"size": 9.0, "speed": Vector2(0.0, 2.0), "spread": 180.0, "curve": "puff", "angle": Vector2(0, 360),
			"color": Color(0.16, 0.12, 0.11, 0.75), "fade": PackedFloat32Array([0.0, 0.9, 0.0]),
			"aabb": AABB(Vector3(-700, -300, -700), Vector3(1400, 900, 1400))})
		trail.local_coords = false
		n.add_child(unfog(trail))
		var sparks: GPUParticles3D = Fx.trail({"amount": 30, "lifetime": 0.8, "size": 4.0, "color": Color(3.0, 1.2, 0.3),
			"emitting": true, "aabb": AABB(Vector3(-700, -300, -700), Vector3(1400, 900, 1400))})
		sparks.local_coords = false
		n.add_child(unfog(sparks))
		n.visible = false
		add_child(n)
		var a: float = TAU * (float(i) + _rng.randf() * 0.7) / 10.0
		var spd: float = _rng.randf_range(38.0, 62.0)
		var tilt: float = _rng.randf_range(0.28, 0.5)
		_bombs.append({"node": n, "trail": trail, "sparks": sparks, "period": _rng.randf_range(4.5, 8.5), "phase": _rng.randf(),
			"v": Vector3(cos(a) * spd * tilt, spd, sin(a) * spd * tilt), "was": false})


func _bomb_update(t: float) -> void:
	for b: Dictionary in _bombs:
		var per: float = float(b["period"])
		var s: float = fposmod(t + float(b["phase"]) * per, per)
		var v: Vector3 = b["v"]
		var p: Vector3 = Vector3(0, lake_y + 4.0, 0) + v * s + Vector3(0, -15.0 * s * s, 0)
		var flying: bool = s < per * 0.95 and p.y > rim_y - 140.0
		var n: Node3D = b["node"]
		if flying:
			if not bool(b["was"]):
				n.visible = true
				n.position = p
				n.reset_physics_interpolation()
				(b["trail"] as GPUParticles3D).restart()
			n.position = p
		elif bool(b["was"]):
			n.visible = false
		(b["trail"] as GPUParticles3D).emitting = flying
		(b["sparks"] as GPUParticles3D).emitting = flying
		b["was"] = flying


# ---- the live eruption ---------------------------------------------------------------------------------

## 0..1: how hard the mountain is surging at `t` (a spike at each surge, easing off over ~5 s).
func surge_at(t: float) -> float:
	var s: float = fposmod(t + SURGE_OFFSET, SURGE_PERIOD)
	if s < 0.4:
		return s / 0.4
	return clampf(exp(-(s - 0.4) / 1.8), 0.0, 1.0)


## Sets off a surge now (the finish).
func force_surge() -> void:
	_fire_surge(1.4)


func _fire_surge(strength: float) -> void:
	_surge_burst.restart()
	_surge_spatter.restart()
	Fx.pulse(_lake_light, 16.0 * strength, 6.0, 3.0)
	surged.emit(strength)
	if WorldAudio.enabled():
		Sfx.play("eruption_boom", 0.04, 0.9)


func _process(_dt: float) -> void:
	var t: float = Game.course_time
	var k: int = int(floor((t + SURGE_OFFSET) / SURGE_PERIOD))
	if k != _last_surge:
		if _last_surge != -999 and fposmod(t + SURGE_OFFSET, SURGE_PERIOD) < 1.0:
			_fire_surge(1.0)
		_last_surge = k
	var surge: float = surge_at(t)
	_terrain_mat.set_shader_parameter("heat", 1.0 + 0.9 * surge)
	_lake_mat.set_shader_parameter("heat", 1.6 + 1.4 * surge)
	_column_mat.set_shader_parameter("glow", 1.0 + 1.3 * surge)
	_bomb_update(t)
	_billow_update(t)
	_lightning_update(t, surge)


func _billow_update(t: float) -> void:
	var foot: float = rim_y + 20.0
	for i: int in _billows.size():
		var base: Vector3 = _billow_base[i]
		var life: float = 60.0
		var s: float = fposmod(t + base.y * life + float(i) * life / float(_billows.size()), life) / life
		var h: float = foot + s * (column_h - 60.0)
		var radius: float = lerpf(crater_r * 0.45, 230.0, pow(s, 0.8))
		var side: Vector3 = Vector3(base.x, 0, base.z) * radius * 0.35
		var b: MeshInstance3D = _billows[i]
		b.position = Vector3(0, h, 0) + WIND * (60.0 + s * 160.0) + side
		b.scale = Vector3(radius, radius * 0.8, radius)
		b.set_instance_shader_parameter("fade", clampf(s * 8.0, 0.0, 1.0) * clampf((1.0 - s) * 4.0, 0.0, 1.0) * 0.85)


func _lightning_update(t: float, surge: float) -> void:
	var slot: int = int(floor(t / 0.42))
	if slot != _last_slot:
		_last_slot = slot
		var h: float = fposmod(sin(float(slot) * 12.9898) * 43758.5453, 1.0)
		var chance: float = 0.16 + 0.55 * surge
		if h < chance:
			_strike(slot, t)
	var flash: float = 0.0
	if _bolt_on >= 0:
		var left: float = _bolt_until - t
		if left <= 0.0 or left > 1.0:
			_bolts[_bolt_on].visible = false
			_bolt_on = -1
		else:
			# a stuttering double flicker
			var on: bool = fposmod(left * 23.0, 1.0) > 0.3
			_bolts[_bolt_on].visible = on
			flash = (1.0 if on else 0.35) * clampf(left / 0.22, 0.0, 1.0)
	for m: ShaderMaterial in _plume_mats:
		m.set_shader_parameter("flash", flash)
		m.set_shader_parameter("glow_center", global_position)
	_flash_light.visible = flash > 0.01
	_flash_light.light_energy = flash * 5.0


func _strike(slot: int, t: float) -> void:
	var h1: float = fposmod(sin(float(slot) * 78.233) * 43758.5453, 1.0)
	var h2: float = fposmod(sin(float(slot) * 39.346) * 12345.6789, 1.0)
	var h3: float = fposmod(sin(float(slot) * 7.1) * 9876.543, 1.0)
	if _bolt_on >= 0:
		_bolts[_bolt_on].visible = false
	_bolt_on = int(h1 * float(_bolts.size())) % _bolts.size()
	# inside the column (low) or out under the anvil (high)
	var y: float = rim_y + lerpf(260.0, column_h + 20.0, h2)
	var spread: float = lerpf(60.0, 420.0, h2)
	var pos := Vector3(0, y, 0) + WIND * (h3 * spread) + Vector3(-WIND.z, 0, WIND.x) * ((h1 - 0.5) * spread)
	var b: MeshInstance3D = _bolts[_bolt_on]
	b.position = pos
	b.rotation.y = h3 * TAU
	b.visible = true
	_bolt_until = t + 0.22
	for m: ShaderMaterial in _plume_mats:
		m.set_shader_parameter("flash_pos", global_position + pos + Vector3(0, -80.0, 0))
	_flash_light.position = pos + Vector3(0, -120.0, 0)
	lightning.emit(global_position + pos, 0.6 + 0.4 * h2)
