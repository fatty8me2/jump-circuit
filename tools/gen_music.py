#!/usr/bin/env python3
"""Jump Circuit - the score.

Composes and renders every piece of music in the game with tools/music_engine.py:
a score per map (each with a second "hi" layer the game brings in as you progress),
the title overture, the lobby groove, the results loop, the victory reprise, and the
musical stingers (per-map course fanfares, checkpoint chimes, the new-best sparkle).

All of it is built on one leitmotif - the JUMP theme: a triplet run-up (5-6-7) into a
leap from the tonic to the fifth, then a falling answer - which every map quotes in its
own key, rhythm and orchestration, and which the finale gathers up.

Usage:
    python tools/gen_music.py                 # everything
    python tools/gen_music.py gardens title   # only some pieces
    python tools/gen_music.py --list
    python tools/gen_music.py --verify        # check the files on disk
Deterministic: every piece seeds its own RNG from its name.
"""
import os
import sys
import time

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import music_engine as me  # noqa: E402
from music_engine import mel, voice, mtof, chord, bass_note, chord_tones  # noqa: E402,F401

OUT = me.ga.OUT


# --------------------------------------------------------------------------
# the JUMP theme, written in C (transpose per piece with the '>N' token or the helper)
# --------------------------------------------------------------------------
# 8-bar A phrase: run-up + leap, a falling answer, and the bVI - bVII - I lift.
JUMP_PICKUP = "G4t A4t B4t"
JUMP_A = ("C5h G5h | A5q. G5e E5q C5q | D5q. E5e F5q A5q | G5h. G4t A4t B4t | "
          "C5h G5h | C6q. Bb5e Ab5q C6q | D6q. C6e Bb5q D6q | E6w")
JUMP_A_CHORDS = "| C | Fmaj7 | Dm7 | G | C | Ab | Bb | C |"
# 8-bar B phrase: a rising sequence in the relative minor.
JUMP_B = ("A5q. B5e C6q E6q | D6h C6h | A5q. B5e C6q F6q | E6h D6h | "
          "B5q. C6e D6q G6q | E6h. C6q | A5q C6q F6q E6q | D6h. G5t A5t B5t")
JUMP_B_CHORDS = "| Am | F | Dm | G | Em | Am | F | G7sus4 G7 |"


def tx(text, semis):
    """Transpose a melody string by prefixing a >N token (mel() applies it to what follows)."""
    return (">%d " % semis) + text


def tx_chords(text, semis):
    names = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]
    names_sharp = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    import re

    def sub(m):
        root = m.group(1)
        pc = (me._PC[root[0]] + (1 if root[1:] == "#" else -1 if root[1:] == "b" else 0) + semis) % 12
        flat_keys = semis % 12 in (1, 3, 5, 8, 10)
        return (names if flat_keys or "b" in root else names_sharp)[pc]
    return re.sub(r"(?<![A-Za-z])([A-G][#b]?)", sub, text)


# --------------------------------------------------------------------------
# arranger helpers
# --------------------------------------------------------------------------
def prog(text, bpb=4, start_bar=0):
    """'| G | C/G | Am7 D | G |' -> [(beat, beats, symbol)]. Chords in a bar split it evenly;
    'Sym:2' gives an explicit length in beats."""
    out = []
    bar = start_bar
    for cell in [c for c in text.split("|") if c.strip()]:
        syms = cell.split()
        explicit = [s for s in syms if ":" in s]
        beat = bar * bpb
        if explicit:
            for s in syms:
                sym, d = (s.split(":") + ["0"])[:2]
                d = float(d) if ":" in s else (bpb - sum(float(e.split(":")[1]) for e in explicit)) / (len(syms) - len(explicit))
                out.append((beat, d, sym))
                beat += d
        else:
            d = bpb / len(syms)
            for s in syms:
                out.append((beat, d, s))
                beat += d
        bar += 1
    return out


def pad(T, layer, bus, P, inst, center=62, count=4, gain=1.0, sends=None, vel=0.7, overlap=0.0, spread=False,
        top=None, **kw):
    prev = None
    for b, d, sym in P:
        notes = voice(sym, center, count, prev, spread)
        prev = notes
        if top is not None:
            notes = [m for m in notes if m <= top]
        for m in notes:
            T.add(layer, bus, b, inst(T.rng, float(mtof(m)), d * T.spb + overlap, vel, **kw), gain, None, sends, 0.0)


def bass(T, layer, bus, P, pattern, inst, lo=33, hi=47, gain=1.0, sends=None, vel=0.8, period=None, **kw):
    """pattern: [(beat offset, interval in semitones from the bass note, dur beats[, vel])], repeated
    every `period` beats (default a bar) to fill each chord. 'app' as interval = chromatic approach
    into the next chord's bass; 'nxt5' = the fifth below the next bass."""
    period = period or T.bpb
    for i, (b, d, sym) in enumerate(P):
        root = bass_note(sym, lo, hi)
        nxt = bass_note(P[(i + 1) % len(P)][2], lo, hi)
        k = 0.0
        while k < d - 1e-6:
            for item in pattern:
                off, iv, du = item[0], item[1], item[2]
                v = item[3] if len(item) > 3 else vel
                if k + off >= d - 1e-6:
                    continue
                if iv == "app":
                    m = nxt - 1 if nxt > root else nxt + 1
                elif iv == "nxt5":
                    m = nxt - 5 if nxt - 5 >= lo else nxt + 7
                else:
                    m = root + iv
                du2 = min(du, d - k - off)
                T.add(layer, bus, b + k + off, inst(T.rng, float(mtof(m)), du2 * T.spb, v, **kw), gain, None, sends,
                      0.003)
            k += period


def arp(T, layer, bus, P, order, step, inst, lo=60, hi=84, gain=1.0, sends=None, vels=(0.85, 0.6, 0.7, 0.6),
        dur=None, pan_fn=None, skip=None, **kw):
    """Chord-tone arpeggio: `order` indexes into the chord tones within [lo, hi] (negative = from the top)."""
    k = 0
    for b, d, sym in P:
        tones = chord_tones(sym, lo, hi)
        if not tones:
            continue
        t = 0.0
        while t < d - 1e-6:
            if skip is None or not skip(k):
                idx = order[k % len(order)]
                m = tones[idx % len(tones)] if idx >= 0 else tones[idx % len(tones)]
                v = vels[k % len(vels)]
                pan = pan_fn(k) if pan_fn else None
                sig = inst(T.rng, float(mtof(m)), (dur or step) * T.spb, v, **kw)
                T.add(layer, bus, b + t, sig, gain, pan, sends, 0.003)
            k += 1
            t += step


def strum(T, layer, bus, P, pattern, inst, center=57, count=5, gain=1.0, sends=None, step=0.5, spread=0.012,
          vel=0.75, bass_lo=40, bass_hi=52, **kw):
    """Guitar-style strums. pattern chars per step: D down, U up (lighter, top strings), B bass note,
    A alternate bass (fifth), x muted chuck, . rest. The pattern repeats through each chord."""
    prev = None
    for b, d, sym in P:
        notes = voice(sym, center, count, prev, True)
        prev = notes
        root = bass_note(sym, bass_lo, bass_hi)
        n_steps = int(round(d / step))
        for s in range(n_steps):
            c = pattern[s % len(pattern)]
            beat = b + s * step
            if c == ".":
                continue
            if c in "BA":
                m = root if c == "B" else (root + 7 if root + 7 <= bass_hi + 5 else root - 5)
                T.add(layer, bus, beat, inst(T.rng, float(mtof(m)), step * 1.8 * T.spb, vel, **kw), gain, None, sends, 0.003)
                continue
            if c == "x":
                for j, m in enumerate(notes[:4]):
                    T.add(layer, bus, beat + j * 0.004 / T.spb, inst(T.rng, float(mtof(m)), 0.04, vel * 0.5, **kw) * 0.6,
                          gain, None, sends, 0.0)
                continue
            seq = notes if c == "D" else list(reversed(notes[-3:]))
            v = vel * (1.0 if c == "D" else 0.7)
            for j, m in enumerate(seq):
                T.add(layer, bus, beat + j * spread / T.spb, inst(T.rng, float(mtof(m)), step * 1.9 * T.spb, v, **kw),
                      gain, None, sends, 0.0)


def kit(T, layer, bus, bars, patterns, step=0.25, gain=1.0, sends=None, pans=None, pump=()):
    """patterns: {name: (samples list, 'x..x..', gain)}; chars x=1 X=1.2 o=0.65 g=0.35 .=rest.
    `bars` is an iterable of bar indices."""
    vmap = {"x": 1.0, "X": 1.2, "o": 0.65, "g": 0.35, "-": 0.5}
    for bar in bars:
        for name, (samples, pat, g) in patterns.items():
            for i, c in enumerate(pat.replace(" ", "")):
                if c not in vmap:
                    continue
                beat = bar * T.bpb + i * step
                s = samples[int(T.rng.integers(0, len(samples)))]
                pan = (pans or {}).get(name, 0.0)
                T.hit(layer, bus, beat, s, gain * g * vmap[c] * T.rng.uniform(0.9, 1.0), pan, sends,
                      pump=(name in pump))


def variants(fn, k=4, **kw):
    return [fn(**kw) for _ in range(k)]


def swell_into(T, layer, bus, bar, beats=4, gain=0.35, sends=None):
    x = me.cymbal_swell(T.rng, beats, T.spb, 0.8)
    T.add(layer, bus, bar * T.bpb - beats, x, gain, 0.2, sends, 0.0)


# cached takes for parts that repeat the same notes a lot
M_GUITAR = me.memo(me.guitar, 4)
M_GUITAR_STEEL = me.memo(lambda r, f, d, v: me.guitar(r, f, d, v, steel=True), 4, "guitar_steel")
M_PIZZ = me.memo(lambda r, f, d, v: me.pizz(r, f, d, v, section=2), 3, "pizz2")
M_HARP = me.memo(me.harp, 3)
M_UPRIGHT = me.memo(me.upright, 3)


def std_eq(low=35.0, high=16000.0):
    return lambda f: me.hp(f, low, 2) * me.lp(f, high, 2)


# --------------------------------------------------------------------------
# LAUNCH GARDENS - G major, 132 bpm: a sunny pastoral march. Flute tune over strummed guitar,
# pizzicato and glockenspiel; an ocarina bridge; the JUMP theme on clarinet (horns in the
# hi layer) over the bVI-bVII-I lift. Hi layer: light snare + tambourine, strings counter-line,
# horns, timpani, piccolo.
# --------------------------------------------------------------------------
GARDENS_A = ("D5e G5e B5e D6e~ D6q B5q | C6q. B5e A5q G5q | B5q. A5e G5q D5q | E5e F#5e G5e A5e~ A5h | "
             "B5e A5e G5e B5e~ B5q E6q | E6q. D6e C6q B5q | A5q C6q B5q A5q | G5h. r q |")
GARDENS_A2 = ("D5e G5e B5e D6e~ D6q G6q | F#6q. E6e D6q B5q | C6q. E6e D6q C6q | B5q. D6e G5q B5q | "
              "A5e B5e C6e E6e~ E6q D6q | C6q. B5e A5q F#5q | G5q E6q D6q F#5q | G5h. r q |")
GARDENS_A_CH = "| G | C/G | G | D | Em | C | Am7 D | G |"
GARDENS_A2_CH = "| G | Bm | C | G/B | Am | D | C D | G |"
GARDENS_BRIDGE = "G5h. E5q | F#5h A5h | B5q. A5e F#5q D5q | E5w | G5h. E5q | A5h D6h | Bb5q. G5e Eb5q G5q | F#5h. r q |"
GARDENS_BRIDGE_CH = "| C | D | Bm | Em | C | D | Eb | D7 |"
GARDENS_JUMP_CH = "| G | Cmaj7 | Am7 | D | G | Eb | F | G |"
GARDENS_INTRO_CH = "| G | C/G | G | D | G | C/G | Am7 | D |"


def piece_gardens():
    T = me.Track("gardens", 132, 56, 4, layers=("base", "hi"))
    r = T.rng
    T.reverb("hall", me.make_ir(r, rt60=1.6, predelay=0.018, damp=5000, er=0.6))
    T.reverb("air", me.make_ir(r, rt60=2.6, predelay=0.03, damp=3500, er=0.3))
    T.delay("echo", beats=0.75, fb=0.3, damp=3500, ret=0.5)
    T.bus("guitar", eq=lambda f: me.hp(f, 90) * me.bump(f, 3000, 2, 0.8))
    T.bus("pizz", eq=std_eq(40))
    T.bus("lead", eq=std_eq(200))
    T.bus("strings", eq=std_eq(60, 12000))
    T.bus("perc", eq=std_eq(100))
    T.bus("drums", eq=std_eq(35), drive=1.2)
    T.bus("brass", eq=std_eq(80, 9000))
    T.bus("bass", eq=lambda f: me.hp(f, 35) * me.lp(f, 3000))
    hall = {"hall": 0.25}

    # form: intro(8) A(8) A2(8) bridge(8) jump(8) A(8) A2(8)  = 56 bars
    secs_ = [("intro", 0, GARDENS_INTRO_CH), ("A", 8, GARDENS_A_CH), ("A2", 16, GARDENS_A2_CH),
             ("bridge", 24, GARDENS_BRIDGE_CH), ("jump", 32, GARDENS_JUMP_CH), ("A", 40, GARDENS_A_CH),
             ("A2", 48, GARDENS_A2_CH)]
    for name, bar0, ch in secs_:
        P = prog(ch, 4, bar0)
        # --- base: strummed nylon guitar, pizzicato bass line, soft string bed, glockenspiel sparkle
        if name == "bridge":
            strum(T, "base", "guitar", P, "D..UD.U.", M_GUITAR, center=58, gain=0.3, sends=hall, vel=0.6)
            arp(T, "base", "perc", P, [0, 2, 1, 3, 2, 4, 3, 1], 0.5, M_HARP,
                lo=55, hi=79, gain=0.28, sends={"hall": 0.35}, vels=(0.7, 0.45, 0.55, 0.45))
        else:
            strum(T, "base", "guitar", P, "BxDUAxDU", M_GUITAR, center=58, gain=0.34, sends=hall, vel=0.75)
        bass(T, "base", "pizz", P, [(0, 0, 1, 0.9), (2, 7, 1, 0.75)] if name != "bridge" else [(0, 0, 2, 0.8), (2, 7, 2, 0.6)],
             M_PIZZ, lo=38, hi=50, gain=0.55, sends=hall)
        pad(T, "base", "strings", P, lambda rr, f, d, v: me.strings(rr, f, d, v, att=0.5, rel=0.6, bright=0.35),
            center=62, count=3, gain=0.1, sends={"air": 0.4}, vel=0.5)
        # shaker on the offbeats, woodblock pickups
        kit(T, "base", "perc", range(bar0, bar0 + 8), {
            "shk": (SHK, "g.o.g.o.g.o.g.o." if name != "intro" or bar0 > 3 else "................", 0.22),
            "wb": (WB, "............x.x." if name in ("A", "A2") else "................", 0.12),
        }, sends={"hall": 0.15})

    # glockenspiel sparkles in the intro (a little rising call, the jump in miniature)
    glock_call = mel("r h. D6t E6t F#6t | G6q D6q r h | r w | r h. A6t B6t C7t | D7q A6q r h | r w | r w | r w |",
                     start=0)
    T.notes("base", "perc", glock_call, lambda rr, f, d, v: me.mallet(rr, f, d, v, "glockenspiel"), gain=0.2,
            sends={"hall": 0.3, "echo": 0.35})
    # the tune: flute (base), doubled an octave up by piccolo and a violin counter-line (hi)
    for bar0, txt in ((8, GARDENS_A), (16, GARDENS_A2), (40, GARDENS_A), (48, GARDENS_A2)):
        ev = mel(txt, start=bar0 * 4)
        T.notes("base", "lead", ev, lambda rr, f, d, v, **k: me.woodwind(rr, f, d, v, "flute", **k), gain=0.42,
                sends={"hall": 0.3, "echo": 0.12}, legato=True, pan=-0.1)
        if bar0 >= 40:
            T.notes("hi", "lead", mel(txt, start=bar0 * 4, transpose=12), lambda rr, f, d, v, **k: me.woodwind(rr, f, d, v, "piccolo", **k),
                    gain=0.2, sends={"hall": 0.3}, legato=True, pan=0.2)
    # violins' counter-line in the hi layer (long notes, thirds under the tune's landing points)
    counter = ("B4w | C5w | D5w | C5h A4h | B4w | G4h A4h | C5h D5h | B4w |")
    counter2 = ("B4w | D5w | E5w | D5w | C5w | A4h D5h | E5h D5h | B4w |")
    for bar0, txt in ((8, counter), (16, counter2), (40, counter), (48, counter2)):
        T.notes("hi", "strings", mel(txt, start=bar0 * 4), lambda rr, f, d, v, **k: me.strings(rr, f, d, v, att=0.25, rel=0.5, **k),
                gain=0.34, sends={"hall": 0.35}, legato=True, pan=-0.3)
    # bridge: ocarina, answered by glockenspiel echoes
    T.notes("base", "lead", mel(GARDENS_BRIDGE, start=24 * 4), lambda rr, f, d, v, **k: me.woodwind(rr, f, d, v, "ocarina", **k),
            gain=0.46, sends={"hall": 0.4, "echo": 0.25}, legato=True)
    T.notes("hi", "strings", mel("E4w | F#4w | D4w | B3w | E4w | F#4w | G4w | A4w |", start=24 * 4),
            lambda rr, f, d, v, **k: me.strings(rr, f, d, v, att=0.4, rel=0.6, **k), gain=0.26, sends={"hall": 0.4}, legato=True)
    # the JUMP theme in G on clarinet, horns join in the hi layer (pickup on the bridge's last beat)
    jump = mel(tx(JUMP_PICKUP + " | " + JUMP_A, -5), start=31 * 4 + 3)
    T.notes("base", "lead", jump, lambda rr, f, d, v, **k: me.woodwind(rr, f, d, v, "clarinet", **k), gain=0.42,
            sends={"hall": 0.35}, legato=True, pan=0.1)
    T.notes("hi", "brass", jump, lambda rr, f, d, v, **k: me.brass(rr, f, d, v, "horn", voices=2, **k), gain=0.3,
            sends={"hall": 0.45}, legato=True, pan=-0.2)
    pad(T, "hi", "brass", prog(GARDENS_JUMP_CH, 4, 32), lambda rr, f, d, v: me.brass(rr, f, d, v, "horn"),
        center=55, count=3, gain=0.18, sends={"hall": 0.4}, vel=0.55)
    # hi layer: full strings under the tune sections (violins high, violas / cellos below)
    for bar0, ch in ((8, GARDENS_A_CH), (16, GARDENS_A2_CH), (40, GARDENS_A_CH), (48, GARDENS_A2_CH)):
        pad(T, "hi", "strings", prog(ch, 4, bar0), lambda rr, f, d, v: me.strings(rr, f, d, v, att=0.2, rel=0.4, bright=0.5),
            center=67, count=3, gain=0.12, sends={"hall": 0.35}, vel=0.6)
        bass(T, "hi", "bass", prog(ch, 4, bar0), [(0, 0, 1.5, 0.8), (2, 7, 1.5, 0.7)],
             lambda rr, f, d, v: me.strings(rr, f, d, v, att=0.03, rel=0.2, bright=0.4, voices=3), lo=36, hi=48, gain=0.2)
    # hi layer: a light march kit + tambourine, timpani on the section downbeats
    for bar0 in (8, 16, 32, 40, 48):
        kit(T, "hi", "drums", range(bar0, bar0 + 8), {
            "kick": (KICK_SOFT, "x.......x.....g.", 0.8),
            "snare": (SNR_BRUSH, "....x..g....x.gg", 0.45),
            "tamb": (TAMB, "....x.......x...", 0.26),
            "hat": (HATC, "x.o.x.o.x.o.x.o.", 0.14),
        }, sends={"hall": 0.12})
    for bar0 in (8, 24, 32, 40):
        T.hit("hi", "drums", bar0 * 4, me.timpani(r, float(mtof(43)), 0.8), 0.35, 0.0, {"hall": 0.3})
        swell_into(T, "hi", "perc", bar0, 4, 0.2, {"hall": 0.3})
    T.hit("hi", "drums", 36 * 4, me.timpani(r, float(mtof(43)), 0.7), 0.3, 0.0, {"hall": 0.3})
    for b, m in ((37 * 4, 39), (38 * 4, 41), (39 * 4, 43)):
        T.hit("hi", "drums", b, me.timpani(r, float(mtof(m)), 0.85), 0.35, 0.0, {"hall": 0.3})
    T.render(rms_db=-14.5, mode="add", hi_gain=1.0)


