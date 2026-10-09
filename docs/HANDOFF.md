# HANDOFF - 2026-10-09 (session 6): v2.0.0 big update

Read this first. The big update is built and merged on the `big-update` branch (HEAD 21432a7 when this
section was written). It is **not released**: v2.0.0 waits for the owner's OK, and the owner has not yet
seen anything visual from it in a real window.

## What shipped on `big-update` (since v1.8.0, b3efa2e)
- **8 new worlds**, slotted into the campaign by difficulty (`Game.LEVELS`, 31 courses in all):
  - medium: Toybox Tumble, Mushroom Hollow, Carnival Chaos;
  - hard: Sky Citadel, Dino Valley, Arcane Library;
  - very hard: Pixel Panic, Castle Siege (just before The Final Ascent).
  Each has its own score, ambience, footsteps, mechanic sounds, medal times, Silver hat and bot-proven routes.
- **Generic obstacle kit** (10 pieces: launch barrel, zipline, cannonball battery, rolling log, seesaw,
  flipper, drawbridge, gap wall, falling block, spinning hammer) and a Kit Gallery in the Playground.
  See `docs/KIT_OBSTACLES.md`.
- **Cosmetics:** 5 new characters (Wizard, Pirate, Yeti, Robo-Pup, Pixel Hero); 18 new hats; 6 paints,
  6 trails, 4 finish effects; 10 emotes and 6 victory poses (both mirrored online).
- **Animation:** wall runs, mantles, wall kicks and knocks mirrored online; new fidgets, per-character idle
  flourishes, landing variety, checkpoint flourish, respawn beam.
- **Depth:** ghost replays of your personal-best run; 3 challenges per course; Challenges and Stats screens;
  new titles; earned rewards never re-lock.
- **Party mode rebuilt:**
  - core fixes: respawn protection, Fox Claw no longer an instant KO, Swap Warp by real course distance with a
    handshake, items kept when there is no target, round time limit, host-drop recovery, box-grant race,
    tap-on-press attacks, real Shrink and Freeze, Jetpack balance, boxes on every course;
  - new HUD: standings strip, "Targeted!" warnings, radar arrows, item feed, roulette, spectate countdown,
    animated results;
  - CPU racers (Easy / Normal / Hard), "Party vs CPU" solo, and "Fill with CPUs" online;
  - 7 new items: Homing Shell, Leader Strike, Fake Box, Turbo Boost, Ghost, Decoy, Shockwave;
  - cups of 3, 5 or 8 rounds (or Endless) ending on a podium; a host ruleset; new game types King of the
    Hill, Elimination, Coin Rush and Hot Potato.
- **Controls:** the D-pad now plays emotes (keys 1-4 too). The left stick and WASD still move.

## Open owner decisions
1. **D-pad emotes.** The D-pad no longer moves the character. Confirm this binding, or pick another.
2. **Gilded hats instead of new shapes.** The Gold tier uses five Gilded versions of existing hats, not new
   shapes. Confirm, or ask for new shapes.
3. **Sky Citadel's jump density.** 87 of its 91 main-path jumps are at 85% or more. It may be too dense
   for a hard world. Owner to say whether to ease it.
4. **Shortcuts that save little time** on Toybox Tumble, Mushroom Hollow, Carnival Chaos, Castle Siege and
   Arcane Library. Some shortcuts barely beat the main route. Owner to say whether to rework them.
5. **Nothing visual has been seen in a real window yet:** shaders, the podium, the effects, the new worlds'
   looks, the Locker previews and the party HUD. Headless runs never compile shaders or particles.

## Remaining steps, in order
1. **Windowed screenshot pass**, only with the owner's OK (the owner plays on this PC; never open a window
   without asking). Cover the new worlds, the shaders, the podium, the effects and the HUD.
2. **Release v2.0.0**, only with the owner's OK: merge to `main`, bump `config/version`, export, zip,
   `gh release`. Release notes must be 600 characters or fewer; `docs/RELEASE_NOTES_v2.0.0.txt` is the text.
   The GitHub token problem from session 4 was not rechecked for this section. Confirm auth before any push
   or `gh release`.

