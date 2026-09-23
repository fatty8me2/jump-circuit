class_name ItemBox
extends Node3D
## Spinning "?" item box. The PartyLayer places a row across each checkpoint lawn and the
## start, and decides pickups (the host does, online); this node only shows the box, pops it
## with a burst when taken and brings it back after the respawn delay.

var index: int = 0
var available: bool = true
var _respawn_left: float = 0.0
var _cube: MeshInstance3D
var _core: MeshInstance3D
var _mat: StandardMaterial3D
var _q: Label3D
var _halo: GPUParticles3D
var _t: float = 0.0


func _ready() -> void:
	_t = float(index) * 0.7
	var pivot := Node3D.new()
	pivot.name = "Pivot"
	add_child(pivot)
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.55, 0.8, 1.0, 0.45)
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.emission_enabled = true
	_mat.emission = Color(0.5, 0.8, 1.0)
	_mat.emission_energy_multiplier = 1.4
	_mat.roughness = 0.1
	_mat.metallic = 0.3
	_mat.rim_enabled = true
	_mat.rim = 1.0
	_cube = PartyFx.part(pivot, PartyFx.box_mesh(Vector3.ONE * 0.9), _mat, Vector3.ZERO)
	# glowing edges: a slightly larger wire-ish shell of thin bars
	var edge: StandardMaterial3D = PartyFx.glow_mat(Color(1.0, 0.95, 0.6), 2.5)
	for axis: int in 3:
		for a: int in [-1, 1]:
			for b: int in [-1, 1]:
				var size := Vector3(0.06, 0.06, 0.06)
				size[axis] = 0.96
				var pos := Vector3.ZERO
				pos[(axis + 1) % 3] = 0.46 * a
				pos[(axis + 2) % 3] = 0.46 * b
				PartyFx.part(pivot, PartyFx.box_mesh(size), edge, pos)
	_core = PartyFx.part(pivot, PartyFx.sphere_mesh(0.22), PartyFx.glow_mat(Color(1, 1, 1), 3.0), Vector3.ZERO)
	_q = Label3D.new()
	_q.text = "?"
	_q.font_size = 140
	_q.outline_size = 24
	_q.modulate = Color(1.0, 0.9, 0.35)
	_q.outline_modulate = Color(0.35, 0.15, 0.0)
	_q.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_q.pixel_size = 0.004
	_q.layers = PartyFx.LAYER
	add_child(_q)
	# orbiting sparkles and a soft ground glow ring
	_halo = PartyFx.emitter({"amount": 16, "lifetime": 1.2, "size": 0.12, "color": Color(1.0, 0.9, 0.5),
		"shape": "ring", "radius": 0.9, "inner": 0.7, "height": 0.6, "vmin": 0.2, "vmax": 0.6, "dir": Vector3.UP,
		"spread": 20.0, "tangential": 2.5, "spark": true, "aabb": 2.0})
	add_child(_halo)
	var ring: MeshInstance3D = PartyFx.part(self, _ring_mesh(), PartyFx.glow_mat(Color(0.5, 0.8, 1.0, 0.5), 1.6, true), Vector3(0, -1.05, 0))
	ring.name = "Ring"


func _ring_mesh() -> TorusMesh:
	var tm := TorusMesh.new()
	tm.inner_radius = 0.55
	tm.outer_radius = 0.7
	tm.rings = 32
	tm.ring_segments = 4
	return tm


func _process(dt: float) -> void:
	_t += dt
	var pivot: Node3D = get_node("Pivot") as Node3D
	pivot.rotation = Vector3(sin(_t * 0.9) * 0.4, _t * 1.6, cos(_t * 0.7) * 0.3)
	pivot.position.y = sin(_t * 2.2) * 0.12
	_q.position.y = pivot.position.y
	# rainbow shimmer
	var hue: float = fmod(_t * 0.12 + float(index) * 0.13, 1.0)
	_mat.emission = Color.from_hsv(hue, 0.5, 1.0)
	_mat.albedo_color = Color.from_hsv(hue, 0.35, 1.0, 0.45)
	if not available:
		_respawn_left -= dt
		if _respawn_left <= 0.0:
			appear()


## Taken: pop with a burst and hide for `respawn` seconds.
func take(respawn: float) -> void:
	if not available:
		_respawn_left = maxf(_respawn_left, respawn)
		return
	available = false
	_respawn_left = respawn
	var at: Vector3 = global_position
	var parent: Node = get_parent()
	PartyFx.burst(parent, at, Color(1.0, 0.85, 0.35), 40, 7.0, 0.3, 0.6)
	PartyFx.burst(parent, at, Color(0.5, 0.8, 1.0), 24, 4.0, 0.4, 0.5)
	PartyFx.sparks(parent, at, Color(1, 1, 1), 18, 8.0)
	PartyFx.orb_pulse(parent, at, Color(1.0, 0.95, 0.7, 0.8), 0.4, 1.6, 0.3, 3.0)
	visible = false


func appear() -> void:
	available = true
	visible = true
	scale = Vector3.ONE * 0.1
	var tw: Tween = create_tween()
	tw.tween_property(self, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	PartyFx.burst(get_parent(), global_position, Color(0.6, 0.9, 1.0), 16, 2.5, 0.2, 0.5)


## A racer whose centre (feet + 0.8 m) is at `center` touches the box.
func touches(center: Vector3) -> bool:
	return available and center.distance_to(global_position) < 1.25
