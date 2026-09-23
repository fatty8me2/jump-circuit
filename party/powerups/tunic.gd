extends PowerUp
## Hero's Tunic: a green tunic and long pointed cap, a shield on the back and the Legend Blade.
## Speed x1.15, jump x1.1.
##  Attack (tap): Legend Blade - a three-swing combo (the third is a big overhead chop).
##  Attack (hold): the blade gathers light; release for a Spin Attack that throws everyone around.
##  Use: the current tool. Cycle: next tool.
##    Boomerang - curves out and back, stunning everyone it passes through.
##    Hookshot  - fires a chain: yanks a rival to you, or pulls you to the wall / floor it bites.
##    Bombs     - a lobbed bomb with a fizzing fuse; big blast knockback.

const GREEN := Color(0.18, 0.6, 0.2)
const BLADE := Color(0.65, 0.88, 1.0)
const GOLD := Color(1.0, 0.82, 0.25)
const TOOLS: Array[String] = ["boomerang", "hookshot", "bombs"]
const SPIN_CHARGE: float = 0.75
const SLASH_CD: float = 0.26
const TOOL_CD: float = 0.75
const HOOK_RANGE: float = 20.0

var tool: int = 0
var _combo: int = 0
var _combo_t: float = 0.0
var _slash_cd: float = 0.0
var _tool_cd: float = 0.0
var _charge: float = -1.0
var _sword: Node3D
var _charge_fx: GPUParticles3D
var _blade_mat: StandardMaterial3D
var _hook_to: Vector3 = Vector3.ZERO
var _hook_t: float = 0.0
var _chain: MeshInstance3D
var _t: float = 0.0


func _init() -> void:
	duration = 10.0
	takes_attack = true


func mods() -> Vector3:
	return Vector3(1.15, 1.1, 1.0)


