class_name PartyTornado
extends Node3D
## The Tornado hazard: a whirling funnel that wanders up the course along a path of points
## (the owner's spot, then the next checkpoints), weaving side to side. Every screen spawns it
## from the owner's "spawn" event and moves it the same way. Detection is victim-side: each
## client checks only its OWN Player against other people's tornadoes and flings itself; the
## owner's copy flings the practice dummies.

const SPEED: float = 7.0
const LIFE: float = 9.0
const RADIUS: float = 1.9
const HEIGHT: float = 4.5
const GREY := Color(0.78, 0.88, 0.95)

var layer: PartyLayer
var owner_id: int = 0
var key: String = ""
var points: Array[Vector3] = []
var sway_seed: float = 0.0
var t: float = 0.0
var _lengths: Array[float] = []
var _total: float = 0.0
var _cooldown: float = 0.0
var _dummy_cd: Dictionary = {}
var _spin: Node3D
var _done: bool = false
## Own funnel materials (they fade as it winds down) and their full alphas.
var _mats: Array[StandardMaterial3D] = []
var _alphas: Array[float] = []


func _ready() -> void:
	if layer != null and key != "":
		layer.hazards[key] = self
	for i: int in range(1, points.size()):
		var l: float = points[i - 1].distance_to(points[i])
		_lengths.append(l)
		_total += l
	_build()
	global_position = pos_at(0.0)
	scale = Vector3(0.2, 0.2, 0.2)
	create_tween().tween_property(self, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _build() -> void:
	_spin = Node3D.new()
	add_child(_spin)
	# the funnel: stacked translucent cones and swirling rings of dust, wider toward the top
	var mat: StandardMaterial3D = PartyFx.fading_mat(Color(0.8, 0.9, 1.0, 0.07), 1.2)
	var c: CylinderMesh = PartyFx.cyl_mesh(0.35, HEIGHT, 2.0, 20)
	c.cap_top = false
	c.cap_bottom = false
	PartyFx.part(_spin, c, mat, Vector3(0, HEIGHT * 0.5, 0))
	var mat2: StandardMaterial3D = PartyFx.fading_mat(Color(1.0, 1.0, 1.0, 0.06), 1.4)
	var c2: CylinderMesh = PartyFx.cyl_mesh(0.2, HEIGHT * 0.8, 1.3, 16)
	c2.cap_top = false
	c2.cap_bottom = false
	PartyFx.part(_spin, c2, mat2, Vector3(0, HEIGHT * 0.42, 0))
	# wind bands: thin tilted rings whipping round inside the funnel
	var band: StandardMaterial3D = PartyFx.fading_mat(Color(1.0, 1.0, 1.0, 0.22), 1.3)
	for i: int in 4:
		var h: float = 0.6 + float(i) * (HEIGHT / 4.5)
		var r: float = lerpf(0.5, 1.9, float(i) / 3.0)
		var tm := TorusMesh.new()
		tm.inner_radius = 0.93
		tm.outer_radius = 1.0
		tm.rings = 32
		tm.ring_segments = 4
		PartyFx.part(_spin, tm, band, Vector3(0, h, 0), Vector3(r, 1.0, r * 0.9), Vector3(8.0 + 5.0 * float(i % 2), 30.0 * float(i), -6.0))
	for m: StandardMaterial3D in [mat, mat2, band]:
		_mats.append(m)
		_alphas.append(m.albedo_color.a)
	for i: int in 6:
		var h: float = 0.3 + float(i) * (HEIGHT / 6.0)
		var r: float = lerpf(0.45, 2.1, float(i) / 5.0)
		# swirling dust: alpha-blended grey-white puffs whipped round with the funnel
		var e: GPUParticles3D = PartyFx.emitter({"amount": 30, "lifetime": 0.7, "size": 0.55 + 0.12 * float(i), "color": Color(0.86, 0.9, 0.95, 0.75),
			"tex": "smoke", "shape": "ring", "radius": r, "inner": r * 0.8, "height": 0.3, "vmin": 0.0, "vmax": 0.3, "dir": Vector3.UP,
			"spread": 20.0, "local": true, "aabb": 6.0, "additive": false, "angle": true, "shrink": false,
			"colors": [Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0.0)]})
		e.position = Vector3(0, h, 0)
		_spin.add_child(e)
	# debris - clods and pebbles, leaves - carried round and up with the wind
	var clods: GPUParticles3D = PartyFx.emitter({"amount": 14, "lifetime": 1.3, "facing": "mesh", "mesh": Fx.chunk_mesh(0.14),
		"color": Color(0.5, 0.42, 0.32), "shape": "ring", "radius": 1.3, "inner": 0.7, "height": 1.0, "dir": Vector3.UP,
		"spread": 10.0, "vmin": 1.5, "vmax": 3.0, "local": true, "angle": true, "spin": 300.0, "scale_min": 0.6, "scale_max": 1.3,
		"aabb": 7.0, "colors": [Color(1, 1, 1, 1), Color(1, 1, 1, 1)]})
	clods.position = Vector3(0, 0.4, 0)
	_spin.add_child(clods)
	_spin.add_child(PartyFx.emitter({"amount": 18, "lifetime": 1.2, "size": Vector2(0.18, 0.12), "color": Color(0.55, 0.8, 0.35),
		"tex": "none", "shape": "ring", "radius": 1.2, "inner": 0.6, "height": 2.0, "vmin": 2.0, "vmax": 4.0, "dir": Vector3.UP,
		"spread": 15.0, "local": true, "additive": false, "angle": true, "spin": 400.0, "flutter": true, "aabb": 7.0,
		"pick": [Color(0.5, 0.8, 0.3), Color(0.75, 0.85, 0.3), Color(0.4, 0.65, 0.25)],
		"colors": [Color(1, 1, 1, 1), Color(1, 1, 1, 1)]}))
	# the dust skirt at the base, and dust streaks being sucked in along the ground
	add_child(PartyFx.emitter({"amount": 30, "lifetime": 0.9, "size": 0.7, "color": Color(0.7, 0.65, 0.55, 0.45),
		"tex": "smoke", "shape": "ring", "radius": 1.0, "inner": 0.4, "vmin": 2.0, "vmax": 4.0, "dir": Vector3(1, 0.2, 0), "spread": 180.0,
		"flat": 1.0, "additive": false, "grow": true, "angle": true, "aabb": 6.0,
		"colors": [Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0.0)]}))
	var suck: GPUParticles3D = PartyFx.emitter({"amount": 20, "lifetime": 0.5, "size": Vector2(0.08, 0.7), "color": Color(0.9, 0.88, 0.8, 0.6),
		"tex": "streak", "facing": "velocity", "additive": false, "shape": "ring", "radius": 3.0, "inner": 2.4,
		"vmin": 0.5, "vmax": 1.0, "radial": -14.0, "dir": Vector3.UP, "spread": 10.0, "shrink": false, "aabb": 6.0,
		"colors": [Color(1, 1, 1, 0), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)]})
	suck.position = Vector3(0, 0.2, 0)
	add_child(suck)
	# a scar of churned-up dust left along its path, and grit thrown out of the top
	add_child(PartyFx.emitter({"amount": 26, "lifetime": 1.6, "size": 1.0, "color": Color(0.72, 0.66, 0.56, 0.35),
		"tex": "smoke", "shape": "ring", "radius": 0.8, "inner": 0.3, "vmin": 0.2, "vmax": 0.8, "dir": Vector3.UP,
		"spread": 40.0, "additive": false, "grow": true, "angle": true, "aabb": 12.0, "fixed_fps": 0,
		"colors": [Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.0)]}))
	var spray: GPUParticles3D = PartyFx.emitter({"amount": 20, "lifetime": 1.4, "facing": "mesh", "mesh": Fx.chunk_mesh(0.1),
		"color": Color(0.45, 0.38, 0.3), "shape": "ring", "radius": 2.0, "inner": 1.6, "vmin": 3.0, "vmax": 6.0,
		"dir": Vector3(1, 0.4, 0), "spread": 180.0, "flat": 0.6, "gravity": Vector3(0, -14, 0), "angle": true,
		"spin": 400.0, "aabb": 14.0, "colors": [Color(1, 1, 1, 1), Color(1, 1, 1, 1)]})
	spray.position = Vector3(0, HEIGHT * 0.85, 0)
	add_child(spray)


