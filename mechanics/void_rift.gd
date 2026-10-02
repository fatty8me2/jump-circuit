class_name VoidRift
extends Area3D
## The Void: a RIFT - a box of thinned-out dream where gravity loosens its grip.
##  * LOW-GRAVITY rift (`lift` below gravity): while you are airborne inside it, `lift` m/s^2 of
##    gravity is cancelled, so a jump floats higher and further (lift 16: rise 14 / fall 26 instead
##    of 30 / 42). Standing, running and jumping off its floor work as normal.
##  * UP-DRAFT rift (`lift` above gravity): airborne inside it you are carried upward, never faster
##    than `max_rise` m/s.
## Both are clearly marked, never invisible: glowing corner brackets at all eight corners, a faint
## violet veil filling the volume, slow rings at its floor and ceiling and pale fragments drifting
## up through it (faster and denser in an up-draft). Always on - nothing to time, only the arc changes.

const VEIL := Color(0.55, 0.3, 0.95)
const PINK := Color(1.0, 0.36, 0.72)
const CYAN := Color(0.32, 0.9, 1.0)

@export var size: Vector3 = Vector3(6, 8, 12)
## Gravity cancelled (m/s^2) while airborne inside. Above 42 it is an up-draft.
@export var lift: float = 16.0
## Up-drafts never push you upward faster than this.
@export var max_rise: float = 9.0

var _hum: AudioStreamPlayer3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitorable = false
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	add_child(cs)
	_build_visual()
	# SOUND: void_rift_hum - a deep, breathing choral drone inside the rift (loop, close range)
	_hum = WorldAudio.loop("void_rift_hum", self, -10.0, maxf(maxf(size.x, size.y), size.z) * 0.5 + 10.0, 5.0)
	if _hum != null and is_updraft():
		_hum.pitch_scale = 1.15
	body_entered.connect(func(b: Node3D) -> void:
		if b is Player:
			# SOUND: void_rift_enter - a soft airy swell as gravity lets go
			WorldAudio.at(self, "void_rift_enter", b.global_position, 0.5, 20.0))


func is_updraft() -> bool:
	return lift > 42.0


func _physics_process(dt: float) -> void:
	for body: Node3D in get_overlapping_bodies():
		if body is Player:
			var p := body as Player
			if p.grounded or p.is_wall_running() or p.is_mantling():
				continue
			if is_updraft():
				if p.velocity.y < max_rise:
					p.velocity.y = minf(p.velocity.y + lift * dt, max_rise)
			else:
				p.velocity.y += lift * dt


# ---- look -------------------------------------------------------------------------------------

func _build_visual() -> void:
	var h: Vector3 = size * 0.5
	# the veil: a faint violet volume (both faces drawn, unshaded, no shadow)
	var veil := StandardMaterial3D.new()
	veil.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	veil.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	veil.cull_mode = BaseMaterial3D.CULL_DISABLED
	veil.albedo_color = Color(VEIL.r, VEIL.g, VEIL.b, 0.05 if not is_updraft() else 0.07)
	veil.disable_receive_shadows = true
	var v := Look.box(size, veil)
	v.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(v)
	# corner brackets: three short glowing arms at every corner (pink below, cyan above)
	var arm: float = clampf(minf(minf(size.x, size.y), size.z) * 0.22, 0.5, 1.6)
	for sy: float in [-1.0, 1.0]:
		var mat: StandardMaterial3D = Look.flat(PINK if sy < 0.0 else CYAN, 0.3, 0.0, 3.0)
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				var c := Vector3(sx * h.x, sy * h.y, sz * h.z)
				_bar(Vector3(arm, 0.07, 0.07), c - Vector3(sx * arm * 0.5, 0, 0), mat)
				_bar(Vector3(0.07, arm, 0.07), c - Vector3(0, sy * arm * 0.5, 0), mat)
				_bar(Vector3(0.07, 0.07, arm), c - Vector3(0, 0, sz * arm * 0.5), mat)
	# dashed lines along the four vertical edges, so the side boundary reads from any angle
	var dash: StandardMaterial3D = Look.flat(Color(0.85, 0.75, 1.0), 0.3, 0.0, 1.6)
	var n: int = maxi(int(size.y / 1.2), 2)
	for sx2: float in [-1.0, 1.0]:
		for sz2: float in [-1.0, 1.0]:
			for i: int in n:
				var y: float = -h.y + (float(i) + 0.5) * size.y / float(n)
				if absf(y) > h.y - arm - 0.2:
					continue
				_bar(Vector3(0.05, 0.35, 0.05), Vector3(sx2 * h.x, y, sz2 * h.z), dash)
	# slow rings turning at its floor and ceiling
	for sy2: float in [-1.0, 1.0]:
		var tm := TorusMesh.new()
		var r: float = minf(size.x, size.z) * 0.42
		tm.inner_radius = r * 0.96
		tm.outer_radius = r
		tm.rings = 48
		tm.ring_segments = 6
		var ring := Look.mesh_node(tm, Look.flat(PINK if sy2 < 0.0 else CYAN, 0.3, 0.0, 1.8), Vector3(0, sy2 * (h.y - 0.05), 0))
		ring.scale = Vector3(size.x / minf(size.x, size.z), 1.0, size.z / minf(size.x, size.z))
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.set_script(preload("res://visual/spin.gd"))
		ring.set("period", 14.0 * sy2)
		add_child(ring)
	# fragments and motes drifting up through it
	var up: float = 2.6 if is_updraft() else 0.9
	var vol: float = size.x * size.y * size.z
	var life: float = clampf(size.y / up, 2.0, 9.0)
	var vis := AABB(-h - Vector3(2, 2, 2), size + Vector3(4, 4, 4))
	add_child(Fx.emitter({"amount": clampi(int(vol * 0.12), 14, 70), "lifetime": life, "preprocess": life,
		"local": true, "shape": "box", "extents": Vector3(h.x, 0.1, h.z) * 0.9, "offset": Vector3(0, -h.y, 0),
		"dir": Vector3.UP, "spread": 8.0, "speed": Vector2(up * 0.7, up * 1.2), "facing": "mesh",
		"mesh": Fx.chunk_mesh(0.16), "color": Color(0.92, 0.9, 1.0), "scale": Vector2(0.4, 1.1),
		"angle": Vector2(0, 360), "spin": Vector2(-60, 60), "curve": "pop", "aabb": vis}))
	add_child(Fx.emitter({"amount": clampi(int(vol * 0.1), 12, 60), "lifetime": life * 0.8, "preprocess": life,
		"local": true, "shape": "box", "extents": h * Vector3(0.95, 0.8, 0.95),
		"dir": Vector3.UP, "spread": 20.0, "speed": Vector2(up * 0.5, up * 1.3), "tex": Fx.Tex.DOT,
		"size": 0.12, "pick": PackedColorArray([Fx.hot(PINK, 1.8), Fx.hot(CYAN, 1.8), Color(1.8, 1.7, 2.0)]),
		"turbulence": 0.8, "turbulence_scale": 3.0, "curve": "pop", "aabb": vis}))


func _bar(sz: Vector3, at: Vector3, mat: Material) -> void:
	var b := Look.box(sz, mat, at)
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(b)
