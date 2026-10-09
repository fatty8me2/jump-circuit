extends PowerUp
## Leader Strike (instant): calls an orbital strike down on whoever is in front. A red reticle
## locks onto the leading racer, a siren winds up and a pillar of red light builds for 2.7 s -
## then the sky falls in on the spot. The leader sees "Targeted!" the moment it is called and has
## the whole wind-up to run clear (the reticle stops following them just before it lands); anyone
## standing within the blast gets thrown and stunned, friend or foe. Not rolled for the leader;
## kept in the slot when you already are in front.


func can_use() -> bool:
	return not layer.leader_target().is_empty()


func no_use_hint() -> String:
	return "You're already in front!"


func begin() -> void:
	var tg: Dictionary = layer.leader_target()
	if tg.is_empty():
		finish()
		return
	var key: String = layer.new_key()
	var tid: int = int(tg["id"])
	var seed_value: int = randi() % 10000
	var c: Vector3 = tg["center"]
	spawn(layer, key, owner_id, tid, c - Vector3(0, 0.8, 0), seed_value)
	_call_fx(layer, chest())
	layer.sfx.play("powerup", 0.6, 0.7)
	fx("tell", {"k": key, "t": tid, "at": arr(c), "s": seed_value})
	finish()


static func spawn(layer_ref: PartyLayer, key: String, owner: int, tid: int, at: Vector3, seed_value: int) -> StrikeZone:
	var z := StrikeZone.new()
	z.layer = layer_ref
	z.key = key
	z.owner_id = owner
	z.target_id = tid
	z.seed_value = seed_value
	z.position = at
	layer_ref.add_child(z)
	return z


## The caller points at the sky: a red beam leaps up from them and a ring spreads out.
static func _call_fx(parent: Node, o: Vector3) -> void:
	PartyFx.beam(parent, o, o + Vector3(0, 14.0, 0), Color(1.0, 0.45, 0.35, 0.9), 0.07, 0.5, 3.0)
	PartyFx.ring_pulse(parent, o - Vector3(0, 0.6, 0), Vector3.UP, Color(1.0, 0.35, 0.25), 0.2, 2.2, 0.4, 0.14)
	PartyFx.burst(parent, o, Color(1.0, 0.4, 0.3), 20, 4.0, 0.22, 0.45)
	PartyFx.sparks(parent, o, Color(1.4, 0.7, 0.5), 14, 7.0, Vector3.UP, 30.0)
	PartyFx.flash(parent, o + Vector3(0, 1.5, 0), Color(1.0, 0.4, 0.3), 4.0, 6.0, 0.3)


static func remote_fx(layer_ref: PartyLayer, from_id: int, action: String, d: Dictionary) -> void:
	if action != "tell":
		return
	var at: Vector3 = PowerUp.v3(d.get("at", []))
	spawn(layer_ref, str(d.get("k", "")), from_id, int(d.get("t", 0)), at - Vector3(0, 0.8, 0), int(d.get("s", 0)))
	var g: RemoteRacer = layer_ref.ghost(from_id)
	if g != null:
		_call_fx(layer_ref, g.global_position + Vector3(0, 0.8, 0))
