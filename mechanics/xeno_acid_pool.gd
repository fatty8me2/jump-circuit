class_name XenoAcidPool
extends Area3D
## Xeno Wilds: a pool of glowing acid. Touch the surface and you are back at the checkpoint
## (a hazard, like a kill brick - but it looks like what it is: bubbling lime liquid in a crusted
## basin, fuming). Positioned at the centre of the liquid SURFACE; `size` is its width x depth.
## The kill volume starts just under the surface, so landing short in it always counts.

const SHADER: Shader = preload("res://visual/xeno_acid.gdshader")

@export var size: Vector2 = Vector2(6, 6)
## Draw the crusted rim round it (off for lake sheets that disappear under the rocks).
@export var rim: bool = true
@export var fumes: bool = true
## Depth of the floating rock keel under the basin (0 = none, for pools set into the ground).
@export var keel: float = 0.0

static var _mat: ShaderMaterial


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitorable = false
	var shape := BoxShape3D.new()
	shape.size = Vector3(size.x, 1.2, size.y)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, -0.5, 0)
	add_child(cs)
	body_entered.connect(_on_body)
	_build_visual()


static func material() -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = SHADER
	return _mat


func _on_body(body: Node3D) -> void:
	if not (body is Player):
		return
	var n: Node = self
	while n != null and not n.has_method("fail"):
		n = n.get_parent()
	if n != null:
		n.call_deferred("fail", "hazard")


func _build_visual() -> void:
	var pm := PlaneMesh.new()
	pm.size = size
	var surf := Look.mesh_node(pm, material())
	surf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(surf)
	if rim:
		var crust: StandardMaterial3D = Look.flat(Color(0.26, 0.2, 0.18), 0.95)
		var mineral: StandardMaterial3D = Look.flat(Color(0.7, 0.85, 0.3), 0.7, 0.0, 0.3)
		var t: float = clampf(minf(size.x, size.y) * 0.06, 0.5, 2.0)
		for sx: float in [-1.0, 1.0]:
			add_child(Look.box(Vector3(t, t + 0.3, size.y + t * 2.0), crust, Vector3(sx * (size.x + t) * 0.5, -0.5 * t + 0.1, 0)))
			add_child(Look.box(Vector3(size.x + t * 2.0, t + 0.3, t), crust, Vector3(0, -0.5 * t + 0.1, sx * (size.y + t) * 0.5)))
			add_child(Look.box(Vector3(0.18, 0.06, size.y), mineral, Vector3(sx * (size.x * 0.5 - 0.02), 0.02, 0)))
		# a floor under the liquid so it reads as a basin from the side
		add_child(Look.box(Vector3(size.x + t * 2.0, 0.6, size.y + t * 2.0), crust, Vector3(0, -1.4, 0)))
		# a basin carried by the moon's low gravity: a tapering rock keel with dangling glowing roots
		if keel > 0.0:
			var k := Look.underside(Vector3(size.x + t * 2.0, 0.6, size.y + t * 2.0), keel, false)
			k.position = Vector3(0, -1.4 - 0.3 - keel * 0.5, 0)
			add_child(k)
	var area: float = size.x * size.y
	var vis := AABB(Vector3(-size.x * 0.5 - 2.0, -2.0, -size.y * 0.5 - 2.0), Vector3(size.x + 4.0, 8.0, size.y + 4.0))
	var bub: GPUParticles3D = Fx.emitter({"amount": clampi(int(area * 0.8), 6, 60), "lifetime": 0.9, "shape": "box",
		"extents": Vector3(size.x * 0.45, 0.02, size.y * 0.45), "dir": Vector3.UP, "spread": 20.0, "speed": Vector2(0.3, 1.2),
		"gravity": Vector3(0, -2.0, 0), "tex": Fx.Tex.BUBBLE, "size": 0.22, "curve": "pop",
		"color": Color(1.6, 2.2, 0.4, 0.9), "aabb": vis, "preprocess": 0.9, "local": true})
	bub.position = Vector3(0, 0.02, 0)
	add_child(bub)
	if fumes:
		var fume: GPUParticles3D = Fx.emitter({"amount": clampi(int(area * 0.25), 4, 26), "lifetime": 3.2, "shape": "box",
			"extents": Vector3(size.x * 0.45, 0.05, size.y * 0.45), "dir": Vector3.UP, "spread": 15.0, "speed": Vector2(0.4, 1.0),
			"tex": Fx.Tex.SMOKE, "additive": false, "size": 1.6, "curve": "puff", "angle": Vector2(0, 360), "spin": Vector2(-20, 20),
			"color": Color(0.7, 0.95, 0.3, 0.22), "fade": PackedFloat32Array([0.0, 0.8, 0.0]), "aabb": vis, "preprocess": 3.2, "local": true})
		fume.position = Vector3(0, 0.1, 0)
		add_child(fume)
	var l := OmniLight3D.new()
	l.light_color = Color(0.75, 1.0, 0.25)
	l.light_energy = 1.2
	l.omni_range = maxf(size.x, size.y) * 0.8 + 3.0
	l.shadow_enabled = false
	l.position = Vector3(0, 1.0, 0)
	add_child(l)
