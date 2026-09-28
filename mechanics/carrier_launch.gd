class_name CarrierLaunch
extends Node3D
## Super Carrier set piece: a CATAPULT LAUNCH on the course clock. A strike fighter sits tensioned on
## the catapult at the aft end of its lane with the jet blast deflector raised behind it; its engines
## spool up, the shooter lamps strobe, and at the shot it tears down the lane (0 -> ~70 m/s in RUN s),
## lifts off the bow and climbs away. Behind it the deflector drops, the flush aircraft lift at the
## catapult's head sinks into the ship and comes back up with the next jet, the deflector rises
## again, and the next jet spools. Anything in the lane where the jet passes is killed; a lift that
## sinks with you on it is deadly too. Positioned on the deck at the jet's hold point (mid fuselage),
## launching along local -Z; the lane runs `track_length` m to the bow.
##   cycle (s into the period): 0 SHOT .. RUN lane run .. fly-out | JBD down | lift down, reload, up |
##   JBD up | spool (the last WARN s strobing)

@export var track_length: float = 80.0
@export var lane_width: float = 9.0
@export var period: float = 11.0
@export var phase: float = 0.0
@export var lift_size: Vector3 = Vector3(11.0, 0.6, 18.0)
@export var lift_depth: float = 7.0
## The deflector's hinge line (local z, behind the jet's tail) and its size.
@export var jbd_z: float = 9.4
@export var jbd_size: Vector2 = Vector2(10.0, 3.8)

const RUN: float = 2.3
const FLY: float = 3.4
const JBD_DOWN: Vector2 = Vector2(2.5, 3.3)
const LIFT_DOWN: Vector2 = Vector2(3.4, 4.8)
const LIFT_UP: Vector2 = Vector2(5.6, 7.0)
const JET_BACK: float = 5.0
const JBD_UP: Vector2 = Vector2(7.4, 8.2)
const SPOOL: float = 8.4
const WARN: float = 2.5
const JBD_ANGLE: float = 0.95
## Half-length of the deadly box round the running jet.
const KILL_HALF: float = 9.0

const YELLOW := Color(1.0, 0.8, 0.12)

var _jet: Node3D
var _jet_body: AnimatableBody3D
var _jet_kill: Area3D
var _lift: AnimatableBody3D
var _pit_kill: Area3D
var _jbd: AnimatableBody3D
var _jbd_pivot_z: float = 0.0
var _cones: Array[Node3D] = []
var _cone_mat: StandardMaterial3D
var _lamps: Array[MeshInstance3D] = []
var _lamp_on: StandardMaterial3D
var _lamp_off: StandardMaterial3D
var _shuttle: Node3D
var _trail: GPUParticles3D
var _deflect: GPUParticles3D
var _steam: GPUParticles3D
var _shot: GPUParticles3D
var _shot_sparks: GPUParticles3D
var _prev_s: float = 0.0
var _prev_jbd: float = -1.0
var _lift_moving: bool = false


func _ready() -> void:
	_build()
	add_to_group("course_clock")
	snap_to_clock()


func snap_to_clock() -> void:
	_prev_s = _s(Game.course_time)
	_pose(Game.course_time)
	for n: Node3D in [_jet_body, _lift, _jbd]:
		n.reset_physics_interpolation()


# ---- the timeline (pure functions of the course clock) ------------------------------------------

func _s(time: float) -> float:
	return fposmod(time / period + phase, 1.0) * period


## Seconds until the next shot.
func time_until_launch(time: float) -> float:
	var s: float = _s(time)
	return period - s if s > 0.0001 else 0.0


## Local z of the jet's middle while it runs the lane (0 at the hold point).
func jet_z_at(time: float) -> float:
	var s: float = _s(time)
	if s < RUN:
		return -track_length * (s / RUN) * (s / RUN)
	return 0.0


func is_running_at(time: float) -> bool:
	return _s(time) < RUN + 0.1


## True if the running jet's deadly box overlaps local z range [z_lo, z_hi] at `time`.
func lane_deadly(time: float, z_hi: float, z_lo: float) -> bool:
	if not is_running_at(time):
		return false
	var z: float = jet_z_at(time)
	return z - KILL_HALF < z_hi and z + KILL_HALF > z_lo


