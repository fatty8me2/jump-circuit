class_name Soundscape
extends Node
## A map's ambient soundscape (docs/AUDIO_AMBIENCE.md): a looping bed on the "Ambience" bus,
## optionally crossfading into a second bed as the course goes on (Coral Depths darkens into
## the deep, the Final Ascent's wind picks up near the summit), plus one-shots - birds, gulls,
## far-off clanks, whale song - scheduled at random and placed in 3D around the listener.
## Clips come from tools/gen_ambience.py. The beds keep playing while the game is paused (so
## the pause muffle on the Ambience bus is heard); the one-shot schedule pauses with the tree.

const BUS: StringName = &"Ambience"
## Seconds the bed takes to fade in.
const FADE_IN: float = 3.0
const SILENT_DB: float = -60.0
## Positional players for the one-shots (more than this many at once are skipped).
const POOL_SIZE: int = 6
## Course progress moves the layer crossfade at most this fast (per second), so a checkpoint
## eases the bed over rather than switching it.
const PROGRESS_RATE: float = 0.05
## First one-shot of each event waits at least this long after the level loads.
const FIRST_DELAY: float = 2.0
## Leaving a map fades its bed out over this long (on a short-lived player on the root)
## instead of cutting it; a restart of the same map picks the bed up where it was.
const TAIL_FADE: float = 1.5
const HANDOFF_MSEC: int = 2500

