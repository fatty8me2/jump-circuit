class_name GlacierThinIce
extends AnimatableBody3D
## Frostbite Pass: THIN ICE. A clear pane over a crevasse. Step on it and white cracks spread
## out from your first footprint; `delay` seconds later it shatters into falling chunks and
## is gone, then freezes back over after `respawn`. Keep moving. Chains of panes make ice
## bridges you can only cross at a run. reset_state() restores it at once (player respawn).
## Positioned by the centre of its top surface's underside like CollapsingPlatform (kit style:
## place with GlacierThinIce.make or set position = top - (0, size.y / 2, 0)).

const SHADER: Shader = preload("res://visual/glacier_thin_ice.gdshader")

@export var size: Vector3 = Vector3(2.4, 0.3, 2.4)
@export var delay: float = 0.6
@export var respawn: float = 2.6

enum State { IDLE, CRACKING, GONE }

var _state: int = State.IDLE
var _timer: float = 0.0
var _shape: CollisionShape3D
var _vis: MeshInstance3D
var _mat: ShaderMaterial
var _cracked_twice: bool = false
var _shards: GPUParticles3D
var _spray: GPUParticles3D
var _puff: GPUParticles3D
var _grit: GPUParticles3D
var _fade_tw: Tween


func _ready() -> void:
	sync_to_physics = false
	collision_layer = 1
	collision_mask = 0
	add_to_group("resettable")
	var box := BoxShape3D.new()
	box.size = size
	_shape = CollisionShape3D.new()
	_shape.shape = box
	add_child(_shape)
	var bm := BoxMesh.new()
	bm.size = size
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("half_size", size * 0.5)
	_vis = Look.mesh_node(bm, _mat)
	add_child(_vis)
	# a frosted rim of rime along the edges so the pane reads against the crevasse below
	var rim: StandardMaterial3D = GlacierFx.ice_mat(GlacierFx.SNOW, 0.35, 0.9)
	for sx: float in [-1.0, 1.0]:
		_vis.add_child(Look.box(Vector3(0.12, size.y + 0.04, size.z), rim, Vector3(sx * (size.x * 0.5 - 0.06), 0.01, 0)))
	for sz: float in [-1.0, 1.0]:
		_vis.add_child(Look.box(Vector3(size.x, size.y + 0.04, 0.12), rim, Vector3(0, 0.01, sz * (size.z * 0.5 - 0.06))))
	_build_fx()


func _build_fx() -> void:
	var ext := Vector3(size.x * 0.45, size.y * 0.5, size.z * 0.45)
	_shards = GlacierFx.shards(ext, clampi(int(size.x * size.z * 4.0), 12, 30), 0.24)
	add_child(_shards)
	_spray = GlacierFx.frost_burst(GlacierFx.GLOW, 24, 5.0)
	add_child(_spray)
	_puff = GlacierFx.powder(maxf(size.x, size.z) * 0.35, 10, 1.2)
	add_child(_puff)
	# rime sifting off the underside while it cracks
	_grit = Fx.emitter({"amount": clampi(int(size.x * size.z * 3.0), 8, 24), "lifetime": 0.9, "emitting": false,
		"shape": "box", "extents": Vector3(size.x * 0.4, 0.02, size.z * 0.4), "dir": Vector3.DOWN, "spread": 15.0,
		"speed": Vector2(0.3, 1.2), "gravity": Vector3(0, -12, 0), "additive": false, "size": 0.1,
		"color": Color(0.95, 0.98, 1.0, 0.9), "fade": PackedFloat32Array([1.0, 1.0, 0.0]),
		"aabb": AABB(Vector3(-size.x - 2, -12, -size.z - 2), Vector3(size.x * 2 + 4, 16, size.z * 2 + 4))})
	_grit.position = Vector3(0, -size.y * 0.5 - 0.02, 0)
	add_child(_grit)


## Player contract: called every tick while stood on.
func apply_rider_load(point: Vector3, _force: float) -> void:
	if _state != State.IDLE:
		return
	_state = State.CRACKING
	_timer = 0.0
	_cracked_twice = false
	var o: Vector3 = to_local(point)
	_mat.set_shader_parameter("origin", Vector2(o.x, o.z))
	_grit.emitting = true
	WorldAudio.at(self, "ice_crack", global_position, 0.9, 35.0)


func is_solid() -> bool:
	return _state != State.GONE


func reset_state() -> void:
	_state = State.IDLE
	_timer = 0.0
	_shape.set_deferred("disabled", false)
	_vis.visible = true
	_vis.position = Vector3.ZERO
	_mat.set_shader_parameter("crack", 0.0)
	_mat.set_shader_parameter("fade", 1.0)
	_grit.emitting = false
	if _fade_tw != null and _fade_tw.is_valid():
		_fade_tw.kill()
	_vis.reset_physics_interpolation()


func _physics_process(dt: float) -> void:
	match _state:
		State.CRACKING:
			_timer += dt
			var k: float = clampf(_timer / delay, 0.0, 1.0)
			_mat.set_shader_parameter("crack", k)
			var amp: float = 0.01 + 0.035 * k
			_vis.position = Vector3(sin(_timer * 67.0), -k * 0.05, cos(_timer * 59.0)) * amp
			if not _cracked_twice and k > 0.6:
				_cracked_twice = true
				WorldAudio.at(self, "ice_crack", global_position, 1.0, 35.0, 0.12)
			if _timer >= delay:
				_state = State.GONE
				_timer = 0.0
				_shape.set_deferred("disabled", true)
				_vis.visible = false
				_grit.emitting = false
				_shards.restart()
				_spray.restart()
				_puff.restart()
				WorldAudio.at(self, "ice_break", global_position, 1.0, 45.0)
		State.GONE:
			_timer += dt
			if _timer >= respawn:
				reset_state()
				_mat.set_shader_parameter("fade", 0.0)
				_fade_tw = create_tween()
				_fade_tw.tween_method(func(v: float) -> void: _mat.set_shader_parameter("fade", v), 0.0, 1.0, 0.35)
				WorldAudio.at(self, "platform_reform", global_position, 0.5, 30.0)
