# NEW WORLDS brief - levels 7 Xeno Wilds, 8 Cinder Peak, 9 Frostbite Pass and 10 Scarab Sands (read after docs/LEVEL_BRIEF.md, docs/HARD_MODE_BRIEF.md and docs/EXTENSION_BRIEF.md - this overrides them where they differ)

The owner's request (2026-09-24): **"implement 2 more unique maps. I really really like the space station and the coral
map. Maybe do some type of alien planet map and something else crazy you can think of, maybe a crazy volcano map with a
cool looking volcano erupting in the background."**

Coral Depths (`levels/level_5_reef.gd`) and Orbital Drift (`levels/level_6_orbital.gd`) are the bar: the owner loves them
because the whole world is restyled (sky, fog, light, huge custom scenery, dense particles) and the course is full of
theme-specific machines. Read both scripts end to end before you start - reuse their patterns (local stage frames,
`_cp_world`, decor helpers, course-clock bursts, route variants).

Later the same day the owner added: **"build level 9 and 10 as well with 2 different unique untouched themes"** - the
lead chose Frostbite Pass (a frozen ice fortress) and Scarab Sands (a desert sun temple); see their sections below.

New order (0-based index): 0 gardens, 1 foundry, 2 balance, 3 clockwork, 4 reef, 5 orbital, **6 xeno**, **7 volcano**,
**8 glacier**, **9 desert**, 10 ascent. The Final Ascent stays the finale (its files are now `levels/level_11_ascent.*`).
Placeholders exist: `levels/level_7_xeno.gd` / `level_8_volcano.gd` / `level_9_glacier.gd` / `level_10_desert.gd` (+ .tscn), their `Look.THEMES` entries, their `Game.LEVELS` lines,
`SaveData.LAYOUT_REV` entries, and their music tracks (`music_track` is already set - the lead is scoring both maps).

Project root (main checkout): `C:\Users\fatty\Desktop\PlatformerJumpPuzzle`. You work in your own git worktree.

---

## Level 7 - XENO WILDS (`theme_id = "xeno"`, `music_track = "xeno"`)
**An alien planet.** A bioluminescent jungle on a low-gravity alien moon. A colossal ringed gas giant fills a third of the
sky, two suns sit low (one teal, one amber - two shadows if you can, or a warm rim light from the second), and auroras
ribbon overhead. Violet-to-teal sky, glowing flora, floating rock islands, crystal spires, spore clouds, acid pools.
It must feel *alien*, not "gardens at night": strange silhouettes, impossible scale, colour you have not used elsewhere.

Environment ideas (use what serves the course):
- Giant glowing mushrooms (caps = bounce pads, stalks = scenery), tentacle vines that sway, crystal clusters that pulse,
  fern-like fractal trees, bulbous spore pods, a forest of glowing reeds, bones of something enormous half-sunk in acid.
- Floating islands: chunks of rock hanging in the air with dangling roots and little waterfalls of glowing liquid that
  fall upward or dissolve into motes.
- Acid lakes (kill surfaces) that glow and bubble; mist layers; spores drifting up; fireflies; aurora ribbons.
- Far scenery: the ringed giant (with a shaded terminator and a ring shadow), a second moon, rock arches, a
  mega-mushroom forest on the horizon.

Theme mechanics (build 2-3 as your own `mechanics/xeno_*.gd` scripts, deterministic from `Game.course_time`):
- **Spore caps** - mushroom bounce pads that breathe: they swell and shrink on a rhythm, and the bounce you get depends on
  the phase (a timing bounce, not just a pad).
- **Snapjaws** - giant carnivorous flytrap mouths that snap shut across the path on a rhythm (a horizontal crusher);
  deadly while closed, a lingering glow warns before each snap.
- **Drift stones / gravity wells** - floating rocks that orbit a pulsing monolith, or a gravity well that curves your
  jumps; ride them across a chasm.
- **Acid geysers** - vents that erupt on a clock (lift you like `kit.wind` updrafts while erupting, kill if you are in the
  column at its peak, or both - make the rule readable).
- **Set piece idea: The Leviathan** - a huge sky creature (a whale / manta of glowing plates and trailing tendrils) glides
  across a vast chasm on the course clock; its back is a moving platform you board and ride, then jump off at the far
  side. Or your own better idea - but it must be the "wow" moment of the level.
