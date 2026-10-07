class_name ArcadeChomper
extends Node3D
## Pixel Panic: CHOMPERS ON RAILS. A voxel chomper (or one of the four ghosts) patrols a rail of
## pellets on the course clock, or a pong ball bounces round a court. Touch it and you are sent back.
## Its whole path is drawn in advance as a dotted rail, and it is a pure function of Game.course_time
## (identical for every racer), so a route can predict it: pos_at(t) / clear_at().
##   LOOP     a closed polyline, run round and round at `speed` m/s
##   PINGPONG an open polyline, run there and back
##   COURT    `points` = [min corner, max corner] of a rectangle (x / z); `vel` is the ball's
##            velocity (m/s) before it bounces off the four walls, starting at `court_o` m along
## kind: 0 chomper (yellow), 1 red ghost, 2 pink, 3 cyan, 4 orange, 5 pong ball (white cube)

enum Mode { LOOP, PINGPONG, COURT }

@export var mode: Mode = Mode.PINGPONG
@export var kind: int = 0
@export var points: Array[Vector3] = []
@export var speed: float = 6.0
## Distance already travelled at course time 0 (m); for COURT the ball's starting offset (x, z).
@export var offset: float = 0.0
@export var vel: Vector2 = Vector2(5.0, 3.0)
@export var court_o: Vector2 = Vector2.ZERO
@export var radius: float = 0.85
@export var hover: float = 0.95
@export var show_rail: bool = true

const VOX: float = 0.24

var _len: PackedFloat32Array = PackedFloat32Array()
var _total: float = 0.0
var _holder: Node3D
var _jaw_top: Node3D
var _jaw_bot: Node3D
var _hit: Area3D
var _loop: AudioStreamPlayer3D
var _last_dir: Vector3 = Vector3.ZERO
var _bounce_t: float = -1.0
var _trail: GPUParticles3D


func _ready() -> void:
	_total = 0.0
	_len.clear()
	_len.append(0.0)
	for i: int in range(1, points.size()):
		_total += points[i].distance_to(points[i - 1])
		_len.append(_total)
	if mode == Mode.LOOP and points.size() > 1:
		_total += points[points.size() - 1].distance_to(points[0])
		_len.append(_total)
	_holder = Node3D.new()
	add_child(_holder)
	_hit = ArcadeFx.hazard_sphere(radius * 0.92, Vector3(0, hover, 0))
	_holder.add_child(_hit)
	_build_body()
	if show_rail:
		_build_rail()
	_build_fx()
	# SOUND: arcade_chomper_loop - a "waka waka" bubbling loop that follows the chomper (loop)
	_loop = WorldAudio.loop("arcade_ball_hum" if kind == 5 else "arcade_chomper_loop", _holder, -12.0, 18.0, 4.0)
	add_to_group("course_clock")
	_place(Game.course_time)


func snap_to_clock() -> void:
	_place(Game.course_time)
	reset_physics_interpolation()


func _physics_process(_dt: float) -> void:
	_place(Game.course_time)


func _process(_dt: float) -> void:
	var t: float = Game.course_time
	if kind == 0 and _jaw_top != null:
		var open: float = 0.05 + 0.62 * (0.5 + 0.5 * sin(t * TAU * 2.6))
		_jaw_top.rotation.x = open
		_jaw_bot.rotation.x = -open
	elif kind >= 1 and kind <= 4:
		_holder.position.y = sin(t * 5.0 + float(get_instance_id() % 7)) * 0.05
	if kind == 5:
		_holder.rotation.y = t * 1.5


## Ground-level position (the rail point) at course time `time`.
func pos_at(time: float) -> Vector3:
	if mode == Mode.COURT:
		var lo: Vector3 = points[0]
		var hi: Vector3 = points[1]
		var w: float = maxf(hi.x - lo.x, 0.1)
		var d: float = maxf(hi.z - lo.z, 0.1)
		return Vector3(lo.x + _tri(vel.x * time + court_o.x, w), lo.y, lo.z + _tri(vel.y * time + court_o.y, d))
	if points.size() < 2:
		return global_position if points.is_empty() else points[0]
	var dist: float = speed * time + offset
	var m: float
	if mode == Mode.LOOP:
		m = fposmod(dist, _total)
	else:
		var two: float = _total * 2.0
		m = fposmod(dist, two)
		if m > _total:
			m = two - m
	return _point_at(m)


## Triangle wave 0..len..0 of x.
func _tri(x: float, len_m: float) -> float:
	var m: float = fposmod(x, len_m * 2.0)
	return m if m <= len_m else len_m * 2.0 - m


