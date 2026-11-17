#!/usr/bin/env python3
"""Show a text screen saved by SYNMIND /DUMP=... (80x25 cells of character, colour).

  scripts/screen.py build/tp7/SYNTH.BIN            the text, to read or compare
  scripts/screen.py build/tp7/SYNTH.BIN --html     an HTML page in the screen's colours
"""
import html
import sys

COLUMNS, ROWS = 80, 25
PALETTE = ["#000000", "#0000AA", "#00AA00", "#00AAAA", "#AA0000", "#AA00AA", "#AA5500", "#AAAAAA",
           "#555555", "#5555FF", "#55FF55", "#55FFFF", "#FF5555", "#FF55FF", "#FFFF55", "#FFFFFF"]


def char(code):
    """A code page 437 character as Unicode (control codes as their glyphs)."""
    if code < 32:
        return " ☺☻♥♦♣♠•◘○◙♂♀♪♫☼►◄↕‼¶§▬↨↑↓→←∟↔▲▼"[code]
    return bytes([code]).decode("cp437")


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    data = open(sys.argv[1], "rb").read()
    cells = [(data[i], data[i + 1]) for i in range(0, COLUMNS * ROWS * 2, 2)]
    if "--html" not in sys.argv:
        for row in range(ROWS):
            print("".join(char(c) for c, _ in cells[row * COLUMNS:(row + 1) * COLUMNS]).rstrip())
        return
    out = ['<pre style="font-family:monospace;line-height:1.1;display:inline-block">']
    for row in range(ROWS):
        for c, attr in cells[row * COLUMNS:(row + 1) * COLUMNS]:
            fore, back = PALETTE[attr & 15], PALETTE[(attr >> 4) & 7]
            out.append(f'<span style="color:{fore};background:{back}">{html.escape(char(c))}</span>')
        out.append("\n")
    out.append("</pre>")
    print("".join(out))


if __name__ == "__main__":
    main()
