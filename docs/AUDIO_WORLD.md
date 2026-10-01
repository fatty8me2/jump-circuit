# Jump Circuit - World Sound Effects

Per-map footsteps and landings, the player's movement sounds and every machine's
sounds. Like the rest of the game's audio they are **original**: synthesised from
maths and seeded noise by `tools/gen_world_sfx.py` (which borrows the helpers in
`tools/gen_audio.py`). No samples are used, so no third-party licences apply.

## Regenerating

```
python tools/gen_world_sfx.py            # generate all 321 clips into audio/, then verify
python tools/gen_world_sfx.py --only=manor,carrier   # just those maps' generators (gen_<name>), then verify all
python tools/gen_world_sfx.py --verify   # only check the files on disk
```

* Requires Python 3 and numpy. Takes about 25 s.
* Deterministic: each clip has its own RNG, seeded from `gen_audio.SEED` plus the
  CRC of `"world_" + name`, so re-running produces bit-identical files.
* Afterwards run `tools/Godot_v4.7.1-stable_win64.exe --headless --path . --import`.
  New WAVs get default import settings. `edit/loop_mode=0` ("Detect From WAV")
  picks the loop up from the `smpl` chunk.

The verifier checks every clip in the generator's table. It checks the duration,
the format (44.1 kHz mono 16-bit), for NaN or Inf, and the level. For one-shots it
checks that the first and last samples are near zero. For loops it checks the seam:

* the sample step across the wrap must be no larger than 1.5x the 99.9th-percentile step inside the loop;
* the curvature (second difference) across the wrap must pass the same test;
* the 40 ms window across the wrap must be no quieter than the quietest windows in the loop (a faded-out end would fail).

It also checks the total size, which is about 18.5 MB of a 30 MB budget.

## Formats and levels

| Group | Format | Level |
|-------|--------|-------|
| One-shots | 44.1 kHz mono 16-bit | peak normalised to -3 dBFS, DC and subsonics removed, fade in and fade out |
| Footsteps and landings (`step_*`, `land_*`) | same | **loudness-matched** instead: the loudest 80 ms is scaled to an A-weighted -25 dB (steps) or -23 dB (landings), never above a -3 dBFS peak. A clicky glass step and a soft grass step at the same peak differ by about 8 dB to the ear. Soft floors that can't reach the target stay at -3 dBFS peak, so grass and wet sand are a little quieter, which is natural. |
| Loops | same, plus a `smpl` whole-file forward loop | peak -3 dBFS, no fades |

**Loops are rendered circularly.** Noise is filtered in the FFT domain over the
whole loop (`cband`, `cnoise`). Time-varying filters (`csvf`) run over three
periods, and the settled middle one is kept. Every tone has a whole number of
cycles (`cyc`). Modulators are sums of whole-cycle sines (`clfo`, `crand`).
Events that run past the end wrap round to the start (`cplace`). The only
processing after that is a gain, so the seam can't click. Loops are 1 to 2.5 s long (the manor's music-box waltz, 3.6 s, is the one exception).

## Building blocks (in the generator)

* **Modal synthesis**: `modes()` sums exponentially damped sines. The strike
  hardness rolls off the high modes (a soft hit barely excites them). `bar_modes()`
  gives free-free beam ratios (1, 2.756, 5.404, 8.933, 13.34) for grating bars,
  pawls, brass rods and chain links. `plate_modes()` gives the lowest modes of a
  simply supported plate, f ~ m² + (n/aspect)², for deck plates, glass panels and
  the crusher's block. Higher modes decay faster.
* **Contact transients**: `click()` is band-passed noise with a 0.7 to 8 ms decay.
  `thud()` is a body blow: a pitched-down sine with a couple of harmonics.
* **Air and water**: `whoosh()` is noise through a state-variable band-pass that
  rises to the moment of passing, then falls (a Doppler shape). `bubble()` is a
  Minnaert bubble: a decaying sine whose pitch rises. `grains()` scatters short
  noise grains (gravel, sparks, sizzle, debris). `crackle()` makes sparse sharp ticks.
* **Friction and voices**: `creak()` is a stick-slip. A jittered impulse train runs through damped
  resonances (a snapjaw's hinge, basalt or sandstone grinding, a creak in the ice). `reson()` is a
  formant gain, used for the leviathan's voice. `pew()` is the dispersive chirp of cracking ice.
* **Rooms**: `space()` convolves with a synthetic room impulse response whose high
  band decays faster than its low band (for the foundry hall, the clock tower and
  the station interior).
* Every building block ends with a 4 ms taper, so a ring cut off by its buffer
  can't leave a step in the mix.

## Runtime

* `mechanics/world_audio.gd` (`WorldAudio`) is a thin layer over `Sfx`:
  * **Headless runs make nothing** (tests, bots, route checks). `WorldAudio.loop()`
    returns null and `WorldAudio.at()` returns at once. The per-frame audio work
    (sweeper, pendulum, blink warning, data stream, pallets, loose props) is behind
    `WorldAudio.enabled()`. The speed-driven loops only update when their emitter
    exists.
  * `at(node, clip, pos, volume, radius)` plays a pooled 3D one-shot, but only when
    the camera (the listener) is within `radius`. A level full of lasers switching
    far away never fills `Sfx`'s 16 positional voices.
  * `loop(clip, parent, db, max_distance, unit_size, active)` wraps
    `Sfx.loop_at()`. It starts at a random point in the loop, so identical machines
    side by side don't phase against each other. It also adds a `Gate` (a Timer, 5
    checks a second) that pauses the stream while the machine is idle
    (`set_active(p, false)`) or the listener is beyond its `max_distance`. The gate
    re-applies after the game is unpaused, because the engine un-pauses every stream
    it paused.
  * `once(key, secs)` stops identical machines that fire on the same beat from
    stacking copies of one clip (the clockwork pallets, the billboard glitches).
  * `local_player(node)` finds the level's Player (for the sweeper, the data stream and the pallets).
* `player/player_audio.gd` (`PlayerAudio`) holds the local player's continuous
  sounds. `Player.connect_feedback()` creates it only when `WorldAudio.enabled()`,
  so race ghosts (RemoteRacers), test players and bot players never get one. Its
  loops ride on the player with distance attenuation off: air rush, wall-run
  scrape and ice slide. It also plays the boost-strip zing.
* The physics never reads any of this. Obstacles stay pure functions of
  `Game.course_time`. Every hook only reads state and plays a sound on an edge
  that the visuals already detect.

## Player: per-map footsteps and landings

