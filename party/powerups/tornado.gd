extends PowerUp
## Tornado (instant): whips up a tornado at your feet that wanders up the course - toward the
## next checkpoints - weaving across it for 9 s and flinging every rival it catches sky-high.


func begin() -> void:
	var pts: Array = [arr(feet())]
	var lvl: LevelBase = layer.level
	# the path: on toward the next few checkpoints (the course direction), else straight ahead
	var next: int = lvl.current_checkpoint
	for i: int in range(next, mini(next + 3, lvl.checkpoints.size())):
		pts.append(arr(lvl.checkpoints[i].respawn_transform().origin))
	if pts.size() < 2:
		pts.append(arr(feet() + layer.aim_dir() * 60.0))
	var key: String = layer.new_key()
	var sway: float = randf() * TAU
	_spawn(layer, key, owner_id, pts, sway)
	layer.sfx.play("wind", 1.0, 1.0)
	PartyFx.shake(layer.level, 0.2)
	fx("spawn", {"k": key, "pts": pts, "s": sway})
	finish()


static func _spawn(layer_ref: PartyLayer, key: String, owner: int, pts: Array, sway: float) -> PartyTornado:
	var tn := PartyTornado.new()
	tn.layer = layer_ref
	tn.owner_id = owner
	tn.key = key
	tn.sway_seed = sway
	for a: Variant in pts:
		tn.points.append(PowerUp.v3(a))
	layer_ref.add_child(tn)
	PartyFx.burst(layer_ref, tn.points[0] + Vector3(0, 0.5, 0), PartyTornado.GREY, 40, 7.0, 0.3)
	PartyFx.shockwave(layer_ref, tn.points[0], PartyTornado.GREY, 3.0)
	return tn


static func remote_fx(layer_ref: PartyLayer, from_id: int, action: String, d: Dictionary) -> void:
	if action == "spawn" and typeof(d.get("pts", [])) == TYPE_ARRAY:
		_spawn(layer_ref, str(d.get("k", "")), from_id, d["pts"] as Array, float(d.get("s", 0.0)))
		layer_ref.sfx.play_at("wind", PowerUp.v3((d["pts"] as Array)[0]) if not (d["pts"] as Array).is_empty() else Vector3.ZERO, 1.0)
