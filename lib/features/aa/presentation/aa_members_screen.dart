/// AA 成员管理（二级页）：名单的唯一入口。
///
/// 为什么是整页而不是弹窗：`AlertDialog` 的内容恒被 `IntrinsicWidth` 包裹，里面既
/// 放不了 `ListView`（viewport 不支持 intrinsic 尺寸，弹窗会永不渲染）又要为输入框
/// 猜宽度；成员是会长大的列表，整页最省事，也顺带拿到了「面板内二级页」的标准返回键。
///
/// 三个入口（用户 2026-09-19 三轮原话「我们只要添加自己、添加室友、其他范围的同学
/// 不允许批量添加」）：**添加成员**（手打名字）/ **添加我自己**（账号显示名 + 学籍，
/// [aaSelfInfoProvider]）/ **添加全部舍友**（数据中心名单 + 我自己，四轮原话
/// 「点击添加全部舍友时应该一起把自己添加了」→ [aaImportRoommates]）。
/// 同班 / 同专业 / 同学院 / 同年级**一律不给批量入口** —— 想看名单去数据中心的
/// 「校内关系」卡，那边只看不落库。
///
/// 每行显示姓名 + **学号 · 班级**（五轮原话「我希望成员可以显示学号和班级」）：
/// 名字下面挂一行学号/班级，重名时认人；两者都没有（老数据 / 手打只填名字）就不占位。
///
/// 删除口径（对齐结算引擎 `aaSettle` 的语义）：
/// - 有人**垫付过**的成员不能直接删（删了钱就没人认账）→ 提示先改这些开销的付款人；
/// - 只参与过分摊的成员可以删：确认后从各笔开销的参与人里剔除，**其余人重新平分**。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:smarter_jxufe/core/errors/app_exception.dart';
import 'package:smarter_jxufe/design/pane_chrome.dart';
import 'package:smarter_jxufe/features/aa/data/aa_providers.dart';
import 'package:smarter_jxufe/features/aa/domain/aa_import.dart';
import 'package:smarter_jxufe/features/aa/domain/aa_models.dart';
import 'package:smarter_jxufe/features/aa/domain/aa_settlement.dart';
import 'package:smarter_jxufe/features/aa/presentation/aa_member_sheet.dart';
import 'package:smarter_jxufe/features/data_center/data/providers/data_center_providers.dart';
import 'package:smarter_jxufe/features/data_center/domain/dzj_peer.dart';

class AaMembersScreen extends ConsumerStatefulWidget {
  const AaMembersScreen({super.key});

  @override
  ConsumerState<AaMembersScreen> createState() => _AaMembersScreenState();
}

class _AaMembersScreenState extends ConsumerState<AaMembersScreen> {
  /// 正在忙的入口（'self' / 'roommates'）：既是两个按钮的共用禁用闸门，
  /// 也决定转圈画在哪一枚上（拉数据中心名单要走网络，必须给反馈）。
  String? _busy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final data = ref.watch(aaDataProvider).valueOrNull ?? AaData.empty;

