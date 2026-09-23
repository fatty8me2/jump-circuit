extends LevelBase
## 5. CORAL DEPTHS - a dive through a sunken reef: over the sunlit crest, across a wrecked galleon,
## through vent fields, tidal channels and eel dens to a glowing temple in the deep. Seventeen stages,
## each ending on a checkpoint; the water darkens and the bioluminescence brightens as you go.
##
##  1 Reef Crest      warm-up hops over coral heads, the first jellyfish bounce  [shortcut: mantle the coral pillar]
##  2 Anemone Shelf   mantle a 3.3 m coral wall, urchin-ringed stepping stones, a taller mantle
##  3 Kelp Current    narrow kelp beams and small heads in a steady cross-current  [shortcut: 1 m knob in the current]
##  4 Jelly Drift     bounce across a chasm on three drifting / bobbing jellyfish
##  5 Hull Run        WALL RUN the broken stern over the gap, MANTLE onto the wreck's deck
##  6 Cannon Deck     BRANCH: the gangway past three deck rams (PISTONS)  |  mantle the cargo, wall-run the torn
##                    sail, drop from the crow's nest
##  7 Thermal Vents   ride an erupting vent (ReefVent) up to a shelf, hop, ride a second vent into a MANTLE
##  8 Tidal Channel   hop the channel between tidal surges (ReefSurge), then ride a surge over a 9 m gap
##  9 Eel Gallery     BRANCH: slip three electric-eel LASER fences on a 1.2 m beam  |  two MANTLES and a knife ridge
## 10 Clam Beds       run under a giant clam (CRUSHER), MANTLE up under another, hop two snapping clams
## 11 Wreck Chimney   three WALL RUNS zig-zag up the split hull, MANTLE out of the last kick
## 12 Bloom Gauntlet  BRANCH: drifting jelly and blooming (blink) coral  |  three coral heads to the coral PORTAL
## 13 Jet Stream      a current jet (boost 20 m/s) flings you over a chasm, a jellyfish carries the speed on
##                    [shortcut: hidden portal on a 1 m knob below the checkpoint]
## 14 Kelp Wall       WALL RUN the kelp cliff, kick onto a jellyfish, catch the ledge (MANTLE) out of the bounce
## 15 Moray Den       two coral heads swept by circling moray eels (sweepers)  [shortcut: wall-run the den's flank]
## 16 Abyssal Vents   ride a vent up through a LASER grid timed to its eruption, a second vent into a MANTLE
## 17 Sunken Temple   two clam doors on the causeway, WALL RUN the temple wall, MANTLE the steps, the eel gate
##
## Reef mechanics (own scripts): ReefJelly (drifting jellyfish bounce pads), ReefVent (erupting updraft
## columns), ReefSurge (tidal surges on a rhythm). Composed set pieces: eel fences (lasers + morays),
## giant clams (crushers + shells), eel sweepers, the wreck and the temple.
## Route variants for the bot: 0 = main line, 1 = every alternative branch, 2 = main line + every shortcut.

const ROCK_SHADER: Shader = preload("res://visual/reef_rock.gdshader")
const SKY_SHADER: Shader = preload("res://visual/reef_sky.gdshader")

var _o: Vector3 = Vector3.ZERO
var _b: Basis = Basis.IDENTITY
var _yaw: float = 0.0
var _next_yaw: float = 0.0
var deco: ReefDecor
var _env: Environment
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
## World-space checkpoint positions in build order (for set dressing along the route).
var _cp_world: Array[Vector3] = []
var _cp_bursts: Dictionary = {}
var _finish_pos: Vector3 = Vector3.ZERO


func _configure() -> void:
	theme_id = "reef"
	music_track = "a"
	kill_y = -90.0
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


func _blk(c: Vector3, sx: float, sz: float, style: String = "main", thick: float = 1.0, stalk: bool = true) -> Dictionary:
	kit.plat(_w(c), Vector3(sx, thick, sz), style, 0.0, _yaw)
	if stalk:
		deco.pinnacle(_w(c - Vector3(0, thick, 0)), clampf(minf(sx, sz) * 0.3, 0.35, 1.6), kit.rng.randf_range(26.0, 40.0))
	return {"c": c, "hx": sx * 0.5, "hz": sz * 0.5}


func _disc(c: Vector3, r: float, style: String = "main", thick: float = 0.8, stalk: bool = true) -> Dictionary:
	var body: StaticBody3D = kit.disc(_w(c), r, thick, style, 0.0)
	if stalk:
		deco.pinnacle(_w(c - Vector3(0, thick, 0)), clampf(r * 0.45, 0.4, 1.8), kit.rng.randf_range(26.0, 40.0))
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


func _haz(c: Vector3, size: Vector3, yaw_extra: float = 0.0) -> void:
	kit.hazard(_w(c), size, _yaw + yaw_extra)
	# fire coral: red spiky growth on the kill brick so it reads as part of the reef
	var n: int = maxi(int(maxf(size.x, size.z) / 0.9), 1)
	var along: Vector3 = _b * Basis(Vector3.UP, deg_to_rad(yaw_extra)) * Vector3(1, 0, 0)
	if size.z > size.x:
		along = _b * Basis(Vector3.UP, deg_to_rad(yaw_extra)) * Vector3(0, 0, 1)
	for i: int in n:
		var f: float = (float(i) + 0.5) / float(n) - 0.5
		deco.staghorn(_w(c) + along * f * maxf(size.x, size.z) + Vector3(0, size.y * 0.5 - 0.1, 0), 0.45, Color(1.0, 0.25, 0.15))


## Kill brick just past block `b`, square to the arrival direction from `a` (punishes overshoot).
func _urchin_behind(a: Dictionary, b: Dictionary, width: float = 1.6) -> void:
	var ca: Vector3 = a["c"]
	var cb: Vector3 = b["c"]
	var d := Vector3(cb.x - ca.x, 0, cb.z - ca.z).normalized()
	var half: float = minf(float(b["hx"]) / maxf(absf(d.x), 0.001), float(b["hz"]) / maxf(absf(d.z), 0.001))
	var yaw_local: float = rad_to_deg(atan2(-d.x, -d.z))
	_haz(cb + d * (half + 0.55) + Vector3(0, 0.55, 0), Vector3(width, 1.5, 0.5), yaw_local)


func _wind(c: Vector3, size: Vector3, push: Vector3, max_rise: float = 14.0) -> WindZone:
	return kit.wind(_w(c), _sz(size), _b * push, max_rise)


func _jelly(c: Vector3, strength: float, r: float = 1.25, pts: Array[Vector3] = [], period: float = 5.0, phase: float = 0.0, bob: float = 0.0, bob_period: float = 3.0, tint: Color = Color(0, 0, 0, 0)) -> ReefJelly:
	var j := ReefJelly.new()
	j.strength = strength
	j.radius = r
	var wp: Array[Vector3] = []
	for p: Vector3 in pts:
		wp.append(_b * p)
	j.points = wp
	j.period = period
	j.phase = phase
	j.bob = bob
	j.bob_period = bob_period
	j.tint = tint if tint.a > 0.0 else [ReefDecor.PINK, ReefDecor.VIOLET, ReefDecor.CYAN][kit.rng.randi() % 3]
	j.position = _w(c)
	add_child(j)
	return j


## Checkpoint platform facing the next stage's heading (_next_yaw), dressed with anemones.
func _cp(c: Vector3, size: float = 6.0) -> Dictionary:
	var d: Dictionary = _blk(c, size, size, "main", 1.4)
	var cp: Checkpoint = kit.checkpoint(_w(c), _next_yaw)
	_cp_world.append(_w(c))
	var h: float = size * 0.5 - 0.55
	deco.anemone(_w(c + Vector3(-h, 0, h)), 0.42)
	deco.anemone(_w(c + Vector3(h, 0, h)), 0.36)
	deco.sea_fan(_w(c + Vector3(-h, 0, -h)) , 2.4)
	deco.sea_fan(_w(c + Vector3(h, 0, -h)), 2.0)
	for side: float in [-1.0, 1.0]:
		deco.clump(_w(c + Vector3(side * (size * 0.5 + 0.2), -0.7, kit.rng.randf_range(-h, h))), 1.2)
	# banked-stage feedback: a fountain of bubbles and glints
	var burst: GPUParticles3D = ReefFx.burst(Color(0.7, 1.0, 1.0), 40, 6.0, true, 0.35, 1.6)
	burst.position = _w(c) + Vector3(0, 0.3, 0)
	add_child(burst)
	var glints: GPUParticles3D = ReefFx.burst(ReefDecor.CYAN, 30, 7.0, false, 0.25, 1.2)
	glints.position = _w(c) + Vector3(0, 0.5, 0)
	add_child(glints)
	_cp_bursts[cp] = [burst, glints]
	cp.reached.connect(func(which: Checkpoint) -> void:
		if which.index > current_checkpoint:
			for p: GPUParticles3D in _cp_bursts[which]:
				p.restart()
				p.emitting = true)
	return d


func _vent(floor_c: Vector3, height: float, period: float, phase: float, on_fraction: float = 0.5, push: float = 80.0, max_rise: float = 12.0, width: float = 2.4) -> ReefVent:
	var v := ReefVent.new()
	v.size = Vector3(width, height, width)
	v.push = push
	v.max_rise = max_rise
	v.period = period
	v.phase = phase
	v.on_fraction = on_fraction
	v.position = _w(floor_c)
	add_child(v)
	return v


## Position-hold flight (bot): steer toward `to` until `until` is true (or, without it, until landing).
func _fly(to: Vector3, until: Variant = null) -> void:
	var s: Dictionary = {"kind": "a_fly", "to": to}
	if until != null:
		s["until"] = until
	route.append(s)


## Vent `v` has just started erupting and will keep going for at least `need` s.
static func _erupting(v: ReefVent, need: float) -> bool:
	var t: float = Game.course_time
	return v.is_erupting_at(t) and v.eruption_left(t) > need


## Tidal surge zone in the stage frame (centre, local size, local peak push).
func _surge(c: Vector3, size: Vector3, push: Vector3, period: float, phase: float, fraction: float = 0.42) -> ReefSurge:
	var sg := ReefSurge.new()
	sg.size = size
	sg.push = push
	sg.period = period
	sg.phase = phase
	sg.surge_fraction = fraction
	sg.kelp = int(maxf(size.x, size.z) / 2.5) * 2
	sg.rotation_degrees.y = _yaw
	sg.position = _w(c)
	add_child(sg)
	return sg


