#!/usr/bin/env python3
"""make-console-font.py - build the Linux console fonts of proxhawk-tui.

    tools/make-console-font.py /usr/share/unifont/unifont.hex

The Linux virtual console (TERM=linux) draws text with a bitmap font of at
most 512 glyphs: the fonts shipped by Debian lack most symbols used by the
interface and all braille patterns. This tool builds two PSF2 fonts (8x16)
from GNU Unifont, holding exactly what proxhawk-tui displays:

    fonts/proxhawk-256.psf.gz  ASCII, box drawing, blocks, the symbols and
                               braille patterns of the interface, Western
                               European letters (keeps the 16 colours)
    fonts/proxhawk-512.psf.gz  the same plus Latin Extended, Cyrillic, Greek
                               (512 glyph fonts leave 8 foreground colours)

The character lists come from the sources (symbols), from lang/*.sh and
from the Proxmox VE catalogs installed on the build machine (letters).
Development tool: needs unifont.hex (Debian package "unifont"); the fonts
are committed. Unifont is GPL-2+ with the font embedding exception / OFL 1.1.
"""
import glob
import gzip
import os
import re
import struct
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Glyphs that are 16 pixels wide in Unifont, redrawn in 8x16.
HAND = {
    "✔": """
........
........
........
.......#
......##
......#.
.....##.
.....#..
#...##..
##..#...
.####...
..##....
..#.....
........
........
........""",
    "✖": """
........
........
........
........
##...##.
.##.##..
..###...
..###...
.##.##..
##...##.
........
........
........
........
........
........""",
    "✎": """
........
........
......#.
.....###
....###.
...###..
..###...
.###....
.##.....
##......
#.......
........
#######.
........
........
........""",
    "⚙": """
........
........
...##...
.#.##.#.
.######.
..#..#..
###..###
###..###
..#..#..
.######.
.#.##.#.
...##...
........
........
........
........""",
    "⏎": """
........
........
......#.
......#.
......#.
......#.
..#...#.
.##...#.
#######.
.##.....
..#.....
........
........
........
........
........""",
    "⊸": """
........
........
........
........
.....##.
....#..#
#####..#
....#..#
.....##.
........
........
........
........
........
........
........""",
    "⊶": """
........
........
........
........
.##..##.
#..#####
#..#####
#..#####
.##..##.
........
........
........
........
........
........
........""",
}
# Several code points drawn with the glyph of another one.
ALIAS = {
    "✓": "✔", "✕": "✖", "‘": "'", "’": "'", "‚": ",", "“": '"', "”": '"', "„": '"',
    "‐": "-", "‑": "-", "–": "-", "—": "-", "―": "-", " ": " ", " ": " ", " ": " ",
    "⠀": " ", "ʳ": "r", "ᵉ": "e", "ᵒ": "o", "ᵈ": "d", "ˢ": "s", "ᵗ": "t",
}
L_MASK = (0, 64, 68, 70, 71)
R_MASK = (0, 128, 160, 176, 184)
SPINNER = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"


def nonascii(text):
    return {c for c in text if ord(c) > 127}


def interface_chars():
    """Non-ASCII characters written in the sources (not in comments)."""
    out = set()
    files = glob.glob(ROOT + "/lib/*.sh") + glob.glob(ROOT + "/views/*.sh") + glob.glob(ROOT + "/plugins/*.sh")
    for path in files + [ROOT + "/proxhawk-tui"]:
        for line in open(path, encoding="utf-8"):
            if line.lstrip().startswith("#"):
                continue
            if path.endswith("i18n.sh") and "]=" in line and " - " in line:
                continue                      # names of the language menu
            out |= nonascii(line)
    out = {c for c in out if not 0x2800 <= ord(c) <= 0x28FF}
    out |= {chr(0x2800 + (l | r)) for l in L_MASK for r in R_MASK} | set(SPINNER)
    return out


def language_chars():
    """Letters of the translations (lang/*.sh and the Proxmox VE catalogs)."""
    out = set()
    for path in glob.glob(ROOT + "/lang/*.sh"):
        out |= nonascii(open(path, encoding="utf-8").read())
    for cat in glob.glob("/usr/share/pve-i18n/pve-lang-*.js"):
        res = subprocess.run(["perl", ROOT + "/lib/i18n-pve.pl", cat, ROOT + "/lang/TEMPLATE.sh"],
                             capture_output=True, text=True).stdout
        out |= nonascii("".join(re.findall(r"\]='(.*)'$", res, re.M)))
    # Scripts the console cannot hold (CJK, Hangul, Arabic, Hebrew, Georgian, Lao...).
    return {c for c in out if ord(c) < 0x0530 or 0x1D00 <= ord(c) < 0x2150}


def bitmap(hexfont, ch):
    if ch in HAND:
        rows = HAND[ch].strip().split("\n")
        return bytes(int(r.replace(".", "0").replace("#", "1"), 2) for r in rows)
    data = hexfont.get(ord(ch))
    if data is None or len(data) != 32:
        return None
    return bytes.fromhex(data)


def write_psf(path, glyphs):
    """glyphs: list of (bitmap, [code points])."""
    head = struct.pack("<4sIIIIIII", b"\x72\xb5\x4a\x86", 0, 32, 1, len(glyphs), 16, 16, 8)
    body = b"".join(g for g, _ in glyphs)
    table = b"".join("".join(cps).encode("utf-8") + b"\xff" for _, cps in glyphs)
    with gzip.GzipFile(path, "wb", mtime=0) as fh:
        fh.write(head + body + table)


def build(hexfont, chars, size, path):
    chars = set(chars)
    by_glyph = {}                                   # drawn character -> code points
    for c in sorted(chars):
        by_glyph.setdefault(ALIAS.get(c, c), []).append(c)
    for a in ALIAS.values():
        by_glyph.setdefault(a, [])
    slots = [None] * size
    for code in range(32, 127):                     # ASCII at its own position
        ch = chr(code)
        slots[code] = (bitmap(hexfont, ch), [ch] + by_glyph.pop(ch, []))
    free = [i for i in range(size) if slots[i] is None]
    skipped = []
    for ch in sorted(by_glyph):
        bm = bitmap(hexfont, ch)
        if bm is None:
            skipped.append(ch)
            continue
        if not free:
            sys.exit(f"{path}: more than {size} glyphs")
        cps = [ch] + [c for c in by_glyph[ch] if c != ch]
        slots[free.pop(0)] = (bm, cps)
    blank = bytes(16)
    glyphs = [s if s else (blank, []) for s in slots]
    write_psf(path, glyphs)
    used = size - len(free)
    print(f"{os.path.relpath(path, ROOT)}: {used}/{size} glyphs" + (f", not drawable: {''.join(skipped)}" if skipped else ""))


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    hexfont = {}
    for line in open(sys.argv[1]):
        code, data = line.strip().split(":")
        hexfont[int(code, 16)] = data
    ui = interface_chars()
    letters = language_chars() - ui
    west = {c for c in letters if ord(c) < 0x100 or c in "œŒ€№" or c in ALIAS}
    os.makedirs(ROOT + "/fonts", exist_ok=True)
    build(hexfont, ui | west, 256, ROOT + "/fonts/proxhawk-256.psf.gz")
    build(hexfont, ui | letters, 512, ROOT + "/fonts/proxhawk-512.psf.gz")


if __name__ == "__main__":
    main()
