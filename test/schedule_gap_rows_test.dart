import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/class_time.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/period_time.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_entry.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_gap_rows.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/schedule_grid_view.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/schedule_horizontal_view.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/schedule_tone.dart';

/// 用户 2026-09-17：「我希望课表显示时，任意两行之间的时间间隔一旦超过了 1h，
/// 就在这两行之间插一个矮行」。
///
/// 判定必须来自**真实作息表**（课表 HTML 只给节次、不给钟点），所以领域层
/// （`domain/schedule_gap_rows.dart`）是唯一口径，两个视图都按它渲染：
/// - 竖版插矮**行**（`scheduleGapRowAfter-<p>`）；
/// - 横版插矮**列**（`scheduleGapColumnAfter-<p>`）。
void main() {
  /// 与 `PeriodTable.builtin` 同值的完整表（12 节，午休 100 分钟、晚饭 70 分钟）。
  const full = PeriodTable(
    label: '内置兜底表',
    periods: [
      ClassPeriod(index: 1, start: '08:00', end: '08:45'),
      ClassPeriod(index: 2, start: '08:50', end: '09:35'),
      ClassPeriod(index: 3, start: '09:55', end: '10:40'),
      ClassPeriod(index: 4, start: '10:45', end: '11:30'),
      ClassPeriod(index: 5, start: '11:35', end: '12:20'),
      ClassPeriod(index: 6, start: '14:00', end: '14:45'),
      ClassPeriod(index: 7, start: '14:50', end: '15:35'),
      ClassPeriod(index: 8, start: '15:55', end: '16:40'),
      ClassPeriod(index: 9, start: '16:45', end: '17:30'),
      ClassPeriod(index: 10, start: '18:40', end: '19:25'),
      ClassPeriod(index: 11, start: '19:30', end: '20:15'),
      ClassPeriod(index: 12, start: '20:20', end: '21:05'),
    ],
  );

  group('领域口径', () {
    test('内置作息表正好两处超过 1h：第 5 节后（午休）与第 9 节后（晚饭）', () {
      expect(scheduleGapAfterPeriods(PeriodTable.builtin), [5, 9]);
      expect(scheduleGapAfterPeriods(full), [5, 9]);
    });

    test('阈值是「超过 1h」，恰好 60 分钟不算', () {
      expect(scheduleGapThresholdMinutes, 60);
      const exactly = PeriodTable(
        label: 't',
        periods: [
          ClassPeriod(index: 1, start: '08:00', end: '09:00'),
          ClassPeriod(index: 2, start: '10:00', end: '10:45'), // 正好 60 分钟
          ClassPeriod(index: 3, start: '11:46', end: '12:30'), // 61 分钟
        ],
      );
      expect(scheduleGapAfterPeriods(exactly), [2]);
    });

    test('作息表为 null / 缺相邻节次时不插矮行（不猜）', () {
      expect(scheduleGapAfterPeriods(null), isEmpty);
      expect(scheduleRows(null).every((r) => !r.isGap), isTrue);
      // 只有 1、2 两节的表（守卫测试里的那种）：1→2 空档 5 分钟，且 2→3 缺节。
      const partial = PeriodTable(
        label: 't',
        periods: [
          ClassPeriod(index: 1, start: '08:00', end: '08:45'),
          ClassPeriod(index: 2, start: '08:50', end: '09:35'),
        ],
      );
      expect(scheduleGapAfterPeriods(partial), isEmpty);
    });

    test('行序列 = 12 个节次行 + 矮行，顺序与节次一致', () {
      final rows = scheduleRows(full);
      expect(rows.length, 12 + 2);
      final periods = [
        for (final r in rows)
          if (!r.isGap) r.period,
      ];
      expect(periods, List.generate(12, (i) => i + 1));
      final gaps = [
        for (final r in rows)
          if (r.isGap) (r.period, r.gapMinutes),
      ];
      expect(gaps, [(5, 100), (9, 70)]);
      // 矮行紧跟在它所属的节次行之后：
      // 0..4 = 1..5 节，5 = 矮行（5 节后），6..9 = 6..9 节，10 = 矮行（9 节后）
      expect(rows[5].isGap, isTrue);
      expect(rows[5].period, 5);
      expect(rows[10].isGap, isTrue);
      expect(rows[10].period, 9);
    });

    test('空档分钟数与文案', () {
      expect(scheduleBreakMinutes(full, 5), 100);
      expect(scheduleBreakMinutes(full, 9), 70);
      expect(scheduleBreakMinutes(full, 1), 5);
      expect(scheduleBreakMinutes(full, 12), isNull, reason: '第 12 节之后没有下一节');
      expect(scheduleBreakMinutes(null, 5), isNull);

      expect(scheduleGapLabel(100), '1h40');
      expect(scheduleGapLabel(70), '1h10');
      expect(scheduleGapLabel(120), '2h');
      expect(scheduleGapLabel(55), '55m');
      expect(scheduleGapLabel(0), '');
    });
  });

  group('竖版：矮行插在节次行之间', () {
    Future<void> pump(
      WidgetTester tester, {
      PeriodTable? periods,
      List<ScheduleEntry> entries = const [],
      bool dark = false,
      bool showGridLines = true,
    }) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? appDarkTheme : appLightTheme,
          home: Scaffold(
            body: ScheduleGridView(
              entries: entries,
              periods: periods,
              showToggle: false,
              showGridLines: showGridLines,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('无作息表 → 没有矮行（退回旧观感）', (tester) async {
      await pump(tester);
      expect(find.byKey(const Key('scheduleGapRowAfter-5')), findsNothing);
      expect(find.byKey(const Key('scheduleGapRowAfter-9')), findsNothing);
      expect(find.byKey(const Key('schedulePeriodCell-5')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('完整作息表 → 第 5、9 节之后各多一行（节次列与每一天列都有）', (tester) async {
      await pump(tester, periods: full);
      final after5 = find.byKey(const Key('scheduleGapRowAfter-5'));
      final after9 = find.byKey(const Key('scheduleGapRowAfter-9'));
      // 节次列 1 个 + 可见天各 1 个（默认周六周日都显示 → 7 天）
      expect(after5, findsNWidgets(8));
      expect(after9, findsNWidgets(8));
      expect(tester.takeException(), isNull);
    });

    testWidgets('矮行只占很矮的一条，且把 12 节整体撑在可用高度内', (tester) async {
      await pump(tester, periods: full);
      final gap = tester.getRect(
        find.byKey(const Key('scheduleGapRowAfter-5')).first,
      );
      final cell5 = tester.getRect(
        find.byKey(const Key('schedulePeriodCell-5')),
      );
      final cell6 = tester.getRect(
        find.byKey(const Key('schedulePeriodCell-6')),
      );
      expect(gap.height, lessThan(cell5.height), reason: '矮行必须比节次行矮');
      expect(gap.height, lessThanOrEqualTo(20));
      // 顺序：5 → 矮行 → 6（矮行紧贴在两行之间，没有重叠）
      expect(gap.top, greaterThanOrEqualTo(cell5.bottom - 0.5));
      expect(cell6.top, greaterThanOrEqualTo(gap.bottom - 0.5));
    });

    testWidgets('矮行与其他格子同底色（不涂色）、且不渲染任何时长文案', (tester) async {
      // 用户 2026-09-17：「矮行颜色要与其他格子颜色一致，不显示内容文本」。
      for (final dark in [false, true]) {
        await pump(tester, periods: full, dark: dark);
        for (final key in const [
          'scheduleGapRowAfter-5',
          'scheduleGapRowAfter-9',
        ]) {
          final finder = find.byKey(Key(key)).first;
          final container = tester.widget<Container>(finder);
          final decoration = container.decoration;
          expect(decoration, isA<BoxDecoration>(), reason: '$key dark=$dark');
          final box = decoration! as BoxDecoration;
          expect(
            box.color,
            isNull,
            reason: '$key（dark=$dark）又给矮行涂了自己的底色',
          );
          expect(container.color, isNull, reason: '$key（dark=$dark）');
          // 边框与同一列的空格子同规格（bottom / right 同上限，不再混用 stroke）。
          final border = box.border! as Border;
          expect(border.bottom.width, border.right.width);
          // 仍然占位（否则「矮行」就没了）
          expect(tester.getRect(finder).height, greaterThan(0));
        }
        // 时长文案不再渲染（`scheduleGapLabel` 保留在 domain，只是不画）
        expect(find.text('1h40'), findsNothing, reason: 'dark=$dark');
        expect(find.text('1h10'), findsNothing, reason: 'dark=$dark');
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('隐藏周六周日时矮行跟着变少（每天列各一行）', (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: appLightTheme,
          home: Scaffold(
            body: ScheduleGridView(
              entries: const [],
              periods: full,
              showToggle: false,
              showSaturday: false,
              showSunday: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // 节次列 1 + 工作日 5
      expect(find.byKey(const Key('scheduleGapRowAfter-5')), findsNWidgets(6));
    });

    testWidgets('跨过午休的课（5-6 节）把矮行吸收进自己格子，整表不错位', (tester) async {
      final crossing = ScheduleEntry(
        classCode: 'X-01',
        className: '跨午休(01)',
        courseCode: 'X1',
        courseName: '跨午休课',
        totalHours: 32,
        credits: 2,
        studyNature: '必修',
        teacherCode: 'T1',
        teacherName: '张三',
        selectionStatus: '已选',
        isCrossMajor: false,
        hasTextbook: true,
        classTimes: const [
          ClassTime(
            dayOfWeek: DayOfWeek.monday,
            startPeriod: 5,
            endPeriod: 6,
            startWeek: 1,
            endWeek: 16,
            weekParity: WeekParity.every,
            classroom: '麦三教101',
          ),
        ],
      );
      await pump(tester, periods: full, entries: [crossing]);

      // 周一那一列：5-6 节的课格必须正好覆盖「第 5 行 + 矮行 + 第 6 行」，
      // 否则该列会比别的列矮一个矮行、从第 6 节起整列错位。
      final cell5 = tester.getRect(
        find.byKey(const Key('schedulePeriodCell-5')),
      );
      final cell6 = tester.getRect(
        find.byKey(const Key('schedulePeriodCell-6')),
      );
      final gapRow = tester.getRect(
        find.byKey(const Key('scheduleGapRowAfter-5')).first,
      );
      final courseBox = tester.getRect(
        find
            .ancestor(of: find.text('跨午休课'), matching: find.byType(Container))
            .first,
      );
      expect(
        courseBox.height,
        closeTo(cell5.height + gapRow.height + cell6.height, 1.0),
        reason: '跨午休课格没把矮行高度吸收进去（会导致整列错位）',
      );
      expect(courseBox.top, closeTo(cell5.top, 1.0));
      expect(
        courseBox.bottom,
        closeTo(cell6.bottom, 1.0),
        reason: '课格底必须与第 6 节行底对齐（中间那个矮行已算进来）',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('横版：同样的序列，插矮列', () {
    testWidgets('完整作息表 → 第 5、9 节之后各多一列（表头与每一行都有）', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: appLightTheme,
          home: Scaffold(
            body: ScheduleHorizontalView(
              entries: const [],
              periods: full,
              showToggle: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // 表头 1 个 + 7 天各 1 个
      expect(
        find.byKey(const Key('scheduleGapColumnAfter-5')),
        findsNWidgets(8),
      );
      expect(
        find.byKey(const Key('scheduleGapColumnAfter-9')),
        findsNWidgets(8),
      );
      // 矮列比节次列窄
      final gap = tester.getRect(
        find.byKey(const Key('scheduleGapColumnAfter-5')).first,
      );
      final header = tester.getRect(
        find.byKey(const Key('schedulePeriodHeaderCell-5')),
      );
      expect(gap.width, lessThan(header.width));
      expect(tester.takeException(), isNull);
    });

    testWidgets('横版仍然恒适应宽度：12 节次列 + 矮列不超过可用宽度', (tester) async {
      const width = 1200.0;
      tester.view.physicalSize = const Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: appLightTheme,
          home: Scaffold(
            body: ScheduleHorizontalView(
              entries: const [],
              periods: full,
              showToggle: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final last = tester.getRect(
        find.byKey(const Key('schedulePeriodHeaderCell-12')),
      );
      final first = tester.getRect(
        find.byKey(const Key('schedulePeriodHeaderCell-1')),
      );
      // 表头行整体（含矮列）不能超出屏幕
      expect(last.right, lessThanOrEqualTo(width + 0.5));
      expect(first.left, greaterThanOrEqualTo(-0.5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('横版矮列与同行空格子同底色：工作日行不涂色', (tester) async {
      // 用户 2026-09-17：「矮行颜色要与其他格子颜色一致」。横版把矮行转成矮【列】，
      // 规则与同一行的空格子相同：工作日透明，只有周末（分区底）才上色。
      // 关掉周六周日 → 7 行都是工作日 → 除表头那颗（红底）外全都不许有底色。
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final dark in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? appDarkTheme : appLightTheme,
            home: Scaffold(
              body: ScheduleHorizontalView(
                entries: const [],
                periods: full,
                showToggle: false,
                showSaturday: false,
                showSunday: false,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final cells = find.byKey(const Key('scheduleGapColumnAfter-5'));
        // 1 个表头格 + 5 个工作日行格（周六周日已隐藏）
        expect(cells, findsNWidgets(6), reason: 'dark=$dark');
        for (var i = 0; i < 6; i++) {
          final container = tester.widget<Container>(cells.at(i));
          final box = container.decoration! as BoxDecoration;
          if (i == 0) {
            // 表头格：与整条表头带同底色（实心深红，深色下不换档）
            expect(box.color, ScheduleTone.headerRed, reason: 'dark=$dark');
          } else {
            expect(
              box.color,
              isNull,
              reason: '第 $i 个矮列（工作日行）又被涂了底色 dark=$dark',
            );
          }
        }
        expect(tester.takeException(), isNull);
      }
    });
  });
}