## Per theme:
##   bed      res://audio/<bed>.ogg, looped
##   bed_db   its level on the Ambience bus
##   layer    optional second bed, crossfaded in (equal power) as progress runs from..to
## events (one-shots, res://audio/<clip>_1 .. _N; a random variant, never the same twice running):
##   every    Vector2 seconds between plays (random in the range)
##   db       Vector2 volume range, as heard at the distance it spawns at
##   pitch    random pitch spread (+-)
##   dist     Vector2 horizontal distance from the listener (m)
##   height   Vector2 height relative to the listener (m); negative = below
##   travel   optional: metres the source drifts sideways while it plays (fly-bys)
##   chance   optional Vector2: the chance it really plays when due, at the course start and at
##            the end (lerped by progress) - whales grow common as you dive, city sirens fade
##   answer   optional: chance a second call answers from elsewhere a moment later (birds)
const THEMES: Dictionary = {
	"gardens": {
		"bed": "amb_gardens", "bed_db": 0.0,
		"events": [
			{"clip": "amb_gardens_bird", "every": Vector2(3.0, 9.0), "db": Vector2(-16.0, -8.0), "pitch": 0.05,
				"dist": Vector2(10.0, 35.0), "height": Vector2(2.0, 14.0), "answer": 0.35},
			{"clip": "amb_gardens_dove", "every": Vector2(18.0, 40.0), "db": Vector2(-18.0, -12.0), "pitch": 0.03,
				"dist": Vector2(15.0, 40.0), "height": Vector2(0.0, 8.0)},
			{"clip": "amb_gardens_bee", "every": Vector2(22.0, 50.0), "db": Vector2(-20.0, -13.0), "pitch": 0.08,
				"dist": Vector2(2.0, 5.0), "height": Vector2(-0.5, 1.5), "travel": 6.0},
			{"clip": "amb_gardens_chimes", "every": Vector2(25.0, 60.0), "db": Vector2(-20.0, -14.0), "pitch": 0.0,
				"dist": Vector2(8.0, 20.0), "height": Vector2(0.0, 5.0)},
			{"clip": "amb_gardens_windmill", "every": Vector2(30.0, 70.0), "db": Vector2(-20.0, -14.0), "pitch": 0.06,
				"dist": Vector2(25.0, 50.0), "height": Vector2(5.0, 20.0)},
		],
	},
	"title": {
		"bed": "amb_title", "bed_db": 0.0,
		"events": [
			{"clip": "amb_gardens_bird", "every": Vector2(6.0, 14.0), "db": Vector2(-20.0, -12.0), "pitch": 0.05,
				"dist": Vector2(12.0, 35.0), "height": Vector2(2.0, 12.0), "answer": 0.3},
			{"clip": "amb_gardens_dove", "every": Vector2(25.0, 50.0), "db": Vector2(-22.0, -15.0), "pitch": 0.03,
				"dist": Vector2(15.0, 40.0), "height": Vector2(0.0, 8.0)},
		],
	},
	"foundry": {
		"bed": "amb_foundry", "bed_db": 0.0,
		"events": [
			{"clip": "amb_foundry_blorp", "every": Vector2(5.0, 14.0), "db": Vector2(-18.0, -11.0), "pitch": 0.12,
				"dist": Vector2(8.0, 25.0), "height": Vector2(-25.0, -5.0)},
			{"clip": "amb_foundry_clank", "every": Vector2(6.0, 16.0), "db": Vector2(-18.0, -10.0), "pitch": 0.1,
				"dist": Vector2(20.0, 50.0), "height": Vector2(-15.0, 15.0)},
			{"clip": "amb_foundry_steam", "every": Vector2(10.0, 25.0), "db": Vector2(-20.0, -13.0), "pitch": 0.1,
				"dist": Vector2(12.0, 35.0), "height": Vector2(-10.0, 10.0)},
			{"clip": "amb_foundry_chain", "every": Vector2(14.0, 32.0), "db": Vector2(-20.0, -13.0), "pitch": 0.08,
				"dist": Vector2(12.0, 35.0), "height": Vector2(0.0, 15.0)},
			{"clip": "amb_foundry_hammer", "every": Vector2(20.0, 45.0), "db": Vector2(-18.0, -12.0), "pitch": 0.05,
				"dist": Vector2(35.0, 70.0), "height": Vector2(-10.0, 10.0)},
		],
	},
	"balance": {
		"bed": "amb_balance", "bed_db": 0.0,
		"events": [
			{"clip": "amb_balance_gull", "every": Vector2(6.0, 16.0), "db": Vector2(-16.0, -9.0), "pitch": 0.07,
				"dist": Vector2(15.0, 40.0), "height": Vector2(8.0, 25.0), "travel": 12.0, "answer": 0.3},
			{"clip": "amb_balance_chain", "every": Vector2(12.0, 30.0), "db": Vector2(-20.0, -13.0), "pitch": 0.08,
				"dist": Vector2(15.0, 40.0), "height": Vector2(-5.0, 10.0)},
			{"clip": "amb_balance_crane", "every": Vector2(18.0, 40.0), "db": Vector2(-20.0, -13.0), "pitch": 0.08,
				"dist": Vector2(25.0, 60.0), "height": Vector2(-5.0, 15.0)},
			{"clip": "amb_balance_buoy", "every": Vector2(20.0, 45.0), "db": Vector2(-20.0, -14.0), "pitch": 0.03,
				"dist": Vector2(50.0, 90.0), "height": Vector2(-45.0, -25.0)},
			{"clip": "amb_balance_foghorn", "every": Vector2(70.0, 150.0), "db": Vector2(-18.0, -12.0), "pitch": 0.03,
				"dist": Vector2(120.0, 200.0), "height": Vector2(-40.0, -20.0)},
		],
	},
	"clockwork": {
		"bed": "amb_clockwork", "bed_db": 0.0,
		"events": [
			{"clip": "amb_clockwork_ratchet", "every": Vector2(8.0, 20.0), "db": Vector2(-20.0, -13.0), "pitch": 0.1,
				"dist": Vector2(8.0, 25.0), "height": Vector2(-5.0, 10.0)},
			{"clip": "amb_clockwork_steam", "every": Vector2(12.0, 28.0), "db": Vector2(-20.0, -14.0), "pitch": 0.1,
				"dist": Vector2(10.0, 30.0), "height": Vector2(-10.0, 10.0)},
			{"clip": "amb_clockwork_bell", "every": Vector2(30.0, 70.0), "db": Vector2(-16.0, -10.0), "pitch": 0.0,
				"dist": Vector2(40.0, 80.0), "height": Vector2(10.0, 40.0)},
			{"clip": "amb_clockwork_cuckoo", "every": Vector2(60.0, 140.0), "db": Vector2(-17.0, -12.0), "pitch": 0.02,
				"dist": Vector2(20.0, 45.0), "height": Vector2(0.0, 15.0)},
		],
	},
	"reef": {
		"bed": "amb_reef", "bed_db": 0.0,
		"layer": "amb_reef_deep", "from": 0.25, "to": 0.85,
		"events": [
			{"clip": "amb_reef_bubbles", "every": Vector2(4.0, 10.0), "db": Vector2(-18.0, -10.0), "pitch": 0.12,
				"dist": Vector2(5.0, 20.0), "height": Vector2(-8.0, 4.0), "chance": Vector2(1.0, 0.45)},
			{"clip": "amb_reef_shrimp", "every": Vector2(10.0, 25.0), "db": Vector2(-22.0, -15.0), "pitch": 0.1,
				"dist": Vector2(6.0, 20.0), "height": Vector2(-6.0, 0.0), "chance": Vector2(1.0, 0.3)},
			{"clip": "amb_reef_timber", "every": Vector2(15.0, 35.0), "db": Vector2(-18.0, -12.0), "pitch": 0.08,
				"dist": Vector2(15.0, 40.0), "height": Vector2(-10.0, 5.0), "chance": Vector2(0.7, 0.7)},
			{"clip": "amb_reef_whale", "every": Vector2(35.0, 80.0), "db": Vector2(-18.0, -11.0), "pitch": 0.06,
				"dist": Vector2(60.0, 120.0), "height": Vector2(-60.0, -25.0), "chance": Vector2(0.35, 1.0)},
		],
	},
	"orbital": {
		"bed": "amb_orbital", "bed_db": 0.0,
		"events": [
			{"clip": "amb_orbital_blip", "every": Vector2(7.0, 18.0), "db": Vector2(-22.0, -15.0), "pitch": 0.04,
				"dist": Vector2(4.0, 15.0), "height": Vector2(-2.0, 4.0)},
			{"clip": "amb_orbital_servo", "every": Vector2(8.0, 20.0), "db": Vector2(-20.0, -13.0), "pitch": 0.1,
				"dist": Vector2(8.0, 25.0), "height": Vector2(-5.0, 10.0)},
			{"clip": "amb_orbital_ping", "every": Vector2(10.0, 26.0), "db": Vector2(-20.0, -13.0), "pitch": 0.08,
				"dist": Vector2(8.0, 30.0), "height": Vector2(-10.0, 10.0)},
			{"clip": "amb_orbital_radio", "every": Vector2(14.0, 35.0), "db": Vector2(-20.0, -13.0), "pitch": 0.0,
				"dist": Vector2(6.0, 20.0), "height": Vector2(-3.0, 5.0)},
			{"clip": "amb_orbital_airlock", "every": Vector2(40.0, 90.0), "db": Vector2(-18.0, -12.0), "pitch": 0.05,
				"dist": Vector2(20.0, 45.0), "height": Vector2(-10.0, 10.0)},
		],
	},
	"ascent": {
		"bed": "amb_ascent", "bed_db": 0.0,
		"layer": "amb_ascent_high", "from": 0.3, "to": 0.95,
		"events": [
			{"clip": "amb_ascent_crackle", "every": Vector2(9.0, 22.0), "db": Vector2(-22.0, -14.0), "pitch": 0.1,
				"dist": Vector2(5.0, 18.0), "height": Vector2(-4.0, 6.0)},
			{"clip": "amb_ascent_drone", "every": Vector2(30.0, 70.0), "db": Vector2(-18.0, -12.0), "pitch": 0.06,
				"dist": Vector2(10.0, 25.0), "height": Vector2(2.0, 12.0), "travel": 45.0},
			{"clip": "amb_ascent_siren", "every": Vector2(50.0, 110.0), "db": Vector2(-18.0, -12.0), "pitch": 0.04,
				"dist": Vector2(150.0, 300.0), "height": Vector2(-160.0, -90.0), "chance": Vector2(1.0, 0.5)},
			{"clip": "amb_ascent_heli", "every": Vector2(70.0, 150.0), "db": Vector2(-16.0, -11.0), "pitch": 0.03,
				"dist": Vector2(120.0, 220.0), "height": Vector2(-60.0, 20.0), "travel": 120.0},
		],
	},
}

