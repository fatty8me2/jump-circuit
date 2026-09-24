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
var _ring: MeshInstance3D
var _glint: MeshInstance3D
var _gathering: bool = false


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
	_mat.emission_energy_multiplier = 0.55
	_mat.roughness = 0.1
	_mat.metallic = 0.3
	_mat.rim_enabled = true
	_mat.rim = 1.0
	_cube = PartyFx.part(pivot, PartyFx.box_mesh(Vector3.ONE * 0.9), _mat, Vector3.ZERO)
	# glowing edges: a slightly larger wire-ish shell of thin bars
	var edge: StandardMaterial3D = PartyFx.glow_mat(Color(1.0, 0.9, 0.5), 1.3)
	for axis: int in 3:
		for a: int in [-1, 1]:
			for b: int in [-1, 1]:
				var size := Vector3(0.06, 0.06, 0.06)
				size[axis] = 0.96
				var pos := Vector3.ZERO
				pos[(axis + 1) % 3] = 0.46 * a
				pos[(axis + 2) % 3] = 0.46 * b
				PartyFx.part(pivot, PartyFx.box_mesh(size), edge, pos)
	_core = PartyFx.part(pivot, PartyFx.sphere_mesh(0.16), PartyFx.glow_mat(Color(1, 0.95, 0.8), 1.4), Vector3.ZERO)
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
	_halo = PartyFx.emitter({"amount": 22, "lifetime": 1.2, "size": 0.12, "color": Color(1.0, 0.9, 0.5),
		"shape": "ring", "radius": 0.9, "inner": 0.7, "height": 0.6, "vmin": 0.2, "vmax": 0.6, "dir": Vector3.UP,
		"spread": 20.0, "tangential": 2.5, "spark": true, "aabb": 2.0})
	add_child(_halo)
	var ring: MeshInstance3D = PartyFx.part(self, _ring_mesh(), PartyFx.glow_mat(Color(0.5, 0.8, 1.0, 0.5), 1.6, true), Vector3(0, -1.05, 0))
	ring.name = "Ring"
	_ring = ring
	# a star glint that sweeps over a corner now and then
	_glint = Fx.sprite(Color(2.2, 2.1, 1.6), 0.9, Fx.Tex.STAR, true)
	_glint.layers = PartyFx.LAYER
	_glint.position = Vector3(0.36, 0.4, 0.36)
	pivot.add_child(_glint)


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
	# rainbow shimmer, a breathing "?" and ground ring, and the corner glint
	var hue: float = fmod(_t * 0.12 + float(index) * 0.13, 1.0)
	_mat.emission = Color.from_hsv(hue, 0.7, 1.0)
	_mat.albedo_color = Color.from_hsv(hue, 0.55, 1.0, 0.5)
	var beat: float = sin(_t * 3.1)
	_q.scale = Vector3.ONE * (1.0 + 0.07 * beat)
	_q.outline_modulate = Color.from_hsv(fmod(hue + 0.5, 1.0), 0.8, 0.35)
	if _ring != null:
		_ring.scale = Vector3.ONE * (1.0 + 0.08 * sin(_t * 2.2 + 1.0))
	if _glint != null:
		var g: float = fmod(_t + float(index) * 0.37, 2.6)
		var k: float = clampf(1.0 - absf(g - 0.25) / 0.25, 0.0, 1.0)
		_glint.visible = k > 0.0
		_glint.scale = Vector3.ONE * (0.2 + k)
	if not available:
		_respawn_left -= dt
		if _respawn_left <= 0.45 and not _gathering:
			_gathering = true
			_gather_fx()
		if _respawn_left <= 0.0:
			appear()


## Taken: pop with a burst and hide for `respawn` seconds.
func take(respawn: float) -> void:
	if not available:
		_respawn_left = maxf(_respawn_left, respawn)
		return
	available = false
	_gathering = false
	_respawn_left = respawn
	_break_fx()
	visible = false


