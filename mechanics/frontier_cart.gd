class_name FrontierCart
extends MovingPlatform
## Wild West Heist: a MINE CART on rails. An iron ore cart that shuttles along a narrow-gauge track
## laid over the cars (the ore train's transfer line), riding out over a long coupling and back on the
## course clock. Its load of ore is the deck you ride on. It is an ordinary MovingPlatform underneath
## (a pure function of Game.course_time that carries its rider with its full velocity), dressed as a
## cart: no thruster pods, no hover hum - wheels, an iron tub and a rattling rumble instead.
## Build like kit.mover: position = deck top - size.y / 2, `points` = offsets along the rails.

var tint: Color = Color(0.42, 0.3, 0.22)
var _rumble: AudioStreamPlayer3D
var _sparks: GPUParticles3D
var _was_moving: bool = false


func _ready() -> void:
	sync_to_physics = false
	collision_layer = 1
	collision_mask = 0
	_origin = position
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	add_child(cs)
	_build_cart()
	position = _origin + offset_at(Game.course_time)
	reset_physics_interpolation()
	add_to_group("course_clock")
	_rumble = WorldAudio.loop("frontier_cart_rumble", self, -8.0, 22.0, 4.0, false)


func _hums() -> bool:
	return false


func _process(_dt: float) -> void:
	var t: float = Game.course_time
	var v: float = (offset_at(t + 0.05) - offset_at(t)).length() / 0.05
	var moving: bool = v > 0.6
	if moving != _was_moving:
		_was_moving = moving
		_sparks.emitting = moving
		WorldAudio.set_active(_rumble, moving)
		if not moving:
			# SOUND: the cart banging into the buffer at the end of its run
			WorldAudio.at(self, "frontier_cart_clunk", global_position, 0.7, 30.0)


func _build_cart() -> void:
	var iron: StandardMaterial3D = Look.flat(Color(0.2, 0.19, 0.19), 0.5, 0.7)
	var rust: StandardMaterial3D = Look.flat(tint, 0.85, 0.2)
	var ore: StandardMaterial3D = Look.flat(Color(0.5, 0.42, 0.36), 0.95)
	var gold: StandardMaterial3D = Look.flat(Color(1.0, 0.8, 0.3), 0.3, 0.8, 0.6)
	# the deck you stand on is the heaped ore (a walkable top with the usual trim)
	var deck := Look.platform_box(size, "alt")
	add_child(deck)
	# the tub: sloped iron sides flaring out round the ore, banded with rivets
	var hy: float = size.y * 0.5
	for sx: float in [-1.0, 1.0]:
		add_child(Look.box(Vector3(0.12, 1.0, size.z + 0.1), rust, Vector3(sx * (size.x * 0.5 + 0.06), hy - 0.55, 0)))
	for sz: float in [-1.0, 1.0]:
		add_child(Look.box(Vector3(size.x + 0.24, 1.0, 0.12), rust, Vector3(0, hy - 0.55, sz * (size.z * 0.5 + 0.06))))
	for y: float in [hy - 0.12, hy - 0.95]:
		add_child(Look.box(Vector3(size.x + 0.3, 0.1, size.z + 0.3), iron, Vector3(0, y, 0)))
	# glints of gold in the ore
	for i: int in 5:
		var a: float = TAU * float(i) / 5.0 + 0.4
		add_child(Look.sphere(0.09, gold, Vector3(cos(a) * size.x * 0.3, hy + 0.02, sin(a) * size.z * 0.3)))
	# chassis and four flanged wheels on the rails below
	add_child(Look.box(Vector3(size.x * 0.7, 0.2, size.z * 0.8), iron, Vector3(0, hy - 1.15, 0)))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var w := Look.cylinder(0.32, 0.14, iron, Vector3(sx * size.x * 0.32, hy - 1.33, sz * size.z * 0.3), -1.0, 14)
			w.rotation.z = PI * 0.5
			add_child(w)
	# sparks off the wheels while it runs
	_sparks = Fx.sparks({"amount": 16, "lifetime": 0.35, "one_shot": false, "emitting": false, "explosiveness": 0.0,
		"shape": "box", "extents": Vector3(size.x * 0.35, 0.05, size.z * 0.3), "dir": Vector3(0, 0.4, 1),
		"spread": 40.0, "speed": Vector2(2.0, 5.0), "size": Vector2(0.05, 0.3), "color": Color(3.0, 1.8, 0.6),
		"aabb": AABB(Vector3(-200, -20, -200), Vector3(400, 40, 400))})
	_sparks.position = Vector3(0, hy - 1.6, 0)
	add_child(_sparks)
