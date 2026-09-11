/// 校历「假 / 班」角标判定引擎（纯逻辑，无 Flutter 依赖）。
///
/// ## 数据源优先级（用户 2026-09-11 拍板）
/// 1. **官方安排**（`WxSemesterArrangement.events`，小程序校历，GUID 实时 / 内置快照兜底）
///    —— 放假、补课、运动会、考试、军训等逐日事件；
/// 2. **教务校历兜底**（`CalendarDayKind`，jwxt 校历 HTML 的 `workday|nonday`）
///    —— 仅用于「工作日却标 nonday → 放假」这一侧（补寒暑假）。
///
/// ## 为什么校历只能兜底（真实抓取实测）
/// - 2026-10-01~07 国庆假期，教务校历整段标 `workday`（照搬会把假期显示成上课日）；
/// - 2027-01-19~31 寒假期间整段标 `workday`（含 4 个周末），其备注「假期结束日期：
///   2027-01-19」即脏数据。
/// - 反向：校历与官方安排对**学期起止**一致，故「工作日 nonday」一侧可信。
///
/// ## 已排除的噪声（正式实现口径）
/// 「教职工上班」「老生开始上课」「学生课程结束（当天上课）」等常态描述不打角标，
/// 仅在点开当日详情时列出——否则 9/2、12/31 会冒出无意义的角标。
library;

import 'package:smarter_jxufe/features/school_calendar/domain/school_calendar.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/wxcal_semester.dart';

/// 角标风格（校历页「显示设置」中由用户切换）。
enum CalendarBadgeStyle {
  /// 数字下方小字「假/班」。
  underNumber('数字下方小字'),

  /// 格子右上角迷你胶囊（行高不变）。
  cornerTag('右上角角标'),

  /// 整格淡色底 + 数字下方小字。
  filledCell('整格淡色底');

  const CalendarBadgeStyle(this.label);

  final String label;

  /// 是否需要在数字下方再排一行角标（决定日期行高 32 / 40）。
  bool get isTall => this != CalendarBadgeStyle.cornerTag;

  static CalendarBadgeStyle fromName(String? name) => values.firstWhere(
    (e) => e.name == name,
    orElse: () => CalendarBadgeStyle.underNumber,
  );
}

/// 标记类型（决定角标配色）。
enum CalendarMarkKind {
  /// 放假（法定节假日、寒暑假）。
  holiday,

  /// 补课 / 调休上班。
  makeup,

  /// 其它官方事件（运动会、考试、军训、报到…）。
  event,
}

/// 某一天的角标与当日官方安排。
class CalendarDayMark {
  final DateTime day;

  /// 角标类型；`null` 表示该日不打角标（仍可能有 [events]）。
  final CalendarMarkKind? kind;

  /// 角标文字：假 / 班 / 运 / 考 / 军 / 到 / 教；空串 = 无角标。
  final String badge;

  /// 角标对应的说明文字（如「国庆节放假」「补第4周周五的课」）。
  final String label;

  /// 当日全部官方安排（已按人群过滤、已去重）。
  final List<WxCalEvent> events;

  /// 教务校历对该日的原始标注（可能为 null：老学期页面无该标注）。
  final CalendarDayKind? calendarKind;

  /// 判定依据（展示在当日详情里，便于核对）。
  final String reason;

  const CalendarDayMark({
    required this.day,
    required this.kind,
    required this.badge,
    required this.label,
    required this.events,
    required this.calendarKind,
    required this.reason,
  });

  bool get hasBadge => badge.isNotEmpty;

  /// 是否放假（含寒暑假）。
  bool get isHoliday => kind == CalendarMarkKind.holiday;

  /// 是否补课 / 调休上班。
  bool get isMakeup => kind == CalendarMarkKind.makeup;
}

/// 「看这份日历的人」——由学籍派生的两项判定条件。
///
/// 单独抽出成窄模型（而不是直接用 `StudentInfo`）：判定只需入学年与培养层次两项，
/// 且测试可脱离学籍数据直接构造。
class CalendarViewer {
  /// 入学年（如 2026）；未知为 null。
  final int? enrollYear;

  /// 培养层次原文（学籍 `<pycc>`），如「本科」「硕士研究生」；未知为 null。
  final String? trainLevel;

  const CalendarViewer({this.enrollYear, this.trainLevel});

  /// 学籍不可用时的占位（不过滤事件、军训只按入学年判断 → 不显示）。
  static const unknown = CalendarViewer();

  bool get hasInfo => enrollYear != null || (trainLevel?.isNotEmpty ?? false);

  /// 展示用文本，如「2026 级 · 本科」。
  String get label {
    final parts = <String>[
      if (enrollYear != null) '$enrollYear 级',
      if (trainLevel != null && trainLevel!.trim().isNotEmpty)
        trainLevel!.trim(),
    ];
    return parts.isEmpty ? '未获取到学籍' : parts.join(' · ');
  }
}

