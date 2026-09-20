/// 开销编辑弹层（新增 / 修改一笔 AA 开销）。
///
/// 字段与用户立项口径一致：**名称 + 金额 + 付款人（垫付人）+ 参与 AA 的人 + 日期**。
/// 付款人 / 参与人都从成员名单里选（不在这里新建成员——名单的唯一入口是成员管理页）。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import 'package:smarter_jxufe/features/aa/domain/aa_models.dart';

/// 打开开销编辑弹层；保存返回新开销，取消 / 点背景返回 null。
Future<AaExpense?> showAaExpenseEditor(
  BuildContext context, {
  required List<AaMember> members,
  AaExpense? initial,
  DateTime? now,
}) => showModalBottomSheet<AaExpense>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) =>
      AaExpenseSheet(members: members, initial: initial, now: now),
);

/// 学号 / 班级只做**悬停提示**（[AaMember.detail]）：胶囊本身仍只有名字，
/// 一屋子人铺一行不会被撑开；没有标识的成员原样返回，不挂空提示框。
Widget _withDetail(AaMember m, Widget child) =>
    m.detail.isEmpty ? child : Tooltip(message: m.detail, child: child);

class AaExpenseSheet extends StatefulWidget {
  final List<AaMember> members;

  /// 非空 = 编辑这一笔（id / 创建时刻保持不变）。
  final AaExpense? initial;

  /// 注入「今天」（测试用；空 = 真实时间）。
  final DateTime? now;

  const AaExpenseSheet({
    super.key,
    required this.members,
    this.initial,
    this.now,
  });

  @override
  State<AaExpenseSheet> createState() => _AaExpenseSheetState();
}

class _AaExpenseSheetState extends State<AaExpenseSheet> {
  late final TextEditingController _title;
  late final TextEditingController _amount;
  late String _payerId;
  late final Set<String> _participants;
  late DateTime _date;

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    _title = TextEditingController(text: init?.title ?? '');
    _amount = TextEditingController(
      text: init == null ? '' : init.amount.toStringAsFixed(2),
    );
    _title.addListener(_onChanged);
    _amount.addListener(_onChanged);
    _payerId =
        (init != null && widget.members.any((m) => m.id == init.payerId))
        ? init.payerId
        : (widget.members.isEmpty ? '' : widget.members.first.id);
    final initParts = init?.participantIds ?? const <String>[];
    _participants = <String>{
      for (final m in widget.members)
        if (init == null || initParts.contains(m.id)) m.id,
    };
    _date = init?.date ?? aaDay(widget.now ?? DateTime.now());
  }

  @override
  void dispose() {
    _title.removeListener(_onChanged);
    _amount.removeListener(_onChanged);
    _title.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  /// 输入的金额（**分**）；非法 / ≤ 0 → 0（保存按钮因此禁用）。
  int get _amountCents {
    final v = double.tryParse(_amount.text.trim().replaceAll(',', ''));
    if (v == null || !v.isFinite || v <= 0) return 0;
    return aaCentsOf(v);
  }

  bool get _canSave =>
      widget.members.isNotEmpty &&
      _title.text.trim().isNotEmpty &&
      _amountCents > 0 &&
      _participants.isNotEmpty &&
      _payerId.isNotEmpty;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 5, 12, 31),
    );
    if (picked == null || !mounted) return;
    setState(() => _date = aaDay(picked));
  }

  void _save() {
    final init = widget.initial;
    Navigator.of(context).pop(
      AaExpense(
        id: init?.id ?? const Uuid().v4(),
        title: _title.text.trim(),
        amount: aaYuanOf(_amountCents),
        payerId: _payerId,
        participantIds: [
          for (final m in widget.members)
            if (_participants.contains(m.id)) m.id,
        ],
        date: _date,
        createdAt: init?.createdAt ?? DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cents = _amountCents;
    final n = _participants.length;
    final share = (n == 0 || cents == 0) ? null : aaMoney((cents / n).round());

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.initial == null ? '添加开销' : '编辑开销',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('aaTitleField'),
              controller: _title,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                isDense: true,
                labelText: '名称',
                hintText: '聚餐 / 打车 / 房费…',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 12,
                ),
              ),
              style: const TextStyle(fontSize: 13.5),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('aaAmountField'),
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: const InputDecoration(
                isDense: true,
                labelText: '金额',
                prefixText: '¥ ',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 12,
                ),
              ),
              style: const TextStyle(fontSize: 13.5),
            ),
            const SizedBox(height: 14),
            _label(context, '谁垫付的'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final m in widget.members)
                  _withDetail(
                    m,
                    ChoiceChip(
                      key: Key('aaPayer-${m.id}'),
                      label: Text(
                        m.name,
                        style: const TextStyle(fontSize: 12.5),
                      ),
                      selected: _payerId == m.id,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => setState(() => _payerId = m.id),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _label(context, '参与 AA 的人'),
                const Spacer(),
                TextButton(
                  key: const Key('aaPartAll'),
                  onPressed: () => setState(
                    () => _participants
                      ..clear()
                      ..addAll([for (final m in widget.members) m.id]),
                  ),
                  child: const Text('全选', style: TextStyle(fontSize: 12)),
                ),
                TextButton(
                  key: const Key('aaPartNone'),
                  onPressed: () => setState(_participants.clear),
                  child: const Text('清空', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final m in widget.members)
                  _withDetail(
                    m,
                    FilterChip(
                      key: Key('aaPart-${m.id}'),
                      label: Text(
                        m.name,
                        style: const TextStyle(fontSize: 12.5),
                      ),
                      selected: _participants.contains(m.id),
                      visualDensity: VisualDensity.compact,
                      onSelected: (v) => setState(() {
                        if (v) {
                          _participants.add(m.id);
                        } else {
                          _participants.remove(m.id);
                        }
                      }),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              share == null
                  ? '选好金额与参与人后，这里会显示每人分摊多少'
                  : '$n 人平分 · 每人约 $share',
              key: const Key('aaShareText'),
              style: TextStyle(fontSize: 11.5, color: scheme.outline),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _label(context, '日期'),
                const SizedBox(width: 12),
                TextButton(
                  key: const Key('aaDateButton'),
                  onPressed: _pickDate,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.event_outlined, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        aaDateText(_date),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  key: const Key('aaExpenseCancel'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const Key('aaExpenseSave'),
                  onPressed: _canSave ? _save : null,
                  child: const Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(BuildContext context, String text) => Text(
    text,
    style: TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
      color: Theme.of(context).colorScheme.onSurface,
    ),
  );
}
