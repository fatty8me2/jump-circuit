extends PowerUp
## Homing Shell (instant): a spiky green shell pops out of your pack and curves after the racer
## ahead of you along the course (or a decoy that looks like one) - it follows them round
## corners and over gaps and spins them out. A Balloon Shield or respawn protection soaks it; a
## Ghost passes through it. Kept in the slot when nobody is ahead.

## Racers further ahead than this (course metres) are out of its reach.
const RANGE: float = 140.0


func can_use() -> bool:
	return not layer.target_ahead(true, RANGE).is_empty()


func no_use_hint() -> String:
	return "Nobody ahead to chase!"


func begin() -> void:
	var tg: Dictionary = layer.target_ahead(true, RANGE)
	if tg.is_empty():
		finish()
		return
	var aim: Vector3 = layer.aim_dir()
	var o: Vector3 = chest() + aim * 0.8 + Vector3(0, 0.3, 0)
	var dir: Vector3 = (aim + Vector3(0, 0.45, 0)).normalized()
	var key: String = layer.new_key()
	var tid: int = int(tg["id"])
	spawn(layer, key, owner_id, tid, o, dir, true)
	layer.sfx.play("shell", 1.0, 1.0)
	_launch_fx(layer, o, dir)
	fx("launch", {"k": key, "o": arr(o), "d": arr(dir), "t": tid})
	finish()


static func spawn(layer_ref: PartyLayer, key: String, owner: int, tid: int, o: Vector3, dir: Vector3, is_local: bool) -> HomingShell:
	var sh := HomingShell.new()
	sh.layer = layer_ref
	sh.key = key
	sh.owner_id = owner
	sh.target_id = tid
	sh.local = is_local
	sh.velocity = dir.normalized() * HomingShell.SPEED_START
	layer_ref.add_child(sh)
	sh.global_position = o
	return sh


## The pack coughs the shell out: a green puff and ring, a pop of sparks and a hint of speed lines.
static func _launch_fx(parent: Node, o: Vector3, dir: Vector3) -> void:
	PartyFx.burst(parent, o, HomingShell.GREEN, 22, 5.0, 0.22, 0.4)
	PartyFx.ring_pulse(parent, o, dir, Color(0.7, 1.0, 0.75), 0.15, 1.2, 0.25, 0.12)
	PartyFx.sparks(parent, o, Color(0.8, 1.5, 0.9), 14, 6.0, dir, 50.0)
	PartyFx.smoke(parent, o, Color(0.85, 0.95, 0.85, 0.5), 8, 0.3, 0.6)
	PartyFx.speed_lines(parent, o, o + dir * 2.5, Color(0.9, 1.6, 1.0, 0.7), 10, 0.3)


static func remote_fx(layer_ref: PartyLayer, from_id: int, action: String, d: Dictionary) -> void:
	match action:
		"launch":
			var o: Vector3 = PowerUp.v3(d.get("o", []))
			var dir: Vector3 = PowerUp.v3(d.get("d", []))
			if dir.length() < 0.1:
				return
			spawn(layer_ref, str(d.get("k", "")), from_id, int(d.get("t", 0)), o, dir, false)
			_launch_fx(layer_ref, o, dir.normalized())
			layer_ref.sfx.play_at("shell", o, 0.9, 1.0)
		"boom":
			var sh: Variant = layer_ref.hazards.get(str(d.get("k", "")), null)
			if sh is HomingShell and is_instance_valid(sh):
				(sh as HomingShell).end(PowerUp.v3(d.get("at", [])), bool(d.get("hit", false)))
