extends LevelBase
## 3. BALANCE WORKS (hard mode) - a teal-and-white crane yard in the sky.
## Everything answers to your weight: narrow lively beams you must run without
## stopping, heavy seesaws used as catapults, cable-hung dishes over kill water,
## platforms that sink into red, cross-winds, hammers and a sweeper on a big
## tilting dish. Ten stages, each ending on static ground.
## Set piece: the Great Scale - boost run-up, pad slam onto a heavy crane beam,
## then a gauntlet of scale beams with kill bricks waiting under their far ends.
##
## Every stage is written in a local frame: x = right, y = up, d = metres forward
## of the stage's checkpoint. Stages only turn in 90 degree steps because tilt
## boards pivot about the world X / Z axes.

const WHITE := Color(0.92, 0.94, 0.92)
const TEAL := Color(0.20, 0.52, 0.56)
const DEEP := Color(0.16, 0.33, 0.40)
const YELLOW := Color(0.98, 0.78, 0.25)

var _o: Vector3 = Vector3.ZERO
var _yaw: float = 0.0
var _b: Basis = Basis.IDENTITY


func _configure() -> void:
	theme_id = "balance"
	music_track = "a"
	kill_y = -45.0
	route_variants = 2


func _build() -> void:
	set_spawn(Vector3(0, 0.1, 3), 0.0)
	_frame(Vector3.ZERO, 0.0)
	_stage_1_slipway()
	_stage_2_catapult()
	_stage_3_dishes()
	_stage_4_sinkers()
	_stage_5_crosswind()
	_stage_6_hammers()
	_stage_7_boost_board()
	_stage_8_sweeper_dish()
	_stage_9_pad_sprint()
	_stage_10_great_scale()
	_stage_11_container_stacks()
	_stage_12_hook_ride()
	_stage_13_scanner_yard()
	_stage_14_counterweights()
	kit.finish(L(0, 0, 3.0), _yaw)
	_build_surroundings()


# ---- local frame helpers ---------------------------------------------------------------------

func _frame(o: Vector3, yaw_deg: float) -> void:
	_o = o
	_yaw = yaw_deg
	_b = Basis(Vector3.UP, deg_to_rad(yaw_deg))


func L(x: float, y: float, d: float) -> Vector3:
	return _o + _b * Vector3(x, y, -d)


func _side() -> bool:
	return absf(absf(_yaw) - 90.0) < 1.0


## Box size given as (width across travel, height, length along travel).
func _sz(w: float, h: float, ln: float) -> Vector3:
	return Vector3(ln, h, w) if _side() else Vector3(w, h, ln)


## Tilt board. pitch = seesaw along the travel direction, roll = rolls sideways.
func _beam(x: float, y: float, d: float, w: float, ln: float, pitch: bool, roll: bool, opts: Dictionary = {}) -> TiltPlatform:
	var o: Dictionary = opts.duplicate()
	if _side():
		o["tilt_about_z"] = pitch
		o["tilt_about_x"] = roll
	else:
		o["tilt_about_x"] = pitch
		o["tilt_about_z"] = roll
	return kit.tilt(L(x, y, d), _sz(w, 0.4, ln), o)


func _dish(x: float, y: float, d: float, diameter: float = 2.4, edge: float = 18.0) -> TiltPlatform:
	return kit.tilt(L(x, y, d), Vector3(diameter, 0.35, diameter), {"tilt_about_x": true, "tilt_about_z": true, "edge_tilt_deg": edge, "max_tilt_deg": edge + 6.0, "is_round": true, "support": "cables"})


func _water(x: float, y: float, d: float, w: float, ln: float) -> void:
	kit.hazard(L(x, y, d), _sz(w, 0.5, ln))
	# sea spray drifting up off the red water
	var spray: GPUParticles3D = BalanceFx.mist(_sz(w, 1.0, ln), Color(1.0, 0.86, 0.84), clampi(int(w * ln / 40.0), 6, 20))
	spray.position = L(x, y + 0.5, d)
	add_child(spray)


func J(x1: float, y1: float, d1: float, x2: float, y2: float, d2: float, speed: float = 0.0, hold: bool = true) -> void:
	r_jump(L(x1, y1, d1), L(x2, y2, d2), hold)
	if speed > 0.0:
		route[route.size() - 1]["speed"] = speed


func _aim(x: float, y: float, d: float) -> void:
	route[route.size() - 1]["aim"] = L(x, y, d)


## Static checkpoint pad ending a stage; becomes the origin of the next stage.
func _cp(x: float, y: float, d: float, next_yaw: float, w: float = 5.0, ln: float = 5.0) -> void:
	var c: Vector3 = L(x, y, d)
	kit.plat(c, _sz(w, 1.5, ln), "main", 2.4)
	_cp_mark(c, next_yaw)


## Checkpoint on ground that already exists at `c` (a ledge top, the halfway yard).
func _cp_mark(c: Vector3, next_yaw: float) -> void:
	_frame(c, next_yaw)
	kit.checkpoint(c, next_yaw)
	kit.lamp(c + _b * Vector3(-2.1, 0, 2.1), 2.8, false)
	kit.glow_strip(c + _b * Vector3(0, 0.03, -1.9), Vector3(1.6, 0.06, 0.22), YELLOW, next_yaw)
	_cp_fx(c)
	r_walk(c)
	r_checkpoint()


## Stage-clear confetti when you arrive, yard glints hanging round the pad, and the
## prevailing cross-wind streaking over the gap ahead.
func _cp_fx(c: Vector3) -> void:
	var clear := BalanceFx.ProximityBurst.new()
	clear.radius = 2.4
	clear.position = c + Vector3(0, 0.6, 0)
	clear.add_child(BalanceFx.burst(YELLOW, 36, 7.5, 1.4, 0.0, -7.0, 0.2))
	clear.add_child(BalanceFx.burst(Color(0.35, 0.95, 0.9), 30, 6.0, 1.2, 0.0, -6.0, 0.16))
	add_child(clear)
	var glints: GPUParticles3D = BalanceFx.motes(Vector3(9, 4, 9), Color(1.0, 0.9, 0.55), 12)
	glints.position = c + Vector3(0, 2.2, 0)
	add_child(glints)
	var gust: GPUParticles3D = BalanceFx.streaks(Vector3(26, 7, 22), Vector3(1, 0, 0), Color(1, 1, 1, 0.22), 14, 11.0)
	gust.position = c + _b * Vector3(0, 2.5, -20.0)
	add_child(gust)


func _wait(test: Callable, hold: Variant = null) -> void:
	var step: Dictionary = {"kind": "b_wait", "test": test}
	if hold != null:
		step["hold"] = hold
	route.append(step)


