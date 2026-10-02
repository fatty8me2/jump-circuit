class_name VoidCollapse
extends Node3D
## The Void's set piece: THE COLLAPSE. A stair of floating fragments climbs to the door in the sky,
## and the moment you set foot on its first step (`trigger_*`) the dream starts to come apart behind
## you: a wave runs up the stair at `speed` m/s (measured along the fragments, after `delay` s), and
## each fragment it reaches cracks and glows pink for `tell` s (at least 0.8) - still solid - then
## drops away into the void, tumbling and dissolving. A torn curtain of light marks the front, with
## a rumble that follows it. Outrun it.
## Everything after the trigger is a pure function of (Game.course_time - trigger time); a respawn
## re-arms it (reset_state), so every try is the same chase. Fragment tops are world positions.

const PINK := Color(1.0, 0.36, 0.72)
const CYAN := Color(0.32, 0.9, 1.0)
const FALL_G: float = 9.0

## Each: {"top": Vector3 (world, centre of its top), "size": Vector3, "yaw": float (deg)}.
@export var frags: Array[Dictionary] = []
@export var speed: float = 4.0
@export var delay: float = 1.4
@export var tell: float = 0.95
@export var trigger_pos: Vector3 = Vector3.ZERO
@export var trigger_size: Vector3 = Vector3(3, 3, 3)

var _t0: float = -1.0
var _bodies: Array[AnimatableBody3D] = []
var _shapes: Array[CollisionShape3D] = []
var _meshes: Array[Node3D] = []
var _mats: Array[ShaderMaterial] = []
var _dist: PackedFloat32Array = PackedFloat32Array()
var _state: PackedInt32Array = PackedInt32Array()   # 0 whole, 1 cracking, 2 fallen
var _crack_fx: Array[GPUParticles3D] = []
var _fall_fx: Array[GPUParticles3D] = []
var _front: Node3D
var _front_mat: StandardMaterial3D
var _front_fx: GPUParticles3D
var _rumble: AudioStreamPlayer3D


func _ready() -> void:
	add_to_group("resettable")
	var total: float = 0.0
	for i: int in frags.size():
		if i > 0:
			total += (frags[i]["top"] as Vector3).distance_to(frags[i - 1]["top"])
		_dist.append(total)
		_state.append(0)
		_build_fragment(frags[i])
	_build_front()
	var trig := Area3D.new()
	trig.collision_layer = 0
	trig.collision_mask = 2
	trig.monitorable = false
	var box := BoxShape3D.new()
	box.size = trigger_size
	var cs := CollisionShape3D.new()
	cs.shape = box
	trig.add_child(cs)
	trig.position = trigger_pos
	add_child(trig)
	trig.body_entered.connect(func(b: Node3D) -> void:
		if b is Player and _t0 < 0.0:
			_t0 = Game.course_time
			# SOUND: void_collapse_start - a deep tearing groan as the dream begins to come apart
			WorldAudio.at(self, "void_collapse_start", trigger_pos, 1.0, 60.0)
			WorldAudio.set_active(_rumble, true))
	# SOUND: void_collapse_rumble - the roar of the world falling apart, riding the wave front (loop)
	_rumble = WorldAudio.loop("void_collapse_rumble", _front, -4.0, 45.0, 8.0, false)


func is_running() -> bool:
	return _t0 >= 0.0


## Course time at which fragment `i` drops (INF before the trigger).
func fall_time(i: int) -> float:
	if _t0 < 0.0:
		return INF
	return _t0 + delay + _dist[i] / speed


func fragment_count() -> int:
	return frags.size()


func fragment_body(i: int) -> AnimatableBody3D:
	return _bodies[i]


func reset_state() -> void:
	_t0 = -1.0
	for i: int in _bodies.size():
		_state[i] = 0
		_shapes[i].set_deferred("disabled", false)
		_meshes[i].position = Vector3.ZERO
		_meshes[i].rotation = Vector3.ZERO
		_meshes[i].visible = true
		_mats[i].set_shader_parameter("crack", 0.0)
		_mats[i].set_shader_parameter("fade", 0.0)
		_crack_fx[i].emitting = false
	_front.visible = false
	_front_fx.emitting = false
	WorldAudio.set_active(_rumble, false)


