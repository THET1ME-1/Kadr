#!/usr/bin/env python3
"""Генератор брендинга Kadr: баннер для README и ассеты сайта (gh-pages).

Собирает знак «Засечка» (docs/logo/) с типографикой ДНК (Unbounded/Onest) на
ПЛОСКОМ фоне — градиенты в идентике запрещены (docs/logo_prompt.md).

Кладёт:
  * docs/branding/readme-banner.png     — 1280×384, шапка README
  * docs/branding/site-icon.png         — 256×256, иконка сайта и favicon
  * docs/branding/site-banner.png       — 1024×307, баннер в подвале сайта

Файлы сайта копируются в ветку gh-pages вручную (assets/icon.png, assets/banner.png).

Запуск: python3 tool/gen_branding.py
Требует: ImageMagick (magick), Pillow.
"""
import os
import re
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = f"{ROOT}/docs/branding"
FONTS = f"{ROOT}/assets/fonts"

TEAL = "#00B5C7"
INK = "#0E1316"
WHITE = "#FFFFFF"
MUTED = (125, 141, 145)

# На сайте и в README фон тёмный, поэтому берём ЯРКУЮ колеровку (тёмный знак на
# бирюзе): дефолтная «бирюза на графите» на тёмном фоне растворяется.
# Чтобы показывать другую — поменяй местами.
BRAND_MARK, BRAND_BG = INK, TEAL


def sign_svg(fill, bg, scale=0.69):  # = LEGACY_SCALE в gen_icons.py
    """Знак на подложке-сквиркле — та же геометрия, что у launcher-иконки."""
    src = open(f"{ROOT}/docs/logo/E-zasechka.svg").read()
    inner = re.search(r"<svg[^>]*>(.*)</svg>", src, re.S).group(1).strip()
    inner = (inner.replace('id="n"', 'id="b"').replace("url(#n)", "url(#b)")
                  .replace('fill="currentColor"', f'fill="{fill}"'))
    a, k = 50.0, 45.46
    off = 50 * (1 - scale)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">'
            f'<path fill="{bg}" d="M {50+a} 50 C {50+a} {50+k}, {50+k} {50+a}, 50 {50+a} '
            f'C {50-k} {50+a}, {50-a} {50+k}, {50-a} 50 C {50-a} {50-k}, {50-k} {50-a}, 50 {50-a} '
            f'C {50+k} {50-a}, {50+a} {50-k}, {50+a} 50 Z"/>'
            f'<g transform="translate({off:.3f} {off:.3f}) scale({scale})">{inner}</g></svg>')


def render_mark(size, fill=BRAND_MARK, bg=BRAND_BG):
    tmp = f"/tmp/_kadr_brand_{os.getpid()}.svg"
    png = f"/tmp/_kadr_brand_{os.getpid()}.png"
    open(tmp, "w").write(sign_svg(fill, bg))
    subprocess.run(["magick", "-background", "none", "-density", "1200", tmp,
                    "-resize", f"{size * 4}x{size * 4}", "-resize", f"{size}x{size}",
                    png], check=True)
    im = Image.open(png).convert("RGBA")
    os.remove(tmp)
    os.remove(png)
    return im


def font(name, size, weight):
    """Вариативный шрифт ДНК: выставляем ось wght явно."""
    f = ImageFont.truetype(f"{FONTS}/{name}.ttf", size)
    try:
        f.set_variation_by_axes([weight])
    except Exception:
        pass  # статический экземпляр — вес уже вшит
    return f


def banner(w, h, out, mark_size, pad, title_px, sub_px):
    im = Image.new("RGB", (w, h), INK)   # плоский фон, без градиента
    d = ImageDraw.Draw(im)

    mark = render_mark(mark_size)
    my = (h - mark_size) // 2
    im.paste(mark, (pad, my), mark)

    x = pad + mark_size + int(pad * 0.75)
    title_f = font("Unbounded", title_px, 800)
    sub_f = font("Onest", sub_px, 500)

    # Блок текста центрируем по оптической середине знака
    t_box = d.textbbox((0, 0), "Kadr", font=title_f)
    t_h = t_box[3] - t_box[1]
    s_h = d.textbbox((0, 0), "Ag", font=sub_f)[3]
    gap = int(sub_px * 0.75)
    rule_h = max(3, int(h * 0.011))
    rule_gap = int(sub_px * 0.9)
    total = t_h + gap + s_h + rule_gap + rule_h
    y = (h - total) // 2

    d.text((x, y - t_box[1]), "Kadr", font=title_f, fill=WHITE)
    ys = y + t_h + gap
    d.text((x, ys), "Movie & TV tracker · Material 3 Expressive",
           font=sub_f, fill=MUTED)
    yr = ys + s_h + rule_gap
    d.rounded_rectangle([x, yr, x + int(title_px * 1.6), yr + rule_h],
                        radius=rule_h // 2, fill=TEAL)

    im.save(out)
    print(f"  {os.path.basename(out)} — {w}×{h}")


def main():
    if not os.path.exists(f"{ROOT}/docs/logo/E-zasechka.svg"):
        sys.exit("нет docs/logo/E-zasechka.svg")
    os.makedirs(OUT, exist_ok=True)

    banner(1280, 384, f"{OUT}/readme-banner.png",
           mark_size=160, pad=96, title_px=104, sub_px=27)
    banner(1024, 307, f"{OUT}/site-banner.png",
           mark_size=128, pad=76, title_px=83, sub_px=22)

    # RGBA обязателен: у сквиркла углы прозрачные. convert("RGB") зальёт их
    # чёрным — на тёмном сайте это незаметно, но favicon на светлой вкладке
    # получит чёрную кайму вокруг знака.
    render_mark(256).save(f"{OUT}/site-icon.png")
    print("  site-icon.png — 256×256 (RGBA)")


if __name__ == "__main__":
    main()
