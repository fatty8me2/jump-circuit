class_name VolcanoBomb
extends Node3D
## Cinder Peak: a lava-bomb landing zone. Once per `period` (Game.course_time) the volcano
## lobs a bomb that lands exactly on this ring. The ring is always faintly marked; for `warn`
## seconds before impact it brightens, pulses faster and a molten disc fills it from the
## middle out - when the disc touches the rim, the bomb hits. The zone is deadly for `deadly`
## seconds (a cylinder `radius` wide, from just under the floor to head height), then a
## splat of fresh lava cools on the rock. The bomb itself is visible for its last `flight`
## seconds, arcing in from `source` (an offset from the ring, toward the volcano) trailing
## smoke and embers. Positioned at the floor point at the ring's centre.

@export var radius: float = 2.0
@export var period: float = 4.0
@export var phase: float = 0.0
@export var warn: float = 1.5
@export var deadly: float = 0.35
@export var flight: float = 2.2
## Where the bomb comes from, relative to the ring (world axes).
@export var source: Vector3 = Vector3(0, 70, -60)

const RING_COLOR := Color(1.0, 0.3, 0.08)

var _ring_mat: StandardMaterial3D
var _fill: MeshInstance3D
var _fill_mat: StandardMaterial3D
var _splat_mat: StandardMaterial3D
var _bomb: Node3D
var _trail: GPUParticles3D
var _smoke: GPUParticles3D
var _splash: GPUParticles3D
var _puff: GPUParticles3D
var _debris: GPUParticles3D
var _wave: GPUParticles3D
var _flash: OmniLight3D
var _level: LevelBase
var _was_deadly: bool = false
var _was_flying: bool = false
var _whistled: bool = false


func _ready() -> void:
	_build()
	_was_deadly = is_deadly_at(Game.course_time)
	_apply(Game.course_time)


## Fraction of the cycle at `time`; the bomb lands at u = 0.
func _u(time: float) -> float:
	return fposmod(time / period + phase, 1.0)


## True while the zone burns (from impact for `deadly` s).
func is_deadly_at(time: float) -> bool:
	return _u(time) * period < deadly


## Seconds until the next impact (0 while the zone is deadly).
func time_until_impact(time: float) -> float:
	var s: float = _u(time) * period
	return 0.0 if s < deadly else period - s


