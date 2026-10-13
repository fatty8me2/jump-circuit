# FLOW brief (v2.1): four momentum levels in a new Flow section

Owner (2026-10-13): "add some more momentum based levels where you can kind of enter a zen state if you get a flow and
go through the level suuuuuper fast".

What the owner chose:
- **4 levels**, in their own **Flow** section on level select. They unlock from campaign progress.
- **All four mechanics:**
  - speed rings and boost chains;
  - grind rails;
  - a flow meter and combo, with a **ZEN** state;
  - slopes and half-pipes.
- **Easy to finish, hard to master.** Landings are forgiving and deaths are almost nonexistent; the challenge is speed. A
  clean flow run is far faster, and Gold needs near-perfect flow.

**Base and process:**
- **Base branch:** `flow-update`, from `main` at 89e6931 (v2.0.0).
- **Merging:** the lead (Opus) merges.
- **Rules:** every rule in `docs/BIG_UPDATE_BRIEF.md` "Rules for every agent" applies unchanged. Read it first:
  - headless only and `timeout`;
  - `--save=<branch>`;
  - pad support;
  - `Settings.particle_scale()`;
  - NaN-free shaders;
  - CRLF `.import` noise;
  - the report format;
  - kill your own Godot processes.
- **Setup:** in your worktree, `git checkout -B <branch> flow-update`. Seed `.godot` from
  `C:/Users/fatty/Desktop/PlatformerJumpPuzzle/.claude/worktrees/lead-flow/.godot`, then run `--import`.

**The existing move set and `resources/movement_tuning.gd` must not change.** The 31 existing courses and their bot
routes must stay valid. Momentum comes from **surfaces and objects in flow levels only**.

What the engine already gives you:
- **Speed:** max run speed is 9 m/s. Boost strips (`kit.boost`) push you past it, up to `hard_speed_cap` 34 m/s.
- **Overspeed bleed:** above max, ground speed bleeds at `overspeed_friction` 5 m/s² and air speed at
  `air_overspeed_drag` 0.6 m/s².
- **Slopes:** `slip_start_deg` 11°.
- **Speed multiplier:** `Player.speed_mult` exists, and party mode uses it.
- **Floor queries:** `Player.grip()` and the `boost()` query on the floor body (`player.gd` ~298-357) are how surfaces talk
  to the player.

## The four levels (0-based index = `--level=N`; they come AFTER The Final Ascent)
The campaign stays indices 0-30, with The Final Ascent the campaign finale at 30. The flow levels are 31-34.

| Index | Id | File | Name | Theme | Signature |
|---|---|---|---|---|---|
| 31 | `aurora` | `levels/level_33_aurora` | Aurora Run | A clear night descent down a snowy mountain under a huge rippling aurora. Calm, not a blizzard; nothing like Frostbite Pass's ice fortress. | Long downhill slopes, carved half-pipes, ice grind rails along ridgelines |
| 32 | `skysurf` | `levels/level_34_skysurf` | Sky Surf | A pastel sunrise cloudscape: floating islands, wind ribbons, kites and birds. Nothing like Sky Citadel's marble or Tempest's storm. | Ring chains through the sky, wind-ribbon rails, big launch arcs |
| 33 | `hyperloop` | `levels/level_35_hyperloop` | Hyperloop | Chrome sci-fi transit tubes and mag-rails threading a dawn megastructure. Clean white and cyan, nothing like Neon City or Orbital Drift. | Rail-to-rail grinding, boost-gate chains, loop tubes as half-pipes |
| 34 | `lotus` | `levels/level_36_lotus` | Lotus Drift | A misty water garden at dusk: lily pads, flowing streams, paper lanterns, koi, wind chimes. The most meditative; nothing like Sakura Peaks' mountain fortress. | Stream slides (downhill flow water), lily-stem rails, lantern ring chains |

## FLOW tier (what "easy to finish, hard to master" means, measured)
- **Safe line (route 0):**
  - main-path hardest jump ≤ 82% (`test_m`);
  - landings ≥ 2.0 m;
  - a run of 120-170 s at normal speed;
  - **no stop-and-wait timed hazards at all.** Every hazard can be passed on the move, or is static.
- **Flow line (route 1):** a continuous speed line of rings, rails, slopes and half-pipes that chains the whole level.
  - At least **40% faster** than the safe line.
  - Hardest jump ≤ 92%.
  - It should feel like one long breath.
  - Missing a ring or rail never kills you. You drop to the safe line and lose speed, not life.
- **Checkpoints:** 7-10, so stages are long and flowing. Every checkpoint sits on both lines, or the lines rejoin at it.
- **Speed:** the flow line regularly reaches 18-30 m/s.
- **Kills:** deaths are rare. Kill zones exist only where you fall off the world, and there are generous catch platforms
  under rails and ramps.
- **Bot:** 0 respawns on every route, both without and with the temporary 1.0 s pause. Remove the pause hook before
  committing.
