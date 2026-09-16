/// 选课确认面板 —— 选教学班 + 是否买教材 + 提交（教务原生的「选课-课程名」弹窗）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/features/ims/course_selection/data/course_selection_repository.dart';
import 'package:smarter_jxufe/features/ims/course_selection/data/datasources/course_selection_remote_datasource.dart';
import 'package:smarter_jxufe/features/ims/course_selection/data/providers/course_selection_providers.dart';
import 'package:smarter_jxufe/features/ims/course_selection/domain/selection_models.dart';
import 'package:smarter_jxufe/features/ims/course_selection/domain/selection_parsers.dart';
import 'package:smarter_jxufe/features/score_estimate/presentation/ge_common.dart';

Future<void> showCourseSectionSheet({
  required BuildContext context,
  required WidgetRef ref,
  required SelectionChannel channel,
  required OptionalCourse course,
  required SelectionSession session,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) =>
        _CourseSectionSheet(channel: channel, course: course, session: session),
  );
}

class _CourseSectionSheet extends ConsumerStatefulWidget {
  const _CourseSectionSheet({
    required this.channel,
    required this.course,
    required this.session,
  });

  final SelectionChannel channel;
  final OptionalCourse course;
  final SelectionSession session;

  @override
  ConsumerState<_CourseSectionSheet> createState() =>
      _CourseSectionSheetState();
}

