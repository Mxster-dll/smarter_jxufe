# SmarterJxUFE · 智慧er江财（Flutter 客户端）— 会话级约定

> 本文件只对本工作区 `D:\Project\Ongoing\smarter_jxufe` 有效。跨工作区通用的纪律（提问纪律、安装路径、沙箱网络经验）在 `~/.dsh/AGENTS.md`，不重复。
> 最近更新：2026-09-19（**§29 内置 AI 助手（OpenAI 兼容 8 家预设 + 多套切换 / 19 个函数调用工具覆盖成绩·课表·培养方案·学籍·公共查询·无课时间·校规检索·分数估计·综测·材料·志愿·校历·电费网费·设置 / 轻量快照 + 三条自动降级 / 只读 + 写操作二次确认 / 宫格与侧栏**第一格** + 全局悬浮球 / 设置页「AI 助手」节（排在「外观」之后）；模块自带 `lib/features/ai/README.md`）· **§29.10 回答渲染 Markdown + 空卡片守卫（用户同日二轮：「我希望支持markdown渲染，同时AI回复中偶尔会出现空卡片」）** · **§29.11 侧栏「AI 助手」紧贴「数据一览」+ 悬浮球三条真 bug（用户同日三轮：「电脑端AI助手在侧边栏放到和"数据一览"下方紧贴；现在的悬浮球点击后概率无反应，电脑端不显示悬浮球」—— Builder 的 context 在 Navigator **上方**需走全局 `navigatorKey` / 鼠标拖拽 slop 只有 1px / **`dispose()` 里改 provider 会被 Riverpod 拒发通知**）** · **§29.12 电脑端不出悬浮球（用户同日四轮：「我希望电脑端不显示悬浮球」—— `aiDesktopPlatformOn` 纯函数门控 + 桌面端设置页换成说明行；⚠ `flutter_test` 里 `defaultTargetPlatform` 恒为 `android`，要测桌面端必须 `debugDefaultTargetPlatformOverride` 且**必须在测试体内复位**）**） · 2026-09-16（**§21 小程序三服务落地（本科生成绩单 / 网络服务并入校园网 / 我的邮箱）+「网费 → 校园网」改名 + 门户应用列表侦察法** · **§19 侧栏视图的页面 chrome 口径（服务页整条导航栏不画，原按钮下沉到内容首行；面板顶部零 chrome；课表选择器喂真实行宽）** · **§18 页面转场唯一口径（去掉系统默认的中心放大 zoom；全应用横滑 + 淡入 300ms；IMS 入口闸门不再 `pushReplacement`）** · **§17.7 侧栏点击 = 右侧内嵌页面（master-detail，取消内嵌页返回键）** · **排名胶囊改 `#a/b/c`** · **logo 第二批 6 版待选 + 已装 4 个 logo 设计 skill（§17.6）** · **§17 主页布局（宫格 / 左侧导航栏）· 宫格卡片定宽等高 · 数据一览排名胶囊 · 实况窗入口迁设置页 · 应用中文名「智慧er江财」· logo 候选 A–F（第一批已被否）** · **§16 卡片风格唯一口径（全应用统一为「综测评测结果卡」形态：圆角 12 + 淡边框 + 纯白 + 无阴影；单色强调一律改主题红；主页两类卡片只统一形状保留原色）** · **§15.5 选课写入二轮加固（教务写应答是 iframe 回调页 `parent._callBack(...)` 且该端点 fire-and-forget → 写前重读核对 / 写后无条件对账刷新）** · **§4 课程截止日期管理（网课/作业/考试 · 每周/每两周自动滚动 · 本地通知提醒）** · **§12.2 设置页「教务会话」：令牌探活 + 手动刷新（探活优先、失效才换）** · **§4 课程备忘录（文字 + 图片，拷进私有目录 + 压到 1600px，单课 20 张）** · **§4 分数估计「构成占比条」（分段比例条 + 45°/135° 引出线 + 点条设比例，勿回退成滑动条）** · §3「主题纯白」口径（去 M3 seed 派生的偏红白） · §3「数据更新最小间隔 1 分钟」（畅想之星） · §15.4 选课检索栏与教务原页面 8 个控件逐一对齐（类别/属性 = 客户端过滤） · §15 教务「选课」口径（网上选课 / 选课结果 / 退选 + DES 加密移植 + 失效页 UTF-8 解码口径 + 学号 `xh` 口径核实） · §14.7 公共查询「账号默认预填」+ 卡片纯白 · §14 教务「公共查询」口径（教师/班级/教室/课程课表 + 多班对照找无课时间） · §13 Fluent Design 基础层 · §12.1 统一登录（CAS）按账号持久化 · §12 IMS 全局会话口径 · §11 首页顶栏 + 账号头像口径 · §9「当下学期」唯一口径 · §10 桌面小组件）。

## 1. 本机 Flutter/Dart 命令（重要：`flutter.bat` / `dart.bat` 会卡死）

包装脚本内部会再起一层 PowerShell，实测 120–180s 无输出。**一律直连**：

```powershell
$dart = 'D:\Program\flutter\bin\cache\dart-sdk\bin\dart.exe'
$snap = 'D:\Program\flutter\bin\cache\flutter_tools.snapshot'
$env:FLUTTER_ROOT='D:\Program\flutter'; $env:FLUTTER_SUPPRESS_ANALYTICS='true'; $env:FLUTTER_ALREADY_LOCKED='true'
```

| 目的 | 命令 |
|---|---|
| 静态检查 | `& $dart --disable-analytics analyze <paths...>` |
| 测试 | `& $dart $snap test test\xxx_test.dart` |
| 格式化 | `& $dart format <paths>` |

- 各命令首次运行会隐式 `pub get`，输出几百行 `Resolving dependencies` 噪音，可忽略；`pubspec.lock` 无实质改动。
- `format` 末尾会因遥测写 `%APPDATA%\.dart-tool` 被拒（`PathAccessException` errno 5）而 **exit 1**，格式已生效，非故障。
- ⚠ **但不要对整文件跑 `dart format`（2026-09-16 实测）**：本机 SDK 是 **Dart 3.10.7**，`dart format` 已默认**新版 tall style**，而本仓库代码是**旧短样式** → 对任一文件跑一次都会顺带重排大量**你没碰过**的代码（实测 9 个文件：`network_common.dart` 的 `networkBadge` `=> Container(` 体缩进、`read_credit_ui.dart` 的 `readCreditPartColor` switch 表达式、`my_mail_screen.dart` 的 `await ref.read(...).catchError(...)` …），在并行工作流下会产生无法审阅的巨大 diff。**改完手写折行后要核对格式，用只读的 `dart format --output=show <file>` 比对你自己新增的那几行**，别让 format 写盘。
- 长命令一律 `run_in_background: true` + 大超时；`Select-Object -Last N` 截尾。
- ⚠ **全量测试一律加 `--concurrency=1`（2026-09-17 实测）**：默认并发（本机 8 路）下会 flake —— 同一套代码两次全量跑分别得到 **1 例 / 10 例失败**（`materials_wizard_test` 的 `tap()` 因底部弹层超出 800×600 视口而 hit-test 未命中；`qa_rules_visual_test` 的 9 张 golden + `read_credit_progress_test` 的「无布局异常」），而这几个文件**单独跑全部通过**（4/4、27/27）。串行 `--concurrency=1` 一次全绿（**1425 例、exit 0、02:28**）。所以：并发失败先单跑复核，别急着当回归；要可信结论就串行跑。
- **沙箱限制**：直连 `dart analyze` 在只读 / workspace-write 沙箱下**必被拒**（`CreateFile failed 5` + `ProcessException: 拒绝访问`——analysis_server 子进程走命名管道），需一次性 `danger-full-access`。**`flutter test` 同样会被拒**（flutter_tools 启动时用管道读 git：`CreateFile failed 5` / `Flutter tool cannot access … git … log HEAD`）→ 也需 `danger-full-access`，或干脆改跑 `dart test`（**只有 `dart test` 真正不受此限**）。`Get-CimInstance` 沙箱内不可用（「无法从客户端中访问 CIM 资源」），查进程改用 `Get-Process`。

### 1.1 `flutter run -d windows` 的非幂等坑

- CMake 里 `flutter_windows.dll.rule` / `flutter_assemble.rule` 每次 MSBuild 必跑 `tool_backend.bat`，而 `debug_bundle_windows-x64_assets` 对**已存在**的 `build\flutter_assets` 用 createNew 拷贝 → `PathExistsException errno 183`「当文件已存在时无法创建该文件」→ **MSB8066**。
  **对策：每次 run 前先 `Remove-Item build\flutter_assets -Recurse -Force`**（`flutter clean` 也可，但要全量重编）。
- `LNK1168`（无法写入 exe）= 旧的 `smarter_jxufe.exe` 还在跑 → `Stop-Process` 后重试。
- **`flutter test` 与运行中的 `flutter run` 争用构建目录 → 测试挂死**。跑测试前先停掉 run 会话（曾因此 kill 掉一个后台 job）。
- **`flutter test` 的构建产物同样非幂等**：`build\unit_test_assets\NativeAssetsManifest.json` 已存在时会用 createNew 拷贝 → `PathExistsException: Cannot copy file to '…\build\unit_test_assets\NativeAssetsManifest.json' … errno 183` + `Oops; flutter has exited unexpectedly`（并落一份 `flutter_<NN>.log`），与上面 `flutter_assets` 同源。**对策：跑测试前 `Remove-Item build\unit_test_assets -Recurse -Force -EA SilentlyContinue`**（2026-09-11 实测）。

### 1.2 重启 run 会话的固定套路（分离进程，避免作业系统回收）

```powershell
Get-Process dart,smarter_jxufe -EA SilentlyContinue | Stop-Process -Force
Start-Sleep 2
Remove-Item 'D:\Project\Ongoing\smarter_jxufe\build\flutter_assets' -Recurse -Force -EA SilentlyContinue
# env 见上；日志 %TEMP%\ge_flutter_run_windows.log / .err.log
Start-Process $dart -ArgumentList $snap,'run','-d','windows' -WorkingDirectory <repo> -WindowStyle Hidden `
  -RedirectStandardOutput $log -RedirectStandardError $err
# 轮询日志出现 'Flutter run key commands' 即 READY；正则抓 http://127\.0\.0\.1:\d+/[A-Za-z0-9_=-]+/
```

- 失败关键字：`Build process failed|LNK1168|MSB8066|Error launching`。
- 分离会话**没有 stdin 通道**，发不了 `r`/`R`；改代码 = 重启会话（约 1–3 分钟）。
- 该 dart 进程可能自行退出（日志留 `Lost connection to device.`），此时 VM Service 端口失效、但 app 进程仍活着 → 重新走本套路。

## 2. VM Service 探针（不靠 UI 就能验证真实数据路径）

python `websocket-client`（`D:\Program\Python\Python313`）脚本在 `D:\Temp\vmprobe\`：`ge_probe.py`（成绩缓存）、`ge_courses.py`（课程）、`ge_steps_probe.py`（学籍→学院→专业→培养方案逐步链路）、`ge_rc_probe.py`/`ge_calc_probe.py`（真实容器 + 端到端复算）。用法：

```
python ge_calc_probe.py "ws://127.0.0.1:<port>/<token>=/ws"
```

- 端口每次重启都变，从 run 日志抓；app 的 `print/debugPrint` **只进 run 日志**。
- `evaluate` 的 expression 必须是**单行**（多行会报 `Can't find '}' to match '{'`），用 `(() { ... })()` 包裹；`late void Function(...) f;` 才能写递归闭包。
- **库作用域只含该库直接 import 的名字**：`studentInfoRepositoryProvider` 只在 `ge_providers.dart` 可见，`geCalc/geWeightedSummary` 只在 `ge_engine.dart`/`score_estimate_screen.dart` 可见 → 按需选 target library。
- 取真实 `ProviderContainer`：运行时树是 `RootWidget → View → RawView → … → UncontrolledProviderScope`（约 14 层）。`ProviderScope.containerOf(rootElement)` 会 `Bad state: No ProviderScope found`（异常被 VM 当成**返回值**，`evaluate` 仍报 OK，别被骗）；要沿 `visitChildren` 向下走到能 `containerOf` 成功的那层。
- 新建 `ProviderContainer()` 也能验证纯本地链路（学籍/学院/专业/培养方案缓存命中时**零网络**）。

### 2.1 离线读真实 Hive box（app 运行中目录被锁）

把 `app_data\<box>.hive` 复制到临时目录（如 `D:\Temp\gecurr`、`D:\Temp\gecache`），在 `flutter test` 里 `Hive.init(path)` + **手工 registerAdapter**（`AssessmentMethod/CourseImportance/CourseNature/CourseRequirement/CreditHour/Course/Curriculum/Major/College/FunctionType`，见 `lib/core/storage/hive_initializer.dart`）。临时诊断测试**用完即删**（`test/tmp_*.dart`）。

## 3. 代码约定

- **feature-first**：`lib/features/<模块>/{data,domain,presentation}`；新模块数据层可跨 feature import 既有 domain（已有先例）。
- **模型**：手写 immutable 类 + `copyWith` + `toJson/fromJson`（本模块不用 freezed）；Hive 存 `Box<String>` 单 key JSON 整表读写，损坏/缺字段一律容错（`as num?` + clamp + 默认值），**不要**让旧数据导致崩溃。
- **providers**：`FutureProvider` 链 + `Hive.openBox`（lazy，无需改 `main.dart`）；已有 riverpod_generator 生成的 provider 用 `ref.watch(x.future)`。
- **页面数据自动刷新（2026-09-14 立，用户要求）**：凡是展示**缓存型 `FutureProvider`** 数据的页面，必须挂 `lib/core/navigation/page_auto_refresh.dart` 的 `PageAutoRefresher(onRefresh: …)`（`start()` in `initState` + `subscribeRoute(context)` in `didChangeDependencies` + `dispose()`；`appRouteObserver` 已在 `lib/main.dart` 的 `MaterialApp.navigatorObservers` 注册）→ **首次进入 / 从子页面返回（`RouteAware.didPopNext`）/ App 回前台**都自动重取，用户不必再手点按钮或重进页面。要刷的 provider 一律在页面自己的 `_refresh…()` 里列全（如 `jh_read_screen.dart` 的 `_refreshAll()`，**注意顺序**：被 `ref.read(x.future)` 依赖的要先失效）；用 `invalidateIfLoaded(ref, provider)` 而不是裸 `ref.invalidate` —— 它会跳过「首次加载尚未完成」，否则 `build` 刚发出的请求会被立刻重发一次。它是**组合件不是 mixin**（`RouteAware` / `WidgetsBindingObserver` 是接口形态，mixin 里的 `this` 传不进 `subscribe` / `addObserver`，实测 `argument_type_not_assignable`）。守卫：`test/cxstar_auto_refresh_test.dart`（首次进入只取一次数 / 再进入必须重取 / 从子页面返回必须重取 / 回前台必须重取 / 阅读器每分钟刷新 / `PageAutoRefresher` 通用机制 / 真实流程镜像）。
  - **能 `await push` 就 `await push`**（2026-09-14 二轮，用户：「从阅读页点击返回畅想之星页面也要刷新」）：若一个页面的子页面入口都在本页代码里，优先用 `Future<void> _openChild(Widget page)` = `await Navigator.push(...)` → 返回后立即刷新，**并撤掉本页的 `subscribeRoute`** —— 两条路都留着会重复刷新（`ref.invalidate` 不同步生效，「正在加载」拦不住同一 tick 的第二次触发）。路由观察者留给「push 站点散落在子 widget 里、拿不到返回时机」的页面（如 `jh_read_screen.dart`）。畅想之星页另有**结算补刷** `const List<Duration> cxstarReturnSettleDelays = [10s, 45s, 150s]`（累计，`_settleScheduled` 防叠加）：平台统计批量结算，返回那一瞬间可能还是旧值。
  - **刷新必须看得见**：重取期间 `AsyncValue.when` 会继续显示旧值（`skipLoadingOnRefresh`），而一次取数往往是 2–3 个串行请求 → 用户会认为「没刷新」。展示缓存数据的卡片要给出「正在更新…」与「更新于 HH:mm:ss」（`ref.listenManual` 在取到新数据时打时间戳），否则分不清「没刷新」与「刷新了但服务端还没结算」。畅想之星统计卡与阅读器底栏都是这么做的。
  - **「数据更新」最小间隔 1 分钟（2026-09-14 二轮 · 用户原话「数据更新设置一个最小间隔（1min)」，并明确「仅限畅想之星」）**：闸门 = `lib/features/cxstar/data/providers/cxstar_refresh_gate_provider.dart` 的 `const Duration cxstarMinRefreshInterval = Duration(minutes: 1)` + `class CxstarRefreshGate{DateTime? lastUpdatedAt; bool get allowsAutoRefresh; void markUpdated()}` + `cxstarRefreshGateProvider`（**非 autoDispose**：窗口必须跨越页面重建 —— 「畅想之星 → 返回 → 再进入」每次都是新 State，记在 State 上等于没记账；测试里闸门实例必须在 `app()` **之外**创建，否则 ProviderScope 重建会换新实例、窗口被清空）。
    - **窗口起点 = 上一次真的取到新数据的时刻**，即统计卡那行「统计更新于 HH:mm:ss」的同源时刻（`cxstar_screen.dart` 的 `ref.listenManual<AsyncValue<CxstarOverview>>` 里 `markUpdated()` 与 `_updatedAt = DateTime.now()` 同时落，界面显示与节流口径不会互相矛盾）。**刻意按「取到新数据」而不是「发出请求」记账**：请求在飞 / 失败时不该封锁窗口，否则一次网络抖动会让人一分钟内连重试都做不了。
    - **受限**（整组一起跳过）：`_autoRefreshAll()`（首次进入 / 从子页面返回 / 回前台 → `cxstarOverviewProvider` + `readCreditDetailProvider(ReadCreditKind.classic)`）与 `_refreshOverview({bool force = false})` 的非 force 调用。
    - **不受限**：手动下拉（`RefreshIndicator` → `_refreshAll()`）、会话变更（统一认证 / 手工令牌 / 清除令牌）、错误卡「重试」、以及**结算补刷**（`cxstarReturnSettleDelays` 的 10s/45s/150s 改走 `_refreshOverview(force: true)`，用户裁定「保持不受限」）。
    - 后果（有意为之）：「从阅读器 / 书架返回」在 1 分钟窗口内**不再立即重取**，新值由 10 秒后的结算补刷带到（用户 2026-09-14 的「返回后要刷新」仍被守卫住，只是走结算那条路）。
    - **仅限畅想之星**：`lib/core/navigation/page_auto_refresh.dart`（`PageAutoRefresher` / `invalidateIfLoaded`）**没动**，蛟湖阅读页的 `_refreshAll()` 行为不变。
    - 守卫 = `test/cxstar_auto_refresh_test.dart` 的「再次进入 / 从子页面返回 / 手动下拉 / 回前台」四例 + 真实流程镜像（用 `_FakeClock` 注入时钟才能推进 1 分钟窗口：真实 `DateTime.now()` 在 widget 测试里推不动）。
- **色彩**：一律登记在 `lib/design/feature_palette.dart`（如 `scoreEstimate = Color(0xFF536DFE)`）。
- **主题「纯白」口径（2026-09-14 立）**：`lib/main.dart` 的 `ColorScheme.fromSeed(seedColor: 校红 #C3282E)` 会按种子色相派生**整个中性色系** → 白色实际是 `#FFF8F7`（R−B = +8，1920×1080 截图像素实测），整页「白里透红」。已在 `.copyWith()` 里把白色系覆写为中性灰白（R = G = B）：`surface` / `surfaceContainerLowest` = `#FFFFFF`、`surfaceContainerLow` = `#FAFAFA`、`surfaceContainer` = `#F5F5F5`、`surfaceContainerHigh` = `#F0F0F0`、`surfaceContainerHighest` = `#EBEBEB`；**`surfaceTint` 必须设白**（它默认取 primary 系，AppBar / Card 抬起时会再染一层红）。新增任何「白色」都用中性色值，**不要**从 primary 派生；文字色（`onSurface` / `onSurfaceVariant` / `outline`）仍是种子的暖灰 —— 这是用户 2026-09-14 裁定「只改白色系」的结果，别顺手改。
- **首页服务目录（2026-09-15 重构）**：唯一条目表 = `lib/features/home/presentation/home_service_catalog.dart` 的 `homeServiceEntries({required void Function(Widget) push})` → `List<HomeServiceEntry{icon, title, subtitle, group, accent, onTap}>`，**强调色随条目走**；宫格渲染 = `presentation/home_service_grid.dart`、左侧导航栏渲染 = `presentation/home_sidebar.dart`，两者共用这一份。分组 = `HomeServiceGroup{ims '教务系统', study '学习与测评', campus '校园生活', info '数据与信息'}`（**只影响侧栏排版**，宫格平铺不分节）。
  ⚠ **旧铁律已作废**：从前条目写在 `home_screen.dart` 的私有 `_items(context)`、强调色存在顶层 `const _tileColors`，两者**按索引对齐**（增删磁贴必须同步增删色表）。现在只有一份目录、颜色随条目，**不可能再错位**；增删入口只动 catalog 一处，并同步 `test/home_tile_alignment_test.dart` 的条目数（现 **26** 条 —— 2026-09-19 新增「AI 助手」并排在**第一格**）与本文件。详见 §17。
- **UI 风格基准 = 首页宫格页**：功能卡 `Card(elevation: 0, shape: appCardShape(context))` + `Clip.antiAlias`；节标题用 `geCardTitle`（3px 竖条 + 13.5 w600，`accent` 默认主题红）；列表 `padding: EdgeInsets.fromLTRB(24, …, 24, 48~96)`；卡间 12；图标 22–24 用 **Material Icons**（不用 emoji）。共享件在 `lib/features/score_estimate/presentation/ge_common.dart`（`geCardShape`——已转发到 `appCardShape` / `geCardTitle` / `geFmt` / `GeModeBadge`）；**卡片形状与强调色的唯一口径 = `lib/design/app_card.dart`（见 §16）**，别在页面里再拼一套 `BorderRadius.circular(…)` + `BorderSide(…)`。
- 图标按钮用 `IconButton(tooltip: …)`；`AlertDialog` 用 M3 默认样式 + `icon:`。
- **交互必须触摸可用**：手势**不得只挂在 `MouseRegion` hover 开关上**——触摸设备永不产生 hover，被 hover 门控的手势等于没注册（`lib/shared/widgets/academic_year_picker.dart` 曾因此在手机上整条划不动，且同一开关还控制着透明度）。拖拽一律用真实指针事件（`onHorizontalDragStart/Update/End/Cancel`）驱动状态，hover 只做增强。
- **全局偏好入口 = `lib/features/settings/presentation/settings_screen.dart`**（首页右上角齿轮进入）。新增用户偏好一律收拢到这里，不要再新增 feature-local 设置弹层（校历的三个显示开关已于 2026-09-11 迁入本页「校历」节，校历页 AppBar 齿轮只做跳转）。持久化照 `lib/features/campus_address/data/my_campus_prefs.dart`：Hive `Box<String>` 单 key + `ChangeNotifier` + `ChangeNotifierProvider`（改动需即时反映到多个页面时用此模式，**别用 FutureProvider**——中间有异步空窗，页面会先闪一次旧值）。
  - 已收拢的偏好（新增偏好照此追加，别另开弹层）：**入馆教育答题模式** = `lib/features/library_edu/data/tsgxs_prefs.dart`（box `tsgxsPrefs` / key `answerMode`，存 `TsgxsAnswerMode.name`），**唯一切换入口 = 设置页「入馆教育」节**；`tsgxs_exam_screen.dart` 与 `tsgxs_chapter_screen.dart` 只读该偏好（用户 2026-09-11 裁定：「模式的切换不应该显示在任何页面，只能显示在设置页」）——别再往页面里加模式切换控件或 `initialMode` 参数。
  - **标题栏右上角永远有设置按钮（用户 2026-09-16 裁定）**：唯一入口 = `lib/features/settings/presentation/settings_entry.dart` 的 `SettingsActionButton`（紧凑款：`iconSize 18` + `visualDensity compact` + `constraints 30×30` → 实测点击区宽 **40**，与课表 `ScheduleTitleBar.actionWidth` 同口径），**由 `lib/design/pane_chrome.dart` 的 `paneAppBar` 自动追加到 `actions` 末尾** —— 所以走 `paneAppBar` 的服务页（宫格/侧栏能直达的那 20 多个）都自动有，新页面不必自己加。二级页（畅想之星阅读器 / 入馆教育答题页 / 课程详情）用裸 `AppBar`，**没有**设置按钮（用户拍板「所有服务主页、二级页不加」）。
    - **只显示本节**：页面用 `paneAppBar(context, …, settingsSections: [SettingsSection.calendar])` 声明；枚举 = `lib/features/settings/domain/settings_section.dart` 的 `SettingsSection`（**appearance 外观（深色模式，2026-09-16 加，见 §22）** / **aiAssistant AI 助手（2026-09-19 加，排在 appearance 之后，见「内置 AI 助手」节）** / campus 校区 / scope 生效范围 / homeLayout 主页布局 / calendar 校历 / **schedule 课表** / libraryEdu 入馆教育 / platformGuid 平台标识 / liveClass 上课实况窗 / imsSession 教务会话 / **cloudSync 云同步** / homeWidget 桌面小组件 —— 共 **13** 个，顺序即完整设置页的分节顺序），`SettingsScreen(sections: […])` 按它过滤分节（`sections.length == 1` 时 AppBar 标题变成节名）。**空列表 = 完整设置页**（主页、以及没有对应节的页面：综测 / 材料库 / 体测 / 邮箱 / 规章制度 / 志愿者 / 竞赛 / 第二课堂 / 电费）。
    - 已声明映射：校历→calendar；蛟湖阅读→libraryEdu；校园网 + 请假 + 数据中台→platformGuid；选课 / 公共查询 / 分数估计 / IMS 容器（培养方案·成绩·毕业学分·我的）→imsSession；课表→imsSession + liveClass；学校地址 + 校区地图→campus。
    - ⚠ **课表页的行宽记账要 +1**：`schedule_screen.dart` 里 `final barActionCount = actions.length + 1;`（设置按钮由 chrome 追加），少算一个会把标题栏可用宽度多算 40px、该换行时不换行。
    - 守卫 = `test/settings_entry_test.dart`（九节 label；只给一节/多节/不传三档渲染与标题；点按钮进过滤页；源码守卫：chrome 自动注入 + 12 个页面的 `settingsSections` 映射 + 课表 `+1` + 校历页不再自带 `_settingsAction`）。
    - ⚠ **齿轮注入 = 两处（2026-09-17 修订；此前只允许 `paneAppBar` 一处）**：① `paneAppBar`（整页模式，无条件追加到 `actions` 末尾）；② `PaneActionRow`（侧栏内嵌模式，**仅当页面声明了 `settingsSections` 且本行本来就有内容**时在行尾补一个）。用户 2026-09-16 二轮原话「你的设置添加导致不少页面凭空多了一个标题栏，我希望下沉到内容里」→ 红线保留为「**空行不许塞齿轮**」：注入必须排在那道 `actions.isEmpty && leading == null` 早退**之后**，`PaneActionRow` 在空行时仍**整行不画**。用户 2026-09-17「课表页的设置按钮不见了」：内嵌模式不画导航栏、而齿轮从前只由 `paneAppBar` 注入 → 课表页的入口整个消失；现由课表页（**唯一**给 `PaneBody` 传 `settingsSections` 的页面）在**既有**工具条行尾补一个，不新增任何横条。清单唯一出处 = `lib/features/ims/schedule/presentation/schedule_screen.dart` 的 `const List<SettingsSection> scheduleSettingsSections`（整页导航栏与内嵌工具条共用，行宽记账 `barActionCount = actions.length + 1` 两档都恰好 +1）。守卫 = `test/pane_chrome_test.dart`（内嵌有/无声明、空行零尺寸、整页不重复渲染）+ `test/settings_entry_test.dart`（注入恰好两处 + 课表两条链路都挂上了）。**桌面端设置入口改到左侧导航栏底部固定区**（用户同日：「桌面端把标题栏里的头像和设置都应该改到侧边导航栏，设置在下，头像在上，并且这两个是固定在底部不浮动的」）：`home_sidebar.dart` 的 `HomeSidebar(footer:)` + `HomeSidebarFooterRow`（`homeSidebarProfileKey` 头像行在上 / `homeSidebarSettingsKey` 设置行在下，行高 `footerRowHeight`=46），由 `home_screen.dart` 的 `_buildSidebarBody` 装配（`AccountAvatar(radius: 15)` → `StudentInfoScreen`；齿轮 → `SettingsScreen`）；**该区在滚动区之外 → 服务列表再长也压不到它**；顶栏 `_buildTopBar(..., showAccountActions: !useSidebar)` 在侧栏视图下只留品牌。守卫 = `test/home_sidebar_test.dart`「底部固定区」组（顺序/行高/滚不动/回调/未传 footer 不画）、`test/pane_chrome_test.dart`（下沉行不得注入 + 空行零尺寸 + 校历页已从「带按钮页」表移除）。

### 3.1 ⚠️ AlertDialog 里禁止放 ListView / GridView / CustomScrollView

`AlertDialog` 恒用 `IntrinsicWidth` 包裹内容，viewport 类组件不支持 intrinsic 尺寸：

```
RenderViewport does not support returning intrinsic dimensions.
Failed assertion: '!semantics.parentDataDirty': is not true.   ← 随后每帧刷屏
```

表现为弹窗永不渲染 → `await showDialog` 永不返回 → 调用方 loading 标志永远为 true（曾导致「从课表导入」**一直转圈**，误判成网络问题）。
**替代**：`AlertDialog(scrollable: true, content: Column(children: [ for (...) ListTile(dense: true, contentPadding: EdgeInsets.zero, …) ])))`，行直接展开，超出交给外层滚动。

## 4. 分数估计模块 · 计分与加权口径（领域约定，改动前先看这里）

- **分项三种模式**：`GePart{mode, target, current, score, cap}`
  - `up` 正计数 = 已完成次数（可超 target，得分封顶）；
  - `down` 负计数 = **剩余次数**（target = 总事件数，如全学期 16 次课，缺勤一次 −1）；
  - `score` 直接分数 = 老师直接给分：`target` 是**该项满分**、`score` 是**实际得分**（可小数），得分率 = 得分/满分；满分填成与 `cap` 相同即「直接填得分」。`current` 在 score 模式恒为 0，`score` 在计数模式恒为 0。
- 折算：`r = clamp(当前值 / 目标值, 0, 1)`（当前值：计数模式取 `current`，score 模式取 `score`），`得分 = r × cap`；平时满分 `C = Σcap`，`S = Σ得分`，`M = S/C × 100`；总评 `= M × dp% + F × fp%`（`fp = 100 − dp`）。
- 目标反推：`need = (goal − M×dp/100) / (fp/100)`，四态 `reached / ok / recoverByDaily / impossible`；「可达上限」= 还能再挣的分项（**正计数 + 直接分数项**：`p.mode != GePartMode.down` 时 `gainableCap += (1−r)·cap`），**负计数已扣减不回**（用户 2026-09-10 裁定：直接分数项未拿满的部分算可补）。界面层一律用 `gePartRatio/gePartScore`，别重算。

- **总加权平均**（`ge_engine.dart`）：`GeWeightItem{name, score, credits, fromGrades}`；`geWeightedSummary(items)`（credits ≤ 0 跳过、score clamp 0..100）；`contribution = score × credit / Σcredit`，各课贡献之和 = 平均。
- **`geMergeWeightItems({priorItems, courses})` = 合计口径**：教务已出成绩**全量计入**（不是"同名替换"）+ 本模块课程同名时跳过（以真实成绩为准）+ 未填期末 / 学分为 0 不计入。曾因只做同名替换，导致汇总卡恒显示「教务已出 0 门」——**用户看的是构成行的门数**。
- **汇总卡 = 唯一实现**（`data/ge_summary.dart` + `presentation/ge_summary_card.dart`）：界面层一律调 `geSummarize({prior, courses, index})` → `GeSummaryData{summary, pendingCount}`（内部已含 `geMergeWeightItems` + `geEffectiveCredits`），再渲染 `GeWeightedSummaryCard(...)`。**列表页顶部与课程详情页顶部共用同一函数与同一组件**，禁止在界面层各自拼口径（详情页传入的 courses 用 `_summaryCourses()` 把本课替换成编辑中的最新状态 → 即改即算）。
- **学分来源 = 本专业培养方案优先**（`geEffectiveCredits`，`ge_curriculum.dart`）：先按 `courseCode` 再按课程名（忽略空白/大小写）匹配；未命中回退课程自身 `credits`。
  **绝不能跨专业方案按名搜索**：同名课学分不同（`计算机网络` 软件工程 2.0 / 计科 4.0）。
- 排除名单复用在 `lib/features/ims/grades/domain/grades_exclusions.dart`（`kExcludedGradeCourses`：军事训练、创新创业实践活动、毕业设计、毕业论文），成绩页与本模块共用。
- **测试构造注意**：无 `parts` 的课平时占比默认 30% → 总评 ≠ 期末分；要"总评 = 期末分"必须显式 `dailyPercent: 0`。
- 课程学分默认 1；旧 JSON 无 `credits`/`courseCode` 字段 → 兜底 1 / 空串。

- **构成占比条（2026-09-15 重做，用户原话「平时分比例不要直接一个滑动条，而是只显示一个条……平时分断开为若干段……可以点击设置」——勿回退成滑动条）**：唯一实现 = `lib/features/score_estimate/presentation/ge_ratio_bar.dart`。
  - `geRatioSegments({parts, dailyPercent})`：平时段按各分项 `cap` 占比切分（**跳过 cap ≤ 0 的分项**，`partIndex` 保留原下标）；平时占比 > 0 但无可用分项 → 一整段「平时 X% · 待配置分项」（`FeaturePalette.scoreEstimatePending` 浅灰）；平时占比 = 0 / 期末占比 = 0 时对应段不出现（各段 fraction 之和恒为 1）。
  - 配色：平时 = `FeaturePalette.scoreEstimate`（靛蓝）、期末 = `FeaturePalette.scoreEstimateFinal`（新增，蓝灰 `#90A4AE`）；段间断口 `geBarGap = 2`；高度 `geRatioBarHeight = 18`（详情页）/ `geRatioBarThinHeight = 6`（列表页细条，gap 1.5）。
  - **⚠ 分段必须 `Row(crossAxisAlignment: CrossAxisAlignment.stretch)`**：Row 默认 `center` 会给「无子 `ColoredBox`」松高度约束 → 高度塌成 0、**整条隐形**（旧版那条 8px 双色条正是这个写法，等于从未画出来过）。守卫 = `test/ge_ratio_bar_test.dart`「分段真的画出来」（断言每个 `ColoredBox` 高度 = 18、宽度按 flex 占比、两色分明）。
  - 详情页 `GeRatioChart` = 条 + **45°/135° 引出线标注**：`geCalloutLayout({segments, labelWidths, width, barBottom})` 逐段试 1..`geCalloutMaxLevel`(=4，另加 `geCalloutExtraLevel`(=2) 兜底) 级；每级先试「段中心在条左半 → 右下 45°，右半 → 左下 135°」再试反向，取第一个不越界且与已放置标注（`geCalloutMinGap = 5`）不相交的方案。**竖直位移由水平位移导出 → 斜线恒为严格 45°/135°**（标注近端顶角 = 斜线终点，标注行高 `geCalloutLabelHeight = 14`、字号 11；量宽必须用 `DefaultTextStyle.of(context).style.merge(style)` 与实际渲染一致）。段中心另画一个 1.6px 圆点标示归属。
  - **点条 = 唯一设置入口**：`showGeRatioSheet(...)` 出底部弹层（滑动条 10% 步进 + 手输框 + 预设 chip `geRatioPresets = [0,20,30,40,50,60]`），**每次改动立即 `onChanged` 写库**。详情页卡片上的滑动条与手输框已整体删除（`course_detail_screen.dart` 的 `_dpCtrl` / `_dpFocus` / `_applyDailyText` 已删，手输能力移进弹层）；列表页 `_CourseCard` 在说明文字下加同款细条（`GeRatioBar(height: geRatioBarThinHeight, gap: 1.5)`，点行进详情）。
  - ⚠ **仍保留滑动条的只有「课程信息」弹窗** `ge_dialogs.dart` 的 `showGeCourseDialog`（改名/占比/学分/备注一起改的表单，未动）。
  - 守卫 = `test/ge_ratio_bar_test.dart`（19 例：切分 / 45° 不变式 / 不重叠不出界 / 依据相对位置择向 / 同输入确定性 / 12 分项极端情形 / 弹层交互）。离屏看真实的办法：临时测试里 `FontLoader` 载 `C:\Windows\Fonts\simhei.ttf` + `RepaintBoundary.toImage`（**必须包 `tester.runAsync`**，否则 PNG 编码在假异步区永不完成 → 测试挂死），再按行量色段核对比例。
- **课程备忘录（2026-09-15 加 · 用户原话「我希望每门课程可以添加一个备忘录功能，允许上传图片」）**：范围**只在成绩估计页**（用户同日裁定「课表是我发错了，不改」——课表页别动）。唯一实现 = `lib/features/score_estimate/`。
  - 形态 = **单块**：一门课一个备忘录 = 一段文字 + 图片网格（详情页「备忘录」卡，排在「目标反推」卡之后，`presentation/ge_memo_card.dart` 的 `GeMemoCard`）。列表页有备忘的课在课程名后出 `GeMemoBadge` 小图标（tooltip = `geMemoSummary` → `备忘录：文字 + 2 张图片`）。看大图 = `showGeMemoViewer`（PageView + InteractiveViewer + 删除按钮）。
  - 存储：`GeCourse.memo`（`domain/ge_memo.dart` 的 `GeMemo{text, images}` + `GeMemoImage{fileName, addedAt, bytes, width, height}`）随课程 JSON 进 Hive（`GeStore.saveCourses` 整表读写）；**图片本体在应用私有目录** `ge_memos/<账号>/<课程 id>/<uuid>.<ext>`（`data/ge_memo_store.dart` 的 `GeMemoStore`，目录构造注入可单测），**JSON 里只存文件名**。旧数据没有 `memo` 键 → `GeMemo.empty`。
  - 导入链 = `importGeMemoImages({store, account, courseId, sources, remainingSlots, maxBytes, compress})`（`data/ge_memo_importer.dart`）：**先查体积再读内容**（超限文件不进内存）→ `geMemoCompressImage` → `GeMemoStore.save`。压缩口径：最长边压到 `geMemoMaxEdge = 1600`；**已经 ≤1600 且 ≤ `geMemoKeepMaxBytes`(1536KB) 的图字节原样保留**（不二次编码）；带 alpha 保 PNG、其余 JPEG q88；重编码反而更大 → 回退原图；非图片统一抛 `FormatException`（`decodeImage` 对垃圾字节能抛 `RangeError`，必须 try/catch 转成 `FormatException`，否则「不是图片」会被记成「保存失败」）。
  - 限额与失败原因：单课 `geMemoMaxImages = 20` 张（满了禁用添加入口）、单张导入上限 `geMemoImportMaxBytes = 20MB`；跳过原因 = `GeMemoSkipReason{tooLarge, undecodable, overLimit, failed}`，SnackBar 用 `GeMemoImportResult.summary` + 前 3 条 `geMemoSkipText`。
  - 选图：`GeMemoPicker`（provider `geMemoPickerProvider`，测试 override 假实现）——移动端相册/拍照走 image_picker，文件多选走 **`FilePicker.pickFiles(...)` 静态调用**（file_picker v11 **没有** `.platform`，照抄 `materials_screen.dart:545`）；桌面不出「拍照」（`geMemoMobilePlatformOn(defaultTargetPlatform.name)`，**要 `import 'package:flutter/foundation.dart'`**——material.dart 不导出 `defaultTargetPlatform`）。
  - 删除：缩略图与查看器的删除**都要过 `geConfirmDelete`**；**删除课程必须连带清图片**（`score_estimate_screen.dart` 的 `_deleteCourse` → `_removeMemoFiles(c)` → `GeMemoStore.removeAllOfCourse`），否则私有目录留孤儿文件。从详情页返回后列表 `_reload()` 自带出新图标。
  - JSON 容错：取数一律走 `geMemoIntOf/geMemoStringOf`，**不要写 `as num?`**——脏数据会抛 `type 'String' is not a subtype of type 'num?'`（实测踩到）。
  - 守卫 = `test/ge_memo_test.dart`（34 例：模型容错/容量/摘要、路径清洗与体积文案、Store 落盘-隔离-清理、压缩四分支（大图缩边 / 小图原样 / alpha 保 PNG / 非图片抛错）、导入四种跳过原因与数量上限、卡片渲染-取图弹层-确认删除-查看器-满额与 busy 禁用）。

- **课程截止日期管理（2026-09-15 加 · 用户原话「我希望还可以增加一个截止日期管理，用于管理课程的网课、作业截止时间」）**：用户拍板 5 项 = ①入口**只有课程详情页一张卡**（列表页 / 首页都不加入口）；②数据**手工录入 + 本地保存（随账号隔离）**；③**本地通知**提醒，默认**提前 1 天 + 提前 1 小时**、可逐条关；④支持**每周 / 每两周重复**（自动滚到下一次）；⑤字段 = 标题 + 类型 + 截止时间 + 关联课程 + 备注 + 完成勾选（入口在课程页里，故「关联课程」就是本门课：记录挂在 `GeCourse.deadlines` 下）。
  - 模型 = `domain/ge_deadline.dart`：`GeDeadline{id,title,kind,dueAt,repeat,note,doneAt,remind,createdAt}` + `enum GeDeadlineKind{onlineCourse,homework,exam,other}`（label 网课/作业/考试/其它）+ `enum GeDeadlineRepeat{none,weekly,biweekly}`（`interval` 7 / 14 天）。**没有独立 Hive box**：随课程 JSON 进 `score_estimate_<账号>`（旧数据无 `deadlines` 键 → 空列表），因此天然账号隔离、删课即随之消失。
  - **重复语义 = 锚点模型（核心口径，勿改）**：重复条目的 `dueAt` 只是**规则起点**；展示与提醒一律用 `geDeadlineEffectiveDue(d, now)` = 「锚点向后滚到**严格晚于** now 的第一个时刻」→ **永远不会「已过期」**，错过的周期直接跳过、不做补记。`geDeadlinePeriodStart` = 下一次截止 − 间隔（单次条目返回 null）；`geDeadlineDoneNow` = 单次看 `doneAt != null`，重复看 `doneAt` 是否落在当前周期内 → **周期一滚过去完成态自动失效**，无需任何后台任务重置。「完成本期」= 写 `doneAt = now`，取消 = `copyWith(clearDone: true)`。
  - 状态 `GeDeadlineStatus{done,overdue,today,soon,upcoming}`（`overdue` 只可能出现在单次条目；`soon` 阈值 `geDeadlineSoonWindow` = 3 天）；文案 `geDeadlineCountdownText`（「今天 23:59 截止」/「还剩 2 天 3 小时」/「已过期 5 分钟」/「本期已完成」）、`geDeadlineDueText`、`geDeadlineRepeatText`、`geDeadlineRemainingText`；排序 `geSortedDeadlines`（未完成按截止升序在前，已完成 / 已过期沉底）。
  - UI = `presentation/ge_deadline_card.dart`：卡片排在「备忘录」卡之后（行 = 完成勾选 + 标题 + 类型角标 + 倒计时 chip + 截止时刻 + 重复规则 + 备注 + 铃铛 + `more_vert` 菜单「编辑/删除」，点行 = 编辑）+ `showGeDeadlineEditor` 底部弹层（标题 / 类型 / 日期 + 时刻 / 重复 / 提醒开关 / 备注；标题为空则保存禁用；编辑不改 id）。卡片**自带 30 秒倒计时节拍**（`tickInterval`，测试必须传 `Duration.zero` 并注入 `now`，否则 `pumpAndSettle` 会被周期性重建拖到超时）。
  - 提醒 = `data/ge_deadline_reminders.dart`（纯函数 + 薄同步）：默认 `geDeadlineDefaultLeads = [1 天, 1 小时]`；重复条目**预排未来 `geDeadlineScheduleHorizon = 4` 次**（≈ 一个月，回前台会续排）；通知 id = `geDeadlineNotifyIdBase`(920000) + 序号（按触发时刻稳定排序，上限 `geDeadlineMaxScheduled` = 120）；已过去的时刻与「未开始的窗口」不排（Windows 插件对过去时刻直接抛 `ArgumentError`，Android 会立刻弹）。
    - **⚠ 只有重复条目才展开 horizon 次**：单次条目的 `geDeadlineOccurrence(i)` 恒为同一时刻，按 horizon 展开会把同一条提醒排 4 遍（实测排成 8 条而不是 2 条）——守卫 = `test/ge_deadline_test.dart`「排期集合」。
    - 同步 = `syncGeDeadlineReminders({courses, service})`：先 `pendingScheduled()` 对账（payload = 触发时刻的 epoch ms），**完全一致就直接跳过**（避免每次回前台都扰动系统闹钟）；不一致则**先撤本 id 区间的全部排期、再整段重排**（不需要额外记账，区间外的通知不动）。**三个调用点**：进课程详情页 / 截止日期任何增删改勾（`course_detail_screen.dart`）、删除课程后（`score_estimate_screen.dart` 的 `_deleteCourse`）、**App 首帧 + 回前台**（挂在 `home_widget_sync_scope.dart` 的 `_sync()`，与桌面小组件同一时机）。
    - 平台接口：`NotificationService` 新增 `scheduleAt / cancelScheduled / pendingScheduled`（基类给默认空实现，未就绪 / 不支持的平台自动安全返回）。Android 走 `zonedSchedule` + **`AndroidScheduleMode.inexactAllowWhileIdle`**（精确闹钟在 Android 14+ 默认被拒，截止提醒差几分钟无所谓）；`scheduledDate: tz.TZDateTime.from(when.toUtc(), tz.UTC)` —— **用内置 UTC Location 承载绝对时刻**（`tz.UTC` 是常量，无需 `initializeTimeZones`，也不必引入 `flutter_timezone`；`TZDateTime.from` 按 instant 构造，时区无关）；`timezone: ^0.11.1` 已在 pubspec 由传递依赖提升为直接依赖。
    - **⚠ Android 必须在 App 清单里声明两个 receiver**（插件自 v16 起只声明 POST_NOTIFICATIONS / VIBRATE）：`com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver` 与 `…ScheduledNotificationBootReceiver`（带 BOOT_COMPLETED / MY_PACKAGE_REPLACED intent-filter，依赖顶部已有的 `RECEIVE_BOOT_COMPLETED`）→ **少了它们排期到点静默不触发**。Windows 侧只支持一次性排期且 App 未运行时投递取决于快捷方式注册，真机提醒以 Android 为准。
  - 守卫 = `test/ge_deadline_test.dart`（28 例：JSON 容错 / 锚点滚动（含跨年、恰好等于 now、很久以前的锚点）/ 本期完成自动失效 / 状态与文案 / 排序 / 提醒内容 + 排期对账与撤销，用假 `NotificationService` 记录排期）+ `test/ge_deadline_card_test.dart`（11 例：卡片渲染、完成勾选、菜单删除、点行编辑、空态两个添加入口、弹层默认值 / 保存 / 编辑回填 / 取消）。**⚠ 两个测试坑**：①`FilledButton.icon` / `TextButton.icon` 的真实类型是私有子类，`find.byType(FilledButton)`、`widgetWithText(TextButton, …)` **匹配不到**（byType 是精确类型匹配）→ 用 `find.text('保存')`；②底部弹层内容比默认 800×600 视口高，弹层测试要先 `tester.view.physicalSize = const Size(1000, 2200)` + `addTearDown(tester.view.reset)`，否则按钮在视口外点不到。
## 5. 教务数据来源速查

| 数据 | 入口 | 要点 |
|---|---|---|
| 成绩 | POST `jwxt.jxufe.edu.cn/student/xscj.stuckcj_data10421.jsp`（menucode S40303） | 解析 `grades_html_parser.dart`：**学分 = 表格第 3 列**；`cells.length < 10` 整行丢弃。缓存 box `gradesCache`，键前缀 `grades\|…`，值 `{'grades':[Grade.toMap()]}`，**可能同时存在多份不同参数副本**（聚合要遍历全部 key） |
| 课表 | GET `…/wsxk/xkjg.ckdgxsxdkchj_data10319.jsp`（params = base64） | `schedule_html_parser.dart`：**学分 = `cells[4]`**；无上课安排的表头/占位行会被解析成名为「课程」等列头词的**伪课程**，导入须过滤（`_isNoiseEntry`） |
| 培养方案 | `CurriculumRepository.getCurriculumIn(year, College, Major)` | **命中本地缓存直接返回，不发网络**（离线可用）；box `curriculums`，key = `CurriculumKey(year, college, major)` |
| 学籍 | `studentInfoRepository.getCachedStudentInfo()` | 取 `enrollYear / college / major`，是上面链路的起点。**教务请求的学号 `xh` 一律用 `StudentInfo.serialNo`（= 学籍 `<xh>`）**；`userId`（= `<yhxh>`）是**统一身份认证号**，别拿它当教务 `xh`（选课写操作会拒「不是本人」，见 §15.1 第 5 条） |
| 校历 | GET `jwxt.jxufe.edu.cn/public/SchoolCalendar.jsp` → POST `…/SchoolCalendar.show.jsp`（form: `menucode/xn/xq_m/rad=1/sel_xn_xq`） | **免登录**，但必须复用第一步种下的匿名 `JSESSIONID`（否则返回空模板 / 「凭证已失效」）；响应 **GBK**；日期格 `<span class='workday\|nonday'>` 的语义与陷阱见 §8。抓取与核对用 **python requests**（沙箱内 curl.exe 的 TLS 全废） |
| 志愿时长登记表 | GET `ssp.jxufe.edu.cn/admin/tzz/StuVolWork/downloadInfo.do`（`Cookie: JSESSIONID=<ssp 会话>` + `Referer: …/StuVolWork/stu_list.html`） | 学校「学生活动时长统计」页右上角 **「下载时长认定登记表」** 按钮的同款接口，返回 **Word 原件**（OOXML，字节头 `PK\x03\x04`，实测 14961 B，**没有 PDF 接口**）；**2026-09-18 起它同时是「活动日期」的唯一来源**（详情页已失效，见「志愿时长的时间口径」条）；`Content-Disposition` 里中文文件名是 **UTF-8 字节被 HTTP 头按 latin1 解码** → 必须 `latin1.encode → utf8.decode` 还原（`volunteerExportFileName`）；会话失效 = 3xx 或 200 的登录页 HTML（`_looksLikeHtmlBytes`） |

链路：学籍 → `collegeRepository.getAllCollege()` 按名匹配 → `majorRepository.getAllMajorIn(college, year:)` 按名匹配 → 培养方案。任一步失败**返回空索引、不阻塞界面**（回退课程自身学分）。

- **志愿时长的时间口径（2026-09-16）**：`stu_list.html` **没有时间列** → 每个活动的起止时间只能从该行「详情」页取：`GET /admin/tzz/{DQXNVolWork|DektVolActivitiesXw|HSJVolWork|DektVolActivitiesZyfw}/apply_one_detail.html?id=<detailId>&type=<type>`（type→路径 = `volunteer_hours_remote_datasource.dart` 的 `activityDetailPaths`），字段 `#startTime` / `#endTime`（形如 `2026-05-26`）。⚠ **页面里 `id="startTime"` 出现两次**（真实时间框在前、备注框在后且为空）→ 解析必须只认第一个 `<input>`（`anti_corruption/volunteer_detail_parser.dart`）。
**⚠ 2026-09-18 起这条链路整条失效**：服务端对全部记录（实测 5/5）、任何 header / `type` 变体都返回同一张 51271 字节的 **「出错了」** 页 →
  活动日期改从**认定登记表**取：`downloadInfo.do` 的 docx → `anti_corruption/docx_text.dart`（手写最小 ZIP 读取：中央目录 → 本地头 → `dart:io` 的 `ZLibDecoder(raw: true)`，**无第三方依赖**，只认 STORE/DEFLATE）取 `word/document.xml`
  → `anti_corruption/volunteer_form_parser.dart` 解析「序号 | 活动名称 | 认定日期 | 所属类别 | 时长」。⚠ **表是「一份表两栏并排」版式**（表头两组、列序相同、后面还有「志愿服务总时长」合计行）→ 按「先找日期格 → 往左取名 → 往右取类别 → 同行找 `小时` 格」定位，**不要按固定列号取**；
  `volunteerApplyFormDates` 按**去掉全部空白**的名称键补 `startDate`/`endDate`（列表 `Ea  574  …` ↔ 登记表 `Ea 574 …`，逐字符比会错配）。
  `VolunteerHoursRepository._fetchActivitiesWithTime` 的顺序 = **① 认定登记表（1 次请求）→ ② 只对仍缺日期的行回落详情页**，**顺序不许颠倒**（颠倒会白跑 N 个必失败的请求）；
  **日期口径 = 认定日期**（唯一可得）。实测该账号 5 条 = 2025-10-27 / 2025-12-12 / 2025-12-15 / 2026-03-01 / 2026-05-28，全部落在 2025-2026 学年 → **综测（`zcAutoVolunteerProvider`）2025-2026 得 24 h、2026-2027 得 0 h**（用户 2026-09-18：「综测的志愿时长也从 app 内的『志愿时长』部分直接获取 …… 注意分学年」）。
  守卫 = `test/volunteer_form_parser_test.dart`（15 例，含真实脱敏 docx fixture `test/fixtures/volunteer_form_2026.docx` 与「学年归集」验收例）。列表卡显示「活动时间：…」（同日只写一天；**现在填进去的是登记表的「认定日期」**）。仪表盘「志愿时长」卡主数值仍是总时长，右上角胶囊 `本学年 Xh`（`Key('dash_volunteer_year')`）= `volunteerHoursStats(activities, xn: currentSchoolTerm(now, terms: offlineSemesterTerms).xn)` 的结果 —— **「本学年」= 当下教学学年**（与课表/校历同口径，窗口 `[xn]-09-01 ~ [xn+1]-08-31`），**别用综测的 `zcDefaultYear`**（那是测评学年，2026-09 时给 2025-2026；首版误用它，卡片标着「本学年」却显示上学年的量，用户 2026-09-16 当场报错）；`previousYear` 只进 tooltip 做对照；一条日期都取不到时显示 `本学年 —`（**别显示 0**）。守卫 `test/volunteer_activity_time_test.dart`（18 例），归档 `reverse_engineering/志愿时长接口.md`。
- **综测自动源按学年（2026-09-16 用户裁定「综测按学年算」）**：唯一实现 = `lib/features/zongce/domain/zc_year_sources.dart` 的 `zcSemesterStartYear(String)`（`'251'`→2025，认不出→null）/ `zcWeightedForYear(List<GePriorGrade>, {required int yearEnd})`（`Σ成绩×学分/Σ学分`，只算学期码起始年 == `yearEnd-1` 且学分 > 0）/ `zcVolunteerHoursForYear(List<VolunteerActivity>, {required int yearEnd})`（= `volunteerHoursStats(acts, xn: yearEnd - 1).currentYear`）。provider `zcAutoWeightProvider` / `zcAutoVolunteerProvider` **均为 `FutureProvider.family<double?, int>`（参数 = 学年结束年 = 页面的 `_year`）**；智育加权**不再用 `weightedGradeRankingProvider(1)`**（教务「全部课程加权」跨学年累计，且服务端无任意学年档位），改由成绩缓存 `gePriorGradesProvider`（离线、账号隔离、已含排除名单与同课去重）+ 学期码自算；**取不到 → null → 回退手动填写，别显示 0**；刷新按钮要连带失效底层源（`gePriorGradesProvider` / `volunteerActivitiesProvider`）。实测该账号 26 门里 25 门带学期码 → 2025-2026 学年加权 91.89（学期码为空的课不计入任何学年）。守卫 `test/zc_year_sources_test.dart`，口径/实测表见 `reverse_engineering/2026综测规则.md`「自动源按学年取数」。 **智育 = 课程加权口径（用户 2026-09-17 裁定「应该是课程加权，而不是推免加权」）**：`zcWeightedForYear` 把 `semester` 认不出的课**并入该学年**（成绩页课程加权不过滤它们；实测漏掉 1 门实训课 → 91.89091 vs 课程加权 91.85965），但该学年没有任何学期码明确的课 → 仍 null。推免口径（`0.7×主干 + 0.3×非主干`）只存在于成绩页的「推免加权」，综测从不使用。
- **材料不分学年（用户 2026-09-17 裁定「所有的材料本身不分学年，只手动填入时间」）**：`lib/features/materials/presentation/materials_screen.dart` 与 `zongce_screen.dart` 都取 **`final mats = all;`**（材料库不再有学年条 / `_buildYearBar` 已删，列表按 `dateIso` 倒序展示，文案「材料不分学年」）；`zcFilterByYear`（`lib/features/zongce/domain/zc_engine.dart:393`）**保留但不再被页面调用**（`test/zongce_engine_test.dart:186-188` 仍测它）。**学年只用于自动源**（智育加权 / 劳育志愿，见上一条）。**外语能力**：见本 bullet 末尾「外语分值 = 表 10 档位识别」（证书目录已迁到 `lib/features/zongce/domain/zc_foreign.dart`；`zc_rules.dart` 里那套 `zcForeignCertNames`/`zcForeignCerts`/`zcForeignBandsOf` **已删**，「手填加分」的做法已被「填原始成绩、按档位识别」取代）。**综测页智育加权一律 2 位小数**（用户同日「保留2位」）：`zongce_screen.dart` 的 `String _fmt2(double v) => v.toStringAsFixed(2);` 用于结果卡 / 明细行 / 输入框 hint，别再直接插值 double。守卫 = `test/zc_foreign_score_test.dart`（含源码守卫）。 **外语分值 = 表 10 档位识别（用户 2026-09-17 二轮裁定）**：用户报「四级 489 分导致加分加了 489，实际要按挡位识别」→ 证书目录迁到 `lib/features/zongce/domain/zc_foreign.dart`（`class ZcForeignCert{name,bands,unit}` + `ZcForeignBand(label,score,[threshold])` + `zcForeignCatalog`（13 条）+ `zcForeignCertOf`（空白与半角括号容错）+ `zcForeignAward({name,rawScore})` + `zcForeignScoreLabel`；常量 `kZcForeignTotalCap=4`、`kZcForeignOtherCap=2`）。`ZcMaterial.manualScore` 语义改为**原始成绩**（四级 489/雅思 6.5/GRE 320），`zcMaterialValue` 的外语分支调 `zcForeignAward`（目录外证书手填分值上限 2；目录内但没填原始成绩 → 回退 `zcForeignLevels[m.level]` 兼容旧材料）；等级类证书（日语 N1/N2、专八/专四、TOPIK）`needsScore=false`，表单只显示固定分、不用填。`zc_rules.dart` 的 `zcForeignCertNames`/`zcForeignCerts`/`zcForeignBandsOf` **已删**（唯一来源 = zc_foreign.dart），活动候选走 `zcForeignCertNames`。**材料库行不再显示 `+N 分`**（用户同日：「材料页不显示加分」），右侧改显示备注（`m.note.trim()`，最多 2 行右对齐；「材料条目的右侧显示备注」）。守卫 = `test/zc_foreign_score_test.dart`（★ 回归：四级 489 → **1 分**）、`test/materials_wizard_test.dart`。

- **材料库列表按「二级分类」分组（用户 2026-09-18 九轮裁定）**：用户原话「我希望材料库条目显示不要按综测分类，而是直接按二级分类分类，比如学科竞赛这样的」→ 分组键从五育（`ZcTypeSpec.dim`：德育/智育/…）换成**材料类型**（`ZcTypeSpec.label`：学科竞赛获奖 / 论文 · 专利 / 外语水平 …）。唯一实现 = `lib/features/materials/domain/material_grouping.dart` 的 `class MaterialGroup{spec, materials, typeId, label, count, groupKey}` + `List<MaterialGroup> groupMaterialsByType(List<ZcMaterial>)`：**组顺序 = `zcTypeSpecs` 注册顺序**（不按数量排 → 顺序恒定，新录一条不会让分组跳动）、空组不占位、组内按 `dateIso` 倒序（同日按 `id` 兜底 —— `List.sort` 不稳定）、**每条材料恰好落进一个组**（无「未归类」兜底组，有守卫）。页面 = `lib/features/materials/presentation/materials_screen.dart` 的 `_buildBody` 调 `groupMaterialsByType(mats)`、`_materialSection(BuildContext, MaterialGroup)` 出标题 `'${group.label} · ${group.count}'`（Key = `materialsGroup-<typeId.name>`）；**行内不再重复印类型胶囊**（那枚中性墨蓝 `materialTypeColor` 胶囊已删 —— 类型已是分组标题；属性胶囊 类别/级别/奖项 照旧）；旧的 `_dimName` 与 `for (final dim in const ['z', 'd', 't', 'm', 'l'])` 已整体删除。⚠ **「选择活动类型」向导页仍按五育列全部 19 个类型**（`materials_screen.dart` 的 `for (final dim in _dimOrder)` + `s.dim == dim`）—— 那是「挑类型」的导航，不是条目分类，**别一起改**（源码守卫只禁止 `presentation` 下出现 `.spec.dim`）。真机实测（该账号 9 条材料，深色 + 侧栏）= `学科竞赛获奖 · 8` / `外语水平 · 1` / `文艺活动参与 · 4`（顺序 = 注册表顺序 contest → foreign → artAct）。守卫 = `test/materials_grouping_test.dart`（10 例：**同一育的两种类型必须成两组**（contest+foreign 同属智育）/ 组顺序与输入顺序无关且是注册表顺序的子序列 / 空组不占位 + 条数不变式 / 组内倒序与同日 id 定序 / 渲染标题 + `加分材料` 与五育名清零 + 行内不再印类型名 / 源码守卫含「presentation 下不得出现 `.spec.dim`」）；评审图 `design_preview/round18_materials_groups.png`。
- **综测页控件口径（用户 2026-09-18 四条裁定）**：① **全页统一刷新** = AppBar 的 `IconButton(tooltip: '刷新数据')` → `zongce_screen.dart` 的 `_refreshAll()`（`gePriorGradesProvider` / `zcAutoWeightProvider(_year)` / `volunteerActivitiesProvider` / `zcAutoVolunteerProvider(_year)` + `unawaited(_autoTice())`）；**字段级输入框与刷新按钮全部撤掉**（`_numField` / `_refreshAutoWeight` / `_refreshAutoVolunteer` 已删，别再回加）。② 数值一律**点击才输入**：`_tapNumber`（非空：民主评议 / 体测）+ `_tapNumberOpt`（可空：加权 / 志愿时长；`allowClear` 时弹窗多一个「用自动值」按钮 → 写 null = 回到自动）；**次数类**走 `lib/shared/widgets/count_stepper.dart` 的 `CountStepper`（`◀ n ▶`：左三角减、右三角加、点数字弹输入框，`CountStepper.clampCount` 夹取，Key 由 `minusKey/plusKey/valueKey(label)` 生成）；「自动 / 手动」用 `_sourceTag` 小标。③ **智育总分用舍入后的加权**：`zc_engine.dart` 的 `zcRound2(v)` + `final weight = zcRound2(manual.weight ?? autoWeight ?? 0);` —— 界面显示 2 位，参与计算的必须同一个值。④ **竞赛「最终计入」高亮** = `zcContestContributingIds(materials)`（与 calcJS 同口径：最高项 > 5 只计最高，否则从高到低累加至 ≥ 5，跨顶那一项计入、其后未计入）→ `_matRow(highlighted:/dimmed:)` 出「计入总分」/「未计入」。守卫：`test/zc_contest_contribution_test.dart`（含源码守卫：不得再出现 `_numField(` / `suffixIcon: IconButton` / `ValueKey('$_year-num-`，`CountStepper(` ≥ 8 处，`label: '民主评议分'` ≥ 3 处）、`test/count_stepper_test.dart`。
- **分数胶囊实心化 + 只保留 `?` 的悬停（用户 2026-09-18 四轮裁定）**：① 「我希望显示胶囊而不是卡片，就和其他部分的加分汇总一样」→ `zongce_screen.dart` 的 `_staticChip`（只读）与 `_valueTap`（可点）**统一改成与分区徽章 `_badge` 同款**：`color: AppColors.tint(context, …, 0.09)` 实心淡底 + `BorderRadius.circular(999)` + 主色 w700 12.5 + tabular 数字，**不再用「圆角 8 + `AppColors.hairline` 细描边方框」**（那看着像卡片）；`_valueTapText` 的 muted 分支字色也从 `scheme.onSurface` 改成 `scheme.primary`；`_sourceTag`（自动/手动）底色 0.10 → **0.22**（叠在同色淡底胶囊上才看得见）。② 「只有悬浮在指定区域的悬浮提示，没有另一个悬浮提示……那种卡片式的悬浮提示保留」→ **`zongce_screen.dart` 里 `Tooltip(` 计数必须为 0**：`_subRow` 的 `note` 参数与整行 `Tooltip(message: note)` 已删，七处说明性文字（「思想端正、遵纪守法……即认定 · 自动认定 60 分」等）整体撤掉，`_valueTap` 也不再挂 `Tooltip('点击输入')`（可点性由胶囊里的铅笔图标表达）；**唯一保留的悬停 = 标题右侧 `?` 的 `RuleTip` 卡片**。体测的状态说明 `ticeNote`（自动获取年份/免测说明）是状态信息不能丢 → 改成**行下一行 11px 灰字**（`Padding(left: 25, bottom: 4)`），不再用悬停承载。守卫 = `test/zongce_row_layout_test.dart`（`Tooltip(` 清零、`_staticChip`/`_valueTap` 段内 `Border.all(` 清零、`borderRadius: BorderRadius.circular(999)` 与 `AppColors.tint(context, c, 0.09)` 存在、可点胶囊同款底色）、`test/zc_year_sources_test.dart`（改守 `_fmt2(r.weightUsed)` + 无 `Tooltip(`）。
- **综测四项（用户 2026-09-18 六轮裁定）**：① 「综测不是直接算平均分，而是有一个总评成绩，这个成绩的占比由班主任定，应该让用户自行设置」；② 「综测的年份切换要使用我们的『学年选择器』」；③ 「志愿服务也基本和基本分、评议分、加权/体测成绩一样显示，唯一不同的是，还要额外在下方显示一个进度条，并根据各级别分段」；④ 「综测智育外语水平加分条目不能只显示『大学英语四级』这样的证书名，要显示原文里『大学英语四级>=425』这样的加分条目名」。
  - **① 总评成绩 = 五育加权（占比可设）**：唯一实现 = `lib/features/zongce/domain/zc_weights.dart` 的 `class ZcWeights{d,z,t,m,l}`（单位 = **百分数**，`20` 就是 20%）+ 引擎 `zc_engine.dart` 的 `ZcCalcResult.total` / `.weights`（`total = weights.applyTo(deyu:, zhiyu:, tiyu:, meiyu:, laoyu:)`，取 `zcRound2`）。**默认档 = 用户当场拍板的 `20 / 35 / 15 / 15 / 15`**（`kZcDefaultWeightPercents`，不是各 20%），另有 `ZcWeights.even`（各 20% = 旧的五育平均口径）做便捷预设。**存 `ZcManual.weights`**（Hive key `manual-<测评学年结束年>`）→ 天然**按学年各存一套 + 账号隔离**；旧数据没有 `weights` 键 → 回落默认档。`ZcWeights.fromJson` 容错：非 Map / 字段非数 / **越界（不做 clamp，把 120 夹成 100 会静默造出「德育 100%」）** / 合计不在 `100 ± 0.5` → 一律回落默认档。⚠ **`ZcCalcResult.average`（五育平均）仍在，但只是对照值**：界面一律显示 `r.total`，`zongce_screen.dart` 里**不许再出现 `(r.deyu + r.zhiyu + r.tiyu + r.meiyu + r.laoyu) / 5` 当总评**（守卫断言该串已删除）。结果卡 = 「总评成绩」+ 可点胶囊（`Key('zcTotalChip')`，`_editWeights(r.weights)` → `showZcWeightSheet`）+ 下一行小字 `占比 20 / 35 / 15 / 15 / 15`（`Key('zcTotalWeightsLabel')`），「五育平均」降级为普通小字行。弹层 = `lib/features/zongce/presentation/widgets/weight_sheet.dart`（五格百分数输入 + `合计 100%`/红字 `合计 115%` + 预设 `zcWeightPreset-default`/`-even` + `zcWeightSave` 在合计 ≠ 100% 时**禁用**，取消/点背景返 null）。
  - **② 学年切换 = 共享学年选择器**：`zongce_screen.dart` 的 `_buildYearBar` 用 `lib/shared/widgets/academic_year_picker.dart` 的 `AcademicYearPicker(key: Key('zcYearPicker'), startYear: zcDefaultYear(now) - zcYearWindow(5), endYear: zcDefaultYear(now), initialYear: _year, onChanged: _loadYear, onHoverChanged: …)`；**旧的 `_switchYear(int)` 与两个 `IconButton(tooltip: '上一学年'/'下一学年')` 已整体删除**（守卫禁止 `tooltip: '上一学年'` 与 `_switchYear` 回归）——选未来学年无意义，故 `endYear` 夹在当前测评学年。左侧「测评学年 / 9 月起测评上一学年（材料按盖章时间归档）」在悬停展开时 `AnimatedOpacity` 淡出（年份溢出到组件外会压字）。
  - **③ 志愿服务时长 = 单行胶囊 + 表 18 分段进度条**：行改成 `_subRow(context, null, '志愿服务时长（按表 18 档位换算）', tipKey: 'l-3-1', trailing: _tapNumberOpt(label: '学年志愿时长(h)', …))` —— ⚠ **`_subRow` 的 `no` 参数现在可空**：`no == null` 时在同一个 18px 槽位里画一个 6px 圆点（挂在分区下、不需要单独编号的行用它）；旧的 `_editRow(..., scoreText: '24 h → 4 分')` 两段式已删。条 = `lib/features/zongce/presentation/widgets/volunteer_bar.dart` 的 `ZcVolunteerBar(hours: r.volunteerUsed, accent: AppColors.tone(context, _yuColors['l']!), loading: volLoading)`：**6 段 = `zcVolunteerTiers` 升序（10/15/20/30/50/100 h → 1/2/4/6/8/10 分）**，等宽分段（不按小时线性铺 —— 前 10 小时会挤成 1/10 宽）、**段内按小时填充**、已满档实心 / 当前档部分 / 未到只留 `AppColors.tint` 淡底，段下两行 = 门槛（`10h`）+ 分值（`1分`），当前及已达档用强调色加粗；文案 `24 h · 已得 4 分 · 距 30 h 还差 6 h（可 +6 分）`（满 100h → `已达最高档`；取值中 → `取值中…`）。⚠ `Row(crossAxisAlignment: CrossAxisAlignment.stretch)` + 固定高度（分数估计的占比条踩过「Row 默认 center 让 ColoredBox 塌成 0 高」）。
  - **④ 外语加分条目名 = 原文条目名**：新增 `lib/features/zongce/domain/zc_foreign.dart` 的 `String? zcForeignEntryLabel({required String name, double? rawScore})`（目录内取命中档位的 `ZcForeignBand.label`，如 `大学英语四级 ≥425`；等级类证书的 label 就是证书名）；`zongce_screen.dart` 的 `_matRow` 标题改成 `m.typeId == ZcTypeId.foreign ? (zcForeignEntryLabel(name: m.name, rawScore: m.manualScore) ?? m.displayName) : m.displayName` —— **认不出（目录外 / 没填分 / 未达门槛）回落证书名**（未达门槛时把 `≥425` 挂上去反而像已经拿到那一档）；副标题仍是 `外语水平 · 大学英语四级 489 → 1 分`。**材料库列表（`materials_screen.dart`）未改**，仍显示证书名。
  - **真机实测**（VM 探针 dump 全树文案，app 深色 + 侧栏）：`总评成绩 82.77 分` / `占比 20 / 35 / 15 / 15 / 15` / `五育平均 78.932 分`（德育60 智育102.86 体育67.8 美育80 劳育84 → 手算 82.771 ✓）；学年选择器渲染出 2021–2026 且 2026 高亮；`志愿服务时长（按表 18 档位换算）` + `24 h · 已得 4 分 · 距 30 h 还差 6 h（可 +6 分）`；`大学英语四级 ≥425`。
  - 守卫 = `test/zc_weights_test.dart`（28 例：取值/合计校验/百分数文案/JSON 容错/JSON 往返/旧数据回落/copyWith/引擎总评四条/弹层三条 widget 例/四条源码守卫）、`test/zongce_volunteer_bar_test.dart`（19 例：6 段与段内比例（24h → 10/15/20 满 + 30 那段 40%）/恰好到线/满档/小数/loading/注入档位 + `zcForeignEntryLabel` 逐值 + 认不出返 null）；评审图 `design_preview/round15_zongce.png`（总评 + 学年选择器）、`round15_volunteer_bar.png`（浅/深 × 0/24/100h 三段状态）、`round15_weight_sheet.png`（占比弹层合计 115% 的红字 + 禁用保存）。
- **综测 / 材料库五项微调（用户 2026-09-18 七轮裁定）**：① 「智育的竞赛条目上也要显示竞赛的备注信息」→ `zongce_screen.dart` 的 `_matRow` 在副标题后再渲染一行 `m.note.trim()`（**仅** `m.typeId == ZcTypeId.contest && m.note.trim().isNotEmpty`；10.5px `scheme.onSurfaceVariant`、单行省略）。竞赛备注放的是子项目 / 赛道 / 组别（`C++ B组`、`2026 ICPC全国邀请赛（沈阳）`、`智慧零售赛道`、`个人奖`），不显示就分不清同一赛事的几条。② 「材料库备注信息不要限制宽度」→ `lib/features/materials/presentation/materials_screen.dart` 行右侧的备注由 `ConstrainedBox(maxWidth: 132)` 改成 **`Flexible`**（左侧标题列本就是 `Expanded`，两边各分一半：短备注不白占地方、长备注不再被截成「…」；`maxLines: 2` 与右对齐不变）。③ 「材料库不是综测的材料库，因此里面的四级证书这样的，不需要显示『大学英语四级 489 → 1 分』而是直接显示『489』就可以了」→ `lib/features/materials/presentation/material_tags.dart` 的外语分支改出**原始成绩**一枚胶囊（新增 `lib/features/zongce/domain/zc_foreign.dart` 的 `String zcForeignRawScoreText(double?)`，去尾零 `489`/`6.5`；`null`（等级类证书 / 没填分）→ **不出这一枚**，标题已写证书名）。`ZcMaterial.optionLabel` 与综测页的 `zcForeignScoreLabel` **都没动**（综测仍要「填原始成绩→按表 10 换算」口径），换的只是材料库列表的显示。④ 「志愿时长进度条太粗；进度条颜色不对；提示文本太多，『（按表 18 档位换算）』『24 h · 已得 4 分 · 距 30 h 还差 6 h（可 +6 分）』都要去掉」→ `lib/features/zongce/presentation/widgets/volunteer_bar.dart`：高度 `zcVolunteerBarHeight` **9 → 6**（细条）＋配色改 **主题红**（`accent` 默认 `null` → `Theme.of(context).colorScheme.primary`，与同一行右侧胶囊同色；原来是劳育语义青绿 `AppColors.tone(context, _yuColors['l'])`，与胶囊不同色，看着像两套东西）＋**整条 caption 与 `loading` 参数删除**（组件内只剩 6 组「门槛 + 分值」小字 = 恰好 12 个 `Text`）；`zongce_screen.dart` 的行标题去掉「（按表 18 档位换算）」、调用点收成 `ZcVolunteerBar(hours: r.volunteerUsed)`（不再传 accent/loading），`_buildYuCardLao` 的 `volLoading` 形参与其调用点一并删除（否则是留一个没人读的形参）。⑤ 「我希望把所有次数型的项，其次数修改组件放到条目右侧，并改成胶囊」→ `zongce_screen.dart` 里 **9 处**次数项由两段式 `_editRow(context, '<项名>', tipKey: …, child: CountStepper(…), note: '次 × N 分/次')` 改成单行 `_subRow(context, null, '<项名>', tipKey: …, trailing: CountStepper(…))`（`no == null` → 6px 圆点标记 + 右侧胶囊；原来的 `note` 说明整体撤掉，条款仍由标题右侧 `?` 的 `RuleTip` 承载）；`lib/shared/widgets/count_stepper.dart` 同步换成胶囊形态：`AppColors.tint(context, primary, 0.09)` 实心淡底 + `BorderRadius.circular(999)`（`border` 为 null，不再用 `AppColors.hairline` 细描边方框）+ 主色 w700 12.5 数字、三角 26×26（图标 17）、**`width` 默认 `null` = 自适应内容**（原来是固定 138 的方框，放在行尾会白占一大块）。实证（深色真机 + VM 探针 + 像素探针）：条 = `#F2555A` 且厚 **9 物理像素 @150% = 6 逻辑像素**（改前 9 逻辑像素 = 13.5 物理像素）；全树文案已无 `已得` / `还差` / `按表 18` / `取值中` / `已达最高档`；智育竞赛行确认多出备注行；材料库外语行 tag = `489`、右侧备注无省略号。守卫：`test/materials_wizard_test.dart`（长备注实测宽度 > 200；外语行不再印「→ 2 分」）、`test/material_tags_test.dart`（外语胶囊 = `489`、等级类不出胶囊）、`test/zongce_volunteer_bar_test.dart`（高度 6 / 填充色 = `colorScheme.primary` / 组件内恰好 12 个 `Text` 且无任何说明文案）、`test/count_stepper_test.dart`（圆角 999 + 无描边 + 主色数字 + 宽度 < 138）、`test/zc_weights_test.dart`（行标题代码里无「按表 18」（注释除外）、`trailing: CountStepper(` 恰好 9 处且无 `child: CountStepper(`、竞赛备注源码守卫）。评审图 `design_preview/round16_zongce_notes.png` / `round16_volunteer_bar.png` / `round16_materials.png`。
- **自动值不挂「自动」小标（用户 2026-09-18 五轮裁定）**：「加权和体测成绩不要显示『自动』字样」→ `zongce_screen.dart` 的 `_tapNumberOpt` 改成 `tag: manual ? '手动' : null,`（旧式 `(autoValue == null ? null : '自动')` 已删），体测那处 `note: _ticeFilled ? '自动' : null` 整条去掉；**连带删除 `_ticeFilled` 字段**（它只为这个标签服务：字段声明 + `_autoTice` 的 3 处赋值 + `_markTiceManual` + 切学年重置，以及 `_autoTice` 里只喂它的局部 `var filled`）——留着一个没人读的字段会报 `unused_field`。**「手动」小标保留**（手动覆盖时仍显示）；`_tapNumberOpt` 同时服务劳育「学年志愿时长」，那里也不再挂「自动」。守卫 = `test/zc_year_sources_test.dart`（断言 `tag: manual ? '手动' : null,`、`isNot(contains("(autoValue == null ? null : '自动')"))`、`isNot(contains('_ticeFilled'))`）。
- **材料库条目属性胶囊（用户 2026-09-18 裁定）**：底部不再是一行 `scheme.outline` 浅灰文本，而是 `lib/features/materials/presentation/material_tags.dart` 的 `MaterialTag`（深色文字 + 同色 `AppColors.statusFill` 底 + 同色描边）。取色 = `materialCategoryColor(cat)`（Ⅰ~Ⅳ 类赛红/橙/蓝/青）+ `materialAttributeColor(text)`（级别：国家红 / 省橙 / 市校蓝 / 院青 / 班紫；奖项：特等·一等金 / 二等银灰 / 三等铜 / 优胜青 / 未获奖灰）+ `materialTypeColor`；两枚「级别 + 奖项」胶囊由 `materialLevelTags(context, m)` 出（外语只出一枚证书档位胶囊；档位文案用 `materialLevelShort` 去掉「（x 分）」）。**备注颜色 = 标题色**（`scheme.onSurface`）。守卫 `test/material_tags_test.dart`。
- **RuleTip 逐帧跟随（用户 2026-09-18 二轮：「每个都有可能，会随着滚动，原来不遮挡的可能也会遮挡……不要离悬停区太远，但也不能覆盖」）**：`rule_tip.dart` 除滚动监听外，浮层可见期间挂**逐帧 post-frame 跟随**（`_startWatch/_tick/_syncAnchor`；`addPostFrameCallback` 自身不排帧 → 空闲零成本、`pumpAndSettle` 不会卡）；按钮露出一半以下（`_anchorVisible`）**直接收起**（避免被夹到远处）；delegate 末尾加「绝不覆盖锚点」的最终保证（与 `anchor.inflate(gap/2)` 相交就翻面）。守卫 `test/rule_tip_position_test.dart`（8 例）。

- **综测页「单行分区 + 悬停贴左端文字」（用户 2026-09-18 二轮裁定）**：①「基础分」「民主评议分」**各只占一行** —— `zongce_screen.dart` 的 `Widget _subRow(BuildContext, int no, String title, {String? tipKey, List<String>? tipIds, Color? color, String? note, required Widget trailing})`（序号圆块 + 标题 + 紧随其后的 `?` + 最右端 `trailing`；**`note` 不再单独占一行，改挂整行 `Tooltip`**）。三育写法：基础分 `trailing: _flatScore(context, '60 分')`（只读灰分），民主评议 `trailing: _tapNumber(..., display: '${_fmt(pingyi)} / 20', ...)`（**右侧分数可点修改**，口径仍是 x/20）。⛔ 旧的 `_sub(...) + _editRow('X基础分' …)` 两段式已删（守卫禁止这些标签回归）。②「所有悬浮提示位置改到左端文本的右侧旁」= 统一走 `Widget _labelTip(BuildContext, String label, {String? tipKey, List<String>? tipIds, TextStyle? style, Color? tipColor})`（`Row(min, [Flexible(Text), RuleTip])`），调用处放进 `Expanded(child: Align(alignment: Alignment.centerLeft, child: _labelTip(…)))` → 文字与 `?` 贴一起且整体靠左，行尾分值/控件照旧在最右。落点 = `_editRow` / `_extraItem` / `_sub` / `_subRow` / `_yuCard` 五育名 / 结果卡「测评结果」/ 排名卡标题与 5 行 / `_matRow` 材料名（`RuleTip` 移进名称行）。⚠ **同一行原来挂两个条款点的地方要用 `List<String> _tipIdsOf(List<String> keys)`（读 `zcTipRefs`，现已 import `domain/zc_tip_data.dart`）合并成一个按钮**：民主评议 = `_tipIdsOf(const ['sh-d-2', 'd-2-ping'])`（美/劳育同构）。⛔ 已删的旧写法（守卫禁止回归）：`if (tipKey != null) RuleTip(tipKey: tipKey, size: 13.5),`（行尾）、`RuleTip(tipKey: 'overall', size: 14)`、`RuleTip(tipKey: it.$4, size: 13)`、排名卡头部那个多余的 `Icon(Icons.help_outline, size: 15)`。守卫 = `test/zongce_row_layout_test.dart`（单行数/`trailing` 计数/旧标签清零/`_labelTip` 与 `Align(centerLeft)` 计数/材料名含 tip/`zcTipRefs` 九个 key 都能解析出非空 ids）。

- **综测页分数一律用「右侧胶囊」（用户 2026-09-18 三轮裁定）**：「基础分和评议分都显示为胶囊，点击评议分胶囊可修改；然后加权成绩和体测成绩也改成这种形式，点击修改」→ 八行都是 `_subRow(context, no, 标题, {tipKey/tipIds, note, required trailing})` 的单行，`trailing` 一律是胶囊：**基础分** = `_staticChip(context, '60 分')`（新件：**只读胶囊**，与可点胶囊同款外形 —— 圆角 8 + `AppColors.hairline(context, 0.9)` 描边 + 13 w600 + tabular 数字，**无 `InkWell`、无铅笔图标**；原只读灰字件 `_flatScore` 已删）；**民主评议 / 体测成绩** = `_tapNumber(...)`；**加权成绩** = `_tapNumberOpt(...)`（可留空回自动值）。加权行保留 `weightMissing` 红色警示行，加载态用 `display: '加载中…'`（note 追加「教务加载中…」）；体测免测仍显示 `60（免测）` + `自动` 小标。`_valueTap` 的宽度参数改为 **`double? width`（null = 自适应内容宽）**，内部 `final fixed = width != null;` + `Row(mainAxisSize: fixed ? MainAxisSize.max : MainAxisSize.min, children: [if (fixed) Expanded(child: _valueTapText(text, scheme, muted)) else _valueTapText(text, scheme, muted), …tag, …铅笔])` —— 胶囊贴合文字，与只读胶囊观感一致（`_tapNumber` / `_tapNumberOpt` 的宽度默认值随之改为 `double? width`）。⛔ 已删（守卫禁止回归）：`_flatScore(`、`'课程加权平均成绩'`、`'体质测试成绩'`、`_sub(...) + _editRow(...)` 的加权 / 体测两段式。守卫 = `test/zongce_row_layout_test.dart`（`_subRow(` ≥ 9、`trailing: _staticChip(context, '60 分')` == 3、`trailing: _tapNumber(` == 4、`trailing: _tapNumberOpt(` == 2（加权 + 志愿时长）、`_staticChip` 段内不得出现 `InkWell` / `edit_outlined`、必须含 `BorderRadius.circular(8)` 与 `AppColors.hairline(`，以及 `mainAxisSize: fixed ? MainAxisSize.max : MainAxisSize.min,` 与 `double? width,` 的存在性）。

## 6. 工作区状态

- git 工作区有**大量历史 untracked**（`.scratch/`、`dianfei_work/`、`packaging/`、`reverse_engineering/` 等），不要清理、不要 `git clean`。
- 测试是扁平的 `test/*_test.dart`（**77 个文件**，引擎/纯逻辑单测为主；**⚠ 另有 10 张 golden** —— `test/goldens/qa_r*.png`，由 `test/qa_rules_visual_test.dart` 驱动，旧说法「无 golden」已过时）；`flutter test` 全量 **978 例：977 通过 / 1 失败**（2026-09-16 实测；本轮新增 `pane_chrome_test` **13**，见 §19）。**唯一失败 = 模板遗留 `test/widget_test.dart`**（`Counter increments smoke test`，`Found 0 widgets with text "0"`，历史上一直失败，别当回归）。2026-09-11 记的两个失败**都已修复**：`settings_calendar_section_test` 的 3 例 Hive 失败（该文件 `setUpAll` 补了 `Hive.init`）、`auth_session_account_test.dart:230`（当时正被别的会话编辑）。部分文件实测（**非全部**）：`ge_engine_test` 26、`ge_curriculum_test` 11、`ge_summary_test` 8、`calendar_day_mark_test` 47、`my_campus_test` 23、`zongce_engine_test` 15、`school_term_test` 14、`account_avatar_test` 21、`school_calendar_screen_test` 8、`school_calendar_parser_test` 6、`tice_notice_test` 5、`cxstar_auth_test` 8、`read_credit_cxstar_progress_test` 4、**`public_query_test` 35、`public_timetable_parser_test` 19、`public_free_time_test` 23、`public_timetable_view_test` 4**（公共查询四件套，2026-09-14 加，见 §14）、**`course_selection_des_test` 13、`course_selection_parser_test` 21**（选课，2026-09-14 加，见 §15）、**`student_id_test` 5**（教务 `xh` 口径守卫，2026-09-14 加，见 §15.1 第 5 条）、**`ims_token_refresh_test` 12、`ims_session_card_test` 3**（教务令牌探活/手动刷新，2026-09-15 加，见 §12.2）、**`course_selection_filters_test` 16、`course_selection_search_ui_test` 5**（选课检索栏逐控件对齐教务原页面，2026-09-15 加，见 §15.4）、**`home_layout_test` 9、`home_service_grid_test` 6、`home_sidebar_test` 9、`home_tile_alignment_test` 6、`home_detail_pane_test` 6、`home_grade_rank_badge_test` 4**（主页布局 / 宫格定高 / 侧栏 / 服务目录 / **右侧内嵌面板** / **排名胶囊文案**，2026-09-15~16 加，见 §17）、**`app_page_transitions_test` 9**（页面转场取代系统 zoom，2026-09-16 加，见 §18）、**`pane_chrome_test` 13**（侧栏模式服务页不画导航栏 + 按钮下沉 + 课表行宽修正，2026-09-16 加，见 §19）。
- 截图验证：`Add-Type System.Drawing` + user32（`SetWindowPos(-1 TOPMOST)`、`SetForegroundWindow`、`GetWindowRect`）+ `Graphics.CopyFromScreen` → PNG → `view_image`。注意 `PrintWindow(…,2)` 可能抓到被遮挡的其它窗口内容；`view_image` 回报的中文像素坐标不可靠。
- **本机 Windows 的「下载」目录 = `D:\Tmp`**（`HKCU:\…\User Shell Folders\{374DE290-…}` 重定向；`C:\Users\Mxster\Downloads` 与 `Documents` **都不存在**，Documents 实际是 `C:\Users\Mxster\OneDrive\文档`）。`path_provider` 的 `getDownloadsDirectory()` 返回的就是 `D:\Tmp` → 验证「导出文件」类功能落盘要去 **D:\Tmp** 找，别再看 `%USERPROFILE%\Downloads`（曾因此误判成「导出失败」）。

## 7. 校区口径速查（三套命名，勿混用）

`lib/features/campus_address/domain/my_campus.dart` 的 `MyCampus` 是**唯一统一口径**（= 学校地址那套 4 校区），另两套靠它映射：

| 统一口径 `MyCampus` | 电费 `findCampusList` | 校区地图 `campusMapEntries` |
|---|---|---|
| 蛟桥园校区 | `id=1` 蛟桥校区 | 蛟桥园北区 / 蛟桥园南区 |
| 青山园校区 | **无**（无宿舍电费服务） | 青山园校区 |
| 麦庐园校区 | `id=2` 麦庐校区 | 麦庐园北区 / 麦庐园南区 |
| 枫林园校区 | `id=3` 枫林校区 | 枫林园校区 |

- 另两套的出处：电费 `ElectricityRemoteDataSource.fetchCampusList()`（后端 `findCampusList`）、地图 `lib/features/campus_address/presentation/campus_map_screen.dart` 的 `campusMapEntries`、地址 `domain/campus_address.dart` 的 `campuses`。
- 电费 `findCampusList` **免鉴权**（仅需 `servicewechat.com` Referer），可直接实测核对，不必进 App。
- 电费名字是缩写（蛟桥 / 麦庐 / 枫林 +「校区」），**不等于**统一口径名字，`MyCampus.fromName` 刻意不解析它们（避免把 `麦庐校区` 误认成 `麦庐园校区`）。
- 打破映射会被 `test/my_campus_test.dart` 的漂移守卫抓到（地址列表双向完备 + 地图条目归属唯一）。

## 8. 校历「假 / 班」角标口径（改动前必读）

**判定引擎 = `lib/features/school_calendar/domain/calendar_day_mark.dart`**；界面一律走 `CalendarMarkIndex.markOf(day, calendarKind:)`，禁止在页面里各自拼判定。

- **数据源优先级（用户 2026-09-11 拍板）：官方安排为主，教务校历仅兜底。**
  1. 主源 = 小程序校历官方逐日安排（`WxSemesterArrangement.events`：GUID 实时 / `wxcal_offline_data.dart` 内置快照兜底）；
  2. 兜底 = 教务校历 HTML 的 `workday|nonday`，**且只取「工作日却标 nonday → 放假」这一侧**（补寒暑假）。
- **教务校历为什么不能当主源（真实抓取实测，2026-2027 第一学期）**：
  - 2026-10-05 / 06 / 07 在国庆假期内标 `workday`（照搬会把假期显示成上课日）；
  - 2027-01-19 ~ 01-31 寒假内**整段**标 `workday`（含 1/23、1/24、1/30、1/31 四个周末），其备注「假期结束日期：2027-01-19」即脏数据；
  - 故**绝不用「周末 workday → 班」**；`nonday` 一侧与官方安排对学期起止一致，才可用于兜底。
- **角标映射**：`假` = 含「放假 / 假期」的区间 + 「寒假/暑假开始」之后的整段假期（延伸到下一学期开始前一天，无下学期则 +45 天）；`班` = `补.*课|调休`；`运 / 考 / 军 / 到 / 教` = 运动会 / 考试考核复习 / 军训 / 报到注册 / 入学教育。
- **噪声必须排除**：「教职工上班」（老师上班，学生不上课）、「老生开始上课」「学生课程结束（当天上课）」不打角标，只进当日详情——否则 9/2、12/31 会冒出无意义角标。
- **军训按入学年**：只在「本人入学年 == 该学期学年」时显示（学籍 `enrollYear`，取不到 = 不显示），设置里可强制显示。
- **人群过滤**：官方安排按「教职员工 / 本科生 / 研究生」分节，⚠ **分节字段带字间空格**（「本 科 生」），比对前必须去空白；放假与补课**不受**人群过滤影响；学籍取不到时不过滤。学籍条件走窄 provider `calendarViewerProvider`（`CalendarViewer{enrollYear, trainLevel}`），别把整个 `StudentInfo` 灌进判定层。
- **默认值**：角标风格 = 数字下方小字（可切右上角角标 / 整格淡色底，行高 32 → 40）；军训 = 只入学年；人群过滤 = 开。三项开关位于**全局设置页「校历」节**（`lib/features/settings/presentation/settings_screen.dart`，首页右上角齿轮 / 校历页齿轮进入），校历页不再自建设置弹层。
- **守卫测试**：`test/calendar_day_mark_test.dart`（规则 + 261 学期逐日断言）、`test/school_calendar_screen_test.dart`（用真实 fixture `test/fixtures/_cal_261_xq0.html` 渲染整页，断言各角标数量 + 三种风格无溢出）、`test/school_calendar_parser_test.dart`（三学段 fixture 解析）。改判定先动这三处。
- **偏好存储**：`data/calendar_prefs.dart`（Hive `schoolCalendarPrefs` 单 key JSON + `ChangeNotifier` + `ChangeNotifierProvider`，落盘尽力而为、**不做全局单例**——`ChangeNotifierProvider` 会 dispose 掉它）。

## 9. 「当下学期」唯一口径（课表 / 首页今日课程 / 体测 / 校历共用）

**唯一实现 = `lib/features/school_calendar/domain/school_term.dart`**（2026-09-11 立）：

```dart
({int xn, int xq}) currentSchoolTerm(DateTime now, {List<WxSemesterArrangement> terms = const []})
String schoolTermLabel(int xn, int xq)   // → '2026-2027 学年第一学期'
```

- **判定顺序 = 校历区间优先，月份兜底**：传了 `terms`（= `wxcalOfflineToDomain()` 的 19 学期快照）就先按**日期区间**命中（命中多个取 start 最晚者）；落在区间之间的**空档（假期）→ 取最早的未来学期**（即「假期显示下一学期」）；落在快照覆盖范围外 → **返回 null**，由调用方决定。没传 terms 才走 `_termFromMonths` 月份规则：9–12 月→`(y,0)`；1 月 `day ≤ 14`→`(y-1,0)` 否则 `(y-1,1)`；2–6 月→`(y-1,1)`；7–8 月→`(y,0)`。
- **`terms` 从哪来**：`lib/features/school_calendar/data/providers/wxcal_providers.dart:29` 的 `offlineSemesterTermsProvider`（`Provider<List<WxSemesterArrangement>>`）。**一律从校历侧取，禁止在业务侧再定义副本**（schedule 侧曾有一份，已迁走以避免校历 → schedule 的反向依赖）。
- **调用点（改口径必须全查这 6 处，全部要传 `terms`）**：`lib/features/ims/schedule/presentation/schedule_screen.dart`（initState 首帧定学期，切 tab 即重建 → 每次进入都重置）、`…/schedule/presentation/live_class_screen.dart`、`lib/features/school_calendar/presentation/school_calendar_screen.dart:34`、`lib/features/home/presentation/dashboard_panel.dart`（`dashboardTodayCoursesProvider`）、`lib/features/score_estimate/presentation/score_estimate_screen.dart`（`_importFromSchedule`）、`lib/features/tice/presentation/tice_screen.dart`（`_currentXn` getter）。`school_calendar_providers.dart` 现在只做 `export '…/domain/school_term.dart';` 兼旧 import 兼容——**export 必须写在 import 之后、任何声明之前**（放声明之后 = 编译错误）。
- **历史 bug（想改回去之前先读）**：`schedule_screen.dart` 曾写 `_selectedYear = int.tryParse(si.enrollYear) ?? DateTime.now().year;` —— 学籍 `enrollYear` 是**入学年（该生 2025）**，不是学年，于是 2026 年 9 月整月显示 `2025-2026 第一学期`。**`enrollYear` 只能用于「培养方案学年」和「军训是否显示」，永远不要当学年/学期用**（成绩页 `grades_screen.dart:35` 的用途是正确的，别顺手改）。
- **`resolveTeachingWeek` 的陷阱**：`lib/features/school_calendar/domain/teaching_week.dart:65` 内部 `_pickTerm` 在假期会回退到 **lastPast（上一学期）** → 拿到 `TeachingWeek` 后**必须**用 `tw.term.matches(xn, xq)` 守卫，否则会把上学期的周数当成本学期的周数。
- **第 1 教学周锚点 = 学期 `start` 所在周（2026-09-14 修正，勿改回去）**：`_firstTeachingMonday(term) => _mondayOf(term.start)`。教务校历本身就是「周次 + 周一~周日」的月历表（`CalendarWeekRow.weekNo`），第 1 周 = 学期起始周：261 → **09-07**、252 → 03-02、251 → 09-01。旧实现取校历里**最早一条本科生「开始上课」事件**当第 1 周 → 261 命中「老生开始上课」09-14，**整学期错位一周**：开学当天（09-14）课表页显示「第 1 周」且一片空白（该生 12 个课时段全是 `2-17 周`）。「开始上课」是学生第一次上课的日子，**不等于**第 1 教学周（261 第 1 周是新生军训 / 老生报到周）。三条自洽佐证：① 校历周次表 第 1 周 09-07~09-13、第 2 周 09-14~09-20、第 17 周 12-28~2027-01-03；② 校历「2026-10-10 补第4周周五的课」→ 第 4 周周五 = **10-02**，正在国庆假期（10-01~10-07）内（按旧锚点则是 10-09，并非假日，补课无从谈起）；③ 课程 `2-17 周`（老生 09-14 开课 = 第 2 周）↔ 校历「学生课程结束 12-31」= 第 17 周周四（按旧锚点课程要上到 2027-01-10，已过期末复习 01-04）。
  ⚠ 数据中台 `dzj.jxufe.edu.cn` 的 `weekTitle` 与教务周次**不同口径**（它以学生上课为首周，故 2026-09-10 报「第 0 周」）——**别拿它当基准**；课表周次标签与教务校历同源，只有它们必须一致。
- **行为口径（用户 2026-09-11 裁定，原话）**：「开学前显示整学期视图；假期显示下一学期课表，没出来则提示‘课表还没出来’；开学后显示实际周数；**每次进入都重置为当前学期**」。落到代码：`_week = currentWeek`（`null` = 整学期视图）、`_termNotStarted => _isCurrentTerm && _currentWeek == null` → 空课表显示「课表还没出来」+ 副文案，否则「暂无课表数据」；**手动选择不持久化**（只在页内记住）。
- **配套修正**：`lib/shared/widgets/academic_year_picker.dart` 必须实现 `didUpdateWidget`（父级异步纠正学年后要 `_animToken++` 作废在途补间 + 重算 `_selected`/`_offset`），只在 initState 读 `initialYear` 会导致显示不跟随。
- **体测页的时间提示 = 服务端原文，不硬编码时段**：`lib/features/tice/data/tice_remote_datasource.dart` 的顶层纯函数 `String? ticePlainNotice(String body)`（trim 后非空、≤300 字、不以 `{`/`[` 开头、不含 `<` → 返回原文，否则 null）在 JSON 解析**之前**拦截；实测非开放时段返回 62 字节纯文本 `允许学校学生成绩查询的时间为:9:00:00~21:00:00。` → `TiceResultKind.notice`，界面直接展示该文案。
- **课表页周次边界 = 教务数据，绝不写死**（2026-09-15 用户要求「第一周和最后一周的界定教务系统应该有接口……找找然后复用」）：`lib/features/ims/schedule/domain/term_weeks.dart` 提供 `resolveLastTeachingWeek({calendar, entries, fallback})`（**教务校历周次表 → 课表 `ClassTime.endWeek` → 兜底 20**）与 `clampTeachingWeek(target, lastWeek:)`；第 1 周仍取 `resolveTeachingWeek().firstMonday`。课表页「上一周/下一周」按钮与手机端左右滑动都经过 `clampTeachingWeek` —— **首/末周不允许再滑动**。守卫 `test/schedule_term_weeks_test.dart`。
- **周次信息只在整学期视图显示**（2026-09-15 用户裁定：「课表里每个课程，只有在『整学期』视图下，才显示周数信息（包括范围与单双周），而在周视图下，就不显示周数信息了」）：门控 = `ScheduleGridView` / `ScheduleHorizontalView` 内 `final showWeekInfo = week == null;`（`week == null` 即整学期模板，周视图已按周过滤 → 周次是冗余信息），覆盖三处 —— 正常格周次行、停课格 `span≥2` 的周次行、同格多 slot 的「单周/双周: 教室」行（周视图只留教室）。**别用「有 span 就显示」代替该判定**。守卫 `test/schedule_week_info_test.dart`（7 例：两视图 × 整学期有/周视图无 + 单双周 + 同格两门单双周课）。
- **课表页排版口径**（2026-09-15）：手机竖屏（< `ScheduleGridView.compactBreakpoint` = 620dp）**左右无边距**、列宽 = 可用宽度 / 7（整表铺满屏宽、不横向滚动）、字号/行高按 `compact` 收紧；桌面端列宽在 80~160 间自适应屏宽，**超过 160 不再拉伸而是整表居中**、不足 80 才横向滚动。`ScheduleScreen` 用**自己的 AppBar** 承载「学年 + 学段 + 周次/整学期」选择器（**不再显示「课表」标题**），`ims_tab_container.dart` 对 `ImsTab.schedule` 不再叠一层 AppBar。**标题栏单行/两行按可用宽度自适应**（用户 2026-09-15 问「为什么学期选择和周数显示不在同一行」→ 从前写死两行、桌面端白占一行）：唯一实现 = `lib/features/ims/schedule/presentation/schedule_title_bar.dart` 的 `ScheduleTitleBar`（+ `ScheduleSemesterSelector` / `ScheduleWeekSwitcher`，正文筛选栏复用），静态 `fitsOneRow` / `rowNeed`（TextPainter 实测量宽）/ `toolbarHeight(oneRow:, compact:)`；**抽成不依赖 provider 的独立组件就是为了可测**。守卫 `test/schedule_grid_layout_test.dart`（360/900/1600 三档断边距/铺满/居中）+ `test/schedule_title_bar_test.dart`（1400/900/460/360 同一行、250 才两行、两档高度不溢出、周次入口与手机端学期码按钮与弹窗）。
  - ⚠ **`rowNeed` 量宽口径（2026-09-15 二轮校正，用户「还有很大的空隙，但继续减小宽度就换行」）**：① 量宽基础样式必须取 **AppBar 标题样式**（`appBarTheme.titleTextStyle ?? textTheme.titleLarge`）——调用点在 `Scaffold` **之外**，`DefaultTextStyle.of(context)` 在那里是 fallback（无字体族），裸 `TextStyle` 同理，两者都把文字量宽约 2 倍（实测 `261`@15：默认字体 45.0 vs 真实 23.25）；② 非 compact 档「学年 + 学段」内部间距是 **8**（与 build 的 `SizedBox(width: compact ? 4 : 8)` 一致），别再用 `gap`（会被算两遍）；③ 图标按钮实测宽 **40**（48 点击区 − 8 visualDensity），不是约束里的 30/34；④ 学段下拉比文字宽 **19**（实测，别写 32）；⑤ **`week` 必填**：整学期视图（`week == null`）下周次控件**整个不渲染**（2026-09-16 第四轮：用户要求不显示「整学期」字样），恒按「有周次段」预留会白占宽度 —— 组件 build 与 `ScheduleScreen.build` 两处判定都要传；⑥ `fitsOneRow` 余量收到 **6**（校准后 need 与真实内容宽偏差 −3~0，week=null 档按最宽文案保守 12）。**守卫 = `test/schedule_title_bar_test.dart` 的「不变式」组**（`_pumpProduction` 镜像生产：判定在 Scaffold 外算、标题栏进真实 AppBar；`_loadThemeFont` 用 `C:\Windows\Fonts\simhei.ttf` 注册成主题字体族——**不注册字体则此 bug 量不出差别**）：断言 `need − real ∈ [−6, +15]`、可用 = 真实内容 + 24 必须单行、窄于真实内容 12 必须换行且不溢出。
- **显示周六 / 周日（2026-09-17 用户：「课表加两个设置，是否显示周六、是否显示周日；当周六/周日有课时，关闭对应显示要弹出确认框提示用户」）**：领域口径唯一实现 = `lib/features/ims/schedule/domain/schedule_display_days.dart`（`scheduleDayNames` / `scheduleSaturdayIndex`=5 / `scheduleSundayIndex`=6 / `scheduleVisibleDays({showSaturday, showSunday})` / `scheduleDayCourseCount(entries, dayIndex, {reschedules})` —— 按**整学期**、课程名去重、含调课）。偏好 = `lib/features/ims/schedule/data/schedule_display_prefs.dart`（box `schedulePrefs` / key `display`；`fromJson` **必须 `is bool` 判定，别写 `as bool?`** —— 脏值会抛 `type 'String' is not a subtype of type 'bool?'`，守卫实测抓到）+ `lib/features/ims/schedule/data/providers/schedule_display_providers.dart`（`scheduleDisplayPrefsStoreProvider`；`scheduleCachedEntriesProvider` 只读课表缓存、不联网，供设置页判断「那天有没有课」）。**唯一写入点 = 设置页「课表」节**（`SettingsSection.schedule`；课表页 `paneAppBar` 已声明 → 齿轮直达；关闭有课的那天先弹 `AlertDialog` 确认）。两个视图（`schedule_grid_view.dart` / `schedule_horizontal_view.dart`）一律按 `days` / `dayCount` 等分（竖版列宽 = (可用 − 节次列)/dayCount，横版行高 = (高 − 表头)/dayCount），**不得再硬编码 7 天**。守卫 `test/schedule_display_prefs_test.dart`（16 例：可见天推导 / 该天课程数含调课与去重 / 偏好落盘 / 两视图列数 / 设置页渲染与无课直接切换 / 源码守卫）。

- **课表四项显示口径（2026-09-17 二轮 · 用户原话：「我希望深色模式的课表，每个课程内部的文字用白色，但是浅色模式的显示不变」/「我希望课表显示时，任意两行之间的时间间隔一旦超过了1h，就在这两行之间插一个矮行」/「我希望课表可以设置是否显示表格线」/「我希望桌面端主页的侧边导航栏里，顶部"数据一览"和教务系统之间不要显示分割线」；**三轮 2026-09-17**：「我希望矮行颜色要与其他格子颜色一致，不显示内容文本」/「深色模式课程字体颜色不要用纯白，太亮」/「顶部周几的文本不要用深灰，太暗」—— 见下方 ①②⑤ 的更新）**：
  - **① 深色格内文字分两个角色（2026-09-17 三轮，别合并）**：用户三轮原话递进 —— ①「我希望深色模式的课表，每个课程内部的文字用白色，但是浅色模式的显示不变」→ ②「深色模式课程字体颜色不要用纯白，太亮」→ ③「感觉课程名的颜色还是太亮」（②只从纯白降到 `#EBEBEB`、相对亮度 −8%，肉眼几乎没差别，故有第③轮）。唯一出处 = `lib/features/ims/schedule/presentation/schedule_tone.dart`：**课程名**走 `ScheduleTone.name(context, seed)`（深色 = `ScheduleTone.darkCourseName` = **`#C8C8C8`** —— 比正文色暗 27% 相对亮度、CIELAB 明度 93.4 → 80.7，压在 12 个课格实底上仍 ≥6.1:1，最亮橙格 `#462F23` 7.4:1 / 最暗青格 `#234346` 6.4:1）；**次级行**（教师 / 教室 / 周次）走 `ScheduleTone.meta(context, seed)`（深色 = `AppLadder.darkOnSurface` `#EBEBEB`，**基准色刻意不动**）再由调用方 `.withAlpha(190/180/160/150/140)` 淡化 —— 它们本来就只有 3.9~5.8:1，跟着课名一起降会掉到 3.2:1、把元信息读没；降课名也不会层级倒挂（α190 的教师行合成色 ≈ `#B9B2B2`，仍明显暗于课名）。两个视图里 `nameColor`（喂课名那行，`color: nameColor`）与 `textColor`（喂次级行）是**两个**局部变量。底板不变（提亮同色相的 20% 实底）。浅色两侧都逐值返回 `courseTexts[i]` —— **一个色值都不动**。**「已调走 / 停课」两个语义降级态不走它** —— 两个视图的 switch 里仍把**两个**颜色都覆盖成 `AppColors.textMuted`（改成亮字会毁掉「灰掉」的信号）。评审图 = `design_preview/schedule_name_dark.png`（真实渲染）+ `schedule_name_options.png`（旧 / 现 / 备选三档）。守卫 = `test/schedule_dark_tone_test.dart`（课名色 + 对比度 + 次级行基准色 + 源码守卫 `ScheduleTone.name` / `ScheduleTone.meta` / `textColor.withAlpha(`）。
  - **② 大间隔矮行**：领域唯一实现 = `lib/features/ims/schedule/domain/schedule_gap_rows.dart`（`scheduleGapThresholdMinutes = 60` / `scheduleBreakMinutes(table, period)` / `scheduleRows(table)` → `List<ScheduleRow>`（`ScheduleRow.period(p)` / `ScheduleRow.gap(afterPeriod, minutes)`）/ `scheduleGapAfterPeriods(table)` / `scheduleGapLabel(minutes)` → `1h40`）。**阈值只能来自真实作息表**（`PeriodTable`；课表 HTML 只给节次不给钟点），相邻两节任一侧缺节就**不插**（不猜）。内置兜底表正好两处：5 节 12:20→6 节 14:00（100 分，午休）与 9 节 17:30→10 节 18:40（70 分，晚饭），也就是上午/下午/晚上分界。两个视图共用这一份序列：**竖版插矮行**（key `scheduleGapRowAfter-<p>`，高 18/14）、**横版插矮列**（key `scheduleGapColumnAfter-<p>`，宽 16/12；表头那颗保持红底，红色表头带不被切断）。**⚠ 三轮（用户：「矮行颜色要与其他格子颜色一致，不显示内容文本」）：矮行既不涂底色、也不渲染任何时长文案** —— 竖版两颗（节次列 `_buildGapLabelCell` + 课格区 `_buildGapCell`）的 `BoxDecoration.color` 必须为 **null**，边框与同一列的 `_buildEmptyCell` 逐值相同（`bottom` / `right` 都走 `_line(AppColors.fillStrong)`，**别再用 `stroke`**）；横版那颗 `color: isWeekend ? AppColors.fill(context) : null`，与同一行的空格子同规则（**工作日透明、周末才上分区底**）。`scheduleGapLabel(minutes)` 这个纯函数**保留在 domain**（供复用与测试），只是**不再渲染**。矮行的作用只剩「把上下午 / 晚间错开」+ 一截空白与两条行线。⚠ **跨过矮行的课格必须把它吸收进自己的高度/宽度**（`_innerGapHeight` / `_innerGapWidth`：`period ≤ p ≤ period+span-2`；`_buildDayColumn` 的 `absorbedGaps` / `_buildDayRow` 的 `absorbedGaps` 同步跳过那一行），否则该列矮/窄一个矮行、整表从下一节起错位。行高记账：`_fitCellHeight` 必须先扣 `gapTotal = gapsAfter.length * gapHeight`，分页板 `bodyHeight = schedulePeriodCount * cellHeight + gapTotal`。矮行**刻意不等比**（午休 100 分比一节课 45 分还长，等比画出来会比课格还高，与「矮行」相反）。历史踩坑（已不适用，留着别重犯）：一版用 `fillSoft`，与页面底只差 5/255，出图核对时肉眼完全找不到；抬到 `AppColors.fill` 后三轮又按用户要求改成**不涂色**。守卫 `test/schedule_gap_rows_test.dart`。
  - **③ 表格线开关**：偏好 = `ScheduleDisplayPrefs.showGridLines`（**默认 true = 改动前观感**；旧存档无该键 → `_boolOf` 回落 true，老用户不变），设置页「课表」节 `Key('scheduleGridLinesSwitch')` 切换（无需确认框，纯观感）。视图侧唯一入口 = 两个视图各自的 `BorderSide _line(Color)`：关掉返回 `BorderSide.none`，**所有构成表格的分隔线都必须从这里出**（节次列右线 / 行底线 / 课格右底线 / 表头白线 `Colors.white24` / 左上角格底线），别在别处再写 `BorderSide(...)`。**语义标记线不属于表格线、照画**：调课格的橙色上边（竖版）/ 左边（横版，宽 2）与 `调/停/补` 角标。守卫 = `test/schedule_display_prefs_test.dart` 的「表格线开关」组（遍历子树累加所有 `BoxDecoration` 的 `Border` 宽度：开 > 0、关 == 0）+ 源码守卫（两个调用点都传 `showGridLines: display.showGridLines`）。
  - **④ 侧栏分割线**：`lib/features/home/presentation/home_sidebar.dart` 里「数据一览」概览行与 `HomeServiceGroup.values[0]`（'教务系统'）之间**不画分割线** —— 原来那里有一条 `Divider(height: 17, thickness: 1, indent: 12, endIndent: 12)`，已删；靠分组标题自身的上内边距（14）留白即可。分组之间本来就没有线，**别再加回来**；列表里唯一的另一条线在底部固定区上方（那条不动）。守卫 = `test/home_sidebar_test.dart`「「数据一览」与「教务系统」之间不画分割线」（传了 footer 才有线，断言那条线在最后一个分组之下）。
  - **⑤ 顶部星期表头的红底 = 实心深红（深色下不换档）**（2026-09-17 三轮 · 用户：「顶部周几的文本不要用深灰，太暗」）：唯一实现 = `ScheduleTone.headerFill(context, light) => light`（**恒返回原深色值**），竖版 `_buildDayHeader` 与横版 `_buildHeaderRow` 的表头底都改用它（原先走 `ScheduleTone.header` = `AppColors.tone` = `featureTone(#C62828)` = 提亮红 `#D96363`）。**成因**：提亮红上白字只有 3.55:1、深字 4.90:1 → `AppColors.onAccent` 择了**近黑字**，正是用户看到的「周几是深灰」。口径 = §22「深色下实心件（chip 底 / 表头）用深、饱和、实的一档」：红底 `#C62828` 白字 5.62:1、周末底 `#455A64` 白字 7.25:1，两侧都自动择白。`ScheduleTone.header` **只留给线稿**（左上角横竖版切换图标），**实心底不许走它**。浅色两档恒返回原值 → 逐像素不变。守卫 = `test/schedule_dark_tone_test.dart`（表头底 == `headerRed` / `weekendHeader`、白字 ≥4.5 且优于深字、`onAccent(...) == 0xFFFFFFFF`）。
  - 评审产物：`design_preview/schedule_gap_{light,dark,dark_nolines,dark_horizontal}.png`（浅/深 × 表格线开/关 × 竖/横）。
- **矮行高度 = 纯错位量 10/8（2026-09-17 四轮，用户：「矮行太高」）**：矮行上一轮已被要求「颜色与其他格子一致、不显示内容文本」（见上），于是它只剩「把上下午 / 晚间的节次行错开」一个作用，18/14 的高度成了白占的一条空带。现值 = `schedule_grid_view.dart` 的 `_gapHeight = 10.0` / `_compactGapHeight = 8.0`；横版矮列同档收窄 `schedule_horizontal_view.dart` 的 `_gapWidth = 10.0` / `_compactGapWidth = 8.0`（同一语义、同一条用户口径）。**别再往上调**：18/14 是为容纳已删掉的 8px 时长文案而定的。实测（出图工装探针）：矮行高 10.0、节次行高 91.3、整表 1180 无溢出。守卫 = `test/schedule_gap_rows_test.dart`（`gap.height < cell5.height` 且 `≤ 20`）。评审产物：`design_preview/round4_gap_{light,dark}.png`。
- **周数选择器支持直接输入日期（2026-09-17 四轮，用户：「我希望周数选择界面，除了输入周数外，还可以输入日期，跳到对应周数」）**：唯一实现 = `lib/features/ims/schedule/presentation/schedule_week_picker.dart`（用户 2026-09-16 的「点周数开弹窗」形态不变，弹窗里**多一行**日期输入）。
  - 纯函数（同文件顶层，已被导出测试）：`scheduleParseDateInput(String) -> ScheduleDateInput?`（`typedef ScheduleDateInput = ({int month, int day, int? year})`；认 `10-02` / `2026-10-02` / `2026/10/2` / `2026.10.2` / `2026年10月2日` / `20261002`；完整日期必须真的落在日历上，`02-30` 判错）、`scheduleWeekOfDate(parts, {lastWeek, mondayOf}) -> int?`（逐周拿 `mondayOf` 的周一，周一~周日 7 天都比一遍，**周一到周日都算同一周**）、`scheduleWeekOfDateText(raw, {...})`、`scheduleTermRangeText({lastWeek, mondayOf})`（`09-07 ~ 01-24`）。
  - **省年份是常规用法**，跨年学期靠「在学期区间里按月日命中」自动定年（261 学期第 20 周在 2027-01）：同一学期里同一个「月-日」不会出现两次，故无歧义。**不要**改成「拿输入的年去算 week = diff/7」——那要求用户自己判断学年。
  - UI：日期一行 = `scheduleWeekDateInputKey` 输入框 + `scheduleWeekDateSubmitKey`「按日期跳转」（`FilledButton.tonal`，与上方「跳转」并列）；预览行优先跟着日期走（`10-02 → 第 4 周：09-28 ~ 10-04`）。错误就地报、**不关闭弹窗**：格式错 = `认不出日期，如 10-02`；范围错 = `不在本学期范围内（09-07 ~ 01-24）`。
  - **只在本学期可用**：日期 → 周次必须知道第 1 教学周的周一 = `mondayOf`，而它只在「正在看当下学期」时才有（历史学期按既有口径「周次无日期含义」给整学期视图）→ `mondayOf == null` 时日期那一行**整行不渲染**，只留一句「（这个学期没有日期数据，只能按周数选择）」。守卫 = `test/schedule_week_picker_test.dart`。
- **长按回本周 = 横划过去（2026-09-17 用户：「我希望长按周数返回本周要显示横划动画」）**：从前 `_followWeek()` 只在**相邻**周补间（`|current−target| <= WeekPager.jumpThreshold` = 1），跨多周一律 `jumpToPage` 瞬移；长按常常跨十几周，用户看到的就是「唰一下跳过去」。现在**只有外部显式请求平滑时才跨多周补间**：
  - 契约 = `WeekPager.smoothRequest`（int，默认 0）：外部希望这次改周横划过去就 +1（**看序号变化**，不比对周数）；不改成「跨多周一律补间」的原因 —— 弹窗选周 / 切学期是**定位**语义，刷过去会让不相干的周次在眼前掠过。
  - 时长 = `WeekPager.smoothPerPage`(45ms) + `WeekPager.pageTransition`(280ms)：`static Duration smoothTransitionFor(int pages)` = `280 + (pages−1)×45`，夹在 `[280, smoothMaxTransition(700)]`，`pages < 1` 归 1（`lib/features/ims/schedule/presentation/week_pager.dart`）。
  - ⚠ **回声守卫（不加会把自己拽回去）**：补间途中每越过一页都会触发 `onPageChanged`，课表页把它 `setState` 回灌成新的 `week`；`didUpdateWidget` 因此必须 `if (widget.week == _selfReported) return;`（`_selfReported` 在 `onPageChanged` 里先落），否则会对着一页页「回声」反复 `animateToPage`，永远到不了目标。
  - 链路：`schedule_title_bar.dart` 的 `ScheduleWeekSwitcher` 新增 `onReturnToCurrentWeek`（长按走它、**未传时回退 `onGoToWeek`** 保持向后兼容；弹窗选周仍走 `onGoToWeek`）→ `ScheduleTitleBar` 原样转发 → `schedule_screen.dart` 的 `_goToWeek(int target, {bool smooth = false})`（`smooth` 时 `_smoothWeekRequest++`）→ 横版 `WeekPager(smoothRequest:)`、竖版 `ScheduleGridView(pagerSmoothRequest:)` → `SchedulePagedBoard(smoothRequest:)`。
  - 守卫 = `test/week_pager_test.dart`「平滑跳转（长按回本周）」组（时长契约与单调性 / smooth 跨多周补间（途中偏移严格在两端之间）/ 不请求平滑仍瞬移 / 回声不拽回，用文件尾的 `_Host`+`_HostState` 镜像课表页回灌）+ `test/schedule_title_bar_test.dart`（长按走 `onReturnToCurrentWeek`、选周走 `onGoToWeek`、未传时兼容）。
  - ⚠ **测试坑**：`PageView` 的 `cacheExtent` 是 0 → 补间途中**远处的目标页尚未构建**，`find.byKey(ValueKey('page-N'))` 落空、`tester.getTopLeft` 抛 `_getElementPoint`；量「翻到哪了」必须用 `pageOffset(tester)` = `ScrollableState.position.pixels / position.viewportDimension`，**页宽取真实视口**（测试视口默认 800×600 逻辑像素，写死 400 会把结果算成两倍 —— 本轮就这么误判过一次「回声没守住」）。
- **课表正文让开底部系统导航栏（2026-09-17 用户：「我希望课表适应高度不要包括底部三键导航的部分」）**：课表是**恒适应高度、不滚动**的（竖版 12 节铺满、横版可见天平分剩余高度），而 Flutter 的 `Scaffold` **不会**替 `body` 让出系统导航栏 —— `scaffold.dart:3187-3190` 把 `minInsets.bottom` 覆写成「键盘高度或 0」，系统栏只进 `minViewPadding`（那段注释写明仅供 FAB / SnackBar 定位）；`scaffold.dart:2994` 的 `removeBottomPadding` 也只在有 `bottomNavigationBar` 时才去掉 body 的底部 padding。本应用又是 edge-to-edge（§17 的 `home_screen.dart` 口径：`SafeArea(bottom: false)`，靠列表底部 48 内边距兜底）→ 不让位就会把最后一节 / 最后一天盖在三键导航下面（两层 Scaffold：`ims_tab_container.dart:145` 的 `const ScheduleScreen()` 自己一层，`ImsTabContainer` 再一层，都不让位）。
  - 唯一实现 = `lib/features/ims/schedule/presentation/schedule_body_area.dart` 的 `ScheduleBodyArea`（`SafeArea(top: false, child: child)`：顶部由 AppBar 吃，左右沿用 SafeArea 默认）。接线 = `schedule_screen.dart` 的 `body` 里 `Expanded(child: ScheduleBodyArea(child: _buildBody(horizontal)))` —— 加载 / 错误 / 空态 / 下拉刷新都走这一条，**页面级只此一处**。
  - ⚠ **视图里不许再扣一次**：`schedule_grid_view.dart` / `schedule_horizontal_view.dart` 都**不得**出现 `viewPaddingOf(context).bottom` / `paddingOf(context).bottom`（会让位两次、底部白留一条）。`schedule_grid_view.dart` 里那条「Scaffold 已经让过位了，再扣会白留 40~48dp」的旧注释是**错的**（它把 `minInsets.bottom` 当成了 padding，实际是键盘 inset），已改写。
  - 守卫 = `test/schedule_body_area_test.dart`（三键导航 48 → 正文底边 = 屏高−48；不套组件时正文铺到屏底（复现用户报的问题）；`padding.top` 不影响正文顶边；内边距全 0 零变化；左右 30 也避让 + 两条源码守卫）。- **课表课程配色 14 色（2026-09-17 五轮，用户：「感觉课表中课程卡片的颜色不够丰富，可以稍微再添加一两种」）**：色表仍唯一在 `lib/features/ims/schedule/presentation/schedule_tone.dart` 的 `courseFills` / `courseTexts`（**两张表长度必须相等**，`_index = seed % n`，seed = `entry.courseCode.hashCode.abs()`）。前 12 色 = 原 `_coursePalette` / `_textPalette` **逐值未动**（浅色冻结）；新增 2 色按**色相空档**挑，不是凭感觉：原 12 色的深色底色相是 0/0/10/22/38/95/125/185/212/234/254/276（°），最大两处空档 = 276°→360° 与 125°→185° —— 于是加 **玫红 `#F8BBD0` / `#880E4F`**（深色底 `#532B40`、329°、课名压它 7.02:1、与既有 12 色的最小 ΔE76 = **13.2**）与 **青绿 `#E0F2F1` / `#00695C`**（深色底 `#265852`、173°、4.83:1、ΔE **6.9**）。候选里 **橄榄 `#827717`/`#F9FBE7`（ΔE 7.5）与蓝灰 `#37474F`/`#ECEFF1`（ΔE 8.0）未采用** —— 橄榄又是一张暖褐卡（深色下与浅黄 `#564527` 撞调）、蓝灰是中性灰（用户要的是「更丰富」不是更灰）；选色对照板（现状 12 色 + 4 个候选，浅/深两列真实渲染）留档在 `design_preview/schedule_palette_candidates.png`，结论图 `design_preview/schedule_palette_14.png`。
  - ⚠ **扩表会平移已有课程的落点**（`seed % 12` → `seed % 14`）：多数课程颜色会重新分配，颜色**值**不变。这是用户主动要求加色的必然结果，**别当成缺陷去"修"**（真要稳定落点只能放弃 hashCode 取模，那是另一件事）。
  - 守卫 = `test/schedule_dark_tone_test.dart` 的「课程配色扩表」组：14 色 / 末尾两色取值 / **新增色与既有 12 色的深色底 ΔE76 ≥ 6**（反例就在原表里：浅粉 ↔ 浅红只有 **1.6**，肉眼同色）/ 浅底 ΔE ≥ 2.5 且文字压底 ≥ 4.0 / 14 个 seed 拿到 14 个不同底板、`-1` 落回最后一色；既有的「课名压同色相实底 ≥ 4.5:1」「课格底不许太暗」两组自动覆盖新色（最紧的是青绿 4.83:1）。
- **课表课程配色 = 按课程身份发号（2026-09-17 六轮，用户：「我希望优先保证每门课程的颜色都不同，实在不行再重复」）**：唯一实现 = `lib/features/ims/schedule/domain/schedule_color_index.dart` 的 `String scheduleColorKeyOf(ScheduleEntry)`（**课程号优先**，空则退回班级号）与 `Map<String, int> scheduleColorIndices(Iterable<ScheduleEntry>)`（按身份键**去重 + 升序排序**后依次发号 0,1,2,…）。两个视图各在 `_buildDayColumn`（竖版）/ `_buildDayRow`（横版）里 `final colorIndices = scheduleColorIndices(entries);` 算一份（`entries` 是**整学期**课表，按周过滤发生在视图内部 → 跨周稳定），课格取号 `colorIndices[scheduleColorKeyOf(entry)] ?? entry.courseCode.hashCode.abs()`（哈希**只剩兜底**）。
  ⚠ **别再退回 `hashCode % 配色数`**：那是撞色的根源（生日问题 —— 10 门课塞 14 个槽位，「完全不撞」的概率只有约 4%）。实测该账号 2026 第一学期：**10 门课旧口径只用了 7 个色**（1004703634/1005000661、1012100533/1014300174 各撞一组，另有课程号为空的脏行走 `hashCode(空串)` 又撞一个），**11 门课同样只有 7 个色**；新口径分别 **10 / 11**。排序的意义 = 结果只取决于「有哪些课」，与课表接口返回的行序无关 → 换周 / 下拉刷新 / 横竖版切换 / 两个视图之间都不会变色。
  超限行为：课程数 ≤ `ScheduleTone.courseFills.length`（现 14）→ **两两不同**；超过才在 `ScheduleTone._index` 里 `seed % 14` 重复（第 15 门与第 1 门同色）。守卫 = `test/schedule_color_index_test.dart`（10 例：发号口径 / ≤14 门互不相同 / 20 门课的鸽子洞反例留档 / 两个视图渲染层不同色 + 源码守卫），另 `test/schedule_dark_tone_test.dart` 的三处渲染断言已改为按身份号（fixture 只有一门课 → 下标 0）取值。
- **课表行底色一致**（2026-09-16 用户：「课表第五行的颜色和其他行不一样」）：`schedule_grid_view.dart` 里第 5 节（原本当「午休分隔」）曾格外涂色 —— 节次列 `period == 5 ? Colors.grey.shade100 : null`、该行空格`isBeforeNoon ? Colors.grey.shade50 : null`，**两处都已删掉**：12 行底色必须一致，别再引入任何行/列底色；语义底色只保留 `EffectiveMark` 分支（调课 / 停课 / 调走）。守卫 = `test/schedule_period_time_label_test.dart`「12 行底色一致」组（节次列各格 `BoxDecoration.color` 必须同为 null + 源码不含 `isBeforeNoon`）。
- **学期码 `xxy` 与学期选择器**（2026-09-15，用户口径「xxy 代表 xx-(xx+1) 学年，y=1 第一学期、y=2 第二学期、y=3 第二阶段；阵列固定三行、左右延伸、范围可选」）：唯一实现 = `lib/features/school_calendar/domain/school_term.dart` 的 `schoolTermCode(xn, xq)`（= `'xx${xq+1}'`）、`schoolTermFromCode(code)`（严格 3 位数字且末位 1~3，否则 null）、`schoolTermPickerRange({enrollYear, currentYear})`（范围 = 入学年 ~ 当前学年；学籍取不到或不合理 → 当前学年往前 4 年）、`schoolTermsInRange({startYear, endYear})`；UI = `lib/shared/widgets/school_term_grid.dart` 的 `SchoolTermGrid`（行 = 学段、列 = 学年，格子即学期码；`Key('schoolTermRow-N')` / `Key('schoolTermCell-<code>')`）+ `SchoolTermCodeButton` + `showSchoolTermPicker(...)`（弹窗里**纯 Column、无 viewport**，带「当前：<完整学期名>（<码>）」与口径说明）。**手机端学期码按钮 = 纯文字**（用户 2026-09-15 裁定「不要显示边框，不要显示下拉 icon，只显示 xxy 学期的字样」）：`Tooltip > InkWell > Padding > Text`，量宽契约 = `SchoolTermCodeButton.padding`(6) / `fontSizeOf(compact)`，**改字号或内边距必须同步 `ScheduleTitleBar.rowNeed`**；守卫 `test/schedule_title_bar_test.dart`「学期码只有文字：无边框、无下拉 icon」。**手机端课表标题栏（`compact`）= 学期码按钮 + 该弹窗**（学年选择器与学段下拉只在桌面端与 `_buildFilters` 保留）；范围由 `ScheduleScreen._termPickerRange` 算好传入、夹在 `firstYear/lastYear`。**整组恒居中**（用户 2026-09-15「电脑端学年学期选择器居中」→ 拍板「整组居中」；同日追加「移动端的学期切换和周数切换也在标题栏居中」）：`ScheduleTitleBar.build` 恒 `return Center(child: KeyedSubtree(key: scheduleTitleContentKey, …))`（2026-09-16 起手机端也居中，不再分档）；**内容必须包 `scheduleTitleContentKey`** —— 居中后组件自身 RenderBox 会撑满标题槽，量真实内容宽度必须量这个 Key（守卫：`test/schedule_title_bar_test.dart` 的「标题栏对齐」组，按 chrome 56+96 算标题槽中心断言 |Δ|<2）。⚠ `schoolTermCode` 的 `xxy`（用户界面口径，第二阶段 = 3）与 `wxcal_semester.dart` 的 `wxTermCode`（**小程序数据源** term 字段，无暑期段、xq=2 时给 `…2`）**不是一回事**，别互相替换；`schoolTermLabel` 已按 `xqDisplayName` 修正（第二阶段从前被写成「第二学期」）。守卫 `test/school_term_picker_test.dart`。
- **竖版课表周分页板 + 满屏高 + Android 铺满整屏**（2026-09-16，用户三条：「底部有一条通屏宽灰带」·「横划时空顶部周一不动、左侧节数列淡化隐藏、只有主体滑动、松手后节数列出现」·「移动端竖排课表高度与屏幕同高（含那条灰带区域）」）：
  - **分页板唯一实现 = `lib/features/ims/schedule/presentation/schedule_paged_board.dart` 的 `SchedulePagedBoard`**（`weekCount/week/onWeekChanged/header/leading/leadingWidth/bodyHeight/pageBuilder/enabled/fadeDuration`；`leadingHiddenOpacity = 0`）：布局 = `Column[header(静态), SizedBox(height: bodyHeight, child: Stack[Positioned.fill(NotificationListener(WeekPager)), Positioned(left:0, top:0, bottom:0, width: leadingWidth, child: IgnorePointer(AnimatedOpacity(leading)))])]` —— **表头留在分页器外面**，节数列是**浮层**（`IgnorePointer` 必留，否则吞掉拖动/点击）；每页 = `Row[SizedBox(width: leadingWidth), Expanded(pageBuilder)]`，**页面占满整块宽度（含节数列那一栏）** → 拖动时节数列那一栏下面就是**滑动中的课表**（用户 2026-09-16 二轮：「节数列隐藏后不遮挡内容，原节数列位置可以显示被滑动的课表」；初版把节数列放在 `Row` 里占位，那一栏永远是空白）。`AnimatedOpacity` 由 `NotificationListener<ScrollNotification>` 驱动：`ScrollStartNotification.dragDetails != null` → 淡出，`ScrollEndNotification` / `UserScrollNotification.idle` → 恢复 —— **`dragDetails != null` 是刻意的**：点「上一周/下一周」走 `animateToPage`（无 dragDetails）时节数列不闪。
  - `ScheduleGridView` 新增可选分页参数 `pagerWeekCount`（`null` = 不分页：整学期模板 / 桌面 / 横版）/ `pagerEnabled` / `onPagerWeekChanged` / `mondayOfWeek`；传入即走分页板（`pagerOn = pagerWeekCount != null && fitsWidth`）。为此把「左上角格」抽成 `_buildCornerCell`、`_buildPeriodLabelColumn(includeCorner: false)`、`_buildDayColumn(includeHeader: false)`、`_buildDayRow(week:…)`（页主体带 `Key('scheduleWeekRow-<week>')`）、`_buildGrid([int? forWeek])`。**`ScheduleScreen._buildBody` 里竖版周视图不再被外层 `WeekPager` 包**（横版仍包，横版的表头是左侧节次列，暂不拆）。
  - **满屏高**：`_fitCellHeight({..., double? bottomPadding})`（不传 = 旧行为上下同值）；分页模式下 `bottomPadding: 0` 且滚动内边距 `fromLTRB(hPadding, verticalPadding, hPadding, 0)` → 课表一直铺到屏幕底边。**手机端行高恒取适配值**（`_fitCellHeight` 的 compact 分支直接返回 `fitted`，**不设下限**；`_compactCellMinHeight` = 40 只作极端兜底）——用户 2026-09-16 二轮「移动端依旧没有适应高度，内容还是超出屏幕范围」：旧下限 52 仍高于不少机型的内容区（12×52 + 表头 34 + 6 = 664dp）。**内容行按格子总高 `spanHeight = cellHeight * span` 预算**：`roomy = spanHeight ≥ 100` → 课名 3 行 + 教师 + 教室 2 行；`≥ 74` → 课名 2 行；`showTeacher = spanHeight ≥ 58`、`showClassroom = spanHeight ≥ 48`、`classroomLines = slots.length > 1 ? 1 : (spanHeight ≥ 56 ? 2 : 1)`；节次格的「上课/下课时间」在 `cellHeight < _periodTimeMinCellHeight`(46) 时退回只显示节数 —— 否则矮屏上会 `RenderFlex overflowed by 0.5 / 8.5 pixels on the bottom`。**别再自己扣系统导航栏**：`Scaffold` 已用 `MediaQuery.padding.bottom` 给 body 让位（`flutter/lib/src/material/scaffold.dart:1087-1093`：`contentBottom = bottom - max(minInsets.bottom, bottomWidgetsHeight)`），再扣一次会在底部白留 40~48dp。桌面 `_cellMinHeight` 仍 68。**「铺满屏高」的守卫必须量内容**（`Key('schedulePeriodCell-12')` 的 bottom ≈ 网格 bottom）——只量 `ScheduleGridView` 自身 rect 是量不出来的（它恒等于视口，内容溢出时它也是 740）。
  - **Android 铺满整屏（灰带根因与修法）**：`android/app/src/main/kotlin/com/example/smarter_jxufe/MainActivity.kt` 的 `onCreate` 里 `WindowCompat.setDecorFitsSystemWindows(window, false)` + 状态栏/导航栏 `Color.TRANSPARENT` + `isStatusBarContrastEnforced/isNavigationBarContrastEnforced = false`（API 29+）+ `WindowInsetsControllerCompat` 深色图标；`android/app/src/main/res/values{,-night}/styles.xml` 的 `NormalTheme.windowBackground` 从 `?android:colorBackground`（浅色主题下是**灰**，就是那条灰带的颜色）改成 `#FFFFFFFF`。App 是浅色单主题（`main.dart` 只有 `theme:`），故 night 变体也设白。
  - 守卫：`test/schedule_paged_board_test.dart`（6 例：初始无位移 / 拖动中表头纹丝不动 + 节数列淡出且不位移 + 主体左移 + 邻周并排 / 松手恢复（回弹与翻页两种情况）/ 程序化改周不闪 / `enabled=false` 不动 / 常量契约）、`test/schedule_grid_pager_test.dart`（3 例：整表 360×740 铺满且 12 节次格与 7 列头各只一份 / 拖动中表头不动 + 节数列淡出 + 页主体位移 / 翻页后表头与节数列仍在）。
  - ⚠ **测试坑**：`PageView` 跟手位移必须**分两次 `moveBy`**（第一段位移被「起手」touch slop 吃掉，单次 `moveBy` 完全不位移）；量主体位移一律量 `Key('scheduleWeekRow-<week>')`，别量页内文字（多页同时在树上会命中错页）。
- **周数选择器 + 移动端下拉刷新**（2026-09-16 第三轮，用户两条：「移动端课表页取消刷新按钮，改为下拉页面刷新」·「取消周数的左右按钮，但是点击周数，显示一个周数选择器，要可以输入周数/点击直接选择周数」）：
  - **周数 `‹ ›` 已删**：`ScheduleWeekSwitcher`（`schedule_title_bar.dart`）现在 = **纯文字的「第 N 周」按钮**（`Tooltip('选择周数')` + `InkWell` + `Key('scheduleWeekButtonKey')` + 左右内边距 6，**第四轮后连「本周」按钮与视图切换图标也移走/删掉了，见下一条**）；逐周前后翻改由**横滑**（`WeekPager`）承担。唯一实现 = `lib/features/ims/schedule/presentation/schedule_week_picker.dart` 的 `showScheduleWeekPicker(context, {week, lastWeek, currentWeek, mondayOf, compact})` → `AlertDialog`（**纯 Column 无 viewport**）：数字输入框 + 「跳转」（越界**就地报错不关闭**，靠 `errorText: '超出 1 - N'`）、`Wrap` 出的 `1..lastWeek` 格子（点即选中并关闭；本周格子带圆点，选中格主色填充）、`mondayOf` 给出的「第 N 周：MM-DD ~ MM-DD（本周）」预览，actions = 「本周」（`currentWeek != null` 时）/「取消」。`ScheduleTitleBar` 新增 `lastWeek`（页面传 `_lastWeek`，兜底 20）与 `mondayOf: _mondayOfWeek`。**`rowNeed` 随之改**（第四轮后又收窄一次，见下一条的「周次段只剩一个按钮」）。守卫 `test/schedule_week_picker_test.dart`（7 例）+ `test/schedule_title_bar_test.dart` 的周次用例（断言 `byTooltip('上一周'/'下一周')` findsNothing、点周数开弹窗选中即 `onGoToWeek`、长按回本周）。
  - **手机端无刷新按钮**：`ScheduleScreen` 的 `actions` 里 `IconButton(Icons.refresh)` 包在 `if (!compact)` 内（桌面端保留）；手机走 `_wrapRefresh(compact, body)` = `RefreshIndicator(onRefresh: _loadData, child: _refreshable(child))` —— `_refreshable` = `LayoutBuilder → SingleChildScrollView(physics: AlwaysScrollableScrollPhysics) → SizedBox(一屏大小)`，**只包最外层一次**。空课表文案随之改为「可稍后下拉刷新」。
  - ⚠ **内层滚动视图绝不能加 `AlwaysScrollableScrollPhysics`**：探针实测会让分页板翻页阈值从 **0.5 页放大到 1 页**（−220px 不翻页、−400px 才翻；外层包一层则无影响）——即「横滑切周」被弄坏。课表铺满一屏时内层 `maxScrollExtent == 0`、默认 physics 不注册拖动识别器，竖直拖动自然落到外层 `_refreshable`，`RefreshIndicator` 因此拿到 depth 0 的通知。
  - 守卫：`test/schedule_title_bar_test.dart` 的「移动端刷新方式」组（源码守卫：`return RefreshIndicator(` + `onRefresh: _loadData` + `child: _refreshable(child)` 存在，且 `IconButton(Icons.refresh)` 写在 `if (!compact)` 里）。
- **标题栏第四轮：按钮归位 / 「本周」删除 / 整学期无字样 / chrome 不再写死**（2026-09-16 用户四条：「切换整学期/周视图的按钮和调课按钮放到一起，而不是居中」·「感觉不知道哪个组件的边距特别大，导致标题栏总是换行，但是标题栏其实是可以装下那么多内容的」·「整学期视图下，不要显示『整学期』字样」·「标题栏中不显示本周按钮，但是当前周数如果是本周的话，则高亮；同时，长按周数可以回到本周」）：
  - **视图切换按钮移进 `actions`**：`ScheduleScreen.build` 的 `actions` 现在 = `[IconButton(_week == null ? Icons.view_week : Icons.grid_view, tooltip: '切换到周视图'/'切换到整学期视图'), IconButton(Icons.event_repeat, '调课管理'), if (!compact) IconButton(Icons.refresh, '刷新')]`（**顺序即从左到右**）；`ScheduleTitleBar` 的 `onToggleView` 参数**已删**，`ScheduleWeekSwitcher.onToggleView` 变成可选且**标题栏不传**（只有 `_buildFilters` 那条正文筛选栏还传，用于 `showAppBar == false` 的内嵌场景）。
  - **「整学期」字样不显示**：`ScheduleWeekSwitcher.build` 在 `week == null && onToggleView == null` 时 `return const SizedBox.shrink()`；`ScheduleTitleBar.build` 的 `if (week != null) ...[SizedBox(width: gap), weekSwitcher]`（一行/两行两个分支都要写该判定，否则白留间距）。
  - **「本周」按钮删除 + 高亮 + 长按回本周**：`ScheduleWeekSwitcher._isCurrent = week != null && isCurrentTerm && currentWeek != null && week == currentWeek`；命中时文字 `scheme.primary` + `FontWeight.w700` + 主色 12% 底圆角 8（`Container`），否则 `scheme.onSurface` + w600；`InkWell.onLongPress` → `onGoToWeek(currentWeek!)`（`isCurrentTerm && currentWeek != null` 才响应）。`_miniTextButton`（旧的「本周」按钮件）**已删**。
  - **chrome 不再写死 2 个按钮（这就是「有很大空隙却换行」的真因）**：`ScheduleTitleBar.chromeWidthFor({required int actionCount, bool hasLeading = true})` = `(hasLeading ? 56 : 0) + 48 * actionCount`，`fitsOneRow(..., required int actionCount, bool hasLeading = true)` 用它算可用宽度；`ScheduleScreen` 传 `actionCount: actions.length`（手机 2 个 = 152，桌面 3 个 = 200），`_paneTitleBar(titleBar, actionCount)` 的内嵌行宽修正用**同一个** `chromeWidthFor(actionCount: actionCount)`（两边同值正好抵消内部那次减法）。旧常量 `chromeWidth = 152` 只留给旧调用点/测试（= 返回键 + 2 个按钮）。**忘了同步 actionCount 就会重演「明明放得下却换行」**。
  - **`rowNeed` 周次段再收窄**：`weekPart = week == null ? 0 : widest([textWidth('第 20 周', weekFontSize)]) + 12`（不再有 `thisWeekButton` 与 `iconButton`），且 `week == null` 时**不加** `gap`。效果：360 宽手机现在也**单行**（可用 208dp、内容约 130dp；从前被切换按钮 40 + 本周按钮 ~35 顶到两行），250 宽才换行。
  - 守卫：`test/schedule_title_bar_test.dart` 新增/改写 4 例（周次入口长按回本周 + 「本周」findsNothing · 本周高亮主色/非本周非主色 · 整学期视图无「整学期」且无 `scheduleWeekButtonKey` · 源码守卫：`Icon(_week == null ? Icons.view_week : Icons.grid_view)` 在 actions 里 + `actionCount: actions.length` + `ScheduleTitleBar.chromeWidthFor` + 标题栏构造段内**不得**出现 `onToggleView`）；「360 两行」两例改为「360 单行 / 250 才换行」，「手机端（360/460）」同理。
- **课表页 AppBar 按钮 = 紧凑款**（用户 2026-09-16：「标题栏右侧按钮过大」）：唯一构造器 = `lib/features/ims/schedule/presentation/schedule_title_bar.dart` 的顶层 `Widget scheduleBarAction({required IconData icon, required String tooltip, required VoidCallback? onPressed, bool compact = true})`（`iconSize` 18/20 + `visualDensity: VisualDensity.compact` + `padding: zero` + `constraints: minWidth/minHeight 30/34`），课表页三个 action（切换视图 / 调课管理 / 桌面端刷新）都用它 —— **别再写裸 `IconButton`**（M3 默认 48×48、图标 24，用户嫌大）。**量宽契约 = `ScheduleTitleBar.actionWidth` = 40**（实测 `IconButton` 的点击区宽就是 40，`Tooltip` 只包图标故只有 22/26，**量宽要量 `IconButton` 祖先**）→ `chromeWidthFor({actionCount, hasLeading})` = `56 + 40×actionCount`、`chromeWidth` 默认 136（旧 152）。守卫 `test/schedule_title_bar_test.dart`「action 按钮量宽契约」。

- **课表视图选型 / 横竖屏 / 拖动切周 / 教室换行**（2026-09-15 第三轮，用户六条：横版恒适应宽高 · 移动端取消横竖切换按钮改按横竖屏 · 移动端标题栏也居中 · 横滑切周要拖动动画 · 教室放不下就换行 · 学期按钮后加「学期」二字）：**选型唯一口径 = `lib/features/ims/schedule/domain/schedule_view_mode.dart`** 的 `scheduleAutoViewByOrientation(platform)`（Android/iOS = 手机）/ `scheduleViewModeFor({platform,width,height,manualHorizontal})`（手机按横竖屏自动、桌面听按钮）/ `scheduleCompactLayout` / `scheduleMobileInput` / `scheduleCompactBreakpoint`(620)（`ScheduleGridView.compactBreakpoint` 引用它，**只此一份**）；页面里用 `Theme.of(context).platform` 取平台，别写 `defaultTargetPlatform` 分支。**手机端不渲染横/竖切换按钮**（两个视图的 `showToggle` 参数），桌面端保留。**横版课表恒适应宽度与高度**（`schedule_horizontal_view.dart`：12 节次等分可用宽度、7 行平分可用高度、**无任何滚动容器**；行高被压缩时按 `_twoLineNameHeight`(56)/`_twoLineClassroomHeight`(46)/`_teacherHeight`(70) 取舍内容行，绝不溢出）。**竖版行高自适应**：`ScheduleGridView._fitCellHeight({compact,maxHeight,verticalPadding})` 有空间就撑满（底部不留空档）、不够才滚动，最小行高桌面端 `_cellMinHeight` = 68、**手机端恒取适配行高且内容行按格子高预算**（见上面「满屏高」段）。**教室换行**：`classroomLines = slots.length > 1 ? 1 : 2`（同格多门课时留给分隔行与第二门课），别改回恒 `maxLines: 1`。**标题栏恒 `Center`**（手机端同样居中，2026-09-15 追加）；学期码按钮文案 = `SchoolTermCodeButton.labelOf(code)` = `261 学期` —— `rowNeed` 必须用同一函数量宽。**拖动切周 = `lib/features/ims/schedule/presentation/week_pager.dart`**（用户 2026-09-15：「移动端切换周数的动画太奇怪了，我希望就是很自然像手机桌面翻页一样」——`WeekPager` = 一页一周的 `PageView`：**相邻周并排在左右两侧随手指 1:1 位移**、松手按距离/速度 snap（`PageScrollPhysics`）、首末周自然回弹；旧的手写 `week_swipe_wrapper.dart`（跟手 translate + 滑出→硬切→另一侧滑入，滑出时会露出空白）**已删除，别复活**）。`WeekPager` 参数 = `weekCount/week/enabled/onWeekChanged/pageBuilder`；外部改周（上一周/下一周按钮、学期切换、周次夹取）由 `didUpdateWidget` 跟随 —— **相邻一周走补间**（`pageTransition` = 280ms）、**跨多周直接 `jumpToPage`**；`ScheduleScreen` 里整学期视图（`week == null`）不分页，周视图才包 `WeekPager`，每页各算 `mondayOfWeek`。守卫 `test/week_pager_test.dart`（12 例：跟手位移 + 邻页同屏、过阈值 snap、fling 也切页、小幅回弹、首末周不越界、越界夹取、外部改周补间/跳转、`enabled=false` 不响应手势；**量页面位置要按页面的 `Key`，量页内居中文字会把留白当位移**）。守卫：`test/schedule_view_mode_test.dart`（真值表 + 横版铺满 + showToggle）、`test/schedule_week_info_test.dart` 的「课程教室放不下就换行」组、`test/schedule_title_bar_test.dart`（手机端也居中 + `251 学期`）。
- **守卫测试**：`test/school_term_test.dart`（14 例：261 区间 / 寒暑假空档 / 1 月跨年边界 / 快照覆盖范围外返回 null / 与 `resolveTeachingWeek` 协同）、`test/tice_notice_test.dart`（5 例：真实抓包文案、换措辞、JSON/HTML/超长不算提示）。改口径先动这两处。

## 10. 桌面小组件（Android）与「装包前必做」纪律

### 10.1 架构速查

- 形态：**3 指标 × 8 尺寸 = 24 个独立 provider**（`DashboardWidget*` / `ElectricityWidget*` / `GradeWidget*` × `2x1 / 3x1 / 4x1 / 5x1 / 2x2 / 3x2 / 4x2 / 5x2`，见 `android/app/src/main/kotlin/com/example/smarter_jxufe/widget/MetricWidgetProviders.kt`）。**刻意不用「一个可缩放组件」**：华为桌面不保证支持缩放，拆多档用户在添加面板直接就能选到。**历史**：曾只有 2 指标 × 4 档（含 `1x2`），2026-09-11 按用户要求把 `1×2` 改成 `2×1`（横条）并补齐 3×1 / 4×1 / 5×1 / 3×2 与「数据一览」。
- 尺寸档 `enum WidgetSize(cellWidth, cellHeight, metricLayoutRes, dashboardLayoutRes, showSub1, showSub2, dashCells, dashRows, dashFooter)`；派生 `singleLine = cellHeight == 1`、`useShortValue = (this == X2x1)`（最窄档用两字短标题 + 快照里的 `valueShort`，`91.86` 而不是 `91.85965`）。仪表盘网格：2×1/3×1/4×1/5×1 → 1 行 2~5 格；2×2 → 2×2 格；3×2 → 3×2 格；4×2 → 3×2 格 + 页脚；5×2 → 1 行 5 格 + 页脚。
- 布局两套 id 约定（`MetricWidgetRenderer` 按档位只控制可见性，不分支取 id）：
  - 单值卡 `res/layout/home_widget_metric_<tag>.xml`：`widget_root/icon/label/value/unit/sub1/sub2`（6 个恒在）；
  - 仪表盘 `res/layout/home_widget_dashboard_<tag>.xml`：`dash_row1/2`、`dash_cellN` / `dash_cellN_label` / `dash_cellN_value`（N 从 1 起、左上到右下，格数 = `dashCells`，**多一格少一格都会被守卫测试抓到**）、`dash_footer`（仅 4×2/5×2 有）、`dash_message`（整卡空态，恒在）。
  - **单行档**（`singleLine`）放不下第二行：`state != ok` 时渲染器把 `message` 直接写进 `value` 位；多行档才用「`message` 进 sub1 并强制可见」。
- 尺寸元数据 `res/xml/home_widget_<指标>_<档>_info.xml`：`minWidth = cells*70-30`、`minHeight = cells*70-30`（1 行档 = 40dp，2 行档 = 110dp）、`targetCellWidth/Height`、`updatePeriodMillis=1800000`、`previewLayout`；Manifest 里 **24 个 receiver**（`exported=false`）。
- **深色模式（2026-09-11 起）**：颜色**只**在 `res/values/colors.xml` + `res/values-night/colors.xml` 定义（`home_widget_bg/stroke/text_primary/text_secondary/text_muted` 与 `home_widget_accent_{electricity,grade,dashboard}` + `…_muted`）；布局与矢量图**只引用 `@color/…`、禁止写死色值**（守卫测试会扫 16 个布局 + 4 个 drawable）；渲染器取色走 `context.resources.getColor(...)`（命中当前配置，深色自动换值）。浅色点缀色必须等于 `lib/design/feature_palette.dart` 的 `electricity / grade / dashboard`。
- 数据：Dart 快照 `HomeWidgetSnapshot`（`metric/label/value/valueShort/unit/sub1/sub2/state/message/updatedAt/accent/cells`）→ 桥 `MethodChannel('smarter_jxufe/home_widget')` → 原生 `HomeWidgetStore`（SharedPreferences `smarter_home_widget`，键 `snapshot_<metric>` / `auth` / `pending_route`）。认证快照（学号/密码/TGC/JSESSIONID/房间）是给后台 isolate 用的，**后台 isolate 不碰 Hive**。
- **仪表盘（`dashboard`）= 首页「数据一览」同款 5 格**：`cells` 为 `HomeWidgetCell{label,value}` 列表（标签两字：`电费/网费/加权/志愿/今日`，值 `120.9 / 12.5 / 91.86 / 24h / 2 节`，取不到写 `—`）。口径**复用首页面板的 provider**（`dashboardElectricityProvider` / `netFeeSummaryProvider` / `weightedGradeRankingProvider(1)` / `dashboardVolunteerHoursProvider` / `dashboardTodayCoursesProvider`），别再另算一套。
- 刷新：前台 `HomeWidgetSyncScope`（首帧 + `AppLifecycleState.resumed`）+ 原生 `JobScheduler` 周期 16 分钟（job **8802**，`setPersisted(true)` 需 `RECEIVE_BOOT_COMPLETED`）+ 一次性 **8803**（`setOverrideDeadline(20s)`）；「解锁即刷」= `MainActivity` 运行时注册的 `ACTION_USER_PRESENT`（隐式广播不在豁免名单，清单注册收不到）。**后台只更新电费与加权两格**，网费/志愿/今日课程依赖 App 侧会话或本地课表缓存 → 沿用上一次快照的值（`_refreshDashboard` 的 merge 语义），等 App 前台刷新时更新。
- 设置页底部「桌面小组件」节（`lib/features/settings/presentation/settings_screen.dart` 的 `_HomeWidgetCard`，3 指标 × 8 档 = 24 个 `ActionChip`）走 `AppWidgetManager.requestPinAppWidget` 一键固定；华为桌面**支持**该能力（实测弹出「添加主屏幕」确认框，预览卡直接渲染真实数据）。

### 10.2 ⚠️ 已踩过的坑（改动前必读）

- **命名入口点必须定义在 root library**：`DartEntrypoint(bundlePath, 'homeWidgetBackgroundMain')` 不指定 libraryUri 时，Flutter **只在 `lib/main.dart` 里查找**该函数。曾把入口定义在子库 `lib/features/home_widget/data/home_widget_background.dart` → 引擎日志
  `[ERROR:flutter/runtime/dart_isolate.cc(886)] Could not resolve main entrypoint function.` + `runtime_controller.cc(567) Could not create root isolate.` → 引擎「创建成功」但入口没跑，**后台刷新静默失效**（快照永远停在旧值、无任何用户可见报错）。
  现状：入口在 `lib/main.dart`（`@pragma('vm:entry-point') Future<void> homeWidgetBackgroundMain() => runHomeWidgetBackground();`），实现仍在子库。守卫：`test/home_widget_snapshot_test.dart` 的「后台刷新入口点守卫」组。
- **装包前必须校验 APK 的 dex**（本机 Kotlin 增量编译不可信）：pub 缓存在 C:、工程在 D:，Kotlin 守护进程反复报 `Could not close incremental caches … different roots`，曾产出**缺类**的 dex → 装上后 `MainActivity.onCreate` 抛
  `java.lang.NoClassDefFoundError: Failed resolution of: Lcom/example/smarter_jxufe/widget/WidgetRefreshJobService;`
  → **每次启动即崩**（系统弹「smarter_jxufe 屡次停止运行」）。
  三道防线：① `android/gradle.properties` 设 **`kotlin.incremental=false`**（附原因注释，别删）；② 所有系统级调用（`ensurePeriodic` / `registerReceiver` / 引擎创建）一律 `runCatching { }.onFailure { Log.w(…) }` —— **`NoClassDefFoundError` 是 `Error` 不是 `Exception`，普通 `catch (e: Exception)` 抓不到**；③ 装包前用 `System.IO.Compression.ZipFile` 打开 APK，对 `classes*.dex` 逐片 `Latin1.GetString(bytes).Contains('<类名>')` 搜关键类（`WidgetRefreshJobService` / `MetricWidgetRenderer` / 各 provider），全 ✓ 再 `adb install -r -t`。Kotlin 报错时也可 `Remove-Item build\app\kotlin -Recurse -Force` 或 `flutter clean` 强制重编。
- **RemoteViews 布局只能用白名单组件**：`<View>`（哪怕只是当分隔线 / 弹簧）与 `<Space>` **都不在白名单**，宿主 inflate 时报
  `Binary XML file line #N in …: Error inflating class android.view.View`。实测 2026-09-11：12 个单行档（metric 2×1~5×1 + dashboard 2×1~5×1）全灭，由 debug 启动自检抓到。替代：需要弹簧就把 `layout_weight="1"` 给相邻的 `TextView`（标签吃掉剩余空间），分隔线用 1dp 宽的 `TextView` + `android:background="@color/…"`。守卫：`test/home_widget_snapshot_test.dart` 的「白名单」用例（白名单 = LinearLayout / FrameLayout / RelativeLayout / GridLayout / TextView / ImageView / Button / ImageButton / Chronometer / ProgressBar / AnalogClock / ViewFlipper / AdapterViewFlipper）。
- **MethodChannel 参数落盘必须过 `JSONObject.wrap`**：Android 的 `JSONStringer` 遇到不认识的类型（`ArrayList<HashMap>`）会**退化成 `toString()`**，仪表盘的 `cells` 会写成字符串 `"[{label=电费, value=120.9}]"` 而不是数组 → `optJSONArray("cells")` 拿不到 → 卡片只剩「暂无数据」。**自检与单测都过，只有落盘核对能发现**（`adb shell run-as … cat shared_prefs/smarter_home_widget.xml`）。现状：`HomeWidgetBridge.toJson(args)` 统一 wrap；`shapeCheck()` 在 debug 启动时做一次往返验证；渲染器发现 `cells` 不是数组会 `Log.w` 报警。
- `HomeWidgetBridge.selfCheck(context)`（debug 启动时自动跑，`小组件自检: 24/24 OK`）会把 24 个（指标 × 尺寸）组合各 `render` + `RemoteViews.apply` 一次 —— 桌面不一定放着小组件，`onUpdate` 可能永远不被调用，布局/ID 写错会静默潜伏，靠它兜住。另有 `nightCheck(context)`（显式构造 day/night 两个 Context 比对配色，**不能只跟当前配置比**，否则系统本身就是深色时会假通过）与 `shapeCheck()`。
- **桌面分页归启动器管，App 无法命令桌面新建页面**：`requestPinAppWidget` 只提交请求，落在哪一页完全由桌面决定。跨渠道实测（2025-06 第三方对比 + 本机 Mate 30 Pro / HarmonyOS 4.3 亲历）：**「当前页放不下」时小米 / 红米、OPPO、vivo / iQOO、三星会自动新建一页放置，华为 / honor 不会**，只弹系统提示「当前页面空间不足」——**那条提示是桌面弹的，App 拦不掉**。而且**华为不触发** `requestPinAppWidget` 第三个参数（成功回调 PendingIntent，成功也不触发），所以「用户取消」与「桌面满页」在代码里**无法区分**。
  **用户 2026-09-11 裁定：不做任何「满页引导」**（自动弹层必误报，宁可不要）。守卫测试 `test/home_widget_snapshot_test.dart` 会拦 `_WidgetPinGuideSheet` / `桌面放不下` 字样 —— 别再以任何形式加回来。
- **「已在桌面」标记 = `getAppWidgetIds` 计数**：`HomeWidgetBridge.pinnedCounts(context)` 返回 `{「指标:尺寸」→ 该档已绑定实例数}`，键 = 原生 `pinKey(metric, size)` = Dart `homeWidgetPinKey(metric, size)`（两处原文都被守卫测试盯着，改一处必炸）。设置页据此给 24 个尺寸 chip 打 ✓、显示「带 ✓ 的尺寸已经在桌面上，共 N 个。」，并在 `didChangeAppLifecycleState` 回前台时刷新（用户去桌面加/删完再回来）。核对手段：`adb shell dumpsys appwidget` 的 `Widgets:` 段 —— **只数 `provider=ProviderId{…}` 行**，`Providers:` 声明行会让同名类重复计数。

### 10.3 真机（Android）速查

- adb：`C:\Users\Mxster\AppData\Local\Android\Sdk\platform-tools\adb.exe`（**不在 PATH**）；安装 `adb -s <serial> install -r -t build\app\outputs\flutter-apk\app-debug.apk`。
- 强跑后台刷新（测试钩子）：`adb shell cmd jobscheduler run -f com.example.smarter_jxufe 8802`。
- debug 启动自检三连（**改完小组件必看**）：`小组件自检: 24/24 OK` / `小组件数据桥: OK（cells 为数组，2 格）` / `小组件深色模式: OK 底色 #FFFFFF→#1E1E1E …`；另有 `WidgetRefreshJob: onStartJob 收到请求` / `Dart 侧回报 backgroundDone`、`[home_widget] 后台电费刷新成功: … kWh` / `后台成绩刷新成功: …` / `后台仪表盘刷新成功: 电费=… 网费=… 加权=… 志愿=… 今日=…`。
- ⚠️ **`Log.i` 只在 `onCreate` 里**：用 `am start -n …/.MainActivity` 把已在运行的 App 拉到前台**不会**重跑自检（走 onNewIntent）；要看自检必须先 `am force-stop` 再 `monkey -p com.example.smarter_jxufe -c android.intent.category.LAUNCHER 1`（或点图标）。华为的 logcat 主缓冲滚动很快，抓日志要**紧跟着** dump，或轮询到关键字出现为止。
- 深色模式核对：`adb shell cmd uimode night` 看当前模式（`yes`/`no`/`auto`）；临时切换用 `cmd uimode night yes|no`（**会改系统设置，先征得用户同意并及时切回**）。
- 快照落盘核对：`adb shell run-as com.example.smarter_jxufe cat /data/data/com.example.smarter_jxufe/shared_prefs/smarter_home_widget.xml`（**这是唯一能验证 `cells` 等嵌套结构没被写坏的途径**）。
- UI 取证：`adb shell uiautomator dump /sdcard/ui.xml` + `adb pull`（Flutter 语义树常在**第二次 dump** 才出来，第一次为空）；`input tap x y` / `input swipe x1 y1 x2 y2 ms`；截图 `screencap -p` + `view_image`，裁剪用 `[System.Drawing.Rectangle]::new(...)`（`New-Object System.Drawing.Rectangle 0,0,w,h` 会报位置参数错误）。**屏幕熄灭时 `screencap` 只能拍到黑屏**（PNG 只有十几 KB 就是黑屏）——需要用户亮屏解锁。
- Flutter 3.38 嵌入层事实：`FlutterCallbackInformation` **已被移除**（回调句柄那套编译不过）；`FlutterEngine` 构造器不接受 `DartEntrypoint`（单参构造会立刻跑 `main`）→ headless 只能用 `FlutterEngineGroup(...).createAndRunEngine(context, entrypoint)`。查 API 用 `javap -classpath D:\Program\flutter\bin\cache\artifacts\engine\android-arm\flutter.jar <类>`。

## 11. 首页顶栏与账号头像口径（2026-09-11 立）

### 11.1 顶栏只有三样

`lib/features/home/presentation/home_screen.dart` 的 `_buildTopBar(context, scheme)`：

- 左：品牌块（「尼」方块 32×32 + 「智慧尼采」标题）；
- 右：全局设置齿轮（`IconButton(tooltip: '设置')` → `SettingsScreen`）+ **最右账号头像**（`AccountAvatar(radius: 18, tooltip: '我的')`）。

**用户 2026-09-11 裁定（原话）**：「不要在首页左上角显示名字，而是在右上角显示头像，切换角色的按钮取消之，点击头像进入"我的"页面」。落到代码：

- **顶栏不再显示账号名/卡号**（原先那行 `name ?? cardNumber` 已删）——姓名与卡号在「我的」页看；
- **不再有「切换账号」按钮**（`TextButton.icon(Icons.switch_account)` 已删）——账号管理入口 = 「我的」页头部名字右侧的退出图标 → `AccountScreen`（`lib/features/ims/student_info/presentation/student_info_screen.dart` 的 `_header`），另有 `splash_screen.dart` / `unified_mfa_dialog.dart` 里的入口，**别在首页再加回来**；
- 点头像 = `push(StudentInfoScreen())`（带 AppBar「我的」，**不走** `ImsSplashScreen` 的 500ms 会话刷新闸门 —— 那是宫格磁贴的路径）；
- **首页宫格不再有「我的」磁贴**（用户 2026-09-11 追加裁定，原话：「首页宫格视图不要再显示"我的"」）：`home_screen.dart` 的 `_items(context)` 索引 4 的 `ImsTab.studentInfo` 条目与顶层 `_tileColors` 索引 4 的 `FeaturePalette.studentInfo` **同一次删除**（两处按索引对齐，只删一处会让后面全部错色）。IMS 菜单页 `ImsTab.values` 里仍有 `studentInfo`（`ImsTabContainer` 的 `StudentInfoScreen(showAppBar: false)`），**别在宫格加回来**。
- **宫格也不再有「新生入馆教育」磁贴**（用户 2026-09-11 裁定，原话：「我希望『新生入馆教育』的入口改到『蛟湖阅读』页」）：唯一入口 = `lib/features/comprehensive_service/presentation/jh_read_screen.dart` 中部的「新生入馆教育」卡（→ `TsgxsHomeScreen`），`_items(context)` 与 `_tileColors` 的对应条目**同一次删除**（`_tileColors` 索引 9 处留了注释）。机器守卫 = `test/home_tile_alignment_test.dart`（读 `home_screen.dart` 源码静态校验「条目数 == `_tileColors` 条数」）。
- **宫格也没有「获取平台标识」磁贴**（用户 2026-09-11 裁定：「首页宫格里的获取GUID应该放到设置里」）：GUID 入口唯一位置 = 设置页「平台标识」节（`settings_screen.dart` 的 `_PlatformGuidCard`，显示 `wxGuidProvider` 的「已配置 / 未配置」状态 + 掩码后的 GUID + 「去获取 / 查看 / 更新」按钮 → `GuidGuideScreen`）；`_items(context)` 与 `_tileColors` 的对应条目同一次删除（`_tileColors` 索引 14 处留了注释）。
- **蛟湖阅读页 = 三源合一单页**（用户 2026-09-11，二次改版后）：①「四部分进度」= 学分总卡 + 经典阅读 / 普通阅读 / 入馆教育 / 信息素养**各一张进度卡**（`ReadCreditProgressSection` + `ReadCreditPartCard`，`lib/features/read_credit/domain/read_credit_progress.dart` 出数，口径见 `reverse_engineering/阅读学分接口.md` §8）→ ②「学分说明」卡（`ReadCreditRulesCard`）→ ③「学工平台加分记录」（SSP）。
  - **经典阅读的「实际」口径 = 畅想之星平台的个人计数**（用户 2026-09-14 拍板：「把个人口径接进经典阅读进度卡」）：`buildReadCreditProgress({…, cxstar: ReadCreditCxstarProgress})` 的 `cxstar` 参数（typedef `({int books, int minutes})`）由 `lib/features/read_credit/data/providers/read_credit_providers.dart` 的 `_cxstarProgress()` 注入（读 `cxstarOverviewProvider`，**只采信 `overview.personal == true`**——校园网 IP 免密是全校公用账号，实测 2160 册 vs 个人 13 册，当个人进度会严重高估）；此时学分平台的 jd 明细降为**服务端（远端）**那一条（`remote` 只在 cxstar 提供实际值时才给，避免两条数值完全相同的进度条）；没有 cxstar 数据时行为与旧版完全一致。守卫：`test/read_credit_cxstar_progress_test.dart`。
  - **页面不显示账号卡片**（用户 2026-09-14 裁定，原话：「畅想之星页不要显示账号卡片」）：`cxstar_screen.dart` 原先页首的「数据来源卡」（账号名 + 个人/公用账号胶囊 + 「使用统一身份认证登录」/手工令牌/清除令牌）已**整体撤出页面** → 同内容改为 `_SessionPanel` 作为**弹窗**，入口 = AppBar `IconButton(tooltip: '阅读会话', icon: Icons.verified_user_outlined)` → `_CxstarScreenState._openSessionDialog()`（`AlertDialog(scrollable: true, …)`，数据未就绪给 SnackBar）。⚠ **只在落到校园网公用账号时保留一行红字提醒** `_SharedAccountNotice`（可点，同样开会话弹窗）——公用账号是全校汇总值（实测 2160 册 vs 个人 13 册），静默展示会被当成个人进度。守卫：`test/cxstar_auto_refresh_test.dart` 的「不显示账号卡片」group（页面无 `使用统一身份认证登录`/`手工令牌`、有 `校园网公用账号` 提醒、点图标出弹窗、关闭即消失）。别再往页面里加账号/来源卡。**区块顺序固定为 `统计卡 → 找书 · 书架 → 阅读记录 → 说明`**（用户 2026-09-14：「书架卡片应该放到阅读记录上方」；守卫 = 放大视口到 1200×2400 后比较两段标题的 `getTopLeft(...).dy`）。**「阅读记录」标题下不再有操作提示文字**（用户 2026-09-14：「不要显示『点书名即可在 App 内在线阅读（原生渲染，阅读时长同样计入平台统计）。』」；守卫 = 断言 `find.textContaining('点书名即可')` `findsNothing`，别再加回）。**每本书的完成时间与总时长来自 `GET /api/books/{id}/readreport`**（`cxstarBookReportProvider`，个人会话；行内「累计 53 分 · 阅读 2 天 · 14 次 · 完成于 …」+ 行尾 `query_stats` 报告弹窗）；⚠ 平台**只有分钟精度**（秒级接口全 404），且 `/api/user/readings` 的 `ifReadFinish` 恒 null/false —— **读完判据一律用报告的 `isFinish`/`finishReadTime`**（详见 `reverse_engineering/畅想之星接口.md` §11）。
  - 畅想之星平台本体 = `lib/features/cxstar/`（入口：蛟湖阅读页**经典阅读进度卡** → `CxstarScreen`，2026-09-15 起为唯一入口）。**会话三档**：① 统一身份认证（首选，复用项目 CAS TGC → `ua.cxstar.com/uniauth/outLogin/login517` → 个人 JWT，按账号存 `cxstar` box 的 `cxstar_tk_<账号>`，24h）② 手工令牌（高级回退，key `token`）③ 校园网 IP 免密 `POST /api/auth/ip_login`（公用账号兜底）。**业务鉴权 = `Authorization: Bearer <JWT>`**（不是 `userToken`）；接口必须带 `/api` 前缀。全套接口、阅读计时机制（服务端按翻页/取内容累计，客户端不上报时长）与验证记录见 `reverse_engineering/畅想之星接口.md`。
  - **App 内阅读器（原生，不内嵌网页）**：`lib/features/cxstar/presentation/cxstar_reader_screen.dart` 的 `CxstarReaderScreen(bookId, title)`，入口 = `CxstarScreen` 阅读记录点书名。实现要点（**改之前先读 `reverse_engineering/畅想之星接口.md` §7**）：① 阅读器接口要 `nonce/stime/sign`，`sign = md5('123456'+nonce+stime).toUpperCase()`（`cxstarReaderSign()`）；② 每页是**单页 AES-128 加密 PDF**，口令 = `md5('<bookId>-<pageno>')`（`cxstarPdfPassword()`，pdfrx 用 `passwordProvider` + `firstAttemptByEmptyPassword:false` 传入）；③ 渲染走 `pdfrx ^2.2.24`（pdfium），**Windows 构建若报 `pdfium_flutter/windows/CMakeLists.txt` COPY 找不到 `build/windows/x64/pdfium/chromium%2F7520/bin/pdfium.dll`，是 CMake 从 GitHub 下载 0 字节所致 —— 用 `https://ghfast.top/` 前缀手工下 `pdfium-win-x64.tgz` 解压到该目录即可**；④ 时长计入靠 `cxstarReaderHeartbeat`（**60 秒**轻量 `/read` 心跳，仅前台；实测该间隔持续入账，且不必重复拉正文），**每次心跳都刷新底部「今日已计 X 分 · HH:mm 更新」**（用户 2026-09-14 要求「阅读页的时长每分钟更新 1 次」；显示更新时刻是为了区分「没刷新」与「刷新了但平台批量结算还没到账」），翻页防抖 2s 上报续读位；**无「同一页停留超时就不计、必须翻页」的封顶**（2026-09-14 实测同一页 8 分钟逐分钟稳定 +1，翻页后仍约 1/分钟；`readMinutes`/`todayReadMinutes` 会**批量结算**，表现为几分钟不动后一次跳好几分钟，别当计时失效）；⑤ 阅读**必须用个人会话**（`cxstarReaderContextProvider` 拒收校园网公用账号，否则时长记到全校账号上）。守卫：`test/cxstar_reader_test.dart`（含 4 个真实口令向量）。
    - **`pdfrx` 必须显式初始化**（2026-09-14 用户实测报错 `Bad state: Pdfrx getCacheDirectory is not set.`）：`PdfDocument.openData` 走 engine 层，不触发 `pdfrxFlutterInitialize()` → 缓存目录未设。`lib/main.dart` 在 `WidgetsFlutterBinding.ensureInitialized()` 后加 `unawaited(pdfrxFlutterInitialize());`，阅读器 `_CxstarPageViewState._open()` 首行再 `await pdfrxFlutterInitialize();`（幂等）。
    - **翻页页码 = `PageView.onPageChanged` 的索引 + 1（回调是 0 基索引！）**：2026-09-14 用户实测「只能从第 1 页翻到第 2 页，内容变了但底部页码还是 1，并且不能继续翻页，往回翻也不行」= 把它当页码用 → `_currentPage` 恒比真实页码小 1（页码不更新、`onNext` 恒 `jumpToPage(1)` 停在原页、`onPrev` 的 `_currentPage > 1` 恒 false 而禁用、续读位上报少 1）。`_jumpTo(int page)`（1 起）自己落状态，**不依赖 `jumpToPage` 是否派发滚动通知**；`_step(delta)` + `CallbackShortcuts`（`← →` / PageUp / PageDown）供桌面翻页；`_zoomed` 为真时 `PageView.physics = NeverScrollableScrollPhysics()`（否则 `InteractiveViewer` 与 `PageView` 抢手势），换页 / jump 自动退出缩放。实测结论：`InteractiveViewer(panEnabled:false)` 包在 `PageView` 子项里**不影响**拖拽翻页，`jumpToPage` **会**触发 `onPageChanged` → off-by-one 是唯一根因。守卫：`test/cxstar_reader_paging_test.dart`（假数据源驱动真实页面，3 例）。
  - **书架（分类浏览 + 检索）**：`lib/features/cxstar/presentation/cxstar_shelf_screen.dart` 的 `CxstarShelfScreen({initialKeyword})`，入口 = `CxstarScreen` AppBar 的 `Icons.grid_view_rounded`（tooltip「书架 · 找书」）与「找书 · 书架」节的 `_ShelfEntryCard`。数据（**改之前先读 `reverse_engineering/畅想之星接口.md` §9**）：`GET /api/system/categories?pinst=`（**必带 `pinst`，缺则 500**；返回**字典**，`clc` 中图法 22 根 / `subject` 学科 14 / `college` 院系 18，`major`·`sale` 为 null）、`GET /api/categories/{realId}/books?page&size&pinst&sortField=orderno&sortType=DESC&keyword=`（**`categoryId` 非真实分类 id 会退回全库**；检索命中词被服务端包 `<em>` → 域层 `cxstarPlainText()` 清洗）、`GET /api/system/hotSearch?pinst=`；封面 `p.cxstar.com/bookimage*/…_MS.jpg` **免鉴权**可直接 `Image.network`。会话复用 `cxstarReaderContextProvider`（**个人**，校园网公用账号下 `total` 口径都不同：个人 219 vs 匿名 150）。守卫：`test/cxstar_shelf_test.dart`（13 例）。
  - **同一部分只允许出现一张卡**（用户原话：「每个部分显示了好几个卡片…这个四个部分都只显示一个卡片，样式大体是进度卡片」）——原先的 `ReadCreditSummarySection`（学分状态卡 + 5 项行 + 折叠说明）**已删除**，别再恢复。
  - 点卡片：入馆教育 → 原「新生入馆教育」页（`ReadCreditProgressSection.onOpenLibraryEdu` 由 `jh_read_screen.dart` 注入，read_credit 不反向依赖 library_edu 页面）；**经典阅读 → 畅想之星页 `CxstarScreen`**（`onOpenClassic` 同法注入，用户 2026-09-15 裁定「取消畅想之星独立入口，把点击后跳转的页面改成畅想之星」；原「畅想之星 · 经典阅读平台」卡已删，学分平台明细**归并进畅想之星页**的「学分平台 · 经典阅读明细」节，渲染共用 `lib/features/read_credit/presentation/widgets/read_credit_detail_view.dart` 的 `ReadCreditDetailView`——**输出 Column 不自滚动**）；其余两部分（普通阅读 / 信息素养）→ 平台明细页 `ReadCreditDetailScreen`。守卫 = `test/read_credit_progress_test.dart` 的「入口分派」group（含 `jh_read_screen.dart` 源码守卫：不含 `_CxstarCard`）。
  - 蛟湖文化活动不是四部分之一，**并入学分总卡的一个状态胶囊**，不单独占一张卡。
  - 两档口径：平台汇总**只在 5 月 / 11 月更新**，故「实际」一律优先取 App 自有实时源（入馆教育五章闯关、数据中心 `fetchBorrowCountsOnly`），没有自有源的部分才回退平台明细表实时统计。
  - **入馆教育「已通过」的第三种表达**（2026-09-15）：最后一章通过后 `/Web/Exam?cid=` 返回 `302 → /Web/Center/MyGrades`（前 4 章才是 200「已通过本章节考试」），判读用 `tsgxsRedirectIsChapterPassed()`；**别把 3xx 一律当会话失效**（曾因此让末章恒不计入 → 入馆教育卡恒显示 4/5「未完成」）。另：`_eduProgress` 里「取不到状态」= 未知（整体回退服务端值），只有服务端明确 `blocked` 才算未通过。详见 `reverse_engineering/入馆教育接口.md` §6。
  - **一条进度条叠两档（用户 2026-09-11 裁定，四次微调后）**：**浅红** `readCreditActualBarColor(context)` = `scheme.primary.withValues(alpha: 0.30)` = 实际；**深红** `readCreditServerBarColor(context)` = `scheme.primary` = 服务端（两者同色相、靠透明度分层）；**深红覆盖在浅红之上**（`LayoutBuilder` + `Stack` 三层 `Container`）。**服务端标记该项完成时红条直接拉满 100%**，且该行文案变「服务端 已完成」（`_barBlock` 的 `serverPassed: part.remoteMet`，别把满条与 `x / y` 计数写在一起自相矛盾）。术语统一用「服务端」（别再拿「平台」指数据值；平台只用于「学分查询页」这类出处描述）。
  - **总成绩卡 = 四段圆环**（`_CreditRing` + `_CreditRingPainter`，120×120 / stroke 12 / **完成段一律主题红**，`gap = 0.38` 弧度 ≈ 22° 的**明显间隙**，从 12 点顺时针）+ 是否获得学分的胶囊（`bundle.creditGranted`）+ 四部分图例（完成 = 红点 / 未完成 = 灰点）。**圆环亮起与完成计数的唯一口径 = `readCreditPartCompleted(part)`**（实际口径优先，缺席才回退 `remoteMet ?? false`，见 `lib/features/read_credit/domain/read_credit_progress.dart`）；`ReadCreditProgressBundle.completedCount` 不含「蛟湖文化活动」。`readCreditPartColor(kind)` 现在**只给部分卡片的图标盒**用，别再用到圆环/图例上。
- **新生入馆教育页顶部 = 学分平台侧入馆教育卡**（`ReadCreditEduCard`，复用 `ReadCreditPartCard` + 同一个 `readCreditProgressProvider`，不另算一套），下面才是原页面内容（成绩概览 / 五章进度 / 排行榜 / 个人资料）。**底部原「诊断工具」入口与说明性提示文本已按用户要求删除**（2026-09-11；`tsgxs_screen.dart` 调试页文件仍在但已无入口）。

### 11.2 头像 = 绑定账号、只存本机

- **数据**：`lib/features/auth/domain/entities/account.dart` 的 `Account.avatar` 只存**文件名**（如 `0000000.png`，空串 = 未设置）；文件在**应用私有目录** `avatars/`（`accountAvatarStoreProvider` 拿 `getApplicationSupportDirectory()` 后拼 `kAvatarDirName`，目录不存在则创建）。选图时**把原图拷进来** —— 原图随后删/移/换机都不影响头像，卸载才清；**一个账号至多一个文件**（换图先清旧文件）。
- **落盘**：`AccountLocalDataSource.updateAvatar(cardNumber, fileName)` + `AccountRepository.updateAvatar`；`updateDisplayName` 已改走 `Account.copyWith` —— **否则改姓名会把头像字段冲掉**（改数据源时注意）。
- **文件名唯一口径 = `lib/features/auth/domain/account_avatar.dart`**：`avatarBaseName(cardNumber)`（非字母数字 → `_`，空 → `account`）、`avatarFileName(cardNumber, sourcePath)`（扩展名白名单 `png/jpg/jpeg/webp/gif/bmp`，其余归一 `png`）；**别在界面层另拼**。
- **三级回退唯一口径 = 同文件的 `resolveAvatarKind({hasFile, displayName})`** → `AvatarKind.image | initial | placeholder`：本地图片 → 姓名首字 → `Icons.person`（连首字都没有才退图标）。返回的 `initial` 在 `image` 形态下也给出，用作图片加载失败时 `CircleAvatar` 底层 child 的兜底字符（`foregroundImage` 之下永远垫着 child，所以坏图不会留空白圈）。
- **存储层**：`lib/features/auth/data/account_avatar_store.dart` 的 `AccountAvatarStore(Directory)`（**目录构造注入 → 可单测**；`save/resolve/remove/removeAllOf`，删除失败静默不抛）。
- **状态**：`lib/features/auth/data/providers/account_avatar_provider.dart` 的 `accountAvatarProvider` = `ChangeNotifierProvider<AccountAvatarController>`（存储就绪 / `currentAccountProvider` 变化时 `bind`）；**不用 FutureProvider**（异步空窗会让顶栏先闪一次旧头像，同 §3 的偏好存储约定）。
- **共享组件**：`lib/shared/widgets/account_avatar.dart` 的 `AccountAvatar({radius = 18, name, onTap, tooltip})` —— 首页顶栏与「我的」页（`radius: 40`）共用，读同一个控制器实例 → **换图同帧生效**；`name` 传了就用它做首字，不传才订阅 `currentAccountNameProvider`。**头像上不画任何角标**（相机角标已于 2026-09-11 按用户要求删除，见 §11.3）。

### 11.3 换 / 拍 / 移除头像的入口

- **只在「我的」页头像**（用户 2026-09-11 裁定，未选「账户页每卡」与「首页长按」）：点击 → `showModalBottomSheet` → 三项：**「从相册选择」**（桌面端文案自动为「选择图片文件」）/ **「拍照」**（**仅移动端出现**）/ **「移除头像」**（**仅有头像时出现**）→ `enum _AvatarAction { gallery, camera, remove }`（`student_info_screen.dart` 文件尾）→ SnackBar（`头像已更新` / `头像已移除` / `头像操作失败，请重试` / `没有相机权限：请在系统设置里允许本应用使用相机`；取消不提示）。
  **头像上不画相机角标**（用户 2026-09-11 裁定原话：「我的 页头像右下角不要显示拍照，但是点击头像后，除了允许相册，还要允许拍照」）。
- **取图统一走 image_picker**（`pubspec.yaml` 的 `image_picker: ^1.1.2`，2026-09-11 实测解析 1.2.3；**`file_picker` 只留给材料库** `materials_screen.dart:545`）：`lib/features/auth/data/account_avatar_controller.dart` 的 `pick({AvatarSource source = AvatarSource.gallery})` → `ImagePicker().pickImage(source: …, maxWidth: 1080, maxHeight: 1080, imageQuality: 90)`（头像不需要原图分辨率）。`enum AvatarSource { gallery, camera }` 在 `domain/account_avatar.dart`。
- **平台判定唯一口径 = `lib/features/auth/domain/account_avatar.dart` 的 `kAvatarMobilePlatforms = {'android','ios'}` + `avatarMobilePlatformOn(String platformName)`**（纯函数，喂 `TargetPlatform.name`，大小写不敏感）；控制器 `bool get isMobile` 就是它。桌面端 image_picker **没有相机实现**（`image_picker_windows` 源码：`ImageSource.camera` 未注入 `cameraDelegate` 时抛 `StateError`）→ 菜单不出现「拍照」，控制器也硬拦（camera + 非移动端 → `failed`）。
- **Android 相机权限是插件自己请求的**：本应用主清单**没有**声明 CAMERA，但**合并清单里有** —— 由原生依赖 `com.journeyapps:zxing-android-embedded:4.3.0` 带入（看 `build/app/outputs/logs/manifest-merger-debug-report.txt`）；image_picker 的 `ImagePickerUtils.needRequestCameraPermission` 判据正是「清单里有没有 CAMERA」，所以点「拍照」会**先弹系统权限框**，被拒抛 `PlatformException(code: 'camera_access_denied')` → 顶层纯函数 `avatarResultForPickError(Object)` 映射成 `AvatarActionResult.permissionDenied`（**别把它并进 `failed`**，否则用户只会看到无用的「请重试」）。**不要为了拍照去主清单加 CAMERA**（加了反而把权限责任揽到自己身上）。
- `currentAccountNameProvider` 已从 `home_screen.dart` 迁到 `lib/features/auth/data/providers/account_display_name_provider.dart`（共享头像件要用，不能让共享件反向 import 首页）。
- **守卫测试**：`test/account_avatar_test.dart`（**21 例**：文件名清洗 3 / 扩展名归一 3 / 三级回退 4 / 私有目录的存-删-换-不自杀 6 / 移动端平台白名单 3 / 选图异常映射 2）。改口径先动它。

## 12. IMS 全局会话口径（成绩 / 课表 / 毕业学分 / 培养方案 / 我的 共用 · 2026-09-11 立）

**用户诉求（原话）**：「成绩/课表/毕业学分/培养方案/我的 界面都不要强制重新登录 ims，而是同样用全局一个维护的 ims 实例……全局仅实现一个 ims 实例（当然，切换账号要销毁重建这个对象）……重启应用/小组件访问时也不能销毁这个对象，要持久化」。

**唯一实例 = `lib/features/ims/auth/data/ims_session.dart` 的 `ImsSession`**，由 `lib/features/ims/auth/data/providers/ims_session_provider.dart` 的 `imsSessionProvider`（手写 `Provider`，**同步**——十几个数据源要同步 `ref.watch(currentImsDioProvider)` 取 Dio）持有。

- **一个 Dio**：`createImsDio()`（`lib/core/network/ims_dio.dart`）**成对创建 Dio + `ImsAuthInterceptor`**，`currentImsDioProvider` 只取它的 `.dio` → 所有教务数据源共用一份会话与一个重试拦截器。**禁止**再引入「全局单例拦截器 + `setDio`」：多账户并存时后建的 Dio 会覆盖重试目标（历史 bug）。
- **零请求进入（本次改造核心）**：`ImsSplashScreen._enter()` 调 `session.ensureReady()` —— 本地有会话就**一个请求都不发**直接进页面；真失效由拦截器在业务请求上发现 → `session.renew()`（`_inflight` **并发去重**，多个请求同时踩失效只换一次票）→ 用新票重试原请求。**不要把 splash 改回无条件 `refreshJsessionId()`**：那正是用户反馈的「每次进任一 IMS 功能都强制重新登录」；旧代码还没有 try/catch，CAS 一失败就永远停在「加载中…」。换票失败时给「重试 / 先看本地缓存」，不困住用户。
- **续期唯一实现**：`lib/features/ims/auth/data/ims_session_renewal.dart` 的 `fetchAndActivateJsessionId({imsDio, redirectUrl, gid})` = 取票（`/jxcjcaslogin` 的 `Set-Cookie`）+ **用新票访问 CAS 回跳地址激活**（少了第二步教务仍视为未登录）。App 侧 `ImsSession.renew()` 与桌面小组件 `home_widget_background.dart` **共用**它，别再写第二份；App 侧多一层 `AuthRepository.getImsRedirectInfo()`（TGC 过期会用缓存凭据静默重登），小组件侧只有 TGC。
- **持久化按账号**：`imsAuth` box 键 = `JSESSIONID|<账号>`（另有 `…|at` 记落盘时间），实现 `lib/features/ims/auth/data/datasource/ims_auth_local_datasource.dart`。历史版本是无账号单键 `JSESSIONID`（切号必串号），`migrateLegacy()` 把它**只**认领给第一个读到的账号。**`release()`（provider dispose / 切号）只清内存、绝不动磁盘** —— 这是「重启应用 / 小组件访问也不丢会话」的关键；只有 `forget()`（退出登录）才删磁盘。
- **切号 = 会话销毁重建**：`imsSessionProvider` watch `currentAccountProvider`，账号一变整个实例（Dio / 拦截器 / 内存会话）重建。`lib/features/ims/student_info/presentation/account_screen.dart` 的切号流程**不要**再调 `imsAuthRepo.logout()`（会删掉刚登录账号的会话）或 `studentInfoRepo.clearCache()`（已按账号隔离，清了白清）；且必须在**设置账号之后**重新 `ref.read(studentInfoRepositoryProvider.future)`（切号前拿到的仓库绑的是旧账号的 box）。
- **个人数据按账号隔离**：`lib/core/storage/account_scoped_box.dart` 的 `openAccountScopedBox(base, account)` → box 名 `<base>_<账号>`，账号未确定用 `<base>__none`（**故意不回落到旧无账号 box**，避免未登录就露出上一个账号的数据）；旧 box 被第一个账号迁移认领一次（`claimedKey = '__migratedTo'`）。已接入：`gradesCache`（成绩）、`studentInfo`（学籍）、`scheduleReschedules`（调课，经 `RescheduleRepository({account})` + `RescheduleStore.bindAccount` 清内存缓存）、`score_estimate`（分数估计）、`zongce`（综测）。**公共数据不隔离**：`curriculums`（按年/学院/专业）、`colleges`/`majors`、`periodTable`、`scheduleCache`（key 里已含 `studentId`）。新增个人数据 box 一律走 `openAccountScopedBox`。
- **门面**：`ImsAuthRepository` 只剩 `Either` 适配（`getJsessionId({forceRefresh})` / `refreshJsessionId()` / `logout()`），**不再持有任何状态**；成绩 / 学籍 / 培养方案 / 毕业学分 / 加权五个仓库都经它取票，`getJsessionId()` 本来就是「有缓存即返回、不发网络」。
- **守卫测试**：`test/ims_session_test.dart`（13 例：零网络 / 换票两步与落盘 / 并发去重 / 失败可重试 / release 不动磁盘 / forget 才清盘 / 切号不借用他人会话 / 会话键账号隔离与旧键只认领一次 / box 隔离与迁移）。改会话口径先动它。

### 12.1 统一登录（CAS）按账号持久化口径（2026-09-11 立）

**用户诉求（原话）**：「统一登录也要像上面说的一样，持久化，相当于对于每个账号，统一登录和 ims 都只有一个入口」；并拍板：「TGC 有效就直接用，免密码免 MFA；TGC 失效才用保存的密码静默重登」。

- **按账号落盘**（`lib/features/auth/data/datasources/auth_local_datasource.dart`）：`auth` box 键 = `TGC|<账号>` / `CACHEDUSER|<账号>` / `CACHEDPASS|<账号>`；API 一律带账号 —— `saveTgc(account, tgc)` / `getTgc(account)` / `deleteTgc(account)` / `saveCachedCredentials(account, password)` / `getCachedCredentials(account)`。历史无账号单键 `tgc` / `cachedUser` / `cachedPass` 由 `claimLegacyCredentials(account)` **认领给 `cachedUser` 记着的那个账号**（不匹配就不动旧键、认领后删旧键、旧 `cachedUser` 为空则不认领）——归属靠旧 `cachedUser` 精确判定，不会张冠李戴。**真机实测**：老用户升级后 `auth.hive` 里出现 `TGC|2000000002` / `CACHEDUSER|2000000002` / `CACHEDPASS|2000000002` ✓。
- **两个 provider（`lib/features/auth/data/providers/`）**：
  - `authRepositoryForAccountProvider`（**手写** `FutureProvider.family<AuthRepository, String>`，`auth_repository_for_account_provider.dart`）= 指定账号的 CAS 仓库（先 `claimLegacyCredentials` 再 `AuthRepository(account: …)`）。**刻意不用 autoDispose**：`imsSessionProvider` 会 `ref.read` 它，自动销毁会丢掉在途 future。
  - `authRepositoryProvider`（`@Riverpod(keepAlive: true)`）= 当前账号的**唯一入口**，`watch(currentAccountProvider)` 后转发 family。业务代码一律用它；只有 `ims_session_provider.dart` 的 `_resolveRedirect(ref, account)` 直接按会话账号取 family（切号瞬间 `authRepositoryProvider` 可能还在重算）。
- **读盘按账号、写盘按入参账号**：`AuthRepository(account: …)` 构造时只读该账号那份 TGC/凭据；`login(username, …)` / `cacheCredentials(username, …)` 的落盘键用**入参 username** → 「当前是 A、正在登录 B」的切号流程不会写串。
- **免登录闸门 = `AuthRepository.isTgcAlive()`**（一次 CAS 探测，**绝不触发重登**）：`splash_screen.dart` 与 `account_screen._switchAccount` 为 true 时直接 `_enterHome(cardNumber)` / `_completeSwitch(context, ref, account)`（两者都是：设 `currentAccountProvider` → **重新**取 `studentInfoRepositoryProvider` → 刷显示名 → 跳首页），**免密码免 MFA**；false 才走原来的 `prepareLogin → detectMfa → login`（必要时弹 MFA）。**不要拿 `getImsRedirectInfo()` 当闸门**——它 TGC 过期会静默重登，等于每次启动都重登一遍。
- **⚠️ 假阳性陷阱（别删这段判断）**：`AuthRemoteDataSource.getRedirectImsUrl` 对**任何** `Location` 都算成功，而 CAS 会话失效时可能 302 回 `…/cas/login;jsessionid=…` → 会被误判成「TGC 有效」→ 拿死票免登录。`isTgcAlive()` 里显式把「Location 指回 `/cas/login`」判为失效（守卫测试覆盖）。
- **TGC 捕获两条分支都要**：`login()` 的 302（Set-Cookie）与 200+「登录成功」（MFA 后）都调 `_captureTgcFromCookies(response, username)`；只认 302 会让 MFA 用户的票永远落不了盘（`_tgc` 恒 null → 闸门永远 false）。200 分支没带 Set-Cookie 时行为不变。
- **桌面小组件**：`home_widget_sync.pushAuthSnapshot` 的 `tgc` 读本账号 `authDs.getTgc(account)`。
- **守卫测试**：`test/auth_session_account_test.dart`（17 例：TGC/凭据按账号隔离、旧单键精确认领与幂等、读盘按账号、切号不写串、重登用本账号凭据、闸门四态（无票 / 有效 / 过期 / 网络错）、CAS 打回登录页的假阳性、200 分支捕获 TGC）+ `test/auth_trust_device_test.dart`（8 例，调用点已随签名更新：`saveTgc('账号', 'tgc')`、`AuthRepository(account: …)`）。改口径先动这两处。

### 12.2 教务令牌的手动刷新 —— 设置页「教务会话」节（2026-09-15 立）

**用户诉求（原话）**：「我们需要一个在设置里刷新 ims 登录令牌的按钮」；随后问答裁定：语义 = **先探活、失效才换**（不是无条件换票），且卡片要把当前状态与令牌显示出来。

- **落点**：`lib/features/settings/presentation/settings_screen.dart` 的「教务会话」节（`_ImsSessionCard`，排在「平台标识」与「桌面小组件」之间），节颜色 `FeaturePalette.imsSession`（`#00695C`）。**设置页是唯一入口**（§3「全局偏好一律收拢到设置页」）。
- **判定口径 = `lib/features/ims/auth/domain/ims_token_refresh.dart`（纯逻辑，唯一实现）**：`enum ImsProbeResult { alive, expired, noSession, unknown }` → `ImsTokenRefreshActionFor()` → `enum ImsTokenRefreshAction { keepCurrent, renew }`。**只有 `alive` 走 `keepCurrent`**；`expired` / `noSession` / `unknown` 一律换票（unknown 也换：用户按这个按钮就是要一张能用的令牌，在按钮上原地报错没用）。同文件还有 `imsProbeBodyLooksValid` / `maskImsToken` / `imsProbeLabel` / `imsRefreshOutcomeText`。
- **探活实现 = `ImsSession.probe()`**（`lib/features/ims/auth/data/ims_session.dart`）：`GET /jw/common/getStuGradeSpeciatyInfo.action?xh=`（最小、**不依赖学生号**——实测传空也返回本生数据），手工带 `Cookie: JSESSIONID=<token>`。
  - ⚠ **必须用 `ResponseType.bytes`**：`ImsAuthInterceptor.onResponse` 只认 `data is String`，用 bytes 它就不会把我们的探活偷换成「自动换票 + 重试」——**探活结论必须原样交给调用方**，否则「先探活」这个口径在代码里等于不存在。
  - 判据方向**不能反**：`jwSessionExpired`（547 字节 UTF-8 alert 页）→ `expired`；`{` 开头且能 `jsonDecode` 成 Map → `alive`；其余 → `unknown`。**宁可 unknown（进而照样换票），也不能把登录页 / 半截页当成有效** —— 把失效当有效，用户会以为修好了、业务页却仍然打不开。
  - 配套新增 `ImsSession.peek()`：只读（内存 → 磁盘）看一眼令牌，**不发请求、也不换票**；卡片首屏用它（`ensureReady()` 在本地没有令牌时会顺手走一次 CAS 换票，**打开设置页不该触发登录**）。`probe()` 内部也走 `peek()`。
- **实测（2026-09-15，打实时教务）**：真令牌 `633DA58E…` → `alive`（HTTP 200 / **232 字节** `{"status":"200","message":"操作成功!",…}`）；伪造 32 位令牌 → `expired`（547 字节 alert 页）；无本地令牌 → `noSession`。三个分支都有真数据证据。
- **界面口径**：状态胶囊（读取中 / 已就绪 / 未就绪 / 不可用 / 刷新中）+ 掩码令牌（`maskImsToken`，前 8 位）+ `账号 <卡号> · 签发 <HH:mm:ss>`（`issuedAt` 在重启后为 null → 显示「签发时间未知（本次启动尚未换票）」）+ 最近探活结论 + 最近一次失败原因；按钮「刷新登录令牌」busy 时禁用；结果走 SnackBar（`imsRefreshOutcomeText`：**令牌仍有效时不谎称「已刷新」**）。切换账号 → `imsSessionProvider` 重建 → 卡片用 `ref.listen` 清掉本地状态。
- **守卫测试**：`test/ims_token_refresh_test.dart`（12 例：判定表四态 / 响应判据方向 / 掩码与文案 / 源码守卫「probe 必须在 renew 之前，且 renew 必须被判定表守住」）+ `test/ims_session_card_test.dart`（3 例：有令牌显示掩码且**打开页面不换票** / 无令牌显示未就绪 / 按按钮判不出时照样换票、失败落在卡片与 SnackBar）。改口径先动这两处。

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
- 抓真实响应的方法：`D:\Temp\vmprobe\grad_probe.py`（连 VM Service 让 app 用**自己的** `ImsSession` 去 POST，票据不出 app，HTML 落 `D:\Temp\grad_raw.html`）—— 比从 Hive 里挖 JSESSIONID 安全。

## 14. 教务「公共查询」口径（教师 / 班级 / 教室 / 课程课表 + 多班对照找无课时间 · 2026-09-14 立）

**用户诉求（原话）**：「教务系统-公共查询 里面可以找到按教师按班级按教室的各个课表，我希望你全部实现，并添加一个对照多个班级的课表，找出无课时间的功能」。
入口 = **首页宫格「公共查询」磁贴**（`Icons.travel_explore_outlined`，`FeaturePalette.publicQuery = 0xFF4527A0`）；整页 = 4 类别分段 + 学期下拉 + 级联筛选 + 结果网格 + 「多班对照 · 找共同无课时间」。
**完整接口规格见 `reverse_engineering/公共查询接口.md`（改这个模块前必读）**，这里只记最贵的坑。

### 14.1 ★ 报告端点只认 urlencoded（本任务卡最久的坑）

`POST /kbbp/dykb.GS1.jsp?kblx=<kckb|jskb|bjkb|jsikb>` 是**普通 JSP**，不解析 multipart：
用 dio `FormData`（= multipart）提交时服务端 `request.getParameter()` **一个参数都拿不到** →
报表以「无过滤条件」跑一遍 → **恒返回 `没有检索到记录！`（HTTP 200，2652 字节）**，
看起来像「参数不对」，其实是**传输层错了**。
**必须手工拼 urlencoded 字符串体**（`PublicQueryRemoteDataSource.encodeForm`，同 `period_table_remote_datasource.dart`）。
> 对照组：`/frame/droplist/*.action`（Struts2）与 `/taglib/*.jsp` **能**吃 multipart，所以只有报告端点静默空结果。

### 14.2 其余四条字段铁律

1. **`hidFlag` 一律为空**，唯一例外是教师课表 `hidFlag=ggcxjskb`。`smxbjkb` / `smxjskb` 是
   `G_SCHOOL_CODE=="10842"`（三门峡职业技术学院）专属分支，照抄 → 恒空。
2. **`menucode` 发首字母 `S`**（页面 JS `menucode.substring(0,1)` 后再提交），不是 `SB03`。
3. **`pkts`（排课套数）必须现取**：`POST /KB_ExpTeacherSchedualAction.do?hidOption=getpkts&xn=&xq_m=`
   → 纯文本数字（江财当前 `7`）；留空 → 报表恒空。页面 `initPage()` 也先跑这一步。
4. **两套学年学期码勿混**：公共查询报告用 `Ms_KBBP_FBXQLLJXAP` 的**逗号**码 `2026,0`（发进 `xnxq`）；
   `StMsXnxqDxDesc` 的 `2026-0` 是老分支用的。`parseTermCode` 两种都吃。

另：响应编码三分——报告 = **GBK**（`Content-Type` 不带 charset，必须 `ResponseType.bytes` + `fast_gbk`）；
下拉 JSON 与选择器 XML = **UTF-8**；教室课表不带过滤时一次 **1.7MB / >20s** → `receiveTimeout` 固定 150s。

### 14.3 选择器与「码空间」陷阱

模糊选择器 `POST /taglib/CombBoxServlet.jsp`（`className` + `loadDataStyle=loadClass`）：
班级 `kbbp_dykb_SpecialClassComb`（参数含 `nj&xqdm`）、教师 `jbxx_EmployeeAndTeacher`（`jsbm`=部门码）、
课程 `jw_comb_coursename`、教室 `jxap_combbox_js`。
下拉列表 `POST /frame/droplist/getDropLists.action`：学期 / 校区 `MsSchoolArea` / 楼房 `MsSchoolArea_LF` /
**教室 `MsSchoolArea_LF_JS`**（`paramValue="xq_m=<校区>&jslx_m=&lf_m="`） / 部门 `MsDepartment` / 学院 `MsYXB` / 专业 `MsYXB_Specialty`。

- **班级码必须与所选校区配套**（选择器要带 `xqdm=<校区>`）：拿 A 校区班级码查 B 校区 → 恒空。
- **教师码 ≠ 学生课表里的 `[教师码]姓名`**：报告要的是 `jbxx_EmployeeAndTeacher` 的 value（`101599` / `t201600026035`）。
- **课程码 ≠ 课程代码**：`hidKCDM` 要选择器给的内部 id（`2020613`），不是 `1004703634` / `[0004504882]`。
- **教室别用 `jxap_combbox_js`**（带 `lf_m` 恒返 55 字节空表）→ 用 `MsSchoolArea_LF_JS` 下拉的 code
  （`1000752`=蛟三教3101），提交时 `hidCXLX=fjsi` + `hidFJBH` + `selJSMC` 同码、**`selLF/hidLF` 留空**。

**班级课表的三层码空间（2026-09-14 补齐，全部实测）：**

| 层 | comboBoxName | paramValue | 值域 |
|---|---|---|---|
| 学院 | `MsYXB` | `nj=<学年>` + **`isYXB=0`** | 学院代码 `dwh`（会计学院 `05`，显示 `[040]会计学院`）；**`isYXB=1` 恒返 `[]`** |
| 专业 | `MsYXB_Specialty` | `nj=<学年>&dwh=<学院码>` | 专业代码 `zydm`（会计学院 9 个：`0509` 会计学 … `0518` 会计学(第二学士学位)） |
| 培养层次 | `MsCodeset` | `DM-PYCC` | `01`博士 `02`统招本科 `03`硕士 `04`对口本科 **`05`本科** `06`专科 `07`中专 `08`专升本 |

- **这三层同时喂给班级选择器**（`comboParams` 的 `yxb`/`zy`）：`nj=2026&xqdm=1` → 25 个班，加 `yxb=05` → **2 个**，
  加 `zy=0518` → 仍 2 个（该专业 2026 级就这 2 个班）；`yxb=05&zy=0509` → **0 个**（会计学 0509 该年级无班，**不是接口错**）。
- **培养层次 `selPYCC` 是真过滤条件，不要写死 `05`**：同一本科班级 `05`→13034 字节命中、`02`（统招本科）→**2656 空**、
  空串→13034（= 不限，与 `05` 对本科班等价）。客户端原样提交用户所选值，默认 `05`，下拉首项「不限」。

### 14.4 报表结构与解析（`parsePublicTimetableReport`）

`<div group="group">` 描述块 + `<!-- 报表区 -->` + `<table class='table' id='mytableN'>`（**一表 = 一个对象**）。

- 格子 `div1` 的 **id = `<表序号><星期><大节序号>`**（表序号 ≥10 为两位，如 `1011`）→ 星期/大节**从 id 反推**，别数行列。
- 大节 → 实际节次**用行标签还原**（江财 = `1-2 / 3-5 / 6-7 / 8-9 / 10-12` 五档），别假设每档 2 小节。
- 文本按 `&ensp;` 切片（`&amp;ensp;` 也要认）；对象名要**精确匹配标签**（`教室类型` 也以「教室」开头，前缀匹配会取成「设计室」）。
- 空结果两种文案都要认：`没有检索到记录！`（GS1）与 `没有符合检索条件的记录！`（GS4）。

### 14.5 客户端落点与守卫

`lib/features/ims/public_query/{domain/{public_query.dart,public_timetable.dart,free_time.dart},data/{datasources,providers},presentation/{public_query_screen.dart,public_timetable_view.dart,free_time_view.dart}}`；
provider family 的键 = `PublicQueryRequest`（已实现值语义 `==`/`hashCode`/`cacheKey`，**`trainLevel` 也进缓存键**）。
班级课表筛选行（2026-09-14 补）：**校区 → 年级 → 培养层次 → 学院 → 专业 → 班级**；
`_trainLevel` 默认 `'05'`、下拉首项「不限」；`_major` 走 `publicQueryMajorsProvider('<年级>|<学院>')`（未选学院则该行禁用且不发请求）；
级联清空：切类别清 `_department/_major/_class/_compareClasses/_teacher/_course/_roomEntry`、换年级清 学院/专业/班/对照、换学院清 专业/班/对照、换专业清 班/对照。
守卫测试四件套（**真实 fixture**：`test/fixtures/public_{bjkb_class,jskb_teacher,kckb_course,jsikb_rooms}.html`）：
`public_query_test`（35）、`public_timetable_parser_test`（19）、`public_free_time_test`（23）、
**`public_timetable_view_test`（4，渲染守卫，见 §14.6）**。
应用内实证方法：VM Service 取真实容器 → `container.read(publicQueryReportProvider(req).future)` 后 `debugPrint('SJX_PQ …')`
（脚本 `D:\Temp\vmprobe\sjx_pq_probe.py`；三层筛选脚本 `sjx_pq_probe2.py`；推屏幕用 `sjx_nav_probe2.py`）。

### 14.6 ⚠️ 结果「查到了但看不到课表」的两个真因（2026-09-14 用户实测后修，改动前必读）

用户原话：「公共查询里面为什么查询成功后只显示『查询到 1 个课程的课表』，而不显示具体的课表」。

1. **网格行不能用 `CrossAxisAlignment.stretch`（最贵的一条）**：`public_timetable_view.dart` 的 `_row` 原本写
   `Row(crossAxisAlignment: CrossAxisAlignment.stretch, …)`，而卡片挂在**滚动页的无界高度**里（`ListView` 子项 →
   `constraints.maxHeight == Infinity`）→ `RenderFlex` 对非弹性子项用
   `BoxConstraints.tightFor(height: constraints.maxHeight)` → 左侧行标签 `SizedBox(width: 40)` 收到
   **`BoxConstraints(0.0<=w<=Infinity, h=Infinity)`** →
   `Exception: BoxConstraints forces an infinite height.`（`RenderConstrainedBox` 被 `ChildLayoutHelper.layoutChild` 喂了非法约束）
   → 沿父链（`RenderFlex → RenderPadding → … → RenderOffstage`＝ExpansionTile 展开体）连锁 `RenderBox was not laid out`
   → **整张卡片布局失败、网格整片空白**（计数行照旧显示，因为它是同一 `ListView` 里更早的子项）。
   现状 = `CrossAxisAlignment.start`（格子按 `minHeight: 46` 自然撑高，行高不依赖父级有界）。
   **自查**：想在无界高度里让同一行等高，只能给行一个**有界高度**（本仓库既有课表页 `schedule_grid_view.dart` 的写法 =
   `SizedBox(height: _cellMinHeight)` 固定格高 / `IntrinsicHeight`），**绝不能裸用 stretch**。
2. **班级课表曾被 `if (_kind != PublicQueryKind.klass)` 挡在结果区之外**：选了班级查出来只有「多班对照」卡、没有那张班的课表。
   现状 = 班级类别也走 `_resultSection`（顺序：筛选条件 → **该班课表** → 多班对照卡 → 空闲时段）。

**排查手法（可复用）**：日志里出现 `BoxConstraints forces an infinite height` + `RenderBox was not laid out` 连锁时，
先怀疑「无界高度 + stretch」；`Ext.flutter` 之外的实证用 VM Service 探针按 widget 名统计
（`D:\Temp\vmprobe\sjx_pq_dump.py` 打印树上所有 Text + `PublicTimetableCard`/`ExpansionTile` 计数；
`sjx_pq_state.py` 读写当前屏 State 的 `_kind/_campus/_class`；`sjx_scroll_bottom.py` 把滚动区拉到底再看屏）。
⚠️ 探针读到的控件树是**上一帧**的：窗口被遮挡时 Flutter 可能不产帧 → 先 `sjx_shot.ps1` 把窗口置顶（顺带出截图）再读，否则会看到过期文案。

**未做**：SB05 周/日/节次课表、SB06 全校课表、SB11/SB12/SB13 空闲教室（用户未要求）。

### 14.7 账号默认预填 + 卡片纯白（2026-09-14 二轮，用户要求）

用户原话：「卡片背景换成纯白（不要硬编码，而是用主题里是纯白的颜色）」「按班级查和按教室查的校区、学院、专业、班级都默认设为当前账号的校区、学院、专业、班级」。
拍板三项：① 校区 = **「我的校区」偏好 + 在该校区查不到你的班时自动切到对的那个**；② **年级也默认成学籍入学年**；③ **每次打开页面都强制重置成账号默认**（不保留上次手选）。

- **纯匹配层 = `domain/public_query_defaults.dart`**（无 IO）：`matchPublicQueryOption(options, wanted)`（归一化 = 剥 `[码]` 前缀 + 去全部空白 + 全角括号转半角 + 小写；**精确 > 前缀 > 包含**，同级取更短者；找不到返回 null，**绝不返回「差不多的那一项」**）、`publicQueryGradeOf(enrollYear, baseYear)`（只取 `baseYear ~ baseYear-4`，超范围回退学年）、`resolvePublicQueryAccountDefaults(...)`。
- **⚠️ 年级 `nj` 必须用学籍入学年 `<rxnj>`，不是学年**：2025 级的班只在 `nj=2025` 的列表里，`nj=2026`（学年）里没有 → 学院/专业/班级三项默认全靠它。实测 `nj=2025&xqdm=3` → 83 条含 `[2508090D52]计算机科学与技术252`；`nj=2026&xqdm=1` → 25 条（与 §14.3 一致）。真实学籍值：`enrollYear=2025` / `college=计算机与人工智能学院` / `major=计算机科学与技术` / `className=计算机科学与技术252`。
- **校区来源 = 「我的校区」偏好的 `MyCampus.label`（中文全称）—— 不是 enum 的 `name`（`mailu`）**；教务 `MsSchoolArea` 实测 6 条：`05` 深圳校区 / `06` 北京校区 / `07` 上海校区 / `1` 蛟桥园校区 / `3` 麦庐园校区 / `4` 枫林园校区（与 `MyCampus.label` **同字面**）；教务**没有**「青山园校区」→ 匹配不到就留空。学籍里**没有**校区字段（`dormName` / 通讯地址实测皆空）。
- **找班级分三步（班级码必须与校区配套）**：① 按「我的校区」取 → ② 没命中就**逐个校区试**（顺序 = 教务列表顺序，命中即以该校区为准）→ ③ 都没命中才退回**不限校区**（`xqdm=''`，**此时校区留空、班级照填**：报告允许 `selXQ` 空 + `selBJ` 精确查，配套关系没确认就不猜）。三步都不中 → 班级留空、校区保持偏好值。
- **账号侧输入走窄 provider = `data/providers/public_query_profile_provider.dart`**（`publicQueryAccountProfileProvider` = 学籍缓存 + 「我的校区」）。页面**不要**直接 `ref.read(studentInfoRepositoryProvider)` / `myCampusStoreProvider`：这两个 store 的 `Hive.openBox` 会在 `ref.read` 里**同步抛出**（`ChangeNotifierProvider` 的 create 不做 guard，错误直接冒到调用方）→ widget 测试没法覆盖本页。窄 provider 一次 `overrideWith` 就能覆盖整条预填链路。
- **卡片纯白（不硬编码）**：`public_query_screen.dart` 的 `build` 用
  `Theme(data: Theme.of(context).copyWith(cardTheme: Theme.of(context).cardTheme.copyWith(color: scheme.surface)))` 包住 `_buildScreen` → 本页与两个子视图（课表卡 / 空闲网格卡）的 `Card` 全部取**主题的 `surface`**（app 里 = 纯白 `#FFFFFF`，见 §3「主题纯白」口径），而不是 M3 `Card` 默认的 `surfaceContainerLow`（`#FAFAFA`）。改在 `CardTheme` 而不是逐个 `Card(`：一次命中全部卡片；各卡自带 `geCardShape` 的 outline 细边框仍在 → 白卡压纯白底依旧有分界。班级行显示顺带改用 `displayName`（剥掉 `[2508090D52]` 前缀，与课程 / 教室行一致）。
- **生效时机**：`initState` → `unawaited(_applyAccountDefaults())`（`_resolveAccountDefaults` 串行取 学期 → 校区 → 学院 → 专业 → 班级，任一步失败只影响该项，全部取不到则什么都不做）；切换类别后调 `_restoreAccountDefaults(_kind)` 用**已解析的缓存值**补填（不重发请求；校区对班级/教室都用，学院/专业/班级只属于班级课表）。
- **守卫**：`test/public_query_defaults_test.dart`（19 例，选项数据全是实测原文）、`test/public_query_screen_defaults_test.dart`（6 例：卡片 `Material.color == scheme.surface` 且 ≠ `surfaceContainerLow`、outline 边框、全链路预填（断言 family provider 真收到 `nj=2025` / `2025|44` / `xqdm=3`）、跨校区纠正、配套确认不了 → 校区留空、全空输入不预填）。
  ⚠️ 该 widget 测试**把公共查询每个 provider 都换成实测假值** → 零网络零 Hive；**不要用 `pumpAndSettle`**（loading 卡里的 `CircularProgressIndicator` 是无限动画，会挂到默认 10 分钟超时）→ 用有限帧 `pump` + 条件轮询。



## 15. 教务「选课」口径（网上选课 / 选课结果 / 退选 · 2026-09-14 立）

**用户诉求（原话）**：「我们来做同样在教务系统下的选课功能，应包含原系统中的"网上选课"和"选课结果"两部分」；随后拍板：**读写全做**（提交选课 + 退选）、入口 = **首页宫格 1 个「选课」磁贴**（页内两个 Tab）、附加项「被取消课程 / 查询课表 / 申请扩容」全要。

### 15.1 铁律（踩过的坑，最贵）

1. **`taglib/DataTable.jsp` 的 `initQry` 必须传 `0`**。传 `1`（教务页面表单里的初值）时服务端**只回表头、`showTotalRecord(...,'0')`**，看起来像「没有数据」其实是参数没生效。排查耗时最久的一条。
2. **教学班表 `tableId=6142` 只认带 `electiveCourseForm.` 前缀的字段名**（plain 名恒 0 条）——教务页面就是把 `<form>` 里的前缀字段原样 POST 过去。
3. **提交选课要 DES 加密**（`getEncParams`，前端加密后端解密）；**但「选课结果」页的退选是明文**，别顺手给退选也套加密。
4. **⚠ 「凭证已失效」那一页是 UTF-8，正文页才是 GBK**（2026-09-14 实测，最阴的一条）。会话过期时回的是 523 字符 `<script>alert('温馨提示：凭证已失效，请重新登录!');…`，**这一页的字节是 UTF-8**；而 `fast_gbk` 对任意字节都能解出结果（只把 `凭证已失效` 解成乱码、**不抛异常**）→「先 GBK 解、再 `contains('凭证已失效')`」**永远判不出失效**，会话过期被伪装成「没数据」：选课结果页显示「该学期没有已选课程」（真实 10 门）、公共查询显示「没有检索到记录！」。
   **唯一口径 = `lib/core/network/jw_page_decoding.dart` 的 `decodeJwPage(bytes)`**（先严格试 UTF-8 认失效页，其余一律 GBK）+ 判据 `jwSessionExpired(body)`；公共查询的 `decodeGbkBytes` 与选课的 `_decodeGbk` 都是它的薄封装，**禁止再各写一份「先 GBK」的解码**。
   排查手法：同一实例里用 VM Service 对比两个端点——`fetchQuota`（JSON 路径走 `utf8.decode`）能正确抛 `SelectionSessionExpired`，而 `fetchResultHtml` 回 `len=523 expired=false alert=true`，一比即知是解码顺序错。
5. **教务请求里的学号 `xh` = 学籍 `<xh>`（= `StudentInfo.serialNo`），不是 `<yhxh>`**（2026-09-15 二次核实 —— **2026-09-14 那条结论是反的**，成因见末尾）。学籍 XML（`STU_BaseInfoAction.do`，1357 B、单条 `<info>`、无 `<row>`）三条标识：`<yhxh>2000000000</yhxh>`（= `StudentInfo.userId` = **用户号 / 统一身份认证号** = App 账号 `cardNumber`）、`<bz>0000000</bz>`（= `studentId`，体测 `stuNum` 用它）、`<xh>201600035929</xh>`（= `serialNo`，**教务所有请求都用它**）。
   依据（全部是教务自己的产物）：① 课表页 `/student/xkjg.wdkb.jsp` 的隐藏框是**服务端渲染**的 `<input type="hidden" id="xh" name="xh" value="201600035929"/>`；② 选课页的 `xh` 由 `getWsxkTimeRange.action` 响应的 `xh` 字段填充（实测同值），选课结果页 `wsxk.zxjg.jsp` 服务端渲染的也是它；③ **写操作会校验**：`saveElectiveCourse.action` 拿表单里的 `xh` 比对「本人」，传 `<yhxh>` 会被拒 —— 「当前选课操作的用户不是选课学生本人！」。
   **唯一口径**：选课模块走 `lib/features/ims/course_selection/data/providers/course_selection_providers.dart` 的 `selectionStudentIdProvider`（**优先用教务 `getWsxkTimeRange` 返回的 `xh`**，取不到才回退学籍 `serialNo`）；课表两页（`schedule_screen.dart` / `live_class_screen.dart`）直接用 `si.serialNo`。`StudentInfo.jwStudentId` / `jwStudentIdOf` **已删除**（错误口径的产物），「我的」页「学籍标识」卡的「序号」行已恢复。
   **第一次为什么会搞错（别再重蹈）**：只读端点对 `xh` **完全不敏感** —— 同一会话传 `201600035929` / `2000000000` / `0000000` / 空，`getSelectLessonScoreKcsInfo`、`isSelectableSkbjdm`（选课前预检，四组全 `{"status":"200","message":"操作成功!"}`）、确认页 `wsxk.zx_promt.jsp`（两次都正常渲染表单）、课表 `xkjg.ckdgxsxdkchj_data10319.jsp`（三组同 12542 B）**结果逐字节一致**；当时唯一的反证「教务自己印的学号 2000000000」来自「入学以来正选结果」页顶部的展示文案（那是 `<yhxh>` 的展示口径）。**全线只有 `saveElectiveCourse` 会校验**，所以改错当天所有只读路径都毫无异常，直到用户真点「确认选课」才炸。
   教训：**「关键参数取哪个字段」要以「教务自己的页面往哪儿填」为准**（页面隐藏框的服务端渲染值 / 页面 JS 填值的来源），不能拿只读端点的宽容度或某个展示文案去推断；改完这类口径必须找到**会校验它的那个写操作**做验证。守卫测试 `test/student_id_test.dart`（5 例：`SelectionSession.xh` 解析 + 源码口径静态守卫 + 「`jwStudentId` 不许复活」）。

配套：这些页面全是 **GBK 且响应头不带 charset** → 一律 `ResponseType.bytes` + `fast_gbk`；**表单体里的中文要 GBK 百分号编码**（`Uri.encodeComponent` 发 UTF-8，教务按 GBK 解）；`ResponseType.bytes` 下 `ImsAuthInterceptor` 看不到字符串 → **会话失效要自己判**（数据源抛 `SelectionSessionExpired`，仓库续期后重试**一次**）。

### 15.2 加密（唯一实现 = `lib/features/ims/course_selection/domain/kingo_des.dart`）

- 请求体：`params=<base64(hex(strEnc(明文,临时密钥)))>&token=<md5(md5(params)+md5(timestamp))>&timestamp=<服务端时间>`；
  `tempDeskey` / `timestamp` 分别取 `GET /frame/homepage?method=getTempDeskey|getTempNowtime`。
- `strEnc` = `/custom/js/jkingo.des.js` 那支**非标准位序 DES**：明文按 **4 个 UTF-16 码元**一块（末块零填充）、密钥按 **4 字符**一块逐块迭代；**输出与标准 DES 不同**（实测 `133457799bbcdff1`/`0123456789abcdef` → 该库 `37C2A4CD08649BB7`，标准 `85E813540F0AB405`）→ **禁止换成 pointycastle 的 `DESEngine`**。
- 置换表在 `kingo_des_tables.dart`（**自动生成**：node 加载真实 JS 库 + 基向量探测导出，别手改）；对拍向量 `test/course_selection_des_test.dart`（13 例，期望值由 node 跑真实 JS 产出）。
- 时间戳里的空格必须是 `%20`（`Uri.encodeQueryComponent` 会变 `+`）。
- **零副作用验证法**：`GET /student/report/wsxk.zx_promt.jsp?<encParams>` 是**只读**的选课确认页 —— 加密对不对看它回显的 `electiveCourseForm.*`（实测回显 `xh=2000000000 / kcdm=000160 / xf=3.0 / lcid=…` 即成功）。**改加密后先跑这一手**，别拿真选课去试。

### 15.3 端点与口径

- 元信息：`GET /jw/common/getWsxkTimeRange.action?xktype=2|88`（2=正选，88=外年级专业）→ `{status,message,result:"<JSON 字符串>"}`，含 `xn/xqM/xnxqDesc/lcmc(轮次名)/lcid(轮次 id)/qssj/jssj/rxksjqs/rxksjjs/isValidTimerange/nj/zydm/zybdm…/kcfw/kcfwmc`。**`lcid` 每次请求都要回传**；⚠ 返回里的 `xh` 是教务模板默认值（实测恒 `201600035929`），**学号一律取学籍 `serialNo`**。
- 学分额度 `getSelectLessonScoreKcsInfo.action?xn=&xq_m=&xh=`、年级专业 `getStuGradeSpeciatyInfo.action?xh=`、课程范围 `POST frame/droplist/getDropLists.action`（`comboBoxName=MsKcfw&paramValue=<xktype>` → `zxbnj/zxggrx/fx/zxknj`）。
- 列表：可选课程 `tableId=2568&fre=1`；教学班 `tableId=6142&fre=1&<明文查询串>`；查询课表 `tableId=5327042`；申请扩容 `tableId=5929098`。
  **解析一律按 `<td name='X'>` 取格**（同族模板：`<tr id='trN'>` + `td name`），**总条数看 `showTotalRecord('<id>','<n>')`**，别数 `tr`。
- 选课结果：`GET /student/wsxk.zxjg.jsp?menucode=S2020302`（服务端渲染整页：`学年学期/学分上限/选课总学分数/选课总门数` + 分类统计 + `<table id="reportArea">`）、入学以来 `wsxk.zxjg_all.jsp?xh=&nj=&zydm=`（顶部是 `学号/姓名`，**没有**学分上限 → 正则要写成 `学年学期：(\S+)`）、被取消课程 `wsxk.qxbxkc.jsp`（空态文案 `没有相关数据！`）。
  `reportArea` 数据行末格 = **上课班组代码（退选的 `items`）**；列序在不同页面会漂 → 按内容特征定位（课程格 = `^\[[^\]]+\]\S`）。
  **分类统计表只取学分**（2026-09-14 订正）：隐藏表行如 `['已选','25.5','0.0','0.0','1.0','1','0','0','1']`，只有 `cells[1]` 可用（限选 26.0 = 上限、已选 25.5 = 选课总学分数、可选 0.5）；后面那些**「门数」列是按专业限选/专业任选/公共任选分列的**（已选行给 `1/0/0`，而页头写「选课总门数：10」）→ **禁止当分类门数展示**（曾显示「限选 26 学分 · 0 门」这种假数字）；总门数只认页头。
  同理 `getSelectLessonScoreKcsInfo.action` 的 `zxf`/`zdxf`（实测都 25.5）= 教务**指定学分**（培养方案应修），**不是选课上限**（上限 26 只在选课结果页）→ 额度卡别标「上限」（曾标错，现标「应修」）。
- 提交：`POST /jw/common/saveElectiveCourse.action`（加密；字段 = 确认页表单**去掉 `electiveCourseForm.` 前缀**；教务**强制**「是否购买教材」，`is_buy_book` 必填；`is_checkTime=0` = 允许时间冲突）。前置检查 `jw/common/isSelectableSkbjdm.action`（明文）。
- 退选（明文）：`POST /STU_ElectCourseResultAction.do?hidOption=cancel`（**站点根目录，不在 `/student/` 下**），表单 `xktype=2&xh&xn&xq&nj&zydm&zymc&xktime_flag&items=<码>|<可多个>`。
- 教务原文错误一律**透传给用户**（`{status,message}`），别自己编文案。

### 15.4 落点与守卫

- 模块：`lib/features/ims/course_selection/{domain/{kingo_des.dart,kingo_des_tables.dart,data_table_page.dart,selection_models.dart,selection_parsers.dart},data/{datasources/course_selection_remote_datasource.dart,course_selection_repository.dart,providers/course_selection_providers.dart},presentation/{course_selection_screen.dart,selection_online_view.dart,selection_result_view.dart,course_section_sheet.dart,selection_extra_screens.dart}}`。
- 入口：首页宫格 `_items` 末尾「选课」磁贴 + `_tileColors` 末尾 `FeaturePalette.courseSelection`（`0xFFAD1457`）——两处**同一次改**（AGENTS §3）。
- 写操作**一律先核对再提交**（2026-09-15 事故后加硬）：破坏性动作收进行尾 `PopupMenuButton`（「退选本门课」），确认弹窗**必须勾选**「我已核对：要退选的是《课程名》」才解锁确认按钮（退选用 `scheme.error` 危险色），**并且写入成功后必须对账**（见 §15.5）；`session.open == false` 时不给任何写入入口。
- **检索栏 = 教务原页面 `wsxk.zx.html`（S2020202）的 8 个控件**（2026-09-15 用户指出「你目前选课的搜索功能也和原页面不一致」后逐控件补齐）：课程范围 `kcfw`（选项要取 `getWsxkTimeRange` 返回的 `kcfw/kcfwmc` —— 原页面会 `$("kcfw").length=0` 后用它们重建，`MsKcfw` 下拉只是初始值 → `SelectionSession.scopeCodes/scopeNames`）/ 院(系)部 `sel_yxb`（`MsDepartmentYXB` 静态表，**只有 `kcfw==zxknj` 显示**）/ 年级专业 `njzy`（`DroplistControl.jsp` 级联，**默认选中第一项**；`zxknj` 下教务恒空）/ 课程 `kcmc`（hint 照抄原页面 title「可以输入课程代码(前缀匹配)或课程名称(模糊匹配)」）/ 课程类别 `lbgl` / 课程属性 `kcsx`（**这两个是客户端过滤**：类别键 = `kclb2_kclb1`、文本 = `lb` 列（实测常为空 → 退回键本身），属性按 `kcsx` 值；页面里这两个 select 初始 `disabled`，根本不提交）/ 限未选满 `xwxmkc`（checkbox 默认勾选，服务端参数）/ 检索按钮（`zxknj` 下未选年级专业 → 「需选定年级/专业！」）。
  - 纯逻辑 `domain/selection_filters.dart`（`filterOptionalCourses` / `reconcileOptionalCourseFilters`：原页面每次检索重建下拉 = 清空选择，我们只清失效项，且类别∧属性取**交集**而不是「后者覆盖前者」）；取数 `fetchDepartments()` / `fetchGradeMajorsXml({session,studentId,scope,department})`（响应是 `<root><item><key>2025|4405</key><value>2025|计算机科学与技术</value></item></root>`，**`key` = 提交值、`value` = 显示文本**，与 CombBox 的 `<info><value>/<name>` 不同，`parseDropListXml` 两种都吃）；查询对象 = `OptionalCourseQuery{channel,scope,keyword,njzy,department,onlyWithVacancy}`（**`category` 字段已删**）。
  - ⚠ **`kcsx` / `kclb1` / `kclb2` 现在恒发空**（原页面也不提交）——别再拿它们当服务端过滤；「课程类别/属性」必须在已取回的列表内筛。
- 守卫测试：`test/course_selection_des_test.dart`（13，加密对拍）、`test/course_selection_parser_test.dart`（21，真实 fixture `test/fixtures/course_selection_*.html`：可选课程 11 条 / 教学班 9 个 / 本学期结果 10 门·25.5 学分·上限 26 / 入学以来 36 门 / 扩容 2 行 / 被取消空态）、`test/course_selection_safety_test.dart`（18，退选事故后的安全口径，见 §15.5）、`test/course_selection_filters_test.dart`（16，检索栏纯逻辑 + `<item>` XML + 源码静态守卫）、`test/course_selection_search_ui_test.dart`（5，用假 provider 真渲染 `SelectionOnlineView`：8 控件在位 / 客户端过滤当场变窄 / `zxknj` 才显示院系部与检索提示 / 限未选满默认勾选）。
- **未做**：申请扩容的**提交**（弹窗页 `GET /student/wsxk.sqkr_sq.jsp?hidOption=add&…`，其内部提交目标与字段尚未实测）→ App 内只读列表 + 审核状态；`wsxk.tx.nopre.html` 的「退选课程」列表 `tableId=6093` 实测恒 0 条，已改用选课结果页；选课币（`xk_points`）江财未启用，恒传 0。
- 接口细节与复现手段见 `reverse_engineering/选课接口.md`（§7 = 退选事故取证与新增硬规矩）。

### 15.5 ⚠️ 写入后必须对账（2026-09-15 退选事故后立，勿省）

**事故**：用户在「选课结果」点某行的「退选」，教务实际退掉的是**另一门课**（计算机组成原理 1014300184，4 学分），App 只弹了「退选成功」——**提交后没有任何核对**，用户事后才发现。教务侧实测从 10 门/25.5 学分 → 9 门/21.5 学分。

**取证结论（别再重复怀疑同一件事）**：教务选课结果页自己的退选实现是 `CancelData()` 的 `items += rows[ind].cells[l-1].innerHTML + "|"`（**末格**＝上课班组代码），我们提交的 `itemCode` 与它**逐行一致且两两不同** → **「发错码」不是成因**。现实成因 = 行内每行一个小「退选」按钮上下紧贴、长相一致（误触相邻行）+ 主色「确认退选」被顺手点掉 + **写入后无对账**。

**同日二轮（同一处端点的第二个坑）**：用户又退一门课时 App 提示「网络异常，请稍后重试」，但教务网页里**课已经退掉**、App 列表**还留着那门课** → 用户很可能在同一行再点一次（正是上面事故的温床）。根因两条：① 该端点应答不是 JSON 而是 **iframe 回调页 HTML**（`cancelSelection` 实测 HTTP 200 / **109 字节** / `text/html;charset=UTF-8`：`<script language="javascript">parent._callBack("{\"status\":\"200\",\"message\":\"操作成功!\"}")</script>`），旧代码裸 `jsonDecode` 整页 → 恒 null → 误判 `SelectionWriteResult.networkFailure`（=「网络异常，请稍后重试」）；② `cancelAndVerify` 写成 `if (!write.ok) return`，**早退跳过了 `_invalidateAfterWrite()`** → 界面停在过期列表上。

**⚠ 该端点是 fire-and-forget（决定了所有加固方式）**：`items=` 空、以及绝不存在的码 `0000000000-999|` **都回「操作成功!」**（实测三组同款应答）⇒ **`status=200` 只代表「教务收下了」，不代表「退掉了」**；写入是否生效**只能**靠重读 `GET /student/wsxk.zxjg.jsp` 比对。

**四条硬规矩**（代码已落，缺一不可）：

1. **写入后必须对账**：唯一实现 = `lib/features/ims/course_selection/domain/selection_write_check.dart`。
   `SelectionCancelCheck verifyCancellation({required SelectionResult before, required SelectionResult after, required String requestedItemCode})` → `SelectionCancelVerdict{confirmed, requestedStillPresent, wrongCourseDropped, unverifiable}`；**判定顺序不可反**：只要消失了「不是你请求的课」就是 `wrongCourseDropped`（哪怕请求那门也一起消失、哪怕请求那门还在），`alarming` 时界面**弹红字 `AlertDialog`**（文案「退选结果与请求不一致」），不能再无条件说「退选成功」。
   `SelectionSubmitCheck verifySubmission({required SelectionResult after, required String courseCode, required String courseName})` → 抓「教务回成功但选课结果里没有这门课」的假成功。
   门面 = `CourseSelectionActions.prepareCancel({required String itemCode, required String courseName})` → `SelectionCancelPreparation{fresh, message, readFailed; ok; course}`（**只读**，给确认弹窗新鲜数据）与 `cancelChecked({required String itemCode, required String courseName})` → `SelectionCancelOutcome{fresh, write, check, refreshed, freshReadFailed, writeAttempted; blocked; unknown; confirmed; alarming; message}`（`data/providers/course_selection_providers.dart`）；`submitAndVerify({...})` 返回 `({write, check})`。三者内部一律 **`repository.fetchResult()` 重取**（`_readFreshResult()`）—— **绝不能拿旧列表自己比自己**，`before` 必须是发请求前那一刻重读的那一份；**且任何分支（成功 / 拒绝 / 抛异常 / 读不到）都要 `_invalidateAfterWrite()`**（`if (!write.ok) return` 这种早退已删，守卫会拦它复活）。界面播报统一走纯函数 `selectionCancelMessage({fresh, write, check, refreshed, freshReadFailed, writeAttempted})` —— 教务回「操作成功!」但没读到结果时必须说「**无法确认是否真的退掉**」，不许说成功。
2. **退选码只认表格末格**：`selection_parsers.dart` 的 `_itemCodeFromLastCell(cells)` —— 末格匹配 `^[A-Za-z0-9]+-\d+$` 才用，否则留空（界面据此禁用该行退选）。**`itemCode = classCode` 的兜底已在事故当晚删除**：那是「上课班级」格，合班 / 换班时可能是**别门课**的班号，取错就会退掉别的课。守卫会拦它复活。
3. **破坏性动作先进菜单 + 弹窗强制核对 + 唯一性闸门**：行内不再有「退选」按钮（`PopupMenuButton` → 「退选本门课」）；弹窗列出课程/代码/教师/学分/时间地点/**退选码**（且**渲染的是 `prepareCancel` 刚重读回来的那一行** `prep.course`，不是界面手上那份），必须勾选「我已核对」才解锁确认；`_cancel` 另有一道本地闸门 —— 退选码必须在本页**唯一**指向这一行（重码 / 空码 → 提示「已阻止退选」并拒绝提交）。选课侧（`course_section_sheet.dart`）同样加了核对勾选，且**只有对账确认后才关弹窗**。
4. **写前必须重读核对（防「在过期列表上操作」）**：`checkFreshCancelTarget({required SelectionResult fresh, required String itemCode, required String courseName})` → `SelectionFreshTargetVerdict{ok, missing, duplicated, nameMismatch}`；非 `ok` 一律**不提交**并刷新列表。`missing` = 这码已不在最新结果里（多半刚退掉）；`duplicated` = 同码多行；**`nameMismatch` = 码对应的课名 ≠ 用户看到的那门 —— 这正是「再点一次会退错课」的直接形态**。配套：`parseWriteEnvelope(String body)` 宽容解析写应答（① 整串 JSON → ② 取 `_callBack(...)` 第一实参、反转义 `\"`/`&quot;` → ③ 剥外层引号 → ④ 兜底扫第一个配平 `{}`），`cancelSelection` 与 `submitSelection` **两条写路径都必须走它**（守卫会拦裸 `tryJsonMap(_decodeEnvelopeText(...)`）。


**恢复路径实测（同类事故可直接复用）**：窗口「第一轮退改选 2026-09-14 09:00 → 2026-09-16 17:00」当时仍开放；被退的课在 `kcfw=zxbnj` 可选列表里（学生自己能选回），各班余量 `-001` 45 限选/50 已选（超员）、`-002` 60/60、`-003` 60/59（剩 1，但与本生「数据结构与算法」周一 3-4 节冲突）、`-004`（原班）60/60、`-005` 60/60 → 原班多半选不回，满员必修课走教务员 / 扩容申请。

## 16. 卡片风格唯一口径（全应用统一 · 2026-09-15 立）

用户原话：「我希望统一卡片风格，我希望应用内大部分的卡片，其卡片样式都采用“综合测评“中”评测“结果卡片的样式，配色也要调整为类似的红色，（如果本身是彩色不用改成红色，但如果是单一的其他颜色，就要改），综测部分的其他卡片不需要改成这样；主页的卡片也要这样改」。
两项裁定：① **主页两类卡片（功能宫格磁贴 / 「数据一览」4 格）保留原色，只统一形状**；② **其他页面的单色强调一律改主题红**（语义色不动）。

- **目标形态（原式 = `lib/features/zongce/presentation/zongce_screen.dart` 的 `_card`）**：`Container(padding: EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6))))` —— **无阴影**。
- **唯一实现 = `lib/design/app_card.dart`**（别在页面里再拼 `BorderRadius.circular(…)` + `BorderSide(…)`）：
  `kAppCardRadius = 12`、`kAppCardPadding = 14`、`kAppCardColor = 0xFFFFFFFF`、`appCardBorderSide(scheme)` = `outlineVariant@0.6`、`appCardShapeOf(scheme)` / `appCardShape(context)`、`appCardTheme(scheme)`、`appCard(context, child: …)`（纯装饰容器，要点击涟漪用 `Material(color: kAppCardColor, shape: appCardShape(context))`）、`appCardAccent(context)` / `appCardAccentSoft(context)`。
- **两条覆盖路径，缺一不可**：① `lib/main.dart` 的 `cardTheme: appCardTheme(_appScheme)` → 覆盖**所有** `Card(`（`color` 纯白 + `elevation: 0` + `surfaceTintColor` 透明 + 该 shape；**刻意不设 `margin`**，`Card` 默认外边距 4 不动，免得连带改掉全应用卡间距）；② `appCardShape(context)`（`geCardShape` 已**转发**到它，48 处旧调用点无需改）→ 覆盖显式写 `shape:` 的 `Card`/`Material`。
- ⚠ **显式写 `shape:` 或 `elevation:` 的卡片会绕过 `cardTheme`**（本次逐处改掉，共 26 处）：数据中台 10（`data_center_screen.dart`）、第二课堂 6、志愿时长 1、教务 IMS 菜单 1、融合门户选择页 1、材料库 4、网费 1、体测 1、办事指南（platform_guid）1、请假列表/详情 2、制度阅读器 1、学校地址/校区地图 2（后两个是「我的校区」pinned 态：`appCardShape(context).copyWith(side: BorderSide(color: FeaturePalette.cardAccent))`）。
- **强调色 = `FeaturePalette.cardAccent`（`#C3282E`，与 `scheme.primary` 同值；常量版在 `app_card.dart` 的 `kAppCardAccent`，给拿不到 context 的静态 helper 用）**：卡片标题竖条（`geCardTitle` 的 `accent` 默认值已改成它）/ 图标与图标底 / 分区点缀色 / TabBar 指示器 / 主按钮。已扫过：选课、公共查询、课表（live_class 实况窗）、调课列表（生效中）、畅想之星（含书架选中态）、蛟湖阅读/阅读学分、成绩估计全模块、设置页 6 个节、校区徽标。
- **刻意保留的「彩色」**（用户口径「本身是彩色不用改」）：① 首页宫格条目的 `HomeServiceEntry.accent`（`home_service_catalog.dart`，原 `_tileColors`）与「数据一览」4 格（电费/网费/加权/志愿）；② 桌面小组件三色 + 设置页尺寸 chip 的 `_color(metric)`；③ **语义色**：`scheme.error`（成绩页挂科红边 / 总评不及格）、成绩等级绿 `#2E7D32`、调课·补课·停课三态（`FeaturePalette.reschedule / makeUpClass / classCancelled`，含 `reschedule_marks.dart` 与 `_markColor`）、校历假日/补课/活动角标、`ge_deadline_card` 状态色、`ge_ratio_bar` 平时/期末双色（`test/ge_ratio_bar_test.dart` 断言其配色，别动）、畅想之星账号/已读完状态 chip；④ 课表网格里的调课/补课标记。
- ⚠ **`InkWell.borderRadius` 要 `BorderRadius`，不能传 `appCardShape(context).borderRadius`**（静态类型是 `BorderRadiusGeometry` → 编译错误 `argument_type_not_assignable`）→ 圆角处一律写 `BorderRadius.circular(kAppCardRadius)`。
- **golden 影响（改卡片形状前先知道）**：`test/qa_rules_visual_test.dart` 有 10 张金标准（`test/goldens/qa_r*.png`，2026-09-08 生成）——本次卡片圆角 9→12 + 描边变化使 `qa_r01_reader_top` / `qa_r01_notice_tail_links` 失败（diff 仅圆角矩形轮廓，0.2% / 1947px），已用 `flutter test test/qa_rules_visual_test.dart --update-goldens` 重生成。**注意「无 golden」的旧说法已过时**。

## 17. 主页布局 / 宫格排版 / 应用名（2026-09-15 立）

用户当日六条（原话）：「1. 电脑端主页可选宫格视图与左侧导航栏视图 2. 电脑端宫格视图下，每个卡片要一样宽高，提示文本不足1行，也显示为2行高，超过2行的，显示省略号，仅保留两行内容 3. 数据一览的成绩卡片，排名不要占用高度，而是显示在右上角的一个胶囊（a/b/c)abc分别为班级、专业、年级成绩 4. “上下课实况窗”功能改到设置，主页不要显示 5. 我们需要项目的中文名（软件在系统应用管理中的显示名称）为智慧er江财 6. 我们需要一个项目logo，你用svg设计几版，然后放到html里让我看看效果，我选一个告诉你」。
另四条裁定：**① 系统显示名 + App 内标题一起改**；② 排名胶囊 = **一个胶囊写 `3 / 12 / 45`**（无标签，含义靠 tooltip）；③ 布局切换**只在设置页 + 记住选择**；④ 侧栏 = **全部分组服务列表，右侧仍显示「数据一览 + 宫格外的内容」**；⑤ 实况窗 = **设置页新增卡片，点击进入原页面**。

### 17.1 主页两种布局（唯一判定 = `lib/features/home/domain/home_layout.dart`）

- `enum HomeLayout { grid, sidebar }`（各带 `label` / `description`，设置页直接渲染）+ `HomeLayout.fromName(String?)`（未知 / null → `grid`，旧数据不会崩）。
- `bool homeUsesSidebarLayout({required HomeLayout layout, required bool desktop, required double width})` = 选了侧栏 **且** 桌面平台 **且** `width >= homeSidebarMinWidth`(**900**)。**手机端永远宫格**。`bool homeDesktopPlatform(String platformName)`（windows / macOS / linux）；页面里用 `Theme.of(context).platform.name` 取平台（**别写 `defaultTargetPlatform` 分支**）。
- **切换入口只在设置页**「主页布局」节（`_HomeLayoutCard`，两个选项行 + 底部说明「侧栏视图只在电脑端生效（≥900px）」；`Key('homeLayoutOption-<name>')`），**不往顶栏加按钮**（用户裁定）。
- 持久化 = `lib/features/home/data/home_layout_prefs.dart`（Hive box **`homePrefs`** / key `homeLayout`，存 `HomeLayout.name`；`HomeLayoutStore extends ChangeNotifier` + `homeLayoutStoreProvider`，照 `my_campus_prefs.dart` 范式 → 设置页改完**主页即时跟随**，不重进页面）。
- 侧栏 = `HomeSidebar`（宽 `homeSidebarWidth` = **232**、底色 `surfaceContainerLow`、按 `HomeServiceGroup.values` 顺序分组、行高 `HomeSidebar.rowHeight` = 38、`Key('homeSidebar')` / `Key('homeSidebarItem-<title>')`）；**右侧默认内容 = 「数据一览」概览**（`Key('homeOverviewPane')`，侧栏顶部固定一行 `homeSidebarOverviewTitle` = 「数据一览」，`Key('homeSidebarOverview')`，也是唯一的「回概览」入口）。**点侧栏 = 选中并把功能页内嵌到右侧面板，不再 push 整页**（2026-09-16 用户裁定第 2 条，实现与铁律见 §17.7）；未传 `onSelect` 时回落到条目自带的 `onTap`（旧调用点/测试零改动）。顶栏在两种布局下都在。
- 守卫 = `test/home_layout_test.dart`（9 例：四分支判定 + 平台表 + `fromName` 往返/兜底 + label 非空）、`test/home_sidebar_test.dart`（9 例：分组齐全与顺序、空分组不渲染、无 `onSelect` 时回落 `onTap`、给了 `onSelect` 只回调不 push、选中态高亮（左指示条 3px + 加粗）、概览行默认选中且在分组之上、不给 `onOverview` 不渲染该行、宽度/行高、长标题不溢出）。

### 17.2 宫格卡片定宽等高（唯一实现 = `lib/features/home/presentation/home_service_grid.dart`）

- 用户口径「不足 1 行也显示为 2 行高、超过 2 行省略号」→ **副标题区恒为 `subtitleLineHeight * 2` = 32px 的 `SizedBox`**（`Key('homeSubtitleBox-<title>')`）包住 `maxLines: 2` + `ellipsis` 的 `Text`；磁贴高度由外层 `SizedBox(height:)` 固定 —— 宽屏 `cardHeight` = **88**、窄屏（< `compactBreakpoint` **620**）`compactCardHeight` = **94**。**别再靠内容撑高**（`Wrap` 里每项独立，文案一长一短就参差不齐）。
- 宽度仍按列数平分（宽屏 `minCard` 208、`cols` 夹在 1..6；窄屏按 `compactExtent` 108 算列数、至少 2 列）→ **所有磁贴等宽等高**。
- 被截断的长文案靠 `Tooltip(message: subtitle)` 看全文（桌面悬停 / 手机长按）；磁贴 Key = `Key('homeTile-<title>')`。
- 守卫 = `test/home_service_grid_test.dart`（6 例：真渲染量 `RenderBox` 断言等宽等高、1 行/空文案同样占 32px、超 2 行断言 `maxLines == 2` + `ellipsis`、360 宽紧凑档等高不溢出、点击触发、tooltip 全文）。

### 17.3 数据一览「课程加权」排名胶囊

- 用户口径「排名不要占用高度」→ **右上角一枚胶囊**，内容 = **`#班级/专业/年级`**（用户 2026-09-16 二轮裁定「改成 #a/b/c 的格式」：`#` 前缀 + 斜杠分隔、**斜杠两侧不留空格**；`WeightedGrade.classRank / majorRank / gradeRank`，**≤ 0 写 `—`**），`Key('dash_grade_rank')`，tooltip 出完整含义。**文案唯一实现 = `lib/features/home/domain/grade_rank_badge.dart`** 的 `gradeRankBadge({classRank, majorRank, gradeRank})` / `gradeRankText(int)` / `gradeRankTooltip(...)`（抽成纯函数就是为了可单测：整块 `DashboardPanel` 需要一堆数据 provider 才能 pump）。渲染 = `dashboard_panel.dart` 的 `_gradeRankCapsule` + `_MetricCard` 的 **`trailing` 参数**（挂在卡片头部行尾部，不占内容区高度）；`_buildGradeContent` 只剩加权分那一行（原「专业排名 第 N 名」第二行**已删**）。
- 守卫 = `test/home_grade_rank_badge_test.dart`（4 例：三排名齐全 `#1/3/9`、紧凑无空格、≤0 写 `—`、tooltip 仍是完整中文）。改格式先动这里。
- 桌面小组件快照仍用 `sub1 = '专业排名 第 N 名'`（`home_widget_sync.dart` / `home_widget_background.dart`）——**没动**。

### 17.4 「上课实况窗」入口迁到设置页

- 宫格磁贴已删（`home_tile_alignment_test` 有一条守卫断言它不在目录里）；设置页新增「上课实况窗」节 + `_LiveClassCard`（点击 push `LiveClassScreen`）—— **页面本体与 Android 常驻通知（channel `live_class` / id 8801）完全没变**，只是入口换地方。

### 17.5 应用中文名 = 智慧er江财（字面如此，`er` 是小写拉丁字母）

**目录名 / 包名 / bundle id 一律不动**，只改「显示名」：
- Android `android/app/src/main/AndroidManifest.xml` 的 `android:label="智慧er江财"`（**系统「应用管理」里显示的就是它**）；
- Windows `windows/runner/main.cpp` 的 `window.Create(L"\u667A\u6167er\u6C5F\u8D22", …)`（**必须用 `\u` 转义**，免得源码编码 / MSVC 代码页把它弄乱）+ `windows/runner/Runner.rc` 的 `FileDescription` / `ProductName`（该文件第 3 行已有 `#pragma code_page(65001)`，可直接写中文；`InternalName` / `OriginalFilename` 保持 `smarter_jxufe`，那是文件身份不是显示名）；
- iOS `ios/Runner/Info.plist` 的 `CFBundleDisplayName` + `CFBundleName`；macOS `macos/Runner/Configs/AppInfo.xcconfig` 的 `PRODUCT_NAME`；Linux `linux/runner/my_application.cc` 两处 `gtk_*_set_title`；Web `web/manifest.json`（name / short_name）+ `web/index.html`（`<title>` / `apple-mobile-web-app-title`）；`pubspec.yaml` 的 `description`。
- **App 内自称一起改**：`lib/main.dart` 的 `MaterialApp.title`、`lib/features/home/presentation/home_screen.dart` 顶栏标题、`lib/shared/services/windows_notification_service.dart` 的 `appName` —— 三处原为「智慧尼采」，现均「智慧er江财」。顶栏品牌方块里的字从「尼」改成「**智**」（logo 定稿后换成图形）。

### 17.6 Logo（**第三轮 5 版已交付、等用户挑**；前两批均已被否）

- **第一批（`logo-a-book-seal/bridge/grid/chart/seal-zhi/e-wave.svg` + `logo_candidates.html`）已被用户否掉**（原话「logo我不满意，你自己给自己装一些logo设计skill」）。**别再用它们**：病根是「把一张应用图标展示图当 logo 画」——识别度全押在 512 满幅红圆角方块上，线宽 4–8 units（= 0.25–0.5px@32）、缝 16–24 units（= 1.0px@32）、图形实占 13.5–21px（应 ≥22px）**系统性违反**，且每案都用插画解释含义（书+星 / 桥+水+云 / 格+方胜+金 / 柱+折线+光晕）。
- **已安装的 logo 设计 skill（用户在 `~/.dsh/skills/`，2026-09-16 装）**：`logo-design`（rampstackco，23 KB + `references/` 7 篇：architectures-explained / symbol-approaches / typographic-registers / application-contexts / category-conventions / client-package / example-variant-spec）、`logo-designer`（neonwatty，SVG 迭代 + `scripts/`）、`logo-designer-svg`（luongnv89，7 变体 + showcase + `references/`）、`logo-design-brief`（seb1n）。**画 logo 前先读 `logo-design` 与其 references**。
- **硬规则（第二批全部按此执行，判据都是数字）**：@32 格设计（`viewBox="0 0 32 32"`，1 unit = 1px@32）；最细正形 **≥3px@32**、最细缝 **≥2px@32**（= @512 的 48 / 32 units）；图形实占宽 **≥22px@32（≥70%）**；32px 下实心块 **≤3**；**一个想法**（一句话说清且句中无「和」）；比例/角度必须能报名字（如 `外径:环厚 = 5:1`、`缺口 40°`）；**孔洞必须布尔减**（`fill-rule="evenodd"` + 同一条 `d` 的子路径），**禁止用底色方块补**（透明/反白/水印全废）；先出纯黑剪影再上色；全 path 化（**禁止 live `<text>` + 字体族**，否则三端两个样）；光学居中偏差 ≤1px@32。
- **第二批候选（`design_preview/logo2-*.svg` + 判读板 `design_preview/logo2_board.html`）**：`a-round-e`（圆 e，外径 22 / 环厚 4 / 横杠 4 / 右下 40° 缺口）、`b-square-e`（方 e，圆角方环 22 / 环厚 4 / 横杠 / 右下 45° 切角）、`c-tilt-e`（a 绕中心 −15°，唯一的「上扬」来自横杠与开口倾角）、`d-arch`（拱桥：拱外半径 11 / 内 7 / 基座 26×6，洞口真挖空）、`e-grid`（格窗：圆角方环 22 + 十字分隔 → 1 连通块 + 4 个 5×5 窗洞）、`f-coin`（方孔：外圆 22 + 正中 10×10 方孔）。
- **判读工具链（可复用，全在 `D:\Temp\logo2\`）**：`build_board.py`（判读板：A 尺寸阶梯 / B 单色 / C 反白 / D Android 遮罩 / E 任务栏+顶栏场景 / F 真 32px / G 字标组合，内联 SVG + `color` 控制 currentColor）、`build_t32.py`（固定几何网格的小尺寸页，格 x0=130+k·64、行高 64）、`judge32.py`（切格量墨迹 bbox 与实占比）、`analyze32.py`（**连通块 / 封闭孔洞 / 最细横竖段** —— 这三个量才是「32px 糊没糊」的客观判据）、`ascii32.py`（把真渲染打成 ASCII，肉眼逐像素核对）、`build_gallery.py`（大图审美画廊）。**无头 Edge 命令**：`--headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 --screenshot=<png> --window-size=W,H file:///<html>`。
- **⚠ 本批实测踩到的坑**：① **`fill-rule="evenodd"` 写在根 `<svg>` 上有效**，但**孔洞必须与外形同处一条 `d`** —— 拆成两个 `<path>` 时第二个会被当成实心图形**覆盖**上去（拱桥案的洞口就这么消失了；`ascii32.py` 打出来一看就是实心块）；② 判读不要只信 `view_image`：它对 32px 小图的描述前后矛盾（把白形红底读成「红压红」、把 22px 圆 e 读成有返回箭头），**用它看大图与文案，用 `analyze32.py`/ASCII 判小图**；③ **「最细横竖段」指标对圆形/旋转图形会给出假阴性**：`analyze32b.py`（严格阈值 `dist<90` 只取实心校红像素）对圆 e / 斜 e 报「最细 1–2px」，逐行打游程（`ringcheck.py`）才看清那是**切线极值处的 1px 切片**（`y=27: x16+2`），环厚实际 4px —— 判断笔画细不细要量**中线上的游程宽度**，别用全图最小游程；④ 量居中偏差时**窗口必须按图形盒（已知坐标）对齐**，用「以 ink bbox 中心开窗」的写法会给所有方案同一个 `(+1.0,+1.0)` 伪影（六案同值即伪影，不是设计偏移）。
- **用户选定后要做**：① 存 `assets/logo/`（矢量 + 导出 PNG）；② Android `mipmap-*/ic_launcher.png` 全档 + 自适应图标（前景图形 / 背景校红或白，前景须落在 66/108 安全区内）；③ Windows `windows/runner/resources/app_icon.ico`；④ 顶栏品牌位把「智」方块换成该图形（`home_screen.dart` 的 `_buildTopBar`）。
- **第三轮（2026-09-16，改用 `logo-designer` skill；设计主题 = 「智慧江西财经大学综合服务平台」）**：用户四答 = **只要图标（方形）**、方向**四条全选**（校徽同源 / 平台枢纽 / 汉字几何 / 地标地域）、用色「都尝试一下，给我看看效果」、**替换现有 App 图标（同一枚标记贯彻到底）**。5 个概念已落盘 `logos/concepts/concept-{1-fangsheng,2-hub,3-seal,4-bridge,5-azalea}.svg`（方胜·圆融 / 辐辏 / 白文印·江 / 蛟桥·水波 / 映山红）；32px 实测：实占 81 / 81 / 94 / 81 / 88%，最细正形 9.0 / 5.0 / 3.0 / 3.0 / 8.2px，最细缝 8.2 / 3.0 / 3.0 / — / —，块数 1/1/1/2/1，孔数 1/4/4/0/0 —— **全部达标**。预览板 = `logos/preview.html`（97 KB 自包含；每案 5 套配色 = 映山红红 `#C3282E` / 墨 `#1F2328` / 金 `#B4884B` / 靛青 `#1B4F8A` / 红→金渐变，另有 64-32-16 真像素 favicon 条、三种 App 图标遮罩、反白、场景模拟、内嵌校徽原图与释义）。
- **校徽权威依据（学校党委宣传部《校徽释义》 `news.jxufe.edu.cn/news-show-77942.html`）**：圆形 + **古铜钱外圆内方** + 中心篆体「**信敏廉毅**」汉印 + **整枚单色、以江西映山红花色为基础色调**（2002 试用 / 2011 正式启用）；校训 = 信敏廉毅。→ 「外圆内方」就是校徽的核心构图（方孔类标记与校徽并排不打架）；用色有依据，且与 App 校红 `#C3282E` 同族。
- **第三轮工具链（`D:\Temp\logo4\`）**：`marks.py`（32 单位设计 → 输出 viewBox `0 0 512 512`、无 width/height、纯 path、`fill="currentColor"`；`emit` 写 probe/、`repo <dir>` 写产物）· `probe.py`（`metrics` / `ascii <slug> [px]` / `sheet`：内联 SVG 固定偏移 16px → 无头 Edge 截图 → PIL 量 bbox / 连通块 / 封闭孔洞 / 最细·最厚笔画（距离变换脊线）/ 居中）· `board.py`（生成 preview.html）。**两个新坑**：① **`evenodd` 与 `nonzero` 都解决不了「孔子路径互相重叠」**——evenodd 下重叠处 XOR、nonzero 下两个 −1 相加把重叠处翻回实心，两者都会把笔画切断（印章「工」的竖与两横重叠 → 孔从 4 个裂成 8 个、笔画断成 5 段）；**正解 = 让孔互不重叠**（竖只连在两横之间）。② **Edge 会缓存同名 `file://` URL**（改完 SVG 再量还是旧图）→ 截图文件名必须每次唯一。

### 17.7 侧栏点击 = 内嵌右侧面板（master-detail，2026-09-16 用户裁定第 2 条）

- 用户原话：「我希望点击左侧导航栏后，不是跳转页面，而是直接在右侧显示原跳转页面，并取消原页面的返回按钮」。
- **实现 = `lib/features/home/presentation/home_detail_pane.dart` 的 `HomeDetailPane`**：右侧放**一个独立的 `Navigator`**，把服务页当它的首路由（`onGenerateRoute` → `MaterialPageRoute(builder: (_) => entry.builder())`），`key = ValueKey('homeDetailNav-<entry.title>')`（`HomeDetailPane.navKeyOf`）→ **换条目 = 换栈**，不用手写 pop 逻辑。
- **返回按钮为什么自动没了**：内嵌页是该 Navigator 的**首路由** → `Navigator.of(context).canPop()` 为 false → AppBar 的 `automaticallyImplyLeading` 不画返回键。**两处硬编码返回键已改为按 `canPop()` 门控**：`lib/features/ims/menu/presentation/ims_tab_container.dart`（原 `leading: IconButton(icon: Icon(Icons.arrow_back), onPressed: () => Navigator.of(context).maybePop())`）与 `lib/features/data_center/presentation/data_center_screen.dart`。**新增全屏页别再硬编码返回键**，用 same 判定。
- **为什么必须用嵌套 Navigator（不能直接渲染 `entry.builder()`）**：**2026-09-16 更新 —— 闸门本身已改为就地渲染、不再 `pushReplacement`（见 §18.3）**，但嵌套 Navigator 仍然必需：页面内部的二级跳转（成绩 → 课程详情）要留在面板内、侧栏不消失，且此时二级页**照常**有返回键（只有面板的首路由才没有）。
- 侧栏是「选中」而不是「跳转」：`HomeSidebar(selectedTitle:, onSelect:, onOverview:)`（选中态 = 左指示条 3px + 加粗 + 8% 强调色底；顶部固定一行「数据一览」= 概览，也是唯一的回概览入口）；`home_service_catalog.dart` 的 `HomeServiceEntry` 新增 **`Widget Function() builder`**（`onTap` 仍在，宫格视图照旧 push 整页）。`HomeScreen` 因此从 `ConsumerWidget` 改为 `ConsumerStatefulWidget`（状态 `_selectedService`，**只活在页面 State、不持久化**；目录里已不存在的标题回落概览）。
- 守卫 = `test/home_detail_pane_test.dart`（6 例：服务页渲染在面板内且侧栏/根路由仍在、首路由 `canPop=false` → 无 `BackButton`/`arrow_back`、二级跳转留在面板内且二级页有返回键、换条目重置路由栈、**闸门式 `pushReplacement` 留在面板内**、两处 `canPop()` 门控的源码守卫）。
- **实证**（VM Service 探针 `D:\Temp\vmprobe\sjx_home_sidebar.py <ws> <条目名|__overview__>`：把 `_HomeScreenState._selectedService` 置值 + `setState`，再数树）：选「成绩」→ `navs=2 panes=1 sidebar=1 backButtons=0 arrowBackIcons=0`；回概览 → `navs=1 panes=0`。另有 `sjx_rect.py <ws> <key>`（按 Key 量屏幕矩形）与 `sjx_capsule_text.py`（读胶囊文本，实测 `#1/3/9`）——**胶囊这类小字别用截图 OCR，直接读控件树的 `Text.data`**。

### 17.8 仪表盘版式：左指标卡 / 右今日课程（2026-09-18 用户七轮裁定）

**七轮补丁（同日，用户原话：「主页课表卡片两个问题 1. 今天没有第三节晚课，但是组件里第二节晚课后没有空间了 2. 第一条分界线距离上下卡片距离和第二条不一样」）—— 当前口径（这两条是同一个几何模型）：**
- **时间轴全天占位**：`_todayCourseSlots` 返回 `SizedBox(key: Key('dashTodayTimeline'), height: schedulePeriodCount * todayCourseTrackHeight - todayCourseSlotGap + shifted)` —— **末尾没课的节次也留高度**，最后一门课之后始终有余量（当天最后一块 10-11 节 → 时间轴 414dp、块底 380dp、余 34dp = 一个节次）。旧的 `previousEnd == 0 ? 0 : (previousEnd-1)*track + slot`（末尾截断）**已删**，守卫禁止 `previousEnd == 0` 回归。
- **每条分隔线几何完全一致**：空档不足 `dashboardBreakBandHeight`(14) 时**把它撑开**（不是把带压扁）—— `extra = rawGap >= band ? 0 : band - rawGap`、`shifted += extra`，后续课块 `top = (start-1)*track + shifted`。任何一条线都是：带高 14 = 线上留白 4 + 线 2 + 线下留白 8；线底距下一块恒为 `dashboardBreakLineGap`(8)。⚠ 六轮那版「窄空档把带收缩进 4dp、线上下各 1dp」**已废**（与宽空档那条观感不一致，正是七轮报的「不一样」）。
- **几何算式（改代码/写断言照抄）**：`rawGapTop = (prevEnd-1)*track + slot`、`rawGapBottom = (start-1)*track`、`rawGap = rawGapBottom - rawGapTop`；带 `top = rawGapBottom + shifted(含 extra) - band`；**线底距带顶 = band − lineGap = 6**（`band` 已含线高，别再减一次 lineHeight —— 我第一版断言正是这么算错的：期望 4 实得 6）。真实数据（当天 3-5 / 6-7 / 10-11 节：午休 5→6 钟点差 100 分钟、时间轴只差 4dp；7→10 空两节 72dp）→ 午休那条撑到 14dp、7→10 那条仍 72dp、时间轴 414dp。守卫 = `test/home_dashboard_layout_test.dart` 的「两条分隔线几何完全一致 + 最后一门课之后仍留出全天余量（七轮）」例（同时断言 `Key('dashTodayTimeline')` 高度 = `12*34-4+10`）。

**六轮补丁（同日，用户原话：「我希望主页课表卡片内容宽度不够不要显示省略号，而是换行；缩小左右卡片间距；现在分割线有一条不可见，按理说是两条，但是现在只能看见第二条」）—— 栏间距与换行仍是当前口径；分隔线口径见七轮：**
- **栏间距 = `dashboardColumnGap = 10`**（原 16）：`Row[Expanded(flex: 2, child: metrics), SizedBox(width: DashboardPanel.dashboardColumnGap), Expanded(child: today)]`；守卫按 `today.dx - (metrics.dx + metricsSize.width) ≈ 10` 断言，**别写死 16**。
- **课名 / 教室放不下就换行**：`_todayCourseCell` 的 `Text` 由 `maxLines: 1` 改为 `maxLines: roomy ? 2 : 1`（`roomy = span >= 2`）—— 合并块内高 ≥ 60dp，2 行名称（2×14.375 = 28.75）+ 2 行教室（2×12.65 = 25.3）= 54.05 放得下；单节块内高仅 26dp，**只能一行**。`overflow: TextOverflow.ellipsis` 保留作极端兜底（超长名 / 系统大字号），外面套 `ClipRect` 保证兜不住时不会溢到相邻课块。守卫：`tester.widget<Text>(…).maxLines == 2` + 渲染高度 `> 12.5*1.15*1.5`（真的换行了）+ 单节块仍 `== 1`。
- **空档窄也要画线（正解「分割线少了一条」）**：旧实现 `if (gap >= dashboardBreakBandHeight(14))` 会把**午休式间隔**整条吃掉 —— 真实场景第 5 节 12:20 下课、第 6 节 14:00 上课（钟点间隔 100 分钟，`_isLongBreak` 为真），但两块课在时间轴上**相邻**，视觉空档 = `34 × 1 − 30 = 4dp` < 14 → 不画。⚠ **六轮那版「把分隔带收缩进 4dp、线上下各留 1dp」已被七轮取代**（观感与宽空档那条不一致），现口径见本节七轮补丁：空档不足带高就**撑开**，两条线几何完全一致。
- ⚠ 只改口径**不要**退回 `gap >= 14`：那正是用户报的「按理说是两条，只能看见第二条」。

**四轮补丁（同日，用户原话：「1. 我希望即使移动端，也是这种左右2：1的显示 2. 课表无课要按节数显示，不能一节无课和两节无课的占位高度是一样的；感觉今天最后一节课的显示位置不对，应该是贴着分割线的 3. 增大分割线的占位高度」）—— 当前口径：**
- **恒为 2 : 1，移动端不堆叠**：`dashboardSplitBreakpoint` 已删，`build` 直接 `Row[Expanded(flex: 2, child: metrics), SizedBox(width: DashboardPanel.dashboardColumnGap), Expanded(child: today)]`（栏间距见六轮）。⚠ 窄栏连带两处必修：① `_buildMetrics` 必须 `var cols = …; if (cols < 1) cols = 1;`（手机 2:1 后左栏 ≈200dp 时算出 0 列 → `gap*(cols-1)` 负宽度 + `/0` 得 NaN）；② 「今日课程」卡新增窄档 `todayCourseCardNarrowBreakpoint = 210`（卡内 `LayoutBuilder` 算 `narrow` → 藏掉 40×40 图标盒、内边距 `16,14,12,14` → `10,10,6,10`、标题 15→13、日期 12→10.5、刷新按钮 icon 18→16 且 `padding: EdgeInsets.zero`；课块字号 12.5/11 → 11/10、教室 11/9.5 → 9.5/9、块内左右内边距 8→5）。不收档时「图标盒 40 + 间距 12 + 刷新按钮 40」本身就超过 ~96dp 可用宽度（RenderFlex 溢出）。
- **空档高度 = 空节数 × 34 + 4**：`top(next) − bottom(prev)` = `空节数 × todayCourseTrackHeight + todayCourseSlotGap` → 「一节空 ≠ 两节空」是几何必然（38 vs 72，差整整一个轨道）。守卫直接按这两个数断言。
- **分隔线在「空档下部、且不贴死课块」**：`gapTop = (prevEnd-1)*34 + todayCourseSlotHeight`、`gapBottom = (start-1)*34`、`gap = gapBottom - gapTop`；画法 = `Positioned(top: gapBottom - 14, height: 14) > Padding(bottom: dashboardBreakLineGap(8)) > Align(alignment: bottomCenter) > Container(height: dashboardBreakLineHeight(2))` —— 即「线上留白 4 + 线 2 + 线下到课块 8 = 14」。理由（load-bearing）：居中会让「两节空」看起来只有一节空（线下方只剩半个空档）；而 2026-09-18 五轮用户又裁定「分割线距离卡片太近」，所以线底边必须离下方课块 `dashboardBreakLineGap = 8`（**别贴死、也别退回正中**）。⚠ **空档不足 14dp 时七轮起改为「撑开空档」**（见本节七轮补丁），不再收缩带高。Key 仍是 `dashTodayBreak-<nextStartPeriod>`。
- 守卫 = `test/home_dashboard_layout_test.dart`（8 例：源码守卫 `dashboardSplitBreakpoint` 已删 + `Expanded(flex: 2, child: metrics)`；宽屏例断言「线底 = 下一块顶 − 8」与 `top7-bottom3 == 2*34+4` 与栏间距 10；窄屏例 `≈ 2 ± 0.15`；「空档高度严格按空节数」用 `1-2/4-5` 与 `1-2/5-6` 两组算 38 vs 72；「午休式间隔 4dp 也画线」；「名称/教室换行」两例）。⚠ 同一 `testWidgets` 里换 fixture 必须先 `await tester.pumpWidget(const SizedBox())` 卸载，否则 ProviderScope 复用旧 container、新 override 不生效。⚠ `_todayCourseCell` 的字号三元必须写 `double` 字面量（`11.0` 而非 `11`），否则 `num` 不能赋给 `double?`（analysis 报 `argument_type_not_assignable`）。
- 测试辅助 `_app(courses, {withPeriodTable, periods})`：`periods` 缺省用 `_testPeriods`，午休例传 `_noonBreakPeriods`（第 2 节 09:35 下课 → 第 3 节 14:00 上课，两块课相邻）。

**三轮补丁（同日，用户原话：「1. 无课格子不显示不等于不占位 2. 宽度太宽，我希望与左侧成比例，应该大概左：右=2：1 3. 教室显示在课程名称下面」）—— 当前口径：**
- **绝对定位时间轴**（`_todayCourseSlots` 不再拼 `Column`，改为 `SizedBox(height: …) > Stack`）：
  `Positioned(top: (起始节 - 1) * todayCourseTrackHeight, height: (节数) * track - todayCourseSlotGap)`；
  `todayCourseTrackHeight = todayCourseSlotHeight(30) + todayCourseSlotGap(4) = 34`。
  于是**空节不画格子却仍然占位** —— 第 7 节的块永远在第 3 节的块下方 `4 × 34 = 136`（守卫按此断言，去掉占位时该距离只剩十几像素）；
  跨节块高度 = `节数 × 34 - 4`（2 节 = 64，与二轮公式等价）。
  **末尾没有课的节次不再占位**（`totalHeight = (lastEnd - 1) * 34 + 30`），否则卡片底部会拖出一大片空白 —— 要「整条 12 节时间轴」再说。
- **大间隔分隔线改画在空档中央**：`top = 上一块下沿 + 空档 / 2 - 0.5`（空档 = 上一门末节下沿 → 本门首节上沿），Key 仍是 `dashTodayBreak-<nextStartPeriod>`；因为现在空档本身占位，线只是标注。
- **分栏比例 = 左 : 右 ≈ 2 : 1**（`Expanded(flex: 2, child: metrics)` + `Expanded(child: today)`；**原来的 flex 2 : 3 已被否**）。守卫按 `metricsSize.width / todaySize.width ≈ 2 ± 0.12` 断言。
- **教室在课程名称下面**（`_todayCourseCell` 由 `Row` 改 `Column`：课名在上、教室在下、左对齐、都单行省略）。单节块只有 30px 高 → 两行各收一档字号（`span >= 2` 用 12.5 / 11，单节用 11 / 9.5，`height: 1.15`），否则 RenderFlex 溢出。
- 像素实测（`design_preview/round16_home_dashboard.png`，预览测试离屏渲染）：右栏 tint 列范围 x 931..1369 逻辑（宽 ≈ 437，面板 1352）、块间距实测 136.4 / 135.7 逻辑（= 4 个轨道 ✓）、空档里的细线正好落在空档中央（+36 逻辑）✓。
- 补丁脚本 `D:\Temp\_home_dash3.py`；⚠ **`cut()` 同一坑又踩了一次**：切 `Expanded(flex: …)` 那段时把 `],\n        );` 一起吃掉 → `Expected to find ']'.`，必须手工补回（教训见 §17.8 一轮段落）。


- 一轮原话：「首先去除两个小标题"数据一览""全部服务"，然后我们希望"今日课程"卡片不要显示在底部，而是把其他卡片显示在左侧，今日课程显示在右侧，然后按节数划分 12 个格子，但是不显示具体的节数列，但是要按具体节数填入课程，课程只显示名称和教室」。二轮改为（**当前口径**）：「我希望格子可以合并，然后无课格子不显示，同时要按时间表，在任意两节间隔超过 1h 的课程之间显示一条分隔线」→ **不再有固定 12 格**（第一版的 `todayCourseSlotCount = 12` 与 12 个空格子已撤）。
- **两个小标题已删**：`lib/features/home/presentation/dashboard_panel.dart` 的原「数据一览」竖条标题行（含它的刷新按钮）整段撤掉；`lib/features/home/presentation/home_screen.dart` 的 `_buildSectionHeader(context, '全部服务')` 与随之无用的 `_buildSectionHeader` 私有方法一并删除（留着会报 `unused_element`）。**唯一保留的「数据一览」是侧栏顶部的概览行**（`lib/features/home/presentation/home_sidebar.dart` 的 `homeSidebarOverviewTitle`，那是导航项不是小标题，别删）。
- **刷新入口**：全面板唯一刷新 = `Key('dashRefresh')` 的 `IconButton(tooltip: '刷新数据')`，挂在今日课程卡头部（原来在标题行右侧）；点击仍走 `DashboardPanel._refresh(ref)`（invalidate 5 个 provider + 推桌面小组件）。
- **分栏**：`DashboardPanel.build` 现在是 `LayoutBuilder` → **宽度 ≥ `DashboardPanel.dashboardSplitBreakpoint`（= 760）时 `Row(Expanded(flex: 2, 指标卡), SizedBox(16), Expanded(flex: 3, 今日课程))`**；更窄（手机竖屏 / 窄面板）→ `Column`（指标卡在上、今日课程在下）。指标卡区抽成 `_buildMetrics(...)`（`Key('dashMetrics')`，仍是按 `minCard = 210` 自适应列数的 `Wrap`），今日课程卡 = `Key('dashTodayCard')`。
- **今日课程 = 一门课一块（合并）+ 大间隔分隔线**（`_todayCourseSlots` → `_todayCourseCell` / `_isLongBreak`）：
  - 块：`Key('dashTodayCourse-<startPeriod>')`，高度 = `节数 × todayCourseSlotHeight(30) + (节数-1) × todayCourseSlotGap(4)`（跨节合并成一块，**不再一格一节**）；内容只有「名称 + 教室」（同日一轮裁定），无课节次**完全不渲染**。
  - 分隔线：`Key('dashTodayBreak-<nextStartPeriod>')`，当 `下一门课第一节的开始时刻 − 上一门课最后一节的结束时刻 > dashboardCourseBreakMinutes(60)` 时插入（`Padding(vertical: 8)` + 1px `AppColors.hairline`），否则只留 `todayCourseSlotGap` 的 4px 空隙。
  - 钟点来自**作息表**（与课表页同源）：`ref.watch(currentPeriodTableProvider).valueOrNull ?? ref.watch(cachedPeriodTableProvider).valueOrNull`（`lib/features/ims/schedule/domain/period_time.dart` 的 `PeriodTable.periodOf(index)` + `ClassPeriod.startMinutes/endMinutes`，靠 `ClassPeriod.parseHhmm`）；**作息表拿不到或节次缺失时一律不画线**（宁可不画）。
- 守卫 = `test/home_dashboard_layout_test.dart`（4 例：源码守卫「两个标题已删 / `_buildSectionHeader` 与 `todayCourseSlotCount` 都不得回归 / `dashTodayCourse`、`dashTodayBreak`、`dashboardCourseBreakMinutes = 60`、两个作息表 provider 必须在」；宽屏 widget 例注入自制作息表断言 4 块合并块（各高 64 = 2×30+4）、只写一次课名、`find.textContaining('节')` 为空、**间隔 20 分钟不画线、200/170 分钟画线**、两栏顶对齐且宽度和 = 面板宽 − 16；窄屏例断言上下堆叠 + 无课时只留提示且不画任何块；第三例断制作息表不可用时**不画线但块照常合并**）。
  ⚠ 该测试必须把 `currentPeriodTableProvider` **与** `cachedPeriodTableProvider` **都** override：面板取值链是 `current.valueOrNull ?? cached.valueOrNull`，首帧 current 还在加载时就会去读 `cached`，而 `cached` 会开 Hive box → 未 init 时抛 `You need to initialize Hive or provide a path to store the box.` 的未处理异步错误，直接把测试打挂（实测踩到）。
- 预览图 = `design_preview/round16_home_dashboard.png`（离屏 `RepaintBoundary.toImage` 渲染；像素实测：4 个 64.3 逻辑高的淡红块、块间 4px 小空隙两处、17px 分隔线两处 —— 与 20 / 200 / 170 分钟的三种间隔一一对应）。

## 18. 页面转场唯一口径（2026-09-16 立）

用户原话：「点开培养方案 / 课表 / 成绩 / 毕业学分这四个部分时，会显示一个由中心向外的扩张动画，我希望去除，另给每一个页面点开，添加一个过渡动画，具体效果你看看」。

### 18.1 被去掉的东西 = Flutter 的平台默认 zoom（不是本项目的代码）

- 根因在 SDK：`D:\Program\flutter\packages\flutter\lib\src\material\page_transitions_theme.dart:1049-1055` 的 `_defaultBuilders`：**windows / linux → `ZoomPageTransitionsBuilder`（从屏幕中心放大 + 淡入）**、android → `PredictiveBackPageTransitionsBuilder`（设备没有预测返回手势时同样回落 zoom）。本项目此前**没有任何自定义转场代码**（`lib/` 下 `PageRouteBuilder` / `ScaleTransition` / `Hero` 全无命中）→ 用户看到的「由中心向外扩张」就是它。
- **叠加因素（别只改主题）**：培养方案 / 课表 / 成绩 / 毕业学分都过 `ImsSplashScreen` 闸门，而闸门此前用 `Navigator.pushReplacement` 换掉自己 → 「点一下」连做**两次**路由转场 + 中间闪一帧转圈。只换转场主题不改闸门，观感仍是两次。

### 18.2 唯一实现 = `lib/design/app_page_transitions.dart`

- `AppPageTransitionsBuilder extends PageTransitionsBuilder`（覆写 `transitionDuration` = `appPageTransitionDuration` = **300ms**；该 getter 被 `material/page.dart:91` 读取，正/反同长）→ 包公开组件 `AppPageTransition`（**公开就是为了让测试能直接 pump**）：外层 `SlideTransition` 让位（`Tween(Offset.zero → Offset(-appPageExitOffsetX,0))`.animate(secondaryAnimation)）+ 内层 `SlideTransition` 进场（`Offset(appPageEnterOffsetX,0) → Offset.zero`）+ `FadeTransition`（`CurvedAnimation(parent: animation, curve: Interval(0, appPageFadeEnd))`）。
- 常量：`appPageEnterOffsetX = 0.04`、`appPageExitOffsetX = 0.025`、`appPageFadeEnd = 0.55`、`appPageTransitionDuration = Duration(milliseconds: 300)`、`appPaneSwitchDuration = Duration(milliseconds: 220)`、`appPaneSwitchOffsetX = 0.02`。
- **三条刻意选择**：① **不做任何缩放**（缩放就是被用户否掉的那个效果）；② 让位页**只位移不淡出**（两层同时半透明会发糊）；③ **iOS / macOS 保留 `CupertinoPageTransitionsBuilder`**（回滑返回手势比统一观感重要）。
- 挂载 = `appPageTransitionsTheme`（`PageTransitionsTheme(builders: {android / fuchsia / linux / windows: AppPageTransitionsBuilder(), iOS / macOS: CupertinoPageTransitionsBuilder()})`）写进 `lib/main.dart` 的 `ThemeData(pageTransitionsTheme: appPageTransitionsTheme)` → **全应用每个 `MaterialPageRoute` 都生效**，含侧栏右侧那个嵌套 Navigator（主题经 context 继承）。AndroidManifest **没有** `enableOnBackInvokedCallback`，所以丢掉 predictive back 不损失任何东西。
- 侧栏右栏的**面板切换**也用同一套语言：`home_screen.dart` 的 `AnimatedSwitcher(duration: appPaneSwitchDuration, …)`。⚠ **必须自备 `layoutBuilder: (c, p) => Stack(fit: StackFit.expand, children: <Widget>[...p, ?c])`** —— 默认那个用 `Stack(alignment: center)` 且不撑满，右栏内容会缩到中间。

### 18.3 IMS 入口闸门 = 就地渲染，不许再 pushReplacement

- `lib/features/ims/splash/presentation/ims_splash_screen.dart` 改为 `bool _ready` + `_target()` 就地渲染：`initialTab == null ? const ImsMenuScreen() : ImsTabContainer(initialTab: initialTab)`；会话已存在时在 `initState` 里同步 `_ready = true`（**首帧就是目标页，不闪转圈**）；失败面板「先看本地缓存」= `setState(() { _error = null; _ready = true; })`。
- 好处：整条路径只剩一次转场；不再有 `setState during build` 风险；侧栏内嵌时本页仍是面板栈的**首路由** → `canPop() == false` → 内嵌页照旧无返回键（§17.7 的口径不变，只是「为什么必须嵌套 Navigator」的理由变成「二级页要留在面板内」）。

### 18.4 守卫 = `test/app_page_transitions_test.dart`（9 例）

① 转场表四平台 = `AppPageTransitionsBuilder`；② **表里不得出现任何 `ZoomPageTransitionsBuilder`**（直接对着用户那句抱怨）；③ iOS/macOS = `CupertinoPageTransitionsBuilder`；④ 时长 300ms 且正向/反向同长；⑤ 动态：进场页从右滑入（早段位移 > 8px 且 ≤ 4%×800）、**ancestry 里不得有 `ScaleTransition`**、所有 `SlideTransition` 的 `dy == 0`、中段位移 < 早段一半、落位归零、淡入 mid-flight（0 < opacity < 1）；⑥ pop 逐帧找「向右滑出」那一帧；⑦⑧⑨ 源码守卫：闸门不许再含 `pushReplacement` / 不许再有 `addPostFrameCallback`、必须含 `ImsTabContainer(initialTab: initialTab)`；`main.dart` 必须挂 `pageTransitionsTheme: appPageTransitionsTheme`；`home_screen.dart` 必须有 `AnimatedSwitcher(` / `duration: appPaneSwitchDuration` / `fit: StackFit.expand` / `appPaneSwitchOffsetX`。
- 守卫里的 `_code(path)` **先剥注释行**（文档注释里会出现 `pushReplacement` 字样，不剥会误报）；源码守卫文件里 `library;` 必须写在 import **之前**（写在后面报 `library_directive_not_first`）。
- **三个测试坑**：① `find.text` 默认 `skipOffstage: true` —— 新页面不透明后，下面那页在转场中不被 finder 看见（要量它就 `skipOffstage: false`，或在**控件层**读 `SlideTransition.position.value`）；② pop 的退场动画要等路由处理完下一帧才起 → 改成逐帧循环找「向右滑出」的那一帧，别只 pump 固定帧数；③ fixture 必须真含被断言的文本。

### 18.5 实证手法：连拍量位移（动画类改动的唯一硬证据）

- `D:\Temp\vmprobe\sjx_click_burst.ps1 -Format Bmp -CropX/Y/W/H`（~30ms/帧；**PNG 要 ~70–100ms/帧，抢不到 220–300ms 的动画**）→ 用互相关量每帧的水平位移。
- 实测：**push 转场 34 → 27 → 21 → 13 → 9 → 3 → 1 → 0px 单调收敛，落位后残差精确 0.00**（若是 zoom，靠平移永远配不上、残差不会归零）；起点与 `0.04 × 1265 ≈ 50px` 吻合（第一帧抓到 easeOutCubic 的 34px 处）；**侧栏切换**同样量到 5px 位移（`diff@k=0` 8.55 → 平移后残差 5.20）。
- 窗口坐标：dpr 1.5、Flutter 报 physical 1898×1024（逻辑 ~1265×683），而 DPI 虚拟化的 PowerShell 看到 1280×720 → **窗口内点击坐标 ≈ 逻辑坐标 + (7, 30)**（实测 `(123,249)` / `(123,268)` / `(1202,58)` / `(1242,58)` / `(35,58)` 分别命中侧栏「课表」/ 侧栏「成绩」/ 顶栏齿轮 / 头像 / 返回键）。另有 `D:\Temp\vmprobe\sjx_shot_fast.ps1`（无 1.2s 等待的快速截图）。

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

## 20. 学科竞赛（第二课堂 · 申请与公示，2026-09-16 加）

用户原话：「第二课堂学分平台里有一个申请竞赛与竞赛公示的功能，实现出来」。官网菜单 = 团委模块
`/admin/tzz/dektSubjectGame/` 下的「学科竞赛申请」`apply_list.html` + 「学科竞赛公示」`gs_list.html`。
接口全表与字段列序见 **`reverse_engineering/竞赛接口.md`**（真实抓包整理）。

### 20.1 形态与代码位置

- 收在既有的 **`lib/features/comprehensive_service/`**（与第二课堂学分 / 志愿时长同一套 SSP 会话），没有另开 feature：
  `data/models/competition.dart` · `data/anti_corruption/competition_parser.dart` ·
  `data/datasource/competition_remote_datasource.dart` · `data/competition_repository.dart`（会话刷新重试一次）·
  `data/providers/competition_providers.dart`（`autoDispose.family`，查询条件对象带 `==/hashCode`）·
  `data/competition_image_picker.dart`（相册/拍照/文件，provider 可注入假实现）。
- 界面：`presentation/competition_screen.dart`（**两个 Tab：我的申请 / 竞赛公示**，`PaneBody(leading: TabBar, height: kTextTabBarHeight)`，见 §19）·
  `competition_apply_form_screen.dart`（申请表单）· `competition_pickers.dart`（选比赛 / 选成员，整页 push 回值）·
  `competition_detail_screen.dart`（详情，loader 注入，申请 / 公示共用）· `competition_widgets.dart`（分页条 / 状态胶囊 / 空态 / 错误卡）。
- 入口 = 首页服务目录 `home_service_catalog.dart` 的「学科竞赛」（`Icons.emoji_events_outlined`，
  `FeaturePalette.competition = #B8860B`）；目录条目 21 → **22**，已同步 `test/home_tile_alignment_test.dart`。
- 列表刷新：两个列表都是 `autoDispose` family，离开页面即释放；子页面返回用 `await push` 后 `invalidate`
  —— 因此**没有**挂 `PageAutoRefresher`（那套是给有本地缓存的页面用的）。

### 20.2 接口口径（**五条坑，改动前必读**）

1. **分页参数 = `pageNumber`，首查必须 `pageInit=yes`**：不带 `pageInit=yes` 时**筛选参数被服务端忽略**
   （实测 `search_like_gameName=蓝桥杯` 返回 0 条）；而**翻第 N 页要重复带同一批筛选参数、且不能带 `pageInit`**
   （带了会被强制重置回第 1 页）。唯一实现 = `competitionPageRequestParams({page, pageSize, filters})`。
   客户端没有 Cookie jar，官网靠 Cookie 记的查询条件我们靠**每次重发**。
2. **团队 `team` 字段存的是成员内部 id**（`find_student.do` 行内 radio 的 `value`，如 `350377`），
   **不是学号**（学号在表格第 1 列，如 `826200545`）→ `CompetitionStudent.rowId` 进 `team`，`studentId`
   只用于展示 / 搜索。官网 `setGame()` 读的就是 `:radio:checked` 的 value。团队「加自己」也因此必须先按学号
   搜一次学生列表拿 rowId（`_addSelf()`）。
3. **`add.do` 不做服务端校验**：字段全空也回 `{"type":"success","content":"申请成功"}`，但记录**不落库**
   （实测行数不变）→ 前端必须比照官网 `checkSubmit` 自校验：比赛 / 奖项 / 证书图片 ≥1 张 / 团队 ≥2 人。
   提交字段 = `gameId`、`remark`（`【赛别】奖项名`，赛别取 `find_game` 行的 `data-level`）、`type`（0 个人 1 团队）、
   `team`（分号相连）、`enclosure`（附件 id 逗号相连，先 `upload.do` 拿 `data[].id`）。
4. **dio 会把 JSON 应答自动解码**：`getCredit.do` / `add.do` / `delete.do` / `upload.do` 的 `Content-Type`
   都是 `application/json`，dio 默认 `ResponseType.json` → `response.data` 已是 Map/List，`data.toString()`
   出来的是 **Dart 字面量而非 JSON**，解析器会全判「格式不对」（奖项永远空、提交永远失败）。数据源 `_bodyOf`
   统一 `jsonEncode` 回文本 —— 同类坑见 §10.2 的 `JSONObject.wrap`。
5. **删除用数组参数**：`POST delete.do` body = `ids[]=<id>&ids[]=<id>`（jQuery `$.ajax` 默认 `traditional:false`
   的序列化）；`ids=<id>` 直接 400。

另两点结构差异：**公示详情分个人 / 团队两种** —— 团队记录**没有**「申请人姓名 / 学号」字段，改出一张
`团队成员列表` 表（排名/学号/姓名/学院/班级/得分，App 解析成 `团队成员 N` 字段行）；`select`（获得奖项 /
最终获得奖项）只有带 `selected` 的 option 才是当前值，未评奖时首选项 value 为空 → 解析成空串。

6. **获奖等级不在公示列表里**（2026-09-16 用户要求「竞赛公示每条要显示其获奖等级」时补）：
   `gs_list.html` 的 9 列**没有奖项列** → 等级只能**逐行拉 `xd_detail.html`**（走
   `competitionPublicityAwardProvider`，`autoDispose.family` + 卡片懒构建 = 只有进视口的行才发请求，
   滚走即释放）。取自详情的方式：**优先「最终获得奖项」**（评定后才写，实测当页 20 条**全空**），
   否则用「学生提交的奖项」（`【赛别】奖项名`，实测 20/20 都有：`【校赛】参与未获奖` ×17、
   `【省赛】三等奖` ×2、`【校赛】一等奖` ×1）；赛别前缀只存在于后者 → 用最终奖项时沿用它的前缀。
   解析口径 = `CompetitionAwardLevel.parse`（去 `(2)分` 分值后缀、`无` 视为空）+ `competitionAwardLevelOf(detail)`；
   展示 = `省赛 · 三等奖`（国赛金 / 省赛蓝 / 校赛绿 / 参与未获奖灰），取不到时**整颗胶囊不显示**。

7. **申请条目右侧的「此项加分」（2026-09-18 加 · 用户原话：「我希望学科竞赛申请页面，要在每个申请条目右侧显示此项加分」）**：
   **申请列表没有奖项列、也没有分值列**（`apply_list.html` 10 列 = 序号 / 比赛年份 / 学号 / 姓名 / 比赛名称 /
   类型 / 申请时间 / 附件 / 审批状态 / 操作），而且**申请详情端点 `detail.html` 自 2026-09-18 起对全部记录返回
   200 +「出错了」页**（实测 4/4 条、换 id 同样；志愿活动详情页是同一类服务端故障）→ 加分的唯一来源是
   **公示详情端点 `xd_detail.html`**：**申请记录的 id 与公示记录是同一套**，
   `xd_detail.html?id=<申请 id>&code=look&team=个人` 返回同一条记录，且带三样东西 ——
   ① `学生提交的奖项`（`input[readonly]`，`【赛别】奖项名`，**每条都有**）；
   ② `最终获得奖项`（`select[disabled]`）= **该赛别的完整分值表**（选项文案自带分值：`三等奖(5)分`，
      旧版还带赛别前缀 `【国赛】三等奖(5)分`，占位首项是 `无` / 旧版 `请设置奖项`），评定后给那一档写 `selected`；
   ③ `个人得分`（`input[readonly]`，未评定为 `0分`；**团队记录没有这一项**，改出团队成员表）。
   - 解析 = `parseCompetitionApplyAward(html)` → `CompetitionApplyAward{submitted, granted, submittedScore,
     grantedScore, personalScore, options}`；小件 = `competitionScoreValue` / `parseCompetitionAwardOptions` /
     `competitionOptionScoreFor` / `competitionAwardKey`（同文件）。⚠ `competitionAwardKey` 要同时去 `【…】`
     前缀与 `(N)分` 后缀 —— **新旧两版文案写法都要能对上**，否则「学生提交的奖项」认不出档位。
   - **分值取值顺序 = 个人得分（> 0）→ 最终获得奖项分值 → 申报奖项按该赛别标准的分值**（`scored` =
     个人得分 > 0 或已选定最终奖项；`0分` 一律当「未评定」，别当成 0 分实得）。
   - 链路 = `CompetitionRemoteDataSource.fetchApplyAward` → `CompetitionRepository.fetchApplyAward` →
     `competitionApplyAwardProvider`（`autoDispose.family`，key = `({int id, CompetitionType type})`，
     卡片进视口才请求 —— 与第 6 条的公示等级同一套路，**别改成整页并发拉 20 条**）。
   - 展示 = `CompetitionApplyAwardChip`（未评定 → `预计 N 分`，`FeaturePalette.competition` 琥珀金；已评定 →
     `N 分`，`AppColors.success` 绿）+ `showCompetitionApplyAwardSheet`（弹层 = 这一项的加分 / 你申报的奖项 /
     最终获得奖项 / 个人得分 / **该赛别的分值标准**，申报那一档加粗上色）。胶囊排在审批状态胶囊**之前**（同一行
     右侧，自带 6px 右间距）；拉取失败 / 没有奖项 → 整颗不显示，读取中 → `…` 占位。
   - **顺带修好一个空白页**：`fetchApplyDetail` 解析出空字段时**回落到公示详情端点**
     （`_fetchPublicityDetailBody`）—— 点申请条目进详情页以前整页空白（`detail.html` 已「出错了」）。
   - 实测该账号 4 条 = 百度之星【省赛】二等 **预计 3 分** / 中国高校计算机大赛【国赛】三等 **预计 5 分** /
     蓝桥杯【国赛】一等 **预计 10 分** / 蓝桥杯【省赛】一等 **预计 4 分**；像素实测胶囊文字 `#EDBF4F`
     （= `featureTone(#B8860B)`）、底 `#483E25`（= 同色 10% 叠卡片）。评审图 =
     `design_preview/round17_competition_award.png`（列表）/ `round17_competition_award_sheet.png`（弹层）。
### 20.3 守卫与验证

- `test/competition_test.dart`（真实 fixture 解析 + 口径 + 漂移：列位置、行 id、`pageSkip` 总页数、`data-level`
  赛别、团队 `rowId`、团队成员表、奖项 JSON、写应答、分页参数两条、端点与字段拼法守卫）。
- `test/competition_screen_test.dart`（两 Tab 渲染、翻页把 `page: 2` 交给 provider、搜索回到第 1 页、公示页无 FAB
  —— 全部 provider override 喂假数据，不碰网络）。
- Fixture = `test/fixtures/_competition_*.html`（真实抓取、已裁 script/style）+ `_competition_awards.json`。
- `test/competition_apply_award_test.dart`（21 例：分值文案 / `competitionScoreValue` / `competitionAwardKey` /
  分值表解析（现行版 + 旧版带赛别前缀 + 校赛 0.1 档 + 结构不符）/ 一条记录的加分（未评定、旧版申请详情、
  团队无个人得分、已评定个人得分优先、解析不到 → empty）/ 界面（`预计 N 分`、点开弹层与分值表、两条各自显示、
  loading 占位 `…`、取不到不显示）/ 源码守卫（胶囊与弹层接线、加分走 `xd_detail`、申请详情回落、
  胶囊与弹层不许硬编码颜色）。
- 新 fixture = `test/fixtures/_competition_xd_detail.html`（2026-09-18 抓的**现行版** `xd_detail`，已脱敏）；
  旧 fixture（`_competition_apply_detail.html` / `_competition_publicity_*.html`）继续用于旧版文案与团队记录。
- 端到端真实验证手法（可复用）：临时 `test/tmp_*.dart` 里 `CompetitionRemoteDataSource(Dio(...))` 直连，
  会话 id 从 `$env:SSP_SID` 读（`app_data/sspauth.hive` 用 latin1 解码 + 32 位十六进制正则抽 JSESSIONID，
  再用 `StuVolWork/stu_list.html` 验有效性）——**只调只读接口**，别在平台上写真实数据；跑完删文件。

## 21. 小程序三个服务的落地（2026-09-16 · 用户原话：「本科生成绩单实现到现有的成绩页」「还有一个网络服务，整合到现有网费功能里，网费功能的名字改成『校园网』」「还有一个『我的邮箱』功能，做成独立功能」）

### 21.0 通用侦察法（**先读这一条，别再抓包**）

智慧江财是**门户式（低代码）小程序**：所有服务都是门户后台下发的条目，条目里带真实地址。
**只要已配置平台 GUID，就能把全部门店列出来**（实测 2026-09-16，49 条）：

```
GET https://wxcourse.jxufe.cn/platForm/api/littleProgram/application/getHotAppsByPlatformUsername?platformUsername=<GUID>
GET …/getNewAppsByPlatformUsername?platformUsername=<GUID>
GET …/getMyAppsByUserDefaultRole?platformUsername=<GUID>
→ {code:1,success:true,result:[{appName,appId,applicationId,url,classify,count}…]}
```

单条服务的**完整元信息**（含 memo 说明与带签名入口）走 `checkAppAuth`：

```
GET …/api/littleProgram/application/checkAppAuth?appid=<appId>&platformUsername=<GUID>
→ {code:200,result:{name,memo,typeC:'H5',isCredible,pageUrl:'…带 cardinfo/openId 签名…',username:'<加密账号 enc>'}}
```

- `result.username` = **加密账号（enc）**，H5 的 `?userId=` 参数；`pageUrl` = H5 入口（`useVersion 2.0` 时由服务端按会话签发）。
- 本账号实测条目：本科生成绩单 `1741570971384`／本科生在校证明 `1741570790414`／网络服务 `1575336885141`／我的邮箱 `wx0bc2c17d023b213d`（**跳独立小程序**，门户侧只有账号类接口）／网络故障报修 `1575430876461`。
- 报文头（全部这些接口都要）：`Referer: https://servicewechat.com/wx70c0beda0bb7b021/143/page-frame.html` + 浏览器 UA（仓库已有 `deviceProfileRepositoryProvider.userAgent`）。
- 侦察脚本（可重复跑，**只读**）：`tools/_wxapkg_unpack.py`（PC 微信 wxapkg 解密解包，需 `D:\Program\Python\Python313`）、`tools/_wxapkg_scan.py`（全分包关键词检索）、`tools/_wx_mail_probe.py` / `_wx_apps_probe.py` / `_wx_cert_probe.py` / `_wx_netsvc_probe*.py` / `_wx_email_probe*.py`（本轮新增：从已解密包与门户接口挖邮箱 / 成绩单 / 网络服务），报告落在 `.scratch/wx_*.txt`。

### 21.1 本科生成绩单（成绩页入口）

- **官方只有「邮箱投递」，没有下载接口**（教务处 2025-05-20 上线口径，H5 = `/jxufeLayuiApp/certificate/undergraduate/scoreIndex.html`）：
  - `POST https://wxcourse.jxufe.cn/layuiApp/score/verifySecondMajor`（form `userId=enc`）→ `{status,message:",1,2"}`：**message 从下标 1 起按 `,` 切**，`1`=有主修、`2`=有辅修（本账号实测 `,1`）。→ 报表类型 `1` 主修(中)、`11` 主修(英)、`2` 辅修(中)、`22` 辅修(英)。
  - `POST …/layuiApp/score/bkscj`（form `userId`/`email`/`courseId`）→ `{status,message}`，**服务端把盖章 PDF 发到该邮箱**。
  - 在校证明同构：`POST …/layuiApp/studentCertificate/bks`（form `userId`/`email`）。
- **⚠ enc 必须按 form 编码提交**：enc 形如 `AAAAAAAAAAAAAAAAAAAAAA==`，H5 里专门写了 `if(username.indexOf("=")!=-1||username.indexOf("+")!=-1) username=encodeURIComponent(username)`。Dio 的 `data:{}` + `Headers.formUrlEncodedContentType` 与之同口径（`+`→`%2B`、`=`→`%3D`），守卫 `test/transcript_test.dart` 断言请求体里出现 `userId=…%3D%3D`。
- **本机网络取不回 PDF**：学生邮箱 `stu.jxufe.edu.cn` 的 993/143/443/25 **全 timeout**（`mail.jxufe.edu.cn` 仅 :25 通），IMAP 代取方案不可行 → 用户 2026-09-16 拍板「发送后我自己去邮箱下载」，**不要再试图做本地落盘**。邮箱 Web 入口仅校园网可达。
- 实现：`lib/features/ims/grades/domain/transcript_report.dart`（`transcriptReportTypes` / `transcriptEmailValid` / `kTranscriptVerifyUrl`）、`data/datasources/transcript_remote_datasource.dart`（`fetchEncUserId` / `fetchReportTypes` / `sendTranscript`，DioException 统一转 `TranscriptApiException`）、`data/providers/transcript_providers.dart`（`transcriptEncUserIdProvider` / `transcriptReportTypesProvider` / `transcriptDefaultEmailProvider`）、`presentation/transcript_sheet.dart`（弹层：类型下拉 + 邮箱 + 发送 + 学信网链接）。
- **入口位置 = 筛选栏下方一行 `TextButton.icon`（`Key('grades_transcript_entry')`）**，位于 `grades_screen.dart` 的 `_buildTranscriptRow`，**不要塞进 AppBar**：内嵌（侧栏模式）时成绩页不画导航栏（§19），按钮必须落在内容里。
- **邮箱默认值 = 学生邮箱地址**（`transcriptDefaultEmailProvider`）：**首选**邮箱接口给的权威值（`myMailboxProvider`），**回退**登录账号（= 学号）+ `@stu.jxufe.edu.cn`。⚠ **别用学籍 `serialNo` 拼**：实测本账号 `serialNo = 201600035929`（12 位学籍号），而学生邮箱是 **10 位学号** `2000000000@stu.jxufe.edu.cn`（首版用 serialNo，真机验收直接暴露成错的邮箱地址）。

### 21.2 网络服务（并入「校园网」页第二段 · 2026-09-16 二轮已打通**真数据**）

- 本体 = 广州热点 Dr.COM **「用户自助服务系统」**（`https://wxcourse.jxufe.cn/1575336885141/`），
  身份 = 小程序 `applicationId 196 / appId 1575336885141 / classify '6' = 生活`，`type 3`（H5）。
- **登录链（关键就一个参数，别再试别的）**：
  `checkAppAuth(appid, platformUsername=GUID)` → `result.username`（enc 学号）+ `result.pageUrl`
  → **`GET <pageUrl>&userId=<urlencode(enc)>`** → 302 且 `Set-Cookie: JSESSIONID=…` → 之后只带
  `Cookie: JSESSIONID=…` 即可。此前「只带 pageUrl 自带 cardinfo/openId」一律 302 回 `/login/`，
  根因 = 小程序 `pages/modules/app/detail/view.js` 会**追加 `userId`**（`jwtToken` 传空串也行，
  `accessKey/colleageCode/jssdk_url` 可省 —— 逐项实测过）。
- **会话失效**：业务请求返回登录页（含「用户自助服务系统」且含 `name="password"`）→ 自动重登一次并重试；
  仍失败则报「会话已失效」。**CSRF**：写操作 token **每页现取**，两种写法都要认
  （`var AJAXCSRFTOKEN = '…'`、`"ajaxCsrfToken=" + '…'`、隐藏域 `name="csrftoken" value="…"`）。
- **⚠ 第四个坑（真机才暴露的静默空数据）**：这套服务端**有一半接口不回 `Content-Type`**
  （实测 `dashboard/getLoginHistory`、`bill/getMonthPay`、`bill/getPayMent`、`bill/getOperatorLog` 完全没有该头），
  Dio 便**不做 JSON 解码**→ 返回 `String` → `networkList(String)` **静默变空列表**，
  界面显示「暂无记录」而服务端其实有数据（近期上网记录 / 历史账单都中招）。
  修法 = 全链路 `ResponseType.plain` + `NetworkServiceRemoteDataSource._decodeJson`（按正文首字符判 JSON）。
  **教训**：凡「无 content-type 也返回 JSON」的服务端，别依赖 Dio 的内容协商；
  解析器也**不要**把「类型不符」默默当空集合（该抛就抛，否则静默空态骗过测试）。
- **拿数必看的三个坑**：① 账号概览**只能**从 `/dashboard` 的 `window.user` 内嵌 JSON 扒
  （`dashboard/refreshaccount` 是 fire-and-forget，**空响应**）；② `bill/getUserOnlineLog` **必须带
  `startTime`/`endTime`**，`bill/getMonthPay` **必须带 `year`**，否则返回空；③ 账单 `rows` 的结束时间是
  **开区间端点**（= 下期开始、上一期结束 == 下一期开始），学校页面显示的结束日要**减一天**
  （`NetworkMonthBill.endDay`）。
- 实现（`lib/features/network_service/`）：`data/datasources/network_service_remote_datasource.dart`（会话缓存
  + 自动重登 + token 现取 + 全部读写接口，与网费共用 `netFeeDioProvider`）、`data/providers/network_service_providers.dart`
  （整组 provider + `invalidateNetworkService(WidgetRef)` 做**写后对账**）、
  `domain/network_service_models.dart`（容错解析）+ `domain/network_service_format.dart`（**纯格式化，无 Flutter 依赖**，
  由 `presentation/network_common.dart` re-export 给页面）、`presentation/network_service_section.dart`（校园网页第二段）
  + `network_records_screen.dart` / `network_devices_screen.dart` / `network_services_screen.dart` / `network_profile_screen.dart`。
  旧的「只做一个『打开网络服务』按钮」那套（`fetchNetworkServiceUrl` / `netFeeNetworkServiceUrlProvider` / `_buildNetworkServiceCard`）**已删除**。
- **敏感信息口径**：上网密码（服务端下发明文）**默认掩码**、点开才显示、复制取真值；身份证号只显示前 3 后 4；都不写日志。
- **写操作**（报停 / 复通 / 预约套餐 / 解绑设备 / 强制下线 / 改密码 / 改资料）一律
  **二次确认（危险操作红色按钮）→ 提交 → 写后对账刷新**，与选课写操作同口径；文案只在有服务端文案时用它。
- 未做：上网记录导出（`/bill/exportUserOnlineLog`）、在线充值支付流程（微信充值只做「带账号跳学校支付页」）。
- 抓包/接口全表见 `reverse_engineering/网络服务接口.md`。
- **强调色 = 主题红，别再给这一段单独配色**（用户 2026-09-16 当场问「怎么这部分主题色是青色」）：
  首版给「网络服务」注册了 `FeaturePalette.networkService = #00838F`（青蓝）当装饰强调色，结果
  **同一张「校园网」页里第一段（余额）红、第二段（网络服务）青蓝**，违反 §16「单色强调一律改主题红」。
  已改为 `networkAccent(context) => Theme.of(context).colorScheme.primary`
  （`presentation/network_common.dart`；`kNetworkAccent` 常量已删），`FeaturePalette.networkService` 一并撤掉。
  段落区分靠**分组标题 + 卡片结构**，不靠换色；**只有状态语义**才用别的颜色
  （正常/在线 = `FeaturePalette.networkServiceOk` 绿、停机 = `FeaturePalette.networkServiceStop` 红）。
  ⚠ 改这里后要连带处理 `const Icon(...)` / `const TextStyle(...)`（`color:` 变成运行时调用后
  `const` 会报 `const_eval_method_invocation`）。


### 21.3 我的邮箱（独立功能，只读）

- 小程序侧「我的邮箱」= **跳独立小程序** `wx0bc2c17d023b213d`（门户还有「绑定邮箱」`pages/center/email/view`、「更换邮箱」`amendEmail`、「邮箱密码」`emailDetail/emailPasswd` 三个原生页）。App 侧只做门户能拿到的账号信息，用户 2026-09-16 拍板**只要「查看账号 / 初始密码 / 复制邮箱 / 复制初始密码」四项**（不做未读数、不做改绑）。
- 门户接口（`username` = **GUID 本身**，无需换 enc）：
  - `GET https://wxcourse.jxufe.cn/platForm/api/wx/email/getPwd?username=<GUID>` → `{email:'2000000000@stu.jxufe.edu.cn',pwd:'<10 位初始密码>'}`（实测通过）。
  - （未采用）`GET /api/third/email/getNoReadNums?username=<user_id>` = 未读邮件数；`POST /api/littleProgram/login/getSmsCode` → `validateSmsCode` → `bindEmail` = 改绑邮箱（写操作）；`GET /api/littleProgram/login/getUserInfo` 的 `email` 字段 = 门户绑定邮箱（本账号 null）。
- 实现：`lib/features/my_mail/`（`domain/student_mailbox.dart` 含 `myMailMaskPassword` / `myMailStudentAddress`、`data/datasources/my_mail_remote_datasource.dart`、`data/providers/my_mail_providers.dart` 的 `myMailboxProvider` + `kMyMailNeedGuid` + `myMailNeedsGuid`、`presentation/my_mail_screen.dart`）+ 首页目录条目（`FeaturePalette.myMail`）。
- **密码默认掩码**（`'*' × 长度`，小程序同款），点眼睛才明文；**掩码状态下复制按钮也复制真值**。

### 21.4 「网费」→「校园网」改名（展示层；**内部标识不动**）

- 改的全是**用户可见字符串**：目录条目（`home_service_catalog.dart` 标题 + 副标题「余额充值 · 网络服务」）、`net_fee_screen.dart` 的 AppBar 标题与记录类型文案（校园网充值/校园网记录）、净费接口异常文案、`dashboard_panel.dart` 指标标签、`data_center_screen.dart` 单元格标签、GUID 向导/设置页/请假页提示语、`android/…/values/strings.xml` 八个小组件描述、README。
- **刻意不改**：类名/目录（`net_fee`、`NetFee*`）、Hive box 与 key、仪表盘快照 cell 标签键以外的东西、桌面小组件 `home_widget_dashboard_*` 资源名与 `home_widget_sync.dart` 的 `add('校园网', …)`（**标签即快照键**：`home_widget_background.dart` 的 `'校园网': prev['校园网']` 必须同步，旧快照里的 `'网费'` 格会在下次前台同步时自愈为 `—`）、数据中心 `fieldName: '网费余额'`（**数据中台字段名，不能改**）。
- 守卫：`test/pane_chrome_test.dart`（断言 `net_fee_screen.dart` 里是 `'校园网'`）、`test/home_widget_snapshot_test.dart:563`、`test/home_tile_alignment_test.dart`（条目数 **23**）。

### 21.5 守卫与验证

- `test/my_mail_test.dart`（15 例：掩码/地址约定/JSON 容错、datasource 成功与四类失败、provider 未登录与缺 GUID、页面掩码-明文切换与两条复制写剪贴板）。
- `test/transcript_test.dart`（15 例：类型解析六种 message、邮箱正则、enc 的 form 编码守卫、发送成功/失败、弹层预填/发送/空邮箱/格式错/服务端报错/类型拉取失败）。
- `test/network_service_data_test.dart`（34 例：登录链与 Cookie 复用 / 未下发 Cookie / 空 GUID / 登录页自动重登、
  `window.user` 字段映射（含「套餐计费方式取 `userGroup.payStyle` 而非顶层」）/ 在线会话与上网记录数组行映射 /
  明细必带日期范围 / 账单必带 year 与「含末日 = 结束时间减一天」/ 充值明细与办理记录的列序 / 空 rows 不抛 /
  七类写操作的表单参数与 token / HTML 抽取工具三种写法 / 模型容错与格式化真值）。
- `test/network_service_ui_test.dart`（14 例：第二段账号概览与密码掩码-显示切换、在线设备与下线入口、近期记录、
  七个明细/业务入口 + 微信充值走外部打开、缺 GUID 提示去配置、强制下线真发请求并提示、账号服务页三项业务与
  立即报停 POST（flag=1 + token）、预约套餐弹层取页面卡片并 POST serid、账单四页签渲染与年度合计、
  设备页在线与已绑定、账号设置页证件号掩码与改密码两处校验、`inAppWebViewSupported` 真值表）。
  **三个测试坑**（都踩过）：① `TabBarView(children: [...])` 在 build 时**构造全部子页** → 四个分页的 provider
  都会被 watch，未 override 的那个会去 `Hive.openBox` → `HiveError`（测试里没有 `Hive.init`）；
  ② 测试环境 `defaultTargetPlatform` 是 android → `inAppWebViewSupportedProvider` 默认 true，
  要验桌面分支必须 override 成 false；③ 假 `HttpClientAdapter` **必须按 body 区分 content-type**
  （JSON 才给 `application/json`），否则 Dio 的 JSON 转换器会对 HTML 页面抛 `FormatException`，
  报出来是「服务响应格式异常」这种误导性文案。
- 端到端真实验证（可复用）：`tools/_wx_email_probe.py`（getPwd / getUserInfoData / getNoReadNums 三连）、`tools/_wx_cert_probe.py`（checkAppAuth → enc → verifySecondMajor；`--send <email>` 才发信）、`tools/_wx_apps_probe.py`（应用列表）。

### 21.6 不靠点击的 UI 验收法（2026-09-16 新增，很值得复用）

**像素点击测 Flutter 桌面 app 不可靠**（`view_image` 报的中文坐标偏差极大：同一行报 590 与实际 380 差 200+；`mouse_event` 滚轮 Flutter 不接收）。改用 **VM Service 驱动 + 元素树检索**：

1. `tools/_vm_eval.py <ws-url> [library-uri-substring] "<单行表达式>" [--out x.txt]` —— 通用求值探针。
   - ws-url：`(Select-String "$env:TEMP\ge_flutter_run_windows.log" -Pattern 'ws://127\.0\.0\.1:\d+/[^/]+=/ws').Matches[0].Value`
   - **`--out` 必用**：终端直打中文是 GBK 乱码，写文件再 `read`。
   - 表达式必须**单行**；库作用域 = 该库直接 import 的名字（`home_service_catalog.dart` 的库含 `MyMailScreen` / `NetFeeScreen`，但**不含** `GradesScreen` → 后者要用 `grades_screen.dart` 自己的库）。
2. **推页面**（确定性导航，不猜坐标）：
   ```dart
   (() { NavigatorState? nav; late void Function(Element) visit; visit = (Element e) { if (nav != null) return; if (e is StatefulElement && e.state is NavigatorState) { nav = e.state as NavigatorState; return; } e.visitChildren(visit); }; visit(WidgetsBinding.instance.rootElement!); (nav as NavigatorState).push(MaterialPageRoute<void>(builder: (BuildContext c) => const XxxScreen())); return 'pushed'; })()
   ```
   开弹层同理：`showTranscriptSheet((nav as NavigatorState).context)`（在 `transcript_sheet.dart` 的库作用域里求值）。
3. **验内容（硬证据）**：遍历 `Element` 树取 `Text.data` / `EditableText.controller.text`：
   ```dart
   (() { final hits = <String>[]; late void Function(Element) v; v = (Element e) { final w = e.widget; if (w is Text) { final d = w.data ?? ''; if (d.contains('关键词')) hits.add(d); } else if (w is EditableText) { hits.add('EDIT[' + w.controller.text + ']'); } e.visitChildren(v); }; v(WidgetsBinding.instance.rootElement!); return hits.length.toString() + ' :: ' + hits.join(' || '); })()
   ```
   本轮靠它验出：校园网第二段 5 个文本全在树里（⇒ checkAppAuth 现取签名 URL 真机成功）、成绩单弹层的报表类型是**真从服务端拿的**（`主修成绩单（中）`）、以及**一个真 bug**——预填邮箱曾用学籍 `serialNo`（12 位 `201600035929`）。
4. **滚动**：`ScrollableState` 也能遍历到（`s.position.jumpTo(maxScrollExtent)`）；页面里通常有多个 Scrollable（侧栏 / 仪表盘 / 页面自身），用「子树里是否含目标文案」挑对的那个。
5. ⚠ `debugDumpApp()` 在 flutter run 里**只把首页路由那部分写进日志**（有 `MaterialApp`/侧栏、没有 pushed 页面）→ 别用它验 pushed 页面。
6. 截图脚本 `tools/_shot.ps1 -Out x.png [-ClickX/-ClickY] [-Wheel/-WheelSteps]`（自动还原最小化窗口、可选点击/滚轮）仍要跑，但只当「大致观感」；**控件树命中才是硬证据**。

## 22. 深色模式（2026-09-16 立 · 用户原话：「给应用适配深色模式」）

三个口径由用户在看过设计预览后逐项拍板：① 深色底色阶梯 = **A · 中性深灰**（预览 `design_preview/dark_mode_preview.html` 四列对比 A/B/C，用户回了一个字「A」）；② 深色强调色 = **亮红档**（初版 `#FF6B6E`，用户 2026-09-16 上机后反馈「成绩页、加载圈的红色太浅了，回调一些」→ 已收到 **`#F2555A`**，五档对比见 `design_preview/dark_accent_presets.html`；浅色仍是校徽红 `#C3282E`）；③ 模式入口 = **设置页「外观」节 · 跟随系统 / 浅色 / 深色 · 默认跟随系统**。

⚠ **同一轮修掉的真缺陷（别改回去）**：`ColorScheme.fromSeed(brightness: dark)` 给的 `error` 是 M3 深色默认的 **`#FFB4AB`（极淡粉红，#121212 上 11.03:1，几乎发白）** —— 成绩页的错误标记 / 虚框 / 进度条都吃它，用户说的「成绩页太浅」就是它。现由 `kErrorRedDark = #EE4C50` 显式覆写（`lib/design/app_theme.dart`），`onError` 随之翻成深字 `#1A1A1A`（原 `#690005` 压新错误色只有 3.61:1）。**深色下任何「红」都要先查是不是漏改的 M3 默认值**（`error` / `errorContainer` / `tertiary` 都是种子派生的淡色）。

**当前档位（压 #121212 的对比度）**：`primary #F2555A` = 5.55:1 · `error #EE4C50` = 5.16:1；压卡片底 #1A1A1A 分别 5.16 / 4.79，均 ≥4.5。再往深调（如 `#E5484D`）会掉到 4.45 且需把 `onPrimary` 从深字翻回白字 —— 深过 `#E5484D` 之前先让用户看预览的第 4/5 档。Fluent 三档同源：`accentDark = cardAccentDark`、`accentSecondaryDark = #DA4D51`（×0.90）、`accentTertiaryDark = #C24448`（×0.80）、`accentDisabledDark = 0x66F2555A`。
⚠ **深色下的「红」分两个角色，不许合并（2026-09-16 第五轮 · 用户原话「我说的是成绩页的按钮背景，卡片的框线，太浅了」）**：`colorScheme.error`（`#EE4C50`）是**当文字/标记用**的亮红档 —— 它必须压得住 `#121212`，所以只能偏亮；而**实心件（筛选 chip 底 / 成绩表表头底）与描边（统计卡红框线）不需要跟页面底比对比度，需要的是「深、饱和、实」**，另立一档不透明深红 `AppLadder.darkErrorFill = #C62828`（白字压它 5.62:1；压卡片底 3.10:1、压页面底 3.33:1）。成因实测：改前 chip 底直接吃 `error`、框线吃 `error.withValues(alpha: 0.7)`（叠在卡片 `#1A1A1A` 上混成 `#AE3D40`，对卡片只有 **2.93:1**，低于 3:1 的图形对比度门槛 —— 发灰发脏）。**唯一入口 = `lib/design/app_theme.dart` 的 `AppColors.errorFill / onErrorFill / errorBorder`**（浅色下三者 = 原来的 `scheme.error` / `scheme.onError` / `error@70%`，逐像素冻结）；**两个角色不许互换**：深红 `#C62828` 压页面底只有 3.33:1，**不能**反过来当正文色。别处再也不要写 `colorScheme.error.withValues(alpha: 0.7)` 当框线。守卫 = `test/theme_dark_test.dart` 组②「深色下「红」分两个角色」+ 组⑥「AppColors 的错误红三态」（含源码守卫：成绩页不得再出现 `colorScheme.error.withValues(alpha: 0.7)` 与 `headerBgColor: theme.colorScheme.error`）。对照图 `design_preview/dark_red_role.png`（浅色 / 深色改前 / 深色现在 三列）。
**已切换到 `AppColors.errorFill / onErrorFill` 的实心红件（全仓清点过，7 处）**：成绩页筛选 chip 底 + 成绩表表头底 + 表头文字/排序箭头（`lib/features/ims/grades/presentation/grades_screen.dart`）、选课「确认退选」危险按钮（`lib/features/ims/course_selection/presentation/selection_result_view.dart`）、校园网「危险确认」按钮（`lib/features/network_service/presentation/network_common.dart` 的 `networkConfirm`，`danger` 分支）、校园网「立即报停」按钮（`lib/features/network_service/presentation/network_services_screen.dart`）、账号卡头像底 + 其上前景 + 账号卡「登录」按钮底（`lib/features/ims/student_info/presentation/account_screen.dart`）、共享头像 `AccountAvatar` 底 + 其上前景（`lib/shared/widgets/account_avatar.dart` —— 注意这个文件原先全用 `scheme.onError` 当「压在 error 底上的前景」，现已整体换掉，`scheme` 局部变量已删）。**`FilledButton` 只改底色不改前景会翻车**：默认前景取 `colorScheme.onPrimary`（深色 = 深字 `#1A1A1A`），压在深红 `#C62828` 上只有 3.10:1 → **改底的必须同时给 `foregroundColor: AppColors.onErrorFill(context)`**。
**刻意不动的两类**：① 「红当文字/图标/进度条」的标记角色仍走 `colorScheme.error`（成绩页错误文字与 rank 数字与 `LinearProgressIndicator.valueColor`、`network_common.dart` 的 `danger ? scheme.error : scheme.primary` 对话框图标、`selection_result_view.dart` 的「加载失败」文字与 `error_outline` 图标、`account_screen.dart` 的「当前登录」小字）；② `account_screen.dart` 里「当前账号卡」的 2px 整圈 `colorScheme.error` 选中描边（**不是**被稀释的淡框，深色下亮红反而更显眼，改动会降低可见性）。
⚠ **第三类红缺陷：低 alpha 的「淡底 / 淡框」在深色下被整块吞掉（2026-09-16 第六轮 · 用户对「要不要一起收口」回了一个字「修」）**：全应用大量写 `scheme.error / scheme.primary` 的 `.withValues(alpha: 0.04~0.14)` 当**淡底或淡框**（警示面板 / 选中 chip / 服务磁贴的图标底板 / 区块底）。浅色下它叠在白底上是一层看得见的粉，**同一个 alpha 叠到深色卡片 `#1A1A1A` 上就被整块吞掉** —— 实测 `#EE4C50 @ 6%` 混成 `#201A1A`，对卡片只有 **1.065:1**（肉眼与卡片底无异，警示面板等于不存在）；`#F2555A @ 10%` 是 **1.12:1**。原因是**深底会吞淡色**：同样的 6% 叠在白底上 ΔL≈0.10（约 30 倍）。**唯一入口 = `AppColors.tint(context, accent, lightAlpha)` / `AppColors.tintBorder(context, accent, lightAlpha)`**（`lib/design/app_theme.dart`）：`lightAlpha` 必须传**调用方原来在浅色下用的那个 alpha（原样，浅色逐像素冻结）**，深色侧自动换 `AppLadder.darkTintAlpha` / `darkBorderAlpha`。换算 = 淡底 `lightAlpha × 3.5` 夹 `[0.14, darkSoftAlpha]`、淡框 `× 1.2` 夹 `[0.30, 0.60]`。
- **`AppLadder.darkSoftAlpha = 0.22` 是深色「淡底」的全局封顶，也就是 `AppColors.statusFill` 的深色档** —— 两者必须是同一个值，否则会出现「浅色 8% 的块在深色下比浅色 12% 的块更浓」的倒挂。因此 0.07 / 0.08 / 0.09 / 0.10 / 0.12 / 0.14 在深色下**全都落在 0.22**（深色下并档是有意为之）。实测：淡底叠卡片 1.065:1 → **1.31:1**，压在上面的正文（`#EBEBEB`）仍有 **10.3:1**。
- **淡框下限取 0.30** 是为了保住「框比底显眼」这个关系：有一批面板是「淡底 5% + 淡框 16%」，深色下底已抬到 21%+，框若还停在 16% 就会被自己的底吞掉（浅色下框是底的 3.2 倍浓）。
- `lib/design/app_card.dart` 的 `appCardAccentSoft(context)`（服务磁贴 / 仪表盘图标底板）与 `FeatureColors.cardAccentSoft` 也已跟主题走（深色 = `darkSoftAlpha`）；**`const kAppCardAccentSoft` 是编译期常量、恒等于浅色档，有 context 时别用它**。Fluent 层 `FluentPalette.accentSubtle` 的深色档同步 0.12 → **0.20**（保住与 `accentSubtleStrong` 的 0.24 的层次）。
- 本轮覆盖：`withValues(alpha: < 0.15)` 全清（约 100 处，跨 ~55 个文件）+ 7 处遗留 API `withAlpha(20/26/28/40/51)`（写成 `N / 255` 保持浅色逐位相同）。**仍未收口 = alpha ≥ 0.15 的淡底/淡框**（0.18 / 0.2 / 0.3 / 0.5 的描边与滑块轨道等；只挑了「与已抬高的淡底配对、否则框会消失」的少数几处），要动得单独评估。
- **刻意不动**：`hoverColor:`（桌面 hover 提示，有意极轻）、`Colors.*` 字面量（阴影 / 遮罩 / 水印）、`lib/design/fluent/**` 里 `Colors.white.withValues(...)` 的深色分支、以及各文件里 alpha ≥ 0.15 的片段。
- 守卫 = `test/theme_dark_test.dart` 组⑦：换算表（含封顶/下限/单调不倒挂）、浅色逐像素冻结、深色被抬 alpha、**不变式（深色淡底叠卡片必须 ≥1.15:1 且压得住正文，并反向断言旧写法 <1.15）**、共享淡底 token 跟主题、两条源码守卫（8 个警示面板已收口 / `lib/features` 与 `lib/shared` 下不许再有 `error.withValues(alpha: 0.0…`）。对照图 `design_preview/dark_soft_tint.png`（浅色 / 深色改前 / 深色现在 三列 × 警示面板 / 区块底 / 选中 chip / 磁贴图标底板，带实时对比度读数）。
⚠ **第四类缺陷：中性淡描边被 `withValues` 放大成亮白线（2026-09-17 第七轮 · 用户原话「深色模式桌面端左侧导航栏底部固定项最顶部的分割线太亮」）**：`scheme.outlineVariant` 在**浅色**是不透明暖灰 `#D8C2C0`，在**深色**是 `0x1AFFFFFF`（**10% 白、自带 alpha**）。而 `Color.withValues(alpha: x)` 是**替换** alpha **不是相乘** → 代码里那套「浅色下把 outlineVariant 稀释到 0.6」的写法在深色下把 10% 抬成 **60% 白**（`0x99FFFFFF`），叠在侧栏 `#1A1A1A` 上混成 **`#A3A3A3`**（窗口截图逐行扫描实测：y=749 `#5f5f5f` / y=750 `#a3a3a3`，1px 逻辑线在 150% 缩放下跨两个物理像素）—— 对卡片底 **6.98:1**，一根刺眼白线；浅色下同一根线只有 **1.36:1**，所以这个 bug **只出现在深色侧**。**唯一入口 = `AppColors.hairline(context, lightAlpha)`**（`lib/design/app_theme.dart`）：`lightAlpha` = 调用方原来在浅色下用的那个 alpha（原样透传，**浅色逐像素冻结**），深色侧把同一稀释比例搬到 10% 白这个新基准上（`0.6 → 10%`、`0.5 → 8.5%`、`0.7 → 11.7%`、`0.9 → 15%`；基准常量 `_hairlineLightReference = 0.6` = 全应用最常用档，也正是 `app_card.dart` 深色描边的取值）。全库共 **31 处 / 20 个文件**这种裸写法，已全部收口（`lib/design/app_card.dart:50` 那处本来就有 `brightness == dark` 特判，**保持不动**）。**别再写 `scheme.outlineVariant.withValues(alpha: …)`**；实心 / 不透明描边走 `AppColors.stroke`，带色的淡描边走 `AppColors.tintBorder`。守卫 = `test/theme_dark_test.dart` 组⑧（浅色逐值冻结 / 深色 10% 基准 / **反向断言旧写法 >4:1 且新档 <1.5:1** / 侧栏 `Divider.color` 契约 / 源码守卫 `lib/features` + `lib/shared` 下不许再有裸稀释）。**唯一出处（四条链路，别处一律引用，不许在页面里再拼一套）**：

| 层 | 文件 | 内容 |
|---|---|---|
| 底阶常量 | `lib/design/app_ladder.dart` | `AppLadder.light*` / `AppLadder.dark*`（唯一色值来源） |
| 主题装配 | `lib/design/app_theme.dart` | `appLightScheme` / `appDarkScheme` / `appLightTheme` / `appDarkTheme` / `kBrandRed` / `kBrandRedDark` + **`AppColors`**（页面语义色入口）+ `export 'app_ladder.dart'`（页面只 import 这一支即可） |
| 卡片 | `lib/design/app_card.dart` | `appCardColorOf(scheme)` / `appCardColor(context)` / `kAppCardColorDark` = `AppLadder.darkCard`；`appCardBorderSide` 深色下取 `outlineVariant` 原值（不再 ×0.6）；`appCardTheme` / `appCard` 都已按亮度取色 |
| 功能强调色 | `lib/design/feature_palette.dart` | `cardAccentDark = #F2555A`、`featureTone(Color)`、`class FeatureColors` + 顶层 `fp(context)` |

- **深色 A 逐值（用户批准的权威取值，改值必须先改预览并重新请用户过目）**：`surface` / `surfaceContainerLowest` = `#121212`、`surfaceContainerLow` = `#1A1A1A`（= 卡片色 = 顶栏色）、`surfaceContainer` = `#1E1E1E`、`surfaceContainerHigh` = `#242424`、`surfaceContainerHighest` = `#2C2C2C`、`surfaceTint` = `#121212`（中性不着色）、`onSurface` = `#EBEBEB`、`onSurfaceVariant` = `#A0A0A0`、`outline` = `rgba(255,255,255,.20)`、`outlineVariant` = `rgba(255,255,255,.10)`、`onPrimary` = `#1A1A1A`。**深色语义：Lowest 最暗 → Highest 最亮，与浅色相反**。浅色侧**逐值保持改动前原样**，一个色值都不许动。
- **功能强调色深色下统一提亮（不是逐个手调）**：`featureTone(Color base)` —— `base` 的 HSL 明度 ≥ `featureToneFloor`(0.62) 时**原样返回**，否则只把明度设成 0.62、饱和 ×0.92（上限 1）、**色相不动**。47 个 `FeaturePalette` 静态常量全部保留（供 `const` 场景 / 桌面小组件后台 isolate）；实例色表另起名 **`FeatureColors`**（类里不能同时有 `static const curriculum` 和 `get curriculum`），页面侧统一写 **`fp(context).schedule`**。唯一例外 = `cardAccent`：深色取 `FeaturePalette.cardAccentDark`（`#F2555A`）而**不是** `featureTone(cardAccent)` 的 `#D96368` —— 预览里主题强调色是单独定死的一档。
- **`AppColors`（页面侧语义色，别再写裸色）**：`isDark(context)` / `tone(context, light)` / `card` / `page` / `fillSoft`(#FAFAFA|#1A1A1A) / `fill`(#F5F5F5|#1E1E1E) / `fillStrong`(#F0F0F0|#242424) / `fillStronger`(#EBEBEB|#2C2C2C) / `stroke` / `textBase` / `textMuted` / `success`/`caution`/`critical`/`info` / `statusFill(context, accent)`（深色 22% / 浅色 12%）/ `successFill`/`cautionFill`/`criticalFill`/`infoFill`。对照表式注释在文件顶部。
- **Fluent 层**：`lib/design/fluent/fluent_tokens.dart` 新增 `class FluentPalette` + 顶层简写 `fluent(context)`（`FluentColors` 的浅色静态常量全部原样保留）。深色 accent 用 **`#F2555A`**（同 `cardAccentDark`），**不是** Fluent 规范的蓝 `#60cdff`（§16「单色强调一律改主题红」优先）。深色底表：`bgBase` `#121212` / `bgSecondary` `#1A1A1A` / `bgTertiary` `#1E1E1E` / `bgQuaternary` `#242424` / `cardDefault` `#1A1A1A` / `layerDefault` `#1E1E1E` / 描边 `0x1AFFFFFF`·`0x33FFFFFF` / 分隔线 `0x14FFFFFF` / 文字 `#F2F2F2`·`#B0B0B0`·`#8A8A8A`·`#5E5E5E`；`success`/`cautionDeep`/`critical` 走 `featureTone()` 保持全应用同一提亮口径。
- **偏好存储（照 §3「全局偏好入口」模板）**：`lib/features/settings/data/theme_prefs.dart` —— `themePrefsBoxName = 'themePrefs'` / key `themeMode`（存 `ThemeMode.name`）+ `class ThemeModeStore extends ChangeNotifier`（`ensureLoaded()` 幂等 `_loading ??= _load()`、`save()` 尽力而为不抛）+ `themeModeStoreProvider`。**设置页「外观」节 = 唯一入口**（`SettingsSection.appearance`，排在 `campus` 之前，`_AppearanceCard`，三档 `Key('themeModeOption-<name>')`）。
- **首帧不许白闪**：`lib/main.dart` 的 `main()` 已改 `async`，在 `runApp` 之前 `await HiveInitializer.init(); await themeModeStore.ensureLoaded();`，再 `runApp(ProviderScope(overrides: [themeModeStoreProvider.overrideWith((ref) => themeModeStore)], …))`（`overrideWith` 而非 `overrideWithValue` —— 后者对 `ChangeNotifierProvider` 不存在）。`SmarterJxUFE` 已由 `StatelessWidget` 改 `ConsumerWidget`，`MaterialApp` 接 `theme: appLightTheme` / `darkTheme: appDarkTheme` / `themeMode: ref.watch(themeModeStoreProvider).mode`。
  - ⚠ `lib/core/storage/hive_initializer.dart` 的 `init()` 已加幂等（`static Future<void>? _init; static Future<void> init() => _init ??= _run();`）：`main()` 预载会调一次、`SplashScreen._checkAuth()` 首行（`lib/features/splash/presentation/splash_screen.dart:34`）还会再调一次，而 `Hive.registerAdapter` 二次注册会抛。**新加任何提前 `HiveInitializer.init()` 的调用点都靠这个标志兜底，别再自己写一套。**
- **`@pragma('vm:entry-point') Future<void> homeWidgetBackgroundMain()` 必须留在 `lib/main.dart` 这个 root library**（DartEntrypoint 不指定 `libraryUri` 时只在根库查找；搬去子库 → 后台刷新静默失败）。
- **守卫 = `test/theme_dark_test.dart`**（浅色逐值不变 / 深色 A 逐值 / `featureTone` 与预览 JS 逐值同值（37 组期望值硬编码）+ 色相不动 + 「深色下每个功能色在卡片底 ≥3:1 且原本不足 4.5:1 的必须被抬高」不变式 / 偏好存储与 `themeModeFromName` 容错 / 设置页三档默认跟随系统与写库 / `MaterialApp` 真的跟着切）。**改任何色值 = 改用户看过的那份预览，必须重新请用户过目并同步该测试的期望表**。
- **仍然刻意保留的裸色**：二维码的白色底板（`QrImageView` 白底，深色下扫不出来）、`lib/design/JxufeTheme.dart` 常量类本身（遗留、仅保留定义，页面侧已全部改用 `scheme.*` / `AppColors.*`）。其余 `Colors.white|black|grey` 一律不得新增。

### 22.1 课表与「我的」页的深色适配（2026-09-17 · 用户原话「课表的颜色没有做深色适配；个人主页卡片的顶部颜色没有适配」）

- **课表课程色 = `lib/features/ims/schedule/presentation/schedule_tone.dart` 的 `abstract final class ScheduleTone`（唯一实现，竖版 / 横版共用）**：原来 `schedule_grid_view.dart` 与 `schedule_horizontal_view.dart` **各抄了一份硬编码浅色 pastel 色表**（`_coursePalette` / `_textPalette`），深色下仍是浅底 + 深字。现在两处都删表，改用 `ScheduleTone.fill(context, seed)` / `ScheduleTone.text(context, seed)`（`seed` = `entry.courseCode.hashCode.abs()`，内部取模，负数也合法）。
  - **浅色逐值冻结**：`fill` 浅色返回 `courseFills[i]`（原 pastel 12 色）、`text` 走 `AppColors.tone` → 浅色原样返回 —— 浅色侧一个色值都不许动（同 §22 总口径）。
  - **深色 = 同色相实底 + 柔光灰文字**：底 = `Color.alphaBlend(featureTone(courseTexts[i]).withValues(alpha: ScheduleTone.darkFillAlpha), AppColors.card(context))`（`darkTint`，**实色**：半透明会随下层——页面底 / 卡片底 / 空格子——变观感，12 色就不恒定了）。
    - ⚠ **`darkFillAlpha` 现在 = `0.28`（2026-09-17 第四轮，用户：「课表深色模式下，课程卡片颜色较暗，稍微提亮一点」）**：初版 `0.20` 叠出来最亮才 `#234346`、与卡片底 `#1A1A1A` 只差 1.26:1，整片发闷；`0.28` 后 12 色 = `#265458`(青，最亮) ~ `#37304E`(深紫，最暗)，与卡片底分离度 **1.40:1**，亮度整体 +35%~56%。
    - **上限就是 0.28，别再往上加**：`0.30` 课程名 `#C8C8C8` 只剩 4.76:1、`0.32` 掉到 **4.49:1（破 AA）**、`0.36` 4.02、`0.40` 3.60；次级行（α190 教师/教室 5.78→4.76、α140 周次 3.91→3.34）也会跟着掉。想更亮必须**同时**抬课程名（如 `#D8D8D8`），那是另一档改动。
    - 守卫 = `test/schedule_dark_tone_test.dart`「课格底不许太暗：第四轮…」：断言 `darkFillAlpha == 0.28`（且在 `(0.20, 0.30]`）、12 色亮度 ≥ 0.032、与卡片底 ≥ 1.35:1、`darkTint` 默认档 == `fill`（补课格同源）；对照图 = `design_preview/schedule_fill_ladder.png`（12 色 × 4 档）+ `schedule_fill_grid.png`（浅色 / 深色真实网格）。
  - 配套：补课格底板 `ScheduleTone.tintFill(context, ScheduleTone.extraFill, fp(context).makeUpClass)`（浅色 = 原 `#E8F5E9`）；表头红 / 周末蓝灰走 `ScheduleTone.header(context, …)`（常量 `headerRed` = 原 `#C62828`、`weekendHeader` = 原 `Colors.blueGrey.shade700` 的 `#455A64`）—— 深色下 `#455A64` 会糊在深底上，必须提亮。**表头上的白字 / `white24` 分隔线保留不动**（画在固定彩色底上，§22 对照表最后两行）。
  - 守卫 = `test/schedule_dark_tone_test.dart`（9 例：浅色逐值零漂移 + 负数取模、深色底「不透明且比浅色 pastel 暗」、文字明度 ≥ 0.62、补课格与表头换档、**渲染层断言**（深色 pump 真 `ScheduleGridView` 后课程格与「周一/周六」表头的 `BoxDecoration.color` 必须等于 `ScheduleTone.*`；浅色同款断言原 pastel）、源码守卫（两个视图不得再出现 `_coursePalette`/`_textPalette`/`0xFFE3F2FD`，色表只在 `schedule_tone.dart`））。
- **「我的」页卡头条带**（`lib/features/ims/student_info/presentation/student_info_screen.dart` 的 `_card(...)`）：原为**写死的粉底 `#EFA0A0` + `Colors.black` 字**，深色下粉带刺眼、黑字读不清。现在浅色**逐值不变**（仍是 `#EFA0A0` + 黑字），深色改用 `AppColors.statusFill(context, scheme.primary)`（主题红 22%）+ `AppColors.textBase(context)`。改这个卡片头时别退回裸色。
- ⚠ 扫描口径：本仓已无「深色未适配」的其他明显点（2026-09-17 全 `lib/**/*.dart` 扫 `Color.fromARGB` / `Colors.black` / `Colors.grey.shadeN` / `Colors.blueGrey.shadeN` 共 43 处，其余均为**合法裸色**：阴影 `black.withValues(alpha:)`、固定彩底上的白字、全屏看图/阅读器的黑底、Fluent tokens 内部）。脚本 `D:\Temp\_scan_raw_colors_all.py`（可复用）。

## 23. 云同步（用图书馆「我的订阅」当云端存储面 · 2026-09-17 立）

**用户目标**：在没有云服务器的前提下实现「设置同步」。存储面 = 江财图书馆 `https://findjxufe.libsp.cn/#/personalCenter` 的**订阅词**（统一认证登录后可用）。经 `/grill-me` 逐问审问 15 问后冻结，**完整方案 + 全部实测数据 = `reverse_engineering/图书馆订阅词云同步方案.md`**（改协议前必读；本节只记「必须知道的口径」）。

**用户裁定（15 问，别推翻）**：① 正式功能，所有装了 App 的同学都能同步；② 明示 + 主动 opt-in + 一键清除；③ 范围 = 纯偏好 + 分数估计（不含图片）；④ 汉字编码（CJK 基本区 U+4E00–U+9FFF，**不用 base64**，也不扩 Ext-A/谚文/emoji）+ 写回校验 + 版本号；⑤ 复用 App 现有 CAS 链路（service = 超星网关）；⑥ 快照 + 双代 + 对账式自动上传 + 显式恢复（恢复前留档）；⑦ **备忘录文字不进**（自由文本不可明示）、**电费绑定进**（含宿舍房间号 → 明示文案必须逐项列出）；⑧ 前缀 `勿删！智慧er江财云同步信息：`；⑨ 双代 ping-pong（写满新代并校验通过才删旧代）；⑩ 三组 = 最新版×2 + 上一版×1；⑪ 防抖 60s + 手动 + 回前台对账 + 失败退化为「上一版仍可用」；⑫ 「关闭同步」只停上传、不删云端，「清除云端数据」按结构全删 + 对账；⑬ 设置页新增 `SettingsSection.cloudSync` 一节；⑭ 超限时先抽 uuid 再走固定降级链。

**实测事实（真账号跑出来的，不是推断）**：
- **登录链零密码**：`TGC`（`auth.hive` 的 `TGC|<账号>`，值 111 字符 `TGT-…`）→ CAS `service=https://unified-auth.chaoxing.com/login_auth/cas/jxufe/index` → 票据 `ST-…` → 网关 `GET /login_auth/cas/jxufe/login?data&time&enc` → `{"status":true}` → 回跳 `…/find/sso/login/jxufe/0?pageType=0&data&time&enc` → **`findjxufe.libsp.cn` 下发 `SESSION`（Spring Session，不是 JSESSIONID）+ `_passport_login` + `route`**。
- **图书馆域名不在学校 CAS 白名单**（5 个变体全返回「未认证授权的服务」；对照组 5 个已知可用 service 全部拿到登录页）→ service 只能写超星网关那个。
- **单条上限 = 100 字符**（写 303 汉字读回恰好 100 字 / 294 字节；101 字只存下 100 字）→ **超长是静默截断**（`add` 仍返回 `success:true`）→ **必须逐片读回校验**。
- **服务端零规范化、且不去重**：78 字含全角 `！`/`：` 与跨区采样汉字逐字节往返一致；同一条写两次列表里就有两条 → 幂等自己保证、清理只能按结构全删。
- **条数上限 ≥ 120**（2026-09-17 实测：连续写 120 条全部成功、服务端一条不拒，写到 120 主动停；更早一轮验过 70 条。`/find/user/userLimit` 返回的是荐购/借阅口径，**不是**订阅词配额）→ 预算 `kLibspDefaultWordBudget = 90`（留 30 条给**用户自己的**订阅词，探针账号起始是 0 条而真实用户可能有）。
- 载荷实况：本机 **10 门真实课程 + 5 个偏好箱 + 1 条综测** → 信封 **1020 B** → **8 片/份**，一次上传 1.0 s；三份 = 24 条词 = 实测上限的 20%。

**协议（冻结）**：单条词恒 100 字 = 前缀 15 + ASCII 数字头 5（槽位 1 + 序号 2 + 总片 2）+ 校验 2（CRC-32 低 24 位）+ 载荷 78 字；每片 139 字节 `[4B 大端长度][gzip]`；字母表 20,992 字 = 14.357 bit/字 = 1.795 B/字。**识别只看结构、不看前缀文本**（从第 1 字起找「5 位 ASCII 数字 + 其后 80 字全在字母表内」），所以服务端若把全角标点归一也不影响识别与清除；**读回校验只覆盖数字头 + 校验 + 载荷，不覆盖前缀**（否则误报数据损坏）。

**唯一实现（`lib/features/library_sync/`，别在别处再拼一套）**：

| 文件 | 职责 |
|---|---|
| `domain/libsp_chunk.dart` | 布局常量与不变式（**守卫测试守住 `20992^78 ≥ 256^139`**） |
| `data/libsp_codec.dart` | 字节 ⇄ 订阅词（BigInt 20,992 进制 + CRC-32）+ 分片/重组 + 信封 |
| `data/libsp_payload.dart` | 白名单（`kLibspSyncedPrefBoxes` / `kLibspExcludedBoxes`）+ 剥 uuid/createdAt/memo + gzip + **固定降级链**；⚠ **课程顺序 = 本机原序**（「新在前」只用于决定装不下时先丢谁） |
| `domain/libsp_remote.dart` | 端口：`LibspRemote`（网络）/ `LibspLocalStore`（本机）→ 逻辑可单测 |
| `data/libsp_sync_service.dart` | 状态机：三组轮转 / 保护最后一份完整快照 / 自愈 / 清理 / 恢复 |
| `data/libsp_local_store.dart` | Hive 实现（**写入白名单守卫**：云端塞 `imsAuth` 之类一律不写） |
| `data/datasources/libsp_auth_remote_datasource.dart` | 换证链（页内参数解析要**回代 var 标识符**，否则服务端回「参数错误」） |
| `data/datasources/libsp_subscribe_remote_datasource.dart` | `list/add/del`（401/跳登录页 = 会话失效） |
| `data/libsp_remote_adapter.dart` | 会话缓存 + **失效才重换一次票**（§12.2 口径） |
| `data/libsp_sync_prefs.dart` | opt-in 状态 + `LibspSyncGate`（60s 窗口 + 每日 20 次 + 跨天归零） |
| `data/libsp_sync_controller.dart` | 编排（状态/文案；不弹窗、不管协议）+ **60s 防抖 `Timer`**（`markDirty()` 顺延窗口，`dispose()` 取消悬挂定时器） |
| `data/libsp_dirty_watch.dart` | `LibspDirtyWatcher`：**监听 Hive box 本身**（6 个偏好箱 + 账号级 `score_estimate_<账号>`）→ `markDirty()`；`pauseWhile()` 在恢复期间抑制自写事件 |
| `data/providers/libsp_providers.dart` | 唯一装配点 |
| `presentation/libsp_sync_card.dart` | 设置页「云同步」节 + 明示清单 + 两步确认恢复/清除 |
| `lib/core/storage/box_reload_watcher.dart` | `BoxReloadWatcher` mixin：偏好 store 订阅自己的 box → **外部写入（云同步恢复）也反映到界面**（见下条 bug） |
| `lib/core/storage/local_data_revision.dart` | `localDataRevisionProvider`：恢复后 bump 一次 → **把数据读进 State 的页面**（分数估计 / 综测）据此重读 |

**不变式（守卫测试盯着，破坏即红）**：任意时刻云端至少有一份完整快照；稳态 = [最新版, 最新版, 上一版]；**绝不碰用户的订阅词**；部分缺片自愈、整组缺失不自愈；恢复前必须留档且留档失败就中止。

- **自动触发有三条腿**（全部过 `LibspSyncGate`：未 opt-in / 未登录 / 60s 窗口 / 每日 20 次直接返回）：
  1. **首帧 + 回前台对账** = `home_widget_sync_scope.dart` 的 `_sync()`（与截止提醒同一时机）；
  2. **本机改动 → 60s 防抖 → 自动上传** = `LibspDirtyWatcher`（装配在 `libspSyncControllerProvider`，`ref.onDispose` 释放）。**为什么监听 box 而不是逐个 store 埋点**：偏好在 6 个箱、分数估计在账号级箱，逐个埋点会**漏掉以后新增的写入路径**，还会让别的 feature 反向依赖同步模块；
  3. 设置页手动「立即同步」。
- **真机端到端 = `tool/libsp_smoke.dart`**（`dart run tool\libsp_smoke.dart`，纯 Dart 不拉 Flutter）：真账号换证链 → 读**磁盘上的真 box**（拷副本后只读）→ 真实 codec/payload/service 上传 → 读回逐字段比对 → 恢复 → 幂等 → 清除。**2026-09-17 实测 25/25 通过**（10 门真实课程全字段往返一致、稳态 `[最新×2, 上一版×1]`、清除残留 0）。改协议后先跑它。
- **App 内也已验过一遍**（`flutter run` + `D:\Temp\vmprobe\sjx_eval.py` 驱动真实容器）：手动同步 `msg=已同步到图书馆`（真实 `AuthRepository` + `Adapter` + `HiveLibspLocalStore`）；**防抖链**：清空云端 → 回写一个白名单偏好箱 → `dirty=true` → 70 s 后自动上传、云端又有 16 条 ✓。探针三个坑：① 目标库必须 import material + flutter_riverpod（包装表达式要用 `WidgetsBinding`/`Element`/`ProviderScope`；`libsp_dirty_watch.dart` 只有 foundation 会报 `Undefined name 'WidgetsBinding'`）；② 要同时用 `Hive` 就选 `lib/features/settings/data/theme_prefs.dart`（material + riverpod + hive 三件套齐）；③ 表达式从文件读入必须 `.Trim()`（尾随换行 → `Can't find ')' to match '('`）。
- ⚠ **「从云端恢复」后设置不变 —— 根因与修法（2026-09-17 用户实测报告：「目前从云端同步似乎设置不会变」）**：偏好 store 全是「值读一次就存内存」（`ensureLoaded()` 里 `_loading ??= _load()` 幂等缓存，`_load()` 之后**再没人读盘**），而恢复走的是 `HiveLibspLocalStore.writePrefs` → `box.put`，**只改了盘**：没人通知内存 → 恢复报成功、界面一动不动（重启 App 才看得到）。**修法 = 每个偏好 store 订阅自己的 box**：混入 `lib/core/storage/box_reload_watcher.dart` 的 `BoxReloadWatcher`，在 `_load()` 里 `bindBoxReload(box, _readFromBox)`，并把原来的首载读取逻辑抽成 `_readFromBox(Box<String>)`（**首载与外部写入共用同一段，判等相等就不通知** → 自己 `save()` 写盘走回来时静默、不形成回环；`dispose()` 之后到达的事件直接丢弃，否则 `notifyListeners()` 抛「A ChangeNotifier was used after being disposed」）。覆盖 5 个 store：外观 `lib/features/settings/data/theme_prefs.dart`、校区 `lib/features/campus_address/data/my_campus_prefs.dart`、主页布局 `lib/features/home/data/home_layout_prefs.dart`、校历 `lib/features/school_calendar/data/calendar_prefs.dart`、入馆教育 `lib/features/library_edu/data/tsgxs_prefs.dart`（`electricityBinding` 不在其列：它是 `FutureProvider<Box<String>>`，页面每次读 box 本体）。**证据链 = `test/libsp_restore_live_test.dart`**：直接调**真实恢复写入路径** `HiveLibspLocalStore.writePrefs` → 修前 6 例全红（`Expected: ThemeMode.dark / Actual: ThemeMode.system`、校区 `null`、布局 `HomeLayout.grid`、模式 `TsgxsAnswerMode.normal`、校历 JSON 不相等），修后 12/12 绿。
- **另加一条腿：把数据读进 State 的页面** —— 分数估计 / 综测是「`_init()` 读进 `_courses` / `_manual`」的，box 变了它们不会自己知道（而且 `score_estimate_screen.dart` 没有 `PageAutoRefresher`）。做法：`LibspSyncController` 加 `onRestored` 回调（装配在 `libspSyncControllerProvider` → `ref.read(localDataRevisionProvider.notifier).bump()`），恢复成功后**只在真恢复成功那一条路**调一次；两个页面在 `build` 里 `ref.listen(localDataRevisionProvider, (_, _) => unawaited(_reload()))`（综测走 `_reloadManual()`，只重读手册、不触发体测自动源）。**别在页面里各写一套「恢复后刷新」**：信号只有 `lib/core/storage/local_data_revision.dart` 一个。
- **二轮真机验收 = 用户场景原样复现（2026-09-17）**：`flutter run -d windows` + VM 探针，**跨两个库作用域操作同一个容器**（单个库作用域只含它直接 import 的名字 → `libsp_sync_card.dart` 取控制器、`theme_prefs.dart` 读写外观与 box）：① `syncNow()` → `status=ok / msg=已同步到图书馆`（云端 24 条 = 3 代 × 8 片）；② 本地 `themeModeStoreProvider.save(light)` → 探针 `mode=light box=light` 且**界面真的变浅**（截图像素 `(1000,650)=240,240,240`；注意本机「系统」当时是深色，翻到 `light` 才看得出差别）；③ `restoreFromCloud()` → `status=ok / msg=已从云端恢复`、`mode=system box=system`、**界面回到深色**（`36,36,36`）→ 用户报的「设置不会变」彻底消失；④ `localDataRevisionProvider` 读回 **2**（两次恢复各 bump 一次）= 页面重读信号确实在跑。截图 `D:\Temp\libsp_flip_light.png` / `D:\Temp\libsp_restore_back.png`（**比较用像素点，别信 `view_image` 的散文描述** —— 它会把同一张图读成「深色主界面 + 白色弹窗」）。
- **守卫 = `test/libsp_codec_test.dart`（20）/ `libsp_payload_test.dart`（18）/ `libsp_sync_test.dart`（15）/ `libsp_store_test.dart`（7）/ `libsp_auth_parse_test.dart`（14）/ `libsp_debounce_test.dart`（10）/ **`libsp_restore_live_test.dart`（12）**，共 **84 例**；`flutter test` 全量 **1300 例全绿**。
  - ⚠ **防抖/监听这组必须用真时钟的 `test()` + 本仓既有 Hive 口径**（`setUpAll` 里一个临时目录 + 每例 `Hive.deleteFromDisk()`，见 `libsp_store_test.dart`）：① `testWidgets` 的假异步区里**真实 Hive 文件 I/O 的回调永远等不到** → 整轮测试挂死（首版踩到）；② 每例 `Hive.init(新目录)` + `Hive.close()` 会把上一个 box 留在 Hive 缓存里 → 第二条测试起就串味（同样挂死）。生产 60s 的约定用「常量 + 默认参数」断言，不真等 60 秒。
  - ⚠ **超载样本必须用随机汉字噪声**：120 门「除课名外完全一样」的课，gzip 之后只有几百字节 → 降级链根本不被触发，测试会假绿（实测踩到）。真实数据压缩率约 2.7:1。
  - ⚠ 写测试时别用 `dart test`（本仓测试依赖 `flutter_test`，`dart test` 报「Could not find package test」）；`flutter test` 前先删 `build\unit_test_assets`，且**别的会话并发跑测试会抢构建目录导致崩在 shader 编译**（`Could not write file to build\unit_test_assets\shaders/ink_sparkle.frag`）。

**侦察脚本（可复用，别删）**：`.scratch/libsp.py`（会话建立模块：`establish()` + `api()` + `items()` + `add()` + `delete()`，**全程只报长度不打印凭据**）、`.scratch/probe23.py`（上限/配额实测范例）。
⚠ **凭据纪律（本轮踩过）**：读 `app_data/auth.hive` 时 `CACHEDPASS|<账号>` 存着**明文 CAS 密码**，`TGC|<账号>` 是会话票 —— 探针一律只打印长度与形态，**任何值都不许进日志/对话**；超星网关的登录响应还会带真名与手机号。

## 24. 材料库「添加材料」向导 + 通用三宫格日期选择器（2026-09-17 立）

- **通用日期选择器 = `lib/shared/widgets/grid_date_picker.dart`**（用户：「制作一个通用的日期选择器，不仅限于材料库功能」）：`showGridDatePicker(context, {initialDate, firstDate, lastDate, title, helpText})` → `Future<DateTime?>`（取消 = null）；弹窗本体 `GridDatePickerDialog` 可单独 pump 单测。**一个弹窗里三块宫格**（年 / 月 / 日；用户 ask 拍板，不是「依次弹三次」）：`gridDatePickerColumnsBreakpoint = 520`（宽屏三列并排、窄屏纵向堆叠），点日期即返回，「今天」仅在区间内可用，越界年/月/日禁用（点了不关闭）。纯函数 `gridDaysInMonth(year, month)`（含 2000/2100 闰年规则）、`gridClampDate(value, first, last)`；Key = `gridDatePickerKey` / `gridDateYearKey(y)` / `gridDateMonthKey(m)` / `gridDateDayKey(d)`。
  - ⚠ **自建 `Dialog` + `SingleChildScrollView` + `Wrap`**，不是 `AlertDialog` + `GridView`（守 §3.1：AlertDialog 恒用 IntrinsicWidth，viewport 组件会 `RenderViewport does not support returning intrinsic dimensions`）。
  - 已接入：材料库 `_pickDate`（盖章日期，区间 = 近 6 年 ~ 今天）。别的页面要用直接 import 这个文件，别再各处 `showDatePicker`。
- **材料库表单口径**：① **竞赛名称与类别 = 固定项**（`_lockedActivity`：目录里点选具体比赛时只读展示，`widget.existing != null || item.other || namePrefill 为空` 才可编辑，要改回上一步重选）；② **竞赛不填组织单位**（`if (spec.needOrg && spec.id != ZcTypeId.contest)`）；③ **级别/档位与奖项/细分 = 一排按钮**（`_choiceGroup` + `_choiceChip`，不再下拉）；④ **保存后停留在活动候选页**：`_ActivityPickPage` 不再 `pop` 自己，改用 `onPicked` 回调开表单（`onPicked: (item) => _openEditor(null, type: type, activity: item)`，`item == null` = 「直接填写」），保存成功清空搜索框以便连续添加。
- 守卫 = `test/grid_date_picker_test.dart`（10 例：闰年天数 / 夹取 / 三块宫格渲染 / 宽窄布局 / 选年-月-日回传 / 2 月收敛 / 越界禁用 / 今天 / 取消）+ `test/materials_wizard_test.dart`（4 例：固定项 + 无组织单位 + 按钮档位 / 三宫格日期 + 保存后仍在候选页 + 连续添加 / 自定义竞赛可编辑 / 非竞赛保留组织单位）。
  - ⚠ **测试坑（本仓通用）**：widget 测试里**不要让 App 写真 Hive** —— 真实文件写入的完成回调会落到**下一个用例**的假异步区，后续用例永远 `did not complete`（`tester.runAsync` 也救不了，实测两轮）。材料库测试因此用 `_MemoryStore extends ZcStore`（只覆写 `loadMaterials/saveMaterials/deleteMaterial`，保存在内存 list）。
  - ⚠ 另一个坑：**失败的用例会让后面用例不完成**（先修失败再看「挂起」，别把挂起当独立问题查）。
- **通用日期选择器三处追加口径（2026-09-17）**：① `materials_screen.dart` 的 `_openEditor` 里 `await ref.read(calendarViewerProvider.future)` 取 `enrollYear` → `firstDate = DateTime(enrollYear ?? now.year - 6, 1, 1)`（用户「学科竞赛日期选择器的年份范围应该最早是入学年份」；`_MaterialEditDialog` 的 `initialYear` 字段已改名 `final DateTime firstDate`）；② 日期块**顶部显示周一到周日**并按周对齐 —— `gridDateMonthOffset(year, month) => DateTime(year, month, 1).weekday - DateTime.monday` 前导空格 + `gridDateDayCellWidth/Height = 32`/`gridDateDayCellGap = 2` + `_dayCalendar(context, maxDay)`（7 列整行 `Row`，每格 `Padding(all: gap/2)`），**表头 SizedBox 宽度必须 = `gridDateDayCellWidth + gridDateDayCellGap`（34）**—— 首版写 `+ gap*2`(36) 导致第 7 列错位 13px；③ 日期块不再是 `Wrap`（`_section(..., wrap: false)`）。守卫 = `test/grid_date_picker_test.dart` 的「日期块：周一到周日表头 + 日期对齐」组（表头 7 格、1 号落对列、切月重排）。

## 25. 浮层定位（RuleTip）（2026-09-17 立）

用户原话：「综测页的悬浮提示位置不对，我希望显示在悬浮按钮周围，并且不能超出屏幕外」。
唯一实现 = `lib/features/zongce/presentation/widgets/rule_tip.dart`（`RuleTip`）：

- 定位用 **`OverlayEntry` → `Positioned.fill` → `CustomSingleChildLayout` + `_TipPositionDelegate`**：
  只有 delegate 的 `getPositionForChild(size, child)` 同时拿得到屏幕尺寸与**卡片真实尺寸**
  （旧实现按 `maxHeight`（≤400）估高 → 翻到上方时卡片离按钮很远）。规则：下方放得下
  （`anchor.bottom + gap + child.height ≤ size.height - margin`）→ 紧贴下沿；否则若
  `anchor.top - gap - child.height ≥ margin` → 贴上沿；两者都放不下 → 夹在屏幕内。
  横向 `anchor.center.dx - child.width/2` 夹在 `[margin, size.width - margin - child.width]`。
  `gap = 6`、`margin = 8`；卡片最大宽 420 / 最大高 460。卡片有 `Key`：`ruleTipCardKey`。
- **⚠ 两条硬约束（都实测踩到）**：
  1. **不能在 delegate 的布局回调里 `localToGlobal`** —— 布局期读祖先 `RenderBox.size` 被禁，
     报 `RenderBox.size accessed beyond the scope of resize, layout, or permitted parent access`
     （栈里可见 `RenderFractionalTranslation.applyPaintTransform` → `getTransformTo`），卡片会被
     扔到屏幕外。按钮矩形必须**在 build 时算好**传给 delegate。
  2. **`ScrollPosition` 的通知在新偏移应用之前同步发出** → 收到通知立刻重建，`localToGlobal`
     仍是旧位置，卡片原地不动。必须 `WidgetsBinding.instance.addPostFrameCallback` **帧后再
     `markNeedsBuild()`**（`_repositionScheduled` 去重）。滚动跟随 = `Scrollable.maybeOf(context)`
     的 position listener + 帧后重排；窗口变化 = `WidgetsBindingObserver.didChangeMetrics` 走同一路径。
- **不许遮盖悬停处（2026-09-18 追加 · 用户原话「综测的悬浮显示不能遮盖悬停的地方」）**：
  卡片高度上限改为 **较大一侧的实际可用空间**（`availBelow = size.height - margin - (anchor.bottom + gap)`、
  `availAbove = (anchor.top - gap) - margin`，取 `max` 后 clamp 到 ≤460）→「放不下就翻面」这条**永远成立**，
  卡片不可能压在按钮上；定位一律按**原始锚点** + `gap`（6 > 安全外扩 `_tipAnchorPadding = 4`，天然留 4px）。
  ⚠ 旧版高度固定 `clamp(120,460)`，矮窗口靠 `(size.height - margin - child.height).clamp(margin, belowTop)`
  兜底 —— 那一夹就把卡片夹到按钮上（实测 760×220 窗口：按钮 `[100,118]`，卡片 `[42,212]` **压住了**）。
- 守卫 = `test/rule_tip_position_test.dart`（**8 例**：下方紧贴 / 贴底翻到上方 / 靠右夹取 /
  矮窗口不越界 / **矮窗口卡片收缩且与按钮不相交** / **中部按钮不压按钮** / 滚动跟随（用 `ScrollPosition.jumpTo`，**不能用 `tester.drag`** —— 浮层卡片在
  列表之上会吃掉拖拽）/ 再点收起）。**测试必须真改窗口尺寸**（`tester.view.physicalSize`），
  只塞一个 `MediaQuery(data: MediaQueryData(size: …))` 不改变 Overlay 的实际大小 → 会得出
  「越界」的假结论。
## 26. 推免成绩 / 竞赛奖励（2026-09-17 加 · 资料库运行时解析）

用户原话（两条，决定整个设计）：
1. 「我希望编写一个新功能，推免成绩 / 自动从资料库里获取加分项 / 具体的加分项参考 app 目前"规章制度"部分里有相关文件」
2. 「新功能：竞赛奖励 / 参考《学科竞赛管理办法》 / 自动资料库里获取竞赛信息，然后时间范围不是按学年，而是手动选择时间范围」

已拍板口径：① **「资料库」= 随包 `assets/rules/`（规章制度）→ 运行时解析**（不把表格抄成静态数据：学校换版后无需改代码）；② 竞赛奖励的时间范围 = **手选起止日期筛选获奖记录并合计奖励**（不是按学年、也不是挑目录版本）；③ 推免加权平均成绩 **自动取数**（离线缓存自算）；④ 入口 = 首页「学习与测评」组两个磁贴（`Icons.flight_takeoff` 推免成绩 / `Icons.military_tech_outlined` 竞赛奖励；目录条目数 21 → **25**，已同步 `test/home_tile_alignment_test.dart`）。

### 26.1 共用解析层（唯一实现，别在 feature 里另写一份）

| 文件 | 作用 |
|---|---|
| `lib/features/rules/data/rule_doc_parse.dart` | md → 分段 `ruleSectionsOf` / 物理化表格 `ruleTableOf` / 文本清洗 `ruleCleanText` / 金额 `ruleAmountInYuan` |
| `lib/features/recommendation/data/bonus_catalog_parser.dart` | r08a 附件五节 → `BonusCatalog` |
| `lib/features/competition_award/data/competition_catalog_parser.dart` | r20/r21 → `CompetitionCatalogEdition` |
| `lib/features/competition_award/data/award_standard_parser.dart` | r01a 第九条 5 张表 → `AwardStandard` |

**三个必须记住的解析口径（都踩过坑）**：
- **词内空格必须删掉**：pdf2md 产物会写 `级 别`、`中国国际大学生创新创 业大赛`、`省优 秀共产党员`；`MdParser.clean` **只把连续空白压成一个空格**，用它匹配表头会**静默取不到列**（实测：专利类整类解析成 0 项）。`ruleCleanText` 的做法 = 两侧都是 CJK/全角/数字的空格直接删，拉丁↔中文的空格保留。
- **合并单元格要补齐**：`<td rowspan="3">特等奖（金奖）</td>` 只在首行有文本，`ruleTableOf` 把锚格文本复制到覆盖的每个槽位；否则Ⅰ类奖励表只能读到第一档等次。
- **按表头文字取列，绝不按下标**：四类竞赛目录的列数各不相同（3/3/5/5），Ⅰ类奖励表有三行表头（`Ⅰ类竞赛` → `奖励对象` → `获奖等级`）——统一「先定位『国赛/省赛』那一行，再按列向上回溯」。

### 26.2 推免成绩（`lib/features/recommendation/`）

- **综合成绩 = 推免加权平均成绩 + 附加分**（办法第十五条）；附加分**每一类别只计一项、不累加**、**总分 10 分封顶**（第十条）。
- 竞赛类分值 = 获奖等级分（金奖 10 / 银奖 7 / 铜奖 4；挑战杯课外学术 特等 10/一等 7/二等 4/三等 2；国家级Ⅱ类 2/1/0.5）× **排名系数**（第 1 名 1.0 → 第 5 名 0.6 → 第 6 名 0.5 → 第 7-10 名 0.3 → 第 11-15 名 0.1 → **第 16 名及以后不加分**）；**2025-01-01 之前**取得的获奖，排名第 6 及以后按满分 ×0.5（注 2，分界日与系数从原文解析，不写死）。
- **推免加权平均成绩的唯一实现 = `lib/features/ims/grades/domain/recommendation_weighted.dart` 的 `recommendationWeightedOf`**（`主干加权×0.7 + 非主干×0.3`，先排除 `kExcludedGradeCourses`）——2026-09-17 从 `grades_screen.dart` 抽出，**成绩页与推免页共用**；课程地位来自 `lib/features/ims/grades/data/providers/curriculum_importance_provider.dart`（也是从成绩页抽出的公开 provider），成绩取 `gePriorGradesProvider`（离线、账号隔离）。**别再写第二份**，否则两个页面会显示不同的数字。
- 加分项存储：账号级 box `recommendationData` key `items`（`lib/features/recommendation/data/recommendation_store.dart`）；条目冗余保存 `optionLabel`/`tierLabel`，资料库改版后旧条目仍能显示（重新计分时提示「资料库里已找不到该项目」而不是静默算 0）。
- 页面在「根据资料库算不出」时**必须给原因**：未填排名（按第 1 名计 + warnings）、未选等次、项目已下架、培养方案未就绪（`importanceAvailable == false` → 整卡替换为提示 + 重试）。

### 26.3 竞赛奖励（`lib/features/competition_award/`）

- 奖励金额来自第九条 5 张表（**表头特征识别**：含「Ⅰ类竞赛」=Ⅰ类表；含「先进集体奖」= 组织奖 → **跳过**；同时含「Ⅱ类竞赛」「Ⅲ类竞赛」= Ⅱ/Ⅲ类表，用前一段文字里的「本科生」区分学生/教师表；含「Ⅳ类」=Ⅳ类表）。
- **Ⅳ类只奖励指导教师（组），不奖励学生** → `studentAmountFor` 返回 **0**（不是 null），页面显示「不奖励学生」。
- **Ⅱ/Ⅲ类「个人或团队只分别奖励金额最高的 1 个竞赛获奖项目，不累计」**（第九条注）→ 按类别取最高，其余标为不累计。
- **第十条**：同一年度同一作品在同一竞赛不同级别获奖取最高；只奖励最高 3 个等次；**设特等奖的赛事**里特等奖对应一等奖、一等奖对应二等奖并依此类推（页面上是 `hasSpecialTier` 开关）；入围奖/晋级奖/参与奖/优秀奖**不计入**。
- 第九条注的两个折减：`AwardAdjustment.international70`（国际项目 ×0.7）、`nonMainTrackAsClassII`（挑战杯非主体赛道按Ⅱ类标准）。
- ⚠ **Ⅰ类赛项组认不出时必须返回 null，绝不回落到「第一组」**（`AwardStandard.groupLabelFor`）：Ⅰ类两组标准不同（创业计划特等奖 3.2 万 vs 创新大赛 4 万，且创业计划三等奖 `/` 不奖励学生），回落会让「挑战杯创业计划三等奖」静默拿到 5000 元 —— 2026-09-17 被 `test/award_rules_parse_test.dart` 抓到并修掉。
- 记录存储：账号级 box `competitionAwardData` key `records`；**手选日期范围只筛记录**（缺日期 / 超范围都明确标原因，不静默丢弃）。
- **未计入的记录分两档表现（用户 2026-09-18 口径：「不计入的项变暗，而不是显示那个什么第九条的提示」）**：`AwardRecordOutcome.suppressed == true`（③ 第十条同年同赛事取最高 / ④ Ⅱ Ⅲ类只奖最高一项不累计 —— 计算里就是 `suppressed` 那个下标集合）→ 页面**只把该行左侧信息列压暗**（`kAwardDimOpacity = 0.55`，`lib/features/competition_award/presentation/award_record_card.dart`）且**不印 `reason`**；其余未计入（缺日期 / 超范围 / 奖励标准无金额 / Ⅳ类不奖学生 / 等次认不出）**同样变暗，但原因照旧印出来** —— 那是唯一能解释「为什么没算钱」的信息，别顺手一起藏。行尾「忽略 / 删除」**不压暗**（唯一能撤销动作的入口）；算不出来的那类**原因行也压在压暗之外**（0.55 的警示色只剩约 1.7:1，等于看不清）。条款本身仍在「本次统计口径」卡（`appliedRules`）与规则原文注记里，因此断言「不累计」「更高奖项」这类文案时**必须把 finder 限定在 `Key('awardRecordCard')` 内**，全局 `find.textContaining` 会被口径卡误伤（踩过）。守卫 = `test/award_calc_test.dart`（两类 `suppressed` 各自断言）+ `test/competition_award_screen_test.dart`「被『取最高』挤掉的行只变暗，不再印第九条 / 第十条的提示」（按 `Key('awardDim-<记录 id>')` 取 `Opacity.opacity`）。
- **时间范围 = 手选起止 + 四个预设**（唯一实现 = `lib/features/competition_award/presentation/award_common.dart` 的 `awardRangeOfPreset(AwardRangePreset preset, {required DateTime now, List<WxSemesterArrangement> terms = const []})`）：**「本学期」优先取校历快照里该学期的真实起止**（`terms` 中 `t.matches(xn: term.xn, xq: term.xq)` 命中的那条 `t.start` / `t.end`，与课表 / 校历同源，见 §9），快照取不到才按学段推（第一学期 `[xn]-09-01 ~ [xn+1]-01-31`、第二学期 `[xn+1]-02-01 ~ [xn+1]-08-31`）；「本学年」= `[xn]-09-01 ~ [xn+1]-08-31`；「近一年」= 今天往前 365 天；「全部」= null。**范围不进库**（只是「这一次想看哪一段」的页面临时状态，重建即回到全部）。守卫见 §26.5 的两条并列用例（空快照走兜底 / 真快照走 261 真实起止）。

### 26.4 实测基线（学校 2024-2026 资料库，改解析先看这组数）

- 竞赛目录：`r21`（2025-2026 年）Ⅰ3 / Ⅱ78 / Ⅲ75 / Ⅳ27；`r20`（2024-2025 学年）Ⅰ3 / Ⅱ75 / Ⅲ71 / Ⅳ10。
- 竞赛奖励标准：58 条（Ⅰ类学生 14 / 教师 14，Ⅱ、Ⅲ类各 6+6，Ⅳ类教师 6）；Ⅰ类学生 国赛特等 4 万（创业计划 3.2 万）、一等 2 万（1.6 万）、二等 1 万（1 万）、三等 5000（创业计划无）；Ⅱ类 6000/600 · 3000/400 · 1500/200；Ⅲ类 3000/400 · 1500/200 · 1000/100。
- 附加分目录：竞赛类 4 项 / 专利类 8 项（含实用新型总上限 0.6、外观 1、著作权 1）/ 著作权 1 项 / 综合类 37 项（分/学年）/ 学术科研类 7 项（含注记里的课题组前 2-5 名 0.15 与 0.1）。
- ⚠ 加分标准原文把创新大赛写作 **「中国国际大学生创新创业大赛」**，而竞赛目录写作「中国国际大学生创新大赛」——**两处名字本来就不同，别去"修"**（组名匹配靠 `创业计划` / `课外学术` / `创新` 三个关键词，两种写法都能归到同一组）。

### 26.5 守卫与入口

- 守卫：`test/award_rules_parse_test.dart`（三个解析器对**真实资产**逐值 + 合并单元格 / 词内空格 + 等次折算）、`test/award_calc_test.dart`（推免 11 例 + 竞赛奖励 12 例 + JSON 容错 + 金额文案）、`test/recommendation_screen_test.dart`（9 例）、`test/competition_award_screen_test.dart`（**11 例**：首屏四卡 / 时间范围四个预设（兜底 + 真快照两条并列）/ 清除范围 / 增删改三条链 / 目录浏览搜索 / 两条源码守卫）。
- ⚠ **两页的 widget 测试各有两条纪律**（照抄，别退回去）：① **不碰 Hive** —— `RecommendationStore` / `CompetitionAwardStore` 的 `add/save` 是真异步 I/O，在 `testWidgets` 的假异步区里永不完成（会把用例挂满 10 分钟）→ 一律用内存假 store 子类 override `records` / `loaded` / `ensureLoaded` / `add` / `update` / `remove`；② **不用 `pumpAndSettle`** —— 页面挂着 `PageAutoRefresher`（首帧后会失效资料库 provider）+ 弹层进出场动画，会被拖到超时 → 用有界 `pump`（`_settle` = 1×`pump()` + 3×`pump(350ms)`）。另外：断言合计金额必须按 `Key('awardTotal')` 取，**记录行也印同样的金额，`find.text` 会撞**；弹层比默认 800×600 高，测试要先 `tester.view.physicalSize = const Size(1000, 2200)` + `addTearDown(tester.view.reset)`。
- 两个页面都用 `paneAppBar(context, title: …)` 且**不传** `settingsSections`（避免动 `test/settings_entry_test.dart` 的映射守卫表）；「查看原文」直达 `RulesReaderScreen(doc: …)`（文档由 `rulesCatalogProvider` 定位，不是写死路径）。
- 配色登记：`FeaturePalette.recommendation = #4A148C`、`FeaturePalette.competitionAward = #BF360C`（深色下由 `featureTone` 提亮，见 §22）。

## 27. 学科竞赛目录的搜索/识别 + 智育四小项（2026-09-18 立）

用户原话（三条一起给的）：
1. 「学科竞赛目录里有很多像『中国高校计算机大赛一①大数据挑战赛、②团体程序设计天梯 赛、③移动应用创新赛、
   ④网络技术挑战赛、⑤人工智能创意 赛』这样的比赛，虽然显示为『中国高校计算机大赛』是正确的，但是搜索
   应该可以被『大数据挑战赛』『团体程序设计天梯 赛』这样的比赛识别到，同时修复一个问题，那就是学科竞赛
   目录中很多比赛名因为在原文件换行，导致了识别出来有空格，你要防止这个导致匹配不上」
2. 「综测智育加分项分为四部分，我希望你分开显示为四小项」
3. 「综测的悬浮显示不能遮盖悬停的地方」（口径见 §25）

### 27.1 名称口径（唯一实现 = `lib/features/zongce/domain/zc_catalog.dart`）
- **`String zcNameKey(String)`**（原私有 `_zcNorm` 已公开改名，**不要再写 `_zcNorm`**）：小写 + 去**全部空白 /
  标点 / 零宽字符（`\u200b-\u200d\ufeff`）** + 全角数字转半角。**自动识别与搜索两侧都要过它**。
- **`String zcCleanName(String)`**：只删「**中文之间**」的空白（原稿换行残留：`团体程序设计天梯 赛` →
  `团体程序设计天梯赛`、`人工智能创意 赛` → `人工智能创意赛`），**保留中英之间的排版空格**
  （`华为 ICT 大赛`、`ACM-ICPC 国际大学生程序设计竞赛`、`香港会计师公会 QP 个案分析比赛` 原样）；零宽字符一律删。
- **`({String main, List<String> subs}) zcSplitCompositeContest(String)`**：复合赛事名拆解 ——
  `主名一①子项、②子项…`（带圈序号 + `、，,；;/` 分隔，子项尾部「等」剥除，主名尾部 `一-—:：·（(` 剥除）
  与 `主名（子项A、子项B）` 两种形态；非复合 → `main` = 原名、`subs` 空。
  内部自带 `_zcSplitParenEnum`，**故意不 import `zc_activity.dart` 的 `zcSplitExample`**（zc_activity 依赖本文件，
  反向 import 会形成库循环）。
- **`List<String> zcContestKeywords(String name)`**：该竞赛名的可搜索词 = 复合子项 + `zcContestAliases` 里
  指向它的别名（`大数据挑战赛/团体程序设计天梯赛/移动应用创新赛/网络技术挑战赛/人工智能创意赛 → 中国高校计算机大赛`）。

### 27.2 搜索与识别
- **`_buildIndex()`** 现在对每个目录名：先 `zcCleanName`，再按「主名 + 复合子项」**逐条建索引**
  （子项条目的 `name` 仍是主名 → 识别出的显示名与类别都正确），并用 `seenKeys` 去重。
  ⚠ `catOf` 的键也要用 `zcNameKey`（**旧代码用 `_zcNorm`，改名后漏一处就会让别名索引失效**）。
- **候选关键词**：`ZcActivityItem` 新增 `List<String> keywords`（默认空）——竞赛候选挂
  `zcContestKeywords(name)`，Ⅳ 类候选挂 `[子项名]`（`江西省大学生科技创新竞赛 <子项>` 的标题空格是**层级分隔**，
  不是换行残留，别一起删）。
- **`bool zcActivityMatches(ZcActivityItem item, String query)`** = 二级页搜索的**唯一口径**（标题 / `namePrefill` /
  任一 `keywords` 三者任一命中即可，两侧都过 `zcNameKey`）。`materials_screen.dart` 的 `_aliasFor`（精确等值匹配）
  与其自带 `contains` 已删 —— **别再各写一套搜索**。
- 守卫 = `test/zc_contest_search_test.dart`（12 例：`zcNameKey`/`zcCleanName`/复合拆解三形态/候选名无「中文间空白」/
  中国高校计算机大赛 5 子项可搜且部分输入可命中/`华为ICT大赛` 能搜到 `华为 ICT 大赛`/空查询/无关查询/
  `zcMatchContest` 认子项与原文复合名/源码守卫）。

### 27.3 智育四小项（`lib/features/zongce/presentation/zongce_screen.dart`）
- 加分项不再是一整块材料列表，改 **4 个小项**：`学科竞赛（表 8）` / `论文 / 专利（表 9）` / `外语能力（表 10）` /
  `创新创业（表 11）`，各带条款悬停（`ids: r77+r37` / `r42+r43` / `r44` / `r45`）、各自分值、各自材料行
  （无材料时给「暂无该小项证明 · 去材料库录入」）。
- **分值一律 `_sumDetail(r, const ['智育 · 学科竞赛'])` 等四个引擎明细前缀**（界面层不重算；四者之和 == 加分项总徽章）。
  新助手 = `Widget _extraItem(BuildContext, {required String label, required double value, required List<String> tipIds,
  required List<ZcMaterial> items})`。
- 守卫 = `test/zongce_zhijia_extra_test.dart`（引擎确实产出四个明细 label；四小项标签与四个 `_sumDetail` 前缀齐备；
  `x.typeId == ZcTypeId.contest|paper|foreign|startup` 四个筛选都在；旧文案「加分项 · 证明材料（四类各计最高）」不得回归）。

## 28. 材料库 → 推免加分项 / 竞赛奖励获奖记录「自动带入」（2026-09-18 立 · 用户原话：「我希望推免和竞赛奖励的加分项自动从资料库中获取」）

用户 ask_user_question 拍板两条：来源 = **材料库**（不是别的模块）、**直接按自动识别结果计入**（不做二次确认）。注意「资料库」在用户口中 = **材料库**：§26 的「目录 / 标准来自 `assets/rules` 规章制度」说的是**可选项清单**，本节说的是**我的条目**来自材料库，两件事别混。

### 28.1 唯一实现 = `lib/features/materials/domain/material_award_bridge.dart`（纯函数；页面不许自己拼映射）

- `kMaterialAwardIdPrefix = 'material:'` / `materialAwardIdOf(materialId)` / `materialIdOfAwardId(awardId)`（手填条目返回 null）——自动条目 id 由此而来，页面据此打「材料库」徽标、判可忽略、去重。
- `class MaterialAwardLink<T>{material, value, reason}` + `linkedValuesOf<T>(links)` / `unlinkedOf<T>(links)`。
- `materialAwardRecordLinks(materials, {excludedMaterialIds, existing})` → 竞赛奖励获奖记录；`materialBonusItemLinks(materials, catalog, {excludedMaterialIds, existing})` → 推免加分项。
- 识别口径：类别 = 材料 `cat`（综测 c1~c4 = Ⅰ~Ⅳ 类）优先、缺失时 `zcMatchContest(name)` 兜底；赛别 = 国家级→国赛 / 省级→省赛，**校级不计入**（办法只有国赛 / 省赛标准）；等次 = `opt` → 特等 / 一等 / 二等 / 三等（「参与(未获奖)」不计入）；备注里写了「第 N 名 / 排名第 N」才取排名（否则沿用既有口径按第 1 名计 + 警告）。
- **加分项三套档位命名各自的对应关系**（改动前先看）：金 / 银 / 铜 → 特等→金、一等→银、二等→铜、三等无档；特等 / 一等 / 二等 / 三等 → 同名对位；第一 / 二 / 三等次奖 → 特等与一等都落第一等次、二等→第二、三等→第三。一般国家级竞赛落「排行榜目录 / 非主体赛道」档（第 4 项），**省级不进竞赛类加分**。
- 综合类荣誉匹配顺序 = **完全相同 → 材料名含目录名（取最长）→ 目录名含材料名（取最短）**——别改成「最长包含」一把梭：材料写「校优秀学生干部」会落到「校优秀学生干部标兵」。
- 专利匹配必须**去掉括号注记后全等**（目录标签写成「实用新型专利第二发明人（第三发明人以下不加分）」，用 `contains('第三发明人')` 会把第三发明人误配到第二发明人那档）；实用新型 / 外观只有第一、第二发明人两档，更后的序位**不回落**。
- ⚠ 去重**只对手填条目**生效（竞赛名 + 日期 / optionId + 日期）；材料库同一天登记同赛事的不同级别是两条真记录，各自交给第十条 / 第九条注取最高。
- 行标题 = **材料名**（不是加分标准原文那一整段「1.国家级Ⅰ类赛…；2.列入…」，否则同一段会连着重几行）；命中的目录项由 `optionId` 保留、判定依据写进 note（`来自材料库 · 国家级 · 排行榜目录 / 非主体赛道档 · …`）。
- 折减只在材料写明时套：Ⅰ类 + 备注含「非主体赛道 / 专项赛」→ `nonMainTrackAsClassII`；Ⅰ类 + 「国际项目」→ `international70`。

### 28.2 页面接线（两页同构）

- 推免页（`lib/features/recommendation/presentation/recommendation_screen.dart`）：`ref.watch(zcMaterialsProvider)` → `[...store.items, ...autoItems]` 进 `recommendationOutcomeOf`；自动行徽标 `recAutoBadge-<id>` + 忽略按钮 `recIgnoreItem-<id>`（**没有删除按钮、不可编辑**，因为它由材料库派生）；`recSkippedMaterials` 小节逐条列「材料名：原因」；空态文案改成「材料库里登记的竞赛 / 专利 / 著作权 / 荣誉 / 论文会自动带进来并计入…」。
- 竞赛奖励页（`lib/features/competition_award/presentation/competition_award_screen.dart` + `award_record_card.dart`）：同构，`awardAutoBadge-<id>` / `awardIgnoreMaterial-<材料 id>` / `awardSkippedMaterials`，`[...store.records, ...autoRecords]` 进 `competitionAwardOutcomeOf`。
- 忽略名单 = 两个 store 各自 box 的 `excludedMaterials` key（`recommendationExcludedKey` / `competitionAwardExcludedKey`，`Set<String>` 存材料 id）+ `excludeMaterial(id)` / `includeMaterial(id)`；**自动条目不落库**（每次由材料库现算）→ 改材料库两页当场跟着变。
- **忽略必须可恢复（用户 2026-09-18 十轮：「竞赛奖励功能里可以忽略某些项，但是没有恢复手段」）**：忽略名单只记在 store 里（材料库一个字都不改），所以撤销 = 把材料 id 从名单里摘掉（`includeMaterial`）。页面侧四条口径：
  - 唯一判据 = **忽略名单**（`store.excludedMaterialIds`），**不是** `reason` 文案 —— 材料库改过之后某条可能已经认不出，但它仍在名单里，仍要能恢复（`test/material_award_bridge_test.dart` 有一条专测这个）；
  - 拆分器 = `lib/features/materials/domain/material_award_bridge.dart` 的 `splitIgnoredMaterials<T>(links, excludedMaterialIds)` → `({List<MaterialAwardLink<T>> ignored, List<MaterialAwardLink<T>> skipped})`：`ignored` 给「恢复」按钮、`skipped` 仍只列原因（两页都调它，别在页面里自己 filter）；`reason` 里那句统一文案 = 常量 `kMaterialIgnoredReason`（两处 bridge 都引用它，别再写字面量）；
  - 推免页 = 「已忽略 N 条」节 `recIgnoredMaterials` + 逐条 `recRestoreMaterial-<材料 id>`；竞赛奖励页 = `awardIgnoredMaterials` + `awardRestoreMaterial-<材料 id>`；**两页的「已忽略」节都排在「材料库里还有 N 条没算进来」之前**（前者是「你自己的选择、可撤销」，后者是「材料库的问题」）；
  - 被忽略的条目**不再混进** `recSkippedMaterials` / `awardSkippedMaterials` 节（那节的条数也不含它们）；忽略按钮的 tooltip 补了「忽略后可在卡片下方「已忽略」里恢复」。
- 两页 `_refreshAll()` 都多了 `invalidateIfLoaded(ref, zcMaterialsProvider)`；材料库页脚加了提示行（`materialsAutoFillHint`）。材料库保存 / 删除本身已 `invalidate(zcMaterialsProvider)`，所以「在材料库改 → 两页立刻变」是 provider 层的，不需要额外通道。

### 28.3 实测基线（该账号材料库 9 条 = 8 竞赛 + 1 外语四级）

- 竞赛奖励：8 条全部生成记录 → **7500 元 / 计入 2 条**（Ⅱ类取最高 = 蓝桥杯国家级一等 6000；Ⅲ类 = CCPC 国家级二等 1500）；其余 6 条各自带原因（省级 3 条被「同年度同竞赛取最高 / Ⅱ类只取最高」压掉、外语 1 条「不是学科竞赛获奖材料」）。
- 推免附加分：国家级 5 条落第 4 档（一等→第一等次奖 2 分、二等→1、三等→0.5），**竞赛类只计最高 → 附加分 2.00**，综合成绩 = 91.91（推免加权）+ 2.00 = **93.91**；省级 3 条 + 外语 1 条进未计入清单。
- 忽略 / 恢复链路真机实测：忽略掉最高那条（蓝桥杯 2 分）后附加分立刻回落到 **1.00**，条目从记录列表转到「已忽略 1 条」节并给「恢复」按钮；点「恢复」即回到 **2.00**（「材料库里还有 N 条没算进来」的条数不含被忽略的）。
- 守卫 = `test/material_award_bridge_test.dart`（**19 例**：真实材料库 + 真实 r08a/r01a 资产逐值；含「忽略 / 恢复（splitIgnoredMaterials）」5 例）+ 推免页 14 例（含忽略 / 恢复两条）+ 竞赛奖励页 21 例（含忽略 / 恢复两条）（**两页测试都必须 `override` `zcMaterialsProvider`**，否则会去开 Hive 而失败）。评审图：`design_preview/round11_rec_autofill.png`、`design_preview/round11_award_autofill.png`。

### 28.4 赛事经验系数（按赛事手动缩减金额 · 2026-09-18 二轮）
用户原话：「竞赛奖励有一个经验系数，就是有些奖项它拿的人太多，就会导致奖金被等比例缩小，而这个比例一般是固定的，我希望可以手动设置」。ask_user_question 两条拍板：**按赛事设**（一个赛事的比例固定，配一次即可，该赛事所有记录等比缩减）+ **行内明算**（记录行写「6000 元 × 0.6 = 3600 元」，并在统计口径里说明哪几条被缩减）。与办法原文的关系：第九条注「Ⅱ / Ⅲ类单个赛事总奖励金额超过 10 万元 / 15 万元时按『奖励标准 ×（封顶额 / 该赛事总奖励金额）』等比缩减」——学校实际执行出来的那个比例就是这里的「经验系数」，总额算不出来时直接固定下来。

- 唯一实现 = `lib/features/competition_award/domain/award_coefficient.dart`：`AwardCoefficient{competitionName, factor}`（`toJson` / `fromJson` 容错：脏数据跳过、越界 clamp）；`parseAwardCoefficient(String)` 认 `0.6` / `.6` / `60%` / 全角 `％` / `6折`，**越界（>1）与认不出都返 null**（系数是缩减语义，>1 一定是用错了）；`fmtAwardCoefficient`（去尾零、最多两位）；`awardCoefficientKey`（去全部空白 + 小写，与 `award_calc` 去重同一套）；`AwardCoefficientTable{entries, factorFor, entryFor, affects, upsert, remove}` —— **未设过的赛事恒 1.0**，`upsert` 按归一后的名字覆盖（同名不新增一条）。
- **乘在哪（核心口径）= `competitionAwardOutcomeOf(..., coefficients:)` 的 ②′ 步**：乘在 `AwardAdjustment`（国际项目 70% / 非主体赛道按Ⅱ类）**之后**、第十条与第九条注的「取最高」**之前** —— 学校比的是**实际发放金额**，先缩后比才与办法一致。守卫 = `test/award_coefficient_test.dart` 的「先缩后比」：蓝桥杯 Ⅱ类国赛第一等次 6000 × 0.3 = 1800 < 另一项第二等次 3000 → 让位。⚠ **Ⅱ类国赛第一等次 = 6000、第二等次 = 3000**（别拿两个不同赛事当"不同金额"来造夹具，Ⅱ类同档金额与赛事名无关）。
- `AwardRecordOutcome` 新增 `baseAmount`（乘系数**之前**的金额）/ `coefficient` / `scaled`（= `counted && coefficient != 1`），三者默认 0 / 1 / false → 既有构造点不用改。`lib/features/competition_award/presentation/award_record_card.dart` 在金额上方多渲染一行 `Key('awardScaleExpr-<记录 id>')` = `'6000 元 ×0.6 ='`（未缩减的记录不渲染）。
- 卡片 = `lib/features/competition_award/presentation/award_coefficient_card.dart`，**卡位在「口径原文」卡之后、「获奖记录」卡之前**：`Key('awardCoefficientCard')` / `awardAddCoefficient` / `awardAddCoefficientEmpty` / `awardCoefficientTile-<赛事名>` / `awardEditCoefficient-<赛事名>` / `awardDeleteCoefficient-<赛事名>`；弹层 `showAwardCoefficientSheet` 的 key = `coefNameField` / `coefNameChip-<i>`（当前记录里的赛事名一键填入，免手打长名字打错）/ `coefFactorField` / `coefFactorError` / `coefSave`（名字空或系数非法 → `onPressed: null`）。**弹层收的是 `onSave` 回调而不是 store**（不把数据层拖进 presentation）。行内「影响 N 条记录」由**真实计算结果**反推（数 `outcome.items` 里同赛事名的条数），没有对应记录时显示「当前记录里没有这个赛事（留着下次用）」。
- 存储 = `competitionAwardData` box 的新 key `coefficients`（`competitionAwardCoefficientsKey`，`[{name, factor}]` 整表读写）；store 新增 `coefficients` / `coefficientTable` / `setCoefficient(name, factor)` / `removeCoefficient(name)`（都走 `_persistCoefficients`，尽力而为不抛）。删除要过 `geConfirmDelete`（删完该赛事恢复全额）。
- ⚠ `test/competition_award_screen_test.dart` 的源码守卫「`presentation` 下恰好 N 个 dart」7 → **8**；内存假 store 必须同时 override `coefficients` / `coefficientTable` / `setCoefficient` / `removeCoefficient`（**不碰 Hive**，理由同 §28.2）。
- 守卫 = `test/award_coefficient_test.dart`（14 例：解析 / 展示 / 查表 / JSON 容错 / 接进计算 6 例）+ `test/competition_award_screen_test.dart` 新增 5 例（设 0.6 后合计 6000 → 3600 且行内明算 / 只缩命中赛事 / 添加-编辑-删除三链 / 赛事名 chip / 越界禁用保存）。评审图 = `design_preview/round12_award_coefficient.png`（三列：深色未设 / 深色 ×0.6 / 浅色 ×0.6）。

## 29. 内置 AI 助手（2026-09-19 立 · 用户原话：「我们希望增加一个功能，那就是AI融入项目的底层。我们希望添加一个内置ai功能，通过配置api，然后可以和这个ai对话，这个ai则可以访问到这个软件内部所有的数据（包括设置），比如成绩、比如规章制度、比如课表，我们都可以通过对话与这个ai获取这些信息，比如我们希望可以这样问：我们希望知道今天蒋剑老师没有课的时间，然后ai返回会话。」）

模块自带文档 = **`lib/features/ai/README.md`**（口径表 / 工具清单 / 加新工具四步 / 踩过的坑，与本节互补：README 是施工图，本节是**红线与理由**）。

### 29.1 用户 ask_user_question 拍板的四项口径（改动前先看这里）

| 维度 | 决定 | 理由 |
|---|---|---|
| 模型接入 | **OpenAI 兼容 + 供应商预设**（8 家），可存多套切换 | 国内外主流一家一套，换供应商不必重填；预设里 `deepseek` 是默认档（`kAiDefaultBaseUrl='https://api.deepseek.com/v1'` / `kAiDefaultModel='deepseek-chat'`） |
| 取数方式 | **函数调用为主 + 轻量常驻快照 + 自动降级** | 427KB 校规**绝不能**灌进提示词（检索代替灌注）；快照省掉一轮工具调用 |
| 权限 | **只读 + 写操作二次确认** | 写操作走 `AiWriteGate`，用户不点同意就什么都不发生 |
| 入口 | **首页宫格/侧栏条目 + 全局悬浮球**（可在设置里关；**电脑端不出球**，见 §29.12） | 悬浮球挂在 `MaterialApp.builder`，任意页面可叫 |

其余常量：`kAiDefaultTemperature=0.3`、`kAiDefaultMaxToolRounds=6`（钳制 `kAiMinToolRounds=1` ~ `kAiMaxToolRoundsLimit=12`）、`kAiMinTemperature=0` / `kAiMaxTemperature=2`。

### 29.2 分层与**两份唯一清单**

- `lib/features/ai/{domain,data,tools,presentation}`。铁律：`domain/` **不 import** `data/`；所有协议细节（SSE 分帧 / 请求体形态 / 错误文案）都在 `data/ai_stream.dart` 且是**纯函数** —— 所以每条分支都能单测钉住。
- **工具清单唯一出处** = `tools/tool_registry.dart` 的 `kAllAiTools`（现 **19** 条）+ `availableAiTools(ctx)`（`AiTool.available` 为 false 的不下发给模型，避免模型去调一个必然失败的工具）+ `aiToolByName(name)`。下发给模型的 `tools` 数组与执行时的名字查找都从这一处取 —— **两份清单一旦漂移，就会出现「模型调了一个找不到的工具」这类静默失败**。
- **中文动作名唯一出处** = `data/ai_chat_controller.dart` 的 `kAiToolLabels`，配 `aiToolLabel(name)`（查不到回落工具名）。**每个工具都必须登记**（有守卫）。

### 29.3 工具清单（19 条 · 「访问软件内部所有数据」的落地范围）

| 分组 | 工具 |
|---|---|
| 规章制度 | `search_rules`、`read_rule`（**检索** `assets/rules/text/*.md`，按标题切节 + 缓存打分，不整篇灌） |
| 课表 | `get_my_schedule`、`find_free_time`（**用户那句例子的落地**）、`query_timetable`（教师/班级/教室/课程课表，走教务公共查询） |
| 成绩与学习 | `get_grades`、`get_score_estimate`、`get_deadlines` |
| 培养方案与毕业 | `get_curriculum`、`get_graduation_credits` |
| 生活与综合 | `get_volunteer_hours`、`get_zongce`、`list_materials`、`get_school_calendar`、`get_energy`（电费 + 校园网费） |
| 学籍 / 设置 / 跳转 | `get_student_info`、`get_app_settings`、`update_app_setting`（**唯一 `mutating`**）、`open_page` |

「今天蒋剑老师没有课的时间」的链路 = `find_free_time(teachers:["蒋剑"])` → `publicQueryComboBoxProvider` 把姓名解析成教师 code（精确 → 包含 → 报候选）→ `publicQueryReportProvider` 取课表 → `slotsOfTimetables` 转占用槽 → `findFreeWindows`（含单双周；**连续判定只在一个半日块内**，上午/下午/晚上不合并）→ `PeriodTable` 翻钟点（`第 3-4 节（10:10-11:35）`）。

### 29.4 三条自动降级（`_streamOnce` 里，每条**只降一档**，最多重试 4 次）

1. `stream_options` 被拒 → 去掉字段重发；
2. 流式不支持 → `_streamDisabled=true` 转非流式；
3. tools 不支持 → `_toolsDisabled=true`，改走**「预取数据塞提示词」**：`buildAiDataPack(ctx)` **直接调工具本身**取数（不是另写一套取数逻辑）→ **两条路径口径必然一致**，不会出现「有工具时准、降级后不准」。

- ⚠ `aiLooksLikeToolsUnsupported(body, status)` **必须同时命中「tools/function」关键词与否定词**才算降级信号 —— 否则任何一个普通 400（参数错、余额不足）都会被误判成「不支持工具」而**静默降级**，用户永远等不到真正的报错。
- 同理 `aiLooksLikeStreamUnsupported` / `aiIsStreamOptionsRejected`。三条判定都只改**运行时标志**，**不写回 `AiConfig.useTools` 字段**（下次开新对话仍会先试真工具）。
- `_runLoop` 的 `useTools = !degraded && round < maxRounds` —— **最后一轮不给工具**，逼模型用已经查到的数据作答，而不是再去查一轮然后没机会说结论。

### 29.5 安全与隐私（红线）

- **`aiDioProvider` 是裸 `Dio`**（无 cookie、无拦截器）。**绝不能**复用 `currentImsDioProvider` —— 那个带教务 `CookieManager`，会把学校会话 cookie 发给第三方 LLM 服务商。
- `AiDenyWriteGate` 是**安全默认值**：没接 UI 闸门 = 写操作一律拒绝（不是"一律执行"）。`update_app_setting` 的 `mutating => true` 是唯一需要过闸门的工具。
- API Key 存 Hive（box `aiSettings` / key `settings`）。**全仓 `flutter_secure_storage` 无人 import**（grep 零命中），所以与既有 token 存储口径一致，不为此单独引入依赖。界面只显示 `maskAiApiKey` 的脱敏值（`头5…尾4`）。
- `get_student_info` **刻意不回传**身份证号 / 家庭收入 / 高考分 —— 工具描述里写明，schema 里也不给这些字段。
- 聊天记录 box `aiChat` 的 key = `chat|<account>`（**按账号隔离**：记录里含成绩与课表）；上限 `aiChatMaxMessages = 60`。
- ⚠ **云同步（§23）是载荷白名单制**（`lib/features/library_sync/data/libsp_payload.dart`）→ 新 box 默认**不**进白名单，所以 AI 配置（含 API Key）**不会**外传。**代码里已留注释**：以后往白名单加 box 时别把 `aiSettings` 加进去。

### 29.6 入口（3 处显示 + 1 处设置）

- 首页宫格 / 侧栏条目「AI 助手」= `lib/features/home/presentation/home_service_catalog.dart` 的**第一条** `homeServiceEntries` 条目（条目数 25 → **26**，`test/home_tile_alignment_test.dart` 同步）。
  **宫格 = 第一格；侧栏 = 紧贴「数据一览」正下方**（2026-09-19 二轮用户要求，见 §29.11）—— 靠条目上的 `HomeServiceEntry.sidebarPinned: true`，
  `home_sidebar.dart` 在 `_overviewRow` 之后单独渲染、并在 `_group` 里把这些条目摘掉（**不插分组标题、不加分割线**）。条目表仍是唯一出处。
- 全局悬浮球 = `lib/main.dart` 的 `MaterialApp(builder: (context, child) => AiFloatingBallHost(child: child ?? const SizedBox.shrink()))`；`presentation/ai_floating_ball.dart` 的 `aiChatScreenOpenProvider`（`StateProvider<int>`）> 0 时**自隐藏**（对话页开着就别再压一个球）；设置页「AI 助手」节能关掉它；**电脑端（Windows / macOS / Linux）一律不出球**（用户 2026-09-19 四轮裁定，见 §29.12）。
  ⚠ 三条实测坑（Builder 的 context 在 Navigator **上方** → 必须走全局 `navigatorKey`；鼠标拖拽 slop 只有 1px → 点击会被 pan 抢走；**`dispose()` 里改 provider 会被 Riverpod 拒发通知** → 球再也回不来）全在 **§29.11**，改这个文件前必读。
- 设置页节 = `SettingsSection.aiAssistant('AI 助手')`，**排在 `appearance` 之后（index 1）**；卡片 = `presentation/widgets/ai_settings_section.dart` 的 `AiAssistantSettingsCard`。
- `open_page` 工具**不自己跳转**，只把 `ui:{kind:'navigate', title}` 交给界面渲染一个按钮 —— 跳转权在用户手里（AI 不该替人换页）。页面表**复用** `homeServiceEntries`（`presentation/ai_page_launcher.dart` 的 `openHomeServiceByTitle`），**不另抄一份**。

### 29.7 加一个新工具的固定四步

1. 写 `AiTool` 子类：`spec`（`AiToolSpec{name, description, parameters}`）+ 可选 `mutating` / `available` + `run(ctx, args)`；
2. `kAiToolLabels` 加中文动作名；
3. `kAllAiTools` 加一行；
4. 补测试。

- 工具 `description` **直接决定模型选对工具的概率** → 要写清「问**什么**问题用它」，并顺手写「注意：这个不是 XX，那个用 YY」（有守卫断言描述长度 > 12 且名字是 snake_case）。
- 参数一律走 `AiArgs`（`str/optStr/intOf/boolOf/strList/intList` + `hasError/errorText`），**绝不写 `args['x'] as String`** —— 模型给的 JSON 什么形状都可能有（`strList` 刻意容忍「单个字符串」与「逗号分隔的字符串」）。schema 用 `aiObjectSchema/aiStrProp/aiIntProp/...` 这组助手拼。
- 返回值 = **给模型看的紧凑中文文本**（token 要花钱），结构化数据放 `AiToolResult.ui` 让界面渲染卡片/按钮。失败用 `AiToolResult.fail(说明)` 且**说明要有用**（模型据此决定「换参数重试」还是「如实告诉用户」）。

### 29.8 踩过的坑（都是实测踩出来的）

- **`ScheduleRepository.getSchedule` 是纯在线、无缓存的**（会话不在直接抛 `Exception('获取 JSESSIONID 失败')`）；cache-first 的是**另一条路** `scheduleCacheRepositoryProvider` / `scheduleCachedEntriesProvider`（box `scheduleCache`，不联网，异常返空）。`loadMySchedule` = **先读缓存 → 缓存空才联网**，`MyScheduleData.fromCache` 记录走了哪条。**「缓存空 + 教务也拿不到」要给 error，不能静默返回空列表** —— 那会让 AI 回答「你今天没课」，比报错糟得多。
- **`getCachedStudentInfo()` 是同步的 `Either<Failure, StudentInfo?>`**（不是 Future），取值必须 `repo.getCachedStudentInfo().fold((_) => null, (i) => i)`。
- **`body.stream.transform(utf8.decoder)` 编译不过**：`StreamTransformer<List<int>,String>` 不是 `StreamTransformer<Uint8List,dynamic>` 的子类型（`argument_type_not_assignable`）→ 用 `utf8.decoder.bind(body.stream).transform(const LineSplitter())`。
- assistant 消息带 `tool_calls` 时 **`content` 必须是 `null` 而不是空串**；`tool` 消息必须带 `tool_call_id`；本地错误提示消息（`isError`）**不进线上数组**。
- `_trimHistory` 保留最近 40 条并**回退到 user 消息边界** —— 拆开 `tool_calls` 与它的 `tool` 结果就是 400。
- **Dart 的 `replaceAll` 不解析 `$1`**：md 清洗里写 `replaceAll(re, r'$1')` 会把整行变成字面量 `$1`，必须 `replaceAllMapped`。
- `AiChatScreen.dispose()` 里不能 `ref.read`（`Bad state: Cannot use "ref" after the widget was disposed`）—— `StateController<int>` 必须在 `initState` 里取出来存住。
- 淡描边不要裸写 `outlineVariant.withValues`（源码守卫拦），走 `AppColors.hairline(context, 原浅色alpha)`。
- **学期码不要 +1**：`getSchedule(semester: '${term.xq}')` 传的是 `'0'/'1'`。
- **测试坑**：① widget 测试里 Hive 的真实文件 IO 在假异步时钟上**永不完成** → `AiSettingsStore(persist: false)`（纯内存档）；② override `FutureProvider.family` 用 `overrideWith((ref, arg) async => …)`；③ 要一个真实 `Ref` 时 —— **`ProviderContainer` 本身不是 `Ref`**，用 `container.read(Provider<Ref>((ref) => ref))` 借一个（provider 非 autoDispose，Ref 一直有效）；④ **别用 `TextSpan.visitChildren` 递归收集 span** —— 它在 `text != null` 时**会拿 span 自己回调一次**，照直递归就是无限递归（实测栈溢出刷屏），直接遍历 `span.children`；⑤ 要给对话页喂一段**指定的**消息历史：真控制器的 `_messages` 是私有的、widget 测试里 Hive 又跑不动（见①）→ **继承 `AiChatController` 覆写 `messages` / `traces` / `busy` 三个 getter**，再用 `aiChatControllerProvider.overrideWith` 注入；⑥ 断言「**真的加粗了**」不能只看文字在不在 —— `find.text` 匹配的是 `textSpan.toPlainText()`（markdown 符号已被解析掉，所以 `find.text('**周一**')` 必须 `findsNothing`），要验样式得把 `RichText` 的 span 树摊平后按 `style.fontWeight` / `style.fontFamily` 断言。
- **`TapGestureRecognizer` 不在 `material.dart` 里**（`widgets.dart` 只用 `show` 列了一部分手势类型）→ 要 `import 'package:flutter/gestures.dart';`，否则报 `The name 'TapGestureRecognizer' isn't a type`。
- **span 样式不会自动继承**：`TextStyle.copyWith` 产出的是「字段全满」的样式，嵌套时子 span 会**整体覆盖**父 span（不是合并）→ 渲染器必须把算好的完整样式**显式往下传**，别指望 `TextSpan(children: …)` 继承到父级的粗体 / 字号。
- **`SelectionArea` 不会吞掉 `TextSpan.recognizer` 的点击**（**实测**：包在 `SelectionArea` 里的链接仍然可点、回调拿得到 URL）—— 当初担心选区和点击抢手势才写的测试，结论是两者共存。

### 29.9 守卫与实测基线

- **7 个测试文件共 184 例**：`test/ai_config_test.dart`（28，URL 兜底 / 容错解析 / 多档管理 / 脱敏）、`test/ai_stream_test.dart`（45，SSE 分帧 / tool_calls 分片累积 / 请求体形态 / 错误文案与三条降级判定）、`test/ai_tools_test.dart`（29，md 切节检索 / 注册表守卫 / 公共查询 kind / 我的课表「先缓存后联网」四分支）、`test/ai_more_tools_test.dart`（19，培养方案总账 / 毕业学分合计 / 志愿学年归集与「—」/ 材料分组 / 校历连续非工作日合并）、`test/ai_markdown_test.dart`（**40**，见 §29.10：块级与内联解析 / 真的加粗了真的等宽了 / 表格是 `Table` / 链接可点 / **空卡片守卫 + 端到端回归**）、`test/ai_ui_test.dart`（**18**，对话页空态与未配置态 / 设置卡 / 设置页只显示 AI 节 / 悬浮球自隐藏 / **电脑端设置卡换成说明行** / 写操作确认弹窗）、`test/ai_floating_ball_test.dart`（**9**，见 §29.11 + §29.12：**必须按 `main.dart` 的 `builder` 挂法测**，桌面端两例要 `debugDefaultTargetPlatformOverride`）。
- `dart analyze lib/features/ai lib/features/home lib/main.dart <相关测试>` → **No issues found**；全量串行 `--concurrency=1` → **1916 例全绿 exit 0**（§29.10 时是 1903；§29.11 新增 9 = 悬浮球 6 + 侧栏固定项 3；§29.12 新增 4 = 桌面端球 2 + 平台判定 1 + 设置卡说明行 1）。
- 真机 `flutter run -d windows` READY；VM 探针核到 `homeServiceEntries` **n=26、first=AI 助手、group=info、widget=AiChatScreen**，`AiFloatingBallHost` 与 `_Ball` 都在树里。
- ⚠ **仍未做真实 LLM 往返**（当时没有 API Key，只有用户能测）。第一句建议就问「今天蒋剑老师没有课的时间」—— 那条链路是唯一没有端到端跑过的部分。预期内行为：`useTools` 关掉 / 模型不支持 function calling 时**看不到工具动作条**但数据照样准（走 `buildAiDataPack` 降级路径）。

### 29.10 回答渲染：Markdown + 空卡片守卫（2026-09-19 二轮 · 用户原话：「我希望支持markdown渲染，同时AI回复中偶尔会出现空卡片」）

**Markdown** = `lib/features/ai/domain/ai_markdown.dart`（纯 Dart 解析，可单测）+ `lib/features/ai/presentation/widgets/ai_markdown_view.dart`（渲染）。

- **不复用 `lib/features/rules/data/md_parser.dart`**：那套是给 pdf2md 产出的**法务长文档**用的 —— `BlockKind` 只有 `heading/para/table` 三种，内联格式（粗体 / 行内码 / 链接）、列表、代码块**全丢**；它的 `clean()` 还会折叠 CJK 之间的空格（对代码内容是破坏性的）。对话回答里这些恰恰是高频内容 → **另写一套**（阅读器仍走它自己那套，互不影响）。
- 支持范围：`#` 标题 1–6 / 段落 / ``` 围栏代码块（带语言标注 + 复制按钮）/ 无序与有序列表（**缩进栈**推嵌套深度、`- [ ]` 任务项）/ `>` 引用 / GFM 管道表格（`:--:` 对齐 + 横向滚动）/ `---` 分隔线；内联 `**粗**`、`*斜*`、`` `码` ``、`~~删~~`、`[文字](链接)`、`<http://…>`、反斜杠转义。表格 / 列表 / 标题 / 引用 / 代码块都是**真 widget**（`Table` / `Row` / 更大字号的 `Text.rich` / 左侧强调条 / 横向滚动容器），不是把符号打出来。
- **两条刻意的取舍**：① 单换行**保留成换行**（标准 markdown 折叠成空格；模型爱用单换行分点，折叠后挤成一坨）；② `_` 强调**只在词边界生效** —— 否则 `get_my_schedule` / `snake_case` 会被撕成碎片（`*` 不受此限，但也不吃 `2 * 3 * 4` 这种乘法写法）。
- **容错优先**：认不出的行一律当普通段落，**绝不抛异常**（流式回答每个 token 重解析一次，未闭合的 `**` / 没写完的围栏随时出现，抛异常会让整个气泡挂掉）。
- 整条消息共用一个 `SelectionArea`（块之间能连着选中、复制）；链接点击走全应用统一出口 `externalUrlOpenerProvider`，且**只放行 http/https**（模型偶尔会编出 `javascript:` / `file:`）。
- ⚠ `_LinkRegistry` **按 URL 缓存** `TapGestureRecognizer` 并在 `dispose` 统一释放 —— 流式每 token 重建一遍 span，在 `build` 里新建识别器会以每秒几十个的速度泄漏。解析结果另留 1 条 memo。

**空卡片** = `aiShouldRenderMessage`（`lib/features/ai/presentation/ai_chat_screen.dart` 的**顶层公开函数**）。根因：**带工具调用的那一轮**，assistant 消息的 `content` 常常是**空串** —— OpenAI 协议要求这条消息（连同 `tool_calls`）原样发回端点，而模型在决定调用工具时往往不附任何文字；`_buildList` 曾对**每一条** assistant 消息无条件画卡片 → 每跑一轮工具就多一张只有内边距的空卡片（`content` 非空的分支早有 `'（模型没有返回内容）'` 兜底，所以空卡片只来自工具轮次）。

- ⚠ **`lib/features/ai/data/ai_chat_controller.dart` 一行都不改**：那条空消息是协议要求的历史，删了下一轮请求直接 400。要挡的是**显示**，不是**存储**。
- 三条防线**都在**（别只留一条）：① `aiShouldRenderMessage(m)` 统一判定（`tool`/`system` 与空白 `content` 都不画）；② `_AssistantBubble` 内部再兜一次 `text.trim().isEmpty → SizedBox.shrink()`；③ `AiMarkdownView` 解析出 0 块时返回 `SizedBox.shrink()`。
- 规则抽成**公开顶层函数**就是为了能单测 —— 藏在 `build` 里就只能靠 widget 测试碰运气。守卫里有一条**端到端**用例：给对话页喂「user → 空 assistant(toolCalls) → tool → 最终回答」，断言只长出一个 `AiMarkdownView`。

### 29.11 侧栏固定项 + 悬浮球三条真 bug（2026-09-19 三轮 · 用户原话：「电脑端AI助手在侧边栏放到和"数据一览"下方紧贴；现在的悬浮球点击后概率无反应，电脑端不显示悬浮球」）

**① 侧栏「AI 助手」紧贴「数据一览」下方** —— 靠条目上的标志位，**不是**在 `home_screen.dart` 里硬写一行：

- `HomeServiceEntry.sidebarPinned`（默认 `false`）+ `homePinnedSidebarEntries(all)`（`home_service_catalog.dart`）；AI 助手那条设 `sidebarPinned: true`。
- `home_sidebar.dart` 的 `ListView.children` = `[_overviewRow, ...固定项, ...各分组]` —— **固定项不插分组标题、不加分割线**，与「数据一览」同高（`rowHeight = 38`）直接相接；`_group` 里 `if (!e.sidebarPinned)` 把它们摘掉（**别让它出现两次**）。
- `homeServiceEntriesInGroup` **照旧返回含固定项的全部成员**（只按 group 过滤）→ `test/home_tile_alignment_test.dart` 的「分组并集 = 全目录」不变量不受影响；宫格照旧按目录顺序铺（AI 助手仍第一格）。
- 守卫 = `test/home_sidebar_test.dart` 的「顶部固定项（紧贴「数据一览」）」组（`pinned.top == overview.bottom`、只此一处、它下面才是「教务系统」、点它走的还是 `onSelect`）+ 一条目录守卫（**恰好一条固定项且就是「AI 助手」**）。

**② 悬浮球三条真 bug** —— 全部只在**按 `lib/main.dart` 的真实挂法**（`navigatorKey` + `MaterialApp.builder`）下才暴露。第一版测试把它挂在 `home:` 里（= Navigator 的**后代**），于是三条一路活到用户手上：

| # | 症状 | 真因 | 修法 |
|---|---|---|---|
| 1 | 点击**完全**无反应 | `widgets/app.dart:1707-1717` 把 `routing`（根 `Navigator`）**当参数塞进 `builder` 返回值内部** → builder 的 context 是 Navigator 的**祖先**、悬浮球是它的**兄弟**，祖先链上没有 `NavigatorState` → `Navigator.of(context)` 必抛 `Navigator operation requested with a context that does not include a Navigator`，被 `main.dart` 的 `FlutterError.onError` 吞成日志 | `_openChat` 走 `lib/core/navigation/navigator_key.dart` 的全局 `navigatorKey`（`main.dart:90` 挂在 `MaterialApp.navigatorKey` 上），兜底才 `Navigator.maybeOf` |
| 2 | 点击**概率**无反应（仅电脑端） | **鼠标的拖拽 slop 只有 1 逻辑像素**（`kPrecisePointerPanSlop = 1.0`；触屏是 `kPanSlop = 36`）→ 点一下抖 2px，外层 pan 就赢下手势竞技场、内层 `InkWell.onTap` **永不触发** | `onPanEnd` 里按**全局坐标差**判「几乎没动」，小的当点击补上（两条路互斥、不会双开），并把球位置**放回按下那一刻**（否则每点一次漂 1~2px，多点几次球自己走掉） |
| 3 | 「电脑端不显示悬浮球」= 进对话页后球隐藏、**退出后再也不回来** | `AiChatScreen.dispose()` 里那句 `state--` 跑在 `BuildOwner.finalizeTree()`（unmount 阶段）：① Riverpod 仍认为「widget 树正在构建」，`_notifyListeners` 被 `_debugCanModifyProviders` 拦下并抛 `Tried to modify a provider while the widget tree was building.` → **值改了、监听者一个都没收到**；② 即便通知送出去，`schedulerPhase` 也还是 `persistentCallbacks`，`ensureVisualUpdate()` 在该阶段**不排帧** | 把「减一」推迟到 `scheduleMicrotask`（帧的同步阶段已结束，两条都解除）+ `try/catch` 兜住「容器已随 App 退出销毁」（`Bad state: Tried to use StateController<int> after 'dispose' was called.`） |

- ⚠ **判定「点击 vs 拖拽」不能靠累加 `onPanUpdate` 的 delta**：默认 `DragStartBehavior.start` 下 `_checkDrag` 把首帧 `localUpdateDelta` 置为 `Offset.zero`（`gestures/monodrag.dart:805-811`）→ **单次大幅移动根本不派发 `onPanUpdate`**（`tester.moveBy`、快速一甩都是这种），累加值恒 0、真拖拽被误判成点击。位移一律用**按下点与当前全局坐标之差**，并设 `dragStartBehavior: DragStartBehavior.down` 让那段位移以完整 delta 补发（球才跟手）。
- 顺带修掉的两个隐患：`value.clamp(lo, hi)` 在 `hi < lo` 时**抛 `ArgumentError`**（窗口比球还窄/矮时真的会发生）→ 走 `_clampIn` 先把上界抬到下界；隐藏悬浮球时**保持同一个 `Stack` 形状**，别 `return widget.child`（形状一变，根 Navigator 整棵子树会被卸载 + 用 GlobalKey 重挂）。
- 守卫 = `test/ai_floating_ball_test.dart`（**9** 例，**必须**按 `main.dart` 的真实挂法写）：画得出来 / 点击真能进对话页 / 鼠标抖 2px 仍算点击 / 真拖拽（越过中线）不打开且贴边停靠 / 开关关掉不渲染 / **进对话页后隐藏、退出后必须自己回来** / **电脑端不渲染但宿主与 app 照常** / 电脑端开关开着也不出球 / `aiDesktopPlatformOn` 三桌面端为真、三移动端为假。
- 通用教训（适用于全仓库）：**任何在 `dispose()` / unmount 阶段修改 Riverpod provider 的写法都是错的** —— 通知会被静默丢弃；要改就推迟到微任务或 `addPostFrameCallback`。

### 29.12 电脑端不出悬浮球（2026-09-19 四轮 · 用户原话：「我希望电脑端不显示悬浮球」）

三轮时我把「电脑端不显示悬浮球」当成 bug 修（真因确实是 `dispose()` 改 provider，见 §29.11 ③），用户随即澄清这同时**也是一条产品决定**：桌面端**根本不要**那个球。落法：

- 判定 = `lib/features/ai/presentation/ai_floating_ball.dart` 的**公开顶层纯函数** `bool aiDesktopPlatformOn(String platform) => platform == 'windows' || platform == 'macos' || platform == 'linux';`（吃 `TargetPlatform.name` 小写形式，与 `geMemoMobilePlatformOn` / `avatarMobilePlatformOn` 同一口径；抽顶层是为了能单测）。
- 门控在 `build` 的 `if (enabled && !chatOpen && !aiDesktopPlatformOn(defaultTargetPlatform.name)) _ball(context)` —— ⚠ **仍然返回同一个 `Stack` 形状**（§29.11 那条不变式对桌面端同样成立：形状一变根 Navigator 会被卸载重挂）。
- 设置页 `presentation/widgets/ai_settings_section.dart`：桌面端**不出 `SwitchListTile`**，换成一枚只读说明行（`Icons.desktop_windows_outlined` + 「电脑端不显示悬浮球 —— 入口在左侧导航栏「数据一览」下方的「AI 助手」」）—— **别让用户拨一个什么都不做的开关**。
- 桌面端的入口因此**唯一** = 侧栏「数据一览」正下方那一格（`HomeServiceEntry.sidebarPinned`，§29.11 ①）；移动端仍是「球 + 宫格 + 侧栏」三选多。
- ⚠ **测试坑（本仓库第一次踩）**：`flutter_test` 里 `defaultTargetPlatform` **恒为 `android`**（`package:flutter/src/foundation/platform.dart:25` 注释原文「In a test environment, the platform returned is [TargetPlatform.android]」）→ 既有的悬浮球用例测的本就是移动端行为；要测桌面端必须 `debugDefaultTargetPlatformOverride = TargetPlatform.windows`，且**必须在测试体内用 `try/finally` 复位** —— 用 `setUp`/`tearDown` 会报 `The value of a foundation debug variable was changed by the test.`，因为 `TestWidgetsFlutterBinding._verifyInvariants`（`flutter_test/src/binding.dart:1100` → `debugAssertAllFoundationVarsUnset`，`foundation/debug.dart:45`）在**测试体跑完那一刻**就断言，tearDown 还没轮到。
- 守卫 = `test/ai_floating_ball_test.dart` 的「电脑端不出悬浮球」组（3 例）+ `test/ai_ui_test.dart` 的「电脑端不出开关，改出说明行」（1 例）。