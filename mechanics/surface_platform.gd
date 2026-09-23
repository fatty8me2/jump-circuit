class_name SurfacePlatform
extends StaticBody3D
## Static platform whose surface acts on the player:
##  BOOST    accelerates along local -Z up to `speed` (momentum is then yours to keep)
##  CONVEYOR drags everything on it along local -Z at `speed`
##  SLICK    almost no traction; on a slope it accelerates you downhill
## The player reads these through boost() / surface_velocity() / grip().

enum Kind { BOOST, CONVEYOR, SLICK }

@export var kind: Kind = Kind.BOOST
@export var size: Vector3 = Vector3(3, 0.4, 8)
@export var speed: float = 20.0
@export var accel: float = 45.0
@export var slick_grip: float = 0.06


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	add_child(cs)
	var bm := BoxMesh.new()
	bm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	if kind == Kind.SLICK:
		var ice := StandardMaterial3D.new()
		ice.albedo_color = Color(0.72, 0.9, 1.0)
		ice.roughness = 0.04
		ice.metallic = 0.35
		ice.emission_enabled = true
		ice.emission = Color(0.4, 0.75, 1.0)
		ice.emission_energy_multiplier = 0.25
		mi.material_override = ice
	else:
		var m := ShaderMaterial.new()
		m.shader = preload("res://visual/strip.gdshader")
		m.set_shader_parameter("half_size", size * 0.5)
		if kind == Kind.BOOST:
			m.set_shader_parameter("arrow_color", Color(0.15, 1.0, 0.85))
			m.set_shader_parameter("scroll_speed", speed * 0.35)
		else:
			m.set_shader_parameter("arrow_color", Color(1.0, 0.7, 0.15))
			m.set_shader_parameter("scroll_speed", speed)
			m.set_shader_parameter("glow", 1.2)
		mi.material_override = m
	add_child(mi)
	if kind == Kind.BOOST:
		_build_boost_fx()


## Boost strips stream sparks along their arrow (local -Z), riding just over the deck:
## born at the back end, gone by the front. Visual only; one cheap local emitter.
func _build_boost_fx() -> void:
	var v: float = maxf(speed * 0.55, 4.0)
	var p: GPUParticles3D = Fx.emitter({"amount": clampi(int(size.x * size.z * 0.9), 10, 36),
		"lifetime": size.z / v, "local": true, "shape": "box",
		"extents": Vector3(size.x * 0.4, 0.02, 0.1), "offset": Vector3(0, 0, size.z * 0.5 - 0.2),
		"dir": Vector3.FORWARD, "spread": 2.0, "speed": Vector2(v * 0.8, v * 1.2),
		"facing": "velocity", "tex": Fx.Tex.SPARK, "size": Vector2(0.14, 1.1),
		"fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]), "color": Color(1.2, 3.4, 3.0),
		"aabb": AABB(-size * 0.5 - Vector3(1, 0, 1), size + Vector3(2, 2, 2)), "preprocess": size.z / v})
	p.position = Vector3(0, size.y * 0.5 + 0.12, 0)
	add_child(p)


func _dir() -> Vector3:
	var d: Vector3 = -global_basis.z
	d.y = 0.0
	return d.normalized()


func boost() -> Dictionary:
	if kind != Kind.BOOST:
		return {"dir": Vector3.FORWARD, "speed": 0.0, "accel": 0.0}
	return {"dir": _dir(), "speed": speed, "accel": accel}


func surface_velocity() -> Vector3:
	return _dir() * speed if kind == Kind.CONVEYOR else Vector3.ZERO


func grip() -> float:
	return slick_grip if kind == Kind.SLICK else 1.0
