extends Node
## Sound: pooled one-shots (flat and positional), looping emitters attached to nodes, per-theme
## clip variants, and the music system - a score per map with an intensity layer that follows
## your progress, fanfares that duck the score, and a muffle while the game is paused.
## Every clip is synthesised by tools/gen_*.py into res://audio (see docs/AUDIO.md).

## Track changes crossfade: the old bed fades out while the new one fades in.
const MUSIC_FADE_OUT: float = 0.6
const MUSIC_FADE_IN: float = 0.9
const MUSIC_SILENT_DB: float = -40.0
## Layers of a score sit this low when "off" (inaudible, still playing in sync).
const LAYER_OFF_DB: float = -60.0
## Seconds a layer takes to swell in or out when progress moves it.
const LAYER_FADE: float = 3.5
## Where the second layer of a score comes in, as course progress 0..1 (smoothstep ramp).
## "add" layers sit on top of the base (drums, counter-melody, brass); "cross" layers replace
## it (Coral Depths darkens from the sunlit shallows into the deep).
const LAYER_RULES: Dictionary = {
	"default": {"mode": "add", "from": 0.3, "to": 0.5},
	"reef": {"mode": "cross", "from": 0.35, "to": 0.75},
}
## Scale steps the checkpoint chime climbs through (semitones above the map's tonic), so the
## chime always lands in the key of the score it plays over. Wraps after an octave.
const CHIME_MAJOR: Array[int] = [0, 2, 4, 7, 9, 12, 14, 16]
const CHIME_MINOR: Array[int] = [0, 3, 5, 7, 10, 12, 15, 17]
const MINOR_THEMES: Array[String] = ["foundry", "clockwork", "volcano", "glacier", "desert", "ascent"]
## Variant files are clip_1 .. clip_N; one of them is picked at random (never twice running).
const MAX_VARIANTS: int = 8

var _clips: Dictionary = {}          # clip name -> Array[AudioStream] ([] = no such clip)
var _last_variant: Dictionary = {}   # clip name -> index played last
var _theme: String = ""
var _pool: Array[AudioStreamPlayer] = []
var _pool3d: Array[AudioStreamPlayer3D] = []
var _music_players: Array[AudioStreamPlayer] = []
var _music: AudioStreamPlayer    # the current (audible or fading-in) player
var _music_name: String = ""
var _music_tween: Tween
var _layered: AudioStreamSynchronized    # the current score when it has a second layer
var _layer_mix: float = 0.0              # 0 = base only, 1 = second layer fully in
var _layer_target: float = 0.0
var _layer_tween: Tween
var _fanfare: AudioStreamPlayer
var _fanfare_seq: int = 0
var _fanfare_live: bool = false
var _duck_tween: Tween
var _muffle_tween: Tween
var _muffled: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i: int in 14:
		var a := AudioStreamPlayer.new()
		a.bus = "SFX"
		add_child(a)
		_pool.append(a)
	for i: int in 16:
		var b := AudioStreamPlayer3D.new()
		b.bus = "SFX"
		b.unit_size = 9.0
		b.max_distance = 70.0
		add_child(b)
		_pool3d.append(b)
	for i: int in 2:
		var m := AudioStreamPlayer.new()
		m.bus = "Music"
		# tracks loop, so this is only a fallback; never restart a fading-out player
		m.finished.connect(func() -> void:
			if m == _music and _music_name != "":
				m.play())
		add_child(m)
		_music_players.append(m)
	_music = _music_players[0]
	_fanfare = AudioStreamPlayer.new()
	_fanfare.bus = "Music"
	add_child(_fanfare)
	_setup_muffle()


## Quit with no sound in flight. The audio thread only lets go of a stopped playback on its next
## mix, so quitting mid-sound (a test run ending on the finish chime) left it held at exit and Godot
## reported leaked instances / resources still in use. Stops everything, gives the mixer a beat, quits.
func quit(code: int = 0) -> void:
	for n: Node in get_tree().root.find_children("*", "AudioStreamPlayer", true, false):
		(n as AudioStreamPlayer).stop()
	for n: Node in get_tree().root.find_children("*", "AudioStreamPlayer3D", true, false):
		(n as AudioStreamPlayer3D).stop()
	await get_tree().create_timer(0.15, true, false, true).timeout
	get_tree().quit(code)


