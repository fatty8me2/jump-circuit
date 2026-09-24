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

* Needs Python 3, numpy and soundfile. Generating everything takes about 4 minutes.
* Deterministic: every clip has its own RNG (`SEED` + CRC of its name). libsndfile gives each
  Ogg stream a random serial number, so the generator pins the serial and rewrites the page
  CRCs, which makes re-runs bit-identical.
* Afterwards run `tools/Godot_v4.7.1-stable_win64.exe --headless --path . --import` once.

`--verify` checks every file. For **beds**: Ogg, 32 kHz, stereo, 45-90 s, RMS within 1 dB of the
target, peak under -3 dBFS, and less than 35 % of the energy below 80 Hz. It also checks the
loop seam on the *decoded* file: the sample step and the curvature across the wrap must be no
larger than ordinary ones inside the file, and the level of the last 50 ms must match the first
50 ms. For **one-shots**: 44.1 kHz mono, 0.2-10 s, peak about -3 dBFS, silent first and last
samples. It fails on missing or stray `amb_*` files and when the total goes over 18 MB.

## Formats and levels

| Group     | Files                            | Format                         | Level |
|-----------|----------------------------------|--------------------------------|-------|
| Beds      | `amb_<theme>.ogg` (+ layers)     | Ogg Vorbis, 32 kHz stereo      | -24 to -27 dBFS RMS (title -30; the glacier and desert storm layers are 1 dB above their base beds); a memoryless soft knee holds peaks under -4 dBFS; 40 Hz high-pass, 6-9 kHz low-pass |
| One-shots | `amb_<theme>_<event>_<n>.ogg`    | Ogg Vorbis, 44.1 kHz mono      | peak normalised to -3 dBFS; the runtime plays them 8-22 dB down |

One-shots are Ogg rather than WAV to keep within the size budget: the 159 clips add up to about
540 s, which would be about 48 MB as 44.1 kHz 16-bit WAV, against 4.2 MB as Ogg. Nothing is
timing-critical, so Ogg's decode latency doesn't matter. Total size: about 16.8 MB (18 beds 12.6 MB,
159 one-shots 4.2 MB).

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
  Pass (`amb_glacier_storm`) and the sandstorm reaches Scarab Sands (`amb_desert_storm`). Near
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

**The Final Ascent** (bed `amb_ascent`, layer `amb_ascent_high` from 0.3 to 0.95)

| Event | every | dB | pitch +- | dist | height | extra |
|-------|-------|----|----------|------|--------|-------|
| crackle | 9-22 | -22 to -14 | 0.1 | 5-18 | -4 to 6 | |
| drone | 30-70 | -18 to -12 | 0.06 | 10-25 | 2-12 | travel 45 m |
| siren | 50-110 | -18 to -12 | 0.04 | 150-300 | -160 to -90 (the city) | chance 100 % -> 50 % |
| heli | 70-150 | -16 to -11 | 0.03 | 120-220 | -60 to 20 | travel 120 m |

## Tests

`test_zs_soundscapes` (tests/run_tests.gd) builds every theme's soundscape headless and checks
three things. First, each bed and layer loads as a looping Ogg of 45 s or more and plays on
the Ambience bus with `PROCESS_MODE_ALWAYS`. Second, every event has clips and plays in 3D on
the Ambience bus. Third, every layer (reef, xeno, volcano, glacier, desert, ascent) has taken
over at the end of the course. In the real Coral Depths level, reaching the last checkpoint
starts easing the deep bed in.
