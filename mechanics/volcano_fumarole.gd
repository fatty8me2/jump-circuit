class_name VolcanoFumarole
extends Node3D
## Cinder Peak: a fumarole - a sulphur-crusted vent blasting hot gas. While it vents, its
## column is an updraft (like WindZone) that carries you up; a pulsing one vents on a rhythm
## (Game.course_time) and, for `warn` seconds before each blast, coughs yellow puffs and its
## mouth flares - step in then. `on_fraction` 1 = it never stops.
## Positioned at the floor point at the centre of the vent mouth.

@export var size: Vector3 = Vector3(2.4, 9.0, 2.4)
## Upward acceleration while venting (gravity is 30 rising / 42 falling).
@export var push: float = 80.0
## Vertical speed the column will not push past.
@export var max_rise: float = 12.0
@export var period: float = 4.0
@export var on_fraction: float = 0.5
@export var phase: float = 0.0
@export var warn: float = 0.7

var _area: Area3D
var _plume: GPUParticles3D
var _jets: GPUParticles3D
var _cough: GPUParticles3D
var _mouth_mat: StandardMaterial3D
var _light: OmniLight3D
# sound (side effect only): the roaring gas column while it vents
var _roar: AudioStreamPlayer3D


func _ready() -> void:
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 2
	_area.monitorable = false
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	_area.add_child(cs)
	_area.position = Vector3(0, size.y * 0.5, 0)
	add_child(_area)
	_build_visual()
	_roar = WorldAudio.loop("fumarole_loop", self, -5.0, 28.0, 5.0, is_venting_at(Game.course_time))
	if _roar != null:
		_roar.position = Vector3(0, 1.5, 0)
	_apply(Game.course_time)


func is_venting_at(time: float) -> bool:
	return on_fraction >= 1.0 or fposmod(time / period + phase, 1.0) < on_fraction


## Seconds until the next blast starts (0 while venting).
func time_until_vent(time: float) -> float:
	if is_venting_at(time):
		return 0.0
	return (1.0 - fposmod(time / period + phase, 1.0)) * period


## Seconds of venting left (INF for a steady vent, 0 while quiet).
func vent_left(time: float) -> float:
	if on_fraction >= 1.0:
		return INF
	var u: float = fposmod(time / period + phase, 1.0)
	return (on_fraction - u) * period if u < on_fraction else 0.0


func _physics_process(dt: float) -> void:
	var t: float = Game.course_time
	_apply(t)
	if not is_venting_at(t):
		return
	for body: Node3D in _area.get_overlapping_bodies():
		if body is Player:
			var p := body as Player
			var dv := Vector3(0, push * dt, 0)
			if p.velocity.y > max_rise:
				dv.y = 0.0
			p.add_impulse(dv)


func _apply(t: float) -> void:
	var on: bool = is_venting_at(t)
	var warning: bool = not on and time_until_vent(t) < warn
	if _plume.emitting != on:
		_plume.emitting = on
		_jets.emitting = on
	if _cough.emitting != warning:
		_cough.emitting = warning
	WorldAudio.set_active(_roar, on)
	var glow: float = 0.7
	if on:
		glow = 3.2 + 0.4 * sin(t * 23.0)
	elif warning:
		glow = 1.2 + 2.0 * (1.0 - time_until_vent(t) / warn) * (0.7 + 0.3 * sin(t * 36.0))
	if not is_equal_approx(_mouth_mat.emission_energy_multiplier, glow):
		_mouth_mat.emission_energy_multiplier = glow
		_light.light_energy = 0.4 + glow * 0.5


