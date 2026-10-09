class_name PartySfx
extends Node
## Party Mode sounds: its own small pool over the SFX bus, playing the party_*.wav clips
## (synthesised by party/gen_party_audio.py). A clip that is missing falls back to a
## pitched main-game Sfx clip, so the mode never goes silent.

const CLIPS: Array[String] = ["pickup", "roll", "whoosh", "hit", "ko", "boom", "zap", "charge",
	"beam", "slash", "powerup", "pop", "spring", "freeze", "warp", "chime", "wind", "clank",
	"tick", "land", "warn", "tally", "fanfare", "coin", "zone", "fuse", "blast", "elim", "pass", "drum", "champion",
	"shell", "siren", "strike", "fake", "turbo", "ghost", "steal", "decoy", "shock"]
## Fallback main-game clip and pitch per party clip.
const FALLBACK: Dictionary = {
	"pickup": ["checkpoint", 1.5], "roll": ["tick", 1.3], "whoosh": ["jump", 0.7], "hit": ["whack", 1.0],
	"ko": ["whack", 0.6], "boom": ["collapse", 0.8], "zap": ["tick", 0.5], "charge": ["creak", 1.6],
	"beam": ["bounce", 0.5], "slash": ["jump", 1.6], "powerup": ["finish", 1.3], "pop": ["bounce", 1.8],
	"spring": ["bounce", 1.2], "freeze": ["crumble", 1.6], "warp": ["respawn", 1.4], "chime": ["checkpoint", 1.0],
	"wind": ["creak", 0.5], "clank": ["whack", 1.5],
	"tick": ["tick", 1.6], "land": ["checkpoint", 1.3], "warn": ["tick", 0.5], "tally": ["tick", 2.0], "fanfare": ["finish", 1.2],
	"shell": ["jump", 1.8], "siren": ["tick", 0.4], "strike": ["collapse", 0.7], "fake": ["whack", 0.7], "turbo": ["jump", 0.6],
	"ghost": ["creak", 1.3], "steal": ["checkpoint", 1.7], "decoy": ["bounce", 1.5], "shock": ["whack", 0.5],
	"coin": ["checkpoint", 2.0], "zone": ["checkpoint", 0.8], "fuse": ["tick", 1.2], "blast": ["collapse", 0.9], "elim": ["whack", 0.5],
	"pass": ["jump", 1.8], "drum": ["creak", 1.0], "champion": ["finish", 1.0],
}

static var _streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _pool3d: Array[AudioStreamPlayer3D] = []


func _ready() -> void:
	if _streams.is_empty():
		for n: String in CLIPS:
			var p: String = "res://audio/party_%s.wav" % n
			if ResourceLoader.exists(p):
				_streams[n] = load(p)
	for i: int in 8:
		var a := AudioStreamPlayer.new()
		a.bus = "SFX"
		add_child(a)
		_pool.append(a)
	for i: int in 10:
		var b := AudioStreamPlayer3D.new()
		b.bus = "SFX"
		b.unit_size = 10.0
		b.max_distance = 80.0
		add_child(b)
		_pool3d.append(b)


## Non-positional (the local player's own actions).
func play(clip: String, volume: float = 1.0, pitch: float = 1.0, pitch_var: float = 0.05) -> void:
	if not _streams.has(clip):
		var fb: Array = FALLBACK.get(clip, ["ui", 1.0])
		Sfx.play(str(fb[0]), pitch_var, volume, float(fb[1]) * pitch)
		return
	for a: AudioStreamPlayer in _pool:
		if not a.playing:
			a.stream = _streams[clip]
			a.pitch_scale = maxf(pitch + randf_range(-pitch_var, pitch_var), 0.05)
			a.volume_db = linear_to_db(clampf(volume, 0.01, 1.5))
			a.play()
			return


## Positional (rivals' actions, explosions out in the world).
func play_at(clip: String, pos: Vector3, volume: float = 1.0, pitch: float = 1.0) -> void:
	if not _streams.has(clip):
		Sfx.play_at(str((FALLBACK.get(clip, ["ui", 1.0]) as Array)[0]), pos, 0.05, volume)
		return
	for b: AudioStreamPlayer3D in _pool3d:
		if not b.playing:
			b.stream = _streams[clip]
			b.global_position = pos
			b.pitch_scale = maxf(pitch + randf_range(-0.05, 0.05), 0.05)
			b.volume_db = linear_to_db(clampf(volume, 0.01, 1.5))
			b.play()
			return


## A looping-ish sound bound to a node (charge hum): returns the player so the caller can stop it.
func hum(clip: String, parent: Node3D, pitch: float = 1.0, volume: float = 0.6) -> AudioStreamPlayer3D:
	var b := AudioStreamPlayer3D.new()
	b.bus = "SFX"
	b.unit_size = 10.0
	var s: AudioStream = _streams.get(clip, null)
	if s == null:
		return null
	b.stream = s
	b.pitch_scale = pitch
	b.volume_db = linear_to_db(volume)
	parent.add_child(b)
	b.play()
	return b
