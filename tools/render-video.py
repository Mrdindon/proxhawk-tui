#!/usr/bin/env python3
"""render-video.py - render terminal screens captured by demo-video.sh
(tmux capture-pane -e: text with SGR colour codes) to an MP4 video.

    render-video.py FRAMES_DIR OUTPUT.mp4 COLS ROWS

FRAMES_DIR/list holds one "file seconds" line per screen. Needs Pillow,
imageio-ffmpeg and fontTools (development only, not used by pvetty).
Fonts: DEMO_FONT / DEMO_FONT_BOLD (a Nerd Font Mono, for the icons), then
DejaVu Sans Mono and DejaVu Sans for the symbols they lack.
"""
import os
import re
import sys

import imageio_ffmpeg
from fontTools.ttLib import TTFont
from PIL import Image, ImageDraw, ImageFont

SIZE = int(os.environ.get("DEMO_FONT_SIZE", "20"))
FPS = 20
PAD = 24
BG = (29, 33, 39)
FG = (213, 217, 224)
# Base 16 colours (a soft dark palette), then the xterm 6x6x6 cube and greys.
BASE16 = [(40, 44, 52), (224, 108, 117), (152, 195, 121), (229, 192, 123),
          (97, 175, 239), (198, 120, 221), (86, 182, 194), (171, 178, 191),
          (92, 99, 112), (240, 128, 137), (170, 215, 140), (240, 205, 140),
          (125, 195, 250), (215, 145, 235), (110, 200, 210), (230, 233, 238)]
