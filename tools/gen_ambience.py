#!/usr/bin/env python3
"""Jump Circuit - map soundscapes (ambience) generator.

Synthesises the ambience of every map into <project>/audio/:
  * beds      amb_<theme>.ogg            seamless stereo loops (Ogg Vorbis, 32 kHz)
  * one-shots amb_<theme>_<event>_<i>.ogg  mono 44.1 kHz clips that sound/soundscape.gd
                                           schedules at random around the listener
Everything is original: built from maths and seeded noise with the helpers in
tools/gen_audio.py (no samples, no third-party assets).  See docs/AUDIO_AMBIENCE.md.

Usage (from anywhere):
    python tools/gen_ambience.py              # generate everything, then verify
    python tools/gen_ambience.py --verify     # only verify the files on disk
    python tools/gen_ambience.py --beds       # only the beds
    python tools/gen_ambience.py --shots      # only the one-shots
    python tools/gen_ambience.py --only=reef  # only names containing "reef" (no full verify)
then run Godot once with --import so it picks new files up.

Beds are rendered into circular buffers: every event is mixed in at its sample index
modulo the loop length, noise filters, reverbs and the moving (STFT) filters work over
the whole loop, and every modulation completes a whole number of cycles, so the loop
point is seamless.  Deterministic: each sound has its own RNG (SEED + CRC of its name)
and the Ogg stream serial is pinned, so re-running gives bit-identical files.
Requires numpy and soundfile.
"""
import os
import struct
import sys
import zlib

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_audio as ga  # noqa: E402  (shared helpers: osc, sweep, ad_env, fft_band, bell, place, write_ogg ...)

SR = ga.SR            # one-shots: 44.1 kHz mono
BSR = 32000           # beds: 32 kHz stereo
TAU = ga.TAU
OUT = ga.OUT
BED_QUALITY = 0.85    # libsndfile Vorbis compression level (0 best .. 1 smallest)
SHOT_QUALITY = 0.55
SHOT_PEAK_DB = -3.0
BED_CEIL = 10.0 ** (-4.0 / 20.0)   # soft-knee ceiling for beds (-4 dBFS)
SIZE_BUDGET = 10.0e6
place = ga.place


def rng(name):
    return ga.rng_for("amb_" + name)


# ==========================================================================
# generic helpers
# ==========================================================================
def tv(dur, sr=SR):
    return np.arange(int(round(dur * sr))) / sr


def zeros(dur, sr=SR):
    return np.zeros(int(round(dur * sr)))


def lp(x, hz, order=2, sr=SR):
    return ga.fft_band(x, sr, None, hz, order)


def hp(x, hz, order=2, sr=SR):
    return ga.fft_band(x, sr, hz, None, order)


def bp(x, lo, hi, order=2, sr=SR):
    return ga.fft_band(x, sr, lo, hi, order)


def unit(x):
    return x / (np.max(np.abs(x)) + 1e-12)


def rmsn(x):
    return x / (np.sqrt(np.mean(x ** 2)) + 1e-12)


def rcos_env(n, att, rel, sr=SR):
    """Flat envelope with raised-cosine attack / release (seconds)."""
    e = np.ones(n)
    a = min(max(int(att * sr), 1), n)
    b = min(max(int(rel * sr), 1), n)
    e[:a] *= 0.5 - 0.5 * np.cos(np.pi * np.arange(a) / a)
    e[n - b:] *= 0.5 + 0.5 * np.cos(np.pi * np.arange(b) / b)
    return e


def pts_env(pts, n):
    """Piecewise-linear curve through (u, value) points, u in 0..1 over n samples."""
    u = np.arange(n) / max(n - 1, 1)
    return np.interp(u, [p[0] for p in pts], [p[1] for p in pts])


def contour(pts, n, sr=SR, smooth_s=0.004):
    """Pitch contour through (u, hz) points, interpolated in log-frequency and smoothed."""
    u = np.arange(n) / max(n - 1, 1)
    f = np.exp(np.interp(u, [p[0] for p in pts], [np.log(p[1]) for p in pts]))
    k = int(smooth_s * sr)
    if k > 2 and n > 2 * k:
        w = np.hanning(k)
        w /= w.sum()
        f = np.convolve(np.pad(f, (k, k), mode="edge"), w, mode="same")[k:-k]
    return f


def tone(f, harm=((1, 1.0),), sr=SR, phase=0.0):
    """Additive tone on a per-sample frequency array; partials above 0.45 sr are muted."""
    ph = TAU * np.cumsum(f) / sr + phase
    out = np.zeros(len(f))
    for k, a in harm:
        out += a * np.sin(k * ph) * (k * f < 0.45 * sr)
    return out


def modal(freqs, amps, taus, dur, sr=SR, att=0.0008, r=None):
    """Sum of exponentially decaying sine modes (struck metal, wood, glass)."""
    t = tv(dur, sr)
    out = np.zeros(len(t))
    for f, a, tau in zip(freqs, amps, taus):
        if f < 0.45 * sr:
            ph = r.uniform(0, TAU) if r is not None else 0.0
            out += a * np.sin(TAU * f * t + ph) * np.exp(-t / tau)
    # a release fade, so a mode cut off by `dur` never ends in a click
    return out * np.minimum(t / att, 1.0) * rcos_env(len(t), 0.0, min(0.3 * dur, 0.4), sr)


def noise_hit(r, dur, lo, hi, tau, sr=SR, att=0.0005):
    t = tv(dur, sr)
    g = ga.fft_band(r.standard_normal(len(t)), sr, lo, hi, 2) * ga.ad_env(t, att, tau)
    return unit(g)


def smooth(r, n, hz, sr=SR):
    """Circular smooth random curve (std 1) with content below about `hz`."""
    spec = np.fft.rfft(r.standard_normal(n))
    f = np.fft.rfftfreq(n, 1.0 / sr)
    spec *= np.exp(-(f / hz) ** 2)
    spec[0] = 0.0
    y = np.fft.irfft(spec, n)
    return y / (np.std(y) + 1e-12)


def pink(r, n, sr=SR, slope=-0.5, floor_hz=20.0):
    """Circular coloured noise: amplitude spectrum ~ f^slope (pink -0.5, brown -1)."""
    spec = np.fft.rfft(r.standard_normal(n))
    f = np.fft.rfftfreq(n, 1.0 / sr)
    spec *= (np.maximum(f, floor_hz) / 1000.0) ** slope
    spec[0] = 0.0
    return rmsn(np.fft.irfft(spec, n))


def conv(x, h):
    """Linear convolution via FFT (output len(x)+len(h)-1)."""
    n = len(x) + len(h) - 1
    m = 1 << (n - 1).bit_length()
    return np.fft.irfft(np.fft.rfft(x, m) * np.fft.rfft(h, m), m)[:n]


def make_ir(r, sr, t60, damp, predelay=0.0, length=None, bright_t60=0.3):
    """Diffuse reverb impulse response: noise decaying at t60 below `damp` Hz and
    bright_t60 * t60 above it, with a soft 8 ms build-up; unit energy."""
    n = int((length if length else t60 * 1.15) * sr)
    t = np.arange(n) / sr
    nz = r.standard_normal(n)
    low = ga.fft_band(nz, sr, None, damp, 1, circular=True)
    h = low * np.exp(-6.91 * t / t60) + (nz - low) * np.exp(-6.91 * t / (t60 * bright_t60))
    h *= 1.0 - np.exp(-t / 0.008)
    d = int(predelay * sr)
    h = np.concatenate([np.zeros(d), h])[:n]
    return h / np.sqrt(np.sum(h ** 2))


def reverb(x, r, t60, damp, wet, sr=SR, predelay=0.01):
    """Mono one-shot reverb: returns dry*(1-wet/2) + wet*reverb, extended by the tail."""
    h = make_ir(r, sr, t60, damp, predelay)
    y = conv(x, h)
    dry = np.concatenate([x, np.zeros(len(y) - len(x))])
    return dry * (1.0 - 0.5 * wet) + wet * y


def trim(x, db_floor=-62.0, sr=SR, fout=0.08):
    """Cut the silent tail (below db_floor of the peak) and fade the end."""
    env = np.abs(x)
    thr = np.max(env) * 10.0 ** (db_floor / 20.0)
    idx = np.nonzero(env > thr)[0]
    end = min(len(x), (idx[-1] if len(idx) else len(x) - 1) + int(fout * sr))
    y = x[:end].copy()
    k = min(int(fout * sr), len(y))
    y[-k:] *= np.linspace(1.0, 0.0, k) ** 2
    return y


def far(x, r, lp_hz, t60, wet, damp=2500.0, hp_hz=None, predelay=0.02, sr=SR):
    """Distance: dull the top, add a room / landscape tail."""
    y = lp(x, lp_hz, 2, sr)
    if hp_hz:
        y = hp(y, hp_hz, 2, sr)
    return reverb(y, r, t60, damp, wet, sr, predelay)


def stick_slip(r, dur, rate_fn, modes, bend=1.0, sr=SR):
    """Creak: a jittered impulse train (rate_fn(u) Hz, u = 0..1) through damped resonances,
    cross-faded into a copy with the resonances scaled by `bend` (the creak bends in pitch)."""
    n = int(dur * sr)
    imp = np.zeros(n)
    pos = 0.0
    while pos < dur:
        i = int(pos * sr)
        imp[i] = r.uniform(0.5, 1.0) * (1.0 if r.random() > 0.08 else 1.8)
        pos += (1.0 / max(rate_fn(pos / dur), 1.0)) * r.uniform(0.85, 1.15)

    def kernel(scale):
        kt = tv(0.2, sr)
        k = np.zeros(len(kt))
        for fr, tau, amp in modes:
            k += amp * np.sin(TAU * fr * scale * kt) * np.exp(-kt / tau)
        return k

    a = np.convolve(imp, kernel(1.0))[:n]
    b = np.convolve(imp, kernel(bend))[:n]
    mix = 0.5 - 0.5 * np.cos(np.pi * np.arange(n) / n)
    return a * (1.0 - mix) + b * mix


def doppler_pass(src, sr, v, d, t_close, c=343.0):
    """Render a source moving past the listener in a straight line (speed v, closest
    distance d, closest approach heard at t_close s): the emission-time signal `src` is
    time-warped by the propagation delay (so its pitch and rhythm shift) and scaled by 1/r.
    Returns (signal, closeness 0..1) on the arrival-time grid of the same length."""
    n = len(src)
    e = np.arange(n) / sr
    x = v * (e - t_close)
    rr = np.sqrt(x ** 2 + d ** 2)
    arr = e + (rr - d) / c
    ta = np.arange(n) / sr
    ee = np.interp(ta, arr, e)
    y = np.interp(ee, e, src)
    rr_a = np.interp(ee, e, rr)
    return y * (d / rr_a), d / rr_a


# ==========================================================================
# circular (bed) helpers - everything wraps round the loop
# ==========================================================================
HOP = 512
NFFT = 2048


def loop_len(seconds):
    n = int(round(seconds * BSR))
    return n - n % HOP


def cband(x, lo=None, hi=None, order=2, sr=BSR):
    return ga.fft_band(x, sr, lo, hi, order, circular=True)


def cconv(x, h):
    n = len(x)
    if len(h) > n:
        h = np.pad(h, (0, (-len(h)) % n)).reshape(-1, n).sum(axis=0)
    return np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(h, n), n)


def csine(f, n, sr=BSR, phase=0.0):
    """Sine whose frequency is rounded so it completes whole cycles in the loop."""
    k = max(1, int(round(f * n / sr)))
    return np.sin(TAU * k * np.arange(n) / n + phase)


def cosc(freq, sr=BSR, phase=0.0):
    """Oscillator on a per-sample frequency array, rescaled to whole cycles in the loop."""
    cyc = np.sum(freq) / sr
    k = max(1.0, np.round(cyc))
    return np.sin(TAU * np.cumsum(freq * (k / cyc)) / sr + phase)


def cbeat(n, cycles, phase=0.0):
    """Slow periodic modulation with a whole number of cycles per loop (0..1)."""
    return 0.5 + 0.5 * np.sin(TAU * cycles * np.arange(n) / n + phase)


def gusts(r, n, hz, sr=BSR, bias=0.0, sharp=1.3):
    """Circular gust envelope 0..1."""
    return 0.5 + 0.5 * np.tanh(sharp * smooth(r, n, hz, sr) + bias)


