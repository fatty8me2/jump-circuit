"""Jump Circuit music engine.

Instruments, a small score notation, and a circular mixer / mastering chain used by
tools/gen_music.py.  Everything is synthesised from maths and seeded noise: no samples,
sound fonts or third-party material.

Design notes
------------
* Rich sustained sources (strings, brass, reeds, choir, synths) are band-limited
  PolyBLEP oscillators shaped in the FFT domain by instrument "bodies" (formant bumps,
  brightness low-passes).  Brightness that follows loudness (brass) crossfades between a
  dark and a bright rendering of the same tone.
* Struck and plucked instruments (harp, guitar, pizzicato, harpsichord, piano, mallets,
  bells, music box) are additive: every partial has its own ratio, amplitude and decay,
  which is what gives them their character.
* Every note is normalised to a common sustained level, then scaled by velocity, so parts
  are balanced in the score rather than by trial and error.
* A Track is a set of circular stereo buffers: notes are mixed with their sample index
  taken modulo the loop length, and reverb (convolution with a synthesised room impulse),
  delay, chorus, side-chain pumping and the limiter are all circular too - so the loop point
  is seamless by construction.
* A Track has layers ("base" and optionally "hi"), rendered as separate files that the game
  plays locked together (AudioStreamSynchronized) and mixes by course progress.
"""
import os
import re
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_audio as ga  # noqa: E402

MSR = 32000
TAU = 2.0 * np.pi
NYQ = MSR / 2.0


def mtof(m):
    return 440.0 * 2.0 ** ((np.asarray(m, dtype=np.float64) - 69.0) / 12.0)


def rng_for(name):
    return ga.rng_for(name)


def secs(n):
    return np.arange(n) / MSR


def _smooth(n, primes=(2, 3, 5, 7, 11)):
    for p in primes:
        while n % p == 0:
            n //= p
    return n == 1


def nice_len(n0, tol=0.004):
    """The 11-smooth length closest to n0 within +-tol (relative); n0 itself if none."""
    span = int(n0 * tol)
    for d in range(0, span + 1):
        for n in (n0 + d, n0 - d):
            if n % 2 == 0 and _smooth(n):
                return n
    return n0


def fast_len(n):
    """Next length with only small prime factors (fast FFT)."""
    best = 1 << int(np.ceil(np.log2(max(n, 1))))
    for a in (1, 3, 5, 9, 15, 25, 27, 45, 75):
        for p in range(0, 40):
            v = a << p
            if v >= n:
                best = min(best, v)
                break
    return best


# --------------------------------------------------------------------------
# spectral helpers (gain curves over frequency arrays)
# --------------------------------------------------------------------------
def bump(f, fc, gain_db, width_oct=0.5):
    """Log-gaussian peak / dip."""
    x = np.log2(np.maximum(f, 1.0) / fc) / width_oct
    return 10.0 ** (gain_db / 20.0 * np.exp(-0.5 * x * x))


def lp(f, fc, order=2):
    return 1.0 / np.sqrt(1.0 + (np.maximum(f, 0.0) / fc) ** (2 * order))


def hp(f, fc, order=2):
    return 1.0 / np.sqrt(1.0 + (fc / np.maximum(f, 1e-3)) ** (2 * order))


def shelf(f, fc, gain_db):
    """Smooth high shelf (gain_db above fc)."""
    s = 1.0 / (1.0 + (fc / np.maximum(f, 1e-3)) ** 2)
    return 10.0 ** (gain_db / 20.0 * s)


def fft_shape(x, gain_fn, pad=0.04):
    """Filter a finite signal with a zero-phase spectral gain curve gain_fn(freqs)."""
    p = int(pad * MSR)
    n = len(x)
    m = fast_len(n + 2 * p)
    spec = np.fft.rfft(np.concatenate([np.zeros(p), x, np.zeros(m - n - p)]))
    f = np.fft.rfftfreq(m, 1.0 / MSR)
    return np.fft.irfft(spec * gain_fn(f), m)[p:p + n]


def circ_shape(x, gain_fn):
    """Same, but circular over the whole buffer (for loop stems). x: (n,) or (n, 2)."""
    n = len(x)
    f = np.fft.rfftfreq(n, 1.0 / MSR)
    g = gain_fn(f)
    if x.ndim == 1:
        return np.fft.irfft(np.fft.rfft(x) * g, n)
    return np.stack([np.fft.irfft(np.fft.rfft(x[:, c]) * g, n) for c in range(x.shape[1])], axis=1)


# --------------------------------------------------------------------------
# oscillators
# --------------------------------------------------------------------------
def _blep(ph, dt):
    y = np.zeros_like(ph)
    m = ph < dt
    t = ph[m] / dt[m]
    y[m] = t + t - t * t - 1.0
    m = ph > 1.0 - dt
    t = (ph[m] - 1.0) / dt[m]
    y[m] = t * t + t + t + 1.0
    return y


def saw(f, ph0=0.0):
    """PolyBLEP sawtooth driven by a per-sample frequency array."""
    dt = np.minimum(np.asarray(f, dtype=np.float64) / MSR, 0.49)
    ph = (ph0 + np.cumsum(dt)) % 1.0
    return 2.0 * ph - 1.0 - _blep(ph, dt)


def pulse(f, width=0.5, ph0=0.0):
    dt = np.minimum(np.asarray(f, dtype=np.float64) / MSR, 0.49)
    ph = (ph0 + np.cumsum(dt)) % 1.0
    ph2 = (ph + width) % 1.0
    a = 2.0 * ph - 1.0 - _blep(ph, dt)
    b = 2.0 * ph2 - 1.0 - _blep(ph2, dt)
    return 0.5 * (a - b)


def sine(f, ph0=0.0):
    return np.sin(TAU * np.cumsum(np.asarray(f, dtype=np.float64)) / MSR + ph0)


def drift(r, n, cents=3.0, rate=0.7):
    """Slow random pitch wander (ratio array)."""
    k = max(int(n * rate / MSR) + 3, 4)
    pts = r.normal(0.0, 1.0, k)
    x = np.interp(np.linspace(0, k - 1, n), np.arange(k), pts)
    return 2.0 ** (cents * x / 1200.0)


def vibrato(r, n, rate=5.3, depth=0.004, delay=0.25, ramp=0.35):
    t = secs(n)
    rate = rate * r.uniform(0.93, 1.07)
    onset = np.clip((t - delay) / max(ramp, 1e-3), 0.0, 1.0)
    return 1.0 + depth * onset * np.sin(TAU * rate * t + r.uniform(0, TAU))


def glide(n, f_from, f_to, secs_=0.06):
    """Portamento ratio curve from f_from to f_to (as multipliers of f_to)."""
    if f_from is None or f_from <= 0:
        return np.ones(n)
    t = secs(n)
    k = np.clip(t / secs_, 0.0, 1.0)
    k = k * k * (3 - 2 * k)
    return (f_from / f_to) ** (1.0 - k)


# --------------------------------------------------------------------------
# envelopes
# --------------------------------------------------------------------------
def env_asr(n, dur, att, rel, curve=1.0, swell=0.0):
    """Raised-cosine attack, (optional linear swell), raised-cosine release after `dur`."""
    t = secs(n)
    a = np.clip(t / max(att, 1e-4), 0.0, 1.0)
    a = (0.5 - 0.5 * np.cos(np.pi * a)) ** curve
    s = 1.0 + swell * np.clip(t / max(dur, 1e-3), 0.0, 1.0) - swell * 0.5
    rr = np.clip((t - dur) / max(rel, 1e-4), 0.0, 1.0)
    r = 0.5 + 0.5 * np.cos(np.pi * rr)
    return a * s * r


def env_perc(n, att, tau, dur=None, rel=0.05):
    t = secs(n)
    e = np.minimum(t / max(att, 1e-4), 1.0) * np.exp(-np.maximum(t - att, 0.0) / tau)
    if dur is not None:
        rr = np.clip((t - dur) / max(rel, 1e-4), 0.0, 1.0)
        e *= 0.5 + 0.5 * np.cos(np.pi * rr)
    return e


def tail_fade(x, secs_=0.01):
    k = min(int(secs_ * MSR), len(x))
    if k > 1:
        x[-k:] *= np.linspace(1.0, 0.0, k)[:, None] if x.ndim == 2 else np.linspace(1.0, 0.0, k)
    return x


def _level(x, target=0.3):
    rms = np.sqrt(np.mean(x ** 2)) + 1e-12
    return x * (target / rms)


def _level_head(x, target=0.3, head=0.15):
    """Normalise a decaying sound by the RMS of its first `head` seconds (so a long ring and a
    short one of the same note sit at the same level)."""
    k = max(min(int(head * MSR), len(x)), 1)
    rms = np.sqrt(np.mean(x[:k] ** 2)) + 1e-12
    return x * (target / rms)


def stereo(x, pan=0.0):
    a = (pan + 1.0) * np.pi / 4.0
    return x[:, None] * np.array([np.cos(a), np.sin(a)]) * np.sqrt(2.0)


def noise(r, n):
    return r.standard_normal(n)


# --------------------------------------------------------------------------
# bowed / blown / sung (subtractive: PolyBLEP source -> body)
# --------------------------------------------------------------------------
STRING_BODIES = {
    "violin": lambda f: bump(f, 290, 4, 0.35) * bump(f, 480, 2, 0.4) * bump(f, 1100, 3, 0.5) * bump(f, 2700, 5, 0.5)
    * bump(f, 1650, -3, 0.3),
    "viola": lambda f: bump(f, 230, 4, 0.35) * bump(f, 420, 2, 0.4) * bump(f, 950, 3, 0.5) * bump(f, 2300, 3, 0.5),
    "cello": lambda f: bump(f, 180, 4, 0.4) * bump(f, 330, 2, 0.4) * bump(f, 700, 3, 0.5) * bump(f, 1500, 2, 0.5),
    "bass": lambda f: bump(f, 90, 4, 0.5) * bump(f, 220, 2, 0.5) * bump(f, 600, 1, 0.6),
}


def strings(r, freq, dur, vel=0.8, att=0.14, rel=0.4, voices=4, bright=0.5, vib=0.0045, body=None,
            tremolo=0.0, swell=0.0, legato_from=None, spread=0.5, pan=0.0):
    """String section (or a solo with voices=1). Returns stereo."""
    n = int((dur + rel + 0.05) * MSR)
    if body is None:
        body = "violin" if freq > 380 else ("viola" if freq > 190 else ("cello" if freq > 70 else "bass"))
    out = np.zeros((n, 2))
    for v in range(voices):
        cents = r.normal(0.0, 5.0 if voices > 1 else 0.0)
        off = int(r.uniform(0.0, 0.022 if voices > 1 else 0.0) * MSR)
        m = n - off
        fcurve = freq * 2 ** (cents / 1200.0) * vibrato(r, m, 5.4, vib * r.uniform(0.7, 1.2), 0.18, 0.4) \
            * drift(r, m, 2.5 if voices > 1 else 1.5) * glide(m, legato_from, freq, 0.07)
        s = saw(fcurve, r.uniform())
        if tremolo:
            tt = secs(m)
            s *= 1.0 - tremolo * (0.5 + 0.5 * np.sin(TAU * r.uniform(11.0, 14.0) * tt + r.uniform(0, TAU)))
        p = pan + (spread * (v / max(voices - 1, 1) - 0.5) * 2.0 if voices > 1 else 0.0)
        out[off:] += stereo(s * r.uniform(0.85, 1.0), float(np.clip(p, -1, 1)))
    fc = 700.0 + 3600.0 * bright * (0.45 + 0.55 * vel)
    shape = lambda f: STRING_BODIES[body](f) * lp(f, fc, 2) * hp(f, freq * 0.7, 2)  # noqa: E731
    for c in range(2):
        out[:, c] = fft_shape(out[:, c], shape)
    out = _level(out, 0.3)
    # bow noise, stronger at the attack
    bn = fft_shape(noise(r, n), lambda f: hp(f, 2000, 2) * lp(f, 7000, 2))
    bn = bn / (np.max(np.abs(bn)) + 1e-9) * 0.05 * min(1.0, freq / 440.0) * (1.0 + 2.0 * np.exp(-secs(n) / 0.06))
    out += stereo(bn, pan) * 0.5
    e = env_asr(n, dur, att, rel, 1.0, swell) * (0.35 + 0.65 * vel)
    return tail_fade(out * e[:, None])


