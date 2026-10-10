// 本文件是 `lib/design/window_chrome/` 拆分件之一 —— 文件地图见 docs/agents/43 的 §43.5。
// 公开入口仍是 `package:smarter_jxufe/design/window_title_bar.dart`（桶文件，对外零改动）。

import 'package:flutter/material.dart';

import 'package:smarter_jxufe/core/window/window_chrome.dart';
import 'package:smarter_jxufe/design/window_chrome/app_window_chrome.dart';
import 'package:smarter_jxufe/features/settings/data/window_bar_prefs.dart';

/// 三键之一（**纯视觉**：点击由原生处理，悬停 / 按下态由原生推回）。
///
/// 两项设置的切换是**动画**的：槽宽在 46（Win 方键）↔ 20（mac 圆点）之间补间，
/// codicon 字形与圆点**交叉淡入淡出**（同一棵树，不是换树 —— 换树那一下会闪）。
class WindowButton extends StatelessWidget {
  const WindowButton({
    super.key,
    required this.snapshot,
    required this.button,
    required this.style,
  });
  final WindowChromeSnapshot snapshot;
  final WindowTitleBarButton button;
  final WindowButtonsStyle style;
  @override
  Widget build(BuildContext context) {
    final isMac = style == WindowButtonsStyle.mac;
    return TweenAnimationBuilder<double>(
      // `end` 变 → Flutter 从**当前值**补间到新值（这正是「槽宽 46↔20 是补间」）。
      tween: Tween<double>(end: isMac ? 1 : 0),
      duration: kWindowTitleBarSwitchDuration,
      curve: kWindowTitleBarSwitchCurve,
      builder: (context, t, _) => SizedBox(
        width: kWindowTitleBarMacSlot +
            (kWindowTitleBarButtonWidth - kWindowTitleBarMacSlot) * (1 - t),
        height: kWindowTitleBarHeight,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Win 视觉：方键底 + codicon 字形 —— 与圆点对称：只在「非 mac 或正在形变」时进树
            // （mac 终态若还留着 Icon，守卫「形变中途两套视觉同时在」的收尾断言会红）。
            if (!isMac || t < 1)
              Opacity(
                opacity: 1 - t,
              child: _WinKeyFace(
                snapshot: snapshot,
                button: button,
                width: kWindowTitleBarMacSlot +
                    (kWindowTitleBarButtonWidth - kWindowTitleBarMacSlot) * (1 - t),
              ),
            ),
            // mac 视觉：圆点 —— **只在 mac 风格或正在形变时进树**：纯 Win 时它不该存在
            // （守卫「形变中途两套视觉同时在」先在起始帧断言它不存在，再在中途断言它出现）。
            if (isMac || t > 0)
              Opacity(
                opacity: t,
                child: _MacDotFace(snapshot: snapshot, button: button),
              ),
          ],
        ),
      ),
    );
  }
}
class _WinKeyFace extends StatelessWidget {
  const _WinKeyFace({
    required this.snapshot,
    required this.button,
    required this.width,
  });
  final WindowChromeSnapshot snapshot;
  final WindowTitleBarButton button;
  final double width;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = snapshot.active &&
        (snapshot.hovered == button || snapshot.pressed == button);
    final isClose = button == WindowTitleBarButton.close;
    final glyph = switch (button) {
      WindowTitleBarButton.minimize => Codicons.chromeMinimize,
      WindowTitleBarButton.maximize =>
        snapshot.maximized ? Codicons.chromeRestore : Codicons.chromeMaximize,
      WindowTitleBarButton.close => Codicons.chromeClose,
    };
    return Container(
      width: width,
      height: kWindowTitleBarHeight,
      color: active
          ? (isClose
              ? const Color(0xFFC42B1C)
              : scheme.onSurface.withValues(alpha: 0.09))
          : Colors.transparent,
      child: Center(
        child: Icon(
          glyph,
          size: kWindowTitleBarGlyphSize,
          color: isClose && active ? Colors.white : scheme.onSurface,
        ),
      ),
    );
  }
}
class _MacDotFace extends StatelessWidget {
  const _MacDotFace({required this.snapshot, required this.button});
  final WindowChromeSnapshot snapshot;
  final WindowTitleBarButton button;
  @override
  Widget build(BuildContext context) {
    final fill = switch (button) {
      WindowTitleBarButton.close => const Color(0xFFFF5F57),
      WindowTitleBarButton.minimize => const Color(0xFFFEBC2E),
      WindowTitleBarButton.maximize => const Color(0xFF28C840),
    };
    return Container(
      width: kWindowTitleBarMacDot,
      height: kWindowTitleBarMacDot,
      decoration: BoxDecoration(
        color: snapshot.active ? fill : fill.withValues(alpha: 0.55),
        shape: BoxShape.circle,
      ),
    );
  }
}

