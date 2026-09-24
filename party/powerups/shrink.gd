extends PowerUp
## Shrink Ray (instant): a wobbling rainbow ray zaps the rival in front (auto-aimed) down to
## half size for 7 s - slower, weaker jumps, and every bump throws them 50 % further.

const RANGE: float = 28.0
const PINK := Color(0.95, 0.45, 1.0)
const TIME: float = 7.0


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
	_ray_fx(layer, o, to, not tg.is_empty())
	layer.sfx.play("zap", 0.9, 1.8)
	fx("ray", {"o": arr(o), "t": arr(to), "h": not tg.is_empty()})
	if not tg.is_empty():
		layer.hit(tg, Vector3(0, 3.0, 0), {"e": "shrink", "ed": TIME, "s": "shrink", "quiet": true, "add": true})
	finish()


## Muzzle sparkle, a wobbling rainbow double-helix ray with rings marching down it and
## glitter along the way; on a hit the target is squeezed by a pink implosion and "pops"
## small with a star ring and a SHRINK! call-out.
static func _ray_fx(parent: Node, o: Vector3, to: Vector3, hit: bool) -> void:
	var dir: Vector3 = (to - o).normalized()
	var length: float = o.distance_to(to)
	# the gun charges in a blink: glitter sucked into the muzzle, a ring flash
	PartyFx.one_shot(parent, o, {"amount": 16, "lifetime": 0.18, "size": 0.16, "color": Color(1.4, 0.8, 1.5), "tex": "star",
		"shape": "shell", "radius": 0.7, "vmin": 0.0, "vmax": 0.1, "radial": -30.0, "explosiveness": 1.0, "shrink": false})
	PartyFx.ring_pulse(parent, o, dir, Color(1.0, 0.7, 1.0), 0.1, 0.8, 0.2, 0.2)
	HeroFx.stars(parent, o, Color(1.4, 0.9, 1.5), 8, 3.0, 0.3, 0.15)
	PartyFx.flash(parent, o, PINK, 4.0, 5.0, 0.25)
	PartyFx.beam(parent, o, to, Color(1.0, 0.8, 1.0, 1.0), 0.045, 0.35, 2.2)
	PartyFx.beam(parent, o, to, Color(0.9, 0.35, 1.0, 0.22), 0.2, 0.45, 1.2)
	# the wobble: two rainbow ribbons twisting round the core
	var waves: float = maxf(length / 2.2, 2.0)
	PartyFx.wave_ribbon(parent, o, to, Color(1, 1, 1, 0.95), 0.28, waves, 0.05, 0.45, 0.0, true)
	PartyFx.wave_ribbon(parent, o, to, Color(1, 1, 1, 0.95), 0.28, waves, 0.05, 0.45, PI * 0.5, true)
	# rainbow rings marching down the ray
	var n: int = maxi(int(length / 1.6), 2)
	for i: int in n:
		var k: float = float(i) / float(n)
		var col: Color = Color.from_hsv(fmod(k * 1.5, 1.0), 0.6, 1.0)
		PartyFx.ring_pulse(parent, o + dir * length * k, dir, col, 0.5, 0.15, 0.3 + 0.2 * k, 0.25)
	PartyFx.streak(parent, o, to, Color(0.8, 0.35, 0.9), 34, 0.16, 0.5, 0.25, 1.5, true)
	PartyFx.one_shot(parent, (o + to) * 0.5, {"amount": 24, "lifetime": 0.6, "size": 0.2, "color": Color(1.3, 1.1, 1.3),
		"tex": "star", "shape": "box", "extents": Vector3(0.25, length * 0.5, 0.25), "basis": PartyFx.beam_transform(o, to, 1.0).basis.orthonormalized(),
		"vmin": 0.2, "vmax": 0.8, "hue": 0.5, "angle": true, "explosiveness": 0.8, "grow": true, "aabb": length + 4.0,
		"colors": [Color(1, 1, 1, 1), Color(1, 1, 1, 0)]})
	if hit:
		PartyFx.implode(parent, to, PINK, 1.6)
		PartyFx.one_shot(parent, to, {"amount": 40, "lifetime": 0.7, "size": 0.2, "color": PINK, "shape": "sphere",
			"radius": 0.6, "vmin": 1.0, "vmax": 3.0, "spark": true, "tangential": 8.0,
			"colors": [Color(1, 0.6, 1, 1), Color(0.6, 0.8, 1, 0.8), Color(1, 1, 0.6, 0)]})
		PartyFx.star_ring(parent, to, Color(1.2, 0.7, 1.3), 10, 4.5, 0.4)
		PartyFx.ring_pulse(parent, to, Vector3.UP, PINK, 1.6, 0.2, 0.3, 0.12)
		PartyFx.comic_burst(parent, to + Vector3(0, 1.1, 0), "SHRINK!", Color(1.0, 0.45, 0.95), 0.8)
		# a spiral of rainbow glitter wrapping them as they shrink, then a sparkle cloud that hangs
		for k: int in 3:
			PartyFx.ring_pulse(parent, to + Vector3(0, -0.5 + 0.5 * float(k), 0), Vector3.UP, Color.from_hsv(0.8 + 0.1 * float(k), 0.55, 1.0), 1.4 - 0.2 * float(k), 0.15, 0.35 + 0.08 * float(k), 0.1)
		HeroFx.pop(parent, {"amount": 40, "lifetime": 0.6, "local": false, "shape": "shell", "radius": 1.3,
			"speed": Vector2(0.0, 0.2), "radial": Vector2(-7.0, -5.0), "tex": Fx.Tex.STAR, "size": 0.2, "curve": "pop",
			"hue": 0.5, "color": Color(1.3, 0.8, 1.4), "explosiveness": 0.5}, to)
		if PartyFx.rich():
			HeroFx.pop(parent, {"amount": 24, "lifetime": 1.4, "shape": "sphere", "radius": 0.8, "dir": Vector3.UP,
				"spread": 60.0, "speed": Vector2(0.2, 0.8), "turbulence": 0.8, "tex": Fx.Tex.STAR, "size": 0.15,
				"curve": "pop", "hue": 0.5, "explosiveness": 0.3, "color": Color(1.3, 0.9, 1.4)}, to)
		HeroFx.ground_ring(parent, to - Vector3(0, 0.8, 0), Color(1.2, 0.5, 1.3), 1.6, 0.4)
	else:
		PartyFx.burst(parent, to, PINK, 16, 3.0, 0.2)
		PartyFx.star_ring(parent, to, Color(1.2, 0.8, 1.3), 6, 3.0, 0.3, -dir)


static func remote_fx(layer_ref: PartyLayer, _from_id: int, action: String, d: Dictionary) -> void:
	if action == "ray":
		_ray_fx(layer_ref, PowerUp.v3(d.get("o", [])), PowerUp.v3(d.get("t", [])), bool(d.get("h", false)))
		layer_ref.sfx.play_at("zap", PowerUp.v3(d.get("o", [])), 0.8, 1.8)
