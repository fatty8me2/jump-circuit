class_name DoomAlarm
extends Node3D
## Doom Fortress: an ALARM CYCLE that changes the state of a whole hall on a klaxon. Each cycle is
## SAFE for `period - lock` seconds, then LOCKDOWN for `lock` seconds: every registered floor GRATE
## is electrified (back to the checkpoint if you are on it) and the hall's laser fences come on
## (build them with laser_phase() so they switch with it). The tell: `warn` seconds before each
## lockdown the klaxon sounds, every beacon in the hall spins up and flares, and the grates start to
## pulse red; the all-clear rings when it ends. The raised posts between grates are never powered.
## A pure function of Game.course_time. Add the alarm node to the level at the hall's centre (the
## klaxon sounds from there) first, then register grates and beacons.

@export var period: float = 7.2
@export var phase: float = 0.0
## Seconds of lockdown at the end of each cycle.
@export var lock: float = 2.2
## Seconds of klaxon before each lockdown.
@export var warn: float = 1.2

## {"xf": Transform3D (world, at the grate's top centre), "half": Vector2, "mat": StandardMaterial3D,
##  "fx": GPUParticles3D, "hum": AudioStreamPlayer3D}
var _grates: Array[Dictionary] = []
## {"spin": Node3D, "mat": StandardMaterial3D, "light": OmniLight3D}
var _beacons: Array[Dictionary] = []
var _hot: StandardMaterial3D
var _warm: StandardMaterial3D
var _cold: StandardMaterial3D
var _warned: int = -999
var _locked_cycle: int = -999
var _was_locked: bool = false
var _hit_tick: int = -100


func _ready() -> void:
	_hot = Look.flat(Color(1.0, 0.2, 0.08), 0.3, 0.0, 3.5)
	_warm = Look.flat(Color(0.7, 0.1, 0.05), 0.4, 0.0, 1.2)
	_cold = Look.flat(Color(0.12, 0.11, 0.11), 0.5, 0.6)
	add_to_group("course_clock")


func _s(time: float) -> float:
	return fposmod(time / maxf(period, 0.01) + phase, 1.0) * period


func _cycle(time: float) -> int:
	return int(floor(time / maxf(period, 0.01) + phase))


func is_locked_at(time: float) -> bool:
	return _s(time) >= period - lock


func is_warning_at(time: float) -> bool:
	var s: float = _s(time)
	return s >= period - lock - warn and s < period - lock


## Seconds from `time` until the next lockdown starts (0 while locked).
func time_until_lock(time: float) -> float:
	var s: float = _s(time)
	return 0.0 if s >= period - lock else period - lock - s


## No lockdown at any point of [now + a, now + b].
func safe_for(a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if is_locked_at(Game.course_time + s):
			return false
		s += 0.04
	return true


## The `phase` to give a kit.laser (period = this period, on_fraction = lock / period) so that its
## beam is on exactly during lockdown.
func laser_phase() -> float:
	return fposmod(phase + lock / period, 1.0)


func snap_to_clock() -> void:
	pass


## An electrified floor grate laid over a walkable surface: `top` is the surface's top centre
## (world), `size` its x/z extent in the grate's own frame, turned by `yaw_deg`.
func add_grate(top: Vector3, size: Vector2, yaw_deg: float = 0.0) -> void:
	var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), top)
	var n := Node3D.new()
	n.transform = global_transform.affine_inverse() * xf
	add_child(n)
	var mat: StandardMaterial3D = _cold if _cold != null else Look.flat(Color(0.12, 0.11, 0.11), 0.5, 0.6)
	var bars: int = int(size.y / 0.5)
	var meshes: Array[MeshInstance3D] = []
	for i: int in bars:
		var z: float = -size.y * 0.5 + (float(i) + 0.5) * size.y / float(bars)
		var bar := Look.box(Vector3(size.x * 0.94, 0.04, 0.12), mat, Vector3(0, 0.025, z))
		bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(bar)
		meshes.append(bar)
	for sx: float in [-1.0, 1.0]:
		var rail := Look.box(Vector3(0.1, 0.06, size.y), DoomDecor.iron(), Vector3(sx * size.x * 0.48, 0.03, 0))
		n.add_child(rail)
	var fx: GPUParticles3D = Fx.emitter({"amount": clampi(int(size.x * size.y * 2.5), 10, 50), "lifetime": 0.25,
		"emitting": false, "shape": "box", "extents": Vector3(size.x * 0.45, 0.02, size.y * 0.45),
		"dir": Vector3.UP, "spread": 80.0, "speed": Vector2(1.0, 3.5), "gravity": Vector3(0, -8.0, 0),
		"facing": "velocity", "tex": Fx.Tex.SPARK, "size": Vector2(0.03, 0.3), "color": Color(3.0, 1.6, 1.2),
		"aabb": AABB(Vector3(-size.x, -1, -size.y), Vector3(size.x * 2.0, 4, size.y * 2.0))})
	fx.position = Vector3(0, 0.05, 0)
	n.add_child(fx)
	# SOUND: doom_grate_buzz - the electrified grating crackling (loop, while locked down)
	var hum: AudioStreamPlayer3D = WorldAudio.loop("doom_grate_buzz", n, -8.0, 22.0, 4.0, false)
	_grates.append({"xf": xf, "half": size * 0.5, "bars": meshes, "fx": fx, "hum": hum})


