extends PowerUp
## Jetpack (5 s): twin rockets strapped on. Using it fires a big burst up and forward; then
## gravity halves for a floaty glide, and holding Jump thrusts you upward (fuel permitting).

const FLAME := Color(1.0, 0.6, 0.2)
## Seconds of thrust in the tank.
const FUEL: float = 2.2

var fuel: float = FUEL
var _thrusting: bool = false
var _flames: Array[GPUParticles3D] = []
var _cores: Array[MeshInstance3D] = []
var _jets: Array[GPUParticles3D] = []
var _smoke: GPUParticles3D
var _haze: MeshInstance3D
var _spits: GPUParticles3D
var _t: float = 0.0
var _puff_t: float = 0.0
## Mirrors learn thrust from "thrust" messages; the fuel gauge only exists on the owner.
var _on: bool = false


func _init() -> void:
	duration = 5.0


func mods() -> Vector3:
	return Vector3(1.25, 1.1, 0.5)


func build_look() -> void:
	var steel: StandardMaterial3D = PartyFx.solid_mat(Color(0.75, 0.78, 0.84), 0.1, 0.3, 0.8)
	var orange: StandardMaterial3D = PartyFx.solid_mat(Color(1.0, 0.5, 0.15), 0.3, 0.4, 0.3)
	for sx: float in [-1.0, 1.0]:
		var tank := Node3D.new()
		tank.position = Vector3(sx * 0.16, 0.62, 0.44)
		add_child(tank)
		PartyFx.part(tank, PartyFx.cyl_mesh(0.11, 0.46), orange, Vector3.ZERO)
		PartyFx.part(tank, PartyFx.sphere_mesh(0.11, 12), orange, Vector3(0, 0.23, 0))
		PartyFx.part(tank, PartyFx.cyl_mesh(0.07, 0.12, 0.1), steel, Vector3(0, -0.29, 0))
		PartyFx.part(tank, PartyFx.box_mesh(Vector3(0.04, 0.3, 0.14)), steel, Vector3(sx * 0.1, 0.02, 0.02))
		PartyFx.part(tank, PartyFx.cyl_mesh(0.115, 0.04), steel, Vector3(0, 0.1, 0))
		var core: MeshInstance3D = PartyFx.part(tank, PartyFx.cone_mesh(0.07, 0.35, 10), PartyFx.glow_mat(Color(1.0, 0.85, 0.5, 0.8), 2.2, true), Vector3(0, -0.52, 0), Vector3(1, -1, 1))
		_cores.append(core)
		# the flame: a white-hot jet of streaks inside an orange plume
		var jet: GPUParticles3D = PartyFx.emitter({"amount": 24, "lifetime": 0.14, "size": Vector2(0.09, 0.45), "color": Color(1.4, 1.25, 0.9),
			"tex": "streak", "facing": "velocity", "dir": Vector3.DOWN, "spread": 4.0, "vmin": 6.0, "vmax": 8.0, "aabb": 6.0,
			"colors": [Color(1, 1, 1, 1), Color(1, 1, 1, 0)]})
		jet.position = Vector3(0, -0.38, 0)
		tank.add_child(jet)
		_jets.append(jet)
		var flame: GPUParticles3D = PartyFx.emitter({"amount": 40, "lifetime": 0.3, "size": 0.26, "color": FLAME,
			"dir": Vector3.DOWN, "spread": 10.0, "vmin": 5.0, "vmax": 8.0, "aabb": 6.0,
			"colors": [Color(1.0, 1.0, 0.8, 1.0), Color(1.0, 0.55, 0.1, 0.9), Color(0.6, 0.1, 0.05, 0.0)]})
		flame.position = Vector3(0, -0.4, 0)
		tank.add_child(flame)
		_flames.append(flame)
	# a smoke plume left hanging in the air behind, and heat shimmer under the nozzles
	_smoke = PartyFx.emitter({"amount": 30, "lifetime": 1.1, "size": 0.5, "color": Color(0.55, 0.55, 0.6, 0.45),
		"additive": false, "tex": "smoke", "dir": Vector3.DOWN, "spread": 25.0, "vmin": 1.0, "vmax": 2.5, "grow": true,
		"angle": true, "spin": 40.0, "aabb": 10.0, "fixed_fps": 0, "turbulence": 0.8,
		"colors": [Color(1, 1, 1, 0), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0)]})
	_smoke.position = Vector3(0, 0.0, 0.44)
	add_child(_smoke)
	# hot sparks spitting out of the nozzles and falling away behind
	_spits = HeroFx.em({"amount": 30, "lifetime": 0.5, "shape": "box", "extents": Vector3(0.2, 0.05, 0.05),
		"dir": Vector3.DOWN, "spread": 25.0, "speed": Vector2(3.0, 7.0), "gravity": Vector3(0, -12, 0),
		"facing": "velocity", "tex": Fx.Tex.SPARK, "size": Vector2(0.04, 0.22), "fixed_fps": 0, "box_aabb": 10.0,
		"color": Color(2.2, 1.2, 0.4)})
	_spits.position = Vector3(0, -0.05, 0.44)
	add_child(_spits)
	_haze = PartyFx.heat_haze(0.9, 0.012)
	_haze.position = Vector3(0, -0.15, 0.46)
	add_child(_haze)
	if is_inside_tree():
		PartyFx.smoke(world(), global_position + Vector3(0, 0.6, 0.4), Color(0.6, 0.6, 0.65, 0.5), 8, 0.4, 0.7)


