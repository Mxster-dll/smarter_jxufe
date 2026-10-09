<!-- 本册 = AGENTS.md §13 的正文（节号与标题原样保留，勿重编号）。根文件：../../AGENTS.md -->

## 13. Fluent Design（WinUI 3）基础层（2026-09-11 立）

**用户诉求（原话）**：「我希望重新设计毕业学分页」（用 `/fluent-design` skill 触发）；ask_user_question 拍板五项：①**只重做这一页 + 抽一套可复用 Fluent 基础件**（否决「只此页一次性实现」与「全 app 换 ThemeData」）；②**accent = 校红 #C3282E**（否决 Fluent 官方蓝 #0078d4 与功能青 #00838F）；③**只做浅色**；④**Hero 汇总卡 + 平铺 Fluent 列表**；⑤不加 fixture / widget 测试（用户自己跑）。

### 13.1 基础件 = `lib/design/fluent/`（别再复制第二份令牌）

`fluent.dart` 是 barrel，`import 'package:smarter_jxufe/design/fluent/fluent.dart';` 一次拿全。

| 文件 | 内容 |
|---|---|
| `fluent_tokens.dart` | `FluentColors`（Fluent 2 浅色令牌 + 校红 accent 与 `accentSecondary/accentTertiary/accentDisabled/accentSubtle/accentSubtleStrong`）、`FluentSpacing`（4px 网格）、`FluentRadius`（**只有** `control=4` / `overlay=8` 与 `controlAll/overlayAll`）、`FluentType`（caption 12 / body 14 / bodyStrong 14 / bodyLarge 18 / subtitle 20 / title 28 / titleLarge 40，字重只 400 与 600，`fontFamilyFallback` 按 Segoe UI Variable → Segoe UI → 微软雅黑 → PingFang → Noto 回退）、`FluentShadows`（card/flyout/dialog）、`FluentMotion`（fast 150 / normal 200 / gentle 250 + easyEase/decelerate/accelerate 曲线） |
| `fluent_surfaces.dart` | `FluentPageBackground`（Mica 等效实色 `#F3F3F3` + 默认 880 内容宽上限）、`FluentCard`（填充 + 1px 描边 + 8 圆角，**静止态不投影**，`elevated` 才给 `FluentShadows.card`）、`FluentDivider`、`FluentSectionHeader`、`FluentInfoBar`(+`FluentInfoSeverity{informational,success,warning,error}`)、`FluentLoading`、`FluentMetricCard`（label/value/unit/description/trailing/footer） |
| `fluent_controls.dart` | `FluentListRow`（hover=controlSecondary / pressed=controlTertiary，4px 圆角，`minHeight` 默认 52）、`FluentIndexBadge`(24×24 accent 淡染)、`FluentIconButton`（默认 36×36 / icon 18）、`FluentButton`（标准 / `accent: true` 两种，dense=32 否则 36）、`FluentShareBar` + `FluentShareSegment`（accent 单色 0.9→0.35 深浅分段条）、**`FluentProgressBar`**（2026-10-08 加：单一比率 0~1 的圆角进度条，`tone` 可传 `p.success` 表示「已满足」；越界自动夹取、NaN 当 0，带 `Semantics` 百分比） |

**硬约束（Fluent 规范，不是风格偏好 —— 改这些文件或新页面时照做）**：
1. 间距一律 4 的倍数（`FluentSpacing`），禁 5/7/10/15/20/25/30，禁用负 margin；
2. 圆角只有两档：控件与列表项 4、卡片与浮层 8；
3. 字重只用 400 / 600，**禁 `FontWeight.bold`(700)**；字号最小 12，且只用 `FluentType` 那六档；
4. 页面里**禁止裸 `Color(0x…)`** —— 一律引用 `FluentColors`（与 §3「色彩登记」同精神；业务分色仍登记在 `lib/design/feature_palette.dart`）；
5. **手势必须触摸可用**（同 §3）：`FluentListRow` / `FluentIconButton` / `FluentButton` 的 tap 都挂在 `GestureDetector` 上，`MouseRegion` 只负责 hover 增强。

**accent 与浅色**：accent 取校红 `#C3282E`（= `JxufeTheme.primaryColor`），hover `#AF2429`、pressed `#9C2025`、禁用 `rgba(195,40,46,.40)`、8% 淡染 `#14C3282E`。**深色令牌表刻意未启用**（app 无 `darkTheme`，单页深色会与 AppBar/外壳冲突）；将来接 `ThemeMode` 时补一套 `FluentColors.dark*`（规范值：底 `#202020`、卡片 `rgba(255,255,255,.05)`、文本 `rgba(255,255,255,.95)`、accent `#60cdff`），**页面侧不用改**。

### 13.2 已采用页面：毕业学分页

`lib/features/ims/graduation_requirements/presentation/graduation_requirements_screen.dart` 已整页改写（Fluent）。