## True when every [pendulum, seconds-until-we-pass-it] pair is clear of the beam line.
func _hammers_clear(list: Array) -> bool:
	var now: float = Game.course_time
	for pair: Array in list:
		var p: Pendulum = pair[0]
		var need: float = asin(clampf(2.1 / p.length, 0.0, 0.95))
		var tau: float = float(pair[1]) - 0.3
		while tau <= float(pair[1]) + 0.3:
			if absf(p.angle_at(now + tau)) < need:
				return false
			tau += 0.05
	return true


## Hammer swinging ACROSS the travel line at forward distance d (head skims the beam).
## `span` puts the gantry posts outside the head's reach (length * sin(swing) + head).
func _hammer(y: float, d: float, period: float, phase: float, swing: float = 45.0, length: float = 7.0, span: float = 6.6) -> Pendulum:
	var p: Pendulum = kit.pendulum(L(0, y + length + 1.3, d), length, period, phase, _yaw, swing)
	# gantry the hammer hangs from
	kit.block(L(0, y + length + 1.6, d), _sz(span * 2.0 + 0.4, 0.5, 0.5), TEAL, false)
	for sx: float in [-span, span]:
		kit.block(L(sx, y + length + 1.6 - 9.0, d), Vector3(0.3, 18.0, 0.3), DEEP, false)
	return p


# ---- 1. SLIPWAY: the two kinds of lively beam, over red water ---------------------------------

func _stage_1_slipway() -> void:
	kit.plat(L(0, 0, 0), Vector3(10, 2, 10))
	kit.arch(L(0, 0, 4.4), 5.0, 4.2, 0.0, WHITE)
	kit.banner(L(-4.4, 0, 4.4), 4.4, YELLOW)
	kit.banner(L(4.4, 0, 4.4), 4.4)
	_crate_stack(L(-3.6, 0, -2.5))
	_crate_stack(L(3.4, 0, -3.0), 1)
	kit.ball(L(2.6, 0.6, 1.0), 0.42, YELLOW)
	_water(0, -5.0, 29.0, 12.0, 48.0)

	# A: pitching seesaw, 1.2 m wide - the far end drops away as you arrive, so keep running
	_beam(0, 0, 13.1, 1.2, 9.0, true, false, {"edge_tilt_deg": 16.0, "max_tilt_deg": 20.0})
	kit.plat(L(0, -0.8, 23.3), Vector3(2.2, 1.0, 2.2), "alt", 1.6)
	# B: rolling beam, 1 m wide - one step off the centre line and it dumps you
	_beam(0, -0.8, 32.6, 1.0, 8.0, false, true, {"edge_tilt_deg": 24.0, "max_tilt_deg": 30.0})
	# C: both at once
	_beam(0, -0.6, 44.5, 1.2, 7.0, true, true, {"edge_tilt_deg": 18.0, "max_tilt_deg": 24.0})

	J(0, 0, 4.7, 0, 0, 9.6)
	J(0, 0, 17.0, 0, -0.8, 23.2)
	J(0, -0.8, 24.1, 0, -0.8, 29.5)
	J(0, -0.8, 36.2, 0, -0.6, 41.9)
	J(0, -0.6, 47.5, 0, -0.4, 53.2)
	_cp(0, -0.4, 54.9, 90.0)


# ---- 2. CATAPULT YARD: heavy seesaw as a launch ramp, then a seesaw over a kill brick --------

func _stage_2_catapult() -> void:
	_water(0, -4.5, 22.0, 12.0, 34.0)
	# heavy board: stand on the near end, let the far end swing up, then sprint up it and jump
	var heavy: TiltPlatform = _beam(0, 0, 11.7, 2.6, 12.0, true, false, {"edge_tilt_deg": 20.0, "max_tilt_deg": 22.0, "board_mass": 5000.0})
	kit.plat(L(0, 2.8, 20.75), Vector3(3.5, 1.2, 3.5), "main", 2.0)
	kit.glow_strip(L(0, 2.83, 19.3), _sz(2.4, 0.06, 0.2), YELLOW)
	kit.banner(L(1.5, 2.8, 22.2), 3.4, YELLOW, _yaw)
	# lively seesaw with a kill brick waiting under its far end
	_beam(0, 1.6, 31.0, 1.4, 10.0, true, false, {"edge_tilt_deg": 20.0, "max_tilt_deg": 24.0})
	kit.hazard(L(0, 1.6 - 0.95 - 0.5, 35.6), _sz(2.4, 1.0, 1.2))

	J(0, 0, 2.2, 0, 0, 6.9)
	_wait(func() -> bool: return absf(heavy.tilt_degrees().x) + absf(heavy.tilt_degrees().y) >= 8.5, L(0, 0, 6.9))
	route.append({"kind": "b_jump", "from": L(0, 0, 17.0), "to": L(0, 2.8, 20.4), "hold": true})
	J(0, 2.8, 22.2, 0, 1.6, 27.0)
	J(0, 1.6, 34.3, 0, 0.4, 41.4)

	# SHORTCUT: two 1 m posts straight from the ledge - skips the brick seesaw
	kit.disc(L(-2.6, 2.4, 29.2), 0.5, 0.5, "alt", 2.0)
	kit.disc(L(-2.6, 1.8, 35.9), 0.5, 0.5, "alt", 2.0)
	_cp(0, 0.4, 42.9, 0.0)


# ---- 3. DISH CHAIN: six two-axis hanging dishes over kill water -------------------------------

func _stage_3_dishes() -> void:
	_water(0, -3.5, 30.0, 14.0, 56.0)
	var spots: Array[Vector3] = [Vector3(-1.5, 0.2, 7.9), Vector3(1.5, 0.5, 14.1), Vector3(-1.5, 0.8, 20.3), Vector3(1.6, 1.1, 26.5), Vector3(-1.2, 1.4, 32.7), Vector3(1.0, 1.7, 38.9), Vector3(-1.6, 2.0, 45.1), Vector3(1.2, 2.3, 51.3)]
	var prev := Vector3(0, 0, 2.2)
	for i: int in spots.size():
		var s: Vector3 = spots[i]
		_dish(s.x, s.y, s.z, 1.9 if (i == 3 or i == 6) else 2.4, 18.0)
		J(prev.x, prev.y, prev.z, s.x, s.y, s.z)
		var nxt: Vector3 = spots[i + 1] if i + 1 < spots.size() else Vector3(0, 2.6, 57.5)
		var dir: Vector3 = Vector3(nxt.x - s.x, 0, nxt.z - s.z).normalized()
		prev = s + dir * 0.75
	J(prev.x, prev.y, prev.z, 0, 2.6, 57.8)
	_cp(0, 2.6, 59.4, -90.0)


# ---- 4. SINKERS: platforms that sink into a red tide - leave early ------------------------------

