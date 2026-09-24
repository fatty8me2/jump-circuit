extends PowerUp
## Nine-Tailed Fox: a licking chakra-flame cloak, flame fox ears, glowing red slit eyes and
## whisker marks, and nine living tails (FoxTails: they lag, whip on turns, fan out on jumps,
## stream back at speed and curl when idle). Speed x1.6, jump x1.35.
##  Attack (tap): Fox Claw - a lunging three-streak swipe that KOs the rival it connects with.
##  Attack (hold): charge a Tailed Beast Bomb (the tails arch forward and feed a dark sphere
##  in front of the mouth), release to fire it - a huge explosion that throws everyone in
##  its radius.
## The look (the most over-the-top thing in the game): a transformation (the ground cracks, a
## vortex drags in dust, rubble and flame, a towering pillar of fire, a roar that blows out a
## flame shockwave and a wall of dust), a burning cloak with tall flame tongues and a heat
## shimmer, tails that leave flame ribbons and throw sparks as they whip, burning footprints
## and a roaring fire streak at speed, claws that leave smouldering scars in the air and the
## ground, a staged Tailed Beast Bomb (red and blue chakra spiralling in, a dark collapse with
## lightning, a recoil) that detonates as a dark dome, then a mushroom of fire with burning
## rubble; on expiry the cloak burns away into embers.

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
var _tongues: GPUParticles3D
var _ground_fire: GPUParticles3D
var _smoke_trail: GPUParticles3D
var _floor_glow: MeshInstance3D
var _haze: MeshInstance3D
var _stride: float = 0.0
var _foot: float = 1.0
var _flare_t: float = 1.0
var _ball_spin: Node3D
var _ball_shell: ShaderMaterial
var _ball_pulse: float = 1.0
var _spiral: Node3D
var _pebbles: GPUParticles3D
var _bolt_t: float = 0.0


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
	# the looming flame silhouette: tall tongues of chakra fire rising round the body to well
	# above the head (a ring, so the body itself stays readable)
	var fo: Dictionary = {"amount": 44, "lifetime": 0.55, "shape": "ring", "ring_radius": 0.5, "ring_inner": 0.28,
		"ring_height": 0.7, "dir": Vector3.UP, "spread": 9.0, "speed": Vector2(1.8, 3.6), "gravity": Vector3(0, 2.5, 0),
		"curve": "shrink", "scale": Vector2(0.7, 1.3), "fixed_fps": 0, "box_aabb": 6.0,
		"colors": PackedColorArray([Color(1.8, 0.9, 0.25, 0.0), Color(1.6, 0.42, 0.04, 0.75), Color(0.95, 0.08, 0.0, 0.45), Color(0.3, 0.0, 0.0, 0.0)])}
	fo.merge(HeroFx.tongues(Vector2(0.46, 1.05)))
	_tongues = HeroFx.em(fo)
	_tongues.position = Vector3(0, 0.25, 0)
	_rig.add_child(_tongues)
	# flame tongues licking up off the cloak (world space: they stream behind a runner)
	_flames = HeroFx.em({"amount": 34, "lifetime": 0.4, "shape": "ring", "ring_radius": 0.4, "ring_inner": 0.25,
		"ring_height": 0.5, "dir": Vector3.UP, "spread": 12.0, "speed": Vector2(1.0, 2.2), "gravity": Vector3(0, 2.0, 0),
		"facing": "velocity", "tex": Fx.Tex.SPARK, "size": Vector2(0.3, 0.55), "curve": "shrink", "fixed_fps": 0,
		"additive": false, "box_aabb": 8.0,
		"colors": PackedColorArray([Color(1.3, 0.9, 0.3, 0.0), Color(1.2, 0.45, 0.04, 0.85), Color(0.8, 0.1, 0.0, 0.0)])})
	_flames.position = Vector3(0, 0.45, 0)
	_rig.add_child(_flames)
	# chakra bubbles popping on the surface, and embers drifting up
	var bubbles: GPUParticles3D = HeroFx.em({"amount": 16, "lifetime": 0.5, "shape": "shell", "radius": 0.5,
		"speed": Vector2(0.1, 0.5), "dir": Vector3.UP, "spread": 60.0, "size": 0.22, "curve": "pop", "local": true,
		"color": Color(2.2, 1.0, 0.25, 0.8)})
	bubbles.position = Vector3(0, 0.65, 0)
	_rig.add_child(bubbles)
	var embers: GPUParticles3D = HeroFx.em({"amount": 26, "lifetime": 1.4, "shape": "sphere", "radius": 0.6,
		"dir": Vector3.UP, "spread": 30.0, "speed": Vector2(0.8, 2.6), "gravity": Vector3(0, 0.9, 0),
		"facing": "velocity", "tex": Fx.Tex.SPARK, "size": Vector2(0.05, 0.17), "turbulence": 1.0, "box_aabb": 8.0,
		"color": Color(1.8, 0.8, 0.2), "fade": PackedFloat32Array([0.0, 1.0, 0.7, 0.0])})
	embers.position = Vector3(0, 0.55, 0)
	_rig.add_child(embers)
	# a trail of fire off the feet while running flat out: roaring tongues, a burning smear on
	# the ground and a column of dark smoke behind
	# (short-lived, so the streak stays near the feet and never fills our own camera's view)
	var ff: Dictionary = {"amount": 36, "lifetime": 0.3, "shape": "box", "extents": Vector3(0.24, 0.06, 0.12),
		"dir": Vector3.UP, "spread": 22.0, "speed": Vector2(0.8, 2.4), "gravity": Vector3(0, 3.0, 0),
		"curve": "shrink", "scale": Vector2(0.7, 1.3), "fixed_fps": 0, "emitting": false, "box_aabb": 10.0,
		"colors": PackedColorArray([Color(2.2, 1.5, 0.5, 0.95), Color(1.9, 0.5, 0.05, 0.8), Color(0.7, 0.06, 0.0, 0.4), Color(0.2, 0.05, 0.03, 0.0)])}
	ff.merge(HeroFx.tongues(Vector2(0.4, 0.85)))
	_feet_fire = HeroFx.em(ff)
	_feet_fire.position = Vector3(0, 0.1, 0.12)
	_rig.add_child(_feet_fire)
	_ground_fire = HeroFx.em({"amount": 40, "lifetime": 0.75, "shape": "box", "extents": Vector3(0.2, 0.01, 0.1),
		"speed": Vector2.ZERO, "spread": 0.0, "facing": "flat", "tex": Fx.Tex.DOT, "size": 0.75, "additive": false,
		"curve": "shrink", "angle": Vector2(0, 360), "fixed_fps": 0, "emitting": false, "box_aabb": 12.0,
		"colors": PackedColorArray([Color(2.4, 1.2, 0.3, 0.85), Color(1.6, 0.3, 0.02, 0.6), Color(0.15, 0.04, 0.03, 0.0)])})
	_ground_fire.position = Vector3(0, 0.05, 0.1)
	add_child(_ground_fire)
	_smoke_trail = HeroFx.em({"amount": 24, "lifetime": 1.0, "shape": "box", "extents": Vector3(0.2, 0.1, 0.1),
		"dir": Vector3.UP, "spread": 25.0, "speed": Vector2(0.8, 1.8), "gravity": Vector3(0, 1.2, 0), "damping": Vector2(0.5, 1.0),
		"facing": "mesh", "mesh": HeroFx.soft_quad(Fx.Tex.SMOKE, false, 0.8), "curve": "puff", "angle": Vector2(0, 360),
		"spin": Vector2(-60, 60), "fixed_fps": 0, "emitting": false, "box_aabb": 12.0,
		"color": Color(0.18, 0.1, 0.09, 0.35), "fade": PackedFloat32Array([0.0, 0.8, 0.4, 0.0])})
	_smoke_trail.position = Vector3(0, 0.6, 0.3)
	add_child(_smoke_trail)
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
		# a wisp of flame off each ear tip
		var wisp: GPUParticles3D = HeroFx.em({"amount": 10, "lifetime": 0.3, "size": 0.16, "fixed_fps": 0,
			"speed": Vector2(0.3, 1.0), "spread": 20.0, "dir": Vector3.UP, "gravity": Vector3(0, 2.0, 0), "curve": "shrink",
			"tex": Fx.Tex.SMOKE, "additive": false, "angle": Vector2(0, 360), "box_aabb": 6.0,
			"colors": PackedColorArray([Color(2.0, 1.2, 0.4, 0.9), Color(1.6, 0.35, 0.03, 0.6), Color(0.5, 0.05, 0.0, 0.0)])})
		wisp.position = Vector3(0, 0.38, 0)
		piv.add_child(wisp)
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
		var tr: GPUParticles3D = HeroFx.em({"amount": 26, "lifetime": 0.28, "speed": Vector2.ZERO, "spread": 0.0,
			"size": 0.12, "curve": "shrink", "fixed_fps": 0, "emitting": false, "box_aabb": 10.0,
			"color": Color(2.6, 0.25, 0.08, 0.9)})
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
	# a pool of firelight on the ground, and a heat shimmer round the whole cloak
	_floor_glow = HeroFx.glow_sprite(self, Color(1.0, 0.35, 0.05, 0.5), 2.4, Fx.Tex.RING, Vector3(0, 0.05, 0))
	(_floor_glow.material_override as StandardMaterial3D).billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	_floor_glow.rotation_degrees = Vector3(-90, 0, 0)
	_floor_glow.set_meta("no_ghost", true)
	if PartyFx.rich():
		_haze = PartyFx.heat_haze(2.3, 0.006)
		_haze.position = Vector3(0, 1.05, 0.15)
		_haze.set_meta("no_ghost", true)
		_rig.add_child(_haze)
	# the cloak lights its surroundings (not on Low)
	if not HeroFx.low():
		_light = OmniLight3D.new()
		_light.light_color = Color(1.0, 0.5, 0.15)
		_light.light_energy = 0.0
		_light.omni_range = 4.0
		_light.shadow_enabled = false
		_light.position = Vector3(0, 0.8, 0.2)
		_rig.add_child(_light)
	if is_inside_tree():
		_transform_in()
	else:
		_tails.grow = 1.0


