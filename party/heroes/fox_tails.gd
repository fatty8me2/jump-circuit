class_name FoxTails
extends Node3D
## The Nine-Tailed Fox's tails: nine chains of points simulated in world space, each point
## springing toward an ideal pose with stiffness falling off toward the tip, so the tails lag,
## whip round on a turn, fan out on a jump, stream back when running fast and curl lazily
## when idle. Drawn as one MultiMesh of overlapping energy ellipsoids (a solid chakra core)
## plus the same instances again through an additive flame shell (the licking fringe), with
## flames streaming off every tip. Purely cosmetic.
##
## Sits at the base of the spine; its own basis is the body frame (front -Z, up +Y).

const TAILS: int = 9
const SEGS: int = 10
const LENGTH: float = 1.5

## The racer (Player or RemoteRacer): velocity and grounded drive the pose.
var body: Node3D
## Sprout / wilt: tail length and thickness 0..1 (tween it).
var grow: float = 0.0
## A pose that overrides the automatic one ("charge", "roar", "wilt"; "" = automatic).
var pose: String = ""
## Burn-away 0..1 (the expiry).
var dissolve: float = 0.0:
	set(v):
		dissolve = v
		if _core_mat != null:
			_core_mat.set_shader_parameter("dissolve", v)
		if _fringe_mat != null:
			_fringe_mat.set_shader_parameter("alpha", clampf(1.0 - v * 1.4, 0.0, 1.0))

var _p := PackedVector3Array()
var _v := PackedVector3Array()
var _mm: MultiMesh
var _core: MultiMeshInstance3D
var _fringe: MultiMeshInstance3D
var _core_mat: ShaderMaterial
var _fringe_mat: ShaderMaterial
var _tip_fx: Array[GPUParticles3D] = []
var _licks: GPUParticles3D
var _t: float = 0.0
var _started: bool = false
var _last_root: Vector3 = Vector3.ZERO
var _prev_yaw: float = 0.0
var _yaw_rate: float = 0.0
# eased pose knobs
var _elev: float = 0.6
var _phi: float = 0.9
var _spread: float = 1.65
var _curl: float = 1.1
var _curl_to: float = 1.57
var _wave: float = 0.2
var _tremble: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_p.resize(TAILS * (SEGS + 1))
	_v.resize(TAILS * (SEGS + 1))
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_custom_data = true
	_mm.mesh = PartyFx.sphere_mesh(0.5, 12)
	_mm.instance_count = TAILS * SEGS
	for i: int in TAILS:
		for s: int in SEGS:
			var u: float = (float(s) + 0.5) / float(SEGS)
			var c: Color = Color(0.75, 0.45, 0.4).lerp(Color(1.15, 1.6, 2.2), pow(u, 2.2))
			c.a = 1.0 + u * 0.3
			_mm.set_instance_custom_data(i * SEGS + s, c)
			_mm.set_instance_transform(i * SEGS + s, Transform3D(Basis().scaled(Vector3.ONE * 0.001), Vector3.ZERO))
	_core_mat = HeroFx.energy_mat(Color(1.0, 0.33, 0.03), Color(1.0, 0.62, 0.16), 1.25, 3.5)
	_core_mat.set_shader_parameter("use_custom", true)
	_core_mat.set_shader_parameter("rim_amt", 0.4)
	_core_mat.set_shader_parameter("edge", Color(1.0, 0.6, 0.15))
	_core = MultiMeshInstance3D.new()
	_core.multimesh = _mm
	_core.material_override = _core_mat
	_core.top_level = true
	_core.layers = HeroFx.LAYER
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_core.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_core)
	_fringe_mat = HeroFx.flame_mat(Color(0.9, 0.12, 0.0), Color(1.0, 0.42, 0.04), 0.9, 0.35, 3.0)
	_fringe_mat.set_shader_parameter("grow", 0.2)
	_fringe_mat.set_shader_parameter("freq", 6.0)
	_fringe_mat.set_shader_parameter("base_alpha", 0.0)
	_fringe = MultiMeshInstance3D.new()
	_fringe.multimesh = _mm
	_fringe.material_override = _fringe_mat
	_fringe.top_level = true
	_fringe.layers = HeroFx.LAYER
	_fringe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fringe.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_fringe)
	# flames streaming off every tip (world space: they trail behind a moving tail)
	for i: int in TAILS:
		var f: GPUParticles3D = HeroFx.em({"amount": 12, "lifetime": 0.36, "size": 0.24, "fixed_fps": 0,
			"speed": Vector2(0.2, 1.0), "spread": 50.0, "dir": Vector3.UP, "gravity": Vector3(0, 2.5, 0),
			"curve": "shrink", "scale": Vector2(0.6, 1.0), "box_aabb": 6.0, "additive": false,
			"tex": Fx.Tex.SMOKE, "angle": Vector2(0, 360),
			"colors": PackedColorArray([Color(2.0, 1.5, 0.5, 0.95), Color(1.8, 0.45, 0.04, 0.8), Color(0.7, 0.08, 0.0, 0.0)])})
		f.top_level = true
		add_child(f)
		_tip_fx.append(f)
	# flame licks along the tails: one emitter hopping between random beads every frame
	_licks = HeroFx.em({"amount": 40, "lifetime": 0.42, "size": 0.22, "fixed_fps": 0,
		"speed": Vector2(0.4, 1.4), "spread": 35.0, "dir": Vector3.UP, "gravity": Vector3(0, 3.0, 0),
		"curve": "shrink", "box_aabb": 6.0, "shape": "sphere", "radius": 0.08, "additive": false,
		"tex": Fx.Tex.SMOKE, "angle": Vector2(0, 360),
		"colors": PackedColorArray([Color(2.0, 1.3, 0.4, 0.9), Color(1.7, 0.4, 0.03, 0.7), Color(0.6, 0.06, 0.0, 0.0)])})
	_licks.top_level = true
	_licks.interpolate = false
	add_child(_licks)


