class_name FungalSnail
extends MovingPlatform
## Mushroom Hollow: a SNAIL-SHELL MOVER. A big garden snail trundles back and forth along `points`
## (offsets from where it is built) on the course clock, and you ride the flat saddle of moss on top
## of its spiral shell. It is slow, it pauses at both ends (`dwell`) and its eye-stalks turn toward
## where it is going, so you can read it from afar. It carries the rider with its full velocity (an
## ordinary kinematic mover: nothing teleports) and loops seamlessly. `size` is the saddle (the
## collision box); it is positioned by the middle of that box, like every mover.

@export var tint: Color = Color(0.86, 0.5, 0.2)
## "snail" (a trundling snail) or "ladybird" (a flying ladybird: red wing-case saddle, buzzing wings).
@export var kind: String = "snail"

var _vis: Node3D
var _eyes: Array[Node3D] = []
var _wings: Array[Node3D] = []
var _face: float = 0.0


func _ready() -> void:
	sync_to_physics = false
	collision_layer = 1
	collision_mask = 0
	_origin = position
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	add_child(cs)
	if kind == "ladybird":
		_build_ladybird()
	else:
		_build_visual()
	position = _origin + offset_at(Game.course_time)
	reset_physics_interpolation()
	add_to_group("course_clock")
	# SOUND: fungal_snail_squelch - a soft, slow, wet trundling while it moves (loop, close range)
	WorldAudio.loop("fungal_snail_squelch", self, -16.0, 14.0, 3.0)


func _hums() -> bool:
	return false


func _process(_dt: float) -> void:
	var t: float = Game.course_time
	var v: Vector3 = offset_at(t + 0.15) - offset_at(t - 0.15)
	v.y = 0.0
	if v.length() > 0.02:
		_face = lerp_angle(_face, atan2(-v.x, -v.z), 0.08)
	_vis.rotation.y = _face
	if kind == "ladybird":
		for i: int in _wings.size():
			_wings[i].rotation.z = (0.5 + 0.45 * sin(t * 40.0)) * (1.0 if i == 0 else -1.0)
		_vis.position.y = sin(t * 3.0) * 0.04
		return
	# eye-stalks sway, and swing toward the way it is going
	for i: int in _eyes.size():
		_eyes[i].rotation.z = sin(t * 1.7 + float(i) * 2.0) * 0.12 + (0.25 if i == 0 else -0.25) * 0.4
		_eyes[i].rotation.x = -0.25 + sin(t * 1.3 + float(i)) * 0.1


func _build_visual() -> void:
	_vis = Node3D.new()
	_vis.name = "SnailBody"
	add_child(_vis)
	var half: float = size.y * 0.5
	# the saddle: a flat disc of moss on top of the shell, level with the collision box's top
	var moss: StandardMaterial3D = Look.flat(Color(0.42, 0.66, 0.28), 0.9)
	var shell_mat: StandardMaterial3D = Look.flat(tint, 0.5)
	var ring_mat: StandardMaterial3D = Look.flat(tint.darkened(0.3), 0.55)
	var cream: StandardMaterial3D = Look.flat(Color(0.97, 0.9, 0.7), 0.7)
	var r: float = maxf(size.x, size.z) * 0.5
	_vis.add_child(Look.cylinder(r, size.y, moss, Vector3.ZERO, r * 0.96, 24))
	# the shell: a fat disc below the saddle with spiral ridges round its flank
	var shell := Look.cylinder(r * 1.02, 1.3, shell_mat, Vector3(0, -half - 0.65, 0), r * 0.82, 28)
	_vis.add_child(shell)
	for i: int in 3:
		var tm := TorusMesh.new()
		tm.inner_radius = r * (0.78 - 0.17 * float(i)) - 0.05
		tm.outer_radius = r * (0.78 - 0.17 * float(i)) + 0.05
		tm.rings = 36
		tm.ring_segments = 5
		var rn := Look.mesh_node(tm, ring_mat, Vector3(0, -half - 0.04 - 0.02 * float(i), 0))
		rn.scale = Vector3(1, 0.3, 1)
		rn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_vis.add_child(rn)
	var lip := Look.sphere(r * 0.9, shell_mat, Vector3(0, -half - 1.1, 0))
	lip.scale = Vector3(1.0, 0.45, 1.0)
	_vis.add_child(lip)
	# the body: a long cream foot under the shell, a rounded head ahead (the snail faces local -Z)
	var foot := Look.sphere(1.0, cream, Vector3(0, -half - 1.45, -r * 0.55))
	foot.scale = Vector3(r * 0.62, 0.38, r * 1.9)
	_vis.add_child(foot)
	var head := Look.sphere(r * 0.42, cream, Vector3(0, -half - 1.0, -r * 1.55))
	head.scale = Vector3(1.0, 0.9, 1.15)
	_vis.add_child(head)
	# two eye-stalks with dark beads
	var bead: StandardMaterial3D = Look.flat(Color(0.12, 0.1, 0.1), 0.3)
	for sx: float in [-1.0, 1.0]:
		var stalk := Node3D.new()
		stalk.position = Vector3(sx * r * 0.2, -half - 0.8, -r * 1.65)
		stalk.add_child(Look.cylinder(0.07, 0.8, cream, Vector3(0, 0.4, 0), 0.05, 8))
		stalk.add_child(Look.sphere(0.13, bead, Vector3(0, 0.82, 0)))
		_vis.add_child(stalk)
		_eyes.append(stalk)