func _stage_4_sinkers() -> void:
	var sink := {"tilt_about_x": false, "tilt_about_z": false, "sink_depth": 1.5, "board_mass": 500.0, "support": "cables"}
	var spots: Array[Vector3] = [Vector3(0, 0, 8.2), Vector3(2.0, 0.3, 15.6), Vector3(-1.0, 0.6, 23.0), Vector3(1.0, 0.9, 30.2), Vector3(-1.5, 1.2, 37.2), Vector3(0.5, 1.5, 44.0)]
	var prev := Vector3(0, 0, 2.2)
	for i: int in spots.size():
		var s: Vector3 = spots[i]
		var o: Dictionary = sink.duplicate()
		var size: Vector3 = Vector3(3, 0.4, 3)
		if i == 2:
			# narrow one that also rolls
			o["tilt_about_x"] = true
			o["edge_tilt_deg"] = 12.0
			o["max_tilt_deg"] = 16.0
			size = Vector3(3, 0.4, 2.2)
		elif i >= 4:
			size = Vector3(2.4, 0.4, 2.4)
			o["board_mass"] = 350.0
		kit.tilt(L(s.x, s.y, s.z), size, o)
		# the tide: a kill slab 1 m under each landing - the pan sinks INTO it
		kit.hazard(L(s.x, s.y - 1.0 - 0.3, s.z), Vector3(4.6, 0.6, 4.6))
		var half: float = size.x * 0.5
		J(prev.x, prev.y, prev.z, s.x, s.y, s.z - half + 0.8)
		var nxt: Vector3 = spots[i + 1] if i + 1 < spots.size() else Vector3(0, 2.7, 50.0)
		var dir: Vector3 = Vector3(nxt.x - s.x, 0, nxt.z - s.z).normalized()
		prev = s + dir * (half - 0.4)
	_water(0, -2.2, 26.0, 12.0, 46.0)
	J(prev.x, prev.y, prev.z, 0.3, 2.7, 49.4)
	_cp(0, 2.7, 50.7, 0.0)


# ---- 5. CROSSWIND: static beam, ice beam, rolling beam - every gap has a side wind ---------------

func _stage_5_crosswind() -> void:
	_water(0, -4.0, 31.0, 12.0, 58.0)
	kit.plat(L(0, 0, 11.0), Vector3(0.8, 0.6, 10.0), "alt", 0.8)
	kit.wind(L(0, 2.0, 18.3), Vector3(9, 6, 4.6), _b * Vector3(16, 0, 0))
	kit.slick(L(0, 0, 25.1), Vector3(1.3, 0.5, 9.0))
	kit.wind(L(0, 2.0, 31.8), Vector3(9, 6, 4.4), _b * Vector3(-16, 0, 0))
	_beam(0, 0, 38.0, 1.2, 8.0, false, true, {"edge_tilt_deg": 20.0, "max_tilt_deg": 26.0})
	kit.wind(L(0, 2.0, 44.2), Vector3(9, 6, 4.4), _b * Vector3(16, 0, 0))
	kit.plat(L(0, 0, 50.4), Vector3(0.8, 0.6, 8.0), "alt", 0.8)
	kit.banner(L(-4.6, -0.5, 44.2), 5.0, YELLOW, -90.0)
	# wind socks
	kit.banner(L(-4.6, -0.5, 18.3), 5.0, YELLOW, -90.0)
	kit.banner(L(4.6, -0.5, 31.8), 5.0, YELLOW, 90.0)
	J(0, 0, 2.2, 0, 0, 6.9)
	J(0, 0, 15.7, 0, 0, 21.6)
	_aim(-0.7, 0, 21.6)
	J(0, 0, 29.3, 0, 0, 35.0)
	_aim(0.7, 0, 35.0)
	J(0, 0, 41.6, 0, 0, 47.4)
	_aim(-0.7, 0, 47.4)
	J(0, 0, 54.1, 0, 0.3, 59.8)
	_cp(0, 0.3, 61.3, 90.0)


# ---- 6. HAMMER ALLEY: a travelling wave of hammers over a 1.2 m beam -------------------------------

func _stage_6_hammers() -> void:
	_water(0, -4.0, 24.0, 8.0, 40.0)
	kit.plat(L(0, 0, 15.5), _sz(1.2, 0.6, 20.0), "alt", 0.8)
	# phases chosen so one committed sprint threads all three
	# (wide gantries: the posts straddle both the beam and the shortcut side deck)
	var h1: Pendulum = _hammer(0, 10.0, 2.4, 0.0, 45.0, 7.0, 10.4)
	var h2: Pendulum = _hammer(0, 13.5, 2.4, 0.338, 45.0, 7.0, 10.4)
	var h3: Pendulum = _hammer(0, 17.0, 2.4, 0.676, 45.0, 7.0, 10.4)
	var h4: Pendulum = _hammer(0, 22.0, 2.0, 0.2, 45.0, 7.0, 10.4)
	_beam(0, 0, 34.2, 1.4, 9.0, false, true, {"edge_tilt_deg": 18.0, "max_tilt_deg": 24.0})
	var h5: Pendulum = _hammer(0, 34.2, 2.4, 0.1, 45.0, 7.0, 10.4)

	J(0, 0, 2.2, 0, 0, 6.3)
	r_walk(L(0, 0, 7.0))
	_wait(_hammers_clear.bind([[h1, 0.45], [h2, 0.84], [h3, 1.23]]))
	r_walk(L(0, 0, 19.5))
	_wait(_hammers_clear.bind([[h4, 0.4]]))
	r_walk(L(0, 0, 24.3))
	_wait(_hammers_clear.bind([[h5, 1.4]]))
	J(0, 0, 25.2, 0, 0, 30.6)
	J(0, 0, 38.3, 0, 0.3, 43.8)

	# SHORTCUT (hammer ride): hop to the spur, let the big hammer hit you from behind -
	# it hurls you ~12 m down the side deck, then a 92% side jump back onto the beam end.
	kit.plat(L(8.0, 0, 3.5), _sz(3.4, 1.2, 7.0), "alt", 2.0)
	kit.pendulum(L(8.0, 8.3, 2.5), 7.0, 2.6, 0.0, _yaw + 90.0, 50.0)
	kit.block(L(8.0, 8.6, 2.5), _sz(0.5, 0.5, 8.0), TEAL, false)
	kit.glow_strip(L(8.0, 0.03, 5.6), _sz(2.4, 0.06, 0.25), YELLOW)
	kit.plat(L(8.0, -0.5, 21.5), _sz(3.2, 0.8, 19.0), "alt", 1.4)
	kit.glow_strip(L(8.0, -0.47, 21.5), _sz(0.2, 0.06, 17.0), YELLOW)
	_cp(0, 0.3, 45.6, 0.0)


# ---- 7. SLIP LAUNCH: boost -> lively board -> 10 m leap -> ice -> 9.5 m leap ------------------------

