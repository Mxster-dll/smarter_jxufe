import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/design/app_card.dart';
import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/features/campus_address/data/my_campus_prefs.dart';
import 'package:smarter_jxufe/features/campus_address/domain/campus_address.dart';
import 'package:smarter_jxufe/features/campus_address/domain/my_campus.dart';
import 'package:smarter_jxufe/features/campus_address/presentation/my_campus_widgets.dart';

/// 学校地址：展示四个校区（蛟桥园 / 青山园 / 麦庐园 / 枫林园）的
/// 地址与邮编，点击卡片右上角可一键复制整条校区信息。
///
/// 「我的校区」（[myCampusStoreProvider]）一旦设置，该校区条目置顶并带
/// 「我的校区」徽标；未设置时保持原有四个校区的稳定顺序。
class CampusAddressScreen extends ConsumerWidget {
  const CampusAddressScreen({super.key});

  void _copy(BuildContext context, CampusInfo c) {
    Clipboard.setData(
      ClipboardData(text: '${c.name} ${c.address} 邮编：${c.postcode}'),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('已复制${c.name}地址'),
          duration: const Duration(seconds: 1),
        ),
      );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final mine = ref.watch(myCampusStoreProvider).campus;
    bool isMine(CampusInfo c) => mine != null && mine.matchesAddress(c);
    final ordered = pinMineFirst(campuses, isMine);
    final pinnedNames = [
      for (final c in ordered)
        if (isMine(c)) c.name,
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('学校地址'), centerTitle: true),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        // 第 0 项是「我的校区」状态提示行，其后是校区卡片。
        itemCount: ordered.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index == 0) {
            return myCampusHint(context, mine: mine, pinnedNames: pinnedNames);
          }
          final c = ordered[index - 1];
          final pinned = isMine(c);
          final accent = pinned ? FeaturePalette.cardAccent : scheme.primary;
          return Material(
            color: Theme.of(context).cardTheme.color,
            shape: pinned
                ? appCardShape(
                    context,
                  ).copyWith(side: BorderSide(color: FeaturePalette.cardAccent))
                : appCardShape(context),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _copy(context, c),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.place_outlined,
                        color: accent,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  c.name,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: scheme.primary.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  '邮编 ${c.postcode}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: scheme.primary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (pinned) ...[
                            const SizedBox(height: 6),
                            // 徽标独占一行：与长校区名 + 邮编同排会在窄屏溢出。
                            Align(
                              alignment: Alignment.centerLeft,
                              child: myCampusBadge(context),
                            ),
                          ],
                          const SizedBox(height: 6),
                          Text(
                            c.address,
                            style: TextStyle(
                              fontSize: 13,
                              height: 18 / 13,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.copy_outlined,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
