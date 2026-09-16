# SmarterJxUFE · 智慧er江财（Flutter 客户端）— 会话级约定

> 本文件只对本工作区 `D:\Project\Ongoing\smarter_jxufe` 有效。跨工作区通用的纪律（提问纪律、安装路径、沙箱网络经验）在 `~/.dsh/AGENTS.md`，不重复。
> 最近更新：2026-09-16（**§18 页面转场唯一口径（去掉系统默认的中心放大 zoom；全应用横滑 + 淡入 300ms；IMS 入口闸门不再 `pushReplacement`）** · **§17.7 侧栏点击 = 右侧内嵌页面（master-detail，取消内嵌页返回键）** · **排名胶囊改 `#a/b/c`** · **logo 第二批 6 版待选 + 已装 4 个 logo 设计 skill（§17.6）** · **§17 主页布局（宫格 / 左侧导航栏）· 宫格卡片定宽等高 · 数据一览排名胶囊 · 实况窗入口迁设置页 · 应用中文名「智慧er江财」· logo 候选 A–F（第一批已被否）** · **§16 卡片风格唯一口径（全应用统一为「综测评测结果卡」形态：圆角 12 + 淡边框 + 纯白 + 无阴影；单色强调一律改主题红；主页两类卡片只统一形状保留原色）** · **§15.5 选课写入二轮加固（教务写应答是 iframe 回调页 `parent._callBack(...)` 且该端点 fire-and-forget → 写前重读核对 / 写后无条件对账刷新）** · **§4 课程截止日期管理（网课/作业/考试 · 每周/每两周自动滚动 · 本地通知提醒）** · **§12.2 设置页「教务会话」：令牌探活 + 手动刷新（探活优先、失效才换）** · **§4 课程备忘录（文字 + 图片，拷进私有目录 + 压到 1600px，单课 20 张）** · **§4 分数估计「构成占比条」（分段比例条 + 45°/135° 引出线 + 点条设比例，勿回退成滑动条）** · §3「主题纯白」口径（去 M3 seed 派生的偏红白） · §3「数据更新最小间隔 1 分钟」（畅想之星） · §15.4 选课检索栏与教务原页面 8 个控件逐一对齐（类别/属性 = 客户端过滤） · §15 教务「选课」口径（网上选课 / 选课结果 / 退选 + DES 加密移植 + 失效页 UTF-8 解码口径 + 学号 `xh` 口径核实） · §14.7 公共查询「账号默认预填」+ 卡片纯白 · §14 教务「公共查询」口径（教师/班级/教室/课程课表 + 多班对照找无课时间） · §13 Fluent Design 基础层 · §12.1 统一登录（CAS）按账号持久化 · §12 IMS 全局会话口径 · §11 首页顶栏 + 账号头像口径 · §9「当下学期」唯一口径 · §10 桌面小组件）。

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
- 长命令一律 `run_in_background: true` + 大超时；`Select-Object -Last N` 截尾。
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
  ⚠ **旧铁律已作废**：从前条目写在 `home_screen.dart` 的私有 `_items(context)`、强调色存在顶层 `const _tileColors`，两者**按索引对齐**（增删磁贴必须同步增删色表）。现在只有一份目录、颜色随条目，**不可能再错位**；增删入口只动 catalog 一处，并同步 `test/home_tile_alignment_test.dart` 的条目数（现 21 条）与本文件。详见 §17。
