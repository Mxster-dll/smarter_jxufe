/// 课表标题栏「学期 + 周次」单行/两行自适应 + 手机端学期码按钮守卫。
///
/// 背景（用户 2026-09-15 两条裁定）：
/// ① 「为什么学期选择和周数显示不在同一行」—— 起因是当时的 `_buildTitleBar`
///    **写死**两行（`Column[Row(学年+学段), 周次行]`），桌面端白白浪费一行高度。
///    现按可用宽度自适应：宽屏一行、手机竖屏两行。
/// ② 「把手机端的课表的学年选择器和学期下拉列表改成一个显示学期的按钮，
///    显示格式也是 xxy，然后点击显示这个学期选择器，范围设为入学年份-当前学年」
///    —— 手机端（compact）现在是 `SchoolTermCodeButton`（如 `251`）+ 阵列弹窗；
///    桌面端仍是学年选择器 + 学段下拉。
///
/// `ScheduleTitleBar` 是独立组件（不依赖任何 provider），因此这里直接渲染真实
/// 组件、按真实的 `getTopLeft()/getCenter()` 断言行数与内容，而不必伪造学籍/课表仓库。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/ims/schedule/presentation/schedule_title_bar.dart';
import 'package:smarter_jxufe/shared/widgets/academic_year_picker.dart';
import 'package:smarter_jxufe/shared/widgets/school_term_grid.dart';

/// 把系统黑体注册成主题字体族 `Cascadia Code`。
///
/// **不变式用例必须用它**：`FlutterTest` 默认字体与「裸 `TextStyle`（无字体族）」
/// 同形，量宽虚高这类 bug 在默认字体下量不出差别（真实字体 `261`@15 = 23.3，
/// 默认字体 = 45.0）。文件不存在时静默跳过（量宽仍成立，只是敏感度下降）。
Future<void> _loadThemeFont() async {
  final file = File(r'C:\Windows\Fonts\simhei.ttf');
  if (!file.existsSync()) return;
  final bytes = file.readAsBytesSync();
  final loader = FontLoader('Cascadia Code')
    ..addFont(
      Future<ByteData>.value(ByteData.view(Uint8List.fromList(bytes).buffer)),
    );
  await loader.load();
}

/// 镜像**生产**布局与调用点。
///
/// `ScheduleScreen.build` 是在 `Scaffold` **之外**调 `fitsOneRow` 的，那里既没有
/// AppBar 的 `DefaultTextStyle`、也没有 Material 的文字样式 —— 量宽基础样式取错
/// 就会虚高导致「还有很大空隙就换行」（用户 2026-09-15 报的问题）。所以这里也把
/// 判定放在 `Scaffold` 之外算，标题栏则放进**真实 AppBar**里渲染。
Future<({double need, bool oneRow, double real})> _pumpProduction(
  WidgetTester tester, {
  required double width,
  required int? week,
  int currentWeek = 2,
  bool withChrome = false,
}) async {
  final compact = width < 620;
  tester.view.physicalSize = Size(width, 700);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  late double need;
  late bool oneRow;
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: 'Cascadia Code'),
      home: Builder(
        builder: (context) {
          need = ScheduleTitleBar.rowNeed(
            context,
            compact: compact,
            isCurrentTerm: true,
            currentWeek: currentWeek,
            week: week,
          );
          oneRow = ScheduleTitleBar.fitsOneRow(
            context,
            compact: compact,
            isCurrentTerm: true,
            currentWeek: currentWeek,
            week: week,
          );
          return Scaffold(
            appBar: AppBar(
              titleSpacing: 0,
              // 生产里返回键 56 + 两个 action 各 48，「居中」是相对**标题槽**居中。
              leading: withChrome ? const BackButton() : null,
              actions: withChrome
                  ? [
                      IconButton(
                        icon: const Icon(Icons.event_repeat),
                        onPressed: () {},
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: () {},
                      ),
                    ]
                  : null,
              toolbarHeight: ScheduleTitleBar.toolbarHeight(
                oneRow: oneRow,
                compact: compact,
              ),
              title: ScheduleTitleBar(
                selectedYear: 2025,
                selectedSemester: '0',
                week: week,
                currentWeek: currentWeek,
                isCurrentTerm: true,
                compact: compact,
                pickerStartYear: 2025,
                pickerEndYear: 2026,
                onYearChanged: (_) {},
                onSemesterChanged: (_) {},
                onTermPicked: (_) {},
                onGoToWeek: (_) {},
                onToggleView: () {},
              ),
            ),
          );
        },
      ),
    ),
  );
  await tester.pump();
  return (
    need: need,
    oneRow: oneRow,
    // ⚠ 量 content Key 而不是组件类型：桌面端整组居中后组件自身会撑满标题槽。
    real: tester.getSize(find.byKey(scheduleTitleContentKey)).width,
  );
}

