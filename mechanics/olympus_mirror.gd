class_name OlympusMirror
extends Node3D
## Sky Citadel: a SUN MIRROR. A gilded mirror on a pedestal catches a shaft of the low sun and throws
## it across the course as a blade of light. On a fixed rhythm (Game.course_time, identical for
## every racer) the mirror turns to its first angle and a pale footprint of the beam-to-come
## flickers on the floor and a thin guide line wakes (`warn` s, at least 0.8: the mirror glints,
## the footprint brightens and a chime rises); then the blade FIRES and sweeps from angle A to angle B
## in `on_time` seconds, deadly to anyone standing in it, then fades while the mirror turns back.
## The beam is a blade of light: it reaches from `min_range` out to `beam_len` along the mirror's
## heading, `half_width` either side, from the floor up to `beam_h` - too tall to hop.
## The head (`pivot`) turns with the beam so a level can dress it as a hand-mirror held by a giant
## statue (children of `pivot` turn with the beam, along local -Z). Place the node on the floor
## (its origin is the beam's floor level), off the route; the pedestal is dressing, not collision.
##   headings: degrees clockwise from local -Z seen from above (+ = towards local +X)
##   bot helpers: is_on_at(t), time_until_on(t), time_until_off(t), angle_at(t), hits(point, t)

@export var beam_len: float = 14.0
@export var beam_h: float = 2.6
@export var half_width: float = 0.5
@export var min_range: float = 1.2
@export var period: float = 7.0
@export var on_time: float = 1.4
@export var phase: float = 0.0
@export var yaw_a: float = -45.0
@export var yaw_b: float = 45.0
@export var warn: float = 1.0
## The direction the sun's shaft comes from (towards the sun), world space.
@export var sun_dir: Vector3 = Vector3(0.3, 0.55, 0.8)
## Height of the mirror head above the floor.
@export var head_h: float = 1.5
## Dress the head as a plain hand-mirror on a stand (levels that dress their own head turn it off).
@export var plain_head: bool = true

const GOLD := Color(1.0, 0.78, 0.28)
const HOT := Color(1.0, 0.93, 0.62)

var pivot: Node3D
var _blade: Node3D
var _guide: Node3D
var _foot_mat: StandardMaterial3D
var _guide_mat: StandardMaterial3D
var _ray: Node3D
var _ray_mat: StandardMaterial3D
var _glint: MeshInstance3D
var _lamp: OmniLight3D
var _sparks: GPUParticles3D
var _flash: GPUParticles3D
var _motes: GPUParticles3D
var _hum: AudioStreamPlayer3D
var _was_on: bool = false
var _was_charging: bool = false


func _ready() -> void:
	_build()
	add_to_group("course_clock")
	snap_to_clock()


func snap_to_clock() -> void:
	_was_on = is_on_at(Game.course_time)
	_was_charging = false
	_apply(Game.course_time)


# ---- the clock (pure functions of time) -------------------------------------------------------

func _s(time: float) -> float:
	return fposmod(time / period + phase, 1.0) * period


func is_on_at(time: float) -> bool:
	return _s(time) < on_time


## Seconds until the blade next fires (0 while it is firing).
func time_until_on(time: float) -> float:
	var s: float = _s(time)
	return 0.0 if s < on_time else period - s


## Seconds until the blade next goes out (0 while it is out).
func time_until_off(time: float) -> float:
	var s: float = _s(time)
	return on_time - s if s < on_time else 0.0


## The heading (degrees) of the mirror at `time`.
func angle_at(time: float) -> float:
	var s: float = _s(time)
	if s < on_time:
		return lerpf(yaw_a, yaw_b, s / on_time)
	var back_end: float = period - warn
	if s < back_end:
		var k: float = clampf((s - on_time) / maxf(back_end - on_time, 0.01), 0.0, 1.0)
		return lerpf(yaw_b, yaw_a, k * k * (3.0 - 2.0 * k))
	return yaw_a


## True when a body at world `p` would be caught by the blade at `time` (`margin` widens it).
func hits(p: Vector3, time: float, margin: float = 0.0) -> bool:
	if not is_on_at(time):
		return false
	var l: Vector3 = global_transform.affine_inverse() * p
	var a: float = deg_to_rad(angle_at(time))
	var along: float = l.x * sin(a) - l.z * cos(a)
	var across: float = l.x * cos(a) + l.z * sin(a)
	return along > min_range - margin and along < beam_len + margin and absf(across) < half_width + margin \
		and l.y > -0.4 and l.y < beam_h


# ---- per tick ---------------------------------------------------------------------------------

