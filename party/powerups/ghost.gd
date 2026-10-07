extends PowerUp
## Ghost (6 s): you fade to a pale, see-through spirit trailing wisps of mist. Nothing can touch
## you while it lasts - shoves, shells, strikes, puddles, fake boxes, a Swap Warp all pass straight
## through (PartyLayer.local_vulnerable is false; a fall still counts). And you can reach into
## a rival: float into one and you steal the item they are holding. Only one steal per ghost, and
## a rival with a Balloon Shield or respawn protection cannot be robbed.

const PALE := Color(0.75, 0.9, 1.0)
const SOUL := Color(0.55, 0.7, 1.0)
## A rival this close (to their chest) gets robbed.
const TOUCH: float = 2.4
## Seconds between steal attempts (a refusal or an empty-handed rival).
const RETRY: float = 0.9
const FADE: float = 0.62

var _t: float = 0.0
var _faded: Dictionary = {}
var _steal_cd: float = 0.0
var _wisp_t: float = 0.0
var _aura: MeshInstance3D


func _init() -> void:
	duration = 6.0


func build_look() -> void:
	# see-through: every part of the model fades (remembered, so it comes back exactly as it was)
	var root: Node = get_parent()
	if root != null:
		_fade_tree(root)
	_aura = PartyFx.part(self, PartyFx.sphere_mesh(0.85, 20), PartyFx.fading_mat(Color(0.6, 0.8, 1.0, 0.1), 1.5), Vector3(0, 0.75, 0), Vector3(1, 1.2, 1))
	# mist rising off the body, a cold glow in the heart and drifting soul-lights
	add_child(PartyFx.emitter({"amount": 30, "lifetime": 1.2, "size": 0.55, "color": Color(0.8, 0.9, 1.0, 0.4), "additive": false,
		"tex": "smoke", "shape": "sphere", "radius": 0.35, "offset": Vector3(0, 0.7, 0), "dir": Vector3.UP, "spread": 25.0,
		"vmin": 0.2, "vmax": 0.8, "grow": true, "angle": true, "aabb": 6.0, "turbulence": 0.5,
		"colors": [Color(1, 1, 1, 0), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0)]}))
	add_child(PartyFx.emitter({"amount": 16, "lifetime": 1.3, "size": 0.14, "color": Color(0.8, 1.4, 2.0), "spark": true,
		"shape": "sphere", "radius": 0.5, "offset": Vector3(0, 0.8, 0), "vmin": 0.1, "vmax": 0.6, "dir": Vector3.UP, "spread": 60.0,
		"aabb": 6.0, "colors": [Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)]}))
	# a trailing ectoplasm tail streaming out behind
	add_child(PartyFx.emitter({"amount": 26, "lifetime": 0.7, "size": Vector2(0.1, 0.6), "color": Color(0.7, 0.85, 1.4, 0.6),
		"tex": "streak", "facing": "velocity", "shape": "box", "extents": Vector3(0.2, 0.4, 0.1), "offset": Vector3(0, 0.7, 0.3),
		"dir": Vector3(0, 0, 1), "spread": 8.0, "vmin": 0.5, "vmax": 1.5, "aabb": 8.0, "fixed_fps": 0}))
	if is_inside_tree():
		_vanish_fx(world(), global_position + Vector3(0, 0.8, 0))
		if not local and layer != null:
			layer.sfx.play_at("ghost", global_position, 0.8, 1.0)


## Poof: the body turns to mist - a pale ring and sparkles, a puff of fog, a rising wisp.
static func _vanish_fx(parent: Node, at: Vector3) -> void:
	PartyFx.implode(parent, at, PALE, 1.8)
	PartyFx.ring_pulse(parent, at - Vector3(0, 0.6, 0), Vector3.UP, PALE, 0.2, 2.4, 0.45, 0.12)
	PartyFx.burst(parent, at, SOUL, 30, 4.5, 0.22, 0.7)
	PartyFx.star_ring(parent, at, Color(0.8, 0.95, 1.0), 8, 4.0, 0.35)
	PartyFx.smoke(parent, at, Color(0.85, 0.92, 1.0, 0.5), 14, 0.5, 1.2)
	PartyFx.one_shot(parent, at, {"amount": 12, "lifetime": 1.4, "size": 0.9, "color": Color(0.85, 0.92, 1.0, 0.45), "additive": false,
		"tex": "smoke", "dir": Vector3.UP, "spread": 20.0, "vmin": 1.0, "vmax": 2.2, "grow": true, "angle": true, "aabb": 8.0,
		"colors": [Color(1, 1, 1, 0), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0)]})
	PartyFx.flash(parent, at, SOUL, 4.0, 6.0, 0.4)