## The transformation (about 1.5 s): the ground splits in glowing cracks, a vortex of chakra
## drags dust, rubble and flame in from all round and up the body, a towering pillar of fire
## erupts, the cloak ignites, the tails burst out and the fox roars - a shockwave of flame,
## a wall of dust, thrown rubble and a jolt of the camera.
func _transform_in() -> void:
	var w: Node = world()
	var at: Vector3 = global_position
	var fwd: Vector3 = -global_basis.z.normalized()
	_cloak_mat.set_shader_parameter("alpha", 0.0)
	_tails.grow = 0.0
	# 1. the ground splits under the feet
	PartyFx.ground_cracks(w, at, 3.8, Color(2.8, 1.0, 0.2), 11, 3.4)
	PartyFx.scorch(w, at, 2.4, 3.2, Color(1.0, 0.45, 0.1))
	# 2. the vortex: flame streaks spiral up the body; dust, rubble and red chakra are sucked in
	var spin := Node3D.new()
	w.add_child(spin)
	spin.global_position = at
	var vortex: GPUParticles3D = HeroFx.em({"amount": 120, "lifetime": 0.6, "one_shot": true, "explosiveness": 0.3,
		"local": true, "shape": "ring", "ring_radius": 1.3, "ring_inner": 0.9, "ring_height": 0.1, "dir": Vector3.UP,
		"spread": 8.0, "speed": Vector2(5.0, 10.0), "radial": Vector2(-7.0, -4.0), "facing": "velocity", "tex": Fx.Tex.SPARK,
		"size": Vector2(0.16, 0.8), "curve": "shrink", "fixed_fps": 0, "emitting": false, "box_aabb": 10.0,
		"colors": PackedColorArray([Color(2.4, 1.2, 0.3), Color(2.0, 0.45, 0.05), Color(0.9, 0.08, 0.0, 0.0)])})
	spin.add_child(vortex)
	var suck_dust: GPUParticles3D = HeroFx.em({"amount": 40, "lifetime": 0.6, "one_shot": true, "explosiveness": 0.4,
		"local": true, "shape": "ring", "ring_radius": 5.0, "ring_inner": 3.5, "ring_height": 0.2, "dir": Vector3.UP,
		"spread": 10.0, "speed": Vector2(0.5, 2.0), "radial": Vector2(-18.0, -12.0), "facing": "velocity", "tex": Fx.Tex.SPARK,
		"size": Vector2(0.1, 0.8), "additive": false, "emitting": false, "fixed_fps": 0, "box_aabb": 10.0,
		"color": Color(0.7, 0.6, 0.5, 0.45), "fade": PackedFloat32Array([0.0, 1.0, 0.6, 0.0])})
	spin.add_child(suck_dust)
	var rubble: GPUParticles3D = HeroFx.em({"amount": 22, "lifetime": 0.9, "one_shot": true, "explosiveness": 0.5,
		"local": true, "shape": "ring", "ring_radius": 4.0, "ring_inner": 2.0, "ring_height": 0.1, "dir": Vector3.UP,
		"spread": 15.0, "speed": Vector2(3.0, 6.0), "radial": Vector2(-9.0, -6.0), "gravity": Vector3(0, -3.0, 0),
		"facing": "mesh", "mesh": Fx.chunk_mesh(0.14), "scale": Vector2(0.6, 1.4), "curve": "shrink",
		"spin": Vector2(-400, 400), "angle": Vector2(0, 360), "emitting": false, "fixed_fps": 0, "box_aabb": 10.0,
		"color": Color(0.42, 0.34, 0.3), "fade": PackedFloat32Array([1.0, 1.0])})
	spin.add_child(rubble)
	var chakra: GPUParticles3D = HeroFx.em({"amount": 36, "lifetime": 0.8, "one_shot": true, "explosiveness": 0.2,
		"local": true, "shape": "ring", "ring_radius": 1.0, "ring_inner": 0.6, "ring_height": 0.3, "dir": Vector3.UP,
		"spread": 20.0, "speed": Vector2(2.0, 5.0), "size": 0.3, "curve": "pop", "emitting": false, "fixed_fps": 0,
		"box_aabb": 10.0, "color": Color(2.6, 0.35, 0.08, 0.9)})
	spin.add_child(chakra)
	for c: Node in spin.get_children():
		(c as GPUParticles3D).emitting = true
	var tw: Tween = spin.create_tween()
	tw.tween_property(spin, "rotation:y", TAU * 3.0, 1.3).set_ease(Tween.EASE_OUT)
	tw.tween_callback(spin.queue_free)
	# 3. a towering pillar of flame, a hotter core inside it and flame rushing up through it
	# mix-blended so it reads as fire, not a pale glow, against a bright sky
	var pillar_mat: ShaderMaterial = HeroFx.flame_mat(Color(0.8, 0.1, 0.0), Color(1.3, 0.45, 0.05), 1.3, 0.14, 6.0, true)
	pillar_mat.set_shader_parameter("stretch", 0.4)
	pillar_mat.set_shader_parameter("base_alpha", 0.25)
	var core_mat: ShaderMaterial = HeroFx.flame_mat(Color(1.5, 0.55, 0.06), Color(2.0, 1.2, 0.35), 1.0, 0.1, 8.0, true)
	core_mat.set_shader_parameter("base_alpha", 0.35)
	for layer_i: int in 2:
		var pmat: ShaderMaterial = pillar_mat if layer_i == 0 else core_mat
		var pillar := MeshInstance3D.new()
		var pm: CylinderMesh = PartyFx.cyl_mesh(0.5, 1.0, 0.22, 24)
		pm.cap_top = false
		pm.cap_bottom = false
		pillar.mesh = pm
		pillar.material_override = pmat
		pillar.layers = HeroFx.LAYER
		pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		w.add_child(pillar)
		pillar.global_position = at + Vector3(0, 0.1, 0)
		pillar.scale = Vector3(0.6, 0.1, 0.6)
		var wide: float = 2.6 if layer_i == 0 else 1.1
		var tall: float = 8.0 if layer_i == 0 else 9.0
		var ptw: Tween = pillar.create_tween().set_parallel(true)
		ptw.tween_property(pillar, "scale", Vector3(wide, tall, wide), 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		ptw.tween_property(pillar, "position:y", pillar.position.y + tall * 0.5, 0.5).set_ease(Tween.EASE_OUT)
		ptw.chain().tween_property(pillar, "scale", Vector3(wide * 0.3, tall * 1.1, wide * 0.3), 0.55).set_ease(Tween.EASE_IN)
		ptw.tween_method(func(v: float) -> void: pmat.set_shader_parameter("alpha", v), 1.0, 0.0, 0.55).set_ease(Tween.EASE_IN)
		ptw.chain().tween_callback(pillar.queue_free)
	var up_o: Dictionary = {"amount": 70, "lifetime": 0.75, "shape": "ring", "ring_radius": 0.7, "ring_inner": 0.2,
		"dir": Vector3.UP, "spread": 6.0, "speed": Vector2(8.0, 15.0), "damping": Vector2(2.0, 4.0), "curve": "shrink",
		"scale": Vector2(0.7, 1.4), "explosiveness": 0.35, "box_aabb": 14.0,
		"colors": PackedColorArray([Color(2.2, 1.3, 0.4, 0.95), Color(1.8, 0.4, 0.04, 0.8), Color(0.7, 0.05, 0.0, 0.5), Color(0.3, 0.0, 0.0, 0.0)])}
	up_o.merge(HeroFx.tongues(Vector2(0.7, 1.9), false))
	HeroFx.pop(w, up_o, at + Vector3(0, 0.2, 0))
	if PartyFx.rich():
		var haze: MeshInstance3D = PartyFx.heat_haze(4.5, 0.014)
		w.add_child(haze)
		haze.global_position = at + Vector3(0, 2.4, 0)
		var hm := haze.material_override as ShaderMaterial
		HeroFx.tween_param(haze, hm, "amount", 1.0, 0.0, 1.4).tween_callback(haze.queue_free)
	HeroFx.ground_ring(w, at, Color(1.6, 0.45, 0.06), 2.6, 0.5)
	HeroFx.dust_ring(w, at, Color(0.9, 0.78, 0.62, 0.45), 1.2, 14, 6.0)
	HeroFx.flash(w, at + Vector3(0, 1.5, 0), Color(1.0, 0.4, 0.1), 5.0, 9.0, 1.0)
	# 4. the cloak ignites, the ears pop, the tails burst out
	HeroFx.tween_param(self, _cloak_mat, "alpha", 0.0, 1.0, 0.35)
	var st: Tween = create_tween()
	st.tween_interval(0.12)
	st.tween_property(_tails, "grow", 1.25, 0.32).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	st.tween_property(_tails, "grow", 1.0, 0.3).set_ease(Tween.EASE_IN_OUT)
	for i: int in _ears.size():
		var et: Tween = create_tween()
		et.tween_interval(0.1 + 0.05 * float(i))
		et.tween_property(_ears[i], "scale", Vector3.ONE, 0.28).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	# 5. the roar
	var rt: Tween = create_tween()
	rt.tween_interval(0.5)
	rt.tween_callback(func() -> void: _roar(fwd))
	rt.tween_interval(0.7)
	rt.tween_callback(func() -> void:
		if _tails.pose == "roar":
			_tails.pose = "")


## The roar: rings of force out of the maw, a flame shockwave racing across the ground, a wall
## of dust, rubble thrown out burning, embers, a flash and a jolt of the local camera.
func _roar(fwd: Vector3) -> void:
	if not is_inside_tree():
		return
	_tails.pose = "roar"
	_mouth_open = 1.0
	_ear_back = 1.0
	var w: Node = world()
	var at: Vector3 = global_position
	var head: Vector3 = at + Vector3(0, 0.75, 0) + fwd * 0.4
	for k: int in 4:
		HeroFx.ring(w, head + fwd * (0.3 + 0.55 * float(k)), fwd, Color(1.4, 0.5 - 0.08 * float(k), 0.05, 0.7), 0.3 + 0.2 * float(k), 1.2 + 0.45 * float(k), 0.28 + 0.06 * float(k), 0.07, true)
	HeroFx.ring(w, at + Vector3(0, 0.12, 0), Vector3.UP, Color(1.1, 0.35, 0.04, 0.85), 0.4, 7.5, 0.6, 0.04)
	HeroFx.ring(w, at + Vector3(0, 0.5, 0), Vector3.UP, Color(1.2, 0.6, 0.2, 0.6), 0.3, 5.0, 0.45, 0.03)
	HeroFx.ground_ring(w, at, Color(1.5, 0.45, 0.06), 4.5, 0.6)
	PartyFx.dust_wall(w, at, 3.2, Color(0.9, 0.8, 0.66, 0.65), 28)
	# a flat wave of flame tongues racing out across the ground
	var wave: Dictionary = {"amount": 64, "lifetime": 0.5, "shape": "ring", "ring_radius": 0.6, "ring_inner": 0.4,
		"dir": Vector3(1, 0.06, 0), "spread": 180.0, "flatness": 0.92, "speed": Vector2(11.0, 17.0),
		"damping": Vector2(14.0, 20.0), "curve": "shrink", "scale": Vector2(0.7, 1.3), "box_aabb": 14.0,
		"colors": PackedColorArray([Color(2.4, 1.4, 0.4, 0.9), Color(1.9, 0.45, 0.04, 0.7), Color(0.6, 0.04, 0.0, 0.0)])}
	wave.merge(HeroFx.tongues(Vector2(0.55, 1.3), false))
	HeroFx.pop(w, wave, at + Vector3(0, 0.25, 0))
	PartyFx.burning_debris(w, at + Vector3(0, 0.3, 0), 7, 10.0, Color(2.4, 0.9, 0.2), Color(0.3, 0.24, 0.22), 0.55)
	HeroFx.burst(w, at + Vector3(0, 0.8, 0), Color(2.4, 1.1, 0.25), 50, 10.0, 0.32, 0.6)
	HeroFx.sparks(w, at + Vector3(0, 0.8, 0), Color(2.6, 1.6, 0.6), 44, 13.0, Vector3.UP, 110.0, 0.6)
	if PartyFx.rich():
		PartyFx.embers(w, at + Vector3(0, 1.0, 0), 1.6, Color(2.6, 1.0, 0.25), 44, 2.4, 1.8)
	HeroFx.flash(w, at + Vector3(0, 1.2, 0), Color(1.0, 0.45, 0.12), 8.0, 11.0, 0.6)
	for e: MeshInstance3D in _eye_glow:
		e.scale = Vector3.ONE * 2.8
		create_tween().tween_property(e, "scale", Vector3.ONE, 0.5).set_ease(Tween.EASE_OUT)
	if local and layer != null:
		HeroFx.screen_flash(layer, Color(1.0, 0.5, 0.12), 0.22, 0.45)
		PartyFx.shake(layer.level, 0.55)


func _process(dt: float) -> void:
	_t += dt
	if _ball != null:
		if _ball_spin != null:
			_ball_spin.rotation.y += dt * 6.0
		var s: float = 0.2 + 0.8 * clampf(_charge / CHARGE_TIME, 0.0, 1.0)
		_ball.scale = _ball.scale.lerp(Vector3.ONE * s * _ball_pulse, 1.0 - exp(-12.0 * dt))
		_ball_pulse = lerpf(_ball_pulse, 1.0, 1.0 - exp(-6.0 * dt))
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
	# flat out: a roaring fire streak off the feet, a burning smear on the ground, smoke, and
	# red streaks off the eyes
	var fast: bool = hs > 7.0 and not ended
	_feet_fire.emitting = fast and grounded
	_feet_fire.amount_ratio = clampf((hs - 6.0) / 8.0, 0.3, 1.0)
	_ground_fire.emitting = fast and grounded
	# (a rival's fox only: behind our own runner the smoke would sit between us and the course)
	_smoke_trail.emitting = fast and not local
	_smoke_trail.amount_ratio = clampf((hs - 6.0) / 10.0, 0.2, 1.0)
	for tr: GPUParticles3D in _eye_trails:
		tr.emitting = hs > 9.0 and not ended
	# burning footprints
	if grounded and hs > 2.5 and not ended:
		_stride += hs * dt
		if _stride > 0.85:
			_stride = 0.0
			_foot = -_foot
			var f: Vector3 = Vector3(vel.x, 0, vel.z).normalized()
			var side: Vector3 = f.cross(Vector3.UP)
			PartyFx.footprint(world(), feet() + side * 0.15 * _foot, f, Color(2.4, 0.8, 0.15), 1.9 if hs > 7.0 else 1.3, 0.34)
	else:
		_stride = 0.6
	# now and then the cloak flares: a gout of flame tongues bursts up
	_flare_t -= dt
	if _flare_t <= 0.0 and not ended:
		_flare_t = randf_range(0.7, 1.6)
		var fl: Dictionary = {"amount": 8, "lifetime": 0.4, "shape": "sphere", "radius": 0.3, "dir": Vector3.UP,
			"spread": 25.0, "speed": Vector2(3.0, 4.5), "damping": Vector2(2.0, 3.0), "curve": "shrink",
			"colors": PackedColorArray([Color(1.9, 1.0, 0.25, 0.9), Color(1.5, 0.3, 0.02, 0.6), Color(0.4, 0.02, 0.0, 0.0)])}
		fl.merge(HeroFx.tongues(Vector2(0.35, 0.8), false))
		HeroFx.pop(world(), fl, chest() + Vector3(0, 0.3, 0))
	# the eyes pulse; the cloak flickers its light and its pool of firelight
	var pulse: float = 1.0 + sin(_t * 7.0) * 0.12
	for e: MeshInstance3D in _eye_glow:
		e.scale = e.scale.lerp(Vector3.ONE * pulse, 1.0 - exp(-10.0 * dt))
	var charging: float = charge_frac() if _charge >= 0.0 else 0.0
	if _floor_glow != null:
		var fm := _floor_glow.material_override as StandardMaterial3D
		fm.albedo_color = Color(1.0, 0.35, 0.05).lerp(Color(0.7, 0.2, 1.0), charging)
		fm.albedo_color.a = 0.0 if ended else 0.38 + 0.12 * sin(_t * 11.0) + charging * 0.3
		_floor_glow.scale = Vector3.ONE * (1.0 + sin(_t * 7.0) * 0.06 + charging * 0.4)
	if _light != null:
		var want: float = 0.0 if ended else 1.3 + sin(_t * 17.0) * 0.3 + sin(_t * 7.3) * 0.2 + (1.4 if _charge >= 0.0 else 0.0)
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
## the ghost of a huge paw behind them, then the scars: the talon lines hang in the air,
## cooling and smouldering, and three glowing gouges are torn into the ground ahead, with
## burning chips and embers.
static func _claw_fx(parent: Node, o: Vector3, dir: Vector3) -> void:
	var b := PartyFx.facing(dir)
	# the rake is drawn across the view in front of the fox (a plane facing the attack, leaned
	# forward a little), so it reads from behind - the player's own camera - and from the side
	var right: Vector3 = b.x
	var up: Vector3 = b.y
	var y: Vector3 = -dir
	var plane := Basis(right, y, right.cross(y)).rotated(right, deg_to_rad(-35.0))
	var c: Vector3 = o + dir * 1.1 + right * 0.55 - up * 0.7
	# the huge faint paw smear behind the claws
	HeroFx.slash(parent, c, plane, 1.25, 0.5, -1.5, Color(1.0, 0.25, 0.02, 0.45), 0.6, 0.1, 0.3, Color(1.1, 0.45, 0.06, 0.6))
	# three raking talons: concentric, bright-cored, drawn one after another
	for i: int in 3:
		HeroFx.slash(parent, c, plane, 0.95 + 0.26 * float(i), 0.45, -1.4 - 0.05 * float(i), Color(1.2, 0.3 + 0.08 * float(i), 0.02), 0.13, 0.06 + 0.02 * float(i), 0.28, Color(1.5, 1.35, 1.1))
		_scar(parent, c, plane, 0.95 + 0.26 * float(i), 0.4, -1.35 - 0.05 * float(i), 1.3 + 0.2 * float(i), 0.05 + 0.03 * float(i))
	var hit: Vector3 = o + dir * 1.5
	HeroFx.sparks(parent, hit, Color(2.0, 1.0, 0.3), 36, 13.0, (dir + (b * Vector3(1, 0, 0)) * 0.6).normalized(), 45.0, 0.6)
	HeroFx.pop(parent, {"amount": 30, "lifetime": 0.45, "spread": 45.0, "dir": dir, "speed": Vector2(4.0, 10.0),
		"damping": Vector2(8.0, 12.0), "size": 0.32, "curve": "shrink", "color": Color(1.6, 0.55, 0.08)}, hit)
	HeroFx.ring(parent, hit, dir, Color(1.3, 0.55, 0.1, 0.85), 0.2, 1.8, 0.28, 0.08)
	HeroFx.flash(parent, hit, Color(1.0, 0.5, 0.15), 6.0, 7.0, 0.3)
	# gouges in the ground where the claws raked through
	if parent is Node3D and (parent as Node3D).is_inside_tree():
		var from: Vector3 = o + dir * 0.7
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -2.5, 0), 1)
		var g: Dictionary = (parent as Node3D).get_world_3d().direct_space_state.intersect_ray(q)
		if not g.is_empty():
			var gp: Vector3 = g["position"]
			PartyFx.claw_gouges(parent, gp, dir, 2.8, 3, 0.34, Color(2.8, 1.0, 0.22), 2.4, g["normal"] as Vector3)
			HeroFx.dust_ring(parent, gp + dir * 1.2, Color(0.85, 0.76, 0.62, 0.5), 0.6, 10, 4.0)
			PartyFx.burning_debris(parent, gp + dir * 1.0 + Vector3(0, 0.1, 0), 4, 6.0, Color(2.4, 0.9, 0.2), Color(0.35, 0.28, 0.24), 0.5)


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
		_ball_spin = Node3D.new()
		_ball.add_child(_ball_spin)
		_ball_pulse = 1.0
		# a near-black core with a violet rim, wrapped in licking dark-violet flame
		var core_mat: ShaderMaterial = HeroFx.energy_mat(Color(0.05, 0.0, 0.08), Color(0.75, 0.3, 1.0), 1.0, 6.0)
		_ball_core = HeroFx.mesh_part(_ball_spin, PartyFx.sphere_mesh(0.5, 20), core_mat, Vector3.ZERO)
		_ball_shell = HeroFx.flame_mat(Color(0.3, 0.02, 0.5), Color(1.2, 0.4, 1.6), 1.4, 0.16, 5.0, true)
		_ball_shell.set_shader_parameter("freq", 6.0)
		_ball_shell.set_shader_parameter("grow", 0.08)
		HeroFx.mesh_part(_ball_spin, PartyFx.sphere_mesh(0.62, 20), _ball_shell, Vector3.ZERO)
		# a spinning band of crackling energy
		var band := TorusMesh.new()
		band.inner_radius = 0.7
		band.outer_radius = 0.76
		band.rings = 32
		band.ring_segments = 6
		var bm: MeshInstance3D = HeroFx.mesh_part(_ball_spin, band, PartyFx.glow_mat(Color(0.8, 0.2, 1.0, 0.45), 1.6, true), Vector3.ZERO, Vector3.ONE, Vector3(70, 0, 20))
		bm.set_meta("spin", true)
		# chakra sucked in from all around (streaks racing to the centre)
		_ball.add_child(HeroFx.em({"amount": 70, "lifetime": 0.42, "local": true, "shape": "shell", "radius": 2.4,
			"speed": Vector2(0.0, 0.2), "radial": Vector2(-36.0, -28.0), "facing": "velocity", "tex": Fx.Tex.SPARK,
			"size": Vector2(0.07, 0.55), "curve": "flat", "fixed_fps": 0,
			"colors": PackedColorArray([Color(0.6, 0.2, 1.4, 0.0), Color(1.6, 0.5, 2.2, 1.0), Color(2.4, 0.4, 0.6, 0.0)])}))
		# red and blue chakra spiralling in, like two arms of a galaxy: emitted (in world space)
		# from two points whirling round the sphere, each speck then falls straight inward
		_spiral = Node3D.new()
		_ball.add_child(_spiral)
		for k: int in 2:
			var col: Color = Color(2.6, 0.35, 0.15) if k == 0 else Color(0.35, 0.7, 2.8)
			var arm: GPUParticles3D = HeroFx.em({"amount": 60, "lifetime": 0.5, "shape": "point",
				"offset": Vector3(2.2 * (1.0 if k == 0 else -1.0), 0, 0), "speed": Vector2(0.0, 0.1), "spread": 180.0,
				"radial": Vector2(-9.0, -7.0), "size": 0.22, "scale": Vector2(0.6, 1.1), "curve": "shrink", "fixed_fps": 0,
				"box_aabb": 8.0, "colors": PackedColorArray([Color(col.r, col.g, col.b, 0.0), col, Color(2.2, 1.8, 2.2, 0.0)])})
			_spiral.add_child(arm)
		# dark wisps folding into it
		_ball.add_child(HeroFx.em({"amount": 22, "lifetime": 0.6, "local": true, "shape": "shell", "radius": 1.4,
			"speed": Vector2(0.0, 0.1), "radial": Vector2(-8.0, -6.0), "tex": Fx.Tex.SMOKE, "additive": false,
			"size": 0.55, "curve": "shrink", "angle": Vector2(0, 360), "color": Color(0.08, 0.0, 0.12, 0.75),
			"fade": PackedFloat32Array([0.0, 0.8, 0.6])}))
		# pebbles tugged up off the ground toward the sphere
		_pebbles = HeroFx.em({"amount": 12, "lifetime": 1.1, "shape": "ring", "ring_radius": 2.2, "ring_inner": 0.8,
			"ring_height": 0.02, "dir": Vector3.UP, "spread": 12.0, "speed": Vector2(0.6, 1.6), "gravity": Vector3(0, 1.2, 0),
			"radial": Vector2(-1.5, -0.8), "facing": "mesh", "mesh": Fx.chunk_mesh(0.1), "scale": Vector2(0.6, 1.3),
			"curve": "shrink", "spin": Vector2(-200, 200), "angle": Vector2(0, 360), "color": Color(0.45, 0.38, 0.36),
			"fade": PackedFloat32Array([1.0, 1.0]), "fixed_fps": 0})
		_pebbles.position = Vector3(0, 0.05, -0.4)
		add_child(_pebbles)
		if not HeroFx.low():
			var l := OmniLight3D.new()
			l.light_color = Color(0.7, 0.3, 1.0)
			l.light_energy = 2.5
			l.omni_range = 5.0
			l.shadow_enabled = false
			_ball.add_child(l)
		_ball.scale = Vector3.ONE * 0.2
		_full = false
		_bolt_t = 0.0
		if _tails != null:
			_tails.pose = "charge"
		_mouth_open = 1.0
		if is_inside_tree():
			HeroFx.ring(world(), global_position + Vector3(0, 0.1, 0), Vector3.UP, Color(0.6, 0.2, 1.0, 0.7), 0.3, 2.2, 0.4, 0.05)
			HeroFx.dust_ring(world(), global_position, Color(0.8, 0.72, 0.8, 0.5), 0.8, 10, 4.0)
	elif not on and _ball != null:
		_ball.queue_free()
		_ball = null
		_ball_core = null
		_ball_spin = null
		_ball_shell = null
		_spiral = null
		if _pebbles != null:
			_pebbles.emitting = false
			HeroFx.free_after(_pebbles, 1.5)
			_pebbles = null
		if _tails != null and _tails.pose == "charge":
			_tails.pose = ""


