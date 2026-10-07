class_name PartyRoulette
extends RefCounted
## The item slot's roulette: the icon flicks through the catalogue for DURATION seconds with a
## tick on every change, slowing down, and lands exactly on the item that was rolled. Pure state
## (the HUD feeds it frame time and draws `current`), so a test can drive it by hand.

const DURATION: float = 0.8

var final_id: String = ""
var current: String = ""
var active: bool = false
var ticks: int = 0
var elapsed: float = 0.0
var _seq: Array[String] = []
var _times: Array[float] = []
var _at: int = 0


func start(final: String, rng_seed: int = 0) -> void:
	final_id = final
	active = true
	ticks = 0
	elapsed = 0.0
	_at = 0
	_seq.clear()
	_times.clear()
	var pool: Array[String] = []
	for id: String in PartyItems.ids():
		if id != final:
			pool.append(id)
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed if rng_seed != 0 else int(Time.get_ticks_usec())
	for i: int in range(pool.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: String = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	# tick times: quick at first, slowing toward the landing (the last tick IS the landing)
	var t: float = 0.0
	while t < DURATION - 0.09:
		_times.append(t)
		t += 0.04 + 0.11 * pow(t / DURATION, 2.0)
	_times.append(DURATION)
	for i: int in _times.size() - 1:
		_seq.append(pool[i % pool.size()] if not pool.is_empty() else final)
	_seq.append(final)
	current = _seq[0]


## Advances by dt. Returns {tick: the icon changed this step, landed: the roulette just stopped}.
func step(dt: float) -> Dictionary:
	var res: Dictionary = {"tick": false, "landed": false}
	if not active:
		return res
	elapsed += dt
	while _at < _times.size() and elapsed >= _times[_at]:
		current = _seq[_at]
		_at += 1
		ticks += 1
		res["tick"] = true
	if _at >= _times.size():
		active = false
		current = final_id
		res["landed"] = true
	return res