func build_look() -> void:
	var green: StandardMaterial3D = PartyFx.solid_mat(GREEN, 0.25, 0.7)
	var dark: StandardMaterial3D = PartyFx.solid_mat(Color(0.1, 0.36, 0.12), 0.1, 0.7)
	var leather: StandardMaterial3D = PartyFx.solid_mat(Color(0.42, 0.26, 0.12), 0.0, 0.8)
	var gold: StandardMaterial3D = PartyFx.solid_mat(GOLD, 0.9, 0.3, 0.8)
	# tunic: a flared skirt over the lower shell, belt and buckle
	PartyFx.part(self, PartyFx.cyl_mesh(0.47, 0.44, 0.36, 20), green, Vector3(0, 0.42, 0))
	PartyFx.part(self, PartyFx.cyl_mesh(0.52, 0.08, 0.48, 20), dark, Vector3(0, 0.2, 0))
	var belt := TorusMesh.new()
	belt.inner_radius = 0.36
	belt.outer_radius = 0.43
	belt.rings = 24
	belt.ring_segments = 8
	PartyFx.part(self, belt, leather, Vector3(0, 0.55, 0), Vector3(1, 0.8, 1))
	PartyFx.part(self, PartyFx.box_mesh(Vector3(0.14, 0.11, 0.05)), gold, Vector3(0, 0.55, -0.42))
	# cap: a band and a long cone drooping back
	PartyFx.part(self, PartyFx.cyl_mesh(0.34, 0.12, 0.32, 20), green, Vector3(0, 0.98, 0.02))
	var cap_pivot := Node3D.new()
	cap_pivot.position = Vector3(0, 1.03, 0.06)
	cap_pivot.rotation_degrees = Vector3(62, 0, 0)
	cap_pivot.name = "Cap"
	add_child(cap_pivot)
	PartyFx.part(cap_pivot, PartyFx.cone_mesh(0.3, 0.95, 16), green, Vector3(0, 0.44, 0))
	# shield on the back: blue face, silver rim, a golden three-triangle crest
	var shield := Node3D.new()
	shield.position = Vector3(0, 0.66, 0.43)
	add_child(shield)
	PartyFx.part(shield, PartyFx.cyl_mesh(0.3, 0.06, -1.0, 24), PartyFx.solid_mat(Color(0.75, 0.78, 0.85), 0.1, 0.3, 0.9), Vector3.ZERO, Vector3(1, 1, 1.25), Vector3(90, 0, 0))
	PartyFx.part(shield, PartyFx.cyl_mesh(0.25, 0.07, -1.0, 24), PartyFx.solid_mat(Color(0.12, 0.2, 0.62), 0.2, 0.4), Vector3(0, 0, 0.01), Vector3(1, 1, 1.25), Vector3(90, 0, 0))
	var tri := PrismMesh.new()
	tri.size = Vector3(0.12, 0.1, 0.02)
	for off: Vector3 in [Vector3(0, 0.07, 0.045), Vector3(-0.06, -0.03, 0.045), Vector3(0.06, -0.03, 0.045)]:
		PartyFx.part(shield, tri, PartyFx.glow_mat(GOLD, 2.0), off)
	# the Legend Blade, held in the right hand
	_sword = Node3D.new()
	_sword.position = Vector3(0.42, 0.55, -0.1)
	_sword.rotation_degrees = Vector3(-70, 0, -12)
	_sword.name = "Sword"
	add_child(_sword)
	_blade_mat = PartyFx.fading_mat(BLADE, 1.6)
	_blade_mat.albedo_color.a = 1.0
	PartyFx.part(_sword, PartyFx.box_mesh(Vector3(0.07, 0.86, 0.022)), _blade_mat, Vector3(0, 0.55, 0))
	PartyFx.part(_sword, PartyFx.cone_mesh(0.05, 0.1, 4), _blade_mat, Vector3(0, 1.03, 0), Vector3(1, 1, 0.3))
	PartyFx.part(_sword, PartyFx.box_mesh(Vector3(0.3, 0.05, 0.07)), PartyFx.solid_mat(Color(0.35, 0.2, 0.7), 0.6, 0.3, 0.6), Vector3(0, 0.1, 0))
	PartyFx.part(_sword, PartyFx.cyl_mesh(0.03, 0.18), PartyFx.solid_mat(Color(0.3, 0.18, 0.5)), Vector3(0, 0.0, 0))
	var glint: GPUParticles3D = PartyFx.emitter({"amount": 10, "lifetime": 0.5, "size": 0.08, "color": BLADE,
		"shape": "box", "extents": Vector3(0.02, 0.42, 0.01), "vmin": 0.0, "vmax": 0.15, "spark": true, "aabb": 3.0})
	glint.position = Vector3(0, 0.55, 0)
	_sword.add_child(glint)
	_charge_fx = PartyFx.emitter({"amount": 40, "lifetime": 0.35, "size": 0.14, "color": Color(0.8, 0.95, 1.0),
		"shape": "shell", "radius": 0.9, "vmin": 0.0, "vmax": 0.1, "radial": -12.0, "spark": true, "local": true,
		"emitting": false, "aabb": 3.0})
	_charge_fx.position = Vector3(0, 1.0, 0)
	_sword.add_child(_charge_fx)
	# a slow swirl of green leaves and golden motes around the hero
	var leaves: GPUParticles3D = PartyFx.emitter({"amount": 14, "lifetime": 1.4, "size": 0.12, "color": Color(0.5, 1.0, 0.45),
		"shape": "ring", "radius": 0.75, "inner": 0.6, "height": 0.8, "vmin": 0.2, "vmax": 0.5, "dir": Vector3.UP,
		"spread": 25.0, "tangential": 2.0, "aabb": 3.0})
	leaves.position = Vector3(0, 0.5, 0)
	add_child(leaves)
	if is_inside_tree():
		var at: Vector3 = global_position
		PartyFx.burst(world(), at + Vector3(0, 0.8, 0), Color(0.45, 1.0, 0.4), 50, 7.0, 0.3, 0.7)
		PartyFx.one_shot(world(), at + Vector3(0, 0.3, 0), {"amount": 40, "lifetime": 1.0, "size": 0.18, "color": GOLD,
			"shape": "ring", "radius": 1.2, "inner": 1.0, "vmin": 3.0, "vmax": 5.0, "dir": Vector3.UP, "spread": 10.0,
			"tangential": 6.0, "spark": true, "explosiveness": 0.6})
		PartyFx.shockwave(world(), at, Color(0.4, 1.0, 0.5), 3.0)
		PartyFx.flash(world(), at + Vector3(0, 1, 0), Color(0.6, 1.0, 0.6), 7.0, 8.0, 0.5)


func begin() -> void:
	layer.sfx.play("chime", 1.0, 1.0)
	PartyFx.shake(layer.level, 0.25)


