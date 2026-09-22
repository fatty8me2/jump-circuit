class_name FinishGate
extends Area3D
## The visible destination: a tall glowing arch. Entering it completes the level.

signal reached

@export var width: float = 5.0
@export var gate_height: float = 5.5

var _t: float = 0.0
var _ring: MeshInstance3D
var _done: bool = false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitorable = false
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, gate_height, 2.0)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, gate_height * 0.5, 0)
	add_child(cs)
	body_entered.connect(func(body: Node3D) -> void:
		if body is Player and not _done:
			_done = true
			reached.emit())
	var glow: StandardMaterial3D = Look.flat(Look.c("accent"), 0.3, 0.0, 3.0)
	var stone: StandardMaterial3D = Look.flat(Look.c("trim").lerp(Color.WHITE, 0.2), 0.6)
	for sx: int in [-1, 1]:
		add_child(Look.box(Vector3(0.7, gate_height, 0.9), stone, Vector3(sx * (width * 0.5 + 0.35), gate_height * 0.5, 0)))
		add_child(Look.box(Vector3(0.16, gate_height * 0.85, 0.95), glow, Vector3(sx * (width * 0.5 + 0.02), gate_height * 0.47, 0)))
	add_child(Look.box(Vector3(width + 2.2, 0.8, 1.1), stone, Vector3(0, gate_height + 0.4, 0)))
	add_child(Look.box(Vector3(width + 0.1, 0.14, 1.15), glow, Vector3(0, gate_height + 0.02, 0)))
	var tm := TorusMesh.new()
	tm.inner_radius = 0.9
	tm.outer_radius = 1.08
	tm.rings = 40
	tm.ring_segments = 8
	_ring = Look.mesh_node(tm, glow, Vector3(0, gate_height + 2.2, 0))
	_ring.rotation.x = PI / 2.0
	add_child(_ring)
	# sheer light curtain
	var veil_mat := StandardMaterial3D.new()
	veil_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	veil_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	veil_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var ac: Color = Look.c("accent")
	veil_mat.albedo_color = Color(ac.r, ac.g, ac.b, 0.16)
	var qm := QuadMesh.new()
	qm.size = Vector2(width, gate_height)
	var veil := Look.mesh_node(qm, veil_mat, Vector3(0, gate_height * 0.5, 0))
	veil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(veil)
	var lamp := OmniLight3D.new()
	lamp.light_color = ac
	lamp.light_energy = 2.5
	lamp.omni_range = 12.0
	lamp.position = Vector3(0, gate_height * 0.6, 0)
	add_child(lamp)


func _process(dt: float) -> void:
	_t += dt
	_ring.rotation.y = _t * 1.2
	_ring.position.y = gate_height + 2.2 + sin(_t * 1.7) * 0.15
