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

# ---- effects pass (visual/fx.gd): all world-space unless noted, all layer 2 ----
## Outward normal of the wall we run on (set on latch; wall_roll says whether we still are).
var wall_normal: Vector3 = Vector3.ZERO
var _wall_streak: GPUParticles3D   # glowing streak where the feet meet the panel
var _wall_sparks: GPUParticles3D   # sparks scraped off the panel
var _wall_motes: GPUParticles3D    # cyan motes shed behind
var _latch_sparks: GPUParticles3D
var _latch_ring: GPUParticles3D
var _kick_sparks: GPUParticles3D   # wall jump: radial kick off the wall
var _kick_ring: GPUParticles3D
var _kick_trail: GPUParticles3D
var _kick_t: float = 0.0
var _mantle_dust: GPUParticles3D
var _mantle_sparks: GPUParticles3D
var _hop_puff: GPUParticles3D      # the little puff on top of a finished climb
var _mantle_pending: float = 0.0
var _speed_lines: GPUParticles3D
var _speed_k: float = 0.0
var _land_ring: GPUParticles3D     # big landings
var _land_debris: GPUParticles3D
var _land_smoke: GPUParticles3D
var _spring_ring: GPUParticles3D   # pad launches
var _spring_sparkle: GPUParticles3D
var _knock_sparks: GPUParticles3D
var _arrive_column: GPUParticles3D # respawn / teleport arrival (accent)
var _arrive_ring: GPUParticles3D
var _arrive_stars: GPUParticles3D
var _cp_spin: Node3D               # checkpoint banking: a helix of accent stars
var _cp_helix: GPUParticles3D
var _cp_ring: GPUParticles3D
var _light: OmniLight3D            # one reused flash light


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
	_build_fx()


func _apply_colors() -> void:
	(_root.get_node("Belt") as MeshInstance3D).material_override = _mat(accent, 0.45)
	(_root.get_node("Pack") as MeshInstance3D).material_override = _mat(accent.darkened(0.25), 0.5)
	_bulb_mat.albedo_color = accent
	_bulb_mat.emission = accent
	_tint_fx()


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


const WALL_FX: Color = Color(0.3, 0.95, 1.0)   # WallRunPanel.RUN_COLOR
const LIP_FX: Color = Color(1.0, 0.82, 0.22)   # LedgeBlock.LIP_COLOR


