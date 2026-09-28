class_name ManorBats
extends Node3D
## Phantom Manor: a flock of bats wheeling on lazy loops (across the moon, round a tower),
## wings flapping. Visual only; every bat is three tiny meshes sharing one material, driven
## from one _process. Loops are ellipses of `radius` round the node, each bat on its own
## phase, height wobble and speed.

@export var count: int = 14
@export var radius: Vector2 = Vector2(30.0, 14.0)
@export var height: float = 6.0
@export var scale_k: float = 1.0
@export var speed: float = 0.25

var _bats: Array[Dictionary] = []


static func make(center: Vector3, n: int, r: Vector2, h: float, k: float = 1.0, spd: float = 0.25) -> ManorBats:
	var b := ManorBats.new()
	b.position = center
	b.count = n
	b.radius = r
	b.height = h
	b.scale_k = k
	b.speed = spd
	return b


func _ready() -> void:
	var m: StandardMaterial3D = Look.flat(Color(0.03, 0.02, 0.03), 0.9)
	var wing_mesh := PrismMesh.new()
	wing_mesh.size = Vector3(0.9, 0.35, 0.03)
	wing_mesh.left_to_right = 1.0
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absf(position.x * 13.0 + position.z * 7.0)) + 3
	for i: int in count:
		var bat := Node3D.new()
		bat.scale = Vector3.ONE * scale_k * rng.randf_range(0.8, 1.2)
		add_child(bat)
		var body := Look.sphere(0.12, m)
		body.scale = Vector3(0.8, 0.8, 1.6)
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bat.add_child(body)
		var wings: Array[Node3D] = []
		for s: float in [-1.0, 1.0]:
			var hinge := Node3D.new()
			bat.add_child(hinge)
			var w := Look.mesh_node(wing_mesh, m, Vector3(s * 0.45, 0, 0))
			w.rotation = Vector3(PI * 0.5, 0, 0)
			w.scale = Vector3(s, 1, 1)
			w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			hinge.add_child(w)
			wings.append(hinge)
		_bats.append({"n": bat, "w": wings, "ph": rng.randf() * TAU, "sp": speed * rng.randf_range(0.7, 1.3),
			"dir": 1.0 if rng.randf() < 0.75 else -1.0, "r": rng.randf_range(0.6, 1.0), "hy": rng.randf() * TAU,
			"flap": rng.randf_range(9.0, 13.0)})


func _process(_dt: float) -> void:
	var t: float = Time.get_ticks_msec() * 0.001
	for b: Dictionary in _bats:
		var a: float = float(b["ph"]) + t * float(b["sp"]) * float(b["dir"])
		var r: float = float(b["r"])
		var p := Vector3(cos(a) * radius.x * r, sin(t * 0.7 + float(b["hy"])) * height * 0.5, sin(a) * radius.y * r)
		var n := b["n"] as Node3D
		# face along the loop
		var v := Vector3(-sin(a) * radius.x, 0.0, cos(a) * radius.y) * float(b["dir"])
		n.position = p
		if v.length() > 0.001:
			n.rotation.y = atan2(-v.x, -v.z)
		var f: float = sin(t * float(b["flap"]) + float(b["hy"])) * 0.9
		var wings: Array = b["w"]
		(wings[0] as Node3D).rotation.z = -f
		(wings[1] as Node3D).rotation.z = f
