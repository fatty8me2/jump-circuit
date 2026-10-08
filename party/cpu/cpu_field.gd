class_name CpuField
extends Node
## CPU racers in a Party round. ARCHITECTURE
##
## * A CPU is a roster entry (id BASE_ID + slot, flag "cpu": true, cosmetics like a human's), so
##   Net.standings(), the level's ghosts, bonuses, KO scoring, round end and the results screen
##   treat it exactly like a peer. No other system knows CPUs exist.
## * Solo ("Party vs CPU"): Net.host_local() makes a one-person session (host, no peers); the
##   CPUs fill the roster. Online: the host's lobby option "Fill with CPUs" tops the roster up to
##   8 when a round starts and takes them out when the cup ends (so the lobby never fills up).
## * Only the HOST simulates them (this node, one CpuRacer + RouteWalker each) and broadcasts
##   their poses as Party packets - one batched "cpose" per 4 ticks over either transport. The
##   other peers run a CpuField too, but it only applies what the host sends.
## * Hits: a human's attack on a CPU's ghost goes through Net.send_party(to_id = CPU id), which
##   hands it to route_to_cpu() here (host: applied now; guest: wrapped as "cwrap" to the host).
##   A CPU's attack on a human is a victim-side "chit" (credited to the CPU's id) to that peer.
##
## Party packets (k), all from the host unless noted:
##   cpose {l: [[id, px,py,pz, vx,vy,vz, grounded, seq] ...]}   cp {id, i, at}   cfin {id, t}
##   cst {id, e, d} status look   cpw {id, p, on, d} power-up mirror   cfx {id, p, a, d} replay an item action
##   cko {by, v} a CPU was KO'd   chit {by, m} -> victim: apply hit m   cswap {by, pos, cp} -> victim
##   chf {by, v, s} HUD feed line for a CPU's hit   cuse {by, p} HUD feed line / warning for a CPU's item
##   cwrap also carries the Swap handshake (swap, swap_ok, swap_no) answered by / sent to CPUs
##   cwrap {to, m}  (guest -> host) a hit / swap on CPU `to`

const BASE_ID: int = 900
const MAX_RACERS: int = 8
## Poses go out as often as a human's (Net.POSE_INTERVAL): the relay bills every message.

## Lobby choices (kept for the session).
static var fill_online: bool = false
## Online fill target (racers the roster is topped up to) - the host's "CPU fill" rule.
static var fill_to: int = 8
static var difficulty: String = CpuSkill.NORMAL
static var local_count: int = 3
static var current: CpuField = null
## Tests set this to make a round's CPU randomness repeatable (-1 = random).
static var test_seed: int = -1
static var _order: Array[String] = []
static var _ident: Dictionary = {}

var layer: PartyLayer
var level: LevelBase
var racers: Dictionary = {}
var clock: float = 0.0
var _pose_acc: float = 0.0
var _standing: Array[int] = []
var _stand_t: float = 99.0
var _key_n: int = 0
var _tornado_cd: Dictionary = {}


# ---- roster management (host; static so the lobby / Net can call them) ---------------------------

static func is_cpu_id(id: int) -> bool:
	return id >= BASE_ID and id < BASE_ID + MAX_RACERS


static func cpu_ids() -> Array[int]:
	var out: Array[int] = []
	for id: int in Net.roster:
		if bool((Net.roster[id] as Dictionary).get("cpu", false)):
			out.append(id)
	out.sort()
	return out


static func human_count() -> int:
	return Net.roster.size() - cpu_ids().size()


## How many CPUs the next round should have, given the session.
static func wanted_count() -> int:
	if Net.game_mode == "race" or not Net.is_host():
		return 0
	var room: int = MAX_RACERS - human_count()
	if Net.local_session:
		return clampi(local_count, 0, room)
	if fill_online:
		return clampi(mini(fill_to, MAX_RACERS) - human_count(), 0, room)
	return 0