## Every move effect is built once, idle until its event (no emitter runs at rest).
func _build_fx() -> void:
	var wall_hot: Color = Fx.hot(WALL_FX, 2.6)
	# wall run: a bright streak painted where the feet scrape the panel, sparks kicked
	# off it, and a wake of cyan motes (all world-space, so they stay on the wall)
	_wall_streak = _fx(Fx.trail({"amount": 44, "lifetime": 0.32, "size": 0.26, "color": wall_hot,
		"shape": "sphere", "radius": 0.06, "speed": Vector2.ZERO, "curve": "shrink",
		"fade": PackedFloat32Array([1.0, 0.7, 0.0])}))
	_wall_sparks = _fx(Fx.sparks({"amount": 36, "lifetime": 0.32, "one_shot": false, "emitting": false,
		"explosiveness": 0.0, "randomness": 0.4, "dir": Vector3(0, 0.45, 1), "spread": 35.0,
		"speed": Vector2(2.5, 5.5), "gravity": Vector3(0, -16, 0), "size": Vector2(0.045, 0.3),
		"color": Fx.hot(WALL_FX.lerp(Color.WHITE, 0.45), 2.4)}))
	_wall_motes = _fx(Fx.trail({"amount": 26, "lifetime": 0.9, "size": 0.14, "color": Fx.hot(WALL_FX, 1.6),
		"shape": "box", "extents": Vector3(0.1, 0.45, 0.25), "offset": Vector3(0, 0.55, 0),
		"dir": Vector3(0, 0.2, 1), "spread": 40.0, "speed": Vector2(0.3, 0.9), "damping": Vector2(0.5, 1.0),
		"curve": "pop", "fade": PackedFloat32Array([0.0, 1.0, 0.0]), "turbulence": 0.4}))
	_latch_sparks = _fx(Fx.sparks({"amount": 30, "lifetime": 0.45, "dir": Vector3.UP, "spread": 88.0,
		"flatness": 0.7, "speed": Vector2(3.0, 8.0), "gravity": Vector3(0, -12, 0), "color": wall_hot}))
	_latch_ring = _fx(Fx.shockwave(1.1, {"lifetime": 0.3, "color": wall_hot}))
	# wall jump: a star of sparks and a ring blown off the wall, then a short cyan trail
	_kick_sparks = _fx(Fx.sparks({"amount": 40, "lifetime": 0.5, "dir": Vector3.UP, "spread": 70.0,
		"speed": Vector2(5.0, 11.0), "damping": Vector2(3.0, 5.0), "gravity": Vector3(0, -9, 0),
		"size": Vector2(0.06, 0.5), "color": Fx.hot(WALL_FX.lerp(Color.WHITE, 0.3), 2.8)}))
	_kick_ring = _fx(Fx.shockwave(1.6, {"lifetime": 0.35, "color": wall_hot}))
	_kick_trail = _fx(Fx.trail({"amount": 48, "lifetime": 0.35, "size": 0.24, "color": wall_hot,
		"shape": "sphere", "radius": 0.22, "offset": Vector3(0, 0.6, 0)}))
	# mantle: dust knocked off the lip, gold sparks where the hands catch, a hop puff on top
	_mantle_dust = _fx(Fx.smoke({"amount": 14, "lifetime": 0.75, "size": 0.7, "shape": "box",
		"extents": Vector3(0.45, 0.05, 0.1), "dir": Vector3(0, -0.3, 1), "spread": 50.0,
		"speed": Vector2(0.6, 1.6), "gravity": Vector3(0, -1.5, 0), "color": Color(0.92, 0.88, 0.8, 0.85)}))
	_mantle_sparks = _fx(Fx.sparks({"amount": 30, "lifetime": 0.45, "shape": "box",
		"extents": Vector3(0.45, 0.02, 0.05), "dir": Vector3(0, 1, 0.4), "spread": 55.0,
		"speed": Vector2(2.5, 6.5), "color": Color(2.4, 1.4, 0.25), "size": Vector2(0.06, 0.38)}))
	_hop_puff = _fx(Fx.smoke({"amount": 10, "lifetime": 0.55, "size": 0.45, "shape": "ring",
		"ring_radius": 0.35, "ring_inner": 0.25, "dir": Vector3.UP, "spread": 80.0, "flatness": 0.9,
		"speed": Vector2(1.2, 2.2), "color": Color(1, 1, 1, 0.65)}))
	# speed: long thin wind streaks around the body, flowing past
	_speed_lines = _fx(Fx.emitter({"amount": 40, "lifetime": 0.26, "emitting": false, "shape": "shell",
		"radius": 0.95, "offset": Vector3(0, 0.6, 0), "spread": 4.0, "speed": Vector2(3.0, 6.0),
		"facing": "velocity", "tex": Fx.Tex.SPARK, "size": Vector2(0.035, 1.3),
		"fade": PackedFloat32Array([0.0, 0.55, 0.0]), "color": Color(1.5, 1.6, 1.8, 0.8)}))
	# big landings: a ground shockwave, a dust ring rolling out and a spray of grit
	_land_ring = _fx(Fx.shockwave(2.4, {"lifetime": 0.42, "color": Color(1.3, 1.25, 1.15, 0.9)}))
	_land_smoke = _fx(Fx.smoke({"amount": 18, "lifetime": 0.8, "shape": "ring", "ring_radius": 0.5,
		"ring_inner": 0.3, "dir": Vector3.UP, "spread": 88.0, "flatness": 0.92, "speed": Vector2(3.0, 6.0),
		"damping": Vector2(5.0, 8.0), "size": 0.75, "color": Color(0.95, 0.92, 0.86, 0.7)}))
	_land_debris = _fx(Fx.debris({"amount": 14, "chunk": 0.1, "dir": Vector3.UP, "spread": 55.0,
		"speed": Vector2(3.0, 7.0), "color": Color(0.62, 0.58, 0.52)}))
	# pad launches: a spring ring in the pad's colour and a column of sparkles
	_spring_ring = _fx(Fx.shockwave(1.9, {"lifetime": 0.35}))
	_spring_sparkle = _fx(Fx.burst({"amount": 22, "lifetime": 0.7, "tex": Fx.Tex.STAR, "size": 0.32,
		"shape": "ring", "ring_radius": 0.55, "dir": Vector3.UP, "spread": 12.0, "speed": Vector2(4.0, 10.0),
		"damping": Vector2(4.0, 7.0), "curve": "pop"}))
	_knock_sparks = _fx(Fx.sparks({"amount": 26, "lifetime": 0.4, "spread": 180.0,
		"speed": Vector2(4.0, 9.0), "damping": Vector2(4.0, 6.0), "color": Color(2.6, 2.2, 1.8)}))
	# arrival (respawn / teleport): a column of accent sparks, a ring and twinkles
	_arrive_column = _fx(Fx.sparks({"amount": 34, "lifetime": 0.7, "shape": "ring", "ring_radius": 0.55,
		"ring_inner": 0.2, "dir": Vector3.UP, "spread": 6.0, "speed": Vector2(4.0, 9.0),
		"gravity": Vector3(0, -3, 0), "damping": Vector2(2.0, 4.0), "size": Vector2(0.06, 0.55)}))
	_arrive_ring = _fx(Fx.shockwave(1.8, {"lifetime": 0.45}))
	_arrive_stars = _fx(Fx.burst({"amount": 18, "lifetime": 0.8, "tex": Fx.Tex.STAR, "size": 0.3,
		"shape": "sphere", "radius": 0.7, "offset": Vector3(0, 0.7, 0), "speed": Vector2(0.5, 2.0),
		"curve": "pop"}))
	# checkpoint: a helix of stars winding up around Volt (local, so it rides along)
	_cp_spin = Node3D.new()
	add_child(_cp_spin)
	_cp_helix = Fx.burst({"amount": 30, "lifetime": 0.9, "explosiveness": 0.35, "local": true,
		"tex": Fx.Tex.STAR, "size": 0.26, "shape": "ring", "ring_radius": 0.7, "ring_inner": 0.6,
		"dir": Vector3.UP, "spread": 5.0, "speed": Vector2(2.5, 3.5), "damping": Vector2.ZERO,
		"curve": "pop", "layers": 2})
	_cp_spin.add_child(_cp_helix)
	_cp_ring = _fx(Fx.shockwave(2.0, {"lifetime": 0.5}))
	_light = OmniLight3D.new()
	_light.position = Vector3(0, 0.8, 0)
	_light.omni_range = 5.0
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	_light.visible = false
	add_child(_light)
	_tint_fx()


