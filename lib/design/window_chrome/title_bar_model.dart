/// 标题栏**排布模型** —— 四区 × 四槽的**纯函数**（2026-10-10 重构，见 §43.5）。
///
/// 为什么要有这个文件：重构前「三键在哪侧 / 动作簇在哪侧 / 品牌显不显示 / 中间组怎么摆」
/// 全都散在 `window_title_bar.dart` 的 130 行 `build` 里，用一堆 `if (narrow && …)`、
/// `isMac && buttonsOnLeft ? … : …` 拼出来 —— 于是出了两个只有点开界面才发现的 bug ✗：
/// ① **mac 风格 + 交换三键 → 三键整个不可见**（判据写错一支，圆点没画、方键的字形透明度是 0）；
/// ② **窄屏下三键跟着动作簇一起漂到左边**（两件事共用一个 `AnimatedAlign`）。
///
/// 现在排布规则全在这里 ✓：**输入**宽度 / 平台 / 两项偏好 / 三区在不在，
/// **输出**四个槽位 —— 于是整张矩阵可以**不 pump 任何 widget** 地逐行断言
/// （`test/title_bar_model_test.dart`），上面那两个 bug 会先在表里照出来。
///
/// ⚠ 三区在不在由**调用方**告知（`hasActions` / `hasCenter` / `hasBrand`）：
/// 本文件不许 import 任何 provider / 页面 —— 它只做算术。
library;

import 'package:smarter_jxufe/design/breakpoints.dart';
import 'package:smarter_jxufe/features/settings/data/window_bar_prefs.dart';

/// 一个区可以待的地方。`hidden` = 这一档不画它。
enum TitleBarSlot { left, center, right, hidden }

/// 四个区的排布结果。
class TitleBarLayoutModel {
  const TitleBarLayoutModel({
    required this.narrow,
    required this.controls,
    required this.actions,
    required this.center,
    required this.brand,
    required this.macOrderReversed,
  });

  /// 是否处在「窄屏」档（= 手机那种形态）。
  final bool narrow;

  /// 窗口三键（最小化 / 最大化 / 关闭）。
  ///
  /// ⚠ **只由「三键左右互换」这一项偏好决定** —— 任何宽度下都不许动它
  /// （用户 2026-10-10：「我希望右上角三键位置不要漂移」）。
  final TitleBarSlot controls;

  /// 页面发布的动作簇（头像 + 设置）。窄屏时它还**捎带着中间组**（见 [center]）。
  final TitleBarSlot actions;

  /// 中间组：侧栏开关 + 路由历史。
  ///
  /// - 宽屏：恒 `center`（用户 2026-10-09：「都要放到标题栏中间」）；
  /// - 窄屏：**并入 [actions]**（用户 2026-10-10：「center 在窄屏和 actions 合并」）
  ///   → 本槽位 `hidden`，由 [actions] 那一侧一起承载。
  final TitleBarSlot center;

  /// 品牌（logo + 应用名）：宽屏摆在三键**对侧**；窄屏 `hidden`
  /// （用户 2026-10-10：「brand 在窄屏不显示」）。
  final TitleBarSlot brand;

  /// mac 风格且三键在左侧时，顺序要倒成「关闭 / 最小化 / 最大化」（mac 惯例）。
  ///
  /// ⚠ 交换位置**只改顺序、不改风格** —— 重构前那句 `isMac && buttonsOnLeft ? 圆点 : 方键`
  /// 把两件事混在一起，交换后画出来的方键字形透明度是 0 → 三键看不见 ✗。
  final bool macOrderReversed;

  /// 按「宽度 + 平台 + 两项偏好 + 各区在不在」算出排布。
  ///
  /// [hasHistory] / [hasSidebarToggle] 合成 [hasCenter]：两者都没有才叫「没有中间组」。
  factory TitleBarLayoutModel.compute({
    required double width,
    required bool desktop,
    required WindowButtonsStyle style,
    required bool swapSides,
    required bool hasActions,
    required bool hasBrand,
    required bool hasHistory,
    required bool hasSidebarToggle,
  }) {
    // 窄屏阈值**故意取 `Breakpoints.narrow`(600)** 而不是页面宫格⇄侧栏那条 900：
    // 顶栏满配大约 450px（三键 138 + 动作 ~70 + 中间组 ~100 + 品牌 ~140），600 时还有余量；
    // 而且用户明确说过 900 太高（用户 2026-10-10：「我希望降低窄屏阈值」）。
    final narrow = width < Breakpoints.narrow;
    final buttonsOnLeft =
        windowButtonsOnLeft(style: style, swapSides: swapSides);
    final controls = buttonsOnLeft ? TitleBarSlot.left : TitleBarSlot.right;
    // 三键的**对侧**：窄屏时动作簇（+ 中间组）摆这里。
    final opposite = buttonsOnLeft ? TitleBarSlot.right : TitleBarSlot.left;
    final hasCenter = hasHistory || hasSidebarToggle;

    if (narrow) {
      // 窄屏：品牌不画；中间组并入动作簇那一侧；三键不动。
      return TitleBarLayoutModel(
        narrow: true,
        controls: controls,
        // 「动作簇 + 中间组」合成一坨：有动作就由 actions 槽位承载，否则让 center 槽位承载
        // （两者都要摆到同一侧，谁在不在都不该改变那一侧的位置）。
        actions: hasActions ? opposite : TitleBarSlot.hidden,
        center: hasActions
            ? TitleBarSlot.hidden
            : (hasCenter ? opposite : TitleBarSlot.hidden),
        brand: TitleBarSlot.hidden,
        macOrderReversed: style == WindowButtonsStyle.mac && buttonsOnLeft,
      );
    }

    return TitleBarLayoutModel(
      narrow: false,
      controls: controls,
      // 宽屏：动作簇与三键**同侧紧挨**（桌面上它俩都是窗口级操作）。
      actions: hasActions ? controls : TitleBarSlot.hidden,
      center: hasCenter ? TitleBarSlot.center : TitleBarSlot.hidden,
      brand: hasBrand ? opposite : TitleBarSlot.hidden,
      macOrderReversed: style == WindowButtonsStyle.mac && buttonsOnLeft,
    );
  }
}
