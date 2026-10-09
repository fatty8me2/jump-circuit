class_name ArcaneCircle
extends StaticBody3D
## Arcane Library: SPELL CIRCLE. A round slab with a spell drawn on it in light. Stand on it and the
## spell gathers: the runes spin faster and burn brighter while a bright hand sweeps round the outer
## ring (that is the tell, `charge_time` s, never under 0.8) and then it throws you along a fixed
## arc to land on `target`, a feet position (a dotted arc of sparks shows the flight). Step off before
## it is full and the charge drains away (twice as fast as it filled); after a cast it ignores you
## for a second. The throw is the same every time (the same arc as the kit's launch barrel: the
## stick held toward the target in flight is all it takes to land).
## Place the node at the centre of the circle's TOP surface (like kit.plat).
##   target     world feet position to land on
##   arc        metres the flight rises above the higher of start and target
##   radius     of the slab

@export var target: Vector3 = Vector3.ZERO
@export var arc: float = 3.0
@export var radius: float = 1.5
@export var charge_time: float = 1.0
@export var cooldown: float = 1.0
@export var tint: Color = Color(0.7, 0.45, 1.0)

var _charge: float = 0.0
var _cool: float = 0.0
var _vel: Vector3 = Vector3.ZERO
var _area: Area3D
var _glyph: MeshInstance3D
var _mat: ShaderMaterial
var _fired_tick: int = -100000
var _was_charging: bool = false
var _gather: GPUParticles3D
var _cast: GPUParticles3D
var _lamp: OmniLight3D


func _ready() -> void:
	charge_time = maxf(charge_time, KitUtil.MIN_TELL)
	collision_layer = 1
	collision_mask = 0
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = 0.3
	var cs := CollisionShape3D.new()
	cs.shape = cyl
	cs.position = Vector3(0, -0.15, 0)
	add_child(cs)
	var slab: MeshInstance3D = Look.platform_round(radius, 0.3, "accent")
	slab.position = Vector3(0, -0.15, 0)
	add_child(slab)
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 2
	_area.monitorable = false
	var shape := CylinderShape3D.new()
	shape.radius = radius * 0.78
	shape.height = 0.5
	var acs := CollisionShape3D.new()
	acs.shape = shape
	acs.position = Vector3(0, 0.25, 0)
	_area.add_child(acs)
	add_child(_area)
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://visual/arcane_circle.gdshader")
	_mat.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	var qm := QuadMesh.new()
	qm.size = Vector2(radius * 2.0, radius * 2.0)
	qm.orientation = PlaneMesh.FACE_Y
	_glyph = Look.mesh_node(qm, _mat, Vector3(0, 0.012, 0))
	_glyph.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_glyph)
	_vel = KitUtil.launch_velocity(global_position, target, arc)
	_build_fx()
	add_to_group("resettable")


func launch_velocity() -> Vector3:
	return _vel


## 0..1: how much of the spell has gathered.
func charge_fraction() -> float:
	return clampf(_charge / charge_time, 0.0, 1.0)


func is_charging() -> bool:
	return _charge > 0.0


## True if the circle cast within the last `window` s (a bot / test hook).
func cast_within(window: float) -> bool:
	return float(Engine.get_physics_frames() - _fired_tick) / float(Engine.physics_ticks_per_second) <= window


func reset_state() -> void:
	_charge = 0.0
	_cool = 0.0


func _physics_process(dt: float) -> void:
	_cool = maxf(_cool - dt, 0.0)
	var pl: Player = null
	if _cool <= 0.0:
		pl = KitUtil.player_in(_area, true)
	var on: bool = pl != null and pl.grounded and absf(pl.global_position.y - global_position.y) < 0.35
	if on:
		_charge = minf(_charge + dt, charge_time)
		if _charge >= charge_time:
			_cast_spell(pl)
	else:
		_charge = maxf(_charge - dt * 2.0, 0.0)
	var f: float = charge_fraction()
	_mat.set_shader_parameter("charge", f)
	var charging: bool = _charge > 0.0
	if charging != _was_charging:
		_was_charging = charging
		_gather.emitting = charging
		_lamp.visible = charging
		if charging:
			# SOUND: arcane_circle_charge - the spell gathers: a rising chord of glass and whispers (~1 s)
			WorldAudio.at(self, "arcane_circle_charge", global_position, 0.8, 26.0)
	if charging:
		_lamp.light_energy = 0.4 + 2.6 * f


func _cast_spell(pl: Player) -> void:
	_charge = 0.0
	_cool = cooldown
	_fired_tick = Engine.get_physics_frames()
	pl.knockback(_vel)
	_cast.restart()
	_cast.emitting = true
	Fx.pulse(_lamp, 6.0, 0.0, 0.5)
	# SOUND: arcane_circle_cast - the spell breaks: a bright bell and a whoosh as the rider is thrown
	WorldAudio.at(self, "arcane_circle_cast", global_position, 1.0, 40.0)


func _build_fx() -> void:
	var hot: Color = Fx.hot(tint.lerp(Color(1.0, 0.85, 0.5), 0.4), 2.2)
	var vis := AABB(Vector3(-radius - 2.0, -1.0, -radius - 2.0), Vector3(radius * 2.0 + 4.0, 9.0, radius * 2.0 + 4.0))
	_gather = Fx.emitter({"amount": 26, "lifetime": 0.9, "emitting": false, "local": true, "shape": "ring",
		"ring_radius": radius * 0.9, "ring_inner": radius * 0.2, "dir": Vector3.UP, "spread": 10.0,
		"speed": Vector2(0.8, 2.4), "tex": Fx.Tex.STAR, "size": 0.22, "color": hot, "curve": "pop", "aabb": vis})
	_gather.position = Vector3(0, 0.05, 0)
	add_child(_gather)
	_cast = Fx.sparks({"amount": 40, "lifetime": 0.7, "shape": "ring", "ring_radius": radius * 0.7,
		"ring_inner": radius * 0.2, "dir": Vector3.UP, "spread": 20.0, "speed": Vector2(5.0, 12.0),
		"gravity": Vector3(0, -10, 0), "color": hot, "size": Vector2(0.07, 0.55), "aabb": vis})
	_cast.position = Vector3(0, 0.05, 0)
	add_child(_cast)
	_lamp = OmniLight3D.new()
	_lamp.light_color = tint.lerp(Color(1.0, 0.85, 0.6), 0.3)
	_lamp.omni_range = 5.0
	_lamp.light_energy = 0.0
	_lamp.visible = false
	_lamp.position = Vector3(0, 0.8, 0)
	add_child(_lamp)
	_build_preview()


## A dotted arc of gold motes from the circle to the landing (MultiMesh, unshaded).
func _build_preview() -> void:
	var tuning := load("res://resources/default_tuning.tres") as MovementTuning
	var pts: PackedVector3Array = Ballistics.arc(tuning, global_position, _vel, 2.2, 0.09)
	var local_pts: Array[Vector3] = []
	for p: Vector3 in pts:
		if p.y < target.y - 0.2 and local_pts.size() > 3:
			break
		local_pts.append(to_local(p))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var sm := SphereMesh.new()
	sm.radius = 0.1
	sm.height = 0.2
	sm.radial_segments = 8
	sm.rings = 4
	mm.mesh = sm
	var count: int = maxi(local_pts.size() - 4, 0)
	mm.instance_count = count
	for i: int in count:
		var s: float = 1.0 - 0.55 * float(i) / float(maxi(count, 1))
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * s), local_pts[i + 4]))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(tint.r, tint.g, tint.b, 0.6).lerp(Color(1.0, 0.85, 0.5, 0.7), 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
