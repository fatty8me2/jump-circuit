class_name PartyLayer
extends Node3D
## Party Mode inside a level. LevelBase adds exactly one of these when Game.party is set (a
## Party / Team Party race, or Party Practice) - never in the main mode.
##
## Owns: item boxes (placed from the level's checkpoints at runtime), the local item slot and
## active power-ups, the Shove, hit detection against rivals' ghosts / practice dummies, the
## victim side of hits (knockback, stun, status effects, KOs), and the Party Cup round (the
## host decides pickups, bonuses and the round end; everyone shows the same result).
##
## Network messages (Net.send_party / Net.party_message; `k` is the kind):
##   pw        {p, on, d}                  a racer's timed power-up started / ended (cosmetic mirror)
##   fx        {p, a, d}                   an item action to replay (swing, projectile, burst ...)
##   hit       {kb, st, ko, e, ed, s, add} -> victim only: apply to your own Player
##   st        {e, d}                      the victim shows a status effect (ice, bubble, stars)
##   ko        {by, v}                     a victim fell / died within 4 s of by's hit (KO +3)
##   swap      {pos}                       -> victim: teleport to pos (Swap Warp)
##   hz        {h}                         a placed hazard (puddle) was used up
##   pick      {b}                         -> host: I touched box b
##   box       {b, id, it, r}      (host)  box b was taken by id, who gets item it; back in r s
##   bonus     {id, cp}            (host)  id was first through checkpoint cp (+2)
##   round_end {r, rows, cup}      (host)  the round is over: its scoreboard and the cup totals

signal item_changed(id: String)
## Our attack connected (target id: peer id, or a dummy's negative id).
signal hit_landed(target_id: int, src: String)
## We were hit.
signal hit_taken(from_id: int, src: String)
signal round_finished
signal ko_scored(by: int, victim: int)

const SHOVE_COOLDOWN: float = 0.85
const BOX_RESPAWN: float = 4.0
const HOST_KINDS: Array[String] = ["box", "bonus", "round_end"]
## Seconds a status visual stays on a ghost if its end never arrives.
const MAX_STATUS: float = 8.0

var level: LevelBase
var rules: PartyRules
var player: Player
var sfx: PartySfx
var hud: PartyHud
var practice: bool = false
var boxes: Array[ItemBox] = []
var dummies: Array[PracticeDummy] = []
## The item in our one slot ("" = empty).
var item: String = ""
## Our active timed power-ups (at most one transformation, plus gadgets).
var actives: Array[PowerUp] = []
## peer id -> {item id -> PowerUp} cosmetic mirrors on ghosts.
var remote_powers: Dictionary = {}
## Our status effects: name -> seconds left.
var statuses: Dictionary = {}
var _status_fx: Dictionary = {}
## "id:effect" -> [Node3D, seconds left] status visuals on ghosts.
var _ghost_status: Dictionary = {}
## Projectiles / hazards in flight, by key (see PartyProjectile.key).
var projectiles: Dictionary = {}
var hazards: Dictionary = {}
## Tests (and bots) drive these instead of the device when use_device_input is false.
var use_device_input: bool = true
var cmd_attack: bool = false
var cmd_use: bool = false
var cmd_shove: bool = false
var cmd_cycle: bool = false
var shove_cd: float = 0.0
## Local monotonic seconds (KO window, cooldowns).
var clock: float = 0.0
var last_hit_by: int = 0
var last_hit_at: float = -99.0
## Live tallies this round: peer id -> KOs scored / checkpoints taken first.
var kos: Dictionary = {}
var bonus: Dictionary = {}
var first_through: Dictionary = {}
var round_over: bool = false
## The last round_end message applied (rows + cup), for the results screen and tests.
var last_rows: Array[Dictionary] = []
var results: PartyResults
var _rng := RandomNumberGenerator.new()
var _practice_next: int = 0
var _pick_wait: Dictionary = {}
var _counter: int = 0
var _attack_was: bool = false
var _use_was: bool = false
var _shove_was: bool = false
var _cycle_was: bool = false
var _attack_held: float = -1.0
var _ready_done: bool = false


func setup(p_level: LevelBase) -> void:
	level = p_level
	rules = Game.party
	practice = rules.is_practice()
	player = level.player
	name = "PartyLayer"
	_rng.seed = 7 if practice else int(Time.get_ticks_usec()) ^ (Net.my_id() * 7919)
	sfx = PartySfx.new()
	add_child(sfx)
	hud = PartyHud.new()
	hud.party = self
	add_child(hud)
	Net.party_message.connect(_on_message)
	Net.racer_checkpoint.connect(_on_racer_checkpoint)
	Net.roster_changed.connect(_on_roster_changed)
	level.player_failed.connect(_on_player_failed)
	level.player_respawned.connect(_on_player_respawned)
	if rules.is_team():
		player.visual.set_accent(PartyNames.team_color(Net.team_of(Net.my_id())))
		for id: Variant in level._ghosts:
			(level._ghosts[id] as RemoteRacer).set_team(PartyNames.team_name(Net.team_of(int(id))), PartyNames.team_color(Net.team_of(int(id))))
	_place_when_ready.call_deferred()


