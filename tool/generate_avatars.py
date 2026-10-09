#!/usr/bin/env python3
"""Draws a cartoon face for each flatmate, from a short description:

    Азамат   black hair, long black beard
    Аслан    black hair, short black beard, a slimmer face
    Мухаммад brown hair, beard, glasses
    Имран    glasses, no beard

Pure geometry, drawn at 4x and downsampled. Writes
assets/avatars/<latin name>.png; the app maps names to files in
lib/models/avatars.dart.

Usage:
    python3 tool/generate_avatars.py
    python3 tool/generate_avatars.py --preview sheet.png

Requires Pillow.
"""
import argparse
import os
import random

from PIL import Image, ImageChops, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIZE = 128
SS = 4
S = SIZE * SS

SKIN = (236, 196, 158, 255)
SKIN_SHADE = (214, 168, 128, 255)
BLACK_HAIR = (30, 27, 30, 255)
BROWN_HAIR = (104, 66, 38, 255)
EYE = (34, 26, 26, 255)
MOUTH = (120, 48, 44, 255)
FRAME = (28, 28, 36, 255)
CHEEK = (236, 140, 130, 90)

# Every face is drawn at the same size and height, sized so the longest
# beard still ends inside the disc. Only the face's width differs, where
# the description asks for a slimmer face.
FACE_SIZE = 0.88
FACE_CENTRE = 0.45

PEOPLE = [
    # file, background, hair, face width, beard, glasses
    ('azamat', (196, 160, 92, 255), BLACK_HAIR, 1.0, 'long', False),
    ('aslan', (74, 150, 140, 255), BLACK_HAIR, 0.78, 'short', False),
    ('muhammad', (132, 102, 176, 255), BROWN_HAIR, 1.0, 'medium', True),
    ('imran', (78, 128, 200, 255), BLACK_HAIR, 0.96, 'sparse', True),
]

# How much of the hair colour shows through each beard. Stubble is the same
# shape as a beard, only short and thin, so it is drawn see-through.
BEARD_OPACITY = {'long': 1.0, 'medium': 1.0, 'short': 1.0, 'stubble': 0.42}

# Beards short enough to follow the jaw rather than hang below the chin.
JAW_BEARDS = {'short', 'stubble'}


def ellipse(draw, cx, cy, rx, ry, **kw):
    draw.ellipse((cx - rx, cy - ry, cx + rx, cy + ry), **kw)


