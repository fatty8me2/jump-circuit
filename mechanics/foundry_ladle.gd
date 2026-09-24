class_name FoundryLadle
extends Node3D
## Bounce Foundry's slag-pour line: a drum ladle hung over the walkway that rolls
## forward on a fixed rhythm (Game.course_time) and pours a sheet of molten slag
## straight down across the path. While the sheet is falling it kills; between
## pours the way is clear. Warning: for `warn` s before a pour the drum rolls
## over, its lip glows and slag drips; the floor channel under it brightens.
## Positioned at the floor point under the middle of the sheet. The sheet spans
## local X (`width`), is THICK deep along local Z and falls from `drop` m up.

@export var width: float = 3.2
@export var drop: float = 6.0
@export var period: float = 3.0
@export var pour_fraction: float = 0.4
@export var phase: float = 0.0
@export var warn: float = 0.6

const THICK: float = 0.8
const DRUM_R: float = 0.85
const TIP_DEG: float = 75.0

var _area: Area3D
var _sheet: Node3D
var _drum: Node3D
var _lip_mat: StandardMaterial3D
var _channel_mat: StandardMaterial3D
var _stream: GPUParticles3D
var _splash: GPUParticles3D
var _steam: GPUParticles3D
var _drips: GPUParticles3D
var _state: int = -1
# sound (side effect only): the pour's roar while the sheet is falling
var _pour: AudioStreamPlayer3D


func _ready() -> void:
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 2
	_area.monitorable = false
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, drop - 0.3, THICK * 0.9)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	_area.add_child(cs)
	_area.position = Vector3(0, (drop - 0.3) * 0.5, 0)
	add_child(_area)
	_build_look()
	_apply(true)
	_pour = WorldAudio.loop("ladle_pour", self, -7.0, 28.0, 5.0, _state == 2)
	if _pour != null:
		_pour.position = Vector3(0, minf(drop * 0.5, 2.0), 0)


func _build_look() -> void:
	# the molten sheet: a bright core inside a hot orange skin
	_sheet = Node3D.new()
	add_child(_sheet)
	var skin := StandardMaterial3D.new()
	skin.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	skin.albedo_color = Color(1.0, 0.42, 0.08)
	skin.emission_enabled = true
	skin.emission = Color(1.0, 0.38, 0.06)
	skin.emission_energy_multiplier = 3.2
	var core := StandardMaterial3D.new()
	core.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core.albedo_color = Color(1.0, 0.86, 0.45)
	core.emission_enabled = true
	core.emission = Color(1.0, 0.8, 0.4)
	core.emission_energy_multiplier = 4.5
	var sheet := Look.box(Vector3(width, drop, THICK * 0.7), skin, Vector3(0, drop * 0.5, 0))
	sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sheet.add_child(sheet)
	var inner := Look.box(Vector3(width * 0.8, drop, THICK * 0.72), core, Vector3(0, drop * 0.5, 0))
	inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sheet.add_child(inner)
	# floor channel the slag falls into (drawn just above the floor, wider than the sheet)
	_channel_mat = Look.flat(Color(0.9, 0.3, 0.06), 0.5, 0.0, 0.6)
	var ch := Look.box(Vector3(width + 0.3, 0.06, THICK + 0.5), _channel_mat, Vector3(0, 0.035, 0))
	ch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ch)
	# the drum ladle: a horizontal barrel that rolls over to pour from its slot
	var pivot := Node3D.new()
	pivot.position = Vector3(0, drop + DRUM_R * 0.55, DRUM_R * 0.55)
	add_child(pivot)
	_drum = Node3D.new()
	pivot.add_child(_drum)
	var shell: StandardMaterial3D = Look.flat(Color(0.2, 0.19, 0.22), 0.55, 0.6)
	var drum := Look.cylinder(DRUM_R, width + 0.5, shell, Vector3.ZERO, -1.0, 20)
	drum.rotation.z = PI * 0.5
	_drum.add_child(drum)
	var band: StandardMaterial3D = Look.flat(Look.c("metal"), 0.4, 0.7)
	for sx: float in [-1.0, 1.0]:
		var b := Look.cylinder(DRUM_R + 0.08, 0.22, band, Vector3(sx * (width * 0.5 + 0.1), 0, 0), -1.0, 20)
		b.rotation.z = PI * 0.5
		_drum.add_child(b)
	_lip_mat = Look.flat(Color(1.0, 0.5, 0.1), 0.4, 0.0, 1.0)
	# the pour slot: a glowing strip along the drum on the side that rolls down to the sheet
	_drum.add_child(Look.box(Vector3(width + 0.2, 0.3, 0.2), _lip_mat, Vector3(0, DRUM_R * 0.55, -DRUM_R * 0.8)))
	# trunnion hangers up to the rail (the level draws the rail itself)
	var iron: StandardMaterial3D = Look.flat(Color(0.25, 0.23, 0.27), 0.6, 0.5)
	for sx: float in [-1.0, 1.0]:
		add_child(Look.box(Vector3(0.18, 2.6, 0.3), iron, pivot.position + Vector3(sx * (width * 0.5 + 0.38), 1.1, 0)))
	add_child(Look.box(Vector3(width + 1.2, 0.3, 0.5), iron, pivot.position + Vector3(0, 2.45, 0)))
	# particles: the falling stream, the splash at the floor, steam after, warning drips
	_stream = _stream_fx()
	_stream.position = Vector3(0, drop, 0)
	add_child(_stream)
	_splash = FoundryFx.sparks(self, Vector3(0, 0.15, 0), Vector3.UP, 36, 7.0, 55.0, 0.75)
	var spm := _splash.process_material as ParticleProcessMaterial
	spm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	spm.emission_box_extents = Vector3(width * 0.5, 0.05, THICK * 0.5)
	_steam = FoundryFx.steam(self, Vector3(0, 0.3, 0), Vector3.UP, 10, 2.2, 1.4)
	var stm := _steam.process_material as ParticleProcessMaterial
	stm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	stm.emission_box_extents = Vector3(width * 0.5, 0.1, THICK * 0.5)
	_drips = _drip_fx()
	_drips.position = Vector3(0, drop, 0)
	add_child(_drips)


