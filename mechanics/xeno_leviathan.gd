class_name XenoLeviathan
extends MovingPlatform
## Xeno Wilds set piece: a sky leviathan - a vast manta-whale of glowing chitin plates, trailing
## tendrils and slow wing beats - gliding a closed loop on the course clock. On the first part of
## its loop it flies dead straight across the chasm (`cross`, from its build position) at a steady
## speed: its armoured back is a moving platform you jump onto from the boarding ledge, ride, and
## jump off at the far side. Then it banks, climbs and sweeps back high overhead and round to the
## start (the return swings `loop_side` m off to the side and `loop_height` m up, so it never
## crosses the course). Pure function of Game.course_time, like every mover: a pod of them sharing
## one loop at different phases keeps the ferry frequent.
## Positioned (like kit.mover) at the CENTRE of the back's collision box at the start of the crossing.

@export var cross: Vector3 = Vector3(0, 0, -60)
## Fraction of the period spent on the straight crossing.
@export var cross_fraction: float = 0.5
@export var loop_height: float = 30.0
## Sideways swing of the return loop (+ = to the right of the crossing heading).
@export var loop_side: float = 40.0
@export var tint: Color = Color(0.35, 1.0, 0.9)
@export var visual_scale: float = 1.0

const SWAY: Script = preload("res://visual/reef_sway.gd")

var _body: Node3D
var _trail: Array[GPUParticles3D] = []
var _called: int = -1


func _ready() -> void:
	sync_to_physics = false
	collision_layer = 1
	collision_mask = 0
	_origin = position
	var box := BoxShape3D.new()
	box.size = size
	var cs := CollisionShape3D.new()
	cs.shape = box
	add_child(cs)
	_body = creature(visual_scale, tint, size)
	_body.position = Vector3(0, size.y * 0.5, 0)
	add_child(_body)
	# a warm light on its back so a rider stays lit over the dark chasm
	var l := OmniLight3D.new()
	l.light_color = tint.lerp(Color.WHITE, 0.5)
	l.light_energy = 1.2
	l.omni_range = 9.0
	l.position = Vector3(0, 2.5, 0)
	l.shadow_enabled = false
	add_child(l)
	_build_fx()
	_pose(Game.course_time)
	reset_physics_interpolation()
	add_to_group("course_clock")


func _u(time: float) -> float:
	return fposmod(time / maxf(period, 0.01) + phase, 1.0)


func offset_at(time: float) -> Vector3:
	var u: float = _u(time)
	var c: float = clampf(cross_fraction, 0.1, 0.9)
	if u < c:
		return cross * (u / c)
	var s: float = (u - c) / (1.0 - c)
	# Hermite from the far end back to the start, leaving and arriving at the crossing velocity,
	# lifted and swung aside by sin^2 bumps (zero slope at both ends: no jerk at the joins)
	var m: Vector3 = cross * ((1.0 - c) / c)
	var s2: float = s * s
	var s3: float = s2 * s
	var p: Vector3 = cross * (2.0 * s3 - 3.0 * s2 + 1.0) + m * (s3 - 2.0 * s2 + s) + m * (s3 - s2)
	var bump: float = sin(PI * s)
	bump *= bump
	var side: Vector3 = Vector3(-cross.z, 0.0, cross.x).normalized()
	return p + side * loop_side * bump + Vector3.UP * loop_height * bump


## Seconds until the crossing leg next begins (0 at its start).
func time_until_crossing(time: float) -> float:
	return (1.0 - _u(time)) * period if _u(time) > 0.0 else 0.0


## True while it is on the straight crossing leg.
func is_crossing_at(time: float) -> bool:
	return _u(time) < clampf(cross_fraction, 0.1, 0.9)


func _heading(time: float) -> Basis:
	var d: Vector3 = offset_at(time + 0.05) - offset_at(time - 0.05)
	if is_crossing_at(time - 0.05) and is_crossing_at(time + 0.05):
		d = cross
	if d.length() < 0.001:
		d = cross
	var fwd: Vector3 = d.normalized()
	var flat := Vector3(fwd.x, 0.0, fwd.z)
	if flat.length() < 0.01:
		flat = Vector3(cross.x, 0.0, cross.z)
	var yaw: float = atan2(-flat.x, -flat.z)
	var pitch: float = clampf(asin(clampf(fwd.y, -1.0, 1.0)), -0.5, 0.5)
	return Basis.from_euler(Vector3(pitch, yaw, 0.0))


func _bank(time: float) -> float:
	if is_crossing_at(time - 0.3) and is_crossing_at(time + 0.3):
		return 0.0
	var a: Vector3 = offset_at(time + 0.3) - 2.0 * offset_at(time) + offset_at(time - 0.3)
	var b: Basis = _heading(time)
	return clampf(-a.dot(b.x) * 0.25, -0.6, 0.6)


func snap_to_clock() -> void:
	_pose(Game.course_time)
	reset_physics_interpolation()


func _physics_process(_dt: float) -> void:
	_pose(Game.course_time)


