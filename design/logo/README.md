# design/logo/

Logo 的**源文件与生成脚本**。

| 文件 | 说明 |
|---|---|
| `logo.png` | 定稿源图，1440×1440（RGBA，alpha 恒 255）。整幅场景 = 天空渐变 + 主楼 + 水面倒影；原图角上的「AI生成」「千问」水印已去掉 |
| `make_icons.py` | **唯一生成脚本**（PIL + numpy，不依赖 npm/sharp）。2026-10-08 从 `logos/new/icon-from-png/` 迁来，源图路径已同步改到本目录 |

## 跑法

```powershell
# 只出预览（.scratch/icon_work/），改参数先看效果
& '<PYTHON>\python.exe' design/logo/make_icons.py

# 落盘到 android/ 、assets/ 、windows/（一次写 22 个文件，约 850 KB）
& '<PYTHON>\python.exe' design/logo/make_icons.py --write
```

写出的 22 个文件：

- `mipmap-{m,h,xh,xxh,xxxh}dpi/ic_launcher_foreground.png` = 108dp 安全构图（108/162/216/324/432px，不透明）
- `mipmap-{…}dpi/ic_launcher_background.png` = 同图放大裁切 + 高斯模糊（兜底延展，正常看不见）
- `mipmap-{…}dpi/ic_launcher.png` = 旧版方形兜底（48/72/96/144/192）
- `mipmap-{…}dpi/ic_launcher_round.png` = 同尺寸圆形预裁（给 API 25 的 `android:roundIcon`）
- `assets/images/brand/logo.png`（512² 紧构图，圆角由 UI 的 `ClipRRect` 负责）
- `windows/runner/resources/app_icon.ico`（16/24/32/48/64/128/256）

## ⚠ 脚本不写自适应 XML

`mipmap-anydpi-v26/ic_launcher{,_round}.xml` **由手维护**，引的是 `@mipmap/ic_launcher_background`
与 `@mipmap/ic_launcher_foreground`（不是 `@drawable/…`）。`design/` 里曾有另一套 Node 脚本
（`build-icons.cjs`）会把 XML 写成「引 `@drawable/` + 四角平涂色」，那份成品在真机上**会露出一圈
看得见的方框边**（画面天空是渐变、补色是平涂），已于 2026-10-08 删除，别再引入同类做法。

## 取景参数（`make_icons.py` 中段）

| 常量 | 当前值 | 含义 |
|---|---|---|
| `CHOSEN_SIZE_DP` | `79.2` | 画面高度（dp）。72dp = 自适应图标可见区下限（1:1 原图）；79.2 = v2 的 72 × 1.1 |
| `CHOSEN_DY_DP` | `+1.0` | 画面中心纵向偏移（dp）；用户的「整体上移一些」 |
| `TARGET_CIRCLE_DP` | `70.0` | 楼体收进的圆（比官方安全区 ⌀66 宽 2dp、比可见圆 ⌀72 小 2dp） |
| `LEGACY_BUILDING_FILL` | `0.66` | 旧版方形图标的取景：楼体占画幅比例（塞进圆形框也不切楼） |

改动历史（v1 求解器纯几何最优 → v2 = 72dp/dy+3 → v3 = 79.2dp/dy+1）写在脚本头部的注释里。

生成物**不放在这个目录**，直接写到各端需要的位置（见 `../README.md` 的生成链）。
