extends PowerUp
## Gravity Bomb (instant): lobs a humming black orb ringed in violet (auto-aimed at the nearest
## rival ahead). Where it lands space folds in on itself: everyone caught in the blast floats
## helplessly in a bubble for a few seconds.

const VIOLET := Color(0.65, 0.35, 1.0)
const RADIUS: float = 4.8
const FLOAT_TIME: float = 2.6


func begin() -> void:
	var o: Vector3 = chest() + Vector3(0, 0.3, 0)
	var dir: Vector3 = layer.aim_dir()
	var dist: float = 12.0
	var tg: Dictionary = layer.nearest_in_cone(o, dir, 22.0, 0.8)
	if not tg.is_empty():
		var to: Vector3 = (tg["center"] as Vector3) - o
		dist = clampf(Vector3(to.x, 0, to.z).length(), 3.0, 22.0)
		dir = Vector3(to.x, 0, to.z).normalized()
	var v: Vector3 = dir * (dist / 0.8) + Vector3(0, 7.0, 0)
	var key: String = layer.new_key()
	_spawn(layer, key, o, v, true)
	layer.sfx.play("whoosh", 0.8, 0.7)
	fx("throw", {"k": key, "o": arr(o), "v": arr(v)})
	finish()


static func _spawn(layer_ref: PartyLayer, key: String, o: Vector3, v: Vector3, is_local: bool) -> PartyProjectile:
	var pr := PartyProjectile.new()
	pr.layer = layer_ref
	pr.local = is_local
	pr.key = key
	pr.origin = o
	pr.velocity = v
	pr.gravity = 20.0
	pr.life = 2.0
	pr.radius = 0.8
	# the orb: a black core that bends the light around it, two violet rings orbiting
	PartyFx.part(pr, PartyFx.sphere_mesh(0.3, 16), PartyFx.glow_mat(Color(0.03, 0.0, 0.06), 1.0), Vector3.ZERO)
	pr.add_child(PartyFx.lens_sphere(0.6, Color(0.7, 0.4, 1.0), 0.05))
	var ring := Node3D.new()
	pr.add_child(ring)
	var tm := TorusMesh.new()
	tm.inner_radius = 0.42
	tm.outer_radius = 0.5
	tm.rings = 32
	tm.ring_segments = 6
	PartyFx.part(ring, tm, PartyFx.glow_mat(VIOLET, 2.5), Vector3.ZERO, Vector3.ONE, Vector3(70, 0, 0))
	PartyFx.part(ring, tm, PartyFx.glow_mat(Color(0.4, 0.6, 1.0), 2.0), Vector3.ZERO, Vector3(0.8, 0.8, 0.8), Vector3(-40, 60, 0))
	var tw: Tween = ring.create_tween().set_loops()
	tw.tween_property(ring, "rotation:y", TAU, 0.6).from(0.0)
	# accretion: motes spiralling in, a dark violet wake behind it
	pr.add_child(PartyFx.emitter({"amount": 40, "lifetime": 0.5, "size": 0.2, "color": VIOLET, "shape": "shell",
		"radius": 0.9, "vmin": 0.0, "vmax": 0.1, "radial": -6.0, "tangential": 6.0, "aabb": 25.0,
		"colors": [Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)]}))
	pr.add_child(PartyFx.emitter({"amount": 30, "lifetime": 0.45, "size": 0.4, "color": Color(0.22, 0.08, 0.35, 0.75),
		"additive": false, "tex": "smoke", "vmin": 0.0, "vmax": 0.3, "grow": true, "angle": true, "aabb": 25.0,
		"fixed_fps": 0, "colors": [Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)]}))
	pr.add_child(PartyFx.emitter({"amount": 40, "lifetime": 0.45, "size": 0.2, "color": Color(0.8, 0.5, 1.4),
		"vmin": 0.0, "vmax": 0.3, "aabb": 25.0, "fixed_fps": 0}))
	# a dark ribbon of warped space streaming behind it
	pr.add_child(HeroFx.em({"amount": 30, "lifetime": 0.35, "size": 0.3, "fixed_fps": 0, "speed": Vector2.ZERO,
		"spread": 0.0, "curve": "shrink", "additive": false, "box_aabb": 25.0, "color": Color(0.1, 0.02, 0.18, 0.6)}))
	var boom := func(pos: Vector3) -> void: _burst(layer_ref, key, pos, true)
	pr.on_world = func(pos: Vector3, n: Vector3) -> void: boom.call(pos + n * 0.4)
	pr.on_expire = boom
	pr.on_target = func(_t: Dictionary, pos: Vector3) -> bool:
		boom.call(pos)
		return true
	layer_ref.add_child(pr)
	return pr


