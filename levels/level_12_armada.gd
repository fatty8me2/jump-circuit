extends LevelBase
## 12. STORM ARMADA - a sky-pirate fleet battling through a thunderstorm high above the clouds; you
## cross it ship to ship. Eighteen stages, each ending on a checkpoint (the deck of a little sloop
## hung under its gas bag): from the sky dock out across gangplanks, mast tops, cannon-swept
## gangways, rolling skiffs, propeller updrafts, cargo ropeways, lightning-struck spars, gun-port
## rams, balloon crowns and rope swings, through the great broadside, and up the flagship's gun tower
## to its quarterdeck - climbing all the way toward the sunset breaking through the storm ahead.
##
##  1 Sky Dock          cargo floats, the first GANGPLANK that runs in and out of a hull
##                      [shortcut: MANTLE the cargo stack, leap over the gangplank]
##  2 Mainsail          MANTLE the poop, hop the mast tops of the galleon below, WALL RUN the sail
##  3 Crossfire         three gangways swept by CANNON lanes firing in a rolling volley
##  4 Skiff Hop         three ROLLING skiffs heaving and rolling in the storm
##                      [shortcut: three 1 m buoy barrels beside them]
##  5 Stern Lift        BRANCH: ride a PROPELLER updraft up and hop the buoys | MANTLE the stern,
##                      WALL RUN the hull, MANTLE again
##  6 Cargo Ropeway     ride a cargo pallet down a ZIP-LINE, cross a LIGHTNING ROD's circle, ride
##                      the next pallet back up
##  7 Lightning Spars   narrow yards: two LIGHTNING RODS and a tesla arc (LASER)
##  8 Gun Port Rams     a walkway along a warship's side while its guns run out (PISTONS), two
##                      MANTLES up, the last under a falling cargo weight (CRUSHER)
##  9 Balloon Crowns    BRANCH: a bounce pad up onto the gas bags and run their crowns | two ROPE
##                      SWINGS under them
## 10 THE BROADSIDE     the set piece: sprint your ship's shattered deck while the enemy galleon
##                      alongside fires rippling broadsides across every hole (and your guns answer)
## 11 Rope Swings       ROPE SWINGS over the void, crumbling cargo between them
##                      [shortcut: two 1 m buoys past the second swing]
## 12 Anchor Drop       three anchors dropping on a wave (CRUSHERS), a WALL RUN along a hull
## 13 Storm Eye         BRANCH: two LIGHTNING ROD spars | MANTLE, WALL RUN, MANTLE and dive through the
##                      storm's eye (PORTAL)
## 14 The Falling Mast  a topmast topples across the gap on the clock - run it before the winch
##                      hauls it back, with a CANNON lane across it; then a ROLLING skiff
##                      [shortcut: two 1 m buoys that skip the skiff]
## 15 Gun Tower         a PROPELLER lifts you up the tower, a chimney of three WALL RUNS, MANTLE out
## 16 Cargo Hooks       slow swinging cargo hooks (hammers) over the stepping stones, crumbling crates,
##                      a tesla arc (LASER)
## 17 Boarding Planks   two GANGPLANKS in turn onto the flagship, two MANTLES up its side, a boarding
##                      ram (PISTON) over the last gap
## 18 The Flagship      a LIGHTNING ROD, the last CANNON lane, the last WALL RUN along the great
##                      mainsail, MANTLE onto the quarterdeck - the finish at the helm as the sunset
##                      breaks through
##
## Armada mechanics (own scripts): ArmadaCannon (clock-fired cannon lanes with a warning glow),
## ArmadaDeck (rolling, heaving skiffs), ArmadaLightning (rods struck on a clock, a danger circle),
## ArmadaPropeller (lift fans: updrafts), ArmadaSwing (rope swings), ArmadaMast (the toppling mast),
## plus gangplanks and zip-line pallets built from movers. Route variants for the bot: 0 = main line,
## 1 = every alternative branch, 2 = main line + every shortcut.

const WOOD_SHADER: Shader = preload("res://visual/armada_wood.gdshader")

const BRASS := Color(1.0, 0.72, 0.3)
const BLUE := Color(0.4, 0.75, 1.0)
const RED := Color(1.0, 0.3, 0.2)
const GREEN := Color(0.35, 1.0, 0.55)

var _o: Vector3 = Vector3.ZERO
var _b: Basis = Basis.IDENTITY
var _yaw: float = 0.0
var _next_yaw: float = 0.0
var deco: ArmadaDecor
var storm: ArmadaStorm
var _env: Environment
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
var _cloud_mat: ShaderMaterial
## World-space checkpoint positions in build order (set dressing along the route).
var _cp_world: Array[Vector3] = []
var _cp_bursts: Dictionary = {}
var _finish_pos: Vector3 = Vector3.ZERO
## Bursts that fire when the player arrives at a spot (portal exits): {"at", "p": [GPUParticles3D], "cool"}
var _arrivals: Array[Dictionary] = []
## Stage frames (origin, yaw) - for the fleet and the weather round the route.
var _stage_frames: Array[Array] = []
var _house: int = 0
## Every ship hull built (centre, yaw, length, beam, depth, envelope height or -1): the clearance check
## in tests/scratch keeps them off the route.
var hulls: Array[Array] = []


func _configure() -> void:
	theme_id = "armada"
	music_track = "armada"
	kill_y = -30.0
	# 0 = main line, 1 = every alternative branch, 2 = main line taking every optional shortcut
	route_variants = 3


# ---- local-frame helpers --------------------------------------------------------------------

func _frame(origin: Vector3, yaw_deg: float) -> void:
	_o = origin
	_yaw = yaw_deg
	_b = Basis(Vector3.UP, deg_to_rad(yaw_deg))


func _w(l: Vector3) -> Vector3:
	return _o + _b * l


func _d(v: Vector3) -> Vector3:
	return _b * v


## A local size (x across, z along) turned into world axes (frames only turn in 90 degree steps).
func _sz(size: Vector3) -> Vector3:
	return Vector3(size.z, size.y, size.x) if absf(fmod(absf(_yaw), 180.0) - 90.0) < 1.0 else size


func _area(c: Vector3, hx: float, hz: float) -> Dictionary:
	return {"c": c, "hx": hx, "hz": hz}


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


func _next_house() -> int:
	_house += 1
	return _house


# ---- walkable pieces ---------------------------------------------------------------------------

## A plank landing. `dress`: "float" = a cargo crate hung under a little gas bag; "spar" = a yard
## (narrow timber on iron brackets); "none" = bare (a ship deck the caller dresses).
func _blk(c: Vector3, sx: float, sz: float, style: String = "main", thick: float = 0.8, dress: String = "float") -> Dictionary:
	kit.plat(_w(c), Vector3(sx, thick, sz), style, 0.0, _yaw)
	match dress:
		"float":
			_float(c, sx, sz, thick)
		"spar":
			_spar_dress(c, sx, sz, thick)
	return {"c": c, "hx": sx * 0.5, "hz": sz * 0.5}


## A round landing: a barrel buoy (a drum top with its barrel under it and a little gas bag over it).
func _drum(c: Vector3, r: float, style: String = "main", thick: float = 0.7, bag: bool = true) -> Dictionary:
	kit.disc(_w(c), r, thick, style, 0.0)
	var wood: StandardMaterial3D = Look.flat(Color(0.42, 0.27, 0.15), 0.8)
	var iron: StandardMaterial3D = Look.flat(ArmadaDecor.IRON, 0.5, 0.7)
	var h: float = maxf(r * 1.8, 1.2)
	add_child(Look.cylinder(r * 0.92, h, wood, _w(c - Vector3(0, thick + h * 0.5, 0)), r * 0.8, 16))
	for f: float in [0.25, 0.8]:
		add_child(Look.cylinder(r * 0.95, 0.08, iron, _w(c - Vector3(0, thick + h * f, 0)), -1.0, 16))
	if bag:
		_bag(c, r * 1.6, r * 1.6)
	return {"c": c, "r": r}


## The little gas bag a cargo float hangs from, `lift` metres over its top, on four lines.
func _bag(c: Vector3, sx: float, sz: float, lift: float = 6.2) -> void:
	var cols: Array = ArmadaDecor.ENVELOPES[(_house + int(absf(c.z))) % ArmadaDecor.ENVELOPES.size()]
	var rad: float = clampf(maxf(sx, sz) * 0.42 + 0.5, 1.0, 2.4)
	var ln: float = clampf(maxf(sx, sz) * 1.2 + 2.0, 3.0, 12.0)
	var top: Vector3 = c + Vector3(0, lift + rad, 0)
	deco.envelope(_w(top), _yaw, ln, rad, cols, false)
	var rope: StandardMaterial3D = Look.flat(ArmadaDecor.ROPE, 0.9)
	for cx: float in [-1.0, 1.0]:
		for cz: float in [-1.0, 1.0]:
			var a := Vector3(cx * (sx * 0.5 + 0.02), 0.05, cz * (sz * 0.5 + 0.02))
			var b2 := Vector3(cx * minf(maxf(rad * 0.5, sx * 0.5 + 0.1), rad * 0.9), lift + rad * 0.3, cz * minf(maxf(ln * 0.25, sz * 0.5 + 0.1), ln * 0.45))
			add_child(deco.line(_w(c + a), _w(c + b2), 0.03, rope))


## A crate under a float's plank top, and its gas bag.
func _float(c: Vector3, sx: float, sz: float, thick: float) -> void:
	var h: float = clampf(minf(sx, sz) * 0.6, 0.8, 1.6)
	var crate := Look.box(Vector3(sx * 0.86, h, sz * 0.86), Look.flat(Color(0.5, 0.35, 0.2), 0.85), _w(c - Vector3(0, thick + h * 0.5, 0)))
	crate.rotation.y = deg_to_rad(_yaw)
	add_child(crate)
	var band := Look.box(Vector3(sx * 0.9, 0.1, sz * 0.9), Look.flat(ArmadaDecor.IRON, 0.5, 0.7), _w(c - Vector3(0, thick + h * 0.5, 0)))
	band.rotation.y = deg_to_rad(_yaw)
	add_child(band)
	if maxf(sx, sz) <= 5.0:
		_bag(c, sx, sz)


## A yard: iron brackets under a narrow timber, a furled sail lashed beneath.
func _spar_dress(c: Vector3, sx: float, sz: float, thick: float) -> void:
	var along_z: bool = sz >= sx
	var ln: float = maxf(sx, sz)
	var furl := Look.cylinder(0.35, ln * 0.9, deco.canvas_mat(ArmadaDecor.CANVAS.darkened(0.1)), _w(c - Vector3(0, thick + 0.35, 0)), -1.0, 10)
	furl.basis = _b * (Basis(Vector3.RIGHT, PI * 0.5) if along_z else Basis(Vector3.BACK, PI * 0.5))
	add_child(furl)
	_bag(c, sx + 1.0, sz, 6.5)


func _ledge(top: Vector3, size: Vector3, style: String = "main") -> Dictionary:
	kit.ledge(_w(top), size, _yaw, style)
	return {"c": top, "hx": size.x * 0.5, "hz": size.z * 0.5}


## A ship: its walkable deck (the square part of the hull, `deck_len` along the ship's axis, `beam`
## across), the lofted hull under it with a walkable bow, and (optionally) its gas envelope, masts
## and lift propellers. `c` = the deck's centre (local), `axis` = the bow's heading relative to the
## frame (0 = forward, 90 = to the left, -90 = to the right).
func _ship(c: Vector3, deck_len: float, beam: float, axis: float, opts: Dictionary = {}) -> Node3D:
	var yaw: float = _yaw + axis
	var hb := Basis(Vector3.UP, deg_to_rad(yaw))
	var length: float = deck_len / ArmadaDecor.BOW
	var depth: float = float(opts.get("depth", clampf(beam * 0.6, 2.4, 6.5)))
	kit.plat(_w(c), Vector3(beam, 0.6, deck_len), "main", 0.0, yaw)
	var center: Vector3 = _w(c) - hb * Vector3(0, 0, length * (0.5 - ArmadaDecor.BOW * 0.5))
	var house: int = int(opts.get("house", _next_house()))
	hulls.append([center, yaw, length, beam, depth, float(opts.get("env_y", 11.0)) if bool(opts.get("envelope", true)) else -1.0])
	var n: Node3D = deco.hull(center, yaw, length, beam, depth, ArmadaDecor.PAINTS[house % ArmadaDecor.PAINTS.size()],
		{"castle": bool(opts.get("castle", false)), "rails": bool(opts.get("rails", true)), "lit": 0.45})
	if bool(opts.get("envelope", true)):
		var ey: float = float(opts.get("env_y", 11.0))
		var er: float = float(opts.get("env_r", clampf(beam * 0.55, 2.8, 7.0)))
		deco.envelope(center + Vector3(0, ey + er, 0), yaw, length * 1.05, er, ArmadaDecor.ENVELOPES[house % ArmadaDecor.ENVELOPES.size()])
		var ropem: StandardMaterial3D = Look.flat(ArmadaDecor.ROPE, 0.9)
		for sx: float in [-1.0, 1.0]:
			for f: float in [-0.3, 0.05, 0.4]:
				var a: Vector3 = center + hb * Vector3(sx * (beam * 0.5 + 0.05), 0.1, f * length)
				var b2: Vector3 = center + hb * Vector3(sx * er * 0.55, ey + er * 0.2, f * length * 0.95)
				add_child(deco.line(a, b2, 0.05, ropem))
	if bool(opts.get("props", true)):
		for sx: float in [-1.0, 1.0]:
			var pp: Vector3 = center + hb * Vector3(sx * (beam * 0.5 + 1.6), -depth * 0.35, length * 0.3)
			add_child(deco.line(center + hb * Vector3(sx * beam * 0.45, -depth * 0.35, length * 0.3), pp, 0.12, Look.flat(ArmadaDecor.IRON, 0.5, 0.7)))
			deco.propeller(pp + hb * Vector3(0, 0, 0.6), 1.4, Vector3(0, rad_to_deg(yaw), 0), 0.25 if sx > 0.0 else -0.25)
	for m: float in opts.get("masts", []):
		deco.mast(center + hb * Vector3(0, 0, m * length), float(opts.get("mast_h", 12.0)), yaw, beam * 1.1)
	return n


