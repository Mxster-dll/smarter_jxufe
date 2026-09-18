/// 通用「年 / 月 / 日」三块宫格日期选择器（用户 2026-09-17 定制）。
///
/// 与 Material 的 `showDatePicker`（月历 + 需先点日历图标切年）不同：本选择器
/// **一个弹窗里同时给出三块宫格** —— 年份、月份、日期，点日期即完成。宽屏三列
/// 并排、窄屏纵向堆叠（`gridDatePickerColumnsBreakpoint`）。不限于材料库：
/// 任何需要选日期的页面都可 `showGridDatePicker(...)`。
///
/// 实现约束（AGENTS §3.1）：`AlertDialog` 恒用 `IntrinsicWidth`，内部不能放
/// viewport 组件 —— 这里用自建 `Dialog` + `SingleChildScrollView` + `Wrap`
/// （宫格 = 自身换行的 `Wrap`，不是 `GridView`）。
library;

import 'package:flutter/material.dart';

/// 宽屏（≥ 该宽度）时三块宫格并排，否则纵向堆叠。
const double gridDatePickerColumnsBreakpoint = 520;

/// 弹窗根 Key（测试用）。
const Key gridDatePickerKey = Key('gridDatePicker');

/// 年份 / 月份 / 日期格子的 Key（测试用）。
Key gridDateYearKey(int year) => Key('gridDateYear-$year');
Key gridDateMonthKey(int month) => Key('gridDateMonth-$month');
Key gridDateDayKey(int day) => Key('gridDateDay-$day');

/// 「日期」块的星期表头 Key（0 = 周一 … 6 = 周日）。
Key gridDateWeekdayKey(int index) => Key('gridDateWeekday-$index');

/// 日期块顶部显示的星期（用户 2026-09-17：「日期选择部分，要在顶部显示周一到
/// 周日，并让日期对齐」）—— 恒为周一起始。
const List<String> gridDateWeekdayLabels = [
  '周一',
  '周二',
  '周三',
  '周四',
  '周五',
  '周六',
  '周日',
];

/// 该月 1 号前面应留几个空格（周一 = 0）——日期对齐的唯一定义。
int gridDateMonthOffset(int year, int month) =>
    DateTime(year, month, 1).weekday - DateTime.monday;

/// 日期格子边长（7 列 × 该宽度 + 间距 = 日期块宽度）。
const double gridDateDayCellWidth = 32;
const double gridDateDayCellHeight = 32;
const double gridDateDayCellGap = 2;

/// 该年该月的天数（月份 1~12）。
int gridDaysInMonth(int year, int month) {
  if (month == 2) {
    final leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
    return leap ? 29 : 28;
  }
  return const [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1];
}

/// 把日期夹到 `[first, last]` 区间内（只保留年月日）。
DateTime gridClampDate(DateTime value, DateTime first, DateTime last) {
  final d = DateTime(value.year, value.month, value.day);
  if (d.isBefore(DateTime(first.year, first.month, first.day))) {
    return DateTime(first.year, first.month, first.day);
  }
  if (d.isAfter(DateTime(last.year, last.month, last.day))) {
    return DateTime(last.year, last.month, last.day);
  }
  return d;
}

/// 弹出「年 / 月 / 日」三宫格选择器；取消返回 null。
Future<DateTime?> showGridDatePicker(
  BuildContext context, {
  DateTime? initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  String title = '选择日期',
  String? helpText,
}) {
  return showDialog<DateTime>(
    context: context,
    builder: (_) => GridDatePickerDialog(
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      title: title,
      helpText: helpText,
    ),
  );
}

/// 三宫格日期选择弹窗本体（独立成类便于单测直接 pump）。
class GridDatePickerDialog extends StatefulWidget {
  const GridDatePickerDialog({
    super.key,
    this.initialDate,
    required this.firstDate,
    required this.lastDate,
    this.title = '选择日期',
    this.helpText,
  });

  final DateTime? initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final String title;
  final String? helpText;

  @override
  State<GridDatePickerDialog> createState() => _GridDatePickerDialogState();
}

class _GridDatePickerDialogState extends State<GridDatePickerDialog> {
  late int _year;
  late int _month;
  late int _day;

  DateTime get _first => DateTime(
    widget.firstDate.year,
    widget.firstDate.month,
    widget.firstDate.day,
  );
  DateTime get _last => DateTime(
    widget.lastDate.year,
    widget.lastDate.month,
    widget.lastDate.day,
  );

  @override
  void initState() {
    super.initState();
    final start = gridClampDate(
      widget.initialDate ?? widget.lastDate,
      widget.firstDate,
      widget.lastDate,
    );
    _year = start.year;
    _month = start.month;
    _day = start.day;
  }

  /// 当「日」在选择新月份后越界时收敛到该月最后一天（或区间上界）。
  void _syncDay() {
    final maxDay = gridDaysInMonth(_year, _month);
    if (_day > maxDay) _day = maxDay;
    final picked = DateTime(_year, _month, _day);
    if (picked.isBefore(_first)) {
      _day = _first.day;
    } else if (picked.isAfter(_last)) {
      _day = _last.day;
    }
    if (_day > maxDay) _day = maxDay;
  }

  bool get _todayInRange {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return !today.isBefore(_first) && !today.isAfter(_last);
  }

  bool _dayEnabled(int day) {
    final d = DateTime(_year, _month, day);
    return !d.isBefore(_first) && !d.isAfter(_last);
  }