func _stage_7_boost_board() -> void:
	_water(0, -6.0, 30.0, 12.0, 50.0)
	kit.boost(L(0, 0, 6.5), Vector3(3, 0.4, 8), _yaw, 20.0)
	_beam(0, 0, 16.8, 2.2, 12.0, true, false, {"edge_tilt_deg": 16.0, "max_tilt_deg": 20.0})
	kit.slick(L(0, -1.5, 37.8), Vector3(3.5, 0.5, 10.0))
	kit.pillar(L(0, -2.0, 37.8), 0.8, 9.0)
	r_walk(L(0, 0, 12.5))
	J(0, 0, 22.0, 0, -1.5, 35.0, 16.0)
	J(0, -1.5, 42.4, 0, -1.5, 52.4, 14.5)
	_cp(0, -1.5, 55.8, -90.0, 6.0, 10.0)


# ---- 8. THE TURNTABLE: a sweeper riding a big two-axis dish ------------------------------------------

func _stage_8_sweeper_dish() -> void:
	_water(0, -4.0, 22.0, 16.0, 36.0)
	var dish: TiltPlatform = kit.tilt(L(0, 0, 11.5), Vector3(10, 0.4, 10), {"tilt_about_x": true, "tilt_about_z": true, "edge_tilt_deg": 12.0, "max_tilt_deg": 14.0, "board_mass": 400.0, "is_round": true})
	var sw := Sweeper.new()
	sw.arm_length = 4.4
	sw.bar_count = 2
	sw.period = 3.6
	sw.position = Vector3(0, 0.2, 0)
	(dish.get("_surface") as Node3D).add_child(sw)
	_dish(0, 0.3, 22.0, 2.4, 18.0)
	_dish(-2.0, 0.6, 28.0, 2.4, 18.0)

	J(1.5, 0, 2.7, 1.5, 0, 7.8)
	route.append({"kind": "b_sweep", "to": L(1.5, 0, 15.0), "sweeper": sw, "tol": 0.5})
	J(1.2, 0, 15.9, 0, 0.3, 22.0)
	J(-0.25, 0.3, 22.7, -2.0, 0.6, 28.0)
	_dish(1.5, 0.9, 34.0, 2.4, 18.0)
	J(-1.6, 0.6, 28.7, 1.5, 0.9, 34.0)
	J(1.2, 0.9, 34.7, 0, 1.2, 40.4)
	_cp(0, 1.2, 41.9, 0.0)


# ---- 9. SPRINT PAD: boost into a vertical pad, land 3 m up on a seesaw, leap off its far end -----------

func _stage_9_pad_sprint() -> void:
	_water(0, -5.0, 28.0, 12.0, 44.0)
	kit.boost(L(0, 0, 6.5), Vector3(3, 0.4, 8), _yaw, 18.0)
	kit.plat(L(0, 0, 12.0), Vector3(3, 1.0, 3), "main", 2.0)
	kit.pad(L(0, 0, 12.0), 17.0, 0.0, 0.0, 1.3)
	_beam(0, 3.0, 30.5, 2.4, 12.0, true, false, {"edge_tilt_deg": 16.0, "max_tilt_deg": 20.0})
	r_walk(L(0, 0, 9.0))
	r_pad(L(0, 0, 12.0), L(0, 3.0, 27.5))
	J(0, 3.0, 35.7, 0, 2.0, 45.0, 13.0)
	_cp(0, 2.0, 47.0, 0.0, 5.0, 7.0)


# ---- 10. THE GREAT SCALE ------------------------------------------------------------------------------

func _stage_10_great_scale() -> void:
	_water(0, -5.0, 26.0, 12.0, 36.0)
	kit.boost(L(0, 0, 7.0), Vector3(3, 0.4, 7), _yaw, 16.0)
	kit.plat(L(0, 0, 12.0), Vector3(3, 1.0, 3), "main", 2.0)
	kit.pad(L(0, 0, 12.0), 15.0, 0.0, 0.0, 1.3)
	# beam 1: the slam of your landing swings the far end up toward the gallery
	_beam(0, 2.2, 30.0, 3.2, 16.0, true, false, {"edge_tilt_deg": 14.0, "max_tilt_deg": 16.0, "board_mass": 2500.0, "support": "cables"})
	kit.hazard(L(0, 2.2 - 0.55 - 0.5, 37.3), Vector3(4.0, 1.0, 1.2))
	r_walk(L(0, 0, 9.0))
	r_pad(L(0, 0, 12.0), L(0, 2.2, 24.6))
	J(0, 2.2, 37.2, 0, 3.4, 42.0, 11.0)

	# gallery on the crane tower
	var g: Vector3 = L(0, 3.4, 44.0)
	_cp(0, 3.4, 44.0, 90.0, 6.0, 6.0)
	_build_crane_tower(g)

	# beam 2 along the jib: heavy, hammer across the middle, brick under the far end
	_water(0, -6.0, 24.0, 10.0, 40.0)
	_beam(0, -0.6, 13.5, 2.4, 14.0, true, false, {"edge_tilt_deg": 16.0, "max_tilt_deg": 18.0, "board_mass": 1500.0, "support": "cables"})
	var h: Pendulum = _hammer(-0.6, 13.5, 2.6, 0.0)
	kit.hazard(L(0, -0.6 - 0.85 - 0.5, 20.0), _sz(3.2, 1.0, 1.0))
	kit.disc(L(0, -0.2, 25.0), 1.0, 0.6, "alt", 3.0)
	# beam 3: narrow and lively
	_beam(0, -0.2, 34.3, 1.2, 9.0, false, true, {"edge_tilt_deg": 22.0, "max_tilt_deg": 28.0})
	# the old finish yard is now the halfway yard: checkpoint 10, the new half heads off toward -Z
	var yard: Vector3 = L(0, 0.4, 48.3)
	kit.plat(yard, Vector3(10, 2, 10))

	_wait(_hammers_clear.bind([[h, 1.85]]))
	J(0, 0, 2.7, 0, -0.6, 7.6)
	J(0, -0.6, 19.2, 0, -0.2, 24.9)
	J(0, -0.2, 25.7, 0, -0.2, 30.7)
	J(0, -0.2, 38.4, 0, 0.4, 44.5)
	_dress_master(yard)
	_cp_mark(yard, 0.0)


# ---- new-half helpers (all in the local frame; sizes are (across, height, along)) ------------------

## Walkable block, top centre at (x, y, d).
func P(x: float, y: float, d: float, w: float, ln: float, style: String = "main", thick: float = 1.0, keel: float = -1.0) -> StaticBody3D:
	return kit.plat(L(x, y, d), Vector3(w, thick, ln), style, keel, _yaw)


## Mantle block (gold lip), top centre at (x, y, d).
func LG(x: float, y: float, d: float, w: float, h: float, ln: float, style: String = "main") -> LedgeBlock:
	return kit.ledge(L(x, y, d), Vector3(w, h, ln), _yaw, style)