func _pose(t: float) -> void:
	transform = Transform3D(_heading(t), _origin + offset_at(t))
	if _body != null:
		_body.rotation.z = _bank(t)


func _process(_dt: float) -> void:
	var t: float = Game.course_time
	var cycle: int = int(floor(t / maxf(period, 0.01) + phase))
	if cycle != _called and _u(t) < 0.05:
		_called = cycle
		WorldAudio.at(self, "leviathan_call", global_position, 1.0, 160.0, 0.08)


func _build_fx() -> void:
	var k: float = visual_scale
	var vis := AABB(Vector3(-30, -30, -30) * k, Vector3(60, 60, 60) * k)
	# glowing motes streaming off both wing tips (world space: a wake hanging behind it)
	for side: float in [-1.0, 1.0]:
		var tr: GPUParticles3D = Fx.emitter({"amount": 40, "lifetime": 2.4, "fixed_fps": 0, "shape": "sphere", "radius": 0.4 * k,
			"speed": Vector2(0.0, 0.4), "spread": 180.0, "gravity": Vector3(0, -0.4, 0), "tex": Fx.Tex.DOT,
			"size": 0.35 * k, "curve": "shrink", "color": Fx.hot(tint, 2.0), "aabb": AABB(Vector3(-400, -200, -400), Vector3(800, 400, 800))})
		tr.position = Vector3(side * 11.0 * k, size.y * 0.5 - 2.4 * k, 1.2 * k)
		add_child(tr)
		_trail.append(tr)
	# spores sifting down from its belly
	var spores: GPUParticles3D = Fx.emitter({"amount": 26, "lifetime": 3.0, "shape": "box", "extents": Vector3(2.5, 0.2, 6.0) * k,
		"dir": Vector3.DOWN, "spread": 20.0, "speed": Vector2(0.4, 1.2), "gravity": Vector3(0, -0.6, 0),
		"tex": Fx.Tex.DOT, "size": 0.2 * k, "curve": "pop", "turbulence": 0.8,
		"color": Fx.hot(tint.lerp(Color(1.0, 0.5, 0.9), 0.5), 1.8), "aabb": AABB(Vector3(-200, -200, -200), Vector3(400, 400, 400))})
	spores.position = Vector3(0, size.y * 0.5 - 4.0 * k, 0)
	add_child(spores)
	# a shimmer of glints over the back plates
	var glint: GPUParticles3D = Fx.emitter({"amount": 12, "lifetime": 1.6, "local": true, "shape": "box",
		"extents": Vector3(size.x * 0.45, 0.1, size.z * 0.45), "dir": Vector3.UP, "spread": 20.0,
		"speed": Vector2(0.2, 0.6), "tex": Fx.Tex.STAR, "size": 0.25, "curve": "pop", "color": Fx.hot(tint, 1.8),
		"aabb": vis, "preprocess": 1.6})
	glint.position = Vector3(0, size.y * 0.5 + 0.1, 0)
	add_child(glint)


