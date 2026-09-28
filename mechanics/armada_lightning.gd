class_name ArmadaLightning
extends Node3D
## Storm Armada: a lightning rod the storm keeps striking, on the course clock. Positioned at the
## floor point at the foot of the rod. For `warn` seconds before each strike the rod charges: the
## brass ring painted round it on the deck (the danger circle) glows brighter and brighter, blue
## sparks crawl up the rod and the glass orb on top flickers. Then the bolt comes down - a blinding
## flash, a burst of sparks and a shock ring across the circle - and anything inside the circle
## for `strike` seconds is fried. Pure function of the clock.
##   cycle: the bolt lands at u = 0 (u = fposmod(t / period + phase, 1)).

signal struck(pos: Vector3)

@export var period: float = 4.5
@export var phase: float = 0.0
@export var warn: float = 1.5
## How long the strike stays deadly.
@export var strike: float = 0.4
## Radius of the deadly circle, and how high above the floor it reaches.
@export var radius: float = 1.8
@export var reach_up: float = 3.2
@export var rod_height: float = 3.4
## Stand the rod on the circle's edge (offset from the centre, local) - e.g. out on a rail.
@export var rod_offset: Vector3 = Vector3.ZERO

const CHARGE := Color(0.55, 0.8, 1.0)

var _ring_mat: StandardMaterial3D
var _orb_mat: StandardMaterial3D
var _crawl: GPUParticles3D
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


