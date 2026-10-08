class_name OlympusChariot
extends MovingPlatform
## Sky Citadel: a WINGED CHARIOT you ride between marble islands. A MovingPlatform PATH (so a rider
## is carried with its full velocity, it never teleports, and the bot can read offset_at): a marble
## deck with a gilded rail across the front and a pair of great feathered wings that beat as it
## flies, a plume of gold light and shed feathers streaming off its tail while it moves, and a soft
## bow-wave of cloud. It pauses (`dwell`) at each dock so you can step on and off.
## Positioned like kit.mover: the node sits at the centre of the deck at its first stop (top - size.y / 2);
## `size` and `points` are in world axes, like any MovingPlatform (so the bot's local offsets work), and
## `facing` (radians about Y) turns only the model: local -Z of the model is the way it flies.
## Visual only beyond the deck: nothing but the deck collides.

const MARBLE := Color(0.95, 0.92, 0.84)
const GOLD := Color(1.0, 0.78, 0.28)
const SKY := Color(0.42, 0.72, 1.0)

## Which way the model faces (radians about Y); the deck's collision box stays in world axes.
@export var facing: float = 0.0

var _vis: Node3D
var _wing_l: Node3D
var _wing_r: Node3D
var _trail: GPUParticles3D
var _feathers: GPUParticles3D
var _bow: GPUParticles3D
var _wind: AudioStreamPlayer3D
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
	# SOUND: olympus_chariot_wind - beating wings and rushing air around the chariot (loop, close range)
	_wind = WorldAudio.loop("olympus_chariot_wind", self, -14.0, 24.0, 4.0, false)


func _hums() -> bool:
	return false


## Moving right now (between docks), as seen at `time`.
func is_moving_at(time: float) -> bool:
	return offset_at(time).distance_to(offset_at(time + 0.12)) > 0.004


func _process(_dt: float) -> void:
	var t: float = Game.course_time
	var moving: bool = is_moving_at(t)
	# the wings beat quickly in flight and slowly while it waits at a dock
	var beat: float = sin(t * (7.0 if moving else 2.2)) * (0.42 if moving else 0.14)
	if _wing_l != null:
		_wing_l.rotation.z = 0.35 + beat
		_wing_r.rotation.z = -0.35 - beat
	if moving != _was_moving:
		_was_moving = moving
		_trail.emitting = moving
		_feathers.emitting = moving
		_bow.emitting = moving
		WorldAudio.set_active(_wind, moving)
		if moving:
			# SOUND: olympus_chariot_launch - a rush of wings as the chariot leaves its dock
			WorldAudio.at(self, "olympus_chariot_launch", global_position, 0.7, 34.0)


## The deck in the model's own frame (-Z forward).
func _vsize() -> Vector3:
	return Vector3(size.z, size.y, size.x) if absf(sin(facing)) > 0.7 else size


