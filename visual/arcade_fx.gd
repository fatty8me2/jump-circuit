class_name ArcadeFx
extends RefCounted
## Pixel Panic's shared look: the arcade palette, the beveled-block and ghost-outline materials,
## square-pixel particle presets (every amount goes through Fx.count, i.e. Settings.particle_scale())
## and the one hook the hazards use to send the player back. Visual only, except `hurt`.

const CYAN := Color(0.1, 0.92, 1.0)
const YELLOW := Color(1.0, 0.88, 0.12)
const PURPLE := Color(0.72, 0.28, 1.0)
const GREEN := Color(0.22, 1.0, 0.36)
const RED := Color(1.0, 0.2, 0.26)
const BLUE := Color(0.22, 0.38, 1.0)
const ORANGE := Color(1.0, 0.54, 0.1)
const MAGENTA := Color(1.0, 0.22, 0.7)
const WHITE := Color(0.95, 0.96, 1.0)
const INK := Color(0.03, 0.02, 0.09)

const BLOCK_SHADER: Shader = preload("res://visual/arcade_block.gdshader")
const GHOST_SHADER: Shader = preload("res://visual/arcade_ghost.gdshader")

static var _pixel: BoxMesh
static var _cache: Dictionary = {}


static func pal(i: int) -> Color:
	var all: Array[Color] = [CYAN, YELLOW, PURPLE, GREEN, RED, BLUE, ORANGE, MAGENTA]
	return all[posmod(i, all.size())]


## A beveled block material for a box of `size` (its own instance: the caller animates `flash`).
static func block_mat(tint: Color, size: Vector3, glow: float = 0.35) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = BLOCK_SHADER
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("half_size", size * 0.5)
	m.set_shader_parameter("glow", glow)
	return m


## The bright outline of a box about to land / arrive (its own instance: the caller animates `pulse`).
static func ghost_mat(tint: Color, size: Vector3) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = GHOST_SHADER
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("half_size", size * 0.5)
	return m


## A shared, unshaded cube for pixel particles (the particle colour tints it; HDR blooms).
static func pixel_mesh() -> Mesh:
	if _pixel == null:
		_pixel = BoxMesh.new()
		_pixel.size = Vector3.ONE * 0.18
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		_pixel.material = m
	return _pixel


static func _aabb(ext: Vector3, extra: float = 6.0) -> AABB:
	return AABB(-ext - Vector3.ONE * extra, (ext + Vector3.ONE * extra) * 2.0)


## Square pixels drifting up through a box (world space): the cabinet's dust.
static func pixels(parent: Node, center: Vector3, ext: Vector3, amount: int, cols: PackedColorArray = PackedColorArray()) -> GPUParticles3D:
	var pick: PackedColorArray = cols
	if pick.is_empty():
		pick = PackedColorArray([Fx.hot(CYAN, 1.6), Fx.hot(MAGENTA, 1.6), Fx.hot(YELLOW, 1.6), Fx.hot(WHITE, 1.3)])
	var p: GPUParticles3D = Fx.emitter({"amount": amount, "lifetime": 6.0, "preprocess": 6.0, "shape": "box", "extents": ext,
		"dir": Vector3.UP, "spread": 12.0, "speed": Vector2(0.3, 0.9), "facing": "mesh", "mesh": pixel_mesh(),
		"scale": Vector2(0.6, 1.5), "pick": pick, "curve": "pop", "turbulence": 0.3, "aabb": _aabb(ext, 6.0)})
	p.position = center
	parent.add_child(p)
	return p


## A one-shot burst of square pixels (built idle; restart() it on its event).
static func pop(col: Color, amount: int = 24, speed: Vector2 = Vector2(2.0, 6.0), spread: float = 80.0) -> GPUParticles3D:
	return Fx.burst({"amount": amount, "lifetime": 0.8, "facing": "mesh", "mesh": pixel_mesh(), "dir": Vector3.UP,
		"spread": spread, "speed": speed, "gravity": Vector3(0, -9.0, 0), "damping": Vector2(0.5, 1.5),
		"scale": Vector2(0.6, 1.6), "color": Fx.hot(col, 1.8), "curve": "shrink", "aabb": _aabb(Vector3(5, 6, 5))})


