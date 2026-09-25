class_name XenoSnapjaw
extends Node3D
## Xeno Wilds: a giant carnivorous flytrap lying across the path - a horizontal crusher. Its two
## toothed lobes are hinged along the path's edges; open, they lie back and droop out over the drop,
## then on a fixed rhythm (Game.course_time) they SNAP up and inward, meeting over the path like a
## tent of teeth. Caught between them while they are shut = back to the checkpoint. Readable: the
## wet red trap inside the lobes glows brighter and brighter for a long beat before every snap (the
## "lingering glow"), and goes dark again as the jaws fall open.
## Positioned at the floor point at the middle of the mouth; the path runs along local Z.
##   u 0.00-0.30 open   0.30-0.62 glow warning (open)   0.62-0.68 SNAP   0.68-0.84 shut   0.84-1.00 open up

@export var width: float = 3.0
## Extent of the mouth along the path.
@export var length: float = 3.2
## Lobe length, hinge to rim (the lobes meet over the middle when shut: >= width / 2).
@export var lobe: float = 3.0
@export var period: float = 3.0
@export var phase: float = 0.0
@export var tint: Color = Color(1.0, 0.25, 0.3)

const WARN: float = 0.30
const SNAP: float = 0.62
const SHUT: float = 0.68
const OPEN: float = 0.84
const OPEN_DEG: float = 118.0

var _kill: Area3D
var _pivots: Array[Node3D] = []
var _trap_mat: StandardMaterial3D
var _shut_deg: float = 30.0
var _light: OmniLight3D
var _snap_fx: GPUParticles3D
var _drip: GPUParticles3D
var _fx_u: float = -1.0
var _flash: float = 0.0


func _ready() -> void:
	_shut_deg = rad_to_deg(asin(clampf(width * 0.5 / lobe, 0.05, 0.95)))
	_kill = Area3D.new()
	_kill.collision_layer = 0
	_kill.collision_mask = 2
	_kill.monitorable = false
	var ks := BoxShape3D.new()
	var roof: float = lobe * cos(deg_to_rad(_shut_deg))
	ks.size = Vector3(width - 0.2, roof - 0.2, length - 0.3)
	var kcs := CollisionShape3D.new()
	kcs.shape = ks
	_kill.add_child(kcs)
	_kill.position = Vector3(0, roof * 0.5, 0)
	add_child(_kill)
	_build_visual()
	add_to_group("course_clock")
	_pose(Game.course_time)


func _u(time: float) -> float:
	return fposmod(time / period + phase, 1.0)


## 0 = wide open .. 1 = shut.
func closure_at(time: float) -> float:
	var u: float = _u(time)
	if u < SNAP:
		return 0.0
	if u < SHUT:
		var k: float = (u - SNAP) / (SHUT - SNAP)
		return k * k
	if u < OPEN:
		return 1.0
	var r: float = (u - OPEN) / (1.0 - OPEN)
	return 1.0 - r * r * (3.0 - 2.0 * r)


## Deadly from the moment the lobes are half way up until they are half way open again.
func is_deadly_at(time: float) -> bool:
	return closure_at(time) > 0.45


## True while the mouth stays harmless for the next `window` seconds.
func is_clear_for(time: float, window: float) -> bool:
	var s: float = 0.0
	while s <= window:
		if is_deadly_at(time + s):
			return false
		s += 0.04
	return true


## Seconds until the next snap starts (0 while snapping / shut).
func time_until_snap(time: float) -> float:
	var u: float = _u(time)
	return (SNAP - u) * period if u < SNAP else (1.0 - u + SNAP) * period


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


func _process(dt: float) -> void:
	var t: float = Game.course_time
	_flash = maxf(_flash - dt * 2.5, 0.0)
	_pose(t)
	var u: float = _u(t)
	var was: float = _fx_u
	_fx_u = u
	if was < 0.0 or u - was > 0.25 or u < was:
		return
	if was < SNAP and u >= SNAP:
		WorldAudio.at(self, "snapjaw_snap", global_position + Vector3(0, 1.2, 0), 1.0, 45.0)
	if was < SHUT and u >= SHUT:
		_snap_fx.restart()
		_snap_fx.emitting = true
		_flash = 1.0 if Fx.density() >= 0.5 else 0.0
	if was < OPEN and u >= OPEN:
		WorldAudio.at(self, "snapjaw_open", global_position + Vector3(0, 1.2, 0), 0.7, 35.0)
		_drip.restart()
		_drip.emitting = true


func _pose(t: float) -> void:
	var c: float = closure_at(t)
	var ang: float = lerpf(-OPEN_DEG, _shut_deg, c)
	for i: int in _pivots.size():
		var s: float = 1.0 if i == 0 else -1.0
		_pivots[i].rotation.z = deg_to_rad(ang) * s
	# the lingering glow: builds through the warning, peaks shut, fades as they open
	var u: float = _u(t)
	var g: float = 0.35
	if u >= WARN and u < SNAP:
		var k: float = (u - WARN) / (SNAP - WARN)
		g = 0.35 + 3.2 * k * (0.8 + 0.2 * sin(t * 30.0))
	elif u >= SNAP and u < OPEN:
		g = 3.6
	elif u >= OPEN:
		g = lerpf(3.6, 0.35, (u - OPEN) / (1.0 - OPEN))
	_trap_mat.emission_energy_multiplier = g
	if _light != null:
		_light.light_energy = g * 0.45 + _flash * 4.0


