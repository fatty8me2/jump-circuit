class_name ReefSurge
extends Area3D
## Coral Depths: a TIDAL SURGE - a current that comes and goes on a fixed rhythm
## (Game.course_time). Most of the cycle the channel is slack; then the surge builds,
## rushes through at full strength and eases off. It only really moves you in the air
## (ground friction beats it), so it is a timing hazard for jumps across it - and a
## free ride for a jump WITH it. A telegraph runs `warn` seconds ahead: sand lifts,
## bubbles start streaming and the kelp in the channel leans into the coming push.
## Centre position; `push` is the peak acceleration in the node's local axes.

@export var size: Vector3 = Vector3(12, 8, 30)
@export var push: Vector3 = Vector3(24, 0, 0)
@export var period: float = 4.5
## Part of the cycle the surge runs (build + full + ease).
@export var surge_fraction: float = 0.42
@export var phase: float = 0.0
@export var warn: float = 0.8
## Kelp ribbons planted along the channel edges (visual only).
@export var kelp: int = 10

var _streaks: GPUParticles3D
var _silt: GPUParticles3D
var _kelp: Array[Node3D] = []


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitorable = false
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	add_child(cs)
	_build_visual()
	_apply(Game.course_time)


## 0 (slack) .. 1 (full surge) at `time`.
func strength_at(time: float) -> float:
	var u: float = fposmod(time / period + phase, 1.0)
	if u >= surge_fraction:
		return 0.0
	var k: float = u / surge_fraction
	return smoothstep(0.0, 0.22, k) * (1.0 - smoothstep(0.78, 1.0, k))


## True when the channel stays slack (strength below 3 %) for the next `window` seconds.
func is_calm_for(time: float, window: float) -> bool:
	var s: float = 0.0
	while s <= window:
		if strength_at(time + s) > 0.03:
			return false
		s += 0.05
	return true


## Seconds until the next surge starts building (0 while it runs).
func time_until_surge(time: float) -> float:
	var u: float = fposmod(time / period + phase, 1.0)
	return 0.0 if u < surge_fraction else (1.0 - u) * period


## Visual strength: the real one, plus the telegraph ramp before it.
func _look_at_time(t: float) -> float:
	var s: float = strength_at(t)
	var until: float = time_until_surge(t)
	if until > 0.0 and until < warn:
		s = maxf(s, 0.35 * (1.0 - until / warn))
	return s


func _physics_process(dt: float) -> void:
	var t: float = Game.course_time
	_apply(t)
	var s: float = strength_at(t)
	if s <= 0.0:
		return
	for body: Node3D in get_overlapping_bodies():
		if body is Player:
			(body as Player).add_impulse(global_basis * push * s * dt)


func _apply(t: float) -> void:
	var v: float = _look_at_time(t)
	_streaks.amount_ratio = 0.06 + 0.94 * v
	_streaks.speed_scale = 0.5 + 1.3 * v
	_silt.amount_ratio = 0.15 + 0.85 * v
	var lean: float = v * 0.55
	var dir: Vector3 = push.normalized()
	for i: int in _kelp.size():
		var k: Node3D = _kelp[i]
		var wob: float = sin(t * 2.2 + float(i) * 1.3) * (0.06 + 0.1 * v)
		# lean toward the push: rotate about the horizontal axis square to it
		k.rotation = Vector3(dir.z * (lean + wob), 0.0, -dir.x * (lean + wob))