# shared percussion variants (rendered once per run)
SHK = WB = TAMB = KICK_SOFT = SNR_BRUSH = HATC = None
_BANKS = {}


def _perc_bank():
    global SHK, WB, TAMB, KICK_SOFT, SNR_BRUSH, HATC
    r = me.rng_for("perc_bank")
    SHK = [me.shaker(r, 1.0) for _ in range(4)]
    WB = [me.woodblock(r, 1.0, p) for p in (1.0, 1.0, 1.06)]
    TAMB = [me.tambourine(r, 1.0) for _ in range(3)]
    KICK_SOFT = [me.kick(r, "soft") for _ in range(2)]
    SNR_BRUSH = [me.snare(r, "piccolo") for _ in range(3)]
    HATC = [me.hat(r, "closed") for _ in range(4)]


def bank(name, fn, k=3):
    """A few seeded takes of a percussion sound, shared by every piece."""
    if name not in _BANKS:
        r = me.rng_for("bank_" + name)
        _BANKS[name] = [fn(r) for _ in range(k)]
    return _BANKS[name]


def I(fn, **fixed):
    """Instrument with fixed keyword args. Arguments the instrument doesn't take (legato_from from
    the note loop, for a choir or a mallet) are dropped."""
    import inspect
    params = set(inspect.signature(fn).parameters)

    def inst(r, f, d, v, **k):
        kw = {a: b for a, b in {**fixed, **k}.items() if a in params}
        return fn(r, f, d, v, **kw)
    return inst


FLUTE = I(me.woodwind, kind="flute")
PICCOLO = I(me.woodwind, kind="piccolo")
WHISTLE = I(me.woodwind, kind="whistle")
OCARINA = I(me.woodwind, kind="ocarina")
CLARINET = I(me.woodwind, kind="clarinet")
OBOE = I(me.woodwind, kind="oboe")
BASSOON = I(me.woodwind, kind="bassoon")
HORN = I(me.brass, kind="horn")
HORNS = I(me.brass, kind="horn", voices=3)
TRUMPET = I(me.brass, kind="trumpet")
TRUMPETS = I(me.brass, kind="trumpet", voices=2)
TROMBONES = I(me.brass, kind="trombone", voices=2)
TUBA = I(me.brass, kind="tuba")
VIOLINS = I(me.strings, att=0.12, rel=0.35, bright=0.55)
STRINGS_SOFT = I(me.strings, att=0.5, rel=0.8, bright=0.35)
CELLOS = I(me.strings, att=0.1, rel=0.3, bright=0.45, body="cello")
FIDDLE = I(me.solo_string)
CHOIR_A = I(me.choir, vowel="a")
CHOIR_O = I(me.choir, vowel="o")
CHOIR_U = I(me.choir, vowel="u")
ACCORDION = I(me.accordion)
EPIANO = I(me.epiano)
PIANO = I(me.piano)
SYNTH_LEAD = I(me.synth_lead, wave="saw", cutoff=3800.0)
SQUARE_LEAD = I(me.synth_lead, wave="square", cutoff=3000.0)
M_MUSICBOX = me.memo(I(me.mallet, kind="musicbox"), 3, "musicbox")
M_CELESTA = me.memo(I(me.mallet, kind="celesta"), 3, "celesta")
M_GLOCK = me.memo(I(me.mallet, kind="glockenspiel"), 3, "glock")
M_MARIMBA = me.memo(I(me.mallet, kind="marimba"), 3, "marimba")
M_VIBES = me.memo(I(me.mallet, kind="vibraphone"), 3, "vibes")
M_KALIMBA = me.memo(I(me.mallet, kind="kalimba"), 3, "kalimba")
M_HARPSI = me.memo(me.harpsichord, 3)
M_EPIANO = me.memo(me.epiano, 3)
M_SPLUCK = me.memo(I(me.synth_pluck, cutoff=4200.0, decay=0.14), 3, "spluck")
M_SPLUCK_SQ = me.memo(I(me.synth_pluck, wave="pulse", cutoff=3000.0, decay=0.12), 3, "spluck_sq")
M_SBASS = me.memo(me.synth_bass, 3)
M_SUB = me.memo(me.sub_bass, 2)
M_PIZZ3 = me.memo(lambda r, f, d, v: me.pizz(r, f, d, v, section=3), 3, "pizz3")
M_CELLO_STAC = me.memo(I(me.strings, att=0.012, rel=0.08, bright=0.5, voices=3), 3, "cello_stac")
M_VLN_STAC = me.memo(I(me.strings, att=0.01, rel=0.07, bright=0.6, voices=3), 3, "vln_stac")
M_BRASS_STAB = me.memo(I(me.brass, kind="trombone", voices=2, fp=True), 3, "brass_stab")
M_TRPT_STAB = me.memo(I(me.brass, kind="trumpet", voices=2, fp=True), 3, "trpt_stab")


def line(T, layer, bus, text, bar0, inst, gain=1.0, sends=None, pan=None, legato=True, transpose=0, pickup=0.0,
         jitter=0.004, **kw):
    """Play a melody string starting at bar0 (minus `pickup` beats for an anacrusis)."""
    ev = mel(text, T.bpb, transpose, bar0 * T.bpb - pickup)
    T.notes(layer, bus, ev, inst, gain, sends, pan, jitter, legato=legato, **kw)


def stabs(T, layer, bus, P, offsets, inst, center=60, count=3, gain=1.0, sends=None, vel=0.8, dur=0.25):
    """Chord hits at beat offsets inside every bar of each chord."""
    prev = None
    for b, d, sym in P:
        notes = voice(sym, center, count, prev)
        prev = notes
        for o in offsets:
            k = 0.0
            while k + o < d - 1e-6:
                for m in notes:
                    T.add(layer, bus, b + k + o, inst(T.rng, float(mtof(m)), dur * T.spb, vel), gain, None, sends, 0.002)
                k += T.bpb


def waltz(T, layer, bus, P, bass_inst, chord_inst, center=62, count=3, gains=(1.0, 1.0), sends=None,
          vels=(0.8, 0.5, 0.45), bass_lo=40, bass_hi=52, chord_dur=0.6):
    """Oom-pah-pah: the bass on 1 (root, then the fifth on alternate bars), chords on 2 and 3."""
    prev = None
    bar_i = 0
    for b, d, sym in P:
        notes = voice(sym, center, count, prev)
        prev = notes
        root = bass_note(sym, bass_lo, bass_hi)
        for bb in range(int(round(d))):
            beat = b + bb
            if bb % 3 == 0:
                m = root if bar_i % 2 == 0 else (root + 7 if root + 7 <= bass_hi + 4 else root - 5)
                T.add(layer, bus, beat, bass_inst(T.rng, float(mtof(m)), 0.9 * T.spb, vels[0]), gains[0], None, sends, 0.003)
                bar_i += 1
            else:
                for m in notes:
                    T.add(layer, bus, beat, chord_inst(T.rng, float(mtof(m)), chord_dur * T.spb, vels[bb % 3]), gains[1],
                          None, sends, 0.003)


def ring(T, layer, bus, beat, sig, gain=1.0, pan=0.0, sends=None):
    T.add(layer, bus, beat, sig, gain, pan, sends, 0.0)


# --------------------------------------------------------------------------
# TITLE - "Jump Circuit" overture. Bb major, 84 bpm, 36 bars. Dawn intro (celesta hints the
# run-up), the JUMP theme on horns, the B phrase on violins, a tutti reprise with trumpets,
# and a hushed coda that leads back round.
# --------------------------------------------------------------------------
def piece_title():
    T = me.Track("title", 84, 36, 4)
    r = T.rng
    T.reverb("hall", me.make_ir(r, rt60=2.4, predelay=0.025, damp=4500, er=0.5))
    T.delay("echo", beats=0.75, fb=0.35, damp=3000, ret=0.45)
    for b_, e in (("strings", std_eq(40, 13000)), ("brass", std_eq(60, 9000)), ("ww", std_eq(150)),
                  ("harp", std_eq(60)), ("perc", std_eq(30)), ("bass", std_eq(30, 4000))):
        T.bus(b_, eq=e)
    H = {"hall": 0.35}
    intro = prog("| Bb | Gm | Ebmaj7 | F7sus4 F |", 4, 0)
    a1 = prog(tx_chords(JUMP_A_CHORDS, -2), 4, 4)
    bb = prog(tx_chords(JUMP_B_CHORDS, -2), 4, 12)
    a2 = prog(tx_chords(JUMP_A_CHORDS, -2), 4, 20)
    coda = prog("| Eb | Bb/D | Cm7 | F | Gm | Eb | Cm7 F | Bb |", 4, 28)
    allp = intro + a1 + bb + a2 + coda
    # strings bed throughout, harp arpeggios, basses
    pad(T, "base", "strings", intro + coda, STRINGS_SOFT, center=62, count=4, gain=0.16, sends=H, vel=0.45)
    pad(T, "base", "strings", a1 + bb, I(me.strings, att=0.3, rel=0.6, bright=0.45), center=62, count=4, gain=0.17,
        sends=H, vel=0.6)
    pad(T, "base", "strings", a2, I(me.strings, att=0.15, rel=0.5, bright=0.6, tremolo=0.35), center=65, count=4,
        gain=0.2, sends=H, vel=0.85)
    arp(T, "base", "harp", intro + a1 + bb + coda, [0, 1, 2, 3, 4, 3, 2, 1], 0.5, M_HARP, lo=46, hi=77, gain=0.3,
        sends={"hall": 0.4}, vels=(0.75, 0.5, 0.55, 0.5))
    arp(T, "base", "harp", a2, [0, 2, 4, 5, 6, 5, 4, 2], 0.5, M_HARP, lo=50, hi=84, gain=0.28, sends={"hall": 0.4})
    bass(T, "base", "bass", a1 + bb + a2, [(0, 0, 2, 0.8), (2, 0, 2, 0.6)], I(me.strings, att=0.05, rel=0.3, voices=3,
         bright=0.35), lo=34, hi=46, gain=0.3, sends={"hall": 0.2})
    bass(T, "base", "bass", intro + coda, [(0, 0, 4, 0.6)], I(me.strings, att=0.6, rel=0.8, voices=3, bright=0.3), lo=34,
         hi=46, gain=0.25, sends={"hall": 0.2})
    # dawn: celesta hints the run-up, a flute answers
    line(T, "base", "ww", "r h. F5t G5t A5t | Bb5h F6h | r w | r w |", 0, M_CELESTA, 0.3, {"hall": 0.5, "echo": 0.4},
         legato=False)
    line(T, "base", "ww", "r w | r w | G5q. F5e Eb5q Bb4q | C5h. r q |", 0, FLUTE, 0.32, {"hall": 0.4})
    # the JUMP theme on horns (an octave down: warm), pickup on the intro's last beat
    line(T, "base", "brass", JUMP_PICKUP + " | " + JUMP_A, 4, HORNS, 0.42, {"hall": 0.45}, transpose=-14, pickup=1.0)
    # B phrase: violins sing it, cellos answer below, flute doubles the last half
    line(T, "base", "strings", JUMP_B, 12, I(me.strings, att=0.1, rel=0.4, bright=0.6, voices=5), 0.34, H, transpose=-2,
         pan=-0.25)
    line(T, "base", "strings", "D4w | Bb3w | F3w | C4h A3h | F3w | D4w | C4h Bb3h | A3h. r q |", 12, CELLOS, 0.26, H,
         pan=0.35)
    line(T, "base", "ww", "r w | r w | r w | r w | " + " ".join(JUMP_B.split("|")[4].split()) + " | E6h. C6q | A5q C6q F6q E6q | D6h. r q |",
         12, FLUTE, 0.2, {"hall": 0.4}, transpose=-2)
    pad(T, "base", "brass", bb, HORN, center=58, count=3, gain=0.12, sends=H, vel=0.45)
    # tutti reprise: trumpets on the tune, horns an octave below, timpani and a snare pulse
    line(T, "base", "brass", JUMP_PICKUP + " | " + JUMP_A, 20, TRUMPETS, 0.36, {"hall": 0.4}, transpose=-2, pickup=1.0)
    line(T, "base", "brass", JUMP_PICKUP + " | " + JUMP_A, 20, HORNS, 0.34, {"hall": 0.45}, transpose=-14, pickup=1.0)
    pad(T, "base", "brass", a2, TROMBONES, center=55, count=3, gain=0.12, sends=H, vel=0.6)
    snr = bank("snare_march", lambda r: me.snare(r, "march"), 4)
    kit(T, "base", "perc", range(20, 28), {"snare": (snr, "x..g..x.x.g.x...", 0.16)}, sends={"hall": 0.25})
    for bar, m in ((4, 34), (8, 34), (12, 31), (20, 34), (24, 34), (25, 30), (26, 32), (27, 34)):
        ring(T, "base", "perc", bar * 4, me.timpani(r, float(mtof(m + 12)), 0.85), 0.34, 0.0, {"hall": 0.3})
    crash = bank("crash", lambda r: me.cymbal(r, "crash"), 2)
    for bar in (20, 27):
        ring(T, "base", "perc", bar * 4, crash[bar % 2], 0.16, 0.3, {"hall": 0.3})
    for bar in (4, 12, 20, 28):
        swell_into(T, "base", "perc", bar, 4, 0.16, {"hall": 0.4})
    ring(T, "base", "perc", 20 * 4 - 2, me.timpani_roll(r, float(mtof(41)), 2.0, T.spb, 0.2, 0.9), 0.3, 0.0, {"hall": 0.3})
    # coda: music box / celesta echo the leap, the strings settle
    line(T, "base", "ww", "r w | F5h Bb5h | r w | r h. F5t G5t A5t | Bb5h F6h | r w | r w | r w |", 28, M_MUSICBOX, 0.24,
         {"hall": 0.5, "echo": 0.5}, legato=False)
    line(T, "base", "ww", "r w | r w | Eb5h. D5q | C5w | D5h. Bb4q | G4w | r w | r w |", 28, CLARINET, 0.3, H)
    T.render(rms_db=-15.5)


# --------------------------------------------------------------------------
# LOBBY - "Warm-Up". F major funk, 108 bpm, 32 bars: tight kit, e-piano comping, muted
# guitar chicks, octave bass, brass stabs; the JUMP theme syncopated on vibes / muted lead.
# --------------------------------------------------------------------------
LOBBY_A_CH = "| Fmaj7 | Em7 A7 | Dm7 | G7 | Bbmaj7 | A7 | Dm7 G7 | C7sus4 C7 |"
LOBBY_JUMP = ("C5t D5t E5t | F5q. C6e~ C6h | D6q. C6e A5q F5q | G5q. A5e Bb5q D6q | C6h. C5t D5t E5t | "
              "F5q. C6e~ C6h | F6q. Eb6e Db6q F6q | G6q. F6e Eb6q G6q | A6h. r q |")
LOBBY_JUMP_CH = "| F | Bbmaj7 | Gm7 | C7 | F | Db | Eb | F |"


def piece_lobby():
    T = me.Track("lobby", 108, 32, 4, swing=0.12)
    r = T.rng
    T.reverb("room", me.make_ir(r, rt60=0.9, predelay=0.01, damp=6000, er=0.8))
    T.reverb("plate", me.make_ir(r, rt60=1.8, predelay=0.02, damp=5000, er=0.2))
    T.delay("echo", beats=0.75, fb=0.3, damp=3500, ret=0.4)
    T.bus("drums", eq=std_eq(30), drive=1.3)
    T.bus("bass", eq=lambda f: me.hp(f, 35) * me.lp(f, 2500))
    T.bus("keys", eq=std_eq(120))
    T.bus("gtr", eq=std_eq(200))
    T.bus("brass", eq=std_eq(120, 10000))
    T.bus("lead", eq=std_eq(150))
    RM = {"room": 0.2}
    kick = bank("kick_punch", lambda r: me.kick(r, "punch"), 2)
    snr = bank("snare_ac", lambda r: me.snare(r, "acoustic"), 4)
    hats = bank("hat_c", lambda r: me.hat(r, "closed"), 4)
    hato = bank("hat_o", lambda r: me.hat(r, "open"), 2)
    clp = bank("clap", lambda r: me.clap(r), 3)
    sections = [(0, LOBBY_A_CH, "A"), (8, LOBBY_JUMP_CH, "J"), (16, LOBBY_A_CH, "A2"), (24, "| Dm7 | G7 | Bbmaj7 | C7sus4 C7 | Dm7 | G7 | Bbmaj7 | C7sus4 C7 |", "brk")]
    for bar0, ch, name in sections:
        P = prog(ch, 4, bar0)
        drums = {
            "kick": (kick, "x.....x...x..x.." if name != "brk" else "x.......x.......", 0.7),
            "snare": (snr, "....x..g.g..x..g" if name != "brk" else "................", 0.5),
            "hat": (hats, "xoxoxoxoxoxoxoxo" if name != "brk" else "x.o.x.o.x.o.x.o.", 0.16),
            "hato": (hato, "..............x." if name != "brk" else "................", 0.12),
            "clap": (clp, "................" if name != "brk" else "....x.......x...", 0.4),
        }
        kit(T, "base", "drums", range(bar0, bar0 + 8), drums, sends={"room": 0.15})
        bass(T, "base", "bass", P, [(0, 0, 0.75, 0.9), (0.75, 12, 0.25, 0.6), (1.5, 0, 0.5, 0.7), (2.5, 12, 0.25, 0.55),
                                    (3, 7, 0.5, 0.7), (3.5, "app", 0.5, 0.6)], M_SBASS, lo=36, hi=48, gain=0.5,
             cutoff=700.0, decay=0.09)
        # e-piano comping: anticipated chords on the "and" of 2 and 4
        stabs(T, "base", "keys", P, (0.0, 1.5, 3.5), M_EPIANO, center=62, count=4, gain=0.22, sends={"plate": 0.25},
              vel=0.6, dur=0.4)
        # guitar chicks on the offbeats
        stabs(T, "base", "gtr", P, (0.5, 1.5, 2.5, 3.5), me.memo(I(me.guitar, steel=True, palm=True), 3, "gtr_mute"),
              center=67, count=3, gain=0.12, sends=RM, vel=0.5, dur=0.12)
        if name != "brk":
            stabs(T, "base", "brass", prog(ch, 4, bar0)[::2], (2.5,), M_TRPT_STAB, center=67, count=3, gain=0.1,
                  sends={"plate": 0.25}, vel=0.7, dur=0.25)
    # vibes riff in the A sections, the syncopated JUMP theme on a muted lead
    riff = "r e A5e C6e F6e~ F6q E6e C6e | D6q. B5e~ B5h | r e A5e D6e F6e~ F6q E6e D6e | B5h. r q |"
    for bar0 in (0, 4, 16, 20):
        line(T, "base", "lead", riff, bar0, M_VIBES, 0.3, {"plate": 0.3, "echo": 0.25}, legato=False)
    line(T, "base", "lead", LOBBY_JUMP, 8, SQUARE_LEAD, 0.3, {"plate": 0.3, "echo": 0.2}, pickup=1.0, cutoff=2400.0)
    line(T, "base", "lead", LOBBY_JUMP, 8, M_VIBES, 0.16, {"plate": 0.3}, legato=False, pickup=1.0, transpose=-12)
    # break: vibes solo licks over the claps
    line(T, "base", "lead", "F5e A5e C6e E6e D6q C6q | B5e G5e F5e D5e B4h | D6e C6e A5e F5e G5q A5q | Bb5h. r q | "
         "F6e E6e C6e A5e D6q C6q | B5e C6e D6e F6e E6h | D6e C6e Bb5e A5e G5q E5q | F5h. C5t D5t E5t |", 24, M_VIBES, 0.3,
         {"plate": 0.3, "echo": 0.3}, legato=False)
    T.render(rms_db=-15.5)


