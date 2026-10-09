/// 窗口标题栏（隐藏系统标题栏 + 自绘三键）的守卫与行为测试 —— 2026-10-09 立。
///
/// 需求原话（用户）：
/// 「我希望把系统标题栏隐藏，然后让我们的顶部标题栏支持三键（最小化/最大化/关闭）。
/// 然后让我们的顶部标题栏支持系统标题栏的各种特性。并且设置里可以调关于此标题栏的
/// 两项：① 交换左侧应用 logo 与右侧三键的位置，变成左侧三键，右侧 logo；
/// ② 允许选择 win 风格三键与 mac 风格」。
///
/// 这里守四件事：
/// 1. **偏好口径**（`windowButtonsOnLeft` / store 落盘 / 默认值）；
/// 2. **上报给原生的几何**（高度 40、三键矩形贴着所在那一侧、页面动作矩形进
///    `interactive`）—— 原生 `WM_NCHITTEST` 就按这份矩形判命中，算错一个像素就会
///    出现「点关闭没反应 / 点标题栏变成拉高度」（真机实测踩过，见 §43）；
/// 3. **三键的视觉**（Win 风格关闭键悬停变红、mac 风格三个圆点、失焦转灰）；
/// 4. **跨语言契约**（通道名 / 三键标识在 Dart 与 `window_chrome.cpp` 逐字一致）。
///
/// ⚠ 两个测试环境的坑（都踩过）：
/// - **Hive 的文件 I/O 不能进 `testWidgets` 的 FakeAsync 区**（`await openBox` 永不
///   返回 → `pumpAndSettle` 10 分钟超时）→ box 一律在 `setUp` 里打开并写档；
///   widget 测试里**不要**自己 `ensureLoaded()`（在真异步区建出来的 future，完成回调
///   排在真微任务队列里，假区抽不到 → `save()` 卡在第一个 await 上）—— 交给 provider
///   在假区里建、在假区里等（与 `theme_dark_test.dart` ⑤ 同套路）。
/// - **`debugDefaultTargetPlatformOverride` 必须在测试体内复位**：框架在测试体结束、
///   tearDown 之前就查「foundation 调试变量有没有被改过」（放 tearDown 会报
///   「The value of a foundation debug variable was changed by the test」）。
library;

import 'dart:io';

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/core/window/window_chrome.dart';
import 'package:smarter_jxufe/core/window/window_title_bar_actions.dart';
import 'package:smarter_jxufe/design/status_palette.dart';
import 'package:smarter_jxufe/design/window_title_bar.dart';
import 'package:smarter_jxufe/features/settings/data/window_bar_prefs.dart';
import 'package:smarter_jxufe/features/settings/presentation/widgets/settings_cards_window.dart';

/// 记录 Dart → 原生 的方法调用。
late List<MethodCall> channelCalls;

/// 原生 → Dart 的事件（用 `handlePlatformMessage` 灌进来）。
Future<void> emitPlatformCall(String method, [Object? arguments]) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        kWindowChromeChannelName,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall(method, arguments),
        ),
        (_) {},
      );
}

/// 最近一次 `setTitleBarLayout` 的参数。
Map<Object?, Object?> lastLayout() {
  final call = channelCalls.lastWhere(
    (c) => c.method == 'setTitleBarLayout',
    orElse: () => throw StateError('没有上报过 setTitleBarLayout：$channelCalls'),
  );
  return (call.arguments as Map).cast<Object?, Object?>();
}

List<double>? rectOf(Map<Object?, Object?> layout, String key) {
  final raw = layout[key];
  if (raw is! List) return null;
  return raw.cast<num>().map((n) => n.toDouble()).toList();
}

/// 与被测组件同构的宿主：`AppWindowChrome` 挂在 `MaterialApp.builder` 上
/// （与 `main.dart` 的接法一致 —— 标题栏必须在 Navigator 之上）。
///
/// 偏好 provider **不覆盖**：让它走真实那条路（在假异步区里建、在假异步区里
/// `ensureLoaded`），box 由 `setUp` 打开 —— 覆盖成 `setUp` 里建好的实例会踩
/// 「真区建的 future 在假区永远等不到」那个坑（见文件头）。
Widget host({TargetPlatform platform = TargetPlatform.windows}) =>
    ProviderScope(
      child: MaterialApp(
        theme: ThemeData(platform: platform, useMaterial3: true),
        builder: (context, child) =>
            AppWindowChrome(child: child ?? const SizedBox.shrink()),
        home: const Scaffold(body: Text('内容')),
      ),
    );

Widget cardHost(TargetPlatform platform, {WindowBarPrefsStore? store}) =>
    ProviderScope(
      overrides: [
        if (store != null)
          windowBarPrefsProvider.overrideWith((ref) => store),
      ],
      child: MaterialApp(
        theme: ThemeData(platform: platform, useMaterial3: true),
        home: const Scaffold(
          body: SingleChildScrollView(child: SettingsWindowBarCard()),
        ),
      ),
    );

