class_name DoomReactor
extends Node3D
## Doom Fortress set piece: the REACTOR CORE in meltdown. A colossal column of white-hot energy in
## a containment cage, rising through the middle of the reactor chamber. At each TIER (a height
## listed in `tiers`) a field emitter girdles the core; on the course clock each emitter charges
## and then FIRES a ring of energy that sweeps out across its tier to `reach` metres from the core's
## axis. Anyone on that tier inside the ring's reach (from the floor to head height) while it fires
## goes back to the checkpoint. The pulses climb the core: tier k fires `step` seconds after tier
## k - 1, every `period` seconds - follow a pulse up and you climb in its wake.
## The tell: each emitter charges for `charge` seconds first - it brightens from dull red to white,
## crackles, its reach ring on the floor strobes - and the core's hum swells. The floor of every
## tier is marked at the ring's reach: beyond the red line you are always safe.
## A pure function of Game.course_time. Positioned at the core's base centre.

@export var core_radius: float = 3.0
@export var height: float = 40.0
## Tier floor heights above the node.
@export var tiers: PackedFloat32Array = PackedFloat32Array([4.0, 8.0])
@export var reach: float = 9.5
@export var period: float = 7.0
@export var phase: float = 0.0
## Seconds between one tier firing and the next one up.
@export var step: float = 1.0
@export var fire: float = 0.5
@export var charge: float = 1.2
## Height above a tier's floor the ring covers.
@export var band: float = 2.4

var _emit_mats: Array[StandardMaterial3D] = []
var _reach_mats: Array[StandardMaterial3D] = []
var _waves: Array[MeshInstance3D] = []
var _wave_mats: Array[StandardMaterial3D] = []
var _fired: Array[int] = []
var _charged: Array[int] = []
var _core_mat: ShaderMaterial
var _core_light: OmniLight3D
var _hum: AudioStreamPlayer3D
var _hit_tick: int = -100
var _dead: bool = false
var _bursts: Array[GPUParticles3D] = []


func _ready() -> void:
	_build()
	add_to_group("course_clock")


func tier_count() -> int:
	return tiers.size()


## Seconds into tier k's own cycle at `time` (0 = the moment it fires).
func _s(k: int, time: float) -> float:
	return fposmod(time - phase * period - float(k) * step, period)


func is_firing(k: int, time: float) -> bool:
	return not _dead and _s(k, time) < fire


## 0..1 charge of tier k's emitter at `time` (1 just before it fires).
func charge_at(k: int, time: float) -> float:
	var s: float = _s(k, time)
	var until: float = period - s
	if s < fire or until > charge:
		return 0.0
	return clampf(1.0 - until / charge, 0.0, 1.0)


## Tier k does not fire at any point of [now + a, now + b].
func zone_clear(k: int, a: float, b: float) -> bool:
	var s: float = a
	while s <= b:
		if is_firing(k, Game.course_time + s):
			return false
		s += 0.04
	return true


## Seconds from `time` until tier k next fires.
func time_until_fire(k: int, time: float) -> float:
	var s: float = _s(k, time)
	return 0.0 if s < fire else period - s


func snap_to_clock() -> void:
	pass


## The off switch thrown: the pulses stop and the core cools (the finish sequence).
func shut_down() -> void:
	_dead = true
	if _core_mat != null:
		var tw: Tween = create_tween()
		tw.tween_method(func(v: float) -> void: _core_mat.set_shader_parameter("heat", v), 2.4, 0.25, 2.5)
	if _core_light != null:
		var tw2: Tween = create_tween()
		tw2.tween_property(_core_light, "light_energy", 0.3, 2.5)
	for m: StandardMaterial3D in _emit_mats:
		m.emission_energy_multiplier = 0.2
	for m2: StandardMaterial3D in _reach_mats:
		m2.emission_energy_multiplier = 0.1
	WorldAudio.set_active(_hum, false)


func _physics_process(_dt: float) -> void:
	if _dead:
		return
	var t: float = Game.course_time
	var pl: Node3D = WorldAudio.local_player(self)
	if pl == null:
		return
	var p: Vector3 = to_local(pl.global_position)
	var r: float = Vector2(p.x, p.z).length()
	if r > reach + 0.3:
		return
	for k: int in tiers.size():
		if not is_firing(k, t):
			continue
		var h: float = tiers[k]
		# the wave front sweeps out from the core over the first 40% of the firing
		var front: float = lerpf(core_radius, reach + 0.3, clampf(_s(k, t) / (fire * 0.4), 0.0, 1.0))
		if p.y > h - 0.4 and p.y < h + band and r < front:
			var tick: int = Engine.get_physics_frames()
			if tick - _hit_tick > 30:
				_hit_tick = tick
				var n: Node = self
				while n != null and not n.has_method("fail"):
					n = n.get_parent()
				if n != null:
					n.call_deferred("fail", "hazard")
			return


