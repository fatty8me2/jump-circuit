extends PowerUp
## Hero's Tunic: a green tunic and long pointed cap, a shield on the back and the Legend Blade.
## Speed x1.15, jump x1.1.
##  Attack (tap): Legend Blade - a three-swing combo (the third is a big overhead chop).
##  Attack (hold): the blade gathers light; release for a Spin Attack that throws everyone around.
##  Use: the current tool. Cycle: next tool.
##    Boomerang - curves out and back, stunning everyone it passes through.
##    Hookshot  - fires a chain: yanks a rival to you, or pulls you to the wall / floor it bites.
##    Bombs     - a lobbed bomb with a fizzing fuse; big blast knockback.
## The look: an item-get pose on pickup (the blade raised in a column of golden light with rays
## falling round it and leaves blown out), a cap that flops with every move, a glinting shield,
## a blade that leaves a swept trail and a wind arc on every swing (cut grass flies; the chop
## splits the ground), a whirlwind spin that cuts a glowing circle and raises a dust wall, a
## spinning boomerang in a whirl of wind, a real chain for the hookshot that bites with chips,
## and cartoon bomb blasts with burning chunks, scorch and cracks.

const GREEN := Color(0.18, 0.6, 0.2)
const BLADE := Color(0.65, 0.88, 1.0)
const GOLD := Color(1.0, 0.82, 0.25)
const TOOLS: Array[String] = ["boomerang", "hookshot", "bombs"]
const SPIN_CHARGE: float = 0.75
const SLASH_CD: float = 0.26
const TOOL_CD: float = 0.75
const HOOK_RANGE: float = 20.0
const SWORD_REST_POS := Vector3(0.42, 0.55, -0.1)
const SWORD_REST_ROT := Vector3(-70, 0, -12)

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
var _chain: Node3D
var _t: float = 0.0
# the look
var _rig: HeroFx.Rig
var _cap: Node3D
var _cap_tip: Node3D
var _cap_swing: Vector2 = Vector2.ZERO
var _cap_vel: Vector2 = Vector2.ZERO
var _prev_vel: Vector3 = Vector3.ZERO
var _shield: Node3D
var _glint: MeshInstance3D
var _glint_t: float = 1.2
var _trail: HeroFx.Trail
var _trail_off: float = 0.0
var _sword_tw: Tween
var _tip_glow: MeshInstance3D
var _full: bool = false
var _spark_t: float = 0.0


func _init() -> void:
	duration = 10.0
	takes_attack = true


func mods() -> Vector3:
	return Vector3(1.15, 1.1, 1.0)


func build_look() -> void:
	_rig = HeroFx.Rig.new()
	add_child(_rig)
	var green: StandardMaterial3D = PartyFx.solid_mat(GREEN, 0.25, 0.7)
	var dark: StandardMaterial3D = PartyFx.solid_mat(Color(0.1, 0.36, 0.12), 0.1, 0.7)
	var leather: StandardMaterial3D = PartyFx.solid_mat(Color(0.42, 0.26, 0.12), 0.0, 0.8)
	var gold: StandardMaterial3D = PartyFx.solid_mat(GOLD, 0.9, 0.3, 0.8)
	# tunic: a flared skirt over the lower shell, belt and buckle
	PartyFx.part(_rig, PartyFx.cyl_mesh(0.47, 0.44, 0.36, 20), green, Vector3(0, 0.42, 0))
	PartyFx.part(_rig, PartyFx.cyl_mesh(0.52, 0.08, 0.48, 20), dark, Vector3(0, 0.2, 0))
	var belt := TorusMesh.new()
	belt.inner_radius = 0.36
	belt.outer_radius = 0.43
	belt.rings = 24
	belt.ring_segments = 8
	PartyFx.part(_rig, belt, leather, Vector3(0, 0.55, 0), Vector3(1, 0.8, 1))
	PartyFx.part(_rig, PartyFx.box_mesh(Vector3(0.14, 0.11, 0.05)), gold, Vector3(0, 0.55, -0.42))
	# cap: a band and a long cone drooping back, in two jointed halves so it flops
	PartyFx.part(_rig, PartyFx.cyl_mesh(0.34, 0.12, 0.32, 20), green, Vector3(0, 0.98, 0.02))
	_cap = Node3D.new()
	_cap.position = Vector3(0, 1.03, 0.06)
	_cap.rotation_degrees = Vector3(62, 0, 0)
	_cap.name = "Cap"
	_rig.add_child(_cap)
	PartyFx.part(_cap, PartyFx.cyl_mesh(0.28, 0.46, 0.15, 16), green, Vector3(0, 0.23, 0))
	_cap_tip = Node3D.new()
	_cap_tip.position = Vector3(0, 0.46, 0)
	_cap.add_child(_cap_tip)
	PartyFx.part(_cap_tip, PartyFx.cone_mesh(0.15, 0.5, 14), green, Vector3(0, 0.24, 0))
	# shield on the back: blue face, silver rim, a golden three-triangle crest, and a glint
	_shield = Node3D.new()
	_shield.position = Vector3(0, 0.66, 0.43)
	_rig.add_child(_shield)
	PartyFx.part(_shield, PartyFx.cyl_mesh(0.3, 0.06, -1.0, 24), PartyFx.solid_mat(Color(0.75, 0.78, 0.85), 0.1, 0.3, 0.9), Vector3.ZERO, Vector3(1, 1, 1.25), Vector3(90, 0, 0))
	PartyFx.part(_shield, PartyFx.cyl_mesh(0.25, 0.07, -1.0, 24), PartyFx.solid_mat(Color(0.12, 0.2, 0.62), 0.2, 0.4), Vector3(0, 0, 0.01), Vector3(1, 1, 1.25), Vector3(90, 0, 0))
	var tri := PrismMesh.new()
	tri.size = Vector3(0.12, 0.1, 0.02)
	for off: Vector3 in [Vector3(0, 0.07, 0.045), Vector3(-0.06, -0.03, 0.045), Vector3(0.06, -0.03, 0.045)]:
		PartyFx.part(_shield, tri, PartyFx.glow_mat(GOLD, 2.0), off)
	_glint = HeroFx.glow_sprite(_shield, Color(1.6, 1.6, 1.4, 0.0), 0.5, Fx.Tex.STAR, Vector3(0.1, 0.12, 0.08))
	_glint.set_meta("no_ghost", true)
	# the Legend Blade, held in the right hand
	_sword = Node3D.new()
	_sword.position = SWORD_REST_POS
	_sword.rotation_degrees = SWORD_REST_ROT
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
	_tip_glow = HeroFx.glow_sprite(_sword, Color(1.2, 1.4, 1.6, 0.0), 0.7, Fx.Tex.STAR, Vector3(0, 1.08, 0))
	_tip_glow.set_meta("no_ghost", true)
	# the blade's swept trail (drawn while it swings)
	_trail = HeroFx.Trail.new()
	_trail.target = _sword
	_trail.a_local = Vector3(0, 0.22, 0)
	_trail.b_local = Vector3(0, 1.08, 0)
	_trail.color = Color(0.45, 0.8, 1.0)
	_trail.hot = Color(1.3, 1.45, 1.6)
	_trail.max_age = 0.14
	add_child(_trail)
	# a slow swirl of green leaves and golden motes around the hero
	var leaves: GPUParticles3D = PartyFx.emitter({"amount": 14, "lifetime": 1.4, "size": 0.12, "color": Color(0.5, 1.0, 0.45),
		"shape": "ring", "radius": 0.75, "inner": 0.6, "height": 0.8, "vmin": 0.2, "vmax": 0.5, "dir": Vector3.UP,
		"spread": 25.0, "tangential": 2.0, "aabb": 3.0})
	leaves.position = Vector3(0, 0.5, 0)
	add_child(leaves)
	add_child(HeroFx.em({"amount": 8, "lifetime": 1.2, "shape": "sphere", "radius": 0.7, "dir": Vector3.UP,
		"spread": 40.0, "speed": Vector2(0.2, 0.6), "size": 0.18, "curve": "pop", "tex": Fx.Tex.STAR,
		"color": Color(1.3, 1.1, 0.5), "offset": Vector3(0, 0.7, 0)}))
	if is_inside_tree():
		_item_get()


