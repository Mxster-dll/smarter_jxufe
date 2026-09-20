/// 学习通取数闸门 —— 自动刷新最小间隔。
///
/// 口径与畅想之星（`cxstar_refresh_gate_provider.dart`）逐条一致，理由也一样：
/// 一次取数是 **69 个请求**（1 课程 + 34×2 作业 + 通知 + 换证），
/// 「进页面 / 从子页返回 / 回前台」三件套叠加起来会把服务端点着。
///
/// - **窗口起点 = 上一次真的取到新数据的时刻**（不是「发出请求」）：请求在飞 /
///   失败时不该封锁窗口，否则一次网络抖动会让人一分钟内连重试都做不了。
/// - **不受限**：手动下拉刷新、错误卡「重试」、会话变更。
/// - provider **非 autoDispose**：窗口必须跨越页面重建（「学习通 → 返回 → 再进入」
///   每次都是新 State，记在 State 上等于没记账）。
library;

import 'package:smarter_jxufe/core/navigation/refresh_gate.dart';

/// 自动刷新的最小间隔（用户口径：1 分钟）。
const Duration chaoxingMinRefreshInterval = Duration(minutes: 1);

/// 取数闸门（纯逻辑，时钟可注入 —— widget 测试里推不动真实 `DateTime.now()`）。
///
/// 机制本体 = [RefreshGate]（`lib/core/navigation/refresh_gate.dart`，2026-09-20 收敛）；
/// 本类只绑定学习通自己的间隔常量，字段与方法全部继承（`lastUpdatedAt` /
/// `allowsAutoRefresh` / `markUpdated` / `remaining` / `reset`），调用方口径不变。
class ChaoxingRefreshGate extends RefreshGate {
  ChaoxingRefreshGate({super.now})
    : super(minInterval: chaoxingMinRefreshInterval);
}
