class_name PartyStatusFx
extends Node3D
## The look of one status effect on a racer, a ghost or a practice dummy (parented to its
## root, feet at the origin). Built with an entry flourish, animated while it lasts, warns
## when it is about to wear off (fed `left` by its owner), and leaves with its own end
## effect through `retire()`. Purely cosmetic.
##   freeze - an ice block with crystal spikes, frost mist and glints; cracks, then shatters
##   float  - a wobbling violet gravity bubble with swirling motes; pops
##   stun / spin - dizzy stars circling the head (spin adds a whirl at the feet)
##   slow   - a little storm cloud over the head: drizzle and crackling static
##   shrink - pink sparkles orbiting the shrunken racer; a puff when they grow back

const ICE := Color(0.7, 0.93, 1.0)
const VIOLET := Color(0.7, 0.45, 1.0)
const PINK := Color(1.0, 0.5, 0.95)
const STAR := Color(1.0, 0.92, 0.4)

## Which effect this shows.
var effect: String = ""
## Seconds left, when the owner knows (drives the running-out warning); < 0 = unknown.
var left: float = -1.0
var _t: float = 0.0
var _spin: Node3D
var _body: MeshInstance3D
var _mat: StandardMaterial3D
var _cracks: Array[MeshInstance3D] = []
var _crackle_t: float = 0.0
var _retired: bool = false
var _seed: int = 0


static func create(e: String) -> PartyStatusFx:
	var v := PartyStatusFx.new()
	v.effect = e
	v.name = "Status_" + e
	return v


func _ready() -> void:
	_seed = randi()
	match effect:
		"freeze":
			_build_ice()
		"float":
			_build_bubble()
		"stun", "spin":
			_build_stars()
		"slow":
			_build_storm()
		"shrink":
			_build_shrink()


## The level / layer the racer stands in (for world-space one-shots that outlive us).
func _world() -> Node:
	var p: Node = get_parent()
	if p != null and p.get_parent() != null:
		return p.get_parent()
	return p


func _center() -> Vector3:
	return global_position + Vector3(0, 0.85, 0)


# ---- builders -------------------------------------------------------------------------------

