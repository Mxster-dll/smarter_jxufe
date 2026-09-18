/// 侧栏（左侧导航栏）视图的**页面 chrome 口径**守卫 —— 用户 2026-09-16 裁定：
/// 侧栏模式下每个服务页自己的导航栏一律不画，原按钮下沉到页面内容顶部。
///
/// 三档行为（见 `lib/design/pane_chrome.dart` 与 AGENTS.md §19）：
/// 1. 内嵌在右侧面板**首路由**（真正的服务主页）→ 不画导航栏、按钮下沉；
/// 2. 面板内压栈的**二级页** → 照旧完整导航栏（含返回键），按钮留在导航栏；
/// 3. 整页模式（宫格 push / 独立页面）→ 与从前完全一致。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/design/pane_chrome.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/schedule_title_bar.dart';
import 'package:smarter_jxufe/features/settings/domain/settings_section.dart';

/// 与生产页面同构的最小页面：`paneAppBar` + `PaneBody`。
///
/// 课表页是唯一传 [settingsSections] 的页面（见 `scheduleSettingsSections`），
/// 两条链路共用同一份清单 —— 整页模式由 `paneAppBar` 追加齿轮，内嵌模式由
/// `PaneBody` 在**已有**工具条行尾补一个。
class _ServicePage extends StatelessWidget {
  const _ServicePage({required this.title, this.settingsSections = const []});

  final String title;
  final List<SettingsSection> settingsSections;

  List<Widget> _actions() => [
    IconButton(
      tooltip: '刷新',
      icon: const Icon(Icons.refresh),
      onPressed: () {},
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: paneAppBar(
        context,
        title: Text(title),
        actions: _actions(),
        settingsSections: settingsSections,
      ),
      body: PaneBody(
        actions: _actions(),
        settingsSections: settingsSections,
        child: const Text('页面内容'),
      ),
    );
  }
}

/// 没有自己的按钮、也没有行首控件的服务页（校历、材料库这类）：
/// 内嵌模式下**不该**出现任何横向 chrome。
class _NoActionPage extends StatelessWidget {
  const _NoActionPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: paneAppBar(context, title: const Text('无按钮页')),
      body: const PaneBody(child: Text('页面内容')),
    );
  }
}

/// 面板宿主：`PaneScope(embedded: true)` 包一个独立 Navigator，路由栈由 [routes] 给定。/// 传两个路由 = 页面是二级页（`canPop() == true`）。
Widget _paneHost(List<Widget> routes) => MaterialApp(
  home: PaneScope(
    embedded: true,
    child: Navigator(
      onGenerateInitialRoutes: (navigator, initialRoute) => [
        for (final r in routes) MaterialPageRoute<void>(builder: (_) => r),
      ],
      onGenerateRoute: (_) =>
          MaterialPageRoute<void>(builder: (_) => routes.last),
    ),
  ),
);

/// 服务页源码（`paneAppBar` 必须替代裸 `AppBar(`）。
const List<String> _servicePages = [
  'lib/features/campus_address/presentation/campus_address_screen.dart',
  'lib/features/campus_address/presentation/campus_map_screen.dart',
  'lib/features/comprehensive_service/presentation/volunteer_hours_screen.dart',
  'lib/features/comprehensive_service/presentation/second_class_credit_screen.dart',
  'lib/features/comprehensive_service/presentation/jh_read_screen.dart',
  'lib/features/data_center/presentation/data_center_screen.dart',
  'lib/features/electricity/presentation/electricity_screen.dart',
  'lib/features/net_fee/presentation/net_fee_screen.dart',
  'lib/features/leave/presentation/leave_screen.dart',
  'lib/features/zongce/presentation/zongce_screen.dart',
  'lib/features/score_estimate/presentation/score_estimate_screen.dart',
  'lib/features/tice/presentation/tice_screen.dart',
  'lib/features/materials/presentation/materials_screen.dart',
  'lib/features/school_calendar/presentation/school_calendar_screen.dart',
  'lib/features/rules/presentation/rules_home_screen.dart',
  'lib/features/ims/splash/presentation/ims_splash_screen.dart',
  'lib/features/ims/public_query/presentation/public_query_screen.dart',
  'lib/features/ims/course_selection/presentation/course_selection_screen.dart',
  'lib/features/ims/schedule/presentation/schedule_screen.dart',
  'lib/features/ims/menu/presentation/ims_tab_container.dart',
];

