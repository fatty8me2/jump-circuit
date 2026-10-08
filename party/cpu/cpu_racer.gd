class_name CpuRacer
extends RefCounted
## One CPU racer, simulated on the host: a RouteWalker (the driving) plus everything that makes
## it a Party Mode participant - an item slot, shoves, being hit / KO'd, power-up buffs.
## It is a roster entry like any peer (id CpuField.BASE_ID + slot), so standings, bonuses,
## scoring and the results screen need no special cases. CpuField owns the network side.

const SHOVE_COOLDOWN: float = 0.85
const CLAW_COOLDOWN: float = 1.2
## Same grace as a human after a respawn: hits during it do nothing.
const PROTECT: float = PartyRules.RESPAWN_PROTECTION

var id: int = 0
var racer_name: String = "CPU"
var walker: RouteWalker
var p: Dictionary = {}
var rng := RandomNumberGenerator.new()

var item: String = ""
var item_age: float = 0.0
var _item_wait: float = 0.0
var shove_cd: float = 0.0
var claw_cd: float = 0.0
var protect_left: float = 0.0
## Balloon Shield: absorbs the next hit.
var shield_left: float = 0.0
## Transformation (fox / tunic / surge): speed buff + a stronger melee while it lasts.
var form: String = ""
var form_left: float = 0.0
var boost_left: float = 0.0
var boost_mult: float = 1.0
var slow_left: float = 0.0
var shrink_left: float = 0.0
var magnet_left: float = 0.0
var last_hit_by: int = 0
var last_hit_at: float = -99.0
var finished: bool = false
var _ai_t: float = 0.0
var swap_wait: float = -1.0
var _enc: Dictionary = {}
var _skip_box: Dictionary = {}
var _magnet_pulse: float = 0.0
## Per-game-type bookkeeping for CpuModes (hill lingering ...).
var mode_state: Dictionary = {}


func setup(p_id: int, p_name: String, level: LevelBase, diff: String, at: Vector3, p_seed: int) -> void:
	id = p_id
	racer_name = p_name
	rng.seed = p_seed
	p = CpuSkill.personal(diff, rng)
	walker = RouteWalker.new()
	walker.setup(level, p, p_seed ^ 0x5bd1e995, at)
	protect_left = 0.0


func tick(dt: float, f: CpuField) -> void:
	if finished:
		return
	shove_cd = maxf(shove_cd - dt, 0.0)
	claw_cd = maxf(claw_cd - dt, 0.0)
	protect_left = maxf(protect_left - dt, 0.0)
	slow_left = maxf(slow_left - dt, 0.0)
	shrink_left = maxf(shrink_left - dt, 0.0)
	_tick_buffs(dt, f)
	walker.pace = _pace(f) * CpuModes.pace_mult(self, f, dt)
	walker.tick(dt)
	_drain(f)
	if finished or walker.done:
		return
	if item == "":
		_try_pickup(f)
	else:
		item_age += dt
	_ai_t -= dt
	if _ai_t <= 0.0 and walker.hold <= 0.0 and walker.mode == RouteWalker.Mode.STEP:
		_ai_t = 0.12 + rng.randf() * 0.1
		_think(f)
	if magnet_left > 0.0:
		_magnet(dt, f)


func _drain(f: CpuField) -> void:
	for ev: Dictionary in walker.events:
		match str(ev["k"]):
			"cp":
				f.cpu_checkpoint(self, int(ev["i"]))
			"fail":
				f.cpu_fail(self, str(ev["cause"]))
			"respawn":
				protect_left = PROTECT
			"finish":
				finished = true
				f.cpu_finish(self)
	walker.events.clear()


## Run speed factor: item / status buffs, plus a little catch-up so a race stays a race.
func _pace(f: CpuField) -> float:
	var m: float = 1.0
	if boost_left > 0.0:
		m *= boost_mult
	if slow_left > 0.0:
		m *= 0.6
	if shrink_left > 0.0:
		m *= 0.75
	m *= f.catch_up(self)
	return m


func _tick_buffs(dt: float, f: CpuField) -> void:
	if form_left > 0.0:
		form_left -= dt
		if form_left <= 0.0:
			f.cpu_power(id, form, false)
			form = ""
	if boost_left > 0.0:
		boost_left -= dt
		if boost_left <= 0.0:
			boost_mult = 1.0
	if shield_left > 0.0:
		shield_left -= dt
		if shield_left <= 0.0:
			f.cpu_power(id, "balloon", false)


## A fall or a catch: buffs end like a human's power-ups do on a respawn.
func clear_buffs(f: CpuField) -> void:
	if form != "":
		f.cpu_power(id, form, false)
	if shield_left > 0.0:
		f.cpu_power(id, "balloon", false)
	form = ""
	form_left = 0.0
	boost_left = 0.0
	boost_mult = 1.0
	shield_left = 0.0
	slow_left = 0.0
	shrink_left = 0.0
	magnet_left = 0.0


# ---- items ------------------------------------------------------------------------------------

func give(it: String) -> void:
	item = it
	item_age = 0.0
	var span: Array = p["item_wait"]
	_item_wait = rng.randf_range(float(span[0]), float(span[1]))


func _try_pickup(f: CpuField) -> void:
	if not f.layer._ready_done:
		return
	var c: Vector3 = walker.pos + Vector3(0, 0.8, 0)
	for b: ItemBox in f.layer.boxes:
		if not b.available or c.distance_to(b.global_position) > 2.2:
			continue
		if float(_skip_box.get(b.index, -1.0)) > f.clock:
			continue
		if rng.randf() > float(p["greed"]):
			_skip_box[b.index] = f.clock + 6.0
			continue
		f.cpu_take_box(self, b)
		return


