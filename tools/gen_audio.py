#!/usr/bin/env python3
"""Jump Circuit - procedural audio generator.

Synthesises the core sound effects used by the game (the score is tools/gen_music.py) and writes
them as 16-bit PCM WAV files into <project>/audio/.  Everything is original
and generated from maths + seeded noise, so no third-party assets are used.

Usage (from anywhere):
    python tools/gen_audio.py            # generate everything, then verify
    python tools/gen_audio.py --verify   # only verify the files on disk
    (music: tools/gen_music.py; the circular Track helpers below remain for loop generators)

Deterministic: every sound uses its own RNG seeded from SEED + its name, so
re-running gives bit-identical files.  Requires numpy.
"""
import os
import struct
import sys
import wave
import zlib

import numpy as np

SEED = 20260921
SR = 44100          # effects sample rate (mono)
MSR = 22050         # music sample rate (stereo)
SFX_PEAK_DB = -3.0
MUSIC_RMS_DB = -14.0
MUSIC_PEAK_CEIL = 0.84   # about -1.5 dBFS

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "audio")
TAU = 2.0 * np.pi


# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------
def rng_for(name):
    return np.random.default_rng(SEED + zlib.crc32(name.encode("ascii")))


def mtof(m):
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


def db(x):
    return 20.0 * np.log10(max(float(x), 1e-12))


def tvec(dur, sr=SR):
    return np.arange(int(round(dur * sr))) / sr


def osc(freq, sr=SR, phase=0.0):
    """Sine oscillator driven by a per-sample frequency array."""
    return np.sin(TAU * np.cumsum(freq) / sr + phase)


def sweep(f0, f1, t, dur):
    """Exponential frequency glide from f0 to f1 over dur seconds."""
    return f0 * (f1 / f0) ** np.clip(t / dur, 0.0, 1.0)


def ad_env(t, attack, tau):
    """Linear attack then exponential decay."""
    return np.minimum(t / max(attack, 1e-6), 1.0) * np.exp(-np.maximum(t - attack, 0.0) / tau)


def fade(x, sr=SR, fin=0.002, fout=0.008):
    x = x.copy()
    a = max(int(fin * sr), 1)
    b = max(int(fout * sr), 1)
    x[:a] *= 0.5 - 0.5 * np.cos(np.pi * np.arange(a) / a)
    x[-b:] *= 0.5 + 0.5 * np.cos(np.pi * np.arange(b) / b)
    return x


def norm_peak(x, peak_db=SFX_PEAK_DB):
    x = x - np.mean(x)
    return x * (10.0 ** (peak_db / 20.0) / np.max(np.abs(x)))


def fft_band(x, sr, lo=None, hi=None, order=4, circular=False):
    """Zero-phase Butterworth-shaped band filter done in the FFT domain."""
    pad = 0 if circular else int(0.03 * sr)
    xp = x if circular else np.concatenate([np.zeros(pad), x, np.zeros(pad)])
    spec = np.fft.rfft(xp)
    f = np.fft.rfftfreq(len(xp), 1.0 / sr)
    g = np.ones_like(f)
    if lo:
        g *= 1.0 / np.sqrt(1.0 + (lo / np.maximum(f, 1e-9)) ** (2 * order))
    if hi:
        g *= 1.0 / np.sqrt(1.0 + (f / hi) ** (2 * order))
    y = np.fft.irfft(spec * g, len(xp))
    return y if circular else y[pad:pad + len(x)]


def svf_bandpass(x, fc, q, sr):
    """Chamberlin state-variable band-pass with a per-sample cutoff array."""
    f = (2.0 * np.sin(np.pi * np.minimum(fc, sr / 6.5) / sr)).tolist()
    xs = x.tolist()
    damp = 1.0 / q
    low = 0.0
    band = 0.0
    out = [0.0] * len(xs)
    for i in range(len(xs)):
        low += f[i] * band
        high = xs[i] - low - damp * band
        band += f[i] * high
        out[i] = band
    return np.array(out)


def place(buf, t0, sig, sr=SR, gain=1.0):
    """Mix sig into buf at time t0 (truncates at the end of buf)."""
    i0 = int(round(t0 * sr))
    n = min(len(sig), len(buf) - i0)
    if n > 0:
        buf[i0:i0 + n] += sig[:n] * gain


