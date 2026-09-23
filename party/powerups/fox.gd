extends PowerUp
## Nine-Tailed Fox: an orange chakra cloak with fox ears, glowing red eyes and nine flowing
## tails. Speed x1.6, jump x1.35.
##  Attack (tap): Fox Claw - a lunging three-streak swipe that KOs the rival it connects with.
##  Attack (hold): charge a Tailed Beast Bomb (a dark sphere swirling in front of the mouth),
##  release to fire it - a huge explosion that throws everyone in its radius.

const CLOAK := Color(1.0, 0.45, 0.06)
const DARK := Color(0.28, 0.05, 0.4)
const CLAW_COOLDOWN: float = 0.45
const CHARGE_TIME: float = 1.2
const BOMB_SPEED: float = 28.0

var _tails: Array[Node3D] = []
var _t: float = 0.0
var _claw_cd: float = 0.0
var _charge: float = -1.0
var _ball: Node3D
var _ball_core: MeshInstance3D
var _hum: AudioStreamPlayer3D


func _init() -> void:
	duration = 10.0
	takes_attack = true


func mods() -> Vector3:
	return Vector3(1.6, 1.35, 1.0)


func build_look() -> void:
	# chakra cloak: a translucent glowing shell plus rising flames
	PartyFx.part(self, PartyFx.sphere_mesh(0.62, 20), PartyFx.glow_mat(Color(CLOAK.r, CLOAK.g, CLOAK.b, 0.28), 1.6, true), Vector3(0, 0.64, 0), Vector3(1.0, 1.12, 1.0))
	var flames: GPUParticles3D = PartyFx.emitter({"amount": 42, "lifetime": 0.55, "size": 0.34, "color": CLOAK,
		"shape": "sphere", "radius": 0.45, "dir": Vector3.UP, "spread": 25.0, "vmin": 1.2, "vmax": 2.8,
		"colors": [Color(1.0, 0.9, 0.5, 0.9), Color(1.0, 0.45, 0.05, 0.8), Color(0.8, 0.1, 0.0, 0.0)], "aabb": 3.0})
	flames.position = Vector3(0, 0.6, 0)
	add_child(flames)
	var embers: GPUParticles3D = PartyFx.emitter({"amount": 16, "lifetime": 0.9, "size": 0.09, "color": Color(1.0, 0.7, 0.2),
		"shape": "sphere", "radius": 0.5, "dir": Vector3.UP, "spread": 40.0, "vmin": 1.5, "vmax": 3.5, "spark": true,
		"gravity": Vector3(0, 1.0, 0), "aabb": 3.0})
	embers.position = Vector3(0, 0.5, 0)
	add_child(embers)
	# ears
	var fur: StandardMaterial3D = PartyFx.solid_mat(Color(1.0, 0.5, 0.1), 1.2)
	var inner: StandardMaterial3D = PartyFx.solid_mat(Color(0.35, 0.08, 0.02), 0.4)
	for sx: float in [-1.0, 1.0]:
		PartyFx.part(self, PartyFx.cone_mesh(0.12, 0.34, 8), fur, Vector3(sx * 0.2, 1.12, 0.04), Vector3(1, 1, 0.6), Vector3(0, 0, -sx * 22.0))
		PartyFx.part(self, PartyFx.cone_mesh(0.07, 0.22, 8), inner, Vector3(sx * 0.2, 1.1, -0.0), Vector3(1, 1, 0.4), Vector3(0, 0, -sx * 22.0))
	# red slit eyes, glowing through the visor
	var eye: StandardMaterial3D = PartyFx.glow_mat(Color(1.0, 0.08, 0.05), 4.0)
	for sx: float in [-0.11, 0.11]:
		PartyFx.part(self, PartyFx.sphere_mesh(0.06), eye, Vector3(sx, 0.76, -0.4), Vector3(1.0, 0.55, 0.6))
	# nine tails: chains of glowing beads fanned out behind, each with a ribbon of particles at its tip
	var bead: StandardMaterial3D = PartyFx.glow_mat(Color(1.0, 0.5, 0.08, 0.75), 1.8, true)
	for i: int in 9:
		var pivot := Node3D.new()
		pivot.position = Vector3(0, 0.42, 0.34)
		var fan: float = lerpf(-70.0, 70.0, float(i) / 8.0)
		pivot.rotation_degrees = Vector3(-35.0 - absf(fan) * 0.25, 0, fan)
		add_child(pivot)
		for j: int in 6:
			var r: float = 0.13 - float(j) * 0.014
			var seg: MeshInstance3D = PartyFx.part(pivot, PartyFx.sphere_mesh(r, 10), bead, Vector3(0, 0, 0.14 * float(j + 1)))
			seg.name = "S%d" % j
		var tip: GPUParticles3D = PartyFx.emitter({"amount": 18, "lifetime": 0.35, "size": 0.16, "color": CLOAK,
			"vmin": 0.0, "vmax": 0.3, "aabb": 4.0,
			"colors": [Color(1.0, 0.8, 0.4, 0.9), Color(1.0, 0.3, 0.0, 0.0)]})
		tip.position = Vector3(0, 0, 0.9)
		tip.name = "Tip"
		pivot.add_child(tip)
		pivot.set_meta("phase", float(i) * 0.7)
		_tails.append(pivot)
	# transformation burst
	var at: Vector3 = global_position if is_inside_tree() else Vector3.ZERO
	if is_inside_tree():
		PartyFx.burst(world(), at + Vector3(0, 0.8, 0), CLOAK, 60, 9.0, 0.4, 0.7)
		PartyFx.shockwave(world(), at, CLOAK, 3.5)
		PartyFx.flash(world(), at + Vector3(0, 1, 0), CLOAK, 8.0, 8.0, 0.5)


