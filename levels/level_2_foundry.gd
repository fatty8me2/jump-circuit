extends LevelBase
## 2. BOUNCE FOUNDRY (hard mode) - a brutal vertical obby wound two and a half times
## around a floating furnace tower, then over the ladle pour line to the Smelter and twice
## round it to the stack on its crown. Bounce physics and carried momentum rule:
## vertical pads KEEP the speed you bring, angled pads REPLACE it with their arc; the second
## half adds wall runs, mantles and the timed machines (lasers, pistons, crushers, a portal).
## route_variants = 2: variant 0 takes the main line at every fork, variant 1 the alternative.
##
## Stages (each ends on a checkpoint, the last on the finish):
##  1 Stamping yard      safe pad, sprint-bounce, block hops, first angled pad
##  2 West chain         four offset vertical pads, steer between molten pillars
##  3 Blast run          boost strip -> sprint-bounce over the slag pool, boost strip -> 13 m leap
##  4 Pinball shaft      four bumpers ricochet you up between kill walls
##  5 Furnace hall       conveyors dragging you at the crusher, two hammers, then a hammer
##                       you stand in front of ON PURPOSE to be hurled to the far deck
##  6 Slag steps         rising block ladder, tap-jump beam under a molten ceiling
##  7 Updraft vents      ride two vents between pads
##  8 Blink works        pad -> blink -> blink -> pad
##  9 Ice chute          slide, fly off the lip onto an angled pad that fires you back up
## 10 Crucible I         angled, angled, two offset vertical pads around the glowing core
## 11 Crucible II        angled pad to a blink landing, two sprint-bounces, two angled pads, roof
## --- second half: over the pour line to the Smelter, then twice round it to its crown ---
## 12 Gatehouse          sprint-bounce off the roof; FORK: a green wave through three lasers in the
##                       gate tunnel (0) or mantle over the gate wings (1); first wall run across a slag gap
## 13 Pour line          boost rollers under two ladle pours, leap through a third, a belt
##                       dragging you back under the fourth
## 14 The flue           three-panel wall-run zig-zag up the Smelter's face, mantle out of the last kick
## 15 Forge press        dash under a press, mantle an anvil under the next press, mantle out under a third
## 16 Ingot feed         FORK: a belt through three stamping rams (0) or stand on the launch ram's
##                       mark and ride its punch, then mantle (1); sprint pad through a molten gate
## 17 Kiln works         FORK: two blinking kiln plates (0) or a narrow plank to the kiln portal (1);
##                       a beam swept by two lasers, sprint pad up
## 18 Pour run           two wall runs under three ladle pours, kick onto a sprint pad
## 19 Quench stack       FORK: mantle the ingot stack through two laser curtains (0) or sprint over
##                       a pad into a tall panel, run it, kick and mantle the checkpoint ledge (1)
## 20 Hammer lift        ride two forge presses up as elevators - mistime a hop and you are under one
## 21 Crown pour         a narrow beam under two crown ladles, a wall run, kick and mantle onto the
##                       crown's lip under a press
## 22 Crown stack        hop the crucible sweeper, bounce into a wall-run zig-zag, mantle the stack: finish
## Set pieces: the Crucible (nine bounces); the POUR LINE - FoundryLadle drums (mechanics/foundry_ladle.gd)
## pouring molten sheets across the path on the course clock (stages 13, 18, 21).
## Shortcuts: the red sprint pad after checkpoint 1, the hammer ride from checkpoint 4, the tall anvil
## (a 4.1 m running mantle that skips press 1, stage 20), the lip panel (a wall run past the crown
## pours that kicks straight onto the last wall run, stage 21).
## Particles: visual/foundry_fx.gd - ember and ash layers, core motes, flue sparks, quench steam,
## ladle streams/splashes/drips, press-slam and ram-punch bursts, checkpoint gates, finish fireworks.

const OZ: float = -40.0          # tower axis is x = 0, z = OZ
const CORE: float = 10.0         # tower core is CORE x CORE
const DY: float = 9.4            # stages 5+ are authored 9.4 m lower and lifted as one piece
const ROOF_Y: float = 98.0 + DY
const GLOW_LO: float = 66.0 + DY # the glowing furnace core (the Crucible winds around it)
const GLOW_HI: float = 95.0 + DY

var _tuning: MovementTuning


func _configure() -> void:
	theme_id = "foundry"
	music_track = "b"
	kill_y = -45.0
	# 0 = main line at every split; 1 = the alternative at every split (see the stage notes)
	route_variants = 2


# ---- helpers ---------------------------------------------------------------------------

## Point on a circle around the tower. a = 0 south (+Z side), 90 west, 180 north, 270 east.
func _pol(a_deg: float, r: float, y: float) -> Vector3:
	var a: float = deg_to_rad(a_deg)
	return Vector3(-r * sin(a), y, OZ + r * cos(a))


func _launch_velocity(strength: float, pitch_deg: float, yaw_deg: float) -> Vector3:
	var p: float = deg_to_rad(pitch_deg)
	return Basis(Vector3.UP, deg_to_rad(yaw_deg)) * (Vector3(0, cos(p), -sin(p)) * strength)


## Angled pad at `from` whose ballistic arc comes down exactly on `to`
## (strength is solved with the same Ballistics the pad preview uses).
func _aim_pad(from: Vector3, to: Vector3, pitch_deg: float, radius: float = 1.1) -> BouncePad:
	var yaw: float = rad_to_deg(atan2(-(to.x - from.x), -(to.z - from.z)))
	var want: float = Vector2(to.x - from.x, to.z - from.z).length()
	var lo: float = 6.0
	var hi: float = 48.0
	for i: int in 40:
		var mid: float = (lo + hi) * 0.5
		var v: Vector3 = _launch_velocity(mid, pitch_deg, yaw)
		var got: float = 0.0
		if v.y * v.y / (2.0 * _tuning.gravity_rise) > (to.y - from.y) + 0.3:
			var l: Vector3 = Ballistics.landing_point(_tuning, from + Vector3(0, 0.1, 0), v, to.y)
			got = Vector2(l.x - from.x, l.z - from.z).length()
		if got < want:
			lo = mid
		else:
			hi = mid
	return kit.pad(from, snappedf(hi, 0.05), pitch_deg, yaw, radius)


## Support arm from a floating piece back to the tower so nothing reads as a loose box.
func _arm(top: Vector3, under: float = 1.4, radius: float = 0.3) -> void:
	var start: Vector3 = top - Vector3(0, under, 0)
	var end := Vector3(0, top.y - under - 3.5, OZ)
	var flat := Vector3(start.x - end.x, 0, start.z - end.z)
	end += flat.normalized() * (CORE * 0.45)
	kit.pipe(start, end, radius)
	kit.glow_strip(start.lerp(end, 0.5), Vector3(0.7, 0.7, 0.7), Look.c("decor2"))


func _pad_disc(top: Vector3, radius: float = 1.4, arm: bool = true) -> void:
	kit.disc(top, radius, 0.7, "accent", 1.3)
	if arm:
		_arm(top, 1.2)


func _blk(top: Vector3, s: float = 1.6, style: String = "alt") -> void:
	kit.plat(top, Vector3(s, 1.0, s), style, 1.3)


## Invisible catch net: same as falling out, only sooner.
func _net(center: Vector3, size: Vector3) -> void:
	var k := KillZone.new()
	k.size = size
	k.show_mesh = false
	kit._add(k, center)


func _cwait(period: float, lo: float, hi: float, offset: float = 0.0) -> void:
	route.append({"kind": "c_wait", "period": period, "lo": lo, "hi": hi, "offset": offset})


func _kick(from: Vector3, to: Vector3) -> void:
	route.append({"kind": "kick", "from": from, "to": to})


func _speed(v: float) -> void:
	route[route.size() - 1]["speed"] = v


## Chain of small blocks with a route jump between each pair. `start_from` is the takeoff on
## whatever precedes the chain. Returns the takeoff point on the last block toward `next`.
func _chain(start_from: Vector3, pts: Array[Vector3], s: float = 1.6, style: String = "alt") -> void:
	var from: Vector3 = start_from
	for i: int in pts.size():
		_blk(pts[i], s, style)
		r_jump(from, pts[i])
		if i + 1 < pts.size():
			from = _edge(pts[i], pts[i + 1], s)


## Takeoff point on a block of size s at `c`, 0.35 m inside the edge facing `toward`.
func _edge(c: Vector3, toward: Vector3, s: float = 1.6) -> Vector3:
	var d := Vector3(toward.x - c.x, 0, toward.z - c.z).normalized()
	return c + d * (s * 0.5 - 0.35)


# ---- build -----------------------------------------------------------------------------

func _build() -> void:
	_tuning = load("res://resources/default_tuning.tres") as MovementTuning
	set_spawn(Vector3(5, 0.1, 5.5), 0.0)
	_build_tower()
	_stage_1_yard()
	_stage_2_west_chain()
	_stage_3_blast_run()
	_stage_4_pinball()
	var upper := Node3D.new()
	upper.position = Vector3(0, DY, 0)
	add_child(upper)
	kit.root = upper
	var first: int = route.size()
	_stage_5_hall()
	_stage_6_slag_steps()
	_stage_7_vents()
	_stage_8_blink()
	_stage_9_chute()
	_stage_10_crucible()
	kit.root = self
	for i: int in range(first, route.size()):
		if route[i].has("from"):
			route[i]["from"] = (route[i]["from"] as Vector3) + Vector3(0, DY, 0)
		if route[i].has("to") and not route[i].has("to_node"):
			route[i]["to"] = (route[i]["to"] as Vector3) + Vector3(0, DY, 0)
	# the second half: over the pour line to the Smelter and up around it (world coordinates)
	_build_smelter()
	_stage_12_gatehouse()
	_stage_13_pour_line()
	_stage_14_flue()
	_stage_15_forge_press()
	_stage_16_ingot_feed()
	_stage_17_kiln()
	_stage_18_pour_run()
	_stage_19_quench()
	_stage_20_hammer_lift()
	_stage_21_crown()
	_stage_22_stack()
	_build_surroundings()
	_build_ambient_fx()


func _build_tower() -> void:
	var iron: Color = Look.c("decor")
	var bottom: float = -18.0
	var top: float = ROOF_Y - 2.0
	kit.block(Vector3(0, (bottom + top) * 0.5, OZ), Vector3(CORE, top - bottom, CORE), iron)
	var foot := Look.cylinder(1.2, 9.0, Look.flat(iron.darkened(0.2), 0.9), Vector3.ZERO, CORE * 0.7, 4)
	foot.rotation.y = PI / 4.0
	kit._add(foot, Vector3(0, bottom - 4.5, OZ))
	# corner stacks hugging the core (below the Crucible)
	for sx: int in [-1, 1]:
		for sz: int in [-1, 1]:
			var h: float = 74.0 if sx * sz > 0 else 66.0
			kit.chimney(Vector3(sx * (CORE * 0.5 + 0.5), bottom + 4.0, OZ + sz * (CORE * 0.5 + 0.5)), h, 1.5, false)
	# riveted bands + thin molten seams up the tower
	var y: float = bottom + 6.0
	while y < GLOW_LO - 3.0:
		kit.block(Vector3(0, y, OZ), Vector3(CORE + 0.7, 0.9, CORE + 0.7), Look.c("metal"), false)
		kit.glow_strip(Vector3(0, y + 0.75, OZ), Vector3(CORE + 0.25, 0.22, CORE + 0.25), Look.c("decor2"))
		y += 7.0
	# the furnace core: glowing slits on every face
	var mid: float = (GLOW_LO + GLOW_HI) * 0.5
	var span: float = GLOW_HI - GLOW_LO
	kit.block(Vector3(0, GLOW_LO - 1.0, OZ), Vector3(CORE + 1.4, 1.4, CORE + 1.4), Look.c("metal"), false)
	kit.block(Vector3(0, GLOW_HI + 0.4, OZ), Vector3(CORE + 1.4, 1.2, CORE + 1.4), Look.c("metal"), false)
	for i: int in 4:
		var yaw: float = 90.0 * i
		var n: Vector3 = Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3(0, 0, 1)
		var side: Vector3 = Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3(1, 0, 0)
		for k: int in [-1, 0, 1]:
			var c: Vector3 = Vector3(0, mid, OZ) + n * (CORE * 0.5 + 0.02) + side * (k * 3.0)
			kit.glow_strip(c, Vector3(1.5, span - 2.0, 0.12), Look.c("decor2"), yaw)
			kit.glow_strip(c + n * 0.05, Vector3(0.6, span - 2.0, 0.12), Look.c("accent2").lerp(Look.c("trim"), 0.85), yaw)
		for k2: int in [-1, 1]:
			kit.block(Vector3(0, mid, OZ) + n * (CORE * 0.5 + 0.25) + side * (k2 * 1.5), Vector3(0.7, span, 0.5), Look.c("metal"), false, yaw)
	for yy: float in [GLOW_LO + 5.0, mid, GLOW_HI - 5.0]:
		for off: Vector3 in [Vector3(9, 0, 9), Vector3(-9, 0, -9), Vector3(9, 0, -9), Vector3(-9, 0, 9)]:
			var o := OmniLight3D.new()
			o.light_color = Look.c("decor2")
			o.light_energy = 2.4
			o.omni_range = 17.0
			o.shadow_enabled = false
			kit._add(o, Vector3(0, yy, OZ) + off)
	# slow gears on the faces
	var h2: float = CORE * 0.5 + 0.35
	kit.gear(Vector3(0, 12.5, OZ + h2), 3.6, 14, 0.7, 26.0)
	kit.gear(Vector3(4.6, 17.2, OZ + h2 + 0.4), 2.1, 10, 0.6, -15.2)
	kit.gear(Vector3(-2.0, 30.5, OZ + h2), 2.6, 12, 0.6, 19.0)
	kit.gear(Vector3(1.0, 52.0, OZ + h2), 3.4, 14, 0.7, -23.0)
	kit.gear(Vector3(-h2, 21.0, OZ + 1.0), 3.2, 14, 0.7, -24.0, Vector3(90, 90, 0))
	kit.gear(Vector3(-h2 - 0.4, 25.6, OZ - 2.6), 1.8, 9, 0.6, 13.5, Vector3(90, 90, 0))
	kit.gear(Vector3(-h2, 50.0, OZ - 1.0), 3.0, 12, 0.7, 21.0, Vector3(90, 90, 0))
	kit.gear(Vector3(1.5, 27.0, OZ - h2), 3.0, 12, 0.7, 22.0)
	kit.gear(Vector3(-2.0, 56.0, OZ - h2), 3.3, 14, 0.7, -20.0)
	kit.gear(Vector3(h2, 33.0, OZ + 0.5), 3.4, 14, 0.7, 25.0, Vector3(90, 90, 0))
	kit.gear(Vector3(h2, 8.0, OZ - 1.5), 2.6, 12, 0.7, -18.0, Vector3(90, 90, 0))
	kit.gear(Vector3(h2, 58.0, OZ - 1.0), 2.8, 12, 0.7, 17.0, Vector3(90, 90, 0))

	# --- roof: the halfway checkpoint (the finish is on the Smelter's crown now) ---------------
	kit.plat(Vector3(0, ROOF_Y, OZ), Vector3(14, 2, 14), "goal", 0.0)
	kit.block(Vector3(0, ROOF_Y - 2.6, OZ), Vector3(12, 1.2, 12), Look.c("metal"), false)
	kit.chimney(Vector3(-5.2, ROOF_Y, OZ + 5.2), 8.0, 1.0)
	kit.chimney(Vector3(5.6, ROOF_Y, OZ + 4.6), 10.0, 1.1)
	kit.lamp(Vector3(6.2, ROOF_Y, OZ - 6.2), 3.0, false)
	for sx: int in [-1, 1]:
		kit.glow_strip(Vector3(sx * 7.05, ROOF_Y - 1.0, OZ), Vector3(0.15, 0.5, 13.0), Look.c("accent2"))
		kit.glow_strip(Vector3(0, ROOF_Y - 1.0, OZ + sx * 7.05), Vector3(13.0, 0.5, 0.15), Look.c("accent2"))


