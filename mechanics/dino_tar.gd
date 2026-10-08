class_name DinoTar
extends AnimatableBody3D
## Dino Valley: a TAR PIT. A black, bubbling bed of tar you can walk across - slowly. While you stand
## on it your running speed drops to `slow` of normal and the tar SWALLOWS you at `sink_rate` m/s: it
## sinks under your feet until it has sunk `sink_max` m, and then it drags you back to the checkpoint.
## Step off and it heaves back up at `rise_rate` m/s. So cross it without dawdling (sinking is
## slow enough to cross ~9 m at the reduced speed), or hop from stone to stone across the narrow
## pits. The tell is plain: the surface bubbles faster and glows a warning red as you go down, the
## tar glugs at 60 %, and a bone-white marker post stands in the rim at the depth that kills.
## Positioned like a platform: `top` is the centre of its top surface at rest.

@export var size: Vector3 = Vector3(6.0, 1.4, 6.0)
@export var slow: float = 0.55
@export var sink_rate: float = 0.45
@export var sink_max: float = 1.4
@export var rise_rate: float = 1.0

var depth: float = 0.0
var _origin: Vector3
var _area: Area3D
var _mat: ShaderMaterial
var _victim: Player = null
var _saved_speed: float = 1.0
var _slowed: bool = false
var _bubbles: GPUParticles3D
var _spit: GPUParticles3D
var _glugged: bool = false


func _ready() -> void:
	sync_to_physics = false
	collision_layer = 1
	collision_mask = 0
	_origin = position
	var box := BoxShape3D.new()
	box.size = size
	var cs := CollisionShape3D.new()
	cs.shape = box
	add_child(cs)
	var bm := BoxMesh.new()
	bm.size = size
	bm.subdivide_width = maxi(int(size.x), 1)
	bm.subdivide_depth = maxi(int(size.z), 1)
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://visual/dino_tar.gdshader")
	_mat.set_shader_parameter("half_size", size * 0.5)
	mi.material_override = _mat
	add_child(mi)
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 2
	_area.monitorable = false
	var ash := BoxShape3D.new()
	ash.size = Vector3(size.x, 1.2, size.z)
	var acs := CollisionShape3D.new()
	acs.shape = ash
	acs.position = Vector3(0, size.y * 0.5 + 0.5, 0)
	_area.add_child(acs)
	add_child(_area)
	var vis := AABB(Vector3(-size.x, -2.0, -size.z), Vector3(size.x * 2.0, 6.0, size.z * 2.0))
	_bubbles = Fx.emitter({"amount": clampi(int(size.x * size.z * 0.5), 6, 40), "lifetime": 1.0, "shape": "box",
		"extents": Vector3(size.x * 0.45, 0.02, size.z * 0.45), "dir": Vector3.UP, "spread": 20.0,
		"speed": Vector2(0.4, 1.4), "gravity": Vector3(0, -3, 0), "tex": Fx.Tex.BUBBLE, "additive": false,
		"size": 0.34, "scale": Vector2(0.4, 1.2), "color": Color(0.12, 0.1, 0.13, 0.9),
		"fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]), "aabb": vis, "preprocess": 1.0})
	_bubbles.position = Vector3(0, size.y * 0.5 + 0.03, 0)
	add_child(_bubbles)
	# the occasional big blob that pops and throws dark drops
	_spit = Fx.debris({"amount": 14, "lifetime": 0.7, "one_shot": true, "emitting": false, "shape": "sphere",
		"radius": 0.3, "dir": Vector3.UP, "spread": 40.0, "speed": Vector2(2.0, 5.0), "gravity": Vector3(0, -12, 0),
		"color": Color(0.07, 0.06, 0.08), "chunk": 0.12, "aabb": vis})
	_spit.position = Vector3(0, size.y * 0.5 + 0.1, 0)
	add_child(_spit)
	add_to_group("resettable")
	_dress()


func _dress() -> void:
	# a rim of mud-caked rock round the pit and a pale bone post at the corner
	var rock: StandardMaterial3D = Look.flat(Color(0.36, 0.3, 0.24), 0.95)
	var bone: StandardMaterial3D = Look.flat(Color(0.93, 0.9, 0.78), 0.6)
	var top: float = size.y * 0.5
	var hx: float = size.x * 0.5
	var hz: float = size.z * 0.5
	for sx: float in [-1.0, 1.0]:
		var wall := Look.box(Vector3(0.45, 0.5, size.z + 0.9), rock, Vector3(sx * (hx + 0.2), top - 0.1, 0))
		wall.top_level = true
		add_child(wall)
		wall.global_position = global_position + Vector3(sx * (hx + 0.2), top - 0.1, 0)
	for sz: float in [-1.0, 1.0]:
		var wall2 := Look.box(Vector3(size.x + 0.9, 0.5, 0.45), rock, Vector3(0, top - 0.1, sz * (hz + 0.2)))
		wall2.top_level = true
		add_child(wall2)
		wall2.global_position = global_position + Vector3(0, top - 0.1, sz * (hz + 0.2))
	var post := Look.cylinder(0.07, 1.3, bone, Vector3.ZERO, 0.05, 6)
	post.top_level = true
	add_child(post)
	post.global_position = global_position + Vector3(hx + 0.1, top + 0.3, hz + 0.1)


func _stood_on() -> Player:
	var p: Player = KitUtil.player_in(_area)
	if p != null and p.grounded and p.floor_body == self:
		return p
	return null


func _physics_process(dt: float) -> void:
	var p: Player = _stood_on()
	if p != null:
		if not _slowed:
			_slowed = true
			_victim = p
			_saved_speed = p.speed_mult
			p.speed_mult = minf(_saved_speed, slow)
		depth = minf(depth + sink_rate * dt, sink_max)
		if depth >= sink_max - 0.01:
			_release()
			depth = 0.0
			position = _origin
			KitUtil.kill(self, "hazard")
			return
	else:
		if _slowed:
			_release()
		depth = maxf(depth - rise_rate * dt, 0.0)
	var k: float = depth / maxf(sink_max, 0.1)
	if k > 0.6 and not _glugged:
		_glugged = true
		WorldAudio.at(self, "dino_tar_glug", global_position + Vector3(0, size.y * 0.5, 0), 0.9, 30.0)
		_spit.restart()
		_spit.emitting = true
	elif k < 0.2:
		_glugged = false
	position = _origin - Vector3(0, depth, 0)
	_mat.set_shader_parameter("danger", clampf((k - 0.15) / 0.85, 0.0, 1.0))
	_bubbles.speed_scale = 1.0 + 2.5 * k


func _release() -> void:
	if _slowed and _victim != null and is_instance_valid(_victim):
		_victim.speed_mult = _saved_speed
	_slowed = false
	_victim = null


func reset_state() -> void:
	_release()
	depth = 0.0
	position = _origin
	_glugged = false
	reset_physics_interpolation()