/// 原导航栏带按钮、因而必须把按钮搬到内容里的页面。
///
/// ⚠ 校历页不在表里：它**本来就没有自己的按钮**（旧版把全局设置按钮注入了下沉行，
/// 于是凭空多出一条只有齿轮的 44px 行 —— 用户 2026-09-16 二轮否掉，见
/// `settings_entry_test.dart` 的反向守卫）。
const Map<String, String> _pagesWithActions = {
  'lib/features/comprehensive_service/presentation/volunteer_hours_screen.dart':
      'PaneBody(',
  'lib/features/ims/public_query/presentation/public_query_screen.dart':
      'PaneBody(',
  'lib/features/score_estimate/presentation/score_estimate_screen.dart':
      'PaneBody(',
  'lib/features/ims/course_selection/presentation/course_selection_screen.dart':
      'PaneActionRow(',
  'lib/features/ims/schedule/presentation/schedule_screen.dart': 'PaneBody(',
  'lib/features/ims/menu/presentation/ims_tab_container.dart': 'PaneBody(',
};

String _code(String path) {
  final raw = File(path).readAsStringSync();
  // 去掉整行注释，避免文档注释里的示例文本命中守卫。
  return raw
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');
}

/// [paneAppBar] 调用里是否出现 [needle]（在调用点后 600 字符内找）。
bool _paneAppBarHas(String src, String needle) {
  for (final m in RegExp(r'paneAppBar\(').allMatches(src)) {
    final window = src.substring(m.start, (m.start + 600).clamp(0, src.length));
    if (window.contains(needle)) return true;
  }
  return false;
}