# --------------------------------------------------------------------------
# RESULTS - "Course Clear". C major, 92 bpm, 16 bars: piano sings the JUMP B phrase over
# soft strings and brushes; a gentle, satisfied loop behind the results panel.
# --------------------------------------------------------------------------
def piece_results():
    T = me.Track("results", 92, 16, 4, swing=0.1)
    r = T.rng
    T.reverb("hall", me.make_ir(r, rt60=1.9, predelay=0.02, damp=4500, er=0.5))
    T.bus("keys", eq=std_eq(60))
    T.bus("strings", eq=std_eq(80, 11000))
    T.bus("perc", eq=std_eq(80))
    T.bus("bass", eq=std_eq(35, 3000))
    H = {"hall": 0.3}
    P = prog(JUMP_B_CHORDS + JUMP_A_CHORDS.replace("| Ab | Bb | C |", "| Ab | Bb | C |"), 4, 0)
    pad(T, "base", "strings", P, STRINGS_SOFT, center=62, count=4, gain=0.13, sends=H, vel=0.45)
    stabs(T, "base", "keys", P, (0.0, 2.0), me.memo(me.piano, 2), center=58, count=3, gain=0.2, sends=H, vel=0.4, dur=1.8)
    bass(T, "base", "bass", P, [(0, 0, 1.5, 0.7), (2, 7, 1.5, 0.55)], M_PIZZ, lo=36, hi=48, gain=0.4, sends=H)
    line(T, "base", "keys", JUMP_B, 0, PIANO, 0.34, H, legato=False, transpose=0)
    line(T, "base", "keys", JUMP_A, 8, PIANO, 0.3, H, legato=False, transpose=-12)
    line(T, "base", "keys", "r w | r w | r w | r w | r w | r h. G5t A5t B5t | C6h G6h | r w |", 8, M_GLOCK, 0.14,
         {"hall": 0.5}, legato=False)
    brush = bank("brush", lambda r: me.snare(r, "brush"), 4)
    kit(T, "base", "perc", range(0, 16), {"brush": (brush, "x.g.x.g.x.g.x.gg", 0.14), "kick": (KICK_SOFT, "x.......x.......", 0.3)},
        sends={"hall": 0.2})
    T.render(rms_db=-17.0)


# --------------------------------------------------------------------------
# VICTORY - "Summit". C major, 88 bpm, 24 bars: the whole JUMP theme for full orchestra and
# choir after every course is beaten - A (horns + strings), B (choir + violins), A (tutti).
# --------------------------------------------------------------------------
def piece_victory():
    T = me.Track("victory", 88, 24, 4)
    r = T.rng
    T.reverb("hall", me.make_ir(r, rt60=2.8, predelay=0.03, damp=4200, er=0.5))
    for b_, e in (("strings", std_eq(40, 13000)), ("brass", std_eq(60, 9000)), ("choir", std_eq(120, 9000)),
                  ("harp", std_eq(60)), ("perc", std_eq(30)), ("bass", std_eq(30, 4000))):
        T.bus(b_, eq=e)
    H = {"hall": 0.4}
    a1 = prog(JUMP_A_CHORDS, 4, 0)
    b1 = prog(JUMP_B_CHORDS, 4, 8)
    a2 = prog(JUMP_A_CHORDS, 4, 16)
    allp = a1 + b1 + a2
    pad(T, "base", "strings", allp, I(me.strings, att=0.2, rel=0.6, bright=0.55, tremolo=0.2), center=64, count=4,
        gain=0.2, sends=H, vel=0.75)
    arp(T, "base", "harp", allp, [0, 2, 4, 6, 5, 3, 1, 2], 0.5, M_HARP, lo=48, hi=86, gain=0.26, sends=H)
    bass(T, "base", "bass", allp, [(0, 0, 2, 0.85), (2, 0, 2, 0.65)], I(me.strings, att=0.05, rel=0.3, voices=3, bright=0.4),
         lo=36, hi=48, gain=0.34)
    bass(T, "base", "bass", allp, [(0, 0, 4, 0.6)], TUBA, lo=33, hi=45, gain=0.12)
    line(T, "base", "brass", JUMP_PICKUP + " | " + JUMP_A, 0, HORNS, 0.42, H, transpose=-12, pickup=1.0)
    line(T, "base", "strings", JUMP_PICKUP + " | " + JUMP_A, 0, VIOLINS, 0.3, H, pickup=1.0)
    line(T, "base", "choir", JUMP_B, 8, CHOIR_A, 0.36, {"hall": 0.5}, transpose=-12)
    line(T, "base", "strings", JUMP_B, 8, I(me.strings, att=0.1, rel=0.4, bright=0.6, voices=5), 0.32, H)
    pad(T, "base", "brass", b1, HORN, center=57, count=3, gain=0.14, sends=H, vel=0.55)
    line(T, "base", "brass", JUMP_A, 16, TRUMPETS, 0.36, H)
    line(T, "base", "brass", JUMP_A, 16, HORNS, 0.34, H, transpose=-12)
    pad(T, "base", "choir", a2, CHOIR_A, center=62, count=4, gain=0.18, sends={"hall": 0.5}, vel=0.7)
    pad(T, "base", "brass", a2, TROMBONES, center=52, count=3, gain=0.14, sends=H, vel=0.7)
    snr = bank("snare_march", lambda r: me.snare(r, "march"), 4)
    kit(T, "base", "perc", range(16, 24), {"snare": (snr, "x..g..x.x.g.x...", 0.15)}, sends={"hall": 0.25})
    crash = bank("crash", lambda r: me.cymbal(r, "crash"), 2)
    for bar in (0, 8, 16, 21, 23):
        ring(T, "base", "perc", bar * 4, me.timpani(r, float(mtof(43 if bar != 21 else 44)), 0.9), 0.36, 0.0, {"hall": 0.3})
    for bar in (0, 16, 23):
        ring(T, "base", "perc", bar * 4, crash[bar % 2], 0.18, -0.3, {"hall": 0.3})
    for bar in (8, 16):
        swell_into(T, "base", "perc", bar, 4, 0.18, H)
    tb = bank("tubular", lambda r: me.bell(r, float(mtof(72)), 4.0, 0.8), 1)[0]
    for bar in (0, 16, 23):
        ring(T, "base", "perc", bar * 4, tb, 0.12, 0.4, {"hall": 0.5})
    T.render(rms_db=-15.0)


# --------------------------------------------------------------------------
# BOUNCE FOUNDRY - D minor (phrygian colour), 138 bpm, 48 bars. A forge: marcato ostinato,
# anvils on the off-beats, taiko; a heavy brass march; the JUMP theme turned minor, then a
# Bb - C - D major lift through the pour. Hi layer: full taiko ensemble, choir, trumpets,
# tremolo strings, gong.
# --------------------------------------------------------------------------
FOUNDRY_A_CH = "| Dm | Dm | Bb | A | Dm | Dm | Eb | A7 |"
FOUNDRY_B_CH = "| Dm | Bb | Gm | A | Dm | F | Eb | A | Dm | Bb | Gm | A7 | Dm | Bb | Gm6 | A7 |"
FOUNDRY_B = ("D4q. D4e F4q A4q | Bb4h. A4e G4e | G4q. G4e Bb4q D5q | C#5h. A4q | "
             "D5q. C5e A4q F4q | C5q. Bb4e A4q F4q | G4q. F4e Eb4q G4q | A4w | "
             "D4q. D4e F4q A4q | D5h. C5e Bb4e | Bb4q. A4e G4q Bb4q | A4h. A3t B3t C#4t | "
             "D4h A4h | Bb4q. A4e F4q D4q | E4q. F4e G4q Bb4q | A4h. r q |")
FOUNDRY_C_CH = "| Bb | C | Dsus4 | D | D | Bb | C | D |"


def piece_foundry():
    T = me.Track("foundry", 138, 48, 4, layers=("base", "hi"))
    r = T.rng
    T.reverb("hall", me.make_ir(r, rt60=2.2, predelay=0.02, damp=3500, er=0.9, er_span=0.09,
                                tone=lambda f: me.bump(f, 1800, 3, 0.8)))
    T.delay("slap", beats=0.5, fb=0.2, damp=2500, ret=0.3, pingpong=False)
    T.bus("drums", eq=std_eq(30), drive=1.4)
    T.bus("metal", eq=std_eq(300, 14000))
    T.bus("low", eq=lambda f: me.hp(f, 32) * me.lp(f, 5000) * me.bump(f, 300, -2, 0.8))
    T.bus("brass", eq=std_eq(60, 9000), drive=1.1)
    T.bus("choir", eq=std_eq(120, 9000))
    T.bus("strings", eq=std_eq(60, 12000))
    H = {"hall": 0.3}
    odaiko = bank("odaiko", lambda r: me.taiko(r, "odaiko"), 3)
    nagado = bank("nagado", lambda r: me.taiko(r, "nagado"), 3)
    shime = bank("shime", lambda r: me.taiko(r, "shime"), 4)
    ka = bank("ka", lambda r: me.taiko(r, "ka"), 4)
    anvils = [me.anvil(me.rng_for("anv%d" % i), 1.0, p, 0.8) for i, p in enumerate((1.0, 1.0, 0.749, 1.335))]
    metal = [me.metal_hit(me.rng_for("mh%d" % i), 1.0, f, 1.0) for i, f in enumerate((147.0, 196.0, 110.0))]
    sections = [("A", 0, FOUNDRY_A_CH), ("B", 8, FOUNDRY_B_CH), ("C", 24, FOUNDRY_C_CH),
                ("D", 32, "| Dm | Dm | Dm | Dm | Eb | Eb | A | A |"), ("A2", 40, FOUNDRY_A_CH)]
    for name, bar0, ch in sections:
        P = prog(ch, 4, bar0)
        nb = len(P)
        # ostinato: marcato low strings + a growling synth bass underneath
        if name != "D":
            bass(T, "base", "low", P, [(k * 0.5, iv, 0.5, v) for k, (iv, v) in enumerate(
                ((0, 1.0), (0, 0.6), (12, 0.8), (0, 0.6), (0, 0.9), (7, 0.6), (12, 0.8), (7, 0.6)))],
                 M_CELLO_STAC, lo=38, hi=50, gain=0.4, sends={"hall": 0.15})
            bass(T, "base", "low", P, [(0, 0, 0.45, 0.9), (1.5, 0, 0.45, 0.7), (2, 0, 0.45, 0.8), (3.5, 0, 0.45, 0.7)],
                 M_SBASS, lo=26, hi=38, gain=0.32, cutoff=500.0, decay=0.1)
        else:
            bass(T, "base", "low", P, [(0, 0, 4, 0.7)], I(me.strings, att=0.3, rel=0.5, voices=4, body="cello",
                 tremolo=0.5), lo=38, hi=50, gain=0.35, sends=H)
            bass(T, "base", "low", P, [(0, 0, 4, 0.7)], M_SUB, lo=26, hi=38, gain=0.25)
        # taiko groove
        pats = {
            "A": {"od": "x.....x...x.....", "ka": "..g...g...g...x."},
            "B": {"od": "x.....x...x...x.", "ka": "..x...x...x...x."},
            "C": {"od": "x.......x...x...", "ka": "....x.......x..."},
            "D": {"od": "x...............", "ka": "................"},
            "A2": {"od": "x.....x...x.....", "ka": "..g...g...g...x."},
        }[name]
        kit(T, "base", "drums", range(bar0, bar0 + nb), {"od": (odaiko, pats["od"], 0.7), "ka": (ka, pats["ka"], 0.3)},
            sends={"hall": 0.25})
        # the forge: anvils ring on the off-beats (tuned to D / A), metal clangs on bar ends
        for bar in range(bar0, bar0 + nb):
            for o, k in ((1.5, 0), (3.5, 1 if bar % 2 else 2)):
                if name == "D" and bar - bar0 < 4 and o == 1.5:
                    continue
                T.hit("base", "metal", bar * 4 + o, anvils[k], 0.2 * r.uniform(0.85, 1.0), 0.35 if k else -0.3,
                      {"hall": 0.35, "slap": 0.2})
            if bar % 4 == 3:
                T.hit("base", "metal", bar * 4 + 3.0, metal[bar % 3], 0.16, -0.5, {"hall": 0.4})
        # hi layer: the full ensemble
        hp_ = {
            "A": ("x.x...x...x.x...", "xxgxxgxgxxgxxgxg", "................"),
            "B": ("x.x...x...x.x.x.", "xgxgxgxgxgxgxgxg", "....x.......x..."),
            "C": ("x...x...x...x.x.", "xxxxxxxxxxxxxxxx", "....x.......x..."),
            "D": ("x.......x.......", "................", "................"),
            "A2": ("x.x...x...x.x...", "xxgxxgxgxxgxxgxg", "....x.......x..x"),
        }[name]
        kit(T, "hi", "drums", range(bar0, bar0 + nb), {"na": (nagado, hp_[0], 0.55), "shime": (shime, hp_[1], 0.18),
                                                       "snare": (bank("snare_ac", lambda r: me.snare(r, "acoustic"), 4), hp_[2], 0.3)},
            sends={"hall": 0.3})
    # brass: the foundry march (trombones + tuba base; horns + trumpets an octave up in hi)
    line(T, "base", "brass", FOUNDRY_B, 8, TROMBONES, 0.42, {"hall": 0.35})
    line(T, "base", "brass", FOUNDRY_B, 8, TUBA, 0.18, H, transpose=-12)
    line(T, "hi", "brass", FOUNDRY_B, 8, HORNS, 0.3, {"hall": 0.4}, transpose=12)
    line(T, "hi", "brass", " ".join(FOUNDRY_B.split("|")[8].split()) + " | " + " | ".join(FOUNDRY_B.split("|")[9:16]) + " |",
         16, TRUMPETS, 0.24, {"hall": 0.4}, transpose=12)
    # low brass fragment in the reprise
    line(T, "base", "brass", " | ".join(FOUNDRY_B.split("|")[0:4]) + " | r w | r w | r w | r w |", 40, TROMBONES, 0.36,
         {"hall": 0.35})
    line(T, "hi", "choir", "D4w | D4w | Bb3w | A3w | D4w | D4w | Eb4w | C#4w |", 40, CHOIR_A, 0.3, {"hall": 0.45})
    # the pour: build (bars 24-27) then the JUMP lift in D major (28-31)
    for i, sym in enumerate(("Bb", "C", "Dsus4", "D")):
        pad(T, "base", "brass", prog("| %s |" % sym, 4, 24 + i), I(me.brass, kind="horn", voices=2, att=1.2), center=57,
            count=3, gain=0.2, sends=H, vel=0.5 + 0.12 * i)
    line(T, "base", "brass", "C5h G5h | C6q. Bb5e Ab5q C6q | D6q. C6e Bb5q D6q | E6w |", 28, HORNS, 0.4, {"hall": 0.4},
         transpose=-10)
    line(T, "hi", "brass", "C5h G5h | C6q. Bb5e Ab5q C6q | D6q. C6e Bb5q D6q | E6w |", 28, TRUMPETS, 0.3, {"hall": 0.4},
         transpose=2)
    pad(T, "hi", "choir", prog(FOUNDRY_C_CH, 4, 24), CHOIR_A, center=62, count=4, gain=0.22, sends={"hall": 0.5}, vel=0.75)
    pad(T, "base", "strings", prog("| D | Bb | C | D |", 4, 28), I(me.strings, att=0.1, rel=0.4, bright=0.6, tremolo=0.5),
        center=66, count=4, gain=0.14, sends=H, vel=0.8)
    # hi: tremolo strings over the theme, choir chant in the breakdown
    pad(T, "hi", "strings", prog(FOUNDRY_B_CH, 4, 8), I(me.strings, att=0.08, rel=0.3, bright=0.5, tremolo=0.6),
        center=67, count=3, gain=0.12, sends=H, vel=0.7)
    for bar in range(32, 40):
        for o in (0.0, 1.5, 3.0):
            T.add("hi", "choir", bar * 4 + o, me.choir(r, float(mtof(50 if bar < 36 else (51 if bar < 38 else 49))),
                  0.3 * T.spb, 0.8, "a", voices=5, att=0.02, rel=0.25), 0.2, 0.0, {"hall": 0.4})
    # gongs and booms at the big moments, a riser out of the breakdown
    gong = me.gong(me.rng_for("fgong"), 1.0, 5.0, 73.0)
    for bar in (8, 24, 28):
        ring(T, "hi", "metal", bar * 4, gong, 0.2, 0.0, {"hall": 0.3})
    ring(T, "base", "drums", 36 * 4, me.timpani_roll(r, float(mtof(45)), 16.0, T.spb, 0.15, 1.0), 0.35, 0.0, H)
    ring(T, "hi", "metal", 36 * 4, me.riser(r, 16.0, T.spb, 0.8, 200.0, 5000.0), 0.18, 0.0, {"hall": 0.3})
    for bar in (8, 24, 40):
        ring(T, "base", "drums", bar * 4, me.boom(me.rng_for("fboom"), 1.0, 36.0, 2.0), 0.3, 0.0, {"hall": 0.2})
    T.render(rms_db=-14.5, hi_gain=0.7)


# --------------------------------------------------------------------------
# BALANCE WORKS - D mixolydian sea shanty in 6/8 (dotted quarter = 104), 64 bars. Accordion
# tune over guitar, upright bass and bodhran; a tin-whistle chorus; the JUMP theme rolling in
# compound time with a Bb - C - D lift; a whistle break over the claps. Hi layer: fiddle,
# stomps and claps, a "heave-ho" crew, strings, marimba sea-sparkle.
# --------------------------------------------------------------------------
BAL_A_CH = "| D | D | C | C | D | D | A | A | D | D | C | C | G | D | A | D |"
BAL_A = ("D5x D5t F#5x A5t | A5x G5t F#5x E5t | E5x E5t G5x E5t | C5x D5t E5q | "
         "D5x D5t F#5x A5t | D6x C6t A5x F#5t | E5x F#5t G5x A5t | E5h | "
         "D5x D5t F#5x A5t | A5x G5t F#5x E5t | G5x G5t C6x G5t | E5x D5t C5q | "
         "B4x D5t G5x B5t | A5x F#5t D5x F#5t | E5x A5t G5x E5t | D5h |")
BAL_B_CH = "| G | G | D | D | G | G | A | A | Bm | G | D | A | G | D | A | D |"
BAL_B = ("B5t A5t G5t D6x B5t | C6x B5t A5x G5t | F#5t E5t D5t A5x F#5t | A5h | "
         "B5t A5t G5t D6x B5t | E6x D6t B5x G5t | A5t B5t C#6t E6x C#6t | A5h | "
         "B5x A5t F#5x D5t | G5x B5t D6x B5t | A5x F#5t D5x F#5t | E5x F#5t G5x A5t | "
         "B5x D6t G6x D6t | F#6x E6t D6x A5t | C#6x B5t A5x E5t | D6h |")
BAL_J_CH = "| D | G | Em | A | D | Bb | C | D |"
BAL_J = ("A4t B4t C#5t | D5q A5q | B5x A5t F#5x D5t | E5x F#5t G5x B5t | A5q A4t B4t C#5t | "
         "D5q A5q | D6x C6t Bb5x D6t | E6x D6t C6x E6t | F#6h |")
BAL_D_CH = "| D | D | C | C | D | D | A | A |"
BAL_D = ("r h | A5t B5t A5t F#5x D5t | r h | G5t A5t G5t E5x C5t | r h | A5t B5t D6t F#6x D6t | "
         "E6x D6t C#6x A5t | A5h |")