def write_wav(name, data, sr, loop=False):
    """16-bit PCM RIFF writer.  loop=True adds a smpl chunk (whole-file forward loop)."""
    data = np.asarray(data, dtype=np.float64)
    if not np.all(np.isfinite(data)):
        raise ValueError(name + ": non-finite samples")
    ch = 1 if data.ndim == 1 else data.shape[1]
    pcm = np.clip(np.round(data * 32767.0), -32768, 32767).astype("<i2")
    frames = pcm.shape[0]
    raw = pcm.tobytes()
    fmt = struct.pack("<HHIIHH", 1, ch, sr, sr * ch * 2, ch * 2, 16)
    body = b"WAVE" + b"fmt " + struct.pack("<I", len(fmt)) + fmt
    body += b"data" + struct.pack("<I", len(raw)) + raw
    if loop:
        smpl = struct.pack("<9I", 0, 0, int(1e9 / sr), 60, 0, 0, 0, 1, 0)
        smpl += struct.pack("<6I", 0, 0, 0, frames - 1, 0, 0)
        body += b"smpl" + struct.pack("<I", len(smpl)) + smpl
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".wav")
    with open(path, "wb") as fh:
        fh.write(b"RIFF" + struct.pack("<I", len(body)) + body)
    return path


def write_ogg(name, data, sr, quality=0.55):
    """Ogg Vorbis writer (needs the soundfile package).  `quality` is libsndfile's
    compression level: 0 = best / biggest, 1 = smallest.  Written in blocks: one big
    write crashes libsndfile's Vorbis encoder on Windows.  Loops are set at runtime
    (AudioStreamOggVorbis.loop), so no loop metadata is stored."""
    import soundfile as sf  # only the music / ambience generators need it
    data = np.asarray(data, dtype=np.float64)
    if not np.all(np.isfinite(data)):
        raise ValueError(name + ": non-finite samples")
    data = np.clip(data, -1.0, 1.0)
    ch = 1 if data.ndim == 1 else data.shape[1]
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".ogg")
    with sf.SoundFile(path, "w", sr, ch, format="OGG", subtype="VORBIS", compression_level=quality) as fh:
        for i in range(0, len(data), 16384):
            fh.write(data[i:i + 16384])
    return path


def finish_sfx(name, x, fin=0.002, fout=0.008):
    x = norm_peak(fade(x, SR, fin, fout))
    write_wav(name, x, SR)
    print("  %-14s %5.2f s  peak %6.2f dBFS" % (name + ".wav", len(x) / SR, db(np.max(np.abs(x)))))


# --------------------------------------------------------------------------
# sound effects
# --------------------------------------------------------------------------
def sfx_jump():
    t = tvec(0.18)
    ph_f = sweep(380.0, 900.0, t, 0.13)
    blip = osc(ph_f) + 0.22 * osc(ph_f * 2.0) * np.exp(-t / 0.05)
    blip *= ad_env(t, 0.004, 0.06)
    thump = osc(sweep(150.0, 65.0, t, 0.07)) * ad_env(t, 0.002, 0.035)
    finish_sfx("jump", blip + 0.5 * thump)


def sfx_land():
    r = rng_for("land")
    t = tvec(0.2)
    ft = sweep(125.0, 52.0, t, 0.12)
    thud = (osc(ft) + 0.35 * osc(ft * 2.0) + 0.15 * osc(ft * 3.0)) * ad_env(t, 0.003, 0.06)
    noise = fft_band(r.standard_normal(len(t)), SR, 120.0, 950.0, 2) * ad_env(t, 0.002, 0.03)
    finish_sfx("land", thud + 0.7 * noise / np.max(np.abs(noise)))


def sfx_step():
    # a light robot foot tick: a bright noise click over a short 210 -> 120 Hz tap
    # (kept well above the land thud so the two never muddy each other)
    r = rng_for("step")
    t = tvec(0.07)
    click = fft_band(r.standard_normal(len(t)), SR, 1400.0, 6000.0, 2) * ad_env(t, 0.001, 0.008)
    tap = osc(sweep(210.0, 120.0, t, 0.04)) * ad_env(t, 0.002, 0.018)
    finish_sfx("step", 0.6 * click / np.max(np.abs(click)) + tap, fout=0.01)


def sfx_whack():
    r = rng_for("whack")
    t = tvec(0.3)
    ft = sweep(180.0, 60.0, t, 0.12)
    body = (osc(ft) + 0.4 * osc(ft * 2.0)) * ad_env(t, 0.002, 0.08)
    crack = fft_band(r.standard_normal(len(t)), SR, 900.0, 4500.0, 2) * np.exp(-t / 0.018)
    ring = (np.sin(TAU * 523.0 * t) + 0.5 * np.sin(TAU * 1307.0 * t)) * ad_env(t, 0.002, 0.06)
    finish_sfx("whack", body + 0.6 * crack / np.max(np.abs(crack)) + 0.2 * ring, fout=0.02)