# ---- 1. stamping yard: the pieces at modest stakes --------------------------------------------

func _stage_1_yard() -> void:
	kit.plat(Vector3(0, 0, -4), Vector3(30, 2, 26))
	var p1 := Vector3(5, 0, -5)
	kit.pad(p1, 19.0, 0.0, 0.0, 1.5)
	kit.plat(Vector3(2, 3.6, -11), Vector3(16, 3.6, 6), "alt", 0.0)          # press housing
	kit.glow_strip(Vector3(2, 3.0, -7.95), Vector3(15.6, 0.25, 0.12))
	kit.gear(Vector3(-2.2, 1.9, -7.7), 1.5, 10, 0.5, 11.0)
	kit.gear(Vector3(-4.6, 1.3, -7.6), 1.05, 8, 0.5, -7.7)
	r_pad(p1, Vector3(5, 3.6, -10.8))
	# sprint-bounce: hit the pad at a run and the run carries you over the gap
	var p2 := Vector3(-4.3, 3.6, -11)
	var d1 := Vector3(-12.2, 6.4, -11)
	kit.pad(p2, 18.0, 0.0, 0.0, 1.2)
	kit.glow_strip(Vector3(1.5, 3.62, -11), Vector3(8.0, 0.05, 0.25), Look.c("accent2"))
	kit.disc(d1, 1.4, 0.7, "accent", 1.3)
	kit.pillar(d1 - Vector3(0, 0.7, 0), 0.5, 5.7)
	r_walk(Vector3(3.0, 3.6, -11))
	r_pad(p2, d1)
	# block hops out over the drop, then the first angled pad
	var b: Array[Vector3] = [Vector3(-12.6, 7.4, -16.9), Vector3(-8.0, 8.0, -20.6), Vector3(-12.8, 8.6, -24.2)]
	_chain(d1 + Vector3(0, 0, -0.95), b, 1.8)
	for i: int in b.size():
		kit.pillar(b[i] - Vector3(0, 1.0, 0), 0.35, 5.0)
	var a1 := Vector3(-13.2, 9.2, -30.0)
	var cp1 := Vector3(-12.5, 11.0, -38.5)
	_pad_disc(a1, 1.4, false)
	kit.pillar(a1 - Vector3(0, 0.7, 0), 0.4, 6.0)
	_aim_pad(a1, cp1 + Vector3(0, 0, 0.8), 25.0, 1.1)
	r_jump(_edge(b[2], a1, 1.8), a1)
	r_pad(a1, cp1 + Vector3(0, 0, 0.8))
	kit.plat(cp1, Vector3(5, 1.2, 5), "main", 2.4)
	_arm(cp1 + Vector3(2, 0, 0), 1.6, 0.5)
	kit.checkpoint(cp1, 40.0)
	kit.lamp(cp1 + Vector3(-2.1, 0, 2.1), 2.6)
	r_walk(cp1)
	r_checkpoint()

	# yard dressing
	kit.chimney(Vector3(12, 0, 5.5), 10.0, 1.3)
	kit.chimney(Vector3(12.6, 0, 1.5), 6.5, 0.9, false)
	kit.block(Vector3(11.5, 1.5, -11), Vector3(3, 3, 5), Look.c("decor"))
	kit.block(Vector3(12.2, 3.6, -11.5), Vector3(1.6, 1.2, 2.4), Look.c("metal"), false)
	kit.glow_strip(Vector3(9.95, 1.4, -11), Vector3(0.12, 1.2, 3.4), Look.c("decor2"))
	kit.block(Vector3(-11.5, 0.8, 4.5), Vector3(2.2, 1.6, 2.2), Look.c("metal"), true, 20.0)
	kit.block(Vector3(-9.2, 0.6, 5.6), Vector3(1.2, 1.2, 1.2), Look.c("alt_top"), true, -15.0)
	kit.lamp(Vector3(-3.5, 0, 7.5), 3.2)
	kit.lamp(Vector3(9.5, 0, 7.5), 3.2, false)
	kit.lamp(Vector3(9.2, 3.6, -8.8), 2.4, false)
	kit.arch(Vector3(5, 0, 0.5), 7.0, 5.0, 0.0, Look.c("metal"))
	kit.ball(Vector3(1.0, 0.6, 1.0), 0.5, Look.c("decor2"))
	kit.ball(Vector3(8.4, 0.5, -1.5), 0.4, Look.c("accent2"))
	kit.pipe(Vector3(8, 2.6, -14), Vector3(3.5, 7.0, OZ + CORE * 0.5), 0.7)
	kit.pipe(Vector3(12, -1.5, -17), Vector3(1.0, -8.0, OZ + CORE * 0.5), 0.9, Look.c("decor"))


# ---- 2. west chain: offset vertical pads, steer every bounce ----------------------------------

const CP2 := Vector3(-39.5, 21.0, -63.5)

func _stage_2_west_chain() -> void:
	var cp1 := Vector3(-12.5, 11.0, -38.5)
	var v: Array[Vector3] = [Vector3(-14.5, 11.0, -43.6), Vector3(-18.1, 13.0, -49.4), Vector3(-25.4, 15.0, -51.2), Vector3(-27.8, 17.0, -58.4), Vector3(-35.1, 19.0, -60.2)]
	for i: int in v.size():
		_pad_disc(v[i], 1.2, false)
		kit.pillar(v[i] - Vector3(0, 0.7, 0), 0.35, 6.0)
		kit.pad(v[i], 20.0, 0.0, 0.0, 0.9)
	r_jump(_edge(cp1, v[0], 5.0), v[0])
	for i: int in v.size() - 1:
		r_pad(v[i], v[i + 1])
	r_pad(v[4], CP2 + Vector3(1.2, 0, 0.8))
	# molten pillars where an unsteered bounce carries you
	for i: int in v.size() - 1:
		var dir: Vector3 = (v[i + 1] - v[i])
		dir.y = 0.0
		dir = dir.normalized()
		var p: Vector3 = v[i + 1] + dir * 3.2
		kit.hazard(Vector3(p.x, v[i + 1].y + 2.5, p.z), Vector3(1.3, 9.0, 1.3))
		kit.pillar(Vector3(p.x, v[i + 1].y - 2.0, p.z), 0.45, 5.0)
	kit.plat(CP2, Vector3(5, 1.2, 5), "main", 2.4)
	kit.checkpoint(CP2, -90.0)
	kit.lamp(CP2 + Vector3(-2.1, 0, -2.1), 2.6)
	kit.pillar(CP2 - Vector3(0, 1.2, 0), 1.0, 9.0)
	r_walk(CP2)
	r_checkpoint()
	_net(Vector3(-25, 3.0, -54.5), Vector3(36, 0.6, 28))

	# SHORTCUT: the red sprint pad. Standing on it just drops you back; hit at a full sprint
	# and steered hard it skips two pads.
	var j := Vector3(-16.8, 11.0, -42.6)
	_pad_disc(j, 1.1, false)
	kit.pad(j, 27.0, 0.0, 0.0, 0.8)


# ---- 3. blast run: boost -> leap -> ice -> sprint-bounce, boost -> leap --------------------------

func _stage_3_blast_run() -> void:
	var z: float = -63.5
	kit.boost(Vector3(-33.5, 21.0, z), Vector3(2.2, 0.4, 7.0), -90.0, 20.0)      # x -37 .. -30
	kit.pillar(Vector3(-33.5, 20.6, z), 0.6, 7.0)
	kit.slick(Vector3(-11.2, 21.0, z), Vector3(3.0, 0.5, 15.2), -90.0, 0.0)       # x -18.8 .. -3.6
	kit.pillar(Vector3(-14.0, 20.5, z), 0.6, 7.0)
	kit.pillar(Vector3(-7.0, 20.5, z), 0.6, 7.0)
	kit.hazard(Vector3(-24.5, 16.0, z), Vector3(10.0, 0.6, 6.0))
	kit.block(Vector3(-24.5, 15.2, z), Vector3(11.0, 1.2, 7.0), Look.c("decor"), false)
	var pv := Vector3(-2.3, 21.0, z)
	_pad_disc(pv, 1.5, false)
	_arm(pv, 1.2)
	kit.pad(pv, 22.0, 0.0, 0.0, 1.3)
	var deck := Vector3(19.0, 25.0, z)
	kit.plat(deck, Vector3(12, 1.2, 3.4), "main", 2.0)
	kit.pillar(deck - Vector3(0, 1.2, 0), 0.9, 8.0)
	# the slag pool under the flight and a gate the arc threads
	kit.hazard(Vector3(6.0, 16.0, z), Vector3(13.0, 0.6, 7.0))
	kit.block(Vector3(6.0, 15.2, z), Vector3(14.0, 1.2, 8.0), Look.c("decor"), false)
	for sz: int in [-1, 1]:
		kit.hazard(Vector3(7.0, 27.0, z + sz * 2.4), Vector3(1.0, 14.0, 1.0))
	kit.hazard(Vector3(7.0, 34.5, z), Vector3(1.0, 1.0, 5.8))
	r_walk(Vector3(-36.0, 21.0, z))
	r_jump(Vector3(-30.35, 21.0, z), Vector3(-11.0, 21.0, z))
	_speed(19.0)
	r_pad(pv, deck + Vector3(-1.0, 0, 0))
	# second strip: a boosted running jump between molten posts
	var s2 := Vector3(16.5, 25.0, -57.8)
	kit.boost(s2, Vector3(2.2, 0.4, 8.0), 180.0, 20.0)
	kit.pillar(s2 - Vector3(0, 0.4, 0), 0.6, 7.0)
	var cp3 := Vector3(16.5, 26.0, -40.9)
	kit.plat(cp3, Vector3(5, 1.2, 5), "main", 2.4)
	_arm(cp3 + Vector3(-2, 0, 0), 1.6, 0.5)
	for sx: int in [-1, 1]:
		kit.hazard(Vector3(16.5 + sx * 2.6, 27.5, -48.5), Vector3(1.0, 9.0, 1.0))
	r_walk(Vector3(16.5, 25.0, -61.0))
	r_jump(Vector3(16.5, 25.0, -54.2), cp3 + Vector3(0, 0, -0.8))
	_speed(19.0)
	kit.checkpoint(cp3, 180.0)
	kit.lamp(cp3 + Vector3(2.1, 0, -2.1), 2.6)
	r_walk(cp3)
	r_checkpoint()
	_net(Vector3(-8, 11.0, z), Vector3(70, 0.6, 9))
	_net(Vector3(16.5, 13.0, -50), Vector3(10, 0.6, 22))


# ---- 4. pinball: bumper slalom, then six bumpers ricochet you up between kill walls -------------

