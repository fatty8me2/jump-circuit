# Jump Circuit

A native 3D physics platformer about reading a course, building momentum and landing the jump -
solo against your own best times, or racing up to 8 friends live on the same course.

Godot 4.7.1 (stable) - typed GDScript - Jolt Physics - Windows x64.

## Play

Run `build/JumpCircuit.exe` (see *Building* below), or open the project in Godot 4.7.1 and press F5.

| Input | Action |
|---|---|
| WASD / left stick / D-pad | Move (camera relative) |
| Space / A | Jump - tap for a hop, hold for full height |
| Mouse / right stick | Orbit camera, wheel zooms |
| R / Y | Instantly back to the checkpoint (before the first checkpoint: instant restart; on the results screen: run it again). Bailing out while falling still counts as a fall |
| Esc / Start | Pause, settings |
| Arrows or D-pad, Enter / A, Esc / B | Menus: move, confirm, back |
| F3 | Developer readout (speed, grounded, jump stats, platform velocity, tilt) |
| F11 / Alt+Enter | Toggle fullscreen |

**It is hard on purpose** - obby-style stages with a checkpoint each, instant retries, a fall counter, and
momentum toys everywhere: boost strips, ice slides, bumpers, hammers that hurl you, conveyors, updrafts,
blinking blocks, sweepers and kill bricks.

