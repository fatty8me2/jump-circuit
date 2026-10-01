class_name FrontierDynamite
extends Node3D
## Wild West Heist: a DYNAMITE bundle on a lit fuse. On a fixed rhythm (Game.course_time) a spark
## runs down the fuse (sputtering, hissing, throwing sparks), the bundle flashes red for its last
## moments, then BOOM: a fireball fills `radius` around the bundle for `blast_time` and sends you back
## to the checkpoint. Then the smoke clears, a fresh bundle is planted with a puff of dust and the fuse
## lies there unlit until the next cycle lights it. The node sits on the floor at the bundle.
##   cycle (s into the period): 0 spark lit .. burn -> BOOM .. +blast_time -> smoke .. +regrow -> idle
## Readable: the spark is visible crawling for the whole `burn` (2 s by default), and the bundle
## blinks for the last `warn` seconds, so a blast never comes without a long tell.

## Seconds a full cycle lasts, and where in it the clock starts (0..1).
@export var period: float = 3.6
@export var phase: float = 0.0
## Seconds the spark takes from the end of the fuse to the bundle.
@export var burn: float = 2.0
## Seconds the blast kills.
@export var blast_time: float = 0.3
## Kill radius round the bundle (the sphere is centred `radius * 0.35` above the floor).
@export var radius: float = 2.0
## Seconds after the blast before a new bundle appears.
@export var regrow: float = 0.7
## The fuse, in this node's space, from where the spark starts to the bundle (floor height).
@export var fuse: PackedVector3Array = PackedVector3Array([Vector3(2.4, 0.03, 0.0), Vector3(0.0, 0.03, 0.0)])
## Seconds before the blast that the bundle blinks red.
@export var warn: float = 0.8

var _area: Area3D
var _bundle: Node3D
var _cap_mat: StandardMaterial3D
var _fuse_segs: Array[MeshInstance3D] = []
var _seg_len: PackedFloat32Array = PackedFloat32Array()
var _fuse_len: float = 0.0
var _spark: Node3D
var _spark_fx: GPUParticles3D
var _fireball: GPUParticles3D
var _smoke: GPUParticles3D
var _debris: GPUParticles3D
var _sparks: GPUParticles3D
var _ring: GPUParticles3D
var _puff: GPUParticles3D
var _lamp: OmniLight3D
var _hiss: AudioStreamPlayer3D
var _was_lit: bool = false
var _was_blast: bool = false
var _was_present: bool = true


func _ready() -> void:
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 2
	_area.monitorable = false
	var s := SphereShape3D.new()
	s.radius = radius
	var cs := CollisionShape3D.new()
	cs.shape = s
	cs.position = Vector3(0, radius * 0.35, 0)
	_area.add_child(cs)
	add_child(_area)
	_build()
	_hiss = WorldAudio.loop("frontier_fuse_hiss", self, -10.0, 22.0, 4.0, false)
	add_to_group("course_clock")
	snap_to_clock()


func snap_to_clock() -> void:
	var t: float = Game.course_time
	_was_lit = is_lit_at(t)
	_was_blast = is_blasting_at(t)
	_was_present = is_present_at(t)
	_apply(t)


# ---- the rhythm (pure functions of the course clock) -------------------------------------------

func _s(time: float) -> float:
	return fposmod(time / period + phase, 1.0) * period


## The spark is running down the fuse.
func is_lit_at(time: float) -> bool:
	return _s(time) < burn


## The fireball is out: deadly.
func is_blasting_at(time: float) -> bool:
	var s: float = _s(time)
	return s >= burn and s < burn + blast_time


## A bundle sits there (lit or not).
func is_present_at(time: float) -> bool:
	var s: float = _s(time)
	return s < burn or s >= burn + regrow


