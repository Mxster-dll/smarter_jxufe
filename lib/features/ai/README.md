# 内置 AI 助手（`lib/features/ai/`）

用户 2026-09-19 立项，原话：

> 我们希望增加一个功能，那就是 AI 融入项目的底层。我们希望添加一个内置 ai 功能，
> 通过配置 api，然后可以和这个 ai 对话，这个 ai 则可以访问到这个软件内部所有的数据
> （包括设置），比如成绩、比如规章制度、比如课表，我们都可以通过对话与这个 ai 获取
> 这些信息，比如我们希望可以这样问：我们希望知道今天蒋剑老师没有课的时间，然后 ai
> 返回会话。

## 已拍板的四项口径

| 维度 | 决定 | 理由 |
|---|---|---|
| 模型接入 | **OpenAI 兼容 + 供应商预设**，可保存多套切换 | 8 家预设覆盖国内主流；换供应商不必重填 |
| 取数方式 | **工具调用为主 + 轻量快照 + 自动降级** | 不把 427KB 校规灌进提示词；快照省掉一轮调用 |
| 权限 | **只读 + 写操作二次确认** | 写操作走 `AiWriteGate`，用户不点同意就什么都不发生 |
| 入口 | **首页宫格/侧栏条目 + 全局悬浮球**（可关） | 悬浮球挂在 `MaterialApp.builder`，任意页面可叫 |

## 入口与悬浮球（2026-09-19 二轮加固）

| 形态 | 位置 | 实现 |
|---|---|---|
| 宫格第一格 | 首页「全部服务」 | `home_service_catalog.dart` 里 `homeServiceEntries` 的第一条 |
| **侧栏顶部固定项** | 紧贴「数据一览」**正下方**（不落进「数据与信息」组） | 条目上的 `HomeServiceEntry.sidebarPinned: true`；`home_sidebar.dart` 在 `_overviewRow` 之后单独渲染，并在 `_group` 里把这些条目摘掉 |
| 全局悬浮球 | **只给手机 / 平板**：任意页面右下角，可拖、松手吸附到近边。**电脑端不出球** | `presentation/ai_floating_ball.dart`，挂在 `lib/main.dart` 的 `MaterialApp.builder` 上；开关 = 设置页「AI 助手 → 全局悬浮球」（桌面端该开关换成一行说明） |

侧栏那条**仍然只有一份清单**（`home_service_catalog.dart`）：标志位长在条目上，
不是「在 `home_screen.dart` 里硬写一行」。宫格不受影响，仍按目录顺序铺（AI 助手照旧第一格）。

**电脑端（Windows / macOS / Linux）一律不出悬浮球**（用户 2026-09-19 四轮原话：
「我希望电脑端不显示悬浮球」）—— 桌面端入口就是左侧导航栏「数据一览」正下方那一格，
再压一个圆球纯属重复、还挡正文。判定 = 公开顶层纯函数
`bool aiDesktopPlatformOn(String platform)`（吃 `TargetPlatform.name` 小写形式，
与 `geMemoMobilePlatformOn` / `avatarMobilePlatformOn` 同一口径），门控写在 `build` 里。
⚠ 桌面端**仍然返回同一个 `Stack` 形状**（只是不往里塞球）—— 形状一变根 Navigator
会被卸载重挂，见下面「三条」的第 ③ 条。

悬浮球有**三条**独立的坑，都踩过（详见下面「踩过的坑」）：
`MaterialApp.builder` 的 context 在 Navigator **上方**；鼠标的拖拽 slop 只有 1px；
`dispose()` 里改 provider 会被 Riverpod 拒发通知。守卫 =
`test/ai_floating_ball_test.dart`（它**必须**按 `main.dart` 的真实挂法测，
`MaterialApp(home: AiFloatingBallHost(...))` 那种挂法会把这些坑全掩盖掉）。

## 目录结构

```
domain/     纯领域：配置模型、消息模型、Markdown 解析（无 Flutter / Hive / 网络）
data/       协议与编排：SSE 分帧、客户端、设置存储、对话存储、快照、对话控制器
tools/      工具框架与全部工具实现（唯一清单 = tool_registry.dart）
presentation/      对话页、设置节卡片、悬浮球、写操作确认弹窗、页面跳转
presentation/widgets/  Markdown 渲染器、写操作确认弹窗、设置节卡片
```

