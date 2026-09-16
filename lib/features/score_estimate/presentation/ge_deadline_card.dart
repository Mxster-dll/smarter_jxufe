/// 分数估计 · 课程「截止日期」卡与新增/编辑弹层。
///
/// 入口只有一处：**课程详情页**（用户 2026-09-15 裁定「只在课程详情页加一张卡」）。
/// 卡片排在「备忘录」卡之后；卡上可勾选完成（重复条目 = 完成本期）、编辑、删除。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../design/feature_palette.dart';
import '../domain/ge_deadline.dart';
import 'ge_common.dart';

/// 类型配色。
Color geDeadlineKindColor(GeDeadlineKind kind) => switch (kind) {
  GeDeadlineKind.onlineCourse => FeaturePalette.deadlineOnline,
  GeDeadlineKind.homework => FeaturePalette.deadlineHomework,
  GeDeadlineKind.exam => FeaturePalette.deadlineExam,
  GeDeadlineKind.other => FeaturePalette.deadlineOther,
};

/// 类型图标。
IconData geDeadlineKindIcon(GeDeadlineKind kind) => switch (kind) {
  GeDeadlineKind.onlineCourse => Icons.play_lesson_outlined,
  GeDeadlineKind.homework => Icons.assignment_outlined,
  GeDeadlineKind.exam => Icons.quiz_outlined,
  GeDeadlineKind.other => Icons.event_note_outlined,
};

/// 状态配色：已完成灰、已过期红、今天/3 天内橙、更远蓝灰。
Color geDeadlineStatusColor(GeDeadlineStatus status) => switch (status) {
  GeDeadlineStatus.done => FeaturePalette.deadlineDone,
  GeDeadlineStatus.overdue => FeaturePalette.deadlineOverdue,
  GeDeadlineStatus.today => FeaturePalette.deadlineSoon,
  GeDeadlineStatus.soon => FeaturePalette.deadlineSoon,
  GeDeadlineStatus.upcoming => FeaturePalette.scoreEstimateFinal,
};

/// 一门课的截止日期卡。
///
/// 自带 30 秒刷新（倒计时会走）；测试里传 `tickInterval: Duration.zero` 关掉定时器，
/// 否则 `pumpAndSettle` 会被周期性重建拖到超时。
class GeDeadlineCard extends StatefulWidget {
  const GeDeadlineCard({
    super.key,
    required this.deadlines,
    required this.onAdd,
    required this.onEdit,
    required this.onToggleDone,
    required this.onDelete,
    this.now,
    this.tickInterval = const Duration(seconds: 30),
  });

  /// 本课的全部截止日期（内部排序）。
  final List<GeDeadline> deadlines;

  /// 新增（打开编辑弹层）。
  final VoidCallback onAdd;

  /// 编辑某条。
  final ValueChanged<GeDeadline> onEdit;

  /// 勾选 / 取消完成（重复条目 = 完成本期）。
  final ValueChanged<GeDeadline> onToggleDone;

  /// 删除某条。
  final ValueChanged<GeDeadline> onDelete;

  /// 注入「现在」（测试用；null = 真实时间）。
  final DateTime? now;

  /// 倒计时刷新间隔；`Duration.zero` = 不刷新。
  final Duration tickInterval;

  @override
  State<GeDeadlineCard> createState() => _GeDeadlineCardState();
}

