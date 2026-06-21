# SmarterJxUFE 智慧尼采

[![Flutter](https://img.shields.io/badge/Flutter-3.10+-02569B?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.10+-0175C2?logo=dart)](https://dart.dev)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

**智慧尼采** 是 [江西财经大学](https://www.jxufe.edu.cn) 智慧江财（学生综合服务平台）的第三方客户端。项目基于 Flutter 构建，对原平台功能进行了扩展与重新设计，旨在提供更流畅、更便捷的移动端与桌面端使用体验。

> 不只是套壳：基于对校园系统后端的逆向分析，实现了课程表可视化、培养方案解读、成绩加权计算、学分制规章制度查阅等原平台缺失或体验不佳的功能。

---

## ✨ 功能特性

- **统一认证登录** — 通过 CAS + MFA 双因子认证接入校园统一身份认证系统
- **课程表管理** — 支持周视图、拖拽排序、折叠分组，比原网页更直观
- **成绩查询** — 支持 GPA / 加权平均分计算，多维度成绩分析
- **培养方案查阅** — 按学院、专业查看培养方案，课程结构一目了然
- **规章制度速查** — 内置学分制管理办法、推免办法等规章制度全文检索
- **二维码扫码登录** — 支持 PC 端扫码快速登录
- **校历集成** — 查询学期、假期、教学周等日程信息
- **多平台适配** — 一套代码覆盖 Android、iOS、Windows、Linux、macOS、Web

## 🛠 技术栈

| 类别     | 技术                                                                                                              |
| -------- | ----------------------------------------------------------------------------------------------------------------- |
| 框架     | [Flutter](https://flutter.dev) 3.10+                                                                              |
| 状态管理 | [Riverpod](https://riverpod.dev) 2.x                                                                              |
| 网络请求 | [Dio](https://pub.dev/packages/dio) 5.x + Cookie 管理                                                             |
| 本地存储 | [Hive](https://pub.dev/packages/hive) + [Flutter Secure Storage](https://pub.dev/packages/flutter_secure_storage) |
| 代码生成 | [Freezed](https://pub.dev/packages/freezed) + [json_annotation](https://pub.dev/packages/json_annotation)         |
| 加密     | [crypto](https://pub.dev/packages/crypto) + [encrypt](https://pub.dev/packages/encrypt)                           |
| 二维码   | [qr_code_scanner](https://pub.dev/packages/qr_code_scanner) + [qr_flutter](https://pub.dev/packages/qr_flutter)   |
| 本地认证 | [local_auth](https://pub.dev/packages/local_auth)（指纹/面容解锁）                                                |

## 📁 项目结构

```
lib/
├── main.dart                 # 应用入口
├── Info.dart                 # 全局常量/信息
├── core/                     # 核心模块
│   ├── constants/            # 常量定义
│   ├── errors/               # 错误处理
│   ├── exception/            # 异常类型
│   ├── extension/            # 扩展方法
│   ├── function_type.dart    # 函数类型定义（Freezed）
│   ├── network/              # 网络层（Dio Provider、拦截器、设备画像）
│   └── storage/              # 本地持久化
├── design/                   # 设计系统
│   ├── Icons.dart            # 图标资源
│   └── JxufeTheme.dart       # 全局主题
├── features/                 # 功能模块（DDD 分层架构）
│   ├── auth/                 # 认证模块
│   │   ├── data/             #   数据层
│   │   ├── domain/           #   领域层
│   │   └── presentation/     #   表现层（页面/Widget）
│   ├── college/              # 学院/专业信息
│   ├── ims/                  # IMS 集成
│   ├── major/                # 专业/培养方案
│   ├── qr_login/             # 扫码登录
│   └── splash/               # 启动页
├── shared/                   # 共享组件
│   ├── gestures/             # 手势处理
│   └── widgets/              # 可复用 Widget
├── utils/                    # 工具函数
└── Widgets/                  # 全局自定义 Widget
reverse_engineering/          # 后端 API 逆向分析
├── login.http                # 登录接口分析
├── calendar.http             # 校历接口分析
├── regulations/              # 规章制度 PDF 与解读
├── subjects/                 # 课程/成绩接口分析
│   ├── course.http
│   ├── curriculum.http
│   ├── grade.http
│   └── weightedGrade.http
├── user_info/                # 用户信息接口分析
│   └── info.http
└── 问题.md                   # 分析过程中发现的问题与结论
```

## 🚀 快速开始

### 环境要求

- Flutter SDK ≥ 3.10.0
- Dart SDK ≥ 3.10.0
- Android Studio / VS Code + Flutter 插件

### 安装依赖

```bash
cd smarter_jxufe
flutter pub get
```

### 生成代码

项目使用 Freezed、Riverpod、json_annotation 等代码生成器，首次运行前需生成：

```bash
dart run build_runner build --delete-conflicting-outputs
```

### 运行

```bash
# 开发模式运行
flutter run

# 指定平台
flutter run -d android
flutter run -d windows
flutter run -d chrome
```

### 构建

```bash
# Android APK
flutter build apk --release

# Windows
flutter build windows --release

# iOS
flutter build ios --release
```

## 📱 平台支持

| 平台    | 状态       | 备注              |
| ------- | ---------- | ----------------- |
| Android | ✅ 主要目标 | 已测试            |
| iOS     | ⚠️ 可构建   | 未充分测试        |
| Windows | ✅ 已测试   | 桌面端可用        |
| Linux   | ⚠️ 可构建   | 未充分测试        |
| macOS   | ⚠️ 可构建   | 未充分测试        |
| Web     | ❌ 暂不可用 | CORS 限制，待解决 |

## 🔬 逆向工程

项目的一大亮点是对智慧江财后端 API 的系统性逆向分析。通过抓包和接口测试，梳理了认证流程、课表查询、成绩获取、培养方案等核心接口，并将分析结果整理在 `reverse_engineering/` 目录下供参考。

发现并记录的问题包括：
- 学分制管理办法版本确认
- 推免资格计算规则
- 培养方案分类体系漏洞
- 浮点型周学时的存在
- 校历数据完整性验证

## ⚠️ 免责声明

本项目为**学习交流目的**开发，仅供江西财经大学师生作为智慧江财平台的辅助工具使用。使用者的账号密码仅在本地与校园服务器之间传输，不会上传至任何第三方。请遵守学校相关规定使用本工具。

## 📄 License

MIT License

---

*Made with ❤️ by JxUFE students, for JxUFE students.*