## Wall-run panel running along the travel direction, centred at (x, yc, dc).
func WR(x: float, yc: float, dc: float, ln: float, h: float, th: float = 0.5) -> WallRunPanel:
	return kit.wallrun(L(x, yc, dc), Vector3(ln, h, th), _yaw + 90.0)


func MANTLE(fx: float, fy: float, fd: float, tx: float, ty: float, td: float) -> void:
	r_mantle(L(fx, fy, fd), L(tx, ty, td))


## Crane-hook cargo (mantle onto it) riding `travel` metres forward. Top centre at (x, y, d).
func _hook_cargo(x: float, y: float, d: float, along: float, h: float, across: float, travel: float, period: float, phase: float, dwell: float, col: Color) -> BalanceHookCargo:
	var c := BalanceHookCargo.new()
	c.size = Vector3(along, h, across)
	var pts: Array[Vector3] = [Vector3.ZERO, _b * Vector3(0, 0, -travel)]
	c.points = pts
	c.period = period
	c.phase = phase
	c.dwell = dwell
	c.crate_color = col
	c.cable_height = 6.5
	c.rotation_degrees.y = _yaw + 90.0
	c.position = L(x, y - h * 0.5, d)
	add_child(c)
	return c


## Crane-hung container with wall-run sides, sliding `travel` metres forward and back.
func _run_container(x: float, yc: float, d: float, along: float, h: float, across: float, travel: float, period: float, phase: float, dwell: float) -> BalanceRunContainer:
	var c := BalanceRunContainer.new()
	c.size = Vector3(along, h, across)
	var pts: Array[Vector3] = [Vector3.ZERO, _b * Vector3(0, 0, -travel)]
	c.points = pts
	c.period = period
	c.phase = phase
	c.dwell = dwell
	c.crate_color = DEEP
	c.cable_height = 5.0
	c.rotation_degrees.y = _yaw + 90.0
	c.position = L(x, yc, d)
	add_child(c)
	return c


## Counterweight lift: cage A's top at (x, y, d), cage B `gap_d` further along.
func _counterweight(x: float, y: float, d: float, gap_d: float, car_w: float, car_ln: float, travel: float, rate: float) -> BalanceCounterweight:
	var cw := BalanceCounterweight.new()
	cw.car_size = _sz(car_w, 1.0, car_ln)
	cw.b_offset = _b * Vector3(0, 0, -gap_d)
	cw.travel = travel
	cw.rate = rate
	cw.position = L(x, y, d)
	add_child(cw)
	return cw


## Sweeping laser scanner over the floor point (x, y, d), running `sweep` metres forward and back.
func _scanner(x: float, y: float, d: float, sweep: float, width: float, period: float, phase: float) -> BalanceScanner:
	var s := BalanceScanner.new()
	s.width = width
	s.beam_height = 1.1
	var pts: Array[Vector3] = [Vector3.ZERO, _b * Vector3(0, 0, -sweep)]
	s.points = pts
	s.period = period
	s.phase = phase
	s.rotation_degrees.y = _yaw
	s.position = L(x, y, d)
	add_child(s)
	# the rails it runs on
	for sx: float in [-1.0, 1.0]:
		kit.block(L(x + sx * (width * 0.5 + 0.5), y + s.rail_height + 0.35, d + sweep * 0.5), _sz(0.25, 0.25, sweep + 3.0), TEAL, false)
	for dd: float in [d - 1.5, d + sweep + 1.5]:
		kit.block(L(x, y + s.rail_height + 0.55, dd), _sz(width + 1.6, 0.3, 0.3), WHITE, false)
		for sx2: float in [-1.0, 1.0]:
			kit.block(L(x + sx2 * (width * 0.5 + 0.8), y + s.rail_height - 6.0, dd), Vector3(0.22, 13.0, 0.22), DEEP, false)
	return s


## Scanner's distance travelled from its start point at `time`.
func _scan_d(s: BalanceScanner, time: float) -> float:
	return s.offset_at(time).length()


## A run from `d0` (standing, local d) to a takeoff at `d_take` stays behind a scanner that
## starts at `d_start`, and at takeoff it is parked at the far end (so the leap clears it).
func _chase_ok(s: BalanceScanner, d_start: float, sweep: float, d0: float, d_take: float) -> bool:
	var now: float = Game.course_time
	var t_take: float = 0.12 + (d_take - d0) / 8.3
	var tau: float = 0.0
	while tau <= t_take:
		var dp: float = d0 + 8.3 * maxf(tau - 0.12, 0.0)
		if d_start + _scan_d(s, now + tau) < dp + 1.1:
			return false
		tau += 0.04
	return _scan_d(s, now + t_take) > sweep - 0.25 and _scan_d(s, now + t_take + 0.3) > sweep - 0.4


## Every laser gate in `list` ([gate, from, to] seconds from now) stays off over its window.
func _gates_off(list: Array) -> bool:
	var now: float = Game.course_time
	for g: Array in list:
		var gate: LaserGate = g[0]
		var tau: float = float(g[1])
		while tau <= float(g[2]):
			if gate.is_on_at(now + tau):
				return false
			tau += 0.04
	return true


## Every piston in `list` ([piston, from, to]) stays retracted over its window.
func _rams_in(list: Array) -> bool:
	var now: float = Game.course_time
	for g: Array in list:
		var p: Piston = g[0]
		var tau: float = float(g[1])
		while tau <= float(g[2]):
			if p.extension_at(now + tau) > 0.03:
				return false
			tau += 0.04
	return true


## Every crusher in `list` ([crusher, from, to]) is safe to be under over its window.
func _presses_clear(list: Array) -> bool:
	var now: float = Game.course_time
	for g: Array in list:
		var c: Crusher = g[0]
		if not c.is_clear_for(now + float(g[1]), float(g[2]) - float(g[1])):
			return false
		if c.gap_at(now + float(g[1])) < 2.0:
			return false
	return true


## Container-yard scenery: a stack of non-colliding shipping containers at world `pos`.
func _containers(pos: Vector3, count: int, yaw: float) -> void:
	var cols: Array[Color] = [TEAL, WHITE, YELLOW.darkened(0.1), DEEP, Color(0.85, 0.35, 0.25)]
	for i: int in count:
		var c: Color = cols[(i * 3 + int(absf(pos.x + pos.z))) % cols.size()]
		var off := Vector3(kit.rng.randf_range(-0.3, 0.3), 0.0, kit.rng.randf_range(-0.3, 0.3))
		var body: Node3D = kit.block(pos + off + Vector3(0, 1.3 + 2.6 * i, 0), Vector3(6.0, 2.6, 2.4), c, false, yaw + kit.rng.randf_range(-4, 4))
		for k: int in 9:
			body.add_child(Look.box(Vector3(0.12, 2.3, 2.5), Look.flat(c.darkened(0.25), 0.8), Vector3(-2.6 + k * 0.65, 0, 0)))


