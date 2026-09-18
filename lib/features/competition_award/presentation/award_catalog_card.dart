/// 竞赛奖励 · 「竞赛目录」卡 + 目录浏览弹层。
///
/// 目录来自资料库（`competitionCatalogProvider` 解析《学科竞赛目录》各版本），
/// 用户口径「自动资料库里获取竞赛信息」——所以这里只**读**不写：卡片列出各版本
/// 的类别条数，弹层里搜索、点一条就直接进「添加记录」弹层并预填名称与类别，
/// 省掉手打竞赛名（手打的名字和目录对不上时，Ⅰ类还会因为查不到赛项组而算不出钱）。
library;

import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/features/score_estimate/presentation/ge_common.dart';

import '../domain/competition_catalog.dart';
import 'award_common.dart';

class AwardCatalogCard extends StatelessWidget {
  const AwardCatalogCard({
    super.key,
    required this.catalog,
    required this.loading,
    required this.onBrowse,
    this.onRetry,
  });

  final CompetitionCatalog catalog;
  final bool loading;
  final VoidCallback onBrowse;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final accent = fp(context).competitionAward;
    return KeyedSubtree(
      key: const Key('awardCatalogCard'),
      child: awardCard(
        context,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            geCardTitle(
              context,
              text: '竞赛目录',
              accent: accent,
              trailing: TextButton.icon(
                key: const Key('awardCatalogBrowse'),
                onPressed: catalog.isEmpty ? null : onBrowse,
                icon: const Icon(Icons.menu_book_outlined, size: 18),
                label: const Text('浏览'),
              ),
            ),
            const SizedBox(height: 6),
            if (catalog.isEmpty)
              AwardEmptyHint(
                icon: Icons.library_books_outlined,
                text: '资料库未解析到学科竞赛目录',
                hint: loading
                    ? '正在读取资料库…'
                    : '资料库里没有「竞赛目录」文档，或文档格式变了；'
                          '不影响手动登记，但没法按名称定位赛项组。',
                actionLabel: loading ? null : '重试',
                actionKey: const Key('awardCatalogRetry'),
                onAction: onRetry,
              )
            else ...[
              for (final edition in catalog.editions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    '${edition.label} · '
                    '${[for (final k in CompetitionClass.values) '${k.label} ${edition.countOf(k)}'].join(' · ')}',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: AppColors.textBase(context),
                    ),
                  ),
                ),
              const SizedBox(height: 2),
              Text(
                '共 ${catalog.allEntries.length} 条（含各版本）· '
                '点「浏览」可按名称搜索，选中的条目会直接带进「添加记录」。',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.5,
                  color: AppColors.textMuted(context),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 打开目录浏览弹层；返回用户挑中的目录条目（null = 直接关掉）。
Future<CompetitionEntry?> showAwardCatalogSheet(
  BuildContext context, {
  required CompetitionCatalog catalog,
}) => showModalBottomSheet<CompetitionEntry>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  useSafeArea: true,
  builder: (_) => _AwardCatalogSheet(catalog: catalog),
);

class _AwardCatalogSheet extends StatefulWidget {
  const _AwardCatalogSheet({required this.catalog});

  final CompetitionCatalog catalog;

  @override
  State<_AwardCatalogSheet> createState() => _AwardCatalogSheetState();
}

class _AwardCatalogSheetState extends State<_AwardCatalogSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = fp(context).competitionAward;
    final results = widget.catalog.search(_query);
    // 跨版本搜索是按「类别 + 名称」去重的，但同名不同子项目可能撞上同一个
    // `klass-serial` Key（Key 必须唯一）→ 渲染前按 Key 再去一次重。
    final seen = <String>{};
    final groups = <CompetitionClass, List<CompetitionEntry>>{};
    for (final klass in CompetitionClass.values) {
      for (final e in results) {
        if (e.klass != klass) continue;
        if (!seen.add('${e.klass.name}-${e.serial}')) continue;
        groups.putIfAbsent(klass, () => []).add(e);
      }
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.menu_book_outlined, size: 20, color: accent),
                const SizedBox(width: 8),
                const Text(
                  '竞赛目录',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Text(
                  '${results.length} 条',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('awardCatalogSearch'),
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 18),
                labelText: '搜索竞赛名称',
                hintText: '如 数学建模 / 电子设计 / 挑战杯',
              ),
            ),
            const SizedBox(height: 10),
            if (groups.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  '没有匹配的竞赛，换个关键词试试。',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textMuted(context),
                  ),
                ),
              )
            else
              Flexible(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    for (final klass in CompetitionClass.values)
                      if (groups[klass] != null) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 6, bottom: 2),
                          child: Text(
                            '${klass.label} · ${klass.description}',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textMuted(context),
                            ),
                          ),
                        ),
                        for (final e in groups[klass]!)
                          ListTile(
                            key: Key(
                              'awardCatalogEntry-${e.klass.name}-${e.serial}',
                            ),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              e.displayName,
                              style: const TextStyle(fontSize: 13),
                            ),
                            subtitle: Text(
                              [
                                e.edition,
                                if ((e.organizer ?? '').isNotEmpty)
                                  e.organizer!,
                                if ((e.major ?? '').isNotEmpty) e.major!,
                              ].join(' · '),
                              style: const TextStyle(fontSize: 11),
                            ),
                            onTap: () => Navigator.pop(context, e),
                          ),
                      ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