var theme: String = ""
## Course progress 0..1 as heard (eases toward the level's checkpoint progress).
var progress: float = 0.0
## >= 0 pins the progress (tests, or a map that wants to drive the layer itself).
var progress_override: float = -1.0

var _spec: Dictionary = {}
var _bed: AudioStreamPlayer
var _layer: AudioStreamPlayer
var _layer_from: float = 0.0
var _layer_to: float = 1.0
var _fade: float = 0.0
var _events: Array[Dictionary] = []   # spec + "streams": Array[AudioStream], "last": int, "due": float
var _answers: Array[Vector2] = []     # (seconds until due, event index)
var _pool: Array[AudioStreamPlayer3D] = []
var _drift: Dictionary = {}           # AudioStreamPlayer3D -> Vector3 velocity (m/s)
var _rng := RandomNumberGenerator.new()

## Bed hand-over between scenes: what was playing when the last soundscape left the tree.
static var _handoff: Dictionary = {}
static var _tails: Array[AudioStreamPlayer] = []
static var _closing: bool = false


## The soundscape for a Look theme id (or "title"). An unknown theme builds a silent node.
static func make(theme_id: String) -> Soundscape:
	var s := Soundscape.new()
	s.name = "Soundscape"
	s.theme = theme_id
	s._spec = THEMES.get(theme_id, {})
	return s


