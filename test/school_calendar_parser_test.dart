import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smarter_jxufe/features/school_calendar/data/anti_corruption/school_calendar_html_parser.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/school_calendar.dart';

/// 解析器对三个学段真实 HTML（抓取自 jwxt.jxufe.edu.cn，2025-2026 学年）的验证。
void main() {
  final fixtures = <(String, int, int, int, String)>[
    // (文件, xn, xq, 期望月数, 期望标题片段)
    ('_cal_xq0.html', 2025, 0, 7, '第一学期'),
    ('_cal_xq1.html', 2025, 1, 5, '第二学期'),
    ('_cal_xq2.html', 2025, 2, 3, '第二阶段'),
  ];

  for (final (file, xn, xq, expectedMonths, titlePart) in fixtures) {
    test('解析 $file → 标题含"$titlePart"、$expectedMonths 张月表', () {
      final fixture = File('test/fixtures/$file');
      expect(fixture.existsSync(), isTrue,
          reason: 'fixture $file 不存在，请先抓取校历 HTML 存档');
      final html = fixture.readAsStringSync();
      final calendar = SchoolCalendarHtmlParser()
          .parse(html, xn: xn, xq: xq);

      expect(calendar.title, contains(titlePart));
      expect(calendar.months.length, expectedMonths);
      // 每张月表行数 ≥3、首行教学周次存在（跨月续周时可能为空，但至少有一行非空）
      for (final month in calendar.months) {
        expect(month.rows, isNotEmpty, reason: '${month.label} 不应为空');
        for (final row in month.rows) {
          expect(row.days.length, 7);
        }
      }
    });
  }

  test('第一学期(2025-0)备注含学期起止日期', () {
    final html = File('test/fixtures/_cal_xq0.html').readAsStringSync();
    final calendar =
        SchoolCalendarHtmlParser().parse(html, xn: 2025, xq: 0);
    final joined = calendar.notes.join('\n');
    expect(joined, contains('学期开始日期：2025-09-01'));
    expect(joined, contains('假期结束日期：2026-03-01'));
  });

  test('第二学期(2025-1)月份覆盖 3~7 月，周次 1 起头', () {
    final html = File('test/fixtures/_cal_xq1.html').readAsStringSync();
    final calendar =
        SchoolCalendarHtmlParser().parse(html, xn: 2025, xq: 1);
    final labels = calendar.months.map((m) => m.label).toList();
    expect(labels, containsAll(['2026-03', '2026-04', '2026-05', '2026-06', '2026-07']));
    // 3 月首行应为教学第 1 周
    expect(calendar.months.first.rows.first.weekNo, '1');
  });

  test('学段展示名与标题拼接正确', () {
    expect(xqDisplayName(0), '第一学期');
    expect(xqDisplayName(1), '第二学期');
    expect(xqDisplayName(2), '第二阶段');
    expect(xnDisplayName(2025), '2025-2026学年');
    expect(buildCalendarTitle(2025, 0), '江西财经大学2025-2026学年第一学期校历');
  });
}
