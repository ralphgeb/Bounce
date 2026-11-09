"""Synthesises Bricks' sounds into BounceApp/Sources/Sounds/*.wav. No samples: every sound is made here.

The palette is calm and minimal: soft marimba and bell notes tuned to one scale (A minor pentatonic,
so any notes played together sit well), airy swishes of filtered noise, water-drop plips, a soft
thud and boom, and a slow shimmering pad. Everything is quiet, rounded and short.

Run from anywhere:  python3 BounceApp/tools/make_sounds.py
"""
import os
import wave

import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "Sources", "Sounds")
rng = np.random.default_rng(7)

# A minor pentatonic from A3 up two octaves and a bit: A C D E G A C D E G A
SCALE = [220.00, 261.63, 293.66, 329.63, 392.00, 440.00, 523.25, 587.33, 659.25, 783.99, 880.00]


def t(d):
    return np.arange(int(SR * d)) / SR


def env(n, attack=0.004, decay=6.0):
    x = np.arange(n) / SR
    a = np.clip(x / attack, 0, 1)
    return a * np.exp(-x * decay)


def lowpass(x, cutoff):
    # one-pole low-pass (cutoff may be an array, for sweeps)
    cutoff = np.broadcast_to(cutoff, x.shape)
    y = np.zeros_like(x)
    acc = 0.0
    for i in range(len(x)):
        a = 1 - np.exp(-2 * np.pi * cutoff[i] / SR)
        acc += a * (x[i] - acc)
        y[i] = acc
    return y


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def fade_out(x, d=0.02):
    n = min(len(x), int(SR * d))
    x[-n:] *= np.linspace(1, 0, n)
    return x


