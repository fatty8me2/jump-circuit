class_name OrbitCamera
extends Camera3D
## Mouse-driven orbit camera built for platforming:
##  * horizontal follow is exact (no lag to fight while lining up a jump)
##  * vertical follow is softened while airborne so jumps don't bob the view
##  * looks slightly ahead/below during falls so the landing stays in frame
##  * sphere-cast collision pulls in instantly, eases back out
## Runs in _process from the player's interpolated transform.

@export var distance: float = 7.2
@export var min_distance: float = 3.5
@export var max_distance: float = 11.0
@export var height: float = 1.35
@export var pitch_min_deg: float = -78.0
@export var pitch_max_deg: float = 40.0

var target: Player
var yaw: float = 0.0
var pitch: float = deg_to_rad(-22.0)
var mouse_enabled: bool = true

var _focus: Vector3
var _focus_ready: bool = false
var _cur_dist: float = 7.2
var _fall_look: float = 0.0
var _shape: SphereShape3D
var _fov_kick: float = 0.0


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_shape = SphereShape3D.new()
	_shape.radius = 0.28
	near = 0.08
	far = 900.0
	fov = Settings.fov
	_cur_dist = distance


func face(dir: Vector3) -> void:
	if dir.length() > 0.01:
		yaw = atan2(-dir.x, -dir.z)
	pitch = deg_to_rad(-22.0)
	_focus_ready = false


func _unhandled_input(event: InputEvent) -> void:
	if not mouse_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		var s: float = 0.0023 * Settings.mouse_sensitivity
		yaw -= mm.relative.x * s
		var dy: float = mm.relative.y * s
		pitch += dy if Settings.invert_y else -dy
		pitch = clampf(pitch, deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))
	elif event is InputEventMouseButton and event.is_pressed():
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(distance - 0.6, min_distance)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(distance + 0.6, max_distance)


func _process(dt: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	# right stick
	var stick := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if stick.length() > 0.2 and mouse_enabled:
		yaw -= stick.x * 2.6 * dt * Settings.mouse_sensitivity
		pitch = clampf(pitch - stick.y * 1.8 * dt * (-1.0 if Settings.invert_y else 1.0), deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))
	target.camera_yaw = yaw

	var p: Vector3 = target.get_global_transform_interpolated().origin
	if not _focus_ready:
		_focus = p
		_focus_ready = true
		_fall_look = 0.0
	_focus.x = p.x
	_focus.z = p.z
	var rate: float = 14.0 if target.grounded else 5.5
	_focus.y = lerpf(_focus.y, p.y, 1.0 - exp(-rate * dt))
	_focus.y = clampf(_focus.y, p.y - 1.6, p.y + 2.6)
	var fall_target: float = clampf((-target.velocity.y - 10.0) * 0.12, 0.0, 2.6) if not target.grounded else 0.0
	_fall_look = lerpf(_fall_look, fall_target, 1.0 - exp(-4.0 * dt))

	# speed opens the lens a little: momentum should be felt, not just measured
	var kick_target: float = clampf((target.horizontal_speed() - 10.5) * 1.1, 0.0, 17.0)
	_fov_kick = lerpf(_fov_kick, kick_target, 1.0 - exp(-3.5 * dt))
	fov = Settings.fov + _fov_kick

	var pivot: Vector3 = _focus + Vector3(0, height - _fall_look, 0)
	var rot := Basis.from_euler(Vector3(pitch, yaw, 0))
	var back: Vector3 = rot * Vector3(0, 0, 1)
	var want: float = distance
	var hit: float = _cast(pivot, back * want)
	var allowed: float = maxf(want * hit - 0.05, 0.6)
	if allowed < _cur_dist:
		_cur_dist = allowed
	else:
		_cur_dist = minf(_cur_dist + 7.0 * dt, allowed)
	global_transform = Transform3D(rot, pivot + back * _cur_dist)
	_apply_impact(dt)


func _cast(from: Vector3, motion: Vector3) -> float:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space == null:
		return 1.0
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _shape
	q.transform = Transform3D(Basis(), from)
	q.motion = motion
	q.collision_mask = 1
	var res: PackedFloat32Array = space.cast_motion(q)
	return res[0] if res.size() > 0 else 1.0


# ---- impact jolt (cosmetic only) --------------------------------------------
# A short, small shake when a hazard throws the player. It is applied to the
# rendered transform only: yaw, pitch and the player's camera_yaw never see it.
# Landings and pads deliberately don't shake - that is when the next jump is lined up.

const JOLT_MAX_TRAUMA: float = 0.6
const JOLT_DECAY: float = 2.5          # trauma per second
const JOLT_OFFSET: float = 0.12        # metres at trauma 1 (scaled by trauma^2)
const JOLT_ANGLE_DEG: float = 0.9      # degrees at trauma 1 (scaled by trauma^2)

var _trauma: float = 0.0
var _jolt_t: float = 0.0
var _hooked: Player


## Kicks the camera: `amount` of trauma (0..1), capped and fading within ~0.25 s.
func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, JOLT_MAX_TRAUMA)


func _on_target_knocked(v: Vector3) -> void:
	add_trauma(clampf(v.length() / 40.0, 0.3, JOLT_MAX_TRAUMA))


func _apply_impact(dt: float) -> void:
	if _hooked != target:
		if _hooked != null and is_instance_valid(_hooked) and _hooked.knocked.is_connected(_on_target_knocked):
			_hooked.knocked.disconnect(_on_target_knocked)
		_hooked = target
		_hooked.knocked.connect(_on_target_knocked)
	if _trauma <= 0.0:
		return
	_trauma = maxf(_trauma - JOLT_DECAY * dt, 0.0)
	_jolt_t += dt
	var k: float = _trauma * _trauma
	var n := Vector3(sin(_jolt_t * 47.0), sin(_jolt_t * 59.0 + 1.3), sin(_jolt_t * 53.0 + 2.1))
	var ang: float = deg_to_rad(JOLT_ANGLE_DEG) * k
	var b: Basis = global_basis
	global_transform = Transform3D(b * Basis.from_euler(Vector3(n.y * ang, n.z * ang, 0.0)),
		global_position + b * (Vector3(n.x, n.y, 0.0) * JOLT_OFFSET * k))
