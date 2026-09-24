class_name Crusher
extends AnimatableBody3D
## A heavy press that hangs `lift` metres above the floor, shudders, slams down,
## holds and hauls itself back up - on a fixed rhythm (Game.course_time). Caught
## under it while it drops or rests = back to the checkpoint. Its top is solid
## and rideable (an elevator with a nasty underside). Positioned by the floor
## point under its centre; the block's bottom rests `lift` above it.
##   u 0.00-0.42 up   0.42-0.50 shudder   0.50-0.56 slam   0.56-0.72 down   0.72-1.00 rise

@export var size: Vector3 = Vector3(3, 2, 3)
@export var lift: float = 3.2
@export var period: float = 3.2
@export var phase: float = 0.0

const SHUDDER: float = 0.42
const SLAM: float = 0.50
const DOWN: float = 0.56
const RISE: float = 0.72

var _floor: Vector3
var _kill: Area3D
var _plate_mat: StandardMaterial3D
# effects (visual only): grit sifting off the underside while it shudders; on the slam a
# dust ring rolling out over the floor, flying debris, edge sparks, a ground ring, a flash
var _grit: GPUParticles3D
var _dust: GPUParticles3D
var _debris: GPUParticles3D
var _sparks: GPUParticles3D
var _ring: GPUParticles3D
var _lamp: OmniLight3D
var _fx_u: float = -1.0
var _haze: GPUParticles3D


func _ready() -> void:
	sync_to_physics = false
	collision_layer = 1
	collision_mask = 0
	_floor = position
	var box := BoxShape3D.new()
	box.size = size
	var cs := CollisionShape3D.new()
	cs.shape = box
	add_child(cs)
	add_child(Look.platform_box(size, "alt"))
	_plate_mat = Look.flat(Color(1.0, 0.2, 0.12), 0.4, 0.3, 0.4)
	add_child(Look.box(Vector3(size.x + 0.1, 0.25, size.z + 0.1), _plate_mat, Vector3(0, -size.y * 0.5 + 0.1, 0)))
	var tooth: StandardMaterial3D = Look.flat(Color(0.2, 0.2, 0.24), 0.4, 0.8)
	for sx: float in [-0.3, 0.3]:
		for sz: float in [-0.3, 0.3]:
			add_child(Look.cylinder(0.18, 0.3, tooth, Vector3(sx * size.x, -size.y * 0.5 - 0.1, sz * size.z), 0.05, 8))
	_kill = Area3D.new()
	_kill.collision_layer = 0
	_kill.collision_mask = 2
	_kill.monitorable = false
	var ks := BoxShape3D.new()
	ks.size = Vector3(size.x - 0.15, 0.9, size.z - 0.15)
	var kcs := CollisionShape3D.new()
	kcs.shape = ks
	_kill.add_child(kcs)
	# from 0.5 below the underside to 0.4 inside it: only a player it lands on can be in there
	_kill.position = Vector3(0, -size.y * 0.5 - 0.05, 0)
	add_child(_kill)
	position = _floor + Vector3(0, gap_at(Game.course_time) + size.y * 0.5, 0)
	reset_physics_interpolation()
	add_to_group("course_clock")
	_build_fx()


func _build_fx() -> void:
	var under: float = -size.y * 0.5 - 0.15
	var reach: float = maxf(size.x, size.z)
	var vis := AABB(Vector3(-reach - 4.0, under - lift - 2.0, -reach - 4.0), Vector3(reach * 2.0 + 8.0, lift + size.y + 8.0, reach * 2.0 + 8.0))
	# (it only shudders ~0.25 s, so the rate is high)
	_grit = Fx.emitter({"amount": clampi(int(size.x * size.z * 5.0), 24, 60), "lifetime": 0.7, "emitting": false,
		"shape": "box", "extents": Vector3(size.x * 0.45, 0.02, size.z * 0.45), "dir": Vector3.DOWN,
		"spread": 10.0, "speed": Vector2(0.2, 1.0), "gravity": Vector3(0, -14, 0), "additive": false,
		"size": 0.16, "scale": Vector2(0.5, 1.2), "color": Color(0.42, 0.36, 0.3, 0.95),
		"fade": PackedFloat32Array([1.0, 1.0, 0.0]), "aabb": vis})
	_grit.position = Vector3(0, under, 0)
	add_child(_grit)
	_dust = Fx.smoke({"amount": 34, "lifetime": 1.1, "shape": "ring", "ring_radius": reach * 0.5,
		"ring_inner": reach * 0.35, "dir": Vector3(0, 0.15, 0), "spread": 180.0, "flatness": 0.9,
		"radial_vel": Vector2(4.0, 8.0), "speed": Vector2(0.0, 0.4), "damping": Vector2(5.0, 8.0),
		"gravity": Vector3(0, 0.6, 0), "size": 1.4, "color": Color(0.78, 0.72, 0.64, 0.85), "aabb": vis})
	add_child(_dust)
	_debris = Fx.debris({"amount": 26, "shape": "ring", "ring_radius": reach * 0.5, "ring_inner": reach * 0.3,
		"dir": Vector3.UP, "spread": 50.0, "radial_vel": Vector2(2.0, 5.0), "speed": Vector2(3.0, 7.0),
		"color": Color(0.4, 0.33, 0.27), "chunk": 0.22, "aabb": vis})
	add_child(_debris)
	_sparks = Fx.sparks({"amount": 50, "lifetime": 0.45, "shape": "ring", "ring_radius": reach * 0.55,
		"ring_inner": reach * 0.45, "dir": Vector3.UP, "spread": 70.0, "radial_vel": Vector2(3.0, 7.0),
		"speed": Vector2(2.0, 6.0), "color": Color(3.0, 1.5, 0.6), "aabb": vis})
	add_child(_sparks)
	_ring = Fx.shockwave(reach * 1.4, {"lifetime": 0.5, "color": Color(2.2, 1.7, 1.2), "aabb": vis})
	add_child(_ring)
	# dust that hangs over the floor after the slam
	_haze = Fx.smoke({"amount": 14, "lifetime": 2.0, "explosiveness": 0.6, "shape": "ring",
		"ring_radius": reach * 0.8, "ring_inner": reach * 0.3, "dir": Vector3.UP, "spread": 50.0,
		"speed": Vector2(0.2, 0.6), "damping": Vector2(0.5, 1.0), "size": 1.8,
		"color": Color(0.78, 0.72, 0.64, 0.4), "aabb": vis})
	add_child(_haze)
	_lamp = OmniLight3D.new()
	_lamp.light_color = Color(1.0, 0.55, 0.3)
	_lamp.omni_range = reach * 2.0 + 2.0
	_lamp.light_energy = 0.0
	_lamp.visible = false
	add_child(_lamp)