## A ladybird: the flat red wing-case saddle you ride (black spots and a centre line), a black belly,
## a head with antennae ahead (it faces local -Z), six legs and two buzzing wings at the sides.
func _build_ladybird() -> void:
	_vis = Node3D.new()
	_vis.name = "LadybirdBody"
	add_child(_vis)
	var half: float = size.y * 0.5
	var r: float = maxf(size.x, size.z) * 0.5
	var red: StandardMaterial3D = Look.flat(Color(0.9, 0.16, 0.12), 0.3)
	var ink: StandardMaterial3D = Look.flat(Color(0.1, 0.09, 0.11), 0.4)
	var white: StandardMaterial3D = Look.flat(Color(0.97, 0.95, 0.9), 0.4)
	_vis.add_child(Look.cylinder(r, size.y, red, Vector3.ZERO, r * 0.97, 28))
	# the wing-case seam and the spots (flat, on the deck)
	var seam := Look.box(Vector3(0.07, 0.02, r * 1.9), ink, Vector3(0, half + 0.011, 0))
	seam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vis.add_child(seam)
	for p: Vector3 in [Vector3(-0.6, 0, -0.55), Vector3(0.6, 0, -0.55), Vector3(-0.7, 0, 0.45), Vector3(0.7, 0, 0.45), Vector3(-0.35, 0, 1.0), Vector3(0.35, 0, 1.0)]:
		var sp := Look.cylinder(0.2, 0.02, ink, Vector3(p.x * r * 0.5, half + 0.011, p.z * r * 0.55), -1.0, 14)
		sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_vis.add_child(sp)
	# belly, head, eyes, antennae, legs
	var belly := Look.sphere(1.0, ink, Vector3(0, -half - 0.35, 0.1))
	belly.scale = Vector3(r * 0.88, 0.45, r * 1.05)
	_vis.add_child(belly)
	var head := Look.sphere(r * 0.42, ink, Vector3(0, -half - 0.15, -r * 1.1))
	_vis.add_child(head)
	for sx: float in [-1.0, 1.0]:
		_vis.add_child(Look.sphere(r * 0.13, white, Vector3(sx * r * 0.26, -half - 0.02, -r * 1.38)))
		var ant := Look.cylinder(0.025, r * 0.9, ink, Vector3(sx * r * 0.3, -half + 0.2, -r * 1.65), 0.015, 5)
		ant.rotation = Vector3(-0.9, 0, sx * 0.35)
		_vis.add_child(ant)
		for i: int in 3:
			var leg := Look.cylinder(0.04, r * 0.9, ink, Vector3(sx * r * 0.75, -half - 0.65, (float(i) - 1.0) * r * 0.55), 0.025, 5)
			leg.rotation.z = sx * 0.75
			_vis.add_child(leg)
	for i2: int in 2:
		var w := Node3D.new()
		var sx2: float = -1.0 if i2 == 0 else 1.0
		w.position = Vector3(sx2 * r * 0.9, half * 0.0 - 0.1, 0.2)
		var wing := Look.sphere(1.0, Look.flat(Color(0.85, 0.92, 1.0, 0.55), 0.2), Vector3(sx2 * r * 0.75, 0, 0))
		wing.scale = Vector3(r * 0.75, 0.02, r * 0.42)
		wing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		w.add_child(wing)
		_vis.add_child(w)
		_wings.append(w)
