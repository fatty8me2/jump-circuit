class_name AbyssDecor
extends RefCounted
## The Abyss set dressing, all built from primitives: trench rock (one shared world-space shader
## speckled with breathing bioluminescent spots), rock columns under the course, glowing kelp,
## tube-worm thickets, black-smoker chimneys, anemones, drifting jellyfish, whale bones, light
## shafts that die out long before the bottom, and the trench floor far below. Nothing here
## collides. Materials are cached.

const WALL: Shader = preload("res://visual/abyss_wall.gdshader")
const SHAFT: Shader = preload("res://visual/abyss_shaft.gdshader")
const BOB: Script = preload("res://visual/abyss_bob.gd")

const CYAN := Color(0.1, 1.0, 0.85)
const GREEN := Color(0.35, 1.0, 0.45)
const VIOLET := Color(0.7, 0.35, 1.0)
const PINK := Color(1.0, 0.35, 0.8)

static var _mats: Dictionary = {}

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


static func _ns(mi: GeometryInstance3D) -> GeometryInstance3D:
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func pick_glow() -> Color:
	return [CYAN, GREEN, VIOLET, PINK][rng.randi() % 4]


static func wall_mat(spots: float = 0.6) -> ShaderMaterial:
	var key: String = "w|%.2f" % spots
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = WALL
	m.set_shader_parameter("spots", spots)
	_mats[key] = m
	return m


static func bone_mat() -> StandardMaterial3D:
	if _mats.has("bone"):
		return _mats["bone"]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.62, 0.66, 0.6)
	m.roughness = 0.85
	m.emission_enabled = true
	m.emission = Color(0.35, 0.55, 0.5)
	m.emission_energy_multiplier = 0.18
	_mats["bone"] = m
	return m


# ---- rock ---------------------------------------------------------------------------------------

## A block of trench rock (scenery), centre position.
func rock(center: Vector3, size: Vector3, yaw: float = 0.0, spots: float = 0.6) -> MeshInstance3D:
	var mi := Look.box(size, wall_mat(spots), center)
	mi.rotation.y = yaw
	root.add_child(mi)
	return mi


## A tapered rock column from `top` down to `bottom_y` (under small landings).
func column(top: Vector3, r: float, bottom_y: float) -> void:
	var h: float = top.y - bottom_y
	if h < 0.8:
		return
	var mi := Look.cylinder(r * 1.6, h, wall_mat(0.4), Vector3(top.x, top.y - h * 0.5, top.z), r, 8)
	mi.rotation.y = rng.randf() * TAU
	root.add_child(mi)


## A great jagged spire of rock rising out of the dark (far scenery).
func spire(base: Vector3, height: float, r: float) -> void:
	var n := Node3D.new()
	var segs: int = 3
	var y: float = 0.0
	for i: int in segs:
		var h: float = height / float(segs)
		var r0: float = r * (1.0 - float(i) / float(segs) * 0.8)
		var r1: float = r * (1.0 - float(i + 1) / float(segs) * 0.8)
		var c := Look.cylinder(r0, h, wall_mat(0.8), Vector3(rng.randf_range(-0.4, 0.4) * r0, y + h * 0.5, 0), r1, 7)
		c.rotation.y = rng.randf() * TAU
		n.add_child(c)
		y += h
	_add(n, base)


# ---- life ---------------------------------------------------------------------------------------

