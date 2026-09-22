class_name BlinkPlatform
extends AnimatableBody3D
## Appears and disappears on a fixed rhythm driven by Game.course_time
## (identical for every racer). Flickers for `warn` seconds before vanishing.

@export var size: Vector3 = Vector3(2.5, 0.4, 2.5)
@export var period: float = 3.0
@export var on_fraction: float = 0.55
@export var phase: float = 0.0
@export var warn: float = 0.5

var _shape: CollisionShape3D
var _vis: MeshInstance3D
var _ghost: MeshInstance3D
var _solid: bool = true


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
	gm.albedo_color = Color(ac.r, ac.g, ac.b, 0.13)
	_ghost = Look.box(size, gm)
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ghost)


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