func _build_ice() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	var root := Node3D.new()
	add_child(root)
	_spin = root
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.72, 0.94, 1.0, 0.42)
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.roughness = 0.04
	_mat.metallic = 0.25
	_mat.emission_enabled = true
	_mat.emission = Color(0.45, 0.75, 1.0)
	_mat.emission_energy_multiplier = 0.5
	_mat.rim_enabled = true
	_mat.rim = 1.0
	_mat.rim_tint = 0.2
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_body = PartyFx.part(root, PartyFx.box_mesh(Vector3(1.2, 1.75, 1.2)), _mat, Vector3(0, 0.87, 0), Vector3.ONE, Vector3(0, 12, 0))
	# a bevelled second skin so the block reads as cut crystal
	PartyFx.part(root, PartyFx.box_mesh(Vector3(1.05, 1.9, 1.05)), _mat, Vector3(0, 0.9, 0), Vector3.ONE, Vector3(0, 57, 0))
	var spike: StandardMaterial3D = PartyFx.solid_mat(Color(0.82, 0.97, 1.0, 0.75), 0.9, 0.05, 0.2)
	# crystal clusters around the base and bursting off the top corners
	for i: int in 9:
		var a: float = TAU * float(i) / 9.0 + rng.randf_range(-0.2, 0.2)
		var r: float = rng.randf_range(0.62, 0.85)
		var h: float = rng.randf_range(0.35, 0.8)
		PartyFx.part(root, PartyFx.cone_mesh(rng.randf_range(0.1, 0.17), h, 5), spike,
			Vector3(cos(a) * r, h * 0.35, sin(a) * r), Vector3.ONE,
			Vector3(rad_to_deg(sin(a)) * 0.5 + rng.randf_range(-15, 15), 0, -rad_to_deg(cos(a)) * 0.5 + rng.randf_range(-15, 15)))
	for i: int in 4:
		var a: float = TAU * float(i) / 4.0 + 0.6
		PartyFx.part(root, PartyFx.cone_mesh(0.12, 0.55, 5), spike, Vector3(cos(a) * 0.5, 1.75, sin(a) * 0.5), Vector3.ONE,
			Vector3(rad_to_deg(sin(a)) * 0.6, 0, -rad_to_deg(cos(a)) * 0.6))
	# cracks that appear as it is about to break (hidden until then)
	var crack: StandardMaterial3D = PartyFx.glow_mat(Color(0.9, 1.0, 1.0), 2.5)
	for i: int in 7:
		var c: MeshInstance3D = PartyFx.part(root, PartyFx.box_mesh(Vector3(0.03, rng.randf_range(0.3, 0.7), 0.03)), crack,
			Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(0.4, 1.5), 0.62 if i % 2 == 0 else -0.62),
			Vector3.ONE, Vector3(0, 12, rng.randf_range(-50, 50)))
		c.visible = false
		_cracks.append(c)
	# frost rolling off the base, glints on the faces, a few flakes
	add_child(PartyFx.emitter({"amount": 8, "lifetime": 1.4, "size": 0.8, "color": Color(0.9, 0.97, 1.0, 0.35),
		"additive": false, "tex": "smoke", "shape": "ring", "radius": 0.8, "inner": 0.5, "dir": Vector3(1, 0, 0),
		"spread": 180.0, "flat": 0.8, "vmin": 0.3, "vmax": 0.8, "gravity": Vector3(0, -0.3, 0), "grow": true,
		"angle": true, "spin": 20.0, "aabb": 3.0, "colors": [Color(1, 1, 1, 0), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)]}))
	var glint: GPUParticles3D = PartyFx.emitter({"amount": 5, "lifetime": 0.5, "size": 0.45, "color": Color(1.6, 1.9, 2.0),
		"tex": "star", "shape": "box", "extents": Vector3(0.62, 0.9, 0.62), "vmin": 0.0, "vmax": 0.0, "angle": true,
		"randomness": 1.0, "aabb": 3.0, "grow": true, "colors": [Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)]})
	glint.position = Vector3(0, 0.9, 0)
	add_child(glint)
	var flakes: GPUParticles3D = PartyFx.emitter({"amount": 10, "lifetime": 1.3, "size": 0.12, "color": Color(0.85, 0.97, 1.0),
		"tex": "star", "shape": "box", "extents": Vector3(0.7, 0.2, 0.7), "dir": Vector3.DOWN, "spread": 30.0,
		"vmin": 0.2, "vmax": 0.5, "gravity": Vector3(0, -0.5, 0), "spin": 90.0, "angle": true, "aabb": 3.0,
		"colors": [Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)]})
	flakes.position = Vector3(0, 1.9, 0)
	add_child(flakes)
	root.scale = Vector3(1.0, 0.1, 1.0)
	root.create_tween().tween_property(root, "scale", Vector3.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_entry.call_deferred()


func _build_bubble() -> void:
	_spin = Node3D.new()
	_spin.position = Vector3(0, 0.8, 0)
	add_child(_spin)
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.72, 0.5, 1.0, 0.3)
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.roughness = 0.02
	_mat.metallic = 0.4
	_mat.emission_enabled = true
	_mat.emission = Color(0.55, 0.3, 1.0)
	_mat.emission_energy_multiplier = 0.9
	_mat.rim_enabled = true
	_mat.rim = 1.0
	_mat.rim_tint = 0.9
	_body = PartyFx.part(self, PartyFx.sphere_mesh(1.0, 28), _mat, Vector3(0, 0.8, 0))
	# a glossy highlight, swirling motes (the spinning pivot carries them round)
	PartyFx.part(self, PartyFx.sphere_mesh(0.14, 10), PartyFx.glow_mat(Color(1, 1, 1, 0.6), 1.6, true), Vector3(-0.42, 1.32, -0.55), Vector3(1.0, 0.6, 1.0))
	_spin.add_child(PartyFx.emitter({"amount": 22, "lifetime": 0.9, "size": 0.14, "color": Color(0.8, 0.55, 1.4),
		"shape": "shell", "radius": 0.85, "vmin": 0.0, "vmax": 0.15, "local": true, "spark": true, "aabb": 2.5,
		"colors": [Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)]}))
	var rise: GPUParticles3D = PartyFx.emitter({"amount": 6, "lifetime": 1.3, "size": 0.2, "color": Color(0.85, 0.7, 1.3),
		"tex": "ring", "shape": "sphere", "radius": 0.9, "dir": Vector3.UP, "spread": 20.0, "vmin": 0.4, "vmax": 0.9,
		"shrink": false, "aabb": 3.0, "colors": [Color(1, 1, 1, 0), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0)]})
	rise.position = Vector3(0, 0.8, 0)
	add_child(rise)
	PartyFx.pop_in(_body, 0.45)
	_entry.call_deferred()