## Where the tornado is `time` seconds after spawning (the same on every screen).
func pos_at(time: float) -> Vector3:
	if points.is_empty():
		return Vector3.ZERO
	var s: float = clampf(time * SPEED, 0.0, _total)
	var base: Vector3 = points[points.size() - 1]
	var dir := Vector3.FORWARD
	for i: int in _lengths.size():
		if s <= _lengths[i] or i == _lengths.size() - 1:
			var k: float = clampf(s / maxf(_lengths[i], 0.01), 0.0, 1.0)
			base = points[i].lerp(points[i + 1], k)
			dir = (points[i + 1] - points[i])
			break
		s -= _lengths[i]
	dir.y = 0.0
	var side: Vector3 = dir.normalized().cross(Vector3.UP) if dir.length() > 0.01 else Vector3.RIGHT
	# weave: wide lazy S-curves (fading in over the first second so it starts at its owner)
	return base + side * sin(time * 1.4 + sway_seed) * 2.6 * clampf(time, 0.0, 1.0)


func _physics_process(dt: float) -> void:
	if _done:
		return
	t += dt
	_cooldown = maxf(_cooldown - dt, 0.0)
	var p: Vector3 = pos_at(t)
	global_position = p
	if t >= LIFE:
		dissipate()
		return
	if layer == null:
		return
	var me: int = Net.my_id()
	if owner_id != me and _cooldown <= 0.0 and layer.is_rival(owner_id) and layer.local_vulnerable() and _catches(layer.player.global_position):
		_cooldown = 1.6
		var out: Vector3 = layer.player.global_position - p
		out.y = 0.0
		var tangent: Vector3 = out.normalized().cross(Vector3.UP) if out.length() > 0.1 else Vector3.RIGHT
		layer.take_hazard(owner_id, tangent * 9.0 + out.normalized() * 3.0 + Vector3(0, 17.0, 0), {"st": 0.7, "e": "spin", "ed": 1.0, "s": "tornado"})
		_fling_fx(layer.player.global_position)
	if owner_id == me:
		for d: PracticeDummy in layer.dummies:
			if not is_instance_valid(d) or d.knocked_out or float(_dummy_cd.get(d.id, 0.0)) > t:
				continue
			if _catches(d.global_position):
				_dummy_cd[d.id] = t + 1.6
				var out2: Vector3 = d.global_position - p
				out2.y = 0.0
				var tan2: Vector3 = out2.normalized().cross(Vector3.UP) if out2.length() > 0.1 else Vector3.RIGHT
				layer.hit({"id": d.id, "node": d, "pos": d.global_position, "center": d.center(), "vel": d.vel,
					"grounded": d.grounded, "dummy": true}, tan2 * 9.0 + Vector3(0, 17.0, 0), {"st": 0.7, "s": "tornado", "quiet": true})
				_fling_fx(d.global_position)


