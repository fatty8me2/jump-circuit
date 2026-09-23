# EFFECTS pass brief (particles)

Owner (2026-09-23): "put a heavy emphasis on cool particle effects". Other agents are extending the levels (their own
ambient/set-piece particles) and building a party mode (power-up effects). YOUR job: make the shared moves and machines
and the core game feel spectacular with particles - without changing any gameplay.

Read first: player/player_visual.gd (existing `_make_burst` / `_make_trail` / dust style), player/player.gd (signals:
jumped, landed, bounced, knocked, teleported, wall_run_started, wall_jumped, mantled; `is_wall_running()`,
`wall_side()`, `is_mantling()`), mechanics/*.gd, visual/look.gd, levels/level_kit.gd (`_soft_dot`), docs/EXTENSION_BRIEF.md.

## Deliver
1. **A small shared FX library** `visual/fx.gd` (class_name Fx): factories for the effects you build (bursts, trails,
   sparks, rings/shockwaves, embers, smoke puffs, light flashes), soft textures cached, sensible defaults, one-shot
   helpers that free themselves. Others may use it later.
2. **Player moves** (player/player_visual.gd + wiring in player.gd `connect_feedback()` only):
   - wall run: a sparking / glowing streak where the feet meet the panel, cyan motes shed behind, a burst on latch;
   - wall jump: a radial kick burst off the wall + a short trail;
   - mantle: dust puff and lip sparks on grab, a small hop puff on top;
   - speed: wind streaks / speed lines once the player is well over run speed (boosts, pads, slides), fading smoothly;
   - big landings: a ground shockwave ring + debris puffs scaled by impact; bounce pads: a spring ring + sparkles;
   - respawn/teleport arrival and checkpoint banking: brighter, more satisfying bursts than now (keep the veil).
3. **The new machines** (visual-only edits inside mechanics/wall_run_panel.gd, ledge_block.gd, laser_gate.gd, piston.gd,
   crusher.gd, warp_portal.gd): drifting glints along wall-run lines; gleam travelling along ledge lips; laser emitters
   crackle while charging, sparks + heat haze along the beam when on, a snap burst on switch-on; piston steam venting on
   retract and an impact spark fan on the punch; crusher dust ring + debris on slam, falling grit while shuddering;
   portals: a swirling vortex of particles in the ring, streaks pulled into the entry, an arrival burst at the exit.
4. **The existing mechanics** (visual-only): boost strips (streaming chevron sparks), bounce pads (idle shimmer + launch
   ring), bumpers (hit flash sparks), hammers (motion streak on the head), sweepers (glow trail on the bars), blink
   platforms (dissolve/materialise particles), collapsing platforms (crumble debris), wind zones (already streaked -
   polish), kill bricks (subtle rising red embers), checkpoints (activation fountain), finish gate (confetti/firework
   finale).
## Rules
- **No gameplay change**: collision shapes, timings, positions, speeds, areas and every number that affects play stay
  exactly as they are. Only add child visual nodes / materials. The full test suite must stay green and the bot times
  in test_n must not change (they are deterministic).
- You own: `visual/fx.gd` (+ new files under visual/), `player/player_visual.gd`, the `connect_feedback()` function in
  player/player.gd (nothing else in that file), and the visual parts of every file in `mechanics/`.
  Do NOT edit level scripts, levels/level_kit.gd, levels/level_base.gd, autoload/, ui/, tests/route_bot.gd.
  Other agents create new `mechanics/<level>_*.gd` files - leave those alone.
- Performance: tasteful density - many modest emitters (amount 8-60), unshaded soft billboards, sensible
  visibility AABBs, `local_coords` where the effect should follow its node. Always-on emitters on repeated pieces
  (every boost strip, every pad) must be cheap. Respect `Settings` if it has a quality/particles option (check
  autoload/settings.gd; if there is none, do not add one - report it instead).
- Headless runs never compile particle shaders. Verify visually with the windowed screenshot tool and grep its output
  for ERROR / SHADER lines:
  `timeout 120 $G --path $W res://tools/shot.tscn -- --level=<i> --cam=x,y,z --look=x,y,z --out=<abs>.png [--player=x,y,z] [--time=s]`
  (output folder must exist). Look at the PNGs with the Read tool. For effects that need an event (a latch, a slam),
  build a tiny scratch scene under tests/scratch/ that stages it and screenshots it (delete it afterwards). Do NOT
  launch the game normally or run tools/bot_shots.tscn (they can touch the owner's real save file).
- Engine: `/c/Users/fatty/Desktop/PlatformerJumpPuzzle/tools/Godot_v4.7.1-stable_win64.exe` with `--path <worktree>`;
  run `--headless --import` first; wrap every run in `timeout`. Discard CRLF-only *.import churn. Heredocs truncate at
  apostrophes - use the Write/Edit tools for file content.
- Verify with the whole suite minus the long bot test while iterating, then once the full suite including test_n.

## When done
Commit on your worktree branch (your files only), message ending with
`Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Do not push or merge. Report every effect added,
screenshots taken, test results (and that bot times are unchanged), branch + commit.
