/// 分数估计 · 总加权平均汇总卡（列表页与课程详情页共用）。
///
/// 用户口径（2026-09-26）：
/// - 「总加权页面不要显示：计入明细 / 逐课贡献 = 分数 × 学分 ÷ 总学分 / 教务侧口径 /
///   学分来源 / 排除名单 / 另有 N 门未填期末」→ 那六段说明**整块删掉**，
///   卡片只留：标题 + 门数学分 + 大号平均分 + 一行「教务已出 X 门 + 估计 Y 门」；
/// - 课程详情页要**同时算「含本课」与「不含本课」**：主数字显示含本课的加权平均，
///   右侧一枚胶囊给出本课带来的提升 / 减少（`withoutCourseAverage` 非空时才有）。
library;

import 'package:flutter/material.dart';

import '../../../design/app_theme.dart';
import '../../../design/feature_palette.dart';
import '../domain/ge_engine.dart';
import 'ge_common.dart';

/// 顶部汇总卡：教务已出成绩 + 本模块估计分的学分加权平均。
class GeWeightedSummaryCard extends StatelessWidget {
  final GeWeightedSummary summary;

  /// 「不含本课」的加权平均（课程详情页专用）。
  ///
  /// `null` = 不比较（列表页没有「本课」这个概念）。非空时右侧出 Δ 胶囊，
  /// 副行给出「不含本课 xx 分」。
  final double? withoutCourseAverage;

  /// 本课没进合计时的原因（`null` = 已计入）。
  ///
  /// 非空时**不出 Δ 胶囊**、改出这枚灰色胶囊 —— 没计入就没有「提升 / 减少」可言。
  /// 取值如「未填期末，暂未计入」「同名教务成绩已计入」。
  final String? courseExcludedNote;

  /// 强调色；不传 = `fp(context).cardAccent`（随亮度的主题红）。
  final Color? accent;

  const GeWeightedSummaryCard({
    super.key,
    required this.summary,
    this.withoutCourseAverage,
    this.courseExcludedNote,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accentColor = accent ?? fp(context).cardAccent;
    final avg = summary.average;
    final hintStyle = TextStyle(
      fontSize: 11.5,
      height: 1.4,
      color: scheme.onSurfaceVariant,
    );
    final without = withoutCourseAverage;

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
                    color: avg == null ? scheme.onSurfaceVariant : accentColor,
                  ),
                ),
                const SizedBox(width: 6),
                Text('分', style: hintStyle),
                const Spacer(),
                if (courseExcludedNote != null)
                  _notePill(context, courseExcludedNote!)
                else if (without != null && avg != null)
                  _deltaPill(context, avg - without),
              ],
            ),
            const SizedBox(height: 6),
            if (summary.isEmpty)
              Text(
                '暂无已确定分数的课程：在课程里填写期末分，或在「教务 · 成绩」页拉取成绩后回到本页。',
                style: hintStyle,
              )
            else
              Text(_infoLine(without, avg), style: hintStyle),
          ],
        ),
      ),
    );
  }

  /// 副行：`不含本课 85.97 分 · 教务已出 26 门 + 估计 1 门`。
  ///
  /// 本课**没计入**时不写「不含本课」——那时含本课与不含本课是同一个数，
  /// 写出来只会让人以为「少了什么」。
  String _infoLine(double? without, double? avg) {
    final head =
        '教务已出 ${summary.gradesCount} 门 + 估计 ${summary.estimateCount} 门';
    if (without == null || avg == null || courseExcludedNote != null) {
      return head;
    }
    return '不含本课 ${geFmt(without, decimals: 2)} 分 · $head';
  }

  /// Δ 胶囊：本课计入合计后带来的提升 / 减少（含 Tooltip 说清算法）。
  Widget _deltaPill(BuildContext context, double delta) {
    final up = delta > 0.005;
    final down = delta < -0.005;
    final color = up
        ? AppColors.success(context)
        : (down ? AppColors.critical(context) : AppColors.textMuted(context));
    final text = up
        ? '▲ +${geFmt(delta, decimals: 2)} 本课'
        : (down
              ? '▼ −${geFmt(delta.abs(), decimals: 2)} 本课'
              : '±0 本课');
    return Tooltip(
      message:
          '本课计入合计后，总加权平均相比「不含本课」'
          '${up ? '提高' : (down ? '降低' : '没变')} '
          '${geFmt(delta.abs(), decimals: 2)} 分',
      child: _pill(context, text, color),
    );
  }

  /// 灰色原因胶囊：本课没进合计（没计入就谈不上提升 / 减少）。
  Widget _notePill(BuildContext context, String text) =>
      _pill(context, text, AppColors.textMuted(context));

  Widget _pill(BuildContext context, String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: AppColors.tint(context, color, 0.12),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: 0.35)),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        color: color,
      ),
    ),
  );
}
