class_name XenoGeyser
extends Node3D
## Xeno Wilds: an acid geyser that erupts on a fixed rhythm (Game.course_time) in two colours with
## one rule each:
##   TEAL steam  - the first part of an eruption is a roaring column of vapour that LIFTS you (an
##                 updraft, like a vent): step in as it blows and ride it up past the ledges;
##   LIME acid   - then the acid itself surges up the column: anyone still inside it is burned.
## So: ride the steam, be out before it turns green. For `warn` s before each eruption the crater
## bubbles and its glow flares. With `lift` = 0 a geyser is a pure acid jet (a timing gate).
## Positioned at the floor point at the base (centre) of the column.
##   u [0, lift) steam   [lift, lift + acid) acid   the rest quiet (the last `warn` s bubbling)

const STEAM: Color = Color(0.45, 1.0, 0.95)
const ACID: Color = Color(0.8, 1.0, 0.15)

@export var size: Vector3 = Vector3(2.4, 9.0, 2.4)
@export var push: float = 80.0
@export var max_rise: float = 12.0
@export var period: float = 4.0
@export var phase: float = 0.0
## Fractions of the cycle: steam (lifting), then acid (burning).
@export var lift: float = 0.45
@export var acid: float = 0.2
@export var warn: float = 0.7

var _area: Area3D
var _steam: GPUParticles3D
var _acid: GPUParticles3D
var _spit: GPUParticles3D
var _bubbles: GPUParticles3D
var _glow_mat: StandardMaterial3D
var _light: OmniLight3D
var _was_lift: bool = false
var _was_acid: bool = false


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
	var t: float = Game.course_time
	_was_lift = is_lifting_at(t)
	_was_acid = is_acid_at(t)
	_apply(t)


func _u(time: float) -> float:
	return fposmod(time / period + phase, 1.0)


func is_lifting_at(time: float) -> bool:
	return _u(time) < lift


func is_acid_at(time: float) -> bool:
	var u: float = _u(time)
	return u >= lift and u < lift + acid


## Seconds until the next eruption (steam) starts; 0 while it is steaming.
func time_until_lift(time: float) -> float:
	var u: float = _u(time)
	return 0.0 if u < lift else (1.0 - u) * period


## Seconds of steam left (0 when not steaming).
func lift_left(time: float) -> float:
	var u: float = _u(time)
	return (lift - u) * period if u < lift else 0.0


## Seconds until the column next burns (0 while it burns).
func time_until_acid(time: float) -> float:
	var u: float = _u(time)
	if u >= lift and u < lift + acid:
		return 0.0
	return fposmod(lift - u, 1.0) * period


## The column is harmless for the whole window [time, time + window].
func is_safe_for(time: float, window: float) -> bool:
	var s: float = 0.0
	while s <= window:
		if is_acid_at(time + s):
			return false
		s += 0.04
	return true


func _physics_process(dt: float) -> void:
	var t: float = Game.course_time
	_apply(t)
	var lifting: bool = is_lifting_at(t)
	var burning: bool = is_acid_at(t)
	if not lifting and not burning:
		return
	for body: Node3D in _area.get_overlapping_bodies():
		if not (body is Player):
			continue
		var p := body as Player
		if burning:
			# the acid fills the column's core: a runner brushing its rim is spared
			var off: Vector3 = p.global_position - global_position
			if Vector2(off.x, off.z).length() < minf(size.x, size.z) * 0.45:
				var n: Node = self
				while n != null and not n.has_method("fail"):
					n = n.get_parent()
				if n != null:
					n.call_deferred("fail", "hazard")
				return
		var dv := Vector3(0, push * dt, 0)
		if p.velocity.y > max_rise:
			dv.y = 0.0
		p.add_impulse(dv)


func _apply(t: float) -> void:
	var lifting: bool = is_lifting_at(t)
	var burning: bool = is_acid_at(t)
	var until: float = time_until_lift(t)
	var warning: bool = not lifting and not burning and until < warn
	if _steam.emitting != lifting:
		_steam.emitting = lifting
	if _acid.emitting != burning:
		_acid.emitting = burning
	if _bubbles.emitting != warning:
		_bubbles.emitting = warning
	if lifting and not _was_lift:
		WorldAudio.at(self, "geyser_erupt", global_position + Vector3(0, 1.0, 0), 1.0, 45.0)
	if burning and not _was_acid:
		_spit.restart()
		_spit.emitting = true
	_was_lift = lifting
	_was_acid = burning
	var glow: float = 0.7
	var col: Color = STEAM
	if lifting:
		glow = 2.6
	elif burning:
		glow = 4.0
		col = ACID
	elif warning:
		glow = 0.9 + 2.2 * (1.0 - until / warn) * (0.75 + 0.25 * sin(t * 36.0))
		col = STEAM.lerp(ACID, 0.3)
	if not is_equal_approx(_glow_mat.emission_energy_multiplier, glow) or _glow_mat.emission != col:
		_glow_mat.emission_energy_multiplier = glow
		_glow_mat.emission = col
		_light.light_energy = glow * 0.8
		_light.light_color = col


