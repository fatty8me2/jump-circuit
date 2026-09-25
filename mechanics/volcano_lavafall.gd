class_name VolcanoLavaFall
extends Node3D
## Cinder Peak: a curtain of lava pouring off a lip on a rhythm (Game.course_time) - a timing
## gate. For `warn` seconds before each pour it drips and a thin glowing trickle starts; then
## the pour front falls from the lip at `fall_speed` and the curtain stands until the source
## stops, when its tail falls away the same way. Whatever part of the curtain is actually
## there burns (the kill tests the player's body against the lava's current top and bottom),
## so what you see is exactly what kills. Positioned at the floor point under the middle of
## the curtain; local X runs across it (`size.x` wide), `size.y` is the lip's height above
## the floor, `size.z` the curtain's thickness; it keeps falling `below` m past the floor.

const SHADER: Shader = preload("res://visual/volcano_flow.gdshader")

@export var size: Vector3 = Vector3(3.0, 6.0, 0.6)
@export var below: float = 8.0
@export var period: float = 3.0
@export var on_fraction: float = 0.5
@export var phase: float = 0.0
@export var warn: float = 0.7
@export var fall_speed: float = 18.0

var _sheet: MeshInstance3D
var _mat: ShaderMaterial
var _trickle: MeshInstance3D
var _drips: GPUParticles3D
var _splash: GPUParticles3D
var _steam: GPUParticles3D
var _light: OmniLight3D
var _level: LevelBase
# sound (side effect only): the pouring roar while lava falls
var _roar: AudioStreamPlayer3D


func _ready() -> void:
	_build()
	_roar = WorldAudio.loop("lavafall_loop", self, -4.0, 30.0, 6.0, false)
	if _roar != null:
		_roar.position = Vector3(0, size.y * 0.5, 0)
	_apply(Game.course_time)


func _total() -> float:
	return size.y + below


## Seconds since the current pour started, or -1 when the source is off.
func _pouring_for(time: float) -> float:
	var u: float = fposmod(time / period + phase, 1.0)
	return u * period if u < on_fraction else -1.0


## Seconds since the source last stopped (only meaningful while it is off).
func _stopped_for(time: float) -> float:
	var u: float = fposmod(time / period + phase, 1.0)
	return (u - on_fraction) * period if u >= on_fraction else INF


## Metres of lava below the lip: x = tail (top of the lava), y = head (bottom). Both 0 = none.
func span_at(time: float) -> Vector2:
	var full: float = _total()
	var p: float = _pouring_for(time)
	if p >= 0.0:
		return Vector2(0.0, minf(p * fall_speed, full))
	var s: float = _stopped_for(time)
	# the tail falls away; the head had reached the bottom unless the pour was shorter than the fall
	var head: float = minf(on_fraction * period * fall_speed + s * fall_speed, full)
	var tail: float = minf(s * fall_speed, full)
	if tail >= full:
		return Vector2.ZERO
	return Vector2(tail, head)


## True when lava covers the band between `y0` and `y1` m above the floor at `time`.
func covers_at(time: float, y0: float, y1: float) -> bool:
	var sp: Vector2 = span_at(time)
	if sp.y <= sp.x:
		return false
	var top: float = size.y - sp.x
	var bottom: float = size.y - sp.y
	return bottom < y1 and top > y0


## A runner's body (floor to head height) is clear of the curtain over [now + a, now + b].
func is_clear_between(time: float, a: float, b: float, y0: float = -0.5, y1: float = 2.2) -> bool:
	var s: float = a
	while s <= b:
		if covers_at(time + s, y0, y1):
			return false
		s += 0.03
	return true


func _physics_process(_dt: float) -> void:
	var t: float = Game.course_time
	_apply(t)
	if _level == null:
		_level = VolcanoLava.level_of(self)
		if _level == null:
			return
	var p: Player = _level.player
	if p == null or _level.finished:
		return
	var local: Vector3 = global_transform.affine_inverse() * p.global_position
	if absf(local.x) < size.x * 0.5 + 0.2 and absf(local.z) < size.z * 0.5 + 0.35 and covers_at(t, local.y, local.y + 1.7):
		_level.fail("hazard")