## Checkpoint bloom: coloured pixels bursting up, white stars and a ring across the slab.
static func cp_burst(col: Color) -> Array[GPUParticles3D]:
	var cubes: GPUParticles3D = Fx.burst({"amount": 46, "lifetime": 1.4, "facing": "mesh", "mesh": pixel_mesh(),
		"dir": Vector3.UP, "spread": 75.0, "speed": Vector2(2.5, 7.0), "gravity": Vector3(0, -7.0, 0),
		"damping": Vector2(0.5, 1.5), "scale": Vector2(0.7, 1.8), "angle": Vector2(0, 360), "spin": Vector2(-200, 200),
		"pick": PackedColorArray([Fx.hot(col, 2.0), Fx.hot(WHITE, 1.6), Fx.hot(YELLOW, 1.8)]), "curve": "shrink",
		"aabb": _aabb(Vector3(6, 8, 6))})
	var stars: GPUParticles3D = Fx.burst({"amount": 30, "lifetime": 1.2, "tex": Fx.Tex.STAR, "size": 0.32,
		"dir": Vector3.UP, "spread": 60.0, "speed": Vector2(2.0, 6.0), "gravity": Vector3(0, -1.0, 0),
		"color": Fx.hot(col, 2.4), "aabb": _aabb(Vector3(6, 8, 6))})
	var ring: GPUParticles3D = Fx.shockwave(4.5, {"lifetime": 0.7, "color": Fx.hot(col, 1.6), "aabb": _aabb(Vector3(6, 2, 6))})
	return [cubes, stars, ring]


## Finish: a fountain of pixels in every arcade colour.
static func finale(col: Color, amount: int = 90) -> GPUParticles3D:
	return Fx.burst({"amount": amount, "lifetime": 2.4, "facing": "mesh", "mesh": pixel_mesh(), "dir": Vector3.UP,
		"spread": 180.0, "speed": Vector2(4.0, 12.0), "gravity": Vector3(0, -4.0, 0), "damping": Vector2(0.4, 1.2),
		"scale": Vector2(0.8, 2.2), "angle": Vector2(0, 360), "spin": Vector2(-200, 200),
		"color": Fx.hot(col, 2.4), "curve": "shrink", "aabb": _aabb(Vector3(16, 16, 16))})


## Sends the local player back to the checkpoint: the Area3D hazards' common ending. `body` is
## whatever entered; `node` is any node inside the level.
static func hurt(node: Node, body: Node3D) -> void:
	if not (body is Player):
		return
	var n: Node = node
	while n != null and not n.has_method("fail"):
		n = n.get_parent()
	if n != null:
		print("HURT by ", node.get_parent().name if node.get_parent() else "?", " ", node.get_parent().get_script().resource_path if node.get_parent() and node.get_parent().get_script() else "", " t=", Game.course_time)
		n.call_deferred("fail", "hazard")


## A box-shaped hazard volume (Area3D, no mesh) that hurts whoever touches it while `monitoring`.
static func hazard_area(size: Vector3, pos: Vector3 = Vector3.ZERO) -> Area3D:
	var a := Area3D.new()
	a.collision_layer = 0
	a.collision_mask = 2
	a.monitorable = false
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	a.add_child(cs)
	a.position = pos
	a.body_entered.connect(func(b: Node3D) -> void: ArcadeFx.hurt(a, b))
	return a


## A sphere-shaped hazard volume (for chompers and balls).
static func hazard_sphere(radius: float, pos: Vector3 = Vector3.ZERO) -> Area3D:
	var a := Area3D.new()
	a.collision_layer = 0
	a.collision_mask = 2
	a.monitorable = false
	var shape := SphereShape3D.new()
	shape.radius = radius
	var cs := CollisionShape3D.new()
	cs.shape = shape
	a.add_child(cs)
	a.position = pos
	a.body_entered.connect(func(b: Node3D) -> void: ArcadeFx.hurt(a, b))
	return a


## Unshaded emissive material (HDR colour, optional alpha) for neon strips, eyes, beams.
static func glow_mat(col: Color, energy: float = 2.0, alpha: float = 1.0) -> StandardMaterial3D:
	var key: String = "glow:%s:%.2f:%.2f" % [col.to_html(false), energy, alpha]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(col.r * energy, col.g * energy, col.b * energy, alpha)
	if alpha < 0.99:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cache[key] = m
	return m
