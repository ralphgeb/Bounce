"""Synthesises Bricks' sounds into BounceApp/Sources/Sounds/*.wav. No samples: every sound is made here.

A calm, meditative palette, kept quiet and soft:
  - kalimba-like notes (a thumb piano: a warm tone with a faint metallic overtone that fades fast),
    tuned to A minor pentatonic so anything that overlaps sits well;
  - singing bowls (inharmonic partials, each a pair of slightly detuned tones that beat slowly,
    struck with a felt mallet) for moments;
  - breaths of air (soft low-passed noise) for movement;
  - tiny wooden clicks, water drops and a soft felt thump;
and everything goes through a small, gentle room reverb so nothing sounds dry or electronic.

Run from anywhere:  python3 BounceApp/tools/make_sounds.py
"""
import os
import wave

import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "Sources", "Sounds")
rng = np.random.default_rng(11)

# A minor pentatonic, low and warm: A3 C4 D4 E4 G4 A4 C5 D5 E5 G5 A5
SCALE = [220.00, 261.63, 293.66, 329.63, 392.00, 440.00, 523.25, 587.33, 659.25, 783.99, 880.00]


def t(d):
    return np.arange(int(SR * d)) / SR


def env(n, attack=0.004, decay=6.0):
    x = np.arange(n) / SR
    return np.clip(x / attack, 0, 1) * np.exp(-x * decay)


def lowpass(x, cutoff):
    """One-pole low-pass; cutoff may sweep (an array)."""
    cutoff = np.broadcast_to(np.asarray(cutoff, dtype=float), x.shape)
    a = 1 - np.exp(-2 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc += a[i] * (x[i] - acc)
        y[i] = acc
    return y


def soft(x, cutoff=3000, passes=2):
    for _ in range(passes):
        x = lowpass(x, cutoff)
    return x


# A small, soft room: a burst of noise that fades over about a second, darkened.
_ir_len = int(SR * 1.1)
_ir = soft(rng.standard_normal(_ir_len), 2200, 2) * np.exp(-np.arange(_ir_len) / SR * 4.2)
_ir /= np.sqrt(np.sum(_ir ** 2))


def room(x, wet=0.28):
    n = len(x) + len(_ir)
    size = 1 << (n - 1).bit_length()
    tail = np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(_ir, size), size)[:n]
    dry = np.concatenate([x, np.zeros(len(_ir))])
    tail *= np.max(np.abs(x)) / (np.max(np.abs(tail)) or 1)
    return dry * (1 - wet) + tail * wet


def fade_out(x, d=0.05):
    n = min(len(x), int(SR * d))
    x[-n:] *= np.linspace(1, 0, n) ** 2
    return x


def trim(x, floor=0.004):
    idx = np.nonzero(np.abs(x) > floor * np.max(np.abs(x)))[0]
    return x[: idx[-1] + 1] if len(idx) else x


def save(name, x, peak, reverb=0.28):
    x = np.asarray(x, dtype=float)
    if reverb > 0:
        x = room(x, reverb)
    x = trim(x)
    x = fade_out(x / (np.max(np.abs(x)) or 1) * peak)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())


def felt(n, cutoff=1800):
    """The soft knock of a felt mallet or a fingertip."""
    return soft(rng.standard_normal(n), cutoff) * env(n, 0.001, 140)


def kalimba(f, d=1.1):
    x = t(d)
    tone = np.sin(2 * np.pi * f * x) * env(len(x), 0.003, 4.5)
    warm = 0.25 * np.sin(2 * np.pi * f * 2.0 * x + 0.3) * env(len(x), 0.003, 7)
    metal = 0.12 * np.sin(2 * np.pi * f * 6.27 * x) * env(len(x), 0.001, 26)
    return tone + warm + metal + 0.25 * felt(len(x), 2400)


def bowl(f, d=2.4, strike=1.0):
    """A singing bowl: inharmonic partials, each a slowly beating pair."""
    x = t(d)
    y = np.zeros(len(x))
    for ratio, amp, dec, beat in [(1, 1.0, 1.1, 0.7), (2.71, 0.45, 1.8, 1.3), (5.15, 0.18, 3.0, 2.1), (8.2, 0.06, 5.0, 2.9)]:
        fr = f * ratio
        pair = np.sin(2 * np.pi * fr * x) + np.sin(2 * np.pi * (fr + beat) * x + 1.1)
        y += amp * 0.5 * pair * env(len(x), 0.008, dec)
    return y + 0.4 * strike * felt(len(x), 1500)


def breath(d=0.3, lo=350, hi=1300, rise=True, grain=0.0):
    """A soft breath of air: low-passed noise that swells and fades."""
    x = t(d)
    k = np.linspace(0, 1, len(x))
    sweep = lo + (hi - lo) * (k if rise else 1 - k)
    y = soft(rng.standard_normal(len(x)), sweep, 3)
    y -= soft(y, lo * 0.5, 1)                       # take away the rumble
    shape = np.sin(np.pi * k) ** 2
    if grain:
        y += grain * soft(rng.standard_normal(len(x)), hi * 1.5, 1) * shape
    return y * shape