## Boxes and dummies need the level's colliders in the physics space: wait two ticks.
func _place_when_ready() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	place_boxes()
	if practice:
		place_dummies()
	_ready_done = true


# ---- placement -----------------------------------------------------------------------------

## Spots on the lawn around a respawn transform: rows across its local X, a few metres ahead
## (along the facing, -Z) or behind, kept only where a ray finds the same collider the
## checkpoint stands on - checkpoints are always on static safe ground, so boxes are too.
func lawn_spots(xf: Transform3D, lateral: Array, forward: Array) -> Array[Vector3]:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var base: Vector3 = xf.origin
	var q := PhysicsRayQueryParameters3D.create(base + Vector3(0, 1.0, 0), base + Vector3(0, -2.0, 0), 1)
	var lawn: Dictionary = space.intersect_ray(q)
	if lawn.is_empty():
		return []
	var ground: Object = lawn["collider"]
	var right: Vector3 = xf.basis.x.normalized()
	var fwd: Vector3 = -xf.basis.z.normalized()
	for f: Variant in forward:
		var out: Array[Vector3] = []
		for l: Variant in lateral:
			var p: Vector3 = base + fwd * float(f) + right * float(l)
			var rq := PhysicsRayQueryParameters3D.create(p + Vector3(0, 2.5, 0), p + Vector3(0, -2.5, 0), 1)
			var hit: Dictionary = space.intersect_ray(rq)
			if hit.is_empty() or hit["collider"] != ground or (hit["normal"] as Vector3).y < 0.85:
				continue
			var y: float = (hit["position"] as Vector3).y
			if absf(y - (base.y - 0.15)) > 0.9:
				continue
			out.append(Vector3(p.x, y, p.z))
		if out.size() >= mini(2, lateral.size()):
			return out
	return []


func respawn_points() -> Array[Transform3D]:
	var pts: Array[Transform3D] = [level._spawn]
	for cp: Checkpoint in level.checkpoints:
		pts.append(cp.respawn_transform())
	return pts


func place_boxes() -> void:
	for b: ItemBox in boxes:
		b.queue_free()
	boxes.clear()
	var pts: Array[Transform3D] = respawn_points()
	for i: int in pts.size():
		var spots: Array[Vector3] = lawn_spots(pts[i], [-2.7, -0.9, 0.9, 2.7], [3.2, 2.2, 1.4, -2.0])
		if spots.size() < 3:
			spots = lawn_spots(pts[i], [-1.6, 0.0, 1.6], [3.0, 2.0, 1.2, -1.8])
		for s: Vector3 in spots:
			var box := ItemBox.new()
			box.index = boxes.size()
			add_child(box)
			box.global_position = s + Vector3(0, 1.15, 0)
			boxes.append(box)


func place_dummies() -> void:
	var pts: Array[Transform3D] = respawn_points()
	var n: int = 0
	for i: int in pts.size():
		var spots: Array[Vector3] = lawn_spots(pts[i], [-2.2, 2.2], [5.0, 4.2, -2.6, -3.4])
		if spots.is_empty():
			spots = lawn_spots(pts[i], [-1.5, 1.5], [4.0, -2.0])
		for s: Vector3 in spots:
			n += 1
			var d := PracticeDummy.new()
			d.id = -n
			d.home = s
			add_child(d)
			d.global_position = s
			# face the player coming up the course
			d.rotation.y = pts[i].basis.get_euler().y
			dummies.append(d)


# ---- per tick -------------------------------------------------------------------------------

func _physics_process(dt: float) -> void:
	if player == null:
		return
	clock += dt
	shove_cd = maxf(shove_cd - dt, 0.0)
	_tick_statuses(dt)
	_apply_mods()
	_tick_ghost_status(dt)
	if round_over:
		return
	_read_input(dt)
	_check_boxes()
	if not practice and Net.is_host():
		_host_check_round_end()


func can_act() -> bool:
	return player.control_enabled and not level.finished and not round_over and player.party_stun <= 0.0 \
		and not statuses.has("freeze")