**2026-10-08 起（用户原话：「我希望你更新『毕业学分』功能」+「必修课肯定要全部修完。毕业学分要求功能内部应该分为『必修课进度』以及『选修课进度』」）**，结构 = `FluentPageBackground` → `ListView`（页面内边距：宽 ≥720 用 24，否则 16）→
1. **`CreditOverviewCards`**：两张 `FluentMetricCard` 并排（窄屏竖排）——「必修课」（已修 X 学分 / 要求 Y · N/M 门已修 / `FluentProgressBar` + 「还差 Z 学分」，刷新按钮挂在第一张的 `trailing`）与「选修课」（已修 X / 要求 28 · N 项 · M 项已满足 / 进度条 + 还差）；
2. **`FluentSectionHeader`「必修课进度」**（description = 培养方案标识）→ `CompulsoryProgressCard`：`已修 / 要求` + 进度条 + 「培养方案共 N 门必修课，已修 M 门」+ `FluentButton('查看还差 N 门')` 展开待修课清单（课名 + 二级分类 + 学分）；
3. **`FluentSectionHeader`「选修课进度」**（description = 教务表「N 项 · 合计 28 学分」）→ 每项一行 `ElectiveProgressRow`：`FluentIndexBadge` + 项目名 + **判定口径**（「通识课程库『美育』模块」/「培养方案『专业方向课』（选修）」+ 可选池门数与学分）+ 行尾 `已修 / 要求` 与 `已满足 / 还差 X` + 进度条 + 「计入：课名 学分 · …」；
4. **「未归类课程（N 门）」**（仅当非空）→ `UnmatchedCoursesCard`：课名 + **为什么没算进去** + 学分；
5. 尾部 `CreditProgressNotes`：逐条口径备注（含「学校没下发该年级通识库表」这类降级说明）+ 已修学分合计 + 四路数据来源。

- 状态：加载 = `FluentLoading`；整页失败 = `FluentInfoBar(error)` + `FluentButton('重试')`（`_ErrorView`）；**教务要求表单独失败** = 只有「选修课进度」这一节画 error InfoBar，必修进度与未归类照常显示（`_ElectiveSection`）；要求表空 = `FluentInfoBar(informational)`；`creditText()`（原 `_creditText`，已提到 `presentation/widgets/credit_progress_widgets.dart`）把 `2.00 → 「2」`、`1.25 → 「1.25」`；
- 原实现拿 `theme.colorScheme.error`（红）当表头与合计强调色 —— **语义错误**，已全部换成 accent，别再改回 error 色。新加的进度条同理：未满足用 accent、已满足用 `p.success`，**不要**用 error 红表示「还差」（那是进度不是故障）。
- 宿主：`ImsTabContainer`（`ims_tab_container.dart:146`）以 `showAppBar: false` 挂载，页面**不要**再加重复的大标题；`showAppBar: true` 分支只用于独立打开（Fluent 化 AppBar：bgBase 底 + Subtitle 20/600 + 左对齐）。
- **刷新两条路**：手动刷新 = `_refreshNow()` 同时 `ref.invalidate(graduationRequirementsProvider)`（要求表**没有本地缓存**，每次都得走网络）与 `graduationCreditReportProvider`；自动刷新 = `PageAutoRefresher`（本页是 IMS 容器里的 tab 正文而非独立路由，`subscribeRoute` 订到容器那个路由，从子页面返回 / 回前台照常生效），走 `invalidateIfLoaded` 以免把首帧那两个请求重发一遍。
- ⚠ **关于「⑤ 不加 fixture / widget 测试」这条 2026-09-11 的范围决定**：2026-10-08 补了 `test/graduation_credit_page_layout_test.dart`（**6 例纯渲染冒烟**）—— 页面这轮从「一张只读表」变成「指标卡 + 可展开清单 + 逐项进度条」，而这条冒烟**当场抓出两个真溢出**（`CompulsoryProgressCard` 的两处 `Row` + `Spacer`：360 宽溢出 50px、280 宽溢出 130px，已改 `Wrap` + `Text.rich`）。它只断言「画得出来 / 不溢出 / 降级文案对」，**不碰像素与配色**（那是 golden 的事），数据全合成。若用户不要它，删该文件即可，源码侧无耦合。

### 13.3 ⚠️ 该页数据口径与坑（改数据侧之前先读）

