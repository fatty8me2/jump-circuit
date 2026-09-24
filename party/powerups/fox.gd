extends PowerUp
## Nine-Tailed Fox: a licking chakra-flame cloak, flame fox ears, glowing red slit eyes and
## whisker marks, and nine living tails (FoxTails: they lag, whip on turns, fan out on jumps,
## stream back at speed and curl when idle). Speed x1.6, jump x1.35.
##  Attack (tap): Fox Claw - a lunging three-streak swipe that KOs the rival it connects with.
##  Attack (hold): charge a Tailed Beast Bomb (the tails arch forward and feed a dark sphere
##  in front of the mouth), release to fire it - a huge explosion that throws everyone in
##  its radius.
## The look: a transformation (flame vortex, the tails bursting out, a roar with a shockwave),
## flame trails while running, and on expiry the cloak burns away into embers.

const CLOAK := Color(1.0, 0.45, 0.06)
const DARK := Color(0.28, 0.05, 0.4)
const CLAW_COOLDOWN: float = 0.45
const CHARGE_TIME: float = 1.2
const BOMB_SPEED: float = 28.0
const HOT := Color(2.4, 1.3, 0.45)
const BOMB_PURPLE := Color(0.62, 0.18, 1.0)

var _t: float = 0.0
var _claw_cd: float = 0.0
var _charge: float = -1.0
var _ball: Node3D
var _ball_core: MeshInstance3D
var _hum: AudioStreamPlayer3D
# the costume
var _rig: HeroFx.Rig
var _tails: FoxTails
var _cloak_mat: ShaderMaterial
var _ear_mat: ShaderMaterial
var _ears: Array[Node3D] = []
var _eyes: Node3D
var _eye_glow: Array[MeshInstance3D] = []
var _eye_trails: Array[GPUParticles3D] = []
var _mouth: Node3D
var _feet_fire: GPUParticles3D
var _flames: GPUParticles3D
var _light: OmniLight3D
var _mouth_open: float = 0.0
var _ear_back: float = 0.0
var _twitch: float = 0.0
var _twitch_t: float = 1.5
var _feed_t: float = 0.0
var _crackle_t: float = 0.0
var _dust_t: float = 0.0
var _full: bool = false


func _init() -> void:
	duration = 10.0
	takes_attack = true


func mods() -> Vector3:
	return Vector3(1.6, 1.35, 1.0)


