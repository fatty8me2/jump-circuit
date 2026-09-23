extends PowerUp
## Golden Surge Hair: spiky golden hair, a roaring golden aura and crackling lightning.
## Speed x1.4, jump x1.2 and a mid-air double jump.
##  Attack (tap): Dash Punch - a blurring lunge; whoever it meets is sent flying.
##  Attack (hold): charge the Energy Wave between the hands ("Ka... me..."), release to fire a
##  long beam that shoves everyone along it (shortened by walls).

const GOLDEN := Color(1.0, 0.84, 0.2)
const WAVE := Color(0.45, 0.8, 1.0)
const CHARGE_TIME: float = 1.4
const DASH_TIME: float = 0.2
const DASH_SPEED: float = 25.0
const DASH_CD: float = 0.5
const WAVE_RANGE: float = 34.0

var _t: float = 0.0
var _crackle_t: float = 0.0
var _charge: float = -1.0
var _orb: Node3D
var _orb_light: OmniLight3D
var _dash: float = 0.0
var _dash_dir: Vector3 = Vector3.ZERO
var _dash_cd: float = 0.0
var _dash_hit: Array[int] = []
var _hum: AudioStreamPlayer3D
var _air_used: int = 0
var _aura_shell: MeshInstance3D
var _hair: Node3D


func _init() -> void:
	duration = 10.0
	takes_attack = true


func mods() -> Vector3:
	return Vector3(1.4, 1.2, 1.0)


func air_jumps() -> int:
	return 1


func build_look() -> void:
	# spiky golden hair: a crown of glowing cones swept up and back
	_hair = Node3D.new()
	_hair.position = Vector3(0, 0.96, 0.05)
	add_child(_hair)
	var hair_mat: StandardMaterial3D = PartyFx.glow_mat(GOLDEN, 1.9)
	var spikes: Array = [
		[Vector3(0, 0.18, 0.02), Vector3(-8, 0, 0), 0.62, 0.13],
		[Vector3(-0.17, 0.12, 0.02), Vector3(-10, 0, 34), 0.5, 0.12],
		[Vector3(0.17, 0.12, 0.02), Vector3(-10, 0, -34), 0.5, 0.12],
		[Vector3(-0.28, 0.02, 0.06), Vector3(-5, 0, 62), 0.42, 0.11],
		[Vector3(0.28, 0.02, 0.06), Vector3(-5, 0, -62), 0.42, 0.11],
		[Vector3(0, 0.1, 0.2), Vector3(-50, 0, 0), 0.55, 0.13],
		[Vector3(-0.15, 0.06, 0.22), Vector3(-55, 0, 25), 0.46, 0.11],
		[Vector3(0.15, 0.06, 0.22), Vector3(-55, 0, -25), 0.46, 0.11],
		[Vector3(0, 0.14, -0.16), Vector3(28, 0, 0), 0.3, 0.1],
	]
	for s: Array in spikes:
		var piv := Node3D.new()
		piv.position = s[0]
		piv.rotation_degrees = s[1]
		_hair.add_child(piv)
		PartyFx.part(piv, PartyFx.cone_mesh(float(s[3]), float(s[2]), 8), hair_mat, Vector3(0, float(s[2]) * 0.5, 0))
	PartyFx.part(_hair, PartyFx.sphere_mesh(0.3, 16), hair_mat, Vector3(0, 0.02, 0.04), Vector3(1.05, 0.5, 1.0))
	# aura: a pulsing golden shell, flames licking upward, lifted pebbles of light, electric sparks
	_aura_shell = PartyFx.part(self, PartyFx.sphere_mesh(0.75, 20), PartyFx.glow_mat(Color(1.0, 0.8, 0.2, 0.16), 2.0, true), Vector3(0, 0.7, 0), Vector3(1.0, 1.35, 1.0))
	var flames: GPUParticles3D = PartyFx.emitter({"amount": 64, "lifetime": 0.5, "size": 0.36, "color": GOLDEN,
		"shape": "ring", "radius": 0.55, "inner": 0.3, "height": 0.2, "dir": Vector3.UP, "spread": 12.0, "vmin": 3.0, "vmax": 5.5,
		"colors": [Color(1.0, 1.0, 0.8, 0.0), Color(1.0, 0.9, 0.35, 0.9), Color(1.0, 0.6, 0.1, 0.0)], "aabb": 4.0})
	flames.position = Vector3(0, 0.05, 0)
	add_child(flames)
	var motes: GPUParticles3D = PartyFx.emitter({"amount": 20, "lifetime": 1.0, "size": 0.08, "color": Color(1.0, 0.95, 0.6),
		"shape": "ring", "radius": 1.1, "inner": 0.6, "height": 0.1, "dir": Vector3.UP, "spread": 5.0, "vmin": 1.0, "vmax": 2.4,
		"spark": true, "aabb": 4.0})
	add_child(motes)
	var sparks: GPUParticles3D = PartyFx.emitter({"amount": 14, "lifetime": 0.14, "size": 0.12, "color": Color(0.7, 0.9, 1.0),
		"shape": "sphere", "radius": 0.7, "vmin": 2.0, "vmax": 6.0, "spark": true, "aabb": 4.0})
	sparks.position = Vector3(0, 0.7, 0)
	add_child(sparks)
	if is_inside_tree():
		var at: Vector3 = global_position
		PartyFx.burst(world(), at + Vector3(0, 0.8, 0), GOLDEN, 80, 10.0, 0.35, 0.8)
		PartyFx.one_shot(world(), at, {"amount": 60, "lifetime": 0.9, "size": 0.3, "color": GOLDEN, "shape": "ring",
			"radius": 0.8, "inner": 0.5, "dir": Vector3.UP, "spread": 8.0, "vmin": 8.0, "vmax": 14.0, "damping": 6.0,
			"explosiveness": 0.8})
		PartyFx.shockwave(world(), at, GOLDEN, 5.0, 0.5)
		PartyFx.flash(world(), at + Vector3(0, 1, 0), GOLDEN, 10.0, 10.0, 0.6)
		for i: int in 4:
			PartyFx.crackle(world(), at + Vector3(0, 0.8, 0), 1.2, Color(0.75, 0.9, 1.0), 5, 0.2)


