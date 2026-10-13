class_name LotusBloom
extends Node3D
## Lotus Drift: the CHECKPOINT LOTUS. A great lotus bud sits in a stone basin at the isle's edge;
## when the checkpoint beside it is touched the bud opens (petals fan out in a quick bloom, a soft
## glow lights its heart) and stays open, so a glance back tells you which isles you have woken. The
## others stay closed buds with a faint pulse. Bound to one Checkpoint node with bind(); it closes
## again if the run is restarted. Scenery only.

@export var scale_k: float = 2.4
@export var tint: Color = Color(1.0, 0.55, 0.72)

var _flower: MeshInstance3D
var _glow: MeshInstance3D
var _light: OmniLight3D
var _open: float = 0.0
var _want: float = 0.0
var _cp: Checkpoint
var _level: LevelBase
var _burst: Array[GPUParticles3D] = []


func _ready() -> void:
	var basin := Look.cylinder(0.9 * scale_k * 0.5, 0.5, Look.flat(Color(0.42, 0.42, 0.48), 0.9), Vector3(0, 0.25, 0), 0.7 * scale_k * 0.5, 14)
	add_child(basin)
	add_child(Look.cylinder(0.78 * scale_k * 0.5, 0.06, LotusDecor.water_material(), Vector3(0, 0.5, 0), -1.0, 14))
	_flower = MeshInstance3D.new()
	_flower.mesh = LotusDecor.flower_mesh(0.0)
	_flower.scale = Vector3.ONE * scale_k
	_flower.position = Vector3(0, 0.5, 0)
	_flower.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_flower)
	_glow = Look.sphere(0.18 * scale_k * 0.5, Look.flat(Color(1.0, 0.8, 0.45), 0.4, 0.0, 3.0), Vector3(0, 0.62 * scale_k * 0.5 + 0.5, 0))
	_glow.visible = false
	add_child(_glow)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.72, 0.5)
	_light.light_energy = 0.0
	_light.omni_range = 9.0
	_light.position = Vector3(0, 1.8, 0)
	add_child(_light)
	_burst = LotusFx.cp_burst(tint)
	for p: GPUParticles3D in _burst:
		p.position = Vector3(0, 0.8, 0)
		add_child(p)


## Follow `cp` (and the level that counts it): the flower is open while that checkpoint is banked.
func bind(cp: Checkpoint, lvl: LevelBase) -> void:
	_cp = cp
	_level = lvl


func _process(dt: float) -> void:
	if _cp != null and _level != null:
		var banked: bool = _level.current_checkpoint >= _cp.index and _cp.index > 0
		if banked and _want < 0.5:
			_want = 1.0
			for p: GPUParticles3D in _burst:
				p.restart()
				p.emitting = true
			# SOUND: lotus_bloom - a soft chord blooming as the lotus opens
			WorldAudio.at(self, "lotus_bloom", global_position, 0.9, 40.0)
		elif not banked and _want > 0.5:
			_want = 0.0
	var prev: float = _open
	_open = move_toward(_open, _want, dt * 1.6)
	if absf(_open - prev) > 0.0005 or _open == 0.0:
		_flower.mesh = LotusDecor.flower_mesh(roundf(_open * 10.0) / 10.0)
		_glow.visible = _open > 0.3
		_light.light_energy = 1.3 * _open
	# the unopened bud breathes; the open flower sways a hair
	var t: float = Time.get_ticks_msec() * 0.001
	var s: float = scale_k * (1.0 + 0.03 * sin(t * 1.4) * (1.0 - _open) + 0.05 * _open)
	_flower.scale = Vector3.ONE * s
