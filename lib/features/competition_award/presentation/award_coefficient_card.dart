/// 竞赛奖励页 —— 「赛事经验系数」卡片与设置弹层。
///
/// 用户 2026-09-18 原话：「竞赛奖励有一个经验系数，就是有些奖项它拿的人太多，就会
/// 导致奖金被等比例缩小，而这个比例一般是固定的，我希望可以手动设置」。
/// 拍板两条口径（ask_user_question）：
/// - **按赛事设** —— 一个赛事的比例是固定的，配一次即可，该赛事所有记录等比缩减；
/// - **行内明算** —— 记录行显示「6000 元 × 0.6 = 3600 元」，并在「本次统计口径」里
///   说明哪几条被缩减。
///
/// 口径唯一出处 = `domain/award_coefficient.dart`（模型 + 解析 + 查表）与
/// `domain/award_calc.dart` 的 `competitionAwardOutcomeOf(coefficients:)`
/// （**乘在折减后、取最高之前**）；本文件只负责录入与展示。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/features/score_estimate/presentation/ge_common.dart';

import '../domain/award_calc.dart';
import '../domain/award_coefficient.dart';
import 'award_common.dart';

/// 「赛事经验系数」卡片。
///
/// [outcome] 用来算「这条系数影响几条记录」——**用真实计算结果反推**，
/// 而不是让调用方再筛一遍（口径只有一处）。
class AwardCoefficientCard extends StatelessWidget {
  const AwardCoefficientCard({
    super.key,
    required this.coefficients,
    required this.outcome,
    required this.loaded,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  final List<AwardCoefficient> coefficients;
  final CompetitionAwardOutcome outcome;
  final bool loaded;
  final VoidCallback onAdd;
  final ValueChanged<AwardCoefficient> onEdit;
  final ValueChanged<AwardCoefficient> onDelete;

  /// 该系数命中的记录条数（含未计入的——用户要对得上账）。
  int _hitCount(AwardCoefficient c) {
    final key = awardCoefficientKey(c.competitionName);
    var n = 0;
    for (final item in outcome.items) {
      if (awardCoefficientKey(item.record.competitionName) == key) n++;
    }
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final accent = fp(context).competitionAward;
    return KeyedSubtree(
      key: const Key('awardCoefficientCard'),
      child: awardCard(
        context,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            geCardTitle(
              context,
              text: '赛事经验系数',
              accent: accent,
              trailing: TextButton.icon(
                key: const Key('awardAddCoefficient'),
                onPressed: onAdd,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加'),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '办法第九条注：Ⅱ / Ⅲ类单个赛事总奖励金额超过 10 万元（部分版本 15 万元）时，'
              '按「奖励标准 ×（封顶额 / 该赛事总金额）」等比缩减。'
              '学校实际执行出来的那个比例（例如某赛事获奖人数过多、统一按 0.6 发放）'
              '可以在这里固定下来，该赛事的每条记录都按它等比缩减。',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.5,
                color: AppColors.textMuted(context),
              ),
            ),
            const SizedBox(height: 6),
            if (!loaded)
              const AwardEmptyHint(
                icon: Icons.hourglass_empty,
                text: '正在载入本地设置…',
              )
            else if (coefficients.isEmpty)
              AwardEmptyHint(
                icon: Icons.percent_outlined,
                text: '还没有设置赛事系数 —— 所有获奖都按奖励标准全额计算。',
                hint: '只有「拿的人太多、奖金被等比缩小」的赛事才需要设，其余留空即可。',
                actionLabel: '添加',
                actionKey: const Key('awardAddCoefficientEmpty'),
                onAction: onAdd,
              )
            else
              for (final c in coefficients) _tile(context, c, accent),
          ],
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, AwardCoefficient c, Color accent) {
    final hits = _hitCount(c);
    final unmatched = hits == 0;
    return Padding(
      key: Key('awardCoefficientTile-${c.competitionName}'),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.competitionName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  unmatched
                      ? '当前记录里没有这个赛事（留着下次用）'
                      : '影响 $hits 条记录：金额按 ×${fmtAwardCoefficient(c.factor)} 等比缩减',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.4,
                    color: AppColors.textMuted(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.tint(context, accent, 0.10),
                  border: Border.all(
                    color: AppColors.tintBorder(context, accent, 0.35),
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '×${fmtAwardCoefficient(c.factor)}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ),
              Row(
                children: [
                  IconButton(
                    key: Key('awardEditCoefficient-${c.competitionName}'),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 30,
                    ),
                    tooltip: '修改系数',
                    iconSize: 17,
                    icon: Icon(
                      Icons.edit_outlined,
                      color: AppColors.textMuted(context),
                    ),
                    onPressed: () => onEdit(c),
                  ),
                  IconButton(
                    key: Key('awardDeleteCoefficient-${c.competitionName}'),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 30,
                    ),
                    tooltip: '删除系数',
                    iconSize: 17,
                    icon: Icon(
                      Icons.delete_outline,
                      color: AppColors.textMuted(context),
                    ),
                    onPressed: () => onDelete(c),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 打开「赛事系数」录入弹层。
///
/// [editing] 非空 = 编辑已有系数（赛事名可改）；[knownNames] = 当前记录里出现过的
/// 赛事名，做成一键填入的 chip（避免手打长名字打错导致匹配不上）。
/// [onSave] 由页面接上 store（用回调而不是把 store 传进来：弹层不依赖数据层，
/// 测试里直接数「保存了什么」即可）。
Future<void> showAwardCoefficientSheet(
  BuildContext context, {
  required Future<void> Function(String name, double factor) onSave,
  AwardCoefficient? editing,
  List<String> knownNames = const [],
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => _AwardCoefficientSheet(
      onSave: onSave,
      editing: editing,
      knownNames: knownNames,
    ),
  );
}

class _AwardCoefficientSheet extends StatefulWidget {
  const _AwardCoefficientSheet({
    required this.onSave,
    this.editing,
    this.knownNames = const [],
  });

  final Future<void> Function(String name, double factor) onSave;
  final AwardCoefficient? editing;
  final List<String> knownNames;

  @override
  State<_AwardCoefficientSheet> createState() => _AwardCoefficientSheetState();
}

class _AwardCoefficientSheetState extends State<_AwardCoefficientSheet> {
  late final TextEditingController _nameCtrl = TextEditingController(
    text: widget.editing?.competitionName ?? '',
  );
  late final TextEditingController _factorCtrl = TextEditingController(
    text: widget.editing == null
        ? ''
        : fmtAwardCoefficient(widget.editing!.factor),
  );
  bool _busy = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _factorCtrl.dispose();
    super.dispose();
  }

  double? get _factor => parseAwardCoefficient(_factorCtrl.text);
  bool get _canSave =>
      !_busy && _nameCtrl.text.trim().isNotEmpty && _factor != null;

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final factor = _factor;
    if (name.isEmpty || factor == null || _busy) return;
    setState(() => _busy = true);
    await widget.onSave(name, factor);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final accent = fp(context).competitionAward;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.editing == null ? '添加赛事系数' : '修改赛事系数',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              '系数小于 1 表示等比缩减（0.6 = 发标准的 60%），1 表示不缩减。'
              '同一赛事的每条记录都按它缩减，未设置的赛事不受影响。',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.45,
                color: AppColors.textMuted(context),
              ),
            ),
            const SizedBox(height: 14),
            const AwardFieldLabel('赛事名称（与获奖记录里的名字一致）'),
            TextField(
              key: const Key('coefNameField'),
              controller: _nameCtrl,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                hintText: '例如：蓝桥杯全国软件和信息技术专业人才大赛',
              ),
            ),
            if (widget.knownNames.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < widget.knownNames.length; i++)
                    ActionChip(
                      key: Key('coefNameChip-$i'),
                      label: Text(
                        widget.knownNames[i],
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      onPressed: () => setState(() {
                        _nameCtrl.text = widget.knownNames[i];
                      }),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            const AwardFieldLabel('系数（可填 0.6 / 60% / 6折）'),
            TextField(
              key: const Key('coefFactorField'),
              controller: _factorCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.%％折]')),
              ],
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                hintText: '0.6',
              ),
            ),
            if (_factorCtrl.text.trim().isNotEmpty && _factor == null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '系数要在 0 ~ 1 之间（0.6 或 60% 或 6折）',
                  key: const Key('coefFactorError'),
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.caution(context),
                  ),
                ),
              ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _factor == null
                        ? '请填写赛事名与系数'
                        : '将按 ×${fmtAwardCoefficient(_factor!)} 缩减该赛事的记录',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textMuted(context),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const Key('coefSave'),
                  onPressed: _canSave ? _save : null,
                  style: FilledButton.styleFrom(backgroundColor: accent),
                  child: const Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
