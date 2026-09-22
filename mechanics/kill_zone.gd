class_name KillZone
extends Area3D
## Touch it and you are back at the checkpoint. Box-shaped; can be parented to
## movers/spinners to make moving hazards.

@export var size: Vector3 = Vector3(2, 0.5, 2)
@export var show_mesh: bool = true


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
	body_entered.connect(_on_body)


func _on_body(body: Node3D) -> void:
	if not (body is Player):
		return
	var n: Node = self
	while n != null and not n.has_method("fail"):
		n = n.get_parent()
	if n != null:
		# a visible brick is a hazard hit; an invisible catch net is just an early fall-out
		n.call_deferred("fail", "hazard" if show_mesh else "fall")