## The circle is safe for the whole window [time + a, time + b].
func is_safe_for(time: float, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if is_deadly_at(time + s):
			return false
		s += 0.03
	return true


func snap_to_clock() -> void:
	_last = _index(Game.course_time)
	_apply(Game.course_time)


func _physics_process(_dt: float) -> void:
	if not is_deadly_at(Game.course_time):
		return
	var pl: Node3D = WorldAudio.local_player(self)
	if pl == null or not (pl is Player):
		return
	var d: Vector3 = pl.global_position - global_position
	if Vector2(d.x, d.z).length() < radius + 0.3 and d.y > -0.6 and d.y < reach_up:
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
	var ring: float = 0.35
	if since < strike:
		ring = 6.0
	elif since < strike + 0.6:
		ring = lerpf(6.0, 0.35, (since - strike) / 0.6)
	elif warning:
		ring = 0.5 + w * w * 4.5 * (0.7 + 0.3 * sin(t * 45.0))
	_ring_mat.emission_energy_multiplier = ring
	_orb_mat.emission_energy_multiplier = 1.0 + (w * 5.0 * absf(sin(t * 31.0)) if warning else 0.0) + (6.0 if since < strike else 0.0)
	if _crawl.emitting != warning:
		_crawl.emitting = warning
	if warning and not _was_warn:
		WorldAudio.at(self, "armada_rod_charge", global_position + Vector3(0, 1.5, 0), 0.8, 30.0)
	_was_warn = warning
	# the bolt: a stuttering double flicker over the deadly moment
	var on: bool = since < strike and fposmod(since * 21.0, 1.0) > 0.25
	if _bolt.visible != on:
		_bolt.visible = on
		_bolt.rotation.y = fposmod(float(k) * 2.39, TAU)
	var fl: float = 0.0
	if since < strike + 0.25:
		fl = (1.0 if on else 0.4) * clampf(1.0 - since / (strike + 0.25), 0.0, 1.0)
	_light.light_energy = fl * 9.0
	_light.visible = fl > 0.01


func _strike() -> void:
	_burst.restart()
	_burst.emitting = true
	_wave.restart()
	_wave.emitting = true
	var top: Vector3 = global_position + rod_offset + Vector3(0, rod_height, 0)
	WorldAudio.at(self, "armada_lightning_strike", top, 1.0, 70.0)
	struck.emit(top)


func _build() -> void:
	var brass: StandardMaterial3D = Look.flat(Color(0.86, 0.63, 0.3), 0.3, 0.9)
	var copper: StandardMaterial3D = Look.flat(Color(0.8, 0.42, 0.25), 0.35, 0.85)
	var iron: StandardMaterial3D = Look.flat(Color(0.18, 0.18, 0.2), 0.4, 0.8)
	var foot: Vector3 = rod_offset
	# the rod: an iron mast, a copper coil wound round it and a glass orb on a brass crown
	add_child(Look.cylinder(0.2, 0.3, iron, foot + Vector3(0, 0.15, 0), 0.14, 10))
	add_child(Look.cylinder(0.06, rod_height, brass, foot + Vector3(0, rod_height * 0.5, 0), 0.04, 8))
	for i: int in 7:
		var coil := Look.cylinder(0.13, 0.06, copper, foot + Vector3(0, 0.7 + float(i) * 0.26, 0), -1.0, 10)
		add_child(coil)
	_orb_mat = Look.flat(CHARGE, 0.2, 0.0, 1.0).duplicate() as StandardMaterial3D
	add_child(Look.sphere(0.2, _orb_mat, foot + Vector3(0, rod_height + 0.1, 0)))
	for i: int in 4:
		var a: float = TAU * float(i) / 4.0
		var prong := Look.box(Vector3(0.04, 0.4, 0.04), brass, foot + Vector3(cos(a) * 0.16, rod_height + 0.1, sin(a) * 0.16))
		prong.rotation = Vector3(sin(a) * 0.4, 0, -cos(a) * 0.4)
		add_child(prong)
	# the danger circle: a brass ring inlaid round the deck (a thin flat band, flush with the floor)
	_ring_mat = Look.flat(CHARGE, 0.3, 0.0, 0.35).duplicate() as StandardMaterial3D
	var tm := TorusMesh.new()
	tm.inner_radius = radius - 0.12
	tm.outer_radius = radius
	tm.rings = 48
	tm.ring_segments = 4
	var ring := Look.mesh_node(tm, _ring_mat, Vector3(0, 0.01, 0))
	ring.scale = Vector3(1.0, 0.15, 1.0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	# the bolt from the clouds to the orb
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(2.2, 2.6, 4.0, 1.0)
	mat.disable_fog = true
	mat.disable_receive_shadows = true
	_bolt = MeshInstance3D.new()
	_bolt.mesh = bolt_mesh(70.0, 12, 0.35, int(absf(global_position.x * 7.0 + global_position.z * 13.0)) + 5)
	_bolt.material_override = mat
	_bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bolt.extra_cull_margin = 80.0
	_bolt.position = foot + Vector3(0, rod_height + 70.0, 0)
	_bolt.visible = false
	add_child(_bolt)
	_light = OmniLight3D.new()
	_light.light_color = Color(0.7, 0.82, 1.0)
	_light.omni_range = 16.0
	_light.shadow_enabled = false
	_light.light_energy = 0.0
	_light.visible = false
	_light.position = foot + Vector3(0, rod_height + 1.0, 0)
	add_child(_light)
	var vis := AABB(Vector3(-radius - 6, -2, -radius - 6), Vector3(radius * 2 + 12, rod_height + 10, radius * 2 + 12))
	_crawl = Fx.emitter({"amount": 24, "lifetime": 0.35, "emitting": false, "shape": "box",
		"extents": Vector3(0.12, rod_height * 0.45, 0.12), "dir": Vector3.UP, "spread": 70.0, "speed": Vector2(0.5, 2.0),
		"facing": "velocity", "tex": Fx.Tex.SPARK, "size": Vector2(0.04, 0.3), "color": Color(1.4, 2.2, 3.2),
		"fade": PackedFloat32Array([1.0, 1.0, 0.0]), "aabb": vis})
	_crawl.position = foot + Vector3(0, rod_height * 0.5, 0)
	add_child(_crawl)
	_burst = Fx.sparks({"amount": 40, "shape": "sphere", "radius": 0.3, "dir": Vector3.UP, "spread": 90.0,
		"speed": Vector2(4.0, 11.0), "color": Color(1.8, 2.4, 3.4), "aabb": vis})
	_burst.position = foot + Vector3(0, rod_height, 0)
	add_child(_burst)
	_wave = Fx.shockwave(radius + 0.6, {"color": Color(1.2, 1.8, 3.0, 0.8), "lifetime": 0.45, "aabb": vis})
	_wave.position = Vector3(0, 0.08, 0)
	add_child(_wave)


## A jagged forked bolt hanging down from its origin, `length` long (two crossed ribbons).
static func bolt_mesh(length: float, steps: int, width: float, seed_value: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array[Vector3] = [Vector3.ZERO]
	var p := Vector3.ZERO
	for i: int in steps:
		var jag: float = length * 0.07 * (1.0 if i < steps - 1 else 0.0)
		p += Vector3(rng.randf_range(-1.0, 1.0) * jag, -length / float(steps), rng.randf_range(-1.0, 1.0) * jag)
		pts.append(p)
	# the last point lands exactly on the target below the origin
	pts[pts.size() - 1] = Vector3(0, -length, 0)
	_ribbon(st, pts, width)
	var f: Vector3 = pts[steps >> 1]
	var fork: Array[Vector3] = [f]
	for i: int in steps >> 2:
		f += Vector3(rng.randf_range(-0.2, 1.0) * length * 0.08, -length / float(steps) * 0.8, rng.randf_range(-1.0, 0.2) * length * 0.08)
		fork.append(f)
	_ribbon(st, fork, width * 0.6)
	return st.commit()


static func _ribbon(st: SurfaceTool, pts: Array[Vector3], w: float) -> void:
	for side: Vector3 in [Vector3(w, 0, 0), Vector3(0, 0, w)]:
		for i: int in pts.size() - 1:
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[i + 1]
			st.add_vertex(a - side)
			st.add_vertex(a + side)
			st.add_vertex(b + side)
			st.add_vertex(a - side)
			st.add_vertex(b + side)
			st.add_vertex(b - side)