func _apply(t: float) -> void:
	var sp: Vector2 = span_at(t)
	var full: float = _total()
	var showing: bool = sp.y > sp.x
	_sheet.visible = showing
	if showing:
		_mat.set_shader_parameter("cut_top", sp.x / full)
		_mat.set_shader_parameter("cut_bottom", sp.y / full)
	var p: float = _pouring_for(t)
	var until: float = 0.0 if p >= 0.0 else (1.0 - fposmod(t / period + phase, 1.0)) * period
	var warning: bool = p < 0.0 and until < warn
	_trickle.visible = warning
	if _drips.emitting != (warning or showing):
		_drips.emitting = warning or showing
	var landing: bool = showing and sp.y >= full - 0.2
	if _splash.emitting != landing:
		_splash.emitting = landing
		_steam.emitting = landing
	WorldAudio.set_active(_roar, showing)
	_light.light_energy = 3.0 if showing else (1.2 if warning else 0.5)


func _build() -> void:
	var full: float = _total()
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("size", Vector2(size.x, full))
	_mat.set_shader_parameter("speed", fall_speed * 0.6)
	var q := QuadMesh.new()
	q.size = Vector2(size.x, full)
	_sheet = Look.mesh_node(q, _mat, Vector3(0, size.y - full * 0.5, 0))
	_sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_sheet)
	# a second sheet a little behind for body (thickness)
	var back := Look.mesh_node(q, _mat, Vector3(0, size.y - full * 0.5, -size.z * 0.5))
	back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sheet.add_child(back)
	back.position = Vector3(0, 0, -size.z * 0.6)
	# the warning trickle: a thin bright thread down the middle
	var tq := QuadMesh.new()
	tq.size = Vector2(0.18, full)
	_trickle = Look.mesh_node(tq, Look.flat(Color(1.0, 0.6, 0.15), 0.4, 0.0, 4.0), Vector3(0, size.y - full * 0.5, 0))
	_trickle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trickle.visible = false
	add_child(_trickle)
	# the lip it pours from: a slab of dark rock with a glowing mouth
	var rock: StandardMaterial3D = Look.flat(Color(0.12, 0.1, 0.1), 0.9)
	add_child(Look.box(Vector3(size.x + 1.2, 0.8, size.z + 2.2), rock, Vector3(0, size.y + 0.45, -0.5)))
	add_child(Look.box(Vector3(size.x * 0.9, 0.12, 0.5), Look.flat(Color(1.0, 0.5, 0.12), 0.4, 0.0, 3.0), Vector3(0, size.y + 0.08, size.z * 0.3)))
	var vis := AABB(Vector3(-size.x - 4.0, -below - 4.0, -size.z - 4.0), Vector3(size.x * 2.0 + 8.0, full + 10.0, size.z * 2.0 + 8.0))
	_drips = Fx.emitter({"amount": 18, "lifetime": 0.9, "emitting": false, "shape": "box",
		"extents": Vector3(size.x * 0.4, 0.05, size.z * 0.3), "dir": Vector3.DOWN, "spread": 5.0, "speed": Vector2(1.0, 3.0),
		"gravity": Vector3(0, -30.0, 0), "tex": Fx.Tex.DOT, "size": 0.2, "curve": "shrink",
		"color": Color(3.0, 1.3, 0.3), "aabb": vis})
	_drips.position = Vector3(0, size.y, 0)
	add_child(_drips)
	# where it hits the floor line: a spray of droplets and steam
	_splash = Fx.emitter({"amount": 40, "lifetime": 0.8, "emitting": false, "shape": "box",
		"extents": Vector3(size.x * 0.45, 0.05, size.z * 0.5), "dir": Vector3.UP, "spread": 55.0, "speed": Vector2(2.0, 5.5),
		"gravity": Vector3(0, -22.0, 0), "tex": Fx.Tex.DOT, "size": 0.22, "curve": "shrink",
		"colors": PackedColorArray([VolcanoFx.EMBER_HOT, VolcanoFx.EMBER, Color(1.0, 0.2, 0.05, 0.0)]), "aabb": vis})
	_splash.position = Vector3(0, -below + 0.3, 0)
	add_child(_splash)
	_steam = Fx.emitter({"amount": 14, "lifetime": 1.6, "emitting": false, "shape": "box",
		"extents": Vector3(size.x * 0.5, 0.2, size.z), "dir": Vector3.UP, "spread": 20.0, "speed": Vector2(1.5, 3.0),
		"tex": Fx.Tex.SMOKE, "additive": false, "size": 1.6, "curve": "puff", "color": Color(0.35, 0.28, 0.26, 0.5),
		"fade": PackedFloat32Array([0.0, 0.8, 0.0]), "angle": Vector2(0, 360), "aabb": vis})
	_steam.position = Vector3(0, -below + 0.5, 0)
	add_child(_steam)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.5, 0.15)
	_light.omni_range = maxf(size.y, 8.0)
	_light.omni_attenuation = 1.4
	_light.light_energy = 0.5
	_light.position = Vector3(0, size.y * 0.5, 1.2)
	add_child(_light)