func _read_input(dt: float) -> void:
	var dev: bool = use_device_input and player.use_device_input
	var atk: bool = cmd_attack or (dev and Input.is_action_pressed("attack"))
	var use: bool = cmd_use or (dev and Input.is_action_pressed("use_item"))
	var shv: bool = cmd_shove or (dev and Input.is_action_pressed("shove"))
	var cyc: bool = cmd_cycle or (dev and Input.is_action_pressed("cycle_item"))
	var ok: bool = can_act()
	var pw: PowerUp = transformation()
	if atk and not _attack_was:
		if ok:
			_attack_held = 0.0
			if pw != null:
				pw.on_attack_press()
			else:
				do_shove()
	elif atk and _attack_held >= 0.0:
		_attack_held += dt
		if pw != null and ok:
			pw.on_attack_hold(_attack_held)
	# release (or a stun / the round end cutting a charge short: held -1 = cancelled)
	if _attack_held >= 0.0 and (not atk or not ok):
		if pw != null:
			pw.on_attack_release(_attack_held if ok else -1.0)
		_attack_held = -1.0
	if use and not _use_was and ok:
		press_use()
	if shv and not _shove_was and ok:
		do_shove()
	if cyc and not _cycle_was and ok and pw != null:
		pw.on_cycle()
	_attack_was = atk
	_use_was = use
	_shove_was = shv
	_cycle_was = cyc


func press_use() -> void:
	for pw: PowerUp in actives:
		if not pw.ended and pw.on_use():
			return
	if item != "":
		activate_item()


## The active transformation (it owns the Attack button), if any.
func transformation() -> PowerUp:
	for pw: PowerUp in actives:
		if pw.takes_attack and not pw.ended:
			return pw
	return null


func _apply_mods() -> void:
	var m := Vector3.ONE
	var air: int = 0
	for pw: PowerUp in actives:
		if not pw.ended:
			m *= pw.mods()
			air = maxi(air, pw.air_jumps())
	for e: String in statuses:
		m *= PartyStatus.mods(e)
	player.speed_mult = m.x
	player.jump_mult = m.y
	player.gravity_mult = m.z
	player.party_air_jumps = air
	if statuses.has("freeze"):
		player.velocity = Vector3.ZERO
	var shrink: bool = statuses.has("shrink")
	var s: float = player.visual.scale.x
	var want: float = 0.5 if shrink else 1.0
	if absf(s - want) > 0.001:
		player.visual.scale = Vector3.ONE * lerpf(s, want, 0.2)


# ---- items ---------------------------------------------------------------------------------

func _check_boxes() -> void:
	if item != "" or not _ready_done:
		return
	var c: Vector3 = player.global_position + Vector3(0, 0.8, 0)
	for b: ItemBox in boxes:
		if not b.touches(c):
			continue
		if practice or not Net.active:
			_take_box(b.index, Net.my_id(), _practice_item(), BOX_RESPAWN)
		elif Net.is_host():
			_host_pick(b.index, Net.my_id())
		elif clock - float(_pick_wait.get(b.index, -9.0)) > 0.6:
			_pick_wait[b.index] = clock
			Net.send_party({"k": "pick", "b": b.index}, 1)
		return


func _practice_item() -> String:
	var id: String = PartyItems.PRACTICE_ORDER[_practice_next % PartyItems.PRACTICE_ORDER.size()]
	_practice_next += 1
	return id


## Host: a racer touched a box. First come, first served: the box is taken once.
func _host_pick(b: int, id: int) -> void:
	if round_over or b < 0 or b >= boxes.size() or not boxes[b].available or not Net.roster.has(id):
		return
	var msg: Dictionary = {"k": "box", "b": b, "id": id, "it": roll_for(id), "r": BOX_RESPAWN}
	_take_box(b, id, str(msg["it"]), BOX_RESPAWN)
	Net.send_party(msg)


## Weighted roll by race position (leader: small / defensive, back of the pack: wild).
func roll_for(id: int) -> String:
	var order: Array[int] = Net.standings()
	var place: int = order.find(id) + 1
	if place <= 0:
		place = order.size()
	var frac: float = PartyItems.place_fraction(place, order.size())
	var it: String = PartyItems.roll(frac, _rng.randf())
	if it == "swap" and place <= 1:
		it = "balloon"
	return it


func _take_box(b: int, id: int, it: String, respawn: float) -> void:
	if b < 0 or b >= boxes.size():
		return
	var box: ItemBox = boxes[b]
	if box.available:
		sfx.play_at("pickup", box.global_position, 0.8)
	box.take(respawn)
	if id == Net.my_id() and item == "":
		give_item(it)


func give_item(it: String) -> void:
	item = it
	item_changed.emit(it)
	sfx.play("roll", 0.7)
	hud.item_rolled(it)


