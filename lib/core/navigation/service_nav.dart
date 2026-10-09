/// 页面之间的「跳转缝」（2026-09-20 立 · 架构审查 ⑦）。
///
/// **为什么要它**：feature 之间直接 `import` 别家的 **presentation** 页面去 push，会造出
/// 双向依赖环 —— 实测有两条这样的反向边：`features/zongce` 为了「去材料库」import 了
/// `features/materials/presentation/materials_screen.dart`；`features/ims/student_info` 为了
/// 「切换账号后回主页」import 了 `features/home/presentation/home_screen.dart`。
///
/// **做法**：这里只放**注册表 + 两个动作**，组装根 `lib/main.dart` 把目标页 builder 注册进来，
/// 业务代码只喊 id —— 与 `mfaReloginService.setFallback`（`lib/features/auth/data/mfa_relogin_service.dart`）
/// 同一套路：**组装根本来就该知道所有模块**，feature 之间因此少一条环。
///
/// ⚠ 两点约定：
/// 1. **未注册时静默返回**（`openServiceScreen` 返回 false / `resetToServiceScreen` 退化为
///    `popUntil(isFirst)`）—— 单测常常只 pump 一个页面、不走组装根，抛异常会把无关用例打红；
/// 2. 这里**不许 import 任何 feature**（`lib/core/` 是地基，唯一允许的方向是 feature → core）。
library;

import 'package:flutter/material.dart';

/// 目标页构造器（无参，页面自己从 Riverpod 取数）。
typedef ServiceScreenBuilder = Widget Function();

/// 首页（宫格 / 侧栏）。
const String kServiceHome = 'home';

/// 侧栏视图右栏的默认那一格：**数据一览概览**。
///
/// 用户 2026-10-09 二十四轮：它必须是一个"注册过的页面"（而不是 `home_screen` 里裸渲染
/// 的一块内容），否则它里面的卡片上查不到 `PaneScope`，点开就会**整页盖住窗口**。
const String kServiceOverview = 'overview';

/// 材料库（综测页的「去材料库录入 / 管理」要跳它）。
const String kServiceMaterials = 'materials';

/// 设置页。⚠ 常规入口是 `lib/design/settings_entry.dart` 的 `openSettings(context, sections: …)`；
/// 这里只给「需要整栈替换」等特殊场景兜底。
const String kServiceSettings = 'settings';

/// IMS 教务（平台选择器「教学信息服务」的落点）。
const String kServiceIms = 'ims';

/// 综合管理服务平台（平台选择器「综合管理服务平台」的落点）。
const String kServiceComprehensive = 'comprehensive';

/// 学生个人数据中心（平台选择器「学生个人数据中心」的落点）。
const String kServiceDataCenter = 'dataCenter';

/// 「我的」（学籍个人信息页）。
///
/// 2026-10-09 五轮加：侧栏视图下它和设置一样**内嵌在右栏**显示（不再 push 子页面），
/// 而 `home` 不许直接 import 别家页面 —— 所以走这里取 builder。
const String kServiceStudentInfo = 'studentInfo';

final Map<String, ServiceScreenBuilder> _builders = <String, ServiceScreenBuilder>{};

/// id → 显示名（顶部历史里的那一行字）。组装根注册时一并给。
final Map<String, String> _labels = <String, String>{};

/// 组装根注入的 Navigator：**历史回放**里没有 `BuildContext`，只能靠它开页面。
///
/// 只在 `lib/main.dart` 用 `navigatorKey.currentState` 注入一次（`SmarterJxUFE.build`）。
NavigatorState? _navigator;

/// 组装根注入的「记一笔历史」钩子。
///
/// 缝本身是**纯函数 + 注册表**：它没有 `WidgetRef`，也不该 import 历史那条链上的
/// provider。所以由组装根把动作注入进来，缝只负责在三个跳转动作里喊它。
/// 参数刻意只用基本类型（id / 文案 / 能不能回去），避免 core 里互相 import。
void Function(String id, String label, bool canRestore)? serviceNavHistoryRecorder;