- 接口：POST `/taglib/DataTable.jsp?tableId=6033`，body `sysf=&menucode_current=S20103`，Referer `…/student/pyfa.byxfyq.html?menucode=S20103&bqflag=1`；解析 `#sdTable_tbody`（`name="xm"` 项目 / `name="xf"` 学分）。
- **真实返回是 5 列**：序号 / 项目 / 学分 / **年级(`nj`)** / **专业(`zymc`)**，且 `sysf` 为空时后两列**全空**；此时返回的是**「选修学分要求」通用集**（2026-09-12 抓包实测，逐字：`2024公共外语选修课 2.00` / `2024美育选修2学分 2.00` / `2024科学、技术与方法选修2学分 2.00` / `2024历史、政治与社会选修2学分 2.00` / `2024哲学、思维与语言选修2学分 2.00` / `2024学科开放选修课 3.00` / `2024专业方向选修课 15.00` / `合计 28.0`）。**这 7 条是要求项匹配的基准台账**（守卫 `test/general_education_catalog_test.dart` 逐条钉着），项目名的写法**不要**按「好看」去改。
- **表里没有「已获学分」列** → 「已修 vs 要求」必须另找数据源。**2026-10-08 已做**，口径见下面 §13.4，**不要在这个接口上猜**。
- **数据侧试过了、没成**（2026-10-08）：把学籍的年级 / 专业填进请求（`nj` + `zymc`、`sysf=2025`、`sysf=<专业名>`、`nj_` + `sel_zy` 四种写法都试了）**返回一字不差还是那 7 条**；而且表单里 `sysf` 只是个 value 为空的 hidden input（`pyfa.byxfyq.html` 全文只有一个 `sysf`），页面里那段被注释掉的旧实现走的是另一个接口（`STU_DynamicInitDataAction.do?classPath=credithour`，返回 `ggbxxf/sj hjxf/zxf/zyxxxf/zybxxf/kxf/ggrxxf/zyrxxf` 这类**必修学分汇总**）。**想要「含必修的官方要求表」得去啃那个接口 —— 本轮没做**（本轮必修进度的分母取自培养方案，见 §13.4）。
- ⚠ 抓这个接口要**活的教务会话**：`imsauth.hive` 里存的 JSESSIONID 一个月就失效，POST 会被打回「凭证已失效，请重新登录!」（GET 那个 html 静态页却照样 200 —— 别被 GET 骗了）。

### 13.4 「已修 vs 要求」的推算口径（2026-10-08 立 · 改动前先读）

用户诉求（原话）：「这是我校的 2026 通识课程库，然后学科开放课、专业方向课、公共外语课，这些都是可以在培养方案中查到的。那么根据我已修的课程（从成绩页得到），就可以得知我距离『毕业学分』还差多少」+ 追问拍板：「必修课肯定要全部修完。毕业学分要求功能内部应该分为『必修课进度』以及『选修课进度』」。

**唯一算法 = `lib/features/ims/graduation_requirements/domain/credit_progress.dart` 的 `buildGraduationCreditProgress(...)`**（页面与 AI 工具都只吃它的结果，界面里**一率不重算**）：

| 段 | 分母（要求） | 分子（已修） |
|---|---|---|
| **必修课进度** | 本专业培养方案里 `Course.requirement == compulsory` 的**全部**课程学分之和 | 成绩里按课程代码（缺码退课程名）匹配上的那些课的 `获得学分` |
| **选修课进度** | 教务 7 项各自的 `学分` | 见下的逐项判定 |

选修 7 项的判定（`resolveElectiveRule`，要求项名先过 `canonicalCategoryKey` 归一）：

| 要求项 | 找课的地方 | 判据 |
|---|---|---|
| `2024公共外语选修课` | 培养方案 | `subCategory == '公共外语课'` **且** `requirement == elective` |
| `2024学科开放选修课` | 培养方案 | `subCategory == '学科开放课'` |
| `2024专业方向选修课` | 培养方案 | `subCategory == '专业方向课'` |
| `2024美育选修2学分` 等 4 项 | **通识课程库**（`assets/general_education/ge_catalog.json`） | 库里该课的 `module` 是同一模块 |

**四条硬口径（改之前先想清楚，测试钉着）**：
1. **只认「获得学分」**（`Grade.earnedCredit`）：不及格记 0；同码多条取获得学分最高的那条、再按学期取新（重修不许把两次学分相加）。
2. **培养方案里的必修课不再计入任何选修项**。典型陷阱 = `写作与沟通 I` 在培养方案里属「2024通识教育课 / 哲学、思维与语言」但性质是**必修** —— 它顶的是必修进度，**不是**那 2 学分通识选修。（守则：分类时先判 `requirement == compulsory` 直接归必修。）
3. **各项溢出互不抵扣**：教务把每一项列成独立要求，专业方向多修 5 学分顶不了美育的 2 学分。合计「还差」= 各项 `max(0, 要求 − 已修)` 之和；而「已修」显示的是**真实值不截顶**（`CreditProgressItem.earned`），截顶值另给 `counted`，超了会明写「已超出 X 学分（不抵扣其它项）」。
4. **认不出就不猜**：要求项名归一后对不上任何规则的 → `recognized: false`，只显示要求学分；课程归不到任何**被要求的**类别的 → 进「未归类」并写明理由（`UnmatchedCourse.reason`，共 5 种：两边都没有 / 培养方案外类别 / 通识库模块不在要求项里 / 通识库该行没模块标签 / 培养方案二级分类为空）。

