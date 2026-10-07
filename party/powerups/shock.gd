extends PowerUp
## Shockwave (instant): you stamp the ground and a ring of force explodes outward, hurling every
## rival within 7 m away from you and up into the air (and popping any decoy it meets). The
## answer to being mobbed - a good pick for the racer in front. Kept in the slot when nobody is
## close enough to feel it.

const RADIUS: float = 7.0
const GOLD := Color(1.0, 0.8, 0.3)


func can_use() -> bool:
	return not layer.targets_in_sphere(chest(), RADIUS).is_empty()


func no_use_hint() -> String:
	return "Nobody close enough to blast!"


func begin() -> void:
	var o: Vector3 = feet()
	var c: Vector3 = chest()
	slam_fx(layer, o)
	layer.sfx.play("shock", 1.0, 1.0)
	PartyFx.shake(layer.level, 0.5)
	fx("slam", {"at": arr(o)})
	for t: Dictionary in layer.targets_in_sphere(c, RADIUS):
		var away: Vector3 = (t["center"] as Vector3) - c
		away.y = 0.0
		away = away.normalized() if away.length() > 0.2 else layer.aim_dir()
		# strongest right next to you, fading to a hard shove at the edge of the ring
		var k: float = 1.0 - clampf(((t["center"] as Vector3).distance_to(c)) / RADIUS, 0.0, 1.0) * 0.5
		layer.hit(t, away * 17.0 * k + Vector3(0, 10.0 * k, 0), {"st": 0.7, "s": "shock", "quiet": true})
		PartyFx.star_ring(layer, t["center"], GOLD, 8, 5.0, 0.38, away)
	finish()


## A ground-pound: dust and rubble thrown up, three rings of force racing out, a column of light
## from the point of impact, cracks in the floor and sparks flying - big, but never in the way.
static func slam_fx(parent: Node, at: Vector3) -> void:
	PartyFx.shockwave(parent, at, GOLD, RADIUS * 1.05, 0.5)
	PartyFx.shockwave(parent, at, Color(1.0, 0.95, 0.8), RADIUS * 0.7, 0.35)
	for i: int in 3:
		PartyFx.ring_pulse(parent, at + Vector3(0, 0.1 + 0.15 * float(i), 0), Vector3.UP, Color(1.0, 0.85, 0.5), 0.4, RADIUS * (1.0 - 0.15 * float(i)), 0.4 + 0.08 * float(i), 0.2 - 0.04 * float(i))
	PartyFx.orb_pulse(parent, at + Vector3(0, 0.5, 0), Color(1.0, 0.95, 0.8, 0.55), 0.3, 2.4, 0.2, 2.5)
	PartyFx.burst(parent, at + Vector3(0, 0.4, 0), GOLD, 40, 8.0, 0.28, 0.6)
	PartyFx.sparks(parent, at + Vector3(0, 0.3, 0), Color(1.0, 0.9, 0.5), 30, 11.0, Vector3.UP, 80.0)
	PartyFx.ground_cracks(parent, at, RADIUS * 0.55, Color(2.4, 1.6, 0.5), 8, 1.8, int(at.x * 10.0))
	PartyFx.debris(parent, at + Vector3(0, 0.3, 0), Color(0.55, 0.5, 0.42), 14, 8.0, 0.18)
	PartyFx.dust_wall(parent, at, RADIUS * 0.6)
	PartyFx.beam(parent, at, at + Vector3(0, 12.0, 0), Color(1.0, 0.9, 0.6, 0.5), 0.5, 0.3, 2.0)
	PartyFx.star_ring(parent, at + Vector3(0, 0.5, 0), Color(1.0, 0.9, 0.4), 12, 9.0, 0.45)
	PartyFx.flash(parent, at + Vector3(0, 0.6, 0), GOLD, 7.0, 10.0, 0.35)
	PartyFx.comic_burst(parent, at + Vector3(0, 1.8, 0), "SLAM!", Color(1.0, 0.8, 0.25), 1.0)


static func remote_fx(layer_ref: PartyLayer, _from_id: int, action: String, d: Dictionary) -> void:
	if action == "slam":
		var at: Vector3 = PowerUp.v3(d.get("at", []))
		slam_fx(layer_ref, at)
		layer_ref.sfx.play_at("shock", at, 1.0, 1.0)
