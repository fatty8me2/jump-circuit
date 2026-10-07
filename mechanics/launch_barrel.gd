class_name LaunchBarrel
extends Node3D
## Launch barrel (kit obstacle). Walk or fall into the open mouth and you are held inside; the
## barrel shudders and glows for `tell` seconds, then fires you along a FIXED arc to `target`.
## Firing happens on the course clock grid (k + phase) * period, never earlier than `tell`
## after you got in, so the moment is a pure function of when you entered (the bot can predict
## it with fire_time_after()). The barrel's origin is where a loaded rider's FEET sit.
##
## The arc assumes the stick is held toward the target in flight (air braking pulls 3 m/s^2
## with no input), so give the landing spot room: 4 m or more across.

@export var target: Vector3 = Vector3(0, 0, -10)
## Metres the arc rises above the higher of start and target.
@export var arc: float = 3.0
@export var period: float = 3.0
@export var phase: float = 0.0
@export var tell: float = 1.0
## Radius of the mouth that catches a rider.
@export var mouth: float = 1.0

var _vel: Vector3 = Vector3.ZERO
var _area: Area3D
var _tube: Node3D
var _rider: Player = null
var _fire_at: float = 0.0
var _loaded_at: float = 0.0
var _cool_until: float = -1.0
var _was_control: bool = true
var _fired_tick: int = -100000
var _glow_mat: StandardMaterial3D
var _flash: GPUParticles3D
var _smoke: GPUParticles3D
var _lamp: OmniLight3D
var _fuse: GPUParticles3D
var _fx_state: int = 0   # 0 idle, 1 loaded


func _ready() -> void:
	process_physics_priority = KitUtil.EARLY
	tell = maxf(tell, KitUtil.MIN_TELL)
	_vel = KitUtil.launch_velocity(global_position, target, arc)
	_build()
	add_to_group("resettable")
	add_to_group("course_clock")


func _build() -> void:
	var dir: Vector3 = _vel.normalized()
	_tube = Node3D.new()
	_tube.basis = Fx.basis_up(dir)
	add_child(_tube)
	var wood: StandardMaterial3D = Look.flat(Look.c("decor").darkened(0.35), 0.85, 0.1)
	var band_col: Color = Look.c("accent")
	_glow_mat = Look.flat(band_col, 0.4, 0.2, 0.5).duplicate() as StandardMaterial3D
	# the staves, bulging a little, with two glowing hoops and a dark inside
	_tube.add_child(Look.cylinder(mouth * 1.15, 2.0, wood, Vector3(0, -0.15, 0), mouth * 1.05, 16))
	for y: float in [-0.75, 0.55]:
		_tube.add_child(Look.cylinder(mouth * 1.2, 0.16, _glow_mat, Vector3(0, y, 0), -1.0, 16))
	_tube.add_child(Look.cylinder(mouth * 0.9, 0.04, Look.flat(Color(0.03, 0.03, 0.04), 1.0), Vector3(0, 0.85, 0), -1.0, 16))
	# a wide base so it reads as sitting on something
	add_child(Look.cylinder(mouth * 1.35, 0.3, Look.flat(Look.c("metal"), 0.5, 0.6), Vector3(0, -1.0, 0), mouth * 1.5, 12))
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 2
	_area.monitorable = false
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = mouth
	sh.height = 1.8
	cs.shape = sh
	_area.add_child(cs)
	_area.position = Vector3(0, 0.6, 0)
	add_child(_area)
	var vis := AABB(Vector3(-6, -4, -6), Vector3(12, 12, 12))
	_flash = Fx.sparks({"amount": 50, "lifetime": 0.5, "shape": "point", "dir": dir, "spread": 28.0,
		"speed": Vector2(6.0, 14.0), "color": Color(3.0, 1.8, 0.6), "aabb": vis})
	_flash.position = dir * 1.2
	add_child(_flash)
	_smoke = Fx.smoke({"amount": 20, "lifetime": 1.0, "shape": "point", "dir": dir, "spread": 40.0,
		"speed": Vector2(1.0, 4.0), "size": 1.0, "color": Color(0.85, 0.8, 0.75, 0.7), "aabb": vis})
	_smoke.position = dir * 1.2
	add_child(_smoke)
	_fuse = Fx.emitter({"amount": 18, "lifetime": 0.35, "emitting": false, "shape": "sphere", "radius": 0.15,
		"dir": Vector3.UP, "spread": 60.0, "speed": Vector2(1.0, 3.0), "gravity": Vector3(0, -6, 0),
		"size": 0.14, "color": Color(2.6, 1.6, 0.5), "aabb": vis})
	_fuse.position = Vector3(0, 1.1, 0)
	add_child(_fuse)
	_lamp = OmniLight3D.new()
	_lamp.light_color = band_col
	_lamp.omni_range = 7.0
	_lamp.light_energy = 0.0
	_lamp.visible = false
	_lamp.shadow_enabled = false
	_lamp.position = Vector3(0, 1.0, 0)
	add_child(_lamp)


