class_name ManorPossessed
extends MovingPlatform
## Phantom Manor: possessed furniture - a floating table, chair, armoire, bookcase, coffin or
## a waltzing ghost couple on a torn-up piece of the ballroom parquet. It moves exactly like a
## MovingPlatform (PATH ping-pong or ORBIT, a pure function of Game.course_time, so the route
## bot can look ahead), but it is dressed as the haunted piece: it drifts and rocks gently (the
## visual only; the collider stays level), trails green ectoplasm, and the dancers turn as
## they waltz. The collider is one box (or disc) of `size`; the top of the piece is its top.

## "table", "chair", "armoire", "bookcase", "coffin", "trunk", "dancers"
@export var kind: String = "table"
@export var tint: Color = Color(0.55, 1.0, 0.72)

const WOOD := Color(0.26, 0.15, 0.11)
const WOOD_DARK := Color(0.14, 0.08, 0.07)
const BRASS := Color(0.7, 0.52, 0.24)

var _look: Node3D
var _spin: Node3D
var _seed: float = 0.0


func _ready() -> void:
	sync_to_physics = false
	collision_layer = 1
	collision_mask = 0
	_origin = position
	_seed = fposmod(position.x * 0.37 + position.z * 0.61, 6.28)
	var cs := CollisionShape3D.new()
	if is_round:
		var cyl := CylinderShape3D.new()
		cyl.radius = size.x * 0.5
		cyl.height = size.y
		cs.shape = cyl
	else:
		var box := BoxShape3D.new()
		box.size = size
		cs.shape = box
	add_child(cs)
	_look = Node3D.new()
	add_child(_look)
	_build_look()
	var vis := AABB(-size * 0.5 - Vector3(3, 6, 3), size + Vector3(6, 12, 6))
	var drip: GPUParticles3D = Fx.emitter({"amount": 10, "lifetime": 1.4, "preprocess": 1.4,
		"shape": "box", "extents": Vector3(size.x * 0.4, 0.05, size.z * 0.4), "dir": Vector3.DOWN, "spread": 10.0,
		"speed": Vector2(0.4, 1.2), "gravity": Vector3(0, -2.0, 0), "tex": Fx.Tex.DOT, "size": 0.1,
		"color": Fx.hot(tint, 1.6), "curve": "shrink", "aabb": vis})
	drip.position = Vector3(0, -size.y * 0.5 - 0.2, 0)
	add_child(drip)
	position = _origin + offset_at(Game.course_time)
	reset_physics_interpolation()
	add_to_group("course_clock")
	if kind == "dancers":
		WorldAudio.loop("manor_waltz_box", self, -16.0, 16.0, 4.0)
	else:
		WorldAudio.loop("manor_possessed_creak", self, -18.0, 12.0, 3.0)


func _mat(c: Color, rough: float = 0.75, metal: float = 0.0, emit: float = 0.0) -> StandardMaterial3D:
	return Look.flat(c, rough, metal, emit)


func _box(s: Vector3, m: Material, at: Vector3, parent: Node3D = null) -> MeshInstance3D:
	var mi := Look.box(s, m, at)
	(parent if parent != null else _look).add_child(mi)
	return mi