- **UI 风格基准 = 首页宫格页**：功能卡 `Card(elevation: 0, shape: appCardShape(context))` + `Clip.antiAlias`；节标题用 `geCardTitle`（3px 竖条 + 13.5 w600，`accent` 默认主题红）；列表 `padding: EdgeInsets.fromLTRB(24, …, 24, 48~96)`；卡间 12；图标 22–24 用 **Material Icons**（不用 emoji）。共享件在 `lib/features/score_estimate/presentation/ge_common.dart`（`geCardShape`——已转发到 `appCardShape` / `geCardTitle` / `geFmt` / `GeModeBadge`）；**卡片形状与强调色的唯一口径 = `lib/design/app_card.dart`（见 §16）**，别在页面里再拼一套 `BorderRadius.circular(…)` + `BorderSide(…)`。
- 图标按钮用 `IconButton(tooltip: …)`；`AlertDialog` 用 M3 默认样式 + `icon:`。
- **交互必须触摸可用**：手势**不得只挂在 `MouseRegion` hover 开关上**——触摸设备永不产生 hover，被 hover 门控的手势等于没注册（`lib/shared/widgets/academic_year_picker.dart` 曾因此在手机上整条划不动，且同一开关还控制着透明度）。拖拽一律用真实指针事件（`onHorizontalDragStart/Update/End/Cancel`）驱动状态，hover 只做增强。
- **全局偏好入口 = `lib/features/settings/presentation/settings_screen.dart`**（首页右上角齿轮进入）。新增用户偏好一律收拢到这里，不要再新增 feature-local 设置弹层（校历的三个显示开关已于 2026-09-11 迁入本页「校历」节，校历页 AppBar 齿轮只做跳转）。持久化照 `lib/features/campus_address/data/my_campus_prefs.dart`：Hive `Box<String>` 单 key + `ChangeNotifier` + `ChangeNotifierProvider`（改动需即时反映到多个页面时用此模式，**别用 FutureProvider**——中间有异步空窗，页面会先闪一次旧值）。
  - 已收拢的偏好（新增偏好照此追加，别另开弹层）：**入馆教育答题模式** = `lib/features/library_edu/data/tsgxs_prefs.dart`（box `tsgxsPrefs` / key `answerMode`，存 `TsgxsAnswerMode.name`），**唯一切换入口 = 设置页「入馆教育」节**；`tsgxs_exam_screen.dart` 与 `tsgxs_chapter_screen.dart` 只读该偏好（用户 2026-09-11 裁定：「模式的切换不应该显示在任何页面，只能显示在设置页」）——别再往页面里加模式切换控件或 `initialMode` 参数。

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
| 志愿时长登记表 | GET `ssp.jxufe.edu.cn/admin/tzz/StuVolWork/downloadInfo.do`（`Cookie: JSESSIONID=<ssp 会话>` + `Referer: …/StuVolWork/stu_list.html`） | 学校「学生活动时长统计」页右上角 **「下载时长认定登记表」** 按钮的同款接口，返回 **Word 原件**（OOXML，字节头 `PK\x03\x04`，实测 14961 B，**没有 PDF 接口**）；`Content-Disposition` 里中文文件名是 **UTF-8 字节被 HTTP 头按 latin1 解码** → 必须 `latin1.encode → utf8.decode` 还原（`volunteerExportFileName`）；会话失效 = 3xx 或 200 的登录页 HTML（`_looksLikeHtmlBytes`） |

链路：学籍 → `collegeRepository.getAllCollege()` 按名匹配 → `majorRepository.getAllMajorIn(college, year:)` 按名匹配 → 培养方案。任一步失败**返回空索引、不阻塞界面**（回退课程自身学分）。

## 6. 工作区状态