## Welding sparks spitting off a crane or container (decor, pointed away from the route).
func _welder(pos: Vector3, dir: Vector3) -> void:
	var sp: GPUParticles3D = BalanceFx.sparks(Color(1.0, 0.85, 0.5), 22, 4.5, 0.8, dir, 25.0)
	sp.position = pos
	add_child(sp)
	var glow: GPUParticles3D = BalanceFx.motes(Vector3(0.4, 0.4, 0.4), Color(0.6, 0.85, 1.0), 6, 0.5)
	glow.position = pos
	add_child(glow)


# ---- 11. CONTAINER STACKS: the first mantles - up a container, and up again off a sinking pan -----

func _stage_11_container_stacks() -> void:
	_water(0, -5.5, 30.0, 14.0, 50.0)
	# rolling beam warm-up off the halfway yard
	_beam(0, 0, 13.0, 1.2, 8.0, false, true, {"edge_tilt_deg": 22.0, "max_tilt_deg": 28.0})
	P(0, -0.4, 22.0, 3.0, 3.0, "alt")
	# container C1: 3.4 m over the deck - too tall to jump, grab the gold lip and climb
	LG(0, 3.0, 27.0, 3.2, 4.4, 5.0)
	# sinking pan in front of container C2: the longer you stand, the taller C2 gets
	var sink := {"tilt_about_x": false, "tilt_about_z": false, "sink_depth": 1.5, "board_mass": 500.0, "support": "cables"}
	kit.tilt(L(0, 2.6, 36.0), Vector3(3, 0.4, 3), sink)
	kit.hazard(L(0, 2.6 - 1.0 - 0.3, 36.0), Vector3(4.6, 0.6, 4.6))
	LG(0, 5.4, 42.5, 3.2, 5.0, 5.0)
	# scenery: container stacks either side, a welder at work on the far one
	_containers(L(-6.5, -6.0, 27.0), 3, _yaw + 90.0)
	_containers(L(6.8, -6.0, 36.0), 4, _yaw + 90.0)
	_containers(L(-7.0, -6.0, 45.0), 2, _yaw + 90.0)
	_welder(L(5.4, 4.2, 36.0), _b * Vector3(1, 0.3, 0))
	kit.banner(L(-1.9, 3.0, 25.0), 3.6, YELLOW, _yaw)

	J(0, 0, 4.7, 0, 0, 9.6)
	J(0, 0, 16.6, 0, -0.4, 21.0)
	MANTLE(0, -0.4, 23.0, 0, 3.0, 26.2)
	J(0, 3.0, 29.2, 0, 2.6, 35.2)
	MANTLE(0, 2.6, 37.1, 0, 5.4, 41.2)
	J(0, 5.4, 44.7, 0, 5.4, 50.3)
	_cp(0, 5.4, 52.0, 90.0)


# ---- 12. HOOK RIDE: mantle onto cargo hanging from a crane trolley and ride it over the water ----

var _hook_a: BalanceHookCargo
var _hook_b: BalanceHookCargo

func _stage_12_hook_ride() -> void:
	_water(0, -6.0, 32.0, 16.0, 60.0)
	_beam(0, 0, 11.0, 1.4, 9.0, true, false, {"edge_tilt_deg": 16.0, "max_tilt_deg": 20.0})
	P(0, 0, 21.0, 4.6, 4.0, "main", 1.2)
	kit.glow_strip(L(0, 0.03, 22.8), _sz(4.2, 0.06, 0.2), YELLOW)
	# two hooks on parallel trolley lines, half a cycle apart: one is always on its way
	_hook_a = _hook_cargo(-1.35, 3.2, 25.6, 3.2, 2.6, 2.4, 18.0, 10.0, 0.0, 0.2, TEAL)
	_hook_b = _hook_cargo(1.35, 3.2, 25.6, 3.2, 2.6, 2.4, 18.0, 10.0, 0.5, 0.2, Color(0.85, 0.35, 0.25))
	# the jib the trolleys run along
	for sx: float in [-1.35, 1.35]:
		kit.block(L(sx, 3.2 + 6.5 + 0.8, 34.6), _sz(0.7, 0.6, 24.0), TEAL, false)
	kit.block(L(0, 3.2 + 7.4, 34.6), _sz(4.2, 0.4, 0.8), WHITE, false)
	for dd: float in [22.0, 47.0]:
		for sx: float in [-3.4, 3.4]:
			kit.block(L(sx, -3.0, dd), Vector3(0.5, 27.0, 0.5), WHITE, false)
		kit.block(L(0, 10.8, dd), _sz(7.4, 0.5, 0.5), TEAL, false)
	P(0, 2.0, 49.5, 5.0, 3.0, "alt")
	_beam(0, 2.0, 59.0, 1.2, 8.0, false, true, {"edge_tilt_deg": 22.0, "max_tilt_deg": 28.0})

	J(0, 0, 2.2, 0, 0, 7.1)
	J(0, 0, 15.2, 0, 0, 19.6)
	# (the bot always takes hook A; a human hops on whichever one is waiting)
	_wait(func() -> bool: return _hook_a.offset_at(Game.course_time).length() < 0.02 and _hook_a.offset_at(Game.course_time + 1.0).length() < 0.02, L(-1.2, 0, 20.4))
	MANTLE(-1.35, 0, 22.4, -1.35, 3.2, 25.1)
	r_jump_from_ride(_hook_a, L(-1.35, 1.9, 43.6), 0.04, L(-1.0, 2.0, 49.0), true, Vector3(1.0, 1.3, 0))
	J(0, 2.0, 50.7, 0, 2.0, 55.4)
	J(0, 2.0, 62.7, 0, 2.4, 67.0)
	_cp(0, 2.4, 69.0, 0.0)


# ---- 13. SCANNER YARD: fork - lasers on lively beams (left) or climb the containers (right) --------

var _scan_a: BalanceScanner