func _build_stars() -> void:
	_spin = Node3D.new()
	_spin.position = Vector3(0, 1.45, 0)
	_spin.rotation_degrees = Vector3(14, 0, 8)
	add_child(_spin)
	for i: int in 4:
		var a: float = TAU * float(i) / 4.0
		var s: MeshInstance3D = PartyFx.star_sprite(0.3, Color(1.0, 0.86, 0.2))
		s.position = Vector3(cos(a) * 0.45, 0, sin(a) * 0.45)
		_spin.add_child(s)
	# a faint ring the stars ride on, and glitter shed from them
	var tm := TorusMesh.new()
	tm.inner_radius = 0.43
	tm.outer_radius = 0.47
	tm.rings = 32
	tm.ring_segments = 4
	PartyFx.part(_spin, tm, PartyFx.glow_mat(Color(1.0, 0.9, 0.5, 0.25), 1.5, true), Vector3.ZERO)
	_spin.add_child(PartyFx.emitter({"amount": 10, "lifetime": 0.5, "size": 0.12, "color": STAR, "spark": true,
		"shape": "ring", "radius": 0.45, "inner": 0.4, "vmin": 0.0, "vmax": 0.2, "aabb": 2.0}))
	if effect == "spin":
		var whirl: GPUParticles3D = PartyFx.emitter({"amount": 18, "lifetime": 0.45, "size": 0.35, "color": Color(0.95, 0.9, 0.7, 0.55),
			"additive": false, "tex": "smoke", "shape": "ring", "radius": 0.6, "inner": 0.4, "local": true,
			"vmin": 0.0, "vmax": 0.2, "aabb": 2.0, "angle": true, "colors": [Color(1, 1, 1, 0), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)]})
		whirl.position = Vector3(0, 0.15, 0)
		var wp := Node3D.new()
		wp.name = "Whirl"
		add_child(wp)
		wp.add_child(whirl)
	PartyFx.pop_in(_spin, 0.4)


func _build_storm() -> void:
	_spin = Node3D.new()
	_spin.position = Vector3(0, 2.05, 0)
	add_child(_spin)
	var cloud: StandardMaterial3D = PartyFx.solid_mat(Color(0.32, 0.34, 0.44), 0.15, 0.9)
	for i: int in 5:
		var a: float = TAU * float(i) / 5.0
		var r: float = 0.22 if i % 2 == 0 else 0.3
		PartyFx.part(_spin, PartyFx.sphere_mesh(r, 12), cloud, Vector3(cos(a) * 0.28, (0.06 if i % 2 == 0 else 0.0), sin(a) * 0.22))
	PartyFx.part(_spin, PartyFx.sphere_mesh(0.3, 12), cloud, Vector3(0, 0.12, 0))
	_spin.add_child(PartyFx.emitter({"amount": 14, "lifetime": 0.4, "size": Vector2(0.025, 0.3), "color": Color(0.7, 0.8, 1.2, 0.8),
		"tex": "streak", "facing": "velocity", "shape": "box", "extents": Vector3(0.35, 0.02, 0.3), "offset": Vector3(0, -0.2, 0),
		"dir": Vector3.DOWN, "spread": 4.0, "vmin": 5.0, "vmax": 6.5, "shrink": false, "aabb": 4.0,
		"colors": [Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.3)]}))
	var stat: GPUParticles3D = PartyFx.emitter({"amount": 14, "lifetime": 0.22, "size": 0.12, "color": Color(0.65, 0.75, 1.3),
		"shape": "sphere", "radius": 0.5, "vmin": 1.0, "vmax": 3.0, "spark": true, "aabb": 1.5})
	stat.position = Vector3(0, 0.75, 0)
	add_child(stat)
	PartyFx.pop_in(_spin, 0.35)