## Breaking open: the glass shell flashes out, shatters into rainbow shards, the "?" flies
## off, and confetti + stars + sparks spray out.
func _break_fx() -> void:
	var at: Vector3 = global_position
	var parent: Node = get_parent()
	if parent == null or not is_inside_tree():
		return
	var hue: float = fmod(_t * 0.12 + float(index) * 0.13, 1.0)
	var col: Color = Color.from_hsv(hue, 0.55, 1.0)
	# the shell bursting: a copy of the cube swells and fades in a blink
	var pivot: Node3D = get_node("Pivot") as Node3D
	var shell_mat: StandardMaterial3D = _mat.duplicate() as StandardMaterial3D
	shell_mat.emission_energy_multiplier = 3.0
	var shell: MeshInstance3D = PartyFx.part(parent as Node3D if parent is Node3D else self, PartyFx.box_mesh(Vector3.ONE * 0.9), shell_mat, Vector3.ZERO)
	shell.global_transform = pivot.global_transform
	var tw: Tween = shell.create_tween().set_parallel(true)
	tw.tween_property(shell, "scale", Vector3.ONE * 1.6, 0.16).set_ease(Tween.EASE_OUT)
	tw.tween_property(shell_mat, "albedo_color:a", 0.0, 0.16)
	tw.chain().tween_callback(shell.queue_free)
	PartyFx.orb_pulse(parent, at, Color(1.0, 0.97, 0.85, 0.6), 0.3, 0.9, 0.12, 2.0)
	PartyFx.shards(parent, at, col, 14, 7.0, 0.16, Vector3.UP, 180.0)
	PartyFx.confetti(parent, at, 48, 8.0, Vector3.UP, 80.0, 1.5)
	PartyFx.star_ring(parent, at, Color(1.0, 0.9, 0.4), 9, 6.0, 0.45)
	PartyFx.burst(parent, at, Color(1.0, 0.85, 0.35), 30, 7.0, 0.28, 0.5)
	PartyFx.sparks(parent, at, Color(1, 1, 1), 18, 8.0)
	PartyFx.ring_pulse(parent, at + Vector3(0, -1.0, 0), Vector3.UP, col, 0.5, 2.2, 0.35, 0.12)
	PartyFx.flash(parent, at, col.lerp(Color.WHITE, 0.4), 5.0, 6.0, 0.3)
	# rays of rainbow light burst out of it, glitter rains down, dust puffs off the lawn
	for i: int in 6:
		var a: float = TAU * float(i) / 6.0 + _t
		var d := Vector3(cos(a), 0.45 + 0.35 * float(i % 2), sin(a)).normalized()
		PartyFx.beam(parent, at, at + d * 2.6, Color.from_hsv(fmod(hue + float(i) / 6.0, 1.0), 0.5, 1.0, 0.5), 0.07, 0.28, 2.0)
	HeroFx.pop(parent, {"amount": 30, "lifetime": 1.2, "shape": "sphere", "radius": 0.5, "dir": Vector3.UP,
		"spread": 70.0, "speed": Vector2(1.0, 3.5), "gravity": Vector3(0, -3.0, 0), "tex": Fx.Tex.STAR, "size": 0.16,
		"curve": "pop", "hue": 0.5, "color": Color(1.3, 1.2, 0.8)}, at)
	HeroFx.dust_ring(parent, at + Vector3(0, -1.0, 0), Color(0.9, 0.88, 0.8, 0.4), 0.6, 8, 3.5)
	# the "?" pops off, spinning up and away
	var q := Label3D.new()
	q.text = "?"
	q.font_size = 140
	q.outline_size = 24
	q.modulate = Color(1.0, 0.9, 0.35)
	q.outline_modulate = Color(0.35, 0.15, 0.0)
	q.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	q.pixel_size = 0.004
	q.layers = PartyFx.LAYER
	parent.add_child(q)
	q.global_position = at
	var qt: Tween = q.create_tween().set_parallel(true)
	qt.tween_property(q, "global_position", at + Vector3(0, 1.6, 0), 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	qt.tween_property(q, "scale", Vector3.ONE * 1.8, 0.5)
	qt.tween_property(q, "modulate:a", 0.0, 0.5).set_ease(Tween.EASE_IN)
	qt.tween_property(q, "outline_modulate:a", 0.0, 0.5).set_ease(Tween.EASE_IN)
	qt.chain().tween_callback(q.queue_free)


## Just before it comes back: sparkles gather into the empty spot.
func _gather_fx() -> void:
	if not is_inside_tree():
		return
	PartyFx.one_shot(get_parent(), global_position, {"amount": 24, "lifetime": 0.45, "size": 0.22, "color": Color(1.4, 1.3, 0.8),
		"tex": "star", "shape": "shell", "radius": 1.6, "vmin": 0.0, "vmax": 0.1, "radial": -14.0, "angle": true,
		"explosiveness": 0.7, "shrink": false, "colors": [Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.3)]})


func appear() -> void:
	available = true
	visible = true
	scale = Vector3.ONE * 0.1
	var tw: Tween = create_tween()
	tw.tween_property(self, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	var parent: Node = get_parent()
	PartyFx.burst(parent, global_position, Color(0.6, 0.9, 1.0), 16, 2.5, 0.2, 0.5)
	PartyFx.ring_pulse(parent, global_position + Vector3(0, -1.0, 0), Vector3.UP, Color(0.6, 0.9, 1.0), 0.2, 1.4, 0.35, 0.12)
	PartyFx.star_ring(parent, global_position, Color(1.0, 0.95, 0.6), 6, 3.0, 0.3)


## A racer whose centre (feet + 0.8 m) is at `center` touches the box.
func touches(center: Vector3) -> bool:
	return available and center.distance_to(global_position) < 1.25