分层铁律：`domain/` 不 import `data/`；协议细节（SSE / 请求体 / 错误文案）全在
`data/ai_stream.dart` 且是**纯函数**，所以每一条分支都能单测钉住。

## 工具清单

`kAllAiTools`（`tools/tool_registry.dart`）—— 新增工具只改这一处。

| 工具 | 作用 | 数据来源 |
|---|---|---|
| `search_rules` | 规章全文检索（关键词 → 命中小节摘要） | `assets/rules/text/*.md`（427KB，按标题切节 + 缓存） |
| `read_rule` | 读某篇/某节的完整条文 | 同上 |
| `get_my_schedule` | 我的课表（今天 / 本周 / 整学期） | 先 `scheduleCachedEntriesProvider` 本地缓存，缓存空才 `scheduleRepositoryProvider`（**那条是纯在线、会抛**） |
| `find_free_time` | **无课时间**（我自己 / 教师 / 班级） | 同上 + `free_time.dart` 引擎；教师/班级走公共查询（需登录） |
| `query_timetable` | 教师 / 班级 / 教室 / 课程课表 | 教务公共查询（需登录） |
| `get_grades` | 成绩（可按课程/学期筛，给加权平均） | `gePriorGradesProvider`（离线） |
| `get_score_estimate` | 分数估计：平时分、总评预测、加权汇总 | `geCoursesProvider` + `geSummarize` |
| `get_deadlines` | 课程截止日期（重复条目自动滚到下一次） | `geCoursesProvider` 的 `deadlines` |
| `get_curriculum` | 培养方案：要修哪些课、各多少学分、必修/选修 | 学籍 → 学院 → 专业 → `CurriculumRepository`（**命中缓存不发网络**） |
| `get_graduation_credits` | 毕业学分构成**要求**（只有要求，没有已修） | `graduationRequirementsProvider`（在线，需教务会话） |
| `get_volunteer_hours` | 志愿时长（累计 + **本学年** + 活动记录） | `volunteerActivitiesProvider` + `volunteerHoursStats(xn: 教学学年)` |
| `get_zongce` | 综测：总评 + 五育得分与等次 + 明细 | `zcMaterialsProvider` + `ZcStore.loadManual` + `zcCalculate` |
| `list_materials` | 材料库（按材料类型分组） | `zcMaterialsProvider` + `groupMaterialsByType` |
| `get_school_calendar` | 校历：第几教学周、放假区间、调休备注 | `schoolCalendarProvider` + `teachingWeekProvider` |
| `get_energy` | 宿舍电费 + 校园网费余额 | `dashboardElectricityProvider` + `netFeeSummaryProvider` |
| `get_student_info` | 学籍（姓名/学院/专业/班级/辅导员） | `studentInfoRepository` 离线缓存 |
| `get_app_settings` | 读设置 | 各偏好 store |
| `update_app_setting` | **写设置（需确认）** | 同上 |
| `open_page` | 给界面递一个「打开某页」按钮 | 首页服务目录（不自己跳转） |

### 用户那句例子的落地路径

「今天蒋剑老师没有课的时间」→ 模型调 `find_free_time(teachers: ["蒋剑"])`：

1. `publicQueryComboBoxProvider` 把姓名解析成教师 code（精确 → 包含 → 报候选）；
2. `publicQueryReportProvider` 取该教师课表 → `slotsOfTimetables` 转占用槽；
3. `findFreeWindows(slots, week: 当前教学周, weekdays: {今天})` 算空闲窗口
   （含单双周、半日块不合并）；
4. `PeriodTable` 把节次区间翻成钟点（`第 3-4 节（10:10-11:35）`）。

**算术全在引擎里，模型只负责把口语翻成参数** —— 这样它不会因为自己数错节次而给出错误答案。

## 回答渲染（Markdown + 空卡片守卫）

用户 2026-09-19 原话：「我希望支持markdown渲染，同时AI回复中偶尔会出现空卡片」。

**Markdown**：`domain/ai_markdown.dart`（解析，纯 Dart）→
`presentation/widgets/ai_markdown_view.dart`（渲染）。

- **为什么不复用 `lib/features/rules/data/md_parser.dart`**：那套是给 pdf2md 产出的
  **法务长文档**用的 —— `BlockKind` 只有 `heading / para / table` 三种块，内联格式
  （粗体 / 行内码 / 链接）、列表、代码块**全部丢弃**；它的 `clean()` 还会折叠 CJK
  之间的空格（对代码内容是破坏性的）。对话回答里这些恰恰是高频内容，所以另写一套
  （阅读器仍走它自己那套，互不影响）。
