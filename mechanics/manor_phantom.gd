class_name ManorPhantom
extends AnimatableBody3D
## Phantom Manor: phantom furniture - a ghostly table, armoire, bed, bench, chest or tombstone
## that is only solid while the ghost lantern hanging over it burns. On a fixed rhythm
## (Game.course_time; a blink variant) the piece phases in and out of the world:
##  * solid: a dense, glowing green body, its lantern bright;
##  * `warn` s before it goes: it wavers and flickers harder and harder, the lantern gutters;
##  * gone: a faint outline hangs there, the lantern is a dim ember;
##  * `warn` s before it returns: the outline fills back in and the lantern relights.
## Solid only while "on". Positioned like a platform (centre of its top slab); the collision
## is one box of `size`, and the furniture is built so its top matches that box's top.

@export var size: Vector3 = Vector3(2.4, 0.5, 2.0)
@export var period: float = 4.0
@export var on_fraction: float = 0.6
@export var phase: float = 0.0
@export var warn: float = 0.9
## "table", "armoire" (on its back), "bed", "bench", "chest", "slab" (a gravestone lying flat), "piano"
@export var kind: String = "table"
@export var tint: Color = Color(0.55, 1.0, 0.72)
## Hang a ghost lantern over it (the cue a human reads).
@export var lantern: bool = true

const GHOST: float = 0.1

var _shape: CollisionShape3D
var _mat: ShaderMaterial
var _solid: bool = true
var _fx_on: bool = true
var _warned: bool = false
var _fade: GPUParticles3D
var _form: GPUParticles3D
var _flame_mat: StandardMaterial3D
var _lamp: OmniLight3D


func _ready() -> void:
	sync_to_physics = false
	collision_layer = 1
	collision_mask = 0
	var box := BoxShape3D.new()
	box.size = size
	_shape = CollisionShape3D.new()
	_shape.shape = box
	add_child(_shape)
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://visual/manor_ghost.gdshader")
	_mat.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	_build_body()
	var vis := AABB(-size * 0.5 - Vector3(2, 3, 2), size + Vector3(4, 8, 4))
	var hot: Color = Fx.hot(tint, 2.0)
	_fade = Fx.burst({"amount": 34, "lifetime": 1.0, "explosiveness": 0.55, "shape": "box", "extents": size * 0.5,
		"dir": Vector3.UP, "spread": 35.0, "speed": Vector2(0.6, 2.2), "gravity": Vector3(0, 1.8, 0),
		"damping": Vector2(0.5, 1.5), "size": 0.22, "tex": Fx.Tex.SMOKE, "color": Color(hot.r, hot.g, hot.b, 0.6),
		"turbulence": 1.0, "aabb": vis})
	add_child(_fade)
	_form = Fx.burst({"amount": 28, "lifetime": 0.5, "explosiveness": 0.9, "shape": "box",
		"extents": size * 0.5 + Vector3(0.9, 0.6, 0.9), "speed": Vector2.ZERO, "radial": Vector2(-12.0, -8.0),
		"size": 0.16, "tex": Fx.Tex.STAR, "curve": "pop", "color": hot, "aabb": vis})
	add_child(_form)
	# ectoplasm dripping off it and a few wisps rising all the time
	var wisp: GPUParticles3D = Fx.emitter({"amount": 8, "lifetime": 1.8, "preprocess": 1.8, "shape": "box",
		"extents": Vector3(size.x * 0.45, 0.05, size.z * 0.45), "dir": Vector3.UP, "spread": 12.0,
		"speed": Vector2(0.3, 0.8), "turbulence": 0.8, "tex": Fx.Tex.DOT, "size": 0.12, "curve": "pop",
		"color": Color(hot.r * 0.6, hot.g * 0.6, hot.b * 0.6, 0.7), "aabb": vis})
	wisp.position = Vector3(0, size.y * 0.5, 0)
	add_child(wisp)
	if lantern:
		_build_lantern()
	_fx_on = is_on_at(Game.course_time)
	_apply(Game.course_time)


