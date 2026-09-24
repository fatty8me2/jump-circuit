class_name PlayerVisual
extends Node3D
## "Volt" - a round little courier robot. Purely cosmetic: squash/stretch, lean,
## foot cycle and particles are animated here and never touch the collider.
## Used both by the local Player and by RemoteRacer ghosts.

## A foot planted while moving on the ground (the local Player turns it into a quiet tick).
signal footstep(speed: float)

var accent: Color = Color(1.0, 0.72, 0.2)

var _root: Node3D          # squash/stretch + lean pivot (at the feet)
var _flip: Node3D          # flips, rolls and spins (pivot at the body's centre)
var _rig: Node3D           # everything visible; scaled for the respawn pop-in (from the feet)
var _torso: Node3D         # body, visor, belt, pack, antenna: bob, twist, breathing
var _body: MeshInstance3D
var _foot_l: MeshInstance3D
var _foot_r: MeshInstance3D
var _hand_l: MeshInstance3D    # floating mitts (no arms): they reach, pump and grab
var _hand_r: MeshInstance3D
var _eye_l: MeshInstance3D
var _eye_r: MeshInstance3D
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
var _antenna_vel: Vector2 = Vector2.ZERO   # the antenna is a spring: it whips and settles
## Set by the player each frame while wall running: -1 wall on the left, +1 on the right.
var wall_roll: float = 0.0
var _step_quiet: float = 0.0   # no footstep right on top of a jump / land / bounce sound

# ---- animation state (all cosmetic) ----
const TAU_F: float = TAU
const HAND_REST := Vector3(0.49, 0.43, 0.02)   # right hand; the left mirrors x
var _t: float = 0.0             # animation clock
var _air_t: float = 0.0         # seconds airborne
var _jump_t: float = 9.0        # since takeoff (the kick-off pose)
var _land_t: float = 9.0        # since landing (the recovery crouch)
var _land_k: float = 0.0        # how hard that landing was, 0..1
var _flip_t: float = 9.0        # a flip / roll / spin in progress
var _flip_len: float = 0.5
var _flip_axis: Vector3 = Vector3.ZERO   # radians per full move about local x (pitch), y (spin), z (roll)
var _flip_delay: float = 0.0
var _flip_tuck: float = 0.0     # how tightly limbs tuck during it
var _mantle_t: float = 9.0      # mantle climb clock
var _mantle_len: float = 0.34
var _lip: Vector3 = Vector3.ZERO    # world lip point the hands grab
var _lip_in: Vector3 = Vector3.ZERO # climb direction (into the ledge)
var _cp_t: float = 9.0          # checkpoint fist pump
var _cheer_t: float = 9.0       # finish celebration
var _appear_t: float = 9.0      # respawn pop-in
var _knock_t: float = 9.0
var _idle_t: float = 0.0
var _fidget: int = -1
var _fidget_t: float = 0.0
var _fidget_n: int = 0
var _blink_t: float = 2.0       # counts down to the next blink
var _blink: float = 0.0         # 0 open .. 1 shut
var _skid: float = 0.0          # sharp-turn skid, 0..1
var _skid_cd: float = 0.0
var _sprint: float = 0.0        # boost / high-speed pose, 0..1
var _last_wall: float = 0.0     # which side the wall was on (kept after we leave it)
var _hands_prev: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]

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
var _jump_ring: GPUParticles3D     # a small ground ring on every takeoff
var _skid_dust: GPUParticles3D     # grit kicked up by hard turns and stops
var _cheer_confetti: GPUParticles3D
var _hand_trail_l: Swoosh          # ribbons off the mitts: boost pose, flips, rolls
var _hand_trail_r: Swoosh
# ---- the heavy layer: more of everything, all one-shots idle until their event ----
var _body_trail: Swoosh            # a wide ribbon off the body on launches and at boost speed
var _jump_streaks: GPUParticles3D  # takeoff: streaks shot down from the soles
var _jump_glints: GPUParticles3D
var _land_ring_small: GPUParticles3D   # every real landing gets a ring
var _land_sparks: GPUParticles3D   # big landings: a hot fan of sparks along the floor
var _land_haze: GPUParticles3D     # ... and dust that hangs a moment
var _step_puff: GPUParticles3D     # a small kick of dust per foot plant at speed
var _sprint_dust: GPUParticles3D   # boost pose on the ground: a wake of dust
var _wall_step: GPUParticles3D     # a crackle of sparks per foot plant on the panel
var _wall_light: OmniLight3D       # cyan glow riding the contact point while wall running
var _kick_smoke: GPUParticles3D    # wall jump: a puff blown off the panel
var _mantle_glints: GPUParticles3D # gold glints left on the lip
var _spring_streaks: GPUParticles3D  # pad launch: a column of upward streaks
var _knock_ring: GPUParticles3D
var _knock_stars: GPUParticles3D   # a daze of stars circling after a hit
var _arrive_suck: GPUParticles3D   # respawn: motes drawn in before the pop
var _arrive_motes: GPUParticles3D  # ... and a few that linger after it
var _cp_confetti: GPUParticles3D


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
	# rig: _root (feet pivot) > _flip (body-centre pivot) > _rig (back at the feet) > parts
	_flip = Node3D.new()
	_flip.position = Vector3(0, 0.55, 0)
	_root.add_child(_flip)
	_rig = Node3D.new()
	_rig.position = Vector3(0, -0.55, 0)
	_flip.add_child(_rig)
	_torso = Node3D.new()
	_torso.position = Vector3(0, 0.2, 0)
	_rig.add_child(_torso)
	var tz := Vector3(0, -0.2, 0)   # torso parts keep their feet-relative heights
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 28
	sphere.rings = 14
	# body: a plump shell
	_body = _part(_torso, sphere, _mat(Color(0.96, 0.94, 0.88), 0.4), Vector3(0, 0.62, 0) + tz, Vector3(0.78, 0.86, 0.78))
	# accent belt
	var belt := TorusMesh.new()
	belt.inner_radius = 0.33
	belt.outer_radius = 0.41
	belt.rings = 28
	belt.ring_segments = 10
	var belt_mi := _part(_torso, belt, _mat(accent, 0.45), Vector3(0, 0.47, 0) + tz, Vector3(1, 0.9, 1))
	belt_mi.name = "Belt"
	# visor + eyes (front is -Z)
	_part(_torso, sphere, _mat(Color(0.08, 0.1, 0.16), 0.15, 0.3), Vector3(0, 0.74, -0.2) + tz, Vector3(0.56, 0.3, 0.42))
	var eye_mat := _mat(Color(0.5, 0.97, 1.0), 0.3, 0.0, 3.0)
	_eye_l = _part(_torso, sphere, eye_mat, Vector3(-0.11, 0.75, -0.385) + tz, Vector3(0.09, 0.12, 0.06))
	_eye_r = _part(_torso, sphere, eye_mat, Vector3(0.11, 0.75, -0.385) + tz, Vector3(0.09, 0.12, 0.06))
	# backpack
	var box := BoxMesh.new()
	box.size = Vector3(0.34, 0.3, 0.16)
	var pack := _part(_torso, box, _mat(accent.darkened(0.25), 0.5), Vector3(0, 0.62, 0.33) + tz)
	pack.name = "Pack"
	# antenna
	_antenna = Node3D.new()
	_antenna.position = Vector3(0, 1.02, 0.02) + tz
	_torso.add_child(_antenna)
	var rod := CylinderMesh.new()
	rod.top_radius = 0.012
	rod.bottom_radius = 0.02
	rod.height = 0.3
	_part(_antenna, rod, _mat(Color(0.25, 0.27, 0.33), 0.4, 0.6), Vector3(0, 0.15, 0))
	_bulb_mat = _mat(accent, 0.3, 0.0, 2.0)
	_bulb = _part(_antenna, sphere, _bulb_mat, Vector3(0, 0.33, 0), Vector3.ONE * 0.12)
	# feet (dark rubber) and floating mitts (accent, like the belt)
	var foot_mat := _mat(Color(0.16, 0.18, 0.26), 0.6)
	_foot_l = _part(_rig, sphere, foot_mat, Vector3(-0.17, 0.09, 0), Vector3(0.24, 0.17, 0.34))
	_foot_r = _part(_rig, sphere, foot_mat, Vector3(0.17, 0.09, 0), Vector3(0.24, 0.17, 0.34))
	var hand_mat := _mat(accent.lerp(Color.WHITE, 0.12), 0.45)
	_hand_l = _part(_rig, sphere, hand_mat, Vector3(-HAND_REST.x, HAND_REST.y, HAND_REST.z), Vector3(0.18, 0.17, 0.2))
	_hand_r = _part(_rig, sphere, hand_mat, HAND_REST, Vector3(0.18, 0.17, 0.2))
	_hand_l.name = "HandL"
	_hand_r.name = "HandR"
	_dust = _make_burst(Color(1, 1, 1, 0.75))
	add_child(_dust)
	_jump_dust = _make_burst(Color(1, 1, 1, 0.75))
	add_child(_jump_dust)
	_trail = _make_trail()
	add_child(_trail)
	_build_fx()


