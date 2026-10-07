class_name PartyDecoy
extends Node3D
## The Decoy's body: a second "you", wearing your character, name and cosmetics, that sprints
## up the course ahead of you for a few seconds. To a rival it is just another racer - shells chase
## it, shoves and claws land on it - and it soaks up exactly one hit: the first blow (or blast, or
## shell) pops it in a cloud of confetti and the real owner is spared.
## Every screen spawns and walks it from the owner's "drop" event (same waypoints, same speed, so
## it runs in the same place everywhere). It stands in layer.targets() as {decoy: true} for
## everyone except its owner and their team; whoever hits it tells all screens ("hz") to pop it.

const LIFE: float = 10.0
const SPEED: float = 7.0
## A step this much higher than the last ground ends the run (it has hit a wall).
const MAX_STEP: float = 0.8

var layer: PartyLayer
var owner_id: int = 0
var key: String = ""
## Negative and unique per key: a target id that can never be a peer's (see id_for).
var id: int = -1000
var points: Array[Vector3] = []
## Parallel to points: true = the leg INTO that point is a jump (an arc), false = a run.
var air: Array[bool] = []
var vel: Vector3 = Vector3.ZERO
var grounded: bool = true
var popped: bool = false
var hits: int = 0
var _age: float = 0.0
var _wp: int = 1
var _leg_from: Vector3 = Vector3.ZERO
var _leg_len: float = -1.0
var _leg_t: float = 0.0
var _racer: RemoteRacer
var _stopped: bool = false


## Target id for a decoy key ("<owner>_<n>"): the same on every screen.
static func id_for(decoy_key: String) -> int:
	var parts: PackedStringArray = decoy_key.split("_")
	var owner: int = int(parts[0]) if parts.size() > 0 else 0
	var n: int = int(parts[1]) if parts.size() > 1 else 0
	return -(1000 + absi(owner) * 1000 + n % 1000)


func _ready() -> void:
	id = id_for(key)
	if layer != null:
		layer.hazards[key] = self
		layer.decoys.append(self)
	_racer = RemoteRacer.new()
	add_child(_racer)
	var mine: bool = owner_id == Net.my_id()
	var entry: Dictionary = Cosmetics.equipped_all() if mine else (Net.roster.get(owner_id, {}) as Dictionary)
	var nm: String = layer.racer_name(owner_id) if layer != null else "?"
	var friendly: bool = layer != null and not layer.is_rival(owner_id)
	var col: Color = Settings.my_color() if mine else (layer.team_color_of(owner_id) if layer != null else Color.WHITE)
	_racer.setup(("%s (decoy)" % nm) if friendly else nm, col)
	_racer.apply_cosmetics(entry)
	_racer.exact = true
	_racer.push_state(global_position, Vector3.ZERO, true, 0)
	if friendly:
		# its owner (and their team) can tell: a faint see-through copy
		_fade(_racer.visual(), 0.45)
	# it appears in a puff, with a pop
	if is_inside_tree():
		spawn_fx(get_parent(), center())
		if layer != null:
			layer.sfx.play_at("decoy", center(), 0.9, 1.0)
	PartyFx.pop_in(_racer, 0.3)


func _fade(n: Node, amount: float) -> void:
	if n is MeshInstance3D:
		(n as MeshInstance3D).transparency = amount
	for c: Node in n.get_children():
		_fade(c, amount)


func center() -> Vector3:
	return global_position + Vector3(0, 0.8, 0)


func _physics_process(dt: float) -> void:
	if popped:
		return
	_age += dt
	if _age >= LIFE:
		consume(false, false)
		return
	visible = PartyFx.blink_on(LIFE - _age, 1.5)
	var dir := Vector3.ZERO
	if not _stopped and _wp < points.size() and layer != null:
		var tgt: Vector3 = points[_wp]
		if _wp < air.size() and air[_wp]:
			dir = _hop(tgt, dt)
		else:
			dir = _walk(tgt, dt)
	else:
		vel = Vector3.ZERO
	if _racer != null:
		_racer.push_state(global_position, vel, grounded, 0)
		_racer.set_exact_facing(dir if dir != Vector3.ZERO else Vector3(vel.x, 0, vel.z))


## A ground leg: run at the waypoint, hugging the floor; a wall or an edge ends the run.
func _walk(tgt: Vector3, dt: float) -> Vector3:
	var to: Vector3 = tgt - global_position
	to.y = 0.0
	if to.length() < 0.7:
		_wp += 1
		return Vector3.ZERO
	var dir: Vector3 = to.normalized()
	var next: Vector3 = global_position + dir * minf(SPEED * dt, to.length())
	var g: Dictionary = layer.ground_at(next + Vector3(0, 0.4, 0), 2.6)
	if g.is_empty() or (g["position"] as Vector3).y > global_position.y + MAX_STEP:
		_stopped = true   # the edge of the world, or a wall: it stands its ground
		vel = Vector3.ZERO
		return Vector3.ZERO
	next.y = (g["position"] as Vector3).y
	global_position = next
	vel = dir * SPEED
	grounded = true
	return dir