## The host's CPU-fill rule (PartyRuleset "cpu": 0 off, else fill to N racers) switches the online fill.
static func apply_ruleset() -> void:
	var n: int = int(PartyRuleset.cur()["cpu"])
	fill_online = n > 0
	fill_to = n if n > 0 else 8


## Host: make the roster hold exactly the CPUs wanted (no-op when it already does).
static func sync_roster() -> void:
	if not Net.is_host():
		return
	var want: int = wanted_count()
	var have: Array[int] = cpu_ids()
	var same: bool = have.size() == want
	for i: int in have.size():
		if not same:
			break
		if have[i] != BASE_ID + i or str((Net.roster[have[i]] as Dictionary).get("diff", "")) != difficulty:
			same = false
	if same:
		return
	for id: int in have:
		Net.roster.erase(id)
		Net.teams.erase(id)
	for slot: int in want:
		_add(slot)
	_publish()


## Takes every CPU out of the roster (cup over / back in the lobby).
static func clear_roster() -> void:
	var have: Array[int] = cpu_ids()
	if have.is_empty():
		return
	for id: int in have:
		Net.roster.erase(id)
		Net.teams.erase(id)
	_publish()


static func _publish() -> void:
	if Net.is_host() and not Net.local_session:
		Net._broadcast_roster()
	Net.roster_changed.emit()


static func _add(slot: int) -> void:
	var id: int = BASE_ID + slot
	var e: Dictionary = identity(slot).duplicate()
	e["cp"] = 0
	e["cp_at"] = 0.0
	e["finished"] = -1.0
	e["cpu"] = true
	e["diff"] = difficulty
	e["color"] = Net._free_color(id, int(e["color"]))
	Net.roster[id] = e
	if Net.game_mode == "team" and not Net.teams.has(id):
		Net.teams[id] = PartyRules.smaller_team(Net.teams)


## Local session: how many CPUs and how good.
static func configure_local(count: int, diff: String) -> void:
	local_count = clampi(count, 0, MAX_RACERS - 1)
	difficulty = diff if CpuSkill.valid(diff) else CpuSkill.NORMAL


static func reset_identities() -> void:
	_ident.clear()
	_order.clear()


## A CPU's name, colour and cosmetics: stable for a slot over the whole cup, mostly things the
## owner has unlocked (so the field looks like the game), sometimes anything.
static func identity(slot: int) -> Dictionary:
	if _ident.has(slot):
		return _ident[slot]
	if _order.is_empty():
		_order.assign(CpuSkill.NAMES)
		_order.shuffle()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var d: Dictionary = {"name": _order[slot % _order.size()], "color": (slot * 3 + 2) % Settings.RACER_COLORS.size()}
	for kind: String in Cosmetics.kinds():
		var all: Array[String] = Cosmetics.ids(kind)
		var pool: Array[String] = []
		for cid: String in all:
			if Cosmetics.is_unlocked(kind, cid):
				pool.append(cid)
		if pool.is_empty() or rng.randf() < 0.3:
			pool = all
		d[kind] = pool[rng.randi() % pool.size()]
	_ident[slot] = d
	return d


# ---- hooks called from other files ------------------------------------------------------------------

## PartyLayer.setup: adds the CPU field when the round has CPUs.
static func attach(p_layer: PartyLayer) -> void:
	if cpu_ids().is_empty():
		return
	var f := CpuField.new()
	f.name = "CpuField"
	p_layer.add_child(f)
	f.setup(p_layer)


## Net.send_party for a CPU target. A human's hit / swap on a CPU: the host applies it, a guest
## hands it to the host. Returns true when handled.
static func route_to_cpu(to_id: int, msg: Dictionary) -> bool:
	if current == null or not is_instance_valid(current):
		return true   # (no round running: nothing to hit)
	if Net.is_host():
		current._apply_wrapped(Net.my_id(), to_id, msg)
	else:
		Net.send_party({"k": "cwrap", "to": to_id, "m": msg}, 1)
	return true


