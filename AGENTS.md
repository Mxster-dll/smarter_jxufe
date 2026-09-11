# SmarterJxUFE · 智慧尼采（Flutter 客户端）— 会话级约定

> 本文件只对本工作区 `D:\Project\Ongoing\smarter_jxufe` 有效。跨工作区通用的纪律（提问纪律、安装路径、沙箱网络经验）在 `~/.dsh/AGENTS.md`，不重复。
> 最近更新：2026-09-11（**§13 Fluent Design 基础层（毕业学分页重设计）** · **§12.1 统一登录（CAS）按账号持久化** · §12 IMS 全局会话口径 · §11 首页顶栏 + 账号头像口径（含取图 / 拍照入口、宫格去掉「我的」）· §9「当下学期」唯一口径 · §10 桌面小组件 · 校历「假/班」角标口径 · 「我的校区」偏好 · 三套校区命名统一口径）。

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
- **色彩**：一律登记在 `lib/design/feature_palette.dart`（如 `scoreEstimate = Color(0xFF536DFE)`）。
- **首页宫格**：`home_screen.dart` 的 `_items(context)`（`List<_HomeItem(icon, title, subtitle, onTap)>`）与文件顶层 `const _tileColors = <Color>[...]` **按索引一一对齐**，渲染取 `_tileColors[i % _tileColors.length]` → 插入新入口时两处都要动，**别错位**（「我的」磁贴 2026-09-11 已删，见 §11.1）。
- **UI 风格基准 = 首页宫格页**：功能卡 `Card(elevation: 0, shape: geCardShape(context))` + `Clip.antiAlias`；节标题用 `geCardTitle`（3px 竖条 + 13.5 w600）；列表 `padding: EdgeInsets.fromLTRB(24, …, 24, 48~96)`；卡间 12；图标 22–24 用 **Material Icons**（不用 emoji）。共享件在 `lib/features/score_estimate/presentation/ge_common.dart`（`geCardShape` / `geCardTitle` / `geFmt` / `GeModeBadge`）。
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

## 5. 教务数据来源速查

| 数据 | 入口 | 要点 |
|---|---|---|
| 成绩 | POST `jwxt.jxufe.edu.cn/student/xscj.stuckcj_data10421.jsp`（menucode S40303） | 解析 `grades_html_parser.dart`：**学分 = 表格第 3 列**；`cells.length < 10` 整行丢弃。缓存 box `gradesCache`，键前缀 `grades\|…`，值 `{'grades':[Grade.toMap()]}`，**可能同时存在多份不同参数副本**（聚合要遍历全部 key） |
| 课表 | GET `…/wsxk/xkjg.ckdgxsxdkchj_data10319.jsp`（params = base64） | `schedule_html_parser.dart`：**学分 = `cells[4]`**；无上课安排的表头/占位行会被解析成名为「课程」等列头词的**伪课程**，导入须过滤（`_isNoiseEntry`） |
| 培养方案 | `CurriculumRepository.getCurriculumIn(year, College, Major)` | **命中本地缓存直接返回，不发网络**（离线可用）；box `curriculums`，key = `CurriculumKey(year, college, major)` |
| 学籍 | `studentInfoRepository.getCachedStudentInfo()` | 取 `enrollYear / college / major`，是上面链路的起点 |
| 校历 | GET `jwxt.jxufe.edu.cn/public/SchoolCalendar.jsp` → POST `…/SchoolCalendar.show.jsp`（form: `menucode/xn/xq_m/rad=1/sel_xn_xq`） | **免登录**，但必须复用第一步种下的匿名 `JSESSIONID`（否则返回空模板 / 「凭证已失效」）；响应 **GBK**；日期格 `<span class='workday\|nonday'>` 的语义与陷阱见 §8。抓取与核对用 **python requests**（沙箱内 curl.exe 的 TLS 全废） |

链路：学籍 → `collegeRepository.getAllCollege()` 按名匹配 → `majorRepository.getAllMajorIn(college, year:)` 按名匹配 → 培养方案。任一步失败**返回空索引、不阻塞界面**（回退课程自身学分）。
（2026-09 实测该生：2025 · 计算机与人工智能学院 · 计算机科学与技术，44 学院 / 9 专业 / 97 门课。）