class _GeDeadlineCardState extends State<GeDeadlineCard> {
  late DateTime _now = widget.now ?? DateTime.now();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    if (widget.now != null || widget.tickInterval <= Duration.zero) return;
    _timer = Timer.periodic(widget.tickInterval, (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.now ?? _now;
    final sorted = geSortedDeadlines(widget.deadlines, now);
    final pending = [
      for (final d in sorted)
        if (!geDeadlineDoneNow(d, now)) d,
    ].length;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: geCardShape(context),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            geCardTitle(
              context,
              text: '截止日期',
              trailing: TextButton.icon(
                onPressed: widget.onAdd,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加'),
              ),
            ),
            Text(
              sorted.isEmpty
                  ? '记下网课、作业、考试的截止时间，到期前会收到系统通知。'
                  : '共 ${sorted.length} 条 · 还有 $pending 条未完成',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 6),
            if (sorted.isEmpty)
              _EmptyHint(onAdd: widget.onAdd)
            else
              for (final d in sorted) _row(context, d, now),
            if (sorted.isNotEmpty) ...[
              const SizedBox(height: 4),
              Divider(height: 18, color: Theme.of(context).colorScheme.outlineVariant),
            ],
            Text(
              '提醒：提前 1 天 + 提前 1 小时（系统通知，可逐条关闭）。'
              '每周 / 每两周的条目按规则自动滚到下一次，不会堆积成过期。',
              style: TextStyle(fontSize: 11.5, height: 1.5, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, GeDeadline d, DateTime now) {
    final scheme = Theme.of(context).colorScheme;
    final status = geDeadlineStatus(d, now);
    final done = status == GeDeadlineStatus.done;
    final statusColor = geDeadlineStatusColor(status);
    final due = geDeadlineEffectiveDue(d, now);
    final kindColor = geDeadlineKindColor(d.kind);

    return InkWell(
      onTap: () => widget.onEdit(d),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 40,
              height: 40,
              child: IconButton(
                padding: EdgeInsets.zero,
                tooltip: done ? '取消完成' : (d.isRepeating ? '完成本期' : '标为完成'),
                icon: Icon(
                  done ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 22,
                  color: done ? FeaturePalette.deadlineDone : scheme.outline,
                ),
                onPressed: () => widget.onToggleDone(d),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          d.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            decoration: done ? TextDecoration.lineThrough : null,
                            color: done ? Colors.grey.shade600 : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: kindColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          d.badge,
                          style: TextStyle(fontSize: 10.5, color: kindColor),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Tooltip(
                        message: '${status.label} · ${geDeadlineRepeatText(d, now)}',
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            geDeadlineCountdownText(d, now),
                            style: TextStyle(fontSize: 11, color: statusColor),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          '${geDeadlineDueText(due, now)}'
                          '${d.isRepeating ? ' · ${d.repeat.label}' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                        ),
                      ),
                      if (d.remind) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.notifications_active_outlined,
                          size: 12,
                          color: Colors.grey.shade500,
                        ),
                      ],
                    ],
                  ),
                  if (d.note.trim().isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      d.note.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                  ],
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: '更多',
              icon: Icon(Icons.more_vert, size: 20, color: scheme.outline),
              onSelected: (v) {
                if (v == 'edit') widget.onEdit(d);
                if (v == 'delete') widget.onDelete(d);
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'edit', child: Text('编辑')),
                PopupMenuItem(value: 'delete', child: Text('删除')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 空态（卡内）。
class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(
            Icons.event_available_outlined,
            size: 20,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '还没有截止日期。点右上角「添加」记一条，例如「网课第 2 讲测验」。',
              style: TextStyle(fontSize: 12.5, height: 1.4),
            ),
          ),
          TextButton(onPressed: onAdd, child: const Text('添加')),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- 编辑弹层

/// 打开新增 / 编辑弹层；返回编辑结果（null = 用户取消）。
Future<GeDeadline?> showGeDeadlineEditor(
  BuildContext context, {
  GeDeadline? existing,
  DateTime? now,
}) {
  return showModalBottomSheet<GeDeadline>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (context) => _GeDeadlineEditor(
      existing: existing,
      now: now ?? DateTime.now(),
    ),
  );
}

/// 默认截止时刻 = 今天 23:59（已过则明天 23:59）。
DateTime geDeadlineDefaultDue(DateTime now) {
  final today = DateTime(now.year, now.month, now.day, 23, 59);
  return today.isAfter(now) ? today : today.add(const Duration(days: 1));
}

class _GeDeadlineEditor extends StatefulWidget {
  const _GeDeadlineEditor({required this.existing, required this.now});

  final GeDeadline? existing;
  final DateTime now;

  @override
  State<_GeDeadlineEditor> createState() => _GeDeadlineEditorState();
}

class _GeDeadlineEditorState extends State<_GeDeadlineEditor> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _noteCtrl;
  late GeDeadlineKind _kind;
  late GeDeadlineRepeat _repeat;
  late DateTime _due;
  late bool _remind;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _titleCtrl = TextEditingController(text: e?.title ?? '');
    _noteCtrl = TextEditingController(text: e?.note ?? '');
    _kind = e?.kind ?? GeDeadlineKind.homework;
    _repeat = e?.repeat ?? GeDeadlineRepeat.none;
    _due = e?.dueAt ?? geDeadlineDefaultDue(widget.now);
    _remind = e?.remind ?? true;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  bool get _canSave => _titleCtrl.text.trim().isNotEmpty;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _due,
      firstDate: DateTime(widget.now.year - 2),
      lastDate: DateTime(widget.now.year + 6, 12, 31),
      helpText: '选择截止日期',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _due = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _due.hour,
        _due.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_due),
      helpText: '选择截止时刻',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _due = DateTime(
        _due.year,
        _due.month,
        _due.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  void _save() {
    if (!_canSave) return;
    final e = widget.existing;
    Navigator.pop(
      context,
      GeDeadline(
        id: e?.id ?? const Uuid().v4(),
        title: _titleCtrl.text.trim(),
        kind: _kind,
        dueAt: _due,
        repeat: _repeat,
        note: _noteCtrl.text.trim(),
        doneAt: e?.doneAt,
        remind: _remind,
        createdAt: e?.createdAt ?? widget.now.millisecondsSinceEpoch,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = geDeadlineKindColor(_kind);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(geDeadlineKindIcon(_kind), size: 20, color: color),
                const SizedBox(width: 8),
                Text(
                  widget.existing == null ? '添加截止日期' : '编辑截止日期',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _titleCtrl,
              autofocus: widget.existing == null,
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: '标题',
                hintText: '如 第 3 章习题 / 网课第 2 讲测验',
              ),
            ),
            const SizedBox(height: 14),
            const _FieldLabel('类型'),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final k in GeDeadlineKind.values)
                  ChoiceChip(
                    avatar: Icon(
                      geDeadlineKindIcon(k),
                      size: 16,
                      color: _kind == k ? Colors.white : geDeadlineKindColor(k),
                    ),
                    label: Text(k.label),
                    selected: _kind == k,
                    selectedColor: geDeadlineKindColor(k),
                    labelStyle: TextStyle(
                      color: _kind == k ? Colors.white : null,
                    ),
                    onSelected: (_) => setState(() => _kind = k),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            const _FieldLabel('截止时间'),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.event, size: 18),
                    label: Text(geDeadlineDateText(_due, widget.now)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickTime,
                    icon: const Icon(Icons.schedule, size: 18),
                    label: Text(geDeadlineClockText(_due)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const _FieldLabel('重复'),
            Wrap(
              spacing: 8,
              children: [
                for (final r in GeDeadlineRepeat.values)
                  ChoiceChip(
                    label: Text(r.label),
                    selected: _repeat == r,
                    onSelected: (_) => setState(() => _repeat = r),
                  ),
              ],
            ),
            if (_repeat.isRepeating)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '以 ${geDeadlineDueText(_due, widget.now)} 为起点，${_repeat.label}'
                  '自动滚到下一个未到期的时刻；过期不会堆积。',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                ),
              ),
            const SizedBox(height: 6),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _remind,
              onChanged: (v) => setState(() => _remind = v),
              title: const Text('到期提醒'),
              subtitle: Text(
                _remind ? '提前 1 天 + 提前 1 小时（系统通知）' : '不提醒',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _noteCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: '备注（可选）',
                hintText: '如 超星学习通 · 需提交 PDF',
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: _canSave ? _save : null,
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('保存'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Colors.grey.shade700,
      ),
    ),
  );
}
