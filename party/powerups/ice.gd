extends PowerUp
## Ice Beam (instant): a crackling beam of frost (auto-aimed at the rival in front) that
## freezes them solid in a block of ice for a couple of seconds - stuck wherever they were,
## even mid-jump.

const RANGE: float = 26.0
const ICE := Color(0.55, 0.9, 1.0)
const FREEZE: float = 2.2


func begin() -> void:
	var o: Vector3 = chest() + layer.aim_dir() * 0.5
	var dir: Vector3 = layer.aim_dir()
	var tg: Dictionary = layer.nearest_in_cone(o, dir, RANGE, 0.85)
	if tg.is_empty():
		tg = layer.nearest_in_cone(o, layer.melee_dir(RANGE), RANGE, 0.85)
	var to: Vector3 = o + dir * RANGE
	if not tg.is_empty():
		to = tg["center"]
	else:
		var wall: Dictionary = layer.ray(o, to)
		if not wall.is_empty():
			to = wall["position"]
	_beam_fx(layer, o, to, not tg.is_empty())
	layer.sfx.play("freeze", 1.0, 1.2)
	fx("beam", {"o": arr(o), "t": arr(to), "h": not tg.is_empty()})
	if not tg.is_empty():
		layer.hit(tg, Vector3.ZERO, {"e": "freeze", "ed": FREEZE, "s": "ice", "quiet": true, "add": true})
	finish()


## A frosty muzzle puff, a white-hot beam in a cyan glow with snow glitter and mist along
## it, ice crystals that sprout along the path of the beam and shatter a moment later; on a
## hit a frost nova (shards, a mist ring, a glint) - the ice block itself is the freeze status.
static func _beam_fx(parent: Node, o: Vector3, to: Vector3, hit: bool) -> void:
	var dir: Vector3 = (to - o).normalized()
	var length: float = o.distance_to(to)
	PartyFx.one_shot(parent, o, {"amount": 12, "lifetime": 0.5, "size": 0.5, "color": Color(0.9, 0.97, 1.0, 0.6),
		"additive": false, "tex": "smoke", "dir": dir, "spread": 35.0, "vmin": 1.0, "vmax": 3.0, "damping": 4.0,
		"grow": true, "angle": true, "colors": [Color(1, 1, 1, 0.9), Color(1, 1, 1, 0)]})
	PartyFx.ring_pulse(parent, o, dir, Color(0.85, 0.97, 1.0), 0.1, 0.9, 0.2, 0.2)
	PartyFx.beam(parent, o, to, Color(0.85, 0.97, 1.0, 1.0), 0.06, 0.45, 2.2)
	PartyFx.beam(parent, o, to, Color(0.35, 0.75, 1.0, 0.28), 0.26, 0.55, 1.3)
	PartyFx.wave_ribbon(parent, o, to, Color(0.8, 0.95, 1.0, 0.7), 0.16, maxf(length / 1.2, 3.0), 0.03, 0.4, 0.3)
	PartyFx.streak(parent, o, to, Color(0.6, 0.85, 1.0), 44, 0.14, 0.9, 0.35, 0.8, true)
	# snowflake glitter drifting off the beam, and a trail of cold mist
	var b: Basis = PartyFx.beam_transform(o, to, 1.0).basis.orthonormalized()
	PartyFx.one_shot(parent, (o + to) * 0.5, {"amount": 30, "lifetime": 1.1, "size": 0.2, "color": Color(1.3, 1.6, 1.8),
		"tex": "star", "shape": "box", "extents": Vector3(0.3, length * 0.5, 0.3), "basis": b, "vmin": 0.1, "vmax": 0.6,
		"gravity": Vector3(0, -0.8, 0), "angle": true, "spin": 120.0, "explosiveness": 0.7, "aabb": length + 4.0,
		"colors": [Color(1, 1, 1, 1), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)]})
	PartyFx.one_shot(parent, (o + to) * 0.5, {"amount": 14, "lifetime": 1.0, "size": 0.9, "color": Color(0.88, 0.96, 1.0, 0.35),
		"additive": false, "tex": "smoke", "shape": "box", "extents": Vector3(0.2, length * 0.5, 0.2), "basis": b,
		"vmin": 0.1, "vmax": 0.4, "grow": true, "angle": true, "explosiveness": 0.9, "aabb": length + 4.0,
		"colors": [Color(1, 1, 1, 0), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0)]})
	_crystals(parent, o, to)
	var n: int = maxi(int(length / 2.5), 1)
	for i: int in n:
		PartyFx.ring_pulse(parent, o + dir * (1.0 + 2.5 * float(i)), dir, Color(0.8, 0.95, 1.0), 0.15, 0.6, 0.3, 0.3)
	PartyFx.flash(parent, o, ICE, 5.0, 6.0, 0.3)
	if hit:
		PartyFx.burst(parent, to, Color(0.85, 0.97, 1.0), 36, 6.0, 0.22, 0.5)
		PartyFx.shards(parent, to, ICE, 16, 7.0, 0.14, -dir, 80.0)
		PartyFx.one_shot(parent, to - Vector3(0, 0.6, 0), {"amount": 24, "lifetime": 0.8, "size": 0.8,
			"color": Color(0.9, 0.97, 1.0, 0.55), "additive": false, "tex": "smoke", "shape": "ring", "radius": 0.4,
			"inner": 0.3, "dir": Vector3(1, 0.1, 0), "spread": 180.0, "flat": 1.0, "vmin": 3.5, "vmax": 5.5,
			"damping": 5.0, "grow": true, "angle": true, "colors": [Color(1, 1, 1, 0.9), Color(1, 1, 1, 0)]})
		var glint: MeshInstance3D = Fx.sprite(Color(2.0, 2.3, 2.5), 2.4, Fx.Tex.STAR, true)
		glint.layers = PartyFx.LAYER
		parent.add_child(glint)
		glint.global_position = to + Vector3(0, 0.3, 0)
		var gm: StandardMaterial3D = glint.material_override as StandardMaterial3D
		var tw: Tween = glint.create_tween().set_parallel(true)
		tw.tween_property(glint, "scale", Vector3.ONE * 0.2, 0.4).from(Vector3.ONE * 1.2)
		tw.tween_property(gm, "albedo_color:a", 0.0, 0.4)
		tw.chain().tween_callback(glint.queue_free)
		PartyFx.flash(parent, to, ICE, 6.0, 6.0, 0.4)
		# frost spreads over the ground under them, and snow drifts down round the block
		if parent is Node3D and (parent as Node3D).is_inside_tree():
			var gq := PhysicsRayQueryParameters3D.create(to, to + Vector3(0, -3.0, 0), 1)
			var gh: Dictionary = (parent as Node3D).get_world_3d().direct_space_state.intersect_ray(gq)
			if not gh.is_empty():
				PartyFx.frost_patch(parent, gh["position"] as Vector3, 1.8, 3.0, gh["normal"] as Vector3)
		if PartyFx.rich():
			HeroFx.pop(parent, {"amount": 30, "lifetime": 1.6, "shape": "box", "extents": Vector3(1.0, 0.1, 1.0),
				"dir": Vector3.DOWN, "spread": 20.0, "speed": Vector2(0.3, 0.8), "gravity": Vector3(0, -0.6, 0),
				"turbulence": 0.8, "tex": Fx.Tex.STAR, "size": 0.14, "curve": "pop", "explosiveness": 0.2,
				"color": Color(1.3, 1.6, 1.9)}, to + Vector3(0, 1.4, 0))
	else:
		PartyFx.burst(parent, to, ICE, 18, 3.0, 0.2)
		PartyFx.shards(parent, to, ICE, 10, 4.0, 0.12, -dir, 70.0)


