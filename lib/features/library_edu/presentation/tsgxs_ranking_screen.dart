import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/library_edu/data/providers/tsgxs_providers.dart';
import 'package:smarter_jxufe/features/library_edu/domain/tsgxs_models.dart';

/// 排行榜:全校闯关成绩排名(未通过不上榜)。
class TsgxsRankingScreen extends ConsumerWidget {
  const TsgxsRankingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(tsgxsRankingProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('排行榜'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: () => ref.invalidate(tsgxsRankingProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              '$e',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: scheme.error),
            ),
          ),
        ),
        data: (ranking) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            _header(context, ranking),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.6),
                ),
              ),
              child: Column(
                children: [
                  _row(context, '名次', '姓名', '分数', '用时', header: true),
                  for (final r in ranking.rows.take(60)) ...[
                    Divider(
                      height: 1,
                      color: scheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                    _row(context, '${r.rank}', r.name, r.score, r.elapsed),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (ranking.note.isNotEmpty)
              Text(
                ranking.note,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.6,
                  color: scheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, TsgxsRanking ranking) {
    final scheme = Theme.of(context).colorScheme;
    // 页面首表为「我的名次」,此处以榜单首位名次作为榜首展示。
    final top = ranking.topRank;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          Icon(Icons.emoji_events_outlined, size: 20, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              top == null
                  ? '暂无排行数据'
                  : '共 ${ranking.rows.length} 条上榜记录 · 榜首名次 $top',
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    String a,
    String b,
    String c,
    String d, {
    bool header = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    TextStyle style(int flex) => TextStyle(
      fontSize: header ? 12 : 13,
      fontWeight: header ? FontWeight.w600 : FontWeight.w500,
      color: header
          ? scheme.onSurfaceVariant
          : (flex == 4 ? scheme.primary : null),
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(a, style: style(2))),
          Expanded(
            flex: 4,
            child: Text(
              b,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style(4),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(c, textAlign: TextAlign.center, style: style(3)),
          ),
          Expanded(
            flex: 3,
            child: Text(d, textAlign: TextAlign.right, style: style(3)),
          ),
        ],
      ),
    );
  }
}
