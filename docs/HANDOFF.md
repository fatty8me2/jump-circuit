# HANDOFF - big expansion (resumed and merged 2026-09-23, session 2)

**Status: all nine workstreams finished and merged into `extend-levels`, then into `main`.** The sections below are
the original pause notes, kept for history. What session 2 added on top:
- Every WIP branch finished against its brief and merged: levels 1-4 and 7 roughly doubled (18 / 22 / 20 / 20 / 23
  stages), new levels 5 Coral Depths (17) and 6 Orbital Drift (18), party mode (14 power-ups, teams, cup scoring,
  online over the existing relay - no redeploy), the shared effects pass.
- Spectating: after finishing a race you can watch the racers still running (results "Spectate", LB/RB or Q/E,
  B/Esc back); party races offer it from the waiting bar.
- Wall-run fix: latching needs the panel beside the body (no more leading-edge latch that burned the panel).
- Crusher yaw: `kit.crusher(..., yaw_deg)` turns the press, its kill zone and its guide frame. Existing calls are
  unchanged (yaw 0); Orbital Drift and Balance Works still use their own workarounds, which is fine.
- RouteBot resumes after the checkpoint the level respawns at (a checkpoint touched mid-step no longer sends every
  retry back to the previous stage's steps).
- Known shared-code follow-ups reported by the level agents (not done): the `kick` step
  treats a hard landing as a kick; after a pad bounce the bot's bounce flag stays set. Orbital Drift is on the easy
  side (0 bot respawns) - tighten after playtesting.

Read this first if you are picking this work up (new session / other account).

## What the owner asked for (all still wanted)
1. Double the length of every level, with new unique obstacles along the way.
2. Obstacles that need a **wall run**, and others that need a **mantle** to get up.
3. **Two new levels** with super unique environments: 5 Coral Depths (`reef`, underwater) and 6 Orbital Drift
   (`orbital`, space station). The Final Ascent is now level 7 (`levels/level_7_ascent.gd`) and stays the finale.
4. **More shortcuts, stages and different routes** (branching routes).
5. A **party game mode** (less competitive, griefing, crazy power-ups incl. Nine-Tailed Fox, Link's tunic
   nod "Hero's Tunic", super-saiyan nod "Golden Surge Hair"), **2v2 team races with scoring** - party mode only,
   never in the main mode.
6. **Heavy emphasis on cool particle effects.**
7. **Update prompt**: the game tells players when a newer GitHub release exists (DONE).
8. Finally: **commit everything and push it to GitHub** (`fatty8me2/jump-circuit`).

## State of the branches
- `main` - local main was fast-forwarded to `polish-pass` (owner said "merge polish pass"). Not pushed yet at pause time
  (check `git log origin/main..main`).
- `extend-levels` (branched from main) - FINISHED foundation, tested:
  - 973dd6a: player wall run (WallRunPanel only) + mantle (LedgeBlock only), LaserGate / Piston / Crusher /
    WarpPortal machines + kit calls, r_wallrun / r_mantle / r_portal / r_until route helpers + RouteBot steps,
    route variants (`route_variants`, `LevelBase.route_variant`, run_tests `--route=N|all`), party movement hooks
    (`Player.speed_mult/jump_mult/gravity_mult`, all 1.0 in the main mode), reef/orbital themes + placeholder
    levels, LAYOUT_REV bumped, autoload/updater.gd (GitHub release check, tags `vX.Y.Z` vs
    `application/config/version` = 1.1.0) + title "update" screen, docs/BUILD.md release steps.
  - c307250: the specs the agents work from - **docs/EXTENSION_BRIEF.md** (levels), **docs/PARTY_BRIEF.md**,
    **docs/VFX_BRIEF.md**. They are the source of truth for what "done" means.
  - Full suite was green on this foundation (299+ checks; the only failures were artifacts of editing mid-run,
    re-run green). Bot times on the 5 old levels unchanged (73.8 / 84.6 / 68.6 / 103.0 / 86.6 s).
- Nine WIP branches, each ONE commit on top of c307250, work in progress, **not yet verified** (may not even parse -
  run `--import` and test_m first). Each worktree lives at `.claude/worktrees/agent-<id>` (local machine only):

| branch | commit | scope | where it stopped |
|---|---|---|---|
| `wip/gardens` | 5adea7c | L1 Launch Gardens extension (+ mechanics/gardens_trimmer.gd, visual/gardens_*.gd) | was appending the helpers + nine new stages to the end of level_1_gardens.gd |
| `wip/foundry` | efaf4f7 | L2 Bounce Foundry (+ mechanics/foundry_ladle.gd, visual/foundry_fx.gd) | new stages written up to S18; was fixing an S18 timing phase so the bot's wait can be satisfied |
| `wip/balance` | 6d88fc0 | L3 Balance Works (+ 5 balance_* mechanics, visual/balance_fx.gd) | was writing new-half frame helpers and stages 11-14 |
| `wip/clockwork` | c20a14f | L4 Clockwork Heights (+ clockwork_escapement, clockwork_fx) | converting the old finish into a checkpoint, starting new stages 12-14 |
| `wip/ascent` | 8ae911f | L7 Final Ascent (+ ascent_billboard, ascent_data_stream, route_bot edits) | wall-run chimney stage done and working (3 wall runs then a mantle); next was stage 17, a crusher row with a portal-skip branch |
| `wip/reef` | abeaa05 | L5 Coral Depths new level (reef_* mechanics, shaders, fx, decor) | stages 1-6 passed the bot with 0 respawns; next: fix stage 3 takeoff spots, stage 6 alternate route, stages 7-12, then to 17-20 |
| `wip/orbital` | 7f78f8f | L6 Orbital Drift new level (orbital_* mechanics, sky, fx) | stages written; was wiring the stages into _build and checking parse |
| `party-mode` | 6b740ed | Party mode (party/ framework, 15 power-up scripts in party/powerups/, item boxes, dummies, projectiles, party HUD/results UI, net.gd + relay changes, tests) | large WIP; power-ups exist as scripts (fox, tunic, surge, balloon, glove, gravity_bomb, ice, jetpack, magnet, shrink, slick, swap, thunder, tornado); network test + polish not verified |
| `wip/vfx` | 8767515 | Effects pass (visual/fx.gd, heat_haze shader, particles in 17 mechanics + player_visual/player.gd connect_feedback) | effects written; was building a scratch showcase scene to screenshot them |

## How to resume
1. `git fetch` (all branches are pushed to origin), check out each WIP branch in its own worktree
   (`git worktree add ../jc-<name> <branch>`), and continue it against its brief, one agent per branch in parallel.
   Tell each: read docs/HANDOFF.md + its brief, verify what exists first (`--import`, test_m, test_n
   `--route=all` for its level index), then finish the remaining scope. Level indices (0-based): 0 gardens,
   1 foundry, 2 balance, 3 clockwork, 4 reef, 5 orbital, 6 ascent.
2. When branches are done, merge them into `extend-levels` one by one. Expected conflicts: `tests/route_bot.gd` (several
   branches append step kinds at the end of the file and add match lines - keep all), `tests/run_tests.gd` (party
   appends tests), `player/player.gd` (party hooks vs VFX `connect_feedback`), `mechanics/*` (VFX visual edits only),
   `visual/look.gd` (reef + orbital entries only). Re-run `--import` after merging.
3. Full suite: `tools/Godot_v4.7.1-stable_win64.exe --headless --path . res://tests/run_tests.tscn -- --route=all`
   (long: 7 levels x all route variants). Also windowed screenshots of each level for particle shader errors.
4. Merge `extend-levels` into `main`, then push `main` (owner asked for everything on GitHub). Optionally publish
   release `v1.1.0` (see docs/BUILD.md) - the first release whose tag triggers the in-game update prompt.

## Gotchas
- Engine binary `tools/Godot_v4.7.1-stable_win64.exe` is gitignored (download from godotengine.org if missing).
  Worktrees need `--import` with that binary and `--path <worktree>`.
- A GDScript parse error makes Godot hang forever: always wrap runs in `timeout`.
- `--import` rewrites tracked `*.import` files with CRLF-only changes - discard them, never commit.
- All Godot processes share `%APPDATA%\Godot\app_userdata\Jump Circuit\`; running the game or tools/bot_shots can write
  the owner's REAL progress.json. Tests use test_progress.json.
- Headless never compiles particle shaders: verify effects with windowed `tools/shot.tscn` and grep for ERROR/SHADER.
- Owner plays with a gamepad: every new menu must be fully pad-navigable (initial focus, B back).
- Power-up display names are nods, not trademarks (public repo) - kept in one table (party/party_names.gd).
