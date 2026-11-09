"""Synthesises Bricks' sounds into BounceApp/Sources/Sounds/*.wav. No samples: every sound is made here.

A calm, meditative palette of soft thuds rather than chimes, kept quiet:
  - pitched "thocks" (a felt-damped wood block: a short warm knock with a pitch that falls quickly),
    tuned to A minor pentatonic so a run of them makes a gentle little melody;
  - warm, deeper thuds for moments (stars, power-ups, the end of a level);
  - a dull, hollow key click (like a keyboard's delete key) for the menu, and a short rubbery thup
    when a stretched logo springs back;
  - breaths of air for movement, water drops for the dots, a deep felt thump for big clears;
and a little room around everything so nothing sounds dry. (Earlier palette notes kept below.)

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


def thock(f, d=0.22, decay=24, noise=0.55):
    """A soft knock with a little pitch: like a felt-damped wood block."""
    x = t(d)
    fr = f * (1 + 0.7 * np.exp(-x * 70))
    phase = 2 * np.pi * np.cumsum(fr) / SR
    tone = np.sin(phase) * env(len(x), 0.0012, decay)
    under = 0.45 * np.sin(phase / 2) * env(len(x), 0.002, decay * 1.2)
    knock = noise * soft(rng.standard_normal(len(x)), 2200, 2) * env(len(x), 0.0005, 260)
    return tone + under + knock


def key_click(f=430, d=0.1):
    """A dull, hollow key click, like a keyboard's delete key."""
    x = t(d)
    body = np.sin(2 * np.pi * f * x) * env(len(x), 0.0006, 55)
    hollow = 0.5 * np.sin(2 * np.pi * f * 2.4 * x) * env(len(x), 0.0004, 120)
    snap = 0.8 * soft(rng.standard_normal(len(x)), 3500, 1) * env(len(x), 0.0003, 600)
    return body + hollow + snap


def rubber(d=0.2):
    """A short rubbery thup: a low knock that wobbles for a moment."""
    x = t(d)
    fr = 150 * (1 + 0.25 * np.sin(2 * np.pi * 26 * x) * np.exp(-x * 30)) * (1 + 0.4 * np.exp(-x * 50))
    body = np.sin(2 * np.pi * np.cumsum(fr) / SR) * env(len(x), 0.003, 22)
    return body + 0.3 * soft(rng.standard_normal(len(x)), 900, 2) * env(len(x), 0.001, 150)


def warm(f, d=0.9):
    """A warm, deeper thud with just a breath of tone after it: for moments."""
    x = t(d)
    fr = f * (1 + 0.5 * np.exp(-x * 40))
    phase = 2 * np.pi * np.cumsum(fr) / SR
    body = np.sin(phase) * env(len(x), 0.002, 9) + 0.35 * np.sin(phase * 2.01) * env(len(x), 0.002, 16)
    return body + 0.5 * soft(rng.standard_normal(len(x)), 1200, 2) * env(len(x), 0.001, 90)


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
    # Notes: soft pitched thocks across the scale (an octave down: warmer); and warm thuds for moments.
    for i, f in enumerate(SCALE):
        save(f"note{i:02d}", thock(f), 0.32, reverb=0.14)
        save(f"bell{i:02d}", warm(f * 0.75), 0.3, reverb=0.2)

    # Interface: key clicks and knocks, nothing that rings.
    save("tap", key_click(560, 0.08), 0.15, reverb=0.08)
    save("back", key_click(380, 0.09), 0.15, reverb=0.08)
    save("open", key_click(330, 0.11), 0.2, reverb=0.1)        # opening a game: the delete-key click
    save("tick", key_click(700, 0.06), 0.11, reverb=0.06)
    save("toggle", key_click(520, 0.07), 0.13, reverb=0.06)
    save("spring", rubber(), 0.17, reverb=0.08)                 # a stretched logo springs back

    # Movement: breaths of air (quiet).
    save("swish", breath(0.22, 360, 1000), 0.11, reverb=0.1)
    save("swish_long", breath(0.34, 300, 1150), 0.13, reverb=0.12)
    save("swish_soft", breath(0.18, 480, 950, rise=False), 0.1, reverb=0.08)
    save("whoosh", breath(0.6, 200, 800), 0.15, reverb=0.18)

    # Touch and drops
    save("plip", drop(820, 420, 0.24), 0.18, reverb=0.16)        # a dot dropped
    save("plop", drop(380, 700, 0.22), 0.16, reverb=0.16)        # a dot picked up
    save("glass", thock(880, 0.14, 40), 0.12, reverb=0.1)        # hint
    save("bump", thump(120, 0.2), 0.15, reverb=0.06)
    save("thud", thump(90, 0.3), 0.2, reverb=0.08)
    save("boom", mix(thump(55, 1.2), 0.3 * breath(1.2, 120, 380)), 0.3, reverb=0.25)

    # Moments: thuds, not chimes.
    save("reveal", mix(warm(110, 1.2), 0.5 * breath(1.6, 200, 700)), 0.2, reverb=0.3)
    save("twinkle", seq([thock(SCALE[i] * 2, 0.16, 34) for i in (6, 8, 10)], 0.07, 0.6), 0.1, reverb=0.12)
    save("power", seq([warm(SCALE[2] * 0.75, 0.6), thock(SCALE[7], 0.25)], 0.06, 0.9), 0.22, reverb=0.2)
    save("clear", mix(breath(0.4, 260, 1100), 0.5 * thump(80, 0.3)), 0.18, reverb=0.18)
    save("life", seq([thock(SCALE[i]) for i in (5, 7, 9, 10)], 0.1, 0.9), 0.24, reverb=0.16)
    save("lose", seq([thock(SCALE[4], 0.4, 14), thock(SCALE[1], 0.6, 10)], 0.2, 1.1), 0.22, reverb=0.18)
    save("over", seq([thock(SCALE[i], 0.5, 11) for i in (5, 3, 1, 0)], 0.24, 1.8), 0.24, reverb=0.2)
    save("win", seq([warm(110, 1.2)] + [thock(SCALE[i]) for i in (5, 7, 8, 10)], 0.12, 1.6), 0.24, reverb=0.25)
    save("star", warm(SCALE[5] * 0.5, 0.9), 0.22, reverb=0.2)
    print("sounds written to", os.path.abspath(OUT))


if __name__ == "__main__":
    main()
