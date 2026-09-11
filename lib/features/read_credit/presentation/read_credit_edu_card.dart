/// 入馆教育页顶部的「阅读学分 · 入馆教育」卡。
///
/// 用户 2026-09-11 裁定：入馆教育页要**既显示进度条、也显示学分平台这一部分的信息**，
/// 同时保留原入馆教育页的内容。数据直接复用 `readCreditProgressProvider` 里
/// 入馆教育那一条（口径与蛟湖阅读页完全一致，不另算一套）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/read_credit/data/providers/read_credit_providers.dart';
import 'package:smarter_jxufe/features/read_credit/domain/read_credit_models.dart';
import 'package:smarter_jxufe/features/read_credit/presentation/read_credit_detail_screen.dart';
import 'package:smarter_jxufe/features/read_credit/presentation/read_credit_progress_section.dart';
import 'package:smarter_jxufe/features/read_credit/presentation/widgets/read_credit_ui.dart';

/// 学分平台侧的入馆教育进度卡（进度条 + 平台信息 + 明细入口）。
class ReadCreditEduCard extends ConsumerWidget {
  const ReadCreditEduCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(readCreditProgressProvider);
    return async.when(
      loading: () => readCreditCard(
        context,
        child: const Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('正在读取阅读学分平台…', style: TextStyle(fontSize: 13)),
          ],
        ),
      ),
      error: (error, _) =>
          readCreditCard(context, child: _errorBody(context, ref, '$error')),
      data: (bundle) {
        final part = bundle.partOf(ReadCreditKind.libraryEdu);
        if (part == null) {
          return readCreditCard(
            context,
            child: Text(
              '阅读学分平台未返回「入馆教育」项。',
              style: TextStyle(
                fontSize: 12.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }
        return ReadCreditPartCard(
          part: part,
          titleOverride: '阅读学分 · 第三部分 入馆教育',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  const ReadCreditDetailScreen(kind: ReadCreditKind.libraryEdu),
            ),
          ),
        );
      },
    );
  }

  Widget _errorBody(BuildContext context, WidgetRef ref, String message) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.error_outline, size: 17, color: scheme.error),
            const SizedBox(width: 8),
            const Text(
              '阅读学分平台读取失败',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          message,
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: () => ref.invalidate(readCreditProgressProvider),
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('重试'),
          ),
        ),
      ],
    );
  }
}
