class_name ArcadeScroll
extends Node3D
## Pixel Panic: the AUTO-SCROLL. The edge of the screen is a wall of corrupted video parked behind the
## start of the stretch. The moment you step on the trigger the screen starts to scroll: after `delay`
## s the wall creeps up the course along `path` at `speed` m/s, and anything the wall has reached is
## sent back to the checkpoint. It is a pure function of (Game.course_time - trigger time): a respawn
## re-arms it (reset_state), so every try is the same chase. It never moves past `stop_before_end`
## metres short of the path's last point, so the checkpoint at the end is always safe.
## The wall is visible, rumbling and flickering from the start (it is not a surprise), and the first
## `delay` s are a stand-still with a siren: the screen is about to scroll.
##   progress(p)  how far along the path a world point is (the path is extended 60 m back)

const FALL_BACK: float = 60.0

## World points along the course, in order (at least two).
@export var path: Array[Vector3] = []
@export var speed: float = 4.6
@export var delay: float = 2.4
## How far behind the trigger point the front starts (m).
@export var lead: float = 16.0
@export var stop_before_end: float = 6.0
@export var trigger_pos: Vector3 = Vector3.ZERO
@export var trigger_size: Vector3 = Vector3(3, 3, 3)
@export var width: float = 18.0
@export var height: float = 40.0
@export var thickness: float = 3.0

var _pts: PackedVector3Array = PackedVector3Array()
var _cum: PackedFloat32Array = PackedFloat32Array()
var _len: float = 0.0
var _t0: float = -1.0
var _f0: float = 0.0
var _cap: float = 0.0
var _wall: Node3D
var _fx: GPUParticles3D
var _rumble: AudioStreamPlayer3D
var _siren: bool = false


func _ready() -> void:
	add_to_group("resettable")
	var first: Vector3 = path[0]
	var dir0: Vector3 = (path[1] - path[0])
	dir0.y = 0.0
	dir0 = dir0.normalized() if dir0.length() > 0.01 else Vector3.FORWARD
	_pts.append(first - dir0 * FALL_BACK)
	for p: Vector3 in path:
		_pts.append(p)
	_cum.append(0.0)
	for i: int in range(1, _pts.size()):
		_len += _pts[i].distance_to(_pts[i - 1])
		_cum.append(_len)
	_f0 = progress(trigger_pos) - lead
	_cap = _len - stop_before_end
	_build_wall()
	var trig := Area3D.new()
	trig.collision_layer = 0
	trig.collision_mask = 2
	trig.monitorable = false
	var box := BoxShape3D.new()
	box.size = trigger_size
	var cs := CollisionShape3D.new()
	cs.shape = box
	trig.add_child(cs)
	trig.position = trigger_pos
	add_child(trig)
	trig.body_entered.connect(func(b: Node3D) -> void:
		if b is Player and _t0 < 0.0:
			_t0 = Game.course_time
			# SOUND: arcade_scroll_start - the screen jolts and a siren warns: it is about to scroll
			WorldAudio.at(self, "arcade_scroll_start", trigger_pos, 1.0, 60.0)
			WorldAudio.set_active(_rumble, true))
	# SOUND: arcade_scroll_rumble - a low static roar riding the wall (loop)
	_rumble = WorldAudio.loop("arcade_scroll_rumble", _wall, -4.0, 40.0, 8.0, false)
	_place(Game.course_time)


func reset_state() -> void:
	_t0 = -1.0
	_siren = false
	WorldAudio.set_active(_rumble, false)
	_place(Game.course_time)


func snap_to_clock() -> void:
	_place(Game.course_time)


func is_running() -> bool:
	return _t0 >= 0.0


## Progress (m) of the front at course time `time`.
func front_at(time: float) -> float:
	if _t0 < 0.0:
		return _f0
	return minf(_f0 + maxf(time - _t0 - delay, 0.0) * speed, _cap)