func _physics_process(_dt: float) -> void:
	var t: float = Game.course_time
	_apply(t)
	if not is_on_at(t):
		return
	var n: Node = self
	while n != null and not n.has_method("fail"):
		n = n.get_parent()
	if n == null:
		return
	var pl: Player = n.get("player") as Player
	if pl != null and hits(pl.global_position + Vector3(0, 0.5, 0), t, 0.25):
		n.call_deferred("fail", "hazard")


func _apply(t: float) -> void:
	pivot.rotation.y = -deg_to_rad(angle_at(t))
	var on: bool = is_on_at(t)
	var until_on: float = time_until_on(t)
	var charging: bool = not on and until_on < warn
	_blade.visible = on
	_guide.visible = charging or on
	_ray.visible = charging or on
	if on:
		_foot_mat.albedo_color.a = 0.55
		_ray_mat.albedo_color.a = 0.5
	elif charging:
		var k: float = clampf(1.0 - until_on / maxf(warn, 0.01), 0.0, 1.0)
		var flick: float = 0.5 + 0.5 * sin(t * lerpf(10.0, 34.0, k) * TAU * 0.5)
		_foot_mat.albedo_color.a = lerpf(0.1, 0.45, k) * (0.55 + 0.45 * flick)
		_ray_mat.albedo_color.a = lerpf(0.15, 0.5, k)
		_glint.scale = Vector3.ONE * lerpf(0.4, 1.4, k) * (0.8 + 0.2 * flick)
		_lamp.light_energy = lerpf(0.3, 2.0, k) * (0.7 + 0.3 * flick)
	_glint.visible = charging or on
	_lamp.visible = charging or on
	if on:
		_lamp.light_energy = 3.0


func _process(_dt: float) -> void:
	var t: float = Game.course_time
	var on: bool = is_on_at(t)
	var charging: bool = not on and time_until_on(t) < warn
	if charging and not _was_charging:
		_motes.emitting = true
		# SOUND: olympus_mirror_charge - a rising chime and a glint of bright metal (the tell, `warn` s ahead)
		WorldAudio.at(self, "olympus_mirror_charge", global_position + Vector3(0, head_h, 0), 0.7, 34.0)
		WorldAudio.set_active(_hum, true)
	if not charging and _was_charging:
		_motes.emitting = false
	_was_charging = charging
	if on != _was_on:
		_was_on = on
		_sparks.emitting = on
		if on:
			_flash.restart()
			_flash.emitting = true
			# SOUND: olympus_mirror_fire - the blade of light striking out across the court
			WorldAudio.at(self, "olympus_mirror_fire", global_position + Vector3(0, head_h, 0), 0.9, 40.0)
		else:
			WorldAudio.set_active(_hum, false)


# ---- look -------------------------------------------------------------------------------------