def solo_string(r, freq, dur, vel=0.8, legato_from=None, att=0.08, rel=0.25, bright=0.65, body=None, pan=0.0):
    """Expressive solo fiddle / cello: one voice, stronger vibrato, bow scratch at the start."""
    x = strings(r, freq, dur, vel, att, rel, voices=1, bright=bright, vib=0.0065, body=body,
                legato_from=legato_from, pan=pan)
    n = len(x)
    sc = fft_shape(noise(r, n), lambda f: bump(f, 3200, 10, 0.8) * hp(f, 900))
    sc = sc / (np.max(np.abs(sc)) + 1e-9) * 0.25 * np.exp(-secs(n) / 0.035) * vel
    if legato_from is None:
        x += stereo(sc, pan)
    return x


def brass(r, freq, dur, vel=0.8, kind="horn", att=None, rel=None, voices=1, pan=0.0, legato_from=None,
          spread=0.3, fp=False):
    """Horn / trumpet / trombone / tuba. Brightness follows the envelope (the brass 'blat')."""
    cfg = {  # formant, dark cutoff, bright cutoff, attack, release, vibrato
        "horn": (420.0, 500.0, 1700.0, 0.07, 0.3, 0.0025),
        "trumpet": (1300.0, 1000.0, 4500.0, 0.03, 0.18, 0.004),
        "trombone": (550.0, 600.0, 2600.0, 0.05, 0.22, 0.002),
        "tuba": (230.0, 260.0, 900.0, 0.06, 0.25, 0.0015),
    }[kind]
    form, dark_fc, bright_fc, a0, r0, vb = cfg
    att = a0 if att is None else att
    rel = r0 if rel is None else rel
    n = int((dur + rel + 0.05) * MSR)
    t = secs(n)
    src = np.zeros((n, 2))
    for v in range(voices):
        cents = r.normal(0.0, 4.0 if voices > 1 else 0.0)
        scoop = 1.0 - (0.012 + 0.01 * r.uniform()) * np.exp(-t / 0.035) if legato_from is None else 1.0
        fcurve = freq * 2 ** (cents / 1200.0) * scoop * vibrato(r, n, 5.0, vb, 0.35, 0.4) * drift(r, n, 2.0) \
            * glide(n, legato_from, freq, 0.05)
        p = pan + (spread * (v / max(voices - 1, 1) - 0.5) * 2.0 if voices > 1 else 0.0)
        src += stereo(saw(fcurve, r.uniform()), float(np.clip(p, -1, 1)))
    body = lambda f: bump(f, form, 5, 0.6) * hp(f, freq * 0.75, 2)  # noqa: E731
    dark = np.stack([fft_shape(src[:, c], lambda f: body(f) * lp(f, dark_fc, 2)) for c in range(2)], 1)
    brt = np.stack([fft_shape(src[:, c], lambda f: body(f) * lp(f, bright_fc * (0.7 + 0.5 * vel), 2)) for c in range(2)], 1)
    dark = _level(dark, 0.3)
    brt = _level(brt, 0.3)
    e = env_asr(n, dur, att, rel, 1.3)
    # attack overshoot; fp = fortepiano (hit then drop)
    over = 1.0 + (0.25 * vel) * np.exp(-np.maximum(t - att, 0) / 0.08) * (t > att * 0.5)
    if fp:
        over *= 0.45 + 0.55 * np.exp(-np.maximum(t - att, 0) / 0.12)
    amp = e * over * (0.3 + 0.7 * vel)
    w = np.clip(amp * vel ** 0.5, 0.0, 1.0) ** 1.4
    out = dark * (1.0 - w)[:, None] + brt * w[:, None]
    breath = fft_shape(noise(r, n), lambda f: bump(f, form * 3, 6, 1.0) * hp(f, 800))
    breath = breath / (np.max(np.abs(breath)) + 1e-9) * 0.03 * np.exp(-t / 0.05)
    out = out * amp[:, None] + stereo(breath, pan)
    return tail_fade(out)


def woodwind(r, freq, dur, vel=0.8, kind="flute", att=None, rel=None, legato_from=None, pan=0.0, vib=None):
    """Flute / piccolo / whistle / ocarina (additive + breath), clarinet (odd partials),
    oboe / bassoon (source-filter)."""
    n = int((dur + 0.3) * MSR)
    t = secs(n)
    presets = {
        #          partial amps                         breath  vib     att    rel
        "flute": ((1.0, 0.22, 0.1, 0.05, 0.025, 0.012), 0.10, 0.0055, 0.05, 0.12),
        "piccolo": ((1.0, 0.12, 0.05, 0.02), 0.08, 0.005, 0.03, 0.1),
        "whistle": ((1.0, 0.3, 0.12, 0.05, 0.02), 0.13, 0.004, 0.02, 0.06),
        "ocarina": ((1.0, 0.06, 0.03, 0.01), 0.07, 0.0045, 0.06, 0.12),
        "clarinet": ((1.0, 0.03, 0.6, 0.03, 0.35, 0.02, 0.2, 0.01, 0.1, 0.01, 0.05), 0.03, 0.002, 0.04, 0.1),
        "panflute": ((1.0, 0.1, 0.12, 0.02, 0.03), 0.22, 0.003, 0.06, 0.2),
    }
    if kind in ("oboe", "bassoon", "englishhorn"):
        return reed(r, freq, dur, vel, kind, legato_from=legato_from, pan=pan)
    amps, breath, vb, a0, r0 = presets[kind]
    vb = vb if vib is None else vib
    att = a0 if att is None else att
    rel = r0 if rel is None else rel
    fcurve = freq * vibrato(r, n, 5.1, vb, 0.2, 0.3) * drift(r, n, 1.5) * glide(n, legato_from, freq, 0.045)
    # a small pitch overshoot on tongued attacks
    if legato_from is None:
        fcurve = fcurve * (1.0 + 0.006 * np.exp(-t / 0.02))
    ph = TAU * np.cumsum(fcurve) / MSR
    x = np.zeros(n)
    bright = 0.6 + 0.6 * vel
    for k, a in enumerate(amps, start=1):
        if freq * k < NYQ * 0.9:
            x += a * bright ** (k - 1) * np.sin(k * ph + r.uniform(0, TAU))
    x = _level(x, 0.3)
    # breath: noise band-passed around the fundamental and a broad airy hiss
    nb = noise(r, n)
    tonal = fft_shape(nb, lambda f: bump(f, freq, 18, 0.12) * lp(f, freq * 3))
    tonal = tonal / (np.sqrt(np.mean(tonal ** 2)) + 1e-9) * 0.3
    air = fft_shape(noise(r, n), lambda f: hp(f, 1800) * lp(f, 9000))
    air = air / (np.sqrt(np.mean(air ** 2)) + 1e-9) * 0.3
    x = x + breath * (0.8 * tonal + 0.5 * air)
    if legato_from is None:
        chiff = fft_shape(noise(r, n), lambda f: bump(f, freq * 2.2, 10, 0.7) * hp(f, 500))
        chiff = chiff / (np.max(np.abs(chiff)) + 1e-9) * 0.35 * np.exp(-t / 0.018) * vel
        x += chiff
    e = env_asr(n, dur, att, rel, 1.0) * (0.35 + 0.65 * vel)
    return tail_fade(stereo(x * e, pan))


def reed(r, freq, dur, vel=0.8, kind="oboe", legato_from=None, pan=0.0):
    form = {"oboe": ((1100, 9, 0.4), (2900, 6, 0.35)), "englishhorn": ((850, 8, 0.4), (2400, 5, 0.4)),
            "bassoon": ((450, 8, 0.4), (1150, 6, 0.4))}[kind]
    n = int((dur + 0.3) * MSR)
    t = secs(n)
    fcurve = freq * vibrato(r, n, 5.0, 0.004, 0.25, 0.3) * drift(r, n, 1.5) * glide(n, legato_from, freq, 0.05)
    s = pulse(fcurve, 0.38, r.uniform())
    body = lambda f: bump(f, form[0][0], form[0][1], form[0][2]) * bump(f, form[1][0], form[1][1], form[1][2]) \
        * lp(f, 5500, 2) * hp(f, freq * 0.8)  # noqa: E731
    x = _level(fft_shape(s, body), 0.3)
    e = env_asr(n, dur, 0.035, 0.1, 1.0) * (0.35 + 0.65 * vel)
    return tail_fade(stereo(x * e, pan))


VOWELS = {  # formant (freq, gain dB, width oct) sets
    "a": ((800, 12, 0.22), (1150, 9, 0.2), (2900, 5, 0.18), (3900, 3, 0.18)),
    "o": ((450, 12, 0.22), (800, 9, 0.2), (2830, 3, 0.18), (3800, 2, 0.18)),
    "u": ((325, 12, 0.22), (700, 6, 0.2), (2530, 2, 0.18), (3500, 1, 0.18)),
    "e": ((400, 12, 0.22), (1600, 8, 0.18), (2700, 6, 0.18), (3300, 4, 0.18)),
    "m": ((260, 12, 0.3), (1000, -6, 0.5), (2200, -6, 0.5), (3000, -8, 0.5)),  # humming
}


def choir(r, freq, dur, vel=0.7, vowel="a", voices=6, att=0.35, rel=0.8, male=None, pan=0.0, spread=0.6):
    """Choir section: detuned, individually vibrating voices through vowel formants."""
    n = int((dur + rel + 0.05) * MSR)
    male = freq < 260 if male is None else male
    shift = 0.82 if male else 1.0
    out = np.zeros((n, 2))
    for v in range(voices):
        cents = r.normal(0.0, 9.0)
        off = int(r.uniform(0.0, 0.05) * MSR)
        m = n - off
        fcurve = freq * 2 ** (cents / 1200.0) * vibrato(r, m, r.uniform(4.6, 5.8), r.uniform(0.004, 0.008), 0.15, 0.5) \
            * drift(r, m, 4.0, 1.2)
        p = pan + spread * (v / max(voices - 1, 1) - 0.5) * 2.0
        out[off:] += stereo(saw(fcurve, r.uniform()) * r.uniform(0.8, 1.0), float(np.clip(p, -1, 1)))
    fm = VOWELS[vowel]
    shape = lambda f: np.prod([bump(f, a * shift, g, w) for a, g, w in fm], axis=0) * lp(f, 4500, 2) \
        * hp(f, freq * 0.8, 2) * 0.1  # noqa: E731
    for c in range(2):
        out[:, c] = fft_shape(out[:, c], shape)
    out = _level(out, 0.3)
    br = fft_shape(noise(r, n), lambda f: np.prod([bump(f, a * shift, g, w * 1.5) for a, g, w in fm], axis=0) * hp(f, 300))
    br = br / (np.sqrt(np.mean(br ** 2)) + 1e-9) * 0.018
    out += stereo(br, pan)
    e = env_asr(n, dur, att, rel, 1.0) * (0.35 + 0.65 * vel)
    return tail_fade(out * e[:, None])