Five levels: Launch Gardens, Bounce Foundry, Balance Works, Clockwork Heights, The Final Ascent.
The run timer stays hidden until you have cleared a level once (Settings can force it on or off).
Once you have a best, every checkpoint shows your split against it and the results screen shows the
time gained or lost. Leaving the window pauses a solo run; pause-menu actions that would throw away
banked checkpoints ask for a second press.
Progress, personal bests and best-run splits are saved to `user://progress.json`
(`%APPDATA%\Godot\app_userdata\Jump Circuit\`). Bests set on an earlier layout of a course are
kept in the file as `legacy_best` but no longer shown (`SaveData.LAYOUT_REV`).

## Racing friends

Title -> **Race Friends**.

* One player presses **Host a Race** and shares the 8-character room code shown in the lobby.
* Everyone else enters that code and presses **Join** or Enter. No router changes, VPN, or separate
  networking app is needed.
* Newcomers are given a colour nobody else in the lobby is wearing.
* The host picks a course and presses **Start Race**: everyone loads in, gets a synchronized 3-2-1-GO,
  and races. You see the other racers live (name tags, their colours) but never collide, so nobody can
  block or grief a jump. Standings (checkpoints reached, finish times) are top right.
* When you finish you keep watching the standings; the host sends everyone back to the lobby for the
  next course (from the results panel, or any time from the Esc menu).

Online rooms use a Cloudflare Durable Object WebSocket relay. Configure and deploy it using
[`docs/RELAY.md`](docs/RELAY.md); the game needs its Worker URL in Project Settings under
`network/relay_url`. The WebSocket carries room, roster, race and racer-pose messages; each player
still simulates their own movement locally.

How it works: each racer simulates their own character locally (zero input lag); poses are sent
30 times a second and smoothed; moving/rotating obstacles run off a clock synchronized with the
host, so every racer sees identical cycles. Tilting and collapsing pieces react only to you.

## Party Mode

A second, sillier way to play: item boxes, crazy power-ups and griefing. It only exists in Party Mode -
solo play and classic races are completely unaffected.

* **Party / Team Party** (multiplayer): in the lobby the host picks **Mode: Race** (the classic race),
  **Party** (free-for-all) or **Team Party** (two teams, Blaze vs Tide, balanced automatically; the host
  can move anyone with the *Move to* buttons). Each race is a round of the **Party Cup**: 1st 10 points,
  then 8, 6, 5, 4, 3, 2, 1; **+3 per KO** (a rival who falls or is KO'd within 4 s of your hit); **+2**
  for the first racer through each checkpoint. A round ends when everyone is home or 45 s after the
  first finisher. In Team Party a team scores the sum of its members. After each round everyone sees the
  round breakdown and the cup standings; the host picks the next course or ends the cup.
* **Party Practice** (title menu): any unlocked course with item boxes and practice dummies on the
  checkpoint lawns. Every box hands out the next power-up, so you can try them all. Nothing is saved.

Spinning **?** boxes wait in a row at the start and on every checkpoint lawn. The leader mostly rolls
small or defensive items; racers at the back get the wild stuff. Everyone always has a **Shove**.

| Input (default; rebind in Settings > Party Mode controls) | Action |
|---|---|
| F / left mouse / X, or RT | Attack (the Shove, or the transformation's attack; hold to charge) |
| E / right mouse / RB, or LT | Use the item in your slot (Hero's Tunic: throw the current tool) |
| Q / B | Shove |
| C / LB | Next tool (Hero's Tunic) |

Power-ups (display names live in `party/party_names.gd`, so they are easy to rename):

| Power-up | What it does |
|---|---|
| Nine-Tailed Fox (10 s) | Chakra cloak, ears and nine flowing tails. x1.6 speed, x1.35 jump. Tap Attack: Fox Claw, a lunging swipe that KOs. Hold: charge a Tailed Beast Bomb and release for a huge blast. |
| Hero's Tunic (10 s) | Tunic, cap, shield and the Legend Blade: a three-swing combo; hold for a Spin Attack. Use throws the current tool - Boomerang (stuns), Hookshot (yank a rival to you, or pull yourself to a wall), Bombs. Next tool cycles them. |
| Golden Surge Hair (10 s) | Spiky golden hair and a crackling aura. x1.4 speed, a double jump. Tap: Dash Punch. Hold: "Ka... me..." - release an Energy Wave beam that shoves everyone along it. |
| Thunder Cloud | Lightning strikes every rival ahead of you: stunned, then slowed. |
| Slick Puddle | Dropped behind you; the first rival through it spins out. |
| Spring Glove | A boxing glove on a spring punches the rival in front. |
| Mega Magnet (5 s) | Drags nearby rivals toward you - off beams, into gaps. |
| Shrink Ray | The rival in front shrinks for 7 s: slower, weaker jumps, knocked further. |
| Swap Warp | Trade places with the racer just ahead. |
| Balloon Shield (15 s) | Absorbs the next hit (even a KO) and bounces it back at the attacker. |
| Jetpack (5 s) | A rocket burst up and forward, half gravity, hold Jump to thrust. |
| Tornado | A tornado wanders up the course for 9 s flinging every rival it catches. |
| Gravity Bomb | Lobbed; rivals caught in the blast float helplessly in a bubble. |
| Ice Beam | Freezes the rival in front in a block of ice. |

How it works online: every hit is detected by the attacker against the victim's ghost and sent to the
victim, whose game applies it to its own character (knockback, stun, status effects, KOs). Hazards
(puddles, tornadoes, magnet pull) are checked by each player against their own character. The host
decides item-box pickups, checkpoint bonuses and the round end, so every screen shows the same scores.
Over the room relay, party packets ride the existing pose event - no relay redeploy is needed.

## Project layout

```
autoload/    game flow, settings, save data, audio, networking
resources/   MovementTuning resource (+ default_tuning.tres): every movement number lives here
player/      controller, Volt visual, orbit camera, blob shadow, remote racer ghost
mechanics/   bounce pad, moving / rotating / tilting / collapsing platforms, checkpoint, finish gate
levels/      level_base.gd (runtime), level_kit.gd (builder), one script + scene per level
visual/      themes, materials, shaders, decor helpers
ui/          title, level select, lobby, HUD, pause, settings
tests/       headless physics + integration tests, route bot, two-process multiplayer test
tools/       screenshot tool, bot capture tool, audio generator, contact sheets
docs/        DECISIONS.md, LEVEL_BRIEF.md, AUDIO.md, LICENSES.md
```

Levels are small scripts that compose reusable mechanics through `LevelKit`
(`kit.plat`, `kit.pad`, `kit.mover`, `kit.tilt`, `kit.collapse`, `kit.checkpoint`...), positioned by
"where feet go" (top-centre coordinates). Each level also annotates its intended route so the
RouteBot can play it with real physics.

## Tuning and dev tools

* Edit `resources/default_tuning.tres` in the inspector: speeds, accelerations, gravity, jump,
  coyote/buffer windows, slip thresholds, mass and impact transfer.
* F3 in game: live speed / vertical speed / grounded / floor object / platform velocity / board tilt /
  last jump height and distance / course clock.
* Launch with `-- --dev` to unlock every level and enable F6 (teleport to next checkpoint).

## Tests

```
tools\Godot_v4.7.1-stable_win64.exe --headless --path . --import
tools\Godot_v4.7.1-stable_win64.exe --headless --path . res://tests/run_tests.tscn
```

Options after `--`: `--only=<substring>`, `--level=<0-4>`, `--fps=<cap>`. A selection that matches
nothing exits with code 2. Any engine or script error logged during a test fails that test, and a
per-test watchdog fails a test that hangs.
The suite measures the controller (speed, jump heights/distances, coyote, buffer, air control),
checks slopes/seams/ceilings/terminal-velocity landings, every mechanic (pad consistency and
no double triggers, riding and takeoff inheritance on movers and spinners, tilt response/limits/
reset, collapse/reset), validates every level's required jumps against the measured jump envelope,
plays every level start-to-finish with the RouteBot, and checks checkpoint/fail/respawn/reset,
save round-trips and the final win.

Multiplayer localhost integration harness (direct ENet, for regression checks):

```
start /b tools\Godot_v4.7.1-stable_win64.exe --headless --path . res://tests/mp_test.tscn -- --role=host
tools\Godot_v4.7.1-stable_win64.exe --headless --path . res://tests/mp_test.tscn -- --role=client
```

Add `--port=<n>` to both commands to use another UDP port (default 24577). Each process gives up
after 90 s (exit code 1) if the other one never shows up. The tests never try UPnP.

Visual review:

```
tools\Godot_v4.7.1-stable_win64.exe --path . res://tools/shot.tscn -- --level=0 --follow --out=C:/tmp/a.png
tools\Godot_v4.7.1-stable_win64.exe --path . res://tools/bot_shots.tscn -- --level=0 --every=1.5 --out=C:/tmp/run
```

## Building

See `docs/BUILD.md`.
