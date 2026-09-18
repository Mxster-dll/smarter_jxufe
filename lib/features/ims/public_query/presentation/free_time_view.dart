import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/features/ims/public_query/domain/free_time.dart';
import 'package:smarter_jxufe/features/score_estimate/presentation/ge_common.dart';

/// 参与对照的一个对象（一个班 / 一位教师 / 一间教室）。
class PublicScheduleColumn {
  /// 展示名（班级名、教师名、教室名）。
  final String owner;

  /// 该对象课表展开后的占用槽。
  final List<ScheduleSlot> slots;

  const PublicScheduleColumn({required this.owner, required this.slots});
}

/// 「多班对照找无课时间」的呈现：周网格（占用热力 + 全空高亮）+ 空闲时段清单。
///
/// 纯展示组件：所有计算都走 `domain/free_time.dart` 的纯函数，
/// 因此可以脱离网络与页面单测。
class FreeTimeView extends StatelessWidget {
  /// 参与对照的对象（≥1 个）。
  final List<PublicScheduleColumn> columns;

  /// 当前教学周（1 起）。
  final int week;

  /// 一天最大节次。
  final int maxPeriod;

  /// 是否纳入周末。
  final bool includeWeekend;

  /// 只列出连续节数 ≥ 该值的窗口。
  final int minPeriods;

  /// 节次 → 起始时刻（`HH:mm`），用于清单里显示钟点；缺省则不显示。
  final Map<int, String> periodStarts;

  /// 点某个全空格子。
  final ValueChanged<FreeWindow>? onTapWindow;

  const FreeTimeView({
    super.key,
    required this.columns,
    required this.week,
    this.maxPeriod = 12,
    this.includeWeekend = false,
    this.minPeriods = 1,
    this.periodStarts = const {},
    this.onTapWindow,
  });

  // 「全空」格子的语义色走 `AppColors.success*`（浅色 = 原来的
  // `#E8F5E9` / `#2E7D32`，深色自动提亮），见 `lib/design/app_theme.dart`。

  List<ScheduleSlot> get _slots => [for (final c in columns) ...c.slots];

  Set<int> get _weekdays =>
      includeWeekend ? const {1, 2, 3, 4, 5, 6, 7} : const {1, 2, 3, 4, 5};

  @override
  Widget build(BuildContext context) {
    final grid = buildOccupancyGrid(
      slots: _slots,
      week: week,
      maxPeriod: maxPeriod,
    );
    final windows = rankFreeWindows(
      findFreeWindows(
        slots: _slots,
        week: week,
        maxPeriod: maxPeriod,
        weekdays: _weekdays,
        minPeriods: minPeriods,
      ),
    );
    final ownersByCell = _ownersByCell();
    final longest = windows.isEmpty ? 0 : windows.first.periods;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Summary(
          ownerCount: columns.length,
          week: week,
          windowCount: windows.length,
          longest: longest,
        ),
        const SizedBox(height: 12),
        _GridCard(
          grid: grid,
          ownersByCell: ownersByCell,
          weekdays: _weekdays.toList()..sort(),
          maxPeriod: maxPeriod,
          periodStarts: periodStarts,
          onTapWindow: onTapWindow,
        ),
        const SizedBox(height: 12),
        _WindowList(
          windows: windows,
          maxPeriod: maxPeriod,
          periodStarts: periodStarts,
          onTapWindow: onTapWindow,
        ),
      ],
    );
  }

  Map<String, List<String>> _ownersByCell() {
    final map = <String, List<String>>{};
    for (final c in columns) {
      for (final s in c.slots) {
        if (!s.coversWeek(week)) continue;
        for (var p = s.startPeriod; p <= s.endPeriod; p++) {
          if (p < 1 || p > maxPeriod) continue;
          final key = '${s.weekday}|$p';
          final list = map.putIfAbsent(key, () => <String>[]);
          if (!list.contains(c.owner)) list.add(c.owner);
        }
      }
    }
    return map;
  }
}

class _Summary extends StatelessWidget {
  final int ownerCount;
  final int week;
  final int windowCount;
  final int longest;