## Checkpoint on the deck of a little sloop, facing the next stage's heading (_next_yaw). Its bow
## points away from where the next stage leaves.
func _cp(c: Vector3, size: float = 6.0) -> Dictionary:
	var turn: float = wrapf(_next_yaw - _yaw, -180.0, 180.0)
	var axis: float = 90.0 if turn < -1.0 else -90.0
	if absf(turn) < 1.0:
		axis = 90.0 if (_cp_world.size() % 2) == 0 else -90.0
	_ship(c, size, size, axis, {"env_y": 11.5, "depth": 3.2})
	var cp: Checkpoint = kit.checkpoint(_w(c), _next_yaw)
	_cp_world.append(_w(c))
	# lanterns on posts at the back corners (clear of the checkpoint's pylons and the way on)
	var back: Vector3 = Basis(Vector3.UP, deg_to_rad(_next_yaw - _yaw)) * Vector3(0, 0, 1)
	for s: float in [-1.0, 1.0]:
		var side := Vector3(-back.z, 0, back.x) * s
		deco.lamp_post(_w(c + back * (size * 0.5 - 0.35) + side * (size * 0.5 - 0.35)), 2.6, s < 0.0)
	# banked-stage feedback: the sloop's whistle blows steam and brass sparks fly
	var burst: GPUParticles3D = ArmadaFx.steam_burst(self, _w(c) + Vector3(0, 0.4, 0), 1.2, 30, 5.0)
	var glints: GPUParticles3D = ArmadaFx.glints(self, _w(c) + Vector3(0, 0.9, 0), BRASS, 40, 7.0)
	_cp_bursts[cp] = [burst, glints]
	cp.reached.connect(func(which: Checkpoint) -> void:
		if which.index > current_checkpoint:
			for p: GPUParticles3D in _cp_bursts[which]:
				p.restart()
				p.emitting = true
			WorldAudio.at(self, "armada_ship_bell", which.global_position + Vector3(0, 2.0, 0), 0.8, 40.0))
	return {"c": c, "hx": size * 0.5, "hz": size * 0.5}


# ---- machines ----------------------------------------------------------------------------------

## Strip the thruster pods a MovingPlatform builds (ours hang on ropes, they don't fly on jets).
func _strip_pods(m: MovingPlatform) -> void:
	for ch: Node in m.get_children():
		if ch is MeshInstance3D and (ch as MeshInstance3D).mesh is CylinderMesh:
			ch.queue_free()


## A gangplank that runs out of a hull and back in on the clock: extended at offset 0, retracted
## at `retract` (local). Top at `top`; `size` local (x across, z along).
func _plank(top: Vector3, size: Vector3, retract: Vector3, period: float, phase: float) -> MovingPlatform:
	var m: MovingPlatform = kit.mover(_w(top), _sz(size), [Vector3.ZERO, _d(retract)], period, phase)
	m.dwell = 0.3
	m.style = "alt"
	_strip_pods(m)
	var rope: StandardMaterial3D = Look.flat(ArmadaDecor.ROPE, 0.9)
	var iron: StandardMaterial3D = Look.flat(ArmadaDecor.IRON, 0.5, 0.7)
	var half: float = size.z * 0.5
	for sx: float in [-1.0, 1.0]:
		for k: int in 3:
			var z: float = -half + 0.3 + float(k) * (size.z - 0.6) * 0.5
			m.add_child(Look.box(_sz(Vector3(0.06, 0.9, 0.06)), iron, _d(Vector3(sx * (size.x * 0.5 - 0.05), 0.6, z))))
		m.add_child(deco.line(_d(Vector3(sx * (size.x * 0.5 - 0.05), 1.05, -half + 0.3)), _d(Vector3(sx * (size.x * 0.5 - 0.05), 1.05, half - 0.3)), 0.035, rope))
	return m


## A zip-line cargo pallet: hangs from a trolley on a rope 3.2 m above it and runs `travel` (local)
## out and back on the clock, pausing at each end. The main rope and its end posts are built too.
func _pallet(top: Vector3, travel: Vector3, period: float, phase: float) -> MovingPlatform:
	var size := Vector3(2.6, 0.4, 3.0)
	var m: MovingPlatform = kit.mover(_w(top), _sz(size), [Vector3.ZERO, _d(travel)], period, phase)
	m.dwell = 0.25
	m.style = "alt"
	_strip_pods(m)
	var rope: StandardMaterial3D = Look.flat(ArmadaDecor.ROPE, 0.9)
	var brass: StandardMaterial3D = Look.flat(ArmadaDecor.BRASS, 0.3, 0.9)
	var hang: float = 3.2
	for cx: float in [-1.0, 1.0]:
		for cz: float in [-1.0, 1.0]:
			m.add_child(deco.line(_d(Vector3(cx * 1.2, 0.2, cz * 1.4)), Vector3(0, hang, 0), 0.03, rope))
	var trolley := Look.cylinder(0.3, 0.3, brass, Vector3(0, hang + 0.15, 0), -1.0, 12)
	trolley.basis = _b * Basis(Vector3.BACK, PI * 0.5)
	m.add_child(trolley)
	# the main rope, overrunning both ends onto a post frame at each
	var a: Vector3 = _w(top + Vector3(0, hang + 0.35, 0))
	var b: Vector3 = _w(top + travel + Vector3(0, hang + 0.35, 0))
	var dir: Vector3 = (b - a).normalized()
	a -= dir * 2.4
	b += dir * 2.4
	add_child(deco.line(a, b, 0.07, Look.flat(ArmadaDecor.ROPE.darkened(0.2), 0.9)))
	for e: Vector3 in [a, b]:
		var side: Vector3 = _d(Vector3(1.6, 0, 0))
		for s: float in [-1.0, 1.0]:
			add_child(deco.line(e + side * s + Vector3(0, -6.0, 0), e + side * s * 0.2 + Vector3(0, 0.6, 0), 0.12, Look.flat(ArmadaDecor.OAK, 0.8)))
		add_child(Look.sphere(0.3, brass, e))
	return m


## A rolling skiff (ArmadaDeck) whose deck top is at `top`.
func _skiff(top: Vector3, size: Vector3, period: float, phase: float, heave: float = 0.45, roll: float = 7.0, pitch: float = 3.0) -> ArmadaDeck:
	var d := ArmadaDeck.new()
	d.period = period
	d.phase = phase
	d.heave = heave
	d.roll_deg = roll
	d.pitch_deg = pitch
	d.sway = _sz(Vector3(0.25, 0, 0.15)).abs()
	d.style = "main"
	d.balloon_color = (ArmadaDecor.ENVELOPES[_next_house() % ArmadaDecor.ENVELOPES.size()] as Array)[0]
	d.position = _w(top) - Vector3(0, size.y * 0.5, 0)
	d.rotation.y = deg_to_rad(_yaw)
	# the deck's local size is in the skiff's own (turned) frame
	d.size = size
	add_child(d)
	return d


## A rope swing: the plank's top at the BOTTOM of its arc is `bottom_top` (local); it swings along the
## frame's forward axis, `rope` long, `deg` each way.
func _swing(bottom_top: Vector3, rope: float, deg: float, period: float, phase: float) -> ArmadaSwing:
	var s := ArmadaSwing.new()
	var size := Vector3(2.4, 0.35, 2.6)
	s.size = _sz(size)
	s.rope = rope
	s.swing_deg = deg
	s.period = period
	s.phase = phase
	s.swing_dir = _d(Vector3(0, 0, -1))
	s.style = "alt"
	s.position = _w(bottom_top) - Vector3(0, size.y * 0.5, 0)
	s.set_meta("bottom", s.position)
	add_child(s)
	# the yardarm it hangs from, on a pair of tall posts either side
	var pivot: Vector3 = bottom_top + Vector3(0, rope - size.y * 0.5 + 0.05, 0)
	var oak: StandardMaterial3D = Look.flat(ArmadaDecor.OAK.lightened(0.1), 0.8)
	var beam := Look.box(_sz(Vector3(7.0, 0.35, 0.35)), oak, _w(pivot + Vector3(0, 0.25, 0)))
	add_child(beam)
	for sx: float in [-1.0, 1.0]:
		add_child(deco.line(_w(pivot + Vector3(sx * 3.4, 0.25, 0)), _w(pivot + Vector3(sx * 5.5, 12.0, 0)), 0.07, Look.flat(ArmadaDecor.ROPE, 0.9)))
	_bag(pivot + Vector3(0, 0.4, 0), 6.0, 2.0, 5.0)
	return s


## A swing's plank centre (world) at the near (-1) or far (+1) end of its arc.
func _swing_end(s: ArmadaSwing, side: float) -> Vector3:
	var a: float = deg_to_rad(s.swing_deg) * side
	var bottom: Vector3 = s.get_meta("bottom")
	return bottom + s.swing_dir * s.rope * sin(a) + Vector3.UP * s.rope * (1.0 - cos(a))


## A cannon at local `p` (the muzzle), firing along the frame's local `dir` ("+x", "-x", "+z", "-z").
func _cannon(p: Vector3, dir: String, period: float, phase: float, reach: float, lane_drop: float = 0.0, lane_from: float = 2.0, lane_to: float = -1.0, show_gun: bool = false, speed: float = 22.0, stop_at: float = 0.0) -> ArmadaCannon:
	var c := ArmadaCannon.new()
	c.stop_at = stop_at
	c.period = period
	c.phase = phase
	c.reach = reach
	c.speed = speed
	c.lane_drop = lane_drop
	c.lane_from = lane_from
	c.lane_to = lane_to
	c.show_gun = show_gun
	var extra: float = {"-z": 0.0, "+x": -90.0, "+z": 180.0, "-x": 90.0}[dir]
	c.rotation.y = deg_to_rad(_yaw + extra)
	c.position = _w(p)
	add_child(c)
	return c


## A lightning rod whose danger circle is centred on local `c` (floor), the rod `off` from it.
func _rod(c: Vector3, radius: float, period: float, phase: float, off: Vector3 = Vector3.ZERO) -> ArmadaLightning:
	var r := ArmadaLightning.new()
	r.radius = radius
	r.period = period
	r.phase = phase
	r.rod_offset = _d(off)
	r.position = _w(c)
	add_child(r)
	r.struck.connect(func(pos: Vector3) -> void:
		if storm != null:
			storm.local_flash(pos))
	if off.length() > 0.5:
		# a bracket holding the rod out beside the walkway
		add_child(deco.line(_w(c + off * 0.75 + Vector3(0, -0.35, 0)), _w(c + off) + Vector3(0, 0.1, 0), 0.1, Look.flat(ArmadaDecor.IRON, 0.5, 0.7)))
	return r


## A lift propeller (updraft) whose fan hub is at local `c`, hung on an outrigger from `anchor`.
func _prop(c: Vector3, height: float, push: float = 80.0, anchor: Variant = null) -> ArmadaPropeller:
	var p := ArmadaPropeller.new()
	p.size = Vector3(2.8, height, 2.8)
	p.push = push
	p.max_rise = 12.0
	p.position = _w(c)
	add_child(p)
	if anchor != null:
		var iron: StandardMaterial3D = Look.flat(ArmadaDecor.IRON, 0.5, 0.7)
		add_child(deco.line(_w(anchor as Vector3), _w(c + Vector3(0, -1.5, 0)), 0.16, iron))
	return p


## A tesla arc (laser) across the way at local floor point `c`: two brass electrode posts wound with
## copper, crackling.
func _arc(c: Vector3, width: float, period: float, on: float, phase: float, height: float = 2.4) -> LaserGate:
	var g: LaserGate = kit.laser(_w(c + Vector3(0, height * 0.5, 0)), Vector3(width, height, 0.2), period, on, phase, _yaw)
	var brass: StandardMaterial3D = Look.flat(ArmadaDecor.BRASS, 0.3, 0.9)
	var copper: StandardMaterial3D = Look.flat(Color(0.8, 0.42, 0.25), 0.35, 0.85)
	for sx: float in [-1.0, 1.0]:
		var base: Vector3 = c + Vector3(sx * (width * 0.5 + 0.35), 0, 0)
		add_child(Look.cylinder(0.12, height + 0.8, brass, _w(base + Vector3(0, (height + 0.8) * 0.5 - 0.6, 0)), 0.08, 10))
		for k: int in 5:
			add_child(Look.cylinder(0.2, 0.08, copper, _w(base + Vector3(0, 0.3 + float(k) * 0.35, 0)), -1.0, 10))
		add_child(Look.sphere(0.24, Look.flat(Color(0.6, 0.85, 1.0), 0.2, 0.0, 2.2), _w(base + Vector3(0, height + 0.3, 0))))
		ArmadaFx.arc_sparks(self, _w(base + Vector3(0, height + 0.3, 0)), Vector3(0.1, 0.1, 0.1), 8)
	return g


## A falling cargo weight: the crusher dressed as a great iron anchor hung on a chain.
func _anchor(floor_c: Vector3, size: Vector3, lift: float, period: float, phase: float) -> Crusher:
	var cr: Crusher = kit.crusher(_w(floor_c), size, lift, period, phase, _yaw)
	var iron: StandardMaterial3D = Look.flat(Color(0.2, 0.2, 0.23), 0.4, 0.8)
	var brass: StandardMaterial3D = Look.flat(ArmadaDecor.BRASS, 0.3, 0.9)
	# the shank and ring standing on top, flukes curling round the sides
	cr.add_child(Look.box(Vector3(0.4, 0.6, 0.4), iron, Vector3(0, size.y * 0.5 + 0.3, 0)))
	var ring := TorusMesh.new()
	ring.inner_radius = 0.2
	ring.outer_radius = 0.34
	var rm := Look.mesh_node(ring, brass, Vector3(0, size.y * 0.5 + 0.8, 0))
	rm.rotation.x = PI * 0.5
	cr.add_child(rm)
	cr.add_child(Look.box(Vector3(size.x - 0.2, 0.3, 0.4), iron, Vector3(0, size.y * 0.5 + 0.15, 0)))
	for sx: float in [-1.0, 1.0]:
		var fluke := Look.box(Vector3(0.2, size.y + 0.5, 0.7), iron, Vector3(sx * (size.x * 0.5 + 0.02), 0.15, 0))
		cr.add_child(fluke)
	# the chain up into the storm (static: it runs up from the press's guide beam)
	add_child(deco.line(_w(floor_c + Vector3(0, lift + size.y + 1.9, 0)), _w(floor_c + Vector3(0, lift + size.y + 26.0, 0)), 0.1, iron))
	return cr


