# NEW WORLDS 3 brief - levels 16 Sakura Peaks, 17 Jungle Temple, 18 Wild West Heist, 19 Neon City
Owner (2026-10-01): "make a plan for 3 more thematically unique maps". When offered four themes, they picked all four.

**This brief extends `docs/NEW_WORLDS_2_BRIEF.md` and `docs/NEW_WORLDS_BRIEF.md`.** Read both first. Every rule, the
definition of done, the verify steps, the sound-hook conventions, the report format and **all of the "Lessons from
the last round" hard rules** apply here unchanged. The quality bar is the eight newest levels, `level_7_xeno.gd`
through `level_14_carrier.gd`; read at least two of them before you start.

New order (0-based index): ... 13 carrier, **14 sakura**, **15 jungle**, **16 frontier**, **17 neon**, 18 ascent (the
finale, now `levels/level_20_ascent.*`). The placeholders, the `Look.THEMES` entries, the `Game.LEVELS` lines and
`SaveData.LAYOUT_REV` are already in place. The lead is writing the scores and the sound.

## Extra rules for this round
- **Medal times are coming.** Every map will get Bronze, Silver and Gold target times, set from the bot's fastest
  route. So the shortcut route should be a real time saver for a skilled player, not a trick only the bot can do.
  Keep shortcut jumps at 95% or less.
- **The 1.0 s pause check is mandatory.** After every wait and every checkpoint, the bot pauses for 1.0 s. With that
  pause, every route must finish. Report the paused results for every route, run on your final commit, not before a
  later timing change. Then remove the hook before committing.
- **The bot must not stand on anything a human couldn't see coming.** Every timed hazard needs a visible and
  audible tell at least about 0.8 s ahead.
- **Moving trains and traffic:** any platform the player rides must carry the player with its full velocity, using
  the existing mover and conveyor machinery that keeps a rider attached. It must never teleport, and it must loop
  seamlessly; Sugar Rush's toy trains are the reference.

## Level 16 - SAKURA PEAKS (`theme_id = "sakura"`, `music_track = "sakura"`)
A feudal-Japan mountain at dusk. The course climbs from a village by a koi pond, through a bamboo forest and up
temple stairs and rope bridges, to the castle keep at the summit.
- **Setting:** cherry trees with drifting blossom (the particle signature), pagodas with tiered curved roofs, torii
  gate tunnels, stone lanterns and hanging paper lanterns that glow as dusk falls, a misty valley with distant peaks
  and a big low sun. The palette is pink and cream blossom, vermilion lacquer, dark wood and a warm sky.
- **Theme mechanics (2-3, `mechanics/sakura_*.gd`):**
  - **Bamboo spring launchers:** a bent bamboo that flicks you up on a clock.
  - **Swinging temple-bell logs:** battering-ram pendulums.
  - **Paper sliding doors:** shoji panels slide open and shut across a gap or corridor.
  - **Falling-blossom platforms:** big floating petals that sink while you stand on them, then float back up.
  - **Koi stepping stones:** they bob.
  - **Ninja shuriken:** spinning disc sweepers on rails, telegraphed.
- **Set piece:** cross a long rope bridge between peaks while it sways, with gusts that you see coming as a wave of
  blossom across the bridge. The finish is the top of the keep's roof under the first stars.
- **Content:** a respectful, storybook Japan. No real place names, and no text in Japanese unless it is purely
  decorative and abstract.

## Level 17 - JUNGLE TEMPLE (`theme_id = "jungle"`, `music_track = "jungle"`)
Overgrown Maya/Aztec-style ruins deep in a rainforest. Climb from the river through the ruins to the top of a great
step pyramid.
- **Setting:** giant trees and canopy, hanging vines and roots, waterfalls with mist and rainbows, carved stone
  faces, glowing jade glyphs, broken stairways, toucans and butterflies, and god rays through the leaves.
- **Theme mechanics (2-3, `mechanics/jungle_*.gd`):**
  - **Vine swings:** rideable pendulums, like Armada's rope swings.
  - **Dart traps:** wall faces that fire dart volleys across lanes on a clock, with a clicking tell. Use the existing
    laser or crusher style kill, or a knockback.
  - **Crumbling stone bridges.**
  - **Glyph pressure plates** that open and close stone gates.
  - **Spike-pit floors.**
  - **Log rafts on the river:** moving platforms.