func _physics_process(_dt: float) -> void:
	if _t0 < 0.0:
		return
	var now: float = Game.course_time
	for i: int in _bodies.size():
		if _state[i] < 2 and now >= fall_time(i):
			_state[i] = 2
			_shapes[i].set_deferred("disabled", true)


func _process(_dt: float) -> void:
	if _t0 < 0.0:
		return
	var now: float = Game.course_time
	var front_d: float = (now - _t0 - delay) * speed
	for i: int in _bodies.size():
		var ft: float = fall_time(i)
		var m: Node3D = _meshes[i]
		if now < ft - tell:
			continue
		if now < ft:
			# cracking: still solid, shaking harder and glowing hotter
			var k: float = clampf(1.0 - (ft - now) / tell, 0.0, 1.0)
			var amp: float = 0.02 + 0.06 * k
			m.position = Vector3(sin(now * 91.0 + float(i)) * amp, 0.0, cos(now * 77.0 + float(i)) * amp)
			_mats[i].set_shader_parameter("crack", k)
			if _state[i] == 0:
				_state[i] = 1
				_crack_fx[i].emitting = true
				# SOUND: void_fragment_crack - glass-and-stone cracking as a step starts to go (tell)
				if WorldAudio.once("void_fragment_crack", 0.25):
					WorldAudio.at(self, "void_fragment_crack", _bodies[i].global_position, 0.8, 30.0)
			continue
		# fallen: drops, tumbles and dissolves into the void
		var s: float = now - ft
		if s > 3.2:
			if m.visible:
				m.visible = false
				_crack_fx[i].emitting = false
			continue
		if _crack_fx[i].emitting and s > 0.0:
			_crack_fx[i].emitting = false
			_fall_fx[i].restart()
			# SOUND: void_fragment_fall - the step breaks away with a hollow crash
			if WorldAudio.once("void_fragment_fall", 0.2):
				WorldAudio.at(self, "void_fragment_fall", _bodies[i].global_position, 0.8, 34.0)
		m.position = Vector3(0, -0.5 * FALL_G * s * s, 0)
		m.rotation = Vector3(s * 0.9, s * 0.4, s * 0.7) * (1.0 if i % 2 == 0 else -1.0)
		_mats[i].set_shader_parameter("crack", 1.0)
		_mats[i].set_shader_parameter("fade", clampf(s / 3.0, 0.0, 1.0))
	# the torn curtain of light rides the wave front
	var shown: bool = front_d > -2.0 and front_d < _dist[_dist.size() - 1] + 4.0
	_front.visible = shown
	_front_fx.emitting = shown
	if shown:
		_front.global_position = _point_at(maxf(front_d, 0.0)) + Vector3(0, -0.5, 0)
		var ahead: Vector3 = _point_at(maxf(front_d, 0.0) + 1.0) - _point_at(maxf(front_d, 0.0))
		ahead.y = 0.0
		if ahead.length() > 0.01:
			_front.global_basis = Basis.looking_at(ahead.normalized(), Vector3.UP)
		_front_mat.albedo_color = Color(PINK.r, PINK.g, PINK.b, 0.35 + 0.15 * sin(now * 9.0))
	else:
		WorldAudio.set_active(_rumble, false)


## The point `d` m along the fragment path (clamped to its ends).
func _point_at(d: float) -> Vector3:
	if frags.is_empty():
		return global_position
	for i: int in range(1, _dist.size()):
		if d <= _dist[i]:
			var a: Vector3 = frags[i - 1]["top"]
			var b: Vector3 = frags[i]["top"]
			var seg: float = maxf(_dist[i] - _dist[i - 1], 0.001)
			return a.lerp(b, clampf((d - _dist[i - 1]) / seg, 0.0, 1.0))
	return frags[frags.size() - 1]["top"]


# ---- look -------------------------------------------------------------------------------------

