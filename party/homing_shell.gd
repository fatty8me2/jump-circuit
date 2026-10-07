class_name HomingShell
extends Node3D
## The Homing Shell's flying body: a spiky green shell that curves after the racer ahead of its
## owner (or a decoy that looks like one). Every screen spawns it from the owner's "launch" event
## and steers it at the same target (a rival's ghost, or - on the target's own screen - the real
## Player), so it is drawn arriving everywhere. Only the owner's copy (local = true) decides the
## hit: it asks the layer to hit whatever it touches, then tells the others where it burst.

const SPEED_MAX: float = 23.0
const SPEED_START: float = 11.0
const ACCEL: float = 20.0
## Radians / second the shell can turn: tight enough to chase, loose enough to be outrun round a corner.
const TURN: float = 3.6
const LIFE: float = 6.0
const HIT_RADIUS: float = 1.1
const GREEN := Color(0.4, 1.0, 0.45)

var layer: PartyLayer
var owner_id: int = 0
var key: String = ""
var target_id: int = 0
var local: bool = false
var velocity: Vector3 = Vector3.ZERO
var age: float = 0.0
var done: bool = false
var _speed: float = SPEED_START
var _spin: Node3D
var _beeped: float = 0.0


func _ready() -> void:
	if layer != null and key != "":
		layer.hazards[key] = self
	_spin = Node3D.new()
	add_child(_spin)
	var shell_mat: StandardMaterial3D = PartyFx.solid_mat(Color(0.25, 0.85, 0.35), 0.9, 0.3, 0.2)
	shell_mat.rim_enabled = true
	shell_mat.rim = 0.8
	PartyFx.part(_spin, PartyFx.sphere_mesh(0.34, 18), shell_mat, Vector3.ZERO, Vector3(1.0, 0.8, 1.0))
	# the rim of the shell and the spikes
	var white: StandardMaterial3D = PartyFx.solid_mat(Color(0.97, 0.97, 0.9), 0.4, 0.4)
	PartyFx.part(_spin, PartyFx.cyl_mesh(0.4, 0.06, 0.4, 18), white, Vector3(0, -0.2, 0))
	for i: int in 6:
		var a: float = TAU * float(i) / 6.0
		PartyFx.part(_spin, PartyFx.cone_mesh(0.07, 0.2, 5), white, Vector3(cos(a) * 0.3, 0.2, sin(a) * 0.3), Vector3.ONE,
			Vector3(sin(a) * 40.0, 0, -cos(a) * 40.0))
	PartyFx.part(_spin, PartyFx.sphere_mesh(0.1, 8), PartyFx.glow_mat(Color(1, 1, 0.9, 0.9), 2.0, true), Vector3(0, 0.26, 0))
	# a glowing seeker halo and a wake of green sparks and speed streaks
	PartyFx.part(self, PartyFx.sphere_mesh(0.62, 14), PartyFx.glow_mat(Color(0.4, 1.0, 0.5, 0.16), 1.6, true), Vector3.ZERO)
	add_child(PartyFx.emitter({"amount": 46, "lifetime": 0.4, "size": 0.26, "color": Color(0.5, 1.4, 0.6), "vmin": 0.0, "vmax": 0.5,
		"aabb": 30.0, "fixed_fps": 0}))
	add_child(PartyFx.emitter({"amount": 26, "lifetime": 0.35, "size": Vector2(0.05, 0.55), "color": Color(0.8, 1.6, 0.9, 0.8),
		"tex": "streak", "facing": "velocity", "vmin": 0.0, "vmax": 0.4, "shrink": true, "aabb": 30.0, "fixed_fps": 0}))
	add_child(PartyFx.emitter({"amount": 14, "lifetime": 0.7, "size": 0.5, "color": Color(0.85, 0.95, 0.85, 0.5), "additive": false,
		"tex": "smoke", "vmin": 0.0, "vmax": 0.3, "grow": true, "angle": true, "aabb": 30.0, "fixed_fps": 0,
		"colors": [Color(1, 1, 1, 0.6), Color(1, 1, 1, 0)]}))
	scale = Vector3.ONE * 0.1
	create_tween().tween_property(self, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _physics_process(dt: float) -> void:
	if done:
		return
	age += dt
	if _spin != null:
		_spin.rotation.y += dt * 14.0
	var to_pos: Variant = null
	if layer != null:
		to_pos = layer.target_center(target_id)
	_speed = minf(_speed + ACCEL * dt, SPEED_MAX)
	var dir: Vector3 = velocity.normalized() if velocity.length() > 0.1 else Vector3.FORWARD
	if to_pos != null:
		var want: Vector3 = (to_pos as Vector3) - global_position
		if want.length() > 0.05:
			var wd: Vector3 = want.normalized()
			var ang: float = dir.angle_to(wd)
			if ang > 0.0005:
				dir = dir.slerp(wd, clampf(TURN * dt / ang, 0.0, 1.0)).normalized()
	velocity = dir * _speed
	global_position += velocity * dt
	# beeping gets faster the closer it is to its target
	_beeped -= dt
	if to_pos != null and layer != null and _beeped <= 0.0:
		var near: float = clampf(global_position.distance_to(to_pos as Vector3) / 30.0, 0.0, 1.0)
		_beeped = lerpf(0.12, 0.45, near)
		PartyFx.sparks(layer, global_position, Color(0.6, 1.5, 0.7), 4, 3.0)
	if local and layer != null:
		for t: Dictionary in layer.targets_in_sphere(global_position, HIT_RADIUS):
			_strike(t)
			return
		if age >= LIFE:
			end(global_position, false)
	elif age >= LIFE + 0.8:
		end(global_position, false)


## The owner's shell touched `t`: the layer delivers the blow (which a Balloon Shield or respawn
## protection may refuse on their side), then everyone sees it burst.
func _strike(t: Dictionary) -> void:
	var flat := Vector3(velocity.x, 0, velocity.z)
	var dir: Vector3 = flat.normalized() if flat.length() > 0.1 else Vector3.FORWARD
	layer.hit(t, dir * 9.0 + Vector3(0, 8.5, 0), {"st": 1.3, "e": "spin", "ed": 1.3, "s": "homing", "quiet": true})
	PartyFx.shake(layer.level, 0.25)
	var at: Vector3 = global_position
	layer.send_fx("homing", "boom", {"k": key, "at": PowerUp.arr(at), "hit": true})
	end(at, true)


## Ends the flight (the owner's "boom" message calls this on the remote copies).
func end(at: Vector3, hit: bool) -> void:
	if done:
		return
	done = true
	global_position = at
	if layer != null and layer.hazards.get(key) == self:
		layer.hazards.erase(key)
	if layer != null and is_inside_tree():
		if hit:
			burst_fx(layer, at)
			layer.sfx.play_at("boom", at, 0.6, 1.5)
		else:
			PartyFx.smoke(layer, at, Color(0.7, 0.9, 0.7, 0.5), 8, 0.4, 0.8)
			PartyFx.burst(layer, at, GREEN, 14, 3.0, 0.2, 0.4)
			layer.sfx.play_at("pop", at, 0.7, 0.8)
	for c: Node in find_children("*", "GPUParticles3D", true, false):
		(c as GPUParticles3D).emitting = false
	for c: Node in find_children("*", "MeshInstance3D", true, false):
		(c as MeshInstance3D).visible = false
	set_physics_process(false)
	get_tree().create_timer(1.0, false).timeout.connect(queue_free)


## The pop on impact: a green-white flash, a ring of stars, shell shards and spikes flying.
static func burst_fx(parent: Node, at: Vector3) -> void:
	PartyFx.explosion(parent, at, Color(0.9, 1.0, 0.8), GREEN, 2.2)
	PartyFx.orb_pulse(parent, at, Color(0.85, 1.0, 0.85, 0.6), 0.2, 1.6, 0.18, 2.5)
	PartyFx.burst(parent, at, GREEN, 36, 7.0, 0.26, 0.6)
	PartyFx.star_ring(parent, at, Color(0.7, 1.0, 0.55), 9, 6.0, 0.4)
	PartyFx.shards(parent, at, Color(0.35, 0.9, 0.4), 14, 8.0, 0.16)
	PartyFx.ring_pulse(parent, at, Vector3.UP, GREEN, 0.3, 3.0, 0.35, 0.16)
	PartyFx.flash(parent, at, GREEN, 6.0, 7.0, 0.3)
	PartyFx.comic_burst(parent, at + Vector3(0, 1.0, 0), "BONK!", Color(0.55, 1.0, 0.45), 0.9)