**数据来源四路（各自的失败面互不牵连）**：
- 教务要求表 = `graduationRequirementsProvider`（**在线**，需教务会话）；挂了只影响「选修课进度」这一节。
- 培养方案 = `myCurriculumProvider`（`features/ims/curriculum/data/providers/my_curriculum_provider.dart`，学籍 → 学院 → 专业 → 培养方案；**命中本地缓存不发网络**）。拿不到 → 必修 unavailable（显示「无法统计」而**不是** 0）+ 三类专业选修算不出，但四个通识模块照算。
- 通识课程库 = `generalEducationCatalogProvider`（**纯本地 asset**）。源 = 学校下发的《2026年通识课程库（含外校网课）》xlsx，生成脚本 `tool/make_ge_catalog.py`（**源 xlsx 不入库**，重跑脚本即可换版），守卫 `test/general_education_catalog_test.dart`（真实 asset 台账 42 例）。
- 成绩 = `graduationTakenCoursesProvider`：**一档**走成绩页同款查询（`时间限制=全部`，`GradesRepository` 缓存优先 → 命中缓存零网络、缺缓存自己补拉），**二档**退回直接读成绩缓存 box（离线）。⚠ **刻意不套用成绩页的 GPA 课程排除名单**（军事训练 / 毕业设计…）—— 那是算加权的口径，毕业学分要的是「到底拿了多少学分」。

**通识课程库的三张 sheet 与适用年级**：`适用于2021-2023级` / `适用于2024-2025级` / `外校网课清单（适用于各年级）`。按学籍入学年选表（年级表 + 各年级表）；**一个区间都没命中时退到 `cohortTo` 最大的那张**，并把 `GeneralEducationScope.exactCohortMatch` 置 false，页面照实写「通识课程库没有适用 XXXX 级的表，已退到…」。⚠ 判命中**只能拿年级区间表**判 —— 「适用各年级」那张对任何 cohort 都 `covers`，混进来会让「没有本年级的表」永远判成命中（2026 级实测踩过，测试钉着）。

**源表的两个真实缺口（别当成 bug 去「修」）**：
- 2021-2023 那张表**开头 89 门课没有模块标签**（`A3:A91` 是个空值的合并区）→ 产物里 `module` 记 null，成绩里命中这些课时进「未归类」并写「该行没有模块标签」。
- 该表尾部两行（`学科前沿课` / `竞赛指导课`）**没有课程编码**、学分是区间（`0.5-1` / `1-1.5`）→ `credit: null` + `creditText` 存原文，靠课程名兜底匹配。

**归一化的坑（2026-10-08 实测回归）**：`canonicalCategoryKey` 剥噪音时**不许把「课 / 必修 / 限选 / 任选」也剥掉** —— 早先版本这么干，`专业必修课 → 专业必修 → 专业`、`专业限选课 → 专业限选 → 专业`、`专业方向课 → 专业方向` 三个类别会塌成「专业」一类。真正需要抹平的只有**要求项名里的「选修 / 学分」**（教务写「公共外语选修课」，培养方案写「公共外语课」）。守卫 = `test/general_education_catalog_test.dart` 的「三个类别必须是三个键」。

**预期数值样例**（2025 级计算机科学与技术，2026-10-08 实测）：必修 50 门 / 113 学分，读完 252 学期已修 25 门 / 56 学分 → 还差 57 学分；选修 7 项 / 28 学分全为 0（该生还没修选修）；未归类 = `大学生安全教育`（1 学分，两边都没有）+ `军事训练`（2 学分，不在培养方案）；已修合计 59 学分（与成绩页一致）。

- 该页 **没有本地缓存**（要求表每次进页面都走网络）；要加缓存请照 §12 的 `openAccountScopedBox` 做账号隔离。
- 抓真实响应的方法：`%TEMP%\vmprobe\grad_probe.py`（连 VM Service 让 app 用**自己的** `ImsSession` 去 POST，票据不出 app，HTML 落 `%TEMP%\grad_raw.html`）—— 比从 Hive 里挖 JSESSIONID 安全。

### 13.5 培养方案有两张表：理论课程 + **实践环节**（2026-10-08 立 · 改动前必读）

用户原话：「我们需要更新一个一直忽略的事，那就是我们当前的培养方案查询接口只是『**理论课程**』的培养方案，但实际上培养方案还有『**实践环节**』，而**军事训练**就属于这一部分。」

**事实核实（2026-10-08 实测抓包）**：

| | 理论课程 | 实践环节 |
|---|---|---|
| 页面 | `pyfa.llkc.html` | **`pyfa.sjhj.html`** |
| 表号 | `DataTable.jsp?tableId=2508` | **`DataTable.jsp?tableId=2509`** |
| menucode | `S20101` | `S20102` |
| 列 | 序号 / 学年学期 / 课程 / 学分 / **课程类别（三段式 `2024公共课/国家安全教育/必修课`）** / 课程地位 / 考核方式 / 总学时 / 讲授 / 实验 / 实践 / 其它 / 周学时 / 标识 | 序号 / 学年学期 / **环节** / 学分 / **环节类别**（军训·科研创新实践·实习实训·论文设计） / 考核方式 / 周数 / 标识 / (隐藏 `hjdm`) |
| 2025 级计算机科学与技术 | 97 门 / 223 学分 | **4 项 / 18 学分**：军事训练 2 · 创新创业实践活动 4 · 毕业实习 4 · 毕业设计 8 |

