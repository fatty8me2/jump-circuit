class_name SiegeBoulder
extends Node3D
## Castle Siege: a TREBUCHET BOULDER landing zone. Once per `period` (Game.course_time) a siege
## engine somewhere out in the dusk hurls a flaming stone that lands exactly on this painted ring.
## The ring is always faintly marked on the stone; for `warn` seconds (the tell, at least 0.8) before
## impact the landing shadow brightens, pulses faster and a dark disc swells from the middle out - when
## the disc touches the rim, the boulder hits. The zone is deadly for `deadly` seconds (a cylinder
## `radius` wide, from just under the floor to head height), then rubble and a smouldering crater
## stay on the stone. The boulder itself is in view for its last `flight` seconds, arcing in from
## `source` (an offset from the ring, toward the trebuchet) trailing fire and smoke, and whistling
## for the last ~1.1 s. Node origin = the floor point at the ring's centre.
## A pure function of the course clock: identical for every racer.

@export var radius: float = 1.9
@export var period: float = 4.5
@export var phase: float = 0.0
@export var warn: float = 1.5
@export var deadly: float = 0.4
@export var flight: float = 2.4
## Where the boulder comes from, relative to the ring (world axes): toward the trebuchet.
@export var source: Vector3 = Vector3(0, 46, 70)

const RING := Color(1.0, 0.42, 0.12)

var _ring_mat: StandardMaterial3D
var _fill: MeshInstance3D
var _fill_mat: StandardMaterial3D
var _crater_mat: StandardMaterial3D
var _rock: Node3D
var _trail: GPUParticles3D
var _smoke: GPUParticles3D
var _dust: GPUParticles3D
var _debris: GPUParticles3D
var _wave: GPUParticles3D
var _flash: OmniLight3D
var _was_deadly: bool = false
var _was_flying: bool = false
var _whistled: bool = false
var _hit_tick: int = -100


func _ready() -> void:
	warn = maxf(warn, 0.8)
	_build()
	_was_deadly = is_deadly_at(Game.course_time)
	_apply(Game.course_time)
	add_to_group("course_clock")


func snap_to_clock() -> void:
	_was_deadly = is_deadly_at(Game.course_time)
	_apply(Game.course_time)


## Seconds into the cycle: the boulder lands at 0.
func _s(time: float) -> float:
	return fposmod(time / maxf(period, 0.01) + phase, 1.0) * period


## True while the zone is deadly (from impact for `deadly` s).
func is_deadly_at(time: float) -> bool:
	return _s(time) < deadly


## Seconds until the next impact (0 while the zone is deadly).
func time_until_impact(time: float) -> float:
	var s: float = _s(time)
	return 0.0 if s < deadly else period - s


## True when nothing lands on the ring anywhere in [time + a, time + b] (a little margin either side).
func is_clear_between(time: float, a: float, b: float, margin: float = 0.12) -> bool:
	var s: float = a - margin
	while s <= b + margin:
		if is_deadly_at(time + s):
			return false
		s += 0.03
	return not is_deadly_at(time + b + margin)


func _physics_process(_dt: float) -> void:
	var t: float = Game.course_time
	_apply(t)
	if not is_deadly_at(t):
		return
	var pl: Node3D = WorldAudio.local_player(self)
	if pl == null:
		return
	var rel: Vector3 = pl.global_position - global_position
	if Vector2(rel.x, rel.z).length() < radius + 0.2 and rel.y > -1.0 and rel.y < 2.4:
		var tick: int = Engine.get_physics_frames()
		if tick - _hit_tick > 20:
			_hit_tick = tick
			KitUtil.kill(self)


func _process(_dt: float) -> void:
	_apply(Game.course_time)