func _process(dt: float) -> void:
	_t += dt
	# tails sway: each bead offset by a travelling sine wave, so they flow like ribbons
	for pivot: Node3D in _tails:
		var ph: float = float(pivot.get_meta("phase"))
		for j: int in 6:
			var seg: Node3D = pivot.get_node("S%d" % j) as Node3D
			var k: float = float(j + 1) / 6.0
			seg.position = Vector3(sin(_t * 5.0 + ph + k * 2.5) * 0.12 * k, cos(_t * 4.0 + ph + k * 2.0) * 0.1 * k, 0.14 * float(j + 1))
		var tip: Node3D = pivot.get_node("Tip") as Node3D
		var last: Node3D = pivot.get_node("S5") as Node3D
		tip.position = last.position + Vector3(0, 0, 0.1)
	if _ball != null:
		_ball.rotation.y += dt * 6.0
		var s: float = 0.2 + 0.8 * clampf(_charge / CHARGE_TIME, 0.0, 1.0)
		_ball.scale = _ball.scale.lerp(Vector3.ONE * s, 1.0 - exp(-12.0 * dt))
		if _ball_core != null:
			_ball_core.scale = Vector3.ONE * (0.9 + sin(_t * 30.0) * 0.08)


func begin() -> void:
	layer.sfx.play("powerup", 1.0, 0.8)
	PartyFx.shake(layer.level, 0.35)


func tick(dt: float) -> void:
	_claw_cd = maxf(_claw_cd - dt, 0.0)


func charge_frac() -> float:
	return clampf(_charge / CHARGE_TIME, 0.0, 1.0) if _charge >= 0.0 else -1.0


func hud_status() -> String:
	if _charge >= 0.0:
		return "%s  %d%%" % [PartyNames.move_name("beast_bomb"), int(charge_frac() * 100.0)]
	return "%s: tap   %s: hold" % [PartyNames.move_name("claw"), PartyNames.move_name("beast_bomb")]


# ---- Fox Claw -------------------------------------------------------------------------------

## A tap (released before the charge begins) is a claw.
func _claw() -> void:
	if _claw_cd > 0.0:
		return
	_claw_cd = CLAW_COOLDOWN
	var p: Player = player()
	var dir: Vector3 = layer.melee_dir(4.0)
	p.facing_dir = dir
	# lunge
	var hv := Vector3(p.velocity.x, 0, p.velocity.z)
	var along: float = maxf(hv.dot(dir), 0.0)
	var lunge: Vector3 = dir * maxf(along, 15.0)
	p.velocity = Vector3(lunge.x, maxf(p.velocity.y, 1.5), lunge.z)
	var o: Vector3 = chest()
	_claw_fx(layer, o, dir)
	layer.sfx.play("slash", 1.0, 0.9)
	fx("claw", {"o": arr(o), "d": arr(dir)})
	for t: Dictionary in layer.targets_in_cone(o, dir, 3.0, 0.4):
		layer.hit(t, dir * 20.0 + Vector3(0, 10, 0), {"ko": true, "s": "claw"})


static func _claw_fx(parent: Node, o: Vector3, dir: Vector3) -> void:
	var b := Basis.looking_at(dir, Vector3.UP)
	for i: int in 3:
		var tilt := Basis(dir, deg_to_rad(-35.0 + 8.0 * float(i)))
		PartyFx.arc(parent, o + Vector3(0, 0.25 - 0.22 * float(i), 0) + dir * 0.4, tilt * b, 1.3, -1.0, 1.0, Color(1.0, 0.3 + 0.15 * float(i), 0.05), 0.12, 0.25)
	PartyFx.one_shot(parent, o + dir * 1.2, {"amount": 26, "lifetime": 0.35, "size": 0.2, "color": Color(1.0, 0.4, 0.05),
		"dir": dir, "spread": 40.0, "vmin": 5.0, "vmax": 11.0, "damping": 12.0, "spark": true})


