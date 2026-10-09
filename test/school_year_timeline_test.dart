/// 学年时间线（**一根单轴**）的守卫。
///
/// 用户 2026-10-09 裁定：校历页顶部那张卡改成一根单轴时间线（`/fluent-design`），
/// 于是「段」从展示层收上来成了纯数据（`domain/school_time_timeline.dart`）：
///
/// - 轴 = 学年窗口（`schoolTimelineAxis`，拿不到校历退固定 09-01~08-31）；
/// - 段 = 学段 + 假期，**按时间排序**，长度 ∝ 真实天数（含首含尾）；
/// - **待公布** = 段的 `end == null`（起点已知、终点未知）→ 画虚线，且**不猜日期**；
/// - 整段未公布（连起点都没有）→ 不画（编不出位置）。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/school_time.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/school_time_timeline.dart';
import 'package:smarter_jxufe/features/school_calendar/presentation/widgets/school_year_timeline.dart';

/// 一个学段（教务页备注的四行日期）。
SchoolTermDates term(
  int xn,
  int xq, {
  DateTime? start,
  DateTime? end,
  DateTime? breakStart,
  DateTime? breakEnd,
}) => SchoolTermDates(
  xn: xn,
  xq: xq,
  termStart: start,
  termEnd: end,
  breakStart: breakStart,
  breakEnd: breakEnd,
);

/// 2025 学年（已排满 · 实测台账）。
SchoolTimeTable fullTable() => SchoolTimeTable([
  term(2025, 0,
      start: DateTime(2025, 9, 1),
      end: DateTime(2026, 1, 15),
      breakStart: DateTime(2026, 1, 16)),
  term(2025, 1,
      start: DateTime(2026, 3, 2),
      end: DateTime(2026, 7, 5),
      breakStart: DateTime(2026, 7, 6),
      breakEnd: DateTime(2026, 7, 10)),
  term(2025, 2, start: DateTime(2026, 7, 6), end: DateTime(2026, 7, 10)),
  // 下学年第一学段：决定本学年最后一天（2026-09-06）
  term(2026, 0, start: DateTime(2026, 9, 7)),
]);

/// 2026 学年（只公布了第一学段 + 4 天占位寒假）。
SchoolTimeTable partialTable() => SchoolTimeTable([
  term(2026, 0,
      start: DateTime(2026, 9, 7),
      end: DateTime(2027, 1, 15),
      breakStart: DateTime(2027, 1, 16),
      // 教务把寒假串成 01-16 ~ 01-19（4 天）—— 占位值，识别后 end 置空
      breakEnd: DateTime(2027, 1, 19)),
  term(2026, 1, start: DateTime(2027, 1, 20)),
]);

Widget harness(Widget child, {double width = 360}) => MaterialApp(
  theme: appLightTheme,
  home: Scaffold(
    body: Center(
      child: SizedBox(width: width, child: child),
    ),
  ),
);

/// 已排满学年的时间线（多段一起画的那种）。
Widget _timeline(SchoolTimeTable table) => SchoolYearTimeline(
  axis: schoolTimelineAxis(table, 2025),
  segments: schoolTimelineSegments(table, 2025),
);

