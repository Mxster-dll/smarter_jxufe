import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:smarter_jxufe/features/campus_address/domain/campus_address.dart';

/// 学校地址：展示四个校区（蛟桥园 / 青山园 / 麦庐园 / 枫林园）的
/// 地址与邮编，点击卡片右上角可一键复制整条校区信息。
class CampusAddressScreen extends StatelessWidget {
  const CampusAddressScreen({super.key});

  void _copy(BuildContext context, CampusInfo c) {
    Clipboard.setData(ClipboardData(text: '${c.name} ${c.address} 邮编：${c.postcode}'));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('已复制${c.name}地址'),
        duration: const Duration(seconds: 1),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('学校地址'), centerTitle: true),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        itemCount: campuses.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final c = campuses[index];
          return Material(
            color: Theme.of(context).cardTheme.color,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: scheme.outline),
            ),
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
                        color: scheme.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.place_outlined,
                          color: scheme.primary, size: 22),
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
                                    horizontal: 8, vertical: 2),
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
                    Icon(Icons.copy_outlined,
                        size: 18, color: scheme.onSurfaceVariant),
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
