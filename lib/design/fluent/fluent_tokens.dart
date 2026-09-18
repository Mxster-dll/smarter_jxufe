import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/app_ladder.dart';
import 'package:smarter_jxufe/design/feature_palette.dart';

/// WinUI 3 / Fluent Design 设计令牌（**浅色 + 深色**）—— 手工映射到 Flutter。
///
/// 数值取自 Fluent 2 官方令牌表（`~/.agents/skills/fluent-design/references/design-tokens.md`）。
/// 本文件只做「令牌 → Dart 常量」的映射，**不含任何业务语义**；业务色一律走
/// [FluentColors.accent]（= 校红）或 `lib/design/feature_palette.dart`。
///
/// 改这一页之前先读这四条硬约束（Fluent 规范，不是个人风格）：
/// 1. **间距一律 4 的倍数**（[FluentSpacing]）——禁止 5 / 7 / 10 / 15 / 20 / 25 / 30 这类值，
///    也不要用负 margin；
/// 2. **圆角只有两档**：控件与列表项 `4`、卡片与浮层 `8`（[FluentRadius]）；
/// 3. **字重只用 400 / 600** —— 禁止 `FontWeight.bold`(700)，强调用 semibold；
/// 4. **字号最小 12，且只用 [FluentType] 里的那几档**（12 / 14 / 18 / 20 / 28 / 40）。
///
/// 页面里**不要**出现裸 `Color(0x…)`，一律引用本文件（AGENTS.md §3 的「色彩登记」约定）。
///
/// ⚠️ 只做浅色是用户 2026-09-11 的裁定（当时 app 没有 `darkTheme`）。**2026-09-16 已落地深色**：
/// - 深色档常量 = 本文件 `FluentColors.*Dark`；**取色入口 = [FluentPalette] / 简写 [fluent]**
///   （`fluent(context).textPrimary`），页面侧与 `fluent_surfaces.dart` / `fluent_controls.dart`
///   里的取色一律走它；
/// - [FluentColors] 上的静态浅色值**保留原样**，只给「拿不到 `BuildContext` 的 const 场景」用，
///   页面里不要再直接引用（深色下会整片发白）。浅色档取值一个都没改。
///
/// 深色**不采用** Fluent 规范的蓝强调与 `#202020` 底：本应用的权威阶梯是
/// `lib/design/app_ladder.dart`（A · 中性深灰，用户 2026-09-16 拍板），强调色是校红亮色档
/// [`FeaturePalette.cardAccentDark`]（AGENTS.md §16「单色强调一律改主题红」）。
/// 表里只对 [success] / [cautionDeep] / [critical] 走 [`featureTone`] 提亮 —— 与全应用同一口径，
/// 其余深色值按阶梯定死，**不做全局提亮**。
abstract final class FluentColors {
  // ── 文本 TextFillColor* ──
  /// 主文本 rgba(0,0,0,.90)
  static const textPrimary = Color(0xE6000000);

  /// 次要文本 rgba(0,0,0,.61)
  static const textSecondary = Color(0x9C000000);

  /// 三级文本 rgba(0,0,0,.45)
  static const textTertiary = Color(0x73000000);

  /// 禁用文本 rgba(0,0,0,.25)
  static const textDisabled = Color(0x40000000);

  /// 强调色上的文本
  static const textOnAccentPrimary = Color(0xFFFFFFFF);
  static const textOnAccentSecondary = Color(0xB3FFFFFF);

  // ── 实心底 SolidBackgroundFillColor* ──
  /// 页面底（Win11 浅色 Mica 的等效实色）
  static const bgBase = Color(0xFFF3F3F3);
  static const bgSecondary = Color(0xFFEEEEEE);
  static const bgTertiary = Color(0xFFF9F9F9);
  static const bgQuaternary = Color(0xFFFFFFFF);

