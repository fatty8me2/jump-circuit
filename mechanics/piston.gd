class_name Piston
extends AnimatableBody3D
## A ram that punches out of its housing along local -Z on a fixed rhythm
## (Game.course_time), holds, and pulls back slowly. Its striped face SHOVES a
## player it catches while extending (knockback along the stroke) - off a
## walkway, into a pit, or on purpose across a gap. Its top is solid ground that
## you can ride. Placed at the block's centre when fully retracted.
##   u 0.00-0.45 retracted   0.45-0.55 punch   0.55-0.80 held out   0.80-1.00 retract

@export var size: Vector3 = Vector3(3, 1.6, 2)
@export var stroke: float = 3.0
@export var period: float = 3.0
@export var phase: float = 0.0
## Shove speed on top of the stroke speed, and its lift.
@export var strength: float = 13.0
@export var lift: float = 5.0

const PUNCH_START: float = 0.45
const PUNCH_END: float = 0.55
const RETRACT_START: float = 0.8

var _origin: Vector3
var _face: Area3D
var _cool: float = 0.0
# effects (visual only): steam venting from the housing on the slow retract, a spark
# fan, dust and a ring off the striped face when the punch lands
var _steam: GPUParticles3D
var _fan: GPUParticles3D
var _puff: GPUParticles3D
var _ring: GPUParticles3D
var _fx_phase: int = -1


func _ready() -> void:
	sync_to_physics = false
	collision_layer = 1
	collision_mask = 0
	_origin = position
	var box := BoxShape3D.new()
	box.size = size
	var cs := CollisionShape3D.new()
	cs.shape = box
	add_child(cs)
	add_child(Look.platform_box(size, "mover"))
	# hazard-striped push face
	var stripe_a: StandardMaterial3D = Look.flat(Color(1.0, 0.72, 0.1), 0.5, 0.1, 0.6)
	var stripe_b: StandardMaterial3D = Look.flat(Color(0.12, 0.12, 0.14), 0.6, 0.2)
	var n: int = maxi(int(size.x / 0.5), 2)
	for i: int in n:
		var w: float = size.x / float(n)
		var bar := Look.box(Vector3(w, size.y - 0.1, 0.06), stripe_a if i % 2 == 0 else stripe_b, Vector3(-size.x * 0.5 + (float(i) + 0.5) * w, 0, -size.z * 0.5 - 0.03))
		add_child(bar)
	# the rod back into the housing
	var rod := Look.cylinder(minf(size.y, size.x) * 0.2, stroke + 0.2, Look.flat(Color(0.75, 0.78, 0.82), 0.25, 0.9), Vector3(0, 0, size.z * 0.5 + (stroke + 0.2) * 0.5))
	rod.rotation.x = PI * 0.5
	add_child(rod)
	_face = Area3D.new()
	_face.collision_layer = 0
	_face.collision_mask = 2
	_face.monitorable = false
	var fs := BoxShape3D.new()
	fs.size = Vector3(size.x + 0.2, maxf(size.y - 0.25, 0.3), 0.7)
	var fcs := CollisionShape3D.new()
	fcs.shape = fs
	_face.add_child(fcs)
	_face.position = Vector3(0, -0.12, -size.z * 0.5 - 0.3)
	add_child(_face)
	position = _origin + offset_at(Game.course_time)
	reset_physics_interpolation()
	add_to_group("course_clock")
	_build_fx()


func _build_fx() -> void:
	var face_z: float = -size.z * 0.5 - 0.08
	var vis := AABB(Vector3(-size.x - 3.0, -size.y - 2.0, -size.z - 6.0), Vector3(size.x * 2.0 + 6.0, size.y * 2.0 + 6.0, size.z * 2.0 + stroke * 2.0 + 10.0))
	_steam = Fx.smoke({"amount": 40, "lifetime": 1.0, "one_shot": false, "emitting": false,
		"explosiveness": 0.0, "randomness": 0.3, "shape": "box",
		"extents": Vector3(size.x * 0.3, size.y * 0.25, 0.1), "dir": Vector3.UP, "spread": 65.0,
		"speed": Vector2(1.5, 3.2), "gravity": Vector3(0, 1.6, 0), "damping": Vector2(1.5, 2.5),
		"size": 0.95, "color": Color(0.95, 0.97, 1.0, 0.65), "aabb": vis})
	add_child(_steam)
	# the punch: a fan of sparks spraying sideways off the face, a dust puff and a ring
	var face_basis := Fx.basis_up(Vector3.FORWARD)
	_fan = Fx.sparks({"amount": 56, "lifetime": 0.45, "shape": "box",
		"extents": Vector3(size.y * 0.4, 0.05, size.x * 0.5), "dir": Vector3.UP, "spread": 80.0,
		"speed": Vector2(4.0, 10.0), "gravity": Vector3(0, -14, 0), "aabb": vis})
	_fan.transform = Transform3D(face_basis, Vector3(0, 0, face_z))
	add_child(_fan)
	_puff = Fx.smoke({"amount": 18, "lifetime": 0.7, "shape": "box",
		"extents": Vector3(size.y * 0.4, 0.05, size.x * 0.5), "dir": Vector3.UP, "spread": 70.0,
		"speed": Vector2(1.0, 3.0), "size": 0.7, "color": Color(0.9, 0.86, 0.8, 0.6), "aabb": vis})
	_puff.transform = _fan.transform
	add_child(_puff)
	_ring = Fx.shockwave(maxf(size.x, size.y) * 0.9, {"lifetime": 0.3, "color": Color(2.2, 1.6, 0.5)})
	_ring.transform = Transform3D(face_basis, Vector3(0, 0, face_z - 0.05))
	add_child(_ring)
	_lamp = OmniLight3D.new()
	_lamp.light_color = Color(1.0, 0.7, 0.35)
	_lamp.omni_range = maxf(size.x, size.y) + 4.0
	_lamp.light_energy = 0.0
	_lamp.visible = false
	_lamp.shadow_enabled = false
	_lamp.position = Vector3(0, 0, face_z - 0.6)
	add_child(_lamp)
	# the ram face corners trace short hot ribbons while it punches
	for sx: float in [-1.0, 1.0]:
		var c := Node3D.new()
		c.position = Vector3(sx * size.x * 0.5, size.y * 0.5, face_z)
		add_child(c)
		_corners.append(c)
		var sw: Swoosh = Swoosh.make(Color(1.0, 0.55, 0.2, 0.7), 0.12, 0.18, false)
		add_child(sw)
		_swooshes.append(sw)


