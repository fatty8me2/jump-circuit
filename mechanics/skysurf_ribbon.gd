class_name SkysurfRibbon
extends Node3D
## Sky Surf: a WIND RIBBON - a long translucent strip that streams through the air along a line,
## rippling in the wind with bright pulses running in the direction of travel. The flow line is
## dressed with them so the way through the sky reads at 25 m/s, and they twist round the grind
## rails. Purely visual (no collision): the pulses are a function of TIME only. `points` are world
## positions of the ribbon's spine; the strip is a Catmull-Rom curve through them.

const SHADER: Shader = preload("res://visual/skysurf_ribbon.gdshader")

var points: PackedVector3Array = PackedVector3Array()
var width: float = 1.6
var color_a: Color = Color(1.0, 0.62, 0.7)
var color_b: Color = Color(1.0, 0.95, 0.8)
var speed: float = 6.0
var wave: float = 0.35
var strength: float = 0.7
var twist: float = 0.9
var phase: float = 0.0
## The strip's width runs along tangent x up_hint: UP gives a ribbon lying flat, a horizontal
## vector across a vertical arch gives a band in the arch's own plane.
var up_hint: Vector3 = Vector3.UP
## Metres between cross-sections.
var step: float = 1.3


## Build the strip. Call once after setting the fields, before or after adding to the tree.
func build() -> void:
	if points.size() < 2:
		return
	var curve: Array[Vector3] = _sample()
	if curve.size() < 2:
		return
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var run: float = 0.0
	var prev: Vector3 = curve[0]
	for i: int in curve.size():
		var p: Vector3 = curve[i]
		run += p.distance_to(prev) if i > 0 else 0.0
		prev = p
		var t: Vector3 = (curve[mini(i + 1, curve.size() - 1)] - curve[maxi(i - 1, 0)])
		t = t.normalized() if t.length() > 0.0001 else Vector3(0, 0, -1)
		var side: Vector3 = t.cross(up_hint)
		side = side.normalized() if side.length() > 0.001 else Vector3.RIGHT
		# twist the strip about its own spine so it catches the light from all sides
		side = side.rotated(t, sin(run * 0.12 + phase) * twist)
		verts.append(p - side * width * 0.5)
		verts.append(p + side * width * 0.5)
		uvs.append(Vector2(run, 0.0))
		uvs.append(Vector2(run, 1.0))
		if i > 0:
			var b: int = (i - 1) * 2
			idx.append_array(PackedInt32Array([b, b + 1, b + 2, b + 1, b + 3, b + 2]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var aabb := AABB(verts[0], Vector3.ZERO)
	for v: Vector3 in verts:
		aabb = aabb.expand(v)
	mesh.custom_aabb = aabb.grow(2.0)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("color_a", color_a)
	mat.set_shader_parameter("color_b", color_b)
	mat.set_shader_parameter("total", run)
	mat.set_shader_parameter("speed", speed)
	mat.set_shader_parameter("wave", wave)
	mat.set_shader_parameter("strength", strength)
	mat.set_shader_parameter("phase", phase)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Catmull-Rom through the spine points, about `step` metres apart.
func _sample() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var n: int = points.size()
	for s: int in n - 1:
		var p0: Vector3 = points[maxi(s - 1, 0)]
		var p1: Vector3 = points[s]
		var p2: Vector3 = points[s + 1]
		var p3: Vector3 = points[mini(s + 2, n - 1)]
		var seg: float = p1.distance_to(p2)
		var k: int = maxi(int(ceil(seg / step)), 1)
		for j: int in k:
			var u: float = float(j) / float(k)
			out.append(_cr(p0, p1, p2, p3, u))
	out.append(points[n - 1])
	return out


static func _cr(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, u: float) -> Vector3:
	var u2: float = u * u
	var u3: float = u2 * u
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u3)
