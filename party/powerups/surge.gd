extends PowerUp
## Golden Surge Hair: spiky golden hair, a roaring golden aura and crackling lightning.
## Speed x1.4, jump x1.2 and a mid-air double jump.
##  Attack (tap): Dash Punch - a blurring lunge; whoever it meets is sent flying.
##  Attack (hold): charge the Energy Wave between the hands ("Ka... me..."), release to fire a
##  long beam that shoves everyone along it (shortened by walls).
## The look: the hair flares up in a transformation burst (a pillar of light, a crater of
## dust, lightning); a flickering flame aura with rising motes, lifted pebbles and crackles;
## afterimages behind the dash; a gathering orb at the hip and a thick shimmering beam; the
## aura sputters out when it ends.

const GOLDEN := Color(1.0, 0.84, 0.2)
const WAVE := Color(0.45, 0.8, 1.0)
const CHARGE_TIME: float = 1.4
const DASH_TIME: float = 0.2
const DASH_SPEED: float = 25.0
const DASH_CD: float = 0.5
const WAVE_RANGE: float = 34.0
const BOLT := Color(0.75, 0.9, 1.0)

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
# the look
var _rig: HeroFx.Rig
var _aura_mat: ShaderMaterial
var _hair_mat: ShaderMaterial
var _spikes: Array[Node3D] = []
var _spike_rest: Array[Vector3] = []
var _hair_lean: Vector2 = Vector2.ZERO
var _flare: float = 0.0
var _flames: GPUParticles3D
var _motes: GPUParticles3D
var _pebbles: GPUParticles3D
var _floor_glow: MeshInstance3D
var _light: OmniLight3D
var _dash_vis: float = 0.0
var _ghost_t: float = 0.0
var _vis_dir: Vector3 = Vector3.FORWARD
var _dust_t: float = 0.0


func _init() -> void:
	duration = 10.0
	takes_attack = true


func mods() -> Vector3:
	return Vector3(1.4, 1.2, 1.0)


func air_jumps() -> int:
	return 1