func _process(dt: float) -> void:
	_t += dt
	var cap: Node3D = get_node_or_null("Cap") as Node3D
	if cap != null:
		cap.rotation_degrees.z = sin(_t * 3.0) * 6.0
	if _charge >= 0.0 and _blade_mat != null:
		var k: float = charge_frac()
		_blade_mat.albedo_color = Color(BLADE.r, BLADE.g, BLADE.b, 1.0).lerp(Color(3.0, 3.0, 3.2, 1.0), k * (0.7 + 0.3 * sin(_t * 30.0)))
	if _chain != null and is_instance_valid(_chain):
		var hand: Vector3 = _sword.global_position
		_chain.global_transform = PartyFx.beam_transform(hand, _hook_to, 0.05)


func tick(dt: float) -> void:
	_slash_cd = maxf(_slash_cd - dt, 0.0)
	_tool_cd = maxf(_tool_cd - dt, 0.0)
	_combo_t = maxf(_combo_t - dt, 0.0)
	if _hook_t > 0.0:
		_hook_t -= dt
		var p: Player = player()
		var to: Vector3 = _hook_to - p.global_position - Vector3(0, 0.6, 0)
		if to.length() < 1.3 or _hook_t <= 0.0 or p.party_stun > 0.0:
			_end_hook(true)
		else:
			p.velocity = to.normalized() * 26.0
			p.add_impulse(Vector3(0, 0.001, 0))


func charge_frac() -> float:
	return clampf(_charge / SPIN_CHARGE, 0.0, 1.0) if _charge >= 0.0 else -1.0


func hud_status() -> String:
	if _charge >= 0.0:
		return "%s  %d%%" % [PartyNames.move_name("spin"), int(charge_frac() * 100.0)]
	return "%s  %s  -  %s next" % [Game.prompt("use_item"), PartyNames.move_name(TOOLS[tool]), Game.prompt("cycle_item")]


# ---- Legend Blade ---------------------------------------------------------------------------

func on_attack_hold(held: float) -> void:
	if held < hold_threshold:
		return
	if _charge < 0.0:
		_charge = 0.0
		_charge_fx.emitting = true
		layer.sfx.play("charge", 0.6, 1.4)
		fx("charge", {"on": true})
	var was: bool = _charge >= SPIN_CHARGE
	_charge += 1.0 / Engine.physics_ticks_per_second
	if not was and _charge >= SPIN_CHARGE:
		# fully charged: a ping and a flash on the blade
		layer.sfx.play("chime", 0.8, 1.6)
		PartyFx.burst(world(), _sword.global_position + _sword.global_basis.y * 1.0, Color(0.9, 1.0, 1.0), 20, 4.0, 0.15)


func on_attack_release(held: float) -> void:
	if _charge >= 0.0:
		var full: bool = _charge >= SPIN_CHARGE * 0.5
		_charge = -1.0
		_charge_fx.emitting = false
		_blade_mat.albedo_color = Color(BLADE.r, BLADE.g, BLADE.b, 1.0) * 1.6
		_blade_mat.albedo_color.a = 1.0
		if held >= 0.0 and full:
			_spin()
		else:
			fx("charge", {"on": false})
		return
	if held >= 0.0 and held < hold_threshold:
		_slash()


func _slash() -> void:
	if _slash_cd > 0.0:
		return
	_slash_cd = SLASH_CD
	_combo = (_combo + 1) % 3 if _combo_t > 0.0 else 0
	_combo_t = 0.7
	var p: Player = player()
	var dir: Vector3 = layer.melee_dir(3.5)
	p.facing_dir = dir
	var hv := Vector3(p.velocity.x, 0, p.velocity.z)
	if hv.dot(dir) < 6.0:
		p.add_impulse(dir * (6.0 - maxf(hv.dot(dir), 0.0)))
	var o: Vector3 = chest()
	_slash_fx(layer, o, dir, _combo)
	_swing_anim(_combo)
	layer.sfx.play("slash", 0.9, 1.0 + 0.12 * _combo)
	fx("slash", {"o": arr(o), "d": arr(dir), "c": _combo})
	var big: bool = _combo == 2
	for t: Dictionary in layer.targets_in_cone(o, dir, 3.4 if big else 2.9, 0.25):
		layer.hit(t, dir * (17.0 if big else 11.0) + Vector3(0, 8.0 if big else 5.0, 0), {"st": 0.45 if big else 0.25, "s": "blade"})


