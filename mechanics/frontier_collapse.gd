class_name FrontierCollapse
extends Node3D
## Wild West Heist set piece: THE TRESTLE GIVES WAY. A run of short lumber flats rides over a stretch
## of the trestle that is coming apart. On a fixed rhythm (Game.course_time) the collapse starts behind
## the run - a rumble, dust boiling up from under the rearmost flat, the timbers groaning - then a
## front of splintering trestle chases forward under the flats at `wave_speed`. Each flat it reaches
## shudders for `shake` seconds, then tips back and drops into the gorge with a crash of timbers.
## Outrun it. When the whole run has gone the cloud settles and the flats are hauled back up out of
## the dust before the next collapse.
## The node sits at the rear end of the run (floor height of the rear flat); the run goes toward -Z.
## Sections are added by the level (add_section) before the node enters the tree.
##   cycle (s into the period): 0 rumble .. warn -> front leaves z = 0 .. each section breaks as the
##   front reaches it .. all fallen -> settle .. period - rise -> hauled back up .. period

@export var period: float = 15.0
@export var phase: float = 0.0
## Seconds of rumble before the front starts moving.
@export var warn: float = 1.4
## How fast the front chases (m/s along -Z).
@export var wave_speed: float = 5.0
## Seconds a section shudders before it breaks.
@export var shake: float = 0.7
## Seconds the sections take to come back up at the end of the cycle.
@export var rise: float = 1.4

const FALL_TIME: float = 1.6

## {"body": AnimatableBody3D, "home": Vector3 (local), "size": Vector3, "break": float (s into cycle)}
var _sections: Array[Dictionary] = []
var _pending: Array[Dictionary] = []
var _rumble: AudioStreamPlayer3D
var _front_dust: GPUParticles3D
var _front_node: Node3D
var _was_broken: Array[bool] = []
var _was_rumbling: bool = false
var _was_rising: bool = false


## Adds a section (a walkable slab) whose top centre is at local `top` with `size`. Returns its body
## so the level can dress it (children move and fall with it).
func add_section(top: Vector3, size: Vector3, style: String = "alt") -> AnimatableBody3D:
	var b := AnimatableBody3D.new()
	b.sync_to_physics = false
	b.collision_layer = 1
	b.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, -size.y * 0.5, 0)
	b.add_child(cs)
	var vis := Look.platform_box(size, style)
	vis.position = Vector3(0, -size.y * 0.5, 0)
	b.add_child(vis)
	b.position = top
	_pending.append({"body": b, "home": top, "size": size, "shape": cs})
	return b


func _ready() -> void:
	for d: Dictionary in _pending:
		var top: Vector3 = d["home"]
		var size: Vector3 = d["size"]
		# a section breaks once the front has passed under a third of it
		d["break"] = warn + (-(top.z + size.z * 0.5) + size.z * 0.33) / wave_speed
		add_child(d["body"] as Node3D)
		var fx: Array[GPUParticles3D] = _section_fx(top, size)
		d["dust"] = fx[0]
		d["chunks"] = fx[1]
		_sections.append(d)
		_was_broken.append(false)
	_pending.clear()
	_build_front()
	_rumble = WorldAudio.loop("frontier_collapse_rumble", self, -4.0, 70.0, 10.0, false)
	add_to_group("course_clock")
	snap_to_clock()


func snap_to_clock() -> void:
	var t: float = Game.course_time
	for i: int in _sections.size():
		_was_broken[i] = _broken(i, t)
	_was_rumbling = is_rumbling_at(t)
	_apply(t)
	for d: Dictionary in _sections:
		(d["body"] as Node3D).reset_physics_interpolation()


# ---- the rhythm (pure functions of the course clock) ------------------------------------------------

func _s(time: float) -> float:
	return fposmod(time / period + phase, 1.0) * period


## Seconds into the cycle at which the last section has gone.
func last_break() -> float:
	var m: float = 0.0
	for d: Dictionary in _sections:
		m = maxf(m, float(d["break"]))
	return m


func _broken(i: int, time: float) -> bool:
	var s: float = _s(time)
	return s >= float(_sections[i]["break"]) and s < period - 0.05


## Is section `i` solid (standable) at `time`?
func solid_at(i: int, time: float) -> bool:
	return not _broken(i, time)


## The collapse is under way (rumble, front moving or sections falling).
func is_rumbling_at(time: float) -> bool:
	var s: float = _s(time)
	return s < last_break() + FALL_TIME


## Where the front is at `time` (local z; 0 at the rear end), or 1.0 when it is not moving.
func front_z(time: float) -> float:
	var s: float = _s(time)
	if s < warn or s > last_break() + 0.5:
		return 1.0
	return -(s - warn) * wave_speed


## Every section stands whole at `time`.
func all_solid_at(time: float) -> bool:
	var s: float = _s(time)
	return s >= period - 0.05 or s < _first_break()


func _first_break() -> float:
	var m: float = INF
	for d: Dictionary in _sections:
		m = minf(m, float(d["break"]))
	return m


## Bot helper: true while a run started now has the whole cycle ahead of it (all sections whole, and
## the front not yet launched more than `late` seconds ago).
func run_open(time: float, late: float = 0.2) -> bool:
	var s: float = _s(time)
	return s >= period - 0.05 or s <= warn + late


