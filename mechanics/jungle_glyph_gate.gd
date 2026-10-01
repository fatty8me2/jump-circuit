class_name JungleGlyphGate
extends Node3D
## Jungle Temple: a glyph pressure plate and the stone gate it opens. Step on the plate (it sinks
## and its glyph lights jade) and the gate's slab grinds up into its lintel. It stays open while
## you stand on the plate and for `open_time` seconds after you step off; a row of jade lamps on
## the lintel goes out one by one to count the time down. Over the last `warn` seconds the lamps
## blink red and the mechanism ticks, then the slab grinds shut. It never shuts on you: while you
## stand in the doorway it holds. A respawn closes it again (reset_state).
## Positioned at the doorway's floor centre; the slab spans local X (`width`), `height` tall,
## `thick` deep along Z. `plate` is the plate's floor centre in this node's local space.

@export var width: float = 3.2
@export var height: float = 3.6
@export var thick: float = 0.9
@export var plate: Vector3 = Vector3(0, 0, 8)
@export var plate_radius: float = 1.1
@export var open_time: float = 7.0
@export var warn: float = 1.6
@export var rise_time: float = 0.7
@export var close_time: float = 0.9
## Build the jambs and lintel (false when the level builds the wall round the doorway itself).
@export var frame: bool = true

const STONE := Color(0.48, 0.48, 0.4)
const JADE := Color(0.25, 0.95, 0.65)
const RED := Color(1.0, 0.25, 0.15)
const LAMPS: int = 5

var _slab: AnimatableBody3D
var _plate_vis: Node3D
var _plate_mat: StandardMaterial3D
var _plate_area: Area3D
var _door_area: Area3D
var _lamps: Array[MeshInstance3D] = []
var _lamp_on: StandardMaterial3D
var _lamp_off: StandardMaterial3D
var _lamp_red: StandardMaterial3D
var _dust: GPUParticles3D
var _slam: GPUParticles3D
## Course time the countdown runs from (-1 = closed and idle).
var _t0: float = -1.0
var _pressed: bool = false
var _was_open: float = 0.0
var _tick: int = -1