## The pickup: the hero thrusts the blade to the sky in a column of golden light - rays of
## light fall round the hero, a star flashes on the tip, sparkles pour down, rings rise round
## the body and a ring of light and leaves washes out over the ground.
func _item_get() -> void:
	var w: Node = world()
	var at: Vector3 = global_position
	PartyFx.burst(w, at + Vector3(0, 0.8, 0), Color(0.45, 1.0, 0.4), 50, 7.0, 0.3, 0.7)
	HeroFx.ring(w, at + Vector3(0, 0.1, 0), Vector3.UP, Color(0.5, 1.0, 0.45, 0.9), 0.4, 3.6, 0.5, 0.06)
	HeroFx.ground_ring(w, at, Color(1.1, 0.95, 0.4), 2.6, 0.7)
	HeroFx.dust_ring(w, at, Color(0.92, 0.9, 0.78, 0.5), 1.0, 14, 5.0)
	HeroFx.flash(w, at + Vector3(0, 1, 0), Color(0.8, 1.0, 0.6), 7.0, 8.0, 0.6)
	# leaves and grass blown out round the feet
	HeroFx.pop(w, {"amount": 26, "lifetime": 1.2, "shape": "ring", "ring_radius": 0.5, "ring_inner": 0.2,
		"dir": Vector3(1, 0.6, 0), "spread": 180.0, "flatness": 0.5, "speed": Vector2(2.0, 5.0), "damping": Vector2(2.0, 3.0),
		"gravity": Vector3(0, -2.0, 0), "size": Vector2(0.16, 0.09), "curve": "shrink", "angle": Vector2(0, 360),
		"spin": Vector2(-400, 400), "additive": false, "tex": Fx.Tex.DOT,
		"pick": PackedColorArray([Color(0.35, 0.8, 0.3), Color(0.5, 0.95, 0.35), Color(0.25, 0.6, 0.2)]),
		"fade": PackedFloat32Array([1.0, 1.0, 0.0]), "box_aabb": 8.0}, at + Vector3(0, 0.2, 0))
	# golden rings rising round the hero, one after another
	for i: int in 4:
		var tw: Tween = create_tween()
		tw.tween_interval(0.1 + 0.11 * float(i))
		tw.tween_callback(func() -> void:
			if is_inside_tree():
				HeroFx.ring(world(), global_position + Vector3(0, 0.2 + 0.45 * float(i), 0), Vector3.UP, Color(1.2, 1.0, 0.4, 0.85), 0.9, 0.5, 0.4, 0.05))
	# a column of golden light and sparkles, and rays of light falling round the hero
	HeroFx.pop(w, {"amount": 48, "lifetime": 1.1, "shape": "ring", "ring_radius": 0.8, "ring_inner": 0.5,
		"dir": Vector3.UP, "spread": 5.0, "speed": Vector2(2.0, 4.5), "tex": Fx.Tex.STAR, "size": 0.3, "curve": "pop",
		"angle": Vector2(0, 360), "color": Color(1.3, 1.1, 0.5), "explosiveness": 0.4}, at)
	for i: int in 6:
		var a: float = TAU * float(i) / 6.0 + 0.3
		var base: Vector3 = at + Vector3(cos(a) * 1.1, 0.0, sin(a) * 1.1)
		PartyFx.beam(w, base, base + Vector3(0, 6.0, 0), Color(1.2, 1.05, 0.55, 0.35), 0.12, 0.7 + 0.05 * float(i), 1.4)
	PartyFx.beam(w, at, at + Vector3(0, 8.0, 0), Color(1.2, 1.1, 0.6, 0.3), 0.55, 0.8, 1.2)
	# the pose: blade straight up above the head, hold, back to the side
	_kill_sword_tween()
	_sword_tw = create_tween()
	_sword_tw.tween_property(_sword, "position", Vector3(0.12, 1.05, -0.05), 0.16).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_sword_tw.parallel().tween_property(_sword, "rotation_degrees", Vector3(0, 0, -6), 0.16).set_ease(Tween.EASE_OUT)
	_sword_tw.tween_callback(func() -> void:
		if not is_inside_tree():
			return
		var tip: Vector3 = _sword.global_transform * Vector3(0, 1.08, 0)
		_tip_glow.scale = Vector3.ONE * 3.4
		(_tip_glow.material_override as StandardMaterial3D).albedo_color.a = 1.0
		var gt: Tween = create_tween().set_parallel(true)
		gt.tween_property(_tip_glow, "scale", Vector3.ONE, 0.55).set_ease(Tween.EASE_OUT)
		gt.tween_property(_tip_glow, "rotation:z", TAU * 0.5, 0.55)
		gt.tween_property(_tip_glow.material_override, "albedo_color:a", 0.0, 0.65).set_ease(Tween.EASE_IN)
		HeroFx.stars(world(), tip, Color(1.4, 1.25, 0.6), 18, 3.5, 0.5, 0.2)
		HeroFx.ring(world(), tip, Vector3.BACK, Color(1.3, 1.15, 0.6, 0.9), 0.1, 1.4, 0.35, 0.08, true)
		HeroFx.pop(world(), {"amount": 40, "lifetime": 1.1, "shape": "sphere", "radius": 0.15, "dir": Vector3.DOWN,
			"spread": 70.0, "speed": Vector2(1.0, 3.0), "gravity": Vector3(0, -3.0, 0), "tex": Fx.Tex.STAR, "size": 0.18,
			"curve": "pop", "color": Color(1.3, 1.15, 0.55)}, tip)
		HeroFx.flash(world(), tip, GOLD, 6.0, 7.0, 0.55))
	_sword_tw.tween_interval(0.45)
	_sword_tw.tween_property(_sword, "position", SWORD_REST_POS, 0.2).set_ease(Tween.EASE_IN_OUT)
	_sword_tw.parallel().tween_property(_sword, "rotation_degrees", SWORD_REST_ROT, 0.2).set_ease(Tween.EASE_IN_OUT)


