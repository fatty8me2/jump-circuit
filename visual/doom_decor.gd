class_name DoomDecor
extends RefCounted
## Doom Fortress set dressing, all built from primitives: black-iron girders and riveted columns
## running down into the pits, lattice trusses, colossal gears turning in the dark, background rams
## pumping, smoke stacks, pipe runs, hazard-striped bands, rotating red alarm beacons, molten forge
## channels far below and warning lamps. Nothing here collides unless it says so. Materials are cached.

const MOLTEN_SHADER: Shader = preload("res://visual/doom_molten.gdshader")
const ANIM: Script = preload("res://visual/doom_anim.gd")

const ALARM := Color(1.0, 0.08, 0.04)
const MOLTEN := Color(1.0, 0.45, 0.08)
const HAZARD := Color(1.0, 0.62, 0.06)
const IRON := Color(0.07, 0.07, 0.075)
const GUNMETAL := Color(0.24, 0.25, 0.27)
const RUST := Color(0.26, 0.11, 0.05)

const HAZARD_CODE: String = """
shader_type spatial;
uniform vec3 stripe_color : source_color = vec3(1.0, 0.62, 0.06);
uniform float glow = 0.0;
uniform float freq = 1.6;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float s = step(0.5, fract((wp.x + wp.y + wp.z) * freq));
	vec3 c = mix(vec3(0.03, 0.03, 0.03), stripe_color, s);
	ALBEDO = c;
	ROUGHNESS = 0.7;
	METALLIC = 0.1;
	EMISSION = stripe_color * s * clamp(glow, 0.0, 3.0);
}
"""

static var _mats: Dictionary = {}
static var _hazard_shader: Shader

var root: Node3D
var rng: RandomNumberGenerator


func _init(level_root: Node3D, r: RandomNumberGenerator) -> void:
	root = level_root
	rng = r
	_mats.clear()


func _add(n: Node3D, pos: Vector3) -> Node3D:
	n.position = pos
	root.add_child(n)
	return n


static func ns(mi: GeometryInstance3D) -> GeometryInstance3D:
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# ---- materials ------------------------------------------------------------------------------

static func iron() -> StandardMaterial3D:
	return Look.flat(IRON, 0.55, 0.75)


static func steel() -> StandardMaterial3D:
	return Look.flat(GUNMETAL, 0.45, 0.8)


static func rust() -> StandardMaterial3D:
	return Look.flat(RUST, 0.85, 0.3)


static func alarm(emit: float = 3.0) -> StandardMaterial3D:
	return Look.flat(ALARM, 0.3, 0.0, emit)


static func hot(emit: float = 2.5) -> StandardMaterial3D:
	return Look.flat(MOLTEN, 0.3, 0.0, emit)


static func hazard(glow: float = 0.0) -> ShaderMaterial:
	var key: String = "hz|%.2f" % glow
	if _mats.has(key):
		return _mats[key]
	if _hazard_shader == null:
		_hazard_shader = Shader.new()
		_hazard_shader.code = HAZARD_CODE
	var m := ShaderMaterial.new()
	m.shader = _hazard_shader
	m.set_shader_parameter("glow", glow)
	_mats[key] = m
	return m


static func molten(flow: Vector2 = Vector2.ZERO, heat: float = 1.6, crust: float = 0.45, scale: float = 0.5) -> ShaderMaterial:
	var key: String = "mo|%.2f|%.2f|%.2f|%.2f|%.2f" % [flow.x, flow.y, heat, crust, scale]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = MOLTEN_SHADER
	m.set_shader_parameter("flow", flow)
	m.set_shader_parameter("heat", heat)
	m.set_shader_parameter("crust", crust)
	m.set_shader_parameter("scale", scale)
	_mats[key] = m
	return m


## A fake light beam (additive, unshaded, transparent) for beacons and the reactor's shafts.
static func beam_material(col: Color, alpha: float = 0.22) -> StandardMaterial3D:
	var key: String = "bm|%s|%.2f" % [col.to_html(), alpha]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(col.r, col.g, col.b, alpha)
	_mats[key] = m
	return m


# ---- structure ------------------------------------------------------------------------------