def piece_balance():
    T = me.Track("balance", 104, 64, 2, layers=("base", "hi"))
    r = T.rng
    T.reverb("harbour", me.make_ir(r, rt60=1.3, predelay=0.012, damp=5500, er=0.7, er_span=0.05))
    T.reverb("wide", me.make_ir(r, rt60=2.4, predelay=0.04, damp=3500, er=0.2))
    T.delay("echo", beats=1.0, fb=0.25, damp=3000, ret=0.35)
    T.bus("acc", eq=std_eq(120, 11000))
    T.bus("gtr", eq=lambda f: me.hp(f, 90) * me.bump(f, 3000, 2, 0.8))
    T.bus("bass", eq=std_eq(35, 3000))
    T.bus("drums", eq=std_eq(40), drive=1.15)
    T.bus("lead", eq=std_eq(200))
    T.bus("strings", eq=std_eq(60, 12000))
    T.bus("crew", eq=std_eq(90, 7000))
    HB = {"harbour": 0.3}
    third = 1.0 / 3.0
    frame = bank("frame", lambda r: me.frame_drum(r, 1.0, True), 3)
    frame_hi = bank("frame_hi", lambda r: me.frame_drum(r, 1.0, False), 3)
    clp = bank("clap", lambda r: me.clap(r), 3)
    stomp = bank("stomp", lambda r: me.kick(r, "soft"), 2)
    tamb = TAMB
    sections = [("A", 0, BAL_A_CH), ("B", 16, BAL_B_CH), ("A", 32, BAL_A_CH), ("J", 48, BAL_J_CH), ("D", 56, BAL_D_CH)]
    for name, bar0, ch in sections:
        P = prog(ch, 2, bar0)
        nb = len(P)
        # guitar: bass note on 1, strums on the 3rd and 6th eighths ("oom-pa-pa")
        strum(T, "base", "gtr", P, "B.DA.D" if name != "D" else "B..A..", M_GUITAR, center=58, gain=0.3,
              sends=HB, step=third, vel=0.7, bass_lo=38, bass_hi=50)
        bass(T, "base", "bass", P, [(0, 0, 0.9, 0.9), (1, 7, 0.9, 0.7)], M_UPRIGHT, lo=33, hi=45, gain=0.5, period=2)
        kit(T, "base", "drums", range(bar0, bar0 + nb), {
            "frame": (frame, "x..x.." if name != "D" else "x.....", 0.5),
            "frame_hi": (frame_hi, "..g..g" if name != "D" else "...g..", 0.3),
        }, step=third, sends=HB)
        # hi: stomp-clap, tambourine, crew "ho" on the beats
        kit(T, "hi", "drums", range(bar0, bar0 + nb), {
            "stomp": (stomp, "x..x.." if name != "D" else "x..x..", 0.55),
            "clap": (clp, "...x.." if name != "D" else "...x..", 0.4),
            "tamb": (tamb, "x.xx.x" if name in ("B", "J") else "......", 0.14),
        }, step=third, sends={"harbour": 0.2})
        pad(T, "hi", "strings", P, I(me.strings, att=0.2, rel=0.4, bright=0.45), center=64, count=3, gain=0.1,
            sends=HB, vel=0.55)
    # the tune: accordion, whistle chorus, fiddle doubling in the hi layer
    for bar0 in (0, 32):
        line(T, "base", "acc", BAL_A, bar0, ACCORDION, 0.36, {"harbour": 0.25}, legato=False, pan=-0.15)
        line(T, "hi", "strings", BAL_A, bar0, FIDDLE, 0.26, {"harbour": 0.3}, transpose=-12 if bar0 == 32 else 0,
             pan=0.3)
    line(T, "base", "lead", BAL_B, 16, WHISTLE, 0.3, {"harbour": 0.3, "echo": 0.15})
    line(T, "base", "acc", "D5h | D5h | A4h | A4h | D5h | D5h | E5h | E5h | F#5h | D5h | A4h | C#5h | D5h | A4h | E5h | F#5h |",
         16, I(me.accordion, musette=False), 0.2, HB, legato=False, pan=-0.3)
    line(T, "hi", "strings", BAL_B, 16, FIDDLE, 0.22, {"harbour": 0.3}, transpose=-12, pan=0.35)
    # the JUMP theme in compound time: accordion (base), fiddle and horn (hi)
    line(T, "base", "acc", BAL_J, 48, ACCORDION, 0.38, HB, legato=False, pickup=1.0)
    line(T, "hi", "strings", BAL_J, 48, FIDDLE, 0.25, HB, pickup=1.0, pan=0.3)
    line(T, "hi", "lead", BAL_J, 48, HORN, 0.2, {"wide": 0.3}, pickup=1.0, transpose=-12)
    # break: whistle over claps, marimba sea sparkle
    line(T, "base", "lead", BAL_D, 56, WHISTLE, 0.3, {"harbour": 0.3, "echo": 0.3})
    arp(T, "hi", "lead", prog(BAL_A_CH + BAL_B_CH, 2, 0), [0, 2, 1, 3, 2, 1], third, M_MARIMBA, lo=62, hi=86, gain=0.12,
        sends={"wide": 0.3}, vels=(0.6, 0.4, 0.5, 0.4, 0.5, 0.4))
    # the crew: a short "ho!" on beat one of every other bar in the A sections
    for bar0 in (0, 32):
        for bar in range(bar0, bar0 + 16, 2):
            sym = prog(BAL_A_CH, 2, bar0)[bar - bar0][2]
            for m in voice(sym, 50, 3):
                T.add("hi", "crew", bar * 2, me.choir(r, float(mtof(m)), 0.35 * T.spb, 0.8, "o", voices=4, att=0.03,
                      rel=0.2, male=True), 0.14, 0.0, {"wide": 0.3}, 0.0)
    T.render(rms_db=-14.5)


# --------------------------------------------------------------------------
# CLOCKWORK HEIGHTS - E minor waltz, 3/4, 168 bpm, 80 bars. The clock ticks every beat (tick /
# tock), harpsichord and pizzicato keep the oom-pah-pah, a music box sings; a warmer G major
# clarinet strain; the JUMP theme as a waltz; tubular-bell chimes on the hour. Hi layer: the
# string waltz, horns, bells, triangle, timpani.
# --------------------------------------------------------------------------
CW_A_CH = "| Em | Em | Am | Am | D | D | G | B7 | Em | Em | Am | Am | C | B7 | Em | Em |"
CW_A = ("B5h E6q | D#6q E6q F#6q | G6h. | E6h r q | F#6h A6q | G6q F#6q E6q | D6h B5q | D#6h. | "
        "B5h E6q | G6q F#6q E6q | C7h B6q | A6q G6q E6q | G6h E6q | F#6q E6q D#6q | E6h. | r h. |")
CW_B_CH = "| G | G | D/F# | D/F# | Em | Em | C | D | G | G | Bm | Bm | C | Am | D7 | D7 |"
CW_B = ("D5h B4q | G4h. | A4q B4q C5q | D5h. | E5h D5q | B4h G4q | E5q D5q C5q | A4h. | "
        "D5h B4q | G5h. | F#5q E5q D5q | B4h. | C5q E5q G5q | A5h G5q | F#5q E5q D5q | C5h A4q |")
CW_J_CH = "| G | Cmaj7 | Am7 | D | G | Eb | F | G | Em | C | Am | D | Bm | Em | C | D |"
CW_J = ("D5e E5e F#5e | G5h D6q | E6q. D6e B5q | A5q. B5e C6q | D6q. D5e E5e F#5e | G5h D6q | G6q. F6e Eb6q | "
        "A6q. G6e F6q | B6h. | E6q. F#6e G6q | A6h G6q | E6q. F#6e G6q | B6h A6q | F#6q. G6e A6q | B6h. | "
        "E6q G6q B6q | A6h. |")


def piece_clockwork():
    T = me.Track("clockwork", 168, 80, 3, layers=("base", "hi"))
    r = T.rng
    T.reverb("tower", me.make_ir(r, rt60=2.6, predelay=0.03, damp=4000, er=0.7, er_span=0.08))
    T.reverb("box", me.make_ir(r, rt60=0.8, predelay=0.005, damp=7000, er=0.9, er_span=0.02))
    T.delay("echo", beats=1.0, fb=0.3, damp=4000, ret=0.35)
    T.bus("tick", eq=std_eq(400))
    T.bus("keys", eq=std_eq(80, 12000))
    T.bus("pizz", eq=std_eq(40))
    T.bus("lead", eq=std_eq(200))
    T.bus("strings", eq=std_eq(50, 12000))
    T.bus("brass", eq=std_eq(70, 9000))
    T.bus("bells", eq=std_eq(150))
    TW = {"tower": 0.3}
    tick = [me.clock_tick(me.rng_for("ck%d" % i), 1.0, False) for i in range(3)]
    tock = [me.clock_tick(me.rng_for("ct%d" % i), 1.0, True) for i in range(3)]
    esc = [me.woodblock(me.rng_for("esc%d" % i), 1.0, 0.62) for i in range(2)]
    tri = bank("triangle", lambda r: me.triangle(r, 1.0, 1.6), 2)
    sections = [("A", 0, CW_A_CH, CW_A, "musicbox"), ("B", 16, CW_B_CH, CW_B, "clar"), ("J", 32, CW_J_CH, None, "celesta"),
                ("A", 48, CW_A_CH, CW_A, "musicbox"), ("B", 64, CW_B_CH, CW_B, "clar")]
    for name, bar0, ch, tune, lead in sections:
        P = prog(ch, 3, bar0)
        # the clock: tick / tock on every beat, the escapement clunk on each bar
        for bar in range(bar0, bar0 + 16):
            for bt in range(3):
                s = tick[(bar + bt) % 3] if bt != 1 else tock[bar % 3]
                T.hit("base", "tick", bar * 3 + bt, s, 0.16 if bt == 0 else 0.1, 0.45 if bt % 2 else -0.45, {"box": 0.3})
            T.hit("base", "tick", bar * 3, esc[bar % 2], 0.12, 0.0, {"tower": 0.2})
        # waltz: pizzicato bass + harpsichord chords
        waltz(T, "base", "keys", P, M_PIZZ, M_HARPSI, center=64, count=3, gains=(0.5, 0.16), sends={"tower": 0.2},
              bass_lo=38, bass_hi=50)
        # hi: the string waltz (cellos on 1, violas / violins on 2-3) and triangle on the downbeats
        waltz(T, "hi", "strings", P, M_CELLO_STAC, M_VLN_STAC, center=67, count=3, gains=(0.3, 0.1), sends=TW,
              bass_lo=36, bass_hi=48, vels=(0.8, 0.55, 0.5), chord_dur=0.5)
        kit(T, "hi", "bells", range(bar0, bar0 + 16), {"tri": (tri, "x..", 0.06)}, step=1.0, sends={"tower": 0.3})
        if name != "J":
            pad(T, "hi", "brass", P[::2], HORN, center=57, count=2, gain=0.12, sends=TW, vel=0.5)
        if tune:
            if lead == "musicbox":
                line(T, "base", "lead", tune, bar0, M_MUSICBOX, 0.34, {"box": 0.4, "echo": 0.2}, legato=False)
                line(T, "hi", "strings", tune, bar0, I(me.strings, att=0.08, rel=0.35, bright=0.6, voices=5), 0.28, TW,
                     transpose=-12, pan=-0.2)
            else:
                line(T, "base", "lead", tune, bar0, CLARINET, 0.4, TW, pan=0.1)
                line(T, "base", "lead", tune, bar0, BASSOON, 0.16, TW, transpose=-12, pan=-0.1)
                line(T, "hi", "brass", tune, bar0, HORN, 0.22, TW, transpose=0, pan=-0.3)
    # the JUMP theme as a waltz: celesta (base), violins an octave down (hi)
    line(T, "base", "lead", CW_J, 32, M_CELESTA, 0.4, {"tower": 0.35, "echo": 0.25}, legato=False, pickup=1.5)
    line(T, "base", "lead", CW_J, 32, CLARINET, 0.2, TW, pickup=1.5, transpose=-12)
    line(T, "hi", "strings", CW_J, 32, I(me.strings, att=0.08, rel=0.35, bright=0.6, voices=5), 0.3, TW, pickup=1.5,
         transpose=-12, pan=-0.2)
    # tubular-bell chimes "on the hour" at every section, the hour struck before the reprise
    for bar0 in (0, 16, 32, 48, 64):
        ring(T, "hi", "bells", bar0 * 3, me.bell(r, float(mtof(64 if bar0 % 32 == 0 else 67)), 4.0, 0.8), 0.16, 0.4,
             {"tower": 0.45})
    for k in range(3):
        ring(T, "base", "bells", (45 + k) * 3, me.bell(r, float(mtof(52)), 4.0, 0.7, kind="church"), 0.18, -0.3,
             {"tower": 0.5})
    for bar in (16, 32, 48, 64):
        ring(T, "hi", "keys", bar * 3, me.timpani(r, float(mtof(40 if bar % 32 == 0 else 43)), 0.7), 0.26, 0.0, TW)
    T.render(rms_db=-15.0)


# --------------------------------------------------------------------------
# CORAL DEPTHS - F lydian, 80 bpm, 32 bars, two full arrangements the game crossfades as you
# dive: "base" = the sunlit shallows (e-piano, harp ripples, vibraphone, marimba, bubbles,
# flute), "hi" = the deep (choir, low strings, a dark synth pulse, kalimba, whale-song glides,
# temple bells). The JUMP theme drifts by in augmentation.
# --------------------------------------------------------------------------
REEF_A_CH = "| Fmaj7 | G/F | Em7 | Am7 | Dm9 | G/B | Cmaj7 | Bbmaj7#11 |"
REEF_A = "A5q. C6e E6h | D6q. B5e G5h | G5q. B5e D6q E6q | C6w | F5q. A5e E6h | D6q. B5e G5h | E5q. G5e B5q C6q | A5w |"
REEF_B_CH = "| Dm9 | Bbmaj7 | F/A | Gm7 | Dm9 | Bbmaj7 | Gm7 | C7sus4 |"
REEF_B = "E5h F5q A5q | D6h. C6q | C6q A5q F5q A5q | Bb5w | A5h. C6q | F6h. E6q | D6q. C6e Bb5q G5q | F5h C5x D5x E5x |"
REEF_J_CH = "| F | F | Bbmaj7 | Bbmaj7 | Gm7 | Gm7 | C | C7sus4 |"
REEF_J = "F5w | C6w | D6h. C6q | A5h F5h | G5h. A5q | Bb5h D6h | C6w | C6w |"
REEF_D_CH = "| Fmaj7 | G/F | Em7 | Am7 | Dm9 | Bbmaj7 | Gm7 | C7sus4 |"


def piece_reef():
    T = me.Track("reef", 80, 32, 4, layers=("base", "hi"))
    r = T.rng
    T.reverb("water", me.make_ir(r, rt60=2.8, predelay=0.03, damp=3000, er=0.3, tone=lambda f: me.lp(f, 6000, 1)))
    T.reverb("abyss", me.make_ir(r, rt60=5.5, predelay=0.06, damp=1800, er=0.1, tone=lambda f: me.lp(f, 3000, 1)))
    T.delay("echo", beats=0.75, fb=0.4, damp=2500, ret=0.45)
    T.bus("keys", eq=std_eq(80, 10000), chorus=(2.5, 0.5, 11.0, 0.45))
    T.bus("harp", eq=std_eq(80))
    T.bus("lead", eq=std_eq(150, 11000))
    T.bus("perc", eq=std_eq(200))
    T.bus("bass", eq=std_eq(30, 2500))
    T.bus("pad", eq=std_eq(80, 9000), chorus=(4.0, 0.25, 15.0, 0.5))
    T.bus("deep", eq=lambda f: me.hp(f, 30) * me.lp(f, 5000))
    T.bus("choir", eq=std_eq(100, 7000))
    W = {"water": 0.4}
    sections = [("A", 0, REEF_A_CH), ("B", 8, REEF_B_CH), ("J", 16, REEF_J_CH), ("D", 24, REEF_D_CH)]
    bubbles = [me.bubble(me.rng_for("bub%d" % i), 1.0, f) for i, f in enumerate((600, 800, 1000, 1250, 1500, 1900))]
    for name, bar0, ch in sections:
        P = prog(ch, 4, bar0)
        # ---- shallows (base)
        stabs(T, "base", "keys", P, (0.0, 2.5), M_EPIANO, center=62, count=4, gain=0.2, sends=W, vel=0.5, dur=2.2)
        arp(T, "base", "harp", P, [0, 1, 2, 3, 4, 5, 4, 3, 2, 1, 2, 3, 4, 5, 6, 5], 0.25, M_HARP, lo=53, hi=89,
            gain=0.13, sends={"water": 0.5, "echo": 0.2}, vels=(0.6, 0.4, 0.45, 0.4))
        bass(T, "base", "bass", P, [(0, 0, 2.5, 0.8), (2.5, 7, 1.0, 0.6), (3.5, 12, 0.5, 0.5)], M_SUB, lo=29, hi=41,
             gain=0.4, drive=1.1)
        arp(T, "base", "perc", P, [0, 2, 4, 2], 1.0, M_MARIMBA, lo=60, hi=79, gain=0.1, sends=W, vels=(0.5, 0.35, 0.4, 0.35))
        pad(T, "base", "pad", P, I(me.pad_glass, att=1.5, rel=2.5), center=70, count=3, gain=0.07, sends=W, vel=0.5)
        for bar in range(bar0, bar0 + 8):
            for _ in range(3):
                T.hit("base", "perc", bar * 4 + r.integers(0, 8) * 0.5, bubbles[int(r.integers(0, 6))],
                      0.05 * r.uniform(0.5, 1.0), r.uniform(-0.8, 0.8), {"water": 0.5})
        kit(T, "base", "perc", range(bar0, bar0 + 8), {"shk": (SHK, "..g...g...g...g." if name != "J" else "................", 0.1)},
            sends=W)
        # ---- the deep (hi)
        pad(T, "hi", "choir", P, I(me.choir, vowel="u", att=1.2, rel=2.0), center=58, count=3, gain=0.14,
            sends={"abyss": 0.6}, vel=0.55)
        bass(T, "hi", "deep", P, [(0, 0, 4, 0.7)], I(me.strings, att=0.8, rel=1.2, voices=4, body="cello", bright=0.25),
             lo=36, hi=48, gain=0.22, sends={"abyss": 0.4})
        bass(T, "hi", "bass", P, [(0, 0, 3.5, 0.9)], M_SUB, lo=24, hi=36, gain=0.3, drive=1.0)
        # a slow dark pulse (filtered saws on the 8ths, breathing)
        arp(T, "hi", "deep", P, [0, 0, 1, 0, 2, 0, 1, 0], 0.5, me.memo(I(me.synth_pluck, cutoff=900.0, decay=0.25), 3, "dpulse"),
            lo=41, hi=60, gain=0.12, sends={"abyss": 0.4, "echo": 0.3}, vels=(0.7, 0.4, 0.5, 0.4))
        arp(T, "hi", "perc", P, [2, 4, 3, 5], 2.0, M_KALIMBA, lo=67, hi=91, gain=0.1, sends={"abyss": 0.6, "echo": 0.4},
            vels=(0.6, 0.45, 0.5, 0.45))
    # melodies
    line(T, "base", "lead", REEF_A, 0, M_VIBES, 0.34, {"water": 0.45, "echo": 0.2}, legato=False)
    line(T, "base", "lead", REEF_B, 8, FLUTE, 0.32, {"water": 0.5, "echo": 0.2})
    line(T, "base", "lead", REEF_J, 16, M_VIBES, 0.32, {"water": 0.45, "echo": 0.25}, legato=False)
    line(T, "base", "lead", REEF_J, 16, OCARINA, 0.2, W, transpose=-12)
    line(T, "base", "lead", REEF_A.replace("A5w |", "C6w |"), 24, M_EPIANO, 0.3, {"water": 0.45, "echo": 0.3}, legato=False,
         transpose=-12)
    # the deep: celesta / choir carry the same lines, whale-like glides between phrases
    line(T, "hi", "lead", REEF_A, 0, M_CELESTA, 0.22, {"abyss": 0.6, "echo": 0.35}, legato=False)
    line(T, "hi", "choir", REEF_B, 8, CHOIR_O, 0.26, {"abyss": 0.6}, transpose=-12)
    line(T, "hi", "choir", REEF_J, 16, CHOIR_U, 0.3, {"abyss": 0.6}, transpose=-12)
    line(T, "hi", "lead", REEF_A, 24, I(me.solo_string, bright=0.35, body="cello", att=0.3, rel=0.6), 0.26, {"abyss": 0.5},
         transpose=-24)
    for bar, f0, f1 in ((3, 55, 62), (7, 60, 53), (11, 57, 64), (15, 62, 55), (23, 53, 60), (31, 60, 65)):
        n = int(3.2 * T.spb * me.MSR)
        tt = me.secs(n)
        u = np.clip(tt / (3.0 * T.spb), 0, 1)
        fcurve = float(mtof(f0)) * (float(mtof(f1)) / float(mtof(f0))) ** (u * u * (3 - 2 * u))
        wh = np.sin(me.TAU * np.cumsum(fcurve * (1 + 0.004 * np.sin(me.TAU * 4.5 * tt))) / me.MSR)
        wh += 0.3 * np.sin(2 * me.TAU * np.cumsum(fcurve) / me.MSR)
        wh *= me.env_asr(n, 2.6 * T.spb, 0.5, 0.6) * 0.3
        T.add("hi", "lead", bar * 4 + 0.5, wh, 0.2, -0.4 if bar % 2 else 0.4, {"abyss": 0.8, "echo": 0.3}, 0.0)
    for bar in (0, 16):
        ring(T, "hi", "perc", bar * 4, me.bell(r, float(mtof(53)), 6.0, 0.7, kind="church"), 0.14, 0.0, {"abyss": 0.7})
    T.render(rms_db=-15.5, mode="cross")


