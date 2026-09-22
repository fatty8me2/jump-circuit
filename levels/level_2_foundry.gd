extends LevelBase
## 2. BOUNCE FOUNDRY (hard mode) - a brutal vertical obby wound two and a half times
## around a floating furnace tower. Bounce physics and carried momentum rule:
## vertical pads KEEP the speed you bring, angled pads REPLACE it with their arc.
##
## Stages (each ends on a checkpoint):
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
## Set piece: the Crucible (nine bounces). Shortcuts: the red sprint pad after checkpoint 1,
## the hammer ride from checkpoint 4.

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
	_build_surroundings()


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

	# --- roof + finish -----------------------------------------------------------------------
	kit.plat(Vector3(0, ROOF_Y, OZ), Vector3(14, 2, 14), "goal", 0.0)
	kit.block(Vector3(0, ROOF_Y - 2.6, OZ), Vector3(12, 1.2, 12), Look.c("metal"), false)
	kit.finish(Vector3(3.2, ROOF_Y, OZ + 3.2), 45.0)
	kit.chimney(Vector3(-5.2, ROOF_Y, OZ + 5.2), 8.0, 1.0)
	kit.chimney(Vector3(5.4, ROOF_Y, OZ - 5.2), 10.0, 1.1)
	kit.lamp(Vector3(6.2, ROOF_Y, OZ + 6.2), 3.0, false)
	# beacon so the goal can be found from the yard
	kit.glow_strip(Vector3(5.2, ROOF_Y + 16.0, OZ + 5.2), Vector3(0.5, 32.0, 0.5), Look.c("accent2"))
	kit.ring(Vector3(5.2, ROOF_Y + 12.0, OZ + 5.2), 2.4, Look.c("accent2"), Vector3.ZERO, 9.0)
	kit.ring(Vector3(5.2, ROOF_Y + 19.0, OZ + 5.2), 1.7, Look.c("accent2"), Vector3.ZERO, -7.0)
	kit.ring(Vector3(5.2, ROOF_Y + 25.0, OZ + 5.2), 1.1, Look.c("accent2"), Vector3.ZERO, 5.0)
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
	_cwait(3.0, 0.7, 0.8, 0.0)
	r_pad(c5, bl)
	r_jump(_edge(bl, c6, 3.0), c6)
	r_pad(c6, c7)
	r_pad(c7, c8)
	r_pad(c8, c9)
	r_pad(c9, roof_land)
	r_walk(Vector3(3.2, roof_y, OZ + 3.2))
	var chain2: Array[Vector3] = [c5, bl, c6, c7, c8, c9]
	for i: int in chain2.size() - 1:
		_net_under(chain2[i], chain2[i + 1])
	_net_under(c9, Vector3(-9.0, c9.y, OZ))


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
		kit.pipe(spot + Vector3(0, -2.0, 0), Vector3(0, maxf(spot.y - 20.0, -15.0), OZ), 0.6, Look.c("decor"))
