class_name AscentDataStream
extends Node3D
## THE FINAL ASCENT's data stream: laser "packets" pour down a conveyor toward the runner
## on a fixed rhythm (pure function of Game.course_time, identical for every racer).
## Each packet is a low kill beam across the belt - the whole width ("full") or one lane
## ("left" / "right", sidestep or hop). Hop them while the belt drags you back.
## Placed at the centre of the belt's top; packets travel along local +Z (downstream),
## so the runner heads toward local -Z. Beams fade in at the upstream end and out at
## the downstream end, and only kill while fully lit.

const COLORS: Array[Color] = [Color(1.0, 0.25, 0.75), Color(0.35, 0.95, 1.0)]

@export var length: float = 30.0
@export var width: float = 4.4
## Packet speed along the belt (m/s, toward local +Z).
@export var speed: float = 5.5
@export var spacing: float = 8.5
## Beam centre above the belt top.
@export var height: float = 0.45
## Offset of the whole train along the stream (m).
@export var phase: float = 0.0
## Which lanes each packet covers, cycling: "full", "left" (local -X half) or "right".
@export var pattern: PackedStringArray = PackedStringArray(["full", "full", "left", "full", "right"])

const BEAM: float = 0.24
const FADE: float = 0.9

var _count: int = 0
var _cycle: float = 0.0
var _packets: Array[Node3D] = []
var _areas: Array[Area3D] = []
# sound (side effect only): a chirp as each packet spawns upstream, a zip as one passes the runner
var _audio: bool = false
var _rel: Array[float] = []


func _ready() -> void:
	_count = maxi(int(round(length / spacing)), 1)
	_cycle = float(_count) * spacing
	for k: int in _count:
		var lane: String = pattern[k % pattern.size()]
		var span: Vector2 = _span(lane)
		var p := Node3D.new()
		add_child(p)
		var col: Color = COLORS[k % COLORS.size()] if lane == "full" else COLORS[0]
		var core := StandardMaterial3D.new()
		core.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		core.albedo_color = col.lightened(0.35)
		var beam := Look.box(Vector3(span.y - span.x, BEAM, BEAM), core, Vector3((span.x + span.y) * 0.5, 0, 0))
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.add_child(beam)
		var halo_mat := StandardMaterial3D.new()
		halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		halo_mat.albedo_color = Color(col.r, col.g, col.b, 0.35)
		var halo := Look.box(Vector3(span.y - span.x + 0.1, BEAM * 2.6, BEAM * 2.6), halo_mat, Vector3((span.x + span.y) * 0.5, 0, 0))
		halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.add_child(halo)
		# emitter nodes riding at the beam ends
		var node_mat: StandardMaterial3D = Look.flat(col, 0.3, 0.0, 3.0)
		for x: float in [span.x, span.y]:
			var d := Look.sphere(0.2, node_mat, Vector3(x, 0, 0))
			d.scale = Vector3(0.7, 1.6, 0.7)
			p.add_child(d)
		p.add_child(_bits(col, span))
		var area := Area3D.new()
		area.collision_layer = 0
		area.collision_mask = 2
		area.monitorable = false
		var shape := BoxShape3D.new()
		shape.size = Vector3(span.y - span.x, BEAM * 0.92, BEAM * 0.92)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = Vector3((span.x + span.y) * 0.5, 0, 0)
		area.add_child(cs)
		p.add_child(area)
		_packets.append(p)
		_areas.append(area)
	_apply()
	add_to_group("course_clock")
	_audio = WorldAudio.enabled()


## Local X range a lane covers.
func _span(lane: String) -> Vector2:
	var h: float = width * 0.5
	if lane == "left":
		return Vector2(-h, -0.05)
	if lane == "right":
		return Vector2(0.05, h)
	return Vector2(-h, h)


