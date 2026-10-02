# NEW WORLDS 4 brief: four VERY HARD levels
Levels: 20 Doom Fortress, 21 The Abyss, 22 Tempest Tower, 23 The Void.

Owner (2026-10-02): "add 3 more levels my dude. make them very hard". They picked all four offered themes, placed
**before The Final Ascent** (now `levels/level_24_ascent.*`).

**This brief extends `docs/NEW_WORLDS_3_BRIEF.md`, `NEW_WORLDS_2_BRIEF.md` and `NEW_WORLDS_BRIEF.md`.** Read all
three first. Every rule in them applies unchanged:
- the definition of done, the verify steps, the sound-hook conventions and the report format;
- all the hard lessons:
  - the 1.0 s human-pause check;
  - at least 1.5 s of slack on timed hazards;
  - no overlapping visuals;
  - no NaN and bounded HDR in shaders;
  - particles through `Settings.particle_scale()`.

The quality bar is the newest levels, 16-19 (`level_16_sakura.gd` ... `level_19_neon.gd`).

New order (0-based index): ... 17 neon, **18 doom, 19 abyss, 20 tempest, 21 void**, 22 ascent. The placeholders,
the `Look.THEMES` entries, the `Game.LEVELS` lines (provisional medals) and `SaveData.LAYOUT_REV` are in place. The
lead writes the scores and the sound.

## What "very hard" means here (every one of these, measured)
This is a difficulty tier above everything shipped so far. It is hard through **precision, pace and combination**,
never through unfairness. The owner was burned once by an end-section that was "unbeatable" for humans, so:
- **Jumps:**
  - The main path's hardest jump is **92-95%** of max reach (`test_m`). At least **12 main-path jumps are 85% or
    more**.
  - Shortcuts may reach 96-97% (still listed and measured).
- **Landings:**
  - At least a third of main-path landings are **1.0-1.4 m** wide (posts, beams, rails, small blocks).
  - Never under 0.9 m.
- **Longer stretches between checkpoints:** **14 checkpoints** (15 stages) rather than 17, so each stage chains
  more moves. Stages must still read as distinct beats.
- **Combinations:** almost every stage combines **2-3 different demands back to back**, for example:
  - a moving target, then a timed hazard, then a wall run;
  - a mantle under a crusher's cycle;
  - a precision hop chain while a sweeper passes.
- **Pace:** fewer "stand and wait" moments. Prefer hazards you thread **on the move**, with the timing built in, over
  cycles you wait out. A waiting player loses time, not their life.
- **Fairness rules are NOT relaxed:**
  - Every timed hazard still tells you **at least 0.8 s ahead**, visibly and audibly.
  - Every wait the bot makes still has **at least 1.5 s of slack**.
  - The bot must still finish **every route with 0 respawns, both without and with the 1.0 s pause after every wait
    and checkpoint**, on your final commit. A level the frame-perfect bot can't do cleanly with a human's pauses is
    not hard; it's broken.
- **Medals:** with these, the Gold time will genuinely demand mastery. Make the shortcut route a real time saver, but
  a risky one.

## Make each one clearly different from the existing worlds
- **Doom Fortress** must not look like Clockwork Heights (brass clock tower), Bounce Foundry or Cinder Peak (volcano).
- **The Abyss** must not look like Coral Depths (sunny, shallow and colourful). It is **pitch-dark deep water** lit
  only by bioluminescence and the player's own lamp.
- **Tempest Tower** must not look like Storm Armada (wooden airships) or Neon City / The Final Ascent (night neon).
  It is grey steel and glass in a howling daytime hurricane.
- **The Void** must not look like Orbital Drift (space station) or The Final Ascent. It is surreal and dreamlike, not
  sci-fi.

## Level 20 - DOOM FORTRESS (`theme_id = "doom"`, `music_track = "doom"`)
Inside a giant doomsday machine that is tearing itself apart. Red alarm beacons spin, klaxon light washes the halls,
sparks and steam everywhere.
- **Setting:**
  - Black iron and riveted steel, huge interlocking gears turning in the dark, forges pouring white-hot metal into
    channels far below.
  - Hazard stripes, warning lights, collapsing catwalks, a reactor core glowing at the heart.
  - A palette of black, gunmetal and red alarm light, with molten orange.
- **Theme mechanics (2-3, `mechanics/doom_*.gd`):**
  - **Gear teeth:** ride a huge rotating gear's rim, or hop tooth to tooth.
  - **Steam vents:** blast you up on a clock, or burn you.
  - **Alarm-cycle hazards:** the whole stage changes state on a klaxon.
  - **Molten pour:** a crucible tips and molten metal sweeps a lane.
  - **Collapsing catwalks:** sections fall a beat after you land.
  - **Grinder rollers.**
