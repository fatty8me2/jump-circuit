# Jump Circuit - Audio

**All audio in this project is original.** Every sound effect and every piece of
music is synthesised from maths and seeded pseudo-random noise by the generators
in `tools/` (and `party/`). No samples, loops, sound fonts or other third-party assets
are used, so no third-party licences or attributions are needed. The generated
files are released with the project under the project's own terms.

## Where everything lives

| What | Generator | Doc |
|------|-----------|-----|
| Core effects (jump, land, bounce, checkpoint / finish fallbacks, UI ...) | `tools/gen_audio.py` | this file |
| The score: map music, menus, fanfares, checkpoint chimes | `tools/gen_music.py` + `tools/music_engine.py` | [Music](#music) below |
| Map soundscapes: ambience beds + scheduled one-shots (`sound/soundscape.gd`) | `tools/gen_ambience.py` | [AUDIO_AMBIENCE.md](AUDIO_AMBIENCE.md) |
| Machine, mechanic, footstep and movement sounds (`mechanics/world_audio.gd`, `player/player_audio.gd`) | `tools/gen_world_sfx.py` | [AUDIO_WORLD.md](AUDIO_WORLD.md) |
| Party Mode effects | `party/gen_party_audio.py` | [PARTY_BRIEF.md](PARTY_BRIEF.md) |

The music and ambience generators need `soundfile` (`pip install soundfile`) as well as numpy.

## Regenerating

```
python tools/gen_audio.py            # generate everything into audio/, then verify
python tools/gen_audio.py --sfx      # effects only
python tools/gen_audio.py --music    # music only
python tools/gen_audio.py --verify   # only check the files on disk
```

* Requires Python 3 and numpy.
* Deterministic: each sound has its own RNG seeded from a fixed `SEED` plus the
  CRC of its name, so re-running produces bit-identical files.
* Generation takes roughly 25 s (the music reverbs are large FFTs).
* After regenerating, run
  `tools/Godot_v4.7.1-stable_win64.exe --headless --path . --import`.
  The existing `.import` files (including the loop settings) are kept.

The built-in verifier checks, for every file: duration, 16-bit format, no
NaN/Inf, peak level, near-zero first/last sample for effects, and for music the
RMS level and loop-point continuity (the sample step and the curvature across
the wrap-around must be no larger than ordinary steps inside the file). It also
checks the total size budget (currently about 14 MB of the 25 MB allowed).

## Formats and levels

| Group   | Format                        | Level                                      |
|---------|-------------------------------|--------------------------------------------|
| Effects | 44.1 kHz, mono, 16-bit PCM    | peak normalised to -3 dBFS, 2 ms fade in, 8+ ms fade out, DC removed |
| Music   | 32 kHz, stereo, Ogg Vorbis (~96 kbps) | K-weighted loudness: full map score about -14.5 dB (base layer alone about -16.5), menus -15.5, results -17; circular look-ahead limiter, peaks under -1 dBFS |

Music is stored at 22.05 kHz because it is deliberately soft and dark (it sits
under the effects) and this keeps stereo loops inside the size budget.

## Building blocks

* **Oscillators** - sines only, driven by per-sample frequency arrays (phase
  accumulation) so pitch glides are click-free. Richer tones are small sums of
  harmonics / detuned sines; there are no raw square or saw waves.
* **Envelopes** - linear attack + exponential decay, or raised-cosine
  attack/release for pads.
* **Noise** - seeded Gaussian noise shaped by a zero-phase Butterworth-shaped
  FFT filter (`fft_band`) or, for moving filters, a Chamberlin state-variable
  band-pass (`svf_bandpass`).
* **Grains** - very short band-passed noise bursts used for gravel/debris.

## Sound effects (names are fixed by `autoload/sfx.gd`)

| File | Length | Synthesis |
|------|--------|-----------|
| `jump.wav` | 0.18 s | Sine blip gliding 380 -> 900 Hz with a touch of 2nd harmonic, 4 ms attack / 60 ms decay, layered over a soft 150 -> 65 Hz sine thump. |
| `land.wav` | 0.20 s | 125 -> 52 Hz sine thud with 2nd/3rd harmonics (so it is audible on small speakers) plus a 30 ms puff of 120-950 Hz noise. |
| `step.wav` | 0.07 s | Footstep tick: an 8 ms click of 1.4-6 kHz band-passed noise over a short 210 -> 120 Hz sine tap (well above the land thud). Played quietly and pitch-varied at each foot plant while you are walking or running; faster steps are a little louder, and on ice the pitch goes up. |
| `whack.wav` | 0.30 s | Hammer hit: a 180 -> 60 Hz sine drop with its octave, an 18 ms crack of 900-4500 Hz band-passed noise and a quiet metallic ring (523 + 1307 Hz, inharmonic) that dies in about 60 ms. |
| `bounce.wav` | 0.45 s | The "boing": pitch starts high, drops within about 20 ms, then rises, with a damped 11.5 Hz spring wobble on the pitch. Fast-decaying 2nd and 3rd harmonics and a 4 ms high-passed noise click give the bright attack; a short sine thump adds weight. |
| `checkpoint.wav` | 0.70 s | Two bell notes (E5 then B5, 150 ms apart) built from slightly inharmonic partials (1, 2, 3.01, 4.2). Shimmer is a detuned octave-up sine pair with 17 Hz tremolo plus a faint twelfth. |
| `crumble.wav` | 0.70 s | About 70 random band-passed noise grains (gravel) over a 140-520 Hz noise bed chopped by a wobbling 27 Hz gate (the rattle), with a gentle swell. |
| `collapse.wav` | 0.90 s | Low-passed noise rumble, sine drops 98 -> 27 Hz and 196 -> 54 Hz, a 200-700 Hz noise body, an initial crack and debris grains whose pitch falls as the platform drops away. |
| `creak.wav` | 0.35 s | Stick-slip model: a jittered impulse train (about 50-100 Hz, rising then falling) convolved with three damped resonances (610 / 1470 / 2650 Hz); two versions with the resonances 14 % apart are cross-faded so the creak bends in pitch. |
| `finish.wav` | 2.2 s | Fanfare: C5-E5-G5-C6 arpeggio then a sustained C major chord topped by E6, with C3/C4 underneath. Brass-bell tone = six harmonics with harmonic-dependent decay. Sixteen random pentatonic sine pings (sparkle) and a three-tap echo. |
| `respawn.wav` | 0.30 s | Noise through a state-variable band-pass swept 450 -> 5200 Hz (whoosh) plus a quiet 280 -> 1500 Hz sine zip, under a sine-shaped envelope. |
| `tick.wav` | 0.12 s | 880 Hz sine with a quickly dying octave partial, 1.5 ms attack, 28 ms decay. |
| `go.wav` | 0.50 s | Brighter, an octave up: 1760 Hz with 880, 1318, 2640 and 3520 Hz partials, slight vibrato, longer decay. |
| `ui.wav` | 0.06 s | Tiny sine click gliding 1250 -> 850 Hz with an 11 ms decay. |
| `beacon.wav` | 4.0 s | Power-up swell: a detuned sine stack (root, fifth, octave, twelfth) glides two octaves D2 -> D4 over 2.7 s, upper voices fading in later, with a tremolo accelerating 4 -> 17 Hz and a swept band-pass noise riser. It lands on a D major add9 chord of detuned sine pairs with individually tremoloed upper notes, a sub thump, an airy noise burst and random high pentatonic pings, fading over the last 0.3 s. |

## Music

Every map has its own score, and all of them grow from one leitmotif, the **JUMP theme**. It is a
triplet run-up (5-6-7) into a leap from the tonic up to the fifth, a falling answer, and a
bVI - bVII - I lift (the "Mario cadence") at the end of its A phrase. Its B phrase is a rising
sequence in the relative minor. Each map quotes the theme in its own key, meter and
orchestration, and the finale gathers them all up. `tools/gen_music.py` holds the score;
`tools/music_engine.py` is the synthesiser, notation and mixer.

```
python tools/gen_music.py                  # every piece + stingers, then verify
python tools/gen_music.py gardens stingers # only some
python tools/gen_music.py --verify
```

Requires numpy and `soundfile` (for Ogg Vorbis). It is deterministic: every piece seeds its RNG
from its name. (The audio is identical run to run, but the Ogg container gets a random stream serial,
so a re-render changes the file bytes: after regenerating only some pieces, `git checkout` the
unchanged ones.) A piece takes 25-90 s to render. Pieces are independent, so they can be rendered
as parallel processes.

### Engine

* **Bowed, blown and sung parts** (string sections, solo fiddle / cello, horn / trumpet /
  trombone / tuba, flute / piccolo / whistle / ocarina / clarinet / oboe / bassoon, accordion,
  choir). These are band-limited PolyBLEP oscillators with per-voice detune, delayed vibrato and
  slow pitch drift. Each is shaped in the FFT domain by an instrument "body" (formant bumps and a
  brightness low-pass). Sections are several independent voices spread across the stereo field,
  entering a few milliseconds apart. Brass brightness follows its envelope: dark and bright
  renderings are crossfaded by loudness. The choir runs its voices through vowel formants
  (a / o / u / e / hum). Woodwinds add breath (pitched and airy noise) and a tongued "chiff".
  Legato lines glide between notes.
* **Plucked and struck parts** (harp, nylon / steel guitar, pizzicato, upright bass,
  harpsichord with a 4' choir and jack thunk, two-string piano with inharmonic partials and a
  two-stage decay, marimba, xylophone, vibraphone with motor tremolo, glockenspiel, celesta,
  music box, kalimba, tubular and church bells). These are additive: a pluck-position comb, and
  each partial with its own ratio, amplitude and decay.
* **FM and synth parts:** FM electric piano and bells, supersaw pads, analogue-style plucks and
  basses with swept filters (a bank of static filters interpolated per sample), square and saw
  leads, sub bass, and glassy sine pads.
* **Percussion:** kicks (soft / punch / 808 / concert), snares (acoustic, march, piccolo, gated,
  brush, rim), claps, hats, cymbals and swells, toms, timpani and rolls, taiko (odaiko, nagado,
  shime, rim), frame drum, cajon, shaker, tambourine, triangle, woodblock, claves, castanets,
  clock tick / tock, anvil, struck steel, gong, bubbles, drops, risers and booms.
* **Notation:** melodies are strings like `C5h G5h | A5q. G5e E5q C5q |`. Durations are
  w/h/q/e/s, t/x for triplet eighths and quarters, and `.` for dotted. `~` ties, `!` accents,
  `?` ghosts, `>N` transposes, and `[C4E4G4]q` is a chord. Every bar is length-checked, and a
  pickup bar is allowed. Chord symbols (`Bbmaj7#11`, `D/F#`, `G7sus4` ...) are voiced
  automatically with voice-leading from the previous chord. Helpers write pads, bass lines,
  arpeggios, guitar strums, waltz accompaniment, chord stabs and drum grids.
* **Mixing:** every Track is a set of circular stereo buffers. Notes are mixed with their index
  taken modulo the loop length, so the loop point is seamless by construction. Each bus has
  circular EQ, drive, chorus and side-chain pumping from the kick times. Sends go to
  **convolution reverbs with synthesised room impulses** (early reflections plus decorrelated
  noise with a per-band decay time: open air, stone tower, foundry hall, underwater cave, space)
  and to a circular ping-pong delay. The master is a circular look-ahead limiter plus a soft
  clip, normalised to a K-weighted loudness target. Tempos are nudged by well under 0.5 % so each
  loop length factors into small primes, which keeps the whole-loop FFTs fast. Repeated notes
  (strums, arpeggios, ostinati) reuse a few cached, seeded takes.

### Layers and how the game plays them

Each map score is two files of identical length: `music_<map>.ogg` (the base) and
`music_<map>_hi.ogg`. `Sfx.music()` locks them together in an `AudioStreamSynchronized`, and
`Sfx.music_progress()` (called by `LevelBase` on every checkpoint) moves the second layer:

* "add" maps: the hi layer (drums, counter-lines, brass, choir) swells in between 30 % and 50 %
  of the course. The music builds as you climb.
* Coral Depths is a "cross" map: its two layers are complete arrangements, the sunlit shallows and
  the deep. They crossfade at equal power between 35 % and 75 % of the course, so the music
  darkens as the water does.
* Party Mode plays the full score from the start. A restart takes the layer back out.

On the finish, `Sfx.fanfare("fanfare_<map>", "results")` ducks the score under the map's own
fanfare, then hands over to the results music. A new personal best adds the `new_best` sparkle.
Checkpoints play `checkpoint_<map>`, stepped up the map's scale (`Sfx.checkpoint_chime`) so the
chime is always in the score's key. While the game is paused, the score and the ambience are
low-passed and dipped (`Sfx.muffle`). Menus: the main theme on the title screens, the lobby
groove for Race / Party / Practice and the playground, and the victory reprise when every course
is beaten.

Buses: score players -> `Ducked` (fanfare duck and pause muffle) -> `Music` (the slider);
fanfares go straight to `Music`; ambience has its own `Ambience` bus and slider.

### The pieces

| File | Key / meter / tempo | Length | Character |
|------|------|------|-----------|
| `music_title` | Bb major, 4/4, 84 | 36 bars, 1:43 | Overture. A dawn intro where celesta hints the run-up; the JUMP theme on horns; the B phrase on violins with a cello answer; a tutti reprise (trumpets, snare, timpani, cymbals); a hushed coda with music box and clarinet that leads back round. |
| `music_lobby` | F major, 4/4 swung, 108 | 32 bars, 1:11 | Funk warm-up: punchy kit, octave synth bass, e-piano comping, muted guitar chicks, trumpet stabs, a vibes riff, the JUMP theme syncopated on a muted square lead, and a clap break with vibes licks. Also the playground's music. |
| `music_gardens` | G major, 4/4, 132 | 56 bars, 1:42 | Launch Gardens: a sunny pastoral march. Flute tune over strummed nylon guitar, pizzicato bass, shaker and glockenspiel; an ocarina bridge that turns to Eb; the JUMP theme on clarinet over G - C - Am - D - G - Eb - F - G. **hi:** piccolo, violin counter-line, full strings, horns, light kit and tambourine, timpani runs, cymbal swells. |
| `music_foundry` | D minor (phrygian), 4/4, 138 | 48 bars, 1:24 | Bounce Foundry: a forge. Marcato cello ostinato over a growling synth bass, anvils on the off-beats tuned to D and A, struck-steel clangs, and a taiko groove. A trombone and tuba march; the JUMP theme turned minor; a Bb - C - D major lift "through the pour"; a taiko breakdown with a timpani roll and riser. **hi:** full taiko ensemble (nagado, shime), snare, horns and trumpets an octave up, tremolo strings, choir chant, gongs. |
| `music_balance` | D mixolydian, 6/8, 104 | 64 bars, 1:14 | Balance Works: a sea shanty. Accordion tune over guitar "oom-pa-pa", upright bass and bodhran; a tin-whistle chorus; the JUMP theme rolling in compound time with a Bb - C - D lift; a whistle break. **hi:** fiddle doubling, stomp-clap and tambourine, a "ho!" crew, strings, a marimba sea-sparkle. |
| `music_clockwork` | E minor, 3/4 waltz, 168 | 80 bars, 1:26 | Clockwork Heights: the clock ticks every beat (tick / tock, with an escapement clunk each bar). Pizzicato and harpsichord oom-pah-pah; a music-box waltz; a warmer G major strain on clarinet and bassoon; the JUMP theme as a waltz on celesta; church bells strike the hour before the reprise. **hi:** a string waltz (cello, violas and violins), horns, triangle, tubular-bell chimes, timpani. |
| `music_reef` | F lydian, 4/4, 80 | 32 bars, 1:36 | Coral Depths, two full arrangements. **Shallows:** chorused e-piano, harp ripples, vibraphone tune, marimba, bubbles, glass pad, flute, the JUMP theme in augmentation. **Deep:** "oo" choir, low cellos, a dark filtered pulse, kalimba, celesta, whale-song glides, a church bell in a 5.5 s abyss reverb. |
| `music_orbital` | C lydian, 4/4, 100 | 48 bars, 1:55 | Orbital Drift: a delayed square-wave arpeggio, glass pads, strings and harp. A horn "station" theme climbs straight into the JUMP theme; an A minor "flare"; the B phrase on strings. **hi:** a space opera, with trumpets and trombones, snare march with triplet rolls, timpani, cymbals, choir, and driving spiccato cellos. |
| `music_xeno` | E lydian, 4/4, 92 | 48 bars, 2:05 | Xeno Wilds: an alien jungle. Glass pads, a hushed "oo" choir, a kalimba ostinato and a sub drone under a gliding **theremin**; FM creature chirps and bubbling acid as percussion; chromatic-mediant shifts (E - C - Ab) for wonder; the JUMP theme on celesta and theremin; a slow, vast "leviathan" passage with whale-like glides and gongs. **hi:** strings and a violin counter-line, horns and choir on the theme, a tribal groove (nagado, ka, shaker, tom fills), a bright synth arp. |
| `music_volcano` | C minor, **7/8** (2+2+3), 160 | 64 bars, 1:24 | Cinder Peak: the mountain erupting. A lopsided marcato ostinato and a growling, overdriven lava bass, orchestral kick, odaiko and toms; a trombone and horn theme climbing through the Neapolitan Db; the JUMP theme bursts into C major as the eruption; a chanting breakdown over a timpani roll and riser; booms, gongs and crashes. **hi:** choir, trumpets, nagado / shime / snare, tremolo strings, tom fills. |
| `music_ascent` | B minor to D major, 4/4, 128 | 56 bars, 1:45 | The Final Ascent: synthwave. Side-chained supersaws, octave bass, arps and gated snare under a climbing saw lead. A **medley** quotes every map in turn: the gardens run-up on flute, the foundry march with anvils, the clockwork music box, the reef vibes, the orbital horn. Then the JUMP theme at full height in D major, and a breakdown with a riser. **hi:** strings, choir, trombones, tom fills, trumpets and horns on the theme, booms and timpani. |
| `music_results` | C major, 4/4 swung, 92 | 16 bars, 0:42 | Course clear: piano sings the B phrase and then the A phrase over soft strings, pizzicato and brushes. |
| `music_victory` | C major, 4/4, 88 | 24 bars, 1:05 | Every course beaten: the whole JUMP theme for orchestra and choir. A on horns and violins, B on choir and strings, then A tutti with trumpets, snare, timpani, crashes and tubular bells. |

### Stingers

| File | Bus | Content |
|------|-----|---------|
| `fanfare_gardens` | Music | Flute run-up and leap, a horn chord, timpani, a glockenspiel and harp sparkle (G). |
| `fanfare_foundry` | Music | Trombone march phrase into a D major horn chord; taiko, anvils, gong. |
| `fanfare_balance` | Music | Accordion and fiddle run-up in 6/8, guitar chord, frame drum and claps (D). |
| `fanfare_clockwork` | Music | Music box turns E minor into E major; three bell strokes, celesta, ticking. |
| `fanfare_reef` | Music | Harp glissando, vibraphone chord, "oo" choir, rising bubbles (F). |
| `fanfare_orbital` | Music | Trumpet run-up and leap, brass chord, timpani, crash, FM-bell sparkle (C). |
| `fanfare_xeno` | Music | A theremin run-up and leap, an E major "ah" choir, a cascade of FM bells and kalimba, a gong. |
| `fanfare_volcano` | Music | A trumpet run-up in 7/8 into a C major brass-and-choir eruption: taiko, boom, gong, crash. |
| `fanfare_ascent` | Music | Scored to the beacon: a 2.7 s riser, a timpani roll and choir crescendo land as the crystal ignites on a D major tutti (brass, supersaws, strings, boom, crash) with the JUMP leap on top. It replaces the old `beacon` riser. |
| `checkpoint_<map>` | SFX | A two- or three-note tonic figure in each map's own timbre: glockenspiel and harp, anvil and trombone, marimba and whistle, music box, tick and bell, vibraphone and bubbles, FM bells, synth plucks. |
| `new_best` | SFX | A rising glockenspiel and harp arpeggio over a string chord. |

Scores are 32 kHz stereo Ogg Vorbis; stingers are 32 kHz stereo Ogg. The verifier checks that
every file exists, that layers match in length, peak levels, and loop-seam continuity (the step
across the wrap must look like an ordinary step inside the file).
