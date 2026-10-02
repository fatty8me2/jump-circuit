class_name DoomPour
extends Node3D
## Doom Fortress: the MOLTEN POUR. A crucible hangs on trunnions at the head of a sunken lane; on
## the course clock it tips, and a tongue of white-hot metal pours out over its lip and sweeps down
## the lane at `speed` m/s, `pour` seconds long, then runs off the far end into the pit. Anything in
## the lane under the tongue (below `depth`) goes back to the checkpoint.
## The tell: the crucible starts tipping `tilt_time` seconds before the metal leaves the lip - it
## groans, its glow flares, sparks spill over the rim and the lane's warning lamps flash - and the
## tongue itself is bright and slow enough to watch coming down the lane.
## Local frame: the lane runs along +X from x = 0 (under the crucible's lip) to x = `length`, it is
## `width` wide along Z, and its floor is at y = 0. A pure function of Game.course_time.

@export var length: float = 20.0
@export var width: float = 4.0
@export var period: float = 6.0
@export var phase: float = 0.0
## Speed of the molten front along the lane (m/s).
@export var speed: float = 9.0
## Seconds the crucible pours (the tongue's length is speed * pour).
@export var pour: float = 1.2
## Kill height above the lane floor (the tongue covers anything below it).
@export var depth: float = 1.4
## Seconds the crucible tips before the metal leaves its lip.
@export var tilt_time: float = 1.2

var _crucible: Node3D
var _tongue: MeshInstance3D
var _stream: MeshInstance3D
var _spatter: GPUParticles3D
var _lip_sparks: GPUParticles3D
var _lamps: Array[MeshInstance3D] = []
var _lamp_on: StandardMaterial3D
var _lamp_off: StandardMaterial3D
var _glow: OmniLight3D
var _loop: AudioStreamPlayer3D
var _tipped: int = -999
var _poured: int = -999
var _hit_tick: int = -100


func _ready() -> void:
	_build()
	_apply(Game.course_time)
	add_to_group("course_clock")


func _s(time: float) -> float:
	return fposmod(time / maxf(period, 0.01) + phase, 1.0) * period


func _cycle(time: float) -> int:
	return int(floor(time / maxf(period, 0.01) + phase))


## Seconds of the cycle the metal starts leaving the lip.
func _pour_start() -> float:
	return tilt_time


## The molten span [tail, front] along local X at `time` (empty when tail >= front).
func span_at(time: float) -> Vector2:
	var s: float = _s(time) - _pour_start()
	if s < 0.0:
		return Vector2(0.0, 0.0)
	var front: float = minf(speed * s, length + 1.0)
	var tail: float = clampf(speed * (s - pour), 0.0, length + 1.0)
	return Vector2(tail, front)


## True if the tongue covers lane position `x` (with `margin` either side) at `time`.
func covers(x: float, time: float, margin: float = 0.6) -> bool:
	var sp: Vector2 = span_at(time)
	return sp.y > sp.x and x > sp.x - margin and x < sp.y + margin


## True if lane position `x` stays clear over [now + a, now + b].
func clear_for(x: float, a: float, b: float, margin: float = 0.6) -> bool:
	var s: float = a
	while s <= b:
		if covers(x, Game.course_time + s, margin):
			return false
		s += 0.04
	return true


## Lane position (local x) of a world point.
func lane_x(world: Vector3) -> float:
	return to_local(world).x


## 0 (upright) .. 1 (fully tipped) at `time`.
func tip_at(time: float) -> float:
	var s: float = _s(time)
	var p0: float = _pour_start()
	if s < p0:
		var k: float = s / maxf(p0, 0.01)
		return k * k * 0.75
	if s < p0 + pour:
		return 0.75 + 0.25 * minf((s - p0) / 0.25, 1.0)
	var r: float = clampf((s - p0 - pour) / 1.0, 0.0, 1.0)
	return 1.0 - r * r * (3.0 - 2.0 * r)


func snap_to_clock() -> void:
	_apply(Game.course_time)


