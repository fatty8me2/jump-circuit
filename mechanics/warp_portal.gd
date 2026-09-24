class_name WarpPortal
extends Node3D
## One-way warp. Run (or fly) through the swirling entry ring and you come out of
## the exit ring facing its forward (-Z) with the speed you went in with (at least
## `min_exit_speed`); vertical speed is kept, so a jump through stays a jump.
## Both rings stand on their floor point. Entry is warm orange, exit is cool blue,
## so which way a pair works is readable at a glance.

const ENTRY_COLOR: Color = Color(1.0, 0.55, 0.15)
const EXIT_COLOR: Color = Color(0.35, 0.7, 1.0)
const RING_RADIUS: float = 1.35

## Exit ring position (floor point) and heading in world space.
@export var exit_pos: Vector3 = Vector3.ZERO
@export var exit_yaw_deg: float = 0.0
@export var min_exit_speed: float = 6.0

var _area: Area3D
var _exit: Node3D
var _swirl: Array[Node3D] = []
var _cool: float = 0.0
# effects (visual only): a swirling vortex in each ring (sucking in at the entry,
# spilling out at the exit), streaks pulled into the entry, bursts on every warp
var _suck: GPUParticles3D
var _enter_burst: GPUParticles3D
var _exit_burst: GPUParticles3D
var _exit_ring: GPUParticles3D
var _exit_lamp: OmniLight3D


var _exit_glitter: GPUParticles3D
var _entry_lamp: OmniLight3D


func _ready() -> void:
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 2
	_area.monitorable = false
	var shape := BoxShape3D.new()
	shape.size = Vector3(RING_RADIUS * 1.7, RING_RADIUS * 2.0, 0.5)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	_area.add_child(cs)
	_area.position = Vector3(0, RING_RADIUS + 0.1, 0)
	add_child(_area)
	_swirl.append(_ring(self, ENTRY_COLOR))
	_exit = Node3D.new()
	_exit.top_level = true
	add_child(_exit)
	_exit.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(exit_yaw_deg)), exit_pos)
	_swirl.append(_ring(_exit, EXIT_COLOR))
	_build_fx()
	# both rings hum while they wait (the exit a little higher, like its cooler colour)
	for ring: Node3D in [self, _exit]:
		var hum: AudioStreamPlayer3D = WorldAudio.loop("warp_hum", ring, -16.0, 14.0, 3.0)
		if hum != null:
			hum.position = Vector3(0, RING_RADIUS + 0.1, 0)
			hum.pitch_scale = 1.0 if ring == self else 1.12


