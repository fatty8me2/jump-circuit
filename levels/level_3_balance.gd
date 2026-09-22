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
	_frame(c, next_yaw)
	kit.checkpoint(c, next_yaw)
	kit.lamp(c + _b * Vector3(-2.1, 0, 2.1), 2.8, false)
	kit.glow_strip(c + _b * Vector3(0, 0.03, -1.9), Vector3(1.6, 0.06, 0.22), YELLOW, next_yaw)
	r_walk(c)
	r_checkpoint()


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
	kit.plat(L(0, 0.4, 48.3), Vector3(10, 2, 10))
	kit.finish(L(0, 0.4, 50.3), _yaw)

	_wait(_hammers_clear.bind([[h, 1.85]]))
	J(0, 0, 2.7, 0, -0.6, 7.6)
	J(0, -0.6, 19.2, 0, -0.2, 24.9)
	J(0, -0.2, 25.7, 0, -0.2, 30.7)
	J(0, -0.2, 38.4, 0, 0.4, 44.5)
	r_walk(L(0, 0.4, 50.3))
	_dress_master(L(0, 0.4, 48.3))


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
	# mast and crates stand clear of the finish arch (gate at c + (-2, 0, 0), yaw 90)
	var mast: Vector3 = c + Vector3(-3.8, 0, -3.6)
	_lattice(mast + Vector3(0, 12.0, 0), 12.0, 2.0, true)
	kit.glow_strip(mast + Vector3(0, 26.0, 0), Vector3(0.7, 26.0, 0.7), YELLOW)
	kit.ring(mast + Vector3(0, 32.0, 0), 4.5, YELLOW, Vector3(0, 0, 0), 12.0)
	kit.ring(mast + Vector3(0, 24.0, 0), 3.0, Color(0, 0, 0, 0), Vector3(0, 0, 0), 8.0)
	kit.banner(c + Vector3(3.6, 0, -4.4), 5.0, YELLOW, 90.0)
	kit.banner(c + Vector3(3.6, 0, 4.4), 5.0, YELLOW, 90.0)
	_crate_stack(c + Vector3(-2.0, 0, 4.0))
	kit.lamp(c + Vector3(-4.4, 0, 4.4), 3.4, false)


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
