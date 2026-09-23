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


static func _ray_fx(parent: Node, o: Vector3, to: Vector3, hit: bool) -> void:
	var dir: Vector3 = (to - o).normalized()
	var length: float = o.distance_to(to)
	PartyFx.beam(parent, o, to, Color(1.0, 0.8, 1.0, 1.0), 0.06, 0.35, 4.0)
	PartyFx.beam(parent, o, to, Color(0.9, 0.4, 1.0, 0.35), 0.22, 0.45, 2.0)
	# rainbow rings marching down the ray
	var n: int = maxi(int(length / 1.6), 2)
	for i: int in n:
		var k: float = float(i) / float(n)
		var col: Color = Color.from_hsv(fmod(k * 1.5, 1.0), 0.6, 1.0)
		PartyFx.ring_pulse(parent, o + dir * length * k, dir, col, 0.5, 0.15, 0.3 + 0.2 * k, 0.25)
	PartyFx.streak(parent, o, to, PINK, 50, 0.18, 0.5, 0.25, 1.5, true)
	if hit:
		PartyFx.implode(parent, to, PINK, 1.6)
		PartyFx.one_shot(parent, to, {"amount": 40, "lifetime": 0.7, "size": 0.2, "color": PINK, "shape": "sphere",
			"radius": 0.6, "vmin": 1.0, "vmax": 3.0, "spark": true, "tangential": 8.0,
			"colors": [Color(1, 0.6, 1, 1), Color(0.6, 0.8, 1, 0.8), Color(1, 1, 0.6, 0)]})
		PartyFx.popup_text(parent, to + Vector3(0, 1.0, 0), "shrink!", PINK, 90)
	else:
		PartyFx.burst(parent, to, PINK, 16, 3.0, 0.2)


static func remote_fx(layer_ref: PartyLayer, _from_id: int, action: String, d: Dictionary) -> void:
	if action == "ray":
		_ray_fx(layer_ref, PowerUp.v3(d.get("o", [])), PowerUp.v3(d.get("t", [])), bool(d.get("h", false)))
		layer_ref.sfx.play_at("zap", PowerUp.v3(d.get("o", [])), 0.8, 1.8)