`Player._on_footstep()` plays `Sfx.themed("step")`. The landing plays
`Sfx.themed("land")`, at a volume scaled by impact. Without a map clip they fall
back to the plain `step` / `land`. Footstep pitch variation and the pitch-up on
slick surfaces are unchanged. Each map has 4 step variants (0.16 s) and 3 landing
variants (0.40 s). A variant re-rolls the modes (by ±2 to 3 %), the noise, the
heel-to-toe gap (24 to 40 ms) and the toe level. A landing uses the same material
model struck harder, with a heavier body, longer tails and more debris.

| Map | Files | Synthesis |
|-----|-------|-----------|
| Launch Gardens | `step_gardens_1..4`, `land_gardens_1..3` | Soft earth under grass: a damped 125-150 -> 62 Hz pat and 120-900 Hz soil noise (heel, then toe). 30 to 100 tiny 2.5-9 kHz grains are the blades rustling, with 6 to 28 lower 0.5-2.2 kHz grains for clods and pebbles, all low-passed at 9 kHz. The landing adds a 90 -> 42 Hz body thud. |
| Bounce Foundry | `step_foundry_*`, `land_foundry_*` | Steel grating over a void: a hard 2-11 kHz click, free-bar modes from a 360-460 Hz fundamental (the grating bars), a 185-225 Hz hollow cavity tone, and 1 to 6 delayed re-strikes of the bars (the grating chattering in its frame). The landing adds a 95 -> 45 Hz boom and a 0.9 s industrial-hall reverb. |
| Balance Works | `step_balance_*`, `land_balance_*` | Painted steel deck on timber: plate modes (f11 220-260 Hz, aspect 1.6) damped short by the paint, three low-Q wood modes (about 520 / 900 / 1450 Hz) for the bearers, and a 135 -> 72 Hz body. The landing adds a heavier thud, a few grit grains and a short reverb. |
| Clockwork Heights | `step_clockwork_*`, `land_clockwork_*` | Waxed oak boards with brass inlay: five oak modes (about 220 to 2250 Hz, 5 to 30 ms decays), a warm 150 -> 88 Hz knock, a faint brass bar shimmer from a 1150-1400 Hz fundamental, and a small clock-tower room. |
| Coral Depths | `step_reef_*`, `land_reef_*` | Wet sand that sucks at the foot: noise through a band-pass sweeping down from 850-1000 to 320 Hz. Brittle 1.2-4.5 kHz coral-crunch grains, tiny bubbles in the pores, and a soft 105-125 Hz body. Everything is low-passed at 3 kHz (under water). |
| Orbital Drift | `step_orbital_*`, `land_orbital_*` | Thin deck plate over a service void: a bright 3-13 kHz click, ten plate modes (f11 290-340 Hz) that ring for about 0.1 s, a 2.1-2.5 kHz bar "tink", a 110-125 Hz hollow boom, and a metallic station-interior reverb. The landing adds three rattles of the plate. |
| The Final Ascent | `step_ascent_*`, `land_ascent_*` | Hard glass over a neon panel: a very sharp 2.5-15 kHz tick and high-Q glass plate modes (f11 650-760 Hz, partials to 9 kHz). A short 120 Hz-locked electric buzz is the panel answering, over a thin 170 Hz body. |
| Xeno Wilds | `step_xeno_*`, `land_xeno_*` | Spongy alien moss over a chitin crust: a wet squelch (noise through a band rising from 260-320 Hz to about 1 kHz as the moss compresses), a soft 115-135 -> 70 Hz body, 6 to 24 brittle 1.8-6.5 kHz crunch grains with small hollow chitin pings (1.5-2.6 kHz and 3.4-4.8 kHz modes), and a faint pore hiss. The landing adds a thud and the moss springing back (a soft 70 -> 105 Hz "bwum"). |
| Cinder Peak | `step_volcano_*`, `land_volcano_*` | Loose cinder over basalt: four dead stone modes (about 330 / 650 / 1100 / 1800 Hz, 4-12 ms), a firm 140-160 -> 80 Hz knock and a gritty scuff, 25 to 85 clinker grains (0.9-7 kHz) and a few glassy 3.5-9.5 kHz ticks of vesicular glass. The landing adds a 100 -> 55 Hz thud, four loose clinkers settling 50-200 ms later and a puff of ash. |
| Frostbite Pass | `step_glacier_*`, `land_glacier_*` | Packed snow over hard ice: a run of 40 to 130 crunch grains (0.5-4 kHz, cold grains fracturing) with a few 0.9-1.8 kHz squeaks, over a dull 120-140 -> 70 Hz pat. The ice answers with a hard 2.5-12 kHz tick and three glassy modes (about 2 / 4.3 / 7 kHz). The landing adds a thud and a puff of powder. |
| Scarab Sands | `step_desert_*`, `land_desert_*` | Soft sand over sandstone: a dry 0.6-5 kHz shush that swells as the sole settles, a muffled 110-130 -> 62 Hz pat, a gritty scuff and a short, dead sandstone knock (about 460 / 975 / 1750 Hz), with 25 to 85 fine grains trickling off (2.5-9 kHz). The landing adds a thud and a spray of sand. |
| Phantom Manor | `step_manor_*`, `land_manor_*` | Creaky old oak boards laid over stone: a hollow, dry knock with the loose board's low modes (about 170 / 360 / 690 / 1200 Hz, 10-40 ms), a 125-145 -> 70 Hz body and grit scuffing on the flags beneath. Most steps (and every landing) end in a short creak as the board flexes (a 60-150 per second stick-slip through 420-2000 Hz resonances), all in a 1.1 s stone hall. The landing adds a thud and dust off the boards. |
| Storm Armada | `step_armada_*`, `land_armada_*` | A wet wooden deck in the rain: a plank knock (about 290 / 610 / 1100 / 1750 Hz), a 130-150 -> 75 Hz body, the film of water slapping (0.5-5 kHz), 12 to 52 droplets splashing away (1.5-7 kHz grains) with a few small bubbles, and a faint suck as the boot lifts. The landing adds a thud and the puddle thrown up. |
| Sugar Rush | `step_candy_*`, `land_candy_*` | Sugar-crusted candy over something soft: a squish (noise through a band rising from 380-450 Hz to about 1.4 kHz as it squashes), a 140-165 -> 85 Hz body, a spray of 35 to 115 bright sugar-crystal grains (2-9.5 kHz) with glassy 4-11 kHz ticks, and a springy little 150 -> 190 Hz rebound with an 11 Hz wobble. The landing adds a thud and a jelly-like 85 -> 130 Hz "boing". |
| Super Carrier | `step_carrier_*`, `land_carrier_*` | The flight deck: thick steel under a gritty non-skid coating, so it barely rings. A boot-heel click, a dense rasp of 60 to 140 tiny grit grains (1.2-7 kHz) and a sole scuff, a heavy 150-175 -> 90 Hz body and just a hint of plate modes (f11 170-200 Hz, very short). The landing adds a thud and the hull's deep answer through the deck (plate modes from 70-85 Hz). |
| Sakura Peaks | `step_sakura_*`, `land_sakura_*` | Polished cypress boards of a temple floor raised over stone: a tight, warm knock (about 260 / 560 / 960 / 1600 Hz, 6-25 ms), a slightly hollow 160-185 Hz body under the boards and a soft scuff of a sock on the polish. On about a third of the steps (and most landings) the floor's clamps chirp faintly underfoot (a nightingale floor: a 1.5-1.9 -> 2.3-2.8 kHz squeak), in a small hall. The landing adds a thud and the stone below (dead modes about 350 / 750 / 1300 Hz). |
| Jungle Temple | `step_jungle_*`, `land_jungle_*` | Mossy temple stone under leaf litter: a dull, dead stone knock (about 360 / 730 / 1220 Hz, 5-10 ms) and a 125-145 -> 70 Hz body, muffled by a damp pad of moss (a soft squelch rising from 300-380 Hz to about 0.9 kHz), with 30 to 100 crackling leaf grains (1.2-8 kHz) and a few twigs (0.4-1.5 kHz). The landing adds a thud and the leaves settling. |
| Wild West Heist | `step_frontier_*`, `land_frontier_*` | The dry, dusty roof boards of a wooden boxcar: a plank knock (about 300 / 640 / 1120 / 1950 Hz), the hollow car under it booming low (115-135 Hz, ringing 50-110 ms), 20 to 60 dust and grit grains (1.5-7.5 kHz), and often a loose roofwalk board clacking a moment later. The landing adds a thud and a puff of dust. |
| Neon City | `step_neon_*`, `land_neon_*` | A wet steel rooftop: a sheet-metal panel's dull ring (plate modes from f11 230-270 Hz, damped by the water on it), a 135-155 -> 80 Hz body, the boot slapping the puddle (0.6-6 kHz), 16 to 61 droplets spraying off with a few small bubbles, in a short open reverb. The landing adds a thud and the puddle thrown up. |

