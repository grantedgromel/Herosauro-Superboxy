#!/usr/bin/env python3
"""Offline generator for the storybook sound effects.

    python3 -B scripts/audio/gen/make_story_sfx.py          (from herosauro-superboxy/)

Writes mono 22 050 Hz 16-bit WAVs into assets/audio/sfx/ and prints a table of
what it made. The outputs are COMMITTED: the game loads them like any other
sample and synthesises nothing at boot, because the web build runs on one WASM
thread and every millisecond spent building a waveform there is a child
looking at a loading screen. Re-run this only to change a sound, then
re-import (godot --headless --import .).

Pure Python, standard library only, so it runs anywhere the repo does. Every
random draw comes from a random.Random seeded per sound and per variant, so the
same script writes the same bytes twice.

The brief is a Nintendo / Toca Boca palette for children aged 4 to 8: bright,
warm, musical, cartoon, and never startling. Concretely, every file goes
through the same finishing chain (see finish()):

  * 40 Hz high-pass (no DC, no sub thump the speaker cannot play anyway);
  * 4th-order low-pass at 7 kHz or lower, so nothing has a harsh edge above
    ~8 kHz (the probe measures the energy left up there);
  * a gentle 2.5:1 compressor 10 dB under the peak, so the attack is not much
    louder than the body of the sound;
  * peak normalised to -3 dBFS, a raised-cosine fade in and a fade out.

Musical sounds are in C major so the chimes agree with each other.
"""

import math
import os
import random
import struct
import sys
import wave

SR = 22050
TAU = 2.0 * math.pi
PEAK_DB = -3.0
MAX_BYTES = 60 * 1024

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.normpath(os.path.join(HERE, "..", "..", "..", "assets", "audio", "sfx"))

# Note frequencies used by the musical sounds (equal temperament, A4 = 440).
def note(name):
    names = {"C": -9, "D": -7, "E": -5, "F": -4, "G": -2, "A": 0, "B": 2}
    octave = int(name[-1])
    semis = names[name[0]] + (1 if "#" in name else 0) + 12 * (octave - 4)
    return 440.0 * 2.0 ** (semis / 12.0)


# --- buffers -----------------------------------------------------------------

def ns(sec):
    return int(round(sec * SR))


def buf(sec):
    return [0.0] * ns(sec)


def mix(dst, src, at=0.0, gain=1.0):
    o = ns(at)
    end = min(len(dst), o + len(src))
    for j in range(max(0, o), end):
        dst[j] += src[j - o] * gain
    return dst


def mul(a, b):
    return [x * y for x, y in zip(a, b)]


def noise(n, rng):
    return [rng.uniform(-1.0, 1.0) for _ in range(n)]


# --- envelopes ---------------------------------------------------------------

def k60(t60):
    """Per-sample decay constant for -60 dB in t60 seconds."""
    return math.log(1000.0) / max(1e-4, t60 * SR)


def perc(n, attack, t60, hold=0.0):
    """Raised-cosine attack, optional hold, exponential decay (t60 to -60 dB)."""
    a = max(1, ns(attack))
    h = ns(hold)
    k = k60(t60)
    out = [0.0] * n
    for i in range(n):
        if i < a:
            out[i] = 0.5 - 0.5 * math.cos(math.pi * i / a)
        elif i < a + h:
            out[i] = 1.0
        else:
            out[i] = math.exp(-(i - a - h) * k)
    return out


def swell(n, attack, release):
    """Rise over `attack` s, fall over the last `release` s, smooth both ends."""
    a = max(1, ns(attack))
    r = max(1, ns(release))
    out = [1.0] * n
    for i in range(n):
        if i < a:
            out[i] = math.sin(0.5 * math.pi * i / a) ** 2
        if i > n - r:
            u = (n - i) / r
            out[i] *= math.sin(0.5 * math.pi * u) ** 2
    return out


# --- oscillators -------------------------------------------------------------

def sine(dur, freq, phase=0.0, amp=None):
    """Sine with a constant or callable(t) frequency and optional callable(t) amp."""
    n = ns(dur)
    out = [0.0] * n
    ph = phase
    for i in range(n):
        t = i / SR
        f = freq(t) if callable(freq) else freq
        ph += TAU * f / SR
        out[i] = math.sin(ph) * (amp(t) if amp else 1.0)
    return out


def additive(dur, freq, partials, top=7000.0):
    """Harmonic additive tone: partials = [(multiple, amplitude)], band-limited
    at `top` so nothing aliases or fizzes."""
    n = ns(dur)
    out = [0.0] * n
    ph = 0.0
    for i in range(n):
        t = i / SR
        f = freq(t) if callable(freq) else freq
        ph += TAU * f / SR
        s = 0.0
        for m, a in partials:
            if m * f < top:
                s += a * math.sin(m * ph)
        out[i] = s
    return out


