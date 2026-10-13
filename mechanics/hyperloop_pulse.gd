class_name HyperloopPulse
extends MeshInstance3D
## Hyperloop: PULSE LIGHTS - a lane of flat chevrons laid along a polyline (the flow line), each one
## pointing the way to go, with a bright wave running down the lane in the direction of travel. At speed
## the lane reads as one stream of light you can follow without thinking; in ZEN (the flow meter's
## `zen_amount`) the whole lane glows brighter. Purely visual: no collision, nothing to wait for.
## Build with HyperloopPulse.lay(parent, points, ...). The mesh is one ArrayMesh; the wave runs in the
## shader on TIME, so it needs no per-frame work except the ZEN uniform.

const SHADER_CODE: String = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;

uniform vec3 col : source_color = vec3(0.2, 0.88, 1.0);
uniform float speed = 14.0;
uniform float wave_len = 36.0;
uniform float zen = 0.0;
uniform float base_glow = 0.35;

varying float s_along;
varying float edge;

void vertex() {
	s_along = UV.x;
	edge = UV.y;
}

void fragment() {
	float ph = fract((s_along - TIME * speed) / max(wave_len, 1.0));
	float wave = pow(clamp(1.0 - ph, 0.0, 1.0), 3.0);
	float bright = base_glow + wave * 1.6 + zen * 0.8;
	float soft = clamp(1.0 - abs(edge * 2.0 - 1.0), 0.0, 1.0);
	ALBEDO = col * bright * (0.4 + 0.6 * soft);
	ALPHA = 1.0;
}
"""

static var _shader: Shader = null

var _mat: ShaderMaterial


## Lays a lane of chevrons along `pts` (world points, in the direction of travel). `spacing` is the metres
## between chevrons, `width` the lane width, `lift` how far above the points the chevrons float.
static func lay(parent: Node3D, pts: Array[Vector3], spacing: float = 3.2, width: float = 2.0, lift: float = 0.06,
		color: Color = Color(0.2, 0.88, 1.0)) -> HyperloopPulse:
	var hp := HyperloopPulse.new()
	hp.name = "Pulse"
	hp.mesh = hp._build_mesh(pts, spacing, width, lift)
	hp._mat = ShaderMaterial.new()
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	hp._mat.shader = _shader
	hp._mat.set_shader_parameter("col", Vector3(color.r, color.g, color.b))
	hp.material_override = hp._mat
	hp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hp.add_to_group("flow_highlight")
	parent.add_child(hp)
	return hp


## ZEN deepens: the lane glows (FlowMeter finds nodes in the "flow_highlight" group).
func set_flow_highlight(amount: float) -> void:
	if _mat != null:
		_mat.set_shader_parameter("zen", clampf(amount, 0.0, 1.0))


func _build_mesh(pts: Array[Vector3], spacing: float, width: float, lift: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	if pts.size() < 2:
		return ArrayMesh.new()
	# arc length table
	var cum: Array[float] = [0.0]
	for i: int in range(1, pts.size()):
		cum.append(cum[i - 1] + pts[i].distance_to(pts[i - 1]))
	var total: float = cum[cum.size() - 1]
	var d: float = spacing * 0.5
	var seg: int = 0
	var depth: float = minf(spacing * 0.42, 1.3)
	while d < total - spacing * 0.3:
		while seg < pts.size() - 2 and cum[seg + 1] < d:
			seg += 1
		var span: float = maxf(cum[seg + 1] - cum[seg], 0.0001)
		var k: float = clampf((d - cum[seg]) / span, 0.0, 1.0)
		var p: Vector3 = pts[seg].lerp(pts[seg + 1], k)
		var dir: Vector3 = pts[seg + 1] - pts[seg]
		var flat := Vector3(dir.x, 0.0, dir.z)
		if flat.length() < 0.001:
			d += spacing
			continue
		flat = flat.normalized()
		var side: Vector3 = flat.cross(Vector3.UP).normalized()
		# a dart pointing forward: tip, two back corners and a notch between them
		var tip: Vector3 = p + flat * depth * 0.5 + Vector3(0, lift, 0)
		var wl: Vector3 = p - flat * depth * 0.5 - side * width * 0.5 + Vector3(0, lift, 0)
		var wr: Vector3 = p - flat * depth * 0.5 + side * width * 0.5 + Vector3(0, lift, 0)
		var notch: Vector3 = p - flat * depth * 0.05 + Vector3(0, lift, 0)
		var base: int = verts.size()
		verts.append_array([tip, wl, notch, wr])
		uvs.append_array([Vector2(d, 0.5), Vector2(d, 0.0), Vector2(d, 0.5), Vector2(d, 1.0)])
		idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
		d += spacing
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	if verts.size() > 0:
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		am.custom_aabb = AABB(Vector3(-2000, -2000, -2000), Vector3(4000, 4000, 4000))
	return am
