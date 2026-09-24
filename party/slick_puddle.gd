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
## Cosmetic: where the glob was flung from (INF = none).
var thrown_from: Vector3 = Vector3.INF
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
	# glossy ripples spreading over the surface now and then
	var rip: GPUParticles3D = PartyFx.emitter({"amount": 3, "lifetime": 1.7, "size": 1.0, "color": Color(1.0, 0.97, 0.75, 0.6),
		"tex": "ring", "facing": "flat", "additive": false, "shape": "box", "extents": Vector3(RADIUS * 0.4, 0.0, RADIUS * 0.3),
		"vmin": 0.0, "vmax": 0.0, "scale_min": 0.8, "scale_max": 1.6, "grow": true, "aabb": 3.0,
		"colors": [Color(1, 1, 1, 0), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0)]})
	rip.position = Vector3(0, 0.06, 0)
	add_child(rip)
	# a sheen: a soft highlight drifting across the slick
	var sheen: MeshInstance3D = PartyFx.part(self, PartyFx.sphere_mesh(0.5, 12), PartyFx.glow_mat(Color(1, 1, 0.9, 0.22), 1.4, true),
		Vector3(0, 0.05, 0), Vector3(1.0, 0.02, 0.35))
	sheen.name = "Sheen"
	var st: Tween = sheen.create_tween().set_loops()
	st.tween_property(sheen, "position:x", RADIUS * 0.55, 1.4).from(-RADIUS * 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	st.tween_property(sheen, "position:x", -RADIUS * 0.55, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	scale = Vector3(0.1, 1.0, 0.1)
	var delay: float = 0.0
	if thrown_from.is_finite() and thrown_from.distance_to(global_position) > 0.3:
		delay = 0.16
		_fling_glob(thrown_from, global_position, delay)
	var tw: Tween = create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
		tw.tween_callback(_splat_fx)
	else:
		_splat_fx.call_deferred()
	tw.tween_property(self, "scale", Vector3(1.15, 1.0, 1.15), 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## A glob of golden goo arcing from the thrower to the spot.
func _fling_glob(from: Vector3, to: Vector3, time: float) -> void:
	var w: Node = get_parent()
	var glob := Node3D.new()
	w.add_child(glob)
	glob.global_position = from
	PartyFx.part(glob, PartyFx.sphere_mesh(0.22, 12), PartyFx.solid_mat(Color(1.0, 0.86, 0.2), 0.8, 0.05, 0.3), Vector3.ZERO, Vector3(1, 0.8, 1.2))
	glob.add_child(PartyFx.emitter({"amount": 16, "lifetime": 0.25, "size": 0.12, "color": Color(1.0, 0.85, 0.3),
		"additive": false, "vmin": 0.0, "vmax": 0.5, "gravity": Vector3(0, -6, 0), "fixed_fps": 0, "aabb": 8.0}))
	var mid: Vector3 = (from + to) * 0.5 + Vector3(0, 0.9, 0)
	var tw: Tween = glob.create_tween()
	tw.tween_method(func(k: float) -> void:
		if is_instance_valid(glob):
			glob.global_position = from.lerp(mid, k).lerp(mid.lerp(to, k), k), 0.0, 1.0, time)
	tw.tween_callback(glob.queue_free)


## The slick lands: goo droplets thrown out and a splat ring.
func _splat_fx() -> void:
	if not is_inside_tree() or used:
		return
	PartyFx.one_shot(get_parent(), global_position + Vector3(0, 0.2, 0), {"amount": 30, "lifetime": 0.5, "size": 0.18,
		"color": Color(1.0, 0.85, 0.3), "dir": Vector3.UP, "spread": 60.0, "vmin": 2.0, "vmax": 4.5,
		"gravity": Vector3(0, -12, 0), "additive": false})
	PartyFx.ring_pulse(get_parent(), global_position + Vector3(0, 0.08, 0), Vector3.UP, Color(1.0, 0.9, 0.4), 0.4, RADIUS * 1.5, 0.35, 0.12)


func _physics_process(dt: float) -> void:
	if used or layer == null:
		return
	_age += dt
	if _age > LIFE:
		consume(false, false)
		return
	# drying up: it blinks through its last two seconds
	visible = PartyFx.blink_on(LIFE - _age, 2.0)
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
	visible = true
	if splash and is_inside_tree():
		var at: Vector3 = global_position + Vector3(0, 0.3, 0)
		var w: Node = get_parent()
		PartyFx.one_shot(w, at, {"amount": 44, "lifetime": 0.7, "size": 0.24, "color": Color(1.0, 0.85, 0.25),
			"dir": Vector3.UP, "spread": 70.0, "vmin": 3.0, "vmax": 8.0, "gravity": Vector3(0, -14, 0), "additive": false})
		PartyFx.sparks(w, at, Color(1.0, 1.0, 0.7), 16, 6.0)
		PartyFx.ring_pulse(w, global_position + Vector3(0, 0.08, 0), Vector3.UP, Color(1.0, 0.9, 0.4), 0.5, RADIUS * 2.2, 0.4, 0.12)
		PartyFx.star_ring(w, at + Vector3(0, 0.6, 0), Color(1.0, 0.9, 0.3), 7, 4.0, 0.36)
		PartyFx.comic_burst(w, at + Vector3(0, 1.6, 0), "SLIP!", Color(1.0, 0.85, 0.2), 0.8)
		# a sheet of slick sprays up and splats back down in blobs, leaving a skid streak
		HeroFx.pop(w, {"amount": 16, "lifetime": 0.8, "shape": "sphere", "radius": 0.3, "dir": Vector3.UP, "spread": 55.0,
			"speed": Vector2(3.0, 6.5), "gravity": Vector3(0, -16, 0), "size": 0.32, "curve": "shrink", "additive": false,
			"color": Color(1.1, 0.9, 0.3, 0.9)}, at)
		HeroFx.ring(w, global_position + Vector3(0, 0.06, 0), Vector3.UP, Color(1.2, 1.0, 0.45, 0.7), 0.4, RADIUS * 2.8, 0.5, 0.05, true)
		if layer != null:
			layer.sfx.play_at("pop", at, 0.9, 0.7)
	elif is_inside_tree():
		# dried up: a last wisp of steam
		PartyFx.smoke(get_parent(), global_position + Vector3(0, 0.2, 0), Color(1.0, 0.95, 0.8, 0.4), 8, 0.8, 1.0)
	var tw: Tween = create_tween()
	tw.tween_property(self, "scale", Vector3(0.01, 1.0, 0.01), 0.25)
	tw.tween_callback(queue_free)
