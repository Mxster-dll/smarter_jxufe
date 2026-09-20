/// 学习通 · 全部作业（二级页）。
///
/// 主页只铺前几条，其余在这里看全：顶部一排筛选（全部 / 待做 / 待批阅 / 已完成），
/// 排序口径 = 待做按截止升序在前 → 待批阅 → 已完成按截止倒序（`ChaoxingSnapshot`
/// 已提供派生列表，页面不再自己排）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/features/chaoxing/data/providers/chaoxing_providers.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_snapshot.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_work.dart';
import 'package:smarter_jxufe/features/chaoxing/presentation/chaoxing_common.dart';

/// 作业筛选档。
enum ChaoxingWorkFilter {
  all('全部'),
  todo('待做'),
  pendingReview('待批阅'),
  done('已完成');

  const ChaoxingWorkFilter(this.label);

  final String label;
}

/// 全部作业页。
class ChaoxingWorksScreen extends ConsumerStatefulWidget {
  const ChaoxingWorksScreen({super.key, this.initialFilter = ChaoxingWorkFilter.all});

  /// 从主页「待做」入口进来时直接落在待做档。
  final ChaoxingWorkFilter initialFilter;

  @override
  ConsumerState<ChaoxingWorksScreen> createState() => _ChaoxingWorksScreenState();
}

class _ChaoxingWorksScreenState extends ConsumerState<ChaoxingWorksScreen> {
  late ChaoxingWorkFilter _filter = widget.initialFilter;

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(chaoxingControllerProvider).valueOrNull ??
        ChaoxingSnapshot.empty;
    final now = DateTime.now();
    final works = _filtered(snapshot);

    return Scaffold(
      appBar: AppBar(title: const Text('全部作业'), centerTitle: true),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Wrap(
              spacing: 8,
              children: [
                for (final f in ChaoxingWorkFilter.values)
                  ChoiceChip(
                    label: Text('${f.label}（${_filtered(snapshot, f).length}）'),
                    selected: _filter == f,
                    onSelected: (_) => setState(() => _filter = f),
                  ),
              ],
            ),
          ),
          Expanded(
            child: works.isEmpty
                ? const Center(
                    child: ChaoxingEmptyHint(text: '这一档里没有作业', icon: Icons.assignment_outlined),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 32),
                    itemCount: works.length,
                    separatorBuilder: (_, _) => Divider(
                      height: 1,
                      color: AppColors.stroke(context),
                    ),
                    itemBuilder: (context, i) {
                      final work = works[i];
                      return ChaoxingWorkRow(
                        work: work,
                        now: now,
                        // 同一门课的相邻条目只显示一次课程名，避免整页重复。
                        showCourse: i == 0 || works[i - 1].courseId != work.courseId,
                        onTap: () =>
                            showChaoxingWorkDetail(context, work, now: now),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  List<ChaoxingWork> _filtered(
    ChaoxingSnapshot snapshot, [
    ChaoxingWorkFilter? filter,
  ]) {
    final f = filter ?? _filter;
    final open = snapshot.openWorks;
    final finished = snapshot.finishedWorks;
    final pending = [
      for (final w in snapshot.works)
        if (w.status == ChaoxingWorkStatus.pendingReview) w,
    ];
    return switch (f) {
      ChaoxingWorkFilter.all => [...open, ...pending, ...finished],
      ChaoxingWorkFilter.todo => open,
      ChaoxingWorkFilter.pendingReview => pending,
      ChaoxingWorkFilter.done => finished,
    };
  }
}