func _ready() -> void:
	_rng.randomize()
	if _spec.is_empty():
		return
	_bed = _bed_player(String(_spec["bed"]))
	if _spec.has("layer"):
		_layer = _bed_player(String(_spec["layer"]))
		_layer_from = float(_spec["from"])
		_layer_to = float(_spec["to"])
	for i: int in POOL_SIZE:
		var p := AudioStreamPlayer3D.new()
		p.bus = BUS
		p.max_distance = 0.0             # no cut-off: level comes from the table and 1/r
		p.attenuation_filter_cutoff_hz = 20500.0   # distance is baked into the clips
		p.finished.connect(func() -> void: _drift.erase(p))
		add_child(p)
		_pool.append(p)
	for spec: Dictionary in _spec["events"]:
		var e: Dictionary = spec.duplicate()
		e["streams"] = _variants(String(spec["clip"]))
		e["last"] = -1
		var every: Vector2 = spec["every"]
		e["due"] = FIRST_DELAY + _rng.randf_range(0.0, every.y)
		_events.append(e)
	progress = _target_progress()
	_resume_or_fade_in()
	_apply_mix()


func _bed_player(clip: String) -> AudioStreamPlayer:
	var stream: AudioStream = _load("res://audio/%s.ogg" % clip)
	var p := AudioStreamPlayer.new()
	p.name = "Bed" if _bed == null else "Layer"
	p.bus = BUS
	# the bed carries on under the pause menu, where the Ambience bus is muffled
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	p.volume_db = SILENT_DB
	if stream != null:
		if stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
		p.stream = stream
	add_child(p)
	return p