## Per-frame charging look (both screens), in stages: chakra blobs streak from the tail tips
## into the sphere while red and blue arms spiral in; pressure rings and dust pulse on the
## ground, pebbles lift; past half charge lightning crawls over it; near full it collapses
## dark with a blazing rim, and at full charge the ground cracks with a ping of light.
func _charge_fx(dt: float) -> void:
	if _ball == null or not is_inside_tree():
		return
	var k: float = clampf(_charge / CHARGE_TIME, 0.0, 1.0)
	var at: Vector3 = _ball.global_position
	for c: Node in _ball_spin.get_children():
		if c.has_meta("spin"):
			(c as Node3D).rotate_object_local(Vector3.UP, dt * 14.0)
	if _spiral != null:
		_spiral.rotation.z += dt * lerpf(9.0, 16.0, k)
	if _pebbles != null:
		_pebbles.amount_ratio = clampf(k * 1.2, 0.1, 1.0)
	# the collapse: the flame shell goes darker, its rim blazes brighter
	if _ball_shell != null:
		var dk: float = smoothstep(0.55, 1.0, k)
		_ball_shell.set_shader_parameter("core", Color(0.3, 0.02, 0.5).lerp(Color(0.02, 0.0, 0.04), dk))
		_ball_shell.set_shader_parameter("rim", Color(1.2, 0.4, 1.6).lerp(Color(2.2, 1.2, 2.6), dk))
		_ball_shell.set_shader_parameter("lick", 0.16 + 0.12 * dk)
	_feed_t -= dt
	if _feed_t <= 0.0 and _tails != null:
		_feed_t = lerpf(0.07, 0.03, k) / maxf(HeroFx.density(), 0.3)
		var red: bool = randf() < 0.55
		_feed(_tails.tip(randi() % FoxTails.TAILS), Color(2.4, 0.3, 0.15) if red else Color(0.4, 0.6, 2.4))
	_crackle_t -= dt
	if _crackle_t <= 0.0:
		_crackle_t = lerpf(0.16, 0.05, k)
		PartyFx.crackle(world(), at, 0.45 + 0.35 * k, Color(0.9, 0.55, 1.0), 4, 0.07)
	if k > 0.35:
		_bolt_t -= dt
		if _bolt_t <= 0.0:
			_bolt_t = lerpf(0.16, 0.07, k)
			PartyFx.lightning_shell(world(), at, 0.75 * _ball.scale.x + 0.1, Color(1.3, 0.8, 2.0), 1 + int(k * 2.0), 0.08)
	_dust_t -= dt
	if _dust_t <= 0.0:
		_dust_t = lerpf(0.4, 0.2, k)
		HeroFx.ring(world(), global_position + Vector3(0, 0.1, 0), Vector3.UP, Color(0.55, 0.18, 1.0, 0.55), 0.5, 1.4 + 1.6 * k, 0.35, 0.04)
		if k > 0.4:
			HeroFx.dust_ring(world(), global_position, Color(0.8, 0.72, 0.8, 0.5), 0.8, 8, 4.0 + 5.0 * k)
	if k >= 1.0 and not _full:
		_full = true
		_ball_pulse = 0.55
		HeroFx.burst(world(), at, Color(1.8, 0.8, 2.4), 36, 6.0, 0.24, 0.45)
		HeroFx.ring(world(), at, Vector3.UP, Color(0.85, 0.45, 1.2, 0.9), 0.4, 2.4, 0.3, 0.06)
		HeroFx.ring(world(), at, _ball.global_basis.z, Color(1.2, 0.7, 1.6, 0.9), 0.3, 1.8, 0.25, 0.08)
		PartyFx.ground_cracks(world(), global_position, 2.6, Color(1.6, 0.6, 2.4), 8, 2.0)
		HeroFx.flash(world(), at, Color(0.8, 0.4, 1.0), 7.0, 7.0, 0.35)


