class_name AbyssAngler
extends Node3D
## The Abyss: an ANGLER - a monstrous anglerfish lying in the dark beside the path, its jaw hinged
## along the path's left edge. While it waits, its lure hangs glowing over the middle of the path,
## bobbing ahead of you; the jaw is held wide open, high over the walkway. On a fixed rhythm
## (Game.course_time) it strikes: for `warn` seconds the lure is snatched back toward the head,
## its eye flares red, the jaw trembles and it growls - then the jaw SLAMS across the path and
## stays shut for `shut` seconds before it lifts open again. Caught under it while it is shut =
## back to the checkpoint.
## Positioned at the floor point in the middle of the mouth; the path runs along local Z, the
## hinge (and the fish's head) is on local -X.
##   s (seconds into the cycle): open ... warn ... SNAP (0.14 s) ... shut ... reopen (0.5 s)

@export var width: float = 2.6
## Extent of the mouth along the path.
@export var length: float = 2.6
@export var period: float = 4.0
@export var phase: float = 0.0
@export var warn: float = 1.0
@export var shut: float = 0.7
@export var tint: Color = Color(0.5, 1.0, 0.95)

const SNAP_LEN: float = 0.14
const REOPEN_LEN: float = 0.5
const OPEN_DEG: float = 72.0
const HINGE_UP: float = 2.3

var _kill: Area3D
var _jaw: Node3D
var _eye_mat: StandardMaterial3D
var _lure: Node3D
var _lure_light: OmniLight3D
var _lure_mat: StandardMaterial3D
var _snap_fx: GPUParticles3D
var _silt: GPUParticles3D
var _fx_s: float = -1.0


func _ready() -> void:
	_kill = Area3D.new()
	_kill.collision_layer = 0
	_kill.collision_mask = 2
	_kill.monitorable = false
	var ks := BoxShape3D.new()
	ks.size = Vector3(width - 0.1, HINGE_UP - 0.2, length - 0.3)
	var kcs := CollisionShape3D.new()
	kcs.shape = ks
	_kill.add_child(kcs)
	_kill.position = Vector3(0, HINGE_UP * 0.5, 0)
	add_child(_kill)
	_build_visual()
	add_to_group("course_clock")
	snap_to_clock()


func _s(time: float) -> float:
	return fposmod(time / period + phase, 1.0) * period


## Seconds into the cycle at which the jaw starts to snap.
func snap_start() -> float:
	return period - SNAP_LEN - shut - REOPEN_LEN


## 0 = wide open .. 1 = shut.
func closure_at(time: float) -> float:
	var s: float = _s(time) - snap_start()
	if s < 0.0:
		return 0.0
	if s < SNAP_LEN:
		var k: float = s / SNAP_LEN
		return k * k
	s -= SNAP_LEN
	if s < shut:
		return 1.0
	s -= shut
	var r: float = clampf(s / REOPEN_LEN, 0.0, 1.0)
	return 1.0 - r * r * (3.0 - 2.0 * r)


## Deadly while the jaw is more than half way down.
func is_deadly_at(time: float) -> bool:
	return closure_at(time) > 0.4


## True while the mouth stays harmless for the next `window` seconds.
func is_clear_for(time: float, window: float) -> bool:
	var s: float = 0.0
	while s <= window:
		if is_deadly_at(time + s):
			return false
		s += 0.04
	return not is_deadly_at(time + window)


