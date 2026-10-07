class_name KitUtil
extends RefCounted
## Shared helpers for the generic obstacle kit (docs/KIT_OBSTACLES.md). Everything here is
## a pure function of the course clock or a tiny scene-tree lookup.

## Every kit machine that owns a rider runs before the Player's own physics step.
const EARLY: int = -50
## Shortest tell any kit obstacle gives before it does something to the player (seconds).
const MIN_TELL: float = 0.8


## The level's fail() for `from` (a kill). Safe outside a level (tests with a bare world).
static func kill(from: Node, cause: String = "hazard") -> void:
	var n: Node = from
	while n != null and not n.has_method("fail"):
		n = n.get_parent()
	if n != null:
		n.call_deferred("fail", cause)


## 0..1 position in a cycle of `period` seconds shifted by `phase` (a fraction of a period).
static func cycle_u(time: float, period: float, phase: float) -> float:
	return fposmod(time / maxf(period, 0.01) + phase, 1.0)


## Seconds into the cycle (0..period).
static func cycle_s(time: float, period: float, phase: float) -> float:
	return cycle_u(time, period, phase) * period


## First instant on the grid (k + phase) * period that is at least `lead` seconds after `t`.
static func next_grid(t: float, period: float, phase: float, lead: float) -> float:
	var p: float = maxf(period, 0.01)
	var k: float = ceilf((t + lead) / p - phase - 0.000001)
	return (k + phase) * p


static func smooth(k: float) -> float:
	var x: float = clampf(k, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


static func smoother(k: float) -> float:
	var x: float = clampf(k, 0.0, 1.0)
	return x * x * x * (x * (x * 6.0 - 15.0) + 10.0)


## True while `test(time + s)` holds for every s in [0, window] (sampled every `step`).
static func holds_for(test: Callable, time: float, window: float, step: float = 0.05) -> bool:
	var s: float = 0.0
	while s <= window + 0.0001:
		if not bool(test.call(time + s)):
			return false
		s += step
	return true


## The default movement tuning (the same resource every Player uses).
static var _tuning: MovementTuning

static func tuning() -> MovementTuning:
	if _tuning == null:
		_tuning = load("res://resources/default_tuning.tres") as MovementTuning
	return _tuning


## Launch velocity that carries a Player from `from` to `to` (feet positions) along an arc whose
## apex is `arc` metres above the higher of the two. Solved with the Player's real gravity and
## checked against Ballistics so over-speed drag is included. Assumes the stick is held toward
## the target in flight (air braking is 3 m/s^2 with no input).
static func launch_velocity(from: Vector3, to: Vector3, arc: float = 2.5) -> Vector3:
	var t: MovementTuning = tuning()
	var apex: float = maxf(from.y, to.y) + maxf(arc, 0.3)
	var vy: float = sqrt(2.0 * t.gravity_rise * (apex - from.y))
	var t_up: float = vy / t.gravity_rise
	var t_down: float = sqrt(2.0 * (apex - to.y) / t.gravity_fall)
	var flight: float = maxf(t_up + t_down, 0.1)
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var v := Vector3(flat.x / flight, vy, flat.z / flight)
	for i: int in 3:
		var land: Vector3 = Ballistics.landing_point(t, from, v, to.y)
		var err := Vector3(to.x - land.x, 0.0, to.z - land.z)
		v.x += err.x / flight
		v.z += err.z / flight
	return v


## The Player that overlaps `area` (null when none). `need_control` skips one that cannot act.
static func player_in(area: Area3D, need_control: bool = false) -> Player:
	for b: Node3D in area.get_overlapping_bodies():
		if b is Player and (not need_control or (b as Player).control_enabled):
			return b as Player
	return null


## A flat translucent quad lying on a floor (lane strips, ground shadows). Unshaded alpha.
static func floor_quad(size: Vector2, color: Color) -> MeshInstance3D:
	var qm := QuadMesh.new()
	qm.size = size
	qm.orientation = PlaneMesh.FACE_Y
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.no_depth_test = false
	var mi := MeshInstance3D.new()
	mi.mesh = qm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Set a floor quad's colour (cheap: only touches the material when it changed).
static func set_quad_color(mi: MeshInstance3D, color: Color) -> void:
	var mat: StandardMaterial3D = mi.material_override as StandardMaterial3D
	if mat != null and not mat.albedo_color.is_equal_approx(color):
		mat.albedo_color = color


## Emission energy on a flat() material, only when it changed.
static func glow(mat: StandardMaterial3D, energy: float) -> void:
	if not is_equal_approx(mat.emission_energy_multiplier, energy):
		mat.emission_energy_multiplier = energy


## A cylinder mesh stretched between two points (chains, cables). Re-aim with place_link().
static func link(radius: float, mat: Material) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = 1.0
	cm.radial_segments = 6
	cm.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = mat
	mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func place_link(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var dir: Vector3 = b - a
	var dist: float = dir.length()
	if dist < 0.001:
		mi.visible = false
		return
	mi.visible = true
	var up: Vector3 = dir / dist
	var ref: Vector3 = Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var side: Vector3 = up.cross(ref).normalized()
	mi.transform = Transform3D(Basis(side, up * dist, side.cross(up)), (a + b) * 0.5)