- **Set piece:** the **rolling boulder chase**. A huge boulder rolls down a long temple ramp behind you, and you
  outrun it through a sequence of hops. It must be generous, with at least about 2 s of slack when following the bot's
  line with the 1 s pause. Check the brief's rule about not killing unfairly.
  The finish is the altar on top of the pyramid.

## Level 18 - WILD WEST HEIST (`theme_id = "frontier"`, `music_track = "frontier"`)
A canyon train robbery at sunset. A steam train runs through a red-rock canyon, and you run along it car by car to
the locomotive.
- **Setting:** mesas and hoodoos, a long trestle bridge, the train itself (a locomotive with smoke and steam, a
  tender, boxcars, a passenger car, flatcars with crates), cacti, tumbleweeds, a water tower, mine entrances, dusty
  light and a huge sun low on the horizon.
- **Moving train approach:** decide early, and say in your report which you chose.
  - **Option A (recommended):** the train is static and the world scrolls. The scenery (canyon walls, posts, the
    trestle) moves past while the cars stay still, so the cars are simple static platforms and the run is safe.
  - **Option B:** the train moves along a loop, as in Sugar Rush, using rider-attached movers.
- **Theme mechanics (2-3, `mechanics/frontier_*.gd`):**
  - **Mine carts** on rails: rides.
  - **Dynamite:** lit sticks on a fuse that blow a section up, telegraphed by the spark and a hiss.
  - **Low tunnels and signal arms** that sweep across the car roofs, so you must drop down.
  - **Swinging saloon-style doors.**
  - **A collapsing trestle section.**
  - **Water-tower spouts.**
- **Set piece:** crossing the long trestle bridge as it collapses behind the train. The finish is on the locomotive's
  cab roof, with the whistle blowing.
- **Content:** cartoon heist fun. No guns firing at the player. Dynamite is the hazard.

## Level 19 - NEON CITY (`theme_id = "neon"`, `music_track = "neon"`)
Cyberpunk rooftops at night in the rain, climbing from street-level rooftops up the tallest tower.
- **Warning: it must look clearly different from The Final Ascent,** which is already "a night climb up a neon spire
  complex" in cool blue and cyan. Neon City is a **dense, rainy, lived-in downtown**:
  - hot magenta, amber and teal signs;
  - wet reflective rooftops (roughness low, puddles);
  - steam vents, AC units and water tanks;
  - holographic billboards (abstract shapes, no real brands);
  - flying traffic lanes streaming between towers;
  - a skyline of lit windows;
  - rain streaks and splashes.

  The Final Ascent is sparse, clean and blue; Neon City is busy, wet and pink and orange.
- **Theme mechanics (2-3, `mechanics/neon_*.gd`):**
  - **Hover-car traffic lanes:** cars stream past on a lane at intervals. Some you ride as moving platforms; others
    you cross between.
  - **Searchlight drones:** sweeping light cones that knock you back or kill, telegraphed.
  - **Hologram platforms** that flicker in and out on a clock, like Manor's phantoms but with a visible glitch tell.
  - **Billboard panels** that flip or rotate.
  - **Window-cleaning gondolas:** lifts.
  - **Neon-tube rails:** grind / conveyor.
- **Set piece:** riding a stream of hover cars across a canyon between towers, hopping lane to lane as they pass. The
  finish is the top of the tower's antenna spire with the whole city below.

## Order and difficulty
Sakura < Jungle < Frontier < Neon. All of them are harder than Super Carrier and easier than The Final Ascent.

## Verify
Use the same verify steps as the earlier briefs, with the new indices: **14 sakura, 15 jungle, 16 frontier,
17 neon**.
- The test runner now has `--skip=<substring>`.
- Bot runs are long, so run one level at a time: `--only=test_n_bot --level=N --route=all`.
- After you check out or merge, run a headless `--import` before testing. Otherwise new class names fail to load.
