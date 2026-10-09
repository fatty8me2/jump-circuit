class_name FungalDrip
extends Area3D
## Mushroom Hollow: a DEWDROP. A big drop of morning dew gathers on the tip of a leaf overhead, swells
## (the tell: it grows, trembles and glints, a wet ring on the ground brightens and a "plink" ticks
## faster, for `swell` seconds), lets go, falls (`fall` s) and bursts on the ground in a splash. Anyone
## under it while it falls, or in the splash, is knocked back to the checkpoint.
## Rule (identical for every racer): with u = fposmod(t / period + phase, 1) * period,
##   u < swell                    gathering on the leaf (safe)
##   swell .. swell + fall        falling (deadly in the last 12 % of the fall, when it reaches head height)
##   swell + fall .. + splash     the splash on the ground (deadly)
##   after                        safe until the next one
## Positioned by the point on the ground under the drop; `drop_height` is the leaf tip above it.

@export var drop_height: float = 7.0
@export var radius: float = 1.1
@export var period: float = 5.0
@export var phase: float = 0.0
@export var swell: float = 1.3
@export var splash: float = 0.35

const FALL_GRAVITY: float = 26.0

var _drop: MeshInstance3D
var _drop_mat: StandardMaterial3D
var _ring_mat: StandardMaterial3D
var _leaf: Node3D
var _splash: GPUParticles3D
var _mist: GPUParticles3D
var _tick: int = -1
var _was_deadly: bool = false
var _splashed: bool = false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitorable = false
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = drop_height + 1.0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, (drop_height + 1.0) * 0.5, 0)
	add_child(cs)
	_build_visual()
	add_to_group("course_clock")
	_apply(Game.course_time)


func fall_time() -> float:
	return sqrt(2.0 * drop_height / FALL_GRAVITY)


func _cycle(time: float) -> float:
	return fposmod(time / period + phase, 1.0) * period


## Seconds until the drop lets go (0 once it has).
func time_to_fall(time: float) -> float:
	var c: float = _cycle(time)
	return maxf(swell - c, 0.0) if c < swell else period - c + swell


## True while standing under it is deadly.
func deadly_at(time: float) -> bool:
	var c: float = _cycle(time)
	var f: float = fall_time()
	return c >= swell + f * 0.88 and c < swell + f + splash


