/// 竞赛奖励 · 「添加 / 编辑获奖记录」底部弹层。
///
/// 实时预览（`awardExpectedAmount`）刻意**只喂这一条草稿**给
/// `competitionAwardOutcomeOf`：这样「Ⅳ类不奖励学生」「设特等奖赛事里三等奖落到
/// 第 4 档不奖励」「等次认不出」这些办法口径在敲字时就能看见，而不是等到保存后
/// 才发现金额是 0 —— 但**同一竞赛取最高 / Ⅱ Ⅲ类不累计**这类跨记录口径不在此处
/// 生效（它们要看全表，由页面合计卡负责）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/design/feature_palette.dart';

import '../data/competition_award_store.dart';
import '../domain/award_calc.dart';
import '../domain/award_record.dart';
import '../domain/award_standard.dart';
import '../domain/competition_catalog.dart';
import 'award_catalog_card.dart';
import 'award_common.dart';

/// 打开「添加 / 编辑获奖记录」弹层。
///
/// [editing] 非空 = 编辑（id 不变）；[preset] = 从竞赛目录点进来时的预填条目。
Future<void> showAwardRecordSheet(
  BuildContext context,
  WidgetRef ref, {
  CompetitionAwardRecord? editing,
  CompetitionEntry? preset,
}) {
  final standard =
      ref.read(awardStandardProvider).valueOrNull ?? AwardStandard.empty;
  final catalog =
      ref.read(competitionCatalogProvider).valueOrNull ??
      CompetitionCatalog.empty;
  final store = ref.read(competitionAwardStoreProvider);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => _AwardRecordSheet(
      ref: ref,
      standard: standard,
      catalog: catalog,
      store: store,
      editing: editing,
      preset: preset,
    ),
  );
}

class _AwardRecordSheet extends StatefulWidget {
  const _AwardRecordSheet({
    required this.ref,
    required this.standard,
    required this.catalog,
    required this.store,
    this.editing,
    this.preset,
  });

  /// 页面侧的 ref（用来开目录浏览弹层、读 provider 缓存），不是 ConsumerWidget 的。
  final WidgetRef ref;

  final AwardStandard standard;
  final CompetitionCatalog catalog;
  final CompetitionAwardStore store;
  final CompetitionAwardRecord? editing;
  final CompetitionEntry? preset;

  @override
  State<_AwardRecordSheet> createState() => _AwardRecordSheetState();
}

class _AwardRecordSheetState extends State<_AwardRecordSheet> {
  late final TextEditingController _nameCtrl = TextEditingController(
    text: widget.editing?.competitionName ?? widget.preset?.name ?? '',
  );
  late final TextEditingController _noteCtrl = TextEditingController(
    text: widget.editing?.note ?? '',
  );

  late CompetitionClass _klass =
      widget.editing?.klass ??
      widget.preset?.klass ??
      CompetitionClass.ii;
  late AwardScope _scope = widget.editing?.scope ?? AwardScope.national;
  late DateTime? _date = widget.editing?.date;
  late bool _hasSpecialTier = widget.editing?.hasSpecialTier ?? false;
  late AwardAdjustment _adjustment =
      widget.editing?.adjustment ?? AwardAdjustment.none;
  late String? _edition = widget.editing?.edition ?? widget.preset?.edition;
  late String _tier = widget.editing?.tierLabel ?? '';

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (_tier.isEmpty) _tier = _firstTier(_klass);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  /// 某类别的等次选项。
  ///
  /// Ⅳ类取**指导教师**那一组：办法里Ⅳ类表本来就只列教师金额（第九条注（1）），
  /// 用学生的口径查是空表、等次连填都填不了；金额是不是 0 由 `award_calc.dart`
  /// 判定（Ⅳ类直接给 0 + 注记原因），与本处的选项无关。
  List<String> _tiers(CompetitionClass klass) => widget.standard.tierOptions(
    klass,
    audience: klass.rewardsStudents
        ? AwardAudience.student
        : AwardAudience.teacher,
  );

