#!/usr/bin/env python3
"""Draws the DMG window background: title, an arrow from Baplet to Applications, the three
install steps, and orange label strips under each icon (Finder draws icon names in black or
white depending on the Mac's appearance, and both read on orange). Writes background.png
(660x520) and background@2x.png next to this script; `make dmg` combines them into one
Retina-aware TIFF. Needs Pillow; only run it when the layout changes, and commit the PNGs.
Icon positions must match ICONS in scripts/dmg/layout.applescript."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

WIDTH, HEIGHT = 660, 520
ICON_SIZE = 72
BAPLET, APPLICATIONS = (190, 135), (470, 135)
HELP, SETTINGS, SPONSOR = (150, 400), (330, 400), (510, 400)
FONT = "/System/Library/Fonts/SFNS.ttf"

PAPER = (255, 250, 242)
INK = (23, 23, 26)
MUTED = (93, 90, 85)
ACCENT = (255, 100, 31)


def font(size, weight, scale):
    """Returns San Francisco at `size` points times `scale`, in the named weight."""
    face = ImageFont.truetype(FONT, int(size * scale))
    face.set_variation_by_name(weight)
    return face


def label_strip(draw, center, scale, width=124):
    """Draws the orange rounded strip that sits behind a Finder icon name."""
    x, y = center[0], center[1] + ICON_SIZE // 2 + 15
    draw.rounded_rectangle(
        [(x - width / 2) * scale, (y - 11) * scale, (x + width / 2) * scale, (y + 11) * scale],
        radius=11 * scale,
        fill=ACCENT,
    )


def render(scale):
    """Draws the whole background at `scale` (1 or 2) and returns the image."""
    image = Image.new("RGB", (WIDTH * scale, HEIGHT * scale), PAPER)
    draw = ImageDraw.Draw(image)

    def text(xy, value, face, fill, anchor="la"):
        draw.text((xy[0] * scale, xy[1] * scale), value, font=face, fill=fill, anchor=anchor)

    text((WIDTH / 2, 34), "Install Baplet", font(22, "Bold", scale), INK, "mm")

    y = BAPLET[1]
    start, end = BAPLET[0] + 62, APPLICATIONS[0] - 62
    draw.line([(start * scale, y * scale), ((end - 14) * scale, y * scale)], fill=ACCENT, width=5 * scale)
    draw.polygon(
        [(end * scale, y * scale), ((end - 18) * scale, (y - 11) * scale), ((end - 18) * scale, (y + 11) * scale)],
        fill=ACCENT,
    )
    text(((start + end) / 2, y - 18), "drag", font(13, "Semibold", scale), ACCENT, "mm")

    for center in (BAPLET, APPLICATIONS, HELP, SETTINGS, SPONSOR):
        label_strip(draw, center, scale, width=150 if center == SETTINGS else 124)

    steps = [
        ("1", "Drag Baplet onto Applications."),
        ("2", "Open Baplet from Applications. macOS blocks it the first time: click Done."),
        ("3", "Open Privacy & Security (below), scroll down and click Open Anyway."),
    ]
    number_font, step_font = font(14, "Bold", scale), font(14, "Regular", scale)
    for index, (number, line) in enumerate(steps):
        row = 232 + index * 30
        draw.ellipse([(52 * scale), (row - 11) * scale, (74 * scale), (row + 11) * scale], fill=ACCENT)
        text((63, row), number, number_font, (255, 255, 255), "mm")
        text((86, row), line, step_font, INK, "lm")

    text((WIDTH / 2, 336), "Need help, or want to support Baplet?", font(13, "Medium", scale), MUTED, "mm")
    return image


if __name__ == "__main__":
    here = Path(__file__).resolve().parent
    render(1).save(here / "background.png")
    render(2).save(here / "background@2x.png")
    print("Wrote background.png and background@2x.png")
