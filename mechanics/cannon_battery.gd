class_name CannonBattery
extends Node3D
## Cannonball battery (kit obstacle). A cannon on the course clock fires a salvo of balls down
## a lane (local -Z, turned by yaw). Each ball is a pure function of the clock, so every racer
## sees the same balls and the bot can predict them. A ball that touches the player kills
## (back to the checkpoint). Balls either ROLL on the floor (`fly_height` 0: jump them) or FLY
## at `fly_height` above it (run around them, or jump over a low one).
## The tell is a muzzle glow, a lit fuse and a flashing lane strip for `tell` seconds before
## every salvo.
##   fire time of ball j of salvo n = (n + phase) * period + j * spacing
##   it sits `speed * (t - fire time)` metres down the lane while 0 <= that <= lane_length
## The node sits on the floor under the muzzle.

@export var speed: float = 9.0
@export var lane_length: float = 22.0
@export var period: float = 3.2
@export var phase: float = 0.0
@export var ball_radius: float = 0.55
## 0 = rolls along the floor; otherwise the ball's centre height above the floor.
@export var fly_height: float = 0.0
@export var salvo: int = 1
## Seconds between the balls of one salvo.
@export var spacing: float = 0.55
@export var lane_width: float = 3.0
@export var tell: float = 1.0

var _slots: Array[Dictionary] = []
var _per_salvo: int = 1
var _salvos_alive: int = 1
var _strip: MeshInstance3D
var _glow_mat: StandardMaterial3D
var _flash: GPUParticles3D
var _smoke: GPUParticles3D
var _fuse: GPUParticles3D
var _lamp: OmniLight3D
var _last_s: float = -1.0
var _tell_played: bool = false
var _ball_mat: StandardMaterial3D


func _ready() -> void:
	tell = maxf(tell, KitUtil.MIN_TELL)
	salvo = maxi(salvo, 1)
	_per_salvo = salvo
	var flight: float = lane_length / maxf(speed, 0.5)
	_salvos_alive = int(ceil((flight + float(salvo - 1) * spacing) / period)) + 1
	_build()
	add_to_group("course_clock")
	_move_balls(Game.course_time)


func _build() -> void:
	var metal: StandardMaterial3D = Look.flat(Look.c("metal"), 0.4, 0.7)
	_glow_mat = Look.flat(Look.c("accent"), 0.4, 0.2, 0.4).duplicate() as StandardMaterial3D
	# carriage and barrel
	add_child(Look.box(Vector3(2.2, 0.9, 2.0), Look.flat(Look.c("decor").darkened(0.3), 0.8), Vector3(0, 0.45, 0.9)))
	var barrel := Look.cylinder(0.55, 2.3, metal, Vector3(0, 1.15, -0.4), 0.45, 16)
	barrel.rotation.x = PI * 0.5
	add_child(barrel)
	var muzzle := Look.cylinder(0.62, 0.3, _glow_mat, Vector3(0, 1.15, -1.5), -1.0, 16)
	muzzle.rotation.x = PI * 0.5
	add_child(muzzle)
	for sx: float in [-1.0, 1.0]:
		var wheel := Look.cylinder(0.62, 0.28, metal, Vector3(sx * 1.2, 0.62, 0.9), -1.0, 14)
		wheel.rotation.z = PI * 0.5
		add_child(wheel)
	# the lane strip on the floor: dim, flashing through the tell
	_strip = KitUtil.floor_quad(Vector2(lane_width, lane_length), Color(1.0, 0.4, 0.15, 0.0))
	_strip.position = Vector3(0, 0.05, -lane_length * 0.5 - 1.6)
	add_child(_strip)
	var vis := AABB(Vector3(-6, -2, -8), Vector3(12, 8, 12))
	var fire_dir := Vector3.FORWARD
	_flash = Fx.sparks({"amount": 60, "lifetime": 0.5, "shape": "point", "dir": fire_dir, "spread": 25.0,
		"speed": Vector2(6.0, 15.0), "color": Color(3.0, 1.9, 0.7), "aabb": vis})
	_flash.position = Vector3(0, 1.15, -1.9)
	add_child(_flash)
	_smoke = Fx.smoke({"amount": 22, "lifetime": 1.2, "shape": "point", "dir": fire_dir, "spread": 35.0,
		"speed": Vector2(1.5, 5.0), "size": 1.2, "color": Color(0.85, 0.82, 0.78, 0.75), "aabb": vis})
	_smoke.position = _flash.position
	add_child(_smoke)
	_fuse = Fx.emitter({"amount": 16, "lifetime": 0.3, "emitting": false, "shape": "point", "dir": Vector3.UP,
		"spread": 70.0, "speed": Vector2(1.0, 3.0), "gravity": Vector3(0, -6, 0), "size": 0.12,
		"color": Color(2.6, 1.6, 0.5), "aabb": vis})
	_fuse.position = Vector3(0, 1.75, 0.2)
	add_child(_fuse)
	_lamp = OmniLight3D.new()
	_lamp.light_color = Color(1.0, 0.6, 0.3)
	_lamp.omni_range = 8.0
	_lamp.light_energy = 0.0
	_lamp.visible = false
	_lamp.shadow_enabled = false
	_lamp.position = _flash.position
	add_child(_lamp)
	# the ball pool: slot (k, j) shows ball j of the k-th most recent salvo
	_ball_mat = Look.flat(Color(0.13, 0.13, 0.16), 0.35, 0.8)
	var stripe: StandardMaterial3D = Look.flat(Look.c("accent"), 0.4, 0.1, 1.6)
	for k: int in _salvos_alive:
		for j: int in _per_salvo:
			var ball := Node3D.new()
			ball.add_child(Look.sphere(ball_radius, _ball_mat))
			var band := Look.cylinder(ball_radius * 1.01, 0.1, stripe, Vector3.ZERO, -1.0, 14)
			band.rotation.z = PI * 0.5
			ball.add_child(band)
			var area := Area3D.new()
			area.collision_layer = 0
			area.collision_mask = 2
			area.monitorable = false
			var cs := CollisionShape3D.new()
			var sh := SphereShape3D.new()
			sh.radius = ball_radius * 0.92
			cs.shape = sh
			area.add_child(cs)
			ball.add_child(area)
			ball.visible = false
			add_child(ball)
			_slots.append({"node": ball, "area": area, "k": k, "j": j})