def accordion(r, freq, dur, vel=0.8, musette=True, low_reed=False, pan=0.0, att=0.025, rel=0.08):
    n = int((dur + rel + 0.05) * MSR)
    t = secs(n)
    bellows = 1.0 + 0.04 * np.sin(TAU * 0.9 * t + r.uniform(0, TAU))
    x = np.zeros(n)
    reeds = [(0.0, 1.0)]
    if musette:
        reeds += [(9.0, 0.8), (-7.0, 0.5)]
    if low_reed:
        reeds += [(-1200.0, 0.5)]
    for cents, a in reeds:
        x += a * pulse(freq * 2 ** (cents / 1200.0) * drift(r, n, 1.0), 0.28, r.uniform())
    x = fft_shape(x, lambda f: bump(f, 1500, 6, 0.8) * bump(f, 3000, 3, 0.5) * lp(f, 6000) * hp(f, freq * 0.6))
    x = _level(x, 0.3) * bellows
    e = env_asr(n, dur, att, rel, 1.0) * (0.35 + 0.65 * vel)
    return tail_fade(stereo(x * e, pan))


def organ(r, freq, dur, vel=0.8, stops=(1.0, 0.6, 0.35, 0.0, 0.2), pan=0.0, att=0.02, rel=0.12, leslie=True):
    """Drawbar-ish tonewheel organ (8', 4', 2 2/3', 2', 1 3/5' ...)."""
    n = int((dur + rel + 0.05) * MSR)
    t = secs(n)
    ratios = (1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 8.0)
    x = np.zeros(n)
    for ratio, a in zip(ratios, stops):
        if a and freq * ratio < NYQ * 0.9:
            x += a * np.sin(TAU * freq * ratio * t + r.uniform(0, TAU))
    x = _level(x, 0.3)
    if leslie:
        lf = 1.0 + 0.12 * np.sin(TAU * 6.3 * t)
        out = np.stack([x * lf, x * (2.0 - lf)], 1)
    else:
        out = stereo(x, pan)
    click = np.exp(-t / 0.004) * noise(r, n) * 0.05
    out += stereo(click, pan)
    e = env_asr(n, dur, att, rel) * (0.35 + 0.65 * vel)
    return tail_fade(out * e[:, None])


# --------------------------------------------------------------------------
# plucked / struck (additive, per-partial decays)
# --------------------------------------------------------------------------
def partials_tone(r, freq, n, ratios, amps, taus, att=0.002, detune=0.0, phase_rand=True):
    t = secs(n)
    x = np.zeros(n)
    for ratio, a, tau in zip(ratios, amps, taus):
        f = freq * ratio
        if f >= NYQ * 0.92 or a <= 0:
            continue
        ph = r.uniform(0, TAU) if phase_rand else 0.0
        comp = np.sin(TAU * f * t + ph)
        if detune:
            comp = 0.5 * comp + 0.5 * np.sin(TAU * f * (1.0 + detune) * t + r.uniform(0, TAU))
        x += a * comp * np.exp(-t / max(tau, 1e-4))
    return x * np.minimum(t / max(att, 1e-5), 1.0)


def plucked(r, freq, dur, vel=0.8, pos=0.25, t1=1.2, k_max=24, inharm=5e-5, decay_pow=0.9,
            body=None, damp=0.08, pick=0.08, bright=1.0, ring=False, detune=0.0):
    """Generic plucked string: pluck-position comb, per-harmonic decay, optional body EQ."""
    n = int(((dur + damp) if not ring else max(dur, t1 * 3)) * MSR) + int(0.05 * MSR)
    k = np.arange(1, k_max + 1)
    ratios = k * np.sqrt(1.0 + inharm * k * k)
    amps = np.abs(np.sin(np.pi * k * pos)) / k ** (1.0 + 0.6 * (1.0 - bright * vel))
    taus = t1 / (1.0 + 0.35 * (k - 1) ** decay_pow)
    x = partials_tone(r, freq, n, ratios, amps, taus, 0.0015, detune)
    if body is not None:
        x = fft_shape(x, body)
    t = secs(n)
    nz = fft_shape(noise(r, n), lambda f: hp(f, 1500) * lp(f, 9000))
    x = _level_head(x, 0.3) + pick * vel * nz / (np.max(np.abs(nz)) + 1e-9) * np.exp(-t / 0.005)
    if not ring:
        rr = np.clip((t - dur) / max(damp, 1e-3), 0.0, 1.0)
        x *= 0.5 + 0.5 * np.cos(np.pi * rr)
    return tail_fade(x * (0.3 + 0.7 * vel), 0.02)


def harp(r, freq, dur, vel=0.8, pan=0.0):
    t1 = float(np.clip(2.6 * (261.6 / freq) ** 0.45, 0.8, 5.0))
    x = plucked(r, freq, dur, vel, pos=0.28, t1=t1, k_max=18, inharm=1e-4, ring=True, pick=0.03,
                body=lambda f: bump(f, 250, 3, 0.8) * lp(f, 6000))
    return stereo(x, pan)


def guitar(r, freq, dur, vel=0.8, pan=0.0, steel=False, palm=False):
    t1 = float(np.clip(1.8 * (196.0 / freq) ** 0.5, 0.5, 3.5)) * (0.25 if palm else 1.0)
    body = (lambda f: bump(f, 105, 5, 0.3) * bump(f, 220, 4, 0.35) * bump(f, 420, 2, 0.4) * lp(f, 7000 if steel else 4200)
            * bump(f, 2800, 3 if steel else -2, 0.6))
    x = plucked(r, freq, dur, vel, pos=0.13 if steel else 0.2, t1=t1, k_max=28 if steel else 20, inharm=6e-5,
                body=body, pick=0.12 if steel else 0.06, damp=0.1, detune=0.0007 if steel else 0.0)
    return stereo(x, pan)


def pizz(r, freq, dur=0.3, vel=0.8, pan=0.0, section=3):
    body = "violin" if freq > 380 else ("viola" if freq > 190 else ("cello" if freq > 70 else "bass"))
    t1 = float(np.clip(0.55 * (196.0 / freq) ** 0.35, 0.18, 1.0))
    out = None
    for s in range(section):
        x = plucked(r, freq * 2 ** (r.normal(0, 4) / 1200), dur, vel, pos=0.3, t1=t1, k_max=14, inharm=1e-4, ring=True,
                    body=lambda f: STRING_BODIES[body](f) * lp(f, 3500), pick=0.05)
        off = int(r.uniform(0, 0.015) * MSR) if s else 0
        x = np.concatenate([np.zeros(off), x])
        y = stereo(x, float(np.clip(pan + r.uniform(-0.3, 0.3), -1, 1)))
        out = y if out is None else _addpad(out, y)
    return out / np.sqrt(section)


def _addpad(a, b):
    if len(a) < len(b):
        a, b = b, a
    a = a.copy()
    a[:len(b)] += b
    return a


def upright(r, freq, dur, vel=0.8, pan=0.0):
    x = plucked(r, freq, dur, vel, pos=0.3, t1=float(np.clip(1.4 * (55.0 / freq) ** 0.3, 0.6, 2.0)), k_max=12,
                inharm=2e-4, body=lambda f: bump(f, 90, 5, 0.5) * bump(f, 180, 3, 0.4) * lp(f, 1800), pick=0.06, damp=0.07)
    t = secs(len(x))
    thump = np.sin(TAU * freq * 0.5 * t) * np.exp(-t / 0.05) * 0.2
    return stereo(x + thump * (0.3 + 0.7 * vel), pan)


def harpsichord(r, freq, dur, vel=0.8, pan=0.0):
    t1 = float(np.clip(2.2 * (261.6 / freq) ** 0.4, 0.6, 4.0))
    a = plucked(r, freq, dur, 0.9, pos=0.09, t1=t1, k_max=40, inharm=3e-5, decay_pow=0.7, damp=0.05, pick=0.12,
                bright=1.0, body=lambda f: bump(f, 2500, 3, 0.6) * hp(f, 80))
    b = plucked(r, freq * 2.0, dur, 0.9, pos=0.12, t1=t1 * 0.7, k_max=24, inharm=3e-5, decay_pow=0.7, damp=0.05,
                pick=0.05, bright=1.0)
    x = _addpad(a, 0.35 * b)
    # jack thunk when the damper returns
    n = len(x)
    t = secs(n)
    thunk = fft_shape(noise(r, n), lambda f: bump(f, 900, 8, 0.8)) * np.exp(-np.maximum(t - dur, 0) / 0.01) * (t >= dur)
    x = x + 0.02 * thunk / (np.max(np.abs(thunk)) + 1e-9)
    return stereo(x, pan)


def piano(r, freq, dur, vel=0.7, pan=0.0, pedal=False):
    """Two-string additive piano: inharmonic partials, two-stage decay, hammer knock, damper."""
    ring = 2.5 + 5.0 * (261.6 / freq) ** 0.6
    n = int((min(dur, ring) + (0.2 if not pedal else 1.5)) * MSR)
    t = secs(n)
    B = 4e-4 * (freq / 261.6) ** 0.5
    k = np.arange(1, 31)
    k = k[freq * k < NYQ * 0.9]
    x = np.zeros(n)
    bright = 0.35 + 0.65 * vel
    for kk in k:
        fk = freq * kk * np.sqrt(1.0 + B * kk * kk)
        a = abs(np.sin(np.pi * kk / 7.3)) / kk ** (1.4 - 0.6 * bright)
        tau1 = 0.5 * ring / (1.0 + 0.3 * kk)
        tau2 = 1.6 * ring / (1.0 + 0.12 * kk)
        dec = 0.65 * np.exp(-t / tau1) + 0.35 * np.exp(-t / tau2)
        beat = 1.0 + 0.0006 * r.uniform(0.4, 1.2)
        comp = np.sin(TAU * fk * t + r.uniform(0, TAU)) + np.sin(TAU * fk * beat * t + r.uniform(0, TAU))
        x += a * dec * comp
    x = fft_shape(x, lambda f: lp(f, 2000 + 6000 * bright) * bump(f, 180, 2, 0.6))
    x = _level_head(x, 0.3)
    knock = fft_shape(noise(r, n), lambda f: lp(f, 1200) * hp(f, 60)) * np.exp(-t / 0.015)
    x += 0.4 * vel * knock / (np.max(np.abs(knock)) + 1e-9)
    x *= np.minimum(t / 0.002, 1.0)
    if not pedal:
        rr = np.clip((t - dur) / 0.12, 0.0, 1.0)
        x *= 0.5 + 0.5 * np.cos(np.pi * rr)
    return tail_fade(stereo(x * (0.25 + 0.75 * vel), pan), 0.02)