## 6. 工作区状态

- git 工作区有**大量历史 untracked**（`.scratch/`、`dianfei_work/`、`packaging/`、`reverse_engineering/` 等），不要清理、不要 `git clean`。
- 测试是扁平的 `test/*_test.dart`（**28 个文件**，引擎/纯逻辑单测，无 golden）；`flutter test` 全量 **393 例：388 通过 / 5 失败**（2026-09-11 实测）。5 个失败**都不是回归**：模板遗留 `test/widget_test.dart`（Counter 冒烟，历史上一直失败）+ **3 例 `test/settings_calendar_section_test.dart`**（另一会话新加的「入馆教育」偏好节：`TsgxsExamPrefsStore._load` 抛 `HiveError: You need to initialize Hive or provide a path to store the box.`，该测试没 `Hive.init`）+ **1 例 `test/auth_session_account_test.dart:230`**（`Expected: (B, pw-B)` / `Actual: (null, null)`，该文件当时正被别的会话编辑）。部分文件实测（**非全部**，2026-09-11）：`ge_engine_test` 26、`ge_curriculum_test` 11、`ge_summary_test` 8、`calendar_day_mark_test` 47、`my_campus_test` 23、`zongce_engine_test` 15、`school_term_test` 14、`account_avatar_test` 21、`school_calendar_screen_test` 8、`school_calendar_parser_test` 6、`tice_notice_test` 5。
- 截图验证：`Add-Type System.Drawing` + user32（`SetWindowPos(-1 TOPMOST)`、`SetForegroundWindow`、`GetWindowRect`）+ `Graphics.CopyFromScreen` → PNG → `view_image`。注意 `PrintWindow(…,2)` 可能抓到被遮挡的其它窗口内容；`view_image` 回报的中文像素坐标不可靠。

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
- **行为口径（用户 2026-09-11 裁定，原话）**：「开学前显示整学期视图；假期显示下一学期课表，没出来则提示‘课表还没出来’；开学后显示实际周数；**每次进入都重置为当前学期**」。落到代码：`_week = currentWeek`（`null` = 整学期视图）、`_termNotStarted => _isCurrentTerm && _currentWeek == null` → 空课表显示「课表还没出来」+ 副文案，否则「暂无课表数据」；**手动选择不持久化**（只在页内记住）。
- **配套修正**：`lib/shared/widgets/academic_year_picker.dart` 必须实现 `didUpdateWidget`（父级异步纠正学年后要 `_animToken++` 作废在途补间 + 重算 `_selected`/`_offset`），只在 initState 读 `initialYear` 会导致显示不跟随。
- **体测页的时间提示 = 服务端原文，不硬编码时段**：`lib/features/tice/data/tice_remote_datasource.dart` 的顶层纯函数 `String? ticePlainNotice(String body)`（trim 后非空、≤300 字、不以 `{`/`[` 开头、不含 `<` → 返回原文，否则 null）在 JSON 解析**之前**拦截；实测非开放时段返回 62 字节纯文本 `允许学校学生成绩查询的时间为:9:00:00~21:00:00。` → `TiceResultKind.notice`，界面直接展示该文案。
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
  - **同一部分只允许出现一张卡**（用户原话：「每个部分显示了好几个卡片…这个四个部分都只显示一个卡片，样式大体是进度卡片」）——原先的 `ReadCreditSummarySection`（学分状态卡 + 5 项行 + 折叠说明）**已删除**，别再恢复。
  - 点卡片：入馆教育 → 原「新生入馆教育」页（`ReadCreditProgressSection.onOpenLibraryEdu` 由 `jh_read_screen.dart` 注入，read_credit 不反向依赖 library_edu 页面）；其余三部分 → 平台明细页 `ReadCreditDetailScreen`。
  - 蛟湖文化活动不是四部分之一，**并入学分总卡的一个状态胶囊**，不单独占一张卡。
  - 两档口径：平台汇总**只在 5 月 / 11 月更新**，故「实际」一律优先取 App 自有实时源（入馆教育五章闯关、数据中心 `fetchBorrowCountsOnly`），没有自有源的部分才回退平台明细表实时统计。
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