- **POST body 两页同构**：`count=1&initQry=0&nj_=<年>&sel_yxb=<学院码>&sel_zy=<专业码>&fzyxs=zx&menucode_current=S2010X`。⚠ **少了 `nj_`/`sel_yxb`/`sel_zy` 服务端返回空表（`total=0`）而且不报错** —— 实测踩过，别以为是「这个专业没有实践环节」。
- 实现：`curriculum/domain/practice_stage.dart`（模型，含 §3 容错 `fromMap`）+ `data/anti_corruption/practice_curriculum_html_parser.dart`（**按 `<td name="…">` 取列，不按下标** —— 表里夹着隐藏列）+ `.../practice_curriculum_remote_datasource.dart` + `.../practice_curriculum_local_datasource.dart`（**`Box<String>` 单 key JSON**，刻意不复用 `Box<Curriculum>` 那个 Hive 对象类型：加字段要走 schema 迁移 + build_runner）+ `practice_curriculum_repository.dart`（缓存优先，与 `CurriculumRepository` 同形）+ providers；定位链路复用 `myPlanKeyProvider`（学籍→学院→专业，见 §13.4）。
- **军事训练从此不再落进「未归类」** —— 它是实践环节表里的第 1 项。未归类只剩真正两边都没有的课。

### 13.6 毕业学分页的三段口径补遗（2026-10-08 · 与本轮同批）

**① 第三段：实践环节进度。** 页面节顺序 = 必修课进度 → **实践环节进度** → 选修课进度 → 未归类 → 不计入总学分。顶部三张指标卡（≥1000 宽并排、≥720 两张一行、更窄逐张堆）。`GraduationCreditProgress` 多一个 `practice` 组 + `grandRemaining`（必修 + 选修 + 实践环节）。
- **重叠口径**：一门课若**两张表都有**（本专业实测无重叠，别的专业可能有），按**理论课程计入必修**、不重复计入实践环节，并在 notes 里点名 —— 分母各按各的表算，不会双计。

**② 「已选未考」浅色段。** 用户原话：「用更**更浅一点**的红色，标识**已选但是未考试**的学分部分。」
- 数据源 = **本学期课表的本地缓存**（`scheduleCachedEntriesProvider((xn, xq))`，只读不联网）**减去成绩里已拿到学分的**；学年学期取 `currentSchoolTerm(now, terms: offlineSemesterTermsProvider)`（口径同 AI 层的 `aiCurrentTerm`，**必须传 terms**，不传会退化成月份经验规则）。
- 呈现 = `FluentProgressBar(value: 已修占比, secondary: 在修占比)` —— 主段深红、在修段**同色 40% 透明度**（`secondaryTone` 默认 `tone.withValues(alpha: .40)`），实现是「先铺 `value+secondary` 浅色、再压 `value` 深色」，两段之间硬边。另有 `_InProgressLine` 那个 8×8 浅色小方块 + 「另有 N 学分已选未考」。
- ⚠ **在修不冲抵「还差」**：`remaining` 只按**已拿到手**的算（在修不等于通过）；`inProgressTotal` 单独给。`inProgressCounted` / `inProgressRatio` 会截顶到「要求 − 已修」，所以浅色段永远不会越过轨道。
- 在修课**归不到任何要求项时静默跳过**（还没出成绩，谈不上归错类）。

**③ 联动：实践环节不计入加权。** 用户原话：「还有一个联动的部分，那就是『实践环节』一般**不计入加权成绩**，详见各材料。」
- 材料明文 = `assets/rules/text/r05a.md` 第二十四条注 4：「**实践类课程（如毕业论文、毕业实习等），不计入课程加权平均成绩**」（`r08a` / `r09a` / `r10a` / `r23a` 同款）。
- 实现 = `ims/grades/domain/grades_exclusions.dart` 的 `PracticeCourseFilter`（**代码 + 名称两路**，`fromPractice(PracticeCurriculum?)`）+ `practice_course_filter_provider.dart`（**同步** `Provider`，用 `.valueOrNull` 读实践环节表；别改成 FutureProvider 逼调用方 await）。消费方 = 成绩页（`_practiceFilter` 每帧从 provider 赋值，替换掉原来那个 `static const _excludedCourses`）与分数估计（`gePriorGradesFromBox(box, filter:)`）。
- ⚠ **历史那份四个课名的名单只增不减**：表拿不到时它就是全部判据，删了会让 GPA 数字**悄悄变大**。表在时两者**并集**（表里没有「毕业论文」，历史名单兜住）。
- ⚠ 与毕业学分**不矛盾**：实践环节**算毕业学分**，只是**不进加权**。

