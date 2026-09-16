/// 分数估计 · 总加权平均汇总卡（列表页顶部与课程详情页共用）。
library;

import 'package:flutter/material.dart';

import '../../../design/feature_palette.dart';
import '../../ims/grades/domain/grades_exclusions.dart';
import '../domain/ge_engine.dart';
import 'ge_common.dart';

/// 顶部汇总卡：教务已出成绩 + 本模块估计分的学分加权平均。
class GeWeightedSummaryCard extends StatelessWidget {
  final GeWeightedSummary summary;

  /// 未填期末（未计入合计）的课程数。
  final int pendingCount;
  final Color accent;

  /// 本专业培养方案名（用于说明学分来源）；空 = 未取到方案。
  final String planMajorName;

  const GeWeightedSummaryCard({
    super.key,
    required this.summary,
    required this.pendingCount,
    this.accent = FeaturePalette.cardAccent,
    this.planMajorName = '',
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final avg = summary.average;
    final hintStyle = TextStyle(
      fontSize: 11.5,
      height: 1.4,
      color: scheme.onSurfaceVariant,
    );

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: geCardShape(context),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            geCardTitle(
              context,
              text: '总加权平均',
              trailing: Text(
                summary.isEmpty
                    ? '暂无'
                    : '${summary.count} 门 · ${geFmt(summary.totalCredits)} 学分',
                style: hintStyle,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  avg == null ? '—' : geFmt(avg, decimals: 2),
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    height: 1.05,
                    color: avg == null ? scheme.onSurfaceVariant : accent,
                  ),
                ),
                const SizedBox(width: 6),
                Text('分', style: hintStyle),
                const Spacer(),
                if (!summary.isEmpty)
                  Text(
                    '教务已出 ${summary.gradesCount} 门 + 估计 '
                    '${summary.estimateCount} 门',
                    style: hintStyle,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            if (summary.isEmpty)
              Text(
                '暂无已确定分数的课程：在课程里填写期末分，或在「教务 · 成绩」页拉取成绩后回到本页。',
                style: hintStyle,
              )
            else ...[
              Text(
                '计入明细：教务已出成绩 ${summary.gradesCount} 门'
                '（${geFmt(summary.gradesCredits)} 学分）'
                '、本模块估计 ${summary.estimateCount} 门'
                '（${geFmt(summary.estimateCredits)} 学分）',
                style: hintStyle,
              ),
              Text(
                '逐课贡献 = 分数 × 学分 ÷ 总学分，各课贡献合计即总平均；'
                '同名课程以教务真实成绩计入。',
                style: hintStyle,
              ),
              Text('教务侧为成绩页全部已出成绩课程（含往期学期），按各课原始学分加权。', style: hintStyle),
              Text(
                planMajorName.isEmpty
                    ? '本模块课程的学分优先取本专业培养方案，未匹配的课用课程自身学分。'
                    : '本模块课程的学分优先取本专业培养方案（$planMajorName），未匹配的课用课程自身学分。',
                style: hintStyle,
              ),
              Text(
                '已按成绩页口径排除：${kExcludedGradeCourses.join('、')}。',
                style: hintStyle,
              ),
            ],
            if (pendingCount > 0) ...[
              const SizedBox(height: 2),
              Text(
                '另有 $pendingCount 门未填期末，暂未计入合计。',
                style: hintStyle.copyWith(
                  color: const Color(0xFFE65100),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