# ---- per round ---------------------------------------------------------------------------------------

func setup(p_layer: PartyLayer) -> void:
	layer = p_layer
	level = p_layer.level
	current = self
	Net.party_message.connect(_on_message)
	if not Net.is_host():
		return
	var seed_base: int = test_seed if test_seed >= 0 else int(Time.get_ticks_usec())
	for id: int in cpu_ids():
		var ghost: RemoteRacer = level._ghosts.get(id) as RemoteRacer
		var at: Vector3 = ghost.global_position if ghost != null else level._spawn.origin
		var r := CpuRacer.new()
		r.setup(id, str(Net.roster[id]["name"]), level, str(Net.roster[id].get("diff", difficulty)), at, seed_base + id * 7919)
		racers[id] = r


func _exit_tree() -> void:
	if current == self:
		current = null


func _physics_process(dt: float) -> void:
	if racers.is_empty() or layer == null or layer.round_over:
		return
	if not Game.race_mode or Game.course_time < 0.0 or not level._started:
		return
	clock += dt
	_stand_t += dt
	if _stand_t > 0.5:
		_stand_t = 0.0
		_standing = Net.standings()
	for r: CpuRacer in racers.values():
		r.tick(dt, self)
	_tick_hazards()
	_pose_acc += dt
	if _pose_acc >= Net.POSE_INTERVAL - 0.002:
		_pose_acc = 0.0
		_send_poses()


func _send_poses() -> void:
	var list: Array = []
	for r: CpuRacer in racers.values():
		var w: RouteWalker = r.walker
		Net._emit_pose(r.id, w.pos, w.vel, w.grounded, w.seq)
		list.append([r.id, snappedf(w.pos.x, 0.01), snappedf(w.pos.y, 0.01), snappedf(w.pos.z, 0.01),
			snappedf(w.vel.x, 0.01), snappedf(w.vel.y, 0.01), snappedf(w.vel.z, 0.01), 1 if w.grounded else 0, w.seq])
	Net.send_party({"k": "cpose", "l": list})


## Hazards other racers placed (Slick Puddles, Tornadoes) are caught by the victim's own client, which
## for a CPU is this one: they catch CPUs just as they catch a human's Player.
func _tick_hazards() -> void:
	for key: Variant in layer.hazards.keys():
		var hz: Variant = layer.hazards.get(key)
		if hz == null or not is_instance_valid(hz):
			continue
		for r: CpuRacer in racers.values():
			if r.finished or r.protect_left > 0.0:
				continue
			if hz is SlickPuddle:
				var puddle: SlickPuddle = hz
				if puddle.used or puddle._age < 0.3 or r.id == puddle.owner_id or not is_rival(puddle.owner_id, r.id):
					continue
				if puddle._touches(r.walker.pos):
					var fwd: Vector3 = RouteMath.flat(r.walker.facing).normalized()
					r.take_hit(puddle.owner_id, {"kb": PowerUp.arr(fwd * 7.0 + Vector3(0, 6.5, 0)), "e": "spin", "ed": 1.3, "s": "slick"}, self)
					puddle.consume(true)
					break
			elif hz is FakeBox:
				var fb: FakeBox = hz
				if fb.used or fb._age < 0.4 or r.id == fb.owner_id or not is_rival(fb.owner_id, r.id) or r.ghost_left > 0.0:
					continue
				if fb._touches(r.walker.pos + Vector3(0, 0.8, 0)):
					var back: Vector3 = -RouteMath.flat(r.walker.facing).normalized()
					r.take_hit(fb.owner_id, {"kb": PowerUp.arr(back * 4.0 + Vector3(0, 11.0, 0)), "st": FakeBox.STUN, "e": "stun", "ed": FakeBox.STUN, "s": "fakebox"}, self)
					cpu_hit_feed(fb.owner_id, r.id, "fakebox")
					fb.consume(true)
					break
			elif hz is PartyTornado:
				var tw: PartyTornado = hz
				var ck: String = "%s:%d" % [str(key), r.id]
				if tw.owner_id == r.id or not is_rival(tw.owner_id, r.id) or float(_tornado_cd.get(ck, -1.0)) > clock:
					continue
				if tw._catches(r.walker.pos):
					_tornado_cd[ck] = clock + 1.6
					var out: Vector3 = RouteMath.flat(r.walker.pos - tw.global_position)
					var tangent: Vector3 = out.normalized().cross(Vector3.UP) if out.length() > 0.1 else Vector3.RIGHT
					r.take_hit(tw.owner_id, {"kb": PowerUp.arr(tangent * 9.0 + out.normalized() * 3.0 + Vector3(0, 17.0, 0)),
						"st": 0.7, "e": "spin", "ed": 1.0, "s": "tornado"}, self)