# --------------------------------------------------------------------------
# ORBITAL DRIFT - C lydian, 100 bpm, 48 bars. Drifting: a delayed synth arpeggio, glass pads,
# strings and harp under a horn theme that climbs straight into the JUMP theme; an A minor
# "flare" with a string ostinato; the B phrase with choir. Hi layer: the space opera - trumpets
# and trombones, a snare march with triplet rolls, timpani, cymbals, choir, driving low strings.
# --------------------------------------------------------------------------
ORB_INTRO_CH = "| C | D/C | C | D/C | Am | D/F# | F | G |"
ORB_THEME_CH = "| C | D/C | Em | Am | F | G | C/E | Dm7 G |"
ORB_THEME = "C5h. G4e C5e | D5h. A4e D5e | E5q. D5e B4q G4q | A4w | A4q. C5e F5q A5q | G5h. D5q | E5q. F5e G5q C6q | B5h. G4t A4t B4t |"
ORB_FLARE_CH = "| Am | F | Dm | E | Am | F | Bb | E7 |"
ORB_FLARE = "A4q. B4e C5q E5q | F5h. E5q | D5q. E5e F5q A5q | G#5w | A5q. B5e C6q E6q | F6h. E6q | D6q. C6e Bb5q D6q | E6w |"


def piece_orbital():
    T = me.Track("orbital", 100, 48, 4, layers=("base", "hi"))
    r = T.rng
    T.reverb("space", me.make_ir(r, rt60=4.5, predelay=0.05, damp=3500, er=0.2))
    T.reverb("hall", me.make_ir(r, rt60=2.2, predelay=0.02, damp=4500, er=0.5))
    T.delay("echo", beats=0.75, fb=0.45, damp=4000, ret=0.5)
    T.bus("arp", eq=std_eq(200, 12000))
    T.bus("pad", eq=std_eq(80, 10000), chorus=(3.0, 0.3, 14.0, 0.4))
    T.bus("strings", eq=std_eq(40, 12000))
    T.bus("brass", eq=std_eq(60, 9500))
    T.bus("harp", eq=std_eq(80))
    T.bus("bass", eq=std_eq(30, 3000))
    T.bus("drums", eq=std_eq(30), drive=1.1)
    T.bus("choir", eq=std_eq(120, 8000))
    SP = {"space": 0.45}
    HL = {"hall": 0.35}
    intro = prog(ORB_INTRO_CH, 4, 0)
    theme = prog(ORB_THEME_CH, 4, 8) + prog(JUMP_A_CHORDS, 4, 16)
    flare = prog(ORB_FLARE_CH, 4, 24)
    bsec = prog(JUMP_B_CHORDS, 4, 32)
    outro = prog(ORB_INTRO_CH, 4, 40)
    allp = intro + theme + flare + bsec + outro
    # base: the arpeggiator, pads, strings, harp, pulse bass
    arp(T, "base", "arp", allp, [0, 2, 3, 1, 4, 2, 3, 5], 0.25, M_SPLUCK_SQ, lo=60, hi=88, gain=0.1,
        sends={"echo": 0.35, "space": 0.3}, vels=(0.8, 0.5, 0.6, 0.5), pan_fn=lambda k: 0.5 * np.sin(k * 0.7))
    pad(T, "base", "pad", allp, I(me.pad_glass, att=1.0, rel=2.0), center=67, count=4, gain=0.06, sends=SP, vel=0.5)
    pad(T, "base", "strings", theme + bsec, I(me.strings, att=0.4, rel=0.8, bright=0.45), center=62, count=4, gain=0.15,
        sends=HL, vel=0.6)
    pad(T, "base", "strings", intro + outro, STRINGS_SOFT, center=60, count=3, gain=0.12, sends=SP, vel=0.45)
    arp(T, "base", "harp", theme + bsec, [0, 2, 4, 5, 4, 2], 0.5, M_HARP, lo=48, hi=84, gain=0.18, sends=HL)
    bass(T, "base", "bass", allp, [(k * 0.5, 0, 0.4, 0.8 if k % 2 == 0 else 0.55) for k in range(8)], M_SBASS, lo=31,
         hi=43, gain=0.28, cutoff=400.0, decay=0.12)
    # melodies: horns sing the station theme into the JUMP theme; strings take the B phrase
    line(T, "base", "brass", ORB_THEME, 8, HORNS, 0.42, HL)
    line(T, "base", "brass", JUMP_A, 16, HORNS, 0.42, HL, transpose=-12)
    line(T, "base", "strings", JUMP_A, 16, VIOLINS, 0.26, HL, pan=-0.2)
    line(T, "base", "brass", ORB_FLARE, 24, HORN, 0.34, HL)
    line(T, "base", "strings", JUMP_B, 32, I(me.strings, att=0.15, rel=0.5, bright=0.55, voices=5), 0.32, HL)
    line(T, "base", "arp", "r w | r h. G5t A5t B5t | C6h G6h | r w | r w | r w | r h. G5t A5t B5t | C6h G6h |", 0,
         M_CELESTA, 0.26, {"space": 0.6, "echo": 0.4}, legato=False)
    line(T, "base", "arp", "r w | r h. G5t A5t B5t | C6h G6h | r w | r w | r w | r h. G5t A5t B5t | C6h G6h |", 40,
         M_CELESTA, 0.26, {"space": 0.6, "echo": 0.4}, legato=False)
    # hi: the space opera
    line(T, "hi", "brass", ORB_THEME, 8, TRUMPETS, 0.3, HL, transpose=12)
    line(T, "hi", "brass", JUMP_A, 16, TRUMPETS, 0.32, HL)
    pad(T, "hi", "brass", theme + flare, TROMBONES, center=52, count=3, gain=0.14, sends=HL, vel=0.65)
    line(T, "hi", "brass", ORB_FLARE, 24, TRUMPETS, 0.26, HL, transpose=0)
    line(T, "hi", "choir", JUMP_B, 32, CHOIR_A, 0.3, {"space": 0.5}, transpose=-12)
    pad(T, "hi", "choir", intro + outro, CHOIR_O, center=60, count=3, gain=0.12, sends={"space": 0.6}, vel=0.5)
    # driving low strings (spiccato 16ths) under the theme and the flare
    bass(T, "hi", "strings", theme + flare, [(k * 0.25, 0 if k % 4 != 2 else 12, 0.25, 0.9 if k % 4 == 0 else 0.55)
                                            for k in range(16)], M_CELLO_STAC, lo=36, hi=48, gain=0.2, sends=HL)
    snr = bank("snare_march", lambda r: me.snare(r, "march"), 4)
    for bar in range(8, 40):
        kit(T, "hi", "drums", (bar,), {"snare": (snr, "x..x..x.x.x.x..." if bar % 4 != 3 else "x..x..x.x.xxxxxx", 0.22)},
            sends=HL)
    for bar in range(8, 40, 2):
        ring(T, "hi", "drums", bar * 4, me.timpani(r, float(mtof(36 if bar < 24 or bar >= 32 else 33)), 0.8), 0.3, 0.0, HL)
    crash = bank("crash", lambda r: me.cymbal(r, "crash"), 2)
    for bar in (8, 16, 24, 32):
        ring(T, "hi", "drums", bar * 4, crash[bar % 2], 0.16, 0.3, HL)
        swell_into(T, "base", "drums", bar, 4, 0.14, SP)
    for bar in (0, 40):
        ring(T, "base", "bass", bar * 4, me.boom(me.rng_for("oboom"), 1.0, 33.0, 3.0), 0.22, 0.0, SP)
    T.render(rms_db=-14.5, hi_gain=1.0)


# --------------------------------------------------------------------------
# THE FINAL ASCENT - B minor to D major, 128 bpm, 56 bars. Synthwave engine (side-chained
# supersaws, octave bass, arps, gated snare) under a climbing lead; a medley bar by bar quoting
# every map before it; then the JUMP theme at full height in D major. Hi layer: choir,
# strings, brass, timpani, toms and booms.
# --------------------------------------------------------------------------
ASC_INTRO_CH = "| Bm | G | D | A | Bm | G | D | A |"
ASC_A_CH = "| Bm | G | D | A | Bm | G | Em | F# | Bm | G | D | A | G | A | F# | F# |"
ASC_A = ("F#5q. F#5e B5q D6q | C#6h. B5e A5e | A5q. F#5e A5q D6q | C#6w | F#5q. F#5e B5q D6q | E6h. D6e C#6e | "
         "B5q. A5e G5q E5q | F#5w | F#5q. F#5e B5q D6q | C#6h. B5e A5e | A5q. F#5e A5q D6q | C#6w | "
         "D6q. C#6e B5q G5q | C#6q. B5e A5q E5q | F#5w | F#5h. F#4t G#4t A#4t |")
ASC_MED_CH = "| D | D | Dm | Dm | Em | Em | D | A |"


def piece_ascent():
    T = me.Track("ascent", 128, 56, 4, layers=("base", "hi"))
    r = T.rng
    T.reverb("hall", me.make_ir(r, rt60=2.4, predelay=0.02, damp=5000, er=0.4))
    T.reverb("plate", me.make_ir(r, rt60=1.4, predelay=0.005, damp=7000, er=0.1))
    T.delay("echo", beats=0.75, fb=0.4, damp=4500, ret=0.45)
    T.bus("drums", eq=std_eq(30), drive=1.3)
    T.bus("bass", eq=lambda f: me.hp(f, 30) * me.lp(f, 3500), pump=0.4)
    T.bus("pads", eq=std_eq(120, 13000), pump=0.45, chorus=(2.0, 0.4, 10.0, 0.35))
    T.bus("arp", eq=std_eq(250, 13000), pump=0.2)
    T.bus("lead", eq=std_eq(150, 12000))
    T.bus("orch", eq=std_eq(50, 12000))
    T.bus("choir", eq=std_eq(120, 8500))
    PL = {"plate": 0.25}
    HL = {"hall": 0.35}
    kick = bank("kick_punch", lambda r: me.kick(r, "punch"), 2)
    snr = bank("snare_gated", lambda r: me.snare(r, "gated"), 3)
    hats = bank("hat_c", lambda r: me.hat(r, "closed"), 4)
    hato = bank("hat_o", lambda r: me.hat(r, "open"), 2)
    clp = bank("clap", lambda r: me.clap(r), 3)
    toms = [me.tom(me.rng_for("tom%d" % i), f, 1.0) for i, f in enumerate((82.0, 110.0, 147.0))]
    jA = tx_chords(JUMP_A_CHORDS, 2)
    jB = tx_chords(JUMP_B_CHORDS, 2)
    sections = [("intro", 0, ASC_INTRO_CH), ("A", 8, ASC_A_CH), ("med", 24, ASC_MED_CH), ("JA", 32, jA),
                ("JB", 40, jB), ("brk", 48, ASC_INTRO_CH)]
    for name, bar0, ch in sections:
        P = prog(ch, 4, bar0)
        nb = len(P)
        full = name not in ("intro", "brk")
        dr = {
            "kick": (kick, "x...x...x...x..." if full else ("x.......x......." if name == "intro" else "x..............."), 0.55),
            "snare": (snr, "....x.......x..." if full else "................", 0.5),
            "clap": (clp, "....x.......x..." if name in ("JA", "JB") else "................", 0.3),
            "hat": (hats, "..x...x...x...x." if not full else "gxgxgxgxgxgxgxgx", 0.18),
            "hato": (hato, "..............x." if full else "................", 0.12),
        }
        kit(T, "base", "drums", range(bar0, bar0 + nb), dr, sends=PL, pump=("kick",))
        bass(T, "base", "bass", P, [(k * 0.5, 0 if k % 2 == 0 else 12, 0.45, 0.9 if k % 2 == 0 else 0.7) for k in range(8)]
             if full else [(0, 0, 3.5, 0.8)], M_SBASS, lo=35, hi=47, gain=0.42, cutoff=1100.0 if full else 500.0, decay=0.1)
        pad(T, "base", "pads", P, I(me.supersaw, voices=5, detune=18.0, cutoff=2600.0 if full else 1200.0, att=0.05, rel=0.4,
            sub=0.0), center=64, count=4, gain=0.12, sends={"hall": 0.25}, vel=0.6)
        arp(T, "base", "arp", P, [0, 1, 2, 3, 4, 3, 2, 1] if name != "brk" else [0, 2, 4, 2], 0.25, M_SPLUCK, lo=62, hi=90,
            gain=0.11 if full else 0.13, sends={"echo": 0.3, "plate": 0.2}, vels=(0.8, 0.5, 0.6, 0.5),
            pan_fn=lambda k: 0.4 * np.sin(k * 0.9))
        # hi: orchestra
        if full:
            pad(T, "hi", "orch", P, I(me.strings, att=0.15, rel=0.4, bright=0.6, tremolo=0.3), center=66, count=4, gain=0.14,
                sends=HL, vel=0.8)
            pad(T, "hi", "choir", P, CHOIR_A, center=60, count=4, gain=0.14, sends={"hall": 0.45}, vel=0.75)
            bass(T, "hi", "orch", P, [(0, 0, 1.5, 0.9), (1.5, 0, 1.0, 0.7), (2.5, 0, 1.5, 0.8)], TROMBONES, lo=38, hi=50,
                 gain=0.14, sends=HL)
            for bar in range(bar0, bar0 + nb):
                if bar % 4 == 3:
                    for k, o in enumerate((2.0, 2.5, 3.0, 3.5)):
                        T.hit("hi", "orch", bar * 4 + o, toms[2 - k % 3], 0.3, (k - 1.5) * 0.3, HL)
        else:
            pad(T, "hi", "choir", P, CHOIR_O, center=60, count=3, gain=0.14, sends={"hall": 0.5}, vel=0.5)
    # the climb: synth lead (base) doubled by violins / horns (hi)
    line(T, "base", "lead", ASC_A, 8, SYNTH_LEAD, 0.3, {"echo": 0.2, "hall": 0.2})
    line(T, "hi", "orch", ASC_A, 8, I(me.strings, att=0.08, rel=0.3, bright=0.6, voices=5), 0.22, HL, transpose=-12)
    # medley: the gardens run-up, the foundry anvils, the clockwork music box, the reef vibes, the orbital horn
    line(T, "base", "lead", "A5e D6e F#6e A6e~ A6q F#6q | G6q. F#6e E6q D6q | r w | r w | r w | r w | r w | r w |", 24,
         FLUTE, 0.34, {"hall": 0.3, "echo": 0.2})
    line(T, "base", "lead", "r w | r w | D4q. D4e F4q A4q | Bb4h. A4e G4e | r w | r w | r w | r w |", 24, TROMBONES, 0.34,
         HL)
    anv = me.anvil(me.rng_for("asc_anv"), 1.0, 1.0, 0.8)
    for bar in (26, 27):
        for o in (1.5, 3.5):
            T.hit("base", "arp", bar * 4 + o, anv, 0.18, 0.3, {"hall": 0.3})
    line(T, "base", "lead", "r w | r w | r w | r w | B5q E6q D#6q E6q | F#6q G6h. | r w | r w |", 24, M_MUSICBOX, 0.32,
         {"hall": 0.3, "echo": 0.3}, legato=False)
    line(T, "base", "lead", "r w | r w | r w | r w | r w | r w | F#5q. A5e E6h | C#6h. A4t B4t C#5t |", 24, M_VIBES, 0.3,
         {"hall": 0.3, "echo": 0.3}, legato=False)
    line(T, "hi", "orch", "r w | r w | r w | r w | r w | r w | r w | E5h. A4t B4t C#5t |", 24, HORNS, 0.3, HL)
    # the summit: the JUMP theme in D, lead + trumpets + choir
    line(T, "base", "lead", JUMP_A + " |" + " " + JUMP_B.replace("D6h. G5t A5t B5t", "D6h. r q"), 32, SYNTH_LEAD, 0.32,
         {"echo": 0.2, "hall": 0.25}, transpose=2)
    line(T, "hi", "orch", JUMP_A, 32, TRUMPETS, 0.3, HL, transpose=2)
    line(T, "hi", "orch", JUMP_A, 32, HORNS, 0.26, HL, transpose=-10)
    line(T, "hi", "choir", JUMP_B.replace("D6h. G5t A5t B5t", "D6h. r q"), 40, CHOIR_A, 0.3, {"hall": 0.5}, transpose=-10)
    line(T, "hi", "orch", JUMP_B.replace("D6h. G5t A5t B5t", "D6h. r q"), 40, I(me.strings, att=0.1, rel=0.4, bright=0.6,
         voices=5), 0.26, HL, transpose=2)
    # breakdown: the lead floats the run-up, a riser pulls back into the intro
    line(T, "base", "lead", "r w | r h. F#5t G5t A5t | B5h F#6h | r w | r w | r h. F#5t G5t A5t | B5h F#6h | r w |", 48,
         M_SPLUCK, 0.3, {"echo": 0.5, "hall": 0.4}, legato=False)
    ring(T, "base", "arp", 52 * 4, me.riser(r, 16.0, T.spb, 0.8, 300.0, 8000.0), 0.12, 0.0, {"hall": 0.3})
    crash = bank("crash", lambda r: me.cymbal(r, "crash"), 2)
    for bar in (8, 24, 32, 40):
        ring(T, "base", "drums", bar * 4, crash[bar % 2], 0.2, 0.3, PL)
        ring(T, "hi", "orch", bar * 4, me.boom(me.rng_for("aboom"), 1.0, 36.0, 2.5), 0.26, 0.0, HL)
        ring(T, "hi", "orch", bar * 4, me.timpani(r, float(mtof(38)), 0.95), 0.3, 0.0, HL)
    T.render(rms_db=-14.0)


# --------------------------------------------------------------------------
# XENO WILDS - E lydian, 92 bpm, 48 bars. An alien jungle under a ringed giant: glass pads,
# a kalimba ostinato, alien chirps and bubbling percussion under a gliding theremin; chromatic
# mediant shifts (E - C - Ab) for the sense of wonder; the JUMP theme on kalimba and choir; a slow,
# huge "leviathan" passage. Hi layer: strings, horns, a tribal groove (taiko, frame drums,
# toms), a bright synth arp and a full choir.
# --------------------------------------------------------------------------
XENO_INTRO_CH = "| Emaj7 | F#/E | Emaj7 | F#/E | Cmaj7 | D | Emaj7 | F#/E |"
XENO_A_CH = ("| Emaj7 | F#/E | D#m7 | G#m7 | Cmaj7 | D | Bsus4 | B | "
             "Emaj7 | F#/E | C#m7 | Amaj7 | Cmaj7 | Ab | Bsus4 | B |")
XENO_A = ("B4h E5q F#5q | A#5w | G#5h F#5q D#5q | B5w | E5h G5q B5q | A5h F#5h | E5h. F#5q | D#5w | "
          "B4h E5q F#5q | A#5h C#6h | B5h. G#5q | C#6w | B5h G5q E5q | C6h Eb6h | E6h F#6h | D#6w |")
XENO_LEV_CH = "| C#m | A | E/G# | F# | C#m | A | C | B |"
XENO_LEV = "C#4w | E4h A3h | B3h. G#3q | F#3w | C#4w | E4h A4h | G4h E4h | F#4h D#4h |"
XENO_OUT_CH = "| Emaj7 | F#/E | Cmaj7 | D | Emaj7 | F#/E | Cmaj7 | Bsus4 B |"


