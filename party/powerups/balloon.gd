extends PowerUp
## Balloon Shield (15 s or one hit): three balloons bob over your shoulders. The next hit (or
## hazard) that would land on you pops them in a shower of confetti instead - and the attacker
## gets their own knockback bounced straight back at them.

const COLORS: Array[Color] = [Color(1.0, 0.45, 0.7), Color(0.4, 0.8, 1.0), Color(1.0, 0.9, 0.3)]

var _balloons: Array[Node3D] = []
var _bubble: MeshInstance3D
var _t: float = 0.0


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
		PartyFx.part(piv, PartyFx.sphere_mesh(0.28, 18), mat, Vector3(0, 1.05 + 0.12 * float(i % 2), 0), Vector3(0.9, 1.1, 0.9))
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
	if is_inside_tree():
		PartyFx.burst(world(), global_position + Vector3(0, 1.6, 0), Color(1.0, 0.7, 0.9), 30, 4.0, 0.25)


func begin() -> void:
	layer.sfx.play("pop", 0.7, 1.6)


func _process(dt: float) -> void:
	_t += dt
	for piv: Node3D in _balloons:
		var ph: float = float(piv.get_meta("phase"))
		piv.rotation = Vector3(sin(_t * 1.7 + ph) * 0.12, 0, sin(_t * 1.3 + ph) * 0.15)
	if _bubble != null:
		var k: float = 1.0 + sin(_t * 4.0) * 0.03
		_bubble.scale = Vector3(k, 1.15 * k, k)


func absorb_hit(from_id: int) -> bool:
	if ended:
		return false
	var at: Vector3 = chest() + Vector3(0, 1.0, 0)
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
	# confetti: flat spinning scraps in every colour, drifting down
	PartyFx.one_shot(parent, at, {"amount": 70, "lifetime": 1.6, "size": 0.14, "color": Color(1, 1, 1),
		"vmin": 3.0, "vmax": 8.0, "dir": Vector3.UP, "spread": 80.0, "gravity": Vector3(0, -6, 0), "damping": 3.0,
		"additive": false, "angle": true, "shrink": false, "explosiveness": 1.0,
		"initial": [Color(1, 0.4, 0.6), Color(0.4, 0.8, 1), Color(1, 0.9, 0.3), Color(0.5, 1, 0.5), Color(0.9, 0.5, 1)],
		"colors": [Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)]})
	PartyFx.ring_pulse(parent, at, Vector3.UP, Color(1.0, 0.8, 0.95), 0.4, 2.2, 0.3, 0.15)
	PartyFx.popup_text(parent, at + Vector3(0, 0.6, 0), "POP!", Color(1.0, 0.6, 0.85), 100)


func remote(action: String, d: Dictionary) -> void:
	if action == "pop":
		remote_fx(layer, owner_id, action, d)


static func remote_fx(layer_ref: PartyLayer, _from_id: int, action: String, d: Dictionary) -> void:
	if action == "pop":
		_pop_fx(layer_ref, PowerUp.v3(d.get("at", [])))
		layer_ref.sfx.play_at("pop", PowerUp.v3(d.get("at", [])), 1.0)
