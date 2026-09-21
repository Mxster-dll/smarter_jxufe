# SmarterJxUFE · 智慧er江财（Flutter 客户端）— 会话级约定

> 本文件只对本工作区 `<仓库根>` 有效。跨工作区通用的纪律（提问纪律、安装路径、沙箱网络经验）在 `~/.dsh/AGENTS.md`，不重复。
> 最近更新：2026-09-21（**综测结果卡改版**（用户原话：「我希望综测顶部汇总卡片不要显示：占比 20 / 35 / 15 / 15 / 15、加权成绩 91.86 分、材料条数 13 条 这些信息，而是把占比显示到每个“育”的名称后面」+「“测评结果”改成“总评成绩”，右侧显示总评成绩」+「去除“填写/录入后自动计算，实时更新”」）—— 头部 = 「总评成绩」+ 右侧 19px 大号**纯文字**总分（二轮起不是胶囊、不画铅笔图标，仍可点开占比弹层，`Key('zcTotalChip')` 不变）+ 综合等次胶囊，**总分按综合等次上色**；占比改成每育名称后的淡底小胶囊（`'${zcWeightPercentText(it.$4)}%'`，第 4 项 = `r.weights.d/z/t/m/l`），**育名与占比胶囊取该育自己的语义色（德育玫红 / 智育蓝 / 体育青绿 / 美育紫 / 劳育琥珀金 —— 最终取值见下文「五育色最终定色」）、分数取该育等次色**（二轮用户先提「对于优秀项，其“x育”以及分数都要用优秀的颜色」，随即更正为：「应该是“x育”与占比显示为此育的颜色，只有分数按等次显示」；占比胶囊 = 同色文字 + 同色 12% 淡底，`it.$5 = zcYuColors[...]`，行尾等次小胶囊保留；**总评成绩紧挨「总评成绩」字样**（用户原话：「我希望总评成绩紧挨“总评成绩”字样」→ 标签不再 `Expanded` 撑开（原来把 19px 总分顶到最右、中间一大段空白），改成 标签 → `SizedBox(width: 8)` → 总分，再由 `Spacer()` 把综合等次胶囊留在行尾） · **五育色最终定色**：用户先要「我希望把五育的颜色都提亮一点」，提亮后又反馈「我觉得我现在调的五育不好看，你改改」→ 不再靠手感，按两条硬指标定色：① 白底对比度**一律 4.75:1**（五行等重；提亮那版散在 3.68–4.43，智育蓝明显更亮）；② 育与育最小 ΔE(CIE76) **55.9**、育与最近等次色最小 **ΔE 20.2**（提亮那版德育红 ≈ 不合格红 ΔE 15、体育绿 ≈ 优秀绿 ΔE 19，同一行「育名 + 等次」会糊）。取值 = 德玫红 `0xFFD03860` / 智蓝 `0xFF2B77B8` / 体青绿 `0xFF1E8261` / 美紫 `0xFFBA31CF` / 劳琥珀金 `0xFF926D22`，唯一出处仍是 `lib/design/status_palette.dart` 的 `ZongceTone`，守卫 = `test/core_conventions_test.dart`「五育色 = 2026-09-21 定色后的取值」））；原右列三行（占比 … / 加权成绩 / 材料条数）整块删掉，`zcStatLine` 成死件已删、`zcResultCard` 的 `List<ZcMaterial> mats` 形参一并去掉；守卫 = `test/zc_weights_test.dart` 新增 4 条 widget 例 + 1 条源码守卫（负面判据**先剥注释** —— 新注释里逐字引用了用户原话，直接 contains 会把注释判成违规） · **综测页去掉「五育平均」**（用户原话：「综测页不要显示“五育平均”」）—— 结果卡当时只剩「总评成绩 + 占比 + 加权成绩 + 材料条数」；`ZcCalcResult.average` 留在引擎当对照值、界面不再露，守卫 = `test/zc_contest_contribution_test.dart` 的源码守卫（判据先剥掉注释） · **找空闲教室的节次选择器加了「连接 / 断开」过渡**（用户原话：「我希望为查无课时间功能内的节数选择器添加动画，尤其是两段连续选中的段被连接时，以及单一连续段被分开时」）—— 领域层 `classroomPeriodJointSegments` / `classroomPeriodJoints` 两个纯函数 + `kClassroomJointDuration = 220ms` + 缝上的桥接覆盖层 `_PeriodJointPainter`；**几何一格都不动**，靠 `JointSegments(a, a) ≡ PeriodRuns(a)` / `(b, b) ≡ PeriodRuns(b)` 两条端点恒等式保证起止不跳；口径与守卫见 §31.10） · 2026-09-20（**架构审查 ⑦ 第二/三轮：feature 依赖环 14 → 9** —— 四条**纯导航**的反向边收进「跳转缝」`lib/core/navigation/service_nav.dart`（`registerServiceScreen` 只由组装根 `main.dart` 的 `_installServiceScreens()` 调；业务侧 `openServiceScreen` / `resetToServiceScreen` / `replaceServiceScreen`，现 6 个 id：home / materials / settings / ims / comprehensive / dataCenter）；已收口 `home ⇄ ims`（切换账号回主页）· `materials ⇄ zongce`（去材料库）· `home ⇄ settings` + `ai ⇄ settings` 的导航腿（改走 design 层官方入口 `openSettings`）· `platform 选择器 ⇄ ims / comprehensive_service`（三个无参落点走 `replaceServiceScreen`）；**适用边界写在 §33.6.1.1**：只许纯导航的边、id 保持极小、不许长成通用路由器、未注册静默返回；`ai ⇄ settings` 剩下的 data 腿归 C 类同族耦合**不要**硬塞。守卫 = `test/core_conventions_test.dart`「跳转缝」组 + 行为 `test/service_nav_test.dart` 8 例，棘轮 `maxFeatureCycles = 9`） · **架构审查 ⑥ 巨型页面拆分 ✅ 五个巨型页全部完成：`grades_screen.dart` 1846→799 · `dashboard_panel.dart` 963→214 · `materials_screen.dart` 1544→383 · `zongce_screen.dart` 2305→1166 · `settings_screen.dart` 1983→258（**合计 8641 → 2820 行，−67%，14 个新文件**）—— 口径：零件收显式参数或自己 `ref.watch` 取数；**先按「是否碰状态」给成员分类**再决定怎么搬；私有顶层件先全局改公开名再整块搬（类头可能跨行，`class _X ...{` 必须同行的正则**会漏类**）；`///` 注释随成员一起搬；脚本必须带「跨度两两不许重叠」断言且删块排在改写之前；源码守卫改成读同族文件并集（含「改测试自己的局部读助手」这一形态）。台账 §33.4.4** · **架构审查 ⑤-B 设计口径：节标题唯一实现 `lib/design/section_title.dart` 的 `appSectionTitle`（8 处手写 + 6 处漂移全归一，`geCardTitle` 改为转发别名）/ 与卡片契约等价的 13 处手拼装饰 → `ShapeDecoration(shape: appCardShape(context))` / 9 处硬编码响应式断点 → `lib/design/breakpoints.dart`；用户裁定「全部归一 + 更新 golden」，`test/goldens/qa_home_family_tiles.png` 已重生** · **架构审查 ⑦ feature 依赖环 21 → 14 + 分层红线（data/domain 不许 import 别家 presentation）+ 「设置分节」契约与「平台标识」两处共享内核归一 —— 守卫 `test/core_conventions_test.dart`「feature 依赖环与分层」5 例，台账见 §33.6** · **架构审查后横向收敛 · 见 §33**：Cookie 罐（`SessionCookieJar` 认 `Domain` / `HostCookieJar` 按 host 分桶 / `setCookieNames`）、刷新闸门 `RefreshGate`、教务失效判据 `jwSessionExpired`、SSO 登录页判据 `ssoLoginPage`、CAS 回跳判据 `isCasLoginRedirect`、日志截断 `clipForTrace`、**异常基类 `AppException` / 会话失效标记 `SessionExpiredException`（**全仓 35 个具体异常类**收敛到一个基类、`lib/` 的裸 `throw Exception(` **已清零**，全仓只有 `lib/core/errors/app_exception.dart` 能写 `implements Exception`）** —— **每个都只有一个实现**，守卫 `test/core_conventions_test.dart`（+ 异常行为 `test/app_exception_test.dart`）；**`AGENTS.md` 已拆册**（§1–§3 常驻本文件，§4–§33 正文在 `docs/agents/`，索引见文末）；**代码生成产物入库**（68 个 `.g.dart`/`.freezed.dart`，本仓无 CI，缺了全新克隆编译不过）+ 守卫 `test/repo_hygiene_test.dart`）· **零引用依赖清理**（21 个里删 20 个，`flutter pub get` 后 `pubspec.lock` **215 → 158**，只剩 `json_annotation` 是白名单例外；守卫 = `test/repo_hygiene_test.dart` 的「依赖都被真的 import」——按 **import/export 指令**判、不按子串），并 **三态组件（加载 / 空 / 错误）的唯一实现 = `lib/design/app_states.dart`**（`AppLoadingState` / `AppErrorState` / `AppEmptyState`；裸 `const Center(child: CircularProgressIndicator())` **33 处 / 26 文件 → 0**，`Text('重试')` 手写文件 **39 → 28**；守卫 = `test/core_conventions_test.dart` 4 例 + 行为 `test/app_states_test.dart` 10 例），**统一认证换证「逐跳循环」统一为 `lib/core/network/cas_walk.dart`**（6 条 CAS 链迁 5 条：read_credit / cxstar / chaoxing / libsp / tsgxs —— 循环机制收进 core，站点只留自己的错误文案 / 跳数上限 / 取 token 姿势 / 网关桥接 / JS 跳转兜底；`dzj` 是 1(+1) 跳无循环故不迁，口径见 §33.3；守卫 = `test/cas_walk_test.dart` 14 例 + `test/core_conventions_test.dart`「换证循环」4 例）· 2026-09-19（**§30 学习通（超星）只读接入（CAS 换证链**只改 refer 一处**即得学习通会话；课程 / 作业 / 通知三件套；passport 是域级 Cookie → 必须按域匹配；首页目录 30 条）** · **§29 内置 AI 助手（OpenAI 兼容 8 家预设 + 多套切换 / 19 个函数调用工具覆盖成绩·课表·培养方案·学籍·公共查询·无课时间·校规检索·分数估计·综测·材料·志愿·校历·电费网费·设置 / 轻量快照 + 三条自动降级 / 只读 + 写操作二次确认 / 宫格与侧栏**第一格** + 全局悬浮球 / 设置页「AI 助手」节（排在「外观」之后）；模块自带 `lib/features/ai/README.md`）· **§29.10 回答渲染 Markdown + 空卡片守卫（用户同日二轮：「我希望支持markdown渲染，同时AI回复中偶尔会出现空卡片」）** · **§29.11 侧栏「AI 助手」紧贴「数据一览」+ 悬浮球三条真 bug（用户同日三轮：「电脑端AI助手在侧边栏放到和"数据一览"下方紧贴；现在的悬浮球点击后概率无反应，电脑端不显示悬浮球」—— Builder 的 context 在 Navigator **上方**需走全局 `navigatorKey` / 鼠标拖拽 slop 只有 1px / **`dispose()` 里改 provider 会被 Riverpod 拒发通知**）** · **§29.12 电脑端不出悬浮球（用户同日四轮：「我希望电脑端不显示悬浮球」—— `aiDesktopPlatformOn` 纯函数门控 + 桌面端设置页换成说明行；⚠ `flutter_test` 里 `defaultTargetPlatform` 恒为 `android`，要测桌面端必须 `debugDefaultTargetPlatformOverride` 且**必须在测试体内复位**）**） · 2026-09-16（**§21 小程序三服务落地（本科生成绩单 / 网络服务并入校园网 / 我的邮箱）+「网费 → 校园网」改名 + 门户应用列表侦察法** · **§19 侧栏视图的页面 chrome 口径（服务页整条导航栏不画，原按钮下沉到内容首行；面板顶部零 chrome；课表选择器喂真实行宽）** · **§18 页面转场唯一口径（去掉系统默认的中心放大 zoom；全应用横滑 + 淡入 300ms；IMS 入口闸门不再 `pushReplacement`）** · **§17.7 侧栏点击 = 右侧内嵌页面（master-detail，取消内嵌页返回键）** · **排名胶囊改 `#a/b/c`** · **logo 第二批 6 版待选 + 已装 4 个 logo 设计 skill（§17.6）** · **§17 主页布局（宫格 / 左侧导航栏）· 宫格卡片定宽等高 · 数据一览排名胶囊 · 实况窗入口迁设置页 · 应用中文名「智慧er江财」· logo 候选 A–F（第一批已被否）** · **§16 卡片风格唯一口径（全应用统一为「综测评测结果卡」形态：圆角 12 + 淡边框 + 纯白 + 无阴影；单色强调一律改主题红；主页两类卡片只统一形状保留原色）** · **§15.5 选课写入二轮加固（教务写应答是 iframe 回调页 `parent._callBack(...)` 且该端点 fire-and-forget → 写前重读核对 / 写后无条件对账刷新）** · **§4 课程截止日期管理（网课/作业/考试 · 每周/每两周自动滚动 · 本地通知提醒）** · **§12.2 设置页「教务会话」：令牌探活 + 手动刷新（探活优先、失效才换）** · **§4 课程备忘录（文字 + 图片，拷进私有目录 + 压到 1600px，单课 20 张）** · **§4 分数估计「构成占比条」（分段比例条 + 45°/135° 引出线 + 点条设比例，勿回退成滑动条）** · §3「主题纯白」口径（去 M3 seed 派生的偏红白） · §3「数据更新最小间隔 1 分钟」（畅想之星） · §15.4 选课检索栏与教务原页面 8 个控件逐一对齐（类别/属性 = 客户端过滤） · §15 教务「选课」口径（网上选课 / 选课结果 / 退选 + DES 加密移植 + 失效页 UTF-8 解码口径 + 学号 `xh` 口径核实） · §14.7 公共查询「账号默认预填」+ 卡片纯白 · §14 教务「公共查询」口径（教师/班级/教室/课程课表 + 多班对照找无课时间） · §13 Fluent Design 基础层 · §12.1 统一登录（CAS）按账号持久化 · §12 IMS 全局会话口径 · §11 首页顶栏 + 账号头像口径 · §9「当下学期」唯一口径 · §10 桌面小组件）。

