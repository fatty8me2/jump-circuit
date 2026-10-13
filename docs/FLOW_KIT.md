# Flow kit (v2.1, workstream F2)

Momentum mechanics for the Flow levels: speed rings and boost gates (with a per-level chain counter), flow slopes,
half-pipes, grind rails and launch arcs. Built like the obstacle kit (`docs/KIT_OBSTACLES.md`): `kit.<name>(...)` in a
level's `_build()`, `r_*` route helpers, bot steps, clips named `flow_*`. See every piece in the **Flow Gallery** (dev
playground: walk east past the Kit Gallery) and wired into routes in `tests/flow_course.gd` and `tests/flow_course2.gd`.

## Rules the kit follows

- **Speed is the point, death is not.** Nothing here kills. A missed ring, gate or rail costs speed, never life; put a
  deck or net under every rail and ramp.
- **Positions are where feet go**, like `kit.plat`: gates and arcs stand on a floor point, rail points are the line the
  rider's feet follow, ring centres are about 1 m above the feet.
- **Yaw** turns a piece about Y; "forward" is local -Z (yaw 0 = along the course).
- **The Player's moves are untouched.** Everything talks to the real `Player` through the floor query pattern
  (`flow()`, like `boost()` / `grip()`), a velocity set on a pass, or a short "rider held" state (the rail, like the
  zipline). Nothing changes on any existing surface or level; `movement_tuning` is untouched.
- **Sound** is a side effect only (`WorldAudio`), missing clips are skipped silently, headless plays nothing.
- **Reset**: the rail joins `resettable` and lets go of its rider on respawn; the chain forgets itself on respawn.
- **Physics runs at 120 Hz**, not 60: anything per-tick in a route or mechanic must use `dt` or
  `Engine.physics_ticks_per_second` (the kit's re-arm and cooldown timers are in seconds).

## Player hooks (all additive, in `player/player.gd`)

1. `_surface_move()`: two lines before the existing surface logic. If the floor body has a `flow()` method the move is
   handed to `_flow_move()` (below). No other surface has `flow()`, so nothing else changes.
2. `_flow_move(hv, wish, dt, f)` (new function): the ground rules on a flow surface.
   - At or under the 9 m/s run speed it is the ordinary `_ground_move`.
   - Over it, there is **no over-speed bleed**; the stick turns the heading at `carve` m/s^2 of lateral acceleration
     (30 by default, about 1.2 rad/s at 25 m/s) instead of the usual clamp-and-slerp.
   - A **downhill grade adds speed**: `gravity_fall * sin(pitch) * gain` (gain 0.55) along the downhill direction; the
     part that opposes the heading (climbing) counts 35%, so carving a half-pipe builds speed instead of draining it.
     Gain stops at `cap` (30 m/s) and never reduces a speed already over it. `hard_speed_cap` (34) still applies.
3. `flow_launch(v)` (new function): the launch arc's throw. Sets the whole velocity like a pad, drops coyote time and the
   floor snap so nothing overwrites it.

The rail carries the rider the way the zipline does (`control_enabled` off, position set before the Player's step, the
jump press read from `_jump_press_queued`), so it needs no hook.

## Route-bot support

New route helpers (`levels/level_base.gd`) and bot steps (`tests/route_bot.gd`, `_do_flow` / `_do_rail`):

| Route call | Step | What the bot does |
|---|---|---|
| `r_flow(pts, tol = 2.0)` | `f_line` | follows the polyline `pts` by pure pursuit (aims a lookahead of 0.4 s of travel, 3 to 12 m, ahead of the nearest point; full stick), on the ground or in the air; done when the last point is reached or passed within `tol` |
| `r_launch(arc, to)` | `f_launch` | runs up the ramp's centre line, gets thrown at the lip, air-steers to `to`, done on landing |
| `r_rail(rail, board, opts)` | `f_rail` | jumps (`from`) or walks onto the rail at `board`, rides, jumps off at `leave` (or rides to the end), air-steers to `to`; `chain` / `chain_next` link one rail to the next in the air |

`r_flow` is the one to use for **every** high-speed stretch: gate chains, ring lines, flow slopes and half-pipe carving
(`pipe.carve_points()`). The ordinary `r_walk` still walks to a point, which overshoots at 25 m/s; `r_flow` does not.
The existing `r_jump` works at speed (it jumps on passing `from`), and `r_checkpoint` works between any steps.

Wiring rules of thumb:

- **Path curves**: at 25 m/s the heading can turn about 1.2 rad/s, so keep the line's curve radius over ~25 m (a
  carving swing over 7 m wide walls is fine; a 90 degree corner is not, make it two 45s with a ring between).
