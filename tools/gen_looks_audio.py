#!/usr/bin/env python3
"""Jump Circuit - finish-celebration sounds for the v2.0 looks (balloons, disco, meteor, pixel burst).

Writes audio/fin_<id>.wav for the four LooksExt finishes (player/looks_ext.gd, play_finish). The
synthesis helpers, the sample rate, the seed scheme and the loudness are shared with
tools/gen_audio.py, so these sit beside the original fin_* clips.

Usage (from anywhere):
    python tools/gen_looks_audio.py            # generate the four clips, then verify them
    python tools/gen_looks_audio.py --verify   # only verify the files on disk

Deterministic and original: maths and seeded noise only. Requires numpy.
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_audio as ga  # noqa: E402  (the shared helpers; gen_audio itself is not changed)

SR = ga.SR
TAU = ga.TAU


def sfx_fin_balloons():
    # a few squeaky balloon pops over a rising airy whoosh, and a little cheer blip at the end
    r = ga.rng_for("fin_balloons")
    dur = 1.8
    n = int(round(dur * SR))
    t = ga.tvec(dur)
    x = np.zeros(n)
    wh = ga.svf_bandpass(r.standard_normal(n), 500.0 + 1400.0 * t / dur, 3.0, SR)
    x += 0.35 * wh / np.max(np.abs(wh)) * np.minimum(t / 0.5, 1.0) * np.exp(-np.maximum(t - 1.2, 0.0) / 0.25)
    for _ in range(7):
        t0 = r.uniform(0.05, 1.3)
        tp = ga.tvec(0.09)
        pop = ga.osc(ga.sweep(1900.0, 380.0, tp, 0.09)) * ga.ad_env(tp, 0.001, 0.03)
        snap = ga.fft_band(r.standard_normal(len(tp)), SR, 1500.0, 7000.0, 2) * np.exp(-tp / 0.006)
        ga.place(x, t0, pop + 0.5 * snap / np.max(np.abs(snap)), gain=r.uniform(0.35, 0.6))
    for k, f in enumerate((784.0, 988.0, 1318.0)):
        tb = ga.tvec(0.16)
        blip = (ga.osc(np.full(len(tb), f)) + 0.3 * ga.osc(np.full(len(tb), 2.0 * f))) * ga.ad_env(tb, 0.004, 0.07)
        ga.place(x, 1.3 + 0.07 * k, blip, gain=0.3)
    ga.finish_sfx("fin_balloons", x, fin=0.004, fout=0.15)


def sfx_fin_disco():
    # four-on-the-floor: a kick, bright off-beat chord stabs, and closed hi-hats, for about two bars
    r = ga.rng_for("fin_disco")
    dur = 2.4
    n = int(round(dur * SR))
    x = np.zeros(n)
    beat = 0.5
    for k in range(5):
        t0 = k * beat
        tk = ga.tvec(0.3)
        kick = ga.osc(ga.sweep(150.0, 46.0, tk, 0.12)) * ga.ad_env(tk, 0.002, 0.09)
        ga.place(x, t0, kick, gain=0.9)
    for k in range(4):
        t0 = k * beat + beat / 2.0
        ts = ga.tvec(0.22)
        chord = sum(ga.osc(np.full(len(ts), ga.mtof(m))) for m in (60, 64, 67, 71))
        stab = chord / 4.0 * ga.ad_env(ts, 0.004, 0.06)
        ga.place(x, t0, stab, gain=0.45 if k % 2 == 0 else 0.35)
    for k in range(int(dur / (beat / 2.0))):
        t0 = k * beat / 2.0
        th = ga.tvec(0.05)
        hat = ga.fft_band(r.standard_normal(len(th)), SR, 6000.0, 12000.0, 2) * np.exp(-th / 0.012)
        ga.place(x, t0 + 0.01, hat / np.max(np.abs(hat)), gain=0.14 if k % 2 == 0 else 0.08)
    ga.finish_sfx("fin_disco", x, fin=0.004, fout=0.12)


def sfx_fin_meteor():
    # a falling whistle that gets louder, a boom on impact, and a crackling rumble after it
    r = ga.rng_for("fin_meteor")
    dur = 2.0
    n = int(round(dur * SR))
    t = ga.tvec(dur)
    x = np.zeros(n)
    fc = ga.sweep(3200.0, 260.0, np.minimum(t, 0.55), 0.55)
    fall = ga.svf_bandpass(r.standard_normal(n), fc, 2.5, SR)
    env_fall = np.clip(t / 0.25, 0.0, 1.0) * np.exp(-np.maximum(t - 0.55, 0.0) / 0.12) * (t < 0.6)
    x += 0.5 * fall / np.max(np.abs(fall)) * env_fall
    ti = ga.tvec(1.4)
    boom = ga.osc(ga.sweep(120.0, 34.0, ti, 0.9)) * ga.ad_env(ti, 0.002, 0.35)
    body = ga.fft_band(r.standard_normal(len(ti)), SR, 40.0, 900.0, 2) * ga.ad_env(ti, 0.001, 0.18)
    ga.place(x, 0.55, boom + 0.8 * body / np.max(np.abs(body)), gain=0.9)
    crackle = ga.fft_band(r.standard_normal(n), SR, 1500.0, 7000.0, 2)
    crackle *= (r.random(n) > 0.985) * np.exp(-np.maximum(t - 0.6, 0.0) / 0.3)
    x += 0.35 * crackle / (np.max(np.abs(crackle)) + 1e-9)
    ga.finish_sfx("fin_meteor", x, fin=0.002, fout=0.2)


def sfx_fin_pixelburst():
    # an 8-bit arpeggio of square blips climbing up, bit-crushed, then a sparkle bloop as the pixels fly
    r = ga.rng_for("fin_pixelburst")
    dur = 1.3
    n = int(round(dur * SR))
    x = np.zeros(n)
    notes = (523.25, 659.25, 783.99, 1046.5, 1318.5, 1567.98)
    for k, f in enumerate(notes):
        tb = ga.tvec(0.085)
        sq = np.sign(np.sin(TAU * f * tb))
        crushed = np.round(sq * 6.0) / 6.0 * ga.ad_env(tb, 0.001, 0.05)
        ga.place(x, 0.045 * k, crushed, gain=0.22)
    for k in range(6):
        t0 = 0.3 + r.uniform(0.0, 0.5)
        tb = ga.tvec(0.06)
        blip = np.sign(np.sin(TAU * r.uniform(1800.0, 3200.0) * tb)) * ga.ad_env(tb, 0.001, 0.02)
        ga.place(x, t0, blip, gain=0.12)
    tb = ga.tvec(0.7)
    bloop = ga.osc(ga.sweep(600.0, 1900.0, tb, 0.25)) * ga.ad_env(tb, 0.002, 0.2)
    ga.place(x, 0.35, bloop, gain=0.3)
    ga.finish_sfx("fin_pixelburst", x, fin=0.001, fout=0.12)


SPEC = {"fin_balloons": 1.8, "fin_disco": 2.4, "fin_meteor": 2.0, "fin_pixelburst": 1.3}


def verify():
    ok = True
    print("verify:")
    for name, want in SPEC.items():
        x, sr, sw = ga.read_wav(name)
        dur = len(x) / sr
        peak = ga.db(np.max(np.abs(x)))
        edge = max(abs(x[0, 0]), abs(x[-1, 0]))
        good = (sr == SR and sw == 2 and x.shape[1] == 1 and abs(dur - want) < 0.02 and
                abs(peak - ga.SFX_PEAK_DB) < 0.2 and edge < 0.002 and np.all(np.isfinite(x)))
        ok &= bool(good)
        print("  %-16s %5.2f s peak %6.2f dB edge %.5f %s" % (name, dur, peak, edge, "ok" if good else "FAIL"))
    print("RESULT: " + ("ALL OK" if ok else "PROBLEMS FOUND"))
    return ok


def main():
    args = set(sys.argv[1:])
    if "--verify" not in args:
        for fn in (sfx_fin_balloons, sfx_fin_disco, sfx_fin_meteor, sfx_fin_pixelburst):
            fn()
    sys.exit(0 if verify() else 1)


if __name__ == "__main__":
    main()