def face(background, hair, width, beard, glasses,
         size=FACE_SIZE, centre=FACE_CENTRE):
    image = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    cx, cy = S / 2, S * centre
    rx, ry = S * 0.30 * width * size, S * 0.34 * size

    # Hair behind the head, then the face over it.
    ellipse(draw, cx, cy - ry * 0.15, rx + S * 0.035, ry * 0.98, fill=hair)
    ellipse(draw, cx - rx, cy + ry * 0.02, S * 0.04, S * 0.06, fill=SKIN_SHADE)
    ellipse(draw, cx + rx, cy + ry * 0.02, S * 0.04, S * 0.06, fill=SKIN_SHADE)
    ellipse(draw, cx, cy, rx, ry, fill=SKIN)

    # The top of the hair, then the forehead cut back into it, which gives
    # a rounded hairline instead of a flat fringe.
    ellipse(draw, cx, cy - ry * 0.55, rx + S * 0.02, ry * 0.55, fill=hair)
    ellipse(draw, cx + rx * 0.04, cy - ry * 0.06, rx * 0.84, ry * 0.58,
            fill=SKIN)

    brow_y = cy - ry * 0.22
    eye_y = cy - ry * 0.06
    eye_dx = rx * 0.40

    if beard and beard != 'sparse':
        top, depth = {
            'long': (0.16, ry + S * 0.16),
            'medium': (0.18, ry + S * 0.035),
            'short': (0.30, ry * 0.70),
            'stubble': (0.26, ry * 0.76),
        }[beard]
        by = cy + ry * top
        layer = Image.new('RGBA', (S, S), (0, 0, 0, 0))
        ld = ImageDraw.Draw(layer)
        clear = (0, 0, 0, 0)
        ld.chord((cx - rx, by - depth, cx + rx, by + depth), 0, 180, fill=hair)
        # Sideburns joining beard to hair.
        for side in (-1, 1):
            x0 = cx + side * rx
            x1 = cx + side * (rx - S * 0.05)
            ld.polygon([(x0, cy - ry * 0.35), (x1, cy - ry * 0.35),
                        (x1, by + S * 0.02), (x0, by + S * 0.02)], fill=hair)
        # Cheeks cut out of the beard's top edge, so it starts in a curve
        # along the cheekbones instead of a straight line like a mask.
        for side in (-1, 1):
            ellipse(ld, cx + side * rx * 0.45, by, rx * 0.42, ry * 0.15,
                    fill=clear)
        # A clear patch round the mouth, then the moustache over it.
        ellipse(ld, cx, cy + ry * 0.42, rx * 0.30, ry * 0.12, fill=clear)
        for side in (-1, 1):
            ellipse(ld, cx + side * rx * 0.17, cy + ry * 0.29,
                    rx * 0.20, ry * 0.075, fill=hair)
        # Keep the face's own outline: nothing of the beard outside the
        # jaw except what hangs below the chin.
        opacity = BEARD_OPACITY[beard]
        alpha = layer.getchannel('A').point(lambda a: int(a * opacity))
        if beard in JAW_BEARDS:
            # A short beard grows on the face, never past it: clip to the
            # face's own outline.
            jaw = Image.new('L', (S, S), 0)
            ellipse(ImageDraw.Draw(jaw), cx, cy, rx, ry, fill=255)
            alpha = ImageChops.multiply(alpha, jaw)
        layer.putalpha(alpha)
        image.alpha_composite(layer)
    else:
        cheeks = Image.new('RGBA', (S, S), (0, 0, 0, 0))
        cheek_draw = ImageDraw.Draw(cheeks)
        for side in (-1, 1):
            ellipse(cheek_draw, cx + side * rx * 0.58, cy + ry * 0.22,
                    rx * 0.16, ry * 0.08, fill=CHEEK)
        image.alpha_composite(cheeks)

    if beard == 'sparse':
        # A few short hairs scattered along the jaw and chin: very sparse
        # stubble. Seeded, so every run draws the same face.
        rng = random.Random(7)
        hairs = Image.new('RGBA', (S, S), (0, 0, 0, 0))
        hd = ImageDraw.Draw(hairs)
        colour = hair[:3] + (150,)
        placed = 0
        while placed < 26:
            x = cx + rng.uniform(-1, 1) * rx * 0.92
            y = cy + rng.uniform(0.22, 0.95) * ry
            inside = ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 < 0.86
            near_mouth = abs(x - cx) < rx * 0.32 and abs(y - (cy + ry * 0.38)) < ry * 0.12
            near_cheek = (abs(abs(x - cx) - rx * 0.58) < rx * 0.2
                          and abs(y - (cy + ry * 0.22)) < ry * 0.1)
            if not inside or near_mouth or near_cheek:
                continue
            tilt = rng.uniform(-0.5, 0.5)
            length = S * 0.016
            hd.line((x, y, x + length * tilt, y + length), fill=colour,
                    width=max(1, int(S * 0.006)))
            placed += 1
        image.alpha_composite(hairs)

    # Smile.
    draw.arc((cx - rx * 0.26, cy + ry * 0.24, cx + rx * 0.26, cy + ry * 0.52),
             15, 165, fill=MOUTH, width=int(S * 0.022))

    # Nose.
    draw.arc((cx - rx * 0.10, cy + ry * 0.02, cx + rx * 0.10, cy + ry * 0.20),
             20, 160, fill=SKIN_SHADE, width=int(S * 0.016))

    # Eyes with a glint, and brows.
    for side in (-1, 1):
        ex = cx + side * eye_dx
        ellipse(draw, ex, eye_y, S * 0.032, S * 0.036, fill=EYE)
        ellipse(draw, ex + S * 0.010, eye_y - S * 0.012, S * 0.010, S * 0.010,
                fill=(255, 255, 255, 255))
        draw.line((ex - S * 0.06, brow_y + side * S * 0.004,
                   ex + S * 0.06, brow_y - side * S * 0.004),
                  fill=hair, width=int(S * 0.024))

    if glasses:
        lens = S * 0.085
        for side in (-1, 1):
            ex = cx + side * eye_dx
            tint = Image.new('RGBA', (S, S), (0, 0, 0, 0))
            ellipse(ImageDraw.Draw(tint), ex, eye_y, lens, lens * 0.88,
                    fill=(255, 255, 255, 45))
            image.alpha_composite(tint)
            ellipse(draw, ex, eye_y, lens, lens * 0.88,
                    outline=FRAME, width=int(S * 0.018))
            draw.line((cx + side * (eye_dx + lens), eye_y,
                       cx + side * rx, eye_y - S * 0.01),
                      fill=FRAME, width=int(S * 0.016))
        draw.arc((cx - eye_dx + lens - S * 0.01, eye_y - S * 0.04,
                  cx + eye_dx - lens + S * 0.01, eye_y + S * 0.03),
                 200, 340, fill=FRAME, width=int(S * 0.016))

    # Everything inside a coloured disc.
    disc = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(disc).ellipse((0, 0, S - 1, S - 1), fill=background)
    mask = Image.new('L', (S, S), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, S - 1, S - 1), fill=255)
    clipped = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    clipped.paste(image, (0, 0), mask)
    disc.alpha_composite(clipped)
    return disc.resize((SIZE, SIZE), Image.LANCZOS)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--preview', help='write all four side by side here')
    args = parser.parse_args()

    faces = [(p[0], face(*p[1:])) for p in PEOPLE]
    if args.preview:
        sheet = Image.new('RGBA', (SIZE * 4 * 2 + 30, SIZE * 2 + 20),
                          (20, 19, 24, 255))
        for i, (_, img) in enumerate(faces):
            big = img.resize((SIZE * 2, SIZE * 2), Image.LANCZOS)
            sheet.alpha_composite(big, (10 + i * (SIZE * 2 + 3), 10))
        sheet.save(args.preview)
        return

    for name, img in faces:
        path = os.path.join(ROOT, 'assets', 'avatars', f'{name}.png')
        os.makedirs(os.path.dirname(path), exist_ok=True)
        img.save(path, optimize=True)
        print('wrote', os.path.relpath(path, ROOT))


if __name__ == '__main__':
    main()