func _apply(t: float) -> void:
	var until: float = time_until_impact(t)
	var deadly_now: bool = until <= 0.0
	# the boulder in flight
	var flying: bool = not deadly_now and until < flight
	if flying:
		var k: float = 1.0 - until / flight
		var arc: Vector3 = source * (1.0 - k)
		arc.y = source.y * (1.0 - k) + source.length() * 0.3 * 4.0 * k * (1.0 - k)
		_rock.position = arc + Vector3(0, 0.7, 0)
		_rock.rotation = Vector3(k * 7.0, k * 3.0, k * 2.0)
		if not _was_flying:
			_rock.visible = true
			_rock.reset_physics_interpolation()
			_trail.emitting = true
			_smoke.emitting = true
			# SOUND: siege_boulder_launch - the creak and whump of a trebuchet arm letting go
			WorldAudio.at(self, "siege_boulder_launch", global_position + source * 0.5, 0.7, 90.0)
			_whistled = false
		if not _whistled and until < 1.1:
			_whistled = true
			# SOUND: siege_boulder_whistle - a rising whistle as the stone comes down (the audible tell)
			WorldAudio.at(self, "siege_boulder_whistle", global_position + Vector3(0, 3.0, 0), 0.85, 45.0)
	elif _was_flying:
		_rock.visible = false
		_trail.emitting = false
		_smoke.emitting = false
	_was_flying = flying
	# impact
	if deadly_now and not _was_deadly:
		_dust.restart()
		_debris.restart()
		_wave.restart()
		Fx.pulse(_flash, 6.0, 0.0, 0.5)
		# SOUND: siege_boulder_impact - a stone crashing onto masonry
		WorldAudio.at(self, "siege_boulder_impact", global_position + Vector3(0, 0.5, 0), 1.0, 60.0)
	_was_deadly = deadly_now
	# the landing shadow and its swelling disc
	var glow: float = 0.8 + 0.3 * sin(t * 3.0)
	var fill: float = 0.0
	if deadly_now:
		glow = 6.0
		fill = 1.0
	elif until < warn:
		var k2: float = 1.0 - until / warn
		glow = 1.4 + 5.0 * k2 * (0.7 + 0.3 * sin(t * (10.0 + 22.0 * k2)))
		fill = k2
	_ring_mat.emission_energy_multiplier = glow
	_fill.visible = fill > 0.01
	if _fill.visible:
		var r: float = maxf(fill, 0.05) * radius * 0.94
		_fill.scale = Vector3(r, 1.0, r)
		_fill_mat.albedo_color = Color(0.1 + 0.5 * fill, 0.02 + 0.1 * fill, 0.01, 0.3 + 0.45 * fill)
	# the crater smoulders for a couple of seconds after each hit
	var since: float = _s(t)
	var hot: float = clampf(1.0 - since / 2.5, 0.0, 1.0)
	_crater_mat.emission_energy_multiplier = 0.1 + 2.4 * hot * hot


