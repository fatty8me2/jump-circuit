class_name PartyModeCoins
extends PartyMode
## Coin Rush: coins sit along the course's own route (the ground points its `r_*` steps walk and land on), so a
## racer collects them just by running the line. A KO makes the victim drop up to DROP_MAX of theirs where they
## fell - the coins can be grabbed by anyone. Every coin is a point; most coins wins the mode's points.
##
## Coin positions come from level.route, so every peer builds the same list; the host decides who got what
## (it scans every racer's position, and answers a client's "pick" request at once so a pickup feels instant).

const PICK_RADIUS: float = 1.7
const MIN_GAP: float = 5.5
const MAX_COINS: int = 70
## A route with fewer coin spots than this gets coins on its checkpoint lawns too.
const FILL_BELOW: int = 14
const DROP_MAX: int = 3
const FIRST_DROP_ID: int = 1000

## coin id -> Vector3 (world); ids below FIRST_DROP_ID are the route coins in order.
var coins: Dictionary = {}
var taken: Dictionary = {}
var count: Dictionary = {}
var _nodes: Dictionary = {}
var _mesh: Mesh
var _mat: Material
var _drop_n: int = 0
var _pending: Dictionary = {}
var _spin: float = 0.0
var _built: bool = false


func _init() -> void:
	id = "coins"


func _setup() -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.42
	cyl.bottom_radius = 0.42
	cyl.height = 0.09
	cyl.radial_segments = 20
	_mesh = cyl
	_mat = PartyFx.glow_mat(Color(1.0, 0.82, 0.15), 2.0, false)
	_build_route_coins()


func _build_route_coins() -> void:
	if _built or layer.level.route.is_empty():
		return
	_built = true
	var spots: Array[Vector3] = route_coin_points(layer.level)
	if spots.size() < FILL_BELOW:
		# a course with a short route (a ride, a flight): coins also lie on every checkpoint lawn
		for xf: Transform3D in layer.respawn_points():
			for ahead: float in [7.0, 5.0, 3.0, 1.0, -1.5]:
				for q: Vector3 in layer.lawn_spots(xf, [-2.0, 0.0, 2.0], [ahead]):
					_add_spot(spots, q, 2.2)
	var i: int = 0
	for p: Vector3 in spots:
		coins[i] = p
		i += 1
	_build_nodes()


## The coin spots for a level: every static ground point its route reaches (walk targets, jump landings, wall-run
## exits ...) plus evenly spaced points along its walked stretches, thinned to MIN_GAP apart.
static func route_coin_points(level: LevelBase) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var prev: Vector3 = Vector3.INF
	for step: Dictionary in level.route:
		var kind: String = str(step.get("kind", ""))
		var end: Vector3 = Vector3.INF
		if step.has("to_node") or step.has("node") and kind == "jump":
			end = Vector3.INF
		elif kind in ["walk", "jump", "pad", "b_jump", "x_pad", "kick", "w_run", "k_barrel", "k_zip"]:
			if step.get("to", Vector3.ZERO) is Vector3 and step["to"] != Vector3.ZERO:
				end = step["to"]
		elif kind == "m_climb" and step.get("top", Vector3.ZERO) is Vector3:
			end = step["top"]
		elif kind == "portal" and step.get("exit", Vector3.ZERO) is Vector3:
			end = step["exit"]
		if end == Vector3.INF:
			prev = Vector3.INF
			continue
		if kind == "walk" and prev != Vector3.INF:
			var d: float = prev.distance_to(end)
			var n: int = int(d / (MIN_GAP * 1.2))
			for k: int in range(1, n + 1):
				_add_spot(out, prev.lerp(end, float(k) / float(n + 1)))
		_add_spot(out, end)
		prev = end
		if out.size() >= MAX_COINS:
			break
	return out


static func _add_spot(out: Array[Vector3], p: Vector3, gap: float = MIN_GAP) -> void:
	if out.size() >= MAX_COINS:
		return
	for q: Vector3 in out:
		if q.distance_to(p) < gap:
			return
	out.append(p)


func _build_nodes() -> void:
	for cid: Variant in coins:
		_make_node(int(cid))


func _make_node(cid: int) -> void:
	if _nodes.has(cid):
		return
	var holder := Node3D.new()
	add_child(holder)
	holder.global_position = (coins[cid] as Vector3) + Vector3(0, 1.0, 0)
	var disc: MeshInstance3D = PartyFx.part(holder, _mesh, _mat, Vector3.ZERO, Vector3.ONE, Vector3(90, 0, 0))
	disc.name = "Disc"
	_nodes[cid] = holder


func remaining() -> int:
	return coins.size() - taken.size()


# ---- picking ----------------------------------------------------------------------------------------

func _near(p: Vector3, cid: int) -> bool:
	var c: Vector3 = coins[cid]
	return Vector2(p.x - c.x, p.z - c.z).length() <= PICK_RADIUS and absf(p.y + 0.9 - c.y) <= 2.2


func tick(dt: float) -> void:
	_build_route_coins()
	_spin += dt * 3.0
	for cid: Variant in _nodes:
		var n: Node3D = _nodes[cid]
		if is_instance_valid(n) and n.visible:
			n.rotation.y = _spin
			n.position.y = (coins[cid] as Vector3).y + 1.0 + 0.12 * sin(_spin + float(int(cid)))
	# our own pickups: hide the coin at once and tell the host
	if layer.is_out(Net.my_id()) or layer.level.finished:
		return
	var p: Vector3 = layer.player.global_position
	for cid: Variant in coins:
		var k: int = int(cid)
		if taken.has(k) or _pending.has(k):
			continue
		if _near(p, k):
			_pending[k] = clock
			if _nodes.has(k):
				(_nodes[k] as Node3D).visible = false
			ask({"m": "pick", "c": k})
	for k: Variant in _pending.keys():
		if clock - float(_pending[k]) > 1.0 and not taken.has(int(k)):
			_pending.erase(k)
			if _nodes.has(int(k)):
				(_nodes[int(k)] as Node3D).visible = true
	clock += dt