  // ── 卡片 / 分层 CardBackgroundFillColor* · LayerFillColor* ──
  /// 卡片底 rgba(255,255,255,.60) —— 会与 [bgBase] 合成出 Win11 卡片的灰白
  static const cardDefault = Color(0x99FFFFFF);
  static const cardSecondary = Color(0x80F6F6F6);
  static const layerDefault = Color(0xE6FFFFFF);
  static const layerAlt = Color(0xCCFFFFFF);

  // ── 控件填充 ControlFillColor* ──
  static const controlDefault = Color(0xB3FFFFFF);
  static const controlSecondary = Color(0x80F9F9F9);
  static const controlTertiary = Color(0x4DF9F9F9);
  static const controlDisabled = Color(0x4DF9F9F9);

  // ── 微妙填充 SubtleFillColor* ──
  static const subtleSecondary = Color(0x0A000000);
  static const subtleTertiary = Color(0x0F000000);

  // ── 描边 Stroke* ──
  /// 卡片描边 rgba(0,0,0,.06)
  static const strokeCard = Color(0x0F000000);

  /// 控件描边 rgba(0,0,0,.08)
  static const strokeControlDefault = Color(0x14000000);

  /// 控件描边·强 rgba(0,0,0,.14)
  static const strokeControlSecondary = Color(0x24000000);

  /// 分隔线 rgba(0,0,0,.08)
  static const strokeDivider = Color(0x14000000);

  // ── 强调色 = 校红（用户 2026-09-11 裁定：Fluent 结构 + app 主色）──
  /// 主强调色 #C3282E（同 `JxufeTheme.primaryColor`）
  static const accent = Color(0xFFC3282E);

  /// 悬停态 = accent 90% + black
  static const accentSecondary = Color(0xFFAF2429);

  /// 按下态 = accent 80% + black
  static const accentTertiary = Color(0xFF9C2025);

  /// 禁用态 rgba(195,40,46,.40)
  static const accentDisabled = Color(0x66C3282E);

  /// 8% 淡染（序号徽标 / 合计行底 / 占比条）
  static const accentSubtle = Color(0x14C3282E);

  /// 16% 淡染（需要更明显时）
  static const accentSubtleStrong = Color(0x29C3282E);

  // ── 系统状态色 SystemFillColor* ──
  static const success = Color(0xFF6BB700);
  static const caution = Color(0xFFFCE100);

  /// 警示色·深 —— [caution] 本身太亮，做图标/文字时用这一档才有对比度。
  static const cautionDeep = Color(0xFF9D5D00);

  static const critical = Color(0xFFD13438);
  static const neutral = Color(0xFF8E8E8E);
  static const successBg = Color(0xFFDFF6DD);
  static const cautionBg = Color(0xFFFFF4CE);
  static const criticalBg = Color(0xFFFDE7E9);
  static const neutralBg = Color(0xFFF3F3F3);

  /// 对话框背后的遮罩 rgba(0,0,0,.30)
  static const smoke = Color(0x4D000000);

  // ── 深色档（2026-09-16 接入 `ThemeMode` 时补 · 权威表）────────────────────
  //
  // 底阶 / 描边直接引用 `lib/design/app_ladder.dart`（A 中性深灰，用户 2026-09-16 拍板），
  // 不写第二份字面量 —— 阶梯改了这里跟着走，不会漂移。
  // 深色下 M3 的底阶方向与浅色相反（越高的档越亮），命名沿用 Fluent 的语义：
  // `bgBase` 页面底最暗 → `bgQuaternary` 最高档。

  /// 主文本 `.95` 白。
  static const textPrimaryDark = Color(0xFFF2F2F2);

  /// 次要文本 `.69` 白等效实色。
  static const textSecondaryDark = Color(0xFFB0B0B0);

  /// 三级文本 `.54` 白等效实色。
  static const textTertiaryDark = Color(0xFF8A8A8A);

  /// 禁用文本 `.37` 白等效实色。
  static const textDisabledDark = Color(0xFF5E5E5E);

  // 强调色底上的文字（[textOnAccentPrimary] / [textOnAccentSecondary]）深色**不变**
  // —— 它们画在固定的强调色底上，不随页面底走。