## A strand of glowing kelp swaying up from `base`.
func kelp(base: Vector3, height: float, tint: Color) -> void:
	var n := Node3D.new()
	n.set_script(BOB)
	n.set("bob", 0.0)
	n.set("sway_deg", rng.randf_range(4.0, 8.0))
	n.set("period", rng.randf_range(4.0, 7.0))
	var stem: StandardMaterial3D = Look.flat(Color(0.05, 0.12, 0.1), 0.7, 0.0)
	var glow: StandardMaterial3D = Look.flat(tint, 0.4, 0.0, 2.2)
	var segs: int = maxi(int(height / 1.2), 2)
	for i: int in segs:
		var y: float = (float(i) + 0.5) * height / float(segs)
		var s := Look.box(Vector3(0.12, height / float(segs) + 0.05, 0.12), stem, Vector3(sin(y * 0.6) * 0.3, y, 0))
		n.add_child(s)
		var leaf := Look.box(Vector3(0.7, 0.04, 0.25), stem, Vector3(sin(y * 0.6) * 0.3, y, 0))
		leaf.rotation = Vector3(0.3, rng.randf() * TAU, 0.5)
		n.add_child(leaf)
		if i % 2 == 0:
			n.add_child(_ns(Look.sphere(0.09, glow, Vector3(sin(y * 0.6) * 0.3 + 0.12, y, 0))))
	_add(n, base)


## A thicket of tube worms: white tubes with blood-red glowing plumes.
func worms(base: Vector3, count: int, spread: float = 0.8) -> void:
	var tube: StandardMaterial3D = Look.flat(Color(0.85, 0.85, 0.8), 0.6)
	var plume: StandardMaterial3D = Look.flat(Color(1.0, 0.12, 0.15), 0.5, 0.0, 1.6)
	var n := Node3D.new()
	for i: int in count:
		var h: float = rng.randf_range(0.6, 1.8)
		var p := Vector3(rng.randf_range(-spread, spread), h * 0.5, rng.randf_range(-spread, spread))
		var t := Look.cylinder(0.06, h, tube, p, 0.05, 6)
		t.rotation = Vector3(rng.randf_range(-0.15, 0.15), 0, rng.randf_range(-0.15, 0.15))
		n.add_child(t)
		var pl := Look.sphere(0.11, plume, p + Vector3(0, h * 0.5 + 0.05, 0))
		pl.scale = Vector3(1, 1.6, 1)
		n.add_child(_ns(pl))
	_add(n, base)


## A small glowing anemone.
func anemone(base: Vector3, tint: Color, r: float = 0.4) -> void:
	var n := Node3D.new()
	n.add_child(Look.cylinder(r * 0.6, 0.3, Look.flat(tint.darkened(0.6), 0.6), Vector3(0, 0.15, 0), r * 0.5, 10))
	var arm := CylinderMesh.new()
	arm.top_radius = 0.0
	arm.bottom_radius = 0.04
	arm.height = r * 1.4
	arm.radial_segments = 4
	arm.rings = 1
	var glow: StandardMaterial3D = Look.flat(tint, 0.4, 0.0, 2.0)
	for i: int in 10:
		var a: float = TAU * float(i) / 10.0
		var mi := Look.mesh_node(arm, glow, Vector3(cos(a) * r * 0.35, 0.3 + r * 0.6, sin(a) * r * 0.35))
		mi.rotation = Vector3(sin(a) * 0.5, 0, -cos(a) * 0.5)
		n.add_child(_ns(mi))
	_add(n, base)


## A black-smoker chimney: a stack of crusted rock, glowing at its throat, pouring black smoke.
func chimney(base: Vector3, height: float, smoke: bool = true) -> void:
	var n := Node3D.new()
	var segs: int = 4
	for i: int in segs:
		var h: float = height / float(segs)
		var r0: float = lerpf(1.1, 0.45, float(i) / float(segs))
		var r1: float = lerpf(1.1, 0.45, float(i + 1) / float(segs))
		var c := Look.cylinder(r0, h, wall_mat(0.2), Vector3(rng.randf_range(-0.1, 0.1), (float(i) + 0.5) * h, 0), r1, 9)
		n.add_child(c)
	var throat := Look.cylinder(0.32, 0.2, Look.flat(Color(1.0, 0.45, 0.12), 0.4, 0.0, 3.0), Vector3(0, height + 0.02, 0), -1.0, 10)
	n.add_child(_ns(throat))
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.45, 0.15)
	l.light_energy = 1.2
	l.omni_range = 5.0
	l.position = Vector3(0, height + 0.6, 0)
	n.add_child(l)
	_add(n, base)
	if smoke:
		AbyssFx.smoker(root, base + Vector3(0, height + 0.3, 0), 12.0, 16)
	worms(base + Vector3(1.4, 0, 0.4), 6, 0.6)


