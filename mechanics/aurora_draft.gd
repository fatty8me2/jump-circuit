class_name AuroraDraft
extends Area3D
## Aurora Run's own mechanic: a draft, a ribbon of aurora light you can ride across a chasm. While you are
## airborne inside it you glide (a fall is held to a gentle sink of about `sink` m/s and a rise is left alone)
## and you are carried forward along the ribbon (`push` m/s^2 up to `cap` m/s, never slowing you). On the
## ground nothing happens. It is a pure function of where you are, so it never needs a tell, never kills and
## never makes you wait: launch off an arc, ride it, land on the far shelf. The box's -Z (turned by yaw) is
## "downstream". `glide_step()` is the same rule as a static function so a level can predict a flight through
## it (tests and ring placement use it).

@export var size: Vector3 = Vector3(10.0, 14.0, 40.0)
@export var sink: float = -2.2
@export var push: float = 9.0
@export var cap: float = 30.0
@export var tint: Color = Color(0.25, 1.0, 0.7)

var carries: int = 0
var _was_inside: bool = false
var _ribbons: Array[ShaderMaterial] = []


func _ready() -> void:
	process_physics_priority = KitUtil.EARLY + 1
	collision_layer = 0
	collision_mask = 2
	monitorable = false
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	add_child(cs)
	_build_visuals()
	WorldAudio.loop("aurora_draft_loop", self, -14.0, maxf(size.z, size.x) * 0.5 + 14.0, 5.0)


## Downstream direction on the ground plane.
func forward() -> Vector3:
	var f: Vector3 = -global_basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 0.001 else Vector3.FORWARD


## The rule, for predictions: the velocity change over `dt` for a body at velocity `v` inside a draft whose
## downstream direction is `fwd` (ground plane).
static func glide_step(v: Vector3, fwd: Vector3, dt: float, sink_rate: float = -2.2, accel: float = 9.0, speed_cap: float = 30.0) -> Vector3:
	var out: Vector3 = v
	if out.y < sink_rate:
		out.y = minf(out.y + 80.0 * dt, sink_rate)
	var along: float = Vector3(out.x, 0.0, out.z).dot(fwd)
	if along < speed_cap:
		var add: float = minf(accel * dt, speed_cap - along)
		out += fwd * add
	return out


func _build_visuals() -> void:
	var shader: Shader = preload("res://visual/aurora_curtain.gdshader")
	# two crossing ribbons of light along the whole box, plus drifting motes
	var rot: Array[float] = [0.0, 90.0]
	for i: int in 2:
		var q := QuadMesh.new()
		q.size = Vector2(size.z, size.y * 0.8)
		q.subdivide_width = 40
		q.subdivide_depth = 3
		var m := ShaderMaterial.new()
		m.shader = shader
		m.set_shader_parameter("hem_color", tint)
		m.set_shader_parameter("mid_color", Color(0.15, 0.85, 1.0))
		m.set_shader_parameter("top_color", Color(0.7, 0.4, 1.0))
		m.set_shader_parameter("fold", 1.6)
		m.set_shader_parameter("speed", 0.35)
		m.set_shader_parameter("seed", float(i) * 5.0)
		m.set_shader_parameter("ray_count", 60.0)
		m.set_shader_parameter("intensity", 0.55)
		_ribbons.append(m)
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = m
		mi.rotation = Vector3(0.0, deg_to_rad(90.0), deg_to_rad(rot[i]))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	var motes: GPUParticles3D = Fx.emitter({"amount": int(clampf(size.x * size.z * 0.5, 40.0, 160.0)), "lifetime": 2.2, "preprocess": 2.2,
		"local": true, "shape": "box", "extents": Vector3(size.x * 0.4, size.y * 0.35, 0.5), "offset": Vector3(0, 0, size.z * 0.5),
		"dir": Vector3(0, 0, -1), "spread": 6.0, "speed": Vector2(size.z * 0.35, size.z * 0.45), "turbulence": 1.0,
		"tex": Fx.Tex.DOT, "size": 0.28, "scale": Vector2(0.5, 1.2),
		"pick": PackedColorArray([Fx.hot(tint, 2.4), Fx.hot(Color(0.7, 0.4, 1.0), 2.4), Fx.hot(Color(0.3, 0.9, 1.0), 2.2)]),
		"fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]), "aabb": AABB(-size, size * 2.0)})
	add_child(motes)


func _physics_process(dt: float) -> void:
	var inside: Player = null
	for body: Node3D in get_overlapping_bodies():
		if body is Player:
			inside = body as Player
			break
	if inside == null:
		_was_inside = false
		return
	if inside.grounded:
		_was_inside = false
		return
	if not _was_inside:
		_was_inside = true
		carries += 1
		WorldAudio.at(self, "aurora_draft_enter", inside.global_position, 0.8, 40.0, 0.03)
	var fwd: Vector3 = forward()
	var nv: Vector3 = glide_step(inside.velocity, fwd, dt, sink, push, cap)
	if nv != inside.velocity:
		inside.add_impulse(nv - inside.velocity)
