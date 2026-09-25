extends LevelBase
## 7. XENO WILDS - an alien planet. A bioluminescent jungle on a low-gravity moon: a colossal ringed
## gas giant fills the sky, two suns (teal and amber) sit low, auroras ribbon overhead, and the course
## climbs through glowing fungi, crystal caverns, acid geysers and the bones of a titan to a black
## monolith. Eighteen stages: seventeen end on a checkpoint, the last at the finish.
##
##  1 Landing Site     warm-up hops, the first breathing spore cap   [shortcut: mantle the crystal pillar]
##  2 Spore Garden     time two breathing caps (big bounce at the swell), MANTLE the shelf fungus
##  3 Vine Ravine      WALL RUN the glowing vine cliff over the gap, root beams in a spore wind
##  4 Snapjaw Alley    run the bridge through two SNAPJAWS between snaps, ride a lily pad over acid
##  5 Geyser Terraces  ride an acid GEYSER's steam up (out before it turns lime), slip an acid jet,
##                     ride a second geyser into a MANTLE
##  6 Crystal Caverns  FORK: a 1.2 m beam through three crystal-arc LASER fences | two MANTLES and a
##                     WALL RUN along the crystal face
##  7 Drift Well       low gravity round a humming monolith: board an orbiting drift stone, ride it,
##                     float off to a floating rock and on to the far ledge
##  8 Titan's Spine    vertebra hops over an acid lake, spine catwalks swept by bone rams (PISTONS),
##                     MANTLE the skull                     [shortcut: WALL RUN the great rib]
##  9 Snapjaw Gauntlet FORK: three SNAPJAWS on a broken bridge | a rising chain of spore caps
## 10 Leviathan Crossing  SET PIECE: board a sky leviathan as it glides past the pier, ride its back
##                     across the chasm, leap off at the far pier
## 11 Bloom Marsh      blooming pads (blink) over the acid marsh, a lashing vine whip (sweeper), then the
##                     bloom PORTAL - the only way over the wide acid lake
## 12 Hollow Tree      three WALL RUNS zig-zag up inside a giant hollow trunk, MANTLE out of the last kick
## 13 Stomper Grove    run under a stomper mushroom (CRUSHER), MANTLE up under another, two more
##                                                          [shortcut: the stalk hop]
## 14 Geyser Field     FORK: ride a geyser over an acid jet | a boost strip into an 18 m/s WALL RUN
## 15 Crystal Lattice  beam walk under a crystal LASER, blooming pads, a beam where two lasers and an
##                     acid jet keep one beat         [shortcut: the bloom PORTAL on a 1 m knob]
## 16 Floating Isles   a boost strip flings you across the void, a breathing cap bounces you into a MANTLE
##                                                          [shortcut: hidden PORTAL under the checkpoint]
## 17 The Maw          a snapjaw, a bone-ram catwalk, a geyser lift and a MANTLE
## 18 Monolith Summit  WALL RUN the monolith, kick onto a breathing cap, bounce into a MANTLE, the last
##                     snapjaw and the finish beneath the gas giant
##
## Xeno mechanics (own scripts, mechanics/xeno_*.gd): XenoSporeCap (breathing bounce caps), XenoSnapjaw
## (flytrap horizontal crushers), XenoGeyser (steam lifts, acid burns), XenoDriftWell (low-g monolith
## field), XenoLeviathan (the rideable sky creature), XenoAcidPool (acid pools). Visual: visual/xeno_*.
## Route variants for the bot: 0 = main line, 1 = every alternative branch, 2 = main line + every shortcut.

const GROUND_SHADER: Shader = preload("res://visual/xeno_ground.gdshader")
const AURORA_SHADER: Shader = preload("res://visual/xeno_aurora.gdshader")

var _o: Vector3 = Vector3.ZERO
var _b: Basis = Basis.IDENTITY
var _yaw: float = 0.0
var _next_yaw: float = 0.0
var flora: XenoFlora
var _env: Environment
var _sun: DirectionalLight3D
var _sun2: DirectionalLight3D
## World-space checkpoint positions in build order (for set dressing along the route).
var _cp_world: Array[Vector3] = []
var _cp_bursts: Dictionary = {}
var _finish_pos: Vector3 = Vector3.ZERO
## Portal arrivals: [exit_world, [bursts]] fired on teleport.
var _portal_bursts: Array[Array] = []
## Crushers dressed as stomper mushrooms: [crusher, spore puff, was_down].
var _stomps: Array[Array] = []


func _configure() -> void:
	theme_id = "xeno"
	music_track = "xeno"
	kill_y = -80.0
	# 0 = main line, 1 = every alternative branch, 2 = main line taking every optional shortcut
	route_variants = 3


# ---- local-frame helpers --------------------------------------------------------------------

func _frame(origin: Vector3, yaw_deg: float) -> void:
	_o = origin
	_yaw = yaw_deg
	_b = Basis(Vector3.UP, deg_to_rad(yaw_deg))


func _w(l: Vector3) -> Vector3:
	return _o + _b * l


## A local size (x across, z along) turned into world axes (frames only turn in 90 degree steps).
func _sz(size: Vector3) -> Vector3:
	return Vector3(size.z, size.y, size.x) if absf(fmod(absf(_yaw), 180.0) - 90.0) < 1.0 else size


func _area(c: Vector3, hx: float, hz: float) -> Dictionary:
	return {"c": c, "hx": hx, "hz": hz}


## Walkable block. `under`: "stalk" (a fungal column down to the jungle), "keel" (a floating stone
## with dangling glowing roots) or "" (nothing).
func _blk(c: Vector3, sx: float, sz: float, style: String = "main", thick: float = 1.0, under: String = "keel") -> Dictionary:
	var keel: float = -1.0 if under == "keel" else 0.0
	var body: StaticBody3D = kit.plat(_w(c), Vector3(sx, thick, sz), style, keel, _yaw)
	if under == "stalk":
		flora.stalk(_w(c - Vector3(0, thick, 0)), clampf(minf(sx, sz) * 0.3, 0.35, 1.6), kit.rng.randf_range(28.0, 44.0))
	elif under == "keel":
		flora.roots(_w(c - Vector3(0, thick + clampf(minf(sx, sz) * 0.55, 1.2, 6.0) * 0.6, 0)), minf(sx, sz) * 0.25, 3)
	return {"c": c, "hx": sx * 0.5, "hz": sz * 0.5, "node": body}


func _disc(c: Vector3, r: float, style: String = "main", thick: float = 0.8, under: String = "stalk") -> Dictionary:
	var body: StaticBody3D = kit.disc(_w(c), r, thick, style, -1.0 if under == "keel" else 0.0)
	if under == "stalk":
		flora.stalk(_w(c - Vector3(0, thick, 0)), clampf(r * 0.45, 0.4, 1.8), kit.rng.randf_range(28.0, 44.0))
	return {"c": c, "r": r, "node": body}


func _ledge(top: Vector3, size: Vector3, style: String = "main") -> Dictionary:
	kit.ledge(_w(top), size, _yaw, style)
	return {"c": top, "hx": size.x * 0.5, "hz": size.z * 0.5}


## Takeoff spot on `a`: on the line toward `toward`, `inset` metres inside the edge.
func _edge(a: Dictionary, toward: Vector3, inset: float = 0.35) -> Vector3:
	var c: Vector3 = a["c"]
	var d := Vector3(toward.x - c.x, 0, toward.z - c.z).normalized()
	if a.has("r"):
		return c + d * (float(a["r"]) - inset)
	var tx: float = INF if absf(d.x) < 0.001 else (float(a["hx"]) - inset) / absf(d.x)
	var tz: float = INF if absf(d.z) < 0.001 else (float(a["hz"]) - inset) / absf(d.z)
	return c + d * minf(tx, tz)


## Route a jump from the edge of `a` to the middle of `b` (+ offset). speed > 0 marks a momentum jump.
func _hop(a: Dictionary, b: Dictionary, off: Vector3 = Vector3.ZERO, hold: bool = true, speed: float = 0.0) -> void:
	var to: Vector3 = (b["c"] as Vector3) + off
	r_jump(_w(_edge(a, to)), _w(to), hold)
	if speed > 0.0:
		route[route.size() - 1]["speed"] = speed


## A floaty jump inside a drift well: a jump step the reach validator skips (moon-gravity reach).
func _float(from: Vector3, to: Vector3) -> void:
	route.append({"kind": "b_jump", "from": _w(from), "to": _w(to), "hold": true})


## Kill brick dressed as a cluster of red thorn pods (the game's hazard red, but grown, not built).
func _haz(c: Vector3, size: Vector3, yaw_extra: float = 0.0) -> void:
	kit.hazard(_w(c), size, _yaw + yaw_extra)
	var thorn: StandardMaterial3D = Look.flat(Color(1.0, 0.22, 0.18), 0.4, 0.0, 1.6)
	var n: int = maxi(int(maxf(size.x, size.z) / 0.8), 1)
	var along: Vector3 = _b * Basis(Vector3.UP, deg_to_rad(yaw_extra)) * (Vector3(1, 0, 0) if size.x >= size.z else Vector3(0, 0, 1))
	for i: int in n:
		var f: float = (float(i) + 0.5) / float(n) - 0.5
		var p: Vector3 = _w(c) + along * f * maxf(size.x, size.z) + Vector3(0, size.y * 0.5, 0)
		for k: int in 3:
			var a: float = TAU * float(k) / 3.0 + float(i)
			var sp := Look.cylinder(0.09, 0.7, thorn, p + Vector3(cos(a) * 0.15, 0.2, sin(a) * 0.15), 0.0, 5)
			sp.rotation = Vector3(sin(a) * 0.5, 0, -cos(a) * 0.5)
			add_child(sp)


## Kill brick just past block `b`, square to the arrival direction from `a` (punishes overshoot).
func _thorns_behind(a: Dictionary, b: Dictionary, width: float = 1.6) -> void:
	var ca: Vector3 = a["c"]
	var cb: Vector3 = b["c"]
	var d := Vector3(cb.x - ca.x, 0, cb.z - ca.z).normalized()
	var half: float = minf(float(b["hx"]) / maxf(absf(d.x), 0.001), float(b["hz"]) / maxf(absf(d.z), 0.001))
	var yaw_local: float = rad_to_deg(atan2(-d.x, -d.z))
	_haz(cb + d * (half + 0.55) + Vector3(0, 0.55, 0), Vector3(width, 1.5, 0.5), yaw_local)


func _wind(c: Vector3, size: Vector3, push: Vector3, max_rise: float = 14.0) -> WindZone:
	return kit.wind(_w(c), _sz(size), _b * push, max_rise)


## Checkpoint platform facing the next stage's heading (_next_yaw), ringed with little glowing fungi.
func _cp(c: Vector3, size: float = 6.0, under: String = "stalk") -> Dictionary:
	var d: Dictionary = _blk(c, size, size, "main", 1.4, under)
	var cp: Checkpoint = kit.checkpoint(_w(c), _next_yaw)
	_cp_world.append(_w(c))
	var h: float = size * 0.5 - 0.5
	flora.shroom_patch(_w(c + Vector3(-h, 0, h)), 1.0)
	flora.shroom_patch(_w(c + Vector3(h, 0, h)), 0.9)
	flora.crystals(_w(c + Vector3(-h, 0, -h)), 0.55)
	flora.tendril(_w(c + Vector3(h, 0, -h)), 2.6)
	for side: float in [-1.0, 1.0]:
		flora.pods(_w(c + Vector3(side * (size * 0.5 + 0.2), -0.9, kit.rng.randf_range(-h, h))), 1.0)
	# banked-stage feedback: a fountain of spores and glints
	var burst: GPUParticles3D = XenoFx.burst(XenoFlora.TEAL, 44, 7.0, 0.22)
	burst.position = _w(c) + Vector3(0, 0.3, 0)
	add_child(burst)
	var glints: GPUParticles3D = XenoFx.burst(XenoFlora.MAGENTA, 30, 5.0, 0.3)
	glints.position = _w(c) + Vector3(0, 0.6, 0)
	add_child(glints)
	_cp_bursts[cp] = [burst, glints]
	cp.reached.connect(func(which: Checkpoint) -> void:
		if which.index > current_checkpoint:
			for p: GPUParticles3D in _cp_bursts[which]:
				p.restart()
				p.emitting = true)
	return d


## Breathing spore cap at local `c` (top of cap).
func _cap(c: Vector3, low: float, high: float, period: float = 3.0, phase: float = 0.0, r: float = 1.4, stalk: float = 6.0, tint: Color = Color(0, 0, 0, 0)) -> XenoSporeCap:
	var cap := XenoSporeCap.new()
	cap.low = low
	cap.high = high
	cap.period = period
	cap.phase = phase
	cap.radius = r
	cap.stalk = stalk
	cap.tint = tint if tint.a > 0.0 else [XenoFlora.MAGENTA, XenoFlora.VIOLET, XenoFlora.CYAN][kit.rng.randi() % 3]
	cap.position = _w(c)
	add_child(cap)
	return cap


## Snapjaw across the path at local floor point `c` (the path runs along the stage heading).
func _jaw(c: Vector3, width: float = 3.0, length: float = 3.2, period: float = 3.0, phase: float = 0.0, lobe: float = 3.0) -> XenoSnapjaw:
	var j := XenoSnapjaw.new()
	j.width = width
	j.length = length
	j.lobe = lobe
	j.period = period
	j.phase = phase
	j.position = _w(c)
	j.rotation.y = deg_to_rad(_yaw)
	add_child(j)
	return j


## Acid geyser at local floor point `c`.
func _geyser(c: Vector3, height: float, period: float, phase: float, lift: float = 0.42, acid: float = 0.18, width: float = 2.4) -> XenoGeyser:
	var g := XenoGeyser.new()
	g.size = Vector3(width, height, width)
	g.period = period
	g.phase = phase
	g.lift = lift
	g.acid = acid
	g.position = _w(c)
	add_child(g)
	return g


## Acid pool whose surface centre is local `c` (size = local width x depth).
func _acid(c: Vector3, size: Vector2, keel: float = 5.0, rim: bool = true) -> XenoAcidPool:
	var a := XenoAcidPool.new()
	a.size = size
	a.rim = rim
	a.keel = keel
	a.position = _w(c)
	a.rotation.y = deg_to_rad(_yaw)
	add_child(a)
	return a


