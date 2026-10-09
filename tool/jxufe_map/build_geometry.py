# -*- coding: utf-8 -*-
"""把 _raw/ 的 OSM 快照整理成 App 可渲染的紧凑 JSON（落 assets/campus_map/）。

运行： .venv\\Scripts\\python.exe tool\\jxufe_map\\build_geometry.py

设计（对应 docs/agents/40-校区矢量地图.md）：
- 坐标系：**保留 WGS84 经纬度**，只在每份数据里带一个 `origin`。
  渲染端用 Web Mercator 投影到局部米制平面再画 —— 不引入任何地图库，
  与 Flutter 的 CustomPainter 天然契合。
- 裁剪：按校区 `amenity=university|college` 多边形（含周边缓冲）保留要素。
  校区由多个 way 组成（实测蛟桥园 = 2 个 way），故取**全部同名多边形的并集**。
- 分层：boundary / water / green / sport / road / building / poi / label。
- 简化：Douglas-Peucker（容差按米给），坐标量化到 6 位小数。
"""
from __future__ import annotations

import argparse
import json
import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from campus_anchors import CAMPUS_ANCHORS, CLIP_BUFFER_M  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))

# OSM 原始快照的落点 —— **与 `fetch_osm.py` 必须一致**，且刻意在仓库之外
# （理由见 `fetch_osm.py` 顶部注释：真实手机号 + 体积；可用 `JXUFE_MAP_RAW` 覆盖）。
RAW = os.environ.get(
    "JXUFE_MAP_RAW",
    os.path.join(
        os.environ.get("LOCALAPPDATA") or os.path.expanduser("~"),
        "smarter_jxufe",
        "jxufe_map",
    ),
)
OUT_DIR = os.path.join(REPO, "assets", "campus_map")

# 与 lib/features/campus_address/domain/my_campus.dart 的枚举名一一对应
CAMPUS_KEYS = ["jiaoqiao", "mailu", "fenglin", "qingshan"]

# 道路分级 → 渲染宽度档（渲染端据此选线宽，0 = 不画）
ROAD_CLASS = {
    "motorway": 5, "trunk": 5, "primary": 4, "secondary": 4, "tertiary": 3,
    "unclassified": 3, "residential": 3, "living_street": 2, "pedestrian": 2,
    "service": 1, "footway": 1, "path": 1, "steps": 1, "cycleway": 1, "track": 1,
}

# 建筑分类（渲染端据此上色）。顺序即优先级。
BUILDING_CLASS = [
    ("teaching", {"university", "college", "school", "yes", "public", "civic"}),
    ("dorm", {"dormitory", "residential", "apartments", "house"}),
    ("sport", {"sports_hall", "gym", "stadium"}),
    ("service", {"service", "industrial", "warehouse", "garage", "garages",
                 "commercial", "retail", "office", "hotel", "hospital"}),
]

GREEN_TAGS = {"grass", "wood", "forest", "scrub", "park", "garden", "meadow",
              "village_green", "recreation_ground", "cemetery"}
SPORT_LEISURE = {"pitch", "track", "sports_centre", "stadium", "swimming_pool",
                 "fitness_station", "playground"}

LON_M = 111320.0


def m_per_deg_lat(lat: float) -> float:
    return 110574.0


def m_per_deg_lon(lat: float) -> float:
    return LON_M * math.cos(math.radians(lat))


def dist_m(a, b, lat: float) -> float:
    """a/b = (lon, lat)。"""
    dx = (a[0] - b[0]) * m_per_deg_lon(lat)
    dy = (a[1] - b[1]) * m_per_deg_lat(lat)
    return math.hypot(dx, dy)