def stft_shape(x, gain, sr=BSR):
    """Circular time-varying filter: gain(t_frames[:, None], f[None, :]) -> magnitude per
    frame and bin, applied by windowed overlap-add over the loop.  Gains must be smooth
    in frequency (resonances wider than ~30 Hz) and time."""
    n = len(x)
    frames = n // HOP
    w = np.hanning(NFFT + 1)[:-1]
    idx = (np.arange(frames)[:, None] * HOP + np.arange(NFFT)[None, :]) % n
    spec = np.fft.rfft(x[idx] * w, axis=1)
    tc = ((np.arange(frames) * HOP + NFFT // 2) % n) / sr
    f = np.fft.rfftfreq(NFFT, 1.0 / sr)
    spec *= gain(tc[:, None], f[None, :])
    y = np.fft.irfft(spec, NFFT, axis=1)
    out = np.zeros(n)
    for k in range(frames):
        i0 = k * HOP
        if i0 + NFFT <= n:
            out[i0:i0 + NFFT] += y[k]
        else:
            out[idx[k]] += y[k]
    return out / (w.sum() / HOP)


def at(env, t, sr=BSR):
    """Sample a per-sample loop envelope at times t (s), wrapping."""
    return env[(np.asarray(t) * sr).astype(np.int64) % len(env)]


def resonance(fc, f, q, floor=0.0):
    bw = fc / q
    return floor + 1.0 / (1.0 + ((f - fc) / bw) ** 2)


def st(sig, pan):
    a = (pan + 1.0) * np.pi / 4.0
    return sig[:, None] * np.array([np.cos(a), np.sin(a)]) * np.sqrt(2.0)


def density_times(r, T, count, dens, sr=BSR):
    """`count` random times in [0, T) drawn with probability following the loop curve dens."""
    out = []
    mx = np.max(dens)
    while len(out) < count:
        t = r.uniform(0.0, T)
        if r.uniform(0.0, mx) <= at(dens, t, sr):
            out.append(t)
    return sorted(out)


def spaced_times(r, T, lo, hi):
    """Irregular event times with gaps in [lo, hi] that tile the loop exactly."""
    gaps = []
    while sum(gaps) < T:
        gaps.append(r.uniform(lo, hi))
    if sum(gaps) - T > gaps[-1] * 0.5 and len(gaps) > 1:
        gaps.pop()
    gaps = np.array(gaps) * (T / sum(gaps))
    return np.concatenate([[0.0], np.cumsum(gaps)[:-1]]) + r.uniform(0, lo)


class Mix:
    """A circular stereo loop assembled from named stems, each with its own send to a shared
    circular reverb.  render() balances the stems to a table of relative levels (dB RMS over
    the loop), so a sparse stem (birds) is set by its loop-average level."""

    def __init__(self, name, seconds):
        self.name = name
        self.sr = BSR
        self.n = loop_len(seconds)
        self.T = self.n / BSR
        self.stems = {}
        self.sends = {}
        self.r = rng(name)

    def add(self, stem, t0, sig, gain=1.0, pan=0.0, rev=0.0):
        if sig.ndim == 1:
            sig = st(sig, pan)
        if len(sig) > self.n:
            raise ValueError("event longer than loop")
        sig = sig * gain
        idx = (int(round(t0 * self.sr)) + np.arange(len(sig))) % self.n
        self.stems.setdefault(stem, np.zeros((self.n, 2)))[idx] += sig
        if rev:
            self.sends.setdefault(stem, np.zeros((self.n, 2)))[idx] += sig * rev

    def add_loop(self, stem, sig, gain=1.0, rev=0.0):
        """A whole-loop layer: stereo (n, 2) or mono (centred)."""
        if sig.ndim == 1:
            sig = np.stack([sig, sig], axis=1)
        self.stems.setdefault(stem, np.zeros((self.n, 2)))
        self.stems[stem] += sig * gain
        if rev:
            self.sends.setdefault(stem, np.zeros((self.n, 2)))
            self.sends[stem] += sig * gain * rev

    def render(self, rms_db, levels, t60=1.2, damp=2500.0, wet=0.5, predelay=0.02, hp_hz=32.0, lp_hz=9000.0,
               quality=BED_QUALITY):
        if set(levels) != set(self.stems):
            raise ValueError("%s: levels for %s, stems %s" % (self.name, sorted(levels), sorted(self.stems)))
        for s in self.stems:
            g = 10.0 ** (levels[s] / 20.0) / (np.sqrt(np.mean(self.stems[s] ** 2)) + 1e-12)
            self.stems[s] *= g
            if s in self.sends:
                self.sends[s] *= g
        wetsig = np.zeros((self.n, 2))
        if self.sends:
            send = sum(self.sends.values())
            r = rng(self.name + "_ir")
            h = [make_ir(r, BSR, t60, damp, predelay) for _ in range(2)]
            mono = send.mean(axis=1)
            for ch in range(2):
                wetsig[:, ch] = cconv(0.7 * send[:, ch] + 0.3 * mono, h[ch])
        mix = sum(self.stems.values()) + wet * wetsig
        for ch in range(2):
            mix[:, ch] = cband(mix[:, ch], hp_hz, lp_hz, 2)   # no sub rumble, no fizzy top
        scale = 10.0 ** (rms_db / 20.0) / np.sqrt(np.mean(mix ** 2))
        levels = ["%s %.0f" % (s, ga.db(np.sqrt(np.mean(v ** 2)) * scale)) for s, v in sorted(self.stems.items())]
        levels.append("reverb %.0f" % ga.db(np.sqrt(np.mean((wet * wetsig) ** 2)) * scale))
        print("    stems (dBFS): " + ", ".join(levels))
        mix *= scale
        knee = BED_CEIL * 0.7
        span = BED_CEIL - knee
        mag = np.abs(mix)
        over = mag > knee
        mix[over] = np.sign(mix[over]) * (knee + span * np.tanh((mag[over] - knee) / span))
        path = ga.write_ogg(self.name, mix, BSR, quality)
        pin_ogg(path, zlib.crc32(self.name.encode("ascii")))
        print("  %-24s %5.1f s  rms %6.2f dBFS  peak %6.2f dBFS  %4d KB" % (
            self.name + ".ogg", self.T, ga.db(np.sqrt(np.mean(mix ** 2))), ga.db(np.max(np.abs(mix))),
            os.path.getsize(path) // 1024))


# ==========================================================================
# Ogg determinism: libsndfile picks a random stream serial; pin it and fix the CRCs
# ==========================================================================
def _crc_table():
    tab = []
    for i in range(256):
        c = i << 24
        for _ in range(8):
            c = ((c << 1) ^ 0x04C11DB7) if c & 0x80000000 else (c << 1)
            c &= 0xFFFFFFFF
        tab.append(c)
    return tab


_CRC = _crc_table()


def _ogg_crc(data):
    crc = 0
    tab = _CRC
    for b in data:
        crc = ((crc << 8) & 0xFFFFFFFF) ^ tab[((crc >> 24) & 0xFF) ^ b]
    return crc


def pin_ogg(path, serial):
    with open(path, "rb") as fh:
        data = bytearray(fh.read())
    pos = 0
    while pos < len(data):
        if data[pos:pos + 4] != b"OggS":
            raise ValueError(path + ": bad Ogg page")
        nseg = data[pos + 26]
        size = 27 + nseg + sum(data[pos + 27:pos + 27 + nseg])
        data[pos + 14:pos + 18] = struct.pack("<I", serial & 0xFFFFFFFF)
        data[pos + 22:pos + 26] = b"\0\0\0\0"
        data[pos + 22:pos + 26] = struct.pack("<I", _ogg_crc(bytes(data[pos:pos + size])))
        pos += size
    with open(path, "wb") as fh:
        fh.write(bytes(data))


def lead_trim(x, db_floor=-50.0, sr=SR):
    """Drop leading silence (so a clip sounds the moment the runtime plays it)."""
    idx = np.nonzero(np.abs(x) > np.max(np.abs(x)) * 10.0 ** (db_floor / 20.0))[0]
    return x[max(int(idx[0]) - int(0.005 * sr), 0):] if len(idx) else x


def save_shot(name, x, fin=0.003, fout=0.03):
    x = lead_trim(x)
    x = ga.norm_peak(ga.fade(trim(x, fout=max(fout, 0.05)), SR, fin, fout), SHOT_PEAK_DB)
    path = ga.write_ogg(name, x, SR, SHOT_QUALITY)
    pin_ogg(path, zlib.crc32(name.encode("ascii")))
    print("  %-30s %5.2f s  %3d KB" % (name + ".ogg", len(x) / SR, os.path.getsize(path) // 1024))


# ==========================================================================
# birds (used by the garden one-shots and the far birdsong in the garden beds)
# ==========================================================================
BIRD_HARM = ((1, 1.0), (2, 0.07), (3, 0.018))


def syl(pts, dur, amp=None, harm=BIRD_HARM, fm=None, att=0.006, rel=0.012, sr=SR, smooth_s=0.003):
    """One bird syllable: a near-pure whistle following a pitch contour, optionally with
    fast FM (rate Hz, depth fraction) for buzzy notes."""
    n = int(dur * sr)
    f = contour(pts, n, sr, smooth_s)
    if fm:
        t = np.arange(n) / sr
        f = f * (1.0 + fm[1] * np.sin(TAU * fm[0] * t))
    s = tone(f, harm, sr)
    e = rcos_env(n, att, rel, sr)
    if amp is not None:
        e *= pts_env(amp, n)
    return s * e


def bird_feebee(r, sr=SR):
    """Two clear whistles, the second lower with a waver (a chickadee's 'fee-bee')."""
    k = r.uniform(0.93, 1.07)
    x = zeros(1.25, sr)
    a = syl([(0, 3950 * k), (0.25, 4060 * k), (1, 3930 * k)], r.uniform(0.26, 0.32),
            amp=[(0, 0.25), (0.3, 1), (1, 0.75)], sr=sr)
    b = syl([(0, 3420 * k), (0.4, 3390 * k), (0.8, 3300 * k), (1, 3190 * k)], r.uniform(0.3, 0.37),
            amp=[(0, 0.35), (0.15, 1), (0.8, 0.8), (1, 0.3)], fm=(24.0, 0.005), sr=sr)
    t0 = r.uniform(0.02, 0.08)
    place(x, t0, a, sr)
    place(x, t0 + len(a) / sr + r.uniform(0.04, 0.09), b, sr, 0.85)
    return x


def bird_robin(r, sr=SR):
    """Caroling phrases: groups of two or three slurred notes around 2-3.5 kHz."""
    x = zeros(2.2, sr)
    t = r.uniform(0.02, 0.06)
    for _ in range(int(r.integers(5, 8))):
        for _ in range(int(r.integers(2, 4))):
            d = r.uniform(0.07, 0.13)
            f0, f1, f2 = r.uniform(1900, 2600), r.uniform(2700, 3600), r.uniform(2000, 3000)
            fm = (r.uniform(60, 90), 0.025) if r.random() < 0.3 else None
            s = syl([(0, f0), (r.uniform(0.3, 0.6), f1), (1, f2)], d, amp=[(0, 0.4), (0.3, 1), (1, 0.5)],
                    fm=fm, sr=sr, harm=((1, 1.0), (2, 0.12), (3, 0.03)))
            place(x, t, s, sr, r.uniform(0.6, 1.0))
            t += d + r.uniform(0.008, 0.02)
        t += r.uniform(0.1, 0.22)
        if t > 1.9:
            break
    return x


def bird_cardinal(r, sr=SR):
    """Loud slurred down-whistles repeated and accelerating ('cheer cheer cheer'),
    sometimes finished with quick up-slurs."""
    x = zeros(2.0, sr)
    t = r.uniform(0.02, 0.06)
    gap = r.uniform(0.26, 0.32)
    top = r.uniform(3900, 4400)
    for i in range(int(r.integers(3, 6))):
        d = r.uniform(0.15, 0.19)
        s = syl([(0, top), (0.25, top * 0.85), (1, r.uniform(1750, 2000))], d,
                amp=[(0, 0.5), (0.2, 1), (1, 0.4)], sr=sr, harm=((1, 1.0), (2, 0.1), (3, 0.02)))
        place(x, t, s, sr, 1.0 - 0.06 * i)
        t += gap
        gap *= 0.9
    if r.random() < 0.6:
        for _ in range(3):
            s = syl([(0, 1800), (1, r.uniform(3600, 4000))], 0.09, amp=[(0, 0.4), (0.7, 1), (1, 0.6)], sr=sr)
            place(x, t, s, sr, 0.8)
            t += 0.13
    return x


def bird_warbler(r, sr=SR):
    """A rising series of buzzy notes (fast FM) ending in a sharp up-slur."""
    x = zeros(1.6, sr)
    t = r.uniform(0.02, 0.05)
    base = r.uniform(3300, 3700)
    for i in range(int(r.integers(3, 5))):
        d = r.uniform(0.14, 0.2)
        f = base * (1.0 + 0.1 * i)
        s = syl([(0, f * 0.97), (1, f * 1.03)], d, amp=[(0, 0.4), (0.4, 1), (1, 0.6)],
                fm=(r.uniform(95, 130), 0.07), sr=sr)
        place(x, t, s, sr, 0.75)
        t += d + r.uniform(0.05, 0.09)
    s = syl([(0, base * 1.1), (1, base * 1.65)], 0.12, amp=[(0, 0.3), (0.6, 1), (1, 0.4)], sr=sr)
    place(x, t, s, sr)
    return x


def bird_sparrow(r, sr=SR):
    """Two or three sweet intro notes, a fast trill (a down-sweep repeated ~18 per second)
    and a closing note (a song sparrow's pattern)."""
    x = zeros(2.1, sr)
    t = r.uniform(0.02, 0.05)
    f = r.uniform(2500, 3000)
    for _ in range(int(r.integers(2, 4))):
        s = syl([(0, f), (0.5, f * 1.04), (1, f * 0.98)], 0.11, amp=[(0, 0.4), (0.3, 1), (1, 0.6)], sr=sr)
        place(x, t, s, sr)
        t += r.uniform(0.2, 0.26)
    rate = r.uniform(15, 21)
    hi, lo = r.uniform(4600, 5200), r.uniform(2800, 3300)
    count = int(r.uniform(0.5, 0.75) * rate)
    for i in range(count):
        s = syl([(0, hi), (1, lo)], 0.032, att=0.002, rel=0.006, sr=sr)
        place(x, t, s, sr, 0.75 * (0.8 + 0.2 * np.sin(np.pi * i / count)))
        t += 1.0 / rate
    t += 0.08
    s = syl([(0, 2400), (0.5, 2700), (1, 2200)], 0.2, amp=[(0, 0.3), (0.3, 1), (1, 0.3)], fm=(40, 0.01), sr=sr)
    place(x, t, s, sr, 0.8)
    return x


def bird_dove(r, sr=SR):
    """Soft low cooing: 'coo-OO, oo, oo, oo' around 500 Hz with a breathy edge."""
    x = zeros(3.2, sr)
    k = r.uniform(0.92, 1.08)
    notes = [([(0, 470), (1, 560)], 0.32, 0.55), ([(0, 560), (0.3, 690), (1, 520)], 0.55, 1.0),
             ([(0, 500), (1, 470)], 0.5, 0.7), ([(0, 495), (1, 465)], 0.5, 0.6), ([(0, 490), (1, 460)], 0.5, 0.5)]
    t = r.uniform(0.03, 0.08)
    for i, (pts, d, g) in enumerate(notes):
        pts = [(u, f * k) for u, f in pts]
        s = syl(pts, d, amp=[(0, 0.3), (0.25, 1), (0.8, 0.9), (1, 0.2)], harm=((1, 1.0), (2, 0.22), (3, 0.07)),
                att=0.05, rel=0.12, sr=sr, smooth_s=0.02)
        n = len(s)
        breath = lp(r.standard_normal(n), 1400, 2, sr) * rcos_env(n, 0.05, 0.12, sr)
        s = s + 0.05 * unit(breath)
        place(x, t, s, sr, g)
        t += d + (0.28 if i == 1 else 0.14)
    return x


BIRDS = (bird_feebee, bird_robin, bird_cardinal, bird_warbler, bird_sparrow)


# ==========================================================================
# the beds
# ==========================================================================
BEDS = {}   # name -> (function, rms dBFS)


def bed(name, rms_db):
    def reg(fn):
        BEDS[name] = (fn, rms_db)
        return fn
    return reg


def wind_layer(mix, stem, r, gust, lo, hi, howl=None, howl_q=6.0, howl_gain=0.6, body_gain=1.0,
               spread_s=0.45, howl_pow=2.0):
    """Wind: coloured noise whose level follows the gust curve, plus an optional whistling
    resonance (howl=(f_calm, f_gust)) that rises in pitch with the gusts.  The right channel
    hears each gust a moment after the left, so gusts sweep across."""
    n = mix.n
    for ch in range(2):
        g = np.roll(gust, int(ch * spread_s * BSR))
        body = cband(pink(r, n, BSR), lo, hi, 2) * (0.25 + 0.75 * g)
        sig = body * body_gain
        if howl:
            fa, fb = howl

            def gain(t, f, g=g):
                gg = at(g, t)
                fc = fa * (fb / fa) ** gg
                return resonance(fc, f, howl_q) + 0.35 * resonance(fc * 1.52, f, howl_q * 1.3)
            wh = stft_shape(r.standard_normal(n), gain)
            sig = sig + howl_gain * rmsn(wh) * g ** howl_pow
        chans = np.zeros((n, 2))
        chans[:, ch] = sig
        mix.add_loop(stem, chans)


def far_birds(mix, count, dens, gain=(0.05, 0.14), lp_hz=5000.0, include_dove=False):
    r = mix.r
    kinds = list(BIRDS) + ([bird_dove] if include_dove else [])
    for t in density_times(r, mix.T, count, dens):
        fn = kinds[int(r.integers(0, len(kinds)))]
        s = lp(fn(r, BSR), lp_hz, 2, BSR)
        mix.add("birds", t, s, gain=r.uniform(*gain) ** 1.2 * 3.0, pan=r.uniform(-0.85, 0.85), rev=0.6)


def garden_bed(name, seconds, title=False):
    mix = Mix(name, seconds)
    r = mix.r
    n = mix.n
    gust = gusts(r, n, 0.12, bias=-0.3) * (0.7 + 0.3 * cbeat(n, 3, r.uniform(0, TAU)))
    if title:
        gust = 0.3 + 0.55 * gust
    # breeze body and leaf rustle: a soft continuous rustle plus a flutter (noise chopped by a
    # fast, bounded, jittery envelope) that both rise with the gusts
    wind_layer(mix, "breeze", r, gust, 120.0, 1100.0, body_gain=0.5)
    for ch in range(2):
        g = 0.1 + 0.9 * np.roll(gust, int(ch * 0.45 * BSR))
        soft = cband(r.standard_normal(n), 700.0, 4500.0, 3)
        chop = 0.25 + 0.75 * (0.5 + 0.5 * np.tanh(1.8 * smooth(r, n, 18.0, BSR)))
        flutter = cband(r.standard_normal(n), 1200.0, 6000.0, 3) * chop
        chans = np.zeros((n, 2))
        chans[:, ch] = (rmsn(soft) * 0.6 + rmsn(flutter) * 0.5) * g ** 1.5
        mix.add_loop("leaves", chans)
    # distant birdsong: busier stretches and quiet stretches across the loop
    dens = 0.25 + cbeat(n, 3, r.uniform(0, TAU)) * (0.4 + 0.6 * cbeat(n, 1, r.uniform(0, TAU)))
    far_birds(mix, 10 if title else 30, dens, gain=(0.04, 0.12) if title else (0.05, 0.15), include_dove=not title)
    if not title:
        # grasshoppers: bursts of 4-9 kHz noise pulses at ~35 Hz from one spot, now and then
        on = cbeat(n, 4, r.uniform(0, TAU)) ** 3
        for t in density_times(r, mix.T, 34, on + 0.05):
            dur = r.uniform(0.35, 0.8)
            m = int(dur * BSR)
            tt = np.arange(m) / BSR
            rate = r.uniform(28, 42)
            pulse = np.maximum(np.sin(TAU * rate * tt), 0.0) ** 6
            s = cband(r.standard_normal(m), 4200.0, 9000.0, 2) * pulse * rcos_env(m, 0.08, 0.12, BSR)
            mix.add("insects", t, rmsn(s), gain=r.uniform(0.02, 0.05), pan=r.uniform(-0.9, 0.9), rev=0.2)
    if title:
        levels = {"breeze": -3.0, "leaves": -3.0, "birds": -13.0}
    else:
        levels = {"breeze": -6.0, "leaves": -4.0, "birds": -11.0, "insects": -21.0}
    mix.render(BEDS[name][1], levels, t60=0.9, damp=3500.0, wet=0.45, lp_hz=8000.0)


@bed("amb_gardens", -26.0)
def bed_gardens():
    garden_bed("amb_gardens", 64.0)


@bed("amb_title", -30.0)
def bed_title():
    garden_bed("amb_title", 48.0, title=True)


@bed("amb_foundry", -25.0)
def bed_foundry():
    mix = Mix("amb_foundry", 56.0)
    r = mix.r
    n = mix.n
    t = np.arange(n) / BSR
    # furnace roar: dark noise with a slow flicker, and a fluttering combustion band
    flick = 0.75 + 0.25 * np.tanh(smooth(r, n, 1.5, BSR))
    swell = 0.8 + 0.2 * cbeat(n, 3)
    for ch in range(2):
        roar = cband(pink(r, n, BSR, slope=-0.7), 60.0, 800.0, 2) * flick * swell
        comb = cband(r.standard_normal(n), 250.0, 1800.0, 2) * (0.4 + 0.6 * np.abs(smooth(r, n, 7.0, BSR))) * flick
        chans = np.zeros((n, 2))
        chans[:, ch] = rmsn(roar) * 0.9 + rmsn(comb) * 0.28
        mix.add_loop("roar", chans)
    rumble = cband(r.standard_normal(n), 38.0, 95.0, 3) * (0.6 + 0.4 * cbeat(n, 1))
    mix.add_loop("rumble", rmsn(rumble) * 0.3)
    # bubbling slag: clusters of thick, rising bubbles, some ending in a small pop
    dens = 0.2 + cbeat(n, 5, 1.0) * cbeat(n, 2, 0.3)
    for tb in density_times(r, mix.T, 260, dens):
        d = r.uniform(0.08, 0.26)
        tt = tv(d + 0.05, BSR)
        f0 = r.uniform(70, 240)
        f = f0 * (1.0 + r.uniform(0.4, 0.9) * np.clip(tt / d, 0, 1))
        s = tone(f, ((1, 1.0), (2, 0.35), (3, 0.12)), BSR) * ga.ad_env(tt, d * 0.4, d * 0.35)
        if r.random() < 0.4:
            place(s, d * 0.8, noise_hit(r, 0.02, 400.0, 2500.0, 0.004, BSR), BSR, 0.25)
        mix.add("slag", tb, lp(s, 1800.0, 2, BSR), gain=r.uniform(0.04, 0.12), pan=r.uniform(-0.7, 0.7), rev=0.5)
    # distant machinery: a press thumping every T/24 with a clank after it, and a hum
    period = mix.T / 24
    thunk_t = tv(0.4, BSR)
    for k in range(24):
        tk = k * period + r.uniform(-0.01, 0.01)
        th = tone(ga.sweep(120.0, 52.0, thunk_t, 0.12), ((1, 1.0), (2, 0.4)), BSR) * ga.ad_env(thunk_t, 0.003, 0.07)
        th += 0.5 * noise_hit(r, 0.4, 100.0, 700.0, 0.05, BSR)
        mix.add("machines", tk, lp(th, 900.0, 2, BSR), gain=0.35 * r.uniform(0.85, 1.0), pan=-0.35, rev=1.0)
        cl = modal([r.uniform(700, 760), 1130, 1720, 2480], [1, 0.6, 0.4, 0.2], [0.3, 0.2, 0.12, 0.08], 0.6, BSR, r=r)
        mix.add("machines", tk + period * 0.42, lp(cl, 1600.0, 2, BSR), gain=0.08, pan=-0.2, rev=1.0)
    hum = sum(a * csine(f, n) for f, a in ((47.0, 0.5), (94.0, 1.0), (141.0, 0.45), (188.0, 0.25)))
    hum *= 0.7 + 0.3 * np.cos(TAU * 24 * t / mix.T) ** 2
    mix.add_loop("machines", st(lp(hum, 400.0, 2, BSR), -0.3) * 0.05)
    # far off vents sighing now and then
    for tb in spaced_times(r, mix.T, 7.0, 13.0):
        d = r.uniform(1.0, 2.0)
        m = int(d * BSR)
        s = cband(r.standard_normal(m), 900.0, 5000.0, 2) * rcos_env(m, 0.15, d * 0.6, BSR)
        mix.add("vents", tb, lp(s, 3500.0, 2, BSR), gain=0.06, pan=r.uniform(-0.8, 0.8), rev=1.0)
    levels = {"roar": 0.0, "rumble": -12.0, "slag": -13.0, "machines": -12.0, "vents": -19.0}
    mix.render(BEDS["amb_foundry"][1], levels, t60=2.6, damp=1800.0, wet=0.55, predelay=0.03, hp_hz=40.0, lp_hz=8000.0)


@bed("amb_balance", -25.0)
def bed_balance():
    mix = Mix("amb_balance", 64.0)
    r = mix.r
    n = mix.n
    # surf far below: each wave swells, breaks and washes out (a foam fizz after the crash)
    for tw in spaced_times(r, mix.T, 5.5, 9.0):
        rise, tail = r.uniform(1.4, 2.6), r.uniform(2.2, 3.6)
        dur = rise + tail * 2.5
        m = int(dur * BSR)
        tt = np.arange(m) / BSR
        env = np.where(tt < rise, (tt / rise) ** 2.2, np.exp(-(tt - rise) / tail))
        crash = np.where(tt < rise, (tt / rise) ** 5, np.exp(-(tt - rise) / (tail * 0.35)))
        pan = r.uniform(-0.55, 0.55)
        wide = np.zeros((m, 2))
        for ch in range(2):
            wash = cband(pink(r, m, BSR), 70.0, 1100.0, 2) * env
            brk = cband(r.standard_normal(m), 250.0, 3200.0, 2) * crash
            fizz = cband(r.standard_normal(m), 1500.0, 5000.0, 2) * np.abs(smooth(r, m, 40.0, BSR)) ** 1.5
            fizz *= np.where(tt < rise, 0.0, np.exp(-(tt - rise) / (tail * 0.7))) * (1 - np.exp(-np.maximum(tt - rise, 0) / 0.3))
            wide[:, ch] = wash + 0.55 * brk + 0.3 * rmsn(fizz) * np.std(brk)
        wide *= np.array([np.cos((pan + 1) * np.pi / 4), np.sin((pan + 1) * np.pi / 4)]) * np.sqrt(2)
        mix.add("surf", tw, wide, gain=r.uniform(0.75, 1.0), rev=0.4)
    for ch in range(2):
        sea = cband(pink(r, n, BSR), 60.0, 800.0, 2) * (0.65 + 0.35 * np.tanh(smooth(r, n, 0.15, BSR)))
        chans = np.zeros((n, 2))
        chans[:, ch] = sea * 0.45
        mix.add_loop("sea", chans)
    # the sea is far below: dull the whole surf
    for s in ("surf", "sea"):
        for ch in range(2):
            mix.stems[s][:, ch] = cband(mix.stems[s][:, ch], None, 2400.0, 1)
    # wind gusts across the yard, whistling round the containers
    gust = gusts(r, n, 0.09, bias=-0.2) * (0.7 + 0.3 * cbeat(n, 2, 0.8))
    wind_layer(mix, "wind", r, gust, 150.0, 1600.0, howl=(420.0, 820.0), howl_q=7.0, howl_gain=0.35, body_gain=0.55)
    # singing cables: aeolian tones whose pitch rides the wind speed
    for f0, a, pan in ((196.0, 1.0, -0.5), (293.0, 0.7, 0.4), (412.0, 0.45, 0.1), (587.0, 0.25, -0.2)):
        g = np.roll(gust, int(r.uniform(0, 1.5) * BSR))
        f = f0 * (0.97 + 0.06 * g)
        cab = cosc(f) + 0.18 * cosc(2 * f) + 0.06 * cosc(3 * f)
        beat = 0.8 + 0.2 * cosc(np.full(n, r.uniform(0.2, 0.6)))
        mix.add_loop("cables", st(cab * g ** 2.2 * beat, pan) * 0.05 * a, rev=0.3)
    # rigging: soft taps of loose lines against masts at gust peaks
    for tb in density_times(r, mix.T, 22, gust ** 3 + 0.02):
        s = modal([r.uniform(900, 1300), r.uniform(2100, 2900), r.uniform(3800, 4600)], [1, 0.5, 0.25],
                  [0.08, 0.05, 0.03], 0.3, BSR, r=r)
        mix.add("rigging", tb, lp(s, 4000.0, 2, BSR), gain=r.uniform(0.02, 0.05), pan=r.uniform(-0.8, 0.8), rev=0.6)
    levels = {"surf": 0.0, "sea": -4.0, "wind": -3.0, "cables": -14.0, "rigging": -21.0}
    mix.render(BEDS["amb_balance"][1], levels, t60=1.6, damp=2200.0, wet=0.35, hp_hz=40.0, lp_hz=8500.0)


def tick_kernel(r, scale, dur=0.09, sr=BSR, wood=False):
    """One clock tick: a click exciting a few damped modes."""
    if wood:
        fr = [310, 530, 820, 1290, 2100]
        taus = [0.06, 0.045, 0.03, 0.02, 0.012]
        amps = [1.0, 0.8, 0.55, 0.4, 0.2]
    else:
        fr = [2150, 3350, 4700, 6150]
        taus = [0.012, 0.008, 0.005, 0.003]
        amps = [1.0, 0.7, 0.45, 0.25]
    fr = [f * scale * r.uniform(0.97, 1.03) for f in fr]
    taus = [tau / scale ** 0.5 for tau in taus]
    k = modal(fr, amps, taus, dur, sr, att=0.0003, r=r)
    k += 0.3 * noise_hit(r, dur, 1500.0 * scale, None, 0.0012, sr)
    return unit(k)


@bed("amb_clockwork", -26.0)
def bed_clockwork():
    mix = Mix("amb_clockwork", 60.0)
    r = mix.r
    n = mix.n
    T = mix.T
    # (ticks per loop, level, pan, pitch, wooden, lowpass Hz)
    clocks = ((60, 0.9, -0.35, 1.0, False, 6000), (80, 0.6, 0.45, 1.22, False, 5500),
              (50, 0.75, 0.1, 0.8, False, 5000), (120, 0.28, -0.75, 1.55, False, 4200),
              (40, 0.8, 0.6, 0.62, False, 4500), (30, 1.0, -0.1, 1.0, True, 3000),
              (150, 0.16, 0.8, 1.9, False, 5000), (70, 0.4, -0.55, 1.1, False, 3800))
    for ci, (count, level, pan, pitch, wood, lp_hz) in enumerate(clocks):
        tick = lp(tick_kernel(r, pitch, wood=wood), lp_hz, 2, BSR)
        tock = lp(tick_kernel(r, pitch * 0.86, wood=wood), lp_hz, 2, BSR)
        breathe = 0.6 + 0.4 * gusts(r, n, 0.04)
        period = T / count
        off = r.uniform(0, period)
        for k in range(count):
            tk = off + k * period + r.normal(0, 0.0015)
            g = level * at(breathe, tk) * r.uniform(0.85, 1.0)
            mix.add("ticks", tk, tick if k % 2 == 0 else tock, gain=g * (1.0 if k % 2 == 0 else 0.8),
                    pan=pan, rev=0.5 + 0.1 * ci / len(clocks))
        if wood:
            # the tower escapement's ring after each wooden clunk
            ring = modal([1452.0, 2921.0], [1.0, 0.3], [0.5, 0.25], 1.2, BSR, r=r)
            for k in range(0, count, 2):
                mix.add("ticks", off + k * period, ring, gain=0.06, pan=pan, rev=0.8)
    # gear-train whirr (tooth rate modulation) and a low mechanism hum
    teeth = 0.55 + 0.45 * np.sin(TAU * np.round(7.5 * T) * np.arange(n) / n) ** 2
    whirr = cband(r.standard_normal(n), 160.0, 800.0, 2) * teeth * (0.6 + 0.4 * gusts(r, n, 0.05))
    hum = csine(55.0, n) + 0.5 * csine(110.0, n) + 0.3 * csine(165.0, n)
    mix.add_loop("mechanism", st(rmsn(whirr) * 0.10 + hum * 0.03, 0.2), rev=0.3)
    # wind round the tower
    gust = gusts(r, n, 0.06, bias=-0.3)
    wind_layer(mix, "wind", r, gust, 140.0, 1200.0, howl=(330.0, 620.0), howl_q=6.0, howl_gain=0.3, body_gain=0.35)
    levels = {"ticks": 0.0, "mechanism": -9.0, "wind": -6.0}
    mix.render(BEDS["amb_clockwork"][1], levels, t60=1.7, damp=2800.0, wet=0.45, predelay=0.015)


def bubble(r, f0, tau, rise=0.3, sr=BSR):
    """One bubble: a damped sine whose pitch rises as it rises (Minnaert resonance)."""
    tt = tv(tau * 6.0, sr)
    f = f0 * (1.0 + rise * tt / (tau * 6.0))
    return tone(f, ((1, 1.0),), sr) * np.exp(-tt / tau) * np.minimum(tt / 0.0015, 1.0)


def reef_bed(name, deep):
    mix = Mix(name, 64.0)
    r = mix.r
    n = mix.n
    surge = 0.7 + 0.3 * cbeat(n, 7 if not deep else 3, r.uniform(0, TAU))
    for ch in range(2):
        press = cband(pink(r, n, BSR, slope=-0.7), 42.0, 260.0 if deep else 360.0, 2)
        mid = cband(r.standard_normal(n), 120.0, 600.0, 2)
        sig = rmsn(press) * 0.8 * surge + rmsn(mid) * (0.3 if deep else 0.4) * surge
        if not deep:
            slosh = cband(pink(r, n, BSR), 250.0, 1100.0, 2) * surge ** 3
            sig += rmsn(slosh) * 0.12
        chans = np.zeros((n, 2))
        chans[:, ch] = sig
        mix.add_loop("pressure", chans)
    # bubble streams: a vent or a diver's worth of bubbles from one spot for a few seconds
    for ts in spaced_times(r, mix.T, 4.0, 9.0) if not deep else spaced_times(r, mix.T, 9.0, 16.0):
        dur = r.uniform(2.5, 7.0)
        rate = r.uniform(5.0, 16.0) * (0.5 if deep else 1.0)
        pan = r.uniform(-0.8, 0.8)
        g = r.uniform(0.08, 0.18)
        tb = 0.0
        while tb < dur:
            rmm = np.exp(r.uniform(np.log(1.4), np.log(5.5 if not deep else 8.0)))
            s = bubble(r, 3260.0 / rmm, 0.004 + 0.004 * rmm, r.uniform(0.15, 0.5))
            ramp = np.sin(np.pi * tb / dur) ** 0.5
            mix.add("bubbles", ts + tb, lp(s, 2800.0, 2, BSR), gain=g * ramp * rmm ** 0.4 * r.uniform(0.4, 1.0),
                    pan=pan + r.uniform(-0.1, 0.1), rev=0.6)
            tb += r.exponential(1.0 / rate)
    for tb in r.uniform(0, mix.T, 70 if not deep else 25):
        rmm = np.exp(r.uniform(np.log(1.2), np.log(7.0)))
        s = bubble(r, 3260.0 / rmm, 0.004 + 0.004 * rmm, r.uniform(0.15, 0.5))
        mix.add("bubbles", tb, lp(s, 2800.0, 2, BSR), gain=r.uniform(0.03, 0.1), pan=r.uniform(-0.9, 0.9), rev=0.6)
    # fizz: snapping-shrimp crackle, a faint carpet of clicks whose density drifts
    for ch in range(2):
        rate = (60.0 if not deep else 18.0) * (0.5 + 0.5 * gusts(r, n, 0.08))
        clicks = (r.random(n) < rate / BSR) * r.lognormal(0.0, 0.6, n) * np.sign(r.standard_normal(n))
        fizz = cband(clicks, 2000.0, 7000.0, 2)
        chans = np.zeros((n, 2))
        chans[:, ch] = rmsn(fizz) * (0.04 if not deep else 0.025)
        mix.add_loop("fizz", chans, rev=0.3)
    if deep:
        # slow distant groans of shifting rock and the temple's hollow resonance
        for tg in spaced_times(r, mix.T, 12.0, 20.0):
            d = r.uniform(3.0, 5.0)
            m = int(d * BSR)
            tt = np.arange(m) / BSR
            f = contour([(0, r.uniform(60, 80)), (0.5, r.uniform(85, 110)), (1, r.uniform(55, 70))], m, BSR, 0.2)
            s = tone(f, ((1, 0.6), (2, 1.0), (3, 0.5), (4, 0.25)), BSR) * rcos_env(m, d * 0.4, d * 0.5, BSR)
            s *= 1.0 + 0.3 * np.sin(TAU * r.uniform(5, 9) * tt)
            mix.add("groans", tg, lp(s, 500.0, 2, BSR), gain=0.08, pan=r.uniform(-0.6, 0.6), rev=1.0)
        for ch in range(2):
            def gain(t, f):
                return (resonance(310.0, f, 9.0) + 0.7 * resonance(505.0, f, 11.0) + 0.5 * resonance(870.0, f, 12.0))
            hollow = stft_shape(r.standard_normal(n), gain) * (0.6 + 0.4 * gusts(r, n, 0.05))
            chans = np.zeros((n, 2))
            chans[:, ch] = rmsn(hollow) * 0.07
            mix.add_loop("hollow", chans, rev=0.6)
    # everything under water is dull: a gentle overall low-pass on the lot
    for s in mix.stems:
        for ch in range(2):
            mix.stems[s][:, ch] = cband(mix.stems[s][:, ch], None, 3200.0 if not deep else 2200.0, 1)
    if deep:
        levels = {"pressure": 0.0, "hollow": -10.0, "groans": -12.0, "bubbles": -17.0, "fizz": -23.0}
    else:
        levels = {"pressure": 0.0, "bubbles": -11.0, "fizz": -18.0}
    mix.render(BEDS[name][1], levels, t60=1.4 if not deep else 3.0, damp=1500.0 if not deep else 1000.0,
               wet=0.45 if not deep else 0.6, predelay=0.01, hp_hz=40.0, lp_hz=6000.0)


@bed("amb_reef", -26.0)
def bed_reef():
    reef_bed("amb_reef", deep=False)


@bed("amb_reef_deep", -26.0)
def bed_reef_deep():
    reef_bed("amb_reef_deep", deep=True)


@bed("amb_orbital", -27.0)
def bed_orbital():
    mix = Mix("amb_orbital", 60.0)
    r = mix.r
    n = mix.n
    # air handler: two fan motors a hair apart (a slow beat), weighted to the 2nd-4th harmonics
    for f0, pan, ph in ((58.0, -0.25, 0.0), (58.35, 0.3, 1.3)):
        hum = sum(a * csine(f0 * k, n, phase=ph * k) for k, a in ((1, 0.35), (2, 1.0), (3, 0.6), (4, 0.4),
                                                                    (5, 0.2), (6, 0.12), (8, 0.06)))
        mix.add_loop("hum", st(hum, pan) * 0.05, rev=0.2)
    blade = csine(58.0 * 7 / 3, n) * (0.7 + 0.3 * csine(58.0 / 3, n))
    mix.add_loop("hum", st(blade, 0.0) * 0.012)
    # ventilation: steady airflow through ducts (fixed duct resonances), breathing slowly
    for ch in range(2):
        def gain(t, f):
            return 0.35 + resonance(430.0, f, 4.0) + 0.8 * resonance(1010.0, f, 4.5) + 0.5 * resonance(1870.0, f, 5.0)
        air = stft_shape(pink(r, n, BSR), gain)
        air = cband(air, 150.0, 5000.0, 2) * (0.85 + 0.15 * np.tanh(smooth(r, n, 0.1, BSR)))
        chans = np.zeros((n, 2))
        chans[:, ch] = rmsn(air) * 0.5
        mix.add_loop("vent", chans, rev=0.2)
    # coolant pump: a soft whoosh cycle every T/10
    for k in range(10):
        m = int(2.5 * BSR)
        s = cband(r.standard_normal(m), 250.0, 1200.0, 2) * np.sin(np.pi * np.arange(m) / m) ** 2
        mix.add("pump", k * mix.T / 10, rmsn(s), gain=0.06, pan=0.5, rev=0.5)
    # electrical whine and mains buzz, drifting in and out over the loop
    whine_env = cbeat(n, 2, r.uniform(0, TAU)) ** 2
    wf = 2350.0 * (1.0 + 0.004 * np.sin(TAU * 3 * np.arange(n) / n))
    whine = cosc(wf) + 0.3 * cosc(wf * 1.5)
    mix.add_loop("whine", st(whine * whine_env, -0.6) * 0.004)
    buzz = sum(a * csine(120.0 * k, n) for k, a in ((1, 1.0), (2, 0.5), (3, 0.35), (5, 0.2)))
    mix.add_loop("whine", st(buzz * (0.5 + 0.5 * cbeat(n, 1, 2.0)), 0.5) * 0.008)
    # relays clicking somewhere in the walls
    for tb in r.uniform(0, mix.T, 14):
        s = modal([r.uniform(2600, 3400), r.uniform(4500, 5500)], [1, 0.5], [0.006, 0.004], 0.05, BSR, r=r)
        mix.add("relays", tb, s, gain=r.uniform(0.03, 0.07), pan=r.uniform(-0.9, 0.9), rev=0.6)
    levels = {"vent": 0.0, "hum": -6.0, "pump": -13.0, "whine": -22.0, "relays": -27.0}
    mix.render(BEDS["amb_orbital"][1], levels, t60=0.8, damp=3500.0, wet=0.35, predelay=0.008, hp_hz=40.0)


def ascent_bed(name, high):
    mix = Mix(name, 64.0)
    r = mix.r
    n = mix.n
    # the city far below: a broadband wash with distant traffic passing through it
    city_lp = 1000.0 if not high else 650.0
    for ch in range(2):
        wash = cband(pink(r, n, BSR), 50.0, city_lp, 2) * (0.8 + 0.2 * np.tanh(smooth(r, n, 0.06, BSR)))
        chans = np.zeros((n, 2))
        chans[:, ch] = rmsn(wash) * (0.55 if not high else 0.35)
        mix.add_loop("city", chans)
    for tb in r.uniform(0, mix.T, 44 if not high else 22):
        d = r.uniform(2.5, 6.0)
        m = int(d * BSR)
        s = cband(r.standard_normal(m), 200.0, 2000.0, 2) * np.sin(np.pi * np.arange(m) / m) ** 3
        s = cband(s, None, r.uniform(900, 1600) * (0.7 if high else 1.0), 2)
        p0 = r.uniform(-0.9, 0.9)
        tt = np.arange(m) / m
        sw = np.zeros((m, 2))
        pan = p0 + (r.uniform(-0.5, 0.5)) * (tt - 0.5)
        a = (np.clip(pan, -1, 1) + 1) * np.pi / 4
        sw[:, 0] = s * np.cos(a) * np.sqrt(2)
        sw[:, 1] = s * np.sin(a) * np.sqrt(2)
        mix.add("traffic", tb, rmsn(sw), gain=r.uniform(0.04, 0.1) * (0.6 if high else 1.0), rev=0.5)
    # high-altitude wind, howling round the spire
    gust = gusts(r, n, 0.08, bias=0.0 if high else -0.35) * (0.7 + 0.3 * cbeat(n, 2, 0.4))
    wind_layer(mix, "wind", r, gust, 130.0, 2200.0, howl=(460.0, 1150.0), howl_q=8.0,
               howl_gain=0.6 if high else 0.4, body_gain=1.0 if high else 0.6, howl_pow=1.6)
    # neon: a 120 Hz transformer buzz with gas-discharge fizz that flickers now and then
    flick = 1.0 - 0.6 * (smooth(r, n, 6.0, BSR) > 2.2) * np.abs(smooth(r, n, 30.0, BSR))
    flick = cband(flick, None, 60.0, 1)
    buzz = sum(a * csine(120.0 * k, n) for k, a in ((1, 1.0), (2, 0.6), (3, 0.5), (4, 0.3), (5, 0.3), (7, 0.2),
                                                    (9, 0.12), (11, 0.08), (15, 0.05)))
    fizz = cband(r.standard_normal(n), 3000.0, 6500.0, 2) * 0.15
    mix.add_loop("neon", st((buzz * 0.03 + fizz * 0.02) * flick * (0.35 if high else 1.0), 0.35), rev=0.3)
    if high:
        levels = {"wind": 0.0, "city": -5.0, "traffic": -14.0, "neon": -22.0}
    else:
        levels = {"city": 0.0, "wind": -3.0, "traffic": -9.0, "neon": -16.0}
    mix.render(BEDS[name][1], levels, t60=2.2, damp=2000.0, wet=0.35, hp_hz=40.0, lp_hz=8000.0)


@bed("amb_ascent", -26.0)
def bed_ascent():
    ascent_bed("amb_ascent", high=False)


@bed("amb_ascent_high", -26.0)
def bed_ascent_high():
    ascent_bed("amb_ascent_high", high=True)


# ==========================================================================
# the one-shots
# ==========================================================================
SHOTS = {}   # name -> (function(r, i), variants)


def shots(name, count):
    def reg(fn):
        SHOTS[name] = (fn, count)
        return fn
    return reg


# ---- gardens ---------------------------------------------------------------
@shots("amb_gardens_bird", 5)
def shot_bird(r, i):
    x = BIRDS[i](r)
    return far(hp(x, 1200.0), r, 9000.0, 0.6, 0.12, damp=5000.0)


@shots("amb_gardens_dove", 2)
def shot_dove(r, i):
    return far(bird_dove(r), r, 5000.0, 0.7, 0.15, damp=3000.0, hp_hz=250.0)


@shots("amb_gardens_bee", 3)
def shot_bee(r, i):
    dur = r.uniform(2.6, 3.4)
    n = int(dur * SR)
    t = np.arange(n) / SR
    f0 = r.uniform(150, 225) * (1.0 + 0.03 * smooth(r, n, 2.5))
    wing = tone(f0, [(k, 1.0 / k ** 0.85) for k in range(1, 24)])
    wing *= 1.0 + 0.12 * smooth(r, n, 45.0)
    src = wing + 0.15 * unit(bp(r.standard_normal(n), 2000.0, 6000.0)) * wing
    y, close = doppler_pass(src, SR, r.uniform(1.4, 2.6), r.uniform(0.35, 0.7), dur * r.uniform(0.4, 0.6))
    dark = lp(y, 900.0)
    y = dark + (y - dark) * close ** 1.5
    return y * rcos_env(n, 0.3, 0.4) * (0.6 + 0.4 * np.sin(np.pi * t / dur))


@shots("amb_gardens_chimes", 3)
def shot_chimes(r, i):
    shift = (0, 2, -3)[i]
    tubes = [ga.mtof(m + shift) for m in (81, 84, 86, 88, 91)]
    x = zeros(4.2)
    strikes = int(r.integers(6, 12))
    for _ in range(strikes):
        t0 = r.beta(1.6, 2.6) * 2.6
        f = tubes[int(r.integers(0, len(tubes)))]
        a = r.uniform(0.3, 1.0) ** 1.5
        tau = 2.0 * (880.0 / f) ** 0.3
        dur = 4.2 - t0
        s = np.zeros(len(tv(dur)))
        for ratio, amp, ts in ((1.0, 1.0, 1.0), (2.757, 0.45, 0.55), (5.404, 0.22, 0.3), (8.933, 0.1, 0.18)):
            if f * ratio < 16000:
                for det in (0.9985, 1.0015):
                    s += 0.5 * amp * modal([f * ratio * det], [1.0], [tau * ts], dur, r=r)
        s[:int(0.003 * SR)] += 0.08 * r.standard_normal(int(0.003 * SR))
        place(x, t0, s, SR, a)
    return reverb(x, r, 0.8, 5000.0, 0.15)


@shots("amb_gardens_windmill", 2)
def shot_windmill(r, i):
    dur = 2.8
    x = zeros(dur)
    cr = stick_slip(r, 1.7, lambda u: 16.0 + 30.0 * np.sin(np.pi * u) ** 1.2,
                    ((190.0, 0.018, 1.0), (430.0, 0.012, 0.7), (880.0, 0.007, 0.4), (1500.0, 0.004, 0.2)),
                    bend=r.uniform(1.05, 1.12))
    place(x, 0.2, unit(cr), SR, 0.8)
    m = int(0.9 * SR)
    whoosh = bp(r.standard_normal(m), 150.0, 900.0) * np.sin(np.pi * np.arange(m) / m) ** 2
    place(x, r.uniform(1.3, 1.7), unit(whoosh), SR, 0.45)
    knock = modal([140.0, 262.0, 530.0], [1.0, 0.6, 0.3], [0.035, 0.025, 0.015], 0.3, r=r)
    place(x, 0.08, knock, SR, 0.6)
    place(x, r.uniform(2.1, 2.3), knock, SR, 0.4)
    return far(x, r, 5500.0, 0.7, 0.15)


# ---- foundry ---------------------------------------------------------------
def metal_hit(r, f0, dur, nmodes=7, tau0=1.0):
    ratios = [1.0] + sorted(r.uniform(lo, hi) for lo, hi in ((1.3, 1.7), (2.1, 2.7), (2.9, 3.6), (4.0, 4.9),
                                                           (5.3, 6.4), (7.0, 8.5)))[:nmodes - 1]
    amps = [r.uniform(0.5, 1.0) / (k + 1) ** 0.5 for k in range(len(ratios))]
    taus = [tau0 * r.uniform(0.6, 1.0) / (k + 1) ** 0.6 for k in range(len(ratios))]
    s = modal([f0 * q for q in ratios], amps, taus, dur, r=r)
    return unit(s) + 0.5 * noise_hit(r, dur, 500.0, 6000.0, 0.004)


@shots("amb_foundry_clank", 3)
def shot_clank(r, i):
    x = zeros(1.4)
    f0 = r.uniform(240, 420)
    place(x, 0.01, metal_hit(r, f0, 1.3, tau0=r.uniform(0.5, 1.0)), SR)
    if r.random() < 0.75:
        place(x, r.uniform(0.12, 0.35), metal_hit(r, f0 * r.uniform(0.97, 1.03), 1.0, tau0=0.5), SR, r.uniform(0.35, 0.6))
    return trim(far(x, r, 3600.0, 2.4, 0.55, damp=2200.0, predelay=0.035))


def steam(r, dur, body=0.5, bright=1.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    att = r.uniform(0.012, 0.035)
    env = np.minimum(t / att, 1.0) * np.exp(-t / (dur * 0.55)) * rcos_env(n, 0.001, dur * 0.35)
    flutter = 1.0 + 0.25 * smooth(r, n, 22.0)
    hiss = bp(r.standard_normal(n), 1100.0 * bright, 9000.0) + 0.7 * bp(r.standard_normal(n), 2400.0 * bright, 5200.0 * bright)
    fwump = bp(r.standard_normal(n), 140.0, 650.0) * np.exp(-t / 0.1)
    return unit(hiss) * env * flutter + body * unit(fwump) * np.minimum(t / 0.004, 1.0)


@shots("amb_foundry_steam", 3)
def shot_steam(r, i):
    return trim(far(steam(r, r.uniform(0.9, 1.6)), r, 6000.0, 1.8, 0.4, damp=2500.0))


def chain(r, dur, heavy=False, rate=40.0):
    x = zeros(dur)
    peak = r.uniform(0.15, 0.4)
    t = 0.0
    lo, hi = (650.0, 2400.0) if heavy else (1700.0, 5200.0)
    while t < dur - 0.15:
        dens = np.exp(-((t - peak) / 0.25) ** 2) + 0.35 * np.exp(-max(t - peak, 0) / 0.4)
        if r.random() < dens:
            fr = sorted(r.uniform(lo, hi, 3))
            taus = [r.uniform(0.01, 0.04) * (2.0 if heavy else 1.0) for _ in range(3)]
            s = modal(fr, [1.0, 0.6, 0.35], taus, 0.15, r=r)
            place(x, t, s, SR, r.uniform(0.3, 1.0) ** 2)
        t += r.exponential(1.0 / rate)
    m = len(x)
    drag = bp(r.standard_normal(m), 300.0, 1500.0) * np.exp(-((np.arange(m) / SR - peak) / 0.35) ** 2)
    return x + 0.08 * unit(drag)


@shots("amb_foundry_chain", 3)
def shot_foundry_chain(r, i):
    return trim(far(chain(r, 1.5, heavy=i == 2), r, 5000.0, 1.8, 0.4, damp=2500.0))


@shots("amb_foundry_hammer", 2)
def shot_hammer(r, i):
    x = zeros(2.6)
    f0 = r.uniform(700, 950)
    ratios = (1.0, 1.47, 2.09, 2.76, 3.52, 4.61)
    t = 0.02
    for k in range(int(r.integers(2, 5))):
        s = modal([f0 * q for q in ratios], [1, 0.7, 0.5, 0.4, 0.3, 0.2], [1.0, 0.8, 0.6, 0.45, 0.35, 0.25], 1.5, r=r)
        s = unit(s) + 0.5 * noise_hit(r, 1.5, 700.0, 7000.0, 0.003)
        s += 0.6 * tone(ga.sweep(130.0, 60.0, tv(1.5), 0.05)) * ga.ad_env(tv(1.5), 0.002, 0.05)
        place(x, t, s, SR, r.uniform(0.8, 1.0) * (0.85 if k == 0 else 1.0))
        t += r.uniform(0.55, 0.72)
        if t > 2.0:
            break
    y = lp(x, 3000.0)
    echo = np.zeros(len(y))
    d = int(r.uniform(0.24, 0.32) * SR)
    echo[d:] = lp(y, 1800.0)[:-d] * 0.35
    return trim(reverb(y + echo, r, 2.6, 2000.0, 0.55, predelay=0.04))


@shots("amb_foundry_blorp", 3)
def shot_blorp(r, i):
    x = zeros(1.0)
    grow = r.uniform(0.14, 0.3)
    tt = tv(grow)
    f = r.uniform(85, 130) * (1.0 + 1.1 * (tt / grow) ** 1.5) * (1.0 + 0.04 * np.sin(TAU * 23.0 * tt))
    body = tone(f, ((1, 1.0), (2, 0.6), (3, 0.35), (4, 0.15))) * np.minimum(tt / (grow * 0.6), 1.0) ** 2
    place(x, 0.02, lp(body, 900.0), SR)
    pop_t = 0.02 + grow
    place(x, pop_t, lp(noise_hit(r, 0.1, 180.0, 1400.0, 0.02), 2500.0), SR, 0.4)
    pt = tv(0.12)
    place(x, pop_t, tone(ga.sweep(420.0, 140.0, pt, 0.05)) * ga.ad_env(pt, 0.001, 0.03), SR, 0.6)
    for _ in range(int(r.integers(3, 7))):
        place(x, pop_t + r.uniform(0.04, 0.35), bubble(r, r.uniform(300, 700), 0.015, 0.4, SR), SR, r.uniform(0.1, 0.3))
    sz = tv(0.6)
    place(x, pop_t, bp(r.standard_normal(len(sz)), 3000.0, 8000.0) * np.exp(-sz / 0.2) * 0.02, SR)
    return trim(far(x, r, 3800.0, 1.4, 0.3, damp=2000.0))


# ---- balance ---------------------------------------------------------------
def gull_note(r, dur, f_pts, f2_pts, amp_pts, rough=0.5):
    """A gull note: a harmonic-rich voice gliding along f_pts, shaped by three formants
    (F2 glides along f2_pts, 'kee' -> 'ow'), with jitter and a rough amplitude flutter."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = contour(f_pts, n, SR, 0.01) * (1.0 + 0.012 * smooth(r, n, 70.0))
    f2 = contour(f2_pts, n, SR, 0.02)
    ph = TAU * np.cumsum(f) / SR
    out = np.zeros(n)
    for k in range(1, 12):
        fk = k * f
        g = 0.6 * resonance(1350.0, fk, 3.0) + 1.0 * resonance(f2, fk, 5.0) + 0.45 * resonance(3700.0, fk, 6.0) + 0.04
        out += g / k ** 0.3 * np.sin(k * ph) * (fk < 9000)
    out *= 1.0 + rough * 0.35 * np.sin(TAU * r.uniform(45, 70) * t)
    return out * pts_env(amp_pts, n) * rcos_env(n, 0.015, 0.04)


def gull_kyow(r, k=1.0, dur=None):
    return gull_note(r, dur or r.uniform(0.26, 0.36),
                     [(0, 780 * k), (0.15, 1150 * k), (0.45, 1050 * k), (1, 640 * k)],
                     [(0, 2600), (0.5, 2300), (1, 1300)], [(0, 0.3), (0.15, 1), (0.7, 0.8), (1, 0)])


def gull_long(r, k=1.0):
    return gull_note(r, r.uniform(0.6, 0.8),
                     [(0, 900 * k), (0.1, 1250 * k), (0.5, 1200 * k), (0.8, 1000 * k), (1, 700 * k)],
                     [(0, 2800), (0.55, 2500), (1, 1200)], [(0, 0.2), (0.1, 1), (0.8, 0.85), (1, 0)], rough=0.7)


def gull_laugh(r, x, t, count, k=1.0, gain=1.0):
    for j in range(count):
        s = gull_note(r, r.uniform(0.12, 0.17), [(0, 720 * k), (0.3, 960 * k), (1, 650 * k)],
                      [(0, 2300), (1, 1500)], [(0, 0.3), (0.2, 1), (1, 0)], rough=0.8)
        place(x, t, s, SR, gain * (1.0 - 0.08 * j))
        t += r.uniform(0.18, 0.23)
        k *= 0.985
    return t


@shots("amb_balance_gull", 4)
def shot_gull(r, i):
    x = zeros(2.6)
    k = r.uniform(0.92, 1.08)
    if i == 0:
        place(x, 0.02, gull_long(r, k), SR)
        gull_laugh(r, x, 0.95, int(r.integers(4, 7)), k, 0.8)
    elif i == 1:
        place(x, 0.02, gull_long(r, k), SR)
        place(x, r.uniform(0.9, 1.1), gull_long(r, k * 0.98), SR, 0.85)
    elif i == 2:
        t = 0.02
        for _ in range(3):
            place(x, t, gull_kyow(r, k), SR, r.uniform(0.8, 1.0))
            t += r.uniform(0.38, 0.5)
        other = zeros(2.6)
        place(other, 0.4, gull_long(r, k * 1.12), SR)
        x += 0.35 * lp(other, 3000.0)
    else:
        place(x, 0.02, gull_kyow(r, k), SR)
        place(x, r.uniform(0.35, 0.45), gull_kyow(r, k * 0.97, 0.4), SR, 0.9)
    return trim(far(x, r, 7000.0, 0.5, 0.1, damp=4000.0))


def clunk(r, dur=0.4, f=90.0):
    t = tv(dur)
    th = tone(ga.sweep(f * 1.4, f * 0.7, t, 0.05)) * ga.ad_env(t, 0.002, 0.06)
    cl = modal([r.uniform(1000, 1200), r.uniform(1600, 1800), r.uniform(2300, 2600)], [1, 0.6, 0.3],
               [0.04, 0.03, 0.02], dur, r=r)
    return th + 0.5 * unit(cl) + 0.3 * noise_hit(r, dur, 300.0, 4000.0, 0.006)


@shots("amb_balance_crane", 2)
def shot_crane(r, i):
    dur = 3.8
    n = int(dur * SR)
    t = np.arange(n) / SR
    up, t1, t2 = r.uniform(0.5, 0.8), 0.25, r.uniform(2.6, 2.9)
    s = np.clip((t - t1) / up, 0, 1) ** 2 * (3 - 2 * np.clip((t - t1) / up, 0, 1)) - np.clip((t - t2) / 0.6, 0, 1)
    s = np.clip(s, 0, 1) * (1.0 - 0.08 * np.exp(-((t - 1.8) / 0.3) ** 2)) * (1.0 + 0.01 * smooth(r, n, 3.0))
    f = 35.0 + r.uniform(230, 300) * s
    motor = tone(f, ((1, 0.6), (2, 1.0), (3, 0.35), (4, 0.25), (6, 0.18), (7.3, 0.1), (18, 0.015)))
    grind = bp(r.standard_normal(n), 400.0, 2500.0) * (0.6 + 0.4 * np.sin(TAU * np.cumsum(f / 2) / SR))
    x = (unit(motor) + 0.2 * unit(grind)) * s ** 0.7
    place(x, 0.1, clunk(r), SR, 0.8)
    place(x, t2 + 0.62, clunk(r, f=80.0), SR, 0.9)
    return trim(far(x, r, 4500.0, 1.4, 0.35, damp=2500.0))


@shots("amb_balance_chain", 3)
def shot_balance_chain(r, i):
    return trim(far(chain(r, 1.6, heavy=True, rate=26.0), r, 4500.0, 1.2, 0.3, damp=3000.0))


def church_bell(r, prime, dur, amps=(0.5, 0.6, 0.55, 0.2, 1.0, 0.3, 0.2, 0.3, 0.15), tau_scale=1.0):
    """A bell: hum, prime, tierce (minor third), quint, nominal ... each partial split into
    a slightly detuned pair so it warbles as it dies away."""
    ratios = (0.5, 1.0, 1.19, 1.5, 2.0, 2.51, 2.66, 3.01, 4.07)
    taus = (7.0, 4.5, 3.5, 2.8, 2.8, 1.6, 1.3, 1.1, 0.7)
    t = tv(dur)
    out = np.zeros(len(t))
    for q, a, tau in zip(ratios, amps, taus):
        fq = prime * q
        if fq > 0.45 * SR:
            continue
        beat = r.uniform(0.3, 1.2)
        for d in (-beat / 2, beat / 2):
            out += 0.5 * a * np.sin(TAU * (fq + d) * t + r.uniform(0, TAU)) * np.exp(-t / (tau * tau_scale))
    out *= np.minimum(t / 0.002, 1.0) * rcos_env(len(t), 0.0, min(0.5 * dur, 1.2))
    return unit(out) + 0.15 * noise_hit(r, dur, 800.0, 6000.0, 0.005)


@shots("amb_balance_buoy", 2)
def shot_buoy(r, i):
    x = zeros(5.0)
    f = r.uniform(300, 380)
    times = [0.02, r.uniform(1.1, 1.5)] + ([r.uniform(2.4, 2.8)] if r.random() < 0.6 else [])
    for j, t0 in enumerate(times):
        place(x, t0, church_bell(r, f, 5.0 - t0, tau_scale=0.45), SR, (1.0, 0.65, 0.45)[j])
    return trim(far(x, r, 4000.0, 1.2, 0.2, damp=3000.0))


@shots("amb_balance_foghorn", 2)
def shot_foghorn(r, i):
    held = r.uniform(2.4, 3.0)
    dur = held + 0.5
    n = int(dur * SR)
    t = np.arange(n) / SR
    f0 = r.uniform(85, 105)
    drop = np.clip((t - held + 0.1) / 0.35, 0, 1)
    f = f0 * (1.0 + 0.02 * (1 - np.exp(-t / 0.2))) * (1.0 - 0.28 * drop ** 1.5)
    ph = TAU * np.cumsum(f) / SR
    s = np.zeros(n)
    for k in range(1, 24):
        g = (0.35 + resonance(380.0, k * f, 2.0)) / k ** 0.9
        s += g * np.sin(k * ph) * (k * f < 8000)
    env = rcos_env(n, 0.35, 0.05) * (1.0 - 0.85 * drop)
    x = s * env + 0.03 * unit(bp(r.standard_normal(n), 200.0, 1200.0)) * env
    x = hp(lp(x, 1400.0), 60.0)
    y = np.concatenate([x, np.zeros(int(1.8 * SR))])
    for dly, g in ((r.uniform(0.6, 0.8), 0.32), (r.uniform(1.3, 1.6), 0.16)):
        d = int(dly * SR)
        y[d:d + n] += lp(x, 900.0) * g
    return trim(reverb(y, r, 3.4, 900.0, 0.45, predelay=0.05))


# ---- clockwork -------------------------------------------------------------
@shots("amb_clockwork_bell", 3)
def shot_toll(r, i):
    x = zeros(6.0)
    if i < 2:
        place(x, 0.02, church_bell(r, (196.0, 147.0)[i], 5.9), SR)
    else:
        place(x, 0.02, church_bell(r, 220.0, 5.9), SR, 0.9)
        place(x, r.uniform(1.2, 1.5), church_bell(r, 165.0, 4.4), SR)
    return trim(far(x, r, 4500.0, 3.2, 0.45, damp=2500.0, predelay=0.05))


@shots("amb_clockwork_ratchet", 3)
def shot_ratchet(r, i):
    dur = r.uniform(0.8, 1.1)
    x = zeros(dur + 0.2)
    t = 0.01
    k = 0
    top = r.uniform(24, 40)
    while t < dur:
        u = t / dur
        rate = 10.0 + top * (np.sin(np.pi * u) ** 0.7 if i != 1 else min(u * 3, 1.0))
        click = modal([r.uniform(2500, 2800), r.uniform(3900, 4300), r.uniform(5500, 6000), 850.0, 1400.0],
                      [1.0, 0.6, 0.3, 0.5, 0.3], [0.005, 0.003, 0.002, 0.009, 0.007], 0.05, r=r)
        place(x, t, click, SR, (1.0 if k % 2 == 0 else 0.7) * r.uniform(0.8, 1.0))
        t += 1.0 / rate
        k += 1
    m = len(x)
    whirr = bp(r.standard_normal(m), 500.0, 2500.0) * np.sin(np.pi * np.arange(m) / m)
    x += 0.06 * unit(whirr)
    return trim(far(x, r, 9000.0, 0.9, 0.25, damp=4000.0))


@shots("amb_clockwork_steam", 2)
def shot_puff(r, i):
    return trim(far(steam(r, r.uniform(0.4, 0.6), body=0.3, bright=1.2), r, 7000.0, 1.4, 0.3, damp=3000.0))


@shots("amb_clockwork_cuckoo", 2)
def shot_cuckoo(r, i):
    hi = r.choice([659.3, 698.5, 740.0])
    lo = hi / 2.0 ** (4.0 / 12.0)
    x = zeros(3.2)
    place(x, 0.0, modal([1800.0, 2900.0], [1.0, 0.5], [0.01, 0.006], 0.05, r=r), SR, 0.3)
    t = 0.15
    for _ in range(2 + i):
        for f in (hi, lo):
            d = 0.3
            n = int(d * SR)
            tt = np.arange(n) / SR
            ff = f * (1.0 - 0.03 * np.exp(-tt / 0.04))
            s = tone(ff, ((1, 1.0), (2, 0.18), (3, 0.07))) * rcos_env(n, 0.025, 0.06)
            breath = bp(r.standard_normal(n), f * 0.85, f * 1.15, 3) * rcos_env(n, 0.025, 0.06)
            chiff = bp(r.standard_normal(n), 2000.0, 6000.0) * np.exp(-tt / 0.012)
            s = unit(s) + 0.12 * unit(breath) + 0.05 * unit(chiff)
            whoof = bp(r.standard_normal(n), 150.0, 600.0) * np.sin(np.pi * tt / d)
            place(x, t - 0.05, 0.05 * unit(whoof), SR)
            place(x, t, s, SR)
            t += d + 0.12
        t += 0.3
    return trim(far(x, r, 6500.0, 1.5, 0.3, damp=3500.0))


# ---- reef ------------------------------------------------------------------
@shots("amb_reef_bubbles", 4)
def shot_bubbles(r, i):
    x = zeros(1.6)
    for _ in range(int(r.integers(14, 34))):
        t0 = min(r.gamma(1.5, 0.18), 1.2)
        rmm = np.exp(r.uniform(np.log(1.2), np.log(6.0)))
        s = bubble(r, 3260.0 / rmm, 0.004 + 0.004 * rmm, r.uniform(0.15, 0.5), SR)
        place(x, t0, s, SR, rmm ** 0.5 * r.uniform(0.4, 1.0))
    return trim(far(x, r, 3200.0, 0.8, 0.3, damp=1800.0))


def whale_voice(r, pts, dur, formant, vib=0.006, rough=0.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = contour(pts, n, SR, 0.06) * (1.0 + vib * np.sin(TAU * r.uniform(4, 6) * t))
    ph = TAU * np.cumsum(f) / SR
    s = np.zeros(n)
    for k in range(1, 16):
        g = (0.15 + resonance(formant, k * f, 1.6)) / k ** 0.7
        s += g * np.sin(k * ph) * (k * f < 3000)
    s *= 1.0 + rough * np.sin(TAU * r.uniform(30, 45) * t)
    return s * rcos_env(n, dur * 0.2, dur * 0.3)


@shots("amb_reef_whale", 3)
def shot_whale(r, i):
    x = zeros(3.5)
    if i == 0:
        place(x, 0.05, whale_voice(r, [(0, 160), (0.5, 260), (0.8, 420), (1, 380)], 2.8, 500.0), SR)
    elif i == 1:
        place(x, 0.05, whale_voice(r, [(0, 110), (0.6, 95), (1, 120)], 2.0, 350.0, rough=0.25), SR)
        place(x, 2.4, whale_voice(r, [(0, 150), (0.7, 640), (1, 560)], 0.8, 700.0), SR, 0.7)
    else:
        place(x, 0.05, whale_voice(r, [(0, 900), (0.3, 820), (1, 340)], 2.6, 800.0, vib=0.015), SR)
    return trim(far(x, r, 2200.0, 5.0, 0.65, damp=1100.0, hp_hz=60.0, predelay=0.08), db_floor=-55.0)


@shots("amb_reef_shrimp", 2)
def shot_shrimp(r, i):
    dur = 1.4
    n = int(dur * SR)
    t = np.arange(n) / SR
    rate = 450.0 * np.exp(-((t - dur * 0.45) / (dur * 0.28)) ** 2)
    clicks = (r.random(n) < rate / SR) * r.lognormal(0.0, 0.7, n) * np.sign(r.standard_normal(n))
    k = r.standard_normal(int(0.0006 * SR)) * np.exp(-np.arange(int(0.0006 * SR)) / (0.00015 * SR))
    x = np.convolve(clicks, k)[:n]
    x = bp(x, 1800.0, 9000.0)
    return trim(reverb(x, r, 0.5, 3000.0, 0.2))


@shots("amb_reef_timber", 3)
def shot_timber(r, i):
    dur = r.uniform(1.6, 2.2)
    cr = stick_slip(r, dur, lambda u: 8.0 + 20.0 * np.sin(np.pi * u) ** 1.3,
                    ((160.0, 0.035, 1.0), (370.0, 0.022, 0.7), (820.0, 0.012, 0.4), (1500.0, 0.006, 0.2)),
                    bend=r.uniform(0.9, 0.95))
    x = np.concatenate([unit(cr), np.zeros(int(0.4 * SR))])
    if i == 2:
        place(x, dur - 0.05, modal([120.0, 240.0, 410.0], [1.0, 0.5, 0.3], [0.05, 0.03, 0.02], 0.3, r=r), SR, 0.7)
    return trim(far(x, r, 1800.0, 1.8, 0.45, damp=1000.0))


# ---- orbital ---------------------------------------------------------------
def beep(f, dur, harm=((1, 1.0), (3, 0.15))):
    n = int(dur * SR)
    return tone(np.full(n, f), harm) * rcos_env(n, 0.003, 0.008)


def radio_voice(r, dur):
    """Unintelligible radio chatter: a glottal harmonic stack whose partials are shaped by
    two formants wandering between vowel targets, chopped into syllables."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    f0 = r.uniform(105, 140) * (1.0 + 0.08 * smooth(r, n, 3.0))
    ph = TAU * np.cumsum(f0) / SR
    vowels = [(700, 1200), (400, 2000), (300, 900), (550, 1700), (650, 1050)]
    seg = int(r.uniform(0.12, 0.2) * SR)
    f1 = np.repeat([vowels[int(r.integers(0, 5))][0] for _ in range(n // seg + 1)], seg)[:n]
    f2 = np.repeat([vowels[int(r.integers(0, 5))][1] for _ in range(n // seg + 1)], seg)[:n]
    f1 = np.convolve(f1, np.ones(800) / 800, mode="same")
    f2 = np.convolve(f2, np.ones(800) / 800, mode="same")
    s = np.zeros(n)
    for k in range(1, 30):
        fk = k * f0
        g = resonance(f1, fk, 5.0) + 0.7 * resonance(f2, fk, 7.0) + 0.02
        s += g * np.sin(k * ph) * (fk < 3500)
    syll = np.maximum(np.sin(TAU * r.uniform(4.0, 5.5) * t + 3.0 * smooth(r, n, 2.0)), 0.0) ** 0.6
    return unit(s) * syll * rcos_env(n, 0.02, 0.05)


def radio_static(r, n):
    return bp(r.standard_normal(n), 400.0, 3200.0) * (0.6 + 0.4 * np.abs(smooth(r, n, 60.0)))


@shots("amb_orbital_radio", 3)
def shot_radio(r, i):
    x = zeros(2.6)
    if i == 0:
        place(x, 0.02, beep(2525.0, 0.25, ((1, 1.0),)), SR, 0.5)
        v = radio_voice(r, r.uniform(1.2, 1.5))
        place(x, 0.32, v, SR)
        t = 0.32 + len(v) / SR + 0.05
        place(x, t, beep(2475.0, 0.25, ((1, 1.0),)), SR, 0.5)
        sq = int(0.14 * SR)
        place(x, t + 0.28, unit(radio_static(r, sq)) * np.exp(-np.arange(sq) / (0.05 * SR)), SR, 0.5)
    elif i == 1:
        place(x, 0.02, tone(np.linspace(1400, 1900, int(0.12 * SR))) * rcos_env(int(0.12 * SR), 0.005, 0.01), SR, 0.5)
        place(x, 0.18, tone(np.linspace(1900, 1300, int(0.14 * SR))) * rcos_env(int(0.14 * SR), 0.005, 0.01), SR, 0.5)
        place(x, 0.45, radio_voice(r, r.uniform(0.6, 0.9)), SR)
    else:
        t = 0.05
        for _ in range(int(r.integers(10, 16))):
            place(x, t, beep(r.choice([1200.0, 2200.0]), 0.05, ((1, 1.0),)), SR, 0.45)
            t += 0.05
        sq = int(0.2 * SR)
        place(x, t + 0.05, unit(radio_static(r, sq)) * np.exp(-np.arange(sq) / (0.07 * SR)), SR, 0.45)
    x = x + 0.05 * unit(radio_static(r, len(x))) * (np.abs(x) > 1e-4).astype(float)
    x = bp(np.tanh(2.0 * bp(x, 300.0, 3400.0)) / 2.0, 300.0, 3400.0)
    return trim(far(x, r, 5000.0, 0.6, 0.2, damp=4000.0))


@shots("amb_orbital_servo", 3)
def shot_servo(r, i):
    dur = r.uniform(0.7, 1.1)
    n = int((dur + 0.25) * SR)
    t = np.arange(n) / SR
    up = np.clip(t / 0.08, 0, 1)
    down = np.clip((t - dur) / 0.1, 0, 1)
    s = up * (1.0 - down) * (1.0 - 0.12 * np.exp(-((t - dur * 0.55) / 0.08) ** 2))
    s += 0.06 * np.sin(TAU * 12.0 * np.maximum(t - dur - 0.1, 0)) * np.exp(-np.maximum(t - dur - 0.1, 0) / 0.05) * (t > dur + 0.1)
    s = np.maximum(s, 0.0)
    f = 150.0 + r.uniform(160, 280) * s
    motor = tone(f, ((1, 0.5), (2, 1.0), (3, 0.4), (4, 0.3), (5, 0.15), (8, 0.1), (11, 0.08)))
    brush = bp(r.standard_normal(n), 2000.0, 7000.0) * (0.5 + 0.5 * np.sin(TAU * np.cumsum(2 * f) / SR))
    x = (unit(motor) + 0.05 * unit(lp(brush, 6000.0))) * np.minimum(s * 3.0, 1.0)
    place(x, dur + 0.12, modal([2400.0, 3900.0], [1.0, 0.5], [0.006, 0.004], 0.05, r=r), SR, 0.5)
    return trim(far(x, r, 9000.0, 0.5, 0.15, damp=5000.0))


PLATE = (1.0, 1.62, 2.18, 2.37, 2.93, 3.51)


@shots("amb_orbital_ping", 3)
def shot_ping(r, i):
    x = zeros(3.8)
    if i == 0:
        f0 = r.uniform(1800, 2400)
        place(x, 0.02, modal([f0 * q * r.uniform(0.99, 1.01) for q in PLATE], [1, 0.6, 0.45, 0.35, 0.25, 0.15],
                             [1.2, 0.9, 0.7, 0.6, 0.45, 0.35], 3.6, r=r), SR)
    elif i == 1:
        f0 = r.uniform(600, 800)
        tt = tv(0.3)
        place(x, 0.02, tone(ga.sweep(160.0, 90.0, tt, 0.05)) * ga.ad_env(tt, 0.002, 0.05), SR, 0.8)
        place(x, 0.02, modal([f0 * q for q in PLATE], [1, 0.7, 0.5, 0.4, 0.3, 0.2], [0.9, 0.7, 0.5, 0.4, 0.3, 0.2],
                             3.0, r=r), SR, 0.7)
    else:
        cr = stick_slip(r, 1.2, lambda u: 14.0 + 18.0 * np.sin(np.pi * u),
                        ((240.0, 0.06, 1.0), (610.0, 0.04, 0.7), (1350.0, 0.025, 0.4), (2400.0, 0.015, 0.2)),
                        bend=1.06)
        place(x, 0.02, unit(cr), SR, 0.8)
        f0 = r.uniform(1500, 2000)
        place(x, 1.25, modal([f0 * q for q in PLATE], [1, 0.6, 0.45, 0.35, 0.25, 0.15], [0.8, 0.6, 0.5, 0.4, 0.3, 0.2],
                             2.4, r=r), SR, 0.5)
    return trim(far(x, r, 8000.0, 1.6, 0.35, damp=4000.0))


@shots("amb_orbital_airlock", 2)
def shot_airlock(r, i):
    dur = 3.0
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    place(x, 0.03, clunk(r, 0.4, 75.0), SR, 0.8)
    th = t - 0.25
    p = np.where(th > 0, np.exp(-th / r.uniform(0.55, 0.8)), 0.0)
    lvl = np.sqrt(p) * np.minimum(np.maximum(th, 0) / 0.03, 1.0)
    hiss = ga.svf_bandpass(r.standard_normal(n), 700.0 + 3000.0 * p, 1.2, SR)
    x += unit(hiss) * lvl * 0.8 + 0.25 * unit(hp(r.standard_normal(n), 400.0)) * lvl * p
    place(x, r.uniform(2.3, 2.5), clunk(r, 0.45, 60.0), SR, 0.9)
    return trim(far(x, r, 5000.0, 1.4, 0.45, damp=3500.0))


@shots("amb_orbital_blip", 3)
def shot_blip(r, i):
    notes = (1568.0, 1760.0, 2093.0, 2349.0, 2637.0, 3136.0)
    x = zeros(0.9)
    t = 0.01
    for _ in range(int(r.integers(5, 11))):
        d = r.uniform(0.022, 0.045)
        place(x, t, beep(notes[int(r.integers(0, len(notes)))], d), SR, r.uniform(0.6, 1.0))
        t += d + r.uniform(0.012, 0.07)
        if t > 0.75:
            break
    return trim(far(x, r, 6000.0, 0.6, 0.18, damp=5000.0))


# ---- ascent ----------------------------------------------------------------
def siren_voice(f):
    ph = TAU * np.cumsum(f) / SR
    s = np.zeros(len(f))
    for k, a in ((1, 1.0), (2, 0.25), (3, 0.45), (4, 0.1), (5, 0.25), (7, 0.12)):
        s += a * (0.5 + resonance(1500.0, k * f, 1.5)) * np.sin(k * ph) * (k * f < 9000)
    return s


@shots("amb_ascent_siren", 2)
def shot_siren(r, i):
    dur = 6.5
    n = int(dur * SR)
    t = np.arange(n) / SR
    if i == 0:
        f = 650.0 + 550.0 * (0.5 - 0.5 * np.cos(TAU * t / r.uniform(3.0, 3.6)))
    else:
        f = np.where((t // 0.6) % 2 == 0, 466.0, 622.0).astype(float)
        f = np.convolve(np.pad(f, 400, mode="edge"), np.ones(800) / 800, mode="same")[400:-400]
    f = f * (1.0 + 0.02 * (0.5 - t / dur))
    x = siren_voice(f) * rcos_env(n, 1.6, 2.2)
    x = hp(lp(x, 1800.0), 250.0)
    y = np.concatenate([x, np.zeros(int(1.0 * SR))])
    for dly, g in ((0.21, 0.4), (0.43, 0.25), (0.8, 0.15)):
        d = int(dly * SR)
        y[d:d + n] += lp(x, 1500.0) * g
    return trim(reverb(y, r, 2.8, 1800.0, 0.55, predelay=0.03))


@shots("amb_ascent_crackle", 3)
def shot_crackle(r, i):
    dur = 1.1
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    buzz_src = tone(np.full(n, 120.0), [(k, 1.0 / k ** 0.5) for k in range(1, 50)])
    for _ in range(int(r.integers(2, 5))):
        t0 = r.uniform(0.0, dur - 0.3)
        d = r.uniform(0.05, 0.25)
        gate = ((t > t0) & (t < t0 + d)).astype(float) * (smooth(r, n, 80.0) > -0.3)
        gate = np.convolve(gate, np.ones(40) / 40, mode="same")
        x += bp(buzz_src, 600.0, 6000.0) * gate * r.uniform(0.3, 0.6)
        for _ in range(int(r.integers(4, 16))):
            ts = t0 + r.uniform(0, d)
            place(x, ts, noise_hit(r, 0.02, 2500.0, None, 0.0012), SR, r.uniform(0.4, 1.0))
    return trim(reverb(lp(x, 9000.0), r, 0.4, 5000.0, 0.1))


@shots("amb_ascent_heli", 2)
def shot_heli(r, i):
    dur = 8.0
    n = int(dur * SR)
    e = np.arange(n) / SR
    rate = r.uniform(19.0, 22.0)
    src = np.zeros(n)
    slaps = [noise_hit(r, 0.05, 60.0, 700.0, 0.012) + 0.6 * modal([90.0], [1.0], [0.015], 0.05) for _ in range(6)]
    k = 0
    while k / rate < dur:
        place(src, k / rate, slaps[k % 6], SR, 1.0 + 0.25 * (k % 4 == 0))
        k += 1
    tail = tone(np.full(n, r.uniform(90, 105)), [(k, 1.0 / k) for k in range(1, 9)])
    src = unit(src) + 0.12 * unit(tail)
    v, d = r.uniform(48, 62), r.uniform(170, 240)
    y, close = doppler_pass(src, SR, v if i == 0 else -v, d, dur * 0.5)
    dark = lp(y, 500.0)
    y = dark + (y - dark) * close ** 2
    return trim(reverb(y * rcos_env(n, 0.8, 1.2), r, 2.0, 2000.0, 0.25, predelay=0.04))


@shots("amb_ascent_drone", 2)
def shot_drone(r, i):
    dur = 4.0
    n = int(dur * SR)
    src = np.zeros(n)
    for fr in (185.0, 192.0, 199.0, 207.0):
        f = fr * r.uniform(0.95, 1.1) * (1.0 + 0.02 * smooth(r, n, 1.5))
        src += tone(f, [(k, 1.0 / k ** 0.8) for k in range(1, 14)] + [(7.0 * 1.0, 0.08)])
    src = unit(src) + 0.08 * unit(bp(r.standard_normal(n), 2000.0, 8000.0))
    y, close = doppler_pass(src, SR, r.uniform(10, 16), r.uniform(5, 9), dur * r.uniform(0.45, 0.55))
    dark = lp(y, 1200.0)
    y = dark + (y - dark) * close
    return trim(reverb(y * rcos_env(n, 0.5, 0.7), r, 1.2, 3000.0, 0.2))


# ==========================================================================
# generation and verification
# ==========================================================================
def gen_shots(only=""):
    print("one-shots:")
    for name, (fn, count) in SHOTS.items():
        if only and only not in name:
            continue
        for i in range(count):
            clip = "%s_%d" % (name, i + 1)
            save_shot(clip, fn(rng(clip), i))


def gen_beds(only=""):
    print("beds:")
    for name, (fn, _rms) in BEDS.items():
        if only and only not in name:
            continue
        fn()


def expected_files():
    files = [name + ".ogg" for name in BEDS]
    for name, (_fn, count) in SHOTS.items():
        files += ["%s_%d.ogg" % (name, i + 1) for i in range(count)]
    return files


def verify():
    import soundfile as sf
    ok = True
    total = 0
    print("verify:")
    for name, (_fn, want_rms) in BEDS.items():
        path = os.path.join(OUT, name + ".ogg")
        if not os.path.exists(path):
            print("  %-26s MISSING" % name)
            ok = False
            continue
        total += os.path.getsize(path)
        x, sr = sf.read(path, always_2d=True)
        info = sf.info(path)
        dur = len(x) / sr
        peak = ga.db(np.max(np.abs(x)))
        rms = ga.db(np.sqrt(np.mean(x ** 2)))
        steps = np.max(np.abs(np.diff(x, axis=0)), axis=1)
        p999 = np.quantile(steps, 0.999)
        wrap = np.max(np.abs(x[0] - x[-1]))
        curv = np.max(np.abs(np.diff(x, n=2, axis=0)), axis=1)
        c999 = np.quantile(curv, 0.999)
        seam = np.concatenate([x[-3:], x[:3]])
        seam_curv = np.max(np.abs(np.diff(seam, n=2, axis=0)))
        k = int(0.05 * sr)
        lvl_jump = abs(ga.db(np.sqrt(np.mean(x[-k:] ** 2))) - ga.db(np.sqrt(np.mean(x[:k] ** 2))))
        spec = np.abs(np.fft.rfft(x.mean(axis=1))) ** 2
        f = np.fft.rfftfreq(len(x), 1.0 / sr)
        lf = np.sum(spec[f < 80.0]) / np.sum(spec)
        good = (info.format == "OGG" and sr == BSR and x.shape[1] == 2 and 45.0 <= dur <= 90.0 and
                abs(rms - want_rms) < 1.0 and peak < -3.0 and np.all(np.isfinite(x)) and
                wrap <= p999 * 1.5 and seam_curv <= c999 * 1.5 and lvl_jump < 4.0 and lf < 0.35)
        ok &= bool(good)
        print("  %-26s %5.1f s %d Hz %dch rms %6.2f (want %.0f) peak %6.2f | wrap %.4f (p99.9 %.4f) curv %.4f "
              "(p99.9 %.4f) 50ms-jump %.1f dB | <80Hz %2.0f%% | %4d KB %s" % (
                  name, dur, sr, x.shape[1], rms, want_rms, peak, wrap, p999, seam_curv, c999, lvl_jump, lf * 100,
                  os.path.getsize(path) // 1024, "ok" if good else "FAIL"))
    for name, (_fn, count) in SHOTS.items():
        for i in range(count):
            clip = "%s_%d" % (name, i + 1)
            path = os.path.join(OUT, clip + ".ogg")
            if not os.path.exists(path):
                print("  %-30s MISSING" % clip)
                ok = False
                continue
            total += os.path.getsize(path)
            x, sr = sf.read(path, always_2d=True)
            dur = len(x) / sr
            peak = ga.db(np.max(np.abs(x)))
            edge = max(np.max(np.abs(x[:8])), np.max(np.abs(x[-8:])))
            good = (sr == SR and x.shape[1] == 1 and 0.2 <= dur <= 10.0 and abs(peak - SHOT_PEAK_DB) < 1.5 and
                    edge < 0.01 and np.all(np.isfinite(x)))
            ok &= bool(good)
            print("  %-30s %5.2f s peak %6.2f rms %6.1f edge %.4f %3d KB %s" % (
                clip, dur, peak, ga.db(np.sqrt(np.mean(x ** 2))), edge, os.path.getsize(path) // 1024,
                "ok" if good else "FAIL"))
    want = set(expected_files())
    stray = sorted(fn for fn in os.listdir(OUT) if fn.startswith("amb_") and not fn.endswith(".import") and fn not in want)
    if stray:
        print("  stray files not made by this generator: " + ", ".join(stray))
        ok = False
    print("  total size %.2f MB (budget %.0f MB) %s" % (total / 1e6, SIZE_BUDGET / 1e6, "ok" if total < SIZE_BUDGET else "FAIL"))
    ok &= total < SIZE_BUDGET
    print("RESULT: " + ("ALL OK" if ok else "PROBLEMS FOUND"))
    return ok


def main():
    args = sys.argv[1:]
    only = ""
    for a in args:
        if a.startswith("--only="):
            only = a[len("--only="):]
    if "--verify" not in args:
        if "--shots" not in args:
            gen_beds(only)
        if "--beds" not in args:
            gen_shots(only)
        if only:
            return
    sys.exit(0 if verify() else 1)


if __name__ == "__main__":
    main()
