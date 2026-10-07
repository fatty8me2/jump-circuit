class_name SiegeOil
extends Node3D
## Castle Siege: BOILING OIL. A great iron cauldron hangs on a timber bracket over the head of a
## stone gutter; on the course clock it tips and a tongue of boiling oil pours over its lip and
## sweeps down the lane at `speed` m/s, `pour` seconds long, then runs off the far end. Anything in the
## lane under the tongue (below `depth`) goes back to the checkpoint.
## The tell: the cauldron starts tipping `tilt_time` seconds (at least 0.8) before the oil leaves the
## lip - it groans on its chains, the fire under it roars, bubbling oil slops over the rim and the
## gutter's warning lanterns flash amber - and the tongue itself is slow enough to watch coming.
## Local frame: the lane runs along +X from x = 0 (under the lip) to x = `length`, it is `width` wide
## along Z, and its floor is at y = 0. A pure function of Game.course_time.

@export var length: float = 12.0
@export var width: float = 4.0
@export var period: float = 6.0
@export var phase: float = 0.0
## Speed of the oil front along the lane (m/s).
@export var speed: float = 6.0
## Seconds the cauldron pours (the tongue's length is speed * pour).
@export var pour: float = 1.2
## Kill height above the lane floor.
@export var depth: float = 1.4
## Seconds the cauldron tips before the oil leaves its lip (the tell, at least 0.8).
@export var tilt_time: float = 1.2

var _pot: Node3D
var _tongue: MeshInstance3D
var _stream: MeshInstance3D
var _spatter: GPUParticles3D
var _slop: GPUParticles3D
var _lamps: Array[MeshInstance3D] = []
var _lamp_on: StandardMaterial3D
var _lamp_off: StandardMaterial3D
var _fire_light: OmniLight3D
var _loop: AudioStreamPlayer3D
var _tipped: int = -999
var _poured: int = -999
var _hit_tick: int = -100


func _ready() -> void:
	tilt_time = maxf(tilt_time, 0.8)
	_build()
	_apply(Game.course_time)
	add_to_group("course_clock")


func _s(time: float) -> float:
	return fposmod(time / maxf(period, 0.01) + phase, 1.0) * period


func _cycle(time: float) -> int:
	return int(floor(time / maxf(period, 0.01) + phase))


## The oil's span [tail, front] along local X at `time` (empty when tail >= front).
func span_at(time: float) -> Vector2:
	var s: float = _s(time) - tilt_time
	if s < 0.0:
		return Vector2(0.0, 0.0)
	var front: float = minf(speed * s, length + 1.0)
	var tail: float = clampf(speed * (s - pour), 0.0, length + 1.0)
	return Vector2(tail, front)


## True if the oil covers lane position `x` (with `margin` either side) at `time`.
func covers(x: float, time: float, margin: float = 0.6) -> bool:
	var sp: Vector2 = span_at(time)
	return sp.y > sp.x and x > sp.x - margin and x < sp.y + margin


## True if lane position `x` stays clear over [now + a, now + b].
func clear_for(x: float, a: float, b: float, margin: float = 0.6) -> bool:
	var s: float = a
	while s <= b:
		if covers(x, Game.course_time + s, margin):
			return false
		s += 0.04
	return true


## 0 (upright) .. 1 (fully tipped) at `time`.
func tip_at(time: float) -> float:
	var s: float = _s(time)
	if s < tilt_time:
		var k: float = s / maxf(tilt_time, 0.01)
		return k * k * 0.75
	if s < tilt_time + pour:
		return 0.75 + 0.25 * minf((s - tilt_time) / 0.25, 1.0)
	var r: float = clampf((s - tilt_time - pour) / 1.0, 0.0, 1.0)
	return 1.0 - r * r * (3.0 - 2.0 * r)


func snap_to_clock() -> void:
	_apply(Game.course_time)


func _physics_process(_dt: float) -> void:
	var t: float = Game.course_time
	var sp: Vector2 = span_at(t)
	if sp.y <= sp.x:
		return
	var pl: Node3D = WorldAudio.local_player(self)
	if pl == null:
		return
	var p: Vector3 = to_local(pl.global_position)
	if absf(p.z) < width * 0.5 and p.y > -0.5 and p.y < depth and p.x > sp.x - 0.3 and p.x < sp.y + 0.3:
		var tick: int = Engine.get_physics_frames()
		if tick - _hit_tick > 30:
			_hit_tick = tick
			KitUtil.kill(self)


func _process(_dt: float) -> void:
	_apply(Game.course_time)