## The stretch [z_lo, z_hi] of the lane stays clear over the whole window [time + a, time + b].
func lane_safe_for(time: float, z_hi: float, z_lo: float, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if lane_deadly(time + s, z_hi, z_lo):
			return false
		s += 0.04
	return true


## Lift top height (local) at `time`: 0 flush with the deck, down to -lift_depth.
func lift_y_at(time: float) -> float:
	var s: float = _s(time)
	if s < LIFT_DOWN.x or s >= LIFT_UP.y:
		return 0.0
	if s < LIFT_DOWN.y:
		var k: float = (s - LIFT_DOWN.x) / (LIFT_DOWN.y - LIFT_DOWN.x)
		return -lift_depth * k * k * (3.0 - 2.0 * k)
	if s < LIFT_UP.x:
		return -lift_depth
	var r: float = (s - LIFT_UP.x) / (LIFT_UP.y - LIFT_UP.x)
	return -lift_depth * (1.0 - r * r * (3.0 - 2.0 * r))


## Deflector raise angle 0 (flat) .. 1 (up) at `time`.
func jbd_at(time: float) -> float:
	var s: float = _s(time)
	if s < JBD_DOWN.x:
		return 1.0
	if s < JBD_DOWN.y:
		return 1.0 - smoothstep(JBD_DOWN.x, JBD_DOWN.y, s)
	if s < JBD_UP.x:
		return 0.0
	if s < JBD_UP.y:
		return smoothstep(JBD_UP.x, JBD_UP.y, s)
	return 1.0


# ---- per tick ---------------------------------------------------------------------------------------

func _physics_process(_dt: float) -> void:
	var t: float = Game.course_time
	var s: float = _s(t)
	if s < _prev_s and _prev_s - s > period * 0.5:
		_on_shot()
	_prev_s = s
	_pose(t)
	if is_running_at(t):
		_kill_in(_jet_kill)
	_kill_in(_pit_kill)


func _kill_in(a: Area3D) -> void:
	for body: Node3D in a.get_overlapping_bodies():
		if body is Player:
			var n: Node = self
			while n != null and not n.has_method("fail"):
				n = n.get_parent()
			if n != null:
				n.call_deferred("fail", "hazard")
			return


func _on_shot() -> void:
	_shot.restart()
	_shot_sparks.restart()
	WorldAudio.at(self, "carrier_launch_shot", global_position, 1.0, 120.0)


func _pose(t: float) -> void:
	var s: float = _s(t)
	var ly: float = lift_y_at(t)
	_lift.position = Vector3(0, ly - lift_size.y * 0.5, 0)
	# the jet: on the lift (reloaded), tensioned at the hold point, running the lane, flying away
	var jp := Vector3(0, ly, 0)
	var pitch: float = 0.0
	var shown: bool = true
	var solid: bool = true
	if s < RUN:
		jp = Vector3(0, 0, jet_z_at(t))
		solid = false
	elif s < RUN + FLY:
		var ds: float = s - RUN
		var v: float = 2.0 * track_length / RUN
		jp = Vector3(0, 4.0 * ds + 5.0 * ds * ds, -track_length - v * ds)
		pitch = minf(ds * 0.35, 0.22)
		solid = false
	elif s < JET_BACK:
		shown = false
		solid = false
	_jet.visible = shown
	_jet.position = jp
	_jet.rotation.x = pitch
	_jet_body.position = jp
	_jet_body.collision_layer = 1 if solid else 0
	_jet_kill.position = Vector3(0, 1.5, jp.z)
	# the deflector
	var a: float = jbd_at(t)
	_jbd.rotation.x = -JBD_ANGLE * a
	if _prev_jbd >= 0.0:
		if a > _prev_jbd and _prev_jbd <= 0.001:
			WorldAudio.at(self, "carrier_jbd_raise", to_global(Vector3(0, 0, jbd_z)), 0.8, 50.0)
		elif a < _prev_jbd and _prev_jbd >= 0.999:
			WorldAudio.at(self, "carrier_jbd_lower", to_global(Vector3(0, 0, jbd_z)), 0.8, 50.0)
	_prev_jbd = a
	var lm: bool = (s >= LIFT_DOWN.x and s < LIFT_DOWN.y) or (s >= LIFT_UP.x and s < LIFT_UP.y)
	if lm and not _lift_moving:
		WorldAudio.at(self, "carrier_lift_move", global_position, 0.8, 50.0)
	_lift_moving = lm
	# engines: spool glow before the shot, full burner on the run and the climb
	var throttle: float = 0.0
	if s >= SPOOL:
		throttle = 0.25 + 0.35 * smoothstep(SPOOL, period, s)
	elif s < RUN + FLY:
		throttle = 1.0
	for c: Node3D in _cones:
		c.visible = throttle > 0.02 and shown
		c.scale = Vector3(1.0, 1.0, 0.35 + throttle * 1.1)
	_cone_mat.emission_energy_multiplier = 0.5 + 2.2 * throttle
	var warn: bool = s >= period - WARN
	var flash: bool = warn and fposmod(t * 5.0, 1.0) < 0.5
	for l: MeshInstance3D in _lamps:
		l.material_override = _lamp_on if flash else _lamp_off
	var deflecting: bool = s >= SPOOL and a > 0.9
	if _deflect.emitting != deflecting:
		_deflect.emitting = deflecting
	if _trail.emitting != (s < RUN + FLY):
		_trail.emitting = s < RUN + FLY
	var venting: bool = s < RUN + 2.5
	if _steam.emitting != venting:
		_steam.emitting = venting
	# the shuttle races ahead of the nose gear, then crawls back
	var k: float = 0.0
	if s < RUN:
		k = (s / RUN) * (s / RUN)
	elif s < RUN + 0.6:
		k = 1.0
	elif s < RUN + 4.5:
		var r: float = (s - RUN - 0.6) / 3.9
		k = 1.0 - r * r * (3.0 - 2.0 * r)
	_shuttle.position = Vector3(0, 0.03, -6.0 - k * (track_length - 6.0))
	if s >= SPOOL and s - get_physics_process_delta_time() < SPOOL:
		WorldAudio.at(self, "carrier_launch_spool", global_position + Vector3(0, 2, 6), 0.9, 70.0)
	if s >= RUN + 0.2 and s - get_physics_process_delta_time() < RUN + 0.2:
		WorldAudio.at(self, "carrier_launch_flyby", global_position + Vector3(0, 6, -track_length), 1.0, 160.0)


# ---- build ------------------------------------------------------------------------------------------

func _build() -> void:
	var vis := AABB(Vector3(-20, -lift_depth - 4, -track_length - 260), Vector3(40, 120, track_length + 290))
	# the lift: a flush deck plate with a hazard-striped rim (solid), and the pit under it (deadly)
	_lift = AnimatableBody3D.new()
	_lift.sync_to_physics = false
	_lift.collision_layer = 1
	_lift.collision_mask = 0
	var ls := BoxShape3D.new()
	ls.size = lift_size
	var lcs := CollisionShape3D.new()
	lcs.shape = ls
	_lift.add_child(lcs)
	_lift.add_child(Look.box(lift_size, Look.flat(Color(0.34, 0.36, 0.38), 0.85, 0.2)))
	var ya: StandardMaterial3D = Look.flat(YELLOW, 0.6, 0.0, 0.2)
	var yb: StandardMaterial3D = Look.flat(Color(0.08, 0.08, 0.08), 0.7)
	for side: float in [-1.0, 1.0]:
		var n: int = int(lift_size.z / 1.2)
		for i: int in n:
			var b := Look.box(Vector3(0.35, 0.02, lift_size.z / float(n)), ya if i % 2 == 0 else yb,
				Vector3(side * (lift_size.x * 0.5 - 0.2), lift_size.y * 0.5 + 0.005, -lift_size.z * 0.5 + (float(i) + 0.5) * lift_size.z / float(n)))
			b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_lift.add_child(b)
	# the lift's ram (visible when it sinks)
	_lift.add_child(Look.cylinder(1.0, lift_depth + 2.0, Look.flat(Color(0.75, 0.77, 0.8), 0.25, 0.9), Vector3(0, -(lift_depth + 2.0) * 0.5, 0)))
	add_child(_lift)
	_pit_kill = Area3D.new()
	_pit_kill.collision_layer = 0
	_pit_kill.collision_mask = 2
	_pit_kill.monitorable = false
	var ps := BoxShape3D.new()
	ps.size = Vector3(lift_size.x - 0.5, lift_depth + 1.0, lift_size.z - 0.5)
	var pcs := CollisionShape3D.new()
	pcs.shape = ps
	_pit_kill.add_child(pcs)
	_pit_kill.position = Vector3(0, -0.8 - (lift_depth + 1.0) * 0.5, 0)
	add_child(_pit_kill)
	# the pit walls (seen when the lift is down)
	var wall: StandardMaterial3D = Look.flat(Color(0.2, 0.21, 0.23), 0.8, 0.3)
	for sx: float in [-1.0, 1.0]:
		add_child(Look.box(Vector3(0.3, lift_depth + 0.6, lift_size.z), wall, Vector3(sx * (lift_size.x * 0.5 + 0.15), -(lift_depth + 0.6) * 0.5 - 0.02, 0)))
	for sz: float in [-1.0, 1.0]:
		add_child(Look.box(Vector3(lift_size.x, lift_depth + 0.6, 0.3), wall, Vector3(0, -(lift_depth + 0.6) * 0.5 - 0.02, sz * (lift_size.z * 0.5 + 0.15))))
	add_child(Look.box(Vector3(lift_size.x, 0.3, lift_size.z), Look.flat(Color(0.1, 0.1, 0.11), 0.9), Vector3(0, -lift_depth - lift_size.y - 0.4, 0)))
	# the jet (visual) and its solid fuselage while it sits (so you cannot walk through a parked jet)
	_jet = CarrierCraft.jet(false)
	add_child(_jet)
	_jet_body = AnimatableBody3D.new()
	_jet_body.sync_to_physics = false
	_jet_body.collision_mask = 0
	var js := BoxShape3D.new()
	js.size = Vector3(3.4, 2.4, 15.0)
	var jcs := CollisionShape3D.new()
	jcs.shape = js
	jcs.position = Vector3(0, 2.0, 0.4)
	_jet_body.add_child(jcs)
	add_child(_jet_body)
	_jet_kill = Area3D.new()
	_jet_kill.collision_layer = 0
	_jet_kill.collision_mask = 2
	_jet_kill.monitorable = false
	var ks := BoxShape3D.new()
	ks.size = Vector3(lane_width, 3.4, KILL_HALF * 2.0)
	var kcs := CollisionShape3D.new()
	kcs.shape = ks
	_jet_kill.add_child(kcs)
	add_child(_jet_kill)
	# burner cones out of the nozzles
	_cone_mat = Look.flat(Color(1.0, 0.55, 0.25), 0.3, 0.0, 0.5).duplicate() as StandardMaterial3D
	_cone_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cone_mat.albedo_color = Color(1.0, 0.62, 0.32, 0.6)
	_cone_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cone_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_cone_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for sx: float in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(sx * 0.62, 2.0, 7.35)
		_jet.add_child(pivot)
		var cm := CylinderMesh.new()
		cm.top_radius = 0.05
		cm.bottom_radius = 0.48
		cm.height = 3.0
		cm.radial_segments = 12
		cm.rings = 1
		var cone := Look.mesh_node(cm, _cone_mat)
		cone.rotation.x = PI * 0.5
		cone.position = Vector3(0, 0, 1.5)
		cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(cone)
		_cones.append(pivot)
	_trail = Fx.emitter({"amount": 70, "lifetime": 1.1, "emitting": false, "fixed_fps": 0, "shape": "sphere", "radius": 0.5,
		"speed": Vector2(0.0, 1.0), "spread": 180.0, "tex": Fx.Tex.SMOKE, "additive": false, "size": 2.2, "curve": "puff",
		"color": Color(0.8, 0.8, 0.8, 0.35), "fade": PackedFloat32Array([0.6, 0.4, 0.0]), "angle": Vector2(0, 360), "aabb": vis})
	_trail.position = Vector3(0, 2.0, 8.0)
	_trail.top_level = false
	_jet.add_child(_trail)
	# the deflector: a hinged panel behind the tail (solid), with cooling-water ribs
	_jbd = AnimatableBody3D.new()
	_jbd.sync_to_physics = false
	_jbd.collision_layer = 1
	_jbd.collision_mask = 0
	_jbd.position = Vector3(0, 0.02, jbd_z)
	var bs := BoxShape3D.new()
	bs.size = Vector3(jbd_size.x, 0.3, jbd_size.y)
	var bcs := CollisionShape3D.new()
	bcs.shape = bs
	bcs.position = Vector3(0, 0.15, jbd_size.y * 0.5)
	_jbd.add_child(bcs)
	var jbd_mat: StandardMaterial3D = Look.flat(Color(0.5, 0.52, 0.55), 0.55, 0.5)
	_jbd.add_child(Look.box(Vector3(jbd_size.x, 0.3, jbd_size.y), jbd_mat, Vector3(0, 0.15, jbd_size.y * 0.5)))
	var rib: StandardMaterial3D = Look.flat(Color(0.36, 0.38, 0.4), 0.5, 0.6)
	var nr: int = int(jbd_size.x / 1.25)
	for i: int in nr:
		_jbd.add_child(Look.box(Vector3(0.14, 0.12, jbd_size.y - 0.3), rib, Vector3(-jbd_size.x * 0.5 + 0.6 + float(i) * 1.25, 0.34, jbd_size.y * 0.5)))
	for sx: float in [-1.0, 1.0]:
		_jbd.add_child(Look.box(Vector3(0.5, 0.36, jbd_size.y), Look.flat(YELLOW, 0.5, 0.1, 0.2), Vector3(sx * (jbd_size.x * 0.5 - 0.25), 0.18, jbd_size.y * 0.5)))
	add_child(_jbd)
	_deflect = Fx.smoke({"amount": 36, "lifetime": 1.4, "one_shot": false, "explosiveness": 0.0, "emitting": false,
		"shape": "box", "extents": Vector3(jbd_size.x * 0.4, 0.3, 0.3), "offset": Vector3(0, 1.6, jbd_z + 0.5),
		"dir": Vector3(0, 1, 0.5), "spread": 20.0, "speed": Vector2(4.0, 8.0), "damping": Vector2(1.0, 2.0),
		"size": 2.4, "color": Color(0.85, 0.84, 0.82, 0.3), "aabb": vis})
	add_child(_deflect)
	# the catapult track down the lane, and its shuttle
	var slot := Look.box(Vector3(0.36, 0.04, track_length), Look.flat(Color(0.05, 0.05, 0.06), 0.8), Vector3(0, 0.01, -track_length * 0.5 - 3.0))
	slot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(slot)
	_shuttle = Node3D.new()
	add_child(_shuttle)
	_shuttle.add_child(Look.box(Vector3(0.5, 0.2, 1.3), Look.flat(Color(0.2, 0.21, 0.22), 0.4, 0.8), Vector3(0, 0.08, 0)))
	_shuttle.add_child(Look.box(Vector3(0.16, 0.34, 0.3), Look.flat(YELLOW, 0.5, 0.2, 0.4), Vector3(0, 0.28, -0.45)))
	_steam = Fx.smoke({"amount": int(clampf(track_length * 0.9, 20, 80)), "lifetime": 2.0, "one_shot": false,
		"explosiveness": 0.0, "emitting": false, "shape": "box", "extents": Vector3(0.25, 0.05, track_length * 0.5),
		"offset": Vector3(0, 0.1, -track_length * 0.5 - 3.0), "dir": Vector3.UP, "spread": 18.0, "speed": Vector2(1.0, 3.0),
		"size": 1.8, "color": Color(0.96, 0.97, 1.0, 0.5), "aabb": vis})
	add_child(_steam)
	_shot = Fx.smoke({"amount": 60, "lifetime": 1.8, "shape": "box", "extents": Vector3(1.5, 0.2, 2.0), "offset": Vector3(0, 0.3, -5.0),
		"dir": Vector3(0, 0.6, 1), "spread": 60.0, "speed": Vector2(4.0, 11.0), "damping": Vector2(2.0, 3.5),
		"size": 3.0, "color": Color(1, 1, 1, 0.75), "aabb": vis})
	add_child(_shot)
	_shot_sparks = Fx.sparks({"amount": 30, "offset": Vector3(0, 0.2, -6.0), "dir": Vector3(0, 0.4, -1), "spread": 30.0,
		"speed": Vector2(8.0, 18.0), "color": Color(3.0, 2.2, 1.0), "aabb": vis})
	add_child(_shot_sparks)
	# shooter lamps down both edges of the lane
	_lamp_on = Look.flat(YELLOW, 0.3, 0.0, 3.0)
	_lamp_off = Look.flat(YELLOW.darkened(0.6), 0.4, 0.0, 0.15)
	var nl: int = int(track_length / 10.0)
	for sx: float in [-1.0, 1.0]:
		for i: int in nl:
			var lamp := Look.box(Vector3(0.35, 0.08, 0.35), _lamp_off, Vector3(sx * (lane_width * 0.5 + 0.1), 0.04, -8.0 - float(i) * 10.0))
			lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(lamp)
			_lamps.append(lamp)
