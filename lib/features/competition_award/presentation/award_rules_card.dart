/// 竞赛奖励 · 「口径提示」卡。
///
/// 为什么单列一张卡：奖励金额不是简单查表 —— 本次统计可能触发了第九条注
/// （Ⅳ类不奖励学生 / Ⅱ Ⅲ类不累计 / 挑战杯非主体赛道按Ⅱ类 / 国际项目 70%）
/// 与第十条（等级认定、同年同赛事取最高）。这些口径由 `award_calc.dart` 在计算时
/// 收集进 `appliedRules`，本卡**照原样展示**，不在这里重写判定。
library;

import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/features/rules/domain/rule_doc.dart';
import 'package:smarter_jxufe/features/rules/presentation/rules_reader_screen.dart';
import 'package:smarter_jxufe/features/score_estimate/presentation/ge_common.dart';

import '../domain/award_calc.dart';
import '../domain/award_standard.dart';
import 'award_common.dart';

/// 表下注记里最该露出的三句（办法第九条注与单赛事上限）。
const List<String> awardNoteNeedles = ['不奖励学生', '不累计', '总奖励金额不超过'];

class AwardRulesCard extends StatelessWidget {
  const AwardRulesCard({
    super.key,
    required this.outcome,
    required this.standard,
    required this.doc,
    this.onRetry,
  });

  final CompetitionAwardOutcome outcome;
  final AwardStandard standard;

  /// 《学科竞赛管理办法》原文文档（null = 资料库里没找到，按钮禁用）。
  final RuleDoc? doc;

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final accent = fp(context).competitionAward;
    final notes = <String>[];
    for (final needle in awardNoteNeedles) {
      final note = standard.noteContaining(needle);
      if (note != null && !notes.contains(note)) notes.add(note);
      if (notes.length >= 3) break;
    }

    return KeyedSubtree(
      key: const Key('awardRulesCard'),
      child: awardCard(
        context,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            geCardTitle(context, text: '本次统计口径', accent: accent),
            const SizedBox(height: 6),
            if (!standard.hasData)
              AwardEmptyHint(
                icon: Icons.rule_folder_outlined,
                text: '未解析到奖励标准',
                hint: '资料库里的《学科竞赛管理办法》没解析出奖励标准表，'
                    '本次无法测算金额（记录本身仍会保留）。',
                actionLabel: '重试',
                actionKey: const Key('awardStandardRetry'),
                onAction: onRetry,
              )
            else ...[
              for (final rule in outcome.appliedRules)
                _line(context, '· $rule', muted: false),
              if (outcome.appliedRules.isEmpty)
                _line(
                  context,
                  '· 本次记录都直接按办法第九条奖励标准表计算，未触发额外口径。',
                  muted: true,
                ),
              for (final note in notes) _line(context, '· $note', muted: true),
              if (standard.sourceTitle != null) ...[
                const SizedBox(height: 6),
                Text(
                  '出处：${standard.sourceTitle}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textBase(context),
                  ),
                ),
              ],
            ],
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const Key('awardOpenSource'),
                onPressed: doc == null
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => RulesReaderScreen(doc: doc!),
                        ),
                      ),
                child: const Text('查看《学科竞赛管理办法》原文'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(BuildContext context, String text, {required bool muted}) =>
      Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            height: 1.55,
            color: muted
                ? AppColors.textMuted(context)
                : AppColors.textBase(context),
          ),
        ),
      );
}
