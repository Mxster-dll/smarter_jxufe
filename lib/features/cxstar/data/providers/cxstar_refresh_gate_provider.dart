import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/navigation/refresh_gate.dart';

/// 畅想之星「数据更新」的最小间隔。
///
/// 用户 2026-09-14 要求：「数据更新设置一个最小间隔（1min)」，并明确**仅限畅想之星**。
const Duration cxstarMinRefreshInterval = Duration(minutes: 1);

/// 畅想之星数据的「更新节流」闸门。
///
/// 口径：**窗口起点 = 上一次真的取到新数据的时刻** —— 就是统计卡上那行
/// 「统计更新于 HH:mm:ss」用的同一个时刻（`_CxstarScreenState` 的 listener 里
/// `markUpdated()` 与 `_updatedAt` 同时落），两者不会互相矛盾：卡片说「刚更新过」，
/// 页面就不会又偷偷再取一次。距该时刻不足 [cxstarMinRefreshInterval] 时，
/// **自动**刷新整组跳过；手动刷新与会话变更不受限。
///
/// **为什么记账要挂在 provider 上、不能记在页面 State 里**：窗口必须跨越页面重建 ——
/// 「畅想之星 → 返回 → 再进入」每次都是全新的 State，记在 State 上等于没记账，
/// 同一分钟内照样连发好几次同样的请求。provider 非 autoDispose，生命周期跨越页面。
///
/// **为什么按「取到新数据」而不是「发出请求」记账**：请求还在飞 / 失败时不该封锁窗口，
/// 否则一次网络抖动会让页面在一分钟内连重试都做不了。
///
/// 不受限（用户 2026-09-14 拍板）：手动下拉刷新、会话变更（统一认证 / 手工令牌 /
/// 清除令牌）、错误卡「重试」，以及结算补刷（`cxstarReturnSettleDelays`，专为平台
/// 批量结算设计）。
///
/// 机制本体 = [RefreshGate]（`lib/core/navigation/refresh_gate.dart`，2026-09-20 收敛）；
/// 本类只绑定畅想之星自己的间隔常量，字段与方法全部继承，调用方口径不变。
class CxstarRefreshGate extends RefreshGate {
  CxstarRefreshGate({DateTime Function()? clock})
    : super(minInterval: cxstarMinRefreshInterval, now: clock);
}

/// 闸门实例挂在容器上（非 autoDispose → 生命周期跨越页面重建）。
final cxstarRefreshGateProvider = Provider<CxstarRefreshGate>(
  (ref) => CxstarRefreshGate(),
);