def alien_chirp(r, vel=1.0):
    """A little FM creature call: a gliding carrier, a trilling amplitude, a quick fall-off."""
    dur = r.uniform(0.12, 0.35)
    n = int(dur * me.MSR)
    t = me.secs(n)
    f0 = r.uniform(1400.0, 3800.0)
    bend = r.uniform(-0.9, 0.9)
    f = f0 * 2.0 ** (bend * np.sin(np.pi * t / dur))
    ph = me.TAU * np.cumsum(f) / me.MSR
    idx = r.uniform(0.5, 2.5) * np.exp(-t / (dur * 0.5))
    x = np.sin(ph + idx * np.sin(ph * r.choice([0.5, 1.5, 2.01])))
    x *= 0.6 + 0.4 * np.sin(me.TAU * r.uniform(22.0, 45.0) * t)
    x *= np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 0.7
    return me._pk(x, vel)


def piece_xeno():
    T = me.Track("xeno", 92, 48, 4, layers=("base", "hi"))
    r = T.rng
    T.reverb("jungle", me.make_ir(r, rt60=3.2, predelay=0.04, damp=4200, er=0.35))
    T.reverb("canyon", me.make_ir(r, rt60=5.0, predelay=0.08, damp=2600, er=0.2, tone=lambda f: me.lp(f, 5000, 1)))
    T.delay("echo", beats=0.75, fb=0.42, damp=3800, ret=0.5)
    T.bus("pad", eq=std_eq(70, 11000), chorus=(4.0, 0.22, 14.0, 0.5))
    T.bus("keys", eq=std_eq(120, 12000))
    T.bus("lead", eq=std_eq(180, 11000))
    T.bus("perc", eq=std_eq(120))
    T.bus("bass", eq=std_eq(28, 2500))
    T.bus("choir", eq=std_eq(100, 8000))
    T.bus("strings", eq=std_eq(50, 12000))
    T.bus("brass", eq=std_eq(60, 9000))
    T.bus("drums", eq=std_eq(30), drive=1.2)
    J = {"jungle": 0.4}
    intro = prog(XENO_INTRO_CH, 4, 0)
    a = prog(XENO_A_CH, 4, 8)
    jmp = prog(tx_chords(JUMP_A_CHORDS, 4), 4, 24)
    lev = prog(XENO_LEV_CH, 4, 32)
    out = prog(XENO_OUT_CH, 4, 40)
    allp = intro + a + jmp + lev + out
    # base: glass pads, a hushed "oo" choir, the kalimba ostinato, sub drone
    pad(T, "base", "pad", allp, I(me.pad_glass, att=1.4, rel=2.4), center=66, count=4, gain=0.07, sends=J, vel=0.5)
    pad(T, "base", "choir", allp, I(me.choir, vowel="u", att=1.0, rel=1.8), center=57, count=3, gain=0.1,
        sends={"canyon": 0.5}, vel=0.45)
    arp(T, "base", "keys", intro + a + jmp + out, [0, 2, 4, 1, 3, 5, 2, 4], 0.5, M_KALIMBA, lo=59, hi=86, gain=0.16,
        sends={"jungle": 0.35, "echo": 0.3}, vels=(0.8, 0.5, 0.6, 0.5), pan_fn=lambda k: 0.45 * np.sin(k * 0.8))
    bass(T, "base", "bass", allp, [(0, 0, 3.6, 0.8)], M_SUB, lo=28, hi=40, gain=0.34, drive=1.1)
    # alien wildlife: chirps and trills scattered through every bar, bubbling acid pops
    chirps = [alien_chirp(me.rng_for("chirp%d" % i)) for i in range(10)]
    bubbles = [me.bubble(me.rng_for("xbub%d" % i), 1.0, f) for i, f in enumerate((380, 520, 700, 900, 1150))]
    for bar in range(48):
        for _ in range(2 if bar < 32 or bar >= 40 else 1):
            T.hit("base", "perc", bar * 4 + int(r.integers(0, 16)) * 0.25, chirps[int(r.integers(0, 10))],
                  0.05 * r.uniform(0.4, 1.0), r.uniform(-0.9, 0.9), {"jungle": 0.6, "echo": 0.3})
        for _ in range(2):
            T.hit("base", "perc", bar * 4 + int(r.integers(0, 8)) * 0.5, bubbles[int(r.integers(0, 5))],
                  0.05 * r.uniform(0.5, 1.0), r.uniform(-0.7, 0.7), {"jungle": 0.4})
    frame = bank("frame", lambda r: me.frame_drum(r, 1.0, True), 3)
    frame_hi = bank("frame_hi", lambda r: me.frame_drum(r, 1.0, False), 3)
    kit(T, "base", "perc", range(8, 32), {"fr": (frame, "x.....x...x.....", 0.3),
                                          "frh": (frame_hi, "...g.......g..g.", 0.18)}, sends=J)
    # the theremin sings the Xeno theme; fm bells shimmer on its long notes
    line(T, "base", "lead", "r w | r w | r w | B4h. E5q | A#5w | G#5h. r q | r w | r w |", 0, I(me.theremin), 0.36,
         {"jungle": 0.45, "echo": 0.25})
    line(T, "base", "lead", XENO_A, 8, I(me.theremin), 0.4, {"jungle": 0.4, "echo": 0.2})
    for bar in (9, 11, 15, 19, 23):
        T.add("base", "keys", bar * 4, me.fm_bell(r, float(mtof(88 if bar % 2 else 83)), 3.0, 0.5), 0.12,
              r.uniform(-0.5, 0.5), {"canyon": 0.6, "echo": 0.4}, 0.0)
    # the JUMP theme: kalimba and celesta (base), horns + choir (hi)
    line(T, "base", "keys", JUMP_PICKUP + " | " + JUMP_A, 24, M_CELESTA, 0.32, {"jungle": 0.4, "echo": 0.3},
         legato=False, pickup=1.0, transpose=4)
    line(T, "base", "lead", JUMP_PICKUP + " | " + JUMP_A, 24, I(me.theremin, vib=0.008), 0.24, J, pickup=1.0, transpose=-8)
    line(T, "hi", "brass", JUMP_PICKUP + " | " + JUMP_A, 24, HORNS, 0.34, {"jungle": 0.45}, pickup=1.0, transpose=-8)
    pad(T, "hi", "choir", jmp, CHOIR_A, center=62, count=4, gain=0.16, sends={"canyon": 0.5}, vel=0.7)
    # the leviathan: vast and slow - low strings / choir melody, a deep whale-like glide
    line(T, "base", "strings", XENO_LEV, 32, I(me.strings, att=0.6, rel=1.0, bright=0.3, voices=5, body="cello"), 0.3,
         {"canyon": 0.6})
    line(T, "base", "choir", XENO_LEV, 32, CHOIR_O, 0.2, {"canyon": 0.6}, transpose=12)
    for bar, f0, f1 in ((33, 40, 47), (35, 45, 38), (37, 40, 49), (39, 47, 42)):
        n = int(3.4 * T.spb * me.MSR)
        tt = me.secs(n)
        u = np.clip(tt / (3.2 * T.spb), 0, 1)
        fcurve = float(mtof(f0)) * (float(mtof(f1)) / float(mtof(f0))) ** (u * u * (3 - 2 * u))
        wh = np.sin(me.TAU * np.cumsum(fcurve * (1 + 0.006 * np.sin(me.TAU * 3.5 * tt))) / me.MSR)
        wh += 0.4 * np.sin(2 * me.TAU * np.cumsum(fcurve) / me.MSR) + 0.2 * np.sin(3 * me.TAU * np.cumsum(fcurve) / me.MSR)
        wh *= me.env_asr(n, 2.8 * T.spb, 0.8, 0.8) * 0.3
        T.add("base", "lead", bar * 4 + 0.5, wh, 0.2, -0.3 if bar % 4 == 1 else 0.3, {"canyon": 0.8, "echo": 0.3}, 0.0)
    for bar in (32, 36):
        ring(T, "base", "perc", bar * 4, me.gong(me.rng_for("xgong"), 1.0, 5.0, 62.0), 0.16, 0.0, {"canyon": 0.5})
        ring(T, "base", "bass", bar * 4, me.boom(me.rng_for("xboom"), 1.0, 31.0, 3.0), 0.2, 0.0, {"canyon": 0.3})
    # hi: strings, a counter-line, a tribal groove, a bright arp
    pad(T, "hi", "strings", a + jmp + lev, I(me.strings, att=0.3, rel=0.7, bright=0.5), center=64, count=4, gain=0.13,
        sends=J, vel=0.65)
    line(T, "hi", "strings", "E5w | F#5w | D#5w | D#5w | E5w | F#5w | F#5w | F#5w | G#5w | A#5w | G#5w | A5w | "
         "G5w | Ab5w | F#5w | F#5w |", 8, VIOLINS, 0.18, J, pan=-0.3)
    line(T, "hi", "brass", XENO_LEV, 32, TROMBONES, 0.24, {"canyon": 0.5})
    nagado = bank("nagado", lambda r: me.taiko(r, "nagado"), 3)
    ka = bank("ka", lambda r: me.taiko(r, "ka"), 4)
    toms = [me.tom(me.rng_for("xtom%d" % i), f, 1.0) for i, f in enumerate((90.0, 120.0, 160.0))]
    for bar0, nb in ((8, 16), (24, 8), (32, 8)):
        kit(T, "hi", "drums", range(bar0, bar0 + nb), {
            "na": (nagado, "x.....x.x.....x." if bar0 != 32 else "x...............", 0.5),
            "ka": (ka, "..g.g...g.x.g.g." if bar0 != 32 else "................", 0.2),
            "shk": (SHK, "g.g.g.g.g.g.g.g.", 0.14),
        }, sends=J)
        for bar in range(bar0, bar0 + nb):
            if bar % 4 == 3:
                for k, o in enumerate((2.5, 3.0, 3.5)):
                    T.hit("hi", "drums", bar * 4 + o, toms[2 - k], 0.26, (k - 1) * 0.4, J)
    arp(T, "hi", "keys", a + jmp, [0, 1, 2, 3, 4, 3, 2, 1], 0.25, M_SPLUCK, lo=64, hi=91, gain=0.07,
        sends={"echo": 0.35, "jungle": 0.3}, vels=(0.8, 0.5, 0.6, 0.5))
    for bar in (8, 24, 32):
        swell_into(T, "hi", "drums", bar, 4, 0.16, J)
    T.render(rms_db=-14.5, hi_gain=0.62)


# --------------------------------------------------------------------------
# CINDER PEAK - C minor in 7/8 (2+2+3), 160 bpm, 64 bars. The mountain is erupting: a lopsided
# low-string ostinato and a growling lava bass, war drums, a brass theme climbing through the
# Neapolitan Db; the JUMP theme bursts into C major as the eruption; a chanting breakdown.
# Hi layer: the full storm - choir chants, trumpets, taiko and toms, timpani, tremolo strings,
# gongs and crashes.
# --------------------------------------------------------------------------
VOL_INTRO_CH = "| Cm | Cm | Db | Cm | Cm | Cm | Ab | G |"
VOL_A_CH = "| Cm | Cm | Ab | Ab | Fm | Fm | G | G | Cm | Cm | Db | Db | Bbm | Bbm | G | G7 |"
VOL_A = ("C4q Eb4q G4q. | C5q Bb4q G4q. | Ab4q G4q Eb4q. | C5q. Bb4q Ab4q | F4q Ab4q C5q. | F5q Eb5q C5q. | "
         "D5q B4q G4q. | B4q. C5q D5q | Eb5q D5q C5q. | G5q F5q Eb5q. | F5q Eb5q Db5q. | Ab5q. G5q F5q | "
         "Db5q F5q Bb5q. | Ab5q F5q Db5q. | B4q D5q G5q. | F5q. D5q B4q |")
VOL_J_CH = "| C | F | Dm | G | C | Ab | Bb | C |"
VOL_J = ("G4e A4e B4e | C5q. G5h | A5q G5e E5e C5q. | D5q E5e F5e A5q. | G5h G4e A4e B4e | C5q. G5h | "
         "C6q Bb5e Ab5e C6q. | D6q C6e Bb5e D6q. | E6h. r e |")
VOL_BRK_CH = "| Cm | Cm | Cm | Cm | Db | Db | G | G |"


def piece_volcano():
    T = me.Track("volcano", 160, 64, 3.5, layers=("base", "hi"))
    r = T.rng
    T.reverb("caldera", me.make_ir(r, rt60=2.6, predelay=0.03, damp=3200, er=0.7, er_span=0.1))
    T.reverb("sky", me.make_ir(r, rt60=4.0, predelay=0.05, damp=2400, er=0.2))
    T.bus("low", eq=lambda f: me.hp(f, 30) * me.lp(f, 5000) * me.bump(f, 280, -2, 0.8))
    T.bus("lava", eq=lambda f: me.hp(f, 28) * me.lp(f, 1800), drive=1.6)
    T.bus("brass", eq=std_eq(60, 9500), drive=1.1)
    T.bus("choir", eq=std_eq(100, 8500))
    T.bus("strings", eq=std_eq(60, 12000))
    T.bus("drums", eq=std_eq(28), drive=1.35)
    T.bus("fx", eq=std_eq(40))
    C = {"caldera": 0.3}
    sections = [("intro", 0, VOL_INTRO_CH), ("A", 8, VOL_A_CH), ("J", 24, VOL_J_CH), ("brk", 32, VOL_BRK_CH),
                ("A2", 40, VOL_A_CH), ("out", 56, VOL_INTRO_CH)]
    kick = bank("kick_orch", lambda r: me.kick(r, "orch"), 2)
    odaiko = bank("odaiko", lambda r: me.taiko(r, "odaiko"), 3)
    nagado = bank("nagado", lambda r: me.taiko(r, "nagado"), 3)
    shime = bank("shime", lambda r: me.taiko(r, "shime"), 4)
    snr = bank("snare_march", lambda r: me.snare(r, "march"), 4)
    toms = [me.tom(me.rng_for("vtom%d" % i), f, 1.0) for i, f in enumerate((70.0, 95.0, 130.0))]
    osti = [(0.0, 0, 0.5, 1.0), (0.5, 0, 0.5, 0.55), (1.0, 12, 0.5, 0.95), (1.5, 0, 0.5, 0.55), (2.0, 0, 0.5, 1.0),
            (2.5, 7, 0.5, 0.6), (3.0, 12, 0.5, 0.75)]
    for name, bar0, ch in sections:
        P = prog(ch, 3.5, bar0)
        nb = len(P)
        calm = name in ("intro", "out")
        # the 7/8 ostinato: marcato low strings (2+2+3), the lava bass on each group
        if name != "brk":
            bass(T, "base", "low", P, osti, M_CELLO_STAC, lo=36, hi=48, gain=0.36 if not calm else 0.28, sends={"caldera": 0.15},
                 period=3.5)
            bass(T, "base", "lava", P, [(0.0, 0, 0.95, 0.9), (1.0, 0, 0.95, 0.7), (2.0, 0, 1.45, 0.85)], M_SBASS, lo=24, hi=36,
                 gain=0.3, period=3.5, cutoff=420.0, decay=0.14, drive=2.2)
        else:
            bass(T, "base", "lava", P, [(0.0, 0, 3.4, 0.8)], M_SUB, lo=24, hi=36, gain=0.3, period=3.5, drive=1.8)
        kit(T, "base", "drums", range(bar0, bar0 + nb), {
            "kick": (kick, "x.x.x.." if not calm else "x......", 0.55),
            "od": (odaiko, "x...x.." if name not in ("intro",) else "x......", 0.4),
            "tom": ([toms[0]], "......x" if name != "out" else ".......", 0.25),
        }, step=0.5, sends={"caldera": 0.25})
        pad(T, "base", "choir", P, I(me.choir, vowel="o", att=0.8, rel=1.2), center=55, count=3, gain=0.1 if calm else 0.08,
            sends={"sky": 0.5}, vel=0.5)
        # hi: the storm
        if not calm:
            kit(T, "hi", "drums", range(bar0, bar0 + nb), {
                "na": (nagado, "x.xgx.g" if name != "brk" else "x.x.x..", 0.5),
                "snare": (snr, "..x...x" if name in ("A", "A2", "J") else ".......", 0.3),
            }, step=0.5, sends={"caldera": 0.3})
            kit(T, "hi", "drums", range(bar0, bar0 + nb), {
                "shime": (shime, "xgxgxgxgxgxgxx" if name != "brk" else "x.x.x.x.x.x.x.", 0.16),
            }, step=0.25, sends={"caldera": 0.3})
            pad(T, "hi", "strings", P, I(me.strings, att=0.08, rel=0.3, bright=0.55, tremolo=0.6), center=67, count=3,
                gain=0.12, sends=C, vel=0.75)
            for bar in range(bar0, bar0 + nb):
                if bar % 4 == 3:
                    for k, o in enumerate((2.0, 2.5, 3.0)):
                        T.hit("hi", "drums", bar * 3.5 + o, toms[2 - k], 0.3, (k - 1) * 0.4, C)
    # the theme: trombones + horns (base), trumpets an octave up the second time (hi)
    line(T, "base", "brass", VOL_A, 8, TROMBONES, 0.4, {"caldera": 0.35})
    line(T, "base", "brass", VOL_A, 8, HORNS, 0.22, {"caldera": 0.4}, transpose=12)
    line(T, "base", "brass", VOL_A, 40, TROMBONES, 0.38, {"caldera": 0.35})
    line(T, "hi", "brass", VOL_A, 40, TRUMPETS, 0.26, {"caldera": 0.4}, transpose=12)
    line(T, "hi", "choir", VOL_A, 8, CHOIR_A, 0.22, {"sky": 0.5})
    # the eruption: the JUMP theme in C major, horns and trumpets, the choir wide open
    line(T, "base", "brass", VOL_J, 24, HORNS, 0.42, {"caldera": 0.4}, pickup=1.5)
    line(T, "hi", "brass", VOL_J, 24, TRUMPETS, 0.3, {"caldera": 0.4}, pickup=1.5)
    pad(T, "hi", "choir", prog(VOL_J_CH, 3.5, 24), CHOIR_A, center=62, count=4, gain=0.2, sends={"sky": 0.5}, vel=0.85)
    pad(T, "base", "strings", prog(VOL_J_CH, 3.5, 24), I(me.strings, att=0.1, rel=0.4, bright=0.6, tremolo=0.4),
        center=67, count=4, gain=0.14, sends=C, vel=0.8)
    # breakdown: the choir chants on the 2+2+3 accents, a timpani roll and a riser build back
    for bar in range(32, 40):
        m = 48 if bar < 36 else (49 if bar < 38 else 43)
        for o in (0.0, 1.0, 2.0):
            T.add("hi", "choir", bar * 3.5 + o, me.choir(r, float(mtof(m)), 0.3 * T.spb, 0.85, "a", voices=5, att=0.02,
                  rel=0.25, male=True), 0.22, 0.0, {"sky": 0.4})
            T.add("base", "choir", bar * 3.5 + o, me.choir(r, float(mtof(m + 12)), 0.25 * T.spb, 0.6, "o", voices=4, att=0.02,
                  rel=0.2), 0.12, 0.0, {"sky": 0.4})
    ring(T, "base", "drums", 36 * 3.5, me.timpani_roll(r, float(mtof(43)), 14.0, T.spb, 0.15, 1.0), 0.34, 0.0, C)
    ring(T, "hi", "fx", 36 * 3.5, me.riser(r, 14.0, T.spb, 0.8, 150.0, 6000.0), 0.18, 0.0, C)
    # eruptions: gong + boom + crash at the big downbeats, distant rumbles in the intro
    gong = me.gong(me.rng_for("vgong"), 1.0, 6.0, 55.0)
    crash = bank("crash", lambda r: me.cymbal(r, "crash"), 2)
    for bar in (0, 8, 24, 40, 56):
        ring(T, "base", "fx", bar * 3.5, me.boom(me.rng_for("vboom%d" % bar), 1.0, 30.0, 3.0), 0.3, 0.0, {"sky": 0.3})
        ring(T, "hi", "fx", bar * 3.5, gong, 0.2, 0.0, {"sky": 0.4})
        if bar in (8, 24, 40):
            ring(T, "hi", "drums", bar * 3.5, crash[bar % 2], 0.2, 0.3, C)
            swell_into(T, "hi", "fx", bar, 3.5, 0.14, C)
    for bar in (2, 5, 58, 61):
        ring(T, "base", "fx", bar * 3.5 + 1.0, me.boom(me.rng_for("vrumble%d" % bar), 0.7, 26.0, 2.5), 0.16, 0.0, {"sky": 0.5})
    T.render(rms_db=-14.5, hi_gain=1.1)


