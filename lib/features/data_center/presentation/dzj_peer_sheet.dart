/// 「校内关系」/「相关人员」名单底部弹层：点人数看名单。
///
/// 名单**按需拉取**，不进数据中心首屏：同年级可能上千人，十一个维度一起取等于给
/// 首页再挂一串请求，而用户多数时候只看舍友/同班。
///
/// 列出的是**人**（姓名 + 年级/班级/专业/宿舍/校区/学院/性别），不是数字 ——
/// 用户 2026-09-19 原话「学生个人数据中心，是可以看到同寝室人员、同班级等等，
/// 我希望你都支持查询这些信息」。
///
/// 2026-10-09（用户：「同班和同宿舍，你不用做成切换式的，而是做成**信息归并式**的」）：
/// - **同义的两对**（同班 / 舍友）在这里显示**一份合并名单**：两份名单按学号去重、
///   字段取并集（学号/班级/年级来自校内关系，学院/性别来自相关人员），
///   只在「相关人员」里收录的人会标出来 —— **没有来源切换控件**；
///   数据来自 [dzjPeerMergedProvider]（那两份是进页面时就取好的，所以这里是秒开）；
/// - 其余维度仍是一份名单（[dzjPeersProvider] 按需拉）。
/// - **本地筛选**：同年级动辄上千人（服务端一页上限 [dzjMaxPeerPageSize]），
///   给一个搜索框只筛**已取回的行**，并如实说「已筛出 X / Y 人」——**不发任何新请求**。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/errors/app_exception.dart';
import 'package:smarter_jxufe/design/app_states.dart';
import 'package:smarter_jxufe/features/data_center/data/providers/data_center_providers.dart';
import 'package:smarter_jxufe/features/data_center/domain/dzj_peer.dart';

