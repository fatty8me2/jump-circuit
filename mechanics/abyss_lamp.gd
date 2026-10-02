class_name AbyssLamp
extends StaticBody3D
## The Abyss: a GLOW CAP - a round cushion of bioluminescent sponge on a dark stalk. It is solid
## only while it is lit. On a fixed rhythm (Game.course_time, identical for every racer) its light
## fails: for `warn` seconds it flickers, dims and sheds a cloud of glowing spores (with a falling
## "dimming" chime), then it goes dark and you fall through. Dark, only a faint ring of dots on
## its rim marks where it will be; over the last 0.7 s of its time off the light pulses back in
## from the rim before it snaps solid. Same timing rule as BlinkPlatform:
## solid while fposmod(t / period + phase, 1) < on_fraction.
## Positioned at the centre of its TOP surface minus half its thickness (kit.blink style).

@export var radius: float = 0.65
@export var thick: float = 0.4
@export var period: float = 5.0
@export var on_fraction: float = 0.7
@export var phase: float = 0.0
## Seconds of flickering before it goes dark.
@export var warn: float = 1.0
@export var tint: Color = Color(0.2, 1.0, 0.75)
## Length of the dark stalk below the cap (0 = none).
@export var stalk: float = 6.0

const RELIGHT: float = 0.7

var _shape: CollisionShape3D
var _cap: MeshInstance3D
var _cap_mat: StandardMaterial3D
var _rim_mat: StandardMaterial3D
var _dots: Array[MeshInstance3D] = []
var _dot_on: StandardMaterial3D
var _dot_dim: StandardMaterial3D
var _light: OmniLight3D
var _spores: GPUParticles3D
var _shed: GPUParticles3D
var _bloom: GPUParticles3D
var _solid: bool = true
var _was_on: bool = true
var _was_warn: bool = false


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = thick
	_shape = CollisionShape3D.new()
	_shape.shape = cyl
	add_child(_shape)
	_build()
	add_to_group("course_clock")
	snap_to_clock()


func snap_to_clock() -> void:
	_was_on = is_on_at(Game.course_time)
	_solid = _was_on
	_shape.disabled = not _solid
	_apply(Game.course_time)


func is_on_at(time: float) -> bool:
	return fposmod(time / period + phase, 1.0) < on_fraction