# ---- what a CPU does (called by CpuRacer / CpuItems) ---------------------------------------------------

func is_rival(a: int, b: int) -> bool:
	if a == b:
		return false
	return not (layer.rules.is_team() and Net.team_of(a) == Net.team_of(b))


func rank_of(id: int) -> int:
	var i: int = _standing.find(id)
	return i + 1 if i >= 0 else 99


## Mild catch-up: a CPU two checkpoints behind every human closes in; on Easy / Normal one that
## is two ahead eases off, so the field stays together.
func catch_up(r: CpuRacer) -> float:
	var lead: int = -1
	for id: int in Net.roster:
		var e: Dictionary = Net.roster[id]
		if not bool(e.get("cpu", false)) and float(e.get("finished", -1.0)) < 0.0:
			lead = maxi(lead, int(e["cp"]))
	if lead < 0:
		return 1.0
	var mine: int = int(Net.roster[r.id]["cp"])
	if mine + 2 <= lead:
		return 1.12
	if mine >= lead + 2 and str(r.p.get("diff", "")) != CpuSkill.HARD:
		return 0.9
	return 1.0


## Course progress (metres) of racer `id` at `pos`, the way PartyLayer ranks Swap / Thunder targets.
func progress_of(id: int, pos: Vector3) -> float:
	return layer.progress_of(int(Net.roster.get(id, {}).get("cp", 0)), pos)


## HUD feed ("Bolt iced Ana!") for a CPU's hit; everyone's feed hears of it.
func cpu_hit_feed(by: int, victim: int, src: String) -> void:
	if src == "" or victim <= 0:
		return
	layer.hud.on_hit_event(by, victim, src)
	Net.send_party({"k": "chf", "by": by, "v": victim, "s": src})


## A CPU used an item: the feed line, and the "Targeted!" warning for those it threatens.
func cpu_used(r: CpuRacer, item: String) -> void:
	layer.hud.on_item_used(r.id, item)
	Net.send_party({"k": "cuse", "by": r.id, "p": item})


## A blast (Leader Strike) on the host: every CPU within `radius` of `at` (flat) that is a rival of the
## caster is thrown away from the centre. o: vy (upward kick), st, e, ed, s.
func area_hit(owner: int, at: Vector3, radius: float, height: float, push: float, o: Dictionary) -> void:
	for r: CpuRacer in racers.values():
		if r.id == owner or r.finished or not is_rival(owner, r.id):
			continue
		var d: Vector3 = r.walker.pos - at
		if Vector2(d.x, d.z).length() > radius or absf(d.y) > height:
			continue
		var away: Vector3 = RouteMath.flat(d)
		away = away.normalized() if away.length() > 0.2 else Vector3.RIGHT
		var m: Dictionary = {"kb": PowerUp.arr(away * push + Vector3(0, float(o.get("vy", 10.0)), 0)), "st": float(o.get("st", 0.0)),
			"e": str(o.get("e", "")), "ed": float(o.get("ed", 0.0)), "s": str(o.get("s", ""))}
		var had: bool = r.protect_left <= 0.0 and r.shield_left <= 0.0 and r.ghost_left <= 0.0
		r.take_hit(owner, m, self)
		if had:
			cpu_hit_feed(owner, r.id, str(o.get("s", "")))