# A glockenspiel / celesta: inharmonic partials, the upper ones die first.
BELL = ((1.0, 1.0, 1.0), (2.0, 0.42, 0.55), (3.01, 0.20, 0.35),
        (4.17, 0.10, 0.22), (5.43, 0.05, 0.15))


def bell(f, dur, t60, partials=BELL, attack=0.0025, shimmer=0.0, top=7200.0):
    """One struck chime. `shimmer` detunes a twin of the fundamental to beat."""
    n = ns(dur)
    out = [0.0] * n
    layers = list(partials)
    if shimmer > 0.0:
        layers.append((1.0 + shimmer, 0.35, 0.9))
    for ratio, amp, tscale in layers:
        fr = f * ratio
        if fr >= top:
            continue
        env = perc(n, attack, t60 * tscale)
        w = TAU * fr / SR
        for i in range(n):
            out[i] += amp * env[i] * math.sin(w * i)
    return out


def modal(modes, dur, attack=0.0008):
    """Struck object: modes = [(Hz, t60, amp)]. Wood blocks, knocks, bonks."""
    n = ns(dur)
    out = [0.0] * n
    for f, t60, amp in modes:
        env = perc(n, attack, t60)
        w = TAU * f / SR
        for i in range(n):
            out[i] += amp * env[i] * math.sin(w * i)
    return out


# --- filters -----------------------------------------------------------------

def _coefs(kind, f, q):
    f = min(max(f, 20.0), SR * 0.45)
    w = TAU * f / SR
    cw = math.cos(w)
    alpha = math.sin(w) / (2.0 * q)
    if kind == "lp":
        b0, b1, b2 = (1 - cw) / 2, 1 - cw, (1 - cw) / 2
    elif kind == "hp":
        b0, b1, b2 = (1 + cw) / 2, -(1 + cw), (1 + cw) / 2
    else:  # band-pass, 0 dB at the centre
        b0, b1, b2 = alpha, 0.0, -alpha
    a0 = 1 + alpha
    return b0 / a0, b1 / a0, b2 / a0, (-2 * cw) / a0, (1 - alpha) / a0


def biquad(x, kind, f, q=0.707):
    """RBJ biquad. `f` may be callable(t) for a sweep (re-tuned every 16 samples)."""
    out = [0.0] * len(x)
    x1 = x2 = y1 = y2 = 0.0
    sweep = callable(f)
    c = _coefs(kind, f(0.0) if sweep else f, q)
    for i, xi in enumerate(x):
        if sweep and i % 16 == 0:
            c = _coefs(kind, f(i / SR), q)
        b0, b1, b2, a1, a2 = c
        y = b0 * xi + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1 = x1, xi
        y2, y1 = y1, y
        out[i] = y
    return out


def lowpass4(x, f):
    """4th-order Butterworth low-pass (two biquads)."""
    return biquad(biquad(x, "lp", f, 0.5412), "lp", f, 1.3066)


# --- a small cartoon voice ---------------------------------------------------

# Formants (Hz, bandwidth Hz, gain) for a small, bright voice.
VOWELS = {
    "ee": ((310, 90, 1.0), (2550, 260, 0.55), (3300, 320, 0.25)),
    "ih": ((430, 100, 1.0), (2100, 220, 0.45), (2950, 300, 0.20)),
    "eh": ((600, 110, 1.0), (1850, 200, 0.45), (2700, 300, 0.18)),
    "ah": ((850, 130, 1.0), (1300, 160, 0.60), (2700, 300, 0.16)),
    "oh": ((520, 110, 1.0), (900, 130, 0.50), (2600, 300, 0.10)),
    "oo": ((330, 90, 1.0), (780, 120, 0.35), (2400, 300, 0.06)),
    "mm": ((260, 70, 1.0), (1000, 220, 0.06), (2300, 300, 0.02)),
}


def vowel_at(path, t):
    """path = [(time, vowel)], linearly interpolated between key vowels."""
    if t <= path[0][0]:
        return VOWELS[path[0][1]]
    for (t0, v0), (t1, v1) in zip(path, path[1:]):
        if t <= t1:
            u = (t - t0) / max(1e-6, t1 - t0)
            a, b = VOWELS[v0], VOWELS[v1]
            return tuple(tuple(x + (y - x) * u for x, y in zip(fa, fb)) for fa, fb in zip(a, b))
    return VOWELS[path[-1][1]]


