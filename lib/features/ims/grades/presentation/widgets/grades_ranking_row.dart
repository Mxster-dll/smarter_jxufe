/// 成绩页「排名行」零件（2026-09-20 从 `grades_screen.dart` 外提 · 架构审查 ⑥）。
///
/// 原 `_GradesScreenState._buildRankingRow`（237 行）—— **不引用任何 State 字段**
/// （只用自己的参数），故构造参数即全部依赖。辅助件 `_wideCard` / `_narrowRow`
/// 只在本块内使用，随块一起搬。
library;

import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/design/breakpoints.dart';
import 'package:smarter_jxufe/features/ims/grades/domain/weighted_grade.dart';

class GradesRankingRow extends StatelessWidget {
  const GradesRankingRow({
    super.key,
    required this.wg,
    required this.classTotal,
    required this.majorTotal,
    required this.gradeTotal,
  });

  final WeightedGrade? wg;
  final int classTotal;
  final int majorTotal;
  final int gradeTotal;

  @override
  Widget build(BuildContext context) {
    final isLoading = wg == null;

    final classRank = wg?.classRank ?? 0;
    final majorRank = wg?.majorRank ?? 0;
    final gradeRank = wg?.gradeRank ?? 0;

    Widget wideCard(int rank, int total) {
      final ratio = rank / total;
      return Expanded(
        child: Card(
          color: AppColors.card(context),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: AppColors.errorBorder(context),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (isLoading)
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else ...[
                      Text(
                        '$rank',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '/ $total',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${(ratio * 100).toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: isLoading ? 0 : ratio.clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget narrowRow(int rank, int total, double rankWidth, double pctWidth) {
      final ratio = rank / total;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: rankWidth,
              child: isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Row(
                      children: [
                        Text(
                          '$rank',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '/ $total',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: isLoading ? 0 : ratio.clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: pctWidth,
              child: Text(
                '${(ratio * 100).toStringAsFixed(1)}%',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < Breakpoints.tight) {
            // 计算最宽行的排名和百分比宽度，使进度条对齐
            final tp = TextPainter(textDirection: TextDirection.ltr);
            double maxRankW = 0, maxPctW = 0;
            for (final (r, t) in [
              (classRank, classTotal),
              (majorRank, majorTotal),
              (gradeRank, gradeTotal),
            ]) {
              // 排名用20px bold + 4px间距 + "/ total"用12px
              tp.text = TextSpan(
                text: '$r',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              );
              tp.layout();
              double w = tp.width + 4;
              tp.text = TextSpan(
                text: '/ $t',
                style: const TextStyle(fontSize: 12),
              );
              tp.layout();
              w += tp.width;
              if (w > maxRankW) maxRankW = w;
              tp.text = TextSpan(
                text: '${(r / t * 100).toStringAsFixed(1)}%',
                style: const TextStyle(fontSize: 11),
              );
              tp.layout();
              if (tp.width > maxPctW) maxPctW = tp.width;
            }
            maxRankW += 18;
            maxPctW += 8;

            return Card(
              color: AppColors.card(context),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: AppColors.errorBorder(context),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Column(
                  children: [
                    narrowRow(classRank, classTotal, maxRankW, maxPctW),
                    narrowRow(majorRank, majorTotal, maxRankW, maxPctW),
                    narrowRow(gradeRank, gradeTotal, maxRankW, maxPctW),
                  ],
                ),
              ),
            );
          }
          return Row(
            children: [
              wideCard(classRank, classTotal),
              wideCard(majorRank, majorTotal),
              wideCard(gradeRank, gradeTotal),
            ],
          );
        },
      ),
    );
  }
}
