class_name OrbitalFlare
extends Node3D
## ORBITAL DRIFT - SOLAR FLARE FRONT. A wall of blinding plasma that sweeps along
## an exposed deck on a fixed rhythm (Game.course_time): it launches from the
## flare gate at the far (-Z) end, races to the near (+Z) end in `sweep` seconds,
## then the gate recharges. Anyone it passes over is sent back to the checkpoint -
## unless they are inside a SHELTER: the lee of a shield wall, marked by a glowing
## floor plate. The front is visibly cut away inside every shelter, so the safe
## pockets read at a glance. The gate strobes for `warn` s before each launch.
## Local frame: X across the deck, Y up from the deck, the front travels toward +Z.

const FLARE_COLOR: Color = Color(1.0, 0.82, 0.55)
const MAX_SHELTERS: int = 8

@export var width: float = 12.0
@export var height: float = 9.0
## Below the deck the front reaches down this far (catches anyone hanging low).
@export var depth: float = 4.0
@export var length: float = 40.0
@export var period: float = 5.0
@export var sweep: float = 1.6
@export var phase: float = 0.0
@export var warn: float = 1.0
@export var thickness: float = 1.4

## Shelters in local space.
var shelters: Array[AABB] = []

var _front: Node3D
var _slab_mat: ShaderMaterial
var _gate_mat: StandardMaterial3D
var _gate_light: OmniLight3D
var _embers: GPUParticles3D
var _prev_rel: float = 0.0
var _prev_sweep: int = -1


func _ready() -> void:
	_build_visual()
	add_to_group("course_clock")
	snap_to_clock()


func add_shelter(local_center: Vector3, size: Vector3) -> void:
	shelters.append(AABB(local_center - size * 0.5, size))
	_push_shelters()


func snap_to_clock() -> void:
	_prev_sweep = -1
	_apply(Game.course_time)
	_front.reset_physics_interpolation()


## Front position along local Z at `time`, or NAN while the gate is recharging.
func front_z_at(time: float) -> float:
	var s: float = fposmod(time / period + phase, 1.0) * period
	if s >= sweep:
		return NAN
	return -length * 0.5 + length * (s / sweep)


func is_sweeping_at(time: float) -> bool:
	return fposmod(time / period + phase, 1.0) * period < sweep


## Seconds from `time` until the front next reaches local z (0 if it is there now).
func time_until_front_at(time: float, local_z: float) -> float:
	var k: float = clampf((local_z + length * 0.5) / length, 0.0, 1.0)
	var s_hit: float = k * sweep
	var s: float = fposmod(time / period + phase, 1.0) * period
	var d: float = s_hit - s
	if d < 0.0:
		d += period
	return d


func _sheltered(p: Vector3) -> bool:
	for a: AABB in shelters:
		if a.has_point(p):
			return true
	return false


func _physics_process(_dt: float) -> void:
	var t: float = Game.course_time
	_apply(t)
	var z: float = front_z_at(t)
	var level: Node = _level()
	if level == null or is_nan(z):
		_prev_sweep = -1
		return
	var player: Player = level.get("player")
	if player == null:
		return
	var sweep_id: int = int(floor(t / period + phase))
	var p: Vector3 = to_local(player.global_position + Vector3(0, 0.9, 0))
	var rel: float = p.z - z
	var crossed: bool = _prev_sweep == sweep_id and signf(rel) != signf(_prev_rel)
	_prev_sweep = sweep_id
	_prev_rel = rel
	if absf(p.x) > width * 0.5 or p.y < -depth or p.y > height:
		return
	if (absf(rel) < thickness * 0.5 + 0.35 or crossed) and not _sheltered(p):
		level.call_deferred("fail", "hazard")


func _level() -> Node:
	var n: Node = self
	while n != null and not n.has_method("fail"):
		n = n.get_parent()
	return n


func _apply(t: float) -> void:
	var z: float = front_z_at(t)
	_front.visible = not is_nan(z)
	if not is_nan(z):
		_front.position = Vector3(0, 0, z)
	_embers.emitting = not is_nan(z)
	# gate: dim while recharging, strobing hard in the warning second, blazing while it fires
	var s: float = fposmod(t / period + phase, 1.0) * period
	var until: float = period - s
	var glow: float = 0.6
	if s < sweep:
		glow = 6.0
	elif until < warn:
		glow = 5.0 if fmod(until, 0.2) > 0.1 else 1.2
	if not is_equal_approx(_gate_mat.emission_energy_multiplier, glow):
		_gate_mat.emission_energy_multiplier = glow
	_gate_light.light_energy = glow * 0.9


