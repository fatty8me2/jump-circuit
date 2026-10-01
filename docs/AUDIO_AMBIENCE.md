# Jump Circuit - Map Soundscapes (Ambience)

Every map has its own soundscape: a **bed** (a seamless stereo loop of the place itself:
wind in the leaves, furnace roar, surf far below, a tower full of clocks) and **one-shots**
(birdsong, gulls, far-off clanks, whale song, sirens) that `sound/soundscape.gd` schedules
at random and places in 3D around the listener. Like the rest of the audio, everything is
original and synthesised from maths and seeded noise by `tools/gen_ambience.py` (it reuses
the helpers in `tools/gen_audio.py`). No samples, so no third-party licences are involved.

## Regenerating

```
python tools/gen_ambience.py              # generate everything into audio/, then verify
python tools/gen_ambience.py --beds       # beds only
python tools/gen_ambience.py --shots      # one-shots only
python tools/gen_ambience.py --only=reef  # only files whose name contains "reef" (skips the full verify)
python tools/gen_ambience.py --verify     # only check the files on disk
```

* Needs Python 3, numpy and soundfile. Generating everything takes about 8 minutes.
* Deterministic: every clip has its own RNG (`SEED` + CRC of its name). libsndfile gives each
  Ogg stream a random serial number, so the generator pins the serial and rewrites the page
  CRCs, which makes re-runs bit-identical.
* Afterwards run `tools/Godot_v4.7.1-stable_win64.exe --headless --path . --import` once.

`--verify` checks every file. For **beds**: Ogg, 32 kHz, stereo, 45-90 s, RMS within 1 dB of the
target, peak under -3 dBFS, and less than 35 % of the energy below 80 Hz. It also checks the
loop seam on the *decoded* file: the sample step and the curvature across the wrap must be no
larger than ordinary ones inside the file, and the level of the last 50 ms must match the first
50 ms. For **one-shots**: 44.1 kHz mono, 0.2-10 s, peak about -3 dBFS, silent first and last
samples. It fails on missing or stray `amb_*` files and when the total goes over 34 MB.

## Formats and levels

