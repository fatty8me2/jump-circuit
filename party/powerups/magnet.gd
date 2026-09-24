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
var _tether_t: float = 0.0
var _magnet: Node3D
var _lines: Node3D
var _line_mat: StandardMaterial3D


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
	# field lines: glowing loops arcing out of one pole and back into the other
	_lines = Node3D.new()
	_magnet.add_child(_lines)
	_line_mat = PartyFx.fading_mat(Color(1.0, 0.45, 0.55, 0.55), 1.6)
	_line_mat.vertex_color_use_as_albedo = true
	for plane: int in 2:
		var holder := Node3D.new()
		holder.rotation.y = PI * 0.5 * float(plane)
		_lines.add_child(holder)
		for i: int in 3:
			var mi := MeshInstance3D.new()
			mi.mesh = _loop_mesh(0.35 + 0.3 * float(i), 0.3 + 0.45 * float(i))
			mi.material_override = _line_mat
			mi.layers = PartyFx.LAYER
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			holder.add_child(mi)
	# the field: sparks streaking in from all round, a glow under the tips
	var field: GPUParticles3D = PartyFx.emitter({"amount": 90, "lifetime": 0.7, "size": Vector2(0.05, 0.55), "color": Color(1.0, 0.5, 0.55),
		"tex": "streak", "facing": "velocity", "shape": "shell", "radius": RANGE * 0.7, "vmin": 0.0, "vmax": 0.2,
		"radial": -RANGE * 2.6, "shrink": false, "aabb": RANGE + 3.0,
		"colors": [Color(0.5, 0.6, 1.0, 0.0), Color(1.0, 0.4, 0.5, 1.0), Color(1, 1, 1, 0.2)]})
	field.position = Vector3(0, 0.8, 0)
	add_child(field)
	var tips: GPUParticles3D = PartyFx.emitter({"amount": 24, "lifetime": 0.3, "size": 0.2, "color": Color(0.7, 0.8, 1.0),
		"shape": "box", "extents": Vector3(0.45, 0.05, 0.1), "vmin": 0.5, "vmax": 1.5, "dir": Vector3.DOWN, "spread": 30.0,
		"aabb": 3.0})
	tips.position = Vector3(0, -0.5, 0)
	_magnet.add_child(tips)
	# grit and metal filings dragged in across the ground from the edge of the field
	var grit: GPUParticles3D = HeroFx.em({"amount": 40, "lifetime": 0.9, "shape": "ring", "ring_radius": RANGE * 0.8,
		"ring_inner": RANGE * 0.4, "speed": Vector2(0.0, 0.2), "radial": Vector2(-RANGE * 1.4, -RANGE * 1.0),
		"facing": "velocity", "tex": Fx.Tex.SPARK, "size": Vector2(0.05, 0.3), "additive": false,
		"color": Color(0.35, 0.33, 0.38, 0.8), "fade": PackedFloat32Array([0.0, 1.0, 0.6]), "box_aabb": RANGE + 3.0})
	grit.position = Vector3(0, 0.1, 0)
	add_child(grit)
	PartyFx.pop_in(_magnet, 0.45)
	if is_inside_tree():
		var top: Vector3 = global_position + Vector3(0, 1.7, 0)
		PartyFx.burst(world(), top, RED, 40, 6.0, 0.25)
		PartyFx.ring_pulse(world(), top, Vector3.UP, Color(1.0, 0.5, 0.55), 0.3, 3.0, 0.4, 0.1)
		PartyFx.star_ring(world(), top, Color(1.0, 0.85, 0.3), 6, 4.0, 0.3)
		PartyFx.flash(world(), top, RED, 6.0, 8.0, 0.4)


