class_name ManorGaze
extends Node3D
## Phantom Manor: a portrait's gaze. An ancestor's portrait hangs on the wall; on a fixed rhythm
## (Game.course_time) its eyes snap open and a searing green gaze beam sweeps back and forth
## across the floor in front of it. Touch the beam while the eyes are open and you are sent
## back to the checkpoint. The eyes glow and the pupils swell for `warn` s before they open,
## and while shut the portrait is harmless - that is when you cross.
##
## Placed at the portrait's centre, facing its local -Z (out of the wall). The beam is a thin
## vertical sheet from the eyes down to the floor `reach` metres out, pivoting about the
## vertical axis through the eyes by +-`sweep_deg`, `sweeps` times per open spell.

@export var period: float = 6.0
@export var on_fraction: float = 0.4
@export var phase: float = 0.0
@export var warn: float = 1.0
@export var reach: float = 7.0
## Height of the eyes above the floor the beam lands on.
@export var eye_height: float = 3.2
@export var sweep_deg: float = 38.0
@export var sweeps: float = 1.0
@export var frame_size: Vector2 = Vector2(2.0, 2.6)

const BEAM: Color = Color(0.55, 1.0, 0.5)

var _pivot: Node3D
var _beam: MeshInstance3D
var _beam_mat: ShaderMaterial
var _area: Area3D
var _eye_mat: StandardMaterial3D
var _eyes: Array[MeshInstance3D] = []
var _spot: GPUParticles3D
var _was_on: bool = false
var _hum: AudioStreamPlayer3D


func _ready() -> void:
	_build_portrait()
	_pivot = Node3D.new()
	_pivot.position = Vector3(0, 0.35, -0.12)
	add_child(_pivot)
	# the beam: a quad from the eyes down to the floor, lying in the pivot's local YZ plane
	var drop: float = eye_height
	var length: float = sqrt(reach * reach + drop * drop)
	var q := QuadMesh.new()
	q.size = Vector2(length, 0.9)
	_beam_mat = ShaderMaterial.new()
	_beam_mat.shader = preload("res://visual/manor_beam.gdshader")
	_beam = Look.mesh_node(q, _beam_mat)
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tilt: float = atan2(drop, reach)
	var holder := Node3D.new()
	holder.rotation = Vector3(-tilt, 0, 0)
	_pivot.add_child(holder)
	_beam.position = Vector3(0, 0, -length * 0.5)
	_beam.rotation = Vector3(0, PI * 0.5, 0)
	holder.add_child(_beam)
	# a second quad crossed with the first (lying flat), so the beam reads from every side
	var beam2 := Look.mesh_node(q, _beam_mat, Vector3(0, 0, -length * 0.5))
	beam2.rotation = Vector3(PI * 0.5, PI * 0.5, 0)
	beam2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(beam2)
	# the kill volume: a slab along the beam, from knee height up, the full sweep of the floor
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 2
	_area.monitorable = false
	var box := BoxShape3D.new()
	box.size = Vector3(0.5, 0.5, length)
	var cs := CollisionShape3D.new()
	cs.shape = box
	_area.add_child(cs)
	_area.position = Vector3(0, 0, -length * 0.5)
	holder.add_child(_area)
	# a column of sparks where the gaze burns the floor
	_spot = Fx.emitter({"amount": 26, "lifetime": 0.5, "shape": "sphere", "radius": 0.3, "dir": Vector3.UP,
		"spread": 40.0, "speed": Vector2(1.0, 3.0), "gravity": Vector3(0, -3.0, 0), "tex": Fx.Tex.STAR,
		"size": 0.18, "color": Fx.hot(BEAM, 2.2), "curve": "shrink", "emitting": false,
		"aabb": AABB(Vector3(-reach - 3, -eye_height - 3, -reach - 3), Vector3(reach * 2 + 6, eye_height + 8, reach * 2 + 6))})
	_spot.position = Vector3(0, -drop, -reach)
	_pivot.add_child(_spot)
	_hum = WorldAudio.loop("manor_gaze_hum", self, -10.0, 22.0, 5.0, false)
	_apply(Game.course_time)
	add_to_group("course_clock")