## A CPU Ghost reaches into `rv` (a CPU, our own human, or a remote human).
func steal_from_rival(thief: CpuRacer, rv: Dictionary) -> void:
	var rid: int = int(rv["id"])
	var victim: CpuRacer = rv.get("cpu") as CpuRacer
	thief.steal_wait = clock
	if victim != null:
		thief.steal_result(victim.steal_from(thief.id, self), self)
	elif bool(rv.get("local", false)):
		layer._on_steal(thief.id)
	else:
		Net.send_party({"k": "steal", "by": thief.id}, rid)


## The answer to a CPU's theft: the racer holding the loot slot gets it.
func steal_reply(to_id: int, m: Dictionary) -> void:
	var r: CpuRacer = racers.get(to_id) as CpuRacer
	if r != null:
		r.steal_result(m, self)


## An answer in the Swap handshake: to a CPU, to the host's own human, or over the wire.
func reply(to_id: int, from_id: int, msg: Dictionary) -> void:
	if racers.has(to_id):
		_deliver_swap(racers[to_id], msg)
	elif to_id == Net.my_id():
		layer._on_message(from_id, msg)
	else:
		Net.send_party(msg, to_id)


func _deliver_swap(r: CpuRacer, msg: Dictionary) -> void:
	match str(msg.get("k", "")):
		"swap_ok":
			r.swap_ok(PowerUp.v3(msg.get("pos", [])), int(msg.get("cp", 0)), self)
		"swap_no":
			r.swap_no()


func new_key(id: int) -> String:
	_key_n += 1
	return "%d_c%d" % [id, _key_n]


## Everyone this CPU could hit: {id, pos (feet), center, vel, grounded, cpu: CpuRacer|null, local}
## - never teammates or racers who finished.
func rivals_of(r: CpuRacer) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: int in Net.roster:
		if id == r.id or float(Net.roster[id].get("finished", -1.0)) >= 0.0 or not is_rival(r.id, id) or layer.is_out(id):
			continue
		var d: Dictionary = {"id": id, "cpu": null, "local": false}
		if racers.has(id):
			var o: CpuRacer = racers[id]
			d["cpu"] = o
			d["pos"] = o.walker.pos
			d["vel"] = o.walker.vel
			d["grounded"] = o.walker.grounded
		elif id == Net.my_id():
			d["local"] = true
			d["pos"] = layer.player.global_position
			d["vel"] = layer.player.velocity
			d["grounded"] = layer.player.grounded
		elif level._ghosts.has(id):
			var g: RemoteRacer = level._ghosts[id]
			d["pos"] = g.global_position
			d["vel"] = g.velocity()
			d["grounded"] = g.is_grounded()
		else:
			continue
		d["center"] = (d["pos"] as Vector3) + Vector3(0, 0.8, 0)
		out.append(d)
	# decoys look like their owners to a CPU too: a shell chases one, a shove lands on one
	for dc: PartyDecoy in layer.decoys:
		if not is_instance_valid(dc) or dc.popped or dc.owner_id == r.id or not is_rival(r.id, dc.owner_id):
			continue
		out.append({"id": dc.id, "cpu": null, "local": false, "decoy": dc, "owner": dc.owner_id, "pos": dc.global_position,
			"vel": dc.vel, "grounded": dc.grounded, "center": dc.center()})
	return out


## Is the ground missing within a step of `at` (a rival on a beam / ledge)?
func edge_near(at: Vector3, dir: Vector3) -> bool:
	var space: PhysicsDirectSpaceState3D = level.get_world_3d().direct_space_state
	var side: Vector3 = dir.cross(Vector3.UP).normalized()
	for off: Vector3 in [dir * 1.8, side * 1.6, -side * 1.6]:
		var q := PhysicsRayQueryParameters3D.create(at + off + Vector3(0, 1.0, 0), at + off + Vector3(0, -3.0, 0), RouteWalker.GROUND_MASK)
		if space.intersect_ray(q).is_empty():
			return true
	return false


