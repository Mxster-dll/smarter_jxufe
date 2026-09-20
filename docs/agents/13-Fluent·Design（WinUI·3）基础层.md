<!-- 本册 = AGENTS.md §13 的正文（节号与标题原样保留，勿重编号）。根文件：../../AGENTS.md -->

## 13. Fluent Design（WinUI 3）基础层（2026-09-11 立）

**用户诉求（原话）**：「我希望重新设计毕业学分页」（用 `/fluent-design` skill 触发）；ask_user_question 拍板五项：①**只重做这一页 + 抽一套可复用 Fluent 基础件**（否决「只此页一次性实现」与「全 app 换 ThemeData」）；②**accent = 校红 #C3282E**（否决 Fluent 官方蓝 #0078d4 与功能青 #00838F）；③**只做浅色**；④**Hero 汇总卡 + 平铺 Fluent 列表**；⑤不加 fixture / widget 测试（用户自己跑）。

### 13.1 基础件 = `lib/design/fluent/`（别再复制第二份令牌）

`fluent.dart` 是 barrel，`import 'package:smarter_jxufe/design/fluent/fluent.dart';` 一次拿全。

| 文件 | 内容 |
|---|---|
| `fluent_tokens.dart` | `FluentColors`（Fluent 2 浅色令牌 + 校红 accent 与 `accentSecondary/accentTertiary/accentDisabled/accentSubtle/accentSubtleStrong`）、`FluentSpacing`（4px 网格）、`FluentRadius`（**只有** `control=4` / `overlay=8` 与 `controlAll/overlayAll`）、`FluentType`（caption 12 / body 14 / bodyStrong 14 / bodyLarge 18 / subtitle 20 / title 28 / titleLarge 40，字重只 400 与 600，`fontFamilyFallback` 按 Segoe UI Variable → Segoe UI → 微软雅黑 → PingFang → Noto 回退）、`FluentShadows`（card/flyout/dialog）、`FluentMotion`（fast 150 / normal 200 / gentle 250 + easyEase/decelerate/accelerate 曲线） |
| `fluent_surfaces.dart` | `FluentPageBackground`（Mica 等效实色 `#F3F3F3` + 默认 880 内容宽上限）、`FluentCard`（填充 + 1px 描边 + 8 圆角，**静止态不投影**，`elevated` 才给 `FluentShadows.card`）、`FluentDivider`、`FluentSectionHeader`、`FluentInfoBar`(+`FluentInfoSeverity{informational,success,warning,error}`)、`FluentLoading`、`FluentMetricCard`（label/value/unit/description/trailing/footer） |
| `fluent_controls.dart` | `FluentListRow`（hover=controlSecondary / pressed=controlTertiary，4px 圆角，`minHeight` 默认 52）、`FluentIndexBadge`(24×24 accent 淡染)、`FluentIconButton`（默认 36×36 / icon 18）、`FluentButton`（标准 / `accent: true` 两种，dense=32 否则 36）、`FluentShareBar` + `FluentShareSegment`（accent 单色 0.9→0.35 深浅分段条） |

**硬约束（Fluent 规范，不是风格偏好 —— 改这些文件或新页面时照做）**：
1. 间距一律 4 的倍数（`FluentSpacing`），禁 5/7/10/15/20/25/30，禁用负 margin；
2. 圆角只有两档：控件与列表项 4、卡片与浮层 8；
3. 字重只用 400 / 600，**禁 `FontWeight.bold`(700)**；字号最小 12，且只用 `FluentType` 那六档；
4. 页面里**禁止裸 `Color(0x…)`** —— 一律引用 `FluentColors`（与 §3「色彩登记」同精神；业务分色仍登记在 `lib/design/feature_palette.dart`）；
5. **手势必须触摸可用**（同 §3）：`FluentListRow` / `FluentIconButton` / `FluentButton` 的 tap 都挂在 `GestureDetector` 上，`MouseRegion` 只负责 hover 增强。