func begin() -> void:
	layer.sfx.play("chime", 1.0, 1.0)
	PartyFx.shake(layer.level, 0.25)


func _vel() -> Vector3:
	if body is Player:
		return (body as Player).velocity
	if body != null and body.has_method("velocity"):
		return body.call("velocity")
	return Vector3.ZERO


func _process(dt: float) -> void:
	_t += dt
	if dt > 0.0 and _cap != null and is_inside_tree():
		# the cap flops: a damped spring pushed by the body's acceleration and speed
		var vel: Vector3 = _vel()
		var acc: Vector3 = (vel - _prev_vel) / dt
		_prev_vel = vel
		var inv: Basis = global_basis.orthonormalized().inverse()
		var la: Vector3 = inv * acc
		var lv: Vector3 = inv * vel
		var target := Vector2(clampf(lv.z * 0.03 + la.y * 0.004, -0.5, 0.6), clampf(-lv.x * 0.03, -0.5, 0.5))
		var force: Vector2 = (target - _cap_swing) * 90.0 - _cap_vel * 9.0 + Vector2(la.z * 0.015, -la.x * 0.015)
		_cap_vel += force * dt
		_cap_swing += _cap_vel * dt
		_cap_swing = _cap_swing.clamp(Vector2(-0.9, -0.9), Vector2(0.9, 0.9))
		_cap.rotation = Vector3(deg_to_rad(62.0) - _cap_swing.x * 0.6, 0, _cap_swing.y * 0.6 + sin(_t * 3.0) * 0.08)
		_cap_tip.rotation = Vector3(-_cap_swing.x * 0.8 + 0.2, 0, _cap_swing.y * 0.8 + sin(_t * 3.0 - 0.8) * 0.12)
	# the shield glints now and then
	_glint_t -= dt
	if _glint_t <= 0.0 and _glint != null:
		_glint_t = randf_range(2.0, 3.5)
		var gm := _glint.material_override as StandardMaterial3D
		_glint.position = Vector3(-0.14, -0.1, 0.08)
		var tw: Tween = create_tween().set_parallel(true)
		tw.tween_property(_glint, "position", Vector3(0.14, 0.16, 0.08), 0.35)
		tw.tween_method(func(k: float) -> void: gm.albedo_color.a = sin(k * PI), 0.0, 1.0, 0.35)
		tw.tween_property(_glint, "rotation:z", PI * 0.5, 0.35)
	if _charge >= 0.0 and _blade_mat != null:
		var k: float = charge_frac()
		_blade_mat.albedo_color = Color(BLADE.r, BLADE.g, BLADE.b, 1.0).lerp(Color(3.0, 3.0, 3.2, 1.0), k * (0.7 + 0.3 * sin(_t * 30.0)))
		# light gathers on the tip; a star flares when it is fully charged
		var tm := _tip_glow.material_override as StandardMaterial3D
		tm.albedo_color.a = k * (0.6 + 0.4 * sin(_t * 25.0))
		_tip_glow.rotation.z += dt * 4.0
		_spark_t -= dt
		if _spark_t <= 0.0 and is_inside_tree():
			_spark_t = 0.1
			var tip: Vector3 = _sword.global_transform * Vector3(0, 1.0, 0)
			HeroFx.pop(world(), {"amount": 6, "lifetime": 0.3, "shape": "sphere", "radius": 0.6, "speed": Vector2(0.0, 0.1),
				"radial": Vector2(-14.0, -10.0), "tex": Fx.Tex.STAR, "size": 0.14, "curve": "pop", "color": Color(1.2, 1.4, 1.6)}, tip)
		if k >= 1.0 and not _full:
			_full = true
			_tip_glow.scale = Vector3.ONE * 2.5
			create_tween().tween_property(_tip_glow, "scale", Vector3.ONE * 1.2, 0.3)
			if is_inside_tree():
				HeroFx.ring(world(), _sword.global_transform * Vector3(0, 1.0, 0), Vector3.UP, Color(0.8, 0.95, 1.2, 0.9), 0.1, 1.2, 0.3, 0.1)
	if _chain != null and is_instance_valid(_chain):
		var hand: Vector3 = _sword.global_position
		(_chain as HeroFx.Chain).set_ends(hand, _hook_to)
	if _trail_off > 0.0:
		_trail_off -= dt
		if _trail_off <= 0.0:
			_trail.active = false


