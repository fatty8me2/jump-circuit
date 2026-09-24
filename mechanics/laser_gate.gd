class_name LaserGate
extends Node3D
## A kill beam between two emitter posts that fires on a fixed rhythm driven by
## Game.course_time (identical for every racer). Off: a faint dotted guide line.
## For `warn` seconds before firing the guide flickers bright. On: a solid red
## beam that sends you back to the checkpoint. Local X runs between the posts.

@export var size: Vector3 = Vector3(4, 0.25, 0.25)
@export var period: float = 3.0
@export var on_fraction: float = 0.5
@export var phase: float = 0.0
@export var warn: float = 0.45

var _area: Area3D
var _beam: MeshInstance3D
var _guide: MeshInstance3D
var _guide_mat: StandardMaterial3D
# effects (visual only): charge crackle at the eyes, sparks and heat haze along a live
# beam, a snap burst and flash when it switches on
var _crackle: Array[GPUParticles3D] = []
var _eye_glow: Array[MeshInstance3D] = []
var _beam_sparks: GPUParticles3D
var _snap: GPUParticles3D
var _haze: MeshInstance3D
var _lamp: OmniLight3D
var _fx_on: bool = false
var _fx_charging: bool = false


func _ready() -> void:
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 2
	_area.monitorable = false
	var shape := BoxShape3D.new()
	shape.size = size * Vector3(1.0, 0.92, 0.92)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	_area.add_child(cs)
	add_child(_area)
	var beam_mat := StandardMaterial3D.new()
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.albedo_color = Color(1.0, 0.18, 0.12)
	beam_mat.emission_enabled = true
	beam_mat.emission = Color(1.0, 0.15, 0.1)
	beam_mat.emission_energy_multiplier = 4.0
	_beam = Look.box(size, beam_mat)
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beam)
	# (children of the beam: shown and hidden with it) a white-hot core, a soft red sleeve
	var core_mat := StandardMaterial3D.new()
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_mat.albedo_color = Color(1.0, 0.85, 0.8)
	core_mat.emission_enabled = true
	core_mat.emission = Color(1.0, 0.75, 0.65)
	core_mat.emission_energy_multiplier = 6.0
	var core := Look.box(Vector3(size.x, size.y * 0.35, size.z * 1.02), core_mat)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.add_child(core)
	var sleeve_mat := StandardMaterial3D.new()
	sleeve_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sleeve_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sleeve_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	sleeve_mat.albedo_color = Color(1.0, 0.2, 0.1, 0.22)
	sleeve_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var sleeve := Look.box(Vector3(size.x, size.y + 0.35, size.z + 0.35), sleeve_mat)
	sleeve.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.add_child(sleeve)
	_guide_mat = StandardMaterial3D.new()
	_guide_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_guide_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_guide_mat.albedo_color = Color(1.0, 0.3, 0.2, 0.18)
	_guide = Look.box(Vector3(size.x, size.y * 0.3, size.z * 0.3), _guide_mat)
	_guide.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_guide)
	var post_mat: StandardMaterial3D = Look.flat(Color(0.14, 0.14, 0.18), 0.4, 0.7)
	var eye_mat: StandardMaterial3D = Look.flat(Color(1.0, 0.25, 0.15), 0.3, 0.0, 2.5)
	var post_h: float = maxf(size.y + 0.8, 1.2)
	for sx: float in [-1.0, 1.0]:
		add_child(Look.box(Vector3(0.36, post_h, 0.36), post_mat, Vector3(sx * (size.x * 0.5 + 0.18), 0, 0)))
		add_child(Look.box(Vector3(0.1, maxf(size.y, 0.2) + 0.1, maxf(size.z, 0.2) + 0.1), eye_mat, Vector3(sx * (size.x * 0.5 + 0.02), 0, 0)))
	_build_fx()
	_apply()


func is_on_at(time: float) -> bool:
	return fposmod(time / period + phase, 1.0) < on_fraction


## Seconds until the beam next switches on (0 while it is on).
func time_until_on(time: float) -> float:
	var u: float = fposmod(time / period + phase, 1.0)
	return 0.0 if u < on_fraction else (1.0 - u) * period


## Seconds until the beam next switches off (0 while it is off).
func time_until_off(time: float) -> float:
	var u: float = fposmod(time / period + phase, 1.0)
	return (on_fraction - u) * period if u < on_fraction else 0.0


func _apply() -> void:
	var t: float = Game.course_time
	var on: bool = is_on_at(t)
	_beam.visible = on
	_guide.visible = not on
	var a: float = 0.18
	var until_on: float = time_until_on(t)
	if not on and until_on < warn:
		a = 0.75 if fmod(until_on, 0.12) > 0.06 else 0.35
	if not is_equal_approx(_guide_mat.albedo_color.a, a):
		var c: Color = _guide_mat.albedo_color
		c.a = a
		_guide_mat.albedo_color = c