## A blob of red or blue chakra racing from a tail tip into the sphere, leaving a streak.
func _feed(from: Vector3, color: Color) -> void:
	var blob := Node3D.new()
	world().add_child(blob)
	blob.global_position = from
	PartyFx.part(blob, PartyFx.sphere_mesh(0.09, 8), PartyFx.glow_mat(Color(color.r, color.g, color.b, 1.0), 1.0), Vector3.ZERO)
	blob.add_child(HeroFx.em({"amount": 12, "lifetime": 0.18, "size": 0.14, "fixed_fps": 0, "speed": Vector2.ZERO,
		"spread": 0.0, "curve": "shrink", "box_aabb": 6.0, "color": Color(color.r, color.g, color.b, 0.8)}))
	var ball: WeakRef = weakref(_ball)
	var side: Vector3 = Vector3(randf_range(-1, 1), randf_range(0.2, 1.0), randf_range(-1, 1)) * 0.6
	var tw: Tween = blob.create_tween()
	tw.tween_method(func(k: float) -> void:
		var bn: Node3D = ball.get_ref() as Node3D
		if bn != null and bn.is_inside_tree():
			# a curving path: bows out to the side, then dives in
			blob.global_position = from.lerp(bn.global_position, k * k) + side * sin(k * PI)
			blob.scale = Vector3.ONE * (1.0 - k * 0.7), 0.0, 1.0, 0.26)
	tw.tween_callback(blob.queue_free)