- **Medals:** set from the **fastest** bot route (×1.12 / 1.35 / 1.7). The lead sets them; don't touch them.
- **Required mix:** at least 4 ring chains (each 4 rings or more), at least 3 rails, at least 2 half-pipes or long slopes,
  at least 2 launch arcs (pads or barrels), and a **set-piece finale** that is pure flow.
- **Theme mechanics:** 1-3 of your own (`mechanics/<id>_*.gd`), plus the shared flow kit.

## WORKSTREAM F1: the Flow section (Sonnet, branch `flow-section`)
- **Register the 4 levels** in `Game.LEVELS` after `ascent`, each with `"flow": true`:
  - placeholder `.gd` / `.tscn` (copy the pattern of `levels/level_32_siege` at commit 8c38859);
  - `SaveData.LAYOUT_REV`;
  - placeholder `Look.THEMES` and `visual/ambience.gd` cases;
  - `# PROVISIONAL` medals and `_ZM_PROVISIONAL`;
  - the hard-coded theme, prefix and file lists in `tests/run_tests.gd` (search for `"siege"` and `level_32_siege`).
- **Helpers in `autoload/game.gd`:**
  - `is_flow(index)`, `campaign_size()`, `finale_index()` (= the last non-flow level);
  - `campaign_levels()` / `flow_levels()`.
- **Fix everything that assumes "the last LEVELS entry is the finale"** to use `finale_index()`:
  - `Game.next_level`;
  - `hud.gd` ~374;
  - `test_q_final_win_condition`;
  - the title's "Continue" target;
  - the win screen.
- **Next level from a flow level:** the next flow level, or back to the Flow section after the last one.
- **Unlocks:** Flow 1 opens at **3** campaign courses beaten, Flow 2 at **8**, Flow 3 at **14**, Flow 4 at **20**. A flow
  level is also unlocked if it is already completed, or with dev mode.
  - `Game.is_level_unlocked` handles both kinds.
  - A locked row says "beat N courses to unlock".
- **Level select:** a **FLOW** section header after the campaign list, with its own rows (medals, challenge pips, best
  time). Fully pad navigable; the scroll follows focus.
- **Main menu:** a direct **Flow** entry, or a tab into that section.
- **Cosmetics:** keep `"all"` and `"all_medals"` rules counting **campaign courses only**, so Flow stays optional. Make
  `completed_count` and `medal_count` campaign-only where those rules use them. Challenges and stats include flow levels.
- **Party pickers:** they list flow levels too.
- **Tests:**
  - unlock thresholds;
  - finale index;
  - next-level behaviour;
  - level-select pad navigation into the Flow section;
  - cosmetics rules unchanged by flow levels;
  - `test_m` on the 4 placeholders.

## WORKSTREAM F2: the flow kit (Sonnet, branch `flow-kit`)
New reusable mechanics, each with:
- a `class_name`;
- an appended `kit.*` wrapper;
- `WorldAudio` hooks (`flow_<name>_*` clips; list them);
- **route-bot support**;
- tests;
- a "Flow Gallery" area in `levels/playground.gd`.

The mechanics:
1. **Speed ring** (`kit.speed_ring(center, yaw, add_speed=6, radius=2.2, cap=30)`).
   - A glowing hoop. Passing through it adds forward speed, up to its cap.
   - Rings report to a per-level **chain** counter: consecutive rings within about 1.5 s build the chain, and higher
     chains give a bit more speed.
   - Give rings a visual guide so the next ring is readable at speed (a faint ribbon or arrows).
2. **Boost gate / boost chain:**
   - a ground arch that sets speed to a target, like `boost` but as a pass-through gate;
   - `kit.boost_chain(points)` lays a line of them.
3. **Grind rail** (`kit.rail(points: PackedVector3Array, opts)`).
   - **Snapping:** a smooth path (Catmull-Rom or Curve3D) with a visible rail mesh. Landing or jumping onto it within
     about 1.2 m snaps the player into a grind.
   - **While grinding:**
     - the rider follows the curve at their current speed, gaining a little speed on down-slopes and losing a little on
       up-slopes, with a minimum speed;
     - sparks;
     - steering is ignored except for a small lean.
   - **Leaving:** jump to leave with the full tangent velocity plus a hop. Reaching the end launches you off it.
   - **Rail-to-rail:** jumping from one rail to another must work.
   - **The rider is the real `Player`:** use a `MovingPlatform`-style carry, or set velocity each physics tick. Never
     teleport, and keep it robust to respawns.
4. **Flow surface / slope** (`kit.flow_slope(top, size, pitch_deg, yaw)`) and **half-pipe**
   (`kit.halfpipe(start, end, width, depth, opts)`).
   - On these surfaces, overspeed bleed is off, and downhill grade **adds** speed (about g·sin θ, capped).
   - Do it through the floor-query pattern: `Player.grip()` / `boost()`, or a new floor method such as `flow()` that
     `player.gd` checks with one small additive hook.
   - The half-pipe is a curved trough built from segments, so you can carve side to side without losing speed.
   - **Nothing changes on any other surface.**
