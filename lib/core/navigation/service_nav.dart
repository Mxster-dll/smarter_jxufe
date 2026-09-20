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

/// 材料库（综测页的「去材料库录入 / 管理」要跳它）。
const String kServiceMaterials = 'materials';

/// 设置页。⚠ 常规入口是 `lib/design/settings_entry.dart` 的 `openSettings(context, sections: …)`；
/// 这里只给「需要整栈替换」等特殊场景兜底。
const String kServiceSettings = 'settings';

final Map<String, ServiceScreenBuilder> _builders = <String, ServiceScreenBuilder>{};

/// 组装根用：注册一个可跳转的服务页（重复注册覆盖，便于测试替换）。
void registerServiceScreen(String id, ServiceScreenBuilder builder) {
  _builders[id] = builder;
}

/// 是否已注册（未注册时调用方可以自行决定兜底，比如给一句提示而不是静默）。
bool hasServiceScreen(String id) => _builders.containsKey(id);

/// 已注册 id 的快照（守卫测试用：断言组装根确实注册了哪些页）。
List<String> registeredServiceScreens() => _builders.keys.toList()..sort();

/// 清空注册表（**只给测试用**：注册表是全局单例，用例之间要隔离）。
@visibleForTesting
void clearServiceScreens() => _builders.clear();

/// push 打开目标页；未注册则**什么都不做**并返回 false。
bool openServiceScreen(BuildContext context, String id) {
  final builder = _builders[id];
  if (builder == null) return false;
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => builder()));
  return true;
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
}
