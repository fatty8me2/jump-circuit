# HANDOFF - 2026-09-24 (session 3): sound update, updater fix, relay resume, four new worlds

Read this first when picking the work up (new session, other account, or after a usage-limit pause).

## Done and shipped
- **v1.3.0 "The Sound Update"** (on `main`, released). Every map has its own two-layer score, built on
  one leitmotif; there are soundscapes, world and mechanic sounds, fanfares, checkpoint chimes, a pause
  muffle and an Ambience slider. See `docs/AUDIO.md` (it maps every generator:
  `tools/gen_music.py` + `music_engine.py`, `gen_ambience.py`, `gen_world_sfx.py`).
  The generators need `pip install soundfile`. Listening page for the owner:
  https://claude.ai/artifact/SYQ1cmPxYRgetQ91PGZv6d
- **v1.3.1** (on `main`, released). The in-game updater never restarted the game. Its PowerShell
  arguments were quoted twice, so the path with the space in `...\app_userdata\Jump Circuit\updates`
  was split. The fix: plain arguments, a "started" marker handshake (the game only quits once the
  installer is running), stale downloads cleaned up at launch, and `test_x_update_installer_runs`,
  which runs the real installer on spaced paths. Clients on 1.2.2 / 1.3.0 must install 1.3.1 **once by
  hand**; the release notes say so.

## In flight (not merged)
### 1. Relay resume - branch `fix/relay-resume` (commit e61ef77), ready, needs deploy + release
Owner report: "relay connection closed" kicks people **mid-race** while the lobby sometimes survives.
The fix, all tested:
- **Relay (`relay/src/index.js`):** session tokens, a grace period on unclean drops (20 s racer, 30 s
  host), `role=rejoin`, and `peer_away/peer_back/host_away/host_back` messages. A Durable Object alarm
  expires lost slots, and a reconcile step covers Cloudflare restarting the room.
- **Game (`autoload/net.gd`):** auto-reconnect into the same slot, dead-link detection (45 s silent),
  HUD / lobby notices, `[relay]` lines in the log, and poses at 15 Hz with a 1 s idle heartbeat
  (much lower relay request volume).
- **Verified against `wrangler dev`:** a joiner drop and a host drop both reconnect in about 0.2 s,
  grace expiry works for racers and for the host, and a clean leave is immediate. The
  `test_zp_relay_resume` headless test passes (10/10 in the `test_zp_relay` group).
- **Remaining:**
  - (a) Owner's OK, then `npx wrangler deploy` in `relay/` (wrangler is logged in on this PC).
    Older game builds keep working against the new relay.
  - (b) Full suite.
  - (c) Merge to main, bump to 1.3.2, release (see the release steps below).
- The deployed relay URL is `wss://jump-circuit-relay.jumpcircuit.workers.dev`.

### 2. Four new worlds - branch `new-worlds` + one branch per level (agents were mid-build)
Owner asked: "2 more unique maps" (an alien planet, a volcano with a cool eruption in the background),
then "level 9 and 10 with 2 different unique untouched themes". **The spec is
`docs/NEW_WORLDS_BRIEF.md`.**
New order (0-based index): 6 Xeno Wilds (`xeno`), 7 Cinder Peak (`volcano`), 8 Frostbite Pass
(`glacier`), 9 Scarab Sands (`desert`), 10 The Final Ascent (now `levels/level_11_ascent.*`, still the finale).
- **`new-worlds` (6f5331f):** groundwork (placeholders, level list, themes, save revisions, scrolling
  level select) plus **all four scores** with fanfares and chimes (done).
- **`new-worlds-sound` (cf569ed):** soundscapes, footsteps, landings and every mechanic clip for all
  four themes (done, tested). Merge it into `new-worlds`.
- **Level branches.** Each has a worktree under `.claude/worktrees/agent-<id>`. WIP was committed when
  the usage limit hit, then the agents were resumed:

| branch | worktree id | WIP commit | notes at pause |
|---|---|---|---|
| `xeno-wilds` | ae2389d71321c07d4 | 10c3e87 | ~3.7k lines in; was cleaning up stray Godot processes |
| `cinder-peak` | a8e792763a338343c | d5f8070 | all 3 route variants passed; was tightening easy stages + the stage-17 shortcut |
| `frostbite-pass` | aba14c12c60e8960a | c7f6629 | ~3.3k lines in; early testing |
| `scarab-sands` | a01896e0e7e926de6 | 2e1ca2b | ~4.1k lines in; was editing its Game.LEVELS line |

  If an agent is gone, start a new one in that worktree with this prompt: "read
  docs/NEW_WORLDS_BRIEF.md and your level script, verify what exists (`--import`, `test_m`,
  `test_n --level=<i> --route=all`), then finish the remaining scope". Each branch's `git log`
  shows its latest commit.
- **To finish:**
  1. Merge the four level branches and `new-worlds-sound` into `new-worlds`. Expect small conflicts in
     `autoload/game.gd` LEVELS lines, `tests/route_bot.gd` (additive step kinds: keep all),
     `tests/run_tests.gd` and `visual/ambience.gd` (one `match` case per theme: keep all).
  2. `--import`, then run the full suite.
  3. **Ask the owner for a time they are away**, then do the windowed screenshot pass. Each agent's
     report lists the shots it wants (the owner does not want pop-up windows while playing; see
     memory). Fix anything ugly.
  4. Merge to main and release.

## Release steps (quick form; full: docs/BUILD.md)
1. Bump `config/version` in `project.godot`.
2. `--import`, then `--export-pack "Windows Desktop" <scratch>/pkg/JumpCircuit.pck`, into a scratch
   folder, **not** `build/`: the owner plays from `Desktop\jumpCircuit\`, and `build/` may be in use.
3. Copy the editor exe as `JumpCircuit.exe` and `docs/LICENSES.md` in, zip all three as
   `JumpCircuit-vX.Y.Z.zip`.
4. `gh release create vX.Y.Z <zip> --target main --title "Jump Circuit X.Y.Z" --notes-file notes.txt`,
   with plain-text notes of **600 characters or fewer** (the in-game prompt truncates there).
5. The owner's own copy lives in `C:\Users\fatty\Desktop\jumpCircuit\`. 1.3.1 was installed there by
   hand on 2026-09-24, after asking. From 1.3.1 on, its in-game updater works, so later releases reach
   it through the update prompt.

## Gotchas learned this session
- `OS.create_process` quotes arguments containing spaces itself: never pre-quote.
- Ogg re-renders change bytes (a random stream serial) even when the audio is identical:
  `git checkout` untouched `.ogg` files after partial regenerations.
- Shell heredocs mangle apostrophes and backslash escapes: write patch scripts with the Write tool.
- A test that emits `Net.left_session` must detach the game's handler (it changes scene and frees
  the test runner).
- Another `workerd` may already hold port 8787: run the local relay on 8799.

---

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
- RouteBot: a landing (or a stale fall speed) no longer counts as a kick; a bounce handed to the next step lasts only
  that step. (w_run still steers straight at `entry`: an "aim ahead along entry->exit" change broke Orbital Drift's
  boosted run and was reverted - place entries well ahead of fast takeoffs.)
- Exit noise: everything quits through Sfx.quit() (stops sounds first), which removed most "leaked instances /
  resources still in use" warnings at exit, but some test groups still print them (harmless, exit-time only).
- Not bugs, still open: Orbital Drift is on the easy side (0 bot respawns) - tighten after playtesting; the party relay
  path is covered by a message-level test only (no live relay in CI); a few old shortcuts were not re-probed.

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