func _apply_colors() -> void:
	(_torso.get_node("Belt") as MeshInstance3D).material_override = _mat(accent, 0.45)
	(_torso.get_node("Pack") as MeshInstance3D).material_override = _mat(accent.darkened(0.25), 0.5)
	var hand_mat := _mat(accent.lerp(Color.WHITE, 0.12), 0.45)
	_hand_l.material_override = hand_mat
	_hand_r.material_override = hand_mat
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
	p.amount = Fx.count(14)
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
	p.amount = Fx.count(44)
	p.lifetime = 0.45
	p.layers = 2
	p.local_coords = false
	p.fixed_fps = 0   # every frame: a streak, not a string of beads
	var pm := ParticleProcessMaterial.new()
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.2
	pm.scale_min = 0.35
	pm.scale_max = 0.6
	pm.color_ramp = _fade_ramp()
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.34, 0.34)
	q.material = _puff_material(Color(1, 1, 1, 0.42))
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
	# takeoff: a thin ring pressed into the ground
	_jump_ring = _fx(Fx.shockwave(0.9, {"lifetime": 0.28, "color": Color(1.2, 1.2, 1.2, 0.55),
		"fade": PackedFloat32Array([0.8, 0.4, 0.0])}))
	# skids: low grit sprayed ahead of the braced feet
	_skid_dust = _fx(Fx.smoke({"amount": 6, "lifetime": 0.5, "size": 0.42, "shape": "box",
		"extents": Vector3(0.22, 0.02, 0.05), "dir": Vector3(0, 0.5, -1), "spread": 35.0,
		"speed": Vector2(1.5, 3.2), "gravity": Vector3(0, -2.0, 0), "color": Color(0.95, 0.92, 0.86, 0.7)}))
	# the finish: a shower of confetti stars in every racer colour
	_cheer_confetti = _fx(Fx.burst({"amount": 40, "lifetime": 1.3, "tex": Fx.Tex.STAR, "size": 0.24,
		"shape": "sphere", "radius": 0.3, "dir": Vector3.UP, "spread": 50.0, "speed": Vector2(4.0, 8.0),
		"damping": Vector2(1.0, 2.0), "gravity": Vector3(0, -6.0, 0), "curve": "pop",
		"pick": PackedColorArray([Color(2.4, 0.9, 0.5), Color(0.6, 2.0, 2.4), Color(2.4, 2.0, 0.5),
			Color(1.0, 2.4, 0.9), Color(2.0, 0.8, 2.4)])}))
	# boost / flips: smooth ribbons traced by both mitts
	_hand_trail_l = Swoosh.make(Color.WHITE, 0.09, 0.22)
	_hand_trail_r = Swoosh.make(Color.WHITE, 0.09, 0.22)
	add_child(_hand_trail_l)
	add_child(_hand_trail_r)
	_build_fx_heavy()
	_light = OmniLight3D.new()
	_light.position = Vector3(0, 0.8, 0)
	_light.omni_range = 5.0
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	_light.visible = false
	add_child(_light)
	_tint_fx()