## A jump leg (the route's jumps): an arc to the landing spot at running pace.
func _hop(tgt: Vector3, dt: float) -> Vector3:
	if _leg_len < 0.0:
		_leg_from = global_position
		_leg_len = maxf(_leg_from.distance_to(tgt), 0.5)
		_leg_t = 0.0
	_leg_t += dt * SPEED * 1.2 / _leg_len
	var k: float = minf(_leg_t, 1.0)
	var p: Vector3 = _leg_from.lerp(tgt, k)
	p.y += sin(PI * k) * clampf(_leg_len * 0.22, 0.9, 3.0)
	var d: Vector3 = p - global_position
	vel = d / maxf(dt, 0.0001)
	global_position = p
	grounded = false
	if k >= 1.0:
		_wp += 1
		_leg_len = -1.0
		grounded = true
	var flat := Vector3(d.x, 0, d.z)
	return flat.normalized() if flat.length() > 0.001 else Vector3.ZERO


## A blow lands on the decoy: it pops instead of anybody being hurt, and everyone is told.
func take_hit(_kb: Vector3, _o: Dictionary = {}) -> void:
	if popped:
		return
	hits += 1
	consume(true, true)


## Popped (a hit) or timed out. `tell` = we popped it: let every other screen pop it too.
func consume(tell: bool, splash: bool = true) -> void:
	if popped:
		return
	popped = true
	if layer != null:
		if layer.hazards.get(key) == self:
			layer.hazards.erase(key)
		layer.decoys.erase(self)
	if tell:
		Net.send_party({"k": "hz", "h": key})
	visible = true
	if is_inside_tree():
		if splash:
			pop_fx(get_parent(), center())
			if layer != null:
				layer.sfx.play_at("pop", center(), 1.0, 0.9)
				if layer.is_rival(owner_id) == false and owner_id == Net.my_id():
					layer.hud.announce("Your decoy took the hit!", PartyNames.item_color("decoy"))
		else:
			PartyFx.smoke(get_parent(), center(), Color(0.85, 0.85, 0.9, 0.5), 10, 0.5, 0.9)
			PartyFx.burst(get_parent(), center(), Color(0.7, 0.8, 1.0), 16, 3.0, 0.2, 0.5)
	if _racer != null and is_instance_valid(_racer):
		_racer.visible = false
	get_tree().create_timer(0.4, false).timeout.connect(queue_free)


## A puff of smoke and a rubbery pop as the double appears.
static func spawn_fx(parent: Node, at: Vector3) -> void:
	PartyFx.smoke(parent, at, Color(0.9, 0.9, 0.95, 0.55), 14, 0.5, 0.9)
	PartyFx.burst(parent, at, Color(0.7, 0.85, 1.0), 24, 5.0, 0.22, 0.5)
	PartyFx.ring_pulse(parent, at - Vector3(0, 0.7, 0), Vector3.UP, Color(0.7, 0.85, 1.0), 0.2, 1.8, 0.3, 0.1)
	PartyFx.star_ring(parent, at, Color(0.9, 0.95, 1.0), 6, 3.5, 0.3)


## The decoy takes the hit: a bang of confetti and paper scraps, a ring and a "POOF!".
static func pop_fx(parent: Node, at: Vector3) -> void:
	PartyFx.orb_pulse(parent, at, Color(0.9, 0.95, 1.0, 0.6), 0.2, 1.4, 0.16, 2.5)
	PartyFx.confetti(parent, at, 90, 9.0, Vector3.UP, 85.0, 2.0)
	PartyFx.smoke(parent, at, Color(0.9, 0.9, 0.95, 0.6), 18, 0.6, 1.0)
	PartyFx.burst(parent, at, Color(0.7, 0.85, 1.0), 30, 6.0, 0.24, 0.5)
	PartyFx.star_ring(parent, at, Color(1.0, 0.9, 0.5), 8, 5.0, 0.4)
	PartyFx.ring_pulse(parent, at, Vector3.UP, Color(0.8, 0.9, 1.0), 0.3, 2.6, 0.35, 0.14)
	PartyFx.comic_burst(parent, at + Vector3(0, 0.9, 0), "POOF!", Color(0.7, 0.85, 1.0), 0.9)
