import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/ai/data/ai_stream.dart';
import 'package:smarter_jxufe/features/ai/domain/ai_config.dart';
import 'package:smarter_jxufe/features/ai/domain/ai_message.dart';
import 'package:smarter_jxufe/features/ai/tools/ai_tool.dart';

AiConfig _config({bool stream = true}) => AiConfig(
  id: 'c',
  name: 'c',
  presetId: 'deepseek',
  baseUrl: 'https://api.deepseek.com/v1',
  model: 'deepseek-chat',
  apiKey: 'k',
  stream: stream,
);

void main() {
  group('AiSseFramer 分帧', () {
    test('一条 data 行 + 空行 = 一个事件', () {
      final f = AiSseFramer();
      expect(f.feedLine('data: {"a":1}'), isEmpty);
      expect(f.feedLine(''), ['{"a":1}']);
    });

    test('CRLF 也吃', () {
      final f = AiSseFramer();
      f.feedLine('data: hello\r');
      expect(f.feedLine('\r'), ['hello']);
    });

    test('忽略 event: / id: / 注释行', () {
      final f = AiSseFramer();
      expect(f.feedLine('event: message'), isEmpty);
      expect(f.feedLine(': keep-alive'), isEmpty);
      expect(f.feedLine('id: 1'), isEmpty);
      f.feedLine('data: x');
      expect(f.feedLine(''), ['x']);
    });

    test('同一事件多条 data 行按 \\n 连接', () {
      final f = AiSseFramer();
      f.feedLine('data: line1');
      f.feedLine('data: line2');
      expect(f.feedLine(''), ['line1\nline2']);
    });

    test('data: 后一个空格被吃掉，多余空格保留', () {
      final f = AiSseFramer();
      f.feedLine('data:  two-spaces');
      expect(f.feedLine(''), [' two-spaces']);
    });

    test('连续空行不产生空事件', () {
      final f = AiSseFramer();
      expect(f.feedLine(''), isEmpty);
      expect(f.feedLine(''), isEmpty);
    });

    test('flush 交出没有空行收尾的残留', () {
      final f = AiSseFramer();
      f.feedLine('data: tail');
      expect(f.flush(), ['tail']);
      expect(f.flush(), isEmpty);
    });
  });

  group('parseAiStreamData', () {
    test('[DONE] 与空体不产生 chunk', () {
      expect(parseAiStreamData('[DONE]'), isNull);
      expect(parseAiStreamData('   '), isNull);
    });

    test('非 JSON 帧被忽略（心跳）', () {
      expect(parseAiStreamData('ping'), isNull);
    });

    test('正文增量', () {
      final chunk = parseAiStreamData(
        jsonEncode({
          'choices': [
            {
              'delta': {'content': '你'},
            },
          ],
        }),
      );
      expect(chunk!.content, '你');
    });

    test('reasoning_content 与 reasoning 两种字段都认', () {
      final a = parseAiStreamData(
        jsonEncode({
          'choices': [
            {
              'delta': {'reasoning_content': '想'},
            },
          ],
        }),
      );
      final b = parseAiStreamData(
        jsonEncode({
          'choices': [
            {
              'delta': {'reasoning': '想'},
            },
          ],
        }),
      );
      expect(a!.reasoning, '想');
      expect(b!.reasoning, '想');
    });

    test('多模态数组形态的 content 被拼起来', () {
      final chunk = parseAiStreamData(
        jsonEncode({
          'choices': [
            {
              'delta': {
                'content': [
                  {'type': 'text', 'text': '甲'},
                  {'type': 'text', 'text': '乙'},
                ],
              },
            },
          ],
        }),
      );
      expect(chunk!.content, '甲乙');
    });

    test('只有 usage 的收尾帧', () {
      final chunk = parseAiStreamData(
        jsonEncode({
          'choices': [],
          'usage': {'prompt_tokens': 10, 'completion_tokens': 2, 'total_tokens': 12},
        }),
      );
      expect(chunk!.usage!.totalTokens, 12);
      expect(chunk.content, isNull);
    });

    test('非流式形态（message 而非 delta）也能解析', () {
      final chunk = parseAiStreamData(
        jsonEncode({
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'content': '整段回答',
              },
              'finish_reason': 'stop',
            },
          ],
        }),
      );
      expect(chunk!.content, '整段回答');
      expect(chunk.finishReason, 'stop');
    });
  });

  group('工具调用分片累积', () {
    test('arguments 逐片拼接，id/name 只在第一片出现', () {
      final acc = AiStreamAccumulator();
      acc.apply(
        const AiStreamChunk(
          toolCalls: [
            AiToolCallDelta(
              index: 0,
              id: 'call_1',
              name: 'find_free_time',
              arguments: '{"tea',
            ),
          ],
        ),
      );
      acc.apply(
        const AiStreamChunk(
          toolCalls: [AiToolCallDelta(index: 0, arguments: 'chers":["蒋剑"]}')],
        ),
      );
      expect(acc.toolCalls.length, 1);
      expect(acc.toolCalls.first.id, 'call_1');
      expect(acc.toolCalls.first.name, 'find_free_time');
      expect(acc.toolCalls.first.arguments, '{"teachers":["蒋剑"]}');
      expect(acc.toolCalls.first.args['teachers'], ['蒋剑']);
    });

    test('多个调用按 index 排序且互不串台', () {
      final acc = AiStreamAccumulator();
      acc.apply(
        const AiStreamChunk(
          toolCalls: [
            AiToolCallDelta(index: 1, id: 'b', name: 'b', arguments: '{}'),
            AiToolCallDelta(index: 0, id: 'a', name: 'a', arguments: '{}'),
          ],
        ),
      );
      expect(acc.toolCalls.map((c) => c.name).toList(), ['a', 'b']);
    });

    test('缺 id 时兜一个稳定值（端点不接受空 tool_call_id）', () {
      final acc = AiStreamAccumulator();
      acc.apply(
        const AiStreamChunk(
          toolCalls: [AiToolCallDelta(index: 2, name: 'x', arguments: '{}')],
        ),
      );
      expect(acc.toolCalls.first.id, 'call_2');
    });

    test('正文与工具调用可以同时到达', () {
      final acc = AiStreamAccumulator();
      acc.apply(
        const AiStreamChunk(
          content: '我先查一下。',
          toolCalls: [AiToolCallDelta(index: 0, id: 'c', name: 'n', arguments: '{}')],
        ),
      );
      expect(acc.content, '我先查一下。');
      expect(acc.hasToolCalls, isTrue);
    });

    test('toMessage 产出 assistant 消息（带 toolCalls）', () {
      final acc = AiStreamAccumulator();
      acc.apply(const AiStreamChunk(content: '', toolCalls: [AiToolCallDelta(index: 0, id: 'c', name: 'n', arguments: '{}')]));
      final msg = acc.toMessage(id: 'm1', now: DateTime(2026, 10, 15));
      expect(msg.role, AiRole.assistant);
      expect(msg.toolCalls.length, 1);
    });
  });

  group('请求体构造', () {
    test('无工具时不发 tools（不是空数组）', () {
      final body = buildAiRequestBody(
        config: _config(),
        messages: [
          AiChatMessage(
            id: 'u',
            role: AiRole.user,
            content: '你好',
            createdAt: DateTime(2026),
          ),
        ],
      );
      expect(body.containsKey('tools'), isFalse);
      expect(body.containsKey('tool_choice'), isFalse);
      expect(body['stream'], isTrue);
      expect((body['stream_options'] as Map)['include_usage'], isTrue);
    });

    test('有工具时带 tools + tool_choice:auto', () {
      final body = buildAiRequestBody(
        config: _config(),
        messages: const [],
        toolWires: [
          const AiToolSpec(name: 'x', description: 'd').toWire(),
        ],
      );
      expect((body['tools'] as List).length, 1);
      expect(body['tool_choice'], 'auto');
    });

    test('includeStreamOptions=false 时不带该字段', () {
      final body = buildAiRequestBody(
        config: _config(),
        messages: const [],
        includeStreamOptions: false,
      );
      expect(body.containsKey('stream_options'), isFalse);
    });

    test('非流式不带 stream_options', () {
      final body = buildAiRequestBody(
        config: _config(),
        messages: const [],
        streamOverride: false,
      );
      expect(body['stream'], isFalse);
      expect(body.containsKey('stream_options'), isFalse);
    });

    test('assistant 带 tool_calls 时 content 为 null 而不是空串', () {
      final msg = AiChatMessage(
        id: 'a',
        role: AiRole.assistant,
        content: '',
        toolCalls: const [AiToolCall(id: 'c', name: 'n', arguments: '{}')],
        createdAt: DateTime(2026),
      );
      final wire = msg.toWire();
      expect(wire.containsKey('content'), isTrue);
      expect(wire['content'], isNull);
      expect((wire['tool_calls'] as List).length, 1);
    });

    test('tool 消息带 tool_call_id 与 name', () {
      final msg = AiChatMessage(
        id: 't',
        role: AiRole.tool,
        content: '结果',
        toolCallId: 'c1',
        toolName: 'get_grades',
        createdAt: DateTime(2026),
      );
      final wire = msg.toWire();
      expect(wire['tool_call_id'], 'c1');
      expect(wire['name'], 'get_grades');
    });

    test('本地报错消息不进线上数组', () {
      final body = buildAiRequestBody(
        config: _config(),
        messages: [
          AiChatMessage(id: '1', role: AiRole.user, content: 'q', createdAt: DateTime(2026)),
          AiChatMessage(
            id: '2',
            role: AiRole.assistant,
            content: '（已停止）',
            createdAt: DateTime(2026),
            isError: true,
          ),
        ],
      );
      expect((body['messages'] as List).length, 1);
    });
  });

  group('错误文案与降级判定', () {
    test('401/404/429 翻译成人话', () {
      expect(aiExtractError('', 401), contains('API Key'));
      expect(aiExtractError('', 404), contains('/v1'));
      expect(aiExtractError('', 429), contains('限流'));
    });

    test('OpenAI 形态的 error.message 被提取', () {
      final body = jsonEncode({
        'error': {'message': 'Model not found'},
      });
      expect(aiExtractError(body, 404), contains('Model not found'));
    });

    test('HTML 错误页被截断后带上', () {
      final html = '<html>${'x' * 400}</html>';
      final msg = aiExtractError(html, 502);
      expect(msg.length, lessThan(300));
      expect(msg, contains('服务端错误'));
    });

    test('stream_options 被拒可识别', () {
      expect(
        aiIsStreamOptionsRejected('Unrecognized field: stream_options'),
        isTrue,
      );
      expect(aiIsStreamOptionsRejected('invalid request'), isFalse);
    });

    test('tools 不支持要同时出现关键词与否定词', () {
      expect(
        aiLooksLikeToolsUnsupported('This model does not support tools'),
        isTrue,
      );
      expect(
        aiLooksLikeToolsUnsupported('The request is invalid: tools is unsupported'),
        isTrue,
      );
      // 普通 400（上下文超长）不能被误判成不支持工具
      expect(
        aiLooksLikeToolsUnsupported('This model\'s maximum context length is 8192'),
        isFalse,
      );
      expect(aiLooksLikeToolsUnsupported('Missing tool_call_id'), isFalse);
    });

    test('流式不支持可识别', () {
      expect(aiLooksLikeStreamUnsupported('stream is not supported'), isTrue);
      expect(aiLooksLikeStreamUnsupported('invalid api key'), isFalse);
    });
  });

  group('消息 JSON 容错', () {
    test('tool_calls 逐条容错，坏条目丢弃', () {
      final msg = AiChatMessage.fromJson({
        'id': 'm',
        'role': 'assistant',
        'content': 'x',
        'toolCalls': [
          {'id': 'c', 'name': 'ok', 'arguments': '{}'},
          {'id': 'bad'},
        ],
        'createdAt': '2026-10-15T10:00:00.000',
      });
      expect(msg.toolCalls.length, 1);
      expect(msg.toolCalls.first.name, 'ok');
      expect(msg.role, AiRole.assistant);
    });

    test('认不出的 role 回落 user；坏时间戳回落 epoch', () {
      final msg = AiChatMessage.fromJson({'id': 'm', 'role': '???', 'createdAt': 'zzz'});
      expect(msg.role, AiRole.user);
      expect(msg.createdAt.millisecondsSinceEpoch, 0);
    });
  });

  group('AiArgs 参数读取', () {
    test('缺必填记错误', () {
      final a = AiArgs(const {});
      a.str('query');
      expect(a.hasError, isTrue);
      expect(a.errorText, contains('query'));
    });

    test('类型不对记错误而不是抛', () {
      final a = AiArgs(const {'n': 'abc', 'b': 'maybe', 'list': 3});
      expect(a.intOf('n'), 0);
      expect(a.boolOf('b'), isFalse);
      expect(a.strList('list'), isEmpty);
      expect(a.hasError, isTrue);
    });

    test('strList 吃数组、单串、逗号/顿号分隔', () {
      expect(AiArgs(const {'x': ['a', 'b']}).strList('x'), ['a', 'b']);
      expect(AiArgs(const {'x': 'a,b'}).strList('x'), ['a', 'b']);
      expect(AiArgs(const {'x': '蒋剑、张三'}).strList('x'), ['蒋剑', '张三']);
      expect(AiArgs(const {'x': '蒋剑 张三'}).strList('x'), ['蒋剑', '张三']);
    });

    test('intList 吃单值与字符串', () {
      expect(AiArgs(const {'x': 3}).intList('x'), [3]);
      expect(AiArgs(const {'x': '1, 2'}).intList('x'), [1, 2]);
    });

    test('数字字段给数字串也认', () {
      expect(AiArgs(const {'n': '7'}).intOf('n'), 7);
      expect(AiArgs(const {'n': 3.6}).intOf('n'), 4);
    });
  });

  group('AiToolSpec', () {
    test('默认参数是合法 object schema', () {
      final spec = const AiToolSpec(name: 'x', description: 'd');
      final wire = spec.toWire();
      final fn = wire['function'] as Map;
      expect(fn['name'], 'x');
      final params = fn['parameters'] as Map;
      expect(params['type'], 'object');
      expect(params['properties'], isEmpty);
    });

    test('schema 助手产出合法结构', () {
      final schema = aiObjectSchema(
        {
          'a': aiStrProp('说明', enums: ['x', 'y']),
          'b': aiIntProp('数', min: 1, max: 5),
          'c': aiBoolProp('布尔'),
          'd': aiStrListProp('列表'),
          'e': aiIntListProp('整数列表'),
        },
        required: ['a'],
      );
      expect(schema['required'], ['a']);
      final props = schema['properties'] as Map;
      expect((props['a'] as Map)['enum'], ['x', 'y']);
      expect((props['b'] as Map)['minimum'], 1);
      expect((props['b'] as Map)['maximum'], 5);
      expect((props['c'] as Map)['type'], 'boolean');
      expect((props['d'] as Map)['items'], {'type': 'string'});
      expect((props['e'] as Map)['items'], {'type': 'integer'});
    });

    test('带 min/max 为 null 时不写这两个键', () {
      final prop = aiIntProp('数');
      expect(prop.containsKey('minimum'), isFalse);
      expect(prop.containsKey('maximum'), isFalse);
    });
  });

  group('decodeAiJsonLoose', () {
    test('剥掉 ```json 围栏', () {
      final decoded = decodeAiJsonLoose('```json\n{"a":1}\n```');
      expect((decoded as Map)['a'], 1);
    });

    test('普通 JSON 原样解析', () {
      expect((decodeAiJsonLoose('{"a": [1,2]}') as Map)['a'], [1, 2]);
    });

    test('非法 JSON 抛 FormatException（调用方负责兜）', () {
      expect(() => decodeAiJsonLoose('{oops'), throwsFormatException);
    });
  });
}
