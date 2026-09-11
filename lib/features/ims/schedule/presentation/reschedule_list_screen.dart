import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/providers/reschedule_providers.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/reschedule.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_entry.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/reschedule_editor_sheet.dart';
import 'package:smarter_jxufe/features/score_estimate/presentation/ge_common.dart';

/// 调课管理页：集中查看/编辑/删除本学期的全部调课记录。
///
/// 数据改动经 [RescheduleStore] 广播，课表页与实况窗会立即跟着变，
/// 因此本页返回时**不需要**回传结果。
class RescheduleListScreen extends ConsumerStatefulWidget {
  final RescheduleTerm term;
  final List<ScheduleEntry> entries;

  /// 当前教学周（用于「已过期」分组；无课表数据时可为 null）。
  final int? currentWeek;

  const RescheduleListScreen({
    super.key,
    required this.term,
    required this.entries,
    this.currentWeek,
  });

  @override
  ConsumerState<RescheduleListScreen> createState() =>
      _RescheduleListScreenState();
}

class _RescheduleListScreenState extends ConsumerState<RescheduleListScreen> {
  late final RescheduleStore _store;
  List<Reschedule> _records = const [];

  @override
  void initState() {
    super.initState();
    _store = ref.read(rescheduleStoreProvider);
    _records = _store.recordsOf(widget.term);
    _store.addListener(_onStoreChanged);
    _store.ensureLoaded(widget.term);
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (!mounted) return;
    setState(() => _records = _store.recordsOf(widget.term));
  }

  // ─── 分组 ─────────────────────────────────────────────────────

  bool _isExpired(Reschedule r) {
    final w = widget.currentWeek;
    if (w == null) return false;
    return r.isOnce && r.week < w;
  }

  List<Reschedule> get _active {
    final list = _records.where((r) => !_isExpired(r)).toList();
    list.sort((a, b) {
      if (a.week != b.week) return a.week.compareTo(b.week);
      if (a.kind != b.kind) return a.kind.index.compareTo(b.kind.index);
      return a.courseName.compareTo(b.courseName);
    });
    return list;
  }

  List<Reschedule> get _expired {
    final list = _records.where(_isExpired).toList();
    list.sort((a, b) => b.week.compareTo(a.week));
    return list;
  }

  // ─── 动作 ─────────────────────────────────────────────────────

  Future<void> _openEditor({Reschedule? existing, bool asExtra = false}) async {
    await showRescheduleEditor(
      context,
      term: widget.term,
      store: _store,
      entries: widget.entries,
      existing: existing,
      initialWeek: existing?.week ?? widget.currentWeek ?? 1,
      currentWeek: widget.currentWeek,
      asExtra: asExtra,
    );
  }

  Future<void> _confirmDelete(Reschedule r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.delete_outline),
        title: const Text('删除这条调课记录？'),
        content: Text(
          '「${r.courseName}」${r.scopeText} 将恢复成教务课表的原始安排。',
        ),
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
    if (ok != true) return;
    await _store.remove(widget.term, r.id);
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.delete_sweep_outlined),
        title: const Text('清空本学期调课记录？'),
        content: Text('${widget.term.label} 的 ${_records.length} 条记录将被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _store.clear(widget.term);
  }

  // ─── 构建 ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = _active;
    final expired = _expired;

    return Scaffold(
      appBar: AppBar(
        title: const Text('调课管理'),
        centerTitle: true,
        actions: [
          if (_records.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: '清空本学期调课记录',
              onPressed: _confirmClear,
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(asExtra: true),
        icon: const Icon(Icons.add),
        label: const Text('新增补课'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 96),
        children: [
          _hintCard(scheme),
          const SizedBox(height: 12),
          if (_records.isEmpty)
            _emptyCard(scheme)
          else ...[
            if (active.isNotEmpty) ...[
              geCardTitle(
                context,
                text: '生效中 / 将来',
                accent: FeaturePalette.reschedule,
                trailing: Text(
                  '${active.length} 条',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              for (final r in active) _recordCard(context, r),
              const SizedBox(height: 16),
            ],
            if (expired.isNotEmpty) ...[
              geCardTitle(
                context,
                text: '已过期',
                accent: FeaturePalette.classCancelled,
                trailing: Text(
                  '${expired.length} 条',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              for (final r in expired) _recordCard(context, r, expired: true),
            ],
          ],
        ],
      ),
    );
  }

  Widget _hintCard(ColorScheme scheme) => Card(
    elevation: 0,
    shape: geCardShape(context),
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline,
            size: 18,
            color: FeaturePalette.reschedule,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '调课记录只保存在本机，不会改动教务课表。'
              '课表页切到对应教学周即按调课后显示，实况窗与通知也会跟着调整。',
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _emptyCard(ColorScheme scheme) => Card(
    elevation: 0,
    shape: geCardShape(context),
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
      child: Column(
        children: [
          Icon(
            Icons.event_available_outlined,
            size: 40,
            color: scheme.onSurfaceVariant.withAlpha(150),
          ),
          const SizedBox(height: 12),
          Text(
            '本学期还没有调课记录',
            style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          Text(
            '在课表里点某一节课即可快速调课/停课',
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurfaceVariant.withAlpha(180),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _recordCard(
    BuildContext context,
    Reschedule r, {
    bool expired = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final color = _markColor(r.kind);

    return Card(
      elevation: 0,
      shape: geCardShape(context),
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _openEditor(existing: r),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withAlpha(expired ? 28 : 40),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  r.kind.badge,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: expired ? scheme.onSurfaceVariant : color,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            r.courseName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: expired ? scheme.onSurfaceVariant : null,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          r.scopeText,
                          style: TextStyle(
                            fontSize: 11,
                            color: expired
                                ? scheme.onSurfaceVariant
                                : FeaturePalette.reschedule,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      r.summary,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (r.note.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        '备注：${r.note}',
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant.withAlpha(180),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                tooltip: '删除',
                onPressed: () => _confirmDelete(r),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Color _markColor(RescheduleKind kind) => switch (kind) {
    RescheduleKind.move => FeaturePalette.reschedule,
    RescheduleKind.cancel => FeaturePalette.classCancelled,
    RescheduleKind.extra => FeaturePalette.makeUpClass,
  };
}