func _build() -> void:
	_vis = Node3D.new()
	_vis.rotation.y = facing
	add_child(_vis)
	# the model is built in its own frame: -Z forward, so a quarter-turn facing swaps the deck's sides
	var s: Vector3 = _vsize()
	var marble: StandardMaterial3D = Look.flat(MARBLE, 0.45)
	var trim: StandardMaterial3D = Look.flat(GOLD, 0.35, 0.5, 0.5)
	var glow: StandardMaterial3D = Look.flat(GOLD, 0.3, 0.0, 2.4)
	# the deck: a slab with a gold lip, a pale-blue inlay and a rising front rail (not solid)
	_vis.add_child(Look.box(s, marble))
	_vis.add_child(Look.box(Vector3(s.x + 0.1, 0.1, s.z + 0.1), trim, Vector3(0, s.y * 0.5 - 0.05, 0)))
	var inlay := Look.box(Vector3(s.x * 0.5, 0.02, s.z * 0.5), Look.flat(SKY, 0.4, 0.0, 0.8), Vector3(0, s.y * 0.5 + 0.012, 0))
	inlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vis.add_child(inlay)
	var front: float = -s.z * 0.5
	for sx: float in [-1.0, 1.0]:
		_vis.add_child(Look.box(Vector3(0.1, 0.5, 0.1), trim, Vector3(sx * (s.x * 0.5 - 0.05), s.y * 0.5 + 0.25, front + 0.05)))
		_vis.add_child(Look.box(Vector3(0.08, 0.08, s.z * 0.45), trim, Vector3(sx * (s.x * 0.5 - 0.05), s.y * 0.5 + 0.5, front + s.z * 0.225)))
	_vis.add_child(Look.box(Vector3(s.x - 0.1, 0.08, 0.08), trim, Vector3(0, s.y * 0.5 + 0.5, front + 0.05)))
	# the prow: a gilded sun-disc on a short spar, where the horses would be
	_vis.add_child(Look.box(Vector3(0.12, 0.12, 0.9), trim, Vector3(0, s.y * 0.5 + 0.3, front - 0.4)))
	var disc := Look.cylinder(0.3, 0.06, glow, Vector3(0, s.y * 0.5 + 0.38, front - 0.9), -1.0, 20)
	disc.rotation.x = PI * 0.5
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vis.add_child(disc)
	# the keel under the deck: a tapered marble hull
	_vis.add_child(Look.cylinder(s.x * 0.34, 0.7, Look.flat(MARBLE.darkened(0.12), 0.6), Vector3(0, -s.y * 0.5 - 0.35, 0), s.x * 0.08, 4))
	# wings: a rack of long feathers fanned out from a shoulder bar, one per side (visual only)
	_wing_l = _make_wing(-1.0)
	_wing_r = _make_wing(1.0)
	_vis.add_child(_wing_l)
	_vis.add_child(_wing_r)
	var vis := AABB(Vector3(-24, -6, -24), Vector3(48, 14, 48))
	var tail: Vector3 = Vector3(0, 0.1, s.z * 0.5 + 0.2)
	_trail = Fx.emitter({"amount": 44, "lifetime": 1.0, "emitting": false, "shape": "box",
		"extents": Vector3(s.x * 0.35, 0.1, 0.15), "dir": Vector3(0, 0.15, 1.0), "spread": 18.0,
		"speed": Vector2(1.5, 3.0), "tex": Fx.Tex.STAR, "size": 0.3, "scale": Vector2(0.5, 1.1),
		"pick": PackedColorArray([Fx.hot(GOLD, 2.2), Fx.hot(Color(1.0, 0.9, 0.6), 2.0)]), "curve": "shrink",
		"fade": PackedFloat32Array([0.0, 1.0, 0.0]), "aabb": vis})
	_trail.position = tail
	_vis.add_child(_trail)
	_feathers = Fx.emitter({"amount": 18, "lifetime": 1.8, "emitting": false, "shape": "box",
		"extents": Vector3(s.x * 0.5 + 1.0, 0.2, 0.3), "dir": Vector3(0, -0.2, 1.0), "spread": 40.0,
		"speed": Vector2(0.5, 1.6), "gravity": Vector3(0, -0.9, 0), "tex": Fx.Tex.PETAL, "additive": false,
		"size": 0.26, "angle": Vector2(0, 360), "spin": Vector2(-200, 200), "turbulence": 0.6,
		"color": Color(1.0, 0.98, 0.92, 0.95), "fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]), "aabb": vis})
	_feathers.position = Vector3(0, 0.2, 0)
	_vis.add_child(_feathers)
	_bow = Fx.emitter({"amount": 22, "lifetime": 1.2, "emitting": false, "shape": "box",
		"extents": Vector3(s.x * 0.4, 0.15, 0.2), "dir": Vector3(0, 0.1, 1.0), "spread": 50.0,
		"speed": Vector2(0.8, 2.2), "tex": Fx.Tex.SMOKE, "additive": false, "size": 0.9, "curve": "puff",
		"angle": Vector2(0, 360), "color": Color(1.0, 0.96, 0.9, 0.5),
		"fade": PackedFloat32Array([0.0, 0.7, 0.0]), "aabb": vis})
	_bow.position = Vector3(0, -s.y * 0.5 - 0.1, front)
	_vis.add_child(_bow)


## One wing: `side` -1 (left) / +1 (right). A shoulder bar and seven long feathers fanned out and
## up from it, longest in the middle; the node pivots at the shoulder on the deck's rim.
func _make_wing(side: float) -> Node3D:
	var w := Node3D.new()
	var vs: Vector3 = _vsize()
	w.position = Vector3(side * (vs.x * 0.5 + 0.05), vs.y * 0.5 + 0.35, vs.z * 0.15)
	var white: StandardMaterial3D = Look.flat(Color(1.0, 0.98, 0.93), 0.55)
	var gold: StandardMaterial3D = Look.flat(GOLD, 0.4, 0.4, 0.4)
	w.add_child(Look.box(Vector3(0.2, 0.2, 1.3), gold, Vector3(side * 0.1, 0, 0)))
	for i: int in 7:
		var k: float = float(i) / 6.0
		var flen: float = 1.7 + 1.3 * sin(k * PI)
		var f := Look.box(Vector3(flen, 0.04, 0.22), white, Vector3(side * (flen * 0.5 + 0.15), 0.0, -0.55 + 1.1 * k))
		f.rotation.y = side * (k - 0.5) * 0.5
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		w.add_child(f)
		var tip := Look.box(Vector3(0.22, 0.045, 0.2), gold, f.position + Vector3(side * cos(f.rotation.y) * flen * 0.5, 0, -side * sin(f.rotation.y) * flen * 0.5))
		tip.rotation.y = f.rotation.y
		tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		w.add_child(tip)
	return w
