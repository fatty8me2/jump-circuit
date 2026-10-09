class_name SiegeTrebuchet
extends Node3D
## Castle Siege: a TREBUCHET (scenery that works). A timber A-frame carries a long throwing arm on an
## axle; the short end holds a counterweight box, the long end a sling. It fires toward local -Z.
## It is purely visual and driven by something that really happens:
##  * `link_boulder(b)`: the arm lets go when the SiegeBoulder `b` launches its stone (so the boulder
##    seen in the sky comes from a trebuchet that is seen to throw it), then winds back;
##  * `link_barrel(b)`: the arm swings when the LaunchBarrel `b` fires its rider (the finale: the
##    sling is your ride) and winds back afterwards;
##  * neither: it throws on its own `period`.
## Nothing here touches gameplay: hazards and launches are separate nodes with their own timing.

@export var arm_length: float = 8.0
@export var period: float = 7.0
@export var phase: float = 0.0
@export var with_stone: bool = true

var _boulder: SiegeBoulder
var _barrel: LaunchBarrel
var _arm: Node3D
var _stone: Node3D
var _swing: float = 0.0
var _was_loaded: bool = false
var _creaked: bool = false


func link_boulder(b: SiegeBoulder) -> void:
	_boulder = b


func link_barrel(b: LaunchBarrel) -> void:
	_barrel = b


func _ready() -> void:
	_build()
	_pose(_target(Game.course_time))
	_swing = _target(Game.course_time)


## 0 = cocked (arm back), 1 = thrown (arm forward, over the top). Eased in _process.
func _target(t: float) -> float:
	if _boulder != null:
		var until: float = _boulder.time_until_impact(t)
		var since: float = _boulder.flight - until
		if until <= 0.0:
			return 0.0
		if since < 0.0:
			return 0.0
		# thrown at launch (0..0.9 s later), then winds back over the next ~2 s
		if since < 0.9:
			return clampf(since / 0.9, 0.0, 1.0)
		return clampf(1.0 - (since - 0.9) / 2.2, 0.0, 1.0) if since < 3.1 else 0.0
	if _barrel != null:
		if _barrel.is_loaded():
			return clampf(1.0 - _barrel.time_to_fire() / 0.55, 0.0, 1.0)
		return _swing
	var u: float = fposmod(t / period + phase, 1.0)
	if u < 0.1:
		return u / 0.1
	return clampf(1.0 - (u - 0.1) / 0.35, 0.0, 1.0)


func _process(dt: float) -> void:
	var tgt: float = _target(Game.course_time)
	if _barrel != null and not _barrel.is_loaded():
		# after the shot the arm winds back slowly
		if _was_loaded:
			_was_loaded = false
			_swing = 1.0
			# SOUND: siege_trebuchet_throw - the great arm whipping over the top and the sling letting go
			WorldAudio.at(self, "siege_trebuchet_throw", global_position + Vector3(0, 6.0, 0), 1.0, 70.0)
		_swing = maxf(_swing - dt / 3.0, 0.0)
		tgt = _swing
	elif _barrel != null:
		if not _was_loaded:
			_was_loaded = true
			_creaked = false
		if not _creaked and _barrel.time_to_fire() < 0.9:
			_creaked = true
			# SOUND: siege_trebuchet_wind - the winch ratchets and the arm creaks as it is released (the tell)
			WorldAudio.at(self, "siege_trebuchet_wind", global_position + Vector3(0, 4.0, 0), 0.9, 60.0)
		_swing = tgt
	else:
		_swing = lerpf(_swing, tgt, clampf(dt * 14.0, 0.0, 1.0))
		tgt = _swing
	_pose(tgt)


func _pose(k: float) -> void:
	# cocked: the long arm points back and down (+65 deg); thrown: over the top and forward (-165 deg)
	var e: float = k * k * (3.0 - 2.0 * k)
	_arm.rotation.x = deg_to_rad(lerpf(65.0, -165.0, e))
	if _stone != null:
		_stone.visible = k < 0.62


