class_name CandySoldier
extends Node3D
## Sugar Rush: a wind-up toy drummer soldier marching back and forth along a painted track on the
## course clock (from its build position to `to`, pausing at each end to wind down, turn about and
## wind up again). It is not solid: it SHOVES whoever it marches into - along its march and away
## from its body, with a little lift - which on a narrow walkway means over the side. Readable: the
## dashed track shows where it goes, its key spins, its legs swing and the drum thumps each step;
## at each end it stops and turns round on the spot. A pure function of Game.course_time.
##   u: 0..0.5 out (dwell at both ends), 0.5..1 back.
## Positioned by the point on the floor between its feet at the start of its track.

@export var to: Vector3 = Vector3(8, 0, 0)
@export var period: float = 10.0
@export var phase: float = 0.0
## Fraction of each leg spent standing at the end, turning round.
@export var dwell: float = 0.18
@export var push: float = 11.0
@export var lift: float = 5.0
@export var height: float = 2.3
@export var coat: Color = Color(0.95, 0.2, 0.3)

var _origin: Vector3
var _body: Node3D
var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _key: Node3D
var _area: Area3D
var _cool: float = 0.0
var _steps: GPUParticles3D
var _march: AudioStreamPlayer3D
var _turned: int = -1


func _ready() -> void:
	_origin = position
	_build()
	_pose(Game.course_time)
	add_to_group("course_clock")
	_march = WorldAudio.loop("candy_soldier_march", self, -8.0, 22.0, 4.0)


func _u(time: float) -> float:
	return fposmod(time / maxf(period, 0.01) + phase, 1.0)


## 0..1 along the track (start .. `to`) at `time`.
func progress_at(time: float) -> float:
	var u: float = _u(time)
	var tri: float = 1.0 - absf(u * 2.0 - 1.0)
	var k: float = clampf((tri - dwell) / maxf(1.0 - 2.0 * dwell, 0.01), 0.0, 1.0)
	return k * k * (3.0 - 2.0 * k) * 0.25 + k * 0.75


## World position of its feet at `time`.
func pos_at(time: float) -> Vector3:
	var start: Vector3 = get_parent().to_global(_origin) if get_parent() is Node3D else _origin
	var end: Vector3 = get_parent().to_global(_origin + to) if get_parent() is Node3D else _origin + to
	return start.lerp(end, progress_at(time))


func is_marching_at(time: float) -> bool:
	var p0: float = progress_at(time - 0.05)
	var p1: float = progress_at(time + 0.05)
	return absf(p1 - p0) > 0.0005


## True if its body stays at least `clear` metres (along its track) from world point `p` over
## [now + a, now + b].
func lane_clear(p: Vector3, clear: float, a: float, b: float) -> bool:
	var dir: Vector3 = (get_parent() as Node3D).global_basis * to if get_parent() is Node3D else to
	dir.y = 0.0
	dir = dir.normalized()
	var s: float = a
	while s <= b:
		var q: Vector3 = pos_at(Game.course_time + s)
		if absf((p - q).dot(dir)) < clear:
			return false
		s += 0.05
	return true


func snap_to_clock() -> void:
	_pose(Game.course_time)
	reset_physics_interpolation()


func _physics_process(dt: float) -> void:
	var t: float = Game.course_time
	_pose(t)
	_cool = maxf(_cool - dt, 0.0)
	if _cool > 0.0:
		return
	for body: Node3D in _area.get_overlapping_bodies():
		if body is Player:
			var d: Vector3 = to
			if progress_at(t + 0.05) < progress_at(t - 0.05):
				d = -to
			var away: Vector3 = body.global_position - global_position
			away.y = 0.0
			var shove: Vector3 = d.normalized() * push * 0.7 + away.normalized() * push * 0.5 if away.length() > 0.05 else d.normalized() * push
			if not is_marching_at(t):
				shove = away.normalized() * push if away.length() > 0.05 else d.normalized() * push
			(body as Player).knockback(Vector3(shove.x, lift, shove.z))
			_cool = 0.6
			Sfx.play_at("whack", global_position, 0.08, 0.9)


func _pose(t: float) -> void:
	position = _origin + to * progress_at(t)
	# facing: along the march; at the ends it turns about during the dwell
	var u: float = _u(t)
	var heading: float = atan2(-to.x, -to.z)
	var yaw: float = heading if u < 0.5 else heading + PI
	var leg_u: float = fposmod(u * 2.0, 1.0)
	var dw: float = maxf(dwell, 0.01)
	# turning about on the spot across each end's dwell (half of it at the end of one leg, half
	# at the start of the next)
	if leg_u > 1.0 - dw:
		var f: float = (leg_u - (1.0 - dw)) / (2.0 * dw)
		yaw += PI * f * f * (3.0 - 2.0 * f)
	elif leg_u < dw:
		var f2: float = 0.5 + leg_u / (2.0 * dw)
		yaw -= PI * (1.0 - f2 * f2 * (3.0 - 2.0 * f2))
	_body.rotation.y = yaw