Low gravity is welcome in places (see `mechanics/orbital_gravity_bay.gd`), but keep it a feature of some stages, not
the whole level, and don't repeat Orbital Drift's pulse bay.

## Level 8 - CINDER PEAK (`theme_id = "volcano"`, `music_track = "volcano"`)
**A volcano mid-eruption.** A night climb up the flank of a volcano toward its crater rim while it erupts. The
**erupting volcano in the background must look spectacular** - it is the headline image of the level:
- A huge cone on the horizon (and the one you climb) with a crater glowing from within.
- A continuous **eruption**: a lava fountain (dense orange-white particles shooting up and arcing down), a towering
  ash column that billows and spreads into an anvil cloud lit red from below, **volcanic lightning** flickering inside
  the ash cloud (flash lights + bolt meshes on a timer), lava bombs arcing out and trailing smoke.
- **Lava rivers** glowing down the flanks (emissive meshes; a scrolling / pulsing shader or animated emission), lava
  falls, glowing fissures in the ground, heat haze, falling ash and embers everywhere, a red-black sky, smoke layers.
- Periodic bigger **eruption pulses** (on the course clock) - the fountain surges, the sky flashes, embers rain harder.
It must not look like Bounce Foundry (an industrial furnace). This is natural and elemental: basalt, obsidian,
hexagonal basalt columns, cooled pahoehoe crust, sulphur vents, lava tubes, a storm of ash and lightning.

Theme mechanics (build 2-3 as `mechanics/volcano_*.gd`, deterministic from `Game.course_time`):
- **Lava bombs** - bombs launched from the volcano on the course clock, arcing in and landing on target zones marked
  on the ground (a glowing ring that brightens before impact); the landing zone is deadly for a moment and splashes.
  Readable, fair, dodgeable: the ring always warns long enough.
- **Rising lava** - the set piece: a flooded crater chamber / lava tube where the lava level rises and falls on the course
  clock (kill below the surface, `kill_y`-style). You climb (wall runs, mantles, pads) to stay ahead of the rising tide,
  and the stage is designed so a fluent run just outpaces it.
- **Sinking basalt** - basalt columns that sink into the lava when stood on (like `kit.collapse`, but they slowly sink and
  rise back), or that rise and fall on a rhythm like pistons.