- 支持：`#` 标题 1–6、段落、``` 围栏代码块（带语言 + 复制按钮）、`-`/`*`/`+` 与 `1.`
  列表（缩进栈推嵌套深度、`- [ ]` 任务项）、`>` 引用、GFM 管道表格（含 `:--:` 对齐、
  横向滚动）、`---` 分隔线；内联 `**粗**` / `*斜*` / `` `码` `` / `~~删~~` /
  `[文字](链接)` / `<http://…>` / 反斜杠转义。
- **两条刻意的取舍**（都是为对话场景）：① 单换行**保留成换行**（标准 markdown 会折叠
  成空格，模型常拿单换行分点，折叠后挤成一坨）；② `_` 强调**只在词边界生效** ——
  `get_my_schedule` / `snake_case` 这类标识符在回答里很常见，按「任意 `_` 都开斜体」
  处理会被撕成碎片。`*` 不受此限，但 `*` 也不吃 `2 * 3 * 4` 这种乘法写法。
- **容错优先**：认不出的行一律当普通段落，**绝不抛异常** —— 流式回答每个 token 都会
  重解析一次，半截语法（未闭合的 `**`、没写完的围栏）随时出现，抛异常会让气泡整个挂掉。
- **整条消息共用一个 `SelectionArea`**：块之间能连着选中、复制。
- 链接点击走全应用统一的外链出口 `externalUrlOpenerProvider`（provider 化的意义就是
  测试能替换掉它），且**只放行 http/https** —— 模型偶尔会编出 `javascript:` / `file:`。
- 性能：`_LinkRegistry` 按 URL 缓存 `TapGestureRecognizer` 并在 `dispose` 统一释放
  （流式每 token 重建 span，在 `build` 里新建识别器会以每秒几十个的速度泄漏）；
  解析结果留 1 条 memo。

**空卡片**（`aiShouldRenderMessage`，`presentation/ai_chat_screen.dart`）：
根因是**带工具调用的那一轮**，assistant 消息的 `content` 常常是**空串** —— OpenAI 协议
要求这条消息（连同 `tool_calls`）原样发回端点，而模型在决定调用工具时往往不附任何文字。
它**必须留在历史里**（抽掉会让端点直接 400），但**不该画出来**：画出来就是一张只有
内边距的空卡片，每查一次工具多一张。它查了什么由 `_TraceStrip` 表达 —— 那正是「让用户
看得见 AI 动了哪些数据」的设计。

三条防线（都在，别只留一条）：
1. `aiShouldRenderMessage(m)` 统一判定「这条要不要画」：`tool`/`system` 不画，
   `content` 为空白的不画（规则抽成公开函数是为了能单测，藏在 `build` 里只能靠碰运气）；
2. `_AssistantBubble` 内部再兜一次 `text.trim().isEmpty → SizedBox.shrink()`，
   让「组件画出空卡片」在组件层面不可能发生；
3. `AiMarkdownView(source: 空)` 自己返回 `SizedBox.shrink()`（解析出 0 块就不画）。

⚠ **不改** `data/ai_chat_controller.dart`：那条空消息是协议要求的历史，删了会让下一轮
请求 400。要挡的是「显示」，不是「存储」。

## 三条自动降级（`AiChatController._streamOnce`）

1. 端点不认 `stream_options` → 去字段重发（保住多数端点的 token 用量）；
2. 端点不支持流式 → 转非流式重发；
3. 端点不支持函数调用 → `_toolsDisabled = true`，改为
   `buildAiDataPack()` 预取一批常用数据塞进提示词。

降级**不写回用户配置**（下次仍按用户设置来）；判定条件刻意保守
（`aiLooksLikeToolsUnsupported` 要求同时出现关键词与否定词），
否则一句普通 400 会让整个对话悄悄降级。

## 安全与隐私

- API Key 与聊天记录都存本机 Hive（`aiSettings` / `aiChat`），**按账号隔离**；
- 这两个 box **不得**加入云同步载荷白名单
  （`lib/features/library_sync/data/libsp_payload.dart`）—— 明文过图书馆订阅词这条通道；
- AI 用**裸 Dio**（`aiDioProvider`），绝不复用 `currentImsDioProvider`
  —— 那个挂着教务 `CookieManager`，复用等于把学校账号 cookie 发给第三方；