def sfx_bounce():
    r = rng_for("bounce")
    t = tvec(0.45)
    # fast drop, slower rise, with a damped spring wobble on top
    f = 235.0 * (1.0 + 1.35 * np.exp(-t / 0.022)) + 310.0 * (1.0 - np.exp(-t / 0.2))
    f *= 1.0 + 0.13 * np.exp(-t / 0.22) * np.sin(TAU * 11.5 * t)
    ph = TAU * np.cumsum(f) / SR
    tone = np.sin(ph) + 0.5 * np.sin(2 * ph) * np.exp(-t / 0.08) + 0.3 * np.sin(3 * ph) * np.exp(-t / 0.04)
    tone *= ad_env(t, 0.003, 0.17)
    click = fft_band(r.standard_normal(len(t)), SR, 2500.0, 9000.0, 2) * np.exp(-t / 0.004)
    thump = osc(sweep(130.0, 70.0, t, 0.06)) * ad_env(t, 0.002, 0.04)
    finish_sfx("bounce", tone + 0.25 * click / np.max(np.abs(click)) + 0.45 * thump, fout=0.03)


def bell(freq, dur, sr, tau, partials=((1.0, 1.0), (2.0, 0.45), (3.01, 0.22), (4.2, 0.12)), attack=0.003):
    t = tvec(dur, sr)
    out = np.zeros(len(t))
    for ratio, amp in partials:
        if freq * ratio < sr * 0.45:
            out += amp * np.sin(TAU * freq * ratio * t) * np.exp(-t / (tau / ratio ** 0.7))
    return out * np.minimum(t / attack, 1.0)


def sfx_checkpoint():
    n = int(round(0.7 * SR))
    x = np.zeros(n)
    t = tvec(0.7)
    for t0, m in ((0.0, 76), (0.15, 83)):
        note = bell(mtof(m), 0.7 - t0, SR, 0.22)
        tt = tvec(0.7 - t0)
        shim = (np.sin(TAU * mtof(m + 12) * 1.003 * tt) + np.sin(TAU * mtof(m + 12) * 0.997 * tt))
        shim = shim * 0.12 * (0.6 + 0.4 * np.sin(TAU * 17.0 * tt)) * ad_env(tt, 0.02, 0.2)
        shim += 0.05 * np.sin(TAU * mtof(m + 19) * tt) * ad_env(tt, 0.03, 0.16)
        place(x, t0, note + shim)
    finish_sfx("checkpoint", x, fout=0.05)


def grain(r, dur, lo, hi, tau):
    t = tvec(dur)
    g = fft_band(r.standard_normal(len(t)), SR, lo, hi, 2) * np.exp(-t / tau)
    return g / (np.max(np.abs(g)) + 1e-9)


def sfx_crumble():
    r = rng_for("crumble")
    n = int(round(0.7 * SR))
    t = tvec(0.7)
    x = np.zeros(n)
    for _ in range(70):
        t0 = r.uniform(0.0, 0.62)
        c = r.uniform(500.0, 3200.0)
        g = grain(r, r.uniform(0.012, 0.035), c * 0.6, c * 1.7, r.uniform(0.003, 0.009))
        place(x, t0, g, gain=r.uniform(0.25, 1.0) ** 2)
    rattle = fft_band(r.standard_normal(n), SR, 140.0, 520.0, 2)
    rattle *= (0.5 + 0.5 * np.sign(np.sin(TAU * 27.0 * t + 0.4 * np.sin(TAU * 3.0 * t)))) * 0.5
    rattle = fft_band(rattle, SR, None, 1500.0, 2)
    x = x + 0.55 * rattle / np.max(np.abs(rattle))
    x *= 0.55 + 0.45 * np.sin(np.pi * np.clip(t / 0.7, 0, 1)) ** 0.7
    finish_sfx("crumble", x, fin=0.004, fout=0.06)


