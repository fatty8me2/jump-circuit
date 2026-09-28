# NEW WORLDS 2 brief - levels 11 Phantom Manor, 12 Storm Armada, 13 Sugar Rush, 14 Super Carrier

Owner (2026-09-28): "spin up some more agents to build 3 more unique maps, you have done such an awesome job so far".
**This brief extends `docs/NEW_WORLDS_BRIEF.md`**: read that one first. Every rule, the definition of done, the
verify steps, the sound-hook conventions and the report format there all apply here unchanged. Also read the four
levels built from it, which are the current quality bar: `levels/level_7_xeno.gd`, `level_8_volcano.gd`,
`level_9_glacier.gd`, `level_10_desert.gd`.

New order (0-based index): ... 9 desert, **10 manor**, **11 armada**, **12 candy**, **13 carrier**, 14 ascent (the finale, now
`levels/level_15_ascent.*`). The placeholders, the `Look.THEMES` entries, the `Game.LEVELS` lines, `SaveData.LAYOUT_REV`
and the music tracks are already in place. The lead is writing the scores and the sound.

## Lessons from the last round (these are hard rules now)
- **The bot is not a human.** It is frame-perfect. The owner found Frostbite Pass's avalanche "unbeatable" even
  though the bot passed with 0 respawns. For every timed hazard, give at least about 1.5 s of slack beyond perfect
  timing. As a robustness check, temporarily make the bot pause 1.0 s after every wait and every checkpoint; it
  must still finish. Remove that hook before you commit.
- **No overlapping visuals.** Decorative meshes must never poke through walkable platforms, checkpoints,
  shelters or other set pieces, and moving hazards must never pass through the geometry they are meant to hit.
- **Shaders must never produce NaN.** Clamp before `pow()`, never `normalize()` a vector that can be zero, and keep
  `smoothstep()` edges in order. A NaN in Scarab Sands' sky blacked out the whole level, and headless tests cannot
  see it.
- **Keep emissive / HDR terms bounded.** Cinder Peak's ash cloud glowed so hard that it washed the whole sky orange.
- **Every particle system's amount goes through `Settings.particle_scale()`,** so the new Particles slider
  controls it (see how the other levels build emitters).

## Level 11 - PHANTOM MANOR (`theme_id = "manor"`, `music_track = "manor"`)
A haunted gothic mansion and its graveyard on a cliff, under a huge blood moon, at midnight.
- **Setting:** crooked towers, broken stained-glass windows glowing from inside, a hedge-maze cemetery with leaning
  tombstones and mausoleums, dead trees, a drifting ground fog, will-o'-wisps, bats crossing the moon, candles and
  chandeliers inside. Purple, bone-white and sickly-green palette with the red moon.
- **Theme mechanics (2-3, `mechanics/manor_*.gd`):**
  - **Phantom platforms:** ghostly furniture that is solid only while a lantern light shines on it, or that phases
    in and out.
  - **Portrait eyes:** a sweeping gaze beam that kills or pushes back.
  - **Possessed furniture:** chairs, tables and armoires that float and orbit as moving platforms.
  - **Collapsing floorboards.**
  - **Swinging chandeliers:** pendulum rides.
  - **Coffin lids that snap shut:** crusher-like.
  - **Mirror portals.**
- **Set piece:** something like the grand ballroom, where the ghosts waltz as moving platforms while the chandelier
  swings, or a chase through the halls by a spectral wave. The last stage climbs the bell tower to the finish.

## Level 12 - STORM ARMADA (`theme_id = "armada"`, `music_track = "armada"`)
A fleet of sky-pirate airships in a thunderstorm high above the clouds; you cross from ship to ship.
- **Setting:** wooden galleons hung under huge balloons, brass propellers, rigging, cannons, flags, a sea of storm
  clouds below lit by lightning, rain streaks, and sunset breaking through at the finish on the flagship.
  Warm wood and brass against a dark blue-grey storm.
- **Theme mechanics (2-3, `mechanics/armada_*.gd`):**
  - **Cannon volleys:** cannonballs fired on a clock, with a warning flash and smoke puff, that knock you away or
    kill.
  - **Rolling decks:** ships pitch and roll; use tilt / moving platforms.
  - **Rope swings and zip-lines between ships:** a ride.
  - **Propeller updrafts.**
  - **Lightning strikes:** on marked rods, telegraphed.
  - **Gangplanks that retract.**
- **Set piece:** a boarding run across a broadside while two ships trade cannon fire, or riding a falling mast
  between ships.

## Level 13 - SUGAR RUSH (`theme_id = "candy"`, `music_track = "candy"`)
A candy and toy-box dreamworld: bright, bouncy, joyful and completely different in mood from every other level.
- **Setting:** candy-cane pillars, frosted cake platforms, lollipop trees, gumdrop hills, chocolate rivers (the kill
  surfaces), cotton-candy clouds, a sprinkle rain, toy blocks and wind-up toys, a pastel sky with a rainbow.
- **Theme mechanics (2-3, `mechanics/candy_*.gd`):**
  - **Jelly platforms:** they wobble and bounce you higher the more you fall onto them.
  - **Taffy pull bridges:** they stretch and sag.
  - **Wind-up toy soldiers:** marching sweepers.
  - **Jack-in-the-box launchers:** timed pistons that launch you.
  - **Conveyor licorice.**
  - **Melting ice-cream platforms.**
  - **A giant rolling gumball.**
- **Set piece:** a giant toy train loop you ride through the level, or a gumball machine run.

## Level 14 - SUPER CARRIER (`theme_id = "carrier"`, `music_track = "carrier"`)
Owner's own idea: "a US aircraft carrier, where you play through an enormous jump course through an aircraft
carrier, and end the jump puzzle at the top of the command tower".
- **Scale:** the whole level is one gigantic supercarrier (about 330 m long) on open ocean on a bright day.
- **Route:** start on the fantail or down in the hangar bay, run and climb stem to stern and through the ship, then
  climb the island superstructure to finish at the very top: the mast and radar deck above the bridge.
- **Setting:**
  - Grey hull and deck, yellow deck markings and the angled landing strip, catapult tracks with steam.
  - Parked jets with folded wings and helicopters (built from primitives, generic, no real insignia or brands).
  - Deck tractors, arresting wires, jet blast deflectors, deck-edge elevators.
  - The hangar bay's cavernous interior, catwalks, antennas and spinning radars.
  - Escort ships on the horizon, sea spray, wake foam, gulls.
- **Theme mechanics (2-3, `mechanics/carrier_*.gd`):**
  - **Catapult launches:** a steam catapult boost that flings you along the deck.
  - **Jet blast deflectors:** raising walls, plus jet exhaust that pushes you on a clock.
  - **Deck-edge aircraft elevators:** huge moving platforms between the hangar and the flight deck.
  - **Arresting wires:** taut, bouncy lines.
  - **Moving deck tractors / tugs.**
  - **Rotating radar arrays:** sweeper rides near the top.
  - **Hatch and ladder chimneys up the island.**
- **Set piece:** a launch sequence (a jet taxis and a catapult fires on the clock, with the blast deflector rising
  behind it: time your run between launches), then the final climb up the tower's outside.
- **Content:** keep it heroic and generic. No real ship names, hull numbers or unit insignia; a plain "U.S. Navy"-style
  grey look is fine.

## Order and difficulty
Manor < Armada < Candy < Carrier, all between Scarab Sands and The Final Ascent. Candy is bright and fun but still hard:
it plays as a bounce and momentum showcase.

## Verify
Use the same verify steps as the first brief, with the new indices: **10 manor, 11 armada, 12 candy, 13 carrier**.
