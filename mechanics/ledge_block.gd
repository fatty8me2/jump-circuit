class_name LedgeBlock
extends StaticBody3D
## A block whose top edge can be grabbed. Jump at any side and, if the top is
## within mantle_reach of your feet, the player catches the lip and climbs on.
## Only ledge blocks allow it, so they wear a bright gold lip around the top
## and vertical grip rungs on every face. Too tall to jump onto (3-4.2 m above
## the approach) = a mantle wall; the top is ordinary walkable ground.

const LIP_COLOR: Color = Color(1.0, 0.82, 0.22)

@export var size: Vector3 = Vector3(4, 3.6, 4)
@export var style: String = "main"

# effects (visual only): two gleams chasing each other round the lip, shedding glitter
var _gleams: Array[Node3D] = []
var _gleam_s: float = 0.0


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	add_child(cs)
	add_child(Look.platform_box(size, style))
	var lip: StandardMaterial3D = Look.flat(LIP_COLOR, 0.35, 0.2, 1.6)
	var rung: StandardMaterial3D = Look.flat(LIP_COLOR.darkened(0.25), 0.5, 0.3, 0.5)
	var y_lip: float = size.y * 0.5 - 0.09
	for sx: float in [-1.0, 1.0]:
		add_child(Look.box(Vector3(0.08, 0.16, size.z + 0.16), lip, Vector3(sx * (size.x * 0.5 + 0.04), y_lip, 0)))
	for sz: float in [-1.0, 1.0]:
		add_child(Look.box(Vector3(size.x + 0.16, 0.16, 0.08), lip, Vector3(0, y_lip, sz * (size.z * 0.5 + 0.04))))
	# grip rungs: short vertical bars under the lip, on every face
	var rung_h: float = minf(1.4, size.y * 0.5)
	var y_rung: float = size.y * 0.5 - 0.2 - rung_h * 0.5
	for face: int in 4:
		var along_x: bool = face < 2
		var span: float = size.x if along_x else size.z
		var n: int = maxi(int(span / 1.2), 1)
		for i: int in n:
			var u: float = -span * 0.5 + (float(i) + 0.5) * span / float(n)
			var s: float = -1.0 if face % 2 == 0 else 1.0
			var pos := Vector3(u, y_rung, s * (size.z * 0.5 + 0.03)) if along_x else Vector3(s * (size.x * 0.5 + 0.03), y_rung, u)
			add_child(Look.box(Vector3(0.1, rung_h, 0.06) if along_x else Vector3(0.06, rung_h, 0.1), rung, pos))
	_build_fx()


func _build_fx() -> void:
	var hot: Color = Fx.hot(LIP_COLOR.lerp(Color.WHITE, 0.3), 2.4)
	var vis := AABB(Vector3(-size.x - 2.0, -3.0, -size.z - 2.0), Vector3(size.x * 2.0 + 4.0, 5.0, size.z * 2.0 + 4.0))
	for i: int in 2:
		var g := Node3D.new()
		g.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # moved in _process
		add_child(g)
		g.add_child(Fx.sprite(hot, 0.75))
		# world-space glitter: left behind along the lip as the gleam slides on
		g.add_child(Fx.emitter({"amount": 12, "lifetime": 0.6, "shape": "sphere",
			"radius": 0.08, "dir": Vector3.DOWN, "spread": 40.0, "speed": Vector2(0.1, 0.5),
			"gravity": Vector3(0, -1.5, 0), "tex": Fx.Tex.STAR, "size": 0.16, "curve": "shrink",
			"color": hot, "aabb": vis}))
		_gleams.append(g)
	_gleam_s = fposmod(position.x * 1.7 + position.z * 0.9, _perimeter())
	_place_gleams()


func _perimeter() -> float:
	return 4.0 * (size.x * 0.5 + size.z * 0.5 + 0.16)


## Point `s` metres round the lip (just outside it), going round the top.
func _lip_point(s: float) -> Vector3:
	var hx: float = size.x * 0.5 + 0.08
	var hz: float = size.z * 0.5 + 0.08
	var y: float = size.y * 0.5 - 0.02
	var d: float = fposmod(s, _perimeter())
	if d < 2.0 * hx:
		return Vector3(-hx + d, y, hz)
	d -= 2.0 * hx
	if d < 2.0 * hz:
		return Vector3(hx, y, hz - d)
	d -= 2.0 * hz
	if d < 2.0 * hx:
		return Vector3(hx - d, y, -hz)
	d -= 2.0 * hx
	return Vector3(-hx, y, -hz + d)


## The two gleams run round in opposite directions.
func _place_gleams() -> void:
	var p: float = _perimeter()
	_gleams[0].position = _lip_point(_gleam_s)
	_gleams[1].position = _lip_point(p * 1.5 - _gleam_s)


func _process(dt: float) -> void:
	_gleam_s = fposmod(_gleam_s + dt * 2.4, _perimeter())
	_place_gleams()


func is_ledge() -> bool:
	return true