## Small known items (not fixed)
- `party/party_names.gd` still describes the Fox's tap attack as "Claw (KO)"; the claw no longer KOs
  outright. Reword it.
- CPU "Hard" does not pick a different `route_variant`; variants change the geometry a level builds at load.
  Hard takes corner shortcuts only.
- Tests: this documentation pass ran no Godot and no tests. The full suite takes over 90 minutes, so run it
  in slices (the bot levels one at a time, then `--skip=test_n_bot`) before the release.

## Branches
| Branch | State |
|---|---|
| `big-update` (lead worktree `.claude/worktrees/lead-big`) | v2.0.0 candidate, merged, HEAD 21432a7 |
| `docs-v2` | this documentation pass on top of `big-update` (README, this section, DECISIONS, release notes) |

# HANDOFF - 2026-10-01 (session 4): PAUSED mid-round. Four more worlds, medal times, earnable characters

Read this first when picking the work up. **Everything is paused on purpose; the owner asked for it.** No agents or
processes are running. All unfinished agent work is saved as `WIP (paused)` commits.

## Shipped since session 3
- **v1.4.1:** Frostbite Pass's avalanche finale made beatable; the Particles slider; calmer title music.
- **v1.5.0:** four new worlds, Phantom Manor, Storm Armada, Sugar Rush and Super Carrier (levels 11-14; The
  Final Ascent moved to level 15).
  - Released at the owner's request **before any windowed screenshot pass**, so none of maps 11-14 has been
    looked at rendered yet.
  - Storm Armada's hardest jump is only 83%. The owner hasn't said whether to make it harder.

## BLOCKER: GitHub auth
`GH_TOKEN` is invalid or expired (`gh auth status` says the token is invalid, and `git push` fails with
"Authentication failed"). Nothing from this session is pushed. The owner must renew the token before any push or
`gh release`.

## Branches (all local; nothing pushed)
| Branch / worktree | State |
|---|---|
| `extras` (fb22cb2), worktree `.claude/worktrees/agent-a6587586702cfa6e6` | **DONE and fully tested; ready to become v1.6.0.** Run It Again (lapping) + Locker with unlockable trails & finish effects. Non-bot suite 969/0, every bot level and route passed (0-14). Not merged to main. |
| `new-worlds-3`, lead worktree `.claude/worktrees/lead-nw3`, HEAD 04f084e | Built on `extras`. Holds everything below that is merged. |
| `wild-west`, worktree `agent-af49ba4887b7d7df2`, **WIP 85834eb** | Level 18 is built (78ba03d), but the bot needs respawns. Fix in progress, then paused. **Not merged.** |
| `new-worlds-3-mech`, worktree `agent-a8dca2e0595020100`, **WIP 19bf706** | 71 mechanic clips generated for sakura/jungle/frontier/neon. Not yet verified, imported or tested. **Not merged.** |

## Merged into `new-worlds-3`
The plan is `C:\Users\fatty\.claude\plans\abundant-hugging-lark.md`, approved by the owner. They asked for "3 more
thematically unique maps" and then picked all 4 themes, plus earnable characters and cosmetics (they picked all 4
reward types).

- **Groundwork:**
  - levels 16-19 slotted before the finale; The Final Ascent is now `levels/level_20_ascent.*`;
  - `Game.LEVELS`, `SaveData.LAYOUT_REV` and `Look.THEMES` entries;
  - the spec, `docs/NEW_WORLDS_3_BRIEF.md`.

  New 0-based indices: 14 sakura, 15 jungle, 16 frontier, 17 neon, 18 ascent.
- **Scores (lead):** `piece_sakura`, `piece_jungle`, `piece_frontier` and `piece_neon` in `tools/gen_music.py`,
  each with a fanfare and chimes. All pass `--verify` and are documented in `docs/AUDIO.md`.
  `Sfx.MINOR_THEMES` includes sakura, jungle and neon.