func _process(dt: float) -> void:
	_t += dt
	var left: float = time_left - (0.0 if local else 1.0)
	var dry: bool = local and fuel <= 0.0
	# running out (the timer, or the tank): the flames cough and sputter, black puffs
	var sputter: bool = (left < 1.5 or (local and fuel < FUEL * 0.2)) and not ended
	if sputter:
		var cough: bool = fmod(_t * 11.0, 1.0) < (0.35 if dry else 0.6)
		for f: GPUParticles3D in _flames:
			f.emitting = cough
		for j: GPUParticles3D in _jets:
			j.emitting = cough and _on
		_puff_t -= dt
		if _puff_t <= 0.0 and is_inside_tree():
			_puff_t = randf_range(0.18, 0.35)
			PartyFx.smoke(world(), global_position + Vector3(0, 0.2, 0.45), Color(0.15, 0.14, 0.15, 0.55), 4, 0.25, 0.6)
			PartyFx.sparks(world(), global_position + Vector3(0, 0.2, 0.45), Color(1.0, 0.6, 0.2), 5, 3.0, Vector3.DOWN, 50.0)
	elif not ended:
		for f: GPUParticles3D in _flames:
			f.emitting = true
		for j: GPUParticles3D in _jets:
			j.emitting = _on
	if _haze != null:
		var m: ShaderMaterial = _haze.material_override as ShaderMaterial
		m.set_shader_parameter("amount", 1.0 if _on else 0.45)
	# the nozzle glow flickers
	for c: MeshInstance3D in _cores:
		var fl: float = 1.0 + sin(_t * 47.0 + c.get_index()) * 0.12
		c.scale = Vector3(1.3 * fl, -1.8 * fl, 1.3 * fl) if _on else Vector3(fl, -fl, fl)


func begin() -> void:
	var p: Player = player()
	var fwd := Vector3(p.velocity.x, 0, p.velocity.z)
	var dir: Vector3 = fwd.normalized() if fwd.length() > 1.0 else Vector3(p.facing_dir.x, 0, p.facing_dir.z).normalized()
	var along: float = maxf(fwd.length(), 11.0)
	p.velocity = dir * along + Vector3(0, 15.0, 0)
	p.add_impulse(Vector3(0, 0.001, 0))
	_blast_fx(layer, feet())
	layer.sfx.play("boom", 0.8, 1.6)
	layer.sfx.play("whoosh", 1.0, 0.6)
	PartyFx.shake(layer.level, 0.3)
	fx("blast", {"at": arr(feet())})


