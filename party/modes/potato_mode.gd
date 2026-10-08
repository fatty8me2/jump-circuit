class_name PartyModePotato
extends PartyMode
## Hot Potato: one racer carries a lit bomb. Landing a Shove or any attack on a rival passes it to them (the
## holder's own client, or the host for a CPU, tells the host). When the fuse runs out the holder blows up -
## knocked back to their checkpoint and BLAST_PENALTY points down - everyone else who is still racing gets
## SURVIVE_PTS, and the bomb goes to someone new with a fresh fuse.

const FUSE: float = 18.0
const FIRST_DELAY: float = 6.0
const PASS_GAP: float = 0.8
const BACK_GAP: float = 2.5
const MIN_AFTER_PASS: float = 3.0
const BLAST_PENALTY: int = 3
const SURVIVE_PTS: int = 1
const SYNC_EVERY: float = 1.0

var holder: int = 0
var fuse: float = FUSE
var pts: Dictionary = {}
var blasts: Dictionary = {}
var _last_passer: int = 0
var _last_pass_at: float = -9.0
var _sync_t: float = 0.0
var _bomb: Node3D
var _bomb_on: int = 0
var _tick_t: float = 0.0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	id = "potato"


func _setup() -> void:
	_rng.seed = int(Time.get_ticks_usec()) ^ 0x70747
	fuse = FUSE


# ---- host rules ------------------------------------------------------------------------------------

func _eligible() -> Array[int]:
	return active_ids()


func host_tick(dt: float) -> void:
	if Game.course_time < FIRST_DELAY:
		return
	var el: Array[int] = _eligible()
	if el.size() < 2:
		if holder != 0:
			holder = 0
			send({"m": "pt", "h": 0, "f": fuse})
		return
	if holder == 0 or not el.has(holder):
		_new_holder(el, 0)
		return
	fuse -= dt
	if fuse <= 0.0:
		_boom(el)
		return
	_sync_t -= dt
	if _sync_t <= 0.0:
		_sync_t = SYNC_EVERY
		send({"m": "pt", "h": holder, "f": fuse})


func _new_holder(el: Array[int], skip: int) -> void:
	var pool: Array[int] = []
	for rid: int in el:
		if rid != skip:
			pool.append(rid)
	if pool.is_empty():
		pool = el
	holder = pool[_rng.randi() % pool.size()]
	fuse = FUSE
	_sync_t = SYNC_EVERY
	_apply_holder(holder, 0)
	send({"m": "pt", "h": holder, "f": fuse, "new": true})


func _boom(el: Array[int]) -> void:
	var victim: int = holder
	pts[victim] = int(pts.get(victim, 0)) - BLAST_PENALTY
	blasts[victim] = int(blasts.get(victim, 0)) + 1
	for rid: int in el:
		if rid != victim:
			pts[rid] = int(pts.get(rid, 0)) + SURVIVE_PTS
	_apply_boom(victim)
	_new_holder(el, victim)
	var list: Array = []
	for rid: Variant in pts:
		list.append([int(rid), int(pts[rid])])
	send({"m": "boom", "v": victim, "p": list})


func on_hit(by: int, victim: int, _src: String) -> void:
	if by != holder or victim <= 0 or holder == 0:
		return
	ask({"m": "pass", "to": victim})


func on_request(from_id: int, m: Dictionary) -> void:
	if not is_host() or str(m.get("m", "")) != "pass":
		return
	var to: int = int(m.get("to", 0))
	var el: Array[int] = _eligible()
	var now: float = Game.course_time
	if from_id != holder or not el.has(to) or to == from_id:
		return
	if now - _last_pass_at < PASS_GAP or (to == _last_passer and now - _last_pass_at < BACK_GAP):
		return
	_last_pass_at = now
	_last_passer = from_id
	holder = to
	fuse = maxf(fuse, MIN_AFTER_PASS)
	_apply_holder(to, from_id)
	send({"m": "pt", "h": to, "f": fuse, "from": from_id})


