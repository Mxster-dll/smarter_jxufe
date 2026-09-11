/// 阅读学分 feature 的共享视觉件（白卡 / 图标盒 / 状态胶囊）。
///
/// 用户 2026-09-11 反馈「蛟湖阅读页很混乱、每个部分重复好几张卡」→ 页面统一改为
/// **每个部分一张进度卡**，卡片外观集中在这里，避免各文件各写一套。
library;

import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/features/read_credit/domain/read_credit_models.dart';

/// 白卡容器（圆角 12 + 描边 0.6，与首页宫格页一致）。
Widget readCreditCard(
  BuildContext context, {
  required Widget child,
  EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(14, 12, 14, 12),
}) {
  final scheme = Theme.of(context).colorScheme;
  return Container(
    decoration: BoxDecoration(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
    ),
    padding: padding,
    child: child,
  );
}

/// 圆角图标盒（≤34 用 8 圆角 / 18 图标，>34 用 10 圆角 / 21 图标）。
Widget readCreditIconBox(IconData icon, Color color, {double size = 42}) =>
    Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(size <= 34 ? 8 : 10),
      ),
      child: Icon(icon, size: size <= 34 ? 18 : 21, color: color),
    );

/// 小胶囊（状态徽标）。
Widget readCreditChip(String text, Color bg, Color fg) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
  decoration: BoxDecoration(
    color: bg,
    borderRadius: BorderRadius.circular(999),
  ),
  child: Text(
    text,
    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
  ),
);

/// 达标 / 未达标 / 无数据 三态配色（实际与平台两档共用）。
({Color bg, Color fg}) readCreditMetColors(
  BuildContext context,
  bool? met, {
  bool unknownIsGrey = true,
}) {
  final scheme = Theme.of(context).colorScheme;
  if (met == true) {
    return (
      bg: Colors.green.withValues(alpha: 0.12),
      fg: Colors.green.shade800,
    );
  }
  if (met == false) {
    return (
      bg: Colors.orange.withValues(alpha: 0.14),
      fg: Colors.orange.shade900,
    );
  }
  if (!unknownIsGrey) {
    return (
      bg: Colors.green.withValues(alpha: 0.12),
      fg: Colors.green.shade800,
    );
  }
  return (bg: scheme.surfaceContainerHighest, fg: scheme.onSurfaceVariant);
}

/// 各部分的图标。
IconData readCreditKindIcon(ReadCreditKind kind) => switch (kind) {
  ReadCreditKind.ordinary => Icons.auto_stories_outlined,
  ReadCreditKind.classic => Icons.book_outlined,
  ReadCreditKind.libraryEdu => Icons.school_outlined,
  ReadCreditKind.infoLiteracy => Icons.ondemand_video_outlined,
  ReadCreditKind.culture => Icons.celebration_outlined,
};

/// 各部分的点缀色（圆环分段与图例用；四部分各不相同便于辨认）。
Color readCreditPartColor(ReadCreditKind kind) => switch (kind) {
  ReadCreditKind.classic => const Color(0xFF2E7D32),
  ReadCreditKind.ordinary => const Color(0xFF1565C0),
  ReadCreditKind.libraryEdu => const Color(0xFF00B8D4),
  ReadCreditKind.infoLiteracy => const Color(0xFFEF6C00),
  ReadCreditKind.culture => const Color(0xFF795548),
};

/// 进度条上「实际」那一档的颜色（浅红）——用户裁定：浅红 = 实际数据。
///
/// 与「服务端」深红同色相、只用透明度区分，保证两档叠在一起时层次清楚。
Color readCreditActualBarColor(BuildContext context) =>
    Theme.of(context).colorScheme.primary.withValues(alpha: 0.30);

/// 进度条上「服务端」那一档的颜色（红 = 主题校红，覆盖在灰色条上）。
Color readCreditServerBarColor(BuildContext context) =>
    Theme.of(context).colorScheme.primary;

/// 该 feature 的统一点缀色。
const Color readCreditAccent = FeaturePalette.jhRead;
