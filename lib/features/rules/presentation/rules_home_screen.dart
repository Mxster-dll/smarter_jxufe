import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/rules_repository.dart';
import '../domain/rule_doc.dart';
import 'rules_reader_screen.dart';

/// 规章制度入口页：全量目录（分类分组 + 搜索）。
class RulesHomeScreen extends ConsumerStatefulWidget {
  const RulesHomeScreen({super.key});

  @override
  ConsumerState<RulesHomeScreen> createState() => _RulesHomeScreenState();
}

class _RulesHomeScreenState extends ConsumerState<RulesHomeScreen> {
  final _qCtrl = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _qCtrl.dispose();
    super.dispose();
  }

  static IconData groupIcon(String g) => switch (g) {
        '学科竞赛' => Icons.emoji_events_outlined,
        '教学培养' => Icons.school_outlined,
        '学籍成绩' => Icons.assignment_outlined,
        '升学推免' => Icons.flight_takeoff,
        '资助奖助' => Icons.volunteer_activism,
        '科研奖励' => Icons.science_outlined,
        '纪律处分' => Icons.gavel,
        '综合素质' => Icons.fact_check_outlined,
        '学位授予' => Icons.workspace_premium_outlined,
        _ => Icons.description_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final catalogAsync = ref.watch(rulesCatalogProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '规章制度',
          style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
            child: TextField(
              controller: _qCtrl,
              onChanged: (v) => setState(() => _q = v.trim()),
              decoration: InputDecoration(
                hintText: '搜索：文件名称 / 文号 / 年份',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _q.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _qCtrl.clear();
                          setState(() => _q = '');
                        },
                      ),
                isDense: true,
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: catalogAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text(
                  '目录加载失败：$e',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
              data: (catalog) {
                final families = _q.isEmpty
                    ? catalog.families
                    : catalog.families
                        .where((f) => _familyMatches(f))
                        .toList();
                if (families.isEmpty) {
                  return const Center(child: Text('未找到匹配的规则文件'));
                }
                final grouped = _q.isEmpty
                    ? catalog.groupFamilies()
                    : _groupByClass(families, catalog.groups);
                final list = <Widget>[];
                for (final entry in grouped.entries) {
                  if (entry.value.isEmpty) continue;
                  list.add(_groupHeader(context, entry.key, entry.value.length));
                  for (final f in entry.value) {
                    list.add(_familyTile(f));
                  }
                  list.add(const SizedBox(height: 10));
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
                  children: list,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  bool _familyMatches(RuleFamily f) {
    if (f.name.contains(_q)) return true;
    for (final m in f.members) {
      final d = m.doc;
      if (d.title.contains(_q) ||
          d.file.contains(_q) ||
          m.label.contains(_q) ||
          (d.wenhao?.contains(_q) ?? false) ||
          d.year.contains(_q)) {
        return true;
      }
    }
    return false;
  }

  /// 搜索命中时按家族 group 现场分组（保持 catalog groups 顺序）。
  Map<String, List<RuleFamily>> _groupByClass(
    List<RuleFamily> families,
    List<String> order,
  ) {
    final map = <String, List<RuleFamily>>{};
    for (final f in families) {
      map.putIfAbsent(f.group, () => []).add(f);
    }
    final out = <String, List<RuleFamily>>{};
    for (final g in order) {
      if (map.containsKey(g)) out[g] = map.remove(g)!;
    }
    out.addAll(map);
    return out;
  }

  Widget _groupHeader(BuildContext context, String name, int count) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 14, 2, 8),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 13,
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            name,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          Text(
            '$count 份',
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// 同名家族瓦片：一个《规则》只占一个入口；副标题列出各版本标签。
  Widget _familyTile(RuleFamily family) {
    final scheme = Theme.of(context).colorScheme;
    final doc = family.defaultDoc;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Theme.of(context).cardTheme.color,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9),
          side: BorderSide(color: scheme.outline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => RulesReaderScreen(doc: doc)),
          ),
          hoverColor: scheme.primary.withValues(alpha: 0.04),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    groupIcon(family.group),
                    color: scheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        family.name,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        family.members.map((m) => m.label).join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.45,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