def mallet(r, freq, dur, vel=0.8, kind="marimba", pan=0.0):
    """Struck bars and tines: marimba, xylophone, vibraphone, glockenspiel, celesta, musicbox,
    kalimba. dur only matters for the vibraphone's damper."""
    s = (261.6 / freq) ** 0.5
    cfg = {  # ratios, amps, taus (s), attack, mallet noise, ring length
        "marimba": ((1.0, 3.93, 9.87), (1.0, 0.3, 0.1), (0.9 * s, 0.12 * s, 0.04), 0.002, 0.08, 1.6),
        "xylophone": ((1.0, 3.0, 6.0, 9.9), (1.0, 0.45, 0.2, 0.1), (0.35 * s, 0.1, 0.05, 0.03), 0.001, 0.2, 0.8),
        "vibraphone": ((1.0, 3.99, 10.1), (1.0, 0.25, 0.05), (3.0 * s, 0.5, 0.1), 0.002, 0.05, 4.0),
        "glockenspiel": ((1.0, 2.76, 5.40, 8.93), (1.0, 0.4, 0.2, 0.08), (2.4, 0.7, 0.3, 0.12), 0.0008, 0.15, 3.0),
        "celesta": ((1.0, 2.0, 4.0, 10.0), (1.0, 0.08, 0.28, 0.04), (1.4, 0.5, 0.25, 0.06), 0.002, 0.04, 2.0),
        "musicbox": ((1.0, 5.93, 16.6), (1.0, 0.22, 0.07), (2.0 * s, 0.25, 0.07), 0.0008, 0.1, 2.6),
        "kalimba": ((1.0, 5.4, 12.1), (1.0, 0.18, 0.05), (1.2 * s, 0.1, 0.04), 0.001, 0.06, 1.8),
    }[kind]
    ratios, amps, taus, att, mn, ring = cfg
    n = int((max(dur, ring) + 0.05) * MSR) if kind != "vibraphone" else int((min(dur + 0.4, ring)) * MSR)
    t = secs(n)
    x = partials_tone(r, freq, n, ratios, amps, taus, att, detune=0.0008 if kind == "musicbox" else 0.0)
    x = _level_head(x, 0.3)
    if kind == "vibraphone":
        x *= 1.0 - 0.35 * (0.5 + 0.5 * np.sin(TAU * 5.5 * t + r.uniform(0, TAU)))
        rr = np.clip((t - dur) / 0.3, 0.0, 1.0)
        x *= 0.5 + 0.5 * np.cos(np.pi * rr)
    lo, hi = (1500.0, 9000.0) if kind in ("glockenspiel", "musicbox", "xylophone") else (200.0, 2500.0)
    nz = fft_shape(noise(r, n), lambda f: hp(f, lo) * lp(f, hi))
    x += mn * vel * nz / (np.max(np.abs(nz)) + 1e-9) * np.exp(-t / 0.004)
    return tail_fade(stereo(x * (0.3 + 0.7 * vel), pan), 0.02)


def bell(r, freq, dur=4.0, vel=0.8, pan=0.0, kind="tubular"):
    """Church / tubular bell partial sets (hum, prime, tierce, quint, nominal ...)."""
    if kind == "tubular":  # a slightly inharmonic chime
        ratios = (1.0, 2.0, 3.0, 4.2, 5.4, 6.8)
        amps = (1.0, 0.5, 0.18, 0.25, 0.12, 0.06)
        taus = (4.0, 2.6, 1.6, 1.2, 0.7, 0.4)
    else:  # church: hum, prime, tierce, quint, nominal ...
        ratios = (0.5, 1.0, 1.183, 1.506, 2.0, 2.514, 2.662, 3.011, 4.166)
        amps = (0.35, 1.0, 0.6, 0.3, 0.7, 0.25, 0.2, 0.18, 0.1)
        taus = (6.0, 3.5, 3.0, 2.2, 2.0, 1.2, 1.0, 0.9, 0.6)
    base = freq
    s = (523.0 / freq) ** 0.4
    n = int(max(dur, 3.0 * s) * MSR)
    t = secs(n)
    x = partials_tone(r, base, n, ratios, amps, [q * s for q in taus], 0.001, detune=0.0015)
    x = _level_head(x, 0.3)
    nz = fft_shape(noise(r, n), lambda f: hp(f, 2000) * lp(f, 8000))
    x += 0.2 * vel * nz / (np.max(np.abs(nz)) + 1e-9) * np.exp(-t / 0.003)
    return tail_fade(stereo(x * (0.3 + 0.7 * vel), pan), 0.05)


def epiano(r, freq, dur, vel=0.7, pan=0.0, trem=0.25):
    """FM electric piano (tine + tone bar): 1:1 modulator with decaying index, a bell-y tine."""
    ring = 1.8 + 3.0 * (261.6 / freq) ** 0.6
    n = int((min(dur, ring) + 0.25) * MSR)
    t = secs(n)
    idx = (0.6 + 1.6 * vel) * np.exp(-t / 0.25) + 0.25
    phm = TAU * freq * t + r.uniform(0, TAU)
    x = np.sin(TAU * freq * t + idx * np.sin(phm))
    x *= 0.7 * np.exp(-t / (0.35 * ring)) + 0.3 * np.exp(-t / ring)
    tine = np.sin(TAU * freq * 7.1 * t) * np.exp(-t / 0.03) * 0.25 * vel
    x = _level_head(x, 0.3) + tine
    rr = np.clip((t - dur) / 0.12, 0.0, 1.0)
    x *= (0.5 + 0.5 * np.cos(np.pi * rr)) * np.minimum(t / 0.002, 1.0)
    lfo = trem * np.sin(TAU * 4.2 * t + r.uniform(0, TAU))
    out = np.stack([x * (1.0 + lfo), x * (1.0 - lfo)], 1) * (0.3 + 0.7 * vel)
    return tail_fade(out, 0.02)


def fm_bell(r, freq, dur=3.0, vel=0.7, pan=0.0, ratio=3.5, index=2.5, tau=1.2):
    n = int(max(dur, tau * 3) * MSR)
    t = secs(n)
    idx = index * vel * np.exp(-t / (tau * 0.4))
    x = np.sin(TAU * freq * t + idx * np.sin(TAU * freq * ratio * t)) * np.exp(-t / tau)
    x += 0.3 * np.sin(TAU * freq * 2.001 * t) * np.exp(-t / (tau * 0.5))
    x = _level_head(x, 0.3) * np.minimum(t / 0.002, 1.0)
    return tail_fade(stereo(x * (0.3 + 0.7 * vel), pan), 0.05)


# --------------------------------------------------------------------------
# synths
# --------------------------------------------------------------------------
def _sweep_filter(src, cut):
    """Time-varying low-pass by interpolating a bank of statically filtered copies (log-spaced
    cutoffs). `cut` is a per-sample cutoff array (Hz)."""
    bank_f = 120.0 * 2.0 ** np.arange(0, 8, 0.75)
    bank_f = bank_f[bank_f < NYQ]
    copies = [fft_shape(src, lambda f, fc=fc: lp(f, fc, 2) * bump(f, fc, 3.0, 0.25)) for fc in bank_f]
    pos = np.interp(np.log2(np.clip(cut, bank_f[0], bank_f[-1])), np.log2(bank_f), np.arange(len(bank_f)))
    i0 = np.floor(pos).astype(int)
    i1 = np.minimum(i0 + 1, len(bank_f) - 1)
    w = pos - i0
    stack = np.stack(copies, 0)
    idx = np.arange(len(src))
    return stack[i0, idx] * (1.0 - w) + stack[i1, idx] * w


def supersaw(r, freq, dur, vel=0.8, voices=7, detune=22.0, cutoff=3500.0, att=0.01, rel=0.3, sub=0.3, pan=0.0,
             spread=0.8, env_cut=None, width=None):
    n = int((dur + rel + 0.05) * MSR)
    t = secs(n)
    out = np.zeros((n, 2))
    for v in range(voices):
        c = detune * (v / max(voices - 1, 1) - 0.5) * 2.0
        f = freq * 2 ** (c / 1200.0) * drift(r, n, 1.0)
        s = saw(f, r.uniform()) if width is None else pulse(f, width, r.uniform())
        p = pan + spread * (v / max(voices - 1, 1) - 0.5) * 2.0
        out += stereo(s, float(np.clip(p, -1, 1)))
    if sub:
        out += stereo(np.sin(TAU * freq * 0.5 * t) * sub * voices * 0.5, pan)
    if env_cut is None:
        for c in range(2):
            out[:, c] = fft_shape(out[:, c], lambda f: lp(f, cutoff, 2) * hp(f, 40))
    else:
        cut = env_cut(t)
        for c in range(2):
            out[:, c] = _sweep_filter(out[:, c], cut)
    out = _level(out, 0.3)
    e = env_asr(n, dur, att, rel) * (0.35 + 0.65 * vel)
    return tail_fade(out * e[:, None])


def synth_pluck(r, freq, dur, vel=0.8, cutoff=5000.0, decay=0.18, wave="saw", pan=0.0, detune=8.0):
    n = int((dur + 0.15) * MSR)
    t = secs(n)
    s = np.zeros(n)
    for c in (-detune, detune):
        f = np.full(n, freq * 2 ** (c / 1200.0))
        s += saw(f, r.uniform()) if wave == "saw" else pulse(f, 0.5 if wave == "square" else 0.25, r.uniform())
    cut = 150.0 + cutoff * vel * np.exp(-t / decay)
    x = _level(_sweep_filter(s, cut), 0.3)
    e = env_perc(n, 0.002, decay * 2.5, dur, 0.06)
    return tail_fade(stereo(x * e * (0.3 + 0.7 * vel), pan))


def synth_lead(r, freq, dur, vel=0.8, wave="square", legato_from=None, cutoff=4000.0, pan=0.0, vib=0.006, att=0.01, rel=0.12):
    n = int((dur + rel + 0.05) * MSR)
    fcurve = freq * vibrato(r, n, 5.6, vib, 0.25, 0.3) * glide(n, legato_from, freq, 0.06)
    s = pulse(fcurve, 0.5 if wave == "square" else 0.3, r.uniform()) if wave != "saw" else saw(fcurve, r.uniform())
    s = s + 0.5 * (saw(fcurve * 1.004, r.uniform()) if wave == "saw" else 0)
    x = _level(fft_shape(s, lambda f: lp(f, cutoff, 2) * hp(f, 80)), 0.3)
    e = env_asr(n, dur, att, rel) * (0.35 + 0.65 * vel)
    return tail_fade(stereo(x * e, pan))


def sub_bass(r, freq, dur, vel=0.8, drive=1.6, att=0.006, rel=0.06, pan=0.0, harm=0.25):
    n = int((dur + rel + 0.03) * MSR)
    t = secs(n)
    x = np.sin(TAU * freq * t) + harm * np.sin(TAU * 2 * freq * t + 0.3)
    x = np.tanh(drive * x) / np.tanh(drive)
    x = _level(x, 0.3) * env_asr(n, dur, att, rel) * (0.35 + 0.65 * vel)
    return tail_fade(stereo(x, pan))


def synth_bass(r, freq, dur, vel=0.8, cutoff=900.0, decay=0.12, pan=0.0, detune=7.0, drive=1.5):
    n = int((dur + 0.08) * MSR)
    t = secs(n)
    s = saw(np.full(n, freq * 2 ** (detune / 1200)), r.uniform()) + saw(np.full(n, freq * 2 ** (-detune / 1200)), r.uniform())
    cut = 120.0 + cutoff * (0.4 + 0.6 * vel) * (0.35 + 0.65 * np.exp(-t / decay))
    x = _sweep_filter(s, cut) + 0.8 * np.sin(TAU * freq * t)
    x = np.tanh(drive * _level(x, 0.3) * 3.0) / 3.0
    x = _level(x, 0.3) * env_asr(n, dur, 0.003, 0.05)
    return tail_fade(stereo(x * (0.35 + 0.65 * vel), pan))


def pad_warm(r, freq, dur, vel=0.7, att=1.2, rel=2.0, cutoff=1400.0, pan=0.0, spread=0.7):
    return supersaw(r, freq, dur, vel, voices=4, detune=14.0, cutoff=cutoff, att=att, rel=rel, sub=0.0, pan=pan,
                    spread=spread)


def pad_glass(r, freq, dur, vel=0.7, att=1.5, rel=2.5, pan=0.0, shimmer=True):
    """Airy sine pad with an octave shimmer and slow beating (for water / space)."""
    n = int((dur + rel + 0.05) * MSR)
    t = secs(n)
    L = np.zeros(n)
    R = np.zeros(n)
    for ratio, a in ((1.0, 1.0), (2.0, 0.35), (3.0, 0.08), (4.0, 0.12 if shimmer else 0.0)):
        if not a or freq * ratio > NYQ * 0.9:
            continue
        for side, c in ((0, -4.0), (1, 4.0)):
            f = freq * ratio * 2 ** (c / 1200.0)
            v = a * np.sin(TAU * f * t + r.uniform(0, TAU)) * (1.0 + 0.2 * np.sin(TAU * r.uniform(0.1, 0.4) * t + r.uniform(0, TAU)))
            (L if side == 0 else R)[:] += v
    out = _level(np.stack([L, R], 1), 0.3)
    e = env_asr(n, dur, att, rel) * (0.35 + 0.65 * vel)
    return tail_fade(out * e[:, None])


