class_name ArcaneBook
extends MovingPlatform
## Arcane Library: FLYING BOOK. A great leather-bound tome beating a pair of page-wings, carrying you
## along a fixed route through the air. It is a MovingPlatform (a pure function of the course clock,
## so it is identical for every racer and carries a rider with its full velocity - it never teleports)
## in a book's clothes: a gold-cornered cover you stand on, a block of pages, two fans of pages for
## wings that flap at `flap_rate` beats a second, and a motion trail of floating letters. Nothing
## about it can hurt you; the danger is only the gap under it.
## Move it like any mover: `points` (offsets from the start), `period`, `phase`, `dwell`.

@export var cover: Color = Color(0.5, 0.1, 0.22)
@export var flap_rate: float = 1.8

var _wings: Array[Node3D] = []
var _wing_phase: float = 0.0
var _letters: GPUParticles3D


func _hums() -> bool:
	return false


func _ready() -> void:
	super._ready()
	# the stock slab and thruster pods make way for the book
	for c: Node in get_children():
		if c is MeshInstance3D:
			c.queue_free()
	_build_book()
	WorldAudio.loop("arcane_book_flap", self, -19.0, 14.0, 3.0)


func _build_book() -> void:
	var half: Vector3 = size * 0.5
	var leather: StandardMaterial3D = Look.flat(cover, 0.55, 0.05)
	var gold: StandardMaterial3D = Look.flat(Color(1.0, 0.8, 0.35), 0.3, 0.8, 0.25)
	var page: StandardMaterial3D = Look.flat(Color(0.96, 0.9, 0.76), 0.85)
	var th: float = 0.1
	# the cover is the walking surface: its top is the collision top (size.y / 2)
	add_child(Look.box(Vector3(size.x, th, size.z), leather, Vector3(0, half.y - th * 0.5, 0)))
	add_child(Look.box(Vector3(size.x, th, size.z), leather, Vector3(0, -half.y + th * 0.5, 0)))
	# the page block between the covers, inset a little so the cream edge shows
	add_child(Look.box(Vector3(size.x - 0.16, size.y - th * 2.0 + 0.002, size.z - 0.14), page, Vector3(0.04, 0, 0)))
	# the spine along the -X side
	add_child(Look.box(Vector3(0.14, size.y, size.z), leather, Vector3(-half.x + 0.07, 0, 0)))
	# gold corner caps and a gilt frame on the cover
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			add_child(Look.box(Vector3(0.34, 0.05, 0.34), gold, Vector3(sx * (half.x - 0.17), half.y + 0.005, sz * (half.z - 0.17))))
	add_child(Look.box(Vector3(size.x - 0.7, 0.03, 0.05), gold, Vector3(0, half.y + 0.004, half.z - 0.3)))
	add_child(Look.box(Vector3(size.x - 0.7, 0.03, 0.05), gold, Vector3(0, half.y + 0.004, -half.z + 0.3)))
	# a glowing sigil tooled into the middle of the cover (a thin glowing disc)
	var sig := Look.cylinder(minf(size.x, size.z) * 0.22, 0.02, Look.flat(Color(1.0, 0.82, 0.4), 0.3, 0.0, 1.6), Vector3(0, half.y + 0.012, 0), -1.0, 24)
	sig.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sig)
	# the wings: fans of pages hinged at the cover's long edges, flapping up and down
	for sgn: float in [-1.0, 1.0]:
		var hinge := Node3D.new()
		hinge.position = Vector3(sgn * half.x, -0.04, 0)
		add_child(hinge)
		_wings.append(hinge)
		for i: int in 5:
			var leaf := Look.box(Vector3(1.05 - 0.07 * float(i), 0.025, size.z * (0.9 - 0.09 * float(i))), page,
				Vector3(sgn * (0.5 - 0.035 * float(i)), -0.012 * float(i), 0))
			leaf.rotation.z = sgn * -0.07 * float(i)
			hinge.add_child(leaf)
	var vis := AABB(Vector3(-4, -3, -4), Vector3(8, 6, 8))
	_letters = Fx.emitter({"amount": 14, "lifetime": 1.2, "local": false, "shape": "box",
		"extents": Vector3(half.x, 0.05, half.z), "dir": Vector3.DOWN, "spread": 35.0, "speed": Vector2(0.2, 0.9),
		"gravity": Vector3(0, -0.3, 0), "tex": Fx.Tex.STAR, "size": 0.14, "color": Color(2.4, 1.8, 0.8),
		"curve": "shrink", "turbulence": 0.5, "aabb": vis})
	_letters.position = Vector3(0, -half.y, 0)
	add_child(_letters)


func _process(_dt: float) -> void:
	var t: float = Game.course_time
	var a: float = sin((t * flap_rate + phase) * TAU)
	for i: int in _wings.size():
		var sgn: float = -1.0 if i == 0 else 1.0
		# up on the up-beat, drooping on the down-beat
		_wings[i].rotation.z = sgn * (a * 0.55 - 0.1)