func begin() -> void:
	layer.sfx.play("powerup", 1.0, 0.7)
	layer.sfx.play("zap", 0.8, 1.2)
	PartyFx.shake(layer.level, 0.5)


func _process(dt: float) -> void:
	_t += dt
	if _aura_shell != null:
		var k: float = 1.0 + sin(_t * 18.0) * 0.05 + sin(_t * 7.0) * 0.04
		_aura_shell.scale = Vector3(k, 1.35 * k, k)
	if _hair != null:
		_hair.position.y = 0.96 + sin(_t * 40.0) * 0.008
	_crackle_t -= dt
	if _crackle_t <= 0.0 and is_inside_tree():
		_crackle_t = randf_range(0.12, 0.35)
		PartyFx.crackle(world(), global_position + Vector3(0, 0.75, 0), 0.75, Color(0.75, 0.9, 1.0), 3, 0.08)
	if _orb != null:
		var s: float = 0.25 + 0.75 * clampf(_charge / CHARGE_TIME, 0.0, 1.0)
		_orb.scale = _orb.scale.lerp(Vector3.ONE * s * (1.0 + sin(_t * 35.0) * 0.06), 1.0 - exp(-14.0 * dt))
		if _orb_light != null:
			_orb_light.light_energy = 2.0 + 5.0 * s


func tick(dt: float) -> void:
	_dash_cd = maxf(_dash_cd - dt, 0.0)
	var p: Player = player()
	# double jump flourish (the Player does the jump itself via air_jumps())
	if p._air_jumps_used > _air_used:
		PartyFx.ring_pulse(world(), feet(), Vector3.UP, GOLDEN, 0.3, 1.8, 0.3, 0.2)
		PartyFx.burst(world(), feet(), GOLDEN, 20, 5.0, 0.2, 0.4)
		layer.sfx.play("whoosh", 0.7, 1.5)
	_air_used = p._air_jumps_used
	if _dash > 0.0:
		_dash -= dt
		p.velocity = Vector3(_dash_dir.x * DASH_SPEED, maxf(p.velocity.y, 0.5), _dash_dir.z * DASH_SPEED)
		var o: Vector3 = chest()
		for t: Dictionary in layer.targets_in_cone(o, _dash_dir, 1.9, 0.2):
			if _dash_hit.has(int(t["id"])):
				continue
			_dash_hit.append(int(t["id"]))
			layer.hit(t, _dash_dir * 19.0 + Vector3(0, 8.0, 0), {"st": 0.6, "s": "dash_punch"})
			PartyFx.popup_text(world(), (t["center"] as Vector3) + Vector3(0, 1.2, 0), "POW!", GOLDEN)
			PartyFx.shockwave(world(), t["center"] as Vector3, GOLDEN, 2.0, 0.25)
			_dash = minf(_dash, 0.04)


func charge_frac() -> float:
	return clampf(_charge / CHARGE_TIME, 0.0, 1.0) if _charge >= 0.0 else -1.0


func hud_status() -> String:
	if _charge >= 0.0:
		var n: int = PartyNames.WAVE_CHANT.size()
		return PartyNames.WAVE_CHANT[clampi(int(charge_frac() * float(n)), 0, n - 1)]
	return "%s: tap   %s: hold   Double jump" % [PartyNames.move_name("dash_punch"), PartyNames.move_name("wave")]


