/// 学习通 · 全部课程（二级页）。
///
/// 每门课一行，点开看这门课的作业（已按截止时间排好）。顶部可以按学期前缀筛
/// （`261学期` / `252学期` / 无前缀课程）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/features/chaoxing/data/providers/chaoxing_providers.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_course.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_snapshot.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_text.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_work.dart';
import 'package:smarter_jxufe/features/chaoxing/presentation/chaoxing_common.dart';

/// 全部课程页。
class ChaoxingCoursesScreen extends ConsumerStatefulWidget {
  const ChaoxingCoursesScreen({super.key});

  @override
  ConsumerState<ChaoxingCoursesScreen> createState() => _ChaoxingCoursesScreenState();
}

class _ChaoxingCoursesScreenState extends ConsumerState<ChaoxingCoursesScreen> {
  /// null = 全部学期。
  String? _term;

  @override
  Widget build(BuildContext context) {
    final snapshot =
        ref.watch(chaoxingControllerProvider).valueOrNull ?? ChaoxingSnapshot.empty;
    final now = DateTime.now();
    final terms = <String>{
      for (final c in snapshot.courses)
        if (c.termLabel.isNotEmpty) c.termLabel,
    }.toList()..sort((a, b) => b.compareTo(a));
    final courses = [
      for (final c in snapshot.courses)
        if (_term == null || c.termLabel == _term) c,
    ];
    final byCourse = chaoxingWorksByCourse(snapshot);

    return Scaffold(
      appBar: AppBar(title: const Text('全部课程'), centerTitle: true),
      body: Column(
        children: [
          if (terms.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: Text('全部（${snapshot.courses.length}）'),
                    selected: _term == null,
                    onSelected: (_) => setState(() => _term = null),
                  ),
                  for (final t in terms)
                    ChoiceChip(
                      label: Text(t),
                      selected: _term == t,
                      onSelected: (_) => setState(() => _term = t),
                    ),
                ],
              ),
            ),
          Expanded(
            child: courses.isEmpty
                ? const Center(
                    child: ChaoxingEmptyHint(
                      text: '没有读到课程',
                      icon: Icons.school_outlined,
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 32),
                    children: [
                      for (final course in courses)
                        _courseTile(
                          course,
                          byCourse[course.key] ?? const [],
                          now,
                          chaoxingCourseScanNote(snapshot, course.key),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _courseTile(
    ChaoxingCourse course,
    List<ChaoxingWork> works,
    DateTime now,
    String note,
  ) {
    final todo = works.where((w) => w.status.isOpen).length;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(left: 8, bottom: 8),
        title: Text(
          course.displayName,
          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              works.isEmpty
                  ? '无作业记录'
                  : '作业 ${works.length} 条${todo > 0 ? ' · 待做 $todo 条' : ''}',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted(context)),
            ),
            // 「本轮未扫到 / 扫描失败」照实说 —— 不然用户会以为这门课真没作业。
            if (note.isNotEmpty)
              Text(
                note,
                style: TextStyle(fontSize: 11.5, color: AppColors.textMuted(context)),
              ),
          ],
        ),
        children: [
          if (works.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                note.isEmpty ? '这门课没有作业记录' : note,
                style: TextStyle(fontSize: 12.5, color: AppColors.textMuted(context)),
              ),
            )
          else
            for (final work in works)
              ChaoxingWorkRow(
                work: work,
                now: now,
                showCourse: false,
                onTap: () => showChaoxingWorkDetail(
                  context,
                  work,
                  now: now,
                  courseName: course.name,
                ),
              ),
        ],
      ),
    );
  }
}
