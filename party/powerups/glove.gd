extends PowerUp
## Spring Glove (instant): a big red boxing glove on a coiled spring shoots out of your pack,
## auto-aimed at the nearest rival in front, and punches them into next week. "POW!"

const REACH: float = 7.5
const RED := Color(1.0, 0.18, 0.15)


func begin() -> void:
	var o: Vector3 = chest()
	var dir: Vector3 = layer.aim_dir()
	var tg: Dictionary = layer.nearest_in_cone(o, dir, REACH + 1.0, 0.75)
	if tg.is_empty():
		tg = layer.nearest_in_cone(o, layer.melee_dir(REACH), REACH + 1.0, 0.75)
	if not tg.is_empty():
		dir = ((tg["center"] as Vector3) - o).normalized()
	var reach: float = REACH
	var wall: Dictionary = layer.ray(o, o + dir * REACH)
	if not wall.is_empty():
		reach = o.distance_to(wall["position"]) - 0.2
	_punch_fx(layer, o, dir, reach)
	layer.sfx.play("spring", 1.0, 1.0)
	fx("punch", {"o": arr(o), "d": arr(dir), "r": reach})
	var hits: Array[Dictionary] = layer.targets_near_segment(o, o + dir * (reach + 0.4), 1.1)
	var best: Dictionary = {}
	var best_d: float = INF
	for t: Dictionary in hits:
		var dd: float = (t["center"] as Vector3).distance_to(o)
		if dd < best_d:
			best_d = dd
			best = t
	if not best.is_empty():
		var flat := Vector3(dir.x, 0, dir.z).normalized()
		layer.hit(best, flat * 24.0 + Vector3(0, 10.0, 0), {"st": 0.5, "s": "glove"})
		PartyFx.comic_burst(layer, (best["center"] as Vector3) + Vector3(0, 1.4, 0), "POW!", Color(1.0, 0.8, 0.15), 1.0)
		PartyFx.shake(layer.level, 0.25)
	finish()


## The glove shoots out along `dir` for `reach` m and snaps back (a self-freeing node):
## a tiny wind-up, a rocket out with speed lines and a trail, a BOING wobble on the spring
## at full stretch, then a quick reel-in.
static func _punch_fx(parent: Node, o: Vector3, dir: Vector3, reach: float) -> void:
	var root := Node3D.new()
	parent.add_child(root)
	root.global_transform = Transform3D(PartyFx.facing(dir), o)
	var head := Node3D.new()
	root.add_child(head)
	var red: StandardMaterial3D = PartyFx.solid_mat(RED, 0.5, 0.35)
	PartyFx.part(head, PartyFx.sphere_mesh(0.34, 16), red, Vector3(0, 0, -0.1), Vector3(1.0, 0.9, 1.1))
	PartyFx.part(head, PartyFx.sphere_mesh(0.14, 10), red, Vector3(-0.3, 0.05, -0.02), Vector3(1, 0.8, 1.4))
	PartyFx.part(head, PartyFx.cyl_mesh(0.2, 0.18), PartyFx.solid_mat(Color(0.95, 0.95, 0.95), 0.2), Vector3(0, 0, 0.26), Vector3.ONE, Vector3(90, 0, 0))
	# a glossy highlight and a laced seam so it reads as a boxing glove
	PartyFx.part(head, PartyFx.sphere_mesh(0.08, 8), PartyFx.glow_mat(Color(1, 1, 1, 0.55), 1.5, true), Vector3(0.12, 0.2, -0.25), Vector3(1.2, 0.7, 1))
	PartyFx.part(head, PartyFx.box_mesh(Vector3(0.05, 0.03, 0.3)), PartyFx.solid_mat(Color(0.95, 0.9, 0.85), 0.3), Vector3(0, 0.3, 0.02))
	# the spring: rings stretched between the pack and the glove
	var coils: Array[MeshInstance3D] = []
	var tm := TorusMesh.new()
	tm.inner_radius = 0.1
	tm.outer_radius = 0.14
	tm.rings = 12
	tm.ring_segments = 4
	var steel: StandardMaterial3D = PartyFx.solid_mat(Color(0.8, 0.82, 0.88), 0.2, 0.25, 0.9)
	for i: int in 10:
		coils.append(PartyFx.part(root, tm, steel, Vector3.ZERO, Vector3.ONE, Vector3(90, 0, 0)))
	var trail: GPUParticles3D = PartyFx.emitter({"amount": 30, "lifetime": 0.25, "size": 0.3, "color": Color(1.0, 0.5, 0.3),
		"vmin": 0.0, "vmax": 0.4, "aabb": 12.0, "fixed_fps": 0})
	head.add_child(trail)
	var ext := func(k: float) -> void:
		if not is_instance_valid(head):
			return
		var z: float = -reach * k
		head.position = Vector3(0, 0, z)
		for i: int in coils.size():
			coils[i].position = Vector3(0, 0, z * float(i + 1) / float(coils.size() + 1))
	ext.call(0.0)
	PartyFx.speed_lines(parent, o + dir * 0.4, o + dir * reach, Color(1.6, 1.5, 1.4, 0.8), 16, 0.35)
	var tw: Tween = root.create_tween()
	tw.tween_method(ext, 0.0, -0.06, 0.035)
	tw.tween_method(ext, -0.06, 1.0, 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void:
		var tip: Vector3 = o + dir * reach
		PartyFx.burst(parent, tip, Color(1.0, 0.85, 0.3), 30, 7.0, 0.25, 0.4)
		PartyFx.ring_pulse(parent, tip, dir, Color(1.0, 0.95, 0.7), 0.3, 1.8, 0.25, 0.2)
		PartyFx.star_ring(parent, tip, Color(1.0, 0.9, 0.35), 8, 5.5, 0.42, dir)
		PartyFx.sparks(parent, tip, Color(1.0, 1.0, 0.8), 18, 8.0, dir, 60.0)
		if is_instance_valid(head):
			var sq: Tween = head.create_tween()
			sq.tween_property(head, "scale", Vector3(1.35, 1.35, 0.6), 0.04)
			sq.tween_property(head, "scale", Vector3.ONE, 0.12).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT))
	# BOING: the spring shivers at full stretch
	tw.tween_method(func(k: float) -> void:
		ext.call(1.0 - sin(k * PI * 3.0) * 0.1 * (1.0 - k)), 0.0, 1.0, 0.2)
	tw.tween_method(ext, 1.0, 0.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(root.queue_free)


static func remote_fx(layer_ref: PartyLayer, _from_id: int, action: String, d: Dictionary) -> void:
	if action == "punch":
		_punch_fx(layer_ref, PowerUp.v3(d.get("o", [])), PowerUp.v3(d.get("d", [])), float(d.get("r", REACH)))
		layer_ref.sfx.play_at("spring", PowerUp.v3(d.get("o", [])), 1.0)
