/// 「校内关系」/「相关人员」名单底部弹层：点人数看名单。
///
/// 名单**按需拉取**（[dzjPeersProvider]），不进数据中心首屏：同年级可能上千人，
/// 十一个维度一起取等于给首页再挂一串请求，而用户多数时候只看舍友/同班。
///
/// 列出的是**人**（姓名 + 年级/班级/专业/宿舍/校区/学院/性别），不是数字 ——
/// 用户 2026-09-19 原话「学生个人数据中心，是可以看到同寝室人员、同班级等等，
/// 我希望你都支持查询这些信息」；两个页面（`DzjPeerSource`）共用这一个弹层。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/errors/app_exception.dart';
import 'package:smarter_jxufe/features/data_center/data/providers/data_center_providers.dart';
import 'package:smarter_jxufe/features/data_center/domain/dzj_peer.dart';

/// 打开某个维度的名单弹层。
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

/// 维度图标（弹层标题 + 数据中心卡片胶囊都用；两处各写一份 switch 会分叉）。
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
    // 都不同 —— 三枚胶囊可能挨着放，图一样就分不出点的是哪一枚）。
    case DzjPeerDimension.gradeCollege:
      return Icons.account_balance_outlined;
    // 「相关人员」六维（同名维度换个图标，弹层标题与卡片胶囊上才分得出是哪一份名单）。
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

class _DzjPeerSheet extends ConsumerWidget {
  const _DzjPeerSheet({required this.dimension, this.count});

  final DzjPeerDimension dimension;

  /// 数据中心卡片上显示的「N 人」（可能为 null —— 那格没数据）。
  final int? count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(dzjPeersProvider(dimension));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 8, 2),
          child: Row(
            children: [
              Icon(dzjPeerIcon(dimension), size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${dimension.label}名单',
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
                onPressed: () => ref.invalidate(dzjPeersProvider(dimension)),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(
            _subtitle(async),
            style: TextStyle(fontSize: 11.5, color: scheme.outline),
          ),
        ),
        Expanded(
          child: async.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (e, _) => _message(
              context,
              ref,
              icon: Icons.error_outline,
              text: '名单读取失败：${friendlyErrorText(e)}',
            ),
            data: (peers) => peers.isEmpty
                ? _message(
                    context,
                    ref,
                    icon: Icons.person_off_outlined,
                    text: '没有查到「${dimension.label}」名单。',
                  )
                : _list(peers),
          ),
        ),
      ],
    );
  }

  String _subtitle(AsyncValue<List<DzjPeer>> async) {
    final head = async.when(
      loading: () => '正在读取…',
      error: (_, _) => '读取失败',
      data: (peers) {
        // 名单按页取（上限 = `dzjPeersProvider` 的 limit）：同年级上千人时只列前 N 个，
        // 卡片上的「N 人」是服务端 total → 两个数不一致就明说「已列出前 N 人」。
        if (count != null && count! > peers.length) {
          return '共 $count 人 · 已列出前 ${peers.length} 人';
        }
        return '共 ${peers.length} 人';
      },
    );
    return '$head · 名单来自${dimension.source.title}';
  }

  Widget _list(List<DzjPeer> peers) {
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: peers.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 20),
      itemBuilder: (context, i) {
        final p = peers[i];
        final scheme = Theme.of(context).colorScheme;
        final sub = p.subtitle;
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
    BuildContext context,
    WidgetRef ref, {
    required IconData icon,
    required String text,
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
            const SizedBox(height: 12),
            OutlinedButton(
              key: const Key('dzjPeerRetry'),
              onPressed: () => ref.invalidate(dzjPeersProvider(dimension)),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