func _fx(p: GPUParticles3D) -> GPUParticles3D:
	p.layers = 2
	# placed by hand every frame / right before firing: never interpolated from the last spot
	p.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(p)
	return p


## Accent-coloured effects follow the racer's colour.
func _tint_fx() -> void:
	if _arrive_column == null:
		return
	var hot: Color = Fx.hot(accent.lerp(Color.WHITE, 0.25), 2.4)
	for p: GPUParticles3D in [_arrive_column, _arrive_ring, _arrive_stars, _cp_helix, _cp_ring]:
		(p.process_material as ParticleProcessMaterial).color = hot


## Fires a prebuilt one-shot at `at` with its local Y along `up`.
func _pop(p: GPUParticles3D, at: Vector3, up: Vector3 = Vector3.UP, ratio: float = 1.0) -> void:
	if p == null or not p.is_inside_tree():
		return
	p.amount_ratio = clampf(ratio, 0.05, 1.0)
	Fx.fire(p, at, Fx.basis_up(up))


func _flash(color: Color, energy: float, time: float = 0.3) -> void:
	if _light == null or not _light.is_inside_tree() or Fx.density() < 0.5:
		return
	_light.light_color = color
	Fx.pulse(_light, energy, 0.0, time)


## Feet position in world space.
func _feet() -> Vector3:
	return global_position + Vector3(0, 0.05, 0)


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
	if _mantle_pending > 0.0:
		# topped out a climb: a little hop puff
		_mantle_pending = 0.0
		_pop(_hop_puff, _feet())
		return
	# big landings (a plain full jump lands at ~14 m/s): shockwave, dust wave, grit
	var big: float = clampf((impact - 16.5) / 16.0, 0.0, 1.0)
	if big > 0.0:
		_set_scale(_land_ring, lerpf(1.6, 3.6, big))
		_pop(_land_ring, _feet() + Vector3(0, 0.04, 0))
		_pop(_land_smoke, _feet(), Vector3.UP, 0.45 + big * 0.55)
		_pop(_land_debris, _feet(), Vector3.UP, 0.35 + big * 0.65)
		if big > 0.5:
			_flash(Color(1.0, 0.92, 0.8), 1.5 + big * 2.0, 0.25)


