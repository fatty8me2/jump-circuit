class_name LotusPad
extends AnimatableBody3D
## Lotus Drift: a LILY PAD STEPPING STONE that gives under your feet. A round green leaf floating on
## the pond: it sinks a hand's breadth under your weight, rocks back up on a soft spring and sends a
## ring of ripples across the water every time you land on it. A kindness, never a trap: it only
## dips (0.2 m at the most), never tips, never sinks away, and a jump off it is as high as off stone.
## Positioned at the centre of its TOP surface when resting. State is a tiny spring driven by who is
## standing on it; reset_state() (respawn) puts it back at rest.

@export var radius: float = 1.4
## How far a landing presses it down at the most (m).
@export var max_dip: float = 0.2

const THICK: float = 0.5

var _origin: Vector3
var _dip: float = 0.0
var _vel: float = 0.0
var _was_on: bool = false
var _ripple: GPUParticles3D
var _player: Player
var _mesh: MeshInstance3D


func _ready() -> void:
	sync_to_physics = false
	collision_layer = 1
	collision_mask = 0
	_origin = position
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = THICK
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, -THICK * 0.5, 0)
	add_child(cs)
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius * 0.94
	cm.height = THICK
	cm.radial_segments = 40
	cm.rings = 1
	var m := ShaderMaterial.new()
	m.shader = preload("res://visual/lotus_tile.gdshader")
	m.set_shader_parameter("kind", 1)
	m.set_shader_parameter("is_round", true)
	m.set_shader_parameter("half_size", Vector3(radius, THICK * 0.5, radius))
	_mesh = Look.mesh_node(cm, m, Vector3(0, -THICK * 0.5, 0))
	add_child(_mesh)
	# a thin dark skirt of root and water just under the leaf
	_ripple = LotusFx.ripple()
	_ripple.position = Vector3(0, -THICK + 0.18, 0)
	add_child(_ripple)
	add_to_group("resettable")
	reset_physics_interpolation()


func reset_state() -> void:
	_dip = 0.0
	_vel = 0.0
	_was_on = false
	position = _origin
	reset_physics_interpolation()


func _physics_process(dt: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = WorldAudio.local_player(self) as Player
	var on: bool = _player != null and _player.grounded and _player.floor_body == self
	if on and not _was_on:
		# a landing presses it down: a harder one, a deeper dip
		var hit: float = clampf(absf(_player.velocity.y) / 14.0 + 0.45, 0.45, 1.0)
		_vel = 3.2 * hit
		_ripple.restart()
		_ripple.emitting = true
		# SOUND: lotus_pad_dip - a soft wet pat of a leaf pressing into the water
		WorldAudio.at(self, "lotus_pad_dip", global_position, 0.8, 30.0)
	elif not on and _was_on:
		_vel -= 0.8
	_was_on = on
	# a soft spring toward the rest dip (pressed while stood on), lightly damped
	var rest: float = max_dip * 0.55 if on else 0.0
	var acc: float = (rest - _dip) * 110.0 - _vel * 9.5
	_vel += acc * dt
	_dip = clampf(_dip + _vel * dt, -0.06, max_dip)
	if absf(_dip) < 0.0005 and absf(_vel) < 0.002 and not on:
		_dip = 0.0
		_vel = 0.0
	position = _origin + Vector3(0, -_dip, 0)
