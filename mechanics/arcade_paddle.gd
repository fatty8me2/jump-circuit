class_name ArcadePaddle
extends MovingPlatform
## Pixel Panic: a PONG PADDLE. A white bar you ride that slides along its lane at a steady pace and
## turns round at the ends with a short ease (a trapezoid of speed, not a sine), like a paddle chasing
## a ball. Its pose is a pure function of Game.course_time (identical for every racer; the route bot
## reads it through offset_at() like any MovingPlatform). The lane is drawn as a dashed line, and the
## ends flash and ping on every turn.
##   points / period / phase as MovingPlatform; `ramp` = the fraction of the stroke spent easing at
##   each end (0.09 = a quick turn).

@export var ramp: float = 0.09
@export var tint: Color = Color(0.95, 0.96, 1.0)

var _ping_u: int = -1
var _flash: MeshInstance3D
var _flash_mat: StandardMaterial3D


func _ready() -> void:
	sync_to_physics = false
	collision_layer = 1
	collision_mask = 0
	_origin = position
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	add_child(cs)
	# the bar: a beveled white slab with a glowing cyan edge strip along each long side and a pixel
	# serve-line down the middle
	var mat: ShaderMaterial = ArcadeFx.block_mat(tint, size, 0.25)
	mat.set_shader_parameter("bevel", 0.12)
	add_child(Look.box(size, mat))
	var strip: StandardMaterial3D = ArcadeFx.glow_mat(ArcadeFx.CYAN, 2.2)
	for sx: float in [-1.0, 1.0]:
		var s := Look.box(Vector3(0.08, 0.06, size.z - 0.2), strip, Vector3(sx * (size.x * 0.5 - 0.1), size.y * 0.5 + 0.005, 0))
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(s)
	var dash: StandardMaterial3D = ArcadeFx.glow_mat(ArcadeFx.INK, 1.0)
	var n: int = maxi(int(size.z / 0.7), 2)
	for i: int in n:
		var d := Look.box(Vector3(0.14, 0.02, 0.28), dash, Vector3(0, size.y * 0.5 + 0.012, -size.z * 0.5 + (float(i) + 0.5) * size.z / float(n)))
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(d)
	# little thruster pixels underneath so it reads as "this one moves"
	var pod: StandardMaterial3D = ArcadeFx.glow_mat(ArcadeFx.MAGENTA, 2.0)
	for sz: float in [-0.3, 0.3]:
		var p := Look.box(Vector3(0.3, 0.2, 0.3), pod, Vector3(0, -size.y * 0.5 - 0.1, sz * size.z))
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(p)
	_flash_mat = ArcadeFx.glow_mat(ArcadeFx.WHITE, 3.0, 0.0).duplicate()
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash = Look.box(size + Vector3(0.2, 0.2, 0.2), _flash_mat)
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.visible = false
	add_child(_flash)
	_build_lane()
	position = _origin + offset_at(Game.course_time)
	reset_physics_interpolation()
	add_to_group("course_clock")


func _build_lane() -> void:
	if points.size() < 2:
		return
	var dots: Array[Vector3] = []
	for i: int in range(points.size() - 1):
		var a: Vector3 = _origin + points[i]
		var b: Vector3 = _origin + points[i + 1]
		var cnt: int = maxi(int(a.distance_to(b) / 0.8), 1)
		for k: int in cnt + 1:
			dots.append(a.lerp(b, float(k) / float(cnt)) + Vector3(0, -size.y * 0.5 - 0.25, 0))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new()
	bm.size = Vector3(0.12, 0.12, 0.12)
	mm.mesh = bm
	mm.instance_count = dots.size()
	for i: int in dots.size():
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, dots[i]))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = ArcadeFx.glow_mat(ArcadeFx.CYAN, 1.4)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	add_child(mi)


## Trapezoid speed profile: eases over the first / last `ramp` of the stroke, steady between.
func _profile(x: float) -> float:
	var a: float = clampf(ramp, 0.01, 0.45)
	var d: float = 2.0 * a * (1.0 - a)
	if x < a:
		return x * x / d
	if x > 1.0 - a:
		var y: float = 1.0 - x
		return 1.0 - y * y / d
	return (x - a * 0.5) / (1.0 - a)


func offset_at(time: float) -> Vector3:
	if points.size() < 2:
		return Vector3.ZERO
	var u: float = fposmod(time / maxf(period, 0.01) + phase, 1.0)
	var tri: float = 1.0 - absf(u * 2.0 - 1.0)
	var legs: int = points.size() - 1
	var f: float = _profile(tri) * float(legs)
	var leg: int = mini(int(f), legs - 1)
	var k: float = f - float(leg)
	return points[leg].lerp(points[leg + 1], k)


func _process(_dt: float) -> void:
	var u: float = fposmod(Game.course_time / maxf(period, 0.01) + phase, 1.0)
	# a ping at each end of the stroke (u = 0 and 0.5 are the turns)
	var half: int = int(floor(u * 2.0))
	var c: Color = _flash_mat.albedo_color
	if half != _ping_u:
		if _ping_u >= 0:
			_flash.visible = true
			c.a = 0.5
			# SOUND: arcade_paddle_ping - a pong "tok" as the paddle turns round at the end of its lane
			WorldAudio.at(self, "arcade_paddle_ping", global_position, 0.5, 28.0)
		_ping_u = half
	if _flash.visible:
		c.a = maxf(c.a - _dt * 2.5, 0.0)
		if c.a <= 0.01:
			_flash.visible = false
	_flash_mat.albedo_color = c
