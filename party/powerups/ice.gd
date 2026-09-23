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


static func _beam_fx(parent: Node, o: Vector3, to: Vector3, hit: bool) -> void:
	PartyFx.beam(parent, o, to, Color(0.95, 1.0, 1.0, 1.0), 0.08, 0.45, 4.0)
	PartyFx.beam(parent, o, to, Color(0.5, 0.85, 1.0, 0.4), 0.3, 0.55, 2.0)
	PartyFx.streak(parent, o, to, Color(0.85, 0.97, 1.0), 70, 0.16, 0.9, 0.35, 0.8, true)
	PartyFx.streak(parent, o, to, ICE, 30, 0.4, 0.7, 0.3, 0.3)
	var dir: Vector3 = (to - o).normalized()
	var n: int = maxi(int(o.distance_to(to) / 2.5), 1)
	for i: int in n:
		PartyFx.ring_pulse(parent, o + dir * (1.0 + 2.5 * float(i)), dir, Color(0.8, 0.95, 1.0), 0.15, 0.6, 0.3, 0.3)
	PartyFx.flash(parent, o, ICE, 5.0, 6.0, 0.3)
	if hit:
		PartyFx.burst(parent, to, Color(0.85, 0.97, 1.0), 40, 6.0, 0.22, 0.5)
		PartyFx.sparks(parent, to, Color(0.9, 1.0, 1.0), 30, 7.0)
		PartyFx.one_shot(parent, to, {"amount": 40, "lifetime": 1.4, "size": 0.12, "color": Color(1, 1, 1),
			"shape": "sphere", "radius": 1.0, "vmin": 0.2, "vmax": 0.8, "gravity": Vector3(0, -1.5, 0), "spark": true,
			"explosiveness": 0.6})
		PartyFx.flash(parent, to, ICE, 6.0, 6.0, 0.4)
	else:
		PartyFx.burst(parent, to, ICE, 18, 3.0, 0.2)


static func remote_fx(layer_ref: PartyLayer, _from_id: int, action: String, d: Dictionary) -> void:
	if action == "beam":
		_beam_fx(layer_ref, PowerUp.v3(d.get("o", [])), PowerUp.v3(d.get("t", [])), bool(d.get("h", false)))
		layer_ref.sfx.play_at("freeze", PowerUp.v3(d.get("o", [])), 0.9, 1.2)