func _build_fragment(f: Dictionary) -> void:
	var size: Vector3 = f["size"]
	var top: Vector3 = f["top"]
	var body := AnimatableBody3D.new()
	body.sync_to_physics = false
	body.collision_layer = 1
	body.collision_mask = 0
	var box := BoxShape3D.new()
	box.size = size
	var cs := CollisionShape3D.new()
	cs.shape = box
	body.add_child(cs)
	body.rotation_degrees.y = float(f.get("yaw", 0.0))
	body.position = top - Vector3(0, size.y * 0.5, 0)
	add_child(body)
	# the visible fragment: a slab with a jagged broken-off keel underneath, both cracking together
	var holder := Node3D.new()
	body.add_child(holder)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://visual/void_shard.gdshader")
	mat.set_shader_parameter("half_size", size * 0.5)
	var bm := BoxMesh.new()
	bm.size = size
	holder.add_child(Look.mesh_node(bm, mat))
	var keel := PrismMesh.new()
	keel.size = Vector3(size.x * 0.9, maxf(size.x, size.z) * 1.4, size.z * 0.9)
	var k := Look.mesh_node(keel, Look.flat(Color(0.82, 0.8, 0.9), 0.5), Vector3(0, -size.y * 0.5 - keel.size.y * 0.5, 0))
	k.rotation.z = PI
	holder.add_child(k)
	var hot: Color = Fx.hot(PINK, 2.2)
	var vis := AABB(-Vector3(3, 8, 3), Vector3(6, 12, 6))
	var crack: GPUParticles3D = Fx.emitter({"amount": 14, "lifetime": 0.6, "shape": "box", "extents": size * 0.5,
		"dir": Vector3.DOWN, "spread": 40.0, "speed": Vector2(0.3, 1.2), "gravity": Vector3(0, -5.0, 0),
		"tex": Fx.Tex.STAR, "size": 0.12, "color": hot, "curve": "shrink", "emitting": false, "aabb": vis})
	body.add_child(crack)
	var fall: GPUParticles3D = Fx.debris({"amount": 18, "chunk": 0.18, "color": Color(0.88, 0.86, 0.95),
		"speed": Vector2(1.0, 3.0), "gravity": Vector3(0, -9.0, 0), "lifetime": 1.4, "aabb": vis})
	body.add_child(fall)
	_bodies.append(body)
	_shapes.append(cs)
	_meshes.append(holder)
	_mats.append(mat)
	_crack_fx.append(crack)
	_fall_fx.append(fall)


func _build_front() -> void:
	_front = Node3D.new()
	_front.visible = false
	_front.top_level = true
	add_child(_front)
	_front_mat = StandardMaterial3D.new()
	_front_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_front_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_front_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_front_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_front_mat.albedo_color = Color(PINK.r, PINK.g, PINK.b, 0.4)
	_front_mat.albedo_texture = Fx.texture(Fx.Tex.SMOKE)
	# a ragged vertical curtain across the stair, hanging down into the dark below it
	for i: int in 3:
		var q := QuadMesh.new()
		q.size = Vector2(7.0 - float(i) * 1.5, 12.0)
		var c := Look.mesh_node(q, _front_mat, Vector3(0, -3.0 + float(i) * 0.8, 0.6 * float(i)))
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_front.add_child(c)
	_front_fx = Fx.emitter({"amount": 60, "lifetime": 1.6, "shape": "box", "extents": Vector3(3.0, 3.0, 0.4),
		"dir": Vector3.DOWN, "spread": 25.0, "speed": Vector2(1.0, 3.0), "gravity": Vector3(0, -4.0, 0),
		"facing": "mesh", "mesh": Fx.chunk_mesh(0.14), "color": Color(0.92, 0.9, 1.0), "scale": Vector2(0.5, 1.4),
		"angle": Vector2(0, 360), "spin": Vector2(-200, 200), "curve": "shrink", "emitting": false,
		"aabb": AABB(Vector3(-12, -20, -12), Vector3(24, 30, 24))})
	_front.add_child(_front_fx)
	var sparks: GPUParticles3D = Fx.emitter({"amount": 40, "lifetime": 0.9, "shape": "box", "extents": Vector3(3.0, 2.5, 0.3),
		"dir": Vector3.UP, "spread": 60.0, "speed": Vector2(0.5, 2.0), "tex": Fx.Tex.STAR, "size": 0.16,
		"pick": PackedColorArray([Fx.hot(PINK, 2.4), Fx.hot(CYAN, 2.2)]), "curve": "pop",
		"aabb": AABB(Vector3(-12, -20, -12), Vector3(24, 30, 24))})
	_front.add_child(sparks)
