class_name VolcanoLava
extends Node3D
## Cinder Peak: a molten lava surface. Touch it and you burn (back to the checkpoint): every
## physics tick the local player's feet are tested against the surface inside its footprint,
## which is exact for still pools, sinking basalt and a surface that moves.
## A pool can RISE on the course clock (the Magma Chamber): drain quickly to its low level,
## rest there for `low` s, climb steadily by `rise` m over `climb` s, hold near the top, and
## drain again - a pure function of Game.course_time, identical for every racer.
## Positioned at the centre of the surface at its LOW level; local X / Z span `size`.

const SHADER: Shader = preload("res://visual/volcano_lava.gdshader")

@export var size: Vector2 = Vector2(10, 10)
## Flow direction of the crust rafts (world XZ, m/s).
@export var flow: Vector2 = Vector2(0.0, 0.3)
@export var crust: float = 0.55
## Rising pool: height of the climb (0 = a still pool) and its cycle.
@export var rise: float = 0.0
@export var period: float = 16.0
@export var phase: float = 0.0
@export var drain: float = 2.0
@export var low: float = 3.0
@export var climb: float = 9.0
## Glow and set dressing.
@export var light: bool = true
@export var embers: bool = true

var _mat: ShaderMaterial
var _surface: MeshInstance3D
var _fx: Node3D
var _light: OmniLight3D
var _base_y: float = 0.0
# sound (side effect only): the roar of the tide while it climbs
var _roar: AudioStreamPlayer3D


func _ready() -> void:
	_base_y = position.y
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("flow", flow)
	_mat.set_shader_parameter("crust", crust)
	var pm := PlaneMesh.new()
	pm.size = size
	pm.subdivide_width = 0
	pm.subdivide_depth = 0
	_surface = Look.mesh_node(pm, _mat)
	_surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_surface)
	_fx = Node3D.new()
	add_child(_fx)
	if embers:
		var area: float = size.x * size.y
		VolcanoFx.bubbles(_fx, Vector3(0, 0.05, 0), size * 0.42, clampi(int(area * 0.12), 6, 40))
		VolcanoFx.embers(_fx, Vector3(0, 0.6, 0), Vector3(size.x * 0.42, 0.3, size.y * 0.42), clampi(int(area * 0.1), 6, 36), 1.6)
	if light:
		_light = VolcanoFx.glow_light(_fx, Vector3(0, 1.2, 0), 1.6 + minf(size.x * size.y / 120.0, 2.5), clampf(maxf(size.x, size.y) * 0.9, 7.0, 26.0))
	if rise > 0.0:
		add_to_group("course_clock")
		_roar = WorldAudio.loop("lava_rise", self, -4.0, maxf(size.x, size.y) + 25.0, 8.0, false)
	_apply(Game.course_time)


## Height of the surface above its low level at `time` (0 for a still pool).
func offset_at(time: float) -> float:
	if rise <= 0.0:
		return 0.0
	var s: float = fposmod(time + phase * period, period)
	var hold: float = maxf(period - drain - low - climb, 0.0)
	if s < drain:
		var k: float = s / drain
		return rise * (1.0 - k * k * (3.0 - 2.0 * k))
	s -= drain
	if s < low:
		return 0.0
	s -= low
	if s < climb:
		return rise * s / climb
	return rise


## World height of the surface at `time`.
func level_at(time: float) -> float:
	return _base_y + offset_at(time)


## True while the tide is climbing (the chase is on).
func is_rising_at(time: float) -> bool:
	if rise <= 0.0:
		return false
	var s: float = fposmod(time + phase * period, period)
	return s >= drain + low and s < drain + low + climb


## Seconds until the surface next starts to climb (0 while climbing).
func time_until_climb(time: float) -> float:
	if rise <= 0.0:
		return INF
	var s: float = fposmod(time + phase * period, period)
	var start: float = drain + low
	if s < start:
		return start - s
	if s < start + climb:
		return 0.0
	return period - s + start


func snap_to_clock() -> void:
	_apply(Game.course_time)
	reset_physics_interpolation()


func _apply(t: float) -> void:
	position.y = level_at(t)
	if _roar != null:
		WorldAudio.set_active(_roar, is_rising_at(t))
	if _light != null and rise > 0.0:
		# the tide glows brighter as it climbs
		_light.light_energy = 2.0 + 2.5 * offset_at(t) / rise


func _physics_process(_dt: float) -> void:
	var t: float = Game.course_time
	if rise > 0.0:
		_apply(t)
	if _level == null:
		_level = VolcanoLava.level_of(self)
		if _level == null:
			return
	var p: Player = _level.player
	if p == null or _level.finished:
		return
	var local: Vector3 = global_transform.affine_inverse() * p.global_position
	if absf(local.x) < size.x * 0.5 and absf(local.z) < size.y * 0.5 and local.y < 0.05 and local.y > -40.0:
		_level.fail("hazard")


var _level: LevelBase


## The LevelBase a node belongs to (null outside a level).
static func level_of(node: Node) -> LevelBase:
	var n: Node = node
	while n != null and not (n is LevelBase):
		n = n.get_parent()
	return n as LevelBase