- `get_student_info` 刻意不回传身份证号、家庭收入、高考分数。

## 加一个新工具

1. 在 `tools/` 下写一个 `class XxxTool extends AiTool`，给 `spec`（name 用 snake_case，
   description 写清「什么时候用」而不只是「这是什么」）；
2. 写操作把 `mutating => true`，在执行前 `await ctx.gate.confirm(...)`；
3. 在 `tool_registry.dart` 的 `kAllAiTools` 加一行；
4. 给 `test/ai_tools_test.dart` 的「用户需求里点名的能力都有对应工具」补断言。

返回值一律是**给模型看的紧凑中文文本**（token 要花钱），结构化数据放 `AiToolResult.ui`。

## 测试

```powershell
& $dart $snap test test\ai_config_test.dart test\ai_stream_test.dart test\ai_tools_test.dart test\ai_more_tools_test.dart test\ai_markdown_test.dart test\ai_ui_test.dart test\ai_floating_ball_test.dart
```

- `ai_config_test`：URL 兜底（漏填 `/v1` 是实测最易错的一档）、容错解析、多档管理；
- `ai_stream_test`：SSE 分帧（CRLF / 多 data 行 / 注释 / 残留）、tool_calls 分片累积、
  请求体形态（`content: null`、空 tools 不下发）、错误文案与降级判定；
- `ai_tools_test`：md 切节与检索打分、工具注册表（名字唯一 / schema 合法 / 写操作标记）、
  用户点名的五项能力都有工具、**我的课表「先缓存后联网」的四条分支**；
- `ai_more_tools_test`：培养方案总账口径（全量算账 / 清单才筛选）、毕业学分合计行、
  志愿时长的学年归集与「—」、材料分组、校历连续非工作日合并。**全部靠 override
  底层 provider 来测** —— 不碰 Hive、不碰网络，测的就是工具自己的聚合与措辞；
- `ai_markdown_test`（40 例）：块级（标题 / 段落 / 围栏 / 列表嵌套与任务项 / 引用 /
  表格对齐与缺列补齐 / 分隔线 / **任意半截语法都不抛**）、内联（粗斜删码链 / 转义 /
  **`snake_case` 不被撕成斜体** / 双反引号）、渲染（**真的加粗了、真的等宽了**、表格是
  `Table`、链接可点且回调拿到 URL、空回答不画任何东西）、空卡片守卫（判定规则 6 例 +
  **端到端：喂进「user → 空 assistant(toolCalls) → tool → 最终回答」，断言只长出一个
  `AiMarkdownView`**）。
- `ai_ui_test`（18 例）：对话页空态与未配置态、设置卡（脱敏 key / 悬浮球开关 /
  **电脑端换成一枚说明行**）、悬浮球显示与自隐藏、写操作确认弹窗。
- `ai_floating_ball_test`（9 例）：**按 `lib/main.dart` 的真实挂法**（`navigatorKey` +
  `MaterialApp.builder`）测 —— 画得出来 / 点击真能进对话页（`navigatorKey` 通路）/
  **鼠标点击抖 2px 仍算点击** / 真拖拽（越过中线）不打开且贴边停靠 / 开关关掉不渲染 /
  **进对话页后隐藏、退出后必须自己回来**（守 Riverpod 构建期不通知那条）/
  **电脑端不渲染但宿主与 app 照常** / 电脑端开关开着也不出球 / `aiDesktopPlatformOn` 判定表。
  用户 2026-09-19 报的三件事全部落在这一组里。