class _CourseSectionSheetState extends ConsumerState<_CourseSectionSheet> {
  CourseSection? _section;
  bool? _buyBook;
  bool _isCx = false;
  bool _isYxtj = false;
  bool _allowTimeConflict = false;
  bool _submitting = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final query = CourseSectionQuery(
      channel: widget.channel,
      internalCode: widget.course.internalCode,
      courseName: widget.course.name,
    );
    final sectionsAsync = ref.watch(courseSectionsProvider(query));
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              geCardTitle(
                context,
                text: '选课 · ${widget.course.name}',
                accent: FeaturePalette.cardAccent,
                trailing: Text(
                  [
                    if (widget.course.credits != null)
                      '${geFmt(widget.course.credits!)} 学分',
                    if (widget.course.totalHours != null)
                      '${widget.course.totalHours} 学时',
                  ].join(' · '),
                  style: TextStyle(fontSize: 12, color: scheme.outline),
                ),
              ),
              if (widget.session.lcmc.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${widget.session.xnxqDesc} · ${widget.session.lcmc}',
                    style: TextStyle(fontSize: 12, color: scheme.outline),
                  ),
                ),
              const SizedBox(height: 10),
              Flexible(
                child: sectionsAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (error, _) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      '教学班加载失败：$error',
                      style: TextStyle(fontSize: 12.5, color: scheme.error),
                    ),
                  ),
                  data: (sections) => sections.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            '该课程暂无可选教学班',
                            style: TextStyle(
                              fontSize: 13,
                              color: scheme.outline,
                            ),
                          ),
                        )
                      : RadioGroup<String>(
                          groupValue: _section?.classCode,
                          onChanged: (value) => setState(() {
                            _section = sections.firstWhere(
                              (e) => e.classCode == value,
                              orElse: () => sections.first,
                            );
                          }),
                          child: ListView(
                            shrinkWrap: true,
                            children: [
                              for (final section in sections)
                                _sectionTile(context, section),
                            ],
                          ),
                        ),
                ),
              ),
              const Divider(height: 20),
              _buyBookRow(context),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _isCx,
                title: const Text('重修', style: TextStyle(fontSize: 13.5)),
                onChanged: (value) => setState(() => _isCx = value),
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _isYxtj,
                title: const Text('允许调剂', style: TextStyle(fontSize: 13.5)),
                onChanged: (value) => setState(() => _isYxtj = value),
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _allowTimeConflict,
                title: const Text('允许时间冲突', style: TextStyle(fontSize: 13.5)),
                onChanged: (value) =>
                    setState(() => _allowTimeConflict = value),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: Text(
                    _submitting
                        ? '提交中…'
                        : widget.session.open
                        ? '提交选课'
                        : '不在选课时间',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTile(BuildContext context, CourseSection section) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _section?.classCode == section.classCode;
    final details = <String>[
      if (section.teacher.isNotEmpty) section.teacher,
      if (section.timePlace.isNotEmpty) section.timePlace,
      if (section.campus.isNotEmpty) section.campus,
      if (section.enrolled.isNotEmpty) '已选 ${section.enrolled}',
      if (section.limit.isNotEmpty) '限选 ${section.limit}',
    ];
    return RadioListTile<String>(
      dense: true,
      contentPadding: EdgeInsets.zero,
      value: section.classCode,
      selected: selected,
      title: Row(
        children: [
          Expanded(
            child: Text(
              section.classCode.isEmpty ? '教学班' : section.classCode,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (section.className.isNotEmpty)
            Text(
              section.className,
              style: TextStyle(fontSize: 12, color: scheme.outline),
            ),
        ],
      ),
      subtitle: Text(
        details.join(' · '),
        style: TextStyle(fontSize: 12, color: scheme.outline),
      ),
    );
  }

  Widget _buyBookRow(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        const Text('购买教材', style: TextStyle(fontSize: 13.5)),
        const SizedBox(width: 12),
        Expanded(
          child: Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('是'),
                selected: _buyBook == true,
                onSelected: (_) => setState(() => _buyBook = true),
              ),
              ChoiceChip(
                label: const Text('否'),
                selected: _buyBook == false,
                onSelected: (_) => setState(() => _buyBook = false),
              ),
            ],
          ),
        ),
        if (_buyBook == null)
          Text('教务必填', style: TextStyle(fontSize: 11.5, color: scheme.outline)),
      ],
    );
  }

  Future<void> _submit() async {
    final section = _section;
    if (section == null) {
      _toast('请先选定上课班号');
      return;
    }
    if (_buyBook == null) {
      _toast('需选定是否购买教材');
      return;
    }
    if (!widget.session.open) {
      _toast('当前不在选课时间区段');
      return;
    }
    var acknowledged = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          icon: const Icon(Icons.school_outlined),
          title: const Text('确认选课'),
          scrollable: true,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${widget.course.name}（${widget.course.courseCode}）'),
              const SizedBox(height: 6),
              Text('教学班：${section.classCode}'),
              if (section.teacher.isNotEmpty) Text('任课教师：${section.teacher}'),
              if (section.timePlace.isNotEmpty)
                Text('上课时间地点：${section.timePlace}'),
              Text('购买教材：${_buyBook == true ? '是' : '否'}'),
              const Divider(height: 20),
              // ⚠ 强制核对（2026-09-15 退选事故后统一口径）：破坏/写入类操作必须让用户
              // **看着课程名与教学班号**确认一次，不能顺手点确认。
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
                        '我已核对：要选的是《${widget.course.name}》· 教学班 ${section.classCode}',
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
              onPressed: acknowledged
                  ? () => Navigator.of(dialogContext).pop(true)
                  : null,
              child: const Text('确认选课'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _submitting = true);
    try {
      final actions = ref.read(courseSelectionActionsProvider);
      // 与教务一致：先问「该课程是否允许选择」，被拒时把教务原文带给用户。
      final allowed = await actions.checkSelectable(
        channel: widget.channel,
        internalCode: widget.course.internalCode,
      );
      if (!allowed.ok) {
        _toast(allowed.message.isEmpty ? '该课程当前不可选' : allowed.message);
        return;
      }
      final outcome = await actions.submitAndVerify(
        channel: widget.channel,
        course: widget.course,
        section: section,
        buyBook: _buyBook == true,
        isCx: _isCx,
        isYxtj: _isYxtj,
        allowTimeConflict: _allowTimeConflict,
      );
      if (!mounted) return;
      final write = outcome.write;
      final check = outcome.check;
      // 教务的写应答零信息量（空 items / 不存在的码都回「操作成功!」，见
      // `parseWriteEnvelope`）→ **对账结论优先**，且没对上账就不要说「选课成功」。
      if (!write.ok) {
        _toast(
          check == null
              ? (write.message.isEmpty ? '选课失败' : write.message)
              : '教务未接受这次选课'
                    '（${write.message.isEmpty ? '无返回' : write.message}）；'
                    '最新选课结果：${check.message}',
        );
      } else if (check == null) {
        _toast(
          '选课请求已提交（教务回「${write.message}」），但没能重读选课结果核对 —— '
          '请到教务确认是否真的选上',
        );
      } else {
        _toast(check.message);
        if (check.ok && mounted) Navigator.of(context).pop();
      }
    } catch (error) {
      _toast('选课失败：$error');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
