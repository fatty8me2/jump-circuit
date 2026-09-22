# Jump Circuit - decisions and status

## Engine / stack
- Godot 4.7.1 stable, typed GDScript, Jolt Physics, Forward+.
- Physics 120 Hz fixed tick, physics interpolation on; camera and cosmetics run in `_process`.

## Measured controller envelope (tests/run_tests.gd, default_tuning.tres)
- Run speed 9.0 m/s, 90% speed in 0.13 s, brake distance 0.66 m.
- Full jump: 2.47 m high, 7.05 m long at a run, 0.78 s airtime. Tap jump: 1.12 m high, 3.6 m long.
- Pad 20 m/s vertical: apex 6.7 m. Pad 19 m/s at 40 deg: 11.4 m range on the level.
- Level rule: required jumps use <= 65% of reach (validator fails a level above 85%).

## Architecture
- `player/` controller (CharacterBody3D, explicit accel/gravity/impulses), visual, orbit camera, race ghost.
- `mechanics/` reusable pieces: BouncePad, MovingPlatform, RotatingPlatform, TiltPlatform (+TiltSurface), CollapsingPlatform, Checkpoint, FinishGate.
- `levels/level_base.gd` runtime (spawn, checkpoints, fail, respawn, reset, timer, race hooks); `level_kit.gd` builder; one script per level.
- Kinematic obstacles are pure functions of `Game.course_time` -> repeatable, no reset needed, identical for all racers.
- Tilt boards: real Jolt RigidBody3D (axis-locked, spring/damper, hard stop) receives rider weight/impact; a kinematic skin mirrors it so footing is stable.
- Bounce pads are flat and flush (run-on from any side); direction shown by chevrons, arc dots and a launch hoop.
- Multiplayer: ENet, client-simulated racers, ghost poses at 30 Hz, shared clock for obstacles, no racer collisions.

## Verification
- `tests/run_tests.tscn` headless: movement metrics, mechanics, level validation, RouteBot playthroughs, checkpoint/respawn/reset, save round trip.
- `tools/shot.tscn` renders screenshots for visual review.

## Later decisions
- Steep-board sliding is a downhill *drift velocity* the input steers against (0.45 m/s per degree past 11 deg);
  an acceleration-based slip was cancelled by ground braking.
- Floor identity comes from a short ray every grounded tick: move_and_slide only reports the floor on ticks
  it pushes into it, which made rider weight reach tilt boards intermittently.
- Fail rule: > 11 m below last footing with nothing beneath, or > 24 m below regardless (no watching long falls).
- Level validator measures the real gap (ray-scans the ground along each annotated jump), not route target points.
- Export templates are not installed on the dev machine: `tools/make_build.bat` makes a template-free native
  build (engine exe + PCK). `docs/BUILD.md` has the one-line official export for when templates exist.

## Known limits / remaining work
- No human hands-on playtest was possible from the build environment: feel was tuned through measured metrics,
  the RouteBot, and frame captures through the real camera. Expect to want small tuning passes after playing.
- RouteBot only covers each level main route; optional shortcuts are analysed/physics-probed, not bot-played.
- Level 1 is short (bot 19 s); a second garden loop would be a natural extension.
- Races have no late join or spectator camera; finished racers wait on the standings panel.

## Hard mode rebuild (owner feedback: "way way harder, more momentum, obby-style")
- Direction: Roblox-obby / Minecraft-parkour structure - 8-12 short brutal stages per level, a checkpoint per stage,
  instant respawn, HUD stage + fall counter, fewest-falls record next to best time.
- Momentum tuning: ground over-speed friction 9 -> 5, air over-speed drag 1.2 -> 0.6, hard cap 24 -> 34 m/s. Speed you earn survives
  landings and chains. Camera FOV widens with speed; a speed readout appears above 11 m/s.
- New deterministic toolkit (mechanics/): SurfacePlatform (boost strip / conveyor / ice), KillZone, Sweeper, Pendulum (hurls, does not kill),
  Bumper, WindZone, BlinkPlatform. Player reads surfaces through boost()/surface_velocity()/grip(); everything else acts through
  velocity/add_impulse, so the controller stays the single owner of movement.
- Measured: boost 20 m/s -> 15.5 m jump, still 17 m/s half a second after landing; 25 deg x 16 m ice slide -> 20 m/s; hammer throw ~23 m/s.
- Validator now allows 95% of reach and understands per-jump "speed"; bot may respawn up to 15 times per level (hard but completable).
- Rebuilt levels (bot main-route results): L1 9 stages 74 s / 0 respawns, hardest jump 92%; L2 11 stages 107 m climb 85 s / 2, 92%;
  L3 10 stages 69 s / 0, 90%; L4 11 stages 103 s / 0, 93%; L5 12 stages 100 m climb 87 s / 1, 93%. A clean human run is expected
  to take 3-6 min per level with many falls - that is the design.
- Repo: https://github.com/fatty8me2/jump-circuit (private).

## Polish pass (2026-09-22): bugs, feel, UX; no tuning, geometry or route changes
- Race clock: Game advances course_time one fixed tick at a time and steers it (EMA-filtered, <= 5% of a tick)
  toward the host's session clock. Sampling the wall clock per tick made obstacles lurch (a frame's physics
  ticks run back to back) and doubled or zeroed the velocity riders inherit in races.
- Restart before the first checkpoint (and pause > Restart) happens in place: clock, falls, checkpoints and splits
  reset, and clock-driven obstacles ("course_clock" group, snap_to_clock) take their t=0 pose at once. The solo clock
  is held at 0 until the level's first frame is drawn, so load hitches never land on the timer.
- Falls: one fall per tick however many kill zones report it; R while clearly falling counts as a fall.
- Saves: atomic write (.tmp swapped in, previous kept as .bak, damaged file kept as .corrupt), sanitized on load.
  SaveData.LAYOUT_REV versions each course: bests from an older layout move to legacy_best (in memory on load,
  on disk at the next save), so the pre-hard-mode times no longer show as unbeatable bests. Best-run splits are saved.
- Player: Player.knockback() for hammers/bumpers clears coyote/buffer (a buffered jump used to overwrite the throw);
  teleport keeps the body unrotated and clears floor state. Everything else added is cosmetic (respawn veil,
  checkpoint/finish celebrations, camera trauma on hits, footsteps, pad shockwave, fitted blob shadow).
- Menus work fully on keyboard or any gamepad slot (focus on every screen, A/B = accept/back, D-pad, right stick
  via look_* actions); F11 / Alt+Enter fullscreen; settings save however the panel closes.
- Test harness: any engine/script error during a test fails it (TestLib.ErrorTrap), per-test watchdog, --only/--level
  that select nothing exit 2. Tools and tests never write the real progress.json or open a real UPnP port. The engine binary and build/ are not in git (size).
