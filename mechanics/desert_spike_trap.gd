class_name DesertSpikeTrap
extends Node3D
## Scarab Sands: a floor plate whose bronze spikes thrust up on a rhythm (Game.course_time).
## Positioned at the centre of the floor surface it is set into (the floor is the level's own
## platform; the spikes hide inside it). For `warn` seconds before each thrust the plate's sun
## glyph flares, grit puffs out of the slots and the spike tips peek up - then they stab up
## through the plate, hold, and sink away. Deadly while the spikes are up.
##   cycle (s into the period): 0 .. THRUST rising, .. up_time up, .. + RETRACT sinking, rest down.

## Plate footprint (x, z) and the spikes' height above the floor when up.
@export var size: Vector3 = Vector3(2.0, 1.0, 2.0)
@export var period: float = 2.4
## Fraction of the period the spikes stay up.
@export var on_fraction: float = 0.4
@export var phase: float = 0.0
@export var warn: float = 0.6

const THRUST: float = 0.07
const RETRACT: float = 0.22
## Spikes this far up (fraction of their height) are deadly.
const DEADLY: float = 0.3
const SPACING: float = 0.42

var _bed: Node3D
var _kill: Area3D
var _glyph_mat: ShaderMaterial
var _puff: GPUParticles3D
var _sparks: GPUParticles3D
var _grit: GPUParticles3D
var _was_up: bool = false
var _was_warn: bool = false


func _ready() -> void:
	_build()
	_kill = Area3D.new()
	_kill.collision_layer = 0
	_kill.collision_mask = 2
	_kill.monitorable = false
	var ks := BoxShape3D.new()
	ks.size = Vector3(size.x - 0.12, size.y * 0.9, size.z - 0.12)
	var kcs := CollisionShape3D.new()
	kcs.shape = ks
	_kill.add_child(kcs)
	_kill.position = Vector3(0, size.y * 0.45, 0)
	add_child(_kill)
	add_to_group("course_clock")
	_was_up = is_deadly_at(Game.course_time)
	_apply(Game.course_time)


func _build() -> void:
	# the plate: a darker inset tile with a slot for every spike, the sun glyph in the middle
	var plate := Look.box(Vector3(size.x, 0.04, size.z), Look.flat(Color(0.55, 0.38, 0.22), 0.9), Vector3(0, 0.005, 0))
	add_child(plate)
	var nx: int = maxi(int(size.x / SPACING), 2)
	var nz: int = maxi(int(size.z / SPACING), 2)
	var slot: StandardMaterial3D = Look.flat(Color(0.12, 0.08, 0.06), 0.9)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.09
	cone.height = size.y
	cone.radial_segments = 6
	cone.rings = 1
	mm.mesh = cone
	mm.instance_count = nx * nz
	var slots := MultiMesh.new()
	slots.transform_format = MultiMesh.TRANSFORM_3D
	var sm := BoxMesh.new()
	sm.size = Vector3(0.16, 0.02, 0.16)
	slots.mesh = sm
	slots.instance_count = nx * nz
	var k: int = 0
	for ix: int in nx:
		for iz: int in nz:
			var x: float = (float(ix) + 0.5) / float(nx) * size.x - size.x * 0.5
			var z: float = (float(iz) + 0.5) / float(nz) * size.z - size.z * 0.5
			mm.set_instance_transform(k, Transform3D(Basis.IDENTITY, Vector3(x, size.y * 0.5, z)))
			slots.set_instance_transform(k, Transform3D(Basis.IDENTITY, Vector3(x, 0.02, z)))
			k += 1
	var smi := MultiMeshInstance3D.new()
	smi.multimesh = slots
	smi.material_override = slot
	add_child(smi)
	_bed = Node3D.new()
	var spikes := MultiMeshInstance3D.new()
	spikes.multimesh = mm
	spikes.material_override = Look.flat(Color(0.85, 0.6, 0.28), 0.3, 0.9, 0.15)
	spikes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_bed.add_child(spikes)
	add_child(_bed)
	# the warning glyph (its glow is driven by the rhythm)
	var q := QuadMesh.new()
	var gs: float = minf(size.x, size.z) * 0.7
	q.size = Vector2(gs, gs)
	_glyph_mat = ShaderMaterial.new()
	_glyph_mat.shader = preload("res://visual/desert_glyph.gdshader")
	_glyph_mat.set_shader_parameter("kind", 0.05)
	_glyph_mat.set_shader_parameter("color", Color(1.0, 0.45, 0.2))
	_glyph_mat.set_shader_parameter("glow", 0.3)
	_glyph_mat.set_shader_parameter("framed", true)
	var g := Look.mesh_node(q, _glyph_mat, Vector3(0, 0.035, 0))
	g.rotation.x = -PI * 0.5
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(g)
	var vis := AABB(Vector3(-size.x, -1, -size.z), Vector3(size.x * 2.0, size.y + 4.0, size.z * 2.0))
	_puff = Fx.smoke({"amount": 18, "lifetime": 0.8, "shape": "box", "extents": Vector3(size.x * 0.45, 0.05, size.z * 0.45),
		"dir": Vector3.UP, "spread": 50.0, "speed": Vector2(1.0, 3.0), "size": 0.8, "color": Color(0.95, 0.78, 0.55, 0.6), "aabb": vis})
	_puff.position = Vector3(0, 0.1, 0)
	add_child(_puff)
	_sparks = Fx.sparks({"amount": 14, "shape": "box", "extents": Vector3(size.x * 0.4, 0.05, size.z * 0.4), "dir": Vector3.UP,
		"spread": 35.0, "speed": Vector2(3.0, 6.0), "color": Color(3.0, 1.9, 0.7), "aabb": vis})
	_sparks.position = Vector3(0, 0.3, 0)
	add_child(_sparks)
	_grit = Fx.emitter({"amount": 14, "lifetime": 0.5, "emitting": false, "shape": "box",
		"extents": Vector3(size.x * 0.45, 0.02, size.z * 0.45), "dir": Vector3.UP, "spread": 20.0, "speed": Vector2(0.6, 1.6),
		"gravity": Vector3(0, -6, 0), "additive": false, "size": 0.07, "color": Color(0.9, 0.72, 0.45, 0.9),
		"fade": PackedFloat32Array([1.0, 1.0, 0.0]), "aabb": vis})
	_grit.position = Vector3(0, 0.05, 0)
	add_child(_grit)