func cpu_take_box(r: CpuRacer, b: ItemBox) -> void:
	if layer.round_over or not b.available:
		return
	var it: String = layer.roll_for(r.id)
	layer._take_box(b.index, r.id, it, layer.box_respawn_time())
	Net.send_party({"k": "box", "b": b.index, "id": r.id, "it": it, "r": layer.box_respawn_time()})
	r.give(it)


func cpu_checkpoint(r: CpuRacer, index: int) -> void:
	var at: float = Net.now()
	Net._apply_checkpoint(r.id, index, at)
	Net.send_party({"k": "cp", "id": r.id, "i": index, "at": at})


func cpu_finish(r: CpuRacer) -> void:
	var at: float = Net.now()
	r.clear_buffs(self)
	cpu_checkpoint(r, level.checkpoints.size() + 1)
	var t: float = Game.course_time
	Net._apply_finished(r.id, t)
	Net.send_party({"k": "cfin", "id": r.id, "t": t})


## It fell or was caught: a KO for whoever hit it in the last few seconds.
func cpu_fail(r: CpuRacer, _cause: String) -> void:
	var by: int = PartyRules.ko_credit(r.last_hit_by, r.last_hit_at, clock)
	r.last_hit_by = 0
	r.clear_buffs(self)
	if by != 0 and by != r.id and not layer.round_over:
		layer._apply_ko(by, r.id)
		Net.send_party({"k": "cko", "by": by, "v": r.id})


func cpu_power(id: int, p: String, on: bool, d: float = 10.0) -> void:
	layer._remote_power(id, p, on, d)
	Net.send_party({"k": "cpw", "id": id, "p": p, "on": on, "d": d})


func cpu_fx(id: int, p: String, a: String, d: Dictionary) -> void:
	layer._remote_fx(id, p, a, d)
	Net.send_party({"k": "cfx", "id": id, "p": p, "a": a, "d": d})


func cpu_status(id: int, e: String, d: float) -> void:
	layer._show_ghost_status(id, e, d)
	Net.send_party({"k": "cst", "id": id, "e": e, "d": d})


## A CPU's hit on `rival` (see CpuRacer.take_hit for the hit message shape).
func hit_rival(r: CpuRacer, rival: Dictionary, kb: Vector3, o: Dictionary = {}) -> void:
	var m: Dictionary = {"kb": PowerUp.arr(kb), "st": float(o.get("st", 0.0)), "ko": false, "e": str(o.get("e", "")),
		"ed": float(o.get("ed", 0.0)), "s": str(o.get("s", "")), "add": bool(o.get("add", false))}
	var rid: int = int(rival["id"])
	if rival.get("decoy") != null:
		(rival["decoy"] as PartyDecoy).take_hit(kb, o)
		return
	var target: CpuRacer = rival.get("cpu") as CpuRacer
	if target != null:
		target.take_hit(r.id, m, self)
	elif rid == Net.my_id():
		layer._on_hit(r.id, m)
	else:
		Net.send_party({"k": "chit", "by": r.id, "m": m}, rid)
	cpu_hit_feed(r.id, rid, str(o.get("s", "")))
	if layer.mode != null:
		layer.mode.on_hit(r.id, rid, str(o.get("s", "")))
	if not bool(o.get("quiet", false)):
		layer.hit_fx(rival["center"] as Vector3, kb)