/// `defaultTargetPlatform == windows` 的测试体包装（**复位必须在体内**，见文件头）。
void testWidgetsWindows(
  String description,
  Future<void> Function(WidgetTester) body,
) {
  testWidgets(description, (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Directory? hiveDir;

  /// box 只能在 `setUp` / 普通 `test` 里开（FakeAsync 区里真 I/O 永不返回）。
  Future<void> prepareHive([Map<String, String> prefs = const {}]) async {
    final previous = hiveDir;
    if (previous != null && previous.existsSync()) {
      await Hive.close();
      try {
        previous.deleteSync(recursive: true);
      } catch (_) {}
    }
    final dir = Directory.systemTemp.createTempSync('window_title_bar_test');
    Hive.init(dir.path);
    final box = await Hive.openBox<String>(windowBarPrefsBoxName);
    for (final entry in prefs.entries) {
      await box.put(entry.key, entry.value);
    }
    hiveDir = dir;
  }

  setUp(() async {
    channelCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kWindowChromeChannel, (call) async {
          channelCalls.add(call);
          if (call.method == 'getWindowState') {
            return <String, Object?>{
              'maximized': false,
              'minimized': false,
              'active': true,
            };
          }
          return null;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kWindowChromeChannel, null);
    final dir = hiveDir;
    if (dir != null && dir.existsSync()) {
      await Hive.close();
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  group('偏好口径：logo 与三键谁在左', () {
    test('Windows 风格默认三键在右；交换后到左', () {
      expect(
        windowButtonsOnLeft(
          style: WindowButtonsStyle.windows,
          swapSides: false,
        ),
        isFalse,
      );
      expect(
        windowButtonsOnLeft(style: WindowButtonsStyle.windows, swapSides: true),
        isTrue,
      );
    });

    test('mac 风格默认三键在左（mac 惯例）；「交换」能把它换回右侧', () {
      expect(
        windowButtonsOnLeft(style: WindowButtonsStyle.mac, swapSides: false),
        isTrue,
      );
      expect(
        windowButtonsOnLeft(style: WindowButtonsStyle.mac, swapSides: true),
        isFalse,
      );
    });

    test('认不出的存档值 → null（保持默认，不抛）', () {
      expect(windowButtonsStyleFromName(null), isNull);
      expect(windowButtonsStyleFromName(''), isNull);
      expect(windowButtonsStyleFromName('beos'), isNull);
      expect(windowButtonsStyleFromName('mac'), WindowButtonsStyle.mac);
    });

    test('默认值 + 落盘 + 重读（Hive 单 key 口径）', () async {
      await prepareHive();
      final store = WindowBarPrefsStore();
      await store.ensureLoaded();
      expect(store.style, WindowButtonsStyle.windows);
      expect(store.swapSides, isFalse);
      expect(store.buttonsOnLeft, isFalse);

      await store.saveStyle(WindowButtonsStyle.mac);
      await store.saveSwapSides(true);
      expect(store.buttonsOnLeft, isFalse); // mac + 交换 = 三键在右

      // 新实例重读盘上的值（模拟重启）。
      final reloaded = WindowBarPrefsStore();
      await reloaded.ensureLoaded();
      expect(reloaded.style, WindowButtonsStyle.mac);
      expect(reloaded.swapSides, isTrue);
    });

    test('存档里有脏值：只认得出风格，交换位退回 false', () async {
      await prepareHive({'buttonsStyle': 'mac', 'swapSides': 'yes'});
      final store = WindowBarPrefsStore();
      await store.ensureLoaded();
      expect(store.style, WindowButtonsStyle.mac);
      expect(store.swapSides, isFalse, reason: '只认 "true"');
    });
  });

  group('几何上报（原生就按这份矩形判命中）· Windows 风格', () {
    setUp(() => prepareHive());

    testWidgetsWindows('三键贴右边缘，宽度 46，高度 = 栏高', (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      final layout = lastLayout();
      expect(layout['enabled'], isTrue);
      expect(layout['height'], kWindowTitleBarHeight);

      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      final close = rectOf(layout, 'close')!;
      final maximize = rectOf(layout, 'maximize')!;
      final minimize = rectOf(layout, 'minimize')!;
      expect(close[2], closeTo(screen.width, 0.01), reason: '关闭键贴右边缘');
      expect(close[0], closeTo(screen.width - 46, 0.01));
      // 按钮在栏内被底部 1px 分隔线切掉一格高（39 = 40 - 1）：命中区按**量到的**
      // 矩形上报，原生那一侧不写死高度。
      expect(close[3] - close[1], closeTo(kWindowTitleBarHeight, 1));
      expect(maximize[2], closeTo(close[0], 0.01), reason: '最大化紧挨关闭');
      expect(minimize[2], closeTo(maximize[0], 0.01), reason: '最小化紧挨最大化');
      expect(minimize[0], closeTo(screen.width - 138, 0.01));
      // 2026-10-09：interactive 不再是空 —— 品牌组里的「路由历史」三枚恒在（漏登记
      // 就等于点不动，用户实测过）。这里只守「只有这一簇、且不与三键重叠」。
      final interactive0 = (layout['interactive']! as List).cast<List>();
      expect(interactive0, hasLength(1), reason: '只有路由历史那一簇（侧栏开关此时没发布）');
      expect(interactive0.first[3], lessThanOrEqualTo(kWindowTitleBarHeight));
    });

    testWidgetsWindows('页面动作进 interactive，且与三键不重叠；收回后不再上报', (
      tester,
    ) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(WindowTitleBar)),
        listen: false,
      );
      container
          .read(windowTitleBarActionsProvider)
          .update(
            visible: true,
            builder: (context) => const Icon(Icons.settings, size: 18),
          );
      await tester.pump();
      await tester.pump();

      final layout = lastLayout();
      // 2026-10-09：interactive 里现在恒有「路由历史」那一簇 + 本次发布的页面动作
      // （漏登记 = 点不动，用户实测过「三个按钮都按不动」）。页面动作那一条按
      // 「最靠右 / 与历史不重叠」找，别再用 single（历史那一簇也在列表里）。
      final interactive = (layout['interactive']! as List).cast<List>();
      expect(interactive.length, greaterThanOrEqualTo(2),
          reason: '路由历史那一簇 + 页面动作');
      final rows = interactive.map((r) => r.cast<num>().toList()).toList()
        ..sort((a, b) => a[0].compareTo(b[0]));
      final history = rows.first;
      final actions = rows.last;
      expect(history[2], lessThanOrEqualTo(actions[0]),
          reason: '历史簇与页面动作不许重叠');
      final close = rectOf(layout, 'close')!;
      expect(
        actions[2],
        lessThanOrEqualTo(close[0]),
        reason: '动作区在三键左边，二者不重叠（重叠处原生判成标题栏 → 点不动）',
      );
      expect(actions[2] - actions[0], greaterThan(0));

      // 收回后再上报：interactive 又空（render object 卸载时要把 token 撤掉）。
      container.read(windowTitleBarActionsProvider).clear();
      await tester.pump();
      await tester.pump();
      expect((lastLayout()['interactive']! as List), hasLength(1),
          reason: '收回页面动作后只剩路由历史那一簇');
      expect(lastLayout()['enabled'], isTrue, reason: '三键的矩形一个都不许丢');
    });

    testWidgetsWindows('几何没变就不重复上报（不刷通道）', (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      final first = channelCalls
          .where((c) => c.method == 'setTitleBarLayout')
          .length;
      expect(first, 1);
      await tester.pump();
      await tester.pump();
      expect(
        channelCalls.where((c) => c.method == 'setTitleBarLayout').length,
        first,
        reason: '每帧都推会白刷通道（控制器按值去重）',
      );
    });
  });

  group('几何上报 · mac 风格', () {
    setUp(() => prepareHive({'buttonsStyle': 'mac'}));

    /// 圆点**墨迹**的矩形（三键风格 = 圆点那个 `Container`）。
    Rect dotRect(WidgetTester tester, WindowTitleBarButton button) =>
        tester.getRect(
          find
              .descendant(
                of: find.byKey(Key('windowButton-${button.name}')),
                matching: find.byWidgetPredicate(
                  (w) =>
                      w is Container &&
                      w.decoration is BoxDecoration &&
                      (w.decoration! as BoxDecoration).shape == BoxShape.circle,
                ),
              )
              .first,
        );

    testWidgetsWindows('整组留白：圆点距侧边 = 距栏上下边（用户 2026-10-09 四轮）', (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      final bar = tester.getRect(find.byType(WindowTitleBar));
      final close = dotRect(tester, WindowTitleBarButton.close);
      final maximize = dotRect(tester, WindowTitleBarButton.maximize);
      // 左侧：最左那颗圆点的左缘到栏左边的距离 == 圆点上缘到栏上边的距离。
      expect(
        close.left - bar.left,
        closeTo(kWindowTitleBarEdgeInset, 0.01),
        reason: '侧边留白要等于上下留白',
      );
      expect(close.top - bar.top, closeTo(kWindowTitleBarEdgeInset, 0.01));
      expect(
        close.top - bar.top,
        closeTo(close.left - bar.left, 0.01),
        reason: '用户口径：整组距上下边距与侧边距一致',
      );
      // 上下对称（圆点在栏内竖直居中）。
      expect(
        bar.bottom - close.bottom,
        closeTo(kWindowTitleBarEdgeInset, 0.01),
        reason: '上下留白对称（2026-10-09 六轮撤掉底部分隔线后不再差 1px）',
      );
      // 三颗圆点等距、直径一致。
      final minimize = dotRect(tester, WindowTitleBarButton.minimize);
      expect(minimize.left - close.left, closeTo(kWindowTitleBarMacSlot, 0.01));
      expect(maximize.left - minimize.left, closeTo(kWindowTitleBarMacSlot, 0.01));
      expect(close.width, closeTo(kWindowTitleBarMacDot, 0.01));
      // 槽（命中区）跟着整组一起右移那 10 —— 留白是靠**外侧 padding** 撑出来的，
      // 但槽本身宽度不变（20），点击区不缩水。
      final slot = rectOf(lastLayout(), 'close')!;
      expect(slot[0], closeTo(kWindowTitleBarMacClusterInset, 0.01));
      expect(slot[2] - slot[0], closeTo(kWindowTitleBarMacSlot, 0.01));
    });

    testWidgetsWindows('换到右侧时，留白贴的是右边（同样一致）', (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      final store = ProviderScope.containerOf(
        tester.element(find.byType(WindowTitleBar)),
      ).read(windowBarPrefsProvider);
      await tester.runAsync(() => store.saveSwapSides(true));
      await tester.pumpAndSettle();

      final bar = tester.getRect(find.byType(WindowTitleBar));
      // mac + 交换 = 三键在右；右侧顺序回 Windows 那套（最小化/最大化/**关闭**），
      // 所以最外那颗是关闭。
      final close = dotRect(tester, WindowTitleBarButton.close);
      expect(
        bar.right - close.right,
        closeTo(kWindowTitleBarEdgeInset, 0.01),
        reason: 'mac 在右侧时留白贴右边',
      );
      expect(close.top - bar.top, closeTo(kWindowTitleBarEdgeInset, 0.01));
      expect(
        bar.right - close.right,
        closeTo(close.top - bar.top, 0.01),
        reason: '两侧留白都要等于上下留白',
      );
    });

    testWidgetsWindows('三个圆点槽靠左（mac 惯例），每个槽 20 宽', (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      final layout = lastLayout();
      final close = rectOf(layout, 'close')!;
      final minimize = rectOf(layout, 'minimize')!;
      final maximize = rectOf(layout, 'maximize')!;
      // mac 风格在左：顺序是「关闭 / 最小化 / 最大化」，从整组留白之后起排
      // （2026-10-09 四轮起槽不再贴 x=0 —— 外侧那 9.5 是「圆点距侧边 = 距上下边」的留白）。
      expect(close[0], closeTo(kWindowTitleBarMacClusterInset, 0.01));
      expect(close[2] - close[0], closeTo(kWindowTitleBarMacSlot, 0.01));
      expect(minimize[0], closeTo(close[2], 0.01));
      expect(maximize[0], closeTo(minimize[2], 0.01));
      // 画的确实是圆点（mac 风格），不是 Win 的矩形按钮底色。
      expect(
        find.descendant(
          of: find.byKey(Key('windowButton-${WindowTitleBarButton.close.name}')),
          matching: find.byWidgetPredicate(
            (w) =>
                w is Container &&
                w.decoration is BoxDecoration &&
                (w.decoration! as BoxDecoration).shape == BoxShape.circle,
          ),
        ),
        findsOneWidget,
      );
    });
  });

  group('两项设置的切换是动画的（用户 2026-10-09 要求）', () {
    setUp(() => prepareHive());

    WindowBarPrefsStore storeOf(WidgetTester tester) =>
        ProviderScope.containerOf(
          tester.element(find.byType(WindowTitleBar)),
        ).read(windowBarPrefsProvider);

    double closeLeft(WidgetTester tester) =>
        tester.getTopLeft(find.byKey(const Key('windowButton-close'))).dx;

    double closeWidth(WidgetTester tester) =>
        tester.getSize(find.byKey(const Key('windowButton-close'))).width;

    testWidgetsWindows('交换位置：两组各自滑动，不是瞬移；中途的几何也照常上报', (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      final store = storeOf(tester);
      // Windows 风格顺序恒为「最小化 / 最大化 / 关闭」→ 搬到左边后关闭键在最右一格。
      const closeAtLeft = 2 * kWindowTitleBarButtonWidth;
      expect(closeLeft(tester), closeTo(800 - 46, 0.01), reason: '默认贴右');

      await tester.runAsync(() => store.saveSwapSides(true));
      await tester.pump(); // 触发换位置的那一帧
      final reportsAtStart = channelCalls
          .where((c) => c.method == 'setTitleBarLayout')
          .length;

      await tester.pump(const Duration(milliseconds: 120));
      final mid = closeLeft(tester);
      expect(mid, lessThan(800 - 46), reason: '动画中途应该已经往左走');
      expect(mid, greaterThan(closeAtLeft), reason: '但还没到（不是瞬移）');
      expect(closeWidth(tester), closeTo(46, 0.01), reason: '换位置不该改宽度');

      await tester.pumpAndSettle();
      expect(closeLeft(tester), closeTo(closeAtLeft, 0.01), reason: '动画结束贴左');
      // ⚠ 隐式动画不重建本 State：动画期间必须靠**区域自己**补上报，否则原生拿的是
      // 旧矩形 —— 按钮已经滑到左边，点它却没反应（真机就是这么坏的）。
      final reports = channelCalls
          .where((c) => c.method == 'setTitleBarLayout')
          .length;
      expect(
        reports,
        greaterThan(reportsAtStart),
        reason: '动画期间几何变了就必须重新上报',
      );
      final close = rectOf(lastLayout(), 'close')!;
      expect(
        close[0],
        closeTo(closeAtLeft, 0.01),
        reason: '最后一次上报 = 动画后的位置',
      );
    });

    testWidgetsWindows('换风格：槽宽 46 ↔ 20 是补间，不是跳变', (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      final store = storeOf(tester);
      expect(closeWidth(tester), closeTo(46, 0.01));

      await tester.runAsync(() => store.saveStyle(WindowButtonsStyle.mac));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      final mid = closeWidth(tester);
      expect(
        mid,
        lessThan(46),
        reason: '中途应该已经收窄（动画在跑）',
      );
      expect(mid, greaterThan(kWindowTitleBarMacSlot));

      await tester.pumpAndSettle();
      expect(closeWidth(tester), closeTo(kWindowTitleBarMacSlot, 0.01));
      // mac 默认靠左 → 关闭键跑到最前面（重排也是动画的：结束位置为准），
      // 且整组外侧留出与上下留白一致的 9.5。
      expect(closeLeft(tester), closeTo(kWindowTitleBarMacClusterInset, 0.01));
      expect(
        find.descendant(
          of: find.byKey(const Key('windowButton-close')),
          matching: find.byType(Icon),
        ),
        findsNothing,
        reason: 'mac 风格不画 codicon 字形',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgetsWindows('形变中途两套视觉同时在（交叉淡入淡出，不是换树）', (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      final store = storeOf(tester);

      Finder dot() => find.descendant(
        of: find.byKey(const Key('windowButton-close')),
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration! as BoxDecoration).shape == BoxShape.circle,
        ),
      );
      // 纯 Win 风格下没有圆点（t=0 时整层不画）。
      expect(dot(), findsNothing);

      await tester.runAsync(() => store.saveStyle(WindowButtonsStyle.mac));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      // 中途：codicon 字形还在（正在淡出）+ 圆点已经在（正在淡入）= 交叉淡入淡出。
      // 换树（`AnimatedSwitcher`）在半路会是「两套都满不透明」，形变不会。
      expect(
        find.descendant(
          of: find.byKey(const Key('windowButton-close')),
          matching: find.byType(Icon),
        ),
        findsOneWidget,
      );
      expect(dot(), findsOneWidget);
      final opacities = tester
          .widgetList<Opacity>(
            find.descendant(
              of: find.byKey(const Key('windowButton-close')),
              matching: find.byType(Opacity),
            ),
          )
          .map((o) => o.opacity)
          .toList();
      expect(
        opacities.any((o) => o > 0.05 && o < 0.95),
        isTrue,
        reason: '中途必须有一层是半透明的（$opacities）',
      );

      await tester.pumpAndSettle();
      expect(dot(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('几何上报 · 交换位置', () {
    setUp(() => prepareHive({'swapSides': 'true'}));

    testWidgetsWindows('三键搬到左边（Windows 风格顺序不变）', (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      final layout = lastLayout();
      final minimize = rectOf(layout, 'minimize')!;
      final maximize = rectOf(layout, 'maximize')!;
      final close = rectOf(layout, 'close')!;
      expect(minimize[0], closeTo(0, 0.01));
      expect(maximize[0], closeTo(46, 0.01));
      expect(close[0], closeTo(92, 0.01));
    });
  });

  group('三键视觉（悬停 / 按下 / 失焦由原生推）', () {
    setUp(() => prepareHive());

    /// Win 风格的悬停底色（2026-10-09 起画在 `ColoredBox` 里 —— 三键现在是
    /// 「矩形高亮 + codicon」淡出 / 「圆点」淡入的**形变**，那层底色不再是容器自身）。
    Color? buttonColor(WidgetTester tester, WindowTitleBarButton button) {
      final box = tester.widget<ColoredBox>(
        find
            .descendant(
              of: find.byKey(Key('windowButton-${button.name}')),
              matching: find.byType(ColoredBox),
            )
            .first,
      );
      return box.color;
    }

    testWidgetsWindows('Win 风格：关闭键悬停变红，移开复原', (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      expect(
        buttonColor(tester, WindowTitleBarButton.close),
        Colors.transparent,
      );
      await emitPlatformCall('titleBarPointer', <String, Object?>{
        'hovered': 'close',
        'pressed': null,
        'active': true,
        'maximized': false,
      });
      await tester.pump();
      expect(
        buttonColor(tester, WindowTitleBarButton.close),
        WindowChromeTone.windowsCloseHighlight,
      );
      expect(
        buttonColor(tester, WindowTitleBarButton.minimize),
        Colors.transparent,
        reason: '只高亮被悬停的那一个',
      );

      await emitPlatformCall('titleBarPointer', <String, Object?>{
        'hovered': null,
        'pressed': null,
        'active': true,
        'maximized': false,
      });
      await tester.pump();
      expect(
        buttonColor(tester, WindowTitleBarButton.close),
        Colors.transparent,
      );
    });

    testWidgetsWindows('窗口失焦：不出悬停高亮（原生同理）', (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      await emitPlatformCall('titleBarPointer', <String, Object?>{
        'hovered': 'close',
        'pressed': null,
        'active': false,
        'maximized': false,
      });
      await tester.pump();
      expect(
        buttonColor(tester, WindowTitleBarButton.close),
        Colors.transparent,
      );
    });

    testWidgetsWindows('窗口状态：最大化 → 中间那枚换成 codicon「还原」字形', (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      // 三键图标 = codicon 字体（用户 2026-10-09 指定「跟原生/vshell 一致」），
      // 所以判据是 IconData 的码点，不再是自绘 painter 的 flag。
      IconData iconOfMaximize() {
        final icon = tester.widget<Icon>(
          find
              .descendant(
                of: find.byKey(
                  Key('windowButton-${WindowTitleBarButton.maximize.name}'),
                ),
                matching: find.byType(Icon),
              )
              .first,
        );
        return icon.icon!;
      }

      expect(iconOfMaximize(), Codicons.chromeMaximize);
      expect(Codicons.chromeMaximize.fontFamily, 'codicon');
      await emitPlatformCall('windowState', <String, Object?>{
        'maximized': true,
        'minimized': false,
        'active': true,
      });
      await tester.pump();
      expect(iconOfMaximize(), Codicons.chromeRestore);
    });

    testWidgetsWindows('三键图标码点钉死（codicon 子集字体的契约）', (tester) async {
      // 字体是**子集**（只含这四个字形，见 pubspec 的 `codicon` family）——
      // 码点写错 = 界面上直接是空白/豆腐块，所以在这里钉死。
      expect(Codicons.chromeClose.codePoint, 0xeab8);
      expect(Codicons.chromeMaximize.codePoint, 0xeab9);
      expect(Codicons.chromeMinimize.codePoint, 0xeaba);
      expect(Codicons.chromeRestore.codePoint, 0xeabb);
      expect(Codicons.chromeClose.fontFamily, 'codicon');

      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      for (final button in WindowTitleBarButton.values) {
        final icon = tester.widget<Icon>(
          find
              .descendant(
                of: find.byKey(Key('windowButton-${button.name}')),
                matching: find.byType(Icon),
              )
              .first,
        );
        expect(icon.size, kWindowTitleBarGlyphSize);
        expect(icon.icon!.fontFamily, 'codicon');
      }
    });
  });

  group('平台门槛', () {
    setUp(() => prepareHive());

    testWidgets('非 Windows：不画标题栏，也不碰通道', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await tester.pumpWidget(host(platform: TargetPlatform.android));
        await tester.pumpAndSettle();
        expect(find.byType(WindowTitleBar), findsNothing);
        expect(find.text('内容'), findsOneWidget);
        expect(channelCalls, isEmpty);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgetsWindows('窄窗口：品牌只留 logo，整条栏不溢出', (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      expect(find.byType(WindowTitleBar), findsOneWidget);
      expect(find.text('智慧er江财'), findsNothing, reason: '窄窗口舍掉应用名');
      expect(tester.takeException(), isNull, reason: '不许 Row 溢出');
      // 三键仍然画满、仍然上报（窄窗口更要能关窗口）。
      final close = rectOf(lastLayout(), 'close')!;
      expect(close[2], closeTo(320, 0.01));
      expect(close[2] - close[0], closeTo(46, 0.01));
    });

    testWidgetsWindows('标题栏自带 Material + Overlay（少了首帧就抛 → 整个应用起不来）', (
      tester,
    ) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      // 页面动作区挂的是 IconButton（Tooltip 在 build 期就要 Overlay 祖先）与
      // AccountAvatar（InkWell 要 Material 祖先）；而标题栏是 Navigator 的**兄弟**，
      // navigator 那个 Overlay / Material 都不在它的祖先链上 —— 缺一个就是首帧抛异常，
      // 而 runner 是「首帧之后才 ShowWindow」→ 进程活着、永远没有窗口。
      expect(
        find.ancestor(
          of: find.byType(WindowTitleBar),
          matching: find.byType(Overlay),
        ),
        findsWidgets,
      );
      expect(
        find.ancestor(
          of: find.byType(WindowTitleBar),
          matching: find.byType(Material),
        ),
        findsWidgets,
      );
    });

    testWidgetsWindows('原生没应答（旧 exe + 新 Dart 包）→ 整条 chrome 不画、也不上报', (
      tester,
    ) async {
      // 这一档的 getWindowState 不回值 → `nativeReady` 保持 false。
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(kWindowChromeChannel, (call) async {
            channelCalls.add(call);
            return null;
          });
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      expect(
        find.byType(WindowTitleBar),
        findsNothing,
        reason: '画一条三键点不动的假标题栏，比不画更糟（系统标题栏还在，会变成两条）',
      );
      expect(find.text('内容'), findsOneWidget);
      expect(
        channelCalls.where((c) => c.method == 'setTitleBarLayout'),
        isEmpty,
        reason: '没握手就不该上报几何',
      );
    });

    testWidgetsWindows('原生推来第一个事件也算握手（顺序无关）', (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(kWindowChromeChannel, (call) async {
            channelCalls.add(call);
            return null; // getWindowState 不回值
          });
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      expect(find.byType(WindowTitleBar), findsNothing);

      await emitPlatformCall('windowState', <String, Object?>{
        'maximized': false,
        'minimized': false,
        'active': true,
      });
      await tester.pump();
      await tester.pump();
      expect(find.byType(WindowTitleBar), findsOneWidget);
      expect(lastLayout()['enabled'], isTrue);
    });

    testWidgetsWindows('Windows：标题栏在内容上方（高度 40），不影响内容', (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      expect(find.byType(WindowTitleBar), findsOneWidget);
      expect(find.text('智慧er江财'), findsOneWidget);
      expect(find.text('内容'), findsOneWidget);
      expect(
        tester.getSize(find.byType(WindowTitleBar)).height,
        kWindowTitleBarHeight,
      );
    });
  });

  group('设置卡：两项偏好', () {
    // ⚠ 本组的 store 在 `setUp`（真异步区）里建好并加载，改值走 `tester.runAsync`：
    // 点一下触发的是 `box.put`（真 I/O），在 `testWidgets` 的假异步区里**永远不完成**
    // —— 既会让断言看不到新值，又会把 box 写锁留给 `tearDown` 的 `Hive.close()`
    // （实测：测试体全跑完却卡到 10 分钟超时；`theme_dark_test.dart` ⑤ 记的是同一个坑，
    // 连 `runAsync` 也救不回**已**在假区里发起的那次写）。
    // 所以：值一律在真区里改，假区只负责渲染与断言；点按的接线单独断言 handler 在。
    late WindowBarPrefsStore store;

    setUp(() async {
      await prepareHive();
      store = WindowBarPrefsStore();
      await store.ensureLoaded();
    });

    testWidgetsWindows('Windows：两项都在；改 store 后卡片文案跟着翻', (tester) async {
      // 视口给足：卡片在 SingleChildScrollView 里，矮视口下第二项在屏幕外。
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        cardHost(TargetPlatform.windows, store: store),
      );
      await tester.pumpAndSettle();

      expect(find.text('窗口标题栏'), findsOneWidget);
      expect(find.text('交换 logo 与三键的位置'), findsOneWidget);
      expect(find.text('Windows 风格'), findsOneWidget);
      expect(find.text('macOS 风格'), findsOneWidget);
      // 默认：logo 在左 → 副标题照实说。
      expect(find.textContaining('logo 在左、三键在右'), findsOneWidget);
      // 两项的接线：两个控件都挂上了回调（点击动作本身 = 调 store，见上面的口径）。
      expect(
        tester
            .widget<InkWell>(
              find.byKey(const Key('windowButtonsStyle-mac')),
            )
            .onTap,
        isNotNull,
      );
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const Key('windowBarSwapSides')),
            )
            .onChanged,
        isNotNull,
      );

      await tester.runAsync(
        () => store.saveStyle(WindowButtonsStyle.mac),
      );
      await tester.pumpAndSettle();
      expect(store.style, WindowButtonsStyle.mac);
      // mac 风格默认三键靠左 → 副标题跟着翻。
      expect(find.textContaining('三键在左、logo 在右'), findsOneWidget);

      await tester.runAsync(() => store.saveSwapSides(true));
      await tester.pumpAndSettle();
      expect(store.swapSides, isTrue);
      expect(find.textContaining('logo 在左、三键在右'), findsOneWidget);
    });

    testWidgets('非 Windows：整卡不画（那边没有窗口标题栏）', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await tester.pumpWidget(
          cardHost(TargetPlatform.android),
        );
        await tester.pumpAndSettle();
        expect(find.text('窗口标题栏'), findsNothing);
        expect(find.byKey(const Key('windowBarSwapSides')), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('跨语言契约与源码守卫', () {
    test('通道名 / 三键标识在 Dart 与原生逐字一致', () {
      final native = File(
        'windows/runner/window_chrome.cpp',
      ).readAsStringSync();
      expect(
        native,
        contains('"$kWindowChromeChannelName"'),
        reason: '原生 kChannelName 必须与 kWindowChromeChannelName 一致',
      );
      for (final button in WindowTitleBarButton.values) {
        expect(
          native,
          contains('"${button.name}"'),
          reason: '原生三键标识必须与 WindowTitleBarButton.${button.name} 一致',
        );
      }
      // 两个事件名也要对得上（原生 → Dart）。
      expect(native, contains('"windowState"'));
      expect(native, contains('"titleBarPointer"'));
      // HTMAXBUTTON 是 Win11 贴靠布局的官方契约，删了贴靠面板就没了。
      expect(native, contains('HTMAXBUTTON'));
      expect(native, contains('HTMINBUTTON'));
      expect(native, contains('HTCLOSE'));
      expect(native, contains('HTCAPTION'));
      // 尺子必须按窗口 DPI 取（乘两遍会得到 1.5 倍的边框 —— 真机实测踩过）。
      expect(native, contains('GetSystemMetricsForDpi'));
      // 子窗口必须把命中测试吐给顶层（不吐则顶层永远收不到）。
      expect(native, contains('SetWindowSubclass'));
      expect(native, contains('HTTRANSPARENT'));
      // ---- 原生边框口径（2026-10-09 用户裁定「要用系统原生边框」，照 window_manager
      //      的 TitleBarStyle.hidden 重做；旧版「客户区 = 整个窗口 + 自己模拟缩放」已撤）----
      // ① 左/右/底收成真非客户区 → 系统自己给缩放热区与 DWM 边框；
      // ② 顶部不留（Win11）/ +1（Win10，他们踩过的顶边白线）；
      // ③ 最大化按显示器工作区扩回来；
      // ④ WM_NCACTIVATE 返回 1（不让系统重画非客户区）。
      expect(native, contains('params->rgrc[0].left += BorderWidthX()'));
      expect(native, contains('params->rgrc[0].right -= BorderWidthX()'));
      expect(native, contains('params->rgrc[0].bottom -= BorderWidthY()'));
      expect(native, contains('IsWindows11OrGreater() ? 0 : 1'));
      expect(native, contains('MonitorFromRect'));
      expect(native, contains('MONITOR_DEFAULTTONEAREST'));
      expect(native, contains('info.rcWork'));
      expect(native, contains('case WM_NCACTIVATE'));
      // 顶边那条因为 top += 0 落在客户区里，必须由 TopBorderHit 补回来。
      expect(native, contains('TopBorderHit'));
      expect(native, contains('HTTOPLEFT'));
      expect(native, contains('HTTOPRIGHT'));
      // 旧的模拟缩放（ResizeBorderHit / 自己算四边）必须彻底消失，
      // 否则「原生边框」会退化成假的。
      // ⚠ 负面判据先剥注释：新注释里逐字引用了「HTLEFT/HTRIGHT/HTBOTTOM 不用模拟」
      // 这条口径，直接 contains 会把注释判成违规（本仓踩过同款坑）。
      final code = native
          .split('\n')
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n');
      expect(code, isNot(contains('ResizeBorderHit')));
      expect(code, isNot(contains('HTBOTTOM')));
      expect(code, isNot(contains('HTRIGHT')));
      expect(code, isNot(contains('HTLEFT')));
      // 探针编译开关默认必须是 0（发布构建不许往 .probe 写日志）。
      expect(native, contains('#define WINDOW_CHROME_TRACE 0'));
    });

    test('首页品牌栏已并入标题栏（源码守卫）', () {
      final src = File(
        'lib/features/home/presentation/home_screen.dart',
      ).readAsStringSync();
      expect(
        src.contains('_buildTopBar'),
        isFalse,
        reason: '顶栏整条撤了：品牌在 WindowTitleBar，动作走插槽',
      );
      expect(
        src.contains('智慧er江财'),
        isFalse,
        reason: '应用名只在标题栏里出现一次（别在首页再写一遍）',
      );
      expect(src, contains('windowTitleBarActionsProvider'));
      expect(src, contains('_queueTitleBarActions'));
      // 侧栏底部固定区仍在（桌面端设置 / 头像的另一个入口）。
      expect(src, contains('homeSidebarSettingsKey'));
    });

    test('标题栏挂在组装根上（Navigator 之上）', () {
      final src = File('lib/main.dart').readAsStringSync();
      expect(src, contains('AppWindowChrome('));
      expect(
        src.indexOf('AppWindowChrome('),
        lessThan(src.indexOf('AiFloatingBallHost(')),
        reason: '标题栏在最外层（浮球在它里面）',
      );
      // 偏好预热：标题栏是第一帧就画的 chrome。
      expect(src, contains('windowBarStore.ensureLoaded()'));
      expect(src, contains('windowBarPrefsProvider.overrideWith'));
    });

    test('配色登记在 status_palette（值不许手滑）', () {
      final palette = File(
        'lib/design/status_palette.dart',
      ).readAsStringSync();
      expect(palette, contains('windowsCloseHighlight = Color(0xFFC42B1C)'));
      expect(palette, contains('macClose = Color(0xFFFF5F57)'));
      expect(palette, contains('macMinimize = Color(0xFFFEBC2E)'));
      expect(palette, contains('macZoom = Color(0xFF28C840)'));
      expect(palette, contains('macInactive = Color(0xFFC6C6C6)'));
    });

    test('codicon 子集字体：文件在、pubspec 注册了、只用这四个字形', () {
      // 用户 2026-10-09 指定三键 icon 照 vshell（codicon）—— 字体是**子集**，
      // 少一个字形界面上就是豆腐块，所以文件 / 注册 / 码点三样一起守。
      final font = File('assets/fonts/codicon-titlebar.ttf');
      expect(font.existsSync(), isTrue, reason: 'codicon 子集字体必须在库里');
      expect(
        font.lengthSync(),
        lessThan(64 * 1024),
        reason: '只该是四个字形的子集（原字体 147KB）',
      );

      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('- family: codicon'));
      expect(pubspec, contains('assets/fonts/codicon-titlebar.ttf'));
      expect(
        pubspec,
        contains('fontTools.subset'),
        reason: '子集命令与来源（@vscode/codicons，MIT）要留在 pubspec 注释里',
      );

      // 三键图标只许走 codicon，不许退回自绘（旧实现被用户指出与原生不一致）。
      final bar = File('lib/design/window_title_bar.dart').readAsStringSync();
      expect(bar, contains('Codicons.chromeMinimize'));
      expect(bar, contains('Codicons.chromeMaximize'));
      expect(bar, contains('Codicons.chromeRestore'));
      expect(bar, contains('Codicons.chromeClose'));
      expect(bar, contains("fontFamily = 'codicon'"));
    });
  });

  group('整块 chrome 的 Overlay（用户 2026-10-09：「悬浮显示被标题栏边界裁切了」）', () {
    test('Overlay 罩的是「标题栏 + 页面内容」，不是那 40 高的带子', () {
      final src = File('lib/design/window_title_bar.dart').readAsStringSync();
      // Tooltip 是以 overlay entry 的形式画出来的 —— Overlay 只罩带子时它会被
      // Overlay 的边界裁掉（实测就是这么报的）。判据：Overlay 的 initialEntries
      // 里那棵 Column 同时含带子（SizedBox + kWindowTitleBarHeight）与 Expanded(child)。
      final overlayAt = src.indexOf('return Overlay(');
      expect(overlayAt, greaterThan(0), reason: 'AppWindowChrome 必须自带 Overlay（Tooltip 要祖先）');
      final tail = src.substring(overlayAt, overlayAt + 900);
      expect(tail, contains('Expanded(child: child)'),
          reason: '页面内容要在同一个 Overlay 里（否则气泡会被带子的边界裁掉）');
      expect(tail, contains('kWindowTitleBarHeight'),
          reason: '带子高度仍要显式钉死（IntrinsicHeight 会算出天文数字，整窗首帧崩）');
      // 带子自己那层 Overlay 必须**没有了**（否则又变成只罩 40 高）。
      expect(tail.contains('child: Overlay('), isFalse);
    });
  });
}