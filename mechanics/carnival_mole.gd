class_name CarnivalMole
extends MovingPlatform
## Carnival Chaos: WHACK-A-MOLE PISTONS. A round stone with a cartoon mole's face stands on a piston rod
## that shoots up out of the dark and drops back on a rhythm - step across a row of them as they pop up.
## `top` (the node's origin, as for every mover) is where the stone's TOP sits when it is UP; it sinks
## `depth` m below that when DOWN, where it is out of reach (not solid, out of the way).
##
## One cycle of `period` s (a pure function of the course clock, shifted by `phase`, a fraction):
##   [0, up_time)             UP and solid (the last `warn` s of it: the stone shakes, the face goes "o_o", a
##                            whistle blows - get off before it sinks)
##   [up_time, +sink)         sinks 0.5 s (you ride it down; it is solid until it is half way down)
##   then down, and for the last `warn` + `rise` s before it pops the stone shivers, glows and puffs dust
##   [period - rise, period)  shoots up in `rise` s (solid only once it is nearly up: it never shoves you)
## Tell >= 0.8 s both ways, shown and sounded.

@export var depth: float = 3.2
@export var up_time: float = 3.4
@export var sink: float = 0.5
@export var rise: float = 0.35
@export var warn: float = 1.0
@export var face_tint: Color = Color(0.55, 0.38, 0.28)

var _shape: CollisionShape3D
var _vis: Node3D
var _ring_mat: StandardMaterial3D
var _eye_mats: Array[MeshInstance3D] = []
var _puff: GPUParticles3D
var _last_state: int = -1
var _solid: bool = true


func _ready() -> void:
	sync_to_physics = false
	collision_layer = 1
	collision_mask = 0
	_origin = position
	warn = maxf(warn, 0.8)
	period = maxf(period, up_time + sink + warn + rise + 0.2)
	_shape = CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = size.x * 0.5
	cyl.height = size.y
	_shape.shape = cyl
	add_child(_shape)
	_build()
	position = _origin + offset_at(Game.course_time)
	_solid = frac_at(Game.course_time) >= 0.9
	_shape.disabled = not _solid
	reset_physics_interpolation()
	add_to_group("course_clock")


func _hums() -> bool:
	return false


# ---- the clock -----------------------------------------------------------------------------

func cycle_s(time: float) -> float:
	return fposmod(time / period + phase, 1.0) * period


## 0 = down ... 1 = up.
func frac_at(time: float) -> float:
	var u: float = cycle_s(time)
	if u < up_time:
		return 1.0
	if u < up_time + sink:
		return 1.0 - KitUtil.smooth((u - up_time) / sink)
	if u < period - rise:
		return 0.0
	return KitUtil.smooth((u - (period - rise)) / rise)


func offset_at(time: float) -> Vector3:
	return Vector3(0, -depth * (1.0 - frac_at(time)), 0)


## Fully up and not yet sinking at `time`.
func up_at(time: float) -> bool:
	return cycle_s(time) < up_time


## True when it is up for the whole of [time + a, time + b] (an unbroken stay).
func up_over(time: float, a: float, b: float) -> bool:
	var s: float = a
	while s <= b + 0.0001:
		if not up_at(time + s):
			return false
		s += 0.05
	return true


## Seconds until it is next fully up (0 when up now), counting from `time`.
func up_in(time: float) -> float:
	if up_at(time):
		return 0.0
	var u: float = cycle_s(time)
	return period - u


## Seconds it stays up from now (0 when it is not up).
func up_left(time: float) -> float:
	var u: float = cycle_s(time)
	return maxf(up_time - u, 0.0) if u < up_time else 0.0


## 0 up, 1 shaking before it sinks, 2 sinking, 3 down, 4 shivering before it pops, 5 rising.
func state_at(time: float) -> int:
	var u: float = cycle_s(time)
	if u < up_time - warn:
		return 0
	if u < up_time:
		return 1
	if u < up_time + sink:
		return 2
	if u < period - rise - warn:
		return 3
	if u < period - rise:
		return 4
	return 5


# ---- looks ---------------------------------------------------------------------------------

