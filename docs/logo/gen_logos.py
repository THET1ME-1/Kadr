#!/usr/bin/env python3
"""Генератор вариантов логотипа Kadr по docs/logo_prompt.md.
Плоская заливка, без градиентов. Все вырезы — сквозные (fill-rule=evenodd).
"""
import math, os, subprocess

OUT = "/tmp/claude-1000/-home-alelx/3784a63a-c5b4-4bc9-a85a-8827c842d437/scratchpad/logos"
os.makedirs(OUT, exist_ok=True)
TEAL = "#00B5C7"


def f(v):
    return f"{v:.2f}".rstrip("0").rstrip(".")


def squircle(cx, cy, a, n=4.0):
    """Суперэллипс |x/a|^n+|y/a|^n=1 кубическими Безье. k подобран так, чтобы
    середина сегмента легла точно на диагональную точку суперэллипса."""
    s = a * (0.5) ** (1.0 / n)
    k = (8 * s - 4 * a) / 3.0
    r, l, t, b = cx + a, cx - a, cy - a, cy + a
    return (
        f"M {f(r)} {f(cy)} "
        f"C {f(r)} {f(cy+k)}, {f(cx+k)} {f(b)}, {f(cx)} {f(b)} "
        f"C {f(cx-k)} {f(b)}, {f(l)} {f(cy+k)}, {f(l)} {f(cy)} "
        f"C {f(l)} {f(cy-k)}, {f(cx-k)} {f(t)}, {f(cx)} {f(t)} "
        f"C {f(cx+k)} {f(t)}, {f(r)} {f(cy-k)}, {f(r)} {f(cy)} Z"
    )


def rounded_poly(pts, r, sweep=1):
    """Многоугольник со скруглёнными углами радиуса r (дугами)."""
    n = len(pts)
    segs = []
    for i in range(n):
        p = pts[i]
        prv, nxt = pts[(i - 1) % n], pts[(i + 1) % n]
        # единичные векторы от вершины к соседям
        def unit(a, b):
            dx, dy = b[0] - a[0], b[1] - a[1]
            L = math.hypot(dx, dy)
            return dx / L, dy / L
        u_prev, v_prev = unit(p, prv)
        u_next, v_next = unit(p, nxt)
        # половина угла при вершине
        cosang = u_prev * u_next + v_prev * v_next
        ang = math.acos(max(-1, min(1, cosang)))
        d = r / math.tan(ang / 2)
        a_in = (p[0] + u_prev * d, p[1] + v_prev * d)   # точка входа (со стороны prv)
        a_out = (p[0] + u_next * d, p[1] + v_next * d)  # точка выхода (в сторону nxt)
        segs.append((a_in, a_out))
    d_parts = [f"M {f(segs[0][1][0])} {f(segs[0][1][1])}"]
    for i in range(1, n + 1):
        j = i % n
        a_in, a_out = segs[j]
        d_parts.append(f"L {f(a_in[0])} {f(a_in[1])}")
        d_parts.append(f"A {f(r)} {f(r)} 0 0 {sweep} {f(a_out[0])} {f(a_out[1])}")
    d_parts.append("Z")
    return " ".join(d_parts)


def play_triangle(R=27.0, cx=52.5, cy=50.0, r=3.8):
    """Равносторонний play: вершина вправо, центроид оптически сдвинут."""
    pts = [(cx + R * math.cos(math.radians(a)), cy + R * math.sin(math.radians(a)))
           for a in (0, 120, 240)]
    return rounded_poly(pts, r)


def capsule(cx, cy, w=5.5, h=9.0):
    """Капсула-перфорация как path (rx = w/2)."""
    r = w / 2
    x0, x1 = cx - r, cx + r
    y0, y1 = cy - h / 2 + r, cy + h / 2 - r
    return (f"M {f(x0)} {f(y0)} "
            f"A {f(r)} {f(r)} 0 0 1 {f(x1)} {f(y0)} "
            f"L {f(x1)} {f(y1)} "
            f"A {f(r)} {f(r)} 0 0 1 {f(x0)} {f(y1)} Z")


