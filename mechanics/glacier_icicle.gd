class_name GlacierIcicle
extends Node3D
## Frostbite Pass: a FALLING ICICLE. It hangs from an overhang, shivers, lets go and drops
## on a fixed rhythm (Game.course_time) onto the frost ring painted on the floor under it;
## the ring warns where it will land - pale while it hangs, pulsing hot pink in the warning.
## Deadly while it falls and for a blink as it shatters on the floor; the shards melt away
## and a new icicle grows back out of the overhang. Positioned at the floor point under it
## (the ring's centre); the tip hangs `drop` metres above.
##   cycle: grow back -> hang -> shiver (`warn` s) -> fall -> shatter -> shards melt

@export var drop: float = 5.5
@export var length: float = 1.8
@export var radius: float = 0.34
@export var period: float = 3.0
@export var phase: float = 0.0
@export var warn: float = 0.85
## Radius of the frost ring = the shatter's splash on the floor.
@export var splash: float = 1.0

const GRAVITY: float = 34.0
const SHATTER: float = 0.14
const GONE: float = 0.55
const REGROW: float = 0.45
const BODY: float = 0.38

enum State { HANG, SHIVER, FALL, GONE }

var fall_time: float = 0.6
var _release: float = 0.0
var _holder: Node3D
var _ring_mat: StandardMaterial3D
var _ring: MeshInstance3D
var _shard_bits: Node3D
var _state: int = -1
var _frost: GPUParticles3D
var _sift: GPUParticles3D
var _burst: Array[GPUParticles3D] = []


func _ready() -> void:
	fall_time = sqrt(2.0 * maxf(drop, 0.2) / GRAVITY)
	_release = period - GONE - fall_time
	_build_visual()
	add_to_group("course_clock")
	snap_to_clock()


func snap_to_clock() -> void:
	_state = _state_at(Game.course_time)
	_apply(Game.course_time)
	_holder.reset_physics_interpolation()


# ---- the rhythm (pure functions of the course clock) ------------------------------------------

func _s(time: float) -> float:
	return fposmod(time / period + phase, 1.0) * period


func _state_at(time: float) -> int:
	var s: float = _s(time)
	if s >= _release + fall_time:
		return State.GONE
	if s >= _release:
		return State.FALL
	if s >= _release - warn:
		return State.SHIVER
	return State.HANG


## Height of the tip above the floor (0 once it has hit).
func tip_height_at(time: float) -> float:
	var s: float = _s(time)
	if s < _release:
		return drop
	var k: float = s - _release
	if k < fall_time:
		return maxf(drop - 0.5 * GRAVITY * k * k, 0.0)
	return 0.0


func is_falling_at(time: float) -> bool:
	var s: float = _s(time)
	return s >= _release and s < _release + fall_time


## Falling, or shattering on the floor.
func is_deadly_at(time: float) -> bool:
	var s: float = _s(time)
	return s >= _release and s < _release + fall_time + SHATTER


## Nothing comes down on the ring for the next `window` seconds.
func is_clear_for(time: float, window: float) -> bool:
	var s: float = 0.0
	while s <= window:
		if is_deadly_at(time + s):
			return false
		s += 0.03
	return is_deadly_at(time + window) == false


## Seconds until it next lets go (0 while falling).
func time_until_release(time: float) -> float:
	var s: float = _s(time)
	if s >= _release and s < _release + fall_time:
		return 0.0
	var d: float = _release - s
	return d if d > 0.0 else d + period


## Seconds since it last hit the floor.
func time_since_impact(time: float) -> float:
	var d: float = _s(time) - (_release + fall_time)
	return d if d >= 0.0 else d + period


# ---- gameplay ----------------------------------------------------------------------------------

func _physics_process(_dt: float) -> void:
	var t: float = Game.course_time
	if not is_deadly_at(t):
		return
	var level: Node = _level()
	if level == null:
		return
	var player: Node3D = level.get("player")
	if player == null:
		return
	var lp: Vector3 = to_local(player.global_position)
	var d: float = Vector2(lp.x, lp.z).length()
	if is_falling_at(t):
		var tip: float = tip_height_at(t)
		# the body (feet .. head) overlaps the falling spike
		if d < radius + BODY and lp.y < tip + length and lp.y + 1.7 > tip:
			level.call_deferred("fail", "hazard")
	elif d < splash and lp.y > -0.6 and lp.y < 1.2:
		level.call_deferred("fail", "hazard")


