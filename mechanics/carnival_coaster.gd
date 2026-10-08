class_name CarnivalCoaster
extends MovingPlatform
## Carnival Chaos: a COASTER CAR you ride. A little open car (the deck is the floor you stand on)
## shuttles along a rail between two stations, hills and all. Everything is a pure function of the
## course clock, so the bot can predict it and every racer sees the same car.
##
## One cycle (period = 2 * (dock + travel)):
##   dock at A for `dock` s  ->  run A to B in `travel` s (eased: it pulls out gently, peaks mid-way, brakes in)
##   dock at B for `dock` s  ->  run back to A
## The tell: for the last `tell` s (>= 0.8) of every dock the car's lamps flash and a bell rings, then the
## car pulls out. A rider is carried with the car's full velocity (it is a kinematic body, like every mover).
##
## `points` (offsets from the car's start, at A) are the rail's control points; the rail is a smooth
## Catmull-Rom curve through them. Rails, ties and supports are built as a separate static node.

@export var dock: float = 4.0
@export var travel: float = 5.0
## Dwell at B and the return trip (shorter, so the car is back at A quickly).
@export var dock_b: float = 2.5
@export var back: float = 2.0
@export var tell: float = 1.1
## Depth (m) the rail's supports reach below its lowest point.
@export var support_depth: float = 16.0
@export var tint: Color = Color(0.95, 0.2, 0.25)

var _samples: PackedVector3Array = PackedVector3Array()
var _cum: PackedFloat32Array = PackedFloat32Array()
var _len: float = 0.0
var _lamp_mats: Array[StandardMaterial3D] = []
var _lamp: OmniLight3D
var _bell_flag: int = -1
var _track: Node3D
var _hum: AudioStreamPlayer3D


func _ready() -> void:
	sync_to_physics = false
	collision_layer = 1
	collision_mask = 0
	_origin = position
	tell = maxf(tell, 0.8)
	_bake()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	add_child(cs)
	_build_car()
	position = _origin + offset_at(Game.course_time)
	reset_physics_interpolation()
	add_to_group("course_clock")
	_build_track.call_deferred()
	_hum = WorldAudio.loop("carnival_coaster_rumble", self, -14.0, 26.0, 4.0, false)


func _hums() -> bool:
	return false


# ---- the rail ------------------------------------------------------------------------------

func _bake() -> void:
	var pts: Array[Vector3] = points
	if pts.size() < 2:
		pts = [Vector3.ZERO, Vector3(0, 0, -10)]
	_samples = PackedVector3Array()
	var n: int = pts.size()
	for i: int in n - 1:
		var p0: Vector3 = pts[maxi(i - 1, 0)]
		var p1: Vector3 = pts[i]
		var p2: Vector3 = pts[i + 1]
		var p3: Vector3 = pts[mini(i + 2, n - 1)]
		var steps: int = maxi(int(p1.distance_to(p2) / 0.5), 4)
		for k: int in steps:
			var u: float = float(k) / float(steps)
			_samples.append(_cr(p0, p1, p2, p3, u))
	_samples.append(pts[n - 1])
	_cum = PackedFloat32Array()
	_cum.append(0.0)
	for i: int in range(1, _samples.size()):
		_cum.append(_cum[i - 1] + _samples[i].distance_to(_samples[i - 1]))
	_len = _cum[_cum.size() - 1]


static func _cr(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, u: float) -> Vector3:
	var u2: float = u * u
	var u3: float = u2 * u
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u3)


func rail_length() -> float:
	return _len


## Offset from the start at arc distance `s` along the rail.
func point_at(s: float) -> Vector3:
	s = clampf(s, 0.0, _len)
	var lo: int = 0
	var hi: int = _cum.size() - 1
	while hi - lo > 1:
		var mid: int = (lo + hi) >> 1
		if _cum[mid] <= s:
			lo = mid
		else:
			hi = mid
	var span: float = _cum[hi] - _cum[lo]
	var k: float = 0.0 if span < 0.0001 else (s - _cum[lo]) / span
	return _samples[lo].lerp(_samples[hi], k)


# ---- the clock -----------------------------------------------------------------------------

func cycle() -> float:
	return dock + travel + dock_b + back


## Seconds into the cycle at `time`.
func cycle_s(time: float) -> float:
	return fposmod(time + phase * cycle(), cycle())