## 0 retracted, 1 punching, 2 held out, 3 retracting.
func _phase_at(time: float) -> int:
	var u: float = fposmod(time / period + phase, 1.0)
	if u < PUNCH_START:
		return 0
	if u < PUNCH_END:
		return 1
	return 2 if u < RETRACT_START else 3


## Visual state only: the shove in _physics_process never reads any of this.
var _lamp: OmniLight3D
var _corners: Array[Node3D] = []
var _swooshes: Array[Swoosh] = []


func _process(_dt: float) -> void:
	var t: float = Game.course_time
	var ph: int = _phase_at(t)
	if ph == 3:
		# vent where the rod enters the (static) housing behind the moving ram
		_steam.position = Vector3(0, 0, size.z * 0.5 + stroke * (1.0 + extension_at(t)) + 0.05)
	for i: int in _corners.size():
		_swooshes[i].feed(_corners[i].global_position, ph == 1, _dt)
	if ph == _fx_phase:
		return
	var was: int = _fx_phase
	_fx_phase = ph
	_steam.emitting = ph == 3
	# sound: the valve fires, the ram hits its stop, then vents on the way back
	if was >= 0:
		if ph == 1:
			WorldAudio.at(self, "piston_fire", global_position, 0.7, 35.0)
		elif ph == 2 and was == 1:
			WorldAudio.at(self, "piston_clank", global_position, 0.7, 35.0)
		elif ph == 3:
			WorldAudio.at(self, "piston_retract", global_position, 0.4, 25.0)
	if ph == 2 and (was == 0 or was == 1):
		_fan.restart()
		_puff.restart()
		_ring.restart()
		if Fx.density() >= 0.5:
			Fx.pulse(_lamp, 3.5, 0.0, 0.3)


func snap_to_clock() -> void:
	position = _origin + offset_at(Game.course_time)
	reset_physics_interpolation()


## 0 (retracted) .. 1 (fully out) at `time`.
func extension_at(time: float) -> float:
	var u: float = fposmod(time / period + phase, 1.0)
	if u < PUNCH_START:
		return 0.0
	if u < PUNCH_END:
		var k: float = (u - PUNCH_START) / (PUNCH_END - PUNCH_START)
		return k * k
	if u < RETRACT_START:
		return 1.0
	var r: float = (u - RETRACT_START) / (1.0 - RETRACT_START)
	return 1.0 - r * r * (3.0 - 2.0 * r)


func is_punching_at(time: float) -> bool:
	var u: float = fposmod(time / period + phase, 1.0)
	return u >= PUNCH_START and u < PUNCH_END


func offset_at(time: float) -> Vector3:
	return transform.basis * Vector3(0, 0, -stroke * extension_at(time))


func _physics_process(dt: float) -> void:
	var t: float = Game.course_time
	position = _origin + offset_at(t)
	_cool = maxf(_cool - dt, 0.0)
	if _cool > 0.0 or not is_punching_at(t):
		return
	for body: Node3D in _face.get_overlapping_bodies():
		if body is Player:
			var dir: Vector3 = -global_basis.z
			dir.y = 0.0
			var ram_speed: float = stroke / ((PUNCH_END - PUNCH_START) * period)
			(body as Player).knockback(dir.normalized() * (ram_speed + strength) + Vector3(0, lift, 0))
			_cool = 0.4
			Sfx.play_at("whack", global_position, 0.08, 1.0)
