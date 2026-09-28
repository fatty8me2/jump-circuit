class_name ArmadaCannon
extends Node3D
## Storm Armada: a ship's cannon firing on a clock (Game.course_time). Positioned at the muzzle,
## it fires along its local -Z: an iron ball flies dead straight at `speed` for `reach` metres
## (deadly all the way), then drops away into the clouds (harmless, visual only).
## For `warn` seconds before each shot the fuse fizzes, the touch-hole and the barrel band glow
## brighter and brighter, and the red studs on the deck under the ball's lane light up - then a
## flash, a cloud of smoke, sparks and a recoil. Several balls can be in the air at once when the
## flight is longer than the period. Pure function of the clock, like every machine.
##   cycle: fires at u = 0 (u = fposmod(t / period + phase, 1)).

@export var period: float = 4.0
@export var phase: float = 0.0
@export var speed: float = 24.0
## Deadly flight length (m); the ball then falls away harmlessly.
@export var reach: float = 30.0
@export var ball_radius: float = 0.42
@export var warn: float = 1.2
## Studs on the deck under the lane: how far below the ball the deck is (0 = no studs), and over
## which stretch of the lane (metres from the muzzle) they run.
@export var lane_drop: float = 0.0
@export var lane_from: float = 2.0
@export var lane_to: float = -1.0
## Draw the gun itself (a hidden battery in a hull only needs the muzzle effects).
@export var show_gun: bool = true
## Visual: the balls fly on to this distance and smash into what is there (0 = they plunge away
## into the clouds after `reach`). Never deadly beyond `reach`.
@export var stop_at: float = 0.0

const IRON := Color(0.16, 0.16, 0.18)
const BRASS := Color(0.85, 0.62, 0.28)
const FALL_TIME: float = 1.1

var _balls: Array[Node3D] = []
var _trails: Array[GPUParticles3D] = []
var _barrel: Node3D
var _hole_mat: StandardMaterial3D
var _band_mat: StandardMaterial3D
var _stud_mat: StandardMaterial3D
var _fuse: GPUParticles3D
var _smoke: GPUParticles3D
var _sparks: GPUParticles3D
var _flash: OmniLight3D
var _last_shot: int = -999999
var _impact_shot: int = -999999
var _hit_smoke: GPUParticles3D
var _hit_debris: GPUParticles3D
var _was_warn: bool = false


func _ready() -> void:
	_build()
	add_to_group("course_clock")
	_last_shot = _shot_index(Game.course_time)
	_apply(Game.course_time)


## Index of the most recent shot at `time` (shot k fires at (k - phase) * period).
func _shot_index(time: float) -> int:
	return int(floor(time / period + phase))


func _shot_time(k: int) -> float:
	return (float(k) - phase) * period


## Seconds until the next shot.
func time_until_fire(time: float) -> float:
	return (1.0 - fposmod(time / period + phase, 1.0)) * period