def sfx_collapse():
    r = rng_for("collapse")
    n = int(round(0.9 * SR))
    t = tvec(0.9)
    rumble = fft_band(r.standard_normal(n), SR, 30.0, 190.0, 2)
    rumble = rumble / np.max(np.abs(rumble)) * ad_env(t, 0.02, 0.33)
    drop = osc(sweep(98.0, 27.0, t, 0.8)) * ad_env(t, 0.01, 0.38)
    mid = fft_band(r.standard_normal(n), SR, 200.0, 700.0, 2)
    mid = mid / np.max(np.abs(mid)) * ad_env(t, 0.005, 0.17)
    x = 0.9 * rumble + 0.8 * (drop + 0.3 * osc(sweep(196.0, 54.0, t, 0.8)) * ad_env(t, 0.01, 0.3)) + 0.7 * mid
    place(x, 0.0, grain(r, 0.04, 300.0, 2600.0, 0.012), gain=0.6)
    for _ in range(22):
        t0 = r.uniform(0.02, 0.5)
        c = 2400.0 * (1.0 - t0 / 0.6) + 350.0
        g = grain(r, r.uniform(0.015, 0.04), c * 0.6, c * 1.6, r.uniform(0.004, 0.012))
        place(x, t0, g, gain=0.5 * r.uniform(0.3, 1.0) * (1.0 - t0 / 0.6))
    finish_sfx("collapse", x, fin=0.003, fout=0.12)


def sfx_creak():
    r = rng_for("creak")
    dur = 0.35
    n = int(round(dur * SR))
    t = tvec(dur)
    # stick-slip impulse train with jittered period
    imp = np.zeros(n)
    pos = 0.0
    while pos < dur:
        rate = 52.0 + 50.0 * np.sin(np.pi * pos / dur) ** 1.3
        i = int(pos * SR)
        if i < n:
            imp[i] = r.uniform(0.6, 1.0)
        pos += (1.0 / rate) * r.uniform(0.9, 1.1)

    def kernel(scale):
        kt = tvec(0.03)
        k = np.zeros(len(kt))
        for fr, tau, amp in ((610.0, 0.006, 1.0), (1470.0, 0.004, 0.6), (2650.0, 0.0025, 0.35)):
            k += amp * np.sin(TAU * fr * scale * kt) * np.exp(-kt / tau)
        return k

    a = np.convolve(imp, kernel(1.0))[:n]
    b = np.convolve(imp, kernel(1.14))[:n]
    mix = 0.5 - 0.5 * np.cos(np.pi * t / dur)
    x = a * (1.0 - mix) + b * mix
    x = fft_band(x, SR, 250.0, 5000.0, 2)
    x *= np.minimum(t / 0.03, 1.0) * np.minimum((dur - t) / 0.09, 1.0)
    finish_sfx("creak", x, fin=0.004, fout=0.02)


def brass_bell(freq, dur, tau):
    t = tvec(dur)
    out = np.zeros(len(t))
    for k in range(1, 7):
        if freq * k < 16000.0:
            out += (1.0 / k ** 1.3) * np.sin(TAU * freq * k * t) * np.exp(-t / (tau / k ** 0.6))
    return out * np.minimum(t / 0.005, 1.0)


def sfx_finish():
    r = rng_for("finish")
    dur = 2.2
    n = int(round(dur * SR))
    x = np.zeros(n)
    for i, m in enumerate((72, 76, 79, 84)):
        place(x, 0.115 * i, brass_bell(mtof(m), 0.6, 0.16), gain=0.6)
    t_hit = 0.46
    for m, g in ((88, 0.6), (84, 0.45), (79, 0.4), (76, 0.35), (72, 0.4), (60, 0.45), (48, 0.5)):
        place(x, t_hit, brass_bell(mtof(m), dur - t_hit, 0.75), gain=g)
    penta = (96, 98, 100, 103, 105, 108)
    for _ in range(16):
        t0 = r.uniform(0.5, 1.75)
        f = mtof(penta[int(r.integers(0, len(penta)))])
        tt = tvec(0.35)
        place(x, t0, np.sin(TAU * f * tt) * ad_env(tt, 0.002, 0.09), gain=r.uniform(0.04, 0.1))
    y = x.copy()
    d = int(0.19 * SR)
    for k in range(1, 4):
        y[k * d:] += x[:n - k * d] * (0.3 ** k)
    finish_sfx("finish", y, fout=0.25)


def sfx_respawn():
    r = rng_for("respawn")
    dur = 0.3
    t = tvec(dur)
    fc = sweep(450.0, 5200.0, t, dur)
    wh = svf_bandpass(r.standard_normal(len(t)), fc, 2.5, SR)
    env = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 1.5
    zipt = osc(sweep(280.0, 1500.0, t, dur)) * env * 0.35
    finish_sfx("respawn", wh / np.max(np.abs(wh)) * env + zipt, fin=0.01, fout=0.03)


def sfx_tick():
    t = tvec(0.12)
    x = (np.sin(TAU * 880.0 * t) + 0.3 * np.sin(TAU * 1760.0 * t) * np.exp(-t / 0.01)) * ad_env(t, 0.0015, 0.028)
    finish_sfx("tick", x, fin=0.001)