## Harmless for the whole of [time + a, time + b].
func clear_between(time: float, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if is_deadly_at(time + s):
			return false
		s += 0.04
	return not is_deadly_at(time + b)


## Seconds until the next snap starts (0 while snapping / shut).
func time_until_snap(time: float) -> float:
	var s: float = _s(time)
	var st: float = snap_start()
	return st - s if s < st else 0.0


func snap_to_clock() -> void:
	_pose(Game.course_time)


func _physics_process(_dt: float) -> void:
	var t: float = Game.course_time
	if not is_deadly_at(t):
		return
	for body: Node3D in _kill.get_overlapping_bodies():
		if body is Player:
			var n: Node = self
			while n != null and not n.has_method("fail"):
				n = n.get_parent()
			if n != null:
				n.call_deferred("fail", "hazard")
			return


func _process(_dt: float) -> void:
	var t: float = Game.course_time
	_pose(t)
	var s: float = _s(t)
	var was: float = _fx_s
	_fx_s = s
	if was < 0.0:
		return
	var st: float = snap_start()
	if was < st - warn and s >= st - warn:
		# SOUND: abyss_angler_growl - a deep wet growl and a creak as the lure is snatched back (~1 s ahead)
		WorldAudio.at(self, "abyss_angler_growl", global_position, 0.8, 35.0)
	if was < st and s >= st:
		_snap_fx.restart()
		_silt.restart()
		# SOUND: abyss_angler_snap - the jaw slamming shut, a crunch of teeth
		WorldAudio.at(self, "abyss_angler_snap", global_position, 1.0, 45.0)


func _pose(t: float) -> void:
	var c: float = closure_at(t)
	var s: float = _s(t)
	var st: float = snap_start()
	var w: float = 0.0
	if s < st and s >= st - warn:
		w = clampf(1.0 - (st - s) / warn, 0.0, 1.0)
	var tremble: float = sin(t * 60.0) * 1.5 * w
	_jaw.rotation.z = deg_to_rad(OPEN_DEG * (1.0 - c) - 14.0 * c + tremble)
	_eye_mat.emission = Color(1.0, 0.15, 0.1) if (w > 0.0 or c > 0.0) else Color(0.2, 0.5, 0.55)
	_eye_mat.emission_energy_multiplier = 0.6 + 4.0 * maxf(w, c)
	# the lure: bobs over the path while it waits, is snatched back to the head as it strikes
	var back: float = maxf(smoothstep(0.0, 0.6, w), c)
	if s > st + SNAP_LEN + shut:
		back = 1.0 - smoothstep(0.0, REOPEN_LEN, s - st - SNAP_LEN - shut)
	var bob := Vector3(0, sin(t * 1.7) * 0.12, sin(t * 0.9) * 0.3)
	_lure.position = Vector3(lerpf(0.0, -width * 0.5 - 1.6, back), lerpf(3.2, 2.6, back), 0) + bob * (1.0 - back)
	_lure_mat.emission_energy_multiplier = lerpf(5.0, 1.2, back)
	_lure_light.light_energy = lerpf(2.2, 0.6, back)


func _build_visual() -> void:
	var skin: StandardMaterial3D = Look.flat(Color(0.09, 0.07, 0.08), 0.65, 0.1)
	var gum: StandardMaterial3D = Look.flat(Color(0.32, 0.08, 0.12), 0.5, 0.0, 0.4)
	var tooth: StandardMaterial3D = Look.flat(Color(0.85, 0.92, 0.95), 0.2, 0.0, 0.6)
	var hx: float = width * 0.5
	# the head: a great dark mass beside the path (never on it)
	var head := Look.sphere(1.0, skin, Vector3(-hx - 2.4, 1.0, 0))
	head.scale = Vector3(2.0, 2.2, length * 0.75 + 0.6)
	add_child(head)
	var brow := Look.box(Vector3(1.6, 0.5, length + 0.6), skin, Vector3(-hx - 1.4, HINGE_UP + 0.6, 0))
	brow.rotation.z = -0.4
	add_child(brow)
	# the eye (glows red while it strikes)
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.albedo_color = Color(0.1, 0.1, 0.12)
	_eye_mat.emission_enabled = true
	_eye_mat.emission = Color(0.2, 0.5, 0.55)
	_eye_mat.emission_energy_multiplier = 0.6
	_eye_mat.roughness = 0.1
	for sz: float in [-1.0, 1.0]:
		var eye := Look.sphere(0.32, _eye_mat, Vector3(-hx - 1.9, HINGE_UP + 0.5, sz * (length * 0.5 + 0.2)))
		add_child(eye)
	# lower jaw: a lip of gum and teeth along the far (right) edge, below and outside the walkway
	var lower := Look.box(Vector3(0.5, 0.6, length + 0.4), gum, Vector3(hx + 0.4, -0.5, 0))
	add_child(lower)
	var n: int = maxi(int(length / 0.45), 4)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.11
	cone.height = 0.7
	cone.radial_segments = 6
	cone.rings = 1
	for i: int in n:
		var z: float = -length * 0.5 + 0.2 + float(i) * (length - 0.4) / float(n - 1)
		add_child(Look.mesh_node(cone, tooth, Vector3(hx + 0.45, 0.1, z)))
	# the upper jaw, hinged along the left edge above the path
	_jaw = Node3D.new()
	_jaw.position = Vector3(-hx - 0.3, HINGE_UP, 0)
	add_child(_jaw)
	var span: float = width + 0.9
	var slab := Look.box(Vector3(span, 0.45, length + 0.3), skin, Vector3(span * 0.5, 0.1, 0))
	_jaw.add_child(slab)
	_jaw.add_child(Look.box(Vector3(span - 0.3, 0.12, length), gum, Vector3(span * 0.5, -0.15, 0)))
	# fangs along the jaw's free edge and two rows along its underside
	var fang := CylinderMesh.new()
	fang.top_radius = 0.13
	fang.bottom_radius = 0.0
	fang.height = 0.9
	fang.radial_segments = 6
	fang.rings = 1
	for i: int in n:
		var z2: float = -length * 0.5 + 0.2 + float(i) * (length - 0.4) / float(n - 1)
		_jaw.add_child(Look.mesh_node(fang, tooth, Vector3(span - 0.2, -0.55, z2)))
		if i % 2 == 0:
			var sm := Look.mesh_node(fang, tooth, Vector3(span * 0.55, -0.45, z2))
			sm.scale = Vector3(0.7, 0.7, 0.7)
			_jaw.add_child(sm)
	# the lure: a glowing bulb on a long stalk from the brow
	var stalk_mat: StandardMaterial3D = Look.flat(Color(0.12, 0.1, 0.1), 0.6)
	var stalk := Look.cylinder(0.05, 2.4, stalk_mat, Vector3(-hx - 0.8, HINGE_UP + 1.9, 0), 0.03, 6)
	stalk.rotation.z = -0.9
	add_child(stalk)
	_lure = Node3D.new()
	add_child(_lure)
	_lure_mat = StandardMaterial3D.new()
	_lure_mat.albedo_color = tint
	_lure_mat.emission_enabled = true
	_lure_mat.emission = tint
	_lure_mat.emission_energy_multiplier = 5.0
	_lure.add_child(Look.sphere(0.22, _lure_mat))
	_lure.add_child(Fx.sprite(Fx.hot(tint, 1.6), 1.4, Fx.Tex.DOT, true))
	_lure_light = OmniLight3D.new()
	_lure_light.light_color = tint
	_lure_light.light_energy = 2.2
	_lure_light.omni_range = 7.0
	_lure.add_child(_lure_light)
	var vis := AABB(Vector3(-width - 4.0, -2.0, -length - 2.0), Vector3(width * 2.0 + 8.0, 7.0, length * 2.0 + 4.0))
	_snap_fx = Fx.burst({"amount": 30, "lifetime": 0.6, "shape": "box", "extents": Vector3(width * 0.5, 0.2, length * 0.5),
		"dir": Vector3.UP, "spread": 70.0, "speed": Vector2(1.5, 4.0), "tex": Fx.Tex.BUBBLE, "size": 0.2,
		"color": Color(0.8, 1.2, 1.3, 0.8), "aabb": vis})
	_snap_fx.position = Vector3(0, 0.3, 0)
	add_child(_snap_fx)
	_silt = Fx.burst({"amount": 14, "lifetime": 1.4, "shape": "box", "extents": Vector3(width * 0.6, 0.1, length * 0.5),
		"dir": Vector3.UP, "spread": 80.0, "speed": Vector2(0.6, 1.6), "damping": Vector2(1.0, 2.0), "tex": Fx.Tex.SMOKE,
		"additive": false, "size": 1.2, "curve": "puff", "color": Color(0.3, 0.38, 0.4, 0.35), "aabb": vis})
	add_child(_silt)
