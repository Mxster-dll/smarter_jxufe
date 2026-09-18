/// 应用主题的**唯一出处**：浅色 / 深色两套 `ColorScheme` + `ThemeData` + 语义色取用口径。
///
/// ## 口径（改前先读）
/// - **浅色 = 现状逐值不变**：`ColorScheme.fromSeed(校徽红 #C3282E)` + `.copyWith()`
///   把白色系覆写为中性灰白（§3「主题纯白」：白系一律 R=G=B，**不从 primary 派生**）；
///   文字色（`onSurface` / `onSurfaceVariant` / `outline`）仍是种子的暖灰 —— 用户
///   2026-09-14 裁定「只改白色系」，别顺手改。
/// - **深色 = A · 中性深灰**：用户 2026-09-16 在 `design_preview/dark_mode_preview.html`
///   看过「浅色 / A 中性深灰 / B 纯黑 / C Fluent 深色」四列对比后拍板 A。
///   底色阶梯 / 文字 / 描边的取值逐值来自 `lib/design/app_ladder.dart`（转自预览的 CSS 变量）。
/// - **深色下底阶方向与浅色相反**（M3 语义）：`surfaceContainerLowest` 最暗 →
///   `surfaceContainerHighest` 最亮。映射：`surface`/`Lowest` = `#121212`（页面底）、
///   `Low` = `#1A1A1A`（**卡片色 = 顶栏色**）、`Container` = `#1E1E1E`、
///   `High` = `#242424`、`Highest` = `#2C2C2C`。
/// - **深色强调色 = 亮红档 [kBrandRedDark]**（`#F2555A`）；浅色仍是校徽红 [kBrandRed]。
/// - `surfaceTint` 两侧都设成「底色本身」（中性、不着色）：浅色白、深色 `#121212`。
///   否则 AppBar / Card 抬起时会再染一层红。
///
/// ## 页面侧怎么取色
/// 中性色 / 文字色一律走 `Theme.of(context).colorScheme`（或用下面 [AppColors] 的语义捷径，
/// 它给出与裸色 `Colors.grey.shadeXXX` 一一对应的深浅两档）；**不要**再写
/// `Colors.white` / `Colors.black` / `Colors.grey` 这类不随亮度变化的裸色 ——
/// 深色下它们不是隐形就是刺眼。功能强调色走 `lib/design/feature_palette.dart` 的
/// `fp(context).xxx`（深色下自动提亮）。
///
/// 模式切换（跟随系统 / 浅色 / 深色）的偏好存储见
/// `lib/features/settings/data/theme_prefs.dart`，入口在设置页「外观」节。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_card.dart';
import 'app_ladder.dart';
import 'app_page_transitions.dart';
import 'feature_palette.dart';

export 'app_ladder.dart';

/// 校徽红 —— 浅色主题强调色（= `FeaturePalette.cardAccent`）。
const Color kBrandRed = Color(0xFFC3282E);

/// 深色主题强调色（亮红档）。用户 2026-09-16 拍板：深色下提亮为亮红档；
/// 同日上机后反馈「太浅」→ 已由 `#FF6B6E` 回调到 `#F2555A`（见该常量注释）。
/// 取值登记在 `FeaturePalette.cardAccentDark`（§3：颜色一律登记在 feature_palette）。
const Color kBrandRedDark = FeaturePalette.cardAccentDark;

/// 深色主题的「错误红」。
///
/// ⚠ 必须显式覆写：`ColorScheme.fromSeed(brightness: dark)` 给的是 M3 深色错误色
/// **`#FFB4AB`** —— 一种极淡的粉红（在 #121212 上 11.03:1，几乎发白）。
/// 成绩页的错误标记、虚框与进度条都吃这个色，用户 2026-09-16 反馈
/// 「成绩页的红色太浅了」指的就是它。这里换成真正的红，并保持与浅色相同的
/// 相对关系（浅色 `primary #C3282E` / `error #BA1A1A` → error 比 primary **略深**）。
const Color kErrorRedDark = Color(0xFFEE4C50);