**④ 不计入总学分的课。** `assets/rules/text/r03a.md` 明文：「**大学生安全教育不计入总学分**，但安排 16 学时必修课，作为毕业资格审核的依据」（总学分要求表脚注同款）。
- 它既不在理论课程、也不在实践环节表里 —— 从前落进「未归类」、理由写成「两边都没有」，那是**不完整**的。
- 现在单列一段「不计入总学分」+ `kNotCountedCreditCourses`（`credit_progress.dart`，先按名、再按码 `1003000011` 兜底），理由写「学校文件规定不计入总学分，只作毕业资格审核依据」。⚠ **它仍计入 `earnedTotal`**（那是「成绩单上一共拿到多少学分」，与是否算毕业学分是两回事）。

**⑤ 守卫**（本轮新增/改动）：`practice_curriculum_test.dart` 11 例（真实抓包台账 + 按 name 取列 + JSON 容错）、`practice_course_filter_test.dart` 9 例（判据来源 + 降级逐字不变）、`graduation_credit_progress_test.dart` 38 → **48 例**（实践环节 6 例 + 已选未考 8 例 + 不计入总学分 3 例）、`fluent_progress_bar_test.dart` **6 例**（含第二段截顶与无障碍值）、`graduation_credit_page_layout_test.dart` **6 例**（页面变长后改成 `scrollUntilVisible` 逐节滚）。

### 13.7 挂科：不及格也算「已修」但不能算「已获得学分」（2026-10-08 二轮 · 改动前必读）

用户原话：「**不及格的话即使已修也算未获得学分，并且我希望有 UI 提示**。（测试时不能用我的数据测了，我没有挂科记录）（挂科可以产生一个联动，那就是一旦有挂科记录，保研分页就显示您已挂科，无保研资格之类的）」。

**判据（唯一实现）= 成绩表里有这门课（= 已考核）且获得学分为 0**：
- `TakenCourse.failed` / `CreditProgressCourse.failed`（`credit_progress.dart`）；
- `FailedGrade` + `failedGradesFromBox` + `failedGradesProvider`（`ims/grades/domain/failed_grade.dart`、`data/providers/failed_grades_provider.dart`）—— 推免页与毕业学分页共用同一份。
- 成绩表里的行都是**出过分**的，所以这条不会把「还在修、没出分」误判成挂科（那些走课表那条路，根本不在 `taken` 里）。

⚠ **必须区分「挂科」与「还没修」**：两者 `earned` 都是 0。所以 `CompulsoryCourseState` / `PracticeStageState` 各多一个 **`attempted`**（成绩单上有没有这门课）字段，`failed = attempted && credit > 0 && earned <= 0`。
**2026-10-08 实测踩过**：只看 `earned` 会把整张培养方案里所有没修的课都判成挂科（50 门必修课全变「挂科」，`failedCredits` 从 4 跳到 29.5）—— 守卫里的「★ 挂科 ≠ 在修」「★ 挂科不计入已修」两条当场钉住。

**语义（三条，别改口径）**：
1. 挂科**不计入「已修」**（已修按**获得学分**算），所以它**仍然留在「还差」里** —— 重修通过才消失。
2. 挂科**不算「在修」**：`inProgress` 走课表那条路，两者互斥。
3. **重修通过后就不再是挂科**（同码取获得学分更高的那条，见 `grades_cache_reader.dart` 的去重），但**推免页的「有挂科记录」仍然保留**（用户措辞「一旦有挂科记录」，看的是「有没有挂过」）。

**上屏**：
- 毕业学分页**最顶上**一条 `FailedWarningBar`（`FluentInfoBar(severity: error)` + 逐门明细：课名 / 学分 / **分数**），排在指标卡**上面** —— 挂科会直接改变「已修 / 还差」的含义，得先看到再读数字。
- 必修明细行与选修项里的挂科行标 `p.critical` 的「挂科 52」（而不是「未修」）；口径脚注里也点名。
- 推免页 `RecommendationFailedBar`（`Key('recFailedBar')`）：标题「您已有挂科记录，N 门」+ 课名 + 「按推免工作办法，有课程考核不及格记录的一般不具备推免资格」。⚠ 只**陈述事实**、不替学校下最终结论（各年 / 各学院口径可能不同）；数据取不到时**整条不画**，不会把「没取到」说成「没挂科」。

⚠ **测试纪律**：真实账号**没有挂科记录**（用户明确说了），所以挂科分支**只能靠合成数据覆盖** —— 全部集中在 `graduation_credit_progress_test.dart` 的「挂科」组（10 例）与 `graduation_credit_page_layout_test.dart` 的「挂科」组（3 例，含 360/280 窄屏不溢出）。**别拿真实数据去"验证"这几条**，永远走不到。

### 13.8 ⚠ 本页内容被夹在 880：`extraWide` 永远到不了（2026-10-08 实测）