- **Bleed**: only flow surfaces keep speed. On a plain deck an over-speed run bleeds 5 m/s^2, and in the air 0.6 m/s^2.
  End a flow stretch with a launch arc, a rail, or a plain deck you can afford to slow on.
- **Rings in the air**: the bot cannot change height in the air, so put air rings **on the ballistic path**
  (`arc.arc_points(hs)`), not where you would like the path to be.
- **0 respawns**: run each route with `test_n_bot` normally and with the temporary 1.0 s pause hook. The pause stops the
  bot dead after every checkpoint, so **a checkpoint must be followed by room to get going again** (a boost gate chain,
  a slope, a downhill rail) *before* anything that needs speed (a launch arc, an air ring line), and the checkpoint needs
  a run-out: stopping from 30 m/s takes ~6 m on a plain deck. The two test courses are built this way.
- **Measured** (the test courses, bot): gate chain 20 to 24 m/s; an 11 degree flow slope 44 m long takes 23 to 30 m/s;
  an 8 degree 90 m half-pipe carved wall to wall takes 18 to 27 m/s; rails 17 to 22 m/s; the bot tops out at the 30 m/s cap
  on both courses with 0 respawns, with and without the 1.0 s checkpoint pause.

## The kit

Each entry: signature, what it does, how to wire it, clips.

### 1. `kit.speed_ring(center, yaw_deg = 0, add_speed = 6, radius = 2.2, cap = 30, opts = {}) -> SpeedRing`
A glowing hoop centred on `center`, axis along local -Z. Pass through it going the right way and your horizontal speed
rises by `add_speed * FlowChain.bonus(chain)` (chain 1 = x1.0, +12% per ring, to x1.84 at chain 8), never past `cap`
and never lowering a faster rider. The heading is also pulled `assist` (0.35) of the way toward the ring's axis, so a
line of rings pulls you onto its line. A ring entered from behind does nothing. It re-arms 0.5 s after a pass.
Streaming dashes and a hairline run from each ring to `next_point` (opts `next`) so the next ring reads at speed.
opts: `pitch` (deg, tilts the axis), `assist`, `next`.
Helpers: `speed_out(v_in, chain)`, `contains(point)`, `passed_within(s)`, `forward()`, `passes`.
Route: put it on an `r_flow` path. Clips: `flow_ring_pass`, `flow_ring_chain` (chain of 4 or more).

### 2. `kit.ring_line(points: Array[Vector3], opts = {}) -> Array[SpeedRing]`
A line of rings through `points` (centres), each facing the next, each guiding to it; axes tilt with the rise and fall
(`tilt`, default true). opts: `add_speed`, `radius`, `cap`, `assist`, `tilt`.

### 3. `kit.boost_gate(floor_pos, yaw_deg = 0, speed = 20, width = 5, opts = {}) -> BoostGate`
A ground arch standing on `floor_pos`. Pass it going the right way and your speed is **set to `speed`** along its axis
(never slowed), heading pulled `assist` (0.6) toward the axis. Counts toward the chain. opts: `assist`, `reach` (trigger
height, 3.4), `height`, `counts_chain`, `next`.
Helpers: `speed_out(v_in)`, `passed_within(s)`. Route: on an `r_flow` path. Clip: `flow_gate_pass`.

