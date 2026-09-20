/// 成绩页「总览卡」零件（2026-09-20 从 `grades_screen.dart` 外提 · 架构审查 ⑥）。
///
/// 原 `_GradesScreenState._buildSummary`（310 行）—— 提取成 StatelessWidget，
/// **State 侧字段一律走显式构造参数**（`excludedCourses` / `retakeScores` / `showDeltas`
/// 在块内均为只读引用，已逐个核实）。辅助件 `_decimalsForLabel` / `_statCard` 只在本块内
/// 使用，随块一起搬。
library;

import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/design/breakpoints.dart';
import 'package:smarter_jxufe/features/ims/grades/domain/grade.dart';

import 'package:smarter_jxufe/features/ims/grades/presentation/widgets/dashed_border.dart';

class GradesSummaryCard extends StatelessWidget {
  const GradesSummaryCard({
    super.key,
    required this.grades,
    required this.avgScore,
    required this.recommendationScore,
    required this.hasImportanceMap,
    required this.hasRetake,
    required this.deltas,
    required this.excludedCourses,
    required this.retakeScores,
    required this.showDeltas,
  });

  final List<Grade> grades;
  final double avgScore;
  final double recommendationScore;
  final bool hasImportanceMap;
  final bool hasRetake;
  final Map<String, double> deltas;
  final Set<String> excludedCourses;
  final Map<String, String> retakeScores;
  final bool showDeltas;

  @override
  Widget build(BuildContext context) {
    if (grades.isEmpty) return const SizedBox.shrink();
    final filtered = grades
        .where((g) => !excludedCourses.contains(g.courseName))
        .toList();
    if (filtered.isEmpty) return const SizedBox.shrink();

    double totalCredit = 0, totalGpCredit = 0;
    for (final g in filtered) {
      final c = double.tryParse(g.credit) ?? 0;
      final rawScore =
          double.tryParse(retakeScores[g.courseCode] ?? g.score) ?? 0;
      final gp = rawScore >= 60
          ? (double.tryParse(g.credit) ?? 0) * (rawScore / 10 - 5)
          : 0;
      totalCredit += c;
      totalGpCredit += gp;
    }
    final avgGp = totalCredit > 0 ? totalGpCredit / totalCredit : 0;

    final baseStyle = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.bold,
      color: Theme.of(context).colorScheme.error,
    );

    int decimalsForLabel(String label) => switch (label) {
      '课程' => 0,
      '总学分' => 1,
      'GPA' => 2,
      _ => 2,
    };

