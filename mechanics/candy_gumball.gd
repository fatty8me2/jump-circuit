class_name CandyGumball
extends Node3D
## Sugar Rush: the gumball run. A giant gumball machine lets a gumball the size of a car go every
## `interval` seconds; it rolls down its chute (`path`, a polyline in this node's space from the
## machine's mouth to the chute's lip, at BALL-CENTRE height) at `speed`, spinning, and drops off
## the lip into the chocolate below. A gumball flattens whoever it rolls over (back to the
## checkpoint). Readable: the machine's mouth flashes and rattles before each release, and every
## ball leaves a trail of sugar glints. A pure function of Game.course_time: ball k leaves the
## machine at (k + phase) * interval.

@export var path: PackedVector3Array = PackedVector3Array()
@export var radius: float = 1.5
@export var speed: float = 7.0
@export var interval: float = 6.0
@export var phase: float = 0.0
@export var colors: PackedColorArray = PackedColorArray([Color(1.0, 0.2, 0.35), Color(0.3, 0.7, 1.0), Color(1.0, 0.85, 0.2),
		Color(0.45, 0.95, 0.5), Color(0.8, 0.45, 1.0), Color(1.0, 0.55, 0.2)])
## After the lip: seconds of falling before the ball is gone.
@export var drop_time: float = 1.6

var _cum: PackedFloat32Array = PackedFloat32Array()
var _len: float = 0.0
var _slots: Array[Dictionary] = []
var _mats: Array[StandardMaterial3D] = []
var _released: int = -999999
var _dropped: Dictionary = {}


func _ready() -> void:
	_cum.resize(path.size())
	var total: float = 0.0
	for i: int in path.size():
		if i > 0:
			total += path[i - 1].distance_to(path[i])
		_cum[i] = total
	_len = maxf(total, 0.01)
	for c: Color in colors:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.12
		m.metallic_specular = 0.9
		m.clearcoat_enabled = true
		m.clearcoat = 1.0
		m.rim_enabled = true
		m.rim = 0.35
		_mats.append(m)
	var n: int = int(ceil((_len / speed + drop_time) / interval)) + 1
	for i: int in n:
		var holder := Node3D.new()
		add_child(holder)
		var ball := Look.sphere(radius, _mats[0])
		holder.add_child(ball)
		# a stripe of lighter sugar round it so the spin reads
		var tm := TorusMesh.new()
		tm.inner_radius = radius * 0.97
		tm.outer_radius = radius * 1.03
		tm.rings = 32
		tm.ring_segments = 6
		var band := Look.mesh_node(tm, Look.flat(Color(1.0, 0.98, 0.95), 0.4))
		band.rotation.x = PI * 0.5
		ball.add_child(band)
		var area := Area3D.new()
		area.collision_layer = 0
		area.collision_mask = 2
		area.monitorable = false
		var sh := SphereShape3D.new()
		sh.radius = radius * 0.92
		var cs := CollisionShape3D.new()
		cs.shape = sh
		area.add_child(cs)
		holder.add_child(area)
		area.body_entered.connect(_on_body)
		var trail: GPUParticles3D = Fx.trail({"amount": 24, "lifetime": 0.7, "shape": "sphere", "radius": radius * 0.8,
			"tex": Fx.Tex.STAR, "size": 0.3, "color": Fx.hot(Color(1.0, 0.95, 1.0), 1.6), "emitting": false,
			"aabb": AABB(Vector3(-200, -100, -200), Vector3(400, 200, 400))})
		holder.add_child(trail)
		var roll: AudioStreamPlayer3D = WorldAudio.loop("candy_gumball_roll", holder, -4.0, 28.0, 6.0, false)
		_slots.append({"node": holder, "ball": ball, "trail": trail, "k": -999999, "roll": roll})
	_apply(Game.course_time)
	add_to_group("course_clock")


## Length of the chute (m) and the time a ball takes to roll it (s).
func chute_length() -> float:
	return _len


## Centre of ball k at `time`, or Vector3.INF when that ball is not out.
func ball_pos(k: int, time: float) -> Vector3:
	var age: float = time - (float(k) + phase) * interval
	if age < 0.0:
		return Vector3.INF
	var d: float = age * speed
	if d <= _len:
		return _point(d)
	var over: float = age - _len / speed
	if over > drop_time:
		return Vector3.INF
	var f: Vector3 = (path[path.size() - 1] - path[path.size() - 2]).normalized()
	f.y = 0.0
	return path[path.size() - 1] + f * speed * over * 0.6 + Vector3(0, -21.0 * over * over, 0)


