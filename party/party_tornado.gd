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
	var mat: StandardMaterial3D = PartyFx.glow_mat(Color(0.8, 0.9, 1.0, 0.13), 1.4, true)
	var c: CylinderMesh = PartyFx.cyl_mesh(0.35, HEIGHT, 2.0, 20)
	c.cap_top = false
	c.cap_bottom = false
	PartyFx.part(_spin, c, mat, Vector3(0, HEIGHT * 0.5, 0))
	var c2: CylinderMesh = PartyFx.cyl_mesh(0.2, HEIGHT * 0.8, 1.3, 16)
	c2.cap_top = false
	c2.cap_bottom = false
	PartyFx.part(_spin, c2, PartyFx.glow_mat(Color(1.0, 1.0, 1.0, 0.1), 1.6, true), Vector3(0, HEIGHT * 0.42, 0))
	for i: int in 6:
		var h: float = 0.3 + float(i) * (HEIGHT / 6.0)
		var r: float = lerpf(0.45, 2.1, float(i) / 5.0)
		var e: GPUParticles3D = PartyFx.emitter({"amount": 26, "lifetime": 0.7, "size": 0.35 + 0.08 * float(i), "color": GREY,
			"shape": "ring", "radius": r, "inner": r * 0.8, "height": 0.3, "vmin": 0.0, "vmax": 0.3, "dir": Vector3.UP,
			"spread": 20.0, "orbit": 0.0, "tangential": 26.0, "radial": -r * 3.0, "local": true, "aabb": 6.0,
			"colors": [Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.0)]})
		e.position = Vector3(0, h, 0)
		add_child(e)
	# debris (leaves, pebbles) whipped around, and a dust skirt at the base
	add_child(PartyFx.emitter({"amount": 20, "lifetime": 1.2, "size": 0.12, "color": Color(0.55, 0.75, 0.4),
		"shape": "ring", "radius": 1.2, "inner": 0.6, "height": 2.0, "vmin": 2.0, "vmax": 4.0, "dir": Vector3.UP,
		"spread": 15.0, "tangential": 18.0, "local": true, "additive": false, "angle": true, "aabb": 6.0}))
	add_child(PartyFx.emitter({"amount": 30, "lifetime": 0.9, "size": 0.7, "color": Color(0.7, 0.65, 0.55, 0.45),
		"shape": "ring", "radius": 1.0, "inner": 0.4, "vmin": 2.0, "vmax": 4.0, "dir": Vector3(1, 0.2, 0), "spread": 180.0,
		"flat": 1.0, "tangential": 10.0, "additive": false, "grow": true, "aabb": 6.0,
		"colors": [Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0.0)]}))


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


func _catches(feet: Vector3) -> bool:
	var d: Vector3 = feet - global_position
	return d.y > -1.2 and d.y < HEIGHT and Vector2(d.x, d.z).length() < RADIUS


func _fling_fx(at: Vector3) -> void:
	PartyFx.one_shot(get_parent(), at + Vector3(0, 0.8, 0), {"amount": 30, "lifetime": 0.6, "size": 0.3, "color": GREY,
		"dir": Vector3.UP, "spread": 50.0, "vmin": 4.0, "vmax": 9.0, "tangential": 12.0, "damping": 4.0})
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
	PartyFx.smoke(get_parent(), global_position + Vector3(0, 1.0, 0), Color(0.8, 0.85, 0.9, 0.5), 16, 1.2, 1.2)
	var tw: Tween = create_tween()
	tw.tween_property(self, "scale", Vector3(1.8, 0.05, 1.8), 0.6).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)
