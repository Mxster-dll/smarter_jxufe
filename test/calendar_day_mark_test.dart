import 'package:flutter_test/flutter_test.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/calendar_day_mark.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/school_calendar.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/wxcal_semester.dart';

/// 校历「假/班」角标判定引擎测试。
///
/// 数据用 **term 261（2026-2027 第一学期）真实官方安排**（来源：
/// `lib/features/school_calendar/data/wxcal_offline_data.dart` 第 19 条，
/// 抓取自小程序 getSchoolCalendar 接口），断言与网页原型逐日核对过的结果一致。
void main() {
  WxCalEvent ev(String from, String to, String text, [String? category]) =>
      WxCalEvent(
        from: DateTime.parse(from),
        to: DateTime.parse(to),
        text: text,
        category: category,
      );

  /// 252 学期只保留「暑假开始」，用于推导跨学期的暑假区间。
  final term252 = WxSemesterArrangement(
    id: 18,
    term: '252',
    start: DateTime.parse('2026-03-02'),
    end: DateTime.parse('2026-07-05'),
    style: WxArrangementStyle.lines,
    events: [ev('2026-07-06', '2026-07-06', '暑假开始。')],
  );

  /// 261 学期全部官方事件（三节：教职员工 / 本科生 / 研究生）。
  final term261 = WxSemesterArrangement(
    id: 19,
    term: '261',
    start: DateTime.parse('2026-09-07'),
    end: DateTime.parse('2027-01-16'),
    style: WxArrangementStyle.table,
    events: [
      ev('2026-09-02', '2026-09-02', '教职工上班', '教职员工'),
      ev('2026-09-25', '2026-09-27', '中秋节放假', '教职员工'),
      ev('2026-10-01', '2026-10-07', '国庆节放假', '教职员工'),
      ev('2026-10-10', '2026-10-10', '补第4周周五的课', '教职员工'),
      ev('2027-01-01', '2027-01-01', '元旦放假', '教职员工'),
      ev('2027-01-16', '2027-01-16', '寒假开始', '教职员工'),
      ev('2026-09-05', '2026-09-06', '新生报到注册', '本 科 生'),
      ev('2026-09-07', '2026-09-21', '新生军训', '本 科 生'),
      ev('2026-09-13', '2026-09-13', '老生报到注册', '本 科 生'),
      ev('2026-09-14', '2026-09-14', '老生开始上课', '本 科 生'),
      ev('2026-09-22', '2026-09-24', '新生入学、专业教育', '本 科 生'),
      ev('2026-09-25', '2026-09-27', '中秋节放假', '本 科 生'),
      ev('2026-09-28', '2026-09-28', '新生开始上课', '本 科 生'),
      ev('2026-10-01', '2026-10-07', '国庆节放假', '本 科 生'),
      ev('2026-10-10', '2026-10-10', '补第4周周五的课', '本 科 生'),
      ev('2026-10-29', '2026-10-31', '运动会', '本 科 生'),
      ev('2026-11-07', '2026-11-08', '期中考试', '本 科 生'),
      ev('2026-12-31', '2026-12-31', '学生课程结束（当天上课）', '本 科 生'),
      ev('2027-01-01', '2027-01-01', '元旦放假（以学校放假安排通知为准）', '本 科 生'),
      ev('2027-01-04', '2027-01-15', '期末复习与课程考核', '本 科 生'),
      ev('2026-09-13', '2026-09-13', '老生、新生报到注册', '研 究 生'),
      ev('2026-09-14', '2026-09-14', '老生、新生开始上课', '研 究 生'),
      ev('2026-09-25', '2026-09-27', '中秋节放假', '研 究 生'),
      ev('2026-10-01', '2026-10-07', '国庆节放假', '研 究 生'),
      ev('2026-10-10', '2026-10-10', '补第4周周五的课', '研 究 生'),
      ev('2026-12-28', '2026-12-28', '课程结束（当天上课）', '研 究 生'),
      ev('2026-12-29', '2027-01-08', '期末复习与课程考核', '研 究 生'),
    ],
  );

  CalendarMarkIndex build261({CalendarMarkOptions? options}) =>
      CalendarMarkIndex.build(
        terms: [term252, term261],
        options:
            options ??
            const CalendarMarkOptions(enrollYear: 2026, trainLevel: '本科'),
      );

  String badgeOf(
    CalendarMarkIndex index,
    String date, {
    CalendarDayKind? kind,
  }) => index.markOf(DateTime.parse(date), calendarKind: kind).badge;

  group('term 261 真实数据 · 逐日角标', () {
    final index = build261();

    // (日期, 期望角标) —— 与网页原型 DOM 核对结果一致
    const expected = <String, String>{
      '2026-09-01': '假', // 暑假（252「暑假开始」起）
      '2026-09-04': '假',
      '2026-09-06': '假',
      '2026-09-07': '军', // 新生军训（本人 2026 级）
      '2026-09-13': '军', // 军训 + 老生报到注册（军训优先）
      '2026-09-21': '军',
      '2026-09-22': '教', // 新生入学、专业教育
      '2026-09-24': '教',
      '2026-09-25': '假', // 中秋节
      '2026-09-26': '假',
      '2026-09-27': '假',
      '2026-09-28': '', // 新生开始上课（常态描述不打角标）
      '2026-09-30': '',
      '2026-10-01': '假', // 国庆节
      '2026-10-05': '假',
      '2026-10-07': '假',
      '2026-10-08': '',
      '2026-10-10': '班', // 补第4周周五的课（周六）
      '2026-10-11': '',
      '2026-10-29': '运', // 运动会
      '2026-10-31': '运',
      '2026-11-01': '',
      '2026-11-07': '考', // 期中考试
      '2026-11-08': '考',
      '2026-12-31': '', // 本科生：研究生专属考核期（12/29~1/8）已按人群过滤
      '2027-01-01': '假', // 元旦
      '2027-01-03': '', // 同上（本科生期末复习 1/4 才开始）
      '2027-01-15': '考', // 本科生期末复习与课程考核（1/4~1/15）
      '2027-01-16': '假', // 寒假开始
      '2027-01-31': '假', // 寒假整段
    };

    expected.forEach((date, badge) {
      test('$date → 「$badge」', () {
        expect(badgeOf(index, date), badge);
      });
    });

    test('放假事件在三个分节重复出现时只保留一条（优先学生分节）', () {
      final mark = index.markOf(DateTime.parse('2026-10-01'));
      expect(mark.events.length, 1);
      expect(mark.events.single.text, '国庆节放假');
      expect(mark.events.single.category?.trim(), '本 科 生');
      expect(mark.kind, CalendarMarkKind.holiday);
    });

    test('无角标的常态事件仍能在详情里看到', () {
      final mark = index.markOf(DateTime.parse('2026-09-28'));
      expect(mark.hasBadge, isFalse);
      expect(mark.events.map((e) => e.text), contains('新生开始上课'));
    });
  });

  group('军训角标开关', () {
    test('非新生默认不显示军训', () {
      final index = build261(
        options: const CalendarMarkOptions(enrollYear: 2025, trainLevel: '本科'),
      );
      expect(badgeOf(index, '2026-09-07'), '');
    });

    test('设置里打开「非新生也显示军训」后显示', () {
      final index = build261(
        options: const CalendarMarkOptions(
          enrollYear: 2025,
          trainLevel: '本科',
          alwaysShowMilitary: true,
        ),
      );
      expect(badgeOf(index, '2026-09-07'), '军');
    });

    test('入学年 == 学年起始年（2026 级）时显示军训', () {
      final index = build261(
        options: const CalendarMarkOptions(enrollYear: 2026, trainLevel: '本科'),
      );
      expect(badgeOf(index, '2026-09-07'), '军');
    });
  });

  group('人群过滤开关', () {
    test('本科生不显示研究生专属的期末考核', () {
      final index = build261(
        options: const CalendarMarkOptions(enrollYear: 2025, trainLevel: '本科'),
      );
      expect(badgeOf(index, '2026-12-31'), '');
    });

    test('研究生显示研究生专属的期末考核', () {
      final index = build261(
        options: const CalendarMarkOptions(
          enrollYear: 2025,
          trainLevel: '硕士研究生',
        ),
      );
      expect(badgeOf(index, '2026-12-31'), '考');
    });

    test('关掉过滤后所有分节事件都显示', () {
      final index = build261(
        options: const CalendarMarkOptions(
          enrollYear: 2025,
          trainLevel: '本科',
          filterByCategory: false,
        ),
      );
      expect(badgeOf(index, '2026-12-31'), '考');
    });

    test('层次未知（学籍未同步）时不过滤', () {
      final index = build261(
        options: const CalendarMarkOptions(enrollYear: null, trainLevel: null),
      );
      expect(badgeOf(index, '2026-12-31'), '考');
    });

    test('放假 / 补课不受人群过滤影响', () {
      final index = build261(
        options: const CalendarMarkOptions(enrollYear: 2025, trainLevel: '本科'),
      );
      expect(badgeOf(index, '2026-10-01'), '假');
      expect(badgeOf(index, '2026-10-10'), '班');
    });
  });

  group('角标映射与噪声清理', () {
    final index = CalendarMarkIndex.build(
      terms: [
        WxSemesterArrangement(
          id: 1,
          term: '999',
          start: DateTime.parse('2026-01-01'),
          end: DateTime.parse('2026-12-31'),
          style: WxArrangementStyle.lines,
          events: [
            ev('2026-03-02', '2026-03-02', '教职工上班'),
            ev('2026-03-03', '2026-03-03', '老生开始上课'),
            ev('2026-03-04', '2026-03-04', '学生课程结束（当天上课）'),
            ev('2026-03-05', '2026-03-05', '本科生补（缓）考'),
          ],
        ),
      ],
    );

    test('「教职工上班」不产生「班」角标（学生不上课）', () {
      expect(badgeOf(index, '2026-03-02'), '');
    });

    test('「开始上课 / 课程结束 / 补缓考」不打角标', () {
      expect(badgeOf(index, '2026-03-03'), '');
      expect(badgeOf(index, '2026-03-04'), '');
      expect(badgeOf(index, '2026-03-05'), '');
    });
  });

  group('教务校历兜底（仅工作日 nonday → 假）', () {
    final empty = CalendarMarkIndex.empty();

    test('工作日标 nonday → 假', () {
      expect(badgeOf(empty, '2027-01-19', kind: CalendarDayKind.nonday), '假');
    });

    test('周末标 workday 不产生「班」（校历该侧不可信）', () {
      expect(badgeOf(empty, '2027-01-23', kind: CalendarDayKind.workday), '');
    });

    test('周末 nonday 不算额外放假（本就是周末）', () {
      expect(badgeOf(empty, '2026-10-03', kind: CalendarDayKind.nonday), '');
    });

    test('官方数据在场时优先于校历标注', () {
      final index = build261();
      // 校历把 10/05 标成 workday（要上课），官方安排是国庆放假 → 以官方为准。
      expect(badgeOf(index, '2026-10-05', kind: CalendarDayKind.workday), '假');
    });
  });

  group('角标风格', () {
    test('三种风格名称与持久化名一致，未知名回落推荐值', () {
      expect(
        CalendarBadgeStyle.fromName('cornerTag'),
        CalendarBadgeStyle.cornerTag,
      );
      expect(
        CalendarBadgeStyle.fromName('filledCell'),
        CalendarBadgeStyle.filledCell,
      );
      expect(
        CalendarBadgeStyle.fromName('不存在'),
        CalendarBadgeStyle.underNumber,
      );
      expect(CalendarBadgeStyle.fromName(null), CalendarBadgeStyle.underNumber);
      expect(CalendarBadgeStyle.cornerTag.isTall, isFalse);
      expect(CalendarBadgeStyle.underNumber.isTall, isTrue);
    });
  });
}