### 4. `kit.boost_chain(points: Array[Vector3], speed = 22, width = 5, opts = {}) -> Array[BoostGate]`
A line of gates on floor points, each facing the next; `opts.speed_end` ramps the speed along the chain.

### 5. `kit.flow_slope(top, size, pitch_deg = 12, yaw_deg = 0, opts = {}) -> FlowSurface`
A slab whose surface keeps speed and adds speed downhill (see hook 2). `top` is the middle of its top face, **descending**
toward local -Z by `pitch_deg` (negative climbs), `size` = (width, thickness, length along the slope). opts: `gain`,
`cap`, `carve`. `speed_after(v0, dist, pitch_deg)` predicts the speed you arrive with.

### 6. `kit.flow_slope_between(a, b, width = 8, thick = 0.6, opts = {}) -> FlowSurface`
The same from the middle of the top edge at `a` to the middle of the far top edge at `b` (a above b = downhill). The
tops meet decks at `a` and `b` flush. Use it for almost every slope. A slope of 8 to 14 degrees reaches 25 to 30 m/s
in 40 to 70 m from a 20 m/s start.

### 7. `kit.halfpipe(start, end, width = 10, depth = 2, opts = {}) -> HalfPipe`
A carved trough from `start` to `end` (bottom centre line points; `end` lower = a descending pipe). Its depth eases in
over `taper` (8) m at both ends so it is entered and left flush with ground at the start / end height, never over a lip.
It is a FlowSurface: speed is kept, the walls' grade adds speed, and the stick carves. Depth is limited so the rim
stays under ~41 degrees (parabola: `depth <= 0.44 * half-width`). opts: `taper`, `flat` (0..0.6: a flat floor that
wide), `shelf` (1.5 m lip each side), `guard` (true: a glass fence along the outer edges), `slices` (20), `gain`,
`cap`, `carve`.
Helpers: `surface_point(u, side)` (u 0..1 along, side -1..1 across, +1 = right rim), `centre_point(u)`,
`carve_points(swings = 3, reach = 0.55, per_swing = 4)`.
Route: `r_flow(pipe.carve_points(3, 0.55))`. No clips of its own.