func _stream_fx() -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(width * 0.5, 0.05, THICK * 0.45)
	pm.direction = Vector3.DOWN
	pm.spread = 3.0
	pm.initial_velocity_min = 5.0
	pm.initial_velocity_max = 7.0
	pm.gravity = Vector3(0, -22, 0)
	pm.scale_min = 0.7
	pm.scale_max = 1.4
	pm.color_ramp = FoundryFx.ramp([[0.0, Color(1, 0.95, 0.7, 1)], [0.7, Color(1, 0.6, 0.2, 1)], [1.0, Color(1, 0.4, 0.1, 0.6)]])
	var life: float = (-6.0 + sqrt(36.0 + 44.0 * drop)) / 22.0
	var p := GPUParticles3D.new()
	p.amount = Fx.count(int(clampf(width * 12.0, 24, 60)))
	p.lifetime = maxf(life, 0.2)
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-width, -drop - 1.0, -2), Vector3(width * 2.0, drop + 3.0, 4))
	p.process_material = pm
	p.draw_pass_1 = FoundryFx.quad(0.34, FoundryFx.SLAG, true)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


func _drip_fx() -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(width * 0.45, 0.05, 0.1)
	pm.direction = Vector3.DOWN
	pm.spread = 2.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.5
	pm.gravity = Vector3(0, -22, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.0
	pm.color_ramp = FoundryFx.ramp([[0.0, Color(1, 0.9, 0.6, 1)], [1.0, Color(1, 0.4, 0.1, 0.8)]])
	var p := GPUParticles3D.new()
	p.amount = Fx.count(8)
	p.lifetime = sqrt(2.0 * drop / 22.0) + 0.05
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-width, -drop - 1.0, -2), Vector3(width * 2.0, drop + 3.0, 4))
	p.process_material = pm
	p.draw_pass_1 = FoundryFx.quad(0.22, FoundryFx.SLAG, true)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


# ---- timing (pure functions of the course clock) --------------------------------------------

func is_pouring_at(time: float) -> bool:
	return fposmod(time / period + phase, 1.0) < pour_fraction


## Seconds until the next pour starts (0 while pouring).
func time_until_pour(time: float) -> float:
	var u: float = fposmod(time / period + phase, 1.0)
	return 0.0 if u < pour_fraction else (1.0 - u) * period


## Seconds until the current pour stops (0 while clear).
func time_until_clear(time: float) -> float:
	var u: float = fposmod(time / period + phase, 1.0)
	return (pour_fraction - u) * period if u < pour_fraction else 0.0


## True while the sheet stays off for the whole [time, time + window].
func is_clear_for(time: float, window: float) -> bool:
	return not is_pouring_at(time) and time_until_pour(time) > window


# ---- runtime -------------------------------------------------------------------------------

## 0 idle, 1 warning (rolling over), 2 pouring, 3 rolling back
func _state_at(time: float) -> int:
	var u: float = fposmod(time / period + phase, 1.0)
	if u < pour_fraction:
		return 2
	var until: float = (1.0 - u) * period
	if until < warn:
		return 1
	if (u - pour_fraction) * period < 0.5:
		return 3
	return 0


func _tip_at(time: float) -> float:
	var u: float = fposmod(time / period + phase, 1.0)
	if u < pour_fraction:
		return 1.0
	var until: float = (1.0 - u) * period
	if until < warn:
		var k: float = 1.0 - until / warn
		return k * k * 0.85
	var since: float = (u - pour_fraction) * period
	if since < 0.5:
		var r: float = since / 0.5
		return 1.0 - r * r * (3.0 - 2.0 * r)
	return 0.0


func _apply(force: bool = false) -> void:
	var t: float = Game.course_time
	_drum.rotation.x = -deg_to_rad(TIP_DEG) * _tip_at(t)
	var s: int = _state_at(t)
	if s == _state and not force:
		return
	var was: int = _state
	_state = s
	if not force and was >= 0:
		_sound(s)
	_sheet.visible = s == 2
	_stream.emitting = s == 2
	_splash.emitting = s == 2
	_steam.emitting = s == 2 or s == 3
	_drips.emitting = s == 1
	_lip_mat.emission_energy_multiplier = 3.0 if s == 1 or s == 2 else 0.8
	_channel_mat.emission_energy_multiplier = 2.6 if s == 2 else (1.4 if s == 1 else 0.5)


## Sound only: the drum grinding over, the slag hitting the channel and roaring, the steam after.
func _sound(s: int) -> void:
	WorldAudio.set_active(_pour, s == 2)
	var at: Vector3 = to_global(Vector3(0, drop, DRUM_R * 0.55))
	match s:
		1:
			WorldAudio.at(self, "ladle_tip", at, 0.6, 35.0)
		2:
			WorldAudio.at(self, "ladle_splash", global_position, 0.9, 40.0)
		3:
			WorldAudio.at(self, "ladle_hiss", global_position, 0.5, 30.0)


func _physics_process(_dt: float) -> void:
	_apply()
	if not is_pouring_at(Game.course_time):
		return
	for body: Node3D in _area.get_overlapping_bodies():
		if body is Player:
			var n: Node = self
			while n != null and not n.has_method("fail"):
				n = n.get_parent()
			if n != null:
				n.call_deferred("fail", "hazard")
			return