def drop(f0, f1, d=0.32):
    """A water drop: a soft pitched blip that glides."""
    x = t(d)
    f = f1 + (f0 - f1) * np.exp(-x * 26)
    phase = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(phase) * env(len(x), 0.003, 11) + 0.08 * felt(len(x), 3000)


def wood(f=900, d=0.08):
    """A tiny wooden click."""
    x = t(d)
    body = np.sin(2 * np.pi * f * x) * env(len(x), 0.0008, 70)
    return body + 0.5 * felt(len(x), 4000)


def thump(f=70, d=0.6):
    x = t(d)
    fr = f * (1 + 0.5 * np.exp(-x * 30))
    body = np.sin(2 * np.pi * np.cumsum(fr) / SR) * env(len(x), 0.006, 7)
    return body + 0.3 * soft(rng.standard_normal(len(x)), 300) * env(len(x), 0.004, 12)


def pad(freqs, d=3.0, attack=0.6):
    x = t(d)
    y = sum(np.sin(2 * np.pi * f * x + i) + 0.5 * np.sin(2 * np.pi * (f + 0.6 + i * 0.2) * x)
            for i, f in enumerate(freqs))
    shape = np.clip(x / attack, 0, 1) ** 2 * np.exp(-np.clip(x - attack, 0, None) * 1.2)
    return soft(y, 2500, 1) * shape + 0.25 * breath(d, 300, 900) * 0.6


def mix(*parts):
    """Adds sounds of different lengths."""
    n = max(len(p) for p in parts)
    y = np.zeros(n)
    for p in parts:
        y[: len(p)] += p
    return y


def seq(items, gap, total):
    y = np.zeros(int(SR * total))
    for i, s in enumerate(items):
        start = int(SR * gap * i)
        end = min(len(y), start + len(s))
        y[start:end] += s[: end - start] * (0.82 ** i)
    return y


def main():
    os.makedirs(OUT, exist_ok=True)
    # Notes: kalimba across the scale; bowls an octave up for moments.
    for i, f in enumerate(SCALE):
        save(f"note{i:02d}", kalimba(f), 0.30)
        save(f"bell{i:02d}", bowl(f * 1.5), 0.24, reverb=0.32)

    # Interface: soft wooden clicks, nothing that rings.
    save("tap", wood(1100), 0.16, reverb=0.12)
    save("back", wood(760), 0.15, reverb=0.12)
    save("open", mix(wood(620, 0.1), 0.6 * wood(930, 0.1)), 0.17, reverb=0.15)
    save("tick", wood(1500, 0.05), 0.12, reverb=0.1)
    save("toggle", wood(1250, 0.06), 0.13, reverb=0.1)
    save("spring", drop(260, 360, 0.28), 0.12, reverb=0.15)

    # Movement: breaths of air.
    save("swish", breath(0.24, 380, 1100), 0.13, reverb=0.15)
    save("swish_long", breath(0.36, 320, 1300), 0.15, reverb=0.18)
    save("swish_soft", breath(0.2, 500, 1000, rise=False), 0.12, reverb=0.12)
    save("whoosh", breath(0.7, 220, 900), 0.18, reverb=0.25)

    # Touch and drops
    save("plip", drop(1250, 620), 0.2)
    save("plop", drop(520, 980, 0.28), 0.18)
    save("glass", mix(wood(1400, 0.07), 0.4 * drop(1800, 1500, 0.12)), 0.13, reverb=0.15)
    save("bump", thump(120, 0.22), 0.16, reverb=0.1)
    save("thud", thump(90, 0.35), 0.2, reverb=0.12)
    save("boom", mix(thump(55, 1.4), 0.3 * breath(1.4, 120, 400)), 0.3, reverb=0.35)

    # Moments
    save("reveal", pad([220, 329.63, 440, 493.88, 659.25], 3.0), 0.2, reverb=0.4)
    save("twinkle", seq([kalimba(SCALE[8] * 2, 0.6), kalimba(SCALE[9] * 2, 0.6), kalimba(SCALE[10] * 2, 0.8)], 0.07, 1.2), 0.12)
    save("power", bowl(SCALE[7] * 1.5, 2.2, 0.6), 0.2, reverb=0.35)
    save("clear", breath(0.45, 300, 1500, grain=0.15), 0.18, reverb=0.25)
    save("life", seq([kalimba(SCALE[i]) for i in (5, 7, 9, 10)], 0.11, 1.8), 0.24)
    save("lose", seq([kalimba(SCALE[4], 1.3), kalimba(SCALE[1], 1.6)], 0.22, 2.0), 0.22)
    save("over", seq([kalimba(SCALE[i], 1.6) for i in (5, 3, 1, 0)], 0.26, 2.8), 0.24)
    save("win", seq([bowl(SCALE[5] * 1.5, 3.5)] + [kalimba(SCALE[i] * 2, 0.9) for i in (5, 7, 8)], 0.16, 3.6), 0.24, reverb=0.35)
    save("star", bowl(SCALE[8], 2.4), 0.2, reverb=0.35)
    print("sounds written to", os.path.abspath(OUT))


if __name__ == "__main__":
    main()
