import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/features/ai/data/ai_rule_index.dart';
import 'package:smarter_jxufe/features/ai/tools/ai_tool.dart';
import 'package:smarter_jxufe/features/ai/tools/my_schedule_data.dart';
import 'package:smarter_jxufe/features/ai/tools/score_tools.dart';
import 'package:smarter_jxufe/features/ai/tools/timetable_tools.dart';
import 'package:smarter_jxufe/features/ai/tools/tool_registry.dart';
import 'package:smarter_jxufe/features/ims/public_query/domain/public_query.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/providers/schedule_display_providers.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/providers/schedule_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/class_time.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_entry.dart';
import 'package:smarter_jxufe/features/rules/domain/rule_doc.dart';

const _md = '''
# 江西财经大学普通本科生学籍管理规定

为规范学籍管理，特制定本规定。

## 第一章 入学与注册

新生应当按学校规定的时间报到注册。因故不能按期入学者，应当请假。

### 第一节 保留入学资格

新生可以申请保留入学资格一年。

## 第二章 学籍异动

### 第二节 转专业

学生转专业应当在第一学年结束后提出申请，且必修课程平均分不低于 75 分。

转专业名额一般不超过本专业年级学生数的 10%。

### 第三节 休学与复学

学生休学一般以一年为期。
''';

RulesCatalog _catalog() => RulesCatalog.fromJson({
  'groups': ['学籍成绩', '学科竞赛'],
  'docs': [
    {
      'id': 'r03',
      'file': 'r03.md',
      'pdf': 'r03.pdf',
      'title': '江西财经大学普通本科生学籍管理规定',
      'group': '学籍成绩',
      'template': 'regulation',
      'wenhao': '江财字〔2024〕4号',
      'year': '2024',
    },
    {
      'id': 'r01',
      'file': 'r01.md',
      'pdf': 'r01.pdf',
      'title': '关于学科竞赛的通知',
      'group': '学科竞赛',
      'template': 'regulation',
      'year': '2023',
    },
  ],
});

Future<AiRuleIndex> _index() => loadAiRuleIndex(
  _catalog(),
  loader: (key) async => key.endsWith('r03.md') ? _md : '# 竞赛\n\n竞赛认定由教务处负责。\n',
);

