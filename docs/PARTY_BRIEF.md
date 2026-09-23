# PARTY MODE brief

Owner's request (2026-09-23): "another game mode that's less competitive and more party style with a bunch of crazy
power ups and ways to bump each other off the map / grief each other. One of the powerups can be the nine tailed fox
powerup where you can go really fast, jump far, claw people to death, and shoot tailed beast bombs. Another might be
Link's tunic, where you turn into Link and get a few of his tools and the master sword to fight people with during the
race. Another might be super saiyan hair where you can do kamehameha, etc. Be creative with the power ups, but only
include them in the other game mode, not the main mode. 2v2 mode could be a good addition with team races and a
scoring system of some sort." and "put a heavy emphasis on cool particle effects".

Read first: README.md, docs/DECISIONS.md, docs/RELAY.md, relay/PROTOCOL.md, autoload/net.gd, autoload/game.gd,
levels/level_base.gd, player/player.gd, player/remote_racer.gd, ui/title.gd, ui/hud.gd, ui/ui_kit.gd,
autoload/settings.gd, ui/settings_panel.gd, tests/mp_test.gd, tests/run_tests.gd (how tests are written).

## The mode (design decisions already made - build these)
- **Modes, chosen by the race host in the lobby:** `Race` (today's mode, completely unchanged), `Party` (free-for-all
  with power-ups and griefing), `Team Party` (2v2 - teams of two; with 3 or 5+ players teams are balanced as evenly as
  possible and the host can swap anyone's team in the lobby). Team colours tint names, ghosts and the scoreboard.
- **Party Practice (solo):** a "Party Practice" entry reachable from the title menu (controller-navigable) that plays any
  unlocked level with item boxes and power-ups so a player can try every power-up alone. No scoring. A few static
  "practice dummies" (ghost-like targets standing on checkpoint lawns) that react to hits make the weapons testable.
- **Main mode stays pure:** nothing party-related may spawn, bind, or change numbers in solo Race / multiplayer Race.
  Gate everything behind one flag (e.g. `Game.party_mode` / a `PartyRules` object that is null in the main mode).
- **Item boxes:** spinning "?" cubes with glow + particles, auto-placed by the party layer from the level's own data -
  a row of 3-4 across each checkpoint's ground (checkpoints are always on static safe ground) and at the start - so the
  level scripts need no changes. Levels are being extended in parallel (new checkpoints appear), so derive positions
  at runtime from `LevelBase.checkpoints` (and ground raycasts), never hard-code them. Picking one up rolls an item
  (weighted by race position: players behind get the wild stuff, the leader gets defensive/small items); the box
  pops with a burst and respawns after a few seconds. One item slot, shown on the HUD with its icon and name.
- **Griefing for everyone:** in party modes every player has a **Shove** (short cooldown): a quick lunge that knocks a
  rival away (stronger from behind / in the air) - enough to bump people off narrow beams. Plus all the power-ups.
- **Hits are victim-applied:** the attacker's client detects the hit against the rival's ghost (`RemoteRacer`) and sends
  a hit message (knockback vector, stun, "ko" flag); the victim's client applies it to its own Player (use
  `Player.knockback()`; a KO = `level.fail("hazard")` so they go back to their checkpoint). Projectiles and transformations
  are replicated as events so every screen shows them (deterministic flight from the spawn event where possible).
  Whatever the host needs to be authoritative about (box pickups / respawn, scoring, round end) goes through the host.
  Keep the relay protocol working: check relay/PROTOCOL.md - if the relay forwards opaque game packets you only extend
  the Godot side; if it must change, change relay/src too and its smoke test (`npm test` in relay/).
- **Scoring - the Party Cup:** a party session is a cup of rounds (host picks each level, like now; show "Round n").
  Per round: placement points **1st 10, 2nd 8, 3rd 6, 4th 5, 5th 4, 6th 3, 7th 2, 8th 1**, **+3 per KO** (a rival who
  falls or dies within 4 s of your last hit on them is your KO), **+2** for the first player through each checkpoint's
  "bonus" (optional, if cheap). Round ends when everyone finished or 45 s after the first finisher (HUD countdown);
  unfinished players get 0 placement points but keep KO points. Team Party: team score = sum of its members; the round
  and cup winners are teams. Results screen after each round: round points breakdown + cumulative standings; controller
  friendly (A continue, focus visible), host continues to the next round or back to the lobby.
