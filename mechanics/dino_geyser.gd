class_name DinoGeyser
extends Node3D
## Dino Valley: a hot-spring GEYSER on the course clock. Every `period` s the pool shudders and
## bubbles for `warn` s (the tell: a rumble, a growing froth, a column of steam, the crater lamp
## flashing), then the geyser ERUPTS for `blow` s: a roaring jet of water that HOLDS you up like a
## ball on a fountain. Inside the column your fall is cancelled and you are carried up to its top
## (`height` m above the vent) where you hover while the blow lasts, free to steer out of it onto
## the ledge above. It never hurts: it is a lift on a rhythm. When the blow ends you drop.
##   s [0, quiet) idle wisps   [quiet, quiet + warn) the tell   [.., + blow) the eruption
## A pure function of Game.course_time. Positioned at the vent's floor point (the centre of its top).

@export var radius: float = 1.5
## Hover height of the jet above the vent (the water column reaches a little higher).
@export var height: float = 6.0
@export var period: float = 8.0
@export var phase: float = 0.0
@export var warn: float = 1.3
@export var blow: float = 3.4
## Fastest upward speed the jet gives (m/s).
@export var max_rise: float = 11.0
## Sets whether the vent builds its own crater disc (a decal-height ring; the level places the floor).
@export var crater: bool = true

const WATER := Color(0.86, 0.95, 1.0)
const SULFUR := Color(0.95, 0.85, 0.3)

var _quiet: float = 1.0
var _area: Area3D
var _jet: MeshInstance3D
var _jet_mat: ShaderMaterial
var _pool_mat: StandardMaterial3D
var _lamp_mat: StandardMaterial3D
var _lamp: OmniLight3D
var _spray: GPUParticles3D
var _crown: GPUParticles3D
var _steam: GPUParticles3D
var _froth: GPUParticles3D
var _boom: GPUParticles3D
var _rumble: AudioStreamPlayer3D
var _roar: AudioStreamPlayer3D
var _fx_phase: int = -1
var _shake: float = 0.0


func _ready() -> void:
	warn = maxf(warn, KitUtil.MIN_TELL + 0.2)
	_quiet = maxf(period - warn - blow, 0.5)
	period = _quiet + warn + blow
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 2
	_area.monitorable = false
	var shape := CylinderShape3D.new()
	shape.radius = radius * 0.95
	shape.height = height + 2.2
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, (height + 2.2) * 0.5 - 0.3, 0)
	_area.add_child(cs)
	add_child(_area)
	_build_visual()
	_rumble = WorldAudio.loop("dino_geyser_rumble", self, -8.0, 30.0, 6.0, false)
	_roar = WorldAudio.loop("dino_geyser_roar", self, -6.0, 45.0, 8.0, false)
	add_to_group("course_clock")
	_apply(Game.course_time)


# ---- the clock --------------------------------------------------------------------------------

func _s(time: float) -> float:
	return KitUtil.cycle_s(time, period, phase)


## 0 idle, 1 the tell, 2 erupting.
func phase_at(time: float) -> int:
	var s: float = _s(time)
	if s < _quiet:
		return 0
	return 1 if s < _quiet + warn else 2


func is_erupting_at(time: float) -> bool:
	return phase_at(time) == 2


## Seconds until the eruption next starts (0 while it blows).
func erupts_in(time: float) -> float:
	var s: float = _s(time)
	if s >= _quiet + warn:
		return 0.0
	return _quiet + warn - s


## Seconds of eruption left (0 when not erupting).
func blow_left(time: float) -> float:
	var s: float = _s(time)
	return period - s if s >= _quiet + warn else 0.0


