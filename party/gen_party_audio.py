#!/usr/bin/env python3
"""Jump Circuit - Party Mode sound effects.

Synthesises the audio/party_*.wav clips PartySfx plays (party/party_sfx.gd), with
the same helpers and conventions as tools/gen_audio.py: original, generated from
maths + seeded noise, deterministic, 16-bit mono 44.1 kHz, peak -3 dBFS.

Usage (from anywhere):
    python party/gen_party_audio.py
then run the engine once with --import so Godot picks the new files up.
Requires numpy.
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "tools"))
import gen_audio as ga  # noqa: E402  (shared helpers: osc, sweep, ad_env, fft_band, bell, place, finish_sfx ...)

SR = ga.SR
TAU = ga.TAU
tvec = ga.tvec
osc = ga.osc
sweep = ga.sweep
ad_env = ga.ad_env
fft_band = ga.fft_band
place = ga.place
mtof = ga.mtof


def noise(name, n):
    return ga.rng_for("party_" + name).standard_normal(n)


def save(name, x, fout=0.02):
    ga.finish_sfx("party_" + name, x, fout=fout)


def p_pickup():
    # a bright rising arpeggio with a sparkle tail
    x = np.zeros(int(0.5 * SR))
    for i, m in enumerate((72, 76, 79, 84)):
        place(x, 0.045 * i, ga.bell(mtof(m), 0.5 - 0.045 * i, SR, 0.12) * (0.8 + 0.1 * i))
    t = tvec(0.5)
    sp = fft_band(noise("pickup", len(t)), SR, 5000.0, 11000.0, 2) * ad_env(t, 0.1, 0.12)
    save("pickup", x + 0.15 * sp / np.max(np.abs(sp)))


def p_roll():
    # slot-machine ticks speeding up, then a ding
    x = np.zeros(int(0.55 * SR))
    tt = 0.0
    k = 0
    while tt < 0.36:
        place(x, tt, ga.bell(mtof(84 + (k % 3) * 2), 0.04, SR, 0.012) * 0.5)
        tt += 0.05 * (1.0 - 0.5 * tt / 0.36)
        k += 1
    place(x, 0.38, ga.bell(mtof(91), 0.17, SR, 0.09))
    save("roll", x)


def p_whoosh():
    t = tvec(0.35)
    n = noise("whoosh", len(t))
    fc = sweep(500.0, 2600.0, t, 0.2)
    y = ga.svf_bandpass(n, fc, 1.6, SR) * np.sin(np.pi * np.clip(t / 0.35, 0, 1)) ** 1.5
    save("whoosh", y)


def p_hit():
    t = tvec(0.28)
    body = osc(sweep(220.0, 70.0, t, 0.1)) * ad_env(t, 0.001, 0.07)
    crack = fft_band(noise("hit", len(t)), SR, 1200.0, 7000.0, 2) * np.exp(-t / 0.02)
    save("hit", body + 0.7 * crack / np.max(np.abs(crack)))


def p_ko():
    # a big thump, a descending slide and a comic "bonk" bell
    t = tvec(0.9)
    thump = osc(sweep(160.0, 40.0, t, 0.25)) * ad_env(t, 0.002, 0.18)
    slide = (osc(sweep(900.0, 120.0, t, 0.7)) + 0.3 * osc(sweep(1800.0, 240.0, t, 0.7))) * ad_env(t, 0.01, 0.35)
    x = thump + 0.4 * slide
    place(x, 0.0, ga.bell(mtof(64), 0.5, SR, 0.15) * 0.5)
    save("ko", x, fout=0.08)


def p_boom():
    t = tvec(1.4)
    n = noise("boom", len(t))
    rumble = fft_band(n, SR, None, 180.0, 3) * ad_env(t, 0.004, 0.45)
    blast = fft_band(n, SR, 200.0, 3000.0, 2) * ad_env(t, 0.001, 0.12)
    sub = osc(sweep(90.0, 35.0, t, 0.5)) * ad_env(t, 0.003, 0.35)
    save("boom", rumble / np.max(np.abs(rumble)) + 0.6 * blast / np.max(np.abs(blast)) + 0.8 * sub, fout=0.1)


def p_zap():
    t = tvec(0.5)
    n = noise("zap", len(t))
    buzz = np.sign(np.sin(TAU * np.cumsum(90.0 + 60.0 * n.clip(-2, 2)) / SR))
    crackle = fft_band(n, SR, 2000.0, 9000.0, 2)
    gate = (np.abs(fft_band(noise("zap2", len(t)), SR, None, 40.0, 2)) > 0.05).astype(float)
    y = (0.5 * buzz + crackle / np.max(np.abs(crackle))) * gate * ad_env(t, 0.002, 0.18)
    y += osc(sweep(2400.0, 300.0, t, 0.3)) * ad_env(t, 0.001, 0.05) * 0.5
    save("zap", fft_band(y, SR, 80.0, 12000.0, 2))


def p_charge():
    # a long rising hum with a shimmering top (also used as the looping charge hum)
    t = tvec(1.6)
    f = sweep(110.0, 440.0, t, 1.5)
    y = osc(f) + 0.5 * osc(f * 2.01) + 0.25 * osc(f * 3.0)
    y *= 0.6 + 0.4 * np.sin(TAU * sweep(6.0, 22.0, t, 1.5) * t)
    y *= np.minimum(t / 0.15, 1.0) * np.minimum((1.6 - t) / 0.1, 1.0)
    sh = fft_band(noise("charge", len(t)), SR, 3000.0, 8000.0, 2) * (t / 1.6)
    save("charge", y + 0.2 * sh / np.max(np.abs(sh)), fout=0.05)


def p_beam():
    t = tvec(1.0)
    f = sweep(900.0, 180.0, t, 0.8)
    y = (osc(f) + 0.6 * osc(f * 1.5) + 0.4 * osc(f * 0.5)) * ad_env(t, 0.01, 0.4)
    roar = fft_band(noise("beam", len(t)), SR, 150.0, 2500.0, 2) * ad_env(t, 0.02, 0.35)
    save("beam", y + 0.8 * roar / np.max(np.abs(roar)), fout=0.08)


def p_slash():
    t = tvec(0.22)
    n = noise("slash", len(t))
    y = ga.svf_bandpass(n, sweep(5000.0, 1400.0, t, 0.15), 2.5, SR) * ad_env(t, 0.004, 0.06)
    ring = ga.bell(2400.0, 0.22, SR, 0.05) * 0.25
    save("slash", y + ring)


def p_powerup():
    # a triumphant major arpeggio up two octaves over a swelling chord
    x = np.zeros(int(1.0 * SR))
    for i, m in enumerate((60, 64, 67, 72, 76, 79, 84)):
        place(x, 0.05 * i, ga.bell(mtof(m), 0.9 - 0.05 * i, SR, 0.2) * 0.7)
    t = tvec(1.0)
    pad = sum(osc(np.full(len(t), mtof(m))) for m in (60, 64, 67)) * ad_env(t, 0.25, 0.4)
    save("powerup", x + 0.25 * pad, fout=0.08)


def p_pop():
    t = tvec(0.14)
    y = osc(sweep(1400.0, 300.0, t, 0.05)) * ad_env(t, 0.001, 0.03)
    y += 0.5 * fft_band(noise("pop", len(t)), SR, 1500.0, 8000.0, 2) * np.exp(-t / 0.006)
    save("pop", y)


def p_spring():
    t = tvec(0.5)
    f = 300.0 * (1.0 + 0.6 * np.exp(-t / 0.15) * np.sin(TAU * 18.0 * t))
    y = (osc(f) + 0.4 * osc(f * 2.0)) * ad_env(t, 0.002, 0.18)
    save("spring", y)


def p_freeze():
    t = tvec(0.8)
    n = noise("freeze", len(t))
    crackle = fft_band(n, SR, 3000.0, 11000.0, 2) * (np.abs(n) > 1.8)
    x = crackle * ad_env(t, 0.01, 0.35)
    for i, m in enumerate((96, 91, 100)):
        place(x, 0.05 * i, ga.bell(mtof(m), 0.6, SR, 0.2) * 0.4)
    save("freeze", x, fout=0.06)


def p_warp():
    t = tvec(0.7)
    f = sweep(200.0, 1600.0, t, 0.35) * (1.0 + 0.05 * np.sin(TAU * 30.0 * t))
    y = (osc(f) + 0.5 * osc(f * 1.5)) * np.sin(np.pi * np.clip(t / 0.7, 0, 1))
    save("warp", y, fout=0.05)


def p_chime():
    x = np.zeros(int(0.9 * SR))
    for i, m in enumerate((79, 83, 86, 91)):
        place(x, 0.08 * i, ga.bell(mtof(m), 0.8, SR, 0.25) * 0.6)
    save("chime", x, fout=0.06)


def p_wind():
    t = tvec(1.4)
    n = noise("wind", len(t))
    fc = 500.0 + 350.0 * np.sin(TAU * 1.3 * t) + 200.0 * np.sin(TAU * 3.1 * t)
    y = ga.svf_bandpass(n, fc, 3.0, SR) * np.sin(np.pi * np.clip(t / 1.4, 0, 1))
    save("wind", y, fout=0.1)


def p_clank():
    t = tvec(0.4)
    y = sum(a * np.sin(TAU * f * t) * np.exp(-t / d) for f, a, d in ((523.0, 1.0, 0.12), (1391.0, 0.6, 0.07), (2311.0, 0.4, 0.04), (3187.0, 0.25, 0.03)))
    y += 0.4 * fft_band(noise("clank", len(t)), SR, 2000.0, 8000.0, 2) * np.exp(-t / 0.005)
    save("clank", y)


def p_tick():
    # one crisp roulette tick: a short wooden click with a tiny pitch
    t = tvec(0.06)
    y = osc(1900.0) * np.exp(-t / 0.008) + 0.5 * osc(950.0) * np.exp(-t / 0.014)
    y += 0.3 * fft_band(noise("tick", len(t)), SR, 3000.0, 9000.0, 2) * np.exp(-t / 0.003)
    save("tick", y, fout=0.01)


def p_land():
    # the roulette lands: a bright two-note ding with a sparkle
    x = np.zeros(int(0.6 * SR))
    place(x, 0.0, ga.bell(mtof(79), 0.5, SR, 0.14) * 0.8)
    place(x, 0.07, ga.bell(mtof(86), 0.5, SR, 0.2))
    t = tvec(0.6)
    sp = fft_band(noise("land", len(t)), SR, 6000.0, 12000.0, 2) * ad_env(t, 0.08, 0.1)
    save("land", x + 0.12 * sp / np.max(np.abs(sp)), fout=0.05)


def p_warn():
    # "Targeted!": a falling two-tone alarm blip
    x = np.zeros(int(0.5 * SR))
    for i, f in enumerate((880.0, 660.0, 880.0, 660.0)):
        t = tvec(0.1)
        blip = (osc(f * (1.0 + 0.02 * np.sin(TAU * 40.0 * t))) + 0.4 * osc(f * 2.0)) * np.minimum(t / 0.005, 1.0) * np.exp(-t / 0.07)
        place(x, 0.11 * i, blip)
    save("warn", x, fout=0.04)


def p_tally():
    # a tiny coin-counter blip for the results tallies
    t = tvec(0.07)
    y = (osc(1568.0) + 0.5 * osc(2349.0)) * np.minimum(t / 0.003, 1.0) * np.exp(-t / 0.025)
    save("tally", y, fout=0.012)


def p_fanfare():
    # MVP callout: a short rising brass-ish fanfare
    x = np.zeros(int(1.1 * SR))
    for i, (m, d) in enumerate(((67, 0.14), (72, 0.14), (76, 0.14), (79, 0.7))):
        tt = (0.0, 0.14, 0.28, 0.42)[i]
        t = tvec(d + 0.1)
        f = mtof(m)
        y = (osc(f) + 0.5 * osc(f * 2.0) + 0.25 * osc(f * 3.0)) * np.minimum(t / 0.01, 1.0) * np.exp(-t / (0.25 if i == 3 else 0.12))
        place(x, tt, y * 0.6)
        place(x, tt, ga.bell(f * 2.0, d + 0.1, SR, 0.3) * 0.25)
    save("fanfare", x, fout=0.1)



# ---- the second item wave (homing shell, leader strike, fake box, turbo, ghost, decoy, shockwave) ----

def p_shell():
    # a toy-rocket launch: a pop, then a rising whistle with a wobbling zing
    t = tvec(0.55)
    pop = osc(sweep(900.0, 200.0, t, 0.04)) * ad_env(t, 0.001, 0.025)
    f = sweep(500.0, 2200.0, t, 0.45) * (1.0 + 0.04 * np.sin(TAU * 24.0 * t))
    zing = (osc(f) + 0.35 * osc(f * 2.0)) * np.minimum(t / 0.02, 1.0) * np.exp(-t / 0.3)
    hiss = fft_band(noise("shell", len(t)), SR, 2500.0, 9000.0, 2) * ad_env(t, 0.02, 0.2)
    save("shell", pop + 0.5 * zing + 0.25 * hiss / np.max(np.abs(hiss)), fout=0.06)


def p_siren():
    # the Leader Strike tell: a rising, worrying two-tone siren swell
    t = tvec(1.6)
    f = 440.0 * (1.0 + 0.5 * (t / 1.6)) * (1.0 + 0.25 * np.sign(np.sin(TAU * 3.0 * t)))
    y = (osc(f) + 0.4 * osc(f * 2.0) + 0.2 * osc(f * 3.0)) * (0.35 + 0.65 * t / 1.6)
    y *= np.minimum(t / 0.05, 1.0) * np.minimum((1.6 - t) / 0.08, 1.0)
    sub = osc(sweep(60.0, 120.0, t, 1.5)) * (t / 1.6) ** 2
    save("siren", y + 0.5 * sub, fout=0.05)


def p_strike():
    # an orbital hit: a razor crack, a huge boom and a falling debris rattle
    t = tvec(1.6)
    n = noise("strike", len(t))
    crack = fft_band(n, SR, 1500.0, 12000.0, 2) * np.exp(-t / 0.03)
    boom = fft_band(n, SR, None, 260.0, 3) * ad_env(t, 0.003, 0.5)
    sub = osc(sweep(120.0, 28.0, t, 0.7)) * ad_env(t, 0.004, 0.5)
    rattle = fft_band(noise("strike2", len(t)), SR, 800.0, 5000.0, 2) * (np.abs(noise("strike3", len(t))) > 1.6) * ad_env(t, 0.2, 0.4)
    y = 0.9 * crack / np.max(np.abs(crack)) + boom / np.max(np.abs(boom)) + 0.9 * sub + 0.4 * rattle
    save("strike", y, fout=0.12)


def p_fake():
    # the fake box goes off: a cheerful box ding that collapses into a "wah-wah" and a thump
    x = np.zeros(int(1.0 * SR))
    place(x, 0.0, ga.bell(mtof(84), 0.18, SR, 0.06) * 0.7)
    t = tvec(0.7)
    f = sweep(420.0, 150.0, t, 0.6) * (1.0 + 0.06 * np.sin(TAU * 7.0 * t))
    wah = (osc(f) + 0.5 * osc(f * 2.0) + 0.3 * osc(f * 3.0)) * np.minimum(t / 0.02, 1.0) * np.exp(-t / 0.35)
    place(x, 0.12, wah * 0.7)
    thump = osc(sweep(180.0, 45.0, tvec(0.3), 0.12)) * ad_env(tvec(0.3), 0.002, 0.1)
    place(x, 0.1, thump * 0.9)
    save("fake", x, fout=0.08)


def p_turbo():
    # a rocket-boost ignition: a gas whoosh with a pitch climb and a bright afterburn
    t = tvec(0.9)
    n = noise("turbo", len(t))
    roar = ga.svf_bandpass(n, sweep(300.0, 1800.0, t, 0.5), 1.2, SR) * ad_env(t, 0.03, 0.4)
    tone = (osc(sweep(120.0, 520.0, t, 0.45)) + 0.4 * osc(sweep(240.0, 1040.0, t, 0.45))) * ad_env(t, 0.02, 0.3)
    punch = osc(sweep(200.0, 60.0, t, 0.08)) * ad_env(t, 0.001, 0.05)
    save("turbo", 0.9 * roar / np.max(np.abs(roar)) + 0.45 * tone + 0.8 * punch, fout=0.1)


def p_ghost():
    # a spooky "ooOOoo": two detuned glides under a shimmering vibrato, plus a breath of air
    t = tvec(1.2)
    f = 330.0 * (1.0 + 0.5 * np.sin(np.pi * np.clip(t / 1.2, 0, 1))) * (1.0 + 0.03 * np.sin(TAU * 6.0 * t))
    y = (osc(f) + 0.6 * osc(f * 1.007) + 0.25 * osc(f * 2.0)) * np.sin(np.pi * np.clip(t / 1.2, 0, 1)) ** 1.3
    air = ga.svf_bandpass(noise("ghost", len(t)), 1800.0 + 900.0 * np.sin(TAU * 2.0 * t), 2.0, SR) * np.sin(np.pi * np.clip(t / 1.2, 0, 1))
    save("ghost", 0.7 * y + 0.35 * air / np.max(np.abs(air)), fout=0.1)


def p_steal():
    # the ghost's grab: a cold swipe up, then two quick sparkling notes (it got something)
    x = np.zeros(int(0.7 * SR))
    t = tvec(0.25)
    swipe = ga.svf_bandpass(noise("steal", len(t)), sweep(600.0, 4500.0, t, 0.2), 2.0, SR) * np.sin(np.pi * np.clip(t / 0.25, 0, 1))
    place(x, 0.0, 0.8 * swipe / np.max(np.abs(swipe)))
    place(x, 0.2, ga.bell(mtof(88), 0.4, SR, 0.12) * 0.7)
    place(x, 0.29, ga.bell(mtof(95), 0.4, SR, 0.16) * 0.8)
    save("steal", x, fout=0.06)


def p_decoy():
    # a puff of smoke and a rubbery "boing-pop" as the double appears (or is burst)
    t = tvec(0.5)
    puff = fft_band(noise("decoy", len(t)), SR, 300.0, 3000.0, 2) * ad_env(t, 0.004, 0.09)
    boing = osc(sweep(260.0, 900.0, t, 0.1) * (1.0 + 0.1 * np.sin(TAU * 20.0 * t) * np.exp(-t / 0.15))) * ad_env(t, 0.002, 0.12)
    save("decoy", 0.7 * puff / np.max(np.abs(puff)) + 0.6 * boing, fout=0.05)


def p_shock():
    # a ground-pounding shockwave: a deep thump, a ringing ring-out and a spray of grit
    t = tvec(0.9)
    thump = osc(sweep(150.0, 38.0, t, 0.25)) * ad_env(t, 0.002, 0.2)
    ring = ga.bell(mtof(55), 0.9, SR, 0.3) * 0.5
    grit = fft_band(noise("shock", len(t)), SR, 600.0, 6000.0, 2) * ad_env(t, 0.003, 0.15)
    save("shock", thump + ring + 0.5 * grit / np.max(np.abs(grit)), fout=0.1)


ALL = [p_pickup, p_roll, p_whoosh, p_hit, p_ko, p_boom, p_zap, p_charge, p_beam, p_slash, p_powerup,
       p_pop, p_spring, p_freeze, p_warp, p_chime, p_wind, p_clank, p_tick, p_land, p_warn, p_tally, p_fanfare,
       p_shell, p_siren, p_strike, p_fake, p_turbo, p_ghost, p_steal, p_decoy, p_shock]

if __name__ == "__main__":
    print("Party Mode effects -> audio/party_*.wav")
    for fn in ALL:
        fn()
