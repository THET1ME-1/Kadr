#!/usr/bin/env python3
"""Генератор launcher-иконок Kadr — знак «Засечка».

Основная иконка «Сияние» (glow) — растровый мастер docs/logo/glow-master.png:
бирюзовый градиент на тёмном фоне, утверждён 2026-09-16 как лого приложения.
Три плоские колеровки рисуются из вектора docs/logo/E-zasechka.svg
(см. docs/logo_prompt.md) и остаются в пикере как выбор.

Для каждой колеровки кладёт:
  * mipmap-<d>dpi/ic_launcher_<v>.png        — legacy, сквиркл с прозрачными углами
  * mipmap-<d>dpi/ic_launcher_<v>_round.png  — legacy круглая
  * mipmap-<d>dpi/ic_fg_<v>.png              — foreground для adaptive (знак в safe zone)
  * mipmap-anydpi-v26/ic_launcher_<v>.xml    — adaptive (цвет фона + foreground)
  * values/ic_launcher_colors.xml            — цвета фонов

У glow ещё mipmap-<d>dpi/ic_mono_glow.png — силуэт для тематических иконок
Android 13 (foreground у неё непрозрачный и в monochrome не годится), и
assets/icon/app_icon.png — та же иконка для экранов приложения.

Колеровка по умолчанию (glow) дублируется в ic_launcher.* — иконка
приложения вне лаунчера.

Запуск: python3 tool/gen_icons.py
Требует: ImageMagick (magick), Pillow, numpy.
"""
import os
import re
import shutil
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = f"{ROOT}/android/app/src/main/res"
SIGN = f"{ROOT}/docs/logo/E-zasechka.svg"
GLOW = f"{ROOT}/docs/logo/glow-master.png"
APP_ICON = f"{ROOT}/assets/icon/app_icon.png"

TEAL = "#00B5C7"
INK = "#0E1316"
WHITE = "#FFFFFF"

# id → (цвет знака, цвет фона). Порядок = порядок в пикере.
VARIANTS = {
    "ink": (INK, TEAL),        # по умолчанию: тёмный знак на бирюзовой подложке
    "graphite": (TEAL, INK),   # бирюза на графите
    "white": (WHITE, TEAL),    # белый на бирюзе
}
# Растровые колеровки: id → (мастер, цвет фона мастера). Порядок в пикере —
# впереди векторных.
RASTER = {
    "glow": (GLOW, "#0B0D13"),
}
DEFAULT = "glow"

# Разметка мастера glow: центр и сторона знака в пикселях 1254×1254 (по рамке
# пикселей ярче фона). Знак в SVG занимает 84 единицы из 100 — по этой паре
# растр ужимается до того же видимого размера, что и векторные колеровки.
GLOW_CENTER = (626.5, 620.5)
GLOW_MARK = 842
SIGN_SPAN = 0.84

# legacy: итоговый размер иконки в px
DENSITIES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
# adaptive: канва 108dp, знак живёт в безопасном круге ⌀66dp
FG_DENSITIES = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}
# Доля канвы 108dp под знак (adaptive). Знак сам сквиркл: чем он крупнее, тем
# сильнее распирает маску лаунчера — подложка вырождается в кайму, а на тёмных
# обоях графитовый фон вовсе пропадает и знак «парит». Держим знак мелким,
# чтобы фон читался полноценной плашкой.
FG_SCALE = 0.46
# Legacy рисуется на своей подложке во всю канву, adaptive — на 108dp при
# видимых 72dp. Множитель 108/72 приводит оба к одному видимому размеру знака.
LEGACY_SCALE = round(FG_SCALE * 108 / 72, 2)  # = 0.69

SS = 4  # суперсэмплинг: рендерим крупно, ужимаем с ресемплом


def sign_body(fill: str, uid: str) -> str:
    """Внутренности знака с нужной заливкой и уникальным id обрезки."""
    src = open(SIGN).read()
    inner = re.search(r"<svg[^>]*>(.*)</svg>", src, re.S).group(1).strip()
    return (inner.replace('id="n"', f'id="{uid}"')
                 .replace("url(#n)", f"url(#{uid})")
                 .replace('fill="currentColor"', f'fill="{fill}"'))