- git 工作区有**大量历史 untracked**（`.scratch/`、`dianfei_work/`、`packaging/`、`reverse_engineering/` 等），不要清理、不要 `git clean`。
- 测试是扁平的 `test/*_test.dart`（**74 个文件**，引擎/纯逻辑单测为主；**⚠ 另有 10 张 golden** —— `test/goldens/qa_r*.png`，由 `test/qa_rules_visual_test.dart` 驱动，旧说法「无 golden」已过时）；`flutter test` 全量 **963 例：962 通过 / 1 失败**（2026-09-16 实测，本次新增 `app_page_transitions_test` 9 / `home_detail_pane_test` 6 / `home_grade_rank_badge_test` 4 / `home_sidebar_test` +4）。**唯一失败 = 模板遗留 `test/widget_test.dart`**（`Counter increments smoke test`，`Found 0 widgets with text "0"`，历史上一直失败，别当回归）。2026-09-11 记的两个失败**都已修复**：`settings_calendar_section_test` 的 3 例 Hive 失败（该文件 `setUpAll` 补了 `Hive.init`）、`auth_session_account_test.dart:230`（当时正被别的会话编辑）。部分文件实测（**非全部**）：`ge_engine_test` 26、`ge_curriculum_test` 11、`ge_summary_test` 8、`calendar_day_mark_test` 47、`my_campus_test` 23、`zongce_engine_test` 15、`school_term_test` 14、`account_avatar_test` 21、`school_calendar_screen_test` 8、`school_calendar_parser_test` 6、`tice_notice_test` 5、`cxstar_auth_test` 8、`read_credit_cxstar_progress_test` 4、**`public_query_test` 35、`public_timetable_parser_test` 19、`public_free_time_test` 23、`public_timetable_view_test` 4**（公共查询四件套，2026-09-14 加，见 §14）、**`course_selection_des_test` 13、`course_selection_parser_test` 21**（选课，2026-09-14 加，见 §15）、**`student_id_test` 5**（教务 `xh` 口径守卫，2026-09-14 加，见 §15.1 第 5 条）、**`ims_token_refresh_test` 12、`ims_session_card_test` 3**（教务令牌探活/手动刷新，2026-09-15 加，见 §12.2）、**`course_selection_filters_test` 16、`course_selection_search_ui_test` 5**（选课检索栏逐控件对齐教务原页面，2026-09-15 加，见 §15.4）、**`home_layout_test` 9、`home_service_grid_test` 6、`home_sidebar_test` 9、`home_tile_alignment_test` 6、`home_detail_pane_test` 6、`home_grade_rank_badge_test` 4**（主页布局 / 宫格定高 / 侧栏 / 服务目录 / **右侧内嵌面板** / **排名胶囊文案**，2026-09-15~16 加，见 §17）、**`app_page_transitions_test` 9**（页面转场取代系统 zoom，2026-09-16 加，见 §18）。
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
- **课表页排版口径**（2026-09-15）：手机竖屏（< `ScheduleGridView.compactBreakpoint` = 620dp）**左右无边距**、列宽 = 可用宽度 / 7（整表铺满屏宽、不横向滚动）、字号/行高按 `compact` 收紧；桌面端列宽在 80~160 间自适应屏宽，**超过 160 不再拉伸而是整表居中**、不足 80 才横向滚动。`ScheduleScreen` 用**自己的 AppBar** 承载「学年 + 学段 + 周次/整学期」选择器（**不再显示「课表」标题**），`ims_tab_container.dart` 对 `ImsTab.schedule` 不再叠一层 AppBar。**标题栏单行/两行按可用宽度自适应**（用户 2026-09-15 问「为什么学期选择和周数显示不在同一行」→ 从前写死两行、桌面端白占一行）：唯一实现 = `lib/features/ims/schedule/presentation/schedule_title_bar.dart` 的 `ScheduleTitleBar`（+ `ScheduleSemesterSelector` / `ScheduleWeekSwitcher`，正文筛选栏复用），静态 `fitsOneRow` / `rowNeed`（TextPainter 实测量宽）/ `toolbarHeight(oneRow:, compact:)`；**抽成不依赖 provider 的独立组件就是为了可测**。守卫 `test/schedule_grid_layout_test.dart`（360/900/1600 三档断边距/铺满/居中）+ `test/schedule_title_bar_test.dart`（1400/900/460 同一行、360/320 两行、两档高度不溢出、周次按钮仍可用、手机端学期码按钮与弹窗）。
  - ⚠ **`rowNeed` 量宽口径（2026-09-15 二轮校正，用户「还有很大的空隙，但继续减小宽度就换行」）**：① 量宽基础样式必须取 **AppBar 标题样式**（`appBarTheme.titleTextStyle ?? textTheme.titleLarge`）——调用点在 `Scaffold` **之外**，`DefaultTextStyle.of(context)` 在那里是 fallback（无字体族），裸 `TextStyle` 同理，两者都把文字量宽约 2 倍（实测 `261`@15：默认字体 45.0 vs 真实 23.25）；② 非 compact 档「学年 + 学段」内部间距是 **8**（与 build 的 `SizedBox(width: compact ? 4 : 8)` 一致），别再用 `gap`（会被算两遍）；③ 图标按钮实测宽 **40**（48 点击区 − 8 visualDensity），不是约束里的 30/34；④ 学段下拉比文字宽 **19**（实测，别写 32）；⑤ **`week` 必填**：`本周` 按钮在 `week == currentWeek` 时不渲染（进入课表页的默认状态），恒预留会白占 ~35px —— 组件 build 与 `ScheduleScreen.build` 两处判定都要传；⑥ `fitsOneRow` 余量收到 **6**（校准后 need 与真实内容宽偏差 −3~0，week=null 档按最宽文案保守 12）。**守卫 = `test/schedule_title_bar_test.dart` 的「不变式」组**（`_pumpProduction` 镜像生产：判定在 Scaffold 外算、标题栏进真实 AppBar；`_loadThemeFont` 用 `C:\Windows\Fonts\simhei.ttf` 注册成主题字体族——**不注册字体则此 bug 量不出差别**）：断言 `need − real ∈ [−6, +15]`、可用 = 真实内容 + 24 必须单行、窄于真实内容 12 必须换行且不溢出。
