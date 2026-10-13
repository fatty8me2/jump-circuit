class_name SpeedRing
extends Node3D
## Speed ring (flow kit, docs/FLOW_KIT.md). A glowing hoop whose centre is the node's position and
## whose axis is local -Z (yaw turns it; yaw 0 = along the course). Pass through it moving the right
## way and the rider gains `add_speed` m/s forward (more as the level's chain builds, see
## FlowChain.bonus), never past `cap`; the heading is also nudged `assist` of the way toward the
## ring's own axis, so a chain of rings gently pulls you onto its line. Faint streaming dashes and a
## hairline lead from each ring to `next_point` so the next one is readable at speed.
## The ring re-arms half a second after a pass. Missing a ring costs nothing.

@export var add_speed: float = 6.0
@export var radius: float = 2.2
@export var cap: float = 30.0
@export var assist: float = 0.35
## World point of the next ring / gate (the guide stream points at it); Vector3.INF = no guide.
@export var next_point: Vector3 = Vector3.INF

var chain: FlowChain
## Passes counted by this ring since the level started.
var passes: int = 0

const THICK: float = 1.6
const REARM_SECONDS: float = 0.5

var _area: Area3D
var _mat: StandardMaterial3D
var _film_mat: StandardMaterial3D
var _wave: GPUParticles3D
var _last_tick: int = -100000
var _passed_tick: int = -100000
var _base_energy: float = 2.4


func _ready() -> void:
	_build()
	if chain == null:
		chain = FlowChain.of(self)


func _build() -> void:
	var col: Color = Look.c("accent2").lerp(Color(0.55, 1.0, 0.95), 0.35)
	_mat = (Look.flat(col, 0.3, 0.0, _base_energy).duplicate()) as StandardMaterial3D
	var tm := TorusMesh.new()
	tm.inner_radius = radius - 0.2
	tm.outer_radius = radius
	tm.rings = 28
	tm.ring_segments = 8
	var torus := MeshInstance3D.new()
	torus.mesh = tm
	torus.material_override = _mat
	torus.rotation_degrees.x = 90.0
	torus.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(torus)
	# a faint film across the opening so it reads as a gate from a distance
	_film_mat = StandardMaterial3D.new()
	_film_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_film_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_film_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_film_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_film_mat.albedo_color = Color(col.r, col.g, col.b, 0.09)
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius - 0.2
	cyl.bottom_radius = radius - 0.2
	cyl.height = 0.02
	cyl.radial_segments = 24
	cyl.rings = 1
	var film := MeshInstance3D.new()
	film.mesh = cyl
	film.material_override = _film_mat
	film.rotation_degrees.x = 90.0
	film.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(film)
	# trigger: a fat disc along the axis, thick enough that 34 m/s cannot skip over it
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 2
	_area.monitorable = false
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = radius
	sh.height = THICK
	cs.shape = sh
	cs.rotation_degrees.x = 90.0
	_area.add_child(cs)
	add_child(_area)
	_area.body_entered.connect(_on_body)
	_wave = Fx.shockwave(radius * 0.9, {"color": Color(col.r * 2.0, col.g * 2.0, col.b * 2.0), "lifetime": 0.45})
	add_child(_wave)
	_build_guide(col)


## The streaming dashes and hairline toward `next_point`.
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
		"aabb": aabb, "preprocess": lifetime})
	add_child(dashes)
	var wire_mat := StandardMaterial3D.new()
	wire_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wire_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wire_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	wire_mat.albedo_color = Color(col.r, col.g, col.b, 0.16)
	var wire: MeshInstance3D = KitUtil.link(0.03, wire_mat)
	add_child(wire)
	KitUtil.place_link(wire, local_dir * (radius + 0.1), local_dir * (dist - radius - 0.1))


## The ring's forward (the way you must pass it) on the ground plane.
func forward() -> Vector3:
	var f: Vector3 = -global_basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 0.001 else Vector3.FORWARD


func centre() -> Vector3:
	return global_position


## True when world point `p` is inside the opening (within `radius - margin` of the axis, near the plane).
func contains(p: Vector3, margin: float = 0.0) -> bool:
	var rel: Vector3 = p - global_position
	var along: float = rel.dot(-global_basis.z)
	return absf(along) <= THICK * 0.5 and (rel - (-global_basis.z) * along).length() <= radius - margin


## Speed after passing at `v_in` m/s as the `chain_count`-th link of a chain.
func speed_out(v_in: float, chain_count: int = 1) -> float:
	if v_in >= cap:
		return v_in
	return minf(v_in + add_speed * FlowChain.bonus(chain_count), maxf(cap, v_in))


func passed_within(seconds: float) -> bool:
	return float(Engine.get_physics_frames() - _passed_tick) / float(Engine.physics_ticks_per_second) <= seconds


func _on_body(b: Node3D) -> void:
	if not (b is Player):
		return
	var p: Player = b as Player
	var now: int = Engine.get_physics_frames()
	if now - _last_tick < int(REARM_SECONDS * float(Engine.physics_ticks_per_second)):
		return
	var fwd: Vector3 = forward()
	var hv := Vector3(p.velocity.x, 0.0, p.velocity.z)
	var speed: float = hv.length()
	if speed > 1.0 and hv.dot(fwd) < 0.0:
		return   # the wrong way through
	_last_tick = now
	_passed_tick = now
	passes += 1
	var c: int = chain.register(self) if chain != null else 1
	var dir: Vector3 = hv / speed if speed > 0.5 else fwd
	if assist > 0.0 and dir.dot(fwd) < 0.9999:
		dir = dir.slerp(fwd, clampf(assist, 0.0, 1.0)) if dir.dot(fwd) > -0.99 else fwd
	var out: float = speed_out(speed, c)
	p.velocity.x = dir.x * out
	p.velocity.z = dir.z * out
	if chain != null:
		chain.announce(self, out)
	_pulse(c)


func _pulse(c: int) -> void:
	Fx.fire(_wave, global_position, Fx.basis_up(-global_basis.z))
	_mat.emission_energy_multiplier = _base_energy + 4.0
	var tw: Tween = create_tween()
	tw.tween_property(_mat, "emission_energy_multiplier", _base_energy, 0.5)
	WorldAudio.at(self, "flow_ring_chain" if c >= 4 else "flow_ring_pass", global_position, 0.9, 60.0, 0.02)
