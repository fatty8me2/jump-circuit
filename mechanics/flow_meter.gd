class_name FlowMeter
extends Node
## The flow meter and the ZEN state of the Flow levels (docs/FLOW_BRIEF.md, workstream F3).
##
## LevelBase adds one of these only when the level's Game.LEVELS entry has "flow": true and Party Mode
## is off (FlowMeter.wanted()). It reads the player's speed and keeps `value` (0..1):
##   fills   while you hold >= 12 m/s (faster fills faster), from ring chains (chain()), rail time,
##           slope speed and clean landings (add())
##   drains  below ~7 m/s, when stopped, on a hard landing, and a lot on a respawn
## Tiers: Flow 1 / 2 / 3 at TIER_AT, and ZEN once the meter has been full for ZEN_HOLD seconds; ZEN is
## held until the meter falls under ZEN_EXIT. Each tier adds picture and sound (FlowFx, Sfx.set_zen_target,
## FlowHud). Time in ZEN is banked into the "zen_seconds" stat when the run finishes or the level is left.
##
## For other systems (speed rings, rails, slopes):
##   FlowMeter.add(amount, reason)   a lump of flow (0.05 is a small bonus, the whole meter is 1.0)
##   FlowMeter.chain(n)              the live ring-chain length (0 = broken); each new link adds a bit
## Both are static and do nothing when no meter exists, so callers need no checks (the instance
## methods behind them are add_flow() and set_chain(); LevelBase.flow is the instance). Nodes in the group
## "flow_highlight" with set_flow_highlight(amount: float) are lit softly as ZEN deepens (next ring,
## next rail, hazard tells); FlowMeter.zen_amount holds the same 0..1 value for shaders.

signal tier_changed(tier: int, up: bool)
signal zen_changed(on: bool)
signal chain_changed(count: int)

## Meter value that starts Flow 1, 2 and 3.
const TIER_AT: Array[float] = [0.15, 0.40, 0.70]
const TIER_NAMES: Array[String] = ["", "FLOW 1", "FLOW 2", "FLOW 3", "ZEN"]
const TIER_ZEN: int = 4
## Full means this (the bar holds just under 1.0 for float noise), kept for ZEN_HOLD seconds.
const ZEN_FULL: float = 0.995
const ZEN_HOLD: float = 0.8
const ZEN_EXIT: float = 0.6
const FILL_SPEED: float = 12.0
const FILL_FULL_SPEED: float = 24.0
const FILL_MIN: float = 0.06
const FILL_MAX: float = 0.16
const SLOW_SPEED: float = 7.0
const IDLE_DRAIN: float = 0.02
const SLOW_DRAIN: float = 0.12
const SLOW_DRAIN_EXTRA: float = 0.18
const STOP_SPEED: float = 1.5
const STOP_DRAIN: float = 0.35
## ZEN is held: it drains this much slower.
const ZEN_DRAIN_MULT: float = 0.6
const CHAIN_WINDOW: float = 2.0
const RESPAWN_DRAIN: float = 0.65
const HARD_LANDING: float = 16.0
const CLEAN_LANDING: float = 9.0

## Tests force the meter on for any level (Party Mode still wins).
static var force_on: bool = false
## 0..1 how deep ZEN currently is (eased); shaders and highlight hooks read it.
static var zen_amount: float = 0.0
static var current: FlowMeter = null

var level: LevelBase
var player: Player
var fx: FlowFx
var hud_widget: FlowHud

var value: float = 0.0
var zen: bool = false
var tier: int = 0
var chain_count: int = 0
var best_chain: int = 0
var peak_speed: float = 0.0
var respawns: int = 0
## Seconds spent in ZEN this run, and the whole seconds already banked into the save.
var zen_seconds: float = 0.0
var flow_acc: float = 0.0
var flow_time: float = 0.0
## What add() was called with (reason -> total), for the debug readout and tests.
var added: Dictionary = {}
var last_reason: String = ""
## Eased copies the picture and HUD use (no pops).
var shown: float = 0.0
var shown_zen: float = 0.0
## Tests drive step() by hand and switch the physics tick off.
var auto_step: bool = true

var _banked: int = 0
var _full_t: float = 0.0
var _chain_t: float = 0.0
var _banner_shown: bool = false
var _wind_player: AudioStreamPlayer
var _wind_db: float = -60.0


## Should the level get a meter? Flow levels only, never in Party Mode.
static func wanted() -> bool:
	if Game.party != null:
		return false
	if force_on:
		return true
	if Game.level_index < 0 or Game.level_index >= Game.LEVELS.size():
		return false
	return bool(Game.LEVELS[Game.level_index].get("flow", false))