func _point_at(m: float) -> Vector3:
	var n: int = _len.size()
	for i: int in range(1, n):
		if m <= _len[i] or i == n - 1:
			var a: Vector3 = points[i - 1]
			var b: Vector3 = points[i] if i < points.size() else points[0]
			var seg: float = maxf(_len[i] - _len[i - 1], 0.001)
			return a.lerp(b, clampf((m - _len[i - 1]) / seg, 0.0, 1.0))
	return points[0]


## True when the chomper stays at least radius + margin (flat) from `spot` over [now + a, now + b].
func clear_at(spot: Vector3, margin: float, a: float, b: float, time: float = -1.0) -> bool:
	var t0: float = Game.course_time if time < 0.0 else time
	var s: float = a
	var r: float = radius + margin
	while s <= b:
		var p: Vector3 = pos_at(t0 + s)
		if Vector2(p.x - spot.x, p.z - spot.z).length() < r:
			return false
		s += 0.04
	return true


func _place(t: float) -> void:
	var p: Vector3 = pos_at(t)
	_holder.global_position = Vector3(p.x, p.y, p.z)
	var q: Vector3 = pos_at(t + 0.05)
	var dir := Vector3(q.x - p.x, 0.0, q.z - p.z)
	if dir.length() > 0.001:
		dir = dir.normalized()
		if kind != 5:
			# face the way it is going (-Z forward)
			_holder.global_basis = Basis.looking_at(dir, Vector3.UP)
		if mode == Mode.COURT and _last_dir != Vector3.ZERO and dir.dot(_last_dir) < 0.9 and t - _bounce_t > 0.2:
			_bounce_t = t
			# SOUND: arcade_ball_ping - the pong ball hitting a wall
			WorldAudio.at(self, "arcade_ball_ping", p + Vector3(0, hover, 0), 0.5, 26.0)
		_last_dir = dir


# ---- looks ---------------------------------------------------------------------------------------

func _mat(col: Color) -> ShaderMaterial:
	var m: ShaderMaterial = ArcadeFx.block_mat(col, Vector3.ONE * VOX, 0.7)
	m.set_shader_parameter("bevel", VOX * 0.2)
	return m


## A MultiMeshInstance3D of voxel cubes at `cells` (grid coordinates, centred on the origin).
func _voxels(cells: Array[Vector3], col: Color) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * (VOX - 0.01)
	mm.mesh = bm
	mm.instance_count = cells.size()
	for i: int in cells.size():
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, cells[i] * VOX))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = _mat(col)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _build_body() -> void:
	var body := Node3D.new()
	body.position = Vector3(0, hover, 0)
	_holder.add_child(body)
	var rad: int = int(round(radius / VOX))
	if kind == 0:
		# a voxel sphere in two jaws that hinge at the back and open toward the front (-Z)
		var top: Array[Vector3] = []
		var bot: Array[Vector3] = []
		for x: int in range(-rad, rad + 1):
			for y: int in range(-rad, rad + 1):
				for z: int in range(-rad, rad + 1):
					var d: float = Vector3(x, y, z).length()
					if d <= float(rad) + 0.3 and d > float(rad) - 1.25:
						(top if y >= 0 else bot).append(Vector3(x, y, z))
		_jaw_top = Node3D.new()
		_jaw_bot = Node3D.new()
		body.add_child(_jaw_top)
		body.add_child(_jaw_bot)
		# the jaws hinge about the sphere's centre (the X axis) and open toward the front (-Z)
		_jaw_top.add_child(_voxels(top, ArcadeFx.YELLOW))
		_jaw_bot.add_child(_voxels(bot, ArcadeFx.YELLOW))
		for ex: float in [-1.0, 1.0]:
			var eye := Look.box(Vector3.ONE * VOX * 0.9, Look.flat(ArcadeFx.INK, 0.5), Vector3(ex * rad * VOX * 0.62, rad * VOX * 0.5, -rad * VOX * 0.35))
			_jaw_top.add_child(eye)
		return
	if kind == 5:
		var ball := Look.box(Vector3.ONE * 0.7, ArcadeFx.glow_mat(ArcadeFx.WHITE, 2.2), Vector3.ZERO)
		ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(ball)
		var halo := Look.box(Vector3.ONE * 1.05, ArcadeFx.glow_mat(ArcadeFx.CYAN, 1.5, 0.28), Vector3.ZERO)
		halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(halo)
		return
	# a ghost: dome, straight sides, a ragged skirt
	var cols: Array[Color] = [ArcadeFx.RED, ArcadeFx.RED, Color(1.0, 0.45, 0.8), ArcadeFx.CYAN, ArcadeFx.ORANGE]
	var gc: Color = cols[clampi(kind, 1, 4)]
	var rows: Array[String] = ["..###..", ".#####.", "#######", "#######", "#######", "#######", "##.#.##"]
	var cells: Array[Vector3] = []
	for r: int in rows.size():
		var row: String = rows[r]
		for c: int in row.length():
			if row[c] == "#":
				for z: int in range(-2, 3):
					# a rounder section: trim the corners of the front and back layers
					if absi(z) == 2 and (r == 0 or r == 6 or c == 0 or c == 6):
						continue
					cells.append(Vector3(float(c) - 3.0, 3.0 - float(r), float(z)))
	body.add_child(_voxels(cells, gc))
	body.position.y += 0.0
	# eyes on the front (-Z): white squares with blue pupils
	for ex: float in [-1.0, 1.0]:
		var white := Look.box(Vector3(VOX * 1.5, VOX * 1.8, VOX * 0.5), ArcadeFx.glow_mat(Color.WHITE, 1.6), Vector3(ex * VOX * 1.4, VOX * 1.2, -VOX * 2.6))
		white.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(white)
		var pup := Look.box(Vector3(VOX * 0.8, VOX * 1.0, VOX * 0.3), ArcadeFx.glow_mat(ArcadeFx.BLUE, 1.2), Vector3(ex * VOX * 1.4, VOX * 1.0, -VOX * 2.95))
		pup.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(pup)