/// 打开某个维度的名单弹层。
///
/// [dimension] = 点的那一格（同义关系传主口径即可：弹层自己按
/// [DzjPeerRelation.ofDimension] 认出来并改显示**合并名单**）；
/// [count] = 卡片方格上写的那个数（可能为 null —— 那格还没数据）。
Future<void> showDzjPeerSheet(
  BuildContext context, {
  required DzjPeerDimension dimension,
  int? count,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => FractionallySizedBox(
    heightFactor: 0.8,
    child: _DzjPeerSheet(dimension: dimension, count: count),
  ),
);

/// 维度图标（弹层标题 + 数据中心卡片方格都用；两处各写一份 switch 会分叉）。
IconData dzjPeerIcon(DzjPeerDimension dimension) {
  switch (dimension) {
    case DzjPeerDimension.grade:
      return Icons.school_outlined;
    case DzjPeerDimension.classGroup:
      return Icons.groups_outlined;
    case DzjPeerDimension.major:
      return Icons.account_tree_outlined;
    case DzjPeerDimension.dorm:
      return Icons.bed_outlined;
    case DzjPeerDimension.college:
      return Icons.cake_outlined;
    // 「同年级同学院」= 同年级再按本人学院筛（图标刻意与「同年级」「同学院同生日」
    // 都不同 —— 三枚方格可能挨着放，图一样就分不出点的是哪一枚）。
    case DzjPeerDimension.gradeCollege:
      return Icons.account_balance_outlined;
    // 「相关人员」六维（同名维度换个图标，弹层标题与卡片方格上才分得出是哪一份名单）。
    case DzjPeerDimension.relatedDorm:
      return Icons.meeting_room_outlined;
    case DzjPeerDimension.relatedCollege:
      return Icons.apartment_outlined;
    case DzjPeerDimension.relatedMajor:
      return Icons.menu_book_outlined;
    case DzjPeerDimension.relatedClass:
      return Icons.groups_2_outlined;
    case DzjPeerDimension.enrollDay:
      return Icons.event_available_outlined;
    case DzjPeerDimension.birthday:
      return Icons.celebration_outlined;
  }
}

class _DzjPeerSheet extends ConsumerStatefulWidget {
  const _DzjPeerSheet({required this.dimension, this.count});

  /// 点开时那一维（同义关系传的是主口径）。
  final DzjPeerDimension dimension;

  /// 数据中心卡片上显示的「N 人」（可能为 null —— 那格还没数据）。
  final int? count;

  @override
  ConsumerState<_DzjPeerSheet> createState() => _DzjPeerSheetState();
}

class _DzjPeerSheetState extends ConsumerState<_DzjPeerSheet> {
  /// 当前在看哪一维（**恒等于点开时那一维** —— 合并式之后这里不再有来源切换）。
  late final DzjPeerDimension _dim = widget.dimension;

  final TextEditingController _filter = TextEditingController();

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  /// 这一维属于哪个关系目（`null` = 不在任何目里，理论上不会发生）。
  DzjPeerRelation? get _relation => DzjPeerRelation.ofDimension(_dim);

  /// 是否显示**合并名单**（同义的两对：同班 / 舍友）。
  bool get _merges => _relation?.merges ?? false;

  /// 这一层的名单（统一成「行 + 来源」的形状：合并路径带来源，普通路径来源单一）。
  AsyncValue<List<DzjPeerRow>> _rows(WidgetRef ref) {
    if (_merges) {
      return ref
          .watch(dzjPeerMergedProvider(_relation!))
          .whenData((merged) => merged.rows);
    }
    return ref
        .watch(dzjPeersProvider(_dim))
        .whenData(
          (peers) => [
            for (final p in peers) DzjPeerRow(peer: p, sources: {_dim.source}),
          ],
        );
  }

  /// 本地筛选：姓名 / 学号 / 副标题（年级·班级·专业·宿舍·校区·学院·性别）任意命中。
  List<DzjPeerRow> _filtered(List<DzjPeerRow> rows) {
    final q = _filter.text.trim().toLowerCase();
    if (q.isEmpty) return rows;
    return [
      for (final r in rows)
        if ('${r.peer.name} ${r.peer.userId} ${r.peer.subtitle}'
            .toLowerCase()
            .contains(q))
          r,
    ];
  }

  void _refresh() {
    if (_merges) {
      ref.invalidate(dzjPeerMergedProvider(_relation!));
    } else {
      ref.invalidate(dzjPeersProvider(_dim));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final async = _rows(ref);
    final rows = async.valueOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 8, 2),
          child: Row(
            children: [
              Icon(dzjPeerIcon(_dim), size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  // 合并后标题用**关系目**的措辞（同班同学 / 舍友），与方格一致。
                  '${_merges ? _relation!.label : _dim.label}名单',
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: '刷新',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.refresh, size: 18),
                onPressed: _refresh,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _subtitle(async),
                style: TextStyle(fontSize: 11.5, color: scheme.outline),
              ),
              // 合并名单：说明这里的「一份」是怎么来的（信息归并，不是二选一）。
              if (_merges)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '两份名单来自不同系统，这里按学号合并去重；'
                    '只在「相关人员」里收录的人会标出来。',
                    style: TextStyle(fontSize: 10.5, color: scheme.outline),
                  ),
                ),
            ],
          ),
        ),
        // 本地筛选（有行才给）：同年级一页 500 人，翻不动就筛。
        if (rows != null && rows.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: TextField(
              key: const Key('dzjPeerFilter'),
              controller: _filter,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                hintText: '筛姓名 / 学号 / 班级 / 学院',
                hintStyle: const TextStyle(fontSize: 12.5),
                prefixIcon: const Icon(Icons.search, size: 18),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 34,
                  minHeight: 34,
                ),
                suffixIcon: _filter.text.isEmpty
                    ? null
                    : IconButton(
                        key: const Key('dzjPeerFilterClear'),
                        tooltip: '清空筛选',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () => setState(_filter.clear),
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        Expanded(
          child: async.when(
            loading: () => const AppLoadingState(
              compact: true,
              message: '正在读取名单…',
            ),
            error: (e, _) => _message(
              context,
              icon: Icons.error_outline,
              text: '名单读取失败：${friendlyErrorText(e)}',
              action: _retryButton(),
            ),
            data: (all) {
              if (all.isEmpty) {
                return _message(
                  context,
                  icon: Icons.person_off_outlined,
                  text: '没有查到「${_merges ? _relation!.label : _dim.label}」名单。',
                  action: _retryButton(),
                );
              }
              final shown = _filtered(all);
              if (shown.isEmpty) {
                // 「已列出的这批里没有」而不是「没有这个人」—— 名单是分页取的。
                return _message(
                  context,
                  icon: Icons.search_off_outlined,
                  text: '已列出的 ${all.length} 人里没有匹配'
                      '「${_filter.text.trim()}」的。',
                  action: OutlinedButton(
                    key: const Key('dzjPeerFilterReset'),
                    onPressed: () => setState(_filter.clear),
                    child: const Text('清空筛选'),
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_filter.text.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                      child: Text(
                        '已筛出 ${shown.length} / ${all.length} 人',
                        style: TextStyle(fontSize: 11.5, color: scheme.outline),
                      ),
                    ),
                  Expanded(child: _list(shown)),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _retryButton() => OutlinedButton(
    key: const Key('dzjPeerRetry'),
    onPressed: _refresh,
    child: const Text('重试'),
  );

  String _subtitle(AsyncValue<List<DzjPeerRow>> async) {
    if (_merges) {
      // 合并路径：人数 = 合并去重后的行数；同时如实交代两份各取回多少行，
      // 以及（万一某一份被分页截断）服务端计数是多少 —— 与「共 N 人 · 已列出前 M 人」
      // 同一口径：**数不一致就明说**。
      final relation = _relation!;
      final merged = ref.watch(dzjPeerMergedProvider(relation)).valueOrNull;
      final head = async.when(
        loading: () => '正在读取…',
        error: (_, _) => '读取失败',
        data: (rows) {
          if (merged == null) return '共 ${rows.length} 人';
          final serverPrimary = ref
              .watch(dzjPeerCountsProvider)
              .valueOrNull?[relation.primary.key];
          final serverTwin = ref
              .watch(dzjRelatedCountsProvider)
              .valueOrNull?[relation.twin!.key];
          // 只列**确实比取回行数多**的那一份（另一份的计数可能压根没取到 —— 别印 null）。
          final overPrimary =
              serverPrimary != null && serverPrimary > merged.primaryRows;
          final overTwin =
              serverTwin != null && serverTwin > merged.twinRows;
          final truncatedText = [
            if (overPrimary) '校内关系 $serverPrimary',
            if (overTwin) '相关人员 $serverTwin',
          ].join(' · ');
          return '共 ${merged.count} 人'
              '${truncatedText.isEmpty ? '' : '（只列已取回的部分；'
                    '服务端计数 $truncatedText）'}'
              ' · 已合并：校内关系 ${merged.primaryRows} 行 · '
              '相关人员 ${merged.twinRows} 行';
        },
      );
      return '$head · 名单来自校内关系 + 相关人员（合并去重）';
    }
    final head = async.when(
      loading: () => '正在读取…',
      error: (_, _) => '读取失败',
      data: (rows) {
        // 名单按页取（上限 = `dzjPeersProvider` 的 limit）：同年级上千人时只列前 N 个，
        // 卡片上的「N 人」是服务端 total → 两个数不一致就明说「已列出前 N 人」。
        final count = widget.count;
        if (count != null && count > rows.length) {
          return '共 $count 人 · 已列出前 ${rows.length} 人';
        }
        return '共 ${rows.length} 人';
      },
    );
    return '$head · 名单来自${_dim.source.title}';
  }

  Widget _list(List<DzjPeerRow> rows) {
    final scheme = Theme.of(context).colorScheme;
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 20),
      itemBuilder: (context, i) {
        final row = rows[i];
        final p = row.peer;
        // 信息归并：只在「相关人员」里收录的人标出来（那份名单只有姓名 / 学院）。
        final sub = [
          p.subtitle,
          if (row.relatedOnly) '仅「相关人员」名单收录',
        ].where((s) => s.isNotEmpty).join(' · ');
        return ListTile(
          key: Key('dzjPeerRow-${p.userId.isEmpty ? p.name : p.userId}'),
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          leading: CircleAvatar(
            radius: 15,
            backgroundColor: scheme.primaryContainer,
            child: Text(
              p.name.isEmpty ? '?' : p.name.substring(0, 1),
              style: TextStyle(
                fontSize: 13,
                color: scheme.onPrimaryContainer,
              ),
            ),
          ),
          title: Text(
            p.name,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
          ),
          subtitle: sub.isEmpty
              ? null
              : Text(sub, style: TextStyle(fontSize: 11, color: scheme.outline)),
          trailing: p.userId.isEmpty
              ? null
              : Text(
                  p.userId,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.outline,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
        );
      },
    );
  }

  Widget _message(
    BuildContext context, {
    required IconData icon,
    required String text,
    Widget? action,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 26, color: scheme.outline),
            const SizedBox(height: 10),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: scheme.outline),
            ),
            if (action != null) ...[
              const SizedBox(height: 12),
              action,
            ],
          ],
        ),
      ),
    );
  }
}
