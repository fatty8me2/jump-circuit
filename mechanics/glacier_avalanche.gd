class_name GlacierAvalanche
extends Node3D
## Frostbite Pass: the AVALANCHE. On a fixed rhythm (Game.course_time) the cornice at the top
## of a slope cracks (a glowing fracture line, snow pouring off the lip, a deep rumble for
## `warn` seconds) and lets go: a boiling wall of snow thunders down the slope, slow at first
## and faster and faster, and buries anyone it catches. It passes over the SHELTERS (rock
## overhangs and ice caves the level registers with add_shelter) and ends in the run-out at the
## bottom in a burst of powder. Everything is a pure function of the clock, so a checkpoint
## restart re-arms it and every racer sees the same wave.
## Local frame: origin at the top of the slope (the release line) on its surface; the slope
## runs down toward local -Z, dropping `drop` metres over `length`; X across it.

const WALL_SHADER: Shader = preload("res://visual/glacier_snowwall.gdshader")
const CRACK := Color(1.0, 0.35, 0.45)

@export var length: float = 70.0
@export var drop: float = 18.0
@export var width: float = 16.0
## How high above the slope the front buries you (and how far below it reaches).
@export var height: float = 7.0
@export var depth: float = 3.0
@export var period: float = 10.0
@export var phase: float = 0.0
## Seconds the front takes from the release line to the bottom.
@export var run_time: float = 5.0
## Share of the run's average speed the wave starts with (the rest is acceleration).
@export var start_frac: float = 0.35
@export var warn: float = 1.4
@export var thickness: float = 2.4

## Shelters in local space.
var shelters: Array[AABB] = []
## Local z where the course crosses the slope (set by the level; used by timing checks).
var path_lz: float = 0.0

var _front: Node3D
var _balls: Array[Node3D] = []
var _billows: GPUParticles3D
var _spray: GPUParticles3D
var _chunks: GPUParticles3D
var _slough: GPUParticles3D
var _crack_mat: StandardMaterial3D
var _end_burst: Array[GPUParticles3D] = []
var _prev_rel: float = 0.0
var _prev_p: Vector3 = Vector3.ZERO
var _prev_wave: int = -1
var _state: int = -1
# sound (side effect only): the rumble as the cornice cracks, the roar of the running wave
var _roar: AudioStreamPlayer3D


func _ready() -> void:
	_build_visual()
	add_to_group("course_clock")
	snap_to_clock()
	_roar = WorldAudio.loop("avalanche_roar", _front, 0.0, 70.0, 12.0, is_running_at(Game.course_time))


func add_shelter(local_center: Vector3, size: Vector3) -> void:
	shelters.append(AABB(local_center - size * 0.5, size))


func snap_to_clock() -> void:
	_prev_wave = -1
	_state = _state_at(Game.course_time)
	_apply(Game.course_time)
	_front.reset_physics_interpolation()


# ---- the rhythm (pure functions of the course clock) ------------------------------------------

func _s(time: float) -> float:
	return fposmod(time / period + phase, 1.0) * period


## Slope surface height (local y) at local z.
func surface_y(z: float) -> float:
	return clampf(z, -length, 0.0) * drop / length


## Share of the slope covered after k (0..1) of the run.
func _cover(k: float) -> float:
	return start_frac * k + (1.0 - start_frac) * k * k


func is_running_at(time: float) -> bool:
	return _s(time) < run_time


## Local z of the front at `time`, or NAN while the slope is quiet.
func front_z_at(time: float) -> float:
	var s: float = _s(time)
	if s >= run_time:
		return NAN
	return -length * _cover(s / run_time)


## Front speed (m/s along the slope) at `time` (0 while quiet).
func speed_at(time: float) -> float:
	var s: float = _s(time)
	if s >= run_time:
		return 0.0
	var k: float = s / run_time
	return length / run_time * (start_frac + 2.0 * (1.0 - start_frac) * k)


## Seconds from `time` until the front next reaches local z `lz` (0 if it is there now).
func time_until_front_at(time: float, lz: float) -> float:
	var target: float = clampf(-lz / length, 0.0, 1.0)
	# start_frac k + (1 - start_frac) k^2 = target
	var a: float = 1.0 - start_frac
	var k: float = target / maxf(start_frac, 0.001)
	if a > 0.0001:
		k = (-start_frac + sqrt(start_frac * start_frac + 4.0 * a * target)) / (2.0 * a)
	var d: float = k * run_time - _s(time)
	if d < 0.0:
		d += period
	return d


## Seconds until the next release (0 while the wave runs).
func time_until_release(time: float) -> float:
	var s: float = _s(time)
	return 0.0 if s < run_time else period - s


func _sheltered(p: Vector3) -> bool:
	for a: AABB in shelters:
		if a.has_point(p):
			return true
	return false


# ---- gameplay ----------------------------------------------------------------------------------

