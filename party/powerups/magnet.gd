extends PowerUp
## Mega Magnet (5 s): a huge horseshoe magnet hums over your head and drags every rival within
## range toward you - off narrow beams, into gaps, into your Shove.
## Victim-side: each client's copy of the magnet (the mirror on the owner's ghost) pulls that
## client's OWN Player, so nothing extra crosses the network; the owner's copy pulls dummies.

const RANGE: float = 11.0
## Drift speed (m/s) toward the magnet at the edge of its range; up to 1.8x close in.
const PULL: float = 4.0
const RED := Color(1.0, 0.2, 0.25)

var _t: float = 0.0
var _ring_t: float = 0.0
var _magnet: Node3D


func _init() -> void:
	duration = 5.0


func build_look() -> void:
	_magnet = Node3D.new()
	_magnet.position = Vector3(0, 1.75, 0)
	add_child(_magnet)
	var red: StandardMaterial3D = PartyFx.solid_mat(RED, 0.6, 0.35, 0.3)
	var steel: StandardMaterial3D = PartyFx.solid_mat(Color(0.85, 0.88, 0.95), 0.4, 0.2, 0.9)
	# the U: an arc of blocks and two legs pointing down, silver tips
	for i: int in 7:
		var a: float = PI * float(i) / 6.0
		PartyFx.part(_magnet, PartyFx.box_mesh(Vector3(0.2, 0.2, 0.22)), red, Vector3(cos(a) * 0.36, sin(a) * 0.36, 0), Vector3.ONE, Vector3(0, 0, rad_to_deg(a)))
	for sx: float in [-1.0, 1.0]:
		PartyFx.part(_magnet, PartyFx.box_mesh(Vector3(0.2, 0.34, 0.22)), red, Vector3(sx * 0.36, -0.17, 0))
		PartyFx.part(_magnet, PartyFx.box_mesh(Vector3(0.21, 0.14, 0.23)), steel, Vector3(sx * 0.36, -0.4, 0))
	# field: sparks sucked in from a wide shell, a glow under the tips
	var field: GPUParticles3D = PartyFx.emitter({"amount": 90, "lifetime": 0.7, "size": 0.14, "color": Color(1.0, 0.5, 0.55),
		"shape": "shell", "radius": RANGE * 0.7, "vmin": 0.0, "vmax": 0.2, "radial": -RANGE * 2.6, "spark": true,
		"shrink": false, "aabb": RANGE + 3.0, "colors": [Color(0.5, 0.6, 1.0, 0.0), Color(1.0, 0.4, 0.5, 1.0), Color(1, 1, 1, 0.2)]})
	field.position = Vector3(0, 0.8, 0)
	add_child(field)
	var tips: GPUParticles3D = PartyFx.emitter({"amount": 24, "lifetime": 0.3, "size": 0.2, "color": Color(0.7, 0.8, 1.0),
		"shape": "box", "extents": Vector3(0.45, 0.05, 0.1), "vmin": 0.5, "vmax": 1.5, "dir": Vector3.DOWN, "spread": 30.0,
		"aabb": 3.0})
	tips.position = Vector3(0, -0.5, 0)
	_magnet.add_child(tips)
	if is_inside_tree():
		PartyFx.burst(world(), global_position + Vector3(0, 1.7, 0), RED, 40, 6.0, 0.25)
		PartyFx.flash(world(), global_position + Vector3(0, 1.7, 0), RED, 6.0, 8.0, 0.4)


func begin() -> void:
	layer.sfx.play("clank", 1.0, 0.7)


func _process(dt: float) -> void:
	_t += dt
	if _magnet != null:
		_magnet.position.y = 1.75 + sin(_t * 6.0) * 0.06
		_magnet.rotation.z = sin(_t * 23.0) * 0.04
	_ring_t -= dt
	if _ring_t <= 0.0 and is_inside_tree():
		_ring_t = 0.35
		# field lines: rings closing in on the wearer
		PartyFx.ring_pulse(world(), global_position + Vector3(0, 0.25, 0), Vector3.UP, Color(1.0, 0.35, 0.4, 0.8), RANGE * 0.8, 0.8, 0.5, 0.05)


## Drift toward the magnet (m/s): stronger close in. Applied as a slide of the body, not a
## velocity change, so running away only slows you down - and standing still gets you dragged.
static func pull_vector(from: Vector3, magnet_at: Vector3, _grounded: bool) -> Vector3:
	var to: Vector3 = magnet_at - from
	to.y = 0.0
	var dist: float = to.length()
	if dist > RANGE or dist < 0.9:
		return Vector3.ZERO
	return to.normalized() * PULL * (1.0 + 0.8 * (1.0 - dist / RANGE))


func tick(dt: float) -> void:
	# the owner's copy drags the practice dummies
	for d: PracticeDummy in layer.dummies:
		if not is_instance_valid(d) or d.knocked_out:
			continue
		var v: Vector3 = pull_vector(d.global_position, feet(), d.grounded)
		if v != Vector3.ZERO:
			d.global_position += v * dt
			d.grounded = false   # re-checks the ground: dragged past an edge, it drops
			if not d.has_meta("magnet_hit"):
				d.set_meta("magnet_hit", true)
				d.take_hit(Vector3.ZERO, {"s": "magnet", "add": true})
				layer.hit_landed.emit(d.id, "magnet")


func remote_tick(dt: float) -> void:
	# a mirror on a rival's ghost: its field pulls OUR player (victim-side)
	if not layer.is_rival(owner_id) or not layer.local_vulnerable():
		return
	var p: Player = layer.player
	var v: Vector3 = pull_vector(p.global_position, body.global_position, p.grounded)
	if v == Vector3.ZERO:
		return
	p.move_and_collide(v * dt)
	layer.mark_hit(owner_id)


func on_end() -> void:
	if layer != null:
		for d: PracticeDummy in layer.dummies:
			if is_instance_valid(d) and d.has_meta("magnet_hit"):
				d.remove_meta("magnet_hit")
	if is_inside_tree():
		PartyFx.burst(world(), global_position + Vector3(0, 1.7, 0), RED, 24, 4.0, 0.2)