# ---- clips ------------------------------------------------------------------------------------

## The streams for a clip: res://audio/<clip>.wav / .ogg, or its variants <clip>_1 .. _N.
func _streams(clip: String) -> Array:
	if _clips.has(clip):
		return _clips[clip]
	var found: Array = []
	var single: AudioStream = _load_audio("res://audio/" + clip)
	if single != null:
		found.append(single)
	else:
		for i: int in range(1, MAX_VARIANTS + 1):
			var v: AudioStream = _load_audio("res://audio/%s_%d" % [clip, i])
			if v == null:
				break
			found.append(v)
	_clips[clip] = found
	return found


static func _load_audio(stem: String) -> AudioStream:
	for ext: String in [".wav", ".ogg"]:
		if ResourceLoader.exists(stem + ext):
			return load(stem + ext) as AudioStream
	return null


func has_clip(clip: String) -> bool:
	return not _streams(clip).is_empty()


func _pick(clip: String) -> AudioStream:
	var s: Array = _streams(clip)
	if s.is_empty():
		return null
	if s.size() == 1:
		return s[0]
	var last: int = int(_last_variant.get(clip, -1))
	var i: int = randi() % (s.size() - 1)
	if i >= last:
		i += 1
	_last_variant[clip] = i
	return s[i]


## The map whose clip variants themed() prefers ("" = none). Set by every level.
func set_theme(theme_id: String) -> void:
	_theme = theme_id


## `<base>_<theme>` when the current map has its own version of a clip, else `base`
## (e.g. themed("step") is "step_foundry" on the foundry's metal gratings).
func themed(base: String) -> String:
	if _theme != "":
		var t: String = "%s_%s" % [base, _theme]
		if has_clip(t):
			return t
	return base


func play(clip: String, pitch_var: float = 0.0, volume: float = 1.0, pitch: float = 1.0) -> void:
	var stream: AudioStream = _pick(clip)
	if stream == null:
		return
	for a: AudioStreamPlayer in _pool:
		if not a.playing:
			a.stream = stream
			a.pitch_scale = pitch + randf_range(-pitch_var, pitch_var)
			a.volume_db = linear_to_db(clampf(volume, 0.01, 1.5))
			a.play()
			return


func play_at(clip: String, pos: Vector3, pitch_var: float = 0.05, volume: float = 1.0) -> void:
	var stream: AudioStream = _pick(clip)
	if stream == null:
		return
	for b: AudioStreamPlayer3D in _pool3d:
		if not b.playing:
			b.stream = stream
			b.global_position = pos
			b.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
			b.volume_db = linear_to_db(clampf(volume, 0.01, 1.5))
			b.play()
			return


## A looping positional emitter (a laser's hum, a vent's roar) attached to `parent`: it follows
## the node, starts when it enters the tree and dies with it. Returns null if the clip is
## missing. Adjust volume_db / pitch_scale / stream_paused on the returned player as the
## machine changes state. Loops come from the WAV's smpl chunk (see tools/gen_audio.py).
func loop_at(clip: String, parent: Node3D, volume_db: float = 0.0, max_distance: float = 30.0,
		unit_size: float = 5.0) -> AudioStreamPlayer3D:
	var stream: AudioStream = _pick(clip)
	if stream == null:
		return null
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.bus = "SFX"
	p.volume_db = volume_db
	p.max_distance = max_distance
	p.unit_size = unit_size
	p.attenuation_filter_cutoff_hz = 9000.0
	p.autoplay = true
	parent.add_child(p)
	return p


# ---- music ------------------------------------------------------------------------------------

## Switch the score: res://audio/music_<track>.ogg, plus music_<track>_hi.ogg as its second
## layer when there is one. The same track again keeps playing (a restart doesn't reset it),
## but cuts short a fanfare that was about to hand over to another track.
func music(track: String) -> void:
	var was_ducked: bool = _fanfare_pending()
	_cancel_fanfare()
	if track == _music_name:
		if was_ducked:
			_duck(0.0, 0.8)
		return
	_switch(track, was_ducked)


