class_name DesertBoulder
extends Node3D
## Scarab Sands set piece: the boulder run. A colossal carved stone ball waits in a hatch in
## the ceiling. Step on the sun plate (`trigger_*`) and the hatch grinds open: after `delay`
## the ball drops onto the track behind you and rolls down it, gathering speed (from
## `v_start` at `accel` up to `v_max`), crushing anything it touches, until it runs off the
## end of the track into the pit and smashes. Everything after the trigger is a pure function
## of (Game.course_time - trigger time); a respawn re-arms it (reset_state), so every try is
## the same chase. Positioned at the ball's centre in the hatch; `track` holds ball-centre
## points (offsets from here), track[0] being where it lands.

@export var radius: float = 2.4
@export var track: Array[Vector3] = []
@export var delay: float = 0.6
@export var v_start: float = 4.0
@export var accel: float = 7.0
@export var v_max: float = 11.0
@export var trigger_pos: Vector3 = Vector3.ZERO
@export var trigger_size: Vector3 = Vector3(4, 3, 2)

## Seconds it keeps falling after leaving the track before it smashes (and is gone).
@export var pit_time: float = 1.1

const GRAVITY: float = 30.0

var _t0: float = -1.0
var _ball: Node3D
var _kill: Area3D
var _trail: GPUParticles3D
var _pebbles: GPUParticles3D
var _hatch_dust: GPUParticles3D
var _land_fx: Array[GPUParticles3D] = []
var _crash_fx: Array[GPUParticles3D] = []
var _loop: AudioStreamPlayer3D
var _lens: PackedFloat32Array = PackedFloat32Array()
var _total: float = 0.0
var _landed: bool = false
var _crashed: bool = false
var _smashed: bool = false
var _prev: Vector3 = Vector3.ZERO
var _shake_t: float = 0.0
## Seconds from landing until it rolls off the end of the track.
var _t_end: float = 0.0


func _ready() -> void:
	add_to_group("resettable")
	_lens.append(0.0)
	for i: int in range(1, track.size()):
		_total += track[i].distance_to(track[i - 1])
		_lens.append(_total)
	_t_end = _time_at(_total)
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
	_loop = WorldAudio.loop("boulder_roll", _ball, 0.0, 45.0, 8.0, false)
	reset_state()


