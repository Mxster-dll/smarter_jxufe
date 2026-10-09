# -*- coding: utf-8 -*-
"""把 assets/campus_map/*.json 渲染成 PNG 预览图（纯 Python，只用标准库 + Pillow）。

用途：**不跑 Flutter** 也能肉眼核对几何数据是否正确（环没闭合、跑偏、
把邻校画进来这类错误，看一张图就知道）。

运行： .venv\\Scripts\\python.exe tool\\jxufe_map/render_preview.py
产物： tool/jxufe_map/_preview/<key>.png
"""
from __future__ import annotations

import json
import math
import os

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
SRC = os.path.join(REPO, "assets", "campus_map")

# 预览图也落在仓库**之外**的用户级缓存目录（与 `fetch_osm.py` 的 RAW 同处）：
# 4 张 PNG 共约 80KB，属一次性的肉眼核对产物，不该进公开仓库。
OUT = os.environ.get(
    "JXUFE_MAP_RAW",
    os.path.join(
        os.environ.get("LOCALAPPDATA") or os.path.expanduser("~"),
        "smarter_jxufe",
        "jxufe_map",
    ),
)
KEYS = ["jiaoqiao", "mailu", "fenglin", "qingshan"]

W, H, PAD = 1000, 800, 40

# 与渲染端两套风格对齐的取色（浅色主题）
C = {
    "bg": "#F5F5F0",
    "water": "#A7CBE3",
    "green": "#CFE0BF",
    "sport": "#E8D9A8",
    "road": "#FFFFFF",
    "road_edge": "#D8D4CC",
    "building": "#DDD6CB",
    "building_named": "#C9BFB0",
    "label": "#3A3630",
    "outline": "#B9B2A6",
}


def m_lon(lat):
    return 111320.0 * math.cos(math.radians(lat))


def main() -> int:
    os.makedirs(OUT, exist_ok=True)
    for key in KEYS:
        p = os.path.join(SRC, f"{key}.json")
        if not os.path.exists(p):
            continue
        d = json.load(open(p, encoding="utf-8"))
        w, s, e, n = d["bounds"]
        lat0 = (s + n) / 2
        kx, ky = m_lon(lat0), 110574.0
        spanx = max((e - w) * kx, 1e-6)
        spany = max((n - s) * ky, 1e-6)
        k = min((W - 2 * PAD) / spanx, (H - 2 * PAD) / spany)
        ox = (W - spanx * k) / 2 - w * kx * k
        oy = (H + spany * k) / 2 + s * ky * k  # y 翻转

        def T(lon, lat):
            return (ox + lon * kx * k, oy - lat * ky * k)

        img = Image.new("RGB", (W, H), C["bg"])
        dr = ImageDraw.Draw(img)

        def poly(pts, fill, outline=None, width=1):
            if len(pts) >= 3:
                dr.polygon(pts, fill=fill, outline=outline, width=width)

        def line(pts, fill, width):
            if len(pts) >= 2:
                dr.line(pts, fill=fill, width=width, joint="curve")

        for it in d["green"]:
            poly([T(*q) for q in it["p"]], C["green"])
        for it in d["sport"]:
            poly([T(*q) for q in it["p"]], C["sport"], C["outline"], 1)
        for it in d["water"]:
            pts = [T(*q) for q in it["p"]]
            if len(pts) >= 3 and pts[0] == pts[-1]:
                poly(pts, C["water"], "#6F9FC2", 2)
            else:
                line(pts, C["water"], 6)
        for it in d["road"]:
            line([T(*q) for q in it["p"]], C["road_edge"], it["w"] * 2 + 2)
        for it in d["road"]:
            line([T(*q) for q in it["p"]], C["road"], it["w"] * 2)
        for it in d["building"]:
            named = bool(it.get("n"))
            poly([T(*q) for q in it["p"]],
                 C["building_named"] if named else C["building"],
                 C["outline"], 1)
        # 标签（只画 pri>=2，模拟渲染端的优先级）
        for lb in d["label"]:
            if lb["pri"] < 2:
                continue
            x, y = T(lb["x"], lb["y"])
            dr.text((x + 2, y + 2), lb["n"], fill=C["label"])

        # 图例
        dr.rectangle([0, 0, W - 1, H - 1], outline="#999999")
        counts = {kk: len(d[kk]) for kk in
                  ("building", "road", "water", "green", "sport", "label")}
        dr.text((10, 10), f"{key}  {d['name']}  clip={d['clip']}", fill="#000000")
        dr.text((10, 26), f"counts={counts}", fill="#555555")
        dst = os.path.join(OUT, f"{key}.png")
        img.save(dst)
        print(f"-> {dst}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
