#!/usr/bin/env python3
"""Generate a purple swirled music note icon for Sixth."""

import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter
from scipy import ndimage

SIZE = 1024
CENTER = SIZE // 2

def make_music_note(size):
    """Render a music note character on a transparent canvas."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Try to find a good font with music note glyphs
    note_char = "\u266B"  # ♫ (beamed eighth notes)
    font_size = int(size * 0.75)

    font_paths = [
        "/System/Library/Fonts/Apple Color Emoji.ttc",
        "/System/Library/Fonts/Helvetica.ttc",
        "/System/Library/Fonts/SFNSText.ttf",
        "/Library/Fonts/Arial Unicode.ttf",
    ]

    font = None
    for path in font_paths:
        try:
            font = ImageFont.truetype(path, font_size)
            break
        except (OSError, IOError):
            continue

    if font is None:
        font = ImageFont.load_default()

    # Get bounding box and center the note
    bbox = draw.textbbox((0, 0), note_char, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    x = (size - tw) // 2 - bbox[0]
    y = (size - th) // 2 - bbox[1]

    # Draw the note in white (we'll colorize later)
    draw.text((x, y), note_char, fill=(255, 255, 255, 255), font=font)
    return img


def colorize_purple(img):
    """Replace white pixels with bright purple, preserving alpha."""
    data = np.array(img, dtype=np.float64)
    # Bright purple: (155, 48, 255) — a vivid blue-purple
    purple = np.array([155, 48, 255], dtype=np.float64)

    # Use the luminance of the original as intensity
    lum = data[:, :, :3].mean(axis=2) / 255.0
    for c in range(3):
        data[:, :, c] = lum * purple[c]

    return Image.fromarray(data.astype(np.uint8), "RGBA")


def apply_swirl(img, strength=12, radius=None):
    """Apply a swirl distortion centered on the image."""
    if radius is None:
        radius = SIZE * 0.45

    data = np.array(img)
    h, w = data.shape[:2]
    cy, cx = h / 2, w / 2

    # Build coordinate grids
    y_coords, x_coords = np.mgrid[0:h, 0:w]
    dx = x_coords - cx
    dy = y_coords - cy
    r = np.sqrt(dx**2 + dy**2)
    theta = np.arctan2(dy, dx)

    # Swirl angle falls off with distance from center
    falloff = np.exp(-(r / radius) ** 2)
    swirl_angle = strength * falloff

    new_theta = theta + swirl_angle
    new_x = cx + r * np.cos(new_theta)
    new_y = cy + r * np.sin(new_theta)

    # Remap each channel
    result = np.zeros_like(data)
    for c in range(data.shape[2]):
        result[:, :, c] = ndimage.map_coordinates(
            data[:, :, c], [new_y, new_x], order=1, mode="constant", cval=0
        )

    return Image.fromarray(result, "RGBA")


def add_glow_background(img):
    """Add a subtle purple radial glow behind the note."""
    bg = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(bg)

    # Radial gradient — concentric circles fading out
    for i in range(SIZE // 2, 0, -2):
        t = i / (SIZE // 2)  # 1.0 at center, 0.0 at edge
        alpha = int(60 * (t ** 2))
        r = int(80 * t + 20)
        g = int(10 * t)
        b = int(140 * t + 40)
        draw.ellipse(
            [CENTER - i, CENTER - i, CENTER + i, CENTER + i],
            fill=(r, g, b, alpha),
        )

    # Composite: glow behind, swirled note on top
    bg.paste(img, (0, 0), img)
    return bg


def draw_beamed_notes(draw, cx, cy, scale, color):
    """Draw a beamed eighth note pair (♫) centered at (cx, cy).

    scale=1.0 means note heads are ~30px radius. Adjust for size.
    """
    s = scale
    head_rx = int(26 * s)
    head_ry = int(20 * s)
    stem_w = int(8 * s)
    stem_h = int(100 * s)
    beam_h = int(12 * s)
    spacing = int(50 * s)  # horizontal distance between note centers

    # Two note heads, centered around (cx, cy) at the bottom
    left_x = cx - spacing // 2
    right_x = cx + spacing // 2
    head_y = cy + int(30 * s)  # note heads near bottom

    # Note heads (filled tilted ellipses)
    for nx in [left_x, right_x]:
        draw.ellipse(
            [nx - head_rx, head_y - head_ry, nx + head_rx, head_y + head_ry],
            fill=color,
        )

    # Stems (right side of each note head, going up)
    stem_top = head_y - stem_h
    for nx in [left_x, right_x]:
        stem_x = nx + head_rx - stem_w // 2
        draw.rectangle(
            [stem_x, stem_top, stem_x + stem_w, head_y],
            fill=color,
        )

    # Beam connecting the two stems at top
    left_stem_x = left_x + head_rx - stem_w // 2
    right_stem_x = right_x + head_rx + stem_w // 2
    draw.rectangle(
        [left_stem_x, stem_top, right_stem_x, stem_top + beam_h],
        fill=color,
    )


def make_center_note(size, color, note_scale=1.0):
    """Render a beamed note pair in a given color, centered on a full-size canvas."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw_beamed_notes(draw, size // 2, size // 2, note_scale, color)
    return img


def main():
    print("Rendering music note...")
    note = make_music_note(SIZE)

    print("Colorizing purple...")
    purple_note = colorize_purple(note)

    print("Applying swirl effect...")
    swirled = apply_swirl(purple_note, strength=10, radius=SIZE * 0.4)

    print("Adding glow background...")
    final = add_glow_background(swirled)

    # Add two center notes offset like a drop shadow: red behind, blue in front
    offset = int(SIZE * 0.035)  # shadow offset
    print("Adding center notes (red + blue)...")
    red_note = make_center_note(SIZE, (220, 50, 80, 255), note_scale=1.8)
    blue_note = make_center_note(SIZE, (60, 100, 255, 255), note_scale=1.8)

    # Red slightly up-left, blue slightly down-right
    red_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    red_layer.paste(red_note, (-offset, -offset), red_note)
    final = Image.alpha_composite(final, red_layer)

    blue_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    blue_layer.paste(blue_note, (offset, offset), blue_note)
    final = Image.alpha_composite(final, blue_layer)

    out_path = "icon_preview.png"
    final.save(out_path)
    print(f"Saved to {out_path} ({SIZE}x{SIZE})")


if __name__ == "__main__":
    main()
