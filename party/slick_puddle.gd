class_name SlickPuddle
extends Node3D
## The Slick Puddle hazard: a glossy golden slick with a peel on top, dropped behind its owner.
## Every screen spawns it from the owner's "drop" event. Detection is victim-side: each client
## checks only its OWN Player against other people's puddles (and the owner's copy checks the
## practice dummies). The first racer to step in spins out, and the puddle is used up - the
## victim tells everyone ("hz"), so it vanishes on every screen.

const RADIUS: float = 1.35
const LIFE: float = 25.0

var layer: PartyLayer
var owner_id: int = 0
var key: String = ""
var used: bool = false
var _age: float = 0.0
var _slick: MeshInstance3D


func _ready() -> void:
	if layer != null and key != "":
		layer.hazards[key] = self
	var mat: StandardMaterial3D = PartyFx.solid_mat(Color(1.0, 0.86, 0.2, 0.85), 0.9, 0.05, 0.3)
	_slick = PartyFx.part(self, PartyFx.cyl_mesh(RADIUS, 0.03, -1.0, 28), mat, Vector3(0, 0.03, 0), Vector3(1.0, 1.0, 0.8))
	for i: int in 4:
		var a: float = TAU * float(i) / 4.0 + 0.4
		PartyFx.part(self, PartyFx.cyl_mesh(0.42, 0.03, -1.0, 16), mat, Vector3(cos(a) * 0.95, 0.025, sin(a) * 0.75))
	# the peel: three curled yellow petals around a little stem
	var peel: StandardMaterial3D = PartyFx.solid_mat(Color(1.0, 0.88, 0.25), 0.4, 0.5)
	for i: int in 3:
		var a: float = TAU * float(i) / 3.0
		PartyFx.part(self, PartyFx.sphere_mesh(0.18, 10), peel, Vector3(cos(a) * 0.2, 0.12, sin(a) * 0.2), Vector3(0.7, 0.35, 1.6), Vector3(0, -rad_to_deg(a), 25))
	PartyFx.part(self, PartyFx.cyl_mesh(0.05, 0.18), PartyFx.solid_mat(Color(0.45, 0.35, 0.12)), Vector3(0, 0.22, 0))
	# glints and slow bubbles
	add_child(PartyFx.emitter({"amount": 10, "lifetime": 0.9, "size": 0.16, "color": Color(1.0, 1.0, 0.8),
		"shape": "box", "extents": Vector3(RADIUS * 0.8, 0.02, RADIUS * 0.6), "vmin": 0.0, "vmax": 0.1, "spark": true,
		"shrink": false, "colors": [Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)], "aabb": 3.0}))
	add_child(PartyFx.emitter({"amount": 6, "lifetime": 1.2, "size": 0.12, "color": Color(1.0, 0.9, 0.4, 0.8),
		"shape": "box", "extents": Vector3(RADIUS * 0.7, 0.02, RADIUS * 0.5), "vmin": 0.2, "vmax": 0.5, "dir": Vector3.UP,
		"spread": 10.0, "additive": false, "aabb": 3.0}))
	scale = Vector3(0.1, 1.0, 0.1)
	create_tween().tween_property(self, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	PartyFx.one_shot(get_parent(), global_position + Vector3(0, 0.2, 0), {"amount": 30, "lifetime": 0.5, "size": 0.18,
		"color": Color(1.0, 0.85, 0.3), "dir": Vector3.UP, "spread": 60.0, "vmin": 2.0, "vmax": 4.5,
		"gravity": Vector3(0, -12, 0), "additive": false})


func _physics_process(dt: float) -> void:
	if used or layer == null:
		return
	_age += dt
	if _age > LIFE:
		consume(false, false)
		return
	if _age < 0.3:
		return
	var me: int = Net.my_id()
	if owner_id != me and layer.is_rival(owner_id) and layer.local_vulnerable() and _touches(layer.player.global_position):
		var p: Player = layer.player
		var fwd := Vector3(p.velocity.x, 0, p.velocity.z)
		fwd = fwd.normalized() if fwd.length() > 0.5 else Vector3(p.facing_dir.x, 0, p.facing_dir.z).normalized()
		layer.take_hazard(owner_id, fwd * 7.0 + Vector3(0, 6.5, 0), {"e": "spin", "ed": 1.3, "s": "slick"})
		consume(true)
		return
	if owner_id == me:
		for d: PracticeDummy in layer.dummies:
			if is_instance_valid(d) and not d.knocked_out and _touches(d.global_position):
				d.take_hit(Vector3(0, 6.5, 0), {"e": "stun", "st": 1.3, "s": "slick"})
				layer.hit_landed.emit(d.id, "slick")
				consume(true)
				return


func _touches(feet: Vector3) -> bool:
	var d: Vector3 = feet - global_position
	return absf(d.y) < 0.9 and Vector2(d.x, d.z / 0.8).length() < RADIUS


## Used up (stepped in) or expired. `tell` = we used it: let everyone else remove it too.
func consume(tell: bool, splash: bool = true) -> void:
	if used:
		return
	used = true
	if layer != null and layer.hazards.get(key) == self:
		layer.hazards.erase(key)
	if tell and layer != null:
		Net.send_party({"k": "hz", "h": key})
	if splash and is_inside_tree():
		var at: Vector3 = global_position + Vector3(0, 0.3, 0)
		PartyFx.one_shot(get_parent(), at, {"amount": 36, "lifetime": 0.6, "size": 0.22, "color": Color(1.0, 0.85, 0.25),
			"dir": Vector3.UP, "spread": 70.0, "vmin": 3.0, "vmax": 7.0, "gravity": Vector3(0, -14, 0), "additive": false})
		PartyFx.sparks(get_parent(), at, Color(1.0, 1.0, 0.7), 16, 6.0)
		if layer != null:
			layer.sfx.play_at("pop", at, 0.9, 0.7)
	var tw: Tween = create_tween()
	tw.tween_property(self, "scale", Vector3(0.01, 1.0, 0.01), 0.25)
	tw.tween_callback(queue_free)
