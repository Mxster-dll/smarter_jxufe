<!-- 本册 = AGENTS.md §19 的正文（节号与标题原样保留，勿重编号）。根文件：../../AGENTS.md -->

## 19. 侧栏视图的页面 chrome 口径（2026-09-16 立）

用户原话（问句）：「我们如果采用左侧导航栏的话，每个页面具体的导航栏就不需要了，如果导航栏里不止标题，还有按钮的话，你看看应该放在哪」→ 给了三方案，**用户选 B：按钮下沉进页面内容**；第二问「要不要服务名」→ **「不显示服务名」**。落点 = **侧栏模式下服务主页整条导航栏不画，原导航栏里的按钮下沉到内容首行（右对齐），面板顶部零 chrome**。

### 19.1 唯一实现 = `lib/design/pane_chrome.dart`

- `PaneScope`（`InheritedWidget`，字段 `embedded`）+ `bool paneEmbedded(BuildContext)`：本子树是否在侧栏右侧面板里。**注入点 = `lib/features/home/presentation/home_detail_pane.dart`**，写成 `PaneScope(embedded: true, child: Navigator(...))` —— 必须包在面板 Navigator **外面**，面板内所有路由（含二级页、含 `pushReplacement` 换上去的那一页）才查得到。⚠ 只 import 不包 = 口径完全不生效（本次实测踩到：`home_detail_pane.dart` 引了 `pane_chrome.dart` 却漏了包裹，测试直接抓到）。
- `bool paneIsRoot(BuildContext context) => paneEmbedded(context) && !Navigator.of(context).canPop();` —— **只有面板首路由**吃新口径：整页模式（宫格 push / 独立页面）与面板内的二级页都照旧画完整导航栏 + 返回键。短路求值，非内嵌时不会去调 `Navigator.of`。
- `PreferredSizeWidget? paneAppBar(BuildContext context, {required Widget title, List<Widget> actions = const [], bool? centerTitle, Widget? leading, PreferredSizeWidget? bottom, double? toolbarHeight, double? titleSpacing, Color? backgroundColor, Color? surfaceTintColor})`：**服务页导航栏的唯一入口**。`paneIsRoot` → 返回 `null`（`Scaffold.appBar` 接受 null = 整条栏不画），否则返回真 `AppBar`。**参数一律原样透传、可空参数必须保持可空** —— 给 `centerTitle` 之类填默认值会盖掉主题里的 AppBar 配置，整页模式的观感就变了。
- `PaneActionRow({actions, leading, double? height = defaultHeight(44), padding})`：内嵌首路由的**内容顶部按钮行**（`Row[Expanded(leading) | Spacer, ...actions]`）；非内嵌 / 二级页 / 两者都空 → `SizedBox.shrink()`（可以直接摆在 body 首位，不必自己判模式）。
- `PaneBody({required child, actions, leading, double? height, padding})`：非内嵌 / 二级页 → **原样返回 child**（零包裹、零影响）；内嵌首路由 → `Column[PaneActionRow, Expanded(child)]`。
- **`height: null` = 由行内内容撑高**（默认 44；选课页传 `kTextTabBarHeight` 保持与整页一致；课表页必须传 null，见 19.3）。

### 19.2 21 个服务页的改法（新增页面照抄）

- **14 个「导航栏只有标题」的页** → 只把 `appBar: AppBar(...)` 换成 `appBar: paneAppBar(context, ...)`：学校地址 / 校区地图 / 第二课堂学分 / 蛟湖阅读 / 数据中心 / 宿舍电费 / 网费 / 请假 / 综合测评 / 体测 / 材料库 / 规章制度 / （教务会话失败页）。
- **7 个「导航栏里有按钮」的页** → `paneAppBar(..., actions: X)` + body 包 `PaneBody(actions: X, ...)`（**两处传同一批 widget 实例**；内嵌时只有内容里那一份会挂载，整页时只有 AppBar 那一份）：
  - 成绩容器 `lib/features/ims/menu/presentation/ims_tab_container.dart`（抽 `List<Widget> _headerActions(BuildContext context)`；`PaneBody(actions: _headerActions(context), padding: EdgeInsets.zero, child: _getPage(_currentTab))`）
  - 课表 `lib/features/ims/schedule/presentation/schedule_screen.dart`（标题槽本身就是选择器 → 走 `leading:`，见 19.3）
  - 公共查询 `lib/features/ims/public_query/presentation/public_query_screen.dart`（`_headerActions()`）
  - 选课 `lib/features/ims/course_selection/presentation/course_selection_screen.dart`（`_moreAction(context)` + **`TabBar` 也下沉重排成同一行**：`PaneActionRow(actions: [_moreAction(context)], leading: _buildTabs(), height: kTextTabBarHeight, padding: EdgeInsets.zero)`，body = `Column[PaneActionRow, Expanded(TabBarView)]`）
  - 分数估计 `lib/features/score_estimate/presentation/score_estimate_screen.dart`（`_headerActions(BuildContext context)`）
  - 校历 `lib/features/school_calendar/presentation/school_calendar_screen.dart`（`_settingsAction(context)`；`PaneActionRow` 插在 body Column 首项、`_buildTermSwitcher(context)` 之前）
  - 志愿服务时长 `lib/features/comprehensive_service/presentation/volunteer_hours_screen.dart`（`_buildExportAction()`）
