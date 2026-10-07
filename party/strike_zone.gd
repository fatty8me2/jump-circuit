class_name StrikeZone
extends Node3D
## The Leader Strike's danger zone. Every screen builds one from the caster's "tell" event: a red
## reticle on the ground under the racer in front (it follows them for most of the wind-up), a
## pillar of red light and a storm gathering overhead, a siren and a tightening pulse. Then the
## reticle locks - and TELL seconds after the call the sky falls in.
## Hits are decided victim-side, like the Slick Puddle: when it lands each client checks only
## its OWN Player against the locked spot (so a racer who ran clear is safe, and a bystander
## standing next to the leader is not). The caster's copy also hits practice dummies.

## Seconds from the call to the impact: a long, readable tell.
const TELL: float = 2.7
## The zone stops following its target this long before the impact.
const LOCK: float = 0.8
const RADIUS: float = 3.6
const RED := Color(1.0, 0.25, 0.2)

var layer: PartyLayer
var owner_id: int = 0
var key: String = ""
var target_id: int = 0
var seed_value: int = 0
var age: float = 0.0
var locked: bool = false
var impacted: bool = false
## Where the impact fell (set when it lands; tests read it).
var impact_at: Vector3 = Vector3.INF

var _outer: MeshInstance3D
var _inner: MeshInstance3D
var _cross: Node3D
var _disc_mat: StandardMaterial3D
var _col_mat: StandardMaterial3D
var _ring_mat: StandardMaterial3D
var _mark: Label3D
var _light: OmniLight3D
var _pulse_t: float = 0.0