## True when it is safe to stand under it over the whole of [time + a, time + b].
func clear_over(time: float, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if deadly_at(time + s):
			return false
		s += 0.04
	return not deadly_at(time + b)


## Height of the middle of the drop above the ground at `time` (negative before it forms).
func drop_y_at(time: float) -> float:
	var c: float = _cycle(time)
	var f: float = fall_time()
	if c < swell:
		return drop_height
	if c < swell + f:
		var u: float = c - swell
		return maxf(drop_height - 0.5 * FALL_GRAVITY * u * u, 0.0)
	return -1.0


func snap_to_clock() -> void:
	_apply(Game.course_time)


func _physics_process(_dt: float) -> void:
	if not deadly_at(Game.course_time):
		return
	for body: Node3D in get_overlapping_bodies():
		if body is Player:
			var n: Node = self
			while n != null and not n.has_method("fail"):
				n = n.get_parent()
			if n != null:
				n.call_deferred("fail", "hazard")
			return


func _process(_dt: float) -> void:
	_apply(Game.course_time)


func _apply(t: float) -> void:
	var c: float = _cycle(t)
	var f: float = fall_time()
	var y: float = drop_y_at(t)
	if c < swell:
		var k: float = c / swell
		var g: float = 0.12 + 0.88 * k * k
		_drop.visible = true
		_drop.position = Vector3(0, drop_height - 0.45 * g * 0.5, 0)
		var wob: float = 1.0 + 0.06 * sin(t * (10.0 + 26.0 * k)) * k
		_drop.scale = Vector3(g * wob, g * 1.15, g / wob)
		_drop_mat.emission_energy_multiplier = 0.3 + 1.4 * k
		_ring_mat.emission_energy_multiplier = 0.2 + 3.0 * k * k
		_ring_mat.albedo_color.a = 0.3 + 0.6 * k
		var tk: int = int(floor(k * 4.0 + k * k * 8.0))
		if tk != _tick:
			_tick = tk
			# SOUND: fungal_drip_plink - a glassy tick of dew, faster as the drop swells (about 1.3 s ahead)
			WorldAudio.at(self, "fungal_drip_plink", global_position + Vector3(0, drop_height, 0), 0.5, 24.0)
		_splashed = false
	elif y >= 0.0:
		_drop.visible = true
		_drop.position = Vector3(0, y + 0.1, 0)
		var stretch: float = 1.0 + clampf((c - swell) / maxf(f, 0.01), 0.0, 1.0) * 0.5
		_drop.scale = Vector3(1.0 / sqrt(stretch), 1.15 * stretch, 1.0 / sqrt(stretch))
		_ring_mat.emission_energy_multiplier = 3.2
		_tick = -1
	else:
		_drop.visible = false
		_ring_mat.emission_energy_multiplier = 0.2
		_ring_mat.albedo_color.a = 0.3
		_tick = -1
		if not _splashed and c < swell + f + splash:
			_splashed = true
			_splash.restart()
			_splash.emitting = true
			_mist.restart()
			_mist.emitting = true
			# SOUND: fungal_drip_splash - a wet slap and a spray of droplets
			WorldAudio.at(self, "fungal_drip_splash", global_position, 0.8, 30.0)
	_leaf.rotation.x = -0.2 + 0.02 * sin(t * 2.0 + phase * 6.0)


func _build_visual() -> void:
	# the leaf the drop hangs from: a broad blade tilting down to a tip right above the drop
	_leaf = Node3D.new()
	_leaf.position = Vector3(0, drop_height + 0.35, 0)
	add_child(_leaf)
	var leaf_mat: StandardMaterial3D = Look.flat(Color(0.36, 0.62, 0.22), 0.7)
	var blade := Look.sphere(1.0, leaf_mat, Vector3(0, 0.55, 1.5))
	blade.scale = Vector3(1.1, 0.07, 2.2)
	_leaf.add_child(blade)
	var rib := Look.box(Vector3(0.07, 0.05, 3.2), Look.flat(Color(0.62, 0.8, 0.4), 0.7), Vector3(0, 0.62, 1.3))
	rib.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_leaf.add_child(rib)
	var tip := Look.cylinder(0.0, 0.5, leaf_mat, Vector3(0, 0.27, 0.0), 0.12, 8)
	_leaf.add_child(tip)
	# the drop: a glassy blue-white bead
	_drop_mat = StandardMaterial3D.new()
	_drop_mat.albedo_color = Color(0.7, 0.9, 1.0, 0.7)
	_drop_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_drop_mat.roughness = 0.05
	_drop_mat.metallic_specular = 1.0
	_drop_mat.rim_enabled = true
	_drop_mat.rim = 0.8
	_drop_mat.emission_enabled = true
	_drop_mat.emission = Color(0.55, 0.85, 1.0)
	_drop_mat.emission_energy_multiplier = 0.3
	_drop = Look.sphere(0.46, _drop_mat)
	_drop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_drop)
	# the wet ring on the ground that brightens before the drop lets go
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.albedo_color = Color(0.5, 0.85, 1.0, 0.3)
	_ring_mat.emission_enabled = true
	_ring_mat.emission = Color(0.45, 0.85, 1.0)
	_ring_mat.emission_energy_multiplier = 0.2
	var tm := TorusMesh.new()
	tm.inner_radius = radius * 0.88
	tm.outer_radius = radius
	tm.rings = 36
	tm.ring_segments = 6
	var ring := Look.mesh_node(tm, _ring_mat, Vector3(0, 0.05, 0))
	ring.scale = Vector3(1, 0.12, 1)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	var vis := AABB(Vector3(-4, -1, -4), Vector3(8, drop_height + 4.0, 8))
	_splash = Fx.burst({"amount": 26, "lifetime": 0.7, "shape": "ring", "ring_radius": radius * 0.5, "ring_inner": 0.0,
		"dir": Vector3.UP, "spread": 60.0, "speed": Vector2(2.0, 5.5), "gravity": Vector3(0, -12.0, 0),
		"size": 0.17, "tex": Fx.Tex.BUBBLE, "color": Color(0.8, 0.95, 1.3, 0.9), "aabb": vis})
	_splash.position = Vector3(0, 0.1, 0)
	add_child(_splash)
	_mist = Fx.shockwave(radius * 1.8, {"lifetime": 0.4, "color": Color(0.8, 0.95, 1.4, 0.8), "aabb": vis})
	_mist.position = Vector3(0, 0.08, 0)
	add_child(_mist)