/// 判定所需的外部条件（用户设置 + 学籍）。
class CalendarMarkOptions {
  /// 学籍入学年（`StudentInfo.enrollYear`，如 2025）；未知为 null。
  final int? enrollYear;

  /// 非新生也显示军训角标（设置项，默认关：军训只对入学年显示）。
  final bool alwaysShowMilitary;

  /// 按本人培养层次过滤分节事件（设置项，默认开）。
  final bool filterByCategory;

  /// 学籍「培养层次」原文（`StudentInfo.trainLevel`）；未知为 null。
  final String? trainLevel;

  const CalendarMarkOptions({
    this.enrollYear,
    this.alwaysShowMilitary = false,
    this.filterByCategory = true,
    this.trainLevel,
  });

  /// 归一化后的本人层次：`本科` / `研究生` / `null`（未知 → 不过滤）。
  ///
  /// ⚠ 校历分节字段带字间空格（「本 科 生」「研 究 生」），必须先去空白再比对。
  String? get viewerGroup {
    final t = (trainLevel ?? '').replaceAll(_ws, '');
    if (t.isEmpty) return null;
    if (t.contains('本科') || t.contains('专科')) return '本科';
    if (t.contains('研究生') || t.contains('硕士') || t.contains('博士')) {
      return '研究生';
    }
    return null;
  }

  /// 本人是否该校历学期的「新生」（入学年 == 学年起始年）。
  bool isFreshmanOf(int xn) => enrollYear != null && enrollYear == xn;

  static final _ws = RegExp(r'\s+');
}

/// 「日期 → 角标」索引：由全部学期官方安排一次性构建，界面按月查询。
class CalendarMarkIndex {
  final List<_Span> _spans;
  final CalendarMarkOptions options;

  CalendarMarkIndex._(this._spans, this.options);

  /// 无任何数据的空索引（仍可做校历兜底判定）。
  factory CalendarMarkIndex.empty([CalendarMarkOptions? options]) =>
      CalendarMarkIndex._(const [], options ?? const CalendarMarkOptions());

  /// 由全部学期官方安排构建。
  ///
  /// [terms] 通常传 `wxArrangementsProvider` 的结果（含全部历史学期与当前学期）。
  factory CalendarMarkIndex.build({
    required List<WxSemesterArrangement> terms,
    CalendarMarkOptions options = const CalendarMarkOptions(),
  }) {
    final spans = <_Span>[];

    for (final term in terms) {
      for (final e in term.events) {
        final text = e.text;
        if (_isHolidayText(text)) {
          spans.add(
            _Span(
              e.from,
              e.to,
              text,
              e.category,
              kind: CalendarMarkKind.holiday,
              badge: '假',
            ),
          );
        } else if (_isMakeupText(text)) {
          spans.add(
            _Span(
              e.from,
              e.to,
              text,
              e.category,
              kind: CalendarMarkKind.makeup,
              badge: '班',
            ),
          );
        } else {
          final badge = _badgeOf(text);
          // 军训：只在「本人入学年 == 该学期学年」时显示（可用设置强制显示）。
          final militaryOk =
              !text.contains('军训') ||
              options.alwaysShowMilitary ||
              options.isFreshmanOf(term.xn);
          final categoryOk = _categoryAllows(e.category, options);
          spans.add(
            _Span(
              e.from,
              e.to,
              text,
              e.category,
              kind: badge == null ? null : CalendarMarkKind.event,
              badge: (badge != null && militaryOk && categoryOk) ? badge : null,
            ),
          );
        }
      }
    }

    // 寒 / 暑假整段：由「寒假开始 / 暑假开始」事件起，到下一学期开始前一天。
    final sorted = [...terms]..sort((a, b) => a.start.compareTo(b.start));
    for (var i = 0; i < sorted.length; i++) {
      final term = sorted[i];
      for (final e in term.events) {
        if (!_isBreakStart(e.text)) continue;
        final nextStart = i + 1 < sorted.length ? sorted[i + 1].start : null;
        final end = nextStart != null
            ? nextStart.subtract(const Duration(days: 1))
            : e.from.add(const Duration(days: 45));
        if (end.isBefore(e.from)) continue;
        spans.add(
          _Span(
            e.from,
            end,
            e.text.replaceAll('开始', '').replaceAll('。', ''),
            e.category,
            kind: CalendarMarkKind.holiday,
            badge: '假',
            isBreak: true,
          ),
        );
      }
    }

    return CalendarMarkIndex._(_dedupe(spans), options);
  }