## `cut_outgoing`: the old score is ducked under a fanfare, so drop it at once instead of
## fading it out (un-ducking it for its fade would bring it back up for a moment).
func _switch(track: String, cut_outgoing: bool) -> void:
	_music_name = track
	if _music_tween != null:
		_music_tween.kill()
	var outgoing: AudioStreamPlayer = _music
	_music = _music_players[1] if outgoing == _music_players[0] else _music_players[0]
	_music.stop()
	if cut_outgoing:
		outgoing.stop()
	_set_music_duck(0.0)
	var stream: AudioStream = _score(track) if track != "" else null
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


func current_music() -> String:
	return _music_name


## The stream for a score: a single loop, or both layers locked together in an
## AudioStreamSynchronized whose layer volumes follow music_progress().
func _score(track: String) -> AudioStream:
	var base: AudioStream = _load_audio("res://audio/music_" + track)
	_layered = null
	if _layer_tween != null:
		_layer_tween.kill()
	_layer_mix = 0.0
	_layer_target = 0.0
	if base == null:
		return null
	_set_loop(base)
	var hi: AudioStream = _load_audio("res://audio/music_%s_hi" % track)
	if hi == null:
		return base
	_set_loop(hi)
	var sync := AudioStreamSynchronized.new()
	sync.stream_count = 2
	sync.set_sync_stream(0, base)
	sync.set_sync_stream(1, hi)
	_layered = sync
	_apply_layer_mix(0.0)
	return sync


static func _set_loop(s: AudioStream) -> void:
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true


## How far through the course the player is (0 = start, 1 = the last stage). Brings the score's
## second layer in (or crossfades to it) along LAYER_RULES, swelling over a few seconds.
func music_progress(p: float) -> void:
	var rule: Dictionary = LAYER_RULES.get(_music_name, LAYER_RULES["default"])
	var target: float = smoothstep(float(rule["from"]), float(rule["to"]), clampf(p, 0.0, 1.0))
	if is_equal_approx(target, _layer_target):
		return
	_layer_target = target
	if _layered == null:
		_layer_mix = target
		return
	if _layer_tween != null:
		_layer_tween.kill()
	_layer_tween = create_tween()
	_layer_tween.tween_method(_apply_layer_mix, _layer_mix, target, LAYER_FADE * absf(target - _layer_mix) + 0.2)


func _apply_layer_mix(x: float) -> void:
	_layer_mix = x
	if _layered == null:
		return
	var rule: Dictionary = LAYER_RULES.get(_music_name, LAYER_RULES["default"])
	var base_gain: float = 1.0
	var hi_gain: float = x
	if rule["mode"] == "cross":
		# equal-power crossfade: the sum stays as loud as either layer on its own
		base_gain = cos(x * PI * 0.5)
		hi_gain = sin(x * PI * 0.5)
	_layered.set_sync_stream_volume(0, maxf(linear_to_db(base_gain), LAYER_OFF_DB))
	_layered.set_sync_stream_volume(1, maxf(linear_to_db(hi_gain), LAYER_OFF_DB))


## Current mix of the second layer (0..1); for tests and the debug readout.
func music_layer_mix() -> float:
	return _layer_mix


## Play a musical stinger (res://audio/<clip>.ogg / .wav on the Music bus) with the score ducked
## under it. With `then_track` the score switches to that track as the stinger ends (a course
## fanfare leads into the results music); otherwise the score comes back up. Returns false when
## the clip doesn't exist, so callers can fall back to a plain effect.
func fanfare(clip: String, then_track: String = "", duck_db: float = -30.0) -> bool:
	var stream: AudioStream = _pick(clip)
	if stream == null:
		return false
	_cancel_fanfare()
	var seq: int = _fanfare_seq
	_fanfare.stream = stream
	_fanfare.volume_db = 0.0
	_fanfare.play()
	_duck(duck_db, 0.12)
	_fanfare_live = true
	var back_at: float = maxf(stream.get_length() - 0.6, 0.2)
	get_tree().create_timer(back_at, true, false, true).timeout.connect(func() -> void:
		if seq != _fanfare_seq:
			return
		_fanfare_live = false   # handed over: no longer pending
		if then_track != "" and then_track != _music_name:
			_switch(then_track, true)
		else:
			_duck(0.0, 1.2))
	return true


## A fanfare is playing and still owns the duck / the hand-over.
func _fanfare_pending() -> bool:
	return _fanfare_live and _fanfare.playing


