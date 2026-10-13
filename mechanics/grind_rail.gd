class_name GrindRail
extends Node3D
## Grind rail (flow kit, docs/FLOW_KIT.md). A smooth path (Catmull-Rom through `points`, world space)
## with a visible rail. Land on it or jump at it within `snap` m (feet near the rail, from just under
## to a metre and a bit above it, not travelling against its direction) and the real Player is
## carried along it at their speed: a little faster on the way down, a little slower on the way up,
## never under `min_speed`. Sparks fly, steering is ignored apart from a small `lean`.
##   * press jump: leave with the full tangent velocity and a `hop` upward kick
##   * reach the end: leave with the end tangent velocity and a small `end_hop`
##   * another rail near the flight path catches you in turn (rail to rail)
## The carry is the zipline's: `control_enabled` off, the rider's position set on the curve every
## physics tick before the Player's own step. Never a teleport; a respawn lets go at once.
## The node sits at the world origin and `points` are world positions of the rail line (the feet).

@export var points: PackedVector3Array = PackedVector3Array()
@export var snap: float = 1.2
@export var min_speed: float = 9.0
@export var max_speed: float = 30.0
## m/s^2 gained per unit of downward slope (a 30 degree down rail = 0.5 * this).
@export var slope_accel: float = 16.0
@export var hop: float = 6.0
@export var end_hop: float = 2.0
@export var lean: float = 0.3
## World y to run support posts down to every `post_every` metres (NAN = no posts).
@export var post_to_y: float = NAN
@export var post_every: float = 9.0

const BAKE: float = 0.25

var curve: Curve3D
var boarded: int = 0

var _length: float = 1.0
var _box: AABB
var _area: Area3D
var _rider: Player = null
var _was_control: bool = true
var _s: float = 0.0
var _speed: float = 0.0
var _lean_now: float = 0.0
var _cool_until: int = 0
var _released_tick: int = -100000
var _boarded_tick: int = -100000
var _want_release: bool = false
var _sparks: GPUParticles3D
var _hum: AudioStreamPlayer3D
var _glow_mat: StandardMaterial3D


func _ready() -> void:
	process_physics_priority = KitUtil.EARLY
	_build_curve()
	_build_mesh()
	_build_trigger()
	_sparks = Fx.sparks({"amount": 34, "lifetime": 0.32, "one_shot": false, "emitting": false, "explosiveness": 0.0,
		"shape": "point", "dir": Vector3.UP, "spread": 55.0, "speed": Vector2(2.5, 7.0), "local": false,
		"color": Color(2.6, 2.0, 1.0), "aabb": AABB(Vector3(-40, -10, -40), Vector3(80, 30, 80))})
	add_child(_sparks)
	_hum = WorldAudio.loop("flow_rail_grind", _sparks, -12.0, 40.0, 4.0)
	WorldAudio.set_active(_hum, false)
	add_to_group("resettable")


# ---- the path ----------------------------------------------------------------------------------------

func _build_curve() -> void:
	curve = Curve3D.new()
	curve.bake_interval = BAKE
	var n: int = points.size()
	for i: int in n:
		var prev: Vector3 = points[maxi(i - 1, 0)]
		var next: Vector3 = points[mini(i + 1, n - 1)]
		var tn: Vector3 = (next - prev) / 6.0
		curve.add_point(points[i], -tn, tn)
	_length = maxf(curve.get_baked_length(), 0.5)
	_box = AABB(points[0], Vector3.ZERO) if n > 0 else AABB()
	var s: float = 0.0
	while s <= _length:
		_box = _box.expand(curve.sample_baked(s, true))
		s += 1.0


## Physics ticks in `seconds` (the rate is not fixed).
static func _ticks(seconds: float) -> int:
	return int(seconds * float(Engine.physics_ticks_per_second))


func length() -> float:
	return _length


func point_at(s: float) -> Vector3:
	return curve.sample_baked(clampf(s, 0.0, _length), true)


func tangent_at(s: float) -> Vector3:
	var a: Vector3 = point_at(s - 0.4)
	var b: Vector3 = point_at(s + 0.4)
	var d: Vector3 = b - a
	return d.normalized() if d.length() > 0.001 else Vector3.FORWARD


## Distance along the rail of the point nearest to world position `p`.
func offset_of(p: Vector3) -> float:
	return curve.get_closest_offset(p)


func start_point() -> Vector3:
	return point_at(0.0)


func end_point() -> Vector3:
	return point_at(_length)


## Speed after riding from offset `s0` at `v0` m/s to offset `s1` (the Player's rule, simulated).
func speed_at(v0: float, s0: float, s1: float) -> float:
	var v: float = maxf(v0, min_speed)
	var s: float = s0
	var dt: float = 1.0 / 60.0
	while s < s1:
		v = clampf(v - tangent_at(s).y * slope_accel * dt, min_speed, maxf(max_speed, v0))
		s += v * dt
	return v


