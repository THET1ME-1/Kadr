#!/usr/bin/env python3
"""Раунд 3 — финал. Универсальная капсула (баг раунда 2: горизонтальные
перфорации вырождались в эллипсы). Плоская заливка, сквозные вырезы."""
import math, os, subprocess
from gen_logos import squircle, rounded_poly, play_triangle, f, TEAL

OUT = "/tmp/claude-1000/-home-alelx/3784a63a-c5b4-4bc9-a85a-8827c842d437/scratchpad/final"
os.makedirs(OUT, exist_ok=True)
PLATE = squircle(50, 50, 42)


def cap(cx, cy, w, h):
    """Капсула любой ориентации: радиус = половина короткой стороны."""
    r = min(w, h) / 2
    if h >= w:  # вертикальная
        x0, x1 = cx - r, cx + r
        y0, y1 = cy - h / 2 + r, cy + h / 2 - r
        return (f"M {f(x0)} {f(y0)} A {f(r)} {f(r)} 0 0 1 {f(x1)} {f(y0)} "
                f"L {f(x1)} {f(y1)} A {f(r)} {f(r)} 0 0 1 {f(x0)} {f(y1)} Z")
    x0, x1 = cx - w / 2 + r, cx + w / 2 - r
    y0, y1 = cy - r, cy + r
    return (f"M {f(x0)} {f(y0)} L {f(x1)} {f(y0)} "
            f"A {f(r)} {f(r)} 0 0 1 {f(x1)} {f(y1)} L {f(x0)} {f(y1)} "
            f"A {f(r)} {f(r)} 0 0 1 {f(x0)} {f(y0)} Z")


def svg(body, name):
    open(f"{OUT}/{name}.svg", "w").write(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" '
        f'width="512" height="512" role="img" aria-label="Kadr">\n{body}\n</svg>\n')


def path(d, extra=""):
    return f'  <path fill="currentColor" fill-rule="evenodd" d="{d}"{extra}/>'


# ── A. ВРАТА — монолит, пробитый play; три перфорации по левой кромке ──
tri_a = play_triangle(R=25, cx=56.0, cy=50, r=3.5)
perf_a = [cap(16.5, y, 7, 13) for y in (28.5, 50, 71.5)]
svg(path(" ".join([PLATE, tri_a] + perf_a)), "A-vrata")

# ── B. ПЛЁНКА — настоящий кадр 35мм: перфорация сверху и снизу ──
tri_b = play_triangle(R=19, cx=52.5, cy=50, r=2.9)
perf_b = ([cap(x, 15.0, 12, 6) for x in (32, 50, 68)]
          + [cap(x, 85.0, 12, 6) for x in (32, 50, 68)])
svg(path(" ".join([PLATE, tri_b] + perf_b)), "B-plyonka")

# ── C. РАМКА — кольцо-сквиркл, сплошной play, центр дышит ──
ring = PLATE + " " + squircle(50, 50, 37)
tri_c = play_triangle(R=17, cx=54.0, cy=50, r=2.6)
svg(path(ring) + "\n" + path(tri_c), "C-ramka")

# ── D. ПУСТОЙ КАДР — кольцо + контурный play, максимальная тишина ──
tri_o = play_triangle(R=20, cx=53.0, cy=50, r=3.2)
tri_i = play_triangle(R=12.5, cx=52.2, cy=50, r=1.8)
svg(path(ring) + "\n" + path(tri_o + " " + tri_i), "D-pustoy")

# ── E. ЗАСЕЧКА — дерзкий срез верхнего правого угла ──
notch = '  <clipPath id="n"><path d="M 0 0 L 52 0 L 100 48 L 100 100 L 0 100 Z"/></clipPath>'
tri_e = play_triangle(R=23, cx=56.0, cy=56, r=3.3)
perf_e = [cap(16.5, y, 7, 12) for y in (46, 66)]
svg(f'  <defs>\n{notch}\n  </defs>\n'
    + path(" ".join([PLATE, tri_e] + perf_e), ' clip-path="url(#n)"'), "E-zasechka")

# ── F. ПЛЁНКА-РАМКА — кольцо + перфорация сверху/снизу, play внутри ──
tri_f = play_triangle(R=15, cx=53.0, cy=50, r=2.4)
perf_f = ([cap(x, 12.5, 11, 5) for x in (36, 50, 64)]
          + [cap(x, 87.5, 11, 5) for x in (36, 50, 64)])
svg(path(" ".join([ring] + perf_f)) + "\n" + path(tri_f), "F-plyonka-ramka")

names = ["A-vrata", "B-plyonka", "C-ramka", "D-pustoy", "E-zasechka", "F-plyonka-ramka"]
for n in names:
    s = open(f"{OUT}/{n}.svg").read().replace("currentColor", TEAL)
    open(f"{OUT}/_r_{n}.svg", "w").write(s)
    subprocess.run(["magick", "-background", "none", f"{OUT}/_r_{n}.svg",
                    "-resize", "256x256", f"{OUT}/{n}.png"], check=True)
    subprocess.run(["magick", f"{OUT}/_r_{n}.svg", "-resize", "16x16",
                    "-scale", "96x96", f"{OUT}/tiny_{n}.png"], check=True)
subprocess.run(["magick", "montage"] + [f"{OUT}/{n}.png" for n in names]
               + ["-tile", "3x2", "-geometry", "+12+12", "-background", "#101014",
                  f"{OUT}/contact.png"], check=True)
subprocess.run(["magick", "montage"] + [f"{OUT}/tiny_{n}.png" for n in names]
               + ["-tile", "6x1", "-geometry", "+8+8", "-background", "#101014",
                  f"{OUT}/tiny.png"], check=True)
print("готово")
