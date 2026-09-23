class_name MovementTuning
extends Resource
## Every number that shapes how the player moves lives here.
## Edit resources/default_tuning.tres (or duplicate it) instead of touching player.gd.

@export_group("Ground")
## Top running speed reached from input alone (m/s).
@export var max_speed: float = 9.0
@export var ground_accel: float = 62.0
## Deceleration with no input.
@export var ground_brake: float = 58.0
## Acceleration used while input opposes current velocity (snappy turnarounds).
@export var turn_accel: float = 105.0
## How quickly speed above max_speed bleeds off while grounded. Low = momentum survives landings.
@export var overspeed_friction: float = 5.0
## How quickly an over-speed runner can steer (1/s).
@export var overspeed_steer: float = 5.0

@export_group("Air")
@export var air_accel: float = 24.0
## Drag with no input while airborne.
@export var air_brake: float = 3.0
## Bleed of speed above max_speed while airborne.
@export var air_overspeed_drag: float = 0.6
## Absolute horizontal speed bound.
@export var hard_speed_cap: float = 34.0

@export_group("Jump")
@export var jump_velocity: float = 12.0
@export var gravity_rise: float = 30.0
@export var gravity_fall: float = 42.0
## Gravity multiplier while rising after the jump button was released (short hops).
@export var jump_cut_multiplier: float = 2.7
## Gravity multiplier around the apex while jump is held (a touch of hang time).
@export var apex_hang_multiplier: float = 0.62
@export var apex_hang_speed: float = 1.6
@export var max_fall_speed: float = 38.0
@export var coyote_time: float = 0.11
@export var jump_buffer_time: float = 0.13

@export_group("Surfaces")
@export var floor_snap: float = 0.28
@export var floor_max_angle_deg: float = 46.0
## Largest upward platform speed inherited on takeoff (m/s).
@export var max_inherited_up_speed: float = 7.0
## Boards steeper than this start to slide the player downhill (degrees).
@export var slip_start_deg: float = 11.0
## Downhill drift speed gained per degree of tilt beyond slip_start_deg (m/s per degree).
@export var slip_speed_per_deg: float = 0.45

@export_group("Dynamics")
## Player mass used for weight/impact transfer into tilting platforms and props (kg).
@export var mass: float = 70.0
## Cap on landing impulse handed to platforms (N*s).
@export var max_impact_impulse: float = 1400.0
## Impulse scale when shoving loose rigid props.
@export var prop_push: float = 0.9

@export_group("Wall run")
## Only surfaces that answer is_wall_run() (glowing wall-run panels) can be run on.
## Least speed along the wall needed to latch on (m/s).
@export var wall_run_min_speed: float = 4.5
## Speed along the wall while running (faster arrivals keep their speed).
@export var wall_run_speed: float = 10.0
## Vertical speed on latching (clamped between this and wall_run_lift_max).
@export var wall_run_lift: float = 3.5
@export var wall_run_lift_max: float = 5.0
## Gravity while running: a slow arc, not a fall.
@export var wall_run_gravity: float = 8.0
## Longest run on one panel before you peel off (s).
@export var wall_run_time: float = 1.4
## A fall faster than this cannot latch (m/s).
@export var wall_run_max_entry_fall: float = 11.0
## Wall jump: speed away from the wall and upward. Speed along the wall is kept.
@export var wall_jump_push: float = 7.5
@export var wall_jump_velocity: float = 11.0
## Grace period to wall-jump after running off a panel's end (s).
@export var wall_coyote_time: float = 0.15

@export_group("Mantle")
## Only surfaces that answer is_ledge() (ledges with a bright lip) can be mantled.
## Highest ledge top above the feet that the hands can still catch (m).
@export var mantle_reach: float = 2.05
## Lowest ledge top above the feet worth a mantle (below it you just land).
@export var mantle_min: float = 0.35
## Seconds from grab to standing on top.
@export var mantle_time: float = 0.34
## Forward speed on top when the climb ends.
@export var mantle_exit_speed: float = 4.0
