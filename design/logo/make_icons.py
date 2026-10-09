"""智慧er江财 · 应用图标生成器（源图 = logos/new/logo.png，2026-10-06 定稿的一枚 1440×1440 插画）

    & '<PYTHON>\\python.exe' make_icons.py            # 只出预览（.scratch/icon_work/）
    & '<PYTHON>\\python.exe' make_icons.py --write    # 落盘到 android/ 、assets/ 、windows/

为什么不是「把图缩到 79% 再拿天空色补四角」（上一版那么做，肉眼能看见一圈方框）：

1. **自适应图标（API 26+）的可见区只有画布中间的 72×72dp**，外层 18dp 全部留给系统遮罩 /
   视差；安全区是居中 ⌀66dp 的圆（Android 官方口径）。源图里楼体宽 1034px、剪影高 769px
   （屋顶 y347 ~ 台阶底 y1116），占源图 72%/53% —— 直接铺满 108dp 画布的话，圆形/圆角
   遮罩会把两翼齐刷刷切掉。所以楼体必须缩到「整个剪影都能塞进安全圆」的尺寸
   （本脚本按 ⌀70dp 解出来，比可见圆 ⌀72 小 1dp、比官方安全区 ⌀66 宽 2dp），画布剩下的
   一圈靠**画面自身延展**补，而不是拿一个平涂色去补。
2. 延展方式（不用生成模型、可复现）：左右两侧 = **镜像折叠**（天空/水面/山脊天然连续）；
   上下两端 = **沿边缘的垂直渐变做线性外推**（天空朝上继续变深、水面朝下继续变深，
   用 tanh 限幅，避免外推跑飞）。接缝处像素逐字相同，所以不存在可见的方框边。
3. 三种成品：
   - `ic_launcher_foreground.png` / 旧版 `ic_launcher.png` = 上面这张 108dp 安全构图（不透明，铺满整块画布）；
   - `ic_launcher_background.png` = 同一张图放大裁切 + 模糊（万一某家桌面把前景层缩小，露出来的
     是画面的柔化延展，而不是一圈平涂色）；
   - `assets/images/brand/logo.png` = 应用内顶栏品牌位用的**紧构图**（楼体占 80%，圆角由 UI 的
     `ClipRRect` 负责，不再在资源里烘死圆角）。
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

REPO = Path(__file__).resolve().parents[2]
SRC = Path(__file__).resolve().parent / "logo.png"   # 定稿源图，与本脚本同目录（2026-10-08 从 logos/new/ 迁来）
SCRATCH = REPO / ".scratch" / "icon_work"
ANDROID_RES = REPO / "android" / "app" / "src" / "main" / "res"
BRAND = REPO / "assets" / "images" / "brand" / "logo.png"
ICO = REPO / "windows" / "runner" / "resources" / "app_icon.ico"

# 108dp 自适应图标画布：可见区 72dp（外层各 18dp 会被遮罩裁掉），安全圆 ⌀66dp。
LAYER_DP = 108.0
VISIBLE_DP = 72.0
SAFE_DP = 66.0
# 本脚本把楼体收进 ⌀70dp 的圆（比官方安全区宽 2dp，比可见圆小 2dp）：
# 既留了 1dp 视差余量，也不会把画面压得太小。
TARGET_CIRCLE_DP = 70.0

# 出厂构图（不带参数跑脚本 = 复现仓库里落盘的那一版）：画面尺寸 dp + 中心纵向偏移 dp。
# ⚠ 改这里 = 改仓库里的图标成品，改完必须 `--write` 重跑并重出 APK。
# 画面 72dp 是「不再缩」的下限：自适应图标的可见区正好 72×72dp，画面 72dp 时
# **可见区里 1:1 就是原图**（再小就得靠外推出来的天/水去填可见区了）。
# 历史：v1 = 求解器纯几何最优（91.12dp / dy −5.57，等效把原图放大到可见区的 128%，
#        楼顶几乎贴圆上沿、下半屏全是水）；用户 2026-10-06 二改口径「缩放比大了 +
#        整体需要下移一些」→ v2 = 72dp / dy +3（原图 1:1 + 整体下移 3dp）；
#        同日三改口径「稍微放大一点，1.1 倍 + 整体上移一些（不要太多）」→ v3 = 72×1.1 = 79.2dp / dy +1。
CHOSEN_SIZE_DP = 79.2
CHOSEN_DY_DP = 1.0
AUTO_DY_HINT = "-9.74dp（94.3dp 画面）"
# 旧版方形图标（API < 26）的取景：楼体占画幅多少（66% = 塞进圆形框也不切楼）
LEGACY_BUILDING_FILL = 0.66

# 像素密度档（Android res 目录后缀 → 1dp 对应多少 px）
DENSITIES = {
    "mdpi": 1,
    "hdpi": 1.5,
    "xhdpi": 2,
    "xxhdpi": 3,
    "xxxhdpi": 4,
}
SUPERSAMPLE = 4          # 构图一律在 4×（432px）上做，再降采样落盘
EXTRAPOLATE_SPAN_FRAC = 0.0625   # 垂直外推的参考行距（占画面高度的比例，≈源图 90px）
EXTRAPOLATE_MAX = 45.0   # 单个通道外推总量的上限（tanh 限幅）


# --------------------------------------------------------------------------- #
# 1. 源图 → 楼体剪影（几何约束的依据）
# --------------------------------------------------------------------------- #
def load_source() -> np.ndarray:
    im = Image.open(SRC)
    if im.mode != "RGB":
        im = im.convert("RGB")
    a = np.asarray(im).astype(np.float32)
    print(f"源图 {SRC.name}: {im.width}x{im.height}")
    return a


def _dilate(m: np.ndarray, iters: int) -> np.ndarray:
    """方形结构元的二值膨胀（4 邻域迭代 iters 次 = 曼哈顿距离 iters 以内）。"""
    out = m
    for _ in range(iters):
        e = out.copy()
        e[1:, :] |= out[:-1, :]
        e[:-1, :] |= out[1:, :]
        e[:, 1:] |= out[:, :-1]
        e[:, :-1] |= out[:, 1:]
        out = e
    return out


def building_mask(rgb: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """楼体 = 暖色（米色墙 / 红屋顶）∪ 贴着暖色的深色（窗、底座、台阶）。

    天空/水面/远山都是冷色（B > R），所以 `R - B > 10` 能把楼体的外轮廓干净地挑出来。
    窗与底座偏深、B 略大于 R，但它们**紧贴米色墙**，所以用「暖色膨胀 24px」当范围限制 ——
    不能直接拿全图的深色（那样画面底部那片深水、远处岸线都会被算进楼体）。
    """
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    warm = (r - b) > 10
    dark = (r + g + b) < 330
    mask = warm | (dark & _dilate(warm, 24))
    ys, xs = np.nonzero(mask)
    print(f"楼体候选像素: {mask.sum()}（bbox x[{xs.min()},{xs.max()}] y[{ys.min()},{ys.max()}]）")
    return mask, warm


def protected_mask(mask: np.ndarray, warm: np.ndarray) -> np.ndarray:
    """真正要求「必须落在安全圆内」的像素集合 = 楼体本身（含踩着的底座/岸线）。

    不保护整幅风景：风景的左右被遮罩切掉是自然的，楼体被切就是坏的。远处岸线是一条
    **横贯全宽**的深色带，它一旦横贯全宽就不再算楼体（否则等于要求整条地平线都进圆里，
    楼会被迫缩得极小）——判据是「像素是否已经顶到画面左右边缘」。
    """
    h, w = mask.shape
    ys, xs = np.nonzero(mask)
    x0, x1 = xs.min(), xs.max()
    # 墙脚：最后一行「米色墙还连续成片」的位置
    wall = 0
    for y in range(h):
        if warm[y, x0:x1 + 1].sum() > 400:
            wall = y
    # 往下追底座 / 台阶：只要还没顶到画面左右边缘，就仍算楼体
    base = wall
    for y in range(wall + 1, h):
        idx = np.nonzero(mask[y])[0]
        if idx.size == 0:
            break
        if idx.min() < 100 and idx.max() > w - 100:
            break
        base = y
    prot = mask.copy()
    prot[base + 1:, :] = False
    print(f"约束集: 楼体 x[{x0},{x1}]，墙脚 y={wall}，底座/台阶到 y={base}，保护像素 {prot.sum()}")
    return prot


def boundary_points(prot: np.ndarray) -> np.ndarray:
    """约束集的边界像素（坐标 = (u, v) 归一化到 0..1）。

    最远点一定落在边界上，所以只拿边界去解几何就够；先腐蚀一圈再取差集。
    """
    e = prot.copy()
    e[1:, :] &= prot[:-1, :]
    e[:-1, :] &= prot[1:, :]
    e[:, 1:] &= prot[:, :-1]
    e[:, :-1] &= prot[:, 1:]
    bnd = prot & ~e
    ys, xs = np.nonzero(bnd)
    pts = np.stack([xs, ys], axis=1).astype(np.float64)
    h, w = prot.shape
    pts[:, 0] /= w
    pts[:, 1] /= h
    print(f"边界点 {len(pts)} 个")
    return pts


# --------------------------------------------------------------------------- #
# 2. 解构图：楼体塞进 ⌀70dp 圆内，且尽量大
# --------------------------------------------------------------------------- #
def max_radius(pts: np.ndarray, S: float, dx: float, dy: float) -> float:
    """给定构图（画面 S dp、偏移 dx/dy dp）时，楼体剪影离画布中心的最远距离。"""
    X = (pts[:, 0] - 0.5) * S + dx
    Y = (pts[:, 1] - 0.5) * S + dy
    return float(np.sqrt(X * X + Y * Y).max())


def feasible_dy(pts: np.ndarray, S: float, circle_dp: float = TARGET_CIRCLE_DP,
                dx: float = 0.0, step: float = 0.05) -> tuple[float, float, float]:
    """画面固定为 S dp 时，纵向偏移 dy 的可行区间（楼体最远点仍 ≤ circle/2）。

    `max_radius` 对 dy 是凸的 → 可行集是一个区间，直接扫出来最省事。
    返回 (dy_min, dy_max, dy_best)：dy_max = 能往下压到的极限（用户口径「整体下移」）。
    """
    R = circle_dp / 2
    dys = np.arange(-40.0, 40.001, step)
    ok = np.array([max_radius(pts, S, dx, float(d)) <= R for d in dys])
    if not ok.any():
        raise SystemExit(f"画面 {S:.2f}dp 在任何纵向位置都塞不进 ⌀{circle_dp:.0f} 圆 —— 请缩小画面")
    idx = np.nonzero(ok)[0]
    return float(dys[idx[0]]), float(dys[idx[-1]]), float(dys[ok][np.argmin([max_radius(pts, S, dx, float(d)) for d in dys[ok]])])


def solve_layout(
    pts: np.ndarray,
    circle_dp: float = TARGET_CIRCLE_DP,
    dy_fixed: float | None = None,
    size_fixed: float | None = None,
) -> tuple[float, float, float]:
    """返回 (S, dx, dy)：源图缩放成 S×S dp，画面中心相对画布中心偏移 (dx, dy) dp。

    画布中心 = (54, 54)。源图上 (u, v) 落到画布 (54 + dx + S(u-0.5), 54 + dy + S(v-0.5))。
    半径对 (S, dx, dy) 是一次齐次的，所以先在 S=90dp 上网格搜最优偏移，再按 R/r* 等比放大。
    `dy_fixed` 给定时不搜 dy（人工把楼往下压）；`size_fixed` 给定时画面尺寸直接钉死，
    此时 dy 必须在 `feasible_dy` 区间内，超界就报错（别悄悄裁到楼）。
    """
    if size_fixed is not None:
        lo, hi, best = feasible_dy(pts, size_fixed, circle_dp)
        dy = best if dy_fixed is None else dy_fixed
        if not lo - 1e-9 <= dy <= hi + 1e-9:
            raise SystemExit(
                f"画面 {size_fixed:.2f}dp 时 dy={dy:+.2f}dp 会把楼切出 ⌀{circle_dp:.0f} 圆："
                f"可行区间 {lo:+.2f} .. {hi:+.2f}dp（越正越靠下）")
        dx = 0.0
        r = max_radius(pts, size_fixed, dx, dy)
        print(f"构图解（钉死尺寸）: 画面 {size_fixed:.2f}dp（占画布 {size_fixed / LAYER_DP:.1%}），"
              f"楼体宽 {1034 / 1440 * size_fixed:.1f}dp = 画布 {1034 / 1440 * size_fixed / LAYER_DP:.1%}，"
              f"偏移 dx={dx:+.2f}dp dy={dy:+.2f}dp，最远点半径 {r:.2f}dp"
              f"（dy 可行区间 {lo:+.2f}..{hi:+.2f}）")
        return size_fixed, dx, dy

    S0 = 90.0
    u = pts[:, 0] - 0.5
    v = pts[:, 1] - 0.5

    def worst(dx: float, dy: float) -> float:
        X = S0 * u + dx
        Y = S0 * v + dy
        return float(np.sqrt(X * X + Y * Y).max())

    dys = [dy_fixed] if dy_fixed is not None else list(np.arange(-18.0, 18.01, 0.5))
    best = (1e9, 0.0, 0.0)
    for dy in dys:
        for dx in np.arange(-18.0, 18.01, 0.5):
            r = worst(dx, dy)
            if r < best[0]:
                best = (r, float(dx), float(dy))
    r, dx, dy = best
    for step in (0.2, 0.05):
        for ddx in np.arange(dx - 0.5, dx + 0.501, step):
            ddy = dy if dy_fixed is not None else None
            for cand in ([ddy] if ddy is not None else np.arange(dy - 0.5, dy + 0.501, step)):
                rr = worst(ddx, cand)
                if rr < r - 1e-9:
                    r, dx, dy = rr, float(ddx), float(cand)

    k = circle_dp / 2 / r
    S, dx, dy = S0 * k, dx * k, dy * k
    print(f"构图解: 画面 {S:.2f}dp（占画布 {S / LAYER_DP:.1%}），偏移 dx={dx:+.2f}dp dy={dy:+.2f}dp，"
          f"楼体最远点半径 {r * k:.2f}dp")
    # 最紧的几个点（源图坐标），用来判断构图是被哪儿顶住的
    X = (pts[:, 0] - 0.5) * S + dx
    Y = (pts[:, 1] - 0.5) * S + dy
    rad = np.sqrt(X * X + Y * Y)
    for i in np.argsort(rad)[-4:][::-1]:
        print(f"    顶住圆的是源图 ({pts[i, 0] * 1440:.0f}, {pts[i, 1] * 1440:.0f}) -> 半径 {rad[i]:.2f}dp")
    return S, dx, dy


# --------------------------------------------------------------------------- #
# 3. 合成：安全区镜像折叠（左右）+ 垂直渐变外推（上下）
# --------------------------------------------------------------------------- #
# 楼体在源图里占 x[204,1238]；左右两侧的「可镜像区」只取楼体之外的边带
# （各留 24px 余量 → 0.125 / 0.875），免得镜子把楼的一角搬到画布边缘去
# （画布边缘在自适应图标里被遮罩裁掉，但**旧版方形图标 / 背景层**会看得见）。
SAFE_XL_FRAC = 180 / 1440
SAFE_XR_FRAC = 1260 / 1440


def _fold(x: np.ndarray, n: float) -> np.ndarray:
    """把偏移量镜像折叠回 [0, n]（连续版，用于双线性采样前的坐标映射）。"""
    x = np.abs(x)
    p = 2.0 * n
    x = np.mod(x, p)
    return np.where(x > n, p - x, x)


def _extend_x(sx: np.ndarray, w: int) -> np.ndarray:
    """水平延展：只在楼体之外的左右边带里镜像，避免把楼角复制到画布边缘。"""
    xl = SAFE_XL_FRAC * (w - 1)
    xr = SAFE_XR_FRAC * (w - 1)
    left = _fold(-sx, xl)
    right = (w - 1) - _fold(sx - (w - 1), (w - 1) - xr)
    return np.where(sx < 0, left, np.where(sx > w - 1, right, sx))


def _bilinear(img: np.ndarray, sx: np.ndarray, sy: np.ndarray) -> np.ndarray:
    h, w, _ = img.shape
    x0 = np.clip(np.floor(sx).astype(np.int64), 0, w - 1)
    y0 = np.clip(np.floor(sy).astype(np.int64), 0, h - 1)
    x1 = np.clip(x0 + 1, 0, w - 1)
    y1 = np.clip(y0 + 1, 0, h - 1)
    fx = np.clip(sx - x0, 0.0, 1.0)[..., None]
    fy = np.clip(sy - y0, 0.0, 1.0)[..., None]
    top = img[y0, x0] * (1 - fx) + img[y0, x1] * fx
    bot = img[y1, x0] * (1 - fx) + img[y1, x1] * fx
    return top * (1 - fy) + bot * fy


def compose(src: np.ndarray, S: float, dx: float, dy: float, px_per_dp: int = SUPERSAMPLE) -> Image.Image:
    """把源图按解出来的构图铺进 108dp 画布（左右镜像、上下渐变外推）。

    ⚠ 先把源图用 LANCZOS 预缩到「1 画布像素 = 1 图像素」，再做平移/镜像采样：
    源图 1440px 要缩到 ~377px（3.8 倍降采样），直接双线性采样会**欠采样产生摩尔纹**
    （实测水面会出现竖条纹）。
    """
    size = int(round(LAYER_DP * px_per_dp))
    target_px = int(round(S * px_per_dp))
    small = Image.fromarray(np.clip(src, 0, 255).astype(np.uint8)).resize((target_px, target_px), Image.LANCZOS)
    img = np.asarray(small).astype(np.float32)
    span = EXTRAPOLATE_SPAN_FRAC * target_px          # 外推参考行距（图内像素）

    ox = LAYER_DP / 2 * px_per_dp + dx * px_per_dp - S * px_per_dp / 2
    oy = LAYER_DP / 2 * px_per_dp + dy * px_per_dp - S * px_per_dp / 2

    yy, xx = np.mgrid[0:size, 0:size].astype(np.float64)
    sx = _extend_x(xx - ox, img.shape[1])
    sy = yy - oy

    out = np.zeros((size, size, 3), dtype=np.float32)
    h, w = img.shape[:2]
    inside = (sy >= 0) & (sy <= h - 1)
    if inside.any():
        out[inside] = _bilinear(img, sx[inside], sy[inside])

    # 外推用的「趋势」取横向轻微模糊后的版本：源图水面有逐列噪点/细纹，
    # 直接按列外推会把这些噪点放大成竖条纹（实测）。基准色仍取原图那一行，保证接缝像素相同。
    smooth = np.asarray(
        Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))
        .filter(ImageFilter.GaussianBlur(max(1.0, target_px / 150)))
    ).astype(np.float32)

    # 上端外推：用 0 行与第 span 行的差继续往上推，tanh 限幅
    up = sy < 0
    if up.any():
        c0 = _bilinear(img, sx[up], np.zeros_like(sx[up]))
        b0 = _bilinear(smooth, sx[up], np.zeros_like(sx[up]))
        b1 = _bilinear(smooth, sx[up], np.full_like(sx[up], span))
        t = (-sy[up]) / span
        delta = (b0 - b1) * t[..., None]
        out[up] = c0 + EXTRAPOLATE_MAX * np.tanh(delta / EXTRAPOLATE_MAX)
    # 下端外推：同理，用末行与倒数 span 行的差
    dn = sy > h - 1
    if dn.any():
        cl = _bilinear(img, sx[dn], np.full_like(sx[dn], h - 1.0))
        bl = _bilinear(smooth, sx[dn], np.full_like(sx[dn], h - 1.0))
        bp = _bilinear(smooth, sx[dn], np.full_like(sx[dn], h - 1.0 - span))
        t = (sy[dn] - (h - 1)) / span
        delta = (bl - bp) * t[..., None]
        out[dn] = cl + EXTRAPOLATE_MAX * np.tanh(delta / EXTRAPOLATE_MAX)

    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))


def cover_blurred(icon: Image.Image, scale: float = 1.18, blur_dp: float = 3.5) -> Image.Image:
    """背景层：同一张图放大裁切 + 高斯模糊（前景层万一被桌面缩放，露出来的是柔化延展）。"""
    w, h = icon.size
    s = int(round(w * scale))
    big = icon.resize((s, s), Image.LANCZOS)
    off = (s - w) // 2
    big = big.crop((off, off, off + w, off + h))
    return big.filter(ImageFilter.GaussianBlur(blur_dp * w / LAYER_DP))


def tight_crop(src: np.ndarray, warm: np.ndarray, size: int = 512) -> Image.Image:
    """应用内品牌位：紧构图（楼体占 80% 宽、楼体中心压在 44% 高），圆角交给 UI 的 ClipRRect。"""
    ys, xs = np.nonzero(warm)
    bx0, bx1 = xs.min(), xs.max()
    # 墙脚（米色最后一行）：楼体视觉上的「落地」位置
    wall = 0
    for y in range(src.shape[0]):
        if warm[y, bx0:bx1 + 1].sum() > 400:
            wall = y
    bcx = (bx0 + bx1) / 2
    frame = (bx1 - bx0) / 0.80
    left = bcx - frame / 2
    top = (ys.min() + wall) / 2 - 0.44 * frame
    box = (int(round(left)), int(round(top)), int(round(left + frame)), int(round(top + frame)))
    print(f"品牌位裁切框 {box}（楼体 {bx1 - bx0}×{wall - ys.min()}px，占框宽 "
          f"{(bx1 - bx0) / frame:.1%}）")
    im = Image.fromarray(np.clip(src, 0, 255).astype(np.uint8)).crop(box)
    return im.resize((size, size), Image.LANCZOS)


def legacy_crop(src: np.ndarray, warm: np.ndarray, size: int = 192,
                fill: float = LEGACY_BUILDING_FILL) -> Image.Image:
    """旧版方形图标（API < 26 的 `mipmap-*/ic_launcher.png`）：**另一种取景**。

    自适应图标那套「缩到安全圆 + 四周补边」是给遮罩用的；旧版图标在 API 24/25 上是
    **不遮罩**直接显示（或由 ROM 套一个自己的框），照搬那套会得到「楼很小、四周一片补出来的天/水」。
    这里改成自然取景：楼体占画幅 `fill`（默认 66%），天空/水面留白按原图比例。
    66% 是按「万一被塞进圆形框也不切楼」定的：楼体 66% 宽 × 49% 高 → 半对角线 41% < 50%。
    """
    ys, xs = np.nonzero(warm)
    bx0, bx1 = xs.min(), xs.max()
    wall = 0
    for y in range(src.shape[0]):
        if warm[y, bx0:bx1 + 1].sum() > 400:
            wall = y
    bcx = (bx0 + bx1) / 2
    frame = (bx1 - bx0) / fill
    left = bcx - frame / 2
    top = (ys.min() + wall) / 2 - 0.46 * frame
    box = (max(0, int(round(left))), max(0, int(round(top))))
    box = (box[0], box[1], min(src.shape[1], box[0] + int(round(frame))),
           min(src.shape[0], box[1] + int(round(frame))))
    print(f"旧版方形取景框 {box}（楼体占框宽 {(bx1 - bx0) / (box[2] - box[0]):.1%}）")
    im = Image.fromarray(np.clip(src, 0, 255).astype(np.uint8)).crop(box)
    return im.resize((size, size), Image.LANCZOS)


# --------------------------------------------------------------------------- #
# 4. 遮罩预览（肉眼验收：各种桌面形状下会不会切到楼）
# --------------------------------------------------------------------------- #
def _mask_circle(size: int, dp: float) -> Image.Image:
    ss = size * 4
    m = Image.new("L", (ss, ss), 0)
    d = ImageDraw.Draw(m)
    c = ss / 2
    r = dp / LAYER_DP * ss / 2
    d.ellipse([c - r, c - r, c + r, c + r], fill=255)
    return m.resize((size, size), Image.LANCZOS)


def _mask_round_rect(size: int, dp: float, radius_ratio: float) -> Image.Image:
    ss = size * 4
    m = Image.new("L", (ss, ss), 0)
    d = ImageDraw.Draw(m)
    c = ss / 2
    half = dp / LAYER_DP * ss / 2
    rad = half * radius_ratio
    d.rounded_rectangle([c - half, c - half, c + half, c + half], radius=rad, fill=255)
    return m.resize((size, size), Image.LANCZOS)


def _mask_squircle(size: int, dp: float, n: float = 4.0) -> Image.Image:
    """超椭圆 |x|^n + |y|^n = r^n（各家「方圆」遮罩的近似）。"""
    ss = size * 4
    m = Image.new("L", (ss, ss), 0)
    px = m.load()
    c = ss / 2
    r = dp / LAYER_DP * ss / 2
    for y in range(ss):
        ny = abs((y + 0.5 - c) / r)
        if ny > 1:
            continue
        span = (1 - ny ** n) ** (1.0 / n) * r
        for x in range(int(c - span), int(c + span) + 1):
            px[x, y] = 255
    return m.resize((size, size), Image.LANCZOS)


def _mask_teardrop(size: int, dp: float) -> Image.Image:
    """水滴形（一个下角是尖的）：⌀72 的圆 ∪ 右下角的方块，是 Android 官方四种形状之一。"""
    ss = size * 4
    m = Image.new("L", (ss, ss), 0)
    d = ImageDraw.Draw(m)
    c = ss / 2
    r = dp / LAYER_DP * ss / 2
    d.ellipse([c - r, c - r, c + r, c + r], fill=255)
    d.rectangle([c, c, c + r, c + r], fill=255)  # 右下角补成方角 = 水滴形
    return m.resize((size, size), Image.LANCZOS)


def render_previews(icon: Image.Image, legacy: Image.Image) -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    icon.save(SCRATCH / "composite_full.png")
    legacy.save(SCRATCH / "legacy_full.png")
    preview_px = 192
    base = icon.resize((preview_px, preview_px), Image.LANCZOS)
    bg = Image.new("RGB", (preview_px, preview_px), (240, 240, 242))
    shapes = {
        "circle": _mask_circle(preview_px, VISIBLE_DP),
        "squircle": _mask_squircle(preview_px, VISIBLE_DP),
        "roundrect20": _mask_round_rect(preview_px, VISIBLE_DP, 0.20),
        "roundrect33": _mask_round_rect(preview_px, VISIBLE_DP, 0.33),
        "teardrop": _mask_teardrop(preview_px, VISIBLE_DP),
    }
    tiles = [("原始 108dp", base)]
    for name, m in shapes.items():
        tile = bg.copy()
        tile.paste(base, (0, 0), m)
        tiles.append((name, tile))
    # 旧版方形图标（API<26 用）：原样方形 + 套圆形框两档，确认楼不会被圆框切
    lg = legacy.resize((preview_px, preview_px), Image.LANCZOS)
    tiles.append(("legacy 48px", lg))
    lg_round = bg.copy()
    lg_round.paste(lg, (0, 0), _mask_circle(preview_px, LAYER_DP))
    tiles.append(("legacy+circle", lg_round))

    sheet = Image.new("RGB", (preview_px * len(tiles), preview_px + 18), (255, 255, 255))
    d = ImageDraw.Draw(sheet)
    for i, (name, tile) in enumerate(tiles):
        sheet.paste(tile, (i * preview_px, 18))
        d.text((i * preview_px + 6, 4), name, fill=(0, 0, 0))
    sheet.save(SCRATCH / "preview_shapes.png")

    # 桌面上的真实尺寸（圆形遮罩 + 浅灰底），放大 2 倍看可读性
    sizes = [192, 144, 96, 72, 48]
    zoom = 2
    cell = max(sizes) * zoom + 16
    row = Image.new("RGB", (cell * len(sizes), cell), (255, 255, 255))
    rd = ImageDraw.Draw(row)
    for i, s in enumerate(sizes):
        small = icon.resize((s, s), Image.LANCZOS)
        m = _mask_circle(s, VISIBLE_DP)
        tile = Image.new("RGB", (s, s), (238, 238, 240))
        tile.paste(small, (0, 0), m)
        tile = tile.resize((s * zoom, s * zoom), Image.NEAREST)
        x = i * cell + (cell - tile.width) // 2
        y = (cell - tile.height) // 2
        row.paste(tile, (x, y))
        rd.text((i * cell + 6, 4), f"{s}px", fill=(0, 0, 0))
    row.save(SCRATCH / "preview_sizes.png")

    # 安全区标尺：外层 18dp 压暗、画出可见区 72dp 方框与安全圆
    guide = icon.copy().convert("RGB")
    ov = Image.new("L", guide.size, 0)
    od = ImageDraw.Draw(ov)
    margin = (LAYER_DP - VISIBLE_DP) / 2 / LAYER_DP * guide.width
    od.rectangle([0, 0, guide.width, guide.height], fill=90)
    od.rectangle([margin, margin, guide.width - margin, guide.height - margin], fill=0)
    guide = Image.composite(Image.new("RGB", guide.size, (0, 0, 0)), guide, ov)
    gd = ImageDraw.Draw(guide)
    m = margin
    gd.rectangle([m, m, guide.width - m, guide.height - m], outline=(255, 255, 255), width=2)
    c = guide.width / 2
    r = SAFE_DP / LAYER_DP * guide.width / 2
    gd.ellipse([c - r, c - r, c + r, c + r], outline=(255, 80, 80), width=3)
    r2 = TARGET_CIRCLE_DP / LAYER_DP * guide.width / 2
    gd.ellipse([c - r2, c - r2, c + r2, c + r2], outline=(80, 255, 120), width=2)
    guide.resize((384, 384), Image.LANCZOS).save(SCRATCH / "preview_guide.png")
    print(f"预览: {SCRATCH / 'preview_shapes.png'} / {SCRATCH / 'preview_guide.png'} / "
          f"{SCRATCH / 'preview_sizes.png'}")


# --------------------------------------------------------------------------- #
# 5. 落盘
# --------------------------------------------------------------------------- #
def write_outputs(icon: Image.Image, background: Image.Image, brand: Image.Image,
                  legacy_source: Image.Image) -> None:
    written = []

    def save(im: Image.Image, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        im.save(path, "PNG", optimize=True)
        written.append((path, path.stat().st_size))

    for bucket, dpi in DENSITIES.items():
        res = ANDROID_RES / f"mipmap-{bucket}"
        layer_px = int(round(LAYER_DP * dpi))
        legacy_px = int(round(48 * dpi))
        save(icon.resize((layer_px, layer_px), Image.LANCZOS), res / "ic_launcher_foreground.png")
        save(background.resize((layer_px, layer_px), Image.LANCZOS), res / "ic_launcher_background.png")
        # 旧版方形图标 = 另一套取景（自然构图，楼占 66%），不是自适应那层缩下去
        legacy = legacy_source.resize((legacy_px, legacy_px), Image.LANCZOS)
        save(legacy, res / "ic_launcher.png")
        # API 25 的 roundIcon：同心正圆裁切（楼体半对角线 41% < 50%，裁不到它）
        round_mask = _mask_circle(legacy_px, LAYER_DP).resize((legacy_px, legacy_px), Image.LANCZOS)
        rnd = Image.new("RGBA", (legacy_px, legacy_px), (0, 0, 0, 0))
        rnd.paste(legacy, (0, 0), round_mask)
        save(rnd, res / "ic_launcher_round.png")

    save(brand, BRAND)

    ico_sizes = [16, 24, 32, 48, 64, 128, 256]
    frames = [brand.resize((s, s), Image.LANCZOS) for s in ico_sizes]
    ICO.parent.mkdir(parents=True, exist_ok=True)
    frames[-1].save(ICO, format="ICO", sizes=[(s, s) for s in ico_sizes])
    written.append((ICO, ICO.stat().st_size))

    total = sum(sz for _, sz in written)
    for p, sz in written:
        print(f"  {sz / 1024:8.1f} KB  {p.relative_to(REPO)}")
    print(f"合计 {total / 1024:.0f} KB / {len(written)} 个文件")


def main() -> None:
    # 控制台是 GBK，打印 ⌀ / × 这类字符会炸；统一按 UTF-8 输出
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:  # noqa: BLE001 - 老 Python 或非 tty 时忽略
        pass
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true", help="落盘到 android/ assets/ windows/")
    ap.add_argument("--dy", type=float, default=None,
                    help=f"画面中心纵向偏移（dp，负数=楼往上抬，正数=往下压）；"
                         f"不给则自动求最优（纯几何最优 {AUTO_DY_HINT}）")
    ap.add_argument("--size", type=float, default=None,
                    help="钉死画面尺寸（dp）。给了它就必须给一个落在可行区间内的 --dy，"
                         "越小的画面越能往下压（用户口径「缩比小一点、整体下移」）")
    ap.add_argument("--circle", type=float, default=TARGET_CIRCLE_DP,
                    help="要求楼体剪影塞进多大的圆（dp），默认 70")
    args = ap.parse_args()

    src = load_source()
    mask, warm = building_mask(src)
    prot = protected_mask(mask, warm)
    pts = boundary_points(prot)
    if args.size is not None:
        S, dx, dy = solve_layout(pts, args.circle, args.dy, args.size)
    elif args.dy is not None:
        S, dx, dy = solve_layout(pts, args.circle, args.dy)
    else:
        S, dx, dy = solve_layout(pts, args.circle, CHOSEN_DY_DP, CHOSEN_SIZE_DP)

    icon = compose(src, S, dx, dy)
    background = cover_blurred(icon)
    brand = tight_crop(src, warm)
    legacy = legacy_crop(src, warm)
    render_previews(icon, legacy)

    X = (pts[:, 0] - 0.5) * S + dx
    Y = (pts[:, 1] - 0.5) * S + dy
    print(f"复核: 楼体最远半径 {np.sqrt(X ** 2 + Y ** 2).max():.2f}dp "
          f"（可见圆 d{VISIBLE_DP:.0f} -> 半径 {VISIBLE_DP / 2:.1f}；官方安全圆半径 {SAFE_DP / 2:.1f}）")

    if args.write:
        write_outputs(icon, background, brand, legacy)
    else:
        print("（未加 --write，只出预览）")


if __name__ == "__main__":
    main()
