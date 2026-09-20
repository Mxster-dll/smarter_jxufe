/// 首页仪表盘的共用小件（2026-09-20 从 `dashboard_panel.dart` 外提 · 架构审查 ⑥）。
///
/// 两个渲染簇（`dashboard_metrics.dart` / `dashboard_today_courses.dart`）都要用它们，
/// 故单独一份并公开命名（原来是类内私有方法 `_push` / `_inlineStatus`）。
library;

import 'package:flutter/material.dart';

  void dashboardPush(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  Widget dashboardInlineStatus(ColorScheme scheme, IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 15, color: scheme.onSurfaceVariant),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