func _kill_sword_tween() -> void:
	if _sword_tw != null and _sword_tw.is_valid():
		_sword_tw.kill()


## Turns the blade trail on for `time` seconds.
func _trail_for(time: float) -> void:
	if _trail == null:
		return
	_trail.active = true
	_trail_off = time


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
		_charge_pose(true)
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
		_charge_pose(false)
		_blade_mat.albedo_color = Color(BLADE.r, BLADE.g, BLADE.b, 1.0) * 1.6
		_blade_mat.albedo_color.a = 1.0
		if held >= 0.0 and full:
			_spin()
		else:
			fx("charge", {"on": false})
		return
	if held >= 0.0 and held < hold_threshold:
		_slash()


## Charging: the blade is drawn back low behind the hero, tip glowing (or put back).
func _charge_pose(on: bool) -> void:
	_full = false
	_kill_sword_tween()
	_sword_tw = create_tween()
	if on:
		_sword_tw.tween_property(_sword, "position", Vector3(0.45, 0.5, 0.25), 0.15).set_ease(Tween.EASE_OUT)
		_sword_tw.parallel().tween_property(_sword, "rotation_degrees", Vector3(-110, 30, -30), 0.15).set_ease(Tween.EASE_OUT)
	else:
		(_tip_glow.material_override as StandardMaterial3D).albedo_color.a = 0.0
		_sword_tw.tween_property(_sword, "position", SWORD_REST_POS, 0.12)
		_sword_tw.parallel().tween_property(_sword, "rotation_degrees", SWORD_REST_ROT, 0.12)


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


## A crescent smear of blade-light for each swing (right-to-left, left-to-right, then a big
## overhead chop that splits the ground), a wind arc flying on past it, sparks and glints off
## the edge, cut grass and a puff of dust off the ground.
static func _slash_fx(parent: Node, o: Vector3, dir: Vector3, combo: int) -> void:
	var b := PartyFx.facing(dir)
	var col := Color(0.55, 0.85, 1.1, 0.85)
	var core := Color(1.3, 1.4, 1.5)
	match combo:
		0:
			var p0: Basis = Basis(dir, deg_to_rad(-14.0)) * b
			HeroFx.slash(parent, o, p0, 1.55, 1.35, -1.35, col, 0.42, 0.08, 0.2, core)
			HeroFx.slash(parent, o + dir * 0.4, p0, 2.2, 1.0, -1.0, Color(0.7, 0.9, 1.1, 0.35), 0.18, 0.12, 0.25, Color(1.0, 1.1, 1.2), true)
		1:
			var p1: Basis = Basis(dir, deg_to_rad(18.0)) * b
			HeroFx.slash(parent, o + Vector3(0, 0.1, 0), p1, 1.55, -1.35, 1.35, col, 0.42, 0.08, 0.2, core)
			HeroFx.slash(parent, o + Vector3(0, 0.1, 0) + dir * 0.4, p1, 2.2, -1.0, 1.0, Color(0.7, 0.9, 1.1, 0.35), 0.18, 0.12, 0.25, Color(1.0, 1.1, 1.2), true)
		_:
			# the chop is drawn in a plane leaned toward the viewer behind so it reads head-on too
			var plane := Basis(dir, deg_to_rad(70.0)) * b
			HeroFx.slash(parent, o + Vector3(0, 0.25, 0), plane, 1.8, -1.5, 1.4, Color(0.7, 0.95, 1.2, 0.9), 0.55, 0.11, 0.28, core)
			var ground: Vector3 = o + dir * 1.7 - Vector3(0, 0.75, 0)
			PartyFx.shockwave(parent, ground, Color(0.6, 0.9, 1.0), 1.8, 0.35)
			HeroFx.dust_ring(parent, ground, Color(0.9, 0.87, 0.8, 0.6), 0.9, 14, 6.0)
			HeroFx.sparks(parent, ground + Vector3(0, 0.1, 0), Color(1.4, 1.3, 0.9), 30, 9.0, Vector3.UP, 60.0, 0.45)
			HeroFx.pop(parent, {"amount": 10, "lifetime": 0.8, "facing": "mesh", "mesh": Fx.chunk_mesh(0.1), "spread": 40.0,
				"speed": Vector2(3.0, 6.0), "gravity": Vector3(0, -18, 0), "scale": Vector2(0.6, 1.2), "curve": "shrink",
				"spin": Vector2(-400, 400), "angle": Vector2(0, 360), "color": Color(0.55, 0.5, 0.45),
				"fade": PackedFloat32Array([1.0, 1.0])}, ground)
			# the blade's cut, glowing in the ground, with a split either side
			if parent is Node3D and (parent as Node3D).is_inside_tree():
				var gq := PhysicsRayQueryParameters3D.create(ground + Vector3(0, 0.8, 0), ground + Vector3(0, -1.5, 0), 1)
				var gh: Dictionary = (parent as Node3D).get_world_3d().direct_space_state.intersect_ray(gq)
				if not gh.is_empty():
					var gp: Vector3 = gh["position"]
					PartyFx.claw_gouges(parent, gp - dir * 0.6, dir, 2.4, 1, 0.0, Color(1.2, 1.9, 2.6), 1.8, gh["normal"] as Vector3)
					PartyFx.ground_cracks(parent, gp + dir * 0.4, 1.2, Color(1.1, 1.7, 2.4), 6, 1.6, 0, gh["normal"] as Vector3)
	HeroFx.sparks(parent, o + dir * 1.2, Color(1.2, 1.4, 1.6), 26, 10.0, dir, 50.0, 0.4)
	HeroFx.stars(parent, o + dir * 1.3, Color(1.3, 1.45, 1.6), 5, 2.5, 0.3, 0.3)
	# cut grass and leaves flicked off the swing
	HeroFx.pop(parent, {"amount": 12, "lifetime": 0.8, "shape": "sphere", "radius": 0.4, "dir": dir + Vector3(0, 0.6, 0),
		"spread": 55.0, "speed": Vector2(2.0, 5.0), "gravity": Vector3(0, -6.0, 0), "damping": Vector2(1.0, 2.0),
		"size": Vector2(0.14, 0.06), "curve": "shrink", "angle": Vector2(0, 360), "spin": Vector2(-500, 500), "additive": false,
		"pick": PackedColorArray([Color(0.35, 0.8, 0.3), Color(0.5, 0.95, 0.35), Color(0.25, 0.6, 0.2)]),
		"fade": PackedFloat32Array([1.0, 1.0, 0.0]), "box_aabb": 6.0}, o + dir * 1.0 - Vector3(0, 0.5, 0))