## One field-line loop under the magnet (its local XY plane): out of the left pole tip,
## bulging out and under, into the right one. A thin ribbon, doubled crosswise so it shows
## from any side; brighter near the poles.
static func _loop_mesh(bulge: float, depth: float) -> ImmediateMesh:
	var im := ImmediateMesh.new()
	for pass_i: int in 2:
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		var steps: int = 24
		for i: int in steps + 1:
			var th: float = PI * float(i) / float(steps)
			var p := Vector3(-cos(th) * (0.36 + bulge * sin(th)), -0.47 - sin(th) * depth, 0.0)
			var tang := Vector3(sin(th) * 0.36, -cos(th) * depth, 0.0).normalized()
			var side: Vector3 = Vector3(0, 0, 0.03) if pass_i == 0 else tang.cross(Vector3(0, 0, 1)) * 0.03
			var c := Color(1, 1, 1, 0.35 + 0.65 * absf(cos(th)))
			im.surface_set_color(c)
			im.surface_add_vertex(p - side)
			im.surface_set_color(c)
			im.surface_add_vertex(p + side)
		im.surface_end()
	return im


func begin() -> void:
	layer.sfx.play("clank", 1.0, 0.7)


## Seconds left as the owner sees it (a mirror runs a second longer as a safety).
func _left() -> float:
	return time_left - (0.0 if local else 1.0)


func _process(dt: float) -> void:
	_t += dt
	var left: float = _left()
	if _magnet != null:
		_magnet.position.y = 1.75 + sin(_t * 6.0) * 0.06
		_magnet.rotation.z = sin(_t * 23.0) * 0.04
		# running out: it blinks and sputters
		_magnet.visible = PartyFx.blink_on(left, 1.5)
	if _lines != null:
		_lines.rotation.y += dt * 1.2
		var pulse: float = 0.35 + 0.25 * sin(_t * 9.0)
		_line_mat.albedo_color.a = pulse if left > 1.5 else pulse * (0.4 if _magnet.visible else 0.1)
	_ring_t -= dt
	if _ring_t <= 0.0 and is_inside_tree():
		_ring_t = 0.35
		# field lines: rings closing in on the wearer
		PartyFx.ring_pulse(world(), global_position + Vector3(0, 0.25, 0), Vector3.UP, Color(1.0, 0.35, 0.45, 0.3), RANGE * 0.8, 0.8, 0.5, 0.04)
		if left < 1.5 and left > 0.0:
			PartyFx.sparks(world(), global_position + Vector3(0, 1.3, 0), Color(1.0, 0.8, 0.6), 8, 4.0)
		# an arc snaps between the poles now and then
		if _magnet != null and _magnet.visible and randf() < 0.5:
			var l: Vector3 = _magnet.global_transform * Vector3(-0.36, -0.5, 0)
			var r: Vector3 = _magnet.global_transform * Vector3(0.36, -0.5, 0)
			PartyFx.arc_between(world(), l, r, Color(1.2, 0.7, 1.0), 0.1)
	_tether_t -= dt
	if _tether_t <= 0.0 and is_inside_tree() and layer != null and not ended:
		_tether_t = 0.12
		_tethers()


## Sparks zipping from everyone caught in the field to the magnet (cosmetic: the same range
## test as the pull; the owner sees its targets, a rival sees their own racer dragged).
func _tethers() -> void:
	var top: Vector3 = global_position + Vector3(0, 1.3, 0)
	var froms: Array[Vector3] = []
	if local:
		for t: Dictionary in layer.targets():
			if pull_vector(t["pos"] as Vector3, feet(), true) != Vector3.ZERO:
				froms.append(t["center"] as Vector3)
	elif layer.player != null and layer.is_rival(owner_id) and layer.local_vulnerable():
		if pull_vector(layer.player.global_position, body.global_position, true) != Vector3.ZERO:
			froms.append(layer.player.global_position + Vector3(0, 0.8, 0))
	for f: Vector3 in froms:
		PartyFx.tether(world(), f, top, Color(1.2, 0.5, 0.6), 6, 12.0)


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
		# power gone: it sparks out, puffs smoke and sheds a few bolts
		var top: Vector3 = global_position + Vector3(0, 1.7, 0)
		PartyFx.burst(world(), top, RED, 24, 4.0, 0.2)
		PartyFx.sparks(world(), top + Vector3(0, -0.4, 0), Color(1.0, 0.85, 0.6), 16, 5.0, Vector3.DOWN, 60.0)
		PartyFx.smoke(world(), top, Color(0.35, 0.33, 0.36, 0.5), 10, 0.5, 1.0)
		PartyFx.debris(world(), top, Color(0.8, 0.82, 0.88), 6, 3.0, 0.1)