## Wall-run panel along the stage heading at local x, from z0 to z1 (z0 > z1), centred at height y.
func _panel(x: float, y: float, z0: float, z1: float, height: float = 7.0) -> WallRunPanel:
	return kit.wallrun(_w(Vector3(x, y, (z0 + z1) * 0.5)), Vector3(absf(z0 - z1), height, 0.5), _yaw + 90.0)


## Living wall behind a wall-run panel (decor): dark bark, glowing vine runners and fungus shelves.
func _vine_wall(x: float, y0: float, y1: float, z0: float, z1: float, side: float, color: Color = XenoFlora.TEAL) -> void:
	var len: float = absf(z0 - z1)
	var bark: StandardMaterial3D = Look.flat(Color(0.2, 0.13, 0.24), 0.9)
	var vine: StandardMaterial3D = Look.flat(color, 0.4, 0.0, 1.8)
	var shelf: StandardMaterial3D = Look.flat(Color(0.9, 0.7, 0.5), 0.7, 0.0, 0.4)
	var n := Node3D.new()
	var h: float = y1 - y0
	n.add_child(Look.box(Vector3(0.6, h, len), bark, Vector3(side * 0.25, (y0 + y1) * 0.5, 0)))
	for i: int in 4:
		var yy: float = y0 + h * (0.2 + 0.2 * float(i))
		var v := Look.box(Vector3(0.1, 0.12, len * 0.96), vine, Vector3(-side * 0.08, yy + sin(float(i) * 2.1) * 0.4, 0))
		v.rotation.x = 0.04 * sin(float(i) * 1.7)
		v.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(v)
	for i: int in int(len / 4.0):
		var z: float = -len * 0.5 + 2.0 + float(i) * 4.0
		var s := Look.sphere(0.6, shelf, Vector3(-side * 0.1, y1 - 0.8 - float(i % 2) * 1.5, z))
		s.scale = Vector3(0.9, 0.25, 1.0)
		n.add_child(s)
	n.position = _w(Vector3(x, 0, (z0 + z1) * 0.5))
	n.rotation_degrees.y = _yaw
	add_child(n)


## A crystal-arc fence: stacked laser beams leaping between two glowing crystal clusters.
## `c` = floor centre (local), beams at `heights` above it.
func _arc_fence(c: Vector3, width: float, heights: Array, period: float, on: float, phase: float) -> LaserGate:
	var first: LaserGate = null
	for h: float in heights:
		var g: LaserGate = kit.laser(_w(c + Vector3(0, h, 0)), Vector3(width, 0.22, 0.22), period, on, phase, _yaw)
		if first == null:
			first = g
	for sx: float in [-1.0, 1.0]:
		var post: Vector3 = c + Vector3(sx * (width * 0.5 + 0.45), 0, 0)
		flora.crystals(_w(post + Vector3(0, -0.3, 0)), 0.8, XenoFlora.CYAN)
		var sp: GPUParticles3D = Fx.emitter({"amount": 12, "lifetime": 0.5, "shape": "box", "extents": Vector3(0.4, 1.2, 0.4),
			"speed": Vector2(1.5, 4.0), "spread": 180.0, "damping": Vector2(6.0, 9.0), "tex": Fx.Tex.DOT, "size": 0.12,
			"color": Fx.hot(Color(0.5, 0.9, 1.0), 2.4), "aabb": AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6)), "preprocess": 0.5})
		sp.position = _w(post + Vector3(0, 1.4, 0))
		add_child(sp)
	return first


## A root ram: a piston whose ram is a gnarled root with a horned bone tip, bursting out of a burrow.
func _ram(top: Vector3, size: Vector3, yaw_extra: float, stroke: float, period: float, phase: float, strength: float = 10.0) -> Piston:
	var p: Piston = kit.piston(_w(top), size, _yaw + yaw_extra, stroke, period, phase, strength)
	var horn: StandardMaterial3D = Look.flat(Color(0.9, 0.86, 0.74), 0.6)
	var glow: StandardMaterial3D = Look.flat(XenoFlora.AMBER, 0.4, 0.0, 1.6)
	for sx: float in [-1.0, 1.0]:
		var h := Look.cylinder(0.14, 0.9, horn, Vector3(sx * size.x * 0.3, size.y * 0.1, -size.z * 0.5 - 0.3), 0.02, 6)
		h.rotation.x = -PI * 0.5
		p.add_child(h)
	p.add_child(Look.sphere(0.12, glow, Vector3(0, size.y * 0.25, -size.z * 0.5 - 0.02)))
	return p


## A stomper mushroom: a crusher whose press is a huge fleshy cap slamming down on a stalk.
func _stomper(c: Vector3, size: Vector3, lift: float, period: float, phase: float, tint: Color = XenoFlora.MAGENTA) -> Crusher:
	var cr: Crusher = kit.crusher(_w(c), size, lift, period, phase, _yaw)
	var sz: Vector3 = size
	var cap_mat: StandardMaterial3D = Look.flat(tint.darkened(0.4), 0.5, 0.0, 0.4)
	var spot: StandardMaterial3D = Look.flat(Color(1.0, 0.95, 0.85), 0.3, 0.0, 1.6)
	var dome := Look.sphere(1.0, cap_mat, Vector3(0, sz.y * 0.5 - 0.2, 0))
	dome.scale = Vector3(sz.x * 0.72, 1.3, sz.z * 0.72)
	cr.add_child(dome)
	for i: int in 6:
		var a: float = TAU * float(i) / 6.0
		var s := Look.sphere(0.22, spot, Vector3(cos(a) * sz.x * 0.4, sz.y * 0.5 + 0.55, sin(a) * sz.z * 0.4))
		s.scale = Vector3(1.0, 0.5, 1.0)
		cr.add_child(s)
	cr.add_child(Look.cylinder(0.5, 3.0, Look.flat(Color(0.8, 0.74, 0.9), 0.8), Vector3(0, sz.y * 0.5 + 2.0, 0), 0.35, 10))
	# spores puffed out from under the cap when it slams
	var puff: GPUParticles3D = Fx.smoke({"amount": 30, "lifetime": 1.2, "shape": "ring", "ring_radius": maxf(sz.x, sz.z) * 0.6,
		"ring_inner": maxf(sz.x, sz.z) * 0.35, "dir": Vector3(0, 0.3, 0), "spread": 180.0, "flatness": 0.8,
		"radial_vel": Vector2(3.0, 6.0), "speed": Vector2(0.0, 0.5), "damping": Vector2(3.0, 5.0), "size": 1.1,
		"color": Color(tint.r, tint.g, tint.b, 0.5).lightened(0.4), "aabb": AABB(Vector3(-8, -2, -8), Vector3(16, 8, 16))})
	puff.position = _w(c) + Vector3(0, 0.2, 0)
	add_child(puff)
	_stomps.append([cr, puff, false])
	return cr


## A bloom portal: the warp ring pair, each ring wreathed in glowing petals.
func _bloom_portal(entry: Vector3, exit: Vector3, min_speed: float = 6.0) -> WarpPortal:
	var p: WarpPortal = kit.portal(_w(entry), _yaw, _w(exit), _yaw, min_speed)
	for pair: Array in [[entry, WarpPortal.ENTRY_COLOR], [exit, WarpPortal.EXIT_COLOR]]:
		var at: Vector3 = pair[0]
		var col: Color = pair[1]
		var petal: StandardMaterial3D = Look.flat(col.lerp(XenoFlora.MAGENTA, 0.3), 0.5, 0.0, 0.8)
		for i: int in 8:
			var a: float = TAU * float(i) / 8.0
			var leaf := Look.sphere(0.6, petal, _w(at + Vector3(cos(a) * 1.9, 1.7 + sin(a) * 1.9, 0.1)))
			leaf.scale = Vector3(0.5, 0.2, 1.0)
			leaf.rotation = Vector3(0, deg_to_rad(_yaw), a)
			add_child(leaf)
	var ex: Vector3 = _w(exit)
	var a1: GPUParticles3D = XenoFx.burst(WarpPortal.EXIT_COLOR, 40, 6.0, 0.25)
	a1.position = ex + Vector3(0, 1.2, 0)
	add_child(a1)
	var a2: GPUParticles3D = XenoFx.burst(XenoFlora.MAGENTA, 26, 7.0, 0.3)
	a2.position = ex + Vector3(0, 1.2, 0)
	add_child(a2)
	_portal_bursts.append([ex, [a1, a2]])
	add_child(XenoFx.swirl(ex + Vector3(0, 0.2, 0), 1.4, WarpPortal.EXIT_COLOR, 24))
	add_child(XenoFx.swirl(_w(entry) + Vector3(0, 0.2, 0), 1.4, WarpPortal.ENTRY_COLOR, 24))
	return p


# ---- bot helpers (all deterministic, from the course clock) --------------------------------------

func _wait(test: Callable, hold: Variant = null) -> void:
	var s: Dictionary = {"kind": "b_wait", "test": test}
	if hold != null:
		s["hold"] = hold
	route.append(s)


## Position-hold flight (bot): steer toward `to` until `until` is true (or, without it, until landing).
func _fly(to: Vector3, until: Variant = null) -> void:
	var s: Dictionary = {"kind": "a_fly", "to": to}
	if until != null:
		s["until"] = until
	route.append(s)


## The cap will throw at least `lo` (and at most `hi`) m/s when we reach it `lead` s from now.
static func _cap_ok(cap: XenoSporeCap, lead: float, lo: float, hi: float = 99.0) -> bool:
	var s: float = cap.strength_at(Game.course_time + lead)
	return s >= lo and s <= hi


static func _jaw_clear(j: XenoSnapjaw, a: float, b: float) -> bool:
	return j.is_clear_for(Game.course_time + a, b - a)


## The geyser is steaming and will keep lifting for at least `need` s.
static func _steaming(g: XenoGeyser, need: float) -> bool:
	var t: float = Game.course_time
	return g.is_lifting_at(t) and g.lift_left(t) > need


static func _acid_safe(g: XenoGeyser, a: float, b: float) -> bool:
	return g.is_safe_for(Game.course_time + a, b - a)


