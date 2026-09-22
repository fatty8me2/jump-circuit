class_name Checkpoint
extends Area3D
## Touch to bank progress. Respawns face `-Z` of this node (rotate the node to aim
## the player at the next challenge).

signal reached(cp: Checkpoint)

@export var index: int = 0
@export var radius: float = 2.2

var active: bool = false
var _ring_mat: StandardMaterial3D
var _orb: MeshInstance3D
var _orb_mat: StandardMaterial3D
var _t: float = 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitorable = false
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = 3.0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, 1.5, 0)
	add_child(cs)
	body_entered.connect(func(body: Node3D) -> void:
		if body is Player:
			reached.emit(self))
	# visuals: floor ring + two slim pylons with a floating orb between them
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.albedo_color = Color(0.2, 0.22, 0.28)
	_ring_mat.emission_enabled = true
	_ring_mat.emission = Look.c("accent")
	_ring_mat.emission_energy_multiplier = 0.15
	var tm := TorusMesh.new()
	tm.inner_radius = radius * 0.78
	tm.outer_radius = radius * 0.86
	tm.rings = 48
	tm.ring_segments = 6
	var ring := Look.mesh_node(tm, _ring_mat, Vector3(0, 0.03, 0))
	ring.scale = Vector3(1, 0.25, 1)
	add_child(ring)
	var pole_mat: StandardMaterial3D = Look.flat(Look.c("metal"), 0.4, 0.6)
	for sx: int in [-1, 1]:
		add_child(Look.cylinder(0.09, 2.6, pole_mat, Vector3(sx * radius * 0.82, 1.3, 0), 0.05, 10))
		add_child(Look.sphere(0.13, pole_mat, Vector3(sx * radius * 0.82, 2.65, 0)))
	_orb_mat = StandardMaterial3D.new()
	_orb_mat.albedo_color = Color(0.35, 0.38, 0.45)
	_orb_mat.emission_enabled = true
	_orb_mat.emission = Look.c("accent")
	_orb_mat.emission_energy_multiplier = 0.1
	_orb = Look.mesh_node(_octa(), _orb_mat, Vector3(0, 2.75, 0))
	add_child(_orb)


func _octa() -> Mesh:
	var s := SphereMesh.new()
	s.radius = 0.3
	s.height = 0.75
	s.radial_segments = 4
	s.rings = 1
	return s


func set_active(on: bool, celebrate: bool = true) -> void:
	if active == on:
		return
	active = on
	_ring_mat.emission_energy_multiplier = 2.4 if on else 0.15
	_orb_mat.emission_energy_multiplier = 3.5 if on else 0.1
	_orb_mat.albedo_color = Look.c("accent") if on else Color(0.35, 0.38, 0.45)
	if on and celebrate:
		var tw: Tween = create_tween()
		_orb.scale = Vector3.ONE * 2.2
		tw.tween_property(_orb, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func respawn_transform() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, global_rotation.y), global_position + Vector3(0, 0.15, 0))


func _process(dt: float) -> void:
	_t += dt
	_orb.rotation.y = _t * (2.2 if active else 0.5)
	_orb.position.y = 2.75 + sin(_t * 2.0) * 0.08