5. **Launch arc:** a ramp lip that preserves speed into a predictable arc. The bot can predict it with `ballistics.gd`.

**Bot support (critical):** `tests/route_bot.gd` must drive all of these at high speed:
- new step kinds, e.g. `rail` (board, ride and dismount at a point) and `ring_line` (steer through a sequence of
  centres);
- slope and half-pipe walking with the correct speed steering;
- launch arcs.

The route-bot's ground steering may overshoot at 25 m/s, so make the speed steering correct. Use `r_*` helpers in
`levels/level_base.gd`, append-only. Build **two test courses** (`tests/flow_course*.gd`) the bot completes at speed with
0 respawns, covering every mechanic. Land in two slices: rings, gates and slopes first, then rails and half-pipes. Commit
each slice; the level agents start after slice 1.

**Docs:** `docs/FLOW_KIT.md` covers every function, every predicate, and how to wire it into a route.

## WORKSTREAM F3: the flow meter and ZEN state (Sonnet, branch `flow-zen`)
A `FlowMeter` node that the level adds **only when its `Game.LEVELS` entry has `"flow": true`**, and never in party mode.

**Filling and draining:**
- It fills while you hold high speed (≥ 12 m/s), and from ring chains, rail time, slope speed and clean landings.
- It drains when you slow below about 7 m/s, stop, take a hard landing, or respawn (a big drain).

**Tiers:** Flow 1 → 2 → 3 → **ZEN** (full and held). At each tier, add effects, all tasteful and readable:
- a gradual FOV widen;
- speed lines and wind streaks (`Fx.spawn`, `Settings.particle_scale()`);
- a stronger player trail;
- a subtle colour grade and vignette;
- in **ZEN**:
  - a calm bloom;
  - the world's hazard tells and the next ring and rail softly highlighted;
  - the music's hi layer swells while a low-pass on everything else opens up ("everything gets quiet except the music");
  - a soft ZEN banner the first time.

Also:
- **HUD:** a meter widget, a ring-chain counter, and a speed readout (m/s).
- **Results:** "Flow 87%" and "ZEN for 42 s".
- **Stat:** a new `zen_seconds` in `SaveData.STAT_KEYS`, plus a cosmetic hook for later rewards. Add a hint in
  `Cosmetics.hint`.
- **Settings toggles:** "Flow effects: Full / Reduced / Off" for motion sensitivity, and an FOV-kick toggle.
- **Integration:** use F2's ring and chain signals if F2 has landed. Otherwise read speed from the player, and expose
  `FlowMeter.add(amount, reason)` for F2 to call.
- **Tests:**
  - fill, drain and tier thresholds;
  - only on flow levels, and not in party;
  - the settings toggles;
  - the HUD widget;
  - stat banking.

## WORKSTREAM S: sound
- **S1 scores (Sonnet, branch `flow-scores`):**
  - pieces `piece_aurora`, `piece_skysurf`, `piece_hyperloop`, `piece_lotus` in `tools/gen_music.py`, each with fanfare
    and chime;
  - **driving, hypnotic, building**, like a flow-state soundtrack. The `hi` layer is the "zen" layer, lush and soaring,
    and must sit naturally on top;
  - aurora: shimmering synth pads and a pulsing arp;
  - skysurf: airy pop, guitar plucks and a light breakbeat;
  - hyperloop: a sleek electronic pulse, a sidechained bass and arpeggiated leads;
  - lotus: koto and harp ostinatos, soft taiko heartbeats, flute;
  - `--verify`, `docs/AUDIO.md`, `test_zb4b`.
- **S2 soundscapes (Haiku, branch `flow-ambience`):** ambience beds and one-shots for the 4 themes, footsteps and landings
  (snow crunch, cloud puff, metal tap, wet stone). Budgets are as before; raise them only if needed.
- **S3 mechanic clips (Haiku, later):** the `flow_*` kit clips and each level's clips, plus a wind-rush loop that scales
  with speed (`flow_wind_loop`).

## WORKSTREAM L: the four levels (Sonnet, one each, branch `flow-<id>`; after F1 and F2 slice 1 land)
- **Read:** this brief, `docs/FLOW_KIT.md`, `docs/NEW_WORLDS_BRIEF.md` (done, rules, report),
  `levels/level_23_void.gd` (structure) and `levels/level_25_toybox.gd` (a recent medium level).
- **You own:** your level files, `mechanics/<id>_*`, `visual/<id>_*`, your `Look.THEMES` entry, your `ambience.gd` case,
  and additive `route_bot` steps.
- **Report:**
  - stats for both lines;
  - bot times for every route, with and without the pause;
  - top speeds reached;
  - the clip list;
  - camera setups.