## Player: movement

| File | Length | Synthesis | Triggered |
|------|--------|-----------|-----------|
| `wallstep_1..4` | 0.13 s | The wall-run panel (the same dark slab in every map): plate modes (f11 260-300 Hz, aspect 2.2), a 150-175 Hz hollow tone and a click, with a few spark ticks. | `Player._on_footstep()` while wall running (replaces the old `step` reuse). |
| `wallrun_latch` | 0.35 s | A heavier panel knock, a 700 -> 2100 Hz electric zing with its octave, a crackle of 22 sparks, and a swept 1.5 -> 4.5 kHz scrape onset. | `wall_run_started` |
| `wallrun_scrape` (loop) | 1.0 s | Friction hiss (1.6-7.5 kHz) with fast stick-slip jitter, a 150-700 Hz grind, a faint 2.6 kHz squeal and about 60 sparks a second. | `PlayerAudio` while `is_wall_running()`: fades in at 25/s and out at 9/s, -15 dB, pitch up slightly with speed. |
| `wallkick_1..3` | 0.40 s | A heavy push-off from the panel (panel knock plus a 120 -> 55 Hz thud), sparks, and a whoosh peaking at 3-3.8 kHz 0.1 s in. | `wall_jumped` |
| `mantle_1..3` | 0.45 s | Two metal hand slaps 35-60 ms apart (bar modes from a 1.05-1.3 kHz fundamental, slap noise and a thud), two foot scuffs, and Volt's servos hauling up (a 250 -> 640 Hz whirr with harmonics), ending in a foot set at 0.34 s (the mantle takes 0.34 s). | `mantled` |
| `land_heavy` | 0.8 s | A deep 72 -> 30 Hz body blow with harmonics, a chest thump, a crack and debris grains, and a short descending servo groan (the knees soaking it up). | Layered under the themed landing when the impact is above 24 m/s. |
| `air_rush` (loop) | 2.5 s | Your own wind: pink-tilted broadband turbulence breathing with slow gusts, a buffeting 28-170 Hz low end, a thin whistle wandering around 1.15 kHz, and high flutter. | `PlayerAudio`: silent below 9 m/s, full by 26 m/s (squared curve), -7 dB at full, pitch 0.75 -> 1.25, attack about 0.15 s and release about 0.4 s. Cut on respawn. |
| `boost` | 0.6 s | A 480 -> 2500 Hz electric zing with a slight FM shimmer and a detuned chorus, a whoosh (700 -> 5200 -> 1500 Hz), a shove thump and a spark crackle. | `PlayerAudio`, once for each boost strip you run onto. |
| `ice_slide` (loop) | 1.2 s | The smooth hiss of a sole on ice (2.5-10 kHz), a softer 0.6-2.2 kHz "shh", a little skate rumble, an occasional 3.4 kHz squeak and rare ice ticks. | `PlayerAudio` while grounded on a surface with grip < 1, scaled by speed, -11 dB. |

Jump, bounce and respawn are unchanged. A pad can give its own bounce voice with
`bounce_clip()`. The Player remembers the pad that launched it in `last_pad` (read
only by feedback). The reef's jellyfish use this.

## Machines

All positional. Distances are the one-shot's audible radius or the loop's `max_distance`.