func build_look() -> void:
	_rig = HeroFx.Rig.new()
	add_child(_rig)
	# spiky golden hair: a crown of glowing energy spikes swept up and back, each on a pivot
	_hair = Node3D.new()
	_hair.position = Vector3(0, 0.96, 0.05)
	_rig.add_child(_hair)
	_hair_mat = HeroFx.energy_mat(Color(1.0, 0.78, 0.12), Color(1.0, 1.0, 0.78), 1.25, 2.5)
	_hair_mat.set_shader_parameter("rim_amt", 0.6)
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
		HeroFx.mesh_part(piv, PartyFx.cone_mesh(float(s[3]), float(s[2]), 8), _hair_mat, Vector3(0, float(s[2]) * 0.5, 0))
		_spikes.append(piv)
		_spike_rest.append(s[1])
	HeroFx.mesh_part(_hair, PartyFx.sphere_mesh(0.3, 16), _hair_mat, Vector3(0, 0.02, 0.04), Vector3(1.05, 0.5, 1.0))
	# the aura: a flame-shaped shell (pointed top) plus a soft additive glow round it
	_aura_mat = HeroFx.flame_mat(Color(1.0, 0.68, 0.06), Color(1.0, 0.9, 0.4), 1.0, 0.1, 4.0, true)
	_aura_mat.set_shader_parameter("stretch", 0.22)
	_aura_mat.set_shader_parameter("base_alpha", 0.0)
	_aura_mat.set_shader_parameter("freq", 3.0)
	_aura_shell = HeroFx.mesh_part(_rig, PartyFx.sphere_mesh(0.5, 40), _aura_mat, Vector3(0, 0.72, 0), Vector3(1.25, 1.5, 1.25))
	_aura_shell.set_meta("no_ghost", true)
	# tongues of golden flame licking up around the body (a ring, so the body stays visible)
	var fo: Dictionary = {"amount": 64, "lifetime": 0.45, "shape": "ring", "ring_radius": 0.62, "ring_inner": 0.42,
		"ring_height": 0.25, "dir": Vector3.UP, "spread": 6.0, "speed": Vector2(2.2, 4.2), "gravity": Vector3(0, 2.0, 0),
		"curve": "shrink", "scale": Vector2(0.7, 1.2), "fixed_fps": 0,
		"colors": PackedColorArray([Color(1.2, 1.1, 0.6, 0.0), Color(1.2, 0.88, 0.22, 0.95), Color(1.1, 0.55, 0.04, 0.0)])}
	fo.merge(HeroFx.tongues(Vector2(0.5, 1.0)))
	_flames = HeroFx.em(fo)
	_flames.position = Vector3(0, 0.05, 0)
	_rig.add_child(_flames)
	# rising motes of light, and pebbles lifted off the ground by the energy
	_motes = HeroFx.em({"amount": 22, "lifetime": 1.0, "shape": "ring", "ring_radius": 1.1, "ring_inner": 0.6,
		"ring_height": 0.1, "dir": Vector3.UP, "spread": 5.0, "speed": Vector2(1.0, 2.6), "facing": "velocity",
		"tex": Fx.Tex.SPARK, "size": Vector2(0.08, 0.3), "color": Color(1.2, 1.0, 0.4), "additive": false,
		"fade": PackedFloat32Array([0.0, 1.0, 0.8, 0.0])})
	add_child(_motes)
	_pebbles = HeroFx.em({"amount": 7, "lifetime": 1.4, "shape": "ring", "ring_radius": 1.2, "ring_inner": 0.5,
		"ring_height": 0.02, "dir": Vector3.UP, "spread": 10.0, "speed": Vector2(0.4, 1.0), "gravity": Vector3(0, 0.6, 0),
		"facing": "mesh", "mesh": Fx.chunk_mesh(0.1), "scale": Vector2(0.6, 1.3), "curve": "shrink",
		"spin": Vector2(-120, 120), "angle": Vector2(0, 360), "color": Color(0.55, 0.5, 0.45),
		"fade": PackedFloat32Array([1.0, 1.0])})
	_pebbles.position = Vector3(0, 0.05, 0)
	add_child(_pebbles)
	# a glowing pool of light under the feet
	_floor_glow = HeroFx.glow_sprite(self, Color(1.0, 0.8, 0.2, 0.55), 2.6, Fx.Tex.RING, Vector3(0, 0.05, 0))
	(_floor_glow.material_override as StandardMaterial3D).billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	_floor_glow.rotation_degrees = Vector3(-90, 0, 0)
	_floor_glow.set_meta("no_ghost", true)
	if not HeroFx.low():
		_light = OmniLight3D.new()
		_light.light_color = Color(1.0, 0.85, 0.4)
		_light.light_energy = 0.0
		_light.omni_range = 4.0
		_light.shadow_enabled = false
		_light.position = Vector3(0, 0.9, 0)
		_rig.add_child(_light)
	if is_inside_tree():
		_transform_in()


