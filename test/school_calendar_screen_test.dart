import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarter_jxufe/features/school_calendar/data/calendar_prefs.dart';
import 'package:smarter_jxufe/features/school_calendar/data/providers/calendar_prefs_providers.dart';
import 'package:smarter_jxufe/features/school_calendar/data/providers/school_calendar_providers.dart';
import 'package:smarter_jxufe/features/school_calendar/data/providers/wxcal_providers.dart';
import 'package:smarter_jxufe/features/school_calendar/data/wxcal_repository.dart';
import 'package:smarter_jxufe/features/school_calendar/data/anti_corruption/school_calendar_html_parser.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/calendar_day_mark.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/school_calendar.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/wxcal_semester.dart';
import 'package:smarter_jxufe/features/school_calendar/presentation/school_calendar_screen.dart';

/// 校历页「假/班」角标的**真实渲染**测试。
///
/// 用抓取自教务的 2026-2027 第一学期真实 HTML（`test/fixtures/_cal_261_xq0.html`）
/// 与真实小程序官方安排快照渲染整页，断言：
/// 1. 三种角标风格都不产生布局异常（溢出在 widget 测试里会直接失败）；
/// 2. 角标数量与逐日核对结果一致（等价于网页原型的 DOM 核对）。
void main() {
  final calendar = SchoolCalendarHtmlParser().parse(
    File('test/fixtures/_cal_261_xq0.html').readAsStringSync(),
    xn: 2026,
    xq: 0,
  );

  /// 261 学期的官方安排（内置快照里的最后一条）。
  final terms = <WxSemesterArrangement>[
    for (final t in wxcalOfflineToDomain())
      if (t.term == '252' || t.term == '261') t,
  ];

  /// 2026 级本科生视角（与网页原型核对时一致）。
  const viewer = CalendarViewer(enrollYear: 2026, trainLevel: '本科');

  Widget app({CalendarViewer who = viewer, CalendarDisplayPrefs? prefs}) =>
      ProviderScope(
        overrides: [
          schoolCalendarProvider((
            xn: 2026,
            xq: 0,
          )).overrideWith((ref) async => calendar),
          wxArrangementsProvider.overrideWith((ref) async => terms),
          wxGuidProvider.overrideWith((ref) async => null),
          calendarViewerProvider.overrideWith((ref) async => who),
          // initial 给定的 store 不读也不写 Hive，测试无需初始化存储。
          calendarPrefsStoreProvider.overrideWith(
            (ref) => CalendarPrefsStore(initial: prefs),
          ),
        ],
        child: const MaterialApp(home: SchoolCalendarScreen()),
      );

  Future<void> pumpTall(WidgetTester tester, Widget widget) async {
    // 拉高视口：让 5 张月历卡全部构建（ListView 懒构建，默认 600px 只出第一张）。
    tester.view.physicalSize = const Size(1100, 4200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();
  }

  int count(String text) => find.text(text).evaluate().length;

  test('fixture 覆盖 2026-09 ~ 2027-01 五个月', () {
    expect(calendar.months.map((m) => m.label), [
      '2026-09',
      '2026-10',
      '2026-11',
      '2026-12',
      '2027-01',
    ]);
    // 教务标注确实被解析出来了（否则角标兜底失效）
    // 2026-09-01 是周二 → 该行周一格为空，9/1 落在第 2 格（index 1）。
    final sep = calendar.months.first;
    expect(sep.rows.first.days[1], 1);
    expect(sep.rows.first.kindAt(1), CalendarDayKind.nonday); // 9/1 暑假
  });

  testWidgets('默认风格（数字下方小字）渲染的角标数量正确', (tester) async {
    await pumpTall(tester, app());

    // 页面底部图例各 1 个：假 / 班 / 运
    expect(count('假'), 33 + 1, reason: '暑假6 + 中秋3 + 国庆7 + 元旦1 + 寒假16');
    expect(count('军'), 15, reason: '新生军训 9/7~9/21（本人 2026 级）');
    expect(count('教'), 3, reason: '新生入学、专业教育 9/22~9/24');
    expect(count('班'), 1 + 1, reason: '补第4周周五的课 10/10');
    expect(count('运'), 3 + 1, reason: '运动会 10/29~10/31');
    expect(count('考'), 14, reason: '期中考试 2 + 本科生期末考核 12（研究生考核已过滤）');
    expect(tester.takeException(), isNull);
  });

  testWidgets('学籍缺失时不显示军训，也不做人群过滤', (tester) async {
    await pumpTall(tester, app(who: CalendarViewer.unknown));

    expect(count('军'), 0);
    // 不过滤时「考」= 期中考试 2（11/7~8）+ 本科生期末 12（1/4~15）
    // + 研究生独有 5（12/29、12/30、12/31、1/2、1/3；1/1 元旦优先，1/4~8 与本科重叠）
    expect(count('考'), 19);
    expect(tester.takeException(), isNull);
  });

  testWidgets('右上角角标风格同样完整渲染（行高不变）', (tester) async {
    await pumpTall(
      tester,
      app(
        prefs: const CalendarDisplayPrefs(
          badgeStyle: CalendarBadgeStyle.cornerTag,
        ),
      ),
    );

    expect(count('假'), 33 + 1);
    expect(count('班'), 1 + 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('整格淡色底风格同样完整渲染', (tester) async {
    await pumpTall(
      tester,
      app(
        prefs: const CalendarDisplayPrefs(
          badgeStyle: CalendarBadgeStyle.filledCell,
        ),
      ),
    );

    expect(count('假'), 33 + 1);
    expect(count('班'), 1 + 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('设置：关掉人群过滤后研究生考核周也显示「考」', (tester) async {
    await pumpTall(
      tester,
      app(prefs: const CalendarDisplayPrefs(filterByCategory: false)),
    );

    expect(count('考'), 19); // 口径同上：研究生考核周也显示
    expect(tester.takeException(), isNull);
  });

  testWidgets('设置：勾上「非新生也显示军训」后 2025 级也能看到军训', (tester) async {
    await pumpTall(
      tester,
      app(
        who: const CalendarViewer(enrollYear: 2025, trainLevel: '本科'),
        prefs: const CalendarDisplayPrefs(alwaysShowMilitary: true),
      ),
    );

    expect(count('军'), 15);
    expect(tester.takeException(), isNull);
  });

  testWidgets('点击带角标的日期弹出当日安排详情', (tester) async {
    await pumpTall(tester, app());

    // 第一个「假」角标 = 2026-09-01（暑假，由 252 学期「暑假开始」推导）。
    await tester.tap(find.text('假').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('官方放假'), findsWidgets);
    expect(find.textContaining('暑假'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
