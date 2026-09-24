extends PowerUp
## Thunder Cloud (instant): a storm cloud boils up over every rival ahead of you and drops a
## lightning bolt on each - a short stun, then they run slowed and crackling for a few seconds.
## Look: a little storm gathers over the caster and a bolt leaps up into it; over each target
## a black cloud boils, a forked bolt cracks down (and flickers a second time), scorching a
## ring into the ground; the cloud rumbles with inner flashes and drizzle, then drifts apart.

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
	var seed_value: int = randi() % 10000
	_summon_fx(layer, chest(), seed_value)
	_strikes(layer, pts, seed_value)
	layer.sfx.play("zap", 1.0, 0.9)
	PartyFx.shake(layer.level, 0.15)
	fx("zap", {"o": arr(chest()), "t": pts, "s": seed_value})
	if ahead.is_empty():
		layer.hud.announce("Nobody ahead to zap!", BOLT)
	finish()


## The caster: static crawls over them, a small storm gathers overhead and a bolt leaps up.
static func _summon_fx(parent: Node, o: Vector3, seed_value: int = 0) -> void:
	var sky: Vector3 = o + Vector3(0, 2.4, 0)
	PartyFx.storm_cloud(parent, sky, 0.9, 0.9, seed_value + 99)
	PartyFx.forked_bolt(parent, o + Vector3(0, 0.3, 0), sky, BOLT, seed_value + 5, 0.22, 1)
	PartyFx.crackle(parent, o, 0.7, BOLT, 5, 0.15)
	PartyFx.crackle(parent, o + Vector3(0, 0.3, 0), 0.6, Color(0.9, 0.95, 1.0), 4, 0.12)
	PartyFx.ring_pulse(parent, o - Vector3(0, 0.7, 0), Vector3.UP, BOLT, 0.2, 1.8, 0.35, 0.14)
	PartyFx.one_shot(parent, o, {"amount": 24, "lifetime": 0.5, "size": 0.12, "color": Color(0.8, 0.9, 1.4), "spark": true,
		"shape": "sphere", "radius": 0.6, "dir": Vector3.UP, "spread": 25.0, "vmin": 3.0, "vmax": 7.0, "damping": 2.0})
	PartyFx.flash(parent, sky, BOLT, 5.0, 6.0, 0.3)


static func _strikes(layer_ref: PartyLayer, pts: Array, seed_value: int) -> void:
	var i: int = 0
	for a: Variant in pts:
		var c: Vector3 = PowerUp.v3(a)
		var sky: Vector3 = c + Vector3(0, 9.0, 0)
		var g: Dictionary = layer_ref.ground_at(c, 4.0)
		var floor_at: Vector3 = g["position"] if not g.is_empty() else c - Vector3(0, 0.8, 0)
		# the cloud boils up and hangs there rumbling
		PartyFx.storm_cloud(layer_ref, sky, 2.0, 1.7, seed_value + i * 13)
		# the strike: a forked bolt to the target and on into the ground
		PartyFx.forked_bolt(layer_ref, sky, c, BOLT, seed_value + i, 0.32, 3)
		PartyFx.beam(layer_ref, c, floor_at, Color(0.95, 0.97, 1.0), 0.06, 0.25, 5.0)
		PartyFx.orb_pulse(layer_ref, c, Color(0.8, 0.88, 1.0, 0.6), 0.2, 1.1, 0.16, 2.5)
		PartyFx.scorch(layer_ref, floor_at, 1.3, 2.2, Color(0.55, 0.7, 1.0))
		PartyFx.ring_pulse(layer_ref, floor_at + Vector3(0, 0.1, 0), Vector3.UP, BOLT, 0.3, 2.8, 0.35, 0.2)
		PartyFx.star_ring(layer_ref, c, Color(0.85, 0.92, 1.3), 8, 6.0, 0.4)
		PartyFx.sparks(layer_ref, c, Color(0.85, 0.9, 1.0), 30, 9.0)
		PartyFx.smoke(layer_ref, floor_at + Vector3(0, 0.3, 0), Color(0.3, 0.3, 0.36, 0.5), 10, 0.6, 1.2)
		layer_ref.sfx.play_at("zap", c, 1.0, 0.8 + 0.1 * float(i % 3))
		# the afterflash: a second, thinner fork a blink later
		var s2: int = seed_value + i + 7
		layer_ref.get_tree().create_timer(0.11, false).timeout.connect(func() -> void:
			if is_instance_valid(layer_ref) and layer_ref.is_inside_tree():
				PartyFx.forked_bolt(layer_ref, sky + Vector3(0.5, 0, -0.4), c, Color(0.9, 0.95, 1.0), s2, 0.18, 1))
		i += 1


static func remote_fx(layer_ref: PartyLayer, _from_id: int, action: String, d: Dictionary) -> void:
	if action != "zap":
		return
	var seed_value: int = int(d.get("s", 0))
	_summon_fx(layer_ref, PowerUp.v3(d.get("o", [])), seed_value)
	var pts: Variant = d.get("t", [])
	if typeof(pts) == TYPE_ARRAY:
		_strikes(layer_ref, pts as Array, seed_value)
