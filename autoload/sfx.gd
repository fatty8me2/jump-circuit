extends Node
## Sound: pooled one-shots (flat and positional) plus a looping music bed.
## All clips are synthesised by tools/gen_audio.py into res://audio.

const NAMES: Array[String] = ["jump", "land", "bounce", "checkpoint", "crumble", "collapse", "creak",
	"finish", "respawn", "tick", "go", "ui", "beacon", "whack", "step"]
## Track changes crossfade: the old bed fades out while the new one fades in.
const MUSIC_FADE_OUT: float = 0.6
const MUSIC_FADE_IN: float = 0.9
const MUSIC_SILENT_DB: float = -40.0

var _streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _pool3d: Array[AudioStreamPlayer3D] = []
var _music_players: Array[AudioStreamPlayer] = []
var _music: AudioStreamPlayer    # the current (audible or fading-in) player
var _music_name: String = ""
var _music_tween: Tween


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
	for i: int in 2:
		var m := AudioStreamPlayer.new()
		m.bus = "Music"
		# tracks import as loops, so this is only a fallback; never restart a fading-out player
		m.finished.connect(func() -> void:
			if m == _music and _music_name != "":
				m.play())
		add_child(m)
		_music_players.append(m)
	_music = _music_players[0]


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
	if _music_tween != null:
		_music_tween.kill()
	var outgoing: AudioStreamPlayer = _music
	_music = _music_players[1] if outgoing == _music_players[0] else _music_players[0]
	_music.stop()
	var p: String = "res://audio/music_%s.wav" % track
	var stream: AudioStream = load(p) if track != "" and ResourceLoader.exists(p) else null
	if stream == null and not outgoing.playing:
		return
	# Sfx runs ALWAYS, so the fade also completes while the tree is paused
	_music_tween = create_tween().set_parallel(true)
	if outgoing.playing:
		_music_tween.tween_property(outgoing, "volume_db", MUSIC_SILENT_DB, MUSIC_FADE_OUT)
		_music_tween.tween_callback(outgoing.stop).set_delay(MUSIC_FADE_OUT)
	if stream != null:
		_music.stream = stream
		_music.volume_db = MUSIC_SILENT_DB
		_music.play()
		_music_tween.tween_property(_music, "volume_db", 0.0, MUSIC_FADE_IN)
