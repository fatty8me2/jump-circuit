class_name KillZone
extends Area3D
## Touch it and you are back at the checkpoint. Box-shaped; can be parented to
## movers/spinners to make moving hazards.

@export var size: Vector3 = Vector3(2, 0.5, 2)
@export var show_mesh: bool = true
## Rising embers over a visible brick (visual only; sweepers turn it off for their bars).
var embers: bool = true


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitorable = false
	var shape := BoxShape3D.new()
	shape.size = size * 0.92
	var cs := CollisionShape3D.new()
	cs.shape = shape
	add_child(cs)
	if show_mesh:
		var bm := BoxMesh.new()
		bm.size = size
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		var m := ShaderMaterial.new()
		m.shader = preload("res://visual/hazard.gdshader")
		mi.material_override = m
		add_child(mi)
		if embers:
			_build_embers()
	body_entered.connect(_on_body)


func _build_embers() -> void:
	var area: float = size.x * size.z
	var e: GPUParticles3D = Fx.embers({"amount": clampi(int(area * 1.8), 6, 40), "lifetime": 1.5, "additive": false,
		"extents": Vector3(size.x * 0.45, 0.02, size.z * 0.45), "speed": Vector2(0.5, 1.3),
		"size": 0.17, "color": Color(2.8, 0.75, 0.3), "fade": PackedFloat32Array([0.0, 1.0, 0.6, 0.0]),
		"curve": "shrink", "turbulence": 0.8, "preprocess": 1.5,
		"aabb": AABB(Vector3(-size.x * 0.5 - 1.0, -size.y * 0.5 - 1.0, -size.z * 0.5 - 1.0), Vector3(size.x + 2.0, size.y + 4.0, size.z + 2.0))})
	e.position = Vector3(0, size.y * 0.5, 0)
	add_child(e)


func _on_body(body: Node3D) -> void:
	if not (body is Player):
		return
	var n: Node = self
	while n != null and not n.has_method("fail"):
		n = n.get_parent()
	if n != null:
		# a visible brick is a hazard hit; an invisible catch net is just an early fall-out
		n.call_deferred("fail", "hazard" if show_mesh else "fall")