  // ── 实心底（= AppLadder 深色阶梯）──
  /// 页面底（`AppLadder.darkSurface`）。
  static const bgBaseDark = AppLadder.darkSurface;

  /// 卡片底（`AppLadder.darkSurfaceLow`）。
  static const bgSecondaryDark = AppLadder.darkSurfaceLow;

  /// 分区底（`AppLadder.darkSurfaceContainer`）。
  static const bgTertiaryDark = AppLadder.darkSurfaceContainer;

  /// 分区底·高（`AppLadder.darkSurfaceHigh`）。
  static const bgQuaternaryDark = AppLadder.darkSurfaceHigh;

  // ── 卡片 / 分层 / 控件填充 ──
  /// 卡片底（同 [bgSecondaryDark]）。
  static const cardDefaultDark = AppLadder.darkSurfaceLow;

  /// 分层底（同 [bgTertiaryDark]）。
  static const layerDefaultDark = AppLadder.darkSurfaceContainer;

  /// 分层底·高（同 [bgQuaternaryDark]）。
  static const layerAltDark = AppLadder.darkSurfaceHigh;

  /// 控件填充（同 [bgSecondaryDark]）。
  static const controlDefaultDark = AppLadder.darkSurfaceLow;

  // 半透明的控件 / 微妙填充在深色下是**白色低透明度叠层**（浅色那套是白色高透明度叠浅底），
  // 逐值 = `Colors.white.withValues(alpha: …)`，见 [FluentPalette]：
  // `controlSecondary` .06 / `controlTertiary` .09 / `controlDisabled` .04 /
  // `cardSecondary` .05 / `subtleSecondary` .04 / `subtleTertiary` .06。

  // ── 描边 ──
  /// 卡片描边（`AppLadder.darkOutlineVariant` = rgba(255,255,255,.10)）。
  static const strokeCardDark = AppLadder.darkOutlineVariant;

  /// 控件描边（`AppLadder.darkOutline` = rgba(255,255,255,.20)）。
  static const strokeControlDefaultDark = AppLadder.darkOutline;

  /// 控件描边·强（比 default 再高一档，rgba(255,255,255,.25)）。
  static const strokeControlSecondaryDark = Color(0x40FFFFFF);

  /// 分隔线（`AppLadder.darkDivider` = rgba(255,255,255,.08)）。
  static const strokeDividerDark = AppLadder.darkDivider;

  // ── 强调色 = 校红亮色档（`FeaturePalette.cardAccentDark`，
  //    与深色主题的 `colorScheme.primary` 同值，见 feature_palette.dart）──
  /// 主强调色（深色主题红）。
  static const accentDark = FeaturePalette.cardAccentDark;

  /// 悬停态 = [accentDark] × 0.90（与浅色档 accent→accentSecondary 的相对关系一致）。
  static const accentSecondaryDark = Color(0xFFDA4D51);

  /// 按下态 = [accentDark] × 0.80（同上）。
  static const accentTertiaryDark = Color(0xFFC24448);

  /// 禁用态 = [accentDark] 40% 透明度（同浅色档口径）。
  static const accentDisabledDark = Color(0x66F2555A);

  // `accentSubtle` / `accentSubtleStrong` 深色 = [accentDark] 的 12% / 24% 淡染
  // （浅色档 8% / 16%，深色底更暗故整体抬 1.5 倍），见 [FluentPalette]。
  //
  // `caution`(#FCE100) / `neutral`(#8E8E8E) 深色**原样**（本身就够亮）；
  // `success` / `cautionDeep` / `critical` 深色走 [`featureTone`] 提亮；
  // 四个状态淡底深色 = 各自前景色的 22% 透明度；`smoke` 深色 = 黑 45%。
}

