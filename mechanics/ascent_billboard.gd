class_name AscentBillboard
extends WallRunPanel
## THE FINAL ASCENT's holographic billboard: a wall-run panel that is only there while its
## ad is showing. It runs a fixed cycle (Game.course_time, identical for every racer):
## the hologram flickers in, cycles its ad slides, GLITCHES for `warn` seconds and blinks
## out - and while it is out there is nothing to run on. Its frame posts always stay lit.
## Keeps the wall-run look (cyan run lines + chevrons) while solid, so it reads as runnable.

const AD_COLORS: Array[Color] = [Color(1.0, 0.3, 0.8), Color(0.35, 0.95, 1.0), Color(1.0, 0.8, 0.25)]

@export var period: float = 3.0
@export var on_fraction: float = 0.7
@export var phase: float = 0.0
## Seconds of glitching before it blinks out (and of flicker as it comes back).
@export var warn: float = 0.5

var _shape: CollisionShape3D
var _solid: Array[Node3D] = []
var _slides: Array[Node3D] = []
var _screen_mat: StandardMaterial3D
var _screen: Node3D
var _dust: GPUParticles3D
var _pop: GPUParticles3D
var _was_on: bool = true


func _ready() -> void:
	super._ready()
	for c: Node in get_children():
		if c is CollisionShape3D:
			_shape = c as CollisionShape3D
		elif c is Node3D:
			_solid.append(c as Node3D)
	_build_hologram()
	_build_frame()
	_was_on = is_on_at(Game.course_time)
	_apply(Game.course_time)
	add_to_group("course_clock")


## The screen: a translucent magenta-blue sheet on both faces with the ad slides on it.
func _build_hologram() -> void:
	_screen = Node3D.new()
	add_child(_screen)
	_screen_mat = StandardMaterial3D.new()
	_screen_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_screen_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_screen_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_screen_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_screen_mat.albedo_color = Color(0.45, 0.35, 1.0, 0.22)
	for side: float in [-1.0, 1.0]:
		var sheet := Look.box(Vector3(size.x - 0.2, size.y * 0.62, 0.02), _screen_mat, Vector3(0, size.y * 0.12, side * (size.z * 0.5 + 0.07)))
		sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_screen.add_child(sheet)
	# three ad slides: bold bars and a logo disc, each in its own colour
	for i: int in 3:
		var slide := Node3D.new()
		_screen.add_child(slide)
		var col: Color = AD_COLORS[i]
		var mat: StandardMaterial3D = Look.flat(col, 0.3, 0.0, 2.2)
		for side: float in [-1.0, 1.0]:
			var z: float = side * (size.z * 0.5 + 0.09)
			var logo := Look.cylinder(size.y * 0.16, 0.03, mat, Vector3(-size.x * 0.3 + i * size.x * 0.3, size.y * 0.2, z), -1.0, 20)
			logo.rotation.x = PI * 0.5
			slide.add_child(logo)
			for b: int in 3:
				var w: float = size.x * (0.34 - b * 0.07)
				var x: float = size.x * 0.12 - i * size.x * 0.2 + size.x * 0.1
				slide.add_child(Look.box(Vector3(w, 0.16, 0.03), mat, Vector3(x, size.y * 0.36 - b * 0.34, z)))
		_slides.append(slide)
	# pixel dust drifting off the lit screen
	_dust = _particles(26, 1.4, Vector3(size.x * 0.5, size.y * 0.3, 0.3), Color(0.8, 0.5, 1.0), 0.09)
	_dust.position = Vector3(0, size.y * 0.12, 0)
	var dm := _dust.process_material as ParticleProcessMaterial
	dm.gravity = Vector3(0, 0.5, 0)
	dm.initial_velocity_min = 0.1
	dm.initial_velocity_max = 0.5
	add_child(_dust)
	# the pop when it blinks out / back
	_pop = _particles(60, 0.55, Vector3(size.x * 0.5, size.y * 0.4, 0.2), Color(1.0, 0.45, 0.9), 0.16)
	_pop.one_shot = true
	_pop.emitting = false
	_pop.explosiveness = 0.9
	var ppm := _pop.process_material as ParticleProcessMaterial
	ppm.direction = Vector3(0, 0, 1)
	ppm.spread = 180.0
	ppm.initial_velocity_min = 1.5
	ppm.initial_velocity_max = 4.0
	ppm.damping_min = 2.0
	ppm.damping_max = 4.0
	add_child(_pop)


