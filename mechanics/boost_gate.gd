class_name BoostGate
extends Node3D
## Boost gate (flow kit, docs/FLOW_KIT.md). A ground arch: pass through it going the right way and
## your speed is lifted to `speed` m/s along the gate's axis (local -Z, turned by yaw). It never
## slows you: faster than `speed` already and only the heading is nudged toward the axis.
## Like a boost strip, but a pass-through gate. Passing counts toward the level's ring chain.
## The node's origin is the floor point under the arch's middle.

@export var speed: float = 20.0
@export var width: float = 5.0
@export var height: float = 3.2
## How far the heading is pulled toward the gate's axis on a pass (0..1).
@export var assist: float = 0.6
## Height of the trigger over the floor point (the arch catches a rider up to this high; a gate that
## also catches jumps can be left at the default).
@export var reach: float = 3.4
## Whether a pass counts toward the chain counter.
@export var counts_chain: bool = true
## World point of the next gate / ring (the streaming guide points at it); Vector3.INF = none.
@export var next_point: Vector3 = Vector3.INF

var chain: FlowChain
var passes: int = 0

const THICK: float = 1.6
const REARM_TICKS: int = 30

var _area: Area3D
var _mat: StandardMaterial3D
var _wave: GPUParticles3D
var _last_tick: int = -100000
var _passed_tick: int = -100000
var _base_energy: float = 2.0


func _ready() -> void:
	_build()
	if chain == null and counts_chain:
		chain = FlowChain.of(self)


func _build() -> void:
	var col: Color = Look.c("accent2").lerp(Color(0.55, 1.0, 0.85), 0.3)
	_mat = (Look.flat(col, 0.3, 0.0, _base_energy).duplicate()) as StandardMaterial3D
	var metal: StandardMaterial3D = Look.flat(Look.c("metal"), 0.4, 0.6)
	# two posts, a glowing lintel and a faint sheet between them
	for sx: float in [-1.0, 1.0]:
		add_child(Look.box(Vector3(0.28, height, 0.5), metal, Vector3(sx * (width * 0.5 + 0.14), height * 0.5, 0)))
		add_child(Look.box(Vector3(0.1, height - 0.2, 0.56), _mat, Vector3(sx * (width * 0.5 + 0.14), height * 0.5, 0)))
	add_child(Look.box(Vector3(width + 0.56, 0.34, 0.56), metal, Vector3(0, height, 0)))
	add_child(Look.box(Vector3(width + 0.3, 0.12, 0.6), _mat, Vector3(0, height, 0)))
	# chevrons on the lintel pointing the way (a V of two bars)
	for sx2: float in [-1.0, 1.0]:
		var bar := Look.box(Vector3(0.9, 0.12, 0.08), _mat, Vector3(sx2 * 0.42, height + 0.34, -0.05))
		bar.rotation_degrees.z = -sx2 * 24.0
		add_child(bar)
	var sheet := StandardMaterial3D.new()
	sheet.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sheet.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sheet.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	sheet.cull_mode = BaseMaterial3D.CULL_DISABLED
	sheet.albedo_color = Color(col.r, col.g, col.b, 0.07)
	var qm := QuadMesh.new()
	qm.size = Vector2(width, height)
	var q := MeshInstance3D.new()
	q.mesh = qm
	q.material_override = sheet
	q.position = Vector3(0, height * 0.5, 0)
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(q)
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 2
	_area.monitorable = false
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(width + 0.4, reach, THICK)
	cs.shape = bs
	cs.position = Vector3(0, reach * 0.5 - 0.1, 0)
	_area.add_child(cs)
	add_child(_area)
	_area.body_entered.connect(_on_body)
	_wave = Fx.shockwave(width * 0.45, {"color": Color(col.r * 2.0, col.g * 2.0, col.b * 2.0), "lifetime": 0.4})
	add_child(_wave)
	_build_guide(col)


func _build_guide(col: Color) -> void:
	if not next_point.is_finite():
		return
	var d: Vector3 = next_point - global_position
	var dist: float = d.length()
	if dist < 3.0:
		return
	var local_dir: Vector3 = global_basis.inverse() * (d / dist)
	var v: float = 22.0
	var lifetime: float = dist / v
	var aabb := AABB(Vector3(minf(0.0, local_dir.x * dist), minf(0.0, local_dir.y * dist), minf(0.0, local_dir.z * dist)) - Vector3.ONE * 2.0,
		Vector3(absf(local_dir.x * dist), absf(local_dir.y * dist), absf(local_dir.z * dist)) + Vector3.ONE * 4.0)
	var dashes: GPUParticles3D = Fx.emitter({"amount": clampi(int(dist / 2.2), 4, 28), "lifetime": lifetime,
		"local": true, "shape": "point", "dir": local_dir, "spread": 0.0, "speed": Vector2(v, v),
		"facing": "velocity", "tex": Fx.Tex.SPARK, "size": Vector2(0.07, 1.3),
		"fade": PackedFloat32Array([0.0, 0.7, 0.7, 0.0]), "color": Color(col.r * 1.6, col.g * 1.6, col.b * 1.6, 0.8),
		"aabb": aabb, "preprocess": lifetime, "offset": Vector3(0, 0.9, 0)})
	add_child(dashes)


func forward() -> Vector3:
	var f: Vector3 = -global_basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 0.001 else Vector3.FORWARD


## Speed after passing at `v_in` m/s.
func speed_out(v_in: float) -> float:
	return maxf(v_in, speed)


func passed_within(seconds: float) -> bool:
	return float(Engine.get_physics_frames() - _passed_tick) / float(Engine.physics_ticks_per_second) <= seconds


func _on_body(b: Node3D) -> void:
	if not (b is Player):
		return
	var p: Player = b as Player
	var now: int = Engine.get_physics_frames()
	if now - _last_tick < REARM_TICKS:
		return
	var fwd: Vector3 = forward()
	var hv := Vector3(p.velocity.x, 0.0, p.velocity.z)
	var cur: float = hv.length()
	if cur > 1.0 and hv.dot(fwd) < 0.0:
		return
	_last_tick = now
	_passed_tick = now
	passes += 1
	if chain != null and counts_chain:
		chain.register(self)
	var dir: Vector3 = hv / cur if cur > 0.5 else fwd
	if dir.dot(fwd) < 0.9999:
		dir = dir.slerp(fwd, clampf(assist, 0.0, 1.0)) if dir.dot(fwd) > -0.99 else fwd
	var out: float = speed_out(cur)
	p.velocity.x = dir.x * out
	p.velocity.z = dir.z * out
	if chain != null and counts_chain:
		chain.announce(self, out)
	Fx.fire(_wave, global_position + Vector3(0, 0.1, 0), Fx.basis_up(-global_basis.z))
	_mat.emission_energy_multiplier = _base_energy + 3.5
	var tw: Tween = create_tween()
	tw.tween_property(_mat, "emission_energy_multiplier", _base_energy, 0.4)
	WorldAudio.at(self, "flow_gate_pass", global_position + Vector3(0, 1.0, 0), 0.9, 55.0, 0.02)