## Trail of data bits shed behind the packet (world space, so they stream away downstream).
func _bits(col: Color, span: Vector2) -> GPUParticles3D:
	var g := GPUParticles3D.new()
	g.amount = Fx.count(22)
	g.lifetime = 0.7
	g.local_coords = false
	g.visibility_aabb = AABB(Vector3(-6, -2, -40), Vector3(12, 5, 80))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3((span.y - span.x) * 0.5, 0.08, 0.05)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 40.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 1.2
	pm.gravity = Vector3(0, -0.6, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(col.r, col.g, col.b, 1.0))
	ramp.set_color(1, Color(col.r, col.g, col.b, 0.0))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	g.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.12, 0.12)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	qm.vertex_color_use_as_albedo = true
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = qm
	g.draw_pass_1 = q
	g.position = Vector3((span.x + span.y) * 0.5, 0, 0)
	return g


## Local Z of packet k at `time`.
func packet_z(k: int, time: float) -> float:
	return -length * 0.5 + fposmod(speed * time + phase + float(k) * spacing, _cycle)


## Fully lit (and deadly) while inside the belt, away from both fade zones.
func _lit(z: float) -> bool:
	return absf(z) < length * 0.5 - FADE * 0.5


## Is there a lit packet within `reach` (along the stream) of world point `p` at `time`,
## covering p's lane (with the body's radius)? Bots use this to time their hops.
func threat(p: Vector3, time: float, reach: float) -> bool:
	var l: Vector3 = to_local(p)
	for k: int in _count:
		var z: float = packet_z(k, time)
		if not _lit(z) or absf(z - l.z) > reach:
			continue
		var span: Vector2 = _span(pattern[k % pattern.size()])
		if l.x > span.x - 0.45 and l.x < span.y + 0.45:
			return true
	return false


func snap_to_clock() -> void:
	_apply()
	for p: Node3D in _packets:
		p.reset_physics_interpolation()


func _apply() -> void:
	var t: float = Game.course_time
	for k: int in _count:
		var z: float = packet_z(k, t)
		var p: Node3D = _packets[k]
		var jump: bool = absf(p.position.z - z) > spacing * 0.5
		p.position = Vector3(0, height, z)
		if jump:
			p.reset_physics_interpolation()
			# a fresh packet at the upstream end (not a restart re-placing the train)
			if _audio and z < -length * 0.5 + 1.0:
				WorldAudio.at(self, "data_chirp", p.global_position, 0.45, 30.0, 0.02)
		var edge: float = length * 0.5 - absf(z)
		var s: float = clampf(edge / FADE, 0.02, 1.0)
		p.scale = Vector3(s, s, s)


## Sound only: a zip as a lit packet goes past the runner in its lane.
func _zip_past_player() -> void:
	var pl: Node3D = WorldAudio.local_player(self)
	_rel.resize(_count)
	if pl == null:
		return
	var l: Vector3 = to_local(pl.global_position)
	var on_belt: bool = absf(l.x) < width * 0.5 + 1.0 and l.y > -1.0 and l.y < 3.0
	for k: int in _count:
		var z: float = packet_z(k, Game.course_time)
		var rel: float = z - l.z
		if on_belt and _lit(z) and _rel[k] < 0.0 and rel >= 0.0 and rel - _rel[k] < 1.0:
			var span: Vector2 = _span(pattern[k % pattern.size()])
			var near: float = 0.0 if (l.x > span.x and l.x < span.y) else minf(absf(l.x - span.x), absf(l.x - span.y))
			if near < 1.5:
				WorldAudio.at(self, "data_zip", _packets[k].global_position, 0.6, 20.0, 0.04)
		_rel[k] = rel


func _physics_process(_dt: float) -> void:
	_apply()
	if _audio:
		_zip_past_player()
	var t: float = Game.course_time
	for k: int in _count:
		if not _lit(packet_z(k, t)):
			continue
		for body: Node3D in _areas[k].get_overlapping_bodies():
			if body is Player:
				var n: Node = self
				while n != null and not n.has_method("fail"):
					n = n.get_parent()
				if n != null:
					n.call_deferred("fail", "hazard")
				return
