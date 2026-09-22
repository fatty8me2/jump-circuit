extends Node
## Sound: pooled one-shots (flat and positional) plus a looping music bed.
## All clips are synthesised by tools/gen_audio.py into res://audio.

const NAMES: Array[String] = ["jump", "land", "bounce", "checkpoint", "crumble", "collapse", "creak",
	"finish", "respawn", "tick", "go", "ui", "beacon"]

var _streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _pool3d: Array[AudioStreamPlayer3D] = []
var _music: AudioStreamPlayer
var _music_name: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for n: String in NAMES:
		var p: String = "res://audio/%s.wav" % n
		if ResourceLoader.exists(p):
			_streams[n] = load(p)
	for i: int in 10:
		var a := AudioStreamPlayer.new()
		a.bus = "SFX"
		add_child(a)
		_pool.append(a)
	for i: int in 6:
		var b := AudioStreamPlayer3D.new()
		b.bus = "SFX"
		b.unit_size = 9.0
		b.max_distance = 70.0
		add_child(b)
		_pool3d.append(b)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	_music.finished.connect(func() -> void:
		if _music_name != "":
			_music.play())
	add_child(_music)


func play(clip: String, pitch_var: float = 0.0, volume: float = 1.0, pitch: float = 1.0) -> void:
	if not _streams.has(clip):
		return
	for a: AudioStreamPlayer in _pool:
		if not a.playing:
			a.stream = _streams[clip]
			a.pitch_scale = pitch + randf_range(-pitch_var, pitch_var)
			a.volume_db = linear_to_db(clampf(volume, 0.01, 1.5))
			a.play()
			return


func play_at(clip: String, pos: Vector3, pitch_var: float = 0.05, volume: float = 1.0) -> void:
	if not _streams.has(clip):
		return
	for b: AudioStreamPlayer3D in _pool3d:
		if not b.playing:
			b.stream = _streams[clip]
			b.global_position = pos
			b.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
			b.volume_db = linear_to_db(clampf(volume, 0.01, 1.5))
			b.play()
			return


func music(track: String) -> void:
	if track == _music_name:
		return
	_music_name = track
	var p: String = "res://audio/music_%s.wav" % track
	if track == "" or not ResourceLoader.exists(p):
		_music.stop()
		return
	_music.stream = load(p)
	_music.play()
