class_name CollapsingPlatform
extends AnimatableBody3D
## Stepping stone that warns, then gives way. Standing on it starts a shake;
## after `delay` it drops out from under the player and returns after `respawn`.
## reset_state() restores it instantly (called on player respawn).

@export var size: Vector3 = Vector3(2.4, 0.4, 2.4)
@export var delay: float = 0.7
@export var respawn: float = 2.6
@export var is_round: bool = true

enum State { IDLE, SHAKING, FALLING, GONE }

var _state: State = State.IDLE
var _timer: float = 0.0
var _vis: MeshInstance3D
var _shape: CollisionShape3D
var _fall_speed: float = 0.0
var _mat: ShaderMaterial


func _ready() -> void:
	sync_to_physics = false
	collision_layer = 1
	collision_mask = 0
	add_to_group("resettable")
	_shape = CollisionShape3D.new()
	if is_round:
		var cyl := CylinderShape3D.new()
		cyl.radius = size.x * 0.5
		cyl.height = size.y
		_shape.shape = cyl
		_vis = Look.platform_round(size.x * 0.5, size.y, "collapse")
	else:
		var box := BoxShape3D.new()
		box.size = size
		_shape.shape = box
		_vis = Look.platform_box(size, "collapse")
	add_child(_shape)
	add_child(_vis)
	_mat = _vis.material_override as ShaderMaterial
	# cracked look: dark radial slits on top
	for i: int in 3:
		var slit := Look.box(Vector3(size.x * 0.8, 0.02, 0.05), Look.flat(Color(0.25, 0.1, 0.1), 0.9), Vector3(0, size.y * 0.5 + 0.005, 0))
		slit.rotation.y = i * PI / 3.0 + 0.3
		_vis.add_child(slit)


## Player contract: called every tick while stood on.
func apply_rider_load(_point: Vector3, _force: float) -> void:
	if _state == State.IDLE:
		_state = State.SHAKING
		_timer = 0.0
		Sfx.play_at("crumble", global_position)


func reset_state() -> void:
	_state = State.IDLE
	_timer = 0.0
	_fall_speed = 0.0
	_vis.position = Vector3.ZERO
	_vis.rotation = Vector3.ZERO
	_vis.scale = Vector3.ONE
	_vis.visible = true
	_mat.set_shader_parameter("trim_glow", 0.5)
	_shape.set_deferred("disabled", false)


func _physics_process(dt: float) -> void:
	match _state:
		State.SHAKING:
			_timer += dt
			var k: float = _timer / delay
			var amp: float = 0.025 + 0.06 * k
			_vis.position = Vector3(sin(_timer * 71.0), sin(_timer * 53.0) * 0.4 - k * 0.12, cos(_timer * 63.0)) * amp
			_vis.rotation = Vector3(sin(_timer * 47.0), 0, cos(_timer * 59.0)) * amp * 0.6
			_mat.set_shader_parameter("trim_glow", 0.5 + 5.0 * k * (0.5 + 0.5 * sin(_timer * 30.0)))
			if _timer >= delay:
				_state = State.FALLING
				_timer = 0.0
				_shape.set_deferred("disabled", true)
				Sfx.play_at("collapse", global_position)
		State.FALLING:
			_timer += dt
			_fall_speed += 30.0 * dt
			_vis.position.y -= _fall_speed * dt
			_vis.rotation.x += dt * 1.3
			_vis.scale = Vector3.ONE * maxf(1.0 - _timer * 0.8, 0.05)
			if _timer > 1.1:
				_state = State.GONE
				_vis.visible = false
				_timer = 0.0
		State.GONE:
			_timer += dt
			if _timer >= respawn:
				reset_state()
				_vis.scale = Vector3.ONE * 0.05
				var tw: Tween = create_tween()
				tw.tween_property(_vis, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
