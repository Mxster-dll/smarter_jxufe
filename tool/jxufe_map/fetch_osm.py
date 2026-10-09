# -*- coding: utf-8 -*-
"""抓取江西财经大学四校区的 OSM 要素（只读网络，产物落 tool/jxufe_map/_raw/）。

运行： .venv\\Scripts\\python.exe tool\\jxufe_map\\fetch_osm.py [--only KEY] [--force]

为什么拆成多条小查询：Overpass 实测对「一条大 UNION 查询」频繁 504/500
（2026-10 实测，overpass-api.de 与 kumi.systems 都会超时）。拆成面积要素 /
线要素 / 命名节点三条分别请求，再在本地合并，成功率显著提高。
数据来源 Overpass API（ODbL，© OpenStreetMap contributors）。
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))

# ⚠ 原始快照**刻意不落在仓库里**（两个原因，都实测踩过）：
# 1. OSM 原始 JSON 带着商家的真实手机号（`contact:phone`），而本仓是**公开仓库**；
#    `test/privacy_guard_test.dart` 会扫 `tool/` 目录（它**不看 .gitignore**），
#    留在仓库里就必然报「手机号 N 命中」。
# 2. 单个 0.4–1MB、四个校区共约 2MB，而 `fetch_osm.py` 能完整重抓。
# 所以放用户级缓存目录，可用 `JXUFE_MAP_RAW` 覆盖。
RAW = os.environ.get(
    "JXUFE_MAP_RAW",
    os.path.join(
        os.environ.get("LOCALAPPDATA") or os.path.expanduser("~"),
        "smarter_jxufe",
        "jxufe_map",
    ),
)

ENDPOINTS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
]
UA = {"User-Agent": "smarter_jxufe-dev/1.0 (JXUFE campus map; ODbL attribution)"}

# 校区中心与半边长（度）。bbox 给宽一点保证校园多边形完整落在里面，
# 最终裁剪由 build_geometry.py 按多边形做。
CAMPUSES = {
    "jiaoqiao": {"name": "蛟桥园校区", "lat": 28.7466, "lon": 115.8500, "d": 0.013},
    "mailu": {"name": "麦庐园校区", "lat": 28.7307, "lon": 115.8115, "d": 0.014},
    "fenglin": {"name": "枫林园校区", "lat": 28.7355, "lon": 115.8311, "d": 0.012},
    "qingshan": {"name": "青山园校区", "lat": 28.7077, "lon": 115.9122, "d": 0.012},
}


def bbox_of(c: dict) -> str:
    d = c["d"]
    return f"{c['lat'] - d},{c['lon'] - d},{c['lat'] + d},{c['lon'] + d}"


def queries(c: dict) -> dict[str, str]:
    """三条互补的小查询。返回值顺序即请求顺序。"""
    b = bbox_of(c)
    hdr = "[out:json][timeout:90];"
    return {
        "area": f"""{hdr}
(
  way["building"]({b});
  way["landuse"]({b});
  way["leisure"]({b});
  way["natural"]({b});
  way["amenity"]({b});
);
out geom tags;""",
        "line": f"""{hdr}
(
  way["highway"]({b});
  way["waterway"]({b});
  way["railway"]({b});
  way["barrier"]({b});
);
out geom tags;""",
        "node": f"""{hdr}
(
  node["amenity"]["name"]({b});
  node["shop"]["name"]({b});
  node["highway"="bus_stop"]({b});
  node["railway"]({b});
  node["entrance"]({b});
  way["amenity"~"university|college"]["name"]({b});
);
out geom tags;""",
    }


def overpass(query: str, tries: int = 5) -> dict:
    body = urllib.parse.urlencode({"data": query}).encode()
    last: Exception | None = None
    for attempt in range(tries):
        for ep in ENDPOINTS:
            try:
                req = urllib.request.Request(ep, data=body, headers=UA)
                with urllib.request.urlopen(req, timeout=200) as r:
                    return json.loads(r.read().decode("utf-8"))
            except Exception as e:  # noqa: BLE001
                last = e
                print(f"    {ep.split('/')[2]}: {e}", file=sys.stderr)
        time.sleep(15 * (attempt + 1))  # Overpass 限流，退避要够长
    raise RuntimeError(f"overpass 全部失败: {last}")


def fetch_campus(key: str, c: dict, force: bool) -> int:
    dst = os.path.join(RAW, f"{key}.json")
    if os.path.exists(dst) and not force:
        print(f"{key}: 已存在，跳过（--force 可重抓）")
        return 0
    print(f"{key} {c['name']} bbox={bbox_of(c)}")
    merged: dict[int, dict] = {}
    for qname, q in queries(c).items():
        print(f"  查询 {qname} ...")
        j = overpass(q)
        els = j.get("elements", [])
        # node 与 way 的 id 空间独立，用 (type,id) 复合键去重
        for e in els:
            merged[(e["type"], e["id"])] = e
        print(f"    -> {len(els)} 个要素")
        time.sleep(6)
    out = {
        "_meta": {
            "campus": c["name"],
            "center": [c["lat"], c["lon"]],
            "bbox": [float(x) for x in bbox_of(c).split(",")],
            "source": "Overpass API · © OpenStreetMap contributors (ODbL)",
            "fetched_at": time.strftime("%Y-%m-%dT%H:%M:%S"),
        },
        "elements": list(merged.values()),
    }
    with open(dst, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False)
    print(f"  => {len(out['elements'])} 个要素(去重后), {os.path.getsize(dst) // 1024} KB")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--force", action="store_true", help="重抓已存在的文件")
    ap.add_argument("--only", help="只抓某个 key")
    args = ap.parse_args()

    os.makedirs(RAW, exist_ok=True)
    failed = []
    for key, c in CAMPUSES.items():
        if args.only and key != args.only:
            continue
        try:
            fetch_campus(key, c, args.force)
        except Exception as e:  # noqa: BLE001
            print(f"{key}: 失败 {e}", file=sys.stderr)
            failed.append(key)
        time.sleep(10)
    if failed:
        print(f"\n未拿到: {', '.join(failed)}（可单独重跑 --only）", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
