import 'package:flutter/material.dart';

/// WinUI 3 / Fluent Design 设计令牌（**浅色**）—— 手工映射到 Flutter。
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
/// ⚠️ 只做浅色是用户 2026-09-11 的裁定：app 目前没有 `darkTheme`，单页深色会与
/// AppBar / 外壳冲突。将来接入 `ThemeMode` 时，在这里补一套深色令牌
/// （规范里的深色表：底 #202020 / 卡片 rgba(255,255,255,.05) / 文本 rgba(255,255,255,.95)
/// / accent #60cdff）即可，页面侧不用改。
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
}

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
