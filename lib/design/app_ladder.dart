/// 底色阶梯 + 文字 / 描边档位的**唯一出处**（浅色 / 深色两套）。
///
/// - 浅色 = 现状（原本写在 `lib/main.dart` 的 `.copyWith()` 里，逐值搬来，一个都不许改）。
///   §3「主题纯白」口径：白系一律 R=G=B 中性，**不从 primary 派生**。
/// - 深色 = **A · 中性深灰**，用户 2026-09-16 在 `design_preview/dark_mode_preview.html`
///   看过「浅色 / A 中性深灰 / B 纯黑 / C Fluent 深色」四列对比后拍板 A，
///   取值逐值对应那份预览的 CSS 变量（`--surface --card --container --high --highest
///   --border --divider --text --text2 --text3 --topbar --accent`）。
/// - M3 语义下深色的底阶方向与浅色**相反**：`surfaceContainerLowest` 最暗 →
///   `surfaceContainerHighest` 最亮。
///
/// 装配成 `ColorScheme` / `ThemeData` 的地方是 `lib/design/app_theme.dart`；
/// 页面侧不要直接用这里的常量，走 `Theme.of(context).colorScheme` 或 `AppColors`。
library;

import 'package:flutter/material.dart';

abstract final class AppLadder {
  // ── 浅色（现状，勿改）────────────────────────────────────────────────────
  /// 页面底（= `surfaceContainerLowest`）。
  static const Color lightSurface = Color(0xFFFFFFFF);

  /// M3 深色语义里这一档最暗；浅色里与页面底同色。
  static const Color lightSurfaceLowest = Color(0xFFFFFFFF);

  /// 次级页面底。
  static const Color lightSurfaceLow = Color(0xFFFAFAFA);

  /// 分区底（侧栏 / 分组块）。
  static const Color lightSurfaceContainer = Color(0xFFF5F5F5);
  static const Color lightSurfaceHigh = Color(0xFFF0F0F0);
  static const Color lightSurfaceHighest = Color(0xFFEBEBEB);

  /// 卡片底（§16：纯白）。
  static const Color lightCard = Color(0xFFFFFFFF);

  /// 顶栏底（首页顶栏取卡片色，故与卡片同值）。
  static const Color lightTopBar = Color(0xFFFFFFFF);

  // ── 深色 A 中性深灰（用户 2026-09-16 拍板）──────────────────────────────
  /// 页面底（预览 `--surface`）。
  static const Color darkSurface = Color(0xFF121212);
  static const Color darkSurfaceLowest = Color(0xFF121212);

  /// 卡片底（预览 `--card`）。
  static const Color darkSurfaceLow = Color(0xFF1A1A1A);

  /// 分区底（预览 `--container`）。
  static const Color darkSurfaceContainer = Color(0xFF1E1E1E);
  static const Color darkSurfaceHigh = Color(0xFF242424);
  static const Color darkSurfaceHighest = Color(0xFF2C2C2C);

  /// 卡片底（同 `darkSurfaceLow`）。
  static const Color darkCard = Color(0xFF1A1A1A);

  /// 顶栏底（预览 `--topbar`，与卡片同色）。
  static const Color darkTopBar = Color(0xFF1A1A1A);

  /// 主文字（预览 `--text` = `.92` 白叠在 `#121212` 上的等效实色）。
  static const Color darkOnSurface = Color(0xFFEBEBEB);

  /// 次级文字（预览 `--text2` = `.62` 白）。
  static const Color darkOnSurfaceVariant = Color(0xFFA0A0A0);

  /// 三级文字（预览 `--text3` = `.42` 白）。
  static const Color darkTextTertiary = Color(0xFF6B6B6B);

  /// 弱描边（预览 `--border` = `rgba(255,255,255,.10)`）。
  ///
  /// 带 alpha 是刻意的：这一档被八十多处直接当「淡边框 / 分隔线」用，落在卡片
  /// (`#1A1A1A`) / 分区 (`#1E1E1E`) / 页面 (`#121212`) 三种底上，
  /// 用半透明白才能各自自适应、且与预览取值完全一致。
  static const Color darkOutlineVariant = Color(0x1AFFFFFF);

  /// 强描边（输入框 / `OutlinedButton` 边框，= `rgba(255,255,255,.20)`）。
  static const Color darkOutline = Color(0x33FFFFFF);

  /// 分隔线（预览 `--divider` = `rgba(255,255,255,.08)`）。
  static const Color darkDivider = Color(0x14FFFFFF);

  /// 亮红强调色上的文字（亮红偏浅，压深字才够对比 5.16:1）。
  static const Color darkOnPrimary = Color(0xFF1A1A1A);

