/// AI 对话页：消息一键复制 + 输入框的「粘贴 / 清空」。
///
/// 用户 2026-09-27 两条：
/// 1. 「我希望 ai 的回答与我的提问可以一键复制」；
/// 2. 「当前 ai 输入框无法删除与粘贴」。
///
/// 独立成文件（而不是塞进 `ai_ui_test.dart`）：本文件要往 Hive 的 `aiChat`
/// box 里**预置一段历史**才能渲染出气泡，跟那边「空对话」的用例共享 box 会互相打架。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:smarter_jxufe/features/ai/data/ai_chat_store.dart';
import 'package:smarter_jxufe/features/ai/data/ai_settings_store.dart';
import 'package:smarter_jxufe/features/ai/domain/ai_config.dart';
import 'package:smarter_jxufe/features/ai/presentation/ai_chat_screen.dart';

const _ready = AiConfig(
  id: 'p1',
  name: '宿舍 DeepSeek',
  presetId: 'deepseek',
  baseUrl: 'https://api.deepseek.com/v1',
  model: 'deepseek-chat',
  apiKey: 'sk-1234567890abcd',
);

Future<AiSettingsStore> _store() async {
  final store = AiSettingsStore(persist: false);
  await store.save(const AiSettings(profiles: [_ready], activeId: 'p1'));
  return store;
}

Widget _app(Widget child, AiSettingsStore store) => ProviderScope(
  overrides: [aiSettingsStoreProvider.overrideWith((ref) => store)],
  child: MaterialApp(home: child),
);

/// 一段历史（一问一答）。`currentAccountProvider` 默认空串 → 键是 `chat|none`。
String _historyJson() => jsonEncode([
  {
    'id': 'u1',
    'role': 'user',
    'content': '今天谁没课',
    'createdAt': '2026-10-15T10:00:00.000',
  },
  {
    'id': 'a1',
    'role': 'assistant',
    'content': '**没有人**没课。',
    'createdAt': '2026-10-15T10:00:01.000',
  },
]);

void main() {
  late Directory tempDir;

  /// 系统剪贴板：widget 测试里没有真平台通道，用 mock 顶住。
  /// `setData` 记下来供断言，`getData` 回 [clipboard]。
  String? clipboard;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('ai_copy_test');
    Hive.init(tempDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(() {
    clipboard = null;
    TestDefaultBinaryMessengerBinding
        .instance
        .defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      switch (call.method) {
        case 'Clipboard.setData':
          clipboard = (call.arguments as Map)['text'] as String?;
          return null;
        case 'Clipboard.getData':
          return clipboard == null ? null : <String, dynamic>{'text': clipboard};
      }
      return null;
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    // ⚠ 必须用 `Hive.box`（已打开的实例）而不是 `Hive.openBox` —— 后者在
    // widget 测试的假时钟下会挂死（真文件 IO 永远等不到）。
    try {
      await Hive.box<String>(aiChatBoxName).delete('chat|none');
    } catch (_) {}
  });

  /// 预置历史 → 进对话页（`aiChatControllerProvider` 建的时候会 `restore()`）。
  ///
  /// ⚠ Hive 的文件 IO 必须包在 `tester.runAsync` 里：`testWidgets` 的假异步时钟
  /// 下真实 IO 永不完成（box 一旦在这里打开，后面 `restore()` 里的 `openBox`
  /// 走的就是内存缓存，几个 microtask 就回来了）。
  Future<void> pumpWithHistory(WidgetTester tester, {String? json}) async {
    final raw = json ?? _historyJson();
    await tester.runAsync(() async {
      final hist = await Hive.openBox<String>(aiChatBoxName);
      await hist.put('chat|none', raw);
    });
    await tester.pumpWidget(_app(const AiChatScreen(), await _store()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
  }

  group('消息一键复制（用户 2026-09-27）', () {
    testWidgets('★ 提问与回答各有一颗复制按钮，点了一字不差地进剪贴板', (tester) async {
      await pumpWithHistory(tester);

      expect(find.text('今天谁没课'), findsOneWidget);
      expect(find.byTooltip('复制提问'), findsOneWidget);
      expect(find.byTooltip('复制回答'), findsOneWidget);

      await tester.tap(find.byTooltip('复制提问'));
      await tester.pumpAndSettle();
      expect(clipboard, '今天谁没课');
      expect(find.text('提问已复制'), findsOneWidget);

      await tester.tap(find.byTooltip('复制回答'));
      await tester.pumpAndSettle();
      // 复制的是**原文 markdown**（粘到别处还能保留结构），不是渲染后的纯文本
      expect(clipboard, '**没有人**没课。');
      expect(find.text('回答已复制'), findsOneWidget);
    });

    testWidgets('多轮对话：每一条都有自己的复制按钮', (tester) async {
      final two = jsonDecode(_historyJson()) as List<dynamic>;
      two.add({
        'id': 'u2',
        'role': 'user',
        'content': '那明天呢',
        'createdAt': '2026-10-15T10:01:00.000',
      });
      two.add({
        'id': 'a2',
        'role': 'assistant',
        'content': '明天也没有。',
        'createdAt': '2026-10-15T10:01:01.000',
      });
      await pumpWithHistory(tester, json: jsonEncode(two));

      expect(find.byTooltip('复制提问'), findsNWidgets(2));
      expect(find.byTooltip('复制回答'), findsNWidgets(2));
    });
  });

  group('输入框：粘贴 / 清空（用户 2026-09-27：「无法删除与粘贴」）', () {
    testWidgets('★ 粘贴按钮把剪贴板内容插到光标处', (tester) async {
      await tester.pumpWidget(_app(const AiChatScreen(), await _store()));
      await tester.pumpAndSettle();

      final field = find.byType(TextField).first;
      await tester.enterText(field, '前面');
      await tester.pumpAndSettle();

      clipboard = '粘进来的';
      await tester.tap(find.byKey(const Key('aiComposerPaste')));
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(field).controller?.text,
        '前面粘进来的',
      );
    });

    testWidgets('剪贴板为空 → 明说「剪贴板里没有文本」，不静默', (tester) async {
      await tester.pumpWidget(_app(const AiChatScreen(), await _store()));
      await tester.pumpAndSettle();

      clipboard = null;
      await tester.tap(find.byKey(const Key('aiComposerPaste')));
      await tester.pumpAndSettle();
      expect(find.text('剪贴板里没有文本'), findsOneWidget);
    });

    testWidgets('★ 清空按钮只在有字时出现，一点就空', (tester) async {
      await tester.pumpWidget(_app(const AiChatScreen(), await _store()));
      await tester.pumpAndSettle();

      // 没字时那颗按钮不存在（别摆一个什么都不做的按钮）
      expect(find.byKey(const Key('aiComposerClear')), findsNothing);

      await tester.enterText(find.byType(TextField).first, '要删掉的字');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('aiComposerClear')), findsOneWidget);

      await tester.tap(find.byKey(const Key('aiComposerClear')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller?.text,
        isEmpty,
      );
      expect(find.byKey(const Key('aiComposerClear')), findsNothing);
    });

    testWidgets('粘贴按钮在未配置时也在（数据源没配好也得能贴问题）', (tester) async {
      final store = AiSettingsStore(persist: false);
      await store.save(AiSettings.empty);
      await tester.pumpWidget(_app(const AiChatScreen(), store));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('aiComposerPaste')), findsOneWidget);
    });
  });
}
