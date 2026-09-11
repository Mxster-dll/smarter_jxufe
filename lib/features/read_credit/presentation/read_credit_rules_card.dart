/// 阅读学分「学分说明」卡（用户反馈原 ExpansionTile 排版很乱 → 重排）。
///
/// 版式：卡头（图标 + 标题 + 副标题）→ 4 条编号规则（序号块 + 标题 + 正文）
/// → 底部两条灰底提示（学分归属 / 更新与登录要求）。
library;

import 'package:flutter/material.dart';

import 'package:smarter_jxufe/features/read_credit/domain/read_credit_models.dart';
import 'package:smarter_jxufe/features/read_credit/presentation/widgets/read_credit_ui.dart';

/// 学分说明卡（静态规则原文，无需折叠）。
class ReadCreditRulesCard extends StatelessWidget {
  const ReadCreditRulesCard({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return readCreditCard(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              readCreditIconBox(Icons.menu_book_outlined, readCreditAccent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '学分说明',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '共 1 分 · 四部分全部完成后由图书馆出具证明',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < readCreditRules.length; i++) ...[
            if (i > 0) ...[
              const SizedBox(height: 12),
              Divider(height: 1, color: scheme.outlineVariant),
              const SizedBox(height: 12),
            ],
            _ruleRow(context, i, readCreditRules[i]),
          ],
          const SizedBox(height: 14),
          _hintBlock(context, Icons.verified_outlined, readCreditNotice),
          const SizedBox(height: 8),
          _hintBlock(context, Icons.schedule_outlined, readCreditUpdateHint),
        ],
      ),
    );
  }

  Widget _ruleRow(BuildContext context, int index, ReadCreditRule rule) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: readCreditAccent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '${index + 1}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: readCreditAccent,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                rule.title,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                rule.body,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.6,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _hintBlock(BuildContext context, IconData icon, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.6,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
