class_name DinoRex
extends Node3D
## Dino Valley set piece: the T-REX CHASE. Step over the trigger line at the canyon mouth and the
## valley goes quiet; for `delay` s the ground shakes, dust sifts from the cliffs, pterosaurs burst
## into the sky and a bellowing ROAR rolls down the canyon - then the rex comes out of the haze
## behind you, thudding along the track at a speed that starts well under yours (`v_start`), builds
## (`accel`) and tops out at `v_max`, jaws wide, each footfall shaking the camera. Its bite reaches
## `reach` m ahead of its chest; whoever is inside it goes back to the checkpoint. When the track
## ends it slams to a halt against the sealed canyon gate and roars you off the course.
## Everything after the trigger is a pure function of (Game.course_time - trigger time); a respawn
## re-arms it (reset_state) so every try is the same chase. Positioned at the rex's FEET at its
## starting spot; `track` holds points (offsets from here) along the canyon floor, track[0] = ZERO.

@export var track: Array[Vector3] = []
@export var delay: float = 2.6
@export var v_start: float = 6.4
@export var accel: float = 0.8
@export var v_max: float = 8.6
@export var reach: float = 3.4
@export var bite_radius: float = 3.3
@export var creature_scale: float = 2.3
@export var trigger_pos: Vector3 = Vector3.ZERO
@export var trigger_size: Vector3 = Vector3(6, 3, 2)
## Metres the rex covers per stride cycle (one left and one right step).
@export var stride: float = 9.0

var _t0: float = -1.0
var _rex: DinoCreature
var _lens: PackedFloat32Array = PackedFloat32Array()
var _total: float = 0.0
var _kill_sent: bool = false
var _step_count: int = -1
var _dust: GPUParticles3D
var _quake: GPUParticles3D
var _flock: GPUParticles3D
var _roar_ring: GPUParticles3D
var _foot_fx: GPUParticles3D
var _stopped: bool = false
var _warned: bool = false
var _shake_t: float = 0.0
var _jaw_target: float = 0.0
var _bite_lamp: OmniLight3D
## Closest the mouth has come to the local player this chase (m; tests read it).
var min_gap: float = 999.0


func _ready() -> void:
	add_to_group("resettable")
	_lens.append(0.0)
	for i: int in range(1, track.size()):
		_total += track[i].distance_to(track[i - 1])
		_lens.append(_total)
	_build()
	var trig := Area3D.new()
	trig.collision_layer = 0
	trig.collision_mask = 2
	trig.monitorable = false
	var ts := BoxShape3D.new()
	ts.size = trigger_size
	var tcs := CollisionShape3D.new()
	tcs.shape = ts
	trig.add_child(tcs)
	trig.position = trigger_pos
	add_child(trig)
	trig.body_entered.connect(_on_trigger)
	reset_state()