/// 浅色主题配色（逐值 = 改动前 `lib/main.dart` 里的 `_appScheme`）。
final ColorScheme appLightScheme = ColorScheme.fromSeed(
  seedColor: kBrandRed,
).copyWith(
  primary: kBrandRed,
  surface: AppLadder.lightSurface,
  surfaceContainerLowest: AppLadder.lightSurfaceLowest,
  surfaceContainerLow: AppLadder.lightSurfaceLow,
  surfaceContainer: AppLadder.lightSurfaceContainer,
  surfaceContainerHigh: AppLadder.lightSurfaceHigh,
  surfaceContainerHighest: AppLadder.lightSurfaceHighest,
  surfaceTint: AppLadder.lightSurface,
);

/// 深色主题配色（A 中性深灰 + 亮红强调）。
final ColorScheme appDarkScheme = ColorScheme.fromSeed(
  seedColor: kBrandRed,
  brightness: Brightness.dark,
).copyWith(
  primary: kBrandRedDark,
  onPrimary: AppLadder.darkOnPrimary,
  // M3 深色默认错误色是淡粉 #FFB4AB（发白）→ 换成真正的红，前景跟着翻成深字
  // （深字压 #EE4C50 = 4.79:1；原来的 onError #690005 压它只有 3.61:1）。
  error: kErrorRedDark,
  onError: AppLadder.darkOnPrimary,
  surface: AppLadder.darkSurface,
  surfaceContainerLowest: AppLadder.darkSurfaceLowest,
  surfaceContainerLow: AppLadder.darkSurfaceLow,
  surfaceContainer: AppLadder.darkSurfaceContainer,
  surfaceContainerHigh: AppLadder.darkSurfaceHigh,
  surfaceContainerHighest: AppLadder.darkSurfaceHighest,
  surfaceTint: AppLadder.darkSurface,
  // 中性色系（§3「纯白」口径的深色对偶：R=G=B，不从 primary 派生）。
  onSurface: AppLadder.darkOnSurface,
  onSurfaceVariant: AppLadder.darkOnSurfaceVariant,
  outline: AppLadder.darkOutline,
  outlineVariant: AppLadder.darkOutlineVariant,
);

/// 字体口径（两套主题共用）。
const String _fontFamily = 'Cascadia Code';
const List<String> _fontFallback = <String>['霞鹜文楷', '仓耳今楷01'];

