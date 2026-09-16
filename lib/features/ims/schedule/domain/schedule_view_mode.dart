/// 课表视图选型（横版 / 竖版）与「手机端」判定的**唯一口径**。
///
/// 用户 2026-09-15 裁定：「移动端取消切换横置/竖置按钮，而是适应屏幕是横屏
/// 还是竖屏」——即
/// - **手机平台**（Android / iOS）：**不给**切换按钮，按设备横竖屏自动选视图；
/// - **桌面平台**：保留手动切换按钮（`_isHorizontal`），窗口宽度只影响排版松紧。
///
/// 抽成纯函数（只吃 `TargetPlatform` + 宽高，不碰 BuildContext）是为了可测：
/// 守卫测试 `test/schedule_view_mode_test.dart` 直接断言这张真值表。
library;

import 'package:flutter/foundation.dart' show TargetPlatform;

/// 手机端排版断点：短边（或桌面窗口宽度）小于它即按手机排版。
///
/// `ScheduleGridView.compactBreakpoint` 直接引用本常量（同一个数，不许两处写死）。
const double scheduleCompactBreakpoint = 620.0;

/// 课表视图形态。
enum ScheduleViewMode {
  /// 竖版：12 行（节次）× 7 列（星期）。
  grid,

  /// 横版：12 列（节次）× 7 行（星期）。
  horizontal,
}

/// 是否手机平台 —— 决定「是否按横竖屏自动选视图 / 是否显示切换按钮」。
bool scheduleAutoViewByOrientation(TargetPlatform platform) =>
    platform == TargetPlatform.android || platform == TargetPlatform.iOS;

/// 当前该用哪个视图。
///
/// 手机：按横竖屏（宽 > 高 = 横屏 → 横版课表）；桌面：听用户的 [manualHorizontal]。
ScheduleViewMode scheduleViewModeFor({
  required TargetPlatform platform,
  required double width,
  required double height,
  required bool manualHorizontal,
}) {
  if (scheduleAutoViewByOrientation(platform)) {
    return width > height ? ScheduleViewMode.horizontal : ScheduleViewMode.grid;
  }
  return manualHorizontal ? ScheduleViewMode.horizontal : ScheduleViewMode.grid;
}

/// 是否按「手机端排版」收紧（左右无边距、字号收紧、学期码按钮）。
///
/// 手机平台恒 true（横竖屏都算手机）；桌面平台按窗口宽度——与从前
/// `width < compactBreakpoint` 的行为一致，不会让宽桌面窗口突然变紧。
bool scheduleCompactLayout({
  required TargetPlatform platform,
  required double width,
  double breakpoint = scheduleCompactBreakpoint,
}) => scheduleAutoViewByOrientation(platform) || width < breakpoint;

/// 是否启用「手机式输入」（左右滑动切周）。
///
/// 手机平台恒 true；桌面平台在窄窗口（短边 < 断点）下也启用 —— 与 2026-09-15
/// 之前的 `width < compactBreakpoint` 行为保持兼容。
bool scheduleMobileInput({
  required TargetPlatform platform,
  required double width,
  required double height,
  double breakpoint = scheduleCompactBreakpoint,
}) {
  if (scheduleAutoViewByOrientation(platform)) return true;
  final shortest = width < height ? width : height;
  return shortest < breakpoint;
}
