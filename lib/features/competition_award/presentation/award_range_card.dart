/// 竞赛奖励 · 「统计时间范围」卡（页面第一张）。
///
/// 这是本功能的**主控**：用户 2026-09-17 口径「时间范围不是按学年，而是手动选择
/// 时间范围」→ 起止日期手选、按日筛选获奖记录再合计（口径实现只在
/// `award_calc.dart`，本卡不自己算钱）。
library;

import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/wxcal_semester.dart';
import 'package:smarter_jxufe/features/score_estimate/presentation/ge_common.dart';

import '../domain/award_calc.dart';
import 'award_common.dart';

class AwardRangeCard extends StatelessWidget {
  const AwardRangeCard({
    super.key,
    required this.range,
    required this.outcome,
    required this.now,
    required this.terms,
    required this.onChanged,
  });

  /// 当前区间；null = 不筛日期（全部计入）。
  final AwardDateRange? range;

  final CompetitionAwardOutcome outcome;

  /// 注入「今天」（预设区间与日期选择器的起点；测试也用它固定结果）。
  final DateTime now;

  /// 校历学期快照 —— 「本学期」预设取它的真实起止。
  final List<WxSemesterArrangement> terms;

  final ValueChanged<AwardDateRange?> onChanged;

  Future<void> _pick(BuildContext context, {required bool isStart}) async {
    final current = range;
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? (current?.start ?? now) : (current?.end ?? now),
      // 获奖日期可能很老（往届赛事回填），起点给到 2000；末端只留未来一年
      // （竞赛奖励是「已获奖」的登记，不需要选到很久以后）。
      firstDate: DateTime(2000),
      lastDate: now.add(const Duration(days: 365)),
      helpText: isStart ? '选择起始日期' : '选择结束日期',
    );
    if (picked == null) return;
    final day = DateTime(picked.year, picked.month, picked.day);
    if (isStart) {
      // 起点晚于已有终点时，把终点一起带过去（不静默丢弃用户刚选的日期）。
      final end = current?.end;
      onChanged(
        AwardDateRange(day, end != null && end.isBefore(day) ? day : end ?? day),
      );
      return;
    }
    final start = current?.start;
    onChanged(
      AwardDateRange(start != null && start.isAfter(day) ? day : start ?? day, day),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = fp(context).competitionAward;
    final current = range;
    // 每帧重算：`now` / `terms` 变化时预设区间随之变化。
    final presetRanges = <AwardRangePreset, AwardDateRange?>{
      for (final preset in AwardRangePreset.values)
        preset: awardRangeOfPreset(preset, now: now, terms: terms),
    };

    return KeyedSubtree(
      key: const Key('awardRangeCard'),
      child: awardCard(
        context,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            geCardTitle(
              context,
              text: '统计时间范围',
              accent: accent,
              trailing: TextButton(
                key: const Key('awardClearRange'),
                onPressed: current == null ? null : () => onChanged(null),
                child: const Text('清除'),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: _dayField(
                    context,
                    key: const Key('awardRangeStart'),
                    label: '起始日期',
                    day: current?.start,
                    onTap: () => _pick(context, isStart: true),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    '至',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted(context),
                    ),
                  ),
                ),
                Expanded(
                  child: _dayField(
                    context,
                    key: const Key('awardRangeEnd'),
                    label: '结束日期',
                    day: current?.end,
                    onTap: () => _pick(context, isStart: false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final preset in AwardRangePreset.values)
                  ChoiceChip(
                    key: preset.key,
                    label: Text(preset.label),
                    selected:
                        presetRanges[preset]?.label == current?.label,
                    onSelected: (_) => onChanged(presetRanges[preset]),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              current == null
                  ? '未设时间范围：全部获奖记录都计入合计（含未填日期的记录）。'
                  : '只合计获奖日期落在 ${current.label} 内的记录；'
                        '缺获奖日期或落在区间外的记录会在下方标注原因。',
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: AppColors.textMuted(context),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              fmtAwardAmount(outcome.total),
              key: const Key('awardTotal'),
              style: TextStyle(
                fontSize: 30,
                height: 1.1,
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '计入 ${outcome.countedCount} 条 · 未计入 ${outcome.excludedItems.length} 条',
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.textMuted(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dayField(
    BuildContext context, {
    required Key key,
    required String label,
    required DateTime? day,
    required VoidCallback onTap,
  }) {
    final accent = fp(context).competitionAward;
    final set = day != null;
    return OutlinedButton(
      key: key,
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        alignment: Alignment.centerLeft,
        foregroundColor: set ? AppColors.textBase(context) : AppColors.textMuted(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              color: AppColors.textMuted(context),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            awardDayText(day),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: set ? accent : AppColors.textMuted(context),
            ),
          ),
        ],
      ),
    );
  }
}