## Space folds in: a lens bubble swells over the blast, then collapses to a point while
## streaks and rings are sucked in; then it lets go - a violet shockwave, and dust, rocks and
## sparkles drifting up weightless.
static func _burst(layer_ref: PartyLayer, key: String, pos: Vector3, is_local: bool) -> void:
	PartyFx.implode(layer_ref, pos, VIOLET, RADIUS)
	PartyFx.orb_pulse(layer_ref, pos, Color(0.05, 0.0, 0.1, 0.9), 1.4, 0.1, 0.45, 1.0)
	# the warp: a lens that grows fast, then collapses to nothing
	var lens: MeshInstance3D = PartyFx.lens_sphere(1.0, Color(0.75, 0.45, 1.0), 0.12)
	layer_ref.add_child(lens)
	lens.global_position = pos
	lens.scale = Vector3.ONE * 0.3
	var lw: Tween = lens.create_tween()
	lw.tween_property(lens, "scale", Vector3.ONE * RADIUS * 0.75, 0.12).set_ease(Tween.EASE_OUT)
	lw.tween_property(lens, "scale", Vector3.ONE * 0.05, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	lw.tween_callback(lens.queue_free)
	# streaks sucked into the centre
	PartyFx.one_shot(layer_ref, pos, {"amount": 50, "lifetime": 0.45, "size": Vector2(0.06, 0.9), "color": Color(0.8, 0.55, 1.5),
		"tex": "streak", "facing": "velocity", "shape": "shell", "radius": RADIUS * 1.1, "vmin": 0.0, "vmax": 0.5,
		"radial": -RADIUS * 9.0, "explosiveness": 0.7, "shrink": false, "aabb": RADIUS * 3.0,
		"colors": [Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)]})
	for i: int in 3:
		PartyFx.ring_pulse(layer_ref, pos, Vector3(randf_range(-1, 1), 1.0, randf_range(-1, 1)), VIOLET.lerp(Color(0.4, 0.6, 1.0), float(i) / 2.0), RADIUS, 0.3, 0.45 + 0.1 * float(i), 0.08)
	PartyFx.flash(layer_ref, pos, VIOLET, 8.0, RADIUS * 3.0, 0.5)
	# the ground buckles toward the centre: dust and grit dragged in, violet cracks
	var gh: Dictionary = layer_ref.ground_at(pos, 4.0)
	if not gh.is_empty():
		var g: Vector3 = gh["position"]
		PartyFx.ground_cracks(layer_ref, g, RADIUS * 0.8, Color(1.4, 0.8, 2.6), 9, 2.6, 0, gh["normal"] as Vector3)
		HeroFx.pop(layer_ref, {"amount": 30, "lifetime": 0.5, "shape": "ring", "ring_radius": RADIUS, "ring_inner": RADIUS * 0.6,
			"speed": Vector2(0.0, 0.3), "radial": Vector2(-RADIUS * 6.0, -RADIUS * 4.0), "facing": "mesh",
			"mesh": HeroFx.soft_quad(Fx.Tex.SMOKE, false, 0.9), "curve": "shrink", "angle": Vector2(0, 360),
			"color": Color(0.75, 0.7, 0.8, 0.45), "fade": PackedFloat32Array([0.0, 1.0, 0.0]), "explosiveness": 0.6,
			"box_aabb": RADIUS * 2.0}, g + Vector3(0, 0.25, 0))
	layer_ref.sfx.play_at("warp", pos, 1.0, 0.6)
	# ...and lets go
	layer_ref.get_tree().create_timer(0.48, false).timeout.connect(func() -> void:
		if not is_instance_valid(layer_ref) or not layer_ref.is_inside_tree():
			return
		PartyFx.orb_pulse(layer_ref, pos, Color(0.5, 0.25, 1.0, 0.3), 0.3, RADIUS, 0.5, 1.6)
		PartyFx.shockwave(layer_ref, pos - Vector3(0, 0.6, 0), VIOLET, RADIUS * 1.1, 0.5)
		PartyFx.ring_pulse(layer_ref, pos, Vector3.UP, Color(0.8, 0.6, 1.0), 0.3, RADIUS * 1.2, 0.4, 0.1)
		PartyFx.star_ring(layer_ref, pos, Color(0.8, 0.6, 1.0), 8, 6.0, 0.4)
		PartyFx.one_shot(layer_ref, pos, {"amount": 60, "lifetime": 1.8, "size": 0.18, "color": VIOLET, "shape": "sphere",
			"radius": RADIUS * 0.8, "vmin": 0.2, "vmax": 0.8, "dir": Vector3.UP, "spread": 30.0, "gravity": Vector3(0, 1.2, 0),
			"spark": true, "explosiveness": 0.7})
		# weightless rubble drifting up, tumbling slowly
		PartyFx.one_shot(layer_ref, pos - Vector3(0, 0.5, 0), {"amount": 14, "lifetime": 1.8, "facing": "mesh",
			"mesh": Fx.chunk_mesh(0.16), "color": Color(0.55, 0.5, 0.6), "shape": "sphere", "radius": RADIUS * 0.6,
			"dir": Vector3.UP, "spread": 25.0, "vmin": 0.6, "vmax": 1.6, "gravity": Vector3(0, 0.6, 0), "angle": true,
			"spin": 90.0, "explosiveness": 0.9, "colors": [Color(1, 1, 1, 1), Color(1, 1, 1, 1)], "aabb": RADIUS * 3.0})
		PartyFx.dust_wall(layer_ref, pos - Vector3(0, 0.6, 0), RADIUS * 0.8, Color(0.78, 0.74, 0.84, 0.55), 22)
		if PartyFx.rich():
			HeroFx.pop(layer_ref, {"amount": 40, "lifetime": 2.4, "shape": "sphere", "radius": RADIUS * 0.7, "dir": Vector3.UP,
				"spread": 40.0, "speed": Vector2(0.1, 0.5), "gravity": Vector3(0, 0.4, 0), "turbulence": 0.6, "size": 0.14,
				"curve": "pop", "tex": Fx.Tex.STAR, "explosiveness": 0.5, "color": Color(1.1, 0.8, 1.6),
				"box_aabb": RADIUS * 3.0}, pos))
	if not is_local:
		return
	layer_ref.send_fx("gravity", "burst", {"k": key, "pos": PowerUp.arr(pos)})
	for t: Dictionary in layer_ref.targets_in_sphere(pos, RADIUS):
		layer_ref.hit(t, Vector3(0, 3.0, 0), {"e": "float", "ed": FLOAT_TIME, "s": "gravity", "quiet": true, "add": true})


static func remote_fx(layer_ref: PartyLayer, _from_id: int, action: String, d: Dictionary) -> void:
	match action:
		"throw":
			_spawn(layer_ref, str(d.get("k", "")), PowerUp.v3(d.get("o", [])), PowerUp.v3(d.get("v", [])), false)
		"burst":
			var pr: Variant = layer_ref.projectiles.get(str(d.get("k", "")), null)
			var pos: Vector3 = PowerUp.v3(d.get("pos", []))
			if pr != null and is_instance_valid(pr):
				(pr as PartyProjectile).stop(pos)
			_burst(layer_ref, str(d.get("k", "")), pos, false)
