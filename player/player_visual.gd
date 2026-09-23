class_name PlayerVisual
extends Node3D
## "Volt" - a round little courier robot. Purely cosmetic: squash/stretch, lean,
## foot cycle and particles are animated here and never touch the collider.
## Used both by the local Player and by RemoteRacer ghosts.

## A foot planted while moving on the ground (the local Player turns it into a quiet tick).
signal footstep(speed: float)

var accent: Color = Color(1.0, 0.72, 0.2)

var _root: Node3D          # squash/stretch + lean pivot (at the feet)
var _body: MeshInstance3D
var _foot_l: MeshInstance3D
var _foot_r: MeshInstance3D
var _bulb: MeshInstance3D
var _bulb_mat: StandardMaterial3D
var _antenna: Node3D
var _dust: GPUParticles3D        # landing puffs
var _jump_dust: GPUParticles3D   # takeoff / bounce puffs (own emitter, so a quick jump can't wipe a landing puff)
var _trail: GPUParticles3D

var _squash: float = 0.0       # spring displacement: + stretch, - squash
var _squash_vel: float = 0.0
var _yaw: float = 0.0
var _lean: Vector2 = Vector2.ZERO
var _stride: float = 0.0
var _flare: float = 0.0
var _prev_hvel: Vector3 = Vector3.ZERO
var _antenna_sway: Vector2 = Vector2.ZERO
## Set by the player each frame while wall running: -1 wall on the left, +1 on the right.
var wall_roll: float = 0.0
var _step_quiet: float = 0.0   # no footstep right on top of a jump / land / bounce sound


func _ready() -> void:
	_build()


func set_accent(c: Color) -> void:
	accent = c
	if _body != null:
		_apply_colors()


func _mat(color: Color, rough: float = 0.55, metal: float = 0.0, emit: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emit
	return m


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	mi.layers = 2
	parent.add_child(mi)
	return mi


func _build() -> void:
	_root = Node3D.new()
	add_child(_root)
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 28
	sphere.rings = 14
	# body: a plump shell
	_body = _part(_root, sphere, _mat(Color(0.96, 0.94, 0.88), 0.4), Vector3(0, 0.62, 0), Vector3(0.78, 0.86, 0.78))
	# accent belt
	var belt := TorusMesh.new()
	belt.inner_radius = 0.33
	belt.outer_radius = 0.41
	belt.rings = 28
	belt.ring_segments = 10
	var belt_mi := _part(_root, belt, _mat(accent, 0.45), Vector3(0, 0.47, 0), Vector3(1, 0.9, 1))
	belt_mi.name = "Belt"
	# visor + eyes (front is -Z)
	_part(_root, sphere, _mat(Color(0.08, 0.1, 0.16), 0.15, 0.3), Vector3(0, 0.74, -0.2), Vector3(0.56, 0.3, 0.42))
	var eye_mat := _mat(Color(0.5, 0.97, 1.0), 0.3, 0.0, 3.0)
	_part(_root, sphere, eye_mat, Vector3(-0.11, 0.75, -0.385), Vector3(0.09, 0.12, 0.06))
	_part(_root, sphere, eye_mat, Vector3(0.11, 0.75, -0.385), Vector3(0.09, 0.12, 0.06))
	# backpack
	var box := BoxMesh.new()
	box.size = Vector3(0.34, 0.3, 0.16)
	var pack := _part(_root, box, _mat(accent.darkened(0.25), 0.5), Vector3(0, 0.62, 0.33))
	pack.name = "Pack"
	# antenna
	_antenna = Node3D.new()
	_antenna.position = Vector3(0, 1.02, 0.02)
	_root.add_child(_antenna)
	var rod := CylinderMesh.new()
	rod.top_radius = 0.012
	rod.bottom_radius = 0.02
	rod.height = 0.3
	_part(_antenna, rod, _mat(Color(0.25, 0.27, 0.33), 0.4, 0.6), Vector3(0, 0.15, 0))
	_bulb_mat = _mat(accent, 0.3, 0.0, 2.0)
	_bulb = _part(_antenna, sphere, _bulb_mat, Vector3(0, 0.33, 0), Vector3.ONE * 0.12)
	# feet
	var foot_mat := _mat(Color(0.16, 0.18, 0.26), 0.6)
	_foot_l = _part(_root, sphere, foot_mat, Vector3(-0.17, 0.09, 0), Vector3(0.24, 0.17, 0.34))
	_foot_r = _part(_root, sphere, foot_mat, Vector3(0.17, 0.09, 0), Vector3(0.24, 0.17, 0.34))
	_dust = _make_burst(Color(1, 1, 1, 0.75))
	add_child(_dust)
	_jump_dust = _make_burst(Color(1, 1, 1, 0.75))
	add_child(_jump_dust)
	_trail = _make_trail()
	add_child(_trail)


func _apply_colors() -> void:
	(_root.get_node("Belt") as MeshInstance3D).material_override = _mat(accent, 0.45)
	(_root.get_node("Pack") as MeshInstance3D).material_override = _mat(accent.darkened(0.25), 0.5)
	_bulb_mat.albedo_color = accent
	_bulb_mat.emission = accent


func _puff_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_color = color
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 64
	tex.height = 64
	m.albedo_texture = tex
	return m


func _fade_ramp() -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


func _make_burst(color: Color) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 14
	p.lifetime = 0.45
	p.explosiveness = 0.95
	p.layers = 2
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0.25, 0)
	pm.spread = 85.0
	pm.flatness = 0.85
	pm.initial_velocity_min = 1.6
	pm.initial_velocity_max = 3.4
	pm.gravity = Vector3(0, -1.5, 0)
	pm.damping_min = 4.0
	pm.damping_max = 6.0
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	pm.color_ramp = _fade_ramp()
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.34, 0.34)
	q.material = _puff_material(color)
	p.draw_pass_1 = q
	p.position = Vector3(0, 0.08, 0)
	return p