# ---- Tailed Beast Bomb ----------------------------------------------------------------------

func on_attack_hold(held: float) -> void:
	if held < hold_threshold:
		return
	if _charge < 0.0:
		_charge = 0.0
		_show_ball(true)
		layer.sfx.play("charge", 0.8, 0.7)
		_hum = layer.sfx.hum("charge", self, 0.6, 0.5)
		fx("charge", {"on": true})
	_charge += 1.0 / Engine.physics_ticks_per_second
	if int(_charge * 20.0) % 4 == 0:
		PartyFx.shake(layer.level, 0.05 + 0.1 * charge_frac())


func on_attack_release(held: float) -> void:
	if _charge < 0.0:
		if held >= 0.0 and held < hold_threshold:
			_claw()
		return
	var power: float = charge_frac()
	_charge = -1.0
	_show_ball(false)
	if _hum != null:
		_hum.queue_free()
		_hum = null
	if held < 0.0 or power < 0.15:
		fx("charge", {"on": false})
		return
	var o: Vector3 = chest() + layer.aim_dir() * 0.9 + Vector3(0, 0.2, 0)
	var dir: Vector3 = layer.aim_dir()
	var tg: Dictionary = layer.nearest_in_cone(o, dir, 40.0, 0.92)
	if not tg.is_empty():
		dir = ((tg["center"] as Vector3) - o).normalized()
	var key: String = layer.new_key()
	var v: Vector3 = dir * BOMB_SPEED
	_spawn_bomb(layer, key, o, v, power, true)
	fx("bomb", {"k": key, "o": arr(o), "v": arr(v), "p": power})
	layer.sfx.play("beam", 1.0, 0.6)
	var p: Player = player()
	p.add_impulse(-dir * 4.0)
	PartyFx.shake(layer.level, 0.3)


func _show_ball(on: bool) -> void:
	if on and _ball == null:
		_ball = Node3D.new()
		_ball.position = Vector3(0, 0.95, -0.85)
		add_child(_ball)
		_ball_core = PartyFx.part(_ball, PartyFx.sphere_mesh(0.5, 20), PartyFx.glow_mat(Color(0.08, 0.0, 0.12), 1.0), Vector3.ZERO)
		PartyFx.part(_ball, PartyFx.sphere_mesh(0.62, 20), PartyFx.glow_mat(Color(0.6, 0.15, 0.9, 0.45), 2.0, true), Vector3.ZERO)
		var swirl: GPUParticles3D = PartyFx.emitter({"amount": 48, "lifetime": 0.45, "size": 0.2, "color": Color(0.7, 0.2, 1.0),
			"shape": "shell", "radius": 1.6, "vmin": 0.0, "vmax": 0.1, "radial": -14.0, "tangential": 10.0, "local": true,
			"shrink": false, "colors": [Color(0.2, 0.0, 0.3, 0.0), Color(0.8, 0.3, 1.0, 1.0), Color(1.0, 0.2, 0.2, 0.0)], "aabb": 3.0})
		_ball.add_child(swirl)
		var dark: GPUParticles3D = PartyFx.emitter({"amount": 20, "lifetime": 0.6, "size": 0.35, "color": Color(0.1, 0.0, 0.15, 0.8),
			"additive": false, "shape": "shell", "radius": 1.2, "vmin": 0.0, "vmax": 0.1, "radial": -8.0, "local": true, "aabb": 3.0})
		_ball.add_child(dark)
		_ball.scale = Vector3.ONE * 0.2
	elif not on and _ball != null:
		_ball.queue_free()
		_ball = null
		_ball_core = null