func _ready() -> void:
	add_to_group("resettable")
	var stone: StandardMaterial3D = Look.flat(STONE, 0.9)
	var dark: StandardMaterial3D = Look.flat(STONE.darkened(0.3), 0.95)
	# the slab
	_slab = AnimatableBody3D.new()
	_slab.sync_to_physics = false
	_slab.collision_layer = 1
	_slab.collision_mask = 0
	var bs := BoxShape3D.new()
	bs.size = Vector3(width, height, thick)
	var bcs := CollisionShape3D.new()
	bcs.shape = bs
	_slab.add_child(bcs)
	_slab.add_child(Look.box(Vector3(width, height, thick), stone))
	# a carved jade glyph on both faces: a ring, a bar and two dots (the "sun-eye")
	var jade: StandardMaterial3D = Look.flat(JADE, 0.3, 0.0, 1.4)
	for s: float in [-1.0, 1.0]:
		var tm := TorusMesh.new()
		tm.inner_radius = 0.42
		tm.outer_radius = 0.55
		tm.rings = 20
		tm.ring_segments = 6
		var ring := Look.mesh_node(tm, jade, Vector3(0, 0.2, s * (thick * 0.5 + 0.01)))
		ring.rotation.x = PI * 0.5
		_slab.add_child(ring)
		_slab.add_child(Look.box(Vector3(0.12, 0.7, 0.05), jade, Vector3(0, -0.85, s * (thick * 0.5 + 0.01))))
		for dx: float in [-0.75, 0.75]:
			_slab.add_child(Look.box(Vector3(0.16, 0.16, 0.05), jade, Vector3(dx, 0.2, s * (thick * 0.5 + 0.01))))
		# carved bands
		for y: float in [-height * 0.38, height * 0.38]:
			_slab.add_child(Look.box(Vector3(width * 0.9, 0.08, 0.05), dark, Vector3(0, y, s * (thick * 0.5 + 0.01))))
	_slab.position = Vector3(0, height * 0.5, 0)
	add_child(_slab)
	if frame:
		for sx: float in [-1.0, 1.0]:
			var jamb := StaticBody3D.new()
			jamb.collision_layer = 1
			jamb.collision_mask = 0
			var js := BoxShape3D.new()
			js.size = Vector3(1.0, height * 2.0 + 1.2, thick + 0.6)
			var jcs := CollisionShape3D.new()
			jcs.shape = js
			jamb.add_child(jcs)
			jamb.add_child(Look.box(js.size, stone))
			jamb.position = Vector3(sx * (width * 0.5 + 0.5), (height * 2.0 + 1.2) * 0.5, 0)
			add_child(jamb)
		var lintel := StaticBody3D.new()
		lintel.collision_layer = 1
		lintel.collision_mask = 0
		var ls := BoxShape3D.new()
		ls.size = Vector3(width, height + 1.2, thick + 0.6)
		var lcs := CollisionShape3D.new()
		lcs.shape = ls
		lintel.add_child(lcs)
		lintel.add_child(Look.box(ls.size, dark))
		lintel.position = Vector3(0, height + 0.25 + ls.size.y * 0.5, 0)
		add_child(lintel)
	# the countdown lamps on both faces of the lintel
	_lamp_on = Look.flat(JADE, 0.3, 0.0, 2.6)
	_lamp_off = Look.flat(Color(0.12, 0.16, 0.13), 0.8)
	_lamp_red = Look.flat(RED, 0.3, 0.0, 3.0)
	for s: float in [-1.0, 1.0]:
		for i: int in LAMPS:
			var x: float = (float(i) - float(LAMPS - 1) * 0.5) * minf(0.55, width / float(LAMPS + 1))
			var l := Look.box(Vector3(0.3, 0.3, 0.06), _lamp_off, Vector3(x, height + 0.75, s * (thick * 0.5 + 0.32)))
			add_child(l)
			_lamps.append(l)
	# the plate: a round stone disc with a jade glyph, flush with the floor
	_plate_vis = Node3D.new()
	_plate_vis.position = plate
	add_child(_plate_vis)
	_plate_mat = StandardMaterial3D.new()
	_plate_mat.albedo_color = JADE.darkened(0.3)
	_plate_mat.emission_enabled = true
	_plate_mat.emission = JADE
	_plate_mat.emission_energy_multiplier = 0.5
	_plate_vis.add_child(Look.cylinder(plate_radius, 0.12, Look.flat(STONE.lightened(0.1), 0.85), Vector3(0, 0.03, 0), -1.0, 24))
	var tm2 := TorusMesh.new()
	tm2.inner_radius = plate_radius * 0.55
	tm2.outer_radius = plate_radius * 0.75
	tm2.rings = 24
	tm2.ring_segments = 6
	var glyph := Look.mesh_node(tm2, _plate_mat, Vector3(0, 0.09, 0))
	glyph.scale = Vector3(1, 0.15, 1)
	_plate_vis.add_child(glyph)
	_plate_vis.add_child(Look.cylinder(plate_radius * 0.22, 0.05, _plate_mat, Vector3(0, 0.1, 0), -1.0, 12))
	_plate_area = _area(plate + Vector3(0, 0.9, 0), Vector3(plate_radius * 1.7, 1.8, plate_radius * 1.7))
	_door_area = _area(Vector3(0, 1.0, 0), Vector3(width + 0.4, 2.0, thick + 1.4))
	var big := AABB(Vector3(-width - 2, -1, -4), Vector3(width * 2 + 4, height * 2 + 4, 8))
	_dust = Fx.emitter({"amount": 30, "lifetime": 0.9, "emitting": false, "shape": "box",
		"extents": Vector3(width * 0.5, 0.1, thick * 0.6), "dir": Vector3.DOWN, "spread": 30.0, "speed": Vector2(0.4, 1.4),
		"gravity": Vector3(0, -5, 0), "tex": Fx.Tex.SMOKE, "additive": false, "size": 0.5, "curve": "puff",
		"color": Color(0.75, 0.72, 0.6, 0.6), "fade": PackedFloat32Array([0.0, 1.0, 0.0]), "aabb": big})
	_dust.position = Vector3(0, height, 0)
	add_child(_dust)
	_slam = Fx.smoke({"amount": 26, "lifetime": 1.0, "shape": "box", "extents": Vector3(width * 0.5, 0.1, thick),
		"dir": Vector3.UP, "spread": 80.0, "speed": Vector2(1.0, 3.0), "size": 0.9, "color": Color(0.78, 0.74, 0.62, 0.6), "aabb": big})
	_slam.position = Vector3(0, 0.1, 0)
	add_child(_slam)
	_pose()


