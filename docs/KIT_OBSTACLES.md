# Generic obstacle kit (v2.0, workstream O)

Ten reusable, theme-neutral obstacles for any course, built with `kit.<name>(...)` in a level's
`_build()`. They use `Look` / `Fx`, so they pick up the world's palette. See them all in the
**Kit Gallery** (dev playground, walk east from the spawn) and wired into routes in
`tests/kit_course.gd` and `tests/kit_course2.gd`.

## Rules every kit obstacle follows

- **Course clock.** Everything is a pure function of `Game.course_time` (identical for every racer,
  survives `restart_run()`). Each machine has `period` and `phase` (a fraction of a period) and
  prediction helpers named `is_*_for(time, window)` / `*_in(time)` that take a course time.
- **Tell >= 0.8 s** before anything happens to the player (clamped in code: you cannot set a shorter
  one). The tell is both visual (glow, shadow, lamp, wind-up) and a one-shot clip.
- **Positions are where feet go**: `floor_top` / `top` is the surface you stand on, like `kit.plat`.
  Nodes whose name says "pivot/hinge" sit at deck-top height.
- **Yaw** turns the machine about Y; "forward" is local -Z (so yaw 0 = along the course), except
  where noted (log and flipper lie along local X).
- **Kills** go through the level's `fail("hazard")` (cannonballs, falling block). Everything else
  throws or carries (no deaths unless it throws you off something).
- **Nothing here changes the player's moves.** Machines use `Player.knockback()`, `add_impulse()`,
  the existing `surface_velocity()` / TiltSurface hooks and (barrel, zipline) a short "rider held"
  state that sets `control_enabled = false` and gives it back.
- **Sound** is a side effect only: `WorldAudio.at/loop` with clips named `kit_<machine>_*` (list at
  the end). Missing clips are skipped silently. Headless runs play nothing.
- **Reset**: the stateful ones (barrel, zipline, approach-mode block) join `resettable` and let go
  of the rider on respawn / `restart_run()`.

## Route-bot support

New route helpers (in `levels/level_base.gd`) and bot steps (in `tests/route_bot.gd`):

| Route call | Step | What the bot does |
|---|---|---|
| `r_barrel(barrel, to)` | `k_barrel` | walks into the barrel, waits out the tell, then air-steers to `to` until it lands |
| `r_zipline(zip, point, radius, to)` | `k_zip` | stands under the zipline's start until picked up, rides, lets go (`zip.release_rider()`, same as a jump press) once the trolley is within `radius` of world point `point`, air-steers to `to` |
| `r_until(test)` (exists) | `b_wait` | stands still until `test.call()` is true: use the machine's `is_*_for(Game.course_time, w)` helper |
| `{"kind": "kick", "from", "to"}` (exists) | `kick` | stands at `from` until something throws it, air-steers to `to`. Use it for the flipper and hammer |

Also, `RouteBot._steer_ground` now cancels a `RollingLog`'s sideways drag (it only cancelled
opposing conveyors before), so a plain `r_walk` along a log works.

Typical wiring for the timed ones: walk to a waiting spot, `r_until(...)`, `r_walk` through. Pick the
`window` to cover the walk through plus ~0.5 s of margin (the bot covers ~9 m/s once up to speed).

## The ten

Each entry: signature, what it does, how to wire it, clips. All return the mechanic node.

### 1. `kit.barrel(floor_top, target, arc = 3.0, period = 3.0, phase = 0.0, tell = 1.0) -> LaunchBarrel`
A barrel standing on `floor_top`. Walk (or fall) into the mouth and you are held inside; it shudders
and the hoops glow white-hot for the tell, then fires you along a fixed arc to land on `target`
(a feet position; hold the stick toward it, the arc assumes forward is held: air braking is
3 m/s^2). `arc` = metres the path rises above the higher of start and target. It fires on the clock
grid `(k + phase) * period`, never sooner than `tell` after you got in (`fire_time_after(t)`), then
ignores you for 0.7 s. Give the landing 4 m or more across (measured error with forward held: ~1.9 m
for a 14 m shot).
Route: `r_barrel(b, target)`. Helpers: `is_loaded()`, `loaded_player()`, `time_to_fire()`,
`launch_velocity()`, `fire_time_after(t)`, `fired_within(s)`.
Clips: `kit_barrel_load`, `kit_barrel_fuse`, `kit_barrel_fire`.

