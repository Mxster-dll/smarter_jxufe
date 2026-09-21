/// 设置页「AI 助手」的**模型名从官网动态获取**（用户 2026-09-22 原话：
/// 「我希望设置页里配置 api 的话，ds 的模型名可以从官网动态获取」）。
///
/// 走真实控件链路：`showAiProfileEditor` → 底部弹层 `_ProfileEditor` →
/// `ref.read(aiClientProvider).testConnection(config)`（= `GET {baseUrl}/models`），
/// 只把 Dio 的**适配器**换成假的（`aiDioProvider` 覆盖），所以：
/// - 请求 URL / Authorization 头是真的（能断言「带没带 Key、打的是不是 /models」）；
/// - 响应体由各用例给，能造出官网新增模型、401、空列表这些真实分支。
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/ai/data/ai_providers.dart';
import 'package:smarter_jxufe/features/ai/domain/ai_config.dart';
import 'package:smarter_jxufe/features/ai/presentation/widgets/ai_settings_section.dart';

/// DeepSeek 官网 `/models` 的真实报文形状（`data[].id`）。
String _modelsBody(List<String> ids) {
  final items = ids.map((id) => '{"id":"$id","object":"model"}').join(',');
  return '{"object":"list","data":[$items]}';
}

/// 假适配器：按 URL 里出现的关键字回不同报文（换供应商时端点会变），
/// 并把每次请求记下来。
class _ModelsAdapter implements HttpClientAdapter {
  _ModelsAdapter({
    this.status = 200,
    this.body = '{"object":"list","data":[]}',
    this.routes = const <String, String>{},
  });

  final int status;
  final String body;