/// 三键**整行**的组装：风格（win 方键 / mac 圆点）+ 顺序（mac 在左侧时「关闭」打头）。
///
/// ⚠ 重构前这里是 `isMac && buttonsOnLeft ? 圆点 : 方键` ✗ —— 把「风格」和「在哪一侧」
/// 混成了一个判据：mac 风格 + 交换三键时走 else 画方键，而方键的字形透明度是
/// `1 - macReveal` = 0 → **三键整个看不见**（用户 2026-10-10 报的 bug）。
/// 现在风格只认 [style]，位置只决定**顺序**（[macOrderReversed]）。
class WindowButtonsRow extends StatelessWidget {
  const WindowButtonsRow({
    super.key,
    required this.snapshot,
    required this.style,
    required this.macOrderReversed,
    required this.macClusterOnLeft,
    required this.region,
  });

  final WindowChromeSnapshot snapshot;
  final WindowButtonsStyle style;

  /// mac 风格且三键在左侧 → 顺序倒成「关闭 / 最小化 / 最大化」（mac 惯例）。
  final bool macOrderReversed;

  /// 三键整组靠窗口哪一侧（mac 风格要在**外侧**补整组留白）。
  final bool macClusterOnLeft;

  /// 把一枚三键登记成交互区（由栏本体提供 —— 登记要进它那份 `interactive` 名单）。
  final Widget Function(Object token, Widget child) region;

  @override
  Widget build(BuildContext context) {
    final order = macOrderReversed
        ? const [
            WindowTitleBarButton.close,
            WindowTitleBarButton.minimize,
            WindowTitleBarButton.maximize,
          ]
        : const [
            WindowTitleBarButton.minimize,
            WindowTitleBarButton.maximize,
            WindowTitleBarButton.close,
          ];
    // mac 风格：三键**整组**外侧补 kWindowTitleBarMacClusterInset —— 圆点在 20 宽的槽里
    // 居中自带 (20-12)/2 = 4，加上这 10 就与「距栏上下边的 14」对齐（用户 2026-10-09 四轮：
    // 「mac 三键作为一个整体，其距离标题栏上下边距与侧边边距要一致」）。Win 方键贴边，不补。
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final button in order)
          region(
            switch (button) {
              WindowTitleBarButton.minimize => 'minimize',
              WindowTitleBarButton.maximize => 'maximize',
              WindowTitleBarButton.close => 'close',
            },
            WindowButton(
              key: Key('windowButton-${button.name}'),
              snapshot: snapshot,
              button: button,
              style: style,
            ),
          ),
      ],
    );
    // ⚠ **结构必须恒定**：这里若写成 `if (style != mac) return row;`，换风格时树会从
    // `Row` 变成 `Padding(Row)` → 按钮的 element 被重建 → `TweenAnimationBuilder`
    // 从「起点」重来（`Tween(end:)` 的 begin 为 null → 直接取终值）→ 槽宽一步到位 ✗
    // （守卫「换风格：槽宽 46 ↔ 20 是补间」实测就是这么红的）。Win 风格只是 padding 为零。
    return Padding(
      padding: style == WindowButtonsStyle.mac
          ? (macClusterOnLeft
              ? const EdgeInsets.only(left: kWindowTitleBarMacClusterInset)
              : const EdgeInsets.only(right: kWindowTitleBarMacClusterInset))
          : EdgeInsets.zero,
      child: row,
    );
  }
}

/// Windows 三键的 **codicon** 字形（用户 2026-10-09 指定「照 vshell」）。
///
/// ⚠ **跨语言契约**：`assets/fonts/codicon-titlebar.ttf` 只裁了这四个字形，`pubspec.yaml`
/// 以 `codicon` 注册（子集命令与来源留在 pubspec 注释里）。守卫 =
/// `test/window_title_bar_test.dart` 的「codicon 子集字体」+「跨语言契约」两组。
class Codicons {
  const Codicons._();

  /// 字形族名 —— **跨语言契约的一部分**：`pubspec.yaml` 以这个名字注册裁好的子集字体，
  /// 原生与 Dart 两侧都按它取字形。守卫按源码字面量 `fontFamily = 'codicon'` 记账。
  static const String fontFamily = 'codicon';

  static const IconData chromeMinimize =
      IconData(0xeaba, fontFamily: fontFamily);
  static const IconData chromeMaximize =
      IconData(0xeab9, fontFamily: fontFamily);
  static const IconData chromeRestore =
      IconData(0xeabb, fontFamily: fontFamily);
  static const IconData chromeClose = IconData(0xeab8, fontFamily: fontFamily);
}