func _build() -> void:
	_ball = Node3D.new()
	add_child(_ball)
	var rock := ShaderMaterial.new()
	rock.shader = preload("res://visual/desert_wall.gdshader")
	rock.set_shader_parameter("stone", Color(0.72, 0.55, 0.36))
	rock.set_shader_parameter("block", Vector2(1.6, 0.8))
	rock.set_shader_parameter("glyph_lo", -radius * 0.45)
	rock.set_shader_parameter("glyph_hi", radius * 0.45)
	rock.set_shader_parameter("glyph_cell", 0.8)
	rock.set_shader_parameter("inlay_glow", 0.6)
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 28
	sm.rings = 14
	var spin := Node3D.new()
	spin.name = "Roll"
	_ball.add_child(spin)
	spin.add_child(Look.mesh_node(sm, rock))
	# gold bands so the roll reads, and a turquoise scarab boss on each side
	for rot: Vector3 in [Vector3(0, 0, PI * 0.5), Vector3(0, PI * 0.5, PI * 0.5)]:
		var tm := TorusMesh.new()
		tm.inner_radius = radius * 0.98
		tm.outer_radius = radius * 1.05
		tm.rings = 40
		tm.ring_segments = 6
		var band := Look.mesh_node(tm, Look.flat(Color(1.0, 0.72, 0.22), 0.3, 0.85, 0.5))
		band.rotation = rot
		spin.add_child(band)
	for sx: float in [-1.0, 1.0]:
		var boss := Look.cylinder(radius * 0.32, 0.3, Look.flat(Color(0.15, 0.8, 0.78), 0.3, 0.2, 1.2), Vector3(sx * radius * 0.97, 0, 0), -1.0, 16)
		boss.rotation.z = PI * 0.5
		spin.add_child(boss)
	var kill_shape := SphereShape3D.new()
	kill_shape.radius = radius * 0.92
	_kill = Area3D.new()
	_kill.collision_layer = 0
	_kill.collision_mask = 2
	_kill.monitorable = false
	var kcs := CollisionShape3D.new()
	kcs.shape = kill_shape
	_kill.add_child(kcs)
	_ball.add_child(_kill)
	var big := AABB(Vector3(-60, -30, -60), Vector3(120, 60, 120))
	# the trail of dust it throws up behind it and pebbles skittering ahead
	_trail = Fx.emitter({"amount": 60, "lifetime": 1.6, "emitting": false, "shape": "sphere", "radius": radius * 0.6,
		"dir": Vector3.UP, "spread": 60.0, "speed": Vector2(1.0, 3.0), "gravity": Vector3(0, 0.3, 0),
		"tex": Fx.Tex.SMOKE, "additive": false, "size": 2.4, "curve": "puff", "angle": Vector2(0, 360),
		"spin": Vector2(-40, 40), "color": Color(0.92, 0.75, 0.5, 0.55), "fade": PackedFloat32Array([0.0, 0.9, 0.0]), "aabb": big})
	_trail.top_level = true
	add_child(_trail)
	_pebbles = Fx.debris({"amount": 24, "lifetime": 0.8, "one_shot": false, "emitting": false, "explosiveness": 0.0,
		"shape": "sphere", "radius": radius * 0.5, "dir": Vector3.UP, "spread": 70.0, "speed": Vector2(2.0, 6.0),
		"color": Color(0.7, 0.52, 0.34), "chunk": 0.18, "aabb": big})
	_pebbles.top_level = true
	add_child(_pebbles)
	_hatch_dust = Fx.emitter({"amount": 30, "lifetime": 1.0, "emitting": false, "shape": "sphere", "radius": radius,
		"dir": Vector3.DOWN, "spread": 25.0, "speed": Vector2(1.0, 3.0), "gravity": Vector3(0, -8, 0), "additive": false,
		"size": 0.1, "color": Color(0.9, 0.72, 0.45), "fade": PackedFloat32Array([1.0, 1.0, 0.0]), "aabb": big})
	add_child(_hatch_dust)
	for i: int in 2:
		var land: GPUParticles3D = DesertFx.sand_burst(self, Vector3.ZERO, radius, 40, 7.0)
		land.top_level = true
		_land_fx.append(land)
	_land_fx.append(Fx.debris({"amount": 30, "shape": "sphere", "radius": radius, "speed": Vector2(3.0, 8.0), "spread": 80.0,
		"color": Color(0.72, 0.55, 0.36), "chunk": 0.3, "aabb": big}))
	_land_fx[2].top_level = true
	add_child(_land_fx[2])
	for i: int in 3:
		var c: GPUParticles3D = DesertFx.sand_burst(self, Vector3.ZERO, radius * 1.3, 60, 10.0)
		c.top_level = true
		c.lifetime = 2.2
		_crash_fx.append(c)
	_crash_fx.append(Fx.debris({"amount": 50, "shape": "sphere", "radius": radius, "speed": Vector2(4.0, 12.0), "spread": 70.0,
		"color": Color(0.72, 0.55, 0.36), "chunk": 0.45, "lifetime": 1.6, "aabb": big}))
	_crash_fx[3].top_level = true
	add_child(_crash_fx[3])


func _on_trigger(body: Node3D) -> void:
	if body is Player and _t0 < 0.0:
		_t0 = Game.course_time
		_landed = false
		_crashed = false
		_hatch_dust.emitting = true
		WorldAudio.at(self, "stone_grind", global_position, 1.0, 50.0)


func reset_state() -> void:
	_t0 = -1.0
	_landed = false
	_crashed = false
	_smashed = false
	_ball.visible = true
	_ball.position = Vector3.ZERO
	_ball.reset_physics_interpolation()
	_trail.emitting = false
	_pebbles.emitting = false
	_hatch_dust.emitting = false
	WorldAudio.set_active(_loop, false)


func is_armed() -> bool:
	return _t0 < 0.0


## Seconds since the trigger (-1 while armed).
func elapsed() -> float:
	return -1.0 if _t0 < 0.0 else Game.course_time - _t0


func _drop_time() -> float:
	if track.is_empty():
		return 0.0
	return sqrt(2.0 * maxf(-track[0].y, 0.01) / GRAVITY)


## Distance rolled along the track `tau` seconds after landing, and the speed then.
func _roll(tau: float) -> Vector2:
	var t_cap: float = (v_max - v_start) / accel
	if tau < t_cap:
		return Vector2(v_start * tau + 0.5 * accel * tau * tau, v_start + accel * tau)
	var s_cap: float = v_start * t_cap + 0.5 * accel * t_cap * t_cap
	return Vector2(s_cap + v_max * (tau - t_cap), v_max)


