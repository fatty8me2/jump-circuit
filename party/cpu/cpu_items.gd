class_name CpuItems
extends RefCounted
## How a CPU uses the item in its slot. Simple, readable heuristics (the brief's examples):
## Thunder / Swap when behind, Balloon when a rival is on its heels, Ice / Glove / Shrink at a rival
## in front, Magnet / Gravity when rivals are close, Slick when someone trails it, the
## transformations whenever the wait is up. The item scripts under party/powerups/ drive a local
## Player, so a CPU gets this host-side counterpart: it applies the effect to the rivals itself
## (CpuField.hit_rival) and replays the item's own visuals on every screen through the same
## static `remote_fx` / power-up mirrors the human items use.

## Seconds a held item that never found a use is kept before it is thrown away.
const STALE: float = 24.0

const FORM_BOOST: Dictionary = {"fox": 1.5, "tunic": 1.2, "surge": 1.35}


static func consider(r: CpuRacer, f: CpuField, rivals: Array[Dictionary]) -> void:
	var me: Vector3 = r.walker.pos
	var fwd: Vector3 = r.walker.facing
	var my_rank: int = f.rank_of(r.id)
	var ahead: Array[Dictionary] = []
	for rv: Dictionary in rivals:
		var flat: Vector3 = RouteMath.flat((rv["pos"] as Vector3) - me)
		rv["dist"] = flat.length()
		rv["fwd"] = flat.normalized().dot(fwd) if flat.length() > 0.1 else 1.0
		if f.rank_of(int(rv["id"])) < my_rank:
			ahead.append(rv)
	var age: float = r.item_age
	var used: bool = false
	match r.item:
		"fox", "tunic", "surge":
			used = _form(r, f)
		"thunder":
			if not ahead.is_empty() and (my_rank >= 3 or ahead.size() >= 2 or age > 9.0):
				used = _thunder(r, f, ahead)
		"swap":
			if my_rank > 1:
				used = _swap(r, f, rivals, my_rank)
		"ice":
			var t: Dictionary = _nearest(rivals, 18.0, 0.7)
			if not t.is_empty():
				used = _ice(r, f, t)
		"glove":
			var t2: Dictionary = _nearest(rivals, 7.5, 0.6)
			if not t2.is_empty():
				used = _glove(r, f, t2)
		"shrink":
			var t3: Dictionary = _nearest(rivals, 14.0, 0.6)
			if not t3.is_empty():
				f.hit_rival(r, t3, Vector3.ZERO, {"e": "shrink", "ed": 6.0, "s": "shrink", "quiet": true, "add": true})
				used = true
		"magnet":
			if not _nearest(rivals, 10.0, -2.0).is_empty():
				r.magnet_left = 4.0
				f.cpu_power(r.id, "magnet", true, 4.0)
				used = true
		"slick":
			var trailing: bool = false
			for rv2: Dictionary in rivals:
				if float(rv2["dist"]) < 9.0 and float(rv2["fwd"]) < -0.1:
					trailing = true
			if trailing or age > 12.0:
				used = _slick(r, f)
		"balloon":
			var threat: bool = false
			for rv3: Dictionary in rivals:
				if float(rv3["dist"]) < 7.0 or (float(rv3["dist"]) < 13.0 and float(rv3["fwd"]) < 0.0):
					threat = true
			if threat or age > 6.0:
				r.shield_left = 15.0
				f.cpu_power(r.id, "balloon", true, 15.0)
				used = true
		"jetpack":
			if my_rank >= 2 or age > 6.0:
				r.boost_left = 3.0
				r.boost_mult = 1.7
				f.cpu_power(r.id, "jetpack", true, 4.0)
				used = true
		"tornado":
			used = _tornado(r, f, rivals)
		"gravity":
			var t4: Dictionary = _nearest(rivals, 9.0, -2.0)
			if not t4.is_empty():
				f.hit_rival(r, t4, Vector3.ZERO, {"e": "float", "ed": 2.0, "s": "gravity", "quiet": true, "add": true})
				used = true
	if used:
		r.item = ""
		r.item_age = 0.0
	elif age > STALE:
		r.item = ""   # never found a use: thrown away so the slot frees up


## Nearest rival within `reach` whose direction is at least `min_fwd` along the CPU's heading.
static func _nearest(rivals: Array[Dictionary], reach: float, min_fwd: float) -> Dictionary:
	var best: Dictionary = {}
	var bd: float = INF
	for rv: Dictionary in rivals:
		var d: float = float(rv.get("dist", INF))
		if d <= reach and float(rv.get("fwd", 1.0)) >= min_fwd and d < bd:
			bd = d
			best = rv
	return best