/// 当前亮度下的 Fluent 色表（浅色 / 深色两套）。
///
/// 页面与 Fluent 基础件里**一律这样取色**（`FluentColors.xxx` 的静态值只留给 const 场景）：
/// ```dart
/// final p = fluent(context);   // 或每处内联 fluent(context).textPrimary
/// ... color: p.textPrimary
/// ```
/// 浅色下逐值 = [FluentColors] 的原值（**一个都没变**，见 `test/theme_dark_test.dart`
/// 一类的既有断言不受影响）；深色下逐值 = [FluentColors] 的 `*Dark` 档。
///
/// 写法照 [`FeatureColors`] / [`fp`]（`lib/design/feature_palette.dart`）的同一模式。
class FluentPalette {
  const FluentPalette._(this._dark);

  final bool _dark;

  /// 浅色（= 静态浅色常量，原值）。
  static const FluentPalette light = FluentPalette._(false);

  /// 深色（A 中性深灰阶梯 + 校红亮色档）。
  static const FluentPalette dark = FluentPalette._(true);

  /// 按 `Theme` 的亮度取色表。
  static FluentPalette of(BuildContext context) =>
      forBrightness(Theme.of(context).brightness);

  /// 按亮度取色表。
  static FluentPalette forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// 深色下按全应用统一口径提亮（只抬 HSL 明度），浅色返回原值。
  Color _tone(Color base) => _dark ? featureTone(base) : base;

  // ── 文本 ──
  Color get textPrimary =>
      _dark ? FluentColors.textPrimaryDark : FluentColors.textPrimary;
  Color get textSecondary =>
      _dark ? FluentColors.textSecondaryDark : FluentColors.textSecondary;
  Color get textTertiary =>
      _dark ? FluentColors.textTertiaryDark : FluentColors.textTertiary;
  Color get textDisabled =>
      _dark ? FluentColors.textDisabledDark : FluentColors.textDisabled;

  /// 强调色底上的文字 —— 两侧同值（画在固定强调色底上，不随页面底走）。
  Color get textOnAccentPrimary => FluentColors.textOnAccentPrimary;
  Color get textOnAccentSecondary => FluentColors.textOnAccentSecondary;

  // ── 实心底 ──
  Color get bgBase => _dark ? FluentColors.bgBaseDark : FluentColors.bgBase;
  Color get bgSecondary =>
      _dark ? FluentColors.bgSecondaryDark : FluentColors.bgSecondary;
  Color get bgTertiary =>
      _dark ? FluentColors.bgTertiaryDark : FluentColors.bgTertiary;
  Color get bgQuaternary =>
      _dark ? FluentColors.bgQuaternaryDark : FluentColors.bgQuaternary;

  // ── 卡片 / 分层 ──
  Color get cardDefault =>
      _dark ? FluentColors.cardDefaultDark : FluentColors.cardDefault;

  /// 次要卡片底：深色 = 白 5% 叠层（Fluent 深色卡片填充口径）。
  Color get cardSecondary => _dark
      ? Colors.white.withValues(alpha: 0.05)
      : FluentColors.cardSecondary;

  Color get layerDefault =>
      _dark ? FluentColors.layerDefaultDark : FluentColors.layerDefault;
  Color get layerAlt => _dark ? FluentColors.layerAltDark : FluentColors.layerAlt;

  // ── 控件填充（hover / pressed / disabled 在深色下是白色低透明度叠层）──
  Color get controlDefault =>
      _dark ? FluentColors.controlDefaultDark : FluentColors.controlDefault;
  Color get controlSecondary => _dark
      ? Colors.white.withValues(alpha: 0.06)
      : FluentColors.controlSecondary;
  Color get controlTertiary => _dark
      ? Colors.white.withValues(alpha: 0.09)
      : FluentColors.controlTertiary;
  Color get controlDisabled => _dark
      ? Colors.white.withValues(alpha: 0.04)
      : FluentColors.controlDisabled;

  // ── 微妙填充 ──
  Color get subtleSecondary => _dark
      ? Colors.white.withValues(alpha: 0.04)
      : FluentColors.subtleSecondary;
  Color get subtleTertiary => _dark
      ? Colors.white.withValues(alpha: 0.06)
      : FluentColors.subtleTertiary;