## Ball-centre point `s` metres along the track (local), and the direction there.
func _along(s: float) -> Array:
	for i: int in range(1, track.size()):
		if s <= _lens[i] or i == track.size() - 1:
			var seg: float = _lens[i] - _lens[i - 1]
			var k: float = (s - _lens[i - 1]) / maxf(seg, 0.001)
			var dir: Vector3 = (track[i] - track[i - 1]).normalized()
			return [track[i - 1].lerp(track[i], minf(k, 1.0)), dir]
	return [track[0], Vector3.FORWARD]


## Ball centre (local) `e` seconds after the trigger; w = 0 hidden, 1 visible.
func position_at(e: float) -> Vector3:
	if e < 0.0 or track.is_empty():
		return Vector3.ZERO
	if e < delay:
		return Vector3(sin(e * 70.0), 0, cos(e * 53.0)) * 0.06 * (e / delay)
	var d: float = e - delay
	var td: float = _drop_time()
	if d < td:
		return Vector3.ZERO.lerp(track[0], (0.5 * GRAVITY * d * d) / maxf(-track[0].y, 0.01))
	var r: Vector2 = _roll(d - td)
	if r.x <= _total:
		return _along(r.x)[0]
	# off the end: carry on at the end speed and fall into the pit
	var over: float = d - td - _t_end
	var last: Array = _along(_total)
	var p: Vector3 = last[0] + (last[1] as Vector3) * _roll(_t_end).y * over
	p.y -= 0.5 * GRAVITY * over * over
	return p


## Seconds after landing at which the ball has rolled `s` metres.
func _time_at(s: float) -> float:
	var lo: float = 0.0
	var hi: float = 60.0
	for i: int in 40:
		var mid: float = (lo + hi) * 0.5
		if _roll(mid).x < s:
			lo = mid
		else:
			hi = mid
	return hi


## Seconds after the trigger at which the ball leaves the track (for bots and tuning).
func run_time() -> float:
	return delay + _drop_time() + _t_end


func _physics_process(dt: float) -> void:
	var e: float = elapsed()
	if e < 0.0:
		return
	var d: float = e - delay
	var td: float = _drop_time()
	var gone: bool = d > td + _t_end + pit_time
	if gone:
		if not _crashed:
			_crashed = true
			_ball.visible = false
			_trail.emitting = false
			_pebbles.emitting = false
			WorldAudio.set_active(_loop, false)
		return
	_ball.position = position_at(e)
	if d > td and not _landed:
		_landed = true
		_hatch_dust.emitting = false
		for p: GPUParticles3D in _land_fx:
			p.global_position = _ball.global_position - Vector3(0, radius * 0.8, 0)
			p.restart()
		WorldAudio.at(self, "boulder_impact", _ball.global_position, 1.0, 60.0)
		_shake(0.6)
	var rolling: bool = d > td and d < td + _t_end
	_trail.emitting = rolling
	_pebbles.emitting = rolling
	WorldAudio.set_active(_loop, rolling)
	if rolling:
		_trail.global_position = _ball.global_position - Vector3(0, radius * 0.7, 0)
		_pebbles.global_position = _ball.global_position - Vector3(0, radius * 0.8, 0)
		_shake_t -= dt
		if _shake_t <= 0.0:
			_shake_t = 0.2
			_shake(0.12)
	if d > td + _t_end + pit_time - 0.1 and not _smashed:
		_smashed = true
		for p: GPUParticles3D in _crash_fx:
			p.global_position = _ball.global_position
			p.restart()
		WorldAudio.at(self, "boulder_impact", _ball.global_position, 1.0, 80.0, 0.1)
		_shake(0.5)
	if e > delay:
		for body: Node3D in _kill.get_overlapping_bodies():
			if body is Player:
				var n: Node = self
				while n != null and not n.has_method("fail"):
					n = n.get_parent()
				if n != null:
					n.call_deferred("fail", "hazard")
				return


func _process(dt: float) -> void:
	if _t0 < 0.0 or not _ball.visible:
		_prev = _ball.global_position
		return
	var now: Vector3 = _ball.global_position
	var step: Vector3 = now - _prev
	step.y = 0.0
	_prev = now
	if step.length() > 0.0005 and step.length() < 5.0:
		var axis: Vector3 = Vector3.UP.cross(step.normalized()).normalized()
		var roll := _ball.get_node("Roll") as Node3D
		roll.global_basis = Basis(axis, step.length() / radius) * roll.global_basis


## Shake the camera, scaled by how close the ball is to it.
func _shake(amount: float) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null or not cam.has_method("add_trauma"):
		return
	var dist: float = cam.global_position.distance_to(_ball.global_position)
	var k: float = clampf(1.0 - (dist - 6.0) / 40.0, 0.0, 1.0)
	if k > 0.0:
		cam.call("add_trauma", amount * k)