# --------------------------------------------------------------------------
# percussion (mono unless noted); all peak-normalised to ~0.9 * vel
# --------------------------------------------------------------------------
def _pk(x, vel):
    return tail_fade(x / (np.max(np.abs(x)) + 1e-9) * 0.9 * vel, 0.01)


def kick(r, kind="soft", vel=1.0):
    if kind == "orch":  # concert bass drum
        n = int(1.6 * MSR)
        t = secs(n)
        f = 45.0 + 25.0 * np.exp(-t / 0.05)
        x = sine(f) * np.exp(-t / 0.55) + 0.5 * sine(f * 1.6) * np.exp(-t / 0.2)
        nz = fft_shape(noise(r, n), lambda fr: lp(fr, 250) * hp(fr, 30)) * np.exp(-t / 0.3)
        x = x + 0.6 * nz / (np.max(np.abs(nz)) + 1e-9)
        return _pk(x * np.minimum(t / 0.004, 1), vel)
    if kind == "808":
        n = int(0.9 * MSR)
        t = secs(n)
        f = 44.0 + 90.0 * np.exp(-t / 0.018)
        x = np.tanh(2.2 * sine(f) * np.exp(-t / 0.45))
    elif kind == "punch":
        n = int(0.45 * MSR)
        t = secs(n)
        f = 50.0 + 140.0 * np.exp(-t / 0.022)
        x = np.tanh(1.8 * sine(f) * np.exp(-t / 0.16))
    else:
        n = int(0.4 * MSR)
        t = secs(n)
        f = 52.0 + 70.0 * np.exp(-t / 0.03)
        x = sine(f) * np.exp(-t / 0.14)
    click = fft_shape(noise(r, n), lambda fr: bump(fr, 3500, 6, 1.0) * hp(fr, 1000)) * np.exp(-t / 0.003)
    x = x + 0.15 * click / (np.max(np.abs(click)) + 1e-9)
    return _pk(x * np.minimum(t / 0.001, 1), vel)


def snare(r, kind="acoustic", vel=1.0):
    n = int(0.5 * MSR)
    t = secs(n)
    tune = {"acoustic": 1.0, "march": 1.3, "gated": 0.9, "brush": 1.0, "rim": 1.0, "piccolo": 1.5}[kind]
    if kind == "rim":
        x = fft_shape(noise(r, n), lambda f: bump(f, 1700, 14, 0.25) * bump(f, 450, 8, 0.3)) * np.exp(-t / 0.012)
        return _pk(x, vel)
    if kind == "brush":
        env = np.minimum(t / 0.012, 1) * np.exp(-t / 0.12)
        x = fft_shape(noise(r, n), lambda f: hp(f, 1500) * lp(f, 8000)) * env
        return _pk(x, vel)
    body = (sine(np.full(n, 185.0 * tune)) * np.exp(-t / 0.07) + 0.6 * sine(np.full(n, 330.0 * tune)) * np.exp(-t / 0.05))
    body *= 1.0 + 0.3 * np.exp(-t / 0.01)
    wires_tau = {"acoustic": 0.14, "march": 0.1, "gated": 0.35, "piccolo": 0.09}[kind]
    wires = fft_shape(noise(r, n), lambda f: hp(f, 1800) * lp(f, 10000) * bump(f, 5000, 3, 1.0)) * np.exp(-t / wires_tau)
    if kind == "gated":
        wires *= np.clip((0.3 - t) / 0.02, 0.0, 1.0)
    x = 0.6 * body / np.max(np.abs(body)) + wires / np.max(np.abs(wires)) * (0.8 if kind != "march" else 1.0)
    stick = fft_shape(noise(r, n), lambda f: bump(f, 3000, 8, 0.6)) * np.exp(-t / 0.002)
    x += 0.3 * stick / (np.max(np.abs(stick)) + 1e-9)
    return _pk(x, vel)


def clap(r, vel=1.0, tight=False):
    n = int(0.35 * MSR)
    t = secs(n)
    env = np.zeros(n)
    for t0 in ((0.0, 0.008, 0.017) if tight else (0.0, 0.011, 0.023)):
        env += np.where(t >= t0, np.exp(-(t - t0) / 0.006), 0.0) * 0.6
    env += np.where(t >= 0.023, np.exp(-(t - 0.023) / 0.07), 0.0)
    x = fft_shape(noise(r, n), lambda f: bump(f, 1300, 6, 0.7) * hp(f, 600) * lp(f, 7000)) * env
    return _pk(x, vel)


def snap(r, vel=1.0):
    n = int(0.15 * MSR)
    t = secs(n)
    x = fft_shape(noise(r, n), lambda f: bump(f, 2600, 12, 0.35) * hp(f, 1000)) * np.exp(-t / 0.012)
    return _pk(x, vel)


def hat(r, kind="closed", vel=1.0):
    dur = {"closed": 0.09, "open": 0.55, "pedal": 0.07}[kind]
    tau = {"closed": 0.022, "open": 0.2, "pedal": 0.015}[kind]
    n = int(dur * MSR)
    t = secs(n)
    metal = np.zeros(n)
    for f in (3150.0, 4210.0, 5380.0, 6620.0, 7410.0, 8330.0):
        metal += np.sign(np.sin(TAU * f * r.uniform(0.98, 1.02) * t + r.uniform(0, TAU)))
    x = fft_shape(metal * 0.3 + noise(r, n), lambda f: hp(f, 6500, 3) * lp(f, 13500)) * np.exp(-t / tau)
    x *= np.minimum(t / 0.0008, 1)
    return _pk(x, vel)


def cymbal(r, kind="crash", vel=1.0, dur=None):
    tau = {"crash": 1.1, "ride": 0.9, "splash": 0.35, "china": 0.8, "sizzle": 2.0}[kind]
    dur = dur or tau * 3.0
    n = int(dur * MSR)
    t = secs(n)
    partials = np.zeros(n)
    for _ in range(36):
        f = r.uniform(900.0, 9000.0)
        partials += np.sin(TAU * f * t + r.uniform(0, TAU)) * np.exp(-t / (tau * r.uniform(0.3, 1.0)))
    nz = fft_shape(noise(r, n), lambda f: hp(f, 3000 if kind != "china" else 1800) * lp(f, 13000)) * np.exp(-t / tau)
    x = 0.4 * partials / (np.max(np.abs(partials)) + 1e-9) + nz / (np.max(np.abs(nz)) + 1e-9)
    if kind == "ride":
        x += 0.4 * np.sin(TAU * 2300 * t) * np.exp(-t / 0.4)
    x *= np.minimum(t / 0.002, 1)
    return _pk(x, vel)


def cymbal_swell(r, beats_len, spb, vel=0.8):
    """Mallet cymbal roll crescendo that peaks at the end (place it to end on the downbeat)."""
    dur = beats_len * spb
    n = int((dur + 0.6) * MSR)
    t = secs(n)
    x = fft_shape(noise(r, n), lambda f: hp(f, 2000) * lp(f, 12000) * bump(f, 5000, 4, 1.0))
    part = np.zeros(n)
    for _ in range(24):
        part += np.sin(TAU * r.uniform(1500, 8000) * t + r.uniform(0, TAU))
    x = x / np.max(np.abs(x)) + 0.25 * part / np.max(np.abs(part))
    env = np.clip(t / dur, 0, 1) ** 2.5 * np.where(t > dur, np.exp(-(t - dur) / 0.12), 1.0)
    return _pk(x * env, vel)


def riser(r, beats_len, spb, vel=0.8, lo=300.0, hi=6000.0):
    dur = beats_len * spb
    n = int(dur * MSR)
    t = secs(n)
    u = t / dur
    x = _sweep_filter(noise(r, n), lo * (hi / lo) ** u)
    return _pk(x * u ** 2, vel)


def reverse_swell(r, beats_len, spb, freq=None, vel=0.8):
    """A reversed cymbal (optionally with a reversed tonal bloom at `freq`)."""
    c = cymbal(r, "crash", 1.0, dur=beats_len * spb)
    x = c[::-1].copy()
    if freq:
        n = len(x)
        t = secs(n)
        tone = sum(np.sin(TAU * freq * k * t) / k for k in (1, 2, 3)) * np.exp(-t / (beats_len * spb * 0.4))
        x = x + 0.5 * tone[::-1]
    return _pk(x, vel)


def tom(r, freq=110.0, vel=1.0):
    n = int(0.7 * MSR)
    t = secs(n)
    f = freq * (1.0 + 0.4 * np.exp(-t / 0.04))
    x = sine(f) * np.exp(-t / 0.25) + 0.3 * sine(f * 1.6) * np.exp(-t / 0.12)
    nz = fft_shape(noise(r, n), lambda fr: lp(fr, 2500)) * np.exp(-t / 0.02)
    return _pk(x + 0.25 * nz / np.max(np.abs(nz)), vel)


def timpani(r, freq, vel=1.0, dur=2.5):
    n = int(dur * MSR)
    t = secs(n)
    x = np.zeros(n)
    for ratio, a, tau in ((1.0, 1.0, 1.4), (1.5, 0.55, 0.8), (1.98, 0.35, 0.6), (2.44, 0.2, 0.4), (2.9, 0.12, 0.3)):
        x += a * np.sin(TAU * freq * ratio * t + r.uniform(0, TAU)) * np.exp(-t / tau)
    x += 0.6 * np.sin(TAU * freq * 0.62 * t) * np.exp(-t / 0.12)
    nz = fft_shape(noise(r, n), lambda f: lp(f, 900) * hp(f, 40)) * np.exp(-t / 0.03)
    x += 0.5 * nz / (np.max(np.abs(nz)) + 1e-9)
    x *= np.minimum(t / 0.003, 1)
    return _pk(x, vel)


def timpani_roll(r, freq, beats_len, spb, v0=0.2, v1=1.0):
    dur = beats_len * spb
    n = int((dur + 2.0) * MSR)
    out = np.zeros(n)
    t = 0.0
    while t < dur:
        u = t / dur
        hit = timpani(r, freq, (v0 + (v1 - v0) * u) * r.uniform(0.8, 1.0), 1.6)
        i = int(t * MSR)
        m = min(len(hit), n - i)
        out[i:i + m] += hit[:m]
        t += 1.0 / 17.0 * r.uniform(0.85, 1.15)
    return _pk(out, v1)


def taiko(r, kind="odaiko", vel=1.0):
    if kind == "ka":  # rim click
        n = int(0.12 * MSR)
        t = secs(n)
        x = fft_shape(noise(r, n), lambda f: bump(f, 1600, 14, 0.3) * bump(f, 3200, 8, 0.3)) * np.exp(-t / 0.01)
        return _pk(x, vel)
    f0 = {"odaiko": 52.0, "nagado": 78.0, "shime": 330.0}[kind]
    dur = {"odaiko": 1.6, "nagado": 1.0, "shime": 0.25}[kind]
    n = int(dur * MSR)
    t = secs(n)
    f = f0 * (1.0 + 0.35 * np.exp(-t / 0.06))
    x = np.zeros(n)
    for ratio, a, tau in ((1.0, 1.0, dur * 0.35), (1.59, 0.5, dur * 0.15), (2.14, 0.3, dur * 0.1), (2.65, 0.18, dur * 0.07)):
        x += a * sine(f * ratio) * np.exp(-t / tau)
    slap = fft_shape(noise(r, n), lambda fr: lp(fr, 1800 if kind != "shime" else 6000) * hp(fr, 60)) * np.exp(-t / 0.02)
    x += 0.7 * slap / (np.max(np.abs(slap)) + 1e-9)
    return _pk(np.tanh(1.3 * x / np.max(np.abs(x))), vel)