## Add a lump of flow to the level's meter (no-op without one).
static func add(amount: float, reason: String = "") -> void:
	if current != null and is_instance_valid(current):
		current.add_flow(amount, reason)


## The live ring-chain length, from the speed-ring system (no-op without a meter).
static func chain(n: int) -> void:
	if current != null and is_instance_valid(current):
		current.set_chain(n)


# ---- the pure rules (static, for tests) -----------------------------------------------------------

## Meter change per second for a horizontal speed (positive fills, negative drains).
static func rate_for(speed: float) -> float:
	if speed >= FILL_SPEED:
		return lerpf(FILL_MIN, FILL_MAX, clampf((speed - FILL_SPEED) / (FILL_FULL_SPEED - FILL_SPEED), 0.0, 1.0))
	if speed >= SLOW_SPEED:
		return -IDLE_DRAIN
	var r: float = -(SLOW_DRAIN + SLOW_DRAIN_EXTRA * (1.0 - clampf(speed, 0.0, SLOW_SPEED) / SLOW_SPEED))
	if speed < STOP_SPEED:
		r -= STOP_DRAIN
	return r


## The tier a meter value reaches (no hysteresis): 0 none, 1-3 Flow, 4 ZEN.
static func tier_for(v: float, in_zen: bool) -> int:
	if in_zen:
		return TIER_ZEN
	var t: int = 0
	for i: int in TIER_AT.size():
		if v >= TIER_AT[i]:
			t = i + 1
	return t


# ---- lifecycle -------------------------------------------------------------------------------------

func setup(lvl: LevelBase) -> void:
	level = lvl
	player = lvl.player
	current = self
	add_to_group("flow_meter")
	fx = FlowFx.new()
	add_child(fx)
	fx.setup(lvl)
	hud_widget = FlowHud.new()
	lvl.hud.add_flow_widget(hud_widget)
	player.landed.connect(_on_landed)
	lvl.player_respawned.connect(on_respawn)
	if not lvl.headless_mode and Sfx.has_clip("flow_wind_loop"):
		var stream: AudioStream = Sfx._pick("flow_wind_loop")
		if stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
		_wind_player = AudioStreamPlayer.new()
		_wind_player.stream = stream
		_wind_player.bus = "SFX"
		_wind_player.volume_db = -60.0
		add_child(_wind_player)
		_wind_player.play()
	set_physics_process(auto_step)


func _exit_tree() -> void:
	bank()
	if current == self:
		current = null
	Sfx.set_zen_target(0.0)
	zen_amount = 0.0


## True while the run is live (fills and drains only then).
func running() -> bool:
	return level != null and level._started and not level.finished and Game.course_time >= 0.0


func _physics_process(dt: float) -> void:
	if player == null or not running():
		return
	step(dt, player.horizontal_speed())


# ---- the rules in motion -----------------------------------------------------------------------------

## One tick of the meter at a horizontal speed `speed` (m/s).
func step(dt: float, speed: float) -> void:
	peak_speed = maxf(peak_speed, speed)
	if _chain_t > 0.0:
		_chain_t -= dt
		if _chain_t <= 0.0 and chain_count != 0:
			set_chain(0)
	var r: float = rate_for(speed)
	if r < 0.0 and zen:
		r *= ZEN_DRAIN_MULT
	value = clampf(value + r * dt, 0.0, 1.0)
	if zen:
		zen_seconds += dt
		if value < ZEN_EXIT:
			_set_zen(false)
	else:
		if value >= ZEN_FULL:
			_full_t += dt
			if _full_t >= ZEN_HOLD:
				_set_zen(true)
		else:
			_full_t = 0.0
	flow_acc += (1.0 if zen else value) * dt
	flow_time += dt
	_update_tier()


## A lump of flow (rings, rails, slopes, landings). Negative amounts drain.
func add_flow(amount: float, reason: String = "") -> void:
	if level != null and level.finished:
		return
	value = clampf(value + amount, 0.0, 1.0)
	added[reason] = float(added.get(reason, 0.0)) + amount
	last_reason = reason
	_update_tier()


## The live ring-chain length. Each new link adds a little flow; the chain lapses after CHAIN_WINDOW
## seconds without another (or call chain(0) to break it).
func set_chain(n: int) -> void:
	n = maxi(n, 0)
	if n == chain_count:
		_chain_t = CHAIN_WINDOW if n > 0 else 0.0
		return
	var grew: bool = n > chain_count
	chain_count = n
	_chain_t = CHAIN_WINDOW if n > 0 else 0.0
	if n > 0:
		best_chain = maxi(best_chain, n)
	if grew and n >= 2:
		add_flow(minf(0.03 + 0.012 * float(n), 0.12), "chain")
	chain_changed.emit(n)


