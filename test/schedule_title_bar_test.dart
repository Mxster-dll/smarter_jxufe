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
import 'package:smarter_jxufe/features/ims/schedule/presentation/schedule_week_picker.dart';
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
            // 与下面的 AppBar 里真实渲染的按钮数一致（返回键 56 + 2×48）。
            actionCount: withChrome ? 2 : 0,
            hasLeading: withChrome,
          );
          return Scaffold(
            appBar: AppBar(
              titleSpacing: 0,
              // 生产里返回键 56 + 两个 action 各 48，「居中」是相对**标题槽**居中。
              leading: withChrome ? const BackButton() : null,
              actions: withChrome
                  ? [
                      // 与生产同款（紧凑款 action：宽 = ScheduleTitleBar.actionWidth）。
                      scheduleBarAction(
                        icon: Icons.event_repeat,
                        tooltip: '调课管理',
                        onPressed: () {},
                      ),
                      scheduleBarAction(
                        icon: Icons.refresh,
                        tooltip: '刷新',
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
                actionCount: withChrome ? 2 : 0,
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
  ValueChanged<int>? onReturnToCurrentWeek,
  int actionCount = 2,
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
            onReturnToCurrentWeek: onReturnToCurrentWeek,
            actionCount: actionCount,
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

    testWidgets('手机竖屏（360）：现在也排得进一行（用户 2026-09-16 裁定）', (tester) async {
      // 视图切换按钮移进 `actions`、「本周」按钮删除后，标题栏只剩「学期码 +
      // 第 N 周」两段 → 360 宽（可用 208dp）也放得下。用户 2026-09-16 原话：
      // 「感觉不知道哪个组件的边距特别大，导致标题栏总是换行，但是标题栏其实是
      // 可以装下那么多内容的」——从前这里确实会换行。
      await _pumpBar(tester, width: 360);
      final tops = _rowCenters(tester, compact: true);
      expect(
        (tops[0] - tops[1]).abs(),
        lessThan(2),
        reason: '360 宽（可用 208dp）足以把学期码与周次排成一行',
      );
    });

    testWidgets('极窄（320）：放不下才换行', (tester) async {
      await _pumpBar(tester, width: 250);
      final tops = _rowCenters(tester, compact: true);
      expect(
        tops[1] - tops[0],
        greaterThan(12),
        reason: '更窄时才允许换行（可用宽度 < 内容宽）',
      );
      expect(tester.takeException(), isNull);
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

    testWidgets('周次入口：点周数开选择器；长按周数回本周（用户 2026-09-16 裁定）', (tester) async {
      final jumps = <int>[];
      await _pumpBar(
        tester,
        width: 1400,
        week: 5,
        currentWeek: 3,
        onGoToWeek: jumps.add,
      );
      // 用户 2026-09-16：「取消周数的左右按钮，但是点击周数，显示一个周数选择器」
      expect(find.byTooltip('上一周'), findsNothing);
      expect(find.byTooltip('下一周'), findsNothing);
      // 用户 2026-09-16：「标题栏中不显示本周按钮」
      expect(find.text('本周'), findsNothing);

      await tester.tap(find.byKey(scheduleWeekButtonKey));
      await tester.pumpAndSettle();
      expect(find.text('选择周数'), findsOneWidget);
      await tester.tap(find.byKey(scheduleWeekCellKey(7)));
      await tester.pumpAndSettle();
      expect(jumps, [7]);

      // 用户 2026-09-16：「长按周数可以回到本周」
      await tester.longPress(find.byKey(scheduleWeekButtonKey));
      await tester.pumpAndSettle();
      expect(jumps, [7, 3]);
    });

    testWidgets('长按回本周走 onReturnToCurrentWeek（用户 2026-09-17：要横划动画）', (
      tester,
    ) async {
      // 「回本周」与「弹窗选周」都落在同一个控件上，而课表页只对前者要求
      // 横划过去（后者仍是直接跳）→ 必须能分辨：长按走专用回调。
      final jumps = <int>[];
      final returns = <int>[];
      await _pumpBar(
        tester,
        width: 1400,
        week: 9,
        currentWeek: 3,
        onGoToWeek: jumps.add,
        onReturnToCurrentWeek: returns.add,
      );

      // 弹窗选周 → 普通改周
      await tester.tap(find.byKey(scheduleWeekButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(scheduleWeekCellKey(7)));
      await tester.pumpAndSettle();
      expect(jumps, [7], reason: '弹窗选周走 onGoToWeek');
      expect(returns, isEmpty);

      // 长按 → 专用回调（课表页据此请求分页器横划）
      await tester.longPress(find.byKey(scheduleWeekButtonKey));
      await tester.pumpAndSettle();
      expect(returns, [3], reason: '长按回本周走 onReturnToCurrentWeek');
      expect(jumps, [7], reason: '长按不该再落到 onGoToWeek');
    });

    testWidgets('未传 onReturnToCurrentWeek 时长按仍回本周（向后兼容）', (tester) async {
      final jumps = <int>[];
      await _pumpBar(
        tester,
        width: 1400,
        week: 9,
        currentWeek: 3,
        onGoToWeek: jumps.add,
      );
      await tester.longPress(find.byKey(scheduleWeekButtonKey));
      await tester.pumpAndSettle();
      expect(jumps, [3]);
    });

    testWidgets('本周高亮：当前周就是本周时周数用主色标记（用户 2026-09-16 裁定）', (tester) async {
      await _pumpBar(tester, width: 1400, week: 3, currentWeek: 3);
      final scheme = Theme.of(
        tester.element(find.byKey(scheduleWeekButtonKey)),
      ).colorScheme;
      final text = tester.widget<Text>(find.text('第 3 周'));
      expect(text.style?.color, scheme.primary, reason: '本周要高亮');
      expect(text.style?.fontWeight, FontWeight.w700);

      // 非本周则用普通文字色。
      await _pumpBar(tester, width: 1400, week: 5, currentWeek: 3);
      final other = tester.widget<Text>(find.text('第 5 周'));
      expect(other.style?.color, isNot(scheme.primary));
    });

    testWidgets('整学期视图不显示「整学期」字样（用户 2026-09-16 裁定）', (tester) async {
      await _pumpBar(tester, width: 1400, week: null, currentWeek: 3);
      expect(find.text('整学期'), findsNothing);
      expect(
        find.byKey(scheduleWeekButtonKey),
        findsNothing,
        reason: '整学期视图下周次控件整个不渲染（回周视图靠 actions 里的切换按钮）',
      );
      expect(find.byType(ScheduleWeekSwitcher), findsNothing);
    });

    testWidgets('切换视图按钮与调课按钮在 actions 里（用户 2026-09-16 裁定）', (tester) async {
      final src = File(
        'lib/features/ims/schedule/presentation/schedule_screen.dart',
      ).readAsStringSync();
      expect(
        src.contains('icon: _week == null ? Icons.view_week : Icons.grid_view'),
        isTrue,
        reason: '视图切换按钮要在 actions 列表里（与调课按钮并排），不再居中',
      );
      expect(
        src.contains('final barActionCount = actions.length + 1;'),
        isTrue,
        reason:
            'chrome 宽度必须跟着真实按钮数走（手机 2 个、桌面 3 个）+ 全局设置按钮 1 个'
            '（2026-09-16 由 paneAppBar 自动追加，见 settings_entry.dart）',
      );
      expect(
        src.contains('actionCount: barActionCount'),
        isTrue,
        reason: '标题栏与内嵌面板两处都要用同一个 barActionCount',
      );
      expect(
        src.contains('ScheduleTitleBar.chromeWidthFor'),
        isTrue,
        reason: '内嵌面板的标题栏行宽修正要用同一个 chrome 口径',
      );
      // 标题栏构造里不该再有 onToggleView（那个按钮已移走）。
      final barCall = RegExp(
        r'ScheduleTitleBar\(\s*selectedYear:',
      ).firstMatch(src);
      expect(barCall, isNotNull);
      final segment = src.substring(barCall!.start, barCall.start + 900);
      expect(
        segment.contains('onToggleView'),
        isFalse,
        reason: '标题栏不再接收视图切换回调',
      );
    });
  });

  group('移动端刷新方式（用户 2026-09-16 裁定）', () {
    testWidgets('手机端课表页不再有刷新按钮，改为下拉刷新', (tester) async {
      final src = File(
        'lib/features/ims/schedule/presentation/schedule_screen.dart',
      ).readAsStringSync();
      expect(
        src.contains('_wrapRefresh'),
        isTrue,
        reason: '下拉刷新必须走 _wrapRefresh(compact, body)',
      );
      expect(
        src.contains('return RefreshIndicator(') &&
            src.contains('onRefresh: _loadData'),
        isTrue,
        reason: '手机端的刷新入口就是 RefreshIndicator(onRefresh: _loadData)',
      );
      expect(
        src.contains('child: _refreshable(child)'),
        isTrue,
        reason: '下拉容器必须包在最外层（内层加 always-scrollable 会把翻页阈值放大到 1 页）',
      );
      // 刷新按钮必须被 `if (!compact)` 门控（桌面端保留、手机端不渲染）。
      final gate = RegExp(
        r'if \(!compact\)\s*\n\s*scheduleBarAction\(\s*\n\s*icon: Icons\.refresh',
      );
      expect(
        gate.hasMatch(src),
        isTrue,
        reason: 'IconButton(Icons.refresh) 必须写在 if (!compact) 里',
      );
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
        final phone = await _pumpProduction(
          tester,
          width: 600,
          week: week,
          withChrome: true,
        );
        expect(phone.oneRow, isTrue, reason: '600 宽在手机档里必然单行');
        final phoneContent = phone.real;

        final snug = await _pumpProduction(
          tester,
          width: phoneContent + ScheduleTitleBar.chromeWidth + 24,
          week: week,
          withChrome: true,
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
          withChrome: true,
        );
        expect(narrow.oneRow, isFalse, reason: 'week=$week 手机档：放不下却仍宣称单行');
        expect(tester.takeException(), isNull, reason: '两行布局不该溢出');

        // 桌面档：断点宽（620，桌面档最窄）必须仍单行 —— 内容宽约 416~432、
        // 需要约 435，可用 468，余量足够。
        final desktopMin = await _pumpProduction(
          tester,
          width: 620,
          week: week,
          withChrome: true,
        );
        expect(tester.takeException(), isNull);
        expect(
          desktopMin.oneRow,
          isTrue,
          reason: 'week=$week 桌面档：窄到断点 620 就不该换行（提前换行）',
        );
      }
    });

    testWidgets('手机端（360/460）与桌面端都按上述口径落地', (tester) async {
      // 360：可用 208dp，内容约 130 → **单行**（2026-09-16 视图切换按钮移进
      // actions 之后的新事实；从前它占 40 宽 + 「本周」按钮占 ~35，才被迫换行）。
      final narrow = await _pumpProduction(
        tester,
        width: 360,
        week: 3,
        withChrome: true,
      );
      expect(narrow.oneRow, isTrue);
      expect(tester.takeException(), isNull);
      // 460：可用 308 > 内容 + 24 → 单行
      final wide = await _pumpProduction(
        tester,
        width: 460,
        week: 3,
        withChrome: true,
      );
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
          // 生产 chrome：返回键 56 + 两个紧凑 action 各 ScheduleTitleBar.actionWidth
          const leadingWidth = 56.0;
          final trailingWidth = ScheduleTitleBar.actionWidth * 2;
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
        final trailingWidth = ScheduleTitleBar.actionWidth * 2;
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

  group('action 按钮量宽契约（用户 2026-09-16「标题栏右侧按钮过大」）', () {
    testWidgets('紧凑款 action 实测宽与图标尺寸 == 量宽契约', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              leading: const BackButton(),
              title: const Text('t'),
              actions: [
                scheduleBarAction(
                  icon: Icons.event_repeat,
                  tooltip: '调课管理',
                  onPressed: () {},
                ),
                scheduleBarAction(
                  icon: Icons.refresh,
                  tooltip: '刷新',
                  compact: false,
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      );

      expect(
        // ⚠ 量 `IconButton` 而不是 `Tooltip`：tooltip 只包图标（22/26 宽），
        //   按钮本身的点击区才是 chrome 占宽（实测 40）。
        tester
            .getSize(
              find.ancestor(
                of: find.byTooltip('调课管理'),
                matching: find.byType(IconButton),
              ),
            )
            .width,
        ScheduleTitleBar.actionWidth,
        reason: '实测宽必须等于 chrome 口径用的常量，否则 fitsOneRow 会算错',
      );
      expect(
        tester
            .getSize(
              find.ancestor(
                of: find.byTooltip('刷新'),
                matching: find.byType(IconButton),
              ),
            )
            .width,
        ScheduleTitleBar.actionWidth,
      );
      // 图标也要比 M3 默认的 24 小（用户说的「过大」主要是图标观感）。
      // `Icon.size` 为 null（尺寸来自 IconButton 注入的 IconTheme）→ 读 IconTheme。
      expect(
        IconTheme.of(tester.element(find.byIcon(Icons.event_repeat))).size,
        18,
        reason: '紧凑档图标 18（桌面档 20），都不是默认 24',
      );
      expect(
        IconTheme.of(tester.element(find.byIcon(Icons.refresh))).size,
        20,
      );
      expect(
        ScheduleTitleBar.chromeWidthFor(actionCount: 2),
        56.0 + 2 * ScheduleTitleBar.actionWidth,
      );
      expect(ScheduleTitleBar.actionWidth, lessThan(48.0), reason: '必须小于默认 48');
    });
  });
}