func _build_visual() -> void:
	var r: float = minf(size.x, size.z) * 0.5
	var crust: StandardMaterial3D = Look.flat(Color(0.2, 0.17, 0.12), 0.9)
	var sulphur: StandardMaterial3D = Look.flat(Color(0.95, 0.85, 0.25), 0.6, 0.0, 0.35)
	var pale: StandardMaterial3D = Look.flat(Color(0.85, 0.82, 0.6), 0.8)
	# a low crusted cone round the mouth, streaked with sulphur (decor: the floor is the level's)
	add_child(Look.cylinder(r * 1.1, 0.5, crust, Vector3(0, 0.1, 0), r * 0.72, 14))
	add_child(Look.cylinder(r * 0.8, 0.12, pale, Vector3(0, 0.36, 0), r * 0.7, 14))
	for i: int in 9:
		var a: float = TAU * float(i) / 9.0 + 0.3
		var xtal := Look.box(Vector3(0.16, 0.34 + 0.12 * float(i % 3), 0.16), sulphur, Vector3(cos(a) * r * 0.95, 0.3, sin(a) * r * 0.95))
		xtal.rotation = Vector3(0.35 * sin(a * 3.0), a, 0.4 * cos(a))
		add_child(xtal)
	_mouth_mat = Look.flat(Color(1.0, 0.72, 0.25), 0.4, 0.0, 0.7).duplicate() as StandardMaterial3D
	add_child(Look.cylinder(r * 0.5, 0.06, _mouth_mat, Vector3(0, 0.44, 0), -1.0, 14))
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.75, 0.35)
	_light.omni_range = 7.0
	_light.light_energy = 0.6
	_light.position = Vector3(0, 1.0, 0)
	add_child(_light)
	var vis := AABB(Vector3(-r - 6.0, -1.0, -r - 6.0), Vector3(r * 2.0 + 12.0, size.y + 10.0, r * 2.0 + 12.0))
	# venting: a roaring column of pale gas, and fast bright jets up its core
	var life: float = size.y / 10.0 + 0.8
	_plume = Fx.emitter({"amount": 60, "lifetime": life, "emitting": false, "shape": "sphere", "radius": r * 0.45,
		"dir": Vector3.UP, "spread": 9.0, "speed": Vector2(9.0, 13.0), "damping": Vector2(0.6, 1.4),
		"tex": Fx.Tex.SMOKE, "additive": false, "size": 1.4, "scale": Vector2(0.7, 1.4), "curve": "puff",
		"angle": Vector2(0, 360), "spin": Vector2(-60, 60), "color": Color(0.92, 0.88, 0.62, 0.5),
		"fade": PackedFloat32Array([0.0, 0.9, 0.5, 0.0]), "turbulence": 1.0, "aabb": vis})
	_plume.position = Vector3(0, 0.45, 0)
	add_child(_plume)
	_jets = Fx.emitter({"amount": 40, "lifetime": life * 0.8, "emitting": false, "shape": "sphere", "radius": r * 0.3,
		"dir": Vector3.UP, "spread": 5.0, "speed": Vector2(11.0, 15.0), "facing": "velocity", "tex": Fx.Tex.SPARK,
		"size": Vector2(0.08, 0.9), "color": Color(2.6, 2.2, 1.0, 0.8), "fade": PackedFloat32Array([0.0, 1.0, 0.0]), "aabb": vis})
	_jets.position = Vector3(0, 0.45, 0)
	add_child(_jets)
	# the warning cough: yellow puffs spilling over the lip
	_cough = Fx.emitter({"amount": 16, "lifetime": 0.9, "emitting": false, "shape": "ring", "ring_radius": r * 0.6,
		"ring_inner": r * 0.2, "dir": Vector3.UP, "spread": 50.0, "speed": Vector2(1.2, 2.6), "gravity": Vector3(0, -1.0, 0),
		"tex": Fx.Tex.SMOKE, "additive": false, "size": 0.8, "curve": "puff", "color": Color(0.95, 0.88, 0.4, 0.6),
		"fade": PackedFloat32Array([0.0, 1.0, 0.0]), "aabb": vis})
	_cough.position = Vector3(0, 0.45, 0)
	add_child(_cough)
	# always: a lazy wisp of steam and heat shimmer
	VolcanoFx.steam(self, Vector3(0, 0.5, 0), r * 0.3, 4.0, 8)
	VolcanoFx.haze(self, Vector3(0, 0.4, 0), r * 2.2, minf(size.y, 6.0), 0.005)