func _physics_process(_dt: float) -> void:
	var t: float = Game.course_time
	var sp: Vector2 = span_at(t)
	if sp.y <= sp.x:
		return
	var pl: Node3D = WorldAudio.local_player(self)
	if pl == null:
		return
	var p: Vector3 = to_local(pl.global_position)
	if absf(p.z) < width * 0.5 and p.y > -0.5 and p.y < depth and p.x > sp.x - 0.3 and p.x < sp.y + 0.3:
		var tick: int = Engine.get_physics_frames()
		if tick - _hit_tick > 30:
			_hit_tick = tick
			var n: Node = self
			while n != null and not n.has_method("fail"):
				n = n.get_parent()
			if n != null:
				n.call_deferred("fail", "hazard")


func _process(_dt: float) -> void:
	_apply(Game.course_time)


func _apply(t: float) -> void:
	var s: float = _s(t)
	var cyc: int = _cycle(t)
	var tip: float = tip_at(t)
	_crucible.rotation.z = -tip * 1.25
	var sp: Vector2 = span_at(t)
	var on: bool = sp.y > sp.x
	_tongue.visible = on
	if on:
		var a: float = maxf(sp.x, 0.0)
		var b: float = minf(sp.y, length)
		if b > a + 0.02:
			_tongue.scale = Vector3(b - a, 1.0, 1.0)
			_tongue.position = Vector3((a + b) * 0.5, depth * 0.32, 0)
		else:
			_tongue.visible = false
	var pouring: bool = s >= _pour_start() and s < _pour_start() + pour
	_stream.visible = pouring
	_spatter.emitting = on and sp.y < length + 0.5
	if on:
		_spatter.position = Vector3(clampf(sp.y, 0.0, length), 0.4, 0)
	var warning: bool = s < _pour_start()
	_lip_sparks.emitting = warning or pouring
	var blink: bool = warning and fmod(t, 0.24) < 0.12
	for l: MeshInstance3D in _lamps:
		l.material_override = _lamp_on if (blink or pouring) else _lamp_off
	_glow.light_energy = 1.0 + 3.0 * tip
	if warning and cyc != _tipped:
		_tipped = cyc
		# SOUND: doom_pour_tilt - the crucible's chains groan as it starts to tip (the ~1.2 s warning)
		WorldAudio.at(self, "doom_pour_tilt", _crucible.global_position, 0.9, 40.0)
	if pouring and cyc != _poured:
		_poured = cyc
		# SOUND: doom_pour_splash - the first gout of metal hitting the lane
		WorldAudio.at(self, "doom_pour_splash", global_position + global_basis * Vector3(1.0, 0, 0), 1.0, 40.0)
	WorldAudio.set_active(_loop, on)


