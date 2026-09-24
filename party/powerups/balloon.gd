extends PowerUp
## Balloon Shield (15 s or one hit): three balloons bob over your shoulders. The next hit (or
## hazard) that would land on you pops them in a shower of confetti instead - and the attacker
## gets their own knockback bounced straight back at them.

const COLORS: Array[Color] = [Color(1.0, 0.45, 0.7), Color(0.4, 0.8, 1.0), Color(1.0, 0.9, 0.3)]

var _balloons: Array[Node3D] = []
## The rubber of each balloon (squashes as it bobs, shrinks as the shield runs out).
var _skins: Array[MeshInstance3D] = []
var _bubble: MeshInstance3D
var _t: float = 0.0
## Popped by a hit (vs. simply running out, when the balloons float away instead).
var _popped: bool = false


func _init() -> void:
	duration = 15.0


func build_look() -> void:
	var string_mat: StandardMaterial3D = PartyFx.solid_mat(Color(0.95, 0.95, 0.95), 0.3)
	for i: int in 3:
		var piv := Node3D.new()
		piv.position = Vector3(-0.35 + 0.35 * float(i), 0.8, 0.25)
		piv.set_meta("phase", float(i) * 2.1)
		add_child(piv)
		var mat: StandardMaterial3D = PartyFx.solid_mat(Color(COLORS[i].r, COLORS[i].g, COLORS[i].b, 0.9), 0.5, 0.15, 0.1)
		mat.rim_enabled = true
		mat.rim = 0.7
		_skins.append(PartyFx.part(piv, PartyFx.sphere_mesh(0.28, 18), mat, Vector3(0, 1.05 + 0.12 * float(i % 2), 0), Vector3(0.9, 1.1, 0.9)))
		PartyFx.part(piv, PartyFx.cone_mesh(0.06, 0.08, 6), mat, Vector3(0, 0.74 + 0.12 * float(i % 2), 0), Vector3(1, -1, 1))
		PartyFx.part(piv, PartyFx.sphere_mesh(0.06, 8), PartyFx.glow_mat(Color(1, 1, 1, 0.7), 2.0, true), Vector3(-0.1, 1.15 + 0.12 * float(i % 2), -0.18))
		PartyFx.part(piv, PartyFx.cyl_mesh(0.008, 0.72), string_mat, Vector3(0, 0.34, 0))
		_balloons.append(piv)
	# a faint shield bubble and sparkles, so it reads as protection
	_bubble = PartyFx.part(self, PartyFx.sphere_mesh(0.8, 24), PartyFx.glow_mat(Color(1.0, 0.7, 0.9, 0.1), 1.5, true), Vector3(0, 0.7, 0), Vector3(1, 1.15, 1))
	add_child(PartyFx.emitter({"amount": 12, "lifetime": 1.0, "size": 0.1, "color": Color(1.0, 0.8, 0.95),
		"shape": "shell", "radius": 0.85, "vmin": 0.0, "vmax": 0.2, "spark": true, "aabb": 3.0,
		"colors": [Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)]}))
	(get_child(get_child_count() - 1) as Node3D).position = Vector3(0, 0.7, 0)
	for piv: Node3D in _balloons:
		PartyFx.pop_in(piv, 0.5)
	if is_inside_tree():
		PartyFx.burst(world(), global_position + Vector3(0, 1.6, 0), Color(1.0, 0.7, 0.9), 30, 4.0, 0.25)
		PartyFx.star_ring(world(), global_position + Vector3(0, 1.6, 0), Color(1.0, 0.7, 0.9), 7, 3.5, 0.32)
		PartyFx.ring_pulse(world(), global_position + Vector3(0, 0.8, 0), Vector3.UP, Color(1.0, 0.75, 0.9), 0.3, 1.4, 0.35, 0.12)


func begin() -> void:
	layer.sfx.play("pop", 0.7, 1.6)


func _process(dt: float) -> void:
	_t += dt
	var left: float = time_left - (0.0 if local else 1.0)
	# running out: the balloons go soft and wrinkly and the shield blinks
	var soft: float = clampf(1.0 - left / 2.5, 0.0, 1.0) if duration > 0.0 else 0.0
	var on: bool = PartyFx.blink_on(left, 2.0)
	for i: int in _balloons.size():
		var piv: Node3D = _balloons[i]
		var ph: float = float(piv.get_meta("phase"))
		piv.rotation = Vector3(sin(_t * 1.7 + ph) * (0.12 + 0.2 * soft), 0, sin(_t * 1.3 + ph) * (0.15 + 0.2 * soft))
		var sq: float = sin(_t * 3.1 + ph) * 0.05 + sin(_t * 17.0 + ph) * 0.05 * soft
		var s: float = 1.0 - 0.35 * soft
		_skins[i].scale = Vector3(0.9 * s * (1.0 + sq), 1.1 * s * (1.0 - sq), 0.9 * s * (1.0 + sq))
		piv.visible = on or i % 2 == 0
	if _bubble != null:
		var k: float = 1.0 + sin(_t * 4.0) * 0.03
		_bubble.scale = Vector3(k, 1.15 * k, k)
		_bubble.visible = on