static func _blast_fx(parent: Node, at: Vector3) -> void:
	PartyFx.one_shot(parent, at + Vector3(0, 0.3, 0), {"amount": 60, "lifetime": 0.6, "size": 0.5, "color": FLAME,
		"dir": Vector3.DOWN, "spread": 70.0, "vmin": 6.0, "vmax": 12.0, "damping": 10.0,
		"colors": [Color(1, 1, 0.8, 1), Color(1, 0.5, 0.1, 0.8), Color(0.3, 0.1, 0.05, 0)]})
	PartyFx.smoke(parent, at + Vector3(0, 0.3, 0), Color(0.45, 0.45, 0.5, 0.6), 20, 1.0, 1.4)
	# a ring of dust thrown out along the ground, streaking sparks and a scorch
	PartyFx.one_shot(parent, at + Vector3(0, 0.2, 0), {"amount": 26, "lifetime": 0.8, "size": 0.9,
		"color": Color(0.75, 0.72, 0.68, 0.55), "additive": false, "tex": "smoke", "shape": "ring", "radius": 0.4,
		"inner": 0.2, "dir": Vector3(1, 0.1, 0), "spread": 180.0, "flat": 1.0, "vmin": 4.0, "vmax": 7.0, "damping": 6.0,
		"grow": true, "angle": true, "colors": [Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)]})
	PartyFx.one_shot(parent, at + Vector3(0, 0.3, 0), {"amount": 24, "lifetime": 0.45, "size": Vector2(0.07, 0.6),
		"color": Color(1.5, 1.0, 0.5), "tex": "streak", "facing": "velocity", "dir": Vector3.UP, "spread": 60.0,
		"vmin": 6.0, "vmax": 12.0, "gravity": Vector3(0, -12, 0), "colors": [Color(1, 1, 1, 1), Color(1, 1, 1, 0)]})
	PartyFx.scorch(parent, at, 1.1, 1.6, FLAME)
	PartyFx.shockwave(parent, at, FLAME, 3.0, 0.35)
	PartyFx.speed_lines(parent, at, at + Vector3(0, 4.0, 0), Color(1.4, 1.3, 1.2, 0.6), 12, 0.6)
	PartyFx.flash(parent, at + Vector3(0, 0.5, 0), FLAME, 7.0, 7.0, 0.35)
	PartyFx.dust_wall(parent, at, 1.6, Color(0.78, 0.75, 0.7, 0.55), 18)
	PartyFx.ground_cracks(parent, at, 1.3, Color(2.2, 0.9, 0.25), 6, 1.6)
	if PartyFx.rich():
		PartyFx.embers(parent, at + Vector3(0, 0.4, 0), 0.6, Color(2.4, 1.0, 0.3), 20, 1.2, 1.2)


func tick(dt: float) -> void:
	var p: Player = player()
	var held: bool = p.cmd_jump
	if p.use_device_input:
		held = Input.is_action_pressed("jump")
	var on: bool = held and fuel > 0.0 and p.control_enabled and p.party_stun <= 0.0 and not p.grounded
	if on:
		fuel -= dt
		if p.velocity.y < 7.5:
			p.velocity.y = minf(p.velocity.y + 42.0 * dt, 7.5)
	if on != _thrusting:
		_thrusting = on
		fx("thrust", {"on": on})
		if on:
			layer.sfx.play("whoosh", 0.6, 0.7)
	_show_thrust(on)


func _show_thrust(on: bool) -> void:
	_on = on
	for f: GPUParticles3D in _flames:
		f.speed_scale = 1.6 if on else 1.0
		f.amount_ratio = 1.0 if on else 0.45
	for j: GPUParticles3D in _jets:
		j.emitting = on
	if _smoke != null:
		_smoke.amount_ratio = 1.0 if on else 0.4
	if _spits != null:
		_spits.amount_ratio = 1.0 if on else 0.3
	for c: MeshInstance3D in _cores:
		c.scale = Vector3(1.3, -1.8, 1.3) if on else Vector3(1, -1, 1)


func hud_status() -> String:
	return "Hold %s: thrust   fuel %d%%" % [Game.prompt("jump"), int(clampf(fuel / FUEL, 0.0, 1.0) * 100.0)]


func charge_frac() -> float:
	return clampf(fuel / FUEL, 0.0, 1.0)


func remote(action: String, d: Dictionary) -> void:
	match action:
		"thrust":
			_show_thrust(bool(d.get("on", false)))
		"blast":
			remote_fx(layer, owner_id, action, d)


static func remote_fx(layer_ref: PartyLayer, _from_id: int, action: String, d: Dictionary) -> void:
	if action == "blast":
		_blast_fx(layer_ref, PowerUp.v3(d.get("at", [])))
		layer_ref.sfx.play_at("boom", PowerUp.v3(d.get("at", [])), 0.8, 1.6)


func on_end() -> void:
	if is_inside_tree():
		# out of juice: a last cough of black smoke, a pop and a few bits of hot metal
		var at: Vector3 = global_position + Vector3(0, 0.6, 0.4)
		PartyFx.smoke(world(), at, Color(0.2, 0.19, 0.2, 0.6), 12, 0.6, 1.0)
		PartyFx.burst(world(), at, FLAME, 16, 3.5, 0.2, 0.35)
		PartyFx.sparks(world(), at, Color(1.0, 0.7, 0.3), 12, 5.0)
		PartyFx.debris(world(), at, Color(1.0, 0.5, 0.15), 5, 3.0, 0.09)
