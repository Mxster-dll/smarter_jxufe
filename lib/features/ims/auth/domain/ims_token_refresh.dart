/// 「刷新教务登录令牌」的判定口径 —— 设置页按钮与 `ImsSession.probe()` 共用一处。
///
/// **用户 2026-09-15 裁定：先探活、失效才换。**
/// 按一下设置页的按钮时，先用当前令牌打一个最便宜的会话门控端点：
/// - 仍有效 → 只提示，**一次多余的 CAS 往返都不发**；
/// - 确认失效（教务回 547 字节「凭证已失效」alert 页）→ 重新换票；
/// - 本地根本没有令牌（首次使用 / 刚退出登录）→ 直接换票；
/// - 问不出结论（断网等）→ 也换票（用户按这个按钮就是要一张能用的令牌）。
///
/// 本文件是纯逻辑（无 Flutter / dio 依赖），守卫测试 `test/ims_token_refresh_test.dart`。
library;

import 'dart:convert';

/// 探活结论。
enum ImsProbeResult {
  /// 教务仍认这张令牌（此刻业务页面能正常取数）。
  alive,

  /// 教务回了「凭证已失效」alert 页 —— 需要换票。
  expired,

  /// 本地（内存 + 磁盘）都没有令牌。
  noSession,

  /// 网络异常等，问不出结论。
  unknown,
}

/// 探活之后该做什么。
enum ImsTokenRefreshAction {
  /// 令牌仍有效 —— 什么都不做。
  keepCurrent,

  /// 换票（`ImsSession.renew()`：CAS 取票 → 激活 → 落盘）。
  renew,
}

/// 探活结论 → 动作。
///
/// [ImsProbeResult.unknown] 也走换票：宁可多发一次换票（CAS 侧有 TGC 时是一次
/// 便宜的往返），也不要让按钮在「怪状态」下只会报错。
ImsTokenRefreshAction imsTokenRefreshActionFor(ImsProbeResult result) =>
    switch (result) {
      ImsProbeResult.alive => ImsTokenRefreshAction.keepCurrent,
      ImsProbeResult.expired ||
      ImsProbeResult.noSession ||
      ImsProbeResult.unknown => ImsTokenRefreshAction.renew,
    };

/// 探活响应的「有效」判据：教务的 JSON 信封（`{` 开头且能解成对象）。
///
/// **宁可判 unknown（进而照样换票），也不要把登录页 / 半截页当成有效**：
/// 只有这个方向是安全的 —— 把失效当成有效，用户会以为修好了、业务页却仍然打不开。
/// 失效一侧由 `jwSessionExpired` 精确识别（UTF-8 alert 页），不依赖本判据。
bool imsProbeBodyLooksValid(String body) {
  final text = body.trim();
  if (!text.startsWith('{')) return false;
  try {
    return jsonDecode(text) is Map;
  } catch (_) {
    return false;
  }
}

/// 令牌掩码：只露前 8 位（与设置页 GUID 同款口径，不把整张令牌铺在界面上）。
String maskImsToken(String token) =>
    token.length <= 8 ? token : '${token.substring(0, 8)}…';

/// 探活结论文案（卡片上「最近探活 …」那行）。
String imsProbeLabel(ImsProbeResult result) => switch (result) {
  ImsProbeResult.alive => '令牌有效',
  ImsProbeResult.expired => '令牌已失效',
  ImsProbeResult.noSession => '本地没有令牌',
  ImsProbeResult.unknown => '无法判定（网络异常）',
};

/// 按一下按钮之后给用户看的一句话（SnackBar 正文）。
String imsRefreshOutcomeText({
  required ImsProbeResult probe,
  required bool success,
}) {
  if (!success) return '刷新失败，请检查网络后重试';
  return switch (probe) {
    ImsProbeResult.alive => '当前登录令牌仍可用（未重复换票）',
    ImsProbeResult.expired => '令牌已失效，已重新登录并换票',
    ImsProbeResult.noSession => '本地没有令牌，已重新登录并换票',
    ImsProbeResult.unknown => '无法确认令牌状态（网络异常），已直接换票',
  };
}
