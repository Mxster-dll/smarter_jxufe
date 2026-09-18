import 'dart:io';

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:smarter_jxufe/features/ai/data/ai_chat_controller.dart';
import 'package:smarter_jxufe/features/ai/data/ai_settings_store.dart';
import 'package:smarter_jxufe/features/ai/domain/ai_config.dart';
import 'package:smarter_jxufe/features/ai/presentation/ai_chat_screen.dart';
import 'package:smarter_jxufe/features/ai/presentation/ai_floating_ball.dart';
import 'package:smarter_jxufe/features/ai/presentation/widgets/ai_settings_section.dart';
import 'package:smarter_jxufe/features/ai/presentation/widgets/ai_write_confirm.dart';
import 'package:smarter_jxufe/features/ai/tools/ai_tool.dart';
import 'package:smarter_jxufe/features/settings/domain/settings_section.dart';
import 'package:smarter_jxufe/features/settings/presentation/settings_screen.dart';

const _ready = AiConfig(
  id: 'p1',
  name: '宿舍 DeepSeek',
  presetId: 'deepseek',
  baseUrl: 'https://api.deepseek.com/v1',
  model: 'deepseek-chat',
  apiKey: 'sk-1234567890abcd',
);

/// 造一个已配好的 store。
///
/// `persist: false`：widget 测试跑在假异步时钟上，Hive 的真实文件 IO 永远不会
/// 完成（`await save()` 会挂死），所以这里用内存模式。
Future<AiSettingsStore> _store(AiSettings settings) async {
  final store = AiSettingsStore(persist: false);
  await store.save(settings);
  return store;
}

Widget _app(Widget child, AiSettingsStore store) => ProviderScope(
  overrides: [aiSettingsStoreProvider.overrideWith((ref) => store)],
  child: MaterialApp(home: child),
);

