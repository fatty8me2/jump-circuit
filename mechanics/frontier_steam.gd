class_name FrontierSteam
extends LaserGate
## Wild West Heist's "laser": a scalding STEAM JET. A brass nozzle blasts a jet of live steam across
## the walkway to a catch-pipe on the far side, on the same fixed rhythm as a LaserGate (it is one:
## is_on_at / time_until_on / time_until_off all work, and touching the live jet sends you back to the
## checkpoint). The look is steam, not light: a white roaring jet with puffs boiling off it, and
## before it fires the nozzle sputters and spits for `warn` seconds (0.8 s here) so it never surprises.
## Local X runs between the nozzle (-X end) and the catch-pipe.

var _jet: GPUParticles3D
var _boil: GPUParticles3D
var _spit: GPUParticles3D
var _hiss: AudioStreamPlayer3D
var _steam_on: bool = false
var _sputter: bool = false


func _init() -> void:
	warn = 0.8


## Replaces the laser's crackle and sparks with steam (called from LaserGate._ready).
func _build_fx() -> void:
	# retint the beam as a dense white jet and its guide as a faint wet streak
	var white := StandardMaterial3D.new()
	white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	white.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	white.albedo_color = Color(1.0, 0.98, 0.95, 0.55)
	white.emission_enabled = true
	white.emission = Color(0.9, 0.9, 0.88)
	white.emission_energy_multiplier = 0.6
	_beam.material_override = white
	for c: Node in _beam.get_children():
		(c as MeshInstance3D).visible = false
	_guide_mat.albedo_color = Color(0.9, 0.9, 0.95, 0.12)
	var vis := AABB(Vector3(-size.x * 0.5 - 3.0, -2.0, -3.0), Vector3(size.x + 6.0, 7.0, 6.0))
	var half: float = size.x * 0.5
	# brass nozzle and catch-pipe over the base posts
	var brass: StandardMaterial3D = Look.flat(Color(0.9, 0.68, 0.3), 0.3, 0.85, 0.15)
	var iron: StandardMaterial3D = Look.flat(Color(0.16, 0.15, 0.15), 0.45, 0.6)
	for sx: float in [-1.0, 1.0]:
		var bell := Look.cylinder(0.32 if sx < 0.0 else 0.4, 0.7, brass, Vector3(sx * (half + 0.15), 0, 0), 0.18 if sx < 0.0 else 0.3, 14)
		bell.rotation.z = -sx * PI * 0.5
		add_child(bell)
		add_child(Look.box(Vector3(0.5, maxf(size.y + 0.8, 1.2) + 0.1, 0.5), iron, Vector3(sx * (half + 0.45), 0, 0)))
	# the live jet: fast white streaks and puffs racing along it
	_jet = Fx.emitter({"amount": clampi(int(size.x * 10.0), 20, 70), "lifetime": 0.35, "emitting": false,
		"shape": "box", "extents": Vector3(0.05, size.y * 0.3, size.z * 0.3), "offset": Vector3(-half, 0, 0),
		"dir": Vector3.RIGHT, "spread": 6.0, "speed": Vector2(size.x * 2.6, size.x * 3.4), "tex": Fx.Tex.SMOKE,
		"additive": false, "size": 0.8, "scale": Vector2(0.6, 1.2), "curve": "puff",
		"color": Color(1.0, 1.0, 1.0, 0.65), "fade": PackedFloat32Array([0.0, 0.9, 0.5, 0.0]), "local": true, "aabb": vis})
	add_child(_jet)
	_boil = Fx.smoke({"amount": clampi(int(size.x * 4.0), 10, 30), "lifetime": 1.2, "one_shot": false,
		"explosiveness": 0.0, "emitting": false, "shape": "box", "extents": Vector3(half, size.y * 0.3, 0.2),
		"dir": Vector3.UP, "spread": 40.0, "speed": Vector2(0.8, 2.2), "size": 1.4,
		"gravity": Vector3(0, 0.8, 3.0), "color": Color(0.96, 0.95, 0.94, 0.4), "aabb": vis})
	add_child(_boil)
	# the tell: the nozzle spits and sputters before it fires
	_spit = Fx.smoke({"amount": 10, "lifetime": 0.5, "one_shot": false, "explosiveness": 0.0, "emitting": false,
		"shape": "sphere", "radius": 0.15, "offset": Vector3(-half + 0.2, 0, 0), "dir": Vector3.RIGHT, "spread": 30.0,
		"speed": Vector2(1.5, 3.5), "size": 0.6, "color": Color(1.0, 1.0, 1.0, 0.7), "local": true, "aabb": vis})
	add_child(_spit)
	_steam_on = is_on_at(Game.course_time)
	_hiss = WorldAudio.loop("frontier_steam_hiss", self, -8.0, 24.0, 4.0, _steam_on)


func _process(_dt: float) -> void:
	var t: float = Game.course_time
	var on: bool = is_on_at(t)
	var sputter: bool = not on and time_until_on(t) < warn
	if sputter != _sputter:
		_sputter = sputter
		_spit.emitting = sputter
		if sputter:
			# SOUND: the valve rattling and spitting before the jet fires
			WorldAudio.at(self, "frontier_steam_sputter", global_position - global_basis.x * size.x * 0.5, 0.6, 28.0)
	if on != _steam_on:
		_steam_on = on
		_jet.emitting = on
		_boil.emitting = on
		WorldAudio.set_active(_hiss, on)
		if on:
			WorldAudio.at(self, "frontier_steam_burst", global_position - global_basis.x * size.x * 0.5, 0.9, 35.0)