func _build_visual() -> void:
	var skin: StandardMaterial3D = Look.flat(Color(0.28, 0.55, 0.22), 0.6)
	var rim_mat: StandardMaterial3D = Look.flat(Color(0.55, 0.85, 0.25), 0.5, 0.0, 0.5)
	var tooth_mat: StandardMaterial3D = Look.flat(Color(0.95, 0.95, 0.75), 0.4, 0.0, 0.6)
	_trap_mat = StandardMaterial3D.new()
	_trap_mat.albedo_color = tint.darkened(0.2)
	_trap_mat.emission_enabled = true
	_trap_mat.emission = tint
	_trap_mat.emission_energy_multiplier = 0.35
	_trap_mat.roughness = 0.25
	var teeth: int = maxi(int(length / 0.42), 5)
	for side: float in [1.0, -1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(side * width * 0.5, 0.0, 0.0)
		add_child(pivot)
		_pivots.append(pivot)
		# the lobe: a shallow shell (outer skin + the glowing trap face turned toward the path)
		var shell := Look.sphere(1.0, skin, Vector3(side * 0.12, lobe * 0.5, 0))
		shell.scale = Vector3(0.28, lobe * 0.52, length * 0.52)
		pivot.add_child(shell)
		var face := Look.sphere(1.0, _trap_mat, Vector3(-side * 0.05, lobe * 0.5, 0))
		face.scale = Vector3(0.14, lobe * 0.47, length * 0.47)
		face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(face)
		# the rim and its interlocking teeth (cilia), pointing in across the path
		var rim := Look.cylinder(0.12, length * 0.95, rim_mat, Vector3(0, lobe, 0), -1.0, 8)
		rim.rotation.x = PI * 0.5
		pivot.add_child(rim)
		for k: int in teeth:
			var z: float = -length * 0.46 + float(k) * length * 0.92 / float(teeth - 1) + (0.1 if side > 0.0 else -0.1)
			var tooth := Look.cylinder(0.07, 0.95, tooth_mat, Vector3(-side * 0.42, lobe + 0.02, z), 0.0, 5)
			tooth.rotation.z = side * PI * 0.5
			pivot.add_child(tooth)
		# a few trigger hairs on the trap face
		for k: int in 3:
			var hair := Look.cylinder(0.025, 0.55, tooth_mat, Vector3(-side * 0.18, lobe * (0.35 + 0.15 * float(k)), (float(k) - 1.0) * length * 0.25), 0.01, 4)
			hair.rotation.z = side * 1.1
			pivot.add_child(hair)
	# the gum along each hinge line: a leafy ridge so the lobes read as rooted
	for side: float in [1.0, -1.0]:
		var gum := Look.cylinder(0.3, length + 0.4, skin, Vector3(side * (width * 0.5 + 0.1), -0.05, 0), -1.0, 10)
		gum.rotation.x = PI * 0.5
		add_child(gum)
	_light = OmniLight3D.new()
	_light.light_color = tint
	_light.omni_range = maxf(width, length) + 3.0
	_light.light_energy = 0.2
	_light.position = Vector3(0, 1.4, 0)
	_light.shadow_enabled = false
	add_child(_light)
	var vis := AABB(Vector3(-width - 4.0, -3.0, -length - 3.0), Vector3(width * 2.0 + 8.0, lobe + 6.0, length * 2.0 + 6.0))
	# the snap: a spray of sap droplets and a flat shockwave off the closed jaws
	_snap_fx = Fx.burst({"amount": 34, "lifetime": 0.7, "shape": "box", "extents": Vector3(0.3, 0.2, length * 0.45),
		"dir": Vector3.UP, "spread": 70.0, "speed": Vector2(3.0, 7.0), "gravity": Vector3(0, -14, 0),
		"size": 0.16, "color": Fx.hot(Color(0.75, 1.0, 0.3), 2.0), "aabb": vis})
	_snap_fx.position = Vector3(0, lobe * 0.85, 0)
	add_child(_snap_fx)
	# opening: strings of glowing sap dripping off the lips
	_drip = Fx.emitter({"amount": 16, "lifetime": 0.9, "one_shot": true, "explosiveness": 0.6, "shape": "box",
		"extents": Vector3(width * 0.45, 0.1, length * 0.45), "dir": Vector3.DOWN, "spread": 10.0,
		"speed": Vector2(0.2, 0.8), "gravity": Vector3(0, -9, 0), "tex": Fx.Tex.DOT, "size": 0.12,
		"color": Fx.hot(tint.lightened(0.2), 1.8), "aabb": vis})
	_drip.position = Vector3(0, lobe * 0.8, 0)
	add_child(_drip)
	# always: a few midges drawn to the glow
	var midges: GPUParticles3D = Fx.emitter({"amount": 8, "lifetime": 2.0, "shape": "box",
		"extents": Vector3(width * 0.6, 0.8, length * 0.6), "speed": Vector2(0.2, 0.6), "spread": 180.0,
		"turbulence": 1.5, "tex": Fx.Tex.DOT, "size": 0.08, "curve": "pop", "color": Color(2.2, 2.4, 1.0),
		"aabb": vis, "preprocess": 2.0, "local": true})
	midges.position = Vector3(0, lobe * 0.6, 0)
	add_child(midges)
