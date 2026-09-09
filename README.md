# SmarterJxUFE · 智慧尼采

> 江西财经大学「智慧江财」校园服务生态的**非官方**增强客户端。
> 不是套壳——在官方数据源之上重建交互、聚合信息，并补上官方平台缺失的能力。

- 技术栈：Flutter（Android / Windows）
- 代码仓库：<https://github.com/Mxster-dll/smarter_jxufe>

---

## 目录

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

## 功能特性

### 教务教学（IMS）

| 功能 | 说明 |
| --- | --- |
| 培养方案 | 专业培养方案与教学计划查询 |
| 课表 | 学期课程安排；今日课程同步呈现在首页仪表盘 |
| 成绩 | 各学期考试成绩、加权成绩与排名概览（与数据中心联动） |
| 毕业学分 | 毕业学分要求对照查询 |
| 我的 | 个人信息与学籍状态、账户管理（多账号切换入口） |

### 校园生活

| 功能 | 说明 |
| --- | --- |
| 宿舍电费 | 宿舍绑定（一键绑定/级联选择），剩余电量与充值记录查询 |
| 网费 | 校园网余额与充值记录；实时计费源（GUID）+ 门户概览双源兜底 |
| 请假 | 学生请假申请记录与审批进度查看 |
| 校历 | IMS 学期教学周历 + 官方小程序逐日安排双源合并；内置 19 个学期离线数据 |
| 学校地址 / 校区地图 | 四校区地址邮编一览，官网校区地图与交通示意图内置浏览 |

### 综合服务与数据中心

| 功能 | 说明 |
| --- | --- |
| 志愿服务时长 | 志愿活动记录与时长统计，CAS 会话持久化、过期自动刷新 |
| 第二课堂学分 | 成绩单、学分预警与毕业达标进度总览（SSP 平台） |
| 蛟湖阅读 | 蛟湖阅读考核记录：入馆学习与借阅达标情况 |
| 学生个人数据中心 | dzj 平台聚合概览：学业成绩 · 消费 · 图书 · 校园卡全景 |

### 自研增强

| 功能 | 说明 |
| --- | --- |
| 综合测评 | 证明材料自动测算：五育 / 等次 / 计分明细，规则条款悬停提示 |
| 材料库 | 证明文件本地归档，两级活动选择向导，自动带入综测计分 |
| 体测成绩 | 国家学生体质健康测试总分与分项查询，赛康资料归档 |
| 规章制度 | 校规校纪 · 学分学籍 · 竞赛目录 · 奖助办法等文档库（内置 MD/PDF 资产，可离线阅读与检索） |
| 获取平台标识 | 微信平台 GUID 的 App 内一键捕获（纯 Dart 本地代理），并附向导/粘贴/清除流程，用于配置网费、请假、校历等实时数据源 |

### 体验与平台能力

- **统一身份认证登录**：校园卡号 + 密码走学校 CAS；支持 MFA 多因素验证（二维码 / 短信验证码），可标记信任设备。
- **多账号并存**：多账号本地保存、一键切换；各平台会话（TGC / IMS JSESSIONID / SSP cookie）独立持久化并自动续期。
- **单页扁平入口**：登录后直达功能宫格，无平台两级菜单；全局统一红色主题（校徽红 `#C3282E`），各功能以分色卡片区分辨识。
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
- 账户管理页支持保存多个账号、查看当前账号、一键切换；部分实时数据源（网费 / 请假 / 校历）需要「获取平台标识」页配置微信平台 GUID 后才会启用实时通道。

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
│  │  ├─ auth/                     #   登录与账号：CAS、MFA、多账号
│  │  ├─ ims/                      #   教务：培养方案/课表/成绩/毕业学分/学籍
│  │  ├─ comprehensive_service/    #   志愿服务、第二课堂、蛟湖阅读
│  │  ├─ data_center/              #   学生个人数据中心
│  │  ├─ platform_guid/            #   平台标识（GUID）捕获向导
│  │  ├─ electricity/ net_fee/ leave/ school_calendar/ tice/ ...
│  │  ├─ zongce/ materials/ rules/ campus_address/ home/
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
| 质量 | 解析器/引擎单测 + golden 视觉回归测试 |

## 给开发者

- **分层约定**：每个功能模块内部按 `data / domain / presentation` 分层，领域模型放 `domain`，API 与 UI 通过 repository 解耦。
- **抗腐化层**：教务等平台的非 JSON 响应（HTML/XML）解析与映射放在各模块 `data/anti_corruption/` 下（parser → mapper → 领域模型），不要在页面里直接解析。
- **接口改动时**：先改解析/映射层并补充 `test/` 用例；抓包样例与接口说明沉淀到 `reverse_engineering/`，保持文档同步。
- **配色规范**：新增功能入口的分色统一登记到 `lib/design/feature_palette.dart`，不要在页面里散落魔法色值。
- **代码生成**：改动任何带注解的模型后运行 `dart run build_runner build --delete-conflicting-outputs`。

## 相关文档

- [企划.md](企划.md) —— 产品愿景（为什么做、做什么形态）
- [TODO.md](TODO.md) —— 当前进行中的工作
- [`reverse_engineering/`](reverse_engineering/) —— 各平台接口逆向笔记与 `.http` 抓包样例（宿舍电费、网费、请假、校历、登录等）

## 免责声明

- 本项目为**个人开发的非官方项目**，与江西财经大学及其信息化部门**无任何隶属或合作关系**。
- 本项目所接入的接口基于公开渠道与个人逆向分析，仅用于**学习交流与个人便利**，请勿用于任何商业用途。
- 数据以官方平台为准，本项目不对数据的实时性、完整性与准确性作任何保证；因使用本项目产生的一切后果由使用者自行承担。
- 请遵守学校相关管理规定与《个人信息保护法》，不得滥用本项目获取、传播他人信息。
- 若学校或相关权利方认为本项目涉及侵权，请联系作者删除相关内容。

> 本仓库暂未附带 LICENSE（保留所有权利）；如需合作或授权使用，请通过 GitHub Issues 联系作者。
