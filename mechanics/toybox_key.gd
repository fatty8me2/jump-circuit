class_name ToyboxKey
extends StaticBody3D
## Toybox Tumble: a XYLOPHONE KEY. A painted metal bar on a wooden frame that rings a note and
## bounces whoever lands on it. It speaks the BouncePad contract (get_launch / get_surface_up /
## on_bounced), so the player and the route bot treat it as a pad: `pitch_deg` 0 = a plain upward
## bounce (horizontal speed kept), more = an angled launch along the key's -Z that REPLACES the
## velocity (the same key always throws the same arc). The key dips under the landing and springs
## back, a ring of sparkles pops off it, and the player's bounce sound is the note itself
## (`bounce_clip`, one of toybox_note_1..5). The node sits at the centre of the bar's top.

@export var bar: Vector3 = Vector3(3.4, 0.4, 2.0)
@export var strength: float = 17.0
@export_range(0.0, 75.0) var pitch_deg: float = 0.0
@export var note: int = 0
@export var color: Color = Color(0.95, 0.3, 0.3)

var _vis: Node3D
var _press: float = 0.0
var _press_vel: float = 0.0
var _spark: GPUParticles3D
var _glow: StandardMaterial3D


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = bar
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, -bar.y * 0.5, 0)
	add_child(cs)
	_vis = Node3D.new()
	add_child(_vis)
	_glow = StandardMaterial3D.new()
	_glow.albedo_color = color
	_glow.roughness = 0.25
	_glow.metallic = 0.55
	_glow.emission_enabled = true
	_glow.emission = color
	_glow.emission_energy_multiplier = 0.25
	var metal: StandardMaterial3D = Look.flat(Color(0.88, 0.9, 0.95), 0.2, 0.9)
	var wood: StandardMaterial3D = Look.flat(Color(0.72, 0.5, 0.3), 0.7)
	_vis.add_child(Look.box(bar, _glow, Vector3(0, -bar.y * 0.5, 0)))
	# a lighter strip down the middle (where to land) and two brass rivets near the ends
	var strip := Look.box(Vector3(bar.x - 0.9, 0.025, bar.z - 0.5), Look.flat(color.lerp(Color.WHITE, 0.45), 0.4, 0.3), Vector3(0, 0.006, 0))
	strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vis.add_child(strip)
	for sx: float in [-1.0, 1.0]:
		_vis.add_child(Look.cylinder(0.1, 0.06, metal, Vector3(sx * (bar.x * 0.5 - 0.3), 0.02, 0.0), -1.0, 10))
	# the wooden pegs it rests on (static, they do not dip)
	for sx: float in [-1.0, 1.0]:
		add_child(Look.box(Vector3(0.34, 0.5, bar.z + 0.3), wood, Vector3(sx * (bar.x * 0.5 - 0.7), -bar.y - 0.25, 0)))
	var vis := AABB(Vector3(-4, -1, -4), Vector3(8, 8, 8))
	_spark = Fx.burst({"amount": 14, "lifetime": 0.7, "tex": Fx.Tex.STAR, "size": 0.32, "shape": "box",
		"extents": Vector3(bar.x * 0.4, 0.05, bar.z * 0.3), "dir": Vector3.UP, "spread": 35.0, "speed": Vector2(2.0, 5.0),
		"gravity": Vector3(0, -3.0, 0), "damping": Vector2(0.5, 1.5), "color": Fx.hot(color.lerp(Color.WHITE, 0.4), 2.2), "aabb": vis})
	_spark.position = Vector3(0, 0.1, 0)
	add_child(_spark)
	set_process(false)


# ---- the pad contract used by Player ---------------------------------------------------

func _local_launch() -> Vector3:
	var p: float = deg_to_rad(pitch_deg)
	return Vector3(0, cos(p), -sin(p)) * strength


func get_surface_up() -> Vector3:
	return global_basis.y.normalized()


func get_launch() -> Dictionary:
	return {
		"velocity": global_basis.orthonormalized() * _local_launch(),
		"keep_horizontal": pitch_deg < 1.0,
	}


func launch_origin() -> Vector3:
	return global_position + Vector3(0, 0.1, 0)


func bounce_clip() -> String:
	return "toybox_note_%d" % (posmod(note, 5) + 1)


func on_bounced(_player: Node) -> void:
	_press = -0.18
	_press_vel = 3.0
	_glow.emission_energy_multiplier = 2.4
	set_process(true)
	_spark.restart()


func _process(dt: float) -> void:
	var acc: float = -_press * 380.0 - _press_vel * 14.0
	_press_vel += acc * dt
	_press += _press_vel * dt
	_vis.position = Vector3(0, _press, 0)
	_glow.emission_energy_multiplier = lerpf(_glow.emission_energy_multiplier, 0.25, minf(dt * 4.0, 1.0))
	if absf(_press) < 0.002 and absf(_press_vel) < 0.02 and _glow.emission_energy_multiplier < 0.3:
		_press = 0.0
		_vis.position = Vector3.ZERO
		set_process(false)