## The furniture, in ghost-stuff. Its top face sits at +size.y/2 like the collision box.
func _build_body() -> void:
	var top: float = size.y * 0.5
	var sx: float = size.x
	var sz: float = size.z
	match kind:
		"table":
			_part(Vector3(sx, 0.16, sz), Vector3(0, top - 0.08, 0))
			_part(Vector3(sx - 0.3, 0.2, sz - 0.3), Vector3(0, top - 0.26, 0))
			for x: float in [-1.0, 1.0]:
				for z: float in [-1.0, 1.0]:
					_leg(Vector3(x * (sx * 0.5 - 0.25), top - 0.36, z * (sz * 0.5 - 0.25)), 1.3, 0.09)
		"armoire":
			# an armoire floating on its back: the doors face up, carved panels and a cornice
			_part(Vector3(sx, size.y, sz), Vector3.ZERO)
			_part(Vector3(sx + 0.2, size.y * 0.6, 0.25), Vector3(0, 0, -sz * 0.5 - 0.05))
			for x: float in [-0.25, 0.25]:
				_part(Vector3(sx * 0.4, 0.05, sz * 0.8), Vector3(x * sx, top + 0.01, 0))
		"bed":
			_part(Vector3(sx, 0.35, sz), Vector3(0, top - 0.17, 0))
			_part(Vector3(sx * 0.9, 0.14, sz * 0.25), Vector3(0, top + 0.02, -sz * 0.33))
			_part(Vector3(sx + 0.1, 1.6, 0.14), Vector3(0, top + 0.3, -sz * 0.5))
			for x: float in [-1.0, 1.0]:
				_leg(Vector3(x * (sx * 0.5 - 0.05), top + 0.4, -sz * 0.5), 2.4, 0.08)
				_leg(Vector3(x * (sx * 0.5 - 0.05), top - 0.35, sz * 0.5 - 0.1), 0.9, 0.08)
		"bench":
			_part(Vector3(sx, 0.14, sz), Vector3(0, top - 0.07, 0))
			for x: float in [-1.0, 1.0]:
				_part(Vector3(0.14, 0.9, sz * 0.9), Vector3(x * (sx * 0.5 - 0.2), top - 0.55, 0))
		"chest":
			_part(Vector3(sx, size.y, sz), Vector3.ZERO)
			var lid := Look.cylinder(sz * 0.5, sx, _mat, Vector3(0, top, 0), -1.0, 14)
			lid.rotation.z = PI * 0.5
			lid.scale = Vector3(1.0, 1.0, 0.35)
			add_child(lid)
		"slab":
			_part(Vector3(sx, size.y, sz), Vector3.ZERO)
			_part(Vector3(sx * 0.5, 0.04, 0.12), Vector3(0, top + 0.01, -sz * 0.15))
			_part(Vector3(0.12, 0.04, sz * 0.55), Vector3(0, top + 0.01, -sz * 0.1))
		"piano":
			_part(Vector3(sx, size.y, sz), Vector3.ZERO)
			var cm := CylinderMesh.new()
			cm.top_radius = sz * 0.5
			cm.bottom_radius = sz * 0.5
			cm.height = size.y
			var curve := Look.mesh_node(cm, _mat, Vector3(sx * 0.35, 0, sz * 0.1))
			curve.scale = Vector3(1.2, 1.0, 1.0)
			add_child(curve)
			_part(Vector3(sx * 0.9, 0.08, 0.5), Vector3(0, top - 0.2, sz * 0.5 + 0.2))
			for x: float in [-1.0, 0.0, 1.0]:
				_leg(Vector3(x * sx * 0.4, top - 0.7, 0), 1.0, 0.1)
		_:
			_part(size, Vector3.ZERO)


func _part(s: Vector3, at: Vector3) -> void:
	var mi := Look.box(s, _mat, at)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _leg(at: Vector3, length: float, r: float) -> void:
	var mi := Look.cylinder(r, length, _mat, at - Vector3(0, length * 0.5 - 0.1, 0), r * 0.6, 8)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## A little iron lantern hanging from a crooked hook above the piece: its green flame is the
