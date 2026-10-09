/// 侧栏底部固定区（设置 / 我的）在**右侧内容区**显示的口径。
///
/// 用户 2026-10-09 五轮原话：「我们目前『侧边栏』模式下，设置和我的页都不是在右侧
/// 内容区显示，而是进入一个子页面，我希望与其他功能页统一」。
///
/// 这里守三件事：
/// 1. **装配**：`home_screen.dart` 那两行的 onTap 走 `_selectFooter`（选中右栏），
///    不再 `openSettings` / `push`；页面经跳转缝取（`home` 不许 import 别家页面）。
/// 2. **内嵌 chrome**：设置页 / 我的页走 `paneAppBar` —— 内嵌首路由时整条导航栏不画
///    （与别的内嵌功能页同口径，见 §19）。
/// 3. **行为**：`HomeDetailPane` 把设置页当面板首路由时，注入 `PaneScope(embedded: true)`
///    且页面**没有** AppBar；底部固定区的行有选中态（与目录行同一套观感）。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/core/navigation/service_nav.dart';
import 'package:smarter_jxufe/design/pane_chrome.dart';
import 'package:smarter_jxufe/features/home/presentation/home_detail_pane.dart';
import 'package:smarter_jxufe/features/home/presentation/home_service_catalog.dart';
import 'package:smarter_jxufe/features/home/presentation/home_sidebar.dart';
import 'package:smarter_jxufe/features/settings/presentation/settings_screen.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  group('装配守卫（源码）', () {
    test('侧栏底部两行改成「选中右栏」，不再 push 子页面', () {
      final src = _read('lib/features/home/presentation/home_screen.dart');
      expect(src, contains('_selectFooter(HomeSidebarFooter.profile)'));
      expect(src, contains('_selectFooter(HomeSidebarFooter.settings)'));
      expect(
        src.contains('openSettings(context)'),
        isFalse,
        reason: '侧栏底部不再是「打开设置页」的跳转入口（宫格标题栏那颗还在用 openSettings）',
      );
      expect(src, contains('_selectedFooter'));
      // 两行都要显示选中态（侧栏底部也是右栏内容来源之一）。
      expect(src, contains('selected: footer == HomeSidebarFooter.profile'));
      expect(src, contains('selected: footer == HomeSidebarFooter.settings'));
    });

    test('页面一律经跳转缝取：home 不 import 别家 presentation 页面', () {
      final src = _read('lib/features/home/presentation/home_screen.dart');
      expect(src, contains('serviceScreenBuilder('));
      expect(src, contains('kServiceSettings'));
      expect(src, contains('kServiceStudentInfo'));
      expect(
        src.contains('features/settings/presentation/settings_screen.dart'),
        isFalse,
        reason: 'home → 设置页 这条边 2026-09-20 已收口到跳转缝',
      );
      expect(
        src.contains('features/ims/student_info/presentation'),
        isFalse,
        reason: '「我的」也改走跳转缝（原先直接 import 页面）',
      );
    });

    test('跳转缝提供了「取 builder 不 push」的入口，组装根注册了「我的」', () {
      final seam = _read('lib/core/navigation/service_nav.dart');
      expect(seam, contains('ServiceScreenBuilder? serviceScreenBuilder'));
      expect(seam, contains("const String kServiceStudentInfo"));
      final main = _read('lib/main.dart');
      expect(
        main,
        contains('registerServiceScreen(kServiceStudentInfo'),
        reason: '组装根必须注册「我的」——侧栏右栏要嵌它',
      );
      expect(main, contains('SettingsScreen()'));
    });

    test('设置页 / 我的页的导航栏走 paneAppBar（内嵌时整条不画）', () {
      final settings = _read(
        'lib/features/settings/presentation/settings_screen.dart',
      );
      expect(settings, contains('paneAppBar('));
      expect(
        settings.contains('appBar: AppBar('),
        isFalse,
        reason: '裸 AppBar 在内嵌模式下也会画出来（就是「进了一个子页面」的观感）',
      );
      final mine = _read(
        'lib/features/ims/student_info/presentation/student_info_screen.dart',
      );
      expect(mine, contains('paneAppBar('));
      expect(mine.contains("AppBar(title: const Text('我的')"), isFalse);
    });
  });

  group('行为：内嵌面板', () {
    setUp(() async {
      final dir = Directory.systemTemp.createTempSync('home_pane_test');
      Hive.init(dir.path);
      for (final name in const [
        'myCampusPrefs',
        'schoolCalendarPrefs',
        'tsgxsPrefs',
        'homeLayoutPrefs',
        'windowBarPrefs',
      ]) {
        await Hive.openBox<String>(name);
      }
      addTearDown(() async {
        await Hive.close();
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {}
      });
    });

    testWidgets('设置页当面板首路由：有 PaneScope(embedded) 且整条导航栏不画', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: HomeDetailPane(
                paneKey: 'settings',
                builder: () => const SettingsScreen(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(
        find.byType(AppBar),
        findsNothing,
        reason: '内嵌首路由不画导航栏（§19：侧栏已高亮「设置」，再写一遍是重复信息）',
      );
      // PaneScope 在页面上方，页面自己也能查到（paneIsRoot 才成立）。
      expect(
        paneIsRoot(tester.element(find.byType(SettingsScreen))),
        isTrue,
      );
    });

    testWidgets('面板 id 换人 = 换 Navigator（路由栈天然重置）', (tester) async {
      expect(
        HomeDetailPane.navKeyOfId('settings'),
        isNot(HomeDetailPane.navKeyOfId('profile')),
      );
      expect(
        HomeDetailPane.navKeyOfId('settings').toString(),
        contains('settings'),
      );
    });

    testWidgets('底部固定区的行有选中态（胶囊底色 + 淡描边 + 字重）', (tester) async {
      // ⚠ 2026-10-09 十轮起侧栏选中态改成**圆角胶囊**（`sidebarPillDecoration`）：
      // 不再有左侧指示条 —— 判据 = 胶囊那层的 `color` / `border` 有没有，别再看
      // `border.left`（未选中时 `border` 是 null）。
      Widget row({required bool selected}) => MaterialApp(
        home: Scaffold(
          body: HomeSidebarFooterRow(
            leading: const Icon(Icons.settings_outlined, size: 18),
            label: '设置',
            selected: selected,
            onTap: () {},
          ),
        ),
      );

      BoxDecoration pill() {
        final decorated = tester
            .widgetList<Container>(
              find.ancestor(
                of: find.text('设置'),
                matching: find.byType(Container),
              ),
            )
            .where((c) => c.decoration != null);
        return decorated.first.decoration! as BoxDecoration;
      }

      await tester.pumpWidget(row(selected: false));
      expect(pill().color, isNull, reason: '未选中：没有底色');
      expect(pill().border, isNull, reason: '未选中：没有描边');

      await tester.pumpWidget(row(selected: true));
      expect(pill().color, isNotNull, reason: '选中：有胶囊底色');
      expect(pill().border, isNotNull, reason: '选中：有一圈淡描边');
      expect(pill().borderRadius, isNotNull);
      final text = tester.widget<Text>(find.text('设置'));
      expect(text.style!.fontWeight, FontWeight.w600);
    });

    testWidgets('底部行选中时「数据一览」不再高亮（用户 2026-10-09 五轮报的 bug）', (tester) async {
      // 判据：`selectedTitle == null` 不足以说明「概览被选中」—— 底部固定区的两行
      // 不是目录条目，选中它们时 selectedTitle 也是 null。传 `overviewSelected: false`
      // 之后，侧栏上下一同高亮的情况必须消失。
      Widget sidebar({
        required String? selectedTitle,
        required bool overviewSelected,
      }) => MaterialApp(
        home: Scaffold(
          body: HomeSidebar(
            entries: [
              HomeServiceEntry(
                icon: Icons.book_outlined,
                title: '课程',
                subtitle: '',
                group: HomeServiceGroup.ims,
                accent: const Color(0xFFC3282E),
                builder: () => const SizedBox.shrink(),
                onTap: () {},
              ),
            ],
            selectedTitle: selectedTitle,
            overviewSelected: overviewSelected,
            onOverview: () {},
            onSelect: (_) {},
            footer: const SizedBox.shrink(),
          ),
        ),
      );

      /// 取某一行那层「画胶囊」的装饰（十轮起选中态 = 胶囊底色 + 淡描边）。
      BoxDecoration pillOf(String label) => tester
          .widgetList<Container>(
            find.ancestor(
              of: find.text(label),
              matching: find.byType(Container),
            ),
          )
          .firstWhere((c) => c.decoration != null)
          .decoration! as BoxDecoration;

      bool isHighlighted(String label) => pillOf(label).color != null;

      // ① 概览态：概览高亮、服务行不高亮。
      await tester.pumpWidget(
        sidebar(selectedTitle: null, overviewSelected: true),
      );
      expect(isHighlighted('数据一览'), isTrue);
      expect(isHighlighted('课程'), isFalse);

      // ② 底部行选中（selectedTitle 仍是 null）：**两条都不能亮** —— 概览不亮、服务不亮。
      await tester.pumpWidget(
        sidebar(selectedTitle: null, overviewSelected: false),
      );
      expect(
        isHighlighted('数据一览'),
        isFalse,
        reason: '底部「设置 / 我的」选中时，上方「数据一览」不许留着高亮',
      );
      expect(isHighlighted('课程'), isFalse);

      // ③ 选中某个服务：只有那一行亮。
      await tester.pumpWidget(
        sidebar(selectedTitle: '课程', overviewSelected: false),
      );
      expect(isHighlighted('数据一览'), isFalse);
      expect(isHighlighted('课程'), isTrue);
    });
  });
}