func _physics_process(_dt: float) -> void:
	var t: float = Game.course_time
	var z: float = front_z_at(t)
	var level: Node = _level()
	if level == null or is_nan(z):
		_prev_wave = -1
		return
	var player: Node3D = level.get("player")
	if player == null:
		return
	var wave: int = int(floor(t / period + phase))
	var p: Vector3 = to_local(player.global_position + Vector3(0, 0.9, 0))
	var rel: float = p.z - z
	# a crossing only counts for a body that moved there (not a respawn / warp teleport)
	var crossed: bool = _prev_wave == wave and signf(rel) != signf(_prev_rel) and p.distance_to(_prev_p) < 3.0
	_prev_wave = wave
	_prev_rel = rel
	_prev_p = p
	# above the release line (the cornice, where a course waits for its moment) is never buried
	if absf(p.x) > width * 0.5 or p.z > 0.3:
		return
	var h: float = p.y - surface_y(p.z)
	if h > height or h < -depth:
		return
	if (absf(rel) < thickness * 0.5 + 0.35 or crossed) and not _sheltered(p):
		level.call_deferred("fail", "hazard")


func _level() -> Node:
	var n: Node = self
	while n != null and not n.has_method("fail"):
		n = n.get_parent()
	return n


# ---- look -----------------------------------------------------------------------------------------

func _state_at(t: float) -> int:
	var s: float = _s(t)
	if s < run_time:
		return 1
	if period - s < warn:
		return 0
	return 2


func _process(_dt: float) -> void:
	var t: float = Game.course_time
	var st: int = _state_at(t)
	if st != _state:
		match st:
			0:
				WorldAudio.at(self, "avalanche_rumble", global_position, 1.0, 110.0)
			1:
				WorldAudio.at(self, "snow_thump", global_position, 1.0, 110.0)
			2:
				if _state == 1:
					var bottom: Vector3 = to_global(Vector3(0, surface_y(-length), -length))
					for p: GPUParticles3D in _end_burst:
						p.global_position = bottom + Vector3(0, 1.0, 0)
						p.restart()
					WorldAudio.at(self, "snow_thump", bottom, 1.0, 90.0)
		_state = st
	_apply(t)


func _apply(t: float) -> void:
	var s: float = _s(t)
	var z: float = front_z_at(t)
	var running: bool = not is_nan(z)
	_front.visible = running
	if running:
		var k: float = s / run_time
		_front.position = Vector3(0, surface_y(z), z)
		# the wall grows out of the cornice in the first moments and churns faster as it speeds up
		var grow: float = clampf(s / 0.45, 0.2, 1.0)
		_front.scale = Vector3(1.0, grow, 1.0)
		for i: int in _balls.size():
			var b: Node3D = _balls[i]
			b.rotation.x = -t * (2.0 + 4.0 * k) - float(i)
	if _billows.emitting != running:
		_billows.emitting = running
		_spray.emitting = running
		_chunks.emitting = running
	# the release line: dim rime, then a hot fracture flickering across the slope before it goes
	var until: float = period - s
	var warning: bool = not running and until < warn
	if _slough.emitting != warning:
		_slough.emitting = warning
	var glow: float = 0.2
	var col: Color = GlacierFx.ICE
	if warning:
		var q: float = 1.0 - until / warn
		col = GlacierFx.ICE.lerp(CRACK, clampf(q * 1.5, 0.0, 1.0))
		glow = 1.0 + 4.0 * q * (0.6 + 0.4 * sin(t * 36.0))
	elif running and s < 0.5:
		col = CRACK
		glow = 5.0 * (1.0 - s / 0.5)
	_crack_mat.albedo_color = col
	_crack_mat.emission = col
	_crack_mat.emission_energy_multiplier = glow
	if _roar != null:
		WorldAudio.set_active(_roar, running)


