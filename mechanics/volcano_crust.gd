class_name VolcanoCrust
extends AnimatableBody3D
## Cinder Peak: a raft of cooled crust floating on a lava river. Land on it and it cracks -
## glowing fractures spread across it and it shudders - then after `delay` it breaks up and
## founders into the melt, and a fresh raft cools back into place after `respawn`.
## Rider-driven, restored instantly on the player's respawn. Positioned at its TOP centre.

@export var size: Vector3 = Vector3(2.4, 0.4, 2.4)
@export var delay: float = 0.8
@export var respawn: float = 2.8

enum State { IDLE, CRACKING, BREAKING, GONE, FORMING }

var _state: State = State.IDLE
var _timer: float = 0.0
var _vis: Node3D
var _shape: CollisionShape3D
var _crack_mat: StandardMaterial3D
var _slab_mat: StandardMaterial3D
var _grit: GPUParticles3D
var _splash: GPUParticles3D
var _puff: GPUParticles3D


func _ready() -> void:
	sync_to_physics = false
	collision_layer = 1
	collision_mask = 0
	add_to_group("resettable")
	_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	_shape.shape = box
	_shape.position = Vector3(0, -size.y * 0.5, 0)
	add_child(_shape)
	_build_visual()


## Player contract: called every tick while stood on.
func apply_rider_load(_point: Vector3, _force: float) -> void:
	if _state == State.IDLE:
		_state = State.CRACKING
		_timer = 0.0
		_grit.emitting = true
		WorldAudio.at(self, "crust_crack", global_position, 0.9, 35.0)


func reset_state() -> void:
	_state = State.IDLE
	_timer = 0.0
	_vis.position = Vector3.ZERO
	_vis.rotation = Vector3.ZERO
	_vis.scale = Vector3.ONE
	_vis.visible = true
	_crack_mat.emission_energy_multiplier = 0.25
	_slab_mat.emission_energy_multiplier = 0.0
	_shape.set_deferred("disabled", false)
	_grit.emitting = false
	_vis.reset_physics_interpolation()


func _physics_process(dt: float) -> void:
	match _state:
		State.CRACKING:
			_timer += dt
			var k: float = _timer / delay
			var amp: float = 0.02 + 0.07 * k
			_vis.position = Vector3(sin(_timer * 67.0), -k * 0.08, cos(_timer * 59.0)) * amp
			_vis.rotation = Vector3(sin(_timer * 41.0), 0, cos(_timer * 53.0)) * amp * 0.5
			_crack_mat.emission_energy_multiplier = 0.4 + 6.0 * k * (0.6 + 0.4 * sin(_timer * 28.0))
			_slab_mat.emission_energy_multiplier = 0.8 * k
			if _timer >= delay:
				_state = State.BREAKING
				_timer = 0.0
				_shape.set_deferred("disabled", true)
				_grit.emitting = false
				_splash.restart()
				_puff.restart()
				WorldAudio.at(self, "crust_break", global_position, 1.0, 40.0)
		State.BREAKING:
			_timer += dt
			_vis.position.y -= (0.6 + _timer * 2.0) * dt
			_vis.rotation.x += dt * 0.7
			_vis.rotation.z -= dt * 0.4
			_slab_mat.emission_energy_multiplier = 0.8 + _timer * 2.0
			if _timer > 1.0:
				_state = State.GONE
				_vis.visible = false
				_timer = 0.0
		State.GONE:
			_timer += dt
			if _timer >= respawn:
				reset_state()
				_state = State.FORMING
				_timer = 0.0
				_vis.position.y = -0.35
				_slab_mat.emission_energy_multiplier = 2.5
				WorldAudio.at(self, "platform_reform", global_position, 0.4, 30.0)
		State.FORMING:
			# a fresh raft surfaces glowing and cools (solid already)
			_timer += dt
			var k2: float = clampf(_timer / 0.6, 0.0, 1.0)
			_vis.position.y = -0.35 * (1.0 - k2)
			_slab_mat.emission_energy_multiplier = 2.5 * (1.0 - k2)
			if k2 >= 1.0:
				_state = State.IDLE


func _build_visual() -> void:
	_vis = Node3D.new()
	add_child(_vis)
	# the raft: dark crust, a slightly lighter rim so its edge reads against the melt
	_slab_mat = StandardMaterial3D.new()
	_slab_mat.albedo_color = Color(0.2, 0.15, 0.14)
	_slab_mat.roughness = 0.92
	_slab_mat.emission_enabled = true
	_slab_mat.emission = Color(1.0, 0.3, 0.05)
	_slab_mat.emission_energy_multiplier = 0.0
	var slab := Look.box(size, _slab_mat, Vector3(0, -size.y * 0.5, 0))
	_vis.add_child(slab)
	var rim_mat := Look.flat(Color(0.42, 0.34, 0.3), 0.85)
	for sz: float in [-1.0, 1.0]:
		_vis.add_child(Look.box(Vector3(size.x, 0.06, 0.16), rim_mat, Vector3(0, 0.02, sz * (size.z * 0.5 - 0.08))))
		_vis.add_child(Look.box(Vector3(0.16, 0.06, size.z), rim_mat, Vector3(sz * (size.x * 0.5 - 0.08), 0.02, 0)))
	# the fracture web that lights up as it cracks
	_crack_mat = StandardMaterial3D.new()
	_crack_mat.albedo_color = Color(0.3, 0.06, 0.02)
	_crack_mat.emission_enabled = true
	_crack_mat.emission = Color(1.0, 0.42, 0.08)
	_crack_mat.emission_energy_multiplier = 0.25
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absf(position.x * 13.0 + position.z * 7.0)) + 1
	for i: int in 5:
		var crack_len: float = rng.randf_range(0.45, 0.8) * minf(size.x, size.z)
		var c := Look.box(Vector3(crack_len, 0.02, 0.06), _crack_mat, Vector3(rng.randf_range(-0.25, 0.25) * size.x, 0.012, rng.randf_range(-0.25, 0.25) * size.z))
		c.rotation.y = rng.randf() * PI
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_vis.add_child(c)
	var vis := AABB(Vector3(-size.x - 3.0, -8.0, -size.z - 3.0), Vector3(size.x * 2.0 + 6.0, 14.0, size.z * 2.0 + 6.0))
	_grit = Fx.emitter({"amount": 14, "lifetime": 0.6, "emitting": false, "shape": "box",
		"extents": Vector3(size.x * 0.4, 0.02, size.z * 0.4), "dir": Vector3.UP, "spread": 30.0, "speed": Vector2(0.5, 1.8),
		"gravity": Vector3(0, -6.0, 0), "size": 0.12, "curve": "shrink", "color": Color(3.0, 1.1, 0.3), "aabb": vis})
	add_child(_grit)
	_splash = VolcanoFx.splash(self, Vector3(0, -0.2, 0), maxf(size.x, size.z) * 0.5, 30, 5.5)
	_puff = VolcanoFx.puff(self, Vector3(0, 0.2, 0), maxf(size.x, size.z) * 0.5, 10, Color(0.5, 0.45, 0.42, 0.5))