## Launch: the sphere bursts out of the maw - a heavy flash, rings along the shot, a cone of
## violet fire, sparks, and a back-blast of dust and smoke along the ground behind the fox.
static func _launch_fx(parent: Node, o: Vector3, dir: Vector3, power: float) -> void:
	HeroFx.orb(parent, o, Color(0.8, 0.45, 1.0, 0.6), 0.3, 0.9 + 0.5 * power, 0.18)
	for k: int in 5:
		HeroFx.ring(parent, o + dir * (0.4 + 0.9 * float(k)), dir, Color(0.75, 0.35, 1.1, 0.8), 0.4 + 0.1 * float(k), 1.3 + 0.5 * float(k), 0.3 + 0.06 * float(k), 0.06)
	HeroFx.sparks(parent, o, Color(1.8, 0.8, 2.4), 40, 15.0, dir, 30.0, 0.8)
	var cone: Dictionary = {"amount": 30, "lifetime": 0.35, "spread": 22.0, "dir": dir, "speed": Vector2(6.0, 14.0),
		"damping": Vector2(12.0, 18.0), "curve": "shrink", "scale": Vector2(0.7, 1.3),
		"colors": PackedColorArray([Color(2.2, 1.4, 2.6, 0.9), Color(1.2, 0.3, 2.0, 0.6), Color(0.3, 0.0, 0.6, 0.0)])}
	cone.merge(HeroFx.tongues(Vector2(0.4, 1.1), true))
	HeroFx.pop(parent, cone, o)
	HeroFx.pop(parent, {"amount": 28, "lifetime": 0.55, "spread": 60.0, "dir": -dir, "speed": Vector2(2.0, 6.0),
		"damping": Vector2(5.0, 8.0), "tex": Fx.Tex.SMOKE, "additive": false, "size": 0.75, "curve": "puff",
		"angle": Vector2(0, 360), "color": Color(0.12, 0.02, 0.16, 0.7), "fade": PackedFloat32Array([0.0, 0.8, 0.0])}, o)
	HeroFx.flash(parent, o, Color(0.8, 0.45, 1.0), 12.0, 10.0, 0.4)
	# the back-blast: dust rolls back along the ground behind the shooter
	if parent is Node3D and (parent as Node3D).is_inside_tree():
		var q := PhysicsRayQueryParameters3D.create(o, o + Vector3(0, -3.0, 0), 1)
		var g: Dictionary = (parent as Node3D).get_world_3d().direct_space_state.intersect_ray(q)
		if not g.is_empty():
			var gp: Vector3 = g["position"]
			var back := Vector3(-dir.x, 0, -dir.z).normalized()
			HeroFx.pop(parent, {"amount": 22, "lifetime": 0.9, "facing": "mesh", "mesh": HeroFx.soft_quad(Fx.Tex.SMOKE, false, 1.1),
				"shape": "sphere", "radius": 0.4, "dir": back + Vector3(0, 0.25, 0), "spread": 35.0, "speed": Vector2(4.0, 9.0),
				"damping": Vector2(5.0, 8.0), "curve": "puff", "angle": Vector2(0, 360), "spin": Vector2(-60, 60),
				"color": Color(0.82, 0.76, 0.7, 0.55), "fade": PackedFloat32Array([0.0, 0.9, 0.4, 0.0]), "box_aabb": 10.0}, gp + Vector3(0, 0.2, 0))
			HeroFx.ring(parent, gp + Vector3(0, 0.06, 0), Vector3.UP, Color(0.7, 0.3, 1.1, 0.8), 0.4, 2.8, 0.35, 0.05)


