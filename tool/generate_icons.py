#!/usr/bin/env python3
"""Draws the Общак icon: a tenge coin with the four flatmates around it.

The mark is pure geometry plus one glyph, so it can be re-rendered at any
size without a source image. Everything is drawn at 4x and downsampled to
keep the edges clean.

Writes the web set (favicon, PWA icons, maskable icons, the iOS home-screen
icon) and assets/obshak_mark.png, the mark the app itself shows.

Usage:
    python3 tool/generate_icons.py
    python3 tool/generate_icons.py --preview out.png

Requires Pillow.
"""
import argparse
import math
import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT = os.path.join(ROOT, 'fonts', 'Onest-Bold.ttf')

OBSIDIAN = (20, 19, 24, 255)       # #141318, the app's background
CHAMPAGNE = (200, 168, 107, 255)   # #C8A86B, the app's gold
SUPERSAMPLE = 4


def draw_mark(size, *, plate, rounded, scale=1.0, seats=True):
    """The mark on a [size] square.

    [plate] paints the obsidian background; without it the mark stands on
    transparency. [rounded] gives the plate soft corners (not for maskable
    icons, which the platform crops itself). [scale] shrinks the mark
    toward the centre, for the maskable safe zone.
    """
    big = size * SUPERSAMPLE
    image = Image.new('RGBA', (big, big), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)

    if plate:
        if rounded:
            draw.rounded_rectangle(
                (0, 0, big - 1, big - 1), radius=int(big * 0.22), fill=OBSIDIAN)
        else:
            draw.rectangle((0, 0, big, big), fill=OBSIDIAN)

    centre = big / 2
    unit = big * scale

    # The shared pot: one coin in the middle, with an inner rim.
    coin = unit * 0.25
    draw.ellipse(
        (centre - coin, centre - coin, centre + coin, centre + coin),
        fill=CHAMPAGNE)
    ring = unit * 0.205
    draw.ellipse(
        (centre - ring, centre - ring, centre + ring, centre + ring),
        outline=OBSIDIAN, width=max(1, int(unit * 0.018)))

    font = ImageFont.truetype(FONT, int(unit * 0.27))
    draw.text((centre, centre + unit * 0.01), '₸', font=font,
              fill=OBSIDIAN, anchor='mm')

    # The four flatmates, one at each corner around it.
    if not seats:
        return image.resize((size, size), Image.LANCZOS)
    seat = unit * 0.075
    reach = unit * 0.37
    for quarter in range(4):
        angle = math.radians(45 + 90 * quarter)
        x = centre + reach * math.cos(angle)
        y = centre + reach * math.sin(angle)
        draw.ellipse((x - seat, y - seat, x + seat, y + seat), fill=CHAMPAGNE)

    return image.resize((size, size), Image.LANCZOS)


def write(relative, image):
    path = os.path.join(ROOT, relative)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    image.save(path, optimize=True)
    print('wrote', relative)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--preview', help='write one 512px icon here and stop')
    args = parser.parse_args()

    if args.preview:
        draw_mark(512, plate=True, rounded=True).save(args.preview)
        return

    write('web/favicon.png', draw_mark(32, plate=True, rounded=True))
    write('web/icons/Icon-192.png', draw_mark(192, plate=True, rounded=True))
    write('web/icons/Icon-512.png', draw_mark(512, plate=True, rounded=True))
    # Maskable: full-bleed plate, mark kept inside the 80% safe zone.
    write('web/icons/Icon-maskable-192.png',
          draw_mark(192, plate=True, rounded=False, scale=0.8))
    write('web/icons/Icon-maskable-512.png',
          draw_mark(512, plate=True, rounded=False, scale=0.8))
    # iOS rounds the corners itself and shows transparency as black.
    write('web/icons/apple-touch-icon-180.png',
          draw_mark(180, plate=True, rounded=False))
    write('assets/obshak_mark.png', draw_mark(256, plate=False, rounded=False))
    # The coin alone, for the loading animation the four faces circle.
    coin = draw_mark(256, plate=False, rounded=False, scale=2.0, seats=False)
    write('assets/coin.png', coin)
    write('web/icons/coin.png', coin.resize((128, 128), Image.LANCZOS))


if __name__ == '__main__':
    main()
