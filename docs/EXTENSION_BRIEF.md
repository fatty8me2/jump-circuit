# Level EXTENSION brief (read after docs/LEVEL_BRIEF.md and docs/HARD_MODE_BRIEF.md - this overrides them where they differ)

The owner's request (2026-09-23): **every level must last about twice as long, with new unique obstacles along
the way**, there must be **obstacles where you have to wall run and others where you have to mantle to get up**,
and **two brand-new levels with super unique environments** (Coral Depths = level 5, Orbital Drift = level 6;
The Final Ascent is now level 7 and stays the finale).

Project root (main checkout): `C:\Users\fatty\Desktop\PlatformerJumpPuzzle`. You work in your own git worktree.

## New player moves (player/player.gd, resources/movement_tuning.gd - already built and tested, do NOT edit)
Both only work on their own clearly marked surfaces, so every existing wall and ledge still plays as before.

**Wall run** - `kit.wallrun(center, Vector3(length, height, thickness), yaw)` -> `WallRunPanel`
(dark slab, glowing cyan run lines + chevrons; local X along the wall, turned by yaw; yaw 90 = runs along Z).
- Latch: be airborne (a jump) moving >= 4.5 m/s *along* the panel and come within ~0.4 m of its face.
  Approach at 10-35 degrees to the wall. Holding the stick into the wall is fine; pushing AWAY (>60 deg) drops you.
- Running: speed along the wall = max(arrival speed, 10 m/s). Vertical speed at latch is clamped to 3.5-5 m/s, then
  gravity 8 (not 30/42): you rise ~0.8-1.6 m, then sink slowly. Max 1.4 s per panel (~14 m at 10 m/s, more if you
  arrive boosted). Leaving the panel's end or its top/bottom ends the run (body probes at 0.2 / 0.65 / 1.1 m).
- Wall jump (jump while running, or within 0.15 s after running off the end): velocity = along-speed kept +
  7.5 m/s away from the wall + 11 m/s up (variable-height jump rules apply). ~2 m apex.
- You cannot re-latch the SAME panel before touching ground; a different panel is fine -> chimneys / zig-zags of
  alternating panels (wall jump across a 4-5 m gap to the facing panel) are legal and great.
- Panels are thin slabs: size them so the body stays alongside for the whole intended run
  (bottom <= latch height - 2.5, top >= latch height + 2.5 is safe).

**Mantle** - `kit.ledge(top, size, yaw, style)` -> `LedgeBlock` (gold lip round the top edge, grip rungs on the faces).
- Airborne and pushing toward a ledge face (or moving at it) with its top between 0.35 and 2.05 m above your feet
  -> you grab and climb onto the top in 0.34 s (you keep ~4 m/s forward on top). Needs 1.3 m of headroom there.
- A normal jump tops out at 2.47 m, so a ledge top **3.0-4.0 m above the approach floor REQUIRES a mantle**
  (4.2 m is the practical maximum from a running jump). Ledge tops are ordinary walkable ground.
- Combine: mantle out of a wall jump, mantle onto a moving platform's ledge, mantle under a crusher's rhythm...

Route annotations (levels/level_base.gd) and bot steps (tests/route_bot.gd) already exist:
```
r_wallrun(from, entry, exit, to, kick := true, chain := false)
    # run to `from`, jump at the panel toward `entry` (a point on/near its face, at chest height or so),
    # run along it toward `exit`, wall-jump there (kick=false: ride it off the end), steer to `to`.
    # chain=true: the previous r_wallrun kicked off toward THIS panel - latch mid-air (its `to` = this entry).
r_mantle(from, top)          # run to `from`, jump at the ledge, hold toward `top` until climbed
r_portal(entry, exit)        # run through a warp ring; `exit` = portal.exit_point()
r_until(callable)            # stand still until callable returns true (timing hazards)
```
The validator (test_m) only measures plain `jump` steps; the bot playthrough (test_n) proves the rest.

## New machines (mechanics/*.gd, all deterministic from Game.course_time)
| call | behaviour | bot helpers |
|---|---|---|
| `kit.laser(center, size, period, on_fraction, phase, yaw)` | kill beam between two posts; guide line flickers bright for 0.45 s before it fires | `is_on_at(t)`, `time_until_on(t)`, `time_until_off(t)` |
| `kit.piston(top, size, yaw, stroke, period, phase, strength)` | ram punches out along its arrow (local -Z by yaw) at u 0.45-0.55 of its cycle, holds, retracts; shoves a player caught in front (stroke speed + strength, +5 up); its top is rideable; housing built behind | `extension_at(t)` 0..1, `is_punching_at(t)` |
| `kit.crusher(floor_top, size, lift, period, phase)` | press hangs `lift` above the floor, shudders (red plate glows), slams, holds, rises; deadly underneath from the slam until it is ~20% back up; top rideable | `gap_at(t)`, `is_clear_for(t, window)` |
| `kit.portal(entry_floor, entry_yaw, exit_floor, exit_yaw, min_exit_speed)` | one-way warp ring pair (orange entry -> blue exit); you exit facing exit_yaw with your entry speed (>= min) and your upward speed; camera turns with you | `exit_point()` |
Plus everything in HARD_MODE_BRIEF (boost, slick, conveyor, hazard, sweeper, pendulum, bumper, wind, blink, pads, movers, spinners, tilt, collapse...).