static func _slash_fx(parent: Node, o: Vector3, dir: Vector3, combo: int) -> void:
	var b := Basis.looking_at(dir, Vector3.UP)
	var col := Color(0.7, 0.92, 1.0)
	match combo:
		0:
			PartyFx.arc(parent, o, Basis(dir, deg_to_rad(-12.0)) * b, 1.5, 1.2, -1.2, col, 0.3, 0.2)
		1:
			PartyFx.arc(parent, o, Basis(dir, deg_to_rad(15.0)) * b, 1.5, -1.2, 1.2, col, 0.3, 0.2)
		_:
			PartyFx.arc(parent, o + Vector3(0, 0.2, 0), Basis(dir, deg_to_rad(90.0)) * b, 1.8, -1.4, 1.3, Color(0.85, 1.0, 1.0), 0.45, 0.28)
			PartyFx.shockwave(parent, o + dir * 1.6 - Vector3(0, 0.7, 0), Color(0.6, 0.9, 1.0), 1.6, 0.3)
	PartyFx.one_shot(parent, o + dir * 1.1, {"amount": 22, "lifetime": 0.3, "size": 0.12, "color": col,
		"dir": dir, "spread": 50.0, "vmin": 4.0, "vmax": 9.0, "damping": 10.0, "spark": true})


func _swing_anim(combo: int) -> void:
	var tw: Tween = _sword.create_tween()
	var rest := Vector3(-70, 0, -12)
	match combo:
		0:
			_sword.rotation_degrees = Vector3(-90, 80, -12)
			tw.tween_property(_sword, "rotation_degrees", Vector3(-90, -90, -12), 0.1)
		1:
			_sword.rotation_degrees = Vector3(-90, -90, 10)
			tw.tween_property(_sword, "rotation_degrees", Vector3(-90, 80, 10), 0.1)
		_:
			_sword.rotation_degrees = Vector3(40, 0, 0)
			tw.tween_property(_sword, "rotation_degrees", Vector3(-150, 0, 0), 0.13)
	tw.tween_property(_sword, "rotation_degrees", rest, 0.18)


func _spin() -> void:
	var o: Vector3 = chest()
	_spin_fx(layer, o)
	var tw: Tween = _sword.create_tween()
	_sword.rotation_degrees = Vector3(-90, 0, -12)
	tw.tween_property(self, "rotation:y", rotation.y + TAU, 0.3)
	tw.tween_property(_sword, "rotation_degrees", Vector3(-70, 0, -12), 0.15)
	layer.sfx.play("whoosh", 1.0, 0.8)
	layer.sfx.play("slash", 0.9, 0.7)
	PartyFx.shake(layer.level, 0.35)
	fx("spin", {"o": arr(o)})
	for t: Dictionary in layer.targets_in_sphere(o, 3.6):
		var away: Vector3 = (t["center"] as Vector3) - o
		away.y = 0.0
		away = away.normalized() if away.length() > 0.1 else layer.aim_dir()
		layer.hit(t, away * 19.0 + Vector3(0, 9.0, 0), {"st": 0.6, "s": "spin"})


static func _spin_fx(parent: Node, o: Vector3) -> void:
	var col := Color(0.75, 0.95, 1.0)
	for i: int in 4:
		var a0: float = float(i) * PI * 0.5
		PartyFx.arc(parent, o, Basis(Vector3.UP, 0.0), 2.3, a0, a0 + PI * 0.6, col, 0.4, 0.35)
	PartyFx.shockwave(parent, o - Vector3(0, 0.7, 0), col, 4.0, 0.4)
	PartyFx.one_shot(parent, o, {"amount": 70, "lifetime": 0.5, "size": 0.16, "color": col, "shape": "ring",
		"radius": 1.5, "inner": 1.2, "vmin": 6.0, "vmax": 11.0, "dir": Vector3(1, 0, 0), "spread": 180.0, "flat": 1.0,
		"tangential": 30.0, "damping": 12.0, "spark": true})
	PartyFx.flash(parent, o, col, 6.0, 8.0, 0.35)


# ---- tools ----------------------------------------------------------------------------------

