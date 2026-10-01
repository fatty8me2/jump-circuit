class_name NeonHolo
extends AnimatableBody3D
## Neon City hologram platform: a slab of projected light thrown up by a little projector puck
## underneath. It is there for `on_fraction` of every `period` (Game.course_time, identical for every
## racer) and gone for the rest. The tell is loud: for `warn` seconds before it switches off it
## GLITCHES - it tears into jittering bands, splits magenta / cyan, stutters, spits static sparks and
## crackles - and then it pops out, leaving only a faint outline and the projector's beam. Near the
## end of its time off the outline scans back in, brighter and brighter, before it snaps solid.
## Same timing rule as BlinkPlatform: solid while fposmod(t / period + phase, 1) < on_fraction.

@export var size: Vector3 = Vector3(2.6, 0.35, 2.6)
@export var period: float = 5.0
@export var on_fraction: float = 0.7
@export var phase: float = 0.0
## Seconds of glitching before it switches off.
@export var warn: float = 0.9
@export var tint: Color = Color(0.1, 0.95, 0.85)
## Height of the projector below the slab (0 = no projector).
@export var projector_drop: float = 2.2

var _shape: CollisionShape3D
var _slab: MeshInstance3D
var _mat: ShaderMaterial
var _edges: Array[MeshInstance3D] = []
var _edge_mat: StandardMaterial3D
var _edge_dim: StandardMaterial3D
var _beam_mat: ShaderMaterial
var _sparks: GPUParticles3D
var _pop: GPUParticles3D
var _gather: GPUParticles3D
var _solid: bool = true
var _was_on: bool = true
var _was_glitch: bool = false
var _hum: AudioStreamPlayer3D


func _ready() -> void:
	sync_to_physics = false
	collision_layer = 1
	collision_mask = 0
	var box := BoxShape3D.new()
	box.size = size
	_shape = CollisionShape3D.new()
	_shape.shape = box
	add_child(_shape)
	_build()
	_was_on = is_on_at(Game.course_time)
	_apply(Game.course_time)
	# SOUND: neon_holo_hum - the projector's electric hum while the slab is lit (loop)
	_hum = WorldAudio.loop("neon_holo_hum", self, -14.0, 16.0, 3.0, _was_on)


func is_on_at(time: float) -> bool:
	return fposmod(time / period + phase, 1.0) < on_fraction


## Seconds of solid time left at `time` (0 while off).
func time_left(time: float) -> float:
	var u: float = fposmod(time / period + phase, 1.0)
	return maxf(on_fraction - u, 0.0) * period


func _physics_process(_dt: float) -> void:
	var on: bool = is_on_at(Game.course_time)
	if on != _solid:
		_solid = on
		_shape.set_deferred("disabled", not on)


func _process(_dt: float) -> void:
	_apply(Game.course_time)


func _apply(t: float) -> void:
	var u: float = fposmod(t / period + phase, 1.0)
	var on: bool = u < on_fraction
	var left: float = (on_fraction - u) * period
	var glitch: float = 0.0
	var ghost: float = 0.0
	if on and left < warn:
		glitch = clampf(1.0 - left / warn, 0.0, 1.0) * 0.7 + 0.3
	var until_on: float = (1.0 - u) * period
	if not on:
		ghost = 1.0
		# the outline scans back in over the last 0.7 s
		var k: float = clampf(1.0 - until_on / 0.7, 0.0, 1.0)
		ghost = 1.0 - k * 0.55
	_slab.visible = on or until_on < 0.7
	_mat.set_shader_parameter("glitch", glitch)
	_mat.set_shader_parameter("ghost", ghost)
	var lit: bool = on and not (glitch > 0.0 and fmod(t, 0.12) < 0.05)
	for e: MeshInstance3D in _edges:
		e.material_override = _edge_mat if lit else _edge_dim
	if _beam_mat != null:
		_beam_mat.set_shader_parameter("strength", 0.35 if on else 0.12 + 0.2 * clampf(1.0 - until_on / 0.7, 0.0, 1.0))
	var g: bool = glitch > 0.0
	if g != _was_glitch:
		_was_glitch = g
		_sparks.emitting = g
		if g:
			# SOUND: neon_holo_glitch - the crackle of static as it starts to fail (warning, ~0.9 s ahead)
			WorldAudio.at(self, "neon_holo_glitch", global_position, 0.8, 30.0)
	if on != _was_on:
		_was_on = on
		if on:
			_gather.restart()
			# SOUND: neon_holo_on - the slab snaps back into being
			WorldAudio.at(self, "neon_holo_on", global_position, 0.6, 30.0)
		else:
			_pop.restart()
			# SOUND: neon_holo_off - it blinks out
			WorldAudio.at(self, "neon_holo_off", global_position, 0.7, 30.0)
		WorldAudio.set_active(_hum, on)