## No burn anywhere in [now + a, now + b].
func is_clear_between(time: float, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if is_deadly_at(time + s):
			return false
		s += 0.03
	return is_deadly_at(time + b) == false


func _physics_process(_dt: float) -> void:
	var t: float = Game.course_time
	_apply(t)
	if not is_deadly_at(t):
		return
	if _level == null:
		_level = VolcanoLava.level_of(self)
		if _level == null:
			return
	var p: Player = _level.player
	if p == null or _level.finished:
		return
	var rel: Vector3 = p.global_position - global_position
	if Vector2(rel.x, rel.z).length() < radius + 0.25 and rel.y > -1.0 and rel.y < 2.4:
		_level.fail("hazard")


func _apply(t: float) -> void:
	var until: float = time_until_impact(t)
	var deadly_now: bool = until <= 0.0
	# the bomb in flight
	var flying: bool = not deadly_now and until < flight
	if flying:
		var k: float = 1.0 - until / flight
		var arc: Vector3 = source * (1.0 - k)
		arc.y = source.y * (1.0 - k) + source.length() * 0.35 * 4.0 * k * (1.0 - k)
		_bomb.position = arc + Vector3(0, 0.6, 0)
		_bomb.rotation = Vector3(k * 9.0, k * 5.0, 0)
		if not _was_flying:
			_bomb.visible = true
			_bomb.reset_physics_interpolation()
			_trail.emitting = true
			_smoke.emitting = true
			WorldAudio.at(self, "bomb_launch", global_position + source * 0.5, 0.6, 90.0)
			_whistled = false
		if not _whistled and until < 1.1:
			_whistled = true
			WorldAudio.at(self, "bomb_whistle", global_position + Vector3(0, 3.0, 0), 0.8, 45.0)
	elif _was_flying:
		_bomb.visible = false
		_trail.emitting = false
		_smoke.emitting = false
	_was_flying = flying
	# impact
	if deadly_now and not _was_deadly:
		_splash.restart()
		_puff.restart()
		_debris.restart()
		_wave.restart()
		Fx.pulse(_flash, 7.0, 0.0, 0.5)
		WorldAudio.at(self, "bomb_impact", global_position + Vector3(0, 0.5, 0), 1.0, 60.0)
	_was_deadly = deadly_now
	# the warning ring and the filling disc
	var glow: float = 0.9 + 0.35 * sin(t * 3.0)
	var fill: float = 0.0
	if deadly_now:
		glow = 6.0
		fill = 1.0
	elif until < warn:
		var k2: float = 1.0 - until / warn
		glow = 1.5 + 5.0 * k2 * (0.7 + 0.3 * sin(t * (10.0 + 22.0 * k2)))
		fill = k2
	_ring_mat.emission_energy_multiplier = glow
	_fill.visible = fill > 0.01
	if _fill.visible:
		var r: float = maxf(fill, 0.05) * radius * 0.92
		_fill.scale = Vector3(r, 1.0, r)
		_fill_mat.albedo_color = Color(1.0, 0.45 + 0.3 * fill, 0.1, 0.25 + 0.45 * fill)
	# the fresh splat cools over a couple of seconds after the hit
	var since: float = _u(t) * period
	var hot: float = clampf(1.0 - since / 2.5, 0.0, 1.0)
	_splat_mat.emission_energy_multiplier = 0.15 + 3.0 * hot * hot


func _build() -> void:
	# the ring (a flat torus) and the scorched ground it marks
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.albedo_color = Color(0.25, 0.05, 0.02)
	_ring_mat.emission_enabled = true
	_ring_mat.emission = RING_COLOR
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
	# four tick marks pointing in, so the ring reads as a target from any angle
	for i: int in 4:
		var a: float = TAU * float(i) / 4.0 + PI * 0.25
		var tick := Look.box(Vector3(0.12, 0.05, radius * 0.28), _ring_mat, Vector3(cos(a), 0, sin(a)) * radius * 0.78 + Vector3(0, 0.05, 0))
		tick.rotation.y = -a + PI * 0.5
		tick.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(tick)
	_splat_mat = StandardMaterial3D.new()
	_splat_mat.albedo_color = Color(0.08, 0.04, 0.035)
	_splat_mat.roughness = 0.9
	_splat_mat.emission_enabled = true
	_splat_mat.emission = Color(1.0, 0.35, 0.06)
	_splat_mat.emission_energy_multiplier = 0.15
	var splat := Look.cylinder(radius * 0.62, 0.03, _splat_mat, Vector3(0, 0.02, 0), -1.0, 20)
	splat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(splat)
	# the countdown disc
	_fill_mat = StandardMaterial3D.new()
	_fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fill_mat.albedo_color = Color(1.0, 0.5, 0.1, 0.3)
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.02
	disc.radial_segments = 32
	disc.rings = 1
	_fill = Look.mesh_node(disc, _fill_mat, Vector3(0, 0.07, 0))
	_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_fill)
	# the bomb: a glowing, crusted blob with its own light and a trail of fire and smoke
	_bomb = Node3D.new()
	_bomb.visible = false
	var crust := Look.flat(Color(0.12, 0.05, 0.03), 0.8, 0.0, 0.0)
	var core := Look.flat(Color(1.0, 0.5, 0.12), 0.4, 0.0, 4.0)
	_bomb.add_child(Look.sphere(0.62, core))
	for i: int in 5:
		var a: float = TAU * float(i) / 5.0
		var lump := Look.sphere(0.34, crust, Vector3(cos(a) * 0.42, sin(a * 2.0) * 0.3, sin(a) * 0.42))
		lump.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_bomb.add_child(lump)
	var bl := OmniLight3D.new()
	bl.light_color = Color(1.0, 0.5, 0.15)
	bl.light_energy = 2.5
	bl.omni_range = 7.0
	_bomb.add_child(bl)
	add_child(_bomb)
	var reach: float = source.length() + 10.0
	var vis := AABB(Vector3(-reach, -4.0, -reach), Vector3(reach * 2.0, source.y + reach, reach * 2.0))
	_trail = Fx.trail({"amount": Fx.count(70), "lifetime": 0.7, "size": 0.9, "color": Color(3.0, 1.2, 0.3),
		"speed": Vector2(0.0, 0.6), "aabb": vis})
	_trail.local_coords = false
	_bomb.add_child(_trail)
	_smoke = Fx.emitter({"amount": 40, "lifetime": 1.6, "emitting": false, "tex": Fx.Tex.SMOKE, "additive": false,
		"size": 1.3, "speed": Vector2(0.0, 0.8), "spread": 180.0, "curve": "puff", "fixed_fps": 0,
		"color": Color(0.14, 0.11, 0.1, 0.75), "fade": PackedFloat32Array([0.0, 0.8, 0.0]), "angle": Vector2(0, 360), "aabb": vis})
	_smoke.local_coords = false
	_bomb.add_child(_smoke)
	# impact: a spray of molten droplets, a shock ring, rock chunks, a smoke puff and a flash
	_splash = VolcanoFx.splash(self, Vector3(0, 0.2, 0), radius, 46, 9.0)
	_puff = VolcanoFx.puff(self, Vector3(0, 0.5, 0), radius, 12)
	_debris = Fx.debris({"amount": 16, "lifetime": 1.0, "color": Color(0.2, 0.12, 0.1), "chunk": 0.22,
		"speed": Vector2(4.0, 8.0), "aabb": AABB(Vector3(-10, -3, -10), Vector3(20, 12, 20))})
	_debris.position = Vector3(0, 0.3, 0)
	add_child(_debris)
	_wave = Fx.shockwave(radius * 1.6, {"color": Color(3.0, 1.2, 0.3), "lifetime": 0.45})
	_wave.position = Vector3(0, 0.12, 0)
	add_child(_wave)
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.55, 0.2)
	_flash.omni_range = radius * 5.0
	_flash.light_energy = 0.0
	_flash.visible = false
	_flash.position = Vector3(0, 1.5, 0)
	add_child(_flash)