## How far along the path (the 60 m extension counts) the world point `p` is.
func progress(p: Vector3) -> float:
	var best: float = 0.0
	var best_d: float = INF
	for i: int in range(1, _pts.size()):
		var a: Vector3 = _pts[i - 1]
		var b: Vector3 = _pts[i]
		var ab: Vector3 = b - a
		var l2: float = maxf(ab.length_squared(), 0.0001)
		var t: float = clampf((p - a).dot(ab) / l2, 0.0, 1.0)
		var d: float = (a + ab * t).distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = _cum[i - 1] + t * sqrt(l2)
	return best


func point_at(m: float) -> Vector3:
	var d: float = clampf(m, 0.0, _len)
	for i: int in range(1, _pts.size()):
		if d <= _cum[i]:
			var seg: float = maxf(_cum[i] - _cum[i - 1], 0.001)
			return _pts[i - 1].lerp(_pts[i], clampf((d - _cum[i - 1]) / seg, 0.0, 1.0))
	return _pts[_pts.size() - 1]


func _physics_process(_dt: float) -> void:
	if _t0 < 0.0:
		return
	var pl: Node3D = WorldAudio.local_player(self)
	if pl == null:
		pl = _find_player()
	if pl == null:
		return
	if progress(pl.global_position) < front_at(Game.course_time) - 0.3:
		var n: Node = self
		while n != null and not n.has_method("fail"):
			n = n.get_parent()
		if n != null:
			n.call_deferred("fail", "hazard")


func _find_player() -> Node3D:
	var n: Node = self
	while n != null and not n.has_method("fail"):
		n = n.get_parent()
	return n.get("player") as Node3D if n != null else null


func _process(_dt: float) -> void:
	_place(Game.course_time)


func _place(time: float) -> void:
	var f: float = front_at(time)
	var p: Vector3 = point_at(f)
	var ahead: Vector3 = point_at(f + 1.0) - p
	ahead.y = 0.0
	if ahead.length() < 0.01:
		ahead = point_at(f) - point_at(f - 1.0)
		ahead.y = 0.0
	if ahead.length() > 0.01:
		_wall.global_basis = Basis.looking_at(ahead.normalized(), Vector3.UP)
	# the wall's leading face at the front, its body behind it, standing from the void up past the stage
	_wall.global_position = p - _wall.global_basis.z * (-thickness * 0.5) + Vector3(0, height * 0.5 - 12.0, 0)
	var moving: bool = _t0 >= 0.0 and time - _t0 > delay and f < _cap - 0.01
	if _fx.emitting != moving:
		_fx.emitting = moving
	if _t0 >= 0.0 and time - _t0 < delay:
		if not _siren and time - _t0 > 0.05:
			_siren = true
	if moving:
		WorldAudio.set_active(_rumble, true)
	elif _t0 < 0.0 or f >= _cap - 0.01:
		WorldAudio.set_active(_rumble, false)


func _build_wall() -> void:
	_wall = Node3D.new()
	_wall.top_level = true
	add_child(_wall)
	var m := ShaderMaterial.new()
	m.shader = preload("res://visual/arcade_wall.gdshader")
	m.set_shader_parameter("thickness", thickness)
	var body := Look.box(Vector3(width, height, thickness), m)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wall.add_child(body)
	# the pixels it kicks up at its leading face
	_fx = Fx.emitter({"amount": 80, "lifetime": 1.2, "shape": "box", "extents": Vector3(width * 0.45, height * 0.2, 0.3),
		"dir": Vector3(0, 0.4, -1), "spread": 40.0, "speed": Vector2(1.0, 4.0), "facing": "mesh", "mesh": ArcadeFx.pixel_mesh(),
		"scale": Vector2(0.6, 2.0), "pick": PackedColorArray([Fx.hot(ArcadeFx.MAGENTA, 2.0), Fx.hot(ArcadeFx.CYAN, 2.0), Fx.hot(ArcadeFx.WHITE, 1.6)]),
		"curve": "shrink", "emitting": false, "aabb": AABB(Vector3(-30, -30, -30), Vector3(60, 60, 60))})
	_fx.position = Vector3(0, 2.0, -thickness * 0.5 - 0.2)
	_wall.add_child(_fx)