## What each level agent delivers
**Extending an existing level (levels 1-4 and 7):**
1. Keep every existing stage as it is (it is tuned and bot-proven) - do not nerf or delete them. You may re-route the
   finish: the old final stage usually ends at the finish gate, so move the finish to the new end and turn the old finish
   area into a checkpoint.
2. **Roughly double the level**: add about as many new stages as it has now (e.g. 9 -> 17-19 stages), each ending on a
   checkpoint facing the next stage. Bot time should roughly double too.
3. The new half must feel NEW, not more of the same: in total across the new stages use
   - at least **2 wall-run obstacles** (e.g. a gap crossed only along a panel; a zig-zag / chimney of alternating panels
     with wall jumps; a wall run that ends in a mantle), and
   - at least **2 mantle obstacles** (3-4 m ledge walls; a mantle under a crusher's rhythm; a mantle out of a wall jump), and
   - at least **2 of** laser / piston / crusher / portal, and
   - at least **1 obstacle unique to your level's theme**, built by composing kit pieces in a new way or as a small new
     mechanic script YOU create (`mechanics/<level>_<name>.gd`, your own class_name) - e.g. a garden hedge-maze of lasers,
     a foundry slag-pour crusher line, a clockwork escapement you ride... Make it the new half's set piece.
   - and combine the new pieces with the level's existing identity (its pads/boards/timing/momentum) so it stays that level.
4. Difficulty: the new half continues the level's curve (start it at the level's current mid difficulty and build to a
   harder finale than before). Main-path jumps 75-92% of reach as before; shortcuts optional but welcome.
5. Update the level script's header comment (stage list, set pieces).

**Building a new level (5 Coral Depths / 6 Orbital Drift):**
1. Same length and density as an extended level: **17-20 stages**, each ending on a checkpoint. Difficulty sits between
   Clockwork Heights (4) and The Final Ascent (7): demanding hard-mode obby, not the brutal finale.
2. A **super unique environment** - it must not look like the sky-island levels. Do it all from your level script:
   in `_build()` find the `WorldEnvironment` / `DirectionalLight3D` that `Look.build_environment` added to the level and
   restyle them (fog, sky, glow, light), add particles (bubbles / marine snow; stars / dust), large custom scenery built
   from `Look` primitives (`Look.box/cylinder/sphere/flat`, `kit.block/pillar/...`), and your own set dressing.
   You own your theme's entry in `visual/look.gd` THEMES (only that dictionary entry) and your line in
   `autoload/game.gd` LEVELS (only name/blurb). Placeholders exist in `levels/level_5_reef.gd` / `level_6_orbital.gd`.
3. Mechanics: use the new moves and machines heavily (both must feature >= 3 wall-run and >= 3 mantle obstacles and
   all four machines), invent 2+ environment-specific obstacles (own mechanic scripts allowed, see above), and still
   use the classic kit (pads, boosts, blinks, movers...) so it plays like Jump Circuit.
   Ideas - REEF: current streams (horizontal `kit.wind`), bubble-column updrafts, jellyfish bounce pads, eel sweepers,
   clam crushers, a sunken ship whose hull you wall-run and whose decks you mantle, coral portals, anemone bumpers.
   ORBITAL: low-gravity bays (upward `kit.wind` weaker than gravity = floaty long jumps), airlock lasers, hydraulic
   pistons and presses, teleporter pads (portals), a rotating habitat ring (spinner / orbiter), solar-panel wall runs,
   cargo-container mantles, a planet filling the sky, starfield.
4. Music: reef uses track "a", orbital "b" (already set).

## Routes, branches and shortcuts (owner: "add more shortcuts, stages, and different routes to take")
- **Branching routes:** at least **3 stages per level** (new half or old half) must split into two genuinely different
  routes that rejoin at that stage's end checkpoint - e.g. a safe-but-long path of big landings vs. a fast risky line
  of wall runs; a timing route through the lasers vs. a climbing route over them via mantles; a portal skip vs. the
  full gauntlet. Both routes must be fun and fair, visibly offered at the split (the player sees both options from the
  fork), and roughly comparable in time (risk buys a few seconds, not half the stage). Signpost them with lamps / glow
  strips / banners.
- **Checkpoints stay linear:** a checkpoint must be reachable by every route (put them only where branches have rejoined).
  Checkpoints are numbered in creation order and only count upward.
- **Every route is bot-proven:** set `route_variants = N` in `_configure()` and annotate each split with
  `if route_variant == 0: <main branch steps> else: <alternative steps>` (for more than 2 routes use 0,1,2...; a single
  variant index may choose the alternative at several splits at once). Test each with
  `-- --only=test_n --level=<i> --route=all` (plays every variant; all must pass).
