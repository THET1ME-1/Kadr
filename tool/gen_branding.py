#!/usr/bin/env python3
"""Генератор брендинга Kadr: баннер для README и ассеты сайта (gh-pages).

Собирает основное лого «Сияние» (docs/logo/glow-master.png, бирюзовый
градиент на тёмном) с типографикой ДНК (Unbounded/Onest). Фон баннеров —
цвет фона мастера, поэтому знак стоит на нём без видимой подложки.

Кладёт:
  * docs/branding/readme-banner.png     — 1280×384, шапка README
  * docs/branding/site-icon.png         — 256×256, иконка сайта и favicon
  * docs/branding/site-banner.png       — 1024×307, баннер в подвале сайта
  * android/.../drawable/tv_banner.png  — 320×180, баннер лаунчера Android TV

Файлы сайта копируются в ветку gh-pages вручную (assets/icon.png, assets/banner.png).

Запуск: python3 tool/gen_branding.py
Требует: ImageMagick (magick), Pillow, numpy.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_icons  # noqa: E402  — разметка мастера и маска подложки общие

ROOT = gen_icons.ROOT
OUT = f"{ROOT}/docs/branding"
TV_BANNER = f"{gen_icons.RES}/drawable/tv_banner.png"
FONTS = f"{ROOT}/assets/fonts"

MASTER, BG = gen_icons.RASTER["glow"]
TEAL = "#1ED8E6"   # бирюза с мастера, для черты под заголовком
WHITE = "#FFFFFF"
MUTED = (125, 141, 145)


def glow_source():
    return Image.open(MASTER).convert("RGB")


def render_mark(size):
    """Иконка как на телефоне: знак на сквиркле с прозрачными углами."""
    im = gen_icons.raster_tile(glow_source(), BG, size, gen_icons.LEGACY_SCALE)
    im = im.convert("RGBA")
    im.putalpha(gen_icons.plate_mask("squircle", size))
    return im


def render_flat(size):
    """Знак крупно на квадрате фона мастера — для баннеров того же фона."""
    return gen_icons.raster_tile(glow_source(), BG, size, 1.0)


def font(name, size, weight):
    """Вариативный шрифт ДНК: выставляем ось wght явно."""
    f = ImageFont.truetype(f"{FONTS}/{name}.ttf", size)
    try:
        f.set_variation_by_axes([weight])
    except Exception:
        pass  # статический экземпляр — вес уже вшит
    return f


def banner(w, h, out, mark_size, pad, title_px, sub_px,
           subtitle="Movie & TV tracker · Material 3 Expressive"):
    im = Image.new("RGB", (w, h), BG)
    d = ImageDraw.Draw(im)

    im.paste(render_flat(mark_size), (pad, (h - mark_size) // 2))

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
    d.text((x, ys), subtitle, font=sub_f, fill=MUTED)
    yr = ys + s_h + rule_gap
    d.rounded_rectangle([x, yr, x + int(title_px * 1.6), yr + rule_h],
                        radius=rule_h // 2, fill=TEAL)

    im.save(out)
    print(f"  {os.path.basename(out)} — {w}×{h}")


def main():
    if not os.path.exists(MASTER):
        sys.exit(f"нет мастера: {MASTER}")
    os.makedirs(OUT, exist_ok=True)

    banner(1280, 384, f"{OUT}/readme-banner.png",
           mark_size=160, pad=96, title_px=104, sub_px=27)
    banner(1024, 307, f"{OUT}/site-banner.png",
           mark_size=128, pad=76, title_px=83, sub_px=22)
    banner(320, 180, TV_BANNER,
           mark_size=96, pad=22, title_px=40, sub_px=14,
           subtitle="Трекер фильмов")

    # RGBA обязателен: у сквиркла углы прозрачные. convert("RGB") зальёт их
    # тёмным — на тёмном сайте это незаметно, но favicon на светлой вкладке
    # получит тёмную кайму вокруг знака.
    render_mark(256).save(f"{OUT}/site-icon.png")
    print("  site-icon.png — 256×256 (RGBA)")


if __name__ == "__main__":
    main()
