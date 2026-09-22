# Jump Circuit - Audio

**All audio in this project is original.** Every sound effect and every piece of
music is synthesised from maths and seeded pseudo-random noise by
`tools/gen_audio.py`. No samples, loops, sound fonts or other third-party assets
are used, so no third-party licences or attributions are needed. The generated
files are released with the project under the project's own terms.

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
| Music   | 22.05 kHz, stereo, 16-bit PCM | -14 dBFS RMS, peaks held under about -1.5 dBFS by a memoryless soft knee |

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

All three tracks are forward loops. They are rendered into **circular buffers**:
every note is mixed in with its sample index taken modulo the loop length, so
release tails that run past the end wrap round to the start. The ping-pong delay
and the reverb (six parallel damped feedback combs per channel followed by three
all-passes) are evaluated exactly in the FFT domain over the whole loop, which
makes them circular too - the echo and reverb tail of the last bar is already
present under the first bar. The only processing after that is a global gain and
a memoryless soft knee, neither of which can create a discontinuity, so the loop
point is inaudible. Each file is a whole number of bars.

Voices: `v_pad` (two detuned sine pairs panned left/right, weak 2nd/3rd
harmonics, slow LFO, raised-cosine attack/release), `v_pluck` (five harmonics,
higher ones decay faster), `v_bass` (sine + two harmonics through gentle tanh
saturation), `v_lead` (soft sine with odd harmonics and delayed vibrato),
`v_bell`, and filtered-noise percussion (`v_noise_hit`, `v_clap`), a sine-drop
`v_kick` and a short two-partial "cog" ping.

| File | Length | Description |
|------|--------|-------------|
| `music_a.wav` | 57.6 s (24 bars, 100 bpm) | Light and optimistic, D major / lydian (Dmaj9, E/D, Bm7, Gmaj7, Aadd9, F#m7, Asus4). Wide pads, plucked eighth-note arpeggio with dotted-eighth ping-pong delay, soft bass. Three 8-bar sections: sparse intro, fuller arpeggio with long bell notes and an off-beat shaker, then a bell melody. |
| `music_b.wav` | 49.66 s (24 bars, 116 bpm) | More driven and mechanical, D dorian (Dm9, G7, Fmaj7, Am7, Em7, C). Pulsing eighth-note bass with octave jumps, soft kick, sixteenth-note ticks made from high-passed noise with an accent pattern, metallic "cog" pings on fixed steps, noise claps, a masked sixteenth-note pluck arpeggio, and a soft lead melody from bar 9 (doubled by an octave bell in the last section). |
| `music_title.wav` | 40.0 s (12 bars, 72 bpm) | Calm and spacious menu piece: slow pads (Fmaj9, Cmaj7/E, Dm9, Bbmaj7#11, Gm9, Csus4add9), a sub pad, sparse bell notes with a long delay and a long dark reverb. |

In game, `Sfx.music()` crossfades on a track change (the old bed fades out over
0.6 s while the new one fades in over 0.9 s); restarting a level keeps the
current track playing.

## Godot import settings

The three music `.import` files have `edit/loop_mode=2` (Forward) so the
imported `AudioStreamWAV` loops over the whole file. As a fallback the WAVs also
carry a standard `smpl` chunk describing the same whole-file forward loop, which
Godot's default "Detect From WAV" mode picks up if an `.import` file is ever
recreated. Effects use the default import settings (no loop).
