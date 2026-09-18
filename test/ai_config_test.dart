import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/ai/domain/ai_config.dart';

void main() {
  group('AiConfig.chatCompletionsUrl', () {
    test('裸域名补 /v1/chat/completions', () {
      const c = AiConfig(
        id: 'a',
        name: 'a',
        presetId: 'custom',
        baseUrl: 'https://api.deepseek.com',
        model: 'm',
      );
      expect(c.chatCompletionsUrl, 'https://api.deepseek.com/v1/chat/completions');
    });

    test('/v1 结尾只补端点', () {
      const c = AiConfig(
        id: 'a',
        name: 'a',
        presetId: 'custom',
        baseUrl: 'https://api.deepseek.com/v1',
        model: 'm',
      );
      expect(c.chatCompletionsUrl, 'https://api.deepseek.com/v1/chat/completions');
    });

    test('已经贴全端点就原样用（不重复拼）', () {
      const c = AiConfig(
        id: 'a',
        name: 'a',
        presetId: 'custom',
        baseUrl: 'https://api.deepseek.com/v1/chat/completions',
        model: 'm',
      );
      expect(c.chatCompletionsUrl, 'https://api.deepseek.com/v1/chat/completions');
    });

    test('尾部斜杠被吃掉', () {
      const c = AiConfig(
        id: 'a',
        name: 'a',
        presetId: 'custom',
        baseUrl: 'https://api.deepseek.com/v1/',
        model: 'm',
      );
      expect(c.chatCompletionsUrl, 'https://api.deepseek.com/v1/chat/completions');
    });

    test('智谱 v4 路径与 compatible-mode 都保留', () {
      const zhipu = AiConfig(
        id: 'a',
        name: 'a',
        presetId: 'zhipu',
        baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
        model: 'glm-4',
      );
      expect(
        zhipu.chatCompletionsUrl,
        'https://open.bigmodel.cn/api/paas/v4/chat/completions',
      );
      const qwen = AiConfig(
        id: 'b',
        name: 'b',
        presetId: 'qwen',
        baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
        model: 'qwen-plus',
      );
      expect(
        qwen.chatCompletionsUrl,
        'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions',
      );
    });

    test('路径里带 /compatible-mode（无 /v1）也补端点', () {
      const c = AiConfig(
        id: 'a',
        name: 'a',
        presetId: 'custom',
        baseUrl: 'https://x.com/compatible-mode',
        model: 'm',
      );
      expect(c.chatCompletionsUrl, 'https://x.com/compatible-mode/chat/completions');
    });

    test('空地址 → 空串（调用方据此报「未配置」）', () {
      const c = AiConfig(
        id: 'a',
        name: 'a',
        presetId: 'custom',
        baseUrl: '',
        model: 'm',
      );
      expect(c.chatCompletionsUrl, '');
      expect(c.modelsUrl, '');
    });

    test('modelsUrl 由端点反推', () {
      const c = AiConfig(
        id: 'a',
        name: 'a',
        presetId: 'custom',
        baseUrl: 'https://api.deepseek.com/v1',
        model: 'm',
      );
      expect(c.modelsUrl, 'https://api.deepseek.com/v1/models');
    });
  });

  group('AiConfig 容错', () {
    test('全部字段缺失 → 默认值，不抛', () {
      final c = AiConfig.fromJson(const {});
      expect(c.model, '');
      expect(c.temperature, kAiDefaultTemperature);
      expect(c.useTools, isTrue);
      expect(c.stream, isTrue);
      expect(c.includeSnapshot, isTrue);
      expect(c.id, 'default');
    });

    test('温度越界被夹取', () {
      expect(
        AiConfig.fromJson(const {'temperature': 99}).temperature,
        kAiMaxTemperature,
      );
      expect(
        AiConfig.fromJson(const {'temperature': -5}).temperature,
        kAiMinTemperature,
      );
      expect(AiConfig.fromJson(const {'temperature': 'x'}).temperature, kAiDefaultTemperature);
    });

    test('布尔吃字符串与数字', () {
      expect(AiConfig.fromJson(const {'useTools': 'false'}).useTools, isFalse);
      expect(AiConfig.fromJson(const {'useTools': 0}).useTools, isFalse);
      expect(AiConfig.fromJson(const {'stream': '1'}).stream, isTrue);
    });

    test('往返不丢字段', () {
      const c = AiConfig(
        id: 'x',
        name: '我的 DeepSeek',
        presetId: 'deepseek',
        baseUrl: 'https://api.deepseek.com/v1',
        model: 'deepseek-chat',
        apiKey: 'sk-abcdefghijklmn',
        temperature: 0.7,
        useTools: false,
        stream: false,
        includeSnapshot: false,
        extraSystemPrompt: '简短点',
      );
      final back = AiConfig.fromJson(c.toJson());
      expect(back.name, c.name);
      expect(back.baseUrl, c.baseUrl);
      expect(back.apiKey, c.apiKey);
      expect(back.temperature, 0.7);
      expect(back.useTools, isFalse);
      expect(back.stream, isFalse);
      expect(back.includeSnapshot, isFalse);
      expect(back.extraSystemPrompt, '简短点');
    });

    test('ready / missingField 指认第一处缺失', () {
      const blank = AiConfig(
        id: 'a',
        name: 'a',
        presetId: 'custom',
        baseUrl: '',
        model: '',
      );
      expect(blank.ready, isFalse);
      expect(blank.missingField, '接口地址');
      expect(
        blank.copyWith(baseUrl: 'https://x.com/v1').missingField,
        '模型名',
      );
      expect(
        blank.copyWith(baseUrl: 'https://x.com/v1', model: 'm').missingField,
        'API Key',
      );
      expect(
        blank.copyWith(baseUrl: 'https://x.com/v1', model: 'm', apiKey: 'k').ready,
        isTrue,
      );
    });
  });

  group('maskAiApiKey', () {
    test('长 key 保留头 5 尾 4', () {
      expect(maskAiApiKey('sk-1234567890abcd'), 'sk-12…abcd');
    });

    test('短 key 全打点（不泄露长度之外的信息）', () {
      expect(maskAiApiKey('short'), '•••••');
    });

    test('空 key → 空串', () {
      expect(maskAiApiKey('   '), '');
    });
  });

  group('预设表', () {
    test('id 唯一，且 defaultModel 取第一个', () {
      final ids = aiPresets.map((p) => p.id).toList();
      expect(ids.toSet().length, ids.length);
      expect(aiPresetOf('deepseek').defaultModel, 'deepseek-chat');
      expect(aiPresetOf('custom').defaultModel, '');
    });

    test('未知 id 回落「自定义」而不是 null', () {
      expect(aiPresetOf('nope').id, 'custom');
      expect(aiPresetOf('').id, 'custom');
    });

    test('内置预设的 baseUrl 一律不带 /chat/completions', () {
      for (final p in aiPresets) {
        expect(p.baseUrl.endsWith('/chat/completions'), isFalse);
      }
    });
  });

  group('AiSettings', () {
    const a = AiConfig(
      id: 'a',
      name: 'A',
      presetId: 'deepseek',
      baseUrl: 'https://a/v1',
      model: 'm1',
      apiKey: 'k',
    );
    const b = AiConfig(
      id: 'b',
      name: 'B',
      presetId: 'qwen',
      baseUrl: 'https://b/v1',
      model: 'm2',
      apiKey: 'k',
    );

    test('空设置没有可用配置', () {
      expect(AiSettings.empty.hasAnyProfile, isFalse);
      expect(AiSettings.empty.active, isNull);
      expect(AiSettings.empty.ready, isFalse);
    });

    test('upsert 新档会把它设为当前生效', () {
      final s = AiSettings.empty.upsertProfile(a);
      expect(s.profiles.length, 1);
      expect(s.activeId, 'a');
      final s2 = s.upsertProfile(b);
      expect(s2.profiles.length, 2);
      expect(s2.active?.id, 'b');
    });

    test('upsert 同 id 是替换而不是追加', () {
      final s = AiSettings.empty
          .upsertProfile(a)
          .upsertProfile(a.copyWith(model: 'm9'));
      expect(s.profiles.length, 1);
      expect(s.active?.model, 'm9');
    });

    test('删掉当前档时落到剩下的第一套', () {
      final s = AiSettings.empty.upsertProfile(a).upsertProfile(b);
      final t = s.removeProfile('b');
      expect(t.profiles.length, 1);
      expect(t.active?.id, 'a');
      final empty = t.removeProfile('a');
      expect(empty.profiles, isEmpty);
      expect(empty.activeId, '');
      expect(empty.active, isNull);
    });

    test('activeId 指不到任何档时回落第一套（而不是 null）', () {
      final s = AiSettings(profiles: const [a, b], activeId: 'zzz');
      expect(s.active?.id, 'a');
    });

    test('activate 只认列表里存在的 id', () {
      final s = AiSettings(profiles: const [a, b], activeId: 'a');
      expect(s.activate('b').activeId, 'b');
      expect(s.activate('nope').activeId, 'a');
    });

    test('fromJson 逐条丢弃坏配置，不整表丢弃', () {
      final s = AiSettings.fromJson({
        'profiles': [
          a.toJson(),
          'not-a-map',
          b.toJson(),
        ],
        'activeId': 'b',
        'floatingBall': 'false',
        'maxToolRounds': 99,
      });
      expect(s.profiles.length, 2);
      expect(s.active?.id, 'b');
      expect(s.floatingBall, isFalse);
      expect(s.maxToolRounds, kAiMaxToolRoundsLimit);
    });

    test('maxToolRounds 被夹在 1..12', () {
      expect(
        AiSettings.fromJson(const {'maxToolRounds': 0}).maxToolRounds,
        kAiMinToolRounds,
      );
      expect(
        AiSettings.fromJson(const {'maxToolRounds': -3}).maxToolRounds,
        kAiMinToolRounds,
      );
    });

    test('往返保持档与开关', () {
      final s = AiSettings(
        profiles: const [a, b],
        activeId: 'b',
        floatingBall: false,
        maxToolRounds: 9,
      );
      final back = AiSettings.fromJson(s.toJson());
      expect(back.profiles.length, 2);
      expect(back.activeId, 'b');
      expect(back.floatingBall, isFalse);
      expect(back.maxToolRounds, 9);
    });
  });
}