func _build_shrink() -> void:
	_spin = Node3D.new()
	_spin.position = Vector3(0, 0.45, 0)
	add_child(_spin)
	for i: int in 3:
		var a: float = TAU * float(i) / 3.0
		var s: MeshInstance3D = PartyFx.star_sprite(0.24, Color(1.0, 0.55, 0.95))
		s.position = Vector3(cos(a) * 0.55, 0.25 * float(i % 2), sin(a) * 0.55)
		_spin.add_child(s)
	_spin.add_child(PartyFx.emitter({"amount": 12, "lifetime": 0.7, "size": 0.12, "color": PINK, "spark": true,
		"shape": "ring", "radius": 0.55, "inner": 0.45, "vmin": 0.1, "vmax": 0.4, "dir": Vector3.UP, "spread": 30.0,
		"aabb": 2.0, "hue": 0.08}))
	PartyFx.pop_in(_spin, 0.4)


## World-space entry flourish (after we are in the tree).
func _entry() -> void:
	if not is_inside_tree():
		return
	var w: Node = _world()
	match effect:
		"freeze":
			PartyFx.shards(w, global_position + Vector3(0, 0.5, 0), ICE, 14, 6.0, 0.14)
			PartyFx.one_shot(w, global_position + Vector3(0, 0.2, 0), {"amount": 26, "lifetime": 0.7, "size": 0.7,
				"color": Color(0.9, 0.97, 1.0, 0.6), "additive": false, "tex": "smoke", "shape": "ring", "radius": 0.5,
				"inner": 0.3, "dir": Vector3(1, 0.1, 0), "spread": 180.0, "flat": 1.0, "vmin": 3.0, "vmax": 5.0,
				"damping": 6.0, "grow": true, "angle": true, "colors": [Color(1, 1, 1, 0.9), Color(1, 1, 1, 0)]})
			PartyFx.ring_pulse(w, global_position + Vector3(0, 0.1, 0), Vector3.UP, ICE, 0.4, 2.2, 0.35, 0.12)
		"float":
			PartyFx.ring_pulse(w, _center(), Vector3.UP, VIOLET, 0.3, 1.8, 0.4, 0.1)


# ---- per frame ------------------------------------------------------------------------------

func _process(dt: float) -> void:
	if _retired:
		return
	_t += dt
	var ending: bool = left >= 0.0 and left < 0.7
	match effect:
		"freeze":
			if ending and _spin != null:
				# about to crack open: shiver, cracks spread, chips fall
				var k: float = 1.0 - left / 0.7
				_spin.position = Vector3(sin(_t * 71.0), 0, cos(_t * 63.0)) * 0.035 * k
				for i: int in _cracks.size():
					_cracks[i].visible = float(i) < k * float(_cracks.size()) + 1.0
		"float":
			if _body != null:
				var f: float = 3.2 if not ending else 11.0
				var w: float = 0.05 if not ending else 0.1
				_body.scale = Vector3(1.0 + sin(_t * f) * w, 1.0 - sin(_t * f) * w, 1.0 + cos(_t * f * 0.8) * w)
				if ending:
					_body.visible = PartyFx.blink_on(left, 0.7)
			if _spin != null:
				_spin.rotation.y += dt * 3.0
		"stun", "spin":
			if _spin != null:
				_spin.rotation.y += dt * (7.0 if effect == "stun" else 11.0)
				_spin.position.y = 1.45 + sin(_t * 5.0) * 0.05
				if ending:
					_spin.visible = PartyFx.blink_on(left, 0.7)
			var wp: Node3D = get_node_or_null("Whirl") as Node3D
			if wp != null:
				wp.rotation.y -= dt * 14.0
		"slow":
			if _spin != null:
				_spin.position.y = 2.05 + sin(_t * 2.5) * 0.06
				_spin.rotation.y += dt * 0.8
			_crackle_t -= dt
			if _crackle_t <= 0.0 and is_inside_tree():
				_crackle_t = randf_range(0.18, 0.4)
				PartyFx.crackle(_world(), _center() + Vector3(randf_range(-0.2, 0.2), randf_range(-0.3, 0.4), randf_range(-0.2, 0.2)), 0.45, Color(0.7, 0.8, 1.0), 3, 0.07)
		"shrink":
			if _spin != null:
				_spin.rotation.y += dt * 4.0
				_spin.position.y = 0.45 + sin(_t * 3.0) * 0.08
				if ending:
					_spin.visible = PartyFx.blink_on(left, 0.7)


