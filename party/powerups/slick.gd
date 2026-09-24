extends PowerUp
## Slick Puddle (instant): drops a glossy slick behind you. The first rival to run through it
## spins out (a stunned hop forward, dizzy stars). Lasts until someone slips or 25 s pass.


func begin() -> void:
	var p: Player = player()
	var back: Vector3 = -Vector3(p.facing_dir.x, 0, p.facing_dir.z).normalized()
	if back.length() < 0.1:
		back = -layer.aim_dir()
	var at: Vector3 = feet() + back * 1.8
	var g: Dictionary = layer.ground_at(at, 4.0)
	if g.is_empty():
		g = layer.ground_at(feet(), 3.0)
		at = feet()
	if not g.is_empty():
		at = g["position"]
	var key: String = layer.new_key()
	_drop(layer, key, owner_id, at, chest())
	layer.sfx.play("pop", 0.9, 0.6)
	fx("drop", {"k": key, "pos": arr(at)})
	finish()


## `from`: where the glob of slick is flung from (cosmetic; INF = it just appears).
static func _drop(layer_ref: PartyLayer, key: String, owner: int, at: Vector3, from: Vector3 = Vector3.INF) -> SlickPuddle:
	var pd := SlickPuddle.new()
	pd.layer = layer_ref
	pd.owner_id = owner
	pd.key = key
	pd.thrown_from = from
	layer_ref.add_child(pd)
	pd.global_position = at
	return pd


static func remote_fx(layer_ref: PartyLayer, from_id: int, action: String, d: Dictionary) -> void:
	if action == "drop":
		var g: RemoteRacer = layer_ref.ghost(from_id)
		var from: Vector3 = g.global_position + Vector3(0, 0.8, 0) if g != null else Vector3.INF
		_drop(layer_ref, str(d.get("k", "")), from_id, PowerUp.v3(d.get("pos", [])), from)
		layer_ref.sfx.play_at("pop", PowerUp.v3(d.get("pos", [])), 0.8, 0.6)
