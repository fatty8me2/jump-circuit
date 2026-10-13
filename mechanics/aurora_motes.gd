class_name AuroraMotes
extends Node3D
## Aurora Run's second mechanic: motes of aurora light strung along the fast line. Pass within `reach` of one
## and it flares and joins you (a little flow: FlowMeter.add), so a clean line down the mountain is a
## streak of lights. One node holds the whole string (a single MultiMesh, one distance test per mote per
## tick), they never block, hurt or ask anything of you, and a respawn relights them. In ZEN they glow
## softly brighter (group "flow_highlight").

@export var reach: float = 2.4
@export var flow_each: float = 0.01
@export var tint: Color = Color(0.55, 1.0, 0.85)

var points: PackedVector3Array = PackedVector3Array()
var taken: PackedByteArray = PackedByteArray()
var collected: int = 0
var _mm: MultiMesh
var _mat: StandardMaterial3D
var _burst: GPUParticles3D
var _t: float = 0.0


func _ready() -> void:
	add_to_group("resettable")
	add_to_group("flow_highlight")
	set_physics_process(true)
	_build()


func setup(pts: PackedVector3Array) -> void:
	points = pts
	taken.resize(pts.size())
	taken.fill(0)


func _build() -> void:
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = Color(tint.r * 1.6, tint.g * 1.6, tint.b * 1.6)
	_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat.albedo_texture = Fx.texture(Fx.Tex.STAR)
	_mat.vertex_color_use_as_albedo = false
	var q := QuadMesh.new()
	q.size = Vector2(0.9, 0.9)
	q.material = _mat
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.mesh = q
	_mm.instance_count = points.size()
	for i: int in points.size():
		_mm.set_instance_transform(i, Transform3D(Basis(), points[i]))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 60.0
	add_child(mmi)
	_burst = Fx.burst({"amount": 10, "lifetime": 0.5, "tex": Fx.Tex.STAR, "size": 0.3, "speed": Vector2(1.5, 4.0),
		"color": Fx.hot(tint, 2.6), "aabb": AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))})
	add_child(_burst)


func set_flow_highlight(amount: float) -> void:
	if _mat != null:
		var k: float = 1.6 + 1.4 * clampf(amount, 0.0, 1.0)
		_mat.albedo_color = Color(tint.r * k, tint.g * k, tint.b * k)


func reset_state() -> void:
	taken.fill(0)
	collected = 0
	for i: int in points.size():
		_mm.set_instance_transform(i, Transform3D(Basis(), points[i]))


func _physics_process(dt: float) -> void:
	_t += dt
	var player: Player = null
	var lvl: Node = get_parent()
	if lvl != null and "player" in lvl:
		player = lvl.get("player") as Player
	if player == null:
		return
	var pp: Vector3 = player.global_position + Vector3(0, 0.9, 0)
	var r2: float = reach * reach
	for i: int in points.size():
		if taken[i] != 0:
			continue
		var d: Vector3 = points[i] - pp
		if absf(d.z) > reach or absf(d.x) > reach or absf(d.y) > reach:
			continue
		if d.length_squared() <= r2:
			taken[i] = 1
			collected += 1
			_mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), points[i]))
			FlowMeter.add(flow_each, "mote")
			Fx.fire(_burst, points[i])
			WorldAudio.at(self, "aurora_mote", points[i], 0.5, 30.0, 0.04)