func _build() -> void:
	var iron: StandardMaterial3D = DoomDecor.iron()
	var steel: StandardMaterial3D = DoomDecor.steel()
	# the crucible: a heavy bucket on a trunnion frame above the lane's head, lip toward +X
	var frame_h: float = depth + 3.6
	for sz: float in [-1.0, 1.0]:
		add_child(Look.box(Vector3(0.5, frame_h, 0.5), iron, Vector3(-1.2, frame_h * 0.5, sz * (width * 0.5 + 0.6))))
	add_child(Look.box(Vector3(0.6, 0.6, width + 1.8), iron, Vector3(-1.2, frame_h, 0)))
	_crucible = Node3D.new()
	_crucible.position = Vector3(-1.2, frame_h - 1.0, 0)
	add_child(_crucible)
	var r: float = minf(width * 0.42, 1.6)
	var bucket := Look.cylinder(r, r * 1.6, steel, Vector3(0, -r * 0.5, 0), r * 1.15, 20)
	_crucible.add_child(bucket)
	_crucible.add_child(Look.cylinder(r * 1.2, 0.2, iron, Vector3(0, r * 0.32, 0), -1.0, 20))
	_crucible.add_child(DoomDecor.ns(Look.cylinder(r * 1.02, 0.08, DoomDecor.molten(Vector2.ZERO, 2.2, 0.3, 1.2), Vector3(0, r * 0.3, 0), -1.0, 20)))
	# the spout on the +X side
	_crucible.add_child(Look.box(Vector3(0.9, 0.3, 0.7), steel, Vector3(r + 0.3, r * 0.25, 0)))
	_crucible.add_child(DoomDecor.ns(Look.box(Vector3(0.6, 0.06, 0.4), DoomDecor.molten(Vector2.ZERO, 2.0, 0.2, 1.0), Vector3(r + 0.4, r * 0.4, 0))))
	# the lane: an iron trough with hazard-striped curbs and warning lamps along both sides
	var trough: StandardMaterial3D = Look.flat(Color(0.05, 0.04, 0.04), 0.9, 0.3)
	add_child(Look.box(Vector3(length + 2.0, 0.3, width), trough, Vector3(length * 0.5, -0.15, 0)))
	for sz2: float in [-1.0, 1.0]:
		add_child(DoomDecor.ns(Look.box(Vector3(length + 2.0, 0.12, 0.3), DoomDecor.hazard(0.3), Vector3(length * 0.5, 0.02, sz2 * (width * 0.5 + 0.15)))))
	_lamp_on = DoomDecor.alarm(4.0)
	_lamp_off = Look.flat(Color(0.25, 0.04, 0.03), 0.4, 0.0, 0.3)
	var nl: int = maxi(int(length / 5.0), 2)
	for i: int in nl:
		for sz3: float in [-1.0, 1.0]:
			var lamp := Look.sphere(0.13, _lamp_off, Vector3(1.5 + float(i) * (length - 2.0) / float(nl - 1), 0.25, sz3 * (width * 0.5 + 0.35)))
			lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(lamp)
			_lamps.append(lamp)
	# the tongue (a unit box scaled along X each frame) and the falling stream from the lip
	var flow_dir: Vector3 = global_basis * Vector3(1, 0, 0)
	_tongue = Look.mesh_node(_tongue_mesh(), DoomDecor.molten(Vector2(flow_dir.x, flow_dir.z) * speed * 0.5, 2.2, 0.25, 0.6))
	_tongue.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_tongue)
	var sh: float = frame_h - 1.0 + r * 0.25
	_stream = Look.cylinder(0.32, sh, DoomDecor.molten(Vector2.ZERO, 2.4, 0.15, 1.5), Vector3(-1.2 + r + 0.6, sh * 0.5, 0), 0.22, 10)
	_stream.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_stream)
	var vis := AABB(Vector3(-4, -2, -width - 2), Vector3(length + 8, 10, width * 2 + 4))
	_spatter = DoomFx.spatter(Vector3(0.4, 0.1, width * 0.45), 34)
	_spatter.visibility_aabb = vis
	add_child(_spatter)
	_lip_sparks = Fx.emitter({"amount": 20, "lifetime": 0.8, "emitting": false, "shape": "box", "extents": Vector3(0.4, 0.1, 0.4),
		"dir": Vector3(1, 0.3, 0), "spread": 40.0, "speed": Vector2(1.0, 3.5), "gravity": Vector3(0, -12.0, 0),
		"facing": "velocity", "tex": Fx.Tex.SPARK, "size": Vector2(0.04, 0.3), "color": Color(3.0, 1.4, 0.4), "aabb": vis})
	_lip_sparks.position = Vector3(-1.2 + r + 0.5, frame_h - 1.0 + r * 0.3, 0)
	add_child(_lip_sparks)
	_glow = OmniLight3D.new()
	_glow.light_color = Color(1.0, 0.45, 0.12)
	_glow.light_energy = 1.0
	_glow.omni_range = maxf(width * 2.5, 9.0)
	_glow.position = Vector3(0.5, frame_h - 1.5, 0)
	add_child(_glow)
	# SOUND: doom_pour_loop - molten metal rushing down the lane (loop, while the tongue is out)
	_loop = WorldAudio.loop("doom_pour_loop", _tongue, -4.0, 28.0, 5.0, false)


## The tongue: 1 m long along X (scaled to the span), `width` wide, a little over depth * 0.64 tall,
## so it visibly drowns the posts set in the lane.
func _tongue_mesh() -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(1.0, depth * 0.64, width - 0.1)
	return b