func _build_rail() -> void:
	var pel: Array[Vector3] = []
	if mode == Mode.COURT:
		var lo: Vector3 = points[0]
		var hi: Vector3 = points[1]
		var step: float = 1.6
		var corners: Array[Vector3] = [Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, lo.y, lo.z)]
		for i: int in 4:
			var a: Vector3 = corners[i]
			var b: Vector3 = corners[i + 1]
			var n: int = maxi(int(a.distance_to(b) / step), 1)
			for k: int in n:
				pel.append(a.lerp(b, float(k) / float(n)))
	else:
		var n_pts: int = points.size()
		var segs: int = n_pts if mode == Mode.LOOP else n_pts - 1
		for i: int in segs:
			var a2: Vector3 = points[i]
			var b2: Vector3 = points[(i + 1) % n_pts]
			var n2: int = maxi(int(a2.distance_to(b2) / 0.9), 1)
			for k: int in n2:
				pel.append(a2.lerp(b2, float(k) / float(n2)))
		pel.append(points[n_pts - 1] if mode == Mode.PINGPONG else points[0])
	if pel.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new()
	bm.size = Vector3(0.14, 0.14, 0.14)
	mm.mesh = bm
	mm.instance_count = pel.size()
	for i: int in pel.size():
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, pel[i] + Vector3(0, 0.12, 0)))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = ArcadeFx.glow_mat(ArcadeFx.YELLOW if kind != 5 else ArcadeFx.CYAN, 1.8)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	add_child(mi)
	# power pellets at the ends of an open rail
	if mode == Mode.PINGPONG:
		for p: Vector3 in [points[0], points[points.size() - 1]]:
			var big := Look.box(Vector3.ONE * 0.36, ArcadeFx.glow_mat(ArcadeFx.WHITE, 2.4), Vector3.ZERO)
			big.top_level = true
			big.position = p + Vector3(0, 0.3, 0)
			big.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(big)


func _build_fx() -> void:
	var col: Color = ArcadeFx.YELLOW
	if kind >= 1 and kind <= 4:
		var gcols: Array[Color] = [ArcadeFx.RED, ArcadeFx.RED, Color(1.0, 0.45, 0.8), ArcadeFx.CYAN, ArcadeFx.ORANGE]
		col = gcols[kind]
	elif kind == 5:
		col = ArcadeFx.WHITE
	_trail = Fx.trail({"amount": 18, "lifetime": 0.35, "emitting": true, "facing": "mesh", "mesh": ArcadeFx.pixel_mesh(),
		"scale": Vector2(0.5, 1.0), "color": Fx.hot(col, 1.6), "curve": "shrink", "speed": Vector2(0.0, 0.3),
		"aabb": AABB(Vector3(-30, -3, -30), Vector3(60, 8, 60))})
	_trail.position = Vector3(0, hover, 0)
	_holder.add_child(_trail)
