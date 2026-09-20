<!-- 本册 = AGENTS.md §10 的正文（节号与标题原样保留，勿重编号）。根文件：../../AGENTS.md -->

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

- adb：`%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe`（**不在 PATH**）；安装 `adb -s <serial> install -r -t build\app\outputs\flutter-apk\app-debug.apk`。
- 强跑后台刷新（测试钩子）：`adb shell cmd jobscheduler run -f com.example.smarter_jxufe 8802`。
- debug 启动自检三连（**改完小组件必看**）：`小组件自检: 24/24 OK` / `小组件数据桥: OK（cells 为数组，2 格）` / `小组件深色模式: OK 底色 #FFFFFF→#1E1E1E …`；另有 `WidgetRefreshJob: onStartJob 收到请求` / `Dart 侧回报 backgroundDone`、`[home_widget] 后台电费刷新成功: … kWh` / `后台成绩刷新成功: …` / `后台仪表盘刷新成功: 电费=… 网费=… 加权=… 志愿=… 今日=…`。
- ⚠️ **`Log.i` 只在 `onCreate` 里**：用 `am start -n …/.MainActivity` 把已在运行的 App 拉到前台**不会**重跑自检（走 onNewIntent）；要看自检必须先 `am force-stop` 再 `monkey -p com.example.smarter_jxufe -c android.intent.category.LAUNCHER 1`（或点图标）。华为的 logcat 主缓冲滚动很快，抓日志要**紧跟着** dump，或轮询到关键字出现为止。
- 深色模式核对：`adb shell cmd uimode night` 看当前模式（`yes`/`no`/`auto`）；临时切换用 `cmd uimode night yes|no`（**会改系统设置，先征得用户同意并及时切回**）。
- 快照落盘核对：`adb shell run-as com.example.smarter_jxufe cat /data/data/com.example.smarter_jxufe/shared_prefs/smarter_home_widget.xml`（**这是唯一能验证 `cells` 等嵌套结构没被写坏的途径**）。
- UI 取证：`adb shell uiautomator dump /sdcard/ui.xml` + `adb pull`（Flutter 语义树常在**第二次 dump** 才出来，第一次为空）；`input tap x y` / `input swipe x1 y1 x2 y2 ms`；截图 `screencap -p` + `view_image`，裁剪用 `[System.Drawing.Rectangle]::new(...)`（`New-Object System.Drawing.Rectangle 0,0,w,h` 会报位置参数错误）。**屏幕熄灭时 `screencap` 只能拍到黑屏**（PNG 只有十几 KB 就是黑屏）——需要用户亮屏解锁。
- Flutter 3.38 嵌入层事实：`FlutterCallbackInformation` **已被移除**（回调句柄那套编译不过）；`FlutterEngine` 构造器不接受 `DartEntrypoint`（单参构造会立刻跑 `main`）→ headless 只能用 `FlutterEngineGroup(...).createAndRunEngine(context, entrypoint)`。查 API 用 `javap -classpath <FLUTTER_ROOT>\bin\cache\artifacts\engine\android-arm\flutter.jar <类>`。
