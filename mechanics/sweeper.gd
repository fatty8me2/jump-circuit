class_name Sweeper
extends Node3D
## Rotating kill bars around a hub (the classic obby spinner). Angle is a pure
## function of Game.course_time. Low bars are jumped; `bar_count` sets how often
## one comes round.

@export var arm_length: float = 5.0
@export var bar_count: int = 2
@export var period: float = 4.0
@export var phase: float = 0.0
@export var bar_height: float = 0.45
@export var bar_thickness: float = 0.5

var _pivot: Node3D
var _tips: Array[Node3D] = []
var _swooshes: Array[Swoosh] = []
# sound (side effect only): seconds until each bar next sweeps past the player
var _eta: Array[float] = []

## Seconds before a bar reaches the player that its whoosh starts (the clip peaks ~0.22 s in).
const WHOOSH_LEAD: float = 0.21


func _ready() -> void:
	_pivot = Node3D.new()
	add_child(_pivot)
	add_child(Look.cylinder(0.5, bar_height + 0.6, Look.flat(Color(0.14, 0.15, 0.2), 0.4, 0.7), Vector3(0, (bar_height + 0.6) * 0.5, 0), 0.4, 12))
	for i: int in bar_count:
		var holder := Node3D.new()
		holder.rotation.y = TAU * float(i) / float(bar_count)
		_pivot.add_child(holder)
		var kz := KillZone.new()
		kz.size = Vector3(arm_length, bar_thickness, bar_thickness)
		kz.position = Vector3(arm_length * 0.5 + 0.3, bar_height, 0)
		kz.embers = false        # the sweep trail below is its effect
		holder.add_child(kz)
		# a glowing wake swept out behind the bar (world-space dots left in its path)
		var wake: GPUParticles3D = Fx.trail({"amount": clampi(int(arm_length * 7.0), 14, 44), "lifetime": 0.32,
			"shape": "box", "extents": Vector3(arm_length * 0.5, bar_thickness * 0.3, bar_thickness * 0.3),
			"size": bar_thickness * 1.1, "color": Color(2.2, 0.55, 0.3, 0.6), "emitting": true,
			"fade": PackedFloat32Array([0.7, 0.0]),
			"aabb": AABB(Vector3(-arm_length - 2.0, -2.0, -arm_length - 2.0), Vector3(arm_length * 2.0 + 4.0, 4.0, arm_length * 2.0 + 4.0))})
		wake.position = kz.position
		holder.add_child(wake)
		# a hot ribbon traced by the bar's tip (the fastest, most dangerous point)
		var tip := Node3D.new()
		tip.position = Vector3(arm_length + 0.25, bar_height, 0)
		holder.add_child(tip)
		_tips.append(tip)
		var sw: Swoosh = Swoosh.make(Color(1.0, 0.2, 0.05, 0.9), bar_thickness * 0.6, 0.3, false)
		sw.spacing = 0.1
		add_child(sw)
		_swooshes.append(sw)
	_apply()
	add_to_group("course_clock")


## restart_run() winds the clock back in place: take the new pose now, without a streak.
func snap_to_clock() -> void:
	_apply()
	reset_physics_interpolation()
	for s: Swoosh in _swooshes:
		s.clear()


func _process(dt: float) -> void:
	for i: int in _tips.size():
		_swooshes[i].feed(_tips[i].global_position, true, dt)
	if WorldAudio.enabled():
		_whoosh_past_player()


## A whoosh each time a bar is about to sweep past a player standing within its reach
## (timed so the rush peaks as the bar goes by). Sound only.
func _whoosh_past_player() -> void:
	var pl: Node3D = WorldAudio.local_player(self)
	_eta.resize(bar_count)
	if pl == null:
		return
	var rel: Vector3 = to_local(pl.global_position)
	var r: float = Vector2(rel.x, rel.z).length()
	var near: bool = r < arm_length + 1.2 and r > 0.4 and absf(rel.y - bar_height) < 2.5
	var ang_p: float = atan2(-rel.z, rel.x)
	var omega: float = TAU / period
	for i: int in bar_count:
		var bar_ang: float = _pivot.rotation.y + TAU * float(i) / float(bar_count)
		# (a sweeper may spin either way)
		var eta: float = (fposmod(ang_p - bar_ang, TAU) if omega > 0.0 else fposmod(bar_ang - ang_p, TAU)) / absf(omega)
		if near and _eta[i] > WHOOSH_LEAD and eta <= WHOOSH_LEAD:
			var at: Vector3 = to_global(Vector3(cos(ang_p) * r, bar_height, -sin(ang_p) * r))
			WorldAudio.at(self, "sweep_whoosh", at, 0.8, 30.0, 0.08)
		_eta[i] = eta


func angle_at(time: float) -> float:
	return fposmod(time / period + phase, 1.0) * TAU


func _apply() -> void:
	_pivot.rotation.y = angle_at(Game.course_time)


func _physics_process(_dt: float) -> void:
	_apply()