LEVELS = [0, 95, 135, 175, 215, 255]
PALETTE = BASE16 + [(LEVELS[i // 36], LEVELS[i // 6 % 6], LEVELS[i % 6]) for i in range(216)] \
    + [(8 + 10 * i,) * 3 for i in range(24)]

FONT_FILES = [f for f in (os.environ.get("DEMO_FONT"),
                          "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
                          "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf") if f]
BOLD_FILES = [f for f in (os.environ.get("DEMO_FONT_BOLD"),
                          "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf",
                          "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf") if f]


def load(files):
    return [(ImageFont.truetype(f, SIZE), set(TTFont(f).getBestCmap())) for f in files if os.path.exists(f)]


FONTS, BOLD = load(FONT_FILES), load(BOLD_FILES)
CW = round(FONTS[0][0].getlength("M"))
ASC, DESC = FONTS[0][0].getmetrics()
CH = round(SIZE * 1.3)
BASE = (CH - (ASC + DESC)) // 2 + ASC
_pick = {}


def font_for(ch, bold):
    key = (ch, bold)
    if key not in _pick:
        chain = (BOLD or FONTS) if bold else FONTS
        _pick[key] = next((f for f, cmap in chain if ord(ch) in cmap), chain[0][0])
    return _pick[key]


SGR = re.compile(r"\x1b\[([0-9;:]*)m")


def parse_line(line):
    """Yield (char, fg, bg, bold, reverse) for a line with SGR codes."""
    st = {"fg": None, "bg": None, "bold": False, "rev": False}
    pos = 0
    for m in SGR.finditer(line):
        for ch in line[pos:m.start()]:
            yield ch, st["fg"], st["bg"], st["bold"], st["rev"]
        apply_sgr(st, m.group(1))
        pos = m.end()
    for ch in line[pos:]:
        yield ch, st["fg"], st["bg"], st["bold"], st["rev"]


def apply_sgr(st, params):
    p = [int(x) if x else 0 for x in re.split("[;:]", params)] if params else [0]
    i = 0
    while i < len(p):
        c = p[i]
        if c == 0:
            st.update(fg=None, bg=None, bold=False, rev=False)
        elif c == 1:
            st["bold"] = True
        elif c == 22:
            st["bold"] = False
        elif c == 7:
            st["rev"] = True
        elif c == 27:
            st["rev"] = False
        elif 30 <= c <= 37:
            st["fg"] = PALETTE[c - 30]
        elif 90 <= c <= 97:
            st["fg"] = PALETTE[c - 82]
        elif 40 <= c <= 47:
            st["bg"] = PALETTE[c - 40]
        elif 100 <= c <= 107:
            st["bg"] = PALETTE[c - 92]
        elif c == 39:
            st["fg"] = None
        elif c == 49:
            st["bg"] = None
        elif c in (38, 48) and i + 1 < len(p):
            key = "fg" if c == 38 else "bg"
            if p[i + 1] == 5 and i + 2 < len(p):
                st[key] = PALETTE[p[i + 2] % 256]
                i += 2
            elif p[i + 1] == 2 and i + 4 < len(p):
                st[key] = tuple(p[i + 2:i + 5])
                i += 4
        i += 1


# Box drawing: directions of the lines from the cell centre (l, r, u, d).
BOX = {"─": "lr", "━": "lr", "│": "ud", "┃": "ud", "┌": "rd", "┐": "ld", "└": "ru", "┘": "lu",
       "├": "rud", "┤": "lud", "┬": "lrd", "┴": "lru", "┼": "lrud", "╴": "l", "╶": "r", "╵": "u", "╷": "d"}
ROUND = {"╭": "rd", "╮": "ld", "╰": "ru", "╯": "lu"}


def mix(a, b, t):
    return tuple(round(a[i] * (1 - t) + b[i] * t) for i in range(3))


def draw_special(d, ch, px, py, fg, bg):
    """Draw box drawing, block and braille characters geometrically, so that
    they join from cell to cell. Returns False for other characters."""
    o = ord(ch)
    cx, cy, lw = px + CW // 2, py + CH // 2, max(1, round(SIZE / 12))
    h = lw // 2
    if ch in BOX or ch in ROUND:
        dirs = BOX.get(ch) or ROUND[ch]
        if ch in ROUND:                       # rounded corner: short arc
            r = CW // 2
            sx, sy = (1 if "r" in dirs else -1), (1 if "d" in dirs else -1)
            box = [cx + (0 if sx > 0 else -2 * r), cy + (0 if sy > 0 else -2 * r)]
            box += [box[0] + 2 * r, box[1] + 2 * r]
            start = {(1, 1): 180, (-1, 1): 270, (1, -1): 90, (-1, -1): 0}[(sx, sy)]
            d.arc(box, start, start + 90, fill=fg, width=lw)
            if sx > 0:
                d.rectangle([cx + r, cy - h, px + CW, cy - h + lw - 1], fill=fg)
            else:
                d.rectangle([px, cy - h, cx - r, cy - h + lw - 1], fill=fg)
            if sy > 0:
                d.rectangle([cx - h, cy + r, cx - h + lw - 1, py + CH], fill=fg)
            else:
                d.rectangle([cx - h, py, cx - h + lw - 1, cy - r], fill=fg)
            return True
        if "l" in dirs:
            d.rectangle([px, cy - h, cx, cy - h + lw - 1], fill=fg)
        if "r" in dirs:
            d.rectangle([cx, cy - h, px + CW, cy - h + lw - 1], fill=fg)
        if "u" in dirs:
            d.rectangle([cx - h, py, cx - h + lw - 1, cy], fill=fg)
        if "d" in dirs:
            d.rectangle([cx - h, cy, cx - h + lw - 1, py + CH], fill=fg)
        return True
    if ch == "█":
        d.rectangle([px, py, px + CW - 1, py + CH - 1], fill=fg)
        return True
    if 0x2589 <= o <= 0x258F:                 # ▉ .. ▏ left eighths
        w = round(CW * (0x2590 - o) / 8)
        d.rectangle([px, py, px + max(w, 1) - 1, py + CH - 1], fill=fg)
        return True
    if 0x2581 <= o <= 0x2587:                 # ▁ .. ▇ lower eighths
        t = round(CH * (o - 0x2580) / 8)
        d.rectangle([px, py + CH - t, px + CW - 1, py + CH - 1], fill=fg)
        return True
    if ch in "▌▐▀▄":
        box = {"▌": [px, py, px + CW // 2 - 1, py + CH - 1], "▐": [px + CW // 2, py, px + CW - 1, py + CH - 1],
               "▀": [px, py, px + CW - 1, py + CH // 2 - 1], "▄": [px, py + CH // 2, px + CW - 1, py + CH - 1]}[ch]
        d.rectangle(box, fill=fg)
        return True
    if ch in "░▒▓":                           # shades: a flat mix of the two colours
        d.rectangle([px, py, px + CW - 1, py + CH - 1], fill=mix(bg, fg, {"░": .22, "▒": .5, "▓": .75}[ch]))
        return True
    if 0x2801 <= o <= 0x28FF:                 # braille: round dots, empty dots not drawn
        bits = o - 0x2800
        dots = [(0, 0, 0x01), (0, 1, 0x02), (0, 2, 0x04), (1, 0, 0x08), (1, 1, 0x10), (1, 2, 0x20), (0, 3, 0x40), (1, 3, 0x80)]
        r = max(1.2, CW / 7)
        for gx, gy, bit in dots:
            if bits & bit:
                x = px + CW * (0.3 + 0.4 * gx)
                y = py + CH * (0.14 + 0.24 * gy)
                d.ellipse([x - r, y - r, x + r, y + r], fill=fg)
        return True
    return ch == "\u2800"


def render(path, cols, rows):
    w, h = cols * CW + 2 * PAD, rows * CH + 2 * PAD
    img = Image.new("RGB", (w + (-w) % 16, h + (-h) % 16), BG)    # H.264 blocks
    d = ImageDraw.Draw(img)
    with open(path, encoding="utf-8", errors="replace") as fh:
        lines = fh.read().split("\n")
    for y, line in enumerate(lines[:rows]):
        for x, (ch, fg, bg, bold, rev) in enumerate(parse_line(line)):
            if x >= cols:
                break
            fg, bg = fg or FG, bg or BG
            if rev:
                fg, bg = bg, fg
            px, py = PAD + x * CW, PAD + y * CH
            if bg != BG:
                d.rectangle([px, py, px + CW - 1, py + CH - 1], fill=bg)
            if ch != " " and not draw_special(d, ch, px, py, fg, bg):
                d.text((px, py + BASE), ch, font=font_for(ch, bold), fill=fg, anchor="ls")
    return img


def main():
    frames, out, cols, rows = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
    steps = [line.split() for line in open(os.path.join(frames, "list")) if line.strip()]
    first = render(os.path.join(frames, steps[0][0]), cols, rows)
    size = first.size
    writer = imageio_ffmpeg.write_frames(out, size, fps=FPS, codec="libx264", pix_fmt_out="yuv420p",
                                         output_params=["-crf", "20", "-preset", "slow", "-movflags", "+faststart"])
    writer.send(None)
    for name, secs in steps:
        img = render(os.path.join(frames, name), cols, rows)
        if os.environ.get("DEMO_PNG"):     # keep the screens as PNG (checking)
            img.save(os.path.join(os.environ["DEMO_PNG"], name.replace(".ans", ".png")))
        data = img.tobytes()
        for _ in range(max(1, round(float(secs) * FPS))):
            writer.send(data)
    writer.close()
    total = sum(float(s) for _, s in steps)
    print(f"{out}: {size[0]}x{size[1]}, {len(steps)} screens, {total:.1f} s")


if __name__ == "__main__":
    main()