func _process(dt: float) -> void:
	if _spin != null:
		_spin.rotation.y += dt * 9.0
		# winding down: the funnel thins and fades over its last moments
		var left: float = LIFE - t
		if left < 1.2 and not _done:
			var k: float = clampf(left / 1.2, 0.0, 1.0)
			_spin.scale = Vector3(lerpf(0.55, 1.0, k), 1.0, lerpf(0.55, 1.0, k))
			for i: int in _mats.size():
				_mats[i].albedo_color.a = _alphas[i] * k


func _catches(feet: Vector3) -> bool:
	var d: Vector3 = feet - global_position
	return d.y > -1.2 and d.y < HEIGHT and Vector2(d.x, d.z).length() < RADIUS


func _fling_fx(at: Vector3) -> void:
	var w: Node = get_parent()
	PartyFx.one_shot(w, at + Vector3(0, 0.8, 0), {"amount": 30, "lifetime": 0.6, "size": 0.3, "color": GREY,
		"dir": Vector3.UP, "spread": 50.0, "vmin": 4.0, "vmax": 9.0, "tangential": 12.0, "damping": 4.0})
	PartyFx.one_shot(w, at + Vector3(0, 0.8, 0), {"amount": 16, "lifetime": 0.5, "size": Vector2(0.08, 1.0),
		"color": Color(1.2, 1.25, 1.3, 0.8), "tex": "streak", "facing": "velocity", "dir": Vector3.UP, "spread": 25.0,
		"vmin": 10.0, "vmax": 16.0, "damping": 8.0, "colors": [Color(1, 1, 1, 1), Color(1, 1, 1, 0)]})
	PartyFx.star_ring(w, at + Vector3(0, 0.8, 0), Color(1.0, 0.9, 0.4), 6, 4.0, 0.34)
	PartyFx.debris(w, at + Vector3(0, 0.3, 0), Color(0.5, 0.42, 0.32), 8, 6.0, 0.13)
	PartyFx.comic_burst(w, at + Vector3(0, 2.2, 0), "WHOOSH!", Color(0.6, 0.85, 1.0), 0.75)
	if layer != null:
		layer.sfx.play_at("wind", at, 1.0, 1.2)