func _unshaded(col: Color, a: float, add: bool = true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if add:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(col.r, col.g, col.b, a)
	m.disable_receive_shadows = true
	return m


func _build() -> void:
	pivot = Node3D.new()
	pivot.position = Vector3(0, head_h, 0)
	add_child(pivot)
	# the blade: a white-hot core, a golden sleeve, along the pivot's -Z from min_range to beam_len
	_blade = Node3D.new()
	_blade.position = Vector3(0, -head_h, 0)
	pivot.add_child(_blade)
	var core_mat: StandardMaterial3D = _unshaded(HOT, 0.95, false)
	core_mat.emission_enabled = true
	core_mat.emission = HOT
	core_mat.emission_energy_multiplier = 3.0
	var reach: float = beam_len - min_range
	var mid_z: float = -(min_range + reach * 0.5)
	var core := Look.box(Vector3(0.1, beam_h, reach), core_mat, Vector3(0, beam_h * 0.5, mid_z))
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_blade.add_child(core)
	var sleeve := Look.box(Vector3(half_width * 1.7, beam_h, reach), _unshaded(GOLD, 0.2), Vector3(0, beam_h * 0.5, mid_z))
	sleeve.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_blade.add_child(sleeve)
	# the footprint on the floor: faint while charging, bright while firing (marks exactly where it kills)
	_foot_mat = _unshaded(GOLD, 0.2)
	_guide = Node3D.new()
	_guide.position = Vector3(0, -head_h, 0)
	pivot.add_child(_guide)
	var foot := Look.box(Vector3(half_width * 2.0, 0.03, reach), _foot_mat, Vector3(0, 0.04, mid_z))
	foot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_guide.add_child(foot)
	_guide_mat = _unshaded(HOT, 0.6)
	var line := Look.box(Vector3(0.04, 0.04, reach), _guide_mat, Vector3(0, head_h, mid_z))
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_guide.add_child(line)
	# the shaft of sunlight falling onto the mirror from the sun (fixed in the world, not turning)
	_ray = Node3D.new()
	_ray_mat = _unshaded(HOT, 0.3)
	var sd: Vector3 = sun_dir.normalized()
	var ray_len: float = 26.0
	var ray := Look.box(Vector3(0.14, 0.14, ray_len), _ray_mat, Vector3.ZERO)
	ray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ray.add_child(ray)
	_ray.transform = Transform3D(_basis_z_toward(sd), Vector3(0, head_h, 0) + sd * ray_len * 0.5)
	add_child(_ray)
	_glint = Fx.sprite(Color(3.0, 2.4, 1.3, 1.0), 2.2, Fx.Tex.STAR, true)
	_glint.position = Vector3(0, head_h + 0.2, 0)
	_glint.visible = false
	add_child(_glint)
	_lamp = OmniLight3D.new()
	_lamp.light_color = Color(1.0, 0.82, 0.45)
	_lamp.omni_range = 9.0
	_lamp.light_energy = 0.0
	_lamp.position = Vector3(0, head_h + 0.3, 0)
	_lamp.visible = false
	add_child(_lamp)
	if plain_head:
		_plain_head()
	var vis := AABB(Vector3(-beam_len - 2.0, -3.0, -beam_len - 2.0), Vector3(beam_len * 2.0 + 4.0, 8.0, beam_len * 2.0 + 4.0))
	_sparks = Fx.emitter({"amount": 40, "lifetime": 0.6, "emitting": false, "shape": "box",
		"extents": Vector3(0.3, beam_h * 0.4, reach * 0.5), "offset": Vector3(0, beam_h * 0.5 - head_h, mid_z),
		"dir": Vector3.UP, "spread": 70.0, "speed": Vector2(0.6, 2.4), "tex": Fx.Tex.STAR, "size": 0.18,
		"color": Fx.hot(GOLD, 2.4), "curve": "shrink", "local": true, "aabb": vis})
	pivot.add_child(_sparks)
	_flash = Fx.burst({"amount": 28, "lifetime": 0.5, "spread": 180.0, "speed": Vector2(2.0, 6.0), "tex": Fx.Tex.STAR,
		"size": 0.28, "color": Fx.hot(HOT, 2.6), "emitting": false, "aabb": vis})
	_flash.position = Vector3(0, head_h, 0)
	add_child(_flash)
	_motes = Fx.emitter({"amount": 24, "lifetime": 0.8, "emitting": false, "shape": "sphere", "radius": 1.0,
		"offset": Vector3(0, head_h, 0), "speed": Vector2.ZERO, "radial": Vector2(-3.0, -1.5), "tex": Fx.Tex.DOT,
		"size": 0.14, "color": Fx.hot(HOT, 2.2), "curve": "pop", "aabb": vis})
	add_child(_motes)
	# SOUND: olympus_mirror_hum - the focused sunlight singing while it charges and fires (loop)
	_hum = WorldAudio.loop("olympus_mirror_hum", self, -16.0, 26.0, 4.0, false)


## A basis whose +Z points along `d` (for orienting a long box from the mirror toward the sun).
static func _basis_z_toward(d: Vector3) -> Basis:
	var z: Vector3 = d.normalized()
	var up: Vector3 = Vector3.UP if absf(z.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x: Vector3 = up.cross(z).normalized()
	var y: Vector3 = z.cross(x)
	return Basis(x, y, z)


func _plain_head() -> void:
	var marble: StandardMaterial3D = Look.flat(Color(0.95, 0.92, 0.84), 0.45)
	var gold: StandardMaterial3D = Look.flat(GOLD, 0.35, 0.6, 0.4)
	add_child(Look.cylinder(0.5, 0.25, marble, Vector3(0, 0.125, 0), 0.62, 16))
	add_child(Look.cylinder(0.3, head_h - 0.3, marble, Vector3(0, (head_h + 0.25) * 0.5 - 0.1, 0), 0.22, 14))
	# the mirror: a polished gold disc on a yoke, face along the beam (turns with the pivot)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(1.0, 0.95, 0.8)
	glass.metallic = 1.0
	glass.roughness = 0.08
	glass.emission_enabled = true
	glass.emission = GOLD
	glass.emission_energy_multiplier = 0.5
	var disc := Look.cylinder(0.55, 0.06, glass, Vector3(0, 0.1, 0), -1.0, 24)
	disc.rotation.x = PI * 0.5
	disc.rotation.y = 0.5
	pivot.add_child(disc)
	var rim := Look.cylinder(0.6, 0.05, gold, Vector3(0, 0.1, 0.03), -1.0, 24)
	rim.rotation.x = PI * 0.5
	pivot.add_child(rim)