func _think(f: CpuField) -> void:
	var rivals: Array[Dictionary] = f.rivals_of(self)
	if item != "" and item_age >= _item_wait:
		CpuItems.consider(self, f, rivals)
	_melee(f, rivals)


## Shoves (and, in a transformation, the stronger melee) at a rival in reach.
func _melee(f: CpuField, rivals: Array[Dictionary]) -> void:
	var cd: float = claw_cd if form != "" else shove_cd
	if cd > 0.0 or walker.hold > 0.0:
		return
	for r: Dictionary in rivals:
		var to: Vector3 = (r["pos"] as Vector3) - walker.pos
		var flat: Vector3 = RouteMath.flat(to)
		if flat.length() > 2.5 or absf(to.y) > 1.6:
			continue
		var dir: Vector3 = flat.normalized() if flat.length() > 0.05 else walker.facing
		# only what is ahead or beside it - never someone it has already passed
		if dir.dot(walker.facing) < -0.2:
			continue
		var rid: int = int(r["id"])
		if float(_enc.get(rid, -1.0)) > f.clock and not CpuModes.eager(self, f):
			continue
		_enc[rid] = f.clock + 3.0
		var edge: bool = f.edge_near(r["pos"] as Vector3, dir)
		var chance: float = CpuModes.melee_chance(self, f, float(p["shove"]) * (1.0 if form != "" else (2.0 if edge else 0.3)), r)
		if rng.randf() < chance:
			f.cpu_shove(self, r, dir)
			return


func _magnet(dt: float, f: CpuField) -> void:
	magnet_left -= dt
	_magnet_pulse -= dt
	if _magnet_pulse > 0.0:
		return
	_magnet_pulse = 0.4
	for r: Dictionary in f.rivals_of(self):
		var to: Vector3 = walker.pos - (r["pos"] as Vector3)
		if RouteMath.flat(to).length() < 9.0 and RouteMath.flat(to).length() > 1.2:
			f.hit_rival(self, r, RouteMath.flat(to).normalized() * 7.0 + Vector3(0, 2.5, 0), {"s": "magnet", "add": true, "quiet": true})


# ---- being hit --------------------------------------------------------------------------------

## A hit message (the same shape PartyLayer.hit sends): {kb, st, ko, e, ed, s, add}.
func take_hit(by: int, m: Dictionary, f: CpuField) -> void:
	if finished or protect_left > 0.0 or walker.done:
		return
	if shield_left > 0.0:
		shield_left = 0.0
		f.cpu_power(id, "balloon", false)
		return
	last_hit_by = by
	last_hit_at = f.clock
	if bool(m.get("ko", false)):
		walker.die("ko")
		return
	var kb: Vector3 = PowerUp.v3(m.get("kb", []))
	if shrink_left > 0.0:
		kb *= 1.5
	var st: float = float(m.get("st", 0.0))
	var e: String = str(m.get("e", ""))
	var ed: float = float(m.get("ed", 1.0))
	if e == "freeze" or e == "float":
		walker.stun(ed)
		if e == "float":
			kb += Vector3(0, 2.0, 0)
	elif e in ["stun", "spin"]:
		walker.stun(ed)
	elif e == "slow":
		slow_left = maxf(slow_left, ed)
	elif e == "shrink":
		shrink_left = maxf(shrink_left, ed)
	if e != "":
		f.cpu_status(id, e, ed)
	if kb.length() > 0.5:
		walker.knock(kb)
	if st > 0.0:
		walker.stun(st)
		if e == "" and st >= 0.4:
			f.cpu_status(id, "stun", st)


## Swap Warp, victim side (the same handshake a human answers): refuse while a Balloon Shield or
## respawn protection is up, else trade places and checkpoints with the caster.
func swap_request(by: int, pos: Vector3, cp: int, f: CpuField) -> void:
	if pos == Vector3.ZERO:
		return
	if finished or walker.done or protect_left > 0.0 or shield_left > 0.0:
		f.reply(by, id, {"k": "swap_no"})
		return
	last_hit_by = by
	last_hit_at = f.clock
	var my_pos: Vector3 = walker.pos
	var my_cp: int = walker.cp
	var caster_at: float = float(Net.roster.get(by, {}).get("cp_at", 0.0))
	var my_at: float = float(Net.roster.get(id, {}).get("cp_at", 0.0))
	f.reply(by, id, {"k": "swap_ok", "pos": PowerUp.arr(my_pos), "cp": my_cp})
	var sw: Dictionary = {"k": "swapped", "a": by, "acp": my_cp, "aat": my_at, "b": id, "bcp": cp, "bat": caster_at}
	f.layer._apply_swapped(sw)
	Net.send_party(sw)
	_land_swap(pos, cp)


## Swap Warp, caster side: they accepted - go to their spot, take their checkpoint.
func swap_ok(pos: Vector3, cp: int, f: CpuField) -> void:
	if swap_wait < 0.0 or f.clock - swap_wait > 3.0:
		swap_wait = -1.0
		return
	swap_wait = -1.0
	f.cpu_fx(id, "swap", "warp", {"a": PowerUp.arr(walker.pos), "b": PowerUp.arr(pos)})
	_land_swap(pos, cp)


func swap_no() -> void:
	swap_wait = -1.0


func _land_swap(pos: Vector3, cp: int) -> void:
	walker.teleport(pos)
	walker.relocate(pos, cp)
	walker.stun(0.5)