func _build_visual() -> void:
	var along: Vector3 = push.normalized()
	var axis: Vector3 = along.abs()
	var span: float = maxf(absf(size.dot(axis)), 1.0)
	# current streaks, thick when it surges
	_streaks = GPUParticles3D.new()
	_streaks.amount = Fx.count(int(clampf(size.x * size.y * size.z * 0.05, 40, 160)))
	_streaks.lifetime = span / 14.0
	_streaks.preprocess = _streaks.lifetime
	_streaks.local_coords = true
	_streaks.visibility_aabb = AABB(-size, size * 2.0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = size * 0.5 * (Vector3.ONE - axis) + axis * 0.2
	pm.emission_shape_offset = -along * span * 0.5
	pm.direction = along
	pm.spread = 4.0
	pm.initial_velocity_min = 11.0
	pm.initial_velocity_max = 15.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	pm.particle_flag_align_y = true
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.12, 0.8, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(0.8, 1, 1, 1), Color(0.8, 1, 1, 1), Color(1, 1, 1, 0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	_streaks.process_material = pm
	var m := BoxMesh.new()
	m.size = Vector3(0.05, 1.4, 0.05)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.vertex_color_use_as_albedo = true
	qm.albedo_color = Color(0.85, 1.0, 1.0, 0.4)
	m.material = qm
	_streaks.draw_pass_1 = m
	add_child(_streaks)
	# silt and bubbles tumbling along with it
	_silt = GPUParticles3D.new()
	_silt.amount = Fx.count(int(clampf(size.x * size.z * 0.12, 24, 90)))
	_silt.lifetime = span / 8.0
	_silt.preprocess = _silt.lifetime
	_silt.local_coords = true
	_silt.visibility_aabb = AABB(-size, size * 2.0)
	var sm := ParticleProcessMaterial.new()
	sm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	sm.emission_box_extents = size * 0.5 * (Vector3.ONE - axis) + axis * 0.2
	sm.emission_shape_offset = -along * span * 0.5
	sm.direction = along + Vector3(0, 0.15, 0)
	sm.spread = 12.0
	sm.initial_velocity_min = 6.0
	sm.initial_velocity_max = 9.0
	sm.gravity = Vector3(0, 0.3, 0)
	sm.turbulence_enabled = true
	sm.turbulence_noise_strength = 1.0
	sm.turbulence_noise_scale = 3.0
	sm.turbulence_influence_min = 0.05
	sm.turbulence_influence_max = 0.1
	sm.scale_min = 0.4
	sm.scale_max = 1.1
	sm.color_ramp = ReefFx.fade_ramp(Color(0.9, 1.0, 1.0), 0.85)
	_silt.process_material = sm
	_silt.draw_pass_1 = ReefFx.bubble_quad(0.22)
	add_child(_silt)
	# kelp planted along both long edges of the channel, leaning with the surge
	var side: Vector3 = Vector3.UP.cross(along).normalized()
	var side_half: float = absf(size.dot(side.abs())) * 0.5
	var kelp_mat: StandardMaterial3D = Look.flat(Color(0.35, 0.55, 0.2), 0.8, 0.0, 0.15)
	var tip_mat: StandardMaterial3D = Look.flat(Color(0.55, 0.85, 0.35), 0.7, 0.0, 0.5)
	for i: int in kelp:
		var f: float = (float(i / 2) + 0.5) / float(maxi(kelp / 2, 1))
		var s: float = -1.0 if i % 2 == 0 else 1.0
		var base: Vector3 = side * s * (side_half + 0.6) + along * (f - 0.5) * span * 0.9 + Vector3(0, -size.y * 0.5 - 3.0, 0)
		var h: float = size.y + 2.0 + float(i % 3) * 1.5
		var holder := Node3D.new()
		holder.position = base
		var stalk := Look.box(Vector3(0.12, h, 0.12), kelp_mat, Vector3(0, h * 0.5, 0))
		holder.add_child(stalk)
		for j: int in int(h / 1.6):
			var leaf := Look.box(Vector3(0.5, 0.9, 0.04), kelp_mat if j % 2 == 0 else tip_mat, Vector3(0.22 * (1.0 if j % 2 == 0 else -1.0), 1.2 + float(j) * 1.6, 0))
			leaf.rotation = Vector3(0, float(j) * 1.1, 0.5 * (1.0 if j % 2 == 0 else -1.0))
			holder.add_child(leaf)
		add_child(holder)
		_kelp.append(holder)