func _stage_4_pinball() -> void:
	var x: float = 16.5
	kit.plat(Vector3(x, 26.0, -32.85), Vector3(2.4, 0.6, 11.1), "alt", 0.6)    # catwalk z -38.4 .. -27.3
	var slalom: Array[Vector3] = [Vector3(x + 1.2, 26.0, -35.8), Vector3(x - 1.2, 26.0, -32.6), Vector3(x + 1.2, 26.0, -29.6)]
	for p: Vector3 in slalom:
		kit.bumper(p, 14.0, 6.0, 0.9)
	var b: Array[Vector3] = []
	for i: int in 6:
		var bz: float = -35.5 if i % 2 == 1 else (-26.0 if i == 0 else -27.0)
		var by: float = 26.0 if i == 0 else 25.6 + 4.7 * float(i)
		b.append(Vector3(x, by, bz))
		kit.bumper(b[i], 12.0, 17.0, 0.9)
		var back: float = 1.0 if i % 2 == 0 else -1.0
		kit.pipe(b[i] + Vector3(0, 0.8, back * 0.9), b[i] + Vector3(0, 0.8, back * 2.6), 0.22)
		kit.block(b[i] + Vector3(0, 0.8, back * 3.0), Vector3(5.6, 1.4, 0.7), Look.c("metal"), false)
	for sx: int in [-1, 1]:
		kit.hazard(Vector3(x + sx * 2.7, 40.0, -31.0), Vector3(0.5, 26.0, 11.0))
		for yy: float in [28.0, 36.0, 44.0, 52.0]:
			kit.pipe(Vector3(x + sx * 3.0, yy, -37.0), Vector3(x + sx * 3.0, yy, -25.0), 0.16)
	var cp4 := Vector3(x, 43.0 + DY, -22.5)
	kit.plat(cp4, Vector3(6, 1.2, 6), "main", 2.4)
	kit.pillar(cp4 - Vector3(0, 1.2, 0), 1.0, 9.0)
	kit.checkpoint(cp4 + Vector3(0.6, 0, 0.6), 90.0)
	kit.lamp(cp4 + Vector3(2.5, 0, 2.5), 2.6)
	r_walk(Vector3(x - 0.65, 26.0, -35.8))
	r_walk(Vector3(x + 0.65, 26.0, -32.6))
	r_walk(Vector3(x - 0.65, 26.0, -29.6))
	for i: int in 5:
		_kick(b[i], b[i + 1] + Vector3(0, 0.6, 0))
	_kick(b[5], cp4 + Vector3(0, 0, -0.8))
	r_walk(cp4 + Vector3(0.6, 0, 0.6))
	r_checkpoint()
	_net(Vector3(x, 20.0, -29), Vector3(9, 0.6, 22))


# ---- 5. furnace hall ---------------------------------------------------------------------------

func _stage_5_hall() -> void:
	var y: float = 43.0
	var z: float = -27.5
	# belts drag you east into the crusher
	kit.conveyor(Vector3(9.25, y, z), Vector3(2.4, 0.4, 8.5), -90.0, 5.0)     # x 5 .. 13.5
	kit.hazard(Vector3(14.4, y + 0.7, z), Vector3(1.6, 2.2, 2.8))
	kit.block(Vector3(14.4, y + 2.4, z), Vector3(2.0, 1.2, 3.2), Look.c("metal"), false)
	kit.plat(Vector3(4.1, y, z), Vector3(1.8, 1.0, 2.4), "alt", 1.3)             # island x 3.2 .. 5
	kit.conveyor(Vector3(-1.0, y, z), Vector3(2.4, 0.4, 8.4), -90.0, 5.0)      # x -5.2 .. 3.2
	kit.plat(Vector3(-9.2, y, z), Vector3(8, 1.0, 6), "main", 2.0)               # hurl deck x -13.2 .. -5.2
	for bx: float in [9.25, -1.0]:
		kit.pillar(Vector3(bx, y - 0.4, z), 0.5, 6.0)
	# two hammers across the belts
	var h1: Pendulum = kit.pendulum(Vector3(9.0, y + 7.25, z), 6.0, 3.0, 0.0, 90.0, 50.0)
	var h2: Pendulum = kit.pendulum(Vector3(-1.0, y + 7.25, z), 6.0, 3.0, 0.35, 90.0, 50.0)
	# the hurl hammer: stand on the mark and let it hit you
	var h3: Pendulum = kit.pendulum(Vector3(-11.5, y + 9.25, z), 8.0, 3.2, 0.0, 0.0, 55.0)
	for h: Pendulum in [h1, h2, h3]:
		kit.block(h.position + Vector3(0, 0.6, 0), Vector3(1.2, 0.8, 1.2), Look.c("metal"), false)
		kit.pipe(h.position + Vector3(0, 0.6, 0), Vector3(0, h.position.y - 4.0, OZ + CORE * 0.5), 0.3)
	kit.glow_strip(Vector3(-11.5, y + 0.03, z), Vector3(1.2, 0.05, 1.2), Look.c("accent2"))
	# a molten lintel: a jump arc dies on it, the flat hammer throw passes underneath
	kit.hazard(Vector3(-15.6, y + 3.55, z), Vector3(0.7, 3.6, 5.6))
	kit.block(Vector3(-15.6, y + 5.7, z), Vector3(1.1, 0.8, 6.0), Look.c("decor"), false)
	var deck := Vector3(-24.5, y - 2.5, z)
	kit.plat(deck, Vector3(10, 1.2, 4.4), "main", 2.4)
	kit.pillar(deck - Vector3(0, 1.2, 0), 1.0, 9.0)
	var cp5: Vector3 = deck + Vector3(-3.0, 0, 0)
	kit.checkpoint(cp5, 0.0)
	kit.lamp(deck + Vector3(-4.4, 0, 1.6), 2.6)

	_cwait(1.5, 0.33, 0.42, 0.0)
	r_jump(Vector3(13.85, y, -24.0), Vector3(10.8, y, z))
	r_walk(Vector3(4.1, y, z))
	_cwait(1.5, 0.68, 0.78, 0.7)
	r_walk(Vector3(-6.0, y, z))
	r_walk(Vector3(-6.6, y, z + 2.2))
	_cwait(3.2, 0.06, 0.2, 0.0)
	_kick(Vector3(-11.5, y, z), deck + Vector3(3.0, 0, 0))
	r_walk(cp5)
	r_checkpoint()
	_net(Vector3(-8.5, 35.0, -25), Vector3(43, 0.6, 16))

	# SHORTCUT: the hammer ride. A fourth hammer beside the checkpoint hurls you over both belts.
	var mark := Vector3(11.9, y, -20.3)
	_blk(mark, 1.2)
	var h4: Pendulum = kit.pendulum(mark + Vector3(0, 9.25, 0), 8.0, 3.2, 0.5, 0.0, 55.0)
	kit.block(h4.position + Vector3(0, 0.6, 0), Vector3(1.2, 0.8, 1.2), Look.c("metal"), false)
	kit.glow_strip(mark + Vector3(0, 0.03, 0), Vector3(0.9, 0.05, 0.9), Look.c("accent2"))
	kit.plat(Vector3(1.25, y - 2.1, -20.3), Vector3(8.5, 0.8, 2.4), "alt", 1.2)   # the catch: land at 22 m/s and brake
	kit.pillar(Vector3(1.25, y - 2.9, -20.3), 0.6, 8.0)
	_blk(Vector3(-7.0, y - 0.6, -23.0), 1.2)


# ---- 6. slag steps -----------------------------------------------------------------------------

func _stage_6_slag_steps() -> void:
	var k: Array[Vector3] = [Vector3(-27.5, 42.0, -34.4), Vector3(-23.0, 43.3, -38.0), Vector3(-27.6, 44.3, -41.5), Vector3(-23.6, 46.0, -45.0)]
	_chain(Vector3(-27.5, 40.5, -29.35), k)
	for i: int in [1, 2, 3]:
		var side: float = 1.0 if i % 2 == 1 else -1.0
		kit.hazard(k[i] + Vector3(side * 1.5, 0.6, 0), Vector3(0.8, 3.2, 1.6))
		kit.pillar(k[i] - Vector3(0, 1.0, 0), 0.35, 5.0)
	# tap-jump beam under a molten ceiling
	var beam := Vector3(-27.0, 46.0, -55.0)
	kit.plat(beam, Vector3(0.8, 0.8, 13.0), "main", 1.0)                       # z -61.5 .. -48.5
	kit.hazard(beam + Vector3(0, 3.25, 0), Vector3(2.6, 0.6, 13.0))
	kit.block(beam + Vector3(0, 3.9, 0), Vector3(3.0, 0.7, 13.4), Look.c("decor"), false)
	kit.pillar(beam - Vector3(0, 0.8, 3.0), 0.4, 7.0)
	kit.pillar(beam - Vector3(0, 0.8, -3.0), 0.4, 7.0)
	r_jump(_edge(k[3], Vector3(beam.x, beam.y, -49.4)), Vector3(beam.x, beam.y, -49.4))
	for bz: float in [-51.6, -55.2, -58.8]:
		kit.hazard(Vector3(beam.x, beam.y + 0.25, bz), Vector3(2.4, 0.5, 0.5))
		r_jump(Vector3(beam.x, beam.y, bz + 1.3), Vector3(beam.x, beam.y, bz - 1.6), false)
	var k5 := Vector3(-24.2, 47.2, -65.2)
	var k6 := Vector3(-19.0, 48.4, -67.0)
	var cp6 := Vector3(-11.4, 49.5, -65.5)
	_chain(Vector3(beam.x + 0.1, beam.y, -61.15), [k5, k6])
	kit.plat(cp6, Vector3(5, 1.2, 5), "main", 2.4)
	kit.pillar(cp6 - Vector3(0, 1.2, 0), 1.0, 9.0)
	r_jump(_edge(k6, cp6), cp6 + Vector3(-1.2, 0, 0))
	kit.checkpoint(cp6, -90.0)
	kit.lamp(cp6 + Vector3(-2.1, 0, -2.1), 2.6)
	r_walk(cp6)
	r_checkpoint()
	_net(Vector3(-19, 33.5, -50), Vector3(24, 0.6, 44))


# ---- 7. updraft vents --------------------------------------------------------------------------

func _stage_7_vents() -> void:
	var z: float = -65.5
	var w1 := Vector3(-3.5, 52.5, z)
	kit.wind(w1, Vector3(5, 9, 4), Vector3(0, 75, 0), 14.0)
	kit.chimney(Vector3(w1.x, 30.0, z), 17.0, 2.2, false)
	var p1 := Vector3(6.0, 53.5, z)
	_pad_disc(p1, 1.4)
	var p1n: BouncePad = kit.pad(p1, 18.0, 0.0, 0.0, 1.1)
	for sz: int in [-1, 1]:
		kit.hazard(p1 + Vector3(0, 1.0, sz * 2.6), Vector3(2.4, 3.0, 0.8))
	var w2 := Vector3(13.0, 59.0, z)
	kit.wind(w2, Vector3(5, 9, 4), Vector3(0, 75, 0), 14.0)
	kit.chimney(Vector3(w2.x, 36.0, z), 18.0, 2.2, false)
	var p2 := Vector3(20.8, 60.0, z)
	_pad_disc(p2, 1.4, false)
	kit.pillar(p2 - Vector3(0, 0.7, 0), 0.4, 6.0)
	kit.pad(p2, 17.0, 0.0, 0.0, 1.1)
	kit.hazard(p2 + Vector3(2.6, 1.0, 0), Vector3(0.8, 3.0, 2.4))
	kit.hazard(p2 + Vector3(0, 1.0, -2.6), Vector3(2.4, 3.0, 0.8))
	var cp7 := Vector3(23.0, 61.5, -58.0)
	kit.plat(cp7, Vector3(5, 1.2, 5), "main", 2.4)
	kit.pillar(cp7 - Vector3(0, 1.2, 0), 1.0, 9.0)
	kit.checkpoint(cp7, 180.0)
	kit.lamp(cp7 + Vector3(2.1, 0, -2.1), 2.6)
	r_jump_onto(Vector3(-9.3, 49.5, z), p1n, Vector3(0, 0.1, 0))      # vent-assisted: not a plain jump
	r_pad(p1, p2)
	r_pad(p2, cp7 + Vector3(-0.5, 0, -1.2))
	r_walk(cp7)
	r_checkpoint()
	_net(Vector3(8, 42.0, -63), Vector3(36, 0.6, 14))


# ---- 8. blink works ----------------------------------------------------------------------------

func _stage_8_blink() -> void:
	var x: float = 23.0
	var q1 := Vector3(x, 61.5, -52.4)
	_pad_disc(q1, 1.4, false)
	kit.pillar(q1 - Vector3(0, 0.7, 0), 0.4, 6.0)
	kit.pad(q1, 19.0, 0.0, 0.0, 1.1)
	var b1 := Vector3(x, 64.5, -45.0)
	var b2 := Vector3(x, 65.5, -39.0)
	var b3 := Vector3(22.0, 69.5, -26.2)
	kit.blink(b1, Vector3(2.4, 0.5, 2.4), 3.0, 0.55, 0.0)
	kit.blink(b2, Vector3(2.4, 0.5, 2.4), 3.0, 0.55, 0.75)
	kit.blink(b3, Vector3(2.4, 0.5, 2.4), 3.0, 0.55, 0.2)
	var q2 := Vector3(x, 66.0, -33.4)
	_pad_disc(q2, 1.3, false)
	kit.pillar(q2 - Vector3(0, 0.7, 0), 0.4, 6.0)
	kit.pad(q2, 20.0, 0.0, 0.0, 1.0)
	for sx: int in [-1, 1]:
		kit.hazard(q2 + Vector3(sx * 2.3, 1.5, 0), Vector3(0.8, 4.0, 2.4))
	var d := Vector3(19.4, 70.5, -20.6)
	_blk(d, 1.6)
	var cp8 := Vector3(14.5, 70.5, -22.0)
	kit.plat(cp8, Vector3(5, 1.2, 5), "main", 2.4)
	kit.pillar(cp8 - Vector3(0, 1.2, 0), 1.0, 9.0)
	kit.checkpoint(cp8, 90.0)
	kit.lamp(cp8 + Vector3(2.1, 0, 2.1), 2.6)
	_cwait(3.0, 0.6, 0.7, 0.0)
	r_jump(Vector3(x, 61.5, -55.9), q1)
	r_pad(q1, b1)
	r_jump(b1 + Vector3(0, 0, 0.85), b2)
	r_jump(b2 + Vector3(0, 0, 0.85), q2)
	r_pad(q2, b3)
	r_jump(_edge(b3, d, 2.4), d)
	r_jump(_edge(d, cp8), cp8 + Vector3(1.3, 0, 0.5))
	r_walk(cp8)
	r_checkpoint()
	_net(Vector3(21, 53.0, -38), Vector3(10, 0.6, 44))