def voice(dur, f0, vowels, amp, formant_scale=1.0, tilt=0.9, top=6000.0,
          vib=(5.5, 0.012), rng=None, jitter=0.0, growl=None):
    """Additive source-filter voice: harmonics of f0(t), each weighted by the
    vowel's resonances at that harmonic. Clean, cute and band-limited, which a
    pulse train through filters is not at these pitches."""
    n = ns(dur)
    out = [0.0] * n
    ph = 0.0
    block = 32
    amps_now = []
    jit = 0.0
    for b0 in range(0, n, block):
        t = b0 / SR
        f = f0(t)
        forms = vowel_at(vowels, t)
        kmax = int(top / max(1.0, f))
        target = []
        for k in range(1, kmax + 1):
            h = k * f
            g = 0.0
            for F, bw, gain in forms:
                F *= formant_scale
                x = (h - F) / (0.5 * bw * formant_scale)
                g += gain / (1.0 + x * x)
            target.append(g / (k ** tilt))
        if not amps_now:
            amps_now = target[:]
        a_env = amp(t)
        if rng is not None and jitter > 0.0:
            jit = 0.7 * jit + 0.3 * rng.uniform(-1.0, 1.0)
        for i in range(b0, min(n, b0 + block)):
            ti = i / SR
            fi = f0(ti) * (1.0 + vib[1] * math.sin(TAU * vib[0] * ti)) * (1.0 + jitter * jit)
            ph += TAU * fi / SR
            u = (i - b0) / block
            s = 0.0
            m = min(len(amps_now), len(target))
            for k in range(m):
                s += (amps_now[k] + (target[k] - amps_now[k]) * u) * math.sin((k + 1) * ph)
            g = amp(ti)
            if growl is not None:
                g *= growl(ti)
            out[i] = s * g
        amps_now = target
        del a_env
    return out


def breath(dur, centre, q, env, rng):
    """Aspiration / 'h': band-passed noise under an envelope list."""
    x = biquad(noise(ns(dur), rng), "bp", centre, q)
    return mul(x, env)


# --- finishing ---------------------------------------------------------------

def compress(x, threshold_rel_db=-10.0, ratio=2.5, attack=0.003, release=0.06):
    peak = max(1e-9, max(abs(v) for v in x))
    thr = peak * 10 ** (threshold_rel_db / 20.0)
    ka = 1.0 - math.exp(-1.0 / (attack * SR))
    kr = 1.0 - math.exp(-1.0 / (release * SR))
    level = 0.0
    out = [0.0] * len(x)
    for i, v in enumerate(x):
        a = abs(v)
        level += (a - level) * (ka if a > level else kr)
        g = 1.0
        if level > thr:
            g = (level / thr) ** (1.0 / ratio - 1.0)
        out[i] = v * g
    return out


def finish(x, lp=7000.0, fade_in=0.0015, fade_out=0.02):
    x = biquad(x, "hp", 40.0, 0.707)
    x = lowpass4(x, lp)
    x = compress(x)
    # Trim the inaudible tail so files stay small.
    floor = max(abs(v) for v in x) * 10 ** (-62.0 / 20.0)
    end = len(x)
    while end > 1 and abs(x[end - 1]) < floor:
        end -= 1
    x = x[:end + ns(0.005)]
    fi = max(1, ns(fade_in))
    fo = max(1, ns(fade_out))
    n = len(x)
    for i in range(min(fi, n)):
        x[i] *= 0.5 - 0.5 * math.cos(math.pi * i / fi)
    for i in range(min(fo, n)):
        x[n - 1 - i] *= 0.5 - 0.5 * math.cos(math.pi * i / fo)
    x[-1] = 0.0
    pk = max(abs(v) for v in x)
    g = 10 ** (PEAK_DB / 20.0) / max(1e-9, pk)
    return [v * g for v in x]


def write_wav(path, x):
    frames = b"".join(struct.pack("<h", max(-32768, min(32767, int(round(v * 32767.0))))) for v in x)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(frames)


# =============================================================================
# The sounds
# =============================================================================

def ui_tap(rng, v):
    """A gentle wooden pop: a small woodblock, three pitches a whole tone apart."""
    f = (880.0, 988.0, 784.0)[v]
    x = modal([(f, 0.07, 1.0), (f * 2.56, 0.035, 0.30), (f * 0.5, 0.05, 0.25)], 0.16)
    click = mul(biquad(noise(ns(0.16), rng), "bp", 1800.0, 1.2), perc(ns(0.16), 0.0005, 0.012))
    mix(x, click, 0.0, 0.25)
    return finish(x, lp=6000.0)