| Group     | Files                            | Format                         | Level |
|-----------|----------------------------------|--------------------------------|-------|
| Beds      | `amb_<theme>.ogg` (+ layers)     | Ogg Vorbis, 32 kHz stereo      | -24 to -27 dBFS RMS (title -30; the glacier and desert storm layers, the manor's tower, the carrier's island, Sakura Peaks' keep and the frontier train's engine are 1 dB above their base beds, and the armada's flagship 1 dB below, as the storm breaks); a memoryless soft knee holds peaks under -4 dBFS; 40 Hz high-pass, 6-9 kHz low-pass |
| One-shots | `amb_<theme>_<event>_<n>.ogg`    | Ogg Vorbis, 44.1 kHz mono      | peak normalised to -3 dBFS; the runtime plays them 8-22 dB down |

One-shots are Ogg rather than WAV to keep within the size budget: the 292 clips add up to about
1090 s, which would be about 96 MB as 44.1 kHz 16-bit WAV, against 8.5 MB as Ogg. Nothing is
timing-critical, so Ogg's decode latency doesn't matter. Total size: about 30.9 MB (34 beds 22.5 MB,
292 one-shots 8.5 MB).

The beds sit well under the music and effects. They are rolled off at both ends, so there is
no masking sub rumble and no fizzy top that tires the ear over a long session.

### How a bed loops without a seam

Beds are rendered into **circular buffers**, the same way the music is. Every event is mixed in
at its sample index modulo the loop length, so a wave or a bird that runs past the end wraps
round to the start. Noise filters, reverbs (a synthetic diffuse impulse response, convolved
circularly) and moving filters (a circular STFT overlap-add) all work over the whole loop.
Every modulation completes a whole number of cycles, and tones are tuned to whole cycles per
loop. Slow random curves (gusts, flicker) are periodic low-passed noise. The stems are
balanced to a table of relative levels. The only processing after that is a gain and a
memoryless soft knee, and neither can create a discontinuity.

## Runtime: `sound/soundscape.gd`

`Soundscape.make(theme_id)` is added by `LevelBase._ready()` (outside headless runs, next to
the score) and by the title diorama (`"title"`). An unknown theme builds a silent node.

* **Bed:** an `AudioStreamPlayer` on the **Ambience** bus (its own volume slider). The runtime
  sets `AudioStreamOggVorbis.loop = true`. It fades in over 3 s and uses `PROCESS_MODE_ALWAYS`,
  so it plays on under the pause menu, where `Sfx.muffle()` low-passes the Ambience bus.
* **Layer:** a second bed that crossfades in (equal-power) as course progress
  (`current_checkpoint / checkpoints.size()`, eased at 0.05 per second) goes from `from` to `to`.
  Coral Depths darkens into `amb_reef_deep`. Xeno Wilds grows wilder (`amb_xeno_deep`), Cinder
  Peak roars louder near the crater (`amb_volcano_crater`), the blizzard closes in over Frostbite
  Pass (`amb_glacier_storm`) and the sandstorm reaches Scarab Sands (`amb_desert_storm`). Phantom
  Manor climbs into its bell tower (`amb_manor_tower`), the storm breaks as Storm Armada reaches
  the flagship (`amb_armada_flagship`), Sugar Rush rises into the cotton-candy clouds
  (`amb_candy_high`) and the wind howls round Super Carrier's island (`amb_carrier_island`). The
  wind, the banners and a great bronze bell take over at Sakura Peaks' castle keep
  (`amb_sakura_keep`), Jungle Temple opens out into the wind at the top of the pyramid with the
  waterfall below (`amb_jungle_top`), the engine comes near as the Wild West Heist reaches the
  locomotive (`amb_frontier_loco`) and the gale rises round Neon City's spire as the rain thins
  (`amb_neon_spire`). Near
  the top of the Final Ascent, `amb_ascent_high` takes over: stronger, howling wind with the city
  further away.
* **One-shots:** each event counts down a random interval. When it is due, it plays with
  `chance` (lerped between the course start and end) on one of 8 pooled `AudioStreamPlayer3D`s
  on the Ambience bus. The player is placed at a random bearing and distance from the current
  camera, at a random height (negative = below). `unit_size` is set to the spawn distance, so
  the table level is what you hear there. The distance cues (dullness, reverb) are baked into
  the clips, so the 3D attenuation filter is off. `travel` makes the source drift sideways past
  the listener while it plays (fly-bys pan across). `answer` gives a chance that a second call
  of the same kind answers from elsewhere 0.8-2.5 s later. The variant is random but never the
  same twice running. The schedule and the one-shot players pause with the tree.
* **Scene changes:** when a map is left, its bed is handed to a short-lived player on the root
  that fades out over 1.5 s instead of cutting. If the same map loads again within 2.5 s (a
  restart reloads the scene), the new bed carries on from the same point at full level, and
  the tail is dropped.

## Beds

| File | Length | Synthesis |
|------|--------|-----------|
| `amb_gardens.ogg` | 64 s | Gust curve (periodic smooth noise, three swells per loop). Pink-noise breeze body. Leaf rustle: a soft 0.7-4.5 kHz rustle plus a flutter (1.2-6 kHz noise chopped by a fast, bounded, jittery envelope), both rising with the gusts; the right channel hears each gust 0.45 s later, so it sweeps across. About 30 distant bird phrases (the one-shot species, dulled and reverberated), busier in some stretches than others. Grasshopper bursts (4-9 kHz noise pulsed at about 35 Hz) now and then. |
| `amb_title.ogg` | 48 s | The gardens recipe, gentler: a calmer breeze, 10 far birds, no insects, at -30 dBFS. |
| `amb_foundry.ogg` | 56 s | Furnace roar (reddish noise 60-800 Hz with a slow flicker) plus a fluttering 250-1800 Hz combustion band. A soft 38-95 Hz rumble. About 260 slag bubbles in clusters (low tones gliding up as they swell, some ending in a pop). A distant press thumping 24 times a loop, each thump followed by a clank, and a 47 Hz-series machine hum, all in a large hall reverb. Far vents sighing. |
| `amb_balance.ogg` | 64 s | Surf far below: waves tiled irregularly over the loop, each swelling for 1.5-2.5 s, then crashing (a 250-3200 Hz break) and washing out, with a granular foam fizz after the crash. The whole sea is dulled at 2.4 kHz. A continuous sea wash. Gusting wind with a whistling resonance (420-820 Hz) that rises with the gusts. Four singing cables (aeolian tones whose pitch rides the wind speed). Soft taps of rigging at gust peaks. |
| `amb_clockwork.ogg` | 60 s | Eight clocks at different rates (30-150 ticks per loop: 0.4 s to 2 s periods). Each has its own tick and tock kernels (a click exciting damped modes), its own pitch, pan and distance, a slowly breathing level and 1.5 ms of jitter. The slowest is the wooden tower escapement with a brass ring after every other beat. Also a gear-train whirr (noise gated at the tooth rate), a 55 Hz mechanism hum and wind round the tower, in a stone-room reverb. |
| `amb_reef.ogg` | 64 s | Muffled pressure (reddish noise 42-360 Hz) swelling with a slow surge, surface slosh, bubble streams (a vent's worth of Minnaert bubbles, each a damped sine rising in pitch, from one spot for a few seconds), stray bubbles and a faint snapping-shrimp crackle. Everything is low-passed (under water) and in a dense, dark reverb. |
| `amb_reef_deep.ogg` | 64 s | The deep: darker pressure, a slower surge, few, larger bubbles, slow groans of shifting rock (low tone glides) and the temple's hollow resonance (noise through fixed 310 / 505 / 870 Hz resonances). Low-passed further, in a 3 s cavern reverb. Crossfades in from 25 % to 85 % of the course. |
| `amb_orbital.ogg` | 60 s | Air handler: two fan motors a third of a hertz apart (a slow beat), weighted to their 2nd-4th harmonics, with a blade-pass tone. Ventilation airflow through fixed duct resonances. A coolant-pump whoosh cycle. A 2.35 kHz electrical whine and a 120 Hz mains buzz drifting in and out. Relays clicking in the walls. |
| `amb_ascent.ogg` | 64 s | The city far below: a broadband wash and about 44 distant traffic passes (band-passed noise swells that pan as they go). High-altitude wind with a howl (460-1150 Hz) that rises with the gusts. A neon transformer buzz (120 Hz harmonics plus gas fizz) that flickers now and then. |
| `amb_ascent_high.ogg` | 64 s | The same world higher up: gustier and louder wind with a stronger howl, and the city further away and duller. Crossfades in from 30 % to 95 % of the course. |
| `amb_xeno.ogg` | 64 s | An alien jungle. The planet's hum: two drones on inharmonic partials (73 Hz x 1 : 2.01 : 2.98 : 4.13 : 5.31 : 6.9) a hair apart (a slow beat), weighted to the upper partials, over a low churning band through a wandering resonance. Wind in the fronds. Five crystal spires bowed by the gusts: glassy partials (1 : 2.32 : 4.25 : 6.63, each a detuned pair) on a 13-tone scale, with a breathy bow noise, singing only when a gust reaches them. About 38 far creature calls (the one-shot voices, dulled and reverberated), busier in some stretches than others. Acid pools: streams of thick bubbles and an effervescent fizz. Every 14-24 s a deep formant call from something big, far off. |
| `amb_xeno_deep.ogg` | 64 s | Deeper in: a stronger hum, three spires instead of five, a denser chorus of creatures (55), deep calls every 9-16 s, and a pulsing chorus of frog-like things (inharmonic tones pulsed 5-11 times a second and ring-modulated, each singing in stretches). Crossfades in from 35 % to 90 % of the course. |
| `amb_volcano.ogg` | 64 s | The mountain. A deep rumble (dark noise band-limited to 45-220 Hz and kept under the rest). The eruption's roar (reddish 90-1300 Hz noise that surges and tears). The lava fountain gushing (swelling whooshes). Lava crackling (a carpet of sharp ticks and small pops). Three fumaroles hissing. Wind off the summit with a low 280-560 Hz moan, carrying a patter of ash. Soft, deep booms every 14-24 s. |
| `amb_volcano_crater.ogg` | 64 s | Near the crater: the roar brighter (to 2.4 kHz) and surging harder, the fountain gushing louder, twice the crackle and spatter, and booms every 9-16 s. Crossfades in from 30 % to 95 % of the course. |
| `amb_glacier.ogg` | 64 s | A blizzard over the pass. Wind howling over it (a 420-980 Hz whistle that rises with the gusts) and a lower moan round the fortress walls (230-410 Hz) on its own gust timing. Blowing snow (a 3-8 kHz hiss and grains ticking off the ice, both following the gusts). The glacier and the walls creaking and groaning (slow stick-slip through 70-1200 Hz resonances that bend in pitch), and the ice "singing": 14 dispersive pews a loop (see AUDIO_WORLD.md). Distant glacier cracks that boom and roll off the peaks. A faint shimmer of ice crystals tinkling in the air, more in the gusts. |
| `amb_glacier_storm.ogg` | 64 s | The blizzard closing in: stronger, more constant gusts, a louder, brighter and higher howl, more snow, and the ice and cracks further back. It is 1 dB louder than the base bed, so the wind rises as it takes over. Crossfades in from 25 % to 90 % of the course. |
| `amb_desert.ogg` | 64 s | A sun temple amid dunes. Hot, dry wind with only a low, breathy moan. Sand skipping over the dunes (saltation: a granular 1.8-8.5 kHz hiss that rises steeply with the gusts, over a softer ripple). A far sandstorm (70-900 Hz roar, surging slowly). The temple's halls resonating faintly in the wind (noise through fixed 118/191/287/412 Hz hall modes), and now and then a far knock or a trickle of sand echoing inside. Cicadas in the afternoon heat: three far buzzing drones, each singing in stretches. |
| `amb_desert_storm.ogg` | 64 s | The sandstorm arrives: stronger gusts, twice the sand, the storm's roar near and bright (to 1.8 kHz), no cicadas, the temple faint. It is 1 dB louder than the base bed. Crossfades in from 30 % to 95 % of the course. |
| `amb_manor.ogg` | 64 s | A haunted house at midnight. Wind through the broken windows: a thin whistle (a Q 11 resonance climbing 620 -> 1200 Hz with the gusts) over a soft body, and a low moan down the halls (240-380 Hz) on its own gust timing. A pipe organ somewhere in the house, heard through the walls: two ranks a hair apart (a slow chorus) holding D minor, turning to B-flat and back over the loop, weighted to the upper harmonics, swelling, with a little tremulant and the wind in the pipes, low-passed at 1.5 kHz. The house settling: old timber creaking every 5-12 s (stick-slip through four wood resonances). A grandfather clock's tick-tock (wooden, one a second) in the hall. Three far crickets in the graveyard (pure 3.8-5.2 kHz chirps of 2-4 pulses, singing in stretches). |
| `amb_manor_tower.ogg` | 64 s | Up the bell tower: stronger, higher wind (the whistle to 1350 Hz), the organ further below and duller, more creaking beams (every 3.5-8 s), the tower clock's slow, heavy beat (every 2 s), and the great bell humming faintly as the gusts catch it (its partials, each a beating pair). No crickets. It is 1 dB louder than the base bed. Crossfades in from 40 % to 95 % of the course. |
| `amb_armada.ogg` | 64 s | A thunderstorm above the clouds. Rain on a wooden ship: a hiss, a patter of drops (clicks 1-7 kHz, 2600 a second at full gust) and the heavier drops ringing on the planking (three wood modes). Gusting wind howling through the rigging (480-1100 Hz). Thunder rolling far off every 9-18 s (the physical model below, 1.3-2.6 km away, sometimes with a restrike). Mast groans and rope creaks. Sails flogging in the gusts (noise slapped 4-8 times a second, each slap with a crack of cloth). The ship's propellers: an engine tone (61 and 63.5 Hz stacks) chopped by the blade pass (14-15 Hz), and the air they throw. |
| `amb_armada_flagship.ogg` | 64 s | The storm breaking over the flagship: the wind easing, the rain down to a drizzle, the thunder further off and rarer (every 18-30 s, 2-3.5 km), the flagship's propellers and timbers close by, and gulls out over the clouds again (the Balance Works gull voices, far off). 1 dB quieter than the base bed. Crossfades in from 50 % to 95 % of the course. |
| `amb_candy.ogg` | 64 s | A candy dreamworld, bright and warm. A soft breeze with no howl in it. The breeze plays a music box: about 60 tines plucked a loop on C major pentatonic (C6 upwards; a cantilevered steel reed with partials 1 : 5.93 : 17.5, and the pin's tick), a fifth of them little rising runs, more in the gusts. Soda springs: an effervescent fizz (500 tiny pops a second, 3-10 kHz) and 160 small bubbles rising. The chocolate river: a thick, slow flow (dark noise 60-600 Hz, surging four times a loop) and 120 lazy gloops (90-200 Hz tones rising as they swell). Sugar sparkles: tiny glockenspiel tings two octaves up. |
| `amb_candy_high.ogg` | 64 s | Up among the cotton-candy clouds: a stronger, airier breeze, half again as many music-box notes, twice the sparkles, and the chocolate river far below and duller. Crossfades in from 30 % to 95 % of the course. |
| `amb_carrier.ogg` | 64 s | The flight deck of a supercarrier on a bright day. Wind over the deck that never drops away (the ship steams into the wind), with a soft 380-700 Hz moan. The sea far below: swells running along the hull and slapping it every 3-6 s, a continuous wash, the bow wave and the wake's foam, dulled at 2.8 kHz. Jets idling on deck: two turbine whines (3150 and 3420 Hz with a lower spool) drifting in and out, and their roar. The ship's machinery and ventilation humming up through the deck (60 Hz harmonics). |
| `amb_carrier_island.ogg` | 64 s | Near the top of the island: the wind stronger, gustier and howling round the masts and antennas (a Q 10 whistle, 700 -> 1500 Hz), halyard clips tinking against the mast in the gusts, a flag flogging, the radar turning overhead (its 400 Hz motor and a whoosh of air each time the array sweeps by, 16 times a loop), and the sea and jets further below. It is 1 dB louder than the base bed. Crossfades in from 50 % to 95 % of the course. |
| `amb_sakura.ogg` | 64 s | A mountain temple at dusk. Wind sighing through the pines (a broad 330-620 Hz resonance) and the bamboo leaves rustling with it (a soft rustle and a chopped flutter). Bamboo culms knocking together in the gusts (hollow tubes: three short modes and a click, one to three clacks at a time). Wind chimes on the eaves (metal tubes on D minor pentatonic, from D5) set going by the gusts. The monks' chant drifting up from a temple below: **no words**, a drone of five low voices (two on D2 a hair apart, A2, D3 and A1) held on one vowel (fixed 420 / 820 Hz formants), each breathing in its own time so the drone never breaks. The koi pond's inflow babbling (a 400-3000 Hz babble and 500 small bubbles). Four evening crickets (the manor's model). |
| `amb_sakura_keep.ogg` | 64 s | The castle keep: a stronger, higher wind (a Q 8 howl, 560 -> 1150 Hz), banners flogging on the roof (the canvas model, every 3-7 s), the great bronze bell humming as the gusts catch it (its D3 partials, each a beating pair), more chimes, the chant and the bamboo further below, two crickets, no pond. It is 1 dB louder than the base bed. Crossfades in from 50 % to 95 % of the course. |
| `amb_jungle.ogg` | 64 s | Deep rainforest. The insect chorus: six cicada-like drones (3.2-7 kHz tones and bands buzzed at 90-220 Hz, each singing in stretches) and four katydids ticking (2-3 pulses of 5-9 kHz noise, 1.5-3.5 calls a second). About 110 runs of tree frogs (whistled 2-3.2 kHz peeps and harmonic 600-950 Hz quarks). 320 drips (plinks into puddles and taps on broad leaves). A waterfall off to one side (an 80-2600 Hz roar and its spray). A light breeze in the canopy. About 26 far bird calls (the one-shot species dulled at 4.5 kHz). Thunder rolling 3.5-5 km away a couple of times a loop. |
| `amb_jungle_top.ogg` | 64 s | The top of the pyramid: open air and a real wind (a soft 380-760 Hz howl), the waterfall below (darker, to 1.5 kHz, and louder), half the insects, fewer frogs, drips and birds. Crossfades in from 50 % to 95 % of the course. |
| `amb_frontier.ogg` | 64 s | Riding a steam train through a canyon. Clickety-clack: once a second the trucks of two cars cross a rail joint ("da-dum, da-dum": four wheel thumps, each a 140 -> 70 Hz knock with a short steel ring 0.9-3.6 kHz), from our car and two cars further along (quieter, duller); the loop point sits in the quiet between joints. The cars rolling (a 70-700 Hz rumble and a wheel roar). The locomotive far ahead, dulled at 1.1 kHz: eight exhaust chuffs a second (two turns of the drivers), unevenly accented. Canyon wind whistling round the cars (480-900 Hz). The wooden cars creaking every 3-7 s. A long, canyon-like reverb with a 70 ms predelay. |
| `amb_frontier_loco.ogg` | 64 s | On the engine: the chuffs loud and bright, steam hissing from the valves (2.5-8 kHz), the firebox roar, the side rods clanking twice a second, and the bell (G) rung 10-14 times for a crossing once a loop; the wheels and wind further back. It is 1 dB louder than the base bed. Crossfades in from 50 % to 95 % of the course. |
| `amb_neon.ogg` | 64 s | Rooftops in a downpour. Rain: a 1.5-9 kHz hiss, 3200 drops a second (clicks 1-7 kHz), the heavier ones pinging on sheet metal (four modes, 0.9-4.8 kHz) and slapping into puddles. Gutters overflowing and a down pipe gurgling (300 low bubbles). The city's traffic hum (60-1100 Hz). 24 hover cars whooshing past (a 180-280 Hz turbine hum dropping in pitch as it passes, under a rush of air, panning across). Three neon signs buzzing (120 Hz harmonics and gas fizz), each flickering in its own way. The club in the basement, muffled through the floors: a 120 bpm kick (under 180 Hz) and an offbeat bass line in E minor (E E C D, a bar each, under 220 Hz). A light breeze between the buildings. |
| `amb_neon_spire.ogg` | 64 s | The spire: a gale howling round it (a Q 9 whistle, 600 -> 1300 Hz), the rain thinner (900 drops a second), the city far below (to 600 Hz), 14 hover cars, one faint sign, no gutters and no club. Crossfades in from 50 % to 95 % of the course. |

## One-shots

| Clips | Synthesis |
|-------|-----------|
| `amb_gardens_bird_1..5` | Songbirds. Whistles are near-pure sines on smoothed log-frequency pitch contours; buzzy notes use fast FM. 1 is a chickadee-style "fee-bee" (two whistles, the second wavering); 2 is robin-style caroling (slurred 2-3 note groups); 3 is cardinal-style down-slurred "cheer"s that speed up, sometimes with up-slurs; 4 is warbler-style rising buzzy notes (FM at about 110 Hz) and a sharp up-slur; 5 is song-sparrow-style intro notes, an 18 Hz trill and a closing note. All get a light open-air reverb. |
| `amb_gardens_dove_1..2` | Soft cooing "coo-OO, oo, oo, oo" around 500 Hz with 2nd/3rd harmonics and a breathy edge. |
| `amb_gardens_bee_1..3` | A wing buzz (about 20 harmonics of 150-225 Hz with a wandering pitch and amplitude flutter) flown past the listener by a Doppler model: 1/r level, propagation delay and dulling with distance. |
| `amb_gardens_chimes_1..3` | Wind chimes: five pentatonic tubes (free-free bar partials 1 : 2.757 : 5.404 : 8.933, each a slightly detuned pair) struck 6-11 times in a gust-shaped cluster. |
| `amb_gardens_windmill_1..2` | A slow wooden creak (a stick-slip impulse train through 190-1500 Hz wood resonances, bending in pitch), a sail sweeping past (a band-passed noise swell) and gear knocks. |
| `amb_foundry_clank_1..3` | A distant struck beam: 7 inharmonic modes with an impact click, often a smaller second hit as it settles, in a large dark hall reverb. |
| `amb_foundry_steam_1..3` | A steam burst: bright hiss with pressure flutter and a low valve "fwump" at the onset, at a distance. |
| `amb_foundry_chain_1..3` | A chain rattle: link clinks (3-mode pings, 1.7-5.2 kHz; the 3rd variant is heavier and lower) at a density that surges and dies, over a drag noise. |
| `amb_foundry_hammer_1..2` | Far hammer strikes on an anvil (6 anvil modes plus a thud), 2-4 blows with a slap-back echo off the far wall. |
| `amb_foundry_blorp_1..3` | A lava blorp: a thick bubble swelling as its pitch climbs (85-130 Hz to twice that, wobbling), a soft pop, splatter drips and a brief sizzle. |
| `amb_balance_gull_1..4` | Gulls: a harmonic-rich voice gliding along a pitch contour, shaped by three formants. F2 glides from "kee" to "ow". Pitch jitter and a rough amplitude flutter give the rasp. 1 is a long call and a laughing series; 2 is two long calls; 3 is three "kyow"s with a second, distant gull; 4 is a two-note call. |
| `amb_balance_crane_1..2` | A crane winch: a brake-release clunk, an electric motor spooling up (harmonics, gear mesh and inverter whine), a load dip, spool-down and the brake. |
| `amb_balance_chain_1..3` | Heavy chain clanks (low, slow links). |
| `amb_balance_buoy_1..2` | A buoy bell rocked by the swell: bell partials (hum, prime, minor-third tierce, quint, nominal ... each a beating pair) struck 2-3 times, fading. |
| `amb_balance_foghorn_1..2` | A distant diaphone foghorn: about 95 Hz with a horn-mouth formant, and the characteristic "grunt" (a pitch drop) at the end. Heavily dulled, with echoes off the sea and a 3.4 s tail. |
| `amb_clockwork_bell_1..3` | Distant tower bell tolls: church-bell partials on G3 and D3, and a two-bell "ding ... dong", in a long stone reverb. |
| `amb_clockwork_ratchet_1..3` | A gear ratchet: pawl clicks (bright modes plus a tooth thunk, alternating in strength) whose rate speeds up and slows down, over a faint gear whirr. |
| `amb_clockwork_steam_1..2` | A short steam puff from the mechanism. |
| `amb_clockwork_cuckoo_1..2` | A cuckoo whistle: two pipe notes a major third apart (sine plus harmonics, a bellows pitch sag, breath noise and a chiff), repeated 2-3 times, with a door clack. |
| `amb_reef_bubbles_1..4` | A burst of 14-34 Minnaert bubbles (radius 1.2-6 mm, which sets a 540-2700 Hz pitch that rises as the bubble rises), under water. |
| `amb_reef_whale_1..3` | Whale song: slow gliding harmonic tones through a formant, through a 5 s dark reverb, far below. 1 is a rising moan; 2 is a low rough moan and a "whoop"; 3 is a descending cry with vibrato. |
| `amb_reef_shrimp_1..2` | A snapping-shrimp crackle: a Poisson burst of tiny broadband snaps, swelling and dying. |
| `amb_reef_timber_1..3` | The wreck's timber creaking under water: a slow, deep stick-slip creak; the 3rd variant ends with a knock. |
| `amb_orbital_radio_1..3` | Radio traffic. 1 is a 2525 Hz Quindar tone, chatter and a 2475 Hz Quindar tone, then a squelch; the chatter is a glottal harmonic stack with formants wandering between vowel targets, chopped into syllables. 2 is a two-tone chirp and chatter. 3 is an FSK telemetry burst. All are band-limited to 300-3400 Hz and lightly driven. |
| `amb_orbital_servo_1..3` | A servo: a motor spooling up, a load dip, a stop with a small overshoot and a lock click. |
| `amb_orbital_ping_1..3` | Thermal hull noises: 1 is a high plate "tink"; 2 is a low "tonk" with a ring; 3 is a metal groan (stick-slip through hull resonances) ending in a ping. |
| `amb_orbital_airlock_1..2` | A distant airlock cycle: a latch clunk, a pressure hiss whose band sweeps down as the pressure falls, and the seal thunk. |
| `amb_orbital_blip_1..3` | Data blips: 5-10 tiny beeps on a pentatonic set (G6-G7). |
| `amb_ascent_siren_1..2` | A distant siren (1 is a wail, 2 is a hi-lo two-tone) far below in the streets: dulled, with slap echoes off buildings, a long city reverb and a slow receding pitch drift. |
| `amb_ascent_crackle_1..3` | Electrical arcing: gated 120 Hz buzz bursts and sharp sparks. |
| `amb_ascent_heli_1..2` | A distant helicopter pass: rotor blade slaps at about 20 per second and a tail-rotor tone, flown past 170-240 m away by the Doppler model, so the slap rate and pitch drop as it passes. |
| `amb_ascent_drone_1..2` | A quadcopter fly-by: four slightly detuned rotor harmonic stacks that beat against each other, flown past by the Doppler model. |
| `amb_xeno_trill_1..4` | Alien birdsong that sounds organic but not Earth-like. 1 is a run of sliding whistles ring-modulated by a second tone (every note splits into two inharmonic sidebands), answered by a chitter; 2 is liquid notes on a 13-tone scale, each dropping like a drop and flipping up, with glassy FM (ratio 1.414); 3 is two voices trading fast (40-60 Hz) warbles, one gliding up while the other glides down; 4 is a bouncing-ball call (a glassy FM note, ratio 2.76, repeated faster and faster and falling). |
| `amb_xeno_creature_1..3` | Creature calls through moving formants. 1 is a rising "whee-oo" and a growled "ruk" (a subharmonic: period doubling); 2 is a clicking chatter through a mouth that opens (a formant sweeping 800 -> 2600 Hz) and a whistle; 3 is "hoo-hoo-hee" hoots from a throat sac, ring-modulated at 67 Hz. |
| `amb_xeno_chime_1..3` | Crystal prisms (partials 1 : 2.32 : 4.25 : 6.63, detuned pairs). 1 is a gust knocking through a cluster tuned to a 13-tone scale; 2 is one spire bowed by the wind, swelling up and singing, with a neighbour answering faintly; 3 is a shower of small shards tinkling down off a spire. |
| `amb_xeno_spore_1..3` | A spore pod bursting: a soft membrane pop, a breathy puff pushed out through the pod's mouth (a band sweeping 2.3-2.9 kHz -> 600 Hz) and a cloud of spores drifting off as a fine 5-11 kHz glitter. 3 is a cluster of three pods. |
| `amb_xeno_acid_1..3` | Acid bubbling up through a pool: 6-12 thick, slow bubbles (140-420 Hz, rising) bursting, some with a wet pop, over an effervescent fizz that swells and settles. |
| `amb_xeno_leviathan_1..2` | A leviathan miles off in the sky: a deep moan (a 50-82 Hz harmonic stack through slowly moving formants, a subharmonic growl and a faint 23 Hz ring-modulated sheen) with a higher gliding song over it, dulled at 1.6 kHz in a huge 3.6 s open reverb. |
| `amb_volcano_boom_1..3` | A distant eruption blast: a deep boom gliding down (55-75 Hz x 1.8 -> 0.6, with harmonics), a pressure wave of dark noise, a rolling, breathing rumble and ejecta crackle, echoing back off the slopes (0.5-0.9 s and 1.4-2.1 s). 3 is a double blast. |
| `amb_volcano_thunder_1..3` | Thunder from volcanic lightning in the ash cloud, modelled physically: the channel is a crooked chain of 400 segments, and each sends an N-wave that arrives after its own distance / 343 m/s. The further it travelled, the quieter and duller it is (six distance bands, each low-passed). Segments broadside to the listener arrive together (the crack), and the rest string out into the roll. 1 is near (450-600 m), 2 is far (1.2-1.5 km), 3 has a restrike down the same channel. |
| `amb_volcano_rockfall_1..3` | A slide of rocks down the slope: 26-44 impacts that swell and thin out, each a few low-Q stone modes, a band of body noise and a click (bigger rocks are lower and duller). Some bounce on, each hit sooner and softer, over the hiss of sliding gravel. |
| `amb_volcano_whistle_1..3` | A lava bomb passing far off: a tumbling rock tearing through the air (a narrow whistle band, a wider roar, a 7-12 Hz tumbling flutter and a fizzing trail), flown past at 70-95 m/s by the Doppler model, so the whistle drops as it goes by. 1 and 3 end in a distant thud. |
| `amb_volcano_steam_1..3` | A vent hissing: the steam model, darker and longer. 3 chuffs in pulses. |
| `amb_volcano_blorp_1..3` | A big, slow, viscous lava bubble: a 55-80 Hz tone gliding up as it swells (with a lazy wobble), a heavy pop and a falling 260 -> 90 Hz ring, gas hissing out and fat spatter falling back. |
| `amb_volcano_crack_1..3` | Cooling crust cracking: 6-12 brittle snaps (clicks exciting stony modes) running away, speeding up then dying out, over a low groan of the plate settling. In 3 a slab gives way: a crumble and a breath of steam. |
| `amb_glacier_crack_1..3` | Ice cracking. 1 is a sharp crack with its pew running away through the sheet and a groan; 2 is the ice singing (a run of 4-7 pews); 3 is a big, deep crack (a report, a 140 -> 45 Hz boom, a roll and pews). |
| `amb_glacier_avalanche_1..2` | An avalanche far off across the valley: a roar of tumbling snow that swells and dies away over 6 s, 20-40 blocks thudding inside it and the powder cloud's hiss, dulled at 1.5 kHz in a 3 s valley reverb. 2 starts with the crack of the slab letting go. |
| `amb_glacier_gust_1..3` | A gust howling round the walls: wind swelling and dying away, a howl riding it (a narrow resonance whose pitch rises with the gust, and its overtone at 1.52x) and snow hissing in it. |
| `amb_glacier_icicle_1..3` | Icicles knocking together in the wind: thin ice rods (free-bar partials 1 : 2.76 : 5.40, detuned pairs, shorter-lived than glass) struck in a small cluster. In 3 a small one snaps and tinkles down. |
| `amb_glacier_howl_1..2` | A wolf-like howl far down the pass: a smooth voice (eight harmonics through an "oo" formant) rising to a long held note that wavers and falls away. In 2, another answers. |
| `amb_glacier_snowslide_1..2` | A slab of snow sliding off a ledge: a soft "whumpf" as it lets go, a hissing slide that swells and settles, and lumps thudding down. |
| `amb_desert_hawk_1..3` | Raptors high over the dunes: a harmonic voice gliding down with a breathy rasp (fast roughness and noise that follows the pitch). 1 is a red-tail's long "keee-eeer"; 2 is two shorter screams; 3 is a kite's clean whistled "wee-ooo", repeated. |
| `amb_desert_sand_1..3` | Sand pouring from a crack in the temple: a dry granular hiss, a softer pouring body and the patter of it landing, starting, running and trickling out, in the hall. |
| `amb_desert_grind_1..2` | A stone block sliding somewhere in the temple: stick-slip through the block's dead resonances and a rough scrape, ending in a heavy clunk, in a 2.4 s hall. |
| `amb_desert_gong_1..2` | Far ceremony. 1 is a gong: eight inharmonic partials whose upper modes bloom a moment after the strike, the pitch gliding up a little as it rings; 2 is a big frame drum (membrane modes 1 : 1.59 : 2.14 : 2.30, the pitch dropping as the skin relaxes) in a slow five-beat pattern. Both are far off in a dark 2.8 s reverb. |
| `amb_desert_scarab_1..3` | Scarabs: bursts of fast stridulation (a rasp of tiny chitin clicks at 150-300 a second) and single clicks. In 3, one takes off with a short wing buzz. |
| `amb_desert_torch_1..2` | A torch on the wall: the flame's soft fluttering roar, snaps and small pops. |
| `amb_desert_pebbles_1..3` | Two to five pebbles falling and bouncing on stone (each bounce sooner and softer), with a trickle of sand. |
| `amb_manor_creak_1..3` | Old wood. 1 is a door swinging slowly open: the hinge groans (a stick-slip speeding up to 160 a second, through four resonances that bend up by a third); 2 is two or three floorboard creaks as someone unseen crosses the room; 3 is a door creaking shut and slamming (low wood modes, a thud, a crack and a rattle). |
| `amb_manor_whisper_1..3` | Whispers that say nothing: noise through two formants jumping between random vowel targets, chopped into syllables, with the odd hissed "s", in a 2 s reverb. 1 is one phrase; 2 is a phrase answered, duller, from elsewhere; 3 is a long breathy sigh falling away (a formant sweeping 750 -> 420 Hz) ending in a hiss. |
| `amb_manor_owl_1..3` | Owls. 1 is a tawny-style "hooo ... hu, hu-hoooo" (soft near-pure tones around 400-440 Hz that sag a little, the last one warbling); 2 is the sharp answering "ke-wick", twice; 3 is a barn owl's hoarse, hissing screech (1.8-6.5 kHz noise with a rough 55-75 Hz flutter and a gliding tonal core). |
| `amb_manor_toll_1..2` | The house clock tolling on a deep bell (church-bell partials on 131 or 117 Hz), three strokes about 2 s apart, far off in a 2.6 s reverb. In 1 the striking train whirrs and clunks as it gathers to strike. |
| `amb_manor_chains_1..3` | Heavy chains dragged in the crypt below (the chain model at a slow, then faster rate) in a dark 2.6 s stone reverb. In 3 they are dropped: a metal clank and a burst of links. |
| `amb_manor_shutter_1..3` | A gust through a broken window (a swelling body and a Q 12 whistle rising with it); in 1 a loose shutter bangs against its frame, in 2 twice, and in 3 a cracked pane rattles (14-30 small glass ticks). |
| `amb_armada_thunder_1..3` | Thunder in the storm clouds: the physical model (as Cinder Peak's), 1 near (400-550 m), 2 far (1.5-2 km), 3 with a restrike, in a 2.6 s reverb. |
| `amb_armada_cannon_1..3` | Far cannon fire: a sharp report, a boom gliding down to 38 Hz and a rolling rumble, echoing back off the cloud banks, dulled at 2.2 kHz. 1 is one shot; 2 is a ragged broadside of 4-6; 3 is a shot and another ship answering further off. |
| `amb_armada_bell_1..2` | A ship's bell across the water (bell partials on 620-720 Hz, short-lived): 1 is struck in pairs ("ding-ding, ding-ding"); 2 is rung fast, all hands. |
| `amb_armada_gull_1..3` | The Balance Works gulls, re-rolled (their own seeds). |
| `amb_armada_canvas_1..3` | A sail luffing and flogging (noise slapped 5-9 times a second, with cracks of cloth); 1 and 3 fill with a crack and a thump; in 3 loose lines slap about too. |
| `amb_armada_creak_1..3` | Timber working: 1 is the hull groaning in the swell (deep wood modes, 80-1000 Hz); 2 is a mast and its yards creaking two or three times; 3 is a rope creaking round a block, then the block knocking against the yard. |
| `amb_candy_pop_1..3` | A soda spring bubbling over: 6-15 fizzy pops (tiny "bloops" rising 350-1200 Hz to 2.6x in 30 ms, each with a click) over an effervescent hiss that settles. In 3 a cork comes out first with a hollow "thwop" (a tube resonance). |
| `amb_candy_chime_1..3` | Sparkly chimes on glockenspiel bars (1 : 2.756 : 5.404) up C major pentatonic from C6, in a light reverb: 1 is a glissando up; 2 is a twinkle down and back up; 3 is a random shower. |
| `amb_candy_windup_1..3` | A wind-up toy: the key wound (ratchet clicks, turn by turn), then let go: the clockwork buzzes (a 38-48 Hz gear rate that slows) and plastic feet clack as it waddles off, running down. 2 is only the waddle; 3 ends with a little bell. |
| `amb_candy_squeak_1..3` | Squeaky bounces. 1 is a rubber toy squeezed twice (a nasal tone bending up a third as the air is forced out); 2 is a ball bouncing on jelly (bouncy "boings" that drop onto their pitch and wobble, each sooner and softer); 3 is a squeak and a boing. |
| `amb_candy_carousel_1..2` | A carousel's band organ far across the candy fields: a six-bar waltz phrase (about 6 s) in C major (bass on the beat, chords on two and three, the melody over; flute-ish pipes with a tremulant), swelling and fading as the organ turns, dulled at 2.5 kHz in a 2 s reverb. Two different phrases. |
| `amb_candy_gumball_1..2` | A gumball rolling down a spiral chute (plastic clacks on the rails coming faster and brighter over a hollow roll) and dropping into the tray with two small bounces; in 2 the crank turns first. |
| `amb_carrier_jet_1..3` | Jets on the deck (a compressor whine with a lower spool over a broadband roar). 1 spools up at the catapult (whine 1.4 -> 4.2 kHz, the roar building and brightening); 2 is launched off the bow, the afterburner roar with its crackle passing by the Doppler model at 70 m/s and going away; 3 spools down after a landing. |
| `amb_carrier_catapult_1..3` | The steam catapult. 1 and 2 are the stroke: steam blasting as the valves open, the shuttle racing down the track (a rush rising 300 -> 2500 Hz) and slamming into the water brake (a 90 -> 35 Hz thud, a burst of low noise and a steel ring); in 2 the steam cloud billows on after it. 3 is the shuttle being run back: a grumbling rumble along the track, a hiss and a latch clunk. |
| `amb_carrier_announce_1..3` | Deck announcements as a far-off public-address horn renders them: **no words**, only tone bursts of one fixed, buzzy timbre (no formants moving, so nothing vowel-like) that follow a speaking contour: pitch and level rising and falling in phrases of syllable-length bursts, band-limited to a horn (450-2800 Hz, a 1.1 kHz resonance), lightly driven, with slap echoes off the island and hull. 1 opens with a two-tone chime; 2 is a radio call with a squelch in and out; 3 opens with a bosun's-call whistle swelling up and trilling. |
| `amb_carrier_heli_1..2` | A helicopter passing along the deck 60-110 m away: rotor slaps about 18 a second, the tail rotor's tone and a faint turbine whine, flown past by the Doppler model (the two go opposite ways). |
| `amb_carrier_gull_1..3` | The Balance Works gulls, re-rolled (variants 1, 3 and 4 of theirs). |
| `amb_sakura_bell_1..2` | A temple bell far across the valley (a bonsho: seven partials 1 : 1.62 : 2.07 : 2.73 : 3.42 : 4.25 : 5.1, each a slowly beating pair, ringing 9 s), struck with a wooden beam (a soft thud, no metallic click). 1 is on D3 and struck again as the hum fades; 2 is on A2. |
| `amb_sakura_shishi_1..3` | A shishi-odoshi: water trickling into the bamboo arm (a babble and small bubbles), a gush as it tips, and the hollow "tock" of the bamboo on its stone, echoing off the far side of the valley. 2 comes in as it tips; in 3 it rocks back for a second, softer knock. |
| `amb_sakura_chime_1..3` | Wind chimes: metal tubes (free-bar partials) on D minor pentatonic from D5. 1 is a few lazy strikes; 2 a gust that sets them all going; 3 a glass wind bell (its clapper tinkling 3-6 times, D6 upwards) with its paper strip fluttering. |
| `amb_sakura_cicada_1..3` | Evening cicadas: a ringing "kana-kana-kana", 9-12 notes a second around 4.2-5.2 kHz, each buzzing (180-240 Hz) and sagging a little, the run slowing and sinking as it dies away. In 3 another answers further off. They fade out as the course climbs (chance 100 % -> 20 %). |
| `amb_sakura_bamboo_1..3` | A gust through the bamboo grove: leaves rushing and culms knocking (6-14 hollow clacks from three culms, following the gust). In 2 a tall culm creaks as it bends; 3 is mostly knocks as the wind drops. |
| `amb_sakura_bird_1..2` | 1 is a bush warbler: a long rising whistle and a quick, bright "ho-ke-kyo". 2 is a crow heading home at dusk: three hoarse "kaa"s (the hawk model, rough and low). |
| `amb_sakura_koi_1..2` | A koi at the pond's surface: 1 a gulp (a low 250-380 Hz plop), 2 a tail slap; then 6-14 drips and ripples. |
| `amb_jungle_bird_1..3` | Rainforest birds, in A minor: 1 a bellbird's loud "bonk"s (a clangorous note on A5 or E5, two to four times); 2 an oropendola's liquid gurgles ending in a falling "glooop"; 3 a tinamou's tremulous whistles stepping down A5, G5, E5, D5. |
| `amb_jungle_parrot_1..3` | Parrots (a harsh, rough harmonic voice with a jittering pitch through a bright band, plus a noisy edge): 1 two or three squawks; 2 a flock flying over, squawking, louder as they pass; 3 a macaw's long, raucous "raaa-aah", twice. |
| `amb_jungle_toucan_1..3` | Toucans croaking "kree-ok" (a buzzy 110-150 Hz pulse train through two formants that rise and fall). 2 is answered by a second, duller bird; 3 starts with a bill clatter (fast wooden taps). |
| `amb_jungle_howler_1..2` | Apes whooping far off through the canopy, **gibbon-like and cheerful, not menacing**: a run of rising "hoo" notes that climb and quicken into a whoop. In 2 a second, higher voice joins in. Dulled at 2.6 kHz in a 2.4 s reverb. |
| `amb_jungle_drip_1..3` | 1 is a shower shaken off the canopy (30-55 drops on broad leaves and in a puddle, thinning out); 2 a few big, slow drops into a pool; 3 a branch shaking: a rustle and a burst of drops. |
| `amb_jungle_insect_1..2` | 1 is a cicada winding up: its buzz swells and climbs (3.2-4.8 kHz), holds and sputters out. 2 is katydids: bursts of quick rasping ticks, one answering another. |
| `amb_jungle_thunder_1..2` | Thunder over the hills (the physical model, 2.5-3.5 km away; 2 with a restrike), in a 3 s reverb. |
| `amb_frontier_whistle_1..2` | The engine's chime whistle (three pipes on a G major chord, G4 B4 D5, each a breathy harmonic tone that sags as the valve opens) echoing off the canyon walls: 1 a long blow and a short one; 2 the crossing call (long, long, short, long). |
| `amb_frontier_hawk_1..3` | The Scarab Sands hawks, re-rolled (their own seeds). |
| `amb_frontier_creak_1..3` | 1 is the car body working (two or three timber creaks); 2 slack running in along the train (coupler after coupler clanking, each further off); 3 a boxcar door rattling in its track. |
| `amb_frontier_steam_1..2` | 1 is the cylinder cocks blowing down (4-7 sharp bursts of steam in time with the drivers); 2 the safety valve lifting (a long, fluttering roar of steam). |
| `amb_frontier_bell_1..2` | The locomotive's bell on G (bell partials on G4, the minor tierce held down): 1 rung steadily for a crossing; 2 three strokes, the rope let go. |
| `amb_frontier_coyote_1..2` | Coyotes far across the canyon: 1 a few yips and a long howl (rising, wavering, falling); 2 a pack, howls overlapping and yips among them. |
| `amb_frontier_squeal_1..2` | Wheel flanges squealing round a curve: a thin screech hopping between three wheel modes (1.8-4.2 kHz), swelling and dying away. The runtime keeps it quiet. |
| `amb_neon_hover_1..3` | Hover cars on the traffic lanes (an electric turbine hum and whine over a rush of air, through the Doppler model): 1 one passing; 2 a fast one (85-110 m/s); 3 three in a stream. |
| `amb_neon_siren_1..2` | A siren far down in the streets, **softened** by distance and the rain (dulled at 1.3 kHz, a 3 s reverb, slap echoes, fading in and out): 1 a slow two-tone, B4 / E5; 2 a lazy wail rising and falling. |
| `amb_neon_drone_1..2` | A delivery drone passing overhead: four small rotors (230-270 Hz) a little apart, flown past by the Doppler model; in 2 it chirps a two-note status beep (B5, E6) as it goes over. |
| `amb_neon_spark_1..3` | Neon in the rain: 1 a tube sputtering (bursts of 120 Hz buzz and crackle); 2 a transformer arcing (a sharp crack and a sizzle dying away over a hum surge); 3 a sign flickering on (relay ticks, failed sputters, then the buzz catches). |
| `amb_neon_gutter_1..3` | 1 is a gutter overflowing onto a metal awning (a pouring stream and 60-100 drops pinging the tin); 2 a storm drain gurgling (low glugs over a rush); 3 drips on a tin can, slowing. |
| `amb_neon_horn_1..2` | A hover car's horn down the street (a soft, synthy E4 + G4 chord through a horn resonance), echoing between the towers: 1 a quick double tap; 2 one long blare and a short one. |
| `amb_neon_thunder_1..2` | Thunder above the city (1.8-3 km; 2 with a restrike). |

## Scheduling tables (`Soundscape.THEMES`)

`every` is seconds between plays; `dB` is the level at the spawn point; `dist` is the horizontal
distance (m); `height` is relative to the listener (m). The first play of each event comes 2 s
after load plus a random part of its interval.

**Launch Gardens** (bed `amb_gardens`)

| Event | every | dB | pitch +- | dist | height | extra |
|-------|-------|----|----------|------|--------|-------|
| bird | 3-9 | -16 to -8 | 0.05 | 10-35 | 2-14 | answer 35 % |
| dove | 18-40 | -18 to -12 | 0.03 | 15-40 | 0-8 | |
| bee | 22-50 | -20 to -13 | 0.08 | 2-5 | -0.5 to 1.5 | travel 6 m |
| chimes | 25-60 | -20 to -14 | 0 | 8-20 | 0-5 | |
| windmill | 30-70 | -20 to -14 | 0.06 | 25-50 | 5-20 | |

**Title** (bed `amb_title`): the garden birds every 6-14 s (-20 to -12 dB, answer 30 %) and the
dove every 25-50 s (-22 to -15 dB).

**Bounce Foundry** (bed `amb_foundry`)

| Event | every | dB | pitch +- | dist | height |
|-------|-------|----|----------|------|--------|
| blorp | 5-14 | -18 to -11 | 0.12 | 8-25 | -25 to -5 (the slag below) |
| clank | 6-16 | -18 to -10 | 0.1 | 20-50 | -15 to 15 |
| steam | 10-25 | -20 to -13 | 0.1 | 12-35 | -10 to 10 |
| chain | 14-32 | -20 to -13 | 0.08 | 12-35 | 0-15 |
| hammer | 20-45 | -18 to -12 | 0.05 | 35-70 | -10 to 10 |

**Balance Works** (bed `amb_balance`)

| Event | every | dB | pitch +- | dist | height | extra |
|-------|-------|----|----------|------|--------|-------|
| gull | 6-16 | -16 to -9 | 0.07 | 15-40 | 8-25 (overhead) | travel 12 m, answer 30 % |
| chain | 12-30 | -20 to -13 | 0.08 | 15-40 | -5 to 10 | |
| crane | 18-40 | -20 to -13 | 0.08 | 25-60 | -5 to 15 | |
| buoy | 20-45 | -20 to -14 | 0.03 | 50-90 | -45 to -25 (the sea) | |
| foghorn | 70-150 | -18 to -12 | 0.03 | 120-200 | -40 to -20 | |

**Clockwork Heights** (bed `amb_clockwork`)

| Event | every | dB | pitch +- | dist | height |
|-------|-------|----|----------|------|--------|
| ratchet | 8-20 | -20 to -13 | 0.1 | 8-25 | -5 to 10 |
| steam | 12-28 | -20 to -14 | 0.1 | 10-30 | -10 to 10 |
| bell | 30-70 | -16 to -10 | 0 | 40-80 | 10-40 (the belfry) |
| cuckoo | 60-140 | -17 to -12 | 0.02 | 20-45 | 0-15 |

**Coral Depths** (bed `amb_reef`, layer `amb_reef_deep` from 0.25 to 0.85)

| Event | every | dB | pitch +- | dist | height | chance start -> end |
|-------|-------|----|----------|------|--------|---------------------|
| bubbles | 4-10 | -18 to -10 | 0.12 | 5-20 | -8 to 4 | 100 % -> 45 % |
| shrimp | 10-25 | -22 to -15 | 0.1 | 6-20 | -6 to 0 | 100 % -> 30 % |
| timber | 15-35 | -18 to -12 | 0.08 | 15-40 | -10 to 5 | 70 % |
| whale | 35-80 | -18 to -11 | 0.06 | 60-120 | -60 to -25 (far below) | 35 % -> 100 % |

**Orbital Drift** (bed `amb_orbital`)

| Event | every | dB | pitch +- | dist | height |
|-------|-------|----|----------|------|--------|
| blip | 7-18 | -22 to -15 | 0.04 | 4-15 | -2 to 4 |
| servo | 8-20 | -20 to -13 | 0.1 | 8-25 | -5 to 10 |
| ping | 10-26 | -20 to -13 | 0.08 | 8-30 | -10 to 10 |
| radio | 14-35 | -20 to -13 | 0 | 6-20 | -3 to 5 |
| airlock | 40-90 | -18 to -12 | 0.05 | 20-45 | -10 to 10 |

**Xeno Wilds** (bed `amb_xeno`, layer `amb_xeno_deep` from 0.35 to 0.9)

| Event | every | dB | pitch +- | dist | height | extra |
|-------|-------|----|----------|------|--------|-------|
| trill | 4-10 | -16 to -9 | 0.06 | 10-35 | 2-16 | answer 40 % |
| acid | 8-20 | -20 to -13 | 0.12 | 8-25 | -20 to -4 (the pools below) | |
| spore | 10-24 | -22 to -15 | 0.1 | 4-14 | -2 to 3 | |
| creature | 12-28 | -18 to -11 | 0.08 | 12-40 | -4 to 10 | answer 25 % |
| chime | 14-32 | -20 to -13 | 0 | 8-25 | -2 to 8 | |
| leviathan | 60-140 | -16 to -10 | 0.04 | 120-220 | 20-80 (the sky) | travel 60 m, chance 40 % -> 100 % |

**Cinder Peak** (bed `amb_volcano`, layer `amb_volcano_crater` from 0.3 to 0.95)

| Event | every | dB | pitch +- | dist | height | extra |
|-------|-------|----|----------|------|--------|-------|
| blorp | 5-13 | -18 to -11 | 0.12 | 8-25 | -20 to -3 (the lava below) | |
| steam | 9-22 | -20 to -13 | 0.1 | 10-30 | -8 to 6 | |
| crack | 12-28 | -20 to -13 | 0.1 | 6-20 | -4 to 2 | |
| whistle | 16-36 | -18 to -12 | 0.06 | 40-90 | 20-60 | travel 40 m, chance 60 % -> 100 % |
| rockfall | 18-40 | -18 to -12 | 0.08 | 30-70 | -10 to 30 | |
| thunder | 20-45 | -16 to -10 | 0.05 | 150-300 | 80-200 (the ash cloud) | chance 60 % -> 100 % |
| boom | 25-55 | -16 to -10 | 0.04 | 200-400 | 50-150 | chance 50 % -> 100 % |

**Frostbite Pass** (bed `amb_glacier`, layer `amb_glacier_storm` from 0.25 to 0.9)

| Event | every | dB | pitch +- | dist | height | extra |
|-------|-------|----|----------|------|--------|-------|
| gust | 6-14 | -18 to -11 | 0.08 | 10-30 | 0-15 | travel 20 m |
| icicle | 9-20 | -22 to -15 | 0.05 | 5-15 | 2-8 | |
| crack | 10-24 | -18 to -11 | 0.08 | 20-60 | -20 to 0 | |
| snowslide | 18-40 | -20 to -13 | 0.08 | 15-40 | 0-20 | |
| howl | 40-90 | -18 to -12 | 0.05 | 100-200 | -10 to 40 | answer 40 %, chance 80 % -> 30 % (the blizzard drowns them) |
| avalanche | 50-110 | -16 to -10 | 0.05 | 200-400 | 50-200 | chance 50 % -> 100 % |

**Scarab Sands** (bed `amb_desert`, layer `amb_desert_storm` from 0.3 to 0.95)

| Event | every | dB | pitch +- | dist | height | extra |
|-------|-------|----|----------|------|--------|-------|
| sand | 6-14 | -20 to -13 | 0.1 | 6-20 | -2 to 8 | |
| scarab | 7-16 | -22 to -15 | 0.1 | 2-8 | -1 to 1 | |
| torch | 10-22 | -22 to -16 | 0.08 | 3-10 | 1-4 | |
| pebbles | 12-26 | -20 to -14 | 0.1 | 6-20 | 2-12 | |
| hawk | 14-32 | -16 to -10 | 0.05 | 40-90 | 25-70 | travel 25 m, answer 20 %, chance 100 % -> 30 % (the storm drives them off) |
| grind | 25-55 | -18 to -12 | 0.06 | 15-40 | -5 to 10 | |
| gong | 45-100 | -18 to -12 | 0.02 | 60-120 | -10 to 20 | |

**Phantom Manor** (bed `amb_manor`, layer `amb_manor_tower` from 0.4 to 0.95)

| Event | every | dB | pitch +- | dist | height | extra |
|-------|-------|----|----------|------|--------|-------|
| creak | 8-20 | -20 to -13 | 0.08 | 6-20 | -4 to 8 | |
| shutter | 12-28 | -20 to -13 | 0.06 | 10-30 | 0-15 | |
| owl | 14-32 | -18 to -11 | 0.04 | 25-60 | 5-20 | answer 30 %, chance 100 % -> 50 % (fewer up the tower) |
| whisper | 16-36 | -24 to -17 | 0.05 | 2-6 | 0-2 | travel 4 m |
| chains | 20-45 | -20 to -14 | 0.06 | 10-30 | -15 to 0 (the crypt below) | |
| toll | 50-110 | -16 to -10 | 0 | 40-90 | 20-50 | chance 50 % -> 100 % |

**Storm Armada** (bed `amb_armada`, layer `amb_armada_flagship` from 0.5 to 0.95)

| Event | every | dB | pitch +- | dist | height | extra |
|-------|-------|----|----------|------|--------|-------|
| canvas | 6-14 | -20 to -13 | 0.1 | 8-25 | 2-15 | |
| creak | 7-16 | -20 to -13 | 0.08 | 5-20 | -5 to 8 | |
| thunder | 15-35 | -16 to -10 | 0.05 | 150-300 | 80-200 | chance 100 % -> 40 % (the storm breaks) |
| cannon | 18-40 | -16 to -10 | 0.05 | 150-300 | -30 to 30 | chance 80 % -> 50 % |
| gull | 12-30 | -18 to -11 | 0.07 | 20-50 | 5-25 | travel 12 m, answer 30 %, chance 20 % -> 100 % |
| bell | 30-70 | -18 to -12 | 0.02 | 40-90 | -10 to 20 | |

**Sugar Rush** (bed `amb_candy`, layer `amb_candy_high` from 0.3 to 0.95)

| Event | every | dB | pitch +- | dist | height | extra |
|-------|-------|----|----------|------|--------|-------|
| pop | 5-12 | -22 to -15 | 0.1 | 4-14 | -3 to 2 | |
| chime | 8-18 | -20 to -13 | 0 (in tune) | 6-20 | 2-12 | |
| squeak | 10-24 | -20 to -13 | 0.08 | 6-20 | -2 to 6 | answer 25 % |
| windup | 16-36 | -20 to -14 | 0.05 | 4-12 | -1 to 3 | travel 3 m |
| gumball | 20-45 | -20 to -14 | 0.06 | 8-25 | 0-10 | |
| carousel | 50-110 | -18 to -12 | 0 (in tune) | 60-120 | -10 to 15 | chance 100 % -> 50 % |

**Super Carrier** (bed `amb_carrier`, layer `amb_carrier_island` from 0.5 to 0.95)

| Event | every | dB | pitch +- | dist | height | extra |
|-------|-------|----|----------|------|--------|-------|
| gull | 8-20 | -18 to -11 | 0.07 | 15-45 | 5-25 | travel 12 m, answer 30 % |
| announce | 18-40 | -18 to -12 | 0 | 20-60 | 0-25 | |
| jet | 20-45 | -16 to -10 | 0.05 | 60-150 | -10 to 30 | travel 40 m |
| catapult | 25-55 | -16 to -10 | 0.05 | 60-150 | -5 to 5 | chance 100 % -> 60 % |
| heli | 45-100 | -16 to -11 | 0.03 | 90-180 | 10-60 | travel 90 m |

**Sakura Peaks** (bed `amb_sakura`, layer `amb_sakura_keep` from 0.5 to 0.95)

| Event | every | dB | pitch +- | dist | height | extra |
|-------|-------|----|----------|------|--------|-------|
| bamboo | 7-16 | -20 to -13 | 0.08 | 6-20 | 0-8 | |
| chime | 8-18 | -20 to -13 | 0 (in tune) | 4-12 | 2-6 | |
| cicada | 9-20 | -20 to -13 | 0.04 | 10-30 | 3-12 | answer 30 %, chance 100 % -> 20 % (dusk falls) |
| shishi | 14-30 | -18 to -12 | 0.03 | 10-25 | -6 to 2 | chance 100 % -> 30 % |
| koi | 18-40 | -22 to -15 | 0.06 | 6-18 | -8 to 0 | chance 100 % -> 20 % |
| bird | 20-45 | -18 to -12 | 0.04 | 20-50 | 5-20 | answer 25 % |
| bell | 45-100 | -16 to -10 | 0 (in tune) | 80-160 | -20 to 30 | chance 60 % -> 100 % |

**Jungle Temple** (bed `amb_jungle`, layer `amb_jungle_top` from 0.5 to 0.95)

| Event | every | dB | pitch +- | dist | height | extra |
|-------|-------|----|----------|------|--------|-------|
| bird | 6-14 | -18 to -10 | 0 (in tune) | 15-40 | 4-20 | answer 35 % |
| drip | 8-18 | -22 to -15 | 0.08 | 2-8 | 1-6 | chance 100 % -> 40 % |
| parrot | 10-24 | -18 to -11 | 0.06 | 15-45 | 8-25 | travel 15 m |
| toucan | 12-28 | -18 to -11 | 0.05 | 15-40 | 6-20 | answer 30 % |
| insect | 15-35 | -20 to -13 | 0.05 | 8-25 | 2-12 | chance 100 % -> 50 % |
| howler | 35-80 | -16 to -10 | 0.04 | 60-150 | 0-30 | answer 40 %, chance 100 % -> 70 % |
| thunder | 40-90 | -16 to -10 | 0.05 | 200-400 | 100-300 | |

**Wild West Heist** (bed `amb_frontier`, layer `amb_frontier_loco` from 0.5 to 0.95)

| Event | every | dB | pitch +- | dist | height | extra |
|-------|-------|----|----------|------|--------|-------|
| creak | 6-14 | -20 to -13 | 0.08 | 4-14 | -3 to 2 | |
| steam | 12-28 | -20 to -13 | 0.06 | 20-60 | -2 to 4 | chance 60 % -> 100 % |
| hawk | 14-32 | -18 to -11 | 0.05 | 40-90 | 20-50 | answer 20 % |
| squeal | 25-55 | -22 to -16 | 0.04 | 20-50 | -4 to 0 | |
| whistle | 30-70 | -16 to -10 | 0 (in tune) | 60-140 | 0-10 | |
| bell | 30-65 | -18 to -12 | 0 (in tune) | 40-100 | 0-6 | chance 30 % -> 100 % |
| coyote | 45-100 | -18 to -12 | 0.04 | 120-250 | 10-60 | answer 30 %, chance 100 % -> 50 % |

**Neon City** (bed `amb_neon`, layer `amb_neon_spire` from 0.5 to 0.95)

| Event | every | dB | pitch +- | dist | height | extra |
|-------|-------|----|----------|------|--------|-------|
| gutter | 7-16 | -22 to -15 | 0.08 | 3-10 | -3 to 3 | chance 100 % -> 30 % |
| hover | 8-20 | -16 to -10 | 0.06 | 20-60 | -10 to 20 | travel 50 m, chance 100 % -> 60 % |
| spark | 10-24 | -22 to -14 | 0.1 | 4-14 | -2 to 6 | |
| drone | 25-55 | -18 to -12 | 0.06 | 10-25 | 3-15 | travel 40 m |
| horn | 30-70 | -20 to -14 | 0 (in tune) | 60-150 | -40 to 10 | chance 100 % -> 40 % |
| thunder | 40-90 | -16 to -10 | 0.05 | 200-400 | 100-300 | |
| siren | 50-110 | -20 to -14 | 0.03 | 150-300 | -120 to -30 (the streets) | chance 100 % -> 50 % |

**The Final Ascent** (bed `amb_ascent`, layer `amb_ascent_high` from 0.3 to 0.95)

| Event | every | dB | pitch +- | dist | height | extra |
|-------|-------|----|----------|------|--------|-------|
| crackle | 9-22 | -22 to -14 | 0.1 | 5-18 | -4 to 6 | |
| drone | 30-70 | -18 to -12 | 0.06 | 10-25 | 2-12 | travel 45 m |
| siren | 50-110 | -18 to -12 | 0.04 | 150-300 | -160 to -90 (the city) | chance 100 % -> 50 % |
| heli | 70-150 | -16 to -11 | 0.03 | 120-220 | -60 to 20 | travel 120 m |

## Tests

`test_zs_soundscapes` (tests/run_tests.gd) first checks that every map in `Game.LEVELS` has a
soundscape, then builds every theme's soundscape headless and checks three things. First, each
bed and layer loads as a looping Ogg of 45 s or more and plays on the Ambience bus with
`PROCESS_MODE_ALWAYS`. Second, every event has clips and plays in 3D on the Ambience bus. Third,
every layer (reef, xeno, volcano, glacier, desert, manor, armada, candy, carrier, sakura, jungle,
frontier, neon, ascent) has
taken over at the end of the course. In the real Coral Depths level, reaching the last checkpoint
starts easing the deep bed in.
