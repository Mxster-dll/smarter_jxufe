/// 竞赛奖励页 —— 共用小件与「统计时间范围」口径。
///
/// 为什么时间范围要单列一份口径：用户 2026-09-17 原话是「时间范围不是按学年，
/// 而是手动选择时间范围」——**判定永远只有一处**，即 `award_calc.dart` 的
/// `AwardDateRange`（按日比较、含首尾）落进 `competitionAwardOutcomeOf`；
/// 本文件里的预设只是「帮你把起止日期填好」的快捷方式，既不按学年过滤、
/// 也不与目录版本挂钩（目录版本只是竞赛名称与类别的出处）。
library;

import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/app_card.dart';
import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/school_term.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/wxcal_semester.dart';

import '../domain/award_calc.dart';
import '../domain/award_record.dart';
import '../domain/competition_catalog.dart';

/// 时间范围快捷预设（`.name` 直接进 Key：`awardRangePreset-<name>`）。
enum AwardRangePreset {
  currentTerm('本学期'),
  currentYear('本学年'),
  recentYear('近一年'),
  all('全部');

  const AwardRangePreset(this.label);

  final String label;

  Key get key => Key('awardRangePreset-$name');
}

/// 预设 → 手选区间；`null` = 不设区间（全部计入）。
///
/// - 「本学期」优先取校历快照里的**真实起止**（与课表 / 校历同源，见
///   `school_term.dart` 的「当下学期」唯一口径），快照取不到才按学段推：
///   第一学期 `[xn]-09-01 ~ [xn+1]-01-31`、第二学期 `[xn+1]-02-01 ~ [xn+1]-08-31`；
/// - 「本学年」= `[xn]-09-01 ~ [xn+1]-08-31`；
/// - 「近一年」= 今天往前 365 天；
/// - 「全部」= null（回到「不筛日期」的默认口径）。
AwardDateRange? awardRangeOfPreset(
  AwardRangePreset preset, {
  required DateTime now,
  List<WxSemesterArrangement> terms = const [],
}) {
  if (preset == AwardRangePreset.all) return null;
  if (preset == AwardRangePreset.recentYear) {
    return AwardDateRange(now.subtract(const Duration(days: 365)), now);
  }
  final term = currentSchoolTerm(now, terms: terms);
  if (preset == AwardRangePreset.currentYear) {
    return AwardDateRange(
      DateTime(term.xn, 9, 1),
      DateTime(term.xn + 1, 8, 31),
    );
  }
  for (final t in terms) {
    if (t.matches(xn: term.xn, xq: term.xq)) {
      return AwardDateRange(t.start, t.end);
    }
  }
  return term.xq == 0
      ? AwardDateRange(DateTime(term.xn, 9, 1), DateTime(term.xn + 1, 1, 31))
      : AwardDateRange(
          DateTime(term.xn + 1, 2, 1),
          DateTime(term.xn + 1, 8, 31),
        );
}

/// 日期展示：一律 `YYYY-MM-DD`（`fmtAwardDate`），未设置给「未设置」。
String awardDayText(DateTime? d) => d == null ? '未设置' : fmtAwardDate(d);

/// 页面通用卡片 —— 形状/描边唯一口径 = `lib/design/app_card.dart`。
Widget awardCard(
  BuildContext context, {
  required Widget child,
  EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(16, 14, 16, 12),
}) => Card(
  elevation: 0,
  margin: EdgeInsets.zero,
  shape: appCardShape(context),
  clipBehavior: Clip.antiAlias,
  child: Padding(padding: padding, child: child),
);

/// 类别胶囊：Ⅰ/Ⅱ/Ⅲ 类走功能强调色；Ⅳ类走警示色 —— 办法第九条注（1）明确
/// 「Ⅳ类学科竞赛只奖励指导教师（组），不奖励学生」，颜色先给出提示。
class AwardClassChip extends StatelessWidget {
  const AwardClassChip({super.key, required this.klass});

  final CompetitionClass klass;

  @override
  Widget build(BuildContext context) {
    final color = klass.rewardsStudents
        ? fp(context).competitionAward
        : AppColors.caution(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: AppColors.tint(context, color, 0.10),
        border: Border.all(color: AppColors.tintBorder(context, color, 0.35)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        klass.label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

/// 空态 / 未解析提示（可选一个重试按钮）。
class AwardEmptyHint extends StatelessWidget {
  const AwardEmptyHint({
    super.key,
    required this.icon,
    required this.text,
    this.hint,
    this.actionLabel,
    this.onAction,
    this.actionKey,
  });

  final IconData icon;
  final String text;
  final String? hint;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Key? actionKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.textMuted(context)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: const TextStyle(fontSize: 12.5, height: 1.45),
                ),
                if (hint != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      hint!,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.45,
                        color: AppColors.textMuted(context),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (actionLabel != null)
            TextButton(
              key: actionKey,
              onPressed: onAction,
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

/// 弹层里的字段标题（与 `ge_deadline_card.dart` 的 `_FieldLabel` 同一形态）。
class AwardFieldLabel extends StatelessWidget {
  const AwardFieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.textMuted(context),
      ),
    ),
  );
}
