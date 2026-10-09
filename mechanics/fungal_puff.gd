class_name FungalPuff
extends Area3D
## Mushroom Hollow: a SPORE-PUFF LIFT. A squat puffball sits on the ground. Every `period` seconds it
## swells and shivers for `warn` s (a hiss, and spores trickle up off it - the tell), then exhales a
## tall column of spores for `on_time` s that LIFTS anyone standing or floating in it, gently, never
## faster than `max_rise` m/s. Step in while it is blowing and ride the cloud up to the ledge; step in
## while it is quiet and nothing happens, you just wait on the puffball's shelf.
## Rule (identical for every racer): blowing while fposmod(t / period + phase, 1) * period < on_time.
## Positioned by the point on the ground at the middle of the puffball.

@export var height: float = 9.0
@export var radius: float = 1.6
@export var period: float = 8.0
@export var phase: float = 0.0
@export var on_time: float = 4.6
@export var warn: float = 1.1
@export var lift: float = 66.0
@export var max_rise: float = 9.0
## The walkable shelf round the column's footprint (metres beyond `radius`).
@export var shelf: float = 1.9

var _ball: Node3D
var _ball_mat: StandardMaterial3D
var _beam_mat: StandardMaterial3D
var _beam: MeshInstance3D
var _trickle: GPUParticles3D
var _column: GPUParticles3D
var _puff: GPUParticles3D
var _hum: AudioStreamPlayer3D
var _was_warn: bool = false
var _was_on: bool = false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitorable = false
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, height * 0.5, 0)
	add_child(cs)
	_build_visual()
	# SOUND: fungal_puff_loop - a soft airy rush while the spore column is blowing (loop, close range)
	_hum = WorldAudio.loop("fungal_puff_loop", self, -9.0, height + 10.0, 5.0, false)
	add_to_group("course_clock")
	_apply(Game.course_time)


## Seconds into the cycle at `time` (0 .. period).
func _cycle(time: float) -> float:
	return fposmod(time / period + phase, 1.0) * period


func is_on_at(time: float) -> bool:
	return _cycle(time) < on_time


## Seconds until the column next starts blowing (0 while it blows).
func time_to_on(time: float) -> float:
	var c: float = _cycle(time)
	return 0.0 if c < on_time else period - c