## An I-beam from a to b (web + two flanges). `w` is the flange width.
func girder(a: Vector3, b: Vector3, w: float = 0.5, mat: Material = null) -> Node3D:
	var d: Vector3 = b - a
	var len: float = d.length()
	if len < 0.05:
		return null
	var m: Material = mat if mat != null else iron()
	var g := Node3D.new()
	g.add_child(Look.box(Vector3(w * 0.18, w, len), m))
	for s: float in [-1.0, 1.0]:
		g.add_child(Look.box(Vector3(w, w * 0.14, len), m, Vector3(0, s * w * 0.5, 0)))
	_add(g, (a + b) * 0.5)
	var f: Vector3 = d / len
	var up: Vector3 = Vector3.UP if absf(f.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	g.basis = Basis.looking_at(f, up)
	return g


## A riveted square column from `top` down to `bottom_y`, with a collar of hazard stripes near the top.
func column(top: Vector3, bottom_y: float, w: float = 0.8, collar: bool = true) -> void:
	var h: float = top.y - bottom_y
	if h < 0.5:
		return
	_add(Look.box(Vector3(w, h, w), iron()), Vector3(top.x, top.y - h * 0.5, top.z))
	for s: float in [-1.0, 1.0]:
		_add(Look.box(Vector3(w * 1.25, 0.18, w * 1.25), steel()), Vector3(top.x, top.y - 0.4 - (0.0 if s > 0.0 else 3.0), top.z))
	if collar:
		_add(ns(Look.box(Vector3(w * 1.08, 0.5, w * 1.08), hazard())), Vector3(top.x, top.y - 1.0, top.z))


## A lattice truss between a and b (two chords and zig-zag diagonals), depth `h` straight down.
func truss(a: Vector3, b: Vector3, h: float = 2.0, n: int = 6) -> void:
	girder(a, b, 0.4)
	girder(a - Vector3(0, h, 0), b - Vector3(0, h, 0), 0.4)
	for i: int in n:
		var p0: Vector3 = a.lerp(b, float(i) / float(n))
		var p1: Vector3 = a.lerp(b, float(i + 1) / float(n))
		if i % 2 == 0:
			girder(p0, p1 - Vector3(0, h, 0), 0.22)
		else:
			girder(p0 - Vector3(0, h, 0), p1, 0.22)


## A riveted black-iron wall slab (backing behind wall runs, bulkheads). Local X along `yaw`.
func wall_slab(center: Vector3, size: Vector3, yaw_deg: float = 0.0, lights: bool = true) -> Node3D:
	var n := Node3D.new()
	n.add_child(Look.box(size, iron()))
	# plate seams and a red strip light along the top
	var ribs: int = int(size.x / 3.0)
	for i: int in ribs:
		var x: float = -size.x * 0.5 + (float(i) + 0.5) * size.x / float(ribs)
		n.add_child(Look.box(Vector3(0.18, size.y, size.z + 0.12), steel(), Vector3(x, 0, 0)))
	if lights:
		n.add_child(ns(Look.box(Vector3(size.x, 0.12, size.z + 0.16), alarm(2.2), Vector3(0, size.y * 0.5 - 0.6, 0))) as Node3D)
	n.rotation_degrees.y = yaw_deg
	_add(n, center)
	return n


func hazard_band(center: Vector3, size: Vector3, yaw_deg: float = 0.0, glow: float = 0.0) -> void:
	var mi: MeshInstance3D = Look.box(size, hazard(glow))
	mi.rotation_degrees.y = yaw_deg
	_add(ns(mi), center)


func pipe(a: Vector3, b: Vector3, r: float = 0.3, mat: Material = null) -> void:
	var d: Vector3 = b - a
	var len: float = d.length()
	if len < 0.05:
		return
	var n := Look.cylinder(r, len, mat if mat != null else steel(), Vector3.ZERO, -1.0, 10)
	_add(n, (a + b) * 0.5)
	var up: Vector3 = d / len
	var side: Vector3 = up.cross(Vector3(0.123, 0.4, 0.9)).normalized()
	n.basis = Basis(side, up, side.cross(up))
	# flanges at both ends
	for p: Vector3 in [a, b]:
		var fl := Look.cylinder(r * 1.45, 0.16, iron(), Vector3.ZERO, -1.0, 10)
		_add(fl, p.lerp((a + b) * 0.5, 0.06))
		fl.basis = n.basis


## A hanging chain of `links` from `top`.
func chain(top: Vector3, length: float) -> void:
	var links: int = int(length / 0.36)
	var m: StandardMaterial3D = iron()
	for i: int in links:
		var tm := Look.box(Vector3(0.12, 0.34, 0.05) if i % 2 == 0 else Vector3(0.05, 0.34, 0.12), m)
		_add(tm, top - Vector3(0, 0.18 + 0.32 * float(i), 0))


# ---- machinery ---------------------------------------------------------------------------------

## A colossal gear turning in the dark (visual). `rot_deg` orients its axle (90,0,0 = axle along Z).
func gear(pos: Vector3, radius: float, teeth: int, thick: float, period: float, rot_deg: Vector3 = Vector3(90, 0, 0), hot_teeth: bool = false) -> Node3D:
	var holder := Node3D.new()
	holder.rotation_degrees = rot_deg
	var g := Node3D.new()
	g.set_script(preload("res://visual/spin.gd"))
	g.set("period", period)
	var body: StandardMaterial3D = iron()
	g.add_child(Look.cylinder(radius * 0.84, thick, body, Vector3.ZERO, -1.0, 40))
	g.add_child(Look.cylinder(radius * 0.88, thick * 0.6, steel(), Vector3.ZERO, -1.0, 40))
	g.add_child(Look.cylinder(radius * 0.22, thick * 1.6, steel(), Vector3.ZERO, -1.0, 16))
	g.add_child(ns(Look.cylinder(radius * 0.1, thick * 1.7, alarm(2.0), Vector3.ZERO, -1.0, 12)) as Node3D)
	var tooth_mat: StandardMaterial3D = hot(1.2) if hot_teeth else steel()
	for i: int in teeth:
		var a: float = float(i) / float(teeth) * TAU
		var tooth := Look.box(Vector3(radius * 0.2, thick * 0.96, TAU * radius / float(teeth) * 0.5), tooth_mat, Vector3(cos(a), 0, sin(a)) * radius * 0.94)
		tooth.rotation.y = -a
		g.add_child(tooth)
	# lightening holes (dark discs) between hub and rim
	for i: int in 6:
		var a2: float = float(i) / 6.0 * TAU + 0.3
		g.add_child(Look.cylinder(radius * 0.16, thick * 1.02, Look.flat(Color(0.02, 0.02, 0.02), 0.9), Vector3(cos(a2), 0, sin(a2)) * radius * 0.55, -1.0, 14))
	holder.add_child(g)
	_add(holder, pos)
	return holder


## A ram pumping in the background: a housing and a rod sliding along local Y (rot_deg orients it).
func pump(pos: Vector3, length: float, radius: float, period: float, rot_deg: Vector3 = Vector3.ZERO) -> void:
	var holder := Node3D.new()
	holder.rotation_degrees = rot_deg
	holder.add_child(Look.cylinder(radius * 1.3, length * 0.55, iron(), Vector3(0, length * 0.275, 0), -1.0, 16))
	holder.add_child(ns(Look.cylinder(radius * 1.35, 0.3, hazard(), Vector3(0, length * 0.5, 0), -1.0, 16)) as Node3D)
	var rod := Node3D.new()
	rod.set_script(ANIM)
	rod.set("mode", "pump")
	rod.set("period", period)
	rod.set("axis", Vector3.UP)
	rod.set("amount", length * 0.4)
	rod.position = Vector3(0, length * 0.3, 0)
	rod.add_child(Look.cylinder(radius * 0.6, length * 0.6, steel(), Vector3(0, length * 0.3, 0), -1.0, 12))
	rod.add_child(Look.box(Vector3(radius * 3.0, radius * 1.2, radius * 3.0), iron(), Vector3(0, length * 0.62, 0)))
	holder.add_child(rod)
	_add(holder, pos)


## A rotating red alarm beacon: a squat base, a red glass dome and two light blades sweeping round.
## `light` adds a real red OmniLight3D (use sparingly).
func beacon(pos: Vector3, period: float = 1.4, light: bool = false, scale: float = 1.0) -> void:
	var b := Node3D.new()
	b.add_child(Look.cylinder(0.32 * scale, 0.22 * scale, iron(), Vector3(0, 0.11 * scale, 0), -1.0, 12))
	b.add_child(ns(Look.sphere(0.26 * scale, alarm(3.5), Vector3(0, 0.3 * scale, 0))) as Node3D)
	var spin := Node3D.new()
	spin.set_script(ANIM)
	spin.set("mode", "beacon")
	spin.set("period", period)
	spin.position = Vector3(0, 0.3 * scale, 0)
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05 * scale
	cm.bottom_radius = 1.4 * scale
	cm.height = 6.0 * scale
	cm.radial_segments = 10
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	for s: float in [-1.0, 1.0]:
		var blade := Look.mesh_node(cm, beam_material(ALARM, 0.16), Vector3(s * 3.0 * scale, 0, 0))
		blade.rotation.z = s * PI * 0.5
		ns(blade)
		spin.add_child(blade)
	b.add_child(spin)
	if light:
		var o := OmniLight3D.new()
		o.light_color = Color(1.0, 0.12, 0.05)
		o.light_energy = 2.2
		o.omni_range = 10.0 * scale
		o.position = Vector3(0, 0.5 * scale, 0)
		b.add_child(o)
	_add(b, pos)


## A warning lamp on a short bracket (visual; the caller drives its material's emission).
func lamp(pos: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	_add(Look.box(Vector3(0.16, 0.4, 0.16), iron()), pos - Vector3(0, 0.25, 0))
	var bulb: MeshInstance3D = Look.sphere(0.2, mat, pos)
	root.add_child(ns(bulb))
	return bulb


## A smoke stack with a fire-lit mouth and smoke (far scenery).
func stack(pos: Vector3, height: float, radius: float) -> void:
	var s := Node3D.new()
	s.add_child(Look.cylinder(radius, height, iron(), Vector3(0, height * 0.5, 0), radius * 0.8, 16))
	for i: int in 3:
		s.add_child(Look.cylinder(radius * (1.02 - float(i) * 0.06), 0.4, steel(), Vector3(0, height * (0.25 + float(i) * 0.25), 0), -1.0, 16))
	s.add_child(ns(Look.cylinder(radius * 0.75, 0.3, hot(2.2), Vector3(0, height + 0.05, 0), -1.0, 16)) as Node3D)
	var smoke: GPUParticles3D = Fx.emitter({"amount": 16, "lifetime": 7.0, "shape": "sphere", "radius": radius * 0.5,
		"dir": Vector3(0.2, 1, 0), "spread": 12.0, "speed": Vector2(2.0, 3.5), "gravity": Vector3(0.4, 0.2, 0),
		"tex": Fx.Tex.SMOKE, "additive": false, "size": radius * 3.0, "curve": "puff", "angle": Vector2(0, 360),
		"color": Color(0.12, 0.06, 0.05, 0.45), "fade": PackedFloat32Array([0.0, 0.9, 0.0]), "preprocess": 7.0,
		"aabb": AABB(Vector3(-25, -5, -25), Vector3(50, 50, 50))})
	smoke.position = Vector3(0, height + 0.4, 0)
	s.add_child(smoke)
	_add(s, pos)


## A molten forge channel far below (visual): a glowing trough with iron walls, flowing along `yaw`.
func channel(center: Vector3, length: float, width: float, yaw_deg: float = 0.0, flow_speed: float = 1.5) -> void:
	var n := Node3D.new()
	var f: Vector3 = Basis(Vector3.UP, deg_to_rad(yaw_deg)) * Vector3(0, 0, -1)
	var flow := Vector2(f.x, f.z) * flow_speed
	var melt := Look.box(Vector3(width, 0.3, length), molten(flow, 1.7, 0.4, 0.35))
	melt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(melt)
	for s: float in [-1.0, 1.0]:
		n.add_child(Look.box(Vector3(0.8, 1.6, length), iron(), Vector3(s * (width * 0.5 + 0.4), 0.4, 0)))
	n.rotation_degrees.y = yaw_deg
	_add(n, center)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.42, 0.12)
	light.light_energy = 2.4
	light.omni_range = maxf(length * 0.5, 12.0)
	light.position = center + Vector3(0, 3.0, 0)
	root.add_child(light)


## A railing along one side of a walkway (visual): posts every ~1.5 m and two rails. a -> b along the edge.
func railing(a: Vector3, b: Vector3, height: float = 1.0) -> void:
	var d: Vector3 = b - a
	var len: float = d.length()
	if len < 0.3:
		return
	var n: int = maxi(int(len / 1.5), 1)
	for i: int in n + 1:
		var p: Vector3 = a.lerp(b, float(i) / float(n))
		_add(Look.box(Vector3(0.06, height, 0.06), steel()), p + Vector3(0, height * 0.5, 0))
	girder(a + Vector3(0, height, 0), b + Vector3(0, height, 0), 0.08, hazard())
	girder(a + Vector3(0, height * 0.5, 0), b + Vector3(0, height * 0.5, 0), 0.05, steel())
