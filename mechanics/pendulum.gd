class_name Pendulum
extends Node3D
## Swinging hammer. It does not kill: it HITS - the player is thrown along the
## swing at the head speed plus a kick. Deterministic from Game.course_time.
## Swings side to side along local X (rotate the node to re-aim it).

@export var length: float = 7.0
@export var swing_deg: float = 55.0
@export var period: float = 3.2
@export var phase: float = 0.0
@export var head_radius: float = 1.1
@export var kick: float = 9.0

var _arm: Node3D
var _area: Area3D
var _cool: float = 0.0
# effects (visual only): a smear of glow left behind the head, strongest at the bottom
var _smear: GPUParticles3D
var _swooshes: Array[Swoosh] = []
var _rims: Array[Node3D] = []
# sound (side effect only): seconds until the head next passes the bottom of its swing
var _eta: float = -1.0

## The whoosh starts this long before the head passes the bottom (the clip peaks ~0.35 s in).
const WHOOSH_LEAD: float = 0.34


func _ready() -> void:
	_arm = Node3D.new()
	add_child(_arm)
	var metal: StandardMaterial3D = Look.flat(Color(0.2, 0.21, 0.27), 0.35, 0.8)
	_arm.add_child(Look.cylinder(0.12, length, metal, Vector3(0, -length * 0.5, 0), -1.0, 10))
	var head := Look.cylinder(head_radius, head_radius * 1.5, Look.flat(Color(0.9, 0.25, 0.2), 0.4, 0.4, 0.6), Vector3(0, -length, 0), -1.0, 20)
	head.rotation.z = PI / 2.0
	_arm.add_child(head)
	add_child(Look.sphere(0.35, metal))
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 2
	_area.monitorable = false
	var s := SphereShape3D.new()
	s.radius = head_radius * 1.05
	var cs := CollisionShape3D.new()
	cs.shape = s
	_area.add_child(cs)
	_area.position = Vector3(0, -length, 0)
	_arm.add_child(_area)
	_apply(Game.course_time)
	add_to_group("course_clock")
	_smear = Fx.trail({"amount": 40, "lifetime": 0.22, "shape": "box",
		"extents": Vector3(head_radius * 0.7, head_radius * 0.75, head_radius * 0.75),
		"size": head_radius * 0.9, "curve": "shrink", "color": Color(1.4, 0.45, 0.35, 0.35),
		"fade": PackedFloat32Array([0.8, 0.0]), "emitting": true,
		"aabb": AABB(Vector3(-length * 2.0, -length * 1.5, -length), Vector3(length * 4.0, length * 2.0, length * 2.0))})
	_smear.position = Vector3(0, -length, 0)
	_smear.amount = maxi(1, _smear.amount / 2)
	_arm.add_child(_smear)
	# two arcs of light swept by the head's front and back rims
	for sz: float in [-1.0, 1.0]:
		var rim := Node3D.new()
		rim.position = Vector3(0, -length - head_radius * 0.55, sz * head_radius * 0.62)
		_arm.add_child(rim)
		_rims.append(rim)
		var sw: Swoosh = Swoosh.make(Color(1.0, 0.25, 0.15, 0.85), head_radius * 0.42, 0.28, false)
		sw.spacing = 0.12
		add_child(sw)
		_swooshes.append(sw)


func _process(dt: float) -> void:
	# fraction of the top swing speed right now
	var w: float = absf(cos(TAU * (Game.course_time / period + phase)))
	_smear.amount_ratio = clampf((w - 0.25) / 0.75, 0.0, 1.0)
	var fast: bool = w > 0.35
	for i: int in _swooshes.size():
		_swooshes[i].feed(_rims[i].global_position, fast, dt)
	if WorldAudio.enabled():
		# the head passes the bottom twice a period; whoosh as it comes through
		var half: float = period * 0.5
		var eta: float = half - fposmod(Game.course_time + phase * period, half)
		if _eta > WHOOSH_LEAD and eta <= WHOOSH_LEAD:
			WorldAudio.at(self, "pendulum_whoosh", global_position - global_basis.y * length, 0.8, 30.0, 0.06)
		_eta = eta


## restart_run() winds the clock back in place: take the new pose now, without a streak.
func snap_to_clock() -> void:
	_apply(Game.course_time)
	reset_physics_interpolation()
	for s: Swoosh in _swooshes:
		s.clear()


func angle_at(time: float) -> float:
	return deg_to_rad(swing_deg) * sin(TAU * (time / period + phase))


func _apply(time: float) -> void:
	_arm.rotation.z = angle_at(time)


func _physics_process(dt: float) -> void:
	var t: float = Game.course_time
	_apply(t)
	_cool = maxf(_cool - dt, 0.0)
	if _cool > 0.0:
		return
	for body: Node3D in _area.get_overlapping_bodies():
		if body is Player:
			var w: float = deg_to_rad(swing_deg) * cos(TAU * (t / period + phase)) * TAU / period
			var tangent: Vector3 = global_basis * (Basis(Vector3.BACK, angle_at(t)) * Vector3.RIGHT)
			var dir: Vector3 = tangent * signf(w)
			if absf(w) < 0.05:
				dir = (body.global_position - _area.global_position).normalized()
			var p := body as Player
			p.knockback(dir * (absf(w) * length + kick) + Vector3(0, 7.0, 0))
			_cool = 0.5
			Sfx.play_at("whack", _area.global_position, 0.08, 1.0)