## World position of tail i's tip.
func tip(i: int) -> Vector3:
	return _p[i * (SEGS + 1) + SEGS] if _started else global_position


## Adds a whip of velocity to every tail (more toward the tips).
func whip(v: Vector3) -> void:
	if not _started:
		return
	for i: int in TAILS:
		for s: int in range(1, SEGS + 1):
			var u: float = float(s) / float(SEGS)
			_v[i * (SEGS + 1) + s] += v * u * u * (0.8 + 0.4 * sin(float(i) * 1.7))


func set_emitting(on: bool) -> void:
	for f: GPUParticles3D in _tip_fx:
		f.emitting = on
	_licks.emitting = on


func _body_vel() -> Vector3:
	if body is Player:
		return (body as Player).velocity
	if body != null and body.has_method("velocity"):
		return body.call("velocity")
	return Vector3.ZERO


func _body_grounded() -> bool:
	if body is Player:
		return (body as Player).grounded
	if body != null and body.has_method("is_grounded"):
		return bool(body.call("is_grounded"))
	return true


func _process(dt: float) -> void:
	if not is_inside_tree() or dt <= 0.0:
		return
	_t += dt
	var xf: Transform3D = global_transform
	var b: Basis = xf.basis.orthonormalized()
	var root: Vector3 = xf.origin
	# how fast the body frame turns (tails fling outward on a hard turn)
	var yaw: float = atan2(b.z.x, b.z.z)
	_yaw_rate = lerpf(_yaw_rate, wrapf(yaw - _prev_yaw, -PI, PI) / dt, 1.0 - exp(-10.0 * dt))
	_prev_yaw = yaw
	_ease_pose(dt, b)
	var n: int = mini(ceili(dt * 120.0), 4)
	var h: float = minf(dt, 0.05) / float(n)
	var teleported: bool = not _started or root.distance_to(_last_root) > 4.0
	_last_root = root
	var ideal := PackedVector3Array()
	ideal.resize(SEGS + 1)
	var seg: float = LENGTH / float(SEGS) * maxf(grow, 0.02)
	for i: int in TAILS:
		_ideal_tail(i, b, root, seg, ideal)
		var base: int = i * (SEGS + 1)
		_p[base] = root
		_v[base] = Vector3.ZERO
		if teleported:
			for s: int in range(1, SEGS + 1):
				_p[base + s] = ideal[s]
				_v[base + s] = Vector3.ZERO
			continue
		for step: int in n:
			for s: int in range(1, SEGS + 1):
				var u: float = float(s) / float(SEGS)
				var k: float = lerpf(320.0, 55.0, pow(u, 0.7))
				var c: float = lerpf(30.0, 9.0, u)
				var idx: int = base + s
				var a: Vector3 = (ideal[s] - _p[idx]) * k - _v[idx] * c
				_v[idx] += a * h
				_p[idx] += _v[idx] * h
			# keep the links their length (a tail, not a rubber band)
			for s: int in range(1, SEGS + 1):
				var idx2: int = base + s
				var d: Vector3 = _p[idx2] - _p[idx2 - 1]
				var l: float = d.length()
				if l > 0.0001:
					_p[idx2] = _p[idx2 - 1] + d * (seg / l)
	_started = true
	_draw()