def page_turn(rng, v):
    """A soft paper swish: band-passed noise sweeping up as the page lifts and
    over, a little flutter, and the page settling with a soft low pat."""
    dur = 0.46
    n = ns(dur)
    sweep = lambda t: 700.0 + 2600.0 * math.sin(math.pi * min(1.0, t / 0.36)) ** 1.5
    x = biquad(noise(n, rng), "bp", sweep, 0.65)
    env = [0.0] * n
    for i in range(n):
        t = i / SR
        rise = math.sin(0.5 * math.pi * min(1.0, t / 0.16)) ** 2
        fall = math.exp(-max(0.0, t - 0.18) / 0.09)
        flutter = 1.0 + 0.22 * math.sin(TAU * 23.0 * t) * math.exp(-t / 0.3)
        env[i] = rise * fall * flutter
    x = mul(x, env)
    pat = mul(biquad(noise(ns(0.12), rng), "lp", 380.0, 0.7), perc(ns(0.12), 0.004, 0.08))
    mix(x, pat, 0.27, 0.9)
    return finish(x, lp=5500.0, fade_out=0.04)


STAR_TRIADS = (("C6", "E6", "G6"), ("D6", "G6", "A6"), ("E6", "G6", "C7"))


def star(rng, v):
    """A rising sparkly chime: three quick celesta notes up a C-major shape, a
    shimmering top and a twinkle on the end. Three shapes, so a run of stars
    plays a little tune instead of one note over and over."""
    x = buf(0.62)
    for k, nm in enumerate(STAR_TRIADS[v]):
        mix(x, bell(note(nm), 0.55, 0.42, shimmer=0.004), 0.055 * k, 0.75 + 0.15 * k)
    tw = bell(note(STAR_TRIADS[v][2]) * 2.0, 0.35, 0.18, partials=((1.0, 1.0, 1.0), (2.0, 0.3, 0.5)))
    mix(x, tw, 0.16, 0.30)
    return finish(x, lp=7000.0, fade_out=0.05)


def objective_done(rng, v):
    """A short happy fanfare: C-E-G pick-up into a bright C chord, a soft brassy
    lead doubled by celesta, and a sparkle on top. About a second."""
    x = buf(1.25)
    lead = ((1, 1.0), (2, 0.55), (3, 0.35), (4, 0.22), (5, 0.12), (6, 0.08))
    steps = (("C5", 0.0, 0.10), ("E5", 0.10, 0.10), ("G5", 0.20, 0.10), ("C6", 0.30, 0.80))
    for nm, at, d in steps:
        f = note(nm)
        tone = additive(d + 0.12, lambda t, f=f: f * (1.0 + 0.006 * math.sin(TAU * 5.5 * t) * min(1.0, t / 0.2)), lead)
        env = perc(len(tone), 0.012, 1.4 if d > 0.5 else 0.35, hold=max(0.0, d - 0.06))
        if d > 0.5:
            env = mul(env, swell(len(env), 0.01, 0.35))
        mix(x, lowpass4(mul(tone, env), 3200.0), at, 0.45)
        mix(x, bell(f * 2.0, d + 0.4, 0.6 if d > 0.5 else 0.3), at, 0.35)
    for nm in ("E5", "G5"):  # the chord under the last note
        f = note(nm)
        pad = additive(0.9, f, ((1, 1.0), (2, 0.3), (3, 0.12)))
        mix(x, mul(pad, mul(perc(len(pad), 0.02, 1.2), swell(len(pad), 0.01, 0.35))), 0.30, 0.22)
    for k, nm in enumerate(("G6", "C7", "E7")):
        mix(x, bell(note(nm), 0.5, 0.3, partials=((1.0, 1.0, 1.0), (2.0, 0.25, 0.5))), 0.36 + 0.07 * k, 0.16)
    return finish(x, lp=7000.0, fade_out=0.08)


def bubble_pop(rng, v):
    """A cute bloop: a round tone gliding up fast, then a tiny 'pip'."""
    x = sine(0.16, lambda t: 330.0 * (3.2 ** min(1.0, t / 0.075)),
             amp=lambda t: math.sin(math.pi * min(1.0, t / 0.11)) ** 0.8 if t < 0.11 else 0.0)
    pip = mul(sine(0.08, 1420.0), perc(ns(0.08), 0.001, 0.05))
    mix(x, pip, 0.085, 0.35)
    return finish(x, lp=6000.0)