ThemeData _themeOf(ColorScheme scheme, {required bool dark}) {
  final ThemeData base = ThemeData(
    colorScheme: scheme,
    cardTheme: appCardTheme(scheme),
    pageTransitionsTheme: appPageTransitionsTheme,
    fontFamily: _fontFamily,
    fontFamilyFallback: _fontFallback,
  );
  // 深色只**补**下面几项；浅色一个字段都不加，确保与改动前逐值一致。
  if (!dark) return base;
  return base.copyWith(
    // 顶栏：深色下恒为卡片同色（#1A1A1A），不随滚动抬高变色。
    // 浅色现状是 `surface` 白 + `surfaceTint` 白，效果等价，故不必特判。
    appBarTheme: const AppBarThemeData(
      backgroundColor: AppLadder.darkTopBar,
      surfaceTintColor: Color(0x00000000),
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    // 未显式指定颜色的 `Divider()` 默认值。
    dividerTheme: const DividerThemeData(color: AppLadder.darkDivider),
    dividerColor: AppLadder.darkDivider,
  );
}

/// 浅色主题（逐值 = 改动前的 `lib/main.dart` 内联 ThemeData）。
final ThemeData appLightTheme = _themeOf(appLightScheme, dark: false);

/// 深色主题。
final ThemeData appDarkTheme = _themeOf(appDarkScheme, dark: true);

/// 语义色取用口径：把「裸色」翻译成随亮度自适应的角色色。
///
/// **页面侧一律用这里**，不要写 `Colors.white` / `Colors.black` / `Colors.grey` /
/// `Colors.green.shade800` 这类不随亮度变化的常量 —— 深色下它们不是隐形就是刺眼。
/// 下面是「原来的裸色 → 现在的写法」对照：
///
/// | 原来的裸色 | 换成 |
/// |---|---|
/// | `Colors.white`（卡片底） | `AppColors.card(context)` |
/// | `Colors.grey.shade50` | `AppColors.fillSoft(context)` |
/// | `Colors.grey.shade100` | `AppColors.fill(context)` |
/// | `Colors.grey.shade200` | `AppColors.fillStrong(context)` |
/// | `Colors.grey.shade300/400` | `AppColors.fillStronger(context)` / `AppColors.stroke(context)` |
/// | `Colors.black87` / `Colors.black` | `AppColors.textBase(context)` |
/// | `Colors.grey.shade600/700` / `Colors.black54` / `Colors.grey` | `AppColors.textMuted(context)` |
/// | `Colors.green.shade700/800` | `AppColors.success(context)` |
/// | `Colors.orange.shade800` | `AppColors.caution(context)` |
/// | `Colors.red.shade700/800` | `AppColors.critical(context)` |
/// | `Colors.blue.shade700/800` | `AppColors.info(context)` |
/// | `X.withValues(alpha: .12)` 的状态淡底 | `AppColors.successFill/CautionFill/...` |
/// | `Colors.white`（**画在固定彩色底上的文字/图标**） | **保留不动** |
/// | `Colors.white70/60/54/24`、`Colors.black26`（同上，或阴影/遮罩） | **保留不动** |
/// WCAG 对比度（与 `design_preview/dark_mode_preview.html` 的 `contrast()` 同实现）。
double _contrastRatio(Color a, Color b) {
  double lum(Color c) {
    double ch(int v) {
      final x = v / 255;
      return x <= 0.03928 ? x / 12.92 : math.pow((x + 0.055) / 1.055, 2.4).toDouble();
    }

    final r = ch((c.toARGB32() >> 16) & 0xFF);
    final g = ch((c.toARGB32() >> 8) & 0xFF);
    final b = ch(c.toARGB32() & 0xFF);
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }

  final la = lum(a);
  final lb = lum(b);
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// 浅色侧的**基准稀释档**：全应用最常用的 `outlineVariant` 稀释比例（也是
/// `app_card.dart` 的口径）。深色侧把同一比例搬到 `AppLadder.darkOutlineVariant`
/// （10% 白）这个新基准上，见 `AppColors.hairline`。
const double _hairlineLightReference = 0.6;

abstract final class AppColors {
  /// 当前是否深色。
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  /// 任意「白底可读」的深色调 → 深色下自动提亮（浅色原样返回）。
  /// 提亮口径见 `feature_palette.dart` 的 `featureTone`。
  static Color tone(BuildContext context, Color light) =>
      isDark(context) ? featureTone(light) : light;

  // ── 卡片 / 底 ────────────────────────────────────────────────────────────
  /// 卡片底（浅色纯白，深色 `#1A1A1A`）。原本写 `Colors.white` 的卡片底用它。
  static Color card(BuildContext context) =>
      appCardColorOf(Theme.of(context).colorScheme);

  /// 页面底。
  static Color page(BuildContext context) =>
      Theme.of(context).colorScheme.surface;

  /// **比卡片再退一层的页面底**（浅色 `#F5F5F5` / 深色 `#121212`）。
  ///
  /// 用在「白卡片浮在灰底上、只靠投影区分」的页面（登录页）。别用 `fill()` 代替：
  /// 深色阶梯里 `surfaceContainer`(#1E1E1E) 比卡片 `#1A1A1A` **更亮**，
  /// 会把「卡片浮起」的关系整个倒过来；只有 `surface`(#121212) 在两种模式下
  /// 都严格暗于卡片底。
  static Color recessed(BuildContext context) => isDark(context)
      ? AppLadder.darkSurface
      : Theme.of(context).colorScheme.surfaceContainer;

  // ── 中性填充（原本的 `Colors.grey.shadeXX`）──────────────────────────────
  /// 极淡填充（原 `Colors.grey.shade50`）：`#FAFAFA` / `#1A1A1A`。
  static Color fillSoft(BuildContext context) =>
      Theme.of(context).colorScheme.surfaceContainerLow;

  /// 淡填充（原 `Colors.grey.shade100`）：`#F5F5F5` / `#1E1E1E`。
  static Color fill(BuildContext context) =>
      Theme.of(context).colorScheme.surfaceContainer;

  /// 中填充（原 `Colors.grey.shade200`）：`#F0F0F0` / `#242424`。
  static Color fillStrong(BuildContext context) =>
      Theme.of(context).colorScheme.surfaceContainerHigh;

  /// 强填充（原 `Colors.grey.shade300`）：`#EBEBEB` / `#2C2C2C`。
  static Color fillStronger(BuildContext context) =>
      Theme.of(context).colorScheme.surfaceContainerHighest;

  /// 中性描边（原 `Colors.grey.shade300/400`）：`outlineVariant`
  /// （深色下 = `rgba(255,255,255,.10)`）。
  ///
  /// ⚠ **这是本应用「描边」的唯一口径，别为了「浅色零漂移」换成 `fillStronger`。**
  /// 三点理由：
  /// 1. §3「主题纯白」明确裁定「**文字色（`onSurface` / `onSurfaceVariant` / `outline`）
  ///    仍是种子的暖灰**，只改白色系」—— 浅色下 `outlineVariant` = `#D8C2C0`（暖灰，
  ///    比中性的 `grey.shade300` `#E0E0E0` 多 R−B = +24）。这是**被批准的**取值，不是漂移；
  ///    全应用每一张卡片的描边（`app_card.dart` 的 `outlineVariant` 60%）本来就是这个暖调。
  /// 2. 深色下必须是**带 alpha 的白**（`0x1AFFFFFF`）：它要同时落在页面底 `#121212`、
  ///    卡片 `#1A1A1A`、容器 `#1E1E1E` 三种底上并自适应。换成实色 `fillStronger`(#2C2C2C)
  ///    会在 `#121212` 上变硬线、在 `#1E1E1E` 上几乎看不见 —— 那是**深色侧的真回归**。
  /// 3. 历史映射本身是混的：23 处 `AppColors.stroke(` 里只有约 11 处原本是中性
  ///    `grey.shade300/400`，其余的原文就已经是暖的 `outlineVariant` —— 改 token 会
  ///    修好一半、弄坏另一半。
  static Color stroke(BuildContext context) =>
      Theme.of(context).colorScheme.outlineVariant;

  // ── 文字 ─────────────────────────────────────────────────────────────────
  /// 正文色（原 `Colors.black87` / `Colors.black`）。
  static Color textBase(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface;

  /// 次级文字（原 `Colors.grey.shade600/700` / `Colors.black54` / `Colors.grey`）。
  static Color textMuted(BuildContext context) =>
      Theme.of(context).colorScheme.onSurfaceVariant;

  // ── 状态色（浅色 = Material 700~800 档，深色 = 由 `featureTone` 提亮）────
  static Color success(BuildContext context) =>
      tone(context, FeaturePalette.grade);
  static Color caution(BuildContext context) =>
      tone(context, FeaturePalette.volunteer);
  static Color critical(BuildContext context) =>
      tone(context, FeaturePalette.zongce);
  static Color info(BuildContext context) =>
      tone(context, FeaturePalette.schedule);

  /// **压在任意「强调色实心底」上的前景色**（角标 / 选中态 chip / 实心圆）。
  ///
  /// 为什么必须有这个函数：深色下功能色被 `featureTone` **提亮**，实心底就从
  /// 「暗底」翻成「亮底」，而原来写死的 `Colors.white` 会瞬间掉到读不了：
  /// 实测白字压在提亮后的色上 —— `makeUpClass`(#75C779) **2.08:1**、
  /// `reschedule`(#E77755) **2.93:1**、`classCancelled`(#9E9E9E) **2.68:1**、
  /// `deadlineOther`(#90A3AC) **2.70:1**（9–13px 小字，需要 4.5:1）。
  ///
  /// ⚠ **浅色恒返回白**，不做「亮底压深字」—— 浅色是逐像素冻结的基线，
  /// 像 `classCancelled`(#9E9E9E) 这种浅色下本来就偏亮的底，按亮度择字会把浅色也改掉。
  /// 只在**深色**里按底的亮度择字，缺陷只修深色那一侧。
  static Color onAccent(BuildContext context, Color background) {
    if (!isDark(context)) return const Color(0xFFFFFFFF);
    // 深色：在「白」与「近黑」里挑**实测对比度更高**的那个。
    // ⚠ 不要用 `ThemeData.estimateBrightnessForColor` —— 它的判据
    // `(L+0.05)² > 0.15 ⇔ L > 0.337` 太钝：提亮后的 `#E77755`(L=0.31) 会被判成
    // 「暗底 → 用白字」，而白字只有 2.93:1、深字却有 5.95:1（实测）。
    const white = Color(0xFFFFFFFF);
    final ink = AppLadder.darkOnPrimary;
    return _contrastRatio(white, background) >= _contrastRatio(ink, background)
        ? white
        : ink;
  }

  /// 状态色的淡底（原 `Colors.green.withValues(alpha: .12)` 这类写法）。
  /// 深色下提高不透明度，否则在深底上几乎看不见。
  ///
  /// ⚠ 与 [tint] 的分工：本函数用于**浅色本来就是 0.12** 的状态胶囊底；
  /// 浅色 alpha 不是 0.12 的淡底（如警示面板的 0.05/0.06）走 [tint]，
  /// 由调用方把原来的浅色 alpha 传进去，浅色侧才不会被本函数改掉。
  /// 深色档 = `AppLadder.darkSoftAlpha`（也是 [tint] 的封顶值，全应用同一个上限）。
  static Color statusFill(BuildContext context, Color accent) =>
      accent.withValues(alpha: isDark(context) ? AppLadder.darkSoftAlpha : 0.12);

  static Color successFill(BuildContext context) =>
      statusFill(context, success(context));
  static Color cautionFill(BuildContext context) =>
      statusFill(context, caution(context));
  static Color criticalFill(BuildContext context) =>
      statusFill(context, critical(context));
  static Color infoFill(BuildContext context) =>
      statusFill(context, info(context));

  // ── 半透明淡底 / 淡描边（2026-09-16 立 · 第三类红缺陷）──────────────────
  //
  // 用户 2026-09-16 原话：「我说的是成绩页的按钮背景，卡片的框线，太浅了」。
  // 实心件与描边已由上面那组（`errorFill` / `errorBorder`）修掉；这一组修的是
  // **淡色底**：全应用 8 处警示面板写 `scheme.error.withValues(alpha: 0.05/0.06)`，
  // 浅色下是白底上一层看得见的粉，深色下同一个 alpha 叠在卡片 `#1A1A1A` 上
  // → 混成 `#201A1A`（ΔL≈0.003），与卡片底肉眼无异 —— 面板等于不存在。
  //
  // 口径：**深色按比例抬 alpha，浅色原样透传**（浅色逐像素冻结）。
  // 换算依据与实测见 `AppLadder.darkTintAlpha` / `darkBorderAlpha`。

  /// 半透明**淡底**（警示面板 / 节选底 / 选中 chip 底 / 浅色块）。
  ///
  /// `lightAlpha` = **调用方原来在浅色下用的 alpha**，浅色侧原样使用（不漂移）；
  /// 深色侧换成 `AppLadder.darkTintAlpha(lightAlpha)`。
  ///
  /// 用法：`AppColors.tint(context, scheme.error, 0.06)`。
  /// ⚠ 压在实心强调色上、需要前景对比的底走 `errorFill` / `statusFill`，不是这个。
  static Color tint(BuildContext context, Color accent, double lightAlpha) =>
      accent.withValues(
        alpha: isDark(context)
            ? AppLadder.darkTintAlpha(lightAlpha)
            : lightAlpha,
      );

  /// 半透明**淡描边**（警示面板的框线 / 淡色边框）。`lightAlpha` 口径同 [tint]。
  ///
  /// ⚠ 不透明的**实心**红描边走 [errorBorder]，不要用这个。
  static Color tintBorder(
    BuildContext context,
    Color accent,
    double lightAlpha,
  ) => accent.withValues(
    alpha: isDark(context)
        ? AppLadder.darkBorderAlpha(lightAlpha)
        : lightAlpha,
  );

  // ── 红实心件 / 红描边（2026-09-16 立）────────────────────────────────────
  //
  // 深色下 `colorScheme.error` 是**亮红档**（当文字用，要压得住 #121212），拿它铺底
  // 或当描边会显得浅、灰、脏 —— 用户 2026-09-16 原话：「成绩页的按钮背景，卡片的
  // 框线，太浅了」。实心件与描边改走下面这组（深色 = 不透明深红 `#C62828`）。
  // ⚠ 浅色侧逐像素不变：`errorFill`/`onErrorFill` 就是原来的 `scheme.error`/`onError`，
  // `errorBorder` 就是原来的 `error @ 70%`。

  /// 红**实心件**的底（筛选 chip 选中态 / 表头 / 实心红块）。
  static Color errorFill(BuildContext context) => isDark(context)
      ? AppLadder.darkErrorFill
      : Theme.of(context).colorScheme.error;

  /// 红实心件上的前景。
  static Color onErrorFill(BuildContext context) => isDark(context)
      ? AppLadder.darkOnErrorFill
      : Theme.of(context).colorScheme.onError;

  /// 红**描边**（统计卡 / 排名卡 / 虚线框的框线）。
  ///
  /// 深色下**不透明**：带 alpha 的红叠在卡片 #1A1A1A 上会混成 `#AE3D40`，
  /// 对卡片只有 2.93:1（发灰发脏）；不透明深红是 3.10:1 且饱和。
  static Color errorBorder(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return scheme.brightness == Brightness.dark
        ? AppLadder.darkErrorFill
        : scheme.error.withValues(alpha: 0.7);
  }

  // ── 中性淡描边 / 分隔线（2026-09-17 立 · 第四类缺陷：alpha 是「替换」不是「相乘」）──
  //
  // 用户 2026-09-17 原话：「深色模式桌面端左侧导航栏底部固定项最顶部的分割线太亮」。
  // 成因：`scheme.outlineVariant` 在**浅色**是不透明暖灰 `#D8C2C0`，在**深色**是
  // `0x1AFFFFFF`（10% 白，自带 alpha）。而 `Color.withValues(alpha: x)` 是**替换**
  // alpha，不是相乘 → 同一个写法在深色下把 10% 抬成 60%（`0x99FFFFFF`），叠在侧栏
  // `#1A1A1A` 上混成 **`#A3A3A3`**（窗口截图逐行扫描的像素实测），比浅色下同一根线
  // 刺眼得多。全库共 31 处这种写法（20 个文件），本函数是它们的唯一收口。
  //
  // 换算：浅色原样（逐像素冻结）；深色把**同一稀释比例**搬到 10% 白这个新基准上 ——
  // 0.6 → 10%（浅色 0.6 档的观感锚点，也正是 `app_card.dart` 深色描边的取值）、
  // 0.5 → 8.5%、0.7 → 11.7%、0.9 → 15%。

  /// 淡描边 / 发丝线（卡片与容器的淡框、面板分隔线）。
  ///
  /// `lightAlpha` = **调用方原来在浅色下用的 alpha**（原样透传，浅色不漂移）。
  /// ⚠ 别再用裸写法 `scheme.outlineVariant.withValues(alpha: …)`：`withValues` 是
  /// **替换** alpha，深色下会把 10% 白放大成 50~90% 白（详见本段头注释）。
  /// 实心 / 不透明描边走 [stroke]，带色（红等）的淡描边走 [tintBorder]。
  static Color hairline(BuildContext context, [double lightAlpha = 0.6]) {
    final base = Theme.of(context).colorScheme.outlineVariant;
    if (!isDark(context)) return base.withValues(alpha: lightAlpha);
    return base.withValues(
      alpha: base.a * (lightAlpha / _hairlineLightReference),
    );
  }
}
