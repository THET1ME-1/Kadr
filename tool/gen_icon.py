#!/usr/bin/env python3
"""Генератор launcher-иконки Kadr: бирюзовый сквиркл + белый play-треугольник
(кино-мотив, M3-плоский). Суперсэмплинг для гладких краёв."""
import os
from PIL import Image, ImageDraw

SS = 4  # супер-сэмплинг
TEAL_TOP = (0, 200, 214)
TEAL_BOT = (0, 120, 140)
WHITE = (255, 255, 255)

RES = "/home/alelx/Projects/GitHub/Kadr/android/app/src/main/res"
DENSITIES = {
    "mipmap-mdpi": 48, "mipmap-hdpi": 72, "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144, "mipmap-xxxhdpi": 192,
}


def gradient(size):
    g = Image.new("RGB", (1, size))
    for y in range(size):
        t = y / (size - 1)
        g.putpixel((0, y), tuple(
            int(TEAL_TOP[i] + (TEAL_BOT[i] - TEAL_TOP[i]) * t) for i in range(3)))
    return g.resize((size, size))


def play_triangle(draw, cx, cy, r, fill):
    # треугольник «play» вправо со скруглёнными углами
    pts = [(cx - 0.46 * r, cy - 0.82 * r),
           (cx - 0.46 * r, cy + 0.82 * r),
           (cx + 0.92 * r, cy)]
    draw.polygon(pts, fill=fill)
    rad = 0.14 * r
    for (x, y) in pts:
        draw.ellipse([x - rad, y - rad, x + rad, y + rad], fill=fill)
    # утолщаем стороны, чтобы скругление не «съедало» тело
    draw.line([pts[0], pts[1]], fill=fill, width=int(rad * 2))
    draw.line([pts[1], pts[2]], fill=fill, width=int(rad * 2))
    draw.line([pts[2], pts[0]], fill=fill, width=int(rad * 2))


def make(size, round_icon=False):
    S = size * SS
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    mask = Image.new("L", (S, S), 0)
    md = ImageDraw.Draw(mask)
    margin = int(S * 0.04)
    box = [margin, margin, S - margin, S - margin]
    if round_icon:
        md.ellipse(box, fill=255)
    else:
        md.rounded_rectangle(box, radius=int(S * 0.235), fill=255)
    grad = gradient(S).convert("RGBA")
    img.paste(grad, (0, 0), mask)
    d = ImageDraw.Draw(img)
    play_triangle(d, S * 0.53, S * 0.5, S * 0.27, WHITE)
    return img.resize((size, size), Image.LANCZOS)


def main():
    master = make(512)
    os.makedirs("/home/alelx/Projects/GitHub/Kadr/assets/icon", exist_ok=True)
    master.save("/home/alelx/Projects/GitHub/Kadr/assets/icon/app_icon.png")
    for folder, px in DENSITIES.items():
        d = os.path.join(RES, folder)
        os.makedirs(d, exist_ok=True)
        make(px).save(os.path.join(d, "ic_launcher.png"))
        make(px, round_icon=True).save(os.path.join(d, "ic_launcher_round.png"))
    print("иконки сгенерированы:", ", ".join(DENSITIES))


if __name__ == "__main__":
    main()