# ---- 9. ice chute -> angled pad -> boost strip -> sprint-bounce ---------------------------------

func _stage_9_chute() -> void:
	var z: float = -22.0
	var top := Vector3(12.0, 70.5, z)
	var run: float = 14.0
	var pitch: float = 25.0
	var c: Vector3 = top + Vector3(-cos(deg_to_rad(pitch)) * run * 0.5, -sin(deg_to_rad(pitch)) * run * 0.5, 0)
	kit.slick(c, Vector3(3.0, 0.5, run), 90.0, -pitch)
	for sz: int in [-1, 1]:
		var rail: KillZone = kit.hazard(c + Vector3(0, 0.3, sz * 1.8), Vector3(0.5, 0.8, run))
		rail.rotation_degrees = Vector3(-pitch, 90.0, 0)
	_arm(c + Vector3(0, 0, -1.0), 1.0, 0.5)
	var lip: Vector3 = top + Vector3(-cos(deg_to_rad(pitch)) * run, -sin(deg_to_rad(pitch)) * run, 0)
	var pad := Vector3(lip.x - 8.6, lip.y - 2.8, z)
	var deck := Vector3(-16.5, 66.5, -28.0)
	_pad_disc(pad, 1.6)
	_aim_pad(pad, deck + Vector3(0.4, 0, 0.4), 22.0, 1.3)
	kit.plat(deck, Vector3(4, 1.0, 4), "main", 2.0)
	_arm(deck, 1.4, 0.4)
	kit.boost(Vector3(-16.5, 66.5, -33.5), Vector3(2.2, 0.4, 7.0), 0.0, 20.0)     # z -30 .. -37
	var vp := Vector3(-16.5, 66.5, -38.3)
	_pad_disc(vp, 1.5)
	kit.pad(vp, 20.0, 0.0, 0.0, 1.3)
	for sx: int in [-1, 1]:
		kit.hazard(Vector3(-16.5 + sx * 2.4, 72.0, -49.0), Vector3(1.0, 12.0, 1.0))
	kit.hazard(Vector3(-16.5, 78.5, -49.0), Vector3(5.8, 1.0, 1.0))
	var cp9 := Vector3(-16.5, 68.5, -60.5)
	kit.plat(cp9, Vector3(6, 1.2, 7), "main", 2.4)
	kit.pillar(cp9 - Vector3(0, 1.2, 0), 1.0, 9.0)
	kit.checkpoint(cp9 + Vector3(-0.6, 0, 0), -90.0)
	kit.lamp(cp9 + Vector3(-2.6, 0, -3.0), 2.6)
	r_walk(top + Vector3(-0.5, 0, 0))
	r_pad(pad, deck + Vector3(0.4, 0, 0.4))
	r_walk(Vector3(-16.5, 66.5, -30.5))
	r_pad(vp, cp9 + Vector3(0, 0, 1.5))
	r_walk(cp9 + Vector3(-0.6, 0, 0))
	r_checkpoint()
	_net(Vector3(-3.5, 56.0, -22), Vector3(35, 0.6, 9))
	_net(Vector3(-16.5, 56.0, -46), Vector3(11, 0.6, 40))


# ---- 10 + 11. the Crucible ---------------------------------------------------------------------

func _net_under(a: Vector3, b: Vector3, drop: float = 8.0) -> void:
	_net(Vector3((a.x + b.x) * 0.5, minf(a.y, b.y) - drop, (a.z + b.z) * 0.5), Vector3(absf(a.x - b.x) + 9.0, 0.6, absf(a.z - b.z) + 9.0))


## Molten post just outboard of a pad: carry too much speed past it and you die.
func _outer_post(c: Vector3, gap: float = 2.7) -> void:
	var out: Vector3 = Vector3(c.x, 0, c.z - OZ).normalized()
	kit.hazard(c + out * gap + Vector3(0, 3.0, 0), Vector3(1.2, 8.0, 1.2))


func _gate(a: Vector3, b: Vector3, rise: float, half: float = 2.3) -> void:
	var m: Vector3 = a.lerp(b, 0.5)
	var side: Vector3 = Vector3(b.z - a.z, 0, -(b.x - a.x)).normalized()
	for s: int in [-1, 1]:
		kit.hazard(m + side * (s * half) + Vector3(0, rise, 0), Vector3(0.9, 8.0, 0.9))


func _stage_10_crucible() -> void:
	var cp9 := Vector3(-16.5, 68.5, -60.5)
	var c1: Vector3 = cp9 + Vector3(2.0, 0, 0)
	var c2: Vector3 = _pol(178.0, 14.0, 72.0)
	var c3: Vector3 = _pol(208.0, 14.0, 75.0)
	var c4: Vector3 = _pol(238.0, 13.5, 78.0)
	var c4b: Vector3 = _pol(266.0, 14.0, 81.0)
	var cp10: Vector3 = _pol(295.0, 15.5, 84.0)
	_aim_pad(c1, c2, 26.0, 1.0)
	_pad_disc(c2)
	_aim_pad(c2, c3, 26.0, 1.0)
	for c: Vector3 in [c3, c4, c4b]:
		_pad_disc(c)
		kit.pad(c, 21.0, 0.0, 0.0, 1.0)
		_outer_post(c)
	kit.plat(cp10, Vector3(5, 1.2, 7), "main", 2.4)
	_arm(cp10 + Vector3(-2, 0, 0), 1.6, 0.5)
	kit.checkpoint(cp10 + Vector3(0, 0, -1.3), 180.0)
	kit.lamp(cp10 + Vector3(2.1, 0, -3.0), 2.6)
	_gate(c1, c2, 5.0)
	r_pad(c1, c2)
	r_pad(c2, c3)
	r_pad(c3, c4)
	r_pad(c4, c4b)
	r_pad(c4b, cp10 + Vector3(-0.3, 0, -1.8))
	r_walk(cp10 + Vector3(0, 0, -1.3))
	r_checkpoint()
	var chain: Array[Vector3] = [c1, c2, c3, c4, c4b, cp10]
	for i: int in chain.size() - 1:
		_net_under(chain[i], chain[i + 1])

	# part two
	var c5: Vector3 = cp10 + Vector3(0, 0, 2.6)
	var bl: Vector3 = _pol(325.0, 13.5, 86.5)
	var c6: Vector3 = _pol(350.0, 13.5, 87.5)
	var c7: Vector3 = _pol(25.0, 13.0, 90.5)
	var c8: Vector3 = _pol(60.0, 13.5, 93.5)
	var c9: Vector3 = _pol(98.0, 14.0, 96.5)
	var roof_y: float = ROOF_Y - DY
	var roof_land := Vector3(-3.0, roof_y, OZ + 0.5)
	_aim_pad(c5, bl, 24.0, 1.0)
	kit.blink(bl, Vector3(3.0, 0.5, 3.0), 3.0, 0.6, 0.0)
	for c: Vector3 in [c6, c7, c8]:
		_pad_disc(c)
		kit.pad(c, 21.0, 0.0, 0.0, 1.0)
		_outer_post(c)
	_pad_disc(c9)
	_aim_pad(c9, roof_land, 24.0, 1.0)
	_gate(c9, roof_land, 5.0)
	for c: Vector3 in [c2, c3, c4, c4b, c6, c7, c8, c9]:
		var inw: Vector3 = -Vector3(c.x, 0, c.z - OZ).normalized()
		kit.lamp(c + inw * 1.25, 1.4, false, Look.c("accent2"))
	# the old finish: the tower roof is now checkpoint 11, facing the pour line to the Smelter
	var cp11 := Vector3(0, roof_y, OZ - 1.0)
	kit.checkpoint(cp11, 0.0)
	_cwait(3.0, 0.7, 0.8, 0.0)
	r_pad(c5, bl)
	r_jump(_edge(bl, c6, 3.0), c6)
	r_pad(c6, c7)
	r_pad(c7, c8)
	r_pad(c8, c9)
	r_pad(c9, roof_land)
	r_walk(cp11)
	r_checkpoint()
	var chain2: Array[Vector3] = [c5, bl, c6, c7, c8, c9]
	for i: int in chain2.size() - 1:
		_net_under(chain2[i], chain2[i + 1])
	_net_under(c9, Vector3(-9.0, c9.y, OZ))


# =============================================================================================
# SECOND HALF - over the pour line to the Smelter, then twice round it to its crown.
# Authored in world coordinates (kit.root = self, no DY lift).
# =============================================================================================

const SX: float = -12.0          # the Smelter's axis is x = SX, z = SZ
const SZ: float = -160.0
const SCORE: float = 16.0         # its core is SCORE x SCORE (faces at x = -20 / -4, z = -152 / -168)
const S_TOP: float = 158.0        # top of the crown deck (the finish)
const RAIL_Y: float = 113.8       # drum height of the pour-line ladles


## A drum ladle pouring a molten sheet across the path (see mechanics/foundry_ladle.gd).
func _ladle(floor_pt: Vector3, width: float, drop: float, period: float, pour: float, phase: float, yaw: float = 0.0) -> FoundryLadle:
	var l := FoundryLadle.new()
	l.width = width
	l.drop = drop
	l.period = period
	l.pour_fraction = pour
	l.phase = phase
	l.rotation_degrees.y = yaw
	kit._add(l, floor_pt)
	return l


## Molten pool: a kill surface with a basin under it and heat motes over it.
func _slag_pool(top: Vector3, size: Vector2) -> void:
	kit.hazard(top - Vector3(0, 0.3, 0), Vector3(size.x, 0.6, size.y))
	kit.block(top - Vector3(0, 1.0, 0), Vector3(size.x + 1.0, 1.0, size.y + 1.0), Look.c("decor"), false)
	FoundryFx.motes(self, top + Vector3(0, 0.9, 0), Vector3(size.x * 0.45, 0.6, size.y * 0.45), int(clampf(size.x * size.y * 0.25, 8, 36)))


## Stage gate: sparks and cyan glitter when you arrive on a new checkpoint.
func _gate_fx(at: Vector3) -> void:
	var b1: GPUParticles3D = FoundryFx.burst(44, 9.0)
	var b2: GPUParticles3D = FoundryFx.glitter(26, 6.0, Look.c("accent2"))
	FoundryFx.near_burst(self, at + Vector3(0, 0.4, 0), 2.3, [b1, b2])


func _checkpoint(at: Vector3, yaw: float, lamp_off: Vector3 = Vector3(2.1, 0, 2.1)) -> void:
	kit.checkpoint(at, yaw)
	kit.lamp(at + lamp_off, 2.6)
	_gate_fx(at)


## Seconds-ahead window test for timed hazards: true when none of `probes` (each [node, eta])
## is deadly within +-`slack` s of its ETA. Nodes answer is_on_at / is_pouring_at / _deadly.
func _clear_at(probes: Array, slack: float = 0.2) -> bool:
	var t: float = Game.course_time
	for pr: Array in probes:
		var n: Node = pr[0]
		var eta: float = float(pr[1])
		var s: float = -slack
		while s <= slack + 0.001:
			var tt: float = t + eta + s
			if n is LaserGate and (n as LaserGate).is_on_at(tt):
				return false
			if n is FoundryLadle and (n as FoundryLadle).is_pouring_at(tt):
				return false
			if n is Crusher and not (n as Crusher).is_clear_for(tt, 0.0):
				return false
			if n is Piston and (n as Piston).extension_at(tt) > 0.03:
				return false
			s += 0.05
	return true


