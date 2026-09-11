import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/library_edu/data/providers/tsgxs_providers.dart';
import 'package:smarter_jxufe/features/library_edu/domain/tsgxs_models.dart';

/// 我的成绩:本次成绩与考试记录。
class TsgxsGradeScreen extends ConsumerWidget {
  const TsgxsGradeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(tsgxsGradesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的成绩'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: () => ref.invalidate(tsgxsGradesProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              '$e',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: scheme.error),
            ),
          ),
        ),
        data: (grades) => grades.isEmpty
            ? Center(
                child: Text(
                  '暂无成绩记录',
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                children: [
                  _sectionTitle(context, '本次成绩', Icons.military_tech_outlined),
                  const SizedBox(height: 10),
                  _gradeTable(context, [grades.first]),
                  if (grades.length > 1) ...[
                    const SizedBox(height: 22),
                    _sectionTitle(context, '考试记录', Icons.history),
                    const SizedBox(height: 10),
                    _gradeTable(context, grades),
                  ],
                  const SizedBox(height: 18),
                  Text(
                    '成绩由平台按最高分保留;未通过考试不出现在排行榜中。',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.6,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _gradeTable(BuildContext context, List<TsgxsGrade> grades) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        children: [
          _row(context, const ['考试时间', '闯关用时', '分数'], header: true),
          for (final g in grades) ...[
            Divider(
              height: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
            _row(context, [g.examTime, g.elapsed, g.score]),
          ],
        ],
      ),
    );
  }

  Widget _row(BuildContext context, List<String> cells, {bool header = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          for (var i = 0; i < cells.length; i++)
            Expanded(
              flex: i == 0 ? 4 : 3,
              child: Text(
                cells[i],
                textAlign: i == 0 ? TextAlign.left : TextAlign.center,
                style: TextStyle(
                  fontSize: header ? 12 : 13,
                  fontWeight: header ? FontWeight.w600 : FontWeight.w500,
                  color: header
                      ? scheme.onSurfaceVariant
                      : (i == 2 ? scheme.primary : null),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title, IconData icon) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(width: 3, height: 14, color: scheme.primary),
        const SizedBox(width: 8),
        Icon(icon, size: 15, color: scheme.primary),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