def save(name, x, peak=0.5):
    x = np.asarray(x, dtype=float)
    m = np.max(np.abs(x)) or 1
    x = fade_out(x / m * peak)
    data = (x * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(data.tobytes())


def marimba(f, d=0.55):
    x = t(d)
    body = np.sin(2 * np.pi * f * x) * env(len(x), 0.002, 7)
    tone = 0.35 * np.sin(2 * np.pi * f * 4 * x) * env(len(x), 0.001, 30)     # the wooden "tock"
    under = 0.15 * np.sin(2 * np.pi * f * 0.5 * x) * env(len(x), 0.004, 9)
    click = 0.05 * rng.standard_normal(len(x)) * env(len(x), 0.0005, 400)
    return body + tone + under + click


def bell(f, d=1.4):
    x = t(d)
    parts = [(1, 1.0, 2.6), (2.76, 0.35, 5), (5.4, 0.15, 9), (8.9, 0.06, 14)]
    y = sum(a * np.sin(2 * np.pi * f * r * x) * env(len(x), 0.003, dec) for r, a, dec in parts)
    return y * (1 + 0.02 * np.sin(2 * np.pi * 5 * x))     # a breath of shimmer


def swish(d=0.28, lo=500, hi=3200, rise=True):
    x = t(d)
    noise = rng.standard_normal(len(x))
    k = np.linspace(0, 1, len(x))
    sweep = lo + (hi - lo) * (k if rise else 1 - k)
    y = highpass(lowpass(noise, sweep), lo * 0.6)
    shape = np.sin(np.pi * np.clip(k, 0, 1)) ** 1.6
    return y * shape


def plip(f0, f1, d=0.22):
    x = t(d)
    f = f1 + (f0 - f1) * np.exp(-x * 30)
    phase = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(phase) * env(len(x), 0.002, 14) + 0.2 * np.sin(2 * phase) * env(len(x), 0.001, 30)


def thud(f=95, d=0.25):
    x = t(d)
    f_ = f * (1 + 0.6 * np.exp(-x * 40))
    phase = 2 * np.pi * np.cumsum(f_) / SR
    body = np.sin(phase) * env(len(x), 0.002, 18)
    knock = lowpass(rng.standard_normal(len(x)), 900) * env(len(x), 0.001, 60) * 0.6
    return body + knock


def pad(freqs, d=2.2, attack=0.35):
    x = t(d)
    y = sum(np.sin(2 * np.pi * f * x + i) * (1 + 0.004 * np.sin(2 * np.pi * (0.3 + i * 0.1) * x)) for i, f in enumerate(freqs))
    shape = np.clip(x / attack, 0, 1) * np.exp(-np.clip(x - attack, 0, None) * 1.6)
    air = lowpass(rng.standard_normal(len(x)), 2500) * 0.04
    return (y + air) * shape


def chord(notes, gap=0.07, maker=bell, d=1.6):
    total = int(SR * (d + gap * len(notes)))
    y = np.zeros(total)
    for i, f in enumerate(notes):
        s = maker(f)
        start = int(SR * gap * i)
        y[start:start + len(s)] += s[: total - start] * (0.85 ** i)
    return y


def main():
    os.makedirs(OUT, exist_ok=True)
    # Notes: marimba and bell across the scale
    for i, f in enumerate(SCALE):
        save(f"note{i:02d}", marimba(f), 0.42)
        save(f"bell{i:02d}", bell(f * 2), 0.32)

    # Interface
    save("tap", marimba(1320, 0.12) * env(int(SR * 0.12), 0.001, 40), 0.22)
    save("back", marimba(660, 0.14) * env(int(SR * 0.14), 0.001, 35), 0.2)
    save("open", chord([SCALE[5] * 2, SCALE[7] * 2], gap=0.06, d=0.9), 0.26)
    save("spring", plip(300, 520, 0.32) * 0.8 + 0.4 * plip(520, 360, 0.32), 0.18)
    save("toggle", plip(900, 1400, 0.09), 0.18)

    # Movement
    save("swish", swish(0.26, 500, 2600), 0.28)
    save("swish_long", swish(0.42, 400, 3000), 0.3)
    save("swish_soft", swish(0.2, 700, 2000, rise=False), 0.18)
    save("whoosh", swish(0.6, 250, 1800), 0.3)

    # Touch and drops
    save("plip", plip(1500, 700), 0.32)            # a dot dropped
    save("plop", plip(600, 1250, 0.2), 0.3)        # a dot picked up
    save("tick", plip(2400, 1800, 0.05), 0.16)
    save("glass", bell(1760, 0.5) * env(int(SR * 0.5), 0.001, 9), 0.22)
    save("thud", thud(), 0.34)
    save("bump", thud(140, 0.16), 0.22)
    save("boom", thud(60, 0.9) + 0.5 * lowpass(rng.standard_normal(int(SR * 0.9)), 400) * env(int(SR * 0.9), 0.01, 4), 0.42)

    # Moments
    save("reveal", pad([220, 277.18, 329.63, 440, 554.37], 2.4), 0.3)    # the whole maze shows
    save("twinkle", chord([SCALE[8] * 2, SCALE[9] * 2, SCALE[10] * 2], gap=0.05, d=0.8), 0.18)
    save("power", chord([SCALE[5] * 2, SCALE[7] * 2, SCALE[9] * 2], gap=0.045, d=1.0), 0.26)
    save("clear", swish(0.35, 600, 3500) * 0.7, 0.3)
    save("life", chord([SCALE[5], SCALE[7], SCALE[9], SCALE[10]], gap=0.08, maker=marimba, d=0.6), 0.34)
    save("lose", chord([SCALE[4], SCALE[1]], gap=0.16, maker=marimba, d=0.7), 0.3)
    save("over", chord([SCALE[5], SCALE[3], SCALE[1], SCALE[0]], gap=0.18, maker=marimba, d=0.9), 0.32)
    save("win", chord([SCALE[5], SCALE[6], SCALE[8], SCALE[10], SCALE[10] * 1.5], gap=0.09, d=1.8), 0.32)
    save("star", bell(SCALE[8] * 2, 1.2), 0.3)
    print("sounds written to", os.path.abspath(OUT))


if __name__ == "__main__":
    main()
