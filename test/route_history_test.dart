/// 全局路由历史（顶部前进 / 后退）—— 模型语义 + 标题栏按钮 + 跳转缝记录。
///
/// 用户 2026-10-09 原话：「我希望在顶部增加一个全局路由记录前进/后退，就是记录一下页面
/// 跳转，然后我希望可以点击顶部的按钮，实现页面之间的切换」。
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/core/navigation/route_history.dart';
import 'package:smarter_jxufe/core/navigation/service_nav.dart';
import 'package:smarter_jxufe/design/window_title_bar.dart';

void main() {
  group('账本语义（浏览器式：一条线 + 一个游标）', () {
    test('初始为空：两个方向都不可用', () {
      final h = RouteHistory();
      expect(h.isEmpty, isTrue);
      expect(h.index, -1);
      expect(h.canGoBack, isFalse);
      expect(h.canGoForward, isFalse);
      expect(h.goBack(), isFalse);
      expect(h.goForward(), isFalse);
    });

    test('记一笔之后：能后退、不能前进', () {
      final h = RouteHistory();
      var visited = <String>[];
      h.record(RouteHistoryEntry(
        label: '数据一览',
        key: 'pane:数据一览',
        restore: () => visited.add('数据一览'),
      ));
      expect(h.canGoBack, isFalse, reason: '只有一格时后退无处可去');
      expect(h.current?.label, '数据一览');

      h.record(RouteHistoryEntry(
        label: '设置',
        key: 'pane:设置',
        restore: () => visited.add('设置'),
      ));
      expect(h.canGoBack, isTrue);
      expect(h.canGoForward, isFalse);
      expect(visited, isEmpty, reason: 'record 不该自己触发跳转');
    });

    test('后退 / 前进：只移动游标 + 调 restore，不碰 Navigator 栈', () {
      final h = RouteHistory();
      final visited = <String>[];
      for (final label in ['概览', '成绩', '设置']) {
        h.record(RouteHistoryEntry(
          label: label,
          key: 'pane:$label',
          restore: () => visited.add(label),
        ));
      }
      expect(h.index, 2);

      // 语义：`restore` 是**目标那一格**的动作（「把我放回这个状态」），不是「离开当前」。
      expect(h.goBack(), isTrue);
      expect(visited, ['成绩'], reason: '后退 = 回到「成绩」那一格');
      expect(h.index, 1);
      expect(h.current?.label, '成绩');
      expect(h.canGoForward, isTrue);

      expect(h.goForward(), isTrue);
      expect(visited, ['成绩', '设置'], reason: '前进 = 回到「设置」');
      expect(h.canGoForward, isFalse);
    });

    test('回退后再访问 = 分叉（用户 2026-10-09：「从 a 之前访问了 b，回退到 a 再访问 c，就要出现分叉」）', () {
      final h = RouteHistory();
      for (final label in ['A', 'B', 'C']) {
        h.record(RouteHistoryEntry(label: label, key: label, restore: () {}));
      }
      h.goBack(); // 退回 B
      h.goBack(); // 再退回 A
      h.record(RouteHistoryEntry(label: 'D', key: 'D', restore: () {}));

      // ⚠ 与浏览器不同：C 那条尾巴**不删**，D 挂在 A 下面 → A 有两个孩子（B、D）。
      expect(h.entries.map((e) => e.label), ['A', 'B', 'C', 'D']);
      expect(h.current?.label, 'D');
      final aIdx = h.entries.indexWhere((e) => e.label == 'A');
      final dIdx = h.entries.indexWhere((e) => e.label == 'D');
      expect(h.parentIndexOf(dIdx), aIdx, reason: 'D 的父是 A（不是在 C 后面接一条）');
      // 从 A 出发能前进回最近那一支（D）；A 的泳道 0，D 另开一条泳道（图上就是分叉）。
      expect(h.laneOf(aIdx), 0);
      expect(h.laneOf(dIdx), greaterThan(0));
      expect(h.laneCount, greaterThanOrEqualTo(2));
      // C 那一支还在（另一条分支），点它照样回得去。
      final cIdx = h.entries.indexWhere((e) => e.label == 'C');
      expect(h.goTo(cIdx), isTrue);
      expect(h.current?.label, 'C');
    });

    test('同 key 连续记录只留一条（面板来回点不刷屏）', () {
      final h = RouteHistory();
      h.record(RouteHistoryEntry(label: '设置', key: 'pane:设置', restore: () {}));
      h.record(RouteHistoryEntry(label: '设置', key: 'pane:设置', restore: () {}));
      expect(h.entries.length, 1);
      // 换一个 key 再回来 → 是两条（真实来回走动）
      h.record(RouteHistoryEntry(label: '我的', key: 'pane:我的', restore: () {}));
      h.record(RouteHistoryEntry(label: '设置', key: 'pane:设置', restore: () {}));
      expect(h.entries.map((e) => e.label), ['设置', '我的', '设置']);
    });

    test('回不去的那一条：只挡住「进入它」，不挡离开它', () {
      final h = RouteHistory();
      h.record(RouteHistoryEntry(label: '概览', key: 'a', restore: () {}));
      h.record(const RouteHistoryEntry(label: '某一次性页', key: 'b')); // restore == null

      // 当前就停在「不可重建」那一格上 → 后退（去 A）照样可用（A 能重建）。
      expect(h.canGoBack, isTrue, reason: '判据是**目标那一格**能不能重建');

      // 退回去之后，前面那格回不去 → 前进按钮禁用（不画死按钮）。
      expect(h.goBack(), isTrue);
      expect(h.current?.label, '概览');
      expect(h.canGoForward, isFalse, reason: '目标不可重建 → 前进按钮不给按');
      expect(h.goForward(), isFalse);
    });

    test('goTo：直接跳历史里的任意一条', () {
      final h = RouteHistory();
      final visited = <String>[];
      for (final label in ['A', 'B', 'C']) {
        h.record(RouteHistoryEntry(
            label: label, key: label, restore: () => visited.add(label)));
      }
      expect(h.goTo(0), isTrue);
      expect(h.current?.label, 'A');
      expect(visited, ['A']);
      expect(h.goTo(0), isFalse, reason: '已经在 A 上，点了等于没动');
      expect(h.goTo(9), isFalse, reason: '越界不崩');
      expect(h.goTo(2), isTrue);
      expect(visited, ['A', 'C']);
    });

    test('clear：换账号 / 回根时清空', () {
      final h = RouteHistory();
      h.record(RouteHistoryEntry(label: 'A', key: 'A', restore: () {}));
      h.clear();
      expect(h.isEmpty, isTrue);
      expect(h.canGoBack, isFalse);
    });
  });

  group('标题栏按钮', () {
    Future<void> pump(WidgetTester tester, RouteHistory history) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [routeHistoryProvider.overrideWith((ref) => history)],
          child: MaterialApp(
            home: Scaffold(body: WindowTitleBarHistory()),
          ),
        ),
      );
    }

    testWidgets('空历史：两枚按钮都是禁用的', (tester) async {
      await pump(tester, RouteHistory());
      final back = tester.widget<IconButton>(
        find.byKey(const Key('windowTitleBarBack')),
      );
      final forward = tester.widget<IconButton>(
        find.byKey(const Key('windowTitleBarForward')),
      );
      expect(back.onPressed, isNull);
      expect(forward.onPressed, isNull);
      expect(find.byKey(const Key('windowTitleBarHistoryMenu')), findsNothing,
          reason: '没走过任何页面就不画历史下拉');
    });

    testWidgets('有历史后可点：后退按钮回调账本', (tester) async {
      final history = RouteHistory();
      final visited = <String>[];
      history.record(RouteHistoryEntry(
          label: '概览', key: 'a', restore: () => visited.add('概览')));
      history.record(RouteHistoryEntry(
          label: '设置', key: 'b', restore: () => visited.add('设置')));
      await pump(tester, history);

      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('windowTitleBarBack')))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(const Key('windowTitleBarBack')));
      await tester.pumpAndSettle();
      expect(history.index, 0);
      expect(history.current?.label, '概览');
      expect(visited, ['概览']);

      // 后退之后「前进」亮起来，点它能回到「设置」。
      await tester.tap(find.byKey(const Key('windowTitleBarForward')));
      await tester.pumpAndSettle();
      expect(history.current?.label, '设置');
      expect(visited, ['概览', '设置']);
    });

    testWidgets('历史下拉：列出走过的位置，点一行跳过去', (tester) async {
      final history = RouteHistory();
      final visited = <String>[];
      for (final label in ['概览', '成绩', '设置']) {
        history.record(RouteHistoryEntry(
            label: label, key: label, restore: () => visited.add(label)));
      }
      await pump(tester, history);
      await tester.tap(find.byKey(const Key('windowTitleBarHistoryMenu')));
      await tester.pumpAndSettle();

      expect(find.text('概览'), findsOneWidget);
      expect(find.text('成绩'), findsOneWidget);
      expect(find.text('设置'), findsWidgets, reason: '菜单里一条 + ？');

      await tester.tap(find.text('概览').last);
      await tester.pumpAndSettle();
      expect(history.current?.label, '概览');
      expect(visited, ['概览']);
    });
  });

  group('跳转缝的记录钩子', () {
    setUp(() {
      clearServiceScreens();
      serviceNavHistoryRecorder = null;
      attachServiceNavigator(null);
    });
    tearDown(() {
      clearServiceScreens();
      serviceNavHistoryRecorder = null;
      attachServiceNavigator(null);
    });

    test('注册时带 label，跳一次就记一笔（含能否回退）', () {
      final recorded = <List<Object?>>[];
      serviceNavHistoryRecorder = (id, label, canRestore) =>
          recorded.add([id, label, canRestore]);
      registerServiceScreen(kServiceSettings, () => const SizedBox.shrink(),
          label: '设置');

      expect(
        openServiceScreenById(kServiceSettings),
        isFalse,
        reason: '没注入 Navigator（单测没走组装根）→ 静默 false，不抛异常',
      );
      // ⚠ 没注入 Navigator 时不记历史（页面根本没开出去，记了就是假历史）。
      expect(recorded, isEmpty);
      expect(serviceScreenLabel(kServiceSettings), '设置');
    });

    test('clearServiceScreens 连标签一起清（用例之间要隔离）', () {
      registerServiceScreen(kServiceMaterials, () => const SizedBox.shrink(),
          label: '材料库');
      expect(serviceScreenLabel(kServiceMaterials), '材料库');
      clearServiceScreens();
      expect(serviceScreenLabel(kServiceMaterials), isNull);
      expect(hasServiceScreen(kServiceMaterials), isFalse);
    });
  });

  group('悬浮展开 / 固定（用户 2026-10-09：「悬浮时也可以显示」「点击固定按钮固定不再消失」）', () {
    Future<void> pump(WidgetTester tester, RouteHistory history) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [routeHistoryProvider.overrideWith((ref) => history)],
          child: MaterialApp(home: Scaffold(body: WindowTitleBarHistory())),
        ),
      );
    }

    RouteHistory seeded() {
      final h = RouteHistory();
      for (final label in ['概览', '成绩']) {
        h.record(RouteHistoryEntry(label: label, key: label, restore: () {}));
      }
      return h;
    }

    testWidgets('鼠标停在 🕘 上会自动展开（不用点）', (tester) async {
      await pump(tester, seeded());
      expect(find.byKey(const Key('windowTitleBarHistoryPanel')), findsNothing);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(
        tester.getCenter(find.byKey(const Key('windowTitleBarHistoryMenu'))),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('windowTitleBarHistoryPanel')), findsOneWidget,
          reason: '悬浮 260ms 后应当自动展开');
    });

    // 用户 2026-10-09 二十五轮：「从历史按钮上移开就会让面板消失，不能移动到面板上」。
    //
    // ⚠ 这条**必须逐像素走**：原先的用例只有「停在按钮上」和「直接跳到 (5,400)」两种，
    // 中间那一步（从按钮**挪到面板上**）从来没被测过 —— 而按钮与面板之间正好有一道
    // `Offset(0, 4)` 的缝，鼠标穿过它时两个 `MouseRegion` 都不认，`onExit` 就把面板收了。
    testWidgets('★ 从按钮挪到面板上：面板不许消失', (tester) async {
      await pump(tester, seeded());
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      final button = tester.getCenter(
        find.byKey(const Key('windowTitleBarHistoryMenu')),
      );
      await mouse.moveTo(button);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('windowTitleBarHistoryPanel')), findsOneWidget);

      // 沿「按钮 → 面板」这条线**一小步一小步**挪过去（每 3px 一跳、都让框架处理完），
      // 任何一步把面板收掉都算失败。
      final panelRect = tester.getRect(
        find.byKey(const Key('windowTitleBarHistoryPanel')),
      );
      // ignore: avoid_print
      print(
        'PROBE 按钮 ${tester.getRect(find.byKey(const Key('windowTitleBarHistoryMenu')))} '
        '面板 ${panelRect} 按钮中心 $button',
      );
      final target = Offset(button.dx, panelRect.center.dy);
      const step = 3.0;
      final steps = ((target.dy - button.dy) / step).ceil();
      for (var i = 1; i <= steps; i++) {
        final dy = button.dy + step * i;
        await mouse.moveTo(Offset(button.dx, dy.clamp(button.dy, target.dy)));
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          find.byKey(const Key('windowTitleBarHistoryPanel')),
          findsOneWidget,
          reason: '在 y=${dy.toStringAsFixed(0)} 处面板就被收掉了'
              '（按钮底边 ${button.dy.toStringAsFixed(0)} → 面板顶边 '
              '${panelRect.top.toStringAsFixed(0)} 之间那道缝没被罩住）',
        );
      }
      // 停在面板上：仍然在
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('windowTitleBarHistoryPanel')),
        findsOneWidget,
        reason: '鼠标停在面板上时面板必须还在',
      );
    });

    testWidgets('从按钮挪到**面板上**不会消失（用户 2026-10-09 二轮报的 bug）', (tester) async {
      await pump(tester, seeded());
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(
        tester.getCenter(find.byKey(const Key('windowTitleBarHistoryMenu'))),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('windowTitleBarHistoryPanel')), findsOneWidget);

      // 移到面板**上半部分**（正是「从按钮下来正对的那块」）——移出按钮那一下只是
      // 起一个 320ms 的延迟计时器，进面板就取消，所以这里必须还在。
      final panel = tester.getRect(find.byKey(const Key('windowTitleBarHistoryPanel')));
      await mouse.moveTo(Offset(panel.center.dx, panel.top + 24));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('windowTitleBarHistoryPanel')), findsOneWidget,
          reason: '鼠标要能挪到面板上（不能一移开按钮就收）');
    });
    testWidgets('钉住之后：鼠标移开也不收；取消固定后移开就收', (tester) async {
      await pump(tester, seeded());
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(
        tester.getCenter(find.byKey(const Key('windowTitleBarHistoryMenu'))),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('windowTitleBarHistoryPanel')), findsOneWidget);

      // 钉住
      await tester.tap(find.byKey(const Key('windowTitleBarHistoryPin')));
      await tester.pumpAndSettle();
      // 鼠标移开
      await mouse.moveTo(const Offset(5, 400));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('windowTitleBarHistoryPanel')), findsOneWidget,
          reason: '钉住了就不该被悬浮离开收走');

      // 取消固定 → 再移开一次（进出各一次才触发 onExit）
      await tester.tap(find.byKey(const Key('windowTitleBarHistoryPin')));
      await tester.pumpAndSettle();
      await mouse.moveTo(
        tester.getCenter(find.byKey(const Key('windowTitleBarHistoryMenu'))),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await mouse.moveTo(const Offset(5, 400));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('windowTitleBarHistoryPanel')), findsNothing,
          reason: '取消固定后移开就该收起');
    });
  });
}