## Always-lit end posts and a top truss, so the billboard's place reads even while it is out.
func _build_frame() -> void:
	var post_mat: StandardMaterial3D = Look.flat(Color(0.14, 0.14, 0.2), 0.4, 0.7)
	var lamp_mat: StandardMaterial3D = Look.flat(Color(1.0, 0.35, 0.85), 0.3, 0.0, 2.6)
	for ex: float in [-1.0, 1.0]:
		var x: float = ex * (size.x * 0.5 + 0.35)
		add_child(Look.box(Vector3(0.3, size.y + 1.4, 0.3), post_mat, Vector3(x, 0.3, 0)))
		add_child(Look.box(Vector3(0.12, size.y * 0.8, 0.36), lamp_mat, Vector3(x, 0.3, 0)))
	add_child(Look.box(Vector3(size.x + 1.0, 0.18, 0.18), post_mat, Vector3(0, size.y * 0.5 + 0.95, 0)))
	add_child(Look.box(Vector3(size.x + 0.6, 0.06, 0.22), lamp_mat, Vector3(0, size.y * 0.5 + 0.83, 0)))


func _particles(amount: int, life: float, extents: Vector3, col: Color, quad: float) -> GPUParticles3D:
	var g := GPUParticles3D.new()
	g.amount = Fx.count(amount)
	g.lifetime = life
	g.local_coords = true
	g.visibility_aabb = AABB(-extents - Vector3(4, 4, 4), extents * 2.0 + Vector3(8, 8, 8))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extents
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 30.0
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(col.r, col.g, col.b, 1.0))
	ramp.set_color(1, Color(col.r, col.g, col.b, 0.0))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	g.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(quad, quad)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	qm.vertex_color_use_as_albedo = true
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = qm
	g.draw_pass_1 = q
	return g


func is_on_at(time: float) -> bool:
	return fposmod(time / period + phase, 1.0) < on_fraction


## Seconds until it blinks out (0 while it is out).
func time_until_off(time: float) -> float:
	var u: float = fposmod(time / period + phase, 1.0)
	return (on_fraction - u) * period if u < on_fraction else 0.0


## Seconds until it is back (0 while it is on).
func time_until_on(time: float) -> float:
	var u: float = fposmod(time / period + phase, 1.0)
	return 0.0 if u < on_fraction else (1.0 - u) * period


## Solid for the whole window [now + a, now + b].
func solid_through(time: float, a: float, b: float) -> bool:
	var t: float = time + a
	while t <= time + b:
		if not is_on_at(t):
			return false
		t += 0.04
	return true


func snap_to_clock() -> void:
	_apply(Game.course_time)


func _apply(t: float) -> void:
	var on: bool = is_on_at(t)
	if _shape != null and _shape.disabled == on:
		_shape.disabled = not on
	var u: float = fposmod(t / period + phase, 1.0)
	var left: float = time_until_off(t)
	var since: float = u * period
	# glitch: flicker and jitter before blinking out, flicker as it comes back
	var glitch: bool = on and (left < warn or since < 0.2)
	var show: bool = on and (not glitch or fmod(t, 0.1) > 0.035)
	for n: Node3D in _solid:
		n.visible = show
	_screen.visible = show
	_screen.position.x = (sin(t * 91.0) * 0.12) if glitch else 0.0
	var a: float = 0.22 if not glitch else 0.1 + 0.3 * absf(sin(t * 57.0))
	if not is_equal_approx(_screen_mat.albedo_color.a, a):
		var c: Color = _screen_mat.albedo_color
		c.a = a
		_screen_mat.albedo_color = c
	var slide: int = int(u / maxf(on_fraction, 0.01) * 3.0) % 3
	for i: int in _slides.size():
		_slides[i].visible = i == slide
	_dust.emitting = on
	if on != _was_on:
		_was_on = on
		_pop.restart()


func _physics_process(_dt: float) -> void:
	_apply(Game.course_time)