def cup_collect(rng, v):
    """A shiny ding with a coin tail: the classic B-to-E coin leap on a bright
    square-ish voice, doubled by a ringing celesta that carries the tail."""
    x = buf(0.75)
    coin = ((1, 1.0), (3, 0.30), (5, 0.12), (7, 0.05))
    b5 = additive(0.075, note("B5"), coin)
    mix(x, mul(b5, perc(len(b5), 0.002, 0.5, hold=0.05)), 0.0, 0.42)
    e6 = additive(0.62, note("E6"), coin)
    mix(x, mul(e6, perc(len(e6), 0.002, 0.42)), 0.075, 0.42)
    mix(x, bell(note("E6"), 0.68, 0.6, shimmer=0.003), 0.075, 0.55)
    mix(x, bell(note("B6"), 0.4, 0.25), 0.11, 0.18)
    return finish(x, lp=7000.0, fade_out=0.06)


def goblin_hit(rng, v):
    """A comic boing-bonk: a hollow coconut knock, then a spring that wobbles
    and settles. Cartoon physics, nothing that sounds like it hurt."""
    knock = (520.0, 590.0, 470.0)[v]
    spring = (250.0, 290.0, 220.0)[v]
    rate = (13.0, 15.0, 11.5)[v]
    x = buf(0.56)
    k = modal([(knock, 0.10, 1.0), (knock * 2.31, 0.05, 0.35), (knock * 0.42, 0.08, 0.5)], 0.2)
    mix(x, k, 0.0, 0.8)
    boing = sine(0.5, lambda t: spring * (1.0 + 0.10 * min(1.0, t / 0.3))
                 * (1.0 + 0.22 * math.exp(-t / 0.22) * math.sin(TAU * rate * t)))
    env = perc(len(boing), 0.006, 0.45)
    harm = sine(0.5, lambda t: 2.0 * spring * (1.0 + 0.22 * math.exp(-t / 0.22) * math.sin(TAU * rate * t)))
    mix(x, mul([a + 0.25 * b for a, b in zip(boing, harm)], env), 0.035, 0.75)
    return finish(x, lp=5500.0, fade_out=0.05)


def goblin_giggle(rng, v):
    """A squeaky, mischievous 'hee-hee-hee': a tiny pitched synthetic voice,
    each syllable led by a breathy 'h' and bending down at its end."""
    plans = (
        ((0.00, 900.0), (0.13, 850.0), (0.26, 800.0), (0.39, 760.0)),
        ((0.00, 820.0), (0.12, 880.0), (0.24, 800.0), (0.38, 960.0)),
        ((0.00, 980.0), (0.10, 930.0), (0.20, 880.0), (0.30, 840.0), (0.40, 800.0)),
    )[v]
    syl = 0.10
    dur = plans[-1][0] + syl + 0.12
    x = buf(dur)
    for at, f in plans:
        last = (at, f) == plans[-1]
        d = syl + (0.06 if last else 0.0)
        f0 = lambda t, f=f, d=d: f * (1.06 - 0.16 * min(1.0, t / d))
        amp = lambda t, d=d: (math.sin(0.5 * math.pi * min(1.0, t / 0.012)) ** 2) * math.exp(-max(0.0, t - 0.03) / (0.05 + 0.4 * d / 1.0))
        voc = voice(d, f0, ((0.0, "ee"), (d, "ih")), amp, formant_scale=1.25, tilt=1.0,
                    vib=(9.0, 0.02), rng=rng, jitter=0.004)
        mix(x, voc, at + 0.018, 0.8)
        hn = ns(0.04)
        h = breath(0.04, 2400.0, 1.4, [math.sin(math.pi * i / hn) ** 2 for i in range(hn)], rng)
        mix(x, lowpass4(h, 4000.0), at, 0.30)
    return finish(x, lp=6500.0, fade_out=0.04)


def ball_kick(rng, v):
    """A punchy, rubbery thump: a pitch-dropping kick under a hollow 'pok'."""
    base = (150.0, 170.0, 135.0)[v]
    pok = (640.0, 700.0, 580.0)[v]
    x = buf(0.32)
    th = sine(0.3, lambda t: 55.0 + base * math.exp(-t / 0.035))
    mix(x, mul(th, perc(len(th), 0.0015, 0.22)), 0.0, 1.0)
    p = modal([(pok, 0.06, 1.0), (pok * 1.73, 0.035, 0.4)], 0.12)
    mix(x, p, 0.002, 0.35)
    slap = mul(biquad(noise(ns(0.05), rng), "bp", 1500.0, 0.9), perc(ns(0.05), 0.0008, 0.018))
    mix(x, slap, 0.0, 0.30)
    return finish(x, lp=5000.0, fade_out=0.04)


