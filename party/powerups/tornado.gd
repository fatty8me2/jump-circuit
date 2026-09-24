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
	var at: Vector3 = tn.points[0]
	PartyFx.burst(layer_ref, at + Vector3(0, 0.5, 0), PartyTornado.GREY, 40, 7.0, 0.3)
	PartyFx.shockwave(layer_ref, at, PartyTornado.GREY, 3.0)
	PartyFx.debris(layer_ref, at + Vector3(0, 0.3, 0), Color(0.5, 0.42, 0.32), 12, 7.0, 0.15)
	PartyFx.one_shot(layer_ref, at + Vector3(0, 0.3, 0), {"amount": 30, "lifetime": 0.8, "size": 1.0,
		"color": Color(0.82, 0.8, 0.74, 0.55), "additive": false, "tex": "smoke", "shape": "ring", "radius": 0.5,
		"inner": 0.3, "dir": Vector3(1, 0.35, 0), "spread": 180.0, "flat": 0.6, "vmin": 3.0, "vmax": 6.0, "damping": 4.0,
		"grow": true, "angle": true, "spin": 90.0, "colors": [Color(1, 1, 1, 0.9), Color(1, 1, 1, 0)]})
	PartyFx.speed_lines(layer_ref, at, at + Vector3(0, 5.0, 0), Color(1.3, 1.3, 1.4, 0.6), 14, 1.2)
	return tn


static func remote_fx(layer_ref: PartyLayer, from_id: int, action: String, d: Dictionary) -> void:
	if action == "spawn" and typeof(d.get("pts", [])) == TYPE_ARRAY:
		_spawn(layer_ref, str(d.get("k", "")), from_id, d["pts"] as Array, float(d.get("s", 0.0)))
		layer_ref.sfx.play_at("wind", PowerUp.v3((d["pts"] as Array)[0]) if not (d["pts"] as Array).is_empty() else Vector3.ZERO, 1.0)