## Visual state only (the kill check never reads any of this).
func _process(_dt: float) -> void:
	var u: float = fposmod(Game.course_time / period + phase, 1.0)
	var was: float = _fx_u
	_fx_u = u
	if was < 0.0:
		return
	var shudder: bool = u >= SHUDDER and u < DOWN
	if _grit.emitting != shudder:
		_grit.emitting = shudder
	# sound: the shudder's groan, and the hydraulics hauling it back up (a wrap never counts)
	if u - was < 0.25:
		if was < SHUDDER and u >= SHUDDER:
			WorldAudio.at(self, "crusher_shudder", global_position, 0.6, 35.0)
		elif was < RISE and u >= RISE:
			WorldAudio.at(self, "crusher_rise", global_position, 0.5, 35.0)
	# the frame the press reaches the floor (u passes DOWN; a wrap never counts)
	if was < DOWN and u >= DOWN and u - was < 0.25:
		var floor_local := Vector3(0, -size.y * 0.5 - gap_at(Game.course_time), 0)
		for p: GPUParticles3D in [_dust, _debris, _sparks, _ring]:
			p.position = floor_local + Vector3(0, 0.08, 0)
			p.restart()
		_lamp.position = floor_local + Vector3(0, 0.8, 0)
		Fx.pulse(_lamp, 5.0, 0.0, 0.5)
		_haze.position = floor_local + Vector3(0, 0.1, 0)
		_haze.restart()
		WorldAudio.at(self, "crusher_slam", to_global(floor_local), 1.0, 55.0)


func snap_to_clock() -> void:
	position = _floor + Vector3(0, gap_at(Game.course_time) + size.y * 0.5, 0)
	reset_physics_interpolation()


## Height of the press's underside above the floor at `time`.
func gap_at(time: float) -> float:
	var u: float = fposmod(time / period + phase, 1.0)
	if u < SLAM:
		return lift
	if u < DOWN:
		var k: float = (u - SLAM) / (DOWN - SLAM)
		return lift * (1.0 - k * k)
	if u < RISE:
		return 0.0
	var r: float = (u - RISE) / (1.0 - RISE)
	return lift * r * r * (3.0 - 2.0 * r)


## True while it is safe to stand under it for the next `window` seconds.
func is_clear_for(time: float, window: float) -> bool:
	var s: float = 0.0
	while s <= window:
		if _deadly(time + s):
			return false
		s += 0.05
	return true


func _deadly(time: float) -> bool:
	var u: float = fposmod(time / period + phase, 1.0)
	return u >= SLAM and u < RISE + 0.08


func _physics_process(_dt: float) -> void:
	var t: float = Game.course_time
	var u: float = fposmod(t / period + phase, 1.0)
	var shake := Vector3.ZERO
	if u >= SHUDDER and u < SLAM:
		shake = Vector3(sin(t * 90.0) * 0.05, 0, cos(t * 77.0) * 0.05)
	position = _floor + Vector3(0, gap_at(t) + size.y * 0.5, 0) + shake
	var glow: float = 2.4 if (u >= SHUDDER and u < RISE) else 0.4
	if not is_equal_approx(_plate_mat.emission_energy_multiplier, glow):
		_plate_mat.emission_energy_multiplier = glow
	if not _deadly(t):
		return
	for body: Node3D in _kill.get_overlapping_bodies():
		if body is Player:
			var n: Node = self
			while n != null and not n.has_method("fail"):
				n = n.get_parent()
			if n != null:
				n.call_deferred("fail", "hazard")
			return