## A boarding ram (piston) with a brass-capped head, punching along the frame's local `dir`.
func _ram(top: Vector3, size: Vector3, dir: String, stroke: float, period: float, phase: float, strength: float = 8.0) -> Piston:
	var extra: float = {"-z": 0.0, "+x": -90.0, "+z": 180.0, "-x": 90.0}[dir]
	var p: Piston = kit.piston(_w(top), size, _yaw + extra, stroke, period, phase, strength)
	return p


## A slow cargo hook swinging across the way (a Pendulum: it throws you, it doesn't kill), dressed as
## a netted bale on an iron hook.
func _hook(pivot: Vector3, length: float, period: float, phase: float) -> Pendulum:
	var p: Pendulum = kit.pendulum(_w(pivot), length, period, phase, _yaw, 55.0)
	var arm := p.get_child(0) as Node3D
	(arm.get_child(1) as Node3D).visible = false
	var head := Node3D.new()
	head.position = Vector3(0, -length, 0)
	arm.add_child(head)
	var bale := Look.box(Vector3(1.9, 1.6, 1.6), Look.flat(Color(0.6, 0.47, 0.3), 0.9), Vector3(0, -0.2, 0))
	head.add_child(bale)
	var net: StandardMaterial3D = Look.flat(ArmadaDecor.ROPE.darkened(0.3), 0.9)
	for k: int in 3:
		head.add_child(Look.box(Vector3(1.96, 0.08, 1.66), net, Vector3(0, -0.8 + float(k) * 0.55, 0)))
		head.add_child(Look.box(Vector3(0.08, 1.66, 1.66), net, Vector3(-0.8 + float(k) * 0.8, -0.2, 0)))
	head.add_child(Look.box(Vector3(0.2, 0.9, 0.2), Look.flat(ArmadaDecor.IRON, 0.4, 0.8), Vector3(0, 0.9, 0)))
	head.add_child(Look.sphere(0.18, Look.flat(RED, 0.3, 0.2, 2.0), Vector3(0, 0.1, 0.83)))
	var beam := Look.box(_sz(Vector3(6.0, 0.6, 0.6)), Look.flat(ArmadaDecor.OAK, 0.8), _w(pivot + Vector3(0, 0.3, 0)))
	add_child(beam)
	_bag(pivot + Vector3(0, 0.6, 0), 6.0, 2.0, 4.5)
	return p


## The storm's eye: a portal ring wrapped in a swirling vortex of cloud.
func _eye(entry: Vector3, exit: Vector3) -> WarpPortal:
	var p: WarpPortal = kit.portal(_w(entry), _yaw, _w(exit), _yaw, 7.0)
	ArmadaFx.vortex(self, _w(entry + Vector3(0, 1.6, 0)), 1.9, 40).rotation.y = deg_to_rad(_yaw)
	_arrival(exit + Vector3(0, 0, -0.5), BLUE)
	return p


## A burst of glints and steam where a portal lets you out (fired when you arrive).
func _arrival(at: Vector3, col: Color) -> void:
	var p: GPUParticles3D = ArmadaFx.glints(self, _w(at + Vector3(0, 1.0, 0)), col, 50, 7.0)
	var s: GPUParticles3D = ArmadaFx.steam_burst(self, _w(at + Vector3(0, 0.3, 0)), 1.0, 20, 4.0)
	_arrivals.append({"at": _w(at), "p": [p, s], "cool": 0.0})
	ArmadaFx.rising(self, _w(at), 1.2, 2.5, col, 14)


## Fork signpost: two pennants and a glowing strip in the route's colour.
func _sign(p: Vector3, col: Color) -> void:
	deco.flag(_w(p + Vector3(-1.4, 0, 0)), 3.4, col, _yaw)
	deco.flag(_w(p + Vector3(1.4, 0, 0)), 3.4, col, _yaw)
	kit.glow_strip(_w(p + Vector3(0, 0.03, -0.6)), _sz(Vector3(1.4, 0.05, 0.3)), col)


# ---- bot helpers (all deterministic, from the course clock) --------------------------------------

func _wait(test: Callable, hold: Variant = null) -> void:
	var s: Dictionary = {"kind": "b_wait", "test": test}
	if hold != null:
		s["hold"] = hold
	route.append(s)


## Position-hold flight (bot): steer toward `to` (a point, or a Callable returning one) until
## `until` is true (or, without it, until landing); optionally jump from `jump_from` first.
func _fly(to: Variant, until: Variant = null, jump_from: Variant = null) -> void:
	var s: Dictionary = {"kind": "desert_fly", "to": to}
	if until != null:
		s["until"] = until
	if jump_from != null:
		s["jump_from"] = jump_from
	route.append(s)


## Jump from world `from` onto mover `node` (landing at `local`, relative to its box centre) once it
## will be within `radius` of world `point` `lead` seconds from now.
func _board(from: Vector3, node: MovingPlatform, local: Vector3, point: Vector3, radius: float, lead: float) -> void:
	route.append({"kind": "x_jump", "from": from, "to_node": node, "to_local": local,
		"when_node": node, "when_local": Vector3.ZERO, "when_point": point, "when_radius": radius, "lead": lead})


static func _clear(c: ArmadaCannon, p: Vector3, a: float, b: float) -> bool:
	return c.is_clear_for(p, Game.course_time, a, b, 0.35)


static func _rod_safe(r: ArmadaLightning, a: float, b: float) -> bool:
	return r.is_safe_for(Game.course_time, a, b)