func _build() -> void:
	# the ring: a flat torus painted on the stone, with four ticks pointing in so it reads as a target
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.albedo_color = Color(0.25, 0.07, 0.03)
	_ring_mat.emission_enabled = true
	_ring_mat.emission = RING
	_ring_mat.emission_energy_multiplier = 1.0
	var tm := TorusMesh.new()
	tm.inner_radius = radius * 0.9
	tm.outer_radius = radius
	tm.rings = 48
	tm.ring_segments = 6
	var ring := Look.mesh_node(tm, _ring_mat, Vector3(0, 0.04, 0))
	ring.scale = Vector3(1, 0.3, 1)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	for i: int in 4:
		var a: float = TAU * float(i) / 4.0 + PI * 0.25
		var tick := Look.box(Vector3(0.12, 0.05, radius * 0.28), _ring_mat, Vector3(cos(a), 0, sin(a)) * radius * 0.78 + Vector3(0, 0.05, 0))
		tick.rotation.y = -a + PI * 0.5
		tick.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(tick)
	_crater_mat = StandardMaterial3D.new()
	_crater_mat.albedo_color = Color(0.1, 0.085, 0.08)
	_crater_mat.roughness = 0.95
	_crater_mat.emission_enabled = true
	_crater_mat.emission = Color(1.0, 0.4, 0.1)
	_crater_mat.emission_energy_multiplier = 0.1
	var crater := Look.cylinder(radius * 0.55, 0.03, _crater_mat, Vector3(0, 0.02, 0), -1.0, 20)
	crater.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(crater)
	# a few rubble stones lie where earlier boulders broke
	var rub: StandardMaterial3D = Look.flat(Color(0.42, 0.4, 0.38), 0.95)
	for i: int in 5:
		var a2: float = TAU * float(i) / 5.0 + 0.4
		var d: float = radius * (0.35 + 0.12 * float(i % 3))
		var s: float = 0.14 + 0.05 * float(i % 3)
		var stone := Look.box(Vector3(s * 1.6, s, s * 1.2), rub, Vector3(cos(a2) * d, s * 0.5, sin(a2) * d))
		stone.rotation.y = a2 * 2.0
		add_child(stone)
	# the countdown disc
	_fill_mat = StandardMaterial3D.new()
	_fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fill_mat.albedo_color = Color(0.3, 0.06, 0.02, 0.3)
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.02
	disc.radial_segments = 32
	disc.rings = 1
	_fill = Look.mesh_node(disc, _fill_mat, Vector3(0, 0.07, 0))
	_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_fill)
	# the boulder: a rough grey stone wrapped in burning pitch, with its own light, fire and smoke
	_rock = Node3D.new()
	_rock.visible = false
	var stone_m: StandardMaterial3D = Look.flat(Color(0.34, 0.32, 0.31), 0.95)
	var pitch_m: StandardMaterial3D = Look.flat(Color(1.0, 0.5, 0.12), 0.5, 0.0, 3.2)
	_rock.add_child(Look.sphere(0.7, stone_m))
	for i: int in 6:
		var a3: float = TAU * float(i) / 6.0
		var lump := Look.sphere(0.34, stone_m, Vector3(cos(a3) * 0.5, sin(a3 * 2.0) * 0.38, sin(a3) * 0.5))
		lump.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_rock.add_child(lump)
	var pitch := Look.sphere(0.5, pitch_m, Vector3(0, 0.34, 0))
	pitch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rock.add_child(pitch)
	var bl := OmniLight3D.new()
	bl.light_color = Color(1.0, 0.55, 0.2)
	bl.light_energy = 2.2
	bl.omni_range = 7.0
	bl.shadow_enabled = false
	_rock.add_child(bl)
	add_child(_rock)
	var reach: float = source.length() + 10.0
	var vis := AABB(Vector3(-reach, -4.0, -reach), Vector3(reach * 2.0, source.y + reach, reach * 2.0))
	_trail = Fx.trail({"amount": 70, "lifetime": 0.8, "size": 0.9, "color": Color(3.0, 1.3, 0.35),
		"speed": Vector2(0.0, 0.6), "aabb": vis})
	_trail.local_coords = false
	_rock.add_child(_trail)
	_smoke = Fx.emitter({"amount": 40, "lifetime": 1.8, "emitting": false, "tex": Fx.Tex.SMOKE, "additive": false,
		"size": 1.4, "speed": Vector2(0.0, 0.8), "spread": 180.0, "curve": "puff", "fixed_fps": 0,
		"color": Color(0.16, 0.13, 0.12, 0.75), "fade": PackedFloat32Array([0.0, 0.8, 0.0]), "angle": Vector2(0, 360), "aabb": vis})
	_smoke.local_coords = false
	_rock.add_child(_smoke)
	# impact: a dust cloud, rock chips, a shock ring and a flash
	_dust = Fx.smoke({"amount": 22, "lifetime": 1.2, "shape": "sphere", "radius": radius * 0.5, "dir": Vector3.UP,
		"spread": 80.0, "speed": Vector2(1.5, 4.0), "size": 1.6, "color": Color(0.62, 0.55, 0.5, 0.7),
		"aabb": AABB(Vector3(-10, -3, -10), Vector3(20, 12, 20))})
	_dust.position = Vector3(0, 0.3, 0)
	add_child(_dust)
	_debris = Fx.debris({"amount": 16, "lifetime": 1.0, "color": Color(0.5, 0.47, 0.44), "chunk": 0.22,
		"speed": Vector2(4.0, 8.0), "aabb": AABB(Vector3(-10, -3, -10), Vector3(20, 12, 20))})
	_debris.position = Vector3(0, 0.3, 0)
	add_child(_debris)
	_wave = Fx.shockwave(radius * 1.6, {"color": Color(2.6, 1.5, 0.7), "lifetime": 0.45})
	_wave.position = Vector3(0, 0.12, 0)
	add_child(_wave)
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.6, 0.25)
	_flash.omni_range = radius * 5.0
	_flash.light_energy = 0.0
	_flash.visible = false
	_flash.shadow_enabled = false
	_flash.position = Vector3(0, 1.5, 0)
	add_child(_flash)