def frame_drum(r, vel=1.0, low=True):
    n = int(0.5 * MSR)
    t = secs(n)
    f0 = 95.0 if low else 160.0
    f = f0 * (1.0 + 0.5 * np.exp(-t / 0.03))
    x = sine(f) * np.exp(-t / (0.16 if low else 0.08))
    nz = fft_shape(noise(r, n), lambda fr: lp(fr, 3000) * hp(fr, 200)) * np.exp(-t / 0.015)
    return _pk(x + 0.35 * nz / (np.max(np.abs(nz)) + 1e-9), vel)


def cajon(r, vel=1.0, slap=False):
    n = int(0.35 * MSR)
    t = secs(n)
    if slap:
        x = fft_shape(noise(r, n), lambda f: bump(f, 2200, 8, 0.8) * hp(f, 400)) * np.exp(-t / 0.05)
        x += 0.3 * sine(np.full(n, 190.0)) * np.exp(-t / 0.05)
    else:
        f = 80.0 * (1.0 + 0.6 * np.exp(-t / 0.02))
        x = sine(f) * np.exp(-t / 0.12)
        x += 0.2 * fft_shape(noise(r, n), lambda fr: lp(fr, 1200)) * np.exp(-t / 0.02)
    return _pk(x, vel)


def shaker(r, vel=1.0, long=False):
    n = int((0.16 if long else 0.1) * MSR)
    t = secs(n)
    env = np.minimum(t / (0.018 if long else 0.008), 1) * np.exp(-t / (0.05 if long else 0.025))
    x = fft_shape(noise(r, n), lambda f: hp(f, 4000, 3) * lp(f, 12000)) * env
    return _pk(x, vel)


def tambourine(r, vel=1.0, shake=False):
    n = int(0.4 * MSR)
    t = secs(n)
    x = np.zeros(n)
    for _ in range(14):
        f = r.uniform(5200.0, 11500.0)
        t0 = r.uniform(0.0, 0.02 if not shake else 0.06)
        x += np.where(t > t0, np.sin(TAU * f * (t - t0)) * np.exp(-(t - t0) / r.uniform(0.05, 0.16)), 0.0)
    nz = fft_shape(noise(r, n), lambda f: hp(f, 5000)) * np.exp(-t / 0.05)
    x = x / np.max(np.abs(x)) + 0.5 * nz / np.max(np.abs(nz))
    if not shake:
        hit = fft_shape(noise(r, n), lambda f: bump(f, 700, 6, 0.8)) * np.exp(-t / 0.01)
        x += 0.3 * hit / np.max(np.abs(hit))
    return _pk(x * np.minimum(t / (0.001 if not shake else 0.015), 1), vel)


def triangle(r, vel=1.0, dur=2.0):
    n = int(dur * MSR)
    t = secs(n)
    x = np.zeros(n)
    for f, a, tau in ((1370, 0.5, 1.2), (3900, 1.0, 1.0), (5200, 0.6, 0.8), (7450, 0.4, 0.6), (9800, 0.25, 0.4)):
        x += a * np.sin(TAU * f * t + r.uniform(0, TAU)) * np.exp(-t / tau)
    return _pk(x * np.minimum(t / 0.0008, 1), vel)


def woodblock(r, vel=1.0, pitch=1.0):
    n = int(0.12 * MSR)
    t = secs(n)
    x = np.sin(TAU * 1050 * pitch * t) * np.exp(-t / 0.028) + 0.5 * np.sin(TAU * 1720 * pitch * t) * np.exp(-t / 0.015)
    x += 0.2 * noise(r, n) * np.exp(-t / 0.002)
    return _pk(x, vel)


def claves(r, vel=1.0):
    n = int(0.12 * MSR)
    t = secs(n)
    x = np.sin(TAU * 2500 * t) * np.exp(-t / 0.035) + 0.1 * noise(r, n) * np.exp(-t / 0.002)
    return _pk(x, vel)


def castanets(r, vel=1.0):
    n = int(0.1 * MSR)
    t = secs(n)
    x = np.zeros(n)
    for t0 in (0.0, 0.009):
        x += np.where(t >= t0, fft_shape(noise(r, n), lambda f: bump(f, 2400, 10, 0.5)) * np.exp(-(t - t0) / 0.006), 0)
    return _pk(x, vel)


def clock_tick(r, vel=1.0, tock=False):
    n = int(0.09 * MSR)
    t = secs(n)
    f1, f2 = (2400.0, 4100.0) if not tock else (1250.0, 2050.0)
    x = np.sin(TAU * f1 * t) * np.exp(-t / 0.012) + 0.6 * np.sin(TAU * f2 * t) * np.exp(-t / 0.006)
    x += fft_shape(noise(r, n), lambda f: hp(f, 3000)) * np.exp(-t / 0.0015) * 0.6
    return _pk(x, vel)


def anvil(r, vel=1.0, pitch=1.0, ring=1.0):
    n = int(2.2 * ring * MSR)
    t = secs(n)
    base = 1180.0 * pitch
    x = np.zeros(n)
    for ratio, a, tau in ((1.0, 1.0, 1.1), (2.39, 0.7, 0.8), (2.93, 0.4, 0.6), (4.08, 0.5, 0.5), (5.72, 0.3, 0.35),
                          (6.6, 0.2, 0.25), (0.51, 0.3, 0.3)):
        x += a * np.sin(TAU * base * ratio * t + r.uniform(0, TAU)) * np.exp(-t / (tau * ring))
    strike = fft_shape(noise(r, n), lambda f: hp(f, 1500) * lp(f, 12000)) * np.exp(-t / 0.004)
    x = x / np.max(np.abs(x)) + 0.6 * strike / np.max(np.abs(strike))
    thud = np.sin(TAU * 140 * t) * np.exp(-t / 0.03)
    return _pk(x + 0.4 * thud, vel)


def metal_hit(r, vel=1.0, freq=190.0, ring=1.2):
    """Struck steel pipe / girder: inharmonic bar modes, clangy."""
    n = int(ring * 2.2 * MSR)
    t = secs(n)
    x = np.zeros(n)
    for ratio, a, tau in ((1.0, 1.0, ring), (2.756, 0.8, ring * 0.7), (5.404, 0.6, ring * 0.45), (8.933, 0.4, ring * 0.3),
                          (13.34, 0.2, ring * 0.2)):
        x += a * np.sin(TAU * freq * ratio * t + r.uniform(0, TAU)) * np.exp(-t / tau)
    nz = fft_shape(noise(r, n), lambda f: hp(f, 800) * lp(f, 8000)) * np.exp(-t / 0.006)
    return _pk(x / np.max(np.abs(x)) + 0.5 * nz / np.max(np.abs(nz)), vel)


def gong(r, vel=1.0, dur=6.0, freq=90.0):
    n = int(dur * MSR)
    t = secs(n)
    x = np.zeros(n)
    for _ in range(40):
        f = freq * r.uniform(1.0, 30.0) ** 1.0
        bloom = 1.0 - np.exp(-t / (0.05 + 0.6 * (f / (freq * 30))))
        x += np.sin(TAU * f * t + r.uniform(0, TAU)) * bloom * np.exp(-t / r.uniform(1.0, dur * 0.5)) / (f / freq) ** 0.4
    x += 1.5 * np.sin(TAU * freq * t) * np.exp(-t / (dur * 0.4))
    return _pk(x * np.minimum(t / 0.01, 1), vel)


def bubble(r, vel=1.0, freq=None):
    freq = freq or r.uniform(500, 1400)
    n = int(0.12 * MSR)
    t = secs(n)
    f = freq * (1.0 + 2.5 * t / 0.12)
    x = sine(f) * np.exp(-t / 0.035) * np.minimum(t / 0.002, 1)
    return _pk(x, vel)


def drop(r, vel=1.0, freq=None):
    """A water drop: short falling-then-rising pluck."""
    freq = freq or r.uniform(900, 2000)
    n = int(0.2 * MSR)
    t = secs(n)
    f = freq * (1.0 + 0.8 * t / 0.2 - 0.3 * np.exp(-t / 0.004))
    x = sine(f) * np.exp(-t / 0.05)
    return _pk(x, vel)


def boom(r, vel=1.0, freq=38.0, dur=2.5):
    """Cinematic sub boom (trailer hit)."""
    n = int(dur * MSR)
    t = secs(n)
    f = freq * (1.0 + 1.5 * np.exp(-t / 0.05))
    x = np.tanh(1.5 * sine(f) * np.exp(-t / (dur * 0.35)))
    nz = fft_shape(noise(r, n), lambda fr: lp(fr, 400)) * np.exp(-t / 0.25)
    return _pk(x + 0.3 * nz / np.max(np.abs(nz)), vel)


# --------------------------------------------------------------------------
# render cache: repeated notes (strums, arpeggios, bass lines) reuse a few seeded takes
# --------------------------------------------------------------------------
_CACHE = {}


def memo(fn, takes=3, name=None):
    """Wrap an instrument so identical notes reuse one of `takes` cached renders (chosen by the
    track's RNG, so the result stays deterministic). Keyword args are part of the key."""
    tag = name or getattr(fn, "__name__", repr(fn))
    import inspect
    try:
        params = set(inspect.signature(fn).parameters)
        open_kw = any(p.kind == p.VAR_KEYWORD for p in inspect.signature(fn).parameters.values())
    except (TypeError, ValueError):
        params, open_kw = set(), True

    def inst(r, freq, dur, vel=0.8, **kw):
        if not open_kw:
            kw = {a: v for a, v in kw.items() if a in params}
        k = int(r.integers(0, takes))
        key = (tag, round(float(freq), 2), round(float(dur), 3), round(float(vel), 2), k,
               tuple(sorted((a, v if not isinstance(v, float) else round(v, 4)) for a, v in kw.items())))
        hit = _CACHE.get(key)
        if hit is None:
            hit = fn(np.random.default_rng(_key_seed(key)), freq, dur, vel, **kw)
            _CACHE[key] = hit
        return hit
    return inst


def _key_seed(key):
    import zlib
    return zlib.crc32(repr(key).encode("ascii"))


def clear_cache():
    _CACHE.clear()


# --------------------------------------------------------------------------
# notation
# --------------------------------------------------------------------------
_NOTE_RE = re.compile(r"^([A-Ga-g])([#b]*)(-?\d)$")
_PC = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
_DUR = {"w": 4.0, "h": 2.0, "q": 1.0, "e": 0.5, "s": 0.25, "t": 1.0 / 3.0, "x": 2.0 / 3.0, "z": 1.0 / 6.0, "o": 8.0}


def note_num(s):
    m = _NOTE_RE.match(s)
    if not m:
        raise ValueError("bad note " + s)
    pc = _PC[m.group(1).upper()] + m.group(2).count("#") - m.group(2).count("b")
    return pc + 12 * (int(m.group(3)) + 1)


