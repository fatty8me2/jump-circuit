class_name ReefSchool
extends MultiMeshInstance3D
## Coral Depths, visual only: a school of small fish circling a drifting centre. Each fish
## follows its own ellipse around the school with a little vertical weave; the school
## itself wanders on a slow Lissajous path. One MultiMesh per school.

@export var count: int = 36
@export var radius: float = 4.0
@export var wander: Vector3 = Vector3(10, 2, 10)
@export var speed: float = 0.5
@export var color_a: Color = Color(0.95, 0.85, 0.35)
@export var color_b: Color = Color(0.5, 0.85, 1.0)
@export var fish_scale: float = 1.0

var _r: PackedFloat32Array = PackedFloat32Array()
var _ph: PackedFloat32Array = PackedFloat32Array()
var _h: PackedFloat32Array = PackedFloat32Array()
var _sp: PackedFloat32Array = PackedFloat32Array()
var _seed: float = 0.0


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(global_position)
	_seed = rng.randf() * 100.0
	var mesh := PrismMesh.new()
	mesh.size = Vector3(0.18, 0.5, 0.06)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.3
	mat.metallic = 0.5
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.8, 0.9)
	mat.emission_energy_multiplier = 0.35
	mesh.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = count
	for i: int in count:
		_r.append(radius * rng.randf_range(0.45, 1.0))
		_ph.append(rng.randf() * TAU)
		_h.append(rng.randf_range(-1.2, 1.2))
		_sp.append(rng.randf_range(0.85, 1.15))
		mm.set_instance_color(i, color_a.lerp(color_b, rng.randf()))
	multimesh = mm
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(-wander - Vector3.ONE * (radius + 2.0), (wander + Vector3.ONE * (radius + 2.0)) * 2.0)
	_update(0.0)


func _process(_dt: float) -> void:
	_update(Time.get_ticks_msec() * 0.001)


func _update(t: float) -> void:
	var ts: float = t * speed + _seed
	var centre := Vector3(sin(ts * 0.23) * wander.x, sin(ts * 0.31 + 1.0) * wander.y, sin(ts * 0.17 + 2.0) * wander.z)
	var mm: MultiMesh = multimesh
	for i: int in count:
		var a: float = ts * 1.6 * _sp[i] + _ph[i]
		var r: float = _r[i]
		var p := centre + Vector3(cos(a) * r, _h[i] + sin(a * 2.0 + _ph[i]) * 0.35, sin(a) * r * 0.7)
		# heading = derivative of the ellipse
		var fwd := Vector3(-sin(a) * r, cos(a * 2.0 + _ph[i]) * 0.7, cos(a) * r * 0.7).normalized()
		# prism tip is local +Y: point it along the swim direction
		var up: Vector3 = fwd
		var side: Vector3 = up.cross(Vector3.UP)
		if side.length() < 0.01:
			side = Vector3.RIGHT
		side = side.normalized()
		var b := Basis(side, up, side.cross(up)).scaled(Vector3.ONE * fish_scale)
		mm.set_instance_transform(i, Transform3D(b, p))