`FluentPageBackground.maxContentWidth` 默认 **880**（Fluent 口径：宽窗口不把内容拉到 4K 全宽），于是 `_ReportView` 的 LayoutBuilder 实际只拿到 **832**。
**后果**：`Breakpoints.extraWide`(1000) 在**本页永远不可达**。我一度按「1600 窗口 → 三卡并排」写了 `extraWide` 分支，实测发现它是**死代码**（探针打印 `overview=Size(832.0, 230.0)`），已删。
**顶部指标卡布局定案 = 两档**：`≥wide(720)` → 「必修 + 选修」同行 + 实践环节另起一行；更窄 → 三张竖着堆。
**等高做法**：`_EqualHeightRow` = `IntrinsicHeight(child: Row(crossAxisAlignment: stretch, …))`。
- ⚠ **直接 `Row(stretch)` 不行**：本排位于 `ListView` 内、纵向无界 → 断言「BoxConstraints forces an infinite height」。
- ⚠ **别把 `IntrinsicHeight` 套到带 `ListView` / `GridView` 的子树外面**（viewport 不支持 intrinsic 尺寸，同 §3.1）。
- 守卫 = `test/graduation_credit_page_layout_test.dart` 的「顶部指标卡等高」组：真实页面量同排两张的高度差 ≤ 0.01，并把「内容被夹到 832」这件事写进注释（阈值一变，守卫会提醒你重算）。

### 13.9 培养方案页（2026-10-09 立 · 第二张 Fluent 页 · **停用自研表格**）

用户原话：「我们现在『培养方案』页用的是自研半成品表格组件，现在我们先不用这个表格组件，请你优化培养方案的显示」；追问拍板两条：①「我希望支持各种显示方式，例如按分类聚合、按开课时间聚合；还要支持搜索」；②实践环节「**并入**」。

**旧页面的三个事实（实测，别照抄它的列）**：旧页把整张方案塞进 `shared/widgets/reorderable_table`（16 列 × 97 行、横向滚动、表头/行头染 `colorScheme.error` 红）。拿 `app_data/curriculums.hive` 里 5 份真实方案（404 门课）逐列看过：`三级分类` **恒空**（0 处非空）、`标识` **恒空**，`课程性质` 那列实际印的是「课程地位」（且只在主干课时才有字）。新页面**不再画这三列**，`tertiaryCategory` / `identification` 只在真有值时才进展开详情。
⚠ `reorderable_table` 现在**没有任何调用方**（全仓唯一消费方就是本页），但按用户口径「**先不用**」——**本体保留**（`lib/shared/widgets/reorderable_table/` 一个字没动），要复用直接 import。

**页面结构**（`presentation/curriculum_screen.dart`，`ImsTabContainer` 以 `showAppBar: false` 挂载）：
1. **范围选择器**（`widgets/curriculum_toolbar.dart` 的 `CurriculumSelectorCard`）：年级 / 学院 / 专业三个 `DropdownButtonFormField`，只是换成 Fluent 填充与 4px 圆角（Flutter 没有 Fluent 版下拉，不为它自己造）；加载中用 `hint` 写「正在加载…」并禁用，**不摆转圈**；
2. **两张指标卡**（`widgets/curriculum_summary_cards.dart`）：理论课程（学分 + 门数构成 + 大类占比条 + 图例 + 刷新按钮）与实践环节（学分 + 各环节类别小计）；
3. **工具条**（`CurriculumToolbar`）：搜索框 + `SegmentedButton`（三种分组形态）+ 快筛胶囊 + 「共 N 门 · M 学分」（重取时前缀「正在更新…」）；
4. **理论课程分组清单**（`widgets/curriculum_sections.dart`）：节标题 = 聚合键，卡内 = 组头（组名 + 门数/学分）+ 课程行（行首行号 + 课名 + `[代码] · 类别 · 考核` + 星标[主干] + 修读性质徽标 + 学分 + 展开箭头），点行**就地展开**学时明细（总/讲授/实验/实践/其它/周学时、课程地位、大类、开课学期）；
5. **实践环节**（培养方案第二张表 `pyfa.sjhj.html` / `tableId=2509`，直接复用 `PracticeCurriculumRepository`）：行 = 环节图标 + 名称 + `[代码] · 类别 · 学期 · 周数 · 考核` + 学分；
6. **口径脚注**：数据来源、学分合计、两张表重叠门数（`curriculumPracticeOverlap`）。

**三种分组形态 + 搜索 + 快筛的唯一实现 = `domain/curriculum_browse.dart`**（纯逻辑、无 BuildContext，页面只负责画）：

| 形态 | 节（大写标题） | 组（卡内小标题） | 排序 |
|---|---|---|---|
| `category`（默认） | 课程大类 | **二级分类** | 都按教务表首次出现顺序 |
| `term` | 开课学期（标题旁带短码 `251`） | **课程大类** | 学年学期先后，**认不出的排最后** |
| `flat` | 「全部课程」 | 无 | 教务表原顺序 |