## The surge stays at least `level` strong over the window [now + a, now + b].
static func _surging(sg: ReefSurge, a: float, b: float, level: float = 0.85) -> bool:
	var s: float = a
	while s <= b:
		if sg.strength_at(Game.course_time + s) < level:
			return false
		s += 0.05
	return true


## An "electric eel" fence across the path: stacked laser beams between two moray heads
## poking out of coral posts. `c` = floor centre (local), beams at `heights` above it.
func _eel_fence(c: Vector3, width: float, heights: Array, period: float, on: float, phase: float) -> LaserGate:
	var first: LaserGate = null
	for h: float in heights:
		var g: LaserGate = kit.laser(_w(c + Vector3(0, h, 0)), Vector3(width, 0.22, 0.22), period, on, phase, _yaw)
		if first == null:
			first = g
	var top: float = float(heights[heights.size() - 1])
	for sx: float in [-1.0, 1.0]:
		var post: Vector3 = c + Vector3(sx * (width * 0.5 + 0.5), 0, 0)
		deco.boulder(_w(post + Vector3(0, -0.4, 0)), 1.1)
		# the moray: a thick glowing-spotted neck curling out of the post toward the beam
		var eel := Node3D.new()
		var skin: StandardMaterial3D = Look.flat(Color(0.25, 0.42, 0.18), 0.6)
		var spot: StandardMaterial3D = Look.flat(Color(0.75, 1.0, 0.4), 0.4, 0.0, 1.6)
		for k: int in 4:
			var f: float = float(k) / 3.0
			var seg := Look.sphere(0.34 - 0.04 * f, skin, Vector3(-sx * f * 0.5, top + 0.35 - f * 0.25, sin(f * 3.0) * 0.18))
			seg.scale = Vector3(1.0, 0.85, 0.85)
			eel.add_child(seg)
			eel.add_child(Look.sphere(0.07, spot, Vector3(-sx * f * 0.5, top + 0.62 - f * 0.25, sin(f * 3.0) * 0.18)))
		var head := Look.sphere(0.3, skin, Vector3(-sx * 0.72, top + 0.05, 0.1))
		head.scale = Vector3(1.5, 0.8, 0.9)
		eel.add_child(head)
		eel.add_child(Look.sphere(0.06, Look.flat(Color(1.0, 0.9, 0.3), 0.3, 0.0, 3.0), Vector3(-sx * 0.86, top + 0.18, 0.3)))
		eel.add_child(Look.sphere(0.06, Look.flat(Color(1.0, 0.9, 0.3), 0.3, 0.0, 3.0), Vector3(-sx * 0.86, top + 0.18, -0.1)))
		eel.position = _w(post)
		eel.rotation_degrees.y = _yaw
		add_child(eel)
		# crackle: electric sparks dancing around the jaws
		var sp: GPUParticles3D = _sparks(Color(0.55, 0.9, 1.0), 14)
		sp.position = _w(post + Vector3(-sx * 0.7, top * 0.5, 0))
		add_child(sp)
	return first


## Little electric motes that flick about a point (additive).
func _sparks(color: Color, amount: int, extent: Vector3 = Vector3(0.6, 1.4, 0.6)) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 0.5
	p.preprocess = 0.5
	p.visibility_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extent
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 4.0
	pm.gravity = Vector3.ZERO
	pm.damping_min = 6.0
	pm.damping_max = 9.0
	pm.scale_min = 0.4
	pm.scale_max = 1.0
	pm.color_ramp = ReefFx.fade_ramp(color, 1.0)
	p.process_material = pm
	p.draw_pass_1 = ReefFx.dot_quad(0.14, true)
	return p