| File | Length | Synthesis | Triggered |
|------|--------|-----------|-----------|
| `laser_hum` (loop) | 1.0 s | A 110 Hz transformer stack with strong even harmonics, a noise buzz gated by the hum's own waveform, a 3520/3524 Hz whine beating at 4 Hz, a 2 Hz wobble and crackle. | LaserGate. It **spins up through the warning** (pitch 0.5 -> 1, +16 dB as the charge builds), runs while the beam is on, and pauses when it is off. -13 dB, 20 m. The trimmer and scanner beams are always on, so they just hum. |
| `laser_on` / `laser_off` | 0.40 / 0.35 s | On: a 150 -> 2400 -> 880 Hz zap with a fifth, a crack, a thump, a hum onset and a gated sizzle. Off: a 1300 -> 55 Hz power-down with harmonics, a click and a fizzle. | The beam switching (35 m). |
| `blink_appear` / `blink_vanish` | 0.40 / 0.45 s | Appear: a band sweep of 400 -> 6000 Hz and two chime notes (C6, G6), with a soft "becoming solid" thud. Vanish: a descending tone quantised into 28 ms steps (a glitchy dissolve), a falling dispersal sweep and scattered sparkles. | BlinkPlatform on/off (30 m). |
| `blink_tick` | 0.06 s | A soft 2.2 kHz electronic tick. | Each 0.16 s flicker of the vanish warning. |
| `crusher_shudder` | 0.45 s | A stick-slip groan of the guides (a jittered impulse train through 180/430/950/1900 Hz resonances), rattling chains and a building rumble. | Crusher, as its shudder starts. |
| `crusher_slam` | 1.2 s | A crack, a 60 -> 27 Hz sub boom, the steel block's plate modes (f11 140 Hz), the four teeth clanging, a floor thump, 38 debris grains, a dust hiss and a hall reverb. | The frame the press hits the floor (55 m), at the floor point. |
| `crusher_rise` | 0.9 s | A hydraulic whine climbing from 150 to 265 Hz with harmonics, the valve's hiss and a fluid gurgle. | The press starting its haul back up. |
| `piston_fire` / `piston_clank` / `piston_retract` | 0.35 / 0.45 / 0.7 s | Fire: a pneumatic blast (600-8000 Hz), a whump and a valve ping. Clank: the ram hitting its end stop (bar modes from 255 Hz, a crack, a thud, two rattles, a small room). Retract: a steam hiss pulsing at 17 Hz over a falling servo. | Piston punch start, hold start and retract start. The old `whack` still plays when it shoves you. |
| `sweep_whoosh_1..3` | 0.5 s | A whoosh rising to 1.9-2.5 kHz as the bar passes, then falling, with a 100 Hz-gated electric sizzle (the glowing kill bar) and a low air thump. | Sweeper: when a bar is 0.21 s from sweeping past a player standing within its reach, so the rush peaks as the bar goes by. Works for either spin direction. |
| `pendulum_whoosh_1..2` | 0.7 s | A heavier whoosh (140 -> 800-1000 -> 240 Hz) with a low 70 -> 96 -> 58 Hz "vwoom". | Pendulum: timed to peak as the head passes the bottom of its swing (twice a period, 30 m). |
| `conveyor_hum` (loop) | 1.0 s | A 50 Hz motor stack, a 610 Hz rotor whine, 10 roller clicks per loop (small modal pings) and belt hiss. | Conveyor strips (-17 dB, 18 m, pitch follows belt speed). |
| `wind_loop` (loop) | 2.0 s | Moving air: tilted broadband noise with gusts, a swirling band around 700 Hz, a faint 1.6 kHz whistle and low buffeting. | WindZone / updraft columns (-12 dB, half the box's size + 12 m, pitch follows push). |
| `motor_hum` (loop) | 1.0 s | The thruster pods' soft hover hum (82/83 Hz beating, harmonics) with airy noise. | MovingPlatform (-21 dB, 11 m) and RotatingPlatform (pitch 0.8, 12 m). Close up only. |
| `warp_whoosh` | 0.9 s | A swirling vortex (band-pass wobbling at 3 -> 19 Hz as it rises to 4.5 kHz), five detuned shimmer tones gliding up an octave, the exit's 95 -> 38 Hz whump and pentatonic sparkles. | WarpPortal, flat (the warp is the runner's own experience). Replaces the old `go` reuse. |
| `warp_hum` (loop) | 1.5 s | A low swirling drone (55/110/110.5/165 Hz), a slowly sweeping band and a faint 880/880.5 Hz shimmer. | Both portal rings (the exit is pitched up 12 %), -16 dB, 14 m. |
| `prop_bonk_1..3` | 0.3 s | A rubbery bonk: a 160-190 Hz thud, a hollow 330-420 Hz ring, a click and a slap. | Loose balls, when their velocity changes by more than 3 m/s in one tick (a bounce or a kick). Read only, rate-limited to one per 0.18 s, volume scaled by the change. |
| `platform_reform` | 0.4 s | A soft rising shimmer that settles with a stony tap. | A collapsed platform growing back. |
| `ladle_tip` | 0.7 s | The drum grinding over (stick-slip through 140/330/720 Hz) with three chain clanks. | FoundryLadle warning (the roll-over). |
| `ladle_splash` | 0.7 s | The molten sheet hitting the channel: a low whoomph, a thud, 160 sizzle grains and splatter. | The pour starting. |
| `ladle_pour` (loop) | 1.5 s | A low-tilted roar with bubbling modulation, 26 low "glug" bubbles, dense 3-11 kHz sizzle and pops. | While pouring (-7 dB, 28 m, at mid-height). |
| `ladle_hiss` | 1.0 s | A steam hiss with dying crackle. | The drum rolling back (when the steam shows). |
| `jelly_bounce_1..2` | 0.55 s | A squishy "bloop" (a 150-175 -> 480-560 Hz glide with a decaying 9 Hz wobble), a wet squish and nine rising bubbles, low-passed at 4.2 kHz. | ReefJelly's `bounce_clip()`: replaces the pad boing on the reef's jellyfish. |
| `vent_rumble` | 0.8 s | A swelling 25-170 Hz rumble with low bubble pops and grit. | ReefVent warning start. |
| `vent_burst` | 0.8 s | A whoomph and a thud with a spray of 70 bubbles (300-2000 Hz). | The eruption starting. |
| `vent_loop` (loop) | 1.5 s | A roaring bubble column: 30-320 Hz roar, 180 bubbles, a mid hiss, low-passed. | While erupting (-6 dB, 30 m). |
| `surge_loop` (loop) | 2.0 s | An underwater rush (60-900 Hz), a swirling band around 380 Hz, bubbles, low-passed at 2.8 kHz. | ReefSurge. The volume and pitch follow the surge's strength, including its telegraph. |
| `thruster_ignite` / `thruster_cutoff` | 0.6 / 0.6 s | Ignite: two igniter snaps, a broadband whoomph, a thud and crackle. Cut-off: the roar's tail with its low-pass closing (6 kHz -> 250 Hz), a gas hiss and a thump. | OrbitalThruster burn start and end (45 m). |
| `thruster_burn` (loop) | 1.2 s | A rocket roar: tilted broadband noise with "tearing" modulation, a 380-950 Hz formant, a rumbling low end and 300 crackles a second. | While burning (-5 dB, 35 m). |
| `thruster_cough_1..3` | 0.16 s | A sputter: a noise pop, a 95 -> 48 Hz thump and crackle. | Each flicker of the pre-burn warning (every 0.12 s). |
| `flare_alarm` | 0.14 s | A klaxon beep: 1150 Hz with odd harmonics, a major-third partner and 30 Hz vibrato. | Each strobe of the flare gate's warning (70 m, so it carries down the deck). |
| `flare_launch` | 1.0 s | A deep 55 -> 28 Hz whoomph under a rising 200 -> 3200 Hz roar, crackle and a low rumble. | The flare front launching. |
| `flare_roar` (loop) | 1.5 s | A plasma wall: bright tilted noise with fast tearing, a 6-12 kHz sizzle, a low rumble and dense crackle. | Rides on the moving front while it sweeps (-3 dB, 45 m). |
| `gravity_hum` (loop) | 2.0 s | A floating field drone (55/55.5/82.5/110.5/165 Hz) with a slow 1.5 Hz wub, a pale 1320/1320.5/1980 Hz shimmer and airy noise. | OrbitalGravityBay (-9 dB). A pulsing bay's hum **stutters with the frame's flicker** before cutting out. |
| `gravity_on` / `gravity_off` | 0.6 s | The drone chord gliding up from 0.35x (or down to 0.3x) with the wub speeding up (or slowing), and a swept band. | A pulsing bay switching. |
| `escape_tick` / `escape_tock` | 0.35 s | A brass pawl (bar modes from 1900 or 1400 Hz), the pallet's heavy clunk (150 or 105 Hz with a body), three ratchet clicks, a brief gear whirr and a small room. | ClockworkPallet on each beat: tick as it snaps up, tock as it drops. Each plays once per beat, not once per pallet. |
| `scanner_servo` (loop) | 1.0 s | A 420 Hz servo whine with a 70 Hz gear hum, rail rumble and 8 wheel clicks. | BalanceScanner carriage. The volume and pitch follow its speed (it hushes at the dwells). |
| `trolley_run` (loop) | 1.2 s | A 300 Hz crane motor with a 45 Hz gear buzz, 50 cable and chain link rattles and wheel rumble. | BalanceTrolley (and the hook and run containers) at the trolley. Speed-driven. |
| `trolley_clunk` | 0.6 s | A brake clunk (plate modes, a thud, a click) with a chain jingle. | A trolley starting or stopping. |
| `pulley_rattle` (loop) | 1.0 s | Chain links over the pulley (14 alternating-strength modal clicks), a faint 1.9 kHz wheel squeal and frame rumble. | BalanceCounterweight while it moves (volume follows its speed). |
| `counterweight_thud` | 0.7 s | A cage bottoming out: a heavy thud, plate modes, a click and a slack-chain jingle. | A cage reaching its end stop. |
| `trimmer_buzz` (loop) | 1.0 s | A buzzing 95 Hz band-limited saw (the shear motor), 24 Hz blade chatter, a laser crackle gated by the buzz, and 260 leaf-shredding grains. | GardensTrimmer, riding on the beam (-9 dB, 24 m). |
| `billboard_buzz` (loop) | 1.0 s | A neon transformer buzz (120 Hz, odd-heavy, 150-4000 Hz), a 7.8 kHz whine and irregular crackle. | AscentBillboard while it is shown. It stutters with the hologram's glitch flicker. |
| `billboard_on` / `billboard_off` | 0.45 / 0.40 s | On: four quick buzz zaps of growing length, then the hum thunking on. Off: a zap, a CRT-style 2200 -> 90 Hz "pew" and crackle. | The billboard blinking in or out. |
| `billboard_glitch_1..3` | 0.11 s | Digital glitch: a square tone jumping between random pitches every 5-10 ms, over crushed noise. | Each flicker while it glitches (at most one per 70 ms). |
| `data_chirp_1..4` | 0.16 s | Three or four quick bleeps up or down a pentatonic set (sines with 3rd and 5th harmonics). | AscentDataStream: a packet spawning at the upstream end. |
| `data_zip_1..2` | 0.25 s | A fast falling zip (2.6-3.2 kHz -> 0.5-0.7 kHz) inside a short whoosh. | A lit packet passing the runner in (or next to) its lane. |