def mel(text, bar_beats=4.0, transpose=0, start=0.0):
    """Parse a melody line into [(beat, midi or None, dur, vel, flags)].

    Tokens: <note><dur>[.][!|?][~]   e.g. C5q  G5h.  Bb4e!  r q  -  where
      dur: w h q e s  t (triplet eighth)  x (triplet quarter)  z (triplet 16th)  o (two bars of 4)
      .  dotted     !  accent (vel 1.0)    ?  ghost (vel 0.45)    ~  tie into the next note
      r<dur>  rest.   Chords: [C4E4G4]q.   |  bar line (checked).   >N transposes following notes.
    """
    out = []
    beat = start
    bar_start = start
    vel_default = 0.8
    tie = False
    first_bar = True   # the first bar may be a pickup (anacrusis) of any length
    text = re.sub(r"(?<!\S)r\s+([whqestxzo]\.?)", r"r\1", text.replace("\n", " "))
    for tok in text.split():
        if tok == "|":
            if not first_bar and abs((beat - bar_start) - bar_beats) > 1e-6:
                raise ValueError("bar length %.3f != %.3f near %r (beat %.2f)" % (beat - bar_start, bar_beats, tok, beat))
            bar_start = beat
            first_bar = False
            continue
        if tok.startswith(">"):
            transpose = int(tok[1:])
            continue
        m = re.match(r"^(\[[^\]]+\]|[A-Ga-g][#b]*-?\d|r)([whqestxzo])(\.?)([!?]?)(~?)$", tok)
        if not m:
            raise ValueError("bad token %r" % tok)
        body, d, dot, acc, tl = m.groups()
        dur = _DUR[d] * (1.5 if dot else 1.0)
        vel = 1.0 if acc == "!" else (0.45 if acc == "?" else vel_default)
        if body == "r":
            beat += dur
            tie = False
            continue
        notes = re.findall(r"[A-Ga-g][#b]*-?\d", body) if body.startswith("[") else [body]
        midis = [note_num(nn) + transpose for nn in notes]
        if tie and out:
            # extend the previous note(s) of the same pitch
            for i in range(len(out) - 1, -1, -1):
                if out[i][1] in midis and abs(out[i][0] + out[i][2] - beat) < 1e-6:
                    out[i] = (out[i][0], out[i][1], out[i][2] + dur, out[i][3], out[i][4])
            tie = bool(tl)
            beat += dur
            continue
        for mm in midis:
            out.append((beat, mm, dur, vel, ""))
        tie = bool(tl)
        beat += dur
    return out


_QUAL = {
    "": (0, 4, 7), "m": (0, 3, 7), "dim": (0, 3, 6), "aug": (0, 4, 8), "sus4": (0, 5, 7), "sus2": (0, 2, 7),
    "7": (0, 4, 7, 10), "maj7": (0, 4, 7, 11), "m7": (0, 3, 7, 10), "m7b5": (0, 3, 6, 10), "dim7": (0, 3, 6, 9),
    "6": (0, 4, 7, 9), "m6": (0, 3, 7, 9), "9": (0, 4, 7, 10, 14), "maj9": (0, 4, 7, 11, 14), "m9": (0, 3, 7, 10, 14),
    "add9": (0, 4, 7, 14), "madd9": (0, 3, 7, 14), "7sus4": (0, 5, 7, 10), "mmaj7": (0, 3, 7, 11),
    "maj7#11": (0, 4, 7, 11, 18), "5": (0, 7), "11": (0, 7, 10, 14, 17), "m11": (0, 3, 7, 10, 14, 17),
    "13": (0, 4, 7, 10, 14, 21), "7b9": (0, 4, 7, 10, 13), "6/9": (0, 4, 7, 9, 14), "sus": (0, 5, 7),
}


def chord(sym):
    """'Am7', 'F/C', 'Bbmaj9', 'G7sus4' -> (root pc, [intervals], bass pc)."""
    m = re.match(r"^([A-G])([#b]?)([^/]*)(?:/([A-G][#b]?))?$", sym)
    if not m:
        raise ValueError("bad chord " + sym)
    root = (_PC[m.group(1)] + (1 if m.group(2) == "#" else -1 if m.group(2) == "b" else 0)) % 12
    q = m.group(3)
    if q not in _QUAL:
        raise ValueError("unknown chord quality %r in %s" % (q, sym))
    bass = root
    if m.group(4):
        b = m.group(4)
        bass = (_PC[b[0]] + (1 if b[1:] == "#" else -1 if b[1:] == "b" else 0)) % 12
    return root, list(_QUAL[q]), bass


def voice(sym, center=64, count=4, prev=None, spread=False):
    """Choose MIDI notes for a chord near `center`, voice-led from `prev` when given."""
    import itertools
    root, iv, _ = chord(sym)
    pcs = sorted(set((root + i) % 12 for i in iv))
    cands = [o for o in range(center - 14, center + 15) if o % 12 in pcs]
    for relax in (False, True):
        best = None
        best_cost = 1e9
        for combo in itertools.combinations(cands, count):
            used = set(c % 12 for c in combo)
            missing = [p for p in pcs if p not in used]
            if len(pcs) <= count and missing and not relax:
                continue
            span = combo[-1] - combo[0]
            if span > (19 if spread else 14) + (7 if relax else 0):
                continue
            cost = 0.0
            for p in missing:  # dropping the 5th is fine, the root less so, colour tones not at all
                d = (p - root) % 12
                cost += 1.0 if d == 7 else (4.0 if d == 0 else 6.0)
            cost += abs(np.mean(combo) - center) * 0.4
            gaps = np.diff(combo)
            cost += 3.0 * np.sum(gaps < 2)
            cost += 1.5 * np.sum(gaps[:1] < 3) if combo[0] < 55 else 0.0   # no low seconds / thirds mud
            if prev is not None and len(prev) == count:
                cost += 0.8 * sum(abs(a - b) for a, b in zip(sorted(prev), combo))
            if cost < best_cost:
                best_cost = cost
                best = combo
        if best is not None:
            return list(best)
    return sorted(cands[:count])


def bass_note(sym, lo=36, hi=50):
    _, _, b = chord(sym)
    n = lo + ((b - lo) % 12)
    if n > hi:
        n -= 12
    return n


def chord_tones(sym, lo, hi):
    root, iv, _ = chord(sym)
    pcs = set((root + i) % 12 for i in iv)
    return [m for m in range(lo, hi + 1) if m % 12 in pcs]


# --------------------------------------------------------------------------
# room impulses, delay, chorus
# --------------------------------------------------------------------------
def make_ir(r, rt60=2.0, predelay=0.02, damp=4000.0, low_mult=1.1, er=0.5, er_span=0.06, width=1.0, tone=None):
    """Stereo room impulse: early reflections + exponentially decaying decorrelated noise with a
    frequency-dependent decay time. `tone` optionally shapes the whole IR spectrum."""
    length = rt60 * 1.3 + predelay + 0.1
    n = int(length * MSR)
    t = secs(n)
    ir = np.zeros((n, 2))
    centers = np.array([90.0, 180.0, 360.0, 720.0, 1440.0, 2880.0, 5760.0, 11520.0])
    late_start = int(predelay * MSR)
    m = n - late_start
    tt = secs(m)
    f = np.fft.rfftfreq(fast_len(m), 1.0 / MSR)
    for c in range(2):
        nz = noise(r, fast_len(m))
        spec = np.fft.rfft(nz)
        acc = np.zeros(m)
        for fc in centers:
            w = np.exp(-0.5 * (np.log2(np.maximum(f, 1.0) / fc) / 0.5) ** 2)
            band = np.fft.irfft(spec * w, len(nz))[:m]
            rt = rt60 * (low_mult if fc < 300 else 1.0) * (min(1.0, (damp / fc) ** 0.55))
            acc += band * np.exp(-6.91 * tt / max(rt, 0.05))
        acc *= np.minimum(tt / 0.012, 1.0) ** 1.5
        ir[late_start:, c] = acc
    ir /= np.sqrt(np.sum(ir ** 2) / 2) + 1e-12
    # early reflections
    for _ in range(12):
        d = predelay * 0.3 + r.uniform(0.004, er_span)
        i = int(d * MSR)
        g = er * r.uniform(0.3, 1.0) * (1.0 - d / (er_span + predelay)) * 0.25
        c = int(r.integers(0, 2))
        if i < n:
            ir[i, c] += g
            ir[min(i + int(r.uniform(0.0003, 0.002) * MSR), n - 1), 1 - c] += g * 0.6 * width
    if tone is not None:
        for c in range(2):
            ir[:, c] = fft_shape(ir[:, c], tone, pad=0.01)
    if width < 1.0:
        mid = ir.mean(axis=1, keepdims=True)
        ir = mid + (ir - mid) * width
    return ir


def circ_convolve(x, ir):
    """Circular stereo convolution of a (n, 2) loop with an (m, 2) impulse (m < n)."""
    n = len(x)
    out = np.zeros_like(x)
    xs = [np.fft.rfft(x[:, c]) for c in range(2)]
    for c in range(2):
        h = np.zeros(n)
        h[:len(ir)] = ir[:, c]
        out[:, c] = np.fft.irfft(xs[c] * np.fft.rfft(h), n)
    # a little cross-feed keeps hard-panned sends from sounding one-sided
    return out * 0.85 + out[:, ::-1] * 0.15


