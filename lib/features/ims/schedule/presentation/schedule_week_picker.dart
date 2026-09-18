/// 教学周选择弹窗。
///
/// 用户 2026-09-16 裁定：「取消周数的左右按钮，但是点击周数，显示一个周数选择器，
/// 要可以输入周数 / 点击直接选择周数」——所以标题栏不再有 `‹ ›`，周数文字本身
/// 变成入口（见 `schedule_title_bar.dart` 的 `ScheduleWeekSwitcher`）。
///
/// 弹窗内三种选法：**输入周数**（数字键盘 + 「跳转」，超范围就地报错不关闭）、
/// **输入日期**（用户 2026-09-17：「我希望周数选择界面，除了输入周数外，还可以
/// 输入日期，跳到对应周数」—— 省年份的 `10-02` 与完整的 `2026-10-02` 都认，
/// 命中的那一周就是日期所在的教学周，周一到周日都算）与**周数格子**
/// （1..lastWeek 一次排开，点即选中并关闭；本周带圆点标记）。
/// 内容一律纯 `Column` / `Wrap`，**不放 viewport**（AGENTS §3.1：AlertDialog
/// 用 IntrinsicWidth 包裹内容，viewport 不支持 intrinsic 尺寸 → 弹窗永不渲染）。
///
/// ⚠ 按日期跳转**只在本学期可用**：日期 → 周次必须知道第 1 教学周的周一
/// （[showScheduleWeekPicker] 的 `mondayOf`），而它只在「正在看当下学期」时才有
/// （`schedule_screen.dart` 的 `_firstMonday`；历史学期按既有口径「周次无日期
/// 含义」给整学期视图）。`mondayOf == null` 时日期那一行整行不渲染。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 输入框（测试：键入周数后点「跳转」）。
const Key scheduleWeekInputKey = Key('scheduleWeekInput');

/// 「跳转」按钮。
const Key scheduleWeekSubmitKey = Key('scheduleWeekSubmit');

/// 日期输入框（测试：键入日期后点「按日期跳转」）。
const Key scheduleWeekDateInputKey = Key('scheduleWeekDateInput');

/// 「按日期跳转」按钮。
const Key scheduleWeekDateSubmitKey = Key('scheduleWeekDateSubmit');

/// 周数格子容器。
const Key scheduleWeekGridKey = Key('scheduleWeekGrid');

/// 单个周数格子。
Key scheduleWeekCellKey(int week) => Key('scheduleWeekCell-$week');

/// 标题栏里那个「第 N 周」按钮（点击开本弹窗）。
const Key scheduleWeekButtonKey = Key('scheduleWeekButton');

