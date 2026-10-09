# design/ — 设计源文件

**这个目录进版本控制（git 跟踪），删了能 `git checkout` 回来。** 此前图标稿放在 `logos/`（被 `.gitignore` 排除），误删后无法恢复；2026-10-08 起设计稿统一放这里，`logos/` 已删除。

## 各子目录放什么

| 目录 | 放什么 | 当前内容 |
|---|---|---|
| `design/logo/` | 品牌标 / Logo 的源图与生成脚本 | `logo.png`（定稿源图 1440²）、`make_icons.py`（**唯一生成脚本**） |
| `design/icons/` | 应用图标的设计稿与候选（各比例、各底色的原始导出） | 说明见其 README |
| `design/ui/` | 界面稿、原型截图、标注图 | 说明见其 README |

## 和另外两个目录的分工（别放混）

| 目录 | git | 进不进 APK | 用途 |
|---|---|---|---|
| **`design/`** | ✅ 跟踪 | ❌ 不进 | 设计源文件（大图、多版本、生成脚本）——**你的稿子放这里** |
| `assets/` | ✅ 跟踪 | ✅ **按 `pubspec.yaml` 的 `assets:` 声明打进 APK** | App 运行时真正要读的文件（如 `assets/images/brand/logo.png` 顶栏品牌图） |
| `.scratch/` | ❌ 忽略 | ❌ | 临时产物、预览图，随时可删 |

**规则**：一份稿子若最终要被 App 读取，先在 `design/` 里迭代定稿，再由生成脚本输出到 `assets/` 并在 `pubspec.yaml` 声明；`design/` 保留源文件与脚本。

## 迁移台账（2026-10-08）

| 动作 | 说明 |
|---|---|
| 新建 `design/` | 仓库根的 `design/`（设计源文件）与 `lib/design/`（Dart 设计口径代码）职责不同，互不冲突 |
| `logos/new/logo.png` → `design/logo/logo.png` | 定稿源图；`logos/` 目录已删除，`.gitignore` 里的 `/logos/` 规则一并移除 |
| `logos/new/icon-from-png/make_icons.py` → `design/logo/make_icons.py` | 脚本里 `REPO = parents[3]` 改 `parents[2]`、`SRC` 改为与本脚本同目录的 `logo.png` |
| 删除 `design/logo/build-icons.cjs` | 那套「画面缩到 79% + 四角平涂天空色」的成品在真机上会露出一圈**看得见的方框边**，已被 `make_icons.py` 的「安全构图 + 画面自身延展」取代 |
| `mipmap-anydpi-v26/ic_launcher{,_round}.xml` | ⚠ 此前被写成引 `@drawable/…`（那套已删的 drawable），**已改回引 `@mipmap/ic_launcher_background` / `@mipmap/ic_launcher_foreground`**；`make_icons.py` 不写这两个 XML，**由手维护** |

## 图标生成链（唯一链路，2026-10-08 收敛）

```
design/logo/logo.png                       定稿源图（1440²，已去水印）
        │
        └─ python design/logo/make_icons.py --write     ← 改参数见 design/logo/README.md
                ↓  22 个文件
   android/app/src/main/res/mipmap-*/ic_launcher_foreground.png   108dp 安全构图（自适应前景）
   android/app/src/main/res/mipmap-*/ic_launcher_background.png   同图放大+模糊（兜底延展）
   android/app/src/main/res/mipmap-*/ic_launcher.png              旧版方形兜底 48…192
   android/app/src/main/res/mipmap-*/ic_launcher_round.png        圆形预裁（API 25）
   assets/images/brand/logo.png                                   512² 紧构图（App 顶栏品牌位）
   windows/runner/resources/app_icon.ico                          16/24/32/48/64/128/256
   （mipmap-anydpi-v26/ic_launcher{,_round}.xml 由手维护，脚本不写）
```

改图标 = 改 `make_icons.py` 顶部参数 → `--write` → `flutter build apk --release`。

**⚠ 不要用「把画面缩到 79% 再拿天空色补四角」那类做法**（`design/` 里曾有一版 Node 脚本这么干，已删）：
自适应图标的可见区只有画布中间的 72×72dp，四角补色的成品在真机上会露出一圈**看得见的方框边**
（画面的天空是渐变，补色是平涂，交界处对不上）。正确做法是 `make_icons.py` 的「安全构图 + 画面自身延展」。

口径与历史决策记在 `docs/agents/17-主页布局·宫格排版·应用名.md` 的 §17.6.2。
