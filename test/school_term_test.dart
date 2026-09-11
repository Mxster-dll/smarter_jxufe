// 「当下学期」判定（课表 / 校历 / 实况窗共用口径）单测。
//
// 用户口径（2026-09 裁定）：
// - 学期进行中（含开学前第 0 周）→ 该学期，界面自行给「整学期视图」；
// - 两学期之间的假期 → **下一学期**（假期里看的是即将开学的课表，
//   没出来则提示「课表还没出来」）；
// - 校历快照覆盖范围之外 → 月份经验规则兜底。
//
// 回归目标（本次 bug）：`2026-09` 曾因用「入学年 + 月份」判学期而显示
// `2025-2026 第一学期`；`2026-01` / `2027-01` 又因月份规则跨年错位。

import 'package:flutter_test/flutter_test.dart';
import 'package:smarter_jxufe/features/school_calendar/data/wxcal_repository.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/school_term.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/teaching_week.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/wxcal_semester.dart';

({int xn, int xq}) at(String day, {List<WxSemesterArrangement> terms = const []}) =>
    currentSchoolTerm(DateTime.parse(day), terms: terms);

WxSemesterArrangement term(String code, String start, String end) =>
    WxSemesterArrangement(
      id: int.parse(code),
      term: code,
      start: DateTime.parse(start),
      end: DateTime.parse(end),
      style: WxArrangementStyle.lines,
    );