    Widget statCard(String label, String value, {bool dashed = false}) {
      final borderColor = AppColors.errorBorder(context);
      final dotIndex = value.indexOf('.');
      final delta = deltas[label];
      return Container(
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: BorderRadius.circular(12),
          border: dashed ? null : Border.all(color: borderColor),
        ),
        foregroundDecoration: dashed
            ? DashedBorderDecoration(
                color: borderColor,
                strokeWidth: 1.5,
                radius: 12,
              )
            : null,

        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            children: [
              Text.rich(
                TextSpan(
                  text: dotIndex == -1 ? value : value.substring(0, dotIndex),
                  style: baseStyle,
                  children: dotIndex == -1
                      ? null
                      : [
                          TextSpan(
                            text: value.substring(dotIndex),
                            style: baseStyle.copyWith(fontSize: 11),
                          ),
                        ],
                ),
              ),
              const SizedBox(height: 2),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) {
                  final keyStr = (child.key as ValueKey<String>).value;
                  final isDelta = keyStr.startsWith('d_');
                  final isCurrent = isDelta == showDeltas;
                  final begin = isCurrent
                      ? const Offset(0, -1)
                      : const Offset(0, 1);
                  return SlideTransition(
                    position: Tween<Offset>(
                      begin: begin,
                      end: Offset.zero,
                    ).animate(animation),
                    child: FadeTransition(opacity: animation, child: child),
                  );
                },
                child: Text(
                  delta != null
                      ? '${delta > 0 ? '+' : ''}${delta.toStringAsFixed(decimalsForLabel(label))}'
                      : label,
                  key: ValueKey(
                    delta != null
                        ? 'd_${delta.toStringAsFixed(decimalsForLabel(label))}'
                        : 'l_$label',
                  ),
                  style: delta != null
                      ? TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: delta > 0
                              ? AppColors.success(context)
                              : AppColors.critical(context),
                        )
                      : TextStyle(
                          fontSize: 11,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final cardData = <(String, String, bool)>[
      ('课程', '${filtered.length}', false),
      ('总学分', totalCredit.toStringAsFixed(1), false),
      ('课程加权', avgScore.toStringAsFixed(5), hasRetake),
      ('GPA', avgGp.toStringAsFixed(2), hasRetake),
    ];
    if (hasImportanceMap) {
      cardData.add(('推免加权', recommendationScore.toStringAsFixed(5), false));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final totalWidth = constraints.maxWidth;
          // 用 TextPainter 估算每张卡的内容宽度
          final painter = TextPainter(textDirection: TextDirection.ltr);
          double intrinsicSum = 0;
          final widths = <double>[];
          for (final d in cardData) {
            double maxW = 0;
            for (final text in [d.$2, d.$1]) {
              final isValue = text == d.$2;
              painter
                ..text = TextSpan(
                  text: text,
                  style: TextStyle(
                    fontSize: isValue ? 15 : 11,
                    fontWeight: isValue ? FontWeight.bold : FontWeight.normal,
                  ),
                )
                ..layout();
              if (painter.width > maxW) maxW = painter.width;
            }
            final w = maxW + 16;
            widths.add(w);
            intrinsicSum += w;
          }
          final extra = (totalWidth - intrinsicSum) / cardData.length;
          final extraPerCard = extra > 0 ? extra : 0.0;

          if (constraints.maxWidth < Breakpoints.tight) {
            // 窄屏：共享外侧框线，竖线分隔，沿用原宽度计算
            // 扣除 Card 内边距和竖线宽度
            final narrowWidth = totalWidth - 16 - (cardData.length - 1) * 1.0;
            final narrowExtra = (narrowWidth - intrinsicSum) / cardData.length;
            final epc = narrowExtra > 0 ? narrowExtra : 0.0;
            return Card(
              color: AppColors.card(context),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: AppColors.errorBorder(context),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: IntrinsicHeight(
                  child: Row(
                    children: [
                      for (int i = 0; i < cardData.length; i++) ...[
                        if (i > 0)
                          VerticalDivider(
                            width: 1,
                            color: Theme.of(
                              context,
                            ).dividerColor.withValues(alpha: 0.3),
                          ),
                        SizedBox(
                          width: widths[i] + epc,
                          child: Column(
                            children: [
                              Text.rich(
                                TextSpan(
                                  text: cardData[i].$2.contains('.')
                                      ? cardData[i].$2.substring(
                                          0,
                                          cardData[i].$2.indexOf('.'),
                                        )
                                      : cardData[i].$2,
                                  style: baseStyle,
                                  children: cardData[i].$2.contains('.')
                                      ? [
                                          TextSpan(
                                            text: cardData[i].$2.substring(
                                              cardData[i].$2.indexOf('.'),
                                            ),
                                            style: baseStyle.copyWith(
                                              fontSize: 11,
                                            ),
                                          ),
                                        ]
                                      : null,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 2),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                switchInCurve: Curves.easeOut,
                                switchOutCurve: Curves.easeIn,
                                transitionBuilder: (child, animation) {
                                  final keyStr =
                                      (child.key as ValueKey<String>).value;
                                  final isDelta = keyStr.startsWith('d_');
                                  final isCurrent = isDelta == showDeltas;
                                  final begin = isCurrent
                                      ? const Offset(0, -1)
                                      : const Offset(0, 1);
                                  return SlideTransition(
                                    position: Tween<Offset>(
                                      begin: begin,
                                      end: Offset.zero,
                                    ).animate(animation),
                                    child: FadeTransition(
                                      opacity: animation,
                                      child: child,
                                    ),
                                  );
                                },
                                child: Text(
                                  deltas[cardData[i].$1] != null
                                      ? '${deltas[cardData[i].$1]! > 0 ? '+' : ''}${deltas[cardData[i].$1]!.toStringAsFixed(cardData[i].$1 == '课程'
                                            ? 0
                                            : cardData[i].$1 == '总学分'
                                            ? 1
                                            : 2)}'
                                      : cardData[i].$1,
                                  key: ValueKey(
                                    deltas[cardData[i].$1] != null
                                        ? 'd_${deltas[cardData[i].$1]!.toStringAsFixed(2)}'
                                        : 'l_${cardData[i].$1}',
                                  ),
                                  textAlign: TextAlign.center,
                                  style: deltas[cardData[i].$1] != null
                                      ? TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: deltas[cardData[i].$1]! > 0
                                              ? AppColors.success(context)
                                              : AppColors.critical(context),
                                        )
                                      : TextStyle(
                                          fontSize: 11,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withValues(alpha: 0.6),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }

          return Row(
            children: [
              for (int i = 0; i < cardData.length; i++) ...[
                SizedBox(
                  width: widths[i] + extraPerCard,
                  child: statCard(
                    cardData[i].$1,
                    cardData[i].$2,
                    dashed: cardData[i].$3,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