# ---- predictions -----------------------------------------------------------------------

func fire_time(n: int, j: int = 0) -> float:
	return (float(n) + phase) * period + float(j) * spacing


## Seconds until the next salvo is fired (0 right at the firing instant).
func time_to_salvo(time: float) -> float:
	var s: float = KitUtil.cycle_s(time, period, phase)
	return 0.0 if s <= 0.0001 else period - s


## Distances along the lane (metres from the muzzle) of every ball in flight at `time`.
func balls_at(time: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for j: int in _per_salvo:
		var n_max: int = int(floor((time - float(j) * spacing) / period - phase))
		for k: int in _salvos_alive:
			var d: float = speed * (time - fire_time(n_max - k, j))
			if d >= 0.0 and d <= lane_length:
				out.append(d)
	return out


## True while no ball can touch the lane stretch [d0, d1] (metres from the muzzle) in the next
## `window` seconds. `margin` widens the stretch by the player's reach.
func is_clear_for(d0: float, d1: float, window: float, time: float = -1.0e9, margin: float = 0.9) -> bool:
	var t0: float = Game.course_time if time < -1.0e8 else time
	var s: float = 0.0
	while s <= window + 0.0001:
		for d: float in balls_at(t0 + s):
			if d + ball_radius + margin >= d0 and d - ball_radius - margin <= d1:
				return false
		s += 0.04
	return true


func ball_position_at(d: float) -> Vector3:
	var y: float = ball_radius if fly_height <= 0.0 else fly_height
	return to_global(Vector3(0, y, -1.9 - d))


# ---- behaviour -------------------------------------------------------------------------

func snap_to_clock() -> void:
	_move_balls(Game.course_time)
	_last_s = -1.0


func _physics_process(_dt: float) -> void:
	_move_balls(Game.course_time)


func _move_balls(t: float) -> void:
	var y: float = ball_radius if fly_height <= 0.0 else fly_height
	for slot: Dictionary in _slots:
		var j: int = slot["j"]
		var n_max: int = int(floor((t - float(j) * spacing) / period - phase))
		var d: float = speed * (t - fire_time(n_max - int(slot["k"]), j))
		var ball: Node3D = slot["node"]
		var on: bool = d >= 0.0 and d <= lane_length
		ball.visible = on
		(slot["area"] as Area3D).monitoring = on
		if not on:
			continue
		ball.position = Vector3(0, y, -1.9 - d)
		# a rolling ball turns about its X axis as it travels (distance / radius)
		ball.rotation.x = -d / ball_radius
		if fly_height > 0.0:
			ball.rotation.x = -d / ball_radius * 0.3
		for body: Node3D in (slot["area"] as Area3D).get_overlapping_bodies():
			if body is Player:
				KitUtil.kill(self, "hazard")
				break


func _process(_dt: float) -> void:
	var t: float = Game.course_time
	var s: float = KitUtil.cycle_s(t, period, phase)
	var left: float = period - s
	# tell: muzzle heats, the fuse spits and the lane flashes for the last `tell` s of the period
	var k: float = clampf(1.0 - left / tell, 0.0, 1.0) if left < tell else 0.0
	var fire_now: bool = s < _last_s - period * 0.5
	if k > 0.0:
		KitUtil.glow(_glow_mat, 0.4 + 4.5 * k)
		var flash_on: bool = fmod(left, 0.18) > 0.09
		KitUtil.set_quad_color(_strip, Color(1.0, 0.35, 0.12, (0.18 + 0.3 * k) if flash_on else 0.06))
		_fuse.emitting = true
		if not _tell_played:
			_tell_played = true
			WorldAudio.at(self, "kit_battery_fuse", global_position, 0.7, 40.0)
	else:
		KitUtil.glow(_glow_mat, 0.4)
		KitUtil.set_quad_color(_strip, Color(1.0, 0.4, 0.15, 0.0))
		_fuse.emitting = false
	if fire_now and _last_s >= 0.0:
		_tell_played = false
		_flash.restart()
		_smoke.restart()
		Fx.pulse(_lamp, 6.0, 0.0, 0.35)
		WorldAudio.at(self, "kit_battery_fire", global_position, 1.0, 60.0)
	_last_s = s