## No blast at any moment of [time + a, time + b].
func is_clear_for(time: float, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if is_blasting_at(time + s):
			return false
		s += 0.03
	return not is_blasting_at(time + b)


## Seconds until the next blast begins (0 while one is going off).
func time_until_blast(time: float) -> float:
	var s: float = _s(time)
	if s >= burn and s < burn + blast_time:
		return 0.0
	return burn - s if s < burn else period - s + burn


## 0..1 how far the spark has burned (1 = at the bundle; 0 when unlit).
func burn_at(time: float) -> float:
	var s: float = _s(time)
	return clampf(s / burn, 0.0, 1.0) if s < burn else 0.0


# ---- gameplay ------------------------------------------------------------------------------------

func _physics_process(_dt: float) -> void:
	if not is_blasting_at(Game.course_time):
		return
	for body: Node3D in _area.get_overlapping_bodies():
		if body is Player:
			var n: Node = self
			while n != null and not n.has_method("fail"):
				n = n.get_parent()
			if n != null:
				n.call_deferred("fail", "hazard")
			return


# ---- look and sound (side effects only) -----------------------------------------------------------

func _process(_dt: float) -> void:
	_apply(Game.course_time)


func _apply(t: float) -> void:
	var lit: bool = is_lit_at(t)
	var blast: bool = is_blasting_at(t)
	var present: bool = is_present_at(t)
	_bundle.visible = present
	# the fuse burns away behind the spark
	var k: float = burn_at(t) if lit else (0.0 if present else 1.0)
	var burned: float = k * _fuse_len
	var acc: float = 0.0
	var spark_at: Vector3 = fuse[fuse.size() - 1]
	for i: int in _fuse_segs.size():
		var seg: MeshInstance3D = _fuse_segs[i]
		var l: float = _seg_len[i]
		var a: Vector3 = fuse[i]
		var b: Vector3 = fuse[i + 1]
		var left: float = clampf((acc + l - burned) / maxf(l, 0.001), 0.0, 1.0)
		seg.visible = left > 0.01
		if seg.visible:
			# the unburned part of this segment: from the spark (or its start) to its end
			var from: Vector3 = b.lerp(a, left)
			seg.position = (from + b) * 0.5
			seg.scale = Vector3(1.0, left, 1.0)
		if burned >= acc and burned <= acc + l:
			spark_at = a.lerp(b, (burned - acc) / maxf(l, 0.001))
		acc += l
	_spark.visible = lit
	_spark.position = spark_at + Vector3(0, 0.05, 0)
	if _spark_fx.emitting != lit:
		_spark_fx.emitting = lit
	# the last moments: the caps blink red, faster and faster
	var left_s: float = burn - _s(t)
	var blink: bool = lit and left_s < warn and fmod(left_s, 0.18 if left_s > warn * 0.5 else 0.1) < 0.06
	_cap_mat.emission_energy_multiplier = 3.2 if blink else 0.25
	if lit != _was_lit:
		_was_lit = lit
		WorldAudio.set_active(_hiss, lit)
		if lit:
			# SOUND: the fuse catching
			WorldAudio.at(self, "frontier_fuse_light", global_position + fuse[0], 0.6, 25.0)
	if blast and not _was_blast:
		_boom()
	_was_blast = blast
	if present and not _was_present:
		_puff.restart()
	_was_present = present


func _boom() -> void:
	for p: GPUParticles3D in [_fireball, _smoke, _debris, _sparks, _ring]:
		p.restart()
	Fx.pulse(_lamp, 9.0, 0.0, 0.5)
	# SOUND: the dynamite going off
	WorldAudio.at(self, "frontier_dynamite_boom", global_position, 1.0, 70.0, 0.08)


func _build() -> void:
	var vis := AABB(Vector3(-radius * 3.0, -2.0, -radius * 3.0), Vector3(radius * 6.0, radius * 4.0 + 6.0, radius * 6.0))
	# the bundle: three red sticks bound with twine, a brass cap glowing at the top of each
	_bundle = Node3D.new()
	add_child(_bundle)
	var red: StandardMaterial3D = Look.flat(Color(0.78, 0.12, 0.08), 0.6)
	var twine: StandardMaterial3D = Look.flat(Color(0.75, 0.62, 0.38), 0.9)
	_cap_mat = Look.flat(Color(1.0, 0.25, 0.1), 0.4, 0.0, 0.25).duplicate() as StandardMaterial3D
	for i: int in 3:
		var a: float = TAU * float(i) / 3.0
		var off := Vector3(cos(a) * 0.12, 0.0, sin(a) * 0.12)
		var stick := Look.cylinder(0.1, 0.62, red, off + Vector3(0, 0.31, 0), -1.0, 10)
		_bundle.add_child(stick)
		_bundle.add_child(Look.cylinder(0.105, 0.05, _cap_mat, off + Vector3(0, 0.63, 0), -1.0, 10))
	for y: float in [0.16, 0.46]:
		_bundle.add_child(Look.cylinder(0.25, 0.06, twine, Vector3(0, y, 0), -1.0, 14))
	# a little warning plank stencilled with a red band, under the bundle
	_bundle.add_child(Look.box(Vector3(0.9, 0.04, 0.9), Look.flat(Color(0.45, 0.32, 0.2), 0.9), Vector3(0, 0.02, 0)))
	_bundle.add_child(Look.box(Vector3(0.92, 0.045, 0.16), Look.flat(Color(0.9, 0.2, 0.1), 0.6, 0.0, 0.4), Vector3(0, 0.025, 0)))
	# the fuse: a dark cord in segments, each scaled down as the spark eats it
	var cord: StandardMaterial3D = Look.flat(Color(0.12, 0.1, 0.08), 0.9)
	_fuse_len = 0.0
	for i: int in fuse.size() - 1:
		var a2: Vector3 = fuse[i]
		var b2: Vector3 = fuse[i + 1]
		var l: float = a2.distance_to(b2)
		_seg_len.append(l)
		_fuse_len += l
		var seg := Look.cylinder(0.035, l, cord, (a2 + b2) * 0.5, -1.0, 6)
		var dir: Vector3 = (b2 - a2) / maxf(l, 0.001)
		var side: Vector3 = dir.cross(Vector3(0.123, 0.4, 0.9))
		if side.length() < 0.001:
			side = dir.cross(Vector3.RIGHT)
		side = side.normalized()
		seg.basis = Basis(side, dir, side.cross(dir))
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(seg)
		_fuse_segs.append(seg)
	# the spark: a hot glint throwing a spray of sparks as it crawls
	_spark = Node3D.new()
	_spark.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_spark)
	_spark.add_child(Fx.sprite(Color(3.2, 2.0, 0.8), 0.7))
	_spark_fx = Fx.sparks({"amount": 26, "lifetime": 0.4, "one_shot": false, "emitting": false, "explosiveness": 0.0,
		"spread": 70.0, "speed": Vector2(1.5, 4.0), "gravity": Vector3(0, -9.0, 0), "size": Vector2(0.05, 0.3),
		"color": Color(3.2, 1.9, 0.6), "aabb": vis})
	_spark.add_child(_spark_fx)
	# the blast: fireball, smoke, splinters, sparks, a shock ring along the floor, a flash
	_fireball = Fx.burst({"amount": 46, "lifetime": 0.55, "shape": "sphere", "radius": radius * 0.35,
		"spread": 180.0, "speed": Vector2(radius * 1.5, radius * 3.5), "damping": Vector2(6.0, 9.0), "size": 1.3,
		"scale": Vector2(0.7, 1.4), "curve": "puff", "tex": Fx.Tex.SMOKE,
		"colors": PackedColorArray([Color(3.4, 2.4, 1.0, 1.0), Color(3.0, 1.1, 0.25, 0.9), Color(0.5, 0.2, 0.1, 0.0)]),
		"aabb": vis})
	_fireball.position = Vector3(0, radius * 0.35, 0)
	add_child(_fireball)
	_smoke = Fx.smoke({"amount": 26, "lifetime": 2.0, "shape": "sphere", "radius": radius * 0.4, "speed": Vector2(1.0, 3.0),
		"dir": Vector3.UP, "spread": 70.0, "size": 2.4, "gravity": Vector3(0, 0.6, 2.0),
		"color": Color(0.32, 0.28, 0.26, 0.75), "aabb": vis})
	_smoke.position = Vector3(0, radius * 0.4, 0)
	add_child(_smoke)
	_debris = Fx.debris({"amount": 20, "chunk": 0.16, "speed": Vector2(5.0, 10.0), "spread": 80.0,
		"color": Color(0.55, 0.38, 0.22), "aabb": vis})
	_debris.position = Vector3(0, 0.4, 0)
	add_child(_debris)
	_sparks = Fx.sparks({"amount": 40, "lifetime": 0.7, "spread": 180.0, "speed": Vector2(6.0, 13.0),
		"color": Color(3.4, 1.8, 0.5), "size": Vector2(0.08, 0.6), "aabb": vis})
	_sparks.position = Vector3(0, 0.5, 0)
	add_child(_sparks)
	_ring = Fx.shockwave(radius * 1.4, {"lifetime": 0.35, "color": Color(2.6, 1.5, 0.7), "aabb": vis})
	_ring.position = Vector3(0, 0.08, 0)
	add_child(_ring)
	_puff = Fx.smoke({"amount": 8, "lifetime": 0.7, "shape": "sphere", "radius": 0.3, "speed": Vector2(0.5, 1.4),
		"dir": Vector3.UP, "size": 0.7, "color": Color(0.8, 0.66, 0.5, 0.6), "aabb": vis})
	_puff.position = Vector3(0, 0.3, 0)
	add_child(_puff)
	_lamp = OmniLight3D.new()
	_lamp.light_color = Color(1.0, 0.6, 0.25)
	_lamp.omni_range = radius * 4.0
	_lamp.light_energy = 0.0
	_lamp.visible = false
	_lamp.position = Vector3(0, 1.0, 0)
	add_child(_lamp)
	# the danger ring painted round the bundle: how far the blast reaches
	var tm := TorusMesh.new()
	tm.inner_radius = radius * 0.94
	tm.outer_radius = radius
	tm.rings = 40
	tm.ring_segments = 4
	var ring_mesh := Look.mesh_node(tm, Look.flat(Color(0.95, 0.3, 0.12), 0.6, 0.0, 0.5), Vector3(0, 0.02, 0))
	ring_mesh.scale = Vector3(1, 0.05, 1)
	ring_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring_mesh)
