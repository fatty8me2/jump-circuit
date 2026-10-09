class_name ArcaneHourglass
extends Node3D
## Arcane Library: HOURGLASS TIME GATE. A stone doorway with a great hourglass on its lintel. The
## gate is OPEN while the sand runs: the top bulb drains over `open_time` s, a bright stream falling
## through the neck. When the last grain drops the doorway is sealed with a curtain of frozen golden
## sand for `period - open_time` s (touching it sends you back to the checkpoint) while the sand
## climbs back up into the top bulb; the instant it is full again the gate opens and the sand runs.
## All of it is a pure function of the course clock, identical for every racer.
##   s 0..open_time-warn   open, sand running
##   ..open_time           WARNING (>= 0.8 s): the stream thins, the bulb's last sand glows, the curtain
##                         flickers into being (still harmless) and the hourglass ticks
##   ..period              CLOSED: the curtain is solid gold and deadly; the sand refills
## Place the node at the middle of the doorway's floor; the gate faces local -Z (you walk through it).

@export var width: float = 3.0
@export var height: float = 3.4
@export var period: float = 8.0
@export var phase: float = 0.0
@export var open_time: float = 4.6
@export var warn: float = 1.1

var _kill: Area3D
var _sheet: MeshInstance3D
var _sheet_mat: ShaderMaterial
var _sand_top: MeshInstance3D
var _sand_bottom: MeshInstance3D
var _stream: MeshInstance3D
var _glass_mat: StandardMaterial3D
var _state: int = -1
var _puff: GPUParticles3D
var _tick: GPUParticles3D


func _ready() -> void:
	warn = clampf(maxf(warn, KitUtil.MIN_TELL), KitUtil.MIN_TELL, open_time - 0.5)
	period = maxf(period, open_time + 1.5)
	var stone: StandardMaterial3D = Look.flat(Look.c("side").lerp(Look.c("metal"), 0.25), 0.7)
	var gold: StandardMaterial3D = Look.flat(Look.c("trim"), 0.3, 0.8, 0.2)
	# the doorway: two pillars (solid) and a lintel
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var px: float = width * 0.5 + 0.4
	for sx: float in [-1.0, 1.0]:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.8, height + 0.9, 1.0)
		cs.shape = bs
		cs.position = Vector3(sx * px, (height + 0.9) * 0.5, 0)
		body.add_child(cs)
		add_child(Look.box(Vector3(0.8, height + 0.9, 1.0), stone, Vector3(sx * px, (height + 0.9) * 0.5, 0)))
		add_child(Look.box(Vector3(0.96, 0.22, 1.16), gold, Vector3(sx * px, 0.11, 0)))
		add_child(Look.box(Vector3(0.96, 0.18, 1.16), gold, Vector3(sx * px, height + 0.7, 0)))
	var lc := CollisionShape3D.new()
	var lb := BoxShape3D.new()
	lb.size = Vector3(width + 1.6, 0.9, 1.0)
	lc.shape = lb
	lc.position = Vector3(0, height + 0.45, 0)
	body.add_child(lc)
	add_child(Look.box(Vector3(width + 1.6, 0.9, 1.0), stone, Vector3(0, height + 0.45, 0)))
	add_child(Look.box(Vector3(width + 1.8, 0.14, 1.2), gold, Vector3(0, height + 0.95, 0)))
	_build_glass(height + 1.02)
	# the sand curtain and its kill volume
	_sheet_mat = ShaderMaterial.new()
	_sheet_mat.shader = preload("res://visual/arcane_sheet.gdshader")
	_sheet_mat.set_shader_parameter("size", Vector2(width, height))
	var qm := QuadMesh.new()
	qm.size = Vector2(width, height)
	_sheet = Look.mesh_node(qm, _sheet_mat, Vector3(0, height * 0.5, 0))
	_sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_sheet)
	_kill = Area3D.new()
	_kill.collision_layer = 0
	_kill.collision_mask = 2
	_kill.monitorable = false
	var ks := BoxShape3D.new()
	ks.size = Vector3(width, height, 0.5)
	var kcs := CollisionShape3D.new()
	kcs.shape = ks
	kcs.position = Vector3(0, height * 0.5, 0)
	_kill.add_child(kcs)
	add_child(_kill)
	var vis := AABB(Vector3(-width, -1.0, -3.0), Vector3(width * 2.0, height + 4.0, 6.0))
	_puff = Fx.burst({"amount": 40, "lifetime": 0.7, "shape": "box", "extents": Vector3(width * 0.5, height * 0.5, 0.2),
		"spread": 90.0, "dir": Vector3(0, 0, -1), "speed": Vector2(1.0, 3.5), "tex": Fx.Tex.STAR, "size": 0.2,
		"color": Color(2.4, 1.7, 0.7), "gravity": Vector3(0, -2.0, 0), "aabb": vis})
	_puff.position = Vector3(0, height * 0.5, 0)
	add_child(_puff)
	_tick = Fx.emitter({"amount": 16, "lifetime": 0.8, "emitting": false, "shape": "box",
		"extents": Vector3(width * 0.5, 0.1, 0.15), "dir": Vector3.UP, "spread": 25.0, "speed": Vector2(0.5, 1.6),
		"tex": Fx.Tex.DOT, "size": 0.14, "color": Color(2.4, 1.8, 0.8), "curve": "shrink", "aabb": vis})
	_tick.position = Vector3(0, height + 0.1, -0.2)
	add_child(_tick)
	_apply(Game.course_time)
	add_to_group("course_clock")