## Lit (solid) for the whole of [time + a, time + b].
func on_between(time: float, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if not is_on_at(time + s):
			return false
		s += 0.04
	return is_on_at(time + b)


## Seconds of solid time left at `time` (0 while dark).
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
	var until_on: float = (1.0 - u) * period
	var glow: float = 1.0
	var warning: bool = on and left < warn
	if warning:
		# dims toward the end, with an uneven flicker that gets faster
		var k: float = clampf(1.0 - left / warn, 0.0, 1.0)
		var flick: float = 0.5 + 0.5 * sin(t * lerpf(14.0, 40.0, k)) * sin(t * 23.0)
		glow = lerpf(1.0, 0.25, k) * lerpf(1.0, flick, 0.4 + 0.6 * k)
	elif not on:
		# dark: the rim's dots pulse back in over the last moments
		glow = 0.0
	_cap.visible = on or until_on < RELIGHT
	_cap_mat.emission_energy_multiplier = 0.15 + 2.2 * glow if on else 0.25 * clampf(1.0 - until_on / RELIGHT, 0.0, 1.0)
	var c: Color = _cap_mat.albedo_color
	c.a = 1.0 if on else 0.35
	_cap_mat.albedo_color = c
	_rim_mat.emission_energy_multiplier = 0.4 + 3.2 * glow if on else 0.3 + 2.0 * clampf(1.0 - until_on / RELIGHT, 0.0, 1.0)
	var lit: bool = on and not (warning and fmod(t, 0.16) < 0.05)
	for d: MeshInstance3D in _dots:
		d.material_override = _dot_on if lit else _dot_dim
	if _light != null:
		_light.light_energy = 1.4 * glow
	if warning != _was_warn:
		_was_warn = warning
		_shed.emitting = warning
		if warning:
			# SOUND: abyss_lamp_dim - a falling, wavering glassy chime as the light starts to fail (~1 s ahead)
			WorldAudio.at(self, "abyss_lamp_dim", global_position, 0.7, 30.0)
	if on != _was_on:
		_was_on = on
		_spores.emitting = on
		if on:
			_bloom.restart()
			# SOUND: abyss_lamp_on - a soft bubbling bloom as the cap lights up again
			WorldAudio.at(self, "abyss_lamp_on", global_position, 0.5, 30.0)
		else:
			# SOUND: abyss_lamp_out - a muffled pop as it goes dark
			WorldAudio.at(self, "abyss_lamp_out", global_position, 0.6, 30.0)


func _build() -> void:
	var dark: Color = Color(0.05, 0.07, 0.09)
	# the cap: a soft glowing cushion (its sides a little narrower toward the bottom)
	_cap_mat = StandardMaterial3D.new()
	_cap_mat.albedo_color = tint.darkened(0.55)
	_cap_mat.roughness = 0.55
	_cap_mat.emission_enabled = true
	_cap_mat.emission = tint
	_cap_mat.emission_energy_multiplier = 2.0
	_cap_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius * 0.82
	cm.height = thick
	cm.radial_segments = 28
	cm.rings = 1
	_cap = Look.mesh_node(cm, _cap_mat)
	_cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_cap)
	# a bright rim round the top edge (the outline you aim for)
	_rim_mat = StandardMaterial3D.new()
	_rim_mat.albedo_color = tint
	_rim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rim_mat.emission_enabled = true
	_rim_mat.emission = tint
	_rim_mat.emission_energy_multiplier = 3.0
	var tm := TorusMesh.new()
	tm.inner_radius = radius - 0.06
	tm.outer_radius = radius + 0.02
	tm.rings = 32
	tm.ring_segments = 6
	var rim := Look.mesh_node(tm, _rim_mat, Vector3(0, thick * 0.5, 0))
	rim.scale = Vector3(1, 0.6, 1)
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rim)
	# a ring of glowing dots on the top (they stay, dimmed, as the marker while it is dark)
	_dot_on = Look.flat(tint.lerp(Color.WHITE, 0.4), 0.3, 0.0, 4.0)
	_dot_dim = Look.flat(Color(tint.r, tint.g, tint.b, 0.5), 0.5, 0.0, 1.0)
	var n: int = clampi(int(radius * 9.0), 6, 14)
	for i: int in n:
		var a: float = TAU * float(i) / float(n)
		var d := Look.sphere(0.05, _dot_on, Vector3(cos(a) * radius * 0.7, thick * 0.5 + 0.01, sin(a) * radius * 0.7))
		d.scale = Vector3(1, 0.4, 1)
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_dots.append(d)
		add_child(d)
	# the stalk down into the dark
	if stalk > 0.2:
		var st := Look.cylinder(radius * 0.22, stalk, Look.flat(dark, 0.8), Vector3(0, -thick * 0.5 - stalk * 0.5, 0), radius * 0.3, 10)
		add_child(st)
		var foot := Look.cylinder(radius * 0.34, 0.25, Look.flat(tint.darkened(0.6), 0.6, 0.0, 0.8), Vector3(0, -thick * 0.5 - 0.12, 0), radius * 0.8, 12)
		add_child(foot)
	_light = OmniLight3D.new()
	_light.light_color = tint
	_light.light_energy = 1.4
	_light.omni_range = maxf(radius * 4.0, 3.0)
	_light.shadow_enabled = false
	_light.position = Vector3(0, thick * 0.5 + 0.4, 0)
	add_child(_light)
	var hot: Color = Fx.hot(tint.lerp(Color.WHITE, 0.2), 2.2)
	var vis := AABB(Vector3(-radius - 2.0, -3.0, -radius - 2.0), Vector3(radius * 2.0 + 4.0, 7.0, radius * 2.0 + 4.0))
	# spores drifting up off the lit cap
	_spores = Fx.emitter({"amount": 8, "lifetime": 2.2, "shape": "ring", "ring_radius": radius * 0.8, "ring_inner": 0.1,
		"dir": Vector3.UP, "spread": 20.0, "speed": Vector2(0.2, 0.6), "turbulence": 0.6, "tex": Fx.Tex.DOT,
		"size": 0.07, "curve": "pop", "color": hot, "preprocess": 2.2, "aabb": vis, "local": true})
	_spores.position = Vector3(0, thick * 0.5, 0)
	add_child(_spores)
	# the warning: a cloud of spores shaken loose while it flickers
	_shed = Fx.emitter({"amount": 26, "lifetime": 0.9, "shape": "ring", "ring_radius": radius, "ring_inner": radius * 0.5,
		"dir": Vector3.DOWN, "spread": 60.0, "speed": Vector2(0.4, 1.4), "gravity": Vector3(0, -0.8, 0),
		"tex": Fx.Tex.DOT, "size": 0.09, "curve": "shrink", "color": hot, "emitting": false, "aabb": vis})
	_shed.position = Vector3(0, thick * 0.5, 0)
	add_child(_shed)
	# relit: a ring of light blooming outward
	_bloom = Fx.burst({"amount": 18, "lifetime": 0.5, "explosiveness": 0.9, "shape": "ring", "ring_radius": radius * 0.5,
		"ring_inner": 0.1, "dir": Vector3.UP, "spread": 80.0, "radial_vel": Vector2(1.5, 3.0), "speed": Vector2(0.2, 0.6),
		"size": 0.1, "tex": Fx.Tex.DOT, "curve": "shrink", "color": hot, "aabb": vis})
	_bloom.position = Vector3(0, thick * 0.5, 0)
	add_child(_bloom)