func _launch_anim(dir: Vector3) -> void:
	if not is_inside_tree():
		return
	_mouth_open = 1.0
	_ear_back = 1.0
	if _tails != null:
		_tails.pose = ""
		_tails.whip(-dir * 14.0 + Vector3(0, 2.0, 0))
	# the recoil scores two skid marks back along the ground under the feet
	var q := PhysicsRayQueryParameters3D.create(feet() + Vector3(0, 0.3, 0), feet() + Vector3(0, -1.0, 0), 1)
	var g: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	if not g.is_empty():
		PartyFx.claw_gouges(world(), g["position"] as Vector3, -dir, 1.6, 2, 0.32, Color(1.8, 0.7, 2.4), 1.6, g["normal"] as Vector3)
	HeroFx.afterimage(world(), get_parent() as Node3D, Color(0.8, 0.35, 1.0), 0.3, -dir, 1.4)


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
	pr.add_child(HeroFx.em({"amount": 80, "lifetime": 0.45, "size": 0.6 * (0.6 + power), "shape": "sphere",
		"radius": r * 0.8, "speed": Vector2(0.1, 0.8), "spread": 180.0, "curve": "shrink", "fixed_fps": 0, "box_aabb": 24.0,
		"colors": PackedColorArray([Color(1.8, 0.9, 2.4, 0.9), Color(0.7, 0.1, 1.2, 0.6), Color(0.1, 0.0, 0.2, 0.0)])}))
	pr.add_child(HeroFx.em({"amount": 30, "lifetime": 0.8, "size": 0.9 * (0.6 + power), "shape": "sphere",
		"radius": r * 0.5, "speed": Vector2(0.1, 0.6), "facing": "mesh", "mesh": HeroFx.soft_quad(Fx.Tex.SMOKE, false, 0.9 * (0.6 + power)),
		"curve": "puff", "angle": Vector2(0, 360), "fixed_fps": 0, "box_aabb": 24.0, "color": Color(0.1, 0.02, 0.14, 0.6),
		"fade": PackedFloat32Array([0.0, 0.7, 0.0])}))
	pr.add_child(HeroFx.em({"amount": 28, "lifetime": 0.3, "size": Vector2(0.06, 0.45), "shape": "shell",
		"radius": r * 1.6, "speed": Vector2(0.0, 0.2), "radial": Vector2(-14.0, -10.0), "facing": "velocity",
		"tex": Fx.Tex.SPARK, "local": true, "color": Color(2.4, 0.6, 1.4), "box_aabb": 4.0}))
	# red and blue chakra spiralling round the flight line, each leaving its own streak
	var spinner := Node3D.new()
	pr.add_child(spinner)
	for k: int in 2:
		var col: Color = Color(2.6, 0.4, 0.15) if k == 0 else Color(0.35, 0.75, 2.8)
		var m := Node3D.new()
		m.position = Vector3(r * 1.3 * (1.0 if k == 0 else -1.0), 0, 0)
		spinner.add_child(m)
		PartyFx.part(m, PartyFx.sphere_mesh(0.09, 8), PartyFx.glow_mat(col, 1.0), Vector3.ZERO)
		m.add_child(HeroFx.em({"amount": 40, "lifetime": 0.35, "size": 0.2, "fixed_fps": 0, "speed": Vector2.ZERO,
			"spread": 0.0, "curve": "shrink", "box_aabb": 24.0, "color": Color(col.r, col.g, col.b, 0.9)}))
	var sp: Tween = spinner.create_tween().set_loops()
	sp.tween_property(spinner, "rotation:z", TAU, 0.22).from(0.0)
	# lightning crackling round it in flight
	var cr: Tween = pr.create_tween().set_loops(40)
	cr.tween_interval(0.07)
	cr.tween_callback(func() -> void:
		if is_instance_valid(pr) and pr.is_inside_tree() and not pr.done:
			PartyFx.crackle(layer_ref, pr.global_position, r * 1.5, Color(1.1, 0.7, 1.8), 3, 0.06))
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