## True when the column keeps blowing over the whole of [time + a, time + b].
func on_over(time: float, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if not is_on_at(time + s):
			return false
		s += 0.05
	return is_on_at(time + b)


func snap_to_clock() -> void:
	_apply(Game.course_time)


func _physics_process(dt: float) -> void:
	if not is_on_at(Game.course_time):
		return
	for body: Node3D in get_overlapping_bodies():
		if body is Player:
			var p := body as Player
			if p.is_wall_running() or p.is_mantling():
				continue
			if p.velocity.y < max_rise:
				p.add_impulse(Vector3(0, minf(lift * dt, max_rise - p.velocity.y), 0))


func _process(_dt: float) -> void:
	_apply(Game.course_time)


func _apply(t: float) -> void:
	var on: bool = is_on_at(t)
	var left: float = time_to_on(t)
	var warning: bool = (not on) and left < warn
	var k: float = clampf(1.0 - left / warn, 0.0, 1.0) if warning else 0.0
	# the puffball swells and shivers through the warning, deflates after a blow
	var swell: float = 1.0 + 0.32 * k * k
	var shiver: float = (sin(t * 52.0) * 0.03 * k) if warning else 0.0
	if on:
		var c: float = _cycle(t)
		var rel: float = clampf(1.0 - c / 1.2, 0.0, 1.0)
		swell = 1.0 + 0.32 * rel
	_ball.scale = Vector3(swell + shiver, swell, swell - shiver)
	_ball_mat.emission_energy_multiplier = 0.12 + 1.0 * k + (0.6 if on else 0.0)
	_beam.visible = on
	if on:
		var c2: float = _cycle(t)
		var fade_out: float = clampf((on_time - c2) / 0.6, 0.0, 1.0)
		var fade_in: float = clampf(c2 / 0.25, 0.0, 1.0)
		_beam_mat.albedo_color.a = 0.17 * fade_in * fade_out
	if warning != _was_warn:
		_was_warn = warning
		_trickle.emitting = warning
		if warning:
			# SOUND: fungal_puff_swell - a long, rising hiss as the puffball swells (about 1.1 s ahead)
			if WorldAudio.once("fungal_puff_swell_%d" % get_instance_id(), 0.6):
				WorldAudio.at(self, "fungal_puff_swell", global_position, 0.8, 30.0)
	if on != _was_on:
		_was_on = on
		_column.emitting = on
		WorldAudio.set_active(_hum, on)
		if on:
			_puff.restart()
			_puff.emitting = true
			# SOUND: fungal_puff_blow - the whump of the spore cloud letting go
			WorldAudio.at(self, "fungal_puff_blow", global_position, 0.9, 32.0)


func _build_visual() -> void:
	# the puffball shelf: a flat tan disc (solid, walkable) with a mossy lip and a star of rays
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var fshape := CylinderShape3D.new()
	fshape.radius = radius + shelf
	fshape.height = 0.5
	var fcs := CollisionShape3D.new()
	fcs.shape = fshape
	floor_body.add_child(fcs)
	floor_body.position = Vector3(0, -0.25, 0)
	add_child(floor_body)
	var tan_mat: StandardMaterial3D = Look.flat(Color(0.93, 0.84, 0.62), 0.9)
	floor_body.add_child(Look.cylinder(radius + shelf, 0.5, tan_mat, Vector3.ZERO, radius + shelf - 0.15, 28))
	floor_body.add_child(Look.cylinder(radius + shelf - 0.3, 1.4, Look.flat(Color(0.78, 0.66, 0.46), 0.9), Vector3(0, -0.95, 0), radius * 0.4, 20))
	var ray_mat: StandardMaterial3D = Look.flat(Color(0.8, 0.66, 0.42), 0.9)
	for i: int in 8:
		var ray := Look.box(Vector3(radius + shelf - 0.3, 0.02, 0.22), ray_mat, Vector3(0, 0.26, 0))
		ray.rotation.y = TAU * float(i) / 8.0
		ray.position = Vector3(cos(ray.rotation.y), 0.0, -sin(ray.rotation.y)) * (radius + shelf - 0.3) * 0.5 + Vector3(0, 0.26, 0)
		ray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		floor_body.add_child(ray)
	# the lip of moss round the edge
	var tm := TorusMesh.new()
	tm.inner_radius = radius + 0.3
	tm.outer_radius = radius + 0.62
	tm.rings = 32
	tm.ring_segments = 8
	var lip := Look.mesh_node(tm, Look.flat(Color(0.4, 0.62, 0.26), 0.9), Vector3(0, 0.22, 0))
	lip.scale = Vector3(1, 0.4, 1)
	floor_body.add_child(lip)
	# the pore ring painted on the shelf: the footprint of the column, brightening with the tell
	_ball_mat = StandardMaterial3D.new()
	_ball_mat.albedo_color = Color(1.0, 0.86, 0.45)
	_ball_mat.roughness = 0.6
	_ball_mat.emission_enabled = true
	_ball_mat.emission = Color(1.0, 0.85, 0.4)
	_ball_mat.emission_energy_multiplier = 0.12
	var pore := TorusMesh.new()
	pore.inner_radius = radius * 0.78
	pore.outer_radius = radius * 0.9
	pore.rings = 36
	pore.ring_segments = 6
	var pore_n := Look.mesh_node(pore, _ball_mat, Vector3(0, 0.27, 0))
	pore_n.scale = Vector3(1, 0.16, 1)
	pore_n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pore_n)
	# six little puffballs round the rim that swell and shiver through the tell
	_ball = Node3D.new()
	_ball.position = Vector3(0, 0.1, 0)
	add_child(_ball)
	var puff_mat: StandardMaterial3D = Look.flat(Color(0.97, 0.9, 0.7), 0.85)
	for i: int in 6:
		var a: float = TAU * (float(i) + 0.5) / 6.0
		var pb := Look.sphere(0.34, puff_mat, Vector3(cos(a), 0.0, sin(a)) * (radius + 0.1))
		pb.scale = Vector3(1.0, 0.9, 1.0)
		_ball.add_child(pb)
	# the column: a faint warm cone of light spores (drawn only while blowing)
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam_mat.albedo_color = Color(1.0, 0.92, 0.55, 0.17)
	_beam = Look.cylinder(radius * 0.95, height, _beam_mat, Vector3(0, height * 0.5, 0), radius * 0.6, 20)
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.visible = false
	add_child(_beam)
	var vis := AABB(Vector3(-radius - 3.0, -2.0, -radius - 3.0), Vector3(radius * 2.0 + 6.0, height + 6.0, radius * 2.0 + 6.0))
	# the tell: a thin trickle of spores rising off the swelling ball
	_trickle = Fx.emitter({"amount": 14, "lifetime": 1.3, "emitting": false, "shape": "sphere", "radius": radius * 0.5,
		"dir": Vector3.UP, "spread": 18.0, "speed": Vector2(1.0, 2.2), "tex": Fx.Tex.DOT, "size": 0.16, "curve": "pop",
		"turbulence": 0.6, "color": Fx.hot(Color(1.0, 0.9, 0.5), 2.0), "local": true, "aabb": vis})
	_trickle.position = Vector3(0, radius * 0.7, 0)
	add_child(_trickle)
	# the blow: spores streaming up the whole column, slowly turning
	_column = Fx.emitter({"amount": 46, "lifetime": height / 6.0 + 0.3, "emitting": false, "shape": "ring", "ring_radius": radius * 0.8,
		"ring_inner": 0.0, "dir": Vector3.UP, "spread": 4.0, "speed": Vector2(5.0, 6.6), "tex": Fx.Tex.DOT,
		"size": 0.22, "curve": "pop", "turbulence": 0.5, "turbulence_scale": 3.0,
		"pick": PackedColorArray([Fx.hot(Color(1.0, 0.93, 0.6), 1.9), Fx.hot(Color(1.0, 0.8, 0.45), 1.7), Color(1.8, 1.8, 1.6)]),
		"local": true, "aabb": vis})
	_column.position = Vector3(0, radius * 0.6, 0)
	add_child(_column)
	_puff = Fx.smoke({"amount": 22, "lifetime": 1.4, "shape": "ring", "ring_radius": radius * 0.6, "ring_inner": 0.0,
		"dir": Vector3.UP, "spread": 50.0, "speed": Vector2(1.5, 3.5), "damping": Vector2(1.0, 2.0), "size": 1.1,
		"color": Color(1.0, 0.95, 0.75, 0.5), "aabb": vis})
	_puff.position = Vector3(0, radius * 0.75, 0)
	add_child(_puff)