## The second, heavier layer on every move (see the heavy-layer vars).
func _build_fx_heavy() -> void:
	var dust := Color(0.95, 0.92, 0.86, 0.75)
	_body_trail = Swoosh.make(Color.WHITE, 0.26, 0.28)
	add_child(_body_trail)
	_jump_streaks = _fx(Fx.sparks({"amount": 12, "lifetime": 0.28, "shape": "ring", "ring_radius": 0.3,
		"ring_inner": 0.15, "dir": Vector3.DOWN, "spread": 14.0, "speed": Vector2(5.0, 9.0),
		"gravity": Vector3.ZERO, "damping": Vector2(8.0, 12.0), "size": Vector2(0.05, 0.6),
		"color": Color(1.8, 1.8, 1.9, 0.8)}))
	_jump_glints = _fx(Fx.burst({"amount": 6, "lifetime": 0.45, "tex": Fx.Tex.STAR, "size": 0.2,
		"shape": "ring", "ring_radius": 0.4, "dir": Vector3.UP, "spread": 40.0, "speed": Vector2(1.0, 2.5),
		"curve": "pop", "color": Color(2.0, 2.0, 2.0)}))
	_land_ring_small = _fx(Fx.shockwave(1.2, {"lifetime": 0.3, "color": Color(1.2, 1.2, 1.15, 0.6),
		"fade": PackedFloat32Array([0.9, 0.5, 0.0])}))
	_land_sparks = _fx(Fx.sparks({"amount": 30, "lifetime": 0.45, "shape": "ring", "ring_radius": 0.45,
		"ring_inner": 0.3, "dir": Vector3.UP, "spread": 80.0, "flatness": 0.85, "speed": Vector2(5.0, 11.0),
		"gravity": Vector3(0, -14, 0), "damping": Vector2(2.0, 4.0), "size": Vector2(0.06, 0.45),
		"color": Color(2.8, 2.0, 1.1)}))
	_land_haze = _fx(Fx.smoke({"amount": 10, "lifetime": 1.6, "explosiveness": 0.7, "shape": "ring",
		"ring_radius": 1.0, "ring_inner": 0.5, "dir": Vector3.UP, "spread": 60.0, "speed": Vector2(0.3, 0.9),
		"damping": Vector2(1.0, 2.0), "size": 1.3, "color": Color(dust.r, dust.g, dust.b, 0.45)}))
	_step_puff = _fx(Fx.smoke({"amount": 4, "lifetime": 0.45, "size": 0.32, "dir": Vector3(0, 0.6, 1),
		"spread": 40.0, "speed": Vector2(0.6, 1.4), "damping": Vector2(3.0, 5.0),
		"color": Color(dust.r, dust.g, dust.b, 0.55)}))
	_sprint_dust = _fx(Fx.smoke({"amount": 26, "lifetime": 0.6, "one_shot": false, "emitting": false,
		"explosiveness": 0.0, "shape": "box", "extents": Vector3(0.22, 0.02, 0.1), "dir": Vector3(0, 0.5, 1),
		"spread": 30.0, "speed": Vector2(1.0, 2.5), "damping": Vector2(2.0, 4.0), "size": 0.5,
		"color": Color(dust.r, dust.g, dust.b, 0.5)}))
	_wall_step = _fx(Fx.sparks({"amount": 10, "lifetime": 0.3, "dir": Vector3.UP, "spread": 70.0,
		"speed": Vector2(2.5, 6.0), "gravity": Vector3(0, -12, 0), "size": Vector2(0.05, 0.32),
		"color": Fx.hot(WALL_FX.lerp(Color.WHITE, 0.5), 2.6)}))
	if Fx.density() >= 0.5:
		_wall_light = OmniLight3D.new()
		_wall_light.light_color = WALL_FX
		_wall_light.light_energy = 0.0
		_wall_light.omni_range = 3.5
		_wall_light.shadow_enabled = false
		_wall_light.visible = false
		_wall_light.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(_wall_light)
	_kick_smoke = _fx(Fx.smoke({"amount": 10, "lifetime": 0.7, "shape": "sphere", "radius": 0.25,
		"dir": Vector3.UP, "spread": 60.0, "speed": Vector2(1.5, 3.0), "damping": Vector2(3.0, 5.0),
		"size": 0.7, "color": Color(0.85, 0.97, 1.0, 0.6)}))
	_mantle_glints = _fx(Fx.embers({"amount": 12, "lifetime": 1.2, "one_shot": true, "explosiveness": 0.7,
		"emitting": false, "extents": Vector3(0.5, 0.02, 0.05), "speed": Vector2(0.2, 0.7), "tex": Fx.Tex.STAR,
		"size": 0.22, "curve": "pop", "color": Fx.hot(LIP_FX, 2.4), "turbulence": 0.3}))
	_spring_streaks = _fx(Fx.sparks({"amount": 18, "lifetime": 0.5, "shape": "ring", "ring_radius": 0.5,
		"ring_inner": 0.35, "dir": Vector3.UP, "spread": 4.0, "speed": Vector2(12.0, 20.0),
		"gravity": Vector3.ZERO, "damping": Vector2(10.0, 16.0), "size": Vector2(0.07, 1.1)}))
	_knock_ring = _fx(Fx.shockwave(1.5, {"lifetime": 0.3, "color": Color(2.4, 2.1, 1.8)}))
	_knock_stars = Fx.burst({"amount": 6, "lifetime": 1.0, "explosiveness": 0.9, "local": true,
		"tex": Fx.Tex.STAR, "size": 0.26, "shape": "ring", "ring_radius": 0.45, "ring_inner": 0.4,
		"speed": Vector2.ZERO, "spread": 0.0, "damping": Vector2.ZERO, "curve": "pop",
		"color": Color(2.8, 2.4, 0.9), "layers": 2})
	_knock_stars.position = Vector3(0, 1.3, 0)
	_cp_spin.add_child(_knock_stars)
	_arrive_suck = _fx(Fx.emitter({"amount": 30, "lifetime": 0.35, "one_shot": true, "explosiveness": 0.9,
		"shape": "shell", "radius": 1.6, "offset": Vector3(0, 0.6, 0), "speed": Vector2.ZERO, "spread": 0.0,
		"radial": Vector2(-38.0, -30.0), "tex": Fx.Tex.DOT, "size": 0.16, "curve": "grow",
		"fade": PackedFloat32Array([0.0, 1.0, 1.0])}))
	_arrive_motes = _fx(Fx.embers({"amount": 14, "lifetime": 1.4, "one_shot": true, "explosiveness": 0.6,
		"emitting": false, "shape": "ring", "ring_radius": 0.6, "ring_inner": 0.2, "speed": Vector2(0.4, 1.2),
		"tex": Fx.Tex.STAR, "size": 0.2, "curve": "pop", "turbulence": 0.5}))
	_cp_confetti = _fx(Fx.burst({"amount": 26, "lifetime": 1.1, "tex": Fx.Tex.PETAL, "additive": false,
		"size": 0.2, "shape": "sphere", "radius": 0.3, "dir": Vector3.UP, "spread": 55.0,
		"speed": Vector2(3.5, 6.5), "damping": Vector2(1.5, 2.5), "gravity": Vector3(0, -7.0, 0),
		"angle": Vector2(0, 360), "spin": Vector2(-500, 500), "curve": "flat", "fade": PackedFloat32Array([1.0, 1.0, 0.0]),
		"pick": PackedColorArray([Color(1.0, 0.3, 0.45), Color(0.25, 0.8, 1.0), Color(1.0, 0.85, 0.2),
			Color(0.45, 1.0, 0.4), Color(0.85, 0.45, 1.0)])}))


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
	var streak: Color = Fx.hot(accent.lerp(Color.WHITE, 0.4), 1.5)
	_hand_trail_l.color = streak
	_hand_trail_r.color = streak
	if _body_trail != null:
		var bc: Color = Fx.hot(accent.lerp(Color.WHITE, 0.3), 1.2)
		bc.a = 0.6
		_body_trail.color = bc
		for p: GPUParticles3D in [_arrive_suck, _arrive_motes]:
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
	# anticipation read in one frame: a quick crouch that springs into the stretch
	_squash = minf(_squash, -0.16)
	_squash_vel = maxf(_squash_vel, 0.0) + 8.5
	_flare = 1.0
	_step_quiet = 0.12
	_jump_t = 0.0
	_land_t = 9.0
	_antenna_vel.x -= 5.0
	_jump_dust.amount_ratio = 0.5
	_jump_dust.restart()
	_pop(_jump_ring, _feet() + Vector3(0, 0.04, 0))
	_pop(_jump_streaks, _feet() + Vector3(0, 0.1, 0))
	_pop(_jump_glints, _feet())


