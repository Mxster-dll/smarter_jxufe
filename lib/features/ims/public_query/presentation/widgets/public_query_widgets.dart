/// 公共查询页 · 零件（只收 context / ref 的渲染件与纯辅助）（顶层函数）。
///
/// 拆分自 `public_query_screen.dart`（2026-10-08 架构审计第三轮 · 通用拆分器 `.scratch/split_extract.py`）：
/// 这里只放**不碰字段 / `widget` / `setState`** 的一层；`BuildContext` 本来就是显式参数的
/// 渲染件也在此列。留在原类的是读字段的那批，正文字号 / 全局 key 之类要么收显式参数、
/// 要么留在 State（口径见 AGENTS.md §33.4.4）。
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:smarter_jxufe/features/ims/public_query/domain/public_query.dart';
import 'package:smarter_jxufe/features/ims/public_query/presentation/public_query_option_sheet.dart';
import 'package:smarter_jxufe/features/score_estimate/presentation/ge_common.dart';

/// 在候选列表里把代码翻成显示名；查不到就回退显示代码本身。
String pqLabelOf(List<PublicQueryOption>? list, String code) {
  if (code.isEmpty) return '';
  for (final o in list ?? const <PublicQueryOption>[]) {
    if (o.code == code) return o.displayName;
  }
  return code;
}

PublicQueryOption? pqOptionOf(List<PublicQueryOption> list, String code) {
  for (final o in list) {
    if (o.code == code) return o;
  }
  return null;
}

// ---------------- 通用小组件 ----------------

Widget pqRowShell(
  BuildContext context, {
  required IconData icon,
  required String label,
  required Widget child,
}) {
  final scheme = Theme.of(context).colorScheme;
  return Row(
    children: [
      Icon(icon, size: 20, color: scheme.onSurfaceVariant),
      const SizedBox(width: 10),
      SizedBox(
        width: 92,
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ),
      Expanded(child: child),
    ],
  );
}

Widget pqPickerRow(
  BuildContext context, {
  required IconData icon,
  required String label,
  required String value,
  required String hint,
  VoidCallback? onTap,
}) {
  final scheme = Theme.of(context).colorScheme;
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(6),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: pqRowShell(
        context,
        icon: icon,
        label: label,
        child: Row(
          children: [
            Expanded(
              child: Text(
                value.isEmpty ? hint : value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: value.isEmpty ? scheme.onSurfaceVariant : null,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    ),
  );
}

Widget pqHint(BuildContext context, String text) => Padding(
  padding: const EdgeInsets.only(top: 6),
  child: Text(
    text,
    style: Theme.of(context).textTheme.labelSmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  ),
);

Widget pqLoadingCard(BuildContext context, String text) => Card(
  elevation: 0,
  shape: geCardShape(context),
  child: Padding(
    padding: const EdgeInsets.all(20),
    child: Row(
      children: [
        const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
      ],
    ),
  ),
);

Widget pqErrorCard(
  BuildContext context,
  String text, {
  required VoidCallback onRetry,
}) => Card(
  elevation: 0,
  shape: geCardShape(context),
  child: Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.error_outline,
              size: 20,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(text)),
          ],
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(onPressed: onRetry, child: const Text('重试')),
        ),
      ],
    ),
  ),
);

Widget pqInfoCard(
  BuildContext context,
  IconData icon,
  String title,
  String message,
) => Card(
  elevation: 0,
  shape: geCardShape(context),
  child: Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 20,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(message, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    ),
  ),
);

Future<PublicQueryOption?> pqPickOption(
  BuildContext context,
  String title,
  List<PublicQueryOption> options,
  PublicQueryOption? selected,
) async {
  final picked = await pqPickOptions(context, title, options, single: true);
  return picked.isEmpty ? null : picked.first;
}

/// 可搜索的选择面板（长列表：教师 5000+ / 课程 1000+ / 班级 1000+）。
///
/// 面板本身是共享件（public_query_option_sheet.dart）——「找无课时间」页用它多选班级。
Future<List<PublicQueryOption>> pqPickOptions(
  BuildContext context,
  String title,
  List<PublicQueryOption> options, {
  bool single = false,
}) => pickPublicQueryOptions(
  context,
  title: title,
  options: options,
  single: single,
);
