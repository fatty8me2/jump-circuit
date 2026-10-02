class_name VoidPhase
extends AnimatableBody3D
## The Void: PHASE PLATFORMS. Two sets of floating tiles share one beat on the course clock: the
## PINK set is solid for the first half of every `period`, the CYAN set for the second half, so the
## two sets swap back and forth. A tile that is out is only a dim outline of its colour.
## Both changes are shown ahead of time (`warn` s, at least 0.8):
##  * going out: the tile flickers faster and faster, its edges strobe and it sheds white motes;
##  * coming in: the outline fills with light from the edges inward and motes gather to it.
## Rule (identical for every racer): solid while (fposmod(t / period + phase, 1) < 0.5) == (set == 0).

const PINK := Color(1.0, 0.36, 0.72)
const CYAN := Color(0.32, 0.9, 1.0)

@export var size: Vector3 = Vector3(1.3, 0.4, 1.3)
@export var period: float = 4.8
@export var phase: float = 0.0
## 0 = the pink set (solid first), 1 = the cyan set (solid second).
@export var set_id: int = 0
## Seconds of warning before each change.
@export var warn: float = 0.95

var _shape: CollisionShape3D
var _slab: MeshInstance3D
var _slab_mat: StandardMaterial3D
var _edge_mat: StandardMaterial3D
var _edges: Array[MeshInstance3D] = []
var _shed: GPUParticles3D
var _gather: GPUParticles3D
var _pop: GPUParticles3D
var _solid: bool = true
var _was_on: bool = true
var _was_warn: bool = false


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
	_solid = is_on_at(Game.course_time)
	_shape.disabled = not _solid
	_was_on = _solid
	_apply(Game.course_time)


func tint() -> Color:
	return PINK if set_id == 0 else CYAN


func is_on_at(time: float) -> bool:
	return (fposmod(time / period + phase, 1.0) < 0.5) == (set_id == 0)


## Seconds until the next change (in or out) at `time`.
func time_to_change(time: float) -> float:
	var u: float = fposmod(time / period + phase, 1.0)
	return (0.5 - u if u < 0.5 else 1.0 - u) * period


