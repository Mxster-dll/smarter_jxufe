# SmarterJxUFE · 智慧er江财（Flutter 客户端）— 会话级约定

> 本文件只对本工作区 `<仓库根>` 有效。跨工作区通用的纪律（提问纪律、安装路径、沙箱网络经验）在 `~/.dsh/AGENTS.md`，不重复。
> **本文件是「薄入口」**（维护规则见全局 `~/.dsh/AGENTS.md` 的「自觉维护」节）：只放 §1–§3 常驻纪律 + 分册索引；**细节结论一律写分册，这里只留指针**。唯一硬约束 = 65536 字节指令预算 —— 超了整份文件任何 agent 都读不到。
> 最近 3 条更新记录（ehall 内嵌网页 / 挂科口径 / 培养方案实践环节）已原文移入 `docs/agents/37-最近更新存档（2026-09-27 及更早）.md` 的「追加存档」节；更早的记录同样在该册。**新增口径请按归置顺序落笔：跨工作区通用→全局；本工作区通用纪律→§1–§3；模块领域口径/长台账→对应分册。**

## 本文件的用法（2026-09-19 拆册 · 通用约定，不依赖任何工具的私有语法）

- **本文件 = 唯一必读入口**。所有 agent 工具（Claude Code / Codex / Cursor / Gemini CLI / DSH …）都只自动读取工作区根目录的指令文件，且**都受字节预算限制**（DSH 实测上限 **65536 字节**）。拆册前本文件 **488 KB → 87% 的内容任何工具都读不到**；现在根文件约 33 KB，**全部可见**。
- **§1–§3 = 常驻纪律**（本机命令 / VM 探针 / 代码与设计约定），留在本文件，开箱即用。
- **§4–§40 = 分册正文**，在 `docs/agents/<NN>-<标题>.md`，**不自动注入** —— 需要时用读文件工具按需读，路径见文末索引表。
- 交叉引用沿用 `§N` / `§N.M` 节号：查 `§N` → 先看文末索引表定位文件 → 再读。**分册里的节号与标题原样保留，禁止重编号**（代码注释与测试里都有 `§N` 引用）。
- 新增约定先判归属：跨模块纪律写进本文件（§1–§3）；模块 / 领域口径写进对应分册，分册不存在就新建 `docs/agents/<NN>-<标题>.md` 并在索引表登记（NN 取下一个未用节号，**不复用**）。
- ⚠ 本文件可能被并行会话同时编辑：改之前先 read，`edit` 报 `file changed since it was read` 就重读再改。
## 1. 本机 Flutter/Dart 命令（重要：`flutter.bat` / `dart.bat` 会卡死）

包装脚本内部会再起一层 PowerShell，实测 120–180s 无输出。**一律直连**：

```powershell
$env:FLUTTER_ROOT='<FLUTTER_ROOT>'; $env:FLUTTER_SUPPRESS_ANALYTICS='true';
$env:FLUTTER_ALREADY_LOCKED='true'
$dart = "$env:FLUTTER_ROOT\bin\cache\dart-sdk\bin\dart.exe"
$snap = "$env:FLUTTER_ROOT\bin\cache\flutter_tools.snapshot"
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
Remove-Item '<仓库根>\build\flutter_assets' -Recurse -Force -EA SilentlyContinue
# env 见上；日志 %TEMP%\ge_flutter_run_windows.log / .err.log
Start-Process $dart -ArgumentList $snap,'run','-d','windows' -WorkingDirectory <repo> -WindowStyle Hidden `
  -RedirectStandardOutput $log -RedirectStandardError $err