func _build_glass(base_y: float) -> void:
	_glass_mat = StandardMaterial3D.new()
	_glass_mat.albedo_color = Color(0.8, 0.88, 1.0, 0.22)
	_glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glass_mat.roughness = 0.05
	_glass_mat.metallic = 0.2
	_glass_mat.emission_enabled = true
	_glass_mat.emission = Color(0.7, 0.55, 1.0)
	_glass_mat.emission_energy_multiplier = 0.25
	var gold: StandardMaterial3D = Look.flat(Look.c("trim"), 0.3, 0.8, 0.2)
	var sand: StandardMaterial3D = Look.flat(Color(1.0, 0.78, 0.32), 0.6, 0.0, 1.6).duplicate() as StandardMaterial3D
	var hb: float = 1.0
	var r: float = 0.62
	# two bulbs (cones meeting at the neck), end plates, and a gilt cage
	var top := Look.cylinder(0.05, hb, _glass_mat, Vector3(0, base_y + 0.12 + hb * 1.5, 0), r, 20)
	top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(top)
	var bottom := Look.cylinder(r, hb, _glass_mat, Vector3(0, base_y + 0.12 + hb * 0.5, 0), 0.05, 20)
	bottom.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bottom)
	add_child(Look.cylinder(r + 0.14, 0.12, gold, Vector3(0, base_y + 0.06, 0), -1.0, 20))
	add_child(Look.cylinder(r + 0.14, 0.12, gold, Vector3(0, base_y + 0.18 + hb * 2.0, 0), -1.0, 20))
	for i: int in 3:
		var a: float = TAU * float(i) / 3.0 + 0.5
		add_child(Look.cylinder(0.04, hb * 2.0 + 0.1, gold, Vector3(cos(a) * (r + 0.1), base_y + 0.12 + hb, sin(a) * (r + 0.1)), -1.0, 6))
	# the sand: two cones whose height follows the level (scaled about their neck / floor ends)
	var st_pivot := Node3D.new()
	st_pivot.position = Vector3(0, base_y + 0.12 + hb, 0)
	add_child(st_pivot)
	_sand_top = Look.cylinder(0.05, hb * 0.92, sand, Vector3(0, hb * 0.46, 0), r * 0.9, 16)
	_sand_top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	st_pivot.add_child(_sand_top)
	var sb_pivot := Node3D.new()
	sb_pivot.position = Vector3(0, base_y + 0.12, 0)
	add_child(sb_pivot)
	_sand_bottom = Look.cylinder(r * 0.9, hb * 0.92, sand, Vector3(0, hb * 0.46, 0), 0.05, 16)
	_sand_bottom.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sb_pivot.add_child(_sand_bottom)
	_stream = Look.cylinder(0.025, hb * 0.9, sand, Vector3(0, base_y + 0.12 + hb * 0.5, 0), -1.0, 6)
	_stream.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_stream)
	# the cone meshes sit on their pivots, so the pivot's Y scale is the sand level
	_sand_top.set_meta("pivot", st_pivot)
	_sand_bottom.set_meta("pivot", sb_pivot)