- **Fumaroles** - hot-air vents (updrafts) that lift you, some pulsing on the clock.
- **Lava falls** - curtains of lava pouring across ledges on a rhythm (timing gates; natural, not Foundry's ladles).
- **Crust plates** - cooled lava crust that cracks and breaks shortly after you land on it.
End at the crater rim under the eruption, with a finish that goes off (the fountain surges, a burst of fire and embers).

## Level 9 - FROSTBITE PASS (`theme_id = "glacier"`, `music_track = "glacier"`)
**A frozen mountain pass and an ice fortress in a blizzard, under the northern lights.** Polar dusk turning to night:
a deep-blue sky with aurora curtains, snow-laden peaks, glaciers with blue crevasses, a frozen waterfall the height of
a cathedral, an ice fortress of translucent walls and spires lit from inside, and snow blowing sideways. It must feel
cold: a blue-white palette, glassy translucent ice (refraction, rim light, emission), soft snow and frost sparkle.
Keep it distinct from Xeno Wilds' alien sky: these are green-violet aurora curtains high in a clear polar sky.
Theme mechanics (build 2-3 as `mechanics/glacier_*.gd`, deterministic from `Game.course_time`):
- **Falling icicles:** icicles hanging from overhangs shiver, then drop on the course clock. A frost ring on the floor
  warns where each will land. They are deadly while falling, and the shattered ice melts away.
- **Blizzard gusts:** a readable gust front (snow streaks) sweeps across a stage on a rhythm and shoves you sideways
  (horizontal `kit.wind` pulses). Time your jumps between gusts, or use them.
- **Cracking ice bridges / thin ice:** glassy panels that crack when stood on and break a moment later (show the cracks
  spreading). Also **ice slides**: slick ramps that fling you across crevasses.
- **Set piece: the avalanche.** A wall of snow thunders down a long slope on the course clock, and you race across or
  down the slope ahead of it, or duck into shelters between waves. This is the wow moment of the level: huge snow
  particles and a rumble. Or bring your own better idea.
Also welcome: a frozen-waterfall wall-run chimney, snowball rollers, an ice cave with glowing crystals, a frozen-lake
slide under the aurora, fortress drawbridges (movers), snow cannons (pistons).
Sound hooks (`WorldAudio`; the lead will provide these clips): `icicle_crack`, `icicle_fall`, `icicle_shatter`,
`gust_whoosh`, `ice_crack`, `ice_break`, `avalanche_roar` (loop), `avalanche_rumble`, `snow_thump`.

## Level 10 - SCARAB SANDS (`theme_id = "desert"`, `music_track = "desert"`)
**An ancient desert sun temple.** The setting:
- A blazing afternoon sun, low toward golden hour, over towering dunes with wind-blown sand.
- Colossal pyramids and half-buried statues on the horizon, a sandstorm wall rolling in far away, and heat shimmer.
- An oasis with palms and turquoise water at checkpoints.
- The temple itself: sandstone blocks carved with glyphs, gold and turquoise inlay, torches, sunbeams slanting through
  dusty halls, and a great sun-disc over the finish.
- A warm gold / ochre / turquoise palette, hard shadows, and dust motes in the light.
Theme mechanics (build 2-3 as `mechanics/desert_*.gd`, deterministic from `Game.course_time`):
- **Spike traps:** floor plates whose spikes thrust up on a rhythm; a glyph glows before they fire.
- **Sand falls / quicksand:** curtains of sand pouring from the ceiling on a rhythm (timing gates), and sinking sand
  that drags you down if you stand in it too long.
- **Dust devils:** small whirlwinds wandering on a path that lift you (moving updrafts). Ride them up to high ledges.
- **Mirage platforms:** shimmering platforms that fade in and out with the heat (a blink variant with a readable
  shimmer build-up).
- **Set piece: the boulder run.** A giant stone ball is released on the course clock and rolls down a long temple
  corridor or ramp behind you. Outrun it through a gauntlet and dive into a side alcove, or leap a gap it falls into.
  This is the wow moment of the level. It is deterministic from the clock: a checkpoint restart re-arms it. Design it so
  a fluent run just escapes.
Also welcome: swinging blade pendulums, dart lasers from glyph walls, collapsing sandstone, a rotating sun-dial
platform, scarab swarms (sweepers), and a hidden tomb shortcut behind a sliding wall (a portal).
Sound hooks (the lead will provide these clips): `spike_trap`, `spike_retract`, `sandfall_loop` (loop),
`quicksand_sink`, `dustdevil_loop` (loop), `mirage_shimmer`, `boulder_roll` (loop), `boulder_impact`, `stone_grind`.

Difficulty order: Xeno Wilds < Cinder Peak < Frostbite Pass < Scarab Sands < The Final Ascent.

---

## All four levels: what "done" means
1. **17-20 stages**, each ending on a checkpoint facing the next stage. Difficulty sits between Orbital Drift (6) and
   The Final Ascent (9); each new level is harder than the one before (see the difficulty order above).
2. **A super unique environment** built from your level script: in `_build()` restyle the `WorldEnvironment` /
   `DirectionalLight3D` that `Look.build_environment` added (fog, sky, glow, light, ambient), add a custom sky if needed
   (see `visual/reef_sky.gdshader`, `visual/orbital_sky.gd`), large far scenery, and dense set dressing. You own your
   theme's entry in `visual/look.gd` THEMES and your `Game.LEVELS` name / blurb (placeholders are in place - rename them
   if you find better ones). New `visual/<theme>_*.gd` / `.gdshader` files are yours.
3. **Moves and machines:** at least 3 wall-run and 3 mantle obstacles, all four machines (laser, piston, crusher,
   portal - themed: a laser can be an energy tendril or a jet of flame), 2+ theme mechanics of your own (above), and the
   classic kit (pads, boosts, blinks, movers, sweepers...) so it still plays like Jump Circuit.
4. **Routes:** at least 3 stages split into two genuinely different routes that rejoin at the stage-end checkpoint
   (`route_variants`, bot-proven for every variant), and at least 4 optional shortcuts. See EXTENSION_BRIEF.