static func _dark(g: LaserGate, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if g.is_on_at(Game.course_time + s):
			return false
		s += 0.04
	return true


static func _piston_clear(p: Piston, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if p.extension_at(Game.course_time + s) > 0.02:
			return false
		s += 0.05
	return true


static func _blink_on(bp: BlinkPlatform, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if not bp.is_on_at(Game.course_time + s):
			return false
		s += 0.05
	return true


## The press is up (gap >= `head` m) and harmless over the whole window [now + a, now + b].
static func _open(cr: Crusher, a: float, b: float, head: float = 2.3) -> bool:
	var s: float = a
	while s <= b:
		if cr.gap_at(Game.course_time + s) < head or not cr.is_clear_for(Game.course_time + s, 0.0):
			return false
		s += 0.04
	return true


## Every timed hazard in `gates` is harmless when a runner leaving now reaches it `leads[i]` s from now, +- m.
static func _clear(gates: Array, leads: Array, m: float) -> bool:
	var t: float = Game.course_time
	for i: int in gates.size():
		var a: float = t + float(leads[i])
		var s: float = a - m
		while s <= a + m:
			var g: Node = gates[i]
			if g is LaserGate and (g as LaserGate).is_on_at(s):
				return false
			if g is Piston and (g as Piston).extension_at(s) > 0.02:
				return false
			if g is XenoSnapjaw and (g as XenoSnapjaw).is_deadly_at(s):
				return false
			if g is XenoGeyser and (g as XenoGeyser).is_acid_at(s):
				return false
			s += 0.04
	return true


# ---- the course ---------------------------------------------------------------------------------

func _build() -> void:
	# themed air at three depths around the camera (visual only)
	add_child(Ambience.make(theme_id))
	flora = XenoFlora.new(self, kit.rng)
	_restyle_environment()
	set_spawn(Vector3(0, 0.1, 4), 0.0)
	var yaws: Array[float] = [0.0, 0.0, 0.0, 90.0, 90.0, 0.0, 0.0, -90.0, -90.0, 0.0, 0.0, 90.0, 90.0, 0.0, 0.0, -90.0, -90.0, 0.0, 0.0]
	var stages: Array[Callable] = [_stage_1, _stage_2, _stage_3, _stage_4, _stage_5, _stage_6, _stage_7, _stage_8, _stage_9,
			_stage_10, _stage_11, _stage_12, _stage_13, _stage_14, _stage_15, _stage_16, _stage_17]
	_frame(Vector3.ZERO, yaws[0])
	for i: int in stages.size():
		_next_yaw = yaws[i + 1]
		var end: Vector3 = stages[i].call()
		_frame(_w(end), yaws[i + 1])
	_stage_18()
	_surroundings()
	_xeno_materials()


# ---- stage 1: Landing Site - warm-up hops, the first breathing spore cap ---------------------------

func _stage_1() -> Vector3:
	kit.plat(_w(Vector3.ZERO), Vector3(14, 2, 14), "main", 0.0, _yaw)
	flora.stalk(_w(Vector3(0, -2, 0)), 4.0, 44.0)
	var start: Dictionary = _area(Vector3.ZERO, 7.0, 7.0)
	for p: Vector3 in [Vector3(-5.6, 0, 5.4), Vector3(5.8, 0, 4.6), Vector3(-5.9, 0, -4.8), Vector3(5.5, 0, -5.4)]:
		flora.shroom_patch(_w(p), kit.rng.randf_range(1.0, 1.6))
	for p: Vector3 in [Vector3(-6.2, 0, 0.6), Vector3(6.1, 0, 1.2)]:
		flora.crystals(_w(p), kit.rng.randf_range(0.8, 1.2))
	flora.mushroom(_w(Vector3(-6.0, 0, -2.6)), 3.4, 1.6, XenoFlora.MAGENTA)
	flora.mushroom(_w(Vector3(6.2, 0, -1.8)), 2.6, 1.2, XenoFlora.TEAL)
	flora.fern(_w(Vector3(-5.4, 0, 3.0)), 3.6)
	flora.tendril(_w(Vector3(5.2, 0, 2.6)), 3.2)
	var a1: Dictionary = _blk(Vector3(0, 0, -12.2), 3.0, 3.0)
	var a2: Dictionary = _blk(Vector3(3.2, 1.0, -17.4), 2.6, 2.6, "alt")
	var a3: Dictionary = _blk(Vector3(0.4, 2.0, -22.6), 2.2, 2.2)
	var cc := Vector3(0.4, 1.0, -28.8)
	var cap: XenoSporeCap = _cap(cc, 15.5, 20.0, 3.2, 0.0, 1.4, 7.0, XenoFlora.MAGENTA)
	var l1: Dictionary = _blk(Vector3(0.4, 4.3, -35.6), 3.4, 3.4, "alt")
	var cp: Dictionary = _cp(Vector3(0.4, 4.3, -44.6))
	_hop(start, a1)
	_hop(a1, a2)
	# SHORTCUT: a crystal pillar beside the cap - mantle it from a3 and leap straight to the shelf
	var pil: Dictionary = _ledge(Vector3(-2.4, 5.0, -28.4), Vector3(1.6, 8.0, 1.6), "accent")
	flora.crystals(_w(Vector3(-2.4, 5.0, -28.4)) + Vector3(0.5, 0, 0.4), 0.35, XenoFlora.CYAN)
	_hop(a2, a3)
	if route_variant == 2:
		r_mantle(_w(_edge(a3, pil["c"])), _w((pil["c"] as Vector3) + Vector3(0.2, 0, -0.1)))
		_hop(pil, l1, Vector3(0, 0, 0.6))
	else:
		_wait(func() -> bool: return _cap_ok(cap, 0.9, 17.5))
		r_jump(_w(_edge(a3, cc)), _w(cc))
		r_pad(_w(cc), _w((l1["c"] as Vector3) + Vector3(0, 0, 0.5)))
	_hop(l1, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 2: Spore Garden - time two breathing caps, mantle the shelf fungus -----------------------

func _stage_2() -> Vector3:
	var c1c := Vector3(0, -1.0, -8.6)
	var c1: XenoSporeCap = _cap(c1c, 12.0, 20.5, 3.0, 0.0, 1.4, 8.0, XenoFlora.VIOLET)
	var s1: Dictionary = _blk(Vector3(0, 4.0, -15.6), 3.0, 3.0, "alt")
	var c2c := Vector3(2.6, 2.0, -21.8)
	var c2: XenoSporeCap = _cap(c2c, 12.0, 20.5, 3.0, 0.5, 1.4, 8.0, XenoFlora.CYAN)
	var s2: Dictionary = _blk(Vector3(2.6, 6.2, -28.4), 2.6, 2.6)
	var m1: Dictionary = _ledge(Vector3(0.6, 9.7, -33.9), Vector3(4.2, 8.0, 3.0), "alt")
	var cp: Dictionary = _cp(Vector3(0.6, 9.7, -42.6))
	# thorns past the shelf's far left corner (an overshot bounce), clear of the line on to the second cap
	_haz(Vector3(-0.9, 4.55, -17.65), Vector3(1.4, 1.5, 0.5))
	# giant shelf fungus stepping up the sides of the mantle wall (out of the climb)
	for k: int in 4:
		var side: float = -1.0 if k % 2 == 0 else 1.0
		var sh := Look.sphere(1.0, Look.flat(Color(0.95, 0.72, 0.5), 0.7, 0.0, 0.35), _w(Vector3(0.6 + side * 2.4, 9.7 - 1.6 - floorf(float(k) * 0.5) * 2.2, -33.9 + floorf(float(k) * 0.5) * 0.8)))
		sh.scale = Vector3(0.7, 0.22, 1.1)
		add_child(sh)
	r_walk(_w(Vector3(0, 0, -2.2)))
	_wait(func() -> bool: return _cap_ok(c1, 0.95, 19.2))
	r_jump(_w(Vector3(0, 0, -2.65)), _w(c1c))
	r_pad(_w(c1c), _w((s1["c"] as Vector3) + Vector3(0, 0, 0.3)))
	r_walk(_w(Vector3(0.6, 4.0, -16.4)))
	_wait(func() -> bool: return _cap_ok(c2, 0.95, 18.4))
	r_jump(_w(_edge(s1, c2c)), _w(c2c))
	r_pad(_w(c2c), _w((s2["c"] as Vector3) + Vector3(0, 0, 0.3)))
	r_mantle(_w(Vector3(1.8, 6.2, -29.35)), _w(Vector3(0.9, 9.7, -33.4)))
	_hop(m1, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 3: Vine Ravine - wall-run the glowing vine cliff, root beams in the spore wind ------------

func _stage_3() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var r1: Dictionary = _blk(Vector3(0, 0, -8.0), 3.0, 4.0, "alt")
	kit.wallrun(_w(Vector3(2.3, 1.2, -19.5)), Vector3(16, 6.5, 0.6), _yaw + 90.0)
	_vine_wall(2.9, -5.0, 6.0, -11.0, -28.0, 1.0)
	var r2: Dictionary = _blk(Vector3(-0.4, 0, -32.5), 3.6, 5.0, "alt")
	var bm1: Dictionary = _blk(Vector3(-0.4, 0.6, -40.0), 0.9, 6.0, "accent", 0.6, "")
	var k1: Dictionary = _blk(Vector3(1.6, 1.6, -47.6), 1.4, 1.4)
	var cp: Dictionary = _cp(Vector3(0.4, 1.6, -55.8))
	_wind(Vector3(-0.4, 2.0, -41.0), Vector3(16, 10, 10), Vector3(10, 0, 0))
	for z: float in [-37.5, -42.5]:
		flora.roots(_w(Vector3(-0.4, 0.0, z)), 0.3, 2)
	_hop(cp0, r1, Vector3(0, 0, 0.8))
	r_wallrun(_w(Vector3(0.3, 0, -9.65)), _w(Vector3(1.8, 1.4, -13.6)), _w(Vector3(1.8, 1.4, -24.5)), _w(Vector3(-0.4, 0, -31.8)))
	_hop(r2, bm1, Vector3(0, 0, 1.6))
	r_walk(_w(Vector3(-0.4, 0.6, -42.0)))
	r_jump(_w(Vector3(-0.4, 0.6, -42.65)), _w(k1["c"]))
	_hop(k1, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 4: Snapjaw Alley - through two flytraps between snaps, a lily pad over the acid ------------

func _stage_4() -> Vector3:
	_blk(Vector3(0, 0, -8.0), 3.0, 10.0, "alt", 1.0, "stalk")
	var j1: XenoSnapjaw = _jaw(Vector3(0, 0, -9.2), 3.0, 3.2, 2.5, 0.0)
	_blk(Vector3(0, 0, -19.5), 3.0, 7.0, "alt", 1.0, "stalk")
	var j2: XenoSnapjaw = _jaw(Vector3(0, 0, -20.3), 3.0, 3.2, 2.5, 0.55)
	var lily: MovingPlatform = kit.mover(_w(Vector3(0, 0, -27.8)), Vector3(2.6, 0.5, 2.6), [_b * Vector3(-3.0, 0, 0), _b * Vector3(3.0, 0, 0)], 4.4, 0.0, true)
	var l2: Dictionary = _blk(Vector3(0, 0.8, -34.0), 5.0, 3.0)
	var cp: Dictionary = _cp(Vector3(0, 0.8, -43.0))
	_acid(Vector3(0, -2.5, -28.0), Vector2(12.0, 7.0))
	# the lily pad: a ring of petals round the mover
	var petal: StandardMaterial3D = Look.flat(XenoFlora.TEAL.darkened(0.2), 0.5, 0.0, 0.6)
	for i: int in 7:
		var a: float = TAU * float(i) / 7.0
		var leaf := Look.sphere(0.55, petal, Vector3(cos(a) * 1.35, -0.2, sin(a) * 1.35))
		leaf.scale = Vector3(1.0, 0.2, 0.55)
		leaf.rotation.y = -a
		lily.add_child(leaf)
	r_walk(_w(Vector3(0, 0, -4.2)))
	_wait(func() -> bool: return _jaw_clear(j1, 0.1, 1.3))
	r_walk(_w(Vector3(0, 0, -12.2)))
	r_jump(_w(Vector3(0, 0, -12.65)), _w(Vector3(0, 0, -17.4)))
	_wait(func() -> bool: return _jaw_clear(j2, 0.0, 0.8))
	r_walk(_w(Vector3(0, 0, -22.4)))
	r_wait(lily, _w(Vector3(0, -0.25, -27.8)), 0.8)
	r_jump_onto(_w(Vector3(0, 0, -22.65)), lily, Vector3(0, 0.25, 0))
	r_jump_from_ride(lily, _w(Vector3(0, -0.25, -27.8)), 1.2, _w(Vector3(0, 0.8, -33.6)))
	_hop(l2, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 5: Geyser Terraces - ride the steam up, slip the acid jet, ride the second into a mantle -------

func _stage_5() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var g1f: Dictionary = _blk(Vector3(0, 0, -9.5), 4.0, 6.0, "alt")
	var g1: XenoGeyser = _geyser(Vector3(0, 0, -10.6), 8.5, 4.0, 0.0)
	var s1: Dictionary = _blk(Vector3(0, 7.5, -17.2), 3.0, 3.0)
	var b1: Dictionary = _blk(Vector3(2.2, 8.5, -23.2), 1.8, 1.8, "alt")
	var b2: Dictionary = _blk(Vector3(-0.8, 9.5, -28.6), 1.8, 1.8)
	var jet: XenoGeyser = _geyser(Vector3(0.7, -1.0, -25.9), 14.0, 2.6, 0.0, 0.0, 0.34, 1.8)
	var g2f: Dictionary = _blk(Vector3(-0.8, 6.5, -34.9), 3.6, 5.0, "alt")
	var g2: XenoGeyser = _geyser(Vector3(-0.8, 6.5, -36.1), 5.0, 3.6, 0.5)
	var top: Dictionary = _ledge(Vector3(-0.8, 13.5, -39.4), Vector3(4.0, 9.0, 3.6))
	var cp: Dictionary = _cp(Vector3(-0.2, 13.5, -49.0))
	_thorns_behind(s1, b1)
	_acid(Vector3(0.7, -1.0, -25.9), Vector2(9.0, 9.0))
	_hop(cp0, g1f, Vector3(0, 0, 1.8))
	r_walk(_w(Vector3(0, 0, -8.2)))
	_wait(func() -> bool: return _steaming(g1, 1.2))
	var s1y: float = _w(s1["c"]).y
	_fly(_w(Vector3(0, 0, -10.6)), func() -> bool: return player.global_position.y > s1y + 1.2)
	_fly(_w(s1["c"]))
	_hop(s1, b1)
	r_walk(_w((b1["c"] as Vector3) + Vector3(0.2, 0, 0.2)))
	_wait(func() -> bool: return _acid_safe(jet, 0.0, 1.0))
	_hop(b1, b2)
	_hop(b2, g2f, Vector3(0, 0, 1.4))
	r_walk(_w(Vector3(-0.8, 6.5, -33.4)))
	_wait(func() -> bool: return _steaming(g2, 1.0))
	_fly(_w((top["c"] as Vector3) + Vector3(0, 0, 0.4)))
	_hop(top, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 6: Crystal Caverns (FORK) - the laser-fenced beam, or climb the crystal cliff and run its face -

func _stage_6() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var fork: Dictionary = _blk(Vector3(0, 0, -8.0), 12.0, 4.0, "main", 1.0, "stalk")
	# LEFT: the arc gallery - a 1.2 m beam in three pieces, a fence of crystal lightning across each
	_blk(Vector3(-4.0, 0, -14.25), 1.2, 8.5, "accent", 0.6, "")
	_blk(Vector3(-4.0, 0, -24.35), 1.2, 7.3, "accent", 0.6, "")
	_blk(Vector3(-4.0, 0, -33.1), 1.2, 5.8, "accent", 0.6, "")
	for z: float in [-14.25, -24.35, -33.1]:
		flora.stalk(_w(Vector3(-4.0, -0.6, z)), 0.45, 30.0)
	var fences: Array[LaserGate] = []
	var fz: Array[float] = [-14.0, -24.2, -32.6]
	for i: int in 3:
		fences.append(_arc_fence(Vector3(-4.0, 0, fz[i]), 2.4, [0.5, 1.4, 2.3], 2.2, 0.55, 0.3 * float(i)))
	# RIGHT: the crystal cliff - two mantle walls, then the glassy face you run along down to the merge
	_ledge(Vector3(4.0, 3.3, -14.0), Vector3(3.0, 6.0, 3.2), "alt")
	_ledge(Vector3(4.0, 6.6, -20.0), Vector3(3.0, 9.3, 3.2), "alt")
	_panel(6.3, 8.0, -23.0, -33.0, 7.0)
	_crystal_face(6.75, 4.0, 12.0, -23.0, -33.0)
	var merge: Dictionary = _blk(Vector3(0, 0, -38.0), 12.0, 4.0, "main", 1.0, "stalk")
	var cp: Dictionary = _cp(Vector3(0, 0, -47.0))
	# signposts at the fork: red for the arcs, gold for the climb
	kit.lamp(_w(Vector3(-5.5, 0, -6.6)), 2.8, true, Color(1.0, 0.35, 0.25))
	kit.lamp(_w(Vector3(5.5, 0, -6.6)), 2.8, true, LedgeBlock.LIP_COLOR)
	kit.glow_strip(_w(Vector3(-4.0, 0.03, -9.0)), _sz(Vector3(1.0, 0.06, 1.4)), Color(1.0, 0.35, 0.25))
	kit.glow_strip(_w(Vector3(4.0, 0.03, -9.0)), _sz(Vector3(1.4, 0.06, 1.4)), LedgeBlock.LIP_COLOR)
	_hop(cp0, fork, Vector3(0, 0, 0.5))
	if route_variant != 1:
		r_walk(_w(Vector3(-4.0, 0, -9.4)))
		r_walk(_w(Vector3(-4.0, 0, -11.8)))
		r_until(func() -> bool: return _dark(fences[0], 0.05, 0.75))
		r_walk(_w(Vector3(-4.0, 0, -16.6)))
		r_jump(_w(Vector3(-4.0, 0, -18.15)), _w(Vector3(-4.0, 0, -21.6)))
		r_until(func() -> bool: return _dark(fences[1], 0.05, 0.7))
		r_walk(_w(Vector3(-4.0, 0, -26.6)))
		r_jump(_w(Vector3(-4.0, 0, -27.65)), _w(Vector3(-4.0, 0, -30.7)))
		r_until(func() -> bool: return _dark(fences[2], 0.05, 0.7))
		r_walk(_w(Vector3(-4.0, 0, -35.2)))
		r_walk(_w(Vector3(-2.0, 0, -37.5)))
	else:
		r_walk(_w(Vector3(4.0, 0, -8.6)))
		r_mantle(_w(Vector3(4.0, 0, -9.65)), _w(Vector3(4.0, 3.3, -13.4)))
		r_mantle(_w(Vector3(4.0, 3.3, -15.25)), _w(Vector3(4.0, 6.6, -19.4)))
		r_wallrun(_w(Vector3(4.4, 6.6, -21.25)), _w(Vector3(5.65, 8.0, -25.0)), _w(Vector3(5.65, 8.0, -29.5)), _w(Vector3(2.5, 0, -37.6)))
	_hop(merge, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


## The glassy crystal face behind a wall-run panel (decor): a wall of big hexagonal shards.
func _crystal_face(x: float, y0: float, y1: float, z0: float, z1: float) -> void:
	var len: float = absf(z0 - z1)
	var glass: StandardMaterial3D = Look.flat(Color(0.4, 0.75, 1.0, 0.9), 0.08, 0.3, 0.9)
	var core: StandardMaterial3D = Look.flat(XenoFlora.CYAN, 0.2, 0.0, 2.6)
	var n := Node3D.new()
	var cols: int = int(len / 1.6)
	for i: int in cols:
		var z: float = -len * 0.5 + 0.8 + float(i) * len / float(cols)
		var h: float = (y1 - y0) * (0.75 + 0.25 * sin(float(i) * 2.3))
		n.add_child(Look.cylinder(0.85, h, glass, Vector3(0.5, y0 + h * 0.5, z), 0.75, 6))
		if i % 2 == 0:
			n.add_child(Look.cylinder(0.3, h * 0.6, core, Vector3(0.9, y0 + h * 0.45, z), 0.2, 6))
	n.position = _w(Vector3(x, 0, (z0 + z1) * 0.5))
	n.rotation_degrees.y = _yaw
	add_child(n)


# ---- stage 7: Drift Well - board an orbiting drift stone round the monolith, float off to the far ledge ---

func _stage_7() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var e: Dictionary = _blk(Vector3(0, 0, -8.5), 4.0, 4.0, "alt", 1.0, "stalk")
	var wc := Vector3(0, 1.0, -26.0)
	var well := XenoDriftWell.new()
	well.radius = 17.0
	well.base_y = -34.0
	well.monolith_top = 3.0
	well.position = _w(wc)
	add_child(well)
	var stones: Array = []
	var rock: StandardMaterial3D = XenoFlora.rock_mat(0.05)
	for i: int in 4:
		var s: MovingPlatform = kit.orbiter(_w(Vector3(0, 0, -26.0)), 8.0, Vector3.UP, Vector3(2.6, 0.5, 2.6), 9.6, 0.25 * float(i))
		# dress the plate as a floating stone: a rock keel and a couple of glowing roots
		var keel := Look.cylinder(1.3, 1.6, rock, Vector3(0, -1.05, 0), 0.25, 7)
		s.add_child(keel)
		var tip := Look.sphere(0.1, Look.flat(XenoFlora.VIOLET, 0.3, 0.0, 2.6), Vector3(0.4, -2.3, 0.2))
		s.add_child(tip)
		stones.append(s)
	var r1: Dictionary = _blk(Vector3(12.0, 1.5, -32.0), 2.6, 2.6, "accent", 0.8, "keel")
	var x: Dictionary = _blk(Vector3(7.0, 2.5, -41.5), 4.0, 4.0, "alt", 1.0, "stalk")
	var cp: Dictionary = _cp(Vector3(7.0, 2.5, -50.5))
	_hop(cp0, e, Vector3(0, 0, 0.5))
	r_walk(_w(Vector3(0, 0, -9.8)))
	route.append({"kind": "x_wait", "nodes": stones, "locals": [Vector3.ZERO], "point": _w(Vector3(0, -0.25, -18.0)), "radius": 1.2, "lead": 0.75})
	route.append({"kind": "x_jump", "from": _w(Vector3(0, 0, -10.15)), "picked": true, "to_local": Vector3(0, 0.25, 0), "hold": true})
	route.append({"kind": "x_jump", "picked": true, "when_local": Vector3.ZERO, "when_point": _w(Vector3(7.6, -0.25, -24.0)), "when_radius": 1.4,
			"lead": 0.0, "to": _w(r1["c"]), "hold": true})
	_float(_edge(r1, x["c"]), (x["c"] as Vector3) + Vector3(0, 0, 0.4))
	_hop(x, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 8: Titan's Spine - vertebra hops, bone-ram catwalks over the acid lake, mantle the skull ------

func _stage_8() -> Vector3:
	_blk(Vector3(0, 0, -8.0), 1.4, 10.0, "alt", 1.0, "")
	var p1: Piston = _ram(Vector3(2.4, 1.3, -8.0), Vector3(2.0, 1.3, 1.6), 90.0, 3.0, 2.3, 0.0)
	var v1: Dictionary = _blk(Vector3(0, 0.6, -16.2), 1.4, 1.4, "main", 0.8, "")
	var v2: Dictionary = _blk(Vector3(1.4, 1.2, -21.6), 1.4, 1.4, "main", 0.8, "")
	var v3: Dictionary = _blk(Vector3(-0.2, 1.8, -27.0), 1.4, 1.4, "main", 0.8, "")
	_blk(Vector3(-0.2, 1.8, -34.5), 1.4, 9.0, "alt", 1.0, "")
	var rams: Array = []
	# the second ram fires a runner's half-second later: a wave you can run straight through
	for i: int in 2:
		rams.append(_ram(Vector3(-2.6, 3.1, [-32.5, -36.5][i]), Vector3(2.0, 1.3, 1.6), -90.0, 3.0, 2.2, fposmod(-0.45 * float(i) / 2.2, 1.0)))
	_ledge(Vector3(-0.2, 5.1, -43.0), Vector3(5.0, 7.0, 4.0), "alt")
	_skull(Vector3(-0.2, 5.1, -43.0))
	var cp: Dictionary = _cp(Vector3(-0.2, 5.1, -51.5))
	# the acid lake the titan lies in, and its bones: vertebra discs under the hops, ribs arching over
	_acid(Vector3(0, -6.0, -26.0), Vector2(26.0, 46.0), 12.0)
	for v: Dictionary in [v1, v2, v3]:
		var vc: Vector3 = v["c"]
		add_child(Look.cylinder(1.1, 7.0, Look.flat(Color(0.86, 0.82, 0.72), 0.7), _w(vc + Vector3(0, -4.4, 0)), 0.8, 10))
	for i: int in 5:
		var z: float = -6.0 - float(i) * 8.0
		flora.rib(_w(Vector3(-9.0, -6.5, z + 2.0)), _w(Vector3(9.0, -6.5, z - 2.0)), 17.0 - float(i % 2) * 2.0, 0.55)
	# SHORTCUT: the great rib along the left - run it past the three vertebra hops, kick onto the catwalk
	_panel(-2.3, 1.6, -14.0, -28.0, 7.0)
	flora.rib(_w(Vector3(-2.9, -3.0, -12.5)), _w(Vector3(-2.9, -3.0, -29.5)), 7.0, 0.7)
	var lead1: float = 0.5
	r_walk(_w(Vector3(0, 0, -4.0)))
	_wait(func() -> bool: return _piston_clear(p1, lead1 - 0.3, lead1 + 0.4))
	r_walk(_w(Vector3(0, 0, -12.2)))
	if route_variant == 2:
		r_wallrun(_w(Vector3(-0.3, 0, -12.65)), _w(Vector3(-1.7, 1.4, -16.6)), _w(Vector3(-1.7, 1.4, -25.0)), _w(Vector3(-0.2, 1.8, -30.5)))
	else:
		r_jump(_w(Vector3(0, 0, -12.65)), _w(v1["c"]))
		_hop(v1, v2)
		_hop(v2, v3)
		_hop(v3, _area(Vector3(-0.2, 1.8, -34.5), 0.7, 4.5), Vector3(0, 0, 3.7))
	# (hold the catwalk's first metre: the shortcut's kick lands with speed to spare)
	_wait(func() -> bool: return _clear(rams, [0.25, 0.7], 0.35), _w(Vector3(-0.2, 1.8, -30.6)))
	r_walk(_w(Vector3(-0.2, 1.8, -38.2)))
	r_mantle(_w(Vector3(-0.2, 1.8, -38.65)), _w(Vector3(-0.2, 5.1, -42.2)))
	_hop(_area(Vector3(-0.2, 5.1, -43.0), 2.5, 2.0), cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


## The titan's skull round the mantle block (decor): a great bone dome, eye sockets glowing, horns.
func _skull(top: Vector3) -> void:
	var bone: StandardMaterial3D = Look.flat(Color(0.86, 0.82, 0.72), 0.7)
	var socket: StandardMaterial3D = Look.flat(XenoFlora.LIME, 0.4, 0.0, 2.6)
	var dome := Look.sphere(1.0, bone, _w(top + Vector3(0, -4.2, -1.0)))
	dome.scale = Vector3(4.2, 4.0, 3.0)
	dome.rotation.y = deg_to_rad(_yaw)
	add_child(dome)
	for sx: float in [-1.0, 1.0]:
		add_child(Look.sphere(0.7, socket, _w(top + Vector3(sx * 1.6, -2.2, 1.9))))
		var horn := Look.cylinder(0.6, 6.0, bone, _w(top + Vector3(sx * 3.4, 0.5, -1.5)), 0.05, 8)
		horn.rotation = Vector3(-0.5, deg_to_rad(_yaw), sx * -0.6)
		add_child(horn)
	for i: int in 5:
		var tooth := Look.cylinder(0.22, 1.4, bone, _w(top + Vector3(-1.6 + float(i) * 0.8, -5.6, 2.1)), 0.0, 6)
		tooth.rotation.x = PI
		add_child(tooth)


# ---- stage 9: Snapjaw Gauntlet (FORK) - three snapjaws on the broken bridge, or the rising cap chain --------

func _stage_9() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var fork: Dictionary = _blk(Vector3(0, 0, -7.5), 12.0, 4.0, "main", 1.0, "stalk")
	# LEFT: the broken bridge, a snapjaw on every piece
	_blk(Vector3(-3.5, 0, -12.75), 2.6, 6.5, "alt", 0.8, "")
	_blk(Vector3(-3.5, 0, -21.25), 2.6, 5.5, "alt", 0.8, "")
	_blk(Vector3(-3.5, 0, -29.5), 2.6, 6.0, "alt", 0.8, "")
	var ja: XenoSnapjaw = _jaw(Vector3(-3.5, 0, -13.0), 2.6, 3.2, 2.2, 0.0, 2.6)
	var jb: XenoSnapjaw = _jaw(Vector3(-3.5, 0, -21.0), 2.6, 3.2, 2.2, 0.35, 2.6)
	var jc: XenoSnapjaw = _jaw(Vector3(-3.5, 0, -29.5), 2.6, 3.2, 2.2, 0.7, 2.6)
	# RIGHT: a chain of breathing caps rising over the drop, their breaths rolling along as a wave
	var k1c := Vector3(3.5, -1.5, -13.0)
	var k2c := Vector3(3.5, -0.5, -21.2)
	var k3c := Vector3(3.5, 0.5, -29.4)
	var k1: XenoSporeCap = _cap(k1c, 11.0, 19.0, 2.4, 0.0, 1.4, 9.0, XenoFlora.MAGENTA)
	_cap(k2c, 11.0, 19.0, 2.4, 0.6, 1.4, 9.0, XenoFlora.VIOLET)
	_cap(k3c, 11.0, 19.0, 2.4, 0.2, 1.4, 9.0, XenoFlora.CYAN)
	var merge: Dictionary = _blk(Vector3(0, 0, -38.0), 12.0, 4.0, "main", 1.0, "stalk")
	var cp: Dictionary = _cp(Vector3(0, 0, -47.0), 6.0, "")
	_acid(Vector3(0, -8.0, -22.0), Vector2(20.0, 26.0), 10.0)
	kit.lamp(_w(Vector3(-5.5, 0, -6.2)), 2.8, true, Color(1.0, 0.35, 0.25))
	kit.lamp(_w(Vector3(5.5, 0, -6.2)), 2.8, true, XenoFlora.MAGENTA)
	kit.glow_strip(_w(Vector3(-3.5, 0.03, -8.6)), _sz(Vector3(1.4, 0.06, 1.2)), Color(1.0, 0.35, 0.25))
	kit.glow_strip(_w(Vector3(3.5, 0.03, -8.6)), _sz(Vector3(1.4, 0.06, 1.2)), XenoFlora.MAGENTA)
	_hop(cp0, fork, Vector3(0, 0, 0.5))
	if route_variant != 1:
		r_walk(_w(Vector3(-3.5, 0, -10.2)))
		_wait(func() -> bool: return _jaw_clear(ja, 0.0, 0.85))
		r_walk(_w(Vector3(-3.5, 0, -15.6)))
		_wait(func() -> bool: return _jaw_clear(jb, 0.35, 1.35))
		r_jump(_w(Vector3(-3.5, 0, -15.65)), _w(Vector3(-3.5, 0, -19.6)))
		r_walk(_w(Vector3(-3.5, 0, -23.4)))
		_wait(func() -> bool: return _jaw_clear(jc, 0.35, 1.35))
		r_jump(_w(Vector3(-3.5, 0, -23.65)), _w(Vector3(-3.5, 0, -27.4)))
		r_walk(_w(Vector3(-3.5, 0, -32.0)))
		r_jump(_w(Vector3(-3.5, 0, -32.15)), _w(Vector3(-2.5, 0, -37.4)))
	else:
		r_walk(_w(Vector3(3.5, 0, -8.6)))
		_wait(func() -> bool: return _cap_ok(k1, 1.0, 16.8))
		r_jump(_w(Vector3(3.5, 0, -9.15)), _w(k1c))
		r_pad(_w(k1c), _w(k2c))
		r_pad(_w(k2c), _w(k3c))
		r_pad(_w(k3c), _w(Vector3(1.5, 0, -37.4)))
	_hop(merge, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 10: Leviathan Crossing - board a sky leviathan off the pier, ride it over the chasm ---------------

func _stage_10() -> Vector3:
	_blk(Vector3(3.0, 0, -9.0), 3.0, 12.0, "alt", 1.0, "")
	var p2: Dictionary = _blk(Vector3(3.0, 0, -57.0), 3.0, 10.0, "alt", 1.0, "")
	var cp: Dictionary = _cp(Vector3(0, 0, -69.0))
	# the pod: four leviathans sharing one loop - straight down the chasm beside the piers, then a long
	# climbing turn out to the right and back high overhead
	var pod: Array = []
	var tints: Array[Color] = [XenoFlora.TEAL, XenoFlora.CYAN, XenoFlora.VIOLET, XenoFlora.LIME]
	for i: int in 4:
		var lv := XenoLeviathan.new()
		lv.size = Vector3(3.6, 0.5, 9.0)
		lv.cross = _b * Vector3(0, 0, -72.0)
		lv.cross_fraction = 0.5
		lv.period = 22.0
		lv.phase = 0.25 * float(i)
		lv.loop_height = 32.0
		lv.loop_side = 42.0
		lv.tint = tints[i]
		lv.position = _w(Vector3(7.2, -1.45, 14.0))
		add_child(lv)
		pod.append(lv)
	# the chasm: floating islands spilling light upward beside the ride, a titan's rib vaulting high
	# over it, and a slow river of spores drifting down its length
	flora.island(_w(Vector3(-9.0, 3.0, -31.0)), 3.6)
	flora.island(_w(Vector3(-15.0, -6.0, -46.0)), 5.0)
	flora.island(_w(Vector3(26.0, 6.0, -40.0)), 4.2)
	flora.rib(_w(Vector3(-22.0, -34.0, -36.0)), _w(Vector3(34.0, -34.0, -36.0)), 58.0, 1.8)
	add_child(XenoFx.spores(_w(Vector3(7.0, 2.0, -34.0)), _sz(Vector3(16.0, 8.0, 22.0)), 110))
	add_child(XenoFx.glints(_w(Vector3(7.0, 6.0, -34.0)), _sz(Vector3(18.0, 6.0, 24.0)), 40, Color(0.6, 1.0, 0.95)))
	# pier dressing: bone posts and lanterns along the edges the leviathans pass
	for z: float in [-4.0, -9.0, -14.0, -53.0, -57.0, -61.0]:
		flora.tendril(_w(Vector3(1.8, 0, z)), 2.2)
		kit.lamp(_w(Vector3(4.3, 0, z + 1.5)), 1.6, false, XenoFlora.TEAL)
	r_walk(_w(Vector3(2.4, 0, -2.8)))
	r_walk(_w(Vector3(4.0, 0, -6.0)))
	route.append({"kind": "x_wait", "nodes": pod, "locals": [Vector3.ZERO], "point": _w(Vector3(7.2, -1.45, -7.0)), "radius": 1.2, "lead": 0.8})
	route.append({"kind": "x_jump", "from": _w(Vector3(4.0, 0, -6.0)), "picked": true, "to_local": Vector3(0, 0.25, 0), "hold": true})
	route.append({"kind": "x_jump", "picked": true, "when_local": Vector3.ZERO, "when_point": _w(Vector3(7.2, -1.45, -54.5)), "when_radius": 1.5,
			"lead": 0.0, "to": _w((p2["c"] as Vector3) + Vector3(0, 0, -2.0)), "hold": true})
	_hop(p2, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 11: Bloom Marsh - blooming pads and a vine whip over the acid, the bloom portal across the lake --

func _stage_11() -> Vector3:
	var bl1: BlinkPlatform = kit.blink(_w(Vector3(0, 0, -8.0)), _sz(Vector3(2.0, 0.5, 2.0)), 3.0, 0.6, 0.0)
	var bl2: BlinkPlatform = kit.blink(_w(Vector3(2.0, 0.8, -13.6)), _sz(Vector3(1.8, 0.5, 1.8)), 3.0, 0.6, 0.8)
	var d1: Dictionary = _disc(Vector3(0, 0.8, -21.5), 3.8, "alt")
	# the whip keeps the pads' beat: a runner who catches the two blooms lands clear of it
	var whip: Sweeper = _whip(Vector3(0, 0.8, -21.5), 3.6, 2, 3.0, 0.86)
	var bl3: BlinkPlatform = kit.blink(_w(Vector3(-1.6, 1.6, -29.8)), _sz(Vector3(1.8, 0.5, 1.8)), 2.4, 0.75, 0.3)
	var l: Dictionary = _blk(Vector3(0, 1.6, -35.8), 4.0, 4.0, "alt")
	var cp: Dictionary = _cp(Vector3(0, 1.6, -61.0))
	# the bloom portal: the only way over the wide acid lake
	var portal: WarpPortal = _bloom_portal(Vector3(0, 1.6, -37.0), Vector3(0, 1.6, -58.8), 6.0)
	_acid(Vector3(0, -3.0, -34.0), Vector2(22.0, 58.0), 12.0)
	add_child(XenoFx.fumes(_w(Vector3(0, -2.0, -34.0)), _sz(Vector3(9.0, 0.5, 26.0)), 18))
	# lily flowers under each blooming pad (they stay when the pad folds away)
	for b: BlinkPlatform in [bl1, bl2, bl3]:
		var petal: StandardMaterial3D = Look.flat(XenoFlora.MAGENTA.darkened(0.2), 0.5, 0.0, 0.7)
		for i: int in 6:
			var a: float = TAU * float(i) / 6.0
			var leaf := Look.sphere(0.6, petal, b.position + Vector3(cos(a) * 1.3, -0.5, sin(a) * 1.3))
			leaf.scale = Vector3(1.0, 0.18, 0.5)
			leaf.rotation.y = -a
			add_child(leaf)
		flora.stalk(b.position + Vector3(0, -0.6, 0), 0.25, 5.0)
	var d1n: Node3D = d1["node"]
	var spot: Vector3 = _w(Vector3(-0.6, 0.8, -24.6))
	r_walk(_w(Vector3(0, 0, -2.2)))
	var land: Vector3 = _w(Vector3(0.6, 0.8, -18.4))
	_wait(func() -> bool: return _blink_on(bl1, 0.4, 1.6) and _blink_on(bl2, 1.1, 2.3) and _bar_far(whip, land, 1.9, 2.4, 0.6))
	r_jump(_w(Vector3(0, 0, -2.65)), _w(Vector3(0, 0, -8.0)))
	r_jump(_w(Vector3(0.3, 0, -8.6)), _w(Vector3(2.0, 0.8, -13.6)))
	r_jump(_w(Vector3(1.8, 0.8, -14.35)), _w(Vector3(0.6, 0.8, -18.4)))
	route.append({"kind": "b_sweep", "to": spot, "sweeper": whip, "tol": 0.5})
	route.append({"kind": "h_hop", "node": d1n, "local": d1n.global_transform.affine_inverse() * spot, "sweepers": [whip],
			"until": func() -> bool: return _blink_on(bl3, 0.25, 1.3) and _bar_far(whip, spot, 0.0, 0.3, 0.7)})
	r_jump(_w(Vector3(-0.7, 0.8, -24.95)), _w(Vector3(-1.6, 1.6, -29.8)))
	_hop(_area(Vector3(-1.6, 1.6, -29.8), 0.9, 0.9), l, Vector3(0, 0, 0.8))
	r_portal(_w(Vector3(0, 1.6, -37.6)), portal.exit_point())
	r_walk(_w(cp["c"]))
	r_checkpoint()
	return cp["c"]


## A lashing vine whip: rotating kill bars dressed as thorny glowing vines round a bulb plant.
func _whip(floor_c: Vector3, arm: float, bars: int, period: float, phase: float) -> Sweeper:
	var sw: Sweeper = kit.sweeper(_w(floor_c), arm, bars, period, phase)
	var pivot: Node3D = sw.get_child(0) as Node3D
	var vine: StandardMaterial3D = Look.flat(Color(0.3, 0.5, 0.22), 0.6)
	var thorn: StandardMaterial3D = Look.flat(Color(1.0, 0.3, 0.25), 0.4, 0.0, 1.6)
	for holder: Node in pivot.get_children():
		var h := holder as Node3D
		var n: int = int(arm / 0.5)
		for i: int in n:
			var x: float = 0.45 + float(i) * arm / float(n)
			h.add_child(Look.sphere(0.2 - 0.06 * float(i) / float(n), vine, Vector3(x, 0.45 + 0.05 * sin(float(i) * 1.7), 0)))
			if i % 2 == 1:
				var t := Look.cylinder(0.05, 0.35, thorn, Vector3(x, 0.7, 0), 0.0, 4)
				h.add_child(t)
	var bulb: StandardMaterial3D = Look.flat(XenoFlora.MAGENTA, 0.4, 0.0, 1.6)
	var b := Look.sphere(0.7, bulb, _w(floor_c) + Vector3(0, 0.55, 0))
	b.scale = Vector3(1.0, 1.3, 1.0)
	add_child(b)
	return sw


## No whip bar comes within `min_ang` (rad) of world point `p` during [now + a, now + b].
static func _bar_far(sw: Sweeper, p: Vector3, a: float, b: float, min_ang: float) -> bool:
	var rel: Vector3 = p - sw.global_position
	var me: float = atan2(-rel.z, rel.x)
	var s: float = a
	while s <= b:
		for i: int in sw.bar_count:
			var bar: float = sw.angle_at(Game.course_time + s) + TAU * float(i) / float(sw.bar_count)
			if absf(wrapf(me - bar, -PI, PI)) < min_ang:
				return false
		s += 0.05
	return true


# ---- stage 12: Hollow Tree - three wall runs zig-zag up inside a giant hollow trunk, mantle out ----------

func _stage_12() -> Vector3:
	_panel(2.3, 1.2, -6.0, -12.5)
	_panel(-2.3, 6.0, -11.0, -19.0)
	_panel(2.3, 9.0, -17.0, -25.0)
	_vine_wall(3.1, -6.0, 13.5, -5.0, -26.0, 1.0, XenoFlora.LIME)
	_vine_wall(-3.1, -2.0, 10.5, -10.0, -20.0, -1.0, XenoFlora.MAGENTA)
	var top: Dictionary = _ledge(Vector3(-0.75, 11.9, -28.5), Vector3(4.5, 14.0, 4.0), "alt")
	var cp: Dictionary = _cp(Vector3(0, 11.9, -38.0))
	_hollow_tree(Vector3(0, 0, -15.5))
	r_wallrun(_w(Vector3(0.5, 0, -2.6)), _w(Vector3(1.7, 1.4, -7.1)), _w(Vector3(1.7, 1.4, -10.0)), _w(Vector3(-1.7, 5.5, -13.9)))
	r_wallrun(Vector3.ZERO, _w(Vector3(-1.7, 5.5, -13.9)), _w(Vector3(-1.7, 5.5, -16.9)), _w(Vector3(1.7, 8.5, -20.5)), true, true)
	r_wallrun(Vector3.ZERO, _w(Vector3(1.7, 8.5, -20.5)), _w(Vector3(1.7, 8.5, -21.9)), _w(Vector3(-0.75, 11.9, -27.1)), true, true)
	_hop(top, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


## The giant hollow trunk round the chimney (decor): a ring of bark buttresses rising out of the mist,
## open toward the course so the camera sees in, a glowing fungus ring, and a canopy far overhead.
func _hollow_tree(c: Vector3) -> void:
	var bark: StandardMaterial3D = Look.flat(Color(0.2, 0.13, 0.24), 0.9)
	var ring: StandardMaterial3D = Look.flat(XenoFlora.AMBER, 0.4, 0.0, 1.8)
	var leaf: StandardMaterial3D = Look.flat(Color(0.3, 0.2, 0.55), 0.7, 0.0, 0.3)
	var w: Vector3 = _w(c)
	for i: int in 9:
		var a: float = TAU * float(i) / 9.0
		var dir := Vector3(cos(a), 0, sin(a))
		var local_dir: Vector3 = _b.inverse() * dir
		# leave the sides the course runs along (and the camera looks from) open
		if absf(local_dir.x) < 0.45:
			continue
		var p: Vector3 = w + dir * 9.0
		var slab := Look.box(Vector3(3.2, 60.0, 1.2), bark, p + Vector3(0, -8.0, 0))
		slab.rotation.y = -a + PI * 0.5
		add_child(slab)
		var fr := Look.box(Vector3(3.3, 0.3, 1.4), ring, p + Vector3(0, 4.0 + float(i % 3) * 3.0, 0))
		fr.rotation.y = -a + PI * 0.5
		add_child(XenoFlora._no_shadow(fr))
	for i: int in 7:
		var a2: float = TAU * float(i) / 7.0
		var cl := Look.sphere(1.0, leaf, w + Vector3(cos(a2) * 10.0, 34.0 + float(i % 2) * 3.0, sin(a2) * 10.0))
		cl.scale = Vector3(9.0, 3.0, 9.0)
		cl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(cl)
	add_child(XenoFx.fireflies(w + Vector3(0, 8.0, 0), Vector3(6.0, 9.0, 8.0), 50))


# ---- stage 13: Stomper Grove - run under a stomper, mantle up under another, hop two more ------------------

func _stage_13() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var w1: Dictionary = _blk(Vector3(0, 0, -8.5), 2.6, 7.0, "alt", 1.0, "stalk")
	var c1: Crusher = _stomper(Vector3(0, 0, -8.8), Vector3(3.0, 1.6, 3.0), 3.2, 2.6, 0.0)
	_ledge(Vector3(0, 3.2, -16.5), Vector3(3.4, 7.0, 5.0))
	var c2: Crusher = _stomper(Vector3(0, 3.2, -15.2), Vector3(3.2, 1.6, 2.2), 3.0, 2.6, 0.5, XenoFlora.VIOLET)
	var p1: Dictionary = _blk(Vector3(0, 3.2, -23.5), 2.4, 2.4, "alt")
	var c3: Crusher = _stomper(Vector3(0, 3.2, -23.5), Vector3(2.8, 1.6, 2.8), 3.0, 2.6, 0.0, XenoFlora.CYAN)
	var p2: Dictionary = _blk(Vector3(1.2, 3.2, -29.0), 2.4, 2.4, "alt")
	var c4: Crusher = _stomper(Vector3(1.2, 3.2, -29.0), Vector3(2.8, 1.6, 2.8), 3.0, 2.6, 0.72)
	var cp: Dictionary = _cp(Vector3(0.6, 3.2, -37.2))
	# SHORTCUT: two 1 m stalk tops beside the grove - skip the last two stompers (a 94% leap between them)
	var k1: Dictionary = _blk(Vector3(-3.0, 3.6, -22.8), 1.0, 1.0, "accent", 0.6, "stalk")
	var k2: Dictionary = _blk(Vector3(-2.9, 4.0, -29.0), 1.0, 1.0, "accent", 0.6, "stalk")
	for k: Dictionary in [k1, k2]:
		flora.mushroom(_w((k["c"] as Vector3) + Vector3(-0.35, 0, 0.3)), 0.4, 0.25, XenoFlora.LIME)
	var top: Dictionary = _area(Vector3(0, 3.2, -16.5), 1.7, 2.5)
	_hop(cp0, w1, Vector3(0, 0, 2.6))
	r_until(func() -> bool: return _open(c1, 0.0, 0.9))
	r_walk(_w(Vector3(0, 0, -11.4)))
	r_until(func() -> bool: return _open(c2, 0.15, 1.3))
	r_mantle(_w(Vector3(0, 0, -11.65)), _w(Vector3(0, 3.2, -14.4)))
	r_walk(_w(Vector3(0, 3.2, -17.8)))
	if route_variant == 2:
		_hop(top, k1)
		_hop(k1, k2)
		_hop(k2, cp, Vector3(0, 0, 1.5))
	else:
		r_until(func() -> bool: return _open(c3, 0.2, 1.2) and _open(c4, 0.8, 1.9))
		_hop(top, p1)
		_hop(p1, p2)
		_hop(p2, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 14: Geyser Field (FORK) - ride the geyser over the acid jet, or the boosted wall run ------------

func _stage_14() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var fork: Dictionary = _blk(Vector3(-2.0, 0, -6.5), 8.0, 3.0, "main", 1.0, "stalk")
	# LEFT: the geyser terrace and the acid jet
	_blk(Vector3(-3.5, 0, -10.75), 3.6, 5.5, "alt", 1.0, "stalk")
	var g: XenoGeyser = _geyser(Vector3(-3.5, 0, -11.5), 8.5, 4.0, 0.25)
	var s: Dictionary = _blk(Vector3(-3.5, 7.0, -18.0), 3.0, 3.0)
	var jet: XenoGeyser = _geyser(Vector3(-3.5, -4.0, -21.6), 16.0, 2.4, 0.0, 0.0, 0.36, 1.8)
	_acid(Vector3(-3.5, -4.0, -21.6), Vector2(6.0, 6.0), 4.0)
	var b1: Dictionary = _blk(Vector3(-3.5, 4.5, -25.0), 2.0, 2.0)
	var b2: Dictionary = _blk(Vector3(-2.0, 3.2, -30.0), 1.8, 1.8, "alt")
	# RIGHT: the spore-wind rail - a boost strip into a fast run along the fungus wall
	kit.boost(_w(Vector3(3.4, 0, -8.5)), Vector3(2.2, 0.3, 11.0), _yaw, 20.0)
	_blk(Vector3(3.4, -0.3, -8.5), 2.6, 11.0, "alt", 0.4, "stalk")
	kit.wallrun(_w(Vector3(5.0, 1.5, -19.5)), Vector3(15.0, 7.0, 0.5), _yaw + 90.0)
	_vine_wall(5.6, -4.0, 6.0, -12.0, -27.0, 1.0, XenoFlora.CYAN)
	var merge: Dictionary = _blk(Vector3(0, 2.0, -37.0), 12.0, 8.0, "main", 1.0, "stalk")
	var cp: Dictionary = _cp(Vector3(0, 2.0, -47.0))
	kit.lamp(_w(Vector3(-5.2, 0, -5.4)), 2.8, true, XenoGeyser.STEAM)
	kit.lamp(_w(Vector3(1.6, 0, -5.4)), 2.8, true, Color(0.3, 0.85, 1.0))
	kit.glow_strip(_w(Vector3(-3.5, 0.03, -7.4)), _sz(Vector3(1.4, 0.06, 1.2)), XenoGeyser.STEAM)
	kit.glow_strip(_w(Vector3(3.4, 0.33, -4.2)), _sz(Vector3(1.4, 0.06, 0.6)), Color(0.3, 0.85, 1.0))
	if route_variant != 1:
		_hop(cp0, fork, Vector3(-1.5, 0, 0.5))
		r_walk(_w(Vector3(-3.5, 0, -9.8)))
		_wait(func() -> bool: return _steaming(g, 1.2))
		var sy: float = _w(s["c"]).y
		_fly(_w(Vector3(-3.5, 0, -11.5)), func() -> bool: return player.global_position.y > sy + 1.2)
		_fly(_w(s["c"]))
		r_walk(_w(Vector3(-3.5, 7.0, -18.8)))
		_wait(func() -> bool: return _acid_safe(jet, 0.0, 1.0))
		_hop(s, b1)
		_hop(b1, b2)
		_hop(b2, merge, Vector3(-1.0, 0, 3.0))
	else:
		r_walk(_w(Vector3(2.6, 0, -2.7)))
		r_walk(_w(Vector3(3.9, 0, -4.0)))
		r_wallrun(_w(Vector3(3.9, 0, -13.6)), _w(Vector3(4.7, 1.6, -20.0)), _w(Vector3(4.4, 1.6, -23.5)), _w(Vector3(0.5, 2.0, -36.5)))
	_hop(merge, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 15: Crystal Lattice - the arc gate over the beam, blooming pads, two arcs and a jet on one beat ---

func _stage_15() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var b1: Dictionary = _blk(Vector3(0, 0, -9.0), 1.2, 8.0, "accent", 0.5, "")
	var l1: LaserGate = _arc_gate(Vector3(0, 0, -9.0), 2.6, 2.4, 0.5, 0.0)
	var p1: BlinkPlatform = kit.blink(_w(Vector3(1.5, 0.8, -16.4)), _sz(Vector3(1.8, 0.4, 1.8)), 2.8, 0.62, 0.0)
	var p2: BlinkPlatform = kit.blink(_w(Vector3(-0.5, 1.6, -21.6)), _sz(Vector3(1.8, 0.4, 1.8)), 2.8, 0.62, 0.62)
	_blk(Vector3(0, 1.6, -27.0), 1.2, 4.0, "accent", 0.5, "")
	_blk(Vector3(0, 1.6, -33.0), 1.2, 4.0, "accent", 0.5, "")
	var gates: Array = []
	var leads: Array = []
	for i: int in 2:
		var z: float = [-26.6, -33.4][i]
		var lead: float = (-25.4 - z) / 9.0 + 0.2
		gates.append(_arc_gate(Vector3(0, 1.6, z), 2.6, 2.6, 0.45, fposmod(0.725 - lead / 2.6, 1.0)))
		leads.append(lead)
	# the acid jet rising through the gap in the beam, on the same beat
	var jl: float = (-25.4 + 30.0) / 9.0 + 0.25
	var jet: XenoGeyser = _geyser(Vector3(0, -6.0, -30.0), 14.0, 2.6, fposmod(-0.45 - jl / 2.6, 1.0), 0.0, 0.34, 1.6)
	_acid(Vector3(0, -6.0, -30.0), Vector2(5.0, 5.0), 4.0)
	gates.append(jet)
	leads.append(jl)
	var cp: Dictionary = _cp(Vector3(0, 1.6, -42.0))
	for bp: BlinkPlatform in [p1, p2]:
		flora.crystals(bp.position + Vector3(0, -1.2, 0), 0.5, XenoFlora.VIOLET)
	# SHORTCUT: a bloom portal on a 1 m knob off to the left of the first beam (a 94% leap) - out past the jet
	var kn: Vector3 = Vector3(-4.0, -0.4, -17.5)
	_blk(kn, 1.0, 1.0, "accent", 0.6, "stalk")
	_bloom_portal(kn, Vector3(0, 1.6, -39.8), 6.0)
	_hop(cp0, b1, Vector3(0, 0, 2.4))
	r_walk(_w(Vector3(0, 0, -6.2)))
	r_until(func() -> bool: return _clear([l1], [0.45], 0.35))
	r_walk(_w(Vector3(0, 0, -12.4)))
	if route_variant == 2:
		r_jump(_w(Vector3(-0.2, 0, -12.65)), _w(kn + Vector3(0, 0.3, 0)))
		r_walk(_w(cp["c"]))
		r_checkpoint()
		return cp["c"]
	else:
		r_until(func() -> bool: return _blink_on(p1, 0.4, 1.3) and _blink_on(p2, 1.4, 2.4))
		r_jump(_w(Vector3(0, 0, -12.6)), _w(Vector3(1.5, 0.8, -16.4)))
		r_jump(_w(Vector3(1.2, 0.8, -17.0)), _w(Vector3(-0.5, 1.6, -21.6)))
		r_jump(_w(Vector3(-0.4, 1.6, -22.2)), _w(Vector3(0, 1.6, -25.6)))
		r_walk(_w(Vector3(0, 1.6, -25.4)))
		r_until(func() -> bool: return _clear(gates, leads, 0.35))
		r_walk(_w(Vector3(0, 1.6, -28.6)))
		r_jump(_w(Vector3(0, 1.6, -28.65)), _w(Vector3(0, 1.6, -31.8)))
	r_walk(_w(Vector3(0, 1.6, -34.6)))
	_hop(_area(Vector3(0, 1.6, -33.0), 0.6, 2.0), cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


## A tall crystal-arc gate across a beam: one laser curtain between two crystal pylons.
func _arc_gate(floor_c: Vector3, width: float, period: float, on: float, phase: float) -> LaserGate:
	var g: LaserGate = kit.laser(_w(floor_c + Vector3(0, 1.6, 0)), Vector3(width, 3.2, 0.2), period, on, phase, _yaw)
	for sx: float in [-1.0, 1.0]:
		flora.spire(_w(floor_c + Vector3(sx * (width * 0.5 + 0.35), -1.0, 0)), 4.6, 0.3, XenoFlora.CYAN)
	return g


# ---- stage 16: Floating Isles - boosted leap across the void, a breathing cap bounces you into a mantle ------

func _stage_16() -> Vector3:
	kit.boost(_w(Vector3(0, 0, -8.5)), Vector3(2.4, 0.5, 11.0), _yaw, 20.0)
	_blk(Vector3(0, -0.5, -8.5), 3.0, 11.0, "alt", 0.5, "stalk")
	var i1: Dictionary = _blk(Vector3(0, -4.0, -36.0), 3.4, 12.0, "alt", 1.0, "keel")
	var cc := Vector3(0, -5.5, -46.0)
	var cap: XenoSporeCap = _cap(cc, 13.0, 21.0, 2.8, 0.0, 1.4, 6.0, XenoFlora.AMBER)
	var top: Dictionary = _ledge(Vector3(0, 1.3, -53.5), Vector3(3.6, 9.0, 3.0))
	var cp: Dictionary = _cp(Vector3(0, 1.3, -62.5))
	# the leap: spore streams along the strip and a ring at its mouth
	for i: int in 3:
		var sp: GPUParticles3D = Fx.emitter({"amount": 12, "lifetime": 1.0, "shape": "box", "extents": Vector3(0.8, 0.1, 0.8),
			"dir": _b * Vector3(0, 0.3, -1), "spread": 10.0, "speed": Vector2(6.0, 10.0), "tex": Fx.Tex.DOT, "size": 0.15,
			"color": Fx.hot(XenoFlora.AMBER, 2.0), "aabb": AABB(Vector3(-4, -2, -14), Vector3(8, 6, 16)), "preprocess": 1.0})
		sp.position = _w(Vector3(0, 0.1, -4.5 - 3.5 * float(i)))
		add_child(sp)
	kit.ring(_w(Vector3(0, 2.0, -14.2)), 1.9, XenoFlora.AMBER, Vector3(90, _yaw, 0))
	flora.island(_w(Vector3(-9.0, -6.0, -24.0)), 3.2)
	flora.island(_w(Vector3(8.5, -1.0, -30.0)), 2.6)
	# SHORTCUT: a hidden bloom portal on a 1 m knob below the checkpoint's corner (a 90% leap) - out on the ledge
	var hk: Vector3 = Vector3(5.6, -1.0, -9.0)
	_blk(hk, 1.0, 1.0, "accent", 0.6, "stalk")
	_bloom_portal(hk, Vector3(0, 1.3, -60.2), 6.0)
	if route_variant == 2:
		r_jump(_w(Vector3(2.6, 0, -2.65)), _w(hk + Vector3(0, 0.3, 0)))
		r_walk(_w(cp["c"]))
		r_checkpoint()
		return cp["c"]
	else:
		r_walk(_w(Vector3(0, 0, -2.2)))
		r_jump(_w(Vector3(0, 0, -13.6)), _w(Vector3(0, -4.0, -33.0)))
		route[route.size() - 1]["speed"] = 20.0
		r_walk(_w(Vector3(0, -4.0, -40.5)))
		_wait(func() -> bool: return _cap_ok(cap, 0.95, 19.0))
		r_jump(_w(Vector3(0, -4.0, -41.65)), _w(cc))
		r_pad(_w(cc), _w((top["c"] as Vector3) + Vector3(0, 0, 0.3)))
	_hop(top, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	i1.clear()
	return cp["c"]


# ---- stage 17: The Maw - a snapjaw, a bone-ram catwalk, a geyser lift and a mantle ---------------------------

func _stage_17() -> Vector3:
	_blk(Vector3(0, 0, -8.0), 3.0, 10.0, "alt", 1.0, "stalk")
	var ja: XenoSnapjaw = _jaw(Vector3(0, 0, -8.6), 3.0, 3.2, 2.2, 0.0)
	_blk(Vector3(0, 0, -19.5), 2.2, 9.0, "alt", 1.0, "")
	var rams: Array = []
	for i: int in 2:
		rams.append(_ram(Vector3(2.3, 1.3, [-17.5, -21.5][i]), Vector3(2.0, 1.3, 1.6), 90.0, 2.8, 2.2, fposmod(-0.45 * float(i) / 2.2, 1.0)))
	var gf: Dictionary = _blk(Vector3(0, 0, -28.5), 4.0, 5.0, "alt", 1.0, "stalk")
	var g: XenoGeyser = _geyser(Vector3(0, 0, -29.0), 8.5, 3.6, 0.0)
	var s: Dictionary = _blk(Vector3(0, 7.0, -35.5), 3.0, 3.0)
	_ledge(Vector3(0, 10.3, -42.0), Vector3(4.0, 8.0, 3.0), "alt")
	var cp: Dictionary = _cp(Vector3(0, 10.3, -50.5))
	_acid(Vector3(0, -7.0, -22.0), Vector2(16.0, 28.0), 10.0)
	r_walk(_w(Vector3(0, 0, -4.2)))
	_wait(func() -> bool: return _jaw_clear(ja, 0.1, 1.2))
	r_walk(_w(Vector3(0, 0, -12.2)))
	r_jump(_w(Vector3(0, 0, -12.65)), _w(Vector3(0, 0, -15.8)))
	_wait(func() -> bool: return _clear(rams, [0.25, 0.7], 0.35))
	r_walk(_w(Vector3(0, 0, -23.4)))
	r_jump(_w(Vector3(0, 0, -23.65)), _w((gf["c"] as Vector3) + Vector3(0, 0, 1.2)))
	_wait(func() -> bool: return _steaming(g, 1.2))
	var sy: float = _w(s["c"]).y
	_fly(_w(Vector3(0, 0, -29.0)), func() -> bool: return player.global_position.y > sy + 1.2)
	_fly(_w(s["c"]))
	r_mantle(_w(Vector3(0, 7.0, -36.65)), _w(Vector3(0, 10.3, -41.2)))
	_hop(_area(Vector3(0, 10.3, -42.0), 2.0, 1.5), cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 18: Monolith Summit - run the monolith face, bounce off a breathing cap into the ledge, the last jaw --

func _stage_18() -> void:
	_panel(2.3, 1.0, -5.5, -19.0)
	_obsidian_face(2.9, -6.0, 9.0, -5.0, -20.0)
	var cc := Vector3(-2.0, -3.0, -23.5)
	var cap: XenoSporeCap = _cap(cc, 17.0, 22.0, 3.2, 0.0, 1.4, 6.0, XenoFlora.MAGENTA)
	_ledge(Vector3(-2.0, 4.8, -31.0), Vector3(3.6, 9.0, 3.0))
	_blk(Vector3(-2.0, 4.8, -36.25), 3.0, 7.5, "alt", 1.0, "")
	var jaw: XenoSnapjaw = _jaw(Vector3(-2.0, 4.8, -36.5), 3.0, 3.2, 2.6, 0.0)
	var fin: Dictionary = _blk(Vector3(0, 4.8, -44.5), 12.0, 9.0, "main", 1.6, "stalk")
	kit.finish(_w(Vector3(0, 4.8, -46.0)), _yaw)
	_finish_pos = _w(Vector3(0, 4.8, -46.0))
	_summit(Vector3(0, 4.8, -46.0))
	_wait(func() -> bool: return _cap_ok(cap, 2.2, 19.2))
	r_wallrun(_w(Vector3(0.5, 0, -2.6)), _w(Vector3(1.7, 1.4, -7.1)), _w(Vector3(1.7, 1.4, -15.0)), _w(cc))
	r_pad(_w(cc), _w(Vector3(-2.0, 4.8, -30.7)))
	r_walk(_w(Vector3(-2.0, 4.8, -32.6)))
	_wait(func() -> bool: return _jaw_clear(jaw, 0.1, 1.0))
	r_walk(_w(Vector3(-1.4, 4.8, -41.0)))
	r_walk(_w(Vector3(0, 4.8, -46.0)))
	fin.clear()


## The obsidian face of the monolith behind the summit wall run (decor): black glass with glyph bands.
func _obsidian_face(x: float, y0: float, y1: float, z0: float, z1: float) -> void:
	var glass: StandardMaterial3D = Look.flat(Color(0.06, 0.05, 0.1), 0.12, 0.6)
	var glyph: StandardMaterial3D = Look.flat(XenoFlora.VIOLET, 0.3, 0.0, 2.4)
	var len: float = absf(z0 - z1)
	var n := Node3D.new()
	n.add_child(Look.box(Vector3(0.8, y1 - y0, len), glass, Vector3(0.2, (y0 + y1) * 0.5, 0)))
	for i: int in 4:
		var g := Look.box(Vector3(0.05, 0.14, len * (0.5 + 0.12 * float(i))), glyph, Vector3(-0.21, y0 + 3.0 + float(i) * 2.2, 0))
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(g)
	n.position = _w(Vector3(x, 0, (z0 + z1) * 0.5))
	n.rotation_degrees.y = _yaw
	add_child(n)


## The summit behind the finish: the great black monolith itself, its glyphs blazing, a beam of light
## climbing from its tip toward the gas giant, and a ring of crystal spires round the terrace.
func _summit(at: Vector3) -> void:
	var base: Vector3 = _w(at + Vector3(0, 0, -16.0))
	var obsidian: StandardMaterial3D = Look.flat(Color(0.05, 0.04, 0.09), 0.1, 0.65)
	var glyph: StandardMaterial3D = Look.flat(XenoFlora.VIOLET, 0.3, 0.0, 2.8)
	add_child(Look.cylinder(4.5, 90.0, obsidian, base + Vector3(0, 5.0, 0), 3.0, 6))
	add_child(Look.cylinder(3.0, 10.0, obsidian, base + Vector3(0, 55.0, 0), 0.0, 6))
	for i: int in 9:
		var y: float = -8.0 + float(i) * 6.0
		var r: float = lerpf(4.5, 3.0, (y + 40.0) / 90.0) + 0.1
		add_child(XenoFlora._no_shadow(Look.cylinder(r, 0.35, glyph, base + Vector3(0, y, 0), -1.0, 6)))
	var beam_mat := StandardMaterial3D.new()
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam_mat.albedo_color = Color(0.7, 0.5, 1.0, 0.35)
	beam_mat.disable_fog = true
	_beam_mat = beam_mat
	var beam := Look.cylinder(1.2, 400.0, beam_mat, base + Vector3(0, 260.0, 0), 2.5, 12)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	var halo := Look.sphere(2.2, Look.flat(XenoFlora.VIOLET.lightened(0.4), 0.2, 0.0, 4.0), base + Vector3(0, 61.0, 0))
	add_child(halo)
	var l := OmniLight3D.new()
	l.light_color = XenoFlora.VIOLET
	l.light_energy = 4.0
	l.omni_range = 40.0
	l.position = base + Vector3(0, 12.0, 6.0)
	add_child(l)
	add_child(XenoFx.swirl(base + Vector3(0, 2.0, 0), 7.0, XenoFlora.VIOLET, 60))
	var rise: GPUParticles3D = Fx.emitter({"amount": 60, "lifetime": 6.0, "shape": "ring", "ring_radius": 4.8, "ring_inner": 4.2,
		"ring_height": 2.0, "dir": Vector3.UP, "spread": 4.0, "speed": Vector2(6.0, 10.0), "tex": Fx.Tex.STAR, "size": 0.5,
		"curve": "pop", "color": Fx.hot(Color(0.8, 0.6, 1.0), 2.0), "aabb": AABB(Vector3(-10, -5, -10), Vector3(20, 80, 20)), "preprocess": 6.0})
	rise.position = base
	add_child(rise)
	for i: int in 8:
		var a: float = PI * (0.15 + 0.7 * float(i) / 7.0)
		var p: Vector3 = _w(at + Vector3(cos(a) * 11.0, -1.6, 4.0 - sin(a) * 9.0))
		flora.spire(p, kit.rng.randf_range(5.0, 9.0), 0.5, [XenoFlora.CYAN, XenoFlora.MAGENTA, XenoFlora.VIOLET][i % 3])


# ---- environment ----------------------------------------------------------------------------------

func _restyle_environment() -> void:
	for n: Node in get_children():
		if n is WorldEnvironment:
			_env = (n as WorldEnvironment).environment
		elif n is DirectionalLight3D:
			if n.name == "Sun":
				_sun = n as DirectionalLight3D
			else:
				_sun2 = n as DirectionalLight3D
	# the second sun: a swollen amber star low on the other side (casts its own soft shadows on High+)
	_sun2.rotation_degrees = Vector3(-14.0, -109.5, 0.0)
	_sun2.light_color = Color(1.0, 0.62, 0.32)
	_sun2.light_energy = 0.55
	if Settings.quality >= 2:
		_sun2.shadow_enabled = true
		_sun2.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		_sun2.directional_shadow_max_distance = 60.0
		_sun2.shadow_blur = 2.0
		_sun2.shadow_opacity = 0.55
	_sun.light_color = Color(0.72, 1.0, 0.95)
	_sun.light_energy = 1.15
	var d1: Vector3 = _sun.basis.z.normalized()
	var d2: Vector3 = _sun2.basis.z.normalized()
	_env.sky = XenoSky.make(d1, _sun.light_color, d2, _sun2.light_color)
	_env.background_mode = Environment.BG_SKY
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.46, 0.4, 0.82)
	_env.ambient_light_energy = 0.62
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.tonemap_exposure = 1.05
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.2, 0.24, 0.42)
	_env.fog_density = 0.0024
	_env.fog_aerial_perspective = 0.35
	_env.fog_sky_affect = 0.2
	_env.fog_sun_scatter = 0.25
	# a glowing mist layer hanging in the valleys under the course
	_env.fog_height = -14.0
	_env.fog_height_density = 0.05
	_env.glow_enabled = true
	_env.glow_intensity = 0.9
	_env.glow_bloom = 0.1
	_env.glow_hdr_threshold = 1.0
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 1.2
	_env.adjustment_contrast = 1.08


## Swap every walkable surface to the xeno ground shader (same colours, moss and glowing veins).
func _xeno_materials() -> void:
	for mi: Node in find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi as MeshInstance3D
		var sm: ShaderMaterial = m.material_override as ShaderMaterial
		if sm == null or sm.shader != Look.PLATFORM_SHADER:
			continue
		var r := ShaderMaterial.new()
		r.shader = GROUND_SHADER
		for key: String in ["top_color", "side_color", "trim_color", "half_size", "is_round", "trim_glow"]:
			r.set_shader_parameter(key, sm.get_shader_parameter(key))
		m.material_override = r


## Every point the route passes (takeoffs, landings, walk targets) - background set dressing keeps clear of them.
func _route_points() -> Array[Vector3]:
	var pts: Array[Vector3] = []
	for st: Dictionary in route:
		for key: String in ["from", "to", "entry", "exit", "top", "point", "when_point"]:
			if st.has(key) and st[key] is Vector3 and (st[key] as Vector3) != Vector3.ZERO:
				pts.append(st[key])
	for p: Vector3 in _cp_world:
		pts.append(p)
	pts.append(_finish_pos)
	return pts


var _tiles: Dictionary = {}
const TILE: float = 100.0


## The jungle floor is a patchwork of plateaus that climb with the course (each tile sits ~36 m under
## the lowest stretch of route near it), so the flora stays close under every stage of the ascent.
## Big boxes: moss tops veined with light, their stepped flanks cliffs of banded violet rock.
func _terraces(pts: Array[Vector3], lo: Vector3, hi: Vector3) -> void:
	var ground := ShaderMaterial.new()
	ground.shader = GROUND_SHADER
	ground.set_shader_parameter("top_color", Color(0.1, 0.2, 0.22))
	ground.set_shader_parameter("side_color", Color(0.22, 0.13, 0.3))
	ground.set_shader_parameter("trim_color", Color(0.3, 1.0, 0.8))
	ground.set_shader_parameter("half_size", Vector3(5000, 60, 5000))
	ground.set_shader_parameter("vein_strength", 0.55)
	var x0: int = int(floor((lo.x - 350.0) / TILE))
	var x1: int = int(ceil((hi.x + 350.0) / TILE))
	var z0: int = int(floor((lo.z - 350.0) / TILE))
	var z1: int = int(ceil((hi.z + 350.0) / TILE))
	var base: float = lo.y - 34.0
	for ix: int in range(x0, x1):
		for iz: int in range(z0, z1):
			var c := Vector3((float(ix) + 0.5) * TILE, 0.0, (float(iz) + 0.5) * TILE)
			var low: float = INF
			for q: Vector3 in pts:
				if Vector2(q.x - c.x, q.z - c.z).length() < TILE * 1.1:
					low = minf(low, q.y)
			var top: float = base if low == INF else maxf(base, snappedf(low - 36.0, 8.0))
			_tiles[Vector2i(ix, iz)] = top
			var depth: float = top - (base - 40.0)
			var b := Look.box(Vector3(TILE, depth, TILE), ground, Vector3(c.x, top - depth * 0.5, c.z))
			b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(b)


func _floor_at(p: Vector3) -> float:
	var key := Vector2i(int(floor(p.x / TILE)), int(floor(p.z / TILE)))
	return float(_tiles.get(key, -40.0))


func _nearest(p: Vector3, pts: Array[Vector3]) -> Vector3:
	var best: Vector3 = pts[0]
	var bd: float = INF
	for q: Vector3 in pts:
		var d: float = Vector2(p.x - q.x, p.z - q.z).length()
		if d < bd:
			bd = d
			best = q
	return best


## True when `p` is at least `dist` (flat) from every route point that is not far below it.
func _clear_of(p: Vector3, pts: Array[Vector3], dist: float, above: float = 30.0) -> bool:
	for q: Vector3 in pts:
		if Vector2(p.x - q.x, p.z - q.z).length() < dist and p.y < q.y + above:
			return false
	return true


func _surroundings() -> void:
	var pts: Array[Vector3] = _route_points()
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for p: Vector3 in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	var mid: Vector3 = (lo + hi) * 0.5
	var span: Vector3 = hi - lo
	var rng: RandomNumberGenerator = kit.rng
	_terraces(pts, lo, hi)
	var floor_y: float = lo.y - 34.0
	# -- acid lakes on the jungle floor, fuming and glowing up through the mist, reed beds on their shores --
	for i: int in 10:
		var c := Vector3(rng.randf_range(lo.x - 90.0, hi.x + 90.0), 0.0, rng.randf_range(lo.z - 90.0, hi.z + 90.0))
		c.y = _floor_at(c) + 0.15
		var sz := Vector2(rng.randf_range(40.0, 90.0), rng.randf_range(40.0, 90.0))
		var lake := PlaneMesh.new()
		lake.size = sz
		var lm := Look.mesh_node(lake, XenoAcidPool.material(), c)
		lm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(lm)
		add_child(XenoFx.fumes(c + Vector3(0, 2.0, 0), Vector3(sz.x * 0.4, 1.0, sz.y * 0.4), 14))
		var shore := Vector3(c.x + sz.x * 0.5 + 4.0, 0.0, c.z)
		shore.y = _floor_at(shore)
		flora.reeds(shore, Vector2(5.0, sz.y * 0.4), 90, 2.4)
		var gl := OmniLight3D.new()
		gl.light_color = Color(0.75, 1.0, 0.25)
		gl.light_energy = 2.0
		gl.omni_range = maxf(sz.x, sz.y) * 0.7
		gl.shadow_enabled = false
		gl.position = c + Vector3(0, 6.0, 0)
		add_child(gl)
	# -- mega-mushrooms rising out of the mist, their caps spread round the course's own height -----
	var placed: int = 0
	var tries: int = 0
	while placed < 24 and tries < 600:
		tries += 1
		var p := Vector3(rng.randf_range(lo.x - 90.0, hi.x + 90.0), 0.0, rng.randf_range(lo.z - 90.0, hi.z + 90.0))
		p.y = _floor_at(p)
		var near: Vector3 = _nearest(p, pts)
		var h: float = clampf(near.y - p.y + rng.randf_range(-14.0, 20.0), 18.0, 110.0)
		var cap_r: float = rng.randf_range(9.0, 22.0)
		if not _clear_of(p + Vector3(0, h, 0), pts, cap_r + 14.0, cap_r * 0.6 + 10.0):
			continue
		flora.mushroom(p, h, cap_r, Color(0, 0, 0, 0), rng.randf_range(0.0, 0.14))
		placed += 1
	# -- crystal spire clusters --------------------------------------------------------------------------
	placed = 0
	tries = 0
	while placed < 18 and tries < 500:
		tries += 1
		var sp := Vector3(rng.randf_range(lo.x - 70.0, hi.x + 70.0), 0.0, rng.randf_range(lo.z - 70.0, hi.z + 70.0))
		sp.y = _floor_at(sp)
		var sh: float = clampf(_nearest(sp, pts).y - sp.y + rng.randf_range(-10.0, 24.0), 16.0, 110.0)
		if not _clear_of(sp + Vector3(0, sh, 0), pts, 16.0, 6.0):
			continue
		var col: Color = flora.glow_color()
		flora.spire(sp, sh, rng.randf_range(1.6, 3.6), col)
		for k: int in rng.randi_range(1, 3):
			flora.spire(sp + Vector3(rng.randf_range(-6, 6), 0, rng.randf_range(-6, 6)), sh * rng.randf_range(0.3, 0.6), rng.randf_range(0.8, 1.8), col)
		placed += 1
	# -- glowing undergrowth on the plateaus nearest the course: fern groves, pods, tendrils ------------
	for i: int in 30:
		var gp := Vector3(rng.randf_range(lo.x - 40.0, hi.x + 40.0), 0.0, rng.randf_range(lo.z - 40.0, hi.z + 40.0))
		gp.y = _floor_at(gp)
		match i % 3:
			0:
				flora.fern(gp, rng.randf_range(5.0, 11.0))
			1:
				flora.pods(gp, rng.randf_range(2.0, 4.0))
			_:
				flora.tendril(gp, rng.randf_range(6.0, 12.0))
	# -- floating islands drifting at every height round the course, with their up-falls -----------
	placed = 0
	tries = 0
	while placed < 16 and tries < 400:
		tries += 1
		var ip := Vector3(rng.randf_range(lo.x - 60.0, hi.x + 60.0), rng.randf_range(lo.y - 6.0, hi.y + 45.0), rng.randf_range(lo.z - 60.0, hi.z + 60.0))
		var r: float = rng.randf_range(3.0, 8.0)
		if not _clear_of(ip, pts, r + 16.0, 40.0):
			continue
		flora.island(ip, r)
		placed += 1
	# -- great natural arches striding across the jungle ----------------------------------------------
	for i: int in 3:
		var a: Vector3 = Vector3(rng.randf_range(lo.x - 120.0, hi.x + 120.0), 0.0, rng.randf_range(lo.z - 120.0, hi.z + 120.0))
		a.y = _floor_at(a) - 2.0
		var dir: Vector3 = Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
		var wdt: float = rng.randf_range(50.0, 90.0)
		if _clear_of(a + dir * wdt * 0.5 + Vector3(0, 30, 0), pts, wdt * 0.6, 20.0):
			flora.arch(a, a + dir * wdt, rng.randf_range(45.0, 75.0), rng.randf_range(5.0, 8.0))
	# -- the horizon: a ring of colossal mushrooms and spires far out in the haze ----------------------
	var ring_r: float = maxf(span.x, span.z) * 0.5 + 160.0
	for i: int in 26:
		var a2: float = TAU * (float(i) + rng.randf() * 0.5) / 26.0
		var rp := Vector3(mid.x + cos(a2) * ring_r * rng.randf_range(0.9, 1.25), floor_y - 10.0, mid.z + sin(a2) * ring_r * rng.randf_range(0.9, 1.25))
		if i % 3 == 0:
			flora.spire(rp, rng.randf_range(90.0, 160.0), rng.randf_range(6.0, 12.0))
		else:
			var hm: float = rng.randf_range(80.0, 150.0)
			var mm: Node3D = flora.mushroom(rp, hm, rng.randf_range(30.0, 60.0), Color(0, 0, 0, 0), 0.05)
			for gi: GeometryInstance3D in mm.find_children("*", "GeometryInstance3D", true, false):
				gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# -- auroras: vast rippling curtains high in the sky ------------------------------------------------
	for i: int in 4:
		var a3: float = TAU * float(i) / 4.0 + 0.6
		var ap := Vector3(mid.x + cos(a3) * (ring_r + 60.0), hi.y + rng.randf_range(130.0, 190.0), mid.z + sin(a3) * (ring_r + 60.0))
		var am := PlaneMesh.new()
		am.orientation = PlaneMesh.FACE_Z
		am.size = Vector2(rng.randf_range(380.0, 560.0), rng.randf_range(90.0, 140.0))
		am.subdivide_width = 64
		var mat := ShaderMaterial.new()
		mat.shader = AURORA_SHADER
		mat.set_shader_parameter("seed", float(i) * 3.7)
		var base_i: float = rng.randf_range(0.8, 1.3)
		mat.set_shader_parameter("intensity", base_i)
		mat.set_meta("base", base_i)
		_auroras.append(mat)
		if i % 2 == 1:
			mat.set_shader_parameter("hem_color", Color(0.45, 0.9, 1.0))
			mat.set_shader_parameter("crown_color", Color(1.0, 0.35, 0.8))
		var au := Look.mesh_node(am, mat, ap)
		au.basis = Basis.looking_at(Vector3(mid.x - ap.x, 0.0, mid.z - ap.z).normalized(), Vector3.UP) * Basis(Vector3.RIGHT, -0.35)
		au.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		au.extra_cull_margin = 200.0
		add_child(au)
	# -- distant leviathans wheeling slowly far out over the jungle -----------------------------------
	for i: int in 3:
		var holder := Node3D.new()
		holder.set_script(preload("res://visual/spin.gd"))
		holder.set("period", rng.randf_range(90.0, 140.0) * (1.0 if i % 2 == 0 else -1.0))
		var cr: Node3D = XenoLeviathan.creature(rng.randf_range(2.6, 4.0), [XenoFlora.TEAL, XenoFlora.VIOLET, XenoFlora.CYAN][i])
		cr.position = Vector3(rng.randf_range(170.0, 260.0), 0, 0)
		cr.rotation.y = PI if i % 2 == 0 else 0.0
		holder.add_child(cr)
		holder.position = Vector3(mid.x + rng.randf_range(-60.0, 60.0), hi.y + rng.randf_range(45.0, 90.0), mid.z + rng.randf_range(-60.0, 60.0))
		holder.rotation.y = rng.randf() * TAU
		add_child(holder)
	# -- layered ambient life along the whole route: rising spores, fireflies, drifting pollen glints --
	for i: int in _cp_world.size():
		var here: Vector3 = _cp_world[i]
		var nxt: Vector3 = _cp_world[i + 1] if i + 1 < _cp_world.size() else _finish_pos
		var c: Vector3 = (here + nxt) * 0.5 + Vector3(0, 4.0, 0)
		var ext := Vector3(absf(nxt.x - here.x) * 0.5 + 14.0, 10.0, absf(nxt.z - here.z) * 0.5 + 14.0)
		add_child(XenoFx.spores(c, ext, 70))
		add_child(XenoFx.fireflies(c + Vector3(0, -1.0, 0), ext * Vector3(0.8, 0.5, 0.8), 34))
		add_child(XenoFx.glints(c + Vector3(0, 3.0, 0), ext, 18, [Color(1.0, 0.7, 1.0), Color(0.6, 1.0, 0.95)][i % 2]))
	add_child(XenoFx.spores(Vector3(0, 4, -8), Vector3(20, 8, 20), 70))
	add_child(XenoFx.fireflies(Vector3(0, 2, -6), Vector3(14, 3, 14), 30))


# ---- live effects ----------------------------------------------------------------------------------

## The moon's evening: as the stages are banked the amber sun sinks, the air cools toward violet and
## the auroras brighten (blended along the checkpoints, like the reef's descent).
const DAY_FOG := Color(0.2, 0.24, 0.42)
const DUSK_FOG := Color(0.16, 0.1, 0.3)
const DAY_AMBIENT := Color(0.46, 0.4, 0.82)
const DUSK_AMBIENT := Color(0.42, 0.3, 0.9)

var _dusk: float = 0.0
var _auroras: Array[ShaderMaterial] = []
var _beam_mat: StandardMaterial3D


func _ready() -> void:
	super()
	player.teleported.connect(_on_teleported)


func _process(dt: float) -> void:
	if _env != null and player != null:
		var target: float = clampf(float(current_checkpoint) / float(maxi(checkpoints.size(), 1)), 0.0, 1.0)
		_dusk = move_toward(_dusk, target, dt * 0.06)
		_env.fog_light_color = DAY_FOG.lerp(DUSK_FOG, _dusk)
		_env.ambient_light_color = DAY_AMBIENT.lerp(DUSK_AMBIENT, _dusk)
		_sun2.light_energy = lerpf(0.55, 0.9, _dusk)
		_sun2.light_color = Color(1.0, 0.62, 0.32).lerp(Color(1.0, 0.45, 0.3), _dusk)
		_sun.light_energy = lerpf(1.15, 0.85, _dusk)
		_env.glow_intensity = lerpf(0.9, 1.15, _dusk)
		for m: ShaderMaterial in _auroras:
			m.set_shader_parameter("intensity", float(m.get_meta("base", 1.0)) * lerpf(0.8, 1.6, _dusk))
	var t: float = Game.course_time
	for rec: Array in _stomps:
		var cr: Crusher = rec[0]
		var down: bool = cr.gap_at(t) < 0.15
		if down and not bool(rec[2]):
			var b: GPUParticles3D = rec[1]
			b.restart()
			b.emitting = true
		rec[2] = down


func _on_teleported() -> void:
	for rec: Array in _portal_bursts:
		var at: Vector3 = rec[0]
		if player.global_position.distance_to(at) < 4.0:
			for b: GPUParticles3D in rec[1]:
				b.restart()
				b.emitting = true


## The summit: the monolith answers - a fountain of spores and glints in three colours, a violet flash,
## the sky beam flaring bright, and a ring of light rolling out over the terrace.
func _finish_sequence() -> void:
	var cols: Array[Color] = [XenoFlora.TEAL, XenoFlora.MAGENTA, XenoFlora.VIOLET]
	for i: int in 3:
		var b: GPUParticles3D = XenoFx.burst(cols[i], 60, 9.0 + 2.0 * float(i), 0.3)
		b.lifetime = 1.8
		b.position = _finish_pos + Vector3(0, 1.0 + float(i), 0)
		add_child(b)
		b.restart()
		b.emitting = true
	var ring: GPUParticles3D = Fx.shockwave(9.0, {"lifetime": 0.9, "color": Fx.hot(XenoFlora.VIOLET, 1.8), "aabb": AABB(Vector3(-12, -2, -12), Vector3(24, 6, 24))})
	ring.position = _finish_pos + Vector3(0, 0.15, 0)
	add_child(ring)
	ring.restart()
	var flash := OmniLight3D.new()
	flash.light_color = XenoFlora.VIOLET.lightened(0.3)
	flash.light_energy = 7.0
	flash.omni_range = 22.0
	flash.position = _finish_pos + Vector3(0, 3.0, 0)
	add_child(flash)
	var tw: Tween = create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 1.4)
	if _beam_mat != null:
		var bt: Tween = create_tween()
		bt.tween_property(_beam_mat, "albedo_color:a", 0.9, 0.25)
		bt.tween_property(_beam_mat, "albedo_color:a", 0.45, 1.6)
	WorldAudio.at(self, "leviathan_call", _finish_pos + Vector3(0, 10.0, -20.0), 0.8, 200.0)
	await get_tree().create_timer(0.9).timeout