func _push_shelters() -> void:
	if _slab_mat == null:
		return
	var mins: PackedVector3Array = PackedVector3Array()
	var maxs: PackedVector3Array = PackedVector3Array()
	for i: int in MAX_SHELTERS:
		if i < shelters.size():
			mins.append(to_global_safe(shelters[i].position))
			maxs.append(to_global_safe(shelters[i].end))
		else:
			mins.append(Vector3(1e6, 1e6, 1e6))
			maxs.append(Vector3(1e6, 1e6, 1e6))
	# world-space boxes (the flare is only ever yawed, so its AABBs stay boxes after sorting)
	for i: int in MAX_SHELTERS:
		var a: Vector3 = mins[i]
		var b: Vector3 = maxs[i]
		mins[i] = Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z))
		maxs[i] = Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z))
	_slab_mat.set_shader_parameter("sh_min", mins)
	_slab_mat.set_shader_parameter("sh_max", maxs)


func to_global_safe(local: Vector3) -> Vector3:
	return global_transform * local if is_inside_tree() else transform * local


# ---- look -------------------------------------------------------------------------------------

const SLAB_SHADER: String = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec3 sh_min[8];
uniform vec3 sh_max[8];
uniform vec4 tint : source_color = vec4(1.0, 0.82, 0.55, 1.0);
varying vec3 wpos;
varying vec3 lpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	lpos = VERTEX;
}
void fragment() {
	for (int i = 0; i < 8; i++) {
		if (all(greaterThan(wpos, sh_min[i])) && all(lessThan(wpos, sh_max[i]))) {
			discard;
		}
	}
	float bands = 0.55 + 0.45 * sin(lpos.y * 2.3 - TIME * 9.0 + sin(lpos.x * 0.7 + TIME * 3.0) * 2.0);
	float fade = smoothstep(0.0, 0.25, UV.y) * smoothstep(1.0, 0.75, UV.y);
	ALBEDO = tint.rgb * (0.9 + 1.4 * bands);
	ALPHA = clamp((0.35 + 0.35 * bands) * mix(0.4, 1.0, fade), 0.0, 1.0);
}
"""


func _build_visual() -> void:
	_front = Node3D.new()
	add_child(_front)
	var sh := Shader.new()
	sh.code = SLAB_SHADER
	_slab_mat = ShaderMaterial.new()
	_slab_mat.shader = sh
	_slab_mat.set_shader_parameter("tint", FLARE_COLOR)
	var slab := Look.box(Vector3(width, height + depth, thickness), _slab_mat, Vector3(0, (height - depth) * 0.5, 0))
	slab.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_front.add_child(slab)
	# a brighter leading sheet
	var lead := Look.box(Vector3(width, height + depth, 0.15), _slab_mat, Vector3(0, (height - depth) * 0.5, thickness * 0.5))
	lead.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_front.add_child(lead)
	_push_shelters()
	# plasma embers boiling off the front and trailing behind it
	_embers = GPUParticles3D.new()
	_embers.amount = 140
	_embers.lifetime = 0.7
	_embers.local_coords = false
	_embers.emitting = false
	_embers.visibility_aabb = AABB(Vector3(-width, -depth - 2.0, -length), Vector3(width * 2.0, height + depth + 4.0, length * 2.0))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(width * 0.5, (height + depth) * 0.5, 0.3)
	pm.emission_shape_offset = Vector3(0, (height - depth) * 0.5, 0)
	pm.direction = Vector3(0, 0.2, -1)
	pm.spread = 35.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 6.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.5
	pm.scale_max = 1.3
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 0.9, 1.0), Color(1.0, 0.75, 0.35, 0.9), Color(1.0, 0.3, 0.1, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	_embers.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.3, 0.3)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_texture = OrbitalGravityBay._dot()
	q.material = m
	_embers.draw_pass_1 = q
	_front.add_child(_embers)
	# the flare gate at the far end: a frame that charges up
	_gate_mat = StandardMaterial3D.new()
	_gate_mat.albedo_color = FLARE_COLOR
	_gate_mat.emission_enabled = true
	_gate_mat.emission = Color(1.0, 0.7, 0.35)
	_gate_mat.emission_energy_multiplier = 0.6
	var frame: StandardMaterial3D = Look.flat(Color(0.2, 0.2, 0.24), 0.4, 0.7)
	var z0: float = -length * 0.5 - 0.6
	for sx: float in [-1.0, 1.0]:
		add_child(Look.box(Vector3(0.6, height + depth, 0.6), frame, Vector3(sx * (width * 0.5 + 0.4), (height - depth) * 0.5, z0)))
		add_child(Look.box(Vector3(0.2, height + depth - 0.4, 0.66), _gate_mat, Vector3(sx * (width * 0.5 + 0.1), (height - depth) * 0.5, z0)))
	add_child(Look.box(Vector3(width + 1.4, 0.6, 0.6), frame, Vector3(0, height + 0.3, z0)))
	add_child(Look.box(Vector3(width, 0.2, 0.66), _gate_mat, Vector3(0, height - 0.1, z0)))
	_gate_light = OmniLight3D.new()
	_gate_light.light_color = Color(1.0, 0.75, 0.45)
	_gate_light.omni_range = 14.0
	_gate_light.position = Vector3(0, height * 0.5, z0 + 1.0)
	add_child(_gate_light)