## Fraction of the rail (0 = A, 1 = B) at `time`.
func progress_at(time: float) -> float:
	var s: float = cycle_s(time)
	if s < dock:
		return 0.0
	s -= dock
	if s < travel:
		return KitUtil.smoother(s / travel)
	s -= travel
	if s < dock_b:
		return 1.0
	s -= dock_b
	return 1.0 - KitUtil.smoother(s / back)


func offset_at(time: float) -> Vector3:
	return point_at(progress_at(time) * _len)


## 0 = docked at A, 1 = docked at B, -1 = running.
func dock_at(time: float) -> int:
	var s: float = cycle_s(time)
	if s < dock:
		return 0
	if s >= dock + travel and s < dock + travel + dock_b:
		return 1
	return -1


## True when the car stays docked at station `which` (0 = A, 1 = B) for the next `window` s.
func docked_for(time: float, which: int, window: float) -> bool:
	var s: float = 0.0
	while s <= window + 0.0001:
		if dock_at(time + s) != which:
			return false
		s += 0.05
	return true


## Seconds until the car next pulls out of station `which`.
func departs_in(time: float, which: int) -> float:
	var s: float = cycle_s(time)
	var end: float = dock if which == 0 else dock + travel + dock_b
	var d: float = end - s
	return d if d >= 0.0 else d + cycle()


# ---- looks ---------------------------------------------------------------------------------

func _build_car() -> void:
	var body: StandardMaterial3D = Look.flat(tint, 0.4, 0.1)
	var cream: StandardMaterial3D = Look.flat(Color(1.0, 0.95, 0.85), 0.5)
	var gold: StandardMaterial3D = Look.flat(Color(1.0, 0.8, 0.25), 0.3, 0.7, 0.2)
	var dark: StandardMaterial3D = Look.flat(Color(0.16, 0.12, 0.16), 0.6)
	var hx: float = size.x * 0.5
	var hz: float = size.z * 0.5
	# the floor slab: painted deck with a cream chevron stripe
	add_child(Look.box(size, body, Vector3.ZERO))
	add_child(Look.box(Vector3(size.x - 0.5, 0.04, size.z - 0.5), cream, Vector3(0, size.y * 0.5 + 0.012, 0)))
	for z: float in [-hz * 0.55, 0.0, hz * 0.55]:
		var chev := Look.box(Vector3(size.x - 0.9, 0.05, 0.16), Look.flat(tint.lightened(0.15), 0.5), Vector3(0, size.y * 0.5 + 0.03, z))
		add_child(chev)
	# side walls, low enough to step over, with gold rail caps (visual only)
	for sx: float in [-1.0, 1.0]:
		add_child(Look.box(Vector3(0.14, 0.46, size.z), body, Vector3(sx * (hx + 0.02), size.y * 0.5 + 0.2, 0)))
		add_child(Look.box(Vector3(0.2, 0.08, size.z + 0.1), gold, Vector3(sx * (hx + 0.02), size.y * 0.5 + 0.46, 0)))
	# the nose: a rounded cone with a headlamp, and a tail fin
	var nose := Look.cylinder(hx * 0.95, 0.9, body, Vector3(0, 0.1, -hz - 0.35), 0.2, 4)
	nose.rotation = Vector3(-PI * 0.5, 0, PI * 0.25)
	add_child(nose)
	add_child(Look.box(Vector3(size.x * 0.7, 0.9, 0.16), gold, Vector3(0, size.y * 0.5 + 0.5, hz + 0.05)))
	# wheels
	for sx: float in [-1.0, 1.0]:
		for z: float in [-hz * 0.6, hz * 0.6]:
			var w := Look.cylinder(0.34, 0.14, dark, Vector3(sx * (hx - 0.1), -size.y * 0.5 - 0.1, z), -1.0, 14)
			w.rotation.z = PI * 0.5
			add_child(w)
	# the four warning lamps on the corners: flash during the tell
	for sx2: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var m: StandardMaterial3D = Look.flat(Color(1.0, 0.85, 0.3), 0.3, 0.0, 0.3).duplicate() as StandardMaterial3D
			_lamp_mats.append(m)
			var bulb := Look.sphere(0.15, m, Vector3(sx2 * (hx + 0.02), size.y * 0.5 + 0.62, sz * (hz - 0.2)))
			bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(bulb)
	_lamp = OmniLight3D.new()
	_lamp.light_color = Color(1.0, 0.8, 0.4)
	_lamp.omni_range = 7.0
	_lamp.light_energy = 0.0
	_lamp.shadow_enabled = false
	_lamp.position = Vector3(0, 1.4, 0)
	add_child(_lamp)