⚠ 测试坑：
① `AiSettingsStore(persist: false)` —— widget 测试跑在假异步时钟上，Hive 的真实文件 IO
永远不会完成（`await save()` 会挂死）；
② `AiChatScreen.dispose()` 里不能 `ref.read`（抛 `Cannot use "ref" after the widget was
disposed`），计数器必须在 `initState` 取出来存住。
③ 在测试里 override `FutureProvider.family` 用 `overrideWith((ref, arg) async => ...)`；
④ 想拿一个真实 `Ref`：`ProviderContainer` 本身**不是** `Ref`，用
`container.read(Provider<Ref>((ref) => ref))` 借一个（provider 非 autoDispose，Ref 一直有效）。
⑤ **别用 `TextSpan.visitChildren` 递归收集 span**：它在 `text != null` 时**会拿 span 自己
回调一次**，照直递归就是无限递归（实测栈溢出刷屏）。直接遍历 `span.children`。
⑥ 想给对话页喂一段指定的消息历史：真控制器的 `_messages` 是私有的，而 widget 测试里
Hive 文件 IO 跑不动（见①）→ **继承 `AiChatController` 覆写 `messages` / `traces` /
`busy` 三个 getter**，再用 `aiChatControllerProvider.overrideWith` 注入。
⑦ 断言「**真的加粗了**」不能只看文字在不在：`Text.rich` 的 `find.text` 匹配的是
`textSpan.toPlainText()`（markdown 符号已经被解析掉），所以 `find.text('**周一**')`
必须是 `findsNothing`、`find.text('周一')` 才命中；要验样式得把 `RichText` 的 span 树
摊平后按 `style.fontWeight` / `style.fontFamily` 断言。
⑧ **测 `AiFloatingBallHost` 必须用 `MaterialApp(builder: …)`**（照抄 `lib/main.dart`）：
挂在 `home:` 里它就成了 Navigator 的**后代**，而真实位置是 Navigator 的**祖先**
（它是 Navigator 的兄弟）—— 挂法不同，`Navigator.of` 的行为完全相反，下面三个真
bug 会被**全部掩盖**（第一版测试就是挂在 `home:` 里的，所以它们一路活到用户手上）。
⑨ 判定「一次点击 vs 一次拖拽」要**自己算全局坐标差**，别指望竞技场：鼠标的拖拽
slop 只有 1px（见下），而 `DragStartBehavior.start`（默认值）会把首帧位移吞掉、
**单次大幅移动根本不派发 `onPanUpdate`**（`gestures/monodrag.dart` 的 `_checkDrag`）。
⑩ **要测「电脑端」得自己造平台**：`flutter_test` 里 `defaultTargetPlatform` **恒为
`android`**（`package:flutter/src/foundation/platform.dart:25` 的注释原文就是
「In a test environment, the platform returned is [TargetPlatform.android]」）→ 既有的
悬浮球用例测的本就是移动端行为；桌面端那两条必须 `debugDefaultTargetPlatformOverride =
TargetPlatform.windows`，而且**必须在测试体内 `try/finally` 复位** —— 用
`setUp`/`tearDown` 会直接失败：`TestWidgetsFlutterBinding._verifyInvariants`
（`flutter_test/src/binding.dart:1100` → `debugAssertAllFoundationVarsUnset`）在
**测试体跑完那一刻**就断言，tearDown 还没轮到，报
`The value of a foundation debug variable was changed by the test.`

## 已知未做（后续可加）

- 未纳入本地「调课 / 停课 / 补课」记录（`domain/reschedule.dart`）—— 入口是
  `reschedule_engine.dart` 的 `effectiveClasses(...)`；
- 还没接的工具：体测、竞赛获奖、请假、邮箱、蛟湖阅读 / 畅想之星、第二课堂。
  照上面「加一个新工具」四步即可，无需改框架。

## 踩过的坑（照抄前先看）

- **`ScheduleRepository.getSchedule` 是纯在线、无缓存的**，会话不在直接抛
  `Exception('获取 JSESSIONID 失败')`；cache-first 的是另一条路
  （`ScheduleCacheRepository` / `scheduleCachedEntriesProvider`）。
  `dashboardTodayCoursesProvider` 走的是在线那条 —— 别以为它离线可用。
- **`getCachedStudentInfo()` 是同步的 `Either<Failure, StudentInfo?>`**（不是 Future），
  取值必须 `repo.getCachedStudentInfo().fold((_) => null, (i) => i)`。
- **`replaceAll` 不解析 `$1`**：md 清洗里用 `r'$1'` 会把整行变成字面量 `$1`，
  必须 `replaceAllMapped`。
- **淡描边不能裸写 `outlineVariant.withValues`**（深色下会把 10% 白放大成 60%），
  走 `AppColors.hairline(context, 原浅色alpha)` —— 有源码守卫。
- **学号口径**：教务请求的 `xh` 用 `StudentInfo.serialNo`，`userId` 是统一认证号。
- **学期码不要 +1**：`getSchedule(semester: '${term.xq}')` 传的是 `'0'/'1'`。
- **`TapGestureRecognizer` 不在 `material.dart` 里**（`widgets.dart` 只用 `show` 列出了
  一部分手势类型）→ 要 `import 'package:flutter/gestures.dart';`，否则报
  `The name 'TapGestureRecognizer' isn't a type`。
