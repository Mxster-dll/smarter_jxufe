import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/school_calendar/data/anti_corruption/school_calendar_html_parser.dart';
import 'package:smarter_jxufe/features/school_calendar/data/providers/school_calendar_providers.dart';
import 'package:smarter_jxufe/features/school_calendar/data/providers/school_time_providers.dart';
import 'package:smarter_jxufe/features/school_calendar/data/school_calendar_exception.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/school_calendar.dart';

/// 学校时间表的 provider —— 用**真实抓取的教务校历页**（`test/fixtures/_cal_*.html`）
/// 走真解析器，断言「学年 / 假期」都能从页面攒出来。
///
/// 真页面与学段对应（fixture 里的备注原文）：
/// - `_cal_xq0.html` → 2025 学年第一学段：学期 2025-09-01 ~ 2026-01-15，
///   假期 2026-01-16 ~ 2026-03-01
/// - `_cal_xq1.html` → 2025 学年第二学段：2026-03-02 ~ 2026-07-05
/// - `_cal_xq2.html` → 2025 学年第二阶段：2026-07-06 ~ 2026-07-10，
///   假期 2026-07-11 ~ 2026-09-06
/// - `_cal_261_xq0.html` → **2026 学年**第一学段：2026-09-07 ~ 2027-01-15，
///   假期 2027-01-16 ~ 2027-01-19（占位）
void main() {
  final parser = SchoolCalendarHtmlParser();

  SchoolCalendar real(String file, int xn, int xq) => parser.parse(
        File('test/fixtures/$file').readAsStringSync(),
        xn: xn,
        xq: xq,
      );

  /// 2025 学年三学段 + 2026 学年第一学段（真页面）。
  Map<({int xn, int xq}), SchoolCalendar> realPages() => {
        (xn: 2025, xq: 0): real('_cal_xq0.html', 2025, 0),
        (xn: 2025, xq: 1): real('_cal_xq1.html', 2025, 1),
        (xn: 2025, xq: 2): real('_cal_xq2.html', 2025, 2),
        (xn: 2026, xq: 0): real('_cal_261_xq0.html', 2026, 0),
      };

  /// 未公布学年（教务返回 723 字节空壳 → 解析器抛「未找到月份表」）。
  SchoolCalendar emptyShell() => throw SchoolCalendarException(
        '校历 HTML 解析失败：未找到月份表（共 0 张表）',
      );

  ProviderContainer makeContainer({
    Map<({int xn, int xq}), SchoolCalendar>? pages,
    Set<({int xn, int xq})> unpublished = const {},
  }) {
    final map = pages ?? realPages();
    return ProviderContainer(
      overrides: [
        for (final entry in map.entries)
          schoolCalendarProvider(entry.key).overrideWith(
                (ref) async => unpublished.contains(entry.key)
                    ? emptyShell()
                    : entry.value,
              ),
        // 表里没写的学段（如 2026 学年第二学段）→ 一律按未公布处理，
        // 免得测试悄悄走真网络。
        for (final xn in const [2025, 2026, 2027])
          for (final xq in const [0, 1, 2])
            if (!map.containsKey((xn: xn, xq: xq)))
              schoolCalendarProvider((xn: xn, xq: xq))
                  .overrideWith((ref) async => emptyShell()),
      ],
    );
  }

  test('真页面：2025 学年 = 2025-09-01 ~ 2026-09-06', () async {
    final container = makeContainer();
    addTearDown(container.dispose);
    final table = await container.read(schoolTimeTableProvider(2025).future);

    expect(table.terms.length, 4);
    final year = table.yearOf(2025);
    expect(year.firstDay, DateTime(2025, 9, 1));
    expect(year.lastDay, DateTime(2026, 9, 6));
    expect(year.isComplete, isTrue);
    expect(year.contains(DateTime(2026, 1, 20)), isTrue);

    final breaks = table.breaksOf(2025);
    expect(breaks.map((b) => b.label), ['寒假', '暑假']);
    expect(breaks.first.start, DateTime(2026, 1, 16));
    expect(breaks.first.end, DateTime(2026, 3, 1));
    expect(breaks.first.days, 45);
    expect(breaks.last.start, DateTime(2026, 7, 11));
    expect(breaks.last.end, DateTime(2026, 9, 6));
    expect(breaks.last.days, 58);
    expect(breaks.every((b) => b.certain), isTrue);
  });

  test('真页面：学校时间表的三个便捷 provider 一致', () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    final year = await container.read(schoolYearProvider(2025).future);
    expect(year.rangeText, '2025-09-01 ~ 2026-09-06');

    final breaks = await container.read(schoolBreaksProvider(2025).future);
    expect(breaks.length, 2);
    expect(breaks.first.certain, isTrue);
  });

  test('下学年第一学段未公布 → 该学年结束日留 null', () async {
    final container = makeContainer(
      pages: {
        (xn: 2026, xq: 0): real('_cal_261_xq0.html', 2026, 0),
      },
    );
    addTearDown(container.dispose);
    final table = await container.read(schoolTimeTableProvider(2026).future);

    final year = table.yearOf(2026);
    expect(year.firstDay, DateTime(2026, 9, 7));
    expect(year.lastDay, isNull);
    expect(year.isComplete, isFalse);
    expect(year.rangeText, '2026-09-07 起（下学年校历未公布）');

    // 寒假只有 4 天（教务占位）→ 结束日 null；暑假结束日也 null。
    final breaks = table.breaksOf(2026);
    expect(breaks.length, 1); // 第二阶段页面未公布 → 连暑假开始日都还没有
    expect(breaks.single.label, '寒假');
    expect(breaks.single.certain, isFalse);
    expect(breaks.single.end, isNull);
  });

  test('2026 学年三学段齐、2027 未公布 → 寒假判占位、暑假结束日 null', () async {
    final container = makeContainer(
      pages: {
        (xn: 2026, xq: 0): real('_cal_261_xq0.html', 2026, 0),
        (xn: 2026, xq: 1): _cal(2026, 1, const [
          '学期开始日期：2027-01-20',
          '学期结束日期：2027-07-05',
        ]),
        (xn: 2026, xq: 2): _cal(2026, 2, const [
          '学期开始日期：2027-07-06',
          '学期结束日期：2027-07-31',
          '假期开始日期：2027-08-01',
          '假期结束日期：2027-09-30',
        ]),
      },
    );
    addTearDown(container.dispose);
    final breaks = await container.read(schoolBreaksProvider(2026).future);

    expect(breaks.length, 2);
    final winter = breaks.first;
    expect(winter.label, '寒假');
    expect(winter.start, DateTime(2027, 1, 16));
    expect(winter.certain, isFalse); // 4 天 = 占位
    expect(winter.end, isNull);

    final summer = breaks.last;
    expect(summer.start, DateTime(2027, 8, 1));
    expect(summer.certain, isFalse); // 下学年未公布
    expect(summer.end, isNull);
  });

  test('某一学段失败不影响其它学段（第二学段缺失 → 寒假结束日 null）', () async {
    final container = makeContainer(
      pages: {
        (xn: 2025, xq: 0): real('_cal_xq0.html', 2025, 0),
        (xn: 2025, xq: 1): real('_cal_xq1.html', 2025, 1),
        (xn: 2025, xq: 2): real('_cal_xq2.html', 2025, 2),
        (xn: 2026, xq: 0): real('_cal_261_xq0.html', 2026, 0),
      },
      unpublished: {(xn: 2025, xq: 1)},
    );
    addTearDown(container.dispose);
    final table = await container.read(schoolTimeTableProvider(2025).future);

    expect(table.terms.length, 3); // 少了一个学段，但表仍建得起来
    expect(table.yearOf(2025).lastDay, DateTime(2026, 9, 6));
    final winter = table.breaksOf(2025).first;
    expect(winter.start, DateTime(2026, 1, 16));
    expect(winter.end, isNull);
    expect(winter.certain, isFalse);
  });

  test('四个学段全未公布 → 空表，不抛', () async {
    final container = makeContainer(pages: const {});
    addTearDown(container.dispose);
    final table = await container.read(schoolTimeTableProvider(2026).future);

    expect(table.terms, isEmpty);
    expect(table.yearOf(2026).isKnown, isFalse);
    expect(table.breaksOf(2026), isEmpty);
  });
}

SchoolCalendar _cal(int xn, int xq, List<String> notes) => SchoolCalendar(
      title: '',
      xn: xn,
      xq: xq,
      months: const [],
      notes: notes,
    );