## The furniture: its walkable top flush with the collider's top (+size.y / 2).
func _build_look() -> void:
	var top: float = size.y * 0.5
	var sx: float = size.x
	var sz: float = size.z
	var wood: StandardMaterial3D = _mat(WOOD, 0.7)
	var dark: StandardMaterial3D = _mat(WOOD_DARK, 0.8)
	var brass: StandardMaterial3D = _mat(BRASS, 0.35, 0.85)
	var glow: StandardMaterial3D = _mat(tint, 0.4, 0.0, 1.6)
	match kind:
		"table":
			_box(Vector3(sx, 0.18, sz), wood, Vector3(0, top - 0.09, 0))
			_box(Vector3(sx - 0.3, 0.22, sz - 0.3), dark, Vector3(0, top - 0.29, 0))
			for x: float in [-1.0, 1.0]:
				for z: float in [-1.0, 1.0]:
					_look.add_child(Look.cylinder(0.1, 1.2, dark, Vector3(x * (sx * 0.5 - 0.3), top - 0.95, z * (sz * 0.5 - 0.3)), 0.06, 8))
			# a candlestick left burning on it
			_look.add_child(Look.cylinder(0.05, 0.3, brass, Vector3(sx * 0.3, top + 0.15, -sz * 0.3), -1.0, 8))
			_look.add_child(Look.sphere(0.06, glow, Vector3(sx * 0.3, top + 0.36, -sz * 0.3)))
		"chair":
			_box(Vector3(sx, size.y, sz), wood, Vector3.ZERO)
			_box(Vector3(sx, 1.7, 0.16), dark, Vector3(0, top + 0.85, sz * 0.5 - 0.08))
			_box(Vector3(sx * 0.6, 0.6, 0.05), _mat(Color(0.35, 0.08, 0.12), 0.9), Vector3(0, top + 1.0, sz * 0.5 - 0.17))
			for x: float in [-1.0, 1.0]:
				for z: float in [-1.0, 1.0]:
					_look.add_child(Look.cylinder(0.07, 0.9, dark, Vector3(x * (sx * 0.5 - 0.12), -top - 0.45, z * (sz * 0.5 - 0.12)), 0.05, 8))
		"armoire", "bookcase":
			# lying on its back, doors / shelves facing up
			_box(Vector3(sx, size.y, sz), dark, Vector3.ZERO)
			_box(Vector3(sx + 0.2, size.y + 0.1, 0.3), wood, Vector3(0, 0, -sz * 0.5 - 0.1))
			if kind == "bookcase":
				var n: int = maxi(int(sz / 0.7), 2)
				for i: int in n:
					var z: float = -sz * 0.5 + (float(i) + 0.5) * sz / float(n)
					for j: int in 6:
						var bx: float = -sx * 0.4 + float(j) * sx * 0.16
						var col: Color = [Color(0.4, 0.1, 0.1), Color(0.12, 0.2, 0.3), Color(0.3, 0.26, 0.12), Color(0.18, 0.3, 0.16)][(i + j) % 4]
						_box(Vector3(sx * 0.13, 0.06, 0.45), _mat(col, 0.85), Vector3(bx, top + 0.03, z), null)
			else:
				for x: float in [-0.25, 0.25]:
					_box(Vector3(sx * 0.42, 0.05, sz * 0.85), wood, Vector3(x * sx, top + 0.02, 0))
					_look.add_child(Look.sphere(0.07, brass, Vector3(x * sx * 0.3, top + 0.08, 0)))
		"coffin":
			var lid := Look.box(Vector3(sx, size.y, sz), dark, Vector3.ZERO)
			lid.scale = Vector3(1.0, 1.0, 1.0)
			_look.add_child(lid)
			_box(Vector3(sx * 0.12, 0.04, sz * 0.5), brass, Vector3(0, top + 0.02, -sz * 0.08))
			_box(Vector3(sx * 0.55, 0.04, 0.12), brass, Vector3(0, top + 0.02, -sz * 0.2))
			for s: float in [-1.0, 1.0]:
				_look.add_child(Look.sphere(0.08, brass, Vector3(s * (sx * 0.5 + 0.04), 0, sz * 0.25)))
				_look.add_child(Look.sphere(0.08, brass, Vector3(s * (sx * 0.5 + 0.04), 0, -sz * 0.25)))
		"trunk":
			_box(Vector3(sx, size.y, sz), wood, Vector3.ZERO)
			for z: float in [-0.35, 0.0, 0.35]:
				_box(Vector3(sx + 0.06, size.y + 0.06, 0.1), brass, Vector3(0, 0, z * sz))
		"dancers":
			# a torn-up disc of ballroom parquet, and a ghost couple waltzing on it
			var floor_m := StandardMaterial3D.new()
			floor_m.albedo_color = Color(0.32, 0.2, 0.14)
			floor_m.roughness = 0.35
			floor_m.metallic = 0.1
			var disc := Look.cylinder(size.x * 0.5, size.y, floor_m, Vector3.ZERO, -1.0, 28)
			_look.add_child(disc)
			var rim := Look.cylinder(size.x * 0.5 + 0.05, 0.08, _mat(BRASS, 0.3, 0.9), Vector3(0, top - 0.04, 0), -1.0, 28)
			_look.add_child(rim)
			_look.add_child(Look.cylinder(size.x * 0.46, size.y * 0.7, _mat(Color(0.1, 0.06, 0.05), 0.9), Vector3(0, -size.y * 0.6, 0), size.x * 0.3, 20))
			_spin = Node3D.new()
			_look.add_child(_spin)
			_couple(_spin, top)
		_:
			_box(size, wood, Vector3.ZERO)


## Two ghosts in a waltz hold: a gentleman in a tail coat and a lady in a wide gown, in
## ectoplasm, turning slowly on the spot (on `parent`, standing on the floor at `top`).
func _couple(parent: Node3D, top: float) -> void:
	var g := ShaderMaterial.new()
	g.shader = preload("res://visual/manor_ghost.gdshader")
	g.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	g.set_shader_parameter("glow", 0.9)
	g.set_shader_parameter("wobble", 0.06)
	var r: float = size.x * 0.27
	# the lady: a flared gown, a waist, shoulders and a head
	var gown := Look.cylinder(0.75, 1.5, g, Vector3(-r, top + 0.8, 0), 0.22, 16)
	parent.add_child(gown)
	parent.add_child(Look.cylinder(0.2, 0.55, g, Vector3(-r, top + 1.8, 0), 0.26, 10))
	parent.add_child(Look.sphere(0.2, g, Vector3(-r, top + 2.25, 0)))
	# the gentleman: legs, a coat with tails, shoulders, a head
	for s: float in [-1.0, 1.0]:
		parent.add_child(Look.cylinder(0.1, 0.95, g, Vector3(r, top + 0.48, s * 0.14), 0.12, 8))
	parent.add_child(Look.cylinder(0.3, 0.95, g, Vector3(r, top + 1.4, 0), 0.26, 10))
	parent.add_child(Look.sphere(0.2, g, Vector3(r, top + 2.1, 0)))
	# the hold: joined hands and his arm round her
	var arm := Look.cylinder(0.06, r * 2.0, g, Vector3(0, top + 1.75, 0.2), -1.0, 6)
	arm.rotation.z = PI * 0.5
	parent.add_child(arm)
	var arm2 := Look.cylinder(0.06, r * 1.4, g, Vector3(-r * 0.3, top + 1.55, -0.15), -1.0, 6)
	arm2.rotation.z = PI * 0.5
	parent.add_child(arm2)
	for n: Node in parent.get_children():
		if n is GeometryInstance3D:
			(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _process(dt: float) -> void:
	var t: float = Game.course_time
	# drifting and rocking on the ghost's breath (visual only)
	if kind == "dancers":
		_look.position = Vector3(0, sin(t * 1.3 + _seed) * 0.04, 0)
		_spin.rotation.y = t * 2.1 + _seed
	else:
		_look.position = Vector3(0, sin(t * 1.7 + _seed) * 0.05, 0)
		_look.rotation = Vector3(sin(t * 1.1 + _seed) * 0.03, 0, cos(t * 0.9 + _seed) * 0.03)
