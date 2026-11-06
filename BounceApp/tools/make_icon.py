"""Draws Bounce's app icons: one ball in the centre of the look's background, with depth.

The ball is lit from the top left (a soft highlight and a darker rim), with a small shine
and a blurred shadow on the ground under it. Run from BounceApp/:  python3 tools/make_icon.py
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
    ("Forest", 0xF5F7F3, 0x1C3324, 0xE8B04A),
    ("Dusk", 0xF7F6FA, 0x2B2540, 0xFF8A65),
    ("Mono", 0xFFFFFF, 0x000000, 0xE5484D),
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

    cx, cy, r = S / 2, S / 2 - 10, 200

    # Shadow on the ground under the ball: a blurred ellipse in the ink colour.
    sh = Image.new("L", (S, S), 0)
    shp = np.zeros((S, S))
    ex, ey, rx, ry = cx, cy + r + 58, r * 0.92, r * 0.2
    shp[((x - ex) / rx) ** 2 + ((y - ey) / ry) ** 2 <= 1] = 255
    sh = Image.fromarray(shp.astype(np.uint8)).filter(ImageFilter.GaussianBlur(34))
    a = (np.asarray(sh, dtype=float) / 255 * 0.30)[..., None]
    img = mix(img, ink, a)

    # The ball: lit from the top left.
    dx, dy = (x - cx) / r, (y - cy) / r
    d2 = dx * dx + dy * dy
    inside = d2 <= 1
    nz = np.sqrt(np.clip(1 - d2, 0, 1))
    lx, ly, lz = -0.45, -0.55, 0.70
    n = np.sqrt(lx * lx + ly * ly + lz * lz)
    lx, ly, lz = lx / n, ly / n, lz / n
    lam = np.clip(dx * lx + dy * ly + nz * lz, 0, 1)[..., None]
    light = mix(acc, np.array([255.0, 255, 255]), 0.38)
    dark = acc * 0.62
    ball = np.where(lam > 0.62, mix(acc, light, (lam - 0.62) / 0.38), mix(dark, acc, lam / 0.62))
    # A little light bouncing back from the ground onto the bottom edge.
    rim = np.clip((dy - 0.55) / 0.45, 0, 1)[..., None] * np.clip(1 - nz * 1.4, 0, 1)[..., None]
    ball = mix(ball, mix(acc, bg, 0.4), rim * 0.45)
    # Shine: a soft white spot.
    hx, hy = cx - r * 0.38, cy - r * 0.42
    sd = np.sqrt((x - hx) ** 2 + (y - hy) ** 2) / (r * 0.28)
    shine = (np.clip(1 - sd, 0, 1) ** 2 * 0.55)[..., None]
    ball = mix(ball, np.array([255.0, 255, 255]), shine)

    # Antialiased edge.
    edge = np.clip((r - np.sqrt((x - cx) ** 2 + (y - cy) ** 2)) + 0.5, 0, 1)[..., None]
    img = np.where(inside[..., None] | (edge > 0), mix(img, ball, edge), img)
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
        write_set(f"{out}/IconPreview-{name}.imageset", im, "imageset")
        print("drew", name)