## The detonation, in two beats. First a dark dome swallows the blast radius - near-black,
## with a blazing violet rim and lightning crawling over it - while the ground splits under it.
## Then it bursts: a mushroom of fire boils up, burning rubble is flung out (sparking where it
## lands), a shockwave and a wall of dust race across the ground, and embers hang in the air.
static func _boom_fx(layer_ref: PartyLayer, pos: Vector3, radius: float) -> void:
	var clear: float = PartyFx.camera_clear(pos, radius * 0.7)
	# where the ground is under the blast
	var gq := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0.5, 0), pos + Vector3(0, -radius, 0), 1)
	var gh: Dictionary = layer_ref.get_world_3d().direct_space_state.intersect_ray(gq)
	var ground: Vector3 = gh["position"] if not gh.is_empty() else pos - Vector3(0, 0.5, 0)
	var gn: Vector3 = gh["normal"] if not gh.is_empty() else Vector3.UP
	# 1. a small white-violet pop, and everything nearby sucked into the centre
	HeroFx.orb(layer_ref, pos, Color(1.0, 0.85, 1.0, 0.9), 0.3, radius * 0.25, 0.1)
	PartyFx.implode(layer_ref, pos, Color(0.8, 0.4, 1.2), radius * 0.9)
	# 2. the dark dome
	var dome_r: float = radius * 0.62
	var dm := ShaderMaterial.new()
	dm.shader = HeroFx.shader("dark_dome")
	dm.set_shader_parameter("alpha", 0.0)
	var dome := MeshInstance3D.new()
	dome.mesh = PartyFx.sphere_mesh(1.0, 40)
	dome.material_override = dm
	dome.layers = HeroFx.LAYER
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	layer_ref.add_child(dome)
	dome.global_position = pos
	dome.scale = Vector3.ONE * 0.2
	var a_max: float = 0.3 + 0.7 * clear
	var dt: Tween = dome.create_tween()
	dt.tween_property(dome, "scale", Vector3.ONE * dome_r, 0.14).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	dt.parallel().tween_method(func(v: float) -> void: dm.set_shader_parameter("alpha", v), 0.0, a_max, 0.08)
	dt.tween_property(dome, "scale", Vector3.ONE * dome_r * 1.04, 0.2).set_trans(Tween.TRANS_SINE)
	dt.tween_property(dome, "scale", Vector3.ONE * dome_r * 0.9, 0.08).set_ease(Tween.EASE_IN)
	dt.tween_property(dome, "scale", Vector3.ONE * dome_r * 1.2, 0.22).set_ease(Tween.EASE_OUT)
	dt.parallel().tween_method(func(v: float) -> void: dm.set_shader_parameter("alpha", v), a_max, 0.0, 0.22).set_ease(Tween.EASE_IN)
	dt.tween_callback(dome.queue_free)
	# its rim: licking violet flame, additive, only at the edges
	HeroFx.dome(layer_ref, pos, Color(0.35, 0.05, 0.6), Color(1.2, 0.5, 1.7), dome_r * 1.05, 0.14, 0.5, false, 1.4, 0.0)
	# lightning crawling over it while it holds
	var lt: Tween = dome.create_tween().set_loops(5)
	lt.tween_interval(0.07)
	lt.tween_callback(func() -> void:
		if is_instance_valid(dome) and dome.is_inside_tree():
			PartyFx.lightning_shell(layer_ref, pos, dome.scale.x * 1.01, Color(1.4, 0.9, 2.2), 3, 0.09))
	# the ground splits and scorches under it
	PartyFx.ground_cracks(layer_ref, ground, radius * 1.15, Color(2.2, 0.8, 2.6), 12, 3.4, 0, gn)
	PartyFx.scorch(layer_ref, ground, radius * 0.85, 3.6, Color(0.9, 0.4, 1.2))
	HeroFx.flash(layer_ref, pos, Color(0.7, 0.3, 1.0), 9.0, radius * 3.0, 0.4)
	layer_ref.sfx.play_at("boom", pos, 1.3, 0.8)
	var me: Vector3 = layer_ref.player.global_position
	PartyFx.shake(layer_ref.level, clampf(1.2 - me.distance_to(pos) / (radius * 4.0), 0.0, 0.9))
	# 3. the burst, as the dome breaks
	var burst_at: Node3D = Node3D.new()
	layer_ref.add_child(burst_at)
	burst_at.global_position = pos
	var bt: Tween = burst_at.create_tween()
	bt.tween_interval(0.42)
	bt.tween_callback(func() -> void:
		if not is_instance_valid(layer_ref) or not layer_ref.is_inside_tree():
			return
		PartyFx.fire_mushroom(layer_ref, ground, radius * 1.35, radius * 0.6, Color(2.4, 1.5, 0.7), Color(1.9, 0.5, 0.1), Color(0.2, 0.12, 0.2, 0.75))
		HeroFx.fireball(layer_ref, pos, radius * 0.5, 26, Color(1.6, 1.2, 0.9), Color(1.3, 0.4, 0.9), Color(0.3, 0.15, 0.35, 0.5))
		HeroFx.burst(layer_ref, pos, Color(1.2, 0.45, 1.5), 44, radius * 2.6, 0.45, 0.55)
		HeroFx.sparks(layer_ref, pos, Color(2.2, 1.1, 2.0), 50, radius * 4.2, Vector3.UP, 180.0, 0.75)
		HeroFx.sparks(layer_ref, pos, Color(2.6, 1.3, 0.4), 30, radius * 3.5, Vector3.UP, 70.0, 0.6)
		PartyFx.burning_debris(layer_ref, ground + gn * 0.3, 10, radius * 2.4, Color(2.4, 0.9, 0.3), Color(0.25, 0.2, 0.24), 0.65)
		PartyFx.dust_wall(layer_ref, ground, radius * 1.1, Color(0.8, 0.74, 0.72, 0.7), 30)
		HeroFx.ground_ring(layer_ref, ground, Color(0.8, 0.35, 1.1), radius * 1.6, 0.55)
		HeroFx.ground_ring(layer_ref, ground, Color(1.4, 0.65, 0.15), radius * 1.0, 0.4)
		HeroFx.ring(layer_ref, ground + gn * 0.1, gn, Color(0.9, 0.5, 1.2, 0.9), 0.5, radius * 1.7, 0.5, 0.03)
		HeroFx.ring(layer_ref, pos, Vector3.UP, Color(1.2, 0.7, 1.4, 0.7), dome_r, radius * 1.5, 0.35, 0.05)
		if PartyFx.rich():
			PartyFx.embers(layer_ref, pos + Vector3(0, radius * 0.3, 0), radius * 0.6, Color(2.6, 1.1, 0.35), 50, 2.6, 1.6)
			PartyFx.embers(layer_ref, pos, radius * 0.5, Color(1.6, 0.6, 2.4), 30, 2.2, 1.2)
		HeroFx.flash(layer_ref, pos, Color(1.0, 0.55, 0.35), 12.0, radius * 4.0, 0.6)
		var me2: Vector3 = layer_ref.player.global_position
		PartyFx.shake(layer_ref.level, clampf(1.0 - me2.distance_to(pos) / (radius * 4.0), 0.0, 0.7))
		if me2.distance_to(pos) < radius * 2.5:
			HeroFx.screen_flash(layer_ref, Color(1.0, 0.6, 0.9), 0.28 * clampf(1.5 - me2.distance_to(pos) / (radius * 2.0), 0.3, 1.0), 0.4))
	bt.tween_interval(0.2)
	bt.tween_callback(burst_at.queue_free)


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
	_tongues.emitting = false
	_feet_fire.emitting = false
	_ground_fire.emitting = false
	_smoke_trail.emitting = false
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
	if _haze != null:
		var hm := _haze.material_override as ShaderMaterial
		HeroFx.tween_param(self, hm, "amount", 1.0, 0.0, time * 0.6)
	# embers shed from every tail, rising and drifting
	for i: int in range(0, FoxTails.TAILS, 2):
		HeroFx.pop(w, {"amount": 14, "lifetime": 1.4, "shape": "sphere", "radius": 0.3, "dir": Vector3.UP, "spread": 50.0,
			"speed": Vector2(0.5, 2.0), "gravity": Vector3(0, 1.2, 0), "facing": "velocity", "tex": Fx.Tex.SPARK,
			"size": Vector2(0.06, 0.2), "turbulence": 1.0, "explosiveness": 0.4, "color": Color(2.6, 1.2, 0.35),
			"fade": PackedFloat32Array([0.0, 1.0, 0.7, 0.0])}, _tails.tip(i))
	HeroFx.pop(w, {"amount": 36, "lifetime": 1.5, "shape": "sphere", "radius": 0.5, "dir": Vector3.UP, "spread": 40.0,
		"speed": Vector2(0.8, 2.6), "gravity": Vector3(0, 1.0, 0), "facing": "velocity", "tex": Fx.Tex.SPARK,
		"size": Vector2(0.06, 0.22), "turbulence": 1.0, "explosiveness": 0.3, "color": Color(2.6, 1.0, 0.3),
		"fade": PackedFloat32Array([0.0, 1.0, 0.6, 0.0])}, at + Vector3(0, 0.7, 0))
	# a last gout of flame and a ring of heat as the chakra lets go
	var fl: Dictionary = {"amount": 24, "lifetime": 0.55, "shape": "ring", "ring_radius": 0.5, "ring_inner": 0.2,
		"dir": Vector3.UP, "spread": 12.0, "speed": Vector2(3.0, 6.0), "damping": Vector2(3.0, 5.0), "curve": "shrink",
		"colors": PackedColorArray([Color(2.2, 1.2, 0.3, 0.9), Color(1.6, 0.35, 0.03, 0.5), Color(0.4, 0.02, 0.0, 0.0)])}
	fl.merge(HeroFx.tongues(Vector2(0.45, 1.1), true))
	HeroFx.pop(w, fl, at + Vector3(0, 0.3, 0))
	HeroFx.ring(w, at + Vector3(0, 0.1, 0), Vector3.UP, Color(1.1, 0.4, 0.05, 0.7), 0.4, 2.6, 0.5, 0.05)
	HeroFx.smoke(w, at + Vector3(0, 0.8, 0), Color(0.25, 0.18, 0.16, 0.55), 16, 1.0, 1.4, 1.6)
	HeroFx.flash(w, at + Vector3(0, 0.9, 0), CLOAK, 3.5, 5.0, 0.6)