func _level() -> Node:
	var n: Node = self
	while n != null and not n.has_method("fail"):
		n = n.get_parent()
	return n


# ---- look -----------------------------------------------------------------------------------------

func _process(_dt: float) -> void:
	var t: float = Game.course_time
	var st: int = _state_at(t)
	if st != _state:
		_on_state(st)
		_state = st
	_apply(t)


## Event effects and sounds when the icicle changes state (never while snapping to the clock).
func _on_state(st: int) -> void:
	match st:
		State.SHIVER:
			WorldAudio.at(self, "icicle_crack", global_position + Vector3(0, drop + length, 0), 0.8, 40.0)
		State.FALL:
			WorldAudio.at(self, "icicle_fall", global_position + Vector3(0, drop, 0), 0.9, 40.0)
		State.GONE:
			WorldAudio.at(self, "icicle_shatter", global_position + Vector3(0, 0.3, 0), 1.0, 45.0)
			for p: GPUParticles3D in _burst:
				p.restart()


func _apply(t: float) -> void:
	var s: float = _s(t)
	var st: int = _state_at(t)
	# the spike: grows back out of the overhang, shivers, falls, is gone after the hit
	_holder.visible = st != State.GONE
	var grow: float = clampf(s / REGROW, 0.12, 1.0) if s < REGROW else 1.0
	_holder.scale = Vector3(grow, grow, grow)
	var top: float = tip_height_at(t) + length
	var shake := Vector3.ZERO
	if st == State.SHIVER:
		var k: float = 1.0 - (_release - s) / warn
		shake = Vector3(sin(t * 83.0), 0.0, cos(t * 71.0)) * (0.015 + 0.05 * k)
	_holder.position = Vector3(0, top, 0) + shake
	# the frost ring: pale while it hangs, pulsing hot in the warning, flashing on the hit
	var col: Color = GlacierFx.ICE
	var glow: float = 0.7
	if st == State.SHIVER:
		var k2: float = 1.0 - (_release - s) / warn
		col = GlacierFx.ICE.lerp(GlacierFx.DANGER, clampf(k2 * 1.6, 0.0, 1.0))
		glow = 1.5 + 3.5 * k2 * (0.6 + 0.4 * sin(t * 30.0))
	elif st == State.FALL:
		col = GlacierFx.DANGER
		glow = 5.0
	elif st == State.GONE:
		var since: float = s - (_release + fall_time)
		col = GlacierFx.DANGER.lerp(GlacierFx.ICE, clampf(since / 0.3, 0.0, 1.0))
		glow = lerpf(5.0, 0.7, clampf(since / 0.3, 0.0, 1.0))
	_ring_mat.albedo_color = col
	_ring_mat.emission = col
	_ring_mat.emission_energy_multiplier = glow
	if _frost != null:
		_frost.amount_ratio = 1.0 if st == State.SHIVER or st == State.FALL else 0.2
		_sift.emitting = st == State.SHIVER
	# the melting shards left on the floor
	_shard_bits.visible = st == State.GONE
	if st == State.GONE:
		var since2: float = s - (_release + fall_time)
		_shard_bits.scale = Vector3.ONE * clampf(1.0 - since2 / GONE, 0.05, 1.0)