## ---- predictions the route bot (and level scripts) use ----------------------------------

## The clock time a rider who gets in at `time` is fired.
func fire_time_after(time: float) -> float:
	return KitUtil.next_grid(time, period, phase, tell)


func launch_velocity() -> Vector3:
	return _vel


func is_loaded() -> bool:
	return _rider != null


func loaded_player() -> Player:
	return _rider


## True for `window` seconds after the last firing.
func fired_within(window: float) -> bool:
	return float(Engine.get_physics_frames() - _fired_tick) / float(Engine.physics_ticks_per_second) <= window


## Seconds until a rider loaded now would be fired (-1 when empty).
func time_to_fire() -> float:
	return _fire_at - Game.course_time if _rider != null else -1.0


# ---- behaviour --------------------------------------------------------------------------

func snap_to_clock() -> void:
	reset_state()


func reset_state() -> void:
	_release(false)
	_cool_until = -1.0


func _capture(p: Player) -> void:
	_rider = p
	_was_control = p.control_enabled
	p.control_enabled = false
	_loaded_at = Game.course_time
	_fire_at = fire_time_after(Game.course_time)
	if not p.teleported.is_connected(_on_rider_teleported):
		p.teleported.connect(_on_rider_teleported)
	WorldAudio.at(self, "kit_barrel_load", global_position, 0.8, 35.0)
	_fx_state = 1
	_fuse.emitting = true


func _on_rider_teleported() -> void:
	# a respawn (or any teleport) frees the rider without a launch
	if _rider != null:
		_release(false)
		_cool_until = Game.course_time + 0.5


func _release(fire: bool) -> void:
	var p: Player = _rider
	_rider = null
	_fuse.emitting = false
	_lamp.visible = false
	_lamp.light_energy = 0.0
	_fx_state = 0
	if p == null or not is_instance_valid(p):
		return
	if p.teleported.is_connected(_on_rider_teleported):
		p.teleported.disconnect(_on_rider_teleported)
	p.control_enabled = _was_control
	if fire:
		p.global_position = global_position
		p.knockback(_vel)
		p.reset_physics_interpolation()


func _physics_process(dt: float) -> void:
	var t: float = Game.course_time
	if _rider != null:
		if not is_instance_valid(_rider):
			_rider = null
			return
		if _fire_at - t > period + tell + 1.0 or t < _loaded_at - 0.01:
			# the course clock was wound back (restart): let the rider go
			_release(false)
			return
		_rider.global_position = _rider.global_position.lerp(global_position, clampf(dt * 16.0, 0.0, 1.0))
		_rider.velocity = Vector3.ZERO
		_rider.set("_no_snap", 0.2)   # no floor snap while held aloft
		var left: float = _fire_at - t
		var k: float = clampf(1.0 - left / tell, 0.0, 1.0)
		_shudder(k)
		if t >= _fire_at:
			_fire()
		return
	_rest_pose()
	if t < _cool_until:
		return
	var p: Player = KitUtil.player_in(_area, true)
	if p != null:
		_capture(p)


func _fire() -> void:
	_release(true)
	_fired_tick = Engine.get_physics_frames()
	_cool_until = Game.course_time + 0.7
	_flash.restart()
	_smoke.restart()
	Fx.pulse(_lamp, 5.0, 0.0, 0.4)
	WorldAudio.at(self, "kit_barrel_fire", global_position, 1.0, 55.0)
	_rest_pose()


## Idle pose: a gentle sway and a dim hoop glow.
func _rest_pose() -> void:
	_tube.position = Vector3.ZERO
	KitUtil.glow(_glow_mat, 0.5)


## The tell: the barrel shakes harder and the hoops climb to white-hot as the shot nears.
func _shudder(k: float) -> void:
	var t: float = Game.course_time
	var amp: float = 0.02 + 0.08 * k * k
	_tube.position = Vector3(sin(t * 83.0) * amp, 0.0, cos(t * 71.0) * amp)
	KitUtil.glow(_glow_mat, 0.5 + 4.0 * k)
	if not _lamp.visible and k > 0.2:
		_lamp.visible = true
	_lamp.light_energy = 0.4 + 2.2 * k
	if not WorldAudio.enabled():
		return
	if _fx_state == 1 and k > 0.0 and fposmod(t, 0.2) < 0.02:
		WorldAudio.at(self, "kit_barrel_fuse", global_position, 0.3 + 0.4 * k, 25.0, 0.04)