/// 第 [week] 周对应的日期范围文案（`09-21 ~ 09-27`；缺周一时返回 null）。
String? scheduleWeekRangeText(DateTime? monday) {
  if (monday == null) return null;
  String md(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  return '${md(monday)} ~ ${md(monday.add(const Duration(days: 6)))}';
}

/// 日期输入的解析结果：月 / 日必有，年可省（省了就在本学期里按月日匹配）。
typedef ScheduleDateInput = ({int month, int day, int? year});

/// 解析「日期」输入框里的文本；认不出返回 null（调用方据此报格式错）。
///
/// 认这些写法（分隔符 `-` `/` `.` 与 `年月日` 等价）：
/// `10-02`（省年份）、`2026-10-02`、`2026/10/2`、`2026.10.2`、`2026年10月2日`、
/// `20261002`。完整日期必须真的落在日历上（`02-30` 判错）。
///
/// **省年份是常规用法**：用户手边通常只有「10 月 2 日」这种信息，而学期会跨年
/// （261 学期第 1 周 = 09-07、第 20 周 = 次年 01-18），是哪一年由
/// [scheduleWeekOfDate] 在本学期区间里命中，不需要用户自己判断。
ScheduleDateInput? scheduleParseDateInput(String raw) {
  final normalized = raw
      .trim()
      .replaceAll('年', '-')
      .replaceAll('月', '-')
      .replaceAll('日', '')
      .replaceAll('/', '-')
      .replaceAll('.', '-')
      .replaceAll('－', '-');
  if (normalized.isEmpty) return null;

  final nums = normalized
      .split('-')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  int? year;
  int? month;
  int? day;
  if (nums.length == 1) {
    final only = nums.single;
    if (only.length != 8 || int.tryParse(only) == null) return null;
    year = int.parse(only.substring(0, 4));
    month = int.parse(only.substring(4, 6));
    day = int.parse(only.substring(6, 8));
  } else if (nums.length == 2) {
    month = int.tryParse(nums[0]);
    day = int.tryParse(nums[1]);
  } else if (nums.length == 3) {
    year = int.tryParse(nums[0]);
    month = int.tryParse(nums[1]);
    day = int.tryParse(nums[2]);
  } else {
    return null;
  }

  if (month == null || day == null) return null;
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  if (year != null) {
    if (year < 1900 || year > 2999) return null;
    final d = DateTime(year, month, day);
    if (d.year != year || d.month != month || d.day != day) return null;
  }
  return (month: month, day: day, year: year);
}

/// 日期命中的教学周（1 起）；不在 `1..lastWeek` 内返回 null。
///
/// 逐周拿 [mondayOf] 给出的周一（周一到周日 7 天都比一遍），**不假设**周一的
/// 算法、也不要求 `mondayOf` 能回答 1 号以外的东西；因此跨年学期用省年份的
/// `01-20` 也能命中。同一学期里同一个「月-日」不会出现两次（学期 ≤ 40 周），
/// 所以省年份在学期区间内不存在歧义。
int? scheduleWeekOfDate(
  ScheduleDateInput parts, {
  required int lastWeek,
  required DateTime? Function(int week) mondayOf,
}) {
  for (int w = 1; w <= lastWeek; w++) {
    final monday = mondayOf(w);
    if (monday == null) continue;
    final start = DateTime(monday.year, monday.month, monday.day);
    for (int i = 0; i < 7; i++) {
      final d = start.add(Duration(days: i));
      if (d.month != parts.month || d.day != parts.day) continue;
      if (parts.year != null && parts.year != d.year) continue;
      return w;
    }
  }
  return null;
}

/// [raw] 一步解析成周（等价于先 [scheduleParseDateInput] 再 [scheduleWeekOfDate]）。
///
/// 只回周数 —— 弹窗里「格式错」与「不在本学期范围内」是两句不同的提示，
/// 那边分开调用；本函数供测试与将来别的调用点用。
int? scheduleWeekOfDateText(
  String raw, {
  required int lastWeek,
  required DateTime? Function(int week) mondayOf,
}) {
  final parts = scheduleParseDateInput(raw);
  if (parts == null) return null;
  return scheduleWeekOfDate(parts, lastWeek: lastWeek, mondayOf: mondayOf);
}

/// 本学期日期范围文案（`09-07 ~ 01-10`，用于「不在本学期范围内」的提示）。
String? scheduleTermRangeText({
  required int lastWeek,
  required DateTime? Function(int week) mondayOf,
}) {
  final first = mondayOf(1);
  final last = mondayOf(lastWeek);
  if (first == null || last == null) return null;
  String md(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  return '${md(first)} ~ ${md(last.add(const Duration(days: 6)))}';
}

/// 弹出周数选择器；返回选中的周（1 起），取消返回 null。
///
/// [week] = 当前高亮周（整学期视图传本周或 1）；[lastWeek] = 本学期最后教学周
/// （来自 `resolveLastTeachingWeek`，**别写死 20**）；[mondayOf] 可选，既用于显示
/// 所选周的日期范围，也是**「按日期跳转」的唯一换算依据** —— 不给（历史学期 /
/// 还没拿到校历）时那一行整行不渲染。
Future<int?> showScheduleWeekPicker(
  BuildContext context, {
  required int week,
  required int lastWeek,
  int? currentWeek,
  DateTime? Function(int week)? mondayOf,
  bool compact = true,
}) {
  final safeLast = lastWeek < 1 ? 1 : lastWeek;
  final safeWeek = week.clamp(1, safeLast);
  return showDialog<int>(
    context: context,
    builder: (dialogContext) => _ScheduleWeekPickerDialog(
      week: safeWeek,
      lastWeek: safeLast,
      currentWeek: currentWeek,
      mondayOf: mondayOf,
      compact: compact,
    ),
  );
}

class _ScheduleWeekPickerDialog extends StatefulWidget {
  const _ScheduleWeekPickerDialog({
    required this.week,
    required this.lastWeek,
    required this.currentWeek,
    required this.mondayOf,
    required this.compact,
  });

  final int week;
  final int lastWeek;
  final int? currentWeek;
  final DateTime? Function(int week)? mondayOf;
  final bool compact;

  @override
  State<_ScheduleWeekPickerDialog> createState() =>
      _ScheduleWeekPickerDialogState();
}

class _ScheduleWeekPickerDialogState extends State<_ScheduleWeekPickerDialog> {
  late final TextEditingController _ctrl = TextEditingController();
  late final TextEditingController _dateCtrl = TextEditingController();

  /// 输入框里那串数字解析出来的周（合法才有值）——用于「第 X 周：日期范围」预览。
  int? _typed;
  bool _invalid = false;

  /// 日期输入框命中的周（合法才有值）与它自己的错误文案（null = 没错）。
  int? _dateWeek;
  String? _dateError;

  /// 本学期有没有日期（= 调用方给得出第 N 周的周一）。
  bool get _hasDates => widget.mondayOf != null;

  @override
  void dispose() {
    _ctrl.dispose();
    _dateCtrl.dispose();
    super.dispose();
  }

  void _onChanged(String raw) {
    final parsed = int.tryParse(raw.trim());
    final valid = parsed != null && parsed >= 1 && parsed <= widget.lastWeek;
    setState(() {
      _typed = valid ? parsed : null;
      _invalid = raw.trim().isNotEmpty && !valid;
    });
  }

  void _submit() {
    final parsed = int.tryParse(_ctrl.text.trim());
    if (parsed == null || parsed < 1 || parsed > widget.lastWeek) {
      setState(() => _invalid = true);
      return;
    }
    Navigator.of(context).pop(parsed);
  }

  /// 日期输入变化：解析 → 在本学期里找周 → 更新预览与错误文案。
  void _onDateChanged(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      setState(() {
        _dateWeek = null;
        _dateError = null;
      });
      return;
    }
    final mondayOf = widget.mondayOf;
    final parts = scheduleParseDateInput(text);
    if (parts == null) {
      setState(() {
        _dateWeek = null;
        _dateError = '认不出日期，如 10-02';
      });
      return;
    }
    final week = mondayOf == null
        ? null
        : scheduleWeekOfDate(
            parts,
            lastWeek: widget.lastWeek,
            mondayOf: mondayOf,
          );
    final termRange = mondayOf == null
        ? null
        : scheduleTermRangeText(
            lastWeek: widget.lastWeek,
            mondayOf: mondayOf,
          );
    setState(() {
      _dateWeek = week;
      _dateError = week != null
          ? null
          : '不在本学期范围内${termRange == null ? '' : '（$termRange）'}';
    });
  }

  void _submitDate() {
    final text = _dateCtrl.text.trim();
    if (text.isEmpty) {
      setState(() => _dateError = '请输入日期，如 10-02');
      return;
    }
    _onDateChanged(text);
    final week = _dateWeek;
    if (week == null) return; // 就地报错、不关闭
    Navigator.of(context).pop(week);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 预览优先跟着日期走（刚按日期查过），否则跟着周数输入框。
    final previewWeek = _dateWeek ?? _typed ?? widget.week;
    final range = scheduleWeekRangeText(widget.mondayOf?.call(previewWeek));
    final datePrefix = _dateWeek == null ? '' : '${_dateCtrl.text.trim()} → ';
    final current = widget.currentWeek;

    return AlertDialog(
      icon: const Icon(Icons.calendar_view_week),
      title: const Text('选择周数'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 132,
                child: TextField(
                  key: scheduleWeekInputKey,
                  controller: _ctrl,
                  autofocus: false,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: _onChanged,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: '输入周数',
                    hintText: '1 - ${widget.lastWeek}',
                    isDense: true,
                    border: const OutlineInputBorder(),
                    errorText: _invalid ? '超出 1 - ${widget.lastWeek}' : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: scheduleWeekSubmitKey,
                onPressed: _submit,
                child: const Text('跳转'),
              ),
            ],
          ),
          if (_hasDates) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                SizedBox(
                  width: 132,
                  child: TextField(
                    key: scheduleWeekDateInputKey,
                    controller: _dateCtrl,
                    autofocus: false,
                    keyboardType: TextInputType.datetime,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[0-9\-/.年月日]'),
                      ),
                    ],
                    onChanged: _onDateChanged,
                    onSubmitted: (_) => _submitDate(),
                    decoration: InputDecoration(
                      labelText: '输入日期',
                      hintText: '如 10-02',
                      isDense: true,
                      border: const OutlineInputBorder(),
                      errorText: _dateError,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  key: scheduleWeekDateSubmitKey,
                  onPressed: _submitDate,
                  child: const Text('按日期跳转'),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 8),
            Text(
              '（这个学期没有日期数据，只能按周数选择）',
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            '$datePrefix第 $previewWeek 周${range == null ? '' : '：$range'}'
            '${previewWeek == current ? '（本周）' : ''}',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: scheme.outlineVariant),
          const SizedBox(height: 12),
          Wrap(
            key: scheduleWeekGridKey,
            spacing: 6,
            runSpacing: 6,
            children: [
              for (int w = 1; w <= widget.lastWeek; w++)
                _WeekCell(
                  week: w,
                  selected: w == widget.week,
                  isCurrent: w == current,
                  compact: widget.compact,
                  onTap: () => Navigator.of(context).pop(w),
                ),
            ],
          ),
          if (current != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '圆点 = 本周（第 $current 周）',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      actions: [
        if (current != null)
          TextButton(
            onPressed: () => Navigator.of(context).pop(current),
            child: const Text('本周'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ],
    );
  }
}

/// 一个周数格子：数字 + （本周时）下方圆点。
class _WeekCell extends StatelessWidget {
  const _WeekCell({
    required this.week,
    required this.selected,
    required this.isCurrent,
    required this.compact,
    required this.onTap,
  });

  final int week;
  final bool selected;
  final bool isCurrent;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = selected ? scheme.onPrimary : scheme.onSurface;
    return Material(
      color: selected ? scheme.primary : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        key: scheduleWeekCellKey(week),
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: SizedBox(
          width: compact ? 42 : 46,
          height: compact ? 36 : 40,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$week',
                style: TextStyle(
                  fontSize: compact ? 13 : 14,
                  fontWeight: FontWeight.w600,
                  color: fg,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (isCurrent)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: selected ? scheme.onPrimary : scheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
