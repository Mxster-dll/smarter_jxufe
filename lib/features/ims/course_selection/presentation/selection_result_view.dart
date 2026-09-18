/// 「选课结果」Tab —— 统计 + 已选课程 + 退选（含入学以来正选结果）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/features/ims/course_selection/data/datasources/course_selection_remote_datasource.dart';
import 'package:smarter_jxufe/features/ims/course_selection/data/providers/course_selection_providers.dart';
import 'package:smarter_jxufe/features/ims/course_selection/domain/selection_models.dart';
import 'package:smarter_jxufe/features/ims/course_selection/domain/selection_write_check.dart';
import 'package:smarter_jxufe/features/score_estimate/presentation/ge_common.dart';

/// 每行「更多」菜单里的动作（目前只有退选；破坏性动作一律走菜单 + 弹窗核对）。
enum _CourseAction { drop }

class SelectionResultView extends ConsumerStatefulWidget {
  const SelectionResultView({super.key});

  @override
  ConsumerState<SelectionResultView> createState() =>
      _SelectionResultViewState();
}

class _SelectionResultViewState extends ConsumerState<SelectionResultView> {
  bool _history = false;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final async = _history
        ? ref.watch(allSelectionResultProvider)
        : ref.watch(selectionResultProvider);
    final sessionAsync = ref.watch(
      selectionSessionProvider(SelectionChannel.plan),
    );
    final session = sessionAsync.valueOrNull ?? SelectionSession.unknown;