/// 组装根用：把 Navigator 交给缝（历史回放要用）。
void attachServiceNavigator(NavigatorState? navigator) => _navigator = navigator;

/// 组装根用：注册一个可跳转的服务页（重复注册覆盖，便于测试替换）。
///
/// [label] = 顶部路由历史里的显示名（不传则退回 [id]）。
void registerServiceScreen(
  String id,
  ServiceScreenBuilder builder, {
  String? label,
}) {
  _builders[id] = builder;
  if (label != null) _labels[id] = label;
}

/// 某个 id 的显示名（没登记就返回 null）。
String? serviceScreenLabel(String id) => _labels[id];

/// 取目标页的**构建器**（不 push）。
///
/// 给「内嵌显示」用（侧栏右栏的 `HomeDetailPane` 要把它当面板首路由）：
/// 调用方拿到 builder 自己决定是 push 还是嵌进面板，**跨 feature 的页面依赖照样
/// 只经过这一道缝**（`home` 不得直接 import `features/settings/…`，见 §33.6.1.1）。
/// 未注册返回 null（调用方自行兜底，与 [openServiceScreen] 同口径）。
ServiceScreenBuilder? serviceScreenBuilder(String id) => _builders[id];

/// 是否已注册（未注册时调用方可以自行决定兜底，比如给一句提示而不是静默）。
bool hasServiceScreen(String id) => _builders.containsKey(id);

/// 已注册 id 的快照（守卫测试用：断言组装根确实注册了哪些页）。
List<String> registeredServiceScreens() => _builders.keys.toList()..sort();

/// 清空注册表（**只给测试用**：注册表是全局单例，用例之间要隔离）。
@visibleForTesting
void clearServiceScreens() {
  _builders.clear();
  _labels.clear();
}

/// push 打开目标页；未注册则**什么都不做**并返回 false。
bool openServiceScreen(BuildContext context, String id) {
  final builder = _builders[id];
  if (builder == null) return false;
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => builder()));
  _recordHistory(id);
  return true;
}

/// 无 `BuildContext` 版（**路由历史的回放**用：`restore()` 里手里只有 Navigator）。
///
/// 没注入 Navigator（单测常常只 pump 一个页面、不走组装根）→ 静默返回 false，
/// 与「未注册」同口径，不抛异常。
bool openServiceScreenById(String id) {
  final builder = _builders[id];
  final navigator = _navigator;
  if (builder == null || navigator == null) return false;
  navigator.push(MaterialPageRoute(builder: (_) => builder()));
  _recordHistory(id);
  return true;
}

/// 记一笔历史（只喊组装根注入的钩子；没人接就什么都不做 —— 单测方便）。
void _recordHistory(String id) {
  final recorder = serviceNavHistoryRecorder;
  if (recorder == null) return;
  recorder(id, _labels[id] ?? id, _builders.containsKey(id));
}

/// 清空整栈后打开目标页（「切换账号 → 回主页」这类场景）；
/// 未注册则退化为 `popUntil(isFirst)`（对「回根页」语义等价）。
void resetToServiceScreen(BuildContext context, String id) {
  final navigator = Navigator.of(context);
  final builder = _builders[id];
  if (builder == null) {
    navigator.popUntil((route) => route.isFirst);
    return;
  }
  navigator.pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => builder()),
    (_) => false,
  );
  _recordHistory(id);
}

/// **替换当前页**打开目标页（平台选择器那类「选完就换页、不再回来」的场景）；
/// 未注册则什么都不做并返回 false。
bool replaceServiceScreen(BuildContext context, String id) {
  final builder = _builders[id];
  if (builder == null) return false;
  Navigator.of(context).pushReplacement(
    MaterialPageRoute(builder: (_) => builder()),
  );
  _recordHistory(id);
  return true;
}