func dissipate() -> void:
	if _done:
		return
	_done = true
	if layer != null and layer.hazards.get(key) == self:
		layer.hazards.erase(key)
	for c: Node in find_children("*", "GPUParticles3D", true, false):
		(c as GPUParticles3D).emitting = false
	var w: Node = get_parent()
	PartyFx.smoke(w, global_position + Vector3(0, 1.0, 0), Color(0.8, 0.85, 0.9, 0.5), 16, 1.2, 1.2)
	# what it was carrying falls out of the sky
	PartyFx.debris(w, global_position + Vector3(0, 2.5, 0), Color(0.5, 0.42, 0.32), 10, 3.0, 0.14)
	PartyFx.one_shot(w, global_position + Vector3(0, 3.0, 0), {"amount": 16, "lifetime": 2.0, "size": Vector2(0.18, 0.12),
		"tex": "none", "additive": false, "shape": "sphere", "radius": 1.5, "vmin": 0.5, "vmax": 2.0,
		"gravity": Vector3(0, -2.0, 0), "damping": 1.0, "angle": true, "spin": 300.0, "flutter": true, "turbulence": 1.0,
		"pick": [Color(0.5, 0.8, 0.3), Color(0.75, 0.85, 0.3), Color(0.4, 0.65, 0.25)], "color": Color.WHITE,
		"colors": [Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)]})
	PartyFx.one_shot(w, global_position + Vector3(0, 0.3, 0), {"amount": 22, "lifetime": 0.9, "size": 0.9,
		"color": Color(0.8, 0.78, 0.7, 0.5), "additive": false, "tex": "smoke", "shape": "ring", "radius": 0.6, "inner": 0.3,
		"dir": Vector3(1, 0.1, 0), "spread": 180.0, "flat": 1.0, "vmin": 3.0, "vmax": 5.0, "damping": 4.0, "grow": true,
		"angle": true, "colors": [Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)]})
	var tw: Tween = create_tween()
	tw.tween_property(self, "scale", Vector3(1.8, 0.05, 1.8), 0.6).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)