func _apply(t: float) -> void:
	var s: float = _s(t)
	var cyc: int = _cycle(t)
	var tip: float = tip_at(t)
	_pot.rotation.z = -tip * 1.2
	var sp: Vector2 = span_at(t)
	var on: bool = sp.y > sp.x
	_tongue.visible = on
	if on:
		var a: float = maxf(sp.x, 0.0)
		var b: float = minf(sp.y, length)
		if b > a + 0.02:
			_tongue.scale = Vector3(b - a, 1.0, 1.0)
			_tongue.position = Vector3((a + b) * 0.5, depth * 0.3, 0)
		else:
			_tongue.visible = false
	var pouring: bool = s >= tilt_time and s < tilt_time + pour
	_stream.visible = pouring
	_spatter.emitting = on and sp.y < length + 0.5
	if on:
		_spatter.position = Vector3(clampf(sp.y, 0.0, length), 0.4, 0)
	var warning: bool = s < tilt_time
	_slop.emitting = warning or pouring
	var blink: bool = warning and fmod(t, 0.24) < 0.12
	for l: MeshInstance3D in _lamps:
		l.material_override = _lamp_on if (blink or pouring) else _lamp_off
	_fire_light.light_energy = 1.2 + 2.2 * tip + 0.3 * sin(t * 13.0)
	if warning and cyc != _tipped:
		_tipped = cyc
		# SOUND: siege_oil_tilt - the cauldron's chains groan and the oil slops as it starts to tip (the tell)
		WorldAudio.at(self, "siege_oil_tilt", _pot.global_position, 0.9, 40.0)
	if pouring and cyc != _poured:
		_poured = cyc
		# SOUND: siege_oil_pour - the first gout of boiling oil hitting the gutter
		WorldAudio.at(self, "siege_oil_pour", global_position + global_basis * Vector3(1.0, 0, 0), 1.0, 40.0)
	WorldAudio.set_active(_loop, on)