func _build() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://visual/neon_holo.gdshader")
	_mat.set_shader_parameter("tint", tint)
	_mat.set_shader_parameter("split", Color(1.0, 0.2, 0.7) if tint.g > tint.r else Color(0.1, 0.9, 1.0))
	_mat.set_shader_parameter("half_size", size * 0.5)
	var bm := BoxMesh.new()
	bm.size = size
	bm.subdivide_height = 2
	bm.subdivide_depth = 4
	_slab = Look.mesh_node(bm, _mat)
	_slab.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_slab)
	# wireframe edges round the top (they stay, dimmed, as the outline while it is off)
	_edge_mat = Look.flat(tint, 0.3, 0.0, 4.0)
	_edge_dim = Look.flat(Color(tint.r, tint.g, tint.b, 0.35), 0.5, 0.0, 0.8)
	var hx: float = size.x * 0.5
	var hz: float = size.z * 0.5
	var y: float = size.y * 0.5
	for sz: float in [-1.0, 1.0]:
		var e := Look.box(Vector3(size.x + 0.06, 0.05, 0.05), _edge_mat, Vector3(0, y, sz * hz))
		_edges.append(e)
		var e2 := Look.box(Vector3(0.05, 0.05, size.z + 0.06), _edge_mat, Vector3(sz * hx, y, 0))
		_edges.append(e2)
		for sx: float in [-1.0, 1.0]:
			var post := Look.box(Vector3(0.05, size.y, 0.05), _edge_mat, Vector3(sx * hx, 0, sz * hz))
			_edges.append(post)
	for e3: MeshInstance3D in _edges:
		e3.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(e3)
	if projector_drop > 0.2:
		# the projector puck and its beam up to the slab
		var dark: StandardMaterial3D = Look.flat(Color(0.06, 0.06, 0.08), 0.3, 0.7)
		var puck_y: float = -size.y * 0.5 - projector_drop
		add_child(Look.cylinder(0.35, 0.25, dark, Vector3(0, puck_y, 0), 0.28, 16))
		add_child(Look.cylinder(0.2, 0.05, Look.flat(tint, 0.3, 0.0, 5.0), Vector3(0, puck_y + 0.15, 0), -1.0, 16))
		var cm := CylinderMesh.new()
		cm.top_radius = minf(size.x, size.z) * 0.5
		cm.bottom_radius = 0.18
		cm.height = projector_drop - 0.15
		cm.radial_segments = 4
		cm.rings = 1
		cm.cap_top = false
		cm.cap_bottom = false
		_beam_mat = ShaderMaterial.new()
		_beam_mat.shader = preload("res://visual/neon_beam.gdshader")
		_beam_mat.set_shader_parameter("tint", tint)
		_beam_mat.set_shader_parameter("strength", 0.35)
		_beam_mat.set_shader_parameter("streaks", 0.0)
		var beam := Look.mesh_node(cm, _beam_mat, Vector3(0, puck_y + 0.1 + cm.height * 0.5, 0))
		beam.rotation.y = PI * 0.25
		beam.scale = Vector3(size.x / minf(size.x, size.z), 1.0, size.z / minf(size.x, size.z))
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(beam)
	var hot: Color = Fx.hot(tint.lerp(Color.WHITE, 0.25), 2.4)
	var vis := AABB(-size * 0.5 - Vector3(2, 3, 2), size + Vector3(4, 6, 4))
	_sparks = Fx.emitter({"amount": 26, "lifetime": 0.35, "shape": "box", "extents": size * 0.5,
		"speed": Vector2(1.5, 4.0), "spread": 180.0, "gravity": Vector3(0, -6.0, 0), "facing": "velocity",
		"tex": Fx.Tex.SPARK, "size": Vector2(0.03, 0.25), "pick": PackedColorArray([hot, Fx.hot(Color(1.0, 0.25, 0.7), 2.4)]),
		"emitting": false, "aabb": vis})
	add_child(_sparks)
	_pop = Fx.burst({"amount": clampi(int(size.x * size.z * 5.0), 16, 50), "lifetime": 0.6, "explosiveness": 0.9,
		"shape": "box", "extents": size * 0.5, "dir": Vector3.UP, "spread": 70.0, "speed": Vector2(0.5, 2.5),
		"gravity": Vector3(0, 0.5, 0), "size": 0.12, "tex": Fx.Tex.DOT, "color": hot, "curve": "shrink", "aabb": vis})
	add_child(_pop)
	_gather = Fx.burst({"amount": clampi(int(size.x * size.z * 4.0), 14, 40), "lifetime": 0.35, "explosiveness": 0.9,
		"shape": "box", "extents": size * 0.5 + Vector3(0.8, 0.5, 0.8), "speed": Vector2.ZERO, "radial": Vector2(-14.0, -9.0),
		"size": 0.12, "tex": Fx.Tex.DOT, "curve": "pop", "color": hot, "aabb": vis})
	add_child(_gather)