  // ── 深色下的「红」分两个角色（2026-09-16 立，别合并）──────────────────────
  //
  // 深色里 `colorScheme.error` 取的是**当文字用**的亮红档（#EE4C50）：它必须压得住
  // 页面底 #121212，所以只能偏亮。但**实心件（chip 选中底 / 表头）与描边（卡片红框线）
  // 不该用这一档** —— 它们不需要跟页面底比对比度，需要的是「深、饱和、实」。
  //
  // 用户 2026-09-16 原话：「成绩页的按钮背景、卡片的框线，太浅了」。实测成因：
  //   · 框线原本写 `error.withValues(alpha: 0.7)`，70% 的红叠在卡片 #1A1A1A 上
  //     → 混成 **#AE3D40**，对卡片只有 **2.93:1**（低于 3:1 的图形对比度门槛），发灰发脏；
  //   · chip 选中底原本就是亮红 #EE4C50 → 浅色下同一颗 chip 是深砖红 #BA1A1A，
  //     深色下却成了浅珊瑚红，用户一眼看出「浅」。
  // 现状：两处都改用下面的深红档（不透明），浅色侧一个像素都没动。

  /// 深色下**红实心件**的底（筛选 chip 选中态 / 表头 / 实心红块）。
  ///
  /// 白字压它 **5.62:1**；它压卡片底 #1A1A1A **3.10:1**、压页面底 #121212 **3.33:1**。
  static const Color darkErrorFill = Color(0xFFC62828);

  /// 深红实心件上的前景（白）。压 [darkErrorFill] = 5.62:1。
  static const Color darkOnErrorFill = Color(0xFFFFFFFF);

  // ── 半透明淡底 / 淡描边的「深色等效 alpha」（2026-09-16 立）──────────────
  //
  // 第三类红缺陷（前两类是实心件与描边）：**淡色底在深色下被整块吞掉**。
  // 全应用有 8 处「警示面板」写 `scheme.error.withValues(alpha: 0.05/0.06)`，
  // 浅色下是白底上一层看得见的粉，深色下同一个 alpha 叠在卡片 #1A1A1A 上
  // → 混成 **#201A1A**（ΔL≈0.003），与卡片底肉眼无异 —— 面板等于不存在。
  // 原因是**深底会吞淡色**：同样的 6% 叠在白底上是 ΔL≈0.10（约 30 倍）。
  // 所以深色必须抬 alpha 才能等价，浅色侧**逐像素不动**（alpha 由调用方传入）。

  /// 半透明**淡底**在深色下的等效 alpha（浅色 `0.06` → 深色 `0.21`）。
  ///
  /// 换算 = `lightAlpha × 3.5`，夹在 `[0.14, darkSoftAlpha]`：
  /// · `#EE4C50 @ 21%` 叠卡片 → `#472525`，对卡片 **1.29:1**（浅色同款 1.12:1）；
  /// · 下限 0.14 保证最淡的那档也看得见；
  /// · 上限就是 [darkSoftAlpha]（= `AppColors.statusFill` 的深色档）——
  ///   **全应用深色「淡底」只有一个封顶值**，避免出现
  ///   「浅色 8% 的块比浅色 12% 的块在深色下更浓」这种倒挂。
  ///   代价是 0.07 以上的几档在深色下并成一档（浅色下它们本就只差 1~2% 不透明度）。
  static double darkTintAlpha(double lightAlpha) =>
      (lightAlpha * 3.5).clamp(0.14, darkSoftAlpha);

  /// 半透明**淡描边**在深色下的等效 alpha（浅色 `0.35` → 深色 `0.42`）。
  ///
  /// 描边本来就比底色浓，**不需要** 3.5 倍：实测同一支红
  /// 浅色 35% 对白底 **1.79:1**、深色 35% 对卡片 **1.62:1** ——
  /// 抬到 42% 恰好回到 **1.81:1**，两侧等重。
  ///
  /// 下限 0.30（而不是更低）是为了**保住「框线比底色显眼」这个关系**：
  /// 有一批面板是「淡底 5% + 淡框 16%」，深色下底已经抬到 21%~26%，
  /// 框若还停在 16% 就会被自己的底吞掉（浅色下框是底的 3.2 倍浓）。
  /// 抬到 30% 后框重新高于底，对卡片 **1.52:1**。
  static double darkBorderAlpha(double lightAlpha) =>
      (lightAlpha * 1.2).clamp(0.30, 0.60);

  /// 深色下「淡底」的统一上限（= `AppColors.statusFill` 的深色档）。
  ///
  /// `#F2555A @ 22%` 叠卡片 → 对卡片 **1.31:1**，压在上面的正文（`#EBEBEB`）
  /// 仍有 **10.3:1** —— 既看得见又不会盖住内容。再浓就会开始像「实心色块」。
  static const double darkSoftAlpha = 0.22;
}