void main() {
  group('段的口径（纯函数）', () {
    test('已排满的学年：三段在校 + 两段放假，按时间排序', () {
      final segs = schoolTimelineSegments(fullTable(), 2025);
      expect(segs.map((s) => s.name).toList(), [
        '第一学期',
        '寒假',
        '第二学期',
        '第二阶段',
        '暑假',
      ]);
      expect(segs.map((s) => s.kind).toList(), [
        SchoolTimelineKind.term,
        SchoolTimelineKind.holiday,
        SchoolTimelineKind.term,
        SchoolTimelineKind.term,
        SchoolTimelineKind.holiday,
      ]);
      expect(segs.every((s) => !s.isOpen), isTrue, reason: '这一年教务全公布了');
      // 长度 = 含首含尾的天数（与教务文案同口径）
      expect(segs[0].days, 137); // 2025-09-01 ~ 2026-01-15
      expect(segs[1].days, 45); // 2026-01-16 ~ 03-01
      expect(segs[4].days, 58); // 2026-07-11 ~ 09-06
    });

    test('占位链：寒假判为占位（4 天 < 14 天下限）→ 它后面的学段一律不画', () {
      final segs = schoolTimelineSegments(partialTable(), 2026);
      expect(segs.map((s) => s.name).toList(), ['第一学期', '寒假']);
      final winter = segs.last;
      expect(winter.start, DateTime(2027, 1, 16));
      expect(winter.end, isNull, reason: '占位跨度不采信，结束日留空');
      expect(winter.isOpen, isTrue);
      expect(winter.note, '待公布');
      expect(winter.rangeText, '01-16 起');
      expect(
        segs.any((s) => s.name == '第二学期'),
        isFalse,
        reason: '教务把第二学段编成 2027-01-20 起（寒假只给 4 天就是它的破绽）——'
            '时间线上长度是视觉编码，宁可少画一段也不画一段假的 7 个月',
      );
    });

    test('整段未公布（起点为空）→ 不画；起点已知、终点未知 → 照画成虚线', () {
      final table = SchoolTimeTable([
        term(2026, 0, start: DateTime(2026, 9, 7)), // 只有起点
        term(2026, 1), // 空壳页 → 起点为空
      ]);
      final segs = schoolTimelineSegments(table, 2026);
      expect(segs.map((s) => s.name).toList(), ['第一学期']);
      expect(segs.single.isOpen, isTrue);
      expect(segs.single.note, '结束日待公布');
    });

    test('轴：有校历用真实学年末；没校历退固定窗口', () {
      final real = schoolTimelineAxis(fullTable(), 2025);
      expect(real.start, DateTime(2025, 9, 1));
      expect(real.end, DateTime(2026, 9, 6), reason: '下学年首日 09-07 − 1 天');

      final fallback = schoolTimelineAxis(null, 2026);
      expect(fallback.start, DateTime(2026, 9, 1));
      expect(fallback.end, DateTime(2027, 8, 31));
    });

    test('轴投影：越界夹到端头，待公布的段画到轴尾', () {
      final axis = schoolTimelineAxis(null, 2026);
      expect(axis.fractionOf(DateTime(2026, 9, 1)), 0);
      expect(axis.fractionOf(DateTime(2027, 8, 31)), 1);
      expect(axis.fractionOf(DateTime(2020, 1, 1)), 0, reason: '轴前夹 0');
      expect(axis.fractionOf(DateTime(2030, 1, 1)), 1, reason: '轴后夹 1');

      final open = SchoolTimelineSegment(
        name: '寒假',
        start: DateTime(2027, 1, 16),
        end: null,
        kind: SchoolTimelineKind.holiday,
      );
      final (a, b) = axis.spanOf(open);
      expect(b, 1.0, reason: '终点未知 → 画到轴尾（展示层再画成虚线）');
      expect(a, greaterThan(0));
      expect(a, lessThan(1));
    });
  });

  group('时间线渲染', () {
    testWidgets('已排满的学年：五段都画得下、不溢出不报错', (tester) async {
      final table = fullTable();
      await tester.pumpWidget(
        harness(
          SchoolYearTimeline(
            axis: schoolTimelineAxis(table, 2025),
            segments: schoolTimelineSegments(table, 2025),
            today: DateTime(2025, 10, 9),
            todayNote: '第 5 教学周',
          ),
        ),
      );
      expect(find.byType(SchoolYearTimeline), findsOneWidget);
      expect(
        tester.getSize(find.byType(SchoolYearTimeline)).height,
        SchoolYearTimeline.height,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('★ 卡片比标签还窄也不许崩（clamp 上下界写反过一次）', (tester) async {
      // 实测事故：标签让位用 `clamp(prevRight + 12, size.width - w)`，字体一变宽
      // 就会出现 lower > upper → `ArgumentError: Invalid argument(s): 336.0`
      // （只有全量跑时才复现，因为那时引擎里多了一批字体、标签更宽）。
      final table = fullTable();
      for (final width in const [240.0, 160.0, 96.0]) {
        await tester.pumpWidget(harness(_timeline(table), width: width));
        expect(
          tester.takeException(),
          isNull,
          reason: '宽度 $width 时标签比卡片还宽，也不许抛异常',
        );
      }
    });

    testWidgets('窄卡（280）也不溢出：月份名放不下就隔一个画', (tester) async {
      final table = fullTable();
      await tester.pumpWidget(
        harness(
          SchoolYearTimeline(
            axis: schoolTimelineAxis(table, 2025),
            segments: schoolTimelineSegments(table, 2025),
          ),
          width: 280,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('无障碍标签就是段名的唯一出口（日期画在轴上，find.text 找不到）', (
      tester,
    ) async {
      final table = partialTable();
      await tester.pumpWidget(
        harness(
          SchoolYearTimeline(
            axis: schoolTimelineAxis(table, 2026),
            segments: schoolTimelineSegments(table, 2026),
            today: DateTime(2026, 10, 9),
            todayNote: '第 5 教学周',
          ),
        ),
      );
      final label = tester.getSemantics(find.byType(SchoolYearTimeline)).label;
      expect(label, startsWith('学年时间线'));
      expect(label, contains('第一学期 09-07 ~ 01-15'));
      expect(label, contains('寒假 01-16 起（待公布）'));
      expect(find.text('第一学期'), findsNothing, reason: '段名由 CustomPaint 画，不是 Text');
    });

    testWidgets('今天不在轴上 → 不画标记（历史学年不该出现「今天」）', (tester) async {
      final table = fullTable();
      await tester.pumpWidget(
        harness(
          SchoolYearTimeline(
            axis: schoolTimelineAxis(table, 2025),
            segments: schoolTimelineSegments(table, 2025),
            // 2026-10 已在 2025 学年轴外
            today: DateTime(2026, 10, 9),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('源码守卫', () {
    String read(String rel) =>
        // ignore: avoid_slow_async_io
        File(rel).readAsStringSync();

    test('Fluent 取色：时间线不许出现字面色值', () {
      final src = read(
        'lib/features/school_calendar/presentation/widgets/school_year_timeline.dart',
      );
      expect(src.contains('Color(0x'), isFalse, reason: '色值一律走 fluent(context)');
      expect(src.contains('fluent(context)'), isTrue);
      expect(src.contains('FluentType.'), isTrue, reason: '字号只用 Fluent 那几档');
      // 4px 栅格：带位常量都是 4 的倍数，且没有 5 / 7 / 10 这类越轨值
      for (final m in RegExp(r'static const double _(\w+) = ([\d.]+);')
          .allMatches(src)) {
        final v = double.parse(m.group(2)!);
        expect(v % 4, 0, reason: '${m.group(1)} = $v 不在 4px 栅格上');
      }
    });

    test('卡片确实换成了单轴时间线（旧的图标 + 文字行已删）', () {
      final src = read(
        'lib/features/school_calendar/presentation/school_calendar_screen.dart',
      );
      expect(src.contains('SchoolYearTimeline('), isTrue);
      expect(
        src.contains('Icons.menu_book_outlined'),
        isFalse,
        reason: '旧「一行一个学段」的列表已删，别再复活',
      );
      expect(
        src.contains('Icons.ac_unit_outlined'),
        isFalse,
        reason: '旧「一行一个假期」的列表已删',
      );
    });

    test('学段列表只有一个定义（domain），provider 只转发', () {
      final domain = read(
        'lib/features/school_calendar/domain/school_time_timeline.dart',
      );
      final provider = read(
        'lib/features/school_calendar/data/providers/school_time_providers.dart',
      );
      expect(
        domain.contains('const List<int> schoolYearTermSegments = [0, 1, 2];'),
        isTrue,
      );
      expect(
        provider.contains('const List<int> schoolYearTermSegments'),
        isFalse,
        reason: 'provider 里不许再定义一份（只 export 转发）',
      );
      expect(provider.contains("show schoolYearTermSegments"), isTrue);
    });
  });
}