func _build_smelter() -> void:
	var iron: Color = Look.c("decor")
	var bottom: float = 84.0
	var top: float = S_TOP - 2.0
	var h: float = SCORE * 0.5
	var axis := Vector3(SX, 0, SZ)
	kit.block(axis + Vector3(0, (bottom + top) * 0.5, 0), Vector3(SCORE, top - bottom, SCORE), iron)
	var foot := Look.cylinder(1.4, 10.0, Look.flat(iron.darkened(0.2), 0.9), Vector3.ZERO, SCORE * 0.72, 4)
	foot.rotation.y = PI / 4.0
	kit._add(foot, axis + Vector3(0, bottom - 5.0, 0))
	var y: float = bottom + 3.0
	while y < top - 2.0:
		kit.block(axis + Vector3(0, y, 0), Vector3(SCORE + 0.7, 0.9, SCORE + 0.7), Look.c("metal"), false)
		kit.glow_strip(axis + Vector3(0, y + 0.75, 0), Vector3(SCORE + 0.25, 0.22, SCORE + 0.25), Look.c("decor2"))
		y += 8.0
	# molten slits low on the core (below the course)
	for i: int in 4:
		var yaw: float = 90.0 * i
		var n: Vector3 = Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3(0, 0, 1)
		var side: Vector3 = Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3(1, 0, 0)
		for k: int in [-2, 2]:
			var c: Vector3 = axis + Vector3(0, 96.0, 0) + n * (h + 0.02) + side * (k * 2.4)
			kit.glow_strip(c, Vector3(0.9, 14.0, 0.12), Look.c("decor2"), yaw)
	# the crown deck (finish) and its rim
	kit.plat(axis + Vector3(0, S_TOP, 0), Vector3(20, 2, 20), "goal", 0.0)
	kit.block(axis + Vector3(0, S_TOP - 2.6, 0), Vector3(18, 1.2, 18), Look.c("metal"), false)
	for sx: int in [-1, 1]:
		kit.glow_strip(axis + Vector3(sx * 10.05, S_TOP - 1.0, 0), Vector3(0.15, 0.5, 19.0), Look.c("accent2"))
		kit.glow_strip(axis + Vector3(0, S_TOP - 1.0, sx * 10.05), Vector3(19.0, 0.5, 0.15), Look.c("accent2"))
	# the ladle rail from the tower roof to the Smelter's shoulder, hung from both
	var rail_y: float = RAIL_Y + 3.35
	var z0: float = OZ - 7.5
	var z1: float = SZ + h - 1.0
	kit.block(Vector3(0, rail_y, (z0 + z1) * 0.5), Vector3(0.9, 0.7, z1 - z0), Look.c("metal"), false)
	kit.block(Vector3(0, rail_y + 0.55, (z0 + z1) * 0.5), Vector3(1.4, 0.3, z1 - z0), Look.c("decor"), false)
	kit.glow_strip(Vector3(0, rail_y - 0.4, (z0 + z1) * 0.5), Vector3(0.2, 0.1, z1 - z0), Look.c("decor2"))
	for sx: int in [-1, 1]:
		kit.block(Vector3(sx * 2.6, (ROOF_Y + rail_y) * 0.5, z0), Vector3(0.5, rail_y - ROOF_Y, 0.5), Look.c("metal"), false)
	kit.block(Vector3(0, rail_y + 0.2, z0), Vector3(5.7, 0.5, 0.6), Look.c("metal"), false)
	kit.block(Vector3(SX + h + 2.0, rail_y, z1), Vector3(4.0 + 0.8, 1.0, 1.0), Look.c("metal"), false)
	kit.pipe(Vector3(0, rail_y - 0.3, z1), Vector3(SX + h, rail_y - 5.0, z1 - 2.0), 0.3)
	for zz: float in [-66.0, -92.0, -122.0]:
		kit.pipe(Vector3(0, rail_y + 0.6, zz), Vector3(0, rail_y + 22.0, zz - 16.0), 0.12, Look.c("metal"))


# ---- 12. gatehouse: sprint pad, then lasers through the gate or mantles over it, first wall run --

func _stage_12_gatehouse() -> void:
	var y: float = ROOF_Y
	# sprint-bounce off the roof lip over the slag trough
	var p1 := Vector3(0, y, -45.6)
	kit.pad(p1, 17.0, 0.0, 0.0, 0.9)
	kit.glow_strip(Vector3(0, y + 0.02, -43.4), Vector3(0.22, 0.04, 2.8), Look.c("accent2"))
	_slag_pool(Vector3(0, y - 5.0, -49.5), Vector2(8, 5))
	var deck := Vector3(0, y, -62.5)
	kit.plat(deck, Vector3(3.4, 1.0, 21.0), "main", 1.2)       # z -52 .. -73, on through the gate tunnel
	kit.plat(Vector3(3.3, y, -58.5), Vector3(3.6, 1.0, 7.0), "alt", 1.2)   # east apron, z -55 .. -62
	r_pad(p1, Vector3(0, y, -55.5))

	# the gatehouse (z -62 .. -73)
	var top: float = y + 3.6
	kit.block(Vector3(-3.3, y + 1.8, -67.5), Vector3(3.6, 3.6, 11.0), Look.c("decor"))       # west wing
	kit.block(Vector3(0, top - 0.3, -67.5), Vector3(3.0, 0.6, 11.0), Look.c("metal"))         # tunnel lintel
	var wa := Vector3(3.3, top, -63.5)
	kit.ledge(wa, Vector3(3.6, 3.6, 3.0), 0.0, "alt")                                         # z -62 .. -65
	var wb := Vector3(3.3, top + 1.2, -71.25)
	kit.ledge(wb, Vector3(3.6, 4.8, 3.5), 0.0, "alt")                                         # z -69.5 .. -73
	kit.block(Vector3(3.3, y + 0.75, -67.25), Vector3(3.6, 1.5, 4.5), Look.c("decor"))
	kit.hazard(Vector3(3.3, y + 2.0, -67.25), Vector3(3.2, 1.0, 4.3))                         # molten vent between
	FoundryFx.sparks(self, Vector3(3.3, y + 2.6, -67.25), Vector3.UP, 16, 5.0, 25.0, 0.9)
	# route 0: three lasers in a green wave down the tunnel
	var gates: Array = []
	var gz: Array[float] = [-64.2, -67.4, -70.6]
	var eta: Array[float] = [0.47, 0.83, 1.19]
	for i: int in 3:
		var g: LaserGate = kit.laser(Vector3(0, y + (0.55 if i % 2 == 0 else 1.25), gz[i]), Vector3(3.0, 0.22, 0.22), 1.8, 0.45, fposmod(-eta[i] / 1.8, 1.0), 0.0)
		gates.append([g, eta[i]])
	kit.glow_strip(Vector3(0, y + 0.02, -60.0), Vector3(0.3, 0.04, 3.0), Color(1.0, 0.3, 0.2))
	kit.banner(Vector3(-1.5, y, -61.4), 3.6, Color(1.0, 0.3, 0.2), 0.0)
	kit.banner(Vector3(5.0, y, -61.4), 3.6, LedgeBlock.LIP_COLOR, 0.0)
	var exit := Vector3(1.6, y, -76.5)
	kit.plat(exit, Vector3(6.6, 1.0, 7.0), "main", 1.2)                                       # z -73 .. -80
	if route_variant == 0:
		r_walk(Vector3(0, y, -60.8))
		r_until(func() -> bool: return _clear_at(gates, 0.2))
		r_walk(Vector3(0, y, -75.0))
	else:
		r_walk(Vector3(3.3, y, -58.0))
		r_mantle(Vector3(3.3, y, -60.4), Vector3(3.3, top, -63.2))
		r_jump(_edge(wa, wb, 3.0) + Vector3(0, 0, 0.2), wb + Vector3(0, 0, 0.9))
		r_jump(Vector3(3.3, wb.y, -72.65), Vector3(2.8, y, -75.8))

	# first wall run: a 19 m slag gap crossed only along the panel
	kit.wallrun(Vector3(2.0, y + 1.2, -90.0), Vector3(14, 6, 0.5), 90.0)
	_slag_pool(Vector3(0, y - 7.0, -89.5), Vector2(9, 18))
	var land := Vector3(-1.0, y, -104.0)
	kit.plat(land, Vector3(8, 1.2, 10), "main", 2.0)                                          # z -99 .. -109
	var cp12 := Vector3(-1.0, y, -102.6)
	_checkpoint(cp12, 0.0, Vector3(-3.2, 0, 3.2))
	r_wallrun(Vector3(0.3, y, -79.6), Vector3(1.6, y + 1.2, -84.0), Vector3(1.6, y + 1.2, -94.0), Vector3(-1.5, y, -102.0))
	r_walk(cp12)
	r_checkpoint()
	_net(Vector3(0, y - 9.0, -75.0), Vector3(16, 0.6, 62))


# ---- 13. pour line: belts through the ladle curtains, ingot hops under the pours -----------------

func _stage_13_pour_line() -> void:
	var y: float = ROOF_Y
	# ingot rollers (a boost strip) under two ladles: 18 m/s, and they launch the leap
	kit.boost(Vector3(0, y, -115.0), Vector3(3.0, 0.4, 12.0), 0.0, 18.0)                       # z -109 .. -121
	kit.pillar(Vector3(0, y - 0.4, -115.0), 0.5, 7.0)
	var l1: FoundryLadle = _ladle(Vector3(0, y, -112.8), 3.4, RAIL_Y - y, 2.4, 0.35, 0.796)
	var l2: FoundryLadle = _ladle(Vector3(0, y, -117.4), 3.4, RAIL_Y - y, 2.4, 0.35, 0.812)
	# the third ladle pours across the leap itself, down into the slag
	var l3: FoundryLadle = _ladle(Vector3(0, y - 4.0, -125.2), 2.8, RAIL_Y - y + 4.0, 2.4, 0.35, 0.388)
	_slag_pool(Vector3(0, y - 7.0, -126.0), Vector2(8, 20))
	var i2 := Vector3(0, y + 1.8, -131.8)
	kit.plat(i2 + Vector3(0, 0, 0.5), Vector3(2.4, 1.0, 5.0), "alt", 1.3)                   # z -128.8 .. -133.8
	kit.pillar(i2 - Vector3(0, 1.0, 0), 0.4, 5.0)
	# belt 2 runs AGAINST you under the last ladle
	kit.conveyor(Vector3(0, y + 1.8, -138.8), Vector3(3.0, 0.4, 10.0), 180.0, 4.0)           # z -133.8 .. -143.8
	kit.pillar(Vector3(0, y + 1.4, -138.8), 0.5, 7.0)
	var l4: FoundryLadle = _ladle(Vector3(0, y + 1.8, -139.0), 3.4, RAIL_Y - y - 1.8, 2.4, 0.4, 0.1)
	var cp13 := Vector3(0, y + 3.0, -148.5)
	kit.plat(cp13 + Vector3(0, 0, 0.5), Vector3(5, 1.2, 6), "main", 2.4)                     # z -145 .. -151
	_checkpoint(cp13, 90.0, Vector3(2.1, 0, 2.1))
	r_walk(Vector3(0, y, -107.6))
	r_until(func() -> bool: return _clear_at([[l1, 0.45], [l2, 0.7], [l3, 1.15]], 0.18))
	r_jump(Vector3(0, y, -120.6), i2 + Vector3(0, 0, 0.6))
	_speed(18.0)
	r_until(func() -> bool: return _clear_at([[l4, 1.05]], 0.55))
	r_jump(Vector3(0, i2.y, -143.5), cp13 + Vector3(0, 0, 1.6))
	_speed(5.0)
	r_walk(cp13)
	r_checkpoint()
	_net(Vector3(0, y - 9.0, -127.0), Vector3(12, 0.6, 40))


# ---- 14. the flue: a zig-zag chimney of wall-run panels, out of the last kick onto a ledge ------

func _stage_14_flue() -> void:
	var y: float = ROOF_Y + 3.0          # CP13 deck, 110.4
	var zi: float = -151.75              # inner panels (on the Smelter's south face), face at -151.5
	var zo: float = -146.25              # outer panels, face at -146.5
	kit.wallrun(Vector3(-9.5, y + 2.0, zi), Vector3(10, 7, 0.5), 0.0)       # A  x -4.5 .. -14.5
	kit.wallrun(Vector3(-18.0, y + 3.6, zo), Vector3(12, 7, 0.5), 0.0)      # B  x -12 .. -24
	kit.wallrun(Vector3(-26.0, y + 5.2, zi), Vector3(10, 7, 0.5), 0.0)      # C  x -21 .. -31 (past the corner)
	# C stands free past the corner: a frame holds it
	kit.block(Vector3(-26.0, y + 9.2, zi - 0.6), Vector3(10.4, 0.6, 1.4), Look.c("metal"), false)
	kit.pipe(Vector3(-21.5, y + 9.2, zi - 0.6), Vector3(SX - SCORE * 0.5, y + 14.0, zi - 2.0), 0.3)
	kit.pillar(Vector3(-30.8, y + 1.6, zi), 0.4, 14.0)
	# outer frame of the flue: a riveted hood over it, the slag channel far below
	kit.block(Vector3(-15.0, y + 12.0, -149.0), Vector3(24.0, 0.6, 7.2), Look.c("decor"), false)
	for xx: float in [-4.0, -12.0, -20.0]:
		kit.block(Vector3(xx, y + 6.0, zo + 0.9), Vector3(0.5, 12.5, 0.5), Look.c("metal"), false)
	_slag_pool(Vector3(-15.0, y - 12.0, -149.0), Vector2(26, 7))
	FoundryFx.rising_sparks(self, Vector3(-9.0, y - 10.0, -149.0), Vector3(5.0, 0.5, 2.0), 36, 6.0)
	FoundryFx.rising_sparks(self, Vector3(-21.0, y - 10.0, -149.0), Vector3(5.0, 0.5, 2.0), 36, 6.0)
	FoundryFx.embers(self, Vector3(-15.0, y + 2.0, -149.0), Vector3(12.0, 4.0, 2.5), 50)
	# the ledge you mantle onto out of the last kick: checkpoint 14
	var cp_top := Vector3(-34.0, y + 10.0, -148.0)
	kit.ledge(cp_top, Vector3(5.0, 4.8, 5.0), 0.0, "main")                  # x -36.5 .. -31.5, z -150.5 .. -145.5
	kit.pillar(cp_top - Vector3(0, 4.0, 0), 1.0, 8.0)
	var cp14: Vector3 = cp_top + Vector3(-0.4, 0, -0.6)
	_checkpoint(cp14, 0.0, Vector3(-2.0, 0, 1.8))
	r_wallrun(Vector3(-2.1, y, -149.6), Vector3(-6.5, y + 1.2, -151.1), Vector3(-9.8, y, -151.1), Vector3(-15.0, y + 4.1, -146.9))
	r_wallrun(Vector3.ZERO, Vector3(-15.0, y + 4.1, -146.9), Vector3(-18.8, y, -146.9), Vector3(-24.2, y + 5.6, -151.1), true, true)
	r_wallrun(Vector3.ZERO, Vector3(-24.2, y + 5.6, -151.1), Vector3(-26.8, y, -151.1), cp_top + Vector3(1.5, 0, 0), true, true)
	r_walk(cp14)
	r_checkpoint()
	_net(Vector3(-17.0, y - 8.0, -149.0), Vector3(36, 0.6, 12))


# ---- 15. forge press: dash under a press, mantle an anvil under the next one's rhythm -------------

