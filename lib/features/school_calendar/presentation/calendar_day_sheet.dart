/// 校历角标小件 +「点某一天看当日安排」底部详情弹层。
library;

import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/calendar_day_mark.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/school_calendar.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/wxcal_semester.dart';

/// 角标配色：假 = 红，班 = 绿，其它事件 = 蓝灰。
Color calendarMarkColor(CalendarMarkKind? kind) => switch (kind) {
  CalendarMarkKind.holiday => FeaturePalette.calendarHoliday,
  CalendarMarkKind.makeup => FeaturePalette.calendarMakeup,
  CalendarMarkKind.event => FeaturePalette.calendarEvent,
  null => FeaturePalette.classCancelled,
};

/// 日期格角标（三种风格由 [CalendarBadgeStyle] 决定，行高由调用方保证）。
Widget calendarBadge(CalendarDayMark mark, CalendarBadgeStyle style) {
  if (!mark.hasBadge) return const SizedBox.shrink();
  final color = calendarMarkColor(mark.kind);
  final corner = style == CalendarBadgeStyle.cornerTag;
  return Container(
    padding: corner
        ? const EdgeInsets.symmetric(horizontal: 3, vertical: 1)
        : const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(corner ? 3 : 4),
    ),
    child: Text(
      mark.badge,
      style: TextStyle(
        fontSize: corner ? 8 : 9,
        height: 1.05,
        fontWeight: FontWeight.w600,
        color: color,
      ),
    ),
  );
}

/// 弹出某一天的安排详情。
Future<void> showCalendarDaySheet(
  BuildContext context, {
  required CalendarDayMark mark,
  String? termTitle,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => _CalendarDaySheet(mark: mark, termTitle: termTitle),
  );
}

class _CalendarDaySheet extends StatelessWidget {
  final CalendarDayMark mark;
  final String? termTitle;

  const _CalendarDaySheet({required this.mark, this.termTitle});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final day = mark.day;
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${day.year} 年 ${day.month} 月 ${day.day} 日',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                weekdays[day.weekday - 1],
                style: textTheme.bodySmall?.copyWith(color: Colors.black54),
              ),
              if (mark.hasBadge) ...[
                const Spacer(),
                calendarBadge(mark, CalendarBadgeStyle.underNumber),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            mark.hasBadge ? '${mark.badge} · ${mark.reason}' : mark.reason,
            style: textTheme.bodySmall?.copyWith(
              color: mark.hasBadge
                  ? calendarMarkColor(mark.kind)
                  : Colors.black54,
              fontWeight: mark.hasBadge ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          const SizedBox(height: 14),
          if (mark.events.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '该日无官方安排',
                style: textTheme.bodyMedium?.copyWith(color: Colors.black45),
              ),
            )
          else
            for (final event in mark.events) _EventTile(event: event),
          const SizedBox(height: 4),
          const Divider(height: 18),
          Text(
            '教务校历标注：${switch (mark.calendarKind) {
              CalendarDayKind.workday => 'workday（认为要上课）',
              CalendarDayKind.nonday => 'nonday（认为不上课）',
              null => '（老学期页面无此标注）',
            }}',
            style: textTheme.bodySmall?.copyWith(color: Colors.black54),
          ),
          if (termTitle != null && termTitle!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '校历：$termTitle',
              style: textTheme.bodySmall?.copyWith(color: Colors.black54),
            ),
          ],
        ],
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  final WxCalEvent event;

  const _EventTile({required this.event});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final category = event.category?.trim();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            event.text,
            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            event.rangeText,
            style: textTheme.bodySmall?.copyWith(color: Colors.black54),
          ),
          if (category != null && category.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: scheme.primary.withValues(alpha: 0.35),
                  width: 0.6,
                ),
              ),
              child: Text(
                category,
                style: textTheme.bodySmall?.copyWith(
                  fontSize: 10,
                  color: scheme.primary.withValues(alpha: 0.9),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