static func _chest(r: CpuRacer) -> Vector3:
	return r.walker.pos + Vector3(0, 0.75, 0)


static func _form(r: CpuRacer, f: CpuField) -> bool:
	if r.form != "":
		return false
	r.form = r.item
	r.form_left = 10.0
	r.boost_left = 10.0
	r.boost_mult = float(FORM_BOOST.get(r.item, 1.3))
	f.cpu_power(r.id, r.item, true, 10.0)
	return true


static func _thunder(r: CpuRacer, f: CpuField, ahead: Array[Dictionary]) -> bool:
	var pts: Array = []
	for rv: Dictionary in ahead:
		pts.append(PowerUp.arr(rv["center"] as Vector3))
		f.hit_rival(r, rv, Vector3(0, 4.0, 0), {"st": 0.8, "e": "slow", "ed": 3.0, "s": "thunder", "quiet": true, "add": true})
	f.cpu_fx(r.id, "thunder", "zap", {"o": PowerUp.arr(_chest(r)), "t": pts, "s": r.rng.randi() % 10000})
	return true


static func _swap(r: CpuRacer, f: CpuField, rivals: Array[Dictionary], my_rank: int) -> bool:
	var tg: Dictionary = {}
	var best_rank: int = -1
	for rv: Dictionary in rivals:
		var rk: int = f.rank_of(int(rv["id"]))
		if rk < my_rank and rk > best_rank:
			best_rank = rk
			tg = rv
	if tg.is_empty() or float(tg.get("dist", 999.0)) > 70.0:
		return false
	var a: Vector3 = r.walker.pos
	var b: Vector3 = tg["pos"]
	f.cpu_fx(r.id, "swap", "warp", {"a": PowerUp.arr(a), "b": PowerUp.arr(b)})
	r.walker.teleport(b)
	r.walker.relocate(b)
	r.walker.stun(0.4)
	var o: CpuRacer = tg.get("cpu") as CpuRacer
	if o != null:
		o.swapped(r.id, a, f)
	elif bool(tg.get("local", false)):
		f.layer._on_swap(r.id, a)
	else:
		Net.send_party({"k": "cswap", "by": r.id, "pos": PowerUp.arr(a)}, int(tg["id"]))
	return true


static func _ice(r: CpuRacer, f: CpuField, tg: Dictionary) -> bool:
	f.cpu_fx(r.id, "ice", "beam", {"o": PowerUp.arr(_chest(r)), "t": PowerUp.arr(tg["center"] as Vector3), "h": true})
	f.hit_rival(r, tg, Vector3.ZERO, {"e": "freeze", "ed": 2.2, "s": "ice", "quiet": true, "add": true})
	return true


static func _glove(r: CpuRacer, f: CpuField, tg: Dictionary) -> bool:
	var o: Vector3 = _chest(r)
	var dir: Vector3 = ((tg["center"] as Vector3) - o).normalized()
	var flat: Vector3 = RouteMath.flat(dir).normalized()
	f.cpu_fx(r.id, "glove", "punch", {"o": PowerUp.arr(o), "d": PowerUp.arr(dir), "r": minf(float(tg["dist"]), 7.5)})
	f.hit_rival(r, tg, flat * 24.0 + Vector3(0, 10.0, 0), {"st": 0.5, "s": "glove"})
	return true


static func _slick(r: CpuRacer, f: CpuField) -> bool:
	var back: Vector3 = -RouteMath.flat(r.walker.facing).normalized()
	var at: Vector3 = r.walker.pos + back * 1.8
	var g: Dictionary = f.layer.ground_at(at, 4.0)
	if g.is_empty():
		return false
	at = g["position"]
	f.cpu_fx(r.id, "slick", "drop", {"k": f.new_key(r.id), "pos": PowerUp.arr(at)})
	return true


## The wandering tornado entity is a human-side item; a CPU's version is a violent gust at the
## nearest rivals ahead.
static func _tornado(r: CpuRacer, f: CpuField, rivals: Array[Dictionary]) -> bool:
	var picked: int = 0
	for rv: Dictionary in rivals:
		if float(rv["dist"]) <= 35.0 and float(rv["fwd"]) > 0.2 and picked < 2:
			picked += 1
			var side: Vector3 = Vector3(r.rng.randf_range(-1, 1), 0, r.rng.randf_range(-1, 1)).normalized() * 9.0
			f.hit_rival(r, rv, side + Vector3(0, 9.0, 0), {"st": 0.7, "s": "tornado", "quiet": true})
	return picked > 0