func _point(d: float) -> Vector3:
	var lo: int = 0
	var hi: int = path.size() - 1
	while hi - lo > 1:
		var mid: int = (lo + hi) >> 1
		if _cum[mid] <= d:
			lo = mid
		else:
			hi = mid
	var seg: float = _cum[hi] - _cum[lo]
	var k: float = 0.0 if seg <= 0.0 else clampf((d - _cum[lo]) / seg, 0.0, 1.0)
	return path[lo].lerp(path[hi], k)


## Arc distance along the chute of the point nearest to world point `p`.
func arc_of(p: Vector3) -> float:
	var lp: Vector3 = to_local(p)
	var best: float = 0.0
	var bd: float = INF
	var d: float = 0.0
	while d <= _len:
		var q: float = _point(d).distance_squared_to(lp)
		if q < bd:
			bd = q
			best = d
		d += 0.2
	return best


## No ball comes within radius + `margin` of world point `p` over [now + a, now + b].
func clear_near(p: Vector3, margin: float, a: float, b: float) -> bool:
	var lp: Vector3 = to_local(p)
	var s: float = a
	while s <= b:
		var t: float = Game.course_time + s
		var newest: int = int(floor(t / interval - phase))
		for k: int in range(newest - _slots.size() + 1, newest + 1):
			var bp: Vector3 = ball_pos(k, t)
			if bp != Vector3.INF and bp.distance_to(lp) < radius + margin:
				return false
		s += 0.05
	return true


func snap_to_clock() -> void:
	_apply(Game.course_time)
	for s: Dictionary in _slots:
		(s["node"] as Node3D).reset_physics_interpolation()


func _physics_process(_dt: float) -> void:
	_apply(Game.course_time)


func _apply(t: float) -> void:
	var newest: int = int(floor(t / interval - phase))
	for k: int in range(newest - _slots.size() + 1, newest + 1):
		var slot: Dictionary = _slots[posmod(k, _slots.size())]
		var node: Node3D = slot["node"]
		var p: Vector3 = ball_pos(k, t)
		var on: bool = p != Vector3.INF
		node.visible = on
		(slot["trail"] as GPUParticles3D).emitting = on
		WorldAudio.set_active(slot["roll"], on and ball_pos(k, t - 0.0) != Vector3.INF and (t - (float(k) + phase) * interval) * speed < _len)
		if not on:
			node.position = Vector3(0, -500, 0)
			continue
		node.position = p
		if int(slot["k"]) != k:
			slot["k"] = k
			var ball: MeshInstance3D = slot["ball"]
			ball.material_override = _mats[posmod(k, _mats.size())]
		# roll: spin about the axis across the chute
		var d: float = (t - (float(k) + phase) * interval) * speed
		var f: Vector3 = (_point(minf(d + 0.5, _len)) - _point(maxf(d - 0.5, 0.0)))
		f.y = 0.0
		if f.length() > 0.01:
			var side: Vector3 = f.normalized().cross(Vector3.UP)
			(slot["ball"] as Node3D).basis = Basis(side.normalized(), -d / radius)


func _process(_dt: float) -> void:
	var t: float = Game.course_time
	var newest: int = int(floor(t / interval - phase))
	if newest != _released:
		if _released != -999999:
			# SOUND: the machine's crank clunks and the gumball drops into the chute
			WorldAudio.at(self, "candy_gumball_drop", to_global(path[0]), 1.0, 60.0)
		_released = newest
	# a ball tipping over the lip into the chocolate
	for k: int in range(newest - _slots.size() + 1, newest + 1):
		var age: float = t - (float(k) + phase) * interval
		if age * speed > _len and age * speed < _len + speed * 0.2 and not _dropped.has(k):
			_dropped[k] = true
			# SOUND: the gumball plops into the chocolate far below
			WorldAudio.at(self, "candy_gumball_splash", to_global(path[path.size() - 1]), 0.8, 60.0)
			if _dropped.size() > 16:
				_dropped.clear()
				_dropped[k] = true


func _on_body(body: Node3D) -> void:
	if not (body is Player):
		return
	var n: Node = self
	while n != null and not n.has_method("fail"):
		n = n.get_parent()
	if n != null:
		n.call_deferred("fail", "hazard")
