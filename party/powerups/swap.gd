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


static func _warp_fx(parent: Node, a: Vector3, b: Vector3) -> void:
	for at: Vector3 in [a, b]:
		var c: Vector3 = at + Vector3(0, 0.9, 0)
		PartyFx.implode(parent, c, TEAL, 2.2)
		PartyFx.one_shot(parent, c, {"amount": 60, "lifetime": 0.8, "size": 0.2, "color": TEAL, "shape": "ring",
			"radius": 1.1, "inner": 0.9, "axis": Vector3.UP, "height": 1.6, "vmin": 0.1, "vmax": 0.4,
			"tangential": 14.0, "radial": -1.0, "spark": true, "shrink": false,
			"colors": [Color(1, 1, 1, 0), Color(0.6, 1, 0.9, 1), Color(0.3, 0.6, 1, 0)]})
		for i: int in 3:
			PartyFx.ring_pulse(parent, at + Vector3(0, 0.3 + 0.6 * float(i), 0), Vector3.UP, TEAL, 1.4, 0.2, 0.5 + 0.1 * float(i), 0.12)
		PartyFx.flash(parent, c, TEAL, 6.0, 7.0, 0.4)
	# the thread between the two portals
	PartyFx.beam(parent, a + Vector3(0, 0.9, 0), b + Vector3(0, 0.9, 0), Color(0.5, 1.0, 0.9, 0.5), 0.12, 0.6, 3.0)
	PartyFx.streak(parent, a + Vector3(0, 0.9, 0), b + Vector3(0, 0.9, 0), TEAL, 60, 0.18, 0.7, 0.2, 1.0, true)


static func remote_fx(layer_ref: PartyLayer, _from_id: int, action: String, d: Dictionary) -> void:
	if action == "warp":
		_warp_fx(layer_ref, PowerUp.v3(d.get("a", [])), PowerUp.v3(d.get("b", [])))
		layer_ref.sfx.play_at("warp", PowerUp.v3(d.get("a", [])), 0.9)