def _ff_xeno(B, r, k):
    B.notes(mel("B4e C#5e D#5e E5q B5q E6h", 4, 0, 0), I(me.theremin), r, 0.4, sends={"hall": 0.5}, legato=True)
    for m in (52, 59, 63, 66, 70):
        B.add(1.5, me.choir(r, float(mtof(m)), 2.6, 0.8, "a", att=0.3, rel=1.2), 0.16, sends={"hall": 0.5})
    for i, m in enumerate((76, 80, 83, 87, 90, 94)):
        B.add(1.5 + 0.09 * i, me.fm_bell(r, float(mtof(m)), 1.6, 0.6), 0.12, (i / 5 - 0.5), {"hall": 0.5})
    for i, m in enumerate((64, 68, 71, 75, 76)):
        B.add(1.5 + 0.06 * i, me.mallet(r, float(mtof(m)), 1.0, 0.7, "kalimba"), 0.18, 0.3, {"hall": 0.4})
    B.add(1.5, me.gong(r, 0.8, 4.0, 82.0), 0.18, sends={"hall": 0.4})
    B.add(1.5, me.taiko(r, "nagado"), 0.35, sends={"hall": 0.3})


def _ff_volcano(B, r, k):
    B.notes(mel("G4e A4e B4e C5q. G5q C6h", 3.5, 0, 0), I(me.brass, kind="trumpet", voices=2), r, 0.42, sends={"hall": 0.4})
    for m in (48, 55, 60, 64, 67, 72):
        B.add(3.0, me.brass(r, float(mtof(m)), 2.6, 0.95, "horn" if m < 62 else "trumpet", voices=2), 0.15, sends={"hall": 0.4})
    for m in (48, 55, 60, 64):
        B.add(3.0, me.choir(r, float(mtof(m)), 2.6, 0.9, "a", att=0.1, rel=1.0), 0.16, sends={"hall": 0.5})
    for t0 in (0.0, 1.0, 2.0, 3.0):
        B.add(t0, me.taiko(r, "odaiko"), 0.45, sends={"hall": 0.3})
    B.add(3.0, me.boom(r, 1.0, 32.0, 3.0), 0.45)
    B.add(3.0, me.gong(r, 1.0, 4.0, 55.0), 0.3, sends={"hall": 0.3})
    B.add(3.0, me.cymbal(r, "crash"), 0.22, 0.3, {"hall": 0.3})


# --------------------------------------------------------------------------
# FROSTBITE PASS - F# minor, 84 bpm, 40 bars. Cold and epic: glass-harmonica pads, celesta and
# harp frost, a lonely high piano and a low male choir under a horn / flute theme; a lyrical B
# phrase on violins; the JUMP theme in A major over F - G - A. Hi layer: a driving string
# ostinato, heroic horns, a field drum, timpani, choir and cymbals.
# --------------------------------------------------------------------------
GLA_INTRO_CH = "| F#m | D | Bm | C#sus4 C# |"
GLA_A_CH = "| F#m | D | A | E | F#m | D | Bm | C#sus4 C# |"
GLA_A = "C#5h. F#5q | A5h. F#5q | E5q. F#5e E5q C#5q | B4w | C#5h. F#5q | A5h B5q C#6q | D6q. C#6e B5q F#5q | F#5h E#5h |"
GLA_B_CH = "| D | E | C#m | F#m | Bm | D | Esus4 | E |"
GLA_B = "F#5q A5q D6q C#6q | B5h. G#5q | E5q G#5q C#6q B5q | A5w | D5q F#5q B5q A5q | F#5h. D5q | E5q A5q B5q A5q | G#5w |"
GLA_OUT_CH = "| F#m | D | Bm | C#sus4 C# |"


def piece_glacier():
    T = me.Track("glacier", 84, 40, 4, layers=("base", "hi"))
    r = T.rng
    T.reverb("ice", me.make_ir(r, rt60=3.6, predelay=0.03, damp=6500, er=0.5, tone=lambda f: me.shelf(f, 3000, 2.0)))
    T.reverb("peak", me.make_ir(r, rt60=5.5, predelay=0.07, damp=4000, er=0.15))
    T.delay("echo", beats=0.75, fb=0.4, damp=5000, ret=0.45)
    T.bus("pad", eq=std_eq(80, 13000), chorus=(3.0, 0.2, 13.0, 0.45))
    T.bus("keys", eq=std_eq(150, 14000))
    T.bus("lead", eq=std_eq(120, 11000))
    T.bus("strings", eq=std_eq(45, 13000))
    T.bus("brass", eq=std_eq(60, 9000))
    T.bus("choir", eq=std_eq(80, 8000))
    T.bus("drums", eq=std_eq(30), drive=1.15)
    T.bus("bass", eq=std_eq(28, 3000))
    IC = {"ice": 0.4}
    intro = prog(GLA_INTRO_CH, 4, 0)
    a1 = prog(GLA_A_CH, 4, 4)
    a2 = prog(GLA_A_CH, 4, 12)
    bb = prog(GLA_B_CH, 4, 20)
    jmp = prog(tx_chords(JUMP_A_CHORDS, 9), 4, 28)
    out = prog(GLA_OUT_CH, 4, 36)
    allp = intro + a1 + a2 + bb + jmp + out
    # base: glass pads, a male choir, harp frost, celesta, a lonely high piano
    pad(T, "base", "pad", allp, I(me.pad_glass, att=1.6, rel=2.6), center=70, count=4, gain=0.08, sends=IC, vel=0.5)
    pad(T, "base", "choir", allp, I(me.choir, vowel="o", att=1.2, rel=2.0, male=True), center=50, count=3, gain=0.12,
        sends={"peak": 0.5}, vel=0.5)
    bass(T, "base", "bass", allp, [(0, 0, 3.8, 0.7)], I(me.strings, att=0.6, rel=0.8, voices=4, body="bass", bright=0.3),
         lo=30, hi=42, gain=0.3, sends={"peak": 0.2})
    arp(T, "base", "keys", allp, [0, 2, 4, 6, 5, 3, 1, 3], 0.5, M_HARP, lo=54, hi=90, gain=0.14,
        sends={"ice": 0.45, "echo": 0.25}, vels=(0.7, 0.45, 0.55, 0.45))
    arp(T, "base", "keys", a1 + a2 + bb, [4, 6, 5, 7], 2.0, M_CELESTA, lo=76, hi=98, gain=0.12,
        sends={"ice": 0.5, "echo": 0.4}, vels=(0.6, 0.45, 0.5, 0.45))
    line(T, "base", "keys", "r h C#6q F#6q | A6w | r h B5q E6q | G#6w |", 0, me.memo(me.piano, 2), 0.28,
         {"ice": 0.5, "echo": 0.3}, legato=False)
    line(T, "base", "keys", "r h C#6q F#6q | A6w | r h B5q E6q | G#6h F6h |", 36, me.memo(me.piano, 2), 0.26,
         {"ice": 0.5, "echo": 0.3}, legato=False)
    # the theme: flute first, then horns; violins sing the B phrase
    line(T, "base", "lead", GLA_A, 4, FLUTE, 0.38, {"ice": 0.4, "echo": 0.15})
    line(T, "base", "brass", GLA_A, 12, HORNS, 0.4, {"ice": 0.45}, transpose=-12)
    line(T, "base", "strings", GLA_B, 20, I(me.strings, att=0.15, rel=0.5, bright=0.6, voices=5), 0.34, IC, pan=-0.2)
    line(T, "base", "strings", "D4w | E4w | C#4h E4h | F#4w | B3w | D4h F#4h | E4w | E4w |", 20, CELLOS, 0.24, IC, pan=0.3)
    # the JUMP theme in A major: celesta + flute (base), horns + choir (hi)
    line(T, "base", "keys", JUMP_PICKUP + " | " + JUMP_A, 28, M_CELESTA, 0.3, {"ice": 0.45, "echo": 0.3}, legato=False,
         pickup=1.0, transpose=-3)
    line(T, "base", "lead", JUMP_PICKUP + " | " + JUMP_A, 28, FLUTE, 0.3, IC, pickup=1.0, transpose=-3)
    line(T, "hi", "brass", JUMP_PICKUP + " | " + JUMP_A, 28, HORNS, 0.34, {"ice": 0.45}, pickup=1.0, transpose=-15)
    pad(T, "hi", "choir", jmp, CHOIR_A, center=62, count=4, gain=0.16, sends={"peak": 0.5}, vel=0.75)
    # hi: the driving string ostinato, trumpets doubling, a field drum, timpani and cymbals
    bass(T, "hi", "strings", a1 + a2 + bb + jmp, [(k * 0.5, [0, 12, 7, 12][k % 4], 0.5, 0.9 if k % 2 == 0 else 0.6)
                                                 for k in range(8)], M_CELLO_STAC, lo=42, hi=54, gain=0.2, sends=IC)
    pad(T, "hi", "strings", a2 + bb + jmp, I(me.strings, att=0.2, rel=0.5, bright=0.55, tremolo=0.3), center=69, count=3,
        gain=0.12, sends=IC, vel=0.7)
    line(T, "hi", "brass", GLA_A, 12, TRUMPETS, 0.2, IC)
    snr = bank("snare_march", lambda r: me.snare(r, "march"), 4)
    for bar0, nb in ((4, 8), (12, 8), (20, 8), (28, 8)):
        kit(T, "hi", "drums", range(bar0, bar0 + nb), {
            "snare": (snr, "x..g..x.x.g.x..g" if bar0 != 20 else "x.......x.......", 0.2),
            "kick": (bank("kick_orch", lambda r: me.kick(r, "orch"), 2), "x.......x.......", 0.35),
        }, sends=IC)
    crash = bank("crash", lambda r: me.cymbal(r, "crash"), 2)
    for bar in (4, 12, 20, 28):
        ring(T, "hi", "drums", bar * 4, me.timpani(r, float(mtof(42 if bar != 28 else 45)), 0.9), 0.32, 0.0, IC)
        ring(T, "hi", "drums", bar * 4, crash[bar % 2], 0.14, 0.3, IC)
        swell_into(T, "base", "drums", bar, 4, 0.14, {"peak": 0.4})
    tri = bank("triangle", lambda r: me.triangle(r, 1.0, 1.6), 2)
    kit(T, "base", "keys", range(4, 36), {"tri": (tri, "x...............", 0.05)}, sends={"ice": 0.5})
    T.render(rms_db=-14.5, hi_gain=1.0)


# --------------------------------------------------------------------------
# SCARAB SANDS - D phrygian dominant, 104 bpm, 40 bars. A sun temple: a low drone, a darbuka groove
# (doum - tek - tek), riq and finger cymbals under an oud-and-strings unison riff and a sliding
# ney-like flute; the JUMP theme bent into the exotic scale (its run-up becomes A - Bb - C#).
# Hi layer: deep temple drums, brass, a choir and full strings.
# --------------------------------------------------------------------------
DES_CH = "| D | Eb | D | Cm | D | Eb | Gm | D |"
DES_RIFF = "D4e Eb4e F#4e G4e A4q Bb4e A4e | G4e F#4e Eb4e F#4e D4h |"
DES_A = ("A5h Bb5e A5e G5e F#5e | G5h F#5e Eb5e D5q | D5q F#5q A5q C6q | Bb5h. A5q | A5q. G5e F#5q Eb5q | "
         "Bb5h. G5q | A5q Bb5q G5q Eb5q | D5w |")
DES_J_CH = "| D | Gm | Cm | D | D | Bb | C | D |"
DES_J = ("A4t Bb4t C#5t | D5h A5h | Bb5q. A5e F#5q D5q | Eb5q. F#5e G5q Bb5q | A5h. A4t Bb4t C#5t | D5h A5h | "
         "D6q. C6e Bb5q D6q | C6q. Bb5e A5q C6q | D6w |")


def piece_desert():
    T = me.Track("desert", 104, 40, 4, layers=("base", "hi"))
    r = T.rng
    T.reverb("temple", me.make_ir(r, rt60=2.4, predelay=0.02, damp=4500, er=0.8, er_span=0.07))
    T.reverb("dunes", me.make_ir(r, rt60=3.2, predelay=0.05, damp=3500, er=0.2))
    T.delay("echo", beats=0.75, fb=0.35, damp=3500, ret=0.4)
    T.bus("riff", eq=lambda f: me.hp(f, 70) * me.bump(f, 2500, 2, 0.8))
    T.bus("lead", eq=std_eq(200, 11000))
    T.bus("perc", eq=std_eq(60), drive=1.1)
    T.bus("drone", eq=std_eq(28, 4000))
    T.bus("strings", eq=std_eq(50, 12000))
    T.bus("brass", eq=std_eq(60, 9000))
    T.bus("choir", eq=std_eq(100, 8000))
    T.bus("drums", eq=std_eq(28), drive=1.3)
    TP = {"temple": 0.3}
    doum = [me.frame_drum(me.rng_for("doum%d" % i), 1.0, True) for i in range(3)]
    tek = [me.cajon(me.rng_for("tek%d" % i), 1.0, True) for i in range(3)]
    ka = bank("ka", lambda r: me.taiko(r, "ka"), 4)
    riq = [me.tambourine(me.rng_for("riq%d" % i), 1.0, i % 2 == 1) for i in range(4)]
    zill = [me.triangle(me.rng_for("zill%d" % i), 1.0, 0.8) for i in range(2)]
    sections = [("intro", 0, 4), ("riff", 4, 8), ("melody", 12, 8), ("jump", 20, 8), ("break", 28, 4), ("both", 32, 8)]
    for name, bar0, nb in sections:
        ch = DES_CH if name != "jump" else DES_J_CH
        P = prog(ch, 4, bar0)[:nb]
        # the drone: a low D (with its fifth) under everything, a bowed cello swell
        bass(T, "base", "drone", P, [(0, 0, 3.9, 0.8)], M_SUB, lo=26, hi=38, gain=0.3, drive=1.2)
        if name != "break":
            pad(T, "base", "strings", P, I(me.strings, att=0.8, rel=1.0, bright=0.35, body="cello", voices=4), center=50,
                count=2, gain=0.12, sends=TP, vel=0.55)
        # darbuka maqsum: doum . tek tek . doum tek . (per half bar) + riq shakes + finger cymbals
        kit(T, "base", "perc", range(bar0, bar0 + nb), {
            "doum": (doum, "x.....x.x.......", 0.5),
            "tek": (tek, "..x.x.....x.x.x." if name != "intro" else "..x.......x.....", 0.3),
            "ka": (ka, ".g.g.g.g.g.g.g.g" if name not in ("intro",) else "................", 0.1),
            "riq": (riq, "x...x...x...x..." if name not in ("intro", "break") else "................", 0.12),
        }, sends=TP)
        kit(T, "base", "perc", range(bar0, bar0 + nb), {"zill": (zill, "x.......", 0.05)}, step=0.5, sends={"temple": 0.5})
        # hi: temple drums and full strings
        if name not in ("intro",):
            kit(T, "hi", "drums", range(bar0, bar0 + nb), {
                "od": (bank("odaiko", lambda r: me.taiko(r, "odaiko"), 3), "x.....x.x.....x." if name != "break" else "x.x.x.x.x.x.xxxx", 0.45),
                "na": (bank("nagado", lambda r: me.taiko(r, "nagado"), 3), "....x.......x..." if name != "break" else "................", 0.3),
            }, sends=TP)
    # the riff: oud (steel-string pluck) + strings in unison, doubled an octave down by cellos
    for bar0, nb in ((4, 8), (32, 8), (0, 4)):
        for k in range(0, nb, 2):
            line(T, "base", "riff", DES_RIFF, bar0 + k, M_GUITAR_STEEL, 0.34 if bar0 else 0.26, TP, legato=False)
            if bar0:
                line(T, "base", "riff", DES_RIFF, bar0 + k, M_VLN_STAC, 0.14, TP, legato=False, transpose=12)
                line(T, "hi", "strings", DES_RIFF, bar0 + k, M_CELLO_STAC, 0.2, TP, legato=False, transpose=-12)
    # the ney: a breathy, sliding flute melody (panflute breath, legato glides)
    ney = I(me.woodwind, kind="panflute", vib=0.006)
    line(T, "base", "lead", DES_A, 12, ney, 0.4, {"temple": 0.35, "echo": 0.2})
    line(T, "base", "lead", DES_A, 32, ney, 0.36, {"temple": 0.35, "echo": 0.2})
    line(T, "hi", "strings", DES_A, 12, I(me.strings, att=0.1, rel=0.4, bright=0.6, voices=5), 0.22, TP, transpose=-12)
    # qanun-like harp trills at phrase ends
    for bar in (15, 19, 35, 39):
        for i, m in enumerate((74, 75, 74, 75, 74, 75, 78, 81)):
            T.add("base", "lead", bar * 4 + 2 + i * 0.25, me.harp(r, float(mtof(m)), 0.4, 0.55), 0.12, 0.3, TP, 0.0)
    # the JUMP theme, bent into the scale: brass + ney (base), trumpets + choir (hi)
    line(T, "base", "brass", DES_J, 20, HORNS, 0.38, {"temple": 0.4}, pickup=1.0, transpose=-12)
    line(T, "base", "lead", DES_J, 20, ney, 0.28, TP, pickup=1.0)
    line(T, "hi", "brass", DES_J, 20, TRUMPETS, 0.26, {"temple": 0.4}, pickup=1.0)
    pad(T, "hi", "choir", prog(DES_J_CH, 4, 20), CHOIR_A, center=60, count=4, gain=0.16, sends={"dunes": 0.5}, vel=0.75)
    pad(T, "hi", "brass", prog(DES_CH, 4, 32), TROMBONES, center=50, count=2, gain=0.12, sends=TP, vel=0.6)
    gong = me.gong(me.rng_for("dgong"), 1.0, 5.0, 73.0)
    for bar in (4, 20, 32):
        ring(T, "hi", "drums", bar * 4, gong, 0.18, 0.0, {"dunes": 0.4})
        swell_into(T, "hi", "drums", bar, 4, 0.14, TP)
    ring(T, "base", "drone", 28 * 4, me.riser(r, 16.0, T.spb, 0.7, 200.0, 5000.0), 0.12, 0.0, {"dunes": 0.4})
    T.render(rms_db=-14.5, hi_gain=0.75)


def _ff_glacier(B, r, k):
    B.notes(mel("E5t F#5t G#5t A5q E6q A6h", 4, 0, 0), FLUTE, r, 0.42, sends={"hall": 0.5}, legato=True)
    for m in (57, 61, 64, 69, 73):
        B.add(1.5, me.brass(r, float(mtof(m)), 2.6, 0.85, "horn", voices=2), 0.16, sends={"hall": 0.5})
    for i, m in enumerate((81, 85, 88, 93, 97, 100)):
        B.add(1.5 + 0.08 * i, me.mallet(r, float(mtof(m)), 0.8, 0.7, "celesta"), 0.16, (i / 5 - 0.5), {"hall": 0.6})
    B.add(1.5, me.timpani(r, float(mtof(45)), 1.0), 0.4, sends={"hall": 0.3})
    B.add(1.5, me.cymbal(r, "crash"), 0.16, 0.3, {"hall": 0.4})
    B.add(1.5, me.triangle(r, 0.8, 2.0), 0.1, -0.4, {"hall": 0.5})


def _ff_desert(B, r, k):
    B.notes(mel("A4e Bb4e C#5e D5q A5q D6h", 4, 0, 0), I(me.brass, kind="trumpet", voices=2), r, 0.42, sends={"hall": 0.4})
    for m in (50, 57, 62, 66, 69):
        B.add(1.5, me.brass(r, float(mtof(m)), 2.4, 0.9, "horn" if m < 64 else "trumpet", voices=2), 0.15, sends={"hall": 0.4})
    for i, m in enumerate((74, 75, 74, 75, 78, 81, 86)):
        B.add(1.5 + 0.07 * i, me.harp(r, float(mtof(m)), 0.8, 0.6), 0.14, 0.3, {"hall": 0.4})
    for t0 in (0.0, 0.5, 1.0, 1.5):
        B.add(t0, me.frame_drum(r, 1.0, True), 0.4, sends={"hall": 0.3})
    B.add(1.5, me.gong(r, 1.0, 4.0, 73.0), 0.26, sends={"hall": 0.3})
    B.add(1.5, me.tambourine(r, 1.0, True), 0.2, 0.3, {"hall": 0.3})