def compose(fill, bg, scale, shape, uid):
    """SVG: подложка (squircle/circle/none) + знак, ужатый к центру."""
    off = 50 * (1 - scale)
    if shape == "squircle":
        # тот же суперэллипс n=4, что и у знака — подложка не спорит с формой
        a, k = 50.0, 45.46
        plate = (f'<path fill="{bg}" d="M {50+a} 50 C {50+a} {50+k}, {50+k} {50+a}, 50 {50+a} '
                 f'C {50-k} {50+a}, {50-a} {50+k}, {50-a} 50 '
                 f'C {50-a} {50-k}, {50-k} {50-a}, 50 {50-a} '
                 f'C {50+k} {50-a}, {50+a} {50-k}, {50+a} 50 Z"/>')
    elif shape == "circle":
        plate = f'<circle cx="50" cy="50" r="50" fill="{bg}"/>'
    else:  # adaptive foreground — фон рисует система
        plate = ""
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">'
            f'{plate}<g transform="translate({off:.3f} {off:.3f}) scale({scale})">'
            f'{sign_body(fill, uid)}</g></svg>')


def render(svg: str, size: int, out: str):
    tmp = f"/tmp/_kadr_icon_{os.getpid()}.svg"
    open(tmp, "w").write(svg)
    subprocess.run(["magick", "-background", "none", "-density", "1200", tmp,
                    "-resize", f"{size * SS}x{size * SS}",
                    "-resize", f"{size}x{size}", out], check=True)
    os.remove(tmp)


def raster_tile(src: Image.Image, bg: str, size: int, scale: float) -> Image.Image:
    """Мастер на квадрате size×size: знак по центру, как у векторного при scale.

    Мастер кладётся на канву с его же фоном (фон плоский, шум ±1 уровень —
    шва не видно), затем канва целиком ужимается до size.
    """
    n = round(GLOW_MARK / (SIGN_SPAN * scale))
    canvas = Image.new("RGB", (n, n), bg)
    canvas.paste(src, (round(n / 2 - GLOW_CENTER[0]), round(n / 2 - GLOW_CENTER[1])))
    return canvas.resize((size, size), Image.LANCZOS)


def plate_mask(shape: str, size: int) -> Image.Image:
    """Альфа подложки: тот же сквиркл, что у векторных legacy-иконок, или круг."""
    if shape == "circle":
        big = Image.new("L", (size * SS, size * SS), 0)
        ImageDraw.Draw(big).ellipse([0, 0, size * SS - 1, size * SS - 1], fill=255)
        return big.resize((size, size), Image.LANCZOS)
    # знак белым по белому: в альфе остаётся одна подложка
    svg = compose("#FFFFFF", "#FFFFFF", 0.5, "squircle", "m")
    out = f"/tmp/_kadr_mask_{os.getpid()}.png"
    render(svg, size, out)
    alpha = Image.open(out).getchannel("A")
    os.remove(out)
    return alpha


def silhouette(tile: Image.Image) -> Image.Image:
    """Белый силуэт знака с альфой из яркости: тело знака — бирюза с каналом
    не темнее 130, фон и сквозные вырезы — не светлее 20."""
    peak = np.asarray(tile.convert("RGB")).max(axis=2).astype(float)
    alpha = np.clip((peak - 20) / 110, 0, 1) * 255
    out = Image.new("RGBA", tile.size, (255, 255, 255, 0))
    out.putalpha(Image.fromarray(alpha.astype(np.uint8)))
    return out


def gen_raster(vid: str, master: str, bg: str):
    src = Image.open(master).convert("RGB")
    for dens, size in DENSITIES.items():
        d = f"{RES}/mipmap-{dens}"
        os.makedirs(d, exist_ok=True)
        tile = raster_tile(src, bg, size, LEGACY_SCALE)
        for suffix, shape in (("", "squircle"), ("_round", "circle")):
            icon = tile.convert("RGBA")
            icon.putalpha(plate_mask(shape, size))
            icon.save(f"{d}/ic_launcher_{vid}{suffix}.png")
    for dens, size in FG_DENSITIES.items():
        d = f"{RES}/mipmap-{dens}"
        # foreground непрозрачный: фон мастера совпадает с цветом ic_bg_<id>
        tile = raster_tile(src, bg, size, FG_SCALE)
        tile.save(f"{d}/ic_fg_{vid}.png")
        silhouette(tile).save(f"{d}/ic_mono_{vid}.png")

    d26 = f"{RES}/mipmap-anydpi-v26"
    os.makedirs(d26, exist_ok=True)
    open(f"{d26}/ic_launcher_{vid}.xml", "w").write(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        f'    <background android:drawable="@color/ic_bg_{vid}"/>\n'
        f'    <foreground android:drawable="@mipmap/ic_fg_{vid}"/>\n'
        f'    <monochrome android:drawable="@mipmap/ic_mono_{vid}"/>\n'
        '</adaptive-icon>\n')

    if vid == DEFAULT:
        # экраны приложения («О приложении», пикер): квадрат, скругляет ClipRRect
        raster_tile(src, bg, 512, LEGACY_SCALE).save(APP_ICON)
    print(f"  {vid}: растр {os.path.basename(master)} на {bg}")