func _build_fx() -> void:
	var vis := AABB(Vector3(-5, -5, -5), Vector3(10, 10, 10))
	var r: float = RING_RADIUS
	# vortex: emitted on the rim / core of the spinning spoke holder, local, so the
	# whole cloud turns with it while the radial pull winds each mote into a spiral
	var entry_hot: Color = Fx.hot(ENTRY_COLOR.lerp(Color.WHITE, 0.15), 2.4)
	var exit_hot: Color = Fx.hot(EXIT_COLOR.lerp(Color.WHITE, 0.15), 2.4)
	var vin: GPUParticles3D = Fx.emitter({"amount": 70, "lifetime": 1.1, "local": true, "shape": "ring",
		"ring_axis": Vector3.BACK, "ring_radius": r - 0.12, "ring_inner": r - 0.35, "speed": Vector2.ZERO,
		"radial": Vector2(-3.2, -2.0), "tex": Fx.Tex.STAR, "size": 0.22, "curve": "pop",
		"fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]), "color": entry_hot, "aabb": vis, "preprocess": 1.1})
	_swirl[0].add_child(vin)
	var vout: GPUParticles3D = Fx.emitter({"amount": 70, "lifetime": 1.1, "local": true, "shape": "ring",
		"ring_axis": Vector3.BACK, "ring_radius": 0.35, "ring_inner": 0.05, "speed": Vector2(0.2, 0.5),
		"dir": Vector3.RIGHT, "spread": 180.0, "flatness": 1.0, "radial": Vector2(1.6, 2.6),
		"tex": Fx.Tex.STAR, "size": 0.22, "curve": "pop", "fade": PackedFloat32Array([0.0, 1.0, 1.0, 0.0]),
		"color": exit_hot, "aabb": vis, "preprocess": 1.1})
	_swirl[1].add_child(vout)
	# streaks drawn in from all round the entry ring
	var centre := Vector3(0, r + 0.1, 0)
	_suck = Fx.emitter({"amount": 40, "lifetime": 0.55, "local": true, "shape": "shell", "radius": 3.2,
		"speed": Vector2.ZERO, "radial": Vector2(-22.0, -16.0), "facing": "velocity", "tex": Fx.Tex.SPARK,
		"size": Vector2(0.05, 0.7), "fade": PackedFloat32Array([0.0, 0.9, 0.0]), "color": entry_hot,
		"aabb": vis, "preprocess": 0.6})
	_suck.position = centre
	add_child(_suck)
	# warp bursts: sparks out of the entry film, and out of the exit ring with a ring + flash
	_enter_burst = Fx.sparks({"amount": 50, "lifetime": 0.45, "shape": "ring", "ring_axis": Vector3.BACK,
		"ring_radius": r - 0.1, "ring_inner": 0.2, "dir": Vector3.BACK, "spread": 60.0,
		"speed": Vector2(3.0, 8.0), "gravity": Vector3(0, -6, 0), "damping": Vector2(3.0, 5.0),
		"color": entry_hot, "aabb": vis})
	_enter_burst.position = centre
	add_child(_enter_burst)
	_exit_burst = Fx.sparks({"amount": 80, "lifetime": 0.6, "shape": "ring", "ring_axis": Vector3.BACK,
		"ring_radius": r - 0.1, "ring_inner": r - 0.3, "dir": Vector3.FORWARD, "spread": 55.0,
		"radial_vel": Vector2(1.0, 4.0), "speed": Vector2(4.0, 10.0), "gravity": Vector3(0, -5, 0),
		"damping": Vector2(2.0, 4.0), "size": Vector2(0.07, 0.55), "color": exit_hot, "aabb": vis})
	_exit_burst.position = centre
	_exit.add_child(_exit_burst)
	_exit_ring = Fx.shockwave(r * 2.0, {"lifetime": 0.4, "color": exit_hot, "aabb": vis})
	_exit_ring.transform = Transform3D(Fx.basis_up(Vector3.FORWARD), centre + Vector3(0, 0, -0.3))
	_exit.add_child(_exit_ring)
	_exit_lamp = OmniLight3D.new()
	_exit_lamp.light_color = EXIT_COLOR
	_exit_lamp.omni_range = 7.0
	_exit_lamp.light_energy = 0.0
	_exit_lamp.visible = false
	_exit_lamp.position = centre + Vector3(0, 0, -0.8)
	_exit.add_child(_exit_lamp)
	# glitter that hangs in front of the exit after a warp
	_exit_glitter = Fx.embers({"amount": 30, "lifetime": 1.4, "one_shot": true, "explosiveness": 0.8,
		"emitting": false, "shape": "sphere", "radius": r * 0.8, "speed": Vector2(0.3, 1.2), "tex": Fx.Tex.STAR,
		"size": 0.26, "curve": "pop", "color": exit_hot, "turbulence": 0.6, "aabb": vis})
	_exit_glitter.position = centre + Vector3(0, 0, -0.6)
	_exit.add_child(_exit_glitter)
	# a steady glow inside each ring (Medium and up) and a flash at the entry on a warp
	if Fx.density() >= 0.5:
		for i: int in 2:
			var glow := OmniLight3D.new()
			glow.light_color = ENTRY_COLOR if i == 0 else EXIT_COLOR
			glow.light_energy = 1.2
			glow.omni_range = 4.5
			glow.shadow_enabled = false
			glow.position = centre + Vector3(0, 0, -0.5)
			(self if i == 0 else _exit).add_child(glow)
		_entry_lamp = OmniLight3D.new()
		_entry_lamp.light_color = ENTRY_COLOR
		_entry_lamp.omni_range = 7.0
		_entry_lamp.light_energy = 0.0
		_entry_lamp.visible = false
		_entry_lamp.position = centre + Vector3(0, 0, 0.8)
		add_child(_entry_lamp)


func _warp_fx() -> void:
	if _exit_burst == null:
		return
	_enter_burst.restart()
	_exit_burst.restart()
	_exit_ring.restart()
	_exit_glitter.restart()
	Fx.pulse(_exit_lamp, 7.0, 0.0, 0.5)
	if _entry_lamp != null:
		Fx.pulse(_entry_lamp, 5.0, 0.0, 0.4)


func _ring(parent: Node3D, color: Color) -> Node3D:
	var torus := TorusMesh.new()
	torus.inner_radius = RING_RADIUS - 0.14
	torus.outer_radius = RING_RADIUS + 0.14
	torus.rings = 32
	torus.ring_segments = 10
	var ring := Look.mesh_node(torus, Look.flat(color, 0.3, 0.3, 2.2), Vector3(0, RING_RADIUS + 0.1, 0))
	ring.rotation.x = PI * 0.5
	parent.add_child(ring)
	var film_mat := StandardMaterial3D.new()
	film_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	film_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	film_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	film_mat.albedo_color = Color(color.r, color.g, color.b, 0.28)
	var disc := CylinderMesh.new()
	disc.top_radius = RING_RADIUS - 0.1
	disc.bottom_radius = RING_RADIUS - 0.1
	disc.height = 0.02
	disc.radial_segments = 32
	var film := Look.mesh_node(disc, film_mat, Vector3(0, RING_RADIUS + 0.1, 0))
	film.rotation.x = PI * 0.5
	film.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(film)
	# a spinning spoke so the film reads as a swirl
	var spoke_holder := Node3D.new()
	spoke_holder.position = Vector3(0, RING_RADIUS + 0.1, 0)
	parent.add_child(spoke_holder)
	var spoke_mat: StandardMaterial3D = Look.flat(color.lightened(0.4), 0.3, 0.0, 2.0)
	for i: int in 3:
		var arm := Look.box(Vector3(RING_RADIUS * 0.9, 0.06, 0.03), spoke_mat, Vector3(RING_RADIUS * 0.45, 0, 0).rotated(Vector3.BACK, TAU * float(i) / 3.0))
		arm.rotation.z = TAU * float(i) / 3.0
		spoke_holder.add_child(arm)
	# base plinth
	parent.add_child(Look.box(Vector3(RING_RADIUS * 1.6, 0.2, 0.7), Look.flat(Color(0.16, 0.16, 0.2), 0.4, 0.6), Vector3(0, 0.1, 0)))
	return spoke_holder


## Where a runner coming out of the exit ring starts (world).
func exit_point() -> Vector3:
	return exit_pos + Basis(Vector3.UP, deg_to_rad(exit_yaw_deg)) * Vector3(0, 0.15, -0.9)


func _process(dt: float) -> void:
	for i: int in _swirl.size():
		_swirl[i].rotation.z += dt * (3.0 if i == 0 else -3.0)


func _physics_process(dt: float) -> void:
	_cool = maxf(_cool - dt, 0.0)
	if _cool > 0.0:
		return
	for body: Node3D in _area.get_overlapping_bodies():
		if body is Player:
			var p := body as Player
			var v: Vector3 = p.velocity
			var speed: float = maxf(Vector2(v.x, v.z).length(), min_exit_speed)
			var b := Basis(Vector3.UP, deg_to_rad(exit_yaw_deg))
			p.teleport(Transform3D(b, exit_point()))
			p.velocity = b * Vector3(0, 0, -speed) + Vector3(0, maxf(v.y, 0.0), 0)
			var lvl: Node = self
			while lvl != null and not (lvl is LevelBase):
				lvl = lvl.get_parent()
			if lvl != null and (lvl as LevelBase).camera != null:
				(lvl as LevelBase).camera.face(b * Vector3.FORWARD)
			_cool = 0.5
			# the warp is the runner's own experience: heard flat, not from where the exit is
			Sfx.play("warp_whoosh", 0.03, 0.75)
			_warp_fx()
			return