## Uses the item in the slot.
func activate_item() -> PowerUp:
	if item == "":
		return null
	var id: String = item
	item = ""
	item_changed.emit("")
	var pu: PowerUp = make_power(id, player, true, Net.my_id())
	if pu == null:
		return null
	if pu.duration > 0.0:
		for old: PowerUp in actives.duplicate():
			if not old.ended and (old.item_id == id or (pu.takes_attack and old.takes_attack)):
				old.finish()
		actives.append(pu)
		Net.send_party({"k": "pw", "p": id, "on": true, "d": pu.duration})
	player.visual.add_child(pu)
	hud.announce(PartyNames.item_name(id), PartyNames.item_color(id))
	sfx.play("powerup", 0.8, 1.2 if PartyItems.is_transformation(id) else 1.5)
	return pu


func make_power(id: String, body_node: Node3D, is_local: bool, owner: int) -> PowerUp:
	var scr: GDScript = PartyItems.script_for(id)
	if scr == null:
		return null
	var pu: PowerUp = scr.new() as PowerUp
	pu.setup(self, body_node, is_local, owner, id)
	return pu


## A local power-up ended (timer or used up).
func power_finished(pu: PowerUp) -> void:
	actives.erase(pu)
	if pu.duration > 0.0:
		Net.send_party({"k": "pw", "p": pu.item_id, "on": false})
	_apply_mods()


func end_all_powers() -> void:
	for pu: PowerUp in actives.duplicate():
		pu.finish()
	actives.clear()
	_apply_mods()


func send_fx(p: String, a: String, d: Dictionary) -> void:
	Net.send_party({"k": "fx", "p": p, "a": a, "d": d})


func new_key() -> String:
	_counter += 1
	return "%d_%d" % [Net.my_id(), _counter]


# ---- targets & hits --------------------------------------------------------------------------

## Everything our attacks can hit: rivals' ghosts (never teammates or finished racers) and
## practice dummies. {id, node, pos (feet), center, vel, grounded, dummy}
func targets() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d: PracticeDummy in dummies:
		if is_instance_valid(d) and not d.knocked_out:
			out.append({"id": d.id, "node": d, "pos": d.global_position, "center": d.center(), "vel": d.vel,
				"grounded": d.grounded, "dummy": true})
	for id: Variant in level._ghosts:
		var pid: int = int(id)
		if not Net.roster.has(pid) or float(Net.roster[pid].get("finished", -1.0)) >= 0.0:
			continue
		if rules.is_team() and Net.team_of(pid) == Net.team_of(Net.my_id()):
			continue
		var g: RemoteRacer = level._ghosts[id]
		out.append({"id": pid, "node": g, "pos": g.global_position, "center": g.global_position + Vector3(0, 0.8, 0),
			"vel": g.velocity(), "grounded": g.is_grounded(), "dummy": false})
	return out