func _make_trail() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.emitting = false
	p.amount = 24
	p.lifetime = 0.5
	p.layers = 2
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.2
	pm.scale_min = 0.35
	pm.scale_max = 0.6
	pm.color_ramp = _fade_ramp()
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.22, 0.22)
	q.material = _puff_material(Color(1, 1, 1, 0.5))
	p.draw_pass_1 = q
	p.position = Vector3(0, 0.5, 0)
	return p


# ---- events -------------------------------------------------------------

func on_jump() -> void:
	_squash_vel += 5.5
	_flare = 1.0
	_step_quiet = 0.12
	_jump_dust.amount_ratio = 0.5
	_jump_dust.restart()


func on_land(impact: float) -> void:
	var k: float = clampf(impact / 22.0, 0.15, 1.0)
	_squash_vel -= 9.0 * k
	_step_quiet = 0.12
	_dust.amount_ratio = clampf(k + 0.2, 0.3, 1.0)
	_dust.restart()


func on_bounce(_strength: float) -> void:
	_squash = -0.3
	_squash_vel = 10.0
	_flare = 1.6
	_step_quiet = 0.12
	_jump_dust.amount_ratio = 1.0
	_jump_dust.restart()


## Caught a ledge: stretch up toward it, then the landing squash follows on top.
func on_mantle() -> void:
	_squash_vel += 6.0
	_step_quiet = 0.12


## Banked a checkpoint: bulb flare and a little hop of the body.
func on_checkpoint() -> void:
	_flare = maxf(_flare, 1.2)
	_squash_vel += 4.0


## Crossed the finish: a big stretch and the brightest bulb flash.
func on_cheer() -> void:
	_squash_vel += 7.0
	_flare = 1.6


## Respawn arrival: drops the motion carried over from the death pose (lean, squash,
## antenna swing, the stale velocity that would jolt the lean for a frame) and pops
## in with a small spring and a bulb glow.
func on_respawn() -> void:
	if _root == null:
		return
	_prev_hvel = Vector3.ZERO
	_lean = Vector2.ZERO
	_antenna_sway = Vector2.ZERO
	_squash = -0.2
	_squash_vel = 4.0
	_flare = maxf(_flare, 1.4)
	_step_quiet = 0.12
	_foot_l.position = Vector3(-0.17, 0.09, 0)
	_foot_r.position = Vector3(0.17, 0.09, 0)
	_trail.emitting = false


func snap_facing(dir: Vector3) -> void:
	if dir.length() > 0.01:
		_yaw = atan2(-dir.x, -dir.z)


# ---- per-frame ----------------------------------------------------------