# 轮询日志出现 'Flutter run key commands' 即 READY；正则抓 http://127\.0\.0\.1:\d+/[A-Za-z0-9_=-]+/
```

- 失败关键字：`Build process failed|LNK1168|MSB8066|Error launching`。
- 分离会话**没有 stdin 通道**，发不了 `r`/`R`；改代码 = 重启会话（约 1–3 分钟）。
- 该 dart 进程可能自行退出（日志留 `Lost connection to device.`），此时 VM Service 端口失效、但 app 进程仍活着 → 重新走本套路。

### 1.3 ⚠️ 桌面端启动曾被「通知插件原生 abort」拖死（2026-10-07 实测 · 已处置）

**症状**：`flutter run -d windows` 或直接跑 `build\windows\x64\runner\Debug\smarter_jxufe.exe` —— 构建成功、打印 `🪟 通知平台: Windows` 之后，进程**原生 abort**（弹 `Microsoft Visual C++ Runtime Library — Debug Error! abort() has been called`），**窗口永远不出现**（`EnumWindows` 能看到 `FLUTTER_RUNNER_WIN32_WINDOW`/「智慧er江财」，但 `IsWindowVisible = False` —— runner 是**首帧之后**才 `Show()`，没首帧就没窗口）。Dart 侧 `try/catch` **接不住**（`abort()` 杀进程，不是异常）。

**定位手法（可复现，值得记住）**：造一个**只画一行字**的探针入口，用 `-t` 换掉 `main` 再逐项二分 ——
`& $dart $snap build windows --debug -t lib/tmp_probe_main.dart` → 直接跑 exe：
- 只 `runApp(一行字)` → **2 秒出窗口** → 引擎 / GPU / 窗口 / 插件加载 / pdfium / Hive 全部正常；
- 加上 `NotificationService.instance.init()` → **立刻 abort**；去掉它、其余启动步骤（pdfrx / HomeWidgetLauncher / `HiveInitializer.init()` / `ThemeModeStore`）全留 → 窗口照出。
→ 唯一凶手 = **`flutter_local_notifications_windows` 的原生 `initialize()`**。

**处置**：`lib/shared/services/notification_service.dart` 的 `instance` 在 Windows 上退回 `_NoopNotificationService()`（`windows_notification_service.dart` 的 import 也去掉了，恢复办法写在注释里）。桌面通知本就是「开发期验证」性质、课前提醒只跑 Android（§35），这个取舍可接受。**改完实测：真实应用 2 秒出窗口、稳定存活（300s+）。**

⚠ **热重载曾经不可用 —— 2026-10-09 已定位并修好（原结论「机器层面、疑似杀软」作废）**：
症状 = 应用进程建不了临时目录（`Directory.createTemp` → `PathAccessException … errno = 5`）→ DevFS 起不来 → `_createDevFS: (-32603)`，flutter_tools 自己崩掉。
**真凶 = agent shell 把进程树的写操作限制在工作区内**（不是杀软 / ACL / exe 完整性级别）：探针入口在应用进程里逐条试过 —— `%LOCALAPPDATA%\Temp` ✗ `%TEMP%\…` ✗ `AppData\Roaming` ✗，而**仓库内** `build/devfs/…` ✓ `app_data/…` ✓ 全能建。
**修法**：① 起 `flutter run` 前把 `TEMP/TMP/TMPDIR` 指到工作区内（`build\tmp`）→ DevFS 正常（`Syncing files to device Windows...` = 可用；pdfrx 的字体缓存目录也跟着好了）；② agent 的后台作业没有终端、发不了 `r`/`R` → 用 `.probe/dev_driver.py` 常驻（`--machine` JSON 协议 + 本机命令口 `127.0.0.1:8791`），`.probe/hot.ps1 reload|restart|stop|status` 触发。⚠ daemon 协议**没有 `app.reload`**：热重载 = `{"method":"app.restart","params":{"fullRestart":false}}`、热重启 `fullRestart:true`（`flutter_tools/lib/src/daemon.dart:855`）；热重载**保留运行时状态**。⚠ 只覆盖 Dart 侧：改 `windows/runner/*.cpp` 仍需 `flutter build windows` + 重启。
⚠ **用户自己终端里跑 `flutter run` 从来没有这个限制**（沙箱只作用于 agent 起的进程）。

## 2. VM Service 探针（不靠 UI 就能验证真实数据路径）

python `websocket-client`（`<PYTHON>`）脚本在 `%TEMP%\vmprobe\`：`ge_probe.py`（成绩缓存）、`ge_courses.py`（课程）、`ge_steps_probe.py`（学籍→学院→专业→培养方案逐步链路）、`ge_rc_probe.py`/`ge_calc_probe.py`（真实容器 + 端到端复算）。用法：

```
python ge_calc_probe.py "ws://127.0.0.1:<port>/<token>=/ws"
```

- 端口每次重启都变，从 run 日志抓；app 的 `print/debugPrint` **只进 run 日志**。
- `evaluate` 的 expression 必须是**单行**（多行会报 `Can't find '}' to match '{'`），用 `(() { ... })()` 包裹；`late void Function(...) f;` 才能写递归闭包。
- **库作用域只含该库直接 import 的名字**：`studentInfoRepositoryProvider` 只在 `ge_providers.dart` 可见，`geCalc/geWeightedSummary` 只在 `ge_engine.dart`/`score_estimate_screen.dart` 可见 → 按需选 target library。
- 取真实 `ProviderContainer`：运行时树是 `RootWidget → View → RawView → … → UncontrolledProviderScope`（约 14 层）。`ProviderScope.containerOf(rootElement)` 会 `Bad state: No ProviderScope found`（异常被 VM 当成**返回值**，`evaluate` 仍报 OK，别被骗）；要沿 `visitChildren` 向下走到能 `containerOf` 成功的那层。
- 新建 `ProviderContainer()` 也能验证纯本地链路（学籍/学院/专业/培养方案缓存命中时**零网络**）。

### 2.1 离线读真实 Hive box（app 运行中目录被锁）

把 `app_data\<box>.hive` 复制到临时目录（如 `%TEMP%\gecurr`、`%TEMP%\gecache`），在 `flutter test` 里 `Hive.init(path)` + **手工 registerAdapter**（`AssessmentMethod/CourseImportance/CourseNature/CourseRequirement/CreditHour/Course/Curriculum/Major/College/FunctionType`，见 `lib/core/storage/hive_initializer.dart`）。临时诊断测试**用完即删**（`test/tmp_*.dart`）。

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
- **学校时间（学年 / 学期 / 假期）的唯一出处 = `lib/features/school_calendar/`**（2026-09-27 · 用户要求「独立出来被所有模块复用」）：领域 `domain/school_time.dart`（`SchoolYear` / `SchoolBreak` / `SchoolTimeTable` + 学期标识归一 + 兜底 `schoolYearFallback` / `schoolYearOrFallback` / `schoolYearStartOf` / `schoolDayText`）；其它模块**只经** `data/providers/school_time_providers.dart` 的 `schoolTimeTableProvider` 取数；**学年 = 第一学期第一天 ~ 下学年第一天前一天，取不到就 null**；「当下学期」仍旧走 `domain/school_term.dart`；校历页有「学年时间」卡；zongce / 志愿时长的学年窗口已收上来（转发别名）；口径与实测台账见 **§36**。**课表侧另有一层「校历效应」（假期不排课 / 补课日改上被补那天的课 / 隐藏周六周日只在没课时生效），唯一实现 = `school_calendar/domain/calendar_day_effect.dart` + `ims/schedule/domain/schedule_board.dart`，取数入口 = `school_calendar/data/providers/calendar_effect_providers.dart` 的 `calendarDayEffectIndexProvider`，口径全文见 §39。**
- **跨模块「地基件」的唯一实现（2026-09-20 · 架构审查后收敛）**：Cookie 罐 = `lib/core/network/cookie_jar.dart` 的 `SessionCookieJar`（**认 `Domain`**，超星系 / 图书馆用）与 `HostCookieJar`（**按 host 分桶**，单域换证站点用；7 个站点的私有三件套已迁完 4 个）+ `setCookieNames`（trace 打 `Set-Cookie` 的**唯一出口**，只出名字 —— 手写 `c.split(';').first` 打的是 `name=value`，会把凭据写进日志）；自动刷新闸门 = `lib/core/navigation/refresh_gate.dart` 的 `RefreshGate`（各模块只准继承）；教务会话失效 = `lib/core/network/jw_page_decoding.dart` 的 `jwSessionExpired` / `jwSessionExpiredPrefix` / `JwSessionExpiredException` / `isJwSessionExpiredError`（**数据层不许拿文案当类型**）；SSO 登录页判据（判**正文**）= `lib/core/network/sso_login_page.dart` 的 `ssoLoginPage` / `ssoLoginPageBytes`；CAS 打回登录页判据（判 **URL**）= `lib/core/network/cas_redirect.dart` 的 `isCasLoginRedirect`（精确到路径末段、先剥 `;jsessionid=`、兼容相对写法）；日志截断 = `lib/core/network/trace_text.dart` 的 `clipForTrace` / `clipForTrace200`；**统一认证换证「逐跳循环」** = `lib/core/network/cas_walk.dart` 的 `walkCasRedirects<T>` / `CasWalkSpec{maxHops, traceUrlMax, traceLocationMax}` / `CasWalkStep` / `CasWalkOutcome<T>` / 钩子动作 `CasHopGoto`·`CasHopFinish`（返回 `null` = 按 `Location` 继续）/ `casDioSender(dio, {responseType, extraHeaders, refererIsCurrentUrl})` —— **6 条 CAS 链已迁 5 条**（read_credit / cxstar / chaoxing / libsp / tsgxs：循环机制收进 core，站点只留自己的错误文案、跳数上限、取 token 的姿势、网关桥接、JS 跳转兜底；`dzj` 是 1(+1) 跳**无循环**故不迁，口径见 §33.3）；**异常基类** = `lib/core/errors/app_exception.dart` 的 `AppException`（**全仓 35 个具体异常类**的基类，契约 = `message` 是「能直接说给用户听的一句话」+ `toString()` 恒等于 `message`）/ `SessionExpiredException`（**会话失效标记**，9 个成员，界面按类型分支）+ `friendlyErrorText(e)`（**异常 → 上屏文案的唯一出口**，剥掉 `Exception: ` 前缀；此前这个手法在 lib 里手写了 11 处）；**内嵌网页（可带登录态）** = `lib/core/web/web_session.dart` 的 `WebSessionCookie` / `EmbeddedWebRequest`（要写进浏览器 Cookie 罐的凭据 + 要开的页面）+ `lib/core/network/cas_browser_session.dart` 的 `kCasHost` / `kTgcCookieName` / `casTgcCookie(tgc)`（**把统一认证 TGC 交给浏览器的唯一口径**）+ **`lib/core/web/in_app_web_screen.dart` = 全平台唯一内嵌实现**（Android WebView / Windows WebView2，统一走 `flutter_inappwebview`；口径「**Cookie 先写、页面后开**」+ 唯一跳转缝 `webViewScreenBuilderProvider`，⚠ `inAppWebViewSupported` 的 `windows` 2026-10-08 起为 true，Windows 前置 = nuget + WebView2 运行时，见 §40）；`Failure`（`Either` 侧，`lib/core/errors/failures.dart`）与它**刻意并存、不要互相转换**。守卫 = `test/core_conventions_test.dart`（**全仓只有该文件允许 `implements Exception`**，且禁止再手写 `.replaceFirst('Exception: ', '')`；裸 `throw Exception(` **已清零、禁止再出现**（起点 128 处）；`★ 每个 `*Exception` 类的根都是 `AppException`` 是**自维护**守卫 —— 扫全 `lib/` 建「类名 → 超类名」表，断言超类必是 `AppException` 或本仓另一个异常类，新增站点自动受管，不必手抄类名）+ `test/repo_hygiene_test.dart`（生成物入库）+ 异常行为 = `test/app_exception_test.dart`，口径与「哪些重复其实不该统一」见 **§33**（异常体系与迁移台账详见 §33.5）。
- **依赖纪律（2026-09-20 立 · 架构审查 ① 工程卫生）**：`pubspec.yaml` 只保留**真的被 import 的包**。本轮删掉 20 个零引用运行期依赖（`pubspec.lock` 包数 **215 → 158**，连带传递依赖共减 57），**唯一白名单例外 = `json_annotation`**（freezed 注解层：生成的 `*.freezed.dart` 里写着 `@JsonSerializable()`，注解由 `freezed_annotation.dart` 以 `export` 转发；用 `part of` 的 `.g.dart` 不算 import，**纯 import 统计必漏判**）。三个坑：① `http` 的唯一「命中」是 `package:http_parser/…` 的**子串**误匹配（`http_parser` 要留）；② `cupertino_icons` 可删 —— `CupertinoPageTransitionsBuilder` 是 Material 自带类、全仓 `CupertinoIcons.` 命中 0；③ `provider` 的 445 处命中全是 **Riverpod 自己 export 的** `ChangeNotifierProvider`。`ACCESS_NETWORK_STATE` 权限**原样保留**（曾是 `connectivity_plus` 的天然声明方，权限本身仍可能被原生侧用到）。⚠ CRLF 坑：`pubspec.yaml` 是 CRLF，按 `split('\n')` 切行时空行会剩成 `'\r'` → 被当成「块已结束」→ 只解析出 `flutter`。守卫 = `test/repo_hygiene_test.dart`「依赖都被真的 import」3 例（**自维护**：判据是 `^\s*(?:import|export)\s+'package:<名字>/` **指令**而非子串，故 `http_parser` 不会带出 `http`、白名单理由里写包名也不会自证自话；另两例守「白名单不许陈旧」「理由非空壳」）。
  - ⚠ **`.gitignore` 的目录规则必须锚定仓库根（2026-09-27 事故）**：`tools/` 会**在任意深度**匹配 → `lib/features/ai/tools/`（整个 AI 工具层 10 个 `.dart`）被静默忽略、`git ls-files` 为空（本地全绿、全新克隆缺一层源码）。已改 `/tools/`；守卫 = `test/repo_hygiene_test.dart`「★ 源码不被 .gitignore 吞掉」。
- **三态组件（加载 / 空 / 错误）的唯一实现 = `lib/design/app_states.dart`（2026-09-20 立 · 架构审查 ⑤）**：
  `AppLoadingState({message, compact, padding})` / `AppErrorState({required error, title, onRetry, retryLabel, retryKey, icon, compact, retryIcon})` /
  `AppEmptyState({required message, icon, action, compact, padding})` —— 三个都自带 `Center + Padding`，**直接塞进 `AsyncValue.when` 的三个分支**；
  放进列表 / 卡片用 `compact: true`。审计起点：裸 `const Center(child: CircularProgressIndicator())` **33 处 / 26 文件**、`Text('重试')` **39 个文件**。
  - **错误文案的唯一出口 = `friendlyErrorText(e)`**（`AppErrorState` 内部已调）：调用方**不许再写** `Text('加载失败：$e')` —— 那会把 `Exception: ` 英文前缀印给用户（审计实测 2 处，已改）。
  - **重试按钮只在给了 `onRetry` 时才画**（没给 = 只读页，不该出现死按钮）；`retryLabel` 默认 `'重试'`；`retryKey` 给「测试按 key 找按钮」的页面用（如 `Key('dzjSubRetry')`）。
  - **空态文案要说清是「没有」还是「没取到」**（§30 学习通那轮的教训：把「本轮没扫到」说成「没有作业」被用户当场报错）。
  - 守卫 = `test/core_conventions_test.dart`「三态组件」4 例（三个类只在 `lib/design/` 定义 / **裸中心转圈必须为零** / 棘轮 `maxSpinnerCenters = 7`、`maxRetryTexts = 28` **只减不增** / 不许把裸异常印上屏）+ 行为 `test/app_states_test.dart` 10 例。
  **未迁**（有意留下）：卡片内**横排**错误行（`lib/features/library_edu/presentation/tsgxs_home_screen.dart` 的 `_inlineError`）、页面内已有的本地三态助手（`lib/features/read_credit/presentation/read_credit_detail_screen.dart` 的 `_message`）—— 台账见 §33.4.3。
- **页面互推走「跳转缝」`lib/core/navigation/service_nav.dart`（2026-09-20 立 · 架构审查 ⑦ 第二轮）**：只放**注册表 + 三个动作** —— `registerServiceScreen(id, builder)`（**只有组装根 `lib/main.dart` 的 `_installServiceScreens()` 调**）/ `openServiceScreen` / `resetToServiceScreen` / `replaceServiceScreen`；业务代码只喊 id（现 **6 个**：`kServiceHome` / `kServiceMaterials` / `kServiceSettings` / `kServiceIms` / `kServiceComprehensive` / `kServiceDataCenter`）。目的 = 不再让 feature 直接 import 别家**页面**（已收口 4 条反向导航边：`account_screen → HomeScreen`、`zongce_widgets → MaterialsScreen`、`home / ai → 设置页`（改走 `openSettings`）、平台选择器 → 三个落点，feature 依赖环 14 → **9**）。与 `mfaReloginService.setFallback` 同套路：**组装根本来就知道所有模块**。
  - **适用边界（别把它当通用路由器）**：① 只许「**纯导航**」的边进来 —— 判定口径 = 问「这条依赖是数据 / 口径，还是只为了 push 一个页面？」前者不许进 seam（反例：`ai → settings/data/theme_prefs.dart` 是 AI 工具真的改主题，归 C 类同族耦合）；② **已有官方入口的一律优先用官方入口**（设置页 = `lib/design/settings_entry.dart` 的 `openSettings`）；③ id 数量保持极小（现 6 个），扩充要写进 §33.6.1.1；③ **未注册时静默返回**（`openServiceScreen` 返回 false / `resetToServiceScreen` 退化为 `popUntil(isFirst)` / `replaceServiceScreen` 返回 false）—— 单测常只 pump 一个页面、不走组装根，抛异常会把无关用例打红；这也是「真依赖不可能靠静默 no-op 活着」的护栏。
  - 守卫 = `test/core_conventions_test.dart`「跳转缝」1 例（定义唯一 / **该文件不许 import 任何 feature**（用 `_codeHits` 跳注释、且只扫这一个文件）/ 组装根必须注册 6 个 id（⚠ 比较前先压掉空白，注册调用可能折行）/ 已收口的边不得复活：zongce 不得出现材料库页面、`account_screen` 不得出现首页、`platform_selection_screen` 不得出现三个落点页且必须含 `replaceServiceScreen(`、`home_screen` / `ai_chat_screen` 不得出现设置页）+ 行为 `test/service_nav_test.dart` 8 例。
- **巨型页面拆分（2026-09-20 立 · 架构审查 ⑥ · ✅ 五个巨型页全部完成）**：`grades_screen.dart` **1846 → 799 行**（外提 `presentation/widgets/` 的 `grades_summary_card.dart` / `grades_ranking_row.dart` / `grades_table.dart` / `dashed_border.dart`）· `dashboard_panel.dart` **963 → 214 行**（外提 `dashboard_metrics.dart` / `dashboard_today_courses.dart` / `dashboard_common.dart`）· `materials_screen.dart` **1544 → 383 行**（外提 `material_pick_pages.dart` + `widgets/material_edit_dialog.dart`）· `zongce_screen.dart` **2305 → 1166 行**（外提 `zongce_widgets.dart`：**先按「是否碰状态」给 57 个成员分类**，27 个纯渲染件整体搬；随行件三处：`Color get _schemeColor` → `zcSchemeColor(context)`、`static const` 色板/规则表 → 顶层 const、`zcCheck` 补显式 `context` 首参）· `settings_screen.dart` **1983 → 258 行**（外提 `widgets/settings_cards.dart`：**除屏幕本体外的每个顶层类**都改成 `Settings` 前缀公开名）。**合计 8641 → 2820 行（−67%），14 个新文件。**三条口径：① **零件要么收显式参数、要么自己 `ref.watch` 取数**（绝不把 `State` / `WidgetRef` 之外的整块状态透传进去，那只是换了文件名的巨型方法）；② **公开静态量与布局常量留在原类上**（测试有运行时引用 + 源码断言钉着位置），需要时新文件反过来 import 原文件（**Dart 允许互相 import**，在文件头注明原因）；③ **方法体内的局部函数**（`_statCard` / `_wideCard` 这类）随方法体自动搬走，**不要**单独提取。⚠ **迁移脚本的安全阀（都踩过）**：表达式体（`=> …`）的结束位置必须按**深度 0 的分号**扫 —— 用「找最近的 `{` 再配平」会算到下一个成员、**跨度重叠 → 按原文偏移逐个删除时逐次错位，连带吞掉无辜代码**；脚本必须带**「跨度两两不许重叠」断言**，且**删块要排在改写调用点之前**（改写会让偏移漂移）。源码守卫跟着改成**读同一族文件的并集**（`theme_dark_test.dart` / `home_dashboard_layout_test.dart` / `volunteer_activity_time_test.dart` 三处已改）。台账与剩余清单见 §33.4.4。
- **`data_center_screen.dart` 拆分（2026-10-08 · 巨型页第六例 · ✅）**：**1413 → 122 行**壳 + `presentation/widgets/` 三件（`data_center_common` 177 / `data_center_overview_cards` 735 / `data_center_social_cards` 385），顶层函数统一 `dc` 前缀 —— 它是 `ConsumerWidget`、49 个成员**零 `setState`**，纯机械外提即行为零变化。随行件：`_extraRowsShown`（唯一用户是被搬走的件，已 grep 零引用）搬成顶层 `dcExtraRowsShown`；`_fmt` 的 `static` 必须去掉；`slot` 留在屏幕。⚠ **三坑**：① 抽取要**先跳过参数表括号再找函数体**，否则带 `{required …}` 的成员会在参数块处被截断（`_rosterCard` 只取到 32 行、实际 97 行）；② 搬走必须改公开名，并断言「旧私有名彻底消失」；③ `test/dzj_overview_flow_test.dart` 的源码守卫已改成**读整族文件并集**（`dataCenterFamilySource()`），别再退回单文件断言。守卫 190 例全绿 + `analyze` 零问题。
- **设计口径三件（2026-09-20 立 · 架构审查 ⑤-B；都在 `lib/design/`，页面里不要再拼一套）**：
  - **节标题** = `lib/design/section_title.dart` 的 `appSectionTitle(context, {required text, trailing, accent})`。审计起点：**8 个 feature 各写一份** `_sectionTitle`/`_sectionLabel`/`_buildSectionTitle`，另有 6 处漂移（高度 14/15、间距 8、字号 12.5、少 `letterSpacing`）→ 全部归一（用户 2026-09-20 裁定「全部归一 + 更新 golden」）；**只有两处「竖条 + 图标 + 文案」的分组头有意保留**（`school_calendar_screen.dart` / `site_nav_screen.dart`，并进去会丢图标），已进守卫白名单。
  - **卡片形状** = `lib/design/app_card.dart` 的 `kAppCardRadius` / `appCardBorderSide` / `appCardShape(context)` / `appCardTheme`。与它**逐像素等价**的手拼形状**共 17 处已清零**（13 处 `BoxDecoration` → `ShapeDecoration(shape: appCardShape(context), color: X)`；4 处 `Card(shape: RoundedRectangleBorder(...))` → `shape: appCardShape(context)`）；**着色卡（`AppColors.tintBorder`）不属于这一类，照旧手写**。
  - **响应式断点** = `lib/design/breakpoints.dart` 的 `Breakpoints.narrow`(600) / `tight`(400) / `wide`(720) / `extraWide`(1000) —— 不许再拿 `constraints.maxWidth` 直接与三位数字面量比大小（原来 9 处各写各的，看不出是不是同一个约定）。
  - 守卫 = `test/core_conventions_test.dart`「⑤-B 设计口径」4 例（节标题唯一 / 手写竖条白名单 / 手拼卡片清零 / 断点零字面量）。
- **色彩**：一律登记在 `lib/design/` —— **功能入口色**（宫格/侧栏/卡片图标）走 `lib/design/feature_palette.dart`（如 `scoreEstimate = Color(0xFF536DFE)`）；**状态 / 等级 / 标签 / 品牌 / 一次性视觉值**走 `lib/design/status_palette.dart` 的 `StatusPalette`（品牌与状态）/ `ZongceTone`（五育 + 综测等级）/ `TiceTone` / `MaterialsTone` / `ReadCreditTone` / `PlatformEntryTone`（2026-09-20 起；此前 `features/**` 里散着 72 处字面量）。**页面里不许再写 `Color(0x…)`**：守卫 = `test/core_conventions_test.dart`「设计色值唯一口径」（唯一白名单 = 课程色板 `schedule_tone.dart`，逐值经 ΔE 挑选、与功能色撞值属巧合）。
- **主题「纯白」口径（2026-09-14 立）**：`lib/main.dart` 的 `ColorScheme.fromSeed(seedColor: 校红 #C3282E)` 会按种子色相派生**整个中性色系** → 白色实际是 `#FFF8F7`（R−B = +8，1920×1080 截图像素实测），整页「白里透红」。已在 `.copyWith()` 里把白色系覆写为中性灰白（R = G = B）：`surface` / `surfaceContainerLowest` = `#FFFFFF`、`surfaceContainerLow` = `#FAFAFA`、`surfaceContainer` = `#F5F5F5`、`surfaceContainerHigh` = `#F0F0F0`、`surfaceContainerHighest` = `#EBEBEB`；**`surfaceTint` 必须设白**（它默认取 primary 系，AppBar / Card 抬起时会再染一层红）。新增任何「白色」都用中性色值，**不要**从 primary 派生；文字色（`onSurface` / `onSurfaceVariant` / `outline`）仍是种子的暖灰 —— 这是用户 2026-09-14 裁定「只改白色系」的结果，别顺手改。
- **首页服务目录（2026-09-15 重构）**：唯一条目表 = `lib/features/home/presentation/home_service_catalog.dart` 的 `homeServiceEntries({required void Function(Widget) push})` → `List<HomeServiceEntry{icon, title, subtitle, group, accent, onTap}>`，**强调色随条目走**；宫格渲染 = `presentation/home_service_grid.dart`、左侧导航栏渲染 = `presentation/home_sidebar.dart`，两者共用这一份。分组 = `HomeServiceGroup{ims '教务系统', study '学习与测评', campus '校园生活', info '数据与信息', fillForm '评优评先'}`（**只影响侧栏排版**，宫格平铺不分节）。
  ⚠ **旧铁律已作废**：从前条目写在 `home_screen.dart` 的私有 `_items(context)`、强调色存在顶层 `const _tileColors`，两者**按索引对齐**（增删磁贴必须同步增删色表）。现在只有一份目录、颜色随条目，**不可能再错位**；增删入口只动 catalog 一处，并同步 `test/home_tile_alignment_test.dart` 的条目数（现 **32** 条 —— 依次为 2026-09-19 的「AI 助手」（**第一格**）、2026-10-07 的「填表助手」（**第 2 格**，从材料库独立出来、自成 `fillForm` 一组）、2026-10-08 的「智慧江财」（**排在四枚教务磁贴之后**，带登录态内嵌网页）、「学习通」、「AA 算账」、「找空闲教室」、「网站导航」，逐条历史见该测试里的注释）与本文件。详见 §17、§32、§38。
- **UI 风格基准 = 首页宫格页**：功能卡 `Card(elevation: 0, shape: appCardShape(context))` + `Clip.antiAlias`；节标题用 `appSectionTitle`（`lib/design/section_title.dart`；3px 竖条 + 13.5 w600 + `letterSpacing 0.3`，`accent` 默认主题红）—— **兼容别名 `geCardTitle` 仍在 `lib/features/score_estimate/presentation/ge_common.dart`，但它只是转发**，新代码用 `appSectionTitle`；列表 `padding: EdgeInsets.fromLTRB(24, …, 24, 48~96)`；卡间 12；图标 22–24 用 **Material Icons**（不用 emoji）。共享件在 `lib/features/score_estimate/presentation/ge_common.dart`（`geCardShape`——已转发到 `appCardShape` / `geCardTitle` / `geFmt` / `GeModeBadge`）；**卡片形状与强调色的唯一口径 = `lib/design/app_card.dart`（见 §16）**，别在页面里再拼一套 `BorderRadius.circular(…)` + `BorderSide(…)`。
  - **例外 = 两张 Fluent 页（毕业学分 §13.2 / 培养方案 §13.9）+ 校历页的「学年时间线」（§36.3.2）**：整页走 `lib/design/fluent/` 那套（`FluentPageBackground` / `FluentCard` / `FluentSectionHeader` / `FluentListRow` / `FluentMetricCard` …），取色一律 `fluent(context)`；**不要**往这两页里混 `appCardShape` / `appSectionTitle` 家法，也**不要**把 Fluent 件反向铺到别的页面（那是「单页重做 + 抽一套基础件」的 2026-09-11 裁定，见 §13 开头）。⚠ **2026-10-09 收窄解释（第 3 个采用点）**：校历页那根「**一根单轴时间线**」（用户当天指定「直接用 /fluent-design 设计一根单轴时间线」）**只取 `fluent(context)` 调色板 + `FluentType` 字号档 + 4px 栅格 / 4px 圆角 / 无阴影这套语法**，**不引入 `FluentCard` 等 Fluent 表面件**（卡片外壳仍是本页的 `_WhiteCard`）—— 所以「不反向铺」这条红线仍然成立，判据 = 有没有把 Fluent 的**表面件**搬出那两页。`lib/shared/widgets/reorderable_table/` 那套自研表格 2026-10-09 起**无调用方**（培养方案页已改 Fluent 分组清单），按用户口径「先不用」保留本体。
- **区域级「卡片形态」= `lib/design/card_frame.dart`（2026-10-09 立 · 侧栏视图 · 详见 §44）**：`CardFrame(card: …, child: …)` + `kCardFrameRadius`（= `kAppCardRadius`）+ `kCardFrameShadowsLight·Dark`（**两层**）。⚠ 与 `app_card.dart` 分工**别合并**：那是「页面里的一张卡」、**不画阴影**；本件是「把一块**区域**（侧栏 / 内容面板）框成卡片」、**带阴影**（用户要求）。两条实测硬约束：① 阴影**不能**照搬 vshell 的 `shadow-lg`（`alpha .14 + blur 12`）—— Flutter 里逐像素测不到（见 §44.2②）；② 两张圆角卡之间**不能只有 1px**（会看成一张卡，见 §44.2③）。四档口径 = `features/home/domain/home_card_style.dart`，开关在设置页「主页布局」卡的「卡片样式」一节，默认「都不显示」（= 改造前逐像素）。**间距口径 = `features/home/domain/home_card_gap.dart`（三轮起可调 · 十七轮改口径）**：卡片↔卡片 = **a**（十七轮前是 **2a**）、卡片↔窗口左/右/底边 = **a**、顶边贴标题栏恒 **0**；`a` 默认 **8**（十七轮前是 6）、范围 2~24、落盘 `homePrefs` 的 `homeCardGap`。⚠ **留白逐边按卡片给**（七轮 · 用户否掉了「整块主体统一缩一圈」，一侧不是卡片时那一侧必须贴到窗口边、顶边不许留缝，§44.1.2）；**侧栏可收起**：状态 = 页面 State 的 `_sidebarCollapsed`（不进 Hive），**收起 = 同一条侧栏变窄到 40 宽（图标照旧、文本不画、高亮照旧）且宽度是补间的**（十一 / 十二轮；**十八轮起收起后仍是卡片**，§44.1.12）；**侧栏选中态 = 圆角胶囊高亮**（十轮）；**侧栏不画滚动条、也不画分割线**（十三轮）；**间距与圆角都可调**（步长都是 1；圆角 0~28、**默认 8 = 毕业学分页那套 `FluentCard` 的圆角**，十四~十六轮；圆角口径在 `features/home/domain/home_card_radius.dart`，**只作用于这两张区域卡片**）。⚠ 改这类默认值**只改常量、不许写迁移**（迁移要在 `_load` 里写盘，而本仓 Hive + 假异步测试环境会因此把每个建 store 的用例挂到超时，§44.1.10）。
  ⚠ 该区域有**跨轮次的坑**（都踩过）：① 卡片层与侧栏**两种形态必须是同一个组件类型、且不许挂随形态变的 Key**，否则子树重挂（内嵌设置页滚动位置归零，§44.4 ②）；② **动画期间行的内容要按"本行此刻多宽"决定**、不能按布尔（否则补间中间帧 `RenderFlex overflowed`）；③ **卡片层必须在换页动画外面**、**概览自己也得是面板的一条路由**（`HomeDetailPane` + 缝 id `kServiceOverview`，否则点开会盖住窗口，§44.1.18）；④ **右栏那格 `PaneScope` 要带 `sidebarPane: true`**，否则压上来的那层会凭空多出导航栏 + 返回键（§44.1.19）。
- 图标按钮用 `IconButton(tooltip: …)`；`AlertDialog` 用 M3 默认样式 + `icon:`。
- **交互必须触摸可用**：手势**不得只挂在 `MouseRegion` hover 开关上**——触摸设备永不产生 hover，被 hover 门控的手势等于没注册（`lib/shared/widgets/academic_year_picker.dart` 曾因此在手机上整条划不动，且同一开关还控制着透明度）。拖拽一律用真实指针事件（`onHorizontalDragStart/Update/End/Cancel`）驱动状态，hover 只做增强。
- **全局偏好入口 = `lib/features/settings/presentation/settings_screen.dart`**（首页右上角齿轮进入）。新增用户偏好一律收拢到这里，不要再新增 feature-local 设置弹层（校历的三个显示开关已于 2026-09-11 迁入本页「校历」节，校历页 AppBar 齿轮只做跳转）。持久化照 `lib/features/campus_address/data/my_campus_prefs.dart`：Hive `Box<String>` 单 key + `ChangeNotifier` + `ChangeNotifierProvider`（改动需即时反映到多个页面时用此模式，**别用 FutureProvider**——中间有异步空窗，页面会先闪一次旧值）。
  - 已收拢的偏好（新增偏好照此追加，别另开弹层）：**入馆教育答题模式** = `lib/features/library_edu/data/tsgxs_prefs.dart`（box `tsgxsPrefs` / key `answerMode`，存 `TsgxsAnswerMode.name`），**唯一切换入口 = 设置页「入馆教育」节**；`tsgxs_exam_screen.dart` 与 `tsgxs_chapter_screen.dart` 只读该偏好（用户 2026-09-11 裁定：「模式的切换不应该显示在任何页面，只能显示在设置页」）——别再往页面里加模式切换控件或 `initialMode` 参数。
  - **标题栏右上角永远有设置按钮（用户 2026-09-16 裁定）**：唯一入口 = `lib/design/settings_entry.dart` 的 `SettingsActionButton`（2026-09-20 从 `features/settings/presentation/` 搬到 `lib/design/` —— 它是 chrome 契约，被 10 个 feature 当参数用）（紧凑款：`iconSize 18` + `visualDensity compact` + `constraints 30×30` → 实测点击区宽 **40**，与课表 `ScheduleTitleBar.actionWidth` 同口径），**由 `lib/design/pane_chrome.dart` 的 `paneAppBar` 自动追加到 `actions` 末尾** —— 所以走 `paneAppBar` 的服务页（宫格/侧栏能直达的那 20 多个）都自动有，新页面不必自己加。二级页（畅想之星阅读器 / 入馆教育答题页 / 课程详情）用裸 `AppBar`，**没有**设置按钮（用户拍板「所有服务主页、二级页不加」）。
    - **只显示本节**：页面用 `paneAppBar(context, …, settingsSections: [SettingsSection.calendar])` 声明；枚举 = `lib/design/settings_section.dart` 的 `SettingsSection`（2026-09-20 同上搬家）（**appearance 外观（深色模式，2026-09-16 加，见 §22）** / **aiAssistant AI 助手（2026-09-19 加，排在 appearance 之后，见「内置 AI 助手」节）** / campus 校区 / scope 生效范围 / homeLayout 主页布局 / calendar 校历 / **schedule 课表** / libraryEdu 入馆教育 / platformGuid 平台标识 / liveClass 上课实况窗 / imsSession 教务会话 / publicQuery 公共查询 / **cloudSync 云同步** / homeWidget 桌面小组件 —— 共 **14** 个，顺序即完整设置页的分节顺序），`SettingsScreen(sections: […])` 按它过滤分节（`sections.length == 1` 时 AppBar 标题变成节名）。**空列表 = 完整设置页**（主页、以及没有对应节的页面：综测 / 材料库 / 体测 / 邮箱 / 规章制度 / 志愿者 / 竞赛 / 第二课堂 / 电费）。
    - 已声明映射：校历→calendar；蛟湖阅读→libraryEdu；校园网 + 请假 + 数据中台→platformGuid；选课 / 公共查询 / 分数估计 / IMS 容器（培养方案·成绩·毕业学分·我的）→imsSession；课表→imsSession + liveClass；学校地址 + 校区地图→campus。
    - ⚠ **课表页的行宽记账要 +1**：`schedule_screen.dart` 里 `final barActionCount = actions.length + 1;`（设置按钮由 chrome 追加），少算一个会把标题栏可用宽度多算 40px、该换行时不换行。
    - 守卫 = `test/settings_entry_test.dart`（九节 label；只给一节/多节/不传三档渲染与标题；点按钮进过滤页；源码守卫：chrome 自动注入 + 12 个页面的 `settingsSections` 映射 + 课表 `+1` + 校历页不再自带 `_settingsAction`）。
    - ⚠ **齿轮注入 = 两处（2026-09-17 修订；此前只允许 `paneAppBar` 一处）**：① `paneAppBar`（整页模式，无条件追加到 `actions` 末尾）；② `PaneActionRow`（侧栏内嵌模式，**仅当页面声明了 `settingsSections` 且本行本来就有内容**时在行尾补一个）。用户 2026-09-16 二轮原话「你的设置添加导致不少页面凭空多了一个标题栏，我希望下沉到内容里」→ 红线保留为「**空行不许塞齿轮**」：注入必须排在那道 `actions.isEmpty && leading == null` 早退**之后**，`PaneActionRow` 在空行时仍**整行不画**。用户 2026-09-17「课表页的设置按钮不见了」：内嵌模式不画导航栏、而齿轮从前只由 `paneAppBar` 注入 → 课表页的入口整个消失；现由课表页（**唯一**给 `PaneBody` 传 `settingsSections` 的页面）在**既有**工具条行尾补一个，不新增任何横条。清单唯一出处 = `lib/features/ims/schedule/presentation/schedule_screen.dart` 的 `const List<SettingsSection> scheduleSettingsSections`（整页导航栏与内嵌工具条共用，行宽记账 `barActionCount = actions.length + 1` 两档都恰好 +1）。守卫 = `test/pane_chrome_test.dart`（内嵌有/无声明、空行零尺寸、整页不重复渲染）+ `test/settings_entry_test.dart`（注入恰好两处 + 课表两条链路都挂上了）。**桌面端设置入口改到左侧导航栏底部固定区**（用户同日：「桌面端把标题栏里的头像和设置都应该改到侧边导航栏，设置在下，头像在上，并且这两个是固定在底部不浮动的」）：`home_sidebar.dart` 的 `HomeSidebar(footer:)` + `HomeSidebarFooterRow`（`homeSidebarProfileKey` 头像行在上 / `homeSidebarSettingsKey` 设置行在下，行高 `footerRowHeight`=46），由 `home_screen.dart` 的 `_buildSidebarBody` 装配（`AccountAvatar(radius: 15)` → 我的；齿轮 → 设置）—— ⚠ **2026-10-09 五轮起这两行是在右栏内嵌显示**（不再 push 子页面：`_selectFooter` + 跳转缝 `serviceScreenBuilder(kServiceSettings / kServiceStudentInfo)` + `HomeDetailPane`，两页的导航栏都改走 `paneAppBar`），见 §19.6；**该区在滚动区之外 → 服务列表再长也压不到它**；顶栏在侧栏视图下只留品牌 —— ⚠ **2026-10-09 起首页已没有自己的顶栏**（品牌 + 三键并入全局窗口标题栏，宫格视图的设置/头像改经「标题栏动作插槽」发布，侧栏视图不发布；详见 §43）。守卫 = `test/home_sidebar_test.dart`「底部固定区」组（顺序/行高/滚不动/回调/未传 footer 不画）+ 源码守卫（`_buildTopBar` 已删、`_queueTitleBarActions` 在、侧栏/二级页不发布）、`test/pane_chrome_test.dart`（下沉行不得注入 + 空行零尺寸 + 校历页已从「带按钮页」表移除）。

- **Dio 引导的唯一入口（2026-10-08 立 · 架构审计第二轮）**：`lib/core/network/dio_factory.dart` 的 `createAppDio({baseUrl, userAgent, headers, connectTimeout = 12s, receiveTimeout = 20s, sendTimeout, followRedirects = true, validateStatus = acceptAnyStatus, responseType, responseDecoder})`，外加三个同族件 `acceptAnyStatus`（任何状态码都算成功）/ `rejectNon2xxStatus`（Dio 自己的 2xx 判据，给要严格语义的站点）/ `extractCharset` + `gbkAwareResponseDecoder({allowMalformed})`（GBK 解码器原本在 **ims / 校历 / 桌面小组件抄了三份**，连 charset 正则都各写一遍）。收敛起点 = **23 处手写 `Dio(BaseOptions(...))`**（其中 12 处近乎逐字相同：6 处 15s/30s + 6 处 12s/20s）。**默认值取「校园站点抓取」这一族的多数派，少数派一律显式传参**（例：微信登录传 `validateStatus: rejectNon2xxStatus` 保持「非 2xx 抛 `DioException`」；tice 传 `responseType: ResponseType.bytes` + 自己的 4xx 判据；home_widget 的后台 isolate 传 `gbkAwareResponseDecoder(allowMalformed: true)`）。⚠ 顺手修掉一个真 bug：**`charset="gbk"` 带引号时原先会落进 UTF-8 分支 → 满屏乱码**（三份旧实现都这样）。**唯一例外不套工厂 = AI 客户端**（`features/ai/data/ai_providers.dart`：无 baseUrl、`sendTimeout` 60s、`receiveTimeout` 5min、语义相反，套工厂要传 5 个覆盖参数）。守卫 = `test/dio_factory_test.dart` **15 例**（默认值 / 覆盖 / GBK 与带引号 charset / `allowMalformed` 两档 / **源码守卫：除白名单外 `lib/` 下不许再出现 `BaseOptions(`**，判据取 `BaseOptions(` 而非 `Dio(` —— 两者之间可能夹注释 + 白名单每条必须写理由、且不许陈旧）。

- **桌面窗口标题栏 = 全局一条自绘栏（2026-10-09 立 · Windows 专属 · 详见 §43）**：系统标题栏已隐藏、**系统原生边框保留**（`WM_NCCALCSIZE`：顶部不留，左/右/底各收一圈真非客户区 → DWM 画边框/圆角/阴影、缩放热区归系统；`WM_NCACTIVATE` 回 1；最大化按显示器工作区扩回 —— 口径照 `window_manager` 0.4.3 的 `TitleBarStyle.hidden`，即用户另一个项目 vshell 用的那套），顶部那条栏由 `lib/design/window_title_bar.dart` 画（左品牌 = logo + 「智慧er江财」，右三键 = 最小化/最大化/关闭，图标 = **codicon 子集字体**，用户 2026-10-09 指定「照 vshell」），**命中测试交回系统**（`HTCAPTION`/`HTMINBUTTON`/`HTMAXBUTTON`/`HTCLOSE`）→ 拖动、双击最大化/还原、右键系统菜单、Aero 贴靠、**Win11 贴靠布局**全是原生行为（⚠ `WM_NCHITTEST` 对**边框圈**必须回「不归我判」交回默认处理；回 `HTCLIENT` 会让整个边框拖不动 —— 实测踩过）。它挂在 `MaterialApp.builder` 上（**在 Navigator 之上**，且自带 `Material` + `Overlay`，缺一个首帧就抛 → runner 永远不 `ShowWindow`）→ 页面里 `Navigator.of(context)` 拿不到路由，标题栏内的动作一律用页面自己的 context + `mounted` 守卫。两项偏好在设置页「外观」节（`windowBarPrefs` box：三键风格 win/mac + logo/三键左右互换），**切换是动画的**（280ms：换位置 = 两组反向对滑；换风格 = 46 的方键「收成」20 的圆点，同一份 t 驱动两层交叉淡入淡出；mac 在左侧时三枚用 `AnimatedPositioned` 让位）。⚠ 由此有一条**通用坑**：`AnimatedAlign`/`AnimatedContainer`/`AnimatedPositioned` 只驱动 RenderObject、**不重建 State** —— 几何上报若只挂在 `build` 里，动画期间原生拿的还是旧矩形（按钮滑走了但点在旧位置才响应）。所以 `_TitleBarRegion` 在 `paint` 里发现矩形变化就回调一次 `_queueLayoutSync()` 补上报（守卫：「动画期间几何变了就必须重新上报」）。mac 风格三键**不贴边**：整组外侧留白 = 圆点距栏上下边的留白（`kWindowTitleBarMacClusterInset`，14 − 槽内 4 = 10；Win 风格照旧贴边）。**标题栏底部不再画分隔线**（用户 2026-10-09 六轮：「标题栏底部不要显示那根框线，从而让标题栏可以和侧边栏视觉上连续」——顶栏色与侧栏底色同值，深色都是 `#1A1A1A`）；撤线后栏内可画高度 = 整 40，`kWindowTitleBarContentHeight` 跟着改成不减 1。守卫 = `test/window_title_bar_test.dart` **32 例**（偏好 / 几何 / 视觉 / 平台门槛 / 握手 / codicon 契约 / 切换动画 / 整组留白 / 跨语言契约）。
  - ⚠ **`windows/runner/*.cpp` 是 UTF-8 中文注释**：`windows/runner/CMakeLists.txt` 里已加 `/utf-8`（本工程带 `/WX`，不加的话 MSVC 按 GBK 读源码 → C4819/续行符直接把编译打断）。**新加 C++ 文件不用再加，但别把这条选项删掉。**

### 3.1 ⚠️ AlertDialog 里禁止放 ListView / GridView / CustomScrollView

`AlertDialog` 恒用 `IntrinsicWidth` 包裹内容，viewport 类组件不支持 intrinsic 尺寸：

```
RenderViewport does not support returning intrinsic dimensions.
Failed assertion: '!semantics.parentDataDirty': is not true.   ← 随后每帧刷屏
```

表现为弹窗永不渲染 → `await showDialog` 永不返回 → 调用方 loading 标志永远为 true（曾导致「从课表导入」**一直转圈**，误判成网络问题）。
**替代**：`AlertDialog(scrollable: true, content: Column(children: [ for (...) ListTile(dense: true, contentPadding: EdgeInsets.zero, …) ])))`，行直接展开，超出交给外层滚动。

### 3.2 提交前隐私闸门（公开仓库，必做 · 2026-09-22 立）

仓库是 **public**（`https://github.com/Mxster-dll/smarter_jxufe.git`），2026-09-21 已做过一轮全历史脱敏改写（299 提交）。
**提交前**（不是发版前）走三步，细则与成因见 **§34 提交前隐私纪律**：

1. **跑守卫测试**（~30 秒）：`& $dart $snap test test\privacy_guard_test.dart` —— **红了不许提交**（判据与维护见 §34.5；跑前先停运行中的 `flutter run`，否则争构建目录会挂死）。
2. **眼睛过一遍本次范围**：`git status --porcelain` + `git diff --cached --stat`。`app_data/`、`*.hive`、真机抓包（`*.mitm` / `*.flows` / `captures/`）、`key.properties`、`*.jks`、含明文的扫描/脱敏脚本 **一律不许入库**（清单 §34.3）。
3. **写入新值一律用合成值**：姓名 `同学甲` / `同学乙`…、学号 `2202500001…`、学籍号 `201600000000…`、身份证 `110101200001010010`、手机 `13800000001…`、地址「江西省南昌市示例区示例路1号示例小区1栋101室」、口令 `Test123456`、票据 `<REDACTED>`（完整映射 §34.4）。
   ⚠ **最容易犯的一条 = 把真机抓包整段粘成 fixture** —— 那是 2026-09-21 泄漏的**唯一入口**（`test/network_service_data_test.dart` 的 `const String _dashboardHtml`、`test/my_mail_test.dart` 的回包）；另外**改测试输入要重算派生期望**（DES 对拍值按学号算），掩码 / 截断字面量（`110****0010`、`01234567`）要跟着换。
4. **钩子**：`.githooks/pre-commit`（已入库）自动做「文件名检查 + 跑守卫测试」。**新克隆先启用一次**：`git config core.hooksPath .githooks`。逃生口 = `SKIP_PRIVACY_GUARD=1 git commit …`（只跳守卫测试）/ `git commit --no-verify`（全跳）。
5. **真泄漏了先改口令**，再做工作树脱敏补丁 →（必要时）`git filter-repo` 重写全部历史 + 强推；⚠ GitHub 会保留不可达对象（旧 SHA 仍可取到内容），**彻底清除只有「删除并重建同名仓库」一条路**（止血顺序与四个坑见 §34.7）。

## 分册索引（§4–§41 正身在这里）

| 节 | 标题 | 位置 |
|---|---|---|
| §1 | 本机 Flutter/Dart 命令（重要：`flutter.bat` / `dart.bat` 会卡死） | **本文件（常驻纪律）** |
| §2 | VM Service 探针（不靠 UI 就能验证真实数据路径） | **本文件（常驻纪律）** |
| §3 | 代码约定 | **本文件（常驻纪律）** |
| §4 | 分数估计模块 · 计分与加权口径（领域约定，改动前先看这里） | `docs/agents/04-分数估计模块···计分与加权口径（领域约定，改动前先看这里）.md` |
| §5 | 教务数据来源速查 | `docs/agents/05-教务数据来源速查.md` |
| §6 | 工作区状态 | `docs/agents/06-工作区状态.md` |
| §7 | 校区口径速查（三套命名，勿混用） | `docs/agents/07-校区口径速查（三套命名，勿混用）.md` |
| §8 | 校历「假 / 班」角标口径（改动前必读） | `docs/agents/08-校历「假·班」角标口径（改动前必读）.md` |
| §9 | 「当下学期」唯一口径（课表 / 首页今日课程 / 体测 / 校历共用） | `docs/agents/09-「当下学期」唯一口径（课表·首页今日课程·体测·校历共用）.md` |
| §10 | 桌面小组件（Android）与「装包前必做」纪律 | `docs/agents/10-桌面小组件（Android）与「装包前必做」纪律.md` |
| §11 | 首页顶栏与账号头像口径（2026-09-11 立） | `docs/agents/11-首页顶栏与账号头像口径.md` |
| §12 | IMS 全局会话口径（成绩 / 课表 / 毕业学分 / 培养方案 / 我的 共用 · 2026-09-11 立） | `docs/agents/12-IMS·全局会话口径.md` |
| §13 | Fluent Design（WinUI 3）基础层（2026-09-11 立 · 已采用页 = 毕业学分 §13.2 / 培养方案 §13.9） | `docs/agents/13-Fluent·Design（WinUI·3）基础层.md` |
| §14 | 教务「公共查询」口径（教师 / 班级 / 教室 / 课程课表 + 多班对照找无课时间 · 2026-09-14 立） | `docs/agents/14-教务「公共查询」口径.md` |
| §15 | 教务「选课」口径（网上选课 / 选课结果 / 退选 · 2026-09-14 立） | `docs/agents/15-教务「选课」口径.md` |
| §16 | 卡片风格唯一口径（全应用统一 · 2026-09-15 立） | `docs/agents/16-卡片风格唯一口径.md` |
| §17 | 主页布局 / 宫格排版 / 应用名（2026-09-15 立） | `docs/agents/17-主页布局·宫格排版·应用名.md` |
| §18 | 页面转场唯一口径（2026-09-16 立） | `docs/agents/18-页面转场唯一口径.md` |
| §19 | 侧栏视图的页面 chrome 口径（2026-09-16 立） | `docs/agents/19-侧栏视图的页面·chrome·口径.md` |
| §20 | 学科竞赛（第二课堂 · 申请与公示，2026-09-16 加） | `docs/agents/20-学科竞赛.md` |
| §21 | 小程序三个服务的落地（2026-09-16 · 用户原话：「本科生成绩单实现到现有的成绩页」「还有一个网络服务，整合到现有网费功… | `docs/agents/21-小程序三个服务的落地.md` |
| §22 | 深色模式（2026-09-16 立 · 用户原话：「给应用适配深色模式」） | `docs/agents/22-深色模式.md` |
| §23 | 云同步（用图书馆「我的订阅」当云端存储面 · 2026-09-17 立） | `docs/agents/23-云同步.md` |
| §24 | 材料库「添加材料」向导 + 通用三宫格日期选择器（2026-09-17 立） | `docs/agents/24-材料库「添加材料」向导·+·通用三宫格日期选择器.md` |
| §25 | 浮层定位（RuleTip）（2026-09-17 立） | `docs/agents/25-浮层定位（RuleTip）.md` |
| §26 | 推免成绩 / 竞赛奖励（2026-09-17 加 · 资料库运行时解析） | `docs/agents/26-推免成绩·竞赛奖励.md` |
| §27 | 学科竞赛目录的搜索/识别 + 智育四小项（2026-09-18 立） | `docs/agents/27-学科竞赛目录的搜索·识别·+·智育四小项.md` |
| §28 | 材料库 → 推免加分项 / 竞赛奖励获奖记录「自动带入」（2026-09-18 立 · 用户原话：「我希望推免和竞赛奖励的加分项… | `docs/agents/28-材料库·→·推免加分项·竞赛奖励获奖记录「自动带入」.md` |
| §29 | 内置 AI 助手（2026-09-19 立 · 用户原话：「我们希望增加一个功能，那就是AI融入项目的底层。我们希望添加一个内置… | `docs/agents/29-内置·AI·助手（2026-09-19·立···用户原话：「我们希望增加一个功能，那就是AI融入项目的底层。我们希望添加.md` |
| §30 | 学习通（超星）只读接入（2026-09-19 立 · 用户原话：「我发现了一个接入学习通内容的方法，原智慧江财网页里有一项叫"网… | `docs/agents/30-学习通（超星）只读接入.md` |
| §31 | 公共查询工具化（找空闲教室独立 / 找空教室默认值 · 节次多选 / 分楼层，2026-09-19 一·二轮） | `docs/agents/31-公共查询工具化.md` |
| §32 | 网站导航（全校站点目录 + 星标收藏 · 2026-09-19 立） | `docs/agents/32-网站导航.md` |
| §33 | 横向地基件（跨模块唯一实现）（2026-09-20 立 · 架构审查后收敛） | `docs/agents/33-横向地基件（跨模块唯一实现）.md` |
| §34 | 提交前隐私纪律（公开仓库）（2026-09-22 立 · §3.2 的细则） | `docs/agents/34-提交前隐私纪律（公开仓库）.md` |
| §35 | 上课提醒（课前常驻通知）（2026-09-22 立 · 上课前 X 分钟起、上课时自动消失） | `docs/agents/35-上课提醒（课前常驻通知）.md` |
| §36 | 学校时间轴：学年 / 学期 / 假期的唯一出处（2026-09-27 立 · 学年 = 第一学期第一天 ~ 下学年第一天前一天，取不到留 null） | `docs/agents/36-学校时间轴·学年·学期·假期的唯一出处.md` |
| §37 | 最近更新存档（2026-09-27 及更早）（2026-10-06 拆册 · 根文件 65536 字节指令预算，超了任何 agent 都读不到） | `docs/agents/37-最近更新存档（2026-09-27 及更早）.md` |
| §38 | 填表助手（上传 docx → 自动识别待填项 → 自动填 → 手动改 → 导出）（2026-10-07 立） | `docs/agents/38-填表助手（上传 docx 自动填）.md` |
| §39 | 课表响应校历事件（假期不排课 · 补课日换课 · 显示范围）（2026-10-08 立） | `docs/agents/39-课表响应校历事件（假期不排课·补课日换课·显示范围）.md` |
| §40 | 智慧江财（ehall）内嵌网页 · 复用统一认证登录态（2026-10-08 立 · 内嵌实现换 `flutter_inappwebview` · Windows 前置 = nuget + WebView2） | `docs/agents/40-智慧江财（ehall）内嵌网页·复用统一认证登录态.md` |
| §41 | 校区矢量地图（四校区 · OSM 裁剪 + Flutter 原生绘制 · 浅色/深色两风格 · 2026-10-08 立） | `docs/agents/41-校区矢量地图.md` |
| §42 | 开屏流光（加载页主视觉 = 图书馆插画 + 流动光效 · 2026-10-08 立） | `docs/agents/42-开屏流光（加载页主视觉）.md` |
| §43 | 桌面窗口标题栏（隐藏系统标题栏 · 自绘三键 · 拖动/贴靠/缩放 · 2026-10-09 立） | `docs/agents/43-桌面窗口标题栏（隐藏系统标题栏·自绘三键·贴靠）.md` |
| §44 | 侧栏视图的「卡片形态」（侧栏 / 内容区各自可开 · 要阴影 · 2026-10-09 立） | `docs/agents/44-侧栏视图的卡片形态（侧栏·内容区各自可开）.md` |
| §45 | 全局路由历史（顶部前进 / 后退 · 2026-10-09 立） | `docs/agents/45-全局路由历史（顶部前进·后退）.md` |