## 本文件的用法（2026-09-19 拆册 · 通用约定，不依赖任何工具的私有语法）

- **本文件 = 唯一必读入口**。所有 agent 工具（Claude Code / Codex / Cursor / Gemini CLI / DSH …）都只自动读取工作区根目录的指令文件，且**都受字节预算限制**（DSH 实测上限 **65536 字节**）。拆册前本文件 **488 KB → 87% 的内容任何工具都读不到**；现在根文件约 33 KB，**全部可见**。
- **§1–§3 = 常驻纪律**（本机命令 / VM 探针 / 代码与设计约定），留在本文件，开箱即用。
- **§4–§32 = 分册正文**，在 `docs/agents/<NN>-<标题>.md`，**不自动注入** —— 需要时用读文件工具按需读，路径见文末索引表。
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
- **跨模块「地基件」的唯一实现（2026-09-20 · 架构审查后收敛）**：Cookie 罐 = `lib/core/network/cookie_jar.dart` 的 `SessionCookieJar`（**认 `Domain`**，超星系 / 图书馆用）与 `HostCookieJar`（**按 host 分桶**，单域换证站点用；7 个站点的私有三件套已迁完 4 个）+ `setCookieNames`（trace 打 `Set-Cookie` 的**唯一出口**，只出名字 —— 手写 `c.split(';').first` 打的是 `name=value`，会把凭据写进日志）；自动刷新闸门 = `lib/core/navigation/refresh_gate.dart` 的 `RefreshGate`（各模块只准继承）；教务会话失效 = `lib/core/network/jw_page_decoding.dart` 的 `jwSessionExpired` / `jwSessionExpiredPrefix` / `JwSessionExpiredException` / `isJwSessionExpiredError`（**数据层不许拿文案当类型**）；SSO 登录页判据（判**正文**）= `lib/core/network/sso_login_page.dart` 的 `ssoLoginPage` / `ssoLoginPageBytes`；CAS 打回登录页判据（判 **URL**）= `lib/core/network/cas_redirect.dart` 的 `isCasLoginRedirect`（精确到路径末段、先剥 `;jsessionid=`、兼容相对写法）；日志截断 = `lib/core/network/trace_text.dart` 的 `clipForTrace` / `clipForTrace200`；**统一认证换证「逐跳循环」** = `lib/core/network/cas_walk.dart` 的 `walkCasRedirects<T>` / `CasWalkSpec{maxHops, traceUrlMax, traceLocationMax}` / `CasWalkStep` / `CasWalkOutcome<T>` / 钩子动作 `CasHopGoto`·`CasHopFinish`（返回 `null` = 按 `Location` 继续）/ `casDioSender(dio, {responseType, extraHeaders, refererIsCurrentUrl})` —— **6 条 CAS 链已迁 5 条**（read_credit / cxstar / chaoxing / libsp / tsgxs：循环机制收进 core，站点只留自己的错误文案、跳数上限、取 token 的姿势、网关桥接、JS 跳转兜底；`dzj` 是 1(+1) 跳**无循环**故不迁，口径见 §33.3）；**异常基类** = `lib/core/errors/app_exception.dart` 的 `AppException`（**全仓 35 个具体异常类**的基类，契约 = `message` 是「能直接说给用户听的一句话」+ `toString()` 恒等于 `message`）/ `SessionExpiredException`（**会话失效标记**，9 个成员，界面按类型分支）+ `friendlyErrorText(e)`（**异常 → 上屏文案的唯一出口**，剥掉 `Exception: ` 前缀；此前这个手法在 lib 里手写了 11 处）；`Failure`（`Either` 侧，`lib/core/errors/failures.dart`）与它**刻意并存、不要互相转换**。守卫 = `test/core_conventions_test.dart`（**全仓只有该文件允许 `implements Exception`**，且禁止再手写 `.replaceFirst('Exception: ', '')`；裸 `throw Exception(` **已清零、禁止再出现**（起点 128 处）；`★ 每个 `*Exception` 类的根都是 `AppException`` 是**自维护**守卫 —— 扫全 `lib/` 建「类名 → 超类名」表，断言超类必是 `AppException` 或本仓另一个异常类，新增站点自动受管，不必手抄类名）+ `test/repo_hygiene_test.dart`（生成物入库）+ 异常行为 = `test/app_exception_test.dart`，口径与「哪些重复其实不该统一」见 **§33**（异常体系与迁移台账详见 §33.5）。
- **依赖纪律（2026-09-20 立 · 架构审查 ① 工程卫生）**：`pubspec.yaml` 只保留**真的被 import 的包**。本轮删掉 20 个零引用运行期依赖（`pubspec.lock` 包数 **215 → 158**，连带传递依赖共减 57），**唯一白名单例外 = `json_annotation`**（freezed 注解层：生成的 `*.freezed.dart` 里写着 `@JsonSerializable()`，注解由 `freezed_annotation.dart` 以 `export` 转发；用 `part of` 的 `.g.dart` 不算 import，**纯 import 统计必漏判**）。三个坑：① `http` 的唯一「命中」是 `package:http_parser/…` 的**子串**误匹配（`http_parser` 要留）；② `cupertino_icons` 可删 —— `CupertinoPageTransitionsBuilder` 是 Material 自带类、全仓 `CupertinoIcons.` 命中 0；③ `provider` 的 445 处命中全是 **Riverpod 自己 export 的** `ChangeNotifierProvider`。`ACCESS_NETWORK_STATE` 权限**原样保留**（曾是 `connectivity_plus` 的天然声明方，权限本身仍可能被原生侧用到）。⚠ CRLF 坑：`pubspec.yaml` 是 CRLF，按 `split('\n')` 切行时空行会剩成 `'\r'` → 被当成「块已结束」→ 只解析出 `flutter`。守卫 = `test/repo_hygiene_test.dart`「依赖都被真的 import」3 例（**自维护**：判据是 `^\s*(?:import|export)\s+'package:<名字>/` **指令**而非子串，故 `http_parser` 不会带出 `http`、白名单理由里写包名也不会自证自话；另两例守「白名单不许陈旧」「理由非空壳」）。
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
- **设计口径三件（2026-09-20 立 · 架构审查 ⑤-B；都在 `lib/design/`，页面里不要再拼一套）**：
  - **节标题** = `lib/design/section_title.dart` 的 `appSectionTitle(context, {required text, trailing, accent})`。审计起点：**8 个 feature 各写一份** `_sectionTitle`/`_sectionLabel`/`_buildSectionTitle`，另有 6 处漂移（高度 14/15、间距 8、字号 12.5、少 `letterSpacing`）→ 全部归一（用户 2026-09-20 裁定「全部归一 + 更新 golden」）；**只有两处「竖条 + 图标 + 文案」的分组头有意保留**（`school_calendar_screen.dart` / `site_nav_screen.dart`，并进去会丢图标），已进守卫白名单。
  - **卡片形状** = `lib/design/app_card.dart` 的 `kAppCardRadius` / `appCardBorderSide` / `appCardShape(context)` / `appCardTheme`。与它**逐像素等价**的手拼形状**共 17 处已清零**（13 处 `BoxDecoration` → `ShapeDecoration(shape: appCardShape(context), color: X)`；4 处 `Card(shape: RoundedRectangleBorder(...))` → `shape: appCardShape(context)`）；**着色卡（`AppColors.tintBorder`）不属于这一类，照旧手写**。
  - **响应式断点** = `lib/design/breakpoints.dart` 的 `Breakpoints.narrow`(600) / `tight`(400) / `wide`(720) / `extraWide`(1000) —— 不许再拿 `constraints.maxWidth` 直接与三位数字面量比大小（原来 9 处各写各的，看不出是不是同一个约定）。
  - 守卫 = `test/core_conventions_test.dart`「⑤-B 设计口径」4 例（节标题唯一 / 手写竖条白名单 / 手拼卡片清零 / 断点零字面量）。
