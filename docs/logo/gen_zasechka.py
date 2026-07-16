#!/usr/bin/env python3
"""Засечка в колеровке: знак на бирюзовой подложке.
Вариант юзера — тёмный #0E1316 вместо белого."""
import os, re, subprocess

S = "/tmp/claude-1000/-home-alelx/3784a63a-c5b4-4bc9-a85a-8827c842d437/scratchpad"
OUT = f"{S}/zasechka"
os.makedirs(OUT, exist_ok=True)

TEAL = "#00B5C7"
INK = "#0E1316"
WHITE = "#FFFFFF"


def contrast(hex1, hex2):
    def lum(h):
        c = [int(h[i:i + 2], 16) / 255 for i in (1, 3, 5)]
        c = [v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4 for v in c]
        return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
    a, b = lum(hex1), lum(hex2)
    hi, lo = max(a, b), min(a, b)
    return (hi + 0.05) / (lo + 0.05)


print(f"контраст знак/подложка:")
print(f"  белый  #FFFFFF на {TEAL}: {contrast(WHITE, TEAL):.2f}:1")
print(f"  тёмный {INK} на {TEAL}: {contrast(INK, TEAL):.2f}:1")

# исходная геометрия Засечки
src = open(f"{S}/final/E-zasechka.svg").read()
inner = re.search(r"<svg[^>]*>(.*)</svg>", src, re.S).group(1).strip()


def icon(mark_color, bg, name, scale=0.80):
    """Подложка целиком + знак поверх, ужатый к центру (запас под маску)."""
    body = inner.replace('fill="currentColor"', f'fill="{mark_color}"')
    off = 50 * (1 - scale)
    s = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" width="512" height="512" role="img" aria-label="Kadr">
  <rect x="0" y="0" width="100" height="100" fill="{bg}"/>
  <g transform="translate({off:.2f} {off:.2f}) scale({scale})">
{body}
  </g>
</svg>
'''
    open(f"{OUT}/{name}.svg", "w").write(s)
    return s


def plain(mark_color, bg, name):
    """Без подложки во весь холст: плита сама себе силуэт (для сравнения)."""
    body = inner.replace('fill="currentColor"', f'fill="{mark_color}"')
    s = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" width="512" height="512" role="img" aria-label="Kadr">
  <rect x="0" y="0" width="100" height="100" rx="22" fill="{bg}"/>
{body}
</svg>
'''
    open(f"{OUT}/{name}.svg", "w").write(s)
    return s


icon(INK, TEAL, "ink-on-teal")
icon(WHITE, TEAL, "white-on-teal")
icon(TEAL, INK, "teal-on-ink")

names = ["white-on-teal", "ink-on-teal", "teal-on-ink"]
for n in names:
    subprocess.run(["magick", "-background", "none", f"{OUT}/{n}.svg",
                    "-resize", "256x256", f"{OUT}/{n}.png"], check=True)
    subprocess.run(["magick", f"{OUT}/{n}.svg", "-resize", "16x16",
                    "-scale", "96x96", f"{OUT}/tiny_{n}.png"], check=True)
subprocess.run(["magick", "montage"] + [f"{OUT}/{n}.png" for n in names]
               + ["-tile", "3x1", "-geometry", "+14+14", "-background", "#2A2E33",
                  f"{OUT}/contact.png"], check=True)
subprocess.run(["magick", "montage"] + [f"{OUT}/tiny_{n}.png" for n in names]
               + ["-tile", "3x1", "-geometry", "+8+8", "-background", "#2A2E33",
                  f"{OUT}/tiny.png"], check=True)
print("готово")