func on_land(impact: float) -> void:
	var k: float = clampf(impact / 22.0, 0.15, 1.0)
	_squash_vel -= 9.0 * k
	_step_quiet = 0.12
	_land_t = 0.0
	_land_k = clampf((impact - 3.0) / 25.0, 0.0, 1.0)
	_antenna_vel.x += 6.0 + 10.0 * _land_k
	_blink = maxf(_blink, 0.6 * _land_k)
	_dust.amount_ratio = clampf(k + 0.2, 0.3, 1.0)
	_dust.restart()
	if impact > 8.0 and _land_ring_small != null:
		_set_scale(_land_ring_small, lerpf(0.7, 1.4, clampf((impact - 8.0) / 10.0, 0.0, 1.0)))
		_pop(_land_ring_small, _feet() + Vector3(0, 0.03, 0))
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
		_pop(_land_sparks, _feet() + Vector3(0, 0.05, 0), Vector3.UP, 0.3 + big * 0.7)
		_pop(_land_haze, _feet(), Vector3.UP, 0.4 + big * 0.6)
		_flash(Color(1.0, 0.92, 0.8), 1.2 + big * 3.0, 0.3)


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
	(_spring_streaks.process_material as ParticleProcessMaterial).color = col
	_pop(_spring_streaks, _feet(), Vector3.UP, 0.4 + k * 0.6)
	_flash(col, 1.5 + 3.0 * k, 0.35)
	# strong pads: a tucked front flip (or a twirl on a straight-up launch)
	if strength >= 18.0:
		var hs: float = Vector2(_prev_hvel.x, _prev_hvel.z).length()
		if hs > 4.0:
			_start_flip(Vector3(-TAU_F, 0, 0), 0.62, 0.06, 1.0)
		else:
			_start_flip(Vector3(0, TAU_F, 0), 0.55, 0.05, 0.5)


## A hazard threw us (bumper, hammer, piston): the bounce squash plus a star of hit
## sparks and a white flash (no spring ring: there is no pad under us).
func on_knock(v: Vector3) -> void:
	_pop_up()
	_knock_t = 0.0
	# tumble away from the hit: a backward roll about the axis across the throw
	var flat := Vector3(v.x, 0.0, v.z)
	if flat.length() > 1.0:
		var local: Vector3 = Basis(Vector3.UP, -_yaw) * flat.normalized()
		_start_flip(Vector3(-local.z, 0, local.x) * TAU_F, 0.6, 0.0, 0.6)
	_pop(_knock_sparks, global_position + Vector3(0, 0.6, 0))
	var flat_v := Vector3(v.x, 0.0, v.z)
	_pop(_knock_ring, global_position + Vector3(0, 0.6, 0), flat_v if flat_v.length() > 0.5 else Vector3.UP)
	if _knock_stars != null and _knock_stars.is_inside_tree():
		_knock_stars.restart()
	_flash(Color(1.0, 0.9, 0.85), 3.5, 0.25)


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
	_pop(_kick_smoke, at + wall_normal * 0.2, wall_normal, 0.5)
	_flash(WALL_FX, 3.0, 0.3)


## Kicked off the wall: a radial burst and a ring blown off the panel, then a short trail.
func on_wall_jump() -> void:
	if wall_normal == Vector3.ZERO:
		return
	var at: Vector3 = _wall_contact(0.45)
	_pop(_kick_sparks, at, wall_normal)
	_pop(_kick_ring, at + wall_normal * 0.03, wall_normal)
	_kick_t = 0.35
	_kick_trail.emitting = true
	_pop(_kick_smoke, at + wall_normal * 0.2, wall_normal)
	_flash(WALL_FX, 4.5, 0.35)
	# push-off: a barrel roll away from the wall (head leads away from it)
	var side: float = _last_wall if _last_wall != 0.0 else 1.0
	_start_flip(Vector3(0, 0, side * TAU_F), 0.5, 0.04, 0.8)


## Caught a ledge: stretch up toward it, then the landing squash follows on top.
func on_mantle() -> void:
	_squash_vel += 6.0
	_step_quiet = 0.12
	_mantle_t = 0.0
	_flip_t = 9.0
	var p: Node = get_parent()
	if p is Player and (p as Player).tuning != null:
		_mantle_len = maxf((p as Player).tuning.mantle_time, 0.1)


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
	_mantle_glints.amount_ratio = 1.0
	Fx.fire(_mantle_glints, lip + out * 0.05 + Vector3(0, 0.03, 0), b)
	_flash(LIP_FX, 2.4, 0.3)
	_lip = lip
	_lip_in = d
	_mantle_t = 0.0


## Banked a checkpoint: bulb flare, a little hop of the body, a helix of stars and a ring.
func on_checkpoint() -> void:
	_flare = maxf(_flare, 1.2)
	_squash_vel += 4.0
	_cp_t = 0.0
	_antenna_vel.x -= 6.0
	if _cp_helix != null and _cp_helix.is_inside_tree():
		_cp_helix.restart()
		_pop(_cp_ring, _feet() + Vector3(0, 0.05, 0))
		_pop(_cp_confetti, global_position + Vector3(0, 1.1, 0))
		_flash(accent, 4.0, 0.5)


## Crossed the finish: a big stretch and the brightest bulb flash.
func on_cheer() -> void:
	_squash_vel += 7.0
	_flare = 1.6
	_cheer_t = 0.0
	_start_flip(Vector3(0, 2.0 * TAU_F, 0), 0.8, 0.1, 0.0)
	if _cp_helix != null and _cp_helix.is_inside_tree():
		_cp_helix.restart()
		_pop(_arrive_stars, global_position)
		_pop(_cheer_confetti, global_position + Vector3(0, 1.2, 0))
		_flash(accent.lerp(Color.WHITE, 0.3), 4.0, 0.6)


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
	_antenna_vel = Vector2.ZERO
	_hand_l.position = Vector3(-HAND_REST.x, HAND_REST.y, HAND_REST.z)
	_hand_r.position = HAND_REST
	_appear_t = 0.0
	_flip_t = 9.0
	_mantle_t = 9.0
	_cheer_t = 9.0
	_knock_t = 9.0
	_land_t = 9.0
	_air_t = 0.0
	_idle_t = 0.0
	_fidget = -1
	_sprint = 0.0
	_skid = 0.0
	_last_wall = 0.0
	_trail.emitting = false
	_stop_moves_fx()
	_pop(_arrive_column, _feet())
	_pop(_arrive_ring, _feet() + Vector3(0, 0.05, 0))
	_pop(_arrive_stars, global_position)
	_pop(_arrive_suck, _feet())
	_pop(_arrive_motes, _feet() + Vector3(0, 0.2, 0))
	_flash(accent.lerp(Color.WHITE, 0.3), 4.5, 0.6)