- 搜索命中 **课名 / 课程代码 / 课程大类 / 二级分类**（忽略大小写与两端空白）——带类别是为了「搜『专业方向』就把那一类挑出来」；
- 快筛：`all` / `compulsory` / `elective`（= **非必修**，含限选、任选）/ `core`（主干课程）；计数行只给命中合计，另附「（共 N 门 · M 学分）」；
- ⚠ **「按分类」时行内不写二级分类**（组头已经写了），`flat` / `term` 才带出来 —— `CurriculumCourseRow.showCategory`；
- ⚠ **实践环节的快筛语义**（有意为之）：整张表都是必修性质、也没有「课程地位」，所以 `compulsory` 保留全部，`elective` / `core` 会把它**整个筛空**（页面照写「共 N 项」，另给一句「当前搜索/筛选下没有命中的实践环节」）。这不是 bug，别改成「实践环节不受筛选影响」。

**开课学期 = 一张侧表（`domain/curriculum_terms.dart` + `curriculumTerms` box）**：教务教学计划表的第 2 列 `学年学期`（原文 `2025-2026学年第一学期`）旧解析器**整列丢掉了**，而用户要按它聚合。加字段要动 `Course`（Hive 对象 → schema 迁移 + build_runner），所以照 §13.5 实践环节的老套路**另开 `Box<String>` 单 key JSON**：
- 抓一次表的解析结果**课程 + 侧表一起落盘**（`CurriculumRepository._fetch`），所以 `getCourseSemestersIn` 紧接着那一步通常**零网络**；
- 读的时候必须**条数对齐**（`CurriculumTerms.alignsWith`）：对不上（2026-10 之前的老缓存没有侧表 / 方案改过）→ **重抓一次**，绝不把学期错配到别的课上；
- 侧表拿不到 → `Left`，页面在「按开课学期」时挂一条 warning InfoBar 写「开课学期没取到：…（需要教务会话）」，**不**退化成空学期列表去冒充「都没排定」；「列是空的」与「没取到」是两条不同文案；
- 学期文本归一走 `school_calendar`（`schoolTermOfText` / `schoolTermLabel` / `schoolTermCode`，§36 的唯一出处）：认不出 → 「开课学期未排定」、短码空串、排序键 `termSortKeyUnknown`（**排最后**，不许当第一学期）。

**刷新两条路**（§3「页面数据自动刷新」+「刷新必须看得见」）：`PageAutoRefresher` → `reload()`（**缓存优先**，离开再回来零网络）；指标卡上的刷新按钮 → `reload(force: true)`（绕过缓存重抓两张表）；重取期间工具条计数行前缀「正在更新…」，指标卡的刷新按钮禁用 + tooltip 变「正在更新…」。

**⚠ 本页两条实测踩坑（改这页前先看）**：
1. **`FluentMetricCard` 的 footer 里放图例要可压缩**：大类占比图例是 `Wrap` 套 `Row`，280 宽实测溢出 22 / 47px —— `Wrap` 只负责整条图例换行，**不**会压缩行内文字，文字必须 `Flexible` + `maxLines: 1` + 省略号；
2. **行号别用 `FluentIndexBadge`**：那是固定 24×24 的实心徽标，真实方案 180+ 门课，三位数在里面会折行；改用固定宽度（28）右对齐的小字（`_CourseIndexLabel`）。
另外：本页 `FluentPageBackground.maxContentWidth` 取 **1000**（毕业学分页是默认 880）—— 分组卡要放得下，且 §13.8 那条「880 夹到 832」的教训是**那一页**的，别照搬。

**宿主与换行**：改动只落在 `lib/features/ims/curriculum/`（`domain/curriculum_browse.dart`、`domain/curriculum_terms.dart`、`data/…`、`presentation/…`）+ `lib/core/constants/hive_box_names.dart`（加 `curriculumTermsBoxName`）+ `lib/design/fluent/fluent_controls.dart`（加 `fluentShareAlpha`，图例与占比条共用同一档深浅）。⚠ `curriculum_viewmodel.dart` 本轮顺手把工作区那份被改成 CRLF 的换行**归一回 LF**（HEAD 本来就是 LF，否则 `git diff` 整文件飘红）。

**守卫**：`test/curriculum_browse_test.dart`（**24 例**：三种形态的顺序与小计 / 学期排序与「未排定」/ 搜索 / 快筛 / 汇总 / 实践环节快筛语义 / 重叠统计）、`test/curriculum_terms_test.dart`（**13 例**：mapper 按表头名取列 / 学期归一 / JSON 容错 / 真 Hive 上的仓库缓存与对齐重抓 / 没会话时如实报错）、`test/curriculum_page_layout_test.dart`（**16 例**：宽屏各段画得出来 / 搜索真的筛 / 切形态 / 展开详情 / 学期与实践环节的三种降级文案 / 360 与 280 不溢出）。合计 **53 例**。