- **Power-ups (the fun part - make them spectacular):** transformations last ~10 s with a HUD timer, have their own
  model attachments (built from Look primitives + particles, attached as children to the player's visual / the ghost,
  never by editing player/player_visual.gd), their own sounds (reuse Sfx clips with pitch, or synthesise new ones in
  tools/gen_audio.py style if you can), movement via `Player.speed_mult / jump_mult / gravity_mult` (restore on end),
  and attacks on the Attack button. Required ones:
  1. **Nine-Tailed Fox** - orange chakra cloak, fox ears, nine flowing tails (particle ribbons), red eyes glow:
     speed x1.6, jump x1.35; **Claw**: a lunging swipe that KOs a rival it connects with; **Tailed Beast Bomb**: hold
     Attack to charge a dark sphere (swirling particles) and release to fire it - big explosion knockback radius.
  2. **Hero's Tunic** - green tunic and cap, shield on the back: the **Legend Blade** (sword slash combo, a spin attack
     when charged, knocks rivals away), and tools cycled with Use: **Boomerang** (returns, stuns), **Hookshot**
     (grapple to a surface or yank a rival toward you), **Bombs** (throwable, fuse sparks, blast knockback).
  3. **Golden Surge Hair** (the super-saiyan nod) - spiky golden hair, crackling aura, lightning sparks: faster, a
     double jump, a dash-punch; **Energy Wave**: hold Attack to charge ("Ka... me...") and release a long beam that
     shoves everyone along it (beam particles, screen shake).
  And **at least 7 more of your own**, as creative as possible, e.g. Thunder Cloud (zaps everyone ahead: brief stun +
  slow), Banana-style Slick Puddle dropped behind, Spring Boxing Glove, Magnet (pulls rivals toward you / off ledges),
  Shrink Ray, Position Swap with the player ahead, Balloon Shield (reflects one hit), Jetpack burst, Tornado that
  wanders along the course, Gravity Bomb (rivals caught float helplessly), Ice Beam (freezes a rival in a block).
  Names: use evocative nods rather than exact trademarks (the game is published on GitHub) - e.g. "Hero's Tunic",
  "Legend Blade", "Golden Surge Hair", "Energy Wave" - and keep every display name in ONE table so the owner can
  rename them in one place.
- **Controls:** new actions `use_item` and `attack` (and whatever else you need) with keyboard, mouse and gamepad
  defaults that do not clash with jump / retry / pause / camera, rebindable in Settings like the others, shown with
  pad-aware prompts (`Game.prompt()`, `Game.using_pad`). Every new screen/panel is fully usable with a gamepad alone
  (initial focus, D-pad/stick navigation, A confirm, B back, visible focus ring) - the owner plays with a pad.
- **Particles:** the owner wants a HEAVY emphasis on cool particle effects - every power-up, pickup, hit, KO, charge,
  projectile, explosion and transformation gets rich GPUParticles3D work (plus light flashes / screen shake where apt).
  Keep performance sane (many modest emitters, unshaded soft quads). Headless runs never compile particle shaders:
  run a windowed shot and grep the output for ERROR / SHADER lines.

## Ownership (other agents work in parallel on other files - stay inside these)
You may create anything under `party/` (scripts, scenes), `ui/party_*.gd`, `audio/` new clips, and edit:
`autoload/net.gd`, `autoload/game.gd` (NOT the LEVELS table lines), `autoload/settings.gd`, `ui/title.gd`,
`ui/hud.gd`, `ui/pause_menu.gd`, `ui/settings_panel.gd`, `ui/ui_kit.gd`, `levels/level_base.gd` (small hooks only),
`player/player.gd` (small hooks only - no movement-number changes when party is off), `player/remote_racer.gd`,
`relay/` if unavoidable, `tests/run_tests.gd` / `tests/mp_test.gd` (add tests at the end of the file), README.md
(a Party Mode section), docs/DECISIONS.md.
Do NOT edit: any `levels/level_*` course script, `mechanics/`, `player/player_visual.gd`, `visual/look.gd`,
`levels/level_kit.gd`, `tests/route_bot.gd`.

## Verify
Engine: `/c/Users/fatty/Desktop/PlatformerJumpPuzzle/tools/Godot_v4.7.1-stable_win64.exe` with `--path <your worktree>`;
run `--headless --import` first. Always wrap runs in `timeout` (a parse error hangs Godot forever).
- Unit tests (append to tests/run_tests.gd): scoring (placements, KOs, team sums, round end rule), item roll weighting,
  each power-up applies/restores its movement multipliers and its attack knocks a practice dummy, the main mode spawns
  no party nodes, menus build without errors and are pad-navigable.
- Multiplayer: extend tests/mp_test.gd (it runs real host + client processes) so a party round runs over the network:
  host + client, a hit crosses the wire and knocks the victim, a pickup is consumed once, scores agree on both ends.
- The whole existing suite must stay green: `-- --only=test_` minus the long bot test is fine while iterating; run
  test_r / test_z* / test_v* / test_w* / test_race* for UI and networking regressions.
- Screenshots of each transformation and the HUD (windowed `tools/shot.tscn` or your own small capture scene under
  tests/scratch/, deleted afterwards). Do NOT launch the game normally or run tools/bot_shots.tscn (they can touch the
  owner's real save file).
Godot's --import rewrites tracked *.import files with CRLF-only changes: discard them. Heredocs truncate at apostrophes -
use the Write/Edit tools for file content.

## When done
Commit on your worktree branch (your files only), message ending with
`Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Do not push or merge. Report: what was built, controls,
the full power-up list with what each does, the network messages added, test results, known gaps, branch + commit.