func _build_track() -> void:
	if not is_inside_tree():
		return
	_track = Node3D.new()
	_track.top_level = true
	add_child(_track)
	_track.global_position = _origin_world()
	var rail: StandardMaterial3D = Look.flat(Color(0.95, 0.78, 0.25), 0.3, 0.8)
	var tie_mat: StandardMaterial3D = Look.flat(Color(0.35, 0.2, 0.15), 0.8)
	var post_mat: StandardMaterial3D = Look.flat(Color(0.9, 0.9, 0.95), 0.6)
	var low: float = INF
	for p: Vector3 in _samples:
		low = minf(low, p.y)
	var step_s: float = 0.9
	var s: float = 0.0
	var prev: Vector3 = point_at(0.0)
	var drop: float = size.y * 0.5 + 0.12
	var post_n: int = 0
	while s < _len:
		s = minf(s + step_s, _len)
		var cur: Vector3 = point_at(s)
		var mid: Vector3 = (prev + cur) * 0.5 - Vector3(0, drop, 0)
		var dir: Vector3 = cur - prev
		var l: float = dir.length()
		if l > 0.01:
			var yaw: float = atan2(-dir.x, -dir.z)
			var pitch: float = asin(clampf(dir.y / l, -1.0, 1.0))
			var b := Basis.from_euler(Vector3(pitch, yaw, 0.0))
			for sx: float in [-1.0, 1.0]:
				var r := Look.box(Vector3(0.14, 0.14, l + 0.04), rail, Vector3.ZERO)
				r.transform = Transform3D(b, mid + b * Vector3(sx * (size.x * 0.5 - 0.1), -0.02, 0))
				_track.add_child(r)
			var tie := Look.box(Vector3(size.x + 0.5, 0.1, 0.22), tie_mat, Vector3.ZERO)
			tie.transform = Transform3D(b, mid - Vector3(0, 0.1, 0))
			_track.add_child(tie)
		# a support post every ~4 m
		post_n += 1
		if post_n % 4 == 0:
			var top_y: float = cur.y - drop - 0.15
			var h: float = top_y - (low - support_depth)
			var pst := Look.box(Vector3(0.3, h, 0.3), post_mat, Vector3(cur.x, top_y - h * 0.5, cur.z))
			_track.add_child(pst)
			var cap := Look.box(Vector3(size.x * 0.8, 0.14, 0.4), post_mat, Vector3(cur.x, top_y, cur.z))
			_track.add_child(cap)
		prev = cur
	# station boards at both ends: a gold-edged landing strip
	for end: Vector3 in [point_at(0.0), point_at(_len)]:
		_track.add_child(Look.box(Vector3(size.x + 1.4, 0.08, 0.5), Look.flat(Color(1.0, 0.82, 0.25), 0.4, 0.0, 0.6), end - Vector3(0, drop - 0.04, 0)))


func _origin_world() -> Vector3:
	var p: Node3D = get_parent() as Node3D
	return (p.global_transform * _origin) if p != null else _origin


func _process(_dt: float) -> void:
	var t: float = Game.course_time
	var d: int = dock_at(t)
	var left: float = INF
	if d >= 0:
		left = departs_in(t, d)
	var k: float = clampf(1.0 - left / tell, 0.0, 1.0) if left <= tell else 0.0
	var blink: float = 0.5 + 0.5 * sin(t * (10.0 + 14.0 * k) * TAU * 0.5)
	var e: float = 0.3 if k <= 0.0 else lerpf(0.6, 3.6, blink)
	for m: StandardMaterial3D in _lamp_mats:
		m.emission_enabled = true
		m.emission = Color(1.0, 0.8, 0.3)
		m.emission_energy_multiplier = e
	_lamp.light_energy = 0.0 if k <= 0.0 else 0.6 + 1.6 * blink
	_lamp.visible = k > 0.0
	WorldAudio.set_active(_hum, d < 0)
	# SOUND: carnival_coaster_bell - a clanging station bell through the last second before it pulls out
	var flag: int = -1 if k <= 0.0 else int(floor(t / 0.35))
	if flag != _bell_flag:
		_bell_flag = flag
		if flag >= 0:
			WorldAudio.at(self, "carnival_coaster_bell", global_position, 0.7, 28.0)
