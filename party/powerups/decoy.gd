extends PowerUp
## Decoy (instant): a puff of smoke and a second you steps out of it - same character, same
## name - and sprints up the course ahead of you for 10 s. Rivals can't tell it from the real
## thing: homing shells chase it, shoves and claws land on it, and it soaks up exactly one hit
## before bursting into confetti. (You and your team see it as a faint copy.) It follows the
## course's own route, hopping the gaps the route jumps. Meanwhile you run the other way, unbothered.


func begin() -> void:
	var dir: Vector3 = Vector3(player().facing_dir.x, 0, player().facing_dir.z)
	dir = dir.normalized() if dir.length() > 0.1 else layer.aim_dir()
	var start: Vector3 = feet() + dir * 1.1
	var path: Dictionary = layer.route_path(feet(), PartyDecoy.SPEED * PartyDecoy.LIFE * 1.2)
	var pts: Array = [arr(start)]
	var air: Array = [0]
	for i: int in (path["pts"] as Array).size():
		pts.append(arr((path["pts"] as Array)[i]))
		air.append(1 if bool((path["air"] as Array)[i]) else 0)
	if pts.size() < 2:
		# off the beaten route: straight ahead
		pts.append(arr(start + dir * 60.0))
		air.append(0)
	var key: String = layer.new_key()
	spawn(layer, key, owner_id, pts, air)
	layer.sfx.play("decoy", 1.0, 1.0)
	PartyFx.smoke(layer, chest(), Color(0.9, 0.9, 0.95, 0.5), 10, 0.5, 0.8)
	fx("drop", {"k": key, "pts": pts, "air": air})
	finish()


static func spawn(layer_ref: PartyLayer, key: String, owner: int, pts: Array, air: Array = []) -> PartyDecoy:
	var dc := PartyDecoy.new()
	dc.layer = layer_ref
	dc.owner_id = owner
	dc.key = key
	for a: Variant in pts:
		dc.points.append(PowerUp.v3(a))
	for f: Variant in air:
		dc.air.append(int(f) != 0)
	if dc.points.is_empty():
		dc.points.append(Vector3.ZERO)
	dc.position = dc.points[0]
	layer_ref.add_child(dc)
	return dc


static func remote_fx(layer_ref: PartyLayer, from_id: int, action: String, d: Dictionary) -> void:
	if action == "drop" and typeof(d.get("pts", [])) == TYPE_ARRAY and not (d["pts"] as Array).is_empty():
		var air: Array = d.get("air", []) as Array if typeof(d.get("air", [])) == TYPE_ARRAY else []
		spawn(layer_ref, str(d.get("k", "")), from_id, d["pts"] as Array, air)