### 2. `kit.zipline(start_top, end_top, speed = 11.0, dwell = 1.4, phase = 0.0) -> Zipline`
A cable between two floor points (the cable is 2.2 m above each; the rider hangs 1.9 m below the
trolley). The trolley waits `dwell` s at the start (lamp flashes and it rattles through the last
second), rides at `speed` m/s (a 0.2 ramp-up, then constant), rests 0.35 s at the far end and
returns empty (not grabbable). Standing under it, or jumping into it, while it waits or rides grabs
on. **Jump to let go**: you keep the cable's velocity and add a 6 m/s hop. If you do nothing you are
let go at the far end with the same speed. After a release it ignores you for 0.8 s.
Route: `r_zipline(z, point_on_cable, radius, to)`; `z.handle_at(t)`, `z.velocity_at(t)`,
`z.departs_in(t)`, `z.exit_velocity()`, `z.stand_point()`, `z.rider_feet_at(t)`, `z.release_rider()`.
The release point must be a spot the trolley passes (world coordinates of the HANG point = cable
height, i.e. floor + 2.2). Land past the cable end: you fly on at cable speed.
Clips: `kit_zipline_ready`, `kit_zipline_grab`, `kit_zipline_release`, `kit_zipline_whirr` (loop).

### 3. `kit.battery(floor_pos, yaw_deg = 0, lane_length = 22, speed = 9, period = 3.2, phase = 0, fly_height = 0, opts = {}) -> CannonBattery`
A cannon on the floor point `floor_pos` firing down local -Z. Every `period` s it fires `salvo` balls
(opts: `salvo`, `spacing`, `ball_radius`, `lane_width`, `tell`) that travel `lane_length` m at
`speed`. `fly_height` 0 = rolling balls (radius 0.55: jump them, jump ~0.35 s before they arrive);
else flying at that centre height. A ball kills. The tell (last second before every shot): muzzle
heats, the fuse spits, the lane strip on the floor flashes.
Predictions: `balls_at(t)` (metres from the muzzle), `is_clear_for(d0, d1, window, t = now, margin = 0.9)`
= no ball can touch lane stretch d0..d1 in the next `window` s, `time_to_salvo(t)`.
Route: put the crossing spot at distance `d` from the muzzle (the muzzle is 1.9 m in front of the
node) and `r_until(func(): return bat.is_clear_for(d - 1.6, d + 1.6, 1.3))`, then `r_walk` across.
Clips: `kit_battery_fuse`, `kit_battery_fire`.