func _build_visual() -> void:
	var r: float = minf(size.x, size.z) * 0.5
	var crust: StandardMaterial3D = Look.flat(Color(0.3, 0.26, 0.2), 0.95)
	var mineral: StandardMaterial3D = Look.flat(Color(0.78, 0.9, 0.35), 0.7, 0.0, 0.4)
	# a sinter cone round the mouth, crusted with acid-yellow minerals
	add_child(Look.cylinder(r * 1.25, 0.6, crust, Vector3(0, 0.05, 0), r * 0.85, 18))
	add_child(Look.cylinder(r * 0.95, 0.12, mineral, Vector3(0, 0.38, 0), r * 0.8, 18))
	for i: int in 8:
		var a: float = TAU * float(i) / 8.0 + 0.2
		var lump := Look.sphere(0.3 + 0.12 * float(i % 3), crust if i % 2 == 0 else mineral, Vector3(cos(a) * r * 1.15, 0.15, sin(a) * r * 1.15))
		lump.scale = Vector3(1.0, 0.6, 1.0)
		add_child(lump)
	_glow_mat = Look.flat(STEAM, 0.3, 0.0, 0.7).duplicate() as StandardMaterial3D
	var pool := Look.cylinder(r * 0.7, 0.06, _glow_mat, Vector3(0, 0.44, 0), -1.0, 18)
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pool)
	_light = OmniLight3D.new()
	_light.light_color = STEAM
	_light.omni_range = 9.0
	_light.light_energy = 0.5
	_light.shadow_enabled = false
	_light.position = Vector3(0, 1.2, 0)
	add_child(_light)
	var vis := AABB(Vector3(-5, -1, -5), Vector3(10, size.y + 8.0, 10))
	# steam: a fast dense column of teal vapour roaring up the updraft
	_steam = Fx.emitter({"amount": 70, "lifetime": size.y / 12.0 + 0.5, "shape": "sphere", "radius": r * 0.5,
		"dir": Vector3.UP, "spread": 7.0, "speed": Vector2(10.0, 14.0), "damping": Vector2(0.5, 1.5),
		"tex": Fx.Tex.SMOKE, "additive": true, "size": 1.3, "scale": Vector2(0.6, 1.4), "curve": "puff",
		"angle": Vector2(0, 360), "spin": Vector2(-90, 90), "turbulence": 1.0,
		"color": Color(0.5, 1.6, 1.5, 0.55), "fade": PackedFloat32Array([0.0, 0.8, 0.5, 0.0]), "aabb": vis})
	_steam.position = Vector3(0, 0.5, 0)
	add_child(_steam)
	# acid: bright lime droplets blasting up the column and raining back down around it
	_acid = Fx.emitter({"amount": 90, "lifetime": 1.2, "shape": "sphere", "radius": r * 0.45,
		"dir": Vector3.UP, "spread": 10.0, "speed": Vector2(12.0, 17.0), "gravity": Vector3(0, -16, 0),
		"tex": Fx.Tex.DOT, "size": 0.32, "scale": Vector2(0.6, 1.3), "color": Fx.hot(ACID, 2.4),
		"fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]), "aabb": vis})
	_acid.position = Vector3(0, 0.5, 0)
	add_child(_acid)
	# the moment it turns: a hissing crown of acid spray
	_spit = Fx.sparks({"amount": 40, "lifetime": 0.7, "shape": "ring", "ring_radius": r * 0.6, "ring_inner": r * 0.2,
		"dir": Vector3.UP, "spread": 35.0, "speed": Vector2(6.0, 12.0), "gravity": Vector3(0, -18, 0),
		"color": Fx.hot(ACID, 2.2), "size": Vector2(0.08, 0.6), "aabb": vis})
	_spit.position = Vector3(0, 0.5, 0)
	add_child(_spit)
	# warning: the crater bubbling over
	_bubbles = Fx.emitter({"amount": 24, "lifetime": 0.7, "shape": "ring", "ring_radius": r * 0.6, "ring_inner": r * 0.1,
		"dir": Vector3.UP, "spread": 30.0, "speed": Vector2(1.5, 3.5), "gravity": Vector3(0, -6, 0),
		"tex": Fx.Tex.BUBBLE, "size": 0.26, "scale": Vector2(0.5, 1.2), "color": Fx.hot(STEAM.lerp(ACID, 0.4), 1.6),
		"aabb": vis})
	_bubbles.position = Vector3(0, 0.45, 0)
	add_child(_bubbles)
	# always: a lazy thread of vapour so a quiet geyser still reads
	var idle: GPUParticles3D = Fx.emitter({"amount": 8, "lifetime": 3.0, "shape": "sphere", "radius": r * 0.4,
		"dir": Vector3.UP, "spread": 12.0, "speed": Vector2(0.8, 1.6), "tex": Fx.Tex.SMOKE, "additive": false,
		"size": 1.1, "curve": "puff", "angle": Vector2(0, 360), "color": Color(0.7, 0.95, 0.9, 0.25),
		"fade": PackedFloat32Array([0.0, 0.8, 0.0]), "aabb": vis, "preprocess": 3.0})
	idle.position = Vector3(0, 0.5, 0)
	add_child(idle)