## Seconds to ride from `s0` to `s1` entering at `v0`.
func ride_time(v0: float, s0: float = 0.0, s1: float = -1.0) -> float:
	var end_s: float = _length if s1 < 0.0 else s1
	var v: float = maxf(v0, min_speed)
	var s: float = s0
	var t: float = 0.0
	var dt: float = 1.0 / 60.0
	while s < end_s:
		v = clampf(v - tangent_at(s).y * slope_accel * dt, min_speed, maxf(max_speed, v0))
		s += v * dt
		t += dt
	return t


## The velocity a rider who jumps off at offset `s` entering at `v0` leaves with (tangent * speed + hop).
func jump_velocity(v0: float, s0: float, s: float) -> Vector3:
	return tangent_at(s) * speed_at(v0, s0, s) + Vector3(0, hop, 0)


## The velocity a rider who rides to the end entering at `v0` leaves with.
func exit_velocity(v0: float) -> Vector3:
	return tangent_at(_length) * speed_at(v0, 0.0, _length) + Vector3(0, end_hop, 0)


# ---- visuals -----------------------------------------------------------------------------------------

func _frame(s: float) -> Array:
	var t: Vector3 = tangent_at(s)
	var side: Vector3 = t.cross(Vector3.UP)
	if side.length() < 0.05:
		side = t.cross(Vector3.RIGHT)
	side = side.normalized()
	return [t, side, side.cross(t).normalized()]


func _tube(radius: float, offset_up: float, step: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	var sides: int = 6
	var rings: int = int(ceilf(_length / step)) + 1
	for r: int in rings:
		var s: float = minf(float(r) * step, _length)
		var fr: Array = _frame(s)
		var c: Vector3 = point_at(s) + (fr[2] as Vector3) * offset_up
		for k: int in sides:
			var a: float = TAU * float(k) / float(sides)
			var n: Vector3 = (fr[1] as Vector3) * cos(a) + (fr[2] as Vector3) * sin(a)
			verts.append(c + n * radius)
			norms.append(n)
	for r2: int in rings - 1:
		for k2: int in sides:
			var a0: int = r2 * sides + k2
			var a1: int = r2 * sides + (k2 + 1) % sides
			var b0: int = (r2 + 1) * sides + k2
			var b1: int = (r2 + 1) * sides + (k2 + 1) % sides
			idx.append_array([a0, b0, a1, a1, b0, b1])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


func _build_mesh() -> void:
	if points.size() < 2:
		return
	var metal: StandardMaterial3D = Look.flat(Look.c("metal"), 0.35, 0.7)
	var col: Color = Look.c("accent2").lerp(Color(0.55, 1.0, 0.95), 0.3)
	_glow_mat = (Look.flat(col, 0.3, 0.0, 1.8).duplicate()) as StandardMaterial3D
	var body := MeshInstance3D.new()
	body.mesh = _tube(0.1, 0.0, 0.5)
	body.material_override = metal
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(body)
	var glow := MeshInstance3D.new()
	glow.mesh = _tube(0.04, 0.09, 0.5)
	glow.material_override = _glow_mat
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glow)
	# glowing end caps: where it starts and where it lets go
	add_child(Look.sphere(0.2, _glow_mat, point_at(0.0)))
	add_child(Look.sphere(0.2, _glow_mat, point_at(_length)))
	if is_finite(post_to_y):
		var s: float = post_every * 0.5
		while s < _length:
			var p: Vector3 = point_at(s)
			var h: float = p.y - post_to_y - 0.1
			if h > 0.4:
				add_child(Look.cylinder(0.07, h, metal, p + Vector3(0, -0.1 - h * 0.5, 0), -1.0, 6))
			s += post_every


func _build_trigger() -> void:
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 2
	_area.monitorable = false
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	var grown: AABB = _box.grow(snap + 2.5)
	bs.size = grown.size
	cs.shape = bs
	cs.position = grown.get_center()
	_area.add_child(cs)
	add_child(_area)


# ---- riding ------------------------------------------------------------------------------------------

func is_riding() -> bool:
	return _rider != null


func carrying() -> Player:
	return _rider


## Distance along the rail the current rider is at (-1 when empty).
func rider_offset() -> float:
	return _s if _rider != null else -1.0


## Let go now, as if jump was pressed (the route bot uses this).
func release_rider() -> void:
	if _rider != null:
		_want_release = true


func released_within(seconds: float) -> bool:
	return float(Engine.get_physics_frames() - _released_tick) / float(Engine.physics_ticks_per_second) <= seconds


func boarded_within(seconds: float) -> bool:
	return float(Engine.get_physics_frames() - _boarded_tick) / float(Engine.physics_ticks_per_second) <= seconds


func reset_state() -> void:
	_let_go(false, Vector3.ZERO)
	_cool_until = Engine.get_physics_frames() + _ticks(0.5)