## A jellyfish drifting in the dark (decoration only - keep it off the course).
func jelly(pos: Vector3, r: float, tint: Color) -> void:
	var n := Node3D.new()
	n.set_script(BOB)
	n.set("bob", rng.randf_range(0.4, 1.2))
	n.set("period", rng.randf_range(4.0, 8.0))
	n.set("drift", Vector3(rng.randf_range(-1.5, 1.5), 0, rng.randf_range(-1.5, 1.5)))
	var bell_mat := StandardMaterial3D.new()
	bell_mat.albedo_color = Color(tint.r, tint.g, tint.b, 0.35)
	bell_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bell_mat.emission_enabled = true
	bell_mat.emission = tint
	bell_mat.emission_energy_multiplier = 1.4
	bell_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.is_hemisphere = true
	sm.radial_segments = 16
	sm.rings = 6
	var bell := Look.mesh_node(sm, bell_mat)
	bell.scale = Vector3(1, 0.7, 1)
	n.add_child(_ns(bell))
	n.add_child(_ns(Look.sphere(r * 0.35, Look.flat(tint, 0.3, 0.0, 3.0), Vector3(0, r * 0.2, 0))))
	var ten: StandardMaterial3D = Look.flat(Color(tint.r, tint.g, tint.b, 0.6), 0.5, 0.0, 1.2)
	for i: int in 6:
		var a: float = TAU * float(i) / 6.0
		var tl: float = r * rng.randf_range(2.0, 4.0)
		n.add_child(_ns(Look.box(Vector3(0.03, tl, 0.03), ten, Vector3(cos(a) * r * 0.6, -tl * 0.5, sin(a) * r * 0.6))))
	_add(n, pos)


# ---- bones and light ------------------------------------------------------------------------------

## One curved whale rib: a chain of bone segments arching from `base` up and over (local frame
## turned by `yaw`; it curves toward local +X).
func rib(base: Vector3, height: float, reach: float, yaw: float, thick: float = 0.35) -> void:
	var n := Node3D.new()
	var segs: int = 7
	var prev := Vector3.ZERO
	for i: int in segs:
		var k: float = float(i + 1) / float(segs)
		var p := Vector3(reach * (1.0 - cos(k * PI * 0.5)), height * sin(k * PI * 0.5), 0)
		var mid: Vector3 = (prev + p) * 0.5
		var d: Vector3 = p - prev
		var seg := Look.cylinder(thick * (1.0 - 0.4 * k), d.length() + 0.1, bone_mat(), mid, thick * (1.0 - 0.4 * k) * 0.9, 8)
		var up: Vector3 = d.normalized()
		var side: Vector3 = up.cross(Vector3(0, 0, 1)).normalized()
		seg.basis = Basis(side, up, side.cross(up)).orthonormalized()
		n.add_child(seg)
		prev = p
	n.rotation.y = yaw
	_add(n, base)


## A shaft of the last surface light slanting down into the trench, dying out before the bottom.
func shaft(top: Vector3, radius: float, length: float, tilt: Vector3, strength: float = 0.25) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = radius * 0.6
	cm.bottom_radius = radius
	cm.height = length
	cm.radial_segments = 16
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	var m := ShaderMaterial.new()
	m.shader = SHAFT
	m.set_shader_parameter("strength", strength)
	var holder := Node3D.new()
	holder.rotation = tilt
	var mi := Look.mesh_node(cm, m, Vector3(0, -length * 0.5, 0))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(mi)
	_add(holder, top)


## The trench floor far below: a broad slab of dark rock (cheap) with silt drifting over it.
func trench_floor(center: Vector3, half: float) -> void:
	var mi := Look.box(Vector3(half * 2.0, 2.0, half * 2.0), wall_mat(1.0), center - Vector3(0, 1.0, 0))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	AbyssFx.silt(root, center + Vector3(0, 4.0, 0), Vector3(half * 0.6, 3.0, half * 0.6), 40)