def rope_snap(rng, v):
    """A twangy snap: a crisp (low-passed) crack and a plucked rope that bends
    down and wobbles as it lets go."""
    x = buf(0.62)
    crack = mul(biquad(noise(ns(0.06), rng), "bp", 2200.0, 1.1), perc(ns(0.06), 0.0008, 0.03))
    mix(x, crack, 0.0, 0.6)
    f0 = lambda t: 196.0 * (1.0 - 0.18 * (1.0 - math.exp(-t / 0.12))) * (1.0 + 0.03 * math.exp(-t / 0.2) * math.sin(TAU * 7.0 * t))
    s = additive(0.58, f0, ((1, 1.0), (2, 0.55), (3, 0.35), (4, 0.2), (5, 0.12), (6, 0.07)))
    env = perc(len(s), 0.002, 0.5)
    bright = [math.exp(-i / (0.08 * SR)) for i in range(len(s))]
    s2 = additive(0.58, lambda t: 3.0 * f0(t), ((1, 1.0), (2, 0.4)))
    tw = [a * e + 0.4 * b * e * br for a, b, e, br in zip(s, s2, env, bright)]
    mix(x, tw, 0.006, 0.7)
    return finish(x, lp=6000.0, fade_out=0.05)


def dragon_roar(rng, v):
    """A big, FRIENDLY roar: more yawn-growl than threat. A large soft voice
    opens on 'aah', rises, wobbles with a gentle purr-growl and closes into a
    contented 'mmm'. Low-passed warm, no rasp."""
    dur = 1.28
    def f0(t):
        if t < 0.28:
            return 105.0 + 60.0 * math.sin(0.5 * math.pi * t / 0.28)
        if t < 0.80:
            return 165.0 - 25.0 * (t - 0.28) / 0.52
        return 140.0 - 48.0 * math.sin(0.5 * math.pi * min(1.0, (t - 0.80) / 0.45))
    vowels = ((0.0, "oh"), (0.22, "ah"), (0.70, "ah"), (0.95, "oh"), (1.15, "mm"))
    amp = lambda t: (math.sin(0.5 * math.pi * min(1.0, t / 0.16)) ** 2) * (1.0 - 0.55 * max(0.0, (t - 0.85) / 0.43))
    growl = lambda t: 1.0 - 0.20 * math.sin(math.pi * min(1.0, max(0.0, (t - 0.12) / 0.75))) * (0.5 + 0.5 * math.sin(TAU * 23.0 * t))
    x = voice(dur, f0, vowels, amp, formant_scale=0.72, tilt=0.75, top=3800.0,
              vib=(4.5, 0.01), rng=rng, jitter=0.02, growl=growl)
    sub = sine(dur, lambda t: 0.5 * f0(t), amp=lambda t: 0.22 * amp(t))
    mix(x, sub, 0.0, 1.0)
    n = ns(dur)
    air = breath(dur, 900.0, 0.6, [0.10 * amp(i / SR) for i in range(n)], rng)
    mix(x, lowpass4(air, 1600.0), 0.0, 1.0)
    return finish(x, lp=3800.0, fade_in=0.01, fade_out=0.08)


def dragon_fire(rng, v):
    """A whooshy crackle: a soft rushing flame that swells and fades, with warm
    popping embers through it. Low-passed so the crackle is cosy, not sharp."""
    dur = 1.30
    n = ns(dur)
    sweep = lambda t: 450.0 + 900.0 * math.sin(math.pi * min(1.0, t / 1.1))
    rush = biquad(noise(n, rng), "bp", sweep, 0.55)
    env = [math.sin(0.5 * math.pi * min(1.0, (i / SR) / 0.18)) ** 2
           * (1.0 - max(0.0, (i / SR - 0.55) / 0.75)) ** 1.6 for i in range(n)]
    x = mul(rush, env)
    low = mul(biquad(noise(n, rng), "lp", 220.0, 0.7), env)
    mix(x, low, 0.0, 0.9)
    t = 0.06
    while t < 1.05:
        f = rng.uniform(900.0, 2400.0)
        pop = mul(sine(0.03, f), perc(ns(0.03), 0.0006, rng.uniform(0.012, 0.025)))
        mix(x, pop, t, rng.uniform(0.10, 0.22) * env[min(n - 1, ns(t))])
        t += rng.uniform(0.025, 0.07)
    return finish(x, lp=4500.0, fade_in=0.01, fade_out=0.1)


