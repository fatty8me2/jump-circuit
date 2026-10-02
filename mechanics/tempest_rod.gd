class_name TempestRod
extends Node3D
## Tempest Tower: a LIGHTNING ROD on the steelwork. Lightning picks the tallest thing, and up here
## that is the rod clamped to this beam. On the course clock a charge builds for `warn` seconds: the
## steel span round the rod (painted with yellow-black hazard bands) starts to glow blue, sparks
## crawl up the rod and its tip crackles brighter and brighter. Then the bolt lands - a blinding
## flash, a shower of sparks, a shock ring - and the whole span is live for `strike` seconds:
## anything standing in the zone is fried. Pure function of the clock.
## Positioned at the floor point at the middle of the span; `zone` is the deadly box over it in local
## axes (x across, z along the span, y the height it reaches above the floor).
##   cycle: the bolt lands at u = 0 (u = fposmod(t / period + phase, 1)).

signal struck(pos: Vector3)

@export var period: float = 4.8
@export var phase: float = 0.0
@export var warn: float = 1.4
## How long the span stays live after the bolt lands.
@export var strike: float = 0.45
@export var zone: Vector3 = Vector3(1.6, 3.0, 2.4)
@export var rod_height: float = 3.6
## Where the rod stands (local, on the span's edge, off the walking line).
@export var rod_offset: Vector3 = Vector3(0.95, 0, 0)

const CHARGE := Color(0.55, 0.78, 1.0)

var _band_mat: StandardMaterial3D
var _tip_mat: StandardMaterial3D
var _crawl: GPUParticles3D
var _skin: GPUParticles3D
var _burst: GPUParticles3D
var _wave: GPUParticles3D
var _bolt: MeshInstance3D
var _light: OmniLight3D
var _last: int = -999999
var _was_warn: bool = false


func _ready() -> void:
	_build()
	add_to_group("course_clock")
	_last = _index(Game.course_time)
	_apply(Game.course_time)


func _index(time: float) -> int:
	return int(floor(time / period + phase))


## Seconds since the last bolt landed.
func since_strike(time: float) -> float:
	return fposmod(time / period + phase, 1.0) * period


## Seconds until the next bolt.
func time_until_strike(time: float) -> float:
	return period - since_strike(time)


func is_deadly_at(time: float) -> bool:
	return since_strike(time) < strike