def circ_delay(x, secs_, fb=0.35, damp=4000.0, pingpong=True):
    n = len(x)
    d = int(round(secs_ * MSR))
    th = TAU * np.arange(n // 2 + 1) / n
    f = np.arange(n // 2 + 1) * MSR / n
    lpf = 1.0 / (1.0 + (f / damp) ** 2)
    z = np.exp(-1j * th * d) * lpf
    mono = np.fft.rfft(x.mean(axis=1))
    if pingpong:
        den = 1.0 - (fb * z) ** 2
        left = np.fft.irfft(mono * z / den, n)
        right = np.fft.irfft(mono * fb * z * z / den, n)
        return np.stack([left, right], axis=1)
    y = np.fft.irfft(mono * z / (1.0 - fb * z), n)
    return np.stack([y, y], axis=1)


def circ_chorus(x, depth_ms=3.0, rate=0.6, base_ms=12.0, mix=0.5):
    n = len(x)
    t = secs(n)
    idx = np.arange(n, dtype=np.float64)
    out = x.copy() * (1.0 - mix * 0.5)
    for c, ph in ((0, 0.0), (1, np.pi / 2)):
        d = (base_ms + depth_ms * np.sin(TAU * rate * t + ph)) * MSR / 1000.0
        pos = (idx - d) % n
        i0 = np.floor(pos).astype(int)
        w = pos - i0
        i1 = (i0 + 1) % n
        out[:, c] += mix * (x[i0, c] * (1 - w) + x[i1, c] * w)
    return out


def circ_min_centered(x, half):
    """Sliding minimum over at least [i - half, i + half] (circular), by doubling."""
    w = 1
    y = x.copy()
    while w < 2 * half + 1:
        y = np.minimum(y, np.roll(y, w))
        w *= 2
    return np.roll(y, -(w // 2))


def circ_avg_centered(x, half):
    w = 2 * half + 1
    c = np.cumsum(np.concatenate([x[-w:], x]))
    avg = (c[w:] - c[:-w]) / w          # mean of x[i - w + 1 .. i]
    return np.roll(avg, -half)


def circ_limit_gain(x, ceiling=0.89, look=0.003):
    """Per-sample gain of a circular look-ahead limiter: never above what each sample needs,
    smoothed over ~2 * look seconds so the reduction ramps instead of clicking."""
    h = max(int(look * MSR), 2)
    need = np.minimum(1.0, ceiling / np.maximum(np.max(np.abs(x), axis=1), 1e-9))
    return circ_avg_centered(circ_min_centered(need, 2 * h), h)


def circ_limit(x, ceiling=0.89, look=0.003):
    g = circ_limit_gain(x, ceiling, look)
    return x * g[:, None], float(np.min(g))


def soft_clip(x, knee=0.8, ceil=0.95):
    span = ceil - knee
    mag = np.abs(x)
    over = mag > knee
    y = x.copy()
    y[over] = np.sign(x[over]) * (knee + span * np.tanh((mag[over] - knee) / span))
    return y


def k_rms(x):
    """Rough K-weighted loudness proxy (dB): high-pass + high-shelf, mean over channels."""
    n = len(x)
    f = np.fft.rfftfreq(n, 1.0 / MSR)
    g = hp(f, 60.0, 1) * shelf(f, 1500.0, 4.0)
    y = np.stack([np.fft.irfft(np.fft.rfft(x[:, c]) * g, n) for c in range(x.shape[1])], 1)
    return 20.0 * np.log10(np.sqrt(np.mean(y ** 2)) + 1e-12)


# --------------------------------------------------------------------------
# track: circular multi-layer mixer
# --------------------------------------------------------------------------
class Track:
    """A looping piece. Time is in beats; bars are `bpb` beats long.

    Buses hold dry signal per (layer, bus); each bus may have processing (eq, drive, chorus,
    pump) and sends to named reverbs / the delay.
    """

    def __init__(self, name, bpm, bars, bpb=4, swing=0.0, layers=("base",)):
        self.name = name
        self.bpm = bpm
        self.spb = 60.0 / bpm
        self.bpb = bpb
        self.bars = bars
        self.swing = swing
        self.layers = layers
        # nudge the tempo (by under 0.4 %, inaudible) so the loop length has only small prime factors:
        # every circular filter / reverb is an FFT over the whole loop
        self.n = nice_len(int(round(bars * bpb * self.spb * MSR)))
        self.spb = self.n / (MSR * bars * bpb)
        self.bpm = 60.0 / self.spb
        self.dry = {}        # (layer, bus) -> (n, 2)
        self.sends = {}      # (layer, fx) -> (n, 2)
        self.bus_cfg = {}
        self.fx_cfg = {}
        self.rng = rng_for("music_" + name)
        self.pump_times = []

    # ---- configuration
    def bus(self, name, eq=None, drive=0.0, chorus=None, pump=0.0, width=1.0, gain=1.0):
        self.bus_cfg[name] = dict(eq=eq, drive=drive, chorus=chorus, pump=pump, width=width, gain=gain)

    def reverb(self, name, ir, ret=1.0, eq=None):
        self.fx_cfg[name] = dict(kind="rev", ir=ir, ret=ret, eq=eq)

    def delay(self, name, beats=0.75, fb=0.35, damp=4000.0, ret=1.0, pingpong=True, then=None):
        self.fx_cfg[name] = dict(kind="dly", secs=beats * self.spb, fb=fb, damp=damp, ret=ret, pingpong=pingpong,
                                 then=then)

    # ---- time
    def sec(self, beat):
        b = float(beat)
        if self.swing:
            frac = b % 1.0
            if abs(frac - 0.5) < 1e-6:
                b += self.swing * 0.5
        return b * self.spb

    def bar(self, bar, beat=0.0):
        return bar * self.bpb + beat

    # ---- adding sound
    def add(self, layer, bus, beat, sig, gain=1.0, pan=None, sends=None, jitter=0.0):
        if layer not in self.layers:
            raise ValueError("unknown layer " + layer)
        if sig.ndim == 1:
            sig = stereo(sig, pan or 0.0)
        elif pan:
            # re-pan a stereo signal (balance)
            a = (pan + 1.0) * np.pi / 4.0
            sig = sig * np.array([np.cos(a), np.sin(a)]) * np.sqrt(2.0)
        if len(sig) > self.n:
            sig = tail_fade(sig[:self.n].copy(), 0.05)
        t0 = self.sec(beat) + (self.rng.normal(0.0, jitter) if jitter else 0.0)
        i0 = int(round(t0 * MSR)) % self.n
        key = (layer, bus)
        if key not in self.dry:
            self.dry[key] = np.zeros((self.n, 2))
        sig = sig * gain
        self._mix_in(self.dry[key], i0, sig)
        for fx, amt in (sends or {}).items():
            k2 = (layer, fx)
            if k2 not in self.sends:
                self.sends[k2] = np.zeros((self.n, 2))
            self._mix_in(self.sends[k2], i0, sig * amt)

    def _mix_in(self, buf, i0, sig):
        """buf[i0:] += sig, wrapping round the end of the loop."""
        m = len(sig)
        first = min(m, self.n - i0)
        buf[i0:i0 + first] += sig[:first]
        if first < m:
            buf[:m - first] += sig[first:]

    def notes(self, layer, bus, events, inst, gain=1.0, sends=None, pan=None, jitter=0.004, beat0=0.0, legato=False,
              vel_scale=1.0, dur_scale=1.0, **kw):
        """Render parsed events [(beat, midi, dur, vel, flags)] with inst(r, freq, dur_secs, vel, ...)."""
        prev = None
        prev_end = None
        for (b, m, d, v, _) in events:
            f = float(mtof(m))
            extra = dict(kw)
            if legato and prev is not None and prev_end is not None and abs(prev_end - b) < 1e-6:
                extra["legato_from"] = prev
            dur_s = d * self.spb * dur_scale
            sig = inst(self.rng, f, dur_s, min(v * vel_scale, 1.0), **extra)
            self.add(layer, bus, beat0 + b, sig, gain, pan, sends, jitter)
            prev = f
            prev_end = b + d

    def hit(self, layer, bus, beat, sig, gain=1.0, pan=0.0, sends=None, jitter=0.002, pump=False):
        self.add(layer, bus, beat, sig, gain, pan, sends, jitter)
        if pump:
            self.pump_times.append(self.sec(beat))

    # ---- render
    def _process_bus(self, name, x):
        cfg = self.bus_cfg.get(name, {})
        if cfg.get("eq") is not None:
            x = circ_shape(x, cfg["eq"])
        if cfg.get("drive"):
            d = cfg["drive"]
            pk = np.max(np.abs(x)) + 1e-9
            x = np.tanh(d * x / pk) / np.tanh(d) * pk
        if cfg.get("chorus"):
            x = circ_chorus(x, *cfg["chorus"])
        if cfg.get("pump"):
            x = x * self._pump_env(cfg["pump"])[:, None]
        w = cfg.get("width", 1.0)
        if w != 1.0:
            mid = x.mean(axis=1, keepdims=True)
            x = mid + (x - mid) * w
        return x * cfg.get("gain", 1.0)

    def _pump_env(self, depth, release=None):
        """Side-chain ducking from the kick times (circular)."""
        release = release or self.spb * 0.45
        k = int(release * 2.5 * MSR)
        kt = secs(k)
        att = int(0.004 * MSR)
        kern = depth * np.exp(-kt / (release * 0.35))
        kern[:att] *= np.linspace(0.0, 1.0, att)
        red = np.zeros(self.n)
        for t0 in self.pump_times:
            i0 = int(round(t0 * MSR)) - att
            idx = (i0 + np.arange(k)) % self.n
            red[idx] = np.maximum(red[idx], kern)
        return 1.0 - red

    def render_layer(self, layer):
        mix = np.zeros((self.n, 2))
        for (ly, bus), x in self.dry.items():
            if ly == layer:
                mix += self._process_bus(bus, x)
        for (ly, fx), s in sorted(self.sends.items()):
            if ly != layer:
                continue
            cfg = self.fx_cfg[fx]
            if cfg["kind"] == "rev":
                wet = circ_convolve(s, cfg["ir"])
            else:
                wet = circ_delay(s, cfg["secs"], cfg["fb"], cfg["damp"], cfg["pingpong"])
                if cfg.get("then"):
                    then = self.fx_cfg[cfg["then"][0]]
                    wet = wet + cfg["then"][1] * circ_convolve(wet, then["ir"])
            if cfg.get("eq") is not None:
                wet = circ_shape(wet, cfg["eq"])
            mix += wet * cfg["ret"]
        mix = circ_shape(mix, lambda f: hp(f, 30.0, 2))
        return mix

    def render(self, rms_db=-15.0, ceiling=0.89, mode="add", quality=0.58, master_eq=None, write=True, hi_gain=1.35):
        """Render every layer, master them together and write music_<name>[_hi].ogg.

        mode 'add': layers are stacked in game, loudness is set on the sum.
        mode 'cross': each layer is heard on its own, each is set to the target on its own.
        """
        outs = {ly: self.render_layer(ly) for ly in self.layers}
        if mode == "add" and "hi" in outs:
            outs["hi"] = outs["hi"] * hi_gain   # the build-up should be felt, not just heard
        if master_eq is not None:
            outs = {ly: circ_shape(x, master_eq) for ly, x in outs.items()}
        if mode == "add":
            full = sum(outs.values())
            scale = 10.0 ** ((rms_db - k_rms(full)) / 20.0)
            outs = {ly: x * scale for ly, x in outs.items()}
            # limit the sum, then share the gain reduction so the stack never clips
            g = circ_limit_gain(sum(outs.values()), ceiling)
            outs = {ly: x * g[:, None] for ly, x in outs.items()}
        else:
            for ly in list(outs):
                x = outs[ly]
                x = x * 10.0 ** ((rms_db - k_rms(x)) / 20.0)
                outs[ly], gmin = circ_limit(x, ceiling)
        report = []
        for ly, x in outs.items():
            x = soft_clip(x, 0.85, 0.97)
            outs[ly] = x
            fname = "music_" + self.name + ("" if ly == "base" else "_" + ly)
            if write:
                ga.write_ogg(fname, x, MSR, quality)
            report.append("  %-22s %6.2f s  k-rms %6.1f dB  peak %6.2f dBFS" % (
                fname + ".ogg", self.n / MSR, k_rms(x), 20 * np.log10(np.max(np.abs(x)) + 1e-12)))
        if len(outs) > 1 and mode == "add":
            full = sum(outs.values())
            report.append("  %-22s sum k-rms %6.1f dB  peak %6.2f dBFS" % (
                "(all layers)", k_rms(full), 20 * np.log10(np.max(np.abs(full)) + 1e-12)))
        print("\n".join(report))
        return outs


def render_stinger(name, x, rms_db=-16.0, quality=0.45, peak=0.89):
    """Master a one-shot (non-looping) musical stinger to ogg."""
    x = x * 10.0 ** ((rms_db - k_rms(x)) / 20.0)
    pk = np.max(np.abs(x))
    if pk > peak:
        x = soft_clip(x * (peak / pk) ** 0.5, 0.8, 0.95)
    x = tail_fade(x.copy(), 0.25)
    k = int(0.003 * MSR)
    x[:k] *= np.linspace(0, 1, k)[:, None]
    ga.write_ogg(name, x, MSR, quality)
    print("  %-22s %6.2f s  k-rms %6.1f dB  peak %6.2f dBFS" % (name + ".ogg", len(x) / MSR, k_rms(x),
                                                               20 * np.log10(np.max(np.abs(x)) + 1e-12)))
    return x


class Buffer:
    """Linear (non-circular) stereo buffer for stingers, with the same add / reverb helpers."""

    def __init__(self, seconds, bpm=120.0):
        self.n = int(seconds * MSR)
        self.spb = 60.0 / bpm
        self.dry = np.zeros((self.n, 2))
        self.sends = {}

    def add(self, beat, sig, gain=1.0, pan=None, sends=None):
        if sig.ndim == 1:
            sig = stereo(sig, pan or 0.0)
        i0 = int(round(beat * self.spb * MSR))
        m = min(len(sig), self.n - i0)
        if m <= 0:
            return
        self.dry[i0:i0 + m] += sig[:m] * gain
        for fx, amt in (sends or {}).items():
            self.sends.setdefault(fx, np.zeros((self.n, 2)))[i0:i0 + m] += sig[:m] * gain * amt

    def notes(self, events, inst, rng, gain=1.0, pan=None, sends=None, beat0=0.0, legato=False, **kw):
        prev = None
        prev_end = None
        for (b, m, d, v, _) in events:
            f = float(mtof(m))
            extra = dict(kw)
            if legato and prev is not None and abs(prev_end - b) < 1e-6:
                extra["legato_from"] = prev
            self.add(beat0 + b, inst(rng, f, d * self.spb, v, **extra), gain, pan, sends)
            prev = f
            prev_end = b + d

    def mix(self, irs):
        out = self.dry.copy()
        for fx, s in self.sends.items():
            ir = irs[fx]
            m = fast_len(self.n + len(ir))
            for c in range(2):
                out[:, c] += np.fft.irfft(np.fft.rfft(s[:, c], m) * np.fft.rfft(ir[:, c], m), m)[:self.n]
        return out
