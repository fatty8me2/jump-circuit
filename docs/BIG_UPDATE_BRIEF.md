# BIG UPDATE brief (v2.0.0): 8 new worlds, party mode rebuilt, cosmetics, animation, depth

Owner (2026-10-07): "we need to add more levels and more cosmetics to the game, as well as refining the party mode,
its in really bad shape ... We need a ton more levels ... and overall just more depth added to the game. whether that
means new obstacles, or new animations, make it happen."

What the owner chose:
- **8 new worlds** on a **mixed difficulty curve**, each slotted into the campaign where its difficulty fits.
- **Party mode:** fix its bugs and UX, more items, new party modes, and CPU racers.
- **New visuals, new animations and many new obstacles. No new player moves:** the move set and
  `resources/movement_tuning.gd` stay exactly as they are, so the 23 existing courses and their bot routes stay valid.

Many agents work in parallel, each on its own branch. The lead (Opus) merges them into `big-update`. Find your
workstream below and read **all of "Rules for every agent"**.

## Rules for every agent

### Before you start
1. You are in your own git worktree. Run `git checkout -B <your-branch> big-update`, where `<your-branch>` is named
   in your prompt.
2. Seed the import cache by copying the lead's: `cp -r C:/Users/fatty/Desktop/PlatformerJumpPuzzle/.claude/worktrees/lead-big/.godot .`
   Skip this if your worktree already has `.godot/`.
3. Then always run a headless import (step 4 of "Running Godot").

### Running Godot
1. The engine is **`/c/Users/fatty/Desktop/PlatformerJumpPuzzle/tools/Godot_v4.7.1-stable_win64.exe`** (call it
   `$G`). It exists only in the main checkout.
2. Wrap **every** Godot run in `timeout`. A GDScript parse error makes Godot sit idle forever.
3. **Headless only. Never open a windowed Godot.** The owner plays on this PC, and windows pop up over their game.
   Headless runs never compile shaders or particles, so check your shader code carefully by reading it.
4. Run `timeout 900 $G --headless --path . --import` after checkout, after every merge, and after adding
   `class_name`s or assets.
5. Use **`--save=<your-branch>`** on every test run. Many agents run tests at the same time, and without it they all
   share one test save.

### Running the tests
- Command: `timeout 1800 $G --headless --path . res://tests/run_tests.tscn -- --only=<substr> [--level=N] [--route=all] --save=<branch>`
- **Never run the whole suite.** It takes more than 90 minutes. Run your own tests, plus the ones that cover files
  you touched.
- Bot runs go one level at a time: `--only=test_n_bot --level=N --route=all`.
- The owner's real save is `%APPDATA%\Godot\app_userdata\Jump Circuit\progress.json`. Never touch it.
- **Kill any Godot process you started before you finish.**
  - Tree-kill a hung run: `taskkill //F //T //PID <pid>`.
  - Never kill processes you didn't start: other agents are running.