## One talon's scar: a thin white-hot arc that hangs in the air where the claw passed, cools
## through orange to a dull red and fades, dripping embers and a wisp of smoke.
static func _scar(parent: Node, center: Vector3, basis: Basis, radius: float, a0: float, a1: float, life: float, delay: float) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var im := ImmediateMesh.new()
	var steps: int = 20
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i: int in steps + 1:
		var k: float = float(i) / float(steps)
		var a: float = lerpf(a0, a1, k)
		var d := Vector3(sin(a), 0, -cos(a))
		var w: float = 0.045 * pow(sin(k * PI), 0.7) + 0.004
		var col := Color(1, 1, 1, pow(sin(k * PI), 0.5))
		im.surface_set_color(col)
		im.surface_add_vertex(d * (radius - w))
		im.surface_set_color(col)
		im.surface_add_vertex(d * (radius + w))
	im.surface_end()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	mat.albedo_color = Color(3.0, 2.0, 1.0, 0.0)
	var mi: MeshInstance3D = PartyFx.part(parent as Node3D, im, mat, Vector3.ZERO)
	mi.global_transform = Transform3D(basis, center)
	var tw: Tween = mi.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(mat, "albedo_color:a", 1.0, 0.04)
	tw.tween_property(mat, "albedo_color", Color(2.2, 0.55, 0.08, 1.0), life * 0.3).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color", Color(0.9, 0.08, 0.01, 0.0), life * 0.7).set_ease(Tween.EASE_IN)
	tw.tween_callback(mi.queue_free)
	if not PartyFx.rich():
		return
	for j: int in 3:
		var a2: float = lerpf(a0, a1, 0.25 + 0.25 * float(j))
		var p: Vector3 = center + basis * (Vector3(sin(a2), 0, -cos(a2)) * radius)
		HeroFx.pop(parent, {"amount": 5, "lifetime": 0.8, "shape": "sphere", "radius": 0.08, "dir": Vector3.DOWN,
			"spread": 50.0, "speed": Vector2(0.2, 0.9), "gravity": Vector3(0, -2.5, 0), "facing": "velocity",
			"tex": Fx.Tex.SPARK, "size": Vector2(0.04, 0.14), "turbulence": 0.6, "explosiveness": 0.05,
			"color": Color(2.6, 1.0, 0.25), "fade": PackedFloat32Array([1.0, 0.8, 0.0])}, p)
		HeroFx.pop(parent, {"amount": 3, "lifetime": 1.0, "tex": Fx.Tex.SMOKE, "additive": false, "size": 0.35,
			"speed": Vector2(0.2, 0.6), "spread": 30.0, "dir": Vector3.UP, "gravity": Vector3(0, 0.6, 0), "curve": "puff",
			"angle": Vector2(0, 360), "explosiveness": 0.1, "color": Color(0.25, 0.2, 0.2, 0.35),
			"fade": PackedFloat32Array([0.0, 0.8, 0.0])}, p)