## vel: world velocity, on_floor: grounded, facing: desired horizontal facing.
func animate(dt: float, vel: Vector3, on_floor: bool, facing: Vector3) -> void:
	if _root == null or dt <= 0.0:
		return
	_step_quiet = maxf(_step_quiet - dt, 0.0)
	# facing
	if facing.length() > 0.01:
		var target_yaw: float = atan2(-facing.x, -facing.z)
		_yaw = lerp_angle(_yaw, target_yaw, 1.0 - exp(-14.0 * dt))
	rotation.y = _yaw
	# squash & stretch: a damped spring that velocity and events push around
	var target: float = 0.0
	if not on_floor:
		target = clampf(absf(vel.y) * 0.014, 0.0, 0.2)
	# sub-stepped: this stiff spring overshoots and flip-flops between the clamps if
	# it takes a long frame (a ~0.1 s hitch) in one step; at 60+ fps it is one step
	var n: int = mini(ceili(dt * 50.0), 8)
	var h: float = dt / float(n)
	for i: int in n:
		var accel: float = (target - _squash) * 190.0 - _squash_vel * 15.0
		_squash_vel += accel * h
		_squash = clampf(_squash + _squash_vel * h, -0.42, 0.42)
	var sy: float = 1.0 + _squash
	var sxz: float = 1.0 / sqrt(maxf(sy, 0.3))
	_root.scale = Vector3(sxz, sy, sxz)
	# lean into acceleration and speed (local space)
	var hvel := Vector3(vel.x, 0, vel.z)
	var acc: Vector3 = (hvel - _prev_hvel) / dt
	_prev_hvel = hvel
	var inv: Basis = Basis(Vector3.UP, -_yaw)
	var local_acc: Vector3 = inv * acc
	var local_vel: Vector3 = inv * hvel
	var lean_target := Vector2(
		clampf(-local_acc.z * 0.004 - local_vel.z * 0.012, -0.3, 0.35),
		clampf(-local_acc.x * 0.004, -0.25, 0.25))
	if not on_floor:
		lean_target.x += clampf(-vel.y * 0.012, -0.25, 0.3)
	# lean the body away from a wall we run on (feet on the wall, head out)
	lean_target.y += wall_roll * 0.42
	_lean = _lean.lerp(lean_target, 1.0 - exp(-9.0 * dt))
	_root.rotation = Vector3(-_lean.x, 0, _lean.y)
	# feet
	var speed: float = hvel.length()
	if on_floor:
		var prev: float = _stride
		_stride += dt * (4.0 + speed * 1.55)
		# a foot plants each time the stride phase crosses a multiple of PI
		if speed > 1.5 and _step_quiet <= 0.0 and floori(prev / PI) != floori(_stride / PI):
			footstep.emit(speed)
		var amp: float = clampf(speed / 9.0, 0.0, 1.0)
		var s: float = sin(_stride)
		_foot_l.position = Vector3(-0.17, 0.09 + maxf(s, 0.0) * 0.16 * amp, -cos(_stride) * 0.24 * amp)
		_foot_r.position = Vector3(0.17, 0.09 + maxf(-s, 0.0) * 0.16 * amp, cos(_stride) * 0.24 * amp)
		_body.position.y = 0.62 + absf(cos(_stride)) * 0.035 * amp
	else:
		var tuck: float = clampf(vel.y * 0.02, -0.12, 0.16)
		_foot_l.position = _foot_l.position.lerp(Vector3(-0.19, 0.16 + tuck, 0.1), 1.0 - exp(-12.0 * dt))
		_foot_r.position = _foot_r.position.lerp(Vector3(0.19, 0.12 + tuck, -0.06), 1.0 - exp(-12.0 * dt))
	# antenna drags behind motion
	var sway_target := Vector2(clampf(local_vel.z * 0.03 + vel.y * 0.02, -0.6, 0.6), clampf(-local_vel.x * 0.03, -0.5, 0.5))
	_antenna_sway = _antenna_sway.lerp(sway_target, 1.0 - exp(-7.0 * dt))
	_antenna.rotation = Vector3(_antenna_sway.x, 0, _antenna_sway.y)
	_flare = maxf(_flare - dt * 2.5, 0.0)
	_bulb_mat.emission_energy_multiplier = 2.0 + _flare * 7.0
	_bulb.scale = Vector3.ONE * (0.12 + _flare * 0.05)
	# speed streak: carried momentum (the same > 11 m/s as the HUD readout and the FOV
	# kick), plus big launches (pads, flings off rising platforms); plain hops stay clean
	var rise: float = 0.0 if on_floor else vel.y
	var streak: bool = speed > 11.0 or rise > 15.0
	_trail.emitting = streak
	if streak:
		_trail.amount_ratio = clampf((maxf(speed, rise) - 9.0) / 12.0, 0.35, 1.0)
		_trail.position.y = 0.28 if on_floor else 0.5