### Committing
- Godot's import rewrites tracked `*.import` files with line-ending-only (CRLF) changes. **Never commit those.**
- Stage files by name, never with `git add -A`.
- **New** `.import` files for new assets must be committed.
- Commit on your own branch with clear messages that end with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`
  (or `Haiku 5.5`, matching your model).
- Do not push, merge into `big-update`, or touch other branches.

### File ownership
- Edit only the files your workstream owns.
- In the shared hot files (`autoload/game.gd`, `autoload/net.gd`, `autoload/cosmetics.gd`, `autoload/settings.gd`,
  `player/player_visual.gd`, `player/player.gd`, `levels/level_base.gd`, `ui/title.gd`, `tests/run_tests.gd`,
  `tests/route_bot.gd`):
  - only **add** functions, table entries or small hook calls;
  - never reformat, reorder or rename;
  - put new tests in a new block at the end of `run_tests.gd` (or next to your area's tests);
  - list every hook line you touched in your report.

### Controllers, effects and sound
- **Controller:** every new screen or menu must be fully usable with a pad alone:
  - an initial focus (`_focus_pref` / `UiKit.focus_first`);
  - B or `ui_cancel` backs out;
  - a visible focus ring;
  - `Game.prompt()` button hints.

  Test with `Input.parse_input_event`, sending press and release a frame apart.
- **Effects:**
  - every particle amount goes through `Settings.particle_scale()` (or `Fx.spawn`, which applies it);
  - shaders must be NaN-free (guard every divide, `pow` and `normalize`), with bounded HDR;
  - no overlapping or z-fighting visuals.
- **Sound:** don't edit the audio generators unless your workstream owns them.
  - Call clips by name: `WorldAudio.at/loop`, `Sfx.play...`.
  - Name them `<theme>_<snake_case>`, or `party_<x>` / `kit_<x>`.
  - **List every clip name you call in your report**, with a one-line description and whether it is a one-shot or a
    loop.
  - A missing clip is skipped silently at runtime.

### Your report (your final message)
1. What you built.
2. The files you touched, and the hook lines you touched in shared files.
3. Your test commands and results.
4. Sound clips needed.
5. Known issues.
6. Your branch and its HEAD commit.

## The campaign after this update (0-based index = `--level=N`)
| Index | Courses |
|---|---|
| 0-5 | gardens, foundry, balance, clockwork, reef, **5 toybox** |
| 6-11 | orbital, xeno, **8 fungal**, volcano, glacier, desert |
| 12-17 | **12 carnival**, manor, armada, candy, **16 olympus**, carrier |
| 18-23 | sakura, jungle, **20 dino**, frontier, neon, **23 arcane** |
| 24-30 | doom, abyss, tempest, void, **28 arcade**, **29 siege**, 30 ascent (the finale, always last) |

Placeholder files are `levels/level_25_toybox`, `26_fungal`, `27_olympus`, `28_arcade`, `29_carnival`, `30_dino`,
`31_arcane` and `32_siege` (`.gd` and `.tscn`). File numbers no longer match indices.

## WORKSTREAM L: the 8 new worlds (one Sonnet agent per world, branch `world-<id>`)
Read `docs/NEW_WORLDS_BRIEF.md` ("done", the rules, verify and report), then `docs/NEW_WORLDS_3_BRIEF.md` and
`docs/NEW_WORLDS_4_BRIEF.md`. Every rule in them applies. The quality bar is levels 16-23
(`levels/level_16_sakura.gd` ... `level_23_void.gd`; `level_23_void.gd` is the best structural template).

### What you own
- `levels/level_NN_<id>.gd` / `.tscn`.
- `mechanics/<id>_*.gd`, and `visual/<id>_*.gd` / `.gdshader`.
- Your `Look.THEMES` entry, which is a placeholder now: retune it freely.
- Your case in `visual/ambience.gd` `recipe()`, which is a placeholder now: replace it with near, mid and far layers.
- Your LEVELS `name` and `blurb` if you want to improve them. Don't touch the medals; the lead sets them.
- **Additive** step kinds in `tests/route_bot.gd`: new `match` lines and new functions at the end.

### What the lead does
The score, ambience, footsteps, mechanic clips, medals, the Silver hat and the bot times. Just name your clips and
list them.

### Difficulty tiers (measured by `test_m`)
| Tier | Main-path hardest jump | Checkpoints (stages) | Other |
|---|---|---|---|
| **MEDIUM** | 82-86% | 17 (18) | Generous landings (1.4 m or more on the main path). Playful, readable. A good second taste of the game for new players. |
| **HARD** | 87-91% | 16 (17) | 8 or more jumps at 85% or above. |
| **VERY HARD** | 92-95% | 14 (15) | Every rule of `NEW_WORLDS_4_BRIEF.md` "very hard": 12 or more jumps at 85% or above, a third of landings 1.0-1.4 m, combined demands in each stage, pace. |

**Every tier must have:**
- at least 3 branched stages, at least 4 shortcuts (95% or less, a real time saver), at least 3 wall runs and at least
  3 mantles;
- the four machines (laser, piston, crusher, portal) somewhere;
- **3-4 theme mechanics** (`mechanics/<id>_*.gd`) plus a **set-piece finale**;
- telegraphing of 0.8 s or more on every timed hazard, visible and audible;
- 1.5 s or more of bot slack on every wait;
- **0 bot respawns on every route, both without and with a temporary 1.0 s pause after every wait and checkpoint**,
  on your final commit. Add the pause hook to `route_bot.gd` while testing and remove it before committing.
- Ridden vehicles carry the player with their full velocity, and never teleport.

### The worlds
Each must look unlike every existing world.

| Index | Id | Name | Tier | Theme mechanics (pick 3-4, or better ideas) | Set piece |
|---|---|---|---|---|---|
| 5 | `toybox` | Toybox Tumble | MEDIUM | Wind-up cars you ride; block towers that topple on a tell; jack-in-the-box springs; a toy-train loop; spinning tops as rotating platforms; a xylophone bridge where each key bounces. A giant kid's bedroom in afternoon sun: rug, crayons, LEGO-like bricks, a night-light. | Up the bookshelf to the toy rocket on top. |
| 8 | `fungal` | Mushroom Hollow | MEDIUM | Bouncy caps (springy, with variable height); spore-puff lifts that rise on a puff; dewdrop slides (slick); snail-shell movers; acorn catapults; a leaf canopy that sags. A sunny storybook forest floor seen at beetle size: daisies like trees, a ladybird, a stream. Warm daytime; **not** Xeno's glowing alien night. | The great toadstool: spiral up its gills to the cap. |
| 12 | `carnival` | Carnival Chaos | MEDIUM | Coaster cars you ride along a track; carousels (rotating rings with bobbing horses); whack-a-mole pistons; Ferris-wheel gondolas; a funhouse spinning tunnel; balloon-dart popping platforms. A funfair at sunset with string lights and tents. | The human-cannonball tent: fire out of the cannon to the big-top finish. |
| 16 | `olympus` | Sky Citadel | HARD | Chariot rides (a winged chariot mover); crumbling columns that fall a beat after landing; sun-mirror beams (laser-like light beams swept by rotating mirrors); wind spirits (telegraphed gust lanes); floating marble islands that bob. Marble temples on golden-hour clouds. **No lightning** (that is Tempest's). | Ascend the sun temple stair as giant statues' arms sweep; the finish is at the sun disc. |
| 20 | `dino` | Dino Valley | HARD | Geysers (launch on a clock); pterodactyl rides (a carry path); tar pits (slow / sink); a stampede lane (timed crossings); a brontosaurus neck you ride up and down; fern catapults. A lush prehistoric valley with a smoking volcano far off (not Cinder Peak's ash world). | The T-rex chase: a telegraphed pursuit through a canyon to the nest finish. |
| 23 | `arcane` | Arcane Library | HARD | Flying books (flapping movers); ink rivers (hazard flow lanes); sliding shelves (moving walls you run); spell circles (glyph pads that teleport or boost); hourglass time gates (open while the sand runs); quill sweepers. An endless wizard library with candles and floating staircases. | The orrery tower: ride rotating rings up to the open grimoire. |
| 28 | `arcade` | Pixel Panic | VERY HARD | Falling tetromino blocks that stack and clear on a tell; chomper chasers (dots-maze ghosts on rails); pong paddles (moving platforms that bat); a scrolling-screen stretch (an auto-scroll kill wall); glitch tiles that blink between states; pixel ladders. Inside a retro arcade cabinet: voxel/pixel shaders, scanlines, CRT glow. Not Neon City's rain city, not Ascent. | The boss stage: a giant pixel boss's telegraphed attacks across a scrolling arena to the HIGH SCORE gate. |
| 29 | `siege` | Castle Siege | VERY HARD | Trebuchet boulders (telegraphed landing shadows); battering rams (swinging logs); drawbridges that rise and fall; boiling-oil pours (lane sweeps); arrow volleys (telegraphed strips); siege towers you ride. A medieval castle at dusk with fires, banners and smoke. The last course before the finale, and the hardest. | The trebuchet launch over the walls, then the climb up the keep to the banner. |

### Generic obstacle kit (workstream O)
Its new kit obstacles are merged into `big-update` partway through:
- Wave-B worlds (carnival, dino, arcane, siege) must use **at least 3** of them.
- Wave-A worlds (toybox, fungal, olympus, arcade) may merge `big-update` when the lead says the kit has landed, and use
  them.

### Report
Everything in `NEW_WORLDS_BRIEF.md` "When done", plus:
- the `test_m` statistics: the hardest jump, how many main-path jumps are 85% or more, and the narrowest landing;
- the bot times per route, with and without the pause;
- the clip list;
- 3-5 camera setups for the lead's screenshot pass.

## WORKSTREAM O: generic obstacle kit (Sonnet, branch `kit-obstacles`)
About 10 new reusable obstacles, each with:
- a script `mechanics/<name>.gd` with a `class_name`;
- a `kit.<name>(...)` wrapper in `levels/level_kit.gd` (append only);
- course-clock-driven timing, so the bot can predict it;
- a clear tell of 0.8 s or more;
- `WorldAudio` hooks (`kit_<name>_*` clips);
- route-bot support: new step kinds if needed, or `b_wait` predicates exposed as static helpers;
- tests in a new block at the end of `run_tests.gd`.

The obstacles:
1. **Launch barrel / cannon:** enter it, it aims along a fixed arc, and fires on a tell.
2. **Zipline:** a ride along a cable. Jump to release, keeping the momentum.
3. **Cannonball battery:** fires rolling or flying balls down a lane on a clock, with a muzzle flash tell.
4. **Rolling log:** a rotating cylinder you run on top of, which pushes you sideways.
5. **Seesaw:** a weight-driven tilting plank. Reuse the tilt platform physics where you can.
6. **Flipper paddle:** a pinball-style flipper that swats on a clock.
7. **Drawbridge:** a deck that raises and lowers on a cycle.
8. **Gap wall:** a moving wall with a doorway gap that slides across a lane.
9. **Falling block:** a block that drops when you approach or on a clock, with a growing shadow as the tell, then
   resets.
10. **Spinning hammer:** a hammer on a vertical axis that sweeps a circle, with a gap timing.

Also:
- Build a **"Kit Gallery"** in `levels/playground.gd` (append a new area; don't disturb what is there) that shows each
  obstacle.
- Document every kit function in a header comment and in a new section of this brief's file,
  `docs/KIT_OBSTACLES.md`.
- **Own:** the new mechanics files, the appended parts of `level_kit.gd`, `playground.gd` and `route_bot.gd`, and
  `docs/KIT_OBSTACLES.md`.

## WORKSTREAM P: party mode
Read `docs/PARTY_BRIEF.md`, `docs/DECISIONS.md` (the party section), `party/*`, `ui/party_*`, the party hooks in
`autoload/net.gd` and `game.gd`, and the `test_zp_*` tests plus `tests/mp_test.gd`. Every party change stays behind
`Game.party`: **the main mode stays pure** (`test_zp_main_mode_stays_pure`).

### P1: core fixes (Sonnet, branch `party-fixes`)
Owns `party/party_layer.gd`, `party_rules.gd`, `party_items.gd`, `party/powerups/*`.

Fix every one of these, each with a test where testable:
- **Respawn protection:** about 2 s of invulnerability after any respawn or KO, shown by a blinking shell. No item-box
  camping.
- **Fox Claw:** no longer an instant KO. Make it a big knockback with a 1.2 s cooldown. A KO is only scored if the
  victim falls.
- **Swap Warp:**
  - targets the nearest racer **ahead by real course distance** (checkpoint index plus the distance along the route to
    the next checkpoint), within a sane range;
  - swaps checkpoint progress so respawns are consistent;
  - lands both racers on safe ground (the target's last grounded position);
  - the Balloon Shield blocks it.
- **Thunder / Swap with no valid target:** the item is kept, not wasted, and a hint is shown.
- **Round end:** a hard round time limit (default 4 min; the HUD counts down the last 30 s). If the host drops, every
  client ends the round with its local results after a short grace and returns to the lobby cleanly.
- **Item boxes:** one in-flight pickup per client. The host never grants two; an extra box isn't consumed.
- **Attacks:** a tap attack fires **on press**. Hold-to-charge starts after 0.2 s.
- **Shrink:** shrinks the collision shape as well as the model.
- **Freeze:** keeps gravity; the player falls while frozen.
- **Jetpack:** not rolled for the leader. Cap its horizontal skip.
- **Box placement:** check it on all 31 courses. Add a test that loads every level's party layer and asserts at least
  3 boxes at the start and at least 2 at most checkpoints. Fix `lawn_spots` where a course fails.
- Remove the dead code in `party_hud.gd:244-245`, coordinating with P5 through your report.

### P2: CPU racers (Sonnet, branch `party-cpu`)
Owns `party/cpu/*` (new) plus small hooks.
- **Driving:** a CPU racer drives a real `Player`, or a lightweight player-like body, along the **level's own route**
  (the `r_*` steps every course already defines, as `tests/route_bot.gd` does).
  - Move the reusable driving logic into `party/cpu/` and keep `tests/route_bot.gd` working, either as a thin wrapper
    or with shared code. Bot tests must still pass unchanged.
- **Skill:** Easy, Normal or Hard, which sets reaction delay, hesitation at waits, occasional botched jumps (they fall
  and respawn like humans), and route-variant choice (Hard takes shortcuts).
- **CPUs take part fully:** standings, item boxes (they roll and use items with simple heuristics, e.g. Thunder when
  behind, Balloon when targeted, Shove when adjacent on a narrow beam), being hit and KO'd, scoring and results.
- **Rendering:** they appear like ghosts and remote racers, using cosmetics drawn from the unlocked or random
  catalogue, with names from a fun list.
- **Solo:** a **"Party vs CPU"** entry on the title screen (pad navigable) runs a local party cup:
  1. choose the mode (Party / Team);
  2. the CPU count (1-7) and difficulty;
  3. the course;
  4. play.

  No network is needed. Use the existing offline or practice path, or a local host with no peers.
- **Online:** the lobby host can enable "Fill with CPUs" up to 8 racers. The host simulates the CPUs and broadcasts
  their poses like a peer's (both direct and relay paths).
- **Tests:**
  - a CPU finishes several courses headless (early, mid and late);
  - a solo party round with 3 CPUs completes and scores;
  - the menu works with a pad.
- **Coordinate with P1:** you need only small hooks in `party_layer.gd` and `net.gd`. Keep them minimal and list them.

### P5: party HUD and UX (Sonnet, branch `party-hud`)
Owns `ui/party_hud.gd`, `ui/party_results.gd`, `ui/party_icon.gd`, plus new UI files.
- A live standings strip with your place (1st-8th, big and juicy), and team totals in team mode.
- "Targeted!" warnings for incoming Thunder, Swap, homing items and charged beams, plus off-screen arrows to nearby
  rivals.
- The feed shows item hits ("Ana iced Bo!") as well as KOs and bonuses.
- An item roulette: the slot spins through icons for about 0.8 s with a tick sound, then lands.
- After finishing: spectate the other racers (cycle with LB/RB, or reuse the existing spectate) with a countdown.
- The results screen: animated point tallies, per-round breakdown, MVP callouts (most KOs, biggest comeback).
- Everything pad navigable and readable at 1080p and 720p.

### P3: party modes and cup structure (Sonnet, branch `party-modes`; starts after P1 and P2 are merged)
- **Cups:** 3, 5 or 8 rounds (or Endless), then a **podium / champion screen**: the top 3 on pedestals with their
  cosmetics, confetti, and the cup totals.
- **Ruleset options** in the lobby: item frequency (off / low / normal / chaos), per-item toggles, KO value, round
  time limit, CPU fill. Saved in Settings, synced by the host.
- **New modes**, each in its own file under `party/modes/*.gd`, with one ruleset interface: scoring hooks, end
  condition, HUD widgets.
  - **King of the Hill:** hold the glowing zone, which moves between checkpoint lawns.
  - **Elimination:** the last racer through each checkpoint is out and spectates; the last one standing wins.
  - **Coin Rush:** coins along the route (place them on the route points); KOs drop coins; most coins wins.
  - **Hot Potato:** a bomb passes on a Shove or hit, and whoever holds it at the timer loses points.
- **Tests:** each mode's scoring and end condition, the cup length and podium, and pad navigation.

### P4: new items (Sonnet, branch `party-items`; starts after P1 is merged)
- At least 6 new power-ups in `party/powerups/`:
  - **Homing Shell:** seeks the racer ahead along the route.
  - **Leader Strike:** hits 1st place from the sky, with a long tell.
  - **Fake Box:** looks like an item box, stuns.
  - **Turbo Boost:** a short speed burst.
  - **Ghost:** turn intangible and steal a rival's item.
  - **Decoy:** a fake you that absorbs one hit.
  - Plus your own ideas.

  Each one gets spectacular effects (through `Settings.particle_scale()`), sounds (`party_<x>` clips), a HUD icon,
  and network replication.
- **Item-box rows along the course:** about every 35-45 m of route between checkpoints, on safe ground found by
  raycasts from the route points.
- **Rebalance the roll weights:** back-of-pack catch-up items, and leader-safe items for 1st.
- **Tests:** every new item in `test_zp_every_power_up`-style tests, plus roll weighting.

## WORKSTREAM C: cosmetics and animation
Read `autoload/cosmetics.gd` (`KINDS`, rules), `player/cosmetic_art.gd`, `player/player_visual.gd`
(`animate()` ~1817, `_build_body` ~340), `ui/title.gd` (Locker ~514-767) and the `test_zc_*` / `test_zm_*` tests.

### Extension seams already in place
Use them; never edit the original match blocks:
- `player/hats_ext.gd` (`HatsExt.build`, `HatsExt.OPEN_HATS`): any hat id `CosmeticArt.hat` doesn't know.
- `player/bodies_ext.gd` (`BodiesExt.build`, `BodiesExt.HEADS`): any character `_build_body` doesn't know.
- `player/looks_ext.gd` (`LooksExt.paint_material`, `trail_layers`, `play_finish`): new paints, trails and finishes.

Catalogue entries still go in `autoload/cosmetics.gd`. **Append** your entries to the end of each table (`HATS`,
`CHARACTERS`, `PAINTS`, `TRAILS`, `FINISHES`, `TITLES`). Update the hard-coded test id lists (~run_tests.gd:3958-3975)
by **appending**.

**Unlock rules:** prefer the new worlds' medals, `medals(tier, n)`, `stat(key, n)` and `runs(n)`. New stats must be
added to `SaveData.STAT_KEYS`, with a hint in `Cosmetics.hint`.

### C1: emotes and victory poses (Sonnet, branch `cos-emotes`)
- Two new `KINDS`: `emote` and `pose`.
- **Emotes:**
  - The **D-pad** in game plays emotes: 4 slots (up, right, down, left), configured in the Locker. Keyboard: 1-4.
  - D-pad and 1-4 are unused in gameplay today; double-check `Game` input setup.
  - About 10 emotes, procedural in `animate()` with a timer and pose table: wave, dance, flex, laugh, facepalm, bow,
    spin, thumbs up, taunt, sit.
  - Each has an optional small particle puff and sound (`emote_<id>` clips; list them).
  - Emoting is cancelled by any movement input. It is never allowed mid-air or during a race countdown in a way that
    affects physics.
- **Victory poses:** about 6, played at the finish and on the party podium (P3 will call `play_pose`).
- **Online:** mirrored to other racers through a new reliable net message (direct RPC plus a relay event, the same
  pattern as `send_lap` in `net.gd`). `RemoteRacer` plays them.
- **Locker:** new tabs with live previews; the preview plays the emote on loop.
- **Unlocks:** a few default emotes; the rest from medals and stats.
- **Tests:** kinds, settings sanitizing, the Locker tabs (update the tab index checks), the net message round-trip,
  pad input.

### C3: hats (Haiku, branch `cos-hats`)
- **The 8 world Silver hats**, rule `{"type":"medal","level":id,"tier":2}`:

  | World | Hat |
  |---|---|
  | toybox | wind-up key |
  | fungal | toadstool cap |
  | carnival | ringmaster top hat |
  | olympus | laurel wreath |
  | dino | dino skull |
  | arcane | wizard hat |
  | arcade | pixel crown |
  | siege | knight's helm with plume |

- **Plus about 10 more:** Gold-tier hats for some older worlds, and stat or run hats (e.g. viking helm, pirate
  tricorne, chef hat, beanie, cowboy hat, bunny ears, flower crown, top-hat-with-monocle, headphones, traffic cone).
- **Art:** in `HatsExt.build`. Each must fit **every** character, stay within the mesh budget
  (`test_zm_character_art`, 40 meshes per body plus hat), and may use `sway` / `spin` / `bob` metas.
- **Tests:** `--only=test_zm_character_art`, `--only=test_zm_catalogue`, `--only=test_zc`.

### C4: characters (Sonnet, branch `cos-characters`)
- 4-5 new characters in `BodiesExt`: e.g. **Wizard**, **Pirate**, **Yeti**, **Robo-Pup**, **Pixel Hero**.
- Each provides every standard part (see `_body_knight` and friends), fits every hat, takes paints on its shell only,
  has a `HEADS` entry, and is within the mesh budget.
- Unlock rules tied to the new worlds and stats.
- Run `test_zm_character_art` and the catalogue tests.

### C5: paints, trails, finishes (Haiku, branch `cos-looks`)
- **About 6 paints** in `LooksExt.paint_material`: inline shaders (NaN-free) or StandardMaterials. Ideas: gold leaf,
  pixel, marble, toxic, aurora, stained glass.
- **About 6 trails** in `LooksExt.trail_layers`: hearts, pixels, music notes, bubbles-of-ink, leaves, stars-and-moons.
- **About 4 finish effects** in `LooksExt.play_finish`: balloons, disco, meteor, pixel burst.
- Each finish needs an `audio/fin_<id>.wav`. Generate it with a small Python synth like `tools/gen_audio.py` (read it
  first) and commit the `.wav` plus its new `.import`.
- Run the `test_zc_*` and `test_zm_*` tests.

### C6: animation depth (Sonnet, branch `anim-depth`; starts after C1 is merged)
- **Mirror on remote racers** the wall run (lean / `wall_roll`), the mantle, the wall kick and the knock flail. Extend
  the pose packet compactly (a flags byte), with tests.
- **3-4 more idle fidgets**, plus per-character idle flourishes:
  - the knight swings its sword;
  - the ninja balances on one foot;
  - the dino tail-wags;
  - and so on.
- **Landing variety:** a soft landing after a short hop vs. a heavy crouch and dust after a big fall.
- A new checkpoint "touch" flourish, and a respawn materialize effect.
- `test_zm_player_visual_hooks` and the other existing animation tests must stay green.

## WORKSTREAM M: depth
### M1: ghost replays (Sonnet, branch `ghosts`)
- Record the local run, sampled at about 15 Hz: position, yaw, grounded and animation flags.
- Save the PB ghost per level to `user://ghosts/<id>.ghost`, in a compact binary format with a version header.
- Play it back as a translucent racer (reuse the `RemoteRacer` look, tinted) in solo runs.
- **Settings toggle:** Ghost (Off / PB / Gold medal target if available).
- **Pause-menu toggle.**
- A ghost from an older course layout (a different `LAYOUT_REV`) is discarded.
- No effect in party or multiplayer.
- **Tests:** record → save → load round-trip, playback timing, layout-rev discard, the settings toggle.

### M2: challenges and stats (Sonnet, branch `challenges`; starts in wave 2)
- **Challenges:** 3 per course: "Finish without falling", "Take the shortcut route" (detect it through route or zone
  triggers the level exposes, or simpler: "Beat Silver"), and "Finish under X".
- **Rewards:** progress shown on level select and in a new **Challenges** screen. Rewards are titles and some
  cosmetics (new rule type `challenges(n)`).
- **Stats screen:** total runs, falls, time played, medals by tier, favourite course, party wins.
- Pad navigable. Tests.

## WORKSTREAM S: sound (the lead or sound agents only)
- **S1 scores** (Sonnet, branch `sound-scores`): `piece_<id>` for all 8 worlds in `tools/gen_music.py`, each with
  `base` and `hi` layers, plus `fanfare` and `chime`. Register them in `PIECES` and `LAYERED`, and add minor-key
  worlds to `Sfx.MINOR_THEMES`.
  - Each world needs its own identity and instrument palette:
    - toybox: music box, xylophone, toy piano;
    - fungal: woodwinds, pizzicato, harp;
    - carnival: calliope / band organ, oom-pah;
    - olympus: lyre, choir pads, brass;
    - dino: tribal drums, low brass, marimba;
    - arcane: celesta, harpsichord, mysterious minor;
    - arcade: chiptune square/pulse/noise;
    - siege: war drums, horns, a minor march.
  - Run `--verify`. **Never run the generator without piece names** (that re-renders every score). Document them in
    `docs/AUDIO.md`.
- **S2 soundscapes** (Haiku, branch `sound-ambience`): the 8 themes in `tools/gen_ambience.py` and
  `sound/soundscape.gd` (a bed plus one-shot events), and the step/land clips in `tools/gen_world_sfx.py` (`THEMES`
  tuple and footstep branch).
  - Raise `SIZE_BUDGET` to fit (ambience about 56 MB, world SFX about 52 MB) and record the new totals in
    `docs/AUDIO.md`.
  - Run `--verify`, a headless `--import`, and commit the new `.import` files.
  - Run `--only=test_zs` and `--only=test_z_world`.
- **S3 mechanic clips** (Haiku, branch `sound-mech-<wave>`): every clip named in the level and kit agents' reports, in
  `gen_world_sfx.py`, plus the `WORLD_CLIPS` / `WORLD_LOOPS` test lists.