- **Set piece:** the **reactor meltdown climb**. Up the inside of the core while it pulses, each pulse a telegraphed
  ring of energy you must be clear of. The finish is the off switch at the top.

## Level 21 - THE ABYSS (`theme_id = "abyss"`, `music_track = "abyss"`)
Down, then up, a black ocean trench. The only light comes from bioluminescent creatures, glowing plants and your own
glow.
- **Setting:**
  - Pitch-dark water with marine snow drifting, jellyfish pulsing, glowing kelp and tube worms, hydrothermal vents.
  - A huge whale skeleton, an angler fish's lure in the dark, a wrecked deep-sea submarine at the end.
  - Keep the course readable: **platforms carry their own glowing edges and markers**. Darkness must never hide where
    you can stand.
- **Movement feel:** you are still on foot (standard physics), but the water is shown by drifting particles, light
  shafts that never reach the bottom, and slow-moving creatures.
- **Theme mechanics (2-3, `mechanics/abyss_*.gd`):**
  - **Currents:** a visible stream of particles that pushes you sideways or up, like conveyors in the air.
  - **Jellyfish:** bounce pads that drift or pulse.
  - **Vents:** bubbling geysers that launch you, on a clock.
  - **Angler lure:** a light that leads, then the jaw snaps.
  - **Collapsing coral and shell bridges.**
  - **Glowing platforms that dim:** they are solid while lit.
- **Set piece:** the **leviathan pass**. A huge shadowy creature (never fully seen) sweeps past, and its passing
  surge is a telegraphed push across a precision chain. The finish is on the conning tower of the wrecked submarine.

## Level 22 - TEMPEST TOWER (`theme_id = "tempest"`, `music_track = "tempest"`)
The outside of a mile-high skyscraper under construction, in a hurricane in daylight.
- **Setting:**
  - Grey steel frame, glass curtain walls, cranes, scaffolding, window-cleaning rigs.
  - Torn tarps snapping in the wind, sheets of rain, debris blowing past, the city far below through the cloud.
  - Lightning in the storm wall.
- **Theme mechanics (2-3, `mechanics/tempest_*.gd`):**
  - **Gusts:** telegraphed wind bursts that shove you. A wave of rain and debris crosses toward you about 1.2 s ahead.
  - **Swinging crane loads:** girders on cables you ride or dodge.
  - **Lightning rods:** a charge builds, then strikes.
  - **Failing scaffolding:** it sways, then drops.
  - **Window-washer gondolas:** lifts.
  - **Flapping tarps:** platforms that tilt.
- **Set piece:** **riding a tower crane's jib** as it slews across the gap between towers in the storm, then the final
  climb up the exposed spire to the aircraft-warning beacon at the top.

## Level 23 - THE VOID (`theme_id = "void"`, `music_track = "void"`)
A surreal dream of floating impossible geometry that is coming apart. This is the last level before the finale and
the hardest of the four.
- **Setting:**
  - Escher-like stairs, floating doors and arches, chessboard floors, giant clocks without hands, inverted rooms
    hanging in a violet-black void.
  - Mirrors, slow-falling fragments, a shattered sky.
  - Clean white geometry against the dark, accented in pink and cyan.
- **Theme mechanics (2-3, `mechanics/void_*.gd`):**
  - **Phase platforms:** two alternating sets swap on a beat, shown ahead of time.
  - **Low-gravity / up-draft rifts:** zones that change your jump arc, clearly marked.
  - **Portals:** doors that send you elsewhere.
  - **Rotating rooms:** a room tilts and turns so a wall becomes the floor. Use rotating platforms the player rides,
    not actual gravity changes.
  - **Crumbling stairs.**
  - **Mirror doubles:** a platform exists only while its reflection does.
- **Set piece:** **the collapse**. The last stretch falls apart behind you in a telegraphed wave (outrun it), up a
  stair of fragments to the finish, a door in the sky.
- **Gravity changes:** if you implement real gravity flips, the bot and the validator must still handle them. Prefer
  up-draft and low-gravity zones plus rotating platforms unless you can test real flips properly.

## Order and difficulty
All four are harder than every existing course, ramping Doom < Abyss < Tempest < Void. The Final Ascent stays the
finale after them.

## Verify
Use the same verify steps as the earlier briefs, with the new indices **18 doom, 19 abyss, 20 tempest, 21 void**.
- Use `--save=<name>` on every test run, because several agents test in parallel.
- Run the bots one level at a time: `--only=test_n_bot --level=N --route=all`.
- Run a headless `--import` after checkout.
- Report the `test_m` jump statistics:
  - the hardest jump;
  - how many main-path jumps are 85% or more;
  - the narrowest landing.