void main() {
  testWidgets('内嵌首路由：整条导航栏不画，按钮下沉到内容', (tester) async {
    await tester.pumpWidget(_paneHost(const [_ServicePage(title: '校历')]));

    expect(find.byType(AppBar), findsNothing, reason: '面板首路由不该有导航栏');
    expect(find.text('校历'), findsNothing, reason: '标题也不画（侧栏已高亮）');
    expect(find.text('页面内容'), findsOneWidget);
    expect(find.byTooltip('刷新'), findsOneWidget, reason: '按钮必须在内容里');
    expect(find.byType(PaneActionRow), findsOneWidget);
  });

  testWidgets('整页模式：AppBar 与从前完全一致，内容里不重复渲染按钮', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _ServicePage(title: '校历')));

    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('校历'), findsOneWidget);
    expect(find.byTooltip('刷新'), findsOneWidget, reason: '只有 AppBar 里那一个');
    expect(find.byType(PaneActionRow), findsNothing);
  });

  testWidgets('面板内二级页：保留完整导航栏与返回键，按钮不搬家', (tester) async {
    await tester.pumpWidget(
      _paneHost(const [SizedBox.shrink(), _ServicePage(title: '课程详情')]),
    );

    expect(find.byType(AppBar), findsOneWidget, reason: '二级页照旧有导航栏');
    expect(find.text('课程详情'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget, reason: '二级页必须有返回键');
    expect(find.byTooltip('刷新'), findsOneWidget);
    expect(find.byType(PaneActionRow), findsNothing);
  });

  testWidgets('内嵌页声明 settingsSections：齿轮补在既有工具条行尾', (tester) async {
    // 用户 2026-09-17：「课表页的设置按钮不见了」—— 内嵌模式没有 AppBar，
    // 而齿轮只由 `paneAppBar` 注入，于是这个入口整个消失。修法 = 在**本来就有**
    // 工具条的行尾补一个（不新增横条，不违反二轮裁定）。
    await tester.pumpWidget(
      _paneHost(
        const [
          _ServicePage(
            title: '课表',
            settingsSections: [SettingsSection.schedule],
          ),
        ],
      ),
    );

    expect(find.byType(AppBar), findsNothing, reason: '内嵌首路由照旧不画导航栏');
    expect(find.byType(PaneActionRow), findsOneWidget, reason: '只有一条工具条');
    expect(find.byTooltip('设置'), findsOneWidget, reason: '齿轮必须回到这行上');
    expect(find.byTooltip('刷新'), findsOneWidget);
    // 齿轮在行尾（刷新按钮右侧）。
    final gear = tester.getTopLeft(find.byTooltip('设置')).dx;
    final refresh = tester.getTopLeft(find.byTooltip('刷新')).dx;
    expect(gear, greaterThan(refresh), reason: '设置按钮固定在行尾');
  });

  testWidgets('内嵌页不声明 settingsSections：照旧没有齿轮', (tester) async {
    await tester.pumpWidget(_paneHost(const [_ServicePage(title: '校历')]));

    expect(find.byTooltip('设置'), findsNothing, reason: '默认不注入');
    expect(find.byTooltip('刷新'), findsOneWidget);
  });

  testWidgets('空行 + settingsSections：整行仍不画，不会凭空多一条只有齿轮的横条', (tester) async {
    await tester.pumpWidget(
      _paneHost(
        const [
          Scaffold(
            body: PaneBody(
              settingsSections: [SettingsSection.schedule],
              child: Text('页面内容'),
            ),
          ),
        ],
      ),
    );

    expect(find.byType(PaneActionRow), findsOneWidget);
    expect(
      find.byTooltip('设置'),
      findsNothing,
      reason: '二轮红线：没有工具条的页面不许因为齿轮多出一条 44px 横条',
    );
    expect(tester.getSize(find.byType(PaneActionRow)), Size.zero);
  });

  testWidgets('整页模式 + settingsSections：齿轮只有 AppBar 里那一个（不重复）', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: _ServicePage(
          title: '课表',
          settingsSections: [SettingsSection.schedule],
        ),
      ),
    );

    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byType(PaneActionRow), findsNothing);
    expect(find.byTooltip('设置'), findsOneWidget, reason: '不能注入两次');
  });

  testWidgets('PaneActionRow 的行首控件（选课页签 / 课表选择器）与按钮同行', (tester) async {
    await tester.pumpWidget(
      _paneHost([
        Scaffold(
          body: PaneBody(
            leading: const Text('学期选择器'),
            actions: [
              IconButton(
                tooltip: '刷新',
                icon: const Icon(Icons.refresh),
                onPressed: () {},
              ),
            ],
            child: const Text('页面内容'),
          ),
        ),
      ]),
    );

    expect(find.text('学期选择器'), findsOneWidget);
    expect(find.byTooltip('刷新'), findsOneWidget);
    final row = tester.widget<PaneActionRow>(find.byType(PaneActionRow));
    expect(row.height, PaneActionRow.defaultHeight);
  });

  testWidgets('PaneScope 之外 paneEmbedded 恒为 false', (tester) async {
    late bool embedded;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            embedded = paneEmbedded(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(embedded, isFalse);
  });

  test('20 个服务页一律走 paneAppBar（不再裸写 appBar: AppBar）', () {
    for (final path in _servicePages) {
      final src = _code(path);
      expect(src, contains('paneAppBar('), reason: '$path 必须用 paneAppBar');
      expect(
        src,
        contains('design/pane_chrome.dart'),
        reason: '$path 必须 import pane_chrome',
      );
    }
  });

  test('除材料库的页内二级页外，服务页不得再出现 appBar: AppBar(', () {
    for (final path in _servicePages) {
      final src = _code(path);
      final bare = RegExp(r'appBar: AppBar\(').allMatches(src).length;
      if (path.endsWith('materials_screen.dart')) {
        // 材料库文件里另有「选择活动类型」「专业规格」两个**页内二级页**，
        // 它们不是服务主页，照旧保留自己的导航栏。
        expect(bare, 2, reason: '材料库只该剩两个二级页 AppBar，实为 $bare');
      } else {
        expect(bare, 0, reason: '$path 还留着裸 AppBar（应为 paneAppBar）');
      }
    }
  });

  test('服务页标题仍按原样传给 paneAppBar（内嵌时才被吞掉）', () {
    const titles = {
      'lib/features/campus_address/presentation/campus_address_screen.dart':
          "'学校地址'",
      'lib/features/campus_address/presentation/campus_map_screen.dart':
          "'校区地图'",
      'lib/features/comprehensive_service/presentation/volunteer_hours_screen.dart':
          "'学生活动时长统计'",
      'lib/features/comprehensive_service/presentation/second_class_credit_screen.dart':
          "'第二课堂学分'",
      'lib/features/comprehensive_service/presentation/jh_read_screen.dart':
          "'蛟湖阅读'",
      'lib/features/data_center/presentation/data_center_screen.dart':
          "'学生个人数据中心'",
      'lib/features/electricity/presentation/electricity_screen.dart': "'宿舍电费'",
      'lib/features/net_fee/presentation/net_fee_screen.dart': "'校园网'",
      'lib/features/leave/presentation/leave_screen.dart': "'请假'",
      'lib/features/zongce/presentation/zongce_screen.dart': "'综合测评'",
      'lib/features/score_estimate/presentation/score_estimate_screen.dart':
          "'分数估计'",
      'lib/features/tice/presentation/tice_screen.dart': "'体测成绩'",
      'lib/features/materials/presentation/materials_screen.dart': "'材料库'",
      'lib/features/school_calendar/presentation/school_calendar_screen.dart':
          "'校历'",
      'lib/features/rules/presentation/rules_home_screen.dart': "'规章制度'",
      'lib/features/ims/splash/presentation/ims_splash_screen.dart': "'教务会话'",
      'lib/features/ims/public_query/presentation/public_query_screen.dart':
          "'公共查询'",
      'lib/features/ims/course_selection/presentation/course_selection_screen.dart':
          "'选课'",
    };
    titles.forEach((path, title) {
      expect(
        _paneAppBarHas(_code(path), title),
        isTrue,
        reason: '$path 的 paneAppBar 里没找到标题 $title',
      );
    });
    // 课表页的标题槽是选择器本身（不是「课表」二字），容器页是 tab 标题。
    final schedule = _code(
      'lib/features/ims/schedule/presentation/schedule_screen.dart',
    );
    expect(_paneAppBarHas(schedule, 'title: titleBar'), isTrue);
    final container = _code(
      'lib/features/ims/menu/presentation/ims_tab_container.dart',
    );
    expect(_paneAppBarHas(container, 'Text(_currentTab.title)'), isTrue);
  });

  test('带按钮的服务页都把按钮搬进了内容（PaneBody / PaneActionRow）', () {
    _pagesWithActions.forEach((path, needle) {
      final src = _code(path);
      expect(src, contains(needle), reason: '$path 缺少按钮下沉载体 $needle');
      expect(src, contains('actions:'), reason: '$path 下沉后必须仍把 actions 传下去');
    });
  });

  test('齿轮只在两处注入，且空行整条不画（2026-09-16 二轮 + 2026-09-17 课表补给）', () {
    final chrome = _code('lib/design/pane_chrome.dart');
    // ① `paneAppBar`（整页模式，无条件追加）；
    // ② `PaneActionRow`（侧栏内嵌模式，仅在页面声明了 settingsSections **且本行
    //    本来就有内容**时追加）—— 用户 2026-09-17：「课表页的设置按钮不见了」，
    //    内嵌模式没有 AppBar，齿轮从前整个消失。
    expect(
      'SettingsActionButton('.allMatches(chrome).length,
      2,
      reason: '再多一处就会重复渲染齿轮；一处都没有则「永远显示设置按钮」不成立',
    );
    expect(
      chrome.contains('actions.isEmpty && leading == null'),
      isTrue,
      reason: '没有任何内容的下沉行必须整条不画',
    );
    // 注入排在空行早退**之后**：只有齿轮的横条 = 用户 2026-09-16 否掉的那种。
    final emptyGuard = chrome.indexOf('if (actions.isEmpty && leading == null)');
    expect(
      chrome.indexOf('if (settingsSections.isNotEmpty)'),
      greaterThan(emptyGuard),
      reason: '空行不得因为齿轮变成一条 44px 横条',
    );
  });

  testWidgets('内嵌服务主页：没有按钮也没有行首控件 → 不出现空白横条', (tester) async {
    await tester.pumpWidget(_paneHost(const [_NoActionPage()]));

    // 面板首路由不画导航栏（标题自然也不在），内容照常渲染。
    expect(find.text('页面内容'), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    expect(
      tester.getSize(find.byType(PaneActionRow)),
      Size.zero,
      reason: '空的下沉行必须零尺寸（否则就是用户说的「凭空多了一个标题栏」）',
    );
  });

  test('HomeDetailPane 提供 PaneScope(embedded: true)', () {
    final src = _code('lib/features/home/presentation/home_detail_pane.dart');
    expect(src, contains('PaneScope('));
    expect(src, contains('embedded: true'));
  });

  // ---------------------------------------------------------------------------
  // 课表页的学期选择器要按**真实行宽**判单行/两行（`ScheduleTitleBar` 内部按
  // `MediaQuery` 宽度算），内嵌时那里的窗口宽 ≠ 面板行宽 → 生产代码用
  // `_paneTitleBar` 把行宽喂进去。下面两例一正一反，缺了修正就必挂。
  // ---------------------------------------------------------------------------

  testWidgets('内嵌面板：课表标题栏按面板行宽判定，放不下就换两行且不溢出', (tester) async {
    final need = await _measureTitleBarNeed(tester);
    // 窗口宽到「窗口 − chrome」远超需要宽度 → 不修正的话内部一定误判成单行。
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(
      need + ScheduleTitleBar.chromeWidth + 100,
      800,
    );
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const Center(
        child: SizedBox(
          width: 320, // 行首槽位 ≈ 320 − 24(行内边距) − 48(刷新键) ≈ 248
          child: _PaneHostWith(
            routes: [_ScheduleLikePage(fitToPaneWidth: true)],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull, reason: '喂了真实行宽 → 应换两行，不溢出');
    expect(
      tester.getSize(find.byKey(scheduleTitleContentKey)).width,
      lessThan(need - 40),
      reason: '内容宽度必须真的降下来（= 判定成了两行）',
    );
  });

  testWidgets('反证：不喂真实行宽时同一行宽会溢出（修正不可缺）', (tester) async {
    final need = await _measureTitleBarNeed(tester);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(
      need + ScheduleTitleBar.chromeWidth + 100,
      800,
    );
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const Center(
        child: SizedBox(
          width: 320,
          child: _PaneHostWith(
            routes: [_ScheduleLikePage(fitToPaneWidth: false)],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      tester.takeException(),
      isNotNull,
      reason: '不喂行宽就会按窗口宽判定成单行、塞进 248px 的槽位 → 必须溢出',
    );
  });

  test('课表页把真实行宽喂给标题栏，且行高交给内容撑', () {
    final src = _code(
      'lib/features/ims/schedule/presentation/schedule_screen.dart',
    );
    expect(src, contains('_paneTitleBar('), reason: '缺了行宽修正');
    expect(
      src,
      contains('ScheduleTitleBar.chromeWidth'),
      reason: '按 chrome 抵消内部减法',
    );
    expect(src, contains('height: null'), reason: '行高不能写死（单行/两行由内容定）');
  });
}

/// 量出课表标题栏「排成一行」需要的宽度（与生产同一套字形口径）。
Future<double> _measureTitleBarNeed(WidgetTester tester) async {
  late double need;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          need = ScheduleTitleBar.rowNeed(
            context,
            compact: false,
            isCurrentTerm: true,
            currentWeek: 3,
            week: 3,
          );
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  expect(need, greaterThan(300), reason: '前提：需要宽度要明显大于测试行宽 248');
  return need;
}

/// [_paneHost] 的可内联版本（测试里要放进固定宽度的盒子里量行宽）。
class _PaneHostWith extends StatelessWidget {
  const _PaneHostWith({required this.routes});

  final List<Widget> routes;

  @override
  Widget build(BuildContext context) => _paneHost(routes);
}

/// 与生产课表页同构：`PaneBody` + 学期选择器当 `leading` + 两个按钮。
class _ScheduleLikePage extends StatelessWidget {
  const _ScheduleLikePage({required this.fitToPaneWidth});

  /// true = 生产写法（把真实行宽喂进去）；false = 修正前写法（直接塞标题栏）。
  final bool fitToPaneWidth;

  ScheduleTitleBar _titleBar() => ScheduleTitleBar(
    selectedYear: 2026,
    selectedSemester: '0',
    week: 3,
    currentWeek: 3,
    isCurrentTerm: true,
    compact: false,
    pickerStartYear: 2025,
    pickerEndYear: 2027,
    onYearChanged: (_) {},
    onSemesterChanged: (_) {},
    onTermPicked: (_) {},
    onGoToWeek: (_) {},
    // 视图切换按钮已移进 `actions`（2026-09-16 用户裁定），标题栏只关心
    // 右侧有几个按钮。
    actionCount: 2,
  );

  @override
  Widget build(BuildContext context) {
    final bar = _titleBar();
    return Scaffold(
      body: PaneBody(
        leading: fitToPaneWidth
            ? LayoutBuilder(
                builder: (context, constraints) {
                  final media = MediaQuery.of(context);
                  return MediaQuery(
                    data: media.copyWith(
                      size: Size(
                        constraints.maxWidth + ScheduleTitleBar.chromeWidth,
                        media.size.height,
                      ),
                    ),
                    child: bar,
                  );
                },
              )
            : bar,
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: () {},
          ),
        ],
        height: null,
        child: const Text('页面内容'),
      ),
    );
  }
}