- **Soundscapes + footsteps** (c99ded1):
  - ambience 30.94 / 34 MB;
  - world SFX 18.5 / 30 MB before the mechanic clips.
- **Rewards framework** (8854a5a):
  - **Medals:** `Game.medal_for()`, `medals` on every `Game.LEVELS` entry, and `Game.BOT_TIMES`. Gold is the
    fastest bot route ×1.12, Silver ×1.35, Bronze ×1.7, each rounded up to 5 s.
  - **Cosmetics:** `Cosmetics` is now a `KINDS` table with rules `medal`, `medals`, `all_medals` and `stat`.
  - **Catalogue:** 10 characters, 22 hats, 8 paints and 7 titles.
  - **UI:** a tabbed Locker (LB/RB), medals on level select and the results panel, the unlock banner.
  - **Online:** titles on the roster, and every id synced on both the relay and the direct path.
  - **Saves:** `SaveData.stats` (`laps_dealt`, `flawless_golds`).
  - **Tests:** `run_tests.gd --save=<name>` gives parallel runs separate test saves.
- **Character art** (36f5b74): `player/cosmetic_art.gd`, plus `set_character`, `set_hat` and `set_paint` in
  `player_visual.gd`, with 13 shaders.
  - **Owner decisions pending:**
    - "Factory White" currently means each character's stock look, not literal white.
    - Cat-bot's ears poke through hats on purpose.
- **Levels** (bot: 0 respawns on every route, with and without the 1.0 s human pause):
  - **Neon City** (9dd1931): hardest jump 88%. Hover traffic, searchlight drones, glitching holograms.
  - **Jungle Temple** (0b14f08): hardest jump 79% on the main line, 87% with the shortcut. Vines, rafts, darts,
    glyph gates, the boulder chase.
    - Possibly easier than intended (it should be harder than Sakura).
  - **Sakura Peaks** (a9f96e3): hardest jump 91%. Koi stones, sinking petals, bamboo springs, bell logs,
    shuriken, paper doors, two swaying rope bridges with gusts.
    - Harder than intended for the first of the four. Ask the owner whether to swap difficulty with Jungle or
      tune both.

## Next steps, in order
1. **Wild West Heist:** resume the fix in `agent-af49ba4887b7d7df2` (branch `wild-west`, WIP 85834eb).
   - Goal: 0 respawns on all 3 routes, with and without the temporary 1.0 s pause hook, run on the final commit.
     Remove the hook before committing.
   - Where it stood: on the final commit, routes 0/1/2 needed 1/1/3 respawns without the pause and 4 each with it.
   - The agent had started on the signal arms and the stage 10 gondola wait. Other suspects: the dynamite chain,
     the trestle collapse, the cattle-run fuse.
   - Then merge into `new-worlds-3`. Expect the usual `visual/ambience.gd` conflict: keep both cases, with
     `\t\t\t]` between them.
2. **Mechanic clips:** finish `new-worlds-3-mech` (WIP 19bf706):
   - run `python tools/gen_world_sfx.py --verify`;
   - headless `--import`, then commit the new `.import` files;
   - extend `WORLD_CLIPS` / `WORLD_LOOPS` and the "every WorldAudio clip the newer maps name exists" check for the
     4 themes;
   - run `--only=test_z_world` and `--only=test_zs`, then merge.

   The clip name lists are in the WIP commit's generator code.
3. **Real medal targets for levels 16-19:** run their bots, then update `Game.BOT_TIMES` and `medals`. They are
   marked `# PROVISIONAL`.
4. **Full suite on `new-worlds-3`, split:**
   - every bot level 0-18, one at a time: `--only=test_n_bot --level=N --route=all --save=<name>`;
   - the rest: `--skip=test_n_bot`.

   Run a headless `--import` first after merges.
5. **Ask the owner for a windowed screenshot pass** (never without asking). It is now owed for:
   - maps 11-14 and 16-19;
   - all 13 character/paint shaders plus every level shader (headless runs never compile shaders);
   - the Locker, the medal UI, and the trails and finish effects.

   Every agent's report lists its camera setups.
