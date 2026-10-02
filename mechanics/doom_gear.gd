class_name DoomGear
extends RotatingPlatform
## Doom Fortress: a colossal GEAR lying flat and turning on the course clock - a spoked iron wheel
## whose rim (`rim_width` wide, centred `radius` from the axle) you ride, with square teeth standing
## out round its outside edge. The rim and the teeth are walkable; between the spokes is a drop into
## the machinery. A RotatingPlatform (same clock maths, so the route bot can predict it), but built
## from radial segments instead of axis-aligned arms. Positioned by the centre of the rim's TOP.

@export var radius: float = 6.0
@export var rim_width: float = 1.4
@export var teeth: int = 16
@export var spokes: int = 6
## Thickness of the rim (and the teeth).
@export var rim_thick: float = 0.6

var _grind: AudioStreamPlayer3D


func _ready() -> void:
	arms = []
	hub_radius = 0.0
	super._ready()
	var segs: int = maxi(int(TAU * radius / 1.5), 12)
	var iron: StandardMaterial3D = DoomDecor.iron()
	var steel: StandardMaterial3D = DoomDecor.steel()
	var y: float = -rim_thick * 0.5
	# the rim: radial box segments, overlapping slightly so the walk round it is seamless
	var seg_len: float = TAU * (radius + rim_width * 0.5) / float(segs) + 0.08
	for i: int in segs:
		var a: float = TAU * float(i) / float(segs)
		_box(Vector3(rim_width, rim_thick, seg_len), Vector3(cos(a) * radius, y, sin(a) * radius), a, true, "mover")
	# teeth round the outside, flush with the rim's top
	var tooth_w: float = TAU * (radius + rim_width * 0.5) / float(teeth) * 0.45
	for j: int in teeth:
		var b: float = TAU * (float(j) + 0.5) / float(teeth)
		var r: float = radius + rim_width * 0.5 + 0.45
		_box(Vector3(0.9, rim_thick, tooth_w), Vector3(cos(b) * r, y, sin(b) * r), b, true, "mover")
	# spokes (narrow, walkable) and the hub
	for k: int in spokes:
		var c: float = TAU * (float(k) + 0.25) / float(spokes)
		var len: float = radius - rim_width * 0.5 - 0.9
		var mid: float = 0.9 + len * 0.5
		_box(Vector3(len, 0.5, 0.55), Vector3(cos(c) * mid, -0.45, sin(c) * mid), c, true, "", iron)
	add_child(Look.cylinder(1.2, 1.4, iron, Vector3(0, -0.6, 0), -1.0, 20))
	add_child(Look.cylinder(0.6, 1.6, steel, Vector3(0, -0.5, 0), -1.0, 16))
	add_child(DoomDecor.ns(Look.cylinder(0.35, 1.7, DoomDecor.alarm(2.0), Vector3(0, -0.5, 0), -1.0, 12)))
	var hub_body := CollisionShape3D.new()
	var hc := CylinderShape3D.new()
	hc.radius = 1.2
	hc.height = 1.4
	hub_body.shape = hc
	hub_body.position = Vector3(0, -0.6, 0)
	add_child(hub_body)
	# a hazard-striped band round the rim's outer face, so the edge reads from far off
	for i2: int in segs:
		var a2: float = TAU * float(i2) / float(segs)
		var band := Look.box(Vector3(0.06, rim_thick * 0.5, seg_len), DoomDecor.hazard(0.4), Vector3(cos(a2) * (radius + rim_width * 0.5 + 0.03), y, sin(a2) * (radius + rim_width * 0.5 + 0.03)))
		band.rotation.y = -a2
		band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(band)
	# SOUND: doom_gear_grind - the great wheel grinding round on its bearing (loop)
	_grind = WorldAudio.loop("doom_gear_grind", self, -6.0, 30.0, 6.0)


## A radial box: local size (radial, height, tangential) at `pos`, turned to angle `a` round the axle.
func _box(size: Vector3, pos: Vector3, a: float, collide: bool, style: String, mat: Material = null) -> void:
	var basis_a := Basis(Vector3.UP, -a)
	if collide:
		var shape := BoxShape3D.new()
		shape.size = size
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.transform = Transform3D(basis_a, pos)
		add_child(cs)
	var vis: MeshInstance3D = Look.platform_box(size, style) if style != "" else Look.box(size, mat)
	vis.transform = Transform3D(basis_a, pos)
	add_child(vis)


## A world point on the rim's centre line at angle `a` (gear-local, before rotation) - for the bot.
func rim_local(a: float) -> Vector3:
	return Vector3(cos(a) * radius, 0.05, sin(a) * radius)