### The new worlds' machines

The level scripts own the triggers. They call `WorldAudio.at()` for events and `WorldAudio.loop()` /
`set_active()` for continuous sounds. The "Meant for" column is the hook each clip was built for
(docs/NEW_WORLDS_BRIEF.md lists the names). For a name with `_1.._N` variants, one is picked at random.

**Xeno Wilds**

| File | Length | Synthesis | Meant for |
|------|--------|-----------|-----------|
| `spore_boing_1..3` | 0.6 s | A thick fleshy membrane struck from below: a 95-120 Hz "bwomp" gliding up to 2.1-2.5x as the cap tautens, with circular-membrane overtones (1 : 1.59 : 2.14 : 2.65) and a decaying 9-12 Hz wobble. A wet slap and squelch of contact, the cap puffing out spores (a breath sweeping 2.2 kHz -> 900 Hz) and a faint 4-11 kHz glitter. | A spore cap's bounce. |
| `snapjaw_snap_1..2` | 0.55 s | The lobes swing shut (a short swish peaking at 2.3-2.9 kHz), then meet in a wet, fleshy clap (a 150-175 -> 70 Hz blow, wet 250-3000 Hz noise and a squelch sweeping 1.6 kHz -> 350 Hz). 7 to 10 chitin teeth rattle as they interlock (1.8-3.2 kHz and 4.2-6 kHz modes), and the fibrous hinge creaks. | A snapjaw closing. |
| `snapjaw_open` | 0.7 s | Sap strings peeling apart (90 tacky 1.2-5 kHz ticks, thinning out), a wet stretch (a band rising 220 -> 700 Hz), the hinge groaning (stick-slip through 140/360/820/1500 Hz), a slow breath out and a few drips. | A snapjaw opening. |
| `geyser_erupt` | 1.6 s | Pressure gurgling up (bubbles coming faster for 0.25 s), then the column bursting: a 100 -> 50 Hz whoomph, a roaring spray (tilted 200-9000 Hz noise with turbulence) that dies away over about 0.5 s, 420 acid fizz grains (3-10 kHz) and 30 droplets raining back. | An acid geyser erupting. |
| `leviathan_call` | 3.6 s | The sky leviathan close by: a deep moan (a 66 -> 84 -> 58 Hz harmonic stack through two moving formants, 260-520 Hz and 750-1200 Hz, with a subharmonic growl and a faint 23 Hz ring-modulated sheen), a higher song gliding 330 -> 560 -> 410 Hz over it, breath, and a 2.2 s open-air reverb. | The leviathan set piece. |
| `drift_hum` (loop) | 2.0 s | The drift-stone monolith: a stony, inharmonic drone (82 Hz x 1 : 1.51 : 2.27 : 3.18 : 4.4) that throbs once a second, glassy 1244/1246.5/1871/2489 Hz partials glowing between the throbs, air swirling round the stones (a band wandering round 500 Hz) and the odd grain of grit. | Drift stones / the gravity well. |

**Cinder Peak**