func _stage_13_scanner_yard() -> void:
	_water(0, -5.0, 24.0, 22.0, 44.0)
	# fork signs: red for the laser lane, gold for the climb
	kit.glow_strip(L(-1.6, 0.03, 2.0), _sz(0.2, 0.06, 1.6), Color(1.0, 0.3, 0.2))
	kit.glow_strip(L(1.6, 0.03, 2.0), _sz(0.2, 0.06, 1.6), YELLOW)
	kit.lamp(L(-2.3, 0, 2.3), 3.0, false, Color(1.0, 0.3, 0.2))
	kit.lamp(L(2.3, 0, 2.3), 3.0, false, YELLOW)

	# LEFT: pitching beam under a sweeping scanner, deck, rolling beam through two laser curtains
	_beam(-3.0, 0, 11.8, 1.2, 9.6, true, false, {"edge_tilt_deg": 14.0, "max_tilt_deg": 18.0})
	_scan_a = _scanner(-3.0, 0, 9.0, 6.5, 2.6, 3.2, 0.0)
	P(-3.0, 0, 21.0, 2.2, 3.0, "alt")
	_beam(-3.0, 0, 31.2, 1.2, 10.4, false, true, {"edge_tilt_deg": 18.0, "max_tilt_deg": 24.0})
	var g1: LaserGate = kit.laser(L(-3.0, 1.45, 28.8), Vector3(2.4, 2.9, 0.25), 2.4, 0.45, 0.0, _yaw)
	var g2: LaserGate = kit.laser(L(-3.0, 1.45, 33.6), Vector3(2.4, 2.9, 0.25), 2.4, 0.45, -0.23, _yaw)
	# RIGHT: two container mantles, then a lively beam 7 m up and a drop to the pad
	P(3.5, 0, 7.5, 2.4, 3.0, "alt")
	LG(3.5, 3.4, 13.5, 3.0, 5.0, 8.0)
	LG(3.5, 6.8, 23.25, 3.0, 8.0, 7.5)
	_beam(3.5, 6.8, 34.5, 1.2, 7.0, false, true, {"edge_tilt_deg": 20.0, "max_tilt_deg": 26.0})
	_containers(L(9.0, -6.0, 14.0), 3, _yaw)
	_containers(L(9.5, -6.0, 30.0), 4, _yaw + 90.0)

	if route_variant == 0:
		J(-1.5, 0, 2.2, -3.0, 0, 7.6)
		_wait(_chase_ok.bind(_scan_a, 9.0, 6.5, 7.9, 14.0), L(-3.0, 0, 7.9))
		J(-3.0, 0, 14.0, -3.0, 0, 20.0)
		_wait(_gates_off.bind([[g1, 0.75, 1.45], [g2, 1.3, 2.05]]), L(-3.0, 0, 21.6))
		J(-3.0, 0, 22.2, -3.0, 0, 27.4)
		r_walk(L(-3.0, 0, 35.6))
		J(-3.0, 0, 36.1, -3.0, 0, 41.9)
	else:
		J(1.5, 0, 2.2, 3.5, 0, 6.6)
		MANTLE(3.5, 0, 8.6, 3.5, 3.4, 11.0)
		MANTLE(3.5, 3.4, 17.2, 3.5, 6.8, 20.8)
		J(3.5, 6.8, 26.7, 3.5, 6.8, 31.4)
		J(3.5, 6.8, 37.7, 3.0, 0, 42.4)
	_cp(0, 0, 44.0, -90.0, 10.0, 5.0)


# ---- 14. COUNTERWEIGHT CLIMB: stand on one cage to raise the other, mantle across, get off fast ----

var _cw1: BalanceCounterweight
var _cw2: BalanceCounterweight

func _stage_14_counterweights() -> void:
	_water(0, -7.0, 24.0, 14.0, 40.0)
	_cw1 = _counterweight(0, 0, 7.5, 6.0, 3.0, 3.0, 1.8, 0.85)
	LG(0, 4.0, 20.0, 3.2, 6.0, 6.0)
	_cw2 = _counterweight(0, 4.0, 27.2, 5.5, 2.4, 2.4, 2.0, 1.0)
	LG(0, 8.3, 39.0, 5.0, 7.0, 5.0)
	kit.banner(L(-2.4, 8.3, 41.0), 4.0, YELLOW, _yaw)
	# steam venting off the gantry legs
	for dd: float in [7.5, 13.5, 27.2, 32.7]:
		var st: GPUParticles3D = BalanceFx.steam(Color(0.9, 1.0, 1.0), 8, 1.4, 2.2, 20.0)
		st.position = L(3.3, 2.0 + (4.0 if dd > 20.0 else 0.0), dd)
		add_child(st)

	J(0, 0, 2.2, 0, 0, 6.8)
	_wait(func() -> bool: return _cw1.balance() >= 0.97, L(0, 0, 7.9))
	MANTLE(0, -1.8, 8.7, 0, 1.8, 13.0)
	MANTLE(0, 1.8, 14.7, 0, 4.0, 17.8)
	J(0, 4.0, 22.7, 0, 4.0, 26.8)
	_wait(func() -> bool: return _cw2.balance() >= 0.85, L(0, 4.0, 27.3))
	MANTLE(0, 2.3, 28.1, 0, 5.7, 32.1)
	MANTLE(0, 5.7, 33.6, 0, 8.3, 37.2)
	_cp_mark(L(0, 8.3, 39.0), 0.0)


func _build_crane_tower(g: Vector3) -> void:
	# tower behind the gallery, jibs over beam 1 (toward +Z) and beam 2 (toward -X)
	var tower: Vector3 = g + Vector3(3.2, 0, -5.4)
	_lattice(Vector3(tower.x, g.y + 5.0, tower.z), 60.0, 2.6, true)
	kit.block(tower + Vector3(0, 7.2, 0), Vector3(5.4, 3.6, 5.4), WHITE, false)
	kit.block(tower + Vector3(0, 9.3, 0), Vector3(5.9, 0.6, 5.9), TEAL, false)
	kit.block(tower + Vector3(-1.0, 11.0, 17.0), Vector3(0.9, 0.9, 30.0), TEAL, false)
	kit.block(tower + Vector3(-20.0, 11.8, 5.4), Vector3(36.0, 0.9, 0.9), TEAL, false)
	kit.block(tower + Vector3(0, 16.0, 0), Vector3(1.4, 12.0, 1.4), TEAL, false)
	var top: Vector3 = tower + Vector3(0, 22.0, 0)
	kit.pipe(top, tower + Vector3(-1.0, 11.4, 31.0), 0.09, WHITE)
	kit.pipe(top, tower + Vector3(-37.0, 12.2, 5.4), 0.09, WHITE)
	kit.lamp(top, 1.2, false, YELLOW)
	kit.glow_strip(tower + Vector3(0, 5.8, 2.75), Vector3(4.2, 0.3, 0.12), YELLOW)


func _dress_master(c: Vector3) -> void:
	# halfway yard: the mast stands behind-left of the new half's heading (-Z), clear of the takeoff
	var mast: Vector3 = c + Vector3(-3.8, 0, 3.6)
	_lattice(mast + Vector3(0, 12.0, 0), 12.0, 2.0, true)
	kit.glow_strip(mast + Vector3(0, 26.0, 0), Vector3(0.7, 26.0, 0.7), YELLOW)
	kit.ring(mast + Vector3(0, 32.0, 0), 4.5, YELLOW, Vector3(0, 0, 0), 12.0)
	kit.ring(mast + Vector3(0, 24.0, 0), 3.0, Color(0, 0, 0, 0), Vector3(0, 0, 0), 8.0)
	kit.banner(c + Vector3(4.4, 0, -4.4), 5.0, YELLOW, 0.0)
	kit.banner(c + Vector3(-4.4, 0, -4.4), 5.0, YELLOW, 0.0)
	_crate_stack(c + Vector3(2.0, 0, 3.4))
	kit.lamp(c + Vector3(4.4, 0, 4.4), 3.4, false)
	var halo: GPUParticles3D = BalanceFx.motes(Vector3(6, 20, 6), Color(1.0, 0.85, 0.35), 40, 0.16)
	halo.position = mast + Vector3(0, 22.0, 0)
	add_child(halo)


