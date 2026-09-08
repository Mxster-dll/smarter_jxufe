/// 江西财经大学校历数据模型。
///
/// 逆向自 IMS 教务系统公开页：
/// `jwxt.jxufe.edu.cn/public/SchoolCalendar.jsp`（免登录，匿名 JSESSIONID）。
///
/// 学期（学段）模型（`xn` = 学年起始年，如 2025 表示 2025-2026 学年）：
/// - `xq = 0`：第一学期（秋季，9 月 ~ 次年 1 月）
/// - `xq = 1`：第二学期（春季，2/3 月 ~ 7 月）
/// - `xq = 2`：第二阶段（暑期，7 月 ~ 9 月）
library;

/// 一个教学周行：行首是教学周次，后面是周一 ~ 周日 7 个日期格。
class CalendarWeekRow {
  final String? weekNo;
  final List<int?> days;

  const CalendarWeekRow({this.weekNo, required this.days});

  /// 该行是否完全空白（无周次也无日期），渲染时可跳过。
  bool get isEmpty =>
      (weekNo == null || weekNo!.trim().isEmpty) &&
      days.every((d) => d == null);
}

/// 一个月的月历：周一起始的若干行。
class CalendarMonth {
  final int year;
  final int month;
  final List<CalendarWeekRow> rows;

  const CalendarMonth({
    required this.year,
    required this.month,
    required this.rows,
  });

  String get label =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';
}

/// 一份校历：标题、逐月月历与底部备注（学期/假期起止等）。
class SchoolCalendar {
  final String title;
  final int xn;
  final int xq;
  final List<CalendarMonth> months;
  final List<String> notes;

  const SchoolCalendar({
    required this.title,
    required this.xn,
    required this.xq,
    required this.months,
    required this.notes,
  });
}

/// 学段展示名：与 jwxt `xq_m` 参数对应。
String xqDisplayName(int xq) => switch (xq) {
      0 => '第一学期',
      1 => '第二学期',
      2 => '第二阶段',
      _ => '第$xq学段',
    };

/// 学段展示名缩写（用于紧凑切换条）。
String xqShortName(int xq) => switch (xq) {
      0 => '一学期',
      1 => '二学期',
      2 => '二阶段',
      _ => '学段$xq',
    };

/// 由学年起始年拼「2025-2026 学年」。
String xnDisplayName(int xn) => '$xn-${xn + 1}学年';

/// 由 (xn, xq) 拼校历标题（与教务页面大标题一致）。
String buildCalendarTitle(int xn, int xq) =>
    '江西财经大学${xnDisplayName(xn)}${xqDisplayName(xq)}校历';