## tell - bright while the furniture is solid, guttering while it is about to go.
func _build_lantern() -> void:
	var at := Vector3(size.x * 0.5 - 0.1, size.y * 0.5 + 2.9, -size.z * 0.5 + 0.1)
	var iron: StandardMaterial3D = Look.flat(Color(0.08, 0.07, 0.09), 0.5, 0.7)
	add_child(Look.box(Vector3(0.06, 0.7, 0.06), iron, at + Vector3(0, 0.75, 0)))
	add_child(Look.box(Vector3(0.36, 0.06, 0.36), iron, at + Vector3(0, 0.34, 0)))
	add_child(Look.box(Vector3(0.36, 0.06, 0.36), iron, at + Vector3(0, -0.3, 0)))
	for x: float in [-1.0, 1.0]:
		for z: float in [-1.0, 1.0]:
			add_child(Look.box(Vector3(0.04, 0.62, 0.04), iron, at + Vector3(x * 0.16, 0.02, z * 0.16)))
	_flame_mat = StandardMaterial3D.new()
	_flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flame_mat.albedo_color = Fx.hot(tint, 2.2)
	var flame := Look.sphere(0.13, _flame_mat, at)
	flame.scale = Vector3(1.0, 1.6, 1.0)
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flame)
	_lamp = OmniLight3D.new()
	_lamp.light_color = tint
	_lamp.light_energy = 1.2
	_lamp.omni_range = 5.0
	_lamp.shadow_enabled = false
	_lamp.position = at
	add_child(_lamp)


func _u(time: float) -> float:
	return fposmod(time / period + phase, 1.0)


func is_on_at(time: float) -> bool:
	return _u(time) < on_fraction


## Solid for the whole window [time + a, time + b].
func is_on_for(time: float, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if not is_on_at(time + s):
			return false
		s += 0.05
	return is_on_at(time + b)


## Seconds of solidity left (0 while gone).
func time_until_off(time: float) -> float:
	var u: float = _u(time)
	return (on_fraction - u) * period if u < on_fraction else 0.0


## Seconds until it is solid again (0 while solid).
func time_until_on(time: float) -> float:
	var u: float = _u(time)
	return 0.0 if u < on_fraction else (1.0 - u) * period


func _apply(t: float) -> void:
	var on: bool = is_on_at(t)
	var solidity: float = 1.0
	var shimmer: float = 0.0
	var flame: float = 1.0
	if on:
		var left: float = time_until_off(t)
		if left < warn:
			var k: float = 1.0 - left / warn
			shimmer = k
			solidity = lerpf(1.0, 0.5, k)
			flame = lerpf(1.0, 0.25, k) * (0.6 + 0.4 * absf(sin(t * 23.0)))
	else:
		var until: float = time_until_on(t)
		shimmer = 0.4
		solidity = GHOST
		flame = 0.08
		if until < warn:
			var k2: float = 1.0 - until / warn
			solidity = lerpf(GHOST, 0.75, k2)
			shimmer = lerpf(0.4, 0.9, k2)
			flame = lerpf(0.08, 0.8, k2)
	_mat.set_shader_parameter("solidity", solidity)
	_mat.set_shader_parameter("shimmer", shimmer)
	_mat.set_shader_parameter("glow", lerpf(0.35, 1.15, solidity))
	if _flame_mat != null:
		_flame_mat.albedo_color = Fx.hot(tint, 0.4 + 1.8 * flame)
		_lamp.light_energy = 1.4 * flame


func _process(_dt: float) -> void:
	var t: float = Game.course_time
	_apply(t)
	var on: bool = is_on_at(t)
	var warning: bool = (on and time_until_off(t) < warn) or (not on and time_until_on(t) < warn)
	if warning and not _warned:
		WorldAudio.at(self, "manor_phantom_waver", global_position, 0.6, 30.0)
	_warned = warning
	if on == _fx_on:
		return
	_fx_on = on
	(_form if on else _fade).restart()
	WorldAudio.at(self, "manor_phantom_form" if on else "manor_phantom_fade", global_position, 0.7, 32.0)


func _physics_process(_dt: float) -> void:
	var on: bool = is_on_at(Game.course_time)
	if on != _solid:
		_solid = on
		_shape.set_deferred("disabled", not on)