func snap_facing(dir: Vector3) -> void:
	if dir.length() > 0.01:
		_yaw = atan2(-dir.x, -dir.z)


## A foot plant: a small dust kick at speed, a crackle of sparks on a wall-run panel.
func _step_fx(speed: float, walling: bool) -> void:
	if _step_puff == null or not is_inside_tree():
		return
	if walling and wall_normal != Vector3.ZERO:
		_pop(_wall_step, _wall_contact(0.15) + wall_normal * 0.05, wall_normal)
	elif speed > 6.0:
		var back := -global_basis.z
		back = Vector3(-back.x, 0.0, -back.z).normalized()
		_step_puff.amount_ratio = clampf((speed - 6.0) / 6.0, 0.3, 1.0)
		Fx.fire(_step_puff, _feet() + back * 0.1, Basis(back.cross(Vector3.UP).normalized(), Vector3.UP, back))


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
	_hand_trail_l.clear()
	_hand_trail_r.clear()
	if _body_trail != null:
		_body_trail.clear()
		_sprint_dust.emitting = false
		if _wall_light != null:
			_wall_light.visible = false
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
	# boost pose, flips and rolls: the mitts trace ribbons of light
	var hands_on: bool = _sprint > 0.35 or (_flip_t < _flip_len and _flip_delay <= 0.0) or _speed_k > 0.3
	_hand_trail_l.feed(_hand_l.global_position, hands_on, dt)
	_hand_trail_r.feed(_hand_r.global_position, hands_on, dt)
	# the body ribbon: pad launches and real speed (never plain hops or runs)
	var hs2: float = Vector2(vel.x, vel.z).length()
	var body_on: bool = (not on_floor and vel.y > 13.0) or hs2 > 13.0 or (_flip_t < _flip_len and _flip_delay <= 0.0 and not on_floor)
	_body_trail.feed(global_position + Vector3(0, 0.55, 0), body_on, dt)
	# boost pose on the ground: a wake of dust off the heels
	var wake: bool = on_floor and _sprint > 0.4 and wall_roll == 0.0
	if wake:
		var back := Vector3(-vel.x, 0.0, -vel.z).normalized()
		_sprint_dust.global_transform = Transform3D(Basis(back.cross(Vector3.UP).normalized(), Vector3.UP, back), _feet() + back * 0.2)
		_sprint_dust.amount_ratio = _sprint
	if _sprint_dust.emitting != wake:
		_sprint_dust.emitting = wake
	# a cyan glow rides the contact point on the panel
	if _wall_light != null:
		if running:
			_wall_light.global_position = _wall_contact(0.4) + wall_normal * 0.35
			_wall_light.light_energy = 1.6 + 0.4 * sin(_t * 30.0)
		if _wall_light.visible != running:
			_wall_light.visible = running


# ---- per-frame ----------------------------------------------------------

## Starts a flip / roll / spin: `turn` is a rotation vector (axis * total angle) in the
## body's frame, played over `length` s after `delay` s; `tuck` pulls the limbs in.
func _start_flip(turn: Vector3, length: float, delay: float, tuck: float) -> void:
	if turn == Vector3.ZERO or _flip == null:
		return
	_flip_axis = turn
	_flip_len = length
	_flip_delay = delay
	_flip_tuck = tuck
	_flip_t = 0.0


## A cheap deterministic 0..1 hash (idle variety without touching the global RNG).
static func _hash(n: int) -> float:
	return fposmod(sin(float(n) * 12.9898 + 78.233) * 43758.5453, 1.0)


## 0 -> 1 -> 0 over [0, length]: a quick attack, then a soft release over the last 40%.
static func _env(t: float, length: float, attack: float = 0.1) -> float:
	if t < 0.0 or t >= length:
		return 0.0
	var a: float = clampf(t / attack, 0.0, 1.0)
	var r: float = clampf((length - t) / (length * 0.4), 0.0, 1.0)
	return smoothstep(0.0, 1.0, a) * smoothstep(0.0, 1.0, r)


static func _mirror(v: Vector3) -> Vector3:
	return Vector3(-v.x, v.y, v.z)