def sfx_go():
    t = tvec(0.5)
    vib = 1.0 + 0.002 * np.sin(TAU * 6.0 * t)
    x = np.zeros(len(t))
    for fr, amp, tau in ((1760.0, 1.0, 0.16), (880.0, 0.5, 0.2), (2640.0, 0.3, 0.1), (3520.0, 0.18, 0.07), (1318.5, 0.25, 0.18)):
        x += amp * np.sin(TAU * fr * vib * t) * np.exp(-t / tau)
    x *= np.minimum(t / 0.003, 1.0)
    finish_sfx("go", x, fout=0.05)


def sfx_ui():
    t = tvec(0.06)
    x = osc(sweep(1250.0, 850.0, t, 0.03)) * ad_env(t, 0.001, 0.011)
    finish_sfx("ui", x, fin=0.0008, fout=0.005)


def sfx_beacon():
    r = rng_for("beacon")
    dur = 4.0
    t_hit = 2.7
    n = int(round(dur * SR))
    t = tvec(dur)
    u = np.clip(t / t_hit, 0.0, 1.0)
    after = np.exp(-np.maximum(t - t_hit, 0.0) / 0.12)
    # rising detuned stack: D2 -> D4
    f = mtof(38) * 2.0 ** (2.0 * u ** 1.3)
    swell = np.zeros(n)
    for ratio, amp, power in ((1.0, 1.0, 0.8), (1.5, 0.5, 1.8), (2.0, 0.6, 2.6), (3.0, 0.3, 3.2)):
        for cents in (-8.0, 7.0):
            fr = f * ratio * 2.0 ** (cents / 1200.0)
            swell += amp * osc(fr, SR, r.uniform(0, TAU)) * u ** power
    trem_rate = 4.0 + 13.0 * u ** 2
    swell *= (1.0 + 0.28 * osc(trem_rate)) * after
    riser = svf_bandpass(r.standard_normal(n), sweep(300.0, 6000.0, t, t_hit), 1.8, SR)
    riser = riser / np.max(np.abs(riser)) * u ** 2.5 * after
    x = 0.22 * swell + 0.35 * riser
    # arrival: D major add9 chord with shimmer
    tt = tvec(dur - t_hit)
    chord = np.zeros(len(tt))
    for m, g in ((38, 0.7), (50, 0.8), (57, 0.6), (62, 0.7), (66, 0.55), (69, 0.5), (76, 0.4), (78, 0.35), (86, 0.25)):
        fr = mtof(m)
        v = np.sin(TAU * fr * 1.0025 * tt + r.uniform(0, TAU)) + np.sin(TAU * fr * 0.9975 * tt + r.uniform(0, TAU))
        v += 0.3 * np.sin(TAU * fr * 2.0 * tt) * np.exp(-tt / 0.4)
        if m >= 66:
            v *= 0.65 + 0.35 * np.sin(TAU * r.uniform(5.0, 9.5) * tt + r.uniform(0, TAU))
        chord += g * v
    chord *= ad_env(tt, 0.012, 0.85)
    place(x, t_hit, chord, gain=0.3)
    place(x, t_hit, osc(sweep(130.0, 48.0, tvec(0.3), 0.2)) * ad_env(tvec(0.3), 0.003, 0.09), gain=0.8)
    place(x, t_hit, grain(r, 0.25, 3000.0, 12000.0, 0.06), gain=0.2)
    penta = (86, 88, 90, 93, 95, 98, 100, 102)
    for _ in range(22):
        t0 = r.uniform(t_hit, 3.75)
        pt = tvec(0.3)
        ping = np.sin(TAU * mtof(penta[int(r.integers(0, len(penta)))]) * pt) * ad_env(pt, 0.002, 0.08)
        place(x, t0, ping, gain=r.uniform(0.03, 0.08))
    finish_sfx("beacon", x, fin=0.02, fout=0.3)