def dp_simplify(pts, tol_m: float, lat: float):
    """Douglas-Peucker。pts = [(lon,lat),...]；点数 < 3 原样返回。"""
    if len(pts) < 3 or tol_m <= 0:
        return pts
    keep = [False] * len(pts)
    keep[0] = keep[-1] = True
    stack = [(0, len(pts) - 1)]
    while stack:
        i, j = stack.pop()
        if j <= i + 1:
            continue
        ax, ay = pts[i]
        bx, by = pts[j]
        dx, dy = bx - ax, by - ay
        seg = math.hypot(dx * m_per_deg_lon(lat), dy * m_per_deg_lat(lat))
        best, bi = -1.0, -1
        for k in range(i + 1, j):
            px, py = pts[k]
            if seg < 1e-9:
                d = dist_m(pts[k], pts[i], lat)
            else:
                t = ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)
                t = max(0.0, min(1.0, t))
                d = dist_m(pts[k], (ax + t * dx, ay + t * dy), lat)
            if d > best:
                best, bi = d, k
        if best > tol_m:
            keep[bi] = True
            stack.append((i, bi))
            stack.append((bi, j))
    return [p for p, k in zip(pts, keep) if k]


def ring_closed(pts, tol_m: float, lat: float):
    """闭合环简化：保持首尾相同。"""
    if len(pts) < 4:
        return pts
    closed = pts[0] == pts[-1]
    core = pts[:-1] if closed else pts
    if len(core) < 3:
        return pts
    # 对闭合环，先固定首点与「最远点」再跑 DP，避免起点选在直边上退化
    out = dp_simplify(core + [core[0]], tol_m, lat)
    if out[0] != out[-1]:
        out.append(out[0])
    return out


def ring_area_m2(pts, lat: float) -> float:
    """鞋带公式，单位平方米。"""
    if len(pts) < 3:
        return 0.0
    k = m_per_deg_lon(lat) * m_per_deg_lat(lat)
    s = 0.0
    for i in range(len(pts) - 1):
        s += pts[i][0] * pts[i + 1][1] - pts[i + 1][0] * pts[i][1]
    return abs(s) * k / 2.0


def point_in_ring(p, ring) -> bool:
    x, y = p
    inside = False
    n = len(ring)
    for i in range(n):
        x1, y1 = ring[i]
        x2, y2 = ring[(i + 1) % n]
        if (y1 > y) != (y2 > y):
            xin = (x2 - x1) * (y - y1) / (y2 - y1) + x1
            if x < xin:
                inside = not inside
    return inside


def point_in_any(p, rings) -> bool:
    return any(point_in_ring(p, r) for r in rings)


def ring_within_buffered(p, rings, lat: float, buf: float) -> bool:
    """多边形是否落在「校区并集 + buf 米」内：任一点在校区内，或离边界足够近。"""
    if point_in_any(p, rings):
        return True
    for r in rings:
        for q in r:
            if dist_m(p, q, lat) <= buf:
                return True
    return False


def way_centroid(geom):
    xs = [g["lon"] for g in geom]
    ys = [g["lat"] for g in geom]
    return (sum(xs) / len(xs), sum(ys) / len(ys))


def classify_building(tags) -> str:
    b = tags.get("building", "yes")
    for name, vals in BUILDING_CLASS:
        if b in vals:
            return name
    return "service"


def q(pts):
    """量化到 6 位小数并去掉连续重复点。"""
    out = []
    for lon, lat in pts:
        p = [round(lon, 6), round(lat, 6)]
        if not out or out[-1] != p:
            out.append(p)
    return out


def load_raw(key: str):
    p = os.path.join(RAW, f"{key}.json")
    if not os.path.exists(p):
        return None
    with open(p, encoding="utf-8") as f:
        return json.load(f)