| File | Length | Synthesis | Meant for |
|------|--------|-----------|-----------|
| `bomb_launch` | 1.0 s | The vent coughing a bomb out: an 85 -> 45 Hz "thoom", a tilted blast of gas, the rush of the bomb going up (a whoosh peaking at 1.8 kHz), spatter crackle and a low rumble, with a 1.4 s slope echo. | A lava bomb launching. |
| `bomb_whistle` | 2.0 s | An incoming bomb: a falling whistle (a narrow band, 1.9 kHz -> 650 Hz), the rush of air growing as it closes, a tumbling flutter (9 -> 15 Hz) and a fizzing smoke trail. It ends at full level, on the moment of impact. | A bomb in flight. |
| `bomb_impact_1..3` | 1.0 s | A molten bomb landing: a 95-110 -> 50 Hz thud and a wet splat (a band falling 900 -> 200 Hz), a crack, the crust shattering (four stone modes, 40 flying chips), molten spatter and a sizzling hiss, in a short slope reverb. | A bomb hitting its target ring. |
| `lava_rise` (loop) | 2.5 s | A flooded crater filling: a low, viscous churn (45-900 Hz, tilted dark), nine slow bubbles bulging (60-110 Hz, rising 1.8x) and bursting with a pop and a falling ring, crust crackle and a rim sizzle. | The rising lava. |
| `basalt_sink_1..2` | 1.4 s | A basalt column settling into lava: a clunk as it gives, stone grinding on stone (a stick-slip at 24-50 per second through 110-130/260-300/540-620/1100-1300 Hz, plus a rough scrape), a 95 -> 70 Hz groan of its weight, eight thick bubbles and a sizzle. | A sinking basalt column. |
| `fumarole_loop` (loop) | 2.0 s | A fumarole: a broad jet hiss (250-9000 Hz) with a band wandering round 1.8 kHz, surging gently, a 60-300 Hz rumble in the vent's throat and sputters of grit. | Fumarole updrafts. |
| `lavafall_loop` (loop) | 2.0 s | A thick molten curtain pouring over a ledge: a heavy, dark roar (50-2200 Hz, -3.5 dB/oct) with a tearing 300-1400 Hz sheet, 22 low glugs, 14 heavy plops, spatter and the hiss of the cooling skin. | A lava fall. |
| `crust_crack_1..2` | 0.5 s | Cooled crust giving under your weight: a brittle snap exciting stony plate modes (f11 380-460 Hz), a small thump, 12 fading ticks running away through the crust, a short creak and a puff of steam. | A crust plate starting to crack. |
| `crust_break` | 1.0 s | The plate giving way: a big crack and a 120 -> 62 Hz thud, five slabs breaking off (plate modes), crumbling debris, and the lava under it: a thick 70 -> 150 Hz gloop and a burst of sizzle. | A crust plate breaking. |
| `eruption_boom` | 2.8 s | An eruption pulse: a 72 -> 38 Hz blast with harmonics, a pressure wave of dark noise, the fountain's roar surging up and dying away, 400 ejecta crackles, a rumble, and the boom rolling back off the slopes (two echoes, 0.3-0.95 s). | The eruption pulses and the finish. |

**Frostbite Pass**

| File | Length | Synthesis | Meant for |
|------|--------|-----------|-----------|
| `icicle_crack` | 0.5 s | An icicle shivering loose: a run of tiny ticks quickening for 0.12 s (the ice fracturing at its root), then a sharp glassy crack, the icicle ringing (free-bar modes from 1.4-1.8 kHz) and a "pew" through the overhang. | An icicle's shiver and release. |
| `icicle_fall` | 0.8 s | The icicle dropping: an airy whoosh rising as it gathers speed (a band sweeping 600 -> 3200 Hz) and a thin glassy ring from the tumbling rod. | An icicle falling. |
| `icicle_shatter_1..2` | 0.9 s | The icicle exploding on the floor: a sharp crack and a thud, ice plate modes, 40 glassy shards (2.5-9 kHz, 10-40 ms) spraying and skittering, and tinkles settling, in a small bright space. | An icicle landing. |
| `gust_whoosh` | 1.4 s | A blizzard gust front shoving past: a whoosh rising to 1.4 kHz at the pass, a howl riding it (a narrow band, 380 -> 900 -> 500 Hz), a blast of driven snow and a low buffet. | Each gust pulse. |
| `ice_crack_1..2` | 0.6 s | Thin ice under your feet: a sharp snap, the panel's glassy plate modes (f11 500-650 Hz), two or three pews running out through the sheet, a small thump and a creak. | A thin-ice panel cracking. |
| `ice_break` | 1.0 s | The panel giving way: a big crack and a boom with a pew, five slabs breaking off (ice plate modes), 50 shards, and chunks tumbling away into the crevasse, duller and fainter as they fall. | A thin-ice panel breaking. |
| `avalanche_roar` (loop) | 2.5 s | The avalanche: a massive tumbling roar (45-3000 Hz, tilted dark, churning), a 200-900 Hz churn, 16 blocks of snow thudding inside it, the powder cloud's hiss and a ground rumble. | The avalanche set piece (ride it on the front). |
| `avalanche_rumble` | 2.5 s | The snowpack letting go: a deep 95 -> 48 Hz "whumpf", a crack across the slope with a long pew, then a rumble building over two seconds as the slide gathers, with thuds coming faster. | The avalanche's warning and release. |
| `snow_thump_1..3` | 0.4 s | A lump of snow landing: a soft 120-150 -> 62 Hz whump with a burst of muffled noise, a crumble of powder and a faint crunch. | Snowballs, snow falling off ledges. |

A "pew" is the sound of ice under strain. Ice is dispersive (flexural waves travel faster the
higher they are), so a crack reaches the ear as a laser-like chirp sweeping down,
f = f_hi / (1 + t / t0)^2. The glacier soundscape uses the same model.

**Scarab Sands**