## The beam stays dark over the whole window [now + a, now + b].
static func _dark(g: LaserGate, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if g.is_on_at(Game.course_time + s):
			return false
		s += 0.04
	return true


## A giant clam: a crusher whose press is the upper shell (ridged, pearly lip) slamming down on the
## lower shell around the floor. `c` = floor top centre (local).
func _clam(c: Vector3, size: Vector3, lift: float, period: float, phase: float) -> Crusher:
	var cr: Crusher = kit.crusher(_w(c), _sz(size), lift, period, phase)
	var shell: StandardMaterial3D = Look.flat(Color(0.62, 0.42, 0.72), 0.7)
	var ridge: StandardMaterial3D = Look.flat(Color(0.85, 0.6, 0.95), 0.5, 0.0, 0.4)
	var lip: StandardMaterial3D = Look.flat(Color(0.5, 1.0, 0.9), 0.3, 0.0, 2.2)
	var sz: Vector3 = _sz(size)
	var dome := Look.sphere(1.0, shell, Vector3(0, sz.y * 0.5 - 0.1, 0))
	dome.scale = Vector3(sz.x * 0.62, 0.9, sz.z * 0.62)
	cr.add_child(dome)
	for i: int in 5:
		var f: float = (float(i) - 2.0) / 2.0
		var r := Look.box(Vector3(0.14, 0.2, 1.0), ridge, Vector3(0, sz.y * 0.5 + 0.55 - absf(f) * 0.25, 0))
		r.scale = Vector3(1.0, 1.0, maxf(sz.x, sz.z) * 0.9)
		r.position.x = f * sz.x * 0.3
		r.rotation.y = -f * 0.35
		cr.add_child(r)
	cr.add_child(Look.box(Vector3(sz.x + 0.3, 0.1, sz.z + 0.3), lip, Vector3(0, -sz.y * 0.5 + 0.3, 0)))
	# the lower shell: a scalloped rim around the floor under it, and a glowing pearl on the side
	var low := Node3D.new()
	for i: int in 10:
		var a: float = TAU * float(i) / 10.0
		var sc := Look.sphere(0.45, shell, Vector3(cos(a) * sz.x * 0.62, -0.25, sin(a) * sz.z * 0.62))
		sc.scale = Vector3(1.0, 0.5, 1.0)
		low.add_child(sc)
	low.position = _w(c)
	add_child(low)
	var pearl := Look.sphere(0.32, Look.flat(Color(1.0, 0.95, 0.9), 0.15, 0.2, 1.4), _w(c + Vector3(size.x * 0.5 + 0.45, -0.1, 0)))
	add_child(pearl)
	var b: GPUParticles3D = ReefFx.bubble_stream(8.0, 6, 0.3, 0.18)
	b.position = _w(c + Vector3(size.x * 0.5 + 0.45, 0.2, 0))
	add_child(b)
	_clam_puff(cr, _w(c), sz)
	return cr


## The press is up (gap >= `head` m) over the whole window [now + a, now + b].
static func _open(cr: Crusher, a: float, b: float, head: float = 2.3) -> bool:
	var s: float = a
	while s <= b:
		if cr.gap_at(Game.course_time + s) < head:
			return false
		s += 0.04
	return true


## Wall-run panel along the stage heading at local x, from z0 to z1 (z0 > z1), centred at height y.
func _panel(x: float, y: float, z0: float, z1: float, height: float = 7.0) -> WallRunPanel:
	return kit.wallrun(_w(Vector3(x, y, (z0 + z1) * 0.5)), Vector3(absf(z0 - z1), height, 0.5), _yaw + 90.0)


## Sunken-hull planking behind a panel (decor): tarred boards, ribs and a row of glowing portholes.
func _hull(x: float, y0: float, y1: float, z0: float, z1: float, side: float) -> void:
	var len: float = absf(z0 - z1)
	var wood: StandardMaterial3D = Look.flat(Color(0.3, 0.22, 0.16), 0.95)
	var dark: StandardMaterial3D = Look.flat(Color(0.18, 0.13, 0.1), 0.95)
	var glass: StandardMaterial3D = Look.flat(Color(1.0, 0.8, 0.45), 0.3, 0.0, 2.2)
	var n := Node3D.new()
	var h: float = y1 - y0
	n.add_child(Look.box(Vector3(0.5, h, len), wood, Vector3(0, (y0 + y1) * 0.5, 0)))
	var rows: int = int(h / 1.1)
	for i: int in rows:
		n.add_child(Look.box(Vector3(0.56, 0.08, len), dark, Vector3(0, y0 + 0.55 + float(i) * 1.1, 0)))
	var ribs: int = int(len / 3.0) + 1
	for i: int in ribs:
		n.add_child(Look.box(Vector3(0.8, h + 0.6, 0.35), dark, Vector3(side * 0.2, (y0 + y1) * 0.5, -len * 0.5 + float(i) * len / float(maxi(ribs - 1, 1)))))
	for i: int in int(len / 4.0):
		var z: float = -len * 0.5 + 2.0 + float(i) * 4.0
		n.add_child(Look.cylinder(0.3, 0.6, glass, Vector3(-side * 0.05, y1 - 1.2, z), -1.0, 12))
		n.get_child(n.get_child_count() - 1).rotation.z = PI * 0.5
	n.position = _w(Vector3(x, 0, (z0 + z1) * 0.5))
	n.rotation_degrees.y = _yaw
	add_child(n)


## Eel sweeper: rotating kill bars dressed as morays swimming round a coral head.
func _eel_sweeper(floor_c: Vector3, arm: float, bars: int, period: float, phase: float) -> Sweeper:
	var sw: Sweeper = kit.sweeper(_w(floor_c), arm, bars, period, phase)
	var pivot: Node3D = sw.get_child(0) as Node3D
	var skin: StandardMaterial3D = Look.flat(Color(0.3, 0.45, 0.16), 0.6)
	var belly: StandardMaterial3D = Look.flat(Color(0.95, 0.35, 0.2), 0.4, 0.0, 1.4)
	var eye: StandardMaterial3D = Look.flat(Color(1.0, 0.9, 0.3), 0.3, 0.0, 3.0)
	for holder: Node in pivot.get_children():
		var h := holder as Node3D
		var n: int = int(arm / 0.45)
		for i: int in n:
			var x: float = 0.4 + float(i) * arm / float(n)
			var r: float = 0.3 - 0.1 * float(i) / float(n)
			h.add_child(Look.sphere(r, skin, Vector3(x, 0.45 + 0.05 * sin(float(i) * 1.3), 0.06 * sin(float(i) * 0.9))))
			if i % 2 == 0:
				h.add_child(Look.sphere(0.08, belly, Vector3(x, 0.45 - r * 0.7, 0)))
		var head := Look.sphere(0.3, skin, Vector3(0.45, 0.55, 0))
		head.scale = Vector3(1.3, 0.9, 0.9)
		h.add_child(head)
		for side: float in [-1.0, 1.0]:
			h.add_child(Look.sphere(0.06, eye, Vector3(0.6, 0.68, side * 0.17)))
	deco.brain(_w(floor_c), 0.7, ReefDecor.LIME)
	return sw


## No eel bar comes within `min_ang` (rad) of world point `p` during [now + a, now + b].
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


# ---- bot helpers (all deterministic, from the course clock) --------------------------------------

func _wait(test: Callable, hold: Variant = null) -> void:
	var s: Dictionary = {"kind": "b_wait", "test": test}
	if hold != null:
		s["hold"] = hold
	route.append(s)


static func _laser_off(g: LaserGate, t0: float, t1: float) -> bool:
	var s: float = t0
	while s <= t1:
		if g.is_on_at(Game.course_time + s):
			return false
		s += 0.05
	return true


static func _piston_clear(p: Piston, t0: float, t1: float) -> bool:
	var s: float = t0
	while s <= t1:
		if p.extension_at(Game.course_time + s) > 0.02:
			return false
		s += 0.05
	return true


static func _blink_on(bp: BlinkPlatform, t0: float, t1: float) -> bool:
	var s: float = t0
	while s <= t1:
		if not bp.is_on_at(Game.course_time + s):
			return false
		s += 0.05
	return true


# ---- the course ---------------------------------------------------------------------------------

func _build() -> void:
	deco = ReefDecor.new(self, kit.rng)
	_restyle_environment()
	set_spawn(Vector3(0, 0.1, 4), 0.0)
	var yaws: Array[float] = [0.0, 0.0, 0.0, -90.0, -90.0, -90.0, -90.0, 0.0, 0.0, 0.0, 90.0, 90.0, 0.0, 0.0, -90.0, -90.0, 0.0, 0.0]
	var stages: Array[Callable] = [_stage_1, _stage_2, _stage_3, _stage_4, _stage_5, _stage_6, _stage_7, _stage_8, _stage_9,
			_stage_10, _stage_11, _stage_12, _stage_13, _stage_14, _stage_15, _stage_16, _stage_17]
	_frame(Vector3.ZERO, yaws[0])
	for i: int in stages.size():
		_next_yaw = yaws[i + 1]
		var end: Vector3 = stages[i].call()
		_frame(_w(end), yaws[i + 1])
	_surroundings()
	_reef_materials()


# ---- stage 1: Reef Crest - warm-up hops over coral heads, the first jellyfish ---------------------

func _stage_1() -> Vector3:
	kit.plat(_w(Vector3.ZERO), Vector3(14, 2, 14), "main", 0.0, _yaw)
	deco.pinnacle(_w(Vector3(0, -2, 0)), 3.5, 40.0)
	var start: Dictionary = _area(Vector3.ZERO, 7.0, 7.0)
	for p: Vector3 in [Vector3(-5.6, 0, 5.2), Vector3(5.8, 0, 4.6), Vector3(-5.9, 0, -4.8), Vector3(5.5, 0, -5.4)]:
		deco.brain(_w(p), kit.rng.randf_range(0.7, 1.1))
	for p: Vector3 in [Vector3(-4.2, 0, 6.0), Vector3(6.1, 0, 0.8), Vector3(-6.2, 0, 0.2), Vector3(3.6, 0, 6.2)]:
		deco.staghorn(_w(p), kit.rng.randf_range(0.9, 1.3))
	deco.sea_fan(_w(Vector3(-6.3, 0, -2.4)), 3.0, ReefDecor.VIOLET)
	deco.sea_fan(_w(Vector3(6.4, 0, -2.0)), 2.6, ReefDecor.PINK)
	kit.arch(_w(Vector3(0, 0, -6.6)), 5.0, 4.4, _yaw, ReefDecor.VIOLET.darkened(0.3))
	var a1: Dictionary = _blk(Vector3(0, 0, -12.2), 3.0, 3.0)
	var a2: Dictionary = _blk(Vector3(3.4, 1.0, -17.6), 2.6, 2.6, "alt")
	var a3: Dictionary = _blk(Vector3(0.6, 2.0, -23.0), 2.2, 2.2)
	var jc := Vector3(0.6, 1.0, -29.4)
	_jelly(jc, 17.0, 1.3, [], 5.0, 0.0, 0.0, 3.0, ReefDecor.PINK)
	var l1: Dictionary = _blk(Vector3(0.6, 4.6, -36.2), 3.4, 3.4, "alt")
	var cp: Dictionary = _cp(Vector3(0.6, 4.6, -45.0))
	_hop(start, a1)
	_hop(a1, a2)
	# SHORTCUT: a coral pillar beside the jellyfish - mantle it from a3 and leap straight to the shelf
	var pil: Dictionary = _ledge(Vector3(-2.4, 5.4, -28.6), Vector3(1.6, 8.0, 1.6), "accent")
	deco.pinnacle(_w(Vector3(-2.4, -2.6, -28.6)), 0.6, 30.0)
	_hop(a2, a3)
	if route_variant == 2:
		r_mantle(_w(_edge(a3, pil["c"])), _w((pil["c"] as Vector3) + Vector3(0, 0, 0.3)))
		_hop(pil, l1, Vector3(0, 0, 0.6))
	else:
		r_jump(_w(_edge(a3, jc)), _w(jc))
		r_pad(_w(jc), _w((l1["c"] as Vector3) + Vector3(0, 0, 0.5)))
	_hop(l1, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 2: Anemone Shelf - mantle up a coral wall, urchin-ringed stepping stones, a taller mantle ----

func _stage_2() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var m1: Dictionary = _ledge(Vector3(0, 3.3, -7.2), Vector3(5.0, 5.3, 3.4))
	var u1: Dictionary = _blk(Vector3(-2.2, 3.3, -13.4), 1.8, 1.8)
	var u2: Dictionary = _blk(Vector3(1.8, 4.3, -17.6), 1.8, 1.8, "alt")
	var u3: Dictionary = _blk(Vector3(1.8, 4.3, -23.9), 1.6, 1.6)
	var u4: Dictionary = _blk(Vector3(-1.8, 5.3, -28.4), 1.8, 1.8, "alt")
	var m2: Dictionary = _ledge(Vector3(-1.8, 8.9, -34.2), Vector3(3.2, 5.0, 3.2))
	var cp: Dictionary = _cp(Vector3(-1.8, 8.9, -43.0))
	_urchin_behind(u1, u2)
	_urchin_behind(u2, u3)
	_haz(Vector3(0, 2.6, -15.6), Vector3(1.0, 0.9, 1.0))
	for p: Vector3 in [Vector3(-1.6, 3.3, -8.4), Vector3(1.9, 3.3, -6.0)]:
		deco.anemone(_w(p), 0.38)
	r_mantle(_w(Vector3(0, 0, -2.5)), _w(Vector3(0, 3.3, -7.4)))
	_hop(m1, u1)
	_hop(u1, u2)
	_hop(u2, u3)
	_hop(u3, u4)
	r_mantle(_w(_edge(u4, m2["c"])), _w((m2["c"] as Vector3) + Vector3(0, 0, 0.2)))
	_hop(m2, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 3: Kelp Current - narrow beams and small blocks in a steady cross-current ----------------

func _stage_3() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var k1: Dictionary = _blk(Vector3(-1.0, 0, -9.0), 0.9, 6.0, "accent", 0.7)
	var k2: Dictionary = _blk(Vector3(-3.4, 1.0, -16.6), 1.6, 1.6)
	var k3: Dictionary = _blk(Vector3(-3.4, 1.0, -23.0), 0.8, 5.0, "accent", 0.7)
	var k4: Dictionary = _blk(Vector3(-0.6, 2.0, -29.0), 1.6, 1.6, "alt")
	var k5: Dictionary = _blk(Vector3(-2.8, 3.0, -34.0), 1.6, 1.6)
	var cp: Dictionary = _cp(Vector3(-1.4, 3.0, -42.2))
	_wind(Vector3(-1.0, 2.0, -21.5), Vector3(22, 12, 32), Vector3(13, 0, 0))
	_hop(cp0, k1, Vector3(0, 0, 1.2))
	r_walk(_w(Vector3(-1.0, 0, -10.8)))
	r_jump(_w(Vector3(-1.0, 0, -11.65)), _w(k2["c"]))
	# SHORTCUT: a 1 m coral knob out in the current - two long jumps that skip the kelp beam
	var knob: Dictionary = _blk(Vector3(-0.6, 1.3, -22.6), 1.0, 1.0, "accent", 0.6)
	if route_variant == 2:
		_hop(k2, knob)
		_hop(knob, k4)
	else:
		_hop(k2, k3, Vector3(0, 0, 1.0))
		r_walk(_w(Vector3(-3.4, 1.0, -24.6)))
		r_jump(_w(Vector3(-3.4, 1.0, -25.15)), _w(k4["c"]))
	_hop(k4, k5)
	_hop(k5, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 4: Jelly Drift - bounce across a chasm on drifting jellyfish -----------------------------

func _stage_4() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var j1c := Vector3(0, -1.5, -8.5)
	var j2c := Vector3(0, -0.5, -16.5)
	var j3c := Vector3(2.4, 0.5, -24.2)
	var j1: ReefJelly = _jelly(j1c, 18.0, 1.3, [Vector3(-2.2, 0, 0), Vector3(2.2, 0, 0)], 4.8, 0.0)
	var j2: ReefJelly = _jelly(j2c, 18.0, 1.3, [], 5.0, 0.0, 0.7, 3.2)
	var j3: ReefJelly = _jelly(j3c, 18.0, 1.3, [Vector3(0, 0, 1.8), Vector3(0, 0, -1.8)], 4.0, 0.25)
	var l4: Dictionary = _blk(Vector3(2.4, 3.5, -32.0), 2.4, 2.4, "alt")
	var cp: Dictionary = _cp(Vector3(0, 3.5, -40.0))
	r_jump_onto(_w(Vector3(0, 0, -2.65)), j1)
	route.append({"kind": "pad", "from": _w(j1c), "to_node": j2, "to_local": Vector3.ZERO, "to": Vector3.ZERO})
	route.append({"kind": "pad", "from": _w(j2c), "to_node": j3, "to_local": Vector3.ZERO, "to": Vector3.ZERO})
	r_pad(_w(j3c), _w(l4["c"]))
	_hop(l4, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 5: Hull Run - wall-run the broken stern across a gap, mantle up onto the wreck ------------

func _stage_5() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var r1: Dictionary = _blk(Vector3(0, 0, -8.0), 3.0, 4.0, "alt")
	kit.wallrun(_w(Vector3(2.3, 1.2, -19.5)), Vector3(16, 6.5, 0.6), _yaw + 90.0)
	var r2: Dictionary = _blk(Vector3(-0.4, 0, -32.5), 3.6, 5.0, "alt")
	_ledge(Vector3(0, 3.5, -40.0), Vector3(8.0, 6.0, 3.5))
	_blk(Vector3(0, 3.5, -47.0), 8.0, 10.5, "alt", 1.0, false)
	_hop(cp0, r1, Vector3(0, 0, 0.8))
	r_wallrun(_w(Vector3(0.3, 0, -9.65)), _w(Vector3(1.8, 1.4, -13.6)), _w(Vector3(1.8, 1.4, -24.5)), _w(Vector3(-0.4, 0, -31.8)))
	r_mantle(_w(Vector3(-0.2, 0, -34.6)), _w(Vector3(-0.2, 3.5, -40.2)))
	var cp: Vector3 = Vector3(0, 3.5, -46.5)
	kit.checkpoint(_w(cp), _next_yaw)
	_cp_world.append(_w(cp))
	r_walk(_w(cp))
	r_checkpoint()
	return cp


# ---- stage 6: Cannon Deck (BRANCH) - run the gangway past the deck rams, or climb the fallen mast -----

func _stage_6() -> Vector3:
	# deck continues from stage 5's deck (which reaches local z = -5.75 here)
	var seg_a: Dictionary = _blk(Vector3(0, 0, -9.0), 3.0, 6.5, "alt", 1.0, false)
	var seg_b: Dictionary = _blk(Vector3(0, 0, -19.0), 3.0, 9.0, "alt", 1.0, false)
	var seg_c: Dictionary = _blk(Vector3(0, 0, -30.0), 3.0, 8.0, "alt", 1.0, false)
	var rams: Array[Piston] = []
	var zs: Array[float] = [-9.5, -19.5, -29.5]
	for i: int in zs.size():
		# rams punch from the starboard rail across the gangway (arrow = local -X)
		var p: Piston = kit.piston(_w(Vector3(3.3, 1.3, zs[i])), Vector3(2.0, 1.3, 1.6), _yaw + 90.0, 3.4, 3.0, 0.62 - 0.26 * float(i), 8.0)
		rams.append(p)
	var cp: Dictionary = _cp(Vector3(0, 0, -38.0))
	# the alternative, on the port side: a cargo stack (mantle), the torn mainsail hanging along the
	# wreck (wall run over the drop), and the crow's nest of the fallen mast
	_ledge(Vector3(-4.0, 3.3, -9.0), Vector3(3.0, 6.0, 3.5), "alt")
	kit.wallrun(_w(Vector3(-6.3, 4.4, -18.5)), Vector3(15.0, 7.0, 0.6), _yaw + 90.0)
	var nest: Dictionary = _disc(Vector3(-2.2, 3.3, -29.0), 1.5, "accent", 0.8, false)
	kit.pipe(_w(Vector3(-2.6, 2.4, -28.6)), _w(Vector3(-9.0, -14.0, -19.0)), 0.45, Color(0.42, 0.3, 0.22))
	# signposts at the fork: gold for the climb, red for the rams
	kit.lamp(_w(Vector3(-3.6, 0, -2.4)), 2.6, true, LedgeBlock.LIP_COLOR)
	kit.lamp(_w(Vector3(1.9, 0, -3.2)), 2.6, true, Color(1.0, 0.35, 0.25))
	if route_variant != 1:
		# main: run the gangway, slipping past each ram between shots, hop the two broken planks
		for i: int in rams.size():
			var p: Piston = rams[i]
			var stop: Vector3 = Vector3(0, 0, zs[i] + 2.4)
			if i == 1:
				stop = Vector3(0, 0, -16.2)
				r_jump(_w(Vector3(0, 0, -12.0)), _w(stop))
			elif i == 2:
				stop = Vector3(0, 0, -27.2)
				r_jump(_w(Vector3(0, 0, -23.2)), _w(stop))
			else:
				r_walk(_w(stop))
			_wait(func() -> bool: return _piston_clear(p, 0.0, 0.75))
		_hop(seg_c, cp, Vector3(0, 0, 1.5))
	else:
		# alt: mantle the cargo stack, run the torn sail, drop from the crow's nest to the bow
		r_walk(_w(Vector3(-3.4, 0, -4.2)))
		r_mantle(_w(Vector3(-3.6, 0, -5.4)), _w(Vector3(-3.8, 3.3, -8.6)))
		r_wallrun(_w(Vector3(-3.8, 3.3, -10.3)), _w(Vector3(-5.65, 4.7, -14.2)), _w(Vector3(-5.65, 4.7, -21.0)), _w(nest["c"]))
		_hop(nest, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 7: Thermal Vents - ride an erupting vent up to a shelf, hop, ride the next one into a mantle ----

func _stage_7() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var v1f: Dictionary = _blk(Vector3(0, 0, -9.5), 4.0, 6.0, "alt")
	var v1: ReefVent = _vent(Vector3(0, 0, -10.6), 8.0, 4.0, 0.0)
	var s1: Dictionary = _blk(Vector3(0, 7.5, -17.2), 3.0, 3.0)
	var b1: Dictionary = _blk(Vector3(2.2, 8.5, -23.2), 1.8, 1.8, "alt")
	var b2: Dictionary = _blk(Vector3(-0.8, 9.5, -28.6), 1.8, 1.8)
	var v2f: Dictionary = _blk(Vector3(-0.8, 6.5, -34.9), 3.6, 5.0, "alt")
	var v2: ReefVent = _vent(Vector3(-0.8, 6.5, -36.1), 4.5, 3.6, 0.5)
	var top: Dictionary = _ledge(Vector3(-0.8, 13.5, -39.4), Vector3(4.0, 9.0, 3.6))
	var cp: Dictionary = _cp(Vector3(-0.2, 13.5, -49.0))
	_urchin_behind(s1, b1)
	_urchin_behind(b1, b2)
	_hop(cp0, v1f, Vector3(0, 0, 1.8))
	r_walk(_w(Vector3(0, 0, -8.2)))
	_wait(func() -> bool: return _erupting(v1, 1.3))
	var s1y: float = _w(s1["c"]).y
	_fly(_w(Vector3(0, 0, -10.6)), func() -> bool: return player.global_position.y > s1y + 1.2)
	_fly(_w(s1["c"]))
	_hop(s1, b1)
	_hop(b1, b2)
	_hop(b2, v2f, Vector3(0, 0, 1.4))
	r_walk(_w(Vector3(-0.8, 6.5, -33.4)))
	_wait(func() -> bool: return _erupting(v2, 1.1))
	_fly(_w((top["c"] as Vector3) + Vector3(0, 0, 0.4)))
	_hop(top, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 8: Tidal Channel - hop across the channel between surges, then ride a surge over a gap ------

func _stage_8() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var c1: Dictionary = _blk(Vector3(0.4, 0, -8.6), 1.8, 1.8, "alt")
	var c2: Dictionary = _blk(Vector3(-0.6, 0.8, -14.4), 1.6, 1.6)
	var c3: Dictionary = _blk(Vector3(0.4, 1.6, -20.2), 1.8, 1.8, "alt")
	var bank: Dictionary = _blk(Vector3(0, 1.6, -27.0), 5.0, 4.0)
	var far: Dictionary = _blk(Vector3(0, 1.6, -40.5), 5.0, 5.0)
	var cp: Dictionary = _cp(Vector3(0, 1.6, -50.0))
	# the cross-channel surge rushes toward +X; the long surge races down the channel (-Z)
	var cross: ReefSurge = _surge(Vector3(0, 2.0, -14.0), Vector3(16, 10, 21), Vector3(26, 0, 0), 4.5, 0.0)
	var along: ReefSurge = _surge(Vector3(0, 2.5, -33.5), Vector3(7, 8, 12), Vector3(0, 0, -16), 3.6, 0.3, 0.5)
	var prev: Dictionary = cp0
	for b: Dictionary in [c1, c2, c3]:
		r_walk(_w(_edge(prev, b["c"], 0.9)))
		_wait(func() -> bool: return cross.is_calm_for(Game.course_time, 1.05))
		_hop(prev, b)
		prev = b
	_hop(c3, bank, Vector3(0, 0, 0.6))
	r_walk(_w(Vector3(0, 1.6, -26.4)))
	_wait(func() -> bool: return _surging(along, 0.3, 1.2))
	route.append({"kind": "b_jump", "from": _w(Vector3(0, 1.6, -28.65)), "to": _w((far["c"] as Vector3) + Vector3(0, 0, 0.5)), "hold": true})
	_hop(far, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 9: Eel Gallery (BRANCH) - slip the electric-eel fences on the low beam, or climb the cliffs ----

func _stage_9() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var fork: Dictionary = _blk(Vector3(0, 0, -8.0), 12.0, 4.0, "main", 1.0, false)
	deco.pinnacle(_w(Vector3(-3.5, -1.0, -8.0)), 1.2, 34.0)
	deco.pinnacle(_w(Vector3(3.5, -1.0, -8.0)), 1.2, 30.0)
	# LEFT: the eel alley - a 1.2 m beam in three pieces, a fence of eel-lightning across each
	_blk(Vector3(-4.0, 0, -14.25), 1.2, 8.5, "accent", 0.6, false)
	_blk(Vector3(-4.0, 0, -24.35), 1.2, 7.3, "accent", 0.6, false)
	_blk(Vector3(-4.0, 0, -33.1), 1.2, 5.8, "accent", 0.6, false)
	for z: float in [-14.25, -24.35, -33.1]:
		deco.pinnacle(_w(Vector3(-4.0, -0.6, z)), 0.5, 30.0)
	var fences: Array[LaserGate] = []
	var fz: Array[float] = [-14.0, -24.2, -32.6]
	for i: int in 3:
		fences.append(_eel_fence(Vector3(-4.0, 0, fz[i]), 2.4, [0.5, 1.4, 2.3], 2.2, 0.55, 0.3 * float(i)))
	# RIGHT: the coral cliffs - two mantle walls, a knife-edge ridge, a leap down to the merge
	var l1: Dictionary = _ledge(Vector3(4.0, 3.3, -14.0), Vector3(3.0, 6.0, 3.2), "alt")
	var l2: Dictionary = _ledge(Vector3(4.0, 6.6, -20.0), Vector3(3.0, 9.3, 3.2), "alt")
	var ridge: Dictionary = _blk(Vector3(4.0, 6.6, -26.8), 0.9, 6.0, "accent", 0.6)
	var merge: Dictionary = _blk(Vector3(0, 0, -38.0), 12.0, 4.0, "main", 1.0, false)
	deco.pinnacle(_w(Vector3(0, -1.0, -38.0)), 1.6, 36.0)
	var cp: Dictionary = _cp(Vector3(0, 0, -47.0))
	# signposts at the fork: red lamps and strips for the eels, gold for the climb
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
		r_jump(_w(Vector3(4.0, 6.6, -21.25)), _w(Vector3(4.0, 6.6, -25.0)))
		r_walk(_w(Vector3(4.0, 6.6, -28.6)))
		r_jump(_w(Vector3(4.0, 6.6, -29.45)), _w(Vector3(2.5, 0, -37.4)))
	_hop(merge, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 10: Clam Beds - run under a clam, mantle up under another, hop two snapping clams ------------

func _stage_10() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var w1: Dictionary = _blk(Vector3(0, 0, -8.5), 2.6, 7.0, "alt", 1.0, false)
	deco.pinnacle(_w(Vector3(0, -1.0, -8.5)), 0.9, 34.0)
	var c1: Crusher = _clam(Vector3(0, 0, -8.8), Vector3(3.0, 1.6, 3.0), 3.2, 2.6, 0.0)
	var ledge: Dictionary = _ledge(Vector3(0, 3.2, -16.5), Vector3(3.4, 7.0, 5.0))
	var c2: Crusher = _clam(Vector3(0, 3.2, -15.2), Vector3(3.2, 1.6, 2.2), 3.0, 2.6, 0.5)
	var p1: Dictionary = _blk(Vector3(0, 3.2, -23.5), 2.4, 2.4, "alt")
	var c3: Crusher = _clam(Vector3(0, 3.2, -23.5), Vector3(2.8, 1.6, 2.8), 3.0, 2.6, 0.0)
	var p2: Dictionary = _blk(Vector3(1.2, 3.2, -29.0), 2.4, 2.4, "alt")
	var c4: Crusher = _clam(Vector3(1.2, 3.2, -29.0), Vector3(2.8, 1.6, 2.8), 3.0, 2.6, 0.72)
	var cp: Dictionary = _cp(Vector3(0.6, 3.2, -37.2))
	_hop(cp0, w1, Vector3(0, 0, 2.6))
	r_until(func() -> bool: return _open(c1, 0.0, 0.9))
	r_walk(_w(Vector3(0, 0, -11.4)))
	r_until(func() -> bool: return _open(c2, 0.15, 1.3))
	r_mantle(_w(Vector3(0, 0, -11.65)), _w(Vector3(0, 3.2, -14.4)))
	r_walk(_w(Vector3(0, 3.2, -17.8)))
	r_until(func() -> bool: return _open(c3, 0.2, 1.2) and _open(c4, 0.8, 1.9))
	_hop(_area(Vector3(0, 3.2, -16.5), 1.7, 2.5), p1)
	_hop(p1, p2)
	_hop(p2, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 11: Wreck Chimney - three wall runs zig-zag up the split hull, mantle out of the last kick ------

func _stage_11() -> Vector3:
	_panel(2.3, 1.2, -6.0, -12.5)
	_panel(-2.3, 6.0, -11.0, -19.0)
	_panel(2.3, 9.0, -17.0, -25.0)
	_hull(3.1, -6.0, 13.5, -5.0, -26.0, 1.0)
	_hull(-3.1, -2.0, 10.5, -10.0, -20.0, -1.0)
	var top: Dictionary = _ledge(Vector3(-0.75, 11.9, -28.5), Vector3(4.5, 14.0, 4.0), "alt")
	var cp: Dictionary = _cp(Vector3(0, 11.9, -38.0))
	r_wallrun(_w(Vector3(0.5, 0, -2.6)), _w(Vector3(1.7, 1.4, -7.1)), _w(Vector3(1.7, 1.4, -10.0)), _w(Vector3(-1.7, 5.5, -13.9)))
	r_wallrun(Vector3.ZERO, _w(Vector3(-1.7, 5.5, -13.9)), _w(Vector3(-1.7, 5.5, -16.9)), _w(Vector3(1.7, 8.5, -20.5)), true, true)
	r_wallrun(Vector3.ZERO, _w(Vector3(1.7, 8.5, -20.5)), _w(Vector3(1.7, 8.5, -21.9)), _w(Vector3(-0.75, 11.9, -27.1)), true, true)
	_hop(top, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 12: Bloom Gauntlet (BRANCH) - jellies and blooming coral, or the coral portal up the side -------

func _stage_12() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var j1: ReefJelly = _jelly(Vector3(0, -1.5, -8.5), 17.0, 1.3, [Vector3(-1.8, 0, 0), Vector3(1.8, 0, 0)], 4.2, 0.0)
	var bl1: BlinkPlatform = kit.blink(_w(Vector3(0, 1.5, -15.6)), Vector3(2.2, 0.5, 2.2), 3.0, 0.6, 0.0)
	var bl2: BlinkPlatform = kit.blink(_w(Vector3(1.5, 2.5, -21.6)), Vector3(2.0, 0.5, 2.0), 3.0, 0.6, 0.45)
	var j2c := Vector3(1.5, 0.3, -28.0)
	_jelly(j2c, 18.0, 1.3, [], 5.0, 0.0, 0.0, 3.0, ReefDecor.CYAN)
	var merge: Dictionary = _blk(Vector3(0.5, 3.0, -36.0), 11.0, 5.0, "main", 1.2)
	var cp: Dictionary = _cp(Vector3(0.5, 3.0, -45.0))
	# the portal skip: three small coral heads up the right side to an orange ring in a coral arch
	var r1: Dictionary = _blk(Vector3(5.0, 1.0, -7.8), 1.4, 1.4, "accent", 0.7)
	var r2: Dictionary = _blk(Vector3(5.8, 2.0, -13.4), 1.3, 1.3, "accent", 0.7)
	var pp: Dictionary = _blk(Vector3(5.8, 3.0, -19.0), 2.4, 2.4, "accent", 0.8)
	var portal: WarpPortal = kit.portal(_w(Vector3(5.8, 3.0, -19.6)), _yaw, _w(Vector3(4.2, 3.0, -34.8)), _yaw, 7.0)
	for b: Dictionary in [r1, r2]:
		kit.glow_strip(_w((b["c"] as Vector3) + Vector3(0, 0.03, 0)), Vector3(0.5, 0.06, 0.5), WarpPortal.ENTRY_COLOR)
	kit.arch(_w(Vector3(5.8, 3.0, -19.6)), 3.6, 3.4, _yaw, ReefDecor.PINK.darkened(0.2))
	_portal_arrival(portal.exit_point())
	for side: float in [-1.0, 1.0]:
		deco.staghorn(_w(Vector3(5.8 + side * 2.0, 3.0, -19.6)), 1.3, ReefDecor.ORANGE)
	if route_variant != 1:
		r_walk(_w(Vector3(0, 0, -1.2)))
		r_until(func() -> bool: return _blink_on(bl1, 0.9, 2.3))
		r_jump_onto(_w(Vector3(0, 0, -2.65)), j1)
		r_pad(_w(Vector3(0, -1.5, -8.5)), _w(Vector3(0, 1.5, -15.4)))
		r_until(func() -> bool: return _blink_on(bl2, 0.2, 1.1))
		r_jump(_w(Vector3(0.3, 1.5, -16.4)), _w(Vector3(1.5, 2.5, -21.4)))
		r_jump(_w(Vector3(1.5, 2.5, -22.3)), _w(j2c))
		r_pad(_w(j2c), _w(Vector3(0.8, 3.0, -35.4)))
	else:
		r_jump(_w(Vector3(2.6, 0, -2.65)), _w(r1["c"]))
		_hop(r1, r2)
		_hop(r2, pp, Vector3(0, 0, 0.6))
		r_portal(_w(Vector3(5.8, 3.0, -19.6)), portal.exit_point())
	_hop(merge, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 13: Jet Stream - a current jet flings you over a chasm, a jellyfish carries the speed on -----------

func _stage_13() -> Vector3:
	kit.boost(_w(Vector3(0, 0, -8.5)), _sz(Vector3(2.4, 0.5, 11.0)), _yaw, 20.0)
	deco.pinnacle(_w(Vector3(0, -0.5, -9.0)), 1.0, 34.0)
	_blk(Vector3(0, -4.0, -36.0), 3.4, 12.0, "alt", 1.0, false)
	deco.pinnacle(_w(Vector3(0, -5.0, -33.0)), 1.1, 30.0)
	deco.pinnacle(_w(Vector3(0, -5.0, -39.5)), 0.9, 30.0)
	var jc := Vector3(0, -5.5, -46.0)
	_jelly(jc, 18.0, 1.4, [], 5.0, 0.0, 0.0, 3.0, ReefDecor.VIOLET)
	var l2: Dictionary = _blk(Vector3(0, -3.0, -56.25), 3.4, 8.5)
	_haz(Vector3(0, -2.3, -61.2), Vector3(3.4, 1.4, 0.5))
	var cp: Dictionary = _cp(Vector3(0, -5.0, -67.0))
	# the jet: streaming bubbles along the strip, a ring at its mouth
	for i: int in 3:
		var b: GPUParticles3D = ReefFx.bubble_stream(2.0, 10, 0.5, 0.2)
		b.position = _w(Vector3(0, 0.1, -4.5 - 3.5 * float(i)))
		add_child(b)
	kit.ring(_w(Vector3(0, 2.0, -14.2)), 1.9, ReefDecor.CYAN, Vector3(90, _yaw, 0))
	# SHORTCUT: a hidden portal on a 1 m knob tucked below the checkpoint's corner (a 90% leap) - out at L2
	var hk: Vector3 = Vector3(5.6, -1.0, -9.0)
	_blk(hk, 1.0, 1.0, "accent", 0.6)
	kit.portal(_w(hk), _yaw, _w(Vector3(0, -3.0, -52.6)), _yaw, 6.0)
	_portal_arrival(_w(Vector3(0, -3.0, -52.6)) + _b * Vector3(0, 0.15, -0.9))
	if route_variant == 2:
		r_jump(_w(Vector3(2.6, 0, -2.65)), _w(hk + Vector3(0, 0.3, 0)))
	else:
		r_walk(_w(Vector3(0, 0, -2.2)))
		r_jump(_w(Vector3(0, 0, -13.6)), _w(Vector3(0, -4.0, -33.0)))
		route[route.size() - 1]["speed"] = 20.0
		r_walk(_w(Vector3(0, -4.0, -40.5)))
		r_jump(_w(Vector3(0, -4.0, -41.65)), _w(jc))
		r_pad(_w(jc), _w(Vector3(0, -3.0, -56.5)))
	_hop(l2, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 14: Kelp Wall - wall run the kelp-hung cliff, kick onto a jellyfish, catch the ledge from the bounce ---

func _stage_14() -> Vector3:
	_panel(2.3, 1.0, -5.5, -19.0)
	for z: float in [-7.0, -11.0, -15.0]:
		deco.sea_fan(_w(Vector3(2.9, 4.6, z)), 1.6, ReefDecor.LIME)
	var jc := Vector3(-2.0, -3.0, -23.5)
	_jelly(jc, 20.0, 1.4, [], 5.0, 0.0, 0.0, 3.0, ReefDecor.PINK)
	var top: Dictionary = _ledge(Vector3(-2.0, 4.8, -31.0), Vector3(3.6, 9.0, 3.0))
	var cp: Dictionary = _cp(Vector3(-1.0, 4.8, -40.5))
	r_wallrun(_w(Vector3(0.5, 0, -2.6)), _w(Vector3(1.7, 1.4, -7.1)), _w(Vector3(1.7, 1.4, -15.0)), _w(jc))
	r_pad(_w(jc), _w((top["c"] as Vector3) + Vector3(0, 0, 0.3)))
	_hop(top, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 15: Moray Den - two coral heads swept by circling eels, down into the trench ------------------------

func _stage_15() -> Vector3:
	var d1: Dictionary = _disc(Vector3(0, -2.0, -10.0), 4.5, "alt")
	var e1: Sweeper = _eel_sweeper(Vector3(0, -2.0, -10.0), 4.2, 2, 3.4, 0.0)
	_disc(Vector3(1.0, -4.5, -23.5), 4.5, "alt")
	var e2: Sweeper = _eel_sweeper(Vector3(1.0, -4.5, -23.5), 4.2, 3, 4.2, 0.4)
	var cp: Dictionary = _cp(Vector3(0, -6.0, -36.0))
	# SHORTCUT: a wall-run panel along the den's flank - run it off the first disc, skip the second den
	_panel(6.3, -1.0, -13.0, -29.0)
	var land1: Vector3 = _w(Vector3(0, -2.0, -6.6))
	var land2: Vector3 = _w(Vector3(0.9, -4.5, -20.0))
	r_until(func() -> bool: return _bar_far(e1, land1, 0.4, 0.95, 0.8))
	_hop(_area(Vector3.ZERO, 3.0, 3.0), d1, Vector3(0, 0, 3.4))
	if route_variant == 2:
		route.append({"kind": "b_sweep", "to": _w(Vector3(2.4, -2.0, -9.6)), "sweeper": e1, "tol": 0.5})
		r_wallrun(_w(Vector3(3.6, -2.0, -11.6)), _w(Vector3(5.65, -0.6, -16.5)), _w(Vector3(5.65, -0.6, -25.0)), _w((cp["c"] as Vector3) + Vector3(1.0, 0, 1.4)))
		r_checkpoint()
		return cp["c"]
	route.append({"kind": "b_sweep", "to": _w(Vector3(0, -2.0, -13.9)), "sweeper": e1, "tol": 0.5})
	var d1n: Node3D = d1["node"]
	route.append({"kind": "h_hop", "node": d1n, "local": d1n.global_transform.affine_inverse() * _w(Vector3(0.1, -2.0, -13.9)), "sweepers": [e1],
			"until": func() -> bool: return _bar_far(e2, land2, 0.55, 0.85, 0.6)})
	r_jump(_w(Vector3(0.1, -2.0, -14.15)), land2)
	route.append({"kind": "b_sweep", "to": _w(Vector3(0.8, -4.5, -27.4)), "sweeper": e2, "tol": 0.5})
	r_jump(_w(Vector3(0.7, -4.5, -27.65)), _w((cp["c"] as Vector3) + Vector3(0, 0, 1.5)))
	r_checkpoint()
	return cp["c"]


# ---- stage 16: Abyssal Vents - ride a vent up through the eel-light grid, then the second vent into a mantle -------

func _stage_16() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var v1f: Dictionary = _blk(Vector3(0, 0, -9.5), 4.0, 6.0, "alt")
	var v1: ReefVent = _vent(Vector3(0, 0, -10.6), 9.0, 4.4, 0.0, 0.45)
	# the grid: beams across the column at 3.5 and 6 m, both ways
	var grid: Array[LaserGate] = []
	for h: float in [3.5, 6.0]:
		grid.append(kit.laser(_w(Vector3(0, h, -10.6)), Vector3(4.4, 0.22, 0.22), 2.2, 0.4, 0.4, _yaw))
		grid.append(kit.laser(_w(Vector3(0, h + 0.4, -10.6)), Vector3(4.4, 0.22, 0.22), 2.2, 0.4, 0.4, _yaw + 90.0))
	var s1: Dictionary = _blk(Vector3(0, 8.0, -17.4), 3.0, 3.0)
	var b1: Dictionary = _blk(Vector3(-2.0, 7.0, -23.4), 1.8, 1.8, "alt")
	var v2f: Dictionary = _blk(Vector3(-2.0, 4.5, -30.9), 3.6, 5.0, "alt")
	var v2: ReefVent = _vent(Vector3(-2.0, 4.5, -32.1), 4.5, 3.6, 0.3)
	var top: Dictionary = _ledge(Vector3(-2.0, 11.5, -35.4), Vector3(4.0, 9.0, 3.6))
	var cp: Dictionary = _cp(Vector3(-1.0, 11.5, -45.0))
	_urchin_behind(s1, b1)
	_hop(cp0, v1f, Vector3(0, 0, 1.8))
	r_walk(_w(Vector3(0, 0, -8.2)))
	_wait(func() -> bool: return _erupting(v1, 1.4) and _dark(grid[0], 0.0, 1.0))
	var s1y: float = _w(s1["c"]).y
	_fly(_w(Vector3(0, 0, -10.6)), func() -> bool: return player.global_position.y > s1y + 1.2)
	_fly(_w(s1["c"]))
	_hop(s1, b1)
	_hop(b1, v2f, Vector3(0, 0, 1.4))
	r_walk(_w(Vector3(-2.0, 4.5, -29.4)))
	_wait(func() -> bool: return _erupting(v2, 1.1))
	_fly(_w((top["c"] as Vector3) + Vector3(0, 0, 0.4)))
	_hop(top, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 17: The Sunken Temple - clam doors on the causeway, run the temple wall, mantle the steps, the gate ------

func _stage_17() -> Vector3:
	_blk(Vector3(0, 0, -8.5), 2.6, 11.0, "alt", 1.0, false)
	deco.pinnacle(_w(Vector3(0, -1.0, -9.0)), 1.0, 36.0)
	var c1: Crusher = _clam(Vector3(0, 0, -7.0), Vector3(3.0, 1.6, 2.4), 3.2, 2.4, 0.0)
	var c2: Crusher = _clam(Vector3(0, 0, -11.4), Vector3(3.0, 1.6, 2.4), 3.2, 2.4, 0.8)
	_panel(2.3, 1.0, -16.0, -30.0)
	var t1: Dictionary = _blk(Vector3(-1.5, 1.0, -34.0), 3.4, 3.4)
	_ledge(Vector3(-1.5, 4.2, -39.2), Vector3(4.0, 7.0, 3.0), "alt")
	_ledge(Vector3(-1.5, 7.4, -43.7), Vector3(4.0, 10.0, 3.0), "alt")
	_blk(Vector3(-1.5, 7.4, -47.0), 3.4, 3.6, "accent", 1.0, false)
	var fin: Dictionary = _blk(Vector3(0, 7.4, -53.3), 12.0, 9.0, "main", 1.6)
	var gate: LaserGate = _eel_fence(Vector3(-1.5, 7.4, -47.0), 3.4, [0.5, 1.4, 2.3], 2.0, 0.45, 0.2)
	kit.finish(_w(Vector3(0, 7.4, -54.0)), _yaw)
	_finish_pos = _w(Vector3(0, 7.4, -54.0))
	r_walk(_w(Vector3(0, 0, -4.6)))
	r_until(func() -> bool: return _open(c1, 0.0, 0.7) and _open(c2, 0.35, 1.2))
	r_walk(_w(Vector3(0, 0, -12.6)))
	r_wallrun(_w(Vector3(0.4, 0, -13.65)), _w(Vector3(1.7, 1.4, -17.6)), _w(Vector3(1.7, 1.4, -26.0)), _w(t1["c"]))
	r_mantle(_w(Vector3(-1.5, 1.0, -35.35)), _w(Vector3(-1.5, 4.2, -38.4)))
	r_mantle(_w(Vector3(-1.5, 4.2, -40.35)), _w(Vector3(-1.5, 7.4, -43.0)))
	r_until(func() -> bool: return _dark(gate, 0.05, 0.6))
	r_walk(_w(Vector3(-1.2, 7.4, -50.0)))
	r_walk(_w(Vector3(0, 7.4, -54.0)))
	return fin["c"]

# ---- environment ----------------------------------------------------------------------------------

func _restyle_environment() -> void:
	for n: Node in get_children():
		if n is WorldEnvironment:
			_env = (n as WorldEnvironment).environment
		elif n is DirectionalLight3D:
			if n.name == "Sun":
				_sun = n as DirectionalLight3D
			else:
				_fill = n as DirectionalLight3D
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	_env.sky.sky_material = sky_mat
	_env.fog_light_color = Color(0.05, 0.36, 0.46)
	_env.fog_density = 0.016
	_env.fog_aerial_perspective = 0.45
	_env.fog_sky_affect = 0.6
	_env.fog_sun_scatter = 0.0
	_env.fog_height = -18.0
	_env.fog_height_density = 0.012
	_env.ambient_light_color = Color(0.32, 0.72, 0.82)
	_env.ambient_light_energy = 0.78
	_env.glow_intensity = 0.85
	_env.glow_bloom = 0.12
	_env.glow_hdr_threshold = 1.05
	_env.adjustment_saturation = 1.22
	_env.adjustment_contrast = 1.06
	_sun.light_color = Color(0.72, 0.96, 1.0)
	_sun.light_energy = 1.15
	_sun.rotation_degrees = Vector3(-74, 25, 0)
	# the "fill" becomes a faint violet glow welling up from the abyss
	_fill.light_color = Color(0.45, 0.35, 0.9)
	_fill.light_energy = 0.3
	_fill.rotation_degrees = Vector3(62, 200, 0)


## Swap every walkable surface to the reef shader (same colours, sand and caustic light).
func _reef_materials() -> void:
	for mi: Node in find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi as MeshInstance3D
		var sm: ShaderMaterial = m.material_override as ShaderMaterial
		if sm == null or sm.shader != Look.PLATFORM_SHADER:
			continue
		var r := ShaderMaterial.new()
		r.shader = ROCK_SHADER
		for key: String in ["top_color", "side_color", "trim_color", "half_size", "is_round", "trim_glow"]:
			r.set_shader_parameter(key, sm.get_shader_parameter(key))
		m.material_override = r


## Every point the route passes (takeoffs, landings, walk targets) - background set dressing keeps clear of them.
func _route_points() -> Array[Vector3]:
	var pts: Array[Vector3] = []
	for st: Dictionary in route:
		for key: String in ["from", "to", "entry", "exit", "top"]:
			if st.has(key) and st[key] is Vector3 and (st[key] as Vector3) != Vector3.ZERO:
				pts.append(st[key])
	for p: Vector3 in _cp_world:
		pts.append(p)
	return pts


func _clear_of(p: Vector3, pts: Array[Vector3], dist: float) -> bool:
	for q: Vector3 in pts:
		if Vector2(p.x - q.x, p.z - q.z).length() < dist and p.y < q.y + 30.0:
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
	# the sea surface far overhead, and god rays slanting down from it
	var sea_top: float = hi.y + 95.0
	deco.surface(Vector3(mid.x, sea_top, mid.z), maxf(span.x, span.z) + 500.0)
	for i: int in 22:
		var p := Vector3(rng.randf_range(lo.x - 50.0, hi.x + 50.0), sea_top - 2.0, rng.randf_range(lo.z - 50.0, hi.z + 50.0))
		deco.light_shaft(p, rng.randf_range(170.0, 230.0), rng.randf_range(3.0, 7.0), rng.randf_range(10.0, 22.0), Vector3(rng.randf_range(-0.14, 0.14), 0, rng.randf_range(-0.1, 0.1)))
	# the sea floor: pale sand, dunes, boulders; kelp forests swaying up out of it
	var floor_y: float = -46.0
	var sand := PlaneMesh.new()
	sand.size = Vector2(span.x + 700.0, span.z + 700.0)
	var sand_mi := Look.mesh_node(sand, Look.flat(Color(0.55, 0.52, 0.42), 1.0), Vector3(mid.x, floor_y, mid.z))
	sand_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sand_mi)
	for i: int in 40:
		var d := Look.sphere(1.0, Look.flat(Color(0.6, 0.56, 0.45), 1.0), Vector3(rng.randf_range(lo.x - 120.0, hi.x + 120.0), floor_y - 2.0, rng.randf_range(lo.z - 120.0, hi.z + 120.0)))
		d.scale = Vector3(rng.randf_range(12.0, 30.0), rng.randf_range(2.5, 5.0), rng.randf_range(8.0, 20.0))
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(d)
	for i: int in 9:
		var c := Vector3(rng.randf_range(lo.x - 40.0, hi.x + 40.0), floor_y, rng.randf_range(lo.z - 40.0, hi.z + 40.0))
		deco.kelp_forest(c, Vector2(rng.randf_range(18.0, 34.0), rng.randf_range(18.0, 34.0)), 60, 18.0, 40.0)
	# coral mountains: huge crusted spires crowned with giant coral, well clear of the route
	var placed: int = 0
	var tries: int = 0
	while placed < 26 and tries < 400:
		tries += 1
		var p := Vector3(rng.randf_range(lo.x - 90.0, hi.x + 90.0), 0.0, rng.randf_range(lo.z - 90.0, hi.z + 90.0))
		if not _clear_of(p + Vector3(0, -50, 0), pts, 26.0):
			continue
		var top_y: float = rng.randf_range(lo.y - 10.0, hi.y + 20.0)
		p.y = top_y
		var r: float = rng.randf_range(3.0, 7.0)
		deco.pinnacle(p, r, top_y - floor_y + 4.0)
		var col: Color = deco.glow_color()
		deco.staghorn(p + Vector3(0, -0.5, 0), r * 0.9, col)
		deco.brain(p + Vector3(r * 0.6, -0.8, r * 0.3), r * 0.6)
		deco.sea_fan(p + Vector3(-r * 0.5, -0.6, -r * 0.4), r * 1.6)
		if rng.randf() < 0.6:
			var b: GPUParticles3D = ReefFx.bubble_stream(40.0, 10, r * 0.4, 0.3)
			b.position = p + Vector3(0, 0.2, 0)
			add_child(b)
		placed += 1
	_wreck()
	_temple()
	# schools of fish and gliding mantas
	for i: int in _cp_world.size():
		if i % 2 == 1:
			continue
		var s := ReefSchool.new()
		s.count = rng.randi_range(24, 40)
		s.radius = rng.randf_range(3.0, 5.0)
		s.wander = Vector3(rng.randf_range(6.0, 12.0), 2.0, rng.randf_range(6.0, 12.0))
		s.speed = rng.randf_range(0.35, 0.6)
		var cols: Array[Color] = [Color(0.95, 0.85, 0.35), Color(0.5, 0.85, 1.0), Color(1.0, 0.55, 0.4), Color(0.7, 1.0, 0.6)]
		s.color_a = cols[rng.randi() % cols.size()]
		s.color_b = cols[rng.randi() % cols.size()]
		var side: float = -1.0 if rng.randf() < 0.5 else 1.0
		s.position = _cp_world[i] + Vector3(side * rng.randf_range(16.0, 24.0), rng.randf_range(2.0, 9.0), rng.randf_range(-12.0, 12.0))
		add_child(s)
	for i: int in 4:
		var c := Vector3(rng.randf_range(lo.x, hi.x), rng.randf_range(hi.y + 12.0, hi.y + 30.0), rng.randf_range(lo.z, hi.z))
		_manta(c, rng.randf_range(30.0, 55.0), rng.randf_range(28.0, 45.0) * (1.0 if i % 2 == 0 else -1.0))
	# ambient life along the whole route: marine snow sinking, plankton glinting, a bubble haze
	for i: int in _cp_world.size():
		var here: Vector3 = _cp_world[i]
		var nxt: Vector3 = _cp_world[i + 1] if i + 1 < _cp_world.size() else _finish_pos
		var c: Vector3 = (here + nxt) * 0.5 + Vector3(0, 5.0, 0)
		var ext := Vector3(absf(nxt.x - here.x) + 34.0, 26.0, absf(nxt.z - here.z) + 34.0)
		var snow: GPUParticles3D = ReefFx.marine_snow(ext, 90)
		snow.position = c
		add_child(snow)
		var glint: GPUParticles3D = ReefFx.plankton(ext * Vector3(0.8, 0.7, 0.8), deco.glow_color(), 44)
		glint.position = c
		add_child(glint)
	var start_snow: GPUParticles3D = ReefFx.marine_snow(Vector3(40, 24, 40), 80)
	start_snow.position = Vector3(0, 6, -10)
	add_child(start_snow)
	var start_glint: GPUParticles3D = ReefFx.plankton(Vector3(30, 14, 30), ReefDecor.CYAN, 40)
	start_glint.position = Vector3(0, 4, -12)
	add_child(start_glint)


## A manta ray gliding round a wide circle (visual only).
func _manta(center: Vector3, radius: float, period: float) -> void:
	var holder := Node3D.new()
	holder.set_script(preload("res://visual/spin.gd"))
	holder.set("period", period)
	var m := Node3D.new()
	var skin: StandardMaterial3D = Look.flat(Color(0.12, 0.16, 0.24), 0.6)
	var glow: StandardMaterial3D = Look.flat(ReefDecor.CYAN, 0.3, 0.0, 1.8)
	var body := Look.sphere(1.0, skin)
	body.scale = Vector3(1.4, 0.35, 2.2)
	m.add_child(body)
	for side: float in [-1.0, 1.0]:
		var wing := Node3D.new()
		wing.set_script(preload("res://visual/reef_sway.gd"))
		wing.set("amount", 0.22)
		wing.set("speed", 1.4)
		wing.set("offset", 0.0 if side > 0.0 else PI)
		var pm := PrismMesh.new()
		pm.size = Vector3(4.2, 0.18, 2.6)
		var w := Look.mesh_node(pm, skin, Vector3(side * 2.4, 0, 0.2))
		w.rotation = Vector3(PI * 0.5, 0, side * PI * 0.5)
		wing.add_child(w)
		wing.add_child(Look.box(Vector3(2.8, 0.06, 0.12), glow, Vector3(side * 2.0, 0.1, 0.2)))
		m.add_child(wing)
	var tail := Look.cylinder(0.06, 3.5, skin, Vector3(0, 0, 3.6), 0.02, 6)
	tail.rotation.x = PI * 0.5
	m.add_child(tail)
	m.position = Vector3(radius, 0, 0)
	m.rotation.y = PI if period > 0.0 else 0.0
	holder.add_child(m)
	holder.position = center
	add_child(holder)


## The wreck the Hull Run and Cannon Deck stages cross: a listing hull under the decks, ribs, a broken bow.
func _wreck() -> void:
	if _cp_world.size() < 6:
		return
	var a: Vector3 = _cp_world[4]
	var b: Vector3 = _cp_world[5]
	var wood: StandardMaterial3D = Look.flat(Color(0.28, 0.2, 0.15), 0.95)
	var dark: StandardMaterial3D = Look.flat(Color(0.16, 0.12, 0.1), 0.95)
	var rust: StandardMaterial3D = Look.flat(Color(0.45, 0.28, 0.18), 0.8, 0.3)
	var glass: StandardMaterial3D = Look.flat(Color(1.0, 0.8, 0.45), 0.3, 0.0, 2.0)
	var hull := Node3D.new()
	var length: float = b.x - a.x + 2.0
	var h: float = 14.0
	hull.add_child(Look.box(Vector3(length, h, 10.5), wood, Vector3(0, -h * 0.5 - 1.0, 0)))
	hull.add_child(Look.box(Vector3(length - 4.0, 4.0, 7.0), wood, Vector3(0, -h - 3.0, 0)))
	for i: int in int(length / 3.0):
		var x: float = -length * 0.5 + 1.5 + float(i) * 3.0
		hull.add_child(Look.box(Vector3(0.45, h + 0.4, 11.0), dark, Vector3(x, -h * 0.5 - 1.0, 0)))
	for i: int in int(length / 5.0):
		var x2: float = -length * 0.5 + 3.0 + float(i) * 5.0
		for side: float in [-1.0, 1.0]:
			var port := Look.cylinder(0.4, 0.3, glass, Vector3(x2, -4.0, side * 5.3), -1.0, 12)
			port.rotation.x = PI * 0.5
			hull.add_child(port)
	# an anchor chain hanging off the side, and a rusted cannon or two poking out
	for i: int in 3:
		var cn := Look.cylinder(0.35, 2.4, rust, Vector3(-length * 0.25 + float(i) * length * 0.25, -2.2, 5.6), 0.28, 10)
		cn.rotation.x = PI * 0.5
		hull.add_child(cn)
	hull.position = Vector3((a.x + b.x) * 0.5 + 1.0, a.y - 1.0, a.z)
	hull.rotation.x = deg_to_rad(-5.0)
	add_child(hull)
	for i: int in 4:
		var bs: GPUParticles3D = ReefFx.bubble_stream(24.0, 8, 0.4, 0.26)
		bs.position = hull.position + Vector3(-length * 0.4 + float(i) * length * 0.27, -8.0, 5.8)
		add_child(bs)


## The sunken temple behind the finish: a stepped ziggurat with glowing glyph bands, and pillars down the causeway.
func _temple() -> void:
	if _finish_pos == Vector3.ZERO:
		return
	_frame(_cp_world[_cp_world.size() - 1], 0.0)
	var stone: StandardMaterial3D = Look.flat(Color(0.42, 0.46, 0.5), 0.9)
	var moss: StandardMaterial3D = Look.flat(Color(0.28, 0.42, 0.3), 0.95)
	var glyph: StandardMaterial3D = Look.flat(ReefDecor.CYAN, 0.3, 0.0, 2.6)
	var base: Vector3 = _finish_pos + Vector3(0, 0, -16.0)
	for i: int in 4:
		var w: float = 34.0 - float(i) * 7.0
		var y: float = base.y - 6.0 + float(i) * 5.0
		kit.block(Vector3(base.x, y, base.z - float(i) * 2.0), Vector3(w, 5.0, 16.0 - float(i) * 2.5), stone.albedo_color, false)
		kit.glow_strip(Vector3(base.x, y + 1.2, base.z - float(i) * 2.0 + (8.0 - float(i) * 1.25) + 0.05), Vector3(w - 2.0, 0.25, 0.1), ReefDecor.CYAN)
		add_child(Look.box(Vector3(w + 0.2, 0.5, 16.2 - float(i) * 2.5), moss, Vector3(base.x, y + 2.45, base.z - float(i) * 2.0)))
	# the shrine on top and its beacon
	var top := Vector3(base.x, base.y + 11.5, base.z - 6.0)
	kit.arch(top, 6.0, 6.0, 0.0, Color(0.42, 0.46, 0.5))
	add_child(Look.sphere(1.3, Look.flat(Color(0.6, 1.0, 0.95), 0.2, 0.0, 3.5), top + Vector3(0, 3.2, 0)))
	var beacon := OmniLight3D.new()
	beacon.light_color = ReefDecor.CYAN
	beacon.light_energy = 3.0
	beacon.omni_range = 40.0
	beacon.position = top + Vector3(0, 3.2, 0)
	add_child(beacon)
	var rise: GPUParticles3D = ReefFx.bubble_stream(60.0, 24, 1.2, 0.35)
	rise.position = top + Vector3(0, 4.0, 0)
	add_child(rise)
	var halo: GPUParticles3D = ReefFx.plankton(Vector3(16, 12, 16), ReefDecor.CYAN, 60)
	halo.position = top + Vector3(0, 3.0, 0)
	add_child(halo)
	# pillars lining the causeway and the finish terrace
	for k: int in 4:
		for side: float in [-1.0, 1.0]:
			var p: Vector3 = _w(Vector3(side * 4.2, 0, -4.0 - float(k) * 3.4))
			kit.block(p + Vector3(0, -3.0, 0), Vector3(1.1, 9.0, 1.1), stone.albedo_color, false)
			add_child(Look.box(Vector3(1.4, 0.4, 1.4), glyph, p + Vector3(0, 1.6, 0)))
	for side: float in [-1.0, 1.0]:
		var gp: Vector3 = _finish_pos + Vector3(side * 5.2, 0, -2.5)
		kit.block(gp + Vector3(0, 4.0, 0), Vector3(1.6, 8.0, 1.6), stone.albedo_color, false)
		add_child(Look.sphere(0.6, glyph, gp + Vector3(0, 8.6, 0)))
		var sp: GPUParticles3D = _sparks(ReefDecor.CYAN, 18, Vector3(0.8, 0.8, 0.8))
		sp.position = gp + Vector3(0, 8.6, 0)
		add_child(sp)


# ---- live effects: the water darkens as you go deeper, clams puff sand, portals and the gate burst ----------

## Water colours at the reef crest (0) and in the temple deep (1); the level blends along the checkpoints.
const SHALLOW_FOG := Color(0.05, 0.36, 0.46)
const DEEP_FOG := Color(0.03, 0.12, 0.3)
const SHALLOW_AMBIENT := Color(0.32, 0.72, 0.82)
const DEEP_AMBIENT := Color(0.36, 0.42, 0.9)

var _depth: float = 0.0
## [crusher, burst, was_down] for every clam: a puff of sand and bubbles each time it slams shut.
var _clam_puffs: Array[Array] = []
var _portal_bursts: Array[Array] = []


func _ready() -> void:
	super()
	player.teleported.connect(_on_teleported)


func _process(dt: float) -> void:
	if _env == null or player == null:
		return
	var target: float = clampf(float(current_checkpoint) / float(maxi(checkpoints.size(), 1)), 0.0, 1.0)
	_depth = move_toward(_depth, target, dt * 0.08)
	_env.fog_light_color = SHALLOW_FOG.lerp(DEEP_FOG, _depth)
	_env.ambient_light_color = SHALLOW_AMBIENT.lerp(DEEP_AMBIENT, _depth)
	_env.ambient_light_energy = lerpf(0.78, 0.62, _depth)
	_env.glow_intensity = lerpf(0.85, 1.15, _depth)
	_sun.light_energy = lerpf(1.15, 0.7, _depth)
	var t: float = Game.course_time
	for rec: Array in _clam_puffs:
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


## A ring of sand and bubbles thrown out from under a clam when it slams (one-shot, re-fired by _process).
func _clam_puff(cr: Crusher, floor_world: Vector3, size: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.amount = 36
	p.lifetime = 1.2
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 0.95
	p.visibility_aabb = AABB(Vector3(-8, -2, -8), Vector3(16, 8, 16))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = maxf(size.x, size.z) * 0.55
	pm.emission_ring_inner_radius = maxf(size.x, size.z) * 0.4
	pm.emission_ring_height = 0.1
	pm.direction = Vector3(0, 0.4, 0)
	pm.spread = 80.0
	pm.initial_velocity_min = 2.5
	pm.initial_velocity_max = 5.0
	pm.gravity = Vector3(0, -1.5, 0)
	pm.damping_min = 2.5
	pm.damping_max = 4.0
	pm.scale_min = 0.6
	pm.scale_max = 1.5
	pm.color_ramp = ReefFx.fade_ramp(Color(0.95, 0.88, 0.7), 0.8)
	p.process_material = pm
	p.draw_pass_1 = ReefFx.dot_quad(0.45, false)
	p.position = floor_world + Vector3(0, 0.2, 0)
	add_child(p)
	var bub: GPUParticles3D = ReefFx.burst(Color(0.8, 1.0, 1.0), 20, 4.0, true, 0.3, maxf(size.x, size.z) * 0.4)
	bub.position = floor_world + Vector3(0, 0.3, 0)
	add_child(bub)
	_clam_puffs.append([cr, p, false])
	_clam_puffs.append([cr, bub, false])


## Arrival flourish at a portal exit: a burst of bubbles and orange-blue glints (fired on teleport).
func _portal_arrival(exit_world: Vector3) -> void:
	var a: GPUParticles3D = ReefFx.burst(Color(0.6, 0.85, 1.0), 44, 7.0, true, 0.35, 1.2)
	a.position = exit_world + Vector3(0, 1.2, 0)
	add_child(a)
	var g: GPUParticles3D = ReefFx.burst(WarpPortal.ENTRY_COLOR, 30, 8.0, false, 0.28, 0.8)
	g.position = exit_world + Vector3(0, 1.2, 0)
	add_child(g)
	_portal_bursts.append([exit_world, [a, g]])
	# a lazy swirl of plankton hangs round every exit ring so it reads from afar
	var halo: GPUParticles3D = ReefFx.plankton(Vector3(4, 4, 4), Color(0.45, 0.75, 1.0), 26)
	halo.position = exit_world + Vector3(0, 1.4, 0)
	add_child(halo)


## The temple gate: a fountain of bubbles, glints and a flash of light when you reach it.
func _finish_sequence() -> void:
	var col: Array[Color] = [ReefDecor.CYAN, ReefDecor.PINK, LedgeBlock.LIP_COLOR]
	for i: int in 3:
		var b: GPUParticles3D = ReefFx.burst(col[i], 60, 9.0 + 2.0 * float(i), i == 0, 0.4, 1.6)
		b.position = _finish_pos + Vector3(0, 1.0 + float(i), 0)
		b.lifetime = 1.8
		add_child(b)
		b.restart()
		b.emitting = true
	var flash := OmniLight3D.new()
	flash.light_color = ReefDecor.CYAN
	flash.light_energy = 6.0
	flash.omni_range = 18.0
	flash.position = _finish_pos + Vector3(0, 3.0, 0)
	add_child(flash)
	var tw: Tween = create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 1.2)
	await get_tree().create_timer(0.9).timeout