## Start the beds. A restart of the same map (the scene reloads) continues the bed where it
## was, at its level; anything else fades in while the previous map's bed fades out.
func _resume_or_fade_in() -> void:
	var h: Dictionary = _handoff
	_handoff = {}
	var same: bool = (not h.is_empty() and String(h["bed"]) == String(_spec["bed"])
		and Time.get_ticks_msec() - int(h["msec"]) < HANDOFF_MSEC)
	var late: float = 0.0
	if same:
		for tail: Variant in _tails:   # (untyped: a tail may already be freed)
			if is_instance_valid(tail):
				var t := tail as AudioStreamPlayer
				t.set_meta("dead", true)
				t.stop()
				t.queue_free()
		_tails.clear()
		_fade = float(h["fade"])
		progress = float(h["progress"])
		late = float(Time.get_ticks_msec() - int(h["msec"])) / 1000.0
	for pair: Array in [[_bed, "bed_pos"], [_layer, "layer_pos"]]:
		var p: AudioStreamPlayer = pair[0]
		if p == null or p.stream == null:
			continue
		var at: float = 0.0
		if same:
			at = fmod(float(h.get(pair[1], 0.0)) + late, maxf(p.stream.get_length(), 0.001))
		p.play(at)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_closing = true


func _exit_tree() -> void:
	if _bed == null or not _bed.playing or _closing or DisplayServer.get_name() == "headless":
		return
	_handoff = {"bed": String(_spec["bed"]), "msec": Time.get_ticks_msec(), "fade": _fade, "progress": progress,
		"bed_pos": _bed.get_playback_position(),
		"layer_pos": _layer.get_playback_position() if _layer != null else 0.0}
	for p: AudioStreamPlayer in [_bed, _layer]:
		if p != null and p.playing and p.volume_db > SILENT_DB + 1.0:
			_tail_out(p)


## Carry `p`'s bed on, on a throw-away player on the root that fades out and frees itself.
func _tail_out(p: AudioStreamPlayer) -> void:
	var t := AudioStreamPlayer.new()
	t.stream = p.stream
	t.bus = BUS
	t.volume_db = p.volume_db
	t.process_mode = Node.PROCESS_MODE_ALWAYS
	var from: float = p.get_playback_position()
	t.ready.connect(func() -> void:
		if t.has_meta("dead"):
			t.queue_free()
			return
		t.play(from)
		var tw: Tween = t.create_tween()
		tw.tween_property(t, "volume_db", SILENT_DB, TAIL_FADE)
		tw.tween_callback(t.queue_free), CONNECT_ONE_SHOT)
	t.tree_exited.connect(func() -> void: _tails.erase(t))
	_tails.append(t)
	# the root is busy removing the old scene at this moment
	get_tree().root.add_child.call_deferred(t)


static func _load(path: String) -> AudioStream:
	return load(path) as AudioStream if ResourceLoader.exists(path) else null


## Every variant of a one-shot: res://audio/<clip>_1 .. _N (.ogg or .wav).
static func _variants(clip: String) -> Array[AudioStream]:
	var out: Array[AudioStream] = []
	for i: int in range(1, 17):
		var s: AudioStream = _load("res://audio/%s_%d.ogg" % [clip, i])
		if s == null:
			s = _load("res://audio/%s_%d.wav" % [clip, i])
		if s == null:
			break
		out.append(s)
	return out


func _process(dt: float) -> void:
	if _spec.is_empty():
		return
	_fade = minf(_fade + dt / FADE_IN, 1.0)
	progress = move_toward(progress, _target_progress(), PROGRESS_RATE * dt)
	_apply_mix()
	for i: int in _events.size():
		var e: Dictionary = _events[i]
		e["due"] = float(e["due"]) - dt
		if float(e["due"]) <= 0.0:
			var every: Vector2 = e["every"]
			e["due"] = _rng.randf_range(every.x, every.y)
			var chance: Vector2 = e.get("chance", Vector2.ONE)
			if _rng.randf() < lerpf(chance.x, chance.y, progress):
				play_event(i)
	for k: int in range(_answers.size() - 1, -1, -1):
		var ans: Vector2 = _answers[k]
		ans.x -= dt
		_answers[k] = ans
		if ans.x <= 0.0:
			play_event(int(ans.y), false)
			_answers.remove_at(k)
	for p: AudioStreamPlayer3D in _drift:
		p.global_position += (_drift[p] as Vector3) * dt