## The span is safe for the whole window [time + a, time + b].
func is_safe_for(time: float, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if is_deadly_at(time + s):
			return false
		s += 0.03
	return not is_deadly_at(time + b)


func snap_to_clock() -> void:
	_last = _index(Game.course_time)
	_apply(Game.course_time)


func _physics_process(_dt: float) -> void:
	if not is_deadly_at(Game.course_time):
		return
	var pl: Node3D = WorldAudio.local_player(self)
	if pl == null or not (pl is Player):
		return
	var d: Vector3 = global_basis.inverse() * (pl.global_position - global_position)
	if absf(d.x) < zone.x * 0.5 + 0.3 and absf(d.z) < zone.z * 0.5 + 0.3 and d.y > -0.6 and d.y < zone.y:
		var n: Node = self
		while n != null and not n.has_method("fail"):
			n = n.get_parent()
		if n != null:
			n.call_deferred("fail", "hazard")


func _process(_dt: float) -> void:
	_apply(Game.course_time)


func _apply(t: float) -> void:
	var k: int = _index(t)
	if k != _last:
		if k == _last + 1 and since_strike(t) < 0.3:
			_strike()
		_last = k
	var since: float = since_strike(t)
	var until: float = period - since
	var warning: bool = until < warn
	var w: float = 1.0 - until / warn if warning else 0.0
	var band: float = 0.0
	if since < strike:
		band = 5.0
	elif since < strike + 0.6:
		band = lerpf(5.0, 0.0, (since - strike) / 0.6)
	elif warning:
		band = 0.4 + w * w * 3.6 * (0.7 + 0.3 * sin(t * 47.0))
	_band_mat.emission_energy_multiplier = band
	_tip_mat.emission_energy_multiplier = 0.6 + (w * 5.0 * absf(sin(t * 33.0)) if warning else 0.0) + (6.0 if since < strike else 0.0)
	if _crawl.emitting != warning:
		_crawl.emitting = warning
		_skin.emitting = warning
	if warning and not _was_warn:
		# SOUND: the charge building on the rod (the tell, `warn` s before the bolt)
		WorldAudio.at(self, "tempest_rod_charge", global_position + rod_offset + Vector3(0, 1.5, 0), 0.85, 32.0)
	_was_warn = warning
	# the bolt: a stuttering double flicker over the deadly moment
	var on: bool = since < strike and fposmod(since * 21.0, 1.0) > 0.25
	if _bolt.visible != on:
		_bolt.visible = on
		_bolt.rotation.y = fposmod(float(k) * 2.39, TAU)
	var fl: float = 0.0
	if since < strike + 0.25:
		fl = (1.0 if on else 0.4) * clampf(1.0 - since / (strike + 0.25), 0.0, 1.0)
	_light.light_energy = fl * 8.0
	_light.visible = fl > 0.01


func _strike() -> void:
	_burst.restart()
	_burst.emitting = true
	_wave.restart()
	_wave.emitting = true
	var top: Vector3 = global_transform * (rod_offset + Vector3(0, rod_height, 0))
	# SOUND: the bolt cracking down onto the rod
	WorldAudio.at(self, "tempest_lightning_strike", top, 1.0, 80.0)
	struck.emit(top)


func _build() -> void:
	var steel: StandardMaterial3D = Look.flat(Color(0.55, 0.57, 0.6), 0.35, 0.85)
	var copper: StandardMaterial3D = Look.flat(Color(0.78, 0.45, 0.28), 0.35, 0.85)
	var dark: StandardMaterial3D = Look.flat(Color(0.12, 0.12, 0.13), 0.5, 0.6)
	var foot: Vector3 = rod_offset
	# the rod: a clamp on the beam's flange, a tall copper spike with insulator rings, a crown tip
	add_child(Look.box(Vector3(0.5, 0.22, 0.5), dark, foot + Vector3(0, 0.11, 0)))
	add_child(Look.cylinder(0.07, rod_height, copper, foot + Vector3(0, rod_height * 0.5, 0), 0.035, 8))
	for i: int in 3:
		add_child(Look.cylinder(0.14, 0.1, Look.flat(Color(0.82, 0.86, 0.9), 0.2, 0.1), foot + Vector3(0, 0.6 + float(i) * 0.35, 0), -1.0, 10))
	_tip_mat = Look.flat(CHARGE, 0.2, 0.0, 0.6).duplicate() as StandardMaterial3D
	add_child(Look.sphere(0.13, _tip_mat, foot + Vector3(0, rod_height + 0.05, 0)))
	for i: int in 3:
		var a: float = TAU * float(i) / 3.0
		var prong := Look.box(Vector3(0.03, 0.35, 0.03), steel, foot + Vector3(cos(a) * 0.1, rod_height + 0.12, sin(a) * 0.1))
		prong.rotation = Vector3(sin(a) * 0.45, 0, -cos(a) * 0.45)
		add_child(prong)
	# the live span: hazard bands painted across the beam at both ends of the zone, and a thin glowing
	# strip down each edge (they light up blue as the charge builds and blaze while it is live)
	_band_mat = StandardMaterial3D.new()
	_band_mat.albedo_color = Color(0.95, 0.78, 0.1)
	_band_mat.roughness = 0.5
	_band_mat.emission_enabled = true
	_band_mat.emission = CHARGE
	_band_mat.emission_energy_multiplier = 0.0
	var stripe: StandardMaterial3D = Look.flat(Color(0.08, 0.08, 0.09), 0.6)
	for sz: float in [-1.0, 1.0]:
		var bz: float = sz * (zone.z * 0.5 - 0.12)
		var band := Look.box(Vector3(zone.x + 0.04, 0.03, 0.24), _band_mat, Vector3(0, 0.015, bz))
		band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(band)
		for j: int in 3:
			var st := Look.box(Vector3(0.14, 0.035, 0.25), stripe, Vector3(-zone.x * 0.33 + float(j) * zone.x * 0.33, 0.018, bz))
			st.rotation.y = 0.6
			st.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(st)
	for sx: float in [-1.0, 1.0]:
		var edge := Look.box(Vector3(0.06, 0.03, zone.z - 0.4), _band_mat, Vector3(sx * (zone.x * 0.5 - 0.05), 0.015, 0))
		edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(edge)
	# the bolt from the storm deck to the rod
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(2.0, 2.4, 3.4, 1.0)
	mat.disable_fog = true
	mat.disable_receive_shadows = true
	_bolt = MeshInstance3D.new()
	_bolt.mesh = ArmadaLightning.bolt_mesh(80.0, 13, 0.32, int(absf(position.x * 7.0 + position.z * 13.0 + position.y * 3.0)) + 11)
	_bolt.material_override = mat
	_bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bolt.extra_cull_margin = 90.0
	_bolt.position = foot + Vector3(0, rod_height + 80.0, 0)
	_bolt.visible = false
	add_child(_bolt)
	_light = OmniLight3D.new()
	_light.light_color = Color(0.7, 0.82, 1.0)
	_light.omni_range = 18.0
	_light.shadow_enabled = false
	_light.light_energy = 0.0
	_light.visible = false
	_light.position = foot + Vector3(0, rod_height + 1.0, 0)
	add_child(_light)
	var vis := AABB(Vector3(-zone.x - 6, -2, -zone.z - 6), Vector3(zone.x * 2 + 12, rod_height + 12, zone.z * 2 + 12))
	_crawl = Fx.emitter({"amount": 26, "lifetime": 0.35, "emitting": false, "shape": "box",
		"extents": Vector3(0.1, rod_height * 0.45, 0.1), "dir": Vector3.UP, "spread": 70.0, "speed": Vector2(0.5, 2.2),
		"facing": "velocity", "tex": Fx.Tex.SPARK, "size": Vector2(0.04, 0.3), "color": Color(1.3, 2.0, 3.0),
		"fade": PackedFloat32Array([1.0, 1.0, 0.0]), "aabb": vis})
	_crawl.position = foot + Vector3(0, rod_height * 0.5, 0)
	add_child(_crawl)
	# blue arcs skittering over the live span while it charges
	_skin = Fx.emitter({"amount": int(clampf(zone.x * zone.z * 6.0, 14, 40)), "lifetime": 0.25, "emitting": false,
		"shape": "box", "extents": Vector3(zone.x * 0.5, 0.02, zone.z * 0.5), "dir": Vector3.UP, "spread": 80.0,
		"speed": Vector2(0.4, 1.6), "facing": "velocity", "tex": Fx.Tex.SPARK, "size": Vector2(0.03, 0.22),
		"color": Color(1.2, 1.9, 3.0), "fade": PackedFloat32Array([1.0, 0.0]), "aabb": vis})
	_skin.position = Vector3(0, 0.05, 0)
	add_child(_skin)
	_burst = Fx.sparks({"amount": 46, "shape": "sphere", "radius": 0.3, "dir": Vector3.UP, "spread": 90.0,
		"speed": Vector2(4.0, 12.0), "color": Color(1.8, 2.4, 3.4), "aabb": vis})
	_burst.position = foot + Vector3(0, rod_height, 0)
	add_child(_burst)
	_wave = Fx.shockwave(maxf(zone.x, zone.z) * 0.6 + 0.6, {"color": Color(1.2, 1.8, 3.0, 0.8), "lifetime": 0.45, "aabb": vis})
	_wave.position = Vector3(0, 0.08, 0)
	add_child(_wave)
