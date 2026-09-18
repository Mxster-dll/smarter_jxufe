# SmarterJxUFE · 智慧尼采

> 江西财经大学「智慧江财」校园服务生态的**非官方**增强客户端。
> 不是套壳——在官方数据源之上重建交互、聚合信息，并补上官方平台缺失的能力。

- 技术栈：Flutter（Android / Windows）
- 代码仓库：<https://github.com/Mxster-dll/smarter_jxufe>

---

## 版本与下载

| 项 | 值 |
| --- | --- |
| 当前版本 | **v2.0.0**（2026-09-19） |
| Android | [`SmartJXUFE-v2.0.0-android.apk`](https://github.com/Mxster-dll/smarter_jxufe/releases/latest) —— **正式签名**（RSA 4096 / 30 年有效期），Android 8.0+ |
| Windows | [`SmartJXUFE-v2.0.0-windows.exe`](https://github.com/Mxster-dll/smarter_jxufe/releases/latest) —— Inno Setup 安装包，免管理员权限安装，自动建桌面与开始菜单快捷方式 |
| 源码 | Releases 页附 `SmartJXUFE-source-v2.0.0.zip`（`git archive` 打包，与 tag 一一对应） |

- 下载页：<https://github.com/Mxster-dll/smarter_jxufe/releases>
- ⚠️ v1.0.0 及更早的安装包为**调试签名**；升级到 v2.0.0 请先卸载旧版（签名不同无法覆盖安装；卸载会清空本地登录态与缓存）。

---

## 目录

- [版本与下载](#版本与下载)
- [v2.0.0 更新亮点](#v200-更新亮点)
- [项目简介](#项目简介)
- [功能特性](#功能特性)
- [界面预览](#界面预览)
- [平台支持](#平台支持)
- [登录与账号](#登录与账号)
- [构建与运行](#构建与运行)
- [项目结构](#项目结构)
- [技术栈](#技术栈)
- [给开发者](#给开发者)
- [相关文档](#相关文档)
- [免责声明](#免责声明)

---

## 项目简介

SmarterJxUFE（智慧尼采）是一个用 Flutter 从零编写的「智慧江财」增强前端，面向江西财经大学在校生。项目的出发点写在 [企划.md](企划.md) 里：

> 绝不是单纯做成智慧江财的套壳，而是要基于能获取的信息实现一些智慧江财没有的功能。

我们以学校已有的公共服务为数据源——统一身份认证（CAS）、教务 IMS、综合管理服务平台、学生个人数据中心等——在不改动任何后端的前提下：

- **重建信息架构与交互**：登录后直达单页功能宫格；首页「数据一览」仪表盘把今日课程、电费余额、网费、志愿时长、课程加权等高频数据直接摊开，减少逐层点击。
- **补足官方平台缺失的能力**：综合测评自动测算、证明材料归档自动带入综测、规章制度离线阅读库、多账号并存与一键切换、App 内一键捕获平台标识等。
- **沉淀可维护的适配层**：教务等平台返回 HTML/XML 等非标准数据，全部经由独立 parser / mapper「抗腐化层」转换为领域模型；接口变动时可以快速定位、定点修复，而不是在 UI 里到处打补丁。

## v2.0.0 更新亮点

> 相对 v1.0.0 的主要变化。完整改动见 [Releases](https://github.com/Mxster-dll/smarter_jxufe/releases) 与 git 历史。

**AI 助手（新）** —— 内置大模型对话，OpenAI 兼容协议，预设 8 家服务商可随时切换；**19 个函数调用工具**覆盖成绩、课表、培养方案、学籍、公共查询、无课时间、校规检索、分数估计、综测、材料、志愿、校历、电费网费与设置，回答支持 Markdown 渲染；自动附带轻量数据快照作上下文，只读为主、写操作二次确认；宫格与侧栏第一格入口 + 移动端全局悬浮球。

**深色模式（新）** —— 跟随系统 / 浅色 / 深色三档（设置 →「外观」）。全应用语义色、卡片、课表十二色课程块与 Android 桌面小组件都按深浅两套色板适配。

**主页布局双形态** —— 手机端为定宽自适应宫格（固定格尺寸、按屏宽算列数）；桌面端为左侧导航栏（按教务 / 学习 / 校园 / 信息分组、条目分色）+ 右侧**内嵌页面**（点击即切换，不整页跳转），导航栏底部固定账号头像与设置入口。

**首页仪表盘** —— 「数据一览」指标卡（电费 / 校园网 / 课程加权与专业排名 / 志愿时长含本学年）+ 「今日课程」12 节时间轴：连续课合并成一块、空节按节数占位、相邻课间隔超过 1 小时自动画分隔线、课程名与教室放不下自动换行。

**课表** —— 学期码 `xxy` 阵列选择器（3 行 = 三学段 × 学年列）、周数选择器（可直接输入或点选，长按回到本周）、移动端下拉刷新、**拖动翻页**（顶部周几表头固定、左侧节数列淡出、松手复位）、节次格显示上下课时间、可关闭周六 / 周日（有课时弹确认框）、深色适配。

**综测与材料库** —— 总评成绩改为**五育加权**（占比可在结果卡上自行设置，默认 20/35/15/15/15）；智育加权与劳育志愿时长**按学年**自动带入（智育取课程加权口径）；学科竞赛标出「计入总分 / 未计入」；外语证书按表 10 档位识别（填原始成绩，不再直接当加分）；规则条款 `?` 悬停查看依据。材料库新增**两级选择向导**（类型 → 具体活动，目录含 160+ 竞赛与 13 类外语证书）、按二级分类分组、附件留档、右侧显示备注。

**阅读** —— 新生入馆教育原生闯关（五章学习地图 + App 内答题，后门模式可一键通过全部章节）；蛟湖阅读四部分进度（实际值 / 服务端值双档进度条）；畅想之星「经典阅读」接入：分类书架 + 检索、**原生 PDF 阅读器**（逐页解密渲染、进度云同步、阅读时长如实计入平台统计）、逐书阅读报告。

**其他** —— 桌面小组件扩到 **24 个**（数据一览 / 电费余额 / 课程加权 × 8 档尺寸）；新增网上选课、公共查询、上课实况窗、本科生成绩单申请、网络服务（校园网并入）、我的邮箱、请假记录；全局设置入口常驻各页标题栏且**只显示本页相关的设置节**。

## 功能特性

### 教务教学（IMS）

| 功能 | 说明 |
| --- | --- |
| 培养方案 | 专业培养方案与教学计划查询 |
| 课表 | 学期课程安排；学期码 / 周数选择器、拖动翻页、作息时间、周六周日开关；今日课程同步呈现在首页仪表盘 |
| 网上选课 | 选课 / 选课结果 / 退选：检索栏与教务原页面控件逐一对齐，写操作前后自动对账刷新 |
| 公共查询 | 教师 / 班级 / 教室 / 课程课表查询，支持多班对照找无课时间 |
| 上课实况窗 | 当前节次与下一节提醒（设置 →「上课实况窗」可开关） |
| 成绩 | 各学期考试成绩、加权成绩与排名概览（与数据中心联动）；含「本科生成绩单」申请（选报表类型 + 填邮箱 → 教务处盖章 PDF 发到邮箱） |
| 毕业学分 | 毕业学分要求对照查询 |
| 我的 | 个人信息与学籍状态、账户管理（多账号切换入口） |

### 校园生活

| 功能 | 说明 |
| --- | --- |
| 宿舍电费 | 宿舍绑定（一键绑定/级联选择），剩余电量与充值记录查询 |
| 校园网 | **两段合一**：①余额充值（实时计费源 GUID + 门户概览双源兜底，原「网费」功能）；②**网络服务**（学校自助服务系统真实数据：账号概览/余额/套餐、在线设备与强制下线、近期上网记录、历史账单、充值明细、业务办理记录、资费介绍、账号服务报停/复通/预约套餐、修改上网密码、微信充值跳转） |
| 我的邮箱 | 学校学生邮箱（学号@stu.jxufe.edu.cn）账号与初始密码查看、一键复制 |
| 请假 | 学生请假申请记录与审批进度查看 |
| 校历 | IMS 学期教学周历 + 官方小程序逐日安排双源合并；内置 19 个学期离线数据 |
| 学校地址 / 校区地图 | 四校区地址邮编一览，官网校区地图与交通示意图内置浏览 |

### 综合服务与数据中心

| 功能 | 说明 |
| --- | --- |
| 志愿服务时长 | 志愿活动记录与时长统计，CAS 会话持久化、过期自动刷新；**一键导出学校平台的《志愿服务时长认定登记表》Word 原件并调起系统分享**（自研原生分享桥 FileProvider + ACTION_SEND，零第三方依赖） |
| 第二课堂学分 | 成绩单、学分预警与毕业达标进度总览（SSP 平台） |
| 学科竞赛 | 第二课堂「学科竞赛申请 + 竞赛公示」：我的申请列表与审批状态、**选比赛（208 页目录 + 搜索）→ 选奖项（按分值）→ 个人/团队（成员检索、按排名）→ 上传证书图片 → 提交**、删除申请；公示按学号 / 姓名 / 班级搜索并翻页，详情区分个人 / 团队（团队出成员表） |
| 蛟湖阅读 | 阅读学分四部分进度（经典阅读 / 普通阅读 / 入馆教育 / 信息素养），**实际值与服务端值双档进度条**；页面内嵌新生入馆教育闯关（五章学习地图 + App 内答题，后门模式可一键通过全部章节）与学工平台加分记录 |
| 经典阅读（畅想之星） | 分类书架（中图法 / 学科 / 院系 + 检索）与**原生 PDF 阅读器**：逐页解密渲染、阅读进度云同步、**时长如实计入平台统计**；逐书阅读报告（累计时长 / 阅读天数 / 次数 / 完成时间） |
| 学生个人数据中心 | dzj 平台聚合概览：学业成绩 · 消费 · 图书 · 校园卡全景 |

### 自研增强

| 功能 | 说明 |
| --- | --- |
| AI 助手 | 内置大模型助手（OpenAI 兼容，预设 8 家服务商可切换）：**19 个函数调用工具**覆盖成绩、课表、培养方案、学籍、公共查询、无课时间、校规检索、分数估计、综测、材料、志愿、校历、电费网费与设置；自动附带轻量数据快照，只读为主、写操作二次确认；回答支持 Markdown 渲染；宫格与侧栏第一格入口 + 移动端全局悬浮球 |
| 综合测评 | 证明材料自动测算：五育加权总评（占比可设）/ 等次 / 计分明细，智育加权与志愿时长按学年自动带入，竞赛标注「计入总分」，规则条款 `?` 悬停查看依据 |
| 分数估计 | 课程平时分项（正计数 / 负计数 / 直接分数）自动折算，期末目标反推与达线预警；与教务已出成绩合计学分加权平均（按成绩页口径排除课程）并给出逐课贡献，列表页与课程详情页均显示该汇总卡，学分按本专业培养方案回填（Hive 本地） |
| 材料库 | 证明文件本地归档，两级活动选择向导，自动带入综测计分 |
| 体测成绩 | 国家学生体质健康测试总分与分项查询，赛康资料归档 |
| 规章制度 | 校规校纪 · 学分学籍 · 竞赛目录 · 奖助办法等文档库（内置 MD/PDF 资产，可离线阅读与检索） |
| 获取平台标识 | 微信平台 GUID 的 App 内一键捕获（纯 Dart 本地代理），并附向导/粘贴/清除流程，用于配置校园网、请假、校历等实时数据源 |
| 桌面小组件 | Android 桌面小组件三款：**数据一览**（一卡汇总电费 / 校园网 / 课程加权 / 志愿时长 / 今日课程）、电费余额、课程加权（含专业排名），各提供 **2×1 / 3×1 / 4×1 / 5×1 / 2×2 / 3×2 / 4×2 / 5×2 八档尺寸**（共 24 个独立小组件；单行档只放数值、最窄档自动改用短标题与短数值）；卡片配色走 `values-night` 自动适配系统深色模式；点击直达对应页面，解锁即时刷新 + 周期任务兜底（headless FlutterEngine 后台静默拉取，自研 MethodChannel 数据桥，零第三方依赖） |

### 体验与平台能力

- **统一身份认证登录**：校园卡号 + 密码走学校 CAS；支持 MFA 多因素验证（二维码 / 短信验证码），可标记信任设备。
- **多账号并存**：多账号本地保存、一键切换；各平台会话（TGC / IMS JSESSIONID / SSP cookie）独立持久化并自动续期；「信任此设备」随登录持久化，TGC 过期后自动重登全程免二次验证（仅学校侧主动失效 / 换机 / 系统大版本变更导致设备指纹变化时才需重新验证）。
- **单页扁平入口**：登录后直达功能宫格，无平台两级菜单；全局统一红色主题（校徽红 `#C3282E`），各功能以分色卡片区分辨识。
- **深色模式**：跟随系统 / 浅色 / 深色三档（设置 →「外观」）；全应用语义色、卡片、课表课程色与桌面小组件均按深浅两套色板适配。
- **两套主页布局**：手机端定宽自适应宫格；桌面端左侧导航栏（分组 + 分色）+ 右侧内嵌页面（点击即切换），导航栏底部固定头像与设置。
- **全局设置入口**：所有服务页标题栏右上角常驻设置按钮（`SettingsActionButton`），并**只显示本页相关的设置节**（如课表页 → 课表 / 教务会话 / 上课实况窗）。
- **本地优先**：常用数据落 Hive / 安全存储，离线可读（校历、规章制度等）；本地通知基础设施（Android / Windows）为提醒类功能预留。

## 界面预览

> 截图待补充：请将正式截图放入 `docs/screenshots/`，并在下表引用。

| 建议截图 | 说明 |
| --- | --- |
| `home.png` | 首页仪表盘与功能宫格 |
| `schedule.png` / `grades.png` | 课表、成绩 |
| `electricity.png` | 宿舍电费 |
| `zongce.png` | 综合测评测算 |
| `rules.png` | 规章制度文档库 |

## 平台支持

| 平台 | 状态 | 说明 |
| --- | --- | --- |
| Android | ✅ 主目标 | 手机端主要使用场景 |
| Windows | ✅ 已构建 | 桌面端（含本地代理捕获 GUID、系统通知） |
| iOS / macOS / Linux | ⚠️ 模板生成 | 工程目录已存在，尚未实机验证 |
| Web | ❌ 暂不支持 | 官方接口存在 CORS 限制（见 [企划.md](企划.md)） |

## 登录与账号

- 登录使用 **江西财经大学统一身份认证**（CAS）：账号为校园卡号 + 登录密码。
- 登录过程内置 MFA 检测：需要时弹出统一的多因素验证（二维码 / 短信验证码），支持「信任此设备」以降低后续验证频率。
- 登录态与各平台会话均持久化在本地：TGC、IMS JSESSIONID、SSP 等 cookie 在过期时会自动静默重登（仍需要 MFA 时通过回调唤起验证框）。
- 账户管理页支持保存多个账号、查看当前账号、一键切换；部分实时数据源（校园网 / 请假 / 校历）需要「获取平台标识」页配置微信平台 GUID 后才会启用实时通道。

## 构建与运行

### 环境要求

- Flutter stable 渠道 SDK（工程要求 Dart SDK `^3.10.0`，见 `pubspec.yaml`）
- Android：Android SDK（Android Studio 或命令行工具）
- Windows：Visual Studio 2022，勾选「使用 C++ 的桌面开发」工作负载
- （可选）Python 3：`tools/` 下部分开发脚本使用

### 步骤

```bash
git clone https://github.com/Mxster-dll/smarter_jxufe.git
cd smarter_jxufe

flutter pub get

# 首次克隆、或模型/接口定义变动后，重新生成序列化与 Riverpod 代码
dart run build_runner build --delete-conflicting-outputs

# 运行：Windows 桌面
flutter run -d windows

# 运行：Android 真机/模拟器（先用 flutter devices 查看设备 id）
flutter run -d <device-id>

# 运行测试（解析器、引擎、golden 回归等）
flutter test
```

### 发布构建（正式签名）

Android 正式包用仓库外的 keystore 签名，**密钥与口令绝不入库**（`android/key.properties`、`*.jks` 已在 `.gitignore` 中排除；缺失时自动回退 debug 签名，便于本地调试）：

```powershell
# android/key.properties（本地创建）
#   storeFile=D:/Keys/smarter_jxufe-release.jks
#   storePassword=…  keyAlias=smarter_jxufe  keyPassword=…

flutter build apk --release          # → build/app/outputs/flutter-apk/app-release.apk
flutter build windows --release      # → build/windows/x64/runner/Release/

# Windows 安装包（Inno Setup）
& "D:\Program\Inno\ISCC.exe" packaging\smarter_jxufe.iss   # → dist/SmartJXUFE-v<版本>-windows.exe

# 源码包（只含已提交内容，与 tag 一致）
git archive --format=zip --prefix=SmartJXUFE-v<版本>/ -o dist/SmartJXUFE-source-v<版本>.zip HEAD
```

构建前如遇 Windows 侧 `MSB8066`（`flutter_assemble.rule` 失败），删除 `build\flutter_assets` 后重试即可（该目录的增量拷贝非幂等）。

### 注意事项

- 代码生成产物（`*.g.dart`、`*.freezed.dart`）不应手工修改，统一由 `build_runner` 生成。
- 数据接口均为学校内网/域名服务：能否在校外访问取决于学校网络策略；部分功能（请假审批等）要求按应用内向导完成平台标识配置。
- 部分历史分支/标签（如 `0.0.7-补充提交`、`252PROC` 等）为开发过程存档，日常开发以 `main` 为准。

## 项目结构

```
smarter_jxufe/
├─ lib/
│  ├─ main.dart                    # 入口：主题、全局异常捕获、通知服务初始化
│  ├─ core/                        # 基础设施：Dio/会话、Hive 存储、导航、常量、异常体系
│  ├─ design/                      # 设计系统：主题、功能分色板（feature_palette）、图标
│  ├─ features/                    # 业务模块（feature-first 分层）
│  │  ├─ ai/                       #   内置 AI 助手（8 家预设 + 19 个函数调用工具）
│  │  ├─ auth/ qr_login/           #   登录与账号：CAS、MFA、多账号
│  │  ├─ ims/                      #   教务：培养方案/课表/成绩/毕业学分/学籍/选课/公共查询/成绩单
│  │  ├─ comprehensive_service/    #   志愿服务、第二课堂、学科竞赛、蛟湖阅读
│  │  ├─ read_credit/ cxstar/      #   阅读学分四部分进度；畅想之星书架与原生 PDF 阅读器
│  │  ├─ library_edu/              #   新生入馆教育（学习地图 + 闯关答题）
│  │  ├─ zongce/ materials/        #   综合测评测算；证明材料库
│  │  ├─ score_estimate/ tice/     #   分数估计（含备忘录与截止日期）；体测成绩
│  │  ├─ data_center/ network_service/ my_mail/ leave/ electricity/ net_fee/
│  │  ├─ school_calendar/ campus_address/ competition_award/ recommendation/
│  │  ├─ home/ home_widget/        #   主页（宫格 / 侧栏 / 仪表盘）；Android 桌面小组件
│  │  ├─ rules/ settings/ platform_guid/ platform/
│  ├─ shared/                      # 跨模块组件（可拖拽表格等）、通知服务
│  └─ utils/                       # 通用工具
├─ assets/
│  ├─ rules/                       # 规章制度资产：目录 JSON + Markdown + PDF
│  ├─ images/campus_maps/          # 校区地图
│  ├─ fonts/                       # 内嵌字体与自绘图标字体
│  └─ capture_certs/               # GUID 捕获用证书资产
├─ reverse_engineering/            # 接口逆向笔记（Markdown）+ .http 抓包样例
├─ tools/                          # 开发辅助脚本（Python/Dart 抓包与分析工具等）
├─ test/                           # 单元测试、fixtures 与 golden 基准
└─ pubspec.yaml
```

## 技术栈

| 方面 | 选型 |
| --- | --- |
| 框架 | Flutter · Material 3，校徽红 `#C3282E` 全局主题，内嵌字体（Cascadia Code / 霞鹜文楷 / 仓耳今楷等）+ 自绘 `SmarterJxufeIcons` 图标字体 |
| 状态管理 | Riverpod 2.x（`riverpod_generator` 代码生成为主） |
| 网络 | Dio + cookie_jar / dio_cookie_manager 会话管理；HTML/XML 响应解析（含 GBK 解码） |
| 本地存储 | Hive（业务缓存）+ flutter_secure_storage（凭据）+ get_storage / sqflite 辅助 |
| 模型与代码生成 | Freezed + json_serializable + hive_generator + riverpod_generator（`build_runner` 统一驱动） |
| 认证与会话 | CAS 登录流（HTML 解析、302 跟踪）、MFA 二维码/短信、TGC/JSESSIONID/cookie 持久化与自动重登 |
| 特殊能力 | 纯 Dart 本地代理捕获微信平台 GUID；Android/Windows 本地通知 |
| AI | OpenAI 兼容 HTTP（Chat Completions + Function Calling），8 家服务商预设，密钥存 flutter_secure_storage |
| 文档与阅读 | pdfrx / pdfium 原生渲染加密单页 PDF；Markdown 渲染；规则条款浮层（Overlay + 逐帧跟随） |
| 桌面小组件 | Android AppWidget（RemoteViews，24 个 provider）+ headless FlutterEngine 后台刷新 + 自研 MethodChannel 数据桥 |
| 发布与签名 | Android keystore 正式签名（RSA 4096，密钥不入库）；Windows Inno Setup 安装包；`git archive` 源码包 |
| 质量 | 解析器/引擎单测 + widget 行为守卫 + golden 视觉回归测试（1400+ 例，`flutter test --concurrency=1`） |

## 给开发者

- **分层约定**：每个功能模块内部按 `data / domain / presentation` 分层，领域模型放 `domain`，API 与 UI 通过 repository 解耦。
- **抗腐化层**：教务等平台的非 JSON 响应（HTML/XML）解析与映射放在各模块 `data/anti_corruption/` 下（parser → mapper → 领域模型），不要在页面里直接解析。
- **接口改动时**：先改解析/映射层并补充 `test/` 用例；抓包样例与接口说明沉淀到 `reverse_engineering/`，保持文档同步。
- **配色规范**：新增功能入口的分色统一登记到 `lib/design/feature_palette.dart`，不要在页面里散落魔法色值。
- **代码生成**：改动任何带注解的模型后运行 `dart run build_runner build --delete-conflicting-outputs`。

## 相关文档

- [企划.md](企划.md) —— 产品愿景（为什么做、做什么形态）
- [TODO.md](TODO.md) —— 当前进行中的工作
- [`reverse_engineering/`](reverse_engineering/) —— 各平台接口逆向笔记与 `.http` 抓包样例：
  - 教务：[选课接口](reverse_engineering/选课接口.md) · [公共查询接口](reverse_engineering/公共查询接口.md) · [本科生成绩单接口](reverse_engineering/本科生成绩单接口.md)
  - 校园服务：[宿舍电费接口](reverse_engineering/宿舍电费接口.md) · [网费接口](reverse_engineering/网费接口.md) · [网络服务接口](reverse_engineering/网络服务接口.md) · [我的邮箱接口](reverse_engineering/我的邮箱接口.md) · [请假接口](reverse_engineering/请假接口.md) · [校历接口](reverse_engineering/校历接口.md) · [志愿时长接口](reverse_engineering/志愿时长接口.md) · [竞赛接口](reverse_engineering/竞赛接口.md)
  - 阅读：[入馆教育接口](reverse_engineering/入馆教育接口.md) · [阅读学分接口](reverse_engineering/阅读学分接口.md) · [畅想之星接口](reverse_engineering/畅想之星接口.md)
  - 平台与规则：[小程序门户服务接口](reverse_engineering/小程序门户服务接口.md) · [2026 综测规则](reverse_engineering/2026综测规则.md) · [鸿蒙服务卡片可行性](reverse_engineering/鸿蒙服务卡片可行性.md)

## 免责声明

- 本项目为**个人开发的非官方项目**，与江西财经大学及其信息化部门**无任何隶属或合作关系**。
- 本项目所接入的接口基于公开渠道与个人逆向分析，仅用于**学习交流与个人便利**，请勿用于任何商业用途。
- 数据以官方平台为准，本项目不对数据的实时性、完整性与准确性作任何保证；因使用本项目产生的一切后果由使用者自行承担。
- 请遵守学校相关管理规定与《个人信息保护法》，不得滥用本项目获取、传播他人信息。
- 若学校或相关权利方认为本项目涉及侵权，请联系作者删除相关内容。

> 本仓库暂未附带 LICENSE（保留所有权利）；如需合作或授权使用，请通过 GitHub Issues 联系作者。