func build_look() -> void:
	_rig = HeroFx.Rig.new()
	add_child(_rig)
	# chakra cloak: a licking flame shell hugging the body
	_cloak_mat = HeroFx.flame_mat(Color(1.0, 0.22, 0.0), Color(1.0, 0.55, 0.1), 1.5, 0.07, 2.8)
	_cloak_mat.set_shader_parameter("stretch", 0.22)
	_cloak_mat.set_shader_parameter("freq", 5.0)
	var shell: MeshInstance3D = HeroFx.mesh_part(_rig, PartyFx.sphere_mesh(0.5, 24), _cloak_mat, Vector3(0, 0.62, 0), Vector3(0.92, 1.0, 0.92))
	shell.set_meta("no_ghost", true)
	# flame tongues licking up off the cloak (world space: they stream behind a runner)
	_flames = HeroFx.em({"amount": 30, "lifetime": 0.38, "shape": "ring", "ring_radius": 0.4, "ring_inner": 0.25,
		"ring_height": 0.5, "dir": Vector3.UP, "spread": 12.0, "speed": Vector2(1.0, 2.2), "gravity": Vector3(0, 2.0, 0),
		"facing": "velocity", "tex": Fx.Tex.SPARK, "size": Vector2(0.3, 0.5), "curve": "shrink", "fixed_fps": 0,
		"additive": false,
		"colors": PackedColorArray([Color(1.3, 0.9, 0.3, 0.0), Color(1.2, 0.45, 0.04, 0.85), Color(0.8, 0.1, 0.0, 0.0)])})
	_flames.position = Vector3(0, 0.45, 0)
	_rig.add_child(_flames)
	# chakra bubbles popping on the surface, and embers drifting up
	var bubbles: GPUParticles3D = HeroFx.em({"amount": 12, "lifetime": 0.5, "shape": "shell", "radius": 0.48,
		"speed": Vector2(0.1, 0.4), "dir": Vector3.UP, "spread": 60.0, "size": 0.2, "curve": "pop", "local": true,
		"color": Color(2.2, 1.0, 0.25, 0.8)})
	bubbles.position = Vector3(0, 0.65, 0)
	_rig.add_child(bubbles)
	var embers: GPUParticles3D = HeroFx.em({"amount": 14, "lifetime": 1.1, "shape": "sphere", "radius": 0.55,
		"dir": Vector3.UP, "spread": 30.0, "speed": Vector2(0.8, 2.2), "gravity": Vector3(0, 0.8, 0),
		"facing": "velocity", "tex": Fx.Tex.SPARK, "size": Vector2(0.05, 0.16), "turbulence": 0.8,
		"color": Color(1.6, 0.75, 0.2), "fade": PackedFloat32Array([0.0, 1.0, 0.7, 0.0])})
	embers.position = Vector3(0, 0.55, 0)
	_rig.add_child(embers)
	# a trail of fire off the feet while running flat out
	_feet_fire = HeroFx.em({"amount": 36, "lifetime": 0.4, "shape": "box", "extents": Vector3(0.22, 0.05, 0.1),
		"dir": Vector3.UP, "spread": 25.0, "speed": Vector2(0.6, 1.8), "gravity": Vector3(0, 2.5, 0), "size": 0.34,
		"curve": "shrink", "fixed_fps": 0, "emitting": false, "box_aabb": 8.0, "additive": false,
		"tex": Fx.Tex.SMOKE, "angle": Vector2(0, 360),
		"colors": PackedColorArray([Color(2.0, 1.4, 0.45, 0.9), Color(1.8, 0.45, 0.04, 0.75), Color(0.3, 0.06, 0.03, 0.0)])})
	_feet_fire.position = Vector3(0, 0.1, 0.12)
	_rig.add_child(_feet_fire)
	# flame fox ears on pivots (they twitch, and flatten back for a roar or a sprint)
	_ear_mat = HeroFx.energy_mat(Color(1.0, 0.42, 0.05), Color(1.0, 0.9, 0.55), 1.4, 3.0)
	var ear_rim: ShaderMaterial = HeroFx.flame_mat(Color(1.0, 0.3, 0.02), Color(1.0, 0.75, 0.3), 1.6, 0.05, 3.0)
	ear_rim.set_shader_parameter("grow", 0.012)
	var inner: StandardMaterial3D = PartyFx.glow_mat(Color(0.5, 0.06, 0.02), 1.0)
	for sx: float in [-1.0, 1.0]:
		var piv := Node3D.new()
		piv.position = Vector3(sx * 0.2, 0.93, 0.03)
		piv.rotation_degrees = Vector3(0, 0, -sx * 24.0)
		_rig.add_child(piv)
		HeroFx.mesh_part(piv, PartyFx.cone_mesh(0.13, 0.38, 10), _ear_mat, Vector3(0, 0.17, 0), Vector3(1, 1, 0.62))
		var rim: MeshInstance3D = HeroFx.mesh_part(piv, PartyFx.cone_mesh(0.14, 0.42, 10), ear_rim, Vector3(0, 0.18, 0), Vector3(1, 1, 0.7))
		rim.set_meta("no_ghost", true)
		HeroFx.mesh_part(piv, PartyFx.cone_mesh(0.075, 0.25, 8), inner, Vector3(0, 0.13, -0.045), Vector3(1, 1, 0.35))
		piv.scale = Vector3.ONE * 0.01
		_ears.append(piv)
	# red slit eyes glaring through the visor, and whisker marks on the cheeks
	_eyes = Node3D.new()
	_rig.add_child(_eyes)
	var eye: StandardMaterial3D = PartyFx.glow_mat(Color(1.0, 0.1, 0.04), 2.2)
	var slit: StandardMaterial3D = PartyFx.glow_mat(Color(0.05, 0.0, 0.0), 1.0)
	for sx: float in [-1.0, 1.0]:
		var e := Node3D.new()
		e.position = Vector3(sx * 0.112, 0.752, -0.4)
		e.rotation_degrees = Vector3(0, 0, sx * 22.0)
		_eyes.add_child(e)
		HeroFx.mesh_part(e, PartyFx.sphere_mesh(0.5, 12), eye, Vector3.ZERO, Vector3(0.15, 0.12, 0.06))
		HeroFx.mesh_part(e, PartyFx.box_mesh(Vector3(0.022, 0.1, 0.01)), slit, Vector3(0, 0, -0.034), Vector3.ONE, Vector3(0, 0, -sx * 22.0))
		var g: MeshInstance3D = HeroFx.glow_sprite(e, Color(1.6, 0.12, 0.03, 0.4), 0.26, Fx.Tex.DOT, Vector3(0, 0, 0.01))
		g.set_meta("no_ghost", true)
		_eye_glow.append(g)
		# red streaks off the eyes at speed
		var tr: GPUParticles3D = HeroFx.em({"amount": 16, "lifetime": 0.22, "speed": Vector2.ZERO, "spread": 0.0,
			"size": 0.1, "curve": "shrink", "fixed_fps": 0, "emitting": false, "box_aabb": 8.0,
			"color": Color(2.4, 0.25, 0.08, 0.9)})
		tr.position = Vector3(0, 0, -0.03)
		e.add_child(tr)
		_eye_trails.append(tr)
	var mark: StandardMaterial3D = PartyFx.glow_mat(Color(0.12, 0.02, 0.01), 1.0)
	for sx: float in [-1.0, 1.0]:
		var cheek := Node3D.new()
		var n := Vector3(sx * 0.78, 0.0, -0.62).normalized()
		cheek.position = Vector3(0, 0.6, 0) + Vector3(n.x * 0.395, 0.0, n.z * 0.395)
		cheek.basis = Basis.looking_at(-n, Vector3.UP)
		_rig.add_child(cheek)
		for k: int in 3:
			HeroFx.mesh_part(cheek, PartyFx.box_mesh(Vector3(0.14, 0.02, 0.012)), mark, Vector3(0, 0.055 - 0.05 * float(k), 0), Vector3.ONE, Vector3(0, 0, sx * (10.0 - 10.0 * float(k))))
	# a snarling maw (opens for the roar, the claw and the bomb)
	_mouth = Node3D.new()
	_mouth.position = Vector3(0, 0.605, -0.39)
	_rig.add_child(_mouth)
	HeroFx.mesh_part(_mouth, PartyFx.sphere_mesh(0.5, 14), PartyFx.glow_mat(Color(0.35, 0.02, 0.0), 1.0), Vector3.ZERO, Vector3(0.2, 0.08, 0.05))
	var fang: StandardMaterial3D = PartyFx.glow_mat(Color(1.0, 0.95, 0.9), 1.6)
	for sx: float in [-1.0, 1.0]:
		HeroFx.mesh_part(_mouth, PartyFx.cone_mesh(0.016, 0.05, 6), fang, Vector3(sx * 0.055, 0.02, -0.012), Vector3.ONE, Vector3(180, 0, 0))
	_mouth.scale = Vector3(1, 0.01, 1)
	# the nine tails
	_tails = FoxTails.new()
	_tails.body = body
	_tails.position = Vector3(0, 0.42, 0.3)
	_rig.add_child(_tails)
	# the cloak lights its surroundings (not on Low)
	if not HeroFx.low():
		_light = OmniLight3D.new()
		_light.light_color = Color(1.0, 0.5, 0.15)
		_light.light_energy = 0.0
		_light.omni_range = 3.5
		_light.shadow_enabled = false
		_light.position = Vector3(0, 0.8, 0.2)
		_rig.add_child(_light)
	if is_inside_tree():
		_transform_in()
	else:
		_tails.grow = 1.0


