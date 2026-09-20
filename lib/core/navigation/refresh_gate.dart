/// 「自动刷新最小间隔」闸门的唯一实现（跨模块共用）。
///
/// 2026-09-20 立（架构审查后收敛）：此前每个需要节流的模块各写一份结构相同的
/// 闸门类 —— `cxstar_refresh_gate_provider.dart` 的 `CxstarRefreshGate` 与
/// `chaoxing_gate.dart` 的 `ChaoxingRefreshGate` 逐条语义一致、只是字段名不同
/// （`_clock` vs `_now`、`lastUpdatedAt` 是 getter vs 字段），第三处再有需求就会
/// 出现第三种写法。现在**机制只有这一份**，各模块只提供自己的间隔常量。
///
/// 口径（沿用 2026-09-14 畅想之星那轮用户裁定，学习通模块照搬）：
/// - **窗口起点 = 上一次真的取到新数据的时刻**，不是「发出请求」的时刻 ——
///   请求在飞 / 失败时不该封锁窗口，否则一次网络抖动会让人一分钟内连重试都做不了。
/// - **只读不记账**：[allowsAutoRefresh] 不改变状态，调用方决定什么时候 [markUpdated]。
/// - **不受限的是手动路径**：手动下拉、错误卡「重试」、会话变更一律不看闸门，
///   由调用方绕开（各页面自己 `force: true` / 直接刷新）。
/// - **实例要跨页面重建存活**：挂在**非 autoDispose** 的 provider 上
///   （「进页面 → 返回 → 再进」每次都是新 State，记在 State 上等于没记账）。
library;

/// 自动刷新闸门（纯逻辑，时钟可注入 —— widget 测试里推不动真实 `DateTime.now()`）。
class RefreshGate {
  RefreshGate({required this.minInterval, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  /// 最小间隔（各模块自己的常量，如 `cxstarMinRefreshInterval`）。
  final Duration minInterval;

  /// 取当前时刻（测试注入假时钟以推进窗口）。
  final DateTime Function() _now;

  /// 上一次**真的取到新数据**的时刻（`null` = 本次运行还没取到过）。
  DateTime? lastUpdatedAt;

  /// 现在是否允许自动刷新（`null` = 还没取到过数据 → 放行）。**只读，不记账。**
  bool get allowsAutoRefresh {
    final last = lastUpdatedAt;
    if (last == null) return true;
    return _now().difference(last) >= minInterval;
  }

  /// 刚取到新数据 → 记账，重新开始一个窗口。
  void markUpdated() => lastUpdatedAt = _now();

  /// 距下次允许自动刷新还差多久（已在窗口外返回 [Duration.zero]）。
  Duration get remaining {
    final last = lastUpdatedAt;
    if (last == null) return Duration.zero;
    final left = minInterval - _now().difference(last);
    return left.isNegative ? Duration.zero : left;
  }

  /// 清空记账（测试 / 「清除本机数据」用）。
  void reset() => lastUpdatedAt = null;
}