  const _Summary({
    required this.ownerCount,
    required this.week,
    required this.windowCount,
    required this.longest,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = windowCount == 0
        ? '$ownerCount 个对照对象在第 $week 周没有共同空档'
        : '$ownerCount 个对照对象 · 第 $week 周 · $windowCount 段共同空闲（最长 $longest 节）';
    return Card(
      elevation: 0,
      shape: geCardShape(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            Icon(
              windowCount == 0 ? Icons.search_off : Icons.event_available,
              size: 22,
              color: windowCount == 0 ? scheme.error : AppColors.success(context),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GridCard extends StatelessWidget {
  final List<List<int>> grid;
  final Map<String, List<String>> ownersByCell;
  final List<int> weekdays;
  final int maxPeriod;
  final Map<int, String> periodStarts;
  final ValueChanged<FreeWindow>? onTapWindow;

  const _GridCard({
    required this.grid,
    required this.ownersByCell,
    required this.weekdays,
    required this.maxPeriod,
    required this.periodStarts,
    required this.onTapWindow,
  });

  static const _dayNames = ['一', '二', '三', '四', '五', '六', '日'];
  static const _periodLabelWidth = 44.0;
  static const _cellHeight = 34.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: geCardShape(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            geCardTitle(
              context,
              text: '第 $maxPeriod 节占用一览',
              accent: fp(context).cardAccent,
              trailing: const _Legend(),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const SizedBox(width: _periodLabelWidth),
                for (final d in weekdays)
                  Expanded(
                    child: Center(
                      child: Text(
                        '周${_dayNames[d - 1]}',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            for (var p = 1; p <= maxPeriod; p++)
              SizedBox(
                height: _cellHeight,
                child: Row(
                  children: [
                    SizedBox(
                      width: _periodLabelWidth,
                      child: Text(
                        periodStarts[p] == null
                            ? '$p'
                            : '$p ${periodStarts[p]}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    for (final d in weekdays)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(1),
                          child: _cell(context, d, p),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _cell(BuildContext context, int day, int period) {
    final scheme = Theme.of(context).colorScheme;
    final count = grid[day][period];
    final owners = ownersByCell['$day|$period'] ?? const <String>[];
    final free = count == 0;

    final cell = Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: free
            ? AppColors.successFill(context)
            : scheme.primary.withValues(
                alpha: 0.06 + 0.10 * (count - 1).clamp(0, 6),
              ),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: free
              ? AppColors.success(context).withValues(alpha: 0.25)
              : scheme.outlineVariant,
        ),
      ),
      child: Text(
        free ? '' : '$count',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: free ? AppColors.success(context) : scheme.primary,
          fontWeight: free ? null : FontWeight.w600,
        ),
      ),
    );

    return Tooltip(
      message: free
          ? '周${_dayNames[day - 1]}第 $period 节：全部空闲'
          : '周${_dayNames[day - 1]}第 $period 节：${owners.join('、')}',
      waitDuration: const Duration(milliseconds: 400),
      child: onTapWindow == null || !free
          ? cell
          : GestureDetector(
              onTap: () => onTapWindow!(
                FreeWindow(
                  weekday: day,
                  startPeriod: period,
                  endPeriod: period,
                  week: 0,
                ),
              ),
              child: cell,
            ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget dot(Color color, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: scheme.outlineVariant),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );

    return Row(
      children: [
        dot(AppColors.successFill(context), '全空'),
        const SizedBox(width: 8),
        dot(scheme.primary.withValues(alpha: 0.16), '有课（数字=几个对象有课）'),
      ],
    );
  }
}

class _WindowList extends StatelessWidget {
  final List<FreeWindow> windows;
  final int maxPeriod;
  final Map<int, String> periodStarts;
  final ValueChanged<FreeWindow>? onTapWindow;

  const _WindowList({
    required this.windows,
    required this.maxPeriod,
    required this.periodStarts,
    required this.onTapWindow,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (windows.isEmpty) {
      return Card(
        elevation: 0,
        shape: geCardShape(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 20,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '这些对象在这一周里没有共同空档。可以换个教学周、或把「最短连续节数」调到 1 节再试。',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final grouped = <int, List<FreeWindow>>{};
    for (final w in windows) {
      grouped.putIfAbsent(w.weekday, () => <FreeWindow>[]).add(w);
    }
    final days = grouped.keys.toList()..sort();

    return Card(
      elevation: 0,
      shape: geCardShape(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            geCardTitle(
              context,
              text: '空闲时段（${windows.length} 段，按从长到短）',
              accent: fp(context).cardAccent,
            ),
            const SizedBox(height: 4),
            for (final day in days) ...[
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 2),
                child: Text(
                  _weekdayName(day),
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              for (final w in grouped[day]!) _row(context, w),
            ],
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, FreeWindow w) {
    final scheme = Theme.of(context).colorScheme;
    final start = periodStarts[w.startPeriod];
    final end = periodStarts[w.endPeriod];
    final clock = (start == null || end == null) ? '' : ' · $start 起';
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.successFill(context),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: AppColors.success(context).withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          '${w.periods} 节',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppColors.success(context),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      title: Text(
        '第 ${w.startPeriod}-${w.endPeriod} 节$clock',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      subtitle: Text(
        '${w.label} · 第 ${w.week} 周',
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
      ),
      trailing: onTapWindow == null
          ? null
          : Icon(Icons.chevron_right, size: 18, color: scheme.onSurfaceVariant),
      onTap: onTapWindow == null ? null : () => onTapWindow!(w),
    );
  }

  static String _weekdayName(int day) {
    const names = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return (day >= 1 && day <= 7) ? names[day - 1] : '周?';
  }
}
