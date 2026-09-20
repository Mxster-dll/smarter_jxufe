/// AA 算账（服务主页）：成员 / 开销 / 结算三段。
///
/// 立项口径（用户 2026-09-19）：「我希望增加一个算账的工具，用于aa。我们可以手动
/// 添加一些开销，每个开销包括名称、金额、需要aa的人员；然后自动计算出每两个人之间
/// 的转钱情况」→ 本页第一张卡就是回答「谁该给谁转多少钱」。
///
/// 结算一律调领域层的 [aaSettle]（`domain/aa_settlement.dart`），**界面层不重算**：
/// 金额取分、平分余数、最少笔数配对都只有一份实现，改口径不会漏掉某一处。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/design/app_card.dart';
import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/design/pane_chrome.dart';
import 'package:smarter_jxufe/features/aa/data/aa_providers.dart';
import 'package:smarter_jxufe/features/aa/domain/aa_models.dart';
import 'package:smarter_jxufe/features/aa/domain/aa_settlement.dart';
import 'package:smarter_jxufe/features/aa/presentation/aa_expense_sheet.dart';
import 'package:smarter_jxufe/features/aa/presentation/aa_members_screen.dart';
import 'package:smarter_jxufe/features/score_estimate/presentation/ge_common.dart';
import 'package:smarter_jxufe/design/app_states.dart';

