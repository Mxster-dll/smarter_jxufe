# -*- coding: utf-8 -*-
"""校验：用「官方地址里的路名」给四校区定位（路名比 polygon 名字可靠）。

产物 tool/jxufe_map/_raw/_streets.json（UTF-8，供人工核对）。
"""
from __future__ import annotations

import json
import os
import sys
import time
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))

# 与 `fetch_osm.py` / `build_geometry.py` 同一个落点：仓库**之外**的用户级缓存
# （原因见 `fetch_osm.py` 顶部注释）。
RAW = os.environ.get(
    "JXUFE_MAP_RAW",
    os.path.join(
        os.environ.get("LOCALAPPDATA") or os.path.expanduser("~"),
        "smarter_jxufe",
        "jxufe_map",
    ),
)
UA = {"User-Agent": "smarter_jxufe-dev/1.0 (JXUFE campus map; ODbL)"}

STREETS = ["双港东大街", "玉屏大道", "枫林大道", "青山南路", "庐山南大道",
           "枫林西大街", "菊圃路", "瑞香路", "海棠南路"]
# 学校官网 / 高德 常见的校区地标名，一并在 OSM 里找
LANDMARKS = ["江西财经大学", "麦庐园", "枫林园", "蛟桥园", "青山园", "下罗",
             "江西财经大学现代经济管理学院", "孔目湖"]


def overpass(query: str, tries: int = 4) -> dict:
    body = urllib.parse.urlencode({"data": query}).encode()
    last = None
    for i in range(tries):
        try:
            req = urllib.request.Request(
                "https://overpass-api.de/api/interpreter", data=body, headers=UA)
            with urllib.request.urlopen(req, timeout=200) as r:
                return json.loads(r.read().decode("utf-8"))
        except Exception as e:  # noqa: BLE001
            last = e
            time.sleep(10 * (i + 1))
    raise RuntimeError(f"overpass failed: {last}")


def summarize(els):
    out = {}
    for e in els:
        t = e.get("tags", {})
        nm = t.get("name")
        if not nm:
            continue
        g = e.get("geometry")
        if g:
            las = [p["lat"] for p in g]
            los = [p["lon"] for p in g]
        elif e.get("lat"):
            las, los = [e["lat"]], [e["lon"]]
        else:
            continue
        rec = out.setdefault(nm, {"n": 0, "lat": [], "lon": [], "kinds": set()})
        rec["n"] += 1
        rec["lat"] += [min(las), max(las)]
        rec["lon"] += [min(los), max(los)]
        for k in ("highway", "amenity", "place", "railway", "landuse", "building"):
            if k in t:
                rec["kinds"].add(f"{k}={t[k]}")
    res = {}
    for nm, r in out.items():
        res[nm] = {
            "count": r["n"],
            "center": [round(sum(r["lat"]) / len(r["lat"]), 5),
                       round(sum(r["lon"]) / len(r["lon"]), 5)],
            "bbox": [round(min(r["lat"]), 5), round(min(r["lon"]), 5),
                     round(max(r["lat"]), 5), round(max(r["lon"]), 5)],
            "kinds": sorted(r["kinds"])[:4],
        }
    return res


def main() -> int:
    os.makedirs(RAW, exist_ok=True)
    joined = "|".join(STREETS)
    lm = "|".join(LANDMARKS)
    out = {}

    print("1/2 路名 ...")
    q = f"""[out:json][timeout:180];
way["highway"]["name"~"^({joined})$"](28.60,115.72,28.85,115.99);
out geom tags;"""
    out["streets"] = summarize(overpass(q).get("elements", []))

    print("2/2 地标 ...")
    q2 = f"""[out:json][timeout:180];
(
  nwr["name"~"{lm}"](28.55,115.60,28.90,116.05);
  nwr["name:zh"~"{lm}"](28.55,115.60,28.90,116.05);
);
out geom tags;"""
    out["landmarks"] = summarize(overpass(q2).get("elements", []))

    dst = os.path.join(RAW, "_streets.json")
    with open(dst, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
    print(f"-> {dst}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