## Sparks thrown flat out from under a press every time it slams.
func _slam_fx(c: Crusher, floor_top: Vector3) -> void:
	var b1: GPUParticles3D = FoundryFx.burst(40, 8.0, FoundryFx.SPARK, 0.0, 0.85)
	var b2: GPUParticles3D = FoundryFx.steam_puff(14, 2.5, 1.2)
	FoundryFx.clock_burst(self, floor_top + Vector3(0, 0.25, 0), c.period, c.phase, Crusher.DOWN, [b1, b2])


func _stage_15_forge_press() -> void:
	var x: float = -34.0
	var f: float = ROOF_Y + 13.0                 # 120.4, the CP14 ledge top
	var wa := Vector3(x, f, -156.0)
	kit.plat(wa, Vector3(2.6, 1.0, 11.0), "main", 1.2)                        # z -150.5 .. -161.5
	var c1: Crusher = kit.crusher(Vector3(x, f, -154.5), Vector3(2.8, 1.6, 3.0), 3.2, 2.8, 0.0)
	var anvil := Vector3(x, f + 3.4, -163.5)
	kit.ledge(anvil, Vector3(3.0, 3.4, 4.0), 0.0, "alt")                        # z -161.5 .. -165.5
	var c2: Crusher = kit.crusher(anvil, Vector3(2.8, 1.4, 3.6), 3.0, 2.8, 0.69)
	var wb := Vector3(x, f + 1.0, -170.0)
	kit.plat(wb, Vector3(2.6, 1.0, 9.0), "main", 1.2)                          # z -165.5 .. -174.5
	var c3: Crusher = kit.crusher(Vector3(x, wb.y, -171.0), Vector3(2.8, 1.6, 3.0), 3.2, 2.6, 0.3)
	_slam_fx(c1, Vector3(x, f, -154.5))
	_slam_fx(c2, anvil)
	_slam_fx(c3, Vector3(x, wb.y, -171.0))
	for zz: float in [-156.0, -170.0]:
		kit.pillar(Vector3(x, f - 1.0, zz), 0.5, 7.0)
		kit.pipe(Vector3(x + 1.0, f - 1.5, zz), Vector3(SX - SCORE * 0.5, f - 6.0, zz), 0.35)
	# the forge glow under the press line
	_slag_pool(Vector3(x, f - 11.0, -163.0), Vector2(8, 26))
	FoundryFx.embers(self, Vector3(x, f - 2.0, -163.0), Vector3(3.5, 3.0, 12.0), 40)
	var cp_top := Vector3(x, wb.y + 3.6, -177.0)
	kit.ledge(cp_top, Vector3(5.0, 4.4, 5.0), 0.0, "main")                    # z -174.5 .. -179.5
	kit.pillar(cp_top - Vector3(0, 4.4, 0), 1.0, 8.0)
	var cp15: Vector3 = cp_top + Vector3(-0.6, 0, -0.4)
	_checkpoint(cp15, -90.0, Vector3(-2.0, 0, -2.0))
	r_walk(Vector3(x, f, -151.8))
	r_until(func() -> bool:
		var t: float = Game.course_time
		if not c1.is_clear_for(t + 0.05, 0.6):
			return false
		var s: float = 0.95
		while s <= 1.95:
			if c2.gap_at(t + s) < 1.7 or not c2.is_clear_for(t + s, 0.0):
				return false
			s += 0.05
		return true)
	r_mantle(Vector3(x, f, -160.1), Vector3(x, anvil.y, -162.4))
	r_jump(Vector3(x, anvil.y, -165.1), Vector3(x, wb.y, -166.9))
	r_until(func() -> bool: return c3.is_clear_for(Game.course_time, 0.9))
	r_mantle(Vector3(x, wb.y, -173.0), Vector3(x, cp_top.y, -175.6))
	r_walk(cp15)
	r_checkpoint()
	_net(Vector3(x, f - 8.0, -163.0), Vector3(12, 0.6, 32))


# ---- 16. ingot feed: rams stamping across a belt, or ride the big ram's punch --------------------

## Steam blown out of a piston's housing every time it punches.
func _punch_fx(p: Piston, at: Vector3, dir: Vector3) -> void:
	var b1: GPUParticles3D = FoundryFx.steam_puff(10, 3.0, 1.0, dir)
	var b2: GPUParticles3D = FoundryFx.burst(16, 5.0, FoundryFx.SPARK, 0.5, 0.0)
	FoundryFx.clock_burst(self, at, p.period, p.phase, Piston.PUNCH_START, [b1, b2])


func _stage_16_ingot_feed() -> void:
	var y: float = ROOF_Y + 17.6                # 125.0, the CP15 ledge top
	var zb: float = -176.0                       # the belt line (route 0)
	var zl: float = -181.55                      # the launch line (route 1)
	# route 0: a belt dragging you back while three rams stamp across it
	kit.conveyor(Vector3(-24.5, y, zb), Vector3(2.6, 0.4, 14.0), 90.0, 4.0)       # x -31.5 .. -17.5
	var rams: Array = []
	var ram_x: Array[float] = [-28.0, -23.5, -19.0]
	var eta: Array[float] = [0.95, 1.85, 2.75]
	for i: int in 3:
		var ph: float = fposmod(-eta[i] / 2.4, 1.0)
		var r: Piston = kit.piston(Vector3(ram_x[i], y + 1.2, -173.6), Vector3(2.4, 1.2, 2.0), 0.0, 2.8, 2.4, ph, 8.0)
		rams.append([r, eta[i]])
		_punch_fx(r, Vector3(ram_x[i], y + 0.8, -170.0), Vector3(0, 0.3, 1))
	var pb := Vector3(-16.0, y, zb)
	kit.plat(pb, Vector3(3.0, 1.0, 2.6), "alt", 1.2)                                # x -17.5 .. -14.5
	kit.pillar(Vector3(-24.5, y - 0.4, zb), 0.5, 7.0)
	# route 1: the launch ram - stand on the mark and let it throw you over the gap
	var deck := Vector3(-30.0, y, zl + 0.5)
	kit.plat(deck, Vector3(7.0, 1.0, 4.1), "alt", 1.2)                              # x -33.5 .. -26.5, z -183.6 .. -179.5
	var launcher: Piston = kit.piston(Vector3(-32.5, y + 1.6, zl), Vector3(2.4, 1.6, 1.6), -90.0, 2.0, 3.0, 0.0, 16.0)
	_punch_fx(launcher, Vector3(-36.0, y + 0.8, zl), Vector3(-1, 0.3, 0))
	var mark := Vector3(-31.0, y, zl)
	kit.glow_strip(mark + Vector3(0, 0.03, 0), Vector3(0.9, 0.05, 0.9), Look.c("accent2"))
	kit.glow_strip(Vector3(-28.4, y + 0.03, zl), Vector3(3.6, 0.05, 0.2), Look.c("accent2"))
	var catch := Vector3(-13.5, y - 4.0, zl)
	kit.plat(catch, Vector3(8.0, 1.0, 3.4), "main", 1.2)                            # x -17.5 .. -9.5
	kit.pillar(catch - Vector3(0, 1.0, 0), 0.6, 7.0)
	# where the lines rejoin: the far deck (its west face is the launch line's mantle wall)
	var rj := Vector3(-6.0, y - 0.4, -179.0)
	kit.ledge(rj, Vector3(7.0, 4.6, 10.0), 0.0, "main")                             # x -9.5 .. -2.5, z -184 .. -174
	kit.banner(Vector3(-31.0, y, -174.9), 3.8, Color(1.0, 0.7, 0.15), 0.0)
	kit.banner(Vector3(-27.0, y, -183.3), 3.8, Look.c("accent2"), 0.0)
	# the rejoin sprint pad over the corner gap, through a molten gate, to checkpoint 16
	var vp := Vector3(-1.6, rj.y, -176.5)
	kit.disc(vp, 1.3, 0.7, "accent", 1.3)
	kit.pad(vp, 18.0, 0.0, 0.0, 1.0)
	var cp16 := Vector3(6.0, y + 3.2, -176.5)
	kit.plat(cp16, Vector3(5, 1.2, 5), "main", 2.4)
	kit.pillar(cp16 - Vector3(0, 1.2, 0), 1.0, 9.0)
	kit.pipe(cp16 - Vector3(2.0, 1.4, 0), Vector3(SX + SCORE * 0.5, cp16.y - 6.0, -168.0), 0.4)
	_gate(vp, cp16, 5.2, 2.4)
	_checkpoint(cp16, 180.0, Vector3(2.1, 0, -2.1))
	if route_variant == 0:
		r_walk(Vector3(-32.2, y, zb))
		r_until(func() -> bool: return _clear_at(rams, 0.33))
		r_walk(Vector3(-15.2, y, zb))
		r_jump(Vector3(-14.85, y, zb), Vector3(-8.4, rj.y, zb))
	else:
		r_walk(Vector3(-32.6, y, -179.4))
		r_until(func() -> bool:
			var u: float = fposmod(Game.course_time / launcher.period + launcher.phase, 1.0)
			return u > 0.12 and u < 0.3)
		_kick(mark, catch + Vector3(-1.0, 0, 0))
		r_mantle(Vector3(-11.1, catch.y, zl), Vector3(-8.2, rj.y, zl))
	r_pad(vp, cp16 + Vector3(-1.0, 0, 0))
	r_walk(cp16)
	r_checkpoint()
	_net(Vector3(-15.0, y - 9.0, -179.0), Vector3(44, 0.6, 16))


# ---- 17. kiln works: blinks and a laser beam, or a 90% jump to the kiln portal -------------------

func _stage_17_kiln() -> void:
	var y: float = ROOF_Y + 20.8                # 128.2, the CP16 deck
	# route 0: two blinking kiln plates, a narrow beam swept by lasers
	var b1 := Vector3(4.5, y + 0.6, -170.0)
	var b2 := Vector3(3.5, y + 1.8, -164.8)
	var k1: BlinkPlatform = kit.blink(b1, Vector3(2.2, 0.5, 2.2), 3.0, 0.55, 0.0)
	var k2: BlinkPlatform = kit.blink(b2, Vector3(2.2, 0.5, 2.2), 3.0, 0.55, 0.78)
	var beam := Vector3(4.0, y + 2.4, -156.5)
	kit.plat(beam, Vector3(0.9, 0.8, 9.0), "main", 1.0)                              # z -161 .. -152
	kit.pillar(beam - Vector3(0, 0.8, 2.5), 0.35, 6.0)
	kit.pillar(beam - Vector3(0, 0.8, -2.5), 0.35, 6.0)
	var lz: Array[float] = [-158.5, -154.5]
	var eta: Array[float] = [0.33, 0.78]
	var gates: Array = []
	for i: int in 2:
		var g: LaserGate = kit.laser(Vector3(beam.x, beam.y + (0.5 if i == 0 else 1.15), lz[i]), Vector3(2.4, 0.2, 0.2), 2.0, 0.5, fposmod(-eta[i] / 2.0, 1.0), 0.0)
		gates.append([g, eta[i]])
	# the sprint pad at the beam's end fires you up to checkpoint 17
	var vp := Vector3(4.0, beam.y, -150.8)
	kit.disc(vp, 1.3, 0.7, "accent", 1.3)
	kit.pad(vp, 20.0, 0.0, 0.0, 1.0)
	var cp17 := Vector3(4.6, y + 6.4, -142.0)
	kit.plat(cp17, Vector3(5, 1.2, 5), "main", 2.4)                                 # z -144.5 .. -139.5
	kit.pillar(cp17 - Vector3(0, 1.2, 0), 1.0, 9.0)
	kit.pipe(cp17 - Vector3(2.0, 1.4, 0), Vector3(SX + SCORE * 0.5, cp17.y - 7.0, -152.0), 0.4)
	_checkpoint(cp17, 90.0, Vector3(2.1, 0, 2.1))
	for zz: float in [-146.0, -138.0]:
		kit.hazard(Vector3(vp.x + 2.4, vp.y + 5.0, zz + 0.0), Vector3(0.8, 7.0, 0.8))
	# route 1: the kiln portal on a narrow plank - a 90% jump buys the skip to the beam's end
	var plank := Vector3(11.2, y + 0.4, -166.4)
	kit.plat(plank, Vector3(1.3, 0.8, 4.2), "alt", 1.0)                              # z -168.5 .. -164.3
	kit.pillar(plank - Vector3(0, 0.8, 0), 0.35, 6.0)
	var pr: WarpPortal = kit.portal(plank + Vector3(0, 0, 1.2), 180.0, Vector3(beam.x, beam.y, -161.4), 180.0, 7.0)
	FoundryFx.near_burst(self, pr.exit_point() + Vector3(0, 1.0, 0), 1.6, [FoundryFx.glitter(30, 5.0, Color(0.4, 0.75, 1.0)), FoundryFx.burst(24, 6.0, Color(0.5, 0.8, 1.0))])
	kit.lamp(Vector3(9.6, y, -174.6), 2.4, false, Color(1.0, 0.55, 0.15))
	kit.lamp(Vector3(3.0, y, -174.6), 2.4, false, Look.c("accent2"))
	if route_variant == 0:
		r_walk(Vector3(4.5, y, -174.4))
		r_until(func() -> bool:
			var t: float = Game.course_time
			for s: float in [0.35, 0.6, 0.85, 1.1]:
				if not k1.is_on_at(t + s):
					return false
			for s2: float in [1.2, 1.45, 1.7, 1.95]:
				if not k2.is_on_at(t + s2):
					return false
			return true)
		r_jump(Vector3(4.5, y, -174.4), b1)
		r_jump(_edge(b1, b2, 2.2), b2)
		r_jump(_edge(b2, beam + Vector3(0, 0, -4.1), 2.2), Vector3(beam.x, beam.y, -160.4))
	else:
		r_walk(Vector3(7.6, y, -174.4))
		r_jump(Vector3(7.95, y, -174.4), plank + Vector3(0, 0, -1.2))
		r_portal(plank + Vector3(0, 0, 1.2), pr.exit_point())
	r_until(func() -> bool: return _clear_at(gates, 0.22))
	r_walk(Vector3(beam.x, beam.y, -152.6))
	r_pad(vp, cp17 + Vector3(0, 0, -1.2))
	r_walk(cp17)
	r_checkpoint()
	_net(Vector3(6.0, y - 8.0, -160.0), Vector3(16, 0.6, 36))