# ---- the end -----------------------------------------------------------------------------------

## The effect wore off (or was cleared): play its end effect and free.
func retire() -> void:
	if _retired:
		return
	_retired = true
	if not is_inside_tree():
		queue_free()
		return
	var w: Node = _world()
	var c: Vector3 = _center()
	match effect:
		"freeze":
			PartyFx.shards(w, c, ICE, 22, 8.0, 0.2, Vector3.UP, 110.0)
			PartyFx.shards(w, c + Vector3(0, 0.5, 0), Color(0.95, 1.0, 1.0), 10, 5.0, 0.12)
			PartyFx.burst(w, c, Color(0.75, 0.95, 1.0), 26, 6.0, 0.22)
			PartyFx.one_shot(w, c, {"amount": 16, "lifetime": 0.6, "size": 0.35, "color": Color(1.5, 1.8, 2.0), "tex": "star",
				"shape": "box", "extents": Vector3(0.6, 0.85, 0.6), "vmin": 0.5, "vmax": 2.0, "angle": true, "grow": true,
				"colors": [Color(1, 1, 1, 1), Color(1, 1, 1, 0)]})
			PartyFx.smoke(w, global_position + Vector3(0, 0.5, 0), Color(0.9, 0.97, 1.0, 0.5), 10, 0.7, 0.9)
			PartyFx.ring_pulse(w, global_position + Vector3(0, 0.15, 0), Vector3.UP, ICE, 0.5, 2.4, 0.3, 0.1)
		"float":
			PartyFx.one_shot(w, c, {"amount": 26, "lifetime": 0.5, "size": 0.16, "color": Color(0.9, 0.7, 1.4),
				"tex": "ring", "shape": "shell", "radius": 0.95, "vmin": 2.0, "vmax": 4.5, "damping": 3.0,
				"gravity": Vector3(0, -6, 0), "colors": [Color(1, 1, 1, 1), Color(1, 1, 1, 0)]})
			PartyFx.ring_pulse(w, c, Vector3.UP, VIOLET, 0.9, 2.0, 0.22, 0.08)
			PartyFx.ring_pulse(w, c, Vector3.FORWARD, VIOLET, 0.9, 1.8, 0.22, 0.08)
			PartyFx.burst(w, c, Color(0.85, 0.6, 1.0), 16, 4.0, 0.18, 0.35)
		"stun", "spin":
			if _spin != null:
				PartyFx.star_ring(w, _spin.global_position, STAR, 6, 3.5, 0.35)
		"slow":
			if _spin != null:
				PartyFx.smoke(w, _spin.global_position, Color(0.35, 0.37, 0.45, 0.55), 8, 0.4, 0.8)
				PartyFx.sparks(w, _spin.global_position, Color(0.7, 0.8, 1.0), 10, 4.0)
		"shrink":
			PartyFx.star_ring(w, global_position + Vector3(0, 0.6, 0), PINK, 8, 4.5, 0.35)
			PartyFx.ring_pulse(w, global_position + Vector3(0, 0.1, 0), Vector3.UP, PINK, 0.3, 1.6, 0.3, 0.12)
			PartyFx.burst(w, global_position + Vector3(0, 0.8, 0), PINK, 16, 3.0, 0.2, 0.4)
	queue_free()