PERFS = [capsule(17.75, y) for y in (28.5, 50, 71.5)]
PLATE = squircle(50, 50, 42)
TRI = play_triangle()


def svg(body, name):
    s = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" '
         'width="512" height="512" role="img" aria-label="Kadr">\n'
         f'{body}\n</svg>\n')
    open(f"{OUT}/{name}.svg", "w").write(s)
    return s


def path(d, extra=""):
    return f'  <path fill="currentColor" fill-rule="evenodd" d="{d}"{extra}/>'


# ── 1. ВРАТА — канон: монолит, пробитый треугольником + 3 перфорации ──
svg(path(" ".join([PLATE, TRI] + PERFS)), "1-gate")

# ── 2. СТВОРКИ — монолит + треугольник + вертикальная сквозная щель ──
slit = capsule(17.75, 50, w=4.0, h=54.0)
svg(path(" ".join([PLATE, TRI, slit])), "2-stvorki")

# ── 3. РАМКА — кольцо-сквиркл (толщина 4) с перфорациями + сплошной play ──
ring = PLATE + " " + squircle(50, 50, 38)
tri_solid = play_triangle(R=20, cx=52.0, cy=50, r=3.0)
svg(path(" ".join([ring] + [capsule(12.0, y) for y in (28.5, 50, 71.5)]))
    + "\n" + path(tri_solid), "3-ramka")

# ── 4. ПУСТОЙ КАДР — кольцо + контурный play, центр пуст ──
tri_outer = play_triangle(R=22, cx=52.0, cy=50, r=3.4)
tri_inner = play_triangle(R=14.2, cx=51.3, cy=50, r=2.0)
svg(path(" ".join([ring] + [capsule(12.0, y) for y in (28.5, 50, 71.5)]))
    + "\n" + path(tri_outer + " " + tri_inner), "4-pustoy-kadr")

# ── 5. ЗАСЕЧКА — монолит со срезанным верхне-правым углом ──
notch = ('  <clipPath id="notch"><path d="M 0 0 L 68 0 L 100 32 L 100 100 L 0 100 Z"/></clipPath>')
svg(f'  <defs>\n{notch}\n  </defs>\n'
    + path(" ".join([PLATE, TRI] + PERFS), ' clip-path="url(#notch)"'), "5-zasechka")

# ── 6. КЛИН — монолит, рассечённый диагональной сквозной щелью ──
def diag_slit(x1, y1, x2, y2, w=4.0):
    dx, dy = x2 - x1, y2 - y1
    L = math.hypot(dx, dy)
    nx, ny = -dy / L * w / 2, dx / L * w / 2
    p = [(x1 + nx, y1 + ny), (x2 + nx, y2 + ny), (x2 - nx, y2 - ny), (x1 - nx, y1 - ny)]
    return rounded_poly(p, w / 2)

cleave = diag_slit(6, 84, 30, 12)
svg(path(" ".join([PLATE, TRI, cleave])), "6-klin")

# ── рендер PNG для самопроверки ──
names = ["1-gate", "2-stvorki", "3-ramka", "4-pustoy-kadr", "5-zasechka", "6-klin"]
for n in names:
    src = f"{OUT}/{n}.svg"
    # currentColor → фирменный, для рендера
    s = open(src).read().replace("currentColor", TEAL)
    tmp = f"{OUT}/_r_{n}.svg"
    open(tmp, "w").write(s)
    subprocess.run(["magick", "-background", "none", tmp, "-resize", "256x256",
                    f"{OUT}/{n}.png"], check=True)
# контактный лист
subprocess.run(["magick", "montage"] + [f"{OUT}/{n}.png" for n in names]
               + ["-tile", "3x2", "-geometry", "+12+12", "-background", "#101014",
                  f"{OUT}/contact.png"], check=True)
print("готово:", ", ".join(names))
