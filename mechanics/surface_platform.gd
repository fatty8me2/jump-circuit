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