func absorb_hit(from_id: int) -> bool:
	if ended:
		return false
	var at: Vector3 = chest() + Vector3(0, 1.0, 0)
	_popped = true
	_pop_fx(layer, at)
	fx("pop", {"at": arr(at)})
	layer.sfx.play("pop", 1.0, 1.0)
	layer.hud.announce("BLOCKED!", Color(1.0, 0.7, 0.9))
	# bounce it back: the attacker (if it was a rival, not a dummy) is thrown away from us
	var g: RemoteRacer = layer.ghost(from_id)
	if g != null and layer.is_rival(from_id):
		var away: Vector3 = g.global_position - feet()
		away.y = 0.0
		away = away.normalized() if away.length() > 0.1 else -layer.aim_dir()
		layer.hit({"id": from_id, "node": g, "pos": g.global_position, "center": g.global_position + Vector3(0, 0.8, 0),
			"vel": g.velocity(), "grounded": g.is_grounded(), "dummy": false}, away * 16.0 + Vector3(0, 9.0, 0), {"st": 0.4, "s": "balloon"})
	finish()
	return true


static func _pop_fx(parent: Node, at: Vector3) -> void:
	for i: int in 3:
		PartyFx.burst(parent, at + Vector3(-0.35 + 0.35 * float(i), 0, 0), COLORS[i], 24, 6.0, 0.22, 0.5)
	# confetti fluttering down, and scraps of balloon rubber flung out
	PartyFx.confetti(parent, at, 90, 9.0, Vector3.UP, 85.0, 2.0)
	# streamers: long curling ribbons of colour flung out and falling
	PartyFx.one_shot(parent, at, {"amount": 14, "lifetime": 1.6, "size": Vector2(0.06, 0.55), "color": Color.WHITE,
		"tex": "none", "additive": false, "shape": "sphere", "radius": 0.3, "vmin": 4.0, "vmax": 7.0, "damping": 3.0,
		"gravity": Vector3(0, -5, 0), "angle": true, "spin": 300.0, "flutter": true, "pick": COLORS, "turbulence": 1.2,
		"colors": [Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)]})
	HeroFx.ring(parent, at, Vector3.UP, Color(1.0, 0.85, 0.95, 0.7), 0.3, 2.8, 0.3, 0.05, true)
	PartyFx.one_shot(parent, at, {"amount": 18, "lifetime": 0.7, "size": Vector2(0.2, 0.14), "color": Color.WHITE,
		"tex": "none", "additive": false, "shape": "sphere", "radius": 0.4, "vmin": 4.0, "vmax": 8.0, "damping": 5.0,
		"gravity": Vector3(0, -10, 0), "angle": true, "spin": 600.0, "flutter": true, "pick": COLORS,
		"colors": [Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)]})
	PartyFx.ring_pulse(parent, at, Vector3.UP, Color(1.0, 0.8, 0.95), 0.4, 2.2, 0.3, 0.15)
	PartyFx.ring_pulse(parent, at, Vector3.FORWARD, Color(1.0, 0.8, 0.95), 0.4, 1.8, 0.25, 0.12)
	PartyFx.star_ring(parent, at, Color(1.0, 0.85, 0.3), 8, 5.0, 0.4)
	PartyFx.comic_burst(parent, at + Vector3(0, 0.9, 0), "POP!", Color(1.0, 0.5, 0.8), 0.9)


func remote(action: String, d: Dictionary) -> void:
	if action == "pop":
		_popped = true
		remote_fx(layer, owner_id, action, d)


## Ran out without being popped: the balloons slip their strings and float away.
func on_end() -> void:
	if _popped or not is_inside_tree():
		return
	var w: Node = world()
	for i: int in _balloons.size():
		var from: Vector3 = _skins[i].global_position
		var b := Node3D.new()
		w.add_child(b)
		b.global_position = from
		var mat: StandardMaterial3D = PartyFx.solid_mat(Color(COLORS[i].r, COLORS[i].g, COLORS[i].b, 0.9), 0.5, 0.15, 0.1)
		PartyFx.part(b, PartyFx.sphere_mesh(0.28, 18), mat, Vector3.ZERO, Vector3(0.8, 1.0, 0.8))
		PartyFx.part(b, PartyFx.cyl_mesh(0.008, 0.6), PartyFx.solid_mat(Color(0.95, 0.95, 0.95), 0.3), Vector3(0, -0.55, 0))
		var ph: float = float(i) * 2.1
		var drift := Vector3(randf_range(-1.2, 1.2), 0, randf_range(-1.2, 1.2))
		var tw: Tween = b.create_tween()
		tw.tween_method(func(k: float) -> void:
			if is_instance_valid(b):
				b.global_position = from + drift * k + Vector3(sin(k * 9.0 + ph) * 0.25, k * k * 7.0 + k * 1.5, 0)
				b.rotation.z = sin(k * 11.0 + ph) * 0.4
				b.scale = Vector3.ONE * (1.0 - 0.6 * k), 0.0, 1.0, 1.6)
		tw.tween_callback(func() -> void:
			if is_instance_valid(b) and b.is_inside_tree():
				PartyFx.burst(b.get_parent(), b.global_position, COLORS[i], 10, 2.5, 0.16, 0.35)
			b.queue_free())
	PartyFx.one_shot(w, global_position + Vector3(0, 1.8, 0), {"amount": 12, "lifetime": 1.0, "size": 0.14,
		"color": Color(1.0, 0.8, 0.95), "tex": "star", "dir": Vector3.UP, "spread": 30.0, "vmin": 1.0, "vmax": 2.5,
		"angle": true, "explosiveness": 0.6})


static func remote_fx(layer_ref: PartyLayer, _from_id: int, action: String, d: Dictionary) -> void:
	if action == "pop":
		_pop_fx(layer_ref, PowerUp.v3(d.get("at", [])))
		layer_ref.sfx.play_at("pop", PowerUp.v3(d.get("at", [])), 1.0)