# --------------------------------------------------------------------------
# stingers: course fanfares (Music bus, then the results music), checkpoint chimes (SFX bus,
# pitched up the map's scale per checkpoint by Sfx.checkpoint_chime) and the new-best sparkle.
# --------------------------------------------------------------------------
def _irs(r):
    return {"hall": me.make_ir(r, rt60=2.2, predelay=0.02, damp=4500, er=0.5),
            "small": me.make_ir(r, rt60=1.0, predelay=0.01, damp=6000, er=0.6)}


def fanfare(name, key, spec, seconds=4.5, bpm=120.0, rms=-12.5):
    r = me.rng_for("fanfare_" + name)
    B = me.Buffer(seconds, bpm)
    spec(B, r, key)
    x = B.mix(_irs(r))
    me.render_stinger("fanfare_" + name, x, rms)


def chime(name, spec, seconds=1.4):
    r = me.rng_for("chime_" + name)
    B = me.Buffer(seconds, 120.0)
    spec(B, r)
    x = B.mix(_irs(r))
    me.render_stinger("checkpoint_" + name, x, -17.0, quality=0.4)


def _ff_gardens(B, r, k):
    B.notes(mel("D5t E5t F#5t G5q. D6e G6h", 4, 0, 0), FLUTE, r, 0.5, sends={"hall": 0.3}, legato=True)
    for m in (55, 59, 62, 67):
        B.add(1.0, me.brass(r, float(mtof(m)), 2.2, 0.8, "horn"), 0.22, sends={"hall": 0.4})
    for m in (43, 50):
        B.add(1.0, me.strings(r, float(mtof(m)), 2.2, 0.8, voices=3), 0.25, sends={"hall": 0.3})
    B.add(1.0, me.timpani(r, float(mtof(43)), 1.0), 0.4, sends={"hall": 0.3})
    for i, m in enumerate((79, 83, 86, 91, 95)):
        B.add(1.0 + 0.125 * i, me.mallet(r, float(mtof(m)), 0.5, 0.7, "glockenspiel"), 0.18, 0.3, {"hall": 0.4})
    for i, m in enumerate((55, 59, 62, 67, 71, 74, 79, 83)):
        B.add(1.1 + 0.06 * i, me.harp(r, float(mtof(m)), 1.0, 0.6), 0.14, -0.3, {"hall": 0.4})


def _ff_foundry(B, r, k):
    B.notes(mel("D4q. D4e F4q A4q | D5w", 4, 0, 0), I(me.brass, kind="trombone", voices=3), r, 0.45, sends={"hall": 0.3})
    for m in (50, 54, 57, 62):
        B.add(4.0, me.brass(r, float(mtof(m)), 2.5, 0.9, "horn", voices=2), 0.2, sends={"hall": 0.4})
    for t0 in (0.0, 1.5, 2.0, 3.0, 4.0):
        B.add(t0, me.taiko(r, "odaiko"), 0.5, sends={"hall": 0.3})
    for t0, p in ((1.5, 1.0), (3.5, 0.749), (4.0, 1.0)):
        B.add(t0, me.anvil(r, 1.0, p), 0.26, 0.3, {"hall": 0.3})
    B.add(4.0, me.gong(r, 1.0, 4.0, 73.0), 0.3, sends={"hall": 0.3})


def _ff_balance(B, r, k):
    B.notes(mel("A4t B4t C#5t | D5q A5q | D6h", 2, 0, 0), ACCORDION, r, 0.45, sends={"small": 0.3})
    B.notes(mel("A4t B4t C#5t | D5q A5q | D6h", 2, 0, 0), FIDDLE, r, 0.3, sends={"small": 0.3}, legato=True)
    for m in (50, 54, 57, 62, 66):
        B.add(3.0, me.guitar(r, float(mtof(m)), 1.5, 0.8), 0.18, sends={"small": 0.3})
    for t0 in (1.0, 2.0, 3.0):
        B.add(t0, me.frame_drum(r), 0.4, sends={"small": 0.3})
        B.add(t0 + 0.5, me.clap(r), 0.35, sends={"small": 0.3})


def _ff_clockwork(B, r, k):
    B.notes(mel("B5e E6e F#6e G#6e B6h", 4, 0, 0), I(me.mallet, kind="musicbox"), r, 0.5, sends={"hall": 0.3})
    for m in (52, 56, 59, 64, 68):
        B.add(2.5, me.strings(r, float(mtof(m)), 2.5, 0.7, voices=3), 0.14, sends={"hall": 0.4})
    for i in range(3):
        B.add(2.5 + i * 1.3, me.bell(r, float(mtof(64)), 4.0, 0.8), 0.24, 0.2, {"hall": 0.5})
    for i, m in enumerate((88, 92, 95, 100)):
        B.add(2.5 + 0.1 * i, me.mallet(r, float(mtof(m)), 0.5, 0.6, "celesta"), 0.18, -0.2, {"hall": 0.4})
    for i in range(6):
        B.add(i * 0.5, me.clock_tick(r, 1.0, i % 2 == 1), 0.12, 0.4 if i % 2 else -0.4, {"small": 0.3})


def _ff_reef(B, r, k):
    for i, m in enumerate((53, 57, 60, 64, 65, 69, 72, 76, 77, 81, 84)):
        B.add(0.07 * i, me.harp(r, float(mtof(m)), 1.5, 0.6), 0.16, (i / 10 - 0.5), {"hall": 0.5})
    for m in (65, 69, 72, 76):
        B.add(1.0, me.mallet(r, float(mtof(m)), 2.5, 0.7, "vibraphone"), 0.2, sends={"hall": 0.5})
    for m in (53, 60, 64, 69):
        B.add(0.5, me.choir(r, float(mtof(m)), 2.5, 0.7, "u", att=0.6, rel=1.2), 0.2, sends={"hall": 0.5})
    for i in range(10):
        B.add(0.8 + 0.18 * i, me.bubble(r, 0.8, 600 + 120 * i), 0.1, r.uniform(-0.7, 0.7), {"hall": 0.4})


def _ff_orbital(B, r, k):
    B.notes(mel("G4t A4t B4t C5q G5q C6h", 4, 0, 0), I(me.brass, kind="trumpet", voices=2), r, 0.45, sends={"hall": 0.4})
    for m in (48, 55, 60, 64, 67):
        B.add(2.0, me.brass(r, float(mtof(m)), 2.2, 0.85, "horn" if m < 60 else "trumpet"), 0.18, sends={"hall": 0.45})
    B.add(2.0, me.timpani(r, float(mtof(36)), 1.0), 0.4, sends={"hall": 0.3})
    B.add(2.0, me.cymbal(r, "crash"), 0.2, 0.3, {"hall": 0.3})
    for i, m in enumerate((84, 88, 91, 96, 100)):
        B.add(2.0 + 0.1 * i, me.fm_bell(r, float(mtof(m)), 1.5, 0.6), 0.1, 0.5 * np.sin(i), {"hall": 0.5})


def _ff_ascent(B, r, k):
    """Scored to the beacon: a 2.7 s rise lands as the crystal ignites."""
    hit = 2.7 / B.spb
    B.add(0.0, me.riser(r, hit, B.spb, 0.9, 200.0, 9000.0), 0.3, sends={"hall": 0.3})
    B.add(0.0, me.timpani_roll(r, float(mtof(38)), hit, B.spb, 0.15, 1.0), 0.3, sends={"hall": 0.3})
    for m in (50, 57, 62, 66, 69):
        B.add(0.2, me.choir(r, float(mtof(m)), 2.5, 0.9, "a", att=2.3, rel=0.3), 0.14, sends={"hall": 0.4})
    for m in (62, 66, 69, 74, 78, 81):
        B.add(hit, me.brass(r, float(mtof(m)), 3.0, 0.95, "trumpet" if m > 70 else "horn", voices=2), 0.14, sends={"hall": 0.45})
        B.add(hit, me.supersaw(r, float(mtof(m)), 3.0, 0.8, voices=5, cutoff=4000.0, rel=1.0, sub=0.0), 0.06,
              sends={"hall": 0.3})
    for m in (38, 50):
        B.add(hit, me.strings(r, float(mtof(m)), 3.0, 0.9, voices=4), 0.26, sends={"hall": 0.3})
    B.add(hit, me.boom(r, 1.0, 36.0, 3.0), 0.4)
    B.add(hit, me.cymbal(r, "crash"), 0.25, 0.3, {"hall": 0.3})
    B.add(hit, me.timpani(r, float(mtof(38)), 1.0), 0.4, sends={"hall": 0.3})
    B.notes(mel("F#5t G5t A5t | D6h A6h", 4, 0, hit - 1.0), I(me.synth_lead, wave="saw"), r, 0.3, sends={"hall": 0.3})


def stingers():
    fanfare("gardens", 67, _ff_gardens, 4.2)
    fanfare("foundry", 62, _ff_foundry, 5.0, bpm=138.0)
    fanfare("balance", 62, _ff_balance, 3.8, bpm=104.0)
    fanfare("clockwork", 64, _ff_clockwork, 6.5)
    fanfare("reef", 65, _ff_reef, 5.0)
    fanfare("orbital", 60, _ff_orbital, 4.8, bpm=100.0)
    fanfare("xeno", 64, _ff_xeno, 5.2, bpm=92.0)
    fanfare("volcano", 60, _ff_volcano, 5.2, bpm=160.0)
    fanfare("glacier", 66, _ff_glacier, 5.0, bpm=84.0)
    fanfare("desert", 62, _ff_desert, 5.0, bpm=104.0)
    fanfare("ascent", 62, _ff_ascent, 7.0, bpm=128.0, rms=-12.0)
    # checkpoint chimes (tonic of each map's key; the game steps them up its scale)
    chime("gardens", lambda B, r: (B.add(0, me.mallet(r, float(mtof(79)), 0.8, 0.8, "glockenspiel"), 0.4, 0.2, {"small": 0.3}),
                                   B.add(0.25, me.mallet(r, float(mtof(86)), 0.8, 0.7, "glockenspiel"), 0.35, -0.2, {"small": 0.3}),
                                   B.add(0.0, me.harp(r, float(mtof(67)), 1.0, 0.7), 0.3, 0.0, {"small": 0.3})))
    chime("foundry", lambda B, r: (B.add(0, me.anvil(r, 1.0, 1.0, 0.6), 0.35, 0.2, {"small": 0.3}),
                                   B.add(0.0, me.brass(r, float(mtof(50)), 0.5, 0.9, "trombone", voices=2, fp=True), 0.3, 0.0,
                                         {"small": 0.3}),
                                   B.add(0.3, me.anvil(r, 1.0, 1.335, 0.5), 0.25, -0.2, {"small": 0.3})))
    chime("balance", lambda B, r: (B.add(0, me.mallet(r, float(mtof(74)), 0.6, 0.8, "marimba"), 0.4, 0.2, {"small": 0.3}),
                                   B.add(0.22, me.mallet(r, float(mtof(81)), 0.6, 0.8, "marimba"), 0.4, -0.2, {"small": 0.3}),
                                   B.add(0.22, me.woodwind(r, float(mtof(86)), 0.4, 0.7, "whistle"), 0.25, 0.0, {"small": 0.3})))
    chime("clockwork", lambda B, r: (B.add(0, me.mallet(r, float(mtof(76)), 0.8, 0.8, "musicbox"), 0.4, 0.2, {"small": 0.3}),
                                     B.add(0.2, me.mallet(r, float(mtof(83)), 0.8, 0.8, "musicbox"), 0.4, -0.2, {"small": 0.3}),
                                     B.add(0.0, me.clock_tick(r, 1.0), 0.2, 0.0, {"small": 0.2}),
                                     B.add(0.4, me.bell(r, float(mtof(88)), 1.2, 0.5), 0.15, 0.0, {"small": 0.3})))
    chime("reef", lambda B, r: (B.add(0, me.mallet(r, float(mtof(77)), 1.0, 0.8, "vibraphone"), 0.4, 0.2, {"hall": 0.4}),
                                B.add(0.2, me.mallet(r, float(mtof(84)), 1.0, 0.7, "vibraphone"), 0.35, -0.2, {"hall": 0.4}),
                                B.add(0.05, me.bubble(r, 0.8, 900), 0.2, 0.4, {"hall": 0.3}),
                                B.add(0.25, me.bubble(r, 0.8, 1300), 0.2, -0.4, {"hall": 0.3})))
    chime("orbital", lambda B, r: (B.add(0, me.fm_bell(r, float(mtof(72)), 1.0, 0.8), 0.4, 0.2, {"hall": 0.4}),
                                   B.add(0.2, me.fm_bell(r, float(mtof(79)), 1.0, 0.7), 0.35, -0.2, {"hall": 0.4}),
                                   B.add(0.0, me.synth_pluck(r, float(mtof(84)), 0.4, 0.6), 0.2, 0.0, {"hall": 0.4})))
    chime("xeno", lambda B, r: (B.add(0, me.mallet(r, float(mtof(76)), 0.8, 0.8, "kalimba"), 0.4, 0.2, {"hall": 0.4}),
                                B.add(0.16, me.mallet(r, float(mtof(83)), 0.8, 0.8, "kalimba"), 0.35, -0.2, {"hall": 0.4}),
                                B.add(0.3, me.fm_bell(r, float(mtof(94)), 1.0, 0.5), 0.14, 0.0, {"hall": 0.5}),
                                B.add(0.0, alien_chirp(me.rng_for("chime_chirp"), 0.6), 0.08, 0.5, {"hall": 0.4})))
    chime("volcano", lambda B, r: (B.add(0, me.timpani(r, float(mtof(48)), 0.9), 0.35, 0.0, {"small": 0.3}),
                                   B.add(0.0, me.brass(r, float(mtof(60)), 0.45, 0.9, "horn", voices=2, fp=True), 0.3, 0.2,
                                         {"hall": 0.3}),
                                   B.add(0.2, me.brass(r, float(mtof(67)), 0.5, 0.9, "trumpet", voices=2, fp=True), 0.26, -0.2,
                                         {"hall": 0.3})))
    chime("glacier", lambda B, r: (B.add(0, me.mallet(r, float(mtof(78)), 0.8, 0.8, "celesta"), 0.4, 0.2, {"hall": 0.5}),
                                   B.add(0.18, me.mallet(r, float(mtof(85)), 0.8, 0.8, "celesta"), 0.35, -0.2, {"hall": 0.5}),
                                   B.add(0.0, me.harp(r, float(mtof(66)), 1.0, 0.7), 0.25, 0.0, {"hall": 0.4}),
                                   B.add(0.3, me.triangle(r, 0.6, 1.0), 0.08, 0.4, {"hall": 0.5})))
    chime("desert", lambda B, r: (B.add(0, me.harp(r, float(mtof(74)), 0.6, 0.8), 0.3, 0.2, {"small": 0.4}),
                                  B.add(0.08, me.harp(r, float(mtof(75)), 0.6, 0.7), 0.25, 0.1, {"small": 0.4}),
                                  B.add(0.16, me.harp(r, float(mtof(78)), 0.6, 0.8), 0.28, -0.1, {"small": 0.4}),
                                  B.add(0.24, me.harp(r, float(mtof(81)), 0.8, 0.8), 0.3, -0.2, {"small": 0.4}),
                                  B.add(0.0, me.frame_drum(r, 0.8, True), 0.3, 0.0, {"small": 0.3}),
                                  B.add(0.24, me.triangle(r, 0.6, 0.8), 0.08, 0.3, {"hall": 0.4})))
    chime("ascent", lambda B, r: (B.add(0, me.synth_pluck(r, float(mtof(71)), 0.4, 0.9), 0.4, 0.2, {"hall": 0.3}),
                                  B.add(0.18, me.synth_pluck(r, float(mtof(78)), 0.4, 0.9), 0.4, -0.2, {"hall": 0.3}),
                                  B.add(0.36, me.synth_pluck(r, float(mtof(83)), 0.5, 0.8), 0.35, 0.0, {"hall": 0.4}),
                                  B.add(0.0, me.fm_bell(r, float(mtof(95)), 1.0, 0.4), 0.12, 0.0, {"hall": 0.4})))
    # a new personal best: a rising sparkle (effects bus, over the results music)
    r = me.rng_for("new_best")
    B = me.Buffer(2.4, 120.0)
    for i, m in enumerate((72, 76, 79, 84, 88, 91, 96)):
        B.add(0.12 * i, me.mallet(r, float(mtof(m)), 0.6, 0.8, "glockenspiel"), 0.28, (i / 6 - 0.5), {"hall": 0.4})
        B.add(0.12 * i, me.harp(r, float(mtof(m - 12)), 1.0, 0.7), 0.16, -(i / 6 - 0.5), {"hall": 0.4})
    for m in (60, 64, 67, 72):
        B.add(0.84, me.strings(r, float(mtof(m)), 1.2, 0.7, voices=3, att=0.05, rel=0.6), 0.1, sends={"hall": 0.4})
    me.render_stinger("new_best", B.mix(_irs(r)), -16.0, quality=0.4)


PIECES = {
    "gardens": piece_gardens,
    "foundry": piece_foundry,
    "balance": piece_balance,
    "clockwork": piece_clockwork,
    "reef": piece_reef,
    "orbital": piece_orbital,
    "xeno": piece_xeno,
    "volcano": piece_volcano,
    "glacier": piece_glacier,
    "desert": piece_desert,
    "ascent": piece_ascent,
    "title": piece_title,
    "lobby": piece_lobby,
    "results": piece_results,
    "victory": piece_victory,
    "stingers": stingers,
}
LAYERED = ("gardens", "foundry", "balance", "clockwork", "reef", "orbital", "xeno", "volcano", "glacier", "desert", "ascent")


def verify():
    """Every score / layer exists, loops seamlessly, sits at a sane level; layers match in length."""
    import soundfile as sf
    ok = True
    total = 0
    print("verify:")
    for name in [p for p in PIECES if p != "stingers"]:
        files = ["music_" + name] + (["music_%s_hi" % name] if name in LAYERED else [])
        lens = []
        for f in files:
            path = os.path.join(OUT, f + ".ogg")
            if not os.path.exists(path):
                print("  %-24s MISSING" % f)
                ok = False
                continue
            total += os.path.getsize(path)
            x, sr = sf.read(path)
            lens.append(len(x))
            steps = np.max(np.abs(np.diff(x, axis=0)), axis=1)
            p999 = np.quantile(steps, 0.999)
            wrap = np.max(np.abs(x[0] - x[-1]))
            pk = 20 * np.log10(np.max(np.abs(x)) + 1e-12)
            good = sr == me.MSR and x.shape[1] == 2 and wrap <= max(p999 * 1.5, 0.02) and pk < -0.3 and np.all(np.isfinite(x))
            ok &= bool(good)
            print("  %-24s %6.1f s  peak %6.2f dB  wrap %.4f (p99.9 %.4f)  %4.0f kB  %s" % (
                f, len(x) / sr, pk, wrap, p999, os.path.getsize(path) / 1000, "ok" if good else "FAIL"))
        if len(set(lens)) > 1:
            print("  %-24s layer lengths differ: %s  FAIL" % (name, lens))
            ok = False
    for f in ["fanfare_" + n for n in LAYERED] + ["checkpoint_" + n for n in LAYERED] + ["new_best"]:
        path = os.path.join(OUT, f + ".ogg")
        good = os.path.exists(path)
        if good:
            total += os.path.getsize(path)
        ok &= good
        print("  %-24s %s" % (f, "ok" if good else "MISSING"))
    print("  total %.2f MB" % (total / 1e6))
    print("RESULT: " + ("ALL OK" if ok else "PROBLEMS FOUND"))
    return ok


def main():
    if "--list" in sys.argv:
        print(" ".join(PIECES))
        return
    if "--verify" in sys.argv:
        sys.exit(0 if verify() else 1)
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    _perc_bank()
    todo = args or list(PIECES)
    for name in todo:
        t0 = time.time()
        print("%s:" % name)
        PIECES[name]()
        me.clear_cache()
        print("  (%.1f s)" % (time.time() - t0))
    if not args:
        sys.exit(0 if verify() else 1)


if __name__ == "__main__":
    main()