## A beacon the alarm drives: `spin` turns faster and `mat` flares during the warning and lockdown.
func add_beacon(spin: Node3D, mat: StandardMaterial3D, light: OmniLight3D = null) -> void:
	_beacons.append({"spin": spin, "mat": mat, "light": light})


func _physics_process(_dt: float) -> void:
	if not is_locked_at(Game.course_time):
		return
	var pl: Node3D = WorldAudio.local_player(self)
	if pl == null:
		return
	for g: Dictionary in _grates:
		var p: Vector3 = (g["xf"] as Transform3D).affine_inverse() * pl.global_position
		var h: Vector2 = g["half"]
		if absf(p.x) < h.x and absf(p.z) < h.y and p.y > -0.3 and p.y < 0.6:
			var tick: int = Engine.get_physics_frames()
			if tick - _hit_tick > 30:
				_hit_tick = tick
				var n: Node = self
				while n != null and not n.has_method("fail"):
					n = n.get_parent()
				if n != null:
					n.call_deferred("fail", "hazard")
			return


func _process(dt: float) -> void:
	var t: float = Game.course_time
	var cyc: int = _cycle(t)
	var locked: bool = is_locked_at(t)
	var warning: bool = is_warning_at(t)
	var mat: StandardMaterial3D = _cold
	if locked:
		mat = _hot
	elif warning:
		mat = _warm if fmod(t, 0.3) < 0.15 else _cold
	for g: Dictionary in _grates:
		for b: MeshInstance3D in (g["bars"] as Array):
			if b.material_override != mat:
				b.material_override = mat
		(g["fx"] as GPUParticles3D).emitting = locked
		WorldAudio.set_active(g["hum"], locked)
	var rate: float = 6.0 if (locked or warning) else 0.8
	for bc: Dictionary in _beacons:
		(bc["spin"] as Node3D).rotate_object_local(Vector3.UP, dt * TAU / maxf(1.0 / rate, 0.05))
		(bc["mat"] as StandardMaterial3D).emission_energy_multiplier = 4.5 if (locked or warning) else 1.2
		var l: OmniLight3D = bc["light"]
		if l != null:
			l.light_energy = (3.0 if fmod(t, 0.5) < 0.25 else 1.6) if (locked or warning) else 0.5
	if warning and cyc != _warned:
		_warned = cyc
		# SOUND: doom_klaxon - the lockdown klaxon (the ~1.2 s warning before the grates go live)
		WorldAudio.at(self, "doom_klaxon", global_position, 1.0, 60.0)
	if locked and cyc != _locked_cycle:
		_locked_cycle = cyc
		# SOUND: doom_lockdown - the grates slamming live with a heavy electrical thump
		WorldAudio.at(self, "doom_lockdown", global_position, 1.0, 50.0)
	if _was_locked and not locked:
		# SOUND: doom_alarm_clear - the all-clear chime as the power drops out of the grates
		WorldAudio.at(self, "doom_alarm_clear", global_position, 0.8, 50.0)
	_was_locked = locked
