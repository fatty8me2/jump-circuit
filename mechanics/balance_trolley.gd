class_name BalanceTrolley
extends MovingPlatform
## Balance Works crane cargo: a shipping container hung from a crane trolley. It rides
## back and forth along `points` exactly like a MovingPlatform (pure function of
## Game.course_time, pausing `dwell` at each end), but looks like a crate on a hook:
## corrugated walls, slings up to a hook block and a cable to the trolley overhead,
## which throws sparks while it runs. Local X is the container's long axis.
## Subclasses add the move it allows: BalanceHookCargo (mantle onto it),
## BalanceRunContainer (wall-run along it).

@export var crate_color: Color = Color(0.20, 0.52, 0.56)
## Height of the trolley above the container top (the cable length).
@export var cable_height: float = 7.0

## Visual flavour, set by the subclass.
var ledge_lip: bool = false
var run_lines: bool = false

var _sparks: GPUParticles3D


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
	_build_look()
	position = _origin + offset_at(Game.course_time)
	reset_physics_interpolation()
	add_to_group("course_clock")


func _build_look() -> void:
	var hx: float = size.x * 0.5
	var hy: float = size.y * 0.5
	var hz: float = size.z * 0.5
	add_child(Look.box(size, Look.flat(crate_color, 0.75, 0.15)))
	# walkable roof reads like every other floor in the game
	add_child(Look.box(Vector3(size.x - 0.12, 0.08, size.z - 0.12), Look.platform_material(Vector3(size.x, 0.08, size.z) * 0.5, "alt"), Vector3(0, hy + 0.02, 0)))
	# corrugation ribs on the long faces, corner posts, end doors
	var rib: StandardMaterial3D = Look.flat(crate_color.darkened(0.25), 0.7, 0.2)
	var frame: StandardMaterial3D = Look.flat(crate_color.lightened(0.35), 0.5, 0.4)
	var n: int = maxi(int(size.x / 0.55), 2)
	if not run_lines:
		for i: int in n:
			var x: float = -hx + (float(i) + 0.5) * size.x / float(n)
			for sz: float in [-1.0, 1.0]:
				add_child(Look.box(Vector3(0.12, size.y - 0.3, 0.05), rib, Vector3(x, 0, sz * (hz + 0.02))))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			add_child(Look.box(Vector3(0.18, size.y + 0.02, 0.18), frame, Vector3(sx * (hx - 0.06), 0, sz * (hz - 0.06))))
		add_child(Look.box(Vector3(0.05, size.y - 0.4, size.z - 0.5), rib, Vector3(sx * (hx + 0.02), 0, 0)))
	if ledge_lip:
		var lip: StandardMaterial3D = Look.flat(LedgeBlock.LIP_COLOR, 0.35, 0.2, 1.6)
		for sx: float in [-1.0, 1.0]:
			add_child(Look.box(Vector3(0.08, 0.16, size.z + 0.16), lip, Vector3(sx * (hx + 0.04), hy - 0.09, 0)))
		for sz: float in [-1.0, 1.0]:
			add_child(Look.box(Vector3(size.x + 0.16, 0.16, 0.08), lip, Vector3(0, hy - 0.09, sz * (hz + 0.04))))
		var rung: StandardMaterial3D = Look.flat(LedgeBlock.LIP_COLOR.darkened(0.25), 0.5, 0.3, 0.5)
		var rh: float = minf(1.2, size.y * 0.5)
		for face: int in 4:
			var along_x: bool = face < 2
			var span: float = size.x if along_x else size.z
			var k: int = maxi(int(span / 1.2), 1)
			for i: int in k:
				var u: float = -span * 0.5 + (float(i) + 0.5) * span / float(k)
				var s: float = -1.0 if face % 2 == 0 else 1.0
				var pos := Vector3(u, hy - 0.2 - rh * 0.5, s * (hz + 0.05)) if along_x else Vector3(s * (hx + 0.05), hy - 0.2 - rh * 0.5, u)
				add_child(Look.box(Vector3(0.1, rh, 0.06) if along_x else Vector3(0.06, rh, 0.1), rung, pos))
	if run_lines:
		# the wall-run panel's unmistakable dress: dark face, cyan run lines and chevrons
		var dark: StandardMaterial3D = Look.flat(Color(0.12, 0.14, 0.2), 0.45, 0.3)
		var glow: StandardMaterial3D = Look.flat(WallRunPanel.RUN_COLOR, 0.3, 0.0, 2.4)
		for sz: float in [-1.0, 1.0]:
			var z: float = sz * (hz + 0.03)
			add_child(Look.box(Vector3(size.x - 0.4, size.y - 0.3, 0.03), dark, Vector3(0, 0, z)))
			for h: float in [0.3, 0.68]:
				add_child(Look.box(Vector3(size.x - 0.6, 0.09, 0.05), glow, Vector3(0, -hy + size.y * h, z + sz * 0.01)))
			var k2: int = maxi(int(size.x / 3.0), 1)
			for i: int in k2:
				var x2: float = -hx + (float(i) + 0.5) * size.x / float(k2)
				var dir: float = -1.0 if x2 < 0.0 else 1.0
				for kk: float in [-1.0, 1.0]:
					var bar := Look.box(Vector3(0.6, 0.08, 0.05), glow, Vector3(x2, kk * 0.17, z + sz * 0.01))
					bar.rotation.z = -kk * dir * 0.6
					add_child(bar)
	# hook, slings, cable and trolley (visual only)
	var steel: StandardMaterial3D = Look.flat(Color(0.14, 0.15, 0.18), 0.5, 0.6)
	var hook_y: float = hy + 2.4
	add_child(Look.box(Vector3(0.7, 0.55, 0.5), Look.flat(Color(0.98, 0.78, 0.25), 0.4, 0.3), Vector3(0, hook_y, 0)))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_rod(Vector3(0, hook_y - 0.25, 0), Vector3(sx * (hx - 0.1), hy, sz * (hz - 0.1)), 0.03, steel)
	_rod(Vector3(0, hook_y + 0.25, 0), Vector3(0, hy + cable_height, 0), 0.05, steel)
	var trolley := Look.box(Vector3(1.2, 0.5, 1.0), Look.flat(Color(0.92, 0.94, 0.92), 0.5, 0.4), Vector3(0, hy + cable_height + 0.25, 0))
	add_child(trolley)
	_sparks = BalanceFx.sparks(Color(1.0, 0.75, 0.3), 14, 2.6, 0.6, Vector3(0, -1, 0), 70.0)
	_sparks.position = Vector3(0, hy + cable_height + 0.55, 0)
	_sparks.emitting = false
	add_child(_sparks)


func _rod(a: Vector3, b: Vector3, r: float, mat: StandardMaterial3D) -> void:
	var d: Vector3 = b - a
	var rod := Look.cylinder(r, d.length(), mat, (a + b) * 0.5, -1.0, 6)
	var up: Vector3 = d.normalized()
	var side: Vector3 = up.cross(Vector3(0.3, 0.1, 0.9)).normalized()
	rod.basis = Basis(side, up, side.cross(up))
	add_child(rod)


## Speed (m/s) the trolley runs at `time`.
func speed_at(time: float) -> float:
	return (offset_at(time + 0.05) - offset_at(time)).length() / 0.05


func _physics_process(_dt: float) -> void:
	var t: float = Game.course_time
	position = _origin + offset_at(t)
	var run: bool = speed_at(t) > 1.2
	if _sparks.emitting != run:
		_sparks.emitting = run
