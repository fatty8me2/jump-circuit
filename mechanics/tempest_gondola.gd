class_name TempestGondola
extends MovingPlatform
## Tempest Tower: a WINDOW-WASHER GONDOLA - the cradle the cleaners ride up and down the glass,
## hung on four cables from a davit arm far above. It climbs and drops along the facade on the
## course clock, holding at the top and the bottom (a MovingPlatform PATH with long dwells, so the
## bot can ask where it will be); its warning light blinks and the motor whines up `warn` seconds
## before it sets off. Ride it like a lift. Open at both ends, railed along the glass and the drop.

@export var warn: float = 1.0
## World height of the davit arm the four cables hang from (they stretch from the cradle up to it).
@export var davit_y: float = 30.0

var _lamp_mat: StandardMaterial3D
var _was_warn: bool = false
var _loop: AudioStreamPlayer3D
var _cables: Array[MeshInstance3D] = []
var _corners: Array[Vector3] = []


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
	_build()
	position = _origin + offset_at(Game.course_time)
	reset_physics_interpolation()
	add_to_group("course_clock")
	# SOUND: the hoist motor while the cradle moves
	_loop = WorldAudio.loop("tempest_gondola_motor", self, -16.0, 20.0, 4.0, false)
	_stretch_cables()


func _hums() -> bool:
	return false


func hold_left(time: float) -> float:
	var s: float = 0.0
	while s < period:
		if offset_at(time + s).distance_to(offset_at(time)) > 0.02:
			return s
		s += 0.05
	return period


func is_travelling_at(time: float) -> bool:
	return offset_at(time + 0.05).distance_to(offset_at(time)) > 0.001


func _process(_dt: float) -> void:
	var t: float = Game.course_time
	var moving: bool = is_travelling_at(t)
	var warning: bool = not moving and hold_left(t) < warn
	_lamp_mat.emission_energy_multiplier = (4.5 if fmod(t, 0.2) < 0.1 else 0.4) if warning else (2.0 if moving else 0.5)
	if warning and not _was_warn:
		# SOUND: the hoist motor spooling up (the tell before it moves)
		WorldAudio.at(self, "tempest_gondola_start", global_position + Vector3(0, 1.0, 0), 0.8, 28.0)
	_was_warn = warning
	if _loop != null:
		WorldAudio.set_active(_loop, moving)
	_stretch_cables()


## The cables run from the cradle's corners straight up to the davit (they shorten as it climbs).
func _stretch_cables() -> void:
	for i: int in _cables.size():
		var a: Vector3 = global_transform * _corners[i]
		var len: float = maxf(davit_y - a.y, 0.1)
		var c: MeshInstance3D = _cables[i]
		c.global_position = Vector3(a.x, a.y + len * 0.5, a.z)
		c.scale = Vector3(1.0, len, 1.0)


func _build() -> void:
	var alu: StandardMaterial3D = Look.flat(Color(0.78, 0.8, 0.84), 0.35, 0.8)
	var yellow: StandardMaterial3D = Look.flat(Color(0.95, 0.74, 0.12), 0.5, 0.3)
	var cable: StandardMaterial3D = Look.flat(Color(0.1, 0.1, 0.11), 0.4, 0.8)
	add_child(Look.platform_box(size, "mover"))
	# the cradle: a yellow kick plate round the floor, rails along both long sides (x), open ends (z)
	var hx: float = size.x * 0.5
	var hz: float = size.z * 0.5
	for sx: float in [-1.0, 1.0]:
		add_child(Look.box(Vector3(0.06, 0.25, size.z), yellow, Vector3(sx * (hx - 0.03), size.y * 0.5 + 0.12, 0)))
		add_child(Look.box(Vector3(0.05, 0.05, size.z), alu, Vector3(sx * (hx - 0.03), size.y * 0.5 + 1.05, 0)))
		add_child(Look.box(Vector3(0.05, 0.05, size.z), alu, Vector3(sx * (hx - 0.03), size.y * 0.5 + 0.6, 0)))
		for sz: float in [-1.0, 0.0, 1.0]:
			add_child(Look.box(Vector3(0.05, 1.05, 0.05), alu, Vector3(sx * (hx - 0.03), size.y * 0.5 + 0.52, sz * (hz - 0.03))))
	# hoist motors at the ends under the floor, the warning lamp on a mast at the glass side
	for sz: float in [-1.0, 1.0]:
		add_child(Look.box(Vector3(0.6, 0.45, 0.5), yellow, Vector3(0, -size.y * 0.5 - 0.22, sz * (hz - 0.4))))
	_lamp_mat = Look.flat(Color(1.0, 0.55, 0.1), 0.3, 0.0, 0.5).duplicate() as StandardMaterial3D
	add_child(Look.box(Vector3(0.05, 0.9, 0.05), alu, Vector3(-hx + 0.03, size.y * 0.5 + 1.5, 0)))
	add_child(Look.sphere(0.13, _lamp_mat, Vector3(-hx + 0.03, size.y * 0.5 + 2.0, 0)))
	# four cables up to the davit (top-level: stretched every frame from the corners to davit_y)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var c := Look.cylinder(0.02, 1.0, cable, Vector3.ZERO, -1.0, 4)
			c.top_level = true
			c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			c.extra_cull_margin = davit_y
			add_child(c)
			_cables.append(c)
			_corners.append(Vector3(sx * (hx - 0.03), size.y * 0.5 + 1.05, sz * (hz - 0.03)))
