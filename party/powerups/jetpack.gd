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
var _smoke: GPUParticles3D


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
		var core: MeshInstance3D = PartyFx.part(tank, PartyFx.cone_mesh(0.07, 0.35, 10), PartyFx.glow_mat(Color(1.0, 0.85, 0.5, 0.8), 3.0, true), Vector3(0, -0.52, 0), Vector3(1, -1, 1))
		_cores.append(core)
		var flame: GPUParticles3D = PartyFx.emitter({"amount": 40, "lifetime": 0.3, "size": 0.26, "color": FLAME,
			"dir": Vector3.DOWN, "spread": 10.0, "vmin": 5.0, "vmax": 8.0, "aabb": 6.0,
			"colors": [Color(1.0, 1.0, 0.8, 1.0), Color(1.0, 0.55, 0.1, 0.9), Color(0.6, 0.1, 0.05, 0.0)]})
		flame.position = Vector3(0, -0.4, 0)
		tank.add_child(flame)
		_flames.append(flame)
	_smoke = PartyFx.emitter({"amount": 24, "lifetime": 0.9, "size": 0.45, "color": Color(0.5, 0.5, 0.55, 0.45),
		"additive": false, "dir": Vector3.DOWN, "spread": 25.0, "vmin": 1.0, "vmax": 2.5, "grow": true, "aabb": 8.0,
		"colors": [Color(1, 1, 1, 0), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0)]})
	_smoke.position = Vector3(0, 0.1, 0.44)
	add_child(_smoke)


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
	PartyFx.shockwave(parent, at, FLAME, 3.0, 0.35)
	PartyFx.flash(parent, at + Vector3(0, 0.5, 0), FLAME, 7.0, 7.0, 0.35)


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
	for f: GPUParticles3D in _flames:
		f.speed_scale = 1.6 if on else 1.0
		f.amount_ratio = 1.0 if on else 0.45
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
		PartyFx.smoke(world(), global_position + Vector3(0, 0.6, 0.4), Color(0.5, 0.5, 0.55, 0.5), 12, 0.6, 1.0)