func targets_in_sphere(center: Vector3, radius: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for t: Dictionary in targets():
		if (t["center"] as Vector3).distance_to(center) <= radius:
			out.append(t)
	return out


## Targets within `reach` of `origin` inside a cone around `dir` (cos of the half angle).
func targets_in_cone(origin: Vector3, dir: Vector3, reach: float, cos_half: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var d: Vector3 = dir.normalized()
	for t: Dictionary in targets():
		var to: Vector3 = (t["center"] as Vector3) - origin
		var dist: float = to.length()
		if dist > reach:
			continue
		if dist < 0.9 or to.normalized().dot(d) >= cos_half:
			out.append(t)
	return out


func targets_near_segment(a: Vector3, b: Vector3, radius: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for t: Dictionary in targets():
		var c: Vector3 = t["center"]
		var p: Vector3 = Geometry3D.get_closest_point_to_segment(c, a, b)
		if p.distance_to(c) <= radius:
			out.append(t)
	return out


## Nearest target in a cone (auto-aim for ranged items), or {}.
func nearest_in_cone(origin: Vector3, dir: Vector3, reach: float, cos_half: float) -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = INF
	for t: Dictionary in targets_in_cone(origin, dir, reach, cos_half):
		var dist: float = (t["center"] as Vector3).distance_to(origin)
		if dist < best_d:
			best_d = dist
			best = t
	return best


## Horizontal aim: the camera's forward (where the player is looking).
func aim_dir() -> Vector3:
	return Basis(Vector3.UP, player.camera_yaw) * Vector3(0, 0, -1)


## Melee facing: where the character faces, turned toward a rival close in front if any.
func melee_dir(reach: float = 3.0) -> Vector3:
	var f: Vector3 = Vector3(player.facing_dir.x, 0, player.facing_dir.z)
	if f.length() < 0.1:
		f = aim_dir()
	f = f.normalized()
	var t: Dictionary = nearest_in_cone(player.global_position + Vector3(0, 0.8, 0), f, reach, 0.5)
	if not t.is_empty():
		var to: Vector3 = (t["center"] as Vector3) - (player.global_position + Vector3(0, 0.8, 0))
		to.y = 0.0
		if to.length() > 0.1:
			f = to.normalized()
	return f


## Our attack connected with `t`. kb = knockback velocity. o: st (stun s), ko (bool),
## e (status effect), ed (its seconds), s (source move / item), add (impulse instead of a throw).
func hit(t: Dictionary, kb: Vector3, o: Dictionary = {}) -> void:
	var src: String = str(o.get("s", ""))
	var c: Vector3 = t["center"]
	if bool(t.get("dummy", false)):
		(t["node"] as PracticeDummy).take_hit(kb, o)
	else:
		var g: RemoteRacer = t["node"] as RemoteRacer
		if is_instance_valid(g):
			g.flinch()
		var msg: Dictionary = {"k": "hit", "kb": PowerUp.arr(kb), "st": float(o.get("st", 0.0)), "ko": bool(o.get("ko", false)),
			"e": str(o.get("e", "")), "ed": float(o.get("ed", 0.0)), "s": src, "add": bool(o.get("add", false))}
		Net.send_party(msg, int(t["id"]))
	if not bool(o.get("quiet", false)):
		PartyFx.burst(self, c, Color(1.0, 0.95, 0.7), 18, 5.0, 0.22, 0.4)
		PartyFx.sparks(self, c, Color(1.0, 0.85, 0.4), 14, 7.0, kb.normalized() if kb.length() > 0.1 else Vector3.UP, 60.0)
		sfx.play_at("hit", c, 0.9, 1.0 + randf_range(-0.1, 0.1))
	hit_landed.emit(int(t["id"]), src)


# ---- the Shove --------------------------------------------------------------------------------

## Everyone's griefing tool: a quick lunge that knocks a rival in front away - stronger from
## behind (they're running away from you) or while they're in the air.
func do_shove() -> void:
	if shove_cd > 0.0:
		return
	shove_cd = SHOVE_COOLDOWN
	var dir: Vector3 = melee_dir(3.2)
	player.facing_dir = dir
	var hv := Vector3(player.velocity.x, 0, player.velocity.z)
	if hv.dot(dir) < 7.0:
		player.add_impulse(dir * (7.0 - maxf(hv.dot(dir), 0.0)))
	var origin: Vector3 = player.global_position + Vector3(0, 0.8, 0)
	var basis := Basis.looking_at(dir, Vector3.UP)
	PartyFx.arc(self, origin + dir * 0.5, basis, 1.1, -0.9, 0.9, Color(1.0, 0.9, 0.6), 0.25, 0.18)
	PartyFx.one_shot(self, origin + dir * 0.6, {"amount": 14, "lifetime": 0.3, "size": 0.3, "color": Color(1, 1, 1, 0.8),
		"dir": dir, "spread": 25.0, "vmin": 6.0, "vmax": 10.0, "damping": 20.0})
	sfx.play("whoosh", 0.7, 1.1)
	send_fx("shove", "swing", {"o": PowerUp.arr(origin), "d": PowerUp.arr(dir)})
	for t: Dictionary in targets_in_cone(origin, dir, 2.3, 0.35):
		var k: float = 1.0
		var tv: Vector3 = t["vel"]
		var flat := Vector3(tv.x, 0, tv.z)
		if flat.length() > 1.5 and flat.normalized().dot(dir) > 0.4:
			k *= 1.4   # from behind
		if not bool(t["grounded"]):
			k *= 1.35  # in the air
		hit(t, dir * 11.5 * k + Vector3(0, 5.5 * minf(k, 1.3), 0), {"st": 0.25, "s": "shove"})


## The Shove replayed on another screen.
static func remote_fx_shove(layer_ref: PartyLayer, _from_id: int, _a: String, d: Dictionary) -> void:
	var o: Vector3 = PowerUp.v3(d.get("o", []))
	var dir: Vector3 = PowerUp.v3(d.get("d", []))
	if dir.length() < 0.1:
		return
	PartyFx.arc(layer_ref, o + dir * 0.5, Basis.looking_at(dir, Vector3.UP), 1.1, -0.9, 0.9, Color(1.0, 0.9, 0.6), 0.25, 0.18)
	layer_ref.sfx.play_at("whoosh", o, 0.7, 1.1)


# ---- being hit (victim side) ----------------------------------------------------------------

func _on_hit(from_id: int, m: Dictionary) -> void:
	if level.finished or round_over:
		return
	for pw: PowerUp in actives:
		if not pw.ended and pw.absorb_hit(from_id):
			return
	last_hit_by = from_id
	last_hit_at = clock
	var src: String = str(m.get("s", ""))
	var kb: Vector3 = PowerUp.v3(m.get("kb", []))
	if statuses.has("shrink"):
		kb *= 1.5
	hit_taken.emit(from_id, src)
	if bool(m.get("ko", false)):
		var c: Vector3 = player.global_position + Vector3(0, 0.8, 0)
		PartyFx.explosion(self, c, Color(1.0, 0.4, 0.2), Color(1.0, 0.8, 0.3), 2.0)
		sfx.play("ko", 1.0)
		PartyFx.shake(level, 0.8)
		level.fail("hazard")
		return
	if bool(m.get("add", false)):
		player.add_impulse(kb)
	elif kb.length() > 0.01:
		player.knockback(kb)
	var st: float = float(m.get("st", 0.0))
	if st > 0.0:
		player.party_stun = maxf(player.party_stun, st)
	var e: String = str(m.get("e", ""))
	if e != "":
		apply_status(e, float(m.get("ed", 1.0)))
	if kb.length() > 3.0:
		sfx.play("hit", 0.9)
		PartyFx.shake(level, clampf(kb.length() / 30.0, 0.2, 0.7))
		PartyFx.burst(self, player.global_position + Vector3(0, 0.8, 0), Color(1, 0.9, 0.6), 16, 4.0)


## Puts a status effect on our own Player and shows it everywhere.
func apply_status(e: String, dur: float) -> void:
	statuses[e] = maxf(float(statuses.get(e, 0.0)), dur)
	if e in PartyStatus.STUNNING:
		player.party_stun = maxf(player.party_stun, dur)
	if e == "float":
		player.velocity = Vector3(player.velocity.x * 0.2, 2.0, player.velocity.z * 0.2)
	if e == "freeze":
		sfx.play("freeze", 0.9)
	if not _status_fx.has(e):
		var v: Node3D = PartyStatus.make(e)
		if v != null:
			player.add_child(v)
			_status_fx[e] = v
	Net.send_party({"k": "st", "e": e, "d": dur})
	_apply_mods()


func _tick_statuses(dt: float) -> void:
	for e: String in statuses.keys():
		statuses[e] = float(statuses[e]) - dt
		if float(statuses[e]) <= 0.0:
			_clear_status(e)


func _clear_status(e: String) -> void:
	statuses.erase(e)
	if _status_fx.has(e):
		var v: Node3D = _status_fx[e]
		if is_instance_valid(v):
			if e == "freeze":
				PartyFx.burst(self, player.global_position + Vector3(0, 0.8, 0), Color(0.75, 0.95, 1.0), 30, 6.0, 0.22)
				sfx.play("clank", 0.7, 1.4)
			v.queue_free()
		_status_fx.erase(e)


func clear_statuses() -> void:
	for e: String in statuses.keys():
		_clear_status(e)
	player.party_stun = 0.0
	_apply_mods()


func _show_ghost_status(id: int, e: String, dur: float) -> void:
	if not level._ghosts.has(id):
		return
	var key: String = "%d:%s" % [id, e]
	if _ghost_status.has(key):
		_ghost_status[key][1] = minf(dur, MAX_STATUS)
		return
	var g: RemoteRacer = level._ghosts[id]
	var v: Node3D = PartyStatus.make(e)
	if v != null:
		g.add_child(v)
	if e == "shrink":
		g.visual().scale = Vector3.ONE * 0.5
	_ghost_status[key] = [v, minf(dur, MAX_STATUS), id, e]


func _tick_ghost_status(dt: float) -> void:
	for key: String in _ghost_status.keys():
		var s: Array = _ghost_status[key]
		s[1] = float(s[1]) - dt
		if float(s[1]) <= 0.0:
			if s[0] != null and is_instance_valid(s[0]):
				(s[0] as Node3D).queue_free()
			if str(s[3]) == "shrink" and level._ghosts.has(int(s[2])):
				(level._ghosts[int(s[2])] as RemoteRacer).visual().scale = Vector3.ONE
			_ghost_status.erase(key)


func _on_player_failed(_cause: String) -> void:
	var by: int = PartyRules.ko_credit(last_hit_by, last_hit_at, clock)
	last_hit_by = 0
	if by == 0 or practice:
		return
	var msg: Dictionary = {"k": "ko", "by": by, "v": Net.my_id()}
	_apply_ko(by, Net.my_id())
	Net.send_party(msg)


func _on_player_respawned() -> void:
	clear_statuses()
	player.visual.scale = Vector3.ONE


func _apply_ko(by: int, victim: int) -> void:
	kos[by] = int(kos.get(by, 0)) + 1
	ko_scored.emit(by, victim)
	hud.feed("%s KO'd %s   +%d" % [racer_name(by), racer_name(victim), PartyRules.KO_POINTS], team_color_of(by))
	if by == Net.my_id():
		hud.announce("KO!  +%d" % PartyRules.KO_POINTS, Color(1.0, 0.45, 0.3))
		sfx.play("ko", 0.9, 1.3)


func racer_name(id: int) -> String:
	if id < 0:
		return "Dummy"
	if Net.roster.has(id):
		return str(Net.roster[id]["name"])
	return str(rules.names.get(id, Settings.player_name if id == Net.my_id() else "?"))


## Colour for a racer's name: team colour in Team Party, else their racer colour.
func team_color_of(id: int) -> Color:
	if rules.is_team():
		return PartyNames.team_color(Net.team_of(id))
	if Net.roster.has(id):
		return Settings.RACER_COLORS[int(Net.roster[id]["color"]) % Settings.RACER_COLORS.size()]
	return Settings.my_color()


# ---- messages ----------------------------------------------------------------------------------

func _on_message(from_id: int, m: Dictionary) -> void:
	if not is_inside_tree():
		return
	var k: String = str(m.get("k", ""))
	if k in HOST_KINDS and from_id != 1:
		return   # only the host decides pickups, bonuses and the round end
	match k:
		"pw":
			_remote_power(from_id, str(m.get("p", "")), bool(m.get("on", false)), float(m.get("d", 10.0)))
		"fx":
			_remote_fx(from_id, str(m.get("p", "")), str(m.get("a", "")), m.get("d", {}) as Dictionary if typeof(m.get("d", {})) == TYPE_DICTIONARY else {})
		"hit":
			_on_hit(from_id, m)
		"st":
			_show_ghost_status(from_id, str(m.get("e", "")), float(m.get("d", 1.0)))
		"ko":
			if int(m.get("v", 0)) == from_id and int(m.get("by", 0)) != from_id:
				_apply_ko(int(m.get("by", 0)), from_id)
		"swap":
			_on_swap(from_id, PowerUp.v3(m.get("pos", [])))
		"hz":
			var h: Variant = hazards.get(str(m.get("h", "")), null)
			if h != null and is_instance_valid(h) and (h as Node).has_method("consume"):
				(h as Node).call("consume", false)
		"pick":
			if Net.is_host():
				_host_pick(int(m.get("b", -1)), from_id)
		"box":
			_take_box(int(m.get("b", -1)), int(m.get("id", 0)), str(m.get("it", "")), float(m.get("r", BOX_RESPAWN)))
		"bonus":
			_apply_bonus(int(m.get("id", 0)), int(m.get("cp", 0)))
		"round_end":
			apply_round_end(m)


func _remote_power(from_id: int, p: String, on: bool, dur: float) -> void:
	var per: Dictionary = remote_powers.get(from_id, {})
	remote_powers[from_id] = per
	if per.has(p) and is_instance_valid(per[p]):
		(per[p] as PowerUp).finish()
		per.erase(p)
	if not on or not level._ghosts.has(from_id):
		return
	var g: RemoteRacer = level._ghosts[from_id]
	var pu: PowerUp = make_power(p, g, false, from_id)
	if pu == null:
		return
	pu.duration = minf(dur, 30.0) + 1.0   # safety: ends itself even if "off" never arrives
	g.visual().add_child(pu)
	per[p] = pu
	sfx.play_at("powerup", g.global_position, 0.7, 1.2)


func _remote_fx(from_id: int, p: String, a: String, d: Dictionary) -> void:
	if p == "shove":
		remote_fx_shove(self, from_id, a, d)
		return
	var per: Dictionary = remote_powers.get(from_id, {})
	if per.has(p) and is_instance_valid(per[p]) and not (per[p] as PowerUp).ended:
		(per[p] as PowerUp).remote(a, d)
		return
	var scr: GDScript = PartyItems.script_for(p)
	if scr != null and scr.has_method("remote_fx"):
		scr.call("remote_fx", self, from_id, a, d)


## Swap Warp: the attacker took our place and sends us to theirs.
func _on_swap(from_id: int, pos: Vector3) -> void:
	if level.finished or round_over or pos == Vector3.ZERO:
		return
	last_hit_by = from_id
	last_hit_at = clock
	PartyFx.implode(self, player.global_position + Vector3(0, 0.8, 0), Color(0.4, 1.0, 0.85), 2.0)
	player.teleport(Transform3D(Basis(Vector3.UP, player.camera_yaw), pos + Vector3(0, 0.1, 0)))
	PartyFx.burst(self, pos + Vector3(0, 0.8, 0), Color(0.4, 1.0, 0.85), 40, 6.0)
	sfx.play("warp", 1.0)
	hud.announce("SWAPPED!", Color(0.4, 1.0, 0.85))
	hit_taken.emit(from_id, "swap")


func ghost(id: int) -> RemoteRacer:
	return level._ghosts.get(id, null) as RemoteRacer


func _on_roster_changed() -> void:
	for id: Variant in remote_powers.keys():
		if not Net.roster.has(int(id)):
			for pu: Variant in (remote_powers[id] as Dictionary).values():
				if is_instance_valid(pu):
					(pu as PowerUp).queue_free()
			remote_powers.erase(id)


# ---- scoring (host decides; everyone shows) ------------------------------------------------------

func _on_racer_checkpoint(id: int, index: int, _at: float) -> void:
	if practice or not Net.is_host() or round_over:
		return
	if index < 1 or index > level.checkpoints.size() or first_through.has(index):
		return
	var msg: Dictionary = {"k": "bonus", "id": id, "cp": index}
	_apply_bonus(id, index)
	Net.send_party(msg)


func _apply_bonus(id: int, cp: int) -> void:
	if first_through.has(cp):
		return
	first_through[cp] = id
	bonus[id] = int(bonus.get(id, 0)) + 1
	if id == Net.my_id():
		hud.feed("First through checkpoint %d   +%d" % [cp, PartyRules.BONUS_POINTS], UiKit.GOLD)
	else:
		hud.feed("%s first through checkpoint %d   +%d" % [racer_name(id), cp, PartyRules.BONUS_POINTS], team_color_of(id))


func finish_times() -> Array:
	var times: Array = []
	for id: Variant in Net.roster:
		times.append(float(Net.roster[id].get("finished", -1.0)))
	return times


func _host_check_round_end() -> void:
	if round_over or not Game.race_mode or Game.course_time < 0.0:
		return
	if PartyRules.round_over(finish_times(), Game.course_time):
		host_end_round()


## Host: score the round and tell everyone (they all show exactly these numbers).
func host_end_round() -> void:
	if round_over or not Net.is_host():
		return
	var finished: Array[int] = []
	for id: int in Net.standings():
		if float(Net.roster[id].get("finished", -1.0)) >= 0.0:
			finished.append(id)
	var rows: Array[Dictionary] = PartyRules.score_round(finished, Net.roster.keys(), kos, bonus)
	var next := PartyRules.new(rules.mode)
	next.cup = rules.cup.duplicate()
	next.names = rules.names.duplicate()
	next.teams = rules.teams.duplicate()
	for id: Variant in Net.roster:
		next.names[int(id)] = str(Net.roster[id]["name"])
		next.teams[int(id)] = Net.team_of(int(id))
	next.add_round(rows)
	var msg: Dictionary = {"k": "round_end", "r": rules.round_no, "rows": rows, "cup": next.cup_to_wire()}
	apply_round_end(msg)
	Net.send_party(msg)


func apply_round_end(m: Dictionary) -> void:
	if round_over:
		return
	round_over = true
	last_rows = PartyRules.rows_from_wire(m.get("rows", []))
	rules.cup_from_wire(m.get("cup", []))
	for id: Variant in Net.roster:
		rules.names[int(id)] = str(Net.roster[id]["name"])
		rules.teams[int(id)] = Net.team_of(int(id))
	player.control_enabled = false
	end_all_powers()
	clear_statuses()
	Sfx.play("finish", 0.0, 0.8)
	round_finished.emit()
	hud.show_round_over()
	await get_tree().create_timer(1.4, false).timeout
	if is_inside_tree():
		show_results()


func show_results() -> void:
	if results != null and is_instance_valid(results):
		results.queue_free()
	results = PartyResults.new()
	results.setup_round(self, last_rows)
	hud.add_panel(results)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Our own finish (LevelBase routes it here in party modes).
func on_local_finish(time: float) -> void:
	end_all_powers()
	clear_statuses()
	if practice:
		await get_tree().create_timer(0.8, false).timeout
		if not is_inside_tree():
			return
		results = PartyResults.new()
		results.setup_practice(self, time)
		hud.add_panel(results)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	var place: int = Net.standings().find(Net.my_id()) + 1
	hud.announce("FINISHED  %d%s" % [place, Hud._ordinal(place)], UiKit.GOLD)
