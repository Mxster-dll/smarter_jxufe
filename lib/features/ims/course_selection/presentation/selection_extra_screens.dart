/// 选课模块的三个附加页：查询课表 / 申请扩容 / 被取消课程。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/ims/course_selection/data/datasources/course_selection_remote_datasource.dart';
import 'package:smarter_jxufe/features/ims/course_selection/data/providers/course_selection_providers.dart';
import 'package:smarter_jxufe/features/ims/course_selection/domain/data_table_page.dart';
import 'package:smarter_jxufe/features/score_estimate/presentation/ge_common.dart';

/// 查询课表（`tableId=5327042`）：本学期开出的课程 + 教学班。
class SelectionTimetableScreen extends ConsumerWidget {
  const SelectionTimetableScreen({super.key, required this.channel});

  final SelectionChannel channel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(selectionTimetableProvider(channel));
    return Scaffold(
      appBar: AppBar(title: const Text('查询课表')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('加载失败：$error'),
          ),
        ),
        data: (data) => _DataTableList(
          rows: data.rows,
          total: data.total,
          emptyText: '没有检索到课程',
          titleOf: (row) {
            final coded = splitCodedName(row['kc'] ?? '');
            return coded.name.isEmpty ? '课程' : coded.name;
          },
          subtitleOf: (row) => [
            if ((row['skbjdm'] ?? '').isNotEmpty) row['skbjdm']!,
            if ((row['rkjs'] ?? '').isNotEmpty) row['rkjs']!,
            if ((row['sksj'] ?? '').isNotEmpty) row['sksj']!,
            if ((row['skdd'] ?? '').isNotEmpty) row['skdd']!,
          ].join(' · '),
          trailingOf: (row) => [
            if ((row['xf'] ?? '').isNotEmpty) '${row['xf']} 学分',
            if ((row['xkrs'] ?? '').isNotEmpty) '已选 ${row['xkrs']}',
            if ((row['qdrs'] ?? '').isNotEmpty) '可选 ${row['qdrs']}',
          ].join(' · '),
          extraOf: (row) => [
            if ((row['kclb'] ?? '').isNotEmpty) ('课程类别', row['kclb']!),
            if ((row['cddw'] ?? '').isNotEmpty) ('承担单位', row['cddw']!),
            if ((row['xqmc'] ?? '').isNotEmpty) ('开课校区', row['xqmc']!),
            if ((row['qsz'] ?? '').isNotEmpty) ('周次', row['qsz']!),
            if ((row['zongxs'] ?? '').isNotEmpty) ('总学时', row['zongxs']!),
          ],
        ),
      ),
    );
  }
}

/// 申请扩容（`tableId=5929098`）。
class SelectionExpandScreen extends ConsumerWidget {
  const SelectionExpandScreen({super.key, required this.channel});

  final SelectionChannel channel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(selectionExpandProvider(channel));
    return Scaffold(
      appBar: AppBar(title: const Text('申请扩容')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('加载失败：$error'),
          ),
        ),
        data: (data) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
              child: Text(
                '这里列出可申请扩容的教学班；结果栏显示教务的审核状态与意见。'
                '提交申请请在教务系统「申请扩容」页操作。',
                style: TextStyle(fontSize: 12, color: scheme.outline),
              ),
            ),
            Expanded(
              child: _DataTableList(
                rows: data.rows,
                total: data.total,
                emptyText: '没有可申请扩容的教学班',
                titleOf: (row) {
                  final coded = splitCodedName(row['kc'] ?? '');
                  return coded.name.isEmpty ? '课程' : coded.name;
                },
                subtitleOf: (row) => [
                  if ((row['skbjdm'] ?? '').isNotEmpty) row['skbjdm']!,
                  if ((row['rkjs'] ?? '').isNotEmpty) row['rkjs']!,
                  if ((row['sksj'] ?? '').isNotEmpty) row['sksj']!,
                  if ((row['skdd'] ?? '').isNotEmpty) row['skdd']!,
                ].join(' · '),
                trailingOf: (row) => [
                  if ((row['xkrssx'] ?? '').isNotEmpty) '限选 ${row['xkrssx']}',
                  if ((row['xkrs'] ?? '').isNotEmpty) '已选 ${row['xkrs']}',
                ].join(' · '),
                extraOf: (row) => [
                  if ((row['shzt'] ?? '').isNotEmpty) ('审核状态', row['shzt']!),
                  if ((row['hfyj'] ?? '').isNotEmpty) ('审核意见', row['hfyj']!),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 被取消课程（`student/wsxk.qxbxkc.jsp`）。
class SelectionCancelledScreen extends ConsumerWidget {
  const SelectionCancelledScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(cancelledCoursesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('被取消课程')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('加载失败：$error'),
          ),
        ),
        data: (courses) => courses.isEmpty
            ? Center(
                child: Text(
                  '没有被取消的选课',
                  style: TextStyle(fontSize: 13, color: scheme.outline),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 48),
                itemCount: courses.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final course = courses[index];
                  return Card(
                    elevation: 0,
                    shape: geCardShape(context),
                    child: ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                      title: Text(
                        course.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        [
                          if (course.courseCode.isNotEmpty) course.courseCode,
                          if (course.credits != null)
                            '${geFmt(course.credits!)} 学分',
                          if (course.teacher.isNotEmpty) course.teacher,
                          if (course.classCode.isNotEmpty) course.classCode,
                        ].join(' · '),
                        style: TextStyle(fontSize: 12, color: scheme.outline),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

/// 通用数据列表渲染（教务 DataTable 的列名 → 文案由调用方提供）。
class _DataTableList extends StatelessWidget {
  const _DataTableList({
    required this.rows,
    required this.total,
    required this.emptyText,
    required this.titleOf,
    required this.subtitleOf,
    required this.trailingOf,
    this.extraOf,
  });

  final List<Map<String, String>> rows;
  final int? total;
  final String emptyText;
  final String Function(Map<String, String> row) titleOf;
  final String Function(Map<String, String> row) subtitleOf;
  final String Function(Map<String, String> row) trailingOf;
  final List<(String, String)> Function(Map<String, String> row)? extraOf;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (rows.isEmpty) {
      return Center(
        child: Text(
          emptyText,
          style: TextStyle(fontSize: 13, color: scheme.outline),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 48),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final row = rows[index];
        final extras = extraOf?.call(row) ?? const <(String, String)>[];
        return Card(
          elevation: 0,
          shape: geCardShape(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        titleOf(row),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      trailingOf(row),
                      style: TextStyle(fontSize: 11.5, color: scheme.outline),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitleOf(row),
                  style: TextStyle(fontSize: 12, color: scheme.outline),
                ),
                if (extras.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      for (final entry in extras)
                        Text(
                          '${entry.$1}：${entry.$2}',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: scheme.outline,
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
