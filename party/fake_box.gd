class_name FakeBox
extends Node3D
## The Fake Box hazard: an item box that is not. It is the real ItemBox model (same spin, same
## sparkle), set down in a rival's path. A rival who grabs it gets a face full of confetti-flavoured
## explosion: thrown up and stunned. To its owner and their teammates it wears a tiny red mark, so
## they never run into it themselves.
## Like the Slick Puddle, detection is victim-side (each client checks only its OWN Player against
## other people's fakes; the owner's copy checks the practice dummies) and the victim tells
## everyone ("hz") so the fake vanishes on every screen. A racer with respawn protection, or a
## Ghost, passes straight through it and it stays put; a Balloon Shield pops instead of the stun.

const RADIUS: float = 1.0
const LIFE: float = 45.0
const STUN: float = 1.7

var layer: PartyLayer
var owner_id: int = 0
var key: String = ""
var used: bool = false
var _age: float = 0.0
var _box: ItemBox
var _mark: Node3D


func _ready() -> void:
	if layer != null and key != "":
		layer.hazards[key] = self
	_box = ItemBox.new()
	_box.index = int(Time.get_ticks_msec() % 7)
	add_child(_box)
	_box.position = Vector3(0, 1.15, 0)
	# the owner's side knows better: a small red tell on the ground and over the box
	if layer != null and not layer.is_rival(owner_id):
		_mark = Node3D.new()
		add_child(_mark)
		var m: StandardMaterial3D = PartyFx.glow_mat(Color(1.0, 0.25, 0.2, 0.7), 2.0, true)
		var tm := TorusMesh.new()
		tm.inner_radius = RADIUS * 0.8
		tm.outer_radius = RADIUS * 0.9
		tm.rings = 30
		tm.ring_segments = 4
		PartyFx.part(_mark, tm, m, Vector3(0, 0.08, 0), Vector3(1, 0.3, 1))
		var l := Label3D.new()
		l.text = "FAKE"
		l.font_size = 80
		l.outline_size = 16
		l.modulate = Color(1.0, 0.4, 0.3)
		l.outline_modulate = Color(0.2, 0.03, 0.0)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.pixel_size = 0.004
		l.layers = PartyFx.LAYER
		l.position = Vector3(0, 2.3, 0)
		add_child(l)
	# it drops in with a thump: a squash, a ring and a puff, exactly like a real box being set down
	var tw: Tween = create_tween()
	scale = Vector3(1.3, 0.1, 1.3)
	tw.tween_property(self, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	if is_inside_tree():
		PartyFx.ring_pulse(get_parent(), global_position + Vector3(0, 0.1, 0), Vector3.UP, Color(1.0, 0.9, 0.5), 0.3, 1.8, 0.3, 0.1)
		PartyFx.smoke(get_parent(), global_position + Vector3(0, 0.2, 0), Color(0.9, 0.88, 0.8, 0.5), 8, 0.5, 0.7)
		PartyFx.sparks(get_parent(), global_position + Vector3(0, 1.0, 0), Color(1.0, 0.9, 0.5), 10, 4.0)


func center() -> Vector3:
	return global_position + Vector3(0, 1.15, 0)


func _physics_process(dt: float) -> void:
	if used or layer == null:
		return
	_age += dt
	if _age > LIFE:
		consume(false, false)
		return
	visible = PartyFx.blink_on(LIFE - _age, 2.0)
	if _age < 0.4:
		return
	var me: int = Net.my_id()
	if owner_id != me and layer.is_rival(owner_id) and layer.local_vulnerable() and _touches(layer.player.global_position + Vector3(0, 0.8, 0)):
		var p: Player = layer.player
		var fwd := Vector3(p.velocity.x, 0, p.velocity.z)
		fwd = fwd.normalized() if fwd.length() > 0.5 else Vector3(p.facing_dir.x, 0, p.facing_dir.z).normalized()
		layer.take_hazard(owner_id, -fwd * 4.0 + Vector3(0, 11.0, 0), {"st": STUN, "e": "stun", "ed": STUN, "s": "fakebox", "feed": true})
		consume(true)
		return
	if owner_id == me:
		for d: PracticeDummy in layer.dummies:
			if is_instance_valid(d) and not d.knocked_out and _touches(d.center()):
				d.take_hit(Vector3(0, 11.0, 0), {"st": STUN, "e": "stun", "s": "fakebox"})
				layer.hit_landed.emit(d.id, "fakebox")
				consume(true)
				return


func _touches(c: Vector3) -> bool:
	return c.distance_to(center()) < RADIUS


## Used up (somebody grabbed it) or expired. `tell` = we saw it go off: let everyone else remove it too.
func consume(tell: bool, splash: bool = true) -> void:
	if used:
		return
	used = true
	if layer != null and layer.hazards.get(key) == self:
		layer.hazards.erase(key)
	if tell and layer != null:
		Net.send_party({"k": "hz", "h": key})
	visible = true
	if splash and is_inside_tree():
		go_off_fx(get_parent(), center())
		if layer != null:
			layer.sfx.play_at("fake", center(), 1.0, 1.0)
	elif is_inside_tree():
		PartyFx.smoke(get_parent(), center(), Color(0.9, 0.88, 0.8, 0.4), 8, 0.6, 0.9)
	if _box != null and is_instance_valid(_box):
		_box.visible = false
	var tw: Tween = create_tween()
	tw.tween_interval(0.35)
	tw.tween_callback(queue_free)


## The box was a lie: a cheerful pop that turns into a proper explosion, with a rude "GOTCHA!".
static func go_off_fx(parent: Node, at: Vector3) -> void:
	PartyFx.orb_pulse(parent, at, Color(1.0, 0.95, 0.7, 0.8), 0.2, 1.4, 0.15, 3.0)
	PartyFx.explosion(parent, at, Color(1.0, 0.9, 0.5), Color(1.0, 0.25, 0.15), 2.8)
	PartyFx.shockwave(parent, at - Vector3(0, 1.0, 0), Color(1.0, 0.6, 0.3), 3.4)
	PartyFx.confetti(parent, at, 70, 8.0, Vector3.UP, 80.0, 1.8)
	PartyFx.star_ring(parent, at, Color(1.0, 0.85, 0.3), 9, 6.0, 0.42)
	PartyFx.sparks(parent, at, Color(1.0, 0.8, 0.4), 26, 9.0)
	PartyFx.shards(parent, at, Color(1.0, 0.85, 0.5), 12, 7.0, 0.16)
	PartyFx.smoke(parent, at - Vector3(0, 0.5, 0), Color(0.25, 0.22, 0.22, 0.6), 12, 0.7, 1.1)
	PartyFx.flash(parent, at, Color(1.0, 0.7, 0.4), 6.0, 8.0, 0.3)
	PartyFx.comic_burst(parent, at + Vector3(0, 1.3, 0), "GOTCHA!", Color(1.0, 0.45, 0.25), 1.0)
