extends PowerUp
## Fake Box (instant): you set down a perfect copy of an item box behind you. The first rival to
## run into it (thinking it is a pickup) is blown into the air and stunned. You and your team see
## a red "FAKE" mark on it. Lasts until someone grabs it or 45 s pass. Respawn protection and a
## Ghost pass through it; a Balloon Shield pops instead.


func begin() -> void:
	var p: Player = player()
	var back: Vector3 = -Vector3(p.facing_dir.x, 0, p.facing_dir.z).normalized()
	if back.length() < 0.1:
		back = -layer.aim_dir()
	var at: Vector3 = feet() + back * 2.2
	var g: Dictionary = layer.ground_at(at, 4.0)
	if g.is_empty():
		g = layer.ground_at(feet(), 3.0)
		at = feet()
	if not g.is_empty():
		at = g["position"]
	var key: String = layer.new_key()
	drop(layer, key, owner_id, at)
	layer.sfx.play("pop", 0.9, 1.3)
	PartyFx.burst(layer, chest(), Color(1.0, 0.9, 0.5), 14, 3.0, 0.2, 0.4)
	fx("drop", {"k": key, "pos": arr(at)})
	finish()


static func drop(layer_ref: PartyLayer, key: String, owner: int, at: Vector3) -> FakeBox:
	var fb := FakeBox.new()
	fb.layer = layer_ref
	fb.owner_id = owner
	fb.key = key
	fb.position = at
	layer_ref.add_child(fb)
	return fb


static func remote_fx(layer_ref: PartyLayer, from_id: int, action: String, d: Dictionary) -> void:
	if action == "drop":
		var at: Vector3 = PowerUp.v3(d.get("pos", []))
		drop(layer_ref, str(d.get("k", "")), from_id, at)
		layer_ref.sfx.play_at("pop", at, 0.8, 1.3)
