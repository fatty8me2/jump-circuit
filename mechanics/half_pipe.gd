class_name HalfPipe
extends FlowSurface
## Half-pipe (flow kit, docs/FLOW_KIT.md): a curved trough built from `slices` strips across and a
## row every ~2 m along, so you can carve from wall to wall without losing speed. It is a FlowSurface:
## no over-speed bleed, and the grade of the walls adds speed (the Player's flow rule), so every
## swing across it keeps or builds momentum, up to `cap`.
## Local frame: the node's origin is the bottom centre of the START; the trough runs along local -Z for
## `length` metres (yaw turns it, `pitch_deg` tips it down the course: positive = descends), local X
## is across. The trough starts and ends flush with the ground at the centre line: its depth eases in
## over `taper` metres at both ends, so it is entered and left like a funnel, never over a lip.
## Cross-section: depth * r^2 (r = 0..1 from the middle to the rim), or with `flat` > 0 a flat floor
## that wide (a fraction of the half-width) with parabolic walls. The rim never exceeds 42 degrees,
## so the whole wall is walkable (the depth is limited to make that so).

@export var width: float = 10.0
@export var depth: float = 2.0
@export var length: float = 40.0
@export var pitch_deg: float = 0.0
@export var taper: float = 8.0
@export var flat: float = 0.0
## Width of the flat lip on each side of the rim (at rim height), metres.
@export var shelf: float = 1.5
## A low glass fence along the outer edges of the lip (stops a fast rider leaving the pipe sideways).
@export var guard: bool = true
@export var slices: int = 20

const MAX_SLOPE: float = 0.88   # tan of the steepest wall (about 41 degrees)


func _ready() -> void:
	depth = minf(depth, _max_depth())
	_build()


func _max_depth() -> float:
	var half: float = width * 0.5
	if flat > 0.0:
		return MAX_SLOPE * half * (1.0 - flat) * 0.5
	return MAX_SLOPE * half * 0.5


## 0..1 depth factor at distance `z` (metres along the trough, from the start).
func _taper_k(z: float) -> float:
	var tp: float = maxf(taper, 0.01)
	return KitUtil.smooth(z / tp) * KitUtil.smooth((length - z) / tp)


func _profile(r: float) -> float:
	var a: float = clampf(r, 0.0, 1.0)
	if flat > 0.0:
		a = maxf(0.0, (a - flat) / maxf(1.0 - flat, 0.05))
	return a * a


## Local height of the trough surface at lateral x and distance z along (the shelf is flat at rim height).
func height_local(x: float, z: float) -> float:
	return depth * _taper_k(z) * _profile(absf(x) / (width * 0.5))


# ---- world helpers for level designers and the bot -------------------------------------------------

## World point on the trough surface at fraction `u` (0 start, 1 end) along it and lateral `side` in
## -1..1 (0 = the bottom, +/-1 = the rim, +side = to the right of the direction of travel).
func surface_point(u: float, side: float) -> Vector3:
	var z: float = clampf(u, 0.0, 1.0) * length
	var x: float = clampf(side, -1.0, 1.0) * width * 0.5
	return global_transform * Vector3(x, height_local(x, z), -z)


## World point on the bottom centre line at fraction `u`.
func centre_point(u: float) -> Vector3:
	return surface_point(u, 0.0)


## A carving line: `swings` half-turns from wall to wall (amplitude `reach` of the half-width), as world points
## for r_flow. The line starts and ends on the centre line.
func carve_points(swings: int = 3, reach: float = 0.55, per_swing: int = 4) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var n: int = maxi(swings * per_swing, 2)
	for i: int in n + 1:
		var u: float = float(i) / float(n)
		var env: float = sin(PI * u)   # eases out of and back into the middle
		var side: float = sin(TAU * 0.5 * float(swings) * u) * reach * env
		out.append(surface_point(u, side))
	return out


# ---- geometry ----------------------------------------------------------------------------------------

func _build() -> void:
	var half: float = width * 0.5
	var xs: Array[float] = [-half - shelf]
	var s: int = maxi(slices, 4)
	for i: int in s + 1:
		xs.append(-half + width * float(i) / float(s))
	xs.append(half + shelf)
	var rows: int = maxi(int(ceilf(length / 2.0)), 4) + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	for j: int in rows:
		var z: float = length * float(j) / float(rows - 1)
		for x: float in xs:
			verts.append(Vector3(x, height_local(x, z), -z))
			# normal from the surface gradient (central differences)
			var dx: float = (height_local(x + 0.05, z) - height_local(x - 0.05, z)) / 0.1
			var dz: float = (height_local(x, z + 0.05) - height_local(x, z - 0.05)) / 0.1
			norms.append(Vector3(-dx, 1.0, dz).normalized())
			uvs.append(Vector2(x, z))
	var nx: int = xs.size()
	var idx := PackedInt32Array()
	for j2: int in rows - 1:
		for i2: int in nx - 1:
			var a: int = j2 * nx + i2
			var b: int = a + 1
			var c: int = a + nx
			var d: int = c + 1
			idx.append_array([a, c, b, b, c, d])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = FlowSurface.material(Vector3(width + shelf * 2.0, depth, length), 2.0)
	add_child(mi)
	var shape: ConcavePolygonShape3D = mesh.create_trimesh_shape()
	shape.backface_collision = true
	var cs := CollisionShape3D.new()
	cs.shape = shape
	add_child(cs)
	if guard:
		_build_guard(half + shelf)


func _build_guard(edge: float) -> void:
	var glass := StandardMaterial3D.new()
	glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var col: Color = Look.c("accent2").lerp(Color(0.55, 1.0, 0.95), 0.3)
	glass.albedo_color = Color(col.r, col.g, col.b, 0.10)
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var top_h: float = depth + 1.4
	for sx: float in [-1.0, 1.0]:
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.3, top_h + 1.0, length)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = Vector3(sx * (edge + 0.15), (top_h - 1.0) * 0.5, -length * 0.5)
		add_child(cs)
		var bm := BoxMesh.new()
		bm.size = Vector3(0.06, 1.4, length)
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		mi.material_override = glass
		mi.position = Vector3(sx * (edge + 0.15), depth + 0.7, -length * 0.5)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