### 4. `kit.log_roller(top, length = 12, diameter = 2.4, yaw_deg = 0, speed = 4, period = 0, phase = 0) -> RollingLog`
A log lying along local X (so `yaw_deg = 90` runs it along the course's Z). Its skin drags a rider
along local Z, like a conveyor: `speed(t) = speed * sin(2 pi (t / period + phase))`, or a constant
`speed` when `period` is 0. With `period` the push eases through zero twice a period, so the log
visibly slows and stops before reversing (the tell). A cylinder collider: stay near the top line.
Route: plain `r_walk` along it (the bot cancels the drag); to cross only in the calm spell:
`r_until(func(): return log.is_calm_for(Game.course_time, 1.0, 1.0))`. Also `speed_at(t)`,
`calm_in(t)`, `surface_velocity()`.
Clips: `kit_log_roll` (loop, pitch follows the speed), `kit_log_reverse`.

### 5. `kit.seesaw(top, length = 9, width = 2.6, along_x = true, bias_deg = 0, opts = {}) -> Seesaw`
A weight-driven plank on a centre pivot. It *is* a `TiltPlatform` (Jolt spring/damper, kinematic
top surface), so footing is the same as the balance world's boards. Stand on an end and that end
sinks about 10 deg, walk to the middle to level it, on to the far end and it tips the other way.
`along_x = false` lays it along Z (a plank across a gap on the course axis). `bias_deg` is a
counterweight: the empty plank rests tipped that far. `opts` sets any TiltPlatform field. It tips
no further than 10.5 deg at the very end, which is under the slip angle (11 deg), so ends are
standable; steeper settings make the ends slippery on purpose.
Route: `r_walk` across (bridge gap <= 1 m at each end), `r_jump` off the low end. `s.axis_degrees()`,
`s.is_level(tol)`.
Clip: `kit_seesaw_thunk`.

### 6. `kit.flipper(pivot_top, length = 5, rest_deg = 0, swing_deg = 80, period = 4, phase = 0, opts = {}) -> Flipper`
A pinball flipper lying flat (solid, rideable), pivoting at `pivot_top` (at paddle-top height; the
paddle sits 3 cm proud of that so a flush deck never z-fights). It lies along local +X turned by
`rest_deg`, winds back 8 deg through the tell, SWATS through `swing_deg` (positive = toward -Z) in
0.12 s, holds 0.5 s and eases back in 0.8 s. A rider on or beside it during the swat is thrown along
the swing (`power` 15 m/s at the tip, 40% near the pivot, +8 lift): from the tip it carries ~5.5 m
(`throw_velocity(world_pos)` predicts it). opts: `width`, `thick`, `tell`, `power`, `lift`.
Route as a launcher: `r_walk(spot_near_tip)` then `{"kind": "kick", "from": spot, "to": landing}`
(landing ~5.5 m beyond). As a gate: `r_until(func(): return fl.swat_free_for(Game.course_time, 2.0))`.
Clips: `kit_flipper_tell`, `kit_flipper_swat`, `kit_flipper_return`.

### 7. `kit.drawbridge(hinge_top, length = 8, width = 3.4, yaw_deg = 0, period = 9, phase = 0, opts = {}) -> Drawbridge`
A deck hinged at `hinge_top`, running `length` m along local -Z, with a gatehouse frame and glowing
chains. Cycle: flat for most of the period, chains rattle for `warn` s (the tell, opts `warn`), rises
~80 deg in 1.1 s, held 1.3 s, lowers 1.3 s. Raised, it stands as a wall above the hinge edge. A rider
on the rising deck slides back off it. The hinge edge needs ground behind it; the free end needs ground
(or a gap you mean to open) at the far side.
Route: `r_until(func(): return br.is_down_for(Game.course_time, crossing_s + 0.5))`. Also `phase_at(t)`,
`angle_at(t)`, `down_left(t)`, `down_in(t)`.
Clips: `kit_drawbridge_chains`, `kit_drawbridge_raise`, `kit_drawbridge_lower`, `kit_drawbridge_thud`.

### 8. `kit.gap_wall(floor_pos, yaw_deg = 0, gap = 3.4, period = 8, phase = 0, opts = {}) -> GapWall`
A 5 m tall solid wall across a lane (the lane runs along local Z; yaw 0 = you walk along -Z) with a
`gap`-wide doorway. The doorway sits on the lane for `open_time` s (the lamp over it flashes amber
for the last `warn` s), the wall slides sideways `slide` m in `move_time` s (>= 0.8) to shut the lane,
stays shut, slides back. It is solid and pushes what is in its way: do not stand in the doorway as it
closes. opts: `height`, `thick`, `slide`, `open_time`, `move_time`, `warn`, `side` (+1/-1).
Route: `r_until(func(): return gw.is_open_for(Game.course_time, crossing_s + 0.5))`. Also `state_at(t)`,
`offset_at(t)`, `open_in(t)`.
Clips: `kit_gapwall_warn`, `kit_gapwall_slide`, `kit_gapwall_thud`.

### 9. `kit.falling_block(floor_top, size = (3, 1.6, 3), drop_height = 7, period = 5, phase = 0, approach = false, opts = {}) -> FallingBlock`
A slab hung `drop_height` m above `floor_top` (the floor point under its centre). A dark shadow swells
on the floor for `tell` s (>= 0.8; the block judders at the end), then it drops in 0.3 s. Under it while
it falls or sits = back to the checkpoint. It rests 1.4 s (the top is solid and rideable), rises 1.4 s.
`approach = true`: it idles (faint shadow) until a rider is within `trigger_radius` (opts, 4.5 m); the
tell then starts at once, so a quick runner can beat it. Everything resets on respawn.
Route (clock mode): `r_until(func(): return blk.is_clear_for(Game.course_time, crossing_s + 0.5))`.
Also `phase_at(t)`, `gap_at(t)`, `time_to_land(t)`, `arm(t)`.
Clips: `kit_block_tell`, `kit_block_slam`, `kit_block_rise`.

### 10. `kit.hammer(floor_top, arm_length = 5, period = 4.8, phase = 0, park_deg = 180, spin_dir = 1, opts = {}) -> SpinHammer`
A solid post with an arm whose heavy head sweeps a full circle around a VERTICAL axis. It waits parked
at `park_deg` (degrees about Y from local +X toward -Z), winds back 30 deg through the tell (head
glows), sweeps one revolution in `swing_time` s (eased, 1.2 s) and parks again. Touched while
sweeping it HITS: the rider is thrown outward and along the swing (8-16 m/s, +8 lift); parked it is
harmless. The gap to pass is the parked time (`period - tell - swing_time`). opts: `arm_length`,
`arm_height`, `head_radius`, `tell`, `swing_time`, `windup_deg`.
Route: path on the side the parked arm is NOT on: `r_until(func(): return hm.is_parked_for(Game.course_time, crossing_s + 0.5))`,
then `r_walk`. As a launcher use a `kick` step. Also `phase_at(t)`, `angle_at(t)`, `tip_speed_at(t)`,
`parked_left(t)`, `parked_in(t)`.
Clips: `kit_hammer_tell`, `kit_hammer_swing`, `kit_hammer_park`.

## Timing numbers at a glance

| Obstacle | Default period | Tell | What follows |
|---|---|---|---|
| barrel | 3.0 (grid) | 1.0 s from entry | fires at the next grid tick >= entry + tell |
| zipline | 1.4 + ride + 0.35 + return | 1.0 s lamp flash | ride (26 m = 2.6 s) |
| battery | 3.2 | 1.0 s | ball every period; 9 m/s |
| log | 6.0 (if reversing) | slow-down, ~1.3 s | reverses |
| seesaw | none | none (weight driven) | |
| flipper | 4.0 | 0.9 s | swat 0.12 s, hold 0.5 s, return 0.8 s |
| drawbridge | 9.0 | 1.0 s | rise 1.1, up 1.3, lower 1.3 |
| gap wall | 8.0 | 1.0 s lamp + 1.2 s slide | shut 3.0 s |
| falling block | 5.0 | 1.0 s | fall 0.3, down 1.4, rise 1.4 |
| hammer | 4.8 | 0.9 s | swing 1.2 s, parked 2.7 s |

Keep waits under ~12 s per step (the bot gives a step 14 s) when you design a course around a long
period.

## Tests

Run only the kit's: `timeout 1800 $G --headless --path . res://tests/run_tests.tscn -- --only=test_zk_ --save=<branch>`

`test_zk_barrel`, `_zipline`, `_battery`, `_log`, `_seesaw`, `_flipper`, `_drawbridge`, `_gapwall`,
`_block`, `_hammer` test each machine alone (tell length, the clock predictions, the effect on the
player). `test_zk_bot_slice1` / `test_zk_bot_slice2` play `tests/kit_course.gd` / `kit_course2.gd` with
the route bot, `test_zk_gallery` loads the playground with the Kit Gallery.

## Sound clips the kit calls

One-shots unless marked loop (all positional, via `WorldAudio.at/loop`).

| Clip | Description |
|---|---|
| `kit_barrel_load` | thump as a rider drops into the barrel |
| `kit_barrel_fuse` | short fuse tick/sizzle, repeated every 0.2 s through the 1 s tell (volume rises) |
| `kit_barrel_fire` | cannon boom + whoosh as the barrel fires |
| `kit_zipline_ready` | trolley clank/rattle, 1 s before it departs |
| `kit_zipline_grab` | clack as the rider grabs the bar |
| `kit_zipline_release` | short release clack/whoosh |
| `kit_zipline_whirr` | loop: pulley whirr while a rider is on the cable |
| `kit_battery_fuse` | lit-fuse hiss at the start of the 1 s tell |
| `kit_battery_fire` | cannon blast |
| `kit_log_roll` | loop: wooden rumble of a turning log (pitch follows its speed) |
| `kit_log_reverse` | wood creak/clunk as the roll reverses |
| `kit_seesaw_thunk` | wood thunk when an end hits its stop |
| `kit_flipper_tell` | ratchet wind-up (~0.9 s) |
| `kit_flipper_swat` | hard thwack/clank of the paddle |
| `kit_flipper_return` | soft slide as it lowers |
| `kit_drawbridge_chains` | chain rattle (~1 s) |
| `kit_drawbridge_raise` | chain and timber creak as the deck rises |
| `kit_drawbridge_lower` | lowering creak |
| `kit_drawbridge_thud` | heavy thud as the deck lands |
| `kit_gapwall_warn` | single warning beep as the lamp starts flashing |
| `kit_gapwall_slide` | stone grind (~1.2 s) while the wall slides |
| `kit_gapwall_thud` | heavy thud as it shuts |
| `kit_block_tell` | low rumble/groan (~1 s) while the shadow grows |
| `kit_block_slam` | huge slam |
| `kit_block_rise` | hydraulic haul back up |
| `kit_hammer_tell` | creak/wind-up (~0.9 s) |
| `kit_hammer_swing` | big whoosh (~1.2 s) |
| `kit_hammer_park` | soft thunk as the arm parks |

The flipper and hammer also use the existing `whack` clip for the hit.