# ---- surroundings -------------------------------------------------------------------------------------

func _build_surroundings() -> void:
	kit.cloud_field(Vector3(-15, -30, -160), Vector3(170, 8, 240), 44)
	kit.cloud_field(Vector3(-15, 62, -160), Vector3(190, 10, 260), 14)
	kit.monolith_ring(Vector3(-15, 0, -160), 200.0, 270.0, 22, 24.0)
	# yard cranes standing well off the route
	_crane(Vector3(22, 14, -30), 56.0, Vector3(-1, 0, -0.4), 12.0)
	_crane(Vector3(-24, 16, -80), 58.0, Vector3(1, 0, 0.3), 11.0)
	_crane(Vector3(-66, 16, -100), 58.0, Vector3(1, 0, -0.5), 12.0)
	_crane(Vector3(30, 18, -132), 60.0, Vector3(-1, 0, -0.3), 12.0)
	_crane(Vector3(-16, 18, -148), 60.0, Vector3(0.4, 0, -1), 10.0)
	_crane(Vector3(-74, 16, -190), 58.0, Vector3(1, 0, 0.2), 12.0)
	_crane(Vector3(-14, 20, -204), 60.0, Vector3(-1, 0, 0.3), 11.0)
	_crane(Vector3(30, 22, -268), 62.0, Vector3(-1, 0, -0.2), 12.0)
	_crane(Vector3(-36, 22, -280), 62.0, Vector3(1, 0, -0.3), 12.0)
	for spot: Vector3 in [Vector3(18, -3, -12), Vector3(-22, -2, -24), Vector3(-64, 0, -66), Vector3(-18, 1, -136), Vector3(30, 2, -160), Vector3(-70, 2, -215), Vector3(10, 4, -204), Vector3(-62, 5, -252), Vector3(26, 6, -300)]:
		kit.disc(spot, kit.rng.randf_range(2.8, 4.0), 1.0, "alt")
		_crate_stack(spot + Vector3(0.4, 0, 0.2))
		kit.lamp(spot + Vector3(-1.6, 0, 1.0), 2.6, false)


# ---- local dressing helpers -------------------------------------------------------------------------------

func _crate_stack(pos: Vector3, extra: int = 2) -> void:
	var cols: Array[Color] = [TEAL, WHITE, YELLOW.darkened(0.1), DEEP]
	kit.block(pos + Vector3(0, 0.6, 0), Vector3(1.6, 1.2, 1.2), cols[kit.rng.randi() % 4], true, kit.rng.randf_range(-12, 12))
	if extra >= 1:
		kit.block(pos + Vector3(1.5, 0.45, 0.3), Vector3(1.0, 0.9, 1.0), cols[kit.rng.randi() % 4], true, kit.rng.randf_range(-20, 20))
	if extra >= 2:
		kit.block(pos + Vector3(0.1, 1.6, 0.0), Vector3(1.1, 0.8, 1.0), cols[kit.rng.randi() % 4], true, kit.rng.randf_range(-25, 25))


## Open lattice column whose top sits at `top`.
func _lattice(top: Vector3, height: float, width: float, cap: bool) -> void:
	var h: float = width * 0.5
	for sx: int in [-1, 1]:
		for sz: int in [-1, 1]:
			kit.block(top + Vector3(sx * h, -height * 0.5, sz * h), Vector3(0.28, height, 0.28), TEAL, false)
	var seg: float = width * 1.6
	var n: int = int(height / seg)
	for i: int in n + 1:
		var y: float = top.y - i * seg
		kit.block(Vector3(top.x, y, top.z), Vector3(width + 0.3, 0.2, width + 0.3), WHITE if i % 3 == 0 else TEAL, false)
		if i < n:
			var s: float = 1.0 if i % 2 == 0 else -1.0
			kit.pipe(Vector3(top.x - h * s, y, top.z + h), Vector3(top.x + h * s, y - seg, top.z + h), 0.07, WHITE)
			kit.pipe(Vector3(top.x + h, y, top.z - h * s), Vector3(top.x + h, y - seg, top.z + h * s), 0.07, WHITE)
	if cap:
		kit.block(top + Vector3(0, 0.3, 0), Vector3(width + 0.8, 0.6, width + 0.8), WHITE, false)


## Decorative tower crane: lattice mast, cab, jib toward `jib_dir`, counterweight, stays, hook.
func _crane(top: Vector3, height: float, jib_dir: Vector3, jib_len: float) -> void:
	var d: Vector3 = jib_dir.normalized()
	_lattice(top, height, 2.0, true)
	kit.block(top + Vector3(0, 1.4, 0) + d * 0.6, Vector3(2.2, 1.6, 2.2), WHITE, false, rad_to_deg(atan2(-d.x, -d.z)))
	var jib_y := Vector3(0, 2.6, 0)
	kit.pipe(top + jib_y - d * (jib_len * 0.4), top + jib_y + d * jib_len, 0.28, TEAL)
	kit.pipe(top + jib_y + Vector3(0, 0.9, 0) - d * (jib_len * 0.3), top + jib_y + Vector3(0, 0.9, 0) + d * (jib_len * 0.8), 0.12, WHITE)
	var peak: Vector3 = top + Vector3(0, 6.5, 0)
	kit.pipe(top + jib_y, peak, 0.16, TEAL)
	kit.pipe(peak, top + jib_y + d * jib_len, 0.06, WHITE)
	kit.pipe(peak, top + jib_y - d * (jib_len * 0.4), 0.06, WHITE)
	kit.block(top + jib_y - d * (jib_len * 0.4) + Vector3(0, -0.7, 0), Vector3(1.6, 1.4, 1.6), YELLOW.darkened(0.15), false, rad_to_deg(atan2(-d.x, -d.z)))
	kit.lamp(peak, 0.8, false, YELLOW)
	var tip: Vector3 = top + jib_y + d * (jib_len * 0.8)
	kit.pipe(tip, tip + Vector3(0, -6.0, 0), 0.04, Color(0.12, 0.13, 0.16))
	kit.block(tip + Vector3(0, -6.6, 0), Vector3(1.4, 1.2, 1.4), WHITE if kit.rng.randf() < 0.5 else YELLOW.darkened(0.1), false, kit.rng.randf_range(0, 90))