func on_cycle() -> void:
	tool = (tool + 1) % TOOLS.size()
	layer.sfx.play("clank", 0.6, 1.5)
	layer.hud.announce(PartyNames.move_name(TOOLS[tool]), Color(0.55, 1.0, 0.5))
	PartyFx.burst(world(), chest(), Color(0.5, 1.0, 0.5), 12, 3.0, 0.15, 0.35)


func on_use() -> bool:
	if _tool_cd > 0.0:
		return true
	_tool_cd = TOOL_CD
	match TOOLS[tool]:
		"boomerang":
			_throw_boomerang()
		"hookshot":
			_fire_hook()
		"bombs":
			_throw_bomb()
	return true


func _throw_boomerang() -> void:
	var o: Vector3 = chest() + Vector3(0, 0.1, 0)
	var dir: Vector3 = layer.aim_dir()
	var tg: Dictionary = layer.nearest_in_cone(o, dir, 13.0, 0.8)
	if not tg.is_empty():
		var to: Vector3 = (tg["center"] as Vector3) - o
		to.y = 0.0
		dir = to.normalized()
	var key: String = layer.new_key()
	_spawn_boomerang(layer, key, o, dir, true)
	fx("boomerang", {"k": key, "o": arr(o), "d": arr(dir)})
	layer.sfx.play("whoosh", 0.8, 1.4)


static func _spawn_boomerang(layer_ref: PartyLayer, key: String, o: Vector3, dir: Vector3, is_local: bool) -> PartyProjectile:
	var pr := PartyProjectile.new()
	pr.layer = layer_ref
	pr.local = is_local
	pr.key = key
	pr.life = 1.1
	pr.radius = 1.0
	pr.hit_world = false
	var side: Vector3 = dir.cross(Vector3.UP).normalized()
	# straight out along the aim, then a wide curving loop back to the thrower's spot
	pr.path = func(t: float) -> Vector3:
		var k: float = clampf(t / 1.1, 0.0, 1.0)
		var loop: float = sin(TAU * (k - 0.5)) if k > 0.5 else 0.0
		return o + dir * 12.0 * sin(PI * k) + side * 2.4 * loop
	var spinner := Node3D.new()
	pr.add_child(spinner)
	var wood: StandardMaterial3D = PartyFx.solid_mat(Color(0.8, 0.55, 0.25), 0.5)
	PartyFx.part(spinner, PartyFx.box_mesh(Vector3(0.5, 0.05, 0.12)), wood, Vector3(0.2, 0, 0), Vector3.ONE, Vector3(0, 30, 0))
	PartyFx.part(spinner, PartyFx.box_mesh(Vector3(0.5, 0.05, 0.12)), wood, Vector3(-0.2, 0, 0), Vector3.ONE, Vector3(0, -30, 0))
	PartyFx.part(spinner, PartyFx.sphere_mesh(0.07), PartyFx.glow_mat(Color(0.3, 0.7, 1.0), 3.0), Vector3(0, 0.03, -0.12))
	var tw: Tween = spinner.create_tween().set_loops()
	tw.tween_property(spinner, "rotation:y", -TAU, 0.18).from(0.0)
	pr.add_child(PartyFx.emitter({"amount": 30, "lifetime": 0.3, "size": 0.2, "color": Color(1.0, 0.85, 0.5),
		"vmin": 0.0, "vmax": 0.3, "aabb": 20.0, "colors": [Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)]}))
	pr.on_target = func(t: Dictionary, pos: Vector3) -> bool:
		var away: Vector3 = (t["center"] as Vector3) - pos
		away.y = 0.0
		layer_ref.hit(t, away.normalized() * 4.0 + Vector3(0, 4.0, 0), {"st": 1.1, "e": "stun", "ed": 1.1, "s": "boomerang"})
		return false
	layer_ref.add_child(pr)
	return pr