- **More shortcuts:** at least **4 optional shortcuts per level** in total (existing ones count only if they still work;
  add new ones to old stages too where they fit, as additive geometry that never changes the main line): 90%+ jumps,
  1 m landings, wall-run skips, a hidden portal, a hammer or piston ride, a mantle up a tall wall that skips a climb.
  Shortcuts do not need bot annotations, but must be possible (probe them) and must not make a stage's main challenge
  skippable for free - a shortcut costs risk or skill.

## Particle effects (owner: "put a heavy emphasis on cool particle effects")
Every level must be visibly alive with particles - this is a priority, not garnish:
- **Ambient:** at least 2 layered ambient systems suited to the theme across the course (pollen and petals, embers and
  sparks, sea spray / bubbles and marine snow, starfield dust and ion motes, drifting neon glints...), placed around the
  route (never blocking a landing or a hazard), local_coords / visibility AABBs set so they are not culled wrongly.
- **Set pieces:** your unique obstacle and each new stage's centrepiece get their own effects (steam jets, slag
  splashes, gear sparks, energy arcs, falling leaves when a hedge is clipped, waterfalls of light...).
- **Feedback moments:** where your level has its own events (a stage-ending gate, the finish, a portal arrival zone,
  a crusher line), add bursts that fire on the course clock or on proximity.
- A separate effects pass is adding particles to the shared new mechanics (wall-run panels, ledges, lasers, pistons,
  crushers, portals) and the player's moves - do NOT edit those files; build your own effects in your level script or
  your own `mechanics/<level>_*.gd` / `visual/<level>_*.gd` files (look at player/player_visual.gd `_make_burst` /
  `_make_trail` and mechanics/wind_zone.gd for this project's GPUParticles3D style).
- Performance: stay tasteful - total particle amount on screen in the low thousands, prefer many small emitters with
  modest `amount` over giant ones, unshaded billboard quads with soft textures (see `Look` / `LevelKit._soft_dot`).
- Headless runs never compile particle shaders: take your windowed screenshots and grep their output for
  `ERROR` / `SHADER` lines, and fix any.

## Rules
- You own ONLY: your level script + .tscn, new `mechanics/<level>_*.gd` files you create, and (new levels only) your
  THEMES entry and LEVELS line. Do NOT edit player/, resources/, autoload/ (except that line), level_base.gd,
  level_kit.gd, the existing mechanics/, look.gd outside your entry, run_tests.gd. Report problems instead.
- `tests/route_bot.gd`: prefer the existing step kinds. If you truly need a new one, add it ADDITIVELY: one new
  `"<prefix>_...":` line in the big match and one new function at the very end of the file (prefix = your level id).
- Heredocs in the shell truncate files at apostrophes - use the Write/Edit tools for file content.
- Place pad/boost/wall-run/mantle landings by measuring (Ballistics or a scratch probe scene under tests/scratch/,
  deleted afterwards), never by eye.

## Verify (must pass before you finish)
Your worktree has no engine binary (gitignored); use the main checkout's, with --path pointing at YOUR worktree:
```
G=/c/Users/fatty/Desktop/PlatformerJumpPuzzle/tools/Godot_v4.7.1-stable_win64.exe
W=<your worktree root>
timeout 600 $G --headless --path $W --import                      # once first, and after adding files
timeout 900 $G --headless --path $W res://tests/run_tests.tscn -- --only=test_m --level=<i>
timeout 3000 $G --headless --path $W res://tests/run_tests.tscn -- --only=test_n --level=<i> --route=all
```
Level indices (0-based): 0 gardens, 1 foundry, 2 balance, 3 clockwork, 4 reef, 5 orbital, 6 ascent.
Always wrap runs in `timeout` (a parse error makes Godot hang forever). Target: test_m hardest jump <= 95%,
test_n bot finishes EVERY route variant with <= 30 respawns each (fewer is better; if the precise bot needs many tries the stage is hard enough).
If the bot cannot pass a stage after honest effort on the bot side, soften that stage - completability wins.
Godot's --import rewrites tracked *.import files with CRLF-only changes: discard those, never commit them.

Screenshots (opens a window briefly; do NOT run tools/bot_shots.tscn or the game itself - they can touch the owner's
real save file):
```
timeout 120 $G --path $W res://tools/shot.tscn -- --level=<i> --cam=x,y,z --look=x,y,z --out=<abs path>.png [--player=x,y,z] [--time=<s>]
```
The output directory must already exist. Take at least 6 shots across the new content (plus the start view for new
levels), look at them with the Read tool, and fix anything ugly, unreadable or hidden.

## When done
Commit your work on your worktree branch (git add your files only; no .import churn), message ending with
`Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Do not push, do not merge.
Final report: stage-by-stage list of the NEW stages (what each demands), where the wall runs / mantles / machines /
unique obstacle are, bot result (time, respawns), hardest-jump %, anything in shared code that misbehaved, and the
branch name + commit hash.