func _build() -> void:
	_vis = Node3D.new()
	add_child(_vis)
	var r: float = size.x * 0.5
	var h: float = size.y
	var dirt: StandardMaterial3D = Look.flat(face_tint, 0.9)
	var rod: StandardMaterial3D = Look.flat(Color(0.8, 0.82, 0.88), 0.3, 0.9)
	_ring_mat = Look.flat(Color(1.0, 0.85, 0.3), 0.3, 0.0, 0.4).duplicate() as StandardMaterial3D
	# the stone: a round slab with a striped rim, so it reads as a platform from far off
	var slab := Look.platform_round(r, h, "accent")
	_vis.add_child(slab)
	var lip := Look.cylinder(r + 0.05, 0.12, _ring_mat, Vector3(0, h * 0.5 - 0.07, 0), -1.0, 24)
	_vis.add_child(lip)
	# the mole's face on its +Z flank (the side you approach from)
	var fz: float = r + 0.02
	var face_y: float = -h * 0.5 + 0.18
	_vis.add_child(Look.cylinder(r * 0.98, h * 0.7, dirt, Vector3(0, -h * 0.5 - h * 0.05, 0), -1.0, 24))
	var white: StandardMaterial3D = Look.flat(Color(1.0, 1.0, 0.98), 0.4)
	var black: StandardMaterial3D = Look.flat(Color(0.05, 0.04, 0.05), 0.3)
	for sx: float in [-1.0, 1.0]:
		var eye := Look.sphere(0.17, white, Vector3(sx * 0.3, face_y + 0.22, fz - 0.08))
		eye.scale = Vector3(1, 1, 0.5)
		_vis.add_child(eye)
		var pupil := Look.sphere(0.08, black, Vector3(sx * 0.3, face_y + 0.22, fz + 0.0))
		pupil.scale = Vector3(1, 1, 0.5)
		_vis.add_child(pupil)
		_eye_mats.append(pupil)
	var nose := Look.sphere(0.16, Look.flat(Color(1.0, 0.55, 0.65), 0.4), Vector3(0, face_y + 0.0, fz + 0.0))
	nose.scale = Vector3(1.2, 0.9, 0.6)
	_vis.add_child(nose)
	for sx2: float in [-1.0, 1.0]:
		_vis.add_child(Look.box(Vector3(0.12, 0.16, 0.04), white, Vector3(sx2 * 0.07, face_y - 0.17, fz - 0.02)))
	# the rod it rides on, down into the dark
	_vis.add_child(Look.cylinder(0.32, 30.0, rod, Vector3(0, -h * 0.5 - 15.0 - h * 0.5, 0), -1.0, 10))
	_puff = Fx.burst({"amount": 22, "lifetime": 0.8, "explosiveness": 0.9, "shape": "point", "dir": Vector3.UP,
		"spread": 80.0, "speed": Vector2(1.5, 3.5), "gravity": Vector3(0, -3.0, 0), "tex": Fx.Tex.SMOKE,
		"additive": false, "size": 0.6, "color": Color(0.8, 0.65, 0.5, 0.7), "curve": "puff",
		"aabb": AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))})
	_puff.position = Vector3(0, h * 0.5, 0)
	add_child(_puff)


func _physics_process(_dt: float) -> void:
	var t: float = Game.course_time
	position = _origin + offset_at(t)
	var f: float = frac_at(t)
	var u: float = cycle_s(t)
	var want: bool = f >= 0.5 if u < up_time + sink else f >= 0.9
	if want != _solid:
		_solid = want
		_shape.set_deferred("disabled", not want)


func _process(_dt: float) -> void:
	var t: float = Game.course_time
	var st: int = state_at(t)
	var shake: float = 0.0
	var glow: float = 0.4
	if st == 1:
		var k: float = clampf(1.0 - (up_time - cycle_s(t)) / warn, 0.0, 1.0)
		shake = 0.03 + 0.05 * k
		glow = 0.5 + 3.0 * (0.5 + 0.5 * sin(t * 18.0))
	elif st == 4:
		var k2: float = clampf(1.0 - (period - rise - cycle_s(t)) / warn, 0.0, 1.0)
		shake = 0.02 + 0.07 * k2
		glow = 0.6 + 2.6 * k2
	elif st == 3 or st == 5:
		glow = 0.3
	_vis.position = Vector3(sin(t * 61.0) * shake, 0.0, cos(t * 57.0) * shake)
	_ring_mat.emission_enabled = true
	_ring_mat.emission = Color(1.0, 0.85, 0.3) if st != 4 else Color(0.6, 1.0, 0.7)
	_ring_mat.emission_energy_multiplier = glow
	# the pupils pop wide ("o_o") before it sinks
	for e: MeshInstance3D in _eye_mats:
		e.scale = Vector3(1.6, 1.6, 0.5) if st == 1 else Vector3(1, 1, 0.5)
	if st != _last_state:
		if st == 4:
			# SOUND: carnival_mole_rumble - a hollow drumroll under the board, about a second before it pops
			WorldAudio.at(self, "carnival_mole_rumble", global_position, 0.8, 30.0)
		elif st == 1:
			# SOUND: carnival_mole_whistle - a falling slide-whistle: the stone is about to drop
			WorldAudio.at(self, "carnival_mole_whistle", global_position, 0.8, 30.0)
		elif st == 5:
			# SOUND: carnival_mole_pop - a cork-pop boing as it shoots up
			WorldAudio.at(self, "carnival_mole_pop", global_position, 0.8, 30.0)
			_puff.restart()
			_puff.emitting = true
		_last_state = st