5. **Particles are a priority** (EXTENSION_BRIEF "Particle effects"): at least 3 layered ambient systems along the course,
   effects on every set piece, bursts at checkpoints and the finish. Keep the on-screen total in the low thousands.
6. **Performance:** the level must stay smooth. Far scenery should be cheap (few, large meshes; shaders instead of
   thousands of nodes); share meshes and materials (`Look` caches them); give particles sensible visibility AABBs.
7. Header comment of your level script lists every stage (like level_5_reef.gd).
8. `SaveData.LAYOUT_REV` already has your id at 1 - leave it.

## Rules (in addition to EXTENSION_BRIEF's)
- You own ONLY: your level script + .tscn, your new `mechanics/<theme>_*.gd`, `visual/<theme>_*.gd` / shaders, your
  `Look.THEMES` entry, your theme's `match` case in `visual/ambience.gd` `recipe()` (the camera-following ambient
  particles - add it, following the other themes' style), your `Game.LEVELS` line (name / blurb only). Do NOT edit player/, resources/, the rest of
  autoload/, level_base.gd, level_kit.gd, existing mechanics/, sound/, audio/, the music or sound generators.
  Report anything in shared code that gets in your way.
- `tests/route_bot.gd`: prefer the existing step kinds; if you truly need one, add it ADDITIVELY (one `"<theme>_...":`
  match line + one function at the end of the file).
- **Sound:** the lead is writing your score, soundscape and theme sounds. Just expose clean hooks: for each theme
  mechanic, a comment where an event sound should fire (e.g. `# SOUND: bomb_whistle at launch`) - or, better, call the
  existing helper `WorldAudio` (`mechanics/world_audio.gd`: `WorldAudio.at(self, clip, pos)` for events,
  `WorldAudio.loop(clip, self)` + `WorldAudio.set_active(p, on)` for continuous sounds - it is a no-op headless) with
  a clip name from this list, which will exist:
  xeno: `spore_boing`, `snapjaw_snap`, `snapjaw_open`, `geyser_erupt`, `leviathan_call`, `drift_hum` (loop);
  volcano: `bomb_launch`, `bomb_whistle`, `bomb_impact`, `lava_rise` (loop), `basalt_sink`, `fumarole_loop` (loop),
  `lavafall_loop` (loop), `crust_crack`, `crust_break`, `eruption_boom`. Missing clips are silently skipped, so
  calling them now is safe.
- **NEVER run windowed Godot.** The owner plays on this PC and pop-up windows interrupt them: no `tools/shot.tscn`, no
  `bot_shots`, no game runs - headless only. When your level is otherwise done and tested, finish and say in your
  report which shots you want; the lead will run the screenshot pass at a time the owner allows.
- Heredocs in the shell truncate files at apostrophes - use the Write / Edit tools for file content.
- Measure every pad / boost / wall-run / mantle landing (Ballistics or a scratch probe under `tests/scratch/`, deleted
  afterwards), never by eye.

## Verify (must pass before you finish)
```
G=/c/Users/fatty/Desktop/PlatformerJumpPuzzle/tools/Godot_v4.7.1-stable_win64.exe
W=<your worktree root>
timeout 600 $G --headless --path $W --import
timeout 900 $G --headless --path $W res://tests/run_tests.tscn -- --only=test_m --level=<6, 7, 8 or 9>
timeout 3600 $G --headless --path $W res://tests/run_tests.tscn -- --only=test_n --level=<6, 7, 8 or 9> --route=all
```
Targets: test_m hardest jump <= 95 %; test_n finishes EVERY route variant with <= 30 respawns each. Also run the
quick groups (`--only=test_a`, `test_b`, ...) that load every level, to make sure yours builds cleanly with no errors or
warnings in the log. Discard CRLF-only `.import` churn; commit new `.import` files you create.

Back up `%APPDATA%\Godot\app_userdata\Jump Circuit\progress.json` before tests and restore it afterwards.

## When done
Commit on your worktree branch, message ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
Do not push, do not merge. Final report: stage-by-stage list, where the wall runs / mantles / machines / theme mechanics /
set piece are, the branches and shortcuts, bot result per variant (time, respawns), hardest-jump %, the sound hooks you
added (clip names + trigger), the screenshots you want taken (camera / look positions), and branch + commit hash.