# ---- timeline ---------------------------------------------------------------------------

func _s(time: float) -> float:
	return KitUtil.cycle_s(time, period, phase)


## 0 open, 1 warning (still open), 2 closed.
func state_at(time: float) -> int:
	var s: float = _s(time)
	if s < open_time - warn:
		return 0
	if s < open_time:
		return 1
	return 2


func is_closed_at(time: float) -> bool:
	return _s(time) >= open_time


## True when the doorway stays passable for the whole of [time, time + window].
func open_for(time: float, window: float) -> bool:
	return KitUtil.holds_for(func(x: float) -> bool: return not is_closed_at(x), time, window, 0.04)


## Seconds until the gate next opens (0 while it is open).
func open_in(time: float) -> float:
	var s: float = _s(time)
	return 0.0 if s < open_time else period - s


## Seconds of open time left (0 when closed).
func open_left(time: float) -> float:
	var s: float = _s(time)
	return maxf(open_time - s, 0.0)


## 0..1: how full the top bulb is.
func sand_level(time: float) -> float:
	var s: float = _s(time)
	if s < open_time:
		return 1.0 - s / open_time
	return KitUtil.smooth((s - open_time) / (period - open_time))


func snap_to_clock() -> void:
	_apply(Game.course_time)


func _physics_process(_dt: float) -> void:
	if not is_closed_at(Game.course_time):
		return
	for body: Node3D in _kill.get_overlapping_bodies():
		if body is Player:
			KitUtil.kill(self)
			return


func _process(_dt: float) -> void:
	_apply(Game.course_time)


func _apply(t: float) -> void:
	var s: float = _s(t)
	var st: int = state_at(t)
	var amount: float = 0.0
	if st == 1:
		var k: float = clampf((s - (open_time - warn)) / warn, 0.0, 1.0)
		var flick: float = 0.5 + 0.5 * sin(t * (9.0 + 16.0 * k))
		amount = 0.05 + 0.45 * k * flick
	elif st == 2:
		amount = clampf((s - open_time) / 0.18, 0.0, 1.0)
		amount = maxf(amount, 0.5)
	elif s < 0.3:
		# just opened: the curtain thins away
		amount = 1.0 - s / 0.3
	_sheet.visible = amount > 0.01
	_sheet_mat.set_shader_parameter("amount", amount)
	# the sand
	var lvl: float = sand_level(t)
	var pt: Node3D = _sand_top.get_meta("pivot") as Node3D
	var pb: Node3D = _sand_bottom.get_meta("pivot") as Node3D
	pt.scale = Vector3.ONE * maxf(pow(lvl, 0.3333), 0.001)
	pb.scale = Vector3.ONE * maxf(pow(1.0 - lvl, 0.3333), 0.001)
	_stream.visible = s < open_time and lvl > 0.02
	var pulse: float = 1.0
	if st == 1:
		pulse = 1.0 + 1.6 * (0.5 + 0.5 * sin(t * 18.0))
	(_sand_top.material_override as StandardMaterial3D).emission_energy_multiplier = 1.4 * pulse
	_glass_mat.emission_energy_multiplier = 0.25 + (0.9 if st == 1 else 0.0)
	if st != _state:
		var prev: int = _state
		_state = st
		match st:
			0:
				if prev == 2:
					# SOUND: arcane_hourglass_open - the sand begins to run: a soft glassy chime as the curtain thins
					WorldAudio.at(self, "arcane_hourglass_open", global_position, 0.8, 30.0)
			1:
				_tick.emitting = true
				# SOUND: arcane_hourglass_warn - ticking and a rising shimmer as the last sand runs (~1.1 s ahead)
				WorldAudio.at(self, "arcane_hourglass_warn", global_position + Vector3(0, height, 0), 0.9, 30.0)
			2:
				_tick.emitting = false
				_puff.restart()
				_puff.emitting = true
				# SOUND: arcane_hourglass_shut - the sand curtain slams into the doorway
				WorldAudio.at(self, "arcane_hourglass_shut", global_position + Vector3(0, height * 0.5, 0), 1.0, 34.0)