- **学期码 `xxy` 与学期选择器**（2026-09-15，用户口径「xxy 代表 xx-(xx+1) 学年，y=1 第一学期、y=2 第二学期、y=3 第二阶段；阵列固定三行、左右延伸、范围可选」）：唯一实现 = `lib/features/school_calendar/domain/school_term.dart` 的 `schoolTermCode(xn, xq)`（= `'xx${xq+1}'`）、`schoolTermFromCode(code)`（严格 3 位数字且末位 1~3，否则 null）、`schoolTermPickerRange({enrollYear, currentYear})`（范围 = 入学年 ~ 当前学年；学籍取不到或不合理 → 当前学年往前 4 年）、`schoolTermsInRange({startYear, endYear})`；UI = `lib/shared/widgets/school_term_grid.dart` 的 `SchoolTermGrid`（行 = 学段、列 = 学年，格子即学期码；`Key('schoolTermRow-N')` / `Key('schoolTermCell-<code>')`）+ `SchoolTermCodeButton` + `showSchoolTermPicker(...)`（弹窗里**纯 Column、无 viewport**，带「当前：<完整学期名>（<码>）」与口径说明）。**手机端学期码按钮 = 纯文字**（用户 2026-09-15 裁定「不要显示边框，不要显示下拉 icon，只显示 xxy 学期的字样」）：`Tooltip > InkWell > Padding > Text`，量宽契约 = `SchoolTermCodeButton.padding`(6) / `fontSizeOf(compact)`，**改字号或内边距必须同步 `ScheduleTitleBar.rowNeed`**；守卫 `test/schedule_title_bar_test.dart`「学期码只有文字：无边框、无下拉 icon」。**手机端课表标题栏（`compact`）= 学期码按钮 + 该弹窗**（学年选择器与学段下拉只在桌面端与 `_buildFilters` 保留）；范围由 `ScheduleScreen._termPickerRange` 算好传入、夹在 `firstYear/lastYear`。**桌面端整组居中**（用户 2026-09-15「电脑端学年学期选择器居中」→ 拍板「整组居中」）：`ScheduleTitleBar.build` 在非 compact 时 `return Center(child: KeyedSubtree(key: scheduleTitleContentKey, …))`，手机端仍靠左；**内容必须包 `scheduleTitleContentKey`** —— 居中后组件自身 RenderBox 会撑满标题槽，量真实内容宽度必须量这个 Key（守卫：`test/schedule_title_bar_test.dart` 的「标题栏对齐」组，按 chrome 56+96 算标题槽中心断言 |Δ|<2）。⚠ `schoolTermCode` 的 `xxy`（用户界面口径，第二阶段 = 3）与 `wxcal_semester.dart` 的 `wxTermCode`（**小程序数据源** term 字段，无暑期段、xq=2 时给 `…2`）**不是一回事**，别互相替换；`schoolTermLabel` 已按 `xqDisplayName` 修正（第二阶段从前被写成「第二学期」）。守卫 `test/school_term_picker_test.dart`。
- **课表视图选型 / 横竖屏 / 拖动切周 / 教室换行**（2026-09-15 第三轮，用户六条：横版恒适应宽高 · 移动端取消横竖切换按钮改按横竖屏 · 移动端标题栏也居中 · 横滑切周要拖动动画 · 教室放不下就换行 · 学期按钮后加「学期」二字）：**选型唯一口径 = `lib/features/ims/schedule/domain/schedule_view_mode.dart`** 的 `scheduleAutoViewByOrientation(platform)`（Android/iOS = 手机）/ `scheduleViewModeFor({platform,width,height,manualHorizontal})`（手机按横竖屏自动、桌面听按钮）/ `scheduleCompactLayout` / `scheduleMobileInput` / `scheduleCompactBreakpoint`(620)（`ScheduleGridView.compactBreakpoint` 引用它，**只此一份**）；页面里用 `Theme.of(context).platform` 取平台，别写 `defaultTargetPlatform` 分支。**手机端不渲染横/竖切换按钮**（两个视图的 `showToggle` 参数），桌面端保留。**横版课表恒适应宽度与高度**（`schedule_horizontal_view.dart`：12 节次等分可用宽度、7 行平分可用高度、**无任何滚动容器**；行高被压缩时按 `_twoLineNameHeight`(56)/`_twoLineClassroomHeight`(46)/`_teacherHeight`(70) 取舍内容行，绝不溢出）。**竖版行高自适应**：`ScheduleGridView._fitCellHeight({compact,maxHeight,verticalPadding})` 有空间就撑满（底部不留空档）、不够才滚动，最小行高 `_cellMinHeight`=68 / `_compactCellMinHeight`=64（要装下换行后的教室）。**教室换行**：`classroomLines = slots.length > 1 ? 1 : 2`（同格多门课时留给分隔行与第二门课），别改回恒 `maxLines: 1`。**标题栏恒 `Center`**（手机端同样居中，2026-09-15 追加）；学期码按钮文案 = `SchoolTermCodeButton.labelOf(code)` = `261 学期` —— `rowNeed` 必须用同一函数量宽。**拖动切周 = `lib/features/ims/schedule/presentation/week_pager.dart`**（用户 2026-09-15：「移动端切换周数的动画太奇怪了，我希望就是很自然像手机桌面翻页一样」——`WeekPager` = 一页一周的 `PageView`：**相邻周并排在左右两侧随手指 1:1 位移**、松手按距离/速度 snap（`PageScrollPhysics`）、首末周自然回弹；旧的手写 `week_swipe_wrapper.dart`（跟手 translate + 滑出→硬切→另一侧滑入，滑出时会露出空白）**已删除，别复活**）。`WeekPager` 参数 = `weekCount/week/enabled/onWeekChanged/pageBuilder`；外部改周（上一周/下一周按钮、学期切换、周次夹取）由 `didUpdateWidget` 跟随 —— **相邻一周走补间**（`pageTransition` = 280ms）、**跨多周直接 `jumpToPage`**；`ScheduleScreen` 里整学期视图（`week == null`）不分页，周视图才包 `WeekPager`，每页各算 `mondayOfWeek`。守卫 `test/week_pager_test.dart`（12 例：跟手位移 + 邻页同屏、过阈值 snap、fling 也切页、小幅回弹、首末周不越界、越界夹取、外部改周补间/跳转、`enabled=false` 不响应手势；**量页面位置要按页面的 `Key`，量页内居中文字会把留白当位移**）。守卫：`test/schedule_view_mode_test.dart`（真值表 + 横版铺满 + showToggle）、`test/schedule_week_info_test.dart` 的「课程教室放不下就换行」组、`test/schedule_title_bar_test.dart`（手机端也居中 + `251 学期`）。
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
