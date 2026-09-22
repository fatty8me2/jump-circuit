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
| R / Y | Instantly back to the checkpoint (at the start of a level: instant level restart) |
| Esc / Start | Pause, settings |
| Arrows or D-pad, Enter / A, Esc / B | Menus: move, confirm, back |
| F3 | Developer readout (speed, grounded, jump stats, platform velocity, tilt) |
| F11 / Alt+Enter | Toggle fullscreen |

**It is hard on purpose** - obby-style stages with a checkpoint each, instant retries, a fall counter, and
momentum toys everywhere: boost strips, ice slides, bumpers, hammers that hurl you, conveyors, updrafts,
blinking blocks, sweepers and kill bricks.

Five levels: Launch Gardens, Bounce Foundry, Balance Works, Clockwork Heights, The Final Ascent.
The run timer stays hidden until you have cleared a level once (Settings can force it on or off).
Progress and personal bests are saved to `user://progress.json`
(`%APPDATA%\Godot\app_userdata\Jump Circuit\`).

## Racing friends

Title -> **Race Friends**.

* One player presses **Host a Race**. The lobby shows the LAN address(es) to share, and tries UPnP to
  open UDP port **24565** for internet play (the result is shown in the lobby).
* Everyone else types the host address and presses **Join**.
* The host picks a course and presses **Start Race**: everyone loads in, gets a synchronized
  3-2-1-GO, and races. You see the other racers live (name tags, their colours) but never collide,
  so nobody can block or grief a jump. Standings (checkpoints reached, finish times) are top right.
* When you finish you keep watching the standings; the host sends everyone back to the lobby for
  the next course.

Internet play without touching the router: if UPnP is unavailable, either forward UDP 24565 to the
host PC, or put everyone on a virtual LAN (Tailscale, ZeroTier, Radmin VPN...) and use that address.
Windows will ask to allow the game through the firewall the first time you host - allow it.

How it works: each racer simulates their own character locally (zero input lag); poses are sent
30 times a second and smoothed; moving/rotating obstacles run off a clock synchronized with the
host, so every racer sees identical cycles. Tilting and collapsing pieces react only to you.

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

Options after `--`: `--only=<substring>`, `--level=<0-4>`, `--fps=<cap>`.
The suite measures the controller (speed, jump heights/distances, coyote, buffer, air control),
checks slopes/seams/ceilings/terminal-velocity landings, every mechanic (pad consistency and
no double triggers, riding and takeoff inheritance on movers and spinners, tilt response/limits/
reset, collapse/reset), validates every level's required jumps against the measured jump envelope,
plays every level start-to-finish with the RouteBot, and checks checkpoint/fail/respawn/reset,
save round-trips and the final win.

Multiplayer (two processes, localhost):

```
start /b tools\Godot_v4.7.1-stable_win64.exe --headless --path . res://tests/mp_test.tscn -- --role=host
tools\Godot_v4.7.1-stable_win64.exe --headless --path . res://tests/mp_test.tscn -- --role=client
```

Visual review:

```
tools\Godot_v4.7.1-stable_win64.exe --path . res://tools/shot.tscn -- --level=0 --follow --out=C:/tmp/a.png
tools\Godot_v4.7.1-stable_win64.exe --path . res://tools/bot_shots.tscn -- --level=0 --every=1.5 --out=C:/tmp/run
```

## Building

See `docs/BUILD.md`.