## The transformation: a pillar of golden light, a crater of dust and pebbles, lightning, and
## the hair shoots up spike by spike while the aura ignites.
func _transform_in() -> void:
	var w: Node = world()
	var at: Vector3 = global_position
	# hair starts flat and shoots up, spike by spike, with overshoot
	for i: int in _spikes.size():
		var sp: Node3D = _spikes[i]
		sp.scale = Vector3(1.0, 0.05, 1.0)
		var tw: Tween = create_tween()
		tw.tween_interval(0.05 + 0.03 * float(i))
		tw.tween_property(sp, "scale", Vector3(1.0, 1.25, 1.0), 0.12).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(sp, "scale", Vector3.ONE, 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
	_hair_mat.set_shader_parameter("flash", 1.0)
	HeroFx.tween_param(self, _hair_mat, "flash", 1.0, 0.0, 0.6)
	# the aura ignites with a big flare
	_flare = 1.6
	# the pillar of light
	var pm := ShaderMaterial.new()
	pm.shader = HeroFx.shader("beam")
	pm.set_shader_parameter("core", Color(1.0, 0.95, 0.7))
	pm.set_shader_parameter("glow", Color(1.0, 0.65, 0.05))
	pm.set_shader_parameter("energy", 1.0)
	pm.set_shader_parameter("length_m", 8.0)
	pm.set_shader_parameter("scroll", -10.0)
	var cm: CylinderMesh = PartyFx.cyl_mesh(1.0, 1.0, -1.0, 20)
	cm.cap_top = false
	cm.cap_bottom = false
	var pillar := MeshInstance3D.new()
	pillar.mesh = cm
	pillar.material_override = pm
	pillar.layers = HeroFx.LAYER
	pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	w.add_child(pillar)
	pillar.global_transform = PartyFx.beam_transform(at, at + Vector3(0, 0.3, 0), 0.4)
	var ptw: Tween = pillar.create_tween()
	ptw.tween_method(func(k: float) -> void:
		pillar.global_transform = PartyFx.beam_transform(at - Vector3(0, 0.2, 0), at + Vector3(0, 0.3 + 9.0 * k, 0), 0.3 + 0.3 * k), 0.0, 1.0, 0.16).set_ease(Tween.EASE_OUT)
	ptw.tween_method(func(v: float) -> void: pm.set_shader_parameter("alpha", v), 1.0, 0.0, 0.35).set_ease(Tween.EASE_IN)
	ptw.parallel().tween_method(func(k: float) -> void:
		pillar.global_transform = PartyFx.beam_transform(at - Vector3(0, 0.2, 0), at + Vector3(0, 9.3, 0), 0.6 + 0.5 * k), 0.0, 1.0, 0.35)
	ptw.tween_callback(pillar.queue_free)
	# the burst: a crater of dust and pebbles, rings, sparks and lightning
	HeroFx.ring(w, at + Vector3(0, 0.1, 0), Vector3.UP, Color(1.2, 0.95, 0.35, 0.95), 0.4, 5.0, 0.5, 0.06)
	HeroFx.ground_ring(w, at, Color(1.2, 0.95, 0.4), 3.5, 0.5)
	HeroFx.dust_ring(w, at, Color(0.9, 0.85, 0.7, 0.3), 1.2, 12, 6.0)
	HeroFx.pop(w, {"amount": 14, "lifetime": 1.0, "facing": "mesh", "mesh": Fx.chunk_mesh(0.12), "spread": 35.0,
		"shape": "ring", "ring_radius": 1.0, "ring_inner": 0.4, "speed": Vector2(4.0, 8.0), "gravity": Vector3(0, -18, 0),
		"scale": Vector2(0.6, 1.3), "curve": "shrink", "spin": Vector2(-400, 400), "angle": Vector2(0, 360),
		"color": Color(0.55, 0.5, 0.45), "fade": PackedFloat32Array([1.0, 1.0])}, at)
	HeroFx.pop(w, {"amount": 60, "lifetime": 0.7, "shape": "ring", "ring_radius": 0.7, "ring_inner": 0.4, "dir": Vector3.UP,
		"spread": 10.0, "speed": Vector2(8.0, 15.0), "damping": Vector2(5.0, 8.0), "facing": "velocity",
		"tex": Fx.Tex.SPARK, "size": Vector2(0.1, 0.9), "color": Color(1.6, 1.3, 0.5), "explosiveness": 0.8}, at)
	HeroFx.burst(w, at + Vector3(0, 0.8, 0), Color(1.4, 1.1, 0.4), 50, 9.0, 0.3, 0.6)
	for i: int in 4:
		var a: float = float(i) * TAU / 4.0 + randf() * 0.6
		PartyFx.bolt(w, at + Vector3(0, 1.0, 0), at + Vector3(cos(a) * 2.2, 0.05, sin(a) * 2.2), BOLT, randi(), 0.2)
	HeroFx.flash(w, at + Vector3(0, 1, 0), GOLDEN, 10.0, 10.0, 0.6)
	if local and layer != null:
		HeroFx.screen_flash(layer, Color(1.0, 0.9, 0.5), 0.45, 0.45)


func begin() -> void:
	layer.sfx.play("powerup", 1.0, 0.7)
	layer.sfx.play("zap", 0.8, 1.2)
	PartyFx.shake(layer.level, 0.5)


func _process(dt: float) -> void:
	_t += dt
	if _rig == null or not is_inside_tree():
		return
	_flare = maxf(_flare - dt * 2.2, 0.0)
	var charging: float = charge_frac() if _charge >= 0.0 else 0.0
	var power: float = _flare + charging * 0.8
	# the aura flickers and flares (stretching taller while charging)
	if _aura_shell != null:
		var k: float = 1.0 + sin(_t * 18.0) * 0.05 + sin(_t * 7.0) * 0.04 + power * 0.12
		_aura_shell.scale = Vector3(1.25 * k, 1.5 * k * (1.0 + power * 0.15), 1.25 * k)
		_aura_mat.set_shader_parameter("stretch", 0.22 + power * 0.35 + sin(_t * 11.0) * 0.05)
		_aura_mat.set_shader_parameter("lick", 0.1 + power * 0.08)
	if not ended:
		_flames.amount_ratio = clampf(0.7 + power * 0.5, 0.0, 1.0)
		_pebbles.amount_ratio = clampf(0.4 + charging, 0.0, 1.0)
	# the hair: a crackling shimmer, swept back by speed
	var vel: Vector3 = _vel()
	var inv: Basis = global_basis.orthonormalized().inverse()
	var lv: Vector3 = inv * vel
	var target := Vector2(clampf(lv.z * 0.025, -0.35, 0.25) + clampf(-vel.y * 0.015, -0.2, 0.2), clampf(-lv.x * 0.02, -0.25, 0.25))
	_hair_lean = _hair_lean.lerp(target, 1.0 - exp(-8.0 * dt))
	_hair.rotation = Vector3(_hair_lean.x, 0, _hair_lean.y)
	_hair.position.y = 0.96 + sin(_t * 40.0) * 0.008
	for i: int in _spikes.size():
		var sp: Node3D = _spikes[i]
		var rest: Vector3 = _spike_rest[i]
		sp.rotation_degrees = rest + Vector3(sin(_t * 23.0 + float(i) * 1.9) * 2.5, 0, cos(_t * 19.0 + float(i) * 2.3) * 2.5)
	if _floor_glow != null:
		var fm := _floor_glow.material_override as StandardMaterial3D
		fm.albedo_color.a = (0.0 if ended else 0.4 + 0.15 * sin(_t * 13.0) + power * 0.3)
		_floor_glow.scale = Vector3.ONE * (1.0 + power * 0.4 + sin(_t * 9.0) * 0.05)
	if _light != null:
		var want: float = 0.0 if ended else 1.2 + sin(_t * 23.0) * 0.3 + power * 2.0
		_light.light_energy = lerpf(_light.light_energy, want, 1.0 - exp(-14.0 * dt))
	# lightning crackling round the body (a bigger arc to the ground now and then)
	_crackle_t -= dt
	if _crackle_t <= 0.0 and not ended:
		_crackle_t = randf_range(0.1, 0.3) * (0.5 if charging > 0.0 else 1.0)
		PartyFx.crackle(world(), global_position + Vector3(0, 0.75, 0), 0.8, BOLT, 4, 0.08)
		if randf() < 0.2:
			var a: float = randf() * TAU
			PartyFx.crackle(world(), global_position + Vector3(cos(a) * 0.5, 0.3, sin(a) * 0.5), 0.6, Color(1.0, 0.95, 0.6), 3, 0.08)
	# charging: dust swirls in toward the feet
	if charging > 0.0:
		_dust_t -= dt
		if _dust_t <= 0.0:
			_dust_t = lerpf(0.3, 0.15, charging)
			HeroFx.ring(world(), global_position + Vector3(0, 0.08, 0), Vector3.UP, Color(0.5, 0.8, 1.2, 0.5), 2.4, 0.5, 0.3, 0.04)
			if charging > 0.5:
				HeroFx.dust_ring(world(), global_position, Color(0.85, 0.82, 0.75, 0.5), 0.9, 6, 3.0)
	if _orb != null:
		var s: float = 0.25 + 0.75 * clampf(_charge / CHARGE_TIME, 0.0, 1.0)
		_orb.scale = _orb.scale.lerp(Vector3.ONE * s * (1.0 + sin(_t * 35.0) * 0.06), 1.0 - exp(-14.0 * dt))
		for c: Node in _orb.get_children():
			if c.has_meta("spin"):
				(c as Node3D).rotate_object_local(Vector3.UP, dt * 11.0)
		if _orb_light != null:
			_orb_light.light_energy = 2.0 + 5.0 * s
	# afterimages streaming behind a dash
	if _dash_vis > 0.0:
		_dash_vis -= dt
		_ghost_t -= dt
		if _ghost_t <= 0.0:
			_ghost_t = 0.035
			HeroFx.afterimage(world(), get_parent() as Node3D, Color(1.0, 0.8, 0.25), 0.25, _vis_dir, 1.3)


func _vel() -> Vector3:
	if body is Player:
		return (body as Player).velocity
	if body != null and body.has_method("velocity"):
		return body.call("velocity")
	return Vector3.ZERO


func tick(dt: float) -> void:
	_dash_cd = maxf(_dash_cd - dt, 0.0)
	var p: Player = player()
	# double jump flourish (the Player does the jump itself via air_jumps())
	if p._air_jumps_used > _air_used:
		PartyFx.ring_pulse(world(), feet(), Vector3.UP, GOLDEN, 0.3, 1.8, 0.3, 0.2)
		PartyFx.burst(world(), feet(), GOLDEN, 20, 5.0, 0.2, 0.4)
		_double_jump_fx()
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
			_impact_fx(t["center"] as Vector3, _dash_dir)
			_dash = minf(_dash, 0.04)


## A golden ring of flame kicked off the air under the feet, and an afterimage left below.
func _double_jump_fx() -> void:
	var w: Node = world()
	HeroFx.ring(w, feet() + Vector3(0, 0.05, 0), Vector3.UP, Color(1.2, 0.9, 0.3, 0.9), 0.3, 1.6, 0.3, 0.1)
	HeroFx.pop(w, {"amount": 18, "lifetime": 0.35, "shape": "ring", "ring_radius": 0.4, "ring_inner": 0.2,
		"dir": Vector3(1, -0.3, 0), "spread": 180.0, "flatness": 0.8, "speed": Vector2(4.0, 7.0), "damping": Vector2(8.0, 12.0),
		"facing": "velocity", "tex": Fx.Tex.SPARK, "size": Vector2(0.08, 0.5), "color": Color(1.6, 1.3, 0.5)}, feet())
	HeroFx.afterimage(w, get_parent() as Node3D, Color(1.0, 0.8, 0.25), 0.3, Vector3.UP, 1.2)


## Where the dash punch lands: a flash of light, a starburst and a punch ring.
func _impact_fx(at: Vector3, dir: Vector3) -> void:
	var w: Node = world()
	HeroFx.ring(w, at, dir, Color(1.3, 1.1, 0.5, 0.95), 0.2, 2.0, 0.25, 0.12)
	HeroFx.stars(w, at, Color(1.6, 1.4, 0.6), 10, 5.0, 0.55, 0.3)
	HeroFx.sparks(w, at, Color(1.6, 1.3, 0.5), 26, 12.0, dir, 50.0, 0.6)
	HeroFx.flash(w, at, GOLDEN, 8.0, 7.0, 0.3)
	if local and layer != null:
		HeroFx.screen_flash(layer, Color(1.0, 0.95, 0.7), 0.2, 0.15)


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
	_dash_anim(_dash_dir)
	layer.sfx.play("whoosh", 1.0, 1.3)
	fx("dash", {"o": arr(chest()), "d": arr(_dash_dir)})


## The burst of a dash: a speed streak ahead, a puff blown back, a ring punched through the air
## and a golden fist-flash at the front.
static func _dash_fx(parent: Node, o: Vector3, dir: Vector3) -> void:
	PartyFx.streak(parent, o - dir * 1.0, o + dir * 4.5, Color(1.0, 0.9, 0.4), 40, 0.16, 0.35, 0.35, 0.5)
	HeroFx.pop(parent, {"amount": 30, "lifetime": 0.3, "dir": -dir, "spread": 25.0, "speed": Vector2(6.0, 12.0),
		"damping": Vector2(10.0, 14.0), "size": 0.26, "curve": "shrink", "color": Color(1.3, 1.0, 0.35)}, o)
	HeroFx.ring(parent, o + dir * 0.6, dir, Color(1.2, 1.05, 0.55, 0.9), 0.2, 1.3, 0.2, 0.1)
	HeroFx.ring(parent, o + dir * 1.4, dir, Color(1.2, 1.05, 0.55, 0.7), 0.15, 0.9, 0.25, 0.08)
	HeroFx.pop(parent, {"amount": 26, "lifetime": 0.3, "shape": "sphere", "radius": 0.6, "dir": -dir, "spread": 8.0,
		"speed": Vector2(10.0, 16.0), "facing": "velocity", "tex": Fx.Tex.SPARK, "size": Vector2(0.05, 0.9),
		"color": Color(1.3, 1.2, 0.8)}, o + dir * 2.0)
	HeroFx.orb(parent, o + dir * 0.7, Color(1.0, 0.85, 0.4, 0.8), 0.15, 0.55, 0.16)


## The dasher's side (every screen): afterimages trail it for the length of the dash.
func _dash_anim(dir: Vector3) -> void:
	_dash_vis = DASH_TIME + 0.05
	_ghost_t = 0.0
	_vis_dir = dir
	_flare = maxf(_flare, 0.6)


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
	_flare = 1.5
	HeroFx.screen_flash(layer, Color(0.75, 0.9, 1.0), 0.3, 0.3)
	layer.hud.announce(PartyNames.WAVE_SHOUT, WAVE.lerp(Color.WHITE, 0.4))
	layer.sfx.play("beam", 1.2, 0.8)
	PartyFx.shake(layer.level, 0.5 + 0.4 * power)
	player().add_impulse(-dir * (5.0 + 5.0 * power))
	fx("wave", {"o": arr(o), "e": arr(end), "w": width})
	for t: Dictionary in layer.targets_near_segment(o, end, 1.1 + width):
		layer.hit(t, dir * (18.0 + 12.0 * power) + Vector3(0, 6.0 + 3.0 * power, 0), {"st": 0.6, "s": "wave", "quiet": true})
		PartyFx.burst(layer, t["center"] as Vector3, WAVE.lerp(Color.WHITE, 0.5), 30, 7.0, 0.3)


## The Energy Wave's gathering orb, cupped at the hip: a white-hot core in a shimmering blue
## shell, light streaking in from all around, a spinning band, a light.
func _show_orb(on: bool) -> void:
	if on and _orb == null:
		_orb = Node3D.new()
		_orb.position = Vector3(0.5, 0.62, 0.18)
		add_child(_orb)
		HeroFx.mesh_part(_orb, PartyFx.sphere_mesh(0.2, 18), PartyFx.glow_mat(Color(0.95, 0.98, 1.0), 2.0), Vector3.ZERO)
		var shell: ShaderMaterial = HeroFx.flame_mat(Color(0.15, 0.45, 1.0), Color(0.6, 0.9, 1.0), 1.1, 0.12, 5.0, true)
		shell.set_shader_parameter("grow", 0.05)
		shell.set_shader_parameter("freq", 7.0)
		HeroFx.mesh_part(_orb, PartyFx.sphere_mesh(0.48, 18), shell, Vector3.ZERO)
		var band := TorusMesh.new()
		band.inner_radius = 0.56
		band.outer_radius = 0.6
		band.rings = 32
		band.ring_segments = 6
		var bm: MeshInstance3D = HeroFx.mesh_part(_orb, band, PartyFx.glow_mat(Color(0.5, 0.85, 1.0, 0.5), 1.8, true), Vector3.ZERO, Vector3.ONE, Vector3(60, 0, 25))
		bm.set_meta("spin", true)
		_orb.add_child(HeroFx.em({"amount": 50, "lifetime": 0.38, "local": true, "shape": "shell", "radius": 1.6,
			"speed": Vector2(0.0, 0.2), "radial": Vector2(-26.0, -20.0), "facing": "velocity", "tex": Fx.Tex.SPARK,
			"size": Vector2(0.06, 0.45), "curve": "flat", "fixed_fps": 0,
			"colors": PackedColorArray([Color(0.3, 0.6, 1.4, 0.0), Color(0.8, 1.1, 1.6, 1.0), Color(1.4, 1.4, 1.5, 0.0)])}))
		_orb.add_child(HeroFx.em({"amount": 20, "lifetime": 0.25, "local": true, "shape": "sphere", "radius": 0.2,
			"speed": Vector2(0.2, 0.8), "size": 0.35, "curve": "shrink", "color": Color(0.7, 0.9, 1.3)}))
		if not HeroFx.low():
			_orb_light = OmniLight3D.new()
			_orb_light.light_color = WAVE
			_orb_light.omni_range = 5.0
			_orb_light.light_energy = 2.0
			_orb_light.shadow_enabled = false
			_orb.add_child(_orb_light)
		_orb.scale = Vector3.ONE * 0.25
		if is_inside_tree():
			HeroFx.ring(world(), _orb.global_position, Vector3.UP, Color(0.6, 0.85, 1.2, 0.8), 1.2, 0.2, 0.25, 0.06)
	elif not on and _orb != null:
		_orb.queue_free()
		_orb = null
		_orb_light = null


## The beam: it shoots out to its end in a blink, holds (thick, shimmering, a white-hot core)
## and thins away; spiral rings race along it, the ground under it is torn up, and its end
## bursts.
static func _wave_fx(parent: Node, o: Vector3, end: Vector3, width: float) -> void:
	var dir: Vector3 = (end - o).normalized() if o.distance_to(end) > 0.01 else Vector3.FORWARD
	var length: float = o.distance_to(end)
	var layers_def: Array = [
		[Color(1.0, 1.0, 1.0), Color(0.75, 0.92, 1.0), width * 0.45, 2.2, false],
		[Color(0.7, 0.9, 1.0), Color(0.2, 0.55, 1.0), width, 1.2, true],
		[Color(0.35, 0.65, 1.0), Color(0.15, 0.4, 1.0), width * 1.6, 0.9, true],
	]
	for L: Array in layers_def:
		var m: ShaderMaterial = HeroFx.beam_mat(L[0], L[1], float(L[3]), bool(L[4]))
		if bool(L[4]):
			m.set_shader_parameter("edge_alpha", 0.0)
		m.set_shader_parameter("length_m", maxf(length, 1.0))
		var cm: CylinderMesh = PartyFx.cyl_mesh(1.0, 1.0, -1.0, 20)
		cm.cap_top = false
		cm.cap_bottom = false
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		mi.material_override = m
		mi.layers = HeroFx.LAYER
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
		var r: float = float(L[2])
		mi.global_transform = PartyFx.beam_transform(o, o + dir * 0.1, r * 0.3)
		var tw: Tween = mi.create_tween()
		# shoot out
		tw.tween_method(func(k: float) -> void:
			mi.global_transform = PartyFx.beam_transform(o, o + dir * maxf(length * k, 0.1), r * (0.3 + 0.7 * k)), 0.0, 1.0, 0.1).set_ease(Tween.EASE_OUT)
		# hold, pulsing
		tw.tween_method(func(k: float) -> void:
			mi.global_transform = PartyFx.beam_transform(o, end, r * (1.0 + 0.08 * sin(k * 40.0))), 0.0, 1.0, 0.35)
		# thin away
		tw.tween_method(func(k: float) -> void:
			mi.global_transform = PartyFx.beam_transform(o, end, r * (1.0 - k * 0.9))
			m.set_shader_parameter("alpha", 1.0 - k), 0.0, 1.0, 0.3).set_ease(Tween.EASE_IN)
		tw.tween_callback(mi.queue_free)
	# particles along the beam: a shimmer of light and fast streaks
	PartyFx.streak(parent, o, end, Color(0.6, 0.9, 1.0), 110, 0.26, 0.7, width * 1.2, 4.0)
	HeroFx.pop(parent, {"amount": 60, "lifetime": 0.45, "shape": "box", "extents": Vector3(width, width, length * 0.5),
		"dir": Vector3(0, 0, -1), "spread": 5.0, "speed": Vector2(15.0, 30.0), "facing": "velocity", "tex": Fx.Tex.SPARK,
		"size": Vector2(0.06, 1.0), "color": Color(1.2, 1.4, 1.6), "explosiveness": 0.7, "box_aabb": length + 6.0},
		(o + end) * 0.5, PartyFx.facing(dir))
	# spiral rings racing along it
	var n: int = int(length / 3.0)
	for i: int in n:
		HeroFx.ring(parent, o + dir * (1.5 + 3.0 * float(i)), dir, Color(0.45, 0.75, 1.1, 0.7), width * 1.05, width * 1.6, 0.3 + 0.02 * float(i), 0.05)
	# the ground torn up under the beam: dust puffs and debris along its track
	var steps: int = mini(int(length / 2.5), 12)
	for i: int in steps:
		var p: Vector3 = o + dir * (2.0 + 2.5 * float(i))
		var q := PhysicsRayQueryParameters3D.create(p, p + Vector3(0, -3.0 - width, 0), 1)
		var hit: Dictionary = (parent as Node3D).get_world_3d().direct_space_state.intersect_ray(q) if parent is Node3D else {}
		if hit.is_empty():
			continue
		var g: Vector3 = hit["position"]
		HeroFx.smoke(parent, g + Vector3(0, 0.3, 0), Color(0.85, 0.82, 0.78, 0.5), 5, 1.1, 0.9, 2.5)
		if i % 2 == 0:
			HeroFx.pop(parent, {"amount": 6, "lifetime": 0.8, "facing": "mesh", "mesh": Fx.chunk_mesh(0.12), "spread": 40.0,
				"speed": Vector2(3.0, 6.0), "gravity": Vector3(0, -18, 0), "scale": Vector2(0.6, 1.2), "curve": "shrink",
				"spin": Vector2(-400, 400), "angle": Vector2(0, 360), "color": Color(0.55, 0.5, 0.45),
				"fade": PackedFloat32Array([1.0, 1.0])}, g)
	# the muzzle and the end burst
	HeroFx.orb(parent, o, Color(0.6, 0.85, 1.0, 0.8), 0.3, width * 1.3, 0.25)
	HeroFx.ring(parent, o + dir * 0.3, dir, Color(0.8, 0.95, 1.2, 0.9), 0.3, width * 3.0, 0.3, 0.06)
	HeroFx.orb(parent, end, Color(0.6, 0.85, 1.0, 0.8), 0.4, width * 2.0, 0.3)
	HeroFx.fireball(parent, end, 1.8 + width, 20, Color(1.2, 1.3, 1.4), Color(0.5, 0.75, 1.1), Color(0.55, 0.6, 0.7, 0.5))
	HeroFx.sparks(parent, end, Color(1.0, 1.3, 1.6), 36, 12.0, -dir, 80.0, 0.7)
	HeroFx.ring(parent, end, -dir, Color(0.7, 0.9, 1.2, 0.9), 0.4, 3.0 + width, 0.4, 0.06)
	HeroFx.flash(parent, o, WAVE, 10.0, 12.0, 0.5)
	HeroFx.flash(parent, end, WAVE, 8.0, 10.0, 0.5)


# ---- the mirror on a rival's ghost ----------------------------------------------------------

func remote(action: String, d: Dictionary) -> void:
	match action:
		"dash":
			_dash_fx(layer, v3(d.get("o", [])), v3(d.get("d", [])))
			_dash_anim(v3(d.get("d", [])))
			layer.sfx.play_at("whoosh", v3(d.get("o", [])), 0.9, 1.3)
		"charge":
			_charge = 0.0 if bool(d.get("on", false)) else -1.0
			_show_orb(bool(d.get("on", false)))
		"wave":
			_charge = -1.0
			_show_orb(false)
			_flare = 1.5
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


## Ends like the base (multipliers restored and "off" sent at once), but the look powers down:
## the aura sputters out, the hair sinks and loses its glow, a puff of golden smoke.
func finish() -> void:
	if ended:
		return
	ended = true
	on_end()
	if local and layer != null:
		layer.power_finished(self)
	if not is_inside_tree() or _rig == null:
		queue_free()
		return
	var w: Node = world()
	var at: Vector3 = global_position
	var time: float = 0.6
	_flames.emitting = false
	_motes.emitting = false
	_pebbles.emitting = false
	# the aura sputters: flickers, then gone
	var tw: Tween = create_tween()
	tw.tween_method(func(k: float) -> void:
		var fl: float = (1.0 - k) * (0.5 + 0.5 * signf(sin(k * 60.0)))
		_aura_mat.set_shader_parameter("alpha", fl)
, 0.0, 1.0, time * 0.7)
	for i: int in _spikes.size():
		var st: Tween = create_tween()
		st.tween_interval(0.02 * float(i))
		st.tween_property(_spikes[i], "scale", Vector3(1.0, 0.05, 1.0), time * 0.6).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	var ht: Tween = create_tween()
	ht.tween_property(_hair, "scale", Vector3(0.8, 0.3, 0.8), time).set_ease(Tween.EASE_IN)
	ht.tween_callback(queue_free)
	HeroFx.pop(w, {"amount": 24, "lifetime": 0.9, "shape": "sphere", "radius": 0.5, "dir": Vector3.UP, "spread": 50.0,
		"speed": Vector2(0.8, 2.5), "gravity": Vector3(0, 1.0, 0), "facing": "velocity", "tex": Fx.Tex.SPARK,
		"size": Vector2(0.06, 0.24), "explosiveness": 0.5, "color": Color(1.6, 1.3, 0.5),
		"fade": PackedFloat32Array([0.0, 1.0, 0.6, 0.0])}, at + Vector3(0, 0.8, 0))
	HeroFx.smoke(w, at + Vector3(0, 0.9, 0), Color(1.0, 0.92, 0.7, 0.45), 10, 0.9, 0.9, 1.4)
	PartyFx.crackle(w, at + Vector3(0, 0.8, 0), 0.8, BOLT, 5, 0.12)