    return Scaffold(
      appBar: paneAppBar(context, title: const Text('AA 成员')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 48),
        children: [
          Text(
            '参与 AA 的人。开销里的「谁垫付 / 谁分摊」都从这份名单里选，'
            '改名不会断开已有记录。学号 / 班级是选填的标识（从数据中心导入时自动带上），'
            '用来在重名时认人。可以一键添加你自己；'
            '「添加全部舍友」会连你自己一起加进来；其他范围的同学请手动添加。',
            style: TextStyle(
              fontSize: 12,
              color: scheme.outline,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonal(
                key: const Key('aaAddMember'),
                onPressed: _busy == null
                    ? () => _addMember(context, ref, data)
                    : null,
                child: const Text('添加成员'),
              ),
              OutlinedButton(
                key: const Key('aaAddSelf'),
                onPressed: _busy == null ? () => _addSelf(ref, data) : null,
                child: const Text('添加我自己'),
              ),
              OutlinedButton(
                key: const Key('aaImportRoommates'),
                onPressed: _busy == null ? () => _importRoommates(ref, data) : null,
                child: _busy == 'roommates'
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('添加全部舍友'),
              ),
              // 只在「名单里还有人没有学号/班级」时出现：旧账本的成员是五轮之前手打的，
              // 身上一个标识都没有，而数据中心名单里本来就有学号/班级 —— 一键补上。
              if (data.members.any((m) => m.detail.isEmpty))
                OutlinedButton(
                  key: const Key('aaBackfillMembers'),
                  onPressed: _busy == null ? () => _backfill(ref, data) : null,
                  child: _busy == 'backfill'
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('补全学号 / 班级'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (data.members.isEmpty)
            Text(
              '还没有成员。',
              style: TextStyle(fontSize: 12.5, color: scheme.outline),
            ),
          for (final m in data.members) _memberCard(context, ref, data, m),
        ],
      ),
    );
  }

  Widget _memberCard(
    BuildContext context,
    WidgetRef ref,
    AaData data,
    AaMember m,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final paid = data.expenses.where((e) => e.payerId == m.id).length;
    final joined = data.expenses
        .where((e) => e.participantIds.contains(m.id))
        .length;
    final detail = m.detail;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        // 学号 / 班级是选填的可选第二行：没有就不占位（老数据全是空串）。
        isThreeLine: detail.isNotEmpty,
        title: Text(
          m.name,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (detail.isNotEmpty)
              Text(
                detail,
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onSurfaceVariant,
                  height: 1.3,
                ),
              ),
            Text(
              '垫付 $paid 笔 · 分摊 $joined 笔',
              style: TextStyle(fontSize: 11, color: scheme.outline),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: '编辑',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.edit_outlined, size: 18),
              onPressed: () => _editMember(context, ref, data, m),
            ),
            IconButton(
              tooltip: '删除',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: () => _delete(context, ref, data, m),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addMember(
    BuildContext context,
    WidgetRef ref,
    AaData data,
  ) async {
    final draft = await showAaMemberEditor(context);
    if (draft == null) return;
    final store = await ref.read(aaStoreProvider.future);
    await store.saveMembers([
      ...data.members,
      AaMember(
        id: const Uuid().v4(),
        name: draft.name,
        studentNo: draft.studentNo,
        className: draft.className,
      ),
    ]);
    ref.invalidate(aaDataProvider);
  }

  /// 一键把自己加进名单（用户 2026-09-19 三轮：「允许添加自己」）。
  ///
  /// 姓名 / 学号 / 班级取 [aaSelfInfoProvider]（账号显示名 + 学籍缓存，只读本地 Hive）；
  /// 姓名取不到就提示手填，**不写库、也不瞎猜一个名字** —— 账本里的名字错了比少
  /// 一个人更麻烦。已经在名单里（同名）→ 只提示、不重复加。
  ///
  /// ⚠ 这里用 `State.context`（不接 `BuildContext` 参数）：`await` 之后的
  /// `if (!mounted)` 才与要用的 context 同源，否则 analyzer 判
  /// `use_build_context_synchronously`（跨 async gap 用了被守卫之外的 context）。
  Future<void> _addSelf(WidgetRef ref, AaData data) async {
    if (_busy != null) return;
    setState(() => _busy = 'self');
    try {
      final me = await ref.read(aaSelfInfoProvider.future);
      if (!mounted) return;
      if (me.name.isEmpty) {
        _toast(aaSelfNameMissingHint);
        return;
      }
      final result = aaImportMembers(
        existing: data.members,
        people: [
          AaImportPerson(
            me.name,
            studentNo: me.studentNo,
            className: me.className,
          ),
        ],
      );
      if (result.changed) {
        final store = await ref.read(aaStoreProvider.future);
        await store.saveMembers(result.members);
        if (!mounted) return;
        ref.invalidate(aaDataProvider);
      }
      if (!mounted) return;
      _toast(aaSelfImportMessage(name: me.name, added: result.changed));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  /// 一键导入**舍友 + 我自己**（唯一允许整批导入的名单，见 [aaRoommateDimension]）。
  ///
  /// 口径演进：2026-09-19 二轮「aa功能添加成员允许直接添加所有舍友」→ 三轮收窄
  /// 「我们只要添加自己、添加室友、其他范围的同学不允许批量添加」→ 四轮
  /// 「点击添加全部舍友时应该一起把自己添加了」。所以这里**写死舍友 + 自己**、
  /// 连维度选择都不给（旧的四选一弹层 `aa_peer_import_sheet.dart` 已删）；
  /// 合并去重只有一份口径（[aaImportRoommates] → [aaImportMembers]），
  /// 取不到名单（未登录 / 数据中心会话失效）只提示、不写库。
  ///
  /// 五轮起学号 / 班级一起带进账本（[AaImportPerson.fromPeer]）：数据中心名单本来
  /// 就有这两列，导入时丢掉等于白查一次。
  Future<void> _importRoommates(WidgetRef ref, AaData data) async {
    if (_busy != null) return;
    setState(() => _busy = 'roommates');
    try {
      final peers = await ref.read(
        dzjPeersProvider(aaRoommateDimension).future,
      );
      // 自己的姓名 / 学号 / 班级是本地读，几乎瞬时 —— 放网络之后，网络失败就不必读。
      final me = await ref.read(aaSelfInfoProvider.future);
      if (!mounted) return;
      if (peers.isEmpty) {
        _toast('没有取到${aaRoommateDimension.label}名单');
        return;
      }
      final imported = aaImportRoommates(
        existing: data.members,
        selfName: me.name,
        selfStudentNo: me.studentNo,
        selfClassName: me.className,
        roommates: [for (final p in peers) AaImportPerson.fromPeer(p)],
      );
      if (imported.changed) {
        final store = await ref.read(aaStoreProvider.future);
        await store.saveMembers(imported.members);
        if (!mounted) return;
        ref.invalidate(aaDataProvider);
      }
      if (!mounted) return;
      _toast(imported.summary);
    } catch (e) {
      if (!mounted) return;
      _toast('读取名单失败：${friendlyErrorText(e)}');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  /// 给账本里**已有的**成员补上缺失的学号 / 班级（[aaBackfillMembers]）。
  ///
  /// 名单来源 = 舍友维度（学号）+ **同班同学**维度（班级）+ 我自己（学籍缓存）：
  /// 舍友名单只有「学号 / 校区」，班级在同班名单里 —— 两个维度合并才把两个字段都凑齐。
  /// 只在有人缺标识时出现（见按钮行的条件），补完自动消失。
  Future<void> _backfill(WidgetRef ref, AaData data) async {
    if (_busy != null) return;
    setState(() => _busy = 'backfill');
    try {
      final roommates = await ref.read(
        dzjPeersProvider(aaRoommateDimension).future,
      );
      // 班级来自「同班同学」维度（[aaClassDimension]，只读不落库）；
      // 这一维失败不该让整件事失败。
      var classmates = const <DzjPeer>[];
      try {
        classmates = await ref.read(
          dzjPeersProvider(aaClassDimension).future,
        );
      } catch (_) {}
      final me = await ref.read(aaSelfInfoProvider.future);
      if (!mounted) return;

      final people = <AaImportPerson>[
        for (final p in roommates) AaImportPerson.fromPeer(p),
        for (final p in classmates) AaImportPerson.fromPeer(p),
        if (me.name.isNotEmpty)
          AaImportPerson(
            me.name,
            studentNo: me.studentNo,
            className: me.className,
          ),
      ];
      if (people.isEmpty) {
        _toast('没有取到可用于补全的名单');
        return;
      }
      final result = aaBackfillMembers(existing: data.members, people: people);
      if (result.changed) {
        final store = await ref.read(aaStoreProvider.future);
        await store.saveMembers(result.members);
        if (!mounted) return;
        ref.invalidate(aaDataProvider);
      }
      if (!mounted) return;
      _toast(result.summary);
    } catch (e) {
      if (!mounted) return;
      _toast('读取名单失败：${friendlyErrorText(e)}');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _toast(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  /// 改姓名 / 学号 / 班级（学号与班级五轮起可改 —— 手打成员时先只填了名字）。
  Future<void> _editMember(
    BuildContext context,
    WidgetRef ref,
    AaData data,
    AaMember m,
  ) async {
    final draft = await showAaMemberEditor(
      context,
      initial: AaMemberDraft.of(m),
      title: '编辑成员',
    );
    if (draft == null) return;
    final store = await ref.read(aaStoreProvider.future);
    await store.saveMembers([
      for (final x in data.members)
        if (x.id == m.id)
          x.copyWith(
            name: draft.name,
            studentNo: draft.studentNo,
            className: draft.className,
          )
        else
          x,
    ]);
    ref.invalidate(aaDataProvider);
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    AaData data,
    AaMember m,
  ) async {
    final paid = [for (final e in data.expenses) if (e.payerId == m.id) e];
    if (paid.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.error_outline),
          title: const Text('无法删除'),
          content: Text(
            '「${m.name}」垫付了 ${paid.length} 笔开销，'
            '删掉这笔钱就没人认账了。请先改掉这些开销的付款人。',
          ),
          actions: [
            TextButton(
              key: const Key('aaCannotDeleteOk'),
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }

    final joined = [
      for (final e in data.expenses)
        if (e.participantIds.contains(m.id)) e,
    ];
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.delete_outline),
        title: Text('删除「${m.name}」？'),
        content: Text(
          joined.isEmpty
              ? 'TA 还没有参与任何开销。'
              : 'TA 分摊过的 ${joined.length} 笔开销会把 TA 移出，'
                    '这些钱由其余参与人重新平分。',
        ),
        actions: [
          TextButton(
            key: const Key('aaDeleteCancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('aaDeleteConfirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final store = await ref.read(aaStoreProvider.future);
    await store.saveMembers([
      for (final x in data.members)
        if (x.id != m.id) x,
    ]);
    if (joined.isNotEmpty) {
      await store.saveExpenses([
        for (final e in data.expenses)
          if (e.participantIds.contains(m.id))
            e.copyWith(
              participantIds: [
                for (final id in e.participantIds)
                  if (id != m.id) id,
              ],
            )
          else
            e,
      ]);
    }
    ref.invalidate(aaDataProvider);
  }
}