func _fade_tree(n: Node) -> void:
	if n == self:
		return
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if not _faded.has(mi):
			_faded[mi] = mi.transparency
		mi.transparency = maxf(mi.transparency, FADE)
	for c: Node in n.get_children():
		_fade_tree(c)


func _restore_tree() -> void:
	for mi: Variant in _faded:
		if is_instance_valid(mi):
			(mi as MeshInstance3D).transparency = float(_faded[mi])
	_faded.clear()


func begin() -> void:
	layer.sfx.play("ghost", 1.0, 1.0)
	PartyFx.shake(layer.level, 0.15)
	layer.hud.announce("GHOST!  Touch a rival to steal", PartyNames.item_color("ghost"))


func hud_status() -> String:
	return "Intangible"


func _process(dt: float) -> void:
	_t += dt
	var left: float = time_left - (0.0 if local else 1.0)
	# running out: it flickers solid for a moment before the body comes back
	var solid: bool = not PartyFx.blink_on(left, 1.2)
	if _aura != null:
		var m: StandardMaterial3D = _aura.material_override as StandardMaterial3D
		m.albedo_color.a = 0.05 if solid else 0.1 + 0.05 * sin(_t * 6.0)
		_aura.scale = Vector3(1, 1.2, 1) * (1.0 + 0.05 * sin(_t * 4.0))
	for mi: Variant in _faded:
		if is_instance_valid(mi):
			(mi as MeshInstance3D).transparency = 0.15 if solid else FADE


func remote(action: String, d: Dictionary) -> void:
	remote_fx(layer, owner_id, action, d)


func tick(dt: float) -> void:
	_steal_cd -= dt
	_wisp_t -= dt
	if _wisp_t <= 0.0 and is_inside_tree():
		_wisp_t = 0.25
		PartyFx.smoke(world(), feet() + Vector3(0, 0.3, 0), Color(0.8, 0.9, 1.0, 0.3), 3, 0.3, 0.8)
	if _steal_cd > 0.0 or layer.item != "" or layer.steal_pending():
		return
	var me: Vector3 = chest()
	var best: Dictionary = {}
	var best_d: float = TOUCH
	for t: Dictionary in layer.targets():
		var dd: float = (t["center"] as Vector3).distance_to(me)
		if dd < best_d:
			best_d = dd
			best = t
	if best.is_empty():
		return
	_steal_cd = RETRY
	layer.try_steal(best)


func on_end() -> void:
	_restore_tree()
	if is_inside_tree():
		# the body comes back with a soft pop
		var at: Vector3 = global_position + Vector3(0, 0.8, 0)
		PartyFx.burst(world(), at, SOUL, 20, 4.0, 0.2, 0.4)
		PartyFx.ring_pulse(world(), at - Vector3(0, 0.6, 0), Vector3.UP, PALE, 0.4, 1.8, 0.3, 0.1)
		PartyFx.smoke(world(), at, Color(0.85, 0.92, 1.0, 0.4), 8, 0.4, 0.8)


func _exit_tree() -> void:
	_restore_tree()


## The robbery, drawn on every screen: a pale hand of mist reaches from the thief to the victim,
## snatches a glowing item orb out of them and carries it back.
static func steal_fx(parent: Node, from_pos: Vector3, to_pos: Vector3) -> void:
	PartyFx.comet(parent, to_pos, from_pos, Color(0.7, 0.9, 1.4), 1.6, 0.45, 0.3)
	PartyFx.streak(parent, to_pos, from_pos, PALE, 40, 0.14, 0.7, 0.3, 1.0, true)
	PartyFx.tether(parent, from_pos, to_pos, Color(0.7, 0.9, 1.4), 10, 9.0)
	PartyFx.burst(parent, to_pos, Color(1.0, 0.95, 0.7), 26, 6.0, 0.24, 0.5)
	PartyFx.star_ring(parent, to_pos, Color(1.0, 0.9, 0.5), 8, 5.0, 0.4)
	PartyFx.ring_pulse(parent, to_pos, Vector3.UP, PALE, 0.3, 2.0, 0.3, 0.12)
	PartyFx.comic_burst(parent, to_pos + Vector3(0, 1.0, 0), "MINE!", Color(0.6, 0.85, 1.0), 0.9)
	PartyFx.flash(parent, to_pos, SOUL, 5.0, 6.0, 0.3)


static func remote_fx(layer_ref: PartyLayer, from_id: int, action: String, d: Dictionary) -> void:
	if action == "steal":
		var g: RemoteRacer = layer_ref.ghost(from_id)
		var a: Vector3 = g.global_position + Vector3(0, 0.8, 0) if g != null else PowerUp.v3(d.get("b", []))
		var b: Vector3 = PowerUp.v3(d.get("b", []))
		steal_fx(layer_ref, a, b)
		layer_ref.sfx.play_at("steal", b, 1.0, 1.0)