func _build() -> void:
	_rex = DinoCreature.make("rex", creature_scale)
	_rex.heavy = 1.0
	_rex.top_level = true
	_rex.visible = false
	add_child(_rex)
	var big := AABB(Vector3(-80, -20, -80), Vector3(160, 60, 160))
	# the dust the rex kicks up along its run, and the quake of grit shaken from the cliffs
	_dust = Fx.smoke({"amount": 30, "lifetime": 1.6, "one_shot": false, "emitting": false, "shape": "sphere", "radius": 2.6,
		"dir": Vector3.UP, "spread": 60.0, "speed": Vector2(1.0, 4.0), "gravity": Vector3(0, 0.6, 0), "size": 3.0,
		"color": Color(0.78, 0.66, 0.46, 0.5), "aabb": big})
	_dust.top_level = true
	add_child(_dust)
	_quake = Fx.debris({"amount": 40, "lifetime": 1.4, "one_shot": false, "emitting": false, "explosiveness": 0.0,
		"shape": "box", "extents": Vector3(14, 0.3, 14), "dir": Vector3.DOWN, "spread": 10.0, "speed": Vector2(0.5, 2.0),
		"color": Color(0.55, 0.46, 0.34), "chunk": 0.16, "aabb": big})
	_quake.top_level = true
	add_child(_quake)
	# the flock of pterosaurs that bursts from the cliffs at the roar
	_flock = Fx.emitter({"amount": 26, "lifetime": 3.5, "one_shot": true, "emitting": false, "explosiveness": 0.7,
		"shape": "box", "extents": Vector3(8, 1, 8), "dir": Vector3(0, 0.6, -1), "spread": 40.0, "speed": Vector2(7.0, 12.0),
		"gravity": Vector3(0, 0.5, 0), "tex": Fx.Tex.PETAL, "additive": false, "size": 0.9, "angle": Vector2(0, 360),
		"spin": Vector2(-700, 700), "color": Color(0.16, 0.1, 0.08, 0.95), "fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]), "aabb": big})
	_flock.top_level = true
	add_child(_flock)
	_roar_ring = Fx.shockwave(10.0, {"color": Color(1.0, 0.9, 0.7, 0.6), "lifetime": 1.0})
	_roar_ring.top_level = true
	add_child(_roar_ring)
	_foot_fx = Fx.smoke({"amount": 16, "lifetime": 1.0, "one_shot": true, "emitting": false, "explosiveness": 0.9, "shape": "sphere",
		"radius": 1.2, "dir": Vector3.UP, "spread": 80.0, "speed": Vector2(2.0, 5.0), "size": 2.0,
		"color": Color(0.8, 0.7, 0.5, 0.6), "aabb": big})
	_foot_fx.top_level = true
	add_child(_foot_fx)
	_bite_lamp = OmniLight3D.new()
	_bite_lamp.light_color = Color(1.0, 0.45, 0.2)
	_bite_lamp.omni_range = 12.0
	_bite_lamp.light_energy = 0.0
	_bite_lamp.shadow_enabled = false
	_bite_lamp.top_level = true
	add_child(_bite_lamp)


func _on_trigger(body: Node3D) -> void:
	if body is Player and _t0 < 0.0:
		_t0 = Game.course_time
		_rex.visible = false
		# SOUND: dino_rex_roar - the rex's first bellow down the canyon (the audible tell)
		WorldAudio.at(self, "dino_rex_roar", global_position + Vector3(0, 4.0, 0), 1.0, 160.0, 0.0)
		_quake.global_position = body.global_position + Vector3(0, 9.0, 0)
		_quake.emitting = true
		_flock.global_position = global_position + Vector3(0, 8.0, 0)
		_flock.restart()
		_flock.emitting = true
		_shake(0.5, true)


func reset_state() -> void:
	_t0 = -1.0
	_kill_sent = false
	_stopped = false
	_step_count = -1
	_warned = false
	_jaw_target = 0.0
	min_gap = 999.0
	if _rex != null:
		_rex.visible = false
		_dust.emitting = false
		_quake.emitting = false
		_bite_lamp.light_energy = 0.0


func is_armed() -> bool:
	return _t0 < 0.0


## Seconds since the trigger (-1 while armed).
func elapsed() -> float:
	return -1.0 if _t0 < 0.0 else Game.course_time - _t0


## Distance the rex's feet have covered along the track `e` s after the trigger.
func dist_at(e: float) -> float:
	var tau: float = e - delay
	if tau <= 0.0:
		return 0.0
	var t_cap: float = maxf(v_max - v_start, 0.0) / maxf(accel, 0.001)
	var s: float = 0.0
	if tau < t_cap:
		s = v_start * tau + 0.5 * accel * tau * tau
	else:
		s = v_start * t_cap + 0.5 * accel * t_cap * t_cap + v_max * (tau - t_cap)
	return minf(s, _total)


func speed_at(e: float) -> float:
	var tau: float = e - delay
	if tau <= 0.0 or dist_at(e) >= _total:
		return 0.0
	return minf(v_start + accel * tau, v_max)


## Seconds after the trigger at which the rex's feet reach `s` metres along the track.
func time_at_distance(s: float) -> float:
	var lo: float = 0.0
	var hi: float = 120.0
	for i: int in 40:
		var mid: float = (lo + hi) * 0.5
		if dist_at(mid) < s:
			lo = mid
		else:
			hi = mid
	return hi


func _along(s: float) -> Array:
	for i: int in range(1, track.size()):
		if s <= _lens[i] or i == track.size() - 1:
			var seg: float = _lens[i] - _lens[i - 1]
			var k: float = (s - _lens[i - 1]) / maxf(seg, 0.001)
			var dir: Vector3 = (track[i] - track[i - 1]).normalized()
			return [track[i - 1].lerp(track[i], clampf(k, 0.0, 1.0)), dir]
	return [Vector3.ZERO, Vector3.FORWARD]


## Distance along the track of the point nearest `local_p` (a local point).
func track_distance(local_p: Vector3) -> float:
	var best: float = INF
	var best_s: float = 0.0
	for i: int in range(1, track.size()):
		var a: Vector3 = track[i - 1]
		var b: Vector3 = track[i]
		var ab: Vector3 = b - a
		var k: float = clampf((local_p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var d: float = (a + ab * k).distance_to(local_p)
		if d < best:
			best = d
			best_s = _lens[i - 1] + ab.length() * k
	return best_s


## Seconds after the trigger until the rex has run the whole track.
func run_time() -> float:
	return time_at_distance(_total)


func _physics_process(dt: float) -> void:
	var e: float = elapsed()
	if e < 0.0:
		return
	if e < delay:
		# the valley holds its breath: tremors rise toward the first footfall
		_shake_t -= dt
		if _shake_t <= 0.0:
			_shake_t = 0.28
			_shake(0.1 + 0.25 * (e / delay), true)
		return
	_rex.visible = true
	var s: float = dist_at(e)
	var seg: Array = _along(s)
	var pos: Vector3 = seg[0]
	var dir: Vector3 = seg[1]
	var flat: Vector3 = Vector3(dir.x, 0, dir.z)
	if flat.length() > 0.01:
		flat = flat.normalized()
		_rex.global_basis = Basis.looking_at(flat, Vector3.UP)
	_rex.global_position = global_position + pos
	var moving: bool = speed_at(e) > 0.1
	_rex.amount = 1.0 if moving else 0.0
	_rex.gait = s / stride * TAU
	_dust.emitting = moving
	_dust.global_position = global_position + pos + Vector3(0, 0.4, 0)
	# a footfall every half stride: the ground thumps
	var step: int = int(floor(s / stride * 2.0))
	if step != _step_count and moving:
		if _step_count >= 0:
			_foot_fx.global_position = global_position + pos + Vector3(0, 0.3, 0)
			_foot_fx.restart()
			_foot_fx.emitting = true
			WorldAudio.at(self, "dino_rex_step", global_position + pos, 1.0, 90.0)
			_shake(0.2, false)
		_step_count = step
	# the mouth: jaws open as the bite closes in
	var mouth: Vector3 = _mouth()
	var pl: Node3D = WorldAudio.local_player(self)
	var gap: float = 99.0
	if pl != null:
		gap = mouth.distance_to(pl.global_position + Vector3(0, 0.9, 0))
	if moving:
		min_gap = minf(min_gap, gap)
	_jaw_target = clampf((14.0 - gap) / 8.0, 0.0, 1.0) if moving else 0.5
	_rex.jaw = lerpf(_rex.jaw, _jaw_target, 1.0 - exp(-8.0 * dt))
	_bite_lamp.global_position = mouth
	_bite_lamp.light_energy = clampf((16.0 - gap) / 16.0, 0.0, 1.0) * 2.0
	if gap < 14.0 and not _warned:
		_warned = true
		WorldAudio.at(self, "dino_rex_snarl", mouth, 1.0, 60.0)
	if not moving and s >= _total and not _stopped:
		_stopped = true
		_shake(0.7, true)
		_roar_ring.global_position = mouth
		_roar_ring.restart()
		WorldAudio.at(self, "dino_rex_roar", mouth, 1.0, 160.0, 0.0)
	if pl != null and gap < bite_radius and not _kill_sent and moving:
		_kill_sent = true
		_rex.jaw = 1.0
		WorldAudio.at(self, "dino_rex_chomp", mouth, 1.0, 60.0)
		_shake(0.8, true)
		KitUtil.kill(self, "hazard")


## The point just in front of the rex's chest where its jaws close (world).
func _mouth() -> Vector3:
	var fwd: Vector3 = -_rex.global_basis.z
	return _rex.global_position + fwd * (reach + 0.4) + Vector3(0, creature_scale * 1.55, 0)


func _shake(amount: float, wide: bool) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null or not cam.has_method("add_trauma"):
		return
	var dist: float = cam.global_position.distance_to(_rex.global_position if _rex.visible else global_position)
	var k: float = 1.0 if wide else clampf(1.0 - (dist - 8.0) / 60.0, 0.0, 1.0)
	if k > 0.0:
		cam.call("add_trauma", amount * k)