- **span 样式不会自动继承**：`TextStyle.copyWith` 产出的是「字段全满」的样式，嵌套时子
  span 会**整体覆盖**父 span（不是合并）。所以渲染器把算好的完整样式**显式往下传**，
  别指望 `TextSpan(children: ...)` 能继承到父级的粗体/字号。
- **`SelectionArea` 不会吞掉 `TextSpan.recognizer` 的点击**（实测过：包在 `SelectionArea`
  里的链接仍然可点，回调能拿到 URL）。这条是实测结论，不是推测 —— 当初担心选区和
  点击抢手势才写了测试。

### 悬浮球的三条（2026-09-19 用户报「点击后概率无反应，电脑端不显示悬浮球」）

- **`MaterialApp.builder` 的 context 在根 Navigator 的「外面」**：
  `widgets/app.dart:1707-1717` 把 `routing`（`FocusScope(child: Navigator(…))`）**当参数
  塞进 `builder` 的返回值内部** → 宿主是 Navigator 的**兄弟**，祖先链上没有
  `NavigatorState`。所以 `Navigator.of(context)` **必然抛**
  `Navigator operation requested with a context that does not include a Navigator`，
  被 `main.dart` 的 `FlutterError.onError` 吞成一行日志 → 用户只看到「点了没反应」。
  **修法 = 走 `main.dart:90` 挂在 `MaterialApp.navigatorKey` 上的全局 `navigatorKey`
  （`lib/core/navigation/navigator_key.dart`）**，兜底才用 `Navigator.maybeOf`。
- **鼠标的拖拽 slop 只有 1 逻辑像素**（`kPrecisePointerPanSlop = 1.0`，触屏是
  `kPanSlop = 36`）→ 电脑端一次「点击」只要抖了 2px，外层 pan 就赢下手势竞技场、
  内层 `InkWell.onTap` **永不触发** = 「概率无反应」。修法 = 在 `onPanEnd` 里按
  **全局坐标差**判「几乎没动」，小的当点击补上（两条路互斥，不会双开），并把球位置
  放回按下那一刻（否则每点一次漂 1~2px，多点几次球自己走掉）。
  位移必须用全局坐标算：默认的 `DragStartBehavior.start` 会把首帧位移吞掉
  （`gestures/monodrag.dart:805-811`，`localUpdateDelta = Offset.zero`）→
  **单次大幅移动根本不派发 `onPanUpdate`**（`tester.moveBy`、快速一甩都是这种），
  累加 delta 的写法恒为 0、真拖拽会被误判成点击。同时把
  `dragStartBehavior: DragStartBehavior.down` 设上，那段位移才会以完整 delta 补发。
- **绝不能从 `dispose()` 里改 provider** —— 这是「电脑端不显示悬浮球」的真因：
  `dispose()` 跑在 `BuildOwner.finalizeTree()`（unmount 阶段），那一刻
  ① Riverpod 仍认为「widget 树正在构建」，`_notifyListeners` 被它的调试守卫拦下并抛
  `Tried to modify a provider while the widget tree was building.`
  （`flutter_riverpod/src/framework.dart` 的 `_debugCanModifyProviders`）→
  **值改了但监听者一个都收不到**；② `SchedulerBinding.schedulerPhase` 还是
  `persistentCallbacks`，`ensureVisualUpdate()` 在该阶段**不排帧**。
  合起来 = 进对话页后悬浮球按设计隐藏，**退出后再也不回来**。
  修法 = 把那次「减一」推迟到 `scheduleMicrotask`（帧的同步阶段已结束，两条都解除），
  并 `try/catch` 兜住「容器已随 App 退出销毁」。
  对照：`initState` 里那次「加一」放在 `addPostFrameCallback`（`postFrameCallbacks`
  阶段，排帧、且不在构建期）→ 它一直是好的，所以只有「隐藏回不来」这一半症状。
- 顺带修掉的隐患：`value.clamp(lo, hi)` 在 `hi < lo` 时**抛 `ArgumentError`**
  （窗口比球还窄/矮时真的会发生，首帧尤其）→ 走 `_clampIn` 先把上界抬到下界；
  隐藏悬浮球时**保持同一个 `Stack` 形状**，别 `return widget.child`（形状一变，
  根 Navigator 整棵子树会被卸载 + 用 GlobalKey 重挂）。