## The beam stays dark over the whole window [now + a, now + b].
static func _dark(g: LaserGate, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if g.is_on_at(Game.course_time + s):
			return false
		s += 0.04
	return true


static func _ram_clear(p: Piston, t0: float, t1: float) -> bool:
	var s: float = t0
	while s <= t1:
		if p.extension_at(Game.course_time + s) > 0.02:
			return false
		s += 0.05
	return true


static func _press_ok(c: Crusher, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if c.gap_at(Game.course_time + s) < 2.2 or not c.is_clear_for(Game.course_time + s, 0.0):
			return false
		s += 0.04
	return true


## The hook's bale stays well out to the side of the route over [now + a, now + b].
static func _hook_clear(p: Pendulum, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if absf(sin(p.angle_at(Game.course_time + s))) * p.length < 2.8:
			return false
		s += 0.03
	return true


## The gangplank is run out (within `tol` m of its extended spot) for the whole window.
static func _plank_out(m: MovingPlatform, a: float, b: float, tol: float = 0.5) -> bool:
	var s: float = a
	while s <= b:
		if m.offset_at(Game.course_time + s).length() > tol:
			return false
		s += 0.05
	return true


# ---- the course ---------------------------------------------------------------------------------

func _build() -> void:
	add_child(Ambience.make(theme_id))
	deco = ArmadaDecor.new(self, kit.rng)
	_restyle_environment()
	set_spawn(Vector3(0, 0.1, 4), 0.0)
	var yaws: Array[float] = [0.0, 0.0, -90.0, -90.0, 0.0, 0.0, 90.0, 90.0, 0.0, 0.0, -90.0, -90.0, 0.0, 0.0, 90.0, 90.0, 0.0, 0.0, 0.0]
	var stages: Array[Callable] = [_stage_1, _stage_2, _stage_3, _stage_4, _stage_5, _stage_6, _stage_7, _stage_8,
			_stage_9, _stage_10, _stage_11, _stage_12, _stage_13, _stage_14, _stage_15, _stage_16, _stage_17]
	_frame(Vector3.ZERO, yaws[0])
	for i: int in stages.size():
		_next_yaw = yaws[i + 1]
		_stage_frames.append([_o, _yaw])
		var end: Vector3 = stages[i].call()
		_frame(_w(end), yaws[i + 1])
	_stage_frames.append([_o, _yaw])
	_stage_18()
	_surroundings()
	_armada_materials()


# ---- stage 1: Sky Dock - cargo floats, the first gangplank --------------------------------------

func _stage_1() -> Vector3:
	kit.plat(_w(Vector3.ZERO), Vector3(14, 2, 14), "main", 0.0, _yaw)
	var start: Dictionary = _area(Vector3.ZERO, 7.0, 7.0)
	_dock()
	var a1: Dictionary = _blk(Vector3(0, 0, -12.4), 3.0, 3.0)
	var a2: Dictionary = _drum(Vector3(3.0, 1.0, -18.0), 1.3)
	var a3: Dictionary = _blk(Vector3(0.4, 2.0, -23.6), 2.4, 2.4, "alt")
	# the first ship, broadside across the way: its deck from z -33.5 to -40.5
	var deck: Dictionary = _area(Vector3(0.4, 2.0, -37.0), 8.0, 3.5)
	_ship(Vector3(0.4, 2.0, -37.0), 16.0, 7.0, -90.0, {"masts": [0.05], "mast_h": 14.0})
	# the gangplank runs out of the hull to the last float and back in (into the deck)
	var plank: MovingPlatform = _plank(Vector3(0.4, 1.98, -29.0), Vector3(1.8, 0.3, 8.0), Vector3(0, 0, -8.3), 6.0, 0.0)
	var cp: Dictionary = _cp(Vector3(0.4, 2.0, -47.4))
	_hop(start, a1)
	_hop(a1, a2)
	_hop(a2, a3)
	# SHORTCUT: the cargo stack beside the last float - mantle it and leap past the gangplank
	var stack: Dictionary = _ledge(Vector3(-2.4, 5.3, -27.8), Vector3(1.8, 7.3, 1.8), "accent")
	_bag(Vector3(-2.4, 5.3, -27.8), 2.0, 2.0, 6.0)
	if route_variant == 2:
		r_mantle(_w(_edge(a3, stack["c"])), _w((stack["c"] as Vector3) + Vector3(0, 0, 0.2)))
		r_walk(_w(Vector3(-2.3, 5.3, -28.2)))
		r_jump(_w(Vector3(-2.1, 5.3, -28.35)), _w(Vector3(0.4, 2.0, -35.3)))
	else:
		r_walk(_w(Vector3(0.4, 2.0, -24.2)))
		_wait(func() -> bool: return _plank_out(plank, 0.0, 2.0))
		r_walk(_w(Vector3(0.4, 2.0, -34.6)))
	_hop(deck, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


## The sky dock you start on: a timber-and-iron tower rising out of the clouds, bollards and lamp
## posts, a mooring mast behind with an airship riding at it.
func _dock() -> void:
	var oak: StandardMaterial3D = Look.flat(ArmadaDecor.OAK.lightened(0.05), 0.8)
	var iron: StandardMaterial3D = Look.flat(ArmadaDecor.IRON, 0.5, 0.7)
	add_child(Look.cylinder(5.5, 60.0, oak, _w(Vector3(0, -32.0, 0)), 4.0, 16))
	for k: int in 6:
		add_child(Look.cylinder(5.7 - float(k) * 0.25, 0.4, iron, _w(Vector3(0, -3.0 - float(k) * 8.0, 0)), -1.0, 16))
	for sx: float in [-1.0, 1.0]:
		deco.lamp_post(_w(Vector3(sx * 6.3, 0, -6.3)), 3.0, true)
		deco.barrel(_w(Vector3(sx * 5.8, 0, 3.5)), 0.45)
		add_child(Look.cylinder(0.3, 0.7, iron, _w(Vector3(sx * 6.3, 0.35, -2.0)), 0.22, 10))
	deco.crate(_w(Vector3(-5.6, 0.6, 5.4)), 1.2, 0.4)
	deco.crate(_w(Vector3(-5.5, 1.75, 5.4)), 1.0, 0.9)
	# the mooring mast behind the dock and the airship riding at it
	var mast_base: Vector3 = Vector3(0, -2.0, 16.0)
	add_child(Look.cylinder(0.8, 34.0, iron, _w(mast_base + Vector3(0, 15.0, 0)), 0.5, 10))
	add_child(Look.cylinder(1.4, 0.8, Look.flat(ArmadaDecor.BRASS, 0.3, 0.9), _w(mast_base + Vector3(0, 32.0, 0)), -1.0, 12))
	var ship: Node3D = deco.far_ship(_w(Vector3(16.0, 6.0, 28.0)), _yaw + 55.0, 0.8, 1, 0.0)
	ship.set("bob", 0.4)
	deco.flag(_w(Vector3(-3.0, 0, 6.3)), 5.0, RED, _yaw)
	deco.flag(_w(Vector3(3.0, 0, 6.3)), 5.0, BRASS, _yaw)


# ---- stage 2: Mainsail - mantle the poop, the mast tops, run the sail ---------------------------

func _stage_2() -> Vector3:
	var m1: Dictionary = _ledge(Vector3(0, 3.3, -7.2), Vector3(5.0, 6.3, 3.4))
	var c1: Dictionary = _nest(Vector3(-2.0, 3.9, -13.4), 1.0)
	var c2: Dictionary = _nest(Vector3(1.6, 4.7, -18.3), 0.95, "alt")
	var c3: Dictionary = _nest(Vector3(-0.4, 5.3, -23.6), 0.95)
	var s1: Dictionary = _blk(Vector3(0.2, 5.3, -28.9), 3.0, 3.0, "alt", 0.8, "none")
	_mast_under(Vector3(0.2, 4.5, -28.9), 0.45)
	kit.wallrun(_w(Vector3(2.5, 6.5, -39.9)), Vector3(16, 6.5, 0.6), _yaw + 90.0)
	var s2: Dictionary = _blk(Vector3(-0.2, 5.3, -52.9), 3.6, 5.0, "alt", 0.8, "none")
	_mast_under(Vector3(-0.2, 4.5, -52.9), 0.5)
	var cp: Dictionary = _cp(Vector3(0, 5.3, -62.3))
	r_mantle(_w(Vector3(0, 0, -2.65)), _w(Vector3(0, 3.3, -7.4)))
	_hop(m1, c1)
	_hop(c1, c2)
	_hop(c2, c3)
	_hop(c3, s1)
	r_wallrun(_w(Vector3(0.5, 5.3, -30.05)), _w(Vector3(2.0, 6.7, -34.0)), _w(Vector3(2.0, 6.7, -44.9)), _w(Vector3(-0.2, 5.3, -52.2)))
	_hop(s2, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# the galleon under the mast tops (no gas bag: she flies on lift propellers), the mainsail
	# bellying behind the wall-run panel, and the ship's poop you mantle up
	var gal: Vector3 = Vector3(0.0, -9.0, -32.0)
	deco.hull(_w(gal), _yaw, 66.0, 11.0, 7.0, ArmadaDecor.PAINTS[2], {"castle": false, "bow_walk": false, "lit": 0.6})
	var gdeck := Look.box(Vector3(11.0, 0.4, 66.0 * ArmadaDecor.BOW), Look.flat(ArmadaDecor.DECK.darkened(0.25), 0.8), _w(gal + Vector3(0, -0.2, 66.0 * (0.5 - ArmadaDecor.BOW * 0.5))))
	gdeck.rotation.y = deg_to_rad(_yaw)
	add_child(gdeck)
	for sx: float in [-1.0, 1.0]:
		for z: float in [-12.0, 8.0]:
			var pp: Vector3 = gal + Vector3(sx * 9.5, -2.5, z)
			add_child(deco.line(_w(gal + Vector3(sx * 5.4, -2.5, z)), _w(pp), 0.18, Look.flat(ArmadaDecor.IRON, 0.5, 0.7)))
			deco.propeller(_w(pp + Vector3(0, -0.6, 0)), 3.2, Vector3(-90, _yaw, 0), 0.22 * sx)
	var sail := deco.sail_sheet(Vector3.ZERO, 16.0, 11.0, 1.4, deco.canvas_mat())
	sail.position = _w(Vector3(3.6, 7.0, -39.9))
	sail.rotation.y = deg_to_rad(_yaw - 90.0)
	add_child(sail)
	add_child(deco.line(_w(Vector3(3.2, 12.8, -31.5)), _w(Vector3(3.2, 12.8, -48.3)), 0.22, Look.flat(ArmadaDecor.OAK, 0.8)))
	add_child(Look.cylinder(0.45, 30.0, Look.flat(ArmadaDecor.OAK, 0.8), _w(Vector3(4.2, -2.0, -39.9)), 0.3, 10))
	ArmadaFx.drips(self, _w(Vector3(3.5, 1.4, -39.9)), 12.0, 14.0, 20)
	c1.clear()
	return cp["c"]


## A crow's nest: a round top on the mast rising from the galleon below.
func _nest(c: Vector3, r: float, style: String = "main") -> Dictionary:
	var d: Dictionary = _drum(c, r, style, 0.5, false)
	_mast_under(c - Vector3(0, 1.9, 0), 0.32)
	var rail: StandardMaterial3D = Look.flat(ArmadaDecor.BRASS, 0.3, 0.9)
	var tm := TorusMesh.new()
	tm.inner_radius = r - 0.05
	tm.outer_radius = r + 0.08
	tm.rings = 32
	tm.ring_segments = 6
	add_child(Look.mesh_node(tm, rail, _w(c - Vector3(0, 0.6, 0))))
	return d


## A mast running from under a landing down to the galleon's deck far below.
func _mast_under(top: Vector3, r: float) -> void:
	var h: float = maxf(_w(top).y - (_o.y - 9.0) + 0.5, 2.0)
	add_child(Look.cylinder(r, h, Look.flat(ArmadaDecor.OAK.lightened(0.1), 0.8), _w(top - Vector3(0, h * 0.5, 0)), r * 1.2, 10))


# ---- stage 3: Crossfire - three gangways swept by rolling cannon volleys -----------------------

func _stage_3() -> Vector3:
	var b1: Dictionary = _gangway(Vector3(0, 0, -8.0), 8.0)
	var b2: Dictionary = _gangway(Vector3(0, 0.6, -18.5), 8.0)
	var b3: Dictionary = _gangway(Vector3(0, 1.2, -29.0), 8.0)
	var cp: Dictionary = _cp(Vector3(0, 1.2, -39.5))
	# the lanes: from the frigate on the left, the sloop on the right, the frigate again
	var ca: ArmadaCannon = _cannon(Vector3(-12.3, 1.0, -8.0), "+x", 3.3, 0.0, 24.0, 1.0, 11.0, 13.6)
	var cb: ArmadaCannon = _cannon(Vector3(12.3, 1.6, -18.5), "-x", 3.3, -0.333, 24.0, 1.0, 11.0, 13.6, false, 22.0, 24.5)
	var cc: ArmadaCannon = _cannon(Vector3(-12.3, 2.2, -29.0), "+x", 3.3, -0.667, 24.0, 1.0, 11.0, 13.6, true)
	_ship(Vector3(-16.3, 1.3, -18.5), 30.0, 8.0, 0.0, {"env_y": 12.0, "masts": [-0.1, 0.3], "mast_h": 13.0})
	_ship(Vector3(16.3, 2.0, -18.5), 8.0, 8.0, 180.0, {"env_y": 11.0, "props": false})
	r_jump(_w(Vector3(0, 0, -2.65)), _w(Vector3(0, 0, -5.2)))
	var la: Vector3 = _w(Vector3(0, 0, -8.0))
	_wait(func() -> bool: return _clear(ca, la, 0.0, 1.9), _w(Vector3(0, 0, -5.4)))
	r_walk(_w(Vector3(0, 0, -11.2)))
	_hop(b1, b2, Vector3(0, 0, 2.6))
	var lb: Vector3 = _w(Vector3(0, 0.6, -18.5))
	_wait(func() -> bool: return _clear(cb, lb, 0.0, 1.9), _w(Vector3(0, 0.6, -15.9)))
	r_walk(_w(Vector3(0, 0.6, -21.7)))
	_hop(b2, b3, Vector3(0, 0, 2.6))
	var lc: Vector3 = _w(Vector3(0, 1.2, -29.0))
	_wait(func() -> bool: return _clear(cc, lc, 0.0, 1.9), _w(Vector3(0, 1.2, -26.4)))
	r_walk(_w(Vector3(0, 1.2, -32.2)))
	_hop(b3, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


## A gangway between the ships: a narrow timber walk with rope rails on iron stanchions (beside it,
## below the walking surface's edges).
func _gangway(c: Vector3, length: float) -> Dictionary:
	var d: Dictionary = _blk(c, 1.4, length, "alt", 0.5, "none")
	var iron: StandardMaterial3D = Look.flat(ArmadaDecor.IRON, 0.5, 0.7)
	var rope: StandardMaterial3D = Look.flat(ArmadaDecor.ROPE, 0.9)
	for sx: float in [-1.0, 1.0]:
		var x: float = sx * 0.85
		for k: int in 3:
			var z: float = c.z + length * 0.5 - 0.4 - float(k) * (length - 0.8) * 0.5
			add_child(Look.box(_sz(Vector3(0.06, 1.0, 0.06)), iron, _w(Vector3(x, c.y + 0.1, z))))
		add_child(deco.line(_w(Vector3(x, c.y + 0.6, c.z + length * 0.5 - 0.4)), _w(Vector3(x, c.y + 0.6, c.z - length * 0.5 + 0.4)), 0.03, rope))
	_bag(c, 3.0, length * 0.6, 6.5)
	return d


# ---- stage 4: Skiff Hop - three rolling skiffs ------------------------------------------------

func _stage_4() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var ss := Vector3(3.0, 0.4, 4.2)
	var sk1: ArmadaDeck = _skiff(Vector3(0, -0.6, -8.2), ss, 4.6, 0.0)
	var sk2: ArmadaDeck = _skiff(Vector3(1.6, 0.0, -15.2), ss, 5.2, 0.35)
	var sk3: ArmadaDeck = _skiff(Vector3(-0.6, 0.6, -21.6), ss, 4.2, 0.7)
	var land: Dictionary = _blk(Vector3(0, 1.2, -26.5), 4.0, 4.0)
	var cp: Dictionary = _cp(Vector3(0, 1.2, -35.0))
	# SHORTCUT: three 1 m buoy barrels beside the skiffs
	var bz: Array[Vector3] = [Vector3(-3.4, 0.4, -8.5), Vector3(-3.4, 0.8, -14.5), Vector3(-3.4, 1.2, -20.5)]
	var buoys: Array[Dictionary] = []
	for p: Vector3 in bz:
		buoys.append(_drum(p, 0.5, "accent", 0.5, true))
	if route_variant == 2:
		r_jump(_w(Vector3(-2.6, 0, -2.65)), _w(bz[0]))
		_hop(buoys[0], buoys[1])
		_hop(buoys[1], buoys[2])
		_hop(buoys[2], land, Vector3(-1.0, 0, 1.0))
	else:
		var top := Vector3(0, 0.2, 0)
		route.append({"kind": "x_jump", "from": _w(Vector3(0, 0, -2.65)), "to_node": sk1, "to_local": top + _d(Vector3(0, 0, 0.4))})
		route.append({"kind": "x_jump", "from_node": sk1, "from_local": top + _d(Vector3(0.3, 0, -1.6)), "to_node": sk2, "to_local": top + _d(Vector3(0, 0, 0.5))})
		route.append({"kind": "x_jump", "from_node": sk2, "from_local": top + _d(Vector3(-0.4, 0, -1.6)), "to_node": sk3, "to_local": top + _d(Vector3(0, 0, 0.5))})
		route.append({"kind": "x_jump", "from_node": sk3, "from_local": top + _d(Vector3(0.1, 0, -1.6)), "to": _w(Vector3(0, 1.2, -25.8))})
	_hop(land, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	# the skiffs' mother ship off to the right, her boats out on their lines
	_ship(Vector3(18.0, 0.4, -18.0), 26.0, 9.0, 0.0, {"env_y": 12.0, "masts": [0.0, 0.3], "mast_h": 13.0})
	cp0.clear()
	return cp["c"]


# ---- stage 5: Stern Lift (BRANCH) - a propeller updraft and the buoys | the galleon's stern -------

func _stage_5() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var fork: Dictionary = _blk(Vector3(0, 0, -8.0), 12.0, 4.0, "main", 1.0, "none")
	_fork_dress(Vector3(0, 0, -8.0), 12.0)
	# LEFT (blue): a lift propeller blowing up past the fork, then a line of buoys
	_prop(Vector3(-3.5, -2.5, -15.0), 14.0, 80.0, Vector3(-10.0, -1.0, -15.0))
	var l1: Dictionary = _blk(Vector3(-3.5, 6.6, -21.0), 3.0, 3.0)
	var d1: Dictionary = _drum(Vector3(-2.6, 6.6, -27.0), 1.0)
	var d2: Dictionary = _drum(Vector3(-3.6, 6.6, -32.8), 1.0)
	var k1: Dictionary = _blk(Vector3(-3.0, 6.6, -38.6), 2.0, 2.0)
	var d3: Dictionary = _drum(Vector3(-3.0, 6.6, -44.2), 1.0)
	# RIGHT (gold): up the galleon's stern, along her side, up again
	var m1: Dictionary = _ledge(Vector3(4.0, 3.3, -13.6), Vector3(3.0, 6.3, 3.2), "alt")
	kit.wallrun(_w(Vector3(6.5, 4.5, -24.7)), Vector3(16.0, 6.5, 0.6), _yaw + 90.0)
	var l2: Dictionary = _blk(Vector3(3.8, 3.3, -37.0), 3.6, 4.0, "alt", 0.8, "none")
	var m2: Dictionary = _ledge(Vector3(3.8, 6.6, -42.4), Vector3(3.6, 9.9, 3.4), "alt")
	var merge: Dictionary = _blk(Vector3(0, 6.6, -50.0), 12.0, 4.0, "main", 1.0, "none")
	var cp: Dictionary = _cp(Vector3(0, 6.6, -58.5))
	# the galleon whose side you run: her deck just above the merge, her hull right behind the panel
	_ship(Vector3(11.0, 7.4, -30.0), 36.0, 8.0, 0.0, {"props": false, "env_y": 12.0, "masts": [0.1, 0.35], "mast_h": 14.0, "house": 3})
	_sign(Vector3(-3.5, 0, -6.6), BLUE)
	_sign(Vector3(4.0, 0, -6.6), BRASS)
	_hop(cp0, fork, Vector3(0, 0, 0.8))
	if route_variant != 1:
		r_walk(_w(Vector3(-3.5, 0, -8.8)))
		var y1: float = _w(l1["c"]).y
		_fly(_w(Vector3(-3.5, 0, -15.0)), func() -> bool: return player.global_position.y > y1 + 2.4, _w(Vector3(-3.5, 0, -9.65)))
		_fly(_w((l1["c"] as Vector3) + Vector3(0, 0, 0.5)))
		_hop(l1, d1)
		_hop(d1, d2)
		_hop(d2, k1)
		_hop(k1, d3)
		_hop(d3, merge, Vector3(-3.0, 0, 0.8))
	else:
		r_walk(_w(Vector3(4.0, 0, -8.8)))
		r_mantle(_w(Vector3(4.0, 0, -9.65)), _w(Vector3(4.0, 3.3, -13.2)))
		r_wallrun(_w(Vector3(4.3, 3.3, -14.85)), _w(Vector3(6.0, 4.7, -18.8)), _w(Vector3(6.0, 4.7, -29.7)), _w(Vector3(3.8, 3.3, -36.3)))
		r_mantle(_w(Vector3(3.8, 3.3, -38.65)), _w(Vector3(3.8, 6.6, -41.3)))
		_hop(m2, merge, Vector3(3.0, 0, 0.8))
	_hop(merge, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	l2.clear()
	return cp["c"]


## A fork deck: a broad plank landing on a ship's boat-deck frame (crates at the back corners).
func _fork_dress(c: Vector3, width: float) -> void:
	var iron: StandardMaterial3D = Look.flat(ArmadaDecor.IRON, 0.5, 0.7)
	for sx: float in [-1.0, 1.0]:
		add_child(deco.line(_w(c + Vector3(sx * (width * 0.5 - 0.5), -1.0, 0)), _w(c + Vector3(sx * (width * 0.5 + 2.5), 8.0, 0)), 0.08, iron))
	_bag(c, width * 0.6, 4.0, 7.0)


# ---- stage 6: Cargo Ropeway - down a zip-line, through a rod's circle, back up another ----------

func _stage_6() -> Vector3:
	var pa: MovingPlatform = _pallet(Vector3(-1.6, 0, -6.4), Vector3(0, -5.5, -24.0), 11.0, 0.0)
	_pallet(Vector3(1.6, 0, -6.4), Vector3(0, -5.5, -24.0), 11.0, 0.5)
	var l1: Dictionary = _blk(Vector3(0, -5.5, -34.6), 6.2, 3.0, "main", 0.8, "none")
	var l2: Dictionary = _blk(Vector3(0, -5.5, -44.6), 3.4, 9.0, "alt", 0.8, "none")
	var rod: ArmadaLightning = _rod(Vector3(0, -5.5, -45.1), 2.0, 4.2, 0.0, Vector3(1.95, 0, 0))
	var pc: MovingPlatform = _pallet(Vector3(-1.6, -5.5, -53.2), Vector3(0, 5.5, -22.0), 11.0, 0.3)
	_pallet(Vector3(1.6, -5.5, -53.2), Vector3(0, 5.5, -22.0), 11.0, 0.8)
	var cp: Dictionary = _cp(Vector3(0, 0, -81.6))
	# the docks at the foot of the ropeway hang from a big ship's cargo booms (decor ship to the left)
	_bag(Vector3(0, -5.5, -34.6), 6.2, 3.0, 6.5)
	_bag(Vector3(0, -5.5, -44.6), 3.4, 9.0, 7.0)
	_ship(Vector3(-17.0, -3.0, -42.0), 34.0, 9.0, 0.0, {"env_y": 12.0, "masts": [0.05, 0.35], "mast_h": 13.0})
	var top_a: Vector3 = _w(Vector3(-1.6, 0, -6.4)) - Vector3(0, 0.2, 0)
	var low_a: Vector3 = top_a + _d(Vector3(0, -5.5, -24.0))
	var low_c: Vector3 = _w(Vector3(-1.6, -5.5, -53.2)) - Vector3(0, 0.2, 0)
	var top_c: Vector3 = low_c + _d(Vector3(0, 5.5, -22.0))
	var up := Vector3(0, 0.2, 0)
	_board(_w(Vector3(-1.4, 0, -2.65)), pa, up + _d(Vector3(0, 0, 0.4)), top_a, 0.25, 0.4)
	r_jump_from_ride(pa, low_a, 0.25, _w(Vector3(-1.0, -5.5, -34.2)), true, up + _d(Vector3(0, 0, -0.9)))
	_hop(l1, l2, Vector3(0, 0, 3.4))
	_wait(func() -> bool: return _rod_safe(rod, 0.0, 2.1), _w(Vector3(0, -5.5, -41.2)))
	r_walk(_w(Vector3(-1.1, -5.5, -48.7)))
	_board(_w(Vector3(-1.4, -5.5, -48.75)), pc, up + _d(Vector3(0, 0, 0.4)), low_c, 0.25, 0.4)
	r_jump_from_ride(pc, top_c, 0.25, _w(Vector3(-0.8, 0, -80.0)), true, up + _d(Vector3(0, 0, -0.9)))
	r_checkpoint()
	l2.clear()
	return cp["c"]


# ---- stage 7: Lightning Spars - two struck rods and a tesla arc on the yards ----------------------

func _stage_7() -> Vector3:
	var bm1: Dictionary = _blk(Vector3(0, 0, -8.5), 1.0, 10.0, "alt", 0.6, "spar")
	var ra: ArmadaLightning = _rod(Vector3(0, 0, -8.8), 1.8, 4.4, 0.0, Vector3(1.3, 0, 0))
	var d1: Dictionary = _drum(Vector3(1.2, 0.6, -17.2), 1.0)
	var bm2: Dictionary = _blk(Vector3(0, 1.2, -26.4), 1.0, 10.0, "alt", 0.6, "spar")
	var arc: LaserGate = _arc(Vector3(0, 1.2, -26.4), 2.2, 3.4, 0.35, 0.0)
	var d2: Dictionary = _drum(Vector3(-1.2, 1.8, -35.4), 1.0)
	var bm3: Dictionary = _blk(Vector3(0, 1.8, -44.4), 1.0, 10.0, "alt", 0.6, "spar")
	var rb: ArmadaLightning = _rod(Vector3(0, 1.8, -44.4), 1.8, 4.4, 0.5, Vector3(-1.3, 0, 0))
	var cp: Dictionary = _cp(Vector3(0, 1.8, -55.4))
	# the ships whose yards these are: a tall three-master on each side
	_ship(Vector3(-15.0, -2.0, -26.0), 34.0, 10.0, 0.0, {"env_y": 14.0, "masts": [0.0, 0.3], "mast_h": 16.0})
	_ship(Vector3(15.0, -1.0, -30.0), 30.0, 9.0, 0.0, {"env_y": 14.0, "masts": [0.1], "mast_h": 16.0})
	r_walk(_w(Vector3(0, 0, -5.8)))
	_wait(func() -> bool: return _rod_safe(ra, 0.0, 1.9))
	r_walk(_w(Vector3(0, 0, -12.9)))
	r_jump(_w(Vector3(0, 0, -13.15)), _w(d1["c"]))
	_hop(d1, bm2, Vector3(0, 0, 3.4))
	_wait(func() -> bool: return _dark(arc, 0.05, 1.6), _w(Vector3(0, 1.2, -23.4)))
	r_walk(_w(Vector3(0, 1.2, -30.9)))
	r_jump(_w(Vector3(0, 1.2, -31.05)), _w(d2["c"]))
	_hop(d2, bm3, Vector3(0, 0, 4.0))
	_wait(func() -> bool: return _rod_safe(rb, 0.0, 1.9), _w(Vector3(0, 1.8, -40.4)))
	r_walk(_w(Vector3(0, 1.8, -48.9)))
	_hop(bm3, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 8: Gun Port Rams - the walkway along a warship's side, two mantles under the weight -------

func _stage_8() -> Vector3:
	var walk: Dictionary = _blk(Vector3(0, 0, -11.0), 1.8, 16.0, "alt", 0.6, "none")
	var rams: Array[Piston] = []
	var rz: Array[float] = [-7.5, -11.5, -15.5]
	for k: int in 3:
		rams.append(_ram(Vector3(-3.0, 1.3, rz[k]), Vector3(1.6, 1.2, 1.4), "+x", 2.6, 4.4, fposmod(0.1 - 0.1 * float(k), 1.0)))
	var m1: Dictionary = _ledge(Vector3(0, 3.3, -22.7), Vector3(4.0, 6.3, 3.4))
	_ledge(Vector3(0, 6.6, -26.1), Vector3(3.6, 9.6, 3.4), "alt")
	var press: Crusher = _anchor(Vector3(0, 6.6, -26.1), Vector3(3.2, 1.4, 3.0), 3.4, 5.0, 0.2)
	var cp: Dictionary = _cp(Vector3(0, 6.6, -34.5))
	# the warship: her guns run out of the ports right beside the walkway
	_ship(Vector3(-7.3, 2.6, -11.0), 18.0, 10.0, 0.0, {"env_y": 12.0, "masts": [0.1], "mast_h": 13.0, "props": false})
	for z: float in [-3.5, -19.0]:
		deco.lantern(_w(Vector3(-2.1, 2.2, z)), true)
	var p0: Piston = rams[0]
	var p1: Piston = rams[1]
	var p2: Piston = rams[2]
	r_walk(_w(Vector3(0, 0, -3.6)))
	_wait(func() -> bool: return _ram_clear(p0, 0.1, 1.9) and _ram_clear(p1, 0.55, 2.35) and _ram_clear(p2, 1.0, 2.8))
	r_walk(_w(Vector3(0, 0, -18.4)))
	r_mantle(_w(Vector3(0, 0, -18.65)), _w(Vector3(0, 3.3, -21.8)))
	r_walk(_w(Vector3(0, 3.3, -21.85)))
	_wait(func() -> bool: return _press_ok(press, 0.0, 2.7))
	r_mantle(_w(Vector3(0, 3.3, -21.85)), _w(Vector3(0, 6.6, -25.2)))
	_hop(_area(Vector3(0, 6.6, -26.1), 1.8, 1.7), cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	walk.clear()
	m1.clear()
	return cp["c"]


# ---- stage 9: Balloon Crowns (BRANCH) - bounce up onto the gas bags | two rope swings under them --------

func _stage_9() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var fork: Dictionary = _blk(Vector3(0, 0, -8.0), 12.0, 4.0, "main", 1.0, "none")
	_fork_dress(Vector3(0, 0, -8.0), 12.0)
	# LEFT (red): the crowns of three gas bags - a bounce pad sends you up onto the tallest
	var pa: Dictionary = _crown(Vector3(-3.5, 0, -14.0), 3.0, 4.0, 2.8)
	var pad_p := Vector3(-3.5, 0, -15.2)
	kit.pad(_w(pad_p), 21.0, 0.0, 0.0, 1.2)
	var pb: Dictionary = _crown(Vector3(-3.5, 5.8, -22.6), 4.0, 5.0, 3.4)
	var c1: Dictionary = _crown_disc(Vector3(-2.8, 5.8, -30.0), 1.2)
	var c2: Dictionary = _crown_disc(Vector3(-3.4, 3.4, -35.2), 1.1)
	# RIGHT (blue): two rope swings
	var sw1: ArmadaSwing = _swing(Vector3(3.5, -1.48, -16.21), 7.0, 38.0, 5.0, 0.25)
	var l1: Dictionary = _blk(Vector3(3.5, 0, -24.0), 3.0, 3.0)
	var sw2: ArmadaSwing = _swing(Vector3(3.5, -1.48, -31.71), 7.0, 38.0, 5.0, 0.6)
	var merge: Dictionary = _blk(Vector3(0, 0, -40.0), 12.0, 4.0, "main", 1.0, "none")
	var cp: Dictionary = _cp(Vector3(0, 0, -48.5))
	_sign(Vector3(-3.5, 0, -6.6), RED)
	_sign(Vector3(3.5, 0, -6.6), BLUE)
	_hop(cp0, fork, Vector3(0, 0, 0.8))
	if route_variant != 1:
		r_walk(_w(Vector3(-3.5, 0, -8.8)))
		_hop(_area(Vector3(-3.5, 0, -8.0), 1.5, 2.0), pa, Vector3(0, 0, 1.2))
		r_walk(_w(pad_p + Vector3(0, 0, 1.2)))
		r_pad(_w(pad_p), _w((pb["c"] as Vector3) + Vector3(0, 0, 0.6)))
		_hop(pb, c1)
		_hop(c1, c2)
		_hop(c2, merge, Vector3(-3.0, 0, 0.5))
	else:
		var up := Vector3(0, 0.175, 0)
		r_walk(_w(Vector3(3.5, 0, -8.8)))
		_board(_w(Vector3(3.5, 0, -9.65)), sw1, up, _swing_end(sw1, -1.0), 0.45, 0.4)
		r_jump_from_ride(sw1, _swing_end(sw1, 1.0), 0.45, _w(Vector3(3.5, 0, -23.6)), true, up + _d(Vector3(0, 0, -0.5)))
		r_walk(_w(Vector3(3.5, 0, -24.6)))
		_board(_w(Vector3(3.5, 0, -25.15)), sw2, up, _swing_end(sw2, -1.0), 0.45, 0.4)
		r_jump_from_ride(sw2, _swing_end(sw2, 1.0), 0.45, _w(Vector3(3.0, 0, -39.2)), true, up + _d(Vector3(0, 0, -0.5)))
	_hop(merge, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	l1.clear()
	return cp["c"]


## A gas bag's crown: a plank platform strapped on top of a big envelope (`r` round).
func _crown(c: Vector3, sx: float, sz: float, r: float) -> Dictionary:
	var d: Dictionary = _blk(c, sx, sz, "alt", 0.4, "none")
	var ln: float = sz * 2.0 + 1.0
	deco.envelope(_w(c - Vector3(0, 0.4 + r * 0.95, 0)), _yaw, ln, r, ArmadaDecor.ENVELOPES[_next_house() % ArmadaDecor.ENVELOPES.size()])
	return d


## A round crown platform on a small gas bag.
func _crown_disc(c: Vector3, r: float) -> Dictionary:
	kit.disc(_w(c), r, 0.4, "alt", 0.0)
	var br: float = r * 1.7
	deco.envelope(_w(c - Vector3(0, 0.4 + br * 0.95, 0)), _yaw, br * 2.6, br, ArmadaDecor.ENVELOPES[_next_house() % ArmadaDecor.ENVELOPES.size()], false)
	return {"c": c, "r": r}


# ---- stage 10: THE BROADSIDE - sprint the shattered deck while the enemy's volleys rake every hole ------

func _stage_10() -> Vector3:
	# your ship's deck, shot to pieces: five sections with four holes between them
	var secs: Array[Vector2] = [Vector2(-3.0, -10.0), Vector2(-13.5, -19.5), Vector2(-23.0, -29.0), Vector2(-32.5, -38.5), Vector2(-42.0, -48.0)]
	var areas: Array[Dictionary] = []
	for s: Vector2 in secs:
		var cz: float = (s.x + s.y) * 0.5
		areas.append(_blk(Vector3(0, 0, cz), 5.0, s.x - s.y, "main", 0.8, "none"))
	var cp: Dictionary = _cp(Vector3(0, 0, -54.5))
	# the enemy galleon alongside, her gun ports along your deck
	_ship(Vector3(-20.0, 2.0, -27.0), 52.0, 12.0, 0.0, {"env_y": 16.0, "env_r": 7.0, "masts": [-0.05, 0.25, 0.5], "mast_h": 18.0, "house": 2})
	var period: float = 3.6
	var gaps: Array[float] = []
	var guns: Array[ArmadaCannon] = []
	for k: int in 4:
		var gz: float = (secs[k].y + secs[k + 1].x) * 0.5
		gaps.append(gz)
		guns.append(_cannon(Vector3(-13.8, 1.3, gz), "+x", period, -0.14 * float(k), 30.0, 0.0, 2.0, -1.0, false, 26.0))
		# red glow along both lips of the hole: the lane
		for e: float in [secs[k].y, secs[k + 1].x]:
			kit.glow_strip(_w(Vector3(0, 0.03, e + (0.12 if e == secs[k].y else -0.12))), _sz(Vector3(4.6, 0.05, 0.16)), RED)
	# the upper battery: two more lanes raking the middle of the second and fourth sections
	var mid_z: Array[float] = [-17.3, -36.3]
	var mids: Array[ArmadaCannon] = []
	for k: int in 2:
		mids.append(_cannon(Vector3(-13.8, 1.0, mid_z[k]), "+x", period, 0.5 - 0.14 * float(k * 2 + 1), 30.0, 1.0, 11.3, 16.3, false, 26.0))
	# your ship: the hull under the deck, and her guns answering from the ports below it
	deco.hull(_w(Vector3(0, -0.9, -25.5)), _yaw, 50.0, 6.0, 5.0, ArmadaDecor.PAINTS[0], {"castle": false, "bow_walk": false, "rails": false, "lit": 0.7})
	for k: int in 5:
		_cannon(Vector3(-3.4, -1.6, -6.0 - 9.5 * float(k)), "-x", period, 0.5 + 0.1 * float(k), 1.0, 0.0, 2.0, -1.0, false, 26.0, 10.5)
	# smoke of battle, fires on your deck's broken edges
	for k: int in 4:
		ArmadaFx.fire(self, _w(Vector3(2.2 if k % 2 == 0 else -2.2, 0.0, secs[k].y + 0.3)), 0.8)
	ArmadaFx.scud(self, _w(Vector3(-4.0, 3.0, -26.0)), _sz(Vector3(10.0, 3.0, 24.0)), 16)
	var lanes: Array[Vector3] = []
	for gz: float in gaps:
		lanes.append(_w(Vector3(0, 0, gz)))
	var mp: Array[Vector3] = [_w(Vector3(0, 0, mid_z[0])), _w(Vector3(0, 0, mid_z[1]))]
	var g0: ArmadaCannon = guns[0]
	var g1: ArmadaCannon = guns[1]
	var g2: ArmadaCannon = guns[2]
	var g3: ArmadaCannon = guns[3]
	var m0: ArmadaCannon = mids[0]
	var m1: ArmadaCannon = mids[1]
	# the run: wait for each hole's lane, jump it, wait out the mid-deck lanes
	_wait(func() -> bool: return _clear(g0, lanes[0], 0.0, 1.9), _w(Vector3(0, 0, -9.65)))
	r_jump(_w(Vector3(0, 0, -9.65)), _w(Vector3(0, 0, -15.0)))
	_wait(func() -> bool: return _clear(m0, mp[0], 0.0, 1.8), _w(Vector3(0, 0, -15.0)))
	r_walk(_w(Vector3(0, 0, -19.15)))
	_wait(func() -> bool: return _clear(g1, lanes[1], 0.0, 1.9), _w(Vector3(0, 0, -19.15)))
	r_jump(_w(Vector3(0, 0, -19.15)), _w(Vector3(0, 0, -24.5)))
	r_walk(_w(Vector3(0, 0, -28.65)))
	_wait(func() -> bool: return _clear(g2, lanes[2], 0.0, 1.9), _w(Vector3(0, 0, -28.65)))
	r_jump(_w(Vector3(0, 0, -28.65)), _w(Vector3(0, 0, -34.0)))
	_wait(func() -> bool: return _clear(m1, mp[1], 0.0, 1.8), _w(Vector3(0, 0, -34.0)))
	r_walk(_w(Vector3(0, 0, -38.15)))
	_wait(func() -> bool: return _clear(g3, lanes[3], 0.0, 1.9), _w(Vector3(0, 0, -38.15)))
	r_jump(_w(Vector3(0, 0, -38.15)), _w(Vector3(0, 0, -43.5)))
	_hop(areas[4], cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 11: Rope Swings - swing over the void, crumbling cargo between -------------------------

func _stage_11() -> Vector3:
	var sw1: ArmadaSwing = _swing(Vector3(0, -1.48, -9.21), 7.0, 38.0, 4.8, 0.0)
	var l1: Dictionary = _blk(Vector3(0, 0, -17.0), 3.0, 3.0)
	kit.collapse(_w(Vector3(0.6, 0.4, -23.0)), 2.0, 0.5, 2.4)
	kit.collapse(_w(Vector3(-0.4, 0.8, -28.2)), 2.0, 0.5, 2.4)
	var l1b: Dictionary = _blk(Vector3(0, 0.8, -33.6), 2.4, 2.4)
	var sw2: ArmadaSwing = _swing(Vector3(0, -0.68, -41.01), 7.0, 38.0, 5.2, 0.3)
	var l2: Dictionary = _blk(Vector3(0, 0.8, -48.8), 3.0, 3.0)
	var cp: Dictionary = _cp(Vector3(0, 0.8, -57.0))
	# SHORTCUT: two 1 m buoys past the second swing
	var b1: Dictionary = _drum(Vector3(-2.6, 0.8, -40.2), 0.5, "accent", 0.5)
	var b2: Dictionary = _drum(Vector3(-2.6, 0.8, -46.2), 0.5, "accent", 0.5)
	_ship(Vector3(16.0, -2.0, -30.0), 30.0, 9.0, 180.0, {"env_y": 13.0, "masts": [0.1], "mast_h": 14.0})
	_ship(Vector3(-17.0, 0.0, -20.0), 26.0, 8.0, 0.0, {"env_y": 12.0, "masts": [0.2], "mast_h": 12.0})
	var up := Vector3(0, 0.175, 0)
	var fwd: Vector3 = _d(Vector3(0, 0, -0.5))
	_board(_w(Vector3(0, 0, -2.65)), sw1, up, _swing_end(sw1, -1.0), 0.45, 0.4)
	r_jump_from_ride(sw1, _swing_end(sw1, 1.0), 0.45, _w(Vector3(0, 0, -16.6)), true, up + fwd)
	_hop(l1, _area(Vector3(0.6, 0.4, -23.0), 1.0, 1.0))
	_hop(_area(Vector3(0.6, 0.4, -23.0), 1.0, 1.0), _area(Vector3(-0.4, 0.8, -28.2), 1.0, 1.0))
	_hop(_area(Vector3(-0.4, 0.8, -28.2), 1.0, 1.0), l1b)
	if route_variant == 2:
		r_jump(_w(Vector3(-0.8, 0.8, -34.45)), _w(b1["c"]))
		_hop(b1, b2)
		_hop(b2, l2, Vector3(-0.6, 0, 0.4))
	else:
		r_walk(_w(Vector3(0, 0.8, -34.2)))
		_board(_w(Vector3(0, 0.8, -34.45)), sw2, up, _swing_end(sw2, -1.0), 0.45, 0.4)
		r_jump_from_ride(sw2, _swing_end(sw2, 1.0), 0.45, _w(Vector3(0, 0.8, -48.4)), true, up + fwd)
	_hop(l2, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 12: Anchor Drop - three anchors dropping on a wave, a wall run along a hull -----------------

func _stage_12() -> Vector3:
	var ks: Array[Dictionary] = []
	var anchors: Array[Crusher] = []
	for k: int in 3:
		var c := Vector3(0, 0.6 * float(k), -7.6 - 6.0 * float(k))
		ks.append(_blk(c, 2.4, 3.0, "alt", 0.8, "none"))
		anchors.append(_anchor(c, Vector3(2.2, 1.4, 2.6), 3.4, 5.0, fposmod(0.3 - 0.12 * float(k), 1.0)))
	kit.wallrun(_w(Vector3(2.5, 2.4, -30.6)), Vector3(16, 6.5, 0.6), _yaw + 90.0)
	var s2: Dictionary = _blk(Vector3(-0.2, 1.2, -43.6), 3.6, 5.0, "alt", 0.8, "none")
	var cp: Dictionary = _cp(Vector3(0, 1.2, -53.0))
	# the ship whose hull you run (her side right behind the panel) and the one the anchors hang from
	_ship(Vector3(6.9, 3.4, -32.0), 22.0, 8.0, 0.0, {"env_y": 12.0, "masts": [0.15], "mast_h": 12.0, "props": false})
	_ship(Vector3(-15.0, 4.0, -14.0), 30.0, 9.0, 180.0, {"env_y": 12.0, "masts": [0.0, 0.3], "mast_h": 14.0})
	var a0: Crusher = anchors[0]
	var a1: Crusher = anchors[1]
	var a2: Crusher = anchors[2]
	_wait(func() -> bool: return _press_ok(a0, 0.0, 2.2) and _press_ok(a1, 0.6, 3.1) and _press_ok(a2, 1.2, 4.1))
	_hop(_area(Vector3.ZERO, 3.0, 3.0), ks[0])
	_hop(ks[0], ks[1])
	_hop(ks[1], ks[2])
	r_wallrun(_w(Vector3(0.3, 1.2, -20.75)), _w(Vector3(2.0, 2.6, -24.7)), _w(Vector3(2.0, 2.6, -35.6)), _w(Vector3(-0.2, 1.2, -42.9)))
	_hop(s2, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 13: Storm Eye (BRANCH) - two struck spars | mantle, run, mantle, the storm's eye ------------

func _stage_13() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var fork: Dictionary = _blk(Vector3(0, 0, -8.0), 12.0, 4.0, "main", 1.0, "none")
	_fork_dress(Vector3(0, 0, -8.0), 12.0)
	# LEFT (blue): two spars with lightning rods on them
	var r1: Dictionary = _blk(Vector3(-3.5, 0, -16.0), 1.2, 8.0, "alt", 0.6, "spar")
	var ra: ArmadaLightning = _rod(Vector3(-3.5, 0, -16.0), 1.8, 4.6, 0.0, Vector3(-1.2, 0, 0))
	var r2: Dictionary = _drum(Vector3(-2.8, 0.6, -24.0), 1.1)
	var r3: Dictionary = _blk(Vector3(-3.5, 1.2, -32.5), 1.2, 8.0, "alt", 0.6, "spar")
	var rb: ArmadaLightning = _rod(Vector3(-3.5, 1.2, -32.5), 1.8, 4.6, 0.45, Vector3(-1.2, 0, 0))
	var r4: Dictionary = _drum(Vector3(-2.8, 1.2, -41.2), 1.1)
	# RIGHT (gold): up the stern, along the hull, up again, into the storm's eye
	_ledge(Vector3(4.0, 3.3, -13.6), Vector3(3.0, 6.3, 3.2), "alt")
	kit.wallrun(_w(Vector3(6.5, 4.5, -24.7)), Vector3(16.0, 6.5, 0.6), _yaw + 90.0)
	var l2: Dictionary = _blk(Vector3(3.8, 3.3, -37.0), 3.6, 4.0, "alt", 0.8, "none")
	_ledge(Vector3(3.8, 6.6, -42.4), Vector3(3.6, 9.9, 3.4), "alt")
	var portal: WarpPortal = _eye(Vector3(3.8, 6.6, -43.4), Vector3(2.5, 1.2, -46.9))
	var merge: Dictionary = _blk(Vector3(0, 1.2, -48.5), 12.0, 4.0, "main", 1.0, "none")
	var cp: Dictionary = _cp(Vector3(0, 1.2, -57.0))
	_ship(Vector3(11.0, 7.4, -30.0), 36.0, 8.0, 0.0, {"props": false, "env_y": 12.0, "masts": [0.1, 0.35], "mast_h": 14.0})
	_sign(Vector3(-3.5, 0, -6.6), BLUE)
	_sign(Vector3(4.0, 0, -6.6), BRASS)
	_hop(cp0, fork, Vector3(0, 0, 0.8))
	if route_variant != 1:
		r_walk(_w(Vector3(-3.5, 0, -8.8)))
		_hop(_area(Vector3(-3.5, 0, -8.0), 1.5, 2.0), r1, Vector3(0, 0, 3.1))
		_wait(func() -> bool: return _rod_safe(ra, 0.0, 1.9), _w(Vector3(-3.5, 0, -12.9)))
		r_walk(_w(Vector3(-3.5, 0, -19.4)))
		_hop(r1, r2)
		_hop(r2, r3, Vector3(0, 0, 3.3))
		_wait(func() -> bool: return _rod_safe(rb, 0.0, 1.9), _w(Vector3(-3.5, 1.2, -29.2)))
		r_walk(_w(Vector3(-3.5, 1.2, -35.9)))
		_hop(r3, r4)
		_hop(r4, merge, Vector3(-3.0, 0, 1.2))
	else:
		r_walk(_w(Vector3(4.0, 0, -8.8)))
		r_mantle(_w(Vector3(4.0, 0, -9.65)), _w(Vector3(4.0, 3.3, -13.2)))
		r_wallrun(_w(Vector3(4.3, 3.3, -14.85)), _w(Vector3(6.0, 4.7, -18.8)), _w(Vector3(6.0, 4.7, -29.7)), _w(Vector3(3.8, 3.3, -36.3)))
		r_mantle(_w(Vector3(3.8, 3.3, -38.65)), _w(Vector3(3.8, 6.6, -41.3)))
		r_portal(_w(Vector3(3.8, 6.6, -43.6)), portal.exit_point())
	_hop(merge, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	l2.clear()
	return cp["c"]


# ---- stage 14: The Falling Mast - run the toppled mast before the winch hauls it up, then a skiff -------

func _stage_14() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	_ship(Vector3(0, 0, -7.5), 8.0, 5.0, 90.0, {"env_y": 12.0})
	var deck_a: Dictionary = _area(Vector3(0, 0, -7.5), 4.0, 2.5)
	var mast := ArmadaMast.new()
	mast.length = 15.0
	mast.lie = 6.0
	mast.phase = 0.0
	mast.position = _w(Vector3(0, 0, -10.0))
	mast.rotation.y = deg_to_rad(_yaw)
	add_child(mast)
	_ship(Vector3(0, 0, -28.3), 8.0, 6.0, -90.0, {"env_y": 12.0})
	var deck_b: Dictionary = _area(Vector3(0, 0, -28.3), 4.0, 3.0)
	var lane: ArmadaCannon = _cannon(Vector3(14.2, 1.2, -17.5), "-x", 3.2, 0.3, 28.0, 0.0, 2.0, -1.0, true)
	_ship(Vector3(18.5, 0.35, -17.5), 20.0, 8.0, 180.0, {"env_y": 12.0, "masts": [0.2]})
	var sk: ArmadaDeck = _skiff(Vector3(0, 0.3, -37.0), Vector3(3.0, 0.4, 4.2), 4.8, 0.2)
	var cp: Dictionary = _cp(Vector3(0, 0.6, -45.5))
	# SHORTCUT: two 1 m buoys past the skiff
	var b1: Dictionary = _drum(Vector3(-3.4, 0.3, -35.6), 0.5, "accent", 0.5)
	var b2: Dictionary = _drum(Vector3(-3.4, 0.6, -40.6), 0.5, "accent", 0.5)
	var lp: Vector3 = _w(Vector3(0, 0, -17.5))
	_hop(cp0, deck_a, Vector3(0, 0, 0.5))
	r_walk(_w(Vector3(0, 0, -9.4)))
	_wait(func() -> bool: return mast.is_down_for(Game.course_time, 0.0, 3.4) and _clear(lane, lp, 0.4, 2.4), _w(Vector3(0, 0, -9.4)))
	r_walk(_w(Vector3(0, 0, -26.2)))
	if route_variant == 2:
		r_walk(_w(Vector3(-2.8, 0, -30.6)))
		r_jump(_w(Vector3(-3.3, 0, -30.95)), _w(b1["c"]))
		_hop(b1, b2)
		_hop(b2, cp, Vector3(-2.4, 0, 1.3))
	else:
		route.append({"kind": "x_jump", "from": _w(Vector3(0, 0, -30.95)), "to_node": sk, "to_local": Vector3(0, 0.2, 0) + _d(Vector3(0, 0, 0.5))})
		route.append({"kind": "x_jump", "from_node": sk, "from_local": Vector3(0, 0.2, 0) + _d(Vector3(0, 0, -1.6)), "to": _w(Vector3(0, 0.6, -44.0))})
	r_checkpoint()
	deck_b.clear()
	return cp["c"]


# ---- stage 15: Gun Tower - a propeller lifts you up the tower, a chimney of wall runs, mantle out ------

func _stage_15() -> Vector3:
	# the floor round the lift fan's shaft (a 2.8 m hole in the middle)
	_blk(Vector3(0, 0, -7.7), 5.0, 2.2, "alt", 1.0, "none")
	_blk(Vector3(0, 0, -12.1), 5.0, 1.0, "alt", 1.0, "none")
	_blk(Vector3(-1.95, 0, -10.2), 1.1, 2.8, "alt", 1.0, "none")
	_blk(Vector3(1.95, 0, -10.2), 1.1, 2.8, "alt", 1.0, "none")
	_prop(Vector3(0, -1.2, -10.2), 16.0, 82.0)
	var l1: Dictionary = _blk(Vector3(0, 9.0, -14.7), 3.0, 3.0, "main", 1.0, "none")
	_tower_panel(2.3, 10.2, -19.5, -26.0)
	_tower_panel(-2.3, 15.0, -24.5, -32.5)
	_tower_panel(2.3, 18.0, -30.5, -38.5)
	var top: Dictionary = _ledge(Vector3(-0.75, 20.9, -42.0), Vector3(4.5, 14.0, 4.0), "alt")
	var cp: Dictionary = _cp(Vector3(0, 20.9, -51.2))
	_tower(Vector3(0, 0, -26.0))
	r_jump(_w(Vector3(0, 0, -2.65)), _w(Vector3(0, 0, -7.6)))
	var y1: float = _w(l1["c"]).y
	_fly(_w(Vector3(0, 0, -10.2)), func() -> bool: return player.global_position.y > y1 + 2.2)
	_fly(_w((l1["c"] as Vector3) + Vector3(0, 0, 0.4)))
	r_walk(_w(Vector3(0, 9.0, -13.8)))
	r_wallrun(_w(Vector3(0.5, 9.0, -15.85)), _w(Vector3(1.7, 10.4, -20.6)), _w(Vector3(1.7, 10.4, -23.5)), _w(Vector3(-1.7, 14.5, -27.4)))
	r_wallrun(Vector3.ZERO, _w(Vector3(-1.7, 14.5, -27.4)), _w(Vector3(-1.7, 14.5, -30.4)), _w(Vector3(1.7, 17.5, -34.0)), true, true)
	r_wallrun(Vector3.ZERO, _w(Vector3(1.7, 17.5, -34.0)), _w(Vector3(1.7, 17.5, -35.4)), _w(Vector3(-0.75, 20.9, -40.6)), true, true)
	_hop(top, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


## A chimney wall-run panel at local x along z0..z1 (z0 > z1), backed by the tower's timber wall.
func _tower_panel(x: float, y: float, z0: float, z1: float, height: float = 7.0) -> void:
	kit.wallrun(_w(Vector3(x, y, (z0 + z1) * 0.5)), Vector3(absf(z0 - z1), height, 0.5), _yaw + 90.0)
	var back := Look.box(Vector3(0.6, height + 2.0, absf(z0 - z1) + 1.0), Look.flat(ArmadaDecor.OAK, 0.8), _w(Vector3(x + signf(x) * 0.55, y, (z0 + z1) * 0.5)))
	back.rotation.y = deg_to_rad(_yaw)
	add_child(back)


## The gun tower: a great timber keep on a fortress ship, open on the chimney side, brass-banded,
## guns poking from its ports and lanterns in its windows.
func _tower(c: Vector3) -> void:
	var oak: StandardMaterial3D = Look.flat(ArmadaDecor.OAK.lightened(0.05), 0.8)
	var brass: StandardMaterial3D = Look.flat(ArmadaDecor.BRASS, 0.3, 0.9)
	for sx: float in [-1.0, 1.0]:
		var wall := Look.box(Vector3(1.2, 40.0, 30.0), oak, _w(c + Vector3(sx * 3.7, 2.0, -3.0)))
		wall.rotation.y = deg_to_rad(_yaw)
		add_child(wall)
		for k: int in 4:
			var band := Look.box(Vector3(1.3, 0.3, 30.1), brass, _w(c + Vector3(sx * 3.7, -6.0 + float(k) * 8.0, -3.0)))
			band.rotation.y = deg_to_rad(_yaw)
			add_child(band)
			var gun := Look.cylinder(0.28, 1.6, Look.flat(ArmadaDecor.IRON, 0.4, 0.8), _w(c + Vector3(sx * 4.8, -2.0 + float(k) * 8.0, 4.0 - float(k) * 5.0)), 0.22, 12)
			gun.basis = _b * Basis(Vector3.BACK, PI * 0.5 * sx)
			add_child(gun)
			deco.lantern(_w(c + Vector3(sx * 4.45, 1.0 + float(k) * 8.0, -8.0 + float(k) * 3.0)), k % 2 == 0)
	# the fortress ship's hull under the keep
	deco.hull(_w(c + Vector3(0, -3.0, 2.0)), _yaw, 60.0, 16.0, 8.0, ArmadaDecor.PAINTS[1], {"castle": false, "bow_walk": false, "rails": false})
	deco.envelope(_w(c + Vector3(-22.0, 26.0, -4.0)), _yaw, 50.0, 8.0, ArmadaDecor.ENVELOPES[2])
	deco.envelope(_w(c + Vector3(22.0, 26.0, -4.0)), _yaw, 50.0, 8.0, ArmadaDecor.ENVELOPES[2])
	ArmadaFx.stack_smoke(self, _w(c + Vector3(0, 24.0, 10.0)), 1.6, 18)


# ---- stage 16: Cargo Hooks - slow hooks sweeping the stepping stones, crumbling crates, a tesla arc -----

func _stage_16() -> Vector3:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var ps: Array[Vector3] = [Vector3(0, 0, -8.2), Vector3(0.5, 0.6, -14.3), Vector3(-0.4, 1.2, -20.4)]
	var blocks: Array[Dictionary] = []
	var hooks: Array[Pendulum] = []
	for i: int in ps.size():
		blocks.append(_blk(ps[i], 2.2 if i == 0 else 2.0, 2.2 if i == 0 else 2.0, "alt", 0.8, "none"))
	# the hooks sweep the gaps between the stones (never the stones you stand on)
	var gz: Array[Vector3] = [Vector3(0.25, 0.6, -11.25), Vector3(0.05, 1.2, -17.35), Vector3(0.1, 1.2, -23.3)]
	for i: int in gz.size():
		hooks.append(_hook(gz[i] + Vector3(0, 10.0, 0), 8.5, 6.0, -0.13 * float(i)))
	kit.collapse(_w(Vector3(0.6, 1.2, -26.2)), 2.0, 0.5, 2.4)
	kit.collapse(_w(Vector3(-0.4, 1.8, -31.6)), 2.0, 0.5, 2.4)
	var p5: Dictionary = _blk(Vector3(0, 1.8, -36.4), 2.4, 3.0, "alt", 0.8, "none")
	var arc: LaserGate = _arc(Vector3(0, 1.8, -37.4), 2.4, 3.2, 0.35, 0.3)
	var cp: Dictionary = _cp(Vector3(0, 1.8, -44.0))
	_ship(Vector3(15.0, 4.0, -16.0), 20.0, 9.0, 180.0, {"env_y": 12.0, "masts": [0.1], "mast_h": 13.0})
	_ship(Vector3(-15.5, -2.0, -26.0), 26.0, 8.0, 180.0, {"env_y": 12.0, "masts": [0.2], "mast_h": 12.0})
	var h0: Pendulum = hooks[0]
	var h1: Pendulum = hooks[1]
	var h2: Pendulum = hooks[2]
	_hop(cp0, blocks[0])
	_wait(func() -> bool: return _hook_clear(h0, 0.0, 1.7))
	_hop(blocks[0], blocks[1])
	_wait(func() -> bool: return _hook_clear(h1, 0.0, 1.7))
	_hop(blocks[1], blocks[2])
	_wait(func() -> bool: return _hook_clear(h2, 0.0, 1.7))
	_hop(blocks[2], _area(Vector3(0.6, 1.2, -26.2), 1.0, 1.0))
	_hop(_area(Vector3(0.6, 1.2, -26.2), 1.0, 1.0), _area(Vector3(-0.4, 1.8, -31.6), 1.0, 1.0))
	_hop(_area(Vector3(-0.4, 1.8, -31.6), 1.0, 1.0), p5, Vector3(0, 0, 0.8))
	_wait(func() -> bool: return _dark(arc, 0.05, 1.5), _w(Vector3(0, 1.8, -35.6)))
	r_walk(_w(Vector3(0, 1.8, -37.55)))
	_hop(p5, cp, Vector3(0, 0, 1.5))
	r_checkpoint()
	return cp["c"]


# ---- stage 17: Boarding Planks - onto the flagship's lower deck, up her side, past the ram ------------

func _stage_17() -> Vector3:
	var plank: MovingPlatform = _plank(Vector3(0, -0.02, -7.5), Vector3(1.8, 0.3, 9.0), Vector3(0, 0, -9.4), 6.0, 0.4)
	_ship(Vector3(0, 0, -16.75), 20.0, 9.5, 90.0, {"env_y": 13.0, "masts": [0.3], "mast_h": 14.0, "depth": 5.0})
	var rod: ArmadaLightning = _rod(Vector3(0, 0, -16.8), 2.0, 4.6, 0.3, Vector3(2.1, 0, 0))
	var m1: Dictionary = _ledge(Vector3(0, 3.3, -23.9), Vector3(4.0, 6.3, 3.4))
	_ledge(Vector3(0, 6.6, -27.3), Vector3(3.6, 9.6, 3.4), "alt")
	var ram: Piston = _ram(Vector3(-3.4, 8.0, -30.8), Vector3(1.4, 1.2, 1.6), "+x", 3.2, 4.2, 0.0)
	var cp: Dictionary = _cp(Vector3(0, 6.6, -35.5))
	# the flagship's upper gun deck the ram punches out of
	var bulk := Look.box(Vector3(5.0, 6.0, 5.0), Look.flat(ArmadaDecor.PAINTS[1].lerp(ArmadaDecor.OAK, 0.4), 0.7), _w(Vector3(-5.7, 7.2, -30.8)))
	bulk.rotation.y = deg_to_rad(_yaw)
	add_child(bulk)
	deco.lantern(_w(Vector3(-3.0, 9.6, -28.1)), true)
	r_walk(_w(Vector3(0, 0, -2.4)))
	_wait(func() -> bool: return _plank_out(plank, 0.0, 2.0))
	r_walk(_w(Vector3(0, 0, -12.9)))
	_wait(func() -> bool: return _rod_safe(rod, 0.0, 2.1))
	r_walk(_w(Vector3(0, 0, -20.2)))
	r_mantle(_w(Vector3(0, 0, -20.2)), _w(Vector3(0, 3.3, -23.0)))
	r_mantle(_w(Vector3(0, 3.3, -23.05)), _w(Vector3(0, 6.6, -26.4)))
	r_walk(_w(Vector3(0, 6.6, -28.4)))
	_wait(func() -> bool: return _ram_clear(ram, 0.0, 1.9))
	r_jump(_w(Vector3(0, 6.6, -28.65)), _w(Vector3(0, 6.6, -34.0)))
	r_checkpoint()
	m1.clear()
	return cp["c"]


# ---- stage 18: The Flagship - the last rod, the last broadside, the great mainsail, the helm ----------

func _stage_18() -> void:
	var cp0: Dictionary = _area(Vector3.ZERO, 3.0, 3.0)
	var s1: Dictionary = _blk(Vector3(0, 0, -8.0), 3.0, 4.0)
	var s2: Dictionary = _blk(Vector3(0, 0, -16.5), 3.2, 8.0, "main", 0.8, "none")
	var rod: ArmadaLightning = _rod(Vector3(0, 0, -16.5), 1.8, 4.4, 0.2, Vector3(1.95, 0, 0))
	_bag(Vector3(0, 0, -16.5), 3.2, 8.0, 7.0)
	var s3: Dictionary = _blk(Vector3(0.2, 0.6, -25.5), 3.0, 3.0, "alt")
	var lane: ArmadaCannon = _cannon(Vector3(13.2, 1.3, -22.25), "-x", 3.6, 0.0, 26.0, 0.0, 2.0, -1.0, true)
	_ship(Vector3(17.5, 0.45, -22.0), 22.0, 8.0, 180.0, {"env_y": 12.0, "masts": [0.1], "house": 2})
	kit.wallrun(_w(Vector3(2.5, 1.8, -36.5)), Vector3(16, 6.5, 0.6), _yaw + 90.0)
	var s4: Dictionary = _blk(Vector3(-0.2, 0.6, -49.5), 3.6, 5.0, "alt", 0.8, "none")
	_ledge(Vector3(0, 3.9, -55.7), Vector3(8.0, 7.0, 3.4))
	_flagship(Vector3(0, 3.9, -57.5))
	kit.finish(_w(Vector3(0, 3.9, -64.4)), _yaw)
	_finish_pos = _w(Vector3(0, 3.9, -64.4))
	# the great mainsail bellying behind the last wall run
	var sail := deco.sail_sheet(Vector3.ZERO, 18.0, 12.0, 1.6, deco.canvas_mat())
	sail.position = _w(Vector3(3.8, 3.0, -36.5))
	sail.rotation.y = deg_to_rad(_yaw - 90.0)
	add_child(sail)
	add_child(Look.cylinder(0.5, 34.0, Look.flat(ArmadaDecor.OAK, 0.8), _w(Vector3(4.5, -6.0, -36.5)), 0.35, 10))
	add_child(deco.line(_w(Vector3(3.4, 9.1, -27.0)), _w(Vector3(3.4, 9.1, -46.0)), 0.24, Look.flat(ArmadaDecor.OAK, 0.8)))
	_hop(cp0, s1)
	_hop(s1, s2, Vector3(0, 0, 3.1))
	_wait(func() -> bool: return _rod_safe(rod, 0.0, 1.9), _w(Vector3(0, 0, -13.4)))
	r_walk(_w(Vector3(0, 0, -20.15)))
	var lp: Vector3 = _w(Vector3(0, 0, -22.25))
	_wait(func() -> bool: return _clear(lane, lp, 0.0, 1.8), _w(Vector3(0, 0, -20.15)))
	r_jump(_w(Vector3(0, 0, -20.15)), _w(Vector3(0.2, 0.6, -25.0)))
	r_wallrun(_w(Vector3(0.5, 0.6, -26.65)), _w(Vector3(2.0, 2.0, -30.6)), _w(Vector3(2.0, 2.0, -41.5)), _w(Vector3(-0.2, 0.6, -48.8)))
	r_mantle(_w(Vector3(0, 0.6, -51.65)), _w(Vector3(0, 3.9, -55.2)))
	r_walk(_w(Vector3(0, 3.9, -60.0)))
	r_walk(_w(Vector3(0, 3.9, -64.8)))
	s3.clear()
	s4.clear()


var _sun_disc: Node3D


## The flagship: her quarterdeck (the finish) and main deck stretching away toward the sunset, a huge
## hull under them, three masts, a vast gas envelope, the helm, lanterns and gilt everywhere.
## `stern` is the local point at the middle of her stern rail, on the deck.
func _flagship(stern: Vector3) -> void:
	var length: float = 64.0
	var beam: float = 15.0
	var hb := Basis(Vector3.UP, deg_to_rad(_yaw))
	var deck_len: float = length * ArmadaDecor.BOW
	# the walkable deck (quarterdeck + main deck) and the bow
	kit.plat(_w(stern + Vector3(0, 0, -deck_len * 0.5)), Vector3(beam, 1.6, deck_len), "main", 0.0, _yaw)
	var center: Vector3 = _w(stern + Vector3(0, 0, -length * 0.5))
	deco.hull(center, _yaw, length, beam, 9.0, ArmadaDecor.PAINTS[1], {"castle": false, "lit": 0.8})
	for m: float in [-0.05, 0.18, 0.36]:
		deco.mast(center + hb * Vector3(0, 0, m * length), 26.0, _yaw, beam * 1.2, ArmadaDecor.CANVAS.lerp(Color(1.0, 0.8, 0.6), 0.2))
	deco.envelope(center + Vector3(0, 32.0, 0), _yaw, length * 1.1, 11.0, [Color(0.55, 0.12, 0.1), Color(0.9, 0.78, 0.5)])
	for sx: float in [-1.0, 1.0]:
		for f: float in [-0.3, 0.0, 0.3]:
			add_child(deco.line(center + hb * Vector3(sx * beam * 0.5, 0.1, f * length), center + hb * Vector3(sx * 6.0, 23.0, f * length), 0.08, Look.flat(ArmadaDecor.ROPE, 0.9)))
		deco.propeller(center + hb * Vector3(sx * (beam * 0.5 + 2.5), -4.0, length * 0.42), 3.0, Vector3(0, _yaw, 0), 0.2 * sx)
	# the helm: a great brass-bound wheel on its binnacle, just past the finish
	var helm: Vector3 = stern + Vector3(0, 0, -11.0)
	var wheel := Node3D.new()
	wheel.position = _w(helm + Vector3(0, 1.6, 0))
	wheel.rotation.y = deg_to_rad(_yaw)
	add_child(wheel)
	var tm := TorusMesh.new()
	tm.inner_radius = 0.95
	tm.outer_radius = 1.12
	var rim := Look.mesh_node(tm, Look.flat(ArmadaDecor.OAK.lightened(0.15), 0.6))
	rim.rotation.x = PI * 0.5
	wheel.add_child(rim)
	for i: int in 8:
		var sp := Look.box(Vector3(0.08, 2.6, 0.08), Look.flat(ArmadaDecor.BRASS, 0.3, 0.9))
		sp.rotation.z = TAU * float(i) / 16.0
		wheel.add_child(sp)
	add_child(Look.box(Vector3(0.7, 1.1, 0.7), Look.flat(ArmadaDecor.OAK, 0.8), _w(helm + Vector3(0, 0.55, 0.3))))
	for sx: float in [-1.0, 1.0]:
		for k: int in 3:
			deco.lamp_post(_w(stern + Vector3(sx * (beam * 0.5 - 0.6), 0, -3.0 - float(k) * 8.0)), 3.0, k == 0)
		deco.flag(_w(stern + Vector3(sx * 3.0, 0, -1.0)), 6.0, BRASS if sx < 0.0 else RED, _yaw)
	ArmadaFx.rising(self, _w(stern + Vector3(0, 0.1, -7.0)), 5.0, 8.0, BRASS, 40)
	ArmadaFx.motes(self, _w(stern + Vector3(0, 5.0, -8.0)), _sz(Vector3(7.0, 5.0, 7.0)), 60, Color(2.6, 1.6, 0.8))
	# the sunset breaking through dead ahead: a swollen sun and the light fanning out round it
	_sun_disc = Node3D.new()
	_sun_disc.position = _w(stern + Vector3(0, 30.0, -620.0))
	add_child(_sun_disc)
	var disc := Fx.sprite(Color(2.6, 1.5, 0.7, 1.0), 150.0, Fx.Tex.DOT)
	(disc.material_override as StandardMaterial3D).disable_fog = true
	_sun_disc.add_child(disc)
	var glow := Fx.sprite(Color(1.2, 0.55, 0.25, 0.6), 520.0, Fx.Tex.DOT)
	(glow.material_override as StandardMaterial3D).disable_fog = true
	_sun_disc.add_child(glow)


# ---- environment ----------------------------------------------------------------------------------

## The storm light at the start (0) and at the flagship (1): a cold blue-grey thunderstorm that
## warms toward gold as you climb toward the sunset breaking through ahead.
const FOG_A := Color(0.3, 0.34, 0.44)
const FOG_B := Color(0.62, 0.44, 0.36)
const SUN_A := Color(1.0, 0.7, 0.45)
const SUN_B := Color(1.0, 0.62, 0.32)
const AMB_A := Color(0.5, 0.58, 0.74)
const AMB_B := Color(0.78, 0.6, 0.52)

var _hour: float = 0.0


func _restyle_environment() -> void:
	for n: Node in get_children():
		if n is WorldEnvironment:
			_env = (n as WorldEnvironment).environment
		elif n is DirectionalLight3D:
			if n.name == "Sun":
				_sun = n as DirectionalLight3D
			else:
				_fill = n as DirectionalLight3D
	_env.background_mode = Environment.BG_SKY
	_env.sky = ArmadaSky.make()
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = AMB_A
	_env.ambient_light_energy = 0.7
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.tonemap_exposure = 1.05
	_env.tonemap_white = 6.0
	_env.fog_enabled = true
	_env.fog_light_color = FOG_A
	_env.fog_density = 0.0042
	_env.fog_aerial_perspective = 0.4
	_env.fog_sky_affect = 0.2
	_env.fog_sun_scatter = 0.35
	_env.fog_height = -25.0
	_env.fog_height_density = 0.02
	_env.glow_enabled = true
	_env.glow_intensity = 0.65
	_env.glow_bloom = 0.06
	_env.glow_hdr_threshold = 1.1
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 1.1
	_env.adjustment_contrast = 1.12
	# a low sun ahead of you (toward the sunset: -Z, a little to the left), under the storm deck
	_sun.light_color = SUN_A
	_sun.light_energy = 1.3
	_sun.rotation_degrees = Vector3(-11, 195, 0)
	_sun.shadow_blur = 0.8
	_sun.light_angular_distance = 0.6
	# the "fill" is the cold storm light from overhead behind
	_fill.light_color = Color(0.55, 0.66, 0.9)
	_fill.light_energy = 0.45
	_fill.rotation_degrees = Vector3(-62, 20, 0)


## Swap every walkable surface to the wet deck-plank shader (same colours).
func _armada_materials() -> void:
	for mi: Node in find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi as MeshInstance3D
		var sm: ShaderMaterial = m.material_override as ShaderMaterial
		if sm == null or sm.shader != Look.PLATFORM_SHADER:
			continue
		var r := ShaderMaterial.new()
		r.shader = WOOD_SHADER
		for key: String in ["top_color", "side_color", "trim_color", "half_size", "is_round", "trim_glow"]:
			r.set_shader_parameter(key, sm.get_shader_parameter(key))
		m.material_override = r


## Every point the route passes (takeoffs, landings, walk targets) - set dressing keeps clear of them.
func _route_points() -> Array[Vector3]:
	var pts: Array[Vector3] = []
	for st: Dictionary in route:
		for key: String in ["from", "to", "entry", "exit", "top", "when_point", "point"]:
			if st.has(key) and st[key] is Vector3 and (st[key] as Vector3) != Vector3.ZERO:
				pts.append(st[key])
	for p: Vector3 in _cp_world:
		pts.append(p)
	return pts


func _clear_of(p: Vector3, pts: Array[Vector3], dist: float) -> bool:
	for q: Vector3 in pts:
		if Vector2(p.x - q.x, p.z - q.z).length() < dist:
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
	var sea_y: float = -60.0
	var sun_dir := Vector2(-0.26, -0.97)
	_cloud_mat = deco.cloud_sea(Vector3(mid.x, sea_y, mid.z), maxf(span.x, span.z) + 2400.0, sun_dir)
	# thunderheads towering out of the cloud sea all round, the far fleet between them
	for i: int in 16:
		var a: float = TAU * (float(i) + rng.randf() * 0.6) / 16.0
		var r: float = rng.randf_range(420.0, 760.0)
		deco.storm_tower(Vector3(mid.x + cos(a) * r, sea_y - 10.0, mid.z + sin(a) * r), rng.randf_range(50.0, 90.0), rng.randf_range(140.0, 260.0))
	var placed: int = 0
	var tries: int = 0
	while placed < 14 and tries < 300:
		tries += 1
		var p := Vector3(rng.randf_range(lo.x - 260.0, hi.x + 260.0), rng.randf_range(-20.0, 45.0), rng.randf_range(lo.z - 260.0, hi.z + 260.0))
		if not _clear_of(p, pts, 110.0):
			continue
		deco.far_ship(p, rng.randf_range(0.0, 360.0), rng.randf_range(1.3, 2.4), placed, rng.randf_range(0.8, 2.2))
		placed += 1
	# drifting cloud banks through the fleet, below and beside the route
	for i: int in 28:
		var cp: Vector3 = _cp_world[i % _cp_world.size()]
		var off := Vector3(rng.randf_range(-70.0, 70.0), rng.randf_range(-40.0, -14.0), rng.randf_range(-70.0, 70.0))
		if _clear_of(cp + off, pts, 30.0):
			kit.cloud(cp + off, rng.randf_range(3.0, 6.0))
	# the storm itself
	storm = ArmadaStorm.new()
	storm.center = mid
	storm.top_y = mid.y + 150.0
	storm.bottom_y = sea_y
	storm.cloud_mat = _cloud_mat
	storm.balloon_mats = deco.balloon_mats
	add_child(storm)
	# weather along the whole route: rain, torn scud, blown sparks and lamp motes
	for i: int in _cp_world.size():
		var here: Vector3 = _cp_world[i]
		var prev: Vector3 = _cp_world[i - 1] if i > 0 else Vector3.ZERO
		var c2: Vector3 = (here + prev) * 0.5 + Vector3(0, 4.0, 0)
		var ext := Vector3(absf(here.x - prev.x) * 0.5 + 14.0, 9.0, absf(here.z - prev.z) * 0.5 + 14.0)
		# the rain thins out as the sunset breaks through
		var wet: float = 1.0 - 0.6 * float(i) / float(maxi(_cp_world.size() - 1, 1))
		ArmadaFx.rain(self, c2, ext, int(150.0 * wet))
		ArmadaFx.scud(self, c2 + Vector3(0, -10.0, 0), ext + Vector3(30, 6, 30), 10)
		ArmadaFx.motes(self, c2, ext * 0.8, 24)


# ---- live effects -----------------------------------------------------------------------------------

func _process(dt: float) -> void:
	if player == null:
		return
	if _env != null:
		var target: float = clampf(float(current_checkpoint) / float(maxi(checkpoints.size(), 1)), 0.0, 1.0)
		_hour = move_toward(_hour, target, dt * 0.06)
		var k: float = _hour * _hour
		_env.fog_light_color = FOG_A.lerp(FOG_B, k)
		_env.ambient_light_color = AMB_A.lerp(AMB_B, k)
		_env.fog_density = lerpf(0.0042, 0.0028, k)
		_sun.light_color = SUN_A.lerp(SUN_B, k)
		_sun.light_energy = lerpf(1.3, 2.2, k)
		if storm != null:
			storm.intensity = 1.0 - 0.75 * k
	for e: Dictionary in _arrivals:
		e["cool"] = maxf(float(e["cool"]) - dt, 0.0)
		if float(e["cool"]) <= 0.0 and player.global_position.distance_to(e["at"]) < 2.5:
			e["cool"] = 3.0
			for p: GPUParticles3D in e["p"]:
				p.restart()
				p.emitting = true


## The flagship's guns fire a salute: brass and gold glints and a cloud of powder smoke burst from the
## quarterdeck, a wash of warm light, and the setting sun swells.
func _finish_sequence() -> void:
	var cols: Array[Color] = [BRASS, Color(1.0, 0.85, 0.55), BLUE]
	for i: int in 3:
		var b: GPUParticles3D = ArmadaFx.glints(self, _finish_pos + Vector3(0, 1.0 + float(i) * 1.2, 0), cols[i], 70, 9.0 + 2.0 * float(i))
		b.restart()
		b.emitting = true
	var s: GPUParticles3D = ArmadaFx.steam_burst(self, _finish_pos + Vector3(0, 0.4, 0), 2.5, 60, 9.0)
	s.restart()
	s.emitting = true
	WorldAudio.at(self, "armada_salute", _finish_pos + Vector3(0, 2.0, 0), 1.0, 80.0)
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.72, 0.42)
	flash.light_energy = 8.0
	flash.omni_range = 26.0
	flash.position = _finish_pos + Vector3(0, 4.0, 0)
	add_child(flash)
	var tw: Tween = create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 1.4)
	if _sun_disc != null:
		var tw2: Tween = create_tween()
		tw2.tween_property(_sun_disc, "scale", Vector3.ONE * 1.2, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw2.tween_property(_sun_disc, "scale", Vector3.ONE, 0.8)
	await get_tree().create_timer(0.9).timeout