## Ice crystals sprouting along the beam (staggered out from the muzzle), then shattering.
static func _crystals(parent: Node, o: Vector3, to: Vector3) -> void:
	var length: float = o.distance_to(to)
	var n: int = clampi(int(length / 1.4), 1, 18)
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = o
	var mat: StandardMaterial3D = PartyFx.solid_mat(Color(0.8, 0.96, 1.0, 0.8), 1.2, 0.05, 0.2)
	var d: Vector3 = to - o
	var rng := RandomNumberGenerator.new()
	rng.seed = int(length * 1000.0)
	var tw: Tween = root.create_tween().set_parallel(true)
	for i: int in n:
		var k: float = (float(i) + 0.5) / float(n)
		var c := Node3D.new()
		root.add_child(c)
		c.position = d * k
		c.rotation = Vector3(rng.randf_range(-PI, PI), rng.randf_range(-PI, PI), rng.randf_range(-PI, PI))
		for j: int in 3:
			PartyFx.part(c, PartyFx.cone_mesh(0.06, rng.randf_range(0.25, 0.5), 4), mat, Vector3.ZERO, Vector3.ONE,
				Vector3(rng.randf_range(-60, 60), 0, rng.randf_range(-60, 60)))
		c.scale = Vector3.ONE * 0.01
		tw.tween_property(c, "scale", Vector3.ONE, 0.12).set_delay(0.12 * k).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(0.35)
	tw.chain().tween_callback(func() -> void:
		if not is_instance_valid(root) or not root.is_inside_tree():
			return
		var w: Node = root.get_parent()
		for c: Node in root.get_children():
			PartyFx.one_shot(w, (c as Node3D).global_position, {"amount": 6, "lifetime": 0.45, "size": 0.12,
				"color": Color(1.3, 1.6, 1.8), "tex": "star", "vmin": 1.0, "vmax": 2.5, "gravity": Vector3(0, -8, 0),
				"angle": true, "explosiveness": 1.0})
		root.queue_free())


static func remote_fx(layer_ref: PartyLayer, _from_id: int, action: String, d: Dictionary) -> void:
	if action == "beam":
		_beam_fx(layer_ref, PowerUp.v3(d.get("o", [])), PowerUp.v3(d.get("t", [])), bool(d.get("h", false)))
		layer_ref.sfx.play_at("freeze", PowerUp.v3(d.get("o", [])), 0.9, 1.2)
