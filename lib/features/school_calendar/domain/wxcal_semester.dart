/// 智慧江财小程序「校历」源数据模型。
///
/// 接口：POST https://wxcourse.jxufe.cn/interface/api/interface/getSchoolCalendar
/// 每学期一条记录，`remark` 为官方逐日安排（放假/补课/运动会/期中/军训/报到等），
/// 近两年为行式/表格式，更早年份为整段文字（paragraph）。
///
/// `term` 编码 = 学年起始年后两位 + 段码（1=秋季第一学期 9~1 月，2=春季第二学期
/// 2~7 月），与 IMS 校历的 (xn, xq) 对应：`term == (xn-2000) + (xq == 0 ? '1' : '2')`。
/// 小程序校历无暑期段（IMS xq = 2 无对应数据）。
library;

/// remark 排版风格。
enum WxArrangementStyle {
  /// remark 为空（'null'）。
  empty,

  /// <p> 短行逐条（如 2026 春第二学期）。
  lines,

  /// <table> 按 教职员工/本科生/研究生 分节（如 2026 秋第一学期）。
  table,

  /// 整段文字版（2017 ~ 2025 秋，一、二、三… 通知文体），保留原文段落。
  paragraph,
}

/// 一条官方安排：日期区间 + 说明文字。
class WxCalEvent {
  final DateTime from;
  final DateTime to;

  /// 说明文字，如「中秋节放假」「新生军训」。
  final String text;

  /// 分节类别（教职员工/本科生/研究生…），行式旧版为 null。
  final String? category;

  const WxCalEvent({
    required this.from,
    required this.to,
    required this.text,
    this.category,
  });

  /// 展示用日期区间文本，如「9月25日-27日」「9月2日」。
  String get rangeText {
    String f(int d) => '$d月${from.day}日';
    if (from == to) return f(from.month);
    final sameMonth = from.month == to.month;
    final y = from.year != to.year ? '${to.year}年' : '';
    if (sameMonth) return '${from.month}月${from.day}日-${to.day}日';
    return '${from.month}月${from.day}日-$y${to.month}月${to.day}日';
  }
}

/// 一个学期的官方安排（小程序校历数据源）。
class WxSemesterArrangement {
  final int id;
  final String term;
  final DateTime start;
  final DateTime end;
  final WxArrangementStyle style;
  final List<WxCalEvent> events;
  final List<String> notes;

  const WxSemesterArrangement({
    required this.id,
    required this.term,
    required this.start,
    required this.end,
    required this.style,
    this.events = const [],
    this.notes = const [],
  });

  /// term → 学年起始年（'261' → 2026）。
  int get xn => 2000 + int.parse(term.substring(0, 2));

  /// term → IMS 学段（'261' 末位 1 → xq 0；'252' 末位 2 → xq 1）。
  int get xq => term.endsWith('1') ? 0 : 1;

  bool matches({required int xn, required int xq}) => this.xn == xn && this.xq == xq;
}

/// 由 (xn, xq) 求小程序 term 编码（与小程序数据源匹配用）。
String wxTermCode(int xn, int xq) =>
    '${(xn - 2000).toString().padLeft(2, '0')}${xq == 0 ? 1 : 2}';
