/// 全局悬浮球守卫 —— **必须按 `lib/main.dart` 的真实挂法测**。
///
/// 2026-09-19 用户报：「现在的悬浮球点击后概率无反应，电脑端不显示悬浮球」。
/// 两个真因都只在**真实挂法**下才暴露，所以本文件的宿主一律是
/// `MaterialApp(builder: …)`，而不是 `MaterialApp(home: AiFloatingBallHost(…))`：
///
/// 1. `D:\Program\flutter\packages\flutter\lib\src\widgets\app.dart:1707-1717` ——
///    `routing`（根 `Navigator`）是**以参数塞进 `builder` 返回值内部**的，
///    所以 `builder` 的 context 是根 Navigator 的**祖先**、悬浮球是它的**兄弟**：
///    `Navigator.of(context)` 在那里**找不到任何 Navigator**（祖先链上没有），
///    每次点击都抛 `Navigator operation requested with a context that does not
///    include a Navigator` → 被 `main.dart` 的 `FlutterError.onError` 吞成日志
///    → 用户看到「点了没反应」。修法 = 走全局 `navigatorKey`（`main.dart:90` 已挂）。
/// 2. **鼠标的拖拽 slop 只有 1 逻辑像素**（`kPrecisePointerPanSlop = 1.0`，
///    触屏是 `kPanSlop = 36`）→ 电脑端一次「点击」只要抖了 2px，外层
///    `GestureDetector` 的 pan 就赢下手势竞技场、内层 `InkWell.onTap` **永不触发**
///    → 「概率无反应」。
library;

import 'dart:io';

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:smarter_jxufe/core/navigation/navigator_key.dart';
import 'package:smarter_jxufe/features/ai/data/ai_settings_store.dart';
import 'package:smarter_jxufe/features/ai/domain/ai_config.dart';
import 'package:smarter_jxufe/features/ai/presentation/ai_chat_screen.dart';
import 'package:smarter_jxufe/features/ai/presentation/ai_floating_ball.dart';

const _ready = AiConfig(
  id: 'p1',
  name: '宿舍 DeepSeek',
  presetId: 'deepseek',
  baseUrl: 'https://api.deepseek.com/v1',
  model: 'deepseek-chat',
  apiKey: 'sk-1234567890abcd',
);

Future<AiSettingsStore> _store(AiSettings settings) async {
  // `persist: false`：widget 测试跑在假异步时钟上，Hive 的真实文件 IO 永不完成。
  final store = AiSettingsStore(persist: false);
  await store.save(settings);
  return store;
}

/// 与 `lib/main.dart:89-104` 同构：`navigatorKey` + `builder` 挂宿主。
Widget _app(AiSettingsStore store) => ProviderScope(
  overrides: [aiSettingsStoreProvider.overrideWith((ref) => store)],
  child: MaterialApp(
    navigatorKey: navigatorKey,
    builder: (context, child) =>
        AiFloatingBallHost(child: child ?? const SizedBox.shrink()),
    home: const Scaffold(body: Text('主页')),
  ),
);