def campus_rings(els, meta, anchor):
    """取校区多边形。

    ⚠ 不能用 `name` 精确匹配（见 campus_anchors.py 的说明）：蛟桥园是 2 个 way、
    枫林园在 OSM 里叫「枫庐园」。做法 = 在「名字含『江西财经大学』的
    amenity=university|college 多边形」里，挑**包含锚点**（或中心离锚点最近）
    的那些，并把同一次抓取里所有命中的多边形取并集。
    """
    alat, alon, rad = anchor[1], anchor[2], anchor[3]
    cands = []
    for e in els:
        t = e.get("tags", {})
        if t.get("amenity") not in ("university", "college"):
            continue
        if "江西财经大学" not in t.get("name", ""):
            continue
        g = e.get("geometry")
        if not g or len(g) < 4:
            continue
        ring = [(p["lon"], p["lat"]) for p in g]
        cla = sum(p[1] for p in ring) / len(ring)
        clo = sum(p[0] for p in ring) / len(ring)
        d = math.hypot((cla - alat) * m_per_deg_lat(alat),
                       (clo - alon) * m_per_deg_lon(alat))
        if d > rad * 111320:
            continue
        cands.append({"ring": ring, "name": t["name"], "d": d})

    if not cands:
        s, w, n, e_ = meta["bbox"]
        return [[(w, s), (e_, s), (e_, n), (w, n), (w, s)]], "bbox-fallback", []

    # 以最近的那个为主，并入与它有重叠（质心相距 < 1.2km）的同校多边形
    cands.sort(key=lambda c: c["d"])
    main = cands[0]
    rings = [main["ring"]]
    used = [main["name"]]
    for c in cands[1:]:
        # 「蛟桥园南区 + 北区」两块相邻；「青科园」在麦庐园内部。都并入。
        if all(dist_m(_centroid(c["ring"]), _centroid(r), alat) < 1200 for r in rings):
            rings.append(c["ring"])
            used.append(c["name"])
    return rings, f"osm-campus-polygon({main['name']})", sorted(set(used))


def _centroid(ring):
    return (sum(p[0] for p in ring) / len(ring),
            sum(p[1] for p in ring) / len(ring))