    return RefreshIndicator(
      onRefresh: () async {
        if (_history) {
          ref.invalidate(allSelectionResultProvider);
          await ref.read(allSelectionResultProvider.future);
        } else {
          ref.invalidate(selectionResultProvider);
          ref.invalidate(selectionQuotaProvider);
          await ref.read(selectionResultProvider.future);
        }
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 72),
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('本学期')),
              ButtonSegment(value: true, label: Text('入学以来')),
            ],
            selected: {_history},
            showSelectedIcon: false,
            onSelectionChanged: (values) =>
                setState(() => _history = values.first),
          ),
          const SizedBox(height: 12),
          async.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => _errorCard(context, '$error'),
            data: (result) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _summaryCard(context, result, session),
                const SizedBox(height: 12),
                if (result.courses.isEmpty)
                  Card(
                    elevation: 0,
                    shape: geCardShape(context),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      child: Center(
                        child: Text(
                          '该学期没有已选课程',
                          style: TextStyle(fontSize: 13, color: scheme.outline),
                        ),
                      ),
                    ),
                  )
                else
                  _courseCard(context, result, session),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(
    BuildContext context,
    SelectionResult result,
    SelectionSession session,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final remaining = result.remainingCredits;
    return Card(
      elevation: 0,
      shape: geCardShape(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            geCardTitle(
              context,
              text: '选课统计',
              accent: fp(context).cardAccent,
              trailing: result.fromCache
                  ? Text(
                      '缓存',
                      style: TextStyle(fontSize: 11.5, color: scheme.outline),
                    )
                  : null,
            ),
            const SizedBox(height: 10),
            if (result.termLabel.isNotEmpty)
              Text(
                result.termLabel,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 18,
              runSpacing: 6,
              children: [
                if (result.totalCredits != null)
                  _metric(context, '已选学分', geFmt(result.totalCredits!)),
                if (result.totalCount != null)
                  _metric(context, '已选门数', '${result.totalCount}'),
                if (result.creditLimit != null)
                  _metric(context, '学分上限', geFmt(result.creditLimit!)),
                if (remaining != null)
                  _metric(context, '剩余学分', geFmt(remaining)),
              ],
            ),
            if (result.categoryCredits.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final entry in result.categoryCredits.entries)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: fp(context).cardAccent.withValues(
                          alpha: 0.10,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${entry.key} ${geFmt(entry.value)} 学分',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: fp(context).cardAccent,
                        ),
                      ),
                    ),
                ],
              ),
            ],
            if (!session.open)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  '当前不在选课时间，退选不可用',
                  style: TextStyle(fontSize: 12, color: scheme.outline),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _metric(BuildContext context, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 11.5, color: scheme.outline)),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _courseCard(
    BuildContext context,
    SelectionResult result,
    SelectionSession session,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: geCardShape(context),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: geCardTitle(
              context,
              text: '已选课程（${result.courses.length}）',
              accent: fp(context).cardAccent,
            ),
          ),
          for (final course in result.courses)
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
              title: Text(
                course.name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [
                        if (course.courseCode.isNotEmpty) course.courseCode,
                        if (course.credits != null)
                          '${geFmt(course.credits!)} 学分',
                        if (course.teacher.isNotEmpty) course.teacher,
                        if (course.status.isNotEmpty) course.status,
                      ].join(' · '),
                      style: TextStyle(fontSize: 12, color: scheme.outline),
                    ),
                    if (course.timePlace.isNotEmpty)
                      Text(
                        course.timePlace,
                        style: TextStyle(fontSize: 12, color: scheme.outline),
                      ),
                    if (course.classCode.isNotEmpty)
                      Text(
                        '上课班号 ${course.classCode}',
                        style: TextStyle(fontSize: 11.5, color: scheme.outline),
                      ),
                  ],
                ),
              ),
              // ⚠ 行内**不再直接放「退选」按钮**（2026-09-15 事故）：相邻行的小按钮上下
              // 紧贴、长相一致，手指一偏就退掉另一门课。破坏性动作先进「更多」菜单
              //（菜单本身是个模态弹层，误触无害），退选还要再点一次 + 弹窗里勾选核对。
              trailing: (!session.open || course.itemCode.isEmpty || _busy)
                  ? null
                  : PopupMenuButton<_CourseAction>(
                      tooltip: '更多',
                      icon: Icon(
                        Icons.more_vert,
                        size: 20,
                        color: scheme.outline,
                      ),
                      onSelected: (action) {
                        if (action == _CourseAction.drop) {
                          unawaited(_cancel(course, result));
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: _CourseAction.drop,
                          child: Row(
                            children: [
                              Icon(
                                Icons.remove_circle_outline,
                                size: 18,
                                color: scheme.error,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '退选本门课',
                                style: TextStyle(color: scheme.error),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
        ],
      ),
    );
  }

  Future<void> _cancel(SelectedCourse course, SelectionResult result) async {
    // 硬闸门①（本地）：退选码必须在本页**唯一**指向这一行。重码说明页面结构变了 /
    // 解析错位，这时候提交上去就可能命中别门课（2026-09-15 事故的形态），**宁可不让退**。
    final sameCode = result.courses
        .where((c) => c.itemCode == course.itemCode)
        .length;
    if (course.itemCode.isEmpty || sameCode != 1) {
      _toast(
        '这一行的退选码无法唯一识别'
        '（${course.itemCode.isEmpty ? '页面结构变了' : '有 $sameCode 行同码'}），'
        '已阻止退选，请到教务操作',
      );
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    // 硬闸门②（服务端侧）：**先重读一遍选课结果**再让用户确认 ——
    // 教务退选端点是 fire-and-forget（空 items / 不存在的码都回「操作成功!」），
    // 在**过期列表**上提交一个刚被退掉的码，界面既不知道会不会命中别的课、也无从回滚。
    final actions = ref.read(courseSelectionActionsProvider);
    final SelectionCancelPreparation prep;
    try {
      prep = await actions.prepareCancel(
        itemCode: course.itemCode,
        courseName: course.name,
      );
    } catch (error) {
      if (mounted) setState(() => _busy = false);
      _toast('退选前核对失败：$error');
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (!prep.ok) {
      // 列表已过期 → 界面库存已被 invalidate，这里如实告知并让用户看最新数据。
      _toast(prep.message);
      return;
    }
    // 确认弹窗展示**刚刚重读**的那一行，而不是界面手上那份可能过期的数据。
    final target = prep.course ?? course;
    final scheme = Theme.of(context).colorScheme;
    var acknowledged = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          icon: Icon(Icons.remove_circle_outline, color: scheme.error),
          title: const Text('退选这一门课？'),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${target.name}（${target.courseCode}）',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              if (target.teacher.isNotEmpty) Text('任课教师：${target.teacher}'),
              if (target.credits != null) Text('学分：${geFmt(target.credits!)}'),
              if (target.timePlace.isNotEmpty)
                Text('上课时间地点：${target.timePlace}'),
              Text('退选码（提交给教务）：${target.itemCode}'),
              const SizedBox(height: 6),
              const Text('以上信息取自刚刚重新读取的选课结果。'),
              const Text('退选后需要重新选课才能恢复。'),
              const Divider(height: 20),
              // ⚠ 强制核对：不勾选就不能确认 —— 事故当天正是「顺手点确认」退错了课。
              InkWell(
                onTap: () => setDialogState(() => acknowledged = !acknowledged),
                child: Row(
                  children: [
                    Checkbox(
                      value: acknowledged,
                      onChanged: (value) =>
                          setDialogState(() => acknowledged = value ?? false),
                    ),
                    Expanded(
                      child: Text(
                        '我已核对：要退选的是《${target.name}》',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.errorFill(context),
                foregroundColor: AppColors.onErrorFill(context),
              ),
              onPressed: acknowledged
                  ? () => Navigator.of(dialogContext).pop(true)
                  : null,
              child: const Text('确认退选'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      // 提交前会再重读核对一次；提交后**无论应答如何**都重读对账并刷新界面。
      final outcome = await actions.cancelChecked(
        itemCode: target.itemCode,
        courseName: target.name,
      );
      if (!mounted) return;
      await _reportCancelOutcome(outcome);
    } catch (error) {
      if (!mounted) return;
      _toast('退选失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 退选结果怎么报：**退错了 → 红字弹窗**，其余如实播报（含「已阻止」「结果未知」）。
  ///
  /// 2026-09-15 事故的核心教训：写入之后必须对账，**不能再无条件说「退选成功」**；
  /// 同日的第二个教训：教务应答（哪怕是「操作成功!」）**不能**当成写入已生效 ——
  /// 该端点对空 `items` 与不存在的码都回同一句话。
  Future<void> _reportCancelOutcome(SelectionCancelOutcome outcome) async {
    if (outcome.alarming) {
      final scheme = Theme.of(context).colorScheme;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: Icon(Icons.error_outline, color: scheme.error),
          title: const Text('退选结果与请求不一致'),
          scrollable: true,
          content: Text(outcome.message),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }
    _toast(outcome.message);
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _errorCard(BuildContext context, String message) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: geCardShape(context),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '加载失败',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: scheme.error,
              ),
            ),
            const SizedBox(height: 6),
            Text(message, style: const TextStyle(fontSize: 12.5)),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  ref.invalidate(selectionResultProvider);
                  ref.invalidate(allSelectionResultProvider);
                },
                child: const Text('重试'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
