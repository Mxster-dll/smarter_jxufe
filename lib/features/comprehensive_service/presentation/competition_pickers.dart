/// 学科竞赛的两个选择器（比赛目录 / 学生检索）：整页对话框 + 服务端翻页。
///
/// 官网用 layer iframe 弹层，这里用整页 `MaterialPageRoute`（手机上更好用），
/// 选中后 `pop` 回值。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/comprehensive_service/data/models/competition.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/providers/competition_providers.dart';
import 'package:smarter_jxufe/features/comprehensive_service/presentation/competition_widgets.dart';

/// 打开比赛目录选择器；返回 null = 用户取消。
Future<CompetitionGame?> showCompetitionGamePicker(BuildContext context) {
  return Navigator.of(context).push<CompetitionGame>(
    MaterialPageRoute(builder: (_) => const _CompetitionGamePickerScreen()),
  );
}

/// 打开学生选择器；返回选中的成员（已选过的会排除）。
Future<List<CompetitionStudent>> showCompetitionStudentPicker(
  BuildContext context, {
  List<String> excludeStudentIds = const [],
}) async {
  final picked = await Navigator.of(context).push<List<CompetitionStudent>>(
    MaterialPageRoute(
      builder: (_) =>
          _CompetitionStudentPickerScreen(excludeStudentIds: excludeStudentIds),
    ),
  );
  return picked ?? const [];
}

// ---- 比赛目录 ----

class _CompetitionGamePickerScreen extends ConsumerStatefulWidget {
  const _CompetitionGamePickerScreen();

  @override
  ConsumerState<_CompetitionGamePickerScreen> createState() =>
      _CompetitionGamePickerScreenState();
}

class _CompetitionGamePickerScreenState
    extends ConsumerState<_CompetitionGamePickerScreen> {
  final _nameCtrl = TextEditingController();
  final _yearCtrl = TextEditingController();
  CompetitionGameQuery _query = const CompetitionGameQuery();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _yearCtrl.dispose();
    super.dispose();
  }

  void _search() => setState(() {
    _query = CompetitionGameQuery(
      year: _yearCtrl.text.trim(),
      name: _nameCtrl.text.trim(),
    );
  });

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(competitionGameListProvider(_query));
    return Scaffold(
      appBar: AppBar(title: const Text('选择比赛'), centerTitle: true),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                SizedBox(
                  width: 96,
                  child: TextField(
                    controller: _yearCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '年份',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: '比赛名称（如：数学建模）',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: '搜索',
                  onPressed: _search,
                  icon: const Icon(Icons.search),
                ),
              ],
            ),
          ),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: CompetitionErrorCard(
                  error: error,
                  onRetry: () =>
                      ref.invalidate(competitionGameListProvider(_query)),
                ),
              ),
              data: (page) {
                if (page.items.isEmpty) {
                  return const CompetitionEmptyHint(
                    icon: Icons.search_off,
                    title: '没有找到匹配的比赛',
                    subtitle: '试试更短的关键词（如「建模」「程序设计」），或换年份。',
                  );
                }
                return Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        itemCount: page.items.length,
                        itemBuilder: (context, index) {
                          final game = page.items[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              title: Text(
                                game.name,
                                style: const TextStyle(fontSize: 13.5),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  [
                                    if (game.year.isNotEmpty) game.year,
                                    if (game.level.isNotEmpty) game.level,
                                    if (game.college.isNotEmpty)
                                      '对接：${game.college}',
                                  ].join(' · '),
                                  style: const TextStyle(fontSize: 11.5),
                                ),
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => Navigator.of(context).pop(game),
                            ),
                          );
                        },
                      ),
                    ),
                    CompetitionPagerBar(
                      page: page.page,
                      totalPages: page.totalPages,
                      busy: async.isLoading,
                      onPage: (next) => setState(() {
                        _query = _query.copyWith(page: next);
                      }),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---- 学生检索 ----

class _CompetitionStudentPickerScreen extends ConsumerStatefulWidget {
  const _CompetitionStudentPickerScreen({required this.excludeStudentIds});

  final List<String> excludeStudentIds;

  @override
  ConsumerState<_CompetitionStudentPickerScreen> createState() =>
      _CompetitionStudentPickerScreenState();
}

class _CompetitionStudentPickerScreenState
    extends ConsumerState<_CompetitionStudentPickerScreen> {
  final _nameCtrl = TextEditingController();
  final _idCtrl = TextEditingController();
  CompetitionStudentQuery _query = const CompetitionStudentQuery();
  final _selected = <String, CompetitionStudent>{};

  @override
  void dispose() {
    _nameCtrl.dispose();
    _idCtrl.dispose();
    super.dispose();
  }

  void _search() => setState(() {
    _query = CompetitionStudentQuery(
      name: _nameCtrl.text.trim(),
      studentId: _idCtrl.text.trim(),
    );
  });

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(competitionStudentListProvider(_query));
    return Scaffold(
      appBar: AppBar(
        title: const Text('添加团队成员'),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _selected.isEmpty
                ? null
                : () => Navigator.of(context).pop(_selected.values.toList()),
            child: Text('确定（${_selected.length}）'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: '姓名',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _idCtrl,
                    decoration: const InputDecoration(
                      labelText: '学号',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: '搜索',
                  onPressed: _search,
                  icon: const Icon(Icons.search),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              '按排名顺序添加（申请人自己也要选进来）；团队申请至少 2 人。',
              style: TextStyle(
                fontSize: 11.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: CompetitionErrorCard(
                  error: error,
                  onRetry: () =>
                      ref.invalidate(competitionStudentListProvider(_query)),
                ),
              ),
              data: (page) {
                final items = [
                  for (final student in page.items)
                    if (!widget.excludeStudentIds.contains(student.studentId))
                      student,
                ];
                if (items.isEmpty) {
                  return const CompetitionEmptyHint(
                    icon: Icons.person_search,
                    title: '没有找到匹配的同学',
                    subtitle: '用姓名或学号搜索（同专业的同学都搜得到）。',
                  );
                }
                return Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final student = items[index];
                          final checked = _selected.containsKey(
                            student.studentId,
                          );
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: CheckboxListTile(
                              dense: true,
                              value: checked,
                              title: Text(
                                '${student.name} · ${student.studentId}',
                                style: const TextStyle(fontSize: 13.5),
                              ),
                              subtitle: Text(
                                '${student.college} · ${student.className}',
                                style: const TextStyle(fontSize: 11.5),
                              ),
                              onChanged: (value) => setState(() {
                                if (value ?? false) {
                                  _selected[student.studentId] = student;
                                } else {
                                  _selected.remove(student.studentId);
                                }
                              }),
                            ),
                          );
                        },
                      ),
                    ),
                    CompetitionPagerBar(
                      page: page.page,
                      totalPages: page.totalPages,
                      busy: async.isLoading,
                      onPage: (next) => setState(() {
                        _query = _query.copyWith(page: next);
                      }),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