func on_bounce(strength: float) -> void:
	_pop_up()
	# spring ring + sparkles in the pad colour for this strength (the scale pads wear)
	var col: Color = Fx.hot(BouncePad.strength_color(strength).lerp(Color.WHITE, 0.2), 2.6)
	(_spring_ring.process_material as ParticleProcessMaterial).color = col
	(_spring_sparkle.process_material as ParticleProcessMaterial).color = col
	var k: float = clampf((strength - 10.0) / 20.0, 0.25, 1.0)
	_set_scale(_spring_ring, lerpf(1.2, 2.2, k))
	_pop(_spring_ring, _feet() + Vector3(0, 0.06, 0))
	_pop(_spring_sparkle, _feet(), Vector3.UP, 0.4 + k * 0.6)
	_flash(col, 2.5 * k, 0.3)


## A hazard threw us (bumper, hammer, piston): the bounce squash plus a star of hit
## sparks and a white flash (no spring ring: there is no pad under us).
func on_knock(_v: Vector3) -> void:
	_pop_up()
	_pop(_knock_sparks, global_position + Vector3(0, 0.6, 0))
	_flash(Color(1.0, 0.9, 0.85), 2.5, 0.2)


## The squash-and-stretch pop and takeoff puff shared by pad launches and knocks.
func _pop_up() -> void:
	_squash = -0.3
	_squash_vel = 10.0
	_flare = 1.6
	_step_quiet = 0.12
	_jump_dust.amount_ratio = 1.0
	_jump_dust.restart()


## Latched onto a wall-run panel (`normal` points away from it): a spark burst and a
## ring on the panel where the feet touch.
func on_wall_run(normal: Vector3) -> void:
	wall_normal = Vector3(normal.x, 0.0, normal.z).normalized()
	var at: Vector3 = _wall_contact(0.3)
	_pop(_latch_sparks, at, wall_normal)
	_pop(_latch_ring, at + wall_normal * 0.03, wall_normal)
	_flash(WALL_FX, 2.0, 0.25)


## Kicked off the wall: a radial burst and a ring blown off the panel, then a short trail.
func on_wall_jump() -> void:
	if wall_normal == Vector3.ZERO:
		return
	var at: Vector3 = _wall_contact(0.45)
	_pop(_kick_sparks, at, wall_normal)
	_pop(_kick_ring, at + wall_normal * 0.03, wall_normal)
	_kick_t = 0.35
	_kick_trail.emitting = true
	_flash(WALL_FX, 3.0, 0.3)


## Caught a ledge: stretch up toward it, then the landing squash follows on top.
func on_mantle() -> void:
	_squash_vel += 6.0
	_step_quiet = 0.12


## The ledge grab itself (world lip point, climb direction into the ledge): dust knocked
## off the lip and gold sparks where the hands catch; the landing on top adds a hop puff.
func on_mantle_grab(lip: Vector3, into: Vector3) -> void:
	var d := Vector3(into.x, 0.0, into.z).normalized()
	if d == Vector3.ZERO or _mantle_dust == null:
		return
	# basis: local Z out of the face (toward the climber), local Y up, X along the lip
	var out: Vector3 = -d
	var b := Basis(Vector3.UP.cross(out).normalized(), Vector3.UP, out)
	_mantle_dust.amount_ratio = 1.0
	Fx.fire(_mantle_dust, lip + out * 0.08, b)
	_mantle_sparks.amount_ratio = 1.0
	Fx.fire(_mantle_sparks, lip + out * 0.06 + Vector3(0, 0.02, 0), b)
	_mantle_pending = 1.0
	_flash(LIP_FX, 1.6, 0.25)


## Banked a checkpoint: bulb flare, a little hop of the body, a helix of stars and a ring.
func on_checkpoint() -> void:
	_flare = maxf(_flare, 1.2)
	_squash_vel += 4.0
	if _cp_helix != null and _cp_helix.is_inside_tree():
		_cp_helix.restart()
		_pop(_cp_ring, _feet() + Vector3(0, 0.05, 0))
		_flash(accent, 3.0, 0.45)


