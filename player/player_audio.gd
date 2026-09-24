class_name PlayerAudio
extends Node
## The local player's continuous sounds (cosmetic only; reads the Player, never writes it):
##  * air rush - the wind of your own speed: silent below RUSH_FROM m/s, full by RUSH_FULL
##    (a long fall, a pad launch, a boost-strip sprint), rising in pitch as it grows
##  * wall-run scrape while you run along a panel
##  * ice slide while you slide over a low-grip surface
##  * the boost strip's launch zing, once per strip you run onto
## Made by Player.connect_feedback() for the one Player the local person drives (never for
## race ghosts, which are RemoteRacers, or test / bot players), and not at all in headless runs.

const RUSH_FROM: float = 9.0
const RUSH_FULL: float = 26.0
const RUSH_DB: float = -7.0
const SCRAPE_DB: float = -15.0
const ICE_DB: float = -11.0

var player: Player
var _rush: AudioStreamPlayer3D
var _scrape: AudioStreamPlayer3D
var _ice: AudioStreamPlayer3D
var _rush_k: float = 0.0
var _scrape_k: float = 0.0
var _ice_k: float = 0.0
var _boost_strip: Object = null


func setup(p: Player) -> void:
	player = p
	_rush = _own_loop("air_rush")
	_scrape = _own_loop("wallrun_scrape")
	_ice = _own_loop("ice_slide")
	p.teleported.connect(func() -> void:
		_rush_k = 0.0
		_scrape_k = 0.0
		_ice_k = 0.0
		_boost_strip = null)


## A loop riding on the player that doesn't fade with camera distance (it is our own sound).
func _own_loop(clip: String) -> AudioStreamPlayer3D:
	var p: AudioStreamPlayer3D = Sfx.loop_at(clip, player, -80.0, 0.0, 10.0)
	if p != null:
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		p.attenuation_filter_cutoff_hz = 20500.0
		p.panning_strength = 0.35
		p.stream_paused = true
		var length: float = p.stream.get_length()
		if p.playing and length > 0.0:
			p.seek(randf() * length)
	return p


func _process(dt: float) -> void:
	if player == null:
		return
	var v: Vector3 = player.velocity
	var h: float = Vector2(v.x, v.z).length()
	# air rush
	var k: float = clampf((v.length() - RUSH_FROM) / (RUSH_FULL - RUSH_FROM), 0.0, 1.0)
	_rush_k = _ease(_rush_k, k * k, dt, 7.0, 2.5)
	_drive(_rush, _rush_k, RUSH_DB, 0.75 + 0.5 * _rush_k)
	# wall-run scrape
	var walling: bool = player.is_wall_running()
	_scrape_k = _ease(_scrape_k, 1.0 if walling else 0.0, dt, 25.0, 9.0)
	_drive(_scrape, _scrape_k, SCRAPE_DB, 0.9 + clampf(h / 60.0, 0.0, 0.3))
	# ice slide, and the boost strip's launch
	var fb: Object = player.floor_body if (player.floor_body != null and is_instance_valid(player.floor_body)) else null
	var ice: float = 0.0
	if player.grounded and fb != null:
		if fb.has_method("grip") and float(fb.call("grip")) < 1.0:
			ice = clampf((h - 1.0) / 11.0, 0.0, 1.0)
		var strip: Object = null
		if fb.has_method("boost") and float((fb.call("boost") as Dictionary)["speed"]) > 0.0:
			strip = fb
		if strip != null and strip != _boost_strip:
			Sfx.play("boost", 0.04, 0.8)
		_boost_strip = strip
	_ice_k = _ease(_ice_k, ice, dt, 12.0, 6.0)
	_drive(_ice, _ice_k, ICE_DB, 0.85 + 0.3 * _ice_k)


static func _ease(cur: float, target: float, dt: float, up: float, down: float) -> float:
	return lerpf(cur, target, 1.0 - exp(-dt * (up if target > cur else down)))


static func _drive(p: AudioStreamPlayer3D, k: float, top_db: float, pitch: float) -> void:
	if p == null:
		return
	var on: bool = k > 0.01
	if p.stream_paused == on:
		p.stream_paused = not on
	# (silent while off too: un-pausing the game un-pauses every stream for a frame)
	p.volume_db = top_db + linear_to_db(k) if on else -80.0
	if on:
		p.pitch_scale = pitch