func on_message(_from_id: int, m: Dictionary) -> void:
	match str(m.get("m", "")):
		"pt":
			var h: int = int(m.get("h", 0))
			var from: int = int(m.get("from", 0))
			fuse = float(m.get("f", fuse))
			if h != holder or from != 0 or bool(m.get("new", false)):
				holder = h
				_apply_holder(h, from)
			holder = h
		"boom":
			var raw: Variant = m.get("p", [])
			if typeof(raw) == TYPE_ARRAY:
				for e: Variant in raw:
					if typeof(e) == TYPE_ARRAY and (e as Array).size() >= 2:
						pts[int((e as Array)[0])] = int((e as Array)[1])
			_apply_boom(int(m.get("v", 0)))


# ---- effects (every peer) -----------------------------------------------------------------------------------

func _node_of(rid: int) -> Node3D:
	if rid == Net.my_id():
		return layer.player
	return layer.ghost(rid)


func _apply_holder(rid: int, from: int) -> void:
	holder = rid
	_attach_bomb()
	if rid == 0:
		return
	var n: Node3D = _node_of(rid)
	if from != 0:
		var a: Node3D = _node_of(from)
		if a != null and n != null:
			PartyFx.tether(layer, a.global_position + Vector3(0, 1.0, 0), n.global_position + Vector3(0, 1.0, 0), Color(1.0, 0.5, 0.2))
		layer.sfx.play_at("pass", n.global_position if n != null else Vector3.ZERO, 0.8)
		feed("%s passed the bomb to %s" % [name_of(from), name_of(rid)], Color(1.0, 0.6, 0.3))
	if rid == Net.my_id():
		announce("YOU HAVE THE BOMB!  Shove someone!", Color(1.0, 0.4, 0.2))
		layer.sfx.play("warn", 0.8)
	elif from == Net.my_id() or from == 0:
		announce("%s has the bomb" % name_of(rid), Color(1.0, 0.7, 0.3))


func _attach_bomb() -> void:
	if _bomb != null and is_instance_valid(_bomb):
		_bomb.queue_free()
	_bomb = null
	if holder == 0:
		return
	var n: Node3D = _node_of(holder)
	if n == null:
		return
	_bomb = Node3D.new()
	_bomb.name = "PotatoBomb"
	n.add_child(_bomb)
	_bomb.position = Vector3(0, 2.35, 0)
	var body: MeshInstance3D = PartyFx.part(_bomb, PartyFx.sphere_mesh(0.34, 16), PartyFx.solid_mat(Color(0.08, 0.08, 0.1), 0.0, 0.4, 0.3), Vector3.ZERO)
	body.name = "Body"
	PartyFx.part(_bomb, PartyFx.cyl_mesh(0.07, 0.16), PartyFx.solid_mat(Color(0.35, 0.3, 0.25)), Vector3(0, 0.36, 0))
	var spark: MeshInstance3D = PartyFx.part(_bomb, PartyFx.sphere_mesh(0.09, 8), PartyFx.glow_mat(Color(1.0, 0.7, 0.2), 3.0), Vector3(0.05, 0.5, 0))
	spark.name = "Spark"
	var sparks: GPUParticles3D = PartyFx.emitter({"amount": 14, "lifetime": 0.4, "size": 0.12, "color": Color(1.0, 0.7, 0.2), "dir": Vector3.UP,
		"spread": 40.0, "vmin": 0.8, "vmax": 1.8, "colors": [Color(1, 0.9, 0.4, 1), Color(1, 0.3, 0.05, 0)], "aabb": 3.0})
	_bomb.add_child(sparks)
	sparks.position = Vector3(0.05, 0.5, 0)