## Stops a pending hand-over; a fanfare still ringing fades out quickly.
func _cancel_fanfare() -> void:
	_fanfare_seq += 1
	_fanfare_live = false
	if _fanfare.playing:
		var tw: Tween = create_tween()
		tw.tween_property(_fanfare, "volume_db", MUSIC_SILENT_DB, 0.25)
		tw.tween_callback(_fanfare.stop)


## The duck is an amplify stage on the Ducked bus, so it never fights the crossfade tweens.
func _duck(db: float, secs: float) -> void:
	if _duck_tween != null:
		_duck_tween.kill()
	_duck_tween = create_tween()
	_duck_tween.tween_method(_set_music_duck, _music_duck_db(), db, secs)


func _music_duck_db() -> float:
	var fx: AudioEffectAmplify = _bus_effect("Ducked", "AudioEffectAmplify") as AudioEffectAmplify
	return fx.volume_db if fx != null else 0.0


func _set_music_duck(db: float) -> void:
	var fx: AudioEffectAmplify = _bus_effect("Ducked", "AudioEffectAmplify") as AudioEffectAmplify
	if fx != null:
		fx.volume_db = db


# ---- the muffle while paused --------------------------------------------------------------------

## The score (and the ambience) goes dull and a little quieter while the pause menu is up:
## a low-pass on the Ducked / Ambience buses swept down, and swept back when play resumes.
func muffle(on: bool) -> void:
	if on == _muffled:
		return
	_muffled = on
	if _muffle_tween != null:
		_muffle_tween.kill()
	_muffle_tween = create_tween().set_parallel(true)
	for bus_name: String in ["Ducked", "Ambience"]:
		var lp: AudioEffectLowPassFilter = _bus_effect(bus_name, "AudioEffectLowPassFilter") as AudioEffectLowPassFilter
		if lp != null:
			_muffle_tween.tween_property(lp, "cutoff_hz", 700.0 if on else 20500.0, 0.35 if on else 0.6) \
				.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	var idx: int = AudioServer.get_bus_index("Ducked")
	if idx >= 0:
		_muffle_tween.tween_method(func(db: float) -> void: AudioServer.set_bus_volume_db(idx, db),
			AudioServer.get_bus_volume_db(idx), -5.0 if on else 0.0, 0.35)


func is_muffled() -> bool:
	return _muffled


## Buses: the score players sit on "Ducked" (fanfare ducking + the pause muffle), which sends into
## "Music" (the volume slider); ambience beds have their own bus and slider. Settings creates
## Music / SFX / Ambience; this adds the Ducked stage and the filters.
func _setup_muffle() -> void:
	if AudioServer.get_bus_index("Ducked") < 0:
		AudioServer.add_bus()
		var idx: int = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, "Ducked")
		AudioServer.set_bus_send(idx, "Music")
	for bus_name: String in ["Ducked", "Ambience"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			continue
		if _bus_effect(bus_name, "AudioEffectLowPassFilter") == null:
			var lp := AudioEffectLowPassFilter.new()
			lp.cutoff_hz = 20500.0
			lp.resonance = 0.35
			AudioServer.add_bus_effect(AudioServer.get_bus_index(bus_name), lp)
	if _bus_effect("Ducked", "AudioEffectAmplify") == null:
		AudioServer.add_bus_effect(AudioServer.get_bus_index("Ducked"), AudioEffectAmplify.new())
	for m: AudioStreamPlayer in _music_players:
		m.bus = "Ducked"


static func _bus_effect(bus_name: String, cls: String) -> AudioEffect:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return null
	for i: int in AudioServer.get_bus_effect_count(idx):
		var fx: AudioEffect = AudioServer.get_bus_effect(idx, i)
		if fx.is_class(cls):
			return fx
	return null


# ---- checkpoints --------------------------------------------------------------------------------

## The checkpoint chime for the current map, `index` (1-based) steps up its scale.
func checkpoint_chime(index: int) -> void:
	var steps: Array[int] = CHIME_MINOR if _theme in MINOR_THEMES else CHIME_MAJOR
	var semis: int = steps[posmod(index - 1, steps.size())]
	play(themed("checkpoint"), 0.0, 1.0, pow(2.0, float(semis) / 12.0))