## Crossed the finish: a big stretch and the brightest bulb flash.
func on_cheer() -> void:
	_squash_vel += 7.0
	_flare = 1.6
	if _cp_helix != null and _cp_helix.is_inside_tree():
		_cp_helix.restart()
		_pop(_arrive_stars, global_position)


## Respawn arrival: drops the motion carried over from the death pose (lean, squash,
## antenna swing, the stale velocity that would jolt the lean for a frame) and pops
## in with a small spring, a bulb glow and a column of accent sparks.
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
	_stop_moves_fx()
	_pop(_arrive_column, _feet())
	_pop(_arrive_ring, _feet() + Vector3(0, 0.05, 0))
	_pop(_arrive_stars, global_position)
	_flash(accent.lerp(Color.WHITE, 0.3), 3.5, 0.5)


func snap_facing(dir: Vector3) -> void:
	if dir.length() > 0.01:
		_yaw = atan2(-dir.x, -dir.z)


## Where the feet meet the panel we run on, `h` above the feet.
func _wall_contact(h: float) -> Vector3:
	return global_position - wall_normal * 0.4 + Vector3(0, h, 0)


func _set_scale(ring: GPUParticles3D, radius: float) -> void:
	var pm := ring.process_material as ParticleProcessMaterial
	pm.scale_min = radius * 2.0
	pm.scale_max = radius * 2.0


func _stop_moves_fx() -> void:
	if _wall_streak == null:
		return
	_wall_streak.emitting = false
	_wall_sparks.emitting = false
	_wall_motes.emitting = false
	_kick_trail.emitting = false
	_speed_lines.emitting = false
	_kick_t = 0.0
	_speed_k = 0.0
	_mantle_pending = 0.0


## Per-frame part of the move effects: wall-run scrape, kick trail, speed lines.
func _animate_fx(dt: float, vel: Vector3, on_floor: bool) -> void:
	if _wall_streak == null or not is_inside_tree():
		return
	_mantle_pending = maxf(_mantle_pending - dt, 0.0)
	_cp_spin.rotation.y += dt * 9.0
	# wall run: the scrape emitters ride the contact point, oriented off the wall
	var running: bool = wall_roll != 0.0 and wall_normal != Vector3.ZERO
	if running:
		var along := Vector3(vel.x, 0.0, vel.z)
		var fwd: Vector3 = along.normalized() if along.length() > 0.5 else wall_normal.cross(Vector3.UP)
		var side: Vector3 = Vector3.UP.cross(wall_normal)
		var b := Basis(side, Vector3.UP, wall_normal)
		# scrape sparks fly back along the run and off the panel
		var back: float = -signf(fwd.dot(side))
		(_wall_sparks.process_material as ParticleProcessMaterial).direction = Vector3(back * 0.8, 0.45, 1.0)
		var feet: Vector3 = _wall_contact(0.22)
		_wall_streak.global_transform = Transform3D(Basis.IDENTITY, feet + wall_normal * 0.04)
		_wall_sparks.global_transform = Transform3D(b, feet + wall_normal * 0.05)
		_wall_motes.global_transform = Transform3D(b, global_position - wall_normal * 0.1)
	if _wall_streak.emitting != running:
		_wall_streak.emitting = running
		_wall_sparks.emitting = running
		_wall_motes.emitting = running
	# the kick-off trail runs for a moment after a wall jump
	if _kick_t > 0.0:
		_kick_t -= dt
		if _kick_t <= 0.0:
			_kick_trail.emitting = false
	# speed lines: well over run speed (9 m/s) - boosts, pads, slides, big launches
	var hs: float = Vector2(vel.x, vel.z).length()
	var rise: float = 0.0 if on_floor else vel.y
	var target: float = clampf(maxf((hs - 12.5) / 8.0, (rise - 16.0) / 8.0), 0.0, 1.0)
	_speed_k = move_toward(_speed_k, target, dt * (3.0 if target > _speed_k else 1.6))
	var on: bool = _speed_k > 0.03
	if on:
		_speed_lines.amount_ratio = _speed_k
		var back: Vector3 = -vel.normalized()
		(_speed_lines.process_material as ParticleProcessMaterial).direction = _speed_lines.global_basis.inverse() * back
	if _speed_lines.emitting != on:
		_speed_lines.emitting = on


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
	_animate_fx(dt, vel, on_floor)