func on_respawn() -> void:
	respawns += 1
	value = maxf(value - RESPAWN_DRAIN, 0.0)
	_full_t = 0.0
	if zen:
		_set_zen(false)
	if chain_count != 0:
		set_chain(0)
	_update_tier()
	if fx != null:
		fx.reset()


func _on_landed(impact: float) -> void:
	if level == null or level.finished or not running():
		return
	var speed: float = player.horizontal_speed()
	if impact >= HARD_LANDING:
		add_flow(-minf(0.12 + 0.012 * (impact - HARD_LANDING), 0.3), "hard_landing")
	elif impact < CLEAN_LANDING and speed >= FILL_SPEED:
		add_flow(0.04, "landing")


func _update_tier() -> void:
	var want: int = tier_for(value, zen)
	if want < tier and not zen:
		# a little hysteresis going down so the bar does not flutter on a boundary
		if tier <= TIER_AT.size() and value >= TIER_AT[tier - 1] - 0.03:
			return
	if want == tier:
		return
	var up: bool = want > tier
	tier = want
	tier_changed.emit(tier, up)
	if up and not zen and not (level != null and level.headless_mode):
		Sfx.play("flow_tier_up", 0.0, 0.5, 1.0 + 0.12 * float(tier))


func _set_zen(on: bool) -> void:
	if zen == on:
		return
	zen = on
	_full_t = 0.0
	Sfx.set_zen_target(1.0 if on else 0.0)
	if on:
		Sfx.play("flow_zen_enter", 0.0, 0.8)
		if not _banner_shown and hud_widget != null:
			_banner_shown = true
			hud_widget.show_zen_banner()
	else:
		Sfx.play("flow_zen_exit", 0.0, 0.6)
	zen_changed.emit(on)
	_update_tier()


# ---- results and the stat ------------------------------------------------------------------------------

## Whole seconds of ZEN not yet saved go into the "zen_seconds" stat.
func bank() -> void:
	var n: int = int(zen_seconds) - _banked
	if n > 0:
		_banked += n
		SaveData.add_stat("zen_seconds", n)


## The level was finished: bank the ZEN time and freeze the meter for the results.
func finish() -> void:
	bank()
	if zen:
		_set_zen(false)


## What the results panel shows: Flow % (the meter averaged over the run, ZEN counting full),
## whole seconds of ZEN, the best ring chain and the top speed.
func summary() -> Dictionary:
	return {"pct": roundi(100.0 * flow_acc / maxf(flow_time, 0.001)) if flow_time > 0.0 else 0,
		"zen_secs": int(zen_seconds), "best_chain": best_chain, "top_speed": peak_speed}


## A restart from the top (LevelBase.restart_run): bank, then start the run's numbers over.
func reset() -> void:
	bank()
	value = 0.0
	shown = 0.0
	shown_zen = 0.0
	if zen:
		_set_zen(false)
	tier = 0
	chain_count = 0
	best_chain = 0
	peak_speed = 0.0
	respawns = 0
	zen_seconds = 0.0
	_banked = 0
	flow_acc = 0.0
	flow_time = 0.0
	_full_t = 0.0
	_chain_t = 0.0
	added.clear()
	if fx != null:
		fx.reset()


# ---- the picture ---------------------------------------------------------------------------------------

func _process(dt: float) -> void:
	if player == null or fx == null:
		return
	shown += (value - shown) * (1.0 - exp(-4.0 * dt))
	var zt: float = 1.0 if zen else 0.0
	shown_zen += (zt - shown_zen) * (1.0 - exp(-(1.2 if zt > shown_zen else 1.8) * dt))
	if absf(zt - shown_zen) < 0.002:
		shown_zen = zt
	fx.apply(dt, shown, shown_zen, tier, player.velocity)
	var speed: float = player.horizontal_speed()
	hud_widget.visible = level.hud._results == null
	hud_widget.show_state(shown, tier, chain_count, speed, dt)
	if _wind_player != null:
		var want: float = lerpf(-40.0, -9.0, smoothstep(9.0, 28.0, speed)) if speed > 9.0 else -60.0
		_wind_db = lerpf(_wind_db, want, 1.0 - exp(-3.0 * dt))
		_wind_player.volume_db = _wind_db
		_wind_player.pitch_scale = lerpf(0.85, 1.25, smoothstep(9.0, 30.0, speed))