const HOT_RED: Color = Color(3.0, 0.55, 0.3)


func _build_fx() -> void:
	var half: float = size.x * 0.5
	for sx: float in [-1.0, 1.0]:
		var c: GPUParticles3D = Fx.sparks({"amount": 16, "lifetime": 0.22, "one_shot": false, "emitting": false,
			"explosiveness": 0.0, "randomness": 0.8, "spread": 180.0, "speed": Vector2(2.0, 5.0),
			"gravity": Vector3.ZERO, "damping": Vector2(6.0, 9.0), "size": Vector2(0.06, 0.4),
			"shape": "sphere", "radius": 0.12, "color": Color(3.0, 1.2, 0.8), "local": true,
			"aabb": AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))})
		c.position = Vector3(sx * (half - 0.08), 0, 0)
		add_child(c)
		_crackle.append(c)
		# the eye swells with light as the charge builds
		var glow: MeshInstance3D = Fx.sprite(Color(3.0, 0.9, 0.5, 0.0), 1.0, Fx.Tex.DOT, true)
		glow.position = c.position
		glow.visible = false
		add_child(glow)
		_eye_glow.append(glow)
	var beam_box := Vector3(half, size.y * 0.4, size.z * 0.4)
	var vis := AABB(Vector3(-half - 1.0, -3.0, -1.5), Vector3(size.x + 2.0, 5.0, 3.0))
	_beam_sparks = Fx.sparks({"amount": clampi(int(size.x * 4.0), 8, 36), "lifetime": 0.45, "one_shot": false,
		"emitting": false, "explosiveness": 0.0, "randomness": 0.5, "shape": "box", "extents": beam_box,
		"dir": Vector3(0, 1, 0), "spread": 75.0, "speed": Vector2(1.0, 3.5), "gravity": Vector3(0, -12, 0),
		"size": Vector2(0.06, 0.36), "color": Color(3.2, 1.0, 0.45), "aabb": vis})
	add_child(_beam_sparks)
	_snap = Fx.sparks({"amount": clampi(int(size.x * 7.0), 14, 60), "lifetime": 0.4, "shape": "box",
		"extents": beam_box, "spread": 180.0, "speed": Vector2(3.0, 8.0), "gravity": Vector3(0, -8, 0),
		"damping": Vector2(3.0, 5.0), "color": HOT_RED, "size": Vector2(0.09, 0.6), "aabb": vis})
	add_child(_snap)
	# heat shimmer rising off the live beam (reads the screen: Medium / High only)
	if Fx.density() > 0.5:
		var hm := ShaderMaterial.new()
		hm.shader = preload("res://visual/heat_haze.gdshader")
		var q := QuadMesh.new()
		q.size = Vector2(size.x, 1.1)
		_haze = Look.mesh_node(q, hm, Vector3(0, 0.55 + size.y * 0.3, 0))
		_haze.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_haze.visible = false
		add_child(_haze)
	_lamp = OmniLight3D.new()
	_lamp.light_color = Color(1.0, 0.25, 0.15)
	_lamp.omni_range = maxf(size.x * 0.7, 3.0)
	_lamp.light_energy = 0.0
	_lamp.visible = false
	add_child(_lamp)
	_fx_on = is_on_at(Game.course_time)


## Visual state only (the kill check in _physics_process never reads any of this).
func _process(_dt: float) -> void:
	var t: float = Game.course_time
	var on: bool = is_on_at(t)
	var charging: bool = not on and time_until_on(t) < warn
	if charging != _fx_charging:
		_fx_charging = charging
		for c: GPUParticles3D in _crackle:
			c.emitting = charging
		for g: MeshInstance3D in _eye_glow:
			g.visible = charging
	if charging:
		var k: float = clampf(1.0 - time_until_on(t) / maxf(warn, 0.01), 0.0, 1.0)
		var flick: float = 0.75 + 0.25 * sin(t * 83.0) * sin(t * 57.0)
		for g: MeshInstance3D in _eye_glow:
			g.scale = Vector3.ONE * lerpf(0.35, 1.3, k) * flick
			(g.material_override as StandardMaterial3D).albedo_color.a = lerpf(0.3, 1.0, k)
	if on != _fx_on:
		_fx_on = on
		_beam_sparks.emitting = on
		if _haze != null:
			_haze.visible = on
		if on:
			_snap.restart()
			Fx.pulse(_lamp, 4.0, 0.0, 0.35)


func _physics_process(_dt: float) -> void:
	_apply()
	if not is_on_at(Game.course_time):
		return
	for body: Node3D in _area.get_overlapping_bodies():
		if body is Player:
			var n: Node = self
			while n != null and not n.has_method("fail"):
				n = n.get_parent()
			if n != null:
				n.call_deferred("fail", "hazard")
			return