func host_tick(_dt: float) -> void:
	# CPUs and anyone the request path missed: scan every other racer's position
	for rid: int in active_ids():
		if rid == Net.my_id():
			continue
		var p: Vector3 = layer.racer_pos(rid)
		if p == Vector3.INF:
			continue
		for cid: Variant in coins:
			if not taken.has(int(cid)) and _near(p, int(cid)):
				_grant(int(cid), rid)
				break


func on_request(from_id: int, m: Dictionary) -> void:
	if not is_host() or str(m.get("m", "")) != "pick":
		return
	var cid: int = int(m.get("c", -1))
	if coins.has(cid) and not taken.has(cid) and Net.roster.has(from_id) and not layer.is_out(from_id) \
			and float(Net.roster[from_id].get("finished", -1.0)) < 0.0:
		_grant(cid, from_id)


func _grant(cid: int, rid: int) -> void:
	if taken.has(cid):
		return
	count[rid] = int(count.get(rid, 0)) + 1
	_apply_take(cid, rid, int(count[rid]))
	send({"m": "take", "c": cid, "id": rid, "n": int(count[rid])})


func _apply_take(cid: int, rid: int, n: int) -> void:
	taken[cid] = rid
	count[rid] = n
	_pending.erase(cid)
	if _nodes.has(cid):
		var holder: Node3D = _nodes[cid]
		if is_instance_valid(holder):
			var at: Vector3 = holder.global_position
			holder.queue_free()
			PartyFx.burst(layer, at, Color(1.0, 0.85, 0.2), 14, 4.0, 0.2, 0.45)
			PartyFx.star_ring(layer, at, Color(1.0, 0.9, 0.4), 5, 3.5, 0.3)
		_nodes.erase(cid)
	if rid == Net.my_id():
		layer.sfx.play("coin", 0.7, 1.0 + minf(float(n % 8) * 0.04, 0.3))
	else:
		layer.sfx.play_at("coin", coins.get(cid, Vector3.ZERO), 0.5)


# ---- KOs drop coins ------------------------------------------------------------------------------------------

func on_ko(_by: int, victim: int) -> void:
	if not is_host():
		return
	var n: int = mini(DROP_MAX, int(count.get(victim, 0)))
	if n <= 0:
		return
	count[victim] = int(count[victim]) - n
	var centre: Vector3 = layer.safe_spot_of(victim)
	if victim == Net.my_id():
		centre = layer.my_safe_spot()
	var list: Array = []
	for i: int in n:
		var a: float = TAU * float(i) / float(n) + 0.7
		var p: Vector3 = centre + Vector3(cos(a), 0, sin(a)) * 1.3
		_drop_n += 1
		var cid: int = FIRST_DROP_ID + _drop_n
		_add_drop(cid, p)
		list.append([cid, snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)])
	send({"m": "drop", "v": victim, "n": int(count[victim]), "l": list})
	feed("%s dropped %d coin%s" % [name_of(victim), n, "" if n == 1 else "s"], Color(1.0, 0.85, 0.3))


func _add_drop(cid: int, p: Vector3) -> void:
	coins[cid] = p
	_make_node(cid)
	if is_inside_tree():
		PartyFx.burst(layer, p + Vector3(0, 1.0, 0), Color(1.0, 0.85, 0.2), 10, 3.0, 0.2, 0.4)


func on_message(_from_id: int, m: Dictionary) -> void:
	match str(m.get("m", "")):
		"take":
			_apply_take(int(m.get("c", -1)), int(m.get("id", 0)), int(m.get("n", 0)))
		"drop":
			count[int(m.get("v", 0))] = int(m.get("n", 0))
			var raw: Variant = m.get("l", [])
			if typeof(raw) == TYPE_ARRAY:
				for e: Variant in raw:
					if typeof(e) == TYPE_ARRAY and (e as Array).size() >= 4:
						var a: Array = e
						_add_drop(int(a[0]), Vector3(float(a[1]), float(a[2]), float(a[3])))


# ---- scoring / HUD ----------------------------------------------------------------------------------------------------

func mode_points() -> Dictionary:
	return count.duplicate()


func state() -> Dictionary:
	return {"count": count.duplicate(), "taken": taken.size()}


func leader() -> int:
	var best: int = 0
	var best_n: int = 0
	for rid: Variant in count:
		if int(count[rid]) > best_n:
			best_n = int(count[rid])
			best = int(rid)
	return best


func round_note() -> String:
	var l: int = leader()
	return "" if l == 0 else "%s collected the most coins  (%d)" % [name_of(l), int(count[l])]


func points_label() -> String:
	return "Coins"


func hud_lines() -> Array[String]:
	var l: int = leader()
	var lines: Array[String] = ["COIN RUSH", "Your coins: %d" % int(count.get(Net.my_id(), 0))]
	if l != 0 and l != Net.my_id():
		lines.append("Leader: %s  (%d)" % [name_of(l), int(count[l])])
	elif l == Net.my_id():
		lines.append("You lead!")
	lines.append("%d coins left on the course" % remaining())
	return lines