# ---- motion ----------------------------------------------------------------------------------------

## Pose of section `i` at `time`: offset from home and its tip (radians about X).
func _pose_of(i: int, time: float) -> Array:
	var d: Dictionary = _sections[i]
	var s: float = _s(time)
	var br: float = float(d["break"])
	var size: Vector3 = d["size"]
	if s < br - shake:
		return [Vector3.ZERO, 0.0]
	if s < br:
		# shudder: small fast jitters, growing
		var k: float = (s - (br - shake)) / shake
		var j: float = sin(s * 61.0) * 0.04 * k
		return [Vector3(j, sin(s * 47.0) * 0.03 * k - 0.04 * k, 0.0), j * 0.3]
	if s < period - rise:
		var f: float = minf((s - br) / FALL_TIME, 1.0)
		var drop: float = 30.0 * f * f
		return [Vector3(0, -drop, size.z * 0.15 * f), 0.75 * f]
	# hauled back up from below
	var r: float = clampf((s - (period - rise)) / rise, 0.0, 1.0)
	var e: float = 1.0 - (1.0 - r) * (1.0 - r)
	return [Vector3(0, -14.0 * (1.0 - e), 0.0), 0.0]


func _physics_process(_dt: float) -> void:
	_apply(Game.course_time)


func _apply(t: float) -> void:
	var s: float = _s(t)
	for i: int in _sections.size():
		var d: Dictionary = _sections[i]
		var body: AnimatableBody3D = d["body"]
		var pose: Array = _pose_of(i, t)
		body.position = (d["home"] as Vector3) + (pose[0] as Vector3)
		body.rotation.x = float(pose[1])
		var broken: bool = _broken(i, t)
		var cs: CollisionShape3D = d["shape"]
		if cs.disabled != broken:
			cs.set_deferred("disabled", broken)
		body.visible = s < float(d["break"]) + FALL_TIME or s >= period - rise
		if broken and not _was_broken[i]:
			(d["dust"] as GPUParticles3D).restart()
			(d["chunks"] as GPUParticles3D).restart()
			# SOUND: the timbers splitting as a flat goes
			WorldAudio.at(self, "frontier_timber_crack", body.global_position, 1.0, 60.0, 0.08)
		_was_broken[i] = broken


func _process(_dt: float) -> void:
	var t: float = Game.course_time
	var rumbling: bool = is_rumbling_at(t)
	if rumbling != _was_rumbling:
		_was_rumbling = rumbling
		WorldAudio.set_active(_rumble, rumbling)
	var fz: float = front_z(t)
	var moving: bool = fz < 0.9
	if _front_dust.emitting != (moving or (_s(t) < warn)):
		_front_dust.emitting = moving or _s(t) < warn
	_front_node.position = Vector3(0, -1.0, minf(fz, 0.0))
	var s: float = _s(t)
	var rising: bool = s >= period - rise
	if rising and not _was_rising:
		# SOUND: the flats hauled back up on their chains
		WorldAudio.at(self, "frontier_collapse_rebuild", global_position + Vector3(0, 0, _run_mid()), 0.7, 60.0)
	_was_rising = rising


func _run_mid() -> float:
	var lo: float = 0.0
	for d: Dictionary in _sections:
		lo = minf(lo, (d["home"] as Vector3).z)
	return lo * 0.5


# ---- look --------------------------------------------------------------------------------------------

func _section_fx(top: Vector3, size: Vector3) -> Array[GPUParticles3D]:
	var vis := AABB(Vector3(-size.x * 3.0, -40.0, -size.z * 2.0), Vector3(size.x * 6.0, 50.0, size.z * 4.0))
	var dust: GPUParticles3D = Fx.smoke({"amount": 22, "lifetime": 1.8, "shape": "box",
		"extents": Vector3(size.x * 0.5, 0.2, size.z * 0.5), "dir": Vector3.UP, "spread": 50.0,
		"speed": Vector2(1.5, 4.0), "size": 2.6, "gravity": Vector3(0, 0.3, 1.5),
		"color": Color(0.78, 0.6, 0.42, 0.7), "aabb": vis})
	dust.position = top + Vector3(0, -0.4, 0)
	add_child(dust)
	var chunks: GPUParticles3D = Fx.debris({"amount": 18, "chunk": 0.3, "speed": Vector2(2.0, 6.0), "spread": 70.0,
		"lifetime": 1.6, "color": Color(0.42, 0.28, 0.16), "aabb": vis})
	chunks.position = dust.position
	add_child(chunks)
	return [dust, chunks]


func _build_front() -> void:
	_front_node = Node3D.new()
	_front_node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_front_node)
	var vis := AABB(Vector3(-20, -40, -20), Vector3(40, 60, 40))
	# the front: a boil of dust and splinters rising from the trestle under the flats
	_front_dust = Fx.smoke({"amount": 40, "lifetime": 1.6, "one_shot": false, "explosiveness": 0.0, "emitting": false,
		"shape": "box", "extents": Vector3(3.5, 0.5, 1.0), "dir": Vector3.UP, "spread": 35.0,
		"speed": Vector2(3.0, 7.0), "size": 3.0, "gravity": Vector3(0, 0.5, 3.0),
		"color": Color(0.8, 0.62, 0.44, 0.6), "aabb": vis})
	_front_node.add_child(_front_dust)