func _u(time: float) -> float:
	return fposmod(time / period + phase, 1.0)


## 0 (sunk in the floor) .. 1 (fully up) at `time`.
func extension_at(time: float) -> float:
	var k: float = _u(time) * period
	var up_time: float = on_fraction * period
	if k < THRUST:
		return k / THRUST
	if k < up_time:
		return 1.0
	if k < up_time + RETRACT:
		return 1.0 - (k - up_time) / RETRACT
	return 0.0


func is_deadly_at(time: float) -> bool:
	return extension_at(time) > DEADLY


## Seconds until the next thrust starts (0 while the spikes are up or rising).
func time_until_up(time: float) -> float:
	var k: float = _u(time) * period
	if k < on_fraction * period:
		return 0.0
	return period - k


## True if the plate is harmless for the whole window [time + a, time + b].
func is_safe_for(time: float, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if is_deadly_at(time + s):
			return false
		s += 0.04
	return true


func snap_to_clock() -> void:
	_apply(Game.course_time)


func _apply(t: float) -> void:
	var e: float = extension_at(t)
	var until: float = time_until_up(t)
	var warning: bool = e <= 0.0 and until < warn
	var peek: float = 0.0
	if warning:
		peek = 0.12 * (1.0 - until / warn)
	# fully down the tips sit 3 cm under the plate; up they stand `size.y` tall
	_bed.position.y = -size.y - 0.03 + maxf(e, 0.0) * size.y + peek
	var glow: float = 0.35
	if e > 0.0:
		glow = 2.6
	elif warning:
		glow = 0.8 + 2.4 * (1.0 - until / warn) * (0.7 + 0.3 * sin(t * 38.0))
	_glyph_mat.set_shader_parameter("glow", glow)
	if _grit.emitting != warning:
		_grit.emitting = warning
	var up: bool = e > DEADLY
	if up and not _was_up:
		_puff.restart()
		_sparks.restart()
		WorldAudio.at(self, "spike_trap", global_position + Vector3(0, 0.5, 0), 0.9, 35.0)
	elif not up and _was_up:
		WorldAudio.at(self, "spike_retract", global_position, 0.6, 30.0)
	_was_up = up
	_was_warn = warning


func _process(_dt: float) -> void:
	_apply(Game.course_time)


func _physics_process(_dt: float) -> void:
	if not is_deadly_at(Game.course_time):
		return
	for body: Node3D in _kill.get_overlapping_bodies():
		if body is Player:
			var n: Node = self
			while n != null and not n.has_method("fail"):
				n = n.get_parent()
			if n != null:
				n.call_deferred("fail", "hazard")
			return