func _build_portrait() -> void:
	var gold: StandardMaterial3D = Look.flat(Color(0.62, 0.48, 0.22), 0.35, 0.85)
	var dark: StandardMaterial3D = Look.flat(Color(0.05, 0.035, 0.05), 0.9)
	var w: float = frame_size.x
	var h: float = frame_size.y
	# the carved frame and the dark canvas
	add_child(Look.box(Vector3(w + 0.5, h + 0.5, 0.18), gold, Vector3(0, 0, 0.05)))
	add_child(Look.box(Vector3(w, h, 0.1), dark, Vector3(0, 0, -0.06)))
	for sx: float in [-1.0, 1.0]:
		add_child(Look.sphere(0.14, gold, Vector3(sx * (w * 0.5 + 0.25), h * 0.5 + 0.25, -0.05)))
		add_child(Look.sphere(0.14, gold, Vector3(sx * (w * 0.5 + 0.25), -h * 0.5 - 0.25, -0.05)))
	# the sitter: a pale, long face above a high black collar
	var skin: StandardMaterial3D = Look.flat(Color(0.62, 0.58, 0.55), 0.8)
	var coat: StandardMaterial3D = Look.flat(Color(0.1, 0.06, 0.12), 0.8)
	var head := Look.sphere(0.42, skin, Vector3(0, 0.35, -0.13))
	head.scale = Vector3(0.85, 1.15, 0.35)
	add_child(head)
	var body := Look.sphere(0.8, coat, Vector3(0, -0.75, -0.13))
	body.scale = Vector3(1.0, 0.8, 0.3)
	add_child(body)
	add_child(Look.box(Vector3(0.5, 0.25, 0.06), Look.flat(Color(0.85, 0.83, 0.78), 0.7), Vector3(0, -0.12, -0.2)))
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_eye_mat.albedo_color = Color(0.1, 0.1, 0.1)
	for sx: float in [-1.0, 1.0]:
		var eye := Look.sphere(0.065, _eye_mat, Vector3(sx * 0.14, 0.42, -0.26))
		eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(eye)
		_eyes.append(eye)


func _u(time: float) -> float:
	return fposmod(time / period + phase, 1.0)


## The eyes are open (the beam is deadly).
func is_on_at(time: float) -> bool:
	return _u(time) < on_fraction


## The eyes stay shut over the whole window [time + a, time + b].
func is_shut_for(time: float, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if is_on_at(time + s):
			return false
		s += 0.04
	return not is_on_at(time + b)


func time_until_on(time: float) -> float:
	var u: float = _u(time)
	return 0.0 if u < on_fraction else (1.0 - u) * period


## Beam yaw (radians, about the portrait's up axis) at `time`.
func angle_at(time: float) -> float:
	var u: float = _u(time)
	if u >= on_fraction:
		return 0.0
	var k: float = u / on_fraction
	return deg_to_rad(sweep_deg) * sin(TAU * sweeps * k)


func _apply(t: float) -> void:
	var on: bool = is_on_at(t)
	_pivot.rotation.y = angle_at(t)
	_beam.get_parent().visible = on
	# the eyes: dark; smouldering and swelling during the warning; blazing while open
	var until: float = time_until_on(t)
	var k: float = 0.0
	if on:
		k = 1.0
	elif until < warn:
		k = 0.25 + 0.5 * (1.0 - until / warn) * (0.7 + 0.3 * sin(t * 30.0))
	_eye_mat.albedo_color = Color(0.08, 0.08, 0.08).lerp(Fx.hot(BEAM, 2.4), k)
	var s: float = 1.0 + 0.8 * k
	for e: MeshInstance3D in _eyes:
		e.scale = Vector3(s, s, s)
	if on:
		# the beam brightens as it opens and fades as it shuts
		var u: float = _u(t) / on_fraction
		var a: float = clampf(minf(u * 8.0, (1.0 - u) * 8.0), 0.0, 1.0)
		_beam_mat.set_shader_parameter("strength", 0.35 + 0.65 * a)


## restart_run() winds the clock back: pose for the new time at once.
func snap_to_clock() -> void:
	_apply(Game.course_time)
	_pivot.reset_physics_interpolation()


func _process(_dt: float) -> void:
	var t: float = Game.course_time
	_apply(t)
	var on: bool = is_on_at(t)
	if on != _was_on:
		_was_on = on
		_spot.emitting = on
		if on:
			WorldAudio.at(self, "manor_gaze_open", global_position, 0.9, 36.0)
		WorldAudio.set_active(_hum, on)


func _physics_process(_dt: float) -> void:
	var t: float = Game.course_time
	_pivot.rotation.y = angle_at(t)
	if not is_on_at(t):
		return
	for body: Node3D in _area.get_overlapping_bodies():
		if body is Player:
			var n: Node = self
			while n != null and not n.has_method("fail"):
				n = n.get_parent()
			if n != null:
				n.call_deferred("fail", "hazard")
			return