## The pose the tails spring toward, eased from the racer's motion (or an override).
func _ease_pose(dt: float, b: Basis) -> void:
	var vel: Vector3 = _body_vel()
	var local_v: Vector3 = b.inverse() * vel
	var hs: float = Vector2(vel.x, vel.z).length()
	var run: float = clampf((hs - 4.0) / 9.0, 0.0, 1.0)
	# elevation of the fan's axis above straight back, cone half-angle, sideways spread,
	# curl amount and the direction it curls toward (angle up from back: 90 deg = up)
	var tgt := [deg_to_rad(22.0), deg_to_rad(64.0), deg_to_rad(165.0), 0.95, deg_to_rad(100.0), 0.22, 0.0]
	match pose:
		"charge":
			tgt = [deg_to_rad(55.0), deg_to_rad(58.0), deg_to_rad(175.0), 1.3, deg_to_rad(150.0), 0.06, 0.04]
		"roar":
			tgt = [deg_to_rad(18.0), deg_to_rad(80.0), deg_to_rad(185.0), 0.1, deg_to_rad(90.0), 0.05, 0.08]
		"wilt":
			tgt = [deg_to_rad(-15.0), deg_to_rad(45.0), deg_to_rad(150.0), -0.6, deg_to_rad(90.0), 0.12, 0.0]
		_:
			if not _body_grounded():
				if vel.y > 1.0:
					# rising: fan out wide like a peacock
					var k: float = clampf(vel.y / 10.0, 0.0, 1.0)
					tgt = [deg_to_rad(lerpf(22.0, 15.0, k)), deg_to_rad(lerpf(68.0, 84.0, k)), deg_to_rad(lerpf(170.0, 190.0, k)), 0.45, deg_to_rad(100.0), 0.12, 0.0]
				else:
					# falling: the tails float up above
					var k2: float = clampf(-vel.y / 12.0, 0.0, 1.0)
					tgt = [deg_to_rad(lerpf(35.0, 70.0, k2)), deg_to_rad(60.0), deg_to_rad(160.0), lerpf(0.7, 0.2, k2), deg_to_rad(100.0), 0.16, 0.0]
			if run > 0.0:
				# streaming back behind a fast runner
				var r: Array = [deg_to_rad(12.0), deg_to_rad(24.0), deg_to_rad(150.0), 0.3, deg_to_rad(100.0), 0.16, 0.0]
				for j: int in tgt.size():
					tgt[j] = lerpf(float(tgt[j]), float(r[j]), run * (0.6 if not _body_grounded() else 1.0))
	var e: float = 1.0 - exp(-7.0 * dt)
	_elev = lerpf(_elev, tgt[0], e)
	_phi = lerpf(_phi, tgt[1], e)
	_spread = lerpf(_spread, tgt[2], e)
	_curl = lerpf(_curl, tgt[3], e)
	_curl_to = lerpf(_curl_to, tgt[4], e)
	_wave = lerpf(_wave, tgt[5], e)
	_tremble = lerpf(_tremble, tgt[6], e)
	# a hard turn flings the fan open on the outside for a moment
	_spread += clampf(absf(_yaw_rate) * 0.04, 0.0, 0.35) * e * 3.0
	# sideways motion skews the whole fan the other way (they drag behind)
	_side_drag = lerpf(_side_drag, clampf(-local_v.x * 0.05, -0.5, 0.5), e)