void main() {
  group('splitRuleSections', () {
    test('按标题切节，路径是「章 › 节」', () {
      final sections = splitRuleSections(_md);
      final paths = sections.map((s) => s.path).toList();
      // 文档以 H1 开头 → 没有「前言」节，第 0 节就是 H1 那一节
      expect(paths.first, '江西财经大学普通本科生学籍管理规定');
      // 标题路径是「父 › 子」拼接，所以按后缀匹配
      expect(paths.any((p) => p.endsWith('第一章 入学与注册')), isTrue);
      expect(
        paths.any((p) => p.endsWith('第一章 入学与注册 › 第一节 保留入学资格')),
        isTrue,
      );
      expect(paths.any((p) => p.endsWith('第二章 学籍异动 › 第二节 转专业')), isTrue);
    });

    test('标题之前的正文归到「前言」节（path 为空串）', () {
      final sections = splitRuleSections('开头一段没有标题的话。\n\n# 正文标题\n\n后面的内容。\n');
      expect(sections.first.path, '');
      expect(sections.first.body, contains('开头一段'));
      expect(sections.last.path, '正文标题');
    });

    test('节正文里不留 markdown 装饰', () {
      final sections = splitRuleSections(_md);
      final zhuan = sections.firstWhere((s) => s.path.endsWith('转专业'));
      expect(zhuan.body, contains('不低于 75 分'));
      expect(zhuan.body.contains('##'), isFalse);
      expect(zhuan.body.contains('**'), isFalse);
    });

    test('加粗、行内码、链接被剥掉', () {
      final sections = splitRuleSections(
        '# 标题\n\n**粗体** 与 `代码` 与 [链接](http://x) 与 ![图](http://y)\n',
      );
      final body = sections.last.body;
      expect(body, contains('粗体'));
      expect(body, contains('代码'));
      expect(body, contains('链接'));
      expect(body.contains('http://x'), isFalse);
      expect(body.contains('!['), isFalse);
    });

    test('超长小节按长度再切（带「第 N 段」后缀）', () {
      final long = '# 大表\n\n${'很长的内容。' * 3000}\n';
      final sections = splitRuleSections(long);
      expect(sections.length, greaterThan(1));
      expect(sections.last.path, contains('第'));
      for (final s in sections) {
        expect(s.body.length, lessThanOrEqualTo(5200));
      }
    });

    test('表格分隔行被丢掉', () {
      final sections = splitRuleSections(
        '# T\n\n| 奖项 | 分值 |\n| --- | --- |\n| 一等 | 10 |\n',
      );
      final body = sections.last.body;
      expect(body.contains('---'), isFalse);
      expect(body, contains('一等'));
    });
  });

  group('searchAiRules', () {
    test('命中转专业条文且标题命中权重更高', () async {
      final index = await _index();
      final hits = searchAiRules(index, '转专业');
      expect(hits, isNotEmpty);
      expect(hits.first.section.path, contains('转专业'));
      expect(hits.first.doc.id, 'r03');
    });

    test('多词同时命中加分（平均分 + 转专业）', () async {
      final index = await _index();
      final hits = searchAiRules(index, '转专业 平均分');
      expect(hits.first.section.body, contains('平均分'));
    });

    test('group 过滤生效', () async {
      final index = await _index();
      final hits = searchAiRules(index, '竞赛', group: '学科竞赛');
      expect(hits.every((h) => h.doc.group == '学科竞赛'), isTrue);
    });

    test('查不到时返回空列表而不是乱命中', () async {
      final index = await _index();
      expect(searchAiRules(index, '量子力学'), isEmpty);
    });

    test('单字查询直接放弃（精度太低）', () async {
      final index = await _index();
      expect(searchAiRules(index, '奖'), isEmpty);
    });

    test('limit 生效', () async {
      final index = await _index();
      final hits = searchAiRules(index, '学生', limit: 1);
      expect(hits.length, 1);
    });

    test('byTitle 模糊找文档；byId 精确找', () async {
      final index = await _index();
      expect(index.byId('r03')!.doc.title, contains('学籍管理'));
      expect(index.byTitle('学籍管理')!.doc.id, 'r03');
      expect(index.byTitle('不存在的法规'), isNull);
    });
  });

  group('aiRuleSnippet', () {
    test('围绕关键词截取并带省略号', () {
      final body = '${'前' * 300}关键词${'后' * 300}';
      final snippet = aiRuleSnippet(body, '关键词', radius: 20);
      expect(snippet, contains('关键词'));
      expect(snippet.startsWith('…'), isTrue);
      expect(snippet.endsWith('…'), isTrue);
      expect(snippet.length, lessThan(60));
    });

    test('找不到关键词时给开头（超长则截断）', () {
      expect(aiRuleSnippet('abcdefg', 'zzz', radius: 200), 'abcdefg');
      expect(aiRuleSnippet('abcdefghij', 'zzz', radius: 2), 'abcd…');
    });
  });

  group('工具注册表', () {
    test('名字唯一', () {
      final names = kAllAiTools.map((t) => t.spec.name).toList();
      expect(names.toSet().length, names.length);
    });

    test('每个工具的 schema 都是合法 object', () {
      for (final tool in kAllAiTools) {
        final params = tool.spec.parameters;
        expect(params['type'], 'object', reason: tool.spec.name);
        expect(params['properties'], isA<Map>(), reason: tool.spec.name);
        final required = params['required'];
        if (required != null) {
          final props = params['properties'] as Map;
          for (final key in required as List) {
            expect(
              props.containsKey(key),
              isTrue,
              reason: '${tool.spec.name} 的 required「$key」不在 properties 里',
            );
          }
        }
      }
    });

    test('描述不为空 —— 描述质量直接决定模型选对工具的概率', () {
      for (final tool in kAllAiTools) {
        expect(tool.spec.description.trim().length, greaterThan(12),
            reason: tool.spec.name);
      }
    });

    test('名字全是 snake_case（模型对工具名的常见约定）', () {
      for (final tool in kAllAiTools) {
        expect(RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(tool.spec.name), isTrue,
            reason: tool.spec.name);
      }
    });

    test('aiToolByName 认得全部工具，认不得的返回 null', () {
      for (final tool in kAllAiTools) {
        expect(aiToolByName(tool.spec.name)?.spec.name, tool.spec.name);
      }
      expect(aiToolByName('nope'), isNull);
    });

    test('写操作工具被明确标记（否则闸门形同虚设）', () {
      final mutating = kAllAiTools.where((t) => t.mutating).map((t) => t.spec.name);
      expect(mutating, contains('update_app_setting'));
      // 只读工具不许误标成写操作，否则用户会被无谓地打扰
      expect(mutating, isNot(contains('get_grades')));
      expect(mutating, isNot(contains('find_free_time')));
    });

    test('用户需求里点名的能力都有对应工具', () {
      final names = kAllAiTools.map((t) => t.spec.name).toSet();
      expect(names, contains('get_grades')); // 成绩
      expect(names, contains('search_rules')); // 规章制度
      expect(names, contains('get_my_schedule')); // 课表
      expect(names, contains('find_free_time')); // 「今天蒋剑老师没有课的时间」
      expect(names, contains('get_app_settings')); // 设置
    });
  });

  group('公共查询 kind 解析', () {
    test('英文与中文别名都认', () {
      expect(publicQueryKindOf('teacher'), PublicQueryKind.teacher);
      expect(publicQueryKindOf('教师'), PublicQueryKind.teacher);
      expect(publicQueryKindOf('老师'), PublicQueryKind.teacher);
      expect(publicQueryKindOf('klass'), PublicQueryKind.klass);
      expect(publicQueryKindOf('class'), PublicQueryKind.klass);
      expect(publicQueryKindOf('班级'), PublicQueryKind.klass);
      expect(publicQueryKindOf('classroom'), PublicQueryKind.classroom);
      expect(publicQueryKindOf('课程'), PublicQueryKind.course);
      expect(publicQueryKindOf('瞎写'), isNull);
    });
  });

  group('我的课表：先读缓存、缓存空才联网', () {
    /// 拿到一个真实 `Ref`（`ProviderContainer` 本身不是 `Ref`，但可以借一个
    /// 返回自身的 Provider 把它取出来 —— provider 非 autoDispose，Ref 一直有效）。
    AiToolContext contextWith(ProviderContainer container, {DateTime? now}) =>
        AiToolContext(
          ref: container.read(Provider<Ref>((ref) => ref)),
          gate: const AiDenyWriteGate(),
          now: now ?? DateTime(2026, 10, 15, 14, 30),
        );

    ScheduleEntry entry() => const ScheduleEntry(
      classCode: '001567-056',
      className: '主干+',
      courseCode: '1004600282',
      courseName: '大学英语II',
      totalHours: 64,
      credits: 4,
      studyNature: '初修',
      teacherCode: '1200400772',
      teacherName: '史希平',
      selectionStatus: '选中',
      isCrossMajor: false,
      hasTextbook: true,
      classTimes: [
        ClassTime(
          startWeek: 1,
          endWeek: 16,
          weekParity: WeekParity.every,
          dayOfWeek: DayOfWeek.thursday,
          startPeriod: 1,
          endPeriod: 2,
          classroom: '麦三教3407',
        ),
      ],
    );

    test('缓存命中 → 直接返回且标记 fromCache（不碰教务那条路）', () async {
      final container = ProviderContainer(
        overrides: [
          currentAccountProvider.overrideWith((ref) => '2000000000'),
          scheduleCachedEntriesProvider.overrideWith((ref, arg) async => [entry()]),
        ],
      );
      addTearDown(container.dispose);

      final data = await loadMySchedule(contextWith(container));
      expect(data.error, isNull);
      expect(data.fromCache, isTrue);
      expect(data.entries.length, 1);
      expect(data.entries.first.courseName, '大学英语II');
    });

    test('缓存为空 → 回落教务；教务也拿不到时给的是 error 而不是「你没课」', () async {
      final container = ProviderContainer(
        overrides: [
          currentAccountProvider.overrideWith((ref) => '2000000000'),
          scheduleCachedEntriesProvider.overrideWith((ref, arg) async => const []),
          // 教务那条路是纯在线的，会话不在就抛（真机上抛的正是这一串）。
          scheduleRepositoryProvider.overrideWith(
            (ref) async => throw Exception('获取 JSESSIONID 失败'),
          ),
        ],
      );
      addTearDown(container.dispose);

      final data = await loadMySchedule(contextWith(container));
      // 关键是**不要静默返回空列表** —— 那会让 AI 回答「你今天没课」，
      // 比报错糟得多。
      expect(data.error, contains('课表读取失败'));
      expect(data.entries, isEmpty);
      expect(data.fromCache, isFalse);
    });

    test('没登录账号 → 明确提示先登录，不去打教务', () async {
      final container = ProviderContainer(
        overrides: [
          currentAccountProvider.overrideWith((ref) => ''),
          scheduleCachedEntriesProvider.overrideWith((ref, arg) async => [entry()]),
        ],
      );
      addTearDown(container.dispose);

      final data = await loadMySchedule(contextWith(container));
      expect(data.error, contains('登录'));
      expect(data.entries, isEmpty);
    });

    test('占用槽转换带上课程名（给「找空档」引擎的副标题用）', () async {
      final container = ProviderContainer(
        overrides: [
          currentAccountProvider.overrideWith((ref) => '2000000000'),
          scheduleCachedEntriesProvider.overrideWith((ref, arg) async => [entry()]),
        ],
      );
      addTearDown(container.dispose);

      final slots = await myScheduleSlots(contextWith(container), week: 3);
      expect(slots.error, isNull);
      expect(slots.slots.length, 1);
      final slot = slots.slots.first;
      expect(slot.courseName, '大学英语II');
      expect(slot.weekday, 4); // 周四
      expect(slot.occupies(4, 1, week: 3), isTrue);
      expect(slot.occupies(4, 1, week: 20), isFalse); // 1-16 周之外
    });
  });

  group('学期码文案', () {    test('251 → 2025-2026学年第一学期', () {
      expect(aiSemesterLabel('251'), '2025-2026学年第一学期');
      expect(aiSemesterLabel('261'), '2026-2027学年第一学期');
      expect(aiSemesterLabel('262'), '2026-2027学年第二学期');
    });

    test('认不出时原样返回，不抛', () {
      expect(aiSemesterLabel(''), '未知学期');
      expect(aiSemesterLabel('xx'), 'xx');
    });
  });
}
