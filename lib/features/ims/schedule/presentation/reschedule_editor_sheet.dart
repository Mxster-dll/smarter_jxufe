import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/providers/reschedule_providers.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/class_time.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/reschedule.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/reschedule_engine.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_entry.dart';

/// 「原课」信息 —— 从课表格子/列表项带进编辑弹层。
class RescheduleOrigin {
  final String courseCode;
  final String courseName;
  final String classCode;
  final String teacher;
  final DayOfWeek day;
  final int startPeriod;
  final int endPeriod;
  final String classroom;

  const RescheduleOrigin({
    required this.courseCode,
    required this.courseName,
    required this.classCode,
    required this.teacher,
    required this.day,
    required this.startPeriod,
    required this.endPeriod,
    required this.classroom,
  });

  /// 由课表条目 + 时段构造，如点空白课表格子里的课。
  factory RescheduleOrigin.of(ScheduleEntry entry, ClassTime ct) =>
      RescheduleOrigin(
        courseCode: entry.courseCode,
        courseName: entry.courseName,
        classCode: entry.classCode,
        teacher: entry.teacherName,
        day: ct.dayOfWeek,
        startPeriod: ct.startPeriod,
        endPeriod: ct.endPeriod,
        classroom: ct.classroom,
      );

  /// 由一条既有调课记录还原。
  factory RescheduleOrigin.ofRecord(Reschedule r) => RescheduleOrigin(
    courseCode: r.courseCode,
    courseName: r.courseName,
    classCode: r.classCode,
    teacher: r.originTeacher,
    day: r.originDay ?? DayOfWeek.monday,
    startPeriod: r.originStartPeriod ?? 1,
    endPeriod: r.originEndPeriod ?? r.originStartPeriod ?? 1,
    classroom: r.originClassroom,
  );
}

/// 打开调课编辑弹层。
///
/// - [existing] 非空 → 编辑既有记录（删除按钮可用）；
/// - [origin] 非空 → 新建记录（原课信息来自被点的格子）；
/// - 两者都为空 → 新建**补课**（原课表里没有的额外一次课）。
///
/// 返回 true 表示已保存/删除（调用方其实不必处理：数据改动会经
/// [RescheduleStore] 广播给所有页面）。
Future<bool> showRescheduleEditor(
  BuildContext context, {
  required RescheduleTerm term,
  required RescheduleStore store,
  required List<ScheduleEntry> entries,
  Reschedule? existing,
  RescheduleOrigin? origin,
  int initialWeek = 1,
  int? currentWeek,
  bool asExtra = false,
  DayOfWeek? initialDay,
  int? initialStartPeriod,
  int? initialEndPeriod,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _RescheduleEditorSheet(
      term: term,
      store: store,
      entries: entries,
      existing: existing,
      origin: origin,
      initialWeek: initialWeek,
      currentWeek: currentWeek,
      asExtra: asExtra,
      initialDay: initialDay,
      initialStartPeriod: initialStartPeriod,
      initialEndPeriod: initialEndPeriod,
    ),
  );
  return result ?? false;
}

class _RescheduleEditorSheet extends StatefulWidget {
  final RescheduleTerm term;
  final RescheduleStore store;
  final List<ScheduleEntry> entries;
  final Reschedule? existing;
  final RescheduleOrigin? origin;
  final int initialWeek;
  final int? currentWeek;
  final bool asExtra;
  final DayOfWeek? initialDay;
  final int? initialStartPeriod;
  final int? initialEndPeriod;

  const _RescheduleEditorSheet({
    required this.term,
    required this.store,
    required this.entries,
    this.existing,
    this.origin,
    required this.initialWeek,
    this.currentWeek,
    required this.asExtra,
    this.initialDay,
    this.initialStartPeriod,
    this.initialEndPeriod,
  });

  @override
  State<_RescheduleEditorSheet> createState() => _RescheduleEditorSheetState();
}

class _RescheduleEditorSheetState extends State<_RescheduleEditorSheet> {
  static const _maxWeek = 24;

  late RescheduleKind _kind;
  late RescheduleScope _scope;
  late int _week;
  late DayOfWeek _targetDay;
  late int _startPeriod;
  late int _endPeriod;

  final _roomCtrl = TextEditingController();
  final _teacherCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _customNameCtrl = TextEditingController();

  /// 补课：从既有课表里挑一门课（null = 自定义）
  ScheduleEntry? _pickedEntry;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  bool get _isExtra => _kind == RescheduleKind.extra;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final o = widget.origin;