def magic_repair(rng, v):
    """A magical shimmer sweep: a rising C-major-pentatonic celesta run, a
    twinkling cluster that swells up behind it and a soft airy glissando."""
    dur = 1.32
    x = buf(dur)
    run = ("C5", "D5", "E5", "G5", "A5", "C6", "D6", "E6", "G6", "C7")
    for k, nm in enumerate(run):
        mix(x, bell(note(nm), 0.6, 0.38, shimmer=0.003), 0.055 * k, 0.32 + 0.03 * k)
    n = ns(dur)
    shimmer = [0.0] * n
    for k in range(7):
        f = rng.uniform(2200.0, 4600.0)
        rate = rng.uniform(6.0, 13.0)
        ph = rng.uniform(0.0, TAU)
        w = TAU * f / SR
        for i in range(n):
            t = i / SR
            shimmer[i] += math.sin(w * i) * (0.5 + 0.5 * math.sin(TAU * rate * t + ph)) ** 2
    sw = [math.sin(math.pi * min(1.0, (i / SR) / 1.2)) ** 2 for i in range(n)]
    mix(x, mul(shimmer, sw), 0.0, 0.035)
    air = biquad(noise(n, rng), "bp", lambda t: 900.0 + 4200.0 * min(1.0, t / 1.0), 1.4)
    mix(x, lowpass4(mul(air, sw), 5000.0), 0.0, 0.07)
    return finish(x, lp=7000.0, fade_out=0.12)


def panda_cheer(rng, v):
    """Little happy cheers and claps: three small 'yaaay!' voices a moment
    apart at different pitches, and a ripple of soft hand claps."""
    dur = 1.3
    x = buf(dur)
    for at, base, scale in ((0.0, 470.0, 1.15), (0.07, 560.0, 1.25), (0.13, 410.0, 1.1)):
        d = 0.55
        f0 = lambda t, b=base, d=d: b * (1.0 + 0.30 * math.sin(math.pi * min(1.0, t / (0.8 * d))) ** 0.7) * (1.0 - 0.06 * t / d)
        amp = lambda t, d=d: (math.sin(0.5 * math.pi * min(1.0, t / 0.03)) ** 2) * (1.0 - max(0.0, (t - 0.32) / 0.23)) ** 1.5
        voc = voice(d, f0, ((0.0, "ee"), (0.07, "eh"), (0.18, "ah"), (0.40, "eh"), (0.55, "ee")), amp,
                    formant_scale=scale, tilt=1.0, vib=(6.5, 0.025), rng=rng, jitter=0.012)
        mix(x, voc, at, 0.45)
    t = 0.30
    for _ in range(9):
        cn = ns(0.09)
        c = [0.0] * cn
        src = biquad(noise(cn, rng), "bp", rng.uniform(1000.0, 1500.0), 1.3)
        for burst in range(3):
            o = ns(0.004 * burst)
            e = perc(cn - o, 0.0006, 0.035 if burst < 2 else 0.07)
            for i in range(cn - o):
                c[o + i] += src[o + i] * e[i] * (0.6 if burst < 2 else 1.0)
        mix(x, c, t, rng.uniform(0.40, 0.6))
        t += rng.uniform(0.085, 0.11)
    return finish(x, lp=6000.0, fade_out=0.1)


def suitcase(rng, v):
    """A bouncy hop: a springy rising 'boing' as the case jumps up, and a
    little wheel-clack bounce."""
    x = buf(0.48)
    hop = sine(0.26, lambda t: 210.0 * (2.4 ** min(1.0, t / 0.16)) * (1.0 + 0.06 * math.sin(TAU * 18.0 * t)),
               amp=lambda t: math.sin(math.pi * min(1.0, t / 0.26)) ** 0.7)
    harm = sine(0.26, lambda t: 2.0 * 210.0 * (2.4 ** min(1.0, t / 0.16)), amp=lambda t: math.sin(math.pi * min(1.0, t / 0.26)))
    mix(x, [a + 0.2 * b for a, b in zip(hop, harm)], 0.0, 0.7)
    for at, g in ((0.27, 1.0), (0.37, 0.5)):
        k = modal([(410.0, 0.06, 1.0), (980.0, 0.03, 0.3), (130.0, 0.07, 0.8)], 0.12)
        mix(x, k, at, 0.55 * g)
    return finish(x, lp=5500.0, fade_out=0.04)