class AaScreen extends ConsumerWidget {
  const AaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(aaDataProvider);
    final data = async.valueOrNull;
    // ⚠ 同一批 action widget **两处都传**：整页模式由 `paneAppBar` 渲染进导航栏、
    // 内嵌模式由 `PaneBody` 下沉成内容首行；两种模式各只渲染其中一处（另一处拿不到
    // 实例），漏传哪一处都会让按钮在那种模式下整个消失。
    final actions = <Widget>[
      IconButton(
        tooltip: '成员管理',
        icon: const Icon(Icons.groups_outlined),
        onPressed: () => openAaMembers(context),
      ),
      IconButton(
        tooltip: '添加开销',
        icon: const Icon(Icons.add),
        onPressed: data == null ? null : () => _addExpense(context, ref, data),
      ),
    ];
    return Scaffold(
      appBar: paneAppBar(
        context,
        title: const Text('AA 算账'),
        actions: actions,
      ),
      body: PaneBody(
        padding: const EdgeInsets.fromLTRB(24, 2, 24, 2),
        actions: actions,
        child: async.when(
          loading: () => const AppLoadingState(),
          error: (e, _) => _errorBody(context, e),
          data: (d) => _body(context, ref, d),
        ),
      ),
    );
  }

  Widget _errorBody(BuildContext context, Object e) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        'AA 数据读取失败：$e',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12.5,
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
    ),
  );

  Widget _body(BuildContext context, WidgetRef ref, AaData data) => ListView(
    padding: const EdgeInsets.fromLTRB(24, 12, 24, 48),
    children: [
      _settlementCard(context, data),
      const SizedBox(height: 12),
      _membersCard(context, ref, data),
      const SizedBox(height: 12),
      _expensesCard(context, ref, data),
    ],
  );

  // ---- 结算 ----

  Widget _settlementCard(BuildContext context, AaData data) {
    final scheme = Theme.of(context).colorScheme;
    final s = data.settlement;
    return appCard(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          geCardTitle(
            context,
            text: '结算',
            trailing: Text(
              '共 ${s.expenseCount} 笔 · ${aaMoney(s.totalCents)}',
              style: TextStyle(fontSize: 11.5, color: scheme.outline),
            ),
          ),
          const SizedBox(height: 10),
          if (data.members.isEmpty)
            _hint(context, '还没有成员。AA 至少要有两个人：先建一份名单（可一键添加你自己和舍友）。')
          else if (data.expenses.isEmpty)
            _hint(context, '还没有开销。点右上角的「+」记下第一笔。')
          else ...[
            if (s.settled)
              Row(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 18,
                    color: AppColors.success(context),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    '已结清，谁都不用转钱',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ],
              )
            else
              for (final t in s.transfers) _transferRow(context, data, t),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Text(
              '每人净额（垫付 − 应分摊）',
              style: TextStyle(fontSize: 11, color: scheme.outline),
            ),
            const SizedBox(height: 4),
            for (final b in s.balances) _balanceRow(context, data, b),
          ],
        ],
      ),
    );
  }

  Widget _transferRow(BuildContext context, AaData data, AaTransfer t) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${data.nameOf(t.fromId)} → ${data.nameOf(t.toId)}',
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            aaMoney(t.cents),
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: scheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _balanceRow(BuildContext context, AaData data, AaBalance b) {
    final scheme = Theme.of(context).colorScheme;
    final net = b.netCents;
    final text = net == 0
        ? '已结清'
        : (net > 0 ? '应收 ${aaMoney(net)}' : '应付 ${aaMoney(-net)}');
    final color = net == 0
        ? scheme.outline
        : (net > 0 ? AppColors.success(context) : AppColors.critical(context));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  data.nameOf(b.memberId),
                  style: const TextStyle(fontSize: 13),
                ),
                // 学号 · 班级：结算时按人对号（重名的人靠它分清）。没有就不占位。
                if (data.detailOf(b.memberId).isNotEmpty)
                  Text(
                    data.detailOf(b.memberId),
                    style: TextStyle(fontSize: 10.5, color: scheme.outline),
                  ),
              ],
            ),
          ),
          Text(
            '垫付 ${aaMoney(b.paidCents)} · 分摊 ${aaMoney(b.shareCents)}',
            style: TextStyle(fontSize: 11, color: scheme.outline),
          ),
          const SizedBox(width: 10),
          Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ---- 成员 ----

  Widget _membersCard(BuildContext context, WidgetRef ref, AaData data) {
    return appCard(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          geCardTitle(
            context,
            text: '成员',
            trailing: TextButton(
              key: const Key('aaManageMembers'),
              onPressed: () => openAaMembers(context),
              child: const Text('管理', style: TextStyle(fontSize: 12)),
            ),
          ),
          if (data.members.isEmpty) ...[
            _hint(context, 'AA 的参与人：先加两个人，再记开销。可以一键添加你自己和舍友。'),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonal(
                key: const Key('aaEmptyAddMember'),
                onPressed: () => openAaMembers(context),
                child: const Text('添加成员'),
              ),
            ),
          ] else
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final m in data.members) _memberChip(context, m),
              ],
            ),
        ],
      ),
    );
  }

  /// 成员小胶囊：姓名 + （有学号/班级时）悬停看标识。
  ///
  /// 胶囊刻意只印姓名（一屋子人铺一行，塞进学号会挤成两行）；要**看得见**学号与
  /// 班级的地方是成员管理页的副标题行（`aa_members_screen.dart`）与结算卡的每人净额行
  /// （[AaMember.detail]）。
  Widget _memberChip(BuildContext context, AaMember m) {
    final scheme = Theme.of(context).colorScheme;
    final chip = Chip(
      label: Text(m.name, style: const TextStyle(fontSize: 12.5)),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      side: BorderSide.none,
      backgroundColor: scheme.surfaceContainerHighest,
    );
    return m.detail.isEmpty ? chip : Tooltip(message: m.detail, child: chip);
  }

  // ---- 开销 ----
  Widget _expensesCard(BuildContext context, WidgetRef ref, AaData data) {
    final scheme = Theme.of(context).colorScheme;
    final rows = aaSortedExpenses(data.expenses);
    return Material(
      color: appCardColor(context),
      shape: appCardShape(context),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
            child: geCardTitle(
              context,
              text: '开销',
              trailing: Text(
                '${rows.length} 笔',
                style: TextStyle(fontSize: 11.5, color: scheme.outline),
              ),
            ),
          ),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
              child: _hint(context, '点右上角的「+」添加第一笔开销。'),
            )
          else
            for (final e in rows) _expenseRow(context, ref, data, e),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _expenseRow(
    BuildContext context,
    WidgetRef ref,
    AaData data,
    AaExpense e,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final people = [
      for (final id in e.participantIds)
        if (data.memberOf(id) != null) id,
    ];
    return InkWell(
      key: Key('aaExpense-${e.id}'),
      onTap: () => _editExpense(context, ref, data, e),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.title,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${data.nameOf(e.payerId)} 垫付 · ${people.length} 人 AA · '
                    '${aaDateText(e.date)}',
                    style: TextStyle(fontSize: 11, color: scheme.outline),
                  ),
                ],
              ),
            ),
            Text(
              aaMoney(e.amountCents),
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            PopupMenuButton<String>(
              tooltip: '更多',
              icon: const Icon(Icons.more_vert, size: 18),
              onSelected: (v) {
                if (v == 'edit') {
                  _editExpense(context, ref, data, e);
                } else if (v == 'delete') {
                  _deleteExpense(context, ref, data, e);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem<String>(value: 'edit', child: Text('编辑')),
                PopupMenuItem<String>(value: 'delete', child: Text('删除')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---- 动作 ----

  Future<void> _addExpense(
    BuildContext context,
    WidgetRef ref,
    AaData data,
  ) async {
    if (data.members.isEmpty) {
      await _promptAddMembers(context);
      return;
    }
    final created = await showAaExpenseEditor(context, members: data.members);
    if (created == null) return;
    final store = await ref.read(aaStoreProvider.future);
    await store.saveExpenses([...data.expenses, created]);
    ref.invalidate(aaDataProvider);
  }

  Future<void> _editExpense(
    BuildContext context,
    WidgetRef ref,
    AaData data,
    AaExpense e,
  ) async {
    final edited = await showAaExpenseEditor(
      context,
      members: data.members,
      initial: e,
    );
    if (edited == null) return;
    final store = await ref.read(aaStoreProvider.future);
    await store.saveExpenses([
      for (final x in data.expenses)
        if (x.id == e.id) edited else x,
    ]);
    ref.invalidate(aaDataProvider);
  }

  Future<void> _deleteExpense(
    BuildContext context,
    WidgetRef ref,
    AaData data,
    AaExpense e,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.delete_outline),
        title: Text('删除「${e.title}」？'),
        content: Text('这一笔 ${aaMoney(e.amountCents)} 会从账里去掉，结算随之重算。'),
        actions: [
          TextButton(
            key: const Key('aaExpenseDeleteCancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('aaExpenseDeleteConfirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final store = await ref.read(aaStoreProvider.future);
    await store.saveExpenses([
      for (final x in data.expenses)
        if (x.id != e.id) x,
    ]);
    ref.invalidate(aaDataProvider);
  }

  Future<void> _promptAddMembers(BuildContext context) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.groups_outlined),
        title: const Text('先添加成员'),
        content: const Text('AA 需要知道「谁垫付、谁分摊」——先去成员页面加人。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('aaGoMembers'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('去添加'),
          ),
        ],
      ),
    );
    if (go != true || !context.mounted) return;
    openAaMembers(context);
  }

  Widget _hint(BuildContext context, String text) => Text(
    text,
    style: TextStyle(
      fontSize: 12,
      height: 1.4,
      color: Theme.of(context).colorScheme.outline,
    ),
  );
}

/// 打开成员管理页（主页的「管理 / 添加成员 / 成员管理」三处入口共用）。
void openAaMembers(BuildContext context) => Navigator.of(
  context,
).push<void>(MaterialPageRoute(builder: (_) => const AaMembersScreen()));
