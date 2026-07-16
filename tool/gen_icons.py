#!/usr/bin/env python3
"""Генератор launcher-иконок Kadr — знак «Засечка» в трёх колеровках.

Геометрия знака — docs/logo/E-zasechka.svg (см. docs/logo_prompt.md):
монолит-сквиркл со срезанным верхним правым углом, play и перфорация —
СКВОЗНЫЕ вырезы, заливка строго плоская (градиенты запрещены).

Для каждой колеровки кладёт:
  * mipmap-<d>dpi/ic_launcher_<v>.png        — legacy, сквиркл с прозрачными углами
  * mipmap-<d>dpi/ic_launcher_<v>_round.png  — legacy круглая
  * mipmap-<d>dpi/ic_fg_<v>.png              — foreground для adaptive (знак в safe zone)
  * mipmap-anydpi-v26/ic_launcher_<v>.xml    — adaptive (цвет фона + foreground)
  * values/ic_launcher_colors.xml            — цвета фонов

Колеровка по умолчанию (graphite) дублируется в ic_launcher.* — иконка
приложения вне лаунчера.

Запуск: python3 tool/gen_icons.py
Требует: ImageMagick (magick).
"""
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = f"{ROOT}/android/app/src/main/res"
SIGN = f"{ROOT}/docs/logo/E-zasechka.svg"

TEAL = "#00B5C7"
INK = "#0E1316"
WHITE = "#FFFFFF"

# id → (цвет знака, цвет фона). Порядок = порядок в пикере.
VARIANTS = {
    "ink": (INK, TEAL),        # по умолчанию: тёмный знак на бирюзовой подложке
    "graphite": (TEAL, INK),   # бирюза на графите
    "white": (WHITE, TEAL),    # белый на бирюзе
}
DEFAULT = "ink"

# legacy: итоговый размер иконки в px
DENSITIES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
# adaptive: канва 108dp, знак живёт в безопасном круге ⌀66dp
FG_DENSITIES = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}
# Доля канвы 108dp под знак. 0.68 формально влезает в safe zone ⌀66dp, но знак
# сам сквиркл: под сквиркл-маской лаунчера получался сквиркл в сквиркле (фон —
# тонкая кайма), а под круглой маской срезанный угол резался краем. 0.56 даёт
# воздух вокруг знака и сохраняет срез на любой маске.
FG_SCALE = 0.56
LEGACY_SCALE = 0.78  # знак внутри legacy-подложки

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


def main():
    if not shutil.which("magick"):
        sys.exit("нужен ImageMagick (magick)")
    if not os.path.exists(SIGN):
        sys.exit(f"нет файла знака: {SIGN}")

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
    colors = "\n".join(f'    <color name="ic_bg_{v}">{bg}</color>'
                       for v, (_, bg) in VARIANTS.items())
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
    for vid in VARIANTS:
        shutil.copy(f"{RES}/mipmap-anydpi-v26/ic_launcher_{vid}.xml",
                    f"{RES}/mipmap-anydpi-v26/ic_launcher_{vid}_round.xml")
    print(f"дефолт → ic_launcher.* ({DEFAULT})")


if __name__ == "__main__":
    main()