# --------------------------------------------------------------------------
# music engine: everything is rendered into circular buffers, so note tails,
# delay and reverb wrap round to the start and the loop point is seamless.
# --------------------------------------------------------------------------
class Track:
    def __init__(self, name, seconds):
        self.name = name
        self.sr = MSR
        self.n = int(round(seconds * MSR))
        self.stems = {}
        self.rev = np.zeros((self.n, 2))
        self.dly = np.zeros(self.n)
        self.rng = rng_for(name)

    def add(self, stem, t0, sig, gain=1.0, pan=0.0, rev=0.0, dly=0.0):
        if len(sig) > self.n:
            raise ValueError("note longer than loop")
        if sig.ndim == 1:
            a = (pan + 1.0) * np.pi / 4.0
            sig = sig[:, None] * np.array([np.cos(a), np.sin(a)]) * np.sqrt(2.0)
        sig = sig * gain
        idx = (int(round(t0 * self.sr)) + np.arange(len(sig))) % self.n
        if stem not in self.stems:
            self.stems[stem] = np.zeros((self.n, 2))
        self.stems[stem][idx] += sig
        if rev:
            self.rev[idx] += sig * rev
        if dly:
            self.dly[idx] += sig.mean(axis=1) * dly

    def _theta(self):
        return TAU * np.arange(self.n // 2 + 1) / self.n

    def _delay(self, seconds, fb, damp_hz):
        """Circular ping-pong feedback delay evaluated exactly in the FFT domain."""
        d = int(round(seconds * self.sr))
        th = self._theta()
        f = np.arange(self.n // 2 + 1) * self.sr / self.n
        lp = 1.0 / (1.0 + (f / damp_hz) ** 2)
        z = np.exp(-1j * th * d) * lp
        spec = np.fft.rfft(self.dly)
        den = 1.0 - (fb * z) ** 2
        left = np.fft.irfft(spec * z / den, self.n)
        right = np.fft.irfft(spec * fb * z * z / den, self.n)
        return np.stack([left, right], axis=1)

    def _reverb(self, x, fb, damp_hz):
        """Circular Schroeder-style reverb (parallel damped combs + allpasses) in the FFT domain."""
        th = self._theta()
        f = np.arange(self.n // 2 + 1) * self.sr / self.n
        lp = 1.0 / (1.0 + 1j * f / damp_hz)
        combs = ((0.0297, 0.0371, 0.0411, 0.0437, 0.0533, 0.0617),
                 (0.0313, 0.0353, 0.0423, 0.0461, 0.0547, 0.0593))
        mono = x.mean(axis=1)
        out = np.zeros((self.n, 2))
        for ch in range(2):
            spec = np.fft.rfft(0.6 * x[:, ch] + 0.4 * mono)
            h = np.zeros(len(th), dtype=complex)
            for sec in combs[ch]:
                z = np.exp(-1j * th * int(round(sec * self.sr)))
                h += z / (1.0 - fb * lp * z)
            h /= len(combs[ch])
            for sec, g in ((0.0051 + 0.0004 * ch, 0.6), (0.0017 + 0.0002 * ch, 0.6), (0.0113, 0.5)):
                z = np.exp(-1j * th * int(round(sec * self.sr)))
                h *= (-g + z) / (1.0 - g * z)
            out[:, ch] = np.fft.irfft(spec * h, self.n)
        return out

    def render(self, delay_s, delay_fb, rev_fb, rev_gain, rev_damp=3200.0, dly_damp=3500.0):
        dry = sum(self.stems.values())
        echo = self._delay(delay_s, delay_fb, dly_damp)
        wet = self._reverb(self.rev + 0.5 * echo, rev_fb, rev_damp)
        mix = dry + echo + rev_gain * wet
        for ch in range(2):  # remove sub-sonic content / DC, circularly
            mix[:, ch] = fft_band(mix[:, ch], self.sr, 28.0, None, 2, circular=True)
        rms = np.sqrt(np.mean(mix ** 2))
        scale = 10.0 ** (MUSIC_RMS_DB / 20.0) / rms
        for stem in sorted(self.stems):
            print("    stem %-8s rms %6.1f dBFS" % (stem, db(np.sqrt(np.mean(self.stems[stem] ** 2)) * scale)))
        mix *= scale
        # memoryless soft knee so rare peaks never clip (keeps the loop seamless)
        knee = 0.6
        span = MUSIC_PEAK_CEIL - knee
        mag = np.abs(mix)
        over = mag > knee
        mix[over] = np.sign(mix[over]) * (knee + span * np.tanh((mag[over] - knee) / span))
        write_wav(self.name, mix, self.sr, loop=True)
        print("  %-16s %6.2f s  rms %6.2f dBFS  peak %6.2f dBFS" % (
            self.name + ".wav", self.n / self.sr, db(np.sqrt(np.mean(mix ** 2))), db(np.max(np.abs(mix)))))


def v_pad(r, freq, dur, att=1.2, rel=2.0, bright=0.22):
    n = int((dur + rel) * MSR)
    t = np.arange(n) / MSR
    env = np.ones(n)
    a = int(att * MSR)
    q = int(rel * MSR)
    env[:a] = 0.5 - 0.5 * np.cos(np.pi * np.arange(a) / a)
    env[-q:] = 0.5 + 0.5 * np.cos(np.pi * np.arange(q) / q)

    def voice(cents):
        f = freq * 2.0 ** (cents / 1200.0)
        v = np.sin(TAU * f * t + r.uniform(0, TAU))
        v += bright * np.sin(TAU * 2 * f * t + r.uniform(0, TAU))
        v += bright * 0.3 * np.sin(TAU * 3 * f * t + r.uniform(0, TAU))
        return v

    left = voice(-6.0) + 0.7 * voice(2.0)
    right = voice(6.0) + 0.7 * voice(-2.0)
    lfo = 1.0 + 0.12 * np.sin(TAU * r.uniform(0.12, 0.3) * t + r.uniform(0, TAU))
    loud = (220.0 / freq) ** 0.35
    return np.stack([left, right], axis=1) * (env * lfo * loud)[:, None]


def v_pluck(freq, dur, tau=0.35, bright=0.55):
    t = np.arange(int(dur * MSR)) / MSR
    out = np.zeros(len(t))
    for k in range(1, 6):
        if freq * k < MSR * 0.42:
            out += (bright ** (k - 1)) / k * np.sin(TAU * freq * k * t) * np.exp(-t * k / tau)
    out *= np.minimum(t / 0.003, 1.0) * np.minimum((t[-1] - t) / 0.02, 1.0)
    return out * (330.0 / freq) ** 0.3


def v_bass(freq, dur, punch=0.5):
    n = int((dur + 0.06) * MSR)
    t = np.arange(n) / MSR
    s = np.sin(TAU * freq * t) + 0.3 * np.sin(TAU * 2 * freq * t) + 0.1 * np.sin(TAU * 3 * freq * t)
    env = np.minimum(t / 0.008, 1.0) * (1.0 - punch + punch * np.exp(-t / 0.18))
    env *= np.clip((dur + 0.05 - t) / 0.05, 0.0, 1.0)
    return np.tanh(1.4 * s * env) / 1.4


def v_lead(freq, dur):
    n = int((dur + 0.1) * MSR)
    t = np.arange(n) / MSR
    vib = 1.0 + 0.0035 * np.sin(TAU * 5.2 * t) * np.clip((t - 0.15) / 0.25, 0.0, 1.0)
    ph = TAU * np.cumsum(freq * vib) / MSR
    s = np.sin(ph) + 0.16 * np.sin(3 * ph) + 0.05 * np.sin(5 * ph) + 0.1 * np.sin(2 * ph)
    env = np.minimum(t / 0.012, 1.0) * (0.55 + 0.45 * np.exp(-t / 0.5))
    env *= np.clip((dur + 0.09 - t) / 0.09, 0.0, 1.0)
    return s * env


def v_bell(freq, dur, tau):
    return bell(freq, dur, MSR, tau, partials=((1.0, 1.0), (2.0, 0.3), (3.0, 0.12), (4.2, 0.05)), attack=0.004)


def v_noise_hit(r, dur, lo, hi, tau, attack=0.001):
    t = np.arange(int(dur * MSR)) / MSR
    g = fft_band(r.standard_normal(len(t)), MSR, lo, hi, 3) * ad_env(t, attack, tau)
    return g / np.max(np.abs(g))


def v_kick():
    t = np.arange(int(0.28 * MSR)) / MSR
    k = osc(48.0 + 80.0 * np.exp(-t / 0.028), MSR) * ad_env(t, 0.002, 0.1)
    k[-200:] *= np.linspace(1.0, 0.0, 200)
    return k


def v_clap(r):
    t = np.arange(int(0.22 * MSR)) / MSR
    env = np.zeros(len(t))
    for t0 in (0.0, 0.011, 0.023):
        env += np.where(t >= t0, np.exp(-(t - t0) / 0.006), 0.0) * 0.6
    env += np.where(t >= 0.023, np.exp(-(t - 0.023) / 0.055), 0.0)
    g = fft_band(r.standard_normal(len(t)), MSR, 900.0, 3600.0, 2) * env
    g[-200:] *= np.linspace(1.0, 0.0, 200)
    return g / np.max(np.abs(g))


def v_cog():
    t = np.arange(int(0.06 * MSR)) / MSR
    return (np.sin(TAU * 2300.0 * t) + 0.5 * np.sin(TAU * 3470.0 * t)) * ad_env(t, 0.0008, 0.009)


# --------------------------------------------------------------------------
# verification
# --------------------------------------------------------------------------
SFX_SPEC = {"jump": 0.18, "land": 0.2, "bounce": 0.45, "checkpoint": 0.7, "crumble": 0.7, "collapse": 0.9,
            "creak": 0.35, "finish": 2.2, "respawn": 0.3, "tick": 0.12, "go": 0.5, "ui": 0.06, "beacon": 4.0,
            "whack": 0.3, "step": 0.07}
MUSIC = ()  # the score lives in tools/gen_music.py now


def read_wav(name):
    with wave.open(os.path.join(OUT, name + ".wav"), "rb") as w:
        ch, sw, sr, n = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
        x = np.frombuffer(w.readframes(n), dtype="<i2").astype(np.float64) / 32768.0
    return x.reshape(-1, ch), sr, sw


def verify():
    ok = True
    total = 0
    print("verify:")
    for name, want in SFX_SPEC.items():
        x, sr, sw = read_wav(name)
        total += os.path.getsize(os.path.join(OUT, name + ".wav"))
        dur = len(x) / sr
        peak = db(np.max(np.abs(x)))
        edge = max(abs(x[0, 0]), abs(x[-1, 0]))
        good = (sr == SR and sw == 2 and x.shape[1] == 1 and abs(dur - want) < 0.02 and
                abs(peak - SFX_PEAK_DB) < 0.2 and edge < 0.002 and np.all(np.isfinite(x)))
        ok &= bool(good)
        print("  %-16s %5.2f s peak %6.2f dB rms %6.1f dB edge %.5f %s" % (
            name, dur, peak, db(np.sqrt(np.mean(x ** 2))), edge, "ok" if good else "FAIL"))
    for name in MUSIC:
        x, sr, sw = read_wav(name)
        total += os.path.getsize(os.path.join(OUT, name + ".wav"))
        dur = len(x) / sr
        peak = db(np.max(np.abs(x)))
        rms = db(np.sqrt(np.mean(x ** 2)))
        # loop continuity: the step across the wrap must look like any other step
        wrap_step = np.max(np.abs(x[0] - x[-1]))
        steps = np.max(np.abs(np.diff(x, axis=0)), axis=1)
        p999 = np.quantile(steps, 0.999)
        k = int(0.005 * sr)
        seam = np.concatenate([x[-k:], x[:k]])
        seam_step = np.max(np.abs(np.diff(seam, axis=0)))
        rms_tail = db(np.sqrt(np.mean(x[-k:] ** 2)))
        rms_head = db(np.sqrt(np.mean(x[:k] ** 2)))
        # curvature across the seam (second difference) must also be ordinary
        curv = np.max(np.abs(np.diff(x, n=2, axis=0)), axis=1)
        c999 = np.quantile(curv, 0.999)
        seam_curv = np.max(np.abs(np.diff(seam[k - 3:k + 3], n=2, axis=0)))
        good = (sw == 2 and 40.0 <= dur <= 64.0 and peak < -1.0 and abs(rms - MUSIC_RMS_DB) < 1.0 and
                wrap_step <= p999 * 1.5 and seam_curv <= c999 * 1.5 and np.all(np.isfinite(x)))
        print("  %-16s seam curvature %.5f (p99.9 %.5f)" % ("", seam_curv, c999))
        ok &= bool(good)
        print("  %-16s %5.2f s %d Hz %dch peak %6.2f dB rms %6.2f dB | wrap step %.5f (p99.9 step %.5f, "
              "seam max %.5f) last5ms %.1f dB first5ms %.1f dB %s" % (
                  name, dur, sr, x.shape[1], peak, rms, wrap_step, p999, seam_step, rms_tail, rms_head,
                  "ok" if good else "FAIL"))
    print("  total size %.2f MB %s" % (total / 1e6, "ok" if total < 25e6 else "FAIL"))
    ok &= total < 25e6
    print("RESULT: " + ("ALL OK" if ok else "PROBLEMS FOUND"))
    return ok


def main():
    args = set(sys.argv[1:])
    if "--verify" not in args:
        if "--music" not in args:
            print("effects:")
            for fn in (sfx_jump, sfx_land, sfx_whack, sfx_bounce, sfx_checkpoint, sfx_crumble, sfx_collapse,
                       sfx_creak, sfx_finish, sfx_respawn, sfx_tick, sfx_go, sfx_ui, sfx_beacon, sfx_step):
                fn()
    sys.exit(0 if verify() else 1)


if __name__ == "__main__":
    main()