# ---- Dash Punch -----------------------------------------------------------------------------

func _dash_punch() -> void:
	if _dash_cd > 0.0:
		return
	_dash_cd = DASH_CD
	_dash = DASH_TIME
	_dash_hit.clear()
	var p: Player = player()
	_dash_dir = layer.melee_dir(6.0)
	p.facing_dir = _dash_dir
	_dash_fx(layer, chest(), _dash_dir)
	layer.sfx.play("whoosh", 1.0, 1.3)
	fx("dash", {"o": arr(chest()), "d": arr(_dash_dir)})


static func _dash_fx(parent: Node, o: Vector3, dir: Vector3) -> void:
	PartyFx.streak(parent, o - dir * 1.0, o + dir * 4.5, Color(1.0, 0.9, 0.4), 40, 0.16, 0.35, 0.35, 0.5)
	PartyFx.one_shot(parent, o, {"amount": 30, "lifetime": 0.3, "size": 0.26, "color": Color(1.0, 0.85, 0.3),
		"dir": -dir, "spread": 25.0, "vmin": 6.0, "vmax": 12.0, "damping": 14.0})
	PartyFx.ring_pulse(parent, o + dir * 0.6, dir, Color(1.0, 0.95, 0.6), 0.2, 1.3, 0.2, 0.25)


# ---- Energy Wave ----------------------------------------------------------------------------

func on_attack_hold(held: float) -> void:
	if held < hold_threshold:
		return
	if _charge < 0.0:
		_charge = 0.0
		_show_orb(true)
		layer.sfx.play("charge", 0.9, 1.0)
		_hum = layer.sfx.hum("charge", self, 0.8, 0.5)
		fx("charge", {"on": true})
	var before: int = int(charge_frac() * float(PartyNames.WAVE_CHANT.size()))
	_charge += 1.0 / Engine.physics_ticks_per_second
	var after: int = int(charge_frac() * float(PartyNames.WAVE_CHANT.size()))
	if after != before and after < PartyNames.WAVE_CHANT.size():
		layer.hud.announce(PartyNames.WAVE_CHANT[after], WAVE.lerp(Color.WHITE, 0.3))
	if int(_charge * 30.0) % 5 == 0:
		PartyFx.shake(layer.level, 0.04 + 0.12 * charge_frac())
		PartyFx.crackle(world(), _orb.global_position if _orb != null else chest(), 0.6, WAVE.lerp(Color.WHITE, 0.4), 3, 0.08)


func on_attack_release(held: float) -> void:
	if _charge < 0.0:
		if held >= 0.0 and held < hold_threshold:
			_dash_punch()
		return
	var power: float = charge_frac()
	_charge = -1.0
	_show_orb(false)
	if _hum != null:
		_hum.queue_free()
		_hum = null
	if held < 0.0 or power < 0.2:
		fx("charge", {"on": false})
		return
	var o: Vector3 = chest() + layer.aim_dir() * 0.7
	var dir: Vector3 = layer.aim_dir()
	var tg: Dictionary = layer.nearest_in_cone(o, dir, WAVE_RANGE, 0.94)
	if not tg.is_empty():
		dir = ((tg["center"] as Vector3) - o).normalized()
	var end: Vector3 = o + dir * WAVE_RANGE
	var wall: Dictionary = layer.ray(o, end)
	if not wall.is_empty():
		end = wall["position"]
	var width: float = 0.5 + 0.7 * power
	_wave_fx(layer, o, end, width)
	layer.hud.announce(PartyNames.WAVE_SHOUT, WAVE.lerp(Color.WHITE, 0.4))
	layer.sfx.play("beam", 1.2, 0.8)
	PartyFx.shake(layer.level, 0.5 + 0.4 * power)
	player().add_impulse(-dir * (5.0 + 5.0 * power))
	fx("wave", {"o": arr(o), "e": arr(end), "w": width})
	for t: Dictionary in layer.targets_near_segment(o, end, 1.1 + width):
		layer.hit(t, dir * (18.0 + 12.0 * power) + Vector3(0, 6.0 + 3.0 * power, 0), {"st": 0.6, "s": "wave", "quiet": true})
		PartyFx.burst(layer, t["center"] as Vector3, WAVE.lerp(Color.WHITE, 0.5), 30, 7.0, 0.3)


