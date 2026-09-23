class_name WallRunPanel
extends StaticBody3D
## A wall the player can run along. Jump at it moving along its face (at least
## wall_run_min_speed along it) and you latch on: a slow arc for up to
## wall_run_time, then jump to kick off. Only these panels allow it - ordinary
## walls never do - so they wear one unmistakable look in every level: a dark
## slab with glowing cyan run lines and chevrons on both faces.
## Local X runs along the wall, Y is up, Z is its thickness.

const RUN_COLOR: Color = Color(0.3, 0.95, 1.0)

@export var size: Vector3 = Vector3(12, 4, 0.6)


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	add_child(cs)
	add_child(Look.box(size, Look.flat(Color(0.12, 0.14, 0.2), 0.45, 0.3)))
	var glow: StandardMaterial3D = Look.flat(RUN_COLOR, 0.3, 0.0, 2.4)
	var frame: StandardMaterial3D = Look.flat(Look.c("metal"), 0.4, 0.6)
	for side: float in [-1.0, 1.0]:
		var z: float = side * (size.z * 0.5 + 0.02)
		# two run lines along the length
		for h: float in [0.3, 0.68]:
			add_child(Look.box(Vector3(size.x - 0.4, 0.09, 0.04), glow, Vector3(0, -size.y * 0.5 + size.y * h, z)))
		# chevrons pointing both ways from the middle: "run along me"
		var n: int = maxi(int(size.x / 3.0), 1)
		for i: int in n:
			var x: float = -size.x * 0.5 + (float(i) + 0.5) * size.x / float(n)
			var dir: float = -1.0 if x < 0.0 else 1.0
			for k: float in [-1.0, 1.0]:
				var bar := Look.box(Vector3(0.6, 0.08, 0.04), glow, Vector3(x, -size.y * 0.01 + k * 0.17, z))
				bar.rotation.z = -k * dir * 0.6
				add_child(bar)
	# capped ends so the slab reads as a built thing, not a floating plane
	for ex: float in [-1.0, 1.0]:
		add_child(Look.box(Vector3(0.25, size.y + 0.2, size.z + 0.2), frame, Vector3(ex * (size.x * 0.5 + 0.12), 0, 0)))


func is_wall_run() -> bool:
	return true