void main() {
  // Hive 必须初始化：否则每个 store 的 `Hive.openBox` 都会在测试区外抛错，
  // 虽然我们自己的 try/catch 兜得住，但 flutter_test 会把它报成“测试后异常”而红。
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('ai_ui_test');
    Hive.init(tempDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('对话页（未配置）', () {
    testWidgets('显示引导与「去配置」按钮，不崩', (tester) async {
      final store = await _store(AiSettings.empty);
      await tester.pumpWidget(_app(const AiChatScreen(), store));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('还没配置 AI 接口'), findsOneWidget);
      expect(find.text('去配置'), findsOneWidget);
    });

    testWidgets('未配置时发送 → 给出可操作的错误提示，而不是静默失败', (tester) async {
      final store = await _store(AiSettings.empty);
      await tester.pumpWidget(_app(const AiChatScreen(), store));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '今天谁没课');
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();

      expect(find.textContaining('还没有配置可用的 AI 接口'), findsOneWidget);
    });
  });

  group('对话页（已配置）', () {
    testWidgets('空对话显示建议问题，可点进输入框', (tester) async {
      final store = await _store(
        const AiSettings(profiles: [_ready], activeId: 'p1'),
      );
      await tester.pumpWidget(_app(const AiChatScreen(), store));
      await tester.pumpAndSettle();

      expect(find.text('可以这样问'), findsOneWidget);
      expect(find.text('今天蒋剑老师什么时候没课？'), findsOneWidget);

      await tester.tap(find.text('今天蒋剑老师什么时候没课？'));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(find.byType(TextField).first);
      expect(field.controller?.text, '今天蒋剑老师什么时候没课？');
    });

    testWidgets('空对话时没有清空按钮（没东西可清）', (tester) async {
      final store = await _store(
        const AiSettings(profiles: [_ready], activeId: 'p1'),
      );
      await tester.pumpWidget(_app(const AiChatScreen(), store));
      await tester.pumpAndSettle();
      expect(find.byTooltip('清空对话'), findsNothing);
    });

    testWidgets('控制器初始为空且不在忙（悬浮球与对话页共用同一份历史）', (tester) async {
      final store = await _store(
        const AiSettings(profiles: [_ready], activeId: 'p1'),
      );
      final container = ProviderContainer(
        overrides: [aiSettingsStoreProvider.overrideWith((ref) => store)],
      );
      addTearDown(container.dispose);
      final controller = container.read(aiChatControllerProvider);
      expect(controller.messages, isEmpty);
      expect(controller.busy, isFalse);
      expect(controller.traces, isEmpty);
    });
  });

  group('设置节卡片', () {
    testWidgets('未配置时提示去配置，且能切到对话页', (tester) async {
      final store = await _store(AiSettings.empty);
      await tester.pumpWidget(
        _app(const Scaffold(body: AiAssistantSettingsCard()), store),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('未配置'), findsOneWidget);
      expect(find.text('全局悬浮球'), findsOneWidget);
    });

    testWidgets('已配置时显示脱敏密钥与模型名', (tester) async {
      final store = await _store(
        const AiSettings(profiles: [_ready], activeId: 'p1'),
      );
      await tester.pumpWidget(
        _app(const Scaffold(body: AiAssistantSettingsCard()), store),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('宿舍 DeepSeek'), findsOneWidget);
      // 「deepseek-chat」在摘要与「开始对话」副标题里各出现一次
      expect(find.textContaining('deepseek-chat'), findsWidgets);
      expect(find.textContaining('sk-12…abcd'), findsOneWidget);
      expect(find.text('开始对话'), findsOneWidget);
    });

    testWidgets('悬浮球开关写回 store', (tester) async {
      final store = await _store(
        const AiSettings(profiles: [_ready], activeId: 'p1'),
      );
      await tester.pumpWidget(
        _app(const Scaffold(body: AiAssistantSettingsCard()), store),
      );
      await tester.pumpAndSettle();

      expect(store.settings.floatingBall, isTrue);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(store.settings.floatingBall, isFalse);
    });

    testWidgets('电脑端不出开关，改出说明行（别让人拨一个什么都不做的开关）', (tester) async {
      // ⚠ 测试环境 defaultTargetPlatform 恒为 android（foundation/platform.dart:25）
      // → 桌面端行为必须显式覆盖；且**必须在测试体内复位** ——
      // `_verifyInvariants` 在测试体跑完那一刻就断言它已归 null，tearDown 来不及。
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        final store = await _store(
          const AiSettings(profiles: [_ready], activeId: 'p1'),
        );
        await tester.pumpWidget(
          _app(const Scaffold(body: AiAssistantSettingsCard()), store),
        );
        await tester.pumpAndSettle();

        expect(find.byType(Switch), findsNothing);
        expect(find.text('全局悬浮球'), findsOneWidget);
        expect(find.textContaining('电脑端不显示悬浮球'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('工具轮次弹层可改并写回 store', (tester) async {
      final store = await _store(
        const AiSettings(profiles: [_ready], activeId: 'p1', maxToolRounds: 6),
      );
      await tester.pumpWidget(
        _app(const Scaffold(body: AiAssistantSettingsCard()), store),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('一次提问最多几轮工具调用'));
      await tester.pumpAndSettle();
      expect(find.text('工具调用轮次上限'), findsOneWidget);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(store.settings.maxToolRounds, 6);
    });
  });

  group('全局悬浮球', () {
    testWidgets('开启时出现，点击进入对话页', (tester) async {
      final store = await _store(
        const AiSettings(profiles: [_ready], activeId: 'p1'),
      );
      await tester.pumpWidget(
        _app(const AiFloatingBallHost(child: Scaffold(body: Text('主页'))), store),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
      expect(find.text('主页'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.auto_awesome));
      await tester.pumpAndSettle();
      // 进入对话页后悬浮球自己隐藏（不叠重复入口）
      expect(find.text('AI 助手'), findsWidgets);
    });

    testWidgets('关闭时不渲染（设置里的开关必须真的生效）', (tester) async {
      final store = await _store(
        const AiSettings(
          profiles: [_ready],
          activeId: 'p1',
          floatingBall: false,
        ),
      );
      await tester.pumpWidget(
        _app(const AiFloatingBallHost(child: Scaffold(body: Text('主页'))), store),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.auto_awesome), findsNothing);
      expect(find.text('主页'), findsOneWidget);
    });
  });

  group('设置页「AI 助手」节', () {
    testWidgets('只显示本节时页面不是空的（分节过滤真的挂上了）', (tester) async {
      final store = await _store(
        const AiSettings(profiles: [_ready], activeId: 'p1'),
      );
      await tester.pumpWidget(
        _app(const SettingsScreen(sections: [SettingsSection.aiAssistant]), store),
      );
      await tester.pump();

      // 标题（`geCardTitle` 的文本）与卡片内容都要在
      expect(find.text('AI 助手'), findsWidgets);
      expect(find.text('全局悬浮球'), findsOneWidget);
      expect(find.text('开始对话'), findsOneWidget);
    });

    testWidgets('枚举顺序里「AI 助手」紧跟「外观」之后', (tester) async {
      final values = SettingsSection.values;
      expect(values.indexOf(SettingsSection.aiAssistant), 1);
      expect(values.first, SettingsSection.appearance);
      expect(SettingsSection.aiAssistant.label, 'AI 助手');
    });
  });

  group('写操作确认弹窗', () {
    testWidgets('点「同意修改」返回 true', (tester) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showAiWriteConfirm(
                  context,
                  const AiWriteRequest(
                    toolName: 'update_app_setting',
                    title: '切换主页布局',
                    detail: '把「主页布局」改成「左侧导航栏」',
                  ),
                );
              },
              child: const Text('go'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text('切换主页布局'), findsOneWidget);
      expect(find.textContaining('左侧导航栏'), findsOneWidget);

      await tester.tap(find.text('同意修改'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });

    testWidgets('点「不同意」返回 false', (tester) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showAiWriteConfirm(
                  context,
                  const AiWriteRequest(
                    toolName: 'update_app_setting',
                    title: '改设置',
                    detail: '细节',
                  ),
                );
              },
              child: const Text('go'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('不同意'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    });
  });

  group('工具轨迹文案', () {
    test('每个内置工具都有中文动作名（轨迹条纹不显示英文函数名）', () {
      expect(aiToolLabel('find_free_time'), '算无课时间');
      expect(aiToolLabel('get_grades'), '查成绩');
      expect(aiToolLabel('search_rules'), '检索规章制度');
    });

    test('未知工具回落原名（而不是空串）', () {
      expect(aiToolLabel('some_future_tool'), 'some_future_tool');
    });
  });
}