var _side_drag: float = 0.0


func _ideal_tail(i: int, b: Basis, root: Vector3, seg: float, out: PackedVector3Array) -> void:
	var f: float = float(i) / float(TAILS - 1) * 2.0 - 1.0   # -1 .. 1 across the fan
	var ph: float = float(i) * 1.37
	var back: Vector3 = b.z
	var up: Vector3 = b.y
	var right: Vector3 = b.x
	var theta: float = f * _spread * 0.5 + _side_drag + sin(_t * 1.6 + ph) * 0.07
	var axis: Vector3 = back.rotated(right, -_elev)   # tilt the fan's axis up from straight back
	var ax_up: Vector3 = up.rotated(right, -_elev)
	var phi: float = _phi * (1.0 - absf(f) * 0.12)
	var d0: Vector3 = (axis * cos(phi) + (ax_up * cos(theta) + right * sin(theta)) * sin(phi)).normalized()
	# curl toward `curl_to` (measured up from back), outer tails curl a bit less
	var to: Vector3 = back.rotated(right, -_curl_to)
	var bend_axis: Vector3 = d0.cross(to)
	if bend_axis.length() < 0.01:
		bend_axis = right
	bend_axis = bend_axis.normalized()
	var curl: float = _curl * (1.0 - absf(f) * 0.25) + sin(_t * 2.1 + ph * 1.3) * _wave
	var side_axis: Vector3 = d0.cross(bend_axis).normalized()
	out[0] = root
	var p: Vector3 = root
	for s: int in range(1, SEGS + 1):
		var u: float = float(s) / float(SEGS)
		var d: Vector3 = d0.rotated(bend_axis, curl * pow(u, 1.25))
		# a travelling wave down the tail (idle sway / flutter at speed)
		var wv: float = sin(_t * (3.2 + _wave * 6.0) - u * 3.4 + ph) * _wave * 1.4 * u
		d = d.rotated(side_axis, wv)
		if _tremble > 0.0:
			d = (d + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * _tremble).normalized()
		p += d * seg
		out[s] = p


## Radius of a bead along the tail (u 0 at the root .. 1 at the tip).
static func radius_at(u: float) -> float:
	var r: float = lerpf(0.06, 0.13, smoothstep(0.0, 0.4, u))
	return r * (1.0 - smoothstep(0.5, 1.0, u) * 0.8)


func _draw() -> void:
	var g: float = clampf(grow, 0.0, 1.3)
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for i: int in TAILS:
		var base: int = i * (SEGS + 1)
		for s: int in SEGS:
			var a: Vector3 = _p[base + s]
			var c: Vector3 = _p[base + s + 1]
			var d: Vector3 = c - a
			var l: float = d.length()
			var y: Vector3 = d / l if l > 0.0001 else Vector3.UP
			var x: Vector3 = y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
			var z: Vector3 = x.cross(y)
			var u: float = (float(s) + 0.5) / float(SEGS)
			var r: float = radius_at(u) * 2.0 * maxf(g, 0.001)
			var len: float = maxf(l * 2.3, r * 0.9)
			_mm.set_instance_transform(base - i + s, Transform3D(Basis(x * r, y * len, z * r), (a + c) * 0.5))
			lo = lo.min(a)
			hi = hi.max(a)
		var t: Vector3 = _p[base + SEGS]
		lo = lo.min(t)
		hi = hi.max(t)
		var f: GPUParticles3D = _tip_fx[i]
		f.global_position = t
	var box := AABB(lo, hi - lo).grow(0.6)
	_core.custom_aabb = box
	_fringe.custom_aabb = box
	# hop the lick emitter to a random bead
	var ti: int = _rng.randi_range(0, TAILS - 1)
	var si: int = _rng.randi_range(2, SEGS)
	_licks.global_position = _p[ti * (SEGS + 1) + si]
