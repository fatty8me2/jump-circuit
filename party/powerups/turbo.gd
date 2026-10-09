extends PowerUp
## Turbo Boost (3.5 s): a pair of blue-white rocket nozzles ignite on your heels and kick you
## forward - you run 1.6x as fast until the fuel is gone (the flames sputter for the last
## second). A burst of speed for catching up, rolled mostly in the back half of the pack.

const BLUE := Color(0.45, 0.8, 1.0)
const FLAME := Color(1.0, 0.7, 0.3)
const SPEED: float = 1.6
## The ignition adds this much forward speed on the spot (and no more than the cap in total).
const KICK: float = 7.0

var _t: float = 0.0
var _jets: Array[GPUParticles3D] = []
var _cores: Array[MeshInstance3D] = []
var _trail_t: float = 0.0


func _init() -> void:
	duration = 3.5


func mods() -> Vector3:
	return Vector3(SPEED, 1.0, 1.0)


func build_look() -> void:
	var steel: StandardMaterial3D = PartyFx.solid_mat(Color(0.8, 0.84, 0.92), 0.15, 0.3, 0.8)
	var blue: StandardMaterial3D = PartyFx.solid_mat(Color(0.2, 0.5, 1.0), 0.6, 0.35, 0.3)
	for sx: float in [-1.0, 1.0]:
		var boot := Node3D.new()
		boot.position = Vector3(sx * 0.17, 0.12, 0.12)
		add_child(boot)
		# a rocket cuff round each ankle with a nozzle at the heel
		PartyFx.part(boot, PartyFx.cyl_mesh(0.14, 0.14, 0.12), steel, Vector3.ZERO)
		PartyFx.part(boot, PartyFx.cyl_mesh(0.1, 0.1, 0.16), blue, Vector3(0, -0.02, 0.17), Vector3.ONE, Vector3(90, 0, 0))
		PartyFx.part(boot, PartyFx.box_mesh(Vector3(0.03, 0.18, 0.1)), blue, Vector3(sx * 0.12, 0.0, 0.05))
		var core: MeshInstance3D = PartyFx.part(boot, PartyFx.cone_mesh(0.08, 0.5, 10), PartyFx.glow_mat(Color(0.7, 0.9, 1.0, 0.8), 2.4, true),
			Vector3(0, -0.02, 0.5), Vector3.ONE, Vector3(-90, 0, 0))
		_cores.append(core)
		# the exhaust: a white-hot core inside a blue plume, streaming straight back
		var jet: GPUParticles3D = PartyFx.emitter({"amount": 26, "lifetime": 0.16, "size": Vector2(0.08, 0.5), "color": Color(1.3, 1.5, 1.7),
			"tex": "streak", "facing": "velocity", "dir": Vector3(0, 0, 1), "spread": 4.0, "vmin": 7.0, "vmax": 9.0, "aabb": 8.0,
			"colors": [Color(1, 1, 1, 1), Color(1, 1, 1, 0)]})
		jet.position = Vector3(0, -0.02, 0.28)
		boot.add_child(jet)
		_jets.append(jet)
		var plume: GPUParticles3D = PartyFx.emitter({"amount": 40, "lifetime": 0.32, "size": 0.28, "color": BLUE,
			"dir": Vector3(0, 0, 1), "spread": 12.0, "vmin": 5.0, "vmax": 8.0, "aabb": 8.0,
			"colors": [Color(1.0, 1.0, 1.0, 1.0), Color(0.4, 0.7, 1.0, 0.9), Color(1.0, 0.5, 0.2, 0.5), Color(0.2, 0.1, 0.3, 0.0)]})
		plume.position = Vector3(0, -0.02, 0.3)
		boot.add_child(plume)
		_jets.append(plume)
		PartyFx.pop_in(boot, 0.3)
	# a long glowing smear of speed trailing behind the wearer
	var wake: GPUParticles3D = PartyFx.emitter({"amount": 30, "lifetime": 0.5, "size": Vector2(0.06, 0.8), "color": Color(0.7, 0.9, 1.5, 0.7),
		"tex": "streak", "facing": "velocity", "shape": "box", "extents": Vector3(0.35, 0.5, 0.1), "dir": Vector3(0, 0, 1),
		"spread": 3.0, "vmin": 1.0, "vmax": 3.0, "aabb": 10.0, "fixed_fps": 0})
	wake.position = Vector3(0, 0.7, 0.45)
	add_child(wake)
	_jets.append(wake)
	if is_inside_tree():
		_ignite_fx(world(), global_position)