## The creature's look, built round the rideable back (`back` = the collision box size): the back's
## top sits at the returned node's origin. Also used for the distant, purely decorative leviathans.
static func creature(k: float, tint: Color, back: Vector3 = Vector3(3.6, 0.5, 9.0)) -> Node3D:
	var root := Node3D.new()
	var skin: StandardMaterial3D = Look.flat(Color(0.14, 0.12, 0.24), 0.55)
	var belly: StandardMaterial3D = Look.flat(Color(0.38, 0.3, 0.52), 0.6)
	var plate: StandardMaterial3D = Look.flat(Color(0.2, 0.26, 0.36), 0.35, 0.3)
	var glow: StandardMaterial3D = Look.flat(tint, 0.3, 0.0, 2.6)
	var glow2: StandardMaterial3D = Look.flat(Color(1.0, 0.45, 0.85), 0.3, 0.0, 2.4)
	var membrane: StandardMaterial3D = Look.flat(Color(tint.r * 0.3, tint.g * 0.35, tint.b * 0.5, 0.78), 0.4, 0.0, 0.5)
	membrane = membrane.duplicate() as StandardMaterial3D
	membrane.cull_mode = BaseMaterial3D.CULL_DISABLED
	# the back: armour plates with glowing seams, flush with the collision top
	var rows: int = int(back.z / 1.5)
	for i: int in rows:
		var z: float = -back.z * 0.5 + 0.75 + float(i) * back.z / float(rows)
		root.add_child(Look.box(Vector3(back.x - 0.15, back.y, back.z / float(rows) - 0.12), plate, Vector3(0, -back.y * 0.5, z)))
		root.add_child(Look.box(Vector3(back.x - 0.4, 0.04, 0.08), glow, Vector3(0, -0.01, z + back.z / float(rows) * 0.5 - 0.03)))
	for side: float in [-1.0, 1.0]:
		root.add_child(Look.box(Vector3(0.1, 0.05, back.z - 0.4), glow, Vector3(side * (back.x * 0.5 - 0.1), -0.01, 0)))
	# body: a broad ellipsoid under the back, paler belly below
	var body := Look.sphere(1.0, skin, Vector3(0, -2.2 * k, 0.3 * k))
	body.scale = Vector3(3.4, 2.1, 8.0) * k
	root.add_child(body)
	var bl := Look.sphere(1.0, belly, Vector3(0, -2.9 * k, 0.3 * k))
	bl.scale = Vector3(2.9, 1.5, 7.2) * k
	root.add_child(bl)
	# head: a blunt brow, four glowing eyes, and a lure dangling on a stalk ahead of it
	var head := Look.sphere(1.0, skin, Vector3(0, -1.9 * k, -8.2 * k))
	head.scale = Vector3(2.7, 1.7, 2.8) * k
	root.add_child(head)
	for side: float in [-1.0, 1.0]:
		for j: int in 2:
			root.add_child(Look.sphere(0.28 * k, glow2, Vector3(side * (1.9 - 0.35 * float(j)) * k, (-1.2 - 0.55 * float(j)) * k, (-9.6 + 0.4 * float(j)) * k)))
	var stalk := Look.cylinder(0.08 * k, 3.4 * k, skin, Vector3(0, -0.4 * k, -10.9 * k), 0.05 * k, 6)
	stalk.rotation.x = -1.0
	root.add_child(stalk)
	root.add_child(Look.sphere(0.4 * k, glow, Vector3(0, -1.2 * k, -12.4 * k)))
	# flank lights: two rows of glowing spots down each side
	for side: float in [-1.0, 1.0]:
		for i: int in 9:
			var z2: float = (-6.5 + float(i) * 1.6) * k
			root.add_child(Look.sphere((0.2 - 0.012 * float(i)) * k, glow if i % 2 == 0 else glow2, Vector3(side * (3.1 - 0.1 * absf(float(i) - 4.0)) * k, -2.0 * k, z2)))
	# wings: two vast translucent membranes on flapping roots, veined with light
	for side: float in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(side * 2.8 * k, -2.4 * k, 0.0)
		pivot.set_script(SWAY)
		pivot.set("amount", 0.16)
		pivot.set("speed", 0.9)
		pivot.set("offset", 0.0 if side > 0.0 else PI)
		var wing := Look.sphere(1.0, membrane, Vector3(side * 5.2 * k, 0, 0.6 * k))
		wing.scale = Vector3(5.6, 0.18, 4.2) * k
		wing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		pivot.add_child(wing)
		for v: int in 5:
			var ang: float = -0.7 + 0.35 * float(v)
			var vein := Look.box(Vector3(9.0 * k, 0.06 * k, 0.1 * k), glow, Vector3(side * 4.6 * k, 0.12 * k, (0.6 + sin(ang) * 3.2) * k))
			vein.rotation.y = -side * ang * 0.5
			vein.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			pivot.add_child(vein)
		pivot.add_child(Look.sphere(0.3 * k, glow2, Vector3(side * 10.6 * k, 0, 1.2 * k)))
		root.add_child(pivot)
	# tail: a tapering chain of segments, swaying, ending in a glowing fluke
	var tail := Node3D.new()
	tail.position = Vector3(0, -2.2 * k, 7.5 * k)
	tail.set_script(SWAY)
	tail.set("amount", 0.12)
	tail.set("speed", 0.7)
	for i: int in 7:
		var f: float = float(i) / 6.0
		var seg := Look.sphere((1.2 - 0.95 * f) * k, skin, Vector3(0, -0.2 * f * k, (1.4 + float(i) * 1.7) * k))
		seg.scale = Vector3(1.0, 0.75, 1.3)
		tail.add_child(seg)
		if i % 2 == 0:
			tail.add_child(Look.sphere(0.14 * k, glow, Vector3(0, (0.7 - 0.5 * f) * k, (1.4 + float(i) * 1.7) * k)))
	var fluke := Look.sphere(1.0, membrane, Vector3(0, -0.3 * k, 13.8 * k))
	fluke.scale = Vector3(3.4, 0.15, 1.4) * k
	tail.add_child(fluke)
	root.add_child(tail)
	# tendrils hanging from the belly, drifting in its wake
	for i: int in 8:
		var a: float = TAU * float(i) / 8.0
		var holder := Node3D.new()
		holder.position = Vector3(cos(a) * 1.8 * k, -4.0 * k, (sin(a) * 4.0 + 1.0) * k)
		holder.set_script(SWAY)
		holder.set("amount", 0.22)
		holder.set("speed", 0.8 + 0.1 * float(i % 3))
		holder.set("offset", float(i) * 0.9)
		var tl: float = (6.0 + 5.0 * fposmod(float(i) * 0.618, 1.0)) * k
		var ten := Look.cylinder(0.09 * k, tl, belly, Vector3(0, -tl * 0.5, 0), 0.03 * k, 5)
		ten.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(ten)
		holder.add_child(Look.sphere(0.16 * k, glow if i % 2 == 0 else glow2, Vector3(0, -tl, 0)))
		root.add_child(holder)
	return root