| File | Length | Synthesis | Meant for |
|------|--------|-----------|-----------|
| `spike_trap_1..2` | 0.5 s | The stone latch clunking, five bronze spikes shooting up in a quick, ragged rank (each a bright scrape sweeping 2.5 -> 7 kHz with a short ring of bar modes from 1.1-1.5 kHz), a thud at the top of their travel and a puff of sand, in the temple. | Spikes thrusting up. |
| `spike_retract` | 0.6 s | The spikes sliding back: a slower bronze scrape falling 4.2 -> 1.4 kHz, a faint ring, the plate grinding as it resets and a clunk at 0.45 s. | Spikes going down. |
| `sandfall_loop` (loop) | 2.0 s | A curtain of sand pouring: a dense, dry 1.8-9 kHz hiss with 900 grain ticks, a softer 250-1800 Hz pouring body, 160 low patters where it lands, and a touch of the hall (a circular room reverb). | Sand falls. |
| `quicksand_sink` | 1.2 s | Sinking sand: a low sucking pull (a band sweeping 700 -> 150 Hz), sand shifting and pouring in round it, a low 60-300 Hz body, trickling grains, and a deep, dull gulp at 0.85 s. | Standing in quicksand. |
| `dustdevil_loop` (loop) | 2.0 s | A whirlwind: tilted broadband wind, two bands whose centres circle up and down (round 900 Hz three times a loop, round 1.8 kHz five times), sand whipped round in pulses with the swirl, a faint 2.2 kHz whistle and a low buffet. | Dust devils. |
| `mirage_shimmer` | 1.0 s | Heat haze: five pale, glassy tones (E6 to A7) wavering in and out of tune at 3-6 Hz, swelling and fading like the air, over a breathy band. | A mirage platform's shimmer build-up. |
| `boulder_roll` (loop) | 2.0 s | The stone ball rolling: a 45-400 Hz rumble, knocks from five chips and flats coming round in a repeating pattern (it turns twice a loop), 400 grit crackles, crunch and dust. Pitch it with the ball's speed. | The boulder run, riding on the ball. |
| `boulder_impact` | 1.4 s | The ball smashing into a wall or its pit: a huge 95 -> 55 Hz thud with harmonics, a crack, a burst of low noise, 30 pieces of rubble tumbling and rattling, debris and dust, in a 1.4 s temple reverb. | The boulder's end. |
| `stone_grind_1..2` | 1.3 s | A sandstone block sliding: stone grinding on stone (a stick-slip at 26-52 per second through the block's dead resonances, plus a rough scrape), sand crunching under it, and the block settling with a knock at 1.03 s, in the temple. | Sliding walls, the hidden tomb door, turning sun-dials. |

**Phantom Manor** (score in D minor; pitched clips in D minor)

| File | Length | Synthesis | Meant for |
|------|--------|-----------|-----------|
| `manor_phantom_waver` | 0.6 s | Pale D5/F5/A5/D6 sines with 4-6.5 Hz vibrato and an uneven tremolo, over a breathy band wandering round 900 Hz, swelling and fading, in the hall. | A phantom platform flickering. |
| `manor_phantom_form` / `_fade` | 0.8 s | A detuned cluster gliding into (out of) a D-minor chord, a breath sweeping 400 -> 2600 Hz (2600 -> 350 Hz), and a glassy D6 ping as it takes (loses) shape. | A phantom platform appearing / vanishing. |
| `manor_gaze_open` | 0.7 s | A low swell of D2 + A2 harmonic stacks, a thin G#5/D6 sting (the tritone), a dry canvas creak and an indrawn breath falling 3 kHz -> 700 Hz. | A portrait's eyes opening. |
| `manor_gaze_hum` (loop) | 1.5 s | Two D2 hum stacks 0.6 % apart beating, a hollow formant breathing round 600 Hz once a loop, a thin D6 whine pulsing three times, and air. | The gaze while it's on. |
| `manor_chain_creak` | 0.8 s | Chain links groaning (stick-slip through 850-950/2000-2300/3400 Hz) and five small clinks (bar modes, 1.9-2.6 kHz). | A swinging chandelier. |
| `manor_possessed_creak` (loop) | 1.5 s | Two wooden groans (150 and 190 Hz timbers), two knocks, a restless rattle and a faint draught, all wrapping round the loop. | Possessed furniture. |
| `manor_waltz_box` (loop) | 3.6 s | A music box playing a four-bar waltz in D minor, 3/4 at 200 bpm (Dm, Gm, A7, Dm). A bass tine on each downbeat, dyads on beats two and three, and the tune over them. The tines are cantilever modes (1 : 6.27 : 17.55) and ring across the wrap. The pins tick, and the spring and air brake whirr softly. | The music box. |
| `manor_board_creak` | 0.6 s | A floorboard's long creak: stick-slip at 25-70 per second through a 210-250 Hz board's modes. | A weak board taking weight. |
| `manor_board_snap` | 0.6 s | A splintering crack through the board's modes (240-3000 Hz), 40 splinters, fibres tearing and a dull drop below. | The board breaking. |
| `manor_coffin_slam` | 0.9 s | A heavy 120 -> 58 Hz thud, the box's plate modes booming, the lid rattling three times, and a 1.8 s crypt reverb. | A coffin lid slamming. |
| `manor_bell_toll` | 2.0 s | A D4 bell with a minor tierce (hum, prime, tierce, quint, nominal and upper partials), struck with a thud and swinging (a 2.2 Hz beat), in a long reverb. | The tower bell and the finish. |
| `manor_mirror_chime` | 1.0 s | A quick glassy arpeggio up D6 F6 A6 D7 (glass modes 1 : 2.32 : 4.25) with a high shimmer. | A haunted mirror. |

**Storm Armada** (score in E minor)

| File | Length | Synthesis | Meant for |
|------|--------|-----------|-----------|
| `armada_cannon_fuse` | 0.8 s | A spitting fuse: a 2.5-11 kHz hiss with ragged amplitude, 160 bright crackles and a few low pops. | A cannon about to fire. |
| `armada_cannon_fire` | 1.2 s | A crack, a 106 -> 36 Hz thump with harmonics, a smoky tilted blast, a rolling low tail and the carriage recoiling at 0.09 s, with a sky echo. | A cannon firing. |
| `armada_cannon_impact` | 0.9 s | A 130 -> 60 Hz thud, a splintering crack, the deck's plate modes and 50 splinters raining down. | A ball hitting home. |
| `armada_hull_creak` (loop) | 1.5 s | Two deep timber groans (95 and 140 Hz), water sloshing in the bilge once a loop, and a low bed. | Ship decks in the storm. |
| `armada_swing_creak` | 0.7 s | Rope fibres groaning round the spar (380-440/900-1000/1900 Hz). | Rope swings. |
| `armada_rod_charge` | 0.9 s | A buzz rising from E2 to E4, with corona hiss and crackle thickening. | A lightning rod charging. |
| `armada_lightning_strike` | 1.2 s | A searing crack, a sizzle and a short E2 buzz, then thunder right on top (tilted noise and a 70 -> 38 Hz boom) with a sky reverb. | A strike on the rod. |
| `armada_prop_loop` (loop) | 1.0 s | Blades chopping the air 16 times a second, an E2 engine thrumming with them, and the wash. | Airship propellers. |
| `armada_prop_spinup` | 1.0 s | The chop speeding up from 2 to 16 per second and the engine climbing to pitch. | A propeller starting. |
| `armada_mast_creak` | 0.9 s | A long, deep groan of a 110 Hz timber, with grit. | A mast leaning before it falls. |
| `armada_mast_crash` | 1.2 s | Fibres splintering, a huge 100 -> 45 Hz thud, the planks' plate modes booming, and rigging and debris clattering. | The mast crashing down. |
| `armada_winch_loop` (loop) | 1.0 s | A pawl clacking over the ratchet ten times a second, an E3 gear whine, the rope creaking round the drum, and a rumble. | Winches hauling. |
| `armada_ship_bell` | 1.4 s | "Ding-ding": a small brass bell on E5, struck twice. | Ship's bells. |
| `armada_salute` | 1.5 s | Three guns fired in turn (0, 0.38, 0.76 s), each rolling off the clouds. | The finish salute. |

`armada_thunder_near` / `armada_thunder_far` were in the brief, but nothing calls them (the ambience's
`amb_armada_thunder_*` covers thunder), so they were not made.

**Sugar Rush** (score in C major; pitched clips in C major)

| File | Length | Synthesis | Meant for |
|------|--------|-----------|-----------|
| `candy_jelly_boing` | 0.5 s | A wobbling "boing" gliding C3 -> G3 with a decaying 11 Hz jiggle, a wet slap and a squelch falling 1.5 kHz -> 400 Hz. | Jelly pads (via `Sfx.has_clip`; falls back to `bounce`). |
| `candy_jack_wind` | 0.8 s | A crank ratchet clicking six times and a music-box tune plinking C5 E5 G5 C6. | A jack-in-the-box winding. |
| `candy_jack_pop` | 0.7 s | A latch click, a spring "sproing" (C4 gliding up an octave with a 22 Hz wobble), a cork pop and a C6/E6/G6 ding. | The jack popping out. |
| `candy_soldier_march` (loop) | 1.6 s | Four stiff tin-foot clacks at 150 steps a minute, each with a drum tap, clockwork ticking inside and a spring whirr. | Marching tin soldiers. |
| `candy_soldier_turn` | 0.4 s | A quick clockwork whirr and a tin clank. | A soldier's about-turn. |
| `candy_train_chug` (loop) | 1.6 s | Four steam chuffs, wheels clacking in pairs over the rail joins, the boiler's rumble and a steam hiss. | The toy train. |
| `candy_train_whistle` | 1.2 s | A C6/E6/G6 chord blown through a steamy pipe, scooping into pitch: a short toot, then a long one. | The train's whistle. |
| `candy_gumball_drop` | 0.6 s | The coin wheel clunking, then the ball bouncing down the chute, each hop shorter. | A gumball released. |
| `candy_gumball_roll` (loop) | 1.2 s | A hollow 500 Hz rumble, a knock at each of eight chute seams and the ball's rattle. | A gumball rolling. |
| `candy_gumball_splash` | 0.8 s | A gloopy plunk (a 260 Hz bubble and a thud), a thick splash and slow bubbles. | A gumball landing in syrup. |
| `candy_confetti` | 0.9 s | A popper's pop, 220 paper flutters and a C-major twinkle (C6 E6 G6 C7). | Checkpoints. |
| `candy_fireworks` | 1.5 s | A rocket whistling up (1.2 -> 3.2 kHz), a bang and 260 stars crackling as they fall. | The finish. |

**Super Carrier** (score in A major; pitched clips in A)

| File | Length | Synthesis | Meant for |
|------|--------|-----------|-----------|
| `carrier_cat_hiss` | 0.8 s | Steam bursting out of the track slot (an 800-10000 Hz hiss and a low body). | The catapult venting. |
| `carrier_cat_launch` | 1.2 s | A 110 -> 50 Hz steam thump, the shuttle screaming down the track (a whoosh, and the rails singing), and the water brake's clunk and hiss at 0.85 s. | The catapult firing. |
| `carrier_cat_retract` | 0.9 s | A rumble along the track, a hydraulic whine falling 900 -> 500 Hz, and a clunk. | The shuttle returning. |
| `carrier_jet_spool` | 1.2 s | A compressor whine climbing 600 -> 3200 Hz and the roar swelling under it. | A jet winding up. |
| `carrier_jet_roar` (loop) | 1.5 s | A churning tilted roar, a tearing 600-3000 Hz band, a 3.2 kHz whine and the deck rumbling. | Jet blast. |
| `carrier_wire_twang` | 0.7 s | A 55 Hz steel cable (a stiff, slightly inharmonic string with a 7 Hz flutter) and the hook's clank. | An arresting wire. |
| `carrier_elevator_start` / `_stop` | 0.6 s | The lock clunk and the motor winding up to (down from) A3. | The deck-edge elevator. |
| `carrier_elevator_hum` (loop) | 1.0 s | An A2 motor hum stack, a faint A5 whine and the platform rumbling in its guides. | The elevator moving. |
| `carrier_door_klaxon` | 1.0 s | Two blasts of a buzzy A4 through a horn formant (1.4 and 2.6 kHz). | The hangar door alarm. |
| `carrier_door_grind` | 1.2 s | Steel dragging on its rails (stick-slip through 180-2800 Hz), rollers and a deep A1 motor. | The hangar door moving. |
| `carrier_launch_spool` | 1.2 s | The whine climbing 900 -> 3000 Hz, the roar rising, and the afterburner lighting at 0.9 s with a thump and crackle. | A jet on the catapult going to full power. |
| `carrier_launch_shot` | 1.2 s | The catapult's slam and the jet's roar blasting away down the deck (a band falling 2.5 kHz -> 500 Hz). | The launch. |
| `carrier_launch_flyby` | 1.5 s | A roar sweeping in and out, with the whine's Doppler drop (3.4 -> 2.3 kHz). | The launched jet passing. |
| `carrier_jbd_raise` / `_lower` | 1.0 s | A hydraulic whine rising (falling) between 300 and 520 Hz, fluid hiss, and a deep lock clunk at 0.78 s. | The jet blast deflectors. |
| `carrier_lift_move` | 1.0 s | A clunk, two warning beeps (A5, C#6) and an A2 motor hum rising. | Aircraft lifts. |
| `carrier_flyover` | 1.8 s | Three jets thundering past in turn (peaks at 0.6, 0.8 and 1.0 s), whines dropping, with a sky echo. | The finish flyover. |

### Deliberately silent

* **Checkpoint and FinishGate**: the lead does the themed chimes and fanfares.
* **LedgeBlock and WallRunPanel**: static; the player's mantle and wall sounds cover them.
* **KillZone hazard strips** (up to 24 in a level): a sizzle loop on each would
  become a drone. The ambience beds cover the heat.
* **Boost strips at rest and ice sheets**: they sound through the player (the zing
  on entry and the slide hiss).
* **Decorative gears, rings and chimneys**: these are ambience territory.
* **Tilt platforms, bumpers, bounce pads, collapsing platforms (crumble / collapse)**:
  keep their existing sounds.