/// 渲染标题栏。[width] 是本窗口的逻辑宽度。
///
/// 默认取**两行档**高度（够宽裕），几何断言不受高度影响；溢出另有两个用例
/// 用生产高度（单行 56 / 两行 78/84）单独验证。
Future<void> _pumpBar(
  WidgetTester tester, {
  required double width,
  int? week = 3,
  int? currentWeek = 3,
  bool isCurrentTerm = true,
  double? toolbarHeight,
  ValueChanged<int>? onGoToWeek,
  VoidCallback? onToggleView,
  ValueChanged<({int xn, int xq})>? onTermPicked,
  int pickerStartYear = 2025,
  int pickerEndYear = 2026,
}) async {
  final compact = width < 620;
  // 高度给足：弹窗用例要在同一视口里点到阵列格子（视口太矮会把弹窗内容裁掉，
  // tap 会因命中不到而静默跳过 → 断言看到空回调）。
  tester.view.physicalSize = Size(width * 1.0, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          toolbarHeight:
              toolbarHeight ??
              ScheduleTitleBar.toolbarHeight(oneRow: false, compact: compact),
          title: ScheduleTitleBar(
            // 2025 学年第一学期 → 学期码 `251`
            selectedYear: 2025,
            selectedSemester: '0',
            week: week,
            currentWeek: currentWeek,
            isCurrentTerm: isCurrentTerm,
            compact: compact,
            pickerStartYear: pickerStartYear,
            pickerEndYear: pickerEndYear,
            onYearChanged: (_) {},
            onSemesterChanged: (_) {},
            onTermPicked: onTermPicked ?? (_) {},
            onGoToWeek: onGoToWeek ?? (_) {},
            onToggleView: onToggleView ?? () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 学期选择器与周次行的**竖向中心**位置。
///
/// 用中心而不是顶边：单行布局里 Row 默认竖向居中，而学期控件与周次行（含 34dp
/// 按钮）自身高度不同 → 顶边天然差几像素，那不算「不在同一行」。
/// 手机端（compact）学期控件 = 学期码按钮，桌面端 = 学段下拉。
List<double> _rowCenters(WidgetTester tester, {required bool compact}) => [
  tester
      .getCenter(
        compact
            ? find.byType(SchoolTermCodeButton)
            : find.byType(ScheduleSemesterSelector),
      )
      .dy,
  tester.getCenter(find.byType(ScheduleWeekSwitcher)).dy,
];

void main() {
  group('课表标题栏单行/两行自适应（用户 2026-09-15 裁定）', () {
    testWidgets('宽屏（1400）：学期与周次在同一行', (tester) async {
      await _pumpBar(tester, width: 1400);
      final tops = _rowCenters(tester, compact: false);
      expect(
        (tops[0] - tops[1]).abs(),
        lessThan(2),
        reason: '宽屏可用宽度足够，学年/学段/周次必须排在同一行',
      );
    });

    testWidgets('窄但够宽（900）：单行', (tester) async {
      await _pumpBar(tester, width: 900);
      final tops = _rowCenters(tester, compact: false);
      expect((tops[0] - tops[1]).abs(), lessThan(2));
    });

    testWidgets('手机竖屏（360）：仍分两行（放不下）', (tester) async {
      await _pumpBar(tester, width: 360);
      final tops = _rowCenters(tester, compact: true);
      expect(
        tops[1] - tops[0],
        greaterThan(12),
        reason: '360 宽只有约 208dp 可用，学期码 + 周次仍放不下',
      );
    });

    testWidgets('手机较宽（460）：单行 —— 学期码按钮比「学年+学段」省宽度', (tester) async {
      await _pumpBar(tester, width: 460);
      final tops = _rowCenters(tester, compact: true);
      expect(
        (tops[0] - tops[1]).abs(),
        lessThan(2),
        reason: '合并成一个学期码按钮后，460 宽足以排成一行',
      );
    });

    test('AppBar 高度随行数变化（单行矮、两行高）', () {
      expect(ScheduleTitleBar.toolbarHeight(oneRow: true, compact: false), 56);
      expect(
        ScheduleTitleBar.toolbarHeight(oneRow: false, compact: false),
        greaterThan(
          ScheduleTitleBar.toolbarHeight(oneRow: true, compact: false),
        ),
      );
      expect(
        ScheduleTitleBar.toolbarHeight(oneRow: false, compact: true),
        greaterThan(
          ScheduleTitleBar.toolbarHeight(oneRow: true, compact: true),
        ),
      );
    });

    testWidgets('单行档高度放得下（无溢出）', (tester) async {
      await _pumpBar(
        tester,
        width: 1400,
        toolbarHeight: ScheduleTitleBar.toolbarHeight(
          oneRow: true,
          compact: false,
        ),
      );
      expect(tester.takeException(), isNull, reason: '单行内容必须放得进 56');
      final tops = _rowCenters(tester, compact: false);
      expect((tops[0] - tops[1]).abs(), lessThan(2));
    });

    testWidgets('两行档高度放得下（无溢出）', (tester) async {
      await _pumpBar(
        tester,
        width: 320,
        toolbarHeight: ScheduleTitleBar.toolbarHeight(
          oneRow: false,
          compact: true,
        ),
      );
      expect(tester.takeException(), isNull, reason: '两行内容必须放得进 84');
      final tops = _rowCenters(tester, compact: true);
      expect(tops[1] - tops[0], greaterThan(12));
    });

    testWidgets('周次切换：上一周 / 下一周 / 「本周」/ 视图切换仍可用', (tester) async {
      final jumps = <int>[];
      var toggled = false;
      await _pumpBar(
        tester,
        width: 1400,
        week: 5,
        currentWeek: 3,
        onGoToWeek: jumps.add,
        onToggleView: () => toggled = true,
      );
      await tester.tap(find.byTooltip('上一周'));
      await tester.tap(find.byTooltip('下一周'));
      await tester.tap(find.byTooltip('切换到整学期视图'));
      expect(jumps, [4, 6]);
      expect(toggled, isTrue);
    });
  });

  group('手机端学期码按钮（用户 2026-09-15 裁定）', () {
    testWidgets('手机端只留学期码按钮，学年选择器与学段下拉都不再出现', (tester) async {
      await _pumpBar(tester, width: 360);
      expect(find.byType(SchoolTermCodeButton), findsOneWidget);
      expect(
        find.text('251 学期'),
        findsOneWidget,
        reason: '显示格式 = 学期码 + 「学期」二字（用户 2026-09-15 追加）',
      );
      expect(find.byType(AcademicYearPicker), findsNothing);
      expect(find.byType(ScheduleSemesterSelector), findsNothing);
    });

    testWidgets('学期码只有文字：无边框、无下拉 icon（用户 2026-09-15 裁定）', (tester) async {
      await _pumpBar(tester, width: 360);
      final button = find.byType(SchoolTermCodeButton);
      expect(
        find.descendant(of: button, matching: find.byType(OutlinedButton)),
        findsNothing,
        reason: '不要边框',
      );
      expect(
        find.descendant(
          of: button,
          matching: find.byIcon(Icons.arrow_drop_down),
        ),
        findsNothing,
        reason: '不要下拉 icon',
      );
      expect(
        find.byIcon(Icons.arrow_drop_down),
        findsNothing,
        reason: '整条手机端标题栏都不该有下拉箭头',
      );
      // 只有一段文字（`251`），没有别的可视件
      expect(
        find.descendant(of: button, matching: find.byType(Text)),
        findsOneWidget,
      );
    });

    testWidgets('桌面端仍是「学年选择器 + 学段下拉」，不出现学期码按钮', (tester) async {
      await _pumpBar(tester, width: 1400);
      expect(find.byType(SchoolTermCodeButton), findsNothing);
      expect(find.byType(AcademicYearPicker), findsOneWidget);
      expect(find.byType(ScheduleSemesterSelector), findsOneWidget);
    });

    testWidgets('点学期码按钮 → 阵列弹窗按给定范围出格；选中即回传 (xn, xq)', (tester) async {
      final picked = <({int xn, int xq})>[];
      await _pumpBar(
        tester,
        width: 360,
        pickerStartYear: 2025,
        pickerEndYear: 2026,
        onTermPicked: picked.add,
      );

      await tester.tap(find.byType(SchoolTermCodeButton));
      await tester.pumpAndSettle();

      expect(find.text('选择学期'), findsOneWidget);
      expect(find.byType(SchoolTermGrid), findsOneWidget);
      // 范围 = 2025~2026 → 两列（学年）× 三行（学段）
      for (final code in const ['251', '252', '253', '261', '262', '263']) {
        expect(find.byKey(Key('schoolTermCell-$code')), findsOneWidget);
      }
      expect(find.byKey(const Key('schoolTermCell-241')), findsNothing);

      await tester.tap(find.byKey(const Key('schoolTermCell-262')));
      await tester.pumpAndSettle();

      expect(picked, [(xn: 2026, xq: 1)]);
      expect(find.byType(SchoolTermGrid), findsNothing, reason: '选中后弹窗关闭');
    });

    testWidgets('弹窗取消不触发回传', (tester) async {
      final picked = <({int xn, int xq})>[];
      await _pumpBar(tester, width: 360, onTermPicked: picked.add);

      await tester.tap(find.byType(SchoolTermCodeButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(picked, isEmpty);
      expect(find.byType(SchoolTermGrid), findsNothing);
    });
  });

  group('不变式：量宽与真实渲染一致（用户 2026-09-15「还有很大空隙就换行」）', () {
    setUpAll(_loadThemeFont);

    testWidgets('need 落在真实内容宽度的 [−6, +15] 区间内', (tester) async {
      for (final week in const [null, 2, 3, 20]) {
        // 1600 宽必然单行 → 此时标题栏自身宽度就是单行内容宽度（真实渲染）。
        final m = await _pumpProduction(tester, width: 1600, week: week);
        expect(m.oneRow, isTrue, reason: '1600 宽必然单行');
        expect(
          m.need - m.real,
          inInclusiveRange(-6, 15),
          reason:
              'week=$week：need=${m.need.toStringAsFixed(1)} '
              'real=${m.real.toStringAsFixed(1)} —— need 偏小会溢出、偏大会提前换行',
        );
      }
    });

    testWidgets('可用宽度 = 真实内容 + 24 时必须单行；窄于真实内容时必须换行且不溢出', (tester) async {
      for (final week in const [null, 2, 3, 20]) {
        // ⚠ 必须在**同一档**里量内容宽：档位由窗口宽（< 620 = 手机档）决定，
        // 若用 1600 量到的桌面内容宽去算手机档宽度，算出来的宽度会落回手机档
        // （592 < 620），断言就没意义了。
        // 手机档：600 宽视口（仍单行）下量真实内容宽。
        final phone = await _pumpProduction(tester, width: 600, week: week);
        expect(phone.oneRow, isTrue, reason: '600 宽在手机档里必然单行');
        final phoneContent = phone.real;

        final snug = await _pumpProduction(
          tester,
          width: phoneContent + ScheduleTitleBar.chromeWidth + 24,
          week: week,
        );
        expect(tester.takeException(), isNull);
        expect(
          snug.oneRow,
          isTrue,
          reason: 'week=$week 手机档：可用余量 24dp 却换行了（提前换行）',
        );

        final narrow = await _pumpProduction(
          tester,
          width: phoneContent + ScheduleTitleBar.chromeWidth - 12,
          week: week,
        );
        expect(narrow.oneRow, isFalse, reason: 'week=$week 手机档：放不下却仍宣称单行');
        expect(tester.takeException(), isNull, reason: '两行布局不该溢出');

        // 桌面档：断点宽（620，桌面档最窄）必须仍单行 —— 内容宽约 416~432、
        // 需要约 435，可用 468，余量足够。
        final desktopMin = await _pumpProduction(
          tester,
          width: 620,
          week: week,
        );
        expect(tester.takeException(), isNull);
        expect(
          desktopMin.oneRow,
          isTrue,
          reason: 'week=$week 桌面档：窄到断点 620 就不该换行（提前换行）',
        );
      }
    });

    testWidgets('手机端（360/400/460）与桌面端都按上述口径落地', (tester) async {
      // 360：compact 内容约 210 → 放不下 → 两行
      final narrow = await _pumpProduction(tester, width: 360, week: 3);
      expect(narrow.oneRow, isFalse);
      expect(tester.takeException(), isNull);
      // 460：可用 308 > 内容 + 24 → 单行
      final wide = await _pumpProduction(tester, width: 460, week: 3);
      expect(wide.oneRow, isTrue);
      expect(tester.takeException(), isNull);
    });
  });

  group('标题栏对齐（用户 2026-09-15「电脑端学年学期选择器居中」）', () {
    setUpAll(_loadThemeFont);

    testWidgets('桌面端整组相对标题槽居中', (tester) async {
      for (final week in const [null, 3]) {
        for (final width in const [900.0, 1400.0]) {
          await _pumpProduction(
            tester,
            width: width,
            week: week,
            withChrome: true,
          );
          final content = tester.getRect(find.byKey(scheduleTitleContentKey));
          // 生产 chrome：返回键 56 + 两个 action 各 48 → 标题槽 = [56, width-96]
          const leadingWidth = 56.0;
          const trailingWidth = 96.0;
          final expectedCenter =
              leadingWidth + (width - leadingWidth - trailingWidth) / 2;
          expect(
            (content.center.dx - expectedCenter).abs(),
            lessThan(2),
            reason:
                'week=$week width=$width：整组中心 '
                '${content.center.dx} 应贴标题槽中心 $expectedCenter',
          );
          expect(tester.takeException(), isNull);
        }
      }
    });

    testWidgets('手机端同样整组居中（用户 2026-09-15 追加）', (tester) async {
      for (final width in const [360.0, 460.0]) {
        await _pumpProduction(tester, width: width, week: 3, withChrome: true);
        final content = tester.getRect(find.byKey(scheduleTitleContentKey));
        const leadingWidth = 56.0;
        const trailingWidth = 96.0;
        final expectedCenter =
            leadingWidth + (width - leadingWidth - trailingWidth) / 2;
        expect(
          (content.center.dx - expectedCenter).abs(),
          lessThan(2),
          reason:
              'width=$width：手机端整组中心 ${content.center.dx} 应贴标题槽中心 '
              '$expectedCenter（用户：「移动端的学期切换和周数切换也在标题栏居中」）',
        );
        expect(tester.takeException(), isNull);
      }
    });
  });
}