- **页内二级页一律不动**：材料库文件里另有两个二级页的 `appBar: AppBar(` 是**故意保留**的（守卫按「恰好 2 处」断言）；面板内压栈的二级页（成绩 → 课程详情、材料库 → 编辑…）也照旧完整导航栏 + 返回键 —— 它们整块盖住面板，不会与任何东西叠成两条栏。这条同时兜住「服务页被当二级页再打开一次」（那时 `canPop() == true`，不会出现回不去的页面）。

### 19.3 课表页的例外：标题槽 = 学期选择器，必须喂**真实行宽**

- 内嵌写法：`PaneBody(leading: _paneTitleBar(titleBar), actions: actions, height: null, padding: EdgeInsets.zero, child: body)`。
- 病根：`ScheduleTitleBar` 内部自己按 **`MediaQuery.sizeOf(context).width − chromeWidth(152)`** 判单行还是两行（`schedule_title_bar.dart` 的 `fitsOneRow`，构造器**没有** oneRow 参数）。面板行宽 = 窗口 − 侧栏 232 − 分隔线 1 ≈ 窗口 − 233，再减两个按钮 ~96 → 窄窗口（900px 档 ≈ 571px 可用）会「判定单行却放不下」而溢出。
- 修法（`schedule_screen.dart` 的 `_paneTitleBar(Widget titleBar)`）：`LayoutBuilder` 拿真实行宽 → `MediaQuery(data: media.copyWith(size: Size(constraints.maxWidth + ScheduleTitleBar.chromeWidth, media.size.height)), child: titleBar)` → 内部那次减法正好被抵消，判定口径回到真实行宽。⚠ **`Size` 没有 `copyWith`**（编译期直接报 `undefined_method`），只能整只重建。
- 行高必须交给内容：`height: null`。写死 `ScheduleTitleBar.toolbarHeight(oneRow: …)`（按窗口宽算）会出现「行高按单行给、内容却是两行」的溢出。

### 19.4 守卫 = `test/pane_chrome_test.dart`（13 例）

- 行为三档：内嵌首路由**无 `AppBar` / 无标题 / 按钮在内容里** + `PaneActionRow` 在场；整页模式 AppBar 与从前完全一致且按钮不重复渲染；面板内二级页有 AppBar + `BackButton` 且不出现 `PaneActionRow`；`PaneScope` 之外 `paneEmbedded == false`；`leading` 与按钮同行、默认行高 `PaneActionRow.defaultHeight`。
- **课表行宽一正一反**（改动 19.3 必挂）：320px 盒子里槽位 ≈ 248（按钮 48 + 行内边距 24），够不到 `ScheduleTitleBar.rowNeed` → 喂了行宽 → 换成两行且不溢出；**同一行宽不喂 → 必溢出**（反证证明修正不可缺）。判据 = `scheduleTitleContentKey` 的渲染宽度 < `need − 40`；`need` 由测试当场用 `ScheduleTitleBar.rowNeed(...)` 量（同一个 context 的字形口径，不依赖字体注册）。
- 源码守卫：20 个服务页必须含 `paneAppBar(` 与 `design/pane_chrome.dart`；除材料库两处二级页外不得再出现 `appBar: AppBar(`；各页标题仍原样传给 `paneAppBar`（课表是 `title: titleBar`、容器是 `Text(_currentTab.title)`）；7 个带按钮页必须含 `PaneBody(`/`PaneActionRow(`；`home_detail_pane.dart` 必须含 `PaneScope(` + `embedded: true`；课表页必须含 `_paneTitleBar(` / `ScheduleTitleBar.chromeWidth` / `height: null`。

### 19.5 踩坑（都真踩过）

- **`dart analyze` 的 error 在输出头部，`Select-Object -Last N` 会漏**：本次 `paneAppBar` 压根没写进 `pane_chrome.dart`，20 处 `undefined_method` 全被截尾丢掉，白绕一轮。**改完一律 `Select-String 'error -|warning -'` 过滤全量，别只看尾**。
- 一处报「某方法不存在」时，**先确认那个方法到底有没有定义**；本次还有 `this.height = PaneActionRow.height`（实例字段当静态访问）导致整库分析失败的先例。
- 新增调用页面别忘 `import 'package:smarter_jxufe/design/pane_chrome.dart';`（本次漏了课表页与选课页，只有全量 analyze 抓到）。