void main() {
  // 内置离线快照（覆盖 171 2017-09-02 ~ 261 2027-01-16）。
  final real = wxcalOfflineToDomain();

  group('校历区间优先 · 真实离线快照', () {
    test('261 学期区间内一律判 2026-2027 第一学期', () {
      for (final day in [
        '2026-09-07', // 学期 start（新生军训周 / 老生未开课）
        '2026-09-10', // 开学前（第 0 周）
        '2026-09-14', // 老生开始上课（第 1 教学周）
        '2026-09-28', // 新生开始上课
        '2026-10-15',
        '2026-12-31',
        '2027-01-10', // ← 跨年边界：旧月份规则会错判成 2027-2028 第一学期
        '2027-01-16', // 学期 end（寒假开始）
      ]) {
        expect(
          at(day, terms: real),
          (xn: 2026, xq: 0),
          reason: '$day 应判为 2026-2027 学年第一学期（261）',
        );
      }
    });

    test('251 学期区间内判 2025-2026 第一学期（入学年 ≠ 学期学年）', () {
      // 旧实现用学籍入学年 2025 + 月份 → 2026-01 会被算成 2026-2027 第一学期。
      expect(at('2026-01-10', terms: real), (xn: 2025, xq: 0));
      expect(at('2025-12-31', terms: real), (xn: 2025, xq: 0));
    });

    test('252 学期区间内判 2025-2026 第二学期', () {
      expect(at('2026-03-02', terms: real), (xn: 2025, xq: 1));
      expect(at('2026-06-18', terms: real), (xn: 2025, xq: 1));
      expect(at('2026-07-05', terms: real), (xn: 2025, xq: 1));
    });

    test('寒假空档（2026-01-15 ~ 2026-03-01）判下一学期 2025-2026 第二学期', () {
      for (final day in ['2026-01-15', '2026-02-01', '2026-03-01']) {
        expect(at(day, terms: real), (xn: 2025, xq: 1), reason: day);
      }
    });

    test('暑假空档（2026-07-06 ~ 2026-09-06）判下一学期 2026-2027 第一学期', () {
      for (final day in ['2026-07-06', '2026-08-20', '2026-09-06']) {
        expect(at(day, terms: real), (xn: 2026, xq: 0), reason: day);
      }
    });

    test('快照覆盖范围之外退回月份规则（不会永远停在最后一个学期）', () {
      // 早于 171（2017-09-02）：1 月上旬 → 上年第一学期
      expect(at('2017-01-01', terms: real), (xn: 2016, xq: 0));
      // 晚于 261（2027-01-16）：寒假下半月 / 春季 / 暑假
      expect(at('2027-01-20', terms: real), (xn: 2026, xq: 1));
      expect(at('2027-03-15', terms: real), (xn: 2026, xq: 1));
      expect(at('2027-06-01', terms: real), (xn: 2026, xq: 1));
      expect(at('2027-08-20', terms: real), (xn: 2027, xq: 0));
      expect(at('2027-10-01', terms: real), (xn: 2027, xq: 0));
    });
  });

  group('合成校历 / 边界', () {
    final two = [
      term('261', '2026-09-01', '2027-01-10'),
      term('262', '2027-02-20', '2027-07-01'),
    ];

    test('命中区间取该学期', () {
      expect(at('2026-11-11', terms: two), (xn: 2026, xq: 0));
      expect(at('2027-03-01', terms: two), (xn: 2026, xq: 1));
    });

    test('区间空档取最早的未来学期', () {
      expect(at('2027-01-11', terms: two), (xn: 2026, xq: 1));
      expect(at('2027-02-19', terms: two), (xn: 2026, xq: 1));
    });

    test('区间重叠时取 start 更晚的那个', () {
      final overlap = [
        term('261', '2026-09-01', '2027-01-31'),
        term('262', '2027-01-10', '2027-07-01'),
      ];
      expect(at('2027-01-20', terms: overlap), (xn: 2026, xq: 1));
    });

    test('覆盖范围之外 / 无校历 → 月份兜底', () {
      final old = [term('171', '2017-09-02', '2017-12-22')];
      expect(at('2026-09-20', terms: old), (xn: 2026, xq: 0));
      expect(at('2026-03-05', terms: old), (xn: 2025, xq: 1));
      expect(at('2026-08-01'), (xn: 2026, xq: 0));
      expect(at('2026-09-20'), (xn: 2026, xq: 0));
      expect(at('2026-01-10'), (xn: 2025, xq: 0));
      expect(at('2026-01-20'), (xn: 2025, xq: 1));
      expect(at('2026-05-20'), (xn: 2025, xq: 1));
    });
  });

  group('与教学周口径协同（课表页据此决定周视图 / 整学期视图）', () {
    test('开学后：学期命中且 week ≥ 1 → 周视图', () {
      final tw = resolveTeachingWeek(DateTime.parse('2026-10-15'), terms: real);
      expect(tw, isNotNull);
      expect(tw!.term.matches(xn: 2026, xq: 0), isTrue);
      expect(tw.week, greaterThanOrEqualTo(1));
      expect(tw.firstMonday, DateTime.parse('2026-09-14'));
    });

    test('开学前（261 的 09-07 ~ 09-13）：仍是 261 但 week = 0 → 整学期视图', () {
      final tw = resolveTeachingWeek(DateTime.parse('2026-09-10'), terms: real);
      expect(tw, isNotNull);
      expect(tw!.term.matches(xn: 2026, xq: 0), isTrue);
      expect(tw.week, 0);
    });

    test('假期里 resolveTeachingWeek 给的是「上一学期」→ 界面必须用学期匹配守卫', () {
      // 暑假：currentSchoolTerm = 261（下学期），teachingWeek 仍停在 252。
      expect(at('2026-08-20', terms: real), (xn: 2026, xq: 0));
      final tw = resolveTeachingWeek(DateTime.parse('2026-08-20'), terms: real);
      expect(tw, isNotNull);
      expect(tw!.term.matches(xn: 2026, xq: 0), isFalse);
      expect(tw.term.matches(xn: 2025, xq: 1), isTrue);
    });
  });

  test('schoolTermLabel', () {
    expect(schoolTermLabel(2026, 0), '2026-2027 学年第一学期');
    expect(schoolTermLabel(2026, 1), '2026-2027 学年第二学期');
    expect(schoolTermLabel(2025, 1), '2025-2026 学年第二学期');
  });
}
