class_name ArmadaDeck
extends MovingPlatform
## Storm Armada: a rolling deck - a little sky-skiff (or a ship's loose deck section) riding the
## storm. It heaves up and down, rolls from side to side and pitches bow to stern on the course
## clock, so every landing on it is a moving, tilting target. Pure function of Game.course_time;
## a MovingPlatform, so the route bot can ask where it WILL be (offset_at). Positioned like
## kit.mover (at the centre of the deck's collision box). The hull, a small balloon and a stern
## propeller are built with it, so the whole boat moves as one.

## Heave amplitude (m), roll (about the local fore-aft axis) and pitch amplitudes (degrees).
@export var heave: float = 0.6
@export var roll_deg: float = 7.0
@export var pitch_deg: float = 3.0
## Horizontal drift amplitude (m, local x / z).
@export var sway: Vector3 = Vector3(0.3, 0, 0.2)
## Build the skiff around it (hull, balloon, prop); false = just a rolling plank deck.
@export var skiff: bool = true
@export var balloon_color: Color = Color(0.72, 0.28, 0.22)

var _base_basis: Basis
var _prop: Node3D


func _ready() -> void:
	sync_to_physics = false
	collision_layer = 1
	collision_mask = 0
	_origin = position
	_base_basis = basis
	var box := BoxShape3D.new()
	box.size = size
	var cs := CollisionShape3D.new()
	cs.shape = box
	add_child(cs)
	add_child(Look.platform_box(size, style))
	if skiff:
		_build_skiff()
	_pose(Game.course_time)
	reset_physics_interpolation()
	add_to_group("course_clock")
	var creak: AudioStreamPlayer3D = WorldAudio.loop("armada_hull_creak", self, -16.0, 14.0, 4.0)
	if creak != null:
		creak.pitch_scale = randf_range(0.85, 1.1)


func _w(time: float) -> float:
	return TAU * (time / maxf(period, 0.01) + phase)


func offset_at(time: float) -> Vector3:
	var w: float = _w(time)
	return Vector3(sway.x * sin(w + 0.7), heave * sin(w), sway.z * sin(w + 1.9))


## Roll and pitch (radians) at `time`.
func tilt_at(time: float) -> Vector2:
	var w: float = _w(time)
	return Vector2(deg_to_rad(pitch_deg) * sin(w + 2.4), deg_to_rad(roll_deg) * sin(w + PI * 0.5))


func snap_to_clock() -> void:
	_pose(Game.course_time)
	reset_physics_interpolation()


func _physics_process(_dt: float) -> void:
	_pose(Game.course_time)


func _pose(t: float) -> void:
	var tl: Vector2 = tilt_at(t)
	position = _origin + offset_at(t)
	basis = _base_basis * Basis.from_euler(Vector3(tl.x, 0.0, tl.y))


func _process(dt: float) -> void:
	if _prop != null:
		_prop.rotate_object_local(Vector3(0, 0, 1), dt * 14.0)


## The skiff: a clinker-built wooden hull under the deck, gunwales, a small gas bag overhead on
## four stays, and a brass propeller at the stern. Scaled to the deck (its local -Z is the bow).
func _build_skiff() -> void:
	var hx: float = size.x * 0.5
	var hz: float = size.z * 0.5
	var top: float = size.y * 0.5
	var wood: StandardMaterial3D = Look.flat(Color(0.34, 0.2, 0.11), 0.8)
	var dark: StandardMaterial3D = Look.flat(Color(0.22, 0.13, 0.08), 0.85)
	var brass: StandardMaterial3D = Look.flat(Color(0.86, 0.63, 0.3), 0.3, 0.9)
	var rope: StandardMaterial3D = Look.flat(Color(0.55, 0.45, 0.32), 0.9)
	# the hull: a tapering keel under the deck and a pointed bow
	var hull_d: float = maxf(size.x * 0.55, 1.0)
	var keel := CylinderMesh.new()
	keel.top_radius = 0.7071
	keel.bottom_radius = 0.7071 * 0.3
	keel.height = hull_d
	keel.radial_segments = 4
	keel.rings = 1
	var holder := Node3D.new()
	holder.scale = Vector3(size.x * 0.98, 1.0, size.z * 0.98)
	holder.position = Vector3(0, -top - hull_d * 0.5, 0)
	var km := Look.mesh_node(keel, wood)
	km.rotation.y = PI * 0.25
	holder.add_child(km)
	add_child(holder)
	var bow := PrismMesh.new()
	bow.size = Vector3(size.x * 0.98, 1.3, hull_d * 0.9)
	var bm := Look.mesh_node(bow, wood, Vector3(0, -top - hull_d * 0.45 + 0.02, -hz - 0.64))
	bm.rotation.x = -PI * 0.5
	add_child(bm)
	# gunwales along the sides, just under the deck edge (never above the walking surface)
	for sx: float in [-1.0, 1.0]:
		add_child(Look.box(Vector3(0.16, 0.3, size.z), dark, Vector3(sx * (hx + 0.08), top - 0.2, 0)))
		add_child(Look.box(Vector3(0.1, 0.1, size.z * 0.9), brass, Vector3(sx * (hx + 0.12), -top - 0.3, 0)))
	# the gas bag, high overhead, on four stays from the deck corners
	var bag_y: float = top + 6.5
	var bag := Look.sphere(1.0, Look.flat(balloon_color, 0.7), Vector3(0, bag_y, 0))
	bag.scale = Vector3(hx + 0.6, 1.3, hz + 1.4)
	bag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bag)
	var band := Look.cylinder(1.0, 0.12, brass, Vector3(0, bag_y, 0), -1.0, 20)
	band.scale = Vector3(hx + 0.64, 1.0, hz + 1.44)
	add_child(band)
	for cx: float in [-1.0, 1.0]:
		for cz: float in [-1.0, 1.0]:
			var a := Vector3(cx * (hx + 0.05), top - 0.1, cz * (hz - 0.2))
			var b := Vector3(cx * (hx * 0.6 + 0.3), bag_y - 1.05, cz * (hz * 0.7 + 0.5))
			add_child(_line(a, b, 0.035, rope))
	# a brass prop on a short outrigger at the stern
	_prop = Node3D.new()
	_prop.position = Vector3(0, -top - 0.4, hz + 0.9)
	for i: int in 3:
		var blade := Look.box(Vector3(0.22, 1.3, 0.05), brass, Vector3(0, 0.6, 0))
		var arm := Node3D.new()
		arm.rotation.z = TAU * float(i) / 3.0
		arm.add_child(blade)
		_prop.add_child(arm)
	_prop.add_child(Look.sphere(0.18, brass))
	add_child(_prop)
	add_child(Look.box(Vector3(0.12, 0.12, 1.0), dark, Vector3(0, -top - 0.4, hz + 0.4)))
	# a lantern hanging off the bow
	var lamp := Look.sphere(0.14, Look.flat(Color(1.0, 0.72, 0.3), 0.4, 0.0, 3.0), Vector3(0, top + 0.1, -hz - 0.3))
	add_child(lamp)


static func _line(a: Vector3, b: Vector3, r: float, mat: Material) -> MeshInstance3D:
	var d: Vector3 = b - a
	var n := Look.cylinder(r, d.length(), mat, (a + b) * 0.5, -1.0, 6)
	var up: Vector3 = d.normalized()
	var side: Vector3 = up.cross(Vector3(0.123, 0.4, 0.9)).normalized()
	n.basis = Basis(side, up, side.cross(up))
	return n