# ---- 18. pour line II: wall runs under the high ladles, kick off onto a sprint pad --------------

func _stage_18_pour_run() -> void:
	var y: float = ROOF_Y + 27.2                # 134.6, the CP17 deck
	var drum: float = y + 8.5
	var low: float = y - 7.0
	kit.wallrun(Vector3(-5.0, y + 2.0, -145.25), Vector3(12, 7, 0.5), 0.0)          # W1 x 1 .. -11, face z -145
	kit.wallrun(Vector3(-17.0, y + 3.4, -139.75), Vector3(10, 7, 0.5), 0.0)         # W2 x -12 .. -22, face z -140
	var l5: FoundryLadle = _ladle(Vector3(-3.5, low, -143.6), 2.8, drum - low, 2.4, 0.3, 0.542, 90.0)
	var l6: FoundryLadle = _ladle(Vector3(-7.5, low, -143.6), 2.8, drum - low, 2.4, 0.3, 0.375, 90.0)
	var l7: FoundryLadle = _ladle(Vector3(-17.5, low, -141.4), 2.8, drum - low, 2.4, 0.3, 0.958, 90.0)
	# the high ladle rail along the south face, bracketed to the core
	var rail_y: float = drum + 3.3
	kit.block(Vector3(-9.5, rail_y, -142.5), Vector3(30.0, 0.7, 0.9), Look.c("metal"), false)
	kit.block(Vector3(-9.5, rail_y + 0.55, -142.5), Vector3(30.0, 0.3, 1.4), Look.c("decor"), false)
	kit.glow_strip(Vector3(-9.5, rail_y - 0.4, -142.5), Vector3(30.0, 0.1, 0.2), Look.c("decor2"))
	for xx: float in [-2.0, -12.0, -21.0]:
		kit.block(Vector3(xx, rail_y, -147.3), Vector3(0.8, 0.8, 9.6), Look.c("metal"), false)
	for w: Vector3 in [Vector3(-5.0, y + 5.7, -145.6), Vector3(-17.0, y + 7.1, -139.4)]:
		kit.block(w, Vector3(12.0, 0.4, 0.9), Look.c("metal"), false)
	_slag_pool(Vector3(-10.0, low - 1.0, -143.0), Vector2(26, 8))
	# the kick lands on a sprint pad that fires you round the corner to checkpoint 18
	var vp := Vector3(-26.2, y + 2.6, -146.2)
	kit.disc(vp, 1.4, 0.7, "accent", 1.3)
	kit.pad(vp, 19.0, 0.0, 0.0, 1.1)
	kit.pipe(vp - Vector3(0, 0.8, 0), Vector3(SX - SCORE * 0.5, vp.y - 6.0, -150.0), 0.3)
	var cp18 := Vector3(-30.5, y + 7.0, -155.0)
	kit.plat(cp18, Vector3(5, 1.2, 5), "main", 2.4)
	kit.pillar(cp18 - Vector3(0, 1.2, 0), 1.0, 9.0)
	kit.pipe(cp18 + Vector3(2.0, -1.4, 0), Vector3(SX - SCORE * 0.5, cp18.y - 7.0, -155.0), 0.4)
	_checkpoint(cp18, 0.0, Vector3(-2.1, 0, 2.1))
	r_walk(Vector3(5.4, y, -142.4))
	r_until(func() -> bool: return _clear_at([[l5, 1.1], [l6, 1.5], [l7, 2.5]], 0.15))
	r_wallrun(Vector3(1.6, y, -142.8), Vector3(-2.6, y + 1.2, -144.6), Vector3(-8.6, y, -144.6), Vector3(-14.2, y + 3.0, -140.4))
	r_wallrun(Vector3.ZERO, Vector3(-14.2, y + 3.0, -140.4), Vector3(-18.6, y, -140.4), vp, true, true)
	r_pad(vp, cp18 + Vector3(0, 0, 1.2))
	r_walk(cp18)
	r_checkpoint()
	_net(Vector3(-13.0, y - 9.0, -146.0), Vector3(40, 0.6, 16))


# ---- 19. quench stack: mantle the ingot stack between laser curtains, or bounce into a wall run --

const WALL_CYAN := Color(0.3, 0.9, 1.0)


func _stage_19_quench() -> void:
	var y: float = ROOF_Y + 34.2                # 141.6, the CP18 deck
	var cp18 := Vector3(-30.5, y, -155.0)
	var a := Vector3(-29.4, y + 0.6, -161.4)
	var b := Vector3(-31.4, y + 1.2, -166.2)
	_chain(_edge(cp18, a, 5.0), [a, b], 1.8)
	for p: Vector3 in [a, b]:
		kit.pillar(p - Vector3(0, 1.0, 0), 0.35, 6.0)
	# the fork deck
	var f := Vector3(-26.0, y + 1.6, -175.0)                                             # 143.2
	kit.plat(f, Vector3(9, 1.2, 9), "main", 2.0)                                         # x -30.5 .. -21.5, z -170.5 .. -179.5
	kit.pillar(f - Vector3(0, 1.2, 0), 1.0, 8.0)
	r_jump(_edge(b, f, 1.8), Vector3(-29.0, f.y, -171.6))
	# route 0 (inner lane, gold): mantle the ingot stack; a laser curtain sweeps each top
	var l1 := Vector3(-17.0, f.y + 3.2, -173.0)                                          # 146.4
	var l2 := Vector3(-11.0, f.y + 6.4, -173.0)                                          # 149.6
	kit.ledge(l1, Vector3(3.0, 4.6, 4.0), 0.0, "alt")                                    # x -18.5 .. -15.5
	kit.ledge(l2, Vector3(3.0, 7.8, 4.0), 0.0, "alt")                                    # x -12.5 .. -9.5
	var gates: Array = []
	var eta: Array[float] = [1.25, 2.1]
	var tops: Array[Vector3] = [l1, l2]
	for i: int in 2:
		for h: float in [0.45, 1.3]:
			var g: LaserGate = kit.laser(tops[i] + Vector3(0, h, 0), Vector3(3.6, 0.2, 0.2), 3.0, 0.35, fposmod(-eta[i] / 3.0, 1.0), 90.0)
			gates.append([g, eta[i]])
	# checkpoint 19: a broad ledge both lanes arrive on
	var cp_top := Vector3(-3.0, f.y + 6.4, -175.0)                                       # 149.6
	kit.ledge(cp_top, Vector3(9.0, 7.8, 6.0), 0.0, "main")                               # x -7.5 .. 1.5, z -178 .. -172
	var cp19 := Vector3(-1.5, cp_top.y, -175.0)
	_checkpoint(cp19, -90.0, Vector3(2.0, 0, 2.2))
	# route 1 (outer lane, cyan): sprint over the pad into the tall panel, run it, kick and mantle
	kit.wallrun(Vector3(-13.5, f.y + 4.3, -180.75), Vector3(14, 8, 0.5), 0.0)            # x -20.5 .. -6.5, face z -180.5
	var sp := Vector3(-22.6, f.y, -178.2)
	kit.pad(sp, 16.0, 0.0, 0.0, 0.9)
	kit.glow_strip(Vector3(-25.4, f.y + 0.02, -176.9), Vector3(3.2, 0.04, 0.22), WALL_CYAN, 25.0)
	kit.glow_strip(Vector3(-23.2, f.y + 0.02, -173.0), Vector3(2.4, 0.04, 0.22), LedgeBlock.LIP_COLOR)
	kit.banner(Vector3(-22.2, f.y, -170.9), 3.8, LedgeBlock.LIP_COLOR, 0.0)
	kit.banner(Vector3(-22.2, f.y, -179.3), 3.8, WALL_CYAN, 0.0)
	if route_variant == 0:
		r_walk(Vector3(-25.0, f.y, -173.0))
		r_until(func() -> bool: return _clear_at(gates, 0.4))
		r_mantle(Vector3(-21.9, f.y, -173.0), Vector3(-17.9, l1.y, -173.0))
		r_mantle(Vector3(-15.9, l1.y, -173.0), Vector3(-11.9, l2.y, -173.0))
		r_jump(Vector3(-9.85, l2.y, -173.0), Vector3(-6.0, l2.y, -173.6))
	else:
		r_walk(Vector3(-27.5, f.y, -175.3))
		# chain=true: the run-up crosses the pad, which throws us at the panel mid-air; the kick off
		# the panel flies onto the ledge (mantle) and lands
		r_wallrun(Vector3.ZERO, Vector3(-17.5, f.y + 3.8, -180.1), Vector3(-8.5, f.y + 3.8, -180.1), cp_top + Vector3(-3.0, 0, -1.5), true, true)
	r_walk(cp19)
	r_checkpoint()
	# quench troughs steaming far below, the slag channel they drain into
	_slag_pool(Vector3(-18.0, y - 7.6, -174.0), Vector2(30, 16))
	for sx: float in [-28.0, -18.0, -8.0]:
		FoundryFx.steam(self, Vector3(sx, y - 6.8, -183.5), Vector3.UP, 12, 3.2, 1.8)
		kit.block(Vector3(sx, y - 7.4, -184.5), Vector3(6.0, 1.6, 2.4), Look.c("metal"), false)
		kit.glow_strip(Vector3(sx, y - 6.55, -184.5), Vector3(5.4, 0.05, 1.8), Color(0.35, 0.75, 1.0))
	FoundryFx.embers(self, Vector3(-14.0, y + 4.0, -175.0), Vector3(12.0, 4.0, 5.0), 45)
	FoundryFx.sparks(self, Vector3(-18.5, l1.y - 2.2, -175.1), Vector3(0.3, 0.4, -1), 12, 4.0, 25.0, 0.7)
	_net(Vector3(-28.0, y - 6.0, -163.0), Vector3(10, 0.6, 14))


# ---- 20. hammer lift: ride two forge presses up; mistime a hop and you are under one ---------------

func _stage_20_hammer_lift() -> void:
	var y: float = ROOF_Y + 42.2                # 149.6, the CP19 ledge top
	var cp19 := Vector3(-1.5, y, -175.0)
	var b := Vector3(4.2, y + 0.4, -175.6)      # 150.0
	_blk(b, 1.8)
	kit.pillar(b - Vector3(0, 1.0, 0), 0.4, 7.0)
	# press 1 rests level with the step and lifts 3.4 m; press 2 rests where press 1 tops out
	var f1 := Vector3(8.0, b.y - 1.2, -170.5)
	var f2 := Vector3(8.0, b.y + 2.2, -165.0)
	var p1: Crusher = kit.crusher(f1, Vector3(3.0, 1.2, 3.0), 3.4, 3.0, 0.0)          # x 6.5 .. 9.5, z -172 .. -169
	var p2: Crusher = kit.crusher(f2, Vector3(3.0, 1.2, 3.0), 3.4, 3.0, 0.5)          # z -166.5 .. -163.5
	for fl: Vector3 in [f1, f2]:
		kit.block(fl - Vector3(0, 0.6, 0), Vector3(3.4, 1.2, 3.4), Look.c("metal"))     # the anvil it slams onto
		kit.glow_strip(fl + Vector3(0, 0.02, 0), Vector3(2.4, 0.04, 2.4), Look.c("decor2"))
		kit.pillar(fl - Vector3(0, 1.2, 0), 0.6, 8.0)
	_slam_fx(p1, f1)
	_slam_fx(p2, f2)
	var cp20 := Vector3(8.0, y + 6.4, -157.0)                                           # 156.0
	kit.plat(cp20, Vector3(5, 1.2, 5), "main", 2.4)                                      # z -159.5 .. -154.5
	kit.pillar(cp20 - Vector3(0, 1.2, 0), 1.0, 9.0)
	kit.pipe(cp20 + Vector3(-2.0, -1.4, 0), Vector3(SX + SCORE * 0.5, cp20.y - 8.0, -158.0), 0.4)
	_checkpoint(cp20, 180.0, Vector3(2.1, 0, -2.1))
	r_jump(Vector3(1.15, y, -175.4), b)
	r_until(func() -> bool:
		var u: float = fposmod((Game.course_time + 0.5) / p1.period + p1.phase, 1.0)
		return u > 0.58 and u < 0.8)
	r_jump_onto(_edge(b, f1, 1.8), p1, Vector3(0, 0.6, 0))
	r_until(func() -> bool:
		var t: float = Game.course_time
		var u1: float = fposmod(t / p1.period + p1.phase, 1.0)
		var u2: float = fposmod((t + 0.45) / p2.period + p2.phase, 1.0)
		return u1 < 0.3 and u2 > 0.58 and u2 < 0.8)
	r_jump_onto(Vector3(8.0, f1.y + 4.6, -169.4), p2, Vector3(0, 0.6, 0))
	r_until(func() -> bool: return fposmod(Game.course_time / p2.period + p2.phase, 1.0) < 0.3)
	r_jump(Vector3(8.0, f2.y + 4.6, -163.85), cp20 + Vector3(0, 0, -1.4))
	r_walk(cp20)
	r_checkpoint()
	# SHORTCUT: the tall anvil. A running mantle from the step (4.1 m) skips the first press.
	kit.ledge(Vector3(3.6, b.y + 4.1, -170.0), Vector3(2.4, 5.2, 2.4), 0.0, "alt")      # x 2.4 .. 4.8, z -171.2 .. -168.8
	kit.glow_strip(Vector3(3.6, b.y + 0.02, -174.5), Vector3(0.22, 0.04, 0.9), LedgeBlock.LIP_COLOR)
	FoundryFx.embers(self, Vector3(7.0, y + 3.0, -166.0), Vector3(4.0, 4.0, 7.0), 40)
	_net(Vector3(5.0, y - 6.0, -166.0), Vector3(14, 0.6, 24))