## The blade's own swing (every screen): wound back, whipped through with a trail, recovered.
func _swing_anim(combo: int) -> void:
	_kill_sword_tween()
	_sword_tw = create_tween()
	var rest := SWORD_REST_ROT
	var reach := Vector3(0.25, 0.62, -0.35)
	_sword.position = reach
	_trail_for(0.2)
	match combo:
		0:
			_sword.rotation_degrees = Vector3(-90, 80, -12)
			_sword_tw.tween_property(_sword, "rotation_degrees", Vector3(-90, -90, -12), 0.1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		1:
			_sword.rotation_degrees = Vector3(-90, -90, 10)
			_sword_tw.tween_property(_sword, "rotation_degrees", Vector3(-90, 80, 10), 0.1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		_:
			_sword.position = Vector3(0.2, 0.8, -0.2)
			_sword.rotation_degrees = Vector3(40, 0, 0)
			_sword_tw.tween_property(_sword, "rotation_degrees", Vector3(-150, 0, 0), 0.13).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_sword_tw.tween_property(_sword, "rotation_degrees", rest, 0.18)
	_sword_tw.parallel().tween_property(_sword, "position", SWORD_REST_POS, 0.18)


func _spin() -> void:
	var o: Vector3 = chest()
	_spin_fx(layer, o)
	_spin_anim()
	layer.sfx.play("whoosh", 1.0, 0.8)
	layer.sfx.play("slash", 0.9, 0.7)
	PartyFx.shake(layer.level, 0.35)
	fx("spin", {"o": arr(o)})
	for t: Dictionary in layer.targets_in_sphere(o, 3.6):
		var away: Vector3 = (t["center"] as Vector3) - o
		away.y = 0.0
		away = away.normalized() if away.length() > 0.1 else layer.aim_dir()
		layer.hit(t, away * 19.0 + Vector3(0, 9.0, 0), {"st": 0.6, "s": "spin"})


## The whole hero whirls round once with the blade held out, its trail drawing the circle.
func _spin_anim() -> void:
	_kill_sword_tween()
	_sword.position = Vector3(0.5, 0.6, -0.1)
	_sword.rotation_degrees = Vector3(-90, -60, -12)
	_trail.max_age = 0.26
	_trail_for(0.36)
	_sword_tw = create_tween()
	_sword_tw.tween_property(self, "rotation:y", rotation.y + TAU, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_sword_tw.tween_callback(func() -> void: _trail.max_age = 0.14)
	_sword_tw.tween_property(_sword, "rotation_degrees", SWORD_REST_ROT, 0.15)
	_sword_tw.parallel().tween_property(_sword, "position", SWORD_REST_POS, 0.15)


## The spin's whirlwind: a full ring of blade-light and a wider wind ring, a swirling cyclone of
## sparks, leaves and grass, a circle cut into the ground, a dust wall, and a flash.
static func _spin_fx(parent: Node, o: Vector3) -> void:
	var col := Color(0.6, 0.9, 1.15, 0.85)
	for i: int in 4:
		var a0: float = float(i) * PI * 0.5
		HeroFx.slash(parent, o, Basis.IDENTITY, 2.2, a0, a0 + PI * 0.7, col, 0.45, 0.12, 0.3, Color(1.3, 1.4, 1.5))
		HeroFx.slash(parent, o + Vector3(0, 0.15, 0), Basis.IDENTITY, 3.0, a0 + 0.3, a0 + 0.3 + PI * 0.6, Color(0.75, 0.95, 1.1, 0.3), 0.2, 0.16, 0.3, Color(1.0, 1.1, 1.2), true)
	PartyFx.shockwave(parent, o - Vector3(0, 0.7, 0), Color(0.75, 0.95, 1.0), 4.4, 0.45)
	PartyFx.dust_wall(parent, o - Vector3(0, 0.75, 0), 2.0, Color(0.9, 0.88, 0.8, 0.55), 20)
	# the cyclone: a spinning node carries sparks, leaves and grass round and up
	if parent == null or not parent.is_inside_tree():
		return
	var spin := Node3D.new()
	parent.add_child(spin)
	spin.global_position = o - Vector3(0, 0.6, 0)
	spin.add_child(HeroFx.em({"amount": 80, "lifetime": 0.6, "one_shot": true, "explosiveness": 0.6, "local": true,
		"shape": "ring", "ring_radius": 1.9, "ring_inner": 1.2, "ring_height": 0.4, "dir": Vector3.UP, "spread": 20.0,
		"speed": Vector2(1.0, 3.5), "facing": "velocity", "tex": Fx.Tex.SPARK, "size": Vector2(0.1, 0.55),
		"color": Color(0.6, 0.9, 1.2, 0.8), "additive": false, "fixed_fps": 0, "box_aabb": 8.0}))
	spin.add_child(HeroFx.em({"amount": 34, "lifetime": 0.9, "one_shot": true, "explosiveness": 0.6, "local": true,
		"shape": "ring", "ring_radius": 1.6, "ring_inner": 0.8, "ring_height": 0.8, "dir": Vector3.UP, "spread": 30.0,
		"speed": Vector2(1.0, 3.5), "size": Vector2(0.18, 0.1), "curve": "shrink", "angle": Vector2(0, 360),
		"spin": Vector2(-400, 400), "additive": false, "fixed_fps": 0, "box_aabb": 8.0,
		"pick": PackedColorArray([Color(0.35, 0.8, 0.3), Color(0.5, 0.95, 0.35), Color(0.25, 0.6, 0.2)]),
		"fade": PackedFloat32Array([1.0, 1.0, 0.0])}))
	spin.add_child(HeroFx.em({"amount": 16, "lifetime": 0.7, "one_shot": true, "explosiveness": 0.7, "local": true,
		"shape": "ring", "ring_radius": 1.4, "ring_inner": 1.0, "ring_height": 0.2, "dir": Vector3.UP, "spread": 20.0,
		"speed": Vector2(1.0, 2.0), "tex": Fx.Tex.STAR, "size": 0.3, "curve": "pop", "angle": Vector2(0, 360),
		"color": Color(1.2, 1.4, 1.6), "fixed_fps": 0, "box_aabb": 8.0}))
	for c: Node in spin.get_children():
		(c as GPUParticles3D).emitting = true
	var tw: Tween = spin.create_tween()
	tw.tween_property(spin, "rotation:y", -TAU * 2.5, 1.0).set_ease(Tween.EASE_OUT)
	tw.tween_callback(spin.queue_free)
	# a circle cut into the ground round the hero
	var gq := PhysicsRayQueryParameters3D.create(o, o + Vector3(0, -2.0, 0), 1)
	var gh: Dictionary = (parent as Node3D).get_world_3d().direct_space_state.intersect_ray(gq)
	if not gh.is_empty():
		var pts: Array[Vector3] = []
		for k: int in 33:
			var a: float = TAU * float(k) / 32.0
			pts.append(Vector3(cos(a), 0, sin(a)) * (1.9 + randf_range(-0.05, 0.05)))
		PartyFx.glow_lines(parent, gh["position"] as Vector3, [[pts, 0.05]], Color(1.1, 1.7, 2.4), 1.8, gh["normal"] as Vector3)
	PartyFx.flash(parent, o, col, 7.0, 9.0, 0.4)


# ---- tools ----------------------------------------------------------------------------------

func on_cycle() -> void:
	tool = (tool + 1) % TOOLS.size()
	layer.sfx.play("clank", 0.6, 1.5)
	layer.hud.announce(PartyNames.move_name(TOOLS[tool]), Color(0.55, 1.0, 0.5))
	PartyFx.burst(world(), chest(), Color(0.5, 1.0, 0.5), 12, 3.0, 0.15, 0.35)
	HeroFx.ring(world(), chest(), Vector3.UP, Color(0.5, 1.0, 0.45, 0.8), 0.3, 1.0, 0.25, 0.08)


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
	# a smear following both wing tips as it spins, plus a trail of glinting wind
	var smear := HeroFx.Trail.new()
	smear.target = spinner
	smear.a_local = Vector3(0.12, 0, 0)
	smear.b_local = Vector3(0.45, 0, 0.08)
	smear.color = Color(1.0, 0.8, 0.45)
	smear.hot = Color(1.3, 1.1, 0.7)
	smear.max_age = 0.14
	smear.active = true
	pr.add_child(smear)
	pr.add_child(PartyFx.emitter({"amount": 40, "lifetime": 0.35, "size": 0.22, "color": Color(1.0, 0.85, 0.5),
		"vmin": 0.0, "vmax": 0.3, "aabb": 20.0, "colors": [Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)]}))
	pr.add_child(HeroFx.em({"amount": 18, "lifetime": 0.5, "speed": Vector2(0.1, 0.5), "tex": Fx.Tex.STAR,
		"size": 0.16, "curve": "pop", "color": Color(1.3, 1.2, 0.8), "box_aabb": 20.0, "fixed_fps": 0}))
	# a little whirl of wind around it: pale streaks peeling off the spinning wings
	var whirl := HeroFx.em({"amount": 20, "lifetime": 0.3, "shape": "ring", "ring_radius": 0.5, "ring_inner": 0.4,
		"speed": Vector2(1.5, 3.0), "spread": 180.0, "flatness": 1.0, "facing": "velocity", "tex": Fx.Tex.SPARK,
		"size": Vector2(0.04, 0.35), "additive": false, "color": Color(1.0, 1.0, 1.0, 0.5), "fixed_fps": 0, "box_aabb": 20.0})
	spinner.add_child(whirl)
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
	var ch := HeroFx.Chain.new()
	(world() as Node).add_child(ch)
	ch.set_ends(o, _hook_to)
	_chain = ch
	PartyFx.sparks(world(), _hook_to, Color(1.0, 0.9, 0.6), 18, 6.0, hit["normal"] as Vector3, 70.0)
	HeroFx.ring(world(), _hook_to, hit["normal"] as Vector3, Color(1.2, 1.0, 0.6, 0.9), 0.1, 0.9, 0.25, 0.1)
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
		HeroFx.burst(world(), p.global_position + Vector3(0, 0.6, 0), Color(1.2, 1.1, 0.8), 12, 4.0, 0.2, 0.3)


## The hookshot's shot, on every screen: the chain shoots out link by link with sparks
## streaming off it, bites with a burst of chips, sparks and dust, then whips back in.
static func _hook_fx(parent: Node, o: Vector3, to: Vector3, yank: bool) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var ch := HeroFx.Chain.new()
	parent.add_child(ch)
	ch.set_ends(o, to, 0.0)
	var tw: Tween = ch.create_tween()
	tw.tween_method(func(k: float) -> void: ch.set_ends(o, to, k), 0.0, 1.0, 0.1)
	tw.tween_callback(func() -> void:
		PartyFx.sparks(parent, to, Color(1.0, 0.85, 0.5), 26 if yank else 18, 7.0)
		HeroFx.stars(parent, to, Color(1.4, 1.25, 0.7), 6, 3.0, 0.35, 0.2)
		HeroFx.ring(parent, to, (o - to).normalized(), Color(1.2, 1.0, 0.6, 0.9), 0.1, 1.0, 0.22, 0.1)
		if not yank:
			HeroFx.pop(parent, {"amount": 8, "lifetime": 0.7, "facing": "mesh", "mesh": Fx.chunk_mesh(0.08), "spread": 60.0,
				"dir": (o - to).normalized(), "speed": Vector2(2.0, 5.0), "gravity": Vector3(0, -18, 0), "scale": Vector2(0.6, 1.2),
				"curve": "shrink", "spin": Vector2(-400, 400), "angle": Vector2(0, 360), "color": Color(0.55, 0.5, 0.45),
				"fade": PackedFloat32Array([1.0, 1.0])}, to)
			HeroFx.smoke(parent, to, Color(0.8, 0.77, 0.72, 0.45), 6, 0.6, 0.6, 1.2))
	tw.tween_interval(0.08)
	tw.tween_method(func(k: float) -> void: ch.set_ends(o, to, 1.0 - k), 0.0, 1.0, 0.18).set_ease(Tween.EASE_IN)
	tw.tween_callback(ch.queue_free)
	PartyFx.streak(parent, o, to, Color(1.0, 0.9, 0.6), 34, 0.1, 0.35, 0.05, 0.6, true)
	PartyFx.tether(parent, o, to, Color(1.4, 1.2, 0.8), 12, 26.0)


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
	# a round blue bomb with a shine, a cap and a fizzing fuse; it tumbles and throbs red
	var body := Node3D.new()
	pr.add_child(body)
	var shell_mat: StandardMaterial3D = PartyFx.solid_mat(Color(0.12, 0.16, 0.45), 0.2, 0.3, 0.3).duplicate() as StandardMaterial3D
	PartyFx.part(body, PartyFx.sphere_mesh(0.26, 16), shell_mat, Vector3.ZERO)
	PartyFx.part(body, PartyFx.sphere_mesh(0.06, 8), PartyFx.glow_mat(Color(1, 1, 1, 0.8), 1.4, true), Vector3(-0.1, 0.12, -0.18))
	PartyFx.part(body, PartyFx.cyl_mesh(0.07, 0.1), PartyFx.solid_mat(Color(0.5, 0.5, 0.55)), Vector3(0, 0.27, 0))
	var fuse: GPUParticles3D = PartyFx.emitter({"amount": 34, "lifetime": 0.32, "size": 0.1, "color": Color(1.0, 0.75, 0.3),
		"vmin": 1.5, "vmax": 3.8, "dir": Vector3.UP, "spread": 60.0, "gravity": Vector3(0, -6, 0), "spark": true, "aabb": 20.0})
	fuse.position = Vector3(0, 0.34, 0)
	body.add_child(fuse)
	var puff: GPUParticles3D = HeroFx.em({"amount": 16, "lifetime": 0.6, "speed": Vector2(0.1, 0.4), "tex": Fx.Tex.SMOKE,
		"additive": false, "size": 0.28, "curve": "puff", "angle": Vector2(0, 360), "color": Color(0.5, 0.5, 0.52, 0.5),
		"fade": PackedFloat32Array([0.0, 0.8, 0.0]), "box_aabb": 20.0, "fixed_fps": 0})
	puff.position = Vector3(0, 0.36, 0)
	body.add_child(puff)
	var spark_glow: MeshInstance3D = HeroFx.glow_sprite(body, Color(1.5, 1.0, 0.4, 0.9), 0.3, Fx.Tex.STAR, Vector3(0, 0.36, 0))
	var tw: Tween = body.create_tween().set_loops()
	tw.tween_property(body, "rotation:x", TAU, 0.6).from(0.0)
	var th: Tween = pr.create_tween().set_loops()
	th.tween_method(func(k: float) -> void:
		shell_mat.albedo_color = Color(0.12, 0.16, 0.45).lerp(Color(0.9, 0.15, 0.1), k * k)
		body.scale = Vector3.ONE * (1.0 + 0.12 * k * k)
		spark_glow.rotation.z = k * TAU, 0.0, 1.0, 0.25)
	var boom := func(pos: Vector3) -> void: _bomb_boom(layer_ref, key, pos, true)
	pr.on_world = func(pos: Vector3, n: Vector3) -> void: boom.call(pos + n * 0.3)
	pr.on_expire = boom
	pr.on_target = func(_t: Dictionary, pos: Vector3) -> bool:
		boom.call(pos)
		return true
	layer_ref.add_child(pr)
	return pr


## A cartoon blast: a white pop, puffy orange-to-grey smoke balls, star-shaped sparks, burning
## chunks that spark where they land, a ring and a wall of dust, a scorch mark with a few
## cracks, drifting embers and a "BOOM!".
static func _bomb_boom(layer_ref: PartyLayer, key: String, pos: Vector3, is_local: bool) -> void:
	HeroFx.orb(layer_ref, pos, Color(1.0, 0.95, 0.8, 1.0), 0.3, 1.8, 0.12)
	HeroFx.orb(layer_ref, pos, Color(1.0, 0.55, 0.15, 0.8), 0.5, 2.6, 0.3, false)
	HeroFx.fireball(layer_ref, pos, 2.6, 34, Color(1.3, 1.15, 0.7), Color(1.15, 0.5, 0.08), Color(0.4, 0.37, 0.4, 0.75))
	HeroFx.smoke(layer_ref, pos + Vector3(0, 0.4, 0), Color(0.55, 0.52, 0.55, 0.6), 14, 1.6, 1.6, 2.5)
	HeroFx.stars(layer_ref, pos, Color(1.4, 1.2, 0.5), 16, 8.0, 0.5, 0.4)
	HeroFx.sparks(layer_ref, pos, Color(1.5, 1.1, 0.5), 40, 13.0, Vector3.UP, 90.0, 0.55)
	HeroFx.ring(layer_ref, pos + Vector3(0, -0.2, 0), Vector3.UP, Color(1.2, 0.9, 0.4, 0.9), 0.4, 3.8, 0.35, 0.06)
	var gq := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0.5, 0), pos + Vector3(0, -2.5, 0), 1)
	var gh: Dictionary = layer_ref.get_world_3d().direct_space_state.intersect_ray(gq)
	var ground: Vector3 = gh["position"] if not gh.is_empty() else pos - Vector3(0, 0.3, 0)
	HeroFx.ground_ring(layer_ref, ground, Color(1.2, 0.8, 0.3), 3.0, 0.35)
	PartyFx.dust_wall(layer_ref, ground, 1.8, Color(0.85, 0.8, 0.72, 0.6), 18)
	PartyFx.burning_debris(layer_ref, pos + Vector3(0, 0.2, 0), 6, 8.0, Color(2.2, 0.9, 0.25), Color(0.3, 0.26, 0.24), 0.7)
	if not gh.is_empty():
		PartyFx.scorch(layer_ref, ground, 1.5, 2.8, Color(1.0, 0.55, 0.2))
		PartyFx.ground_cracks(layer_ref, ground, 1.8, Color(2.2, 0.9, 0.25), 7, 1.8, 0, gh["normal"] as Vector3)
	if PartyFx.rich():
		PartyFx.embers(layer_ref, pos, 0.9, Color(2.4, 1.0, 0.3), 24, 1.6, 1.4)
	HeroFx.flash(layer_ref, pos, Color(1.0, 0.7, 0.3), 10.0, 12.0, 0.5)
	PartyFx.popup_text(layer_ref, pos + Vector3(0, 1.4, 0), "BOOM!", Color(1.0, 0.75, 0.25), 110)
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
			_spin_anim()
			layer.sfx.play_at("whoosh", v3(d.get("o", [])), 0.9, 0.8)
		"charge":
			var on: bool = bool(d.get("on", false))
			if _charge_fx != null:
				_charge_fx.emitting = on
			_charge = 0.0 if on else -1.0
			_charge_pose(on)
		_:
			remote_fx(layer, owner_id, action, d)