func _process(_dt: float) -> void:
	var t: float = Game.course_time
	var hot: float = 0.0
	for k: int in tiers.size():
		var c: float = 0.0 if _dead else charge_at(k, t)
		var firing: bool = is_firing(k, t)
		hot = maxf(hot, c)
		var m: StandardMaterial3D = _emit_mats[k]
		m.emission_energy_multiplier = 0.6 + 4.0 * c * (0.75 + 0.25 * sin(t * 40.0)) + (5.0 if firing else 0.0)
		m.emission = Color(1.0, 0.25, 0.08).lerp(Color(1.0, 0.85, 0.7), c)
		var rm: StandardMaterial3D = _reach_mats[k]
		rm.emission_energy_multiplier = (4.0 if fmod(t, 0.2) < 0.1 else 1.0) if c > 0.0 else (5.0 if firing else 1.0)
		var w: MeshInstance3D = _waves[k]
		w.visible = firing
		if firing:
			var f: float = clampf(_s(k, t) / (fire * 0.4), 0.0, 1.0)
			var rr: float = lerpf(core_radius, reach, f)
			w.scale = Vector3(rr, 1.0, rr)
			var wc: Color = _wave_mats[k].albedo_color
			wc.a = 0.85 * (1.0 - clampf((_s(k, t) - fire * 0.4) / (fire * 0.6), 0.0, 1.0)) + 0.1
			_wave_mats[k].albedo_color = wc
		var cyc: int = int(floor((t - phase * period - float(k) * step) / period))
		if c > 0.0 and _charged[k] != cyc:
			_charged[k] = cyc
			# SOUND: doom_reactor_charge - the tier's emitter whining up to fire (the ~1.2 s warning)
			WorldAudio.at(self, "doom_reactor_charge", global_position + Vector3(0, tiers[k], 0), 0.9, 35.0)
		if firing and _fired[k] != cyc:
			_fired[k] = cyc
			_bursts[k].restart()
			_bursts[k].emitting = true
			# SOUND: doom_reactor_pulse - the ring of energy cracking out across the tier
			WorldAudio.at(self, "doom_reactor_pulse", global_position + Vector3(0, tiers[k], 0), 1.0, 45.0)
	if _core_light != null and not _dead:
		_core_light.light_energy = 3.0 + 3.0 * hot