  String _firstTier(CompetitionClass klass) {
    final options = _tiers(klass);
    return options.isEmpty ? '' : options.first;
  }

  void _selectClass(CompetitionClass klass) => setState(() {
    _klass = klass;
    final options = _tiers(klass);
    if (!options.contains(_tier)) _tier = _firstTier(klass);
  });

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      // 与「统计时间范围」卡的日期口径一致：起点给到 2000（往届获奖回填），
      // 末端只留未来一年。
      firstDate: DateTime(2000),
      lastDate: now.add(const Duration(days: 365)),
      helpText: '选择获奖日期',
    );
    if (picked == null || !mounted) return;
    setState(() => _date = DateTime(picked.year, picked.month, picked.day));
  }

  Future<void> _pickFromCatalog() async {
    final picked = await showAwardCatalogSheet(
      context,
      catalog: widget.catalog,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _nameCtrl.text = picked.name;
      _klass = picked.klass;
      _edition = picked.edition;
      final options = _tiers(picked.klass);
      if (!options.contains(_tier)) _tier = _firstTier(picked.klass);
    });
  }

  /// 当前草稿（保存与预览共用，避免两处字段拼装不一致）。
  CompetitionAwardRecord get _draft => CompetitionAwardRecord(
    id: widget.editing?.id ?? 'draft',
    competitionName: _nameCtrl.text.trim(),
    klass: _klass,
    tierLabel: _tier,
    scope: _scope,
    date: _date,
    hasSpecialTier: _hasSpecialTier,
    adjustment: _adjustment,
    edition: _edition,
    note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
  );

  bool get _canSave => _nameCtrl.text.trim().isNotEmpty;

  String get _previewText {
    if (!_klass.rewardsStudents) {
      return '预计奖励：0 元 —— 办法第九条注（1）：Ⅳ类只奖励指导教师（组），不奖励学生';
    }
    final item = competitionAwardOutcomeOf(
      records: [_draft],
      standard: widget.standard,
      range: null,
    ).items.single;
    if (item.counted) return '预计奖励：${fmtAwardAmount(item.amount)}';
    return '该项按办法不产生奖励：${item.reason}';
  }

  Future<void> _save() async {
    if (!_canSave || _saving) return;
    setState(() => _saving = true);
    final draft = _draft;
    final record = CompetitionAwardRecord(
      id: widget.editing?.id ?? newAwardRecordId(),
      competitionName: draft.competitionName,
      klass: draft.klass,
      tierLabel: draft.tierLabel,
      scope: draft.scope,
      date: draft.date,
      hasSpecialTier: draft.hasSpecialTier,
      adjustment: draft.adjustment,
      edition: draft.edition,
      note: draft.note,
    );
    if (widget.editing == null) {
      await widget.store.add(record);
    } else {
      await widget.store.update(record);
    }
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final accent = fp(context).competitionAward;
    final tiers = _tiers(_klass);
    final specialEligible =
        _klass == CompetitionClass.ii || _klass == CompetitionClass.iii;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.emoji_events_outlined, size: 20, color: accent),
                const SizedBox(width: 8),
                Text(
                  widget.editing == null ? '添加获奖记录' : '编辑获奖记录',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              key: const Key('awardNameField'),
              controller: _nameCtrl,
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: '竞赛名称',
                hintText: '如 全国大学生数学建模竞赛',
                suffixIcon: IconButton(
                  key: const Key('awardPickFromCatalog'),
                  tooltip: '从竞赛目录选择',
                  icon: const Icon(Icons.menu_book_outlined, size: 20),
                  onPressed: _pickFromCatalog,
                ),
              ),
            ),
            if (_edition != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '目录版本：$_edition',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textMuted(context),
                  ),
                ),
              ),
            const SizedBox(height: 14),
            const AwardFieldLabel('竞赛类别（办法第七条）'),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final klass in CompetitionClass.values)
                  ChoiceChip(
                    key: Key('awardClassChip-${klass.name}'),
                    label: Text(klass.label),
                    selected: _klass == klass,
                    onSelected: (_) => _selectClass(klass),
                  ),
              ],
            ),
            if (!_klass.rewardsStudents)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  key: const Key('awardClassIvNotice'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.tint(
                      context,
                      AppColors.caution(context),
                      0.08,
                    ),
                    border: Border.all(
                      color: AppColors.tintBorder(
                        context,
                        AppColors.caution(context),
                        0.35,
                      ),
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '办法规定Ⅳ类只奖励指导教师，不奖励学生：'
                    '本条可以保存（教师口径仍要留档），但预计奖励 0 元。',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.5,
                      color: AppColors.caution(context),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 4),
            Text(
              _klass.description,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.5,
                color: AppColors.textMuted(context),
              ),
            ),
            const SizedBox(height: 12),
            const AwardFieldLabel('获奖等次（办法第十条）'),
            if (tiers.isEmpty)
              TextField(
                key: const Key('awardTierField'),
                onChanged: (v) => setState(() => _tier = v.trim()),
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: '等次',
                  hintText: '该类别办法没列奖励等次，可手填',
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final tier in tiers)
                    ChoiceChip(
                      key: Key('awardTierChip-$tier'),
                      label: Text(tier),
                      selected: _tier == tier,
                      onSelected: (_) => setState(() => _tier = tier),
                    ),
                ],
              ),
            if (specialEligible) ...[
              const SizedBox(height: 4),
              SwitchListTile(
                key: const Key('awardSpecialTierSwitch'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _hasSpecialTier,
                onChanged: (v) => setState(() => _hasSpecialTier = v),
                title: const Text('该赛事设特等奖', style: TextStyle(fontSize: 13.5)),
                subtitle: Text(
                  '办法第十条：设特等奖的赛事里，特等奖对应一等奖、'
                  '一等奖对应二等奖并依此类推（三/四等奖就落到第 4 档、不予奖励）。',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.45,
                    color: AppColors.textMuted(context),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            const AwardFieldLabel('赛别（办法第八条）'),
            Wrap(
              spacing: 8,
              children: [
                for (final scope in AwardScope.values)
                  ChoiceChip(
                    key: Key('awardScopeChip-${scope.name}'),
                    label: Text(scope.label),
                    selected: _scope == scope,
                    onSelected: (_) => setState(() => _scope = scope),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            const AwardFieldLabel('获奖日期（时间范围按它筛选）'),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('awardDateField'),
                    onPressed: _pickDate,
                    icon: const Icon(Icons.event, size: 18),
                    label: Text(awardDayText(_date)),
                  ),
                ),
                if (_date != null)
                  IconButton(
                    key: const Key('awardClearDate'),
                    tooltip: '清空日期',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _date = null),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '选填。填了才能在合计卡里按时间范围筛选 —— 没填的记录在设了范围后'
              '一律不计入（会标注「缺获奖日期」）。',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.45,
                color: AppColors.textMuted(context),
              ),
            ),
            const SizedBox(height: 12),
            const AwardFieldLabel('折减口径（办法第九条注）'),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final a in AwardAdjustment.values)
                  ChoiceChip(
                    key: Key('awardAdjustmentChip-${a.name}'),
                    label: Text(a.label),
                    selected: _adjustment == a,
                    onSelected: (_) => setState(() => _adjustment = a),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('awardNoteField'),
              controller: _noteCtrl,
              maxLines: 2,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: '备注（可选）',
                hintText: '如 团队 3 人 / 证书编号 / 省赛推荐国赛',
              ),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: AppColors.tint(context, accent, 0.06),
                border: Border.all(
                  color: AppColors.tintBorder(context, accent, 0.30),
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _previewText,
                key: const Key('awardExpectedAmount'),
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textBase(context),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: _canSave && !_saving ? _save : null,
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('保存'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
