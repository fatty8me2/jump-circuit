class_name Bumper
extends Area3D
## Pinball bumper post: touching it throws you directly away at a fixed speed
## with a little lift. Same contact, same result - routes can be built on it.

@export var radius: float = 0.9
@export var height: float = 1.6
@export var strength: float = 16.0
@export var lift: float = 8.0

var _cool: float = 0.0
var _vis: Node3D
var _pulse: float = 0.0
# effects (visual only): a bright shell that flashes on a hit and a spray of sparks
var _flash_mat: StandardMaterial3D
var _flash_shell: MeshInstance3D
var _hit_sparks: GPUParticles3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitorable = false
	var shape := CylinderShape3D.new()
	shape.radius = radius + 0.15
	shape.height = height
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, height * 0.5, 0)
	add_child(cs)
	_vis = Node3D.new()
	add_child(_vis)
	var cap: StandardMaterial3D = Look.flat(Color(0.12, 0.12, 0.18), 0.4, 0.6)
	_vis.add_child(Look.cylinder(radius, height, Look.flat(Color(0.95, 0.3, 0.75), 0.35, 0.2, 1.2), Vector3(0, height * 0.5, 0), radius * 0.85, 20))
	_vis.add_child(Look.cylinder(radius * 1.15, 0.2, cap, Vector3(0, height + 0.1, 0), -1.0, 20))
	_vis.add_child(Look.cylinder(radius * 1.15, 0.2, cap, Vector3(0, 0.1, 0), -1.0, 20))
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flash_mat.albedo_color = Color(1.0, 0.55, 0.9, 0.0)
	_flash_shell = Look.cylinder(radius * 1.04, height * 0.96, _flash_mat, Vector3(0, height * 0.5, 0), radius * 0.9, 20)
	_flash_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash_shell.visible = false
	_vis.add_child(_flash_shell)
	_hit_sparks = Fx.sparks({"amount": 30, "lifetime": 0.45, "dir": Vector3.UP, "spread": 60.0,
		"speed": Vector2(4.0, 10.0), "damping": Vector2(2.0, 4.0), "gravity": Vector3(0, -10, 0),
		"color": Color(3.0, 1.2, 2.4), "aabb": AABB(Vector3(-5, -3, -5), Vector3(10, 8, 10))})
	_hit_sparks.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_hit_sparks)


## A hit: the post flashes and sparks spray off the side that was struck.
func _hit_fx(away: Vector3, at_y: float) -> void:
	var dir: Vector3 = away.normalized()
	var y: float = clampf(at_y - global_position.y, 0.3, height - 0.2)
	Fx.fire(_hit_sparks, global_position + dir * (radius + 0.1) + Vector3(0, y, 0), Fx.basis_up(dir))
	_flash_shell.visible = true
	_flash_mat.albedo_color.a = 0.9
	var tw: Tween = create_tween()
	tw.tween_property(_flash_mat, "albedo_color:a", 0.0, 0.3).set_ease(Tween.EASE_OUT)
	tw.tween_callback(_flash_shell.hide)


func _physics_process(dt: float) -> void:
	_cool = maxf(_cool - dt, 0.0)
	_pulse = maxf(_pulse - dt * 4.0, 0.0)
	_vis.scale = Vector3(1.0 + _pulse * 0.25, 1.0, 1.0 + _pulse * 0.25)
	if _cool > 0.0:
		return
	for body: Node3D in get_overlapping_bodies():
		if body is Player:
			var p := body as Player
			var away: Vector3 = p.global_position - global_position
			away.y = 0.0
			if away.length() < 0.05:
				away = Vector3.FORWARD
			p.knockback(away.normalized() * strength + Vector3(0, lift, 0))
			_cool = 0.25
			_pulse = 1.0
			Sfx.play_at("bounce", global_position, 0.05, 0.9)
			_hit_fx(away, p.global_position.y + 0.6)