func _build() -> void:
	var iron: StandardMaterial3D = DoomDecor.iron()
	var steel: StandardMaterial3D = DoomDecor.steel()
	# the core: a white-hot column (the molten shader run hot and fast) in a containment cage
	_core_mat = ShaderMaterial.new()
	_core_mat.shader = DoomDecor.MOLTEN_SHADER
	_core_mat.set_shader_parameter("hot_color", Color(1.0, 0.85, 0.6))
	_core_mat.set_shader_parameter("warm_color", Color(1.0, 0.32, 0.08))
	_core_mat.set_shader_parameter("crust_color", Color(0.25, 0.04, 0.02))
	_core_mat.set_shader_parameter("flow", Vector2(0.0, -2.0))
	_core_mat.set_shader_parameter("heat", 2.4)
	_core_mat.set_shader_parameter("crust", 0.25)
	_core_mat.set_shader_parameter("scale", 0.6)
	var core := Look.mesh_node(_cyl(core_radius * 0.82, height, 28), _core_mat, Vector3(0, height * 0.5, 0))
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(core)
	# containment cage: vertical bars and hoops
	var bars: int = 16
	for i: int in bars:
		var a: float = TAU * float(i) / float(bars)
		add_child(Look.box(Vector3(0.28, height, 0.28), iron, Vector3(cos(a) * core_radius, height * 0.5, sin(a) * core_radius)))
	var hoops: int = int(height / 6.0)
	for j: int in hoops:
		add_child(Look.cylinder(core_radius + 0.12, 0.35, steel, Vector3(0, 3.0 + float(j) * 6.0, 0), -1.0, 32))
	# a solid core column for collision (you can not stand on or pass through the core)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = core_radius
	cyl.height = height
	cs.shape = cyl
	cs.position = Vector3(0, height * 0.5, 0)
	body.add_child(cs)
	add_child(body)
	# emitters, reach markers and wave rings per tier
	for k: int in tiers.size():
		var h: float = tiers[k]
		var em := StandardMaterial3D.new()
		em.albedo_color = Color(0.3, 0.05, 0.02)
		em.emission_enabled = true
		em.emission = Color(1.0, 0.25, 0.08)
		em.emission_energy_multiplier = 0.6
		_emit_mats.append(em)
		var girdle := Look.cylinder(core_radius + 0.45, 0.7, em, Vector3(0, h + 0.9, 0), -1.0, 32)
		girdle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(girdle)
		add_child(Look.cylinder(core_radius + 0.6, 0.2, iron, Vector3(0, h + 0.45, 0), -1.0, 32))
		add_child(Look.cylinder(core_radius + 0.6, 0.2, iron, Vector3(0, h + 1.35, 0), -1.0, 32))
		var rm := StandardMaterial3D.new()
		rm.albedo_color = Color(0.4, 0.04, 0.02)
		rm.emission_enabled = true
		rm.emission = Color(1.0, 0.1, 0.04)
		rm.emission_energy_multiplier = 1.0
		_reach_mats.append(rm)
		var tm := TorusMesh.new()
		tm.inner_radius = reach - 0.1
		tm.outer_radius = reach + 0.1
		tm.rings = 64
		tm.ring_segments = 4
		var marker := Look.mesh_node(tm, rm, Vector3(0, h + 0.04, 0))
		marker.scale = Vector3(1.0, 0.3, 1.0)
		marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(marker)
		var wm := StandardMaterial3D.new()
		wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		wm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		wm.cull_mode = BaseMaterial3D.CULL_DISABLED
		wm.albedo_color = Color(1.0, 0.55, 0.3, 0.8)
		_wave_mats.append(wm)
		# the wave: a unit-radius band (scaled out to its front each frame), floor to band height
		var wcm := CylinderMesh.new()
		wcm.top_radius = 1.0
		wcm.bottom_radius = 1.0
		wcm.height = band
		wcm.radial_segments = 48
		wcm.rings = 1
		wcm.cap_top = false
		wcm.cap_bottom = false
		var wave := Look.mesh_node(wcm, wm, Vector3(0, h + band * 0.5, 0))
		wave.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wave.visible = false
		add_child(wave)
		_waves.append(wave)
		var burst: GPUParticles3D = Fx.burst({"amount": 70, "lifetime": 0.6, "explosiveness": 1.0, "shape": "ring",
			"ring_radius": core_radius + 0.6, "ring_inner": core_radius + 0.3, "dir": Vector3.UP, "spread": 20.0,
			"radial_vel": Vector2(14.0, 18.0), "speed": Vector2(0.2, 1.0), "damping": Vector2(2.0, 3.0),
			"tex": Fx.Tex.SPARK, "facing": "velocity", "size": Vector2(0.06, 0.6), "color": Color(3.0, 1.8, 1.0),
			"aabb": AABB(Vector3(-reach - 4, -2, -reach - 4), Vector3(reach * 2 + 8, 6, reach * 2 + 8))})
		burst.position = Vector3(0, h + 0.9, 0)
		add_child(burst)
		_bursts.append(burst)
		_fired.append(-999)
		_charged.append(-999)
	_core_light = OmniLight3D.new()
	_core_light.light_color = Color(1.0, 0.5, 0.2)
	_core_light.light_energy = 3.0
	_core_light.omni_range = 26.0
	_core_light.position = Vector3(0, height * 0.55, 0)
	add_child(_core_light)
	# energy motes streaming up the core
	var motes: GPUParticles3D = Fx.emitter({"amount": 120, "lifetime": 3.0, "shape": "ring", "ring_radius": core_radius * 0.7,
		"ring_inner": 0.0, "ring_height": 0.5, "dir": Vector3.UP, "spread": 4.0, "speed": Vector2(height * 0.25, height * 0.35),
		"tex": Fx.Tex.DOT, "size": 0.25, "curve": "pop", "color": Color(3.0, 1.9, 1.1),
		"preprocess": 3.0, "aabb": AABB(Vector3(-core_radius - 3, -2, -core_radius - 3), Vector3(core_radius * 2 + 6, height + 8, core_radius * 2 + 6))})
	add_child(motes)
	# SOUND: doom_reactor_hum - the core's deep, throbbing hum (loop)
	_hum = WorldAudio.loop("doom_reactor_hum", self, -2.0, 60.0, 12.0)


func _cyl(r: float, h: float, seg: int) -> CylinderMesh:
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = seg
	cm.rings = 4
	return cm