func _on_rider_teleported() -> void:
	if _rider != null:
		_let_go(false, Vector3.ZERO)
		_cool_until = Engine.get_physics_frames() + _ticks(0.25)


func _let_go(fly: bool, v: Vector3, hop_y: float = 0.0) -> void:
	var p: Player = _rider
	_rider = null
	_want_release = false
	_sparks.emitting = false
	WorldAudio.set_active(_hum, false)
	if p == null or not is_instance_valid(p):
		return
	if p.teleported.is_connected(_on_rider_teleported):
		p.teleported.disconnect(_on_rider_teleported)
	p.remove_meta("rail_rider")
	p.control_enabled = _was_control
	if fly:
		p.velocity = v
		p.set("_coyote", 0.0)
		p.set("_buffer", 0.0)
		p.add_impulse(Vector3(0, maxf(hop_y, 0.001), 0))   # cancels variable-jump gravity and the floor snap
		_released_tick = Engine.get_physics_frames()
		_cool_until = Engine.get_physics_frames() + _ticks(0.7)
		WorldAudio.at(self, "flow_rail_leave", p.global_position, 0.8, 40.0)


func _physics_process(dt: float) -> void:
	if points.size() < 2:
		return
	if _rider != null:
		_ride(dt)
		return
	if Engine.get_physics_frames() < _cool_until:
		return
	var p: Player = KitUtil.player_in(_area, true)
	if p != null and not p.has_meta("rail_rider"):
		_try_board(p)


func _try_board(p: Player) -> void:
	var feet: Vector3 = p.global_position
	var s: float = offset_of(feet)
	var on_rail: Vector3 = point_at(s)
	var d: Vector3 = feet - on_rail
	var flat := Vector3(d.x, 0.0, d.z)
	if flat.length() > snap or d.y < -0.5 or d.y > 1.4:
		return
	if p.velocity.y > 3.0 and d.y < 0.3:
		return   # still rising from below
	var hv := Vector3(p.velocity.x, 0.0, p.velocity.z)
	var t: Vector3 = tangent_at(s)
	var tf := Vector3(t.x, 0.0, t.z)
	if hv.length() > 3.0 and tf.length() > 0.2 and hv.normalized().dot(tf.normalized()) < -0.5:
		return   # travelling against the rail
	if s > _length - 0.5:
		return
	_rider = p
	_was_control = p.control_enabled
	p.control_enabled = false
	p.set_meta("rail_rider", self)
	_s = s
	_speed = maxf(min_speed, maxf(hv.length(), p.velocity.dot(t)))   # a fall onto the rail carries along it
	_lean_now = 0.0
	_boarded_tick = Engine.get_physics_frames()
	boarded += 1
	if not p.teleported.is_connected(_on_rider_teleported):
		p.teleported.connect(_on_rider_teleported)
	_sparks.emitting = true
	WorldAudio.set_active(_hum, true)
	WorldAudio.at(self, "flow_rail_land", on_rail, 0.9, 45.0)
	_glow_mat.emission_energy_multiplier = 4.0
	var tw: Tween = create_tween()
	tw.tween_property(_glow_mat, "emission_energy_multiplier", 1.8, 0.5)
	_ride(1.0 / float(Engine.physics_ticks_per_second))


func _ride(dt: float) -> void:
	var p: Player = _rider
	if not is_instance_valid(p):
		_rider = null
		_sparks.emitting = false
		return
	var jump: bool = _want_release or bool(p.get("_jump_press_queued"))
	var t: Vector3 = tangent_at(_s)
	_speed = clampf(_speed - t.y * slope_accel * dt, min_speed, max_speed)
	_s += _speed * dt
	if jump:
		p.set("_jump_press_queued", false)
		_let_go(true, tangent_at(_s) * _speed, hop)
		return
	if _s >= _length:
		_let_go(true, tangent_at(_length) * _speed, end_hop)
		return
	t = tangent_at(_s)
	# a little lean with the stick (camera-relative stick -> the rail's right-hand side)
	var stick := Vector2.ZERO
	if p.use_device_input:
		stick = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	else:
		stick = p.cmd_move
	var side: Vector3 = t.cross(Vector3.UP)
	side = side.normalized() if side.length() > 0.05 else Vector3.RIGHT
	_lean_now = move_toward(_lean_now, clampf(stick.x, -1.0, 1.0) * lean, 1.2 * dt)
	var pos: Vector3 = point_at(_s) + side * _lean_now
	var v: Vector3 = t * _speed
	# the Player's own step still moves it by velocity * dt this tick: start that far back
	p.global_position = pos - v * dt
	p.velocity = v
	p.set("_no_snap", 0.2)
	p.set("_jumping", false)
	p.set("_coyote", 0.0)
	p.grounded = false
	p.air_time = 0.0
	p.last_ground_y = pos.y
	_sparks.global_position = pos
	_sparks.speed_scale = 1.0
	if _hum != null:
		_hum.pitch_scale = clampf(0.7 + _speed / 35.0, 0.7, 1.5)