  /// 取 [day] 当天的标记。
  ///
  /// [calendarKind] 为该日在教务校历上的原始标注（来自 `CalendarWeekRow.kindAt`），
  /// 用于官方数据缺席时的兜底判定。
  CalendarDayMark markOf(DateTime day, {CalendarDayKind? calendarKind}) {
    final d = DateTime(day.year, day.month, day.day);
    final today = <_Span>[
      for (final s in _spans)
        if (s.covers(d)) s,
    ];

    CalendarDayMark build(_Span s) => CalendarDayMark(
      day: d,
      kind: s.kind,
      badge: s.badge ?? '',
      label: s.text,
      events: [for (final x in today) x.toEvent()],
      calendarKind: calendarKind,
      reason: switch (s.kind) {
        CalendarMarkKind.holiday => '官方放假：${s.text}',
        CalendarMarkKind.makeup => '官方补课 / 上班：${s.text}',
        _ => '其它官方事件：${s.text}',
      },
    );

    for (final s in today) {
      if (s.kind == CalendarMarkKind.holiday && s.badge != null) {
        return build(s);
      }
    }
    for (final s in today) {
      if (s.kind == CalendarMarkKind.makeup && s.badge != null) return build(s);
    }
    for (final s in today) {
      if (s.badge != null) return build(s);
    }

    final events = [for (final x in today) x.toEvent()];
    final noBadge = CalendarDayMark(
      day: d,
      kind: null,
      badge: '',
      label: '',
      events: events,
      calendarKind: calendarKind,
      reason: events.isEmpty
          ? (d.weekday >= 6 ? '周末' : '普通教学日')
          : '官方事件（不打角标）：${events.map((e) => e.text).join('、')}',
    );

    // 官方数据缺席时的校历兜底：工作日却标 nonday → 放假（寒暑假）。
    if (events.isEmpty &&
        calendarKind == CalendarDayKind.nonday &&
        d.weekday < 6) {
      return CalendarDayMark(
        day: d,
        kind: CalendarMarkKind.holiday,
        badge: '假',
        label: '学期外假期',
        events: const [],
        calendarKind: calendarKind,
        reason: '校历兜底：工作日标 nonday（学期外 / 假期）',
      );
    }
    return noBadge;
  }

  /// 事件文字 → 角标文字；无需角标的事件返回 null。
  static String? _badgeOf(String text) {
    if (text.contains('运动会')) return '运';
    if (text.contains('考试') || text.contains('考核') || text.contains('复习')) {
      return '考';
    }
    if (text.contains('军训')) return '军';
    if (text.contains('报到') || text.contains('注册')) return '到';
    if (text.contains('入学') || text.contains('教育')) return '教';
    return null;
  }

  static bool _isHolidayText(String t) => t.contains('放假') || t.contains('假期');

  static bool _isBreakStart(String t) =>
      t.contains('寒假开始') || t.contains('暑假开始');

  /// 补课 / 调休。⚠「教职工上班」是老师上班，学生不上课，必须排除。
  static bool _isMakeupText(String t) =>
      RegExp(r'补.*课|调休').hasMatch(t) && !t.contains('教职工');

  /// 分节事件是否属于本人（仅作用于「其它事件」；放假与补课对所有人生效）。
  static bool _categoryAllows(String? category, CalendarMarkOptions options) {
    if (!options.filterByCategory) return true;
    final c = (category ?? '').replaceAll(RegExp(r'\s+'), '');
    if (c.isEmpty) return true; // 旧版校历无分节 → 全量
    if (c.contains('教职员工') || c.contains('教职工')) return false;
    final viewer = options.viewerGroup;
    if (viewer == null) return true; // 学籍层次未知 → 不过滤
    if (c.contains('本科生')) return viewer == '本科';
    if (c.contains('研究生')) return viewer == '研究生';
    return true; // 「全校」「全体学生」等
  }

  /// 同一事件会在「教职员工 / 本科生 / 研究生」三节重复，按 日期+文字 去重，
  /// 并优先保留学生分节（避免详情里挂「教职员工」标签）。
  static List<_Span> _dedupe(List<_Span> spans) {
    final map = <String, _Span>{};
    for (final s in spans) {
      final key =
          '${s.from.toIso8601String()}|${s.to.toIso8601String()}|${s.text}';
      final prev = map[key];
      if (prev == null) {
        map[key] = s;
      } else if (_isStaff(prev.category) && !_isStaff(s.category)) {
        map[key] = s;
      }
    }
    return map.values.toList();
  }

  static bool _isStaff(String? c) =>
      (c ?? '').replaceAll(RegExp(r'\s+'), '').contains('教职');
}

/// 一条官方安排区间（内部结构）。
class _Span {
  final DateTime from;
  final DateTime to;
  final String text;
  final String? category;
  final CalendarMarkKind? kind;
  final String? badge;
  final bool isBreak;

  const _Span(
    this.from,
    this.to,
    this.text,
    this.category, {
    this.kind,
    this.badge,
    this.isBreak = false,
  });

  bool covers(DateTime d) => !d.isBefore(from) && !d.isAfter(to);

  WxCalEvent toEvent() => WxCalEvent(
    from: from,
    to: to,
    // 假期整段其实是「开始日」事件推导而来，标注清楚避免误解。
    text: isBreak ? '$text（假期）' : text,
    category: category,
  );
}
