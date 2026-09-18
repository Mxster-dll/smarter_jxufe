/// 应用统一卡片语言（2026-09-15 立 · 用户口径：全应用卡片统一为「综合测评 > 评测结果卡」形态）。
///
/// **唯一口径来源**：卡片的形状 / 底色 / 边框 / 强调色只在本文件定义，别处一律引用，
/// 不要在页面里再写一套 `BorderRadius.circular(…)` + `BorderSide(…)`。
///
/// - 形状 = 圆角 12 + `outlineVariant` 60% 淡边框（无阴影；深色下改为 `outlineVariant` 原值，
///   即 `rgba(255,255,255,.10)`，见 [appCardBorderSide]）
/// - 底色 = 纯白（浅色）/ `#1A1A1A`（深色 A 中性深灰），见 [appCardColorOf]
/// - 内边距 = 14
/// - 强调色 = `colorScheme.primary`（浅色校红 `#C3282E` / 深色亮红 `#F2555A`，
///   用户裁定：单色强调一律改红）
///
/// 覆盖路径有两条：`lib/main.dart` 的全局 `cardTheme`（所有 `Card(`）+ [appCardShape]
/// （显式写 shape 的 `Card`/`Material`，含 `geCardShape` 的 48 处调用点）。
library;

import 'package:flutter/material.dart';

import 'app_ladder.dart';
import 'feature_palette.dart';

/// 卡片圆角。
const double kAppCardRadius = 12;

/// 卡片默认内边距。
const double kAppCardPadding = 14;

/// 浅色卡片底色（纯白；不用 `colorScheme.surfaceContainerLow` —— 那是 #FAFAFA）。
const Color kAppCardColor = Color(0xFFFFFFFF);

/// 深色卡片底色（A 中性深灰的 `--card`；与顶栏同色）。
const Color kAppCardColorDark = AppLadder.darkCard;

/// 按亮度取卡片底色（浅色纯白 / 深色 `#1A1A1A`）。
Color appCardColorOf(ColorScheme scheme) =>
    scheme.brightness == Brightness.dark ? kAppCardColorDark : kAppCardColor;

/// 按亮度取卡片底色（有 context 的写法）。
Color appCardColor(BuildContext context) =>
    appCardColorOf(Theme.of(context).colorScheme);

/// 卡片描边。
///
/// 浅色 = `outlineVariant` 的 60% 透明度（目标样式的原始取值）；
/// 深色 = `outlineVariant` 原值 —— 深色主题里它本身就是 `rgba(255,255,255,.10)`
/// （用户拍板的 A 档 `--border`），再乘 0.6 会淡到看不见。
BorderSide appCardBorderSide(ColorScheme scheme) => BorderSide(
  color: scheme.brightness == Brightness.dark
      ? scheme.outlineVariant
      : scheme.outlineVariant.withValues(alpha: 0.6),
);

/// 由 [ColorScheme] 直接构造卡片形状（给 `ThemeData`/`CardThemeData` 这类没有 context 的地方用）。
RoundedRectangleBorder appCardShapeOf(ColorScheme scheme) =>
    RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(kAppCardRadius),
      side: appCardBorderSide(scheme),
    );

/// 卡片形状（页面里给 `Card`/`Material` 用）。
RoundedRectangleBorder appCardShape(BuildContext context) =>
    appCardShapeOf(Theme.of(context).colorScheme);

/// 全局 `Card` 主题：一次覆盖全应用所有 `Card(`。
///
/// ⚠️ 刻意**不设 `margin`**：`Card` 默认外边距 4，改动它会连带改变所有页面的卡间距
/// （那不是本次「统一样式」的范围）。
CardThemeData appCardTheme(ColorScheme scheme) => CardThemeData(
  color: appCardColorOf(scheme),
  // 高度叠加色设透明：M3 默认取 primary 系，卡片抬起时会再染一层红。
  surfaceTintColor: const Color(0x00000000),
  elevation: 0,
  shape: appCardShapeOf(scheme),
);

/// 卡片强调色 = 主题红 `colorScheme.primary`（标题竖条 / 图标 / 图标底统一用它）。
Color appCardAccent(BuildContext context) =>
    Theme.of(context).colorScheme.primary;

/// 卡片强调色的淡底（图标底板等，浅色 alpha 0.10 与首页磁贴口径一致）。
///
/// ⚠ **深色下不能还是 0.10**：深底会把低 alpha 的淡色整块吞掉
/// （`#F2555A @ 10%` 叠卡片 `#1A1A1A` 对卡片只有 **1.12:1**，图标底板等于没画），
/// 深色侧一律走 `AppLadder.darkTintAlpha`（与 `AppColors.tint` 同一口径）。
Color appCardAccentSoft(BuildContext context) => appCardAccent(context)
    .withValues(
      alpha: Theme.of(context).brightness == Brightness.dark
          ? AppLadder.darkTintAlpha(0.10)
          : 0.10,
    );

/// 卡片强调色常量（= 主题 primary 的实际取值 `#C3282E`，登记在 [FeaturePalette.cardAccent]）。
///
/// 给「静态 helper / `const` 字段」这类拿不到 `BuildContext` 的地方用；
/// 有 context 时优先用 [appCardAccent]（跟着主题走）。两处同值，不会漂移。
const Color kAppCardAccent = FeaturePalette.cardAccent;

/// [kAppCardAccent] 的 10% 淡底常量。
///
/// ⚠ 这是**编译期常量**，拿不到主题，所以它恒等于浅色档；
/// 只要手边有 `BuildContext`，淡底就该用 [appCardAccentSoft]（深色下会自动抬 alpha）。
const Color kAppCardAccentSoft = FeaturePalette.cardAccentSoft;

/// 「综测评测结果卡」形态的纯装饰卡片容器（不含 Material ink）。
///
/// 需要点击/涟漪时用 `Material(color: appCardColor(context), shape: appCardShape(context))`，
/// 而不是本函数。
Widget appCard(
  BuildContext context, {
  required Widget child,
  EdgeInsetsGeometry padding = const EdgeInsets.all(kAppCardPadding),
  Color? color,
}) => Container(
  padding: padding,
  decoration: BoxDecoration(
    color: color ?? appCardColorOf(Theme.of(context).colorScheme),
    borderRadius: BorderRadius.circular(kAppCardRadius),
    border: Border.all(
      color: appCardBorderSide(Theme.of(context).colorScheme).color,
    ),
  ),
  child: child,
);