## True when it stays solid over the whole of [time + a, time + b].
func solid_over(time: float, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if not is_on_at(time + s):
			return false
		s += 0.05
	return is_on_at(time + b)


func _physics_process(_dt: float) -> void:
	var on: bool = is_on_at(Game.course_time)
	if on != _solid:
		_solid = on
		_shape.set_deferred("disabled", not on)


func _process(_dt: float) -> void:
	_apply(Game.course_time)


func _apply(t: float) -> void:
	var on: bool = is_on_at(t)
	var left: float = time_to_change(t)
	var warning: bool = left < warn
	var k: float = clampf(1.0 - left / warn, 0.0, 1.0) if warning else 0.0
	var col: Color = tint()
	if on:
		# solid: bright white glass with a wash of the set colour; flickering out on the warning
		var a: float = 0.92
		var edge: float = 3.2
		if warning:
			var rate: float = lerpf(7.0, 22.0, k)
			var blink: float = 0.5 + 0.5 * sin(t * rate * TAU)
			a = lerpf(0.92, 0.3, k * blink)
			edge = lerpf(3.2, 0.6, blink * (0.4 + 0.6 * k))
		_slab.visible = true
		_slab_mat.albedo_color = Color(0.94, 0.93, 0.98, a)
		_slab_mat.emission = col
		_slab_mat.emission_energy_multiplier = 0.35
		_edge_mat.emission_energy_multiplier = edge
	else:
		# out: a dim outline; on the warning it fills with light, edges first
		_slab.visible = warning
		_slab_mat.albedo_color = Color(col.r, col.g, col.b, 0.08 + 0.55 * k * k)
		_slab_mat.emission = col
		_slab_mat.emission_energy_multiplier = 0.2 + 1.2 * k
		_edge_mat.emission_energy_multiplier = 0.45 + 2.6 * k
	_edge_mat.albedo_color = Color(col.r, col.g, col.b, 1.0 if on or warning else 0.45)
	if warning != _was_warn:
		_was_warn = warning
		if warning:
			if on:
				_shed.emitting = true
				# SOUND: void_phase_warn - a glassy ticking as the solid set starts to fade (~0.95 s ahead)
				if WorldAudio.once("void_phase_warn_%d" % get_instance_id(), 0.5):
					WorldAudio.at(self, "void_phase_warn", global_position, 0.6, 26.0)
			else:
				_gather.restart()
				_gather.emitting = true
		else:
			_shed.emitting = false
	if on != _was_on:
		_was_on = on
		if not on:
			_pop.restart()
			_pop.emitting = true
		# SOUND: void_phase_swap - the chime of the two sets trading places (one per beat nearby)
		if WorldAudio.once("void_phase_swap", 0.3):
			WorldAudio.at(self, "void_phase_swap", global_position, 0.7, 30.0)


func _build() -> void:
	var col: Color = tint()
	_slab_mat = StandardMaterial3D.new()
	_slab_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_slab_mat.albedo_color = Color(0.94, 0.93, 0.98, 0.92)
	_slab_mat.roughness = 0.15
	_slab_mat.metallic = 0.2
	_slab_mat.emission_enabled = true
	_slab_mat.emission = col
	_slab_mat.emission_energy_multiplier = 0.35
	_slab = Look.box(size, _slab_mat)
	_slab.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_slab)
	# a bright frame round all twelve edges: it stays (dimmed) as the outline while the tile is out
	_edge_mat = StandardMaterial3D.new()
	_edge_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_edge_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_edge_mat.albedo_color = col
	_edge_mat.emission_enabled = true
	_edge_mat.emission = col
	_edge_mat.emission_energy_multiplier = 3.2
	var h: Vector3 = size * 0.5
	var w: float = 0.06
	for sy: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_edge(Vector3(size.x + w, w, w), Vector3(0, sy * h.y, sz * h.z))
		for sx: float in [-1.0, 1.0]:
			_edge(Vector3(w, w, size.z + w), Vector3(sx * h.x, sy * h.y, 0))
	for sx2: float in [-1.0, 1.0]:
		for sz2: float in [-1.0, 1.0]:
			_edge(Vector3(w, size.y, w), Vector3(sx2 * h.x, 0, sz2 * h.z))
	# a diamond inlay on the top so the set reads from above
	var gem := Look.box(Vector3(size.x * 0.32, 0.02, size.z * 0.32), _edge_mat, Vector3(0, h.y + 0.012, 0))
	gem.rotation.y = PI * 0.25
	gem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(gem)
	_edges.append(gem)
	var hot: Color = Fx.hot(col.lerp(Color.WHITE, 0.35), 2.2)
	var vis := AABB(-size * 0.5 - Vector3(2, 2, 2), size + Vector3(4, 5, 4))
	_shed = Fx.emitter({"amount": 18, "lifetime": 0.7, "shape": "box", "extents": size * 0.5, "dir": Vector3.UP,
		"spread": 40.0, "speed": Vector2(0.4, 1.4), "gravity": Vector3(0, 0.6, 0), "tex": Fx.Tex.STAR,
		"size": 0.14, "color": hot, "curve": "shrink", "emitting": false, "aabb": vis})
	add_child(_shed)
	_gather = Fx.burst({"amount": clampi(int(size.x * size.z * 8.0), 10, 30), "lifetime": 0.6, "explosiveness": 0.6,
		"shape": "box", "extents": size * 0.5 + Vector3(0.9, 0.5, 0.9), "speed": Vector2.ZERO,
		"radial": Vector2(-9.0, -6.0), "size": 0.13, "tex": Fx.Tex.DOT, "curve": "pop", "color": hot, "aabb": vis})
	add_child(_gather)
	_pop = Fx.burst({"amount": clampi(int(size.x * size.z * 10.0), 12, 36), "lifetime": 0.7, "explosiveness": 0.9,
		"shape": "box", "extents": size * 0.5, "dir": Vector3.DOWN, "spread": 70.0, "speed": Vector2(0.5, 2.2),
		"gravity": Vector3(0, -2.0, 0), "size": 0.12, "tex": Fx.Tex.STAR, "color": hot, "curve": "shrink", "aabb": vis})
	add_child(_pop)


func _edge(sz: Vector3, at: Vector3) -> void:
	var e := Look.box(sz, _edge_mat, at)
	e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(e)
	_edges.append(e)