func _process(dt: float) -> void:
	var t: float = Game.course_time
	var marching: bool = is_marching_at(t)
	var swing: float = sin(t * 7.0) * (0.5 if marching else 0.0)
	for i: int in _legs.size():
		_legs[i].rotation.x = swing * (1.0 if i == 0 else -1.0)
	for i: int in _arms.size():
		_arms[i].rotation.x = -0.6 + absf(sin(t * 14.0)) * (0.5 if marching else 0.1) * (1.0 if i == 0 else 0.8)
	_body.position.y = absf(sin(t * 7.0)) * 0.06 if marching else 0.0
	_key.rotation.z += dt * (5.0 if marching else 1.2)
	_steps.emitting = marching
	WorldAudio.set_active(_march, marching)
	var cycle: int = int(floor((t / maxf(period, 0.01) + phase) * 2.0))
	if not marching and cycle != _turned:
		_turned = cycle
		# SOUND: the drum roll and the key's clack as it turns about
		WorldAudio.at(self, "candy_soldier_turn", global_position, 0.8, 30.0)


func _build() -> void:
	var k: float = height / 2.3
	_body = Node3D.new()
	add_child(_body)
	var white: StandardMaterial3D = Look.flat(Color(0.97, 0.96, 0.94), 0.6)
	var black: StandardMaterial3D = Look.flat(Color(0.08, 0.08, 0.12), 0.35, 0.2)
	var red: StandardMaterial3D = Look.flat(coat, 0.45)
	var gold: StandardMaterial3D = Look.flat(Color(1.0, 0.78, 0.25), 0.25, 0.9, 0.2)
	var skin: StandardMaterial3D = Look.flat(Color(1.0, 0.85, 0.72), 0.7)
	# legs (pivot at the hip), black boots
	for sx: float in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.position = Vector3(sx * 0.2 * k, 0.95 * k, 0)
		_body.add_child(leg)
		leg.add_child(Look.cylinder(0.14 * k, 0.8 * k, white, Vector3(0, -0.4 * k, 0), -1.0, 10))
		leg.add_child(Look.box(Vector3(0.26, 0.2, 0.4) * k, black, Vector3(0, -0.85 * k, -0.06 * k)))
		_legs.append(leg)
	# coat, cross belts, buttons
	_body.add_child(Look.cylinder(0.38 * k, 0.85 * k, red, Vector3(0, 1.38 * k, 0), 0.34 * k, 16))
	_body.add_child(Look.cylinder(0.4 * k, 0.12 * k, black, Vector3(0, 0.98 * k, 0), -1.0, 16))
	for s: float in [-1.0, 1.0]:
		var belt := Look.box(Vector3(0.08, 0.95, 0.06) * k, white, Vector3(0, 1.38 * k, -0.36 * k))
		belt.rotation.z = s * 0.5
		_body.add_child(belt)
	for i: int in 3:
		_body.add_child(Look.sphere(0.045 * k, gold, Vector3(0, (1.62 - 0.2 * float(i)) * k, -0.37 * k)))
	# epaulettes and arms holding drumsticks
	for sx: float in [-1.0, 1.0]:
		_body.add_child(Look.sphere(0.13 * k, gold, Vector3(sx * 0.4 * k, 1.78 * k, 0)))
		var arm := Node3D.new()
		arm.position = Vector3(sx * 0.46 * k, 1.72 * k, 0)
		_body.add_child(arm)
		arm.add_child(Look.cylinder(0.09 * k, 0.6 * k, red, Vector3(0, -0.3 * k, 0), -1.0, 8))
		var stick := Look.cylinder(0.03 * k, 0.5 * k, Look.flat(Color(1.0, 0.95, 0.85), 0.5), Vector3(0, -0.62 * k, -0.2 * k), -1.0, 6)
		stick.rotation.x = 1.1
		arm.add_child(stick)
		_arms.append(arm)
	# the drum on its belly
	var drum := Look.cylinder(0.3 * k, 0.32 * k, Look.flat(Color(0.25, 0.45, 1.0), 0.5), Vector3(0, 1.12 * k, -0.52 * k), -1.0, 16)
	_body.add_child(drum)
	_body.add_child(Look.cylinder(0.31 * k, 0.04 * k, gold, Vector3(0, 1.28 * k, -0.52 * k), -1.0, 16))
	_body.add_child(Look.cylinder(0.31 * k, 0.04 * k, gold, Vector3(0, 0.96 * k, -0.52 * k), -1.0, 16))
	_body.add_child(Look.cylinder(0.29 * k, 0.02 * k, white, Vector3(0, 1.29 * k, -0.52 * k), -1.0, 16))
	# head: rosy cheeks, eyes, a tall bearskin hat with a gold plate and a plume
	_body.add_child(Look.sphere(0.27 * k, skin, Vector3(0, 1.98 * k, 0)))
	for sx: float in [-1.0, 1.0]:
		_body.add_child(Look.sphere(0.05 * k, black, Vector3(sx * 0.1 * k, 2.02 * k, -0.24 * k)))
		_body.add_child(Look.sphere(0.07 * k, Look.flat(Color(1.0, 0.5, 0.55), 0.8), Vector3(sx * 0.16 * k, 1.93 * k, -0.2 * k)))
	_body.add_child(Look.cylinder(0.27 * k, 0.62 * k, black, Vector3(0, 2.42 * k, 0), 0.24 * k, 14))
	_body.add_child(Look.box(Vector3(0.22, 0.2, 0.04) * k, gold, Vector3(0, 2.3 * k, -0.27 * k)))
	_body.add_child(Look.sphere(0.1 * k, Look.flat(Color(1.0, 0.3, 0.4), 0.6), Vector3(0.2 * k, 2.62 * k, 0)))
	# the wind-up key in its back
	_key = Node3D.new()
	_key.position = Vector3(0, 1.45 * k, 0.45 * k)
	_key.rotation.y = PI * 0.5
	_body.add_child(_key)
	var key_mat: StandardMaterial3D = Look.flat(Color(1.0, 0.8, 0.3), 0.25, 0.9, 0.3)
	var shaft := Look.cylinder(0.04 * k, 0.25 * k, key_mat, Vector3(0.12 * k, 0, 0))
	shaft.rotation.z = PI * 0.5
	_key.add_child(shaft)
	for s: float in [-1.0, 1.0]:
		var bow := Look.sphere(0.13 * k, key_mat, Vector3(0.28 * k, s * 0.14 * k, 0))
		bow.scale = Vector3(0.3, 1.0, 0.8)
		_key.add_child(bow)
	# the shove area round its body
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 2
	_area.monitorable = false
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.0, height, 1.0) * Vector3(1, 1, 1)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, height * 0.5, 0)
	_area.add_child(cs)
	add_child(_area)
	# footstep puffs of icing sugar
	_steps = Fx.emitter({"amount": 10, "lifetime": 0.7, "shape": "box", "extents": Vector3(0.3, 0.02, 0.3),
		"dir": Vector3.UP, "spread": 60.0, "speed": Vector2(0.4, 1.2), "gravity": Vector3(0, -1.0, 0),
		"tex": Fx.Tex.SMOKE, "additive": false, "size": 0.45, "curve": "puff",
		"color": Color(1.0, 0.97, 1.0, 0.55), "fade": PackedFloat32Array([0.0, 0.7, 0.0]),
		"aabb": AABB(Vector3(-30, -2, -30), Vector3(60, 6, 60))})
	_steps.position = Vector3(0, 0.05, 0)
	add_child(_steps)
	# the key sheds a few golden glints
	var glint: GPUParticles3D = Fx.emitter({"amount": 6, "lifetime": 0.9, "local": true, "shape": "sphere", "radius": 0.2,
		"speed": Vector2(0.2, 0.6), "spread": 180.0, "tex": Fx.Tex.STAR, "size": 0.2, "curve": "pop",
		"color": Fx.hot(Color(1.0, 0.85, 0.4), 1.8), "aabb": AABB(Vector3(-3, -1, -3), Vector3(6, 5, 6)), "preprocess": 0.9})
	glint.position = _key.position + Vector3(0, 0, 0.35 * k)
	_body.add_child(glint)


## Painted dashed track on the floor along its march (call after adding it; floor-relative).
static func track(parent: Node3D, from: Vector3, to_world: Vector3, color: Color) -> void:
	var d: Vector3 = to_world - from
	var n: int = maxi(int(d.length() / 0.9), 1)
	var yaw: float = atan2(d.x, d.z)
	var mat: StandardMaterial3D = Look.flat(color, 0.6, 0.0, 0.4)
	for i: int in n + 1:
		var p: Vector3 = from + d * (float(i) / float(n))
		var dash := Look.box(Vector3(0.14, 0.02, 0.45), mat, p + Vector3(0, 0.015, 0))
		dash.rotation.y = yaw
		dash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(dash)