## The transformation: a vortex of chakra flame swirls up the body, the cloak ignites, the
## tails burst out and the fox roars (shockwave, flash).
func _transform_in() -> void:
	var w: Node = world()
	var at: Vector3 = global_position
	var fwd: Vector3 = -global_basis.z.normalized()
	_cloak_mat.set_shader_parameter("alpha", 0.0)
	_tails.grow = 0.0
	# the vortex: a spinning funnel of flame streaks rising round the body
	var spin := Node3D.new()
	w.add_child(spin)
	spin.global_position = at
	var vortex: GPUParticles3D = HeroFx.em({"amount": 90, "lifetime": 0.55, "one_shot": true, "explosiveness": 0.35,
		"local": true, "shape": "ring", "ring_radius": 1.1, "ring_inner": 0.8, "ring_height": 0.1, "dir": Vector3.UP,
		"spread": 8.0, "speed": Vector2(5.0, 9.0), "radial": Vector2(-6.0, -4.0), "facing": "velocity", "tex": Fx.Tex.SPARK,
		"size": Vector2(0.16, 0.7), "curve": "shrink", "fixed_fps": 0, "emitting": false,
		"colors": PackedColorArray([Color(2.5, 1.8, 0.7), Color(2.2, 0.7, 0.1), Color(0.9, 0.1, 0.0, 0.0)])})
	spin.add_child(vortex)
	vortex.emitting = true
	var tw: Tween = spin.create_tween()
	tw.tween_property(spin, "rotation:y", TAU * 2.2, 0.9).set_ease(Tween.EASE_OUT)
	tw.tween_callback(spin.queue_free)
	# a pillar of flame
	var pillar_mat: ShaderMaterial = HeroFx.flame_mat(Color(1.0, 0.25, 0.0), Color(1.0, 0.6, 0.15), 1.5, 0.1, 5.0)
	var pillar := MeshInstance3D.new()
	var pm: CylinderMesh = PartyFx.cyl_mesh(0.5, 1.0, 0.25, 20)
	pm.cap_top = false
	pm.cap_bottom = false
	pillar.mesh = pm
	pillar.material_override = pillar_mat
	pillar.layers = HeroFx.LAYER
	pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	w.add_child(pillar)
	pillar.global_position = at + Vector3(0, 0.1, 0)
	pillar.scale = Vector3(0.6, 0.1, 0.6)
	var ptw: Tween = pillar.create_tween().set_parallel(true)
	ptw.tween_property(pillar, "scale", Vector3(1.9, 3.6, 1.9), 0.55).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	ptw.tween_property(pillar, "position:y", pillar.position.y + 1.6, 0.55).set_ease(Tween.EASE_OUT)
	ptw.tween_method(func(v: float) -> void: pillar_mat.set_shader_parameter("alpha", v), 1.0, 0.0, 0.6).set_ease(Tween.EASE_IN)
	ptw.chain().tween_callback(pillar.queue_free)
	HeroFx.ground_ring(w, at, Color(2.2, 0.8, 0.15), 2.2, 0.45)
	HeroFx.dust_ring(w, at, Color(0.95, 0.8, 0.6, 0.6), 1.2, 16, 6.0)
	HeroFx.flash(w, at + Vector3(0, 1, 0), CLOAK, 7.0, 8.0, 0.6)
	# the cloak ignites, the ears pop, the tails burst out
	HeroFx.tween_param(self, _cloak_mat, "alpha", 0.0, 1.0, 0.35)
	var st: Tween = create_tween()
	st.tween_interval(0.12)
	st.tween_property(_tails, "grow", 1.18, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	st.tween_property(_tails, "grow", 1.0, 0.25).set_ease(Tween.EASE_IN_OUT)
	for i: int in _ears.size():
		var et: Tween = create_tween()
		et.tween_interval(0.1 + 0.05 * float(i))
		et.tween_property(_ears[i], "scale", Vector3.ONE, 0.28).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	# the roar
	var rt: Tween = create_tween()
	rt.tween_interval(0.3)
	rt.tween_callback(func() -> void: _roar(fwd))
	rt.tween_interval(0.55)
	rt.tween_callback(func() -> void:
		if _tails.pose == "roar":
			_tails.pose = "")


func _roar(fwd: Vector3) -> void:
	if not is_inside_tree():
		return
	_tails.pose = "roar"
	_mouth_open = 1.0
	_ear_back = 1.0
	var w: Node = world()
	var at: Vector3 = global_position
	var head: Vector3 = at + Vector3(0, 0.75, 0) + fwd * 0.4
	for k: int in 3:
		HeroFx.ring(w, head + fwd * (0.3 + 0.6 * float(k)), fwd, Color(1.1, 0.45 - 0.1 * float(k), 0.04, 0.85), 0.3 + 0.2 * float(k), 1.3 + 0.5 * float(k), 0.3 + 0.08 * float(k), 0.1)
	HeroFx.ring(w, at + Vector3(0, 0.12, 0), Vector3.UP, Color(1.1, 0.4, 0.04, 0.9), 0.4, 4.0, 0.45, 0.06)
	HeroFx.ground_ring(w, at, Color(1.6, 0.6, 0.15), 3.2, 0.5)
	HeroFx.dust_ring(w, at, Color(0.9, 0.8, 0.65, 0.6), 1.6, 20, 9.0)
	HeroFx.burst(w, at + Vector3(0, 0.8, 0), Color(2.4, 1.1, 0.25), 40, 9.0, 0.3, 0.6)
	HeroFx.sparks(w, at + Vector3(0, 0.8, 0), Color(2.6, 1.6, 0.6), 30, 11.0, Vector3.UP, 110.0)
	HeroFx.flash(w, at + Vector3(0, 1.2, 0), Color(1.0, 0.55, 0.15), 10.0, 10.0, 0.5)
	for e: MeshInstance3D in _eye_glow:
		e.scale = Vector3.ONE * 2.6
		create_tween().tween_property(e, "scale", Vector3.ONE, 0.5).set_ease(Tween.EASE_OUT)
	if local and layer != null:
		HeroFx.screen_flash(layer, Color(1.0, 0.55, 0.15), 0.35, 0.4)


func _process(dt: float) -> void:
	_t += dt
	if _ball != null:
		_ball.rotation.y += dt * 6.0
		var s: float = 0.2 + 0.8 * clampf(_charge / CHARGE_TIME, 0.0, 1.0)
		_ball.scale = _ball.scale.lerp(Vector3.ONE * s, 1.0 - exp(-12.0 * dt))
		if _ball_core != null:
			_ball_core.scale = Vector3.ONE * (0.9 + sin(_t * 30.0) * 0.08)
		_charge_fx(dt)
	if _rig == null or not is_inside_tree():
		return
	var vel: Vector3 = _vel()
	var hs: float = Vector2(vel.x, vel.z).length()
	var grounded: bool = _grounded()
	# ears: twitch now and then, flatten back at speed or in a roar
	_twitch_t -= dt
	if _twitch_t <= 0.0:
		_twitch_t = randf_range(1.2, 3.0)
		_twitch = 1.0
	_twitch = maxf(_twitch - dt * 6.0, 0.0)
	_ear_back = maxf(_ear_back - dt * 1.6, clampf((hs - 8.0) / 8.0, 0.0, 0.8))
	for i: int in _ears.size():
		var sx: float = -1.0 if i == 0 else 1.0
		var tw_k: float = sin(_twitch * PI) * (1.0 if i == int(_t) % 2 else 0.3)
		_ears[i].rotation = Vector3(deg_to_rad(-_ear_back * 55.0 + tw_k * 14.0), 0, deg_to_rad(-sx * (24.0 + tw_k * 10.0 + _ear_back * 12.0)))
	# the maw eases shut
	_mouth_open = maxf(_mouth_open - dt * 1.8, 0.7 if _charge >= 0.0 else 0.0)
	_mouth.scale = Vector3(1.0, maxf(_mouth_open, 0.01), 1.0)
	# flames trail off the feet and red streaks off the eyes when flat out
	var fast: bool = hs > 7.0
	_feet_fire.emitting = fast and grounded and not ended
	_feet_fire.amount_ratio = clampf((hs - 6.0) / 8.0, 0.3, 1.0)
	for tr: GPUParticles3D in _eye_trails:
		tr.emitting = hs > 9.0 and not ended
	# the eyes pulse; the cloak flickers its light
	var pulse: float = 1.0 + sin(_t * 7.0) * 0.12
	for e: MeshInstance3D in _eye_glow:
		e.scale = e.scale.lerp(Vector3.ONE * pulse, 1.0 - exp(-10.0 * dt))
	if _light != null:
		var want: float = 0.0 if ended else 1.1 + sin(_t * 17.0) * 0.25 + sin(_t * 7.3) * 0.2 + (1.2 if _charge >= 0.0 else 0.0)
		_light.light_energy = lerpf(_light.light_energy, want, 1.0 - exp(-12.0 * dt))


func _vel() -> Vector3:
	if body is Player:
		return (body as Player).velocity
	if body != null and body.has_method("velocity"):
		return body.call("velocity")
	return Vector3.ZERO


func _grounded() -> bool:
	if body is Player:
		return (body as Player).grounded
	if body != null and body.has_method("is_grounded"):
		return bool(body.call("is_grounded"))
	return true


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
	_claw_anim(dir)
	layer.sfx.play("slash", 1.0, 0.9)
	fx("claw", {"o": arr(o), "d": arr(dir)})
	for t: Dictionary in layer.targets_in_cone(o, dir, 3.0, 0.4):
		layer.hit(t, dir * 20.0 + Vector3(0, 10, 0), {"ko": true, "s": "claw"})


## Three raking chakra claw streaks (a bright head sweeping across, white-hot at the core),
## the ghost of a huge paw behind them, slash sparks and a ring where they meet.
static func _claw_fx(parent: Node, o: Vector3, dir: Vector3) -> void:
	var b := PartyFx.facing(dir)
	var tilt := Basis(dir, deg_to_rad(-55.0)) * b
	var c: Vector3 = o + dir * 0.15
	# the huge faint paw smear behind the claws
	HeroFx.slash(parent, c, tilt, 1.45, -1.25, 1.15, Color(1.0, 0.25, 0.02, 0.4), 0.55, 0.1, 0.3, Color(1.1, 0.5, 0.08, 0.55))
	# three raking talons: concentric, bright-cored, drawn one after another
	for i: int in 3:
		HeroFx.slash(parent, c, tilt, 1.15 + 0.2 * float(i), -1.05 - 0.05 * float(i), 1.0, Color(1.2, 0.32 + 0.1 * float(i), 0.02), 0.11, 0.06 + 0.02 * float(i), 0.26, Color(1.4, 1.25, 1.0))
	var hit: Vector3 = o + dir * 1.5
	HeroFx.sparks(parent, hit, Color(2.0, 1.0, 0.3), 26, 12.0, (dir + (b * Vector3(1, 0, 0)) * 0.6).normalized(), 40.0, 0.55)
	HeroFx.pop(parent, {"amount": 22, "lifetime": 0.4, "spread": 45.0, "dir": dir, "speed": Vector2(4.0, 9.0),
		"damping": Vector2(8.0, 12.0), "size": 0.3, "curve": "shrink", "color": Color(1.6, 0.55, 0.08)}, hit)
	HeroFx.flash(parent, hit, Color(1.0, 0.5, 0.15), 5.0, 6.0, 0.25)


## The fox's side of a claw (on every screen): a snarl, the tails whip back, a smear of
## afterimage behind the lunge.
func _claw_anim(dir: Vector3) -> void:
	if not is_inside_tree():
		return
	_mouth_open = 1.0
	_ear_back = 1.0
	if _tails != null:
		_tails.whip(-dir * 9.0 + Vector3(0, 3.0, 0))
	var pv: Node3D = get_parent() as Node3D
	HeroFx.afterimage(world(), pv, Color(1.0, 0.4, 0.05), 0.28, dir)
	var tw: Tween = create_tween()
	tw.tween_interval(0.05)
	tw.tween_callback(func() -> void: HeroFx.afterimage(world(), pv, Color(1.0, 0.25, 0.02), 0.22, dir, 1.2))


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
	_launch_fx(layer, o, dir, power)
	_launch_anim(dir)
	HeroFx.screen_flash(layer, Color(0.85, 0.55, 1.0), 0.28, 0.3)
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
		# a near-black core with a violet rim, wrapped in licking dark-violet flame
		var core_mat: ShaderMaterial = HeroFx.energy_mat(Color(0.05, 0.0, 0.08), Color(0.75, 0.3, 1.0), 1.0, 6.0)
		_ball_core = HeroFx.mesh_part(_ball, PartyFx.sphere_mesh(0.5, 20), core_mat, Vector3.ZERO)
		var shell_mat: ShaderMaterial = HeroFx.flame_mat(Color(0.3, 0.02, 0.5), Color(1.2, 0.4, 1.6), 1.4, 0.16, 5.0, true)
		shell_mat.set_shader_parameter("freq", 6.0)
		shell_mat.set_shader_parameter("grow", 0.08)
		HeroFx.mesh_part(_ball, PartyFx.sphere_mesh(0.62, 20), shell_mat, Vector3.ZERO)
		# a spinning band of crackling energy
		var band := TorusMesh.new()
		band.inner_radius = 0.7
		band.outer_radius = 0.76
		band.rings = 32
		band.ring_segments = 6
		var bm: MeshInstance3D = HeroFx.mesh_part(_ball, band, PartyFx.glow_mat(Color(0.8, 0.2, 1.0, 0.45), 1.6, true), Vector3.ZERO, Vector3.ONE, Vector3(70, 0, 20))
		bm.set_meta("spin", true)
		# chakra sucked in from all around (streaks racing to the centre)
		_ball.add_child(HeroFx.em({"amount": 60, "lifetime": 0.42, "local": true, "shape": "shell", "radius": 2.2,
			"speed": Vector2(0.0, 0.2), "radial": Vector2(-34.0, -26.0), "facing": "velocity", "tex": Fx.Tex.SPARK,
			"size": Vector2(0.07, 0.5), "curve": "flat", "fixed_fps": 0,
			"colors": PackedColorArray([Color(0.6, 0.2, 1.4, 0.0), Color(1.6, 0.5, 2.2, 1.0), Color(2.4, 0.4, 0.6, 0.0)])}))
		# dark wisps folding into it
		_ball.add_child(HeroFx.em({"amount": 18, "lifetime": 0.6, "local": true, "shape": "shell", "radius": 1.3,
			"speed": Vector2(0.0, 0.1), "radial": Vector2(-8.0, -6.0), "tex": Fx.Tex.SMOKE, "additive": false,
			"size": 0.5, "curve": "shrink", "angle": Vector2(0, 360), "color": Color(0.08, 0.0, 0.12, 0.75),
			"fade": PackedFloat32Array([0.0, 0.8, 0.6])}))
		if not HeroFx.low():
			var l := OmniLight3D.new()
			l.light_color = Color(0.7, 0.3, 1.0)
			l.light_energy = 2.5
			l.omni_range = 4.5
			l.shadow_enabled = false
			_ball.add_child(l)
		_ball.scale = Vector3.ONE * 0.2
		_full = false
		if _tails != null:
			_tails.pose = "charge"
		_mouth_open = 1.0
		if is_inside_tree():
			HeroFx.ring(world(), global_position + Vector3(0, 0.1, 0), Vector3.UP, Color(0.6, 0.2, 1.0, 0.7), 0.3, 1.8, 0.4, 0.05)
	elif not on and _ball != null:
		_ball.queue_free()
		_ball = null
		_ball_core = null
		if _tails != null and _tails.pose == "charge":
			_tails.pose = ""


## Per-frame charging look (both screens): chakra blobs flying from the tail tips into the
## sphere, crackling arcs, pressure rings in the dust, a ping when it is fully charged.
func _charge_fx(dt: float) -> void:
	if _ball == null or not is_inside_tree():
		return
	var k: float = clampf(_charge / CHARGE_TIME, 0.0, 1.0)
	var at: Vector3 = _ball.global_position
	for c: Node in _ball.get_children():
		if c.has_meta("spin"):
			(c as Node3D).rotate_object_local(Vector3.UP, dt * 14.0)
	_feed_t -= dt
	if _feed_t <= 0.0 and _tails != null:
		_feed_t = lerpf(0.07, 0.035, k) / HeroFx.density()
		var red: bool = randf() < 0.55
		_feed(_tails.tip(randi() % FoxTails.TAILS), Color(2.4, 0.3, 0.15) if red else Color(0.4, 0.6, 2.4))
	_crackle_t -= dt
	if _crackle_t <= 0.0:
		_crackle_t = lerpf(0.16, 0.05, k)
		PartyFx.crackle(world(), at, 0.45 + 0.35 * k, Color(0.9, 0.55, 1.0), 4, 0.07)
	_dust_t -= dt
	if _dust_t <= 0.0:
		_dust_t = lerpf(0.4, 0.22, k)
		HeroFx.ring(world(), global_position + Vector3(0, 0.1, 0), Vector3.UP, Color(0.55, 0.18, 1.0, 0.55), 0.5, 1.2 + 1.3 * k, 0.35, 0.04)
		if k > 0.5:
			HeroFx.dust_ring(world(), global_position, Color(0.8, 0.72, 0.8, 0.5), 0.8, 8, 4.0 + 4.0 * k)
	if k >= 1.0 and not _full:
		_full = true
		HeroFx.burst(world(), at, Color(1.8, 0.8, 2.4), 26, 5.0, 0.22, 0.4)
		HeroFx.ring(world(), at, Vector3.UP, Color(0.85, 0.45, 1.2, 0.9), 0.4, 2.0, 0.3, 0.06)
		HeroFx.flash(world(), at, Color(0.8, 0.4, 1.0), 6.0, 6.0, 0.3)


## A blob of red or blue chakra flying from a tail tip into the sphere.
func _feed(from: Vector3, color: Color) -> void:
	var blob := MeshInstance3D.new()
	blob.mesh = PartyFx.sphere_mesh(0.09, 8)
	blob.material_override = PartyFx.glow_mat(Color(color.r, color.g, color.b, 1.0), 1.0)
	blob.layers = HeroFx.LAYER
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world().add_child(blob)
	blob.global_position = from
	var ball: WeakRef = weakref(_ball)
	var tw: Tween = blob.create_tween()
	tw.tween_method(func(k: float) -> void:
		var bn: Node3D = ball.get_ref() as Node3D
		if bn != null and bn.is_inside_tree():
			blob.global_position = from.lerp(bn.global_position, k * k)
			blob.scale = Vector3.ONE * (1.0 - k * 0.7), 0.0, 1.0, 0.22)
	tw.tween_callback(blob.queue_free)


## Launch: the sphere bursts out of the maw - a heavy flash, rings along the shot, sparks.
static func _launch_fx(parent: Node, o: Vector3, dir: Vector3, power: float) -> void:
	HeroFx.orb(parent, o, Color(0.8, 0.45, 1.0, 0.6), 0.3, 0.9 + 0.5 * power, 0.18)
	for k: int in 3:
		HeroFx.ring(parent, o + dir * (0.4 + 0.9 * float(k)), dir, Color(0.75, 0.35, 1.1, 0.8), 0.4, 1.3 + 0.45 * float(k), 0.3 + 0.06 * float(k), 0.06)
	HeroFx.sparks(parent, o, Color(1.8, 0.8, 2.4), 30, 14.0, dir, 30.0, 0.7)
	HeroFx.pop(parent, {"amount": 24, "lifetime": 0.5, "spread": 60.0, "dir": -dir, "speed": Vector2(2.0, 6.0),
		"damping": Vector2(5.0, 8.0), "tex": Fx.Tex.SMOKE, "additive": false, "size": 0.7, "curve": "puff",
		"angle": Vector2(0, 360), "color": Color(0.12, 0.02, 0.16, 0.7), "fade": PackedFloat32Array([0.0, 0.8, 0.0])}, o)
	HeroFx.flash(parent, o, Color(0.8, 0.45, 1.0), 12.0, 10.0, 0.4)


func _launch_anim(dir: Vector3) -> void:
	if not is_inside_tree():
		return
	_mouth_open = 1.0
	_ear_back = 1.0
	if _tails != null:
		_tails.pose = ""
		_tails.whip(-dir * 12.0)


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
	var core_mat: ShaderMaterial = HeroFx.energy_mat(Color(0.05, 0.0, 0.08), Color(0.8, 0.35, 1.0), 1.0, 8.0)
	HeroFx.mesh_part(pr, PartyFx.sphere_mesh(r, 18), core_mat, Vector3.ZERO)
	var shell_mat: ShaderMaterial = HeroFx.flame_mat(Color(0.4, 0.05, 0.7), Color(1.0, 0.5, 0.95), 2.4, 0.2, 6.0)
	shell_mat.set_shader_parameter("grow", 0.1)
	HeroFx.mesh_part(pr, PartyFx.sphere_mesh(r * 1.3, 18), shell_mat, Vector3.ZERO)
	# a comet tail: violet flame, dark smoke and sparks left behind
	pr.add_child(HeroFx.em({"amount": 60, "lifetime": 0.4, "size": 0.55 * (0.6 + power), "shape": "sphere",
		"radius": r * 0.8, "speed": Vector2(0.1, 0.8), "spread": 180.0, "curve": "shrink", "fixed_fps": 0, "box_aabb": 20.0,
		"colors": PackedColorArray([Color(1.8, 0.9, 2.4, 0.9), Color(0.7, 0.1, 1.2, 0.6), Color(0.1, 0.0, 0.2, 0.0)])}))
	pr.add_child(HeroFx.em({"amount": 22, "lifetime": 0.7, "size": 0.8 * (0.6 + power), "shape": "sphere",
		"radius": r * 0.5, "speed": Vector2(0.1, 0.6), "tex": Fx.Tex.SMOKE, "additive": false, "curve": "puff",
		"angle": Vector2(0, 360), "fixed_fps": 0, "box_aabb": 20.0, "color": Color(0.1, 0.02, 0.14, 0.6),
		"fade": PackedFloat32Array([0.0, 0.7, 0.0])}))
	pr.add_child(HeroFx.em({"amount": 24, "lifetime": 0.3, "size": Vector2(0.06, 0.4), "shape": "shell",
		"radius": r * 1.5, "speed": Vector2(0.0, 0.2), "radial": Vector2(-14.0, -10.0), "facing": "velocity",
		"tex": Fx.Tex.SPARK, "local": true, "color": Color(2.4, 0.6, 1.4), "box_aabb": 4.0}))
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


## The detonation: a dark implosion, then a violet dome of flame swallowing the blast radius
## with an orange fireball inside, ground rings, debris, a pillar of smoke and embers.
static func _boom_fx(layer_ref: PartyLayer, pos: Vector3, radius: float) -> void:
	# 1. the flash: a white-hot violet core
	HeroFx.orb(layer_ref, pos, Color(1.0, 0.85, 1.0, 1.0), 0.4, radius * 0.42, 0.14)
	# 2. a dark sphere with a hot violet rim swallows the blast radius
	HeroFx.dome(layer_ref, pos, Color(0.08, 0.0, 0.16), Color(0.95, 0.4, 1.3), radius * 0.62, 0.22, 0.5, true, 1.25, 0.55)
	# 3. a fireball boils out of it, glowing chakra shards and sparks fly
	HeroFx.fireball(layer_ref, pos, radius * 0.55, 30, Color(1.4, 1.2, 0.8), Color(1.2, 0.45, 0.05), Color(0.35, 0.2, 0.4, 0.55))
	HeroFx.burst(layer_ref, pos, Color(1.2, 0.45, 1.5), 36, radius * 2.4, 0.45, 0.5)
	HeroFx.sparks(layer_ref, pos, Color(1.8, 0.9, 2.0), 40, radius * 4.0, Vector3.UP, 180.0, 0.7)
	# 4. the shockwave across the ground
	HeroFx.ground_ring(layer_ref, pos + Vector3(0, -0.45, 0), Color(0.8, 0.35, 1.1), radius * 1.35, 0.5)
	HeroFx.ground_ring(layer_ref, pos + Vector3(0, -0.4, 0), Color(1.1, 0.55, 0.12), radius * 0.85, 0.35)
	HeroFx.ring(layer_ref, pos + Vector3(0, -0.35, 0), Vector3.UP, Color(0.9, 0.5, 1.2, 0.9), 0.5, radius * 1.25, 0.45, 0.025)
	HeroFx.flash(layer_ref, pos, Color(0.8, 0.45, 1.0), 12.0, radius * 4.0, 0.55)
	HeroFx.dust_ring(layer_ref, pos + Vector3(0, -0.5, 0), Color(0.75, 0.68, 0.7, 0.7), radius * 0.6, 26, radius * 2.6)
	HeroFx.pop(layer_ref, {"amount": 16, "lifetime": 1.0, "facing": "mesh", "mesh": Fx.chunk_mesh(0.18), "spread": 65.0,
		"speed": Vector2(radius * 1.2, radius * 2.4), "gravity": Vector3(0, -22, 0), "scale": Vector2(0.6, 1.4),
		"curve": "shrink", "spin": Vector2(-400, 400), "angle": Vector2(0, 360), "color": Color(0.4, 0.3, 0.35),
		"fade": PackedFloat32Array([1.0, 1.0])}, pos)
	HeroFx.pop(layer_ref, {"amount": 14, "lifetime": 1.8, "facing": "mesh", "mesh": HeroFx.soft_quad(Fx.Tex.SMOKE, false, radius * 0.45),
		"shape": "sphere", "radius": radius * 0.25, "dir": Vector3.UP, "spread": 25.0, "speed": Vector2(2.0, 5.0),
		"damping": Vector2(1.5, 2.5), "curve": "puff", "angle": Vector2(0, 360), "spin": Vector2(-30, 30),
		"color": Color(0.35, 0.25, 0.4, 0.45), "fade": PackedFloat32Array([0.0, 0.7, 0.4, 0.0]), "explosiveness": 0.6}, pos)
	HeroFx.pop(layer_ref, {"amount": 30, "lifetime": 1.6, "shape": "sphere", "radius": radius * 0.5, "dir": Vector3.UP,
		"spread": 60.0, "speed": Vector2(1.0, 4.0), "gravity": Vector3(0, 1.5, 0), "facing": "velocity", "tex": Fx.Tex.SPARK,
		"size": Vector2(0.06, 0.2), "turbulence": 1.0, "explosiveness": 0.5, "color": Color(2.6, 1.2, 0.5),
		"fade": PackedFloat32Array([0.0, 1.0, 0.8, 0.0])}, pos)
	layer_ref.sfx.play_at("boom", pos, 1.3, 0.8)
	var me: Vector3 = layer_ref.player.global_position
	PartyFx.shake(layer_ref.level, clampf(1.2 - me.distance_to(pos) / (radius * 4.0), 0.0, 0.9))
	if me.distance_to(pos) < radius * 2.5:
		HeroFx.screen_flash(layer_ref, Color(0.9, 0.6, 1.0), 0.3 * clampf(1.5 - me.distance_to(pos) / (radius * 2.0), 0.3, 1.0), 0.4)


# ---- the mirror on a rival's ghost ----------------------------------------------------------

func remote(action: String, d: Dictionary) -> void:
	match action:
		"claw":
			_claw_fx(layer, v3(d.get("o", [])), v3(d.get("d", [])))
			_claw_anim(v3(d.get("d", [])))
			layer.sfx.play_at("slash", v3(d.get("o", [])), 0.9)
		"charge":
			_charge = 0.0 if bool(d.get("on", false)) else -1.0
			_show_ball(bool(d.get("on", false)))
		"bomb":
			_charge = -1.0
			_show_ball(false)
			var o: Vector3 = v3(d.get("o", []))
			var v: Vector3 = v3(d.get("v", []))
			_spawn_bomb(layer, str(d.get("k", "")), o, v, float(d.get("p", 0.5)), false)
			_launch_fx(layer, o, v.normalized() if v.length() > 0.01 else Vector3.FORWARD, float(d.get("p", 0.5)))
			_launch_anim(v.normalized() if v.length() > 0.01 else Vector3.FORWARD)
			layer.sfx.play_at("beam", o, 0.9, 0.6)
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


## Ends like the base (the power is over at once: multipliers restored, "off" sent), but the
## costume burns away - the cloak flares and dies, the tails droop and crumble into embers -
## before it is freed.
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
	_burn_out()


func _burn_out() -> void:
	var w: Node = world()
	var at: Vector3 = global_position
	var time: float = 0.75
	_tails.pose = "wilt"
	_tails.set_emitting(false)
	_flames.emitting = false
	HeroFx.tween_param(self, _cloak_mat, "lick", 0.07, 0.3, time * 0.4)
	HeroFx.tween_param(self, _cloak_mat, "alpha", 1.0, 0.0, time).set_ease(Tween.EASE_IN)
	HeroFx.tween_param(self, _ear_mat, "dissolve", 0.0, 1.0, time * 0.8)
	var tw: Tween = create_tween()
	tw.tween_property(_tails, "dissolve", 1.0, time).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)
	for e: MeshInstance3D in _eye_glow:
		create_tween().tween_property(e, "scale", Vector3.ONE * 0.01, time * 0.6)
	for ear: Node3D in _ears:
		create_tween().tween_property(ear, "scale", Vector3(0.6, 0.01, 0.6), time * 0.7).set_ease(Tween.EASE_IN)
	var et: Tween = create_tween().set_parallel(true)
	et.tween_property(_eyes, "scale", Vector3(1, 0.05, 1), time * 0.5).set_ease(Tween.EASE_IN)
	et.tween_property(_mouth, "scale", Vector3(1, 0.01, 1), 0.1)
	# embers shed from every tail, rising and drifting
	for i: int in range(0, FoxTails.TAILS, 2):
		HeroFx.pop(w, {"amount": 10, "lifetime": 1.2, "shape": "sphere", "radius": 0.3, "dir": Vector3.UP, "spread": 50.0,
			"speed": Vector2(0.5, 2.0), "gravity": Vector3(0, 1.2, 0), "facing": "velocity", "tex": Fx.Tex.SPARK,
			"size": Vector2(0.06, 0.2), "turbulence": 1.0, "explosiveness": 0.4, "color": Color(2.6, 1.2, 0.35),
			"fade": PackedFloat32Array([0.0, 1.0, 0.7, 0.0])}, _tails.tip(i))
	HeroFx.pop(w, {"amount": 26, "lifetime": 1.3, "shape": "sphere", "radius": 0.5, "dir": Vector3.UP, "spread": 40.0,
		"speed": Vector2(0.8, 2.6), "gravity": Vector3(0, 1.0, 0), "facing": "velocity", "tex": Fx.Tex.SPARK,
		"size": Vector2(0.06, 0.22), "turbulence": 1.0, "explosiveness": 0.3, "color": Color(2.6, 1.0, 0.3),
		"fade": PackedFloat32Array([0.0, 1.0, 0.6, 0.0])}, at + Vector3(0, 0.7, 0))
	HeroFx.smoke(w, at + Vector3(0, 0.8, 0), Color(0.25, 0.18, 0.16, 0.55), 12, 0.9, 1.2, 1.4)
	HeroFx.flash(w, at + Vector3(0, 0.9, 0), CLOAK, 3.0, 5.0, 0.5)
