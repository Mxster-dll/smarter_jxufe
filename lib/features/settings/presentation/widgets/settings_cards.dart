/// 设置页的 14 个分节卡（2026-09-20 从 `settings_screen.dart` 外提 · 架构审查 ⑥）。
///
/// 原同文件的**全部顶层私有类**（12 个分节卡 + 它们各自的 State + 共享件 `_SubLabel` +
/// 顶层哨兵 `_clearSentinel`）整体搬到本文件，并改为 `Settings` 前缀的公开名
/// （`_` 是库私有，跨文件不可见）。`SettingsScreen` 本体仍留在 `settings_screen.dart`
/// （它只负责按 `sections:` 过滤并组装这些卡）。
library;

import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/feature_palette.dart';

export 'settings_cards_campus.dart';
export 'settings_cards_display.dart';
export 'settings_cards_schedule.dart';
export 'settings_cards_session.dart';
export 'settings_cards_widgets.dart';
export 'settings_cards_window.dart';

/// 「不设置」在选择面板里的哨兵值。
///
/// 面板返回 `null` 表示用户取消（下滑关闭），要区分于「选择清空」，
/// 故清空走一个显式哨兵。
const settingsClearSentinel = '__clear__';

/// 卡片内的小节标题（图标 + 标题 + 说明）。
class SettingsSubLabel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  /// 强调色；`null` = 用随主题解析的主题红（浅色校红 / 深色亮红）。
  final Color? accent;

  const SettingsSubLabel({
      super.key,
    
    required this.icon,
    required this.title,
    required this.subtitle,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final tint = accent ?? fp(context).cardAccent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: tint),
            const SizedBox(width: 6),
            Text(
              title,
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 13.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