## The jet runs for the whole of [now + a, now + b].
func blows_over(a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if not is_erupting_at(Game.course_time + s):
			return false
		s += 0.05
	return true


## World height the jet holds a rider at.
func hover_y() -> float:
	return global_position.y + height


func snap_to_clock() -> void:
	_apply(Game.course_time)


# ---- the lift ---------------------------------------------------------------------------------

func _physics_process(dt: float) -> void:
	var t: float = Game.course_time
	_apply(t)
	if not is_erupting_at(t):
		return
	var top: float = global_position.y + height
	for body: Node3D in _area.get_overlapping_bodies():
		if not (body is Player):
			continue
		var p := body as Player
		if p.is_wall_running() or p.is_mantling():
			continue
		var off: Vector3 = p.global_position - global_position
		if Vector2(off.x, off.z).length() > radius * 0.98:
			continue
		# a fountain holds a ball at its crest: rise toward the top speed, ease to a hover there
		var want: float = clampf((top - p.global_position.y) * 4.5, -4.0, max_rise)
		var vy: float = move_toward(p.velocity.y, want, 110.0 * dt)
		if vy > p.velocity.y:
			p.add_impulse(Vector3(0, vy - p.velocity.y, 0))
		else:
			p.velocity.y = vy


# ---- look ---------------------------------------------------------------------------------------

func _apply(t: float) -> void:
	var ph: int = phase_at(t)
	var s: float = _s(t)
	var into_tell: float = clampf((s - _quiet) / warn, 0.0, 1.0) if ph == 1 else 0.0
	var erupting: bool = ph == 2
	var grow: float = 0.0
	if erupting:
		var k: float = s - _quiet - warn
		grow = KitUtil.smooth(k / 0.3) * (1.0 - KitUtil.smooth((k - (blow - 0.45)) / 0.45))
	_jet.visible = grow > 0.01
	_jet_mat.set_shader_parameter("power", grow)
	_jet.scale = Vector3(1.0, maxf(grow, 0.05), 1.0)
	_jet.position = Vector3(0, (height + 1.2) * 0.5 * maxf(grow, 0.05) + 0.1, 0)
	if _spray.emitting != erupting:
		_spray.emitting = erupting
		_crown.emitting = erupting
	var tell_on: bool = ph == 1
	if _froth.emitting != tell_on:
		_froth.emitting = tell_on
	var steaming: bool = ph != 0
	if _steam.emitting != steaming:
		_steam.emitting = steaming
	WorldAudio.set_active(_rumble, ph == 1)
	WorldAudio.set_active(_roar, erupting)
	if _fx_phase != ph:
		if ph == 2 and _fx_phase >= 0:
			_boom.restart()
			_boom.emitting = true
			WorldAudio.at(self, "dino_geyser_erupt", global_position + Vector3(0, 1.0, 0), 1.0, 55.0)
			_cam_shake(0.35)
		elif ph == 1 and _fx_phase >= 0:
			WorldAudio.at(self, "dino_geyser_gurgle", global_position + Vector3(0, 0.5, 0), 0.9, 40.0)
		_fx_phase = ph
	# the pool and the lamp: sulphur-green and still, flaring through the tell, blue-white in the blow
	var glow: float = 0.5
	var col: Color = SULFUR
	if ph == 1:
		glow = 0.8 + 2.4 * into_tell * (0.7 + 0.3 * sin(t * 30.0))
		col = SULFUR.lerp(Color(1.0, 0.55, 0.2), into_tell)
	elif erupting:
		glow = 2.6
		col = WATER
	if not is_equal_approx(_pool_mat.emission_energy_multiplier, glow) or _pool_mat.emission != col:
		_pool_mat.emission_energy_multiplier = glow
		_pool_mat.emission = col
		_pool_mat.albedo_color = col
		_lamp_mat.emission_energy_multiplier = glow * 1.3
		_lamp_mat.emission = col
		_lamp.light_energy = glow * 0.7
		_lamp.light_color = col
	# the shudder: the whole vent trembles through the tell
	var tremble: float = into_tell * 0.035
	_pool_mat.uv1_offset = Vector3(sin(t * 61.0) * tremble, cos(t * 53.0) * tremble, 0)


func _cam_shake(amount: float) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null or not cam.has_method("add_trauma"):
		return
	var k: float = clampf(1.0 - (cam.global_position.distance_to(global_position) - 6.0) / 30.0, 0.0, 1.0)
	if k > 0.0:
		cam.call("add_trauma", amount * k)


func _build_visual() -> void:
	var r: float = radius
	var rock: StandardMaterial3D = Look.flat(Color(0.74, 0.7, 0.6), 0.9)
	var crust: StandardMaterial3D = Look.flat(Color(0.93, 0.88, 0.7), 0.85)
	var sulfur: StandardMaterial3D = Look.flat(SULFUR, 0.7, 0.0, 0.25)
	if crater:
		# a travertine mound round the mouth, banded white and sulphur yellow, all below a hand's height
		add_child(Look.cylinder(r * 1.5, 0.1, crust, Vector3(0, 0.05, 0), r * 1.3, 24))
		add_child(Look.cylinder(r * 1.22, 0.06, sulfur, Vector3(0, 0.12, 0), r * 1.1, 24))
		for i: int in 9:
			var a: float = TAU * float(i) / 9.0 + 0.3
			var lump: MeshInstance3D = Look.sphere(0.28 + 0.1 * float(i % 3), rock if i % 2 == 0 else crust, Vector3(cos(a) * r * 1.55, 0.05, sin(a) * r * 1.55))
			lump.scale = Vector3(1.0, 0.45, 1.0)
			add_child(lump)
	_pool_mat = Look.flat(SULFUR, 0.2, 0.0, 0.6).duplicate() as StandardMaterial3D
	var pool: MeshInstance3D = Look.cylinder(r * 0.92, 0.04, _pool_mat, Vector3(0, 0.15, 0), -1.0, 24)
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pool)
	# a ring of lamp-stones round the crater: they flash through the tell
	_lamp_mat = Look.flat(SULFUR, 0.3, 0.0, 0.6).duplicate() as StandardMaterial3D
	for i: int in 8:
		var a2: float = TAU * float(i) / 8.0
		var st: MeshInstance3D = Look.sphere(0.13, _lamp_mat, Vector3(cos(a2) * r * 1.12, 0.17, sin(a2) * r * 1.12))
		st.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(st)
	_lamp = OmniLight3D.new()
	_lamp.omni_range = 9.0
	_lamp.light_energy = 0.4
	_lamp.light_color = SULFUR
	_lamp.shadow_enabled = false
	_lamp.position = Vector3(0, 1.2, 0)
	add_child(_lamp)
	# the water column: a tall tapered tube with a streaming shader
	var cm := CylinderMesh.new()
	cm.bottom_radius = r * 0.9
	cm.top_radius = r * 1.15
	cm.height = height + 1.2
	cm.radial_segments = 20
	cm.rings = 1
	_jet = MeshInstance3D.new()
	_jet.mesh = cm
	_jet_mat = ShaderMaterial.new()
	_jet_mat.shader = preload("res://visual/dino_jet.gdshader")
	_jet_mat.set_shader_parameter("height", height + 1.2)
	_jet.material_override = _jet_mat
	_jet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_jet.visible = false
	add_child(_jet)
	var vis := AABB(Vector3(-6, -1, -6), Vector3(12, height + 10.0, 12))
	# the eruption's spray: droplets thrown up the column and raining back around it
	_spray = Fx.emitter({"amount": 110, "lifetime": 1.5, "shape": "sphere", "radius": r * 0.6, "emitting": false,
		"dir": Vector3.UP, "spread": 9.0, "speed": Vector2(11.0, 15.0), "gravity": Vector3(0, -14, 0),
		"tex": Fx.Tex.DOT, "size": 0.28, "scale": Vector2(0.6, 1.4), "color": Fx.hot(WATER, 1.3),
		"fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]), "aabb": vis})
	_spray.position = Vector3(0, 0.3, 0)
	add_child(_spray)
	# the crown: a mushroom of white water spread out at the crest of the jet
	_crown = Fx.emitter({"amount": 40, "lifetime": 1.2, "shape": "sphere", "radius": r * 0.5, "emitting": false,
		"dir": Vector3.UP, "spread": 70.0, "speed": Vector2(2.0, 5.0), "gravity": Vector3(0, -7, 0),
		"tex": Fx.Tex.SMOKE, "additive": false, "size": 1.6, "curve": "puff", "angle": Vector2(0, 360),
		"color": Color(0.96, 0.99, 1.0, 0.6), "fade": PackedFloat32Array([0.0, 0.9, 0.0]), "aabb": vis})
	_crown.position = Vector3(0, height + 0.6, 0)
	add_child(_crown)
	# the tell: froth and bubbles boiling up from the pool, and steam hissing from the vent
	_froth = Fx.emitter({"amount": 34, "lifetime": 0.8, "shape": "ring", "ring_radius": r * 0.8, "ring_inner": 0.1,
		"emitting": false, "dir": Vector3.UP, "spread": 25.0, "speed": Vector2(2.0, 5.5), "gravity": Vector3(0, -9, 0),
		"tex": Fx.Tex.BUBBLE, "size": 0.3, "scale": Vector2(0.5, 1.3), "color": Fx.hot(WATER.lerp(SULFUR, 0.3), 1.4), "aabb": vis})
	_froth.position = Vector3(0, 0.2, 0)
	add_child(_froth)
	_steam = Fx.emitter({"amount": 18, "lifetime": 3.0, "shape": "sphere", "radius": r * 0.5, "emitting": false,
		"dir": Vector3.UP, "spread": 14.0, "speed": Vector2(1.5, 3.0), "damping": Vector2(0.2, 0.6),
		"tex": Fx.Tex.SMOKE, "additive": false, "size": 1.4, "curve": "puff", "angle": Vector2(0, 360),
		"color": Color(0.96, 0.97, 0.95, 0.4), "fade": PackedFloat32Array([0.0, 0.8, 0.0]), "aabb": vis})
	_steam.position = Vector3(0, 0.3, 0)
	add_child(_steam)
	# the moment it blows: a ring of water thrown flat across the ground
	_boom = Fx.burst({"amount": 46, "lifetime": 0.9, "shape": "ring", "ring_radius": r * 0.8, "ring_inner": r * 0.3,
		"dir": Vector3.UP, "spread": 55.0, "radial_vel": Vector2(2.0, 5.0), "speed": Vector2(3.0, 8.0),
		"gravity": Vector3(0, -12, 0), "tex": Fx.Tex.SMOKE, "additive": false, "size": 1.0, "curve": "puff",
		"color": Color(0.96, 0.99, 1.0, 0.7), "fade": PackedFloat32Array([0.0, 1.0, 0.0]), "aabb": vis})
	_boom.position = Vector3(0, 0.3, 0)
	add_child(_boom)
	# always: a thread of vapour off the pool so a quiet vent still reads
	var idle: GPUParticles3D = Fx.emitter({"amount": 6, "lifetime": 3.5, "shape": "sphere", "radius": r * 0.5,
		"dir": Vector3.UP, "spread": 10.0, "speed": Vector2(0.6, 1.2), "tex": Fx.Tex.SMOKE, "additive": false,
		"size": 0.9, "curve": "puff", "angle": Vector2(0, 360), "color": Color(0.96, 0.97, 0.95, 0.22),
		"fade": PackedFloat32Array([0.0, 0.8, 0.0]), "aabb": vis, "preprocess": 3.5})
	idle.position = Vector3(0, 0.3, 0)
	add_child(idle)