6. **Releases, each only with the owner's OK:**
   - **v1.6.0** = `extras`. It can ship now that the token is fixed: merge to main, bump `config/version`, export,
     zip, `gh release`.
   - **v1.7.0** = `new-worlds-3`.

   Release notes must be 600 characters or fewer.

## Test and tool tips learned this session
- **The full suite is too long for one run.** The bot test takes more than 90 min with 15+ levels, so split it as
  above.
- **Test saves:** every run wipes `user://test_progress.json` unless it uses `--save=<name>` (on `new-worlds-3`
  and later). Concurrent runs without it clobber each other.
- **Background limits:** background shell commands hit a time limit. Run bot levels in batches of about three.
- **`tools/gen_music.py` has no `--help`.** Any unknown `--flag` with no piece name re-renders **every** score.
  Use `--list`, or name the pieces.
- **Paths:** Windows Python can't open `/c/...` paths. Write scripts with Windows paths.
- **Merges:** after merging branches, a headless `--import` is required before tests, or new `class_name`s and
  assets fail to load.

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

## In flight
### 1. Relay resume - SHIPPED (v1.3.2, relay deployed 2026-09-24)
Owner report: "relay connection closed" kicked people mid-race. The fix: session tokens, a grace
period on unclean drops (20 s for a racer, 30 s for the host), `role=rejoin`, and auto-reconnect into
the same slot. Poses dropped to 15 Hz with an idle heartbeat. It was verified locally and on the live
relay (`health` reports `resume: true`); the full suite passed with 630/630. The details are in
docs/RELAY.md. If a drop is ever reported again, ask for the `[relay]` lines in the owner's
`godot.log`.

### 2. Four new worlds - SHIPPED (v1.4.0, merged to main 2026-09-24; full suite 803/803)
Owner asked: "2 more unique maps" (an alien planet, a volcano with a cool eruption in the background),
then "level 9 and 10 with 2 different unique untouched themes". The spec is `docs/NEW_WORLDS_BRIEF.md`.
New order (0-based index): 6 Xeno Wilds (`xeno`), 7 Cinder Peak (`volcano`), 8 Frostbite Pass
(`glacier`), 9 Scarab Sands (`desert`), 10 The Final Ascent (`levels/level_11_ascent.*`, still the finale).
- **`new-worlds`** holds all of it:
  - the groundwork and all four scores;
  - the sound (`new-worlds-sound`);
  - the four level branches (`xeno-wilds`, `cinder-peak`, `frostbite-pass`, `scarab-sands`);
  - today's `main` (updater and relay fixes).

  The integration worktree is `.claude/worktrees/lead-new-worlds`.
- **Per-level results** (18 stages each; bot times are for route 0):

| Map | Bot result | Hardest jump | Set piece |
|---|---|---|---|
| Xeno Wilds | 0 respawns on all 3 routes, 147 s | 90% | leviathan ride |
| Cinder Peak | 0 respawns on all 3 routes, 147 s | 91% | rising-lava magma chamber |
| Frostbite Pass | 0 respawns on all 3 routes, 179 s | 92% | avalanche race |
| Scarab Sands | at most 4 respawns per route, 171 s | 88% | boulder run |

- **Screenshot pass done** (2026-09-24, with the owner away): 39 views with zero shader errors. Two
  real bugs were found and fixed in a5c3406:
  - **Scarab Sands rendered black:** NaN in the sky shader from `pow()` of a negative number.
  - **Cinder Peak's sky was washed out orange:** the anvil cloud's underglow was too strong.

  The shot list is in each agent's report and in the session scratchpad `shots/list.txt`.
- **Remaining:**
  - (a) The full suite with `--route=all` on `new-worlds` (it was running at handoff time).
  - (b) Owner's OK, then merge `new-worlds` into `main`, bump to 1.4.0 and release. The patch notes
    should mention the four new maps and that The Final Ascent now unlocks after Scarab Sands.
  - (c) Optional playtest tuning: the bot's 0 respawns reflect its precision; the owner may find some
    stages easy.

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
