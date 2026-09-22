# Level author brief (Jump Circuit)

Godot 4.7.1, typed GDScript. Engine binary: `tools/Godot_v4.7.1-stable_win64.exe` (run from the project root).
**Read first:** `levels/level_kit.gd` (builder API), `levels/level_1_gardens.gd` (the exemplar),
`levels/level_base.gd` (runtime + `r_*` route helpers), `tests/route_bot.gd`, `visual/look.gd` (themes), `docs/DECISIONS.md`.

## Ownership rules
- You own ONLY your level script + its `.tscn` (copy `levels/level_1_gardens.tscn`, change the script path).
- Do NOT edit player/, mechanics/, resources/, autoload/, level_base.gd, level_kit.gd, look.gd, run_tests.gd.
  If something there blocks you, work around it in your level and report it in your final message.
- `tests/route_bot.gd`: additive edits only (a new step kind / small robustness fix), keep existing behaviour.
- In shell heredocs never use apostrophes (the tool truncates files). Prefer the Write/Edit tools.

## Coordinates and conventions
- Gameplay pieces take the position of the centre of their TOP surface. Player travels roughly toward -Z but use all three axes.
- `set_spawn(pos, yaw_deg)`; yaw 0 faces -Z. Checkpoints respawn facing the checkpoint node's -Z (pass yaw_deg so the player faces the next challenge).
- Pads are flat, run-on from any side. `kit.pad(top, strength, pitch_deg, yaw_deg, radius)`: pitch 0 = vertical pad (sets vertical speed, KEEPS horizontal momentum);
  pitch > 0 = angled pad (REPLACES velocity: `strength` m/s along local -Z rotated by yaw, tilted `pitch` from vertical). yaw +90 aims toward -X, yaw -90 toward +X.
- Use `Ballistics.landing_point(tuning, pad.launch_origin(), pad.get_launch()["velocity"], target_y)` in a scratch script if you need exact pad landings.
- Movers/spinners are pure functions of `Game.course_time` (deterministic). Keep cycles short (<= 6 s) so nobody waits long.
- `kit.tilt(top, size, {opts})` opts are TiltPlatform exports: tilt_about_x, tilt_about_z, edge_tilt_deg, max_tilt_deg, sink_depth, support ("fulcrum"/"cables"), is_round. Boards slide the player when tilted beyond ~11 degrees.
- `kit.collapse(top, diameter, delay, respawn)`.

## Measured player capabilities (design inside these!)
- Run 9 m/s. Full jump 2.47 m high, 7.05 m long (flat, at a run). Tap jump 1.12 m high / 3.6 m long.
- MAIN PATH: flat gaps <= 4.5 m, step-ups <= 1.6 m (with gap <= 3.5 m when stepping up), landing areas >= 3 m across (pads/discs radius >= 1.2).
- OPTIONAL SHORTCUTS may use up to ~90% of reach and small landings. Every level needs at least one.
- Vertical pad apex above pad = strength^2 / 60 (e.g. 17 -> 4.8 m, 20 -> 6.7 m, 24 -> 9.6 m). Rise time = strength / 30 s. Horizontal travel during a bounce is ~9 m/s * airtime at most.
- Fall-out rule: the player is respawned after dropping ~11 m below their last footing with nothing solid beneath. Avoid required drops > 9 m.

## Requirements for every level
1. Obvious start, visible destination (finish gate readable from early on if possible), 3-5 checkpoints placed BEFORE each major challenge on safe ground, satisfying finish.
2. Introduce a mechanic safely (low stakes, near ground/safety net), then escalate, then combine with earlier mechanics.
3. A memorable set piece unique to the level.
4. Annotate the main route with `r_jump / r_pad / r_walk / r_wait / r_jump_onto / r_jump_from_ride / r_checkpoint` so the RouteBot can play it. Put `r_checkpoint()` right after the step that lands on a checkpoint.
5. Dress it: decor from the kit (pillars, lamps, arches, banners, gears, chimneys, pipes, glow strips, rings, clouds, monolith ring) composed around (never on) the route. No bare floating debug boxes. Decor must not block the camera on the main path or hide landings.
6. 60-120 s for a first-time human; the bot usually takes 25-60 s.

## Verify (must do, iterate until green)
```
G=tools/Godot_v4.7.1-stable_win64.exe
$G --headless --path . --import            # after adding new files
$G --headless --path . res://tests/run_tests.tscn -- --only=test_m --level=<index>   # validation (index is 0-based)
$G --headless --path . res://tests/run_tests.tscn -- --only=test_n --level=<index>   # bot playthrough with real physics
```
Target: bot finishes with 0-1 respawns, hardest required jump <= 70% of reach.
Screenshots (opens a window briefly; look at the PNG with the Read tool and fix what looks wrong):
```
$G --path . res://tools/shot.tscn -- --level=<index> --cam=x,y,z --look=x,y,z --out=<abs path>.png [--player=x,y,z] [--time=<course seconds>]
```
Take at least 4 shots (start view, two mid-course, finish) and fix readability/ugliness issues you see.

## Final report
List: layout summary, checkpoints, set piece, shortcut(s), bot result (time/respawns), anything in shared code that misbehaved.