    _kind =
        e?.kind ??
        (widget.asExtra ? RescheduleKind.extra : RescheduleKind.move);
    _scope = e?.scope ?? RescheduleScope.once;
    _week = e?.week ?? widget.initialWeek;

    _targetDay =
        e?.targetDay ?? o?.day ?? widget.initialDay ?? DayOfWeek.monday;
    _startPeriod =
        e?.targetStartPeriod ??
        o?.startPeriod ??
        widget.initialStartPeriod ??
        1;
    _endPeriod =
        e?.targetEndPeriod ??
        o?.endPeriod ??
        widget.initialEndPeriod ??
        _startPeriod;

    _roomCtrl.text = e?.targetClassroom ?? o?.classroom ?? '';
    _teacherCtrl.text = e?.newTeacher ?? e?.originTeacher ?? o?.teacher ?? '';
    _noteCtrl.text = e?.note ?? '';

    // 补课：可能从课表里挑了一门课，也可能是纯自定义课名。
    // 课名一律预填（用户把「调课」改成「补课」时不必重打一遍）。
    final name = e?.courseName ?? o?.courseName ?? '';
    _customNameCtrl.text = name;
    _pickedEntry = _findEntryByName(name);
  }

  /// 课表里是否有同名课（补课时挑回来，沿用课程代码 → 颜色一致）。
  ScheduleEntry? _findEntryByName(String name) {
    if (name.isEmpty) return null;
    for (final e in widget.entries) {
      if (e.courseName == name) return e;
    }
    return null;
  }

  @override
  void dispose() {
    _roomCtrl.dispose();
    _teacherCtrl.dispose();
    _noteCtrl.dispose();
    _customNameCtrl.dispose();
    super.dispose();
  }

  // ─── 取值：原课信息 ────────────────────────────────────────────

  String get _courseCode {
    if (_isExtra) return _pickedEntry?.courseCode ?? '';
    return widget.existing?.courseCode ?? widget.origin?.courseCode ?? '';
  }

  String get _classCode {
    if (_isExtra) return _pickedEntry?.classCode ?? '';
    return widget.existing?.classCode ?? widget.origin?.classCode ?? '';
  }

  String get _courseName {
    if (_isExtra) {
      return _pickedEntry?.courseName ?? _customNameCtrl.text.trim();
    }
    return widget.existing?.courseName ?? widget.origin?.courseName ?? '';
  }

  String get _originTeacher {
    if (_isExtra) {
      final t = widget.existing?.originTeacher;
      if (t != null && t.isNotEmpty) return t;
      return _pickedEntry?.teacherName ?? _teacherCtrl.text.trim();
    }
    return widget.existing?.originTeacher ?? widget.origin?.teacher ?? '';
  }

  DayOfWeek? get _originDay {
    if (_isExtra) return null;
    return widget.existing?.originDay ?? widget.origin?.day;
  }

  int? get _originStart {
    if (_isExtra) return null;
    return widget.existing?.originStartPeriod ?? widget.origin?.startPeriod;
  }

  int? get _originEnd {
    if (_isExtra) return null;
    return widget.existing?.originEndPeriod ?? widget.origin?.endPeriod;
  }

  String get _originRoom {
    if (_isExtra) return '';
    return widget.existing?.originClassroom ?? widget.origin?.classroom ?? '';
  }

  // ─── 保存 ─────────────────────────────────────────────────────

  String? _validate() {
    if (_courseName.isEmpty) return '请填写课程名称';
    if (_kind == RescheduleKind.cancel) return null;
    if (_startPeriod > _endPeriod) return '起始节次不能晚于结束节次';
    if (_kind == RescheduleKind.move &&
        _originDay == _targetDay &&
        _originStart == _startPeriod &&
        _originEnd == _endPeriod &&
        _roomCtrl.text.trim() == _originRoom &&
        _teacherCtrl.text.trim() == _originTeacher) {
      return '时间和地点都没变，无需调课';
    }
    return null;
  }

  Future<void> _save() async {
    final err = _validate();
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    setState(() => _saving = true);
    final now = DateTime.now();
    final teacherText = _teacherCtrl.text.trim();
    final record = Reschedule(
      id: widget.existing?.id ?? const Uuid().v4(),
      kind: _kind,
      scope: _scope,
      week: _week,
      courseCode: _courseCode,
      courseName: _courseName,
      classCode: _classCode,
      originTeacher: _isExtra ? teacherText : _originTeacher,
      originDay: _originDay,
      originStartPeriod: _originStart,
      originEndPeriod: _originEnd,
      originClassroom: _originRoom,
      targetDay: _kind == RescheduleKind.cancel ? null : _targetDay,
      targetStartPeriod: _kind == RescheduleKind.cancel ? null : _startPeriod,
      targetEndPeriod: _kind == RescheduleKind.cancel ? null : _endPeriod,
      targetClassroom: _kind == RescheduleKind.cancel
          ? ''
          : _roomCtrl.text.trim(),
      newTeacher:
          _isExtra || teacherText.isEmpty || teacherText == _originTeacher
          ? null
          : teacherText,
      note: _noteCtrl.text.trim(),
      createdAt: widget.existing?.createdAt ?? now,
      updatedAt: now,
    );

    await widget.store.upsert(widget.term, record);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final id = widget.existing?.id;
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.delete_outline),
        title: const Text('删除这条调课记录？'),
        content: Text('「${widget.existing!.courseName}」将恢复成教务课表的原始时间地点。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await widget.store.remove(widget.term, id);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  // ─── 冲突检测 ─────────────────────────────────────────────────

  /// 调整到的时段是否与别的课撞车（只提示，不阻止）。
  String? _conflictHint() {
    if (_kind == RescheduleKind.cancel) return null;
    final others = widget.store
        .recordsOf(widget.term)
        .where((r) => r.id != widget.existing?.id)
        .toList();
    final effective = effectiveClasses(
      entries: widget.entries,
      reschedules: others,
      week: _week,
    );
    final clashes = effective
        .where(
          (c) =>
              !c.isMovedAway &&
              !c.isCancelled &&
              c.dayIndex == _targetDay.dayIndex &&
              c.startPeriod <= _endPeriod &&
              c.endPeriod >= _startPeriod &&
              !(c.courseCode.isNotEmpty && c.courseCode == _courseCode),
        )
        .map(
          (c) =>
              '${c.courseName}(${c.dayIndex == _targetDay.dayIndex ? c.periodText : ''})',
        )
        .toSet()
        .take(3)
        .toList();
    if (clashes.isEmpty) return null;
    return '第 $_week 周 ${_targetDay.displayName} 该时段已有：${clashes.join('、')}';
  }

  // ─── 构建 ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final conflict = _conflictHint();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.86,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    _isEditing
                        ? Icons.edit_calendar
                        : (_isExtra ? Icons.add_task : Icons.event_repeat),
                    size: 20,
                    color: kRescheduleColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _isEditing ? '编辑调课记录' : (_isExtra ? '新增补课' : '调整这节课'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    widget.term.label,
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              if (_isExtra) ...[
                _extraCoursePicker(scheme),
                const SizedBox(height: 12),
              ] else
                _originCard(scheme),

              const SizedBox(height: 14),
              _sectionLabel('怎么调', scheme),
              const SizedBox(height: 6),
              SegmentedButton<RescheduleKind>(
                segments: const [
                  ButtonSegment(
                    value: RescheduleKind.move,
                    icon: Icon(Icons.swap_horiz, size: 16),
                    label: Text('调课'),
                  ),
                  ButtonSegment(
                    value: RescheduleKind.cancel,
                    icon: Icon(Icons.block, size: 16),
                    label: Text('停课'),
                  ),
                  ButtonSegment(
                    value: RescheduleKind.extra,
                    icon: Icon(Icons.add_circle_outline, size: 16),
                    label: Text('补课'),
                  ),
                ],
                selected: {_kind},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _kind = s.first),
              ),

              const SizedBox(height: 14),
              _sectionLabel('生效范围', scheme),
              const SizedBox(height: 6),
              SegmentedButton<RescheduleScope>(
                segments: const [
                  ButtonSegment(
                    value: RescheduleScope.once,
                    label: Text('仅这一次'),
                  ),
                  ButtonSegment(
                    value: RescheduleScope.recurring,
                    label: Text('从这周起长期'),
                  ),
                ],
                selected: {_scope},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _scope = s.first),
              ),
              const SizedBox(height: 8),
              _weekRow(scheme),

              if (_kind != RescheduleKind.cancel) ...[
                const SizedBox(height: 14),
                _sectionLabel('调整到', scheme),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final d in DayOfWeek.values)
                      ChoiceChip(
                        label: Text(d.displayName),
                        selected: _targetDay == d,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => setState(() => _targetDay = d),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Text('节次', style: TextStyle(fontSize: 13)),
                    const SizedBox(width: 10),
                    _periodDropdown(
                      value: _startPeriod,
                      onChanged: (v) => setState(() {
                        _startPeriod = v;
                        if (_endPeriod < v) _endPeriod = v;
                      }),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6),
                      child: Text('—'),
                    ),
                    _periodDropdown(
                      value: _endPeriod,
                      onChanged: (v) => setState(() {
                        _endPeriod = v;
                        if (_startPeriod > v) _startPeriod = v;
                      }),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Text('节', style: TextStyle(fontSize: 13)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _roomCtrl,
                  decoration: const InputDecoration(
                    labelText: '教室',
                    hintText: '如 麦三教3501；留空则沿用原教室',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                if (!_isExtra) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _teacherCtrl,
                    decoration: const InputDecoration(
                      labelText: '任课教师',
                      hintText: '改了才填；与原来相同时不会生成变更',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ],

              const SizedBox(height: 12),
              TextField(
                controller: _noteCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: '备注（可选）',
                  hintText: '如 老师出差，顺延到周五',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),

              if (conflict != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8E1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        size: 16,
                        color: Color(0xFFE65100),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          conflict,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFFE65100),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16),
              Row(
                children: [
                  if (_isEditing)
                    TextButton.icon(
                      onPressed: _saving ? null : _delete,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('删除'),
                      style: TextButton.styleFrom(
                        foregroundColor: scheme.error,
                      ),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_isEditing ? '保存' : '添加'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _originCard(ColorScheme scheme) {
    final o = widget.existing;
    final name = o?.courseName ?? widget.origin?.courseName ?? '';
    final teacher = o?.originTeacher ?? widget.origin?.teacher ?? '';
    final place = o != null && o.originDay != null
        ? o.originText
        : (widget.origin == null
              ? ''
              : '${widget.origin!.day.displayName} '
                    '${periodRangeText(widget.origin!.startPeriod, widget.origin!.endPeriod)}'
                    '${widget.origin!.classroom.isEmpty ? '' : ' · ${widget.origin!.classroom}'}');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withAlpha(120),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            [
              if (teacher.isNotEmpty) teacher,
              if (place.isNotEmpty) place,
            ].join(' · '),
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _extraCoursePicker(ColorScheme scheme) {
    final courses = <String, ScheduleEntry>{};
    for (final e in widget.entries) {
      courses.putIfAbsent(e.courseName, () => e);
    }
    final picked = _pickedEntry;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('补哪门课', scheme),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: picked?.courseName ?? '',
          isDense: true,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem(value: '', child: Text('自定义课程…')),
            for (final name in courses.keys)
              DropdownMenuItem(value: name, child: Text(name)),
          ],
          onChanged: (v) => setState(() {
            _pickedEntry = v == null || v.isEmpty ? null : courses[v];
            if (_pickedEntry != null) {
              _teacherCtrl.text = _pickedEntry!.teacherName;
            }
          }),
        ),
        if (picked == null) ...[
          const SizedBox(height: 10),
          TextField(
            controller: _customNameCtrl,
            decoration: const InputDecoration(
              labelText: '课程名称',
              hintText: '如 高等数学（补课）',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _teacherCtrl,
            decoration: const InputDecoration(
              labelText: '任课教师（可选）',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _weekRow(ColorScheme scheme) {
    final isOnce = _scope == RescheduleScope.once;
    return Row(
      children: [
        IconButton(
          tooltip: '上一周',
          visualDensity: VisualDensity.compact,
          onPressed: _week > 1 ? () => setState(() => _week--) : null,
          icon: const Icon(Icons.remove_circle_outline, size: 20),
        ),
        Text(
          isOnce ? '第 $_week 周' : '第 $_week 周起',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        IconButton(
          tooltip: '下一周',
          visualDensity: VisualDensity.compact,
          onPressed: _week < _maxWeek ? () => setState(() => _week++) : null,
          icon: const Icon(Icons.add_circle_outline, size: 20),
        ),
        if (widget.currentWeek != null && widget.currentWeek != _week)
          TextButton(
            onPressed: () => setState(() => _week = widget.currentWeek!),
            child: const Text('本周'),
          ),
      ],
    );
  }

  Widget _sectionLabel(String text, ColorScheme scheme) => Text(
    text,
    style: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: scheme.onSurfaceVariant,
    ),
  );

  Widget _periodDropdown({
    required int value,
    required ValueChanged<int> onChanged,
  }) => DropdownButtonHideUnderline(
    child: DropdownButton<int>(
      value: value,
      isDense: true,
      style: TextStyle(
        fontSize: 13,
        color: Theme.of(context).colorScheme.onSurface,
      ),
      items: [
        for (var i = 1; i <= 12; i++)
          DropdownMenuItem(value: i, child: Text('$i')),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    ),
  );
}

/// 调课功能主色（登记在 [FeaturePalette.reschedule]）。
const kRescheduleColor = FeaturePalette.reschedule;
