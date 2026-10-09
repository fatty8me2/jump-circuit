class_name DinoTell
extends Node3D
## Dino Valley: the early warning that goes with a clock hazard. A patch of ground (a floor quad) flashes
## amber and a clip sounds `lead` s (0.9 or more) before the hazard fires, however short the machine's own
## shudder is: a crusher foot's shadow darkening, a triceratops pawing the ledge. Purely a function of
## Game.course_time, visual and audible only.

var period: float = 5.0
var phase: float = 0.0
## Cycle fraction at which the hazard goes live.
var fire_u: float = 0.5
var lead: float = 0.95
var size: Vector2 = Vector2(3, 3)
var color: Color = Color(1.0, 0.55, 0.12)
var clip: String = "dino_tell"

var _quad: MeshInstance3D
var _last_tts: float = 99.0
var _crossed_edge: bool = false


static func make(parent: Node3D, at: Vector3, floor_size: Vector2, per: float, ph: float, fire: float, warn_clip: String = "dino_tell", lead_s: float = 0.95, yaw_deg: float = 0.0) -> DinoTell:
	var t := DinoTell.new()
	t.period = per
	t.phase = ph
	t.fire_u = fire
	t.size = floor_size
	t.clip = warn_clip
	t.lead = lead_s
	t.position = at
	t.rotation_degrees.y = yaw_deg
	parent.add_child(t)
	return t


func _ready() -> void:
	_quad = KitUtil.floor_quad(size, Color(color.r, color.g, color.b, 0.0))
	_quad.position = Vector3(0, 0.06, 0)
	add_child(_quad)
	_quad.visible = false


## Seconds until the hazard next fires.
func time_to_fire(time: float) -> float:
	var u: float = KitUtil.cycle_u(time, period, phase)
	return fposmod(fire_u - u, 1.0) * period


func _process(_dt: float) -> void:
	var tts: float = time_to_fire(Game.course_time)
	var on: bool = tts < lead
	_quad.visible = on
	if on:
		var k: float = 1.0 - tts / lead
		var flash: float = 1.0 if fmod(tts, 0.24) < 0.12 else 0.45
		KitUtil.set_quad_color(_quad, Color(color.r, color.g, color.b, (0.18 + 0.5 * k) * flash))
		if not _crossed_edge:
			_crossed_edge = true
			WorldAudio.at(self, clip, global_position + Vector3(0, 1.0, 0), 0.7, 32.0)
	else:
		_crossed_edge = false
