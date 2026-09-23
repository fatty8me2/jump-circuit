extends PowerUp
## Thunder Cloud (instant): a storm cloud boils up over every rival ahead of you and drops a
## lightning bolt on each - a short stun, then they run slowed and crackling for a few seconds.

const BOLT := Color(0.65, 0.75, 1.0)
const STUN: float = 0.8
const SLOW: float = 3.0


func begin() -> void:
	var pts: Array = []
	var ahead: Array[Dictionary] = layer.targets_ahead()
	for t: Dictionary in ahead:
		var c: Vector3 = t["center"]
		pts.append(arr(c))
		layer.hit(t, Vector3(0, 4.0, 0), {"st": STUN, "e": "slow", "ed": SLOW, "s": "thunder", "quiet": true, "add": true})
	# our own cloud rumbles up as we call the storm
	_summon_fx(layer, chest())
	_strikes(layer, pts, randi())
	layer.sfx.play("zap", 1.0, 0.9)
	fx("zap", {"o": arr(chest()), "t": pts, "s": randi() % 10000})
	if ahead.is_empty():
		layer.hud.announce("Nobody ahead to zap!", BOLT)
	finish()


static func _summon_fx(parent: Node, o: Vector3) -> void:
	PartyFx.smoke(parent, o + Vector3(0, 1.6, 0), Color(0.25, 0.27, 0.35, 0.7), 16, 0.9, 1.2)
	PartyFx.crackle(parent, o + Vector3(0, 1.8, 0), 0.8, BOLT, 5, 0.15)
	PartyFx.flash(parent, o + Vector3(0, 2.0, 0), BOLT, 5.0, 6.0, 0.3)


static func _strikes(layer_ref: PartyLayer, pts: Array, seed_value: int) -> void:
	var i: int = 0
	for a: Variant in pts:
		var c: Vector3 = PowerUp.v3(a)
		var sky: Vector3 = c + Vector3(0, 11.0, 0)
		# the cloud: a dark churning puff with flickers inside
		PartyFx.smoke(layer_ref, sky, Color(0.18, 0.2, 0.28, 0.85), 26, 1.8, 1.6)
		PartyFx.one_shot(layer_ref, sky, {"amount": 20, "lifetime": 1.0, "size": 1.4, "color": Color(0.5, 0.55, 0.8, 0.5),
			"shape": "sphere", "radius": 1.6, "vmin": 0.1, "vmax": 0.6, "explosiveness": 0.5})
		PartyFx.bolt(layer_ref, sky, c, BOLT, seed_value + i, 0.3)
		PartyFx.bolt(layer_ref, sky + Vector3(0.4, 0, -0.3), c, Color(0.9, 0.95, 1.0), seed_value + i + 7, 0.2)
		PartyFx.ring_pulse(layer_ref, c - Vector3(0, 0.75, 0), Vector3.UP, BOLT, 0.3, 2.6, 0.35, 0.2)
		PartyFx.sparks(layer_ref, c, Color(0.85, 0.9, 1.0), 30, 9.0)
		layer_ref.sfx.play_at("zap", c, 1.0, 0.8 + 0.1 * float(i % 3))
		i += 1


static func remote_fx(layer_ref: PartyLayer, _from_id: int, action: String, d: Dictionary) -> void:
	if action != "zap":
		return
	_summon_fx(layer_ref, PowerUp.v3(d.get("o", [])))
	var pts: Variant = d.get("t", [])
	if typeof(pts) == TYPE_ARRAY:
		_strikes(layer_ref, pts as Array, int(d.get("s", 0)))