  /// URL 含 key 就用它的报文（用来造「换了供应商，端点与模型名都变了」）。
  final Map<String, String> routes;
  final List<RequestOptions> calls = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add(options);
    final url = options.uri.toString();
    var payload = body;
    for (final entry in routes.entries) {
      if (url.contains(entry.key)) {
        payload = entry.value;
        break;
      }
    }
    return ResponseBody.fromString(
      payload,
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _OpenButton extends ConsumerWidget {
  const _OpenButton({this.existing});

  final AiConfig? existing;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Center(
    child: TextButton(
      onPressed: () => showAiProfileEditor(context, ref, existing),
      child: const Text('打开配置'),
    ),
  );
}

/// 打开配置编辑弹层；[key] 为 null = 新增（没有 Key，不会自动拉官网）。
Future<void> _openEditor(
  WidgetTester tester,
  _ModelsAdapter adapter, {
  String apiKey = 'sk-test',
}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final dio = Dio()..httpClientAdapter = adapter;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [aiDioProvider.overrideWithValue(dio)],
      child: MaterialApp(
        home: Scaffold(
          body: _OpenButton(
            existing: AiConfig.fromPreset(
              aiPresetOf('deepseek'),
              id: 'p1',
            ).copyWith(apiKey: apiKey),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开配置'));
  await tester.pumpAndSettle();
}

/// 等一次真网络（假适配器也是异步返回），再把落地的帧跑完。
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pumpAndSettle();
}

void main() {
  group('设置页：模型名从官网动态获取', () {
    testWidgets('打开已填 Key 的配置 → 自动打 /models，胶囊是官网当天的模型名', (tester) async {
      final adapter = _ModelsAdapter(
        body: _modelsBody([
          'deepseek-chat',
          'deepseek-reasoner',
          'deepseek-v3.2-exp',
        ]),
      );
      await _openEditor(tester, adapter);
      await _settle(tester);

      expect(adapter.calls, hasLength(1));
      expect(adapter.calls.single.uri.toString(),
          'https://api.deepseek.com/v1/models');
      expect(adapter.calls.single.headers['Authorization'], 'Bearer sk-test');

      // 官网有、预设里没有的那个名字必须出现（这就是「动态」的判据）。
      expect(find.byKey(const Key('aiModelOption-deepseek-v3.2-exp')),
          findsOneWidget);
      expect(find.text('以上模型名来自官网（共 3 个）'), findsOneWidget);
      expect(find.textContaining('预设的建议值'), findsNothing);
    });

    testWidgets('点官网胶囊 → 模型名填进输入框；顺手把请求再打一次（手动刷新）', (tester) async {
      final adapter = _ModelsAdapter(
        body: _modelsBody(['deepseek-chat', 'deepseek-v3.2-exp']),
      );
      await _openEditor(tester, adapter);
      await _settle(tester);

      await tester.tap(find.byKey(const Key('aiModelOption-deepseek-v3.2-exp')));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(
        find.ancestor(
          of: find.text('deepseek-v3.2-exp'),
          matching: find.byType(TextField),
        ).first,
      );
      expect(field.controller?.text, 'deepseek-v3.2-exp');

      // 手动再点一次「从官网获取」：不该被「已拉过」挡住。
      await tester.tap(find.byKey(const Key('aiModelFetch')));
      await _settle(tester);
      expect(adapter.calls, hasLength(2));
      expect(find.text('已从官网取到 2 个模型名'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6)); // 排空提示计时器
    });

    testWidgets('拉不到（401）→ 胶囊回落到预设建议值，并说明这是预设', (tester) async {
      final adapter = _ModelsAdapter(
        status: 401,
        body: '{"error":{"message":"Authentication Fails","type":"authentication_error"}}',
      );
      await _openEditor(tester, adapter);
      await _settle(tester);

      expect(find.byKey(const Key('aiModelOption-deepseek-chat')),
          findsOneWidget);
      expect(find.byKey(const Key('aiModelOption-deepseek-reasoner')),
          findsOneWidget);
      expect(find.textContaining('以上是预设的建议值'), findsOneWidget);
      expect(find.textContaining('来自官网'), findsNothing);
    });

    testWidgets('端点没回模型列表也算通：胶囊仍是预设，且不谎称来自官网', (tester) async {
      final adapter = _ModelsAdapter(body: '{"object":"list"}');
      await _openEditor(tester, adapter);
      await _settle(tester);

      expect(find.byKey(const Key('aiModelOption-deepseek-chat')),
          findsOneWidget);
      expect(find.textContaining('来自官网'), findsNothing);
    });

    testWidgets('没填 API Key 就点获取 → 只提示，不发请求', (tester) async {
      final adapter = _ModelsAdapter(body: _modelsBody(['deepseek-chat']));
      await _openEditor(tester, adapter, apiKey: '');
      await _settle(tester);
      expect(adapter.calls, isEmpty); // 没有 Key 时连自动拉都不发

      await tester.tap(find.byKey(const Key('aiModelFetch')));
      await tester.pumpAndSettle();
      expect(adapter.calls, isEmpty);
      expect(find.text('先填接口地址和 API Key'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('「测试连接」也顺手留下模型名（同一个端点，不必点两次）', (tester) async {
      final adapter = _ModelsAdapter(
        body: _modelsBody(['deepseek-chat', 'deepseek-v3.2-exp']),
      );
      await _openEditor(tester, adapter, apiKey: '');
      await _settle(tester);

      // 手动填 Key（新增配置那份流程）
      await tester.enterText(
        find.widgetWithText(TextField, 'API Key'),
        'sk-manual',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('测试连接'));
      await _settle(tester);

      expect(adapter.calls.single.headers['Authorization'], 'Bearer sk-manual');
      expect(find.byKey(const Key('aiModelOption-deepseek-v3.2-exp')),
          findsOneWidget);
      expect(find.textContaining('来自官网'), findsOneWidget);
    });

    testWidgets('换供应商 → 上一家的模型名立刻作废（不会挂在 B 家下面）', (tester) async {
      final adapter = _ModelsAdapter(
        routes: {
          'deepseek.com': _modelsBody(['deepseek-chat', 'deepseek-v3.2-exp']),
          'dashscope': _modelsBody(['qwen-plus', 'qwen3-max']),
        },
      );
      await _openEditor(tester, adapter);
      await _settle(tester);
      expect(find.byKey(const Key('aiModelOption-deepseek-v3.2-exp')),
          findsOneWidget);

      // 切到「通义千问」：端点变了，DeepSeek 那条名字必须消失、换成百炼的。
      await tester.tap(find.text('通义千问'));
      await _settle(tester);
      expect(find.byKey(const Key('aiModelOption-deepseek-v3.2-exp')),
          findsNothing);
      expect(find.byKey(const Key('aiModelOption-qwen3-max')), findsOneWidget);
      expect(adapter.calls.last.uri.toString(),
          contains('dashscope.aliyuncs.com'));
    });
  });
}
