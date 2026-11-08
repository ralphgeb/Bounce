"""Draws Bounce's app icons: one square in the accent colour, in the centre of the look's background.

The square is lit from the top (a touch lighter at the top edge, deeper at the bottom), with a soft
shadow under it, so it sits a little above the background. Run from BounceApp/:  python3 tools/make_icon.py
"""
import json
import os

import numpy as np
from PIL import Image, ImageFilter

S = 1024
# id, light background, ink, accent: the same looks as Theme.swift
LOOKS = [
    ("Graphite", 0xF9F9F7, 0x121214, 0xFF6129),
    ("Ocean", 0xF4F7FA, 0x0E2A47, 0x1FC8B4),
    ("Sky", 0xEEF6FD, 0x33557A, 0x6FB6F2),
    ("Blush", 0xFDF2F6, 0x6B3A50, 0xF08BB0),
    ("Dusk", 0xF7F6FA, 0x2B2540, 0x8C7CF0),
    ("Forest", 0xF5F7F3, 0x1C3324, 0xE8B04A),
]


def rgb(h):
    return np.array([(h >> 16) & 255, (h >> 8) & 255, h & 255], dtype=float)


def mix(a, b, t):
    return a + (b - a) * t


def icon(bg_hex, ink_hex, accent_hex):
    bg, ink, acc = rgb(bg_hex), rgb(ink_hex), rgb(accent_hex)
    y, x = np.mgrid[0:S, 0:S].astype(float)

    # Background: the look's background, a touch deeper towards the bottom.
    t = (y / S)[..., None]
    img = mix(bg, mix(bg, ink, 0.07), t ** 1.6)

    half = 205                       # the square is 410 of 1024
    cx, cy = S / 2, S / 2 - 12

    # Soft shadow under the square, in the ink colour.
    shp = np.zeros((S, S))
    shp[(np.abs(x - cx) <= half - 10) & (np.abs(y - (cy + 34)) <= half - 6)] = 255
    sh = Image.fromarray(shp.astype(np.uint8)).filter(ImageFilter.GaussianBlur(38))
    a = (np.asarray(sh, dtype=float) / 255 * 0.26)[..., None]
    img = mix(img, ink, a)

    # The square: accent, lighter at the top, deeper at the bottom.
    ty = np.clip((y - (cy - half)) / (2 * half), 0, 1)[..., None]
    top_c = mix(acc, np.array([255.0, 255, 255]), 0.16)
    bot_c = acc * 0.86
    sq = mix(top_c, bot_c, ty)
    # A thin highlight along the top edge.
    hl = (np.clip(1 - (y - (cy - half)) / 10, 0, 1) * 0.25)[..., None]
    sq = mix(sq, np.array([255.0, 255, 255]), hl)

    # Antialiased edges.
    ex = np.clip(half - np.abs(x - cx) + 0.5, 0, 1)
    ey = np.clip(half - np.abs(y - cy) + 0.5, 0, 1)
    cover = (ex * ey)[..., None]
    img = mix(img, sq, cover)
    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGB")


def write_set(path, image, kind="appiconset"):
    os.makedirs(path, exist_ok=True)
    if kind == "appiconset":
        image.save(os.path.join(path, "icon-1024.png"))
        contents = {"images": [{"filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}]}
    else:
        image.resize((180, 180), Image.LANCZOS).save(os.path.join(path, "preview.png"))
        contents = {"images": [{"filename": "preview.png", "idiom": "universal"}]}
    contents["info"] = {"author": "xcode", "version": 1}
    with open(os.path.join(path, "Contents.json"), "w") as f:
        json.dump(contents, f, indent=2)


if __name__ == "__main__":
    out = "Sources/Assets.xcassets"
    for i, (name, bg, ink, acc) in enumerate(LOOKS):
        im = icon(bg, ink, acc)
        # Graphite is the main icon; the others are alternate icons chosen in Settings.
        write_set(f"{out}/AppIcon.appiconset" if i == 0 else f"{out}/AppIcon-{name}.appiconset", im)
        print("drew", name)