# ---- 21. crown pour: a beam under the crown ladles, a wall run, kick and mantle onto the crown -------

func _stage_21_crown() -> void:
	var cp20 := Vector3(8.0, ROOF_Y + 48.6, -157.0)     # 156.0
	var k1 := Vector3(7.0, cp20.y - 1.2, -150.6)           # 154.8
	var d1 := Vector3(5.0, cp20.y - 3.0, -145.0)           # 153.0
	_blk(k1, 1.8)
	kit.pillar(k1 - Vector3(0, 1.0, 0), 0.4, 7.0)
	kit.plat(d1, Vector3(6, 1.0, 4.4), "main", 1.4)                                      # x 2 .. 8, z -147.2 .. -142.8
	kit.pillar(d1 - Vector3(0, 1.0, 0), 0.8, 8.0)
	r_jump(_edge(cp20, k1, 5.0), k1)
	r_jump(_edge(k1, d1, 1.8), d1 + Vector3(0.5, 0, -1.0))
	# the pour beam: two crown ladles tip across it
	var beam := Vector3(-4.0, d1.y, -145.0)
	kit.plat(beam, Vector3(12.0, 0.8, 1.0), "main", 1.0)                                  # x -10 .. 2
	kit.pillar(beam - Vector3(0, 0.8, 0), 0.4, 7.0)
	var drum: float = d1.y + 8.0
	var etas: Array[float] = [0.6, 1.25]
	var lx: Array[float] = [-1.0, -6.5]
	var ladles: Array = []
	for i: int in 2:
		var l: FoundryLadle = _ladle(Vector3(lx[i], d1.y, -145.0), 2.4, drum - d1.y, 2.6, 0.35, fposmod(-etas[i] / 2.6, 1.0), 90.0)
		ladles.append([l, etas[i]])
	var rail_y: float = drum + 3.3
	kit.block(Vector3(-4.0, rail_y, -145.0), Vector3(14.0, 0.7, 0.9), Look.c("metal"), false)
	kit.block(Vector3(-4.0, rail_y + 0.55, -145.0), Vector3(14.0, 0.3, 1.4), Look.c("decor"), false)
	kit.glow_strip(Vector3(-4.0, rail_y - 0.4, -145.0), Vector3(14.0, 0.1, 0.2), Look.c("decor2"))
	# the rail hangs from two brackets standing on the crown's south rim
	for xx: float in [-10.0, -2.8]:
		kit.block(Vector3(xx, rail_y, -148.2), Vector3(0.8, 0.8, 6.4), Look.c("metal"), false)
		kit.block(Vector3(xx, (S_TOP + rail_y) * 0.5, -151.0), Vector3(0.7, rail_y - S_TOP + 0.4, 0.7), Look.c("metal"))
	_slag_pool(Vector3(-8.0, d1.y - 9.0, -146.0), Vector2(26, 8))
	# the last wall run, and the crown's south lip with a press over it
	kit.wallrun(Vector3(-18.0, d1.y + 1.3, -143.35), Vector3(14, 7, 0.5), 0.0)            # x -25 .. -11, face z -143.6
	var m := Vector3(-18.0, S_TOP, -148.5)
	kit.ledge(m, Vector3(10.0, 3.0, 3.0), 0.0, "alt")                                    # x -23 .. -13, z -150 .. -147
	var cm: Crusher = kit.crusher(Vector3(-20.5, S_TOP, -148.5), Vector3(3.0, 1.2, 2.4), 3.2, 2.6, 0.34)
	_slam_fx(cm, Vector3(-20.5, S_TOP, -148.5))
	var cp21 := Vector3(-19.5, S_TOP, -153.5)
	_checkpoint(cp21, -90.0, Vector3(-1.6, 0, -2.2))
	r_walk(Vector3(3.0, d1.y, -145.0))
	r_until(func() -> bool: return _clear_at(ladles, 0.2) and cm.is_clear_for(Game.course_time + 2.2, 1.3))
	r_wallrun(Vector3(-9.7, d1.y, -145.0), Vector3(-14.0, d1.y + 1.2, -144.0), Vector3(-17.5, d1.y + 1.2, -144.0), Vector3(-20.5, S_TOP, -149.0))
	r_walk(Vector3(-19.5, S_TOP, -151.8))
	r_walk(cp21)
	r_checkpoint()
	_net(Vector3(-8.0, d1.y - 6.0, -146.0), Vector3(36, 0.6, 12))
	# SHORTCUT: the lip panel. Run it past the pours and kick straight across onto the last wall run.
	kit.wallrun(Vector3(-4.5, d1.y + 1.3, -147.75), Vector3(9, 7, 0.5), 0.0)             # x -9 .. 0, face z -147.5
	kit.glow_strip(Vector3(3.2, d1.y + 0.02, -146.75), Vector3(1.6, 0.04, 0.22), WALL_CYAN, 0.0)


# ---- 22. crown stack: hop the crown sweeper, bounce into a wall-run zig-zag, mantle the stack ----

func _stage_22_stack() -> void:
	var cp21 := Vector3(-19.5, S_TOP, -153.5)
	# the crucible sweeper on the crown deck
	var swc := Vector3(-12.5, S_TOP, -154.5)
	var sw: Sweeper = kit.sweeper(swc, 4.0, 2, 3.6, 0.0, 0.45)
	kit.glow_strip(swc + Vector3(0, 0.02, 0), Vector3(1.4, 0.04, 1.4), Look.c("decor2"), 45.0)
	FoundryFx.motes(self, swc + Vector3(0, 0.6, 0), Vector3(3.0, 0.4, 3.0), 24)
	# panel A along the crown's east rim, panel B hung off its north edge, the stack beyond
	kit.wallrun(Vector3(-3.25, S_TOP + 4.0, -162.0), Vector3(12, 8, 0.5), 90.0)           # z -168 .. -156, face x -3.5
	kit.wallrun(Vector3(-6.85, S_TOP + 7.5, -171.5), Vector3(7, 8, 0.5), 90.0)            # z -175 .. -168, face x -6.6
	kit.block(Vector3(-6.85, S_TOP + 11.8, -171.5), Vector3(0.9, 0.6, 7.4), Look.c("metal"), false)
	kit.pipe(Vector3(-6.85, S_TOP + 11.8, -168.2), Vector3(-9.0, S_TOP, -165.0), 0.25)
	var pad := Vector3(-5.36, S_TOP, -157.4)
	kit.pad(pad, 16.0, 0.0, 0.0, 0.9)
	var st := Vector3(-3.5, S_TOP + 10.0, -178.0)                                          # 168
	kit.ledge(st, Vector3(6.0, 8.0, 6.0), 0.0, "main")                                    # x -6.5 .. -0.5, z -181 .. -175
	kit.block(Vector3(-3.5, S_TOP + 1.4, -172.0), Vector3(2.0, 1.2, 7.6), Look.c("metal"))  # girder back to the crown
	kit.pipe(Vector3(-3.5, st.y - 8.5, -178.0), Vector3(-6.0, st.y - 20.0, SZ - SCORE * 0.5 + 1.0), 0.6)
	kit.chimney(Vector3(-1.4, st.y, -180.0), 4.0, 0.8)
	kit.chimney(Vector3(-5.6, st.y, -180.2), 3.0, 0.6, false)
	var fin := Vector3(-3.5, st.y, -177.6)
	kit.finish(fin, 0.0)
	r_walk(Vector3(-17.2, S_TOP, -155.0))
	route.append({"kind": "b_sweep", "to": Vector3(-6.0, S_TOP, -155.0), "sweeper": sw})
	# the run-up crosses the pad (chain=true: latch A in the air), kick to B, kick onto the stack
	r_wallrun(Vector3.ZERO, Vector3(-4.0, S_TOP + 4.2, -162.5), Vector3(-4.0, S_TOP + 4.2, -166.5), Vector3(-6.2, S_TOP + 7.0, -169.5), true, true)
	r_wallrun(Vector3.ZERO, Vector3(-6.2, S_TOP + 7.0, -169.5), Vector3(-6.2, S_TOP + 7.0, -173.0), fin + Vector3(-1.0, 0, 1.4), true, true)
	r_walk(fin)
	# the finish: fireworks on arrival, spark fountains round the crown
	var fb1: GPUParticles3D = FoundryFx.burst(90, 12.0)
	var fb2: GPUParticles3D = FoundryFx.glitter(70, 9.0, Look.c("accent2"))
	var fb3: GPUParticles3D = FoundryFx.glitter(50, 7.0, FoundryFx.EMBER)
	FoundryFx.near_burst(self, fin + Vector3(0, 1.0, 0), 3.0, [fb1, fb2, fb3], 1.2)
	for c: Vector3 in [Vector3(-20.5, 0, -168.5), Vector3(-13.0, 0, -168.8), Vector3(-21.0, 0, -160.0)]:
		kit.chimney(Vector3(c.x, S_TOP, c.z), 2.5, 0.7, false)
		FoundryFx.sparks(self, Vector3(c.x, S_TOP + 2.7, c.z), Vector3.UP, 26, 7.0, 14.0, 1.1)
	FoundryFx.rising_sparks(self, Vector3(-1.4, st.y + 4.3, -180.0), Vector3(0.4, 0.2, 0.4), 24, 4.0)
	FoundryFx.embers(self, Vector3(-8.0, S_TOP + 5.0, -168.0), Vector3(8.0, 5.0, 10.0), 50)
	kit.lamp(Vector3(-6.5, S_TOP, -151.0), 3.0)
	kit.lamp(Vector3(-20.0, S_TOP, -165.0), 3.0, false)
	kit.banner(Vector3(-2.6, S_TOP, -155.4), 3.6, WALL_CYAN, 0.0)
	# (kept 5 m above checkpoint 19's ledge below: hops there peak 2.5 m up)
	_net(Vector3(-6.0, S_TOP - 3.0, -176.5), Vector3(12, 0.6, 13))


func _build_ambient_fx() -> void:
	# embers rising round the old tower, ash drifting down the whole course (two layers)
	for yy: float in [4.0, 24.0, 44.0, 64.0, 86.0]:
		FoundryFx.embers(self, Vector3(0, yy, OZ - 10.0), Vector3(20.0, 7.0, 22.0), 50)
	for yy2: float in [20.0, 60.0, 100.0, 140.0]:
		FoundryFx.ash(self, Vector3(-6.0, yy2, -95.0), Vector3(40.0, 14.0, 70.0), 70)
	# the furnace core shimmers
	FoundryFx.motes(self, Vector3(0, (GLOW_LO + GLOW_HI) * 0.5, OZ), Vector3(7.0, 13.0, 7.0), 40)
	FoundryFx.rising_sparks(self, Vector3(-5.2, ROOF_Y + 8.2, OZ + 5.2), Vector3(0.5, 0.2, 0.5), 24, 4.0)
	FoundryFx.rising_sparks(self, Vector3(5.6, ROOF_Y + 10.2, OZ + 4.6), Vector3(0.5, 0.2, 0.5), 24, 4.0)
	# the pour line and the Smelter: embers climbing round it
	FoundryFx.embers(self, Vector3(0, ROOF_Y + 4.0, -90.0), Vector3(6.0, 5.0, 40.0), 60)
	for yy3: float in [112.0, 128.0, 144.0]:
		FoundryFx.embers(self, Vector3(SX, yy3, SZ), Vector3(24.0, 7.0, 24.0), 60)
	for c2: Vector3 in [Vector3(SX - 11.0, 96.0, SZ - 11.0), Vector3(SX + 11.0, 96.0, SZ + 11.0)]:
		FoundryFx.rising_sparks(self, c2, Vector3(3.0, 0.5, 3.0), 30, 6.0)


func _build_surroundings() -> void:
	kit.cloud_field(Vector3(0, -34, OZ), Vector3(150, 8, 150), 30)
	kit.cloud_field(Vector3(0, 130, OZ), Vector3(170, 10, 170), 8)
	kit.monolith_ring(Vector3(0, 30, OZ), 120.0, 180.0, 20, 45.0)
	for spot: Vector3 in [Vector3(-52, -6, -18), Vector3(50, 4, -12), Vector3(-56, 30, -76), Vector3(54, 40, -80), Vector3(-6, 8, -112)]:
		var s: float = kit.rng.randf_range(7.0, 10.0)
		kit.plat(spot, Vector3(s, 2.5, s), "alt")
		kit.block(spot + Vector3(0, 2.5, 0), Vector3(s * 0.55, 5.0, s * 0.55), Look.c("decor"), false)
		kit.glow_strip(spot + Vector3(0, 3.2, 0), Vector3(s * 0.57, 0.3, s * 0.57), Look.c("decor2"))
		kit.chimney(spot + Vector3(s * 0.22, 5.0, -s * 0.1), kit.rng.randf_range(8.0, 14.0), 1.1)
		kit.chimney(spot + Vector3(-s * 0.3, 0.0, s * 0.32), kit.rng.randf_range(5.0, 8.0), 0.8, false)
		# feed pipe dives steeply to the tower base, well below the course
		kit.pipe(spot + Vector3(0, -2.0, 0), Vector3(0, maxf(spot.y - 45.0, -15.0), OZ), 0.6, Look.c("decor"))
