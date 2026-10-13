class_name HyperloopPod
extends MovingPlatform
## Hyperloop: a transit POD you ride across a gap. A MovingPlatform PATH (so a rider is carried with its full
## velocity, it never teleports and the bot can read offset_at): a white ceramic sled with a glowing
## cyan mag-strip along each side, a low windshield wedge at the front, a chrome hull under the deck
## and a soft coral thruster glow at the tail. It dwells (`dwell`) at each dock so you can step on and off,
## and a faint cyan wake streams off the tail while it moves.
## Positioned like kit.mover: the node sits at the centre of the deck at its first stop (top - size.y / 2);
## `size` and `points` are in world axes, like any MovingPlatform, and `facing` (radians about Y) turns only
## the model: local -Z of the model is the way it flies. Only the deck collides.

const WHITE := Color(0.95, 0.97, 1.0)
const CYAN := Color(0.2, 0.88, 1.0)
const CORAL := Color(1.0, 0.6, 0.48)

@export var facing: float = 0.0

var _vis: Node3D
var _trail: GPUParticles3D
var _hum: AudioStreamPlayer3D
var _was_moving: bool = false


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
	# SOUND: hyperloop_pod_hum - a smooth maglev whine around the pod (loop, close range)
	_hum = WorldAudio.loop("hyperloop_pod_hum", self, -15.0, 22.0, 4.0, false)


func _hums() -> bool:
	return false


## Moving right now (between docks), as seen at `time`.
func is_moving_at(time: float) -> bool:
	return offset_at(time).distance_to(offset_at(time + 0.12)) > 0.004


## The deck in the model's own frame (-Z forward).
func _vsize() -> Vector3:
	return Vector3(size.z, size.y, size.x) if absf(sin(facing)) > 0.7 else size


func _build() -> void:
	_vis = Node3D.new()
	_vis.rotation.y = facing
	add_child(_vis)
	var s: Vector3 = _vsize()
	var white: StandardMaterial3D = Look.flat(WHITE, 0.32, 0.15)
	var steel: StandardMaterial3D = Look.flat(Color(0.62, 0.70, 0.80), 0.28, 0.7)
	var glow: StandardMaterial3D = Look.flat(CYAN, 0.3, 0.0, 2.4)
	var coral: StandardMaterial3D = Look.flat(CORAL, 0.3, 0.0, 2.2)
	# the deck slab and its cyan edge strips
	_vis.add_child(Look.box(s, white))
	for sx: float in [-1.0, 1.0]:
		var strip := Look.box(Vector3(0.12, 0.05, s.z * 0.86), glow, Vector3(sx * (s.x * 0.5 - 0.1), s.y * 0.5 + 0.01, 0))
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_vis.add_child(strip)
	# a centre stripe of chevrons' worth of light
	var mid := Look.box(Vector3(0.3, 0.03, s.z * 0.55), glow, Vector3(0, s.y * 0.5 + 0.008, 0))
	mid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vis.add_child(mid)
	# low side guards
	for sx: float in [-1.0, 1.0]:
		_vis.add_child(Look.box(Vector3(0.1, 0.36, s.z * 0.8), white, Vector3(sx * (s.x * 0.5 + 0.05), s.y * 0.5 + 0.18, s.z * 0.04)))
	# the windshield wedge at the nose: a tilted translucent cyan panel on two struts
	var nose: float = -s.z * 0.5
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.4, 0.9, 1.0, 0.35)
	glass.emission_enabled = true
	glass.emission = CYAN
	glass.emission_energy_multiplier = 0.5
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var wedge := Look.box(Vector3(s.x * 0.8, 0.9, 0.05), glass, Vector3(0, s.y * 0.5 + 0.45, nose + 0.55))
	wedge.rotation.x = deg_to_rad(-28.0)
	wedge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vis.add_child(wedge)
	for sx: float in [-1.0, 1.0]:
		_vis.add_child(Look.box(Vector3(0.08, 0.5, 0.08), steel, Vector3(sx * s.x * 0.4, s.y * 0.5 + 0.25, nose + 0.22)))
	# the stepped nose under the wedge, and the chrome hull below the deck
	_vis.add_child(Look.box(Vector3(s.x * 0.84, s.y * 0.8, 0.7), white, Vector3(0, -s.y * 0.1, nose - 0.3)))
	_vis.add_child(Look.box(Vector3(s.x * 0.5, s.y * 0.6, 0.5), white, Vector3(0, -s.y * 0.15, nose - 0.8)))
	_vis.add_child(Look.cylinder(s.x * 0.36, 0.55, steel, Vector3(0, -s.y * 0.5 - 0.27, 0), s.x * 0.1, 4))
	# the tail thruster
	var tail: float = s.z * 0.5
	_vis.add_child(Look.box(Vector3(s.x * 0.5, 0.22, 0.3), coral, Vector3(0, -0.02, tail + 0.05)))
	var lamp := OmniLight3D.new()
	lamp.light_color = CYAN
	lamp.light_energy = 0.7
	lamp.omni_range = 5.0
	lamp.shadow_enabled = false
	lamp.position = Vector3(0, s.y * 0.5 + 0.9, nose + 0.5)
	_vis.add_child(lamp)
	var vis := AABB(Vector3(-24, -6, -24), Vector3(48, 14, 48))
	_trail = Fx.emitter({"amount": 36, "lifetime": 0.9, "emitting": false, "shape": "box",
		"extents": Vector3(s.x * 0.3, 0.08, 0.12), "dir": Vector3(0, 0.1, 1.0), "spread": 14.0,
		"speed": Vector2(1.5, 3.2), "tex": Fx.Tex.STAR, "size": 0.26, "scale": Vector2(0.5, 1.1),
		"pick": PackedColorArray([Fx.hot(CYAN, 2.0), Fx.hot(WHITE, 1.8)]), "curve": "shrink",
		"fade": PackedFloat32Array([0.0, 1.0, 0.0]), "aabb": vis})
	_trail.position = Vector3(0, 0.0, tail + 0.2)
	_vis.add_child(_trail)


func _process(_dt: float) -> void:
	var moving: bool = is_moving_at(Game.course_time)
	if moving != _was_moving:
		_was_moving = moving
		_trail.emitting = moving
		if moving:
			# SOUND: hyperloop_pod_go - a rising maglev chirp as the pod leaves its dock
			WorldAudio.at(self, "hyperloop_pod_go", global_position, 0.7, 30.0)