  bool _monthEnabled(int month) {
    final start = DateTime(_year, month, 1);
    final end = DateTime(_year, month, gridDaysInMonth(_year, month));
    return !end.isBefore(_first) && !start.isAfter(_last);
  }

  String get _preview =>
      '$_year-${_month.toString().padLeft(2, '0')}-'
      '${_day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final years = [
      for (var y = _first.year; y <= _last.year; y++) y,
    ];
    final maxDay = gridDaysInMonth(_year, _month);

    return Dialog(
      key: gridDatePickerKey,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 860,
          maxHeight: MediaQuery.sizeOf(context).height * 0.84,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.helpText == null
                              ? '已选 $_preview'
                              : '${widget.helpText} · 已选 $_preview',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: scheme.outlineVariant),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                child: LayoutBuilder(
                  builder: (context, c) {
                    final yearCol = _section(
                      context,
                      label: '年份',
                      children: [
                        for (final y in years)
                          _cell(
                            context,
                            key: gridDateYearKey(y),
                            text: '$y',
                            selected: y == _year,
                            width: 64,
                            onTap: () => setState(() {
                              _year = y;
                              _syncDay();
                            }),
                          ),
                      ],
                    );
                    final monthCol = _section(
                      context,
                      label: '月份',
                      children: [
                        for (var m = 1; m <= 12; m++)
                          _cell(
                            context,
                            key: gridDateMonthKey(m),
                            text: '$m',
                            selected: m == _month,
                            width: 44,
                            enabled: _monthEnabled(m),
                            onTap: () => setState(() {
                              _month = m;
                              _syncDay();
                            }),
                          ),
                      ],
                    );
                    final dayCol = _section(
                      context,
                      label: '日期',
                      wrap: false,
                      children: [_dayCalendar(context, maxDay)],
                    );
                    if (c.maxWidth >= gridDatePickerColumnsBreakpoint) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: yearCol),
                          const SizedBox(width: 14),
                          Expanded(child: monthCol),
                          const SizedBox(width: 14),
                          Expanded(child: dayCol),
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        yearCol,
                        const SizedBox(height: 14),
                        monthCol,
                        const SizedBox(height: 14),
                        dayCol,
                      ],
                    );
                  },
                ),
              ),
            ),
            Divider(height: 1, color: scheme.outlineVariant),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
              child: Row(
                children: [
                  TextButton(
                    onPressed: _todayInRange
                        ? () {
                            final now = DateTime.now();
                            Navigator.of(context).pop(
                              DateTime(now.year, now.month, now.day),
                            );
                          }
                        : null,
                    child: const Text('今天'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 「日期」块：顶部周一到周日的表头 + 按星期对齐的 7 列月历格。
  ///
  /// 用户 2026-09-17：「日期选择部分，要在顶部显示周一到周日，并让日期对齐」
  /// —— 1 号按 `gridDateMonthOffset` 落到对应星期列（周一为第一列）。
  Widget _dayCalendar(BuildContext context, int maxDay) {
    final scheme = Theme.of(context).colorScheme;
    final offset = gridDateMonthOffset(_year, _month);
    // 前导空格 + 本月日期，再补齐到整行。
    final slots = <Widget?>[
      for (var i = 0; i < offset; i++) null,
      for (var d = 1; d <= maxDay; d++) _dayCell(context, d),
    ];
    while (slots.length % 7 != 0) {
      slots.add(null);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var i = 0; i < gridDateWeekdayLabels.length; i++)
              SizedBox(
                key: gridDateWeekdayKey(i),
                // 与日期格同宽（格宽 + 一格间距）→ 表头与日期严格同列
                // （日期格两侧各留 gap/2，故其「槽宽」= 格宽 + gap）。
                width: gridDateDayCellWidth + gridDateDayCellGap,
                height: 18,
                child: Center(
                  child: Text(
                    gridDateWeekdayLabels[i],
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        for (var row = 0; row < slots.length ~/ 7; row++)
          Row(
            children: [
              for (var col = 0; col < 7; col++)
                Padding(
                  padding: const EdgeInsets.all(gridDateDayCellGap / 2),
                  child:
                      slots[row * 7 + col] ??
                      const SizedBox(
                        width: gridDateDayCellWidth,
                        height: gridDateDayCellHeight,
                      ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _dayCell(BuildContext context, int day) => _cell(
    context,
    key: gridDateDayKey(day),
    text: '$day',
    selected: day == _day,
    width: gridDateDayCellWidth,
    height: gridDateDayCellHeight,
    enabled: _dayEnabled(day),
    onTap: () => setState(() {
      _day = day;
      _confirm();
    }),
  );

  void _confirm() {
    Navigator.of(context).pop(DateTime(_year, _month, _day));
  }

  Widget _section(
    BuildContext context, {
    required String label,
    required List<Widget> children,
    bool wrap = true,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        if (wrap)
          Wrap(spacing: 8, runSpacing: 8, children: children)
        else
          ...children,
      ],
    );
  }

  Widget _cell(
    BuildContext context, {
    required Key key,
    required String text,
    required bool selected,
    required VoidCallback onTap,
    double width = 44,
    double height = 36,
    bool enabled = true,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final bg = selected
        ? scheme.primary
        : scheme.surfaceContainerHighest;
    final fg = selected
        ? scheme.onPrimary
        : (enabled ? scheme.onSurface : scheme.onSurfaceVariant);
    return Opacity(
      opacity: enabled ? 1 : 0.38,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          key: key,
          borderRadius: BorderRadius.circular(8),
          onTap: enabled ? onTap : null,
          child: SizedBox(
            width: width,
            height: height,
            child: Center(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: fg,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