func remote_tick(dt: float) -> void:
	if _charge >= 0.0:
		_charge += dt


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
		PartyFx.burst(world(), global_position + Vector3(0, 0.8, 0), Color(0.45, 1.0, 0.4), 40, 5.0, 0.25)
		HeroFx.stars(world(), global_position + Vector3(0, 0.8, 0), Color(1.3, 1.2, 0.6), 14, 3.0, 0.4, 0.5)
		HeroFx.ring(world(), global_position + Vector3(0, 0.1, 0), Vector3.UP, Color(0.5, 1.0, 0.45, 0.8), 0.3, 2.0, 0.4, 0.05)
		HeroFx.smoke(world(), global_position + Vector3(0, 0.7, 0), Color(0.85, 0.95, 0.8, 0.45), 10, 0.8, 0.8, 1.2)
		HeroFx.pop(world(), {"amount": 22, "lifetime": 1.3, "shape": "sphere", "radius": 0.5, "dir": Vector3.UP,
			"spread": 60.0, "speed": Vector2(0.5, 1.5), "gravity": Vector3(0, -0.8, 0), "size": Vector2(0.16, 0.09), "curve": "shrink",
			"angle": Vector2(0, 360), "spin": Vector2(-300, 300), "additive": false, "color": Color(0.45, 0.9, 0.35),
			"explosiveness": 0.7}, global_position + Vector3(0, 0.8, 0))