## Distances (m from the muzzle) of every deadly ball in flight at `time`.
func ball_distances(time: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var flight: float = reach / speed
	var k: int = _shot_index(time)
	var back: int = int(ceil(flight / period)) + 1
	for i: int in back:
		var dt: float = time - _shot_time(k - i)
		if dt >= 0.0 and dt * speed <= reach:
			out.append(dt * speed)
	return out


## True if a ball will be within `margin` m of a player standing with feet at `p` at `time`.
func threat(p: Vector3, time: float, margin: float = 0.0) -> bool:
	var fwd: Vector3 = -global_basis.z
	for s: float in ball_distances(time):
		var c: Vector3 = global_position + fwd * s
		if _capsule_dist(p, c) < ball_radius + 0.38 + margin:
			return true
	return false


## No ball comes within `margin` of feet position `p` over the window [time + a, time + b].
func is_clear_for(p: Vector3, time: float, a: float, b: float, margin: float = 0.3) -> bool:
	var s: float = a
	while s <= b:
		if threat(p, time + s, margin):
			return false
		s += 0.02
	return true


func _capsule_dist(feet: Vector3, c: Vector3) -> float:
	var y: float = clampf(c.y, feet.y + 0.4, feet.y + 1.4)
	return c.distance_to(Vector3(feet.x, y, feet.z))


func snap_to_clock() -> void:
	_last_shot = _shot_index(Game.course_time)
	_apply(Game.course_time)


func _physics_process(_dt: float) -> void:
	var t: float = Game.course_time
	var pl: Node3D = WorldAudio.local_player(self)
	if pl == null or not (pl is Player):
		return
	if threat(pl.global_position, t):
		var n: Node = self
		while n != null and not n.has_method("fail"):
			n = n.get_parent()
		if n != null:
			n.call_deferred("fail", "hazard")


func _process(_dt: float) -> void:
	_apply(Game.course_time)


func _apply(t: float) -> void:
	var k: int = _shot_index(t)
	if k != _last_shot:
		if k == _last_shot + 1 and t - _shot_time(k) < 0.25:
			_fire_fx()
		_last_shot = k
	var until: float = time_until_fire(t)
	var warning: bool = until < warn
	var w: float = 1.0 - until / warn if warning else 0.0
	var glow: float = 0.3 + w * w * 4.0 * (0.75 + 0.25 * sin(t * 40.0)) if warning else 0.3
	_hole_mat.emission_energy_multiplier = glow
	_band_mat.emission_energy_multiplier = 0.15 + w * 1.6
	if _stud_mat != null:
		_stud_mat.emission_energy_multiplier = 0.4 + w * w * 5.0 * (0.7 + 0.3 * sin(t * 30.0)) if warning else 0.4
	if _fuse.emitting != warning:
		_fuse.emitting = warning
	if warning and not _was_warn:
		WorldAudio.at(self, "armada_cannon_fuse", global_position, 0.7, 30.0)
	_was_warn = warning
	# recoil: kicks back 0.5 m at the shot, rolls forward again over 0.8 s
	if _barrel != null:
		var since: float = t - _shot_time(k)
		var r: float = 0.0
		if since >= 0.0 and since < 0.8:
			r = 0.5 * (1.0 - since / 0.8) * (1.0 - since / 0.8)
		_barrel.position.z = r
	# the balls: straight and deadly out to `reach`; then (visual only) either on to `stop_at`, where
	# they smash into what they were aimed at, or losing their pace and plunging into the clouds.
	# Each shot keeps its own ball (slot = shot index mod pool) so no trail ever jumps between shots.
	var fwd := Vector3(0, 0, -1)
	var n: int = _balls.size()
	var life: float = _life()
	var flight: float = reach / speed
	for j: int in n:
		var shot: int = k - j
		var slot: int = posmod(shot, n)
		var ball: Node3D = _balls[slot]
		var dt: float = t - _shot_time(shot)
		if dt < 0.0 or dt > life:
			if ball.visible:
				ball.visible = false
				_trails[slot].emitting = false
			if stop_at > 0.0 and dt > life and dt < life + 0.25 and _impact_shot != shot:
				_impact_shot = shot
				_impact()
			continue
		var pos: Vector3
		if dt * speed <= reach or stop_at > 0.0:
			pos = fwd * (dt * speed)
		else:
			var f: float = dt - flight
			pos = fwd * (reach + speed * 0.3 * (1.0 - exp(-3.0 * f))) + Vector3(0, -9.0 * f * f, 0)
		ball.position = pos
		if not ball.visible:
			ball.visible = true
			_trails[slot].restart()
			_trails[slot].emitting = true


## Seconds a ball stays in sight after its shot.
func _life() -> float:
	return stop_at / speed if stop_at > 0.0 else reach / speed + FALL_TIME


## The ball smashes into its target at `stop_at` (visual): a burst of smoke, sparks and splinters.
func _impact() -> void:
	if _hit_smoke == null:
		return
	_hit_smoke.restart()
	_hit_smoke.emitting = true
	_hit_debris.restart()
	_hit_debris.emitting = true
	WorldAudio.at(self, "armada_cannon_impact", global_position - global_basis.z * stop_at, 0.9, 50.0)


func _fire_fx() -> void:
	_smoke.restart()
	_smoke.emitting = true
	_sparks.restart()
	_sparks.emitting = true
	Fx.pulse(_flash, 6.0, 0.0, 0.3)
	WorldAudio.at(self, "armada_cannon_fire", global_position, 1.0, 60.0)


func _build() -> void:
	var iron: StandardMaterial3D = Look.flat(IRON, 0.35, 0.8)
	var wood: StandardMaterial3D = Look.flat(Color(0.36, 0.22, 0.13), 0.8)
	_band_mat = Look.flat(BRASS, 0.3, 0.9, 0.15).duplicate() as StandardMaterial3D
	_hole_mat = Look.flat(Color(1.0, 0.45, 0.12), 0.4, 0.0, 0.3).duplicate() as StandardMaterial3D
	if show_gun:
		# the barrel (recoils along local +Z), a brass muzzle ring and breech band
		_barrel = Node3D.new()
		add_child(_barrel)
		var tube := Look.cylinder(0.3, 2.4, iron, Vector3(0, 0, 1.2), 0.24, 16)
		tube.rotation.x = PI * 0.5
		_barrel.add_child(tube)
		var lip := Look.cylinder(0.36, 0.22, _band_mat, Vector3(0, 0, 0.1), -1.0, 16)
		lip.rotation.x = PI * 0.5
		_barrel.add_child(lip)
		var band := Look.cylinder(0.4, 0.3, _band_mat, Vector3(0, 0, 2.2), -1.0, 16)
		band.rotation.x = PI * 0.5
		_barrel.add_child(band)
		_barrel.add_child(Look.sphere(0.34, iron, Vector3(0, 0, 2.45)))
		_barrel.add_child(Look.sphere(0.09, _hole_mat, Vector3(0, 0.33, 2.15)))
		# the carriage: cheeks and trucks
		for sx: float in [-1.0, 1.0]:
			add_child(Look.box(Vector3(0.14, 0.62, 1.8), wood, Vector3(sx * 0.42, -0.45, 1.6)))
			for z: float in [0.9, 2.2]:
				var wheel := Look.cylinder(0.26, 0.12, wood, Vector3(sx * 0.52, -0.72, z), -1.0, 12)
				wheel.rotation.z = PI * 0.5
				add_child(wheel)
		add_child(Look.box(Vector3(0.95, 0.16, 2.0), wood, Vector3(0, -0.72, 1.6)))
	else:
		# just the black mouth of a gun port and its glowing touch-hole
		var mouth := Look.cylinder(0.34, 0.3, iron, Vector3(0, 0, 0.15), -1.0, 16)
		mouth.rotation.x = PI * 0.5
		add_child(mouth)
		var ring := Look.cylinder(0.42, 0.12, _band_mat, Vector3(0, 0, 0.02), -1.0, 16)
		ring.rotation.x = PI * 0.5
		add_child(ring)
		add_child(Look.sphere(0.1, _hole_mat, Vector3(0, 0.42, 0.2)))
	# deck studs marking the lane
	if lane_drop > 0.0:
		_stud_mat = Look.flat(Color(1.0, 0.22, 0.12), 0.4, 0.0, 0.4).duplicate() as StandardMaterial3D
		var end: float = lane_to if lane_to > 0.0 else reach
		var s: float = lane_from
		while s <= end:
			var stud := Look.box(Vector3(0.5, 0.05, 0.22), _stud_mat, Vector3(0, -lane_drop + 0.02, -s))
			stud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(stud)
			s += 1.6
	# the ball pool: enough for every ball that can be in the air at once
	var n: int = int(ceil(_life() / period)) + 1
	var ball_mat: StandardMaterial3D = Look.flat(Color(0.1, 0.1, 0.11), 0.3, 0.85)
	var hot: StandardMaterial3D = Look.flat(Color(1.0, 0.5, 0.2), 0.4, 0.0, 2.2)
	for i: int in n:
		var b := Node3D.new()
		b.add_child(Look.sphere(ball_radius, ball_mat))
		var glint := Look.sphere(ball_radius * 0.55, hot, Vector3(0, 0, ball_radius * 0.55))
		b.add_child(glint)
		var tr: GPUParticles3D = Fx.trail({"amount": 26, "lifetime": 0.5, "size": 0.5, "color": Color(0.55, 0.52, 0.5, 0.5),
			"additive": false, "emitting": false, "aabb": AABB(Vector3(-80, -40, -80), Vector3(160, 80, 160))})
		tr.local_coords = false
		b.add_child(tr)
		b.visible = false
		add_child(b)
		_balls.append(b)
		_trails.append(tr)
	var vis := AABB(Vector3(-6, -4, -10), Vector3(12, 10, 14))
	_fuse = Fx.emitter({"amount": 14, "lifetime": 0.4, "emitting": false, "shape": "sphere", "radius": 0.05,
		"dir": Vector3.UP, "spread": 60.0, "speed": Vector2(1.0, 2.6), "gravity": Vector3(0, -4, 0),
		"tex": Fx.Tex.DOT, "size": 0.08, "color": Color(3.0, 1.8, 0.6), "fade": PackedFloat32Array([1.0, 1.0, 0.0]), "aabb": vis})
	_fuse.position = Vector3(0, 0.45, 2.15) if show_gun else Vector3(0, 0.5, 0.2)
	add_child(_fuse)
	_smoke = Fx.smoke({"amount": 26, "lifetime": 1.6, "shape": "sphere", "radius": 0.3, "dir": Vector3(0, 0.15, -1),
		"spread": 25.0, "speed": Vector2(2.0, 7.0), "damping": Vector2(2.0, 4.0), "gravity": Vector3(0, 0.6, 0), "size": 1.6,
		"color": Color(0.78, 0.76, 0.74, 0.7), "aabb": AABB(Vector3(-8, -4, -14), Vector3(16, 12, 18))})
	_smoke.position = Vector3(0, 0, -0.3)
	add_child(_smoke)
	_sparks = Fx.sparks({"amount": 20, "shape": "sphere", "radius": 0.2, "dir": Vector3(0, 0.1, -1), "spread": 30.0,
		"speed": Vector2(6.0, 14.0), "color": Color(3.2, 1.8, 0.5), "aabb": AABB(Vector3(-8, -4, -14), Vector3(16, 12, 18))})
	_sparks.position = Vector3(0, 0, -0.3)
	add_child(_sparks)
	if stop_at > 0.0:
		var hv := AABB(Vector3(-8, -6, -8), Vector3(16, 14, 16))
		_hit_smoke = Fx.smoke({"amount": 20, "lifetime": 1.3, "shape": "sphere", "radius": 0.4, "dir": Vector3(0, 0.4, 1),
			"spread": 60.0, "speed": Vector2(1.5, 5.0), "size": 1.4, "color": Color(0.5, 0.48, 0.46, 0.65), "aabb": hv})
		_hit_smoke.position = Vector3(0, 0, -stop_at)
		add_child(_hit_smoke)
		_hit_debris = Fx.debris({"amount": 16, "shape": "sphere", "radius": 0.3, "dir": Vector3(0, 0.5, 1), "spread": 50.0,
			"speed": Vector2(3.0, 8.0), "color": Color(0.45, 0.3, 0.17), "aabb": hv})
		_hit_debris.position = Vector3(0, 0, -stop_at)
		add_child(_hit_debris)
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.7, 0.35)
	_flash.omni_range = 9.0
	_flash.light_energy = 0.0
	_flash.shadow_enabled = false
	_flash.position = Vector3(0, 0.3, -0.8)
	_flash.visible = false
	add_child(_flash)