func _build() -> void:
	var wood: StandardMaterial3D = Look.flat(Color(0.34, 0.23, 0.15), 0.9)
	var dark: StandardMaterial3D = Look.flat(Color(0.2, 0.14, 0.1), 0.9)
	var iron: StandardMaterial3D = Look.flat(Color(0.16, 0.16, 0.18), 0.45, 0.7)
	var rope: StandardMaterial3D = Look.flat(Color(0.62, 0.5, 0.32), 0.9)
	var h: float = arm_length * 0.5
	# the base sills and two A-frames either side of the axle
	for sx: float in [-1.0, 1.0]:
		add_child(Look.box(Vector3(0.45, 0.45, arm_length * 1.5), dark, Vector3(sx * 2.2, 0.22, 0)))
		for sz: float in [-1.0, 1.0]:
			var leg := Look.box(Vector3(0.4, h * 1.35, 0.4), wood, Vector3(sx * 1.9, h * 0.62, sz * arm_length * 0.28))
			leg.rotation.x = sz * 0.35
			add_child(leg)
	add_child(Look.box(Vector3(4.6, 0.4, 0.4), dark, Vector3(0, h * 1.18, 0)))
	var axle := Look.cylinder(0.2, 4.8, iron, Vector3(0, h * 1.18, 0), -1.0, 8)
	axle.rotation.z = PI * 0.5
	add_child(axle)
	# the throwing arm (its pivot is the axle): long beam to +Z, short beam to -Z, counterweight, sling
	_arm = Node3D.new()
	_arm.position = Vector3(0, h * 1.18, 0)
	add_child(_arm)
	_arm.add_child(Look.box(Vector3(0.38, 0.5, arm_length), wood, Vector3(0, 0, arm_length * 0.5 - 1.2)))
	_arm.add_child(Look.box(Vector3(0.38, 0.5, 1.6), dark, Vector3(0, 0, -1.0)))
	var cw := Node3D.new()
	cw.position = Vector3(0, -0.2, -1.9)
	_arm.add_child(cw)
	cw.add_child(Look.box(Vector3(1.8, 1.9, 1.5), dark, Vector3(0, -0.95, 0)))
	cw.add_child(Look.box(Vector3(1.9, 0.18, 1.6), iron, Vector3(0, -0.2, 0)))
	cw.add_child(Look.box(Vector3(1.9, 0.18, 1.6), iron, Vector3(0, -1.7, 0)))
	for sx2: float in [-1.0, 1.0]:
		cw.add_child(Look.box(Vector3(0.1, 1.6, 0.1), rope, Vector3(sx2 * 0.5, 0.5, 0)))
	# the sling: two ropes and a pouch hanging off the long end
	var tip: Vector3 = Vector3(0, 0, arm_length - 1.2)
	for sx3: float in [-1.0, 1.0]:
		var line := Look.cylinder(0.03, 2.6, rope, tip + Vector3(sx3 * 0.18, -1.3, 0), -1.0, 4)
		_arm.add_child(line)
	_arm.add_child(Look.box(Vector3(0.7, 0.14, 0.7), dark, tip + Vector3(0, -2.65, 0)))
	if with_stone:
		_stone = Node3D.new()
		_stone.position = tip + Vector3(0, -2.95, 0)
		_arm.add_child(_stone)
		_stone.add_child(Look.sphere(0.5, Look.flat(Color(0.34, 0.32, 0.31), 0.95)))
	# a winch drum at the back and a bundle of stones
	var drum := Look.cylinder(0.4, 1.8, wood, Vector3(0, 0.7, arm_length * 0.5), -1.0, 10)
	drum.rotation.z = PI * 0.5
	add_child(drum)
	for i: int in 4:
		add_child(Look.sphere(0.38, Look.flat(Color(0.36, 0.34, 0.32), 0.95), Vector3(3.2 + 0.55 * float(i % 2), 0.38, arm_length * 0.2 + 0.7 * float(i))))
