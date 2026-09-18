/// 全局设置入口（用户 2026-09-16 裁定）的守卫。
///
/// 需求原话：「我希望标题栏右上角永远显示一个设置按钮，只不过在主页点进去，直接
/// 进设置页，在不同的页面进入，也是进设置页，但是只显示此部分的设置项」。
/// 后续 ask 拍板：①范围 = **所有服务主页**（二级页不加）；②映射 = 提案映射，
/// 没有对应设置节的页面当主页一样进**完整设置页**。
///
/// 这里守两件事：
/// 1. `SettingsScreen(sections: […])` 真的只渲染该节（标题 + 卡片），AppBar 标题
///    也变成该节名；空列表 = 完整设置页（九节齐全）。
/// 2. 按钮是**自动注入**的：`paneAppBar` 会把 `SettingsActionButton` 追加到 actions
///    末尾（源码守卫，防止有人把它删掉导致「永远显示」失效）。
///
/// ⚠ 2026-09-16 二轮（用户：「你的设置添加导致不少页面凭空多了一个标题栏，我希望
/// 下沉到内容里」）：注入**只在 `paneAppBar`**；`PaneActionRow` / `PaneBody` 不得再塞
/// 齿轮，且没有任何内容的下沉行必须整条不画 —— 桌面端设置入口改到左侧导航栏底部
/// 固定区（`home_sidebar.dart` 的 `homeSidebarSettingsKey`）。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/features/settings/domain/settings_section.dart';
import 'package:smarter_jxufe/features/settings/presentation/settings_entry.dart';
import 'package:smarter_jxufe/features/settings/presentation/settings_screen.dart';

/// 设置页会读若干 Hive 偏好 box（校区 / 校历 / 入馆教育 / 主页布局），
/// 测试里必须真初始化一个临时目录，否则 `HiveError` 会以未处理异步异常冒出来。
Future<Directory> _initHive() async {
  final dir = Directory.systemTemp.createTempSync('settings_entry_test');
  Hive.init(dir.path);
  for (final name in const [
    'myCampusPrefs',
    'schoolCalendarPrefs',
    'tsgxsPrefs',
    'homeLayoutPrefs',
    'wxPlatform',
  ]) {
    await Hive.openBox<String>(name);
  }
  return dir;
}

Widget _app(Widget child) => ProviderScope(
  child: MaterialApp(
    theme: ThemeData(useMaterial3: true),
    home: child,
  ),
);

