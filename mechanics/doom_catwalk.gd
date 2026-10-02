class_name DoomCatwalk
extends CollapsingPlatform
## Doom Fortress: a COLLAPSING CATWALK section - a length of steel grating on two stringers, its
## bolts long sheared. Land on it and it lurches, its warning strip strobes and sparks spit from
## the snapping bolts; a beat later (`delay`) it tears loose and falls into the pit, and it is
## bolted back in `respawn` seconds later (or at once when you respawn). Keep moving.
## Same contract and timing as CollapsingPlatform (box-shaped); only the look and sounds differ.

var _strip: StandardMaterial3D
var _snap: GPUParticles3D
var _was_state: int = -1


func _init() -> void:
	is_round = false


func _ready() -> void:
	super._ready()
	var iron: StandardMaterial3D = DoomDecor.iron()
	var steel: StandardMaterial3D = DoomDecor.steel()
	var along_x: bool = size.x > size.z
	var length: float = maxf(size.x, size.z)
	var span: float = minf(size.x, size.z)
	# the stringers under each long edge and cross-bars of grating on top
	for s: float in [-1.0, 1.0]:
		var off: float = s * (span * 0.5 - 0.06)
		var st := Look.box(Vector3(length, 0.3, 0.12) if along_x else Vector3(0.12, 0.3, length), iron,
				Vector3(0, -size.y * 0.5 - 0.12, off) if along_x else Vector3(off, -size.y * 0.5 - 0.12, 0))
		_vis.add_child(st)
	var bars: int = int(length / 0.35)
	for i: int in bars:
		var a: float = -length * 0.5 + (float(i) + 0.5) * length / float(bars)
		var bar := Look.box(Vector3(0.05, 0.03, span * 0.92) if along_x else Vector3(span * 0.92, 0.03, 0.05), steel,
				Vector3(a, size.y * 0.5 + 0.012, 0) if along_x else Vector3(0, size.y * 0.5 + 0.012, a))
		_vis.add_child(bar)
	# a warning strip along each long edge that strobes red while it is about to go
	_strip = StandardMaterial3D.new()
	_strip.albedo_color = Color(0.4, 0.05, 0.03)
	_strip.emission_enabled = true
	_strip.emission = Color(1.0, 0.1, 0.04)
	_strip.emission_energy_multiplier = 0.3
	for s2: float in [-1.0, 1.0]:
		var off2: float = s2 * (span * 0.5 - 0.02)
		var strip := Look.box(Vector3(length, 0.05, 0.06) if along_x else Vector3(0.06, 0.05, length), _strip,
				Vector3(0, size.y * 0.5 + 0.02, off2) if along_x else Vector3(off2, size.y * 0.5 + 0.02, 0))
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_vis.add_child(strip)
	_snap = DoomFx.spark_burst(28, DoomFx.HOT, Vector3(size.x * 0.45, 0.1, size.z * 0.45))
	add_child(_snap)


func _process(_dt: float) -> void:
	var st: int = int(_state)
	if st == State.SHAKING:
		_strip.emission_energy_multiplier = 4.0 if fmod(_timer, 0.16) < 0.08 else 0.6
	elif st != _was_state:
		_strip.emission_energy_multiplier = 0.3
	if st != _was_state:
		if st == State.SHAKING:
			# SOUND: doom_catwalk_creak - bolts shearing, the grating lurching (the beat before it goes)
			WorldAudio.at(self, "doom_catwalk_creak", global_position, 0.9, 30.0)
		elif st == State.FALLING:
			_snap.restart()
			_snap.emitting = true
			# SOUND: doom_catwalk_fall - the section tearing loose and clanging away into the pit
			WorldAudio.at(self, "doom_catwalk_fall", global_position, 1.0, 40.0)
		_was_state = st