func _fire_hook() -> void:
	var o: Vector3 = _sword.global_position if _sword != null else chest()
	var dir: Vector3 = layer.aim_dir()
	var tg: Dictionary = layer.nearest_in_cone(chest(), dir, HOOK_RANGE, 0.9)
	if not tg.is_empty():
		var c: Vector3 = tg["center"]
		var blocked: Dictionary = layer.ray(o, c)
		if blocked.is_empty():
			# yank the rival to us
			var pull: Vector3 = chest() - c
			var flat := Vector3(pull.x, 0, pull.z)
			layer.hit(tg, flat.normalized() * minf(8.0 + flat.length() * 1.1, 26.0) + Vector3(0, 7.0, 0), {"st": 0.5, "s": "hookshot"})
			_hook_fx(layer, o, c, true)
			fx("hook", {"o": arr(o), "t": arr(c), "y": true})
			layer.sfx.play("clank", 1.0, 0.8)
			return
	# no rival in the sights: bite into the course (aimed a little upward) and reel in
	var aim: Vector3 = (dir + Vector3(0, 0.18, 0)).normalized()
	var hit: Dictionary = layer.ray(chest(), chest() + aim * HOOK_RANGE)
	if hit.is_empty():
		_hook_fx(layer, o, chest() + aim * HOOK_RANGE, false)
		fx("hook", {"o": arr(o), "t": arr(chest() + aim * HOOK_RANGE), "y": false})
		layer.sfx.play("clank", 0.5, 1.6)
		return
	_hook_to = hit["position"]
	_hook_t = 1.0
	_chain = PartyFx.part(world() as Node3D, PartyFx.cyl_mesh(1.0, 1.0, -1.0, 6), PartyFx.glow_mat(Color(0.8, 0.8, 0.9), 1.5), Vector3.ZERO)
	_chain.global_transform = PartyFx.beam_transform(o, _hook_to, 0.05)
	PartyFx.sparks(world(), _hook_to, Color(1.0, 0.9, 0.6), 18, 6.0, hit["normal"] as Vector3, 70.0)
	layer.sfx.play("clank", 1.0, 1.0)
	fx("hook", {"o": arr(o), "t": arr(_hook_to), "y": false})


func _end_hook(pop: bool) -> void:
	_hook_t = 0.0
	if _chain != null and is_instance_valid(_chain):
		_chain.queue_free()
	_chain = null
	if pop and is_inside_tree():
		var p: Player = player()
		p.add_impulse(Vector3(0, 5.0, 0))


static func _hook_fx(parent: Node, o: Vector3, to: Vector3, yank: bool) -> void:
	PartyFx.beam(parent, o, to, Color(0.85, 0.85, 0.95), 0.05, 0.4, 2.0)
	PartyFx.streak(parent, o, to, Color(1.0, 0.9, 0.6), 30, 0.12, 0.35, 0.05, 0.6, true)
	PartyFx.sparks(parent, to, Color(1.0, 0.85, 0.5), 20 if yank else 12, 6.0)


func _throw_bomb() -> void:
	var o: Vector3 = chest() + Vector3(0, 0.3, 0)
	var dir: Vector3 = layer.aim_dir()
	var tg: Dictionary = layer.nearest_in_cone(o, dir, 16.0, 0.85)
	var dist: float = 9.0
	if not tg.is_empty():
		var to: Vector3 = (tg["center"] as Vector3) - o
		dist = clampf(Vector3(to.x, 0, to.z).length(), 2.0, 16.0)
		dir = Vector3(to.x, 0, to.z).normalized()
	# flight time ~0.75 s for any range: horizontal speed from the distance
	var v: Vector3 = dir * (dist / 0.75) + Vector3(0, 6.0, 0)
	var key: String = layer.new_key()
	_spawn_bomb(layer, key, o, v, true)
	fx("bomb", {"k": key, "o": arr(o), "v": arr(v)})
	layer.sfx.play("whoosh", 0.7, 0.9)


static func _spawn_bomb(layer_ref: PartyLayer, key: String, o: Vector3, v: Vector3, is_local: bool) -> PartyProjectile:
	var pr := PartyProjectile.new()
	pr.layer = layer_ref
	pr.local = is_local
	pr.key = key
	pr.origin = o
	pr.velocity = v
	pr.gravity = 22.0
	pr.life = 1.6
	pr.radius = 0.6
	PartyFx.part(pr, PartyFx.sphere_mesh(0.26, 16), PartyFx.solid_mat(Color(0.12, 0.16, 0.45), 0.2, 0.3, 0.3), Vector3.ZERO)
	PartyFx.part(pr, PartyFx.cyl_mesh(0.07, 0.1), PartyFx.solid_mat(Color(0.5, 0.5, 0.55)), Vector3(0, 0.27, 0))
	var fuse: GPUParticles3D = PartyFx.emitter({"amount": 26, "lifetime": 0.3, "size": 0.1, "color": Color(1.0, 0.75, 0.3),
		"vmin": 1.5, "vmax": 3.5, "dir": Vector3.UP, "spread": 60.0, "gravity": Vector3(0, -6, 0), "spark": true, "aabb": 20.0})
	fuse.position = Vector3(0, 0.34, 0)
	pr.add_child(fuse)
	var boom := func(pos: Vector3) -> void: _bomb_boom(layer_ref, key, pos, true)
	pr.on_world = func(pos: Vector3, n: Vector3) -> void: boom.call(pos + n * 0.3)
	pr.on_expire = boom
	pr.on_target = func(_t: Dictionary, pos: Vector3) -> bool:
		boom.call(pos)
		return true
	layer_ref.add_child(pr)
	return pr