## Ignition: a ring of blue fire and dust round the feet, a streak of sparks, a punchy shockwave.
static func _ignite_fx(parent: Node, at: Vector3) -> void:
	PartyFx.burst(parent, at + Vector3(0, 0.3, 0), BLUE, 36, 7.0, 0.28, 0.5)
	PartyFx.ring_pulse(parent, at + Vector3(0, 0.1, 0), Vector3.UP, Color(0.6, 0.9, 1.0), 0.3, 2.6, 0.35, 0.16)
	PartyFx.shockwave(parent, at, Color(0.5, 0.8, 1.0), 3.2, 0.35)
	PartyFx.star_ring(parent, at + Vector3(0, 0.5, 0), Color(0.8, 0.95, 1.0), 8, 5.0, 0.35)
	PartyFx.one_shot(parent, at + Vector3(0, 0.2, 0), {"amount": 22, "lifetime": 0.7, "size": 0.8, "color": Color(0.85, 0.85, 0.82, 0.5),
		"additive": false, "tex": "smoke", "shape": "ring", "radius": 0.4, "inner": 0.2, "dir": Vector3(1, 0.1, 0), "spread": 180.0,
		"flat": 1.0, "vmin": 3.0, "vmax": 6.0, "damping": 5.0, "grow": true, "angle": true,
		"colors": [Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)]})
	PartyFx.sparks(parent, at + Vector3(0, 0.3, 0), Color(1.0, 0.85, 0.5), 20, 8.0, Vector3.UP, 70.0)
	PartyFx.flash(parent, at + Vector3(0, 0.4, 0), BLUE, 5.0, 7.0, 0.3)


func begin() -> void:
	var p: Player = player()
	var fwd := Vector3(p.velocity.x, 0, p.velocity.z)
	var dir: Vector3 = fwd.normalized() if fwd.length() > 1.0 else Vector3(p.facing_dir.x, 0, p.facing_dir.z).normalized()
	if dir.length() < 0.1:
		dir = layer.aim_dir()
	# a kick forward on top of the new top speed (the multiplier alone only raises the cap)
	p.add_impulse(dir * KICK)
	layer.sfx.play("turbo", 1.0, 1.0)
	PartyFx.shake(layer.level, 0.25)


func _process(dt: float) -> void:
	_t += dt
	var left: float = time_left - (0.0 if local else 1.0)
	# the last second: the nozzles cough and the glow flickers out
	var cough: bool = left > 1.0 or fmod(_t * 12.0, 1.0) < 0.55
	for j: GPUParticles3D in _jets:
		j.emitting = cough and not ended
	for c: MeshInstance3D in _cores:
		var fl: float = 1.0 + sin(_t * 50.0 + float(c.get_index())) * 0.15
		c.scale = Vector3(fl, fl * (1.0 if cough else 0.3), fl)


func tick(dt: float) -> void:
	# dust kicked up at the heels and an echo of speed lines while we are really moving
	_trail_t -= dt
	if _trail_t > 0.0 or not is_inside_tree():
		return
	_trail_t = 0.1
	var p: Player = player()
	var hv := Vector3(p.velocity.x, 0, p.velocity.z)
	if hv.length() < 4.0:
		return
	var dir: Vector3 = hv.normalized()
	if p.grounded:
		PartyFx.smoke(world(), feet() + Vector3(0, 0.15, 0) - dir * 0.3, Color(0.8, 0.78, 0.72, 0.4), 3, 0.25, 0.5)
	PartyFx.speed_lines(world(), chest() - dir * 0.8, chest() - dir * 3.0, Color(0.8, 1.4, 1.7, 0.6), 4, 0.5)


func on_end() -> void:
	if not is_inside_tree():
		return
	# out of fuel: a last cough of smoke and a few falling sparks
	PartyFx.smoke(world(), global_position + Vector3(0, 0.2, 0.3), Color(0.3, 0.3, 0.36, 0.5), 8, 0.3, 0.8)
	PartyFx.sparks(world(), global_position + Vector3(0, 0.2, 0.3), Color(1.0, 0.7, 0.3), 10, 4.0, Vector3.DOWN, 60.0)
