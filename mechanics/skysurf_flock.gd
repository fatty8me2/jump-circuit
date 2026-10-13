class_name SkysurfFlock
extends Node3D
## Sky Surf: a FLOCK of birds wheeling over a point in the sky. One MultiMesh drawn with
## visual/skysurf_bird.gdshader, which flies every bird round its circle, banks it into the turn and
## flaps its wings from TIME alone - no per-frame script. Visual only. Add one per part of the
## course; `radius` is the circle the flock wheels on and `height` the band it flies in.

const SHADER: Shader = preload("res://visual/skysurf_bird.gdshader")

static var _mesh: ArrayMesh
static var _mat: ShaderMaterial

var count: int = 12
var radius: float = 26.0
var height: float = 0.0
var tint: Color = Color(1.0, 0.96, 0.92)
var seed_value: int = 1


func build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _bird_mesh()
	mm.instance_count = Fx.count(count)
	for i: int in mm.instance_count:
		mm.set_instance_transform(i, Transform3D.IDENTITY)
		var r: float = radius * rng.randf_range(0.8, 1.2)
		var spd: float = rng.randf_range(0.10, 0.17) / sqrt(maxf(r / 20.0, 0.3))
		mm.set_instance_custom_data(i, Color(rng.randf() * TAU, r, spd, height + rng.randf_range(-3.5, 3.5)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _material(tint)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ext: float = radius * 1.3 + 4.0
	mmi.custom_aabb = AABB(Vector3(-ext, height - 8.0, -ext), Vector3(ext * 2.0, 16.0, ext * 2.0))
	add_child(mmi)
	if WorldAudio.enabled():
		var tm := Timer.new()
		tm.wait_time = 0.12
		tm.timeout.connect(_poll_listener)
		add_child(tm)
		tm.autostart = true


var _inside: bool = false


## SOUND: skysurf_ribbon - a soft whoosh of wings and air as you sweep into the flock's sky (one-shot,
## once per visit)
func _poll_listener() -> void:
	var l: Vector3 = WorldAudio.listener(self)
	if l == Vector3.INF:
		return
	var d: float = l.distance_to(global_position)
	if d < radius + 8.0 and not _inside:
		_inside = true
		WorldAudio.at(self, "skysurf_ribbon", global_position + Vector3(0, height, 0), 0.6, radius * 3.0 + 30.0)
	elif d > radius + 35.0:
		_inside = false


static func _material(tint_col: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("tint", tint_col)
	return m


## A flat "V": a nose at -z, a tail at +z and a wing tip each side (the shader folds the tips).
static func _bird_mesh() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var s: float = 0.55
	var nose := Vector3(0, 0, -0.7) * s
	var tail := Vector3(0, 0, 0.45) * s
	var left := Vector3(-1.2, 0, 0.35) * s
	var right := Vector3(1.2, 0, 0.35) * s
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([nose, left, tail, nose, tail, right])
	_mesh = ArrayMesh.new()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _mesh
