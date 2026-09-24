#!/usr/bin/env python3
"""Jump Circuit - world sound effects: per-map footsteps and landings, movement
sounds (wall run, wall kick, mantle, air rush, boost, ice) and the machines.

Same conventions as tools/gen_audio.py (and it borrows its helpers): everything
is synthesised from maths and seeded noise - no samples - so no third-party
licences apply.  44.1 kHz mono 16-bit, peak normalised to -3 dBFS, DC removed.
One-shots get a short fade in / out; loops are rendered CIRCULARLY (noise is
filtered in the FFT domain over the whole loop, time-varying filters run over
three periods and keep the middle one, tones have a whole number of cycles,
events that run past the end wrap round to the start) and carry a smpl chunk,
so they repeat without a seam.

Usage (from anywhere):
    python tools/gen_world_sfx.py            # generate everything, then verify
    python tools/gen_world_sfx.py --verify   # only verify the files on disk

Deterministic: every clip has its own RNG seeded from gen_audio.SEED plus the
CRC of "world_" + its name, so re-running gives bit-identical files.
Requires numpy.  Afterwards run Godot once with --import.
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_audio as ga  # noqa: E402  (osc, sweep, ad_env, fft_band, svf_bandpass, grain, place, write_wav ...)

SR = ga.SR
TAU = ga.TAU
PEAK_DB = ga.SFX_PEAK_DB
OUT = ga.OUT
SIZE_BUDGET = 6.2e6

THEMES = ("gardens", "foundry", "balance", "clockwork", "reef", "orbital", "ascent")

# ---------------------------------------------------------------------------
# clip table: name -> (seconds, loop).  The verifier checks the files against it.
# ---------------------------------------------------------------------------
CLIPS = {}


def _reg(name, dur, loop=False):
    CLIPS[name] = (dur, loop)


STEP_LEN = 0.16
LAND_LEN = 0.4
for _th in THEMES:
    for _i in range(1, 5):
        _reg("step_%s_%d" % (_th, _i), STEP_LEN)
    for _i in range(1, 4):
        _reg("land_%s_%d" % (_th, _i), LAND_LEN)
for _i in range(1, 5):
    _reg("wallstep_%d" % _i, 0.13)
for _i in range(1, 4):
    _reg("wallkick_%d" % _i, 0.4)
    _reg("mantle_%d" % _i, 0.45)
    _reg("prop_bonk_%d" % _i, 0.3)
    _reg("sweep_whoosh_%d" % _i, 0.5)
    _reg("thruster_cough_%d" % _i, 0.16)
    _reg("billboard_glitch_%d" % _i, 0.11)
for _i in range(1, 3):
    _reg("pendulum_whoosh_%d" % _i, 0.7)
    _reg("jelly_bounce_%d" % _i, 0.55)
    _reg("data_zip_%d" % _i, 0.25)
for _i in range(1, 5):
    _reg("data_chirp_%d" % _i, 0.16)
for _n, _d in (("wallrun_latch", 0.35), ("land_heavy", 0.8), ("boost", 0.6),
               ("laser_on", 0.4), ("laser_off", 0.35),
               ("blink_appear", 0.4), ("blink_vanish", 0.45), ("blink_tick", 0.06),
               ("crusher_shudder", 0.45), ("crusher_slam", 1.2), ("crusher_rise", 0.9),
               ("piston_fire", 0.35), ("piston_clank", 0.45), ("piston_retract", 0.7),
               ("warp_whoosh", 0.9), ("platform_reform", 0.4),
               ("ladle_tip", 0.7), ("ladle_splash", 0.7), ("ladle_hiss", 1.0),
               ("vent_rumble", 0.8), ("vent_burst", 0.8),
               ("thruster_ignite", 0.6), ("thruster_cutoff", 0.6),
               ("flare_alarm", 0.14), ("flare_launch", 1.0),
               ("gravity_on", 0.6), ("gravity_off", 0.6),
               ("escape_tick", 0.35), ("escape_tock", 0.35),
               ("trolley_clunk", 0.6), ("counterweight_thud", 0.7),
               ("billboard_on", 0.45), ("billboard_off", 0.4)):
    _reg(_n, _d)
for _n, _d in (("air_rush", 2.5), ("wallrun_scrape", 1.0), ("ice_slide", 1.2),
               ("laser_hum", 1.0), ("conveyor_hum", 1.0), ("wind_loop", 2.0), ("motor_hum", 1.0),
               ("warp_hum", 1.5), ("ladle_pour", 1.5), ("vent_loop", 1.5), ("surge_loop", 2.0),
               ("thruster_burn", 1.2), ("flare_roar", 1.5), ("gravity_hum", 2.0),
               ("scanner_servo", 1.0), ("trolley_run", 1.2), ("pulley_rattle", 1.0),
               ("trimmer_buzz", 1.0), ("billboard_buzz", 1.0)):
    _reg(_n, _d, True)


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
def dur(name):
    return CLIPS[name][0]


def rng(name):
    return ga.rng_for("world_" + name)


def ns(dur):
    return int(round(dur * SR))


def tv(dur):
    return ga.tvec(dur)


def unit(x):
    m = np.max(np.abs(x))
    return x / m if m > 0 else x


def band(x, lo=None, hi=None, order=2):
    return ga.fft_band(x, SR, lo, hi, order)


def cband(x, lo=None, hi=None, order=2):
    """Band filter over a loop (circular: the filtered loop still wraps seamlessly)."""
    return ga.fft_band(x, SR, lo, hi, order, circular=True)


def noise(r, n, lo=None, hi=None, order=2):
    return unit(band(r.standard_normal(n), lo, hi, order))


def cnoise(r, n, lo=None, hi=None, order=2):
    return unit(cband(r.standard_normal(n), lo, hi, order))


def tilt(x, db_per_oct, circular=False, ref=1000.0):
    """Spectral tilt (e.g. -3 dB/oct = pink) in the FFT domain."""
    pad = 0 if circular else int(0.03 * SR)
    xp = x if circular else np.concatenate([np.zeros(pad), x, np.zeros(pad)])
    spec = np.fft.rfft(xp)
    f = np.maximum(np.fft.rfftfreq(len(xp), 1.0 / SR), 20.0)
    y = np.fft.irfft(spec * (f / ref) ** (db_per_oct / 6.0206), len(xp))
    return y if circular else y[pad:pad + len(x)]


def fconv(a, b):
    """Linear convolution through the FFT."""
    n = len(a) + len(b) - 1
    m = 1 << (n - 1).bit_length()
    return np.fft.irfft(np.fft.rfft(a, m) * np.fft.rfft(b, m), m)[:n]


def cconv(x, ir):
    """Circular convolution (ir shorter than x): a reverb whose tail wraps round the loop."""
    h = np.zeros(len(x))
    h[:len(ir)] = ir[:len(x)]
    return np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(h), len(x))


def svf(x, fc, q):
    return ga.svf_bandpass(x, np.broadcast_to(np.asarray(fc, dtype=float), x.shape).copy(), q, SR)


def csvf(x, fc, q):
    """Time-varying band-pass over a loop: run three periods, keep the settled middle one."""
    n = len(x)
    fc = np.broadcast_to(np.asarray(fc, dtype=float), x.shape)
    y = ga.svf_bandpass(np.tile(x, 3), np.tile(fc, 3), q, SR)
    return y[n:2 * n]


def env(t, a, tau):
    return ga.ad_env(t, a, tau)


def glide(f0, f1, t, dur):
    return ga.sweep(f0, f1, t, dur)


def tone(freq, t=None, phase=0.0):
    """Sine; `freq` may be a per-sample array (phase-accumulated, click-free glides)."""
    if np.ndim(freq) == 0:
        return np.sin(TAU * freq * t + phase)
    return ga.osc(freq, SR, phase)


def cyc(f, n):
    """Nearest frequency with a whole number of cycles in n samples (loop-safe)."""
    return max(round(f * n / SR), 1) * SR / n


def clfo(n, cycles, phase=0.0):
    return np.sin(TAU * cycles * np.arange(n) / n + phase)


def crand(r, n, max_cycles, power=1.0):
    """Smooth random modulation in -1..1 that repeats exactly every n samples."""
    x = np.zeros(n)
    i = np.arange(n) / n
    for c in range(1, max_cycles + 1):
        x += r.uniform(0.3, 1.0) / c ** power * np.sin(TAU * c * i + r.uniform(0, TAU))
    return unit(x)


def place(buf, t0, sig, gain=1.0):
    ga.place(buf, t0, sig, SR, gain)


def cplace(buf, t0, sig, gain=1.0):
    """place() that wraps round the end of a loop buffer."""
    n = len(buf)
    i0 = int(round(t0 * SR)) % n
    idx = (i0 + np.arange(len(sig))) % n
    np.add.at(buf, idx, sig * gain)


def taper(x, secs=0.004):
    """Short raised-cosine fade on the end of a building block, so a ring cut off by its
    buffer length never leaves a step when it is mixed into a longer clip."""
    k = min(int(secs * SR), len(x))
    if k > 1:
        x = x.copy()
        x[-k:] *= 0.5 + 0.5 * np.cos(np.pi * np.arange(k) / k)
    return x


def click(r, dur, lo, hi, tau):
    """Contact transient: band-passed noise with a very fast decay."""
    t = tv(dur)
    return noise(r, len(t), lo, hi) * np.exp(-t / tau)


def thud(t, f0, f1, glide_s, tau, harm=(0.35, 0.12), attack=0.002):
    """A mass hitting something: a pitched-down sine with a couple of harmonics."""
    f = glide(f0, f1, t, glide_s)
    x = tone(f)
    for k, a in enumerate(harm, start=2):
        x = x + a * tone(f * k) * np.exp(-t / (tau * 0.6))
    return taper(x * env(t, attack, tau))


def modes(t, spec, r=None, detune=0.0, hard=None):
    """Sum of exponentially damped sines [(freq, amp, tau)] - a struck object's modes.
    `hard`: strike hardness as a roll-off frequency (a soft hit barely excites high modes)."""
    x = np.zeros(len(t))
    for f, a, tau in spec:
        if r is not None:
            f *= 1.0 + r.uniform(-detune, detune)
        if f >= SR * 0.45:
            continue
        if hard:
            a /= np.sqrt(1.0 + (f / hard) ** 2)
        ph = r.uniform(0, TAU) if r is not None else 0.0
        x += a * np.sin(TAU * f * t + ph) * np.exp(-t / tau)
    return taper(x * np.minimum(t / 0.0006, 1.0))


BAR = (1.0, 2.756, 5.404, 8.933, 13.34)   # free-free beam mode ratios


def bar_modes(f1, tau1, amps=(1.0, 0.6, 0.4, 0.25, 0.15), damp=0.6):
    """Modes of a struck free bar (grating bars, brass rods, pawls)."""
    return [(f1 * k, a, tau1 / k ** damp) for k, a in zip(BAR, amps)]


def plate_modes(f11, aspect, tau11, count=10, damp=0.7, r=None):
    """Lowest modes of a simply supported rectangular plate: f ~ m^2 + (n/aspect)^2."""
    fs = sorted({(m * m + (k / aspect) ** 2) for m in range(1, 6) for k in range(1, 6)})[:count]
    base = 1.0 + 1.0 / aspect ** 2
    out = []
    for i, v in enumerate(fs):
        f = f11 * v / base
        a = 1.0 / (1.0 + 0.35 * i)
        if r is not None:
            a *= r.uniform(0.6, 1.2)
        out.append((f, a, tau11 * (f11 / f) ** damp))
    return out


def room_ir(r, rt, lo=150.0, hi=7000.0, dur=None, hf_damp=0.5):
    """Synthetic room / hall impulse response: noise whose high end decays faster."""
    dur = dur or rt * 1.1
    t = tv(dur)
    low = noise(r, len(t), lo, 1500.0) * np.exp(-6.91 * t / rt)
    high = noise(r, len(t), 1500.0, hi) * np.exp(-6.91 * t / (rt * hf_damp))
    ir = low + 0.7 * high
    ir *= np.minimum(t / 0.004, 1.0)
    return ir / np.sqrt(np.sum(ir ** 2))


def space(r, x, rt, mix, lo=150.0, hi=7000.0, hf_damp=0.5, predelay=0.006):
    ir = np.concatenate([np.zeros(int(predelay * SR)), room_ir(r, rt, lo, hi, hf_damp=hf_damp)])
    wet = fconv(x, ir)[:len(x)]
    return x + mix * wet * (np.max(np.abs(x)) / (np.max(np.abs(wet)) + 1e-9))


def grains(r, buf, count, t_lo, t_hi, f_lo, f_hi, tau_lo, tau_hi, gain=1.0, decay=None, wrap=False):
    """Scatter short band-passed noise grains (gravel, sparks, debris, crackle)."""
    for _ in range(count):
        t0 = r.uniform(t_lo, t_hi)
        c = np.exp(r.uniform(np.log(f_lo), np.log(f_hi)))
        tau = r.uniform(tau_lo, tau_hi)
        g = ga.grain(r, min(tau * 6.0, 0.08), c * 0.7, c * 1.4, tau)
        a = gain * r.uniform(0.2, 1.0) ** 1.5
        if decay:
            a *= np.exp(-(t0 - t_lo) / decay)
        (cplace if wrap else place)(buf, t0, g, a)


def bubble(f0, dur, tau, rise=0.6):
    """A bubble (Minnaert resonance): a decaying sine whose pitch rises as it forms."""
    t = tv(dur)
    f = f0 * (1.0 + rise * np.minimum(t / (tau * 3.0), 1.0))
    return taper(tone(f) * np.exp(-t / tau) * np.minimum(t / 0.0015, 1.0))


def whoosh(r, dur, f_lo, f_peak, f_end, t_peak, width, q=1.6):
    """Air moved past the ear: noise through a band that rises to the pass then falls (Doppler)."""
    t = tv(dur)
    k = np.where(t < t_peak, (t / t_peak) ** 1.5, 1.0)
    fc = np.where(t < t_peak, f_lo * (f_peak / f_lo) ** k,
                  f_peak * (f_end / f_peak) ** np.clip((t - t_peak) / max(dur - t_peak, 1e-3), 0, 1) ** 0.7)
    x = svf(r.standard_normal(len(t)), fc, q)
    e = np.exp(-0.5 * ((t - t_peak) / width) ** 2)
    e = np.where(t > t_peak, np.exp(-0.5 * ((t - t_peak) / (width * 1.4)) ** 2), e)
    return unit(x) * e


def buzz_wave(f0, n, harmonics=24, tilt_pow=1.0, even=1.0):
    """Band-limited buzzy periodic wave (a saw-like sum of sines)."""
    t = np.arange(n) / SR
    x = np.zeros(n)
    for k in range(1, harmonics + 1):
        if f0 * k > SR * 0.42:
            break
        a = 1.0 / k ** tilt_pow * (even if k % 2 == 0 else 1.0)
        x += a * np.sin(TAU * f0 * k * t)
    return unit(x)


# ---------------------------------------------------------------------------
# output
# ---------------------------------------------------------------------------
LOG = []

# Footsteps and landings are loudness-matched across the maps instead of peak-normalised
# (a clicky glass step and a soft grass step at the same peak differ by ~8 dB to the ear):
# each is scaled to an A-weighted short-term loudness, never above the -3 dBFS peak.
STEP_LOUD_DB = -25.0
LAND_LOUD_DB = -23.0


def a_weight(f):
    f2 = np.maximum(f, 1.0) ** 2
    ra = (12194.0 ** 2 * f2 ** 2) / ((f2 + 20.6 ** 2) * np.sqrt((f2 + 107.7 ** 2) * (f2 + 737.9 ** 2)) *
                                     (f2 + 12194.0 ** 2))
    return ra / 0.7943


def loudness(x, win=0.08):
    """A-weighted RMS of the loudest `win` seconds (dB)."""
    y = np.fft.irfft(np.fft.rfft(x) * a_weight(np.fft.rfftfreq(len(x), 1.0 / SR)), len(x))
    k = int(win * SR)
    best = max(np.sqrt(np.mean(y[i:i + k] ** 2)) for i in range(0, max(len(y) - k, 1), k // 4))
    return ga.db(best)


def levelled_target(name):
    if name.startswith("step_"):
        return STEP_LOUD_DB
    if name.startswith("land_") and name != "land_heavy":
        return LAND_LOUD_DB
    return None


def _fit(name, x):
    want = ns(CLIPS[name][0])
    if len(x) < want:
        x = np.concatenate([x, np.zeros(want - len(x))])
    return x[:want]


def save(name, x, fin=0.002, fout=0.02):
    x = _fit(name, np.asarray(x, dtype=float))
    x = band(x, 18.0, None, 2)          # DC / subsonic out first, so the fades end on zero
    x = ga.fade(x - np.mean(x), SR, fin, fout)
    x *= 10.0 ** (PEAK_DB / 20.0) / np.max(np.abs(x))
    target = levelled_target(name)
    if target is not None:
        x *= min(10.0 ** ((target - loudness(x)) / 20.0), 1.0)
    ga.write_wav(name, x, SR)
    LOG.append(name)
    print("  %-24s %5.2f s  peak %6.2f dBFS  rms %6.1f dB" % (
        name + ".wav", len(x) / SR, ga.db(np.max(np.abs(x))), ga.db(np.sqrt(np.mean(x ** 2)))))


def save_loop(name, x):
    """Loops: no fades (they would put a dip on the seam); mean removal and gain are seam-safe."""
    x = _fit(name, np.asarray(x, dtype=float))
    x = ga.norm_peak(x)
    ga.write_wav(name, x, SR, loop=True)
    LOG.append(name)
    print("  %-24s %5.2f s  loop  rms %6.1f dB  wrap step %.4f" % (
        name + ".wav", len(x) / SR, ga.db(np.sqrt(np.mean(x ** 2))), abs(x[0] - x[-1])))


# ===========================================================================
# per-map footsteps and landings
# ===========================================================================
# One material model per map, shared by the step (k = 0) and the landing (k = 1)
# so they sound like the same floor.  Each variant re-rolls the modes, the noise
# and the heel/toe timing.

def surface_hit(theme, r, k, dur):
    n = ns(dur)
    t = tv(dur)
    x = np.zeros(n)
    toe_t = r.uniform(0.024, 0.04)  # heel then toe (a step); a landing is both feet at once
    toe_g = r.uniform(0.35, 0.55) * (1.0 - 0.6 * k)

    def both(sig, gain=1.0, spread=True):
        place(x, 0.0, sig, gain)
        if spread and toe_g > 0.05:
            place(x, toe_t, sig, gain * toe_g)

    if theme == "gardens":
        # soft earth under grass: a damped pat, loose soil, a rustle of blades
        body = thud(t, r.uniform(125, 150), 62, 0.05, 0.022 + 0.03 * k, harm=(0.2, 0.05))
        soil = noise(r, n, 120, 900) * env(t, 0.002, 0.016 + 0.03 * k)
        both(body + 0.55 * soil, 1.0)
        rustle = np.zeros(n)
        grains(r, rustle, int(30 + 70 * k), 0.0, 0.06 + 0.12 * k, 2500, 9000, 0.0015, 0.005, 1.0,
               decay=0.03 + 0.06 * k)
        grains(r, rustle, int(6 + 22 * k), 0.004, 0.05 + 0.15 * k, 500, 2200, 0.003, 0.009, 0.8,
               decay=0.04 + 0.06 * k)   # clods and pebbles
        x += 0.42 * unit(rustle)
        x = band(x, None, 9000)
        if k:
            place(x, 0.0, thud(t, 90, 42, 0.1, 0.07, harm=(0.25,)), 0.9)
    elif theme == "foundry":
        # steel grating over a void: a hard click, ringing bars, the hollow box under it,
        # and the grating chattering in its frame
        f1 = r.uniform(360, 460)
        ring = modes(t, bar_modes(f1, 0.055 + 0.05 * k), r, 0.03, hard=5000 + 3000 * k)
        cav = thud(t, r.uniform(185, 225), r.uniform(165, 190), 0.05, 0.045 + 0.05 * k, harm=(0.3,))
        both(click(r, dur, 2000, 11000, 0.0012) * 0.9 + 0.55 * ring + 0.6 * cav
             + 0.5 * thud(t, 130, 70, 0.03, 0.018))
        for j in range(int(1 + 5 * k + r.integers(0, 2))):
            tj = r.uniform(0.012, 0.035) + j * r.uniform(0.018, 0.04)
            rat = modes(tv(0.08), bar_modes(f1 * r.uniform(0.97, 1.03), 0.02), r, 0.04, hard=4000)
            place(x, tj, rat + 0.5 * click(r, 0.08, 1500, 8000, 0.001), 0.28 * np.exp(-j * 0.4))
        if k:
            place(x, 0.0, thud(t, 95, 45, 0.12, 0.12), 0.8)
            x = space(r, x, 0.9, 0.35, 200, 6000)
    elif theme == "balance":
        # painted steel deck (the paint deadens it) over timber bearers
        plate = modes(t, plate_modes(r.uniform(220, 260), 1.6, 0.035 + 0.04 * k, 8, 0.8, r), r, 0.02, hard=3500)
        wood = modes(t, [(r.uniform(480, 560), 1.0, 0.012), (r.uniform(850, 960), 0.6, 0.009),
                         (r.uniform(1350, 1550), 0.35, 0.006)], r, 0.0)
        both(click(r, dur, 1500, 6500, 0.0011) * 0.7 + 0.5 * plate + 0.45 * wood
             + 0.8 * thud(t, 135, 72, 0.035, 0.022 + 0.02 * k))
        if k:
            place(x, 0.0, thud(t, 100, 48, 0.1, 0.09), 0.75)
            grains(r, x, 10, 0.01, 0.12, 800, 3000, 0.002, 0.006, 0.12, decay=0.05)
            x = space(r, x, 0.6, 0.2, 200, 5000)
    elif theme == "clockwork":
        # waxed oak boards with brass inlay: a warm knock and the faintest brass shimmer
        oak = modes(t, [(r.uniform(205, 235), 1.0, 0.03), (r.uniform(440, 500), 0.7, 0.02),
                        (r.uniform(760, 830), 0.45, 0.014), (r.uniform(1200, 1320), 0.3, 0.009),
                        (r.uniform(2100, 2400), 0.15, 0.005)], r, 0.0)
        brass = modes(t, bar_modes(r.uniform(1150, 1400), 0.12 + 0.1 * k, (1.0, 0.5, 0.3, 0.15, 0.08), 0.5), r, 0.01)
        both(click(r, dur, 1000, 5000, 0.0018) * 0.7 + 0.8 * oak + 0.1 * brass
             + 0.7 * thud(t, 150, 88, 0.03, 0.028 + 0.03 * k))
        if k:
            place(x, 0.0, thud(t, 105, 55, 0.08, 0.1), 0.7)
            place(x, 0.0, modes(t, bar_modes(r.uniform(900, 1100), 0.3), r, 0.01), 0.1)
        x = space(r, x, 0.7 + 0.4 * k, 0.16 + 0.1 * k, 200, 6000)
    elif theme == "reef":
        # wet sand that sucks at the foot, brittle coral crumbs, water in the pores; muffled
        suck = svf(r.standard_normal(n), glide(r.uniform(850, 1000), 320, t, 0.06 + 0.05 * k), 2.2)
        suck = unit(suck) * env(t, 0.004, 0.03 + 0.04 * k)
        body = thud(t, r.uniform(105, 125), 55, 0.05, 0.03 + 0.04 * k, harm=(0.2,))
        both(0.75 * suck + body)
        crunch = np.zeros(n)
        grains(r, crunch, int(8 + 20 * k), 0.004, 0.05 + 0.1 * k, 1200, 4500, 0.0015, 0.004, 1.0, decay=0.04)
        x += 0.35 * unit(crunch)
        for _ in range(int(2 + 5 * k)):
            place(x, r.uniform(0.01, 0.07 + 0.15 * k), bubble(r.uniform(900, 2200), 0.03, 0.006), 0.12)
        x = band(x, None, 3000, 3)
        if k:
            place(x, 0.0, thud(t, 80, 38, 0.12, 0.09), 0.8)
    elif theme == "orbital":
        # thin deck plate over a service void: bright ring, a hollow boom, station air
        plate = modes(t, plate_modes(r.uniform(290, 340), 1.3, 0.09 + 0.08 * k, 10, 0.55, r), r, 0.02,
                      hard=7000 + 3000 * k)
        tink = modes(t, bar_modes(r.uniform(2100, 2500), 0.05, (1.0, 0.4, 0.2, 0.1, 0.05)), r, 0.02)
        boom = thud(t, r.uniform(110, 125), 92, 0.05, 0.07 + 0.08 * k, harm=(0.3, 0.1))
        both(click(r, dur, 3000, 13000, 0.0009) * 0.8 + 0.45 * plate + 0.18 * tink + 0.7 * boom)
        if k:
            place(x, 0.0, thud(t, 85, 40, 0.12, 0.12), 0.7)
            for j in range(3):
                place(x, 0.03 + 0.03 * j + r.uniform(0, 0.01),
                      modes(tv(0.1), plate_modes(r.uniform(300, 360), 1.3, 0.03, 6, 0.6, r), r, 0.03, hard=6000),
                      0.2 * 0.6 ** j)
        x = space(r, x, 0.5 + 0.4 * k, 0.22, 250, 9000, 0.6)
    elif theme == "ascent":
        # hard glass over a neon panel: a sharp tick, a high glassy ring, a thin buzz
        glass = modes(t, plate_modes(r.uniform(650, 760), 1.4, 0.07 + 0.08 * k, 10, 0.35, r), r, 0.01,
                      hard=9000)
        body = thud(t, 170, 95, 0.025, 0.018 + 0.02 * k, harm=(0.2,))
        both(click(r, dur, 2500, 15000, 0.0007) * 1.0 + 0.3 * glass + 0.55 * body)
        tb = tv(0.03)
        buzz = noise(r, len(tb), 1500, 7000) * (0.5 + 0.5 * np.sin(TAU * 120 * tb)) ** 6 * env(tb, 0.001, 0.008)
        place(x, 0.003, buzz, 0.25 + 0.15 * k)
        if k:
            place(x, 0.0, thud(t, 110, 55, 0.08, 0.08), 0.65)
            place(x, 0.02, modes(tv(dur - 0.02), plate_modes(r.uniform(900, 1000), 1.4, 0.12, 8, 0.3, r), r, 0.01), 0.12)
        x = space(r, x, 0.5, 0.12, 400, 10000, 0.7)
    return x


def gen_steps():
    for th in THEMES:
        for i in range(1, 5):
            name = "step_%s_%d" % (th, i)
            save(name, surface_hit(th, rng(name), 0.0, STEP_LEN), fin=0.0008, fout=0.03)
        for i in range(1, 4):
            name = "land_%s_%d" % (th, i)
            save(name, surface_hit(th, rng(name), 1.0, LAND_LEN), fin=0.0008, fout=0.08)


# ===========================================================================
# movement
# ===========================================================================
def panel_knock(r, t, weight=1.0):
    """The wall-run panel: a dark composite slab on a frame - hollow, a little metallic."""
    plate = modes(t, plate_modes(r.uniform(260, 300), 2.2, 0.03 + 0.02 * weight, 8, 0.7, r), r, 0.02,
                  hard=3000 + 2000 * weight)
    cav = thud(t, r.uniform(150, 175), 135, 0.03, 0.035 + 0.02 * weight, harm=(0.25,))
    return 0.45 * plate + 0.7 * cav + 0.5 * click(r, len(t) / SR, 1200, 7000, 0.0012)


def crackle(r, dur, count, lo=3000, hi=11000, wrap=False, n=None):
    """Spark crackle: sparse sharp ticks (the panel's cyan sparks, a live beam)."""
    buf = np.zeros(n if n is not None else ns(dur))
    for _ in range(count):
        t0 = r.uniform(0, dur)
        tk = tv(0.004)
        g = noise(r, len(tk), lo, hi) * np.exp(-tk / r.uniform(0.0003, 0.0009))
        (cplace if wrap else place)(buf, t0, g, r.uniform(0.2, 1.0) ** 2)
    return buf


def gen_wall():
    for i in range(1, 5):
        name = "wallstep_%d" % i
        r = rng(name)
        t = tv(dur(name))
        x = panel_knock(r, t, 0.6) + 0.35 * crackle(r, 0.03, 5, n=len(t))
        save(name, x, fin=0.0008, fout=0.03)

    name = "wallrun_latch"
    r = rng(name)
    t = tv(dur(name))
    x = panel_knock(r, t, 1.2)
    zing = tone(glide(700, 2100, t, 0.09)) * env(t, 0.004, 0.06)
    zing += 0.3 * tone(glide(1400, 4200, t, 0.09)) * env(t, 0.004, 0.04)
    x += 0.22 * zing + 0.45 * crackle(r, 0.12, 22, n=len(t))
    x += 0.35 * unit(svf(r.standard_normal(len(t)), glide(1500, 4500, t, 0.2), 3.0)) * env(t, 0.02, 0.08)
    save(name, x, fin=0.0008, fout=0.08)

    # wall kick: a heavy push-off from the panel, sparks, and the whoosh of being thrown off it
    for i in range(1, 4):
        name = "wallkick_%d" % i
        r = rng(name)
        t = tv(dur(name))
        x = 1.1 * panel_knock(r, t, 1.6) + 0.6 * thud(t, 120, 55, 0.05, 0.05)
        x += 0.4 * crackle(r, 0.08, 18, n=len(t))
        x += 0.7 * whoosh(r, dur(name), r.uniform(500, 700), r.uniform(3000, 3800), 1100, 0.1, 0.05)
        save(name, x, fin=0.0008, fout=0.1)

    # mantle: the hands slap onto the lip, a scramble of feet, and Volt's servos hauling up
    for i in range(1, 4):
        name = "mantle_%d" % i
        r = rng(name)
        t = tv(dur(name))
        x = np.zeros(len(t))
        th = tv(0.12)
        hand = modes(th, bar_modes(r.uniform(1050, 1300), 0.025), r, 0.03, hard=6000)
        hand = 0.5 * hand + click(r, 0.12, 300, 3500, 0.005) + 0.5 * thud(th, 190, 110, 0.02, 0.015)
        place(x, 0.0, hand, 1.0)
        place(x, r.uniform(0.035, 0.06), hand, 0.7)
        for ts in (r.uniform(0.13, 0.16), r.uniform(0.22, 0.26)):
            tsv = tv(0.05)
            scuff = noise(r, len(tsv), 700, 5000) * env(tsv, 0.004, 0.012)
            place(x, ts, scuff + 0.5 * thud(tsv, 150, 100, 0.02, 0.012), 0.4)
        tw = tv(0.3)
        f = glide(250, 640, tw, 0.28) * (1.0 + 0.01 * np.sin(TAU * 38 * tw))
        servo = (tone(f) + 0.45 * tone(2 * f) + 0.2 * tone(3 * f)) * np.sin(np.pi * tw / 0.3) ** 1.5
        place(x, 0.05, servo, 0.16)
        place(x, 0.34, thud(tv(0.1), 140, 80, 0.03, 0.02), 0.45)
        save(name, x, fin=0.0008, fout=0.08)

    name = "land_heavy"
    r = rng(name)
    t = tv(dur(name))
    x = 1.2 * thud(t, 72, 30, 0.2, 0.16, harm=(0.4, 0.15))
    x += 0.7 * noise(r, len(t), 150, 700) * env(t, 0.003, 0.05)
    x += 0.5 * click(r, 0.8, 800, 7000, 0.003)
    grains(r, x, 26, 0.02, 0.45, 400, 3200, 0.003, 0.012, 0.35, decay=0.15)
    # the knees soak it up: a short descending servo groan
    tg = tv(0.22)
    fg = glide(520, 190, tg, 0.2)
    groan = (tone(fg) + 0.5 * tone(fg * 2.01) + 0.25 * tone(fg * 3.02)) * env(tg, 0.01, 0.08)
    place(x, 0.03, groan, 0.18)
    save(name, x, fin=0.0008, fout=0.15)

    # boost strip launch: an electric zing that climbs, a whoosh and a shove
    name = "boost"
    r = rng(name)
    t = tv(dur(name))
    f = glide(480, 2500, t, 0.13) * (1.0 + 0.012 * np.sin(TAU * 11 * t) * np.minimum(t / 0.15, 1.0))
    fm = 1.0 + 0.004 * np.sin(TAU * f * 1.5 * t)
    z = tone(f * fm) + 0.4 * tone(2 * f) * np.exp(-t / 0.1) + 0.2 * tone(3.01 * f) * np.exp(-t / 0.06)
    z += 0.25 * tone(f * 1.005) + 0.25 * tone(f * 0.995)
    z *= env(t, 0.006, 0.16)
    x = 0.5 * z + 0.8 * whoosh(r, 0.6, 700, 5200, 1500, 0.12, 0.07) + 0.6 * thud(t, 110, 60, 0.04, 0.04)
    x += 0.3 * crackle(r, 0.15, 25, n=len(t))
    save(name, x, fin=0.0008, fout=0.12)


def gen_movement_loops():
    # air rush: the wind of your own speed - broadband turbulence, a buffeting low end, a
    # thin whistle that wanders, all breathing with slow gusts
    name = "air_rush"
    r = rng(name)
    n = ns(dur(name))
    body = cnoise(r, n, 120, 5500, 1)
    body = unit(tilt(body, -3.0, circular=True))
    gust = 0.62 + 0.38 * crand(r, n, 7)
    low = cnoise(r, n, 28, 170, 2) * (0.6 + 0.4 * crand(r, n, 24))
    whistle_fc = 1150 * (1.0 + 0.18 * crand(r, n, 4))
    whistle = unit(csvf(r.standard_normal(n), whistle_fc, 14.0)) * (0.5 + 0.5 * crand(r, n, 5))
    flutter = cnoise(r, n, 3500, 9000) * (0.5 + 0.5 * crand(r, n, 30)) ** 2
    x = body * gust + 0.75 * low + 0.12 * whistle + 0.12 * flutter
    save_loop(name, x)

    # wall-run scrape: friction hiss with stick-slip jitter, a faint squeal and the sparks
    name = "wallrun_scrape"
    r = rng(name)
    n = ns(dur(name))
    hiss = cnoise(r, n, 1600, 7500) * (0.55 + 0.45 * crand(r, n, 70, 0.3))
    grind = cnoise(r, n, 150, 700) * (0.6 + 0.4 * crand(r, n, 40, 0.5))
    squeal = unit(csvf(r.standard_normal(n), cyc(2600, n) * (1 + 0.04 * crand(r, n, 3)), 22.0))
    x = hiss + 0.5 * grind + 0.07 * squeal + 0.8 * crackle(r, dur(name), 60, wrap=True, n=n)
    save_loop(name, x)

    # ice slide: a smooth hiss of the sole on ice, a little skate rumble, rare squeaks and ticks
    name = "ice_slide"
    r = rng(name)
    n = ns(dur(name))
    hiss = cnoise(r, n, 2500, 10000) * (0.8 + 0.2 * crand(r, n, 9))
    shh = cnoise(r, n, 600, 2200) * (0.7 + 0.3 * crand(r, n, 6))
    rum = cnoise(r, n, 90, 320)
    squeak = unit(csvf(r.standard_normal(n), 3400 * (1 + 0.06 * crand(r, n, 2)), 28.0)) * \
        np.maximum(crand(r, n, 3), 0.0) ** 2
    ticks = crackle(r, dur(name), 14, 5000, 12000, wrap=True, n=n)
    x = hiss + 0.45 * shh + 0.3 * rum + 0.1 * squeak + 0.5 * ticks
    save_loop(name, x)


# ===========================================================================
# lasers, blink platforms, crushers, pistons, sweepers, pendulums
# ===========================================================================
def hum_stack(n, f0, count, tilt_pow=1.1, even=1.4, r=None):
    """Mains / transformer hum: a harmonic stack, even harmonics strong (magnetostriction)."""
    t = np.arange(n) / SR
    x = np.zeros(n)
    for k in range(1, count + 1):
        if f0 * k > SR * 0.4:
            break
        a = 1.0 / k ** tilt_pow * (even if k % 2 == 0 else 1.0)
        x += a * np.sin(TAU * f0 * k * t + (r.uniform(0, TAU) if r is not None else 0.0))
    return unit(x)


def gen_lasers():
    # the beam's hum: 110 Hz transformer stack, a crackling electric buzz locked to it,
    # a thin high whine beating slowly, a gentle 2 Hz wobble
    name = "laser_hum"
    r = rng(name)
    n = ns(dur(name))
    t = np.arange(n) / SR
    f0 = cyc(110, n)
    hum = hum_stack(n, f0, 16, 1.0, 1.5, r)
    pulse = (0.5 + 0.5 * np.sin(TAU * f0 * t)) ** 8
    buzz = cnoise(r, n, 2000, 9000) * pulse
    whine = np.sin(TAU * cyc(3520, n) * t) + np.sin(TAU * cyc(3524, n) * t)
    x = hum * (0.9 + 0.1 * clfo(n, 2)) + 0.35 * unit(buzz) + 0.04 * whine
    x += 0.25 * crackle(r, dur(name), 30, wrap=True, n=n)
    save_loop(name, x)

    name = "laser_on"
    r = rng(name)
    t = tv(dur(name))
    f = np.where(t < 0.05, glide(150, 2400, t, 0.05), 2400 * (880 / 2400) ** np.clip((t - 0.05) / 0.08, 0, 1))
    zap = (tone(f) + 0.5 * tone(f * 1.5) * np.exp(-t / 0.05)) * env(t, 0.002, 0.07)
    crack = click(r, 0.4, 1000, 12000, 0.006)
    boom = thud(t, 95, 45, 0.06, 0.06)
    hum = hum_stack(len(t), 110, 12, 1.0, 1.5, r) * env(t, 0.02, 0.12)
    sizzle = noise(r, len(t), 3000, 9000) * (0.5 + 0.5 * np.sin(TAU * 110 * t)) ** 6 * env(t, 0.01, 0.12)
    x = 0.45 * zap + 0.8 * crack + 0.6 * boom + 0.4 * hum + 0.5 * unit(sizzle) + 0.4 * crackle(r, 0.25, 25, n=len(t))
    save(name, x, fin=0.0008, fout=0.1)

    name = "laser_off"
    r = rng(name)
    t = tv(dur(name))
    f = glide(1300, 55, t, 0.26)
    down = (tone(f) + 0.4 * tone(2 * f) + 0.2 * tone(3 * f)) * env(t, 0.003, 0.1)
    x = 0.6 * down + 0.6 * click(r, 0.35, 1500, 9000, 0.003) + 0.35 * crackle(r, 0.12, 14, n=len(t))
    x += 0.3 * noise(r, len(t), 2500, 8000) * env(t, 0.005, 0.05)
    save(name, x, fin=0.0008, fout=0.08)

    # blink platforms: materialise / dematerialise shimmer-zaps and the flicker tick
    name = "blink_appear"
    r = rng(name)
    t = tv(dur(name))
    sweep_n = unit(svf(r.standard_normal(len(t)), glide(400, 6000, t, 0.12), 3.0)) * env(t, 0.06, 0.04)
    x = 0.5 * sweep_n
    for t0, m in ((0.07, 84), (0.1, 91)):
        tt = tv(0.3)
        fm = ga.mtof(m)
        c = tone(fm * (1 + 0.003 * np.sin(TAU * 7 * tt))) + 0.3 * tone(fm * 2.01, tt) * np.exp(-tt / 0.05)
        place(x, t0, c * env(tt, 0.003, 0.09), 0.35)
    place(x, 0.1, thud(tv(0.15), 190, 105, 0.03, 0.03), 0.6)
    save(name, x, fin=0.002, fout=0.08)

    name = "blink_vanish"
    r = rng(name)
    t = tv(dur(name))
    # a descending tone quantised into steps (a glitchy dissolve)
    steps = np.floor(t / 0.028)
    f = 1700 * (280 / 1700) ** np.clip(steps * 0.028 / 0.3, 0, 1)
    g = (tone(f) + 0.35 * tone(f * 2.0)) * env(t, 0.004, 0.14)
    disp = unit(svf(r.standard_normal(len(t)), glide(5500, 600, t, 0.3), 2.5)) * env(t, 0.005, 0.12)
    x = 0.4 * g + 0.5 * disp
    for _ in range(14):
        tt = tv(0.12)
        place(x, r.uniform(0.0, 0.3), tone(r.uniform(2500, 6000), tt) * env(tt, 0.001, 0.02), 0.1)
    save(name, x, fin=0.001, fout=0.1)

    name = "blink_tick"
    r = rng(name)
    t = tv(dur(name))
    x = (tone(2200, t) + 0.4 * tone(4410, t)) * env(t, 0.0008, 0.008) + 0.3 * click(r, 0.06, 3000, 9000, 0.0008)
    save(name, x, fin=0.0005, fout=0.02)


def gen_crusher_piston():
    # the press shudders: a stick-slip groan of the guides, rattling chains, a rumble building
    name = "crusher_shudder"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    imp = np.zeros(n)
    pos = 0.0
    while pos < 0.45:
        imp[min(int(pos * SR), n - 1)] = r.uniform(0.5, 1.0)
        pos += 1.0 / (38.0 + 30.0 * pos) * r.uniform(0.85, 1.15)
    k = modes(tv(0.05), [(180, 1.0, 0.012), (430, 0.6, 0.008), (950, 0.35, 0.005), (1900, 0.2, 0.003)])
    groan = fconv(imp, k)[:n]
    rattle = noise(r, n, 800, 3200) * (0.5 + 0.5 * np.sign(np.sin(TAU * 31 * t)))
    rumble = noise(r, n, 35, 200)
    x = unit(groan) + 0.3 * unit(band(rattle, None, 5000)) + 0.6 * rumble
    x *= np.minimum(t / 0.3, 1.0) ** 1.3 * 0.7 + 0.3
    save(name, x, fin=0.004, fout=0.04)

    # the slam: crack, a sub boom, the ringing steel block, floor thump, debris and dust
    name = "crusher_slam"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = 0.9 * click(r, dur(name), 500, 9000, 0.008)
    x += 1.2 * thud(t, 60, 27, 0.25, 0.35, harm=(0.45, 0.2))
    x += 0.45 * modes(t, plate_modes(140, 1.4, 0.3, 12, 0.6, r), r, 0.02, hard=3000)
    # the four steel teeth on its underside clang against the floor plate
    for j in range(4):
        place(x, r.uniform(0.0, 0.006), modes(t, bar_modes(r.uniform(520, 700), 0.16), r, 0.02, hard=6000), 0.12)
    x += 0.7 * noise(r, n, 60, 450) * env(t, 0.002, 0.15)
    grains(r, x, 38, 0.03, 0.7, 400, 3200, 0.003, 0.012, 0.3, decay=0.25)
    x += 0.12 * noise(r, n, 1000, 6000) * env(t, 0.05, 0.4)
    x = space(r, x, 1.1, 0.3, 120, 5000)
    save(name, x, fin=0.0008, fout=0.3)

    # and hauls itself back up: a hydraulic whine climbing, the valve's hiss, fluid gurgle
    name = "crusher_rise"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    f = glide(150, 265, t, 0.85) * (1.0 + 0.01 * np.sin(TAU * 29 * t))
    whine = (tone(f) + 0.55 * tone(2 * f) + 0.3 * tone(3 * f) + 0.15 * tone(5 * f))
    whine *= np.minimum(t / 0.08, 1.0) * np.clip((dur(name) - t) / 0.25, 0, 1)
    hiss = noise(r, n, 2000, 7500) * env(t, 0.01, 0.2)
    gurgle = noise(r, n, 90, 420) * (0.5 + 0.5 * np.sin(TAU * 13 * t + 3 * np.sin(TAU * 3 * t)))
    x = 0.4 * unit(whine) + 0.45 * hiss + 0.3 * unit(gurgle) * np.minimum(t / 0.1, 1.0)
    save(name, x, fin=0.01, fout=0.2)

    # piston: the pneumatic valve fires, the ram hits its end stop, then vents steam on retract
    name = "piston_fire"
    r = rng(name)
    t = tv(dur(name))
    blast = noise(r, len(t), 600, 8000) * env(t, 0.003, 0.05)
    x = blast + 0.8 * thud(t, 130, 60, 0.04, 0.045) + 0.35 * modes(t, [(2800, 1.0, 0.005), (4100, 0.5, 0.003)])
    x += 0.4 * noise(r, len(t), 200, 900) * env(t, 0.01, 0.06)
    save(name, x, fin=0.0008, fout=0.06)

    name = "piston_clank"
    r = rng(name)
    t = tv(dur(name))
    x = 0.55 * modes(t, bar_modes(255, 0.16), r, 0.02, hard=5000) + 0.9 * click(r, 0.45, 800, 8000, 0.002)
    x += 1.0 * thud(t, 115, 52, 0.05, 0.06)
    for j in range(2):
        place(x, 0.02 + 0.025 * j, modes(tv(0.1), bar_modes(255 * r.uniform(1.8, 2.2), 0.02), r, 0.03), 0.15)
    x = space(r, x, 0.6, 0.15)
    save(name, x, fin=0.0008, fout=0.1)

    name = "piston_retract"
    r = rng(name)
    t = tv(dur(name))
    hiss = noise(r, len(t), 1500, 9000) * env(t, 0.02, 0.22) * (0.75 + 0.25 * np.sin(TAU * 17 * t))
    servo = tone(glide(210, 150, t, 0.6)) * env(t, 0.05, 0.25)
    x = hiss + 0.12 * servo
    save(name, x, fin=0.01, fout=0.2)


def gen_swings():
    for i in range(1, 4):
        name = "sweep_whoosh_%d" % i
        r = rng(name)
        t = tv(dur(name))
        tp = r.uniform(0.2, 0.24)
        w = whoosh(r, 0.5, r.uniform(280, 350), r.uniform(1900, 2500), 550, tp, 0.06)
        e = np.exp(-0.5 * ((t - tp) / 0.06) ** 2)
        sizzle = noise(r, len(t), 4000, 9500) * (0.5 + 0.5 * np.sin(TAU * 100 * t)) ** 6 * e
        low = noise(r, len(t), 70, 260) * e
        save(name, w + 0.35 * unit(sizzle) + 0.4 * low, fin=0.01, fout=0.1)
    for i in range(1, 3):
        name = "pendulum_whoosh_%d" % i
        r = rng(name)
        t = tv(dur(name))
        tp = r.uniform(0.33, 0.38)
        w = whoosh(r, dur(name), 140, r.uniform(800, 1000), 240, tp, 0.12, q=1.2)
        e = np.exp(-0.5 * ((t - tp) / 0.12) ** 2)
        vw = tone(np.interp(t, [0, tp, dur(name)], [70, 96, 58])) * e
        save(name, w + 0.5 * vw + 0.3 * noise(r, len(t), 50, 180) * e, fin=0.01, fout=0.15)


# ===========================================================================
# surfaces, wind, motors, portals, props
# ===========================================================================
def gen_surfaces():
    # conveyor: a 50 Hz motor, its rotor whine, rollers clicking under the belt, belt hiss
    name = "conveyor_hum"
    r = rng(name)
    n = ns(dur(name))
    t = np.arange(n) / SR
    motor = hum_stack(n, cyc(50, n), 12, 1.2, 1.3, r) * (0.9 + 0.1 * clfo(n, 6))
    whine = np.sin(TAU * cyc(610, n) * t) * (0.7 + 0.3 * clfo(n, 3))
    rollers = np.zeros(n)
    for j in range(10):
        tk = tv(0.03)
        c = modes(tk, [(r.uniform(1300, 1600), 1.0, 0.006), (r.uniform(2500, 2900), 0.5, 0.003)], r, 0.0)
        c = c + 0.4 * noise(r, len(tk), 800, 4000) * np.exp(-tk / 0.002)
        cplace(rollers, j * dur(name) / 10 + r.uniform(-0.004, 0.004), c, r.uniform(0.5, 1.0))
    hiss = cnoise(r, n, 900, 5000)
    x = motor + 0.08 * whine + 0.45 * unit(rollers) + 0.18 * hiss
    save_loop(name, x)

    # wind zones and updrafts: steady moving air with gusts, a swirling band and a whistle
    name = "wind_loop"
    r = rng(name)
    n = ns(dur(name))
    base = unit(tilt(cnoise(r, n, 90, 6000, 1), -2.5, circular=True)) * (0.7 + 0.3 * crand(r, n, 5))
    swirl = unit(csvf(r.standard_normal(n), 700 * 2.0 ** (1.2 * crand(r, n, 3)), 3.0)) * (0.6 + 0.4 * crand(r, n, 4))
    whistle = unit(csvf(r.standard_normal(n), 1600 * (1 + 0.1 * crand(r, n, 2)), 18.0))
    low = cnoise(r, n, 30, 140) * (0.6 + 0.4 * crand(r, n, 12))
    save_loop(name, base + 0.6 * swirl + 0.08 * whistle + 0.5 * low)

    # moving platforms: a soft hover hum from the thruster pods
    name = "motor_hum"
    r = rng(name)
    n = ns(dur(name))
    t = np.arange(n) / SR
    f0 = cyc(82, n)
    x = np.sin(TAU * f0 * t) + 0.35 * np.sin(TAU * 2 * f0 * t) + 0.12 * np.sin(TAU * 3 * f0 * t)
    x += 0.5 * np.sin(TAU * cyc(83, n) * t)
    x *= 0.85 + 0.15 * clfo(n, 4)
    x = unit(x) + 0.35 * cnoise(r, n, 250, 1600) * (0.7 + 0.3 * crand(r, n, 6))
    save_loop(name, x)

    # warp portal: a swirling vortex that accelerates, glittering shimmer, the exit's whump
    name = "warp_whoosh"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    rate = 3.0 + 16.0 * np.clip(t / 0.5, 0, 1) ** 1.5
    swirl_ph = TAU * np.cumsum(rate) / SR
    fc = glide(450, 4500, t, 0.5) * (1.0 + 0.45 * np.sin(swirl_ph))
    sw = unit(svf(r.standard_normal(n), fc, 4.0))
    sw *= np.minimum(t / 0.4, 1.0) ** 1.5 * np.exp(-np.maximum(t - 0.5, 0) / 0.12)
    shim = np.zeros(n)
    for j, m in enumerate((69, 76, 81, 88, 93)):
        f = ga.mtof(m) * glide(1.0, 2.0, t, 0.5) * (1.0 + 0.004 * (j - 2))
        shim += tone(f) * (0.6 + 0.4 * np.sin(TAU * (9 + j) * t))
    shim = unit(shim) * np.minimum(t / 0.45, 1.0) ** 2 * np.exp(-np.maximum(t - 0.5, 0) / 0.15)
    x = 0.8 * sw + 0.3 * shim
    place(x, 0.46, thud(tv(0.4), 95, 38, 0.1, 0.12, harm=(0.3,)), 0.9)
    place(x, 0.46, click(r, 0.1, 800, 8000, 0.005), 0.4)
    penta = (93, 95, 97, 100, 102, 105)
    for _ in range(16):
        tt = tv(0.2)
        place(x, r.uniform(0.45, 0.8), tone(ga.mtof(penta[int(r.integers(0, 6))]), tt) * env(tt, 0.002, 0.05),
              r.uniform(0.04, 0.1))
    save(name, x, fin=0.005, fout=0.15)

    name = "warp_hum"
    r = rng(name)
    n = ns(dur(name))
    t = np.arange(n) / SR
    drone = sum(a * np.sin(TAU * cyc(f, n) * t + r.uniform(0, TAU)) for f, a in
                ((55, 1.0), (110, 0.6), (110.5, 0.4), (165, 0.25), (220.5, 0.15)))
    drone *= 0.8 + 0.2 * clfo(n, 3)
    phase_band = unit(csvf(r.standard_normal(n), 1000 * 2.0 ** (0.9 * clfo(n, 1)), 5.0))
    shim = np.sin(TAU * cyc(880, n) * t) + np.sin(TAU * cyc(880.5, n) * t) + 0.6 * np.sin(TAU * cyc(1320, n) * t)
    x = unit(drone) + 0.3 * phase_band + 0.06 * shim
    save_loop(name, x)

    # a loose ball hitting the floor: a rubbery bonk with a hollow ring
    for i in range(1, 4):
        name = "prop_bonk_%d" % i
        r = rng(name)
        t = tv(dur(name))
        x = thud(t, r.uniform(160, 190), 105, 0.03, 0.03, harm=(0.25,))
        x += 0.5 * modes(t, [(r.uniform(330, 420), 1.0, 0.045), (r.uniform(780, 900), 0.4, 0.02)], r, 0.0)
        x += 0.5 * click(r, 0.3, 1000, 4500, 0.002) + 0.3 * noise(r, len(t), 200, 1200) * env(t, 0.002, 0.01)
        save(name, x, fin=0.0008, fout=0.08)

    # a collapsed platform grows back: a soft rising shimmer settling with a stony tap
    name = "platform_reform"
    r = rng(name)
    t = tv(dur(name))
    sh = unit(svf(r.standard_normal(len(t)), glide(900, 5000, t, 0.2), 4.0)) * env(t, 0.12, 0.05)
    tone_up = tone(glide(520, 1040, t, 0.2)) * env(t, 0.1, 0.08)
    x = 0.5 * sh + 0.25 * tone_up
    place(x, 0.2, thud(tv(0.2), 170, 95, 0.03, 0.025) + 0.4 * click(r, 0.2, 800, 5000, 0.002), 0.7)
    save(name, x, fin=0.01, fout=0.06)


# ===========================================================================
# map machines
# ===========================================================================
def gen_foundry():
    name = "ladle_tip"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    imp = np.zeros(n)
    pos = 0.0
    while pos < dur(name) - 0.1:
        imp[min(int(pos * SR), n - 1)] = r.uniform(0.4, 1.0)
        pos += 1.0 / (22.0 + 30.0 * np.sin(np.pi * pos / 0.7)) * r.uniform(0.85, 1.15)
    groan = fconv(imp, modes(tv(0.06), [(140, 1.0, 0.02), (330, 0.7, 0.012), (720, 0.4, 0.007)]))[:n]
    x = unit(groan) + 0.5 * noise(r, n, 40, 220) * np.sin(np.pi * np.clip(t / dur(name), 0, 1))
    for t0 in (0.05, 0.3 + r.uniform(0, 0.1), 0.55 + r.uniform(0, 0.1)):
        place(x, t0, modes(tv(0.2), bar_modes(r.uniform(850, 1000), 0.06), r, 0.02, hard=5000), 0.3)
    save(name, x, fin=0.01, fout=0.1)

    name = "ladle_pour"
    r = rng(name)
    n = ns(dur(name))
    roar = unit(tilt(cnoise(r, n, 55, 1400, 2), -3.0, circular=True)) * (0.65 + 0.35 * crand(r, n, 40, 0.4))
    glugs = np.zeros(n)
    for _ in range(26):
        cplace(glugs, r.uniform(0, dur(name)), bubble(r.uniform(70, 190), 0.12, r.uniform(0.02, 0.04), 0.4),
               r.uniform(0.3, 1.0))
    sizzle = np.zeros(n)
    grains(r, sizzle, 520, 0.0, dur(name), 3000, 11000, 0.0006, 0.002, 1.0, wrap=True)
    pops = np.zeros(n)
    grains(r, pops, 40, 0.0, dur(name), 700, 2500, 0.003, 0.008, 1.0, wrap=True)
    x = roar + 0.5 * unit(glugs) + 0.35 * unit(sizzle) + 0.3 * unit(pops)
    save_loop(name, x)

    name = "ladle_splash"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = noise(r, n, 40, 600) * env(t, 0.008, 0.15) + 0.9 * thud(t, 90, 40, 0.1, 0.12)
    s = np.zeros(n)
    grains(r, s, 160, 0.0, 0.5, 2500, 11000, 0.0006, 0.002, 1.0, decay=0.2)
    grains(r, s, 25, 0.02, 0.4, 600, 2200, 0.003, 0.008, 1.0, decay=0.15)
    x += 0.5 * unit(s)
    save(name, x, fin=0.002, fout=0.15)

    name = "ladle_hiss"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = noise(r, n, 1500, 9000) * env(t, 0.03, 0.35) * (0.8 + 0.2 * np.sin(TAU * 7 * t))
    c = np.zeros(n)
    grains(r, c, 120, 0.0, 0.9, 2500, 10000, 0.0006, 0.002, 1.0, decay=0.3)
    save(name, x + 0.3 * unit(c), fin=0.01, fout=0.3)


def gen_reef():
    for i in range(1, 3):
        name = "jelly_bounce_%d" % i
        r = rng(name)
        t = tv(dur(name))
        n = len(t)
        f = glide(r.uniform(150, 175), r.uniform(480, 560), t, 0.14) * \
            (1.0 + 0.07 * np.exp(-t / 0.15) * np.sin(TAU * 9 * t))
        bloop = (tone(f) + 0.3 * tone(2 * f) * np.exp(-t / 0.05)) * env(t, 0.006, 0.12)
        squish = noise(r, n, 100, 900) * env(t, 0.003, 0.03)
        x = bloop + 0.6 * squish
        for _ in range(9):
            place(x, r.uniform(0.02, 0.28), bubble(r.uniform(600, 1800), 0.06, r.uniform(0.008, 0.02)),
                  r.uniform(0.1, 0.3))
        save(name, band(x, None, 4200, 3), fin=0.002, fout=0.12)

    name = "vent_rumble"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = noise(r, n, 25, 170) * np.minimum(t / 0.6, 1.0) ** 1.5
    for _ in range(14):
        place(x, r.uniform(0.1, 0.72), bubble(r.uniform(150, 420), 0.08, r.uniform(0.015, 0.03)), r.uniform(0.2, 0.5))
    grains(r, x, 20, 0.2, 0.75, 500, 2000, 0.002, 0.006, 0.15)
    save(name, band(x, None, 3500, 3), fin=0.02, fout=0.08)

    name = "vent_burst"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = noise(r, n, 40, 500) * env(t, 0.01, 0.2) + 0.8 * thud(t, 85, 40, 0.1, 0.12)
    b = np.zeros(n)
    for _ in range(70):
        t0 = r.uniform(0.02, 0.75)
        place(b, t0, bubble(r.uniform(300, 2000), 0.06, r.uniform(0.006, 0.02)), r.uniform(0.2, 1.0) * np.exp(-t0 / 0.35))
    x += 0.6 * unit(b)
    save(name, band(x, None, 4500, 3), fin=0.003, fout=0.2)

    name = "vent_loop"
    r = rng(name)
    n = ns(dur(name))
    roar = cnoise(r, n, 30, 320) * (0.7 + 0.3 * crand(r, n, 8))
    hiss = cnoise(r, n, 500, 2500) * (0.6 + 0.4 * crand(r, n, 20))
    b = np.zeros(n)
    for _ in range(180):
        cplace(b, r.uniform(0, dur(name)), bubble(r.uniform(200, 1500), 0.06, r.uniform(0.006, 0.025)), r.uniform(0.2, 1.0))
    x = roar + 0.3 * hiss + 0.55 * unit(b)
    save_loop(name, cband(x, None, 4000, 3))

    name = "surge_loop"
    r = rng(name)
    n = ns(dur(name))
    rush = cnoise(r, n, 60, 900) * (0.75 + 0.25 * clfo(n, 3))
    swirl = unit(csvf(r.standard_normal(n), 380 * 2.0 ** (0.8 * crand(r, n, 4)), 2.5))
    b = np.zeros(n)
    for _ in range(30):
        cplace(b, r.uniform(0, dur(name)), bubble(r.uniform(350, 1300), 0.06, r.uniform(0.008, 0.02)), r.uniform(0.2, 1.0))
    x = rush + 0.6 * swirl + 0.25 * unit(b)
    save_loop(name, cband(x, None, 2800, 3))


def gen_orbital():
    name = "thruster_ignite"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = np.zeros(n)
    for t0 in (0.0, 0.03):
        place(x, t0, click(r, 0.02, 2000, 10000, 0.0015), 0.7)
    lit = np.maximum(t - 0.03, 0)
    wh = unit(tilt(noise(r, n, 45, 7000, 1), -2.0)) * np.minimum(lit / 0.02, 1.0) * (0.6 + 0.4 * np.exp(-lit / 0.08))
    x += wh + 0.9 * thud(t, 80, 38, 0.1, 0.12) + 0.4 * crackle(r, 0.5, 60, 1000, 6000, n=len(t))
    save(name, x, fin=0.0008, fout=0.15)

    name = "thruster_burn"
    r = rng(name)
    n = ns(dur(name))
    roar = unit(tilt(cnoise(r, n, 35, 9000, 1), -2.2, circular=True))
    formant = cnoise(r, n, 380, 950)
    rumble = cnoise(r, n, 28, 110) * (0.6 + 0.4 * crand(r, n, 30, 0.3))
    tear = 0.75 + 0.25 * crand(r, n, 45, 0.2)
    crk = crackle(r, dur(name), 300, 1000, 6000, wrap=True, n=n)
    x = roar * tear + 0.4 * formant + 0.6 * rumble + 0.5 * unit(crk)
    save_loop(name, x)

    for i in range(1, 4):
        name = "thruster_cough_%d" % i
        r = rng(name)
        t = tv(dur(name))
        x = noise(r, len(t), 100, 3000) * env(t, 0.002, 0.015) + 0.8 * thud(t, 95, 48, 0.03, 0.02)
        x += 0.4 * crackle(r, 0.06, 10, 1500, 7000, n=len(t))
        save(name, x, fin=0.0008, fout=0.04)

    name = "thruster_cutoff"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    tail = unit(svf(r.standard_normal(n), glide(6000, 250, t, 0.35), 0.8)) * env(t, 0.002, 0.15)
    x = tail + 0.4 * noise(r, n, 2500, 9000) * env(t, 0.03, 0.12) + 0.5 * thud(t, 70, 40, 0.08, 0.1)
    save(name, x, fin=0.002, fout=0.15)

    # flare: a klaxon beep in time with the gate's strobe, the launch, and the plasma wall itself
    name = "flare_alarm"
    t = tv(dur(name))
    f = 1150.0 * (1.0 + 0.02 * np.sin(TAU * 30 * t))
    x = sum(tone(f * k) / k for k in (1, 3, 5, 7)) + 0.4 * tone(f * 1.26)
    x *= np.minimum(t / 0.004, 1.0) * np.clip((0.14 - t) / 0.03, 0, 1)
    save(name, x, fin=0.001, fout=0.02)

    name = "flare_launch"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    rise = unit(svf(r.standard_normal(n), glide(200, 3200, t, 0.5), 1.2)) * np.minimum(t / 0.1, 1.0) * \
        np.exp(-np.maximum(t - 0.4, 0) / 0.35)
    x = rise + 1.0 * thud(t, 55, 28, 0.2, 0.3, harm=(0.4, 0.2)) + 0.45 * crackle(r, 0.8, 120, 1500, 9000, n=len(t))
    x += 0.35 * noise(r, n, 30, 120) * env(t, 0.05, 0.4)
    save(name, x, fin=0.002, fout=0.3)

    name = "flare_roar"
    r = rng(name)
    n = ns(dur(name))
    roar = unit(tilt(cnoise(r, n, 120, 11000, 1), -1.5, circular=True)) * (0.7 + 0.3 * crand(r, n, 60, 0.2))
    sizzle = cnoise(r, n, 6000, 12000) * (0.5 + 0.5 * crand(r, n, 80, 0.2)) ** 2
    rumble = cnoise(r, n, 35, 130) * (0.7 + 0.3 * crand(r, n, 10))
    crk = crackle(r, dur(name), 500, 1500, 9000, wrap=True, n=n)
    save_loop(name, roar + 0.35 * sizzle + 0.7 * rumble + 0.45 * unit(crk))

    # low-g bay: a floating field drone with a slow wub and a pale shimmer on top
    name = "gravity_hum"
    r = rng(name)
    n = ns(dur(name))
    t = np.arange(n) / SR
    drone = sum(a * np.sin(TAU * cyc(f, n) * t + r.uniform(0, TAU)) for f, a in
                ((55, 1.0), (55.5, 0.7), (82.5, 0.5), (110.5, 0.35), (165, 0.15)))
    wub = 0.7 + 0.3 * clfo(n, 3)
    shim = np.sin(TAU * cyc(1320, n) * t) + np.sin(TAU * cyc(1320.5, n) * t) + 0.7 * np.sin(TAU * cyc(1980, n) * t)
    air = unit(csvf(r.standard_normal(n), 600 * 2.0 ** (0.6 * clfo(n, 1, 1.0)), 6.0))
    save_loop(name, unit(drone) * wub + 0.05 * shim * (0.6 + 0.4 * clfo(n, 2)) + 0.15 * air)

    for name, up in (("gravity_on", True), ("gravity_off", False)):
        r = rng(name)
        t = tv(dur(name))
        n = len(t)
        k = np.clip(t / 0.45, 0, 1)
        ratio = (0.35 + 0.65 * k ** 0.7) if up else (1.0 - 0.7 * k ** 0.7)
        wub_rate = (3.0 + 5.0 * k) if up else (8.0 - 5.5 * k)
        wub = 0.6 + 0.4 * np.sin(TAU * np.cumsum(wub_rate) / SR)
        x = np.zeros(n)
        for f, a in ((55, 1.0), (82.5, 0.5), (110.5, 0.35), (220, 0.2), (1320, 0.05)):
            x += a * tone(f * ratio)
        shape = np.minimum(t / 0.3, 1.0) if up else np.exp(-t / 0.22)
        x = x * wub * shape * np.clip((0.6 - t) / 0.12, 0, 1)
        fc = glide(400, 2400, t, 0.4) if up else glide(2400, 300, t, 0.4)
        x += 0.3 * unit(svf(r.standard_normal(n), fc, 4.0)) * np.sin(np.pi * np.clip(t / 0.5, 0, 1))
        save(name, x, fin=0.004, fout=0.1)


def gen_clockwork():
    # an escapement tick / tock: the brass pawl, the pallet's heavy clunk, the train's ratchet,
    # and a brief whirr of gears while the pallet snaps
    for name, f_pawl, f_thud in (("escape_tick", 1900.0, 150.0), ("escape_tock", 1400.0, 105.0)):
        r = rng(name)
        t = tv(dur(name))
        n = len(t)
        x = 0.5 * modes(t, bar_modes(f_pawl, 0.045), r, 0.01, hard=9000) + 0.6 * click(r, 0.35, 2000, 9000, 0.0015)
        x += 1.0 * thud(t, f_thud, f_thud * 0.55, 0.05, 0.06)
        x += 0.5 * modes(t, [(f_thud * 2.2, 1.0, 0.03), (f_thud * 4.1, 0.6, 0.02), (f_thud * 7.3, 0.35, 0.012)], r, 0.02)
        for tj in (0.022, 0.041, 0.057):
            place(x, tj + r.uniform(-0.003, 0.003), modes(tv(0.03), bar_modes(f_pawl * 1.6, 0.008), r, 0.03), 0.15)
        whirr = np.zeros(n)
        tt = 0.01
        while tt < 0.3:
            place(whirr, tt, click(r, 0.01, 1500, 6000, 0.0008), r.uniform(0.5, 1.0))
            tt += 1.0 / 70.0
        x += 0.2 * whirr * np.exp(-t / 0.12)
        x = space(r, x, 0.9, 0.15, 200, 6000)
        save(name, x, fin=0.0008, fout=0.1)


def gen_balance():
    # scanner carriage servo: a whine with its gear hum, the rail's rumble and wheel clicks
    name = "scanner_servo"
    r = rng(name)
    n = ns(dur(name))
    t = np.arange(n) / SR
    f = cyc(420, n)
    whine = np.sin(TAU * f * t) + 0.5 * np.sin(TAU * 2 * f * t) + 0.2 * np.sin(TAU * 3 * f * t)
    gear = hum_stack(n, cyc(70, n), 10, 1.0, 1.0, r)
    rail = cnoise(r, n, 80, 600)
    clicks = np.zeros(n)
    for j in range(8):
        cplace(clicks, j * dur(name) / 8 + r.uniform(-0.005, 0.005), click(r, 0.02, 1200, 5000, 0.001), r.uniform(0.6, 1.0))
    save_loop(name, 0.4 * unit(whine) + 0.5 * gear + 0.5 * rail + 0.4 * unit(clicks))

    # crane trolley: motor whine and gear buzz, a rattling cable and chain, wheels rumbling
    name = "trolley_run"
    r = rng(name)
    n = ns(dur(name))
    t = np.arange(n) / SR
    f = cyc(300, n)
    whine = (np.sin(TAU * f * t) + 0.5 * np.sin(TAU * 2 * f * t) + 0.2 * np.sin(TAU * 4 * f * t)) * \
        (0.8 + 0.2 * np.sin(TAU * cyc(45, n) * t))
    chain = np.zeros(n)
    for _ in range(50):
        tk = tv(0.04)
        link = modes(tk, [(r.uniform(1800, 3800), 1.0, 0.01), (r.uniform(4500, 6500), 0.4, 0.005)], r, 0.0)
        cplace(chain, r.uniform(0, dur(name)), link, r.uniform(0.2, 1.0))
    rumble = cnoise(r, n, 50, 400) * (0.8 + 0.2 * crand(r, n, 18))
    save_loop(name, 0.35 * unit(whine) + 0.45 * unit(chain) + 0.7 * rumble)

    name = "trolley_clunk"
    r = rng(name)
    t = tv(dur(name))
    x = 0.5 * modes(t, plate_modes(180, 1.5, 0.15, 8, 0.6, r), r, 0.02, hard=3500) + 0.9 * thud(t, 110, 55, 0.05, 0.07)
    x += 0.7 * click(r, 0.6, 900, 6000, 0.002)
    for _ in range(7):
        place(x, r.uniform(0.02, 0.3), modes(tv(0.12), [(r.uniform(2000, 4500), 1.0, 0.03)], r, 0.0), r.uniform(0.05, 0.15))
    save(name, space(r, x, 0.8, 0.2), fin=0.0008, fout=0.12)

    # counterweight: chain links over the pulley, a faint wheel squeal, the frame's rumble
    name = "pulley_rattle"
    r = rng(name)
    n = ns(dur(name))
    links = np.zeros(n)
    for j in range(14):
        tk = tv(0.04)
        g = 1.0 if j % 2 == 0 else 0.55
        link = modes(tk, [(r.uniform(1600, 2400), 1.0, 0.012), (r.uniform(3200, 4200), 0.5, 0.006)], r, 0.0)
        cplace(links, j * dur(name) / 14 + r.uniform(-0.003, 0.003), link + 0.3 * click(r, 0.04, 800, 5000, 0.001), g)
    squeal = unit(csvf(r.standard_normal(n), cyc(1900, n) * (1 + 0.02 * crand(r, n, 3)), 30.0))
    rumble = cnoise(r, n, 60, 350)
    save_loop(name, unit(links) + 0.05 * squeal + 0.4 * rumble)

    name = "counterweight_thud"
    r = rng(name)
    t = tv(dur(name))
    x = 1.0 * thud(t, 95, 45, 0.08, 0.1) + 0.4 * modes(t, plate_modes(160, 1.2, 0.18, 8, 0.6, r), r, 0.02, hard=3000)
    x += 0.6 * click(r, 0.7, 700, 5000, 0.003)
    for _ in range(9):
        place(x, r.uniform(0.03, 0.35), modes(tv(0.1), [(r.uniform(1600, 3500), 1.0, 0.02)], r, 0.0), r.uniform(0.05, 0.18))
    save(name, space(r, x, 0.9, 0.2), fin=0.0008, fout=0.15)


def gen_gardens():
    # the trimmer: a buzzing laser-shear motor, the blades chattering, leaves being shredded
    name = "trimmer_buzz"
    r = rng(name)
    n = ns(dur(name))
    t = np.arange(n) / SR
    f0 = cyc(95, n)
    saw = buzz_wave(f0, n, 40, 1.0)
    chatter = 0.6 + 0.4 * (0.5 + 0.5 * np.sin(TAU * cyc(24, n) * t)) ** 2
    laser = cnoise(r, n, 3000, 9000) * (0.5 + 0.5 * np.sin(TAU * f0 * t)) ** 8
    leaves = np.zeros(n)
    grains(r, leaves, 260, 0.0, dur(name), 1500, 6500, 0.001, 0.004, 1.0, wrap=True)
    x = cband(saw, 60, 5000) * chatter + 0.35 * unit(laser) + 0.4 * unit(leaves)
    save_loop(name, x)


def gen_ascent():
    # the billboard: a neon transformer buzz with a high whine and irregular crackle
    name = "billboard_buzz"
    r = rng(name)
    n = ns(dur(name))
    t = np.arange(n) / SR
    f0 = cyc(120, n)
    b = cband(buzz_wave(f0, n, 30, 0.9, 0.3), 150, 4000)
    whine = np.sin(TAU * cyc(7800, n) * t)
    x = unit(b) * (0.85 + 0.15 * crand(r, n, 25, 0.3)) + 0.03 * whine + \
        0.35 * crackle(r, dur(name), 45, 2500, 9000, True, n)
    save_loop(name, x)

    def zap(r, dur, f0=120.0):
        tz = tv(dur)
        z = buzz_wave(f0, len(tz), 30, 0.9, 0.3) * np.minimum(tz / 0.002, 1) * np.clip((dur - tz) / 0.004, 0, 1)
        return z + 0.5 * noise(r, len(tz), 2500, 9000) * np.exp(-tz / 0.004)

    name = "billboard_on"
    r = rng(name)
    x = np.zeros(ns(0.45))
    for t0, d in ((0.0, 0.015), (0.05, 0.02), (0.09, 0.03), (0.16, 0.05)):
        place(x, t0, zap(r, d), 0.8)
    tt = tv(0.24)
    place(x, 0.21, buzz_wave(120, len(tt), 30, 0.9, 0.3) * env(tt, 0.003, 0.1) + 0.8 * thud(tt, 140, 80, 0.03, 0.03), 0.9)
    save(name, x, fin=0.0008, fout=0.08)

    name = "billboard_off"
    r = rng(name)
    t = tv(dur(name))
    f = glide(2200, 90, t, 0.22)
    x = 0.7 * (tone(f) + 0.3 * tone(2 * f)) * env(t, 0.002, 0.08) + 0.5 * crackle(r, 0.15, 20, n=len(t))
    place(x, 0.0, zap(r, 0.04), 0.8)
    place(x, 0.0, click(r, 0.05, 500, 6000, 0.003), 0.6)
    save(name, x, fin=0.0008, fout=0.08)

    for i in range(1, 4):
        name = "billboard_glitch_%d" % i
        r = rng(name)
        t = tv(dur(name))
        n = len(t)
        hold = int(r.uniform(0.005, 0.01) * SR)
        steps = np.repeat(r.uniform(200, 3500, n // hold + 1), hold)[:n]
        g = band(np.sign(np.sin(TAU * np.cumsum(steps) / SR)) * 0.5, None, 8000)
        crush = np.round(noise(r, n, 500, 8000) * 4) / 4
        x = (0.6 * g + 0.4 * crush) * np.minimum(t / 0.002, 1) * np.clip((0.11 - t) / 0.03, 0, 1)
        save(name, x, fin=0.0008, fout=0.02)

    # data stream: a packet spawns with a chirp of bleeps; one zipping past
    penta = (84, 86, 88, 91, 93, 96, 98, 100)
    for i in range(1, 5):
        name = "data_chirp_%d" % i
        r = rng(name)
        x = np.zeros(ns(0.16))
        start = int(r.integers(0, 4))
        direction = 1 if i % 2 else -1
        for j in range(int(r.integers(3, 5))):
            m = penta[(start + direction * j * int(r.integers(1, 3))) % len(penta)]
            tt = tv(0.05)
            f = ga.mtof(m)
            b = (tone(f, tt) + 0.25 * tone(3 * f, tt) + 0.12 * tone(5 * f, tt)) * env(tt, 0.001, 0.012)
            place(x, j * r.uniform(0.018, 0.026), b, 0.6)
        save(name, x, fin=0.0005, fout=0.03)
    for i in range(1, 3):
        name = "data_zip_%d" % i
        r = rng(name)
        t = tv(dur(name))
        f = glide(r.uniform(2600, 3200), r.uniform(500, 700), t, 0.18)
        z = (tone(f) + 0.3 * tone(2 * f)) * np.exp(-0.5 * ((t - 0.07) / 0.04) ** 2)
        w = whoosh(r, 0.25, 1500, 6000, 1200, 0.07, 0.03, 2.0)
        save(name, 0.5 * z + 0.6 * w, fin=0.002, fout=0.06)


# ===========================================================================
# verification
# ===========================================================================
def verify():
    ok = True
    total = 0
    print("verify:")
    for name, (want, loop) in CLIPS.items():
        path = os.path.join(OUT, name + ".wav")
        if not os.path.exists(path):
            print("  %-24s MISSING" % name)
            ok = False
            continue
        x, sr, sw = ga.read_wav(name)
        total += os.path.getsize(path)
        mono = x.shape[1] == 1
        x = x[:, 0]
        dur = len(x) / sr
        peak = ga.db(np.max(np.abs(x)))
        target = levelled_target(name)
        if target is None:
            level_ok = abs(peak - PEAK_DB) < 0.2
        else:
            # loudness-matched: on target, or held at the -3 dBFS peak when it can't get there
            level_ok = peak < PEAK_DB + 0.05 and (abs(loudness(x) - target) < 0.5 or abs(peak - PEAK_DB) < 0.2)
        good = (sr == SR and sw == 2 and mono and abs(dur - want) < 0.002 and level_ok and
                bool(np.all(np.isfinite(x))))
        if loop:
            # the step across the wrap must look like any other step, and so must the curvature
            steps = np.abs(np.diff(x))
            p999 = np.quantile(steps, 0.999)
            wrap = abs(x[0] - x[-1])
            c999 = np.quantile(np.abs(np.diff(x, n=2)), 0.999)
            seam_curv = np.max(np.abs(np.diff(np.concatenate([x[-3:], x[:3]]), n=2)))
            # and no dip or swell at the seam: the 40 ms window across the wrap must be as loud
            # as the windows elsewhere in the loop (a faded end would be the quietest by far)
            k = int(0.04 * sr)
            hop = int(0.01 * sr)
            xx = np.concatenate([x, x[:k]])
            rms = np.array([np.sqrt(np.mean(xx[i:i + k] ** 2)) for i in range(0, len(x), hop)])
            seam_rms = np.sqrt(np.mean(np.concatenate([x[-k // 2:], x[:k // 2]]) ** 2))
            lvl = ga.db(seam_rms) - ga.db(np.quantile(rms, 0.05))
            good = good and wrap <= p999 * 1.5 and seam_curv <= c999 * 1.5 and lvl > -3.0
            note = "loop: wrap %.4f (p99.9 %.4f) curv %.4f (p99.9 %.4f) seam %+.1f dB vs p5" % (
                wrap, p999, seam_curv, c999, lvl)
        else:
            edge = max(abs(x[0]), abs(x[-1]))
            good = good and edge < 0.002
            note = "edge %.5f" % edge
        ok &= bool(good)
        print("  %-24s %5.2f s peak %6.2f dB %s %s" % (name, dur, peak, note, "ok" if good else "FAIL"))
    print("  %d clips, total size %.2f MB %s" % (len(CLIPS), total / 1e6, "ok" if total < SIZE_BUDGET else "FAIL"))
    ok &= total < SIZE_BUDGET
    print("RESULT: " + ("ALL OK" if ok else "PROBLEMS FOUND"))
    return ok


GENERATORS = (gen_steps, gen_wall, gen_movement_loops, gen_lasers, gen_crusher_piston, gen_swings, gen_surfaces,
              gen_foundry, gen_reef, gen_orbital, gen_clockwork, gen_balance, gen_gardens, gen_ascent)


def main():
    args = sys.argv[1:]
    if "--verify" not in args:
        print("world effects -> audio/")
        for fn in GENERATORS:
            fn()
        missing = [n for n in CLIPS if n not in LOG]
        if missing:
            print("not generated: " + ", ".join(missing))
            sys.exit(1)
    sys.exit(0 if verify() else 1)


if __name__ == "__main__":
    main()
