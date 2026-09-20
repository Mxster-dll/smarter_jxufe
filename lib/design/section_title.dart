/// 节标题 / 卡内区块标题 —— **唯一实现**（2026-09-20 · 架构审查 ⑤-B）。
///
/// 形态（全应用同款，仿首页「全部服务」节标题）：
/// - 竖条 `width: 3, height: 13`、圆角 2、颜色 = [accent]（默认 [appCardAccent]，即主题红）
/// - 竖条与文案间距 `7`
/// - 文案 `fontSize: 13.5` / `FontWeight.w600` / `letterSpacing: 0.3`
/// - [trailing] 非空时用 `Spacer` 顶到最右
///
/// ⚠ **为什么在 `lib/design/`**：它被 30+ 个页面用（含 8 个此前各自手写一份的
/// `_sectionTitle`），住在某个 feature 里会让那个 feature 无端变成「共享内核」。
/// 兼容别名 `geCardTitle` 仍在 `features/score_estimate/presentation/ge_common.dart`
/// （**转发到这里**），老调用点不必改；新代码一律用 [appSectionTitle]。
library;

import 'package:flutter/material.dart';

import 'app_card.dart';

/// 节标题（3px 竖条 + 13.5 w600）。
Widget appSectionTitle(
  BuildContext context, {
  required String text,
  Widget? trailing,
  Color? accent,
}) {
  final a = accent ?? appCardAccent(context);
  return Row(
    children: [
      Container(
        width: 3,
        height: 13,
        decoration: BoxDecoration(
          color: a,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 7),
      Text(
        text,
        style: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
      if (trailing != null) ...[const Spacer(), trailing],
    ],
  );
}