## Equal-power crossfade between the bed and its layer, under the fade-in.
func _apply_mix() -> void:
	var x: float = smoothstep(_layer_from, _layer_to, progress) if _layer != null else 0.0
	var bed_db: float = float(_spec.get("bed_db", 0.0))
	_bed.volume_db = _gain_db(cos(x * PI * 0.5) * _fade, bed_db)
	if _layer != null:
		_layer.volume_db = _gain_db(sin(x * PI * 0.5) * _fade, bed_db)


static func _gain_db(g: float, offset_db: float) -> float:
	return maxf(linear_to_db(maxf(g, 0.0)) + offset_db, SILENT_DB)


## How far through the course the player is (0 at the start, 1 at the last checkpoint).
func _target_progress() -> float:
	if progress_override >= 0.0:
		return clampf(progress_override, 0.0, 1.0)
	var level := get_parent() as LevelBase
	if level == null or level.checkpoints.is_empty():
		return 0.0
	return clampf(float(level.current_checkpoint) / float(level.checkpoints.size()), 0.0, 1.0)


## Play event `index` now at a random spot around the listener (false if it couldn't).
## `may_answer`: roll the event's answer chance (an answer never answers itself).
func play_event(index: int, may_answer: bool = true) -> bool:
	if index < 0 or index >= _events.size():
		return false
	var e: Dictionary = _events[index]
	var streams: Array[AudioStream] = e["streams"]
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if streams.is_empty() or cam == null:
		return false
	var p: AudioStreamPlayer3D = null
	for q: AudioStreamPlayer3D in _pool:
		if not q.playing:
			p = q
			break
	if p == null:
		return false
	var pick: int = _rng.randi_range(0, streams.size() - 1)
	if streams.size() > 1 and pick == int(e["last"]):
		pick = (pick + 1 + _rng.randi_range(0, streams.size() - 2)) % streams.size()
	e["last"] = pick
	var dist: Vector2 = e["dist"]
	var height: Vector2 = e["height"]
	var db: Vector2 = e["db"]
	var d: float = _rng.randf_range(dist.x, dist.y)
	var a: float = _rng.randf_range(0.0, TAU)
	var out := Vector3(cos(a), 0.0, sin(a))
	var offset: Vector3 = out * d + Vector3.UP * _rng.randf_range(height.x, height.y)
	p.stream = streams[pick]
	p.unit_size = maxf(offset.length(), 1.0)   # heard at the table's level where it spawns; 1/r as it drifts
	p.volume_db = _rng.randf_range(db.x, db.y)
	var spread: float = float(e.get("pitch", 0.0))
	p.pitch_scale = 1.0 + _rng.randf_range(-spread, spread)
	p.global_position = cam.global_position + offset
	var travel: float = float(e.get("travel", 0.0))
	if travel > 0.0:
		# drift across the listener: start half the path back, move sideways past
		var side := Vector3(-out.z, 0.0, out.x) * (1.0 if _rng.randf() < 0.5 else -1.0)
		p.global_position -= side * travel * 0.5
		_drift[p] = side * travel / maxf(p.stream.get_length() / p.pitch_scale, 0.5)
	else:
		_drift.erase(p)
	p.play()
	if may_answer and _rng.randf() < float(e.get("answer", 0.0)):
		_answers.append(Vector2(_rng.randf_range(0.8, 2.5), index))
	return true


## The bed player (null for a silent theme); for tests.
func bed_player() -> AudioStreamPlayer:
	return _bed


## The layer player (null when the theme has none); for tests.
func layer_player() -> AudioStreamPlayer:
	return _layer


## One-shot players currently sounding; for tests.
func active_one_shots() -> int:
	var n: int = 0
	for p: AudioStreamPlayer3D in _pool:
		if p.playing:
			n += 1
	return n
