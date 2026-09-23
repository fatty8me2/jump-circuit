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
			Sfx.play_at("go", exit_pos, 0.05, 0.7)
			return