## vel: world velocity, on_floor: grounded, facing: desired horizontal facing.
func animate(dt: float, vel: Vector3, on_floor: bool, facing: Vector3) -> void:
	if _root == null or dt <= 0.0:
		return
	_t += dt
	_step_quiet = maxf(_step_quiet - dt, 0.0)
	_jump_t += dt
	_land_t += dt
	_cp_t += dt
	_cheer_t += dt
	_appear_t += dt
	_knock_t += dt
	_mantle_t += dt
	if _flip_delay > 0.0:
		_flip_delay -= dt
	elif _flip_t < _flip_len:
		# a flip still turning when we touch down finishes fast (never a mid-air pose on the ground)
		var cut: bool = on_floor and _flip_t > 0.1 and absf(_flip_axis.normalized().y) < 0.5
		_flip_t += dt * (3.5 if cut else 1.0)
	_air_t = 0.0 if on_floor else _air_t + dt
	if wall_roll != 0.0:
		_last_wall = wall_roll
	# facing
	if facing.length() > 0.01:
		var target_yaw: float = atan2(-facing.x, -facing.z)
		_yaw = lerp_angle(_yaw, target_yaw, 1.0 - exp(-14.0 * dt))
	# respawn pop-in: grows from the feet with an overshoot while spinning into place
	var ap: float = clampf(_appear_t / 0.42, 0.0, 1.0)
	var pop: float = 1.0
	if ap < 1.0:
		var c1: float = 2.2
		pop = maxf(1.0 + (c1 + 1.0) * pow(ap - 1.0, 3.0) + c1 * pow(ap - 1.0, 2.0), 0.05)
	rotation.y = _yaw + pow(1.0 - ap, 2.0) * TAU_F * 0.75
	_rig.scale = Vector3.ONE * pop

	# ---- motion measures ----
	var hvel := Vector3(vel.x, 0, vel.z)
	var acc: Vector3 = (hvel - _prev_hvel) / dt
	_prev_hvel = hvel
	var inv: Basis = Basis(Vector3.UP, -_yaw)
	var local_acc: Vector3 = inv * acc
	var local_vel: Vector3 = inv * hvel
	var speed: float = hvel.length()
	var amp: float = clampf(speed / 9.0, 0.0, 1.0)
	var walling: bool = wall_roll != 0.0
	var mk: float = _mantle_t / _mantle_len     # mantle progress (active below ~1.2)
	var mantling: bool = mk < 1.2
	# the boost pose: well over run speed (boost strips, pads, slides)
	_sprint = move_toward(_sprint, clampf((speed - 11.0) / 3.0, 0.0, 1.0), dt * 4.0)
	# a skid: braking hard against our own motion on the ground (turnarounds, stops)
	var skid_target: float = 0.0
	if on_floor and not walling and speed > 3.5:
		var brake: float = -acc.dot(hvel / speed)
		skid_target = clampf((brake - 55.0) / 40.0, 0.0, 1.0)
	_skid = move_toward(_skid, skid_target, dt * (10.0 if skid_target > _skid else 4.0))
	_skid_cd = maxf(_skid_cd - dt, 0.0)
	if _skid > 0.45 and _skid_cd <= 0.0 and _skid_dust != null:
		_skid_cd = 0.09
		var fwd: Vector3 = hvel / maxf(speed, 0.01)
		_skid_dust.amount_ratio = clampf(_skid, 0.4, 1.0)
		Fx.fire(_skid_dust, global_position + fwd * 0.25 + Vector3(0, 0.05, 0), Basis(fwd.cross(Vector3.UP).normalized(), Vector3.UP, -fwd))
	# idle clock and fidgets
	var idle: bool = on_floor and speed < 0.4 and not mantling and _cheer_t > 3.6 and ap >= 1.0
	if idle:
		_idle_t += dt
		if _fidget < 0:
			_fidget_t -= dt
			if _fidget_t <= 0.0 and _idle_t > 2.0:
				_fidget = [0, 1, 3, 2][_fidget_n % 4] if _hash(_fidget_n) < 0.7 else int(_hash(_fidget_n + 99) * 4.0)
				_fidget_n += 1
				_fidget_t = 0.0
		else:
			_fidget_t += dt
			if _fidget_t > 1.7:
				_fidget = -1
				_fidget_t = 1.6 + _hash(_fidget_n + 7) * 2.0
	else:
		_idle_t = 0.0
		_fidget = -1
		_fidget_t = 1.2
	var fid_w: float = _env(_fidget_t, 1.7, 0.25) if _fidget >= 0 else 0.0
	var idle_w: float = clampf(_idle_t * 2.0, 0.0, 1.0)

	# ---- envelopes for the one-off moves ----
	var land_w: float = _env(_land_t, 0.16 + 0.22 * _land_k, 0.03)
	var cp_w: float = _env(_cp_t, 0.95, 0.08)
	var cheer_w: float = _env(_cheer_t, 3.6, 0.15)
	var knock_w: float = _env(_knock_t, 0.65, 0.05)
	var fp: float = clampf(_flip_t / _flip_len, 0.0, 1.0) if _flip_delay <= 0.0 else 0.0
	var flipping: bool = _flip_t < _flip_len
	var tuck_w: float = _flip_tuck * sin(PI * fp) if flipping else 0.0
	var mantle_w: float = 0.0
	if mantling:
		mantle_w = smoothstep(0.0, 0.12, mk) * (1.0 - smoothstep(0.95, 1.2, mk))
	# the finish: little hops in place (visual only) after the twirl
	var hop: float = 0.0
	if _cheer_t > 0.85 and _cheer_t < 3.5:
		var ph: float = fposmod((_cheer_t - 0.85) / 0.52, 1.0)
		hop = 4.0 * ph * (1.0 - ph) * 0.26
	_root.position.y = hop

	# ---- squash & stretch: a damped spring that velocity and events push around ----
	var target: float = 0.0
	if not on_floor:
		target = clampf(absf(vel.y) * 0.014, 0.0, 0.2)
	if mantling:
		target = 0.14 * (1.0 - smoothstep(0.35, 0.8, mk)) - 0.08 * smoothstep(0.7, 1.0, mk) * (1.0 - smoothstep(1.0, 1.2, mk))
	target += (0.1 if _fidget == 3 else 0.0) * fid_w
	target += hop * 0.35
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

	# ---- lean into acceleration and speed (local space) ----
	var lean_target := Vector2(
		clampf(-local_acc.z * 0.004 - local_vel.z * 0.012, -0.3, 0.35),
		clampf(-local_acc.x * 0.004, -0.25, 0.25))
	if not on_floor:
		lean_target.x += clampf(-vel.y * 0.012, -0.25, 0.3)
	lean_target.x += 0.14 * _sprint - 0.5 * _skid
	# lean the body away from a wall we run on (feet on the wall, head out)
	lean_target.y += wall_roll * 0.5
	if mantling:
		lean_target = Vector2(0.18 * mantle_w, 0.0)
	_lean = _lean.lerp(lean_target, 1.0 - exp(-9.0 * dt))
	_root.rotation = Vector3(-_lean.x, 0, _lean.y)
	# flips about the body centre; the mantle rolls forward over the lip
	var fb := Basis.IDENTITY
	if flipping and _flip_axis != Vector3.ZERO:
		var e: float = fp * fp * (3.0 - 2.0 * fp)
		e = lerpf(e, 1.0 - pow(1.0 - fp, 2.2), 0.5)   # a snappy start, a soft finish
		fb = Basis(_flip_axis.normalized(), _flip_axis.length() * e)
	if mantling:
		var roll: float = sin(PI * clampf((mk - 0.4) / 0.6, 0.0, 1.0))
		fb = Basis(Vector3.RIGHT, -0.75 * roll) * fb
	_flip.basis = fb

	# ---- feet ----
	var fl := Vector3(-0.17, 0.09, 0.0)
	var fr := Vector3(0.17, 0.09, 0.0)
	var feet_rate: float = 30.0
	if on_floor:
		var prev: float = _stride
		_stride += dt * (4.0 + speed * 1.55)
		# a foot plants each time the stride phase crosses a multiple of PI
		if speed > 1.5 and _step_quiet <= 0.0 and floori(prev / PI) != floori(_stride / PI):
			footstep.emit(speed)
			_step_fx(speed, walling)
		var s: float = sin(_stride)
		var c: float = cos(_stride)
		var reach: float = (0.24 + 0.08 * _sprint) * amp
		var lift: float = (0.16 + 0.07 * _sprint) * amp
		fl = Vector3(-0.17, 0.09 + maxf(s, 0.0) * lift, -c * reach)
		fr = Vector3(0.17, 0.09 + maxf(-s, 0.0) * lift, c * reach)
		if walling:
			# running on the panel: the soles reach out onto it (the body leans away)
			fl.x += wall_roll * 0.26
			fr.x += wall_roll * 0.26
			fl.y += 0.04
			fr.y += 0.04
		# landing crouch: feet spread; skid: feet braced ahead
		fl += Vector3(-0.06, 0.0, -0.02) * land_w
		fr += Vector3(0.06, 0.0, 0.03) * land_w
		fl += Vector3(-0.03, 0.0, -0.16) * _skid
		fr += Vector3(0.02, 0.02, -0.05) * _skid
		# idle fidget: a foot tap
		if _fidget == 2:
			fr += Vector3(0.03, maxf(sin(_fidget_t * 15.0), 0.0) * 0.12, -0.14) * fid_w
		if _cheer_t < 3.5:
			var tuck_hop: float = clampf(hop / 0.2, 0.0, 1.0)
			fl += Vector3(0.02, 0.1, 0.05) * tuck_hop
			fr += Vector3(-0.02, 0.1, 0.05) * tuck_hop
	else:
		feet_rate = 12.0
		var up_k: float = clampf(vel.y / 8.0, 0.0, 1.0)
		var fall_k: float = clampf(-vel.y / 12.0, 0.0, 1.0)
		# apex tuck, the leap (one knee up, one trailing) and the dangle while falling
		fl = Vector3(-0.18, 0.2, 0.02)
		fr = Vector3(0.18, 0.23, -0.05)
		fl = fl.lerp(Vector3(-0.15, 0.03, 0.17), up_k)
		fr = fr.lerp(Vector3(0.17, 0.2, -0.14), up_k)
		fl = fl.lerp(Vector3(-0.21, 0.03, -0.07), fall_k)
		fr = fr.lerp(Vector3(0.21, 0.06, 0.02), fall_k)
		# a long, fast fall: pedalling
		var flail: float = clampf((-vel.y - 16.0) / 8.0, 0.0, 1.0)
		if flail > 0.0:
			fl += Vector3(0.0, maxf(sin(_t * 17.0), 0.0) * 0.1, cos(_t * 17.0) * 0.12) * flail
			fr += Vector3(0.0, maxf(-sin(_t * 17.0), 0.0) * 0.1, -cos(_t * 17.0) * 0.12) * flail
	# tucked for flips
	if tuck_w > 0.0:
		fl = fl.lerp(Vector3(-0.14, 0.32, -0.1), tuck_w)
		fr = fr.lerp(Vector3(0.14, 0.32, -0.1), tuck_w)
	# mantle: scramble up the face, then tuck over the lip
	if mantle_w > 0.0:
		var scr: float = 1.0 - smoothstep(0.45, 0.7, mk)
		var sl := Vector3(-0.16, 0.12 + maxf(sin(_t * 40.0), 0.0) * 0.15, -0.16)
		var sr := Vector3(0.16, 0.12 + maxf(-sin(_t * 40.0), 0.0) * 0.15, -0.16)
		var tl := Vector3(-0.15, 0.3, -0.05)
		var tr := Vector3(0.15, 0.3, -0.05)
		fl = fl.lerp(tl.lerp(sl, scr), mantle_w)
		fr = fr.lerp(tr.lerp(sr, scr), mantle_w)
	_foot_l.position = _foot_l.position.lerp(fl, 1.0 - exp(-feet_rate * dt))
	_foot_r.position = _foot_r.position.lerp(fr, 1.0 - exp(-feet_rate * dt))
	# toes follow the stride (tip up when reaching forward)
	_foot_l.rotation.x = clampf((_foot_l.position.z) * -1.2, -0.4, 0.4) if on_floor else 0.25
	_foot_r.rotation.x = clampf((_foot_r.position.z) * -1.2, -0.4, 0.4) if on_floor else -0.1

	# ---- hands (right-hand values; the left mirrors) ----
	var hr: Vector3
	var hl: Vector3
	if on_floor:
		var c2: float = cos(_stride)
		var swing: float = 0.2 * amp * (1.0 - _sprint)
		var breath: float = sin(_t * 2.3) * 0.014 * idle_w
		hr = Vector3(HAND_REST.x + 0.02 * amp, HAND_REST.y + breath + maxf(c2, 0.0) * 0.08 * amp, HAND_REST.z - c2 * swing)
		hl = Vector3(-HAND_REST.x - 0.02 * amp, HAND_REST.y + breath + maxf(-c2, 0.0) * 0.08 * amp, HAND_REST.z + c2 * swing)
		# boost pose: mitts swept back, streaming
		if _sprint > 0.0:
			var wob: float = sin(_t * 30.0) * 0.02
			hr = hr.lerp(Vector3(0.36, 0.5 + wob, 0.38), _sprint)
			hl = hl.lerp(Vector3(-0.36, 0.5 - wob, 0.38), _sprint)
		if walling:
			# the wall-side mitt skims the panel behind, the other one is flung up and out
			# for balance (both set in the leaned frame: the body rolls ~0.5 rad off the wall)
			var wall_h := Vector3(0.66, 0.36 + sin(_t * 9.0) * 0.03, 0.26)
			var free_h := Vector3(-0.3, 1.08, -0.18 + sin(_t * 7.0) * 0.04)
			if wall_roll > 0.0:
				hr = wall_h
				hl = free_h
			else:
				hl = _mirror(wall_h)
				hr = _mirror(free_h)
		# skid: arms thrown forward for balance
		hr = hr.lerp(Vector3(0.5, 0.62, -0.28), _skid)
		hl = hl.lerp(Vector3(-0.5, 0.66, -0.24), _skid)
	else:
		var up_k2: float = clampf(vel.y / 8.0, 0.0, 1.0)
		var fall_k2: float = clampf(-vel.y / 12.0, 0.0, 1.0)
		hr = Vector3(0.6, 0.7, 0.02)                      # apex: spread wide
		hr = hr.lerp(Vector3(0.56, 0.84, -0.14), up_k2)   # rising: reaching up and out
		hr = hr.lerp(Vector3(0.62, 0.92, 0.1), fall_k2)   # falling: up high, wide
		hl = _mirror(hr)
		# the kick-off: a quick upward thrust right after takeoff
		var kick: float = _env(_jump_t, 0.22, 0.04)
		hr = hr.lerp(Vector3(0.5, 0.96, -0.2), kick)
		hl = hl.lerp(Vector3(-0.5, 0.96, -0.2), kick)
		var flail2: float = clampf((-vel.y - 16.0) / 8.0, 0.0, 1.0)
		if flail2 > 0.0:
			hr += Vector3(sin(_t * 19.0) * 0.06, cos(_t * 23.0) * 0.08, 0.0) * flail2
			hl += Vector3(sin(_t * 21.0 + 1.3) * 0.06, cos(_t * 17.0 + 0.7) * 0.08, 0.0) * flail2
		if _sprint > 0.0:
			hr = hr.lerp(Vector3(0.38, 0.62, 0.4), _sprint * 0.8)
			hl = hl.lerp(Vector3(-0.38, 0.62, 0.4), _sprint * 0.8)
	# landing: mitts slap down and out
	var lw: float = land_w * (0.35 + 0.65 * _land_k)
	hr = hr.lerp(Vector3(0.56, 0.24, -0.12), lw)
	hl = hl.lerp(Vector3(-0.56, 0.24, -0.12), lw)
	if knock_w > 0.0:
		hr = hr.lerp(Vector3(0.66, 0.9 + sin(_t * 25.0) * 0.08, 0.16), knock_w)
		hl = hl.lerp(Vector3(-0.66, 0.9 + cos(_t * 23.0) * 0.08, 0.16), knock_w)
	if tuck_w > 0.0:
		hr = hr.lerp(Vector3(0.27, 0.58, -0.28), tuck_w)
		hl = hl.lerp(Vector3(-0.27, 0.58, -0.28), tuck_w)
	# idle fidgets: 0 look around, 1 flick the antenna, 2 foot tap, 3 big stretch
	if fid_w > 0.0:
		match _fidget:
			1:
				var flick: float = clampf((_fidget_t - 0.35) / 0.3, 0.0, 1.0)
				hr = hr.lerp(Vector3(0.14 - 0.1 * flick, 1.36, -0.02), fid_w)
				if _fidget_t > 0.62 and _fidget_t - dt <= 0.62:
					_antenna_vel += Vector2(3.0, -14.0)
					_flare = maxf(_flare, 0.8)
			2:
				hr = hr.lerp(Vector3(0.36, 0.5, 0.14), fid_w * 0.6)   # hands on hips-ish
				hl = hl.lerp(Vector3(-0.36, 0.5, 0.14), fid_w * 0.6)
			3:
				hr = hr.lerp(Vector3(0.5, 1.12, 0.06), fid_w)
				hl = hl.lerp(Vector3(-0.5, 1.12, 0.06), fid_w)
	# checkpoint: a fist pump (two punches at the sky)
	if cp_w > 0.0:
		var pump: float = absf(sin(_cp_t * 8.5))
		hr = hr.lerp(Vector3(0.56, 0.9 + 0.2 * pump, -0.12), cp_w)
		hl = hl.lerp(Vector3(-0.5, 0.56, -0.08), cp_w * 0.6)
	# the finish: both mitts up, waving
	if cheer_w > 0.0:
		hr = hr.lerp(Vector3(0.66 + sin(_t * 11.0) * 0.08, 1.06 + cos(_t * 11.0) * 0.1, -0.06), cheer_w)
		hl = hl.lerp(Vector3(-0.66 + sin(_t * 11.0 + 1.6) * 0.08, 1.06 + cos(_t * 11.0 + 1.6) * 0.1, -0.06), cheer_w)
	_hand_r.position = _hand_r.position.lerp(hr, 1.0 - exp(-18.0 * dt))
	_hand_l.position = _hand_l.position.lerp(hl, 1.0 - exp(-18.0 * dt))
	# mantle: the mitts lock onto the lip in world space while the body hauls up past them
	if mantle_w > 0.0 and _lip_in != Vector3.ZERO and is_inside_tree():
		var right: Vector3 = _lip_in.cross(Vector3.UP).normalized()
		var reach_k: float = smoothstep(0.0, 0.2, mk)
		for pair: Array in [[_hand_r, 1.0], [_hand_l, -1.0]]:
			var hand: MeshInstance3D = pair[0]
			var grip: Vector3 = _lip + right * (0.3 * float(pair[1])) + Vector3(0, 0.07, 0) + _lip_in * 0.05
			var from: Vector3 = hand.global_position
			hand.global_position = from.lerp(grip, mantle_w * reach_k)

	# ---- torso: bob, twist, breathing, the landing dip ----
	var bob: float = absf(cos(_stride)) * 0.035 * amp if on_floor else 0.0
	var dip: float = land_w * (0.03 + 0.1 * _land_k)
	_torso.position.y = 0.2 + bob - dip
	var twist: float = cos(_stride) * 0.13 * amp * (1.0 - 0.6 * _sprint) if on_floor and not walling else 0.0
	if _fidget == 0:
		# look around: left, then right
		twist += sin(_fidget_t * TAU_F / 1.7) * 0.55 * fid_w
	_torso.rotation.y = lerp_angle(_torso.rotation.y, twist, 1.0 - exp(-16.0 * dt))
	var b: float = sin(_t * 2.3) * 0.013 * idle_w
	_torso.scale = Vector3(1.0 - b * 0.5, 1.0 + b, 1.0 - b * 0.5)

	# ---- eyes: blinks, squints on impact and speed, happy arcs when celebrating ----
	_blink_t -= dt
	if _blink_t <= 0.0:
		_blink = 1.0
		_blink_t = 2.0 + _hash(int(_t * 10.0)) * 3.0
		if _hash(int(_t * 7.0) + 3) < 0.2:
			_blink_t = 0.22   # now and then a double blink
	_blink = maxf(_blink - dt / 0.14, 0.0)
	var shut: float = sin(PI * _blink) if _blink > 0.0 else 0.0
	var eye_y: float = 1.0 - 0.88 * shut
	eye_y *= 1.0 - 0.35 * _sprint - 0.4 * lw
	eye_y *= 1.0 + 0.3 * clampf((-vel.y - 14.0) / 10.0, 0.0, 1.0)
	var happy: float = maxf(cp_w, cheer_w)
	if _fidget == 3:
		happy = maxf(happy, fid_w)
	eye_y = lerpf(eye_y, 0.4, happy)
	var eye_s := Vector3(0.09, 0.12 * clampf(eye_y, 0.08, 1.4), 0.06)
	_eye_l.scale = eye_s
	_eye_r.scale = eye_s

	# ---- antenna: a spring that lags motion and whips on impacts ----
	var sway_target := Vector2(
		clampf(-local_vel.z * 0.03 + vel.y * 0.01, -0.6, 0.7) + 0.35 * _sprint,
		clampf(local_vel.x * 0.03, -0.5, 0.5) + wall_roll * 0.25)
	if idle_w > 0.0:
		sway_target += Vector2(sin(_t * 1.7) * 0.05, sin(_t * 1.1) * 0.06) * idle_w
	for i: int in n:
		var aacc: Vector2 = (sway_target - _antenna_sway) * 170.0 - _antenna_vel * 7.5
		_antenna_vel += aacc * h
		_antenna_sway += _antenna_vel * h
	_antenna_sway = _antenna_sway.clamp(Vector2(-0.9, -0.9), Vector2(0.9, 0.9))
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
