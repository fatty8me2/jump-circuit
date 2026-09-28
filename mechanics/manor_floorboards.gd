class_name ManorFloorboards
extends CollapsingPlatform
## Phantom Manor: rotten floorboards. A patch of old oak planks over a hole in the floor that
## creaks and sags when you step on it, then snaps and drops into the dark `delay` s later and
## grows back `respawn` s after that (CollapsingPlatform's rules and reset). Only the look and
## the sounds are the manor's: dark boards with gaps between them and a glowing green crack
## that flares as they give. Positioned by the centre of the patch's top.

const SURFACE: Shader = preload("res://visual/manor_stone.gdshader")

var _creaked: bool = false
var _was: int = 0


func _ready() -> void:
	sync_to_physics = false
	collision_layer = 1
	collision_mask = 0
	is_round = false
	add_to_group("resettable")
	_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	_shape.shape = box
	add_child(_shape)
	# the joists: a slab in the manor's floorboard shader (wood = 1) under a deck of loose boards;
	# the boards' tops are flush with the collider's top (+size.y / 2)
	var sy: float = size.y - 0.06
	var bm := BoxMesh.new()
	bm.size = Vector3(size.x, sy, size.z)
	_mat = ShaderMaterial.new()
	_mat.shader = SURFACE
	_mat.set_shader_parameter("top_color", Color(0.4, 0.3, 0.24))
	_mat.set_shader_parameter("side_color", Color(0.2, 0.13, 0.1))
	_mat.set_shader_parameter("trim_color", Color(0.6, 1.0, 0.55))
	_mat.set_shader_parameter("half_size", Vector3(size.x, sy, size.z) * 0.5)
	_mat.set_shader_parameter("wood", 1.0)
	_mat.set_shader_parameter("wood_color", Color(0.3, 0.2, 0.15))
	_mat.set_shader_parameter("trim_glow", 0.5)
	_vis = MeshInstance3D.new()
	add_child(_vis)
	var slab := MeshInstance3D.new()
	slab.mesh = bm
	slab.material_override = _mat
	slab.position = Vector3(0, -0.03, 0)
	_vis.add_child(slab)
	var deck: float = size.y * 0.5 - 0.03
	var plank: StandardMaterial3D = Look.flat(Color(0.3, 0.2, 0.15), 0.8)
	var gap: StandardMaterial3D = Look.flat(Color(0.02, 0.015, 0.02), 1.0)
	var along_x: bool = size.x >= size.z
	var width: float = size.z if along_x else size.x
	var n: int = maxi(int(width / 0.32), 3)
	var w: float = width / float(n)
	for i: int in n:
		var off: float = -width * 0.5 + (float(i) + 0.5) * w
		var ps := Vector3(size.x, 0.06, w - 0.05) if along_x else Vector3(w - 0.05, 0.06, size.z)
		var pp := Vector3(0, deck, off) if along_x else Vector3(off, deck, 0)
		_vis.add_child(Look.box(ps, plank, pp))
		if i > 0:
			var gs := Vector3(size.x, 0.065, 0.045) if along_x else Vector3(0.045, 0.065, size.z)
			var gp := Vector3(0, deck, off - w * 0.5) if along_x else Vector3(off - w * 0.5, deck, 0)
			_vis.add_child(Look.box(gs, gap, gp))
	# the crack: a zig-zag of green light across the boards
	var crack := StandardMaterial3D.new()
	crack.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	crack.albedo_color = Color(0.9, 2.0, 0.9)
	for i: int in 4:
		var c := Look.box(Vector3(size.x * 0.34, 0.02, 0.04), crack, Vector3(-size.x * 0.33 + float(i) * size.x * 0.22, deck + 0.035, 0.18 * (1.0 if i % 2 == 0 else -1.0)))
		c.rotation.y = 0.5 if i % 2 == 0 else -0.5
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_vis.add_child(c)
	_build_fx()


func apply_rider_load(point: Vector3, force: float) -> void:
	if _state == State.IDLE and not _creaked:
		_creaked = true
		WorldAudio.at(self, "manor_board_creak", global_position, 0.9, 30.0)
	super.apply_rider_load(point, force)


func reset_state() -> void:
	super.reset_state()
	_creaked = false


func _physics_process(dt: float) -> void:
	super._physics_process(dt)
	if int(_state) != _was:
		if _state == State.FALLING:
			WorldAudio.at(self, "manor_board_snap", global_position, 1.0, 34.0)
		_was = int(_state)