## The Shove - or, in a transformation, its stronger melee.
func cpu_shove(r: CpuRacer, rival: Dictionary, dir: Vector3) -> void:
	var strong: bool = r.form != ""
	r.protect_left = 0.0   # attacking ends the respawn grace
	var k: float = 1.0
	var tv: Vector3 = RouteMath.flat(rival["vel"] as Vector3)
	if tv.length() > 1.5 and tv.normalized().dot(dir) > 0.4:
		k *= 1.4
	if not bool(rival["grounded"]):
		k *= 1.35
	var power: float = 11.5
	var src: String = "shove"
	if strong:
		power = {"fox": 17.0, "tunic": 14.0, "surge": 15.0}.get(r.form, 14.0)
		src = {"fox": "claw", "tunic": "blade", "surge": "dash_punch"}.get(r.form, "shove")
		r.claw_cd = CpuRacer.CLAW_COOLDOWN
	else:
		r.shove_cd = CpuRacer.SHOVE_COOLDOWN
	cpu_fx(r.id, "shove", "swing", {"o": PowerUp.arr(r.walker.pos + Vector3(0, 0.8, 0)), "d": PowerUp.arr(dir)})
	hit_rival(r, rival, dir * power * k + Vector3(0, 5.5 * minf(k, 1.3), 0), {"st": 0.45 if strong else 0.25, "s": src})


# ---- network ---------------------------------------------------------------------------------------------

func _apply_wrapped(from_id: int, to_id: int, m: Dictionary) -> void:
	var r: CpuRacer = racers.get(to_id) as CpuRacer
	if r == null:
		return
	match str(m.get("k", "")):
		"hit":
			r.take_hit(from_id, m, self)
		"swap":
			r.swap_request(from_id, PowerUp.v3(m.get("pos", [])), int(m.get("cp", 0)), self)
		"swap_ok", "swap_no":
			_deliver_swap(r, m)
		"steal":
			# a human Ghost robs this CPU: answer them directly
			reply(from_id, to_id, r.steal_from(from_id, self))
		"stolen", "steal_no":
			r.steal_result(m, self)


func _on_message(from_id: int, m: Dictionary) -> void:
	if not is_inside_tree():
		return
	var k: String = str(m.get("k", ""))
	if k == "cwrap":
		if Net.is_host() and typeof(m.get("m")) == TYPE_DICTIONARY:
			_apply_wrapped(from_id, int(m.get("to", 0)), m["m"] as Dictionary)
		return
	if from_id != 1 or Net.is_host() or not k.begins_with("c"):
		return
	match k:
		"cpose":
			for e: Variant in m.get("l", []):
				var a: Array = e
				if a.size() >= 9:
					Net._emit_pose(int(a[0]), Vector3(float(a[1]), float(a[2]), float(a[3])),
						Vector3(float(a[4]), float(a[5]), float(a[6])), int(a[7]) == 1, int(a[8]))
		"cp":
			Net._apply_checkpoint(int(m.get("id", 0)), int(m.get("i", 0)), float(m.get("at", 0.0)))
		"cfin":
			Net._apply_finished(int(m.get("id", 0)), float(m.get("t", 0.0)))
		"cst":
			layer._show_ghost_status(int(m.get("id", 0)), str(m.get("e", "")), float(m.get("d", 1.0)))
		"cpw":
			layer._remote_power(int(m.get("id", 0)), str(m.get("p", "")), bool(m.get("on", false)), float(m.get("d", 10.0)))
		"cfx":
			if typeof(m.get("d")) == TYPE_DICTIONARY:
				layer._remote_fx(int(m.get("id", 0)), str(m.get("p", "")), str(m.get("a", "")), m["d"] as Dictionary)
		"cko":
			layer._apply_ko(int(m.get("by", 0)), int(m.get("v", 0)))
		"chit":
			if typeof(m.get("m")) == TYPE_DICTIONARY:
				layer._on_hit(int(m.get("by", 0)), m["m"] as Dictionary)
		"cswap":
			layer._on_swap(int(m.get("by", 0)), PowerUp.v3(m.get("pos", [])), int(m.get("cp", 0)))
		"chf":
			layer.hud.on_hit_event(int(m.get("by", 0)), int(m.get("v", 0)), str(m.get("s", "")))
		"cuse":
			layer.hud.on_item_used(int(m.get("by", 0)), str(m.get("p", "")))
