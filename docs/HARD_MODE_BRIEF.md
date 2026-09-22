# HARD MODE rebuild brief (read after docs/LEVEL_BRIEF.md - this file overrides it where they differ)

The owner's verdict on the first version: far too easy. Target now: **a Roblox obby / Minecraft parkour map** -
long, dense, *very* difficult, physics- and momentum-driven, and addictive ("one more try").
Project root is now `C:\Users\fatty\Desktop\PlatformerJumpPuzzle` (engine binary in `tools/`).

## What "hard and addictive" means here
- **Dense stages, Roblox style.** A level is 8-12 short STAGES, each ending on a checkpoint (the HUD shows `Stage n / N` and a fall counter).
  A stage is 10-25 s of committed, precise play. Dying costs only that stage, respawn is instant - so stages can and should be brutal.
- **Precision parkour:** small blocks (main path landings 1.4-2.2 m across; 1.0-1.2 m on shortcuts), jumps at 80-92% of reach,
  diagonal and rising jumps, chains of 5-10 jumps with no rest, narrow beams (0.7-1.0 m wide), low ceilings ("head hitters") that force tap jumps,
  ladders of blocks that rise 1.8-2.2 m per step, moving/blinking/collapsing blocks inside those chains, kill bricks wrapped around the safe line.
- **Momentum is the star.** Every level needs at least FOUR momentum set-ups where speed you build is the key to the jump:
  boost strip -> 12-15 m leap; ice slide -> launch off the lip; bounce pad hit at sprint (vertical pads KEEP horizontal speed);
  fast mover / spinner rim whose velocity you inherit on takeoff; bumper ricochets; hammers that hurl you (sometimes ON PURPOSE as the route);
  tail-wind tunnels; conveyors you must outrun or use. Chain them: boost -> jump -> pad -> ice landing -> jump.
- **Readable and fair.** Everything is deterministic (course clock), hazards are bright red, the next landing is visible from the takeoff,
  no blind leaps of faith, no required wait > 3 s, no RNG. Difficulty = execution, never guessing.
- **Difficulty curve across the game:** L1 = already demanding (think "Easy obby that is not actually easy"), L2-L4 escalate, L5 = brutal finale.
  Inside a level: stage 1-2 teach the level's pieces at modest stakes, the rest escalate and combine.
- Length: a skilled human should need 3-6 minutes clean; the bot typically 60-150 s.

## New toolkit (all tested; see mechanics/*.gd and the bottom of levels/level_kit.gd)
| call | behaviour |
|---|---|
| `kit.boost(top, size, yaw, speed)` | strip accelerating along its arrow (local -Z turned by yaw) at 45 m/s^2 up to `speed` (typ. 16-26). 20 m/s -> full jump flies **15.5 m**. Over-speed bleeds slowly (17 m/s still there 0.5 s after landing) so speed can be carried through a chain. |
| `kit.slick(top, size, yaw, pitch)` | ice: ~no traction. Pitched = slide that accelerates you (25 deg x 16 m -> 20 m/s at the lip). `top` is the centre of the sloped surface; positive pitch rises toward the arrow, negative descends. |
| `kit.conveyor(top, size, yaw, speed)` | belt dragging at `speed` (player runs 9 m/s: 5-7 against you is a fight, with you is a launch aid). |
| `kit.hazard(center, size, yaw, parent)` | kill brick (CENTRE position). Parent it to a mover/spinner for moving hazards. |
| `kit.sweeper(floor_top, arm_length, bars, period, phase, bar_height)` | rotating kill bars to jump over (bar_height 0.45) - classic obby spinner. `angle_at(t)`. |
| `kit.pendulum(pivot, length, period, phase, yaw, swing_deg)` | swinging hammer; does not kill, it HURLS the player along the swing (head speed + 9 m/s, +7 up). Swings along X turned by yaw. |
| `kit.bumper(floor_top, strength, lift, radius)` | pinball post: throws you directly away at `strength` m/s with `lift` up. |
| `kit.wind(center, size, push_accel, max_rise)` | air current (acceleration; gravity is 30 up / 42 down, so updrafts need ~60-80). |
| `kit.blink(top, size, period, on_fraction, phase)` | platform that exists only part of each cycle; `is_on_at(t)`. |
Existing: `plat, disc, ramp, block, pad, mover, orbiter, spinner, tilt, collapse, checkpoint, finish` + decor. Hard speed cap is now 34 m/s.
Tuning changed: air over-speed drag 0.6, ground over-speed friction 5 -> pads and boosts fly a bit further than before. ALWAYS place pad/boost
landings with `Ballistics` or by probing with the real player in a scratch scene (tests/scratch/, delete afterwards), never by eye.

## Measured capabilities (unchanged base)
Run 9 m/s - full jump 2.47 m high / 7.05 m long - tap 1.12 m / 3.6 m - rising 1.5 m: ~5.9 m - boosted 20 m/s: 15.5 m.
Capsule radius 0.38, braking distance 0.66 m from a sprint (so a 1.5 m block is landable but demands a controlled arrival).

## Rules for the rebuild
1. You own only your level script (+ .tscn). Rebuild it substantially: keep the theme, identity and best set piece, but the result must be
   2-3x longer and *dramatically* harder. Delete easy filler. Do not edit shared code (report problems instead).
   `tests/route_bot.gd`: additive edits only, and re-run `--level=0` afterwards if you touch it... other agents edit it too, so re-read before editing.
2. 8-12 checkpoints, each on static safe ground, facing the next stage.
3. Annotate the full main route for the RouteBot. For a jump that relies on built-up speed add the speed to the step so the validator
   knows: `route[route.size() - 1]["speed"] = 20.0`. Validator limit is now 95% of reach; aim for the main path to sit at 75-92%.
   For timing hazards (sweepers, hammers, blinks) give the bot wait steps (see the `x_wait`/`x_jump` step kinds the clockwork level added,
   or add a small new step kind that waits on `angle_at` / `is_on_at`).
4. The bot must finish: `--only=test_n --level=<i>` passing with <= 15 respawns (it is a precise bot; if IT needs several tries the stage is hard enough).
   Also `--only=test_m --level=<i>`. If the bot cannot pass a stage after honest effort on the bot side, soften that stage slightly - completability wins.
5. Optional shortcuts that are even nastier (95%+ jumps, 1 m landings, hammer rides) - at least two per level.
6. Visuals: keep it dressed and atmospheric; hazards must never be hidden by decor; keep landings visible from takeoffs.
   Take screenshots / a bot capture (`tools/bot_shots.tscn`) and look at them.
7. Heredocs in the shell truncate files if the text contains an apostrophe - use the Write/Edit tools for file content.

## Final report
Stage-by-stage list (what each stage demands), the momentum set-ups, shortcuts, bot result (time, respawns per stage if known),
hardest-jump %, and any shared-code problems.