func _show_orb(on: bool) -> void:
	if on and _orb == null:
		_orb = Node3D.new()
		_orb.position = Vector3(0, 0.7, -0.62)
		add_child(_orb)
		PartyFx.part(_orb, PartyFx.sphere_mesh(0.3, 18), PartyFx.glow_mat(Color(0.9, 0.97, 1.0), 3.0), Vector3.ZERO)
		PartyFx.part(_orb, PartyFx.sphere_mesh(0.48, 18), PartyFx.glow_mat(Color(0.35, 0.7, 1.0, 0.4), 2.5, true), Vector3.ZERO)
		_orb.add_child(PartyFx.emitter({"amount": 50, "lifetime": 0.4, "size": 0.14, "color": WAVE,
			"shape": "shell", "radius": 1.4, "vmin": 0.0, "vmax": 0.1, "radial": -16.0, "tangential": 9.0, "local": true,
			"spark": true, "aabb": 3.0, "shrink": false,
			"colors": [Color(0.3, 0.6, 1.0, 0.0), Color(0.7, 0.9, 1.0, 1.0), Color(1, 1, 1, 0.0)]}))
		_orb.add_child(PartyFx.emitter({"amount": 24, "lifetime": 0.25, "size": 0.35, "color": Color(0.6, 0.85, 1.0),
			"shape": "sphere", "radius": 0.2, "vmin": 0.2, "vmax": 0.8, "local": true, "aabb": 3.0}))
		_orb_light = OmniLight3D.new()
		_orb_light.light_color = WAVE
		_orb_light.omni_range = 5.0
		_orb_light.light_energy = 2.0
		_orb.add_child(_orb_light)
		_orb.scale = Vector3.ONE * 0.25
	elif not on and _orb != null:
		_orb.queue_free()
		_orb = null
		_orb_light = null


static func _wave_fx(parent: Node, o: Vector3, end: Vector3, width: float) -> void:
	# a thick white-hot core inside a wide blue beam, fading and thinning over half a second
	PartyFx.beam(parent, o, end, Color(1.0, 1.0, 1.0, 1.0), width * 0.45, 0.55, 3.5)
	PartyFx.beam(parent, o, end, Color(0.35, 0.7, 1.0, 0.55), width, 0.7, 2.5)
	PartyFx.beam(parent, o, end, Color(0.3, 0.55, 1.0, 0.2), width * 1.7, 0.5, 2.0)
	PartyFx.streak(parent, o, end, Color(0.6, 0.9, 1.0), 120, 0.28, 0.7, width * 1.2, 4.0)
	PartyFx.streak(parent, o, end, Color(1.0, 1.0, 1.0), 60, 0.1, 0.5, width, 8.0, true)
	var dir: Vector3 = (end - o).normalized()
	var length: float = o.distance_to(end)
	var n: int = int(length / 4.0)
	for i: int in n:
		PartyFx.ring_pulse(parent, o + dir * (2.0 + 4.0 * float(i)), dir, Color(0.6, 0.9, 1.0), width, width * 2.4, 0.35 + 0.02 * float(i), 0.18)
	PartyFx.orb_pulse(parent, o, Color(0.8, 0.95, 1.0, 0.9), 0.3, width * 2.5, 0.3, 3.0)
	PartyFx.explosion(parent, end, Color(0.4, 0.75, 1.0), Color(0.85, 0.95, 1.0), 2.5 + width)
	PartyFx.flash(parent, o, WAVE, 10.0, 12.0, 0.5)


# ---- the mirror on a rival's ghost ----------------------------------------------------------

func remote(action: String, d: Dictionary) -> void:
	match action:
		"dash":
			_dash_fx(layer, v3(d.get("o", [])), v3(d.get("d", [])))
			layer.sfx.play_at("whoosh", v3(d.get("o", [])), 0.9, 1.3)
		"charge":
			_charge = 0.0 if bool(d.get("on", false)) else -1.0
			_show_orb(bool(d.get("on", false)))
		"wave":
			_charge = -1.0
			_show_orb(false)
			remote_fx(layer, owner_id, action, d)


func remote_tick(dt: float) -> void:
	if _charge >= 0.0:
		_charge += dt


static func remote_fx(layer_ref: PartyLayer, _from_id: int, action: String, d: Dictionary) -> void:
	if action != "wave":
		return
	var o: Vector3 = PowerUp.v3(d.get("o", []))
	_wave_fx(layer_ref, o, PowerUp.v3(d.get("e", [])), float(d.get("w", 0.8)))
	layer_ref.sfx.play_at("beam", o, 1.2, 0.8)
	var me: Vector3 = layer_ref.player.global_position
	PartyFx.shake(layer_ref.level, clampf(0.8 - me.distance_to(o) / 40.0, 0.0, 0.6))


func on_end() -> void:
	_show_orb(false)
	if _hum != null:
		_hum.queue_free()
	if is_inside_tree():
		PartyFx.burst(world(), global_position + Vector3(0, 0.8, 0), GOLDEN, 40, 6.0, 0.3)
		PartyFx.smoke(world(), global_position + Vector3(0, 0.6, 0), Color(1.0, 0.9, 0.6, 0.5), 10, 0.6, 0.8)