func _build_visual() -> void:
	var slope := atan2(drop, length)
	var vis := AABB(Vector3(-width, -depth - 4.0, -length - 10.0), Vector3(width * 2.0, height + depth + 30.0, length + 20.0))
	# the front: a row of churning snow billows square across the slope, tilted with it
	_front = Node3D.new()
	_front.rotation.x = -slope
	add_child(_front)
	var mat := ShaderMaterial.new()
	mat.shader = WALL_SHADER
	var n: int = maxi(int(width / 2.6), 3)
	for i: int in n:
		var x: float = -width * 0.5 + (float(i) + 0.5) * width / float(n)
		var holder := Node3D.new()
		holder.position = Vector3(x, height * 0.42, 0.4 * sin(float(i) * 2.3))
		var r: float = height * (0.42 + 0.08 * sin(float(i) * 1.7))
		var ball := Look.sphere(1.0, mat)
		ball.scale = Vector3(width / float(n) * 0.85, r, r * 0.9)
		ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(ball)
		# a lower, faster roll of snow at the foot
		var foot := Look.sphere(1.0, mat, Vector3(0, -height * 0.25, -r * 0.5))
		foot.scale = Vector3(width / float(n) * 0.7, r * 0.45, r * 0.5)
		foot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(foot)
		_front.add_child(holder)
		_balls.append(holder)
	# a crown of powder boiling off the top and trailing back up the slope (world space: it
	# hangs in the air behind the wave), spray thrown forward, chunks tumbling ahead
	_billows = Fx.emitter({"amount": int(width * 5.0), "lifetime": 1.8, "emitting": false, "shape": "box",
		"extents": Vector3(width * 0.5, height * 0.35, 0.8), "offset": Vector3(0, height * 0.55, 0),
		"dir": Vector3(0, 0.6, 1), "spread": 35.0, "speed": Vector2(2.0, 6.0), "damping": Vector2(0.5, 1.5),
		"tex": Fx.Tex.SMOKE, "additive": false, "size": 5.0, "scale": Vector2(0.7, 1.4), "curve": "puff",
		"angle": Vector2(0, 360), "spin": Vector2(-40, 40), "color": Color(0.94, 0.96, 1.0, 0.85),
		"fade": PackedFloat32Array([0.0, 0.9, 0.5, 0.0]), "aabb": vis})
	_front.add_child(_billows)
	_spray = Fx.emitter({"amount": int(width * 8.0), "lifetime": 0.7, "emitting": false, "shape": "box",
		"extents": Vector3(width * 0.5, height * 0.3, 0.3), "offset": Vector3(0, height * 0.35, -1.2),
		"dir": Vector3(0, 0.35, -1), "spread": 25.0, "speed": Vector2(6.0, 14.0), "gravity": Vector3(0, -9.0, 0),
		"additive": false, "size": 0.18, "color": Color(1, 1, 1, 0.9), "fade": PackedFloat32Array([1.0, 1.0, 0.0]), "aabb": vis})
	_front.add_child(_spray)
	_chunks = Fx.debris({"amount": int(width * 1.5), "lifetime": 0.9, "one_shot": false, "explosiveness": 0.0, "emitting": false,
		"shape": "box", "extents": Vector3(width * 0.45, 0.4, 0.5), "offset": Vector3(0, 0.6, -1.5),
		"dir": Vector3(0, 0.6, -1), "spread": 30.0, "speed": Vector2(4.0, 9.0), "chunk": 0.45, "color": Color(0.9, 0.94, 1.0), "aabb": vis})
	_front.add_child(_chunks)
	# the release line: a fracture across the slope's top, and snow pouring off the cornice
	_crack_mat = StandardMaterial3D.new()
	_crack_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_crack_mat.albedo_color = GlacierFx.ICE
	_crack_mat.emission_enabled = true
	_crack_mat.emission = GlacierFx.ICE
	for i: int in 5:
		var seg := Look.box(Vector3(width / 5.0 + 0.2, 0.08, 0.18), _crack_mat, Vector3(-width * 0.5 + (float(i) + 0.5) * width / 5.0, 0.06, 0.3 * sin(float(i) * 2.1)))
		seg.rotation.y = 0.12 * sin(float(i) * 3.7)
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(seg)
	_slough = Fx.emitter({"amount": int(width * 3.0), "lifetime": 1.4, "emitting": false, "shape": "box",
		"extents": Vector3(width * 0.5, 0.3, 0.6), "offset": Vector3(0, 1.0, 0.8), "dir": Vector3(0, -0.3, -1),
		"spread": 25.0, "speed": Vector2(1.0, 3.0), "gravity": Vector3(0, -6.0, 0), "tex": Fx.Tex.SMOKE, "additive": false,
		"size": 1.2, "curve": "puff", "color": Color(0.95, 0.97, 1.0, 0.6), "fade": PackedFloat32Array([0.0, 0.8, 0.0]), "aabb": vis})
	add_child(_slough)
	# the wave spending itself in the run-out
	var burst: GPUParticles3D = Fx.smoke({"amount": int(width * 3.0), "lifetime": 2.2, "shape": "box",
		"extents": Vector3(width * 0.5, 1.0, 1.5), "dir": Vector3(0, 1, -0.4), "spread": 50.0, "speed": Vector2(3.0, 9.0),
		"size": 6.0, "color": Color(0.94, 0.96, 1.0, 0.8), "aabb": AABB(Vector3(-width - 10, -5, -20), Vector3(width * 2 + 20, 30, 40))})
	add_child(burst)
	_end_burst.append(burst)
	var bits: GPUParticles3D = Fx.debris({"amount": int(width * 2.0), "lifetime": 1.3, "shape": "box",
		"extents": Vector3(width * 0.45, 0.5, 1.0), "dir": Vector3(0, 1, -0.6), "spread": 45.0, "speed": Vector2(5.0, 11.0),
		"chunk": 0.5, "color": Color(0.9, 0.94, 1.0), "aabb": AABB(Vector3(-width - 10, -8, -25), Vector3(width * 2 + 20, 30, 50))})
	add_child(bits)
	_end_burst.append(bits)