void main() {
  late Directory hiveDir;

  setUpAll(() async {
    hiveDir = await _initHive();
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      hiveDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('分节枚举：label 与设置页里的节标题一致', () {
    // 节数不写死：并行工作流 2026-09-16 又加了 appearance('外观')（深色模式），
    // 这里只要求「这九个业务节都在」。
    final labels = SettingsSection.values.map((s) => s.label).toList();
    expect(labels, containsAll(const [
      '校区',
      '生效范围',
      '主页布局',
      '校历',
      '入馆教育',
      '平台标识',
      '上课实况窗',
      '教务会话',
      '云同步',
      '桌面小组件',
    ]));
    expect(SettingsSection.campus.label, '校区');
    expect(SettingsSection.calendar.label, '校历');
  });

  testWidgets('只给一节 → 只渲染该节，标题栏用节名', (tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(const SettingsScreen(sections: [SettingsSection.calendar])),
    );
    await tester.pumpAndSettle();

    // 标题栏 = 节名（不是「设置」）。
    expect(find.text('校历'), findsWidgets);
    expect(find.text('设置'), findsNothing);
    // 该节的卡片在（角标风格是「校历」节里的唯一子项）。
    expect(find.text('角标风格'), findsOneWidget);
    // 其它节一个都不在。
    for (final label in const ['校区', '生效范围', '主页布局', '平台标识', '桌面小组件']) {
      expect(find.text(label), findsNothing, reason: '「$label」节不该出现');
    }
  });

  testWidgets('多节 → 只渲染这几节，标题仍为「设置」', (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(
        const SettingsScreen(
          sections: [SettingsSection.imsSession, SettingsSection.liveClass],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('设置'), findsOneWidget); // AppBar 标题
    expect(find.text('上课实况窗'), findsWidgets); // 节标题 + 卡片内可能再提一次
    expect(find.text('校区'), findsNothing);
  });

  testWidgets('不给 sections → 完整设置页（每节标题都在）', (tester) async {
    // 视口给足：ListView 惰性构建，矮视口下靠后的节根本不在树上。
    tester.view.physicalSize = const Size(1400, 7000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(const SettingsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('设置'), findsOneWidget);
    for (final s in SettingsSection.values) {
      expect(find.text(s.label), findsWidgets, reason: '缺少「${s.label}」节');
    }
  });

  testWidgets('设置按钮：点一下进设置页，并按 sections 过滤', (tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(
        Scaffold(
          appBar: AppBar(
            title: const Text('某服务页'),
            actions: const [
              SettingsActionButton(sections: [SettingsSection.platformGuid]),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('设置'), findsOneWidget);
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();

    // 进的是设置页，且只显示「平台标识」节。
    expect(find.text('微信平台标识（GUID）'), findsOneWidget);
    expect(find.text('角标风格'), findsNothing);
  });

  group('源码守卫：按钮自动注入 + 逐页映射', () {
    String read(String path) => File(path).readAsStringSync();

    test('paneAppBar 自动追加设置按钮；下沉行只在「本来就有工具条」时补一个', () {
      final chrome = read('lib/design/pane_chrome.dart');
      expect(
        chrome.contains('SettingsActionButton('),
        isTrue,
        reason: 'pane_chrome 必须在 actions 末尾追加设置按钮，「永远显示」才成立',
      );
      // 两处：① `paneAppBar`（整页模式）；② `PaneActionRow`（侧栏内嵌模式 ——
      // 用户 2026-09-17「课表页的设置按钮不见了」：内嵌模式没有 AppBar，齿轮
      // 从前整个消失）。
      expect(
        'SettingsActionButton('.allMatches(chrome).length,
        2,
        reason: '注入只允许这两处；再多一处就会重复渲染齿轮',
      );
      expect(chrome.contains('settingsSections'), isTrue);
      // 内嵌侧的红线仍是「**空**行不许塞齿轮」：注入必须排在那道早退之后。
      final emptyGuard = chrome.indexOf('if (actions.isEmpty && leading == null)');
      final inlineInject = chrome.indexOf(
        'if (settingsSections.isNotEmpty)',
      );
      expect(emptyGuard, greaterThan(-1));
      expect(
        inlineInject,
        greaterThan(emptyGuard),
        reason: '只有齿轮的空行 = 用户 2026-09-16 否掉的「凭空多一条横条」',
      );
    });

    test('页面各自声明相关的设置节', () {
      // 页面 → 应声明的节（用户 2026-09-16 拍板的映射）。
      const expected = <String, List<String>>{
        'lib/features/school_calendar/presentation/school_calendar_screen.dart': [
          'SettingsSection.calendar',
        ],
        'lib/features/comprehensive_service/presentation/jh_read_screen.dart': [
          'SettingsSection.libraryEdu',
        ],
        'lib/features/net_fee/presentation/net_fee_screen.dart': [
          'SettingsSection.platformGuid',
        ],
        'lib/features/leave/presentation/leave_screen.dart': [
          'SettingsSection.platformGuid',
        ],
        'lib/features/data_center/presentation/data_center_screen.dart': [
          'SettingsSection.platformGuid',
        ],
        'lib/features/ims/menu/presentation/ims_tab_container.dart': [
          'SettingsSection.imsSession',
        ],
        'lib/features/ims/public_query/presentation/public_query_screen.dart': [
          'SettingsSection.imsSession',
        ],
        'lib/features/ims/course_selection/presentation/course_selection_screen.dart':
            ['SettingsSection.imsSession'],
        'lib/features/score_estimate/presentation/score_estimate_screen.dart': [
          'SettingsSection.imsSession',
        ],
        'lib/features/campus_address/presentation/campus_address_screen.dart': [
          'SettingsSection.campus',
        ],
        'lib/features/campus_address/presentation/campus_map_screen.dart': [
          'SettingsSection.campus',
        ],
        'lib/features/ims/schedule/presentation/schedule_screen.dart': [
          'SettingsSection.imsSession',
          'SettingsSection.liveClass',
        ],
      };
      expected.forEach((path, sections) {
        final src = read(path);
        expect(
          src.contains('settingsSections'),
          isTrue,
          reason: '$path 应声明 settingsSections',
        );
        for (final s in sections) {
          expect(src.contains(s), isTrue, reason: '$path 应含 $s');
        }
      });
    });

    test('课表的行宽记账把设置按钮算进去（+1）', () {
      final src = read(
        'lib/features/ims/schedule/presentation/schedule_screen.dart',
      );
      expect(
        src.contains('final barActionCount = actions.length + 1;'),
        isTrue,
        reason: 'paneAppBar 会追加一个设置按钮，行宽记账少算一个会算错可用宽度',
      );
      expect(src.contains('actionCount: barActionCount'), isTrue);
    });

    test('课表页两条链路都挂上了齿轮（整页导航栏 + 内嵌工具条）', () {
      // 用户 2026-09-17：「课表页的设置按钮不见了」—— 从前只有 `paneAppBar`
      // 那一处，侧栏内嵌模式没有 AppBar，齿轮就整个消失。同一份清单必须喂给
      // 两条链路，少一处就退回旧 bug。
      final src = read(
        'lib/features/ims/schedule/presentation/schedule_screen.dart',
      );
      expect(
        'settingsSections: scheduleSettingsSections'.allMatches(src).length,
        2,
        reason: 'paneAppBar 与 PaneBody 各要一处',
      );
      expect(
        src.contains('const List<SettingsSection> scheduleSettingsSections'),
        isTrue,
        reason: '清单要唯一（别在两处各写一遍）',
      );
      for (final s in const [
        'SettingsSection.imsSession',
        'SettingsSection.liveClass',
        'SettingsSection.schedule',
      ]) {
        expect(src.contains(s), isTrue, reason: '课表页应含 $s');
      }
    });

    test('校历页不再自带 _settingsAction（按钮统一注入）', () {
      final src = read(
        'lib/features/school_calendar/presentation/school_calendar_screen.dart',
      );
      expect(src.contains('_settingsAction'), isFalse);
    });
  });
}