static func _bomb_boom(layer_ref: PartyLayer, key: String, pos: Vector3, is_local: bool) -> void:
	PartyFx.explosion(layer_ref, pos, Color(1.0, 0.55, 0.15), Color(1.0, 0.85, 0.35), 3.2)
	layer_ref.sfx.play_at("boom", pos, 1.0, 1.1)
	var me: Vector3 = layer_ref.player.global_position
	PartyFx.shake(layer_ref.level, clampf(1.0 - me.distance_to(pos) / 14.0, 0.0, 0.6))
	if not is_local:
		return
	layer_ref.send_fx("tunic", "boom", {"k": key, "pos": PowerUp.arr(pos)})
	for t: Dictionary in layer_ref.targets_in_sphere(pos, 3.4):
		var away: Vector3 = (t["center"] as Vector3) - pos
		away.y = 0.0
		away = away.normalized() if away.length() > 0.1 else Vector3.FORWARD
		layer_ref.hit(t, away * 15.0 + Vector3(0, 9.0, 0), {"st": 0.4, "s": "bombs", "quiet": true})


# ---- the mirror on a rival's ghost ----------------------------------------------------------

func remote(action: String, d: Dictionary) -> void:
	match action:
		"slash":
			var c: int = int(d.get("c", 0))
			_slash_fx(layer, v3(d.get("o", [])), v3(d.get("d", [])), c)
			_swing_anim(c)
			layer.sfx.play_at("slash", v3(d.get("o", [])), 0.8)
		"spin":
			_spin_fx(layer, v3(d.get("o", [])))
			create_tween().tween_property(self, "rotation:y", rotation.y + TAU, 0.3)
			layer.sfx.play_at("whoosh", v3(d.get("o", [])), 0.9, 0.8)
		"charge":
			if _charge_fx != null:
				_charge_fx.emitting = bool(d.get("on", false))
		_:
			remote_fx(layer, owner_id, action, d)


## Replays tool actions even after the tunic mirror is gone.
static func remote_fx(layer_ref: PartyLayer, _from_id: int, action: String, d: Dictionary) -> void:
	match action:
		"boomerang":
			_spawn_boomerang(layer_ref, str(d.get("k", "")), PowerUp.v3(d.get("o", [])), PowerUp.v3(d.get("d", [])), false)
			layer_ref.sfx.play_at("whoosh", PowerUp.v3(d.get("o", [])), 0.8, 1.4)
		"hook":
			_hook_fx(layer_ref, PowerUp.v3(d.get("o", [])), PowerUp.v3(d.get("t", [])), bool(d.get("y", false)))
			layer_ref.sfx.play_at("clank", PowerUp.v3(d.get("o", [])), 0.8)
		"bomb":
			_spawn_bomb(layer_ref, str(d.get("k", "")), PowerUp.v3(d.get("o", [])), PowerUp.v3(d.get("v", [])), false)
		"boom":
			var pr: Variant = layer_ref.projectiles.get(str(d.get("k", "")), null)
			var pos: Vector3 = PowerUp.v3(d.get("pos", []))
			if pr != null and is_instance_valid(pr):
				(pr as PartyProjectile).stop(pos)
			_bomb_boom(layer_ref, str(d.get("k", "")), pos, false)


func on_end() -> void:
	_end_hook(false)
	if is_inside_tree():
		PartyFx.burst(world(), global_position + Vector3(0, 0.8, 0), Color(0.45, 1.0, 0.4), 30, 5.0, 0.25)