func _build() -> void:
	var dark: StandardMaterial3D = Look.flat(Color(0.2, 0.14, 0.1), 0.9)
	var iron: StandardMaterial3D = Look.flat(Color(0.14, 0.14, 0.16), 0.45, 0.75)
	var stone: StandardMaterial3D = Look.flat(Color(0.34, 0.32, 0.3), 0.9)
	var frame_h: float = depth + 3.4
	# the timber bracket: two posts either side of the lane's head and a beam across
	for sz: float in [-1.0, 1.0]:
		add_child(Look.box(Vector3(0.5, frame_h, 0.5), dark, Vector3(-1.2, frame_h * 0.5, sz * (width * 0.5 + 0.6))))
		var brace := Look.box(Vector3(0.2, 1.7, 0.2), dark, Vector3(-0.8, frame_h - 0.9, sz * (width * 0.5 + 0.6)))
		brace.rotation.z = -0.7
		add_child(brace)
	add_child(Look.box(Vector3(0.6, 0.55, width + 1.9), dark, Vector3(-1.2, frame_h, 0)))
	# the cauldron on a trunnion, lip toward +X; a fire basket glows under it
	_pot = Node3D.new()
	_pot.position = Vector3(-1.2, frame_h - 1.1, 0)
	add_child(_pot)
	var r: float = minf(width * 0.42, 1.5)
	_pot.add_child(Look.sphere(r, iron, Vector3(0, -r * 0.35, 0)))
	_pot.add_child(Look.cylinder(r * 1.12, 0.18, iron, Vector3(0, r * 0.45, 0), -1.0, 20))
	var oil_m := StandardMaterial3D.new()
	oil_m.albedo_color = Color(0.1, 0.055, 0.02)
	oil_m.roughness = 0.12
	oil_m.metallic = 0.4
	oil_m.emission_enabled = true
	oil_m.emission = Color(1.0, 0.45, 0.08)
	oil_m.emission_energy_multiplier = 0.9
	var surf := Look.cylinder(r * 1.0, 0.06, oil_m, Vector3(0, r * 0.42, 0), -1.0, 20)
	surf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pot.add_child(surf)
	_pot.add_child(Look.box(Vector3(0.9, 0.28, 0.7), iron, Vector3(r + 0.25, r * 0.38, 0)))
	for sx: float in [-1.0, 1.0]:
		var handle := Look.cylinder(0.05, 0.9, iron, Vector3(0, r * 0.5, sx * (r + 0.2)), -1.0, 5)
		handle.rotation.x = PI * 0.5
		_pot.add_child(handle)
	var fire_m: StandardMaterial3D = Look.flat(Color(1.0, 0.5, 0.12), 0.5, 0.0, 3.0)
	var fire_pit := Look.box(Vector3(1.4, 0.18, 1.4), fire_m, Vector3(-1.2, frame_h - 1.1 - r * 1.1, 0))
	fire_pit.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fire_pit)
	# the gutter: a stone trough with amber lanterns along both sides
	add_child(Look.box(Vector3(length + 2.0, 0.3, width), Look.flat(Color(0.1, 0.075, 0.06), 0.9), Vector3(length * 0.5, -0.15, 0)))
	for sz2: float in [-1.0, 1.0]:
		add_child(Look.box(Vector3(length + 2.0, 0.18, 0.3), stone, Vector3(length * 0.5, 0.05, sz2 * (width * 0.5 + 0.15))))
	_lamp_on = Look.flat(Color(1.0, 0.6, 0.1), 0.4, 0.0, 4.0)
	_lamp_off = Look.flat(Color(0.3, 0.12, 0.04), 0.4, 0.0, 0.3)
	var nl: int = maxi(int(length / 4.0), 2)
	for i: int in nl:
		for sz3: float in [-1.0, 1.0]:
			var lamp := Look.sphere(0.14, _lamp_off, Vector3(1.5 + float(i) * (length - 2.0) / float(nl - 1), 0.4, sz3 * (width * 0.5 + 0.35)))
			lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(lamp)
			_lamps.append(lamp)
	# the tongue (a unit box scaled along X each frame) and the falling stream from the lip
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color(0.12, 0.06, 0.02, 0.92)
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.roughness = 0.1
	tm.metallic = 0.3
	tm.emission_enabled = true
	tm.emission = Color(1.0, 0.42, 0.06)
	tm.emission_energy_multiplier = 1.1
	var bm := BoxMesh.new()
	bm.size = Vector3(1.0, depth * 0.6, width - 0.1)
	_tongue = Look.mesh_node(bm, tm)
	_tongue.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_tongue)
	var sh: float = frame_h - 1.0 + r * 0.3
	_stream = Look.cylinder(0.3, sh, tm, Vector3(-1.2 + r + 0.6, sh * 0.5, 0), 0.2, 10)
	_stream.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_stream)
	var vis := AABB(Vector3(-4, -2, -width - 2), Vector3(length + 8, 10, width * 2 + 4))
	_spatter = Fx.emitter({"amount": 30, "lifetime": 0.6, "shape": "box", "extents": Vector3(0.4, 0.1, width * 0.45),
		"dir": Vector3.UP, "spread": 50.0, "speed": Vector2(2.0, 5.0), "gravity": Vector3(0, -14.0, 0), "tex": Fx.Tex.DOT,
		"size": 0.16, "color": Color(2.6, 1.3, 0.4), "curve": "shrink", "emitting": false, "aabb": vis})
	add_child(_spatter)
	_slop = Fx.emitter({"amount": 20, "lifetime": 0.8, "emitting": false, "shape": "box", "extents": Vector3(0.4, 0.1, 0.4),
		"dir": Vector3(1, 0.4, 0), "spread": 40.0, "speed": Vector2(1.0, 3.0), "gravity": Vector3(0, -12.0, 0),
		"size": 0.14, "color": Color(2.4, 1.2, 0.4), "curve": "shrink", "aabb": vis})
	_slop.position = Vector3(-1.2 + r + 0.5, frame_h - 1.1 + r * 0.5, 0)
	add_child(_slop)
	# steam rising off the oil
	var steam: GPUParticles3D = Fx.emitter({"amount": 14, "lifetime": 2.0, "tex": Fx.Tex.SMOKE, "additive": false, "size": 0.8,
		"shape": "box", "extents": Vector3(r * 0.7, 0.05, r * 0.7), "dir": Vector3.UP, "spread": 15.0, "speed": Vector2(0.5, 1.2),
		"curve": "puff", "color": Color(0.9, 0.85, 0.8, 0.5), "fade": PackedFloat32Array([0.0, 0.6, 0.0]),
		"preprocess": 2.0, "aabb": vis})
	steam.position = Vector3(-1.2, frame_h - 0.4, 0)
	add_child(steam)
	_fire_light = OmniLight3D.new()
	_fire_light.light_color = Color(1.0, 0.5, 0.15)
	_fire_light.light_energy = 1.2
	_fire_light.omni_range = maxf(width * 2.5, 9.0)
	_fire_light.shadow_enabled = false
	_fire_light.position = Vector3(0.5, frame_h - 1.5, 0)
	add_child(_fire_light)
	# SOUND: siege_oil_loop - oil rushing and sizzling down the gutter (loop, while the tongue is out)
	_loop = WorldAudio.loop("siege_oil_loop", _tongue, -4.0, 28.0, 5.0, false)