  // ── 描边 ──
  Color get strokeCard =>
      _dark ? FluentColors.strokeCardDark : FluentColors.strokeCard;
  Color get strokeControlDefault => _dark
      ? FluentColors.strokeControlDefaultDark
      : FluentColors.strokeControlDefault;
  Color get strokeControlSecondary => _dark
      ? FluentColors.strokeControlSecondaryDark
      : FluentColors.strokeControlSecondary;
  Color get strokeDivider =>
      _dark ? FluentColors.strokeDividerDark : FluentColors.strokeDivider;

  // ── 强调色（校红）──
  Color get accent => _dark ? FluentColors.accentDark : FluentColors.accent;
  Color get accentSecondary => _dark
      ? FluentColors.accentSecondaryDark
      : FluentColors.accentSecondary;
  Color get accentTertiary => _dark
      ? FluentColors.accentTertiaryDark
      : FluentColors.accentTertiary;
  Color get accentDisabled => _dark
      ? FluentColors.accentDisabledDark
      : FluentColors.accentDisabled;

  /// 8%（浅色）/ 20%（深色）淡染 —— 序号徽标、合计行底。
  ///
  /// ⚠ 深色档 2026-09-16 从 0.12 抬到 0.20：12% 的红叠在深色卡片上对卡片只有
  /// **1.15:1**，与背景几乎分不开（用户本轮的原话是「太浅了」）。浅色侧不动。
  /// 留 0.20 是为了和 [accentSubtleStrong] 的 0.24 保住层次。
  Color get accentSubtle => _dark
      ? accent.withValues(alpha: 0.20)
      : FluentColors.accentSubtle;

  /// 16%（浅色）/ 24%（深色）淡染 —— 需要更明显时。
  Color get accentSubtleStrong => _dark
      ? accent.withValues(alpha: 0.24)
      : FluentColors.accentSubtleStrong;

  // ── 系统状态色 ──
  /// 深色按 [featureTone] 提亮；浅色原值。
  Color get success => _tone(FluentColors.success);

  /// 两侧同值（#FCE100 本身就够亮）。
  Color get caution => FluentColors.caution;

  /// 深色按 [featureTone] 提亮；浅色原值。
  Color get cautionDeep => _tone(FluentColors.cautionDeep);

  /// 深色按 [featureTone] 提亮；浅色原值。
  Color get critical => _tone(FluentColors.critical);

  /// 两侧同值（#8E8E8E 已经够亮，提亮反而发白）。
  Color get neutral => FluentColors.neutral;

  /// 状态淡底：深色 = 各自前景色的 22% 透明度。
  Color get successBg =>
      _dark ? success.withValues(alpha: 0.22) : FluentColors.successBg;
  Color get cautionBg =>
      _dark ? caution.withValues(alpha: 0.22) : FluentColors.cautionBg;
  Color get criticalBg =>
      _dark ? critical.withValues(alpha: 0.22) : FluentColors.criticalBg;
  Color get neutralBg =>
      _dark ? neutral.withValues(alpha: 0.22) : FluentColors.neutralBg;

  /// 对话框背后的遮罩：深色 = 黑 45%（深色底下 30% 已经分不出层）。
  Color get smoke =>
      _dark ? Colors.black.withValues(alpha: 0.45) : FluentColors.smoke;
}

/// [FluentPalette.of] 的简写：`fluent(context).textPrimary`。
FluentPalette fluent(BuildContext context) => FluentPalette.of(context);

/// 间距（4px 网格）。
abstract final class FluentSpacing {
  /// 4 —— 紧邻元素
  static const double xs = 4;

  /// 8 —— 控件与标签
  static const double sm = 8;

  /// 12 —— 控件与标题 / 卡片边缘到文字
  static const double md = 12;

  /// 16 —— 卡片与列表项内边距
  static const double lg = 16;

  /// 24 —— 内容分区间距 / 页面内边距
  static const double xl = 24;

  /// 36 —— 页面级内边距
  static const double xxl = 36;

