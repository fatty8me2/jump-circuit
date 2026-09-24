extends PowerUp
## Swap Warp (instant): you and the racer directly ahead of you trade places through a pair of
## swirling portals. (The leader never rolls it.) In Party Practice it swaps with the nearest
## dummy. The victim is told where to go ("swap") and teleports itself.

const TEAL := Color(0.4, 1.0, 0.85)


func begin() -> void:
	var tg: Dictionary = layer.target_ahead()
	if tg.is_empty():
		layer.hud.announce("Nobody to swap with!", TEAL)
		PartyFx.burst(world(), chest(), TEAL, 20, 3.0, 0.2)
		finish()
		return
	var a: Vector3 = feet()
	var b: Vector3 = tg["pos"]
	_warp_fx(layer, a, b)
	fx("warp", {"a": arr(a), "b": arr(b)})
	layer.sfx.play("warp", 1.0, 1.0)
	if bool(tg.get("dummy", false)):
		var d: PracticeDummy = tg["node"] as PracticeDummy
		d.global_position = a
		d.vel = Vector3.ZERO
		d.grounded = false
		d.take_hit(Vector3.ZERO, {"s": "swap", "add": true, "st": 0.8})
		layer.hit_landed.emit(d.id, "swap")
	else:
		Net.send_party({"k": "swap", "pos": arr(a)}, int(tg["id"]))
		layer.hit_landed.emit(int(tg["id"]), "swap")
	var p: Player = player()
	p.teleport(Transform3D(Basis(Vector3.UP, p.camera_yaw), b + Vector3(0, 0.1, 0)))
	layer.hud.announce("SWAP!", TEAL)
	finish()


## Twin portals iris open where each racer stands, spinning, with rings rising through them
## and a swirl of motes; two comets trade places along an arc between them; the portals
## implode shut with a flash.
static func _warp_fx(parent: Node, a: Vector3, b: Vector3) -> void:
	var across: Vector3 = Vector3(b.x - a.x, 0, b.z - a.z)
	across = across.normalized() if across.length() > 0.1 else Vector3.FORWARD
	for at: Vector3 in [a, b]:
		var c: Vector3 = at + Vector3(0, 0.9, 0)
		PartyFx.portal(parent, c, across, TEAL, 1.15, 0.8)
		PartyFx.ring_pulse(parent, at + Vector3(0, 0.08, 0), Vector3.UP, Color(0.3, 0.8, 1.0), 0.2, 1.5, 0.3, 0.1)
		PartyFx.one_shot(parent, at, {"amount": 30, "lifetime": 0.8, "size": 0.14, "color": Color(0.3, 0.9, 0.8),
			"shape": "ring", "radius": 1.0, "inner": 0.8, "axis": Vector3.UP, "dir": Vector3.UP, "spread": 5.0,
			"vmin": 1.5, "vmax": 3.5, "radial": -1.5, "spark": true, "explosiveness": 0.4,
			"colors": [Color(1, 1, 1, 0), Color(0.6, 1, 0.9, 1), Color(0.3, 0.6, 1, 0)]})
		for i: int in 3:
			PartyFx.ring_pulse(parent, at + Vector3(0, 0.3 + 0.6 * float(i), 0), Vector3.UP, Color(0.3, 0.8, 0.7), 1.3, 0.2, 0.5 + 0.1 * float(i), 0.08)
		PartyFx.flash(parent, c, TEAL, 4.0, 6.0, 0.4)
	# the two racers trading places: comets crossing on an arc, and a faint thread
	PartyFx.comet(parent, a + Vector3(0, 0.9, 0), b + Vector3(0, 0.9, 0), Color(0.4, 1.0, 0.85), 2.2, 0.38, 0.24)
	PartyFx.comet(parent, b + Vector3(0, 0.9, 0), a + Vector3(0, 0.9, 0), Color(0.45, 0.7, 1.0), -0.6, 0.38, 0.2)
	PartyFx.streak(parent, a + Vector3(0, 0.9, 0), b + Vector3(0, 0.9, 0), TEAL, 40, 0.16, 0.7, 0.2, 1.0, true)
	# a moment later both portals snap shut
	var t: SceneTree = parent.get_tree()
	if t != null:
		t.create_timer(0.72, false).timeout.connect(func() -> void:
			if is_instance_valid(parent) and parent.is_inside_tree():
				for at: Vector3 in [a, b]:
					PartyFx.burst(parent, at + Vector3(0, 0.9, 0), Color(0.6, 1.0, 0.95), 24, 5.0, 0.2, 0.4)
					PartyFx.star_ring(parent, at + Vector3(0, 0.9, 0), Color(0.5, 1.0, 0.9), 6, 4.0, 0.3, across))


static func remote_fx(layer_ref: PartyLayer, _from_id: int, action: String, d: Dictionary) -> void:
	if action == "warp":
		_warp_fx(layer_ref, PowerUp.v3(d.get("a", [])), PowerUp.v3(d.get("b", [])))
		layer_ref.sfx.play_at("warp", PowerUp.v3(d.get("a", [])), 0.9)