def hurt_soft(rng, v):
    """The kid-mode hero hurt (Ajudas on): a soft 'oof' and a little boing.
    Surprised, not in pain."""
    x = buf(0.52)
    f0 = lambda t: 320.0 - 110.0 * min(1.0, t / 0.2)
    amp = lambda t: (math.sin(0.5 * math.pi * min(1.0, t / 0.02)) ** 2) * math.exp(-max(0.0, t - 0.05) / 0.08)
    voc = voice(0.24, f0, ((0.0, "oh"), (0.08, "oo"), (0.24, "oo")), amp, formant_scale=1.15,
                tilt=1.1, top=4500.0, vib=(6.0, 0.01), rng=rng, jitter=0.01)
    hn = ns(0.05)
    mix(x, breath(0.05, 1200.0, 0.8, [math.sin(math.pi * i / hn) ** 2 for i in range(hn)], rng), 0.0, 0.12)
    mix(x, voc, 0.012, 0.9)
    boing = sine(0.36, lambda t: 300.0 * (1.0 + 0.18 * math.exp(-t / 0.15) * math.sin(TAU * 15.0 * t)))
    mix(x, mul(boing, perc(len(boing), 0.006, 0.32)), 0.13, 0.35)
    return finish(x, lp=4500.0, fade_out=0.05)


def fall_whoosh(rng, v):
    """Falling out of a storybook level: a light airy whoosh, no splash. (The
    Douro splash is only for the bridge chapter, where there IS a river.)"""
    dur = 0.6
    n = ns(dur)
    x = biquad(noise(n, rng), "bp", lambda t: 1500.0 * (0.35 ** min(1.0, t / 0.5)), 0.8)
    env = [math.sin(0.5 * math.pi * min(1.0, (i / SR) / 0.10)) ** 2 * math.exp(-max(0.0, i / SR - 0.12) / 0.16)
           for i in range(n)]
    x = mul(x, env)
    tone = sine(dur, lambda t: 720.0 * (0.6 ** min(1.0, t / 0.5)), amp=lambda t: 0.08 * env[min(n - 1, ns(t))])
    mix(x, tone, 0.0, 1.0)
    return finish(x, lp=4500.0, fade_in=0.01, fade_out=0.06)


# id -> (designer, variants). Variant files are <id>_1.wav, <id>_2.wav, ...
SOUNDS = {
    "ui_tap": (ui_tap, 3),
    "page_turn": (page_turn, 1),
    "star": (star, 3),
    "objective_done": (objective_done, 1),
    "bubble_pop": (bubble_pop, 1),
    "cup_collect": (cup_collect, 1),
    "goblin_hit": (goblin_hit, 3),
    "goblin_giggle": (goblin_giggle, 3),
    "ball_kick": (ball_kick, 3),
    "rope_snap": (rope_snap, 1),
    "dragon_roar": (dragon_roar, 1),
    "dragon_fire": (dragon_fire, 1),
    "magic_repair": (magic_repair, 1),
    "panda_cheer": (panda_cheer, 1),
    "suitcase": (suitcase, 1),
    "hurt_soft": (hurt_soft, 1),
    "fall_whoosh": (fall_whoosh, 1),
}


def file_names(sid, count):
    if count == 1:
        return [sid + ".wav"]
    return ["%s_%d.wav" % (sid, k + 1) for k in range(count)]


def seed_of(sid, v):
    h = 0x5EED
    for ch in sid:
        h = (h * 131 + ord(ch)) & 0xFFFFFFFF
    return h ^ (v * 0x9E3779B1 & 0xFFFFFFFF)


def stats(x):
    pk = max(abs(v) for v in x)
    rms = math.sqrt(sum(v * v for v in x) / len(x))
    win = ns(0.1)
    best = 0.0
    for s in range(0, max(1, len(x) - win), win // 2):
        seg = x[s:s + win]
        best = max(best, math.sqrt(sum(v * v for v in seg) / len(seg)))
    return pk, rms, best


def main(only=None):
    os.makedirs(OUT_DIR, exist_ok=True)
    print("%-22s %6s %7s %7s %8s" % ("file", "sec", "bytes", "peak", "loud100"))
    ok = True
    for sid, (fn, count) in SOUNDS.items():
        if only and sid not in only:
            continue
        for v, name in enumerate(file_names(sid, count)):
            x = fn(random.Random(seed_of(sid, v)), v)
            path = os.path.join(OUT_DIR, name)
            write_wav(path, x)
            size = os.path.getsize(path)
            pk, rms, loud = stats(x)
            flag = "" if size <= MAX_BYTES else "  TOO BIG"
            ok = ok and size <= MAX_BYTES
            print("%-22s %6.2f %7d %6.1fdB %6.1fdB%s" % (name, len(x) / SR, size,
                  20 * math.log10(pk), 20 * math.log10(max(1e-9, loud)), flag))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(set(sys.argv[1:]) or None))