/// 一次「带 2px 抖动的鼠标点击」——电脑端最常见的手势。
Future<void> _mouseClickWithJitter(WidgetTester tester, Finder target) async {
  final gesture = await tester.startGesture(
    tester.getCenter(target),
    kind: PointerDeviceKind.mouse,
  );
  await gesture.moveBy(const Offset(2, 0));
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('ai_ball_test');
    Hive.init(tempDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  final ball = find.byIcon(Icons.auto_awesome);

  testWidgets('按 main.dart 的挂法（builder）也能画出悬浮球', (tester) async {
    final store = await _store(
      const AiSettings(profiles: [_ready], activeId: 'p1'),
    );
    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();

    expect(ball, findsOneWidget);
    expect(find.text('主页'), findsOneWidget);
  });

  testWidgets('点击悬浮球真的打开对话页（builder 挂法下 Navigator 仍可达）', (tester) async {
    final store = await _store(
      const AiSettings(profiles: [_ready], activeId: 'p1'),
    );
    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();

    await tester.tap(ball);
    await tester.pumpAndSettle();

    expect(find.byType(AiChatScreen), findsOneWidget);
    // 对话页开着时悬浮球自己隐藏（不叠一个同款入口）。
    expect(ball, findsNothing);
  });

  testWidgets('鼠标点击时的 1~2px 抖动不算拖拽，仍然打开对话页', (tester) async {
    final store = await _store(
      const AiSettings(profiles: [_ready], activeId: 'p1'),
    );
    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();

    await _mouseClickWithJitter(tester, ball);

    expect(find.byType(AiChatScreen), findsOneWidget);
  });

  testWidgets('真的拖拽（越过中线）不打开对话页，且松手后贴边停靠', (tester) async {
    final store = await _store(
      const AiSettings(profiles: [_ready], activeId: 'p1'),
    );
    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();

    final before = tester.getCenter(ball);
    final gesture = await tester.startGesture(
      before,
      kind: PointerDeviceKind.mouse,
    );
    // 初始在右下（800 宽时 x≈764），往左拖过中线才会吸附到左边。
    await gesture.moveBy(const Offset(-500, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.byType(AiChatScreen), findsNothing);
    expect(ball, findsOneWidget);
    expect(tester.getCenter(ball).dx, lessThan(before.dx));
  });

  testWidgets('开关关掉时不渲染（设置里的开关必须真的生效）', (tester) async {
    final store = await _store(
      const AiSettings(
        profiles: [_ready],
        activeId: 'p1',
        floatingBall: false,
      ),
    );
    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();

    expect(ball, findsNothing);
    expect(find.text('主页'), findsOneWidget);
  });

  testWidgets('对话页开着时悬浮球隐藏，关掉后回来', (tester) async {
    final store = await _store(
      const AiSettings(profiles: [_ready], activeId: 'p1'),
    );
    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();

    await tester.tap(ball);
    await tester.pumpAndSettle();
    expect(ball, findsNothing);

    // 返回主页 → 悬浮球必须自己回来。
    //
    // 这条守的是三个真因里最隐蔽的一个：`AiChatScreen.dispose()` 里那次
    // `state--` 若直接改 provider，会被 Riverpod 的「widget 树正在构建」守卫拦下
    // （值改了、监听者收不到）→ 宿主永不重建、球再也回不来。
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('主页'), findsOneWidget);
    expect(ball, findsOneWidget);
  });

  group('电脑端不出悬浮球（用户 2026-09-19 裁定）', () {
    // ⚠ 测试环境下 `defaultTargetPlatform` **恒为 `android`**
    // （`package:flutter/src/foundation/platform.dart:25`）→ 想测桌面端必须用
    // `debugDefaultTargetPlatformOverride` 显式覆盖；这也意味着上面那 6 条
    // 用例测的本来就是「移动端」行为。
    //
    // ⚠ 覆盖**必须在测试体内复位**，不能用 `setUp`/`tearDown`：
    // `TestWidgetsFlutterBinding._verifyInvariants`（`flutter_test/src/binding.dart:1100`）
    // 在**测试体跑完的那一刻**就调 `debugAssertAllFoundationVarsUnset`，tearDown 还没轮到
    // → 报 `The value of a foundation debug variable was changed by the test.`
    Future<void> onDesktop(Future<void> Function() body) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        await body();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }

    testWidgets('Windows 上不渲染悬浮球，但 app 与宿主照常', (tester) async {
      await onDesktop(() async {
        final store = await _store(
          const AiSettings(profiles: [_ready], activeId: 'p1'),
        );
        await tester.pumpWidget(_app(store));
        await tester.pumpAndSettle();

        expect(ball, findsNothing);
        expect(find.text('主页'), findsOneWidget);
        // 宿主还在（只是不画球）—— 别整块摘掉，否则移动端/桌面端要两套树。
        expect(find.byType(AiFloatingBallHost), findsOneWidget);
      });
    });

    testWidgets('桌面端开关开着也不出球（开关只管移动端）', (tester) async {
      await onDesktop(() async {
        final store = await _store(
          const AiSettings(
            profiles: [_ready],
            activeId: 'p1',
            floatingBall: true,
          ),
        );
        await tester.pumpWidget(_app(store));
        await tester.pumpAndSettle();

        expect(ball, findsNothing);
      });
    });

    test('三个桌面平台都算电脑端，移动端不算', () {
      expect(aiDesktopPlatformOn('windows'), isTrue);
      expect(aiDesktopPlatformOn('macos'), isTrue);
      expect(aiDesktopPlatformOn('linux'), isTrue);
      expect(aiDesktopPlatformOn('android'), isFalse);
      expect(aiDesktopPlatformOn('ios'), isFalse);
      expect(aiDesktopPlatformOn('fuchsia'), isFalse);
    });
  });
}