  /// 48 —— 大分区间距
  static const double xxxl = 48;
}

/// 圆角：**只有两档**。
abstract final class FluentRadius {
  /// 4 —— 按钮 / 输入框 / 列表项（ControlCornerRadius）
  static const double control = 4;

  /// 8 —— 卡片 / 弹窗 / 浮层（OverlayCornerRadius）
  static const double overlay = 8;

  static const BorderRadius controlAll = BorderRadius.all(
    Radius.circular(control),
  );
  static const BorderRadius overlayAll = BorderRadius.all(
    Radius.circular(overlay),
  );
}

/// 文字排版阶梯。字体族按 Fluent 顺序回退，Windows 命中 Segoe / 微软雅黑，
/// 其它平台找不到这些族时自动回落系统默认字体。
abstract final class FluentType {
  static const List<String> _fallback = <String>[
    'Segoe UI Variable Text',
    'Segoe UI Variable',
    'Segoe UI',
    'Microsoft YaHei UI',
    'Microsoft YaHei',
    'PingFang SC',
    'Noto Sans CJK SC',
  ];

  /// 12 / 400 / 16 —— 标签、时间戳、元信息
  static const caption = TextStyle(
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w400,
    fontFamilyFallback: _fallback,
  );

  /// 14 / 400 / 20 —— 正文（默认档，一般不用显式设置）
  static const body = TextStyle(
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w400,
    fontFamilyFallback: _fallback,
  );

  /// 14 / 600 / 20 —— 强调正文
  static const bodyStrong = TextStyle(
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w600,
    fontFamilyFallback: _fallback,
  );

  /// 18 / 400 / 24 —— 引言性文字
  static const bodyLarge = TextStyle(
    fontSize: 18,
    height: 24 / 18,
    fontWeight: FontWeight.w400,
    fontFamilyFallback: _fallback,
  );

  /// 20 / 600 / 28 —— 节标题、卡片标题、页面标题（AppBar）
  static const subtitle = TextStyle(
    fontSize: 20,
    height: 28 / 20,
    fontWeight: FontWeight.w600,
    fontFamilyFallback: _fallback,
  );

  /// 28 / 600 / 36 —— 页大标题
  static const title = TextStyle(
    fontSize: 28,
    height: 36 / 28,
    fontWeight: FontWeight.w600,
    fontFamilyFallback: _fallback,
  );

  /// 40 / 600 / 52 —— 关键指标数字
  static const titleLarge = TextStyle(
    fontSize: 40,
    height: 52 / 40,
    fontWeight: FontWeight.w600,
    fontFamilyFallback: _fallback,
  );
}

/// 阴影：**按层级用，不做装饰**。Win11 的卡片在静止态只有描边没有阴影，
/// 所以 [FluentCard] 默认不投影，浮层才用 [flyout] / [dialog]。
abstract final class FluentShadows {
  static const List<BoxShadow> card = <BoxShadow>[
    BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 2)),
  ];
  static const List<BoxShadow> flyout = <BoxShadow>[
    BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 4)),
  ];
  static const List<BoxShadow> dialog = <BoxShadow>[
    BoxShadow(color: Color(0x1F000000), blurRadius: 16, offset: Offset(0, 8)),
  ];
}

/// 动效：时长与曲线取自 Fluent 2 的 motion 令牌。
abstract final class FluentMotion {
  /// 150ms —— 控件状态变化（hover / pressed）
  static const Duration fast = Duration(milliseconds: 150);

  /// 200ms —— 入场、尺寸变化
  static const Duration normal = Duration(milliseconds: 200);

  /// 250ms —— 较大范围的位移
  static const Duration gentle = Duration(milliseconds: 250);

  /// easyEase —— 大多数状态过渡
  static const Curve easyEase = Cubic(0.33, 0, 0.67, 1);

  /// 减速曲线 —— 入场
  static const Curve decelerate = Cubic(0, 0, 0, 1);

  /// 加速曲线 —— 退场
  static const Curve accelerate = Cubic(1, 0, 1, 1);
}