- **色彩**：一律登记在 `lib/design/` —— **功能入口色**（宫格/侧栏/卡片图标）走 `lib/design/feature_palette.dart`（如 `scoreEstimate = Color(0xFF536DFE)`）；**状态 / 等级 / 标签 / 品牌 / 一次性视觉值**走 `lib/design/status_palette.dart` 的 `StatusPalette`（品牌与状态）/ `ZongceTone`（五育 + 综测等级）/ `TiceTone` / `MaterialsTone` / `ReadCreditTone` / `PlatformEntryTone`（2026-09-20 起；此前 `features/**` 里散着 72 处字面量）。**页面里不许再写 `Color(0x…)`**：守卫 = `test/core_conventions_test.dart`「设计色值唯一口径」（唯一白名单 = 课程色板 `schedule_tone.dart`，逐值经 ΔE 挑选、与功能色撞值属巧合）。
- **主题「纯白」口径（2026-09-14 立）**：`lib/main.dart` 的 `ColorScheme.fromSeed(seedColor: 校红 #C3282E)` 会按种子色相派生**整个中性色系** → 白色实际是 `#FFF8F7`（R−B = +8，1920×1080 截图像素实测），整页「白里透红」。已在 `.copyWith()` 里把白色系覆写为中性灰白（R = G = B）：`surface` / `surfaceContainerLowest` = `#FFFFFF`、`surfaceContainerLow` = `#FAFAFA`、`surfaceContainer` = `#F5F5F5`、`surfaceContainerHigh` = `#F0F0F0`、`surfaceContainerHighest` = `#EBEBEB`；**`surfaceTint` 必须设白**（它默认取 primary 系，AppBar / Card 抬起时会再染一层红）。新增任何「白色」都用中性色值，**不要**从 primary 派生；文字色（`onSurface` / `onSurfaceVariant` / `outline`）仍是种子的暖灰 —— 这是用户 2026-09-14 裁定「只改白色系」的结果，别顺手改。
- **首页服务目录（2026-09-15 重构）**：唯一条目表 = `lib/features/home/presentation/home_service_catalog.dart` 的 `homeServiceEntries({required void Function(Widget) push})` → `List<HomeServiceEntry{icon, title, subtitle, group, accent, onTap}>`，**强调色随条目走**；宫格渲染 = `presentation/home_service_grid.dart`、左侧导航栏渲染 = `presentation/home_sidebar.dart`，两者共用这一份。分组 = `HomeServiceGroup{ims '教务系统', study '学习与测评', campus '校园生活', info '数据与信息'}`（**只影响侧栏排版**，宫格平铺不分节）。
  ⚠ **旧铁律已作废**：从前条目写在 `home_screen.dart` 的私有 `_items(context)`、强调色存在顶层 `const _tileColors`，两者**按索引对齐**（增删磁贴必须同步增删色表）。现在只有一份目录、颜色随条目，**不可能再错位**；增删入口只动 catalog 一处，并同步 `test/home_tile_alignment_test.dart` 的条目数（现 **30** 条 —— 依次为 2026-09-19 的「AI 助手」（**第一格**）、「学习通」、「AA 算账」、「找空闲教室」、「网站导航」，逐条历史见该测试里的注释）与本文件。详见 §17、§32。
