class_name BlinkPlatform
extends AnimatableBody3D
## Appears and disappears on a fixed rhythm driven by Game.course_time
## (identical for every racer). Flickers for `warn` seconds before vanishing;
## while gone its ghost outline pulses in for `warn` seconds before it returns.

@export var size: Vector3 = Vector3(2.5, 0.4, 2.5)
@export var period: float = 3.0
@export var on_fraction: float = 0.55
@export var phase: float = 0.0
@export var warn: float = 0.5

const GHOST_ALPHA: float = 0.13
const GHOST_ALPHA_WARN: float = 0.5

var _shape: CollisionShape3D
var _vis: MeshInstance3D
var _ghost: MeshInstance3D
var _ghost_mat: StandardMaterial3D
var _solid: bool = true
# effects (visual only): the slab dissolves into rising motes as it goes, and motes
# gather in to it as it returns
var _dissolve: GPUParticles3D
var _gather: GPUParticles3D
var _fx_on: bool = true


func _ready() -> void:
	sync_to_physics = false
	collision_layer = 1
	collision_mask = 0
	var box := BoxShape3D.new()
	box.size = size
	_shape = CollisionShape3D.new()
	_shape.shape = box
	add_child(_shape)
	_vis = Look.platform_box(size, "mover")
	add_child(_vis)
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var ac: Color = Look.c("accent2")
	gm.albedo_color = Color(ac.r, ac.g, ac.b, GHOST_ALPHA)
	_ghost_mat = gm
	_ghost = Look.box(size, gm)
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ghost)
	_build_fx()


func _build_fx() -> void:
	var ac: Color = Look.c("accent2")
	var hot: Color = Fx.hot(ac.lerp(Color.WHITE, 0.3), 2.2)
	var n: int = clampi(int(size.x * size.z * 5.0), 16, 50)
	var vis := AABB(-size * 0.5 - Vector3(2, 2, 2), size + Vector3(4, 6, 4))
	_dissolve = Fx.burst({"amount": n, "lifetime": 0.8, "explosiveness": 0.7, "shape": "box",
		"extents": size * 0.5, "dir": Vector3.UP, "spread": 50.0, "speed": Vector2(0.4, 1.8),
		"gravity": Vector3(0, 1.2, 0), "damping": Vector2(0.5, 1.5), "size": 0.2, "tex": Fx.Tex.STAR,
		"color": hot, "turbulence": 0.5, "aabb": vis})
	add_child(_dissolve)
	_gather = Fx.burst({"amount": n, "lifetime": 0.4, "explosiveness": 0.9, "shape": "box",
		"extents": size * 0.5 + Vector3(0.9, 0.6, 0.9), "speed": Vector2.ZERO, "radial": Vector2(-14.0, -9.0),
		"size": 0.18, "tex": Fx.Tex.STAR, "curve": "pop", "color": hot, "aabb": vis})
	add_child(_gather)
	_fx_on = is_on_at(Game.course_time)


func _process(_dt: float) -> void:
	var on: bool = is_on_at(Game.course_time)
	if on == _fx_on:
		return
	_fx_on = on
	(_dissolve if not on else _gather).restart()


func is_on_at(time: float) -> bool:
	return fposmod(time / period + phase, 1.0) < on_fraction


func _physics_process(_dt: float) -> void:
	var u: float = fposmod(Game.course_time / period + phase, 1.0)
	var on: bool = u < on_fraction
	if on != _solid:
		_solid = on
		_shape.set_deferred("disabled", not on)
	var left: float = (on_fraction - u) * period
	_vis.visible = on and (left > warn or fmod(left, 0.16) > 0.08)
	_ghost.visible = not _vis.visible
	# return telegraph: the ghost fills in, pulsing on the vanish flicker's rhythm
	var ghost_a: float = GHOST_ALPHA
	if not on:
		var until_on: float = (1.0 - u) * period
		if until_on < warn:
			var k: float = 1.0 - until_on / warn
			ghost_a = lerpf(GHOST_ALPHA, GHOST_ALPHA_WARN, k) * (1.0 if fmod(until_on, 0.16) > 0.08 else 0.6)
	if not is_equal_approx(_ghost_mat.albedo_color.a, ghost_a):
		var col: Color = _ghost_mat.albedo_color
		col.a = ghost_a
		_ghost_mat.albedo_color = col
