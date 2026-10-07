class_name RemoteRacer
extends Node3D
## Another player in a race: the same Volt model, tinted, with a name tag.
## Pose snapshots arrive ~30 Hz; we extrapolate briefly along the reported
## velocity and ease toward it so motion stays smooth under jitter.
## No collider - racers never block each other.

var _visual: PlayerVisual
var _label: Label3D
var _pos: Vector3
var _vel: Vector3
var _grounded: bool = true
var _age: float = 0.0
var _has_state: bool = false
var _facing: Vector3 = Vector3.FORWARD
## Teleport sequence of the last packet (a change means the racer respawned).
var _seq: int = -1
var racer_name: String = ""
## Their title (Cosmetics.TITLES id), shown on the name tag under the name.
var title_id: String = "rookie"
var _shadow: Decal
var _team_name: String = ""


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_visual = PlayerVisual.new()
	add_child(_visual)
	_shadow = BlobShadow.make()
	add_child(_shadow)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = true
	_label.pixel_size = 0.0011
	_label.font_size = 34
	_label.outline_size = 10
	_label.position = Vector3(0, 1.75, 0)
	add_child(_label)


func setup(p_name: String, color: Color) -> void:
	racer_name = p_name
	_visual.set_accent(color)
	_label.text = _tag_text()
	_label.modulate = color.lerp(Color.WHITE, 0.4)


## "Ada" over "Speed Demon" on the floating name tag.
func _tag_text(team: String = "") -> String:
	var top: String = racer_name if team == "" else "%s  [%s]" % [racer_name, team]
	return "%s
%s" % [top, Cosmetics.item_name("title", title_id)]


## The racer's unlocked trail and finish celebration, as they registered them (unknown ids
## from a newer or hand-edited client fall back to the defaults).
func set_cosmetics(trail: Variant, finish: Variant) -> void:
	var t: String = Cosmetics.clean("trail", trail)
	if t != _visual.trail_id:
		_visual.set_trail(t)
	_visual.finish_id = Cosmetics.clean("finish", finish)


## Everything a roster entry carries ({"character", "hat", "paint", "trail", "finish", "title"}):
## missing or unknown ids (an older or hand-edited client) fall back to the defaults.
func apply_cosmetics(entry: Dictionary) -> void:
	set_cosmetics(entry.get("trail"), entry.get("finish"))
	_visual.set_character(Cosmetics.clean("character", entry.get("character")))
	_visual.set_hat(Cosmetics.clean("hat", entry.get("hat")))
	_visual.set_paint(Cosmetics.clean("paint", entry.get("paint")))
	set_title(entry.get("title"))
	_visual.pose_id = Cosmetics.clean("pose", entry.get("pose"))


func set_title(id: Variant) -> void:
	title_id = Cosmetics.clean("title", id)
	if _label != null:
		_label.text = _tag_text(_team_name)


## They played an emote / victory pose (kind "emote" | "pose") or cut it short (kind "stop").
## Ids are checked against the catalogue (Net validates them too); movement ends an emote on
## its own (PlayerVisual stops it when the reported speed or air time says they moved).
func play_emote(kind: String, id: String) -> void:
	match kind:
		"emote":
			_visual.play_emote(id)
		"pose":
			_visual.play_pose(id, false, 0.0)
		"stop":
			_visual.cancel_emote()


## They crossed the line: their own finish celebration.
func celebrate() -> void:
	_visual.on_cheer()


# ---- Party Mode accessors (read-only views; party attachments hang off visual()) -------

## The Volt model (party costumes and status effects are added as its children).
func visual() -> PlayerVisual:
	return _visual


## Last reported velocity / grounded flag (hit checks: "from behind", "in the air").
func velocity() -> Vector3:
	return _vel


func is_grounded() -> bool:
	return _grounded


## Team Party: the name tag shows the team colour and name.
func set_team(team_name: String, color: Color) -> void:
	_team_name = team_name
	_label.text = _tag_text(team_name)
	_label.modulate = color.lerp(Color.WHITE, 0.25)
	_visual.set_accent(color)


## Cosmetic flinch the moment a local attack connects (the real knockback arrives with
## the victim's next poses).
func flinch() -> void:
	_visual.on_bounce(12.0)


func push_state(pos: Vector3, vel: Vector3, grounded: bool, seq: int) -> void:
	if not _has_state or seq != _seq or pos.distance_to(global_position) > 12.0:
		# first packet, a respawn / teleport, or a long packet gap: snap, don't slide
		if _has_state and seq != _seq:
			_visual.on_respawn()     # drop the death-pose lean, same arrival glow as ours
		global_position = pos
		var flat := Vector3(vel.x, 0, vel.z)
		if flat.length() > 0.5:
			_facing = flat.normalized()
		_visual.snap_facing(_facing)
	elif grounded and not _grounded:
		_visual.on_land(absf(_vel.y))
	elif not grounded and _grounded and vel.y > 6.0:
		if vel.y > 14.0:
			_visual.on_bounce(vel.length())
		else:
			_visual.on_jump()
	_pos = pos
	_vel = vel
	_grounded = grounded
	_age = 0.0
	_has_state = true
	_seq = seq


## Last reported heading (the spectator camera starts behind it).
func facing() -> Vector3:
	return _facing


func _process(dt: float) -> void:
	if not _has_state:
		return
	_age += dt
	var predicted: Vector3 = _pos + _vel * minf(_age, 0.2)
	global_position = global_position.lerp(predicted, 1.0 - exp(-16.0 * dt))
	var flat := Vector3(_vel.x, 0, _vel.z)
	if flat.length() > 0.5:
		_facing = flat.normalized()
	_visual.animate(dt, _vel, _grounded, _facing)
	BlobShadow.fit(_shadow, get_world_3d().direct_space_state, global_position, 1 | 8)