**accent 与浅色**：accent 取校红 `#C3282E`（= `JxufeTheme.primaryColor`），hover `#AF2429`、pressed `#9C2025`、禁用 `rgba(195,40,46,.40)`、8% 淡染 `#14C3282E`。**深色令牌表刻意未启用**（app 无 `darkTheme`，单页深色会与 AppBar/外壳冲突）；将来接 `ThemeMode` 时补一套 `FluentColors.dark*`（规范值：底 `#202020`、卡片 `rgba(255,255,255,.05)`、文本 `rgba(255,255,255,.95)`、accent `#60cdff`），**页面侧不用改**。

### 13.2 已采用页面：毕业学分页

`lib/features/ims/graduation_requirements/presentation/graduation_requirements_screen.dart` 已整页改写（Fluent）：
- 结构 = `FluentPageBackground` → `ListView`（页面内边距：宽 ≥720 用 24，否则 16）→ **`FluentMetricCard`**（label「选修课学分合计」/ value 40/600 / unit「学分」/ description「共 N 项要求 · 最高 X 学分（项目名）」/ trailing = Fluent 刷新按钮（`refreshing` 时禁用）/ footer = `FluentShareBar` 占比条 + 「按学分占比（顺序与下表一致）」）→ **`FluentSectionHeader`「要求明细」** → **`FluentCard`**（N 个 `FluentListRow`：`FluentIndexBadge(i+1)` + 项目名 + 「占 x%」 + `_CreditValue`，行间 `FluentDivider`）→ **`_TotalRow`**（accent 8% 淡染底 + accent 字，「合计 … N 项 … 28 学分」）；
- 状态：加载 = `FluentLoading`；失败 = `FluentInfoBar(error)` + `FluentButton('重试')`；空 = `FluentInfoBar(informational)`；`_creditText()` 把 `2.00 → 「2」`、`1.25 → 「1.25」`；
- **合计口径 = 优先取教务返回的合计行，缺了才退回各项求和**（不在界面层重算教务口径）；
- 原实现拿 `theme.colorScheme.error`（红）当表头与合计强调色 —— **语义错误**，已全部换成 accent，别再改回 error 色。
- 宿主：`ImsTabContainer`（`ims_tab_container.dart:124`）以 `showAppBar: false` 挂载，页面**不要**再加重复的大标题；`showAppBar: true` 分支只用于独立打开（Fluent 化 AppBar：bgBase 底 + Subtitle 20/600 + 左对齐）。

### 13.3 ⚠️ 该页数据口径与坑（改数据侧之前先读）

- 接口：POST `/taglib/DataTable.jsp?tableId=6033`，body `sysf=&menucode_current=S20103`，Referer `…/student/pyfa.byxfyq.html?menucode=S20103&bqflag=1`；解析 `#sdTable_tbody`（`name="xm"` 项目 / `name="xf"` 学分）。
- **真实返回是 5 列**：序号 / 项目 / 学分 / **年级(`nj`)** / **专业(`zymc`)**，且 `sysf` 为空时后两列**全空**；此时返回的是**「选修学分要求」通用集**（实测账号 2000000002：7 项 = 公共外语 2 + 美育 2 + 科学·技术与方法 2 + 历史·政治与社会 2 + 哲学·思维与语言 2 + 学科开放 3 + 专业方向 15，合计 28.0）。
- **表里没有「已获学分」列** → 想做「已修 vs 要求」进度条必须另找数据源（成绩 + 培养方案推算，匹配可能不准），**不要在这个接口上猜**。
- **可能的后续改进**（尚未做，用户未拍板）：把学籍的年级 + 专业填进 `sysf` 也许能拿到含必修的完整要求 —— 属数据侧改动，动之前先抓真实响应核对。
- 该页 **没有本地缓存**（每次进页面都走网络）；要加缓存请照 §12 的 `openAccountScopedBox` 做账号隔离。
- 抓真实响应的方法：`%TEMP%\vmprobe\grad_probe.py`（连 VM Service 让 app 用**自己的** `ImsSession` 去 POST，票据不出 app，HTML 落 `%TEMP%\grad_raw.html`）—— 比从 Hive 里挖 JSESSIONID 安全。