func _area(at: Vector3, size: Vector3) -> Area3D:
	var a := Area3D.new()
	a.collision_layer = 0
	a.collision_mask = 2
	a.monitorable = false
	var s := BoxShape3D.new()
	s.size = size
	var cs := CollisionShape3D.new()
	cs.shape = s
	a.add_child(cs)
	a.position = at
	add_child(a)
	return a


func reset_state() -> void:
	_t0 = -1.0
	_pressed = false
	_was_open = 0.0
	_pose()
	_slab.reset_physics_interpolation()


## Seconds the gate stays fully open from now before it starts to shut (INF while the plate is
## held, -1 while closed and idle).
func open_left() -> float:
	if _t0 < 0.0:
		return -1.0
	if _pressed:
		return INF
	return open_time - (Game.course_time - _t0)


## 0 = shut, 1 = fully open.
func openness() -> float:
	if _t0 < 0.0:
		return 0.0
	var e: float = Game.course_time - _t0
	if _pressed or e < open_time:
		return clampf(_was_open, 0.0, 1.0)
	return clampf(_was_open * (1.0 - (e - open_time) / close_time), 0.0, 1.0)


func _player_in(a: Area3D) -> bool:
	for b: Node3D in a.get_overlapping_bodies():
		if b is Player:
			return true
	return false


func _physics_process(dt: float) -> void:
	var now: float = Game.course_time
	var on: bool = _player_in(_plate_area)
	if on and not _pressed:
		if _t0 < 0.0 or openness() < 0.99:
			WorldAudio.at(self, "jungle_gate_open", global_position + Vector3(0, height, 0), 1.0, 45.0)
		WorldAudio.at(self, "jungle_plate_click", global_transform * plate, 0.8, 30.0)
	var cur: float = openness()
	_pressed = on
	if on:
		# pressed again while it shuts: it grinds back up from where it is
		_was_open = cur
		_t0 = now
	if _t0 >= 0.0:
		var e: float = now - _t0
		# rising: the slab grinds up at a steady rate (a re-press while closing reverses it)
		if on or e < open_time:
			_was_open = minf(1.0, _was_open + dt / rise_time)
		elif _player_in(_door_area) and e < open_time + close_time:
			# never shut on someone standing in the doorway: hold the countdown
			_t0 += dt
		elif e >= open_time + close_time:
			_t0 = -1.0
			_was_open = 0.0
			_slam.restart()
			WorldAudio.at(self, "jungle_gate_close", global_position + Vector3(0, 0.5, 0), 1.0, 45.0)
	_pose()


func _pose() -> void:
	var k: float = openness()
	_slab.position = Vector3(0, height * 0.5 + k * (height + 0.15), 0)
	_dust.emitting = _t0 >= 0.0 and ((k > 0.02 and k < 0.98))
	_plate_vis.position = plate - Vector3(0, 0.06 if _pressed else 0.0, 0)
	_plate_mat.emission_energy_multiplier = 3.0 if _pressed else (1.6 if _t0 >= 0.0 else 0.5)
	# the countdown: lamps go out one by one; red blinking through the warning
	var left: float = open_left()
	var lit: int = 0
	var red: bool = false
	if _t0 >= 0.0:
		if left == INF:
			lit = LAMPS
		else:
			lit = clampi(int(ceil(left / open_time * float(LAMPS))), 0, LAMPS)
			if left < warn:
				red = fmod(Game.course_time * 4.0, 1.0) < 0.6
				var tk: int = int(floor(left / 0.4))
				if tk != _tick and left > 0.0:
					_tick = tk
					WorldAudio.at(self, "jungle_gate_tick", global_position + Vector3(0, height, 0), 0.7, 35.0)
	for i: int in _lamps.size():
		var j: int = i % LAMPS
		if red:
			_lamps[i].material_override = _lamp_red if j < maxi(lit, 1) else _lamp_off
		else:
			_lamps[i].material_override = _lamp_on if j < lit else _lamp_off