static func _spawn_bomb(layer_ref: PartyLayer, key: String, o: Vector3, v: Vector3, power: float, is_local: bool) -> PartyProjectile:
	var pr := PartyProjectile.new()
	pr.layer = layer_ref
	pr.local = is_local
	pr.key = key
	pr.origin = o
	pr.velocity = v
	pr.life = 1.6
	pr.radius = 0.7 + power * 0.6
	var r: float = 0.35 + 0.45 * power
	PartyFx.part(pr, PartyFx.sphere_mesh(r, 18), PartyFx.glow_mat(Color(0.06, 0.0, 0.1), 1.0), Vector3.ZERO)
	PartyFx.part(pr, PartyFx.sphere_mesh(r * 1.3, 18), PartyFx.glow_mat(Color(0.65, 0.2, 1.0, 0.5), 2.2, true), Vector3.ZERO)
	pr.add_child(PartyFx.emitter({"amount": 60, "lifetime": 0.45, "size": 0.45 * (0.6 + power), "color": Color(0.6, 0.15, 0.9),
		"shape": "sphere", "radius": r, "vmin": 0.1, "vmax": 0.8, "aabb": 20.0,
		"colors": [Color(0.9, 0.5, 1.0, 0.9), Color(0.3, 0.0, 0.5, 0.6), Color(0.1, 0.0, 0.1, 0.0)]}))
	pr.add_child(PartyFx.emitter({"amount": 24, "lifetime": 0.3, "size": 0.14, "color": Color(1.0, 0.3, 0.2),
		"shape": "shell", "radius": r * 1.5, "vmin": 0.0, "vmax": 0.2, "radial": -10.0, "tangential": 12.0, "spark": true,
		"local": true, "aabb": 3.0}))
	var boom := func(pos: Vector3) -> void:
		_explode(layer_ref, key, pos, power, true)
	pr.on_world = func(pos: Vector3, _n: Vector3) -> void: boom.call(pos)
	pr.on_expire = boom
	pr.on_target = func(_t: Dictionary, pos: Vector3) -> bool:
		boom.call(pos)
		return true
	layer_ref.add_child(pr)
	return pr


static func _explode(layer_ref: PartyLayer, key: String, pos: Vector3, power: float, is_local: bool) -> void:
	var radius: float = 3.5 + 2.5 * power
	_boom_fx(layer_ref, pos, radius)
	if is_local:
		layer_ref.send_fx("fox", "boom", {"k": key, "pos": PowerUp.arr(pos), "p": power})
		for t: Dictionary in layer_ref.targets_in_sphere(pos, radius):
			var away: Vector3 = (t["center"] as Vector3) - pos
			away.y = 0.0
			var dist: float = away.length()
			away = away.normalized() if dist > 0.1 else Vector3.FORWARD
			var fall: float = clampf(1.2 - dist / radius, 0.4, 1.0)
			layer_ref.hit(t, away * (14.0 + 10.0 * power) * fall + Vector3(0, (8.0 + 6.0 * power) * fall, 0), {"st": 0.4, "s": "beast_bomb", "quiet": true})


static func _boom_fx(layer_ref: PartyLayer, pos: Vector3, radius: float) -> void:
	PartyFx.explosion(layer_ref, pos, Color(0.55, 0.15, 0.95), Color(1.0, 0.45, 0.1), radius)
	PartyFx.implode(layer_ref, pos, Color(0.2, 0.0, 0.3), radius * 0.6)
	PartyFx.smoke(layer_ref, pos, Color(0.08, 0.0, 0.12, 0.8), 22, radius * 0.6, 2.0)
	layer_ref.sfx.play_at("boom", pos, 1.3, 0.8)
	var me: Vector3 = layer_ref.player.global_position
	PartyFx.shake(layer_ref.level, clampf(1.2 - me.distance_to(pos) / (radius * 4.0), 0.0, 0.9))


# ---- the mirror on a rival's ghost ----------------------------------------------------------

func remote(action: String, d: Dictionary) -> void:
	match action:
		"claw":
			_claw_fx(layer, v3(d.get("o", [])), v3(d.get("d", [])))
			layer.sfx.play_at("slash", v3(d.get("o", [])), 0.9)
		"charge":
			_charge = 0.0 if bool(d.get("on", false)) else -1.0
			_show_ball(bool(d.get("on", false)))
		"bomb":
			_charge = -1.0
			_show_ball(false)
			_spawn_bomb(layer, str(d.get("k", "")), v3(d.get("o", [])), v3(d.get("v", [])), float(d.get("p", 0.5)), false)
			layer.sfx.play_at("beam", v3(d.get("o", [])), 0.9, 0.6)
		"boom":
			remote_fx(layer, owner_id, action, d)


func remote_tick(dt: float) -> void:
	if _charge >= 0.0:
		_charge += dt


## Replays a bomb burst even after the fox mirror is gone.
static func remote_fx(layer_ref: PartyLayer, _from_id: int, action: String, d: Dictionary) -> void:
	if action != "boom":
		return
	var key: String = str(d.get("k", ""))
	var pos: Vector3 = PowerUp.v3(d.get("pos", []))
	var pr: Variant = layer_ref.projectiles.get(key, null)
	if pr != null and is_instance_valid(pr):
		(pr as PartyProjectile).stop(pos)
	_explode(layer_ref, key, pos, float(d.get("p", 0.5)), false)


func on_end() -> void:
	_show_ball(false)
	if _hum != null:
		_hum.queue_free()
	if is_inside_tree():
		PartyFx.burst(world(), global_position + Vector3(0, 0.8, 0), CLOAK, 30, 5.0, 0.3)