- **UI 风格基准 = 首页宫格页**：功能卡 `Card(elevation: 0, shape: appCardShape(context))` + `Clip.antiAlias`；节标题用 `appSectionTitle`（`lib/design/section_title.dart`；3px 竖条 + 13.5 w600 + `letterSpacing 0.3`，`accent` 默认主题红）—— **兼容别名 `geCardTitle` 仍在 `lib/features/score_estimate/presentation/ge_common.dart`，但它只是转发**，新代码用 `appSectionTitle`；列表 `padding: EdgeInsets.fromLTRB(24, …, 24, 48~96)`；卡间 12；图标 22–24 用 **Material Icons**（不用 emoji）。共享件在 `lib/features/score_estimate/presentation/ge_common.dart`（`geCardShape`——已转发到 `appCardShape` / `geCardTitle` / `geFmt` / `GeModeBadge`）；**卡片形状与强调色的唯一口径 = `lib/design/app_card.dart`（见 §16）**，别在页面里再拼一套 `BorderRadius.circular(…)` + `BorderSide(…)`。
- 图标按钮用 `IconButton(tooltip: …)`；`AlertDialog` 用 M3 默认样式 + `icon:`。
- **交互必须触摸可用**：手势**不得只挂在 `MouseRegion` hover 开关上**——触摸设备永不产生 hover，被 hover 门控的手势等于没注册（`lib/shared/widgets/academic_year_picker.dart` 曾因此在手机上整条划不动，且同一开关还控制着透明度）。拖拽一律用真实指针事件（`onHorizontalDragStart/Update/End/Cancel`）驱动状态，hover 只做增强。
- **全局偏好入口 = `lib/features/settings/presentation/settings_screen.dart`**（首页右上角齿轮进入）。新增用户偏好一律收拢到这里，不要再新增 feature-local 设置弹层（校历的三个显示开关已于 2026-09-11 迁入本页「校历」节，校历页 AppBar 齿轮只做跳转）。持久化照 `lib/features/campus_address/data/my_campus_prefs.dart`：Hive `Box<String>` 单 key + `ChangeNotifier` + `ChangeNotifierProvider`（改动需即时反映到多个页面时用此模式，**别用 FutureProvider**——中间有异步空窗，页面会先闪一次旧值）。
  - 已收拢的偏好（新增偏好照此追加，别另开弹层）：**入馆教育答题模式** = `lib/features/library_edu/data/tsgxs_prefs.dart`（box `tsgxsPrefs` / key `answerMode`，存 `TsgxsAnswerMode.name`），**唯一切换入口 = 设置页「入馆教育」节**；`tsgxs_exam_screen.dart` 与 `tsgxs_chapter_screen.dart` 只读该偏好（用户 2026-09-11 裁定：「模式的切换不应该显示在任何页面，只能显示在设置页」）——别再往页面里加模式切换控件或 `initialMode` 参数。
  - **标题栏右上角永远有设置按钮（用户 2026-09-16 裁定）**：唯一入口 = `lib/design/settings_entry.dart` 的 `SettingsActionButton`（2026-09-20 从 `features/settings/presentation/` 搬到 `lib/design/` —— 它是 chrome 契约，被 10 个 feature 当参数用）（紧凑款：`iconSize 18` + `visualDensity compact` + `constraints 30×30` → 实测点击区宽 **40**，与课表 `ScheduleTitleBar.actionWidth` 同口径），**由 `lib/design/pane_chrome.dart` 的 `paneAppBar` 自动追加到 `actions` 末尾** —— 所以走 `paneAppBar` 的服务页（宫格/侧栏能直达的那 20 多个）都自动有，新页面不必自己加。二级页（畅想之星阅读器 / 入馆教育答题页 / 课程详情）用裸 `AppBar`，**没有**设置按钮（用户拍板「所有服务主页、二级页不加」）。
    - **只显示本节**：页面用 `paneAppBar(context, …, settingsSections: [SettingsSection.calendar])` 声明；枚举 = `lib/design/settings_section.dart` 的 `SettingsSection`（2026-09-20 同上搬家）（**appearance 外观（深色模式，2026-09-16 加，见 §22）** / **aiAssistant AI 助手（2026-09-19 加，排在 appearance 之后，见「内置 AI 助手」节）** / campus 校区 / scope 生效范围 / homeLayout 主页布局 / calendar 校历 / **schedule 课表** / libraryEdu 入馆教育 / platformGuid 平台标识 / liveClass 上课实况窗 / imsSession 教务会话 / publicQuery 公共查询 / **cloudSync 云同步** / homeWidget 桌面小组件 —— 共 **14** 个，顺序即完整设置页的分节顺序），`SettingsScreen(sections: […])` 按它过滤分节（`sections.length == 1` 时 AppBar 标题变成节名）。**空列表 = 完整设置页**（主页、以及没有对应节的页面：综测 / 材料库 / 体测 / 邮箱 / 规章制度 / 志愿者 / 竞赛 / 第二课堂 / 电费）。
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

## 分册索引（§4–§33 正身在这里）

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
| §13 | Fluent Design（WinUI 3）基础层（2026-09-11 立） | `docs/agents/13-Fluent·Design（WinUI·3）基础层.md` |
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