### 8. `kit.launch_arc(foot, yaw_deg = 0, pitch_deg = 24, width = 6, length = 9, opts = {}) -> LaunchArc`
A ramp from `foot` (middle of its low edge, deck at feet height) climbing `pitch_deg` over `length` m to a lip
`length * sin(pitch)` higher (`arc.lip()`). It is a FlowSurface (gain 0) so a rider keeps all their speed up it. At the lip
the rider leaves with horizontal speed `hs = clamp(speed along the ramp, min_speed, cap)` (sideways drift halved) and
vertical speed `clamp(hs * tan(pitch) * lift, 3, 18)`: a pure function of `hs`, so
`arc.launch_velocity(hs)`, `arc.arc_points(hs, seconds)` and `arc.landing(hs, y)` place the landing deck and air rings
exactly (hold the stick forward in flight: the prediction is Ballistics' hold-forward model).
opts: `min_speed` (8), `cap` (30), `lift` (1). Helpers: `launched_within(s)`, `launches`.
Route: `r_launch(arc, landing)` after an `r_flow` ending on the ramp's centre line 10 m or more before the lip.
Clip: `flow_launch`.

### 9. `kit.rail(points, opts = {}) -> GrindRail`
A smooth Catmull-Rom path through `points` (world positions of the line the rider's feet follow, in the direction of
travel; an `Array[Vector3]` or `PackedVector3Array`), with a visible rail (metal tube, glowing stripe, end caps) and
optional support posts. **Snapping:** land on it or jump at it so your feet are within `snap` (1.2 m) horizontally of
the rail and from 0.5 m under to 1.4 m over it, not travelling against its direction, and you are carried along it at your
speed (at least `min_speed` 9, so a slow rider is taken up to it). **Riding:** faster downhill, slower uphill
(`slope_accel` 16 m/s^2 per unit of slope), 9 to 30 m/s; sparks fly; steering only leans you up to `lean` (0.3 m).
**Leaving:** jump to leave with the full tangent velocity plus a `hop` (6) upward; or reach the end and be thrown off
with the end tangent velocity plus `end_hop` (2). **Rail to rail:** another rail near the flight path catches you (the
rail you just left ignores you for 0.7 s). **Safety:** a respawn lets go at once; nothing kills; keep a deck or net
under it. opts: `snap`, `min_speed`, `max_speed`, `slope_accel`, `hop`, `end_hop`, `lean`, `post_to_y`, `post_every`.
Helpers: `length()`, `point_at(s)`, `tangent_at(s)`, `offset_of(world_point)`, `start_point()`, `end_point()`,
`speed_at(v0, s0, s1)`, `ride_time(v0, s0, s1)`, `jump_velocity(v0, s0, s)`, `exit_velocity(v0)`, `is_riding()`,
`carrying()`, `rider_offset()`, `release_rider()`, `released_within(s)`, `boarded_within(s)`.
Route: `r_rail(rail, board, {from, leave, to, chain, chain_next})`. Clips: `flow_rail_land`, `flow_rail_grind` (loop),
`flow_rail_leave`.

### 10. `kit.flow_chain() -> FlowChain`
The level's chain counter (made on first use; every ring and gate the kit builds shares it). `count` (current chain),
`best`, `total`; signals `passed(count, speed, source)` and `broken(final_count)`; `is_live()`, `time_left()`,
`reset_state()`. Consecutive passes less than `FlowChain.WINDOW` (1.5 s) apart build the chain; a respawn clears it.
The flow meter (workstream F3) reads it.

## Wiring a route

```gdscript
var gates := kit.boost_chain([Vector3(0, 0, -8), Vector3(0, 0, -18)], 20.0, 5.0, {"speed_end": 24.0})
var slope := kit.flow_slope_between(Vector3(0, 0, -38), Vector3(0, -9, -82), 10.0)
var arc := kit.launch_arc(Vector3(0, -9, -96), 0.0, 24.0, 6.0, 9.0)
var rings := kit.ring_line(ring_centres)                    # on arc.arc_points(hs)
var rail := kit.rail([Vector3(0, 3, -150), Vector3(0, 2, -170), Vector3(6, 0, -190)])

r_flow([Vector3(0, 0, -2), Vector3(0, 0, -8), Vector3(0, 0, -18), Vector3(0, -9, -82), Vector3(0, -9, -91)])
r_launch(arc, landing)
r_rail(rail, rail.start_point(), {"from": Vector3(0, 0, -146), "to": Vector3(6, 0, -196)})
```

## Tests

`timeout 1800 $G --headless --path . res://tests/run_tests.tscn -- --only=test_zfk_ --save=<branch>`

`test_zfk_ring`, `_gate`, `_slope`, `_flow_floor_keeps_speed`, `_launch`, `_rail`, `_pipe`, `_player_untouched` test each
piece alone; `test_zfk_bot_slice1` / `test_zfk_bot_slice2` play `tests/flow_course.gd` / `flow_course2.gd` with the route
bot (0 respawns, top speed and chain printed); `test_zfk_gallery` loads the playground with the Flow Gallery.

## Sound clips the kit calls

All positional, via `WorldAudio.at/loop`, unless noted.

| Clip | Description |
|---|---|
| `flow_ring_pass` | bright chime/whoosh as a ring is passed |
| `flow_ring_chain` | the same with a shimmer, for a chain of 4 or more |
| `flow_gate_pass` | a surge/whoosh through a boost gate |
| `flow_launch` | spring-release whoosh as a launch arc throws the rider |
| `flow_rail_land` | metallic clack as the rider locks on a rail |
| `flow_rail_grind` | loop: steady grinding/sizzling (the loop's pitch follows the speed) while a rider is on a rail |
| `flow_rail_leave` | short zing as the rider jumps off or reaches the end |
