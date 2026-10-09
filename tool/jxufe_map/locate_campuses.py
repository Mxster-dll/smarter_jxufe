# -*- coding: utf-8 -*-
"""定位收尾：找 玉屏大道 / 枫林大道，并列出各候选建筑簇的名字，判定校区归属。

产物 tool/jxufe_map/_raw/_locate.json
"""
from __future__ import annotations

import json
import os
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
            time.sleep(8 * (i + 1))
    raise RuntimeError(f"overpass failed: {last}")


def seg_center(g):
    return (round(sum(p["lat"] for p in g) / len(g), 5),
            round(sum(p["lon"] for p in g) / len(g), 5))


def main() -> int:
    out = {}

    # 1) 玉屏大道 / 枫林大道 这些路名
    print("1) 路名 ...")
    q = """[out:json][timeout:120];
way["highway"]["name"~"玉屏大道|枫林大道|玉屏西大街|枫林大道"](28.68,115.76,28.80,115.90);
out geom tags;"""
    j = overpass(q)
    roads = {}
    for e in j.get("elements", []):
        nm = e.get("tags", {}).get("name")
        g = e.get("geometry")
        if not nm or not g:
            continue
        roads.setdefault(nm, []).append(seg_center(g))
    out["roads"] = {k: {"segs": len(v), "centers": v[:12]} for k, v in roads.items()}

    # 2) 两个候选区域内的建筑名字（判定校区归属）
    print("2) 建筑簇 ...")
    for tag, (s, w, n, e_) in {
        "south_cluster_28.720_28.727": (28.7195, 115.8165, 28.7270, 115.8265),
        "fenglin_poly_28.732_28.739": (28.7320, 115.8280, 28.7390, 115.8345),
        "mailu_poly_28.726_28.735": (28.7260, 115.8075, 28.7355, 115.8155),
        "qingshan_28.705_28.710": (28.7045, 115.9095, 28.7110, 115.9155),
    }.items():
        q2 = f"""[out:json][timeout:120];
(
  way["building"]({s},{w},{n},{e_});
  way["amenity"~"university|college|school"]({s},{w},{n},{e_});
  node["amenity"]({s},{w},{n},{e_});
);
out geom tags;"""
        j2 = overpass(q2)
        names, kinds = [], {}
        for el in j2.get("elements", []):
            t = el.get("tags", {})
            nm = t.get("name")
            if nm:
                names.append(nm)
            for k in ("amenity", "building"):
                if k in t:
                    kinds[f"{k}={t[k]}"] = kinds.get(f"{k}={t[k]}", 0) + 1
        out[tag] = {"elements": len(j2.get("elements", [])),
                    "named": sorted(set(names)),
                    "kinds": dict(sorted(kinds.items(), key=lambda kv: -kv[1])[:10])}

    dst = os.path.join(RAW, "_locate.json")
    with open(dst, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
    print(f"-> {dst}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