func _build_visual() -> void:
	var ice: StandardMaterial3D = GlacierFx.ice_mat(GlacierFx.ICE, 0.5, 0.86)
	_holder = Node3D.new()
	add_child(_holder)
	# the spike hangs down from the holder's origin (its base)
	_holder.add_child(Look.cylinder(0.02, length, ice, Vector3(0, -length * 0.5, 0), radius, 10))
	for i: int in 3:
		var a: float = TAU * float(i) / 3.0 + 0.4
		var l2: float = length * (0.45 + 0.12 * float(i))
		var side := Look.cylinder(0.015, l2, ice, Vector3(cos(a) * radius * 0.75, -l2 * 0.5, sin(a) * radius * 0.75), radius * 0.45, 8)
		_holder.add_child(side)
	# a lump of rime where it hangs from (stays put while the spike falls and regrows)
	var cap := Look.sphere(radius * 1.35, GlacierFx.ice_mat(GlacierFx.SNOW, 0.2, 0.95), Vector3(0, drop + length + 0.1, 0))
	cap.scale = Vector3(1.0, 0.55, 1.0)
	add_child(cap)
	# the frost ring on the floor
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.albedo_color = GlacierFx.ICE
	_ring_mat.emission_enabled = true
	_ring_mat.emission = GlacierFx.ICE
	_ring_mat.emission_energy_multiplier = 0.7
	for r: float in [splash, splash * 0.45]:
		var tm := TorusMesh.new()
		tm.inner_radius = r - 0.09
		tm.outer_radius = r
		tm.rings = 40
		tm.ring_segments = 4
		_ring = Look.mesh_node(tm, _ring_mat, Vector3(0, 0.04, 0))
		_ring.scale = Vector3(1, 0.25, 1)
		_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_ring)
	# a cross of frost spokes inside the ring
	for i: int in 4:
		var spoke := Look.box(Vector3(splash * 0.5, 0.02, 0.05), _ring_mat, Vector3(0, 0.04, 0))
		spoke.rotation.y = TAU * float(i) / 8.0
		spoke.position = Basis(Vector3.UP, spoke.rotation.y) * Vector3(splash * 0.7, 0.04, 0)
		spoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(spoke)
	# melting shards lying on the floor after the hit
	_shard_bits = Node3D.new()
	for i: int in 6:
		var a3: float = TAU * float(i) / 6.0 + 0.3
		var r3: float = splash * (0.25 + 0.12 * float(i % 3))
		var b := Look.box(Vector3(0.22, 0.12, 0.34), ice, Vector3(cos(a3) * r3, 0.07, sin(a3) * r3))
		b.rotation = Vector3(0.3 * float(i % 2), a3, 0.2)
		_shard_bits.add_child(b)
	add_child(_shard_bits)
	# particles: frost glitter rising off the ring, rime sifting off the spike as it shivers,
	# and the shatter (clear chunks, a glitter spray, a powder puff, a frost ring on the floor)
	_frost = Fx.emitter({"amount": 14, "lifetime": 1.2, "preprocess": 1.2, "shape": "ring", "ring_radius": splash,
		"ring_inner": splash * 0.8, "ring_height": 0.05, "dir": Vector3.UP, "spread": 20.0, "speed": Vector2(0.3, 1.0),
		"tex": Fx.Tex.STAR, "size": 0.22, "curve": "pop", "color": GlacierFx.hot(GlacierFx.GLOW, 2.2),
		"aabb": AABB(Vector3(-splash - 1, -1, -splash - 1), Vector3(splash * 2 + 2, 4, splash * 2 + 2))})
	_frost.position = Vector3(0, 0.05, 0)
	add_child(_frost)
	_sift = Fx.emitter({"amount": 12, "lifetime": 1.0, "emitting": false, "shape": "sphere", "radius": radius,
		"dir": Vector3.DOWN, "spread": 10.0, "speed": Vector2(0.5, 1.5), "gravity": Vector3(0, -6, 0),
		"additive": false, "size": 0.09, "color": Color(1, 1, 1, 0.9), "fade": PackedFloat32Array([1.0, 1.0, 0.0]),
		"aabb": AABB(Vector3(-2, -drop - 2, -2), Vector3(4, drop + 4, 4))})
	_sift.position = Vector3(0, drop + length, 0)
	add_child(_sift)
	var chunks: GPUParticles3D = GlacierFx.shards(Vector3(0.3, 0.2, 0.3), 16, 0.18)
	var spray: GPUParticles3D = GlacierFx.frost_burst(GlacierFx.GLOW, 26, 6.0)
	var puff: GPUParticles3D = GlacierFx.powder(0.6, 10, 1.2)
	var wave: GPUParticles3D = GlacierFx.frost_ring(splash * 1.6)
	for p: GPUParticles3D in [chunks, spray, puff]:
		p.position = Vector3(0, 0.3, 0)
		add_child(p)
		_burst.append(p)
	wave.position = Vector3(0, 0.06, 0)
	add_child(wave)
	_burst.append(wave)