def main():
    if not shutil.which("magick"):
        sys.exit("нужен ImageMagick (magick)")
    if not os.path.exists(SIGN):
        sys.exit(f"нет файла знака: {SIGN}")

    for vid, (master, bg) in RASTER.items():
        if not os.path.exists(master):
            sys.exit(f"нет мастера: {master}")
        gen_raster(vid, master, bg)

    for vid, (fill, bg) in VARIANTS.items():
        for dens, size in DENSITIES.items():
            d = f"{RES}/mipmap-{dens}"
            os.makedirs(d, exist_ok=True)
            render(compose(fill, bg, LEGACY_SCALE, "squircle", f"c-{vid}-s"),
                   size, f"{d}/ic_launcher_{vid}.png")
            render(compose(fill, bg, LEGACY_SCALE, "circle", f"c-{vid}-r"),
                   size, f"{d}/ic_launcher_{vid}_round.png")
        for dens, size in FG_DENSITIES.items():
            d = f"{RES}/mipmap-{dens}"
            render(compose(fill, bg, FG_SCALE, "none", f"c-{vid}-f"),
                   size, f"{d}/ic_fg_{vid}.png")

        # adaptive: фон — плоский цвет, знак — foreground
        d26 = f"{RES}/mipmap-anydpi-v26"
        os.makedirs(d26, exist_ok=True)
        open(f"{d26}/ic_launcher_{vid}.xml", "w").write(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            f'    <background android:drawable="@color/ic_bg_{vid}"/>\n'
            f'    <foreground android:drawable="@mipmap/ic_fg_{vid}"/>\n'
            f'    <monochrome android:drawable="@mipmap/ic_fg_{vid}"/>\n'
            '</adaptive-icon>\n')
        print(f"  {vid}: знак {fill} на {bg}")

    # цвета фонов
    os.makedirs(f"{RES}/values", exist_ok=True)
    backgrounds = {v: bg for v, (_, bg) in {**RASTER, **VARIANTS}.items()}
    colors = "\n".join(f'    <color name="ic_bg_{v}">{bg}</color>'
                       for v, bg in backgrounds.items())
    open(f"{RES}/values/ic_launcher_colors.xml", "w").write(
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
        f'{colors}\n</resources>\n')

    # дефолтная колеровка → ic_launcher.*
    for dens in DENSITIES:
        d = f"{RES}/mipmap-{dens}"
        shutil.copy(f"{d}/ic_launcher_{DEFAULT}.png", f"{d}/ic_launcher.png")
        shutil.copy(f"{d}/ic_launcher_{DEFAULT}_round.png", f"{d}/ic_launcher_round.png")
        shutil.copy(f"{d}/ic_fg_{DEFAULT}.png", f"{d}/ic_fg.png")
    shutil.copy(f"{RES}/mipmap-anydpi-v26/ic_launcher_{DEFAULT}.xml",
                f"{RES}/mipmap-anydpi-v26/ic_launcher.xml")
    # ic_launcher.xml ссылается на ic_fg_<default>; для round — та же adaptive
    shutil.copy(f"{RES}/mipmap-anydpi-v26/ic_launcher_{DEFAULT}.xml",
                f"{RES}/mipmap-anydpi-v26/ic_launcher_round.xml")
    for vid in [*RASTER, *VARIANTS]:
        shutil.copy(f"{RES}/mipmap-anydpi-v26/ic_launcher_{vid}.xml",
                    f"{RES}/mipmap-anydpi-v26/ic_launcher_{vid}_round.xml")
    print(f"дефолт → ic_launcher.* ({DEFAULT})")


if __name__ == "__main__":
    main()