def build_campus(key: str) -> dict | None:
    raw = load_raw(key)
    if raw is None:
        print(f"  {key}: 缺少 _raw/{key}.json，跳过")
        return None
    meta = raw["_meta"]
    els = raw["elements"]
    clat, clon = meta["center"]
    anchor = CAMPUS_ANCHORS[key]
    rings, clip_source, matched_names = campus_rings(els, meta, anchor)

    layers = {k: [] for k in
              ("water", "green", "sport", "road", "building", "poi", "label")}
    stats = {k: 0 for k in layers}

    for e in els:
        t = e.get("tags", {})
        g = e.get("geometry")
        name = t.get("name") or t.get("name:zh") or ""

        # ---------- 面积要素（闭合 way）----------
        if e["type"] == "way" and g and len(g) >= 4:
            pts = [(p["lon"], p["lat"]) for p in g]
            cen = way_centroid(g)
            if not ring_within_buffered(cen, rings, clat, CLIP_BUFFER_M):
                continue

            if "building" in t:
                simp = q(ring_closed(pts, 0.5, clat))
                if len(simp) >= 4:
                    area = ring_area_m2(pts, clat)
                    if area >= 12:  # 丢掉哨亭之类的碎块
                        layers["building"].append({
                            "k": classify_building(t),
                            "n": name,
                            "c": [round(cen[0], 6), round(cen[1], 6)],
                            "a": round(area),
                            "p": simp,
                        })
                        stats["building"] += 1
                continue

            if "natural" in t and t["natural"] in ("water", "wetland"):
                layers["water"].append({"n": name, "p": q(ring_closed(pts, 1.0, clat))})
                stats["water"] += 1
                continue

            if t.get("leisure") in SPORT_LEISURE:
                layers["sport"].append({
                    "k": t.get("leisure"),
                    "n": name,
                    "p": q(ring_closed(pts, 0.8, clat)),
                })
                stats["sport"] += 1
                continue

            lu = t.get("landuse") or t.get("natural") or t.get("leisure") or ""
            if lu in GREEN_TAGS:
                layers["green"].append({"n": name, "p": q(ring_closed(pts, 2.5, clat))})
                stats["green"] += 1
                continue

        # ---------- 线要素（道路 / 水体）----------
        if e["type"] == "way" and g and len(g) >= 2:
            pts = [(p["lon"], p["lat"]) for p in g]
            if not ring_within_buffered(way_centroid(g), rings, clat, CLIP_BUFFER_M):
                continue
            if "highway" in t:
                hw = t["highway"]
                if hw in ROAD_CLASS:
                    simp = q(dp_simplify(pts, 0.7, clat))
                    if len(simp) >= 2:
                        layers["road"].append({
                            "k": hw,
                            "w": ROAD_CLASS[hw],
                            "n": name,
                            "p": simp,
                        })
                        stats["road"] += 1
            elif t.get("waterway"):
                layers["water"].append({"n": name, "p": q(dp_simplify(pts, 1.0, clat))})
                stats["water"] += 1

    # ---------- 文字标签（供渲染端做优先级排版）----------
    # 只收「建筑名 + 校内 POI 名」，且必须在校区多边形内（不含缓冲）—— 校外的
    # 路名/邻校名进标签会把财大地图说成别人的校园。
    # pri 越大越优先上屏：3 = 图书馆/食堂/校门/体育馆这类找路锚点，
    # 2 = 普通建筑（教学楼、宿舍），1 = 其它。
    LONG_NAME = 18

    def label_pri(kind: str, nm: str) -> int:
        if kind == "building":
            if re.search(r"图书馆|食堂|校门|大门|体育馆|操场|田径|医院|礼堂|博物馆", nm):
                return 3
            if re.search(r"楼|馆|院|中心|公寓|宿舍|实验|教室", nm):
                return 2
            return 1
        if kind == "sport":
            return 3
        return 2

    seen: dict[tuple, bool] = {}
    for e in els:
        t = e.get("tags", {})
        nm = t.get("name") or t.get("name:zh") or ""
        nm = nm.strip()
        if not nm or len(nm) > LONG_NAME or nm.isdigit():
            continue
        if e["type"] == "node":
            lon, lat = e.get("lon"), e.get("lat")
        elif e.get("geometry"):
            lon, lat = way_centroid(e["geometry"])
        else:
            continue
        if lon is None or lat is None or not point_in_any((lon, lat), rings):
            continue
        kind = "building" if "building" in t else (
            "sport" if t.get("leisure") in SPORT_LEISURE else "poi")
        kk = (nm, round(lon, 5), round(lat, 5))
        if kk in seen:
            continue
        seen[kk] = True
        layers["label"].append({
            "n": nm,
            "x": round(lon, 6),
            "y": round(lat, 6),
            "k": kind,
            "pri": label_pri(kind, nm),
        })
        stats["label"] += 1
    layers["label"].sort(key=lambda l: (-l["pri"], l["n"]))

    data = {
        "id": key,
        "name": anchor[0],
        "origin": [round(clon, 6), round(clat, 6)],
        "bounds": None,  # 由下面算
        "clip": clip_source,
        "clipNames": matched_names,
        "attribution": "地图数据 © OpenStreetMap 贡献者 (ODbL)",
        **layers,
    }

    # bounds = 全部几何的经纬度包围盒（渲染端据此 fit）
    minx = miny = 1e9
    maxx = maxy = -1e9
    for layer in ("water", "green", "sport", "road", "building"):
        for it in data[layer]:
            for lon, lat in it["p"]:
                minx, maxx = min(minx, lon), max(maxx, lon)
                miny, maxy = min(miny, lat), max(maxy, lat)
    if minx > maxx:
        s, w, n, e_ = meta["bbox"]
        minx, miny, maxx, maxy = w, s, e_, n
    data["bounds"] = [round(minx, 6), round(miny, 6), round(maxx, 6), round(maxy, 6)]

    print(f"  {key} {anchor[0]}: clip={clip_source} names={matched_names} "
          + " ".join(f"{k}={v}" for k, v in stats.items()))
    return data


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", help="只处理某个 key")
    args = ap.parse_args()

    os.makedirs(OUT_DIR, exist_ok=True)
    index = []
    for key in CAMPUS_KEYS:
        if args.only and key != args.only:
            continue
        print(f"{key} ...")
        data = build_campus(key)
        if data is None:
            continue
        dst = os.path.join(OUT_DIR, f"{key}.json")
        with open(dst, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, separators=(",", ":"))
        kb = os.path.getsize(dst) // 1024
        print(f"    -> {dst} ({kb} KB)")
        index.append({
            "id": key,
            "name": data["name"],
            "asset": f"assets/campus_map/{key}.json",
            "bounds": data["bounds"],
            "counts": {k: len(data[k]) for k in
                       ("water", "green", "sport", "road", "building", "label")},
        })

    if not args.only:
        idx_path = os.path.join(OUT_DIR, "index.json")
        with open(idx_path, "w", encoding="utf-8") as f:
            json.dump({"campuses": index,
                       "attribution": "地图数据 © OpenStreetMap 贡献者 (ODbL)"},
                      f, ensure_ascii=False, indent=1)
        print(f"index -> {idx_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