func _apply_boom(victim: int) -> void:
	var n: Node3D = _node_of(victim)
	var at: Vector3 = (n.global_position if n != null else Vector3.ZERO) + Vector3(0, 1.0, 0)
	if n != null:
		PartyFx.explosion(layer, at, Color(1.0, 0.6, 0.2), Color(1.0, 0.25, 0.1), 3.0)
		PartyFx.shockwave(layer, at, Color(1.0, 0.6, 0.2), 4.5, 0.5)
		PartyFx.shake(layer.level, 0.8 if victim == Net.my_id() else 0.35)
		layer.sfx.play_at("blast", at, 1.0)
	holder = 0
	_attach_bomb()
	feed("%s blew up!   -%d" % [name_of(victim), BLAST_PENALTY], Color(1.0, 0.45, 0.25))
	if victim == Net.my_id():
		layer.last_hit_by = 0   # the bomb, not a rival, knocked us out: nobody scores a KO
		announce("BOOM!  -%d" % BLAST_PENALTY, Color(1.0, 0.35, 0.2))
		layer.level.fail("hazard")
	var f: CpuField = CpuField.current
	if f != null and is_instance_valid(f) and f.racers.has(victim):
		var r: CpuRacer = f.racers[victim]
		r.last_hit_by = 0
		r.walker.die("potato")


func tick(dt: float) -> void:
	clock += dt
	if holder == 0:
		return
	if not is_host():
		fuse = maxf(fuse - dt, 0.0)
	if _bomb != null and is_instance_valid(_bomb):
		var hurry: float = clampf(1.0 - fuse / FUSE, 0.0, 1.0)
		var rate: float = lerpf(3.0, 14.0, hurry)
		var on: bool = fmod(clock * rate, 1.0) < 0.5
		var s: float = 1.0 + 0.12 * sin(clock * rate * TAU * 0.5) + hurry * 0.25
		_bomb.scale = Vector3.ONE * s
		var body: MeshInstance3D = _bomb.get_node_or_null("Body") as MeshInstance3D
		if body != null:
			body.material_override = PartyFx.solid_mat(Color(1.0, 0.15, 0.05), 1.5, 0.4, 0.3) if (on and hurry > 0.35) else PartyFx.solid_mat(Color(0.08, 0.08, 0.1), 0.0, 0.4, 0.3)
	if holder == Net.my_id():
		_tick_t -= dt
		if _tick_t <= 0.0:
			_tick_t = lerpf(0.9, 0.18, clampf(1.0 - fuse / FUSE, 0.0, 1.0))
			layer.sfx.play("fuse", 0.5, lerpf(0.9, 1.5, clampf(1.0 - fuse / FUSE, 0.0, 1.0)))


# ---- scoring / HUD ---------------------------------------------------------------------------------------------------

func mode_points() -> Dictionary:
	return pts.duplicate()


func state() -> Dictionary:
	return {"holder": holder, "fuse": fuse, "pts": pts.duplicate()}


func round_note() -> String:
	var worst: int = 0
	var n: int = 0
	for rid: Variant in blasts:
		if int(blasts[rid]) > n:
			n = int(blasts[rid])
			worst = int(rid)
	return "" if worst == 0 else "%s blew up %d time%s" % [name_of(worst), n, "" if n == 1 else "s"]


func points_label() -> String:
	return "Bomb"


func hud_lines() -> Array[String]:
	var lines: Array[String] = ["HOT POTATO"]
	if holder == 0:
		lines.append("The bomb is coming...")
	elif holder == Net.my_id():
		lines.append("YOU have the bomb!  Shove a rival!  (%.1f)" % fuse)
	else:
		lines.append("%s has the bomb   (%.0f)" % [name_of(holder), fuse])
	lines.append("Bomb points: %d" % int(pts.get(Net.my_id(), 0)))
	return lines


func hud_color() -> Color:
	return Color(1.0, 0.3, 0.2) if holder == Net.my_id() else Color(1.0, 0.7, 0.3)