func _ready() -> void:
	if layer != null and key != "":
		layer.hazards[key] = self
	_ring_mat = PartyFx.fading_mat(Color(RED.r, RED.g, RED.b, 0.9), 2.4)
	_disc_mat = PartyFx.fading_mat(Color(RED.r, RED.g, RED.b, 0.08), 1.6)
	_col_mat = PartyFx.fading_mat(Color(RED.r, RED.g, RED.b, 0.04), 1.8)
	_outer = _ring(RADIUS, 0.12)
	_inner = _ring(RADIUS * 0.55, 0.08)
	_cross = Node3D.new()
	add_child(_cross)
	for i: int in 2:
		PartyFx.part(_cross, PartyFx.box_mesh(Vector3(RADIUS * 2.1, 0.03, 0.09)), _ring_mat, Vector3(0, 0.05, 0), Vector3.ONE, Vector3(0, 90.0 * float(i), 0))
	PartyFx.part(self, PartyFx.cyl_mesh(RADIUS, 0.02, -1.0, 40), _disc_mat, Vector3(0, 0.04, 0))
	# the pillar of light the strike will ride down
	PartyFx.part(self, PartyFx.cyl_mesh(RADIUS * 0.8, 70.0, -1.0, 20), _col_mat, Vector3(0, 35.0, 0))
	_mark = Label3D.new()
	_mark.text = "!"
	_mark.font_size = 220
	_mark.outline_size = 36
	_mark.modulate = Color(1.0, 0.35, 0.25)
	_mark.outline_modulate = Color(0.25, 0.02, 0.0)
	_mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_mark.no_depth_test = true
	_mark.pixel_size = 0.006
	_mark.layers = PartyFx.LAYER
	_mark.position = Vector3(0, 3.6, 0)
	add_child(_mark)
	if PartyFx.lights_on():
		_light = OmniLight3D.new()
		_light.light_color = RED
		_light.light_energy = 0.0
		_light.omni_range = RADIUS * 3.0
		_light.shadow_enabled = false
		_light.position = Vector3(0, 1.5, 0)
		add_child(_light)
	# the storm gathering high overhead, rumbling red, while the siren winds up
	PartyFx.storm_cloud(layer, global_position + Vector3(0, 20.0, 0), 5.0, TELL, seed_value + 3)
	PartyFx.one_shot(layer, global_position, {"amount": 26, "lifetime": 0.8, "size": 0.16, "color": Color(1.5, 0.5, 0.35),
		"shape": "ring", "radius": RADIUS, "inner": RADIUS * 0.85, "axis": Vector3.UP, "dir": Vector3.UP, "spread": 6.0,
		"vmin": 2.0, "vmax": 4.0, "spark": true, "explosiveness": 0.5})
	if layer != null:
		layer.sfx.play_at("siren", global_position, 1.0, 0.6)
	scale = Vector3(0.2, 1.0, 0.2)
	create_tween().tween_property(self, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _ring(radius: float, thick: float) -> MeshInstance3D:
	var tm := TorusMesh.new()
	tm.inner_radius = radius - thick
	tm.outer_radius = radius + thick
	tm.rings = 40
	tm.ring_segments = 6
	return PartyFx.part(self, tm, _ring_mat, Vector3(0, 0.06, 0), Vector3(1, 0.25, 1))


## Ground under a point (the zone sits on the floor, not on the racer's chest).
func _ground_under(c: Vector3) -> Vector3:
	var g: Dictionary = layer.ground_at(c - Vector3(0, 0.6, 0), 8.0)
	if g.is_empty():
		return c - Vector3(0, 0.8, 0)
	return g["position"]


func _physics_process(dt: float) -> void:
	if impacted or layer == null:
		return
	age += dt
	var left: float = TELL - age
	# follow the target until the lock
	if left > LOCK:
		var c: Variant = layer.target_center(target_id)
		if c != null:
			var want: Vector3 = _ground_under(c as Vector3)
			global_position = global_position.lerp(want, 1.0 - exp(-9.0 * dt))
	elif not locked:
		locked = true
		PartyFx.ring_pulse(layer, global_position + Vector3(0, 0.1, 0), Vector3.UP, Color(1.0, 0.9, 0.7), RADIUS * 1.6, RADIUS, 0.25, 0.15)
		PartyFx.star_ring(layer, global_position + Vector3(0, 0.3, 0), Color(1.0, 0.8, 0.5), 8, 4.0, 0.35)
		layer.sfx.play_at("clank", global_position, 0.7, 1.6)
	# the reticle spins faster and the glow climbs as it nears
	var k: float = clampf(age / TELL, 0.0, 1.0)
	_outer.rotation.y += dt * (0.8 + 5.0 * k)
	_inner.rotation.y -= dt * (1.4 + 7.0 * k)
	_cross.rotation.y += dt * (0.5 + 3.0 * k)
	var beat: float = 0.5 + 0.5 * sin(age * (8.0 + 22.0 * k))
	var hot: Color = Color(1.0, 0.95, 0.8) if locked else RED
	_ring_mat.albedo_color = Color(hot.r * 2.4, hot.g * 2.4, hot.b * 2.4, 0.55 + 0.4 * beat)
	_disc_mat.albedo_color = Color(RED.r * 1.6, RED.g * 1.6, RED.b * 1.6, 0.05 + 0.2 * k * (0.6 + 0.4 * beat))
	_col_mat.albedo_color = Color(RED.r * 1.8, RED.g * 1.8, RED.b * 1.8, 0.02 + 0.13 * k * k)
	if _light != null:
		_light.light_energy = (0.6 + 2.8 * k) * (0.6 + 0.4 * beat)
	_mark.scale = Vector3.ONE * (1.0 + 0.2 * beat)
	# contracting pulse rings, faster and faster
	_pulse_t -= dt
	if _pulse_t <= 0.0:
		_pulse_t = lerpf(0.55, 0.14, k)
		PartyFx.ring_pulse(layer, global_position + Vector3(0, 0.08, 0), Vector3.UP, Color(1.0, 0.35, 0.25), RADIUS * 1.5, RADIUS * 0.3, 0.4, 0.07)
		if PartyFx.rich():
			PartyFx.sparks(layer, global_position + Vector3(0, 0.2, 0), Color(1.4, 0.6, 0.4), 6, 5.0, Vector3.UP, 40.0)
	if age >= TELL:
		_impact()


## The sky falls in.
func _impact() -> void:
	impacted = true
	impact_at = global_position
	if layer != null and layer.hazards.get(key) == self:
		layer.hazards.erase(key)
	var at: Vector3 = global_position
	impact_fx(layer, at, seed_value)
	layer.sfx.play_at("strike", at, 1.0, 1.0)
	var me: Player = layer.player
	var dist: float = me.global_position.distance_to(at) if me != null else 99.0
	PartyFx.shake(layer.level, clampf(1.0 - dist / 40.0, 0.15, 0.95))
	# victim side: our own Player against the locked spot
	if me != null and owner_id != Net.my_id() and layer.is_rival(owner_id) and layer.local_vulnerable():
		var d: Vector3 = me.global_position - at
		if Vector2(d.x, d.z).length() <= RADIUS and absf(d.y) < 4.5:
			var away := Vector3(d.x, 0, d.z)
			away = away.normalized() if away.length() > 0.2 else Vector3(1, 0, 0).rotated(Vector3.UP, float(seed_value % 628) / 100.0)
			layer.take_hazard(owner_id, away * 9.0 + Vector3(0, 14.0, 0), {"st": 1.6, "e": "stun", "ed": 1.6, "s": "strike", "feed": true})
	# the caster's copy: practice dummies in the blast
	if owner_id == Net.my_id():
		for t: Dictionary in layer.targets():
			if not bool(t.get("dummy", false)):
				continue
			var dd: Vector3 = (t["pos"] as Vector3) - at
			if Vector2(dd.x, dd.z).length() <= RADIUS and absf(dd.y) < 4.5:
				var out := Vector3(dd.x, 0, dd.z)
				out = out.normalized() if out.length() > 0.2 else Vector3(1, 0, 0)
				layer.hit(t, out * 9.0 + Vector3(0, 14.0, 0), {"st": 1.6, "s": "strike", "quiet": true})
	_mark.visible = false
	for c: Node in get_children():
		if c is MeshInstance3D:
			(c as MeshInstance3D).visible = false
	if _light != null:
		_light.visible = false
	get_tree().create_timer(0.3, false).timeout.connect(queue_free)


## A white-hot column from the sky, a fireball, a ring of fire and a rain of rubble.
static func impact_fx(parent: Node, at: Vector3, seed_value: int) -> void:
	var top: Vector3 = at + Vector3(0, 90.0, 0)
	var floor_at: Vector3 = at + Vector3(0, 0.05, 0)
	PartyFx.beam(parent, top, at, Color(1.0, 0.97, 0.9, 1.0), 0.9, 0.35, 5.0)
	PartyFx.beam(parent, top, at, Color(1.0, 0.35, 0.2, 0.4), 2.4, 0.5, 1.8)
	PartyFx.forked_bolt(parent, top, at, Color(1.0, 0.7, 0.55), seed_value + 11, 0.4, 4)
	PartyFx.forked_bolt(parent, top + Vector3(3, 0, 2), at, Color(1.0, 0.45, 0.3), seed_value + 12, 0.3, 3)
	PartyFx.explosion(parent, at + Vector3(0, 0.6, 0), Color(1.0, 0.9, 0.7), Color(1.0, 0.3, 0.1), RADIUS * 1.5)
	PartyFx.shockwave(parent, floor_at, Color(1.0, 0.45, 0.25), RADIUS * 2.6, 0.55)
	PartyFx.shockwave(parent, floor_at, Color(1.0, 0.85, 0.6), RADIUS * 1.6, 0.35)
	PartyFx.ring_pulse(parent, floor_at + Vector3(0, 0.1, 0), Vector3.UP, Color(1.0, 0.5, 0.3), 0.5, RADIUS * 3.2, 0.5, 0.25)
	PartyFx.scorch(parent, floor_at, RADIUS * 0.9, 5.0, Color(1.0, 0.45, 0.2))
	PartyFx.ground_cracks(parent, floor_at, RADIUS * 1.3, Color(2.6, 1.0, 0.3), 9, 3.0, seed_value + 5)
	PartyFx.burning_debris(parent, floor_at + Vector3(0, 0.3, 0), 9, 10.0, Color(2.4, 0.9, 0.2), Color(0.22, 0.18, 0.2), 0.8, true)
	PartyFx.debris(parent, floor_at + Vector3(0, 0.3, 0), Color(0.5, 0.42, 0.35), 14, 8.0, 0.2)
	PartyFx.fire_mushroom(parent, floor_at, 7.0, 2.2)
	PartyFx.dust_wall(parent, floor_at, RADIUS * 1.2)
	PartyFx.star_ring(parent, at + Vector3(0, 0.8, 0), Color(1.0, 0.8, 0.4), 10, 8.0, 0.45)
	PartyFx.flash(parent, at + Vector3(0, 2.5, 0), Color(1.0, 0.7, 0.5), 12.0, 18.0, 0.6)
	PartyFx.comic_burst(parent, at + Vector3(0, 3.4, 0), "STRIKE!", Color(1.0, 0.35, 0.2), 1.3)
	if PartyFx.rich():
		PartyFx.embers(parent, at + Vector3(0, 0.5, 0), RADIUS * 0.8, Color(2.6, 1.0, 0.3), 36, 2.0, 2.0)
		PartyFx.lightning_shell(parent, at + Vector3(0, 1.0, 0), RADIUS * 0.7, Color(1.4, 0.8, 0.6), 4, 0.15